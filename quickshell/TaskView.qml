import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Task View: alle Desktops oben, darunter die Fenster des gewählten Desktops mit Live-Vorschau.
// Fenster per Ziehen auf einen Desktop verschieben, "+" legt einen neuen Desktop an. Esc oder Klick daneben schließt.
PanelWindow {
    id: tv
    visible: Global.taskViewOpen
    screen: Global.screenByName(Global.popupScreen)

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "draconyx-taskview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property var hyprMon: Hyprland.monitorFor(screen)
    property int wsSel: 1

    // Desktops dieses Monitors (ohne den versteckten "minimized"-Workspace)
    readonly property var workspaces: Hyprland.workspaces.values
        .filter(w => w.id > 0 && w.monitor && hyprMon && w.monitor.name === hyprMon.name)
        .sort((a, b) => a.id - b.id)
    readonly property int nextFreeId: {
        let m = 0;
        for (const w of Hyprland.workspaces.values) if (w.id > m) m = w.id;
        return Math.max(m, 9) + 1 > 10 ? m + 1 : 10;
    }
    // Fenster des gewählten Desktops (plus minimierte, damit nichts "verloren" geht)
    readonly property var windows: Hyprland.toplevels.values.filter(t =>
        t.workspace && (t.workspace.id === wsSel || (wsSel === (hyprMon && hyprMon.activeWorkspace ? hyprMon.activeWorkspace.id : -1) && t.workspace.name === Global.minWsName)))

    onVisibleChanged: {
        if (visible) {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
            wsSel = hyprMon && hyprMon.activeWorkspace ? hyprMon.activeWorkspace.id : 1;
            keys.forceActiveFocus();
        }
    }

    HyprlandFocusGrab {
        windows: [tv]
        active: tv.visible
        onCleared: Global.taskViewOpen = false
    }

    // Abdunkelung + Klick daneben schließt
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.015, 0.05, 0.66)
        opacity: tv.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durBase } }
        MouseArea { anchors.fill: parent; onClicked: Global.taskViewOpen = false }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Global.taskViewOpen = false
        Keys.onLeftPressed: { const i = tv.workspaces.findIndex(w => w.id === tv.wsSel); if (i > 0) tv.wsSel = tv.workspaces[i - 1].id; }
        Keys.onRightPressed: { const i = tv.workspaces.findIndex(w => w.id === tv.wsSel); if (i >= 0 && i < tv.workspaces.length - 1) tv.wsSel = tv.workspaces[i + 1].id; }

        // ---------- Desktops oben ----------
        Row {
            id: wsRow
            anchors.top: parent.top
            anchors.topMargin: 56
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14

            Repeater {
                model: tv.workspaces
                delegate: Item {
                    id: wsCard
                    required property var modelData
                    readonly property bool current: modelData.id === tv.wsSel
                    readonly property bool isGame: modelData.name === "Spiel"
                    width: 236; height: 150

                    Surface {
                        anchors.fill: parent
                        level: current ? 2 : 1
                        radius: Theme.rM
                        border.color: wsCard.current ? Theme.accent : (drop.containsDrag ? Theme.accentBright : Theme.border)
                        border.width: wsCard.current || drop.containsDrag ? 2 : 1
                        opacity: wsCard.current ? 1 : 0.8
                        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                    }
                    // Mini-Vorschau: Fenster als Rechtecke im Desktop-Verhältnis
                    Item {
                        id: mini
                        anchors.fill: parent
                        anchors.margins: 10
                        anchors.bottomMargin: 30
                        clip: true
                        Repeater {
                            model: Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === wsCard.modelData.id)
                            delegate: Rectangle {
                                required property var modelData
                                readonly property var o: modelData.lastIpcObject || {}
                                readonly property var mon: tv.hyprMon
                                readonly property real sx: mon ? mini.width / mon.width : 0.05
                                readonly property real sy: mon ? mini.height / mon.height : 0.05
                                x: ((o.at ? o.at[0] : 0) - (mon ? mon.x : 0)) * sx
                                y: ((o.at ? o.at[1] : 0) - (mon ? mon.y : 0)) * sy
                                width: Math.max(10, (o.size ? o.size[0] : 200) * sx)
                                height: Math.max(8, (o.size ? o.size[1] : 150) * sy)
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.10)
                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: Math.min(parent.width, parent.height, 22) * 0.9
                                    visible: parent.width > 14 && parent.height > 12
                                    source: Global.iconFor(o.class || "", Global.entryFor(o.class || ""))
                                }
                            }
                        }
                    }
                    Text {
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: wsCard.isGame ? "Spiel" : "Desktop " + wsCard.modelData.id
                        color: wsCard.current ? Theme.text : Theme.textDim
                        font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: wsCard.current ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: tv.wsSel = wsCard.modelData.id
                        onDoubleClicked: { Global.hypr("hl.dsp.focus({ workspace = " + wsCard.modelData.id + " })"); Global.taskViewOpen = false; }
                    }
                    // Fenster hierher ziehen = auf diesen Desktop verschieben
                    DropArea {
                        id: drop
                        anchors.fill: parent
                        onDropped: dropEvent => {
                            const t = dropEvent.source ? dropEvent.source.toplevel : null;
                            if (t) { Global.moveToWorkspace(t, wsCard.modelData.id); }
                        }
                    }
                }
            }

            // Neuer Desktop
            Item {
                width: 90; height: 150
                Surface {
                    anchors.fill: parent
                    level: 0
                    radius: Theme.rM
                    opacity: addArea.containsMouse ? 1 : 0.7
                    Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
                }
                Icon { anchors.centerIn: parent; name: "add"; size: 26 }
                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { tv.wsSel = tv.nextFreeId; Global.hypr("hl.dsp.focus({ workspace = " + tv.nextFreeId + " })"); }
                }
            }
        }

        // ---------- Fenster des gewählten Desktops ----------
        Item {
            id: area
            anchors.top: wsRow.bottom
            anchors.topMargin: 34
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 110
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 90
            anchors.rightMargin: 90

            readonly property int n: Math.max(1, tv.windows.length)
            readonly property int cols: Math.ceil(Math.sqrt(n * (width / Math.max(1, height))))
            readonly property int rows: Math.ceil(n / cols)
            readonly property real cardW: Math.min(560, (width - (cols - 1) * 22) / cols)
            readonly property real cardH: Math.min(cardW * 0.66, (height - (rows - 1) * 22) / rows)

            Text {
                visible: tv.windows.length === 0
                anchors.centerIn: parent
                text: "Keine Fenster auf diesem Desktop"
                color: Theme.textDim
                font.family: Theme.font; font.pixelSize: Theme.fsL
            }

            Flow {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: area.cols * area.cardW + (area.cols - 1) * 22
                spacing: 22

                Repeater {
                    model: tv.windows
                    delegate: Item {
                        id: card
                        required property var modelData
                        readonly property var toplevel: modelData
                        readonly property var o: modelData.lastIpcObject || {}
                        readonly property string appClass: o.class || (modelData.wayland ? modelData.wayland.appId : "")
                        readonly property var entry: Global.entryFor(appClass)
                        readonly property bool minimized: Global.isMinimizedH(modelData)
                        width: area.cardW
                        height: area.cardH

                        Drag.active: dragArea.drag.active
                        Drag.source: card
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2

                        Item {
                            id: visual
                            width: card.width; height: card.height
                            scale: dragArea.drag.active ? 0.6 : (dragArea.containsMouse ? 1.025 : 1.0)
                            opacity: card.minimized ? 0.6 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }

                            Surface {
                                anchors.fill: parent
                                level: 2
                                radius: Theme.rM
                                border.color: dragArea.containsMouse ? Theme.accent : Theme.border
                                border.width: dragArea.containsMouse ? 2 : 1
                            }
                            Row {
                                id: cardHead
                                x: 12; y: 10
                                spacing: 8
                                IconImage { implicitSize: 18; source: Global.iconFor(card.appClass, card.entry); anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    width: card.width - 90
                                    text: card.modelData.title || (card.entry ? card.entry.name : card.appClass)
                                    elide: Text.ElideRight
                                    color: Theme.text
                                    font.family: Theme.font; font.pixelSize: Theme.fsS
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Item {
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: cardHead.bottom; anchors.bottom: parent.bottom
                                anchors.margins: 12; anchors.topMargin: 8
                                clip: true
                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: card.modelData.wayland
                                    live: tv.visible && !card.minimized
                                }
                                Text {
                                    visible: card.minimized
                                    anchors.centerIn: parent
                                    text: "minimiert"
                                    color: Theme.textDim
                                    font.family: Theme.font; font.pixelSize: Theme.fsM
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6
                                width: 26; height: 26; radius: 9
                                visible: dragArea.containsMouse
                                color: closeArea.containsMouse ? Qt.rgba(1, 0.42, 0.42, 0.35) : Qt.rgba(1, 1, 1, 0.10)
                                Icon { anchors.centerIn: parent; name: "close"; size: 13 }
                                MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: card.modelData.wayland && card.modelData.wayland.close() }
                            }
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            hoverEnabled: true
                            drag.target: visual
                            drag.threshold: 12
                            z: -1
                            onReleased: {
                                if (drag.active) { visual.x = 0; visual.y = 0; card.Drag.drop(); }
                            }
                            onClicked: {
                                Global.taskViewOpen = false;
                                Global.focusHypr(card.modelData);
                            }
                        }
                    }
                }
            }
        }
    }
}
