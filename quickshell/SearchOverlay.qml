import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Schnellsuche (Strg+Leertaste): ein eigenes Feld mittig auf dem Bildschirm, darunter die Ergebnisse.
// Apps, Rechner, Einstellungen, Dateien (plocate) und Websuche; Pfeile wählen, Enter startet, Esc schließt.
PanelWindow {
    id: so
    visible: Global.searchOpen
    screen: Global.screenByName(Global.popupScreen)

    // Oberes Drittel des Bildschirms, waagerecht mittig
    anchors.top: true
    margins.top: screen ? Math.round(screen.height * 0.22) : 220
    implicitWidth: 680
    implicitHeight: bar.height + (resultList.visible ? resultList.height + 10 : 0) + 24
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "draconyx-search"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property string query: ""
    property int sel: 0
    property var fileHits: []
    property var ctx: null              // Rechtsklick-Menü auf einem Ergebnis: { x, y, r }

    onVisibleChanged: {
        if (visible) { query = ""; input.text = ""; sel = 0; fileHits = []; ctx = null; input.forceActiveFocus(); }
    }

    HyprlandFocusGrab { id: soGrab; windows: [so]; active: so.visible; onCleared: if (!Global.snipBusy) Global.searchOpen = false }
    Connections { target: Global; function onSnipBusyChanged() { if (!Global.snipBusy && so.visible) { soGrab.active = false; soGrab.active = true; } } }
    Connections { target: Global; function onSearchTestChanged() { if (so.visible) input.text = Global.searchTest; } }

    // ---------- Daten ----------
    readonly property var allApps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    readonly property var settingsItems: [
        { name: "Audio & Lautstärke",   kw: "audio ton sound lautstärke mikrofon",   icon: "vol",      cmd: ["pavucontrol"] },
        { name: "Netzwerk & WLAN",      kw: "netzwerk wlan wifi internet lan",       icon: "wifi",     cmd: ["nm-connection-editor"] },
        { name: "Bluetooth",            kw: "bluetooth geräte kopfhörer",            icon: "bt",       cmd: ["blueman-manager"] },
        { name: "Bildschirme & HDR",    kw: "bildschirm monitor display auflösung hdr refresh", icon: "desktop", cmd: ["nwg-displays"] },
        { name: "Aurora Einstellungen", kw: "aurora einstellungen taskleiste farben tasten", icon: "settings", cmd: ["sh", "-c", "GDK_BACKEND=x11 python3 \"$HOME/.config/hypr/aurora/settings-app\""] }
    ]

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
        if (c !== null) out.push({ kind: "calc", title: "= " + c, sub: "Enter kopiert das Ergebnis", value: c, icon: "add" });
        const apps = [];
        for (const e of allApps) {
            const name = (e.name || "").toLowerCase();
            const hay = [name, (e.genericName || "").toLowerCase(), (e.comment || "").toLowerCase(), (e.keywords || []).join(" ").toLowerCase()].join(" ");
            if (!hay.includes(q)) continue;
            apps.push({ e: e, s: name.startsWith(q) ? 0 : (name.includes(q) ? 1 : 2) });
        }
        apps.sort((a, b) => a.s - b.s || a.e.name.localeCompare(b.e.name));
        for (const a of apps.slice(0, 7)) out.push({ kind: "app", entry: a.e, title: a.e.name, sub: a.e.genericName || a.e.comment || "App" });
        for (const s of settingsItems.filter(s => (s.name + " " + s.kw).toLowerCase().includes(q)).slice(0, 3))
            out.push({ kind: "setting", item: s, title: s.name, sub: "Einstellung", icon: s.icon });
        for (const f of fileHits.slice(0, 5))
            out.push({ kind: "file", path: f, title: f.substring(f.lastIndexOf("/") + 1), sub: f.substring(0, f.lastIndexOf("/")).replace(Theme.home, "~"), icon: "folder" });
        out.push({ kind: "web", text: query.trim(), title: "Im Web suchen: " + query.trim(), sub: "DuckDuckGo", icon: "search" });
        return out;
    }
    onResultsChanged: sel = 0

    function activate(r) {
        if (!r) return;
        Global.logLaunch("suche", r.kind + ":" + (r.path || (r.entry && r.entry.id) || r.text || r.value || ""));
        Global.searchOpen = false;
        if (r.kind === "app") Global.launch(r.entry.id, r.entry);
        else if (r.kind === "setting") Quickshell.execDetached(r.item.cmd);
        else if (r.kind === "file") Quickshell.execDetached(r.path.endsWith("/") ? ["dolphin", r.path] : ["xdg-open", r.path]);
        else if (r.kind === "calc") Quickshell.execDetached(["wl-copy", String(r.value)]);
        else if (r.kind === "web") Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(r.text)]);
    }

    // Dateisuche (plocate), leicht verzögert
    Timer {
        id: fileTimer
        interval: 220
        onTriggered: { if (so.query.trim().length >= 2) { plocate.running = false; plocate.running = true; } else so.fileHits = []; }
    }
    Process {
        id: plocate
        command: ["sh", "-c", "plocate -i -l 80 -b -- \"$1\" 2>/dev/null | grep -E \"^$2/\" | grep -vE '/\\.|/node_modules/' | head -5", "sh", so.query.trim(), Theme.home]
        stdout: StdioCollector { onStreamFinished: so.fileHits = text.split("\n").filter(l => l !== "") }
    }

    // ---------- Oberfläche ----------
    Item { id: root; anchors.fill: parent }

    Rectangle {
        id: bar
        anchors.top: parent.top; anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 24; height: 62
        radius: 31
        color: Theme.panelStrong
        border.color: input.activeFocus ? Theme.accent : Theme.border
        border.width: 1
        Icon { id: lens; name: "search"; size: 22; accent: true; anchors.left: parent.left; anchors.leftMargin: 22; anchors.verticalCenter: parent.verticalCenter }
        TextInput {
            id: input
            anchors.left: lens.right; anchors.leftMargin: 14
            anchors.right: parent.right; anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text; selectionColor: Theme.accent
            font.family: Theme.font; font.pixelSize: 20
            clip: true
            onTextChanged: { so.query = text; fileTimer.restart(); }
            Keys.onEscapePressed: Global.searchOpen = false
            Keys.onDownPressed: if (so.results.length > 0) so.sel = (so.sel + 1) % so.results.length
            Keys.onUpPressed: if (so.results.length > 0) so.sel = (so.sel - 1 + so.results.length) % so.results.length
            Keys.onReturnPressed: so.activate(so.results[so.sel])
            Keys.onEnterPressed: so.activate(so.results[so.sel])
            Text { visible: input.text === ""; text: "Apps, Dateien, Einstellungen durchsuchen …"; color: Theme.textDim; font: input.font }
        }
    }

    Rectangle {
        id: resultList
        visible: so.query.trim() !== "" && so.results.length > 0
        anchors.top: bar.bottom; anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: bar.width
        height: Math.min(so.results.length, 8) * 56 + 14
        radius: 22
        color: Theme.panelStrong
        border.color: Theme.border
        clip: true

        ListView {
            ScrollSpeed { }
            anchors.fill: parent; anchors.margins: 7
            model: so.results
            clip: true
            spacing: 0
            currentIndex: so.sel
            boundsBehavior: Flickable.StopAtBounds
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width; height: 56; radius: 14
                color: index === so.sel ? Theme.selected : (ma.containsMouse ? Theme.tileHover : "transparent")
                Row {
                    anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 14
                    Item {
                        width: 34; height: 34
                        IconImage {
                            anchors.fill: parent
                            visible: row.modelData.kind === "app"
                            source: row.modelData.kind === "app" ? Global.iconFor(row.modelData.entry.id, row.modelData.entry) : ""
                        }
                        Icon { visible: row.modelData.kind !== "app"; anchors.centerIn: parent; name: row.modelData.icon || "search"; size: 22 }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { width: 520; elide: Text.ElideRight; text: row.modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM + 1 }
                        Text { width: 520; elide: Text.ElideRight; text: row.modelData.sub || ""; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                    }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: so.sel = row.index
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (row.modelData.kind === "app" || row.modelData.kind === "file") {
                                const p = ma.mapToItem(root, mouse.x, mouse.y);
                                so.ctx = { x: p.x, y: p.y, r: row.modelData };
                            }
                        } else so.activate(row.modelData);
                    }
                }
            }
        }
    }

    // ---------- Rechtsklick-Menü ----------
    MouseArea { anchors.fill: parent; visible: so.ctx !== null; z: 40; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: so.ctx = null }
    Surface {
        id: ctxMenu
        visible: so.ctx !== null
        z: 41; level: 2; radius: Theme.rM
        width: 250; height: ctxCol.implicitHeight + 16
        x: so.ctx ? Math.max(8, Math.min(so.ctx.x, so.width - width - 8)) : 0
        y: so.ctx ? Math.max(8, Math.min(so.ctx.y, so.height - height - 8)) : 0
        readonly property var entry: so.ctx && so.ctx.r.kind === "app" ? so.ctx.r.entry : null
        readonly property string filePath: so.ctx && so.ctx.r.kind === "file" ? so.ctx.r.path : ""
        Column {
            id: ctxCol
            anchors.fill: parent; anchors.margins: 8; spacing: 2
            MenuRow { visible: ctxMenu.entry !== null; width: ctxCol.width; iconName: "play"; label: "Starten"
                      onTriggered: { const r = so.ctx.r; so.ctx = null; so.activate(r); } }
            MenuRow { visible: ctxMenu.entry !== null; width: ctxCol.width
                      iconName: ctxMenu.entry && Global.isPinned(ctxMenu.entry.id) ? "pin-off" : "pin"
                      label: ctxMenu.entry && Global.isPinned(ctxMenu.entry.id) ? "Von Taskleiste lösen" : "An Taskleiste anheften"
                      onTriggered: { Global.togglePin(ctxMenu.entry.id); so.ctx = null; } }
            MenuRow { visible: ctxMenu.entry !== null; width: ctxCol.width
                      iconName: ctxMenu.entry && Global.isStartPinned(ctxMenu.entry.id) ? "pin-off" : "pin"
                      label: ctxMenu.entry && Global.isStartPinned(ctxMenu.entry.id) ? "Von Start lösen" : "An Start anheften"
                      onTriggered: { Global.toggleStartPin(ctxMenu.entry.id); so.ctx = null; } }
            MenuRow { visible: ctxMenu.filePath !== ""; width: ctxCol.width; iconName: "folder-open"; label: "Öffnen"
                      onTriggered: { const r = so.ctx.r; so.ctx = null; so.activate(r); } }
            MenuRow { visible: ctxMenu.filePath !== ""; width: ctxCol.width; iconName: "folder"; label: "Ordner anzeigen"
                      onTriggered: { const f = ctxMenu.filePath; so.ctx = null; Global.searchOpen = false; Quickshell.execDetached(["dolphin", "--select", f]); } }
            MenuRow { visible: ctxMenu.filePath !== ""; width: ctxCol.width; iconName: "clipboard"; label: "Pfad kopieren"
                      onTriggered: { Quickshell.execDetached(["wl-copy", ctxMenu.filePath]); so.ctx = null; } }
        }
    }
}
