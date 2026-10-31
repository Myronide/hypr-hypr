# AGENTS.md – Working guide for AI agents (Codex, Claude Code, …)

Repo: Hyprland desktop by **SyntaxJason (Hypr Hypr)** and **Myronide (Aurora)**, merged. Language for docs, commits and messages: English. Commit titles may still be German for older commits. **No AI attributions in commits or PRs** (no "Co-Authored-By", no "Generated with" lines).

## Stack and locations
| Part | Location in repo | Runs as / installed to |
|---|---|---|
| Shell (taskbar, start menu, popups, desktop, Git client, wallpaper picker …) | `quickshell/*.qml` (Quickshell 0.3, QML) | `~/.config/quickshell/draconyx/`, start: `qs -c draconyx` |
| Hyprland config (Lua, Hyprland **0.56.2**) | `hypr/hyprland.lua`, `dx_*.lua` | `~/.config/hypr/` |
| Helper scripts | `bin/hyhy-*` | `~/.local/bin/` |
| Aurora settings (GTK3, Python) | `settings-app`, `preferences.py`, `settings.css`, `palette.css` | `~/.config/hypr/aurora/` |
| Aurora leftovers (only pass through when the shell is installed) | `desktop-ui`, `start-desktop`, `start-dock`, `background-restore` | `~/.config/hypr/aurora/` |
| Native plugins (hyprbars, aurora-native) | `native/`, `hyprbars.version` | see **Plugins** below |
| Wallpaper Engine (own build with fixes) | `patches/`, `wallpaper-engine/` | `~/.local/opt/linux-wallpaperengine` |
| Installer / updates | `install.sh`, `bin/hyhy-update`, `VERSION`, `CHANGELOG.md`, `release.sh` | – |

