#!/usr/bin/env bash
# TUI screens built with gum

GUM_HEADER_FOREGROUND="212"
GUM_CHOOSE_HEADER_FOREGROUND="212"
GUM_FILTER_HEADER_FOREGROUND="212"

_header() {
    gum style \
        --border rounded \
        --border-foreground 212 \
        --padding "0 2" \
        --margin "1 0" \
        --bold \
        "  Omarchy Theme Switcher"
}

_status_line() {
    local current mode next
    current=$(omarchy-theme-current 2>/dev/null || echo "unknown")
    mode=$(config_get "MODE" "off")
    next=$(next_switch_description)
    local paused_until
    paused_until=$(config_get "PAUSED_UNTIL" "")
    local now; now=$(date '+%s')
    if [[ -n "$paused_until" && "$paused_until" != "indefinite" && "$now" -lt "$paused_until" ]]; then
        local remaining=$(( paused_until - now ))
        local rem_fmt; rem_fmt=$(printf '%dm' $(( remaining / 60 )))
        (( remaining >= 3600 )) && rem_fmt=$(printf '%dh%dm' $(( remaining / 3600 )) $(( (remaining % 3600) / 60 )))
        gum style --faint "Current: $current  |  Mode: $mode  |  Paused — ${rem_fmt} remaining"
    elif [[ "$paused_until" == "indefinite" ]]; then
        gum style --faint "Current: $current  |  Mode: $mode  |  Paused (indefinite)"
    else
        gum style --faint "Current: $current  |  Mode: $mode  |  $next"
    fi
}

# ---------------------------------------------------------------------------
# Reusable pickers
# ---------------------------------------------------------------------------

# Pick a theme from the installed list.
# Usage: _pick_theme "header text" "current_value"  → prints selected theme
_pick_theme() {
    local header="$1" current="${2:-}"
    local themes
    mapfile -t themes < <(omarchy-theme-list 2>/dev/null)
    if [[ ${#themes[@]} -eq 0 ]]; then
        gum style --foreground 196 "No themes found."
        return 1
    fi
    printf '%s\n' "${themes[@]}" | \
        gum filter \
            --header "$header" \
            --value "$current" \
            --placeholder "Search…" \
            --height 15
}

# Pick a HH:MM time, re-prompting until valid.
# Usage: _pick_time "header text" "current_value"  → prints selected time
_pick_time() {
    local header="$1" current="${2:-}"
    while true; do
        local val
        val=$(gum input --header "$header" --value "$current" --placeholder "HH:MM")
        [[ -z "$val" ]] && return 1
        if validate_hhmm "$val"; then
            echo "$val"
            return 0
        fi
        gum style --foreground 196 "Invalid time \"$val\" — enter HH:MM (e.g. 07:00)"
    done
}

# Pick a theme pool: all themes or a specific subset.
# Usage: _pick_theme_pool "header text" "current_csv"  → prints CSV or ""
_pick_theme_pool() {
    local header="$1" current_csv="${2:-}"
    local use_pool
    use_pool=$(gum choose \
        --header "$header" \
        "All installed themes" \
        "Choose specific themes") || return 1
    if [[ "$use_pool" == "Choose specific themes" ]]; then
        local themes
        mapfile -t themes < <(omarchy-theme-list 2>/dev/null)
        local selected
        selected=$(printf '%s\n' "${themes[@]}" | \
            gum choose \
                --no-limit \
                --header "Select themes (space to toggle, enter to confirm)") || return 1
        tr '\n' ',' <<< "$selected" | sed 's/,$//'
    else
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------

tui_main_menu() {
    _first_run_wizard

    _header >&2
    _status_line >&2
    echo "" >&2

    local notify_label
    notify_label=$(config_get "NOTIFY" "false")
    [[ "$notify_label" == "true" ]] && notify_label="Notifications: On" || notify_label="Notifications: Off"

    local mode paused_until now pause_label
    mode=$(config_get "MODE" "off")
    paused_until=$(config_get "PAUSED_UNTIL" "")
    now=$(date '+%s')
    if [[ "$mode" != "off" ]]; then
        if [[ -n "$paused_until" ]] && \
           { [[ "$paused_until" == "indefinite" ]] || (( now < paused_until )); }; then
            pause_label="Resume automation"
        else
            pause_label="Pause automation…"
        fi
    else
        pause_label=""
    fi

    local items=("Browse & Apply Theme" "Configure Mode" "View Current Settings" "View Switch Log" "$notify_label")
    [[ -n "$pause_label" ]] && items+=("$pause_label")
    items+=("Exit")

    printf '%s\n' "${items[@]}" | gum choose --header "What would you like to do?"
}

# ---------------------------------------------------------------------------
# Browse & apply
# ---------------------------------------------------------------------------

tui_browse_themes() {
    local current
    current=$(omarchy-theme-current 2>/dev/null || echo "unknown")
    local selected
    selected=$(_pick_theme "Select a theme to apply (current: $current)") || return 0
    [[ -z "$selected" ]] && return 0

    gum confirm "Apply theme \"$selected\"?" || return 0

    gum spin --spinner dot --title "Applying $selected…" -- \
        bash -c "apply_theme() { omarchy-theme-set \"\$1\" 2>/dev/null; }; apply_theme '$selected'"
    apply_theme "$selected" "manual"
    gum style --foreground 82 "Theme \"$selected\" applied."
}

# ---------------------------------------------------------------------------
# Configure mode
# ---------------------------------------------------------------------------

tui_configure_mode() {
    local current_mode
    current_mode=$(config_get "MODE" "off")

    local choice
    choice=$(gum choose \
        --header "Select automation mode (current: $current_mode)" \
        "Off — disable all automation" \
        "Day / Night — switch at sunrise and sunset" \
        "Night Only — apply a theme at night, revert at dawn" \
        "Day Only — apply a theme during the day, revert at dusk" \
        "Rotation — cycle themes on a schedule" \
        "Random on Login — random theme each login" \
        "Override behavior…" \
        "Back") || return 0

    case "$choice" in
        "Off"*)               _set_mode_off ;;
        "Day / Night"*)       _configure_day_night ;;
        "Night Only"*)        _configure_night_only ;;
        "Day Only"*)          _configure_day_only ;;
        "Rotation"*)          _configure_rotation ;;
        "Random"*)            _configure_random_login ;;
        "Override behavior"*) _configure_override ;;
    esac
}

