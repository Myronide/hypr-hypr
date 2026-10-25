import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Netzwerk + Lautstärke -> Schnelleinstellungen
BarButton {
    tip: "Schnelleinstellungen – Netzwerk, Lautstärke, Helligkeit, Energie"
    property var bar: null
    implicitHeight: Global.barHeight - 10
    active: Global.controlOpen && Global.popupScreen === bar.mon
    Row {
        spacing: 10
        Icon { name: Global.netType === "ethernet" ? "ethernet" : (Global.netType === "wifi" ? "wifi" : "net-off"); size: 18 }
        Icon { name: bar.muted ? "vol-mute" : (bar.volume < 0.35 ? "vol-low" : "vol"); size: 18 }
    }
    onClicked: Global.toggleControl(bar.mon)
    onScrolled: wheel => {
        if (!bar.sink || !bar.sink.audio) return;
        const v = bar.sink.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05);
        bar.sink.audio.volume = Math.max(0, Math.min(1, v));
    }
}
