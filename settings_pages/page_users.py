"""Aurora-Einstellungen: Benutzer (Konto, Profilbild, Passwort, Sitzungen)."""
import os, sys, re, pwd, grp
from pathlib import Path
_d = os.path.dirname(os.path.realpath(__file__))
if _d not in sys.path:
    sys.path.insert(0, _d)
import dx_sysutil as U

TITLE = 'Benutzer'
GROUP = 'SYSTEM'
ICONS = ['system-users-symbolic', 'avatar-default-symbolic', 'user-info-symbolic']
ORDER = 40
FACE_SIZE = 256

# ---------- reine Logik ----------

def account_info(uid=None):
    """Kontodaten aus passwd/group (ohne Programmaufruf)."""
    uid = os.getuid() if uid is None else uid
    pw = pwd.getpwuid(uid)
    try:
        gids = os.getgrouplist(pw.pw_name, pw.pw_gid)
    except OSError:
        gids = [pw.pw_gid]
    groups = []
    for g in gids:
        try:
            groups.append(grp.getgrgid(g).gr_name)
        except KeyError:
            groups.append(str(g))
    return {'login': pw.pw_name, 'name': pw.pw_gecos.split(',')[0], 'home': pw.pw_dir, 'shell': pw.pw_shell, 'uid': pw.pw_uid, 'groups': sorted(set(groups))}


def validate_login(login):
    return isinstance(login, str) and re.fullmatch(r'[a-z_][a-z0-9_\-]{0,31}\$?', login) is not None


def validate_display_name(name):
    """Anzeigename (GECOS-Feld): 1–100 Zeichen, ohne Doppelpunkt, Komma, Gleichheitszeichen, Zeilenumbruch und Steuerzeichen. -> bereinigter Text oder None."""
    if not isinstance(name, str):
        return None
    n = name.strip()
    if not n or len(n) > 100 or re.search(r'[:,=\x00-\x1f\x7f]', n):
        return None
    return n


def build_set_fullname(login, name):
    if not validate_login(login):
        raise ValueError('Ungültiger Benutzername')
    n = validate_display_name(name)
    if n is None:
        raise ValueError('Ungültiger Anzeigename (keine Doppelpunkte, Kommas oder Gleichheitszeichen)')
    return U.pk(['usermod', '-c', n, '--', login])


def square_crop(w, h):
    """(x, y, Kantenlänge) des mittigen Quadrats."""
    s = min(w, h)
    return (w - s) // 2, (h - s) // 2, s


def parse_sessions(text):
    """`loginctl list-sessions --no-legend` -> [{'id','uid','user','seat','tty'}]; unvollständige Zeilen werden übersprungen."""
    out = []
    for line in (text or '').splitlines():
        p = line.split()
        if len(p) >= 3 and p[0].isalnum() and p[1].isdigit():
            out.append({'id': p[0], 'uid': p[1], 'user': p[2], 'seat': p[3] if len(p) > 3 else '', 'tty': p[4] if len(p) > 4 else ''})
    return out


def parse_session_show(text):
    kv = U.parse_kv(text)
    return {'type': kv.get('Type', ''), 'state': kv.get('State', ''), 'active': kv.get('Active', '') == 'yes', 'remote': kv.get('Remote', '') == 'yes', 'service': kv.get('Service', '')}


def password_command():
    t = U.find_bin('dx-terminal')
    return [t, '--', 'passwd'] if t else None


def save_face(src, dest=None):
    """Bild laden, mittig quadratisch zuschneiden, auf 256x256 skalieren, als PNG atomar nach ~/.face schreiben."""
    import gi
    gi.require_version('GdkPixbuf', '2.0')
    from gi.repository import GdkPixbuf
    import tempfile
    dest = Path(dest) if dest else Path.home() / '.face'
    pb = GdkPixbuf.Pixbuf.new_from_file(str(src))
    x, y, s = square_crop(pb.get_width(), pb.get_height())
    pb = pb.new_subpixbuf(x, y, s, s).scale_simple(FACE_SIZE, FACE_SIZE, GdkPixbuf.InterpType.BILINEAR)
    fd, tmp = tempfile.mkstemp(dir=str(dest.parent), prefix='.face.', suffix='.png')
    os.close(fd)
    try:
        pb.savev(tmp, 'png', [], [])
        os.replace(tmp, dest)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return dest

# ---------- Seite ----------