_set_mode_off() {
    config_set "MODE" "off"
    config_set "DAEMON_ACTIVE_PERIOD" ""
    _disable_timer
    _remove_login_hook
    gum style --foreground 82 "Automation disabled."
}

# Shared helper: configure the time-based schedule type for day/night modes.
# Sets SCHEDULE_TYPE, LATITUDE, LONGITUDE, TWILIGHT (for geo), or DAY_START/NIGHT_START (for clock).
# Usage: _configure_schedule_type  → returns 0 on success, 1 on cancel
_configure_schedule_type() {
    local stype
    stype=$(gum choose \
        --header "Schedule by…" \
        "Clock (fixed times)" \
        "Sunrise / sunset (geolocation)") || return 1

    if [[ "$stype" == "Sunrise / sunset (geolocation)" ]]; then
        config_set "SCHEDULE_TYPE" "geo"
        _configure_geo_location || return 1
    else
        config_set "SCHEDULE_TYPE" "clock"
    fi
}

_configure_geo_location() {
    local lat lon twilight
    local cur_lat cur_lon
    cur_lat=$(config_get "LATITUDE" "")
    cur_lon=$(config_get "LONGITUDE" "")

    # Offer IP-based seeding if curl is available
    if command -v curl &>/dev/null && [[ -z "$cur_lat" ]]; then
        if gum confirm "Auto-detect location via IP? (makes one web request)"; then
            local json
            json=$(curl -sf --max-time 5 "https://ipapi.co/json" 2>/dev/null || echo "")
            if [[ -n "$json" ]]; then
                cur_lat=$(echo "$json" | grep -o '"latitude":[^,}]*' | cut -d: -f2 | tr -d ' "')
                cur_lon=$(echo "$json" | grep -o '"longitude":[^,}]*' | cut -d: -f2 | tr -d ' "')
                gum style --faint "Detected: ${cur_lat}, ${cur_lon} — confirm below or edit."
            fi
        fi
    fi

    while true; do
        lat=$(gum input --header "Latitude (e.g. 51.5)" --value "$cur_lat" --placeholder "0.0")
        [[ -z "$lat" ]] && return 1
        lon=$(gum input --header "Longitude (e.g. -0.1)" --value "$cur_lon" --placeholder "0.0")
        [[ -z "$lon" ]] && return 1
        if validate_latlon "$lat" "$lon"; then break; fi
        gum style --foreground 196 "Invalid coordinates — latitude ±90, longitude ±180"
    done

    twilight=$(gum choose \
        --header "Twilight type" \
        "civil (recommended)" "nautical" "astronomical" "none (true sunrise/sunset)") || return 1
    twilight="${twilight%% *}"

    config_set "LATITUDE" "$lat"
    config_set "LONGITUDE" "$lon"
    config_set "TWILIGHT" "$twilight"
}

