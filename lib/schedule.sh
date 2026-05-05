#!/usr/bin/env bash
# Scheduling logic: day-night crossover, rotation interval checks, next-event arm

# Convert HH:MM to minutes-since-midnight
time_to_minutes() {
    local t="$1"
    local h m
    h=$(echo "$t" | cut -d: -f1)
    m=$(echo "$t" | cut -d: -f2)
    echo $(( 10#$h * 60 + 10#$m ))
}

# Effective day/night start times — from geo cache if SCHEDULE_TYPE=geo, else config
_effective_times() {
    local day_start night_start
    if [[ "$(config_get SCHEDULE_TYPE clock)" == "geo" ]] && \
       command -v geo_sun_times &>/dev/null; then
        local lat lon twilight
        lat=$(config_get "LATITUDE" "")
        lon=$(config_get "LONGITUDE" "")
        twilight=$(config_get "TWILIGHT" "civil")
        if [[ -n "$lat" && -n "$lon" ]]; then
            read -r day_start night_start < <(geo_sun_times "$lat" "$lon" "$twilight" 2>/dev/null || echo "")
        fi
    fi
    day_start="${day_start:-$(config_get DAY_START '07:00')}"
    night_start="${night_start:-$(config_get NIGHT_START '20:00')}"
    echo "$day_start" "$night_start"
}

# Returns "day" or "night" based on current time and configured boundaries
current_period() {
    local day_start night_start
    read -r day_start night_start < <(_effective_times)

    local now_min day_min night_min
    now_min=$(time_to_minutes "$(date '+%H:%M')")
    day_min=$(time_to_minutes "$day_start")
    night_min=$(time_to_minutes "$night_start")

    if (( day_min < night_min )); then
        if (( now_min >= day_min && now_min < night_min )); then
            echo "day"
        else
            echo "night"
        fi
    else
        # Night wraps midnight (e.g. night=22:00, day=06:00)
        if (( now_min >= night_min || now_min < day_min )); then
            echo "night"
        else
            echo "day"
        fi
    fi
}

# Returns the configured theme for the current period
required_theme_for_period() {
    local period
    period=$(current_period)
    if [[ "$period" == "day" ]]; then
        config_get "DAY_THEME"
    else
        config_get "NIGHT_THEME"
    fi
}

# Checks if rotation is due; returns 0 (true) if a switch is needed
rotation_due() {
    local interval last_switch
    interval=$(config_get "ROTATION_INTERVAL" "daily")
    last_switch=$(config_get "ROTATION_LAST_SWITCH" "")

    if [[ -z "$last_switch" ]]; then
        return 0
    fi

    local today
    today=$(date '+%Y-%m-%d')

    case "$interval" in
        daily)
            [[ "$last_switch" != "$today" ]]
            ;;
        weekly)
            local last_week today_week
            last_week=$(date -d "$last_switch" '+%G-%V' 2>/dev/null || date -j -f '%Y-%m-%d' "$last_switch" '+%G-%V')
            today_week=$(date '+%G-%V')
            [[ "$last_week" != "$today_week" ]]
            ;;
        monthly)
            local last_ym today_ym
            last_ym="${last_switch:0:7}"
            today_ym="${today:0:7}"
            [[ "$last_ym" != "$today_ym" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Given the current theme, return the next one from the pool (cycles)
next_rotation_theme() {
    local last_theme
    last_theme=$(config_get "ROTATION_LAST_THEME" "")

    local pool
    mapfile -t pool < <(theme_pool)

    if [[ ${#pool[@]} -eq 0 ]]; then
        echo ""
        return 1
    fi

    if [[ -z "$last_theme" ]]; then
        echo "${pool[0]}"
        return 0
    fi

    local i
    for i in "${!pool[@]}"; do
        if [[ "${pool[$i]}" == "$last_theme" ]]; then
            local next=$(( (i + 1) % ${#pool[@]} ))
            echo "${pool[$next]}"
            return 0
        fi
    done

    echo "${pool[0]}"
}

# ---------------------------------------------------------------------------
# Event-driven scheduling: compute when the next event should fire (epoch),
# then arm a transient systemd user timer to call the daemon at that time.
# ---------------------------------------------------------------------------

# Return the Unix epoch at which the next scheduled event should fire.
# Outputs nothing and returns 1 if no event is needed (off, random-login, paused).
compute_next_event_epoch() {
    local mode
    mode=$(config_get "MODE" "off")

    local paused_until; paused_until=$(config_get "PAUSED_UNTIL" "")
    if [[ -n "$paused_until" ]]; then
        if [[ "$paused_until" == "indefinite" ]]; then
            return 1
        fi
        local now; now=$(date '+%s')
        if (( now < paused_until )); then
            echo "$paused_until"
            return 0
        fi
    fi

    local now; now=$(date '+%s')

    case "$mode" in
        day-night|night-only|day-only)
            local day_start night_start
            read -r day_start night_start < <(_effective_times)
            local day_min night_min now_min
            now_min=$(time_to_minutes "$(date '+%H:%M')")
            day_min=$(time_to_minutes "$day_start")
            night_min=$(time_to_minutes "$night_start")

            # Compute minutes until each boundary
            local mins_to_day mins_to_night
            mins_to_day=$(( day_min - now_min ))
            (( mins_to_day <= 0 )) && mins_to_day=$(( mins_to_day + 1440 ))
            mins_to_night=$(( night_min - now_min ))
            (( mins_to_night <= 0 )) && mins_to_night=$(( mins_to_night + 1440 ))

            local next_mins
            next_mins=$(( mins_to_day < mins_to_night ? mins_to_day : mins_to_night ))
            echo $(( now + next_mins * 60 ))
            ;;
        rotation)
            # Fire at midnight local time (start of next potential rotation day)
            local midnight
            midnight=$(date -d 'tomorrow 00:01' '+%s' 2>/dev/null || \
                       date -v+1d -v0H -v1M -v0S '+%s')
            echo "$midnight"
            ;;
        off|random-login)
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Arm a transient systemd user timer to call the daemon at the next event.
# Safe to call multiple times — replaces any pre-existing next-event unit.
schedule_arm_next() {
    local epoch
    epoch=$(compute_next_event_epoch) || return 0

    # systemd-run with --on-calendar=@EPOCH schedules a one-shot transient unit.
    # We stop any previous instance first to avoid accumulation.
    systemctl --user stop omarchy-theme-switcher-next.timer 2>/dev/null || true

    systemd-run --user \
        --unit=omarchy-theme-switcher-next \
        --on-calendar="@${epoch}" \
        --timer-property=AccuracySec=10s \
        /usr/bin/omarchy-theme-switcherd 2>/dev/null || \
        log_entry "schedule_arm_next: systemd-run failed, falling back to static timer"
}

# ---------------------------------------------------------------------------
# Human-readable next-event description
# ---------------------------------------------------------------------------

next_switch_description() {
    local mode
    mode=$(config_get "MODE" "off")

    local paused_until; paused_until=$(config_get "PAUSED_UNTIL" "")
    if [[ -n "$paused_until" ]]; then
        if [[ "$paused_until" == "indefinite" ]]; then
            echo "Paused (indefinite)"
            return
        fi
        local now; now=$(date '+%s')
        if (( now < paused_until )); then
            local rem=$(( paused_until - now ))
            printf 'Paused — %dm remaining' $(( rem / 60 ))
            return
        fi
    fi

    local day_start night_start
    read -r day_start night_start < <(_effective_times)

    case "$mode" in
        off)
            echo "Automation is off"
            ;;
        day-night)
            local period; period=$(current_period)
            if [[ "$period" == "day" ]]; then
                echo "Night theme activates at $night_start"
            else
                echo "Day theme activates at $day_start"
            fi
            ;;
        rotation)
            local interval last_switch
            interval=$(config_get "ROTATION_INTERVAL" "daily")
            last_switch=$(config_get "ROTATION_LAST_SWITCH" "never")
            echo "Rotates $interval (last switched: $last_switch)"
            ;;
        random-login)
            echo "Random theme applied on each login"
            ;;
        night-only)
            local period; period=$(current_period)
            if [[ "$period" == "night" ]]; then
                echo "Reverts to saved theme at $day_start"
            else
                echo "Night theme activates at $night_start"
            fi
            ;;
        day-only)
            local period; period=$(current_period)
            if [[ "$period" == "day" ]]; then
                echo "Reverts to saved theme at $night_start"
            else
                echo "Day theme activates at $day_start"
            fi
            ;;
    esac
}
