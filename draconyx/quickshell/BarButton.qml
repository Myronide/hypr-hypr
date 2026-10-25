import QtQuick

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
         : (area.containsMouse || active) ? Theme.tileHover
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

        onPressed: mouse => { pressX = mouse.x; wasDrag = false; }
        onPositionChanged: mouse => {
            if (!btn.draggable || !pressed || !(pressedButtons & Qt.LeftButton)) return;
            const dx = mouse.x - pressX;
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
