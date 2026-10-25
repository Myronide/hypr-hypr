import QtQuick
import Quickshell
import Quickshell.Wayland

// Unsichtbare Fläche über dem Bildschirm (ohne Leistenbereich), solange ein Taskleisten-Menü offen ist:
// Ein Klick daneben schließt das Menü – unabhängig davon, ob das Fokus-Greifen der Popups greift.
PanelWindow {
    id: dc
    required property var modelData
    screen: modelData
    visible: Global.taskMenuOpen
    anchors { left: true; right: true; top: true; bottom: true }
    margins.bottom: Global.barTop ? 0 : Math.round(Global.barHeight + Global.barMargin * 2)
    margins.top: Global.barTop ? Math.round(Global.barHeight + Global.barMargin * 2) : 0
    exclusiveZone: -1
    color: "#01000000"
    WlrLayershell.namespace: "draconyx-dismiss"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: Global.taskMenuClose()
    }
}
