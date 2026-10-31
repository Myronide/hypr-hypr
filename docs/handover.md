# Hypr Hypr Desktop on Hyprland – Handover (as of 25.10.2026)

User goal: a **Windows 11-like, but more modern and "cooler" desktop** on Hyprland in the **Hypr Hypr look** (Hypr Hypr = the user's own brand, dragon logo). Lots of features, tidy, gaming-capable, HDR must stay. Please keep developing the concept in this spirit.

---

## System

- Garuda Linux (Arch-based), kernel 7.3.0-4-garuda, AMD RX 7700 XT/7800 XT (amdgpu)
- **Hyprland 0.56.2 with Lua config** (`~/.config/hypr/hyprland.lua`, hyprlang is deprecated since 0.55)
- Quickshell 0.3.2, Ghostty 1.3.1, Waybar 0.15 (fallback only), pcmanfm-qt 2.4.1, nwg-drawer 0.7.5 (fallback)
- Plasma (KDE) and COSMIC are still installed and selectable on the login screen (fallback)
- German keyboard, fish as shell

### Monitors

The displays are stored per machine in `~/.config/hypr/monitors_local.lua` (not in the repo). The installer detects them itself; arrange them, change resolution and scaling: Aurora settings → Displays. The HDR lines (`cm`, `bitdepth`, `sdrbrightness`, `vrr`) are kept when saving.

| Output | Monitor | Mode | Position | Settings |
|---|---|---|---|---|
| DP-1 | Acer VG270U E | 2560x1440@59.95 | 0x0 | `cm="hdr"`, 10 bit, `sdrbrightness=3.75` (≈300 nits) |
| DP-2 | Acer XV271U M3 (main monitor, gaming) | 2560x1440@179.88 | 2560x0 | `cm="hdr"`, 10 bit, `sdrbrightness=2.5` (≈200 nits), VRR on |
| HDMI-A-2 | 236 FHD | 1920x1080@60 | 5120x0 | no (sRGB) |

SDR brightness under HDR = 80 nits × `sdrbrightness`. The Acers are set to 100 % via DDC and cannot be adjusted via DDC in HDR mode.

---

## Design "Hypr Hypr Dark"

- **Main accent violet `#8b5cf6`** (light `#a78bfa`, deep `#5b3fd0`)
- **Secondary accent green `#6ee05c`**, used sparingly (dragon eyes): window border gradient violet→green, "today" in the calendar, password OK on the lock screen
- Backgrounds almost black with a blue/violet tint (`#07060d`, panels `rgba(10,9,17,0.8–0.94)`), text `#ece9f7`, dimmed `#9a95b8`
- Fonts: Inter (UI), JetBrainsMono Nerd Font (terminal)
- Glass look: Hyprland blur on layers `^draconyx-.*`, corner radius 10 (windows) to 22 (popups)
- Icons: **Fluent (Iconify)** as SVG, each in text colour and violet (`name.svg` / `name-a.svg`) in `~/.local/share/draconyx-hypr/qs-icons/` (42 icons). The Iconify API throttles quickly (HTTP 429): the fallback is the npm package `@iconify-json/fluent` (icons.json via jsDelivr), building the SVGs from it.
- Logo: `~/Bilder/draconyx-logo.png` (black dragon, green eyes, transparent). Invisible on a dark UI, so there is a light silver-lavender variant with a violet glow: `~/.local/share/draconyx-hypr/logo-start.png` (start button), `logo-lock.png` (lock screen), `logo-light.png`
- Wallpaper: `~/Bilder/Wallpapers/draconyx-dark.png` (4K, black with a violet glow on the right, dragon as a subtle watermark, green hint at the bottom). Style based on an AI mockup of the user's (`~/Bilder/20aab2f1-ba86-4293-80c0-310edee4109d.png`). The user only wants to take **the mood from it, not copy the layout**.

---

## Components

| Function | Program | Config |
|---|---|---|
| Taskbar, start menu, quick settings, calendar, Alt+Tab | **Quickshell "Hypr Hypr Shell"** | `~/.config/quickshell/draconyx/` |
| Desktop icons + wallpaper | `pcmanfm-qt --desktop` (no longer used, see below) | `~/.config/pcmanfm-qt/default/settings.conf` |
| Notifications | swaync | `~/.config/swaync/style.css` |
| Lock screen / idle | hyprlock / hypridle | `~/.config/hypr/hyprlock.conf`, `hypridle.conf` |
| Launcher "Run" (Super+R), clipboard | fuzzel, cliphist | `~/.config/fuzzel/fuzzel.ini` |
| Terminal | Ghostty (Kitty as fallback) | `~/.config/ghostty/config`, `~/.config/kitty/kitty.conf` |
| File manager | **Dolphin** (default for folders via xdg-mime) | – |
| Qt/KDE app theme | `QT_QPA_PLATFORMTHEME=kde` (reads the KDE colour scheme, dark) | – |
| Fallback taskbar / start menu | Waybar / nwg-drawer | `~/.config/waybar/`, `~/.config/nwg-drawer/drawer.css`, `~/.config/hypr/scripts/start-menu.sh` |

Autostart in `hyprland.lua` (`hl.on("hyprland.start", ...)`): polkit agent, pcmanfm-qt --desktop, **Hypr Hypr Shell** (`QS_ICON_THEME=Papirus-Dark qs -c draconyx`, fallback Waybar), swaync, hypridle, nm-applet, blueman-applet, cliphist, EasyEffects, JamesDSP, JetBrains Toolbox.

---

## Hypr Hypr Shell (Quickshell, ~1700 lines of QML)

Files in `~/.config/quickshell/draconyx/`:

- `shell.qml`: entry point; one bar per monitor (`Variants`), popups, IPC handlers `shell` and `switcher`
- `Theme.qml` (singleton): colours, sizes, paths, `icon(name, accent)`
- `Global.qml` (singleton): popup state, **`settings.json`** (FileView + JsonAdapter: `pinned`, `startPins`, `autohide`), switches (night light, game mode, DND), swaync subscription (counter/DND), nmcli network status, helpers (`normId`, `entryFor`, `iconFor`, `launch`, **`focusToplevel`/`focusHypr`** = focus via Hyprland dispatch)
- `Bar.qml`: taskbar, three floating pills
  - left: desktops of the monitor (desktop 10 = "Game" with controller icon)
  - centre: dragon start button, search, **apps grouped per app ID** (pinned first)
  - right: tray, network + volume (→ quick settings, mouse wheel = volume), bell with counter (left click opens the swaync panel, right click DND), clock (→ calendar), strip "show desktop"
  - **Auto-hide:** slides away after 900 ms without the mouse; a 3 px hover strip at the bottom edge brings it back; can be switched off
  - **Completely hidden when a window is fullscreen on the monitor** (`HyprlandWorkspace.hasFullscreen`)
- `TaskButton.qml`: app button; line at the bottom = running / wider = several windows / violet = active; click = focus or window list; middle click = new window; right-click menu (new window, pin/unpin, close all)
- `StartMenu.qml`: search (arrows + Enter), pinned apps (grid), "All apps", footer with user + lock/log out/standby/restart/power off (log out, restart and power off need a confirmation click)
- `ControlCenter.qml`: tiles (do not disturb, night light via hyprsunset, game mode = animations/blur/shadows off via `hyprctl eval`, hide bar, Bluetooth, network), volume + microphone sliders (PipeWire), media card (MPRIS with cover), tools (screenshot, colour picker, clipboard, nwg-displays, nwg-look, lock)
- `CalendarPopup.qml`: clock with seconds, month grid (Mo–Su, de_DE), month switching
- `AltTab.qml`: **Alt+Tab switcher**: cards with icon, app name, title, sorted by Hyprland `focusHistoryID`; Tab/Shift+Tab, mouse wheel, hover + click, release Alt = switch, Alt+Esc = cancel
- Building blocks: `Pill.qml`, `BarButton.qml`, `Icon.qml`, `MenuRow.qml`, `ToggleTile.qml`, `SliderRow.qml`

Control: `qs -c draconyx ipc call shell toggleStart|toggleControl|toggleCalendar|closeAll|toggleAutohide` and `qs -c draconyx ipc call switcher next|prev|commit|cancel`. Log: `qs -c draconyx log`. Quickshell reloads QML file changes live.

---

## Hyprland behaviour (Windows-like)

- **All windows float** and open centred; terminals at least 760×460
- **Games** (`steam_app_*`, gamescope, `content=game`): real fullscreen, own desktop **10 "Game" on DP-2**, `no_shortcuts_inhibit` (games may not swallow Super/Alt+Tab)
- `follow_mouse = 2` (focus only by click) + `cursor.no_warps = true` (the mouse does not jump when the focus changes)
- Window borders: gradient violet→green, `resize_on_border`

### Key bindings

| Key | Action |
|---|---|
| Win (alone) / Win+S | start menu |
| Win+A | quick settings |
| Win+N | notifications |
| Win+E / Win+T / Win+B / Win+R | Dolphin / terminal / browser / fuzzel |
| Win+L | lock |
| Win+V | clipboard history |
| Win+Shift+S / Print | screenshot region / monitor |
| Alt+Tab, Alt+Shift+Tab | switcher |
| **Alt+F4** | **kill immediately (SIGKILL), explicitly wanted** |
| Win+Q | close normally |
| Win+↑ / Ctrl+Alt+↑ | real maximize (toggle) |
| Win+↓ / Ctrl+Alt+↓ | remove maximize, or normal size centred |
| Win+← / Win+→ | to the left / right half of the screen (own Lua function `snap()`) |
| Ctrl+Alt+← / → and Win+Shift+← / → | window to the left / right monitor |
| Win+F / F11 | fullscreen |
| Win+C | centre window |
| **Win+Esc** | **free the mouse** (focus + pointer to the other monitor, e.g. when a game holds the mouse) |
| Win / Alt + left mouse drag | move window (right mouse = resize) |
| Win+1…9, Win+Shift+1…9, Win+Ctrl+← / → | desktops |
| Win+Ctrl+Shift+Q | emergency exit: quit Hyprland |

---

## Lessons learned (important!)

1. **Hyprland 0.56 = Lua:** `hyprctl keyword` does not work; use `hyprctl eval '<lua>'`; `hyprctl dispatch 'hl.dsp....'` takes Lua expressions. Check with `Hyprland --verify-config`, then `hyprctl reload`. Lua API stubs: `/usr/share/hypr/stubs/hl.meta.lua`. Wiki sources: `github.com/hyprwm/hyprland-wiki` under `content/configuring/core/…`.
2. **Layer `top` in this version also sits above fullscreen windows**, which is why the bar hides itself.
3. **`WlrKeyboardFocus.Exclusive` in Hyprland also blocks mouse clicks.** The start menu uses `OnDemand` + `HyprlandFocusGrab`, Alt+Tab uses `None`.
4. **Wayland `Toplevel.activate()` does not focus in Hyprland** (only "urgent"), so use `hl.dsp.focus({ window = "address:0x…" })`.
5. **Waybar:** the `image` module makes the whole bar invisible. Waybar can only be started once per user (test instances hand over silently and exit).
6. **pcmanfm-qt** rewrites `settings.conf` when it exits; only change it when it is stopped (`pcmanfm-qt --quit`). Terminal there: `Terminal=ghostty`.
7. **No HDR brightness slider in the shell:** `hl.monitor({...})` with partial fields could replace the monitor rule and switch HDR off.
8. **Garuda:** before installing new packages always run a full `garuda-update` (an outdated package database once caused a Qt 6.11/6.12 conflict). 8 kernels installed → updates take a long time.
9. Hyprland has **no option to generally forbid windows from holding the mouse**; only Win+Esc as the emergency exit.
10. COSMIC has no HDR (roadmap epoch 3) → hence Hyprland.

---

## Open / ideas for later

- **Tested:** bar, icons, auto-hide when fullscreen, Alt+Tab display (via IPC + screenshot), maximize, Dolphin dark. **Not tested or only partly:** start menu clicks after switching to OnDemand, quick settings, calendar, window popups of the taskbar, Alt+Tab mouse click, the "show desktop" strip, emergency exit keys.
- Desktop icons appear on **all** monitors (pcmanfm-qt); the user did not really want that. `~/Schreibtisch` is very full (tidying offered, not done). Double-clicking a folder on the desktop still opens pcmanfm-qt instead of Dolphin.
- Workspaces have odd numbers per monitor in places (tidying possible).
- Own **Hypr Hypr colour scheme for KDE/Qt apps** (currently blue ChromeOS dark from KDE). Careful: it would also affect the Plasma session.
- Window previews in Alt+Tab or on hover in the taskbar (screencopy), notifications possibly directly in Quickshell instead of swaync, widgets, weather, system monitor, media mini player in the bar, title bar plugin (hyprbars) for apps without their own title bar.
- Helper script `claude-sessions save|restore` (`~/.local/bin/claude-sessions`) reopens Claude Code sessions after a session change (uses Ghostty).

---

# Addendum (later on 25.10.2026) – replaces contradicting statements above

## Important changes
- **Super key is broken** → ALL combinations run through **Ctrl+Alt** (`mainMod = "CTRL + ALT"`). There are no Super binds any more. Alt+Tab, Alt+F4 (hard kill, intended) and Alt+Space remain.
- **Maximize** is our own maximize (a floating window at work-area size, `DXSnap.toggleMax`), not Hyprland's "maximized". Reason: Hyprland's state sets a fullscreen flag on the desktop, after which clicks go to the wrong window. The app's maximize button is turned into our own maximize via the Lua event `window.fullscreen`.
- **Minimize** = move the window to the normal workspace `name:minimized`, which is never shown; desktop/position/size are remembered and restored exactly when it comes back, animations are off meanwhile (`no_anim`). Trigger: Hyprland IPC event `minimized>>address,1` (Quickshell `Hyprland.onRawEvent`). Steam/XWayland: `~/.local/bin/hyhy-x11-iconify` reads `WM_CHANGE_STATE`; Steam maximizes itself after being restored → an 8 s guard in `Global.qml` (`guardUntil`).
- **Tiling/zones**: windows float by default. `dx_tiling.lua` only tiles marked windows; the preferred layout is **own zones** (`dx_zones.lua`, zones come from the shell via `$XDG_RUNTIME_DIR/draconyx-zones.txt`). Grid editor (`GridEditor.qml`): templates, drag dividers, split/remove zones. Shift while dragging = show zones and snap. Snapping to edges/corners with a preview (`dx_snap.lua`, `SnapPreview.qml`).
- **Desktop** (`Desktop.qml`): wallpaper + icons directly in the shell, only on the monitors from `desktopMonitors`, drag frame / Ctrl+click multi-select, never takes keyboard focus. pcmanfm-qt is no longer used.
- **Coding Space** (`CodeSpace.qml`, `</>` button in the taskbar, Ctrl+Alt+K): finds `Code Space` on the code drive (`/run/media/<user>/*/Code Space`), per project a folder (Dolphin), terminal, VS Code, Claude, everything; opens on desktop 8 ("Code").
- **Window menu** (`WindowMenu.qml`, Alt+Space) for apps without a title bar (Dolphin, Kate): maximize, minimize, grid, monitor, bring to front, close, kill.
- **Start menu 2.0** (search across apps/settings/files/calculator, folders, drag), **Task View** (Ctrl+Alt+Tab), **Alt+Tab with cards**, window preview on hover.
- Settings live in `~/.local/state/draconyx/settings.json` (NOT in the shell folder, otherwise every save reloads the shell).

## Key bindings (all Ctrl+Alt + …)
Space start menu · S search · A quick settings · N notifications · Tab Task View · K Coding Space · E Dolphin · T terminal · B browser · R run · L lock · V clipboard · Q close · M minimize · Shift+M restore · arrows = snap (←→ halves, ↑ maximize/quarter, ↓ minimize/back) · Shift+←/→ other monitor · G window into the grid · Shift+G whole desktop · H switch grid template · J auto layout (zones/grid/columns/rows/master) · Z grid editor · X choose zone for the window · , and . swap places in the grid · Esc free the mouse · 1–9 desktops · Shift+1–9 move window · PgUp/PgDn desktops · Shift+Q emergency exit (quit Hyprland) · Alt+Tab switch windows · Alt+F4 kill · Alt+Space window menu · Alt or Ctrl+Alt + mouse drag/resize.

## Pitfalls (addendum)
- Start the shell **through Hyprland** (`hyprctl dispatch exec`), not from a terminal: started apps inherit its environment (wrong `QT_QPA_PLATFORMTHEME` → white Dolphin).
- `pkill -f` in a tool command kills your own shell. Keep Python replacements in `Global.qml` tightly bounded and back them up first (`~/.local/share/draconyx-backups/`).
- Qt/KDE apps have no window buttons under Hyprland (the Alt+Space menu is the replacement; the real fix would be the hyprbars plugin via `hyprpm`, which needs `sudo pacman -S hyprpm`).
- Still open: control centre 2.0 (Wi-Fi list, Bluetooth devices, output devices, per-app volume, performance profiles), own notification centre, Hypr Hypr settings app, Alt+Tab preview images, game mode with automatic detection, desktop widgets.

## Addendum: Coding Space, Git client, Wallpaper Engine, desktop icons
- **Coding Space** (`CodeSpace.qml`, helper script `~/.local/bin/hyhy-code-list`): workspace = folder with "Workspace" in its name (drive root + "Code Space"). Per project: IntelliJ, VS Code, terminal, Claude (logo, full path `~/.local/bin/claude`, because Hyprland's PATH does not contain ~/.local/bin), Git. "+ Workspace" creates a folder; inside a workspace "Clone" (git clone, `owner/repo` = GitHub).
- **Git client** (`GitClient.qml`): attaches to the right of the Coding Space (layer window, cannot be killed with Alt+F4). Stage by click/arrow/drag, commit, history with cherry-pick/revert/reset, branches (right click: checkout/merge/rebase/delete), fetch/pull (rebase)/push/stash, conflict bar (continue/abort). Detects deleted/renamed remote branches (upstream "gone", `ls-remote --symref`) and offers to switch. Checks on open and every 60 s (`fetch --prune`).
- **Wallpaper Engine**: built from `~/.local/src/linux-wallpaperengine` (installed to `~/.local/opt/linux-wallpaperengine`), scripts `hyhy-we-run`, `hyhy-we-apply`, `hyhy-we-list`. Own fixes: web wallpaper texture (RenderHandler), mouse position via Hyprland IPC per monitor. The desktop window lies above the engine (remap when the engine surface opens); the "Mouse" switch in the picker passes clicks through.
- **Desktop icons**: free positions (`iconPos` in settings.json), dragging also works across monitors.
- **Hidden-desktop guard**: when a monitor switches to `minimized`, the shell jumps back immediately.
