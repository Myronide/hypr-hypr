import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Coding Space: Wurzel zeigt die Workspaces; ein Workspace lässt sich betreten, darin liegen die Projekte.
// Projekt: Klick = Ordner öffnen; rechts die Programm-Symbole IntelliJ und VS Code (starten das Programm mit dem Projekt),
// dazu Terminal und Claude.
PanelWindow {
    id: cs
    visible: Global.codeOpen
    screen: Global.screenByName(Global.popupScreen)

    anchors.bottom: !Global.barTop
    anchors.top: Global.barTop
    anchors.left: true
    margins.bottom: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.top: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.left: Global.popupLeft()
    implicitWidth: 600
    implicitHeight: 640
    exclusionMode: ExclusionMode.Ignore      // Abstand zur Leiste kommt aus den Rändern; die Leisten-Reservierung nicht doppelt rechnen
    color: "transparent"
    WlrLayershell.namespace: "draconyx-code"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property string query: ""
    property bool creating: false
    property var extraGrab: null          // weiteres Fenster, das zum Coding Space gehört (Git-Feld)
    property bool cloning: false
    property var ctx: null              // { item, x, y } Rechtsklick-Menü auf einer Zeile
    readonly property bool inside: Global.codeStack.length > 0
    readonly property string currentName: inside ? Global.codeCurrent.substring(Global.codeCurrent.lastIndexOf("/") + 1) : "Coding Space"
    readonly property var filtered: Global.projects.filter(p => query === "" || p.name.toLowerCase().includes(query.toLowerCase()))
    readonly property var vscodeEntry: Global.entryFor("com.microsoft.VSCode")

    onVisibleChanged: {
        ctx = null;
        if (visible) {
            query = ""; search.text = ""; creating = false; cloning = false; search.forceActiveFocus();
            Global.codeReset();
            Global.refreshProjects();
        }
    }

    HyprlandFocusGrab {
        id: csGrab
        windows: cs.extraGrab ? [cs, cs.extraGrab] : [cs]
        active: cs.visible
        onCleared: if (!Global.snipBusy) Global.closeAll()
    }
    // Nach dem Snip (Fokus kam vom Snip-Fenster zurück) den Fokus-Wächter neu setzen, sonst bleibt das Fenster ohne Tastatur
    Connections { target: Global; function onSnipBusyChanged() { if (!Global.snipBusy && cs.visible) { csGrab.active = false; csGrab.active = true; } } }

    function ago(mtime) {
        const s = Math.max(0, Date.now() / 1000 - mtime);
        if (s < 3600) return "vor " + Math.max(1, Math.round(s / 60)) + " Min.";
        if (s < 86400) return "vor " + Math.round(s / 3600) + " Std.";
        if (s < 86400 * 60) return "vor " + Math.round(s / 86400) + " Tagen";
        return "vor " + Math.round(s / 86400 / 30) + " Monaten";
    }
    function activate(item) {
        if (item.kind === "workspace") { search.text = ""; Global.codeEnter(item.path); }
        else Global.openProject(item.path, "folder");
    }

    Surface {
        anchors.fill: parent
        level: 2
        radius: Theme.rXl

        // ---------- Kopf ----------
        Item {
            id: head
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 74

            Row {
                anchors.left: parent.left; anchors.leftMargin: 22
                anchors.top: parent.top; anchors.topMargin: 18
                spacing: 12

                // Zurück (nur innerhalb eines Workspaces)
                BarButton {
                    visible: cs.inside
                    anchors.verticalCenter: parent.verticalCenter
                    minWidth: 38; implicitHeight: 38; radiusSize: 12
                    color: hovered ? Theme.tileHover : Theme.tile
                    Icon { name: "chevron-left"; size: 18 }
                    onClicked: { search.text = ""; Global.codeBack(); }
                }
                Rectangle {
                    visible: !cs.inside
                    width: 38; height: 38; radius: 12
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Theme.accentDeep }
                    }
                    Icon { anchors.centerIn: parent; name: "code"; size: 20 }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: 330
                        text: cs.currentName
                        elide: Text.ElideRight
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold
                    }
                    Text {
                        width: 330
                        elide: Text.ElideMiddle
                        text: cs.inside ? Global.codeCurrent.replace("/run/media/" + (Quickshell.env("USER") || ""), "")
                                        : (Global.codeRootEffective !== "" ? Global.codeRootEffective.replace("/run/media/" + (Quickshell.env("USER") || ""), "") : "Kein Code-Laufwerk gefunden")
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
                    }
                }
            }
            BarButton {
                visible: cs.inside
                anchors.right: parent.right; anchors.rightMargin: 124
                anchors.top: parent.top; anchors.topMargin: 20
                implicitHeight: 34; padding: 12; radiusSize: 17
                active: cs.cloning
                color: hovered ? Theme.accentHover : (cs.cloning ? Theme.accentSoft : Theme.tile)
                Row {
                    spacing: 7
                    Icon { name: "branch"; size: 15; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Klonen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                }
                onClicked: { cs.cloning = !cs.cloning; if (cs.cloning) cloneUrl.forceActiveFocus(); else search.forceActiveFocus(); }
            }
            BarButton {
                visible: !cs.inside
                anchors.right: parent.right; anchors.rightMargin: 124
                anchors.top: parent.top; anchors.topMargin: 20
                implicitHeight: 34; padding: 12; radiusSize: 17
                active: cs.creating
                color: hovered ? Theme.accentHover : (cs.creating ? Theme.accentSoft : Theme.tile)
                Row {
                    spacing: 7
                    Icon { name: "add"; size: 15; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Workspace"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                }
                onClicked: { cs.creating = !cs.creating; if (cs.creating) newName.forceActiveFocus(); else search.forceActiveFocus(); }
            }
            BarButton {
                anchors.right: parent.right; anchors.rightMargin: 18
                anchors.top: parent.top; anchors.topMargin: 20
                implicitHeight: 34; padding: 12; radiusSize: 17
                color: hovered ? Theme.tileHover : Theme.tile
                Row {
                    spacing: 7
                    Icon { name: "folder-open"; size: 15; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Ordner"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; anchors.verticalCenter: parent.verticalCenter }
                }
                onClicked: {
                    const p = cs.inside ? Global.codeCurrent : Global.codeRootEffective;
                    Global.codeOpen = false;
                    if (p !== "") Quickshell.execDetached(["dolphin", p]);
                }
            }
        }

        // ---------- Suche ----------
        Rectangle {
            id: searchBox
            anchors.top: head.bottom
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 20; anchors.rightMargin: 20
            height: 42; radius: 21
            color: Theme.tile
            border.color: search.activeFocus ? Theme.accent : Theme.borderSoft
            Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
            Icon { id: sIcon; name: "search"; size: 17; anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter }
            TextInput {
                id: search
                anchors.left: sIcon.right; anchors.leftMargin: 10
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: Theme.fsM + 1
                clip: true
                onTextChanged: cs.query = text
                Keys.onEscapePressed: { if (cs.inside && search.text === "") Global.codeBack(); else Global.codeOpen = false; }
                Keys.onBackPressed: { if (cs.inside && search.text === "") Global.codeBack(); }
                Keys.onReturnPressed: { if (cs.filtered.length > 0) cs.activate(cs.filtered[0]); }
                Text { visible: search.text === ""; text: cs.inside ? "Projekt in " + cs.currentName + " suchen …" : "Workspace oder Projekt suchen …"; color: Theme.textDim; font: search.font }
            }
        }

        // ---------- Klonen ----------
        Rectangle {
            visible: cs.cloning && cs.inside
            anchors.top: searchBox.bottom; anchors.topMargin: 10
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 20; anchors.rightMargin: 20
            height: 44; radius: 22
            color: Theme.tile
            border.color: cloneUrl.activeFocus ? Theme.accent : Theme.borderSoft
            Icon { id: cIcon; name: "branch"; size: 17; accent: true; anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter }
            TextInput {
                id: cloneUrl
                anchors.left: cIcon.right; anchors.leftMargin: 10
                anchors.right: cloneBtn.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: Theme.fsM + 1
                clip: true
                Keys.onEscapePressed: { cs.cloning = false; search.forceActiveFocus(); }
                Keys.onReturnPressed: cloneBtn.go()
                Text { visible: cloneUrl.text === ""; text: "Git-URL oder owner/repo (GitHub) …"; color: Theme.textDim; font: cloneUrl.font }
            }
            BarButton {
                id: cloneBtn
                anchors.right: parent.right; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 32; padding: 14; radiusSize: 16
                color: hovered ? Theme.accentHover : Theme.accent
                function go() {
                    if (cloneUrl.text.trim() === "") return;
                    Global.codeClone(cloneUrl.text);
                    cloneUrl.text = ""; cs.cloning = false; search.forceActiveFocus();
                }
                Text { text: "Klonen"; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
                onClicked: go()
            }
        }

        // ---------- Neuer Workspace ----------
        Rectangle {
            visible: cs.creating && !cs.inside
            anchors.top: searchBox.bottom; anchors.topMargin: 10
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 20; anchors.rightMargin: 20
            height: 44; radius: 22
            color: Theme.tile
            border.color: newName.activeFocus ? Theme.accent : Theme.borderSoft
            Icon { id: nIcon; name: "folder"; size: 17; accent: true; anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter }
            TextInput {
                id: newName
                anchors.left: nIcon.right; anchors.leftMargin: 10
                anchors.right: createBtn.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: Theme.fsM + 1
                clip: true
                Keys.onEscapePressed: { cs.creating = false; search.forceActiveFocus(); }
                Keys.onReturnPressed: createBtn.create()
                Text { visible: newName.text === ""; text: "Name des neuen Workspaces (frei wählbar) …"; color: Theme.textDim; font: newName.font }
            }
            BarButton {
                id: createBtn
                anchors.right: parent.right; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 32; padding: 14; radiusSize: 16
                color: hovered ? Theme.accentHover : Theme.accent
                function create() {
                    if (newName.text.trim() === "") return;
                    Global.codeNewWorkspace(newName.text);
                    newName.text = ""; cs.creating = false; search.forceActiveFocus();
                }
                Text { text: "Anlegen"; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
                onClicked: create()
            }
        }

        // ---------- Liste ----------
        ListView {
            ScrollSpeed { }
            id: list
            anchors.top: searchBox.bottom; anchors.topMargin: (cs.creating || cs.cloning) ? 64 : 12
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: foot.top
            anchors.leftMargin: 14; anchors.rightMargin: 14
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: cs.filtered

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isWs: modelData.kind === "workspace"
                width: ListView.view.width
                height: 56
                radius: Theme.rM
                color: rowArea.containsMouse ? Theme.tileHover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast } }

                Row {
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Rectangle {
                        width: 36; height: 36; radius: 11
                        color: row.isWs ? Theme.alpha(Theme.accent, 0.22) : (row.modelData.git ? Qt.rgba(0.43, 0.88, 0.36, 0.14) : Theme.tile)
                        Icon {
                            anchors.centerIn: parent
                            name: row.isWs ? "apps" : (row.modelData.git ? "branch" : "folder")
                            accent: row.isWs
                            size: 18
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            width: row.isWs ? 330 : 214
                            text: row.modelData.name
                            elide: Text.ElideRight
                            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM + 1
                        }
                        Text {
                            text: (row.isWs ? "Workspace  ·  " : "") + cs.ago(row.modelData.mtime)
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
                        }
                    }
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            const p = rowArea.mapToItem(null, mouse.x, mouse.y);
                            cs.ctx = { item: row.modelData, x: p.x, y: p.y };
                        } else cs.activate(row.modelData);
                    }
                }

                // Workspace: Pfeil zum Betreten
                Row {
                    visible: row.isWs
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    BarButton {
                        visible: rowArea.containsMouse
                        minWidth: 36; implicitHeight: 34
                        color: hovered ? Theme.accentHover : Theme.tile
                        Icon { name: "folder-open"; size: 16 }
                        onClicked: { Global.codeOpen = false; Quickshell.execDetached(["dolphin", row.modelData.path]); }
                    }
                    Icon { name: "chevron-right"; size: 18; anchors.verticalCenter: parent.verticalCenter }
                }

                // Projekt: Programm-Symbole (immer sichtbar, damit man sie direkt anklicken kann)
                Row {
                    visible: !row.isWs
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    // Programme (Aurora → Coding Space): ausgewählte erkannte IDEs/Editoren und eigene
                    Repeater {
                        model: Global.codeAppsShown
                        delegate: BarButton {
                            required property var modelData
                            minWidth: 40; implicitHeight: 38
                            color: hovered ? Theme.accentHover : Theme.tile
                            tip: "In " + modelData.name + " öffnen"
                            IconImage { implicitSize: 24; source: Global.codeAppIcon(modelData) }
                            onClicked: Global.openProject(row.modelData.path, "app:" + modelData.id)
                        }
                    }
                    // Terminal, Claude, Git
                    BarButton {
                        minWidth: 36; implicitHeight: 38
                        color: hovered ? Theme.accentHover : Theme.tile
                        Icon { name: "terminal"; size: 17 }
                        onClicked: Global.openProject(row.modelData.path, "term")
                    }
                    BarButton {
                        visible: Global.claudeAvailable
                        minWidth: 36; implicitHeight: 38
                        color: hovered ? Theme.accentHover : Theme.tile
                        Image { source: Theme.icon("claude-logo", false); sourceSize: Qt.size(40, 40); width: 20; height: 20; smooth: true }
                        onClicked: Global.openProject(row.modelData.path, "claude")
                    }
                    BarButton {
                        minWidth: 36; implicitHeight: 38
                        color: hovered ? Theme.accentHover : Theme.tile
                        Icon { name: "branch"; size: 17; accent: true }
                        onClicked: Global.openGit(row.modelData.path)
                    }
                }
            }

            Text {
                visible: cs.filtered.length === 0
                anchors.centerIn: parent
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Global.codeRootEffective === "" ? "Code-Laufwerk nicht eingehängt"
                    : (cs.inside ? "Keine Ordner in diesem Workspace" : "Noch nichts da – lege mit „+ Workspace“ einen Ordner an")
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsM
            }
        }


        // ---------- Rechtsklick-Menü ----------
        MouseArea {
            anchors.fill: parent; visible: cs.ctx !== null; z: 30
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: cs.ctx = null
        }
        Surface {
            id: ctxMenu
            visible: cs.ctx !== null
            z: 31; level: 3; radius: Theme.rM
            width: 250; height: ctxCol.implicitHeight + 12
            x: cs.ctx ? Math.max(8, Math.min(cs.ctx.x - 8, parent.width - width - 8)) : 0
            y: cs.ctx ? Math.max(8, Math.min(cs.ctx.y - 8, parent.height - height - 8)) : 0
            Column {
                id: ctxCol
                anchors.fill: parent; anchors.margins: 6; spacing: 2
                Repeater {
                    model: {
                        if (!cs.ctx) return [];
                        const isWs = cs.ctx.item.kind === "workspace";
                        const l = [
                            { t: "Pfad kopieren", a: "path", i: "clipboard" },
                            { t: "Name kopieren", a: "name", i: "clipboard" },
                            { t: "Im Dateimanager öffnen", a: "folder", i: "folder-open" }
                        ];
                        if (isWs) l.push({ t: "Betreten", a: "enter", i: "chevron-right" });
                        else {
                            l.push({ t: "Terminal hier", a: "term", i: "terminal" });
                            if (Global.claudeAvailable) l.push({ t: "Mit Claude öffnen", a: "claude", i: "bot" });
                            for (const ap of Global.codeAppsShown) l.push({ t: "In " + ap.name + " öffnen", a: "app:" + ap.id, i: "code" });
                            l.push({ t: "Git-Client öffnen", a: "git", i: "branch" });
                            l.push({ t: "Alles öffnen", a: "all", i: "apps" });
                        }
                        l.push({ t: isWs ? "Als Projekt behandeln" : "Als Workspace behandeln", a: isWs ? "markProject" : "markWorkspace", i: "folder" });
                        l.push({ t: "Automatisch erkennen", a: "markAuto", i: "restart" });
                        return l;
                    }
                    MenuRow {
                        required property var modelData
                        width: ctxCol.width
                        iconName: modelData.i
                        label: modelData.t
                        onTriggered: {
                            const it = cs.ctx.item; cs.ctx = null;
                            switch (modelData.a) {
                            case "path": Quickshell.execDetached(["wl-copy", it.path]); break;
                            case "name": Quickshell.execDetached(["wl-copy", it.name]); break;
                            case "folder": Global.codeOpen = false; Quickshell.execDetached(["dolphin", it.path]); break;
                            case "enter": cs.activate(it); break;
                            case "markProject": Global.codeMark(it.path, "project"); break;
                            case "markWorkspace": Global.codeMark(it.path, "workspace"); break;
                            case "markAuto": Global.codeMark(it.path, "auto"); break;
                            case "git": Global.openGit(it.path); break;
                            default: Global.openProject(it.path, modelData.a);
                            }
                        }
                    }
                }
            }
        }

        // ---------- Fuß ----------
        Rectangle {
            id: foot
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 44
            radius: Theme.rXl
            color: Qt.rgba(1, 1, 1, 0.03)
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.borderSoft }
            Text {
                anchors.centerIn: parent
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: Global.cloneStatus !== "" && cs.inside ? "Git: " + Global.cloneStatus
                    : cs.inside ? cs.filtered.length + " Einträge  ·  Klick = Ordner öffnen  ·  Esc = zurück"
                                : cs.filtered.length + " Einträge  ·  Workspace anklicken zum Betreten"
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
            }
        }
    }
}