_configure_day_night() {
    local current_mode; current_mode=$(config_get "MODE" "off")
    if [[ "$current_mode" == "day-night" ]]; then
        _edit_day_night && return
        return
    fi
    _setup_day_night
}

_setup_day_night() {
    gum style --bold -- "-- Day / Night Mode --"
    echo ""

    local day_theme night_theme day_start night_start stype

    day_theme=$(_pick_theme "Select DAY theme" "$(config_get DAY_THEME)") || return
    night_theme=$(_pick_theme "Select NIGHT theme" "$(config_get NIGHT_THEME)") || return

    _configure_schedule_type || return
    stype=$(config_get "SCHEDULE_TYPE" "clock")

    if [[ "$stype" == "clock" ]]; then
        day_start=$(_pick_time "Day theme activates at (HH:MM)" "$(config_get DAY_START '07:00')") || return
        night_start=$(_pick_time "Night theme activates at (HH:MM)" "$(config_get NIGHT_START '20:00')") || return
        config_set "DAY_START" "$day_start"
        config_set "NIGHT_START" "$night_start"
    fi

    config_set "MODE" "day-night"
    config_set "DAY_THEME" "$day_theme"
    config_set "NIGHT_THEME" "$night_theme"
    config_set "DAEMON_ACTIVE_PERIOD" ""
    _remove_login_hook
    _enable_timer
    gum style --foreground 82 "Day/Night mode configured. Timer enabled."
}

_configure_night_only() {
    local current_mode; current_mode=$(config_get "MODE" "off")
    if [[ "$current_mode" == "night-only" ]]; then
        _edit_night_only && return
        return
    fi
    _setup_night_only
}

_setup_night_only() {
    gum style --bold -- "-- Night Only Mode --"
    echo ""

    local night_theme night_start day_start stype

    night_theme=$(_pick_theme "Select NIGHT theme" "$(config_get NIGHT_THEME)") || return

    _configure_schedule_type || return
    stype=$(config_get "SCHEDULE_TYPE" "clock")

    if [[ "$stype" == "clock" ]]; then
        night_start=$(_pick_time "Night theme activates at (HH:MM)" "$(config_get NIGHT_START '20:00')") || return
        day_start=$(_pick_time "Revert to previous theme at (HH:MM)" "$(config_get DAY_START '07:00')") || return
        config_set "NIGHT_START" "$night_start"
        config_set "DAY_START" "$day_start"
    fi

    config_set "MODE" "night-only"
    config_set "NIGHT_THEME" "$night_theme"
    config_set "SAVED_THEME" ""
    config_set "DAEMON_ACTIVE_PERIOD" ""
    _remove_login_hook
    _enable_timer
    gum style --foreground 82 "Night-only mode configured. Timer enabled."
}

_configure_day_only() {
    local current_mode; current_mode=$(config_get "MODE" "off")
    if [[ "$current_mode" == "day-only" ]]; then
        _edit_day_only && return
        return
    fi
    _setup_day_only
}

