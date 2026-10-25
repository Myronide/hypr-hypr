import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// App-Knöpfe (angeheftet + laufend, gruppiert)
Row {
    id: appsRow
    property var bar: null
    spacing: 2
    Repeater {
        model: appsRow.bar ? appsRow.bar.groups : []
        delegate: TaskButton {
            required property var modelData
            group: modelData
            mon: appsRow.bar.mon
            slot: width + appsRow.spacing
            implicitHeight: Global.barHeight - 10
        }
    }
}
