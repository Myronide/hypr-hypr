import QtQuick
import Quickshell
import Quickshell.Wayland

// Raster-Overlay pro Monitor:
//  edit  = Zonen selbst einrichten (Vorlagen, Trennlinien ziehen, Zonen teilen/entfernen)
//  pick  = Zone für das aktive Fenster wählen (Klick oder Ziffer)
//  flash = Raster kurz einblenden (z. B. nach dem Kacheln)
//  hint  = beim Ziehen mit Shift: Zonen zeigen, Zone unter dem Zeiger hervorheben
PanelWindow {
    id: ge
    required property var modelData
    screen: modelData

    readonly property string mon: modelData.name
    readonly property string mode: Global.gridMode
    readonly property bool active: mode !== "" && Global.gridScreen === mon
    readonly property bool hint: Global.zoneHint !== null && Global.zoneHint.mon === mon
    readonly property bool interactive: active && (mode === "edit" || mode === "pick")
    readonly property var lay: Global.computeLayout(Global.layoutFor(mon), Global.zoneArea(modelData))
    readonly property var selZone: lay.zones.find(z => z.path === Global.zoneSel) || null

    visible: active || hint
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "draconyx-grid"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: interactive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region { item: ge.interactive ? root : none }
    Item { id: none; width: 0; height: 0 }

    onInteractiveChanged: if (interactive) root.forceActiveFocus()

    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Global.closeGrid()
        Keys.onPressed: event => {
            if (ge.mode === "pick" && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                const i = event.key - Qt.Key_0;
                if (i <= ge.lay.zones.length) Global.pickZone(i);
            }
        }

        // Abdunkelung (nur Editor/Auswahl)
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.02, 0.015, 0.05, 0.58)
            opacity: ge.interactive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durBase } }
            MouseArea { anchors.fill: parent; enabled: ge.interactive; onClicked: Global.zoneSel = "*" }
        }

        // ---------- Zonen ----------
        Repeater {
            model: ge.lay.zones
            delegate: Rectangle {
                id: zone
                required property var modelData
                required property int index
                readonly property bool hovered: zoneArea.containsMouse
                readonly property bool isHint: ge.hint && Global.zoneHint.idx === index + 1
                readonly property bool isSel: ge.mode === "edit" && Global.zoneSel === modelData.path
                x: modelData.x + 4; y: modelData.y + 4
                width: modelData.w - 8; height: modelData.h - 8
                radius: Theme.rM
                color: isHint ? Theme.alpha(Theme.accent, 0.32)
                     : isSel ? Theme.alpha(Theme.accent, 0.24)
                     : (ge.mode === "pick" && hovered) ? Theme.alpha(Theme.accent, 0.28)
                     : Qt.rgba(1, 1, 1, 0.06)
                border.color: isHint || isSel ? Theme.accent : Theme.alpha(Theme.accent, 0.55)
                border.width: isHint || isSel ? 3 : 2
                Behavior on color { ColorAnimation { duration: Theme.durFast } }

                Text {
                    anchors.centerIn: parent
                    text: zone.index + 1
                    color: Qt.rgba(1, 1, 1, zone.isHint || zone.isSel ? 0.95 : 0.5)
                    font.family: Theme.font; font.pixelSize: Math.min(72, Math.min(zone.width, zone.height) * 0.35); font.weight: Font.Light
                }
                MouseArea {
                    id: zoneArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: ge.interactive
                    onClicked: {
                        if (ge.mode === "pick") Global.pickZone(zone.index + 1);
                        else Global.zoneSel = zone.modelData.path;
                    }
                }
            }
        }

        // ---------- Trennlinien (nur Editor): ziehen ----------
        Repeater {
            model: ge.mode === "edit" && ge.interactive ? ge.lay.dividers : []
            delegate: Item {
                id: div
                required property var modelData
                readonly property bool vertical: modelData.dir === "v"
                x: vertical ? modelData.x - 9 : modelData.x
                y: vertical ? modelData.y : modelData.y - 9
                width: vertical ? 18 : modelData.len
                height: vertical ? modelData.len : 18
                z: 5

                Rectangle {
                    anchors.centerIn: parent
                    width: div.vertical ? (divArea.containsMouse || divArea.pressed ? 6 : 4) : div.width - 20
                    height: div.vertical ? div.height - 20 : (divArea.containsMouse || divArea.pressed ? 6 : 4)
                    radius: 3
                    color: divArea.containsMouse || divArea.pressed ? Theme.accentBright : Theme.accent
                    Behavior on width { NumberAnimation { duration: Theme.durFast } }
                    Behavior on height { NumberAnimation { duration: Theme.durFast } }
                }
                MouseArea {
                    id: divArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: div.vertical ? Qt.SizeHorCursor : Qt.SizeVerCursor
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        const p = mapToItem(root, mouse.x, mouse.y);
                        const r = div.vertical ? (p.x - div.modelData.px) / div.modelData.pw
                                               : (p.y - div.modelData.py) / div.modelData.ph;
                        Global.setRatio(ge.mon, div.modelData.path, r);
                    }
                }
            }
        }

        // ---------- Aktionen für die gewählte Zone ----------
        Surface {
            visible: ge.mode === "edit" && ge.selZone !== null
            level: 2
            radius: Theme.rM
            width: actions.implicitWidth + 16
            height: 54
            x: ge.selZone ? ge.selZone.x + ge.selZone.w / 2 - width / 2 : 0
            y: ge.selZone ? ge.selZone.y + ge.selZone.h / 2 + 34 : 0
            z: 8
            Row {
                id: actions
                anchors.centerIn: parent
                spacing: 4
                BarButton {
                    implicitHeight: 38; padding: 12
                    Row { spacing: 8
                        Icon { name: "chevron-right"; size: 15; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Senkrecht teilen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                    }
                    onClicked: Global.splitZone(ge.mon, Global.zoneSel, "v")
                }
                BarButton {
                    implicitHeight: 38; padding: 12
                    Row { spacing: 8
                        Icon { name: "chevron-down"; size: 15; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Waagerecht teilen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                    }
                    onClicked: Global.splitZone(ge.mon, Global.zoneSel, "h")
                }
                BarButton {
                    implicitHeight: 38; padding: 12
                    visible: ge.lay.zones.length > 1
                    Row { spacing: 8
                        Icon { name: "close"; size: 14; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Entfernen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                    }
                    onClicked: Global.removeZone(ge.mon, Global.zoneSel)
                }
            }
        }

        // ---------- Kopfleiste ----------
        Surface {
            visible: ge.interactive
            level: 2
            radius: Theme.rL
            width: head.implicitWidth + 28
            height: ge.mode === "edit" ? 100 : 56
            anchors.horizontalCenter: parent.horizontalCenter
            y: Global.barTop ? Global.barHeight + 30 : 24
            z: 9
            Column {
                id: head
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ge.mode === "pick" ? "Zone für das Fenster wählen (Klick oder Ziffer)  ·  Esc bricht ab"
                                             : "Raster einrichten – Trennlinien ziehen, Zone anklicken zum Teilen oder Entfernen"
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS
                }
                Row {
                    visible: ge.mode === "edit"
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: Global.zonePresetNames
                        delegate: BarButton {
                            required property var modelData
                            implicitHeight: 34; padding: 12; radiusSize: 17
                            color: hovered ? Theme.tileHover : Theme.tile
                            Text { text: modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                            onClicked: Global.applyPreset(ge.mon, modelData)
                        }
                    }
                    BarButton {
                        implicitHeight: 34; padding: 14; radiusSize: 17
                        color: hovered ? Theme.accentBright : Theme.accent
                        Text { text: "Fertig"; color: Theme.textOn; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
                        onClicked: Global.closeGrid()
                    }
                }
            }
        }
    }
}
