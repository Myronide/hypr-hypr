import QtQuick

// Einheitliche Glas-Fläche für Leiste, Popups, Karten: Verlauf, feine Oberkante, Rand.
Rectangle {
    id: surface
    property int level: 1               // 0 = flach/leicht, 1 = Standard, 2 = Popup (dichter)
    property real opacityScale: 1.0     // z. B. aus den Einstellungen (Transparenz der Leiste)
    property bool outline: true
    property bool pop: false            // Öffnen-Animation (für Popups)
    Loader { active: surface.pop; sourceComponent: PopFx { card: surface } }

    radius: Theme.rL
    border.width: outline ? 1 : 0
    border.color: Theme.border
    gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(Theme.panelTop.r, Theme.panelTop.g, Theme.panelTop.b,
                                                    Math.min(1, Theme.panelTop.a * surface.opacityScale + (surface.level === 2 ? 0.05 : 0))) }
        GradientStop { position: 1.0; color: Qt.rgba(Theme.panelBottom.r, Theme.panelBottom.g, Theme.panelBottom.b,
                                                    Math.min(1, Theme.panelBottom.a * surface.opacityScale + (surface.level === 2 ? 0.04 : 0))) }
    }

    // feine Lichtkante oben (gibt Tiefe, ohne zu leuchten)
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - surface.radius * 1.4
        height: 1
        radius: 1
        visible: surface.outline
        color: Theme.highlight
    }
}
