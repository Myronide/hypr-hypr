import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire

// Verbindungen: Netzwerk (WLAN, Ethernet), Bluetooth und Audio (Geräte, Lautstärke je Programm) in einem Fenster
PanelWindow {
    id: cn
    visible: Global.connOpen
    screen: Global.screenByName(Global.popupScreen)
    anchors.bottom: !Global.barTop
    anchors.top: Global.barTop
    anchors.right: true
    margins.bottom: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.top: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.right: Global.popupRightMargin()
    implicitWidth: 460
    implicitHeight: 640
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "draconyx-conn"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    HyprlandFocusGrab { id: grab; windows: [cn]; active: cn.visible; onCleared: if (!Global.snipBusy) Global.connOpen = false }

    // ---------- Daten ----------
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var wifiDevices: {
        const out = [];
        for (const d of (Networking.devices ? Networking.devices.values : [])) if (d.type === DeviceType.Wifi) out.push(d);
        return out;
    }
    readonly property var wiredDevices: {
        const out = [];
        for (const d of (Networking.devices ? Networking.devices.values : [])) if (d.type === DeviceType.Wired) out.push(d);
        return out;
    }
    readonly property var wifiNets: {
        const list = [];
        for (const d of wifiDevices) for (const n of (d.networks ? d.networks.values : [])) list.push(n);
        list.sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength));
        return list;
    }
    readonly property var btDevices: {
        const list = adapter && adapter.devices ? adapter.devices.values.slice() : [];
        list.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || String(a.name || "").localeCompare(String(b.name || "")));
        return list;
    }
    readonly property var allNodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var sinks: allNodes.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: allNodes.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var streams: allNodes.filter(n => n.audio && n.isSink && n.isStream)
    PwObjectTracker { objects: cn.allNodes }

    // Suchlauf nur solange das Fenster offen ist (spart Strom)
    onVisibleChanged: {
        for (const d of wifiDevices) d.scannerEnabled = visible && Global.connTab === "net";
        if (adapter && !visible) adapter.discovering = false;
        pwTarget = ""; 
    }
    Connections { target: Global; function onConnTabChanged() {
        for (const d of cn.wifiDevices) d.scannerEnabled = cn.visible && Global.connTab === "net";
        if (cn.adapter) cn.adapter.discovering = cn.visible && Global.connTab === "bt";
    } }
    property string pwTarget: ""                 // Netzwerk, für das gerade ein Passwort eingegeben wird
    property string pwError: ""

    function signalIcon(s) { return "wifi"; }
    function secText(n) { return n.security === WifiSecurityType.Open ? "offen" : "geschützt"; }
    function nodeName(n) {
        const p = n.properties || {};
        return p["application.name"] || n.nickname || n.description || n.name;
    }

    // ---------- Aussehen ----------
    PopCard {
        anchors.fill: parent
        radius: 22
        color: Theme.panelStrong
        border.color: Theme.border

        Item {
            id: head
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 64
            Text { text: "Verbindungen"; anchors.left: parent.left; anchors.leftMargin: 22; anchors.verticalCenter: parent.verticalCenter
                   color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: [{ k: "net", t: "Netzwerk", i: "wifi" }, { k: "bt", t: "Bluetooth", i: "bt" }, { k: "audio", t: "Audio", i: "vol" }]
                    BarButton {
                        required property var modelData
                        implicitHeight: 34; padding: 12; radiusSize: 17
                        active: Global.connTab === modelData.k
                        color: active ? Theme.accent : (hovered ? Theme.tileHover : Theme.tile)
                        Row { spacing: 6
                            Icon { name: modelData.i; size: 15; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.t; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        }
                        onClicked: Global.connTab = modelData.k
                    }
                }
            }
        }

        // ============ NETZWERK ============
        Flickable {
            visible: Global.connTab === "net"
            anchors.top: head.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 16; anchors.topMargin: 4
            contentHeight: netCol.implicitHeight + 8
            clip: true; boundsBehavior: Flickable.StopAtBounds
            ScrollSpeed { }
            Column {
                id: netCol
                width: parent.width
                spacing: 8

                // WLAN-Schalter
                Rectangle {
                    width: parent.width; height: 58; radius: 14; color: Theme.tile; border.color: Theme.borderSoft
                    Icon { name: "wifi"; size: 20; accent: Networking.wifiEnabled; anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter }
                    Column { anchors.left: parent.left; anchors.leftMargin: 52; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "WLAN"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                        Text { text: { const c = cn.wifiNets.find(n => n.connected); return !Networking.wifiEnabled ? "ausgeschaltet" : (c ? "verbunden mit " + c.name : "nicht verbunden"); }
                               color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 46; height: 26; radius: 13; color: Networking.wifiEnabled ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle { width: 20; height: 20; radius: 10; color: "white"; anchors.verticalCenter: parent.verticalCenter
                                    x: Networking.wifiEnabled ? parent.width - width - 3 : 3; Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } }
                        MouseArea { anchors.fill: parent; onClicked: Networking.wifiEnabled = !Networking.wifiEnabled }
                    }
                }

                // Ethernet
                Repeater {
                    model: cn.wiredDevices
                    Rectangle {
                        required property var modelData
                        width: netCol.width; height: 58; radius: 14; color: Theme.tile; border.color: Theme.borderSoft
                        Icon { name: "ethernet"; size: 20; accent: modelData.connected; anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter }
                        Column { anchors.left: parent.left; anchors.leftMargin: 52; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text { text: "Ethernet"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                            Text { text: modelData.connected ? "verbunden" + (modelData.linkSpeed > 0 ? " · " + modelData.linkSpeed + " Mbit/s" : "") : (modelData.hasLink ? "Kabel steckt, nicht verbunden" : "kein Kabel")
                                   color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                        }
                    }
                }

                Text { text: "VERFÜGBARE NETZWERKE"; visible: Networking.wifiEnabled; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.4; topPadding: 8 }
                Text { visible: Networking.wifiEnabled && cn.wifiNets.length === 0; text: "Suche …"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsS }

                Repeater {
                    model: Networking.wifiEnabled ? cn.wifiNets : []
                    Rectangle {
                        id: nrow
                        required property var modelData
                        readonly property bool asking: cn.pwTarget === modelData.name
                        width: netCol.width; height: asking ? 118 : 56; radius: 14
                        color: nArea.containsMouse ? Theme.tileHover : (modelData.connected ? Theme.accentSoft : Theme.tile)
                        border.color: modelData.connected ? Theme.accent : Theme.borderSoft
                        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                        clip: true
                        Icon { name: "wifi"; size: 18; accent: nrow.modelData.connected; opacity: 0.45 + 0.55 * nrow.modelData.signalStrength
                               anchors.left: parent.left; anchors.leftMargin: 16; y: 19 }
                        Column { x: 50; y: 9; width: parent.width - 150; spacing: 2
                            Text { text: nrow.modelData.name; width: parent.width; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                            Text { text: (nrow.modelData.connected ? "verbunden · " : (nrow.modelData.known ? "gespeichert · " : "")) + cn.secText(nrow.modelData) + " · " + Math.round(nrow.modelData.signalStrength * 100) + " %"
                                   color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                        }
                        MouseArea { id: nArea; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 56; hoverEnabled: true
                            onClicked: {
                                if (nrow.modelData.connected) nrow.modelData.disconnect();
                                else if (nrow.modelData.known || nrow.modelData.security === WifiSecurityType.Open) nrow.modelData.connect();
                                else { cn.pwTarget = nrow.modelData.name; cn.pwError = ""; pw.text = ""; pw.forceActiveFocus(); }
                            } }
                        BarButton { visible: nrow.modelData.known && !nrow.asking; anchors.right: parent.right; anchors.rightMargin: 10; y: 11
                            implicitHeight: 32; padding: 10; radiusSize: 16; color: hovered ? Qt.rgba(1, 0.42, 0.42, 0.3) : Theme.tile
                            Text { text: "Vergessen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                            onClicked: nrow.modelData.forget() }
                        // Passwortfeld
                        Row { visible: nrow.asking; x: 16; y: 62; spacing: 8; width: parent.width - 32
                            Rectangle { width: parent.width - 108; height: 38; radius: 19; color: Theme.panelStrong; border.color: pw.activeFocus ? Theme.accent : Theme.borderSoft
                                TextInput { id: pw; anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; clip: true
                                    onAccepted: { nrow.modelData.connectWithPsk(text); cn.pwTarget = ""; }
                                    Keys.onEscapePressed: cn.pwTarget = ""
                                    Text { visible: pw.text === ""; text: "Passwort"; color: Theme.textDim; font: pw.font } } }
                            BarButton { implicitHeight: 38; padding: 16; radiusSize: 19; color: hovered ? Theme.accentBright : Theme.accent
                                Text { text: "Verbinden"; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
                                onClicked: { nrow.modelData.connectWithPsk(pw.text); cn.pwTarget = ""; } }
                        }
                    }
                }
                Item { width: 1; height: 8 }
            }
        }

        // ============ BLUETOOTH ============
        Flickable {
            visible: Global.connTab === "bt"
            anchors.top: head.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 16; anchors.topMargin: 4
            contentHeight: btCol.implicitHeight + 8
            clip: true; boundsBehavior: Flickable.StopAtBounds
            ScrollSpeed { }
            Column {
                id: btCol
                width: parent.width
                spacing: 8
                Rectangle {
                    width: parent.width; height: 58; radius: 14; color: Theme.tile; border.color: Theme.borderSoft
                    Icon { name: "bt"; size: 20; accent: !!cn.adapter && cn.adapter.enabled; anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter }
                    Column { anchors.left: parent.left; anchors.leftMargin: 52; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "Bluetooth"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                        Text { text: !cn.adapter ? "kein Adapter gefunden" : (!cn.adapter.enabled ? "ausgeschaltet" : (cn.adapter.discovering ? "sucht nach Geräten …" : "bereit"))
                               color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                    }
                    Rectangle {
                        visible: !!cn.adapter
                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 46; height: 26; radius: 13; color: cn.adapter && cn.adapter.enabled ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle { width: 20; height: 20; radius: 10; color: "white"; anchors.verticalCenter: parent.verticalCenter
                                    x: cn.adapter && cn.adapter.enabled ? parent.width - width - 3 : 3; Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } }
                        MouseArea { anchors.fill: parent; onClicked: { if (cn.adapter) { cn.adapter.enabled = !cn.adapter.enabled; if (cn.adapter.enabled) cn.adapter.discovering = true; } } }
                    }
                }
                Row { visible: !!cn.adapter && cn.adapter.enabled; spacing: 8
                    BarButton { implicitHeight: 34; padding: 14; radiusSize: 17; active: !!cn.adapter && cn.adapter.discovering
                        Text { text: cn.adapter && cn.adapter.discovering ? "Suche läuft – stoppen" : "Nach Geräten suchen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                        onClicked: cn.adapter.discovering = !cn.adapter.discovering }
                }
                Text { text: "GERÄTE"; visible: cn.btDevices.length > 0; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.4; topPadding: 8 }
                Repeater {
                    model: cn.adapter && cn.adapter.enabled ? cn.btDevices : []
                    Rectangle {
                        id: brow
                        required property var modelData
                        width: btCol.width; height: 58; radius: 14
                        color: bArea.containsMouse ? Theme.tileHover : (modelData.connected ? Theme.accentSoft : Theme.tile)
                        border.color: modelData.connected ? Theme.accent : Theme.borderSoft
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Icon { name: "bt"; size: 18; accent: brow.modelData.connected; anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter }
                        Column { x: 50; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 170; spacing: 2
                            Text { text: brow.modelData.name || brow.modelData.address; width: parent.width; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                            Text { text: (brow.modelData.connected ? "verbunden" : (brow.modelData.paired ? "gekoppelt" : "neu")) + (brow.modelData.batteryAvailable ? " · Akku " + Math.round(brow.modelData.battery * 100) + " %" : "")
                                   color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                        }
                        MouseArea { id: bArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                if (brow.modelData.connected) brow.modelData.disconnect();
                                else if (brow.modelData.paired) brow.modelData.connect();
                                else brow.modelData.pair();
                            } }
                        BarButton { visible: brow.modelData.paired; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 32; padding: 10; radiusSize: 16; color: hovered ? Qt.rgba(1, 0.42, 0.42, 0.3) : Theme.tile
                            Text { text: "Entfernen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                            onClicked: brow.modelData.forget() }
                    }
                }
                Item { width: 1; height: 8 }
            }
        }

        // ============ AUDIO ============
        Flickable {
            visible: Global.connTab === "audio"
            anchors.top: head.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 16; anchors.topMargin: 4
            contentHeight: auCol.implicitHeight + 8
            clip: true; boundsBehavior: Flickable.StopAtBounds
            ScrollSpeed { }
            Column {
                id: auCol
                width: parent.width
                spacing: 8
                Text { text: "AUSGABE"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.4 }
                Repeater {
                    model: cn.sinks
                    Rectangle {
                        id: srow
                        required property var modelData
                        readonly property bool isDef: Pipewire.defaultAudioSink === modelData
                        width: auCol.width; height: isDef ? 100 : 54; radius: 14
                        color: sArea.containsMouse ? Theme.tileHover : (isDef ? Theme.accentSoft : Theme.tile)
                        border.color: isDef ? Theme.accent : Theme.borderSoft
                        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        clip: true
                        Icon { name: srow.isDef ? "vol" : "vol-low"; size: 18; accent: srow.isDef; anchors.left: parent.left; anchors.leftMargin: 16; y: 18 }
                        Text { x: 50; y: 10; width: parent.width - 120; text: srow.modelData.description || srow.modelData.nickname || srow.modelData.name; elide: Text.ElideRight
                               color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold; height: 34; verticalAlignment: Text.AlignVCenter }
                        Text { visible: srow.isDef; anchors.right: parent.right; anchors.rightMargin: 16; y: 18; text: "Standard"; color: Theme.accentBright; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                        MouseArea { id: sArea; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 54; hoverEnabled: true
                            onClicked: Pipewire.preferredDefaultAudioSink = srow.modelData }
                        SliderRow { visible: srow.isDef; x: 8; y: 52; width: parent.width - 16
                            iconName: srow.modelData.audio && srow.modelData.audio.muted ? "vol-mute" : "vol"
                            value: srow.modelData.audio ? srow.modelData.audio.volume : 0
                            onMoved: v => { if (srow.modelData.audio) srow.modelData.audio.volume = v; }
                            onIconClicked: { if (srow.modelData.audio) srow.modelData.audio.muted = !srow.modelData.audio.muted; } }
                    }
                }
                Text { text: "EINGABE"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.4; topPadding: 8 }
                Repeater {
                    model: cn.sources
                    Rectangle {
                        id: mrow
                        required property var modelData
                        readonly property bool isDef: Pipewire.defaultAudioSource === modelData
                        width: auCol.width; height: isDef ? 100 : 54; radius: 14
                        color: mArea.containsMouse ? Theme.tileHover : (isDef ? Theme.accentSoft : Theme.tile)
                        border.color: isDef ? Theme.accent : Theme.borderSoft
                        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        clip: true
                        Icon { name: "mic"; size: 18; accent: mrow.isDef; anchors.left: parent.left; anchors.leftMargin: 16; y: 18 }
                        Text { x: 50; y: 10; width: parent.width - 120; text: mrow.modelData.description || mrow.modelData.nickname || mrow.modelData.name; elide: Text.ElideRight
                               color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold; height: 34; verticalAlignment: Text.AlignVCenter }
                        Text { visible: mrow.isDef; anchors.right: parent.right; anchors.rightMargin: 16; y: 18; text: "Standard"; color: Theme.accentBright; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                        MouseArea { id: mArea; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 54; hoverEnabled: true
                            onClicked: Pipewire.preferredDefaultAudioSource = mrow.modelData }
                        SliderRow { visible: mrow.isDef; x: 8; y: 52; width: parent.width - 16
                            iconName: mrow.modelData.audio && mrow.modelData.audio.muted ? "mic-off" : "mic"
                            value: mrow.modelData.audio ? mrow.modelData.audio.volume : 0
                            onMoved: v => { if (mrow.modelData.audio) mrow.modelData.audio.volume = v; }
                            onIconClicked: { if (mrow.modelData.audio) mrow.modelData.audio.muted = !mrow.modelData.audio.muted; } }
                    }
                }
                Text { text: "PROGRAMME"; visible: cn.streams.length > 0; color: Theme.textDim; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.4; topPadding: 8 }
                Repeater {
                    model: cn.streams
                    Rectangle {
                        id: prow
                        required property var modelData
                        width: auCol.width; height: 74; radius: 14; color: Theme.tile; border.color: Theme.borderSoft
                        Text { x: 16; y: 8; width: parent.width - 32; text: cn.nodeName(prow.modelData); elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                        SliderRow { x: 8; y: 30; width: parent.width - 16
                            iconName: prow.modelData.audio && prow.modelData.audio.muted ? "vol-mute" : "vol"
                            value: prow.modelData.audio ? prow.modelData.audio.volume : 0
                            onMoved: v => { if (prow.modelData.audio) prow.modelData.audio.volume = v; }
                            onIconClicked: { if (prow.modelData.audio) prow.modelData.audio.muted = !prow.modelData.audio.muted; } }
                    }
                }
                Item { width: 1; height: 8 }
            }
        }
    }
}
