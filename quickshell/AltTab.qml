import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Alt+Tab-Umschalter: Fenster als Karten, sortiert nach zuletzt benutzt.
// Gesteuert per IPC aus Hyprland (Alt+Tab = next, Alt+Shift+Tab = prev, Alt loslassen = commit).
PanelWindow {
    id: sw
    property bool open: false
    property var items: []
    property int index: 0

    visible: open
    mask: Global.altTabMouse ? null : noInput           // Maus aus: die Übersicht fängt keine Mausereignisse
    Region { id: noInput }
    screen: Global.screenByName(Global.focusedScreenName())
    implicitWidth: Math.max(320, Math.min(items.length, 7) * 152 + 36)
    implicitHeight: 236
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "draconyx-alttab"
    WlrLayershell.layer: WlrLayer.Overlay
    // Keine Tastatur nötig (Tab/Alt kommen über Hyprland); Exclusive würde Mausklicks blockieren
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Zuletzt benutzt: wir führen die Reihenfolge selbst (Hyprland liefert den Fokusverlauf per IPC erst verzögert – das war der Grund,
    // warum Alt+Tab manchmal das falsche oder gar kein Fenster traf).
    property var mru: []                                   // Adressen, zuletzt aktives Fenster zuerst
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            const t = Hyprland.activeToplevel;
            if (t && t.address) sw.mru = [t.address].concat(sw.mru.filter(x => x !== t.address)).slice(0, 300);
        }
    }
    Component.onCompleted: { const t = Hyprland.activeToplevel; if (t && t.address) mru = [t.address]; }

    function build() {
        const list = Hyprland.toplevels.values.filter(t => {
            const o = t.lastIpcObject || {};
            return o.mapped !== false && o.hidden !== true;
        });
        const rank = t => {
            const i = sw.mru.indexOf(t.address);
            if (i >= 0) return i;
            const v = (t.lastIpcObject || {}).focusHistoryID;
            return 1000 + (v === undefined || v < 0 ? 999 : v);
        };
        list.sort((a, b) => rank(a) - rank(b));
        items = list;
    }

    // Ablauf wie unter Windows:
    //  – Alt+Tab antippen: springt SOFORT zum vorigen Fenster (keine Anzeige, nichts zu warten).
    //  – Alt halten und Tab weiter drücken: ab dem zweiten Druck erscheint die Übersicht, jeder Druck geht ein Fenster weiter.
    //  – Alt loslassen: das gewählte Fenster wird aktiv.
    property bool session: false          // Alt ist (vermutlich) noch gedrückt
    property double lastCommit: 0
    function press(dir) {
        if (!session) {
            build();
            const n = items.length;
            if (n < 2) return;
            index = dir > 0 ? 1 : n - 1;
            const t = items[index];
            Global.focusHypr(t);                                   // sofort umschalten
            // Alt wurde schon losgelassen, bevor dieser Befehl ankam (schneller Tipp): Ablauf ist damit erledigt
            if (Date.now() - lastCommit < 250) return;
            session = true;
            sessionGuard.restart();
        } else {
            const n = items.length;
            if (n === 0) return;
            index = (index + dir + n) % n;
            open = true;
            sessionGuard.restart();
        }
    }
    function next() { press(1); }
    function prev() { press(-1); }
    function commit() {
        lastCommit = Date.now();
        if (open) {
            const t = items[index];
            open = false;
            if (t) Global.focusHypr(t);
        }
        session = false;
    }
    function cancel() { open = false; session = false; }
    // Falls das Loslassen von Alt nie ankommt: ohne Übersicht nach einigen Sekunden die Sitzung beenden
    Timer { id: sessionGuard; interval: 4000; onTriggered: { if (!sw.open) sw.session = false; else sessionGuard.restart(); } }

    onOpenChanged: if (open) keys.forceActiveFocus()

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onReleased: event => { if (event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) sw.commit(); }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) sw.cancel();
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) sw.commit();
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) sw.next();
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) sw.prev();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 24
        color: Theme.panelStrong
        border.color: Theme.border

        ListView {
            id: cards
            anchors.fill: parent
            anchors.margins: 18
            orientation: ListView.Horizontal
            spacing: 8
            clip: true
            model: sw.items
            currentIndex: sw.index
            highlightMoveDuration: 120
            preferredHighlightBegin: width / 2 - 72
            preferredHighlightEnd: width / 2 + 72
            highlightRangeMode: ListView.ApplyRange

            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property var info: modelData.lastIpcObject || {}
                readonly property string appClass: info.class || (modelData.wayland ? modelData.wayland.appId : "")
                readonly property var entry: Global.entryFor(appClass)
                readonly property bool selected: index === sw.index

                width: 144
                height: cards.height
                radius: 16
                color: selected ? Theme.tileHover : (cardArea.containsMouse ? Theme.tile : "transparent")
                border.color: selected ? Theme.accent : "transparent"
                border.width: 2
                Behavior on color { ColorAnimation { duration: 100 } }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 10

                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: 64
                        source: Global.iconFor(card.appClass, card.entry)
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: card.entry ? card.entry.name : card.appClass
                        elide: Text.ElideRight
                        color: card.selected ? "#ffffff" : Theme.text
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: card.modelData.title || ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.textDim
                        font.family: Theme.font; font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: cardArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: Global.altTabMouse
                    onEntered: sw.index = card.index
                    onClicked: { sw.index = card.index; sw.commit(); }
                }
            }
        }

        // Mausrad wählt die nächste/vorige Karte (Klicks gehen durch an die Karten)
        MouseArea {
            anchors.fill: parent
            enabled: Global.altTabMouse
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                if (wheel.angleDelta.y < 0 || wheel.angleDelta.x < 0) sw.next(); else sw.prev();
            }
        }
    }
}
