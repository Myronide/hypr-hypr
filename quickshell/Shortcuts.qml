import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Tastenkürzel-Übersicht (Strg+Alt+I): alle wirksamen Kombinationen, nach Themen sortiert und durchsuchbar.
// Gelesen wird ~/.config/draconyx/binds-registry.tsv (schreibt die Hyprland-Konfiguration); geändert wird in Aurora.
PanelWindow {
    id: sc
    visible: Global.shortcutsOpen
    screen: Global.screenByName(Global.popupScreen)
    anchors.top: true
    margins.top: screen ? Math.round(screen.height * 0.10) : 100
    implicitWidth: 920
    implicitHeight: Math.min(720, screen ? screen.height * 0.8 : 720)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "draconyx-shortcuts"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property var rows: []
    property string query: ""

    onVisibleChanged: if (visible) { query = ""; input.text = ""; reg.reload(); input.forceActiveFocus(); }
    HyprlandFocusGrab { windows: [sc]; active: sc.visible; onCleared: if (!Global.snipBusy) Global.shortcutsOpen = false }

    readonly property var groups: [
        { name: "Starten & Suchen", ids: ["start_menu", "desktop_search", "search", "run_menu", "quick_settings", "notifications", "clipboard_history", "shortcuts_help", "task_view", "coding_space", "file_manager", "terminal", "dropdown_terminal", "browser", "focus_timer", "focus_timer_open"] },
        { name: "Fenster", ids: ["window_close", "window_kill", "window_minimize", "window_restore", "fullscreen", "fullscreen_f11", "window_center", "snap_up", "snap_down", "snap_left", "snap_right", "window_to_left_monitor", "window_to_right_monitor", "window_menu", "switcher_next", "switcher_prev", "free_mouse"] },
        { name: "Raster & Kacheln", ids: ["grid_toggle", "grid_toggle_workspace", "grid_mode", "zones_cycle", "zones_edit", "zones_pick", "grid_shift_prev", "grid_shift_next", "grid_panic"] },
        { name: "Desktops", ids: ["desktop_prev", "desktop_next", "ws_focus_1", "ws_move_1"] },
        { name: "Screenshots", ids: ["screenshot_region", "screenshot_snip", "screenshot_screen"] },
        { name: "System", ids: ["lock", "exit_hyprland", "volume_up", "volume_down", "volume_mute", "mic_mute_key", "media_play", "media_next", "media_prev"] },
        { name: "Maus", ids: ["window_drag", "window_resize", "window_drag_alt", "window_resize_alt"] }
    ]

    function pretty(combo) {
        const map = { CTRL: "Strg", ALT: "Alt", SHIFT: "Umschalt", SUPER: "Super", space: "Leertaste", Prior: "Bild ↑", Next: "Bild ↓",
                      Up: "↑", Down: "↓", Left: "←", Right: "→", comma: ",", period: ".", Escape: "Esc", BackSpace: "⌫", Print: "Druck",
                      Tab: "Tab", Return: "Enter", slash: "/", "mouse:272": "Linksklick", "mouse:273": "Rechtsklick",
                      XF86AudioRaiseVolume: "Lauter", XF86AudioLowerVolume: "Leiser", XF86AudioMute: "Stumm", XF86AudioNext: "Weiter",
                      XF86AudioPrev: "Zurück", XF86AudioPlay: "Play", XF86AudioPause: "Pause" };
        return combo.split("+").map(s => s.trim()).filter(s => s !== "").map(s => map[s] !== undefined ? map[s] : (s.length === 1 ? s.toUpperCase() : s));
    }
    function build(text) {
        const byId = {};
        for (const line of text.split("\n")) {
            const p = line.split("\t");
            if (p.length < 4 || p[0] === "") continue;
            byId[p[0]] = { id: p[0], label: p[1], keys: p[3] };
        }
        const out = []; const used = {};
        for (const g of groups) {
            const items = [];
            for (const id of g.ids) {
                const e = byId[id]; if (!e || e.keys === "") continue;
                used[id] = true;
                let label = e.label;
                let keys = pretty(e.keys);
                if (id === "ws_focus_1") { label = "Zu Desktop 1–9"; keys = pretty(e.keys.replace(/1$/, "")).concat(["1–9"]); }
                if (id === "ws_move_1") { label = "Fenster auf Desktop 1–9"; keys = pretty(e.keys.replace(/1$/, "")).concat(["1–9"]); }
                items.push({ label: label, keys: keys });
            }
            if (items.length > 0) out.push({ name: g.name, items: items });
        }
        const rest = [];
        for (const id in byId) if (!used[id] && byId[id].keys !== "" && !/^ws_(focus|move)_/.test(id) && !/^switcher_(commit|cancel)/.test(id) && !/^media_pause/.test(id))
            rest.push({ label: byId[id].label, keys: pretty(byId[id].keys) });
        if (rest.length > 0) out.push({ name: "Weitere", items: rest });
        return out;
    }
    FileView { id: reg; path: Theme.home + "/.config/draconyx/binds-registry.tsv"; onLoaded: sc.rows = sc.build(text()) }

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        if (q === "") return rows;
        const out = [];
        for (const g of rows) {
            const it = g.items.filter(i => i.label.toLowerCase().includes(q) || i.keys.join(" ").toLowerCase().includes(q));
            if (it.length > 0) out.push({ name: g.name, items: it });
        }
        return out;
    }

    PopCard {
        anchors.fill: parent
        radius: 24
        color: Theme.panelStrong
        border.color: Theme.border

        Item {
            id: head
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 76
            Icon { id: ico; name: "keyboard"; size: 24; accent: true; anchors.left: parent.left; anchors.leftMargin: 28; anchors.verticalCenter: parent.verticalCenter }
            Column {
                anchors.left: ico.right; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                Text { text: "Tastenkürzel"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXl; font.weight: Font.DemiBold }
                Text { text: "Strg + Alt ist die Hauptkombination. Ändern kannst du alles in Aurora → Tastenkombinationen."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
            }
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter
                width: 260; height: 40; radius: 20; color: Theme.tile; border.color: input.activeFocus ? Theme.accent : Theme.borderSoft
                Icon { name: "search"; size: 16; anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter }
                TextInput {
                    id: input
                    anchors.left: parent.left; anchors.leftMargin: 40; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; selectionColor: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.fsM; clip: true
                    onTextChanged: sc.query = text
                    Keys.onEscapePressed: Global.shortcutsOpen = false
                    Text { visible: input.text === ""; text: "Suchen …"; color: Theme.textDim; font: input.font }
                }
            }
        }

        Flickable {
            id: fl
            ScrollSpeed { }
            anchors.top: head.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 24; anchors.topMargin: 4
            contentHeight: cols.height + 10
            clip: true; boundsBehavior: Flickable.StopAtBounds

            // zwei Spalten: Gruppen abwechselnd auf die kürzere Seite
            readonly property var split: {
                const a = [], b = []; let ha = 0, hb = 0;
                for (const g of sc.shown) {
                    const h = 40 + g.items.length * 34;
                    if (ha <= hb) { a.push(g); ha += h; } else { b.push(g); hb += h; }
                }
                return [a, b];
            }
            Row {
                id: cols
                width: parent.width; spacing: 28
                Repeater {
                    model: fl.split
                    Column {
                        required property var modelData
                        width: (cols.width - 28) / 2
                        spacing: 18
                        Repeater {
                            model: modelData
                            Column {
                                required property var modelData
                                width: parent.width
                                spacing: 4
                                Text { text: modelData.name.toUpperCase(); color: Theme.accentBright; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.4; bottomPadding: 6 }
                                Repeater {
                                    model: modelData.items
                                    Item {
                                        required property var modelData
                                        width: parent.width; height: 30
                                        Text { anchors.left: parent.left; anchors.right: caps.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                               text: modelData.label; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS + 1 }
                                        Row {
                                            id: caps
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                            Repeater {
                                                model: modelData.keys
                                                Rectangle {
                                                    required property string modelData
                                                    height: 24; width: Math.max(26, kt.implicitWidth + 14); radius: 7
                                                    color: Theme.tile; border.color: Theme.borderSoft
                                                    Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width - 8; height: 2; radius: 1; color: Qt.rgba(1, 1, 1, 0.10) }
                                                    Text { id: kt; anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs; font.weight: Font.Medium }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
