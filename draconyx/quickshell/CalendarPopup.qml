import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Kalender beim Klick auf die Uhr
PanelWindow {
    id: cal
    visible: Global.calendarOpen
    screen: Global.screenByName(Global.popupScreen)

    anchors.bottom: !Global.barTop
    anchors.top: Global.barTop
    anchors.right: true
    margins.bottom: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.top: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.right: 14
    implicitWidth: 360
    implicitHeight: 420
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "draconyx-calendar"
    WlrLayershell.layer: WlrLayer.Overlay

    HyprlandFocusGrab {
        windows: [cal]
        active: cal.visible
        onCleared: Global.calendarOpen = false
    }

    property int monthOffset: 0
    onVisibleChanged: if (visible) monthOffset = 0

    readonly property date today: clock.date
    readonly property date shownMonth: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)
    readonly property var days: {
        const first = shownMonth;
        const startDow = (first.getDay() + 6) % 7;          // Montag = 0
        const start = new Date(first.getFullYear(), first.getMonth(), 1 - startDow);
        const out = [];
        for (let i = 0; i < 42; i++) out.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
        return out;
    }
    readonly property var deLocale: Qt.locale("de_DE")

    SystemClock { id: clock; precision: SystemClock.Seconds }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Theme.panelStrong
        border.color: Theme.border

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Column {
                spacing: 2
                Text {
                    text: Qt.formatDateTime(cal.today, "HH:mm:ss")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Light
                }
                Text {
                    text: cal.today.toLocaleDateString(cal.deLocale, "dddd, d. MMMM yyyy")
                    color: Theme.accentBright; font.family: Theme.font; font.pixelSize: 13
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.borderSoft }

            Item {
                width: parent.width
                height: 30
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: cal.shownMonth.toLocaleDateString(cal.deLocale, "MMMM yyyy")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    BarButton {
                        minWidth: 30; implicitHeight: 30
                        Icon { name: "chevron-left"; size: 14 }
                        onClicked: cal.monthOffset--
                    }
                    BarButton {
                        minWidth: 30; implicitHeight: 30
                        Icon { name: "chevron-right"; size: 14 }
                        onClicked: cal.monthOffset++
                    }
                }
            }

            Grid {
                columns: 7
                width: parent.width
                readonly property real cell: width / 7

                Repeater {
                    model: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
                    delegate: Text {
                        required property var modelData
                        width: parent.cell; height: 26
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                    }
                }
                Repeater {
                    model: cal.days
                    delegate: Item {
                        required property var modelData
                        readonly property bool inMonth: modelData.getMonth() === cal.shownMonth.getMonth()
                        readonly property bool isToday: modelData.toDateString() === cal.today.toDateString()
                        width: parent.cell; height: 38
                        Rectangle {
                            anchors.centerIn: parent
                            width: 34; height: 34; radius: 17
                            color: isToday ? Theme.accent : (dayArea.containsMouse ? Theme.tileHover : "transparent")
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.getDate()
                            color: isToday ? "#ffffff" : (inMonth ? Theme.text : Qt.rgba(1, 1, 1, 0.28))
                            font.family: Theme.font; font.pixelSize: 13
                            font.weight: isToday ? Font.DemiBold : Font.Normal
                        }
                        MouseArea { id: dayArea; anchors.fill: parent; hoverEnabled: true }
                    }
                }
            }
        }
    }
}
