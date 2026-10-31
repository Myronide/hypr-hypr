# AGENTS.md – Arbeitsanleitung für KI-Agenten (Codex, Claude Code, …)

Repo: Hyprland-Desktop von **SyntaxJason (Hypr Hypr)** und **Myronide (Aurora)**, zusammengeführt. Sprache in Doku, Commits und Meldungen: Deutsch, Commit-Titel dürfen Deutsch oder Englisch sein. **Keine KI-Zusätze in Commits oder PRs** (kein „Co-Authored-By", keine „Generated with"-Zeilen).

## Stack und Orte
| Teil | Ort im Repo | Läuft als / installiert nach |
|---|---|---|
| Shell (Taskleiste, Startmenü, Popups, Desktop, Git-Client, Wallpaper-Auswahl …) | `quickshell/*.qml` (Quickshell 0.3, QML) | `~/.config/quickshell/draconyx/`, Start: `qs -c draconyx` |
| Hyprland-Config (Lua, Hyprland **0.56.2**) | `hypr/hyprland.lua`, `dx_*.lua` | `~/.config/hypr/` |
| Hilfsskripte | `bin/dx-*` | `~/.local/bin/` |
| Aurora-Einstellungen (GTK3, Python) | `settings-app`, `preferences.py`, `settings.css`, `palette.css` | `~/.config/hypr/aurora/` |
| Aurora-Reste (reichen bei installierter Shell nur durch) | `desktop-ui`, `start-desktop`, `start-dock`, `background-restore` | `~/.config/hypr/aurora/` |
| Native Plugins (hyprbars, aurora-native) | `native/`, `hyprbars.version` | siehe unten **Plugins** |
| Wallpaper Engine (eigener Build mit Fixes) | `patches/`, `wallpaper-engine/` | `~/.local/opt/linux-wallpaperengine` |
| Installer / Updates | `install.sh`, `bin/dx-update`, `VERSION`, `CHANGELOG.md`, `release.sh` | – |

Zustand zur Laufzeit (nie im Config-Ordner der Shell speichern, jeder Schreibzugriff dort lädt die Shell neu):
`~/.local/state/draconyx/settings.json` (Taskleiste, Symbole, Wallpaper), `~/.config/draconyx/{colors.json,terminal,window-mode,modifier,binds.conf}`, `$XDG_RUNTIME_DIR/draconyx-*.{txt,pid,log}`.

## Harte Regeln (jede wurde durch einen echten Vorfall nötig)
1. **Die Live-Sitzung des Nutzers gehört dem Nutzer.** Hyprland-Absturz = alle Programme weg. Am 2026-10-25 ist Hyprland beim Speichern einer `hyprland.lua` mit Plugin-Block per **Auto-Reload** abgestürzt (SIGSEGV im Lua-Interpreter). Config-Änderungen immer erst mit `Hyprland --verify-config` und `luac5.4 -p datei.lua` prüfen, Sicherung vorher nach `~/.local/share/draconyx-backups/`.
2. **Keine Plugins in eine laufende Sitzung laden** (`hl.plugin.load`, `hyprctl plugin load`, Reload mit Plugin-Block). Nur beim Login laden.
   **Testinstanzen NIE mit `AQ_BACKENDS=headless` starten**: dieser Build ignoriert das, die Instanz läuft dann als **sichtbares Fenster auf dem Display des Nutzers** (ist mehrfach passiert). Stattdessen das Rezept `tests/vhl/vhl.sh <hyprland.lua> [HOME]` (privater `kwin_wayland --virtual` unter eigenem dbus, Hyprland darin; danach `source tests/vhl/vhl.env`, Aufräumen mit `tests/vhl/vhl-stop.sh`). Die Shell dort mit `qs -c draconyx` (Test-HOME mit installierter Shell) starten. **Nie** `unset DBUS_SESSION_BUS_ADDRESS` allein: GTK/Quickshell fallen dann auf den echten Sitzungs-Bus des Nutzers zurück (`/run/user/1000/bus`) und können dort Instanzen aktivieren (z. B. holt `settings-app` mit fester App-ID `local.aurora.Settings` ein echtes Aurora-Fenster nach vorn). Stattdessen `DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/none` setzen oder alles unter `dbus-run-session` starten. Der virtuelle Monitor hat Skalierung 2 und 640x360: `hyprctl eval 'hl.monitor({output="",mode="1920x1080",position="auto",scale=1})'`. `Hyprland --verify-config` stürzt auf diesem System inzwischen immer ab (auch mit der bewährten Config) und taugt nicht mehr als Prüfung; stattdessen Instanz starten, `hyprctl configerrors` und `hyprctl reload` prüfen.
