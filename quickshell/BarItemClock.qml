import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Uhr -> Kalender
BarButton {
    tip: "Datum und Kalender"
    property var bar: null
    implicitHeight: Global.barHeight - 10
    active: Global.calendarOpen && Global.popupScreen === bar.mon
    padding: 12
    SystemClock { id: clock; precision: Global.showSeconds ? SystemClock.Seconds : SystemClock.Minutes }
    Column {
        Text {
            anchors.right: parent.right
            text: Qt.formatDateTime(clock.date, Global.showSeconds ? "HH:mm:ss" : "HH:mm")
            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold
        }
        Text {
            visible: Global.showDate
            anchors.right: parent.right
            text: Qt.formatDateTime(clock.date, "dd.MM.yyyy")
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
        }
    }
    onClicked: Global.toggleCalendar(bar.mon)
}
