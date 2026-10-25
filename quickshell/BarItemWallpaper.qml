import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

BarButton {
    tip: "Wallpaper wählen (Bilder und Wallpaper Engine)"
    property var bar: null
    minWidth: 40
    implicitHeight: Global.barHeight - 10
    active: Global.weOpen && Global.popupScreen === bar.mon
    Icon { name: "desktop"; size: 19; accent: Global.weOpen && Global.popupScreen === bar.mon }
    onClicked: Global.toggleWe(bar.mon)
}
