import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Schmaler Streifen: Desktop anzeigen
BarButton {
    tip: "Schreibtisch zeigen – alle Fenster ausblenden / zurückholen"
    property var bar: null
    minWidth: 12; padding: 0
    implicitHeight: Global.barHeight - 14
    Rectangle { width: 2; height: 18; radius: 1; color: Theme.borderSoft }
    onClicked: {
        const ws = bar.hyprMonitor ? bar.hyprMonitor.activeWorkspace : null;
        if (ws && ws.toplevels && ws.toplevels.values.length > 0) {
            Global.lastWorkspace = ws.id;
            Global.hypr("hl.dsp.focus({ workspace = \"empty\" })");
        } else {
            Global.hypr("hl.dsp.focus({ workspace = " + Global.lastWorkspace + " })");
        }
    }
}