3. **Update-Ablauf nie gegen die echte Sitzung testen.** Eine Test-Benachrichtigung mit „Aktualisieren"-Knopf wurde angeklickt und hat den echten Installer ausgeführt (git stash, Shell überschrieben). Nur mit `HOME=<tmp>`, Attrappen für `sudo`/`notify-send` und einem Test-Remote. Keine Benachrichtigungen mit Aktionsknöpfen auslösen.
4. **Vor jedem Push/Release prüfen, dass die Shell lädt**: nach dem Speichern ca. 8 s warten, nur die NEUEN Zeilen von `qs -c draconyx log` lesen, es muss „Configuration Loaded" ohne `ERROR`/„Failed to load configuration" stehen. Danach erst `./release.sh` und `git push` – **in getrennten Aufrufen**. 1.3.5 ist kaputt rausgegangen, weil das verkettet war.
5. **Nichts committen oder pushen ohne Aufforderung.** `origin` ist Myronides Repo. Version erhöhen: `./release.sh patch|minor|major "Text"` (schreibt VERSION, CHANGELOG, Commit, Tag); die Shells der anderen melden daraufhin ein Update.
6. **Einstellungen der Nutzer nie zurücksetzen.** `settings.json` wird nicht aus dem Repo überschrieben (siehe `dx-settings-guard`, 1.3.5/1.3.7).
7. **Tests dürfen den Nutzer nicht stören**: keine sichtbaren Testfenster auf seinen drei Monitoren (weiße Fenster blenden), keine künstlichen Klicks oder Mausbewegungen, während er arbeitet, keine Terminals als Ersatz für Browser-Verhalten (Brave/Chromium verhalten sich anders). Fenster-Tests auf einem versteckten Desktop (`workspace "9 silent"`), danach schließen.
8. Fallen beim Bearbeiten: große `replace`-Aufrufe in `Global.qml` (über 1000 Zeilen) haben schon einmal zu weit geschnitten, immer mit begrenzten Ankern arbeiten und vorher sichern; doppelte `Component.onCompleted` oder `onVisibleChanged` in einer QML-Datei brechen das Laden; ein `Timer` oder anderes Objekt gehört nicht in `FileView`/`JsonAdapter`.
9. In einem Bash-Aufruf nie `pkill -f` oder `pgrep -f muster`, wenn das Muster im eigenen Befehl vorkommt (beendet die eigene Shell). Stattdessen `pgrep -x name` und `/proc/<pid>/cmdline` prüfen.
10. Wallpaper/Prozess-Namen: `linux-wallpaperengine` wird als `linux-wallpaper` (15 Zeichen) gelistet, `pgrep -x linux-wallpaper`.

## Hyprland-/Quickshell-Fakten, die man sonst teuer lernt
- Config ist **Lua** (`hl.bind`, `hl.on`, `hl.dsp.*`, `hl.timer`, `hl.get_windows/monitors`). `hyprctl keyword` gibt es nicht, stattdessen `hyprctl eval '<lua>'` und `hyprctl dispatch 'hl.dsp…'`. `float({action="set"})` **schaltet um** (nur aufrufen, wenn das Fenster nicht schon floatet).
- Es gibt kein Lua-Ereignis `window.minimize`; Hyprland sendet auf dem Event-Socket `minimized>>adresse,0|1` nur bei Minimieren über foreign-toplevel. **xdg-`set_minimized` von Wayland-Fenstern (GTK, Chromium nativ) wird ignoriert.** Darum: Brave, Discord, VS Code, Aurora laufen über **XWayland** (`--ozone-platform=x11`, `GDK_BACKEND=x11`); deren Minimieren kommt als `WM_CHANGE_STATE` an und wird von `dx-x11-iconify`/`dx-window-watch` an die Shell gegeben.
- Minimieren = Fenster auf den normalen (nicht speziellen) Desktop `name:minimized` verschieben, Herkunft merken, bei Rückkehr auf einen **sichtbaren** Desktop zurück, danach nach oben (`hl.dsp.window.alter_zorder({ mode = "top", window = "address:…" })`). Wechselt ein Monitor auf `minimized`, springt die Shell sofort zurück.
- Maximieren ist ein eigenes floating Fenster in Arbeitsfläche-Größe (`dx_snap`), nicht Hyprlands „maximized" (setzt Workspace-Vollbild-Flag, Klicks treffen das falsche Fenster). Apps (Brave/XWayland) reagieren auf das Zurücknehmen mit eigener Größenänderung, deshalb verzögertes/zweites Anwenden.
- Shell **über Hyprland starten**, nicht aus einem Agent-Terminal (`hyprctl dispatch 'hl.dsp.exec_cmd("sh -c '"'"'QS_ICON_THEME=Papirus-Dark exec qs -c draconyx'"'"'")'`), sonst erben gestartete Apps die falsche Umgebung (weißes Dolphin). Benötigt `QT_QPA_PLATFORMTHEME=kde`.
- Layer-Fenster der Shell: Popups mit `exclusionMode: ExclusionMode.Ignore` und Rändern relativ zum Bildschirmrand; eine Leiste mit `exclusiveZone` verschiebt sonst alle anderen Layer zusätzlich.
- Bedingte Anker (`anchors.top: cond ? x : undefined`) dehnen auf neueren Qt-Versionen Elemente; feste `x`/`y`-Ausdrücke nehmen.
- Mount-Name der Code-Platte wechselt (`Code`/`Code1`); nie fest verdrahten, `dx-code-list` und Global suchen `/run/media/$USER/*/Code Space`.
- Tastatur: Nutzer-Super-Taste ist (vermutlich Firmware-Windows-Sperre der Turtle Beach Vulcan II) tot. Kombinationen müssen über die **Haupttaste**-Einstellung (`modifier`: super | both | ctrl-alt | caps) laufen, Standard für SyntaxJason ist Strg+Alt.

