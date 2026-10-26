import QtQuick
import Quickshell
import Quickshell.Hyprland

// Update-Anzeige: erscheint nur, wenn ein neues Draconyx-Update bereitsteht. Klick: was ist neu + Aktualisieren.
BarButton {
    id: ub
    property var bar: null
    readonly property var info: Global.updateInfo || ({})
    readonly property bool avail: !!info.available
    property bool open: false
    visible: avail
    implicitWidth: avail ? 40 : 0
    implicitHeight: Global.barHeight - 10
    active: open
    tip: avail ? "Update " + info.latest + " verfügbar – anklicken für die Neuigkeiten" : ""
    Item {
        width: 20; height: 20
        Icon { anchors.centerIn: parent; name: "restart"; size: 19; accent: true }
        Rectangle { width: 8; height: 8; radius: 4; color: Theme.accentBright; anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: -2; anchors.topMargin: -2
                    border.color: Theme.panelStrong; border.width: 1 }
    }
    onClicked: open = !open
    onAvailChanged: if (!avail) open = false

    Loader {
        active: ub.open
        sourceComponent: PopupWindow {
            id: pop
            anchor.item: ub
            anchor.edges: Global.barTop ? Edges.Bottom : Edges.Top
            anchor.gravity: Global.barTop ? Edges.Bottom : Edges.Top
            anchor.margins.top: Global.barTop ? 10 : 0
            anchor.margins.bottom: Global.barTop ? 0 : 10
            implicitWidth: 380
            implicitHeight: Math.min(body.implicitHeight + 32, 560)
            color: "transparent"
            visible: true
            HyprlandFocusGrab { windows: [pop]; active: pop.visible; onCleared: ub.open = false }
            Surface {
                anchors.fill: parent
                level: 2
                radius: Theme.rL
                Column {
                    id: body
                    x: 16; y: 16; width: parent.width - 32
                    spacing: 10
                    Text { text: "Update " + ub.info.latest + " verfügbar"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold }
                    Text { text: "Installiert: " + ub.info.installed; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS }
                    Flickable {
                        ScrollSpeed { }
                        width: parent.width
                        height: Math.min(listCol.implicitHeight, 330)
                        contentHeight: listCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: listCol
                            width: parent.width
                            spacing: 12
                            Repeater {
                                model: (ub.info.changelog && ub.info.changelog.length > 0) ? ub.info.changelog : [{ version: ub.info.latest, items: ub.info.notes || [] }]
                                delegate: Column {
                                    required property var modelData
                                    width: listCol.width
                                    spacing: 4
                                    Text { text: "Version " + modelData.version; color: Theme.accentBright; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                                    Repeater {
                                        model: modelData.items
                                        delegate: Text {
                                            required property string modelData
                                            width: listCol.width
                                            text: "•  " + modelData
                                            wrapMode: Text.WordWrap
                                            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        spacing: 8
                        BarButton {
                            implicitHeight: 36; padding: 16; radiusSize: 18
                            color: hovered ? Theme.accentBright : Theme.accent
                            Text { text: "Jetzt aktualisieren"; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                            onClicked: { ub.open = false; Global.runUpdate(); }
                        }
                        BarButton {
                            implicitHeight: 36; padding: 14; radiusSize: 18
                            color: hovered ? Theme.tileHover : Theme.tile
                            Text { text: "Nicht mehr erinnern"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                            onClicked: { Global.updateMuted = ub.info.latest; ub.open = false; }
                        }
                    }
                }
            }
        }
    }
}
