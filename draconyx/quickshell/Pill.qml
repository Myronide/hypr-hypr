import QtQuick

// Schwebende Glas-Pille der Taskleiste
Rectangle {
    default property alias content: row.data
    property alias spacing: row.spacing

    implicitWidth: row.implicitWidth + 14
    implicitHeight: Global.barHeight
    width: implicitWidth
    height: implicitHeight
    radius: Theme.radius
    color: Theme.panel
    border.color: Theme.border
    border.width: 1

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2
    }
}