def build(app):
    from gi.repository import Gtk, GdkPixbuf
    try:
        info = account_info()
    except (KeyError, OSError) as e:
        app.page(TITLE, 'Konto des angemeldeten Benutzers.')
        return
    box = app.page(TITLE, 'Konto, Profilbild, Passwort und angemeldete Sitzungen des aktuellen Benutzers.')
    face_path = Path.home() / '.face'

    img = Gtk.Image()
    img.set_pixel_size(96)

    def load_face():
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_size(str(face_path), 96, 96)
            img.set_from_pixbuf(pb)
        except Exception:
            img.set_from_icon_name('avatar-default-symbolic', Gtk.IconSize.DIALOG)
            img.set_pixel_size(96)
    load_face()
    fb = Gtk.Box(spacing=14)
    fb.pack_start(img, False, False, 0)
    pick = Gtk.Button(label='Bild wählen …')
    pick.set_valign(Gtk.Align.CENTER)

    def choose(*_):
        d = Gtk.FileChooserDialog(title='Profilbild wählen', parent=app.window, action=Gtk.FileChooserAction.OPEN)
        d.add_buttons('Abbrechen', Gtk.ResponseType.CANCEL, 'Wählen', Gtk.ResponseType.OK)
        f = Gtk.FileFilter()
        f.set_name('Bilder')
        f.add_pixbuf_formats()
        d.add_filter(f)
        ok = d.run() == Gtk.ResponseType.OK
        path = d.get_filename()
        d.destroy()
        if not ok or not path:
            return
        try:
            save_face(path)
            load_face()
            app.message('Profilbild gespeichert (%d×%d).' % (FACE_SIZE, FACE_SIZE))
        except Exception as e:
            app.message('Bild konnte nicht verwendet werden: %s' % e)
    pick.connect('clicked', choose)
    fb.pack_start(pick, False, False, 0)
    app.row(box, 'Profilbild', fb, 'Wird als ~/.face gespeichert (mittig quadratisch zugeschnitten, 256×256).')

    name_lbl = U.info_label(info['name'] or '–')
    app.row(box, 'Name', name_lbl, 'Anzeigename des Kontos.')
    app.row(box, 'Benutzername', U.info_label(info['login']), 'Anmeldename (nur Anzeige).')
    app.row(box, 'Heimordner', U.info_label(info['home']), '')
    app.row(box, 'Shell', U.info_label(info['shell']), 'Anmelde-Shell im Terminal.')
    app.row(box, 'Gruppen', U.info_label(', '.join(info['groups']) or '–'), 'Nur Anzeige.')

    ne = Gtk.Entry()
    ne.set_text(info['name'])
    ne.set_width_chars(24)
    nb = Gtk.Button(label='Speichern')
    nbox = Gtk.Box(spacing=8)
    nbox.pack_start(ne, False, False, 0)
    nbox.pack_start(nb, False, False, 0)
    busy = {'v': False}

    def save_name(*_):
        if busy['v']:
            return
        try:
            args = build_set_fullname(info['login'], ne.get_text())
        except ValueError as e:
            app.message(str(e))
            return
        busy['v'] = True
        app.message('Warte auf Berechtigung …')

        def done(res):
            busy['v'] = False
            if isinstance(res, Exception):
                app.message('Fehler: %s' % res)
            elif res[0] == 0:
                name_lbl.set_text(ne.get_text().strip())
                app.message('Anzeigename geändert.')
            else:
                app.message('Nicht geändert (%s)' % ((res[2] or '').strip().splitlines()[-1:] or ['abgebrochen'])[0])
        U.bg(lambda: U.run(args, timeout=120), done)
    nb.connect('clicked', save_name)
    app.row(box, 'Anzeigename ändern', nbox, 'Braucht Administratorrechte. Keine Doppelpunkte, Kommas oder Gleichheitszeichen.')

    def pw():
        cmd = password_command()
        if not cmd:
            app.message('dx-terminal wurde nicht gefunden – im Terminal „passwd“ ausführen.')
            return
        import subprocess
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            app.message('Ein Terminal mit „passwd“ wurde geöffnet.')
        except OSError as e:
            app.message('Terminal konnte nicht gestartet werden: %s' % e)
    app.button(box, 'Passwort ändern', 'Terminal öffnen', pw, 'Öffnet dein Terminal mit „passwd“. Das Passwort wird nur dort eingegeben.')

    sess = U.info_label('Lese Sitzungen …')
    app.row(box, 'Angemeldete Sitzungen', sess, 'Laut loginctl, nur Anzeige.')

    def work():
        rc, out, _ = U.run(['loginctl', 'list-sessions', '--no-legend'])
        if rc != 0:
            return None
        lines = []
        for s in parse_sessions(out):
            rc2, o2, _ = U.run(['loginctl', 'show-session', s['id'], '-p', 'Type', '-p', 'State', '-p', 'Active', '-p', 'Remote', '-p', 'Service'])
            d = parse_session_show(o2) if rc2 == 0 else {}
            lines.append('%s · %s · %s%s%s' % (s['user'], 'Sitzung ' + s['id'], d.get('type') or '?', ' · Seat ' + s['seat'] if s['seat'] else '', ' · entfernt' if d.get('remote') else ''))
        return lines

    def done(lines):
        if isinstance(lines, list):
            sess.set_text('\n'.join(lines) or 'Keine Sitzung gefunden.')
        else:
            sess.set_text('loginctl ist nicht verfügbar.')
    U.bg(work, done)
