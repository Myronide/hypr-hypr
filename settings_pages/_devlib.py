"""Gemeinsame Helfer der Geräte-/Design-Seiten (Drucker, Benachrichtigungen, Design, Geräte).
Der obere Teil ist reine Logik ohne GTK (testbar ohne Anzeige); GTK wird erst in den ui_*-Funktionen geladen."""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')


def strip_ansi(text):
    return ANSI.sub('', text or '')


def which(name):
    return shutil.which(name)


def run_cmd(args, timeout=10, env=None, stdin_null=True):
    """Programm mit Zeitlimit. Fehlendes Programm (127) oder Zeitüberschreitung (124) ergeben ein Ergebnis statt einer Ausnahme."""
    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    try:
        return subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout, env=full_env,
                              stdin=subprocess.DEVNULL if stdin_null else None, errors='replace')
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, '', 'Zeitlimit überschritten')
    except (OSError, subprocess.SubprocessError, ValueError) as e:
        return subprocess.CompletedProcess(args, 127, '', str(e))


def C_LOCALE():
    """Umgebung für Programme, deren Ausgabe wir parsen (englische, stabile Meldungen)."""
    return {'LC_ALL': 'C', 'LANG': 'C', 'LANGUAGE': 'C'}


def config_home():
    return Path(os.environ.get('XDG_CONFIG_HOME') or (Path(os.environ.get('HOME') or str(Path.home())) / '.config'))


def home():
    return Path(os.environ.get('HOME') or str(Path.home()))


