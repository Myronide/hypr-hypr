# Draconyx — unsere Änderungen

Ordner für den Stand von SyntaxJason ("Draconyx"). Der Rest des Repos ist Myronides "Aurora".
Ziel: beide Welten vergleichen und per Cherry-Pick das Beste zusammenführen.

## Inhalt
| Ordner | Was |
|---|---|
| `hypr/` | `hyprland.lua` + Module `dx_snap` (Snap/Maximieren), `dx_tiling` (eigenes Raster), `dx_zones` (frei einstellbare Zonen), `hypridle`, `hyprlock` |
| `quickshell/` | Shell in QML: Taskleiste, Startmenü, Alt+Tab, Task View, Desktop (Symbole frei ziehbar, Multi-Monitor), Coding Space, Git-Client, Wallpaper-Auswahl, Zonen-Editor |
| `bin/` | Hilfsskripte `dx-*` (Wallpaper Engine, Code-Liste, X11-Minimieren), `claude-sessions` |
| `patches/` | Fixes für linux-wallpaperengine (Web-Wallpaper-Textur, Mausposition über Hyprland) |
| `docs/` | Übergabe-Dokument mit allen Entscheidungen und Fallstricken |

## Unterschiede zu Aurora (Stand der ersten Sichtung)
| Thema | Aurora (Myronide) | Draconyx |
|---|---|---|
| Shell/Dock | waybar + Python/GTK (`desktop-ui`) | Quickshell (QML), eine verbundene Leiste |
| Fenstertitel mit Knöpfen | hyprbars-Plugin + eigenes C++-Plugin (Minimieren) | keine Titelleisten; eigenes Minimieren/Maximieren per Skript, Alt+Leertaste-Menü |
| Tastenkürzel | `SUPER + …` | `STRG + ALT + …` (Super-Taste defekt) |
| Fenster-Modi | Tiling ↔ Desktop umschaltbar | Floating + eigenes Zonen-Raster |
| Launcher | rofi | eigenes Startmenü in QML |
| Wallpaper | eigenes natives Programm (`aurora-wallpaper`) | linux-wallpaperengine (selbst gebaut) |
| Einstellungen | `settings-app` / `control_center.py` | Einstellungen in `settings.json`, Control Center in QML |

## Cherry-Pick-Kandidaten (Vorschlag)
- **von Aurora → Draconyx:** hyprbars-Titelleisten mit echten Knöpfen (löst Qt/KDE ohne Buttons), natives Minimieren-Plugin, Einstellungs-App, Wallpaper-Programm.
- **von Draconyx → Aurora:** Zonen-Raster, Snap/Maximieren, Coding Space, Git-Client, Desktop-Symbole mit freier Anordnung.

## Noch zu tun, bevor beide es nutzen können
- Hartkodierte Pfade (`/home/syntaxjason`) durch `$HOME`/`Theme.home` ersetzen.
- Monitore pro Rechner in eine lokale Datei (nicht im Repo) auslagern.
- `settings.json` bleibt lokal.
