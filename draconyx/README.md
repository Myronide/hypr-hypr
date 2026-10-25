# Draconyx — unsere Änderungen

Ordner für den Stand von SyntaxJason ("Draconyx"), zusammengeführt mit Myronides "Aurora" (Rest des Repos).

## Einrichten
```sh
./draconyx/install.sh              # Pakete (fragt vorher), Shell, Skripte, Wallpaper Engine bauen
./draconyx/install.sh --no-we      # ohne Wallpaper Engine
```
Danach in Hyprland neu anmelden oder `qs -c draconyx` starten. Einstellungen: Zahnrad in der Taskleiste (öffnet die Aurora-Einstellungen).
`~/.config/hypr/monitors_local.lua` ist eine Vorlage von SyntaxJason und muss an die eigenen Monitore angepasst werden (`hyprctl monitors`).

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

## Bewusst NICHT drin
- Auroras Plugins (hyprbars, `aurora-native`): Sie lagen in einem Test im Weg und haben beim Laden in eine laufende Sitzung Hyprland zum Absturz gebracht. Nicht per Live-Reload laden. Wer sie nutzt, lädt sie nur beim Login.
