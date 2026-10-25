import QtQuick

// Regler mit Icon links (Icon-Klick = stumm) und Prozent rechts
Item {
    id: row
    property string iconName
    property real value: 0          // 0..1
    signal moved(real value)
    signal iconClicked()

    implicitHeight: 40

    BarButton {
        id: iconBtn
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        minWidth: 38
        implicitHeight: 38
        Icon { name: row.iconName; size: 19 }
        onClicked: row.iconClicked()
    }

    Item {
        id: track
        anchors.left: iconBtn.right
        anchors.leftMargin: 10
        anchors.right: pct.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 24

        readonly property real shown: drag.pressed ? drag.live : row.value

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: 3
            color: Qt.rgba(1, 1, 1, 0.10)
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(6, parent.width * Math.min(1, track.shown)); height: 6; radius: 3
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accentDeep }
                GradientStop { position: 1; color: Theme.accent }
            }
        }
        Rectangle {
            x: parent.width * Math.min(1, track.shown) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: drag.pressed || drag.containsMouse ? 20 : 16
            height: width; radius: width / 2
            color: "#ffffff"
            border.color: Theme.accent; border.width: 3
            Behavior on width { NumberAnimation { duration: 100 } }
        }
        MouseArea {
            id: drag
            property real live: 0
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            function update(mx) {
                live = Math.max(0, Math.min(1, (mx - 6) / track.width));
                row.moved(live);
            }
            onPressed: mouse => update(mouse.x)
            onPositionChanged: mouse => { if (pressed) update(mouse.x); }
            onWheel: wheel => row.moved(Math.max(0, Math.min(1, row.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }

    Text {
        id: pct
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 38
        horizontalAlignment: Text.AlignRight
        text: Math.round(Math.min(1, track.shown) * 100) + "%"
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 12
    }
}
