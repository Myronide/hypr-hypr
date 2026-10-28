"""Aurora-Seite „Maus & Touchpad“: Zeigergeschwindigkeit, Beschleunigung, Scrollen, Touchpad-Gesten, Geräteliste, Spielcontroller.
Werte landen in ~/.config/draconyx/input.json und werden von hypr/dx_input.lua angewendet."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

TITLE = 'Maus & Touchpad'
GROUP = 'SYSTEM'
ICONS = ['input-mouse-symbolic', 'input-touchpad-symbolic']
ORDER = 21


def build(app):
    from gi.repository import Gtk
    import shutil
    import dx_inputlib as lib
    import dx_inputui as ui

    saver = ui.Saver(app)
    box = app.page(TITLE, 'Zeigergeschwindigkeit, Beschleunigung, Scrollrichtung, Touchpad-Gesten, erkannte Eingabegeräte und Spielcontroller. Änderungen gelten sofort.')

    app.section(box, 'Zeiger')
    ui.scale(app, saver, box, 'Zeigergeschwindigkeit', 'sensitivity', 0.0, 'Von −1 (langsam) bis +1 (schnell); 0 ist die Standardgeschwindigkeit.', marks=(0.0,))
    ui.choice(app, saver, box, 'Beschleunigung', 'accel_profile', 'flat',
              [('flat', 'Gleichmäßig (ohne Beschleunigung)'), ('adaptive', 'Adaptiv (schnelle Bewegung = weiterer Weg)')],
              'Gleichmäßig verhält sich wie in Spielen; adaptiv wie in Windows und macOS.')
    ui.switch(app, saver, box, 'Linkshänder-Modus', 'left_handed', False, 'Vertauscht linke und rechte Maustaste (und beim Touchpad die Tasten).')

    app.section(box, 'Mausrad')
    ui.switch(app, saver, box, 'Natürliches Scrollen (Maus)', 'natural_scroll_mouse', False, 'Der Inhalt folgt der Bewegung des Mausrads wie bei einem Touchscreen.')
    if hasattr(app, 'spin') and hasattr(app, 'p'):
        app.spin(box, 'Mausrad-Geschwindigkeit', 'scroll_speed', 0.2, 5.0, 0.1, 'Wie weit ein Rastschritt scrollt (1,0 = Standard). Dieselbe Einstellung wie unter „Übersicht“.')

    app.section(box, 'Touchpad')
    ui.switch(app, saver, box, 'Natürliches Scrollen (Touchpad)', 'natural_scroll_touchpad', False, 'Zwei-Finger-Wischen schiebt den Inhalt wie auf einem Touchscreen.')
    ui.switch(app, saver, box, 'Tippen zum Klicken', 'tap_to_click', True, 'Ein Tipp auf das Touchpad zählt als Klick (zwei Finger = Rechtsklick, drei = Mittelklick).')
    ui.switch(app, saver, box, 'Tippen und Ziehen', 'tap_and_drag', True, 'Tippen, dann mit dem Finger sofort weiterziehen verschiebt Objekte.')
    ui.switch(app, saver, box, 'Ziehen einrasten lassen', 'drag_lock', False, 'Beim Tippen-und-Ziehen bleibt das Objekt gegriffen, bis man erneut tippt.')
    ui.switch(app, saver, box, 'Zwei-Finger-Scrollen', 'two_finger_scroll', True, 'Aus: Scrollen über den rechten Rand des Touchpads.')
    ui.scale(app, saver, box, 'Scrollgeschwindigkeit (Touchpad)', 'touchpad_scroll_factor', 1.0, 'Standard: 1,0.', step=0.1, digits=1)
    ui.switch(app, saver, box, 'Touchpad beim Tippen sperren', 'disable_while_typing', True, 'Verhindert versehentliche Berührungen mit dem Handballen während des Schreibens.')

    app.section(box, 'Doppelklick')
    dc = Gtk.SpinButton.new_with_range(100, 1000, 50)
    dc.set_value(400)
    state = {'ready': False}

    def got(rc, out):
        try:
            if rc == 0:
                dc.set_value(min(max(int(out.strip().split()[-1]), 100), 1000))
        except (ValueError, IndexError):
            pass
        state['ready'] = True
        return False
    gs = shutil.which('gsettings')
    if gs:
        ui.run_async([gs, 'get', 'org.gnome.desktop.peripherals.mouse', 'double-click'], got)
    else:
        state['ready'] = True

    def dc_changed(w):
        if state['ready'] and gs:
            ui.run_async([gs, 'set', 'org.gnome.desktop.peripherals.mouse', 'double-click', str(w.get_value_as_int())],
                         lambda rc, o: app.message('Doppelklick-Zeit gesetzt (gilt für neu gestartete Programme).' if rc == 0 else 'Doppelklick-Zeit konnte nicht gesetzt werden.'))
    dc.connect('value-changed', dc_changed)
    dc.set_sensitive(bool(gs))
    app.row(box, 'Doppelklick-Zeit (ms)', dc, 'Höchster Abstand zweier Klicks für einen Doppelklick (400 ms = Standard). Gilt für GTK-Programme; Hyprland selbst kennt keine Doppelklick-Zeit.' if gs else 'Benötigt „gsettings“ (nicht gefunden).')

    app.section(box, 'Zeigerdarstellung')
    theme, size = lib.current_cursor()
    ui.note(app, box, 'Aktuell: Thema „%s“, Größe %d. Die Größe stellst du unter „Eingabehilfen“ ein; das Thema wird an anderer Stelle gewählt.' % (theme, size))

    app.section(box, 'Erkannte Eingabegeräte')
    dev = Gtk.Label(label='wird gelesen …', xalign=0)
    dev.set_line_wrap(True)
    dev.set_selectable(True)
    app.row(box, 'Mäuse, Tastaturen und weitere Geräte', dev)

    def devs(rc, out):
        import json
        text = 'Hyprland nicht erreichbar – keine Geräteliste.'
        if rc == 0:
            try:
                items = lib.parse_devices(json.loads(out))
                text = '\n'.join('%s: %s' % x for x in items) or 'Keine Geräte gemeldet.'
            except ValueError:
                pass
        dev.set_text(text)
        return False
    if shutil.which('hyprctl') and os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        ui.run_async(['hyprctl', 'devices', '-j'], devs)
    else:
        devs(127, '')

    app.section(box, 'Spielcontroller')
    pads = lib.list_gamepads()
    ui.note(app, box, ('Erkannt: ' + '; '.join('%s (%s)' % (n, d) for d, n in pads) + '. Hier gibt es nichts einzustellen – Controller werden direkt von Spielen und Steam verwaltet.')
            if pads else 'Kein Spielcontroller erkannt. Controller werden direkt von Spielen und Steam verwaltet; hier gibt es nichts einzustellen.')

    ui.reset_button(app, saver, box, ['sensitivity', 'accel_profile', 'left_handed', 'natural_scroll_mouse', 'natural_scroll_touchpad', 'tap_to_click',
                                      'tap_and_drag', 'drag_lock', 'two_finger_scroll', 'touchpad_scroll_factor', 'disable_while_typing'])
