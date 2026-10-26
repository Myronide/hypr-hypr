import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Eigene Titelleisten für schwebende Fenster, die keine haben (z. B. Dolphin, Qt-Apps): eine schmale Leiste direkt über dem Fenster
// mit Titel, Minimieren, Maximieren und Schließen. Ziehen an der Leiste verschiebt das Fenster (ohne Alt/Strg-Taste), Doppelklick
// maximiert, Rechtsklick öffnet das Fenstermenü. Apps mit eigener Leiste stehen in ~/.config/hypr/csd-apps (Aurora → Fenster).
// Die Leiste wird nur gezeigt, wo über dem Fenster Platz ist und kein anderes, weiter oben liegendes Fenster darüber liegt.
Scope {
    id: tb
    readonly property int bh: 30
    readonly property bool enabled: Global.titleBars

    // ---------- Apps mit eigener Titelleiste ----------
    property var csd: ({})
    property var force: ({})       // Klassen, die immer eine Leiste bekommen (auch GTK-Apps): ~/.config/draconyx/titlebar-force
    function addList(text) {
        const m = Object.assign({}, csd);
        for (const l of text.split("\n")) { const k = l.trim().toLowerCase(); if (k !== "" && !k.startsWith("#")) m[k] = true; }
        csd = m;
    }
    FileView { path: Theme.home + "/.config/draconyx/titlebar-force"; watchChanges: true; onFileChanged: reload(); onLoaded: { const m = {}; for (const l of text().split("\n")) { const k = l.trim().toLowerCase(); if (k !== "" && !k.startsWith("#")) m[k] = true; } tb.force = m; } }
    FileView { path: Theme.home + "/.config/hypr/csd-apps"; watchChanges: true; onFileChanged: reload(); onLoaded: tb.addList(text()) }
    FileView { path: Theme.home + "/.config/hypr/aurora/csd-apps"; watchChanges: true; onFileChanged: reload(); onLoaded: tb.addList(text()) }

    // ---------- GTK-Apps zeichnen ihre Titelleiste selbst ----------
    // Wer libgtk geladen hat, bekommt keine zweite Leiste. Geprüft wird einmal je Prozess (cat /proc/PID/maps), das Ergebnis bleibt gemerkt.
    property var kind: ({})          // pid -> "gtk" | "other"
    property var asked: ({})
    property var queue: []
    function wantKind(pid) {
        if (pid === undefined || kind[pid] !== undefined || asked[pid]) return;
        asked[pid] = true; queue = queue.concat([pid]); probeTimer.restart();
    }
    Timer { id: probeTimer; interval: 60; onTriggered: { if (tb.queue.length > 0 && !probe.running) { probe.pids = tb.queue.join(" "); tb.queue = []; probe.running = true; } } }
    Process {
        id: probe
        property string pids: ""
        command: ["sh", "-c", "for p in $0; do if grep -qE 'libgtk-[34]|libadwaita' /proc/$p/maps 2>/dev/null; then echo \"$p gtk\"; else echo \"$p other\"; fi; done", pids]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = Object.assign({}, tb.kind);
                for (const l of text.split("\n")) { const p = l.trim().split(" "); if (p.length === 2) m[p[0]] = p[1]; }
                tb.kind = m;
                if (tb.queue.length > 0) probeTimer.restart();
                tb.recompute();
            }
        }
    }

    // ---------- Fensterliste ----------
    property var wins: []          // Fenster mit Leiste (Live-Daten)
    property var addrs: []         // nur die Adressen: ändert sich nur, wenn Fenster dazukommen/wegfallen (Leisten bleiben bestehen)
    property var byAddr: ({})
    property var lastPos: ({})      // Adresse -> "x,y,w,h" beim letzten Durchlauf
    property var movingUntil: ({})  // Adresse -> Zeitpunkt (ms), bis zu dem das Fenster als "in Bewegung" gilt
    function rectsOverlap(a, b) { return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h; }
    function recompute() {
        if (!enabled) { if (wins.length > 0) wins = []; return; }
        const mons = {};
        for (const m of Hyprland.monitors.values) {
            const o = m.lastIpcObject || {};
            mons[m.name] = { ws: m.activeWorkspace ? m.activeWorkspace.id : -999, top: (o.reserved || [0, 0, 0, 0])[1] || 0, y: o.y || 0 };
        }
        const all = [];
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject || {};
            if (!o.mapped || o.hidden || !o.at || !o.size || !o.workspace) continue;
            all.push({ addr: String(o.address), cls: o.class || "", title: o.title || "", x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1], floating: !!o.floating,
                       pid: o.pid, fs: o.fullscreen || 0, ws: o.workspace.id, wsName: o.workspace.name || "", mon: t.monitor ? t.monitor.name : "", focus: o.focusHistoryID === 0, fh: o.focusHistoryID === undefined ? 99 : o.focusHistoryID });
        }
        const now = Date.now();
        for (const w of all) {
            const k = w.x + "," + w.y + "," + w.w + "," + w.h;
            if (lastPos[w.addr] !== undefined && lastPos[w.addr] !== k) movingUntil[w.addr] = now + 260;
            lastPos[w.addr] = k;
        }
        const out = [];
        for (const w of all) {
            if ((movingUntil[w.addr] || 0) > now && Global.tbDrag !== w.addr) continue;
            if (!w.floating || w.fs !== 0 || w.ws < 1 || w.wsName === "minimized" || w.cls === "" || w.title === "") continue;
            if (tb.csd[w.cls.toLowerCase()] || w.cls.startsWith("steam_app_")) continue;
            if (tb.kind[w.pid] === undefined) { tb.wantKind(w.pid); continue; }          // noch nicht geprüft
            if (tb.kind[w.pid] === "gtk" && !tb.force[w.cls.toLowerCase()]) continue;     // zeichnet die Leiste selbst
            const mi = mons[w.mon]; if (!mi || mi.ws !== w.ws) continue;
            if (w.w < 120 || w.h < 80) continue;
            const bar = { x: w.x, y: w.y - bh, w: w.w, h: bh };
            if (bar.y < mi.y + mi.top) continue;                                  // kein Platz über dem Fenster
            let blocked = false;
            for (const o of all) if (o !== w && o.ws === w.ws && o.mon === w.mon && o.fs === 0 && o.fh < w.fh && rectsOverlap(bar, o)) { blocked = true; break; }   // nur Fenster, die weiter oben liegen (zuletzt benutzt), verdecken die Leiste
            if (blocked) continue;
            out.push(w);
        }
        out.sort((a, b) => a.addr < b.addr ? -1 : 1);
        const same = out.length === wins.length && out.every((w, i) => { const p = wins[i]; return p.addr === w.addr && p.x === w.x && p.y === w.y && p.w === w.w && p.h === w.h && p.title === w.title && p.focus === w.focus && p.mon === w.mon; });
        if (!same) {
            wins = out;
            const map = {}; for (const w of out) map[w.addr] = w;
            byAddr = map;
            const keys = out.map(w => w.addr);
            if (keys.length !== addrs.length || keys.some((k, i) => k !== addrs[i])) addrs = keys;
        }
    }
    Timer { interval: 110; repeat: true; running: tb.enabled; triggeredOnStart: true; onTriggered: { Hyprland.refreshToplevels(); Hyprland.refreshMonitors(); tb.recompute(); } }
    onEnabledChanged: recompute()

    // ---------- Eine Leiste je Fenster ----------
    Variants {
        model: tb.addrs

        PanelWindow {
            id: win
            required property string modelData
            property var frozen: null
            readonly property var live: tb.byAddr[modelData] || ({ addr: modelData, x: 0, y: 0, w: 100, h: 100, mon: "", title: "", cls: "", focus: false })
            readonly property var d: frozen || live
            readonly property var scr: Quickshell.screens.find(s => s.name === d.mon) || null
            screen: scr
            visible: scr !== null
            anchors.top: true
            anchors.left: true
            margins.left: scr ? d.x - scr.x : 0
            margins.top: scr ? d.y - tb.bh - scr.y : 0
            implicitWidth: d.w
            implicitHeight: tb.bh
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "draconyx-titlebar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property string addr: "0x" + String(modelData).replace(/^0x/, "")
            readonly property string sel: "window = \"address:" + addr + "\""
            readonly property bool active: d.focus

            Rectangle {
                anchors.fill: parent
                opacity: Global.tbDrag === win.addr ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 80 } }
                topLeftRadius: 12; topRightRadius: 12
                color: win.active ? Qt.rgba(Theme.bg2.r, Theme.bg2.g, Theme.bg2.b, 0.98) : Qt.rgba(Theme.bg1.r, Theme.bg1.g, Theme.bg1.b, 0.96)
                border.color: win.active ? Theme.border : Theme.borderSoft
                Behavior on color { ColorAnimation { duration: Theme.durFast } }

                // Ziehen / Doppelklick / Rechtsklick auf der ganzen Leiste (unter den Knöpfen)
                MouseArea {
                    id: drag
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    property bool going: false
                    property real gx: 0; property real gy: 0       // Zeigerposition beim Drücken (global)
                    property real wx: 0; property real wy: 0       // Fensterposition beim Drücken
                    property real lastSend: 0
                    onPressed: mouse => {
                        if (mouse.button !== Qt.LeftButton) return;
                        Global.hypr("hl.dsp.focus({ " + win.sel + " })");
                        going = false;
                        gx = win.d.x + mouse.x; gy = win.d.y - tb.bh + mouse.y;
                        wx = win.d.x; wy = win.d.y;
                        win.frozen = Object.assign({}, win.d);                 // die Leiste bleibt beim Ziehen stehen, sonst verschiebt sich der Bezugspunkt mit
                    }
                    onPositionChanged: mouse => {
                        if (!pressed || !(pressedButtons & Qt.LeftButton) || !win.frozen) return;
                        const cx = win.frozen.x + mouse.x, cy = win.frozen.y - tb.bh + mouse.y;       // Zeiger global
                        if (!going && Math.abs(cx - gx) + Math.abs(cy - gy) < 6) return;
                        if (!going) { going = true; Global.tbDrag = win.addr; }
                        const now = Date.now();
                        if (now - lastSend < 12) return;
                        lastSend = now;
                        Global.hypr("hl.dsp.window.move({ " + win.sel + ", x = " + Math.round(wx + cx - gx) + ", y = " + Math.round(wy + cy - gy) + ", relative = false })");
                    }
                    onReleased: { win.frozen = null; going = false; dragEnd.restart(); }
                    onCanceled: { win.frozen = null; going = false; dragEnd.restart(); }
                    onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) Global.hyprEval("DXSnap.toggleMaxAddr('" + win.addr + "')"); }
                    onClicked: mouse => { if (mouse.button === Qt.RightButton) { Global.closeAll(); Global.winMenu = { addr: win.addr, x: win.d.x, y: win.d.y }; } }
                }
                Timer { id: dragEnd; interval: 250; onTriggered: { if (Global.tbDrag === win.addr) Global.tbDrag = ""; } }

                Image {
                    id: ico
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16; sourceSize: Qt.size(32, 32)
                    source: Global.iconFor(win.d.cls, null)
                    opacity: win.active ? 1 : 0.6
                }
                Text {
                    anchors.left: ico.right; anchors.leftMargin: 9
                    anchors.right: btns.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.d.title
                    elide: Text.ElideRight
                    color: win.active ? Theme.text : Theme.textDim
                    font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: win.active ? Font.Medium : Font.Normal
                }
                Row {
                    id: btns
                    anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: [{ k: "min", i: "subtract" }, { k: "max", i: "window" }, { k: "close", i: "close" }]
                        Rectangle {
                            required property var modelData
                            width: 38; height: 24; radius: 8
                            color: bma.containsMouse ? (modelData.k === "close" ? Qt.rgba(1, 0.38, 0.38, 0.85) : Theme.tileHover) : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.durFast } }
                            Icon { anchors.centerIn: parent; name: modelData.i; size: modelData.k === "close" ? 12 : 13; opacity: win.active || bma.containsMouse ? 1 : 0.65 }
                            MouseArea {
                                id: bma
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    if (modelData.k === "min") Global.minimizeAddr(win.addr);
                                    else if (modelData.k === "max") Global.hyprEval("DXSnap.toggleMaxAddr('" + win.addr + "')");
                                    else Global.hypr("hl.dsp.window.close({ " + win.sel + " })");
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
