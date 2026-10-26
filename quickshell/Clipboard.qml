import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Zwischenablage-Verlauf (Strg+Alt+V): Suchfeld oben, darunter die zuletzt kopierten Texte und Bilder.
// Pfeile wählen, Enter kopiert erneut, Entf entfernt, Esc schließt. Bilder zeigen eine Vorschau.
PanelWindow {
    id: cb
    visible: Global.clipOpen
    screen: Global.screenByName(Global.popupScreen)

    anchors.top: true
    margins.top: screen ? Math.round(screen.height * 0.16) : 160
    implicitWidth: 640
    implicitHeight: 560
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "draconyx-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property var items: []                 // { id, text, image, line }
    property string query: ""
    property int sel: 0
    readonly property string cacheDir: Theme.home + "/.cache/draconyx/clip"

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        return q === "" ? items : items.filter(i => i.text.toLowerCase().includes(q));
    }
    onShownChanged: sel = 0

    onVisibleChanged: if (visible) { query = ""; input.text = ""; sel = 0; load(); input.forceActiveFocus(); }
    HyprlandFocusGrab { id: grab; windows: [cb]; active: cb.visible; onCleared: if (!Global.snipBusy) Global.clipOpen = false }

    function load() { thumbsReady = false; list.running = false; list.running = true; }
    Process {
        id: list
        command: ["sh", "-c", "cliphist list 2>/dev/null | head -120"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (line === "") continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const body = line.substring(tab + 1);
                    const img = /^\[\[ binary data .*(png|jpe?g|bmp|gif|webp)/i.test(body);
                    out.push({ id: line.substring(0, tab), text: body, image: img, line: line });
                }
                cb.items = out;
                const ids = out.filter(i => i.image).slice(0, 10).map(i => i.id);
                if (ids.length > 0) thumbs.run(ids); else cb.thumbsReady = true;
            }
        }
    }
    // Vorschaubilder der jüngsten Bilder
    property bool thumbsReady: false
    Process {
        id: thumbs
        function run(ids) {
            command = ["sh", "-c", "mkdir -p \"$0\"; for i in \"$@\"; do [ -s \"$0/$i.img\" ] || cliphist decode \"$i\" > \"$0/$i.img\" 2>/dev/null; done", cb.cacheDir, ...ids];
            running = false; running = true;
        }
        onExited: cb.thumbsReady = true
    }

    function pick(e) {
        if (!e) return;
        Global.clipOpen = false;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "sh", e.line]);
    }
    function remove(e) {
        if (!e) return;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", e.line]);
        items = items.filter(i => i !== e);
    }
    function wipe() { Quickshell.execDetached(["cliphist", "wipe"]); items = []; }

    PopCard {
        anchors.fill: parent
        radius: 24
        color: Theme.panelStrong
        border.color: Theme.border

        Rectangle {
            id: bar
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 14
            height: 52; radius: 26
            color: Theme.tile
            border.color: input.activeFocus ? Theme.accent : Theme.borderSoft
            Icon { id: lens; name: "clipboard"; size: 20; accent: true; anchors.left: parent.left; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter }
            TextInput {
                id: input
                anchors.left: lens.right; anchors.leftMargin: 12
                anchors.right: clearBtn.left; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                clip: true
                onTextChanged: cb.query = text
                Keys.onEscapePressed: Global.clipOpen = false
                Keys.onDownPressed: if (cb.shown.length > 0) cb.sel = Math.min(cb.sel + 1, cb.shown.length - 1)
                Keys.onUpPressed: cb.sel = Math.max(cb.sel - 1, 0)
                Keys.onReturnPressed: cb.pick(cb.shown[cb.sel])
                Keys.onEnterPressed: cb.pick(cb.shown[cb.sel])
                Keys.onDeletePressed: event => { if (input.text === "") cb.remove(cb.shown[cb.sel]); else event.accepted = false; }
                Text { visible: input.text === ""; text: "Zwischenablage durchsuchen …"; color: Theme.textDim; font: input.font }
            }
            BarButton {
                id: clearBtn
                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 34; padding: 14; radiusSize: 17
                color: hovered ? Qt.rgba(1, 0.42, 0.42, 0.3) : "transparent"
                Row { spacing: 6
                    Icon { name: "trash"; size: 15; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Leeren"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                }
                onClicked: cb.wipe()
            }
        }

        Text {
            visible: cb.shown.length === 0
            anchors.centerIn: parent
            text: cb.items.length === 0 ? "Noch nichts kopiert." : "Nichts gefunden."
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsM
        }

        ListView {
            id: lv
            ScrollSpeed { }
            anchors.top: bar.bottom; anchors.topMargin: 10
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: foot.top
            anchors.leftMargin: 10; anchors.rightMargin: 10
            clip: true
            model: cb.shown
            currentIndex: cb.sel
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isSel: index === cb.sel
                width: ListView.view.width
                height: modelData.image ? 96 : Math.min(76, 24 + Math.min(3, Math.ceil(modelData.text.length / 70)) * 18)
                radius: 14
                color: isSel ? Theme.selected : (ma.containsMouse ? Theme.tileHover : "transparent")
                Behavior on color { ColorAnimation { duration: 90 } }

                Image {
                    visible: row.modelData.image
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 120; height: 78
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    source: row.modelData.image && cb.thumbsReady ? "file://" + cb.cacheDir + "/" + row.modelData.id + ".img" : ""
                }
                Text {
                    anchors.left: parent.left; anchors.right: del.left
                    anchors.leftMargin: row.modelData.image ? 148 : 16; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.image ? "Bild  ·  " + row.modelData.text.replace(/^\[\[ binary data /, "").replace(/ \]\]$/, "") : row.modelData.text.replace(/\s+/g, " ").trim()
                    color: Theme.text; font.family: row.modelData.image ? Theme.font : Theme.font; font.pixelSize: Theme.fsM
                    wrapMode: Text.Wrap; maximumLineCount: row.modelData.image ? 2 : 3; elide: Text.ElideRight
                }
                BarButton {
                    id: del
                    visible: ma.containsMouse || row.isSel
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    minWidth: 30; implicitHeight: 30; radiusSize: 15
                    color: hovered ? Qt.rgba(1, 0.42, 0.42, 0.3) : "transparent"
                    Icon { name: "close"; size: 12 }
                    onClicked: cb.remove(row.modelData)
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent; anchors.rightMargin: 44
                    hoverEnabled: true
                    onEntered: cb.sel = row.index
                    onClicked: cb.pick(row.modelData)
                }
            }
        }
        Text {
            id: foot
            anchors.bottom: parent.bottom; anchors.bottomMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            height: 18
            text: "Enter kopiert erneut  ·  Entf entfernt  ·  Esc schließt"
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
        }
    }
}
