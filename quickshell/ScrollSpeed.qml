import QtQuick

// Mausrad-Geschwindigkeit für Listen der Shell. Hyprlands scroll_factor erreicht Qt-Programme nicht (sie lesen die ganzen Rastungen,
// nicht den skalierten Wert) – deshalb skaliert jede Liste ihr Mausrad selbst. 1.0 = 60 px je Rastung; Einstellung: Aurora → Übersicht.
WheelHandler {
    id: wh
    property var flick: null
    // Die Liste finden, in der dieser Handler steckt (der direkte Elternteil ist bei Flickable der Inhalt, nicht die Liste selbst)
    Component.onCompleted: { for (let o = wh.parent; o; o = o.parent) if (o.contentY !== undefined && o.contentHeight !== undefined && o.flick !== undefined) { wh.flick = o; break; } }
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
        const f = wh.flick;
        if (!f) return;
        const horizontal = f.contentHeight <= f.height && f.contentWidth > f.width;
        // Mausrad-Rastungen kommen als Vielfache von 120 (→ 60 px je Rastung, wie Qts Standard); Touchpad-Wischen liefert feine Werte (→ echte Pixel)
        const ay = event.angleDelta.y;
        const raw = (ay !== 0 && Math.abs(ay) % 120 === 0) ? ay / 120 * 60 : (event.pixelDelta.y !== 0 ? event.pixelDelta.y : ay / 120 * 60);
        const d = raw * Theme.scrollSpeed;
        if (horizontal) f.contentX = Math.max(f.originX, Math.min(f.originX + f.contentWidth - f.width, f.contentX - d));
        else f.contentY = Math.max(f.originY, Math.min(f.originY + f.contentHeight - f.height, f.contentY - d));
        event.accepted = true;
    }
}
