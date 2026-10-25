import QtQuick
import Quickshell.Widgets

// Zeile in Menüs und Listen: Fluent-Icon (iconName) oder App-/Dateibild (iconSource), Titel, Untertitel, optional Schließen-Knopf
Rectangle {
    id: row
    property string label
    property string subLabel: ""
    property string iconName: ""
    property string iconSource: ""
    property bool highlighted: false
    property bool closable: false
    signal triggered()
    signal closeRequested()

    readonly property bool hasIcon: iconName !== "" || iconSource !== ""
    implicitHeight: subLabel !== "" ? 48 : 38
    radius: Theme.rS + 2
    color: area.containsMouse ? Theme.tileHover : (highlighted ? Theme.accentSoft : "transparent")
    border.color: highlighted ? Theme.border : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durFast } }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Item {
            visible: row.hasIcon
            width: row.iconSource !== "" ? 28 : 18
            height: width
            anchors.verticalCenter: parent.verticalCenter
            IconImage { anchors.fill: parent; visible: row.iconSource !== ""; source: row.iconSource }
            Icon { anchors.centerIn: parent; visible: row.iconSource === "" && row.iconName !== ""; name: row.iconName; size: 17 }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            readonly property real avail: row.width - 20 - (row.hasIcon ? (row.iconSource !== "" ? 38 : 28) : 0) - (row.closable ? 34 : 0)
            Text {
                text: row.label
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fsM
                elide: Text.ElideRight
                width: parent.avail
            }
            Text {
                visible: row.subLabel !== ""
                text: row.subLabel
                color: Theme.textDim
                font.family: Theme.font
                font.pixelSize: Theme.fsXs
                elide: Text.ElideMiddle
                width: parent.avail
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: row.triggered()
    }

    Rectangle {
        visible: row.closable
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 26; height: 26; radius: 8
        color: closeArea.containsMouse ? Qt.rgba(1, 0.42, 0.42, 0.25) : "transparent"
        Icon { anchors.centerIn: parent; name: "close"; size: 14 }
        MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: row.closeRequested() }
    }
}
