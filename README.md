# omarchy-theme-switcher

An AUR package providing a TUI and automated scheduler for [Omarchy](https://omarchy.org) theme switching.

## Features

- **Interactive TUI** — browse and apply any installed theme with fuzzy search
- **Day / Night mode** — automatically switch between a day and night theme at configurable times
- **Rotation** — cycle through themes on a daily, weekly, or monthly schedule
- **Random on Login** — apply a random theme each time you log in
- **Theme pools** — restrict any mode to a curated set of favourite themes

## Installation

### From AUR

```bash
yay -S omarchy-theme-switcher
# or
paru -S omarchy-theme-switcher
```

### Manual / local build

```bash
git clone https://github.com/lukas/omarchyThemeSwitcher
cd omarchyThemeSwitcher
makepkg -si
```

After installation:

```bash
systemctl --user daemon-reload
omarchy-theme-switcher   # opens the TUI
```

## Usage

### TUI (interactive)

```bash
omarchy-theme-switcher
```

Main menu options:

| Option | Description |
|---|---|
| Browse & Apply Theme | Fuzzy-search all installed themes and apply one |
| Configure Mode | Set up Day/Night, Rotation, or Random-login |
| View Current Settings | Display active config and next scheduled event |
| View Switch Log | Page through the switch history log |

### CLI flags

```bash
omarchy-theme-switcher --status          # show current config
omarchy-theme-switcher --set-mode off    # disable automation
omarchy-theme-switcher --force-check     # run daemon logic right now
```

## Modes

### Off

No automation. Use the TUI to manually apply themes whenever you like.

### Day / Night

Set a *day theme*, a *night theme*, and the times they activate:

```
Day theme:   azure    (active 07:00 → 20:00)
Night theme: brutalism (active 20:00 → 07:00)
```

A systemd user timer fires every minute and switches the theme if needed.

### Rotation

Cycles through themes on a schedule:

- `daily` — new theme every calendar day
- `weekly` — new theme every ISO week
- `monthly` — new theme every month

Themes cycle alphabetically through the pool and wrap around. The systemd timer handles the check.

### Random on Login

Picks a random theme from the pool each time you log in. Implemented via the Omarchy hook system (`~/.config/omarchy/hooks/login`); no persistent daemon required.

## Configuration

Config is stored at `~/.config/omarchy/theme-switcher.conf`:

```bash
MODE=day-night

DAY_THEME=azure
NIGHT_THEME=brutalism
DAY_START=07:00
NIGHT_START=20:00

ROTATION_INTERVAL=daily
ROTATION_THEMES=azure,frost,one-dark-pro   # empty = all themes
ROTATION_LAST_SWITCH=2026-05-04
ROTATION_LAST_THEME=frost

RANDOM_LOGIN_THEMES=   # empty = all themes
```

## Log

Switch history is appended to `~/.local/state/omarchy/theme/switcher.log`.

## Dependencies

- `bash`
- `gum` — TUI primitives (already part of Omarchy)
- `omarchy` — provides `omarchy-theme-set`, `omarchy-theme-list`, `omarchy-theme-current`
- `systemd` — optional, required for timer-based modes

## License

MIT