_setup_day_only() {
    gum style --bold -- "-- Day Only Mode --"
    echo ""

    local day_theme day_start night_start stype

    day_theme=$(_pick_theme "Select DAY theme" "$(config_get DAY_THEME)") || return

    _configure_schedule_type || return
    stype=$(config_get "SCHEDULE_TYPE" "clock")

    if [[ "$stype" == "clock" ]]; then
        day_start=$(_pick_time "Day theme activates at (HH:MM)" "$(config_get DAY_START '07:00')") || return
        night_start=$(_pick_time "Revert to previous theme at (HH:MM)" "$(config_get NIGHT_START '20:00')") || return
        config_set "DAY_START" "$day_start"
        config_set "NIGHT_START" "$night_start"
    fi

    config_set "MODE" "day-only"
    config_set "DAY_THEME" "$day_theme"
    config_set "SAVED_THEME" ""
    config_set "DAEMON_ACTIVE_PERIOD" ""
    _remove_login_hook
    _enable_timer
    gum style --foreground 82 "Day-only mode configured. Timer enabled."
}

_configure_rotation() {
    local current_mode; current_mode=$(config_get "MODE" "off")
    if [[ "$current_mode" == "rotation" ]]; then
        _edit_rotation && return
        return
    fi
    _setup_rotation
}

_setup_rotation() {
    gum style --bold -- "-- Rotation Mode --"
    echo ""

    local interval
    interval=$(gum choose --header "Rotate themes how often?" "daily" "weekly" "monthly") || return

    local pool
    pool=$(_pick_theme_pool "Which themes to rotate through?" "$(config_get ROTATION_THEMES)") || return

    config_set "MODE" "rotation"
    config_set "ROTATION_INTERVAL" "$interval"
    config_set "ROTATION_THEMES" "$pool"
    config_set "ROTATION_LAST_SWITCH" ""
    _remove_login_hook
    _enable_timer
    gum style --foreground 82 "Rotation mode configured ($interval). Timer enabled."
}

_configure_random_login() {
    local current_mode; current_mode=$(config_get "MODE" "off")
    if [[ "$current_mode" == "random-login" ]]; then
        _edit_random_login && return
        return
    fi
    _setup_random_login
}

_setup_random_login() {
    gum style --bold -- "-- Random on Login --"
    echo ""

    local pool
    pool=$(_pick_theme_pool "Which themes to pick from?" "$(config_get RANDOM_LOGIN_THEMES)") || return

    config_set "MODE" "random-login"
    config_set "RANDOM_LOGIN_THEMES" "$pool"
    _disable_timer
    _install_login_hook
    gum style --foreground 82 "Random-login mode configured. Login hook installed."
}

_configure_override() {
    local current
    current=$(config_get "OVERRIDE_BEHAVIOR" "respect")
    local choice
    choice=$(gum choose \
        --header "Override behavior (current: $current)" \
        "respect — skip auto-switch if you changed theme manually" \
        "force — always switch on schedule") || return
    local val="${choice%% *}"
    config_set "OVERRIDE_BEHAVIOR" "$val"
    gum style --foreground 82 "Override behavior set to: $val"
    sleep 1
}

# ---------------------------------------------------------------------------
# Per-field edit menus
# ---------------------------------------------------------------------------

_edit_day_night() {
    while true; do
        local day_theme night_theme day_start night_start stype
        day_theme=$(config_get "DAY_THEME")
        night_theme=$(config_get "NIGHT_THEME")
        day_start=$(config_get "DAY_START" "07:00")
        night_start=$(config_get "NIGHT_START" "20:00")
        stype=$(config_get "SCHEDULE_TYPE" "clock")

        local choice
        choice=$(gum choose \
            --header "Edit Day/Night settings" \
            "Day theme         (${day_theme:-unset})" \
            "Night theme        (${night_theme:-unset})" \
            "Schedule type      ($stype)" \
            "Day start          ($day_start)" \
            "Night start        ($night_start)" \
            "Reconfigure from scratch" \
            "Back") || return 0

        case "$choice" in
            "Day theme"*)
                local v; v=$(_pick_theme "Select DAY theme" "$day_theme") && config_set "DAY_THEME" "$v" ;;
            "Night theme"*)
                local v; v=$(_pick_theme "Select NIGHT theme" "$night_theme") && config_set "NIGHT_THEME" "$v" ;;
            "Schedule type"*)
                _configure_schedule_type ;;
            "Day start"*)
                local v; v=$(_pick_time "Day theme activates at" "$day_start") && config_set "DAY_START" "$v" ;;
            "Night start"*)
                local v; v=$(_pick_time "Night theme activates at" "$night_start") && config_set "NIGHT_START" "$v" ;;
            "Reconfigure"*)
                _setup_day_night; return ;;
            "Back") return 0 ;;
        esac
        config_set "DAEMON_ACTIVE_PERIOD" ""
    done
}

