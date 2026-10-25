# Draconyx Desktop auf Hyprland – Übergabe (Stand 25.10.2026)

Ziel des Nutzers: ein **Windows-11-artiger, aber modernerer und „geilerer" Desktop** auf Hyprland im **Draconyx-Look** (Draconyx = eigene Marke des Nutzers, Drachen-Logo). Viel Funktion, aufgeräumt, gaming-tauglich, HDR muss bleiben. Bitte das Konzept in diesem Sinne weiterentwickeln.

---

## System

- Garuda Linux (Arch-basiert), Kernel 7.3.0-4-garuda, AMD RX 7700 XT/7800 XT (amdgpu)
- **Hyprland 0.56.2 mit Lua-Config** (`~/.config/hypr/hyprland.lua`, hyprlang ist ab 0.55 veraltet)
- Quickshell 0.3.2, Ghostty 1.3.1, Waybar 0.15 (nur noch Fallback), pcmanfm-qt 2.4.1, nwg-drawer 0.7.5 (Fallback)
- Plasma (KDE) und COSMIC sind weiter installiert und im Login-Screen wählbar (Fallback)
- Deutsche Tastatur, Fish als Shell

### Monitore (in `hyprland.lua`, links → rechts, oben bündig)

| Port | Monitor | Modus | Position | HDR |
|---|---|---|---|---|
| DP-1 | Acer VG270U E | 2560x1440@59.95 | 0x0 | `cm="hdr"`, 10 bit, `sdrbrightness=3.75` (≈300 nits) |
| DP-2 | Acer XV271U M3 (Hauptmonitor, Gaming) | 2560x1440@179.88 | 2560x0 | `cm="hdr"`, 10 bit, `sdrbrightness=2.5` (≈200 nits), VRR an |
| HDMI-A-2 | 236 FHD | 1920x1080@60 | 5120x0 | nein (sRGB) |

SDR-Helligkeit unter HDR = 80 nits × `sdrbrightness`. Die Acers stehen per DDC auf 100 % und sind im HDR-Modus per DDC nicht regelbar.

---

## Design „Draconyx Dark"

- **Hauptakzent Violett `#8b5cf6`** (hell `#a78bfa`, tief `#5b3fd0`)
- **Zweitakzent Grün `#6ee05c`** nur sparsam (Drachenaugen): Fensterrand-Verlauf Violett→Grün, „heute" im Kalender, Passwort-OK am Sperrbildschirm
- Hintergründe fast schwarz mit Blau/Violett-Stich (`#07060d`, Panels `rgba(10,9,17,0.8–0.94)`), Text `#ece9f7`, gedimmt `#9a95b8`
- Schrift: Inter (UI), JetBrainsMono Nerd Font (Terminal)
- Glas-Optik: Hyprland-Blur auf Layern `^draconyx-.*`, Rundungen 10 (Fenster) bis 22 (Popups)
- Icons: **Fluent (Iconify)** als SVG, je in Textfarbe und Violett (`name.svg` / `name-a.svg`) in `~/.local/share/draconyx-hypr/qs-icons/` (42 Icons). Iconify-API drosselt schnell (HTTP 429): Ausweichweg ist das npm-Paket `@iconify-json/fluent` (icons.json über jsDelivr) und daraus SVGs bauen.
- Logo: `~/Bilder/draconyx-logo.png` (schwarzer Drache, grüne Augen, transparent). Auf dunkler UI unsichtbar, deshalb gibt es eine helle Silber-Lavendel-Variante mit violettem Glow: `~/.local/share/draconyx-hypr/logo-start.png` (Startknopf), `logo-lock.png` (Sperrbildschirm), `logo-light.png`
- Wallpaper: `~/Bilder/Wallpapers/draconyx-dark.png` (4K, schwarz mit violettem Schein rechts, Drache als dezentes Wasserzeichen, grüner Hauch unten). Stil angelehnt an ein KI-Mockup des Nutzers (`~/Bilder/20aab2f1-ba86-4293-80c0-310edee4109d.png`). Der Nutzer will davon **nur die Stimmung übernehmen, nicht das Layout kopieren**.

