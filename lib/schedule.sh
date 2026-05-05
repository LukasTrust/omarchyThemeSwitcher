#!/usr/bin/env bash
# Scheduling logic: day-night crossover and rotation interval checks

# Convert HH:MM to minutes-since-midnight
time_to_minutes() {
    local t="$1"
    local h m
    h=$(echo "$t" | cut -d: -f1)
    m=$(echo "$t" | cut -d: -f2)
    echo $(( 10#$h * 60 + 10#$m ))
}

# Returns "day" or "night" based on current time and configured boundaries
current_period() {
    local day_start night_start
    day_start=$(config_get "DAY_START" "07:00")
    night_start=$(config_get "NIGHT_START" "20:00")

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

# Returns "day" or "night" for the theme that should currently be active
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
        return 0  # never switched
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

    # Last theme not in pool — start from beginning
    echo "${pool[0]}"
}

# Pick a random theme from the random-login pool
random_theme() {
    local pool
    mapfile -t pool < <(random_login_pool)
    if [[ ${#pool[@]} -eq 0 ]]; then
        echo ""
        return 1
    fi
    local idx=$(( RANDOM % ${#pool[@]} ))
    echo "${pool[$idx]}"
}

# Human-readable description of when the next event occurs
next_switch_description() {
    local mode
    mode=$(config_get "MODE" "off")
    case "$mode" in
        off)
            echo "Automation is off"
            ;;
        day-night)
            local period day_start night_start
            period=$(current_period)
            day_start=$(config_get "DAY_START" "07:00")
            night_start=$(config_get "NIGHT_START" "20:00")
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
    esac
}
