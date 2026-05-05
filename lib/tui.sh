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
    gum style --faint "Current: $current  |  Mode: $mode  |  $next"
}

tui_main_menu() {
    _header
    _status_line
    echo ""
    local notify_label
    notify_label=$(config_get "NOTIFY" "false")
    [[ "$notify_label" == "true" ]] && notify_label="Notifications: On" || notify_label="Notifications: Off"
    gum choose \
        --header "What would you like to do?" \
        "Browse & Apply Theme" \
        "Configure Mode" \
        "View Current Settings" \
        "View Switch Log" \
        "$notify_label" \
        "Exit"
}

tui_browse_themes() {
    local themes
    mapfile -t themes < <(omarchy-theme-list 2>/dev/null)
    if [[ ${#themes[@]} -eq 0 ]]; then
        gum style --foreground 196 "No themes found. Install themes with omarchy-theme-install."
        return 1
    fi

    local current
    current=$(omarchy-theme-current 2>/dev/null)

    local selected
    selected=$(printf '%s\n' "${themes[@]}" | \
        gum filter \
            --header "Select a theme to apply (current: $current)" \
            --placeholder "Search themes…" \
            --height 20)

    if [[ -z "$selected" ]]; then
        return 0
    fi

    gum confirm "Apply theme \"$selected\"?" || return 0

    gum spin --spinner dot --title "Applying $selected…" -- omarchy-theme-set "$selected"
    gum style --foreground 82 "Theme \"$selected\" applied."
}

tui_configure_mode() {
    local current_mode
    current_mode=$(config_get "MODE" "off")

    local choice
    choice=$(gum choose \
        --header "Select automation mode (current: $current_mode)" \
        "Off — disable all automation" \
        "Day / Night — switch at sunrise and sunset" \
        "Rotation — cycle themes on a schedule" \
        "Random on Login — random theme each login" \
        "Back")

    case "$choice" in
        "Off"*)
            _set_mode_off
            ;;
        "Day"*)
            _configure_day_night
            ;;
        "Rotation"*)
            _configure_rotation
            ;;
        "Random"*)
            _configure_random_login
            ;;
    esac
}

_set_mode_off() {
    config_set "MODE" "off"
    _disable_timer
    _remove_login_hook
    gum style --foreground 82 "Automation disabled."
}

_configure_day_night() {
    local themes
    mapfile -t themes < <(omarchy-theme-list 2>/dev/null)

    gum style --bold "-- Day / Night Mode --"
    echo ""

    local day_theme night_theme day_start night_start

    day_theme=$(printf '%s\n' "${themes[@]}" | \
        gum filter \
            --header "Select DAY theme" \
            --value "$(config_get DAY_THEME)" \
            --placeholder "Search…" \
            --height 15)
    [[ -z "$day_theme" ]] && return

    night_theme=$(printf '%s\n' "${themes[@]}" | \
        gum filter \
            --header "Select NIGHT theme" \
            --value "$(config_get NIGHT_THEME)" \
            --placeholder "Search…" \
            --height 15)
    [[ -z "$night_theme" ]] && return

    day_start=$(gum input \
        --header "Day theme activates at (HH:MM)" \
        --value "$(config_get DAY_START '07:00')" \
        --placeholder "07:00")
    [[ -z "$day_start" ]] && return

    night_start=$(gum input \
        --header "Night theme activates at (HH:MM)" \
        --value "$(config_get NIGHT_START '20:00')" \
        --placeholder "20:00")
    [[ -z "$night_start" ]] && return

    config_set "MODE" "day-night"
    config_set "DAY_THEME" "$day_theme"
    config_set "NIGHT_THEME" "$night_theme"
    config_set "DAY_START" "$day_start"
    config_set "NIGHT_START" "$night_start"
    _remove_login_hook
    _enable_timer
    gum style --foreground 82 "Day/Night mode configured. Timer enabled."
}

_configure_rotation() {
    gum style --bold "-- Rotation Mode --"
    echo ""

    local interval
    interval=$(gum choose \
        --header "Rotate themes how often?" \
        "daily" "weekly" "monthly")
    [[ -z "$interval" ]] && return

    local use_pool
    use_pool=$(gum choose \
        --header "Which themes to rotate through?" \
        "All installed themes" \
        "Choose specific themes")

    local pool=""
    if [[ "$use_pool" == "Choose specific themes" ]]; then
        local themes
        mapfile -t themes < <(omarchy-theme-list 2>/dev/null)
        local selected
        selected=$(printf '%s\n' "${themes[@]}" | \
            gum choose \
                --no-limit \
                --header "Select themes for rotation (space to select, enter to confirm)")
        pool=$(tr '\n' ',' <<< "$selected" | sed 's/,$//')
    fi

    config_set "MODE" "rotation"
    config_set "ROTATION_INTERVAL" "$interval"
    config_set "ROTATION_THEMES" "$pool"
    config_set "ROTATION_LAST_SWITCH" ""
    _remove_login_hook
    _enable_timer
    gum style --foreground 82 "Rotation mode configured ($interval). Timer enabled."
}

_configure_random_login() {
    gum style --bold "-- Random on Login --"
    echo ""

    local use_pool
    use_pool=$(gum choose \
        --header "Which themes to pick from?" \
        "All installed themes" \
        "Choose specific themes")

    local pool=""
    if [[ "$use_pool" == "Choose specific themes" ]]; then
        local themes
        mapfile -t themes < <(omarchy-theme-list 2>/dev/null)
        local selected
        selected=$(printf '%s\n' "${themes[@]}" | \
            gum choose \
                --no-limit \
                --header "Select themes for random pool (space to select, enter to confirm)")
        pool=$(tr '\n' ',' <<< "$selected" | sed 's/,$//')
    fi

    config_set "MODE" "random-login"
    config_set "RANDOM_LOGIN_THEMES" "$pool"
    _disable_timer
    _install_login_hook
    gum style --foreground 82 "Random-login mode configured. Login hook installed."
}

tui_view_settings() {
    local mode current day_theme night_theme day_start night_start
    local interval pool last_switch next_theme next_desc

    mode=$(config_get "MODE" "off")
    current=$(omarchy-theme-current 2>/dev/null || echo "unknown")
    next_desc=$(next_switch_description)

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
            output+="  Day theme:     $day_theme (from $day_start)
  Night theme:   $night_theme (from $night_start)
"
            ;;
        rotation)
            interval=$(config_get "ROTATION_INTERVAL" "daily")
            pool=$(config_get "ROTATION_THEMES")
            last_switch=$(config_get "ROTATION_LAST_SWITCH" "never")
            next_theme=$(next_rotation_theme 2>/dev/null)
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
    gum input --placeholder "Press Enter to go back…" > /dev/null
}

tui_view_log() {
    local log="$SWITCHER_LOG"
    if [[ ! -f "$log" ]] || [[ ! -s "$log" ]]; then
        gum style --faint "No log entries yet."
        sleep 2
        return
    fi
    gum pager < "$log"
}

_enable_timer() {
    systemctl --user daemon-reload 2>/dev/null
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

_install_login_hook() {
    local hook_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks"
    local hook_file="$hook_dir/login"
    mkdir -p "$hook_dir"

    # Only write if not already managed by us
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
