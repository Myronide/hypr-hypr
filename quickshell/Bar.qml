import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire

// Taskbar 2.0: eine zusammenhängende Leiste pro Monitor.
// Links: Start, Suche, Task View, Desktops. Mitte: Apps. Rechts: Tray, System, Benachrichtigungen, Uhr.
// Auto-Hide: fährt ein, wenn sie nicht benutzt wird; die Maus am Rand holt sie zurück.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    readonly property string mon: modelData.name
    readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
    readonly property bool enabledHere: Global.monitorSetting(mon, "enabled", true)
    readonly property bool autohideSetting: Global.monitorSetting(mon, "autohide", Global.autohide)
    // Vollbild (Spiele, Videos) auf diesem Monitor: Leiste ganz weg, auch kein Hover-Streifen
    readonly property bool fullscreenHere: hyprMonitor && hyprMonitor.activeWorkspace
                                           ? hyprMonitor.activeWorkspace.hasFullscreen : false
    // Bei Vollbild-Fenstern verhält sich auch eine feste Leiste wie eine Auto-Hide-Leiste (am Rand einblendbar) – einstellbar
    readonly property bool fsActive: fullscreenHere && Global.fullscreenBar !== "show"
    readonly property bool autohideHere: autohideSetting || fsActive
    readonly property bool keepOpen: !autohideHere || Global.popupOpenOn(mon) || hover.hovered
    property bool shown: true
    // Dock + Auto-Hide + "Teile einzeln": jede Insel fährt nur hoch, wenn die Maus bei ihr ist (siehe BarIsland)
    readonly property bool partMode: dock && autohideHere && Global.barPartHide
    property Item startItem: null                       // Startknopf (Anker für das Symbol-Menü)
    function logoMenuToggle() { logoMenu.visible = !logoMenu.visible; }
    readonly property bool dock: Global.barStyle === "dock"
    readonly property int gap: Global.barMargin        // Abstand zum Bildschirmrand

    visible: enabledHere && !(fullscreenHere && Global.fullscreenBar === "hide")
    anchors { left: true; right: true; top: Global.barTop; bottom: !Global.barTop }
    implicitHeight: Global.barHeight + gap * 2 + 6
    color: "transparent"
    exclusiveZone: autohideHere ? 0 : Global.barHeight + gap * 2
    WlrLayershell.namespace: "draconyx-bar"
    // Vollbild-Fenster liegen über der Top-Ebene: soll die Leiste bleiben, rückt sie in die Overlay-Ebene
    WlrLayershell.layer: fullscreenHere && Global.fullscreenBar !== "hide" ? WlrLayer.Overlay : WlrLayer.Top

    onKeepOpenChanged: {
        if (keepOpen) { hideTimer.stop(); shown = true; }
        else hideTimer.restart();
    }
    Component.onCompleted: if (!keepOpen) hideTimer.restart()
    Timer { id: hideTimer; interval: 900; onTriggered: if (!bar.keepOpen) bar.shown = false }

    // Eingabebereich: ganze Leiste, wenn sichtbar; sonst nur ein 3-px-Streifen am Rand
    // Dock: nur die beiden Kapseln fangen Klicks, der Rest der Zeile bleibt durchlässig
    mask: dock ? (Global.barRevealAnywhere && autohideHere ? dockMaskAny : dockMask) : fullMask
    Region { id: fullMask; item: inputArea }
    Region { id: dockMask; item: islL.zone; Region { item: islC.zone; Region { item: islR.zone } } }
    // "Überall öffnen": zusätzlich ein Streifen am Rand über die ganze Breite (Maus irgendwo dort öffnet die schwebende Leiste)
    Region { id: dockMaskAny; item: islL.zone; Region { item: islC.zone; Region { item: islR.zone; Region { item: edgeStrip } } } }
    Item {
        id: edgeStrip
        width: parent.width
        height: bar.shown ? 14 : 3
        y: Global.barTop ? 0 : parent.height - height
    }
    Item {
        id: inputArea
        width: parent.width
        height: bar.shown ? parent.height : 3
        y: Global.barTop ? 0 : parent.height - height
    }

    // ---------- Apps gruppieren: angeheftete zuerst (in Reihenfolge), danach laufende ----------
    readonly property var groups: {
        const out = [];
        const byKey = {};
        const pins = Global.pinned || [];
        for (let i = 0; i < pins.length; i++) {
            const g = { id: pins[i], pinned: true, pinIndex: i, windows: [] };
            out.push(g);
            byKey[Global.normId(pins[i])] = g;
        }
        for (const t of ToplevelManager.toplevels.values) {
            if (!t.appId) continue;
            const k = Global.normId(t.appId);
            let g = byKey[k];
            if (!g) {
                g = { id: t.appId, pinned: false, pinIndex: -1, windows: [] };
                out.push(g);
                byKey[k] = g;
            }
            if (!Global.groupApps && g.windows.length > 0) {
                // ohne Gruppierung: jedes weitere Fenster bekommt einen eigenen Knopf
                out.push({ id: t.appId, pinned: false, pinIndex: -1, windows: [t] });
            } else {
                g.windows.push(t);
            }
        }
        return out;
    }


    // Lage der Kapseln an die Menüs melden (Dock-Stil)
    // linke Kante der ersten und rechte Kante der letzten belegten Insel (Menüs richten sich daran aus)
    readonly property var dockGeom: {
        const isl = [islL, islC, islR].filter(i => i.occupied);
        if (isl.length === 0) return { x: Global.barMargin, w: 0, sx: bar.width - Global.barMargin, sw: 0, screenW: bar.width };
        const first = isl[0].panel, last = isl[isl.length - 1].panel;
        return { x: first.x, w: first.width, sx: last.x, sw: last.width, screenW: bar.width };
    }
    onDockGeomChanged: Global.setDockGeom(mon, dockGeom)

    // Rechtsklick auf den Startknopf: Symbol wählen (Hypr Hypr / Arch / eigenes Bild)
    PopupWindow {
        id: logoMenu
        anchor.item: bar.startItem ? bar.startItem : null
        anchor.edges: Global.barTop ? Edges.Bottom : Edges.Top
        anchor.gravity: Global.barTop ? Edges.Bottom : Edges.Top
        anchor.margins.top: Global.barTop ? 8 : 0
        anchor.margins.bottom: Global.barTop ? 0 : 8
        implicitWidth: 240
        implicitHeight: logoCol.implicitHeight + 16
        color: "transparent"
        visible: false
        HyprlandFocusGrab { windows: [logoMenu]; active: logoMenu.visible; onCleared: if (!Global.snipBusy) logoMenu.visible = false }
        Surface {
            anchors.fill: parent
            level: 2
            radius: Theme.rM
            Column {
                id: logoCol
                anchors.fill: parent; anchors.margins: 8; spacing: 2
                Text { text: "Symbol des Startknopfs"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs; leftPadding: 6; bottomPadding: 4 }
                MenuRow { width: logoCol.width; label: "Hypr Hypr-Logo" + (Global.startLogo === "" ? "  ✓" : ""); iconName: "apps"
                          onTriggered: { Global.startLogo = ""; logoMenu.visible = false; } }
                MenuRow { width: logoCol.width; label: "Arch-Logo" + (Global.startLogo === "arch" ? "  ✓" : ""); iconName: "apps"
                          onTriggered: { Global.startLogo = "arch"; logoMenu.visible = false; } }
                MenuRow { width: logoCol.width; label: "Eigenes Bild wählen …" + (Global.startLogo !== "" && Global.startLogo !== "arch" ? "  ✓" : ""); iconName: "folder-open"
                          onTriggered: { logoMenu.visible = false; Global.pickStartLogo(); } }
            }
        }
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    Item {
        anchors.fill: parent
        HoverHandler { id: hover }

        // Leistenstil: eine Fläche über die ganze Breite (links / mitte / rechts)
        BarIsland { id: islF; anchors.fill: parent; bar: bar; align: "full"; sections: bar.dock ? [] : ["left", "center", "right"] }
        // Dock-Stil: drei Inseln, jede nur sichtbar, wenn sie Teile enthält
        BarIsland { id: islL; anchors.fill: parent; bar: bar; align: "left";   sections: bar.dock ? ["left"] : [] }
        BarIsland { id: islC; anchors.fill: parent; bar: bar; align: "center"; sections: bar.dock ? ["center"] : [] }
        BarIsland { id: islR; anchors.fill: parent; bar: bar; align: "right";  sections: bar.dock ? ["right"] : [] }
    }
}
