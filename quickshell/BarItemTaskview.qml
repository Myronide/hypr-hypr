import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

BarButton {
    tip: "Fensterübersicht – alle offenen Fenster und Arbeitsflächen"
    property var bar: null
    minWidth: 40
    implicitHeight: Global.barHeight - 10
    active: Global.taskViewOpen && Global.popupScreen === bar.mon
    Icon { name: "apps"; size: 19 }
    onClicked: Global.toggleTaskView(bar.mon)
}
