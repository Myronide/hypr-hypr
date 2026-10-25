import QtQuick
import Quickshell
import Quickshell.Wayland

// Fenstermenü (Alt+Leertaste, wie das Systemmenü unter Windows) für Apps ohne eigene Titelleiste.
// Global.winMenu = { addr, x, y }  (globale Koordinaten der oberen linken Ecke des Fensters)
PanelWindow {
    id: wm
    readonly property var info: Global.winMenu
    readonly property var scr: info ? Global.screenAt(info.x, info.y) : null
    screen: scr

    visible: info !== null && scr !== null
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "draconyx-windowmenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function act(lua) { Global.hypr(lua); Global.winMenu = null; }
    readonly property string win: info ? "window = \"address:" + info.addr + "\"" : ""

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Global.winMenu = null
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: Global.winMenu = null }

        Surface {
            level: 2
            radius: Theme.rM
            width: 270
            height: col.implicitHeight + 16
            x: wm.info && wm.scr ? Math.max(8, Math.min(wm.info.x - wm.scr.x + 6, wm.scr.width - width - 8)) : 0
            y: wm.info && wm.scr ? Math.max(8, Math.min(wm.info.y - wm.scr.y + 6, wm.scr.height - height - 8)) : 0

            Column {
                id: col
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                MenuRow {
                    width: col.width; iconName: "window"; label: "Maximieren / Wiederherstellen"
                    onTriggered: { Global.hyprEval("DXSnap.toggleMaxAddr('" + wm.info.addr + "')"); Global.winMenu = null; }
                }
                MenuRow {
                    width: col.width; iconName: "chevron-down"; label: "Minimieren"
                    onTriggered: { Global.minimizeAddr(wm.info.addr); Global.winMenu = null; }
                }
                MenuRow {
                    width: col.width; iconName: "taskbar"; label: "Ins Raster / aus dem Raster"
                    onTriggered: { Global.hyprEval("DXTiling.toggleAddr('" + wm.info.addr + "')"); Global.winMenu = null; }
                }
                MenuRow {
                    width: col.width; iconName: "desktop"; label: "Auf nächsten Monitor"
                    onTriggered: wm.act("hl.dsp.window.move({ " + wm.win + ", monitor = \"r\", follow = true })")
                }
                MenuRow {
                    width: col.width; iconName: "pin"; label: "Immer im Vordergrund (an/aus)"
                    onTriggered: wm.act("hl.dsp.window.pin({ " + wm.win + ", action = \"toggle\" })")
                }
                Rectangle { width: col.width; height: 1; color: Theme.borderSoft }
                MenuRow {
                    width: col.width; iconName: "close"; label: "Schließen"
                    onTriggered: wm.act("hl.dsp.window.close({ " + wm.win + " })")
                }
                MenuRow {
                    width: col.width; iconName: "power"; label: "Beenden erzwingen"
                    onTriggered: wm.act("hl.dsp.window.kill({ " + wm.win + " })")
                }
            }
        }
    }
}
