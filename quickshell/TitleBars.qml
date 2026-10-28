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
    property int rounding: 12          // Eckenradius der Fenster (Aurora → Fenster)
    FileView {
        printErrors: false
        path: Theme.home + "/.config/hypr/aurora/preferences.json"; watchChanges: true; onFileChanged: reload()
        onLoaded: { try { const r = parseInt(JSON.parse(text()).rounding); if (r >= 0 && r <= 40) tb.rounding = r; } catch (e) {} }
    }

    // ---------- Apps mit eigener Titelleiste ----------
    property var csd: ({})
    property var force: ({})       // Klassen, die immer eine Leiste bekommen (auch GTK-Apps): ~/.config/draconyx/titlebar-force
    function addList(text) {
        const m = Object.assign({}, csd);
        for (const l of text.split("\n")) { const k = l.trim().toLowerCase(); if (k !== "" && !k.startsWith("#")) m[k] = true; }
        csd = m;
    }
    FileView { printErrors: false; path: Theme.home + "/.config/draconyx/titlebar-force"; watchChanges: true; onFileChanged: reload(); onLoaded: { const m = {}; for (const l of text().split("\n")) { const k = l.trim().toLowerCase(); if (k !== "" && !k.startsWith("#")) m[k] = true; } tb.force = m; } }
    FileView { printErrors: false; path: Theme.home + "/.config/hypr/csd-apps"; watchChanges: true; onFileChanged: reload(); onLoaded: tb.addList(text()) }
    FileView { printErrors: false; path: Theme.home + "/.config/hypr/aurora/csd-apps"; watchChanges: true; onFileChanged: reload(); onLoaded: tb.addList(text()) }

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
    function rectsOverlap(a, b) { return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h; }
    property var snap: ({ c: [], m: [] })          // letzter Stand von dx-window-watch
    function recompute() {
        if (!enabled) { if (wins.length > 0) wins = []; return; }
        const mons = {};
        for (const m of snap.m) mons[m.id] = { name: m.name, ws: m.ws, top: m.top || 0, y: m.y || 0 };
        const all = [];
        for (const o of snap.c) {
            if (!o.mapped || o.hidden || !o.at || !o.size || !o.workspace) continue;
            const mi = mons[o.monitor];
            all.push({ addr: String(o.address), cls: o.class || "", title: o.title || "", x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1], floating: !!o.floating,
                       pid: o.pid, fs: o.fullscreen || 0, ws: o.workspace.id, wsName: o.workspace.name || "", mon: mi ? mi.name : "", focus: o.focusHistoryID === 0,
                       fh: o.focusHistoryID === undefined ? 99 : o.focusHistoryID });
        }
        const monsByName = {};
        for (const id in mons) monsByName[mons[id].name] = mons[id];
        const out = [];
        for (const w of all) {
            if (!w.floating || w.fs !== 0 || w.ws < 1 || w.wsName === "minimized" || w.cls === "" || w.title === "") continue;
            if (tb.csd[w.cls.toLowerCase()] || w.cls.startsWith("steam_app_")) continue;
            if (tb.kind[w.pid] === undefined) { tb.wantKind(w.pid); continue; }          // noch nicht geprüft
            if (tb.kind[w.pid] === "gtk" && !tb.force[w.cls.toLowerCase()]) continue;     // zeichnet die Leiste selbst
            const mi = monsByName[w.mon]; if (!mi || mi.ws !== w.ws) continue;
            if (w.w < 120 || w.h < 80) continue;
            const bar = { x: w.x, y: w.y - bh, w: w.w, h: bh };
            const dragging = Global.tbDrag === w.addr;                            // wird gerade an der Leiste gezogen: Leiste darf nicht verschwinden (sonst geht das Loslassen der Maus verloren)
            if (!dragging && bar.y < mi.y + mi.top) continue;                      // kein Platz über dem Fenster
            let blocked = false;
            if (!dragging)
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
    // Fenster und Bildschirme in Echtzeit von Hyprland (dx-window-watch): so kleben die Leisten auch bei schnellen Bewegungen am Fenster
    Process {
        running: tb.enabled
        command: [Theme.home + "/.local/bin/dx-window-watch"]
        stdout: SplitParser {
            onRead: line => { try { tb.snap = JSON.parse(line); } catch (e) { return; } tb.recompute(); }
        }
    }
    onEnabledChanged: recompute()

    // ---------- Eine Leiste je Fenster ----------
    Variants {
        model: tb.addrs

        PanelWindow {
            id: win
            required property string modelData
            readonly property var live: tb.byAddr[modelData] || ({ addr: modelData, x: 0, y: 0, w: 100, h: 100, mon: "", title: "", cls: "", focus: false })
            readonly property var d: live
            readonly property var scr: dragScreen || Quickshell.screens.find(s => s.name === d.mon) || null     // beim Ziehen bleibt die Leiste auf ihrem Bildschirm (Fläche neu anlegen würde das Loslassen verschlucken)
            property var dragScreen: null
            property var dragPos: null
            screen: scr
            visible: scr !== null
            anchors.top: true
            anchors.left: true
            margins.left: scr ? (dragPos ? dragPos.x : d.x) - scr.x : 0
            margins.top: scr ? (dragPos ? dragPos.y : d.y) - tb.bh - scr.y : 0
            implicitWidth: d.w
            implicitHeight: tb.bh + tb.rounding
            mask: Region { item: barRect }                // nur die Leiste nimmt Mausereignisse an, nicht die Füllecken
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "draconyx-titlebar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property string addr: "0x" + String(modelData).replace(/^0x/, "")
            readonly property string sel: "window = \"address:" + addr + "\""
            readonly property bool active: d.focus

            // Füllecken: schließen die Lücke zwischen der Leiste und den abgerundeten oberen Fensterecken
            Canvas {
                visible: tb.rounding > 0
                x: 0; y: tb.bh; width: tb.rounding; height: tb.rounding
                property color c: win.active ? Theme.bg2 : Theme.bg1
                onCChanged: requestPaint()
                onPaint: { const g = getContext("2d"); g.reset(); const r = tb.rounding; g.fillStyle = c; g.beginPath(); g.moveTo(0, 0); g.lineTo(r, 0); g.arc(r, r, r, -Math.PI / 2, -Math.PI, true); g.closePath(); g.fill(); }
            }
            Canvas {
                visible: tb.rounding > 0
                x: parent.width - tb.rounding; y: tb.bh; width: tb.rounding; height: tb.rounding
                property color c: win.active ? Theme.bg2 : Theme.bg1
                onCChanged: requestPaint()
                onPaint: { const g = getContext("2d"); g.reset(); const r = tb.rounding; g.fillStyle = c; g.beginPath(); g.moveTo(r, 0); g.lineTo(0, 0); g.arc(0, r, r, -Math.PI / 2, 0, false); g.closePath(); g.fill(); }
            }
            Rectangle {
                id: barRect
                opacity: win.dragScreen && win.d.mon !== win.dragScreen.name ? 0 : 1      // Fenster ist auf einen anderen Bildschirm gezogen: Leiste solange unsichtbar
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: tb.bh
                topLeftRadius: tb.rounding; topRightRadius: tb.rounding
                color: win.active ? Qt.rgba(Theme.bg2.r, Theme.bg2.g, Theme.bg2.b, 0.98) : Qt.rgba(Theme.bg1.r, Theme.bg1.g, Theme.bg1.b, 0.96)
                border.color: win.active ? Theme.border : Theme.borderSoft
                Behavior on color { ColorAnimation { duration: Theme.durFast } }

                // Ziehen / Doppelklick / Rechtsklick auf der ganzen Leiste (unter den Knöpfen)
                MouseArea {
                    id: drag
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: mouse => {
                        if (mouse.button !== Qt.LeftButton) return;
                        Global.hypr("hl.dsp.focus({ " + win.sel + " })");
                        dragEnd.stop();
                        win.dragPos = null;
                        dragProc.startX = win.d.x + mouse.x;
                        dragProc.startY = win.d.y - tb.bh + mouse.y;
                        dragProc.startedAt = String(Date.now());
                        win.dragScreen = win.scr;
                        Global.tbDrag = win.addr;
                        dragProc.running = true;                    // der Helfer nimmt das Fenster mit dem Zeiger mit
                    }
                    onReleased: { dragProc.running = false; dragEnd.restart(); }
                    onCanceled: { dragProc.running = false; dragEnd.restart(); }
                    onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) Global.hyprEval("DXSnap.toggleMaxAddr('" + win.addr + "')"); }
                    onClicked: mouse => { if (mouse.button === Qt.RightButton) { Global.closeAll(); Global.winMenu = { addr: win.addr, x: win.d.x, y: win.d.y }; } }
                }
                Process {
                    id: dragProc
                    property real startX: 0
                    property real startY: 0
                    property string startedAt: "0"
                    command: [Theme.home + "/.local/bin/dx-window-drag", win.addr, String(startX), String(startY), startedAt]
                    stdout: SplitParser {
                        onRead: line => {
                            const p = line.trim().split(" ").map(Number);
                            if (dragProc.running && p.length === 2 && p.every(Number.isFinite))
                                win.dragPos = { x: p[0], y: p[1] };
                        }
                    }
                    onExited: { win.dragPos = null; dragEnd.restart(); }
                }
                Timer { id: dragEnd; interval: 250; onTriggered: { win.dragPos = null; win.dragScreen = null; if (Global.tbDrag === win.addr) Global.tbDrag = ""; tb.recompute(); } }

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
