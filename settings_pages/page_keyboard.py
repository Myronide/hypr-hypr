"""Aurora-Seite „Tastatur“: Layouts, Umschalten, Wiederholung, NumLock, Feststelltaste, Compose-Taste, Testfeld.
Werte landen in ~/.config/draconyx/input.json und werden von hypr/dx_input.lua angewendet."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

TITLE = 'Tastatur'
GROUP = 'SYSTEM'
ICONS = ['input-keyboard-symbolic']
ORDER = 20


def _default_layouts():
    """Belegung der Config ohne Nutzereintrag: ~/.config/draconyx/keymap (Installer), sonst de."""
    import re
    from pathlib import Path
    try:
        k = (Path(os.environ.get('HOME') or str(Path.home())) / '.config/draconyx/keymap').read_text().strip()
    except OSError:
        k = ''
    return [{'layout': x, 'variant': ''} for x in k.split(',') if re.fullmatch(r'[a-z_]{2,8}', x)][:4] or [{'layout': 'de', 'variant': ''}]


def build(app):
    from gi.repository import GLib, Gtk
    import dx_inputlib as lib
    import dx_inputui as ui

    saver = ui.Saver(app)
    lst = lib.parse_base_lst()
    data = lib.load_input()
    state = {'layouts': [dict(e) for e in (data.get('layouts') or _default_layouts())],
             'options': list(data.get('kb_options') or [])}

    box = app.page(TITLE, 'Tastaturbelegungen, Umschalten zwischen Layouts, Wiederholung der Tasten, NumLock, Feststelltaste und Compose-Taste. Änderungen gelten sofort.')

    # ---------- Layouts
    app.section(box, 'Layouts')
    holder = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    summary = Gtk.Label(xalign=0)
    summary.set_line_wrap(True)
    switch_combo = {}

    def commit():
        saver.set('layouts', state['layouts'])
        refresh()

    def move(i, d):
        j = i + d
        if 0 <= j < len(state['layouts']):
            state['layouts'][i], state['layouts'][j] = state['layouts'][j], state['layouts'][i]
            commit()

    def remove(i):
        if len(state['layouts']) > 1:
            del state['layouts'][i]
            commit()

    def refresh():
        for c in holder.get_children():
            holder.remove(c)
            c.destroy()
        n = len(state['layouts'])
        for i, e in enumerate(state['layouts']):
            row = Gtk.Box(spacing=6)
            tag = Gtk.Label(label='%d.' % (i + 1), xalign=0)
            tag.set_size_request(24, -1)
            row.pack_start(tag, False, False, 0)
            name = Gtk.Label(label='%s   (%s)' % (lib.layout_label(e['layout'], e['variant'], lst), lib.short_layout_code(e['layout'], e['variant'])), xalign=0)
            name.set_ellipsize(3)
            row.pack_start(name, True, True, 0)
            for text, tip, cb, ok in (('↑', 'Nach oben', lambda *_, i=i: move(i, -1), i > 0), ('↓', 'Nach unten', lambda *_, i=i: move(i, 1), i < n - 1),
                                      ('Entfernen', 'Layout entfernen', lambda *_, i=i: remove(i), n > 1)):
                b = Gtk.Button(label=text)
                b.set_tooltip_text(tip)
                b.set_sensitive(ok)
                b.connect('clicked', cb)
                row.pack_start(b, False, False, 0)
            holder.pack_start(row, False, False, 0)
        holder.show_all()
        summary.set_text('Aktive Belegung (Reihenfolge = Umschaltreihenfolge): %s' % lib.kb_summary({'layouts': state['layouts']}))
        for w in switch_combo.values():
            w.set_sensitive(n > 1)

    def add_dialog(*_):
        d = Gtk.Dialog(title='Layout hinzufügen', transient_for=app.window, modal=True)
        d.add_button('Abbrechen', Gtk.ResponseType.CANCEL)
        d.add_button('Hinzufügen', Gtk.ResponseType.OK)
        d.set_default_size(460, 460)
        area = d.get_content_area()
        area.set_spacing(8)
        area.set_border_width(12)
        search = Gtk.SearchEntry()
        search.set_placeholder_text('Layout suchen (z. B. Deutsch, French, Dvorak) …')
        area.pack_start(search, False, False, 0)
        store = Gtk.ListStore(str, str)
        view = Gtk.TreeView(model=store, headers_visible=False)
        view.append_column(Gtk.TreeViewColumn('Layout', Gtk.CellRendererText(), text=1))
        sw = Gtk.ScrolledWindow()
        sw.add(view)
        area.pack_start(sw, True, True, 0)
        var_combo = Gtk.ComboBoxText()   # im Dialog ein eigenes Fenster: Standard-Auswahl genügt
        area.pack_start(Gtk.Label(label='Variante', xalign=0), False, False, 0)
        area.pack_start(var_combo, False, False, 0)
        if not lst['layouts']:
            area.pack_start(Gtk.Label(label='Die XKB-Liste (base.lst) wurde nicht gefunden – bitte „xkeyboard-config“ installieren.', xalign=0), False, False, 0)

        def fill(*_):
            store.clear()
            for c, desc in lib.search_layouts(lst['layouts'], search.get_text())[:400]:
                store.append([c, '%s  (%s)' % (desc, c)])
            first = store.get_iter_first()
            if first:
                view.get_selection().select_iter(first)

        def pick(*_):
            var_combo.remove_all()
            var_combo.append('', 'Standard')
            m, it = view.get_selection().get_selected()
            if it:
                for v, vd in lst['variants'].get(m[it][0], []):
                    var_combo.append(v, '%s (%s)' % (vd, v))
            var_combo.set_active(0)
        search.connect('search-changed', fill)
        view.get_selection().connect('changed', pick)
        fill()
        d.show_all()
        r = d.run()
        m, it = view.get_selection().get_selected()
        code = m[it][0] if it else None
        var = var_combo.get_active_id() or ''
        d.destroy()
        if r == Gtk.ResponseType.OK and code:
            if len(state['layouts']) >= lib.MAX_LAYOUTS:
                app.message('Höchstens %d Layouts gleichzeitig möglich.' % lib.MAX_LAYOUTS)
            elif any(e['layout'] == code and e['variant'] == var for e in state['layouts']):
                app.message('Dieses Layout ist schon in der Liste.')
            else:
                state['layouts'].append({'layout': code, 'variant': var})
                commit()

    app.row(box, 'Eingerichtete Layouts', holder, 'Das erste Layout gilt beim Start. Mit der Umschalt-Kombination (unten) wechselst du zwischen ihnen. Höchstens vier.')
    box.pack_start(summary, False, False, 0)
    add = Gtk.Button(label='Layout hinzufügen …')
    add.set_halign(Gtk.Align.START)
    add.connect('clicked', add_dialog)
    box.pack_start(add, False, False, 0)

    # ---------- Umschalten, Feststelltaste, Compose
    app.section(box, 'Tasten')

    def opt_choice(title, kind, items, desc):
        w = ui.make_combo()
        for v, t in items:
            w.append(v, t)
        cur = lib.options_get(state['options'], kind)
        if not ui.combo_select(w, cur):
            w.append(cur, cur + ' (aus der Konfiguration)')
            ui.combo_select(w, cur)

        def changed(w):
            val = w.get_active_id()
            if val is None:
                return
            state['options'] = lib.options_set(state['options'], kind, val)
            saver.set('kb_options', state['options'])
        w.connect('changed', changed)
        app.row(box, title, w, desc)
        return w
    switch_combo['s'] = opt_choice('Layout umschalten mit', 'switch', lib.SWITCH_CHOICES, 'Tastenkombination zum Wechsel zwischen den Layouts. Wirkt nur bei mindestens zwei Layouts.')
    opt_choice('Feststelltaste', 'caps', lib.CAPS_CHOICES, 'Verhalten der Feststelltaste (Caps Lock). Hinweis: Ist die Haupttaste unter „Tastenkombinationen“ auf die Feststelltaste gelegt, hier „Normal“ lassen.')
    opt_choice('Compose-Taste', 'compose', lib.COMPOSE_CHOICES, 'Mit der Compose-Taste tippst du Sonderzeichen über Tastenfolgen (z. B. Compose, ", a ergibt ä).')
    refresh()

    # ---------- Wiederholung, NumLock
    app.section(box, 'Wiederholung und NumLock')
    ui.spin(app, saver, box, 'Wiederholverzögerung (ms)', 'repeat_delay', 600, 'Zeit, die eine Taste gedrückt bleiben muss, bis sie sich wiederholt. Standard: 600.', step=50)
    ui.spin(app, saver, box, 'Wiederholrate (pro Sekunde)', 'repeat_rate', 25, 'Wie schnell sich eine gehaltene Taste wiederholt. Standard: 25.')
    ui.switch(app, saver, box, 'NumLock beim Start einschalten', 'numlock', True, 'Wirkt beim nächsten Start von Hyprland vollständig; zur Laufzeit je nach Tastatur.')

    # ---------- Test
    app.section(box, 'Test')
    entry = Gtk.Entry()
    entry.set_width_chars(46)
    entry.set_placeholder_text('Hier tippen, um Belegung, Umlaute und Umschalten zu testen …')
    app.row(box, 'Testfeld', entry, 'Die Eingabe wird nirgends gespeichert.')

    cur = Gtk.Label(xalign=0)
    cur.set_line_wrap(True)
    cur.set_selectable(True)
    app.row(box, 'Von Hyprland gemeldete Belegung', cur, 'Welche Belegung die Tastaturen gerade wirklich benutzen.')
    cur.set_text('wird gelesen …')

    def got(rc, out):
        import json
        text = 'Hyprland nicht erreichbar (Seite läuft ohne laufende Sitzung).'
        if rc == 0:
            try:
                kbs = json.loads(out).get('keyboards') or []
                names = ['%s: %s' % (k.get('name', '?'), k.get('active_keymap', '?')) for k in kbs if isinstance(k, dict) and k.get('main')]
                text = '\n'.join(names) or 'Keine Tastatur gemeldet.'
            except (ValueError, AttributeError):
                pass
        cur.set_text(text)
        return False
    import shutil
    if shutil.which('hyprctl') and os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        ui.run_async(['hyprctl', 'devices', '-j'], got)
    else:
        got(127, '')

    ui.reset_button(app, saver, box, ['layouts', 'kb_options', 'repeat_delay', 'repeat_rate', 'numlock'])
