"""Gemeinsame Helfer der Systemseiten (Datum & Zeit, Region, Benutzer, Standard-Apps, Über). Keine Seite selbst (kein page_-Name).
Reine Logik hier und in den Seiten ist ohne Display testbar; GTK wird nur in den build()-Funktionen angefasst."""
import os, sys, json, shutil, subprocess, tempfile, threading, fcntl, shlex
from pathlib import Path

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, GLib
except Exception:   # kein GTK (Tests ohne Display): die Logik bleibt benutzbar
    Gtk = GLib = None


def run(args, timeout=8, input_text=None, env=None):
    """(Rückgabecode, stdout, stderr). Fehlendes Programm / Zeitüberschreitung -> Code 127 bzw. 124, nie eine Ausnahme."""
    if not args or (shutil.which(str(args[0])) is None and not os.path.isabs(str(args[0]))):
        return 127, '', 'Programm nicht gefunden: %s' % (args[0] if args else '')
    try:
        r = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout, input=input_text, env=env)
        return r.returncode, r.stdout or '', r.stderr or ''
    except subprocess.TimeoutExpired:
        return 124, '', 'Zeitüberschreitung'
    except (OSError, subprocess.SubprocessError, ValueError) as e:
        return 127, '', str(e)


def quote_cmd(args):
    """Anzeige eines Befehls mit sicherem Quoting."""
    return ' '.join(shlex.quote(str(a)) for a in args)


def atomic_write(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix='.' + path.name + '.', suffix='.tmp')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def shell_settings_path():
    return Path(os.environ.get('XDG_STATE_HOME') or (Path.home() / '.local/state')) / 'draconyx' / 'settings.json'


def shell_get(key, default=None, path=None):
    path = Path(path) if path else shell_settings_path()
    try:
        data = json.loads(path.read_text(encoding='utf-8') or '{}')
    except (OSError, ValueError):
        return default
    return data.get(key, default) if isinstance(data, dict) else default


def shell_update(changes, path=None):
    """Nur die genannten Schlüssel setzen: unter Dateisperre frisch lesen, ändern, atomar ersetzen (kein Lost-Update).
    Unlesbare Datei -> ValueError, nichts wird überschrieben (Kopie *.defekt)."""
    path = Path(path) if path else shell_settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(str(path) + '.lock', 'a') as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            try:
                text = path.read_text(encoding='utf-8')
            except FileNotFoundError:
                text = ''
            if text.strip():
                try:
                    data = json.loads(text)
                except ValueError:
                    data = None
                if not isinstance(data, dict):
                    try:
                        shutil.copy2(path, str(path) + '.defekt')
                    except OSError:
                        pass
                    raise ValueError('settings.json der Shell ist nicht lesbar – nichts geändert')
            else:
                data = {}
            data.update(changes)
            atomic_write(path, json.dumps(data, indent=4))
        finally:
            fcntl.flock(lk, fcntl.LOCK_UN)
    return True


def fmt_bytes(n):
    try:
        n = float(n)
    except (TypeError, ValueError):
        return '?'
    for u in ('B', 'KiB', 'MiB', 'GiB', 'TiB'):
        if n < 1024 or u == 'TiB':
            return ('%d %s' % (n, u)) if u == 'B' else ('%.1f %s' % (n, u)).replace('.', ',')
        n /= 1024


def parse_kv(text, sep='='):
    out = {}
    for line in (text or '').splitlines():
        if sep in line:
            k, v = line.split(sep, 1)
            out[k.strip()] = v.strip()
    return out


def bg(work, done):
    """work() im Thread, done(ergebnis) danach im GTK-Hauptthread. Ausnahmen in work werden als Ergebnis (Exception) geliefert."""
    def th():
        try:
            res = work()
        except Exception as e:   # noqa: BLE001 – die UI darf nie wegen eines Hintergrundfehlers hängen
            res = e
        if GLib is not None:
            GLib.idle_add(lambda: (done(res), False)[1])
        else:
            done(res)
    threading.Thread(target=th, daemon=True).start()


def make_select(items, active=None):
    """Aufklappliste: bevorzugt die Select-Klasse der Einstellungen (Popover), sonst ComboBoxText. items: [(id, Text)]."""
    cls = getattr(sys.modules.get('__main__'), 'Select', None)
    w = cls() if cls else Gtk.ComboBoxText()
    for i, t in items:
        w.append(i, t)
    if active is not None:
        w.set_active_id(active)
    return w


def info_label(text='', selectable=True):
    l = Gtk.Label(label=text, xalign=0)
    l.set_line_wrap(True)
    l.set_selectable(selectable)
    return l


def confirm(app, title, text):
    d = Gtk.MessageDialog(transient_for=app.window, modal=True, message_type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.OK_CANCEL, text=title)
    d.format_secondary_text(text)
    r = d.run()
    d.destroy()
    return r == Gtk.ResponseType.OK


def find_bin(name):
    """bin/<name> aus dem Repo/der Installation, sonst PATH."""
    here = Path(os.path.realpath(__file__)).parent
    for p in (here.parent / 'bin' / name, Path.home() / '.local/bin' / name):
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
    return shutil.which(name)


def pk(args):
    """Befehl mit Rechteerhöhung (nur auf ausdrücklichen Klick aufrufen)."""
    return ['pkexec'] + [str(a) for a in args]
