import QtQuick

// Eine Fläche der Taskleiste. Leistenstil: eine Fläche über die ganze Breite mit den Bereichen links/mitte/rechts.
// Dock-Stil: bis zu drei Inseln (links, Mitte, rechts), jede mit einem Bereich; leere Inseln werden nicht gezeigt.
// Im Modus "Teile einzeln" (Dock + Auto-Hide) fährt jede Insel nur hoch, wenn die Maus bei ihr ist.
Item {
    id: isl
    required property var bar
    property var sections: ["left"]            // Bereiche in dieser Fläche
    property string align: "center"            // Dock: "left" | "center" | "right"; Leiste: "full"

    readonly property bool full: align === "full"
    readonly property var leftItems: sections.indexOf("left") >= 0 ? Global.sectionItems(Global.barStyle, "left") : []
    readonly property var centerItems: sections.indexOf("center") >= 0 ? Global.sectionItems(Global.barStyle, "center") : []
    readonly property var rightItems: sections.indexOf("right") >= 0 ? Global.sectionItems(Global.barStyle, "right") : []
    readonly property var allItems: leftItems.concat(centerItems, rightItems)
    readonly property bool occupied: allItems.length > 0

    property alias zone: zoneItem
    property alias panel: surf

    // ---------- Ein-/Ausfahren ----------
    readonly property bool partMode: bar.partMode
    property bool shownOwn: true
    readonly property bool shownEff: partMode ? shownOwn : bar.shown
    readonly property bool hasSysPart: allItems.indexOf("system") >= 0 || allItems.indexOf("clock") >= 0 || allItems.indexOf("notifications") >= 0
    readonly property bool popupMine: {
        if (!Global.popupOpenOn(bar.mon)) return false;
        const sys = Global.sysPopupOn(bar.mon);
        return sys ? hasSysPart : !hasSysPart || allItems.indexOf("start") >= 0 || allItems.indexOf("code") >= 0 || allItems.indexOf("wallpaper") >= 0;
    }
    readonly property bool keepOwn: !partMode ? true : (!bar.autohideHere || popupMine || hover.hovered)
    onKeepOwnChanged: { if (keepOwn) { hideOwn.stop(); shownOwn = true; } else hideOwn.restart(); }
    Timer { id: hideOwn; interval: 700; onTriggered: if (!isl.keepOwn) isl.shownOwn = false }
    Component.onCompleted: if (partMode && !keepOwn) hideOwn.restart()

    // ---------- Eingabezone (voll, solange sichtbar; sonst ein 3-px-Streifen am Rand) ----------
    Item {
        id: zoneItem
        x: surf.x
        width: isl.occupied ? surf.width : 0
        height: isl.shownEff ? isl.height : 3
        y: Global.barTop ? 0 : isl.height - height
        HoverHandler { id: hover }
    }

    // ---------- Fläche ----------
    Surface {
        id: surf
        visible: isl.occupied
        level: 1
        opacityScale: Global.barOpacity / 0.90
        radius: Theme.rL
        height: Global.barHeight
        width: isl.full ? isl.width - 2 * Global.barMargin : Math.min(isl.width - 2 * Global.barMargin, row1.width + 16)
        x: isl.full ? Global.barMargin
         : isl.align === "left" ? Global.barMargin
         : isl.align === "right" ? isl.width - width - Global.barMargin
         : Math.round((isl.width - width) / 2)
        Behavior on width { enabled: !isl.full; NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
        Behavior on x { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }

        readonly property real shownY: Global.barTop ? bar.gap : isl.height - height - bar.gap
        readonly property real hiddenY: Global.barTop ? -height - 12 : isl.height + 12
        y: isl.shownEff ? shownY : hiddenY
        opacity: isl.shownEff ? 1 : 0
        Behavior on y       { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeOut } }
        Behavior on opacity { NumberAnimation { duration: Theme.durBase } }

        // Inselstil: ein Bereich, mittig in der Fläche
        Row {
            id: row1
            visible: !isl.full
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: isl.full ? [] : (isl.sections[0] === "left" ? isl.leftItems : isl.sections[0] === "center" ? isl.centerItems : isl.rightItems)
                delegate: Loader {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    source: "BarItem" + modelData.charAt(0).toUpperCase() + modelData.slice(1) + ".qml"
                    onLoaded: item.bar = isl.bar
                }
            }
        }

        // Leistenstil: links / mitte / rechts
        Row {
            id: rowLeft
            visible: isl.full
            anchors.left: parent.left; anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: isl.full ? isl.leftItems : []
                delegate: Loader {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    source: "BarItem" + modelData.charAt(0).toUpperCase() + modelData.slice(1) + ".qml"
                    onLoaded: item.bar = isl.bar
                }
            }
        }
        Row {
            id: rowCenter
            visible: isl.full
            x: Math.round((parent.width - width) / 2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Behavior on x { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeOut } }
            Repeater {
                model: isl.full ? isl.centerItems : []
                delegate: Loader {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    source: "BarItem" + modelData.charAt(0).toUpperCase() + modelData.slice(1) + ".qml"
                    onLoaded: item.bar = isl.bar
                }
            }
        }
        Row {
            id: rowRight
            visible: isl.full
            anchors.right: parent.right; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: isl.full ? isl.rightItems : []
                delegate: Loader {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    source: "BarItem" + modelData.charAt(0).toUpperCase() + modelData.slice(1) + ".qml"
                    onLoaded: item.bar = isl.bar
                }
            }
        }
    }
}