---

## Komponenten

| Funktion | Programm | Config |
|---|---|---|
| Taskleiste, Startmenü, Schnelleinstellungen, Kalender, Alt+Tab | **Quickshell „Draconyx Shell"** | `~/.config/quickshell/draconyx/` |
| Desktop-Icons + Wallpaper | `pcmanfm-qt --desktop` | `~/.config/pcmanfm-qt/default/settings.conf` |
| Benachrichtigungen | swaync | `~/.config/swaync/style.css` |
| Sperrbildschirm / Idle | hyprlock / hypridle | `~/.config/hypr/hyprlock.conf`, `hypridle.conf` |
| Launcher „Ausführen" (Super+R), Zwischenablage | fuzzel, cliphist | `~/.config/fuzzel/fuzzel.ini` |
| Terminal | Ghostty (Kitty als Fallback) | `~/.config/ghostty/config`, `~/.config/kitty/kitty.conf` |
| Dateimanager | **Dolphin** (Standard für Ordner via xdg-mime) | – |
| Qt-/KDE-Apps-Theme | `QT_QPA_PLATFORMTHEME=kde` (liest KDE-Farbschema, dunkel) | – |
| Fallback-Taskleiste / -Startmenü | Waybar / nwg-drawer | `~/.config/waybar/`, `~/.config/nwg-drawer/drawer.css`, `~/.config/hypr/scripts/start-menu.sh` |

Autostart in `hyprland.lua` (`hl.on("hyprland.start", ...)`): polkit-agent, pcmanfm-qt --desktop, **Draconyx Shell** (`QS_ICON_THEME=Papirus-Dark qs -c draconyx`, Fallback Waybar), swaync, hypridle, nm-applet, blueman-applet, cliphist, EasyEffects, JamesDSP, JetBrains Toolbox.

---

## Draconyx Shell (Quickshell, ~1700 Zeilen QML)

Dateien in `~/.config/quickshell/draconyx/`:

