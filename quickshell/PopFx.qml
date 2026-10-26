import QtQuick

// Öffnen-Animation für eine Fläche (card): einblenden, minimal wachsen, ein Stück von der Leiste weg gleiten.
// Wirkt nur, solange Global.motion > 0 und on = true.
Item {
    id: fx
    required property Item card
    property bool on: true
    property real appear: 1
    readonly property bool active: on && Global.motion > 0

    Binding { target: fx.card; property: "opacity"; value: fx.appear; when: fx.active }
    Binding { target: fx.card; property: "scale"; value: 0.965 + 0.035 * fx.appear; when: fx.active }
    Binding { target: fx.card; property: "transformOrigin"; value: Global.barTop ? Item.Top : Item.Bottom; when: fx.active }
    Translate { id: tr; y: fx.active ? (1 - fx.appear) * (Global.barTop ? -10 : 10) : 0 }
    Component.onCompleted: card.transform = [tr]

    NumberAnimation { id: anim; target: fx; property: "appear"; from: 0; to: 1; duration: Math.round(Theme.durSlow * Global.motion); easing.type: Easing.OutCubic }
    function play() { if (!active) return; anim.stop(); appear = 0; anim.start(); }
    Connections {
        target: fx.card.Window.window
        ignoreUnknownSignals: true
        function onVisibleChanged() { if (fx.card.Window.window && fx.card.Window.window.visible) fx.play(); }
    }
}
