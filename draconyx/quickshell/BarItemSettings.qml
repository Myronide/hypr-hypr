import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Einstellungen (Aurora)
BarButton {
    property var bar: null
    minWidth: 38
    implicitHeight: Global.barHeight - 10
    Icon { name: "settings"; size: 19 }
    onClicked: Global.openSettings()
}
