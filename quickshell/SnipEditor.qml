import QtQuick
import Quickshell
import Quickshell.Wayland

// Foto-Editor für Snips: Stift, Marker, Pfeil, Rechteck, Ellipse, Text, Verpixeln; Rückgängig; Kopieren / Speichern / Beides.
// Zeichnet in Bildpixeln (voller Auflösung) auf einer Fläche in Bildgröße, die nur verkleinert angezeigt wird – der Export
// (grabToImage der Fläche) ist deshalb scharf.
PanelWindow {
    id: ed
    visible: Global.editOpen
    screen: Global.screenByName(Global.popupScreen)
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "#b3000000"
    WlrLayershell.namespace: "draconyx-snip-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // ---------- Zustand ----------
    property string tool: "pen"                 // pen | marker | arrow | rect | ellipse | text | pixel
    property color strokeColor: "#ff4d4d"
    property real strokeWidth: 5
    property var shapes: []
    property var current: null
    property string status: ""
    readonly property real imgW: Math.max(1, photo.sourceSize.width)
    readonly property real imgH: Math.max(1, photo.sourceSize.height)
    readonly property real maxW: width - 120
    readonly property real maxH: height - 220
    readonly property real fit: Math.min(1, maxW / imgW, maxH / imgH)

    onVisibleChanged: if (visible) { shapes = []; current = null; status = ""; tool = "pen"; input.visible = false; root.forceActiveFocus(); cv.requestPaint(); }

    // nur zum Testen: ein paar Formen setzen
    function demo() {
        shapes = [
            { type: "rect", color: "#ff4d4d", w: 6, x1: imgW * 0.1, y1: imgH * 0.15, x2: imgW * 0.45, y2: imgH * 0.5 },
            { type: "arrow", color: "#ffc857", w: 8, x1: imgW * 0.7, y1: imgH * 0.2, x2: imgW * 0.5, y2: imgH * 0.35 },
            { type: "text", color: "#ffffff", w: 6, text: "Test", x1: imgW * 0.55, y1: imgH * 0.6 },
            { type: "pixel", color: "#000000", w: 6, x1: imgW * 0.1, y1: imgH * 0.6, x2: imgW * 0.35, y2: imgH * 0.85 }
        ];
        cv.requestPaint();
    }
    function undo() { if (shapes.length > 0) { const s = shapes.slice(); s.pop(); shapes = s; cv.requestPaint(); } }
    function close() { Global.editOpen = false; }

    // Fertiges Bild (Foto + Zeichnung) rendern und an das Skript übergeben
    function deliver(mode) {
        const out = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/draconyx-snip-final.png";
        stage.grabToImage(function (res) {
            if (!res.saveToFile(out)) { ed.status = "Konnte das Bild nicht erzeugen"; return; }
            Quickshell.execDetached([Theme.home + "/.local/bin/dx-snip-crop", "--deliver", out, mode]);
            ed.status = mode === "copy" ? "Kopiert" : mode === "save" ? "Gespeichert" : "Kopiert und gespeichert";
            closeTimer.restart();
        }, Qt.size(imgW, imgH));
    }
    Timer { id: closeTimer; interval: 700; onTriggered: ed.close() }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ed.close()
        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) { ed.undo(); event.accepted = true; }
            else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) { ed.deliver("copy"); event.accepted = true; }
            else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) { ed.deliver("save"); event.accepted = true; }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }   // Klicks neben dem Editor nicht durchlassen

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: Math.max(560, view.width + 40)
            height: view.height + 150
            radius: 22
            color: Theme.panelStrong
            border.color: Theme.border

            // ---------- Werkzeugleiste ----------
            Row {
                id: tools
                anchors.top: parent.top; anchors.topMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: [{ k: "pen", t: "Stift" }, { k: "marker", t: "Marker" }, { k: "arrow", t: "Pfeil" }, { k: "rect", t: "Rechteck" },
                            { k: "ellipse", t: "Ellipse" }, { k: "text", t: "Text" }, { k: "pixel", t: "Verpixeln" }]
                    BarButton {
                        required property var modelData
                        implicitHeight: 32; padding: 12; radiusSize: 16
                        active: ed.tool === modelData.k
                        color: ed.tool === modelData.k ? Theme.accent : (hovered ? Theme.tileHover : Theme.tile)
                        Text { text: modelData.t; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsS }
                        onClicked: { ed.tool = modelData.k; input.visible = false; }
                    }
                }
                Rectangle { width: 1; height: 24; color: Theme.borderSoft; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: ["#ff4d4d", "#ffc857", "#6ee05c", "#4d8fe0", "#ffffff", "#111111"]
                    Rectangle {
                        required property string modelData
                        width: 26; height: 26; radius: 13; color: modelData
                        anchors.verticalCenter: parent.verticalCenter
                        border.width: ed.strokeColor.toString() === Qt.color(modelData).toString() ? 3 : 1
                        border.color: ed.strokeColor.toString() === Qt.color(modelData).toString() ? Theme.accentBright : Theme.borderSoft
                        MouseArea { anchors.fill: parent; onClicked: ed.strokeColor = parent.modelData }
                    }
                }
                Rectangle { width: 1; height: 24; color: Theme.borderSoft; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: [{ w: 3, t: "S" }, { w: 6, t: "M" }, { w: 12, t: "L" }]
                    BarButton {
                        required property var modelData
                        minWidth: 32; implicitHeight: 32; radiusSize: 16
                        active: ed.strokeWidth === modelData.w
                        color: ed.strokeWidth === modelData.w ? Theme.accentSoft : (hovered ? Theme.tileHover : Theme.tile)
                        Text { text: modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
                        onClicked: ed.strokeWidth = modelData.w
                    }
                }
                BarButton {
                    implicitHeight: 32; padding: 12; radiusSize: 16
                    color: hovered ? Theme.tileHover : Theme.tile
                    Text { text: "↶ Rückgängig"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                    onClicked: ed.undo()
                }
            }

            // ---------- Bildfläche ----------
            Item {
                id: view
                anchors.top: tools.bottom; anchors.topMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(ed.imgW * ed.fit); height: Math.round(ed.imgH * ed.fit)
                clip: true

                // Fläche in Bildgröße (wird nur verkleinert gezeigt; der Export nimmt sie unverkleinert)
                Item {
                    id: stage
                    width: ed.imgW; height: ed.imgH
                    scale: ed.fit
                    transformOrigin: Item.TopLeft

                    Image {
                        id: photo
                        anchors.fill: parent
                        source: Global.editOpen && Global.editFile !== "" ? "file://" + Global.editFile : ""
                        cache: false
                        smooth: true
                        onStatusChanged: if (status === Image.Ready) { srcCv.requestPaint(); cv.requestPaint(); }
                    }
                    // unsichtbare Kopie des Fotos zum Auslesen von Farben (Verpixeln)
                    Canvas {
                        id: srcCv
                        visible: false
                        width: ed.imgW; height: ed.imgH
                        onPaint: { const c = getContext("2d"); c.drawImage(photo, 0, 0); }
                    }
                    Canvas {
                        id: cv
                        anchors.fill: parent
                        onPaint: {
                            const c = getContext("2d");
                            c.clearRect(0, 0, width, height);
                            for (const s of ed.shapes) ed.drawShape(c, s);
                            if (ed.current) ed.drawShape(c, ed.current);
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    onPressed: mouse => {
                        const x = mouse.x / ed.fit, y = mouse.y / ed.fit;
                        if (ed.tool === "text") {
                            input.x = mouse.x; input.y = mouse.y; input.text = ""; input.visible = true; input.forceActiveFocus(); input.at = Qt.point(x, y);
                            return;
                        }
                        ed.current = { type: ed.tool, color: ed.strokeColor.toString(), w: ed.strokeWidth, pts: [Qt.point(x, y)], x1: x, y1: y, x2: x, y2: y };
                        cv.requestPaint();
                    }
                    onPositionChanged: mouse => {
                        if (!ed.current) return;
                        const x = Math.max(0, Math.min(ed.imgW, mouse.x / ed.fit)), y = Math.max(0, Math.min(ed.imgH, mouse.y / ed.fit));
                        const c = ed.current;
                        if (c.type === "pen" || c.type === "marker") c.pts.push(Qt.point(x, y));
                        c.x2 = x; c.y2 = y;
                        cv.requestPaint();
                    }
                    onReleased: {
                        if (!ed.current) return;
                        const s = ed.shapes.slice(); s.push(ed.current); ed.shapes = s; ed.current = null; cv.requestPaint();
                    }
                }

                // Texteingabe
                Rectangle {
                    id: input
                    property alias text: field.text
                    property point at: Qt.point(0, 0)
                    visible: false
                    width: Math.max(160, field.implicitWidth + 24); height: 34; radius: 8
                    color: Theme.panelStrong; border.color: Theme.accent
                    function commit() {
                        if (field.text.trim() !== "") {
                            const s = ed.shapes.slice();
                            s.push({ type: "text", color: ed.strokeColor.toString(), w: ed.strokeWidth, text: field.text, x1: at.x, y1: at.y });
                            ed.shapes = s; cv.requestPaint();
                        }
                        visible = false;
                    }
                    TextInput {
                        id: field
                        anchors.fill: parent; anchors.margins: 8
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                        onAccepted: input.commit()
                        Keys.onEscapePressed: input.visible = false
                    }
                }
            }

            // ---------- Aktionen ----------
            Row {
                anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                BarButton { implicitHeight: 38; padding: 18; radiusSize: 19; color: hovered ? Theme.accentBright : Theme.accent
                    Text { text: "Kopieren"; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsM; font.weight: Font.DemiBold }
                    onClicked: ed.deliver("copy") }
                BarButton { implicitHeight: 38; padding: 18; radiusSize: 19; color: hovered ? Theme.tileHover : Theme.tile
                    Text { text: "Speichern"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM }
                    onClicked: ed.deliver("save") }
                BarButton { implicitHeight: 38; padding: 18; radiusSize: 19; color: hovered ? Theme.tileHover : Theme.tile
                    Text { text: "Beides"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM }
                    onClicked: ed.deliver("both") }
                BarButton { implicitHeight: 38; padding: 18; radiusSize: 19; color: hovered ? Qt.rgba(1, 0.42, 0.42, 0.3) : Theme.tile
                    Text { text: "Verwerfen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsM }
                    onClicked: ed.close() }
                Text { visible: ed.status !== ""; anchors.verticalCenter: parent.verticalCenter; text: ed.status; color: Theme.accentBright; font.family: Theme.font; font.pixelSize: Theme.fsS }
            }
        }
    }

    // ---------- Zeichnen einer Form (Koordinaten in Bildpixeln) ----------
    function drawShape(c, s) {
        c.save();
        c.strokeStyle = s.color; c.fillStyle = s.color;
        c.lineCap = "round"; c.lineJoin = "round";
        const w = s.w;
        if (s.type === "pen" || s.type === "marker") {
            c.lineWidth = s.type === "marker" ? w * 3.2 : w;
            if (s.type === "marker") c.globalAlpha = 0.38;
            c.beginPath();
            c.moveTo(s.pts[0].x, s.pts[0].y);
            for (let i = 1; i < s.pts.length; i++) c.lineTo(s.pts[i].x, s.pts[i].y);
            if (s.pts.length === 1) c.lineTo(s.pts[0].x + 0.1, s.pts[0].y);
            c.stroke();
        } else if (s.type === "rect") {
            c.lineWidth = w; c.strokeRect(Math.min(s.x1, s.x2), Math.min(s.y1, s.y2), Math.abs(s.x2 - s.x1), Math.abs(s.y2 - s.y1));
        } else if (s.type === "ellipse") {
            c.lineWidth = w; c.beginPath();
            c.ellipse(Math.min(s.x1, s.x2), Math.min(s.y1, s.y2), Math.abs(s.x2 - s.x1), Math.abs(s.y2 - s.y1));
            c.stroke();
        } else if (s.type === "arrow") {
            c.lineWidth = w;
            const ang = Math.atan2(s.y2 - s.y1, s.x2 - s.x1), head = Math.max(14, w * 4);
            c.beginPath(); c.moveTo(s.x1, s.y1); c.lineTo(s.x2, s.y2); c.stroke();
            c.beginPath();
            c.moveTo(s.x2, s.y2);
            c.lineTo(s.x2 - head * Math.cos(ang - 0.45), s.y2 - head * Math.sin(ang - 0.45));
            c.lineTo(s.x2 - head * Math.cos(ang + 0.45), s.y2 - head * Math.sin(ang + 0.45));
            c.closePath(); c.fill();
        } else if (s.type === "text") {
            const px = Math.max(16, w * 5);
            c.font = "bold " + px + "px Inter, sans-serif";
            c.textBaseline = "top";
            c.fillText(s.text, s.x1, s.y1);
        } else if (s.type === "pixel") {
            // Mosaik: Farbe in der Blockmitte des Fotos übernehmen
            const x0 = Math.max(0, Math.round(Math.min(s.x1, s.x2))), y0 = Math.max(0, Math.round(Math.min(s.y1, s.y2)));
            const x1 = Math.min(ed.imgW, Math.round(Math.max(s.x1, s.x2))), y1 = Math.min(ed.imgH, Math.round(Math.max(s.y1, s.y2)));
            const b = Math.max(8, Math.round(Math.max(ed.imgW, ed.imgH) / 90));
            const sc = srcCv.getContext("2d");
            for (let y = y0; y < y1; y += b) for (let x = x0; x < x1; x += b) {
                const d = sc.getImageData(Math.min(ed.imgW - 1, x + b / 2), Math.min(ed.imgH - 1, y + b / 2), 1, 1).data;
                c.fillStyle = "rgb(" + d[0] + "," + d[1] + "," + d[2] + ")";
                c.fillRect(x, y, Math.min(b, x1 - x), Math.min(b, y1 - y));
            }
        }
        c.restore();
    }
}