_edit_night_only() {
    while true; do
        local night_theme night_start day_start stype
        night_theme=$(config_get "NIGHT_THEME")
        night_start=$(config_get "NIGHT_START" "20:00")
        day_start=$(config_get "DAY_START" "07:00")
        stype=$(config_get "SCHEDULE_TYPE" "clock")

        local choice
        choice=$(gum choose \
            --header "Edit Night-Only settings" \
            "Night theme        (${night_theme:-unset})" \
            "Schedule type      ($stype)" \
            "Night start        ($night_start)" \
            "Revert at          ($day_start)" \
            "Reconfigure from scratch" \
            "Back") || return 0

        case "$choice" in
            "Night theme"*)
                local v; v=$(_pick_theme "Select NIGHT theme" "$night_theme") && config_set "NIGHT_THEME" "$v" ;;
            "Schedule type"*)
                _configure_schedule_type ;;
            "Night start"*)
                local v; v=$(_pick_time "Night theme activates at" "$night_start") && config_set "NIGHT_START" "$v" ;;
            "Revert at"*)
                local v; v=$(_pick_time "Revert to previous theme at" "$day_start") && config_set "DAY_START" "$v" ;;
            "Reconfigure"*)
                _setup_night_only; return ;;
            "Back") return 0 ;;
        esac
        config_set "DAEMON_ACTIVE_PERIOD" ""
    done
}

_edit_day_only() {
    while true; do
        local day_theme day_start night_start stype
        day_theme=$(config_get "DAY_THEME")
        day_start=$(config_get "DAY_START" "07:00")
        night_start=$(config_get "NIGHT_START" "20:00")
        stype=$(config_get "SCHEDULE_TYPE" "clock")

        local choice
        choice=$(gum choose \
            --header "Edit Day-Only settings" \
            "Day theme          (${day_theme:-unset})" \
            "Schedule type      ($stype)" \
            "Day start          ($day_start)" \
            "Revert at          ($night_start)" \
            "Reconfigure from scratch" \
            "Back") || return 0

        case "$choice" in
            "Day theme"*)
                local v; v=$(_pick_theme "Select DAY theme" "$day_theme") && config_set "DAY_THEME" "$v" ;;
            "Schedule type"*)
                _configure_schedule_type ;;
            "Day start"*)
                local v; v=$(_pick_time "Day theme activates at" "$day_start") && config_set "DAY_START" "$v" ;;
            "Revert at"*)
                local v; v=$(_pick_time "Revert to previous theme at" "$night_start") && config_set "NIGHT_START" "$v" ;;
            "Reconfigure"*)
                _setup_day_only; return ;;
            "Back") return 0 ;;
        esac
        config_set "DAEMON_ACTIVE_PERIOD" ""
    done
}

_edit_rotation() {
    while true; do
        local interval pool last_switch
        interval=$(config_get "ROTATION_INTERVAL" "daily")
        pool=$(config_get "ROTATION_THEMES")
        last_switch=$(config_get "ROTATION_LAST_SWITCH" "never")

        local choice
        choice=$(gum choose \
            --header "Edit Rotation settings" \
            "Interval           ($interval)" \
            "Theme pool         (${pool:-all themes})" \
            "Last switched      ($last_switch)" \
            "Reconfigure from scratch" \
            "Back") || return 0

        case "$choice" in
            "Interval"*)
                local v; v=$(gum choose --header "Rotate how often?" "daily" "weekly" "monthly") && config_set "ROTATION_INTERVAL" "$v" ;;
            "Theme pool"*)
                local v; v=$(_pick_theme_pool "Which themes to rotate through?" "$pool") && config_set "ROTATION_THEMES" "$v" ;;
            "Last switched"*)
                config_set "ROTATION_LAST_SWITCH" ""
                gum style --foreground 82 "Reset — rotation will switch on next tick." ; sleep 1 ;;
            "Reconfigure"*)
                _setup_rotation; return ;;
            "Back") return 0 ;;
        esac
    done
}

