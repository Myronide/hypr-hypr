pragma Singleton
import QtQuick
import Quickshell

// Draconyx Modern: zentrales Designsystem. Alle Farben, Maße und Bewegungen kommen von hier.
Singleton {
    // ---------- Farben ----------
    // Flächen (von tief nach hoch)
    readonly property color bg0:   "#07060d"
    readonly property color bg1:   "#0d0b17"
    readonly property color bg2:   "#14112a"

    readonly property color panel:       Qt.rgba(0.045, 0.040, 0.078, 0.86)
    readonly property color panelTop:    Qt.rgba(0.075, 0.065, 0.125, 0.90)   // Verlauf oben
    readonly property color panelBottom: Qt.rgba(0.035, 0.030, 0.062, 0.92)   // Verlauf unten
    readonly property color panelStrong: Qt.rgba(0.050, 0.045, 0.090, 0.95)

    readonly property color tile:        Qt.rgba(1, 1, 1, 0.055)
    readonly property color tileHover:   Qt.rgba(1, 1, 1, 0.10)
    readonly property color tilePress:   Qt.rgba(1, 1, 1, 0.07)
    readonly property color accentSoft:  Qt.rgba(0.545, 0.361, 0.965, 0.18)
    readonly property color accentHover: Qt.rgba(0.545, 0.361, 0.965, 0.28)

    readonly property color border:      Qt.rgba(0.545, 0.361, 0.965, 0.20)
    readonly property color borderSoft:  Qt.rgba(1, 1, 1, 0.07)
    readonly property color highlight:   Qt.rgba(1, 1, 1, 0.10)               // feine Oberkante

    readonly property color accent:       "#8b5cf6"
    readonly property color accentBright: "#a78bfa"
    readonly property color accentDeep:   "#5b3fd0"
    readonly property color green:        "#6ee05c"   // Signature-Akzent, sehr sparsam
    readonly property color red:          "#ff6b6b"
    readonly property color amber:        "#ffc857"

    readonly property color text:    "#ece9f7"
    readonly property color textDim: "#9a95b8"
    readonly property color textOn:  "#ffffff"

    // ---------- Typografie ----------
    readonly property string font: "Inter"
    readonly property int fsXs: 11
    readonly property int fsS:  12
    readonly property int fsM:  13
    readonly property int fsL:  15
    readonly property int fsXl: 20
    readonly property int fsDisplay: 34

    // ---------- Maße ----------
    readonly property int rXs: 6
    readonly property int rS:  8
    readonly property int rM:  12
    readonly property int rL:  16
    readonly property int rXl: 22
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
    readonly property string iconDir: home + "/.local/share/draconyx-hypr/qs-icons/"
    readonly property string logo: "file://" + home + "/.local/share/draconyx-hypr/logo-start.png"

    function icon(name, accent) {
        return "file://" + iconDir + name + (accent ? "-a" : "") + ".svg";
    }
}
