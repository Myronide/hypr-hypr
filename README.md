# Draconyx — unsere Änderungen

Ordner für den Stand von SyntaxJason ("Draconyx"), zusammengeführt mit Myronides "Aurora" (Rest des Repos).

## Einrichten
```sh
sudo ./install.sh         # nur mit sudo-Freigabe; richtet alles ein, lädt Hyprland neu und startet die Shell neu
sudo ./install.sh --keymap=us   # Tastaturbelegung vorgeben: de = QWERTZ, us = QWERTY (sonst fragt der Installer einmal)
sudo ./install.sh --no-we # ohne Wallpaper Engine
```
Danach in Hyprland neu anmelden oder `qs -c draconyx` starten. Einstellungen: Zahnrad in der Taskleiste (öffnet die Aurora-Einstellungen).
Die Monitore erkennt der Installer selbst (`~/.config/hypr/monitors_local.lua`, nur wenn es sie noch nicht gibt). Anordnen wie unter Windows: Aurora-Einstellungen → Bildschirme (mit 15-Sekunden-Rückfrage, damit nie ein schwarzer Bildschirm übrig bleibt). Anzeigen: `dx-monitors show`.

## Inhalt
| Ordner | Was |
|---|---|
| `quickshell/` | Shell in QML: Taskleiste (Teile einzeln an/aus), Startmenü (Symbol wählbar), Alt+Tab, Task View, Desktop (Symbole frei ziehbar, mehrere Monitore), Coding Space + Git-Client, Wallpaper-Auswahl, Zonen-Editor |
| `hypr/` | `hyprland.lua` + `dx_snap` (Snap/Maximieren), `dx_tiling` (Kacheln, Standardmodus floating/tiling), `dx_zones`; Monitore in `monitors_local.lua` |
| `bin/` | `dx-*` Hilfsskripte: `dx-colors` (gemeinsame Farbwelt), `dx-terminal` (Terminal-Auswahl), Wallpaper Engine, Code-Liste |
| `patches/`, `wallpaper-engine/` | Fixes für linux-wallpaperengine (Web-Wallpaper, Mausposition) – `install.sh` baut es |
| `docs/` | Übergabe mit allen Entscheidungen und Fallstricken |
| Repo-Wurzel | `settings-app`, `preferences.py`, `settings.css`: Aurora-Einstellungen, neu gestylt, mit Seiten für Taskleiste, Coding Space, Fenstermodus, Farben, Terminal |

## Zusammengeführt (Cherry-Pick)
- **Von Aurora:** Farbwelt (Grau-Blau), Aussehen der Taskleiste, Einstellungs-App (umgestylt und erweitert), Terminal-Auswahl.
- **Von Draconyx:** Zonen-Raster, Snap/Maximieren, Coding Space, Git-Client, Wallpaper Engine in der Taskleiste, frei ziehbare Desktop-Symbole.
- **Gemeinsam steuerbar:** Farben (`~/.config/draconyx/colors.json`), Terminal (`~/.config/draconyx/terminal`), Fenstermodus (`~/.config/draconyx/window-mode`), Taskleiste (`~/.local/state/draconyx/settings.json`).

## Aurora läuft auf der Shell
Ist die Shell installiert, reichen `desktop-ui`, `start-desktop`, `start-dock` und `background-restore` nur noch an Quickshell weiter: kein waybar, kein GTK-Dock. Launcher, Alt+Tab, Fenstermodus und Minimieren-Knöpfe (über `dx-ui-bridge`) landen in der Shell. Altes Verhalten: `AURORA_LEGACY_UI=1`.


## Haupttaste (Super-Taste defekt oder fehlt)
Aurora-Einstellungen → Tastenkombinationen → **Haupttaste** (Datei `~/.config/draconyx/modifier`):
`super` (Standard) · `both` (Super und Strg+Alt) · `ctrl-alt` (Super aus, Strg+Alt ersetzt sie) · `caps` (Feststelltaste wird Super).
Strg+Leertaste öffnet die Suche nur auf dem leeren Desktop, in Apps bleibt die Taste unberührt.


