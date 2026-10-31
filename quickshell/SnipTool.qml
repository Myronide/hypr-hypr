import QtQuick
import Quickshell
import Quickshell.Wayland

// Snip-Werkzeug (Druck / Strg+Alt+Umschalt+S): friert jeden Bildschirm als Foto ein (grim), dann mit der Maus einen Bereich
// aufziehen. Enter = kopieren, Strg+S = speichern, Esc = abbrechen. Kein hyprpicker/hyprshot (dessen Einfrieren färbte die
// Bildschirme weiß).
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        visible: Global.snipOpen
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.namespace: "draconyx-snip"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        readonly property string file: Global.snipFiles[modelData.name] || ""

        // Auswahl in Fensterkoordinaten
        property real selX: 0
        property real selY: 0
        property real selW: 0
        property real selH: 0
        property bool dragging: false
        property bool done: false
        property real startX: 0
        property real startY: 0
        readonly property bool hasSel: selW > 3 && selH > 3

        onVisibleChanged: if (visible) {
            selW = 0; selH = 0; dragging = false; done = false; root.forceActiveFocus(); }

        function act(mode) {
            if (!hasSel || file === "") return;
            const k = shot.sourceSize.width / root.width;            // Pixel des Fotos pro Fenster-Einheit (Skalierung)
            if (mode === "edit") {                                   // Übernehmen: Ausschnitt im Foto-Editor öffnen
                Global.snipEdit(file, Math.round(selX * k), Math.round(selY * k), Math.round(selW * k), Math.round(selH * k), modelData.name);
                return;
            }
            Quickshell.execDetached([Theme.home + "/.local/bin/hyhy-snip-crop", file,
                String(Math.round(selX * k)), String(Math.round(selY * k)), String(Math.round(selW * k)), String(Math.round(selH * k)), mode]);
            Global.snipClose(1500);
        }

        Item {
            id: root
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Global.snipClose(0)
            Keys.onReturnPressed: win.act("edit")
            Keys.onEnterPressed: win.act("edit")
            Keys.onPressed: event => { if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) { win.act("save"); event.accepted = true; }
                else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) { win.act("copy"); event.accepted = true; } }

            Image {
                id: shot
                anchors.fill: parent
                source: (Global.snipOpen && win.file !== "") ? "file://" + win.file : ""
                cache: false
                fillMode: Image.Stretch
                smooth: false
            }

            // abgedunkelt außerhalb der Auswahl
            Rectangle { color: "#a6000000"; x: 0; y: 0; width: root.width; height: win.hasSel ? win.selY : root.height }
            Rectangle { visible: win.hasSel; color: "#a6000000"; x: 0; y: win.selY + win.selH; width: root.width; height: root.height - (win.selY + win.selH) }
            Rectangle { visible: win.hasSel; color: "#a6000000"; x: 0; y: win.selY; width: win.selX; height: win.selH }
            Rectangle { visible: win.hasSel; color: "#a6000000"; x: win.selX + win.selW; y: win.selY; width: root.width - (win.selX + win.selW); height: win.selH }

            Rectangle {
                visible: win.hasSel
                x: win.selX; y: win.selY; width: win.selW; height: win.selH
                color: "transparent"
                border.color: Theme.accentBright; border.width: 2
            }
            // Größe
            Rectangle {
                visible: win.hasSel
                x: win.selX; y: Math.max(4, win.selY - 28)
                width: sizeText.implicitWidth + 16; height: 24; radius: 12
                color: Theme.accentDeep
                Text { id: sizeText; anchors.centerIn: parent; text: Math.round(win.selW * (shot.sourceSize.width / Math.max(1, root.width))) + " × " + Math.round(win.selH * (shot.sourceSize.width / Math.max(1, root.width))); color: "white"; font.family: Theme.font; font.pixelSize: 12 }
            }

            // Hinweis, solange noch nichts ausgewählt ist
            Rectangle {
                visible: !win.hasSel && !win.dragging
                anchors.horizontalCenter: parent.horizontalCenter
                y: 48
                width: hint.implicitWidth + 36; height: 40; radius: 20
                color: Theme.panelStrong; border.color: Theme.border
                Text { id: hint; anchors.centerIn: parent; text: "Bereich aufziehen · Enter übernimmt (Editor) · Strg+C kopiert · Strg+S speichert · Esc bricht ab"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                hoverEnabled: false
                onPressed: mouse => { win.startX = mouse.x; win.startY = mouse.y; win.selX = mouse.x; win.selY = mouse.y; win.selW = 0; win.selH = 0; win.dragging = true; win.done = false; }
                onPositionChanged: mouse => {
                    if (!win.dragging) return;
                    const x = Math.max(0, Math.min(root.width, mouse.x)), y = Math.max(0, Math.min(root.height, mouse.y));
                    win.selX = Math.min(win.startX, x); win.selY = Math.min(win.startY, y);
                    win.selW = Math.abs(x - win.startX); win.selH = Math.abs(y - win.startY);
                }
                onReleased: { win.dragging = false; win.done = win.hasSel; }
            }

            // Werkzeugleiste unter der Auswahl
            Rectangle {
                id: bar
                visible: win.done && win.hasSel
                readonly property real wanted: win.selY + win.selH + 14
                x: Math.max(8, Math.min(root.width - width - 8, win.selX + win.selW - width))
                y: wanted + height > root.height - 8 ? Math.max(8, win.selY - height - 40) : wanted
                width: btnRow.implicitWidth + 20; height: 50; radius: 25
                color: Theme.panelStrong; border.color: Theme.border
                Row {
                    id: btnRow
                    anchors.centerIn: parent
                    spacing: 6
                    Repeater {
                        model: [{ t: "Übernehmen", m: "edit" }, { t: "Kopieren", m: "copy" }, { t: "Speichern", m: "save" }, { t: "Abbrechen", m: "cancel" }]
                        BarButton {
                            required property var modelData
                            implicitHeight: 34; padding: 14; radiusSize: 17
                            color: modelData.m === "edit" ? (hovered ? Theme.accentBright : Theme.accent) : (hovered ? Theme.tileHover : Theme.tile)
                            Text { text: modelData.t; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
                            onClicked: { if (modelData.m === "cancel") Global.snipClose(0); else win.act(modelData.m); }
                        }
                    }
                }
            }
        }
    }
}