_edit_random_login() {
    while true; do
        local pool
        pool=$(config_get "RANDOM_LOGIN_THEMES")

        local choice
        choice=$(gum choose \
            --header "Edit Random-Login settings" \
            "Theme pool         (${pool:-all themes})" \
            "Reconfigure from scratch" \
            "Back") || return 0

        case "$choice" in
            "Theme pool"*)
                local v; v=$(_pick_theme_pool "Which themes to pick from?" "$pool") && config_set "RANDOM_LOGIN_THEMES" "$v" ;;
            "Reconfigure"*)
                _setup_random_login; return ;;
            "Back") return 0 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# View / log
# ---------------------------------------------------------------------------

tui_view_settings() {
    local mode current day_theme night_theme day_start night_start
    local interval pool last_switch next_theme next_desc stype

    mode=$(config_get "MODE" "off")
    current=$(omarchy-theme-current 2>/dev/null || echo "unknown")
    next_desc=$(next_switch_description)
    stype=$(config_get "SCHEDULE_TYPE" "clock")

    local output
    output=$(cat <<EOF
  Mode:          $mode
  Current theme: $current
  Next event:    $next_desc

EOF
    )

    case "$mode" in
        day-night)
            day_theme=$(config_get "DAY_THEME")
            night_theme=$(config_get "NIGHT_THEME")
            day_start=$(config_get "DAY_START" "07:00")
            night_start=$(config_get "NIGHT_START" "20:00")
            output+="  Schedule:      $stype
  Day theme:     $day_theme (from $day_start)
  Night theme:   $night_theme (from $night_start)
"
            if [[ "$stype" == "geo" ]]; then
                local lat lon rise set
                lat=$(config_get "LATITUDE")
                lon=$(config_get "LONGITUDE")
                if [[ -n "$lat" && -n "$lon" ]] && command -v geo_sun_times &>/dev/null; then
                    read -r rise set < <(geo_sun_times "$lat" "$lon" "$(config_get TWILIGHT civil)")
                    output+="  Sunrise today: ${rise:-unknown}  |  Sunset: ${set:-unknown}
"
                fi
            fi
            ;;
        night-only)
            night_theme=$(config_get "NIGHT_THEME")
            night_start=$(config_get "NIGHT_START" "20:00")
            day_start=$(config_get "DAY_START" "07:00")
            local saved; saved=$(config_get "SAVED_THEME" "")
            output+="  Schedule:      $stype
  Night theme:   $night_theme (from $night_start)
  Revert at:     $day_start
  Saved theme:   ${saved:-none yet}
"
            ;;
        day-only)
            day_theme=$(config_get "DAY_THEME")
            day_start=$(config_get "DAY_START" "07:00")
            night_start=$(config_get "NIGHT_START" "20:00")
            local saved; saved=$(config_get "SAVED_THEME" "")
            output+="  Schedule:      $stype
  Day theme:     $day_theme (from $day_start)
  Revert at:     $night_start
  Saved theme:   ${saved:-none yet}
"
            ;;
        rotation)
            interval=$(config_get "ROTATION_INTERVAL" "daily")
            pool=$(config_get "ROTATION_THEMES")
            last_switch=$(config_get "ROTATION_LAST_SWITCH" "never")
            next_theme=$(next_rotation_theme 2>/dev/null || echo "")
            output+="  Interval:      $interval
  Last switch:   $last_switch
  Next theme:    ${next_theme:-auto}
  Theme pool:    ${pool:-all themes}
"
            ;;
        random-login)
            pool=$(config_get "RANDOM_LOGIN_THEMES")
            output+="  Theme pool:    ${pool:-all themes}
"
            ;;
    esac

    echo "$output" | gum style --border rounded --border-foreground 212 --padding "1 2"
    echo ""

    local action
    action=$(gum choose --header "" "Edit…" "Back") || return 0
    [[ "$action" == "Edit…" ]] && tui_configure_mode
}

