import QtQuick
import Quickshell.Widgets

// App-Kachel im Startmenü: Icon + Name, ziehbar (Sortierung), Rechtsklick-Menü.
// Mit folderIcons (bis zu 4 Quellen) wird stattdessen ein Ordner mit Mini-Icons gezeichnet.
Item {
    id: tile
    property string label
    property string iconSource
    property var folderIcons: []
    property bool draggable: false
    property int slotW: 106
    property int slotH: 98
    property bool selected: false
    property bool dragging: false
    property real dragX: 0
    property real dragY: 0

    signal activated()
    signal menuRequested(real x, real y)
    signal dropped(real dx, real dy)

    width: slotW
    height: slotH
    z: dragging ? 20 : 0
    transform: Translate { x: tile.dragX; y: tile.dragY }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: Theme.rM
        color: tile.dragging ? Theme.accentSoft : (area.containsMouse || tile.selected ? Theme.tileHover : "transparent")
        border.color: tile.selected ? Theme.accent : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
    }

    Column {
        anchors.centerIn: parent
        spacing: 7
        scale: area.pressed && !tile.dragging ? 0.95 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeOut } }

        Item {
            width: 42; height: 42
            anchors.horizontalCenter: parent.horizontalCenter

            IconImage {
                anchors.fill: parent
                visible: tile.folderIcons.length === 0
                source: tile.iconSource
            }
            // Ordner: 2x2 Mini-Icons in einer Glas-Kachel
            Rectangle {
                anchors.fill: parent
                visible: tile.folderIcons.length > 0
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.10)
                border.color: Theme.borderSoft
                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    spacing: 3
                    Repeater {
                        model: tile.folderIcons.slice(0, 4)
                        delegate: IconImage { required property var modelData; implicitSize: 15; source: modelData }
                    }
                }
            }
        }
        Text {
            width: tile.slotW - 14
            horizontalAlignment: Text.AlignHCenter
            text: tile.label
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.fsS
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real px: 0
        property real py: 0
        property bool moved: false

        onPressed: mouse => { px = mouse.x; py = mouse.y; moved = false; }
        onPositionChanged: mouse => {
            if (!tile.draggable || !pressed || !(pressedButtons & Qt.LeftButton)) return;
            const dx = mouse.x - px, dy = mouse.y - py;
            if (tile.dragging || Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                tile.dragging = true; moved = true;
                tile.dragX = dx; tile.dragY = dy;
            }
        }
        onReleased: mouse => {
            if (tile.dragging) {
                const dx = tile.dragX, dy = tile.dragY;
                tile.dragging = false; tile.dragX = 0; tile.dragY = 0;
                tile.dropped(dx, dy);
            }
        }
        onClicked: mouse => {
            if (moved) return;
            if (mouse.button === Qt.RightButton) {
                const p = area.mapToItem(null, mouse.x, mouse.y);
                tile.menuRequested(p.x, p.y);
            } else tile.activated();
        }
    }
}
