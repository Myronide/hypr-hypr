import QtQuick

// Schnelleinstellungs-Kachel (an = violett)
Rectangle {
    id: tile
    property string iconName
    property string label
    property bool checked: false
    signal clicked()

    implicitHeight: 74
    radius: 14
    color: checked ? (area.containsMouse ? Theme.accentBright : Theme.accent)
                   : (area.containsMouse ? Theme.tileHover : Theme.tile)
    border.color: checked ? "transparent" : Theme.borderSoft
    Behavior on color { ColorAnimation { duration: 150 } }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Icon { name: tile.iconName; size: 20 }
        Text {
            text: tile.label
            color: tile.checked ? "#ffffff" : Theme.text
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
            width: tile.width - 24
            elide: Text.ElideRight
        }
    }

    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: tile.clicked() }
}