tui_view_log() {
    local log="$SWITCHER_LOG"
    if [[ ! -f "$log" ]] || [[ ! -s "$log" ]]; then
        gum style --faint "No log entries yet."
        sleep 2
        return
    fi

    local action
    action=$(gum choose --header "Switch log" "View log" "Clear log" "Back") || return 0
    case "$action" in
        "View log")  gum pager < "$log" ;;
        "Clear log") tui_clear_log ;;
    esac
}

# ---------------------------------------------------------------------------
# Pause / Resume
# ---------------------------------------------------------------------------

tui_pause_automation() {
    local choice
    choice=$(gum choose \
        --header "Pause automation for how long?" \
        "1 hour" "4 hours" "Until tomorrow morning" "Indefinitely" "Cancel") || return 0

    local now; now=$(date '+%s')
    local until
    case "$choice" in
        "1 hour")                until=$(( now + 3600 )) ;;
        "4 hours")               until=$(( now + 14400 )) ;;
        "Until tomorrow morning")
            local day_start; day_start=$(config_get "DAY_START" "07:00")
            local h m; IFS=: read -r h m <<< "$day_start"
            until=$(date -d "tomorrow $h:$m" '+%s' 2>/dev/null || \
                    date -v+1d -v"${h}H" -v"${m}M" -v0S '+%s')
            ;;
        "Indefinitely") until="indefinite" ;;
        *) return 0 ;;
    esac

    config_set "PAUSED_UNTIL" "$until"
    gum style --foreground 82 "Automation paused."
    sleep 1
}

tui_resume_automation() {
    config_set "PAUSED_UNTIL" ""
    gum style --foreground 82 "Automation resumed."
    sleep 1
}

# ---------------------------------------------------------------------------
# Notifications / log helpers
# ---------------------------------------------------------------------------

tui_toggle_notifications() {
    local current
    current=$(config_get "NOTIFY" "false")
    if [[ "$current" == "true" ]]; then
        config_set "NOTIFY" "false"
        gum style --foreground 82 "Notifications disabled."
    else
        config_set "NOTIFY" "true"
        gum style --foreground 82 "Notifications enabled."
    fi
    sleep 1
}

tui_clear_log() {
    local log="$SWITCHER_LOG"
    if [[ ! -f "$log" ]] || [[ ! -s "$log" ]]; then
        gum style --faint "Log is already empty."
        sleep 1
        return
    fi
    gum confirm "Clear the switch log?" || return 0
    : > "$log"
    gum style --foreground 82 "Log cleared."
    sleep 1
}

# ---------------------------------------------------------------------------
# First-run wizard
# ---------------------------------------------------------------------------

_first_run_wizard() {
    [[ "$(config_get WIZARD_SHOWN false)" == "true" ]] && return
    [[ "$(config_get MODE off)" != "off" ]] && { config_set "WIZARD_SHOWN" "true"; return; }

    config_set "WIZARD_SHOWN" "true"
    gum style \
        --border rounded --border-foreground 212 --padding "0 2" \
        "Welcome to Omarchy Theme Switcher!" \
        "" \
        "It looks like automation isn't configured yet." \
        "Set up a mode to get started."
    echo ""
    gum confirm "Configure automation now?" && tui_configure_mode
}

# ---------------------------------------------------------------------------
# systemd / hook helpers
# ---------------------------------------------------------------------------

_enable_timer() {
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now omarchy-theme-switcher.timer 2>/dev/null || true
}

_disable_timer() {
    systemctl --user disable --now omarchy-theme-switcher.timer 2>/dev/null || true
}

_remove_login_hook() {
    local hook_file="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks/login"
    if [[ -f "$hook_file" ]] && grep -q "omarchy-theme-switcher" "$hook_file"; then
        rm -f "$hook_file"
    fi
}

_install_login_hook() {
    local hook_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks"
    local hook_file="$hook_dir/login"
    mkdir -p "$hook_dir"

    if [[ -f "$hook_file" ]] && grep -q "omarchy-theme-switcher" "$hook_file"; then
        return
    fi

    cat > "$hook_file" <<'HOOK'
#!/usr/bin/env bash
# Managed by omarchy-theme-switcher
if command -v omarchy-theme-switcherd &>/dev/null; then
    omarchy-theme-switcherd --random-login
fi
HOOK
    chmod +x "$hook_file"
}
