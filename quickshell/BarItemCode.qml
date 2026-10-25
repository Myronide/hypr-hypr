import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

BarButton {
    property var bar: null
    minWidth: 40
    implicitHeight: Global.barHeight - 10
    active: Global.codeOpen && Global.popupScreen === bar.mon
    Icon { name: "code"; size: 19; accent: Global.codeOpen && Global.popupScreen === bar.mon }
    onClicked: Global.toggleCode(bar.mon)
}
