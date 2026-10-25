import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Desktops: kompakte Punkte (aktiv = lang)
Row {
    id: dots
    property var bar: null
    leftPadding: 6
    rightPadding: 6
    spacing: 4
    Repeater {
        model: Hyprland.workspaces.values
            .filter(w => w.id > 0 && w.monitor && dots.bar && dots.bar.hyprMonitor && w.monitor.name === dots.bar.hyprMonitor.name)
            .sort((a, b) => a.id - b.id)
        delegate: Item {
            id: ws
            required property var modelData
            readonly property bool current: dots.bar && dots.bar.hyprMonitor && dots.bar.hyprMonitor.activeWorkspace
                                            && dots.bar.hyprMonitor.activeWorkspace.id === modelData.id
            readonly property bool isGame: modelData.name === "Spiel" || modelData.id === 10
            readonly property bool isCode: modelData.id === 8
            width: (isGame || isCode) ? 22 : (current ? 24 : 12)
            height: Global.barHeight - 10
            Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
            Rectangle {
                visible: !ws.isGame && !ws.isCode
                anchors.centerIn: parent
                width: parent.width; height: 6; radius: 3
                color: ws.current ? Theme.accent : (wsArea.containsMouse ? Theme.textDim : Qt.rgba(1, 1, 1, 0.22))
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            Icon { visible: ws.isGame; anchors.centerIn: parent; name: "game"; accent: ws.current; size: 16 }
            Icon { visible: ws.isCode; anchors.centerIn: parent; name: "code"; accent: ws.current; size: 16 }
            MouseArea {
                id: wsArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: Global.hypr("hl.dsp.focus({ workspace = " + ws.modelData.id + " })")
            }
        }
    }
}
