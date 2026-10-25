import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Draconyx Desktop: Wallpaper auf jedem Monitor, Icons nur auf den gewählten Monitoren.
// Nimmt nie Tastaturfokus (Tippen im Browser landet nie auf dem Desktop).
PanelWindow {
    id: desk
    required property var modelData
    screen: modelData

    readonly property string mon: modelData.name
    readonly property bool showIcons: (Global.desktopMonitors || []).length > 0 ? (Global.desktopMonitors || []).indexOf(mon) >= 0 : (Quickshell.screens.length > 0 && Quickshell.screens[0].name === mon)
    readonly property string wallpaperPath: (Global.wallpapers || {})[mon] || Global.wallpaper
    property var selection: ({})           // Pfad -> true (Mehrfachauswahl)
    property var baseSelection: ({})       // Auswahl beim Start des Ziehrahmens (für Strg)
    property var marquee: null             // { x, y, w, h } Ziehrahmen
    readonly property int selCount: Object.keys(selection).length
    function isSelected(p) { return selection[p] === true; }
    function clearSel() { selection = ({}); }
    function setSel(paths) { const o = {}; for (const p of paths) o[p] = true; selection = o; }
    function toggleSel(p) { const o = Object.assign({}, selection); if (o[p]) delete o[p]; else o[p] = true; selection = o; }
    function selectedPaths() { return Object.keys(selection); }
    function selectRect(r, additive) {
        const o = additive ? Object.assign({}, baseSelection) : {};
        for (let i = 0; i < iconRep.count; i++) {
            const it = iconRep.itemAt(i);
            if (!it || !it.visible) continue;
            const p = it.mapToItem(bgArea, 0, 0);
            if (p.x < r.x + r.w && p.x + it.width > r.x && p.y < r.y + r.h && p.y + it.height > r.y)
                o[folder.get(i, "filePath")] = true;
        }
        selection = o;
    }
    property var menu: null           // { x, y, kind: "item"|"empty", path, name, isDir, suffix }

    visible: !Global.weRemap
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    // Läuft die Wallpaper Engine auf diesem Monitor, reichen wir die Maus an sie durch (Monitore ohne Symbole immer;
    // mit Symbolen nur, wenn "Maus fürs Wallpaper" an ist – dann sind die Symbole dort nicht klickbar)
    readonly property bool mouseToWallpaper: !!(Global.weWallpapers || {})[mon] && (!showIcons || (Global.weMouse || []).indexOf(mon) >= 0)
    mask: mouseToWallpaper ? passAll : null
    Region { id: passAll }
    color: "transparent"
    WlrLayershell.namespace: "draconyx-desktop"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ---------- Wallpaper ----------
    Rectangle { anchors.fill: parent; color: Theme.bg0; visible: !(Global.weWallpapers || {})[desk.mon] }
    Image {
        visible: !(Global.weWallpapers || {})[desk.mon]
        anchors.fill: parent
        source: "file://" + desk.wallpaperPath
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: Qt.size(desk.width, desk.height)
        smooth: true
    }

    // ---------- Hintergrund: Ziehrahmen zum Auswählen, Klick leert, Rechtsklick = Menü ----------
    MouseArea {
        id: bgArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point start: Qt.point(0, 0)
        property bool dragging: false

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton) return;
            start = Qt.point(mouse.x, mouse.y);
            dragging = false;
            desk.menu = null;
            const additive = (mouse.modifiers & Qt.ControlModifier) !== 0;
            desk.baseSelection = additive ? Object.assign({}, desk.selection) : ({});
            if (!additive) desk.clearSel();
        }
        onPositionChanged: mouse => {
            if (!(pressedButtons & Qt.LeftButton) || !desk.showIcons) return;
            if (!dragging && (Math.abs(mouse.x - start.x) > 6 || Math.abs(mouse.y - start.y) > 6)) dragging = true;
            if (!dragging) return;
            const r = { x: Math.min(start.x, mouse.x), y: Math.min(start.y, mouse.y),
                        w: Math.abs(mouse.x - start.x), h: Math.abs(mouse.y - start.y) };
            desk.marquee = r;
            desk.selectRect(r, (mouse.modifiers & Qt.ControlModifier) !== 0);
        }
        onReleased: { dragging = false; desk.marquee = null; }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton && desk.showIcons) {
                desk.clearSel();
                desk.menu = { x: mouse.x, y: mouse.y, kind: "empty" };
            } else desk.menu = null;
        }
    }

    // Auswahlrahmen
    Rectangle {
        visible: desk.marquee !== null
        x: desk.marquee ? desk.marquee.x : 0
        y: desk.marquee ? desk.marquee.y : 0
        width: desk.marquee ? desk.marquee.w : 0
        height: desk.marquee ? desk.marquee.h : 0
        color: Theme.accentSoft
        border.color: Theme.accent
        border.width: 1
        radius: 4
        z: 4
    }

    Connections {
        target: Global
        function onTestSelectChanged() {
            if (desk.showIcons && Global.testSelect) { desk.marquee = Global.testSelect; desk.selectRect(Global.testSelect, false); }
            else desk.marquee = null;
        }
    }

    // ---------- Icons ----------
    FolderListModel {
        id: folder
        folder: "file://" + Theme.home + "/Schreibtisch"
        showDirs: true
        showDotAndDotDot: false
        showHidden: false
        showDirsFirst: true
        sortField: FolderListModel.Name
    }

    function iconNameFor(name, isDir, suffix) {
        const s = (suffix || "").toLowerCase();
        if (isDir) return "folder";
        if (["zip", "7z", "rar", "tar", "gz", "xz", "bz2", "zst", "jar"].indexOf(s) >= 0) return "package-x-generic";
        if (["deb", "rpm"].indexOf(s) >= 0) return "application-x-deb";
        if (s === "pdf") return "application-pdf";
        if (["html", "htm"].indexOf(s) >= 0) return "text-html";
        if (["sh", "bash", "fish"].indexOf(s) >= 0) return "text-x-script";
        if (["appimage", "run", "x86_64"].indexOf(s) >= 0) return "application-x-executable";
        if (["exe", "msi", "lnk"].indexOf(s) >= 0) return "wine";
        if (["mp3", "wav", "ogg", "flac"].indexOf(s) >= 0) return "audio-x-generic";
        if (["mp4", "mkv", "webm", "avi", "mov"].indexOf(s) >= 0) return "video-x-generic";
        return "text-x-generic";
    }
    function isImage(suffix) { return ["png", "jpg", "jpeg", "webp", "gif", "bmp"].indexOf((suffix || "").toLowerCase()) >= 0; }

    function openItem(path, name, isDir, suffix) {
        Global.logLaunch("desktop-doppelklick", path);
        const s = (suffix || "").toLowerCase();
        if (isDir) { Quickshell.execDetached(["dolphin", path]); return; }
        if (s === "desktop") {
            const e = Global.entryFor(name.replace(/\.desktop$/, ""));
            if (e) Global.launch(e.id, e); else Quickshell.execDetached(["gio", "launch", path]);
            return;
        }
        if (s === "appimage") { Quickshell.execDetached(["sh", "-c", "chmod +x \"$0\" 2>/dev/null; exec \"$0\"", path]); return; }
        Quickshell.execDetached(["xdg-open", path]);
    }

    // Plätze der Symbole kommen aus Global.iconPos; neue Dateien bekommen automatisch einen freien Platz
    Timer {
        id: placeTimer
        interval: 350
        onTriggered: {
            if (!desk.showIcons || desk.mon !== ((Global.desktopMonitors || [])[0] || desk.mon)) return;
            const names = [];
            for (let i = 0; i < folder.count; i++) names.push(folder.get(i, "fileName"));
            Global.iconAutoPlace(names);
        }
    }
    Connections { target: folder; function onCountChanged() { placeTimer.restart(); } }
    Connections { target: Global; function onDesktopMonitorsChanged() { placeTimer.restart(); } }
    Component.onCompleted: placeTimer.restart()

    // Ziehen: Symbole (alle markierten) auf freie Plätze setzen, auch auf andere Monitore
    property bool dragActive: false
    property point dragPoint: Qt.point(0, 0)
    property string dragLabel: ""
    function dropIcons(anchorName, grabX, grabY, localX, localY) {
        // Oberer linker Punkt des gezogenen Symbols in globalen Koordinaten
        const gx = desk.screen.x + localX - grabX, gy = desk.screen.y + localY - grabY;
        const gcx = desk.screen.x + localX, gcy = desk.screen.y + localY;
        let target = null;
        for (const s of Quickshell.screens)
            if (gcx >= s.x && gcx < s.x + s.width && gcy >= s.y && gcy < s.y + s.height) target = s;
        if (!target) return;
        const topM = Global.barTop ? Global.barHeight + Global.barMargin * 2 + 18 : 18;
        const cw = Global.iconGrid, ch = Global.iconGrid + 14;
        const c = Math.round((gx - target.x - 18) / cw), r = Math.round((gy - target.y - topM) / ch);
        const pos = Global.iconPos || {};
        const names = [];
        for (const p of selectedPaths()) names.push(p.substring(p.lastIndexOf("/") + 1));
        if (names.indexOf(anchorName) < 0) names.push(anchorName);
        const a = pos[anchorName];
        const moves = [];
        for (const n of names) {
            const o = pos[n];
            const same = a && o && a.m === o.m;
            moves.push({ name: n, m: target.name, c: n === anchorName ? c : (same ? c + (o.c - a.c) : c), r: n === anchorName ? r : (same ? r + (o.r - a.r) : r) });
        }
        Global.iconMove(moves);
    }

    Item {
        id: grid
        visible: desk.showIcons
        anchors.fill: parent
        anchors.margins: 18
        anchors.bottomMargin: Global.barHeight + Global.barMargin * 2 + 18
        anchors.topMargin: Global.barTop ? Global.barHeight + Global.barMargin * 2 + 18 : 18
        readonly property int cellWidth: Global.iconGrid
        readonly property int cellHeight: Global.iconGrid + 14
        readonly property int count: iconRep.count

        Repeater {
            id: iconRep
            model: folder
        delegate: Item {
            id: cell
            required property string fileName
            required property string filePath
            required property bool fileIsDir
            required property string fileSuffix
            readonly property bool sel: desk.isSelected(filePath)
            readonly property bool isDesktopFile: fileSuffix.toLowerCase() === "desktop"
            readonly property var appEntry: isDesktopFile ? Global.entryFor(fileName.replace(/\.desktop$/, "")) : null
            readonly property string label: isDesktopFile && appEntry ? appEntry.name : (isDesktopFile ? fileName.replace(/\.desktop$/, "") : fileName)

            readonly property var ipos: (Global.iconPos || {})[fileName]
            visible: ipos !== undefined && ipos.m === desk.mon
            x: ipos ? ipos.c * grid.cellWidth : 0
            y: ipos ? ipos.r * grid.cellHeight : 0
            width: grid.cellWidth
            height: grid.cellHeight
            opacity: desk.dragActive && sel ? 0.35 : 1

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: Theme.rM
                color: cell.sel ? Theme.accentHover : (cellArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                border.color: cell.sel ? Theme.accent : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast } }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 6
                    width: parent.width - 6
                    spacing: 5

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 46; height: 46
                        // Bild-Vorschau für Fotos, sonst Icon
                        Image {
                            anchors.fill: parent
                            visible: desk.isImage(cell.fileSuffix)
                            source: visible ? "file://" + cell.filePath : ""
                            sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                        IconImage {
                            anchors.fill: parent
                            visible: !desk.isImage(cell.fileSuffix)
                            source: cell.isDesktopFile && cell.appEntry
                                    ? Global.iconFor(cell.appEntry.id, cell.appEntry)
                                    : Quickshell.iconPath(desk.iconNameFor(cell.fileName, cell.fileIsDir, cell.fileSuffix), "text-x-generic")
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.label
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.text
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.75)
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
            }

            MouseArea {
                id: cellArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property point grab: Qt.point(0, 0)
                property bool moved: false
                onPressed: mouse => {
                    moved = false;
                    grab = Qt.point(mouse.x, mouse.y);
                    if (mouse.button === Qt.LeftButton && !desk.isSelected(cell.filePath) && !(mouse.modifiers & Qt.ControlModifier))
                        desk.setSel([cell.filePath]);
                }
                onPositionChanged: mouse => {
                    if (!(pressedButtons & Qt.LeftButton)) return;
                    if (!moved && Math.abs(mouse.x - grab.x) + Math.abs(mouse.y - grab.y) > 10) {
                        moved = true; desk.dragActive = true; desk.menu = null;
                        desk.dragLabel = desk.selCount > 1 ? desk.selCount + " Elemente" : cell.label;
                    }
                    if (moved) desk.dragPoint = cellArea.mapToItem(bgArea, mouse.x, mouse.y);
                }
                onReleased: mouse => {
                    if (!moved) return;
                    const p = cellArea.mapToItem(bgArea, mouse.x, mouse.y);
                    desk.dragActive = false;
                    desk.dropIcons(cell.fileName, grab.x, grab.y, p.x, p.y);
                }
                onCanceled: { moved = false; desk.dragActive = false; }
                onClicked: mouse => {
                    if (moved) return;
                    if (mouse.button === Qt.RightButton) {
                        if (!desk.isSelected(cell.filePath)) desk.setSel([cell.filePath]);
                        desk.menu = { x: cell.x + mouse.x + 18, y: cell.y + mouse.y + 18, kind: "item", path: cell.filePath,
                                      name: cell.fileName, isDir: cell.fileIsDir, suffix: cell.fileSuffix };
                    } else if (mouse.modifiers & Qt.ControlModifier) {
                        desk.toggleSel(cell.filePath);
                        desk.menu = null;
                    } else {
                        desk.setSel([cell.filePath]);
                        desk.menu = null;
                    }
                }
                onDoubleClicked: desk.openItem(cell.filePath, cell.fileName, cell.fileIsDir, cell.fileSuffix)
            }
        }
    }

    }   // Ende Symbol-Fläche

    // Zieh-Vorschau (nur im Fenster, in dem das Ziehen begann)
    Rectangle {
        visible: desk.dragActive
        x: desk.dragPoint.x + 10; y: desk.dragPoint.y + 10
        width: dragText.implicitWidth + 24; height: 32; radius: 16
        color: Theme.accent; z: 20
        Text { id: dragText; anchors.centerIn: parent; text: desk.dragLabel; color: "white"; font.family: Theme.font; font.pixelSize: 12 }
    }

    // ---------- Kontextmenü ----------
    MouseArea {
        anchors.fill: parent
        visible: desk.menu !== null
        z: 5
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: desk.menu = null
    }
    Surface {
        id: ctx
        visible: desk.menu !== null
        z: 6
        level: 2
        radius: Theme.rM
        width: 240
        height: ctxCol.implicitHeight + 16
        x: desk.menu ? Math.min(desk.menu.x, desk.width - width - 8) : 0
        y: desk.menu ? Math.min(desk.menu.y, desk.height - height - 70) : 0

        Column {
            id: ctxCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            // --- Datei/Ordner ---
            MenuRow {
                visible: desk.menu && desk.menu.kind === "item" && desk.selCount <= 1
                width: ctxCol.width
                iconName: "folder"
                label: "Öffnen"
                onTriggered: { desk.openItem(desk.menu.path, desk.menu.name, desk.menu.isDir, desk.menu.suffix); desk.menu = null; }
            }
            MenuRow {
                visible: desk.menu && desk.menu.kind === "item" && desk.selCount <= 1
                width: ctxCol.width
                iconName: "desktop"
                label: "In Dolphin anzeigen"
                onTriggered: { Quickshell.execDetached(["dolphin", "--select", desk.menu.path]); desk.menu = null; }
            }
            MenuRow {
                visible: desk.menu && desk.menu.kind === "item" && desk.menu.isDir && desk.selCount <= 1
                width: ctxCol.width
                iconName: "add"
                label: "Im Terminal öffnen"
                onTriggered: { Quickshell.execDetached([Theme.home + "/.local/bin/dx-terminal", "--dir", desk.menu.path]); desk.menu = null; }
            }
            MenuRow {
                visible: desk.menu && desk.menu.kind === "item"
                width: ctxCol.width
                iconName: "clipboard"
                label: desk.selCount > 1 ? "Pfade kopieren (" + desk.selCount + ")" : "Pfad kopieren"
                onTriggered: { Quickshell.execDetached(["wl-copy", desk.selectedPaths().join("\n")]); desk.menu = null; }
            }
            MenuRow {
                visible: desk.menu && desk.menu.kind === "item"
                width: ctxCol.width
                iconName: "close"
                label: desk.selCount > 1 ? "In den Papierkorb (" + desk.selCount + ")" : "In den Papierkorb"
                onTriggered: { Quickshell.execDetached(["gio", "trash"].concat(desk.selectedPaths())); desk.menu = null; desk.clearSel(); }
            }

            // --- leere Fläche ---
            MenuRow {
                visible: desk.menu && desk.menu.kind === "empty"
                width: ctxCol.width
                iconName: "add"
                label: "Neuer Ordner"
                onTriggered: { Quickshell.execDetached(["mkdir", "-p", Theme.home + "/Schreibtisch/Neuer Ordner"]); desk.menu = null; }
            }
            MenuRow {
                visible: desk.menu && desk.menu.kind === "empty"
                width: ctxCol.width
                iconName: "folder"
                label: "Desktop-Ordner in Dolphin"
                onTriggered: { Quickshell.execDetached(["dolphin", Theme.home + "/Schreibtisch"]); desk.menu = null; }
            }
            MenuRow {
                visible: desk.menu && desk.menu.kind === "empty"
                width: ctxCol.width
                iconName: "add"
                label: "Terminal hier"
                onTriggered: { Quickshell.execDetached([Theme.home + "/.local/bin/dx-terminal", "--dir", Theme.home + "/Schreibtisch"]); desk.menu = null; }
            }
            MenuRow {
                visible: desk.menu && desk.menu.kind === "empty"
                width: ctxCol.width
                iconName: "desktop"
                label: "Anzeigeeinstellungen"
                onTriggered: { Quickshell.execDetached(["nwg-displays"]); desk.menu = null; }
            }
        }
    }
}
