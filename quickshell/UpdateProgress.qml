import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Fortschrittsanzeige für das Draconyx-Update (oben rechts). dx-update schreibt den Stand nach ~/.cache/draconyx/update-progress.json:
// { "state": "running" | "done" | "error", "percent": 0-100, "text": "...", "ts": Unixzeit }
PanelWindow {
    id: win
    property var prog: ({})
    property string scrName: ""
    readonly property bool running: prog.state === "running"
    property bool shown: false
    visible: shown
    screen: Global.screenByName(scrName)
    anchors { top: true; right: true }
    margins { top: 16; right: 16 }
    implicitWidth: 360
    implicitHeight: card.implicitHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}                                   // reine Anzeige: Klicks gehen durch
    WlrLayershell.namespace: "draconyx-update"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    FileView {
        path: Theme.home + "/.cache/draconyx/update-progress.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let p = {};
            try { p = JSON.parse(text()); } catch (e) { return; }
            if (!p.state || (Date.now() / 1000 - (p.ts || 0)) > (p.state === "running" ? 900 : 20)) return;   // veraltet: ignorieren
            if (!win.shown) win.scrName = Global.focusedScreenName();
            win.prog = p;
            win.shown = true;
            hideTimer.stop();
            if (p.state !== "running") hideTimer.interval = p.state === "error" ? 14000 : 6000, hideTimer.restart();
        }
    }
    Timer { id: hideTimer; onTriggered: win.shown = false }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: col.implicitHeight + 28
        radius: Theme.rL
        color: Theme.panelStrong
        border.color: win.prog.state === "error" ? "#ff6b6b" : Theme.border
        Column {
            id: col
            x: 16; y: 14; width: parent.width - 32
            spacing: 8
            Row {
                spacing: 8
                Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter
                            color: win.prog.state === "error" ? "#ff6b6b" : win.prog.state === "done" ? "#6ee05c" : Theme.accentBright }
                Text {
                    text: win.prog.state === "error" ? "Update fehlgeschlagen" : win.prog.state === "done" ? "Draconyx ist aktuell" : "Draconyx wird aktualisiert"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold
                }
            }
            Text { width: parent.width; text: win.prog.text || ""; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS; elide: Text.ElideRight }
            Rectangle {
                width: parent.width; height: 8; radius: 4; color: Theme.tile
                Rectangle {
                    height: parent.height; radius: 4
                    width: parent.width * Math.max(0.02, Math.min(100, win.prog.percent || 0)) / 100
                    color: win.prog.state === "error" ? "#ff6b6b" : Theme.accent
                    Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                }
            }
            Text { text: Math.round(win.prog.percent || 0) + " %"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
        }
    }
}
