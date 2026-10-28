"""GTK-Hilfen, die sich die Seiten Tastatur, Maus & Touchpad und Eingabehilfen teilen (nur Oberfläche; Logik: dx_inputlib)."""
import subprocess
import sys
import threading

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import GLib, Gtk

import dx_inputlib as lib


class Saver:
    """Sammelt Änderungen, schreibt input.json atomar nach kurzer Pause und stößt Hyprland an (im Hintergrund, nie blockierend)."""

    def __init__(self, app):
        self.app = app
        self.pending = {}
        self.timer = 0

    def set(self, key, value):
        self.pending[key] = value
        if self.timer:
            GLib.source_remove(self.timer)
        self.timer = GLib.timeout_add(350, self._flush)

    def set_many(self, changes):
        self.pending.update(changes)
        if self.timer:
            GLib.source_remove(self.timer)
        self.timer = GLib.timeout_add(350, self._flush)

    def _flush(self):
        self.timer = 0
        changes, self.pending = self.pending, {}
        try:
            lib.update_input(changes)
        except (OSError, ValueError) as e:
            self.app.message('Konnte nicht gespeichert werden: %s' % e)
            return False
        self.app.message('Gespeichert.')

        def work():
            ok = lib.apply_live()
            GLib.idle_add(self.app.message, 'Gespeichert und angewendet.' if ok else 'Gespeichert (gilt nach dem nächsten Start von Hyprland oder Neuladen der Konfiguration).')
        threading.Thread(target=work, daemon=True).start()
        return False


def run_async(argv, done=None, timeout=10):
    """Programm mit Zeitlimit im Hintergrund; done(returncode, stdout) läuft in der UI-Schleife. Fehlendes Programm -> returncode 127."""
    def work():
        try:
            r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
            rc, out = r.returncode, r.stdout
        except (OSError, subprocess.SubprocessError):
            rc, out = 127, ''
        if done:
            GLib.idle_add(done, rc, out)
    threading.Thread(target=work, daemon=True).start()


def make_combo():
    """Auswahlliste im Stil der Einstellungen (Popover im Fenster statt GTK-ComboBox, die unter Hyprland falsch aufgeht);
    ohne die Klasse aus settings-app Gtk.ComboBoxText."""
    cls = getattr(sys.modules.get('__main__'), 'Select', None)
    try:
        if cls is not None and issubclass(cls, Gtk.Widget):
            return cls()
    except TypeError:
        pass
    return Gtk.ComboBoxText()


def combo_select(w, ident):
    """Wählt ident aus (ohne Signal); gibt zurück, ob es den Eintrag gibt."""
    items = getattr(w, 'items', None)
    if items is not None:
        if ident not in items:
            return False
        w.set_active_id(ident)
        return True
    return bool(w.set_active_id(ident))


def switch(app, saver, box, title, key, default, desc='', invert=False):
    data = lib.load_input()
    val = data.get(key)
    state = default if not isinstance(val, bool) else val
    w = Gtk.Switch(active=state)
    w.connect('notify::active', lambda w, _: saver.set(key, w.get_active()))
    app.row(box, title, w, desc)
    return w


def spin(app, saver, box, title, key, default, desc='', step=None, digits=0):
    lo, hi = lib.LIMITS[key]
    data = lib.load_input()
    val = data.get(key)
    cur = val if isinstance(val, (int, float)) and not isinstance(val, bool) else default
    w = Gtk.SpinButton.new_with_range(lo, hi, step or (1 if not digits else 10 ** -digits))
    w.set_digits(digits)
    w.set_value(cur)
    w.connect('value-changed', lambda w: saver.set(key, w.get_value() if digits else w.get_value_as_int()))
    app.row(box, title, w, desc)
    return w


def scale(app, saver, box, title, key, default, desc='', step=0.05, digits=2, marks=()):
    lo, hi = lib.LIMITS[key]
    data = lib.load_input()
    val = data.get(key)
    cur = val if isinstance(val, (int, float)) and not isinstance(val, bool) else default
    w = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lo, hi, step)
    w.set_digits(digits)
    w.set_value_pos(Gtk.PositionType.RIGHT)
    w.set_size_request(320, -1)
    w.set_value(cur)
    for m in marks:
        w.add_mark(m, Gtk.PositionType.BOTTOM, None)
    w.connect('value-changed', lambda w: saver.set(key, round(w.get_value(), digits)))
    app.row(box, title, w, desc)
    return w


def choice(app, saver, box, title, key, default, items, desc=''):
    """items: [(wert, text)]. Wert None/'' wird als gespeicherter Wert wie in items geführt."""
    data = lib.load_input()
    cur = data.get(key, default)
    w = make_combo()
    for v, t in items:
        w.append(str(v), t)
    if not combo_select(w, str(cur)):
        combo_select(w, str(default))
    w.connect('changed', lambda w: w.get_active_id() is not None and saver.set(key, w.get_active_id()))
    app.row(box, title, w, desc)
    return w


def note(app, box, text):
    """Hinweiszeile ohne Bedienelement."""
    l = Gtk.Label(label=text, xalign=0)
    l.set_line_wrap(True)
    l.set_max_width_chars(100)
    l.get_style_context().add_class('row-desc')
    box.pack_start(l, False, False, 0)
    l.show()
    app.page_index.setdefault(app._cur_page, []).append(text.lower())
    return l


def reset_button(app, saver, box, keys, rebuild_hint='Seite neu öffnen, um die Standardwerte zu sehen.'):
    def go(*_):
        d = Gtk.MessageDialog(transient_for=app.window, modal=True, message_type=Gtk.MessageType.QUESTION,
                              buttons=Gtk.ButtonsType.OK_CANCEL, text='Diese Seite auf Standard zurücksetzen?')
        d.format_secondary_text('Alle Werte dieser Seite gehen auf die Standardwerte der Konfiguration zurück. %s' % rebuild_hint)
        r = d.run()
        d.destroy()
        if r == Gtk.ResponseType.OK:
            saver.set_many({k: None for k in keys})
            app.message('Auf Standard zurückgesetzt.')
    b = Gtk.Button(label='Diese Seite auf Standard zurücksetzen')
    b.set_halign(Gtk.Align.START)
    b.set_margin_top(14)
    b.connect('clicked', go)
    box.pack_start(b, False, False, 0)
    b.show()
    return b