Runtime state (never store it in the shell's config folder; every write there reloads the shell):
`~/.local/state/draconyx/settings.json` (taskbar, icons, wallpaper), `~/.config/draconyx/{colors.json,terminal,window-mode,modifier,binds.conf}`, `$XDG_RUNTIME_DIR/draconyx-*.{txt,pid,log}`.

## Hard rules (each one was needed because of a real incident)
1. **The user's live session belongs to the user.** A Hyprland crash = all programs gone. On 2026-10-25 Hyprland crashed via **auto-reload** while saving a `hyprland.lua` with a plugin block (SIGSEGV in the Lua interpreter). Always check config changes first with `Hyprland --verify-config` and `luac5.4 -p file.lua`, and back up beforehand to `~/.local/share/draconyx-backups/`.
2. **Never load plugins into a running session** (`hl.plugin.load`, `hyprctl plugin load`, reload with a plugin block). Load them only at login.
   **Never start test instances with `AQ_BACKENDS=headless`**: this build ignores it, and the instance then runs as a **visible window on the user's display** (it has happened several times). Use the recipe `tests/vhl/vhl.sh <hyprland.lua> [HOME]` instead (private `kwin_wayland --virtual` under its own dbus, Hyprland inside it; then `source tests/vhl/vhl.env`, clean up with `tests/vhl/vhl-stop.sh`). Start the shell there with `qs -c draconyx` (test HOME with the shell installed). **Never** `unset DBUS_SESSION_BUS_ADDRESS` on its own: GTK/Quickshell then fall back to the user's real session bus (`/run/user/1000/bus`) and can activate instances there (e.g. `settings-app` with the fixed app ID `local.aurora.Settings` brings a real Aurora window to the front). Instead set `DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/none` or run everything under `dbus-run-session`. The virtual monitor has scale 2 and 640x360: `hyprctl eval 'hl.monitor({output="",mode="1920x1080",position="auto",scale=1})'`. `Hyprland --verify-config` now always crashes on this system (even with the proven config) and is no longer a useful check; instead start an instance and check `hyprctl configerrors` and `hyprctl reload`.
3. **Never test the update flow against the real session.** A test notification with an "Update" button was clicked and ran the real installer (git stash, shell overwritten). Only use `HOME=<tmp>`, stubs for `sudo`/`notify-send`, and a test remote. Never trigger notifications with action buttons.
4. **Before every push/release, check that the shell loads**: after saving, wait about 8 s, read only the NEW lines of `qs -c draconyx log`; it must show "Configuration Loaded" without `ERROR`/"Failed to load configuration". Only then run `./release.sh` and `git push` – **in separate calls**. 1.3.5 went out broken because these were chained.
5. **Do not commit or push without being asked.** `origin` is Myronide's repo. Raise the version with `./release.sh patch|minor|major "Text"` (writes VERSION, CHANGELOG, commit, tag); the other users' shells then report an update.
6. **Never reset the user's settings.** `settings.json` is not overwritten from the repo (see `hyhy-settings-guard`, 1.3.5/1.3.7).
7. **Tests must not disturb the user**: no visible test windows on his three monitors (white windows are blinding), no artificial clicks or mouse movement while he is working, no terminals as a stand-in for browser behaviour (Brave/Chromium behave differently). Run window tests on a hidden desktop (`workspace "9 silent"`) and close them afterwards.
8. Pitfalls when editing: large `replace` calls in `Global.qml` (over 1000 lines) have cut too much before; always work with bounded anchors and back up first. Duplicate `Component.onCompleted` or `onVisibleChanged` in one QML file breaks loading; a `Timer` or other object does not belong inside `FileView`/`JsonAdapter`.
9. In a Bash call never use `pkill -f` or `pgrep -f pattern` when the pattern appears in the command itself (it kills your own shell). Use `pgrep -x name` and check `/proc/<pid>/cmdline` instead.
10. Wallpaper/process names: `linux-wallpaperengine` is listed as `linux-wallpaper` (15 characters), so use `pgrep -x linux-wallpaper`.

## Hyprland/Quickshell facts that are expensive to learn the hard way
- The config is **Lua** (`hl.bind`, `hl.on`, `hl.dsp.*`, `hl.timer`, `hl.get_windows/monitors`). `hyprctl keyword` does not exist; use `hyprctl eval '<lua>'` and `hyprctl dispatch 'hl.dsp…'` instead. `float({action="set"})` **toggles** (only call it when the window is not already floating).
- There is no Lua event `window.minimize`; Hyprland only sends `minimized>>address,0|1` on the event socket when minimizing via foreign-toplevel. **xdg `set_minimized` from Wayland windows (GTK, native Chromium) is ignored.** That is why Brave, Discord, VS Code and Aurora run via **XWayland** (`--ozone-platform=x11`, `GDK_BACKEND=x11`); their minimize arrives as `WM_CHANGE_STATE` and is passed to the shell by `hyhy-x11-iconify`/`hyhy-window-watch`.
- Minimizing = move the window to the normal (not special) desktop `name:minimized`, remember where it came from, on restore go back to a **visible** desktop, then raise it (`hl.dsp.window.alter_zorder({ mode = "top", window = "address:…" })`). When a monitor switches to `minimized`, the shell jumps back immediately.
- Maximizing is our own floating window at work-area size (`dx_snap`), not Hyprland's "maximized" (that sets the workspace fullscreen flag, and clicks hit the wrong window). Apps (Brave/XWayland) react to being restored with their own resize, so the apply happens delayed/a second time.
- Start the shell **through Hyprland**, not from an agent terminal (`hyprctl dispatch 'hl.dsp.exec_cmd("sh -c '"'"'QS_ICON_THEME=Papirus-Dark exec qs -c draconyx'"'"'")'`), otherwise started apps inherit the wrong environment (white Dolphin). Requires `QT_QPA_PLATFORMTHEME=kde`.
- Shell layer windows: popups use `exclusionMode: ExclusionMode.Ignore` and margins relative to the screen edge; a bar with `exclusiveZone` otherwise also shifts all other layers.
- Conditional anchors (`anchors.top: cond ? x : undefined`) stretch elements on newer Qt versions; use fixed `x`/`y` expressions instead.
- The mount name of the code drive changes (`Code`/`Code1`); never hard-wire it. `hyhy-code-list` and Global search `/run/media/$USER/*/Code Space`.
- Keyboard: the user's Super key is dead (probably the firmware Windows lock of the Turtle Beach Vulcan II). Combinations must go through the **modifier key** setting (`modifier`: super | both | ctrl-alt | caps); the default for SyntaxJason is Ctrl+Alt.

## Testing
- **Shell**: `qs -c draconyx log` (errors), IPC `qs -c draconyx ipc call shell <function>` (among others `toggleStart`, `closeAll`, `toggleCode`, `openSettings`, `weReapply`, `barStyle`, `toggleAutohide`), screenshots `grim -o <monitor> file.png` (monitors: DP-1 0,0 · DP-2 2560,0 · HDMI-A-2 5120,0). Turn autohide off briefly to photograph the bar, then turn it back on.
- **Windows**: `hyprctl clients -j | jq …`, record events via `/run/user/1000/hypr/<sig>/.socket2.sock`.
- **Keys**: `hyprctl eval "hl.on('input.keyboard.key', function(code,_,state) … end)"` writes key codes to a file (runtime only; Super = 133/134, Ctrl = 37, Alt = 64).
- **Installer**: only with `HOME=<tmp>`, `DX_NO_START=1` and stubs for `sudo`/`pgrep`/`pkill` in PATH (otherwise steps 5/6 stop real programs), `--no-packages`, `--no-we`, run twice (the second run must change nothing).
- **Diagnostics** on users' machines: `hyhy-doctor` (report to `~/hyhy-doctor.txt`), `hyhy-doctor --fix` stops duplicate starts.
- Known: changing files under `~/.config/quickshell/draconyx/` reloads the shell immediately; Hyprland reloads the config automatically when `hyprland.lua` is saved.

## Open points (as of 2026-10-25, **check these first**, some have since been fixed)
- Brave: its own minimize button (X11, own frame) did not arrive as `WM_CHANGE_STATE` in one recording; check with a real click, start Brave with `--ozone-platform=x11` and "system title bar" off.
- Brave maximize: it jumped "big, then small" (the app undoes it); on Myronide's machine additionally "too high, beyond the screen" when auto-hide is off. For this, request `hyprctl monitors -j` (reserved) and `hyprctl clients -j` from his machine with a maximized Brave.
- Taskbar in fullscreen: check the "hide in fullscreen" switch (default off) with fullscreen windows on overlay level.
- Dock with "split pills out individually" (auto-hide): sliding out with the mouse has never really been tested.
- Window mode button (floating ↔ tiles): switching rearranges all windows; never tested live.
- Media card (control centre): showed title/artist only briefly after pausing; browsers take the player away. Check with real browser audio.
- Alt+Tab on Myronide's machine (watcher confirms on Alt release), Breeze cursor in XWayland apps (`~/.icons/default`), mouse jumps on focus (`cursor.no_warps`), load plugins only at login.
- Web wallpaper and the Wallpaper Engine mouse position are patched in the source (`patches/`); clicks only pass through with the "Mouse" switch.

## Before handing off
Shell loads without errors · `hyprland.lua` passes `--verify-config` · installer run twice in a test HOME with no change in the second run · user settings unchanged · `CHANGELOG.md` and `VERSION` via `release.sh` · nothing pushed before the user says so.
