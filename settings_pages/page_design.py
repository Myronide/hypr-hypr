"""Aurora-Einstellungen: Design (Zeiger, Symbole, Themen). Reine Logik oben (testbar), GTK-Oberfläche in build()."""
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import _devlib as D  # noqa: E402

TITLE = 'Design'
GROUP = 'DARSTELLUNG'
ICONS = ['preferences-desktop-theme-symbolic', 'applications-graphics-symbolic', 'preferences-desktop-appearance-symbolic']
ORDER = 45

CURSOR_SIZES = [16, 20, 24, 28, 32, 36, 40, 48, 64, 72, 96]
SKIP_THEMES = {'default', 'hicolor', 'locolor'}
IFACE = 'org.gnome.desktop.interface'


# ---------- Themen finden ----------
def icon_dirs(home=None):
    h = Path(home) if home else D.home()
    xdg = Path(os.environ.get('XDG_DATA_HOME') or (h / '.local/share'))
    return [Path('/usr/share/icons'), xdg / 'icons', h / '.icons']


def theme_dirs(home=None):
    h = Path(home) if home else D.home()
    xdg = Path(os.environ.get('XDG_DATA_HOME') or (h / '.local/share'))
    return [Path('/usr/share/themes'), xdg / 'themes', h / '.themes']


def _theme_meta(index_text):
    name = D.ini_get(index_text, 'Icon Theme', 'Name')
    hidden = (D.ini_get(index_text, 'Icon Theme', 'Hidden') or '').lower() == 'true'
    dirs = D.ini_get(index_text, 'Icon Theme', 'Directories')
    return name, hidden, bool(dirs and dirs.strip())


def find_icon_themes(dirs):
    """-> (symbolthemen, cursorthemen): je {id: Anzeigename}. Cursorthemen haben einen Ordner cursors/; Symbolthemen
    ein index.theme mit Directories= (reine Zeigerthemen fallen so aus der Symbolliste)."""
    icons, cursors = {}, {}
    for base in dirs:
        try:
            entries = sorted(Path(base).iterdir())
        except OSError:
            continue
        for d in entries:
            tid = d.name
            if tid in SKIP_THEMES or tid.startswith('.') or not d.is_dir():
                continue
            idx = d / 'index.theme'
            text = D.read_text(idx) if idx.is_file() else ''
            name, hidden, has_dirs = _theme_meta(text)
            if hidden:
                continue
            label = name or tid
            if (d / 'cursors').is_dir() or (d / 'cursors_scalable').is_dir():
                cursors.setdefault(tid, label)
            if idx.is_file() and has_dirs:
                icons.setdefault(tid, label)
    return icons, cursors


def find_gtk_themes(dirs):
    out = {}
    for base in dirs:
        try:
            entries = sorted(Path(base).iterdir())
        except OSError:
            continue
        for d in entries:
            if d.is_dir() and not d.name.startswith('.') and ((d / 'gtk-3.0').is_dir() or (d / 'gtk-4.0').is_dir()):
                out.setdefault(d.name, d.name)
    return out


def valid_choice(value, options):
    return value in options


def valid_size(size):
    try:
        return 8 <= int(size) <= 256
    except (TypeError, ValueError):
        return False


# ---------- Schreiben ----------
def cmd_gsettings(key, value):
    return ['gsettings', 'set', IFACE, key, str(value)]


def apply_cursor(theme, size, cursors, runner, home=None):
    """Mauszeiger setzen: Dateien (atomar, fremde Zeilen bleiben) + gsettings + hyprctl. runner(argv)->bool. -> Liste von Warnungen."""
    if not valid_choice(theme, cursors):
        raise ValueError('Unbekanntes Zeigerthema.')
    if not valid_size(size):
        raise ValueError('Ungültige Zeigergröße.')
    size = int(size)
    h = Path(home) if home else D.home()
    cfg = Path(os.environ.get('XDG_CONFIG_HOME') or (h / '.config'))
    warn = []
    # Zeiger für X11/XWayland-Programme
    idx = h / '.icons/default/index.theme'
    text = D.read_text(idx)
    if not text.strip():
        text = '[Icon Theme]\nName=Default\nComment=Default cursor theme\n'
    D.atomic_write(idx, D.ini_set(text, 'Icon Theme', 'Inherits', theme))
    for ver in ('gtk-3.0', 'gtk-4.0'):
        D.ini_update_file(cfg / ver / 'settings.ini', 'Settings', [('gtk-cursor-theme-name', theme), ('gtk-cursor-theme-size', size)])
    D.ini_update_file(cfg / 'kcminputrc', 'Mouse', [('cursorTheme', theme), ('cursorSize', size)])
    # Merkdatei für die Hyprland-Config (falls sie sie beim Login liest)
    D.atomic_write(cfg / 'draconyx/cursor', '%s\n%d\n' % (theme, size))
    for argv in (cmd_gsettings('cursor-theme', "'%s'" % theme), cmd_gsettings('cursor-size', size), ['hyprctl', 'setcursor', theme, str(size)]):
        if not runner(argv):
            warn.append(argv[0])
    return warn


