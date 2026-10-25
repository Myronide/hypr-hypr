import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Tray-Symbole mit Trennstrich dahinter
Row {
    id: trayRow
    property var bar: null
    spacing: 2
    Repeater {
        model: SystemTray.items.values
        delegate: BarButton {
            id: trayBtn
            required property var modelData
            required property int index
            property bool menuOpen: false
            tip: modelData.tooltipTitle || modelData.title || modelData.id || ""
            minWidth: 32
            padding: 7
            implicitHeight: Global.barHeight - 14
            IconImage { implicitSize: 18; source: trayBtn.modelData.icon }
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton && !modelData.onlyMenu) {
                    modelData.activate();
                } else if (modelData.hasMenu) {
                    menuOpen = !menuOpen;                      // Rechtsklick (oder Symbol nur mit Menü): eigenes Kontextmenü
                } else {
                    modelData.secondaryActivate();
                }
            }
            Loader {
                active: trayBtn.menuOpen
                sourceComponent: TrayMenu { trayItem: trayBtn.modelData; anchorItem: trayBtn; onDismissed: trayBtn.menuOpen = false }
            }
            onScrolled: wheel => modelData.scroll(wheel.angleDelta.y, false)
        }
    }
    Rectangle { width: 1; height: 22; color: Theme.borderSoft; anchors.verticalCenter: parent.verticalCenter }
}
