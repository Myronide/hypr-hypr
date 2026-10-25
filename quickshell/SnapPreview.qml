import QtQuick
import Quickshell
import Quickshell.Wayland

// Vorschau-Rahmen beim Andocken (Fenster an Rand/Ecke ziehen). Klickdurchlässig.
// Die Zone kommt aus Hyprland (dx_snap.lua) über Global.snapRect.
PanelWindow {
    id: prev
    required property var modelData
    screen: modelData

    readonly property var r: Global.snapRect
    readonly property bool active: r !== null && r.mon === modelData.name

    visible: active || fade.running || box.opacity > 0.01
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}            // leer = Eingaben gehen durch
    WlrLayershell.namespace: "draconyx-snap"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: box
        radius: Theme.rL
        color: Theme.accentSoft
        border.color: Theme.accent
        border.width: 2
        opacity: prev.active ? 1 : 0
        x: prev.active ? prev.r.x - prev.modelData.x : x
        y: prev.active ? prev.r.y - prev.modelData.y : y
        width: prev.active ? prev.r.w : width
        height: prev.active ? prev.r.h : height

        Behavior on x       { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
        Behavior on y       { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
        Behavior on width   { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
        Behavior on height  { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.durFast } }
    }
}
