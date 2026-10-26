import QtQuick

// Prozessor und Arbeitsspeicher in zwei kleinen Anzeigen; Klick öffnet den Systemmonitor
BarButton {
    id: st
    property var bar: null
    tip: "Prozessor " + Math.round(Sys.cpu) + " %  ·  Speicher " + Sys.memUsedGb.toFixed(1) + " von " + Sys.memTotalGb.toFixed(1) + " GB"
         + (Sys.temp > 0 ? "  ·  " + Math.round(Sys.temp) + " °C" : "") + "\nKlick: Systemmonitor"
    implicitHeight: Global.barHeight - 10
    padding: 10
    Row {
        spacing: 12
        Repeater {
            model: [{ n: "CPU", v: Sys.cpu }, { n: "RAM", v: Sys.mem }]
            Column {
                required property var modelData
                spacing: 3
                anchors.verticalCenter: parent.verticalCenter
                Text { text: modelData.n + "  " + Math.round(modelData.v) + "%"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs; font.weight: Font.Medium }
                Rectangle {
                    width: 52; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.12)
                    Rectangle {
                        width: Math.max(4, parent.width * Math.min(1, modelData.v / 100)); height: 4; radius: 2
                        color: modelData.v > 90 ? Theme.red : (modelData.v > 70 ? Theme.amber : Theme.accent)
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Theme.easeOut } }
                    }
                }
            }
        }
    }
    onClicked: Global.run("gtk-launch dx-systemmonitor || python3 \"$HOME/.local/share/draconyx-apps/systemmonitor/sysmon.py\"")
}
