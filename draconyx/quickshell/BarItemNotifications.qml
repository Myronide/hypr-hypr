import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Benachrichtigungen mit Zähler
BarButton {
    id: notifBtn
    property var bar: null
    implicitHeight: Global.barHeight - 10
    Icon { name: Global.dnd ? "notif-dnd" : (Global.notifCount > 0 ? "notif-new" : "notif"); size: 18 }
    Rectangle {
        parent: notifBtn
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 2
        visible: Global.notifCount > 0 && !Global.dnd
        width: Math.max(16, badgeText.implicitWidth + 8); height: 16; radius: 8
        color: Theme.accent
        border.color: Theme.bg1; border.width: 2
        Text { id: badgeText; anchors.centerIn: parent; text: Global.notifCount; color: Theme.textOn; font.pixelSize: 9; font.family: Theme.font; font.bold: true }
    }
    onClicked: mouse => Global.run(mouse.button === Qt.RightButton ? "swaync-client -d -sw" : "swaync-client -t -sw")
}
