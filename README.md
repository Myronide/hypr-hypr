# Hypr Hypr — our changes

Folder for the state of SyntaxJason ("Hypr Hypr"), merged with Myronide's "Aurora" (the rest of the repo).

## Setup
```sh
sudo ./install.sh         # needs sudo; sets everything up, reloads Hyprland and restarts the shell
sudo ./install.sh --keymap=us   # preset the keyboard layout: de = QWERTZ, us = QWERTY (otherwise the installer asks once)
sudo ./install.sh --no-we # without Wallpaper Engine
```
Then log in to Hyprland again or start the shell with `qs -c draconyx`. Settings: the gear icon in the taskbar (opens the Aurora settings).
The installer detects the monitors itself (`~/.config/hypr/monitors_local.lua`, only if it does not exist yet). Arrange them like on Windows: Aurora settings → Displays (with a 15-second confirmation, so the screen never stays black). Show them: `hyhy-monitors show`.

## Contents
| Folder | What |
|---|---|
| `quickshell/` | Shell in QML: taskbar (each part can be toggled), start menu (selectable icon), Alt+Tab, Task View, desktop (icons can be dragged freely, multiple monitors), Coding Space + Git client, wallpaper picker, zone editor |
| `hypr/` | `hyprland.lua` + `dx_snap` (snap/maximize), `dx_tiling` (tiling, default mode floating/tiling), `dx_zones`; monitors in `monitors_local.lua` |
| `bin/` | `hyhy-*` helper scripts: `hyhy-colors` (shared colour scheme), `hyhy-terminal` (terminal choice), Wallpaper Engine, code list |
| `patches/`, `wallpaper-engine/` | Fixes for linux-wallpaperengine (web wallpapers, mouse position) – `install.sh` builds it |
| `docs/` | Handover with all decisions and pitfalls |
| Repo root | `settings-app`, `preferences.py`, `settings.css`: Aurora settings, restyled, with pages for taskbar, Coding Space, window mode, colours, terminal |

## Merged (cherry-pick)
- **From Aurora:** colour scheme (grey-blue), taskbar look, settings app (restyled and extended), terminal choice.
- **From Hypr Hypr:** zone grid, snap/maximize, Coding Space, Git client, Wallpaper Engine in the taskbar, freely movable desktop icons.
- **Shared settings:** colours (`~/.config/draconyx/colors.json`), terminal (`~/.config/draconyx/terminal`), window mode (`~/.config/draconyx/window-mode`), taskbar (`~/.local/state/draconyx/settings.json`).

## Aurora runs on the shell
When the shell is installed, `desktop-ui`, `start-desktop`, `start-dock` and `background-restore` only hand over to Quickshell: no waybar, no GTK dock. The launcher, Alt+Tab, the window mode and the minimize buttons (via `hyhy-ui-bridge`) go to the shell. Old behaviour: `AURORA_LEGACY_UI=1`.


## Modifier key (when Super is broken or missing)
Aurora settings → Key combinations → **Modifier key** (file `~/.config/draconyx/modifier`):
`super` (default) · `both` (Super and Ctrl+Alt) · `ctrl-alt` (Super off, Ctrl+Alt replaces it) · `caps` (Caps Lock becomes Super).
Ctrl+Space opens the search only on the empty desktop; inside apps the key is left alone.


## New: quick search, rebindable keys, diagnostics
- **Ctrl+Space** opens a search field in the centre of the empty desktop with results below (apps, calculator, settings, files, web); right-click a result: pin to taskbar/start, open the file, show the folder, copy the path. Inside apps the key is left alone.
- **All key combinations** can be rebound in Aurora settings → Key combinations (including mouse combinations such as Alt+left click), saved in `~/.config/draconyx/binds.conf`. The list is built from the loaded Hyprland config (`dx_binds.lua`).
- **`hyhy-doctor`** writes a status report to `~/hyhy-doctor.txt` (running processes, config errors, files, shell log); `hyhy-doctor --fix` stops duplicate starts (waybar, old Aurora dock).


## Taskbar: arrangement
Each part of the taskbar (start, search, apps, tray, clock …) can be placed in Aurora settings → Taskbar → **Arrangement** on *Left*, *Centre* or *Right*; the order is changed with the arrows. In dock style each area becomes its own floating island (empty areas disappear); in bar style there are three areas of one continuous bar.

## Installer
`sudo ./install.sh` (or without sudo: it then asks for the sudo approval first). It repairs owners and permissions, applies only what is new, then reloads Hyprland and restarts the shell. `--ask` asks before packages, `--restart` reloads even without changes.


## Snip tool and photo editor
**Print** (or Ctrl+Alt+Shift+S) freezes all screens, then drag a region. **Accept** (Enter) opens the photo editor: pen, marker, arrow, rectangle, ellipse, text, pixelate, undo (Ctrl+Z), then copy (Ctrl+C), save (Ctrl+S) or both. Ctrl+C / Ctrl+S directly on the selection copy/save without the editor. **Shift+Print** copies and saves the whole screen. Files are saved to `~/Bilder/Screenshots/`.

## Small helpers (1.5)
- **Clipboard** (Ctrl+Alt+V): history with search and image previews. **Keyboard shortcuts** (Ctrl+Alt+I): all active combinations, searchable.
- **Focus time** (Calendar → Focus, Ctrl+Alt+P): Pomodoro, timer, stopwatch; the clock shows the remaining time, Pomodoro switches on "Do not disturb".
- **Quick search**: calculates (including percent, sqrt, sin …), converts units ("5 km in mi"), finds open windows and system actions (lock, standby …).
- **Indicators**: volume/microphone OSD, privacy dot in the bar (microphone, screen sharing), optional CPU/memory in the bar.
- **Drop-down terminal** (Ctrl+Alt+Ö), **mute microphone** (Ctrl+Alt+U), **text from screenshot** (Snip → "Text", Ctrl+T).
- **Aurora**: "Power & lock" (hypridle), "Motion & light" (animations, night light with a schedule).

## Deliberately NOT included
- Aurora's plugins (hyprbars, `aurora-native`): they got in the way in a test and crashed Hyprland when loaded into a running session. Do not load them via live reload. Anyone who uses them loads them only at login.
