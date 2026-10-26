pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Zentraler Zustand und einzige Quelle der Wahrheit für alle Komponenten.
// Dauerhafte Einstellungen liegen in settings.json (wird live überwacht und gespeichert).
Singleton {
    id: root

    // =====================================================================
    // Popups
    // =====================================================================
    property bool startOpen: false
    property bool controlOpen: false
    property bool connOpen: false             // Verbindungen: Netzwerk, Bluetooth, Audio
    property string connTab: "net"
    property bool calendarOpen: false
    property string calTab: "cal"           // Reiter im Kalender: cal | focus
    property bool taskViewOpen: false
    property bool codeOpen: false
    property bool weOpen: false
    property bool searchOpen: false
    signal osdRequest(string icon, string label, real value)    // kurze Anzeige am Bildschirmrand
    property bool shortcutsOpen: false       // Tastenkürzel-Übersicht
    property bool clipOpen: false             // Zwischenablage-Verlauf
    property bool snipOpen: false
    // Solange das Snip-Werkzeug aufnimmt oder offen ist (oder der Foto-Editor), dürfen Fokuswechsel andere Fenster der Shell nicht schließen
    readonly property bool snipBusy: snipOpen || editOpen || snipCap.running
    property bool editOpen: false            // Foto-Editor für Snips
    property string editFile: ""
    property var snipFiles: ({})              // Monitor -> eingefrorenes Foto
    property string searchTest: ""           // nur für Tests: Text von außen in die Schnellsuche setzen
    property bool gitOpen: false
    property string gitRepo: ""
    property bool taskMenuOpen: false          // Rechtsklick-Menü / angeheftete Vorschau einer Taskleisten-App
    signal taskMenuClose()
    property var winMenu: null            // { addr, x, y }: Fenstermenü (Alt+Leertaste)
    property bool settingsOpen: false
    property bool taskPopupOpen: false
    property string taskPopupScreen: ""       // Monitor, auf dem das Fenster-Popup der Taskleiste offen ist
    property string popupScreen: ""
    readonly property bool anyPopup: startOpen || controlOpen || connOpen || calendarOpen || taskViewOpen || codeOpen || weOpen || taskPopupOpen

    // Ist auf GENAU diesem Monitor ein Popup offen? (Auto-Hide darf nur die Leiste dieses Monitors offen halten)
    function popupOpenOn(mon) {
        const big = startOpen || controlOpen || connOpen || calendarOpen || taskViewOpen || codeOpen || weOpen;
        return (big && popupScreen === mon) || (taskPopupOpen && taskPopupScreen === mon);
    }
    function sysPopupOn(mon) { return (controlOpen || connOpen || calendarOpen) && popupScreen === mon; }
    function closeAll() { connOpen = false; clipOpen = false; shortcutsOpen = false; editOpen = false; snipOpen = false; searchOpen = false; gitOpen = false; weOpen = false; startOpen = false; controlOpen = false; calendarOpen = false; taskViewOpen = false; codeOpen = false; }
    function focusedScreenName() { return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""; }
    function _toggle(prop, screenName) {
        const open = !root[prop];
        closeAll();
        popupScreen = screenName || focusedScreenName();
        root[prop] = open;
    }
    function toggleStart(s)    { _toggle("startOpen", s); }
    function toggleControl(s)  { _toggle("controlOpen", s); }
    function toggleConn(s)     { _toggle("connOpen", s); }
    function openConn(tab, s)  { connTab = tab; const was = connOpen; closeAll(); popupScreen = s || popupScreen || focusedScreenName(); connOpen = true; }
    function toggleCalendar(s) { _toggle("calendarOpen", s); }
    function toggleTaskView(s) { _toggle("taskViewOpen", s); }
    function toggleCode(s)     { _toggle("codeOpen", s); }
    function toggleWe(s)       { _toggle("weOpen", s); }
    function toggleSearchBox(s) { _toggle("searchOpen", s); }
    function toggleClip(s)     { _toggle("clipOpen", s); }
    function toggleShortcuts(s) { _toggle("shortcutsOpen", s); }
    // Hängt am Coding Space (bleibt offen); ohne ihn öffnet das Git-Feld allein am Fokus-Monitor
    function openGit(path) { if (!codeOpen) { closeAll(); popupScreen = focusedScreenName(); } gitRepo = path; gitOpen = true; }
    function screenAt(x, y) {
        for (const s of Quickshell.screens) if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) return s;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }
    function screenByName(name) {
        const list = Quickshell.screens;
        for (let i = 0; i < list.length; i++) if (list[i].name === name) return list[i];
        return list.length > 0 ? list[0] : null;
    }

    // =====================================================================
    // Einstellungen (dauerhaft)
    // =====================================================================
    property alias pinned:        settings.pinned
    property alias startPins:     settings.startPins
    property alias appFolders:    settings.appFolders
    property alias recentApps:    settings.recentApps
    property alias autohide:      settings.autohide
    property alias tooltips:      settings.tooltips
    property alias altTabMouse:   settings.altTabMouse
    property alias barRevealAnywhere: settings.barRevealAnywhere
    property alias notifiedUpdate: settings.notifiedUpdate
    property alias updateNotify:  settings.updateNotify
    property alias updateLastNotified: settings.updateLastNotified
    property alias updateMuted:   settings.updateMuted
    property alias barHeight:     settings.barHeight
    property alias barOpacity:    settings.barOpacity
    property alias barTop:        settings.barTop
    property alias barCenter:     settings.barCenter
    property alias iconSize:      settings.iconSize
    property alias groupApps:     settings.groupApps
    property alias showSeconds:   settings.showSeconds
    property alias monitorCfg:    settings.monitors
    property alias desktopMonitors: settings.desktopMonitors
    property alias wallpaper:     settings.wallpaper
    property alias wallpapers:    settings.wallpapers
    property alias weWallpapers:  settings.weWallpapers
    property alias weMouse:       settings.weMouse
    property alias iconPos:       settings.iconPos
    property alias gitSessions:   settings.gitSessions
    property alias startLogo:     settings.startLogo
    property alias barStyle:      settings.barStyle
    property alias barPartHide:   settings.barPartHide
    property alias barLayouts:    settings.barLayouts
    property alias fullscreenBar: settings.fullscreenBar
    property alias barItems:      settings.barItems
    property alias showDate:      settings.showDate
    property alias settingsCmd:   settings.settingsCmd
    property alias iconGrid:      settings.iconGrid
    property alias startLeft:     settings.startLeft
    property alias zoneLayouts:   settings.zoneLayouts
    property alias codeRoot:      settings.codeRoot
    property alias codeRoots:     settings.codeRoots
    property alias desktopDir:    settings.desktopDir
    property alias codeAppsOn:    settings.codeAppsOn
    property alias codeCustom:    settings.codeCustom
    property alias nightTemp:     settings.nightTemp
    property alias nightAuto:     settings.nightAuto
    property alias nightFrom:     settings.nightFrom
    property alias nightTo:       settings.nightTo
    property alias osdOn:         settings.osdOn
    property alias motion:        settings.motion
    property alias titleBars:     settings.titleBars
    property string tbDrag: ""              // Fenster (Adresse), das gerade an seiner Titelleiste gezogen wird
    readonly property int barMargin: 16

    Timer { id: retryTimer; interval: 800; onTriggered: settingsFile.reload() }
    FileView {
        id: settingsFile
        path: Theme.home + "/.local/state/draconyx/settings.json"
        watchChanges: true
        onFileChanged: reload()
        // Schutz vor dem Zurücksetzen der Einstellungen: nie vor dem ersten erfolgreichen Laden schreiben, und bei einem Ladefehler
        // einer vorhandenen Datei (halb geschrieben, kurz weg) NICHT die Standardwerte darüberschreiben – nur anlegen, wenn sie fehlt.
        property bool everLoaded: false
        onLoaded: everLoaded = true
        onAdapterUpdated: if (everLoaded) writeAdapter()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) { everLoaded = true; writeAdapter(); } else retryTimer.restart(); }

        JsonAdapter {
            id: settings
            property var pinned: ["org.kde.dolphin", "brave-browser", "com.mitchellh.ghostty", "discord-ptb", "steam", "com.microsoft.VSCode"]
            property var startPins: ["brave-browser", "firefox", "com.mitchellh.ghostty", "org.kde.dolphin", "discord-ptb", "steam",
                                     "com.microsoft.VSCode", "com.obsproject.Studio", "pavucontrol", "blueman-manager",
                                     "nwg-displays", "nwg-look"]
            property var appFolders: []          // [{ name: "Spiele", apps: ["steam", ...] }]
            property var recentApps: []
            property bool autohide: true
            property bool updateNotify: true         // Update-Benachrichtigungen überhaupt zeigen (Aurora → System)
            property real updateLastNotified: 0      // wann zuletzt gemeldet (Unixzeit): höchstens einmal pro Tag
            property string updateMuted: ""          // Version, für die der Nutzer "nicht mehr erinnern" gewählt hat
            property string notifiedUpdate: ""       // Version, für die schon eine Update-Meldung kam
            property bool barRevealAnywhere: false  // Schwebende Leiste: öffnet sich überall am Rand, nicht nur bei den Kapseln
            property bool altTabMouse: true         // Alt+Tab-Übersicht mit der Maus bedienbar (Klick, Hover, Mausrad)
            property bool tooltips: true            // Quickinfos beim Überfahren der Taskleistenknöpfe
            property int barHeight: 48
            property real barOpacity: 0.90
            property bool barTop: false
            property bool barCenter: true        // false = Apps linksbündig (Windows-10-Stil)
            property int iconSize: 26
            property bool groupApps: true
            property bool showSeconds: false
            property var monitors: ({})          // { "DP-1": { enabled: true, autohide: null } }
            property var desktopMonitors: []   // Desktop-Icons nur auf diesen Monitoren (leer = der erste Bildschirm)
            property string wallpaper: ""
            property var barItems: ({})            // { start, search, taskview, code, wallpaper, desktops, apps, tray, system, notifications, clock, showDesktop, mode, settings } an/aus
            property bool showDate: true            // Datum unter der Uhrzeit
            property string settingsCmd: ""         // Befehl der Einstellungs-App (leer = automatisch)
            property string fullscreenBar: "hover"   // Taskleiste bei Vollbild: "hover" = weg, am Rand einblendbar · "hide" = ganz weg · "show" = bleibt sichtbar
            property var barLayouts: ({})           // { bar: { left: [...], center: [...], right: [...] }, dock: {...} } Anordnung der Taskleisten-Teile
            property bool barPartHide: false        // Dock mit Auto-Hide: nur die Kapsel unter der Maus fährt hoch
            property string barStyle: "bar"     // "bar" = durchgehende Leiste, "dock" = schwebendes Dock (wie Aurora)
            property string startLogo: ""        // "" = Draconyx, "arch" = Arch-Logo, sonst Pfad zu einem eigenen Bild
            property var gitSessions: ({})        // { "Repo-Pfad": "Claude-Session-UUID" } je Repository eine fortlaufende Claude-Session
            property var iconPos: ({})            // { "Dateiname": { m: "DP-2", c: Spalte, r: Zeile } } Platz der Desktop-Symbole
            property var weMouse: []              // Monitore, auf denen die Maus ans Wallpaper (statt an die Desktop-Symbole) geht
            property var weWallpapers: ({})      // { "DP-1": "workshop-id" } Wallpaper Engine je Monitor
            property var wallpapers: ({})        // { "DP-1": "/pfad/bild.png" } überschreibt das Standard-Wallpaper
            property int iconGrid: 96            // Rasterbreite der Desktop-Icons
            property bool startLeft: true        // Startmenü links (Windows-10-Stil); false = mittig
            property var codeAppsOn: ["idea", "code"]   // Programme, die in der Projektliste als Knopf erscheinen (Aurora → Coding Space)
            property int nightTemp: 4500            // Nachtlicht: Farbtemperatur in Kelvin (niedriger = wärmer)
            property bool nightAuto: false          // Nachtlicht nach Zeitplan ein-/ausschalten
            property string nightFrom: "21:00"
            property string nightTo: "07:00"
            property real motion: 1.0               // Animationen: 0 = aus, 1 = normal, <1 schneller, >1 weicher/langsamer
            property bool titleBars: true           // eigene Titelleisten für schwebende Fenster ohne eigene Leiste (Dolphin & Co.)
            property bool osdOn: true               // Anzeige am Bildschirmrand bei Lautstärke/Mikrofon
            property var codeCustom: []             // eigene Programme: [{ id, name, cmd (mit {path}), term }]
            property string desktopDir: ""        // Ordner der Desktop-Symbole; leer = automatisch (xdg-user-dir DESKTOP)
            property var codeRoots: []              // weitere Ordner, die im Coding Space mitlaufen (zusätzlich zum Hauptordner)
            property string codeRoot: ""            // leer = automatisch: <Laufwerk>/Code Space unter /run/media/<user>/
            property var zoneLayouts: ({})       // { "DP-2": Teilungsbaum } eigene Zonen pro Monitor
        }
    }

    // Einstellung pro Monitor mit Rückfall auf global
    function monitorSetting(name, key, fallback) {
        const m = (settings.monitors || {})[name];
        return m && m[key] !== undefined && m[key] !== null ? m[key] : fallback;
    }
    function setMonitorSetting(name, key, value) {
        const all = Object.assign({}, settings.monitors || {});
        all[name] = Object.assign({}, all[name] || {}, { [key]: value });
        settings.monitors = all;
    }

    // =====================================================================
    // Coding Space: Projekte von der Code-Festplatte
    // =====================================================================
    property string codeRootAuto: ""
    property var projects: []           // [{ mtime, kind: "project"|"workspace", git, name, path }]
    property var codeStack: []          // betretene Workspace-Ordner (Pfade); leer = Wurzel
    readonly property string codeRootEffective: codeRoot !== "" ? codeRoot : codeRootAuto
    readonly property string codeCurrent: codeStack.length > 0 ? codeStack[codeStack.length - 1] : ""

    // Das Laufwerk heißt je nach Sitzung "Code" oder "Code1": "Code Space" auf allen Datenträgern suchen
    Process {
        id: codeRootProbe
        command: ["sh", "-c", "for d in /run/media/\"$USER\"/*/'Code Space'; do [ -d \"$d\" ] && echo \"$d\" && break; done"]
        stdout: SplitParser { onRead: line => { if (line) root.codeRootAuto = line; } }
    }
    // Ordner auflisten (Projekt oder Workspace). Auf der Wurzel kommen die *Workspace*-Ordner des Laufwerks dazu.
    Process {
        id: codeList
        property string dir: ""
        property string extra: ""
        property string roots: ""
        environment: ({ DX_CODE_ROOTS: roots })
        command: [Theme.home + "/.local/bin/dx-code-list", dir, extra]
        stdout: StdioCollector {
            onStreamFinished: {
                root.projects = text.split("\n").filter(l => l !== "").map(l => {
                    const p = l.split("\t");
                    return { mtime: Number(p[0]), kind: p[1], git: p[2] === "1", name: p[3], path: p[4] };
                });
            }
        }
    }
    onCodeRootsChanged: codeListTimer.restart()
    function refreshProjects() {
        probeCodeTools();
        codeRootProbe.running = false; codeRootProbe.running = true;
        codeListTimer.restart();
    }
    Timer {
        id: codeListTimer
        interval: 250
        onTriggered: {
            const rootDir = root.codeRootEffective;
            if (rootDir === "") { root.projects = []; return; }
            const cur = root.codeCurrent;
            codeList.running = false;
            codeList.dir = cur !== "" ? cur : rootDir;
            codeList.extra = (cur !== "" || root.codeRoot !== "") ? "" : rootDir.replace(/\/[^\/]+$/, "");   // Elternordner des Code Space = Laufwerk
            codeList.roots = cur !== "" ? "" : (root.codeRoots || []).join(":");                           // weitere Ordner nur in der Wurzelansicht
            codeList.running = true;
        }
    }
    function codeEnter(path) { codeStack = codeStack.concat([path]); projects = []; codeListTimer.restart(); }
    function codeBack() { codeStack = codeStack.slice(0, -1); projects = []; codeListTimer.restart(); }
    function codeReset() { codeStack = []; }

    // Git-Repository in den geöffneten Workspace klonen ("owner/repo" = GitHub, sonst volle URL)
    property string cloneStatus: ""        // "" | "läuft: <url>" | "fertig: <name>" | "Fehler: …"
    property string cloneOut: ""
    Process {
        id: cloneProc
        property string url: ""
        property string dir: ""
        workingDirectory: dir
        environment: ({ "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "true" })
        command: ["git", "clone", "--progress", url]
        stderr: SplitParser { onRead: line => { if (line.trim() !== "") root.cloneOut = line.trim(); } }
        onExited: code => {
            if (code === 0) root.cloneStatus = "fertig: " + cloneProc.url.replace(/\.git$/, "").replace(/.*[\/:]/, "");
            else root.cloneStatus = "Fehler: " + (root.cloneOut !== "" ? root.cloneOut : "Klonen fehlgeschlagen (Code " + code + ")");
            root.refreshProjects();
        }
    }
    function codeClone(input) {
        let u = input.trim();
        if (u === "" || codeCurrent === "" || cloneProc.running) return;
        if (/^[\w.-]+\/[\w.-]+$/.test(u)) u = "https://github.com/" + u;
        cloneOut = "";
        cloneProc.url = u;
        cloneProc.dir = codeCurrent;
        cloneStatus = "läuft: " + u.replace(/\.git$/, "").replace(/.*[\/:]/, "");
        cloneProc.running = true;
    }
    // Neuer Workspace-Ordner auf dem Code-Laufwerk (neben den anderen "… Workspace"-Ordnern); "Workspace" wird ergänzt
    function codeNewWorkspace(name) {
        let n = name.trim().replace(/[\/\\]/g, "");
        if (n === "" || codeRootEffective === "") return;
        if (!/workspace/i.test(n)) n += " Workspace";
        // Eigener Code-Space-Ordner (Aurora-Einstellungen): Workspaces entstehen darin; sonst neben dem automatisch gefundenen "Code Space"
        const base = codeRoot !== "" ? codeRoot : codeRootEffective.replace(/\/[^\/]+$/, "");
        Quickshell.execDetached(["mkdir", "-p", base + "/" + n]);
        codeListTimer.interval = 600; codeListTimer.restart();
    }

    // Desktop-Ordner: eingestellter Ordner, sonst der des Systems (Schreibtisch / Desktop)
    property string desktopDirAuto: ""
    readonly property bool desktopDirReady: desktopDir !== "" || desktopDirAuto !== ""
    readonly property string desktopDirEffective: desktopDir !== "" ? desktopDir : desktopDirAuto
    Process {
        id: desktopDirProbe
        command: ["sh", "-c", "d=$(xdg-user-dir DESKTOP 2>/dev/null); if [ -n \"$d\" ] && [ \"$d\" != \"$HOME\" ] && [ -d \"$d\" ]; then echo \"$d\"; elif [ -d \"$HOME/Schreibtisch\" ]; then echo \"$HOME/Schreibtisch\"; else echo \"$HOME/Desktop\"; fi"]
        stdout: SplitParser { onRead: line => { if (line) root.desktopDirAuto = line; } }
    }
    // Installierte Entwicklungsprogramme (dx-code-apps) und Claude: nur was wirklich da ist, wird angezeigt
    property var codeDetected: []
    property bool claudeAvailable: false
    Process {
        id: codeAppsProbe
        command: [Theme.home + "/.local/bin/dx-code-apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.codeDetected = text.split("\n").filter(l => l !== "").map(l => {
                    const p = l.split("\t");
                    return { id: p[0], name: p[1], cmd: p[2], desk: (p[3] || "").split(","), icon: p[4], term: p[5] === "1" };
                });
            }
        }
    }
    Process {
        id: claudeProbe
        command: ["sh", "-c", "command -v claude >/dev/null 2>&1 || [ -x \"$HOME/.local/bin/claude\" ]"]
        onExited: code => root.claudeAvailable = (code === 0)
    }
    function probeCodeTools() {
        codeAppsProbe.running = false; codeAppsProbe.running = true;
        claudeProbe.running = false; claudeProbe.running = true;
    }
    // Knöpfe in der Projektliste: ausgewählte erkannte Programme (in Erkennungsreihenfolge) + eigene
    readonly property var codeAppsShown: {
        const on = codeAppsOn || [];
        const out = codeDetected.filter(a => on.indexOf(a.id) >= 0);
        for (const c of (codeCustom || [])) if (on.indexOf(c.id) >= 0) out.push({ id: c.id, name: c.name, cmd: c.cmd, desk: [], icon: c.icon || "application-x-executable", term: !!c.term, custom: true });
        return out;
    }
    function codeAppIcon(a) {
        if (a.id === "idea" && intellijEntry) return iconFor(intellijEntry.id, intellijEntry);
        for (const d of (a.desk || [])) { const e = DesktopEntries.byId(d); if (e) return iconFor(e.id, e); }
        return Quickshell.iconPath(a.icon || "", "application-x-executable");
    }
    function codeAppById(id) {
        for (const a of codeAppsShown) if (a.id === id) return a;
        return null;
    }

    // IntelliJ-Eintrag der JetBrains Toolbox (Name der Desktop-Datei enthält eine Kennung)
    readonly property var intellijEntry: {
        for (const e of DesktopEntries.applications.values) if (e.id.startsWith("jetbrains-idea")) return e;
        return DesktopEntries.byId("idea");
    }

    // Projekt öffnen: erst auf den Desktop "Code" (8), dann das Programm dort starten
    property var codePending: []
    Timer {
        id: codeLaunchTimer
        interval: 260
        onTriggered: { for (const c of root.codePending) Quickshell.execDetached(c); root.codePending = []; }
    }
    function appCommand(a, path) {
        const tmpl = a.cmd.indexOf("{path}") >= 0 ? a.cmd.replace(/\{path\}/g, "\"$1\"") : a.cmd + " \"$1\"";
        const sh = ["sh", "-c", tmpl, "dx", path];
        return a.term ? [Theme.home + "/.local/bin/dx-terminal", "--dir", path, "--"].concat(sh) : sh;
    }
    function openProject(path, how) {
        closeAll();
        const list = [];
        if (how === "folder" || how === "all") list.push(["dolphin", path]);
        if (how === "term")   list.push([Theme.home + "/.local/bin/dx-terminal", "--dir", path]);
        if (how.indexOf("app:") === 0) { const a = codeAppById(how.substring(4)); if (a) list.push(appCommand(a, path)); }
        if (how === "all") for (const a of codeAppsShown) list.push(appCommand(a, path));
        if ((how === "claude" || how === "all") && claudeAvailable) list.push([Theme.home + "/.local/bin/dx-terminal", "--dir", path, "--", Theme.home + "/.local/bin/claude"]);
        hypr("hl.dsp.focus({ workspace = 8 })");
        codePending = list;
        codeLaunchTimer.restart();
    }

    // =====================================================================
    // Eigene Zonen (Raster-Editor): pro Monitor ein Teilungsbaum
    //   { k: "leaf" }  oder  { k: "split", dir: "v"|"h", r: 0..1, a: <Baum>, b: <Baum> }
    //   "v" = senkrechte Trennlinie (a links, b rechts), "h" = waagerecht (a oben, b unten)
    // =====================================================================
    property string gridMode: ""        // "" | "edit" | "pick" | "flash"
    property string gridScreen: ""
    property string zoneSel: ""         // Pfad der gewählten Zone ("a", "ba", ...), "*" = keine
    property var zoneHint: null         // { mon, idx } solange mit Shift gezogen wird

    readonly property var zonePresets: ({
        "Eins":      { k: "leaf" },
        "2 Spalten": { k: "split", dir: "v", r: 0.5, a: { k: "leaf" }, b: { k: "leaf" } },
        "3 Spalten": { k: "split", dir: "v", r: 0.3333, a: { k: "leaf" }, b: { k: "split", dir: "v", r: 0.5, a: { k: "leaf" }, b: { k: "leaf" } } },
        "2×2":       { k: "split", dir: "h", r: 0.5,
                       a: { k: "split", dir: "v", r: 0.5, a: { k: "leaf" }, b: { k: "leaf" } },
                       b: { k: "split", dir: "v", r: 0.5, a: { k: "leaf" }, b: { k: "leaf" } } },
        "Haupt + 2": { k: "split", dir: "v", r: 0.6, a: { k: "leaf" }, b: { k: "split", dir: "h", r: 0.5, a: { k: "leaf" }, b: { k: "leaf" } } },
        "1 : 2 : 1": { k: "split", dir: "v", r: 0.25, a: { k: "leaf" }, b: { k: "split", dir: "v", r: 0.6667, a: { k: "leaf" }, b: { k: "leaf" } } }
    })
    readonly property var zonePresetNames: ["Eins", "2 Spalten", "3 Spalten", "2×2", "Haupt + 2", "1 : 2 : 1"]

    function layoutFor(mon) {
        const t = (settings.zoneLayouts || {})[mon];
        return t && t.k ? t : zonePresets["2 Spalten"];
    }
    function cloneTree(t) { return JSON.parse(JSON.stringify(t)); }
    function nodeAt(t, path) {
        let n = t;
        for (const c of path) { if (!n || n.k !== "split") return null; n = (c === "a") ? n.a : n.b; }
        return n;
    }
    function setLayout(mon, tree) {
        const all = Object.assign({}, settings.zoneLayouts || {});
        all[mon] = tree;
        settings.zoneLayouts = all;
        zonesTimer.restart();
    }
    function applyPreset(mon, name) { setLayout(mon, cloneTree(zonePresets[name])); zoneSel = "*"; }
    function cyclePreset(mon) {
        const cur = JSON.stringify(layoutFor(mon));
        const i = zonePresetNames.findIndex(n => JSON.stringify(zonePresets[n]) === cur);
        applyPreset(mon, zonePresetNames[(i + 1) % zonePresetNames.length]);
        return zonePresetNames[(i + 1) % zonePresetNames.length];
    }
    function splitZone(mon, path, dir) {
        const t = cloneTree(layoutFor(mon));
        const n = nodeAt(t, path);
        if (!n || n.k !== "leaf") return;
        n.k = "split"; n.dir = dir; n.r = 0.5; n.a = { k: "leaf" }; n.b = { k: "leaf" };
        setLayout(mon, t); zoneSel = "*";
    }
    function removeZone(mon, path) {
        if (path === "" || path === "*") return;
        const t = cloneTree(layoutFor(mon));
        const parentPath = path.slice(0, -1);
        const parent = nodeAt(t, parentPath);
        if (!parent || parent.k !== "split") return;
        const keep = path.slice(-1) === "a" ? parent.b : parent.a;      // Geschwister bleibt
        if (parentPath === "") setLayout(mon, keep);
        else {
            const gp = nodeAt(t, parentPath.slice(0, -1));
            if (parentPath.slice(-1) === "a") gp.a = keep; else gp.b = keep;
            setLayout(mon, t);
        }
        zoneSel = "*";
    }
    function setRatio(mon, path, r) {
        const t = cloneTree(layoutFor(mon));
        const n = nodeAt(t, path);
        if (!n || n.k !== "split") return;
        n.r = Math.max(0.1, Math.min(0.9, r));
        setLayout(mon, t);
    }
    // nutzbare Fläche eines Monitors (lokal): Rand + Platz der Taskleiste, wenn sie fest sichtbar ist
    function zoneArea(screen) {
        const g = barMargin;
        let top = g, bottom = g;
        if (!autohide) { const bh = barHeight + barMargin * 2; if (barTop) top = bh; else bottom = bh; }
        return { x: g, y: top, w: screen.width - 2 * g, h: screen.height - top - bottom };
    }
    function computeLayout(tree, area) {
        const zones = [], dividers = [];
        const rec = (n, x, y, w, h, path) => {
            if (n.k === "leaf") { zones.push({ x: x, y: y, w: w, h: h, path: path }); return; }
            if (n.dir === "v") {
                const w1 = w * n.r;
                dividers.push({ path: path, dir: "v", x: x + w1, y: y, len: h, px: x, py: y, pw: w, ph: h });
                rec(n.a, x, y, w1, h, path + "a"); rec(n.b, x + w1, y, w - w1, h, path + "b");
            } else {
                const h1 = h * n.r;
                dividers.push({ path: path, dir: "h", x: x, y: y + h1, len: w, px: x, py: y, pw: w, ph: h });
                rec(n.a, x, y, w, h1, path + "a"); rec(n.b, x, y + h1, w, h - h1, path + "b");
            }
        };
        rec(tree, area.x, area.y, area.w, area.h, "");
        return { zones: zones, dividers: dividers };
    }

    // Zonen für Hyprland (dx_zones.lua) als Datei bereitstellen und Raster neu anwenden
    property string lastZonesText: ""
    Timer { id: zonesTimer; interval: 220; onTriggered: root.writeZones() }
    function writeZones() {
        let out = "";
        for (const s of Quickshell.screens) {
            const lay = computeLayout(layoutFor(s.name), zoneArea(s));
            lay.zones.forEach((z, i) => {
                out += s.name + " " + (i + 1) + " " + Math.round(s.x + z.x + 4) + " " + Math.round(s.y + z.y + 4)
                     + " " + Math.max(60, Math.round(z.w - 8)) + " " + Math.max(60, Math.round(z.h - 8)) + "\n";
            });
        }
        if (out === lastZonesText) return;
        lastZonesText = out;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$XDG_RUNTIME_DIR/draconyx-zones.txt\"", "sh", out]);
        hyprEval("if DXTiling then DXTiling.retileAll() end");
    }
    Connections { target: settingsFile; function onAdapterUpdated() { zonesTimer.restart(); } }

    function showZones(mon, mode) { gridScreen = mon || focusedScreenName(); gridMode = mode; zoneSel = "*"; }
    function closeGrid() { gridMode = ""; zoneSel = "*"; }
    function pickZone(idx) {
        closeGrid();
        hyprEval("DXZones.placePicked(" + idx + ")");
    }
    onGridModeChanged: if (gridMode === "flash") flashTimer.restart()
    Timer { id: flashTimer; interval: 1700; onTriggered: { if (root.gridMode === "flash") root.closeGrid(); } }

    // =====================================================================
    // Andock-Vorschau: dx_snap.lua schreibt "MONITOR x y w h" (oder "none") in diese Datei
    // =====================================================================
    property var snapRect: null
    FileView {
        id: snapFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/draconyx-snap.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const p = text().trim().split(/\s+/);
            if (p[0] === "zones" && p.length >= 7) {
                const idx = Number(p[2]);
                root.zoneHint = { mon: p[1], idx: idx };
                root.snapRect = idx > 0 ? { mon: p[1], x: Number(p[3]), y: Number(p[4]), w: Number(p[5]), h: Number(p[6]) } : null;
            } else {
                root.zoneHint = null;
                root.snapRect = p.length === 5
                    ? { mon: p[0], x: Number(p[1]), y: Number(p[2]), w: Number(p[3]), h: Number(p[4]) }
                    : null;
            }
        }
    }

    // =====================================================================
    // Angeheftete / zuletzt benutzte Apps
    // =====================================================================
    readonly property var aliases: ({
        "code": "com.microsoft.vscode",
        "code-url-handler": "com.microsoft.vscode",
        "brave": "brave-browser",
        "org.pulseaudio.pavucontrol": "pavucontrol",
        "dolphin": "org.kde.dolphin"
    })
    function normId(id) {
        const k = (id || "").toLowerCase().replace(/\.desktop$/, "");
        return aliases[k] || k;
    }
    function isPinned(id) {
        const k = normId(id);
        return (settings.pinned || []).some(p => normId(p) === k);
    }
    function togglePin(id) {
        const k = normId(id);
        const list = (settings.pinned || []).slice();
        const idx = list.findIndex(p => normId(p) === k);
        if (idx >= 0) list.splice(idx, 1); else list.push(id);
        settings.pinned = list;
    }
    function movePinned(fromIdx, toIdx) {
        const list = (settings.pinned || []).slice();
        if (fromIdx < 0 || fromIdx >= list.length) return;
        toIdx = Math.max(0, Math.min(list.length - 1, toIdx));
        if (fromIdx === toIdx) return;
        const [item] = list.splice(fromIdx, 1);
        list.splice(toIdx, 0, item);
        settings.pinned = list;
    }
    // Reihenfolge in einer der Listen ändern ("pinned" oder "startPins")
    function moveInList(name, fromIdx, toIdx) {
        const list = (settings[name] || []).slice();
        if (fromIdx < 0 || fromIdx >= list.length) return;
        toIdx = Math.max(0, Math.min(list.length - 1, toIdx));
        if (fromIdx === toIdx) return;
        const [item] = list.splice(fromIdx, 1);
        list.splice(toIdx, 0, item);
        settings[name] = list;
    }

    // App-Ordner im Startmenü: [{ name, apps: [ids] }]
    function folderOf(id) {
        const k = normId(id);
        for (const f of (settings.appFolders || []))
            if ((f.apps || []).some(a => normId(a) === k)) return f.name;
        return "";
    }
    function folderAddApp(folderName, id) {
        const k = normId(id);
        const all = (settings.appFolders || []).map(f => ({ name: f.name, apps: (f.apps || []).filter(a => normId(a) !== k) }));
        let f = all.find(x => x.name === folderName);
        if (!f) { f = { name: folderName, apps: [] }; all.push(f); }
        f.apps.push(id);
        settings.appFolders = all.filter(x => x.apps.length > 0);
    }
    function folderRemoveApp(id) {
        const k = normId(id);
        settings.appFolders = (settings.appFolders || [])
            .map(f => ({ name: f.name, apps: (f.apps || []).filter(a => normId(a) !== k) }))
            .filter(f => f.apps.length > 0);
    }
    function folderDissolve(folderName) {
        settings.appFolders = (settings.appFolders || []).filter(f => f.name !== folderName);
    }

    function toggleStartPin(id) {
        const k = normId(id);
        const list = (settings.startPins || []).slice();
        const idx = list.findIndex(p => normId(p) === k);
        if (idx >= 0) list.splice(idx, 1); else list.push(id);
        settings.startPins = list;
    }
    function isStartPinned(id) {
        const k = normId(id);
        return (settings.startPins || []).some(p => normId(p) === k);
    }
    function addRecent(id) {
        if (!id) return;
        const k = normId(id);
        const list = (settings.recentApps || []).filter(p => normId(p) !== k);
        list.unshift(id);
        settings.recentApps = list.slice(0, 12);
    }

    function entryFor(id) {
        if (!id) return null;
        return DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id);
    }
    function iconFor(id, entry) {
        if (entry && entry.icon) {
            if (entry.icon.startsWith("/")) return "file://" + entry.icon;
            return Quickshell.iconPath(entry.icon, "application-x-executable");
        }
        if (id && id.startsWith("steam_app_"))
            return Quickshell.iconPath("steam_icon_" + id.substring(10), "steam");
        return Quickshell.iconPath((id || "").toLowerCase(), "application-x-executable");
    }
    // Apps vollständig abgekoppelt starten (dx-launch): neue Sitzung, Ein-/Ausgabe nach /dev/null. Sonst können Apps wie Discord mit
    // "write EPIPE" abstürzen, wenn die Pipe ihres Starters (z. B. die Shell nach einem Neustart) verschwindet.
    function launchEntry(e) {
        if (e && !e.runInTerminal && e.command && e.command.length > 0)
            Quickshell.execDetached([Theme.home + "/.local/bin/dx-launch"].concat(e.command));
        else if (e) e.execute();
    }
    function launch(id, entry) {
        addRecent(entry ? entry.id : id);
        if (entry) launchEntry(entry); else run(id);
    }

    // =====================================================================
    // Fenster fokussieren (Wayland-activate zählt in Hyprland nur als "dringend")
    // =====================================================================
    function hyprFor(wl) {
        for (const h of Hyprland.toplevels.values) if (h.wayland === wl) return h;
        return null;
    }
    function addressOf(h) {
        const raw = String((h.lastIpcObject && h.lastIpcObject.address) || h.address || "");
        if (raw === "") return "";
        return raw.startsWith("0x") ? raw : "0x" + raw;
    }
    // Minimieren = Fenster in den versteckten Special-Workspace "minimized" legen (Hyprland kennt es nicht nativ)
    readonly property string minWs: "name:minimized"        // normaler, nie angezeigter Workspace
    readonly property string minWsName: "minimized"
    function wsNameOf(h) {
        if (!h) return "";
        if (h.workspace && h.workspace.name) return h.workspace.name;
        const o = h.lastIpcObject || {};
        return (o.workspace && o.workspace.name) || "";
    }
    function isMinimizedH(h) { return h ? wsNameOf(h) === minWsName : false; }
    function isMinimized(wl) { return isMinimizedH(hyprFor(wl)); }
    // Minimieren/Wiederherstellen ohne sichtbare Reise über die Monitore:
    //  - Fenster-Animation für die Dauer des Umzugs aus (no_anim)
    //  - beim Minimieren werden Desktop, Position und Größe gemerkt, beim Wiederherstellen genau so zurückgesetzt
    property var minState: ({})          // address -> { ws, x, y, w, h }
    property var pendingAnim: []
    Timer {
        id: animReset
        interval: 900
        onTriggered: {
            for (const a of root.pendingAnim) root.hypr("hl.dsp.window.set_prop({ window = \"address:" + a + "\", prop = \"no_anim\", value = \"0\" })");
            root.pendingAnim = [];
        }
    }
    function noAnim(a) {
        hypr("hl.dsp.window.set_prop({ window = \"address:" + a + "\", prop = \"no_anim\", value = \"1\" })");
        if (root.pendingAnim.indexOf(a) < 0) root.pendingAnim.push(a);
        animReset.restart();
    }
    function toplevelByAddr(a) {
        for (const h of Hyprland.toplevels.values) if (addressOf(h) === a) return h;
        return null;
    }
    // Minimieren macht die Hyprland-Konfiguration selbst (DXSnap.minimize: merkt sich Größe und Zustand, verschiebt ohne Animation) –
    // direkt über den Hyprland-Socket, ohne vorher hyprctl zu starten. Die Shell merkt sich nur den Desktop für das Zurückholen.
    function minimizeAddr(a) {
        const h = toplevelByAddr(a);
        const o = h ? (h.lastIpcObject || {}) : {};
        if (o.workspace && o.workspace.name !== root.minWsName) {
            const all = Object.assign({}, root.minState);
            all[a] = { ws: o.workspace.id };
            root.minState = all;
        }
        hypr("DXSnap.minimize('" + a + "')");
    }

    // Zurückholen: nur Desktop, Fokus und Reihenfolge macht die Shell. Größe und Maximiert-Zustand setzt die Hyprland-Konfiguration
    // (DXSnap.afterRestore) nach IHREM eigenen Zustand – was die App beim Minimieren mit ihrer Größe gemacht hat, spielt keine Rolle.
    function restoreAddr(a) {
        const st = root.minState[a];
        // Zurück auf den alten Desktop nur, wenn er gerade auf einem Monitor sichtbar ist – sonst auf den aktiven
        let ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
        if (st) for (const m of Hyprland.monitors.values) if (m.activeWorkspace && m.activeWorkspace.id === st.ws) ws = st.ws;
        console.log("EV restore " + a + " ws=" + ws);
        hypr("DXSnap.unminimize('" + a + "', " + ws + ")");
        hypr("hl.dsp.focus({ window = \"address:" + a + "\" })");
        raise(a);
    }
    // Fenster über alle anderen auf dem Bildschirm legen (sonst bleibt ein zurückgeholtes Fenster verdeckt)
    function raise(a) {
        raiseTimer.addr = a; raiseTimer.restart();
        hypr("hl.dsp.window.alter_zorder({ mode = \"top\", window = \"address:" + a + "\" })");
    }
    Timer { id: raiseTimer; property string addr: ""; interval: 220; onTriggered: root.hypr("hl.dsp.window.alter_zorder({ mode = \"top\", window = \"address:" + addr + "\" })") }
    function minimizeH(h) { const a = addressOf(h); if (a !== "") minimizeAddr(a); }
    function minimizeToplevel(wl) { minimizeH(hyprFor(wl)); }
    function restoreH(h) { const a = addressOf(h); if (a !== "") restoreAddr(a); }

    function focusHypr(h) {
        if (!h) return;
        if (isMinimizedH(h)) { restoreH(h); return; }
        const a = addressOf(h);
        if (a !== "") { hypr("hl.dsp.focus({ window = \"address:" + a + "\" })"); raise(a); }
    }
    function focusToplevel(wl) {
        const h = hyprFor(wl);
        if (h) focusHypr(h); else wl.activate();
    }
    function moveToWorkspace(h, id) {
        const a = addressOf(h);
        if (a !== "") hypr("hl.dsp.window.move({ window = \"address:" + a + "\", workspace = " + id + ", follow = false })");
    }

    // XWayland-Apps (z. B. Steam) minimieren über eine X-Nachricht, die Hyprland ignoriert: Wächter-Skript liest sie mit
    // Brücke für die Minimieren-Knöpfe des nativen Aurora-Plugins (aurora-ui.sock -> Shell); läuft nur mit der Shell
    Process { running: true; command: [Theme.home + "/.local/bin/dx-ui-bridge"] }

    property string lastIconify: ""
    property double lastIconifyAt: 0
    Timer { id: x11Restart; interval: 1500; onTriggered: x11Watch.running = true }
    Process {
        id: x11Watch
        running: true
        command: [Theme.home + "/.local/bin/dx-x11-iconify"]
        onExited: (code, status) => { console.log("EV x11-Wächter beendet (" + code + "), starte neu"); x11Restart.restart(); }   // nie ohne Wächter bleiben
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/^iconify (0x[0-9a-f]+)/);
                if (!m) return;
                const now = Date.now();
                if (m[1] === root.lastIconify && now - root.lastIconifyAt < 600) return;   // doppelte Meldung
                root.lastIconify = m[1]; root.lastIconifyAt = now;
                root.minimizeAddr(m[1]);
            }
        }
    }

    // Minimieren-Knopf von Apps: Hyprland sendet "minimized>>adresse,1|0" über den Event-Socket
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Fehlersuche: Ablauf rund ums Minimieren/Maximieren im Shell-Log festhalten (qs -c draconyx log | grep EV)
            if (["minimized", "fullscreen", "movewindowv2", "openwindow", "changefloatingmode", "windowtitlev2"].indexOf(event.name) >= 0)
                console.log("EV " + event.name + " " + event.data);
            // Sobald die Engine ihre Fläche öffnet, liegt sie über dem Desktop -> sofort den Desktop neu darüberlegen
            if (event.name === "openlayer" && String(event.data) === "linux-wallpaperengine") weRemapStart.restart();
            // Nie auf dem Versteck-Desktop landen: Hyprland fokussiert nach dem Minimieren manchmal das versteckte Fenster
            // (z. B. beim Öffnen des Startmenüs) und schaltet den Monitor dorthin -> sofort zurück zum vorigen Desktop
            if (event.name === "workspacev2" && String(event.data).endsWith(",minimized")) {
                console.log("EV zurück vom Versteck-Desktop");
                hypr("hl.dsp.focus({ workspace = \"previous\" })");
            }
            if (event.name !== "minimized" || !root.handleMinimized) return;
            const parts = String(event.data).split(",");
            const addr = parts[0].startsWith("0x") ? parts[0] : "0x" + parts[0];
            if (parts[1] === "1") root.minimizeAddr(addr); else root.restoreAddr(addr);
        }
    }

    // =====================================================================
    // Schalter
    // =====================================================================
    property var testSelect: null      // nur für Tests: Auswahlrahmen auf dem Desktop setzen
    property bool handleMinimized: true   // Test: Ereignis-Handler für Minimieren abschaltbar
    property string testQuery: ""      // nur für automatische Tests (IPC): Suchtext im Startmenü setzen
    property bool nightLight: false
    property bool gameMode: false
    property bool dnd: false
    property int notifCount: 0
    property string netType: "none"
    property string perfProfile: "balanced"
    property int lastWorkspace: 1

    function setNightLight(on) {
        nightLight = on;
        run(on ? "pkill -x hyprsunset; hyprsunset -t " + Math.max(1500, Math.min(6500, nightTemp)) : "pkill -x hyprsunset");
    }
    onNightTempChanged: if (nightLight) setNightLight(true)
    // Zeitplan: schaltet nur beim Übergang um, damit ein Handgriff (an/aus per Kachel) bis zur nächsten Grenze gilt
    property int _nightWas: -1
    function _minutes(s) { const m = /^(\d{1,2}):(\d{2})$/.exec(s || ""); return m ? Math.min(23, +m[1]) * 60 + Math.min(59, +m[2]) : 0; }
    function nightWanted() {
        const d = new Date(), now = d.getHours() * 60 + d.getMinutes();
        const a = _minutes(nightFrom), b = _minutes(nightTo);
        return a === b ? false : (a < b ? (now >= a && now < b) : (now >= a || now < b));
    }
    function nightTick() {
        if (!nightAuto) { _nightWas = -1; return; }
        const w = nightWanted() ? 1 : 0;
        if (w !== _nightWas) { _nightWas = w; if ((w === 1) !== nightLight) setNightLight(w === 1); }
    }
    Timer { interval: 30000; repeat: true; running: root.nightAuto; triggeredOnStart: true; onTriggered: root.nightTick() }
    onNightAutoChanged: { _nightWas = -1; nightTick(); }
    function setGameMode(on) {
        gameMode = on;
        hyprEval(on
            ? "hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false }, shadow = { enabled = false } } })"
            : "hl.config({ animations = { enabled = true }, decoration = { blur = { enabled = true }, shadow = { enabled = true } } })");
    }
    function setPerfProfile(p) {
        perfProfile = p;
        run("powerprofilesctl set " + p);
    }

    // =====================================================================
    // Hilfen
    // =====================================================================
    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }
    // Protokoll: was startet die Shell wann? (~/.local/state/draconyx/launch.log)
    function logLaunch(source, what) {
        Quickshell.execDetached(["sh", "-c", "printf '%s %s %s\\n' \"$(date +%T)\" \"$1\" \"$2\" >> \"$HOME/.local/state/draconyx/launch.log\"", "sh", source, what]);
    }
    function hypr(lua) { Hyprland.dispatch(lua); }
    function hyprEval(lua) { Quickshell.execDetached(["hyprctl", "eval", lua]); }
    // Klick auf den leeren Desktop: Hyprland merkt sich das Fenster, das gerade den Fokus hat. Solange sich der Fokus nicht ändert und
    // kein Fenster angeklickt wird, gilt der Desktop als "fokussiert" (Strg+Leertaste öffnet dann die Suche). Hyprland selbst gibt den
    // Fokus beim Klick auf leere Fläche sonst einfach an das letzte Fenster zurück.
    function desktopClicked() {
        hyprEval("local w = hl.get_active_window(); DX_DESK_CLICK = (w and w.address) or 'none'");
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

    // Benachrichtigungen (swaync): Anzahl + Nicht-stören-Status
    Process {
        running: true
        command: ["sh", "-c", "command -v swaync-client >/dev/null && exec swaync-client -swb || exec sleep infinity"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const j = JSON.parse(line);
                    root.notifCount = parseInt(j.text) || 0;
                    root.dnd = String(j.alt || "").startsWith("dnd");
                } catch (e) {}
            }
        }
    }

    // Netzwerk: nmcli im Hintergrund, ereignisbasiert (monitor) statt ständigem Abfragen
    Process {
        id: netState
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE device | grep ':connected$' | cut -d: -f1 | head -1"]
        stdout: SplitParser {
            onRead: line => { root.netType = line === "ethernet" ? "ethernet" : (line === "wifi" ? "wifi" : "none"); }
        }
    }
    Process {
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: line => { netDebounce.restart(); } }
    }
    Timer { id: netDebounce; interval: 400; onTriggered: netState.running = true }
    // ---------- Desktop-Symbole: freie Plätze im Raster, auch auf anderen Monitoren ----------
    function iconMetrics(mon) {
        for (const s of Quickshell.screens) if (s.name === mon) {
            const top = barTop ? barHeight + barMargin * 2 + 18 : 18;
            const bottom = barTop ? 18 : barHeight + barMargin * 2 + 18;
            return { cols: Math.max(1, Math.floor((s.width - 36) / iconGrid)), rows: Math.max(1, Math.floor((s.height - top - bottom) / (iconGrid + 14))) };
        }
        return { cols: 1, rows: 1 };
    }
    function _ik(m, c, r) { return m + ":" + c + ":" + r; }
    function iconFindFree(mon, c0, r0, occ) {
        const mt = iconMetrics(mon);
        c0 = Math.max(0, Math.min(mt.cols - 1, c0)); r0 = Math.max(0, Math.min(mt.rows - 1, r0));
        for (let d = 0; d <= mt.cols + mt.rows; d++)
            for (let c = c0 - d; c <= c0 + d; c++)
                for (let r = r0 - d; r <= r0 + d; r++) {
                    if (Math.max(Math.abs(c - c0), Math.abs(r - r0)) !== d) continue;
                    if (c < 0 || r < 0 || c >= mt.cols || r >= mt.rows) continue;
                    if (!occ[_ik(mon, c, r)]) return { m: mon, c: c, r: r };
                }
        return null;
    }
    // Neue Dateien ohne Platz: von oben nach unten, links nach rechts auf dem ersten Symbol-Monitor
    function iconAutoPlace(names) {
        const pos = Object.assign({}, iconPos); const occ = {}; let changed = false;
        for (const n of names) if (pos[n]) occ[_ik(pos[n].m, pos[n].c, pos[n].r)] = n;
        const mons = (desktopMonitors && desktopMonitors.length > 0) ? desktopMonitors : (Quickshell.screens.length ? [Quickshell.screens[0].name] : []);
        for (const n of names) {
            if (pos[n]) continue;
            let done = false;
            for (const m of mons) {
                const mt = iconMetrics(m);
                for (let c = 0; c < mt.cols && !done; c++)
                    for (let r = 0; r < mt.rows && !done; r++)
                        if (!occ[_ik(m, c, r)]) { pos[n] = { m: m, c: c, r: r }; occ[_ik(m, c, r)] = n; done = true; changed = true; }
                if (done) break;
            }
        }
        if (changed) iconPos = pos;
    }
    // moves: [{ name, m, c, r }] – Ziel-Zellen; belegte Plätze (von nicht bewegten Symbolen) werden zum nächsten freien
    function iconMove(moves) {
        const pos = Object.assign({}, iconPos); const moving = {};
        for (const mv of moves) moving[mv.name] = true;
        const occ = {};
        for (const n of Object.keys(pos)) if (!moving[n]) occ[_ik(pos[n].m, pos[n].c, pos[n].r)] = n;
        for (const mv of moves) {
            const spot = iconFindFree(mv.m, mv.c, mv.r, occ);
            if (!spot) continue;
            pos[mv.name] = spot; occ[_ik(spot.m, spot.c, spot.r)] = mv.name;
        }
        iconPos = pos;
        const mons = (desktopMonitors || []).slice(); let add = false;
        for (const mv of moves) if (mons.indexOf(pos[mv.name].m) < 0) { mons.push(pos[mv.name].m); add = true; }
        if (add) desktopMonitors = mons;
    }

    // ---------- Anordnung der Taskleiste: jeder Teil sitzt links, mittig oder rechts ----------
    readonly property var barItemIds: ["start", "search", "taskview", "code", "wallpaper", "mode", "desktops", "apps",
                                       "tray", "system", "notifications", "clock", "settings", "showDesktop", "update", "stats", "privacy"]
    function defaultLayout(style) {
        const tools = ["start", "search", "taskview", "code", "wallpaper", "mode", "desktops"];
        const sys = ["update", "privacy", "stats", "tray", "system", "notifications", "clock", "settings", "showDesktop"];
        if (style === "dock") return { left: [], center: tools.concat(["apps"]), right: sys };
        return { left: tools, center: ["apps"], right: sys };
    }
    // gespeicherte Anordnung bereinigen: unbekannte/doppelte Teile raus, fehlende an ihre Standard-Stelle
    function layoutSections(style) {
        const def = defaultLayout(style);
        const saved = (barLayouts || {})[style];
        if (!saved) return def;
        const seen = {}; const out = { left: [], center: [], right: [] };
        for (const sec of ["left", "center", "right"])
            for (const id of (saved[sec] || [])) if (barItemIds.indexOf(id) >= 0 && !seen[id]) { seen[id] = true; out[sec].push(id); }
        for (const sec of ["left", "center", "right"])
            for (const id of def[sec]) if (!seen[id]) { seen[id] = true; out[sec].push(id); }
        return out;
    }
    function sectionItems(style, section) { return layoutSections(style)[section].filter(id => item(id)); }
    function setBarLayout(style, sections) { const m = Object.assign({}, barLayouts); m[style] = sections; barLayouts = m; }
    function resetBarLayout(style) { const m = Object.assign({}, barLayouts); delete m[style]; barLayouts = m; }

    // Bestandteile der Taskleiste an/aus (Standard: an, außer "power" und "stats")
    function item(key) { const v = (barItems || {})[key]; return v === undefined ? ["power", "stats"].indexOf(key) < 0 : v === true; }
    function setItem(key, on) { const m = Object.assign({}, barItems); m[key] = on; barItems = m; }

    // Fenstermodus (Standard): "floating" oder "tiling" – Datei wird von Lua (DXTiling.setDefault) geschrieben
    property string windowMode: "floating"
    FileView {
        id: modeFile
        path: Theme.home + "/.config/draconyx/window-mode"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const v = text().trim(); root.windowMode = v === "tiling" ? "tiling" : "floating"; }
    }
    function setWindowMode(m) { windowMode = m; hyprEval("DXTiling.setDefault(\"" + m + "\")"); }
    function toggleWindowMode() { setWindowMode(windowMode === "tiling" ? "floating" : "tiling"); }
    function openSettings() {
        // Läuft die Einstellungs-App schon (ggf. minimiert), nur nach vorn holen: GApplication würde sonst nur ein nicht
        // sichtbares Wiedervorlegen anfordern, und Hyprland holt ein minimiertes Fenster dadurch nicht zurück.
        for (const t of ToplevelManager.toplevels.values) {
            if (/settings-app|aurora\.settings/i.test(t.appId || "") || t.title === "Aurora") { focusToplevel(t); return; }
        }
        // Mit dem nativen Aurora-Plugin (hyprbars + aurora-native) läuft die App als normales Wayland-Fenster: scharf auch bei
        // gebrochener Skalierung, Minimieren kommt über das Plugin an. Ohne Plugin über XWayland starten, damit das
        // Minimieren-Symbol des Fensters bei Hyprland ankommt (xdg-Minimieren wird dort sonst ignoriert).
        const app = "python3 \"$HOME/.config/hypr/aurora/settings-app\"";
        const c = settingsCmd !== "" ? settingsCmd
                : "if hyprctl plugin list 2>/dev/null | grep -q aurora-native; then exec " + app + "; else exec env GDK_BACKEND=x11 " + app + "; fi";
        Quickshell.execDetached(["sh", "-c", c]);
    }

    // Dock-Stil: Lage der Kapseln je Monitor (von der Leiste gemeldet), damit Menüs an der passenden Kapsel hängen
    property var dockGeom: ({})            // mon -> { x, w, sx, sw, screenW }
    function setDockGeom(mon, g) { const m = Object.assign({}, dockGeom); m[mon] = g; dockGeom = m; }
    function popupLeft() { const g = dockGeom[popupScreen]; return (barStyle === "dock" && g) ? Math.max(barMargin, g.x) : barMargin; }
    function popupRightMargin() { const g = dockGeom[popupScreen]; return (barStyle === "dock" && g) ? Math.max(8, g.screenW - (g.sx + g.sw)) : 14; }


    // ---------- System-Update (Draconyx selbst) ----------
    // dx-update check holt beim Remote die neueste Versionsnummer; bei einer neuen Version kommt einmal pro Version eine Meldung
    // mit Knopf "Aktualisieren" (öffnet ein Terminal: git pull + sudo ./install.sh).
    property var updateInfo: ({})
    property bool updateManual: false
    Process {
        id: updCheck
        command: [Theme.home + "/.local/bin/dx-update", "check", "--quiet"]
        onExited: updRead.reload()
    }
    FileView {
        id: updRead
        path: Theme.home + "/.local/state/draconyx/update.json"
        onLoaded: {
            try { root.updateInfo = JSON.parse(text()); } catch (e) { return; }
            const u = root.updateInfo;
            // Höchstens einmal pro Tag melden; "Nicht mehr erinnern" gilt für diese Version, der Schalter in Aurora für alles
            const now = Date.now() / 1000;
            const due = root.updateManual || (now - root.updateLastNotified > 86400);
            if (u.available && root.updateNotify && u.latest !== root.updateMuted && due) {
                root.updateLastNotified = now;
                updNotify.version = u.latest;
                updNotify.command = ["notify-send", "-a", "Draconyx", "-i", "system-software-update", "-w",
                    "-A", "update=Aktualisieren", "-A", "later=Später", "-A", "mute=Nicht mehr erinnern",
                    "Draconyx-Update " + u.latest + " verfügbar", "Installiert: " + u.installed + (u.notes && u.notes.length ? "\n• " + u.notes.slice(0, 4).join("\n• ") : "")];
                updNotify.running = false; updNotify.running = true;
            }
            root.updateManual = false;
        }
    }
    Process {
        id: updNotify
        property string version: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim();
                if (a === "update") root.runUpdate();
                else if (a === "mute") root.updateMuted = updNotify.version;
            }
        }
    }
    function checkUpdate(manual) { updateManual = !!manual; updCheck.running = false; updCheck.running = true; }
    function runUpdate() { Quickshell.execDetached([Theme.home + "/.local/bin/dx-update", "apply"]); }
    Timer { interval: 60 * 1000; running: true; repeat: true; onTriggered: root.checkUpdate(false) }
    Timer { interval: 20000; running: true; onTriggered: root.checkUpdate(false) }      // 20 Sekunden nach dem Start

    // ---------- Einstellungen sichern ----------
    // Alle 10 Minuten (und kurz nach dem Start) eine Kopie der gültigen settings.json: Notfall-Wiederherstellung (dx-settings-guard restore DATEI).
    Process { id: settingsSnap; command: [Theme.home + "/.local/bin/dx-settings-guard", "snapshot", Theme.home + "/.local/share/draconyx-backups/settings-auto.json"] }
    Timer { interval: 10 * 60 * 1000; running: true; repeat: true; onTriggered: { settingsSnap.running = false; settingsSnap.running = true; } }
    Timer { interval: 60000; running: true; onTriggered: { settingsSnap.running = false; settingsSnap.running = true; } }

    // ---------- Terminal-Wächter ----------
    // Es soll immer mindestens ein Terminal installiert sein (auch wenn Ghostty/Kitty deinstalliert wurden). dx-terminal-ensure
    // stellt die Einstellung auf ein vorhandenes um und installiert nur dann Ghostty, wenn gar keins mehr da ist.
    Process { id: termEnsure; command: [Theme.home + "/.local/bin/dx-terminal-ensure", "--quiet"] }
    Timer { interval: 3 * 3600 * 1000; running: true; repeat: true; onTriggered: { termEnsure.running = false; termEnsure.running = true; } }
    Timer { interval: 45000; running: true; onTriggered: { termEnsure.running = false; termEnsure.running = true; } }

    // ---------- Snip-Werkzeug ----------
    // snip("region"): alle Bildschirme einfrieren, Bereich aufziehen. snip("screen"): ganzen Bildschirm unter dem Fokus direkt kopieren+speichern.
    Process {
        id: snipCap
        onExited: root.snipOpen = true
    }
    function snip(mode) {
        if (snipOpen) { snipClose(0); return; }
        if (mode === "screen") {
            Quickshell.execDetached([Theme.home + "/.local/bin/dx-snip-crop", "--screen", focusedScreenName(), "both"]);
            return;
        }
        const dir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp";
        const files = {};
        let cmd = "";
        for (const s of Quickshell.screens) {
            const f = dir + "/draconyx-snip-" + s.name + ".png";
            files[s.name] = f;
            cmd += "grim -o '" + s.name + "' '" + f + "' & ";
        }
        snipFiles = files;
        snipCap.command = ["sh", "-c", cmd + "wait"];
        snipCap.running = false;
        snipCap.running = true;
    }
    // Ausschnitt (Pixel des eingefrorenen Fotos) in den Editor übernehmen
    Process {
        id: editProc
        stdout: StdioCollector {
            onStreamFinished: { const p = text.trim(); if (p !== "") { root.editFile = p; root.snipOpen = false; root.editOpen = true; } }
        }
    }
    function snipEdit(file, x, y, w, h, mon) {
        popupScreen = mon;
        editProc.command = [Theme.home + "/.local/bin/dx-snip-crop", file, String(x), String(y), String(w), String(h), "edit"];
        editProc.running = false; editProc.running = true;
    }
    function snipClose(delay) {
        if (delay > 0) { snipCloseTimer.interval = delay; snipCloseTimer.restart(); return; }
        snipOpen = false;
        Quickshell.execDetached(["sh", "-c", "sleep 2; rm -f \"${XDG_RUNTIME_DIR:-/tmp}\"/draconyx-snip-*.png"]);
    }
    Timer { id: snipCloseTimer; onTriggered: root.snipClose(0) }

    // Symbol des Startknopfs: Draconyx (Standard), Arch oder eigenes Bild
    readonly property string startLogoUrl: startLogo === "" ? Theme.logo
        : startLogo === "arch" ? "file:///usr/share/pixmaps/archlinux-logo.png"
        : "file://" + startLogo
    Process {
        id: logoPicker
        command: ["zenity", "--file-selection", "--title=Symbol für den Startknopf", "--file-filter=Bilder | *.png *.svg *.jpg *.jpeg *.webp"]
        stdout: StdioCollector { onStreamFinished: { const p = text.trim(); if (p !== "") root.startLogo = p; } }
    }
    function pickStartLogo() { logoPicker.running = false; logoPicker.running = true; }

    // Wallpaper Engine: je Monitor ein Wallpaper; ein Prozess für alle Monitore
    function weSet(mon, id) {
        const m = Object.assign({}, weWallpapers);
        if (id === "" || m[mon] === id) delete m[mon]; else m[mon] = id;
        weWallpapers = m;
        weApply();
    }
    // Die Engine liegt auf derselben Ebene wie der Desktop und käme sonst über die Symbole:
    // Desktop kurz ausblenden, damit er danach wieder obenauf liegt
    property bool weRemap: false
    Timer { id: weRemapStart; interval: 60; onTriggered: { root.weRemap = true; weRemapEnd.restart(); } }
    Timer { id: weRemapEnd; interval: 120; onTriggered: root.weRemap = false }
    function weApply() {
        const args = [Theme.home + "/.local/bin/dx-we-apply"];
        for (const k of Object.keys(weWallpapers)) args.push(k + "=" + weWallpapers[k]);
        Quickshell.execDetached(args);
    }
    Timer { interval: 4000; running: true; onTriggered: if (Object.keys(root.weWallpapers).length > 0) root.weApply() }

    Component.onCompleted: {
        hyprEval("hl.config({ cursor = { no_warps = true } })");   // Maus springt beim Fokuswechsel nicht in die Fenstermitte
        netState.running = true;
        probeCodeTools();
        desktopDirProbe.running = true;
        perfRead.running = true;
        zonesTimer.restart();
        Quickshell.execDetached(["sh", "-c", "[ -f \"$XDG_RUNTIME_DIR/draconyx-snap.txt\" ] || echo none > \"$XDG_RUNTIME_DIR/draconyx-snap.txt\""]);
    }

    // Performance-Profil lesen
    Process {
        id: perfRead
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser { onRead: line => { if (line) root.perfProfile = line.trim(); } }
    }

    // =====================================================================
    // App-Badges und Fortschritt (com.canonical.Unity.LauncherEntry, von Electron-Apps u. a.)
    // =====================================================================
    property var badges: ({})      // normId -> { count, countVisible, progress, progressVisible }
    function badgeFor(id) { return badges[normId(id)] || null; }

    Process {
        running: true
        command: ["dbus-monitor", "--session", "type='signal',interface='com.canonical.Unity.LauncherEntry',member='Update'"]
        stdout: SplitParser {
            property string uri: ""
            property string key: ""
            property var cur: ({})
            onRead: line => {
                if (line.indexOf("member=Update") >= 0) { uri = ""; key = ""; cur = {}; return; }
                const sm = line.match(/^\s*string "(.*)"$/);
                if (sm) {
                    const s = sm[1];
                    if (s.startsWith("application://")) { uri = s.substring(14); return; }
                    key = s;
                    return;
                }
                const vm = line.match(/^\s*variant\s+(int32|int64|uint32|uint64|double|boolean)\s+(\S+)/);
                if (vm && uri !== "") {
                    const val = vm[1] === "boolean" ? vm[2] === "true" : Number(vm[2]);
                    cur[key] = val;
                    const id = root.normId(uri);
                    const all = Object.assign({}, root.badges);
                    all[id] = {
                        count: cur["count"] !== undefined ? cur["count"] : ((all[id] || {}).count || 0),
                        countVisible: cur["count-visible"] !== undefined ? cur["count-visible"] : ((all[id] || {}).countVisible || false),
                        progress: cur["progress"] !== undefined ? cur["progress"] : ((all[id] || {}).progress || 0),
                        progressVisible: cur["progress-visible"] !== undefined ? cur["progress-visible"] : ((all[id] || {}).progressVisible || false)
                    };
                    root.badges = all;
                }
            }
        }
    }
}
