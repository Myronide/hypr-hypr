import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Kurze Anzeige am unteren Bildschirmrand, wenn Lautstärke oder Mikrofon geändert werden (Tasten, Regler, andere Programme).
PanelWindow {
    id: osd
    screen: Global.screenByName(Global.focusedScreenName())
    visible: shown || fade.running
    anchors.bottom: true
    margins.bottom: 110
    implicitWidth: 280
    implicitHeight: 62
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}                       // reine Anzeige: Mausklicks gehen durch
    WlrLayershell.namespace: "draconyx-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property bool shown: false
    property string icon: "vol"
    property string label: ""
    property real value: 0
    property bool ready: false            // Start der Shell nicht als Änderung zeigen

    function show(icon, label, value) {
        if (!ready || !Global.osdOn) return;
        osd.icon = icon; osd.label = label; osd.value = value;
        shown = true; hide.restart();
    }
    Timer { interval: 2500; running: true; onTriggered: osd.ready = true }
    Timer { id: hide; interval: 1400; onTriggered: osd.shown = false }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [osd.sink, osd.source] }

    Connections {
        target: osd.sink ? osd.sink.audio : null
        ignoreUnknownSignals: true
        function onVolumeChanged() { const a = osd.sink.audio; osd.show(a.muted ? "vol-mute" : (a.volume < 0.34 ? "vol-low" : "vol"), "Lautstärke", a.volume); }
        function onMutedChanged() { const a = osd.sink.audio; osd.show(a.muted ? "vol-mute" : "vol", a.muted ? "Stumm" : "Lautstärke", a.muted ? 0 : a.volume); }
    }
    Connections {
        target: osd.source ? osd.source.audio : null
        ignoreUnknownSignals: true
        function onMutedChanged() { const a = osd.source.audio; osd.show(a.muted ? "mic-off" : "mic", a.muted ? "Mikrofon aus" : "Mikrofon an", a.muted ? 0 : a.volume); }
    }
    Connections {
        target: Global
        function onOsdRequest(icon, label, value) { osd.show(icon, label, value); }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 31
        color: Theme.panelStrong
        border.color: Theme.border
        opacity: osd.shown ? 1 : 0
        scale: osd.shown ? 1 : 0.92
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.durBase; easing.type: Theme.easeOut } }
        Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }

        Icon { id: ic; name: osd.icon; size: 22; accent: osd.value > 0; anchors.left: parent.left; anchors.leftMargin: 20; anchors.verticalCenter: parent.verticalCenter }
        Column {
            anchors.left: ic.right; anchors.leftMargin: 14; anchors.right: pct.left; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7
            Text { text: osd.label; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
            Rectangle {
                width: parent.width; height: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.12)
                Rectangle {
                    width: Math.max(6, parent.width * Math.min(1, osd.value)); height: 6; radius: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.accentDeep }
                        GradientStop { position: 1; color: Theme.accent }
                    }
                    Behavior on width { NumberAnimation { duration: 90 } }
                }
            }
        }
        Text { id: pct; anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
               width: 38; horizontalAlignment: Text.AlignRight; text: Math.round(Math.min(1, osd.value) * 100) + "%"
               color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
    }
}
