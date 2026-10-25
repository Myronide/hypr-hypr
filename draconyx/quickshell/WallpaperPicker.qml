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

    property var items: []
    property string query: ""
    property string typ: ""
    readonly property string mon: Global.popupScreen
    readonly property string current: (Global.weWallpapers || {})[mon] || ""
    readonly property var shown: items.filter(i => (typ === "" || i.type === typ)
                                                    && (query === "" || i.title.toLowerCase().includes(query.toLowerCase())))

    onVisibleChanged: if (visible) { query = ""; search.text = ""; search.forceActiveFocus(); load.running = false; load.running = true; rootsProc.running = false; rootsProc.running = true; }

    HyprlandFocusGrab { windows: [wp]; active: wp.visible; onCleared: Global.weOpen = false }

    property string rootsText: ""
    Process {
        id: rootsProc
        command: [Theme.home + "/.local/bin/dx-we-list", "--roots"]
        stdout: StdioCollector { onStreamFinished: wp.rootsText = text.trim().split("\n").filter(l => l.indexOf("\t") > 0).slice(0, 10).map(l => l.split("\t").join("  →  ")).join("\n"); }
    }
    Process {
        id: load
        command: [Theme.home + "/.local/bin/dx-we-list"]
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
                Text { text: "Wallpaper Engine"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold }
                Text { text: "für " + wp.mon + "  ·  " + wp.shown.length + " Wallpaper"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
            }
            Row {
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
                onTextChanged: wp.query = text
                Keys.onEscapePressed: Global.weOpen = false
                Text { visible: search.text === ""; text: "Wallpaper suchen …"; color: Theme.textDim; font: search.font }
            }
        }

        Text {
            visible: wp.items.length === 0
            anchors.centerIn: parent
            width: parent.width - 80
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Keine Wallpaper gefunden.\nOrdner in Aurora → Wallpaper Engine wählen oder die Steam-Bibliothek prüfen.\n\nGesucht in:\n" + wp.rootsText
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS
        }

        GridView {
            id: grid
            anchors.top: sbox.bottom; anchors.topMargin: 12
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: 16; anchors.rightMargin: 8; anchors.bottomMargin: 14
            clip: true
            cellWidth: Math.floor((width - 8) / 4)
            cellHeight: cellWidth * 0.62 + 30
            boundsBehavior: Flickable.StopAtBounds
            model: wp.shown

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth; height: grid.cellHeight
                readonly property bool on: wp.current === modelData.id
                Rectangle {
                    anchors.fill: parent; anchors.margins: 5
                    radius: Theme.rM
                    color: ma.containsMouse ? Theme.tileHover : "transparent"
                    border.color: cell.on ? Theme.accent : "transparent"; border.width: 2
                    Image {
                        id: img
                        x: 6; y: 6; width: parent.width - 12; height: width * 0.56
                        source: cell.modelData.preview !== "" ? "file://" + cell.modelData.preview : ""
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
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: Global.weSet(wp.mon, cell.modelData.id) }
                }
            }
        }
    }
}