def apply_icons(theme, icons, runner, home=None):
    if not valid_choice(theme, icons):
        raise ValueError('Unbekanntes Symbolthema.')
    h = Path(home) if home else D.home()
    cfg = Path(os.environ.get('XDG_CONFIG_HOME') or (h / '.config'))
    D.ini_update_file(cfg / 'kdeglobals', 'Icons', [('Theme', theme)])
    for ver in ('gtk-3.0', 'gtk-4.0'):
        D.ini_update_file(cfg / ver / 'settings.ini', 'Settings', [('gtk-icon-theme-name', theme)])
    return [] if runner(cmd_gsettings('icon-theme', "'%s'" % theme)) else ['gsettings']


def apply_gtk(theme, dark, themes, runner, home=None):
    """GTK-Thema (theme darf None sein = unverändert) und Hell/Dunkel."""
    if theme is not None and not valid_choice(theme, themes):
        raise ValueError('Unbekanntes GTK-Thema.')
    h = Path(home) if home else D.home()
    cfg = Path(os.environ.get('XDG_CONFIG_HOME') or (h / '.config'))
    items = [('gtk-application-prefer-dark-theme', 'true' if dark else 'false')]
    if theme is not None:
        items.append(('gtk-theme-name', theme))
    for ver in ('gtk-3.0', 'gtk-4.0'):
        D.ini_update_file(cfg / ver / 'settings.ini', 'Settings', items)
    warn = []
    cmds = [cmd_gsettings('color-scheme', "'prefer-dark'" if dark else "'prefer-light'")]
    if theme is not None:
        cmds.append(cmd_gsettings('gtk-theme', "'%s'" % theme))
    for argv in cmds:
        if not runner(argv):
            warn.append(argv[0])
    return warn


def read_current(home=None):
    """Aktuelle Werte aus den Dateien (Fallback, wenn gsettings fehlt)."""
    h = Path(home) if home else D.home()
    cfg = Path(os.environ.get('XDG_CONFIG_HOME') or (h / '.config'))
    gtk = D.read_text(cfg / 'gtk-3.0/settings.ini')
    size = D.ini_get(gtk, 'Settings', 'gtk-cursor-theme-size')
    return {
        'cursor': D.ini_get(gtk, 'Settings', 'gtk-cursor-theme-name') or D.ini_get(D.read_text(h / '.icons/default/index.theme'), 'Icon Theme', 'Inherits'),
        'size': int(size) if size and size.isdigit() else None,
        'icons': D.ini_get(gtk, 'Settings', 'gtk-icon-theme-name') or D.ini_get(D.read_text(cfg / 'kdeglobals'), 'Icons', 'Theme'),
        'gtk': D.ini_get(gtk, 'Settings', 'gtk-theme-name'),
        'dark': (D.ini_get(gtk, 'Settings', 'gtk-application-prefer-dark-theme') or '').lower() == 'true',
    }


def read_qt_env(lua_text):
    """Aus der Hyprland-Config: hl.env("QT_…", "wert") -> {name: wert} (nur Anzeige)."""
    out = {}
    for m in re.finditer(r'hl\.env\(\s*"(QT_STYLE_OVERRIDE|QT_QPA_PLATFORMTHEME|GTK_THEME|XCURSOR_THEME|XCURSOR_SIZE)"\s*,\s*"([^"]*)"', lua_text or ''):
        out[m.group(1)] = m.group(2)
    return out


def qt_info(home=None):
    h = Path(home) if home else D.home()
    cfg = Path(os.environ.get('XDG_CONFIG_HOME') or (h / '.config'))
    info = {}
    kv = D.ini_get(D.read_text(cfg / 'Kvantum/kvantum.kvconfig'), 'General', 'theme')
    if kv:
        info['Kvantum-Thema'] = kv
    q6 = D.read_text(cfg / 'qt6ct/qt6ct.conf')
    for lab, sec, key in (('qt6ct-Stil', 'Appearance', 'style'), ('qt6ct-Symbole', 'Appearance', 'icon_theme')):
        v = D.ini_get(q6, sec, key)
        if v:
            info[lab] = v
    cs = D.ini_get(D.read_text(cfg / 'kdeglobals'), 'General', 'ColorScheme')
    if cs:
        info['KDE-Farbschema'] = cs
    return info


