import QtQuick
import Quickshell

// Basis-Kachel mit Hover/Press-Zustand. Optional ziehbar (Drag-and-drop zum Sortieren).
Rectangle {
    id: btn
    default property alias content: inner.data
    property bool active: false
    property bool draggable: false
    property int padding: 10
    property int minWidth: 40
    property int radiusSize: Theme.rM
    readonly property bool hovered: area.containsMouse
    readonly property bool pressed: area.pressed
    property real dragOffset: 0                  // Verschiebung während des Ziehens
    property bool dragging: false
    property string tip: ""                      // Quickinfo (Erklärung beim Überfahren)
    property bool tipOn: false

    // ---------- Quickinfo ----------
    Timer { id: tipTimer; interval: 550; running: btn.hovered && btn.tip !== "" && Global.tooltips && !btn.dragging && !btn.pressed; onTriggered: btn.tipOn = true }
    onHoveredChanged: if (!hovered) tipOn = false
    onPressedChanged: if (pressed) tipOn = false
    Loader {
        active: btn.tipOn
        sourceComponent: PopupWindow {
            anchor.item: btn
            anchor.edges: Global.barTop ? Edges.Bottom : Edges.Top
            anchor.gravity: Global.barTop ? Edges.Bottom : Edges.Top
            anchor.margins.top: Global.barTop ? 10 : 0
            anchor.margins.bottom: Global.barTop ? 0 : 10
            implicitWidth: tipText.implicitWidth + 24
            implicitHeight: tipText.implicitHeight + 14
            color: "transparent"
            visible: true
            mask: Region {}                       // Mausereignisse gehen durch (sonst flackert die Quickinfo)
            Rectangle {
                anchors.fill: parent
                radius: Theme.rS
                color: Theme.panelStrong
                border.color: Theme.border
                Text { id: tipText; anchors.centerIn: parent; text: btn.tip; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
            }
        }
    }

    signal clicked(var mouse)
    signal scrolled(var wheel)
    signal dragMoved(real dx)
    signal dragDropped(real dx)

    implicitWidth: Math.max(minWidth, inner.width + 2 * padding)
    implicitHeight: 40
    width: implicitWidth
    height: implicitHeight
    radius: radiusSize
    color: dragging ? Theme.accentSoft
         : area.pressed ? Theme.tilePress
         : active ? Theme.selected
         : area.containsMouse ? Theme.tileHover
         : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durFast } }
    z: dragging ? 10 : 0
    transform: Translate { x: btn.dragOffset }

    Item {
        id: inner
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
        scale: area.pressed && !btn.dragging ? 0.94 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeOut } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        property real pressX: 0
        property bool wasDrag: false

        // Fensterkoordinaten statt Knopfkoordinaten: der Knopf verschiebt sich beim Ziehen selbst, sonst schaukelt sich die Messung auf
        function sceneX(mouse) { return area.mapToItem(null, mouse.x, mouse.y).x; }
        onPressed: mouse => { pressX = sceneX(mouse); wasDrag = false; }
        onPositionChanged: mouse => {
            if (!btn.draggable || !pressed || !(pressedButtons & Qt.LeftButton)) return;
            const dx = sceneX(mouse) - pressX;
            if (btn.dragging || Math.abs(dx) > 10) {
                btn.dragging = true;
                wasDrag = true;
                btn.dragOffset = dx;
                btn.dragMoved(dx);
            }
        }
        onReleased: mouse => {
            if (btn.dragging) {
                const dx = btn.dragOffset;
                btn.dragging = false;
                btn.dragOffset = 0;
                btn.dragDropped(dx);
            }
        }
        onClicked: mouse => { if (!wasDrag) btn.clicked(mouse); }
        onWheel: wheel => btn.scrolled(wheel)
    }
}
