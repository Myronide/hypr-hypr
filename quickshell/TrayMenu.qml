import QtQuick
import Quickshell
import Quickshell.Hyprland

// Kontextmenü eines Systray-Symbols (Rechtsklick). Eigene Darstellung statt Plattformmenü: die Plattformmenüs von Quickshell
// brauchen den QApplication-Modus und gingen deshalb gar nicht auf. Untermenüs öffnen sich in derselben Liste („‹ Zurück“).
PopupWindow {
    id: pm
    required property var trayItem
    required property Item anchorItem
    property var stack: []                                     // Pfad in Untermenüs
    readonly property var current: stack.length > 0 ? stack[stack.length - 1] : trayItem.menu
    signal dismissed()

    anchor.item: anchorItem
    anchor.edges: Global.barTop ? Edges.Bottom : Edges.Top
    anchor.gravity: Global.barTop ? Edges.Bottom : Edges.Top
    anchor.margins.top: Global.barTop ? 10 : 0
    anchor.margins.bottom: Global.barTop ? 0 : 10
    implicitWidth: 260
    implicitHeight: Math.min(col.implicitHeight + 16, 560)
    color: "transparent"
    visible: true

    HyprlandFocusGrab { windows: [pm]; active: pm.visible; onCleared: pm.dismissed() }
    QsMenuOpener { id: opener; menu: pm.current }

    function clean(t) { return (t || "").replace(/_(?!_)/g, "").replace(/&(?!&)/g, ""); }   // Mnemonik-Zeichen entfernen

    Surface {
        anchors.fill: parent
        level: 2
        radius: Theme.rM
        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: parent.width
                spacing: 2
                MenuRow {
                    visible: pm.stack.length > 0
                    width: col.width
                    label: "‹   Zurück"
                    onTriggered: pm.stack = pm.stack.slice(0, -1)
                }
                Text {
                    visible: opener.children && opener.children.values.length === 0
                    text: "Kein Menü"
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS
                    leftPadding: 10; topPadding: 8; bottomPadding: 8
                }
                Repeater {
                    model: opener.children
                    delegate: Item {
                        id: entry
                        required property var modelData
                        width: col.width
                        height: modelData.isSeparator ? 9 : rowItem.implicitHeight
                        Rectangle { visible: entry.modelData.isSeparator; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.borderSoft }
                        MenuRow {
                            id: rowItem
                            visible: !entry.modelData.isSeparator
                            width: parent.width
                            enabled: entry.modelData.enabled
                            opacity: enabled ? 1 : 0.45
                            label: (entry.modelData.buttonType !== QsMenuButtonType.None && entry.modelData.checkState === Qt.Checked ? "✓  " : "")
                                   + pm.clean(entry.modelData.text) + (entry.modelData.hasChildren ? "   ›" : "")
                            iconSource: entry.modelData.icon || ""
                            onTriggered: {
                                if (entry.modelData.hasChildren) pm.stack = pm.stack.concat([entry.modelData]);
                                else { entry.modelData.triggered(); pm.dismissed(); }
                            }
                        }
                    }
                }
            }
        }
    }
}
