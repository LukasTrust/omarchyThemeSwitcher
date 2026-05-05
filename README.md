# omarchy-theme-switcher

An AUR package providing a TUI and automated scheduler for [Omarchy](https://omarchy.org) theme switching.

## Features

- **Interactive TUI** — browse and apply any installed theme with fuzzy search
- **Day / Night mode** — automatically switch between a day and night theme at configurable times
- **Night Only / Day Only** — apply a dedicated theme at night (or day) and revert when it ends
- **Rotation** — cycle through themes on a daily, weekly, or monthly schedule
- **Random on Login** — apply a random theme each time you log in
- **Geolocation** — use actual sunrise / sunset times instead of fixed HH:MM
- **Pause / Resume** — temporarily suspend automation without losing your config
- **Theme pools** — restrict any mode to a curated set of favourite themes
- **Override respect** — manually switching themes during a period prevents the daemon from clobbering your choice
- **Event-driven timer** — fires only at the next scheduled transition, not every minute

## Installation

### From AUR

```bash
yay -S omarchy-theme-switcher
# or
paru -S omarchy-theme-switcher
```

### Manual / local build

```bash
git clone https://github.com/LukasTrust/omarchyThemeSwitcher
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
| Configure Mode | Set up or edit the active automation mode |
| View Current Settings | Display active config and next scheduled event |
| View Switch Log | Page through or clear the switch history log |
| Notifications: On/Off | Toggle desktop notifications on theme switch |
| Pause automation… | Temporarily suspend automation for 1h / 4h / indefinitely |
| Resume automation | Re-enable automation early |

### CLI flags

```bash
omarchy-theme-switcher --status            # show current config (text)
omarchy-theme-switcher --status --json     # machine-readable JSON
omarchy-theme-switcher --list              # list all available themes
omarchy-theme-switcher --apply THEME       # apply a specific theme now
omarchy-theme-switcher --apply-day         # apply the configured day theme
omarchy-theme-switcher --apply-night       # apply the configured night theme
omarchy-theme-switcher --cycle             # advance one step in the rotation pool
omarchy-theme-switcher --random            # apply a random theme from the pool
omarchy-theme-switcher --set-mode off      # disable automation
omarchy-theme-switcher --pause 4h          # pause for 4 hours (1h / 30m / until-resume)
omarchy-theme-switcher --resume            # resume immediately
omarchy-theme-switcher --force-check       # run daemon logic right now
omarchy-theme-switcher --doctor            # health check (exits non-zero on failures)
omarchy-theme-switcher --purge             # remove all config and state
```

## Modes

### Off

No automation. Use the TUI or `--apply` to switch themes manually.

### Day / Night

Switch between a day theme and a night theme at configurable times:

```
Day theme:   azure    (active 07:00 → 20:00)
Night theme: brutalism (active 20:00 → 07:00)
```

### Night Only

Apply a dedicated night theme at a set time, then automatically revert to whatever theme was active before when morning arrives.

### Day Only

Apply a dedicated day theme during the day, then automatically revert to the previous theme at dusk.

### Rotation

Cycles through themes on a schedule:

- `daily` — new theme every calendar day
- `weekly` — new theme every ISO week
- `monthly` — new theme every month

Themes cycle alphabetically through the pool and wrap around.

### Random on Login

Picks a random theme from the pool each time you log in. Implemented via the Omarchy hook system (`~/.config/omarchy/hooks/login`); no persistent daemon required.

## Geolocation

For Day/Night, Night Only, and Day Only modes you can replace fixed HH:MM times with actual sunrise and sunset for your location.

In the TUI → Configure Mode, choose **Sunrise / sunset (geolocation)** when prompted for schedule type. Enter your latitude/longitude (or let the TUI auto-detect via IP). Choose a twilight type:

| Twilight | Angle | Notes |
|---|---|---|
| civil | 6° | Sun just below horizon — recommended |
| nautical | 12° | Horizon still visible at sea |
| astronomical | 18° | Sky fully dark |
| none | 0° | True sunrise/sunset moment |

If [`sunwait`](https://github.com/risacher/sunwait) is installed, it is used for precise calculations. Otherwise a built-in NOAA algorithm is used (accurate to ±2 minutes). Results are cached per day.

**Optional dependency:** `sunwait`

## Pause / Resume

Pause automation temporarily without changing your mode or losing your schedule:

```bash
omarchy-theme-switcher --pause 4h          # pause for 4 hours
omarchy-theme-switcher --pause until-resume
omarchy-theme-switcher --resume
```

From the TUI, use **Pause automation…** in the main menu. The status line shows remaining pause time. The daemon auto-resumes when the pause expires.

## Override Behavior

By default, if you manually switch to a different theme during a scheduled period, the daemon will **not** overwrite your choice when the next boundary arrives. It waits until the following transition.

Change this under **Configure Mode → Override behavior…** or set `OVERRIDE_BEHAVIOR=force` in the config file to always switch on schedule.

## Configuration

Config is stored at `~/.config/omarchy/theme-switcher.conf`:

```bash
CONFIG_VERSION=2
MODE=day-night

DAY_THEME=azure
NIGHT_THEME=brutalism
DAY_START=07:00
NIGHT_START=20:00

SCHEDULE_TYPE=clock         # clock | geo
LATITUDE=
LONGITUDE=
TWILIGHT=civil              # civil | nautical | astronomical | none

ROTATION_INTERVAL=daily
ROTATION_THEMES=            # empty = all themes (comma-separated otherwise)
ROTATION_LAST_SWITCH=2026-05-04
ROTATION_LAST_THEME=frost

RANDOM_LOGIN_THEMES=        # empty = all themes

OVERRIDE_BEHAVIOR=respect   # respect | force
PAUSED_UNTIL=               # epoch seconds or "indefinite"
NOTIFY=false
```

## Log

Switch history is appended to `~/.local/state/omarchy/theme/switcher.log` (kept to 500 lines).

## Health check

```bash
omarchy-theme-switcher --doctor
```

Prints a checklist of dependencies, timer state, hook installation, and the last 5 log entries. Exits non-zero if any required item fails.

## Shell completion

Tab completion is installed automatically for bash, zsh, and fish:

```bash
omarchy-theme-switcher --<TAB>           # list all flags
omarchy-theme-switcher --apply <TAB>     # list installed themes
omarchy-theme-switcher --set-mode <TAB>  # list modes
```

## Dependencies

- `bash`
- `gum` — TUI primitives (already part of Omarchy)
- `omarchy` — provides `omarchy-theme-set`, `omarchy-theme-list`, `omarchy-theme-current`
- `systemd` — optional, required for timer-based modes
- `sunwait` — optional, for accurate geolocation sunrise/sunset
- `curl` — optional, for IP-based location detection in TUI

## License

MIT
