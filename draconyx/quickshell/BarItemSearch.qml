import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

BarButton {
    property var bar: null
    minWidth: 40
    implicitHeight: Global.barHeight - 10
    Icon { name: "search"; size: 19 }
    onClicked: Global.toggleStart(bar.mon)
}
