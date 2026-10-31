import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// Wallpaper Engine: Wallpaper für den Monitor wählen, auf dem die Taskleiste angeklickt wurde
PanelWindow {
    id: wp
    visible: Global.weOpen
    screen: Global.screenByName(Global.popupScreen)

    anchors.bottom: !Global.barTop
    anchors.top: Global.barTop
    anchors.left: true
    margins.bottom: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.top: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.left: Global.popupLeft() + 120
    implicitWidth: 760
    implicitHeight: 660
    exclusionMode: ExclusionMode.Ignore      // Abstand zur Leiste kommt aus den Rändern; die Leisten-Reservierung nicht doppelt rechnen
    color: "transparent"
    WlrLayershell.namespace: "draconyx-code"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // ---- Steam Workshop (Tab): Liste von der öffentlichen Workshop-Seite; Abonnieren macht der Steam-Client ----
    property string tab: "mine"                // "mine" | "workshop"
    property var wsItems: []
    property string wsSort: "trend"
    property string wsQuery: ""
    property int wsPage: 1
    property bool wsLoading: false
    property string wsError: ""
    function wsLoad(page) {
        wsPage = page;
        wsLoading = true; wsError = "";
        wsProc.command = [Theme.home + "/.local/bin/hyhy-we-workshop", "browse", "--sort", wsSort, "--search", wsQuery, "--page", String(page)];
        wsProc.running = false; wsProc.running = true;
    }
    Process {
        id: wsProc
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = text.split("\n").filter(l => l !== "").map(l => { const p = l.split("\t"); return { id: p[0], title: p[1], preview: p[2], have: p[3] === "1", workshop: true }; });
                wp.wsItems = wp.wsPage > 1 ? wp.wsItems.concat(rows) : rows;
                wp.wsLoading = false;
                if (rows.length === 0 && wp.wsPage === 1) wp.wsError = "Nichts gefunden.";
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") { wp.wsError = "Der Workshop ließ sich nicht laden (keine Verbindung?)"; wp.wsLoading = false; } }
    }
    onTabChanged: { search.text = ""; if (tab === "workshop" && wsItems.length === 0) wsLoad(1); }
    property var items: []
    property string query: ""
    property string typ: ""
    readonly property string mon: Global.popupScreen
    readonly property string current: (Global.weWallpapers || {})[mon] || ""
    readonly property var shown: items.filter(i => (typ === "" || i.type === typ)
                                                    && (query === "" || i.title.toLowerCase().includes(query.toLowerCase())))

    onVisibleChanged: if (visible) { if (tab === "workshop" && wsItems.length === 0) wsLoad(1); query = ""; search.text = ""; search.forceActiveFocus(); load.running = false; load.running = true; rootsProc.running = false; rootsProc.running = true; }

    HyprlandFocusGrab { id: wpGrab; windows: [wp]; active: wp.visible; onCleared: if (!Global.snipBusy) Global.weOpen = false }
    Connections { target: Global; function onSnipBusyChanged() { if (!Global.snipBusy && wp.visible) { wpGrab.active = false; wpGrab.active = true; } } }

    property string rootsText: ""
    Process {
        id: rootsProc
        command: [Theme.home + "/.local/bin/hyhy-we-list", "--roots"]
        stdout: StdioCollector { onStreamFinished: wp.rootsText = text.trim().split("\n").filter(l => l.indexOf("\t") > 0).slice(0, 10).map(l => l.split("\t").join("  →  ")).join("\n"); }
    }
    Process {
        id: load
        command: [Theme.home + "/.local/bin/hyhy-we-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                wp.items = text.split("\n").filter(l => l !== "").map(l => {
                    const p = l.split("\t");
                    return { id: p[0], title: p[1], type: p[2], preview: p[3], mtime: Number(p[4]) };
                }).sort((a, b) => a.title.localeCompare(b.title));
            }
        }
    }

    Surface {
        anchors.fill: parent
        level: 2
        radius: Theme.rXl

        Item {
            id: head
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 70
            Column {
                anchors.left: parent.left; anchors.leftMargin: 22; anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Row {
                    spacing: 6
                    Repeater {
                        model: [{ k: "mine", t: "Meine Wallpaper" }, { k: "workshop", t: "Steam Workshop" }]
                        BarButton {
                            required property var modelData
                            implicitHeight: 32; padding: 14; radiusSize: 16
                            active: wp.tab === modelData.k
                            color: wp.tab === modelData.k ? Theme.accent : (hovered ? Theme.tileHover : Theme.tile)
                            Text { text: modelData.t; color: wp.tab === modelData.k ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                            onClicked: wp.tab = modelData.k
                        }
                    }
                }
                Text { text: wp.tab === "mine" ? "für " + wp.mon + "  ·  " + wp.shown.length + " Wallpaper" : "Abonnieren lädt Steam herunter – danach erscheint es unter „Meine Wallpaper“"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
            }
            Row {
                visible: wp.tab === "workshop"
                anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: [{ k: "trend", t: "Beliebt" }, { k: "new", t: "Neu" }, { k: "top", t: "Top bewertet" }]
                    BarButton {
                        required property var modelData
                        implicitHeight: 32; padding: 12; radiusSize: 16
                        active: wp.wsSort === modelData.k
                        Text { text: modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                        onClicked: { wp.wsSort = modelData.k; wp.wsLoad(1); }
                    }
                }
            }
            Row {
                visible: wp.tab === "mine"
                anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: [{ k: "", t: "Alle" }, { k: "scene", t: "Szene" }, { k: "video", t: "Video" }, { k: "web", t: "Web" }]
                    BarButton {
                        required property var modelData
                        implicitHeight: 32; padding: 12; radiusSize: 16
                        active: wp.typ === modelData.k
                        Text { text: modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                        onClicked: wp.typ = modelData.k
                    }
                }
                BarButton {
                    implicitHeight: 32; padding: 12; radiusSize: 16
                    visible: wp.current !== "" && (Global.desktopMonitors || []).indexOf(wp.mon) >= 0
                    active: (Global.weMouse || []).indexOf(wp.mon) >= 0
                    Text { text: "Maus"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                    onClicked: {
                        const l = (Global.weMouse || []).slice(); const i = l.indexOf(wp.mon);
                        if (i >= 0) l.splice(i, 1); else l.push(wp.mon);
                        Global.weMouse = l;
                    }
                }
                BarButton {
                    implicitHeight: 32; padding: 12; radiusSize: 16
                    visible: wp.current !== ""
                    Text { text: "Aus"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                    onClicked: Global.weSet(wp.mon, "")
                }
            }
        }

        Rectangle {
            id: sbox
            anchors.top: head.bottom
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 20; anchors.rightMargin: 20
            height: 40; radius: 20
            color: Theme.tile
            border.color: search.activeFocus ? Theme.accent : Theme.borderSoft
            Icon { id: si; name: "search"; size: 16; anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter }
            TextInput {
                id: search
                anchors.left: si.right; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: Theme.fsM + 1
                clip: true
                onTextChanged: if (wp.tab === "mine") wp.query = text
                Keys.onReturnPressed: if (wp.tab === "workshop") { wp.wsQuery = text; wp.wsLoad(1); }
                Keys.onEscapePressed: Global.weOpen = false
                Text { visible: search.text === ""; text: wp.tab === "mine" ? "Wallpaper suchen …" : "Im Steam Workshop suchen … (Enter)"; color: Theme.textDim; font: search.font }
            }
        }

        Text {
            visible: wp.tab === "mine" && wp.items.length === 0
            anchors.centerIn: parent
            width: parent.width - 80
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Keine Wallpaper gefunden.\nOrdner in Aurora → Wallpaper Engine wählen oder die Steam-Bibliothek prüfen.\n\nGesucht in:\n" + wp.rootsText
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS
        }

        GridView {
            ScrollSpeed { }
            id: grid
            anchors.top: sbox.bottom; anchors.topMargin: 12
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: 16; anchors.rightMargin: 8; anchors.bottomMargin: 14
            clip: true
            cellWidth: Math.floor((width - 8) / 4)
            cellHeight: cellWidth * 0.62 + 30
            boundsBehavior: Flickable.StopAtBounds
            model: wp.tab === "mine" ? wp.shown : wp.wsItems
            footer: Item {
                visible: wp.tab === "workshop"
                width: grid.width; height: wp.tab === "workshop" ? 56 : 0
                Text {
                    anchors.centerIn: parent
                    visible: wp.wsLoading || wp.wsError !== ""
                    text: wp.wsLoading ? "Lade …" : wp.wsError
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS
                }
                BarButton {
                    anchors.centerIn: parent
                    visible: !wp.wsLoading && wp.wsError === "" && wp.wsItems.length > 0
                    implicitHeight: 34; padding: 18; radiusSize: 17
                    Text { text: "Mehr laden"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                    onClicked: wp.wsLoad(wp.wsPage + 1)
                }
            }

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth; height: grid.cellHeight
                readonly property bool on: wp.tab === "mine" && wp.current === modelData.id
                Rectangle {
                    anchors.fill: parent; anchors.margins: 5
                    radius: Theme.rM
                    color: ma.containsMouse ? Theme.tileHover : "transparent"
                    border.color: cell.on ? Theme.accent : "transparent"; border.width: 2
                    Image {
                        id: img
                        x: 6; y: 6; width: parent.width - 12; height: width * 0.56
                        source: (cell.modelData.preview || "") !== "" ? "file://" + cell.modelData.preview : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true; cache: true
                        sourceSize: Qt.size(320, 180)
                    }
                    Text {
                        anchors.top: img.bottom; anchors.topMargin: 3
                        anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 8
                        text: cell.modelData.title
                        elide: Text.ElideRight
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs
                    }
                    // Workshop: Häkchen, wenn schon installiert; Klick öffnet die Seite in Steam (dort Abonnieren)
                    Rectangle {
                        visible: !!cell.modelData.workshop && !!cell.modelData.have
                        anchors.right: img.right; anchors.top: img.top; anchors.margins: 6
                        width: tag.implicitWidth + 14; height: 22; radius: 11; color: Theme.accent
                        Text { id: tag; anchors.centerIn: parent; text: "✓ installiert"; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                    }
                    Rectangle {
                        visible: !!cell.modelData.workshop && !cell.modelData.have && ma.containsMouse
                        anchors.fill: img; radius: 4; color: "#99000000"
                        Text { anchors.centerIn: parent; text: "In Steam öffnen\n(Abonnieren)"; horizontalAlignment: Text.AlignHCenter; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
                    }
                    MouseArea {
                        id: ma; anchors.fill: parent; hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (cell.modelData.workshop) Quickshell.execDetached([Theme.home + "/.local/bin/hyhy-we-workshop", mouse.button === Qt.RightButton ? "web" : "open", cell.modelData.id]);
                            else Global.weSet(wp.mon, cell.modelData.id);
                        }
                    }
                }
            }
        }
    }
}