- `shell.qml`: Einstieg; eine Leiste pro Monitor (`Variants`), Popups, IPC-Handler `shell` und `switcher`
- `Theme.qml` (Singleton): Farben, Größen, Pfade, `icon(name, accent)`
- `Global.qml` (Singleton): Popup-Zustand, **`settings.json`** (FileView + JsonAdapter: `pinned`, `startPins`, `autohide`), Schalter (Nachtlicht, Game-Modus, DND), swaync-Abo (Zähler/DND), nmcli-Netzstatus, Helfer (`normId`, `entryFor`, `iconFor`, `launch`, **`focusToplevel`/`focusHypr`** = Fokus über Hyprland-Dispatch)
- `Bar.qml`: Taskleiste, drei schwebende Pillen
  - links: Desktops des Monitors (Desktop 10 = „Spiel" mit Controller-Icon)
  - Mitte: Drachen-Startknopf, Suche, **Apps gruppiert pro App-ID** (angeheftete zuerst)
  - rechts: Tray, Netzwerk+Lautstärke (→ Schnelleinstellungen, Mausrad = Lautstärke), Glocke mit Zähler (Linksklick swaync-Panel, Rechtsklick DND), Uhr (→ Kalender), Streifen „Desktop anzeigen"
  - **Auto-Hide:** fährt nach 900 ms ohne Maus ein, 3-px-Hover-Streifen am unteren Rand bringt sie zurück; abschaltbar
  - **Bei Vollbild auf dem Monitor komplett unsichtbar** (`HyprlandWorkspace.hasFullscreen`)
- `TaskButton.qml`: App-Knopf; Strich unten = läuft / breiter = mehrere Fenster / violett = aktiv; Klick = fokussieren oder Fensterliste; Mittelklick = neues Fenster; Rechtsklick-Menü (neues Fenster, anheften/lösen, alle schließen)
- `StartMenu.qml`: Suche (Pfeile + Enter), angeheftete Apps (Raster), „Alle Apps", Fußleiste mit Benutzer + Sperren/Abmelden/Standby/Neustart/Aus (Abmelden, Neustart und Aus mit Bestätigungs-Klick)
- `ControlCenter.qml`: Kacheln (Nicht stören, Nachtlicht via hyprsunset, Game-Modus = Animationen/Blur/Schatten aus via `hyprctl eval`, Leiste ausblenden, Bluetooth, Netzwerk), Regler Lautstärke + Mikrofon (Pipewire), Medienkarte (MPRIS mit Cover), Werkzeuge (Screenshot, Farbpipette, Zwischenablage, nwg-displays, nwg-look, Sperren)
- `CalendarPopup.qml`: Uhr mit Sekunden, Monatsraster (Mo–So, de_DE), Monatswechsel
- `AltTab.qml`: **Alt+Tab-Umschalter**: Karten mit Icon, App-Name, Titel, sortiert nach Hyprland-`focusHistoryID`; Tab/Shift+Tab, Mausrad, Hover + Klick, Alt loslassen = wechseln, Alt+Esc = abbrechen
- Bausteine: `Pill.qml`, `BarButton.qml`, `Icon.qml`, `MenuRow.qml`, `ToggleTile.qml`, `SliderRow.qml`

Steuern: `qs -c draconyx ipc call shell toggleStart|toggleControl|toggleCalendar|closeAll|toggleAutohide` und `qs -c draconyx ipc call switcher next|prev|commit|cancel`. Log: `qs -c draconyx log`. Quickshell lädt Änderungen an QML-Dateien live neu.

---

## Hyprland-Verhalten (Windows-artig)

- **Alle Fenster schweben** und öffnen zentriert; Terminals mindestens 760×460
- **Spiele** (`steam_app_*`, gamescope, `content=game`): echtes Vollbild, eigener Desktop **10 „Spiel" auf DP-2**, `no_shortcuts_inhibit` (Spiele dürfen Super/Alt+Tab nicht schlucken)
- `follow_mouse = 2` (Fokus nur per Klick) + `cursor.no_warps = true` (Maus springt bei Fokuswechsel nicht)
- Fensterränder: Verlauf Violett→Grün, `resize_on_border`

### Tastenkürzel

| Taste | Aktion |
|---|---|
| Win (allein) / Win+S | Startmenü |
| Win+A | Schnelleinstellungen |
| Win+N | Benachrichtigungen |
| Win+E / Win+T / Win+B / Win+R | Dolphin / Terminal / Browser / fuzzel |
| Win+L | Sperren |
| Win+V | Zwischenablage-Verlauf |
| Win+Shift+S / Druck | Screenshot Bereich / Monitor |
| Alt+Tab, Alt+Shift+Tab | Umschalter |
| **Alt+F4** | **Sofort killen (SIGKILL), ausdrücklich so gewünscht** |
| Win+Q | normal schließen |
| Win+↑ / Strg+Alt+↑ | echtes Maximieren (umschalten) |
| Win+↓ / Strg+Alt+↓ | Maximieren aufheben bzw. Normalgröße mittig |
| Win+← / Win+→ | an linke / rechte Bildschirmhälfte (eigene Lua-Funktion `snap()`) |
| Strg+Alt+← / → und Win+Shift+← / → | Fenster auf linken / rechten Monitor |
| Win+F / F11 | Vollbild |
| Win+C | Fenster zentrieren |
| **Win+Esc** | **Maus befreien** (Fokus + Zeiger auf anderen Monitor, z. B. wenn ein Spiel die Maus festhält) |
| Win / Alt + linke Maus ziehen | Fenster verschieben (rechte Maus = Größe) |
| Win+1…9, Win+Shift+1…9, Win+Strg+← / → | Desktops |
| Win+Strg+Shift+Q | Notausgang: Hyprland beenden |

---

## Gelernte Fallen (wichtig!)

1. **Hyprland 0.56 = Lua:** `hyprctl keyword` geht nicht, stattdessen `hyprctl eval '<lua>'`; `hyprctl dispatch 'hl.dsp....'` nimmt Lua-Ausdrücke. Prüfen mit `Hyprland --verify-config`, danach `hyprctl reload`. Lua-API-Stubs: `/usr/share/hypr/stubs/hl.meta.lua`. Wiki-Quellen: `github.com/hyprwm/hyprland-wiki` unter `content/configuring/core/…`.
2. **Layer `top` liegt in dieser Version auch über Vollbild-Fenstern**, deshalb blendet sich die Leiste selbst aus.
3. **`WlrKeyboardFocus.Exclusive` blockiert in Hyprland auch Mausklicks.** Startmenü nutzt `OnDemand` + `HyprlandFocusGrab`, Alt+Tab `None`.
4. **Wayland-`Toplevel.activate()` fokussiert in Hyprland nicht** (nur „dringend"), daher über `hl.dsp.focus({ window = "address:0x…" })`.
5. **Waybar:** Das `image`-Modul macht die ganze Leiste unsichtbar. Waybar ist pro Nutzer nur einmal startbar (Testinstanzen übergeben still und beenden sich).
6. **pcmanfm-qt** schreibt `settings.conf` beim Beenden neu; nur ändern, wenn er gestoppt ist (`pcmanfm-qt --quit`). Terminal dort: `Terminal=ghostty`.
7. **Kein HDR-Helligkeitsregler** in der Shell: `hl.monitor({...})` mit Teilfeldern könnte die Monitor-Regel ersetzen und HDR abschalten.
8. **Garuda:** Vor neuen Paketen immer erst volles `garuda-update` (veraltete Paketdatenbank hat einmal einen Qt-6.11/6.12-Konflikt verursacht). 8 Kernel installiert → Updates dauern lange.
9. Hyprland bietet **keine Option, Maus-Sperren von Fenstern generell zu verbieten**; nur Win+Esc als Notausgang.
10. COSMIC hat kein HDR (Roadmap Epoch 3) → deshalb Hyprland.

---

## Offen / Ideen für weiter

- **Getestet:** Leiste, Icons, Auto-Hide-Ausblenden bei Vollbild, Alt+Tab-Anzeige (per IPC + Screenshot), Maximieren, Dolphin dunkel. **Nicht oder nur teils getestet:** Startmenü-Klicks nach Umstellung auf OnDemand, Schnelleinstellungen, Kalender, Fenster-Popups der Taskleiste, Alt+Tab-Mausklick, Desktop-anzeigen-Streifen, Notausgang-Tasten.
- Desktop-Icons erscheinen auf **allen** Monitoren (pcmanfm-qt), der Nutzer wollte das eigentlich nicht; `~/Schreibtisch` ist sehr voll (Aufräumen angeboten, nicht gemacht). Doppelklick auf Ordner auf dem Desktop öffnet noch pcmanfm-qt statt Dolphin.
- Workspaces haben teils komische Nummern pro Monitor (aufräumen möglich).
- Eigenes **Draconyx-Farbschema für KDE/Qt-Apps** (aktuell blaues ChromeOS-Dark aus KDE). Achtung: würde auch die Plasma-Sitzung betreffen.
- Fensterpreviews im Alt+Tab bzw. beim Hover in der Taskleiste (Screencopy), Benachrichtigungen evtl. direkt in Quickshell statt swaync, Widgets, Wetter, Systemmonitor, Medien-Mini-Player in der Leiste, Titelleisten-Plugin (hyprbars) für Apps ohne eigene Titelleiste.
- Hilfsskript `claude-sessions save|restore` (`~/.local/bin/claude-sessions`) öffnet Claude-Code-Sitzungen nach einem Sitzungswechsel neu (nutzt Ghostty).

---

# Nachtrag (Stand später am 25.10.2026) – ersetzt widersprüchliche Angaben oben

## Wichtige Änderungen
- **Super-Taste ist kaputt** → ALLE Kombis laufen über **Strg+Alt** (`mainMod = "CTRL + ALT"`). Es gibt keinerlei Super-Binds mehr. Alt+Tab, Alt+F4 (harter Kill, gewollt) und Alt+Leertaste bleiben.
- **Maximieren** ist ein eigenes Maximieren (schwebendes Fenster in Arbeitsflächengröße, `DXSnap.toggleMax`), nicht Hyprlands „maximized". Grund: Hyprlands Zustand setzt ein Vollbild-Flag am Desktop, danach gehen Klicks an das falsche Fenster. Der Maximieren-Knopf der Apps wird über das Lua-Ereignis `window.fullscreen` in das eigene Maximieren umgewandelt.
- **Minimieren** = Fenster in den normalen, nie angezeigten Workspace `name:minimized`, Desktop/Position/Größe werden gemerkt und beim Zurückholen exakt wiederhergestellt, Animationen währenddessen aus (`no_anim`). Auslöser: Hyprland-IPC-Ereignis `minimized>>adresse,1` (Quickshell `Hyprland.onRawEvent`). Steam/XWayland: `~/.local/bin/dx-x11-iconify` liest `WM_CHANGE_STATE`; Steam maximiert sich nach dem Zurückholen selbst → 8 s Wächter in `Global.qml` (`guardUntil`).
- **Tiling/Zonen**: Fenster sind standardmäßig frei. `dx_tiling.lua` kachelt nur markierte Fenster; bevorzugtes Layout sind **eigene Zonen** (`dx_zones.lua`, Zonen kommen aus der Shell über `$XDG_RUNTIME_DIR/draconyx-zones.txt`). Raster-Editor (`GridEditor.qml`): Vorlagen, Trennlinien ziehen, Zonen teilen/entfernen. Shift beim Ziehen = Zonen anzeigen und einrasten. Ränder/Ecken andocken mit Vorschau (`dx_snap.lua`, `SnapPreview.qml`).
- **Desktop** (`Desktop.qml`): Wallpaper + Icons direkt in der Shell, nur auf den Monitoren aus `desktopMonitors`, Ziehrahmen/Strg+Klick-Mehrfachauswahl, nimmt nie Tastaturfokus. pcmanfm-qt wird nicht mehr genutzt.
- **Coding Space** (`CodeSpace.qml`, Knopf `</>` in der Taskleiste, Strg+Alt+K): findet `Code Space` auf der Code-Festplatte (`/run/media/<user>/*/Code Space`), pro Projekt Ordner (Dolphin), Terminal, VS Code, Claude, alles; öffnet auf Desktop 8 („Code").
- **Fenstermenü** (`WindowMenu.qml`, Alt+Leertaste) für Apps ohne Titelleiste (Dolphin, Kate): Maximieren, Minimieren, Raster, Monitor, Vordergrund, Schließen, Kill.
- **Startmenü 2.0** (Suche über Apps/Einstellungen/Dateien/Rechner, Ordner, Ziehen), **Task View** (Strg+Alt+Tab), **Alt+Tab mit Karten**, Fenster-Vorschau beim Hover.
- Einstellungen liegen in `~/.local/state/draconyx/settings.json` (NICHT im Shell-Ordner, sonst lädt jede Speicherung die Shell neu).

## Tastenkürzel (alle Strg+Alt + …)
Leertaste Startmenü · S Suche · A Schnelleinstellungen · N Benachrichtigungen · Tab Task View · K Coding Space · E Dolphin · T Terminal · B Browser · R Ausführen · L Sperren · V Zwischenablage · Q schließen · M minimieren · Shift+M zurückholen · Pfeile = Andocken (←→ Hälften, ↑ maximieren/Viertel, ↓ minimieren/zurück) · Shift+←/→ anderer Monitor · G Fenster ins Raster · Shift+G ganzer Desktop · H Raster-Vorlage wechseln · J Auto-Layout (Zonen/Raster/Spalten/Zeilen/Master) · Z Raster-Editor · X Zone fürs Fenster wählen · , und . Platz im Raster tauschen · Esc Maus befreien · 1–9 Desktops · Shift+1–9 Fenster verschieben · PgUp/PgDn Desktops · Shift+Q Notausgang (Hyprland beenden) · Alt+Tab Fensterwechsel · Alt+F4 Kill · Alt+Leertaste Fenstermenü · Alt oder Strg+Alt + Maus ziehen/skalieren.

## Fallen (Ergänzung)
- Shell **über Hyprland** starten (`hyprctl dispatch exec`), nicht aus einem Terminal: gestartete Apps erben dessen Umgebung (falsches `QT_QPA_PLATFORMTHEME` → weißes Dolphin).
- `pkill -f` in einem Tool-Befehl tötet die eigene Shell. Python-Ersetzungen in `Global.qml` immer eng begrenzen und vorher sichern (`~/.local/share/draconyx-backups/`).
- Qt/KDE-Apps haben unter Hyprland keine Fensterknöpfe (Alt+Leertaste-Menü als Ersatz; echte Lösung wäre das Plugin hyprbars über `hyprpm`, braucht `sudo pacman -S hyprpm`).
- Noch offen: Control Center 2.0 (WLAN-Liste, Bluetooth-Geräte, Ausgabegeräte, App-Lautstärken, Performance-Profile), eigenes Notification Center, Draconyx-Einstellungs-App, Alt+Tab-Vorschaubilder, Gaming-Modus mit automatischer Erkennung, Desktop-Widgets.

## Nachtrag: Coding Space, Git-Client, Wallpaper Engine, Desktop-Symbole
- **Coding Space** (`CodeSpace.qml`, Hilfsskript `~/.local/bin/dx-code-list`): Workspace = Ordner mit "Workspace" im Namen (Laufwerk-Wurzel + "Code Space"). Pro Projekt: IntelliJ, VS Code, Terminal, Claude (Logo, voller Pfad `~/.local/bin/claude`, weil Hyprlands PATH ~/.local/bin nicht enthält), Git. "+ Workspace" legt Ordner an, im Workspace "Klonen" (git clone, `owner/repo` = GitHub).
- **Git-Client** (`GitClient.qml`): hängt rechts am Coding Space (Layer-Fenster, nicht killbar per Alt+F4). Stagen per Klick/Pfeil/Ziehen, Commit, Verlauf mit Cherry-Pick/Revert/Reset, Branches (Rechtsklick: checkout/merge/rebase/löschen), Fetch/Pull(Rebase)/Push/Stash, Konflikt-Leiste (continue/abort). Erkennt gelöschte/umbenannte Remote-Branches (Upstream "gone", `ls-remote --symref`) und bietet Umstellen an. Prüft beim Öffnen und alle 60 s (`fetch --prune`).
- **Wallpaper Engine**: selbst gebaut aus `~/.local/src/linux-wallpaperengine` (Installation `~/.local/opt/linux-wallpaperengine`), Skripte `dx-we-run`, `dx-we-apply`, `dx-we-list`. Eigene Fixes: Web-Wallpaper-Textur (RenderHandler), Mausposition über Hyprland-IPC je Monitor. Desktop-Fenster liegt über der Engine (Remap beim Öffnen der Engine-Fläche); Schalter "Maus" im Picker reicht Klicks durch.
- **Desktop-Symbole**: freie Plätze (`iconPos` in settings.json), Ziehen auch auf andere Monitore.
- **Versteck-Desktop-Schutz**: Wechselt ein Monitor auf `minimized`, springt die Shell sofort zurück.
