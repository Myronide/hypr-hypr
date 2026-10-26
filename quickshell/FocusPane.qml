import QtQuick

// Reiter „Fokus“ im Kalender: Pomodoro, Timer, Stoppuhr
Column {
    id: pane
    spacing: 12

    // Moduswahl
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4
        Repeater {
            model: [{ k: "pomodoro", t: "Pomodoro" }, { k: "timer", t: "Timer" }, { k: "stopwatch", t: "Stoppuhr" }]
            BarButton {
                required property var modelData
                implicitHeight: 28; padding: 12; radiusSize: 14
                active: Focus.mode === modelData.k
                opacity: Focus.started && Focus.runMode !== modelData.k ? 0.4 : 1
                Text { text: modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: active ? Font.DemiBold : Font.Normal }
                onClicked: Focus.setMode(modelData.k)
            }
        }
    }

    // Ring mit Zeit
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 150; height: 150
        Canvas {
            id: ring
            anchors.fill: parent
            property real p: Focus.progress
            property color col: Focus.runMode === "pomodoro" && Focus.phase !== "focus" ? Theme.green : Theme.accent
            onPChanged: requestPaint()
            onColChanged: requestPaint()
            onPaint: {
                const c = getContext("2d"); c.reset();
                const cx = width / 2, cy = height / 2, r = width / 2 - 8;
                c.lineWidth = 8; c.lineCap = "round";
                c.strokeStyle = "rgba(255,255,255,0.09)"; c.beginPath(); c.arc(cx, cy, r, 0, Math.PI * 2); c.stroke();
                if (p > 0.002) { c.strokeStyle = col; c.beginPath(); c.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, p)); c.stroke(); }
            }
            Behavior on p { NumberAnimation { duration: 260 } }
        }
        Column {
            anchors.centerIn: parent
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Focus.mode === "stopwatch" ? Focus.fmt(Focus.elapsed)
                    : Focus.started ? Focus.fmt(Focus.left)
                    : Focus.fmt((Focus.mode === "timer" ? Focus.timerMin : Focus.focusMin) * 60)
                color: Theme.text; font.family: Theme.font; font.pixelSize: 32; font.weight: Font.Light
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Focus.started ? Focus.phaseLabel + (Focus.runMode === "pomodoro" ? " · " + Focus.round + "/4" : "") : (Focus.mode === "pomodoro" ? "bereit" : (Focus.mode === "timer" ? "bereit" : "bereit"))
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
            }
        }
    }

    // Knöpfe
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        BarButton {
            implicitHeight: 38; padding: 22; radiusSize: 19
            color: hovered ? Theme.accentBright : Theme.accent
            Row { spacing: 8
                Icon { name: Focus.running ? "pause" : "play"; size: 15; anchors.verticalCenter: parent.verticalCenter }
                Text { text: Focus.running ? "Pause" : (Focus.started ? "Weiter" : "Start"); color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            }
            onClicked: Focus.toggle()
        }
        BarButton {
            visible: Focus.started
            implicitHeight: 38; padding: 18; radiusSize: 19
            color: hovered ? Theme.tileHover : Theme.tile
            Row { spacing: 8
                Icon { name: "stop"; size: 13; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Zurücksetzen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; anchors.verticalCenter: parent.verticalCenter }
            }
            onClicked: Focus.reset()
        }
    }

    // Timer-Voreinstellungen
    Row {
        visible: Focus.mode === "timer" && !Focus.started
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 5
        Repeater {
            model: [5, 10, 15, 25, 45]
            BarButton {
                required property int modelData
                implicitHeight: 28; padding: 10; radiusSize: 14
                active: Focus.timerMin === modelData
                Text { text: modelData + " Min"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                onClicked: Focus.setTimerMin(modelData)
            }
        }
    }
    // Pomodoro: Nicht-stören-Schalter
    Row {
        visible: Focus.mode === "pomodoro"
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        Rectangle {
            width: 38; height: 22; radius: 11; color: Focus.autoDnd ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
            Behavior on color { ColorAnimation { duration: 140 } }
            Rectangle { width: 16; height: 16; radius: 8; color: "white"; anchors.verticalCenter: parent.verticalCenter
                        x: Focus.autoDnd ? parent.width - width - 3 : 3; Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } }
            MouseArea { anchors.fill: parent; onClicked: Focus.autoDnd = !Focus.autoDnd }
        }
        Text { text: "Nicht stören in der Fokus-Phase"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
    }
}