## Neu: Schnellsuche, frei bindbare Tasten, Diagnose
- **Strg+Leertaste** öffnet auf dem leeren Desktop ein eigenes Suchfeld mittig mit Ergebnissen darunter (Apps, Rechner, Einstellungen, Dateien, Web); Rechtsklick auf ein Ergebnis: an Taskleiste/Start anheften, Datei öffnen, Ordner zeigen, Pfad kopieren. In Apps bleibt die Taste unberührt.
- **Alle Tastenkombinationen** sind in den Aurora-Einstellungen → Tastenkombinationen umbindbar (inkl. Maus wie Alt+Linksklick), gespeichert in `~/.config/draconyx/binds.conf`. Die Liste entsteht aus der geladenen Hyprland-Config (`dx_binds.lua`).
- **`dx-doctor`** schreibt einen Zustandsbericht nach `~/dx-doctor.txt` (laufende Prozesse, Config-Fehler, Dateien, Shell-Log); `dx-doctor --fix` beendet Doppelstarts (waybar, altes Aurora-Dock).


## Taskleiste: Anordnung
Jeder Teil der Taskleiste (Start, Suche, Apps, Tray, Uhr …) lässt sich in den Aurora-Einstellungen → Taskleiste → **Anordnung** auf *Links*, *Mitte* oder *Rechts* setzen, Reihenfolge mit den Pfeilen. Im Dock-Stil wird jeder Bereich zu einer eigenen schwebenden Insel (leere Bereiche verschwinden), im Leistenstil sind es drei Bereiche einer durchgehenden Leiste.

## Installer
`sudo ./install.sh` (oder ohne sudo: er verlangt dann zuerst die sudo-Freigabe). Er repariert Besitzer und Rechte, wendet nur Neues an und lädt anschließend Hyprland neu und startet die Shell neu. `--ask` fragt vor Paketen, `--restart` lädt auch ohne Änderung neu.


## Snip-Werkzeug und Foto-Editor
**Druck** (oder Strg+Alt+Umschalt+S) friert alle Bildschirme ein, dann Bereich aufziehen. **Übernehmen** (Enter) öffnet den Foto-Editor: Stift, Marker, Pfeil, Rechteck, Ellipse, Text, Verpixeln, Rückgängig (Strg+Z), dann Kopieren (Strg+C), Speichern (Strg+S) oder Beides. Strg+C / Strg+S direkt in der Auswahl kopieren/speichern ohne Editor. **Umschalt+Druck** kopiert und speichert den ganzen Bildschirm. Gespeichert wird in `~/Bilder/Screenshots/`.

## Kleine Helfer (1.5)
- **Zwischenablage** (Strg+Alt+V): Verlauf mit Suche und Bildvorschau. **Tastenkürzel** (Strg+Alt+I): alle wirksamen Kombinationen, durchsuchbar.
- **Fokus-Zeit** (Kalender → Fokus, Strg+Alt+P): Pomodoro, Timer, Stoppuhr; die Uhr zeigt die Restzeit, Pomodoro schaltet „Nicht stören“ ein.
- **Schnellsuche**: rechnet (auch Prozent, sqrt, sin …), rechnet Einheiten um („5 km in mi“), findet offene Fenster und Systemaktionen (sperren, Standby …).
- **Anzeigen**: Lautstärke-/Mikrofon-OSD, Datenschutz-Punkt in der Leiste (Mikrofon, Bildschirmfreigabe), optional Prozessor/Speicher in der Leiste.
- **Drop-down-Terminal** (Strg+Alt+Ö), **Mikrofon stumm** (Strg+Alt+U), **Text aus Screenshot** (Snip → „Text“, Strg+T).
- **Aurora**: „Energie & Sperre“ (hypridle), „Bewegung & Licht“ (Animationen, Nachtlicht mit Zeitplan).

## Bewusst NICHT drin
- Auroras Plugins (hyprbars, `aurora-native`): Sie lagen in einem Test im Weg und haben beim Laden in eine laufende Sitzung Hyprland zum Absturz gebracht. Nicht per Live-Reload laden. Wer sie nutzt, lädt sie nur beim Login.
