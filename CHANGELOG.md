# Changelog

The version number lives in the file `VERSION` (MAJOR.MINOR.PATCH). Raise the number and add an entry here for every visible change –
the update notification in the shell compares this number with the installed one.

## 1.6.4
- Aurora-Laufzeitmodule liegen in aurora_runtime/; bin/, Tests und Laufzeitmodule sind auf GitHub als generiert markiert (eingeklappt, nicht in der Sprachstatistik)

## 1.6.3
- Folders and commands are now named hypr-hypr and hyhy-*; old names stay as links until 1.x; updating to 2.x requires 1.6.3

## 1.6.2
- Name changed from Draconyx to Hypr Hypr in all displays, notifications and docs; paths and folders stay, nothing needs migrating

## 1.6.1
- Coding Space: workspaces no longer need "Workspace" in their name – detection by content (folders with projects), added folders and newly created workspaces keep their name, right-click: treat as workspace/project

## 1.6.0
- Aurora = all system settings: new pages Sound, Bluetooth, Network, Keyboard, Mouse & Touchpad, Accessibility, Date & Time, Region & Language, Users, Default Apps, About This System (updates, storage), Printers & Scanners, Notifications, Design (cursor, icons, themes), Devices & Ports; pages as modules (settings_pages/); cursor choice applies at login; high contrast as a colour preset

## 1.5.4
- Games: Alt+Tab from fullscreen games (focus/stacking order, foreign windows kept off the game desktop, pointer released when leaving); title bar raises windows; hardening: Lua modules (scaling, state leaks, timers), shell (start warnings, broken settings.json), scripts/installer (locks, atomic writes, timeouts), Aurora settings (search, export/import, input checks); dx-doctor extended

## 1.5.3
- Title bars: moving without animation remnants and release races (one shared helper), events wake the window watcher immediately, tests

## 1.5.2
- Fix: mouse hover in all windows (Aurora set follow_mouse=0, installer cleans up); title bar helpers more economical and snapping while dragging between screens is no longer overridden

## 1.5.1
- Title bars (minimize/maximize/close, dragging, double-click) for apps without their own bar such as Dolphin; windows of XWayland apps (Brave, VS Code, Discord, Aurora) can be dragged by their title bar without Alt or Ctrl+Alt; snapping leaves room for the bars

## 1.5.0
- New: clipboard history with image previews, focus time (Pomodoro/timer/stopwatch), volume OSD, keyboard shortcut overview (Ctrl+Alt+I), privacy and performance display in the bar, quick search with calculator/units/windows/system actions, drop-down terminal, text from screenshots (OCR), microphone key, Aurora: power & lock, motion & light (animations, night light schedule), smooth popup animations

## 1.4.0
- New: autostart management, window rules, backup/restore (Aurora), connections window for Wi-Fi/Bluetooth/audio, system monitor with program summary; VS Code & co. can be minimized (XWayland); desktop click + Ctrl+Space

## 1.3.9
- Snip tool (Print) no longer closes Code Space, the start menu, search and other shell windows

## 1.3.8
- Taskbar arrangement by dragging (areas left/centre/right, islands for the dock, hidden tray, right-click menu); Aurora without an Apply button, changes take effect live; mouse wheel speed also applies to lists in the shell

## 1.3.7
- Mouse wheel speed configurable (Aurora → Overview); settings are no longer reset on updates (since 1.3.6)

## 1.3.6
- Hotfix for 1.3.5: the shell could not load with the protection change (timer in the wrong place) – do not install 1.3.5, go straight to 1.3.6

## 1.3.5
- Important: settings (taskbar, desktop icons, wallpaper) are no longer reset on updates – protection in shell and installer, automatic backup, restore via dx-settings-guard

## 1.3.4
- Hotfix: the update check showed a stale state after git pull/push ("up to date" although something newer existed); "Check now" works now

## 1.3.3
- Hotfix: apps started from the start menu and taskbar are detached (dx-launch) – prevents the Discord error "write EPIPE"

## 1.3.2
- Update check every minute in the background (cheap pre-check), notices still at most once a day

## 1.3.1
- Update check every 30 minutes instead of every 6 hours; "Check now" button in Aurora → System

## 1.3.0
- **Aurora in the new design:** sidebar with icons and groups, card rows, wide controls below the text, clean section titles.
- **Displays like on Windows:** arrange by dragging, resolution, refresh rate, scaling, rotation, 15-second confirmation. Displays survive updates (dx-monitors sync, safety check after reload).
- **Steam Workshop in the wallpaper window:** new tab for browsing (Popular, New, Top, Search); subscribing opens the page in Steam, afterwards the wallpaper appears under "My wallpapers".
- **App installer (Aurora → Apps):** own apps from the repo, first app "Notes"; updated with system updates.
- **Updates:** background update with a progress bar and sudo dialog, update indicator in the taskbar with release notes, at most one notice per day, "Don't remind me", Aurora switch. Own settings are never overwritten.
- **Coding Space:** several folders, freely selectable programs (IntelliJ, VS Code, Cursor, Zed, Sublime, PyCharm, WebStorm, Kate, Neovim …) and custom ones; Claude only if installed.
- **Fonts:** 10 presets (Inter, Noto Sans, IBM Plex Sans, Roboto, Monaspace Krypton/Neon/Argon, JetBrains Mono, Fira Code, Cascadia Code) for the UI and code, selectable and installable in Aurora.
- **Alt+Tab:** a tap jumps immediately, holding Alt + Tab cycles, mouse can be turned off. **Remember window size** on close. **Tray menu** via right-click. **Quick info** on the taskbar buttons.
- **Terminal:** the chosen terminal applies everywhere; Ghostty only if none is installed; `dx-terminal-ensure` makes sure one is always present.
- **Minimizing:** Electron apps (Discord & co.) run via XWayland so the minimize icon works everywhere. Longer list of apps with their own title bar.
- **Installer:** package name alternatives, keyboard choice QWERTZ/QWERTY, portable hyprland.lua, desktop folder detected automatically, no personal monitor data in the repo.

## 1.2.2
- Update in the settings: version, date and update button in one row (button only for a new version), automatic background check

## 1.2.1
- Progress indicator during updates (top right); Alt+Tab: a tap jumps immediately, holding Alt + Tab cycles, mouse can be turned off

## 1.2.0
- Background update (sudo dialog instead of a terminal, notifications, log), keeps local repo changes; installer never overwrites user settings (hyprland.lua only if unchanged)

## 1.1.0
- Arrange displays like on Windows (resolution, scaling, rotation, 15-second confirmation), monitor detection in the installer, Coding Space with several folders, working dropdown popovers and folder selection, quick info, update check, Electron apps via XWayland, portable hyprland.lua, no personal monitor data anymore

## 1.0.0
- First versioned release: Draconyx shell (taskbar, start menu, search, Coding Space), Aurora as the settings app,
  snip tool with photo editor, Wallpaper Engine, rebindable key combinations, installer with keyboard choice, update check.
