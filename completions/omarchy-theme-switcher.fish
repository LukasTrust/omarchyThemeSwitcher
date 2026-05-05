# fish completion for omarchy-theme-switcher

set -l cmd omarchy-theme-switcher

complete -c $cmd -n '__fish_use_subcommand' -l status      -d 'Show current config'
complete -c $cmd -n '__fish_use_subcommand' -l list        -d 'List available themes'
complete -c $cmd -n '__fish_use_subcommand' -l apply       -d 'Apply a theme' -r
complete -c $cmd -n '__fish_use_subcommand' -l apply-day   -d 'Apply the configured day theme'
complete -c $cmd -n '__fish_use_subcommand' -l apply-night -d 'Apply the configured night theme'
complete -c $cmd -n '__fish_use_subcommand' -l cycle       -d 'Apply next rotation theme'
complete -c $cmd -n '__fish_use_subcommand' -l random      -d 'Apply a random theme'
complete -c $cmd -n '__fish_use_subcommand' -l set-mode    -d 'Set automation mode' -r
complete -c $cmd -n '__fish_use_subcommand' -l pause       -d 'Pause automation' -r
complete -c $cmd -n '__fish_use_subcommand' -l resume      -d 'Resume automation'
complete -c $cmd -n '__fish_use_subcommand' -l force-check -d 'Run daemon immediately'
complete -c $cmd -n '__fish_use_subcommand' -l doctor      -d 'Check system health'
complete -c $cmd -n '__fish_use_subcommand' -l purge       -d 'Remove config and state'
complete -c $cmd -n '__fish_use_subcommand' -l help        -d 'Show help'

# Theme completions for --apply
complete -c $cmd -n '__fish_seen_argument -l apply' \
    -a '(omarchy-theme-list 2>/dev/null)'

# Mode completions for --set-mode
complete -c $cmd -n '__fish_seen_argument -l set-mode' \
    -a 'off day-night night-only day-only rotation random-login'

# Duration completions for --pause
complete -c $cmd -n '__fish_seen_argument -l pause' \
    -a '1h 4h 8h 30m until-resume'

# --status flag
complete -c $cmd -n '__fish_seen_argument -l status' -l json -d 'JSON output'