## Testen
- **Shell**: `qs -c draconyx log` (Fehler), IPC `qs -c draconyx ipc call shell <funktion>` (u. a. `toggleStart`, `closeAll`, `toggleCode`, `openSettings`, `weReapply`, `barStyle`, `toggleAutohide`), Screenshots `grim -o <Monitor> datei.png` (Monitore: DP-1 0,0 · DP-2 2560,0 · HDMI-A-2 5120,0). Autohide kurz abschalten, um die Leiste zu fotografieren, danach wieder an.
- **Fenster**: `hyprctl clients -j | jq …`, Ereignisse mitschneiden über `/run/user/1000/hypr/<sig>/.socket2.sock`.
- **Tasten**: `hyprctl eval "hl.on('input.keyboard.key', function(code,_,state) … end)"` schreibt Tastencodes in eine Datei (nur zur Laufzeit; Super = 133/134, Strg = 37, Alt = 64).
- **Installer**: nur mit `HOME=<tmp>`, `DX_NO_START=1` und Attrappen für `sudo`/`pgrep`/`pkill` im PATH (Schritt 5/6 beenden sonst echte Programme), `--no-packages`, `--no-we`, zweimal laufen lassen (zweiter Lauf darf nichts ändern).
- **Diagnose** bei Nutzern: `dx-doctor` (Bericht nach `~/dx-doctor.txt`), `dx-doctor --fix` beendet Doppelstarts.
- Bekannt: Das Ändern von Dateien unter `~/.config/quickshell/draconyx/` lädt die Shell sofort neu; Hyprland lädt die Config beim Speichern von `hyprland.lua` automatisch neu.

## Offene Punkte (Stand 2026-10-25, **zuerst prüfen**, einiges ist inzwischen behoben)
- Brave: eigener Minimieren-Knopf (X11, eigener Rahmen) kam in einer Aufzeichnung nicht als `WM_CHANGE_STATE` an; mit echtem Klick prüfen, Brave starten mit `--ozone-platform=x11` und „Systemtitelleiste" aus.
- Brave Maximieren: sprang „groß, dann klein" (Zurücknehmen durch die App); bei Myronide zusätzlich „zu hoch, über den Bildschirm hinaus", wenn Auto-Hide aus ist. Dafür `hyprctl monitors -j` (reserved) und `hyprctl clients -j` von seinem Rechner mit maximiertem Brave anfordern.
- Taskleiste im Vollbild: Schalter „bei Vollbild ausblenden" (Standard aus) bei Vollbild-Fenstern auf Overlay-Ebene prüfen.
- Dock mit „Teile einzeln ausfahren" (Auto-Hide): Ausfahren per Maus noch nie wirklich getestet.
- Fenstermodus-Knopf (Schweben ↔ Kacheln): Umschalten ordnet alle Fenster, nie live getestet.
- Medien-Karte (Kontrollzentrum): zeigte Titel/Interpret nur kurz nach dem Pausieren; Browser nehmen den Player weg. Mit echtem Browser-Audio prüfen.
- Alt+Tab bei Myronide (Wächter bestätigt bei Alt-Loslassen), Breeze-Cursor in XWayland-Apps (`~/.icons/default`), Maus springt bei Fokus (`cursor.no_warps`), Plugins nur beim Login laden.
- Web-Wallpaper und Mausposition der Wallpaper Engine sind im Quellcode gepatcht (`patches/`), Klicks gehen nur bei „Maus"-Schalter durch.

## Vor dem Abgeben
Shell lädt ohne Fehler · `hyprland.lua` besteht `--verify-config` · Installer zweimal im Test-HOME ohne Änderung im zweiten Lauf · Nutzer-Einstellungen unverändert · `CHANGELOG.md` und `VERSION` über `release.sh` · nichts gepusht, bevor der Nutzer es sagt.
