import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Startmenü 2.0: Suche (Apps, Einstellungen, Dateien, Rechner), angeheftete Apps (ziehbar, mit Ordnern),
// Empfohlen (zuletzt benutzt), Alle Apps nach Kategorien, Schnellzugriff auf Ordner, Systemaktionen.
PanelWindow {
    id: menu
    visible: Global.startOpen
    screen: Global.screenByName(Global.popupScreen)

    anchors.bottom: !Global.barTop
    anchors.top: Global.barTop
    anchors.left: Global.startLeft
    margins.left: Global.popupLeft()
    margins.bottom: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.top: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    implicitWidth: 724
    implicitHeight: 760
    exclusionMode: ExclusionMode.Ignore      // Abstand zur Leiste kommt aus den Rändern; die Leisten-Reservierung nicht doppelt rechnen
    color: "transparent"
    WlrLayershell.namespace: "draconyx-start"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand statt Exclusive: Exclusive blockiert in Hyprland auch Mausklicks
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property string query: ""
    property bool showAll: false
    property string confirm: ""        // Ein/Aus-Aktion, die einen zweiten Klick braucht
    property var ctx: null             // { x, y, entry | folder } Kontextmenü
    property string openFolder: ""     // geöffneter App-Ordner
    property var fileHits: []
    property var recentFiles: []
    property int sel: 0

    onVisibleChanged: {
        if (visible) {
            query = ""; showAll = false; confirm = ""; ctx = null; openFolder = ""; sel = 0;
            search.text = "";
            search.forceActiveFocus();
            recentProc.running = false; recentProc.running = true;
        }
    }

    HyprlandFocusGrab {
        windows: [menu]
        active: menu.visible
        onCleared: Global.startOpen = false
    }

    // Testhaken: Suchtext von außen setzen (IPC "shell search <text>")
    Connections {
        target: Global
        function onTestQueryChanged() { if (menu.visible) search.text = Global.testQuery; }
    }

    function launch(entry) {
        if (!entry) return;
        Global.launch(entry.id, entry);
        Global.startOpen = false;
    }
    function openPath(path) {
        Global.logLaunch("startmenue-datei", path);
        Global.startOpen = false;
        if (path.endsWith("/")) Quickshell.execDetached(["dolphin", path]);
        else Quickshell.execDetached(["xdg-open", path]);
    }

    // ---------- Daten ----------
    readonly property var allApps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    function categoryOf(e) {
        const c = (e.categories || []).map(x => x.toLowerCase());
        const has = k => c.indexOf(k) >= 0;
        if (has("game")) return "Spiele";
        if (has("network") || has("webbrowser") || has("email") || has("chat") || has("instantmessaging")) return "Internet & Kommunikation";
        if (has("development") || has("ide")) return "Entwicklung";
        if (has("audiovideo") || has("audio") || has("video") || has("player") || has("music")) return "Multimedia";
        if (has("graphics") || has("photography")) return "Grafik";
        if (has("office")) return "Büro";
        if (has("settings") || has("system") || has("monitor") || has("terminalemulator")) return "System";
        if (has("utility")) return "Zubehör";
        return "Sonstiges";
    }
    readonly property var categoryOrder: ["Spiele", "Internet & Kommunikation", "Entwicklung", "Multimedia", "Grafik", "Büro", "Zubehör", "System", "Sonstiges"]
    readonly property var allModel: {
        const groups = {};
        for (const e of allApps) {
            const c = categoryOf(e);
            (groups[c] = groups[c] || []).push(e);
        }
        const out = [];
        for (const c of categoryOrder) {
            if (!groups[c]) continue;
            out.push({ header: c });
            for (const e of groups[c]) out.push({ entry: e });
        }
        return out;
    }

    // Einstellungen, die die Suche findet
    readonly property var settingsItems: [
        { name: "Audio & Lautstärke",   kw: "audio ton sound lautstärke mikrofon",   icon: "vol",      cmd: ["pavucontrol"] },
        { name: "Netzwerk & WLAN",      kw: "netzwerk wlan wifi internet lan",       icon: "wifi",     cmd: ["nm-connection-editor"] },
        { name: "Bluetooth",            kw: "bluetooth geräte kopfhörer",            icon: "bt",       cmd: ["blueman-manager"] },
        { name: "Bildschirme & HDR",    kw: "bildschirm monitor display auflösung hdr refresh", icon: "desktop", cmd: ["nwg-displays"] },
        { name: "Aussehen (GTK)",       kw: "aussehen theme design gtk schrift",     icon: "settings", cmd: ["nwg-look"] },
        { name: "Hyprland-Konfiguration", kw: "hyprland config tastenkürzel autostart fenster", icon: "window", cmd: ["xdg-open", Theme.home + "/.config/hypr/hyprland.lua"] },
        { name: "Draconyx Shell Einstellungen", kw: "draconyx leiste taskleiste startmenü einstellungen shell", icon: "taskbar", cmd: ["xdg-open", Theme.home + "/.local/state/draconyx/settings.json"] }
    ]

    // Rechner: einfache Ausdrücke
    function calc(q) {
        const t = q.trim().replace(/,/g, ".");
        if (!/^[0-9+\-*/().%\s^]+$/.test(t) || !/[+\-*/%^]/.test(t.replace(/^-/, ""))) return null;
        try {
            const v = Function('"use strict"; return (' + t.replace(/\^/g, "**") + ")")();
            if (typeof v === "number" && isFinite(v)) return Math.round(v * 1e10) / 1e10;
        } catch (e) {}
        return null;
    }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (q === "") return [];
        const out = [];
        const c = calc(query);
        if (c !== null) { out.push({ header: "Rechner" }); out.push({ kind: "calc", value: c }); }

        const apps = [];
        for (const e of allApps) {
            const name = (e.name || "").toLowerCase();
            const hay = [name, (e.genericName || "").toLowerCase(), (e.comment || "").toLowerCase(),
                         (e.keywords || []).join(" ").toLowerCase()].join(" ");
            if (!hay.includes(q)) continue;
            apps.push({ e: e, s: name.startsWith(q) ? 0 : (name.includes(q) ? 1 : 2) });
        }
        apps.sort((a, b) => a.s - b.s || a.e.name.localeCompare(b.e.name));
        if (apps.length > 0) {
            out.push({ header: "Apps" });
            for (const a of apps.slice(0, 8)) out.push({ kind: "app", entry: a.e });
        }

        const sets = settingsItems.filter(s => (s.name + " " + s.kw).toLowerCase().includes(q));
        if (sets.length > 0) {
            out.push({ header: "Einstellungen" });
            for (const s of sets.slice(0, 4)) out.push({ kind: "setting", item: s });
        }

        if (fileHits.length > 0) {
            out.push({ header: "Dateien" });
            for (const f of fileHits.slice(0, 7)) out.push({ kind: "file", path: f });
        }
        out.push({ header: "Weitere Optionen" });
        out.push({ kind: "web", text: query.trim() });
        return out;
    }
    // Auswahl nur auf auswählbaren Zeilen (keine Überschriften)
    function selectable(i) { return results[i] && results[i].header === undefined; }
    function moveSel(d) {
        let i = sel;
        for (let n = 0; n < results.length; n++) {
            i = (i + d + results.length) % results.length;
            if (selectable(i)) { sel = i; resultList.positionViewAtIndex(i, ListView.Contain); return; }
        }
    }
    function firstSelectable() { for (let i = 0; i < results.length; i++) if (selectable(i)) return i; return 0; }
    function activateResult(r) {
        if (!r || r.header !== undefined) return;
        Global.logLaunch("startmenue-suche", r.kind + ":" + (r.path || (r.item && r.item.name) || (r.entry && r.entry.id) || r.text || r.value));
        if (r.kind === "app") launch(r.entry);
        else if (r.kind === "setting") { Global.startOpen = false; Quickshell.execDetached(r.item.cmd); }
        else if (r.kind === "file") openPath(r.path);
        else if (r.kind === "calc") { Quickshell.execDetached(["wl-copy", String(r.value)]); Global.startOpen = false; }
        else if (r.kind === "web") { Global.startOpen = false; Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(r.text)]); }
    }

    // Dateisuche über plocate (nur eigene, sichtbare Dateien)
    Timer {
        id: fileDebounce
        interval: 220
        onTriggered: {
            if (menu.query.trim().length >= 2) { plocate.running = false; plocate.running = true; }
            else menu.fileHits = [];
        }
    }
    Process {
        id: plocate
        command: ["sh", "-c", "plocate -i -l 80 -b -- \"$1\" 2>/dev/null | grep -E \"^$2/\" | grep -vE '/\\.|/node_modules/' | head -7", "sh", menu.query.trim(), Theme.home]
        stdout: StdioCollector { onStreamFinished: menu.fileHits = text.split("\n").filter(l => l !== "") }
    }
    // Zuletzt geänderte Dateien in den Standardordnern
    Process {
        id: recentProc
        command: ["sh", "-c", "find \"$HOME/Downloads\" \"$HOME/Dokumente\" \"$HOME/Bilder\" \"$HOME/Videos\" \"$HOME/Musik\" \"$HOME/Schreibtisch\" -maxdepth 2 -type f -not -name '.*' -not -name '*.crdownload' -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -6 | cut -f2"]
        stdout: StdioCollector { onStreamFinished: menu.recentFiles = text.split("\n").filter(l => l !== "") }
    }

    readonly property var pinnedItems: {
        const out = [];
        for (const id of (Global.startPins || [])) {
            if (Global.folderOf(id) !== "") continue;
            const e = Global.entryFor(id);
            if (e) out.push({ kind: "app", entry: e, id: id });
        }
        for (const f of (Global.appFolders || [])) out.push({ kind: "folder", name: f.name, apps: f.apps });
        return out;
    }
    readonly property var recentEntries: (Global.recentApps || []).map(id => Global.entryFor(id)).filter(e => e).slice(0, 6)
    readonly property var folderLinks: [
        { name: "Downloads", icon: "folder", path: Theme.home + "/Downloads" },
        { name: "Dokumente", icon: "folder", path: Theme.home + "/Dokumente" },
        { name: "Bilder",    icon: "folder", path: Theme.home + "/Bilder" },
        { name: "Videos",    icon: "folder", path: Theme.home + "/Videos" },
        { name: "Musik",     icon: "music",  path: Theme.home + "/Musik" },
        { name: "Schreibtisch", icon: "desktop", path: Theme.home + "/Schreibtisch" }
    ]

    function fileName(p) { return p.substring(p.lastIndexOf("/") + 1); }
    function fileDir(p) { const d = p.substring(0, p.lastIndexOf("/")); return d.replace(Theme.home, "~"); }
    function fileIcon(p) {
        const s = p.substring(p.lastIndexOf(".") + 1).toLowerCase();
        if (["png", "jpg", "jpeg", "webp", "gif"].indexOf(s) >= 0) return "image-x-generic";
        if (["mp4", "mkv", "webm", "mov", "avi"].indexOf(s) >= 0) return "video-x-generic";
        if (["mp3", "wav", "ogg", "flac"].indexOf(s) >= 0) return "audio-x-generic";
        if (["zip", "7z", "rar", "tar", "gz", "zst"].indexOf(s) >= 0) return "package-x-generic";
        if (s === "pdf") return "application-pdf";
        return "text-x-generic";
    }

    // =====================================================================
    Surface {
        anchors.fill: parent
        level: 2
        radius: Theme.rXl

        // ---------- Suche ----------
        Rectangle {
            id: searchBox
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 22
            height: 46
            radius: 23
            color: Theme.tile
            border.color: search.activeFocus ? Theme.accent : Theme.borderSoft
            Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

            Icon { id: searchIcon; name: "search"; size: 18; anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter }
            TextInput {
                id: search
                anchors.left: searchIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.fsL
                clip: true
                onTextChanged: {
                    menu.query = text;
                    menu.ctx = null;
                    menu.sel = menu.firstSelectable();
                    fileDebounce.restart();
                }
                Keys.onEscapePressed: {
                    if (menu.ctx || menu.openFolder !== "") { menu.ctx = null; menu.openFolder = ""; }
                    else Global.startOpen = false;
                }
                Keys.onReturnPressed: { if (menu.query !== "") menu.activateResult(menu.results[menu.sel]); }
                Keys.onDownPressed: { if (menu.query !== "") menu.moveSel(1); }
                Keys.onUpPressed: { if (menu.query !== "") menu.moveSel(-1); }

                Text {
                    visible: search.text === ""
                    text: "Nach Apps, Einstellungen und Dateien suchen …"
                    color: Theme.textDim
                    font: search.font
                }
            }
        }

        // ---------- Inhalt ----------
        Item {
            id: body
            anchors.top: searchBox.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            clip: true

            // ===== Startansicht =====
            Flickable {
                id: home
                anchors.fill: parent
                visible: menu.query === "" && !menu.showAll
                contentHeight: homeCol.implicitHeight + 12
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: homeCol
                    width: parent.width
                    spacing: 10

                    Item {
                        width: parent.width; height: 30
                        Text { text: "Angeheftet"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        BarButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 30; padding: 12; radiusSize: 15
                            color: hovered ? Theme.tileHover : Theme.tile
                            Row {
                                spacing: 6
                                Text { text: "Alle Apps"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                                Icon { name: "chevron-right"; size: 14; anchors.verticalCenter: parent.verticalCenter }
                            }
                            onClicked: menu.showAll = true
                        }
                    }

                    Flow {
                        id: pinFlow
                        width: parent.width
                        Repeater {
                            model: menu.pinnedItems
                            delegate: AppTile {
                                id: pinTile
                                required property var modelData
                                readonly property bool isFolder: modelData.kind === "folder"
                                label: isFolder ? modelData.name : modelData.entry.name
                                iconSource: isFolder ? "" : Global.iconFor(modelData.entry.id, modelData.entry)
                                folderIcons: isFolder ? modelData.apps.map(a => Global.iconFor(a, Global.entryFor(a))) : []
                                draggable: !isFolder
                                slotW: Math.floor(pinFlow.width / 6)
                                onActivated: { if (isFolder) menu.openFolder = modelData.name; else menu.launch(modelData.entry); }
                                onMenuRequested: (x, y) => {
                                    const p = menuRoot.mapFromItem(null, x, y);
                                    menu.ctx = isFolder ? { x: p.x, y: p.y, folder: modelData.name } : { x: p.x, y: p.y, entry: modelData.entry };
                                }
                                onDropped: (dx, dy) => {
                                    if (isFolder) return;
                                    const shift = Math.round(dx / slotW) + 6 * Math.round(dy / slotH);
                                    const ids = Global.startPins || [];
                                    const from = ids.findIndex(p => Global.normId(p) === Global.normId(modelData.id));
                                    if (shift !== 0 && from >= 0) Global.moveInList("startPins", from, from + shift);
                                }
                            }
                        }
                    }

                    Item { width: 1; height: 6 }

                    Text { text: "Empfohlen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold }

                    Row {
                        width: parent.width
                        spacing: 12

                        // zuletzt benutzte Apps
                        Column {
                            width: (parent.width - 12) / 2
                            spacing: 2
                            Text {
                                visible: menu.recentEntries.length === 0
                                text: "Hier erscheinen zuletzt benutzte Apps."
                                color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS
                                topPadding: 8; leftPadding: 6
                            }
                            Repeater {
                                model: menu.recentEntries
                                delegate: MenuRow {
                                    required property var modelData
                                    width: parent.width
                                    label: modelData.name
                                    iconSource: Global.iconFor(modelData.id, modelData)
                                    onTriggered: menu.launch(modelData)
                                }
                            }
                        }
                        // zuletzt geänderte Dateien
                        Column {
                            width: (parent.width - 12) / 2
                            spacing: 2
                            Repeater {
                                model: menu.recentFiles
                                delegate: MenuRow {
                                    required property var modelData
                                    width: parent.width
                                    label: menu.fileName(modelData)
                                    iconSource: Quickshell.iconPath(menu.fileIcon(modelData), "text-x-generic")
                                    onTriggered: menu.openPath(modelData)
                                }
                            }
                        }
                    }

                    Item { width: 1; height: 4 }

                    // Ordner-Schnellzugriff
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: menu.folderLinks
                            delegate: BarButton {
                                required property var modelData
                                implicitHeight: 34; padding: 12; radiusSize: 17
                                color: hovered ? Theme.tileHover : Theme.tile
                                Row {
                                    spacing: 8
                                    Icon { name: modelData.icon; size: 15; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                                }
                                onClicked: menu.openPath(modelData.path + "/")
                            }
                        }
                    }
                }
            }

            // ===== Alle Apps (nach Kategorien) =====
            Item {
                anchors.fill: parent
                visible: menu.query === "" && menu.showAll

                Item {
                    id: allHead
                    width: parent.width; height: 30
                    Text { text: "Alle Apps"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    BarButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: 30; padding: 12; radiusSize: 15
                        color: hovered ? Theme.tileHover : Theme.tile
                        Row {
                            spacing: 6
                            Icon { name: "chevron-left"; size: 14; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Zurück"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                        }
                        onClicked: menu.showAll = false
                    }
                }
                ListView {
                    anchors.top: allHead.bottom
                    anchors.topMargin: 8
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: menu.allModel
                    delegate: Item {
                        required property var modelData
                        width: ListView.view.width
                        height: modelData.header !== undefined ? 34 : 44
                        Text {
                            visible: modelData.header !== undefined
                            anchors.left: parent.left; anchors.leftMargin: 8
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                            text: modelData.header || ""
                            color: Theme.accentBright
                            font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold
                        }
                        MenuRow {
                            visible: modelData.header === undefined
                            anchors.fill: parent
                            label: modelData.entry ? modelData.entry.name : ""
                            iconSource: modelData.entry ? Global.iconFor(modelData.entry.id, modelData.entry) : ""
                            onTriggered: menu.launch(modelData.entry)
                        }
                    }
                }
            }

            // ===== Suchergebnisse =====
            ListView {
                id: resultList
                anchors.fill: parent
                visible: menu.query !== ""
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: menu.results
                delegate: Item {
                    id: rowItem
                    required property var modelData
                    required property int index
                    readonly property bool isHeader: modelData.header !== undefined
                    width: ListView.view.width
                    height: isHeader ? 34 : 48

                    Text {
                        visible: rowItem.isHeader
                        anchors.left: parent.left; anchors.leftMargin: 8
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                        text: modelData.header || ""
                        color: Theme.accentBright
                        font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold
                    }
                    MenuRow {
                        visible: !rowItem.isHeader
                        anchors.fill: parent
                        highlighted: menu.sel === rowItem.index
                        label: modelData.kind === "app" ? modelData.entry.name
                             : modelData.kind === "setting" ? modelData.item.name
                             : modelData.kind === "file" ? menu.fileName(modelData.path)
                             : modelData.kind === "calc" ? "= " + modelData.value
                             : modelData.kind === "web" ? "Im Web suchen: " + modelData.text : ""
                        subLabel: modelData.kind === "file" ? menu.fileDir(modelData.path)
                                : modelData.kind === "calc" ? "Enter kopiert das Ergebnis"
                                : modelData.kind === "app" ? (modelData.entry.genericName || modelData.entry.comment || "") : ""
                        iconSource: modelData.kind === "app" ? Global.iconFor(modelData.entry.id, modelData.entry)
                                  : modelData.kind === "file" ? Quickshell.iconPath(menu.fileIcon(modelData.path), "text-x-generic")
                                  : ""
                        iconName: modelData.kind === "setting" ? modelData.item.icon
                                : modelData.kind === "calc" ? "add"
                                : modelData.kind === "web" ? "search" : ""
                        onTriggered: menu.activateResult(modelData)
                        onRightClicked: (x, y) => {
                            const p = menuRoot.mapFromItem(null, x, y);
                            if (modelData.kind === "app") menu.ctx = { x: p.x, y: p.y, entry: modelData.entry };
                            else if (modelData.kind === "file") menu.ctx = { x: p.x, y: p.y, file: modelData.path };
                        }
                    }
                }
            }
        }

        // ---------- Fußleiste ----------
        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 66
            radius: Theme.rXl
            color: Qt.rgba(1, 1, 1, 0.03)
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.borderSoft }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Rectangle {
                    width: 36; height: 36; radius: 18
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Theme.accentDeep }
                    }
                    Text { anchors.centerIn: parent; text: (Quickshell.env("USER") || "?").charAt(0).toUpperCase(); color: Theme.textOn; font.family: Theme.font; font.pixelSize: Theme.fsL; font.bold: true }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.confirm !== "" ? "Zum Bestätigen nochmal klicken" : (Quickshell.env("USER") || "")
                    color: menu.confirm !== "" ? Theme.accentBright : Theme.text
                    font.family: Theme.font; font.pixelSize: Theme.fsM + 1
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: [
                        { id: "lock",    icon: "lock",    cmd: "hyprlock",           confirm: false },
                        { id: "logout",  icon: "logout",  cmd: "",                   confirm: true  },
                        { id: "sleep",   icon: "sleep",   cmd: "systemctl suspend",  confirm: false },
                        { id: "restart", icon: "restart", cmd: "systemctl reboot",   confirm: true  },
                        { id: "power",   icon: "power",   cmd: "systemctl poweroff", confirm: true  }
                    ]
                    delegate: BarButton {
                        required property var modelData
                        active: menu.confirm === modelData.id
                        Icon { name: modelData.icon; accent: menu.confirm === modelData.id; size: 19 }
                        onClicked: {
                            if (modelData.confirm && menu.confirm !== modelData.id) { menu.confirm = modelData.id; return; }
                            Global.startOpen = false;
                            if (modelData.id === "logout") Global.hypr("hl.dsp.exit()");
                            else Global.run(modelData.cmd);
                        }
                    }
                }
            }
        }

        // Bezugspunkt für Kontextmenü-Koordinaten (ganzes Menüfenster)
        Item { id: menuRoot; anchors.fill: parent }

        // ---------- geöffneter App-Ordner ----------
        MouseArea { anchors.fill: parent; visible: menu.openFolder !== ""; z: 20; onClicked: menu.openFolder = "" }
        Surface {
            id: folderPanel
            visible: menu.openFolder !== ""
            z: 21
            level: 2
            radius: Theme.rL
            anchors.centerIn: parent
            width: 420
            readonly property var apps: ((Global.appFolders || []).find(f => f.name === menu.openFolder) || { apps: [] }).apps
            height: 74 + Math.ceil(apps.length / 3) * 100
            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                Text { text: menu.openFolder; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold }
                Flow {
                    width: parent.width
                    Repeater {
                        model: folderPanel.apps
                        delegate: AppTile {
                            required property var modelData
                            readonly property var e: Global.entryFor(modelData)
                            label: e ? e.name : modelData
                            iconSource: Global.iconFor(modelData, e)
                            slotW: Math.floor((folderPanel.width - 32) / 3)
                            onActivated: { if (e) { menu.openFolder = ""; menu.launch(e); } }
                            onMenuRequested: (x, y) => {
                                const p = menuRoot.mapFromItem(null, x, y);
                                menu.ctx = { x: p.x, y: p.y, entry: e };
                            }
                        }
                    }
                }
            }
        }

        // ---------- Kontextmenü ----------
        MouseArea { anchors.fill: parent; visible: menu.ctx !== null; z: 30; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: menu.ctx = null }
        Surface {
            id: ctxMenu
            visible: menu.ctx !== null
            z: 31
            level: 2
            radius: Theme.rM
            width: 250
            height: ctxCol.implicitHeight + 16
            x: menu.ctx ? Math.max(8, Math.min(menu.ctx.x, menuRoot.width - width - 8)) : 0
            y: menu.ctx ? Math.max(8, Math.min(menu.ctx.y, menuRoot.height - height - 8)) : 0

            readonly property var entry: menu.ctx && menu.ctx.entry ? menu.ctx.entry : null
            readonly property string filePath: menu.ctx && menu.ctx.file ? menu.ctx.file : ""
            readonly property string folderName: menu.ctx && menu.ctx.folder ? menu.ctx.folder : ""

            Column {
                id: ctxCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                // --- App ---
                MenuRow {
                    visible: ctxMenu.entry !== null
                    width: ctxCol.width
                    iconName: "add"
                    label: "Starten"
                    onTriggered: { const e = ctxMenu.entry; menu.ctx = null; menu.launch(e); }
                }
                MenuRow {
                    visible: ctxMenu.entry !== null
                    width: ctxCol.width
                    iconName: ctxMenu.entry && Global.isPinned(ctxMenu.entry.id) ? "pin-off" : "pin"
                    label: ctxMenu.entry && Global.isPinned(ctxMenu.entry.id) ? "Von Taskleiste lösen" : "An Taskleiste anheften"
                    onTriggered: { Global.togglePin(ctxMenu.entry.id); menu.ctx = null; }
                }
                MenuRow {
                    visible: ctxMenu.entry !== null
                    width: ctxCol.width
                    iconName: ctxMenu.entry && Global.isStartPinned(ctxMenu.entry.id) ? "pin-off" : "pin"
                    label: ctxMenu.entry && Global.isStartPinned(ctxMenu.entry.id) ? "Von Start lösen" : "An Start anheften"
                    onTriggered: { Global.toggleStartPin(ctxMenu.entry.id); menu.ctx = null; }
                }
                Rectangle { visible: ctxMenu.entry !== null; width: ctxCol.width; height: 1; color: Theme.borderSoft }
                Repeater {
                    model: ctxMenu.entry ? (Global.appFolders || []) : []
                    delegate: MenuRow {
                        required property var modelData
                        width: ctxCol.width
                        iconName: "folder"
                        label: "In Ordner „" + modelData.name + "“"
                        onTriggered: { Global.folderAddApp(modelData.name, ctxMenu.entry.id); menu.ctx = null; }
                    }
                }
                MenuRow {
                    visible: ctxMenu.entry !== null
                    width: ctxCol.width
                    iconName: "add"
                    label: "In neuen Ordner"
                    onTriggered: { Global.folderAddApp("Ordner " + ((Global.appFolders || []).length + 1), ctxMenu.entry.id); menu.ctx = null; }
                }
                MenuRow {
                    visible: ctxMenu.entry !== null && Global.folderOf(ctxMenu.entry.id) !== ""
                    width: ctxCol.width
                    iconName: "close"
                    label: "Aus Ordner entfernen"
                    onTriggered: { Global.folderRemoveApp(ctxMenu.entry.id); menu.ctx = null; }
                }

                // --- Datei (aus der Suche) ---
                MenuRow {
                    visible: ctxMenu.filePath !== ""
                    width: ctxCol.width
                    iconName: "folder-open"
                    label: "Öffnen"
                    onTriggered: { const f = ctxMenu.filePath; menu.ctx = null; menu.openPath(f); }
                }
                MenuRow {
                    visible: ctxMenu.filePath !== ""
                    width: ctxCol.width
                    iconName: "folder"
                    label: "Ordner anzeigen"
                    onTriggered: { const f = ctxMenu.filePath; menu.ctx = null; Global.startOpen = false; Quickshell.execDetached(["dolphin", "--select", f]); }
                }
                MenuRow {
                    visible: ctxMenu.filePath !== ""
                    width: ctxCol.width
                    iconName: "clipboard"
                    label: "Pfad kopieren"
                    onTriggered: { Quickshell.execDetached(["wl-copy", ctxMenu.filePath]); menu.ctx = null; }
                }

                // --- Ordner ---
                MenuRow {
                    visible: ctxMenu.folderName !== ""
                    width: ctxCol.width
                    iconName: "folder"
                    label: "Öffnen"
                    onTriggered: { menu.openFolder = ctxMenu.folderName; menu.ctx = null; }
                }
                MenuRow {
                    visible: ctxMenu.folderName !== ""
                    width: ctxCol.width
                    iconName: "close"
                    label: "Ordner auflösen"
                    onTriggered: { Global.folderDissolve(ctxMenu.folderName); menu.ctx = null; }
                }
            }
        }
    }
}