def real_runner(argv):
    if not D.which(argv[0]):
        return False
    return D.run_cmd(argv, 6).returncode == 0


# ---------- Oberfläche ----------
def build(app):
    from gi.repository import Gtk, GLib
    box = app.page(TITLE, 'Mauszeiger (Thema und Größe), Symbolthema, GTK-Thema (Hell/Dunkel) und Qt-Stil. Schriften stehen unter „Farben & Schrift“.')
    icons, cursors = find_icon_themes(icon_dirs())
    gtkth = find_gtk_themes(theme_dirs())
    cur = read_current()
    st = {'cursor': cur['cursor'], 'size': cur['size'] or 24, 'icons': cur['icons'], 'gtk': cur['gtk'], 'dark': cur['dark'], 'sync': True}
    say = app.message

    def finish(warn, ok):
        if warn:
            say(ok + ' (nicht verfügbar: %s)' % ', '.join(sorted(set(warn))))
        else:
            say(ok)

    def run_apply(fn, ok):
        def work():
            return fn()

        def done(res):
            if isinstance(res, Exception):
                say('Nicht angewendet: %s' % res)
            else:
                finish(res, ok)
        D.bg(work, done)

    # --- Zeiger ---
    app.section(box, 'Mauszeiger')
    timer = {'id': 0}

    def cursor_changed():
        if st['sync']:
            return
        if timer['id']:
            GLib.source_remove(timer['id'])

        def go():
            timer['id'] = 0
            if st['cursor'] in cursors:
                t, s = st['cursor'], st['size']
                run_apply(lambda: apply_cursor(t, s, cursors, real_runner), 'Zeiger „%s“ (%s) angewendet.' % (cursors[t], s))
            return False
        timer['id'] = GLib.timeout_add(500, go)

    def pick_cursor(v):
        st['cursor'] = v
        cursor_changed()

    def pick_size(v):
        st['size'] = int(v)
        cursor_changed()
    W = {}
    if cursors:
        W['cursor'] = D.ui_select(sorted(((k, v) for k, v in cursors.items()), key=lambda kv: kv[1].lower()), st['cursor'] if st['cursor'] in cursors else None, pick_cursor)
        app.row(box, 'Zeigerthema', W['cursor'],
                'Gilt sofort für den Desktop und neu gestartete Programme (X11 und GTK); laufende Programme übernehmen es teils erst beim Neustart.')
        sizes = sorted(set(CURSOR_SIZES + [st['size']]))
        W['size_ids'] = [str(x) for x in sizes]
        W['size'] = D.ui_select([(str(s), '%d' % s) for s in sizes], str(st['size']), pick_size)
        app.row(box, 'Zeigergröße', W['size'])
    else:
        box.pack_start(D.ui_label('Keine Zeigerthemen gefunden (in /usr/share/icons, ~/.local/share/icons, ~/.icons).', 'row-desc'), False, False, 0)
    lua = read_qt_env(D.read_text(D.home() / '.config/hypr/hyprland.lua'))
    box.pack_start(D.ui_label('Hinweis: Die Hyprland-Konfiguration setzt den Zeiger beim Anmelden selbst (Windows10Light bzw. Adwaita, Größe 24). Die Auswahl hier gilt sofort und wird zusätzlich in ~/.config/draconyx/cursor gemerkt; nach der nächsten Anmeldung kann die Konfiguration sie überschreiben.', 'row-desc'), False, False, 0)

    # --- Symbole ---
    app.section(box, 'Symbole')
    if icons:
        def pick_icons(v):
            if st['sync'] or not v:
                return
            run_apply(lambda: apply_icons(v, icons, real_runner), 'Symbolthema „%s“ angewendet.' % icons[v])
        W['icons'] = D.ui_select(sorted(icons.items(), key=lambda kv: kv[1].lower()), st['icons'] if st['icons'] in icons else None, pick_icons)
        app.row(box, 'Symbolthema', W['icons'],
                'Für GTK-Programme (gsettings, settings.ini) und KDE/Qt-Programme (kdeglobals). Reine Zeigerthemen sind ausgeblendet. Die Aurora-Shell hat ein eigenes Symbolthema (Umgebungsvariable QS_ICON_THEME).')
    else:
        box.pack_start(D.ui_label('Keine Symbolthemen gefunden.', 'row-desc'), False, False, 0)

    # --- GTK ---
    app.section(box, 'GTK-Programme')
    gtk_sel = {'dark': st['dark']}

    def pick_gtk(v):
        if st['sync'] or not v:
            return
        run_apply(lambda: apply_gtk(v, gtk_sel['dark'], gtkth, real_runner), 'GTK-Thema „%s“ angewendet.' % v)

    def pick_dark(v):
        if st['sync'] or v is None:
            return
        gtk_sel['dark'] = (v == 'dark')
        run_apply(lambda: apply_gtk(None, gtk_sel['dark'], gtkth, real_runner), 'Farbschema: %s.' % ('Dunkel' if gtk_sel['dark'] else 'Hell'))
    W['dark'] = D.ui_choice([('light', 'Hell'), ('dark', 'Dunkel')], 'dark' if st['dark'] else 'light', pick_dark)
    app.row(box, 'Hell oder Dunkel', W['dark'],
            'Bevorzugtes Farbschema für GTK-Programme und Libadwaita-Programme.')
    if gtkth:
        W['gtk'] = D.ui_select(sorted(gtkth.items(), key=lambda kv: kv[1].lower()), st['gtk'] if st['gtk'] in gtkth else None, pick_gtk)
        app.row(box, 'GTK-Thema', W['gtk'],
                'Aus /usr/share/themes, ~/.local/share/themes und ~/.themes. Libadwaita-Programme (GTK 4) ignorieren Themennamen und folgen nur Hell/Dunkel.')
    if lua.get('GTK_THEME'):
        box.pack_start(D.ui_label('Hinweis: Die Hyprland-Konfiguration setzt GTK_THEME=%s für alle gestarteten Programme. Dieser Wert hat Vorrang vor dem hier gewählten GTK-Thema; die Datei wird von dieser Seite nicht verändert.' % lua['GTK_THEME'], 'row-desc'), False, False, 0)

    # --- Qt (nur Anzeige) ---
    app.section(box, 'Qt-Programme (nur Anzeige)')
    qt = qt_info()
    qenv = {k: v for k, v in lua.items() if k.startswith('QT_')}
    lines = ['%s: %s' % (k, v) for k, v in qenv.items()] + ['%s: %s' % (k, v) for k, v in qt.items()]
    if not qenv.get('QT_STYLE_OVERRIDE'):
        lines.insert(0, 'QT_STYLE_OVERRIDE: nicht gesetzt')
    kv = 'kvantummanager' if D.which('kvantummanager') else None
    lines.append('Kvantum: ' + ('installiert (kvantummanager)' if kv else 'nicht installiert'))
    lines.append('qt6ct: ' + ('installiert' if D.which('qt6ct') else 'nicht installiert'))
    box.pack_start(D.ui_label('\n'.join(lines), 'row-desc', selectable=True), False, False, 0)
    box.pack_start(D.ui_label('Die Qt-Umgebung wird in hypr/hyprland.lua beim Anmelden gesetzt, nicht aus einer Datei gelesen. Darum kann diese Seite sie nicht umschalten.', 'row-desc'), False, False, 0)

    # --- aktuelle Werte (gsettings gilt für GTK-Programme zuerst) nachladen ---
    def read_gs():
        out = {}
        if D.which('gsettings'):
            for key in ('cursor-theme', 'cursor-size', 'icon-theme', 'gtk-theme', 'color-scheme'):
                r = D.run_cmd(['gsettings', 'get', IFACE, key], 4)
                if r.returncode == 0:
                    out[key] = D.parse_gsettings(r.stdout)
        return out

    def got(gs):
        if isinstance(gs, Exception) or not gs:
            return
        st['sync'] = True
        try:
            if gs.get('cursor-theme') in cursors and 'cursor' in W:
                st['cursor'] = gs['cursor-theme']
                W['cursor'].set_active_id(st['cursor'])
            if str(gs.get('cursor-size', '')).isdigit() and 'size' in W and gs['cursor-size'] in W['size_ids']:
                st['size'] = int(gs['cursor-size'])
                W['size'].set_active_id(gs['cursor-size'])
            if gs.get('icon-theme') in icons and 'icons' in W:
                W['icons'].set_active_id(gs['icon-theme'])
            if gs.get('gtk-theme') in gtkth and 'gtk' in W:
                W['gtk'].set_active_id(gs['gtk-theme'])
            if 'color-scheme' in gs and 'dark' in W:
                gtk_sel['dark'] = gs['color-scheme'] == 'prefer-dark'
                W['dark'].set_active_id('dark' if gtk_sel['dark'] else 'light')
        finally:
            st['sync'] = False
    D.bg(read_gs, got)
    st['sync'] = False
    return box
