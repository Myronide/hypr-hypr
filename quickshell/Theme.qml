pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Draconyx Modern: zentrales Designsystem. Alle Farben, Maße und Bewegungen kommen von hier.
Singleton {
    // ---------- Farben ----------
    // Kommen aus ~/.config/draconyx/colors.json (gemeinsam mit Aurora; ändern mit `dx-colors` oder in den Einstellungen).
    FileView {
        id: colorFile
        path: Quickshell.env("HOME") + "/.config/draconyx/colors.json"
        watchChanges: true
        onFileChanged: reload()
        adapter: JsonAdapter {
            id: pal
            property string bg: "#262a30"
            property string surface: "#30353d"
            property string hover: "#3a414b"
            property string border: "#424a55"
            property string text: "#edf1f7"
            property string muted: "#a6b0be"
            property string accent: "#4d8fe0"
            property string accentBright: "#6ba9ff"
            property string accentDeep: "#397acb"
            property string selected: "#355a86"
            property string iconKey: "edf1f7-4d8fe0"
        }
    }
    function alpha(c, a) { const k = Qt.color(c); return Qt.rgba(k.r, k.g, k.b, a); }

    // Flächen (von tief nach hoch)
    readonly property color bg0:   Qt.darker(Qt.color(pal.bg), 1.4)
    readonly property color bg1:   Qt.color(pal.bg)
    readonly property color bg2:   Qt.color(pal.surface)

    // Flach und deckend wie bei Aurora (kein Verlauf, keine Lichtkante)
    readonly property color panel:       alpha(pal.bg, 0.97)
    readonly property color panelTop:    alpha(pal.bg, 0.97)
    readonly property color panelBottom: alpha(pal.bg, 0.97)
    readonly property color panelStrong: alpha(pal.bg, 0.99)

    readonly property color tile:        Qt.rgba(1, 1, 1, 0.055)
    readonly property color tileHover:   alpha(pal.hover, 1.0)
    readonly property color tilePress:   Qt.rgba(1, 1, 1, 0.07)
    readonly property color accentSoft:  alpha(pal.accent, 0.22)
    readonly property color accentHover: alpha(pal.accent, 0.34)
    readonly property color selected:    alpha(pal.selected, 0.95)     // markierte Zeile / aktive App

    readonly property color border:      alpha(pal.border, 0.9)
    readonly property color borderSoft:  Qt.rgba(1, 1, 1, 0.07)
    readonly property color highlight:   "transparent"

    readonly property color accent:       pal.accent
    readonly property color accentBright: pal.accentBright
    readonly property color accentDeep:   pal.accentDeep
    readonly property color green:        "#6ee05c"
    readonly property color red:          "#ff6b6b"
    readonly property color amber:        "#ffc857"

    readonly property color text:    pal.text
    readonly property color textDim: pal.muted
    readonly property color textOn:  "#ffffff"

    // ---------- Typografie ----------
    // Schriften: Voreinstellungen aus Aurora (dx-fonts). ~/.config/draconyx/font = Oberfläche, font-code = Git-Client und Diffs.
    property string fontFamily: "Inter"
    property string fontCodeFamily: "Monaspace Krypton"
    // Nicht installierte Schrift: auf Inter bzw. die Systemschrift für Festbreite ausweichen (sonst wäre alles Standardschrift)
    readonly property string font: Qt.fontFamilies().indexOf(fontFamily) >= 0 ? fontFamily : "Inter"
    readonly property string fontMono: Qt.fontFamilies().indexOf(fontCodeFamily) >= 0 ? fontCodeFamily : "monospace"
    // Mausrad-Geschwindigkeit (Aurora → Übersicht schreibt ~/.config/draconyx/scroll-speed): 1.0 = Standard
    property real scrollSpeed: 1.0
    FileView {
        path: Quickshell.env("HOME") + "/.config/draconyx/scroll-speed"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const v = parseFloat(text().trim()); if (!isNaN(v) && v > 0.05 && v < 20) scrollSpeed = v; }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/draconyx/font"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const s = text().trim(); if (s !== "") fontFamily = s; }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/draconyx/font-code"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const s = text().trim(); if (s !== "") fontCodeFamily = s; }
    }
    readonly property int fsXs: 11
    readonly property int fsS:  12
    readonly property int fsM:  13
    readonly property int fsL:  15
    readonly property int fsXl: 20
    readonly property int fsDisplay: 34

    // ---------- Maße ----------
    readonly property int rXs: 6
    readonly property int rS:  8
    readonly property int rM:  10
    readonly property int rL:  12
    readonly property int rXl: 14
    readonly property int radius: rL            // Kompatibilität

    readonly property int sp1: 4
    readonly property int sp2: 8
    readonly property int sp3: 12
    readonly property int sp4: 16
    readonly property int sp5: 24

    // ---------- Bewegung ----------
    readonly property int durFast: 120
    readonly property int durBase: 180
    readonly property int durSlow: 280
    readonly property int easeOut: Easing.OutCubic
    readonly property int easeInOut: Easing.InOutCubic

    // ---------- Pfade ----------
    readonly property string home: Quickshell.env("HOME")
    readonly property string iconDir: home + "/.local/share/draconyx-hypr/icons/" + pal.iconKey + "/"
    readonly property string logo: "file://" + home + "/.local/share/draconyx-hypr/logo-start.png"

    function icon(name, accent) {
        return "file://" + iconDir + name + (accent ? "-a" : "") + ".svg";
    }
}
