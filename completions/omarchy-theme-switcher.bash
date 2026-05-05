# bash completion for omarchy-theme-switcher
_omarchy_theme_switcher() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local opts="--status --list --apply --apply-day --apply-night --cycle --random
                --set-mode --pause --resume --force-check --doctor --purge --help"

    case "$prev" in
        --apply)
            local themes
            themes=$(omarchy-theme-list 2>/dev/null)
            COMPREPLY=( $(compgen -W "$themes" -- "$cur") )
            return ;;
        --set-mode)
            COMPREPLY=( $(compgen -W "off day-night night-only day-only rotation random-login" -- "$cur") )
            return ;;
        --pause)
            COMPREPLY=( $(compgen -W "1h 4h 8h 30m until-resume" -- "$cur") )
            return ;;
        --status)
            COMPREPLY=( $(compgen -W "--json" -- "$cur") )
            return ;;
    esac

    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}

complete -F _omarchy_theme_switcher omarchy-theme-switcher