def atomic_write(path, text, backup_suffix=None):
    """Ersetzt die Datei atomar (Temp-Datei im selben Ordner). Ein Symlink wird aufgelöst (das Ziel wird ersetzt, nicht der Link).
    backup_suffix: einmalige Sicherung der bestehenden Datei (Name + Suffix), falls es noch keine gibt."""
    path = Path(path)
    if path.is_symlink():
        path = Path(os.path.realpath(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    if backup_suffix and path.exists():
        bak = path.with_name(path.name + backup_suffix)
        if not bak.exists():
            shutil.copy2(path, bak)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix='.' + path.name + '.', suffix='.tmp')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(text)
        try:
            os.chmod(tmp, (path.stat().st_mode & 0o777) if path.exists() else 0o644)
        except OSError:
            pass
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_text(path):
    try:
        return Path(path).read_text(encoding='utf-8', errors='replace')
    except OSError:
        return ''


# ---------- ini ----------
_SECTION = re.compile(r'^\s*\[([^\]]*)\]\s*$')


def ini_get(text, section, key):
    cur = None
    for line in (text or '').splitlines():
        m = _SECTION.match(line)
        if m:
            cur = m.group(1)
            continue
        if cur == section and '=' in line and not line.lstrip().startswith(('#', ';')):
            k, v = line.split('=', 1)
            if k.strip() == key:
                return v.strip()
    return None


def ini_set(text, section, key, value):
    """Setzt key=value im Abschnitt [section]; alle anderen Zeilen (auch Kommentare) bleiben unverändert.
    Fehlt der Abschnitt oder der Schlüssel, wird er angelegt."""
    value = str(value)
    if '\n' in value or '\r' in value or '\n' in key or '=' in key:
        raise ValueError('ungültiger ini-Eintrag')
    lines = (text or '').split('\n') if text else []
    had_nl = (text or '').endswith('\n')
    if had_nl:
        lines = lines[:-1]
    start = end = None
    for i, line in enumerate(lines):
        m = _SECTION.match(line)
        if m:
            if start is not None and end is None:
                end = i
            if m.group(1) == section and start is None:
                start = i
    if start is not None and end is None:
        end = len(lines)
    new = '%s=%s' % (key, value)
    if start is None:
        if lines and lines[-1].strip():
            lines.append('')
        lines += ['[%s]' % section, new]
    else:
        for i in range(start + 1, end):
            line = lines[i]
            if '=' in line and not line.lstrip().startswith(('#', ';')) and line.split('=', 1)[0].strip() == key:
                lines[i] = new
                break
        else:
            pos = end
            while pos > start + 1 and not lines[pos - 1].strip():
                pos -= 1
            lines.insert(pos, new)
    return '\n'.join(lines) + '\n'


def ini_update_file(path, section, items, backup_suffix=None):
    """Mehrere Schlüssel eines Abschnitts in einer ini-Datei setzen (atomar)."""
    text = read_text(path)
    for k, v in items:
        text = ini_set(text, section, k, v)
    atomic_write(path, text, backup_suffix)


def parse_gsettings(out):
    """'Papirus' -> Papirus, 24 -> '24', uint32 24 -> '24'."""
    s = (out or '').strip()
    if s.startswith('uint32 ') or s.startswith('int32 '):
        s = s.split(' ', 1)[1]
    if len(s) >= 2 and s[0] == s[-1] and s[0] in '\'"':
        s = s[1:-1]
    return s


# ---------- GTK ----------
def bg(fn, cb=None):
    """fn im Thread, cb(ergebnis) im GTK-Hauptfaden. Eine Ausnahme in fn kommt als Exception-Objekt an."""
    from gi.repository import GLib

    def work():
        try:
            res = fn()
        except Exception as e:  # noqa
            res = e
        if cb:
            def done():
                try:
                    cb(res)
                except Exception as e:  # noqa
                    print('Seite:', repr(e), file=sys.stderr)
                return False
            GLib.idle_add(done)
    threading.Thread(target=work, daemon=True).start()


def ui_clear(box):
    for c in box.get_children():
        box.remove(c)


def ui_label(text, css=None, selectable=False, mono=False):
    from gi.repository import Gtk, Pango
    l = Gtk.Label(label=text, xalign=0)
    l.set_line_wrap(True)
    l.set_selectable(selectable)
    if mono:
        l.override_font(Pango.FontDescription('monospace 9'))
    if css:
        l.get_style_context().add_class(css)
    return l


def ui_button(text, cb, destructive=False):
    from gi.repository import Gtk
    b = Gtk.Button(label=text)
    b.connect('clicked', lambda *_: cb())
    if destructive:
        b.get_style_context().add_class('destructive-action')
    return b


def ui_item(title, desc, *widgets):
    """Zeile für dynamische Listen (Aussehen wie app.row, ohne Eintrag in der Suche)."""
    from gi.repository import Gtk
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
    row.get_style_context().add_class('setting-row')
    labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
    labels.set_valign(Gtk.Align.CENTER)
    t = ui_label(title, 'row-title')
    t.set_max_width_chars(48)
    labels.pack_start(t, False, False, 0)
    if desc:
        d = ui_label(desc, 'row-desc')
        d.set_max_width_chars(70)
        labels.pack_start(d, False, False, 0)
    row.pack_start(labels, True, True, 0)
    bx = Gtk.Box(spacing=6)
    bx.set_valign(Gtk.Align.CENTER)
    for w in widgets:
        bx.pack_start(w, False, False, 0)
    row.pack_end(bx, False, False, 0)
    row.show_all()
    return row


def ui_select(items, active, cb):
    """Aufklappliste der Einstellungen (Select aus settings-app, sonst ComboBoxText). items: [(id, Text)]."""
    cls = getattr(sys.modules.get('__main__'), 'Select', None)
    if cls is None:
        from gi.repository import Gtk
        cls = Gtk.ComboBoxText
    w = cls()
    for i, t in items:
        w.append(i, t)
    if active is not None:
        w.set_active_id(active)
    w.connect('changed', lambda w: cb(w.get_active_id()))
    return w


def ui_choice(items, active, cb):
    cls = getattr(sys.modules.get('__main__'), 'Choice', None)
    if cls is None:
        return ui_select(items, active, cb)
    w = cls()
    for i, t in items:
        w.append(i, t)
    if active is not None:
        w.set_active_id(active)
    w.connect('changed', lambda w: cb(w.get_active_id()))
    return w


def ui_confirm(widget, text, ok='Ja'):
    from gi.repository import Gtk
    top = widget.get_toplevel()
    d = Gtk.MessageDialog(transient_for=top if isinstance(top, Gtk.Window) else None, modal=True,
                          message_type=Gtk.MessageType.QUESTION, text=text)
    d.add_button('Abbrechen', Gtk.ResponseType.CANCEL)
    d.add_button(ok, Gtk.ResponseType.OK)
    r = d.run()
    d.destroy()
    return r == Gtk.ResponseType.OK
