# Änderungsverlauf

Versionsnummer in der Datei `VERSION` (MAJOR.MINOR.PATCH). Bei jeder sichtbaren Änderung die Nummer erhöhen und hier eintragen –
die Update-Benachrichtigung in der Shell vergleicht diese Nummer mit der installierten.

## 1.3.1
- Update-Prüfung alle 30 Minuten statt alle 6 Stunden; Knopf „Jetzt prüfen“ in Aurora → System

## 1.3.0
- **Aurora im neuen Design:** Seitenleiste mit Symbolen und Gruppen, Karten-Zeilen, breite Bedienelemente unter dem Text, saubere Abschnittstitel.
- **Bildschirme wie unter Windows:** anordnen per Ziehen, Auflösung, Wiederholrate, Skalierung, Drehung, 15-Sekunden-Rückfrage. Bildschirme bleiben nach Updates erhalten (dx-monitors sync, Sicherheitsprüfung nach dem Neuladen).
- **Steam Workshop im Wallpaper-Fenster:** neuer Tab zum Stöbern (Beliebt, Neu, Top, Suche); Abonnieren öffnet die Seite in Steam, danach erscheint das Wallpaper unter „Meine Wallpaper“.
- **App-Installer (Aurora → Apps):** eigene Apps aus dem Repo, erste App „Notizen“; werden mit System-Updates aktualisiert.
- **Updates:** Hintergrund-Update mit Fortschrittsbalken und sudo-Dialog, Update-Anzeige in der Taskleiste mit Neuigkeiten, höchstens eine Meldung pro Tag, „Nicht mehr erinnern“, Aurora-Schalter. Eigene Einstellungen werden nie überschrieben.
- **Coding Space:** mehrere Ordner, frei wählbare Programme (IntelliJ, VS Code, Cursor, Zed, Sublime, PyCharm, WebStorm, Kate, Neovim …) und eigene; Claude nur wenn installiert.
- **Schriften:** 10 Voreinstellungen (Inter, Noto Sans, IBM Plex Sans, Roboto, Monaspace Krypton/Neon/Argon, JetBrains Mono, Fira Code, Cascadia Code) für Oberfläche und Code, in Aurora einstellbar und installierbar.
- **Alt+Tab:** Antippen springt sofort, Halten + Tab schaltet durch, Maus abschaltbar. **Fenstergröße merken** beim Schließen. **Tray-Menü** per Rechtsklick. **Quickinfos** an den Taskleistenknöpfen.
- **Terminal:** das eingestellte Terminal gilt überall, Ghostty nur wenn keins installiert ist; `dx-terminal-ensure` sorgt dafür, dass immer eins da ist.
- **Minimieren:** Electron-Apps (Discord & Co.) laufen über XWayland, damit das Minimieren-Symbol überall geht. Größere Liste der Apps mit eigener Titelleiste.
- **Installer:** Paketnamen-Alternativen, Tastaturwahl QWERTZ/QWERTY, portable hyprland.lua, Desktop-Ordner automatisch, keine persönlichen Monitordaten mehr im Repo.

## 1.2.2
- Update in den Einstellungen: Version, Stand und Aktualisieren-Knopf in einer Zeile (Knopf nur bei neuer Version), automatische Prüfung im Hintergrund

## 1.2.1
- Fortschrittsanzeige beim Update (oben rechts); Alt+Tab: Antippen springt sofort, Halten + Tab schaltet durch, Maus abschaltbar

## 1.2.0
- Update im Hintergrund (sudo-Dialog statt Terminal, Benachrichtigungen, Protokoll), sichert lokale Repo-Änderungen; Installer überschreibt keine Nutzereinstellungen (hyprland.lua nur wenn unverändert)

## 1.1.0
- Bildschirme wie unter Windows anordnen (Auflösung, Skalierung, Drehung, 15-s-Rückfrage), Monitor-Erkennung im Installer, Coding Space mit mehreren Ordnern, funktionierende Aufklapplisten und Ordnerwahl, Quickinfos, Update-Prüfung, Electron-Apps über XWayland, portable hyprland.lua, keine persönlichen Monitordaten mehr

## 1.0.0
- Erste versionierte Fassung: Draconyx-Shell (Taskleiste, Startmenü, Suche, Coding Space), Aurora als Einstellungs-App,
  Snip-Werkzeug mit Foto-Editor, Wallpaper Engine, rebindbare Tastenkombinationen, Installer mit Tastaturwahl, Update-Prüfung.
