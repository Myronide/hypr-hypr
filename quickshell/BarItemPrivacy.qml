import QtQuick
import Quickshell.Services.Pipewire

// Datenschutz-Anzeige: erscheint nur, wenn ein Programm das Mikrofon benutzt oder den Bildschirm teilt
BarButton {
    id: pv
    property var bar: null
    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
    PwObjectTracker { objects: pv.nodes }
    function cls(n) { return n.properties ? (n.properties["media.class"] || "") : ""; }
    function appName(n) { const p = n.properties || {}; return p["application.name"] || p["node.name"] || n.nickname || n.name || "?"; }
    // Nur echte Programme zählen (Filter wie EasyEffects-Ketten oder Pegelanzeigen haben keinen Programmnamen)
    readonly property var ignore: ["easyeffects", "jamesdsp", "pavucontrol", "pulseaudio volume control", "peak detect", "cava", "quickshell"]
    function real(n) { const a = ((n.properties || {})["application.name"] || "").toLowerCase(); return a !== "" && ignore.indexOf(a) < 0; }
    readonly property var mics: nodes.filter(n => n.isStream && cls(n) === "Stream/Input/Audio" && n.audio && !n.audio.muted && real(n))
    readonly property var screens: nodes.filter(n => cls(n) === "Stream/Output/Video" && real(n))
    readonly property var names: {
        const out = [];
        for (const n of mics) { const t = "Mikrofon: " + appName(n); if (out.indexOf(t) < 0) out.push(t); }
        for (const n of screens) { const t = "Bildschirm: " + appName(n); if (out.indexOf(t) < 0) out.push(t); }
        return out;
    }
    visible: names.length > 0
    tip: names.join("\n")
    implicitHeight: Global.barHeight - 14
    padding: 8
    minWidth: 28
    Row {
        spacing: 6
        Rectangle { width: 8; height: 8; radius: 4; color: Theme.amber; anchors.verticalCenter: parent.verticalCenter
            SequentialAnimation on opacity { loops: Animation.Infinite; running: pv.visible; NumberAnimation { to: 0.45; duration: 900 } NumberAnimation { to: 1; duration: 900 } } }
        Icon { visible: pv.mics.length > 0; name: "mic"; size: 16; anchors.verticalCenter: parent.verticalCenter }
        Icon { visible: pv.screens.length > 0; name: "desktop"; size: 16; anchors.verticalCenter: parent.verticalCenter }
    }
}
