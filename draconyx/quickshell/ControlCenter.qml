import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

// Schnelleinstellungen (wie Windows 11): Schalter, Lautstärke, Medien, Werkzeuge
PanelWindow {
    id: cc
    visible: Global.controlOpen
    screen: Global.screenByName(Global.popupScreen)

    anchors.bottom: !Global.barTop
    anchors.top: Global.barTop
    anchors.right: true
    margins.bottom: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.top: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.right: Global.popupRightMargin()
    implicitWidth: 420
    implicitHeight: content.implicitHeight + 36
    exclusionMode: ExclusionMode.Ignore      // Abstand zur Leiste kommt aus den Rändern; die Leisten-Reservierung nicht doppelt rechnen
    color: "transparent"
    WlrLayershell.namespace: "draconyx-control"
    WlrLayershell.layer: WlrLayer.Overlay

    HyprlandFocusGrab {
        windows: [cc]
        active: cc.visible
        onCleared: Global.controlOpen = false
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    // Besten Player wählen: spielend und mit Titel zuerst (Browser melden oft mehrere Player, einige ohne Metadaten)
    readonly property var player: {
        const list = Mpris.players.values;
        let best = null, bestScore = -1;
        for (const p of list) {
            const score = (p.isPlaying ? 4 : 0) + ((p.trackTitle || "") !== "" ? 2 : 0) + ((p.trackArtist || "") !== "" ? 1 : 0);
            if (score > bestScore) { best = p; bestScore = score; }
        }
        return best;
    }
    // Zuletzt gesehene Infos behalten: Browser nehmen den Player kurz nach dem Pausieren wieder weg
    property string lastTitle: ""
    property string lastArtist: ""
    property string lastArt: ""
    property string lastPlayerName: ""
    function remember() {
        const p = cc.player;
        if (!p) return;
        if ((p.trackTitle || "") !== "") { lastTitle = p.trackTitle; lastArtist = p.trackArtist || ""; lastArt = p.trackArtUrl || ""; lastPlayerName = p.identity || ""; }
    }
    onPlayerChanged: remember()
    Connections { target: cc.player; ignoreUnknownSignals: true
        function onTrackTitleChanged() { cc.remember(); }
        function onTrackArtistChanged() { cc.remember(); }
        function onTrackArtUrlChanged() { cc.remember(); }
        function onPlaybackStateChanged() { cc.remember(); } }
    Component.onCompleted: remember()
    readonly property string shownTitle: cc.player && (cc.player.trackTitle || "") !== "" ? cc.player.trackTitle : (lastTitle !== "" ? lastTitle : (cc.player ? cc.player.identity : ""))
    readonly property string shownArtist: cc.player && (cc.player.trackTitle || "") !== "" ? (cc.player.trackArtist || "") : lastArtist
    readonly property string shownArt: cc.player && (cc.player.trackArtUrl || "") !== "" ? cc.player.trackArtUrl : lastArt

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Theme.panelStrong
        border.color: Theme.border

        Column {
            id: content
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 18
            spacing: 16

            // ---------- Schalter ----------
            Grid {
                width: parent.width
                columns: 3
                spacing: 8
                readonly property real cellW: (width - 2 * spacing) / 3

                ToggleTile {
                    width: parent.cellW
                    iconName: "notif-dnd"; label: "Nicht stören"
                    checked: Global.dnd
                    onClicked: Global.run("swaync-client -d -sw")
                }
                ToggleTile {
                    width: parent.cellW
                    iconName: "night"; label: "Nachtlicht"
                    checked: Global.nightLight
                    onClicked: Global.setNightLight(!Global.nightLight)
                }
                ToggleTile {
                    width: parent.cellW
                    iconName: "game"; label: "Game-Modus"
                    checked: Global.gameMode
                    onClicked: Global.setGameMode(!Global.gameMode)
                }
                ToggleTile {
                    width: parent.cellW
                    iconName: "taskbar"; label: "Leiste ausblenden"
                    checked: Global.autohide
                    onClicked: Global.autohide = !Global.autohide
                }
                ToggleTile {
                    width: parent.cellW
                    iconName: "bt"; label: "Bluetooth"
                    onClicked: { Global.controlOpen = false; Global.run("blueman-manager"); }
                }
                ToggleTile {
                    width: parent.cellW
                    iconName: Global.netType === "ethernet" ? "ethernet" : (Global.netType === "wifi" ? "wifi" : "net-off")
                    label: Global.netType === "ethernet" ? "Ethernet" : (Global.netType === "wifi" ? "WLAN" : "Offline")
                    checked: Global.netType !== "none"
                    onClicked: { Global.controlOpen = false; Global.run("nm-connection-editor"); }
                }
            }

            // ---------- Regler ----------
            Column {
                width: parent.width
                spacing: 6

                SliderRow {
                    width: parent.width
                    iconName: cc.sink && cc.sink.audio && cc.sink.audio.muted ? "vol-mute" : "vol"
                    value: cc.sink && cc.sink.audio ? cc.sink.audio.volume : 0
                    onMoved: v => { if (cc.sink && cc.sink.audio) cc.sink.audio.volume = v; }
                    onIconClicked: { if (cc.sink && cc.sink.audio) cc.sink.audio.muted = !cc.sink.audio.muted; }
                }
                SliderRow {
                    width: parent.width
                    iconName: cc.source && cc.source.audio && cc.source.audio.muted ? "mic-off" : "mic"
                    value: cc.source && cc.source.audio ? cc.source.audio.volume : 0
                    onMoved: v => { if (cc.source && cc.source.audio) cc.source.audio.volume = v; }
                    onIconClicked: { if (cc.source && cc.source.audio) cc.source.audio.muted = !cc.source.audio.muted; }
                }
                Text {
                    text: cc.sink ? (cc.sink.description || cc.sink.nickname || cc.sink.name) : "Kein Audiogerät"
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11
                    leftPadding: 48; elide: Text.ElideRight; width: parent.width
                }
            }

            // ---------- Medien ----------
            Rectangle {
                visible: cc.player !== null || cc.lastTitle !== ""
                width: parent.width
                height: 96
                radius: 16
                color: Theme.tile
                border.color: Theme.borderSoft

                Rectangle {
                    id: artBox
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 72; height: 72; radius: 12
                    color: Theme.alpha(Theme.accent, 0.25)
                    clip: true
                    Icon { anchors.centerIn: parent; name: "music"; size: 28; visible: art.status !== Image.Ready }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: cc.shownArt
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                Column {
                    anchors.left: artBox.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: cc.shownTitle
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: cc.shownArtist
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: 12
                    }
                    Row {
                        spacing: 4
                        topPadding: 4
                        BarButton {
                            minWidth: 34; implicitHeight: 32
                            Icon { name: "prev"; size: 16 }
                            onClicked: if (cc.player) cc.player.previous()
                        }
                        BarButton {
                            minWidth: 40; implicitHeight: 32
                            color: hovered ? Theme.accentBright : Theme.accent
                            Icon { name: cc.player && cc.player.isPlaying ? "pause" : "play"; size: 16 }
                            onClicked: if (cc.player) cc.player.togglePlaying()
                        }
                        BarButton {
                            minWidth: 34; implicitHeight: 32
                            Icon { name: "next"; size: 16 }
                            onClicked: if (cc.player) cc.player.next()
                        }
                    }
                }
            }

            // ---------- Werkzeuge ----------
            Row {
                spacing: 6
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: [
                        { icon: "screenshot", tip: "Screenshot",      cmd: "sleep 0.3; hyprshot -m region --clipboard-only" },
                        { icon: "picker",     tip: "Farbpipette",     cmd: "sleep 0.3; hyprpicker -a" },
                        { icon: "clipboard",  tip: "Zwischenablage",  cmd: "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy" },
                        { icon: "desktop",    tip: "Monitore",        cmd: "nwg-displays" },
                        { icon: "settings",   tip: "Aussehen",        cmd: "nwg-look" },
                        { icon: "lock",       tip: "Sperren",         cmd: "hyprlock" }
                    ]
                    delegate: BarButton {
                        required property var modelData
                        minWidth: 56
                        implicitHeight: 48
                        color: hovered ? Theme.tileHover : Theme.tile
                        Icon { name: modelData.icon; size: 20 }
                        onClicked: { Global.controlOpen = false; Global.run(modelData.cmd); }
                    }
                }
            }
        }
    }
}
