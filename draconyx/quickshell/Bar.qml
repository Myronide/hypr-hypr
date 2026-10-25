import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire

// Taskbar 2.0: eine zusammenhängende Leiste pro Monitor.
// Links: Start, Suche, Task View, Desktops. Mitte: Apps. Rechts: Tray, System, Benachrichtigungen, Uhr.
// Auto-Hide: fährt ein, wenn sie nicht benutzt wird; die Maus am Rand holt sie zurück.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    readonly property string mon: modelData.name
    readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
    readonly property bool enabledHere: Global.monitorSetting(mon, "enabled", true)
    readonly property bool autohideHere: Global.monitorSetting(mon, "autohide", Global.autohide)
    // Vollbild (Spiele, Videos) auf diesem Monitor: Leiste ganz weg, auch kein Hover-Streifen
    readonly property bool fullscreenHere: hyprMonitor && hyprMonitor.activeWorkspace
                                           ? hyprMonitor.activeWorkspace.hasFullscreen : false
    readonly property bool keepOpen: !autohideHere || Global.popupOpenOn(mon) || hover.hovered
    property bool shown: true

    visible: enabledHere && !fullscreenHere
    anchors { left: true; right: true; top: Global.barTop; bottom: !Global.barTop }
    implicitHeight: Global.barHeight + Global.barMargin * 2 + 6
    color: "transparent"
    exclusiveZone: autohideHere ? 0 : Global.barHeight + Global.barMargin * 2
    WlrLayershell.namespace: "draconyx-bar"
    WlrLayershell.layer: WlrLayer.Top

    onKeepOpenChanged: {
        if (keepOpen) { hideTimer.stop(); shown = true; }
        else hideTimer.restart();
    }
    Component.onCompleted: if (!keepOpen) hideTimer.restart()
    Timer { id: hideTimer; interval: 900; onTriggered: if (!bar.keepOpen) bar.shown = false }

    // Eingabebereich: ganze Leiste, wenn sichtbar; sonst nur ein 3-px-Streifen am Rand
    mask: Region { item: inputArea }
    Item {
        id: inputArea
        width: parent.width
        height: bar.shown ? parent.height : 3
        y: Global.barTop ? 0 : parent.height - height
    }

    // ---------- Apps gruppieren: angeheftete zuerst (in Reihenfolge), danach laufende ----------
    readonly property var groups: {
        const out = [];
        const byKey = {};
        const pins = Global.pinned || [];
        for (let i = 0; i < pins.length; i++) {
            const g = { id: pins[i], pinned: true, pinIndex: i, windows: [] };
            out.push(g);
            byKey[Global.normId(pins[i])] = g;
        }
        for (const t of ToplevelManager.toplevels.values) {
            if (!t.appId) continue;
            const k = Global.normId(t.appId);
            let g = byKey[k];
            if (!g) {
                g = { id: t.appId, pinned: false, pinIndex: -1, windows: [] };
                out.push(g);
                byKey[k] = g;
            }
            if (!Global.groupApps && g.windows.length > 0) {
                // ohne Gruppierung: jedes weitere Fenster bekommt einen eigenen Knopf
                out.push({ id: t.appId, pinned: false, pinIndex: -1, windows: [t] });
            } else {
                g.windows.push(t);
            }
        }
        return out;
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    Item {
        anchors.fill: parent
        HoverHandler { id: hover }

        Surface {
            id: surf
            level: 1
            opacityScale: Global.barOpacity / 0.90
            radius: Theme.rL
            x: Global.barMargin
            width: parent.width - 2 * Global.barMargin
            height: Global.barHeight

            readonly property real shownY: Global.barTop ? Global.barMargin : parent.height - height - Global.barMargin
            readonly property real hiddenY: Global.barTop ? -height - 12 : parent.height + 12
            y: bar.shown ? shownY : hiddenY
            opacity: bar.shown ? 1 : 0
            Behavior on y       { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeOut } }
            Behavior on opacity { NumberAnimation { duration: Theme.durBase } }

            // ================= LINKS =================
            Row {
                id: leftRow
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                BarButton {
                    anchors.verticalCenter: parent.verticalCenter
                    minWidth: 44
                    implicitHeight: Global.barHeight - 10
                    active: Global.startOpen && Global.popupScreen === bar.mon
                    Image {
                        source: Theme.logo
                        width: 34; height: 34
                        sourceSize: Qt.size(68, 68)
                        smooth: true; mipmap: true
                    }
                    onClicked: Global.toggleStart(bar.mon)
                }
                BarButton {
                    anchors.verticalCenter: parent.verticalCenter
                    minWidth: 40
                    implicitHeight: Global.barHeight - 10
                    Icon { name: "search"; size: 19 }
                    onClicked: Global.toggleStart(bar.mon)
                }
                BarButton {
                    anchors.verticalCenter: parent.verticalCenter
                    minWidth: 40
                    implicitHeight: Global.barHeight - 10
                    active: Global.taskViewOpen && Global.popupScreen === bar.mon
                    Icon { name: "apps"; size: 19 }
                    onClicked: Global.toggleTaskView(bar.mon)
                }
                BarButton {
                    anchors.verticalCenter: parent.verticalCenter
                    minWidth: 40
                    implicitHeight: Global.barHeight - 10
                    active: Global.codeOpen && Global.popupScreen === bar.mon
                    Icon { name: "code"; size: 19; accent: Global.codeOpen && Global.popupScreen === bar.mon }
                    onClicked: Global.toggleCode(bar.mon)
                }

                BarButton {
                    anchors.verticalCenter: parent.verticalCenter
                    minWidth: 40
                    implicitHeight: Global.barHeight - 10
                    active: Global.weOpen && Global.popupScreen === bar.mon
                    Icon { name: "desktop"; size: 19; accent: Global.weOpen && Global.popupScreen === bar.mon }
                    onClicked: Global.toggleWe(bar.mon)
                }

                // Desktops: kompakte Leiste (aktiv = lang und violett)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 8
                    spacing: 4
                    Repeater {
                        model: Hyprland.workspaces.values
                            .filter(w => w.id > 0 && w.monitor && bar.hyprMonitor && w.monitor.name === bar.hyprMonitor.name)
                            .sort((a, b) => a.id - b.id)
                        delegate: Item {
                            id: ws
                            required property var modelData
                            readonly property bool current: bar.hyprMonitor && bar.hyprMonitor.activeWorkspace
                                                            && bar.hyprMonitor.activeWorkspace.id === modelData.id
                            readonly property bool isGame: modelData.name === "Spiel" || modelData.id === 10
                            readonly property bool isCode: modelData.id === 8
                            width: (isGame || isCode) ? 22 : (current ? 24 : 12)
                            height: 24
                            anchors.verticalCenter: parent.verticalCenter
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
            }

            // ================= MITTE: Apps =================
            Row {
                id: appsRow
                anchors.verticalCenter: parent.verticalCenter
                x: Global.barCenter ? (parent.width - width) / 2 : leftRow.x + leftRow.width + 16
                spacing: 2
                Behavior on x { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }

                Repeater {
                    model: bar.groups
                    delegate: TaskButton {
                        required property var modelData
                        group: modelData
                        mon: bar.mon
                        slot: width + appsRow.spacing
                        implicitHeight: Global.barHeight - 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // ================= RECHTS =================
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Repeater {
                    model: SystemTray.items.values
                    delegate: BarButton {
                        id: trayBtn
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        minWidth: 32
                        padding: 7
                        implicitHeight: Global.barHeight - 14
                        IconImage { implicitSize: 18; source: trayBtn.modelData.icon }
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton && !modelData.onlyMenu) {
                                modelData.activate();
                            } else if (modelData.hasMenu) {
                                const p = trayBtn.mapToItem(null, 0, 0);
                                modelData.display(bar, p.x, p.y);
                            } else {
                                modelData.secondaryActivate();
                            }
                        }
                        onScrolled: wheel => modelData.scroll(wheel.angleDelta.y, false)
                    }
                }

                Rectangle { width: 1; height: 22; color: Theme.borderSoft; anchors.verticalCenter: parent.verticalCenter }

                // Netzwerk + Lautstärke -> Schnelleinstellungen
                BarButton {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: Global.barHeight - 10
                    active: Global.controlOpen && Global.popupScreen === bar.mon
                    Row {
                        spacing: 10
                        Icon { name: Global.netType === "ethernet" ? "ethernet" : (Global.netType === "wifi" ? "wifi" : "net-off"); size: 18 }
                        Icon { name: bar.muted ? "vol-mute" : (bar.volume < 0.35 ? "vol-low" : "vol"); size: 18 }
                    }
                    onClicked: Global.toggleControl(bar.mon)
                    onScrolled: wheel => {
                        if (!bar.sink || !bar.sink.audio) return;
                        const v = bar.sink.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05);
                        bar.sink.audio.volume = Math.max(0, Math.min(1, v));
                    }
                }

                // Benachrichtigungen mit Zähler
                BarButton {
                    id: notifBtn
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: Global.barHeight - 10
                    Icon { name: Global.dnd ? "notif-dnd" : (Global.notifCount > 0 ? "notif-new" : "notif"); size: 18 }
                    Rectangle {
                        parent: notifBtn
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 2
                        visible: Global.notifCount > 0 && !Global.dnd
                        width: Math.max(16, badgeText.implicitWidth + 8); height: 16; radius: 8
                        color: Theme.accent
                        border.color: Theme.bg1; border.width: 2
                        Text { id: badgeText; anchors.centerIn: parent; text: Global.notifCount; color: Theme.textOn; font.pixelSize: 9; font.family: Theme.font; font.bold: true }
                    }
                    onClicked: mouse => Global.run(mouse.button === Qt.RightButton ? "swaync-client -d -sw" : "swaync-client -t -sw")
                }

                // Uhr -> Kalender
                BarButton {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: Global.barHeight - 10
                    active: Global.calendarOpen && Global.popupScreen === bar.mon
                    padding: 12
                    Column {
                        Text {
                            anchors.right: parent.right
                            text: Qt.formatDateTime(clock.date, Global.showSeconds ? "HH:mm:ss" : "HH:mm")
                            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right
                            text: Qt.formatDateTime(clock.date, "dd.MM.yyyy")
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
                        }
                    }
                    onClicked: Global.toggleCalendar(bar.mon)
                }

                // Schmaler Streifen ganz rechts: Desktop anzeigen
                BarButton {
                    anchors.verticalCenter: parent.verticalCenter
                    minWidth: 12; padding: 0
                    implicitHeight: Global.barHeight - 14
                    Rectangle { width: 2; height: 18; radius: 1; color: Theme.borderSoft }
                    onClicked: {
                        const ws = bar.hyprMonitor ? bar.hyprMonitor.activeWorkspace : null;
                        if (ws && ws.toplevels && ws.toplevels.values.length > 0) {
                            Global.lastWorkspace = ws.id;
                            Global.hypr("hl.dsp.focus({ workspace = \"empty\" })");
                        } else {
                            Global.hypr("hl.dsp.focus({ workspace = " + Global.lastWorkspace + " })");
                        }
                    }
                }
            }
        }
    }

    SystemClock { id: clock; precision: Global.showSeconds ? SystemClock.Seconds : SystemClock.Minutes }
}
