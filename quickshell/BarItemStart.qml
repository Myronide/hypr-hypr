import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Startknopf (Rechtsklick: Symbol wählen)
BarButton {
    tip: "Startmenü – Apps, Suche und Ein/Aus (Rechtsklick: Symbol ändern)"
    id: startBtn
    property var bar: null
    minWidth: 44
    implicitHeight: Global.barHeight - 10
    active: Global.startOpen && Global.popupScreen === bar.mon
    // bar wird vom Loader erst nach dem Erzeugen gesetzt – deshalb auf die Änderung reagieren, nicht auf onCompleted
    onBarChanged: if (bar) bar.startItem = startBtn
    Image {
        source: Global.startLogoUrl
        width: 34; height: 34
        sourceSize: Qt.size(68, 68)
        smooth: true; mipmap: true
    }
    onClicked: mouse => { if (mouse.button === Qt.RightButton) bar.logoMenuToggle(); else Global.toggleStart(bar.mon); }
}
