import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Fenstermodus: frei schwebend <-> Kacheln (Standard für neue Fenster)
BarButton {
    tip: "Fenstermodus – umschalten zwischen frei schwebend und Kacheln"
    property var bar: null
    minWidth: 40
    implicitHeight: Global.barHeight - 10
    active: Global.windowMode === "tiling"
    Icon { name: Global.windowMode === "tiling" ? "apps" : "window"; size: 19; accent: Global.windowMode === "tiling" }
    onClicked: Global.toggleWindowMode()
}
