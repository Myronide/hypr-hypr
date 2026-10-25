import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Startknopf (Rechtsklick: Symbol wählen)
BarButton {
    id: startBtn
    property var bar: null
    minWidth: 44
    implicitHeight: Global.barHeight - 10
    active: Global.startOpen && Global.popupScreen === bar.mon
    Component.onCompleted: if (bar) bar.startItem = startBtn
    Image {
        source: Global.startLogoUrl
        width: 34; height: 34
        sourceSize: Qt.size(68, 68)
        smooth: true; mipmap: true
    }
    onClicked: mouse => { if (mouse.button === Qt.RightButton) bar.logoMenuToggle(); else Global.toggleStart(bar.mon); }
}
