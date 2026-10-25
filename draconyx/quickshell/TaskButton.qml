import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// Ein Knopf pro App: angeheftet und/oder laufend. Mehrere Fenster werden gruppiert.
// Hover = Live-Vorschau der Fenster, Rechtsklick = Menü mit Fensteraktionen, ziehen = angeheftete Apps sortieren.
BarButton {
    id: tb
    required property var group           // { id, pinned, pinIndex, windows: [Toplevel] }
    property int slot: 0                  // Breite eines Plätzchens (für Drag-Sortierung)
    property string mon: ""               // Monitor dieser Leiste
    readonly property var entry: Global.entryFor(group.id)
    readonly property int count: group.windows.length
    readonly property bool focused: group.windows.some(w => w.activated)
    readonly property bool allMinimized: count > 0 && group.windows.every(w => Global.isMinimized(w))
    readonly property string appName: entry ? entry.name : group.id
    readonly property var badge: Global.badgeFor(group.id)
    readonly property bool belowBar: Global.barTop        // Popups öffnen zur Bildschirmmitte hin

    active: focused || popup.visible
    draggable: group.pinned
    minWidth: Global.iconSize + 22
    padding: 8
    opacity: 1

    // ---------- Icon ----------
    IconImage {
        id: appIcon
        implicitSize: Global.iconSize
        source: Global.iconFor(tb.group.id, tb.entry)
        scale: tb.hovered ? 1.08 : 1.0
        opacity: tb.allMinimized ? 0.55 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
        Behavior on opacity { NumberAnimation { duration: Theme.durBase } }
    }

    // ---------- Badge (Anzahl ungelesen o. Ä.) ----------
    Rectangle {
        parent: tb
        visible: tb.badge !== null && tb.badge.countVisible && tb.badge.count > 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 1
        width: Math.max(16, badgeLabel.implicitWidth + 8)
        height: 16
        radius: 8
        color: Theme.accent
        border.color: Theme.bg0
        border.width: 2
        Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: tb.badge ? (tb.badge.count > 99 ? "99+" : tb.badge.count) : ""
            color: Theme.textOn
            font.family: Theme.font
            font.pixelSize: 9
            font.bold: true
        }
    }

    // ---------- Fortschritt (z. B. Downloads) ----------
    Rectangle {
        parent: tb
        visible: tb.badge !== null && tb.badge.progressVisible
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 9
        anchors.rightMargin: 9
        anchors.bottomMargin: 8
        height: 3
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.14)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, tb.badge ? tb.badge.progress : 0))
            height: parent.height
            radius: 2
            color: Theme.green
            Behavior on width { NumberAnimation { duration: Theme.durBase } }
        }
    }

    // ---------- Indikator: Punkt = läuft, Strich = mehrere Fenster, breit + violett = aktiv ----------
    Rectangle {
        parent: tb
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: tb.belowBar ? undefined : parent.bottom
        anchors.top: tb.belowBar ? parent.top : undefined
        anchors.bottomMargin: 2
        anchors.topMargin: 2
        height: 3
        radius: 2
        opacity: tb.count > 0 ? 1 : 0
        width: tb.focused ? 20 : (tb.count > 1 ? 12 : 5)
        color: tb.focused ? Theme.accentBright : Theme.textDim
        Behavior on width   { NumberAnimation { duration: Theme.durBase; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: Theme.durBase } }
        Behavior on color   { ColorAnimation { duration: Theme.durBase } }
    }

    // ---------- Klicks ----------
    onClicked: mouse => {
        previewTimer.stop();
        if (mouse.button === Qt.MiddleButton) {
            Global.launch(group.id, entry);
        } else if (mouse.button === Qt.RightButton) {
            popup.mode = "menu";
            popup.visible = true;
        } else if (count === 0) {
            popup.visible = false;
            Global.launch(group.id, entry);
        } else if (count === 1) {
            popup.visible = false;
            const w = group.windows[0];
            // wie unter Windows: minimiertes Fenster holen, aktives Fenster minimieren, sonst fokussieren
            if (Global.isMinimized(w)) Global.focusToplevel(w);
            else if (w.activated) Global.minimizeToplevel(w);
            else Global.focusToplevel(w);
        } else {
            // mehrere Fenster: Vorschau offen halten, bis ein Fenster gewählt wird
            popup.mode = "preview";
            popup.sticky = true;
            popup.visible = true;
        }
    }

    // ---------- Sortieren per Drag-and-drop ----------
    onDragDropped: dx => {
        if (group.pinIndex < 0 || slot <= 0) return;
        const shift = Math.round(dx / slot);
        if (shift !== 0) Global.movePinned(group.pinIndex, group.pinIndex + shift);
    }

    // ---------- Hover-Vorschau ----------
    onHoveredChanged: {
        if (hovered) { hideTimer.stop(); if (count > 0 && !popup.visible) previewTimer.restart(); }
        else { previewTimer.stop(); if (popup.mode === "preview" && !popup.sticky) hideTimer.restart(); }
    }
    Timer { id: previewTimer; interval: 380; onTriggered: { if (tb.hovered && tb.count > 0) { popup.mode = "preview"; popup.sticky = false; popup.visible = true; } } }
    Timer { id: hideTimer; interval: 260; onTriggered: { if (!tb.hovered && !popupHover.hovered && !popup.sticky) popup.visible = false; } }

    PopupWindow {
        id: popup
        property string mode: "preview"       // "preview" | "menu"
        property bool sticky: false
        onStickyChanged: Global.taskMenuOpen = visible && (mode === "menu" || sticky)
        anchor.item: tb
        anchor.edges: tb.belowBar ? Edges.Bottom : Edges.Top
        anchor.gravity: tb.belowBar ? Edges.Bottom : Edges.Top
        anchor.margins.top: tb.belowBar ? 8 : 0
        anchor.margins.bottom: tb.belowBar ? 0 : 8
        implicitWidth: panel.implicitWidth
        implicitHeight: panel.implicitHeight
        color: "transparent"
        visible: false
        onVisibleChanged: {
            Global.taskPopupOpen = visible;
            Global.taskPopupScreen = visible ? tb.mon : "";
            Global.taskMenuOpen = visible && (mode === "menu" || sticky);
            if (!visible) sticky = false;
        }

        Connections {
            target: Global
            function onTaskMenuClose() { if (popup.visible) popup.visible = false; }
        }

        HyprlandFocusGrab {
            windows: [popup]
            active: popup.visible && (popup.mode === "menu" || popup.sticky)
            onCleared: popup.visible = false
        }

        Surface {
            id: panel
            level: 2
            radius: Theme.rL
            implicitWidth: popup.mode === "preview" ? previewRow.implicitWidth + 24 : 252
            implicitHeight: (popup.mode === "preview" ? previewRow.implicitHeight : menuCol.implicitHeight) + 24
            width: implicitWidth
            height: implicitHeight

            HoverHandler { id: popupHover; onHoveredChanged: { if (hovered) hideTimer.stop(); else if (popup.mode === "preview" && !popup.sticky) hideTimer.restart(); } }

            // ---------- Vorschau: Live-Bild je Fenster ----------
            Flow {
                id: previewRow
                visible: popup.mode === "preview"
                anchors.centerIn: parent
                spacing: 10
                width: Math.min(tb.count, 4) * 214 + (Math.min(tb.count, 4) - 1) * 10

                Repeater {
                    model: popup.mode === "preview" && popup.visible ? tb.group.windows : []
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        width: 214
                        height: 150
                        radius: Theme.rM
                        color: cardArea.containsMouse ? Theme.tileHover : Theme.tile
                        border.color: modelData.activated ? Theme.accent : "transparent"
                        border.width: 2
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }

                        Row {
                            id: cardHead
                            x: 8; y: 7
                            spacing: 6
                            IconImage { implicitSize: 16; source: Global.iconFor(tb.group.id, tb.entry); anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                width: 150
                                text: card.modelData.title || tb.appName
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: Theme.fsS
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 4
                            width: 24; height: 24; radius: 8
                            color: closeArea.containsMouse ? Qt.rgba(1, 0.42, 0.42, 0.30) : "transparent"
                            visible: cardArea.containsMouse || closeArea.containsMouse
                            Icon { anchors.centerIn: parent; name: "close"; size: 12 }
                            MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: card.modelData.close() }
                        }
                        Item {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: cardHead.bottom; anchors.bottom: parent.bottom
                            anchors.margins: 8; anchors.topMargin: 6
                            clip: true
                            ScreencopyView {
                                anchors.fill: parent
                                captureSource: card.modelData
                                live: popup.visible
                            }
                        }
                        MouseArea {
                            id: cardArea
                            anchors.fill: parent
                            hoverEnabled: true
                            z: -1
                            onClicked: { Global.focusToplevel(card.modelData); popup.visible = false; }
                        }
                    }
                }
            }

            // ---------- Kontextmenü ----------
            Column {
                id: menuCol
                visible: popup.mode === "menu"
                anchors.fill: parent
                anchors.margins: 10
                spacing: 2

                Row {
                    spacing: 8
                    leftPadding: 8; bottomPadding: 6; topPadding: 2
                    IconImage { implicitSize: 18; source: Global.iconFor(tb.group.id, tb.entry); anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: tb.appName
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MenuRow {
                    width: menuCol.width
                    iconName: "add"
                    label: "Neues Fenster"
                    onTriggered: { Global.launch(tb.group.id, tb.entry); popup.visible = false; }
                }
                // Aktionen der Desktop-Datei (z. B. "Neues privates Fenster")
                Repeater {
                    model: tb.entry && tb.entry.actions ? tb.entry.actions : []
                    delegate: MenuRow {
                        required property var modelData
                        width: menuCol.width
                        label: modelData.name
                        onTriggered: { modelData.execute(); popup.visible = false; }
                    }
                }
                MenuRow {
                    width: menuCol.width
                    iconName: Global.isPinned(tb.group.id) ? "pin-off" : "pin"
                    label: Global.isPinned(tb.group.id) ? "Von Taskleiste lösen" : "An Taskleiste anheften"
                    onTriggered: { Global.togglePin(tb.group.id); popup.visible = false; }
                }

                // Fensteraktionen (für das aktive bzw. erste Fenster der App)
                Rectangle { visible: tb.count > 0; width: menuCol.width; height: 1; color: Theme.borderSoft }
                MenuRow {
                    visible: tb.count > 0
                    width: menuCol.width
                    iconName: "window"
                    label: "Maximieren / Wiederherstellen"
                    onTriggered: {
                        const h = Global.hyprFor(tb.group.windows.find(w => w.activated) || tb.group.windows[0]);
                        if (h) { Global.focusHypr(h); Global.hypr("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })"); }
                        popup.visible = false;
                    }
                }
                MenuRow {
                    visible: tb.count > 0
                    width: menuCol.width
                    iconName: "chevron-down"
                    label: tb.allMinimized ? "Wiederherstellen" : "Minimieren"
                    onTriggered: {
                        for (const w of tb.group.windows) { if (tb.allMinimized) Global.focusToplevel(w); else Global.minimizeToplevel(w); }
                        popup.visible = false;
                    }
                }
                MenuRow {
                    visible: tb.count > 0
                    width: menuCol.width
                    iconName: "desktop"
                    label: "Auf nächsten Monitor"
                    onTriggered: {
                        const h = Global.hyprFor(tb.group.windows.find(w => w.activated) || tb.group.windows[0]);
                        if (h) { Global.focusHypr(h); Global.hypr("hl.dsp.window.move({ monitor = \"r\", follow = true })"); }
                        popup.visible = false;
                    }
                }
                MenuRow {
                    visible: tb.count > 0
                    width: menuCol.width
                    iconName: "close"
                    label: tb.count > 1 ? "Alle " + tb.count + " Fenster schließen" : "Fenster schließen"
                    onTriggered: { tb.group.windows.forEach(w => w.close()); popup.visible = false; }
                }
            }
        }
    }
}
