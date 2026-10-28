"""Aurora-Einstellungen: Standard-Apps (xdg-mime, xdg-settings, Terminal)."""
import os, sys, re, shutil, configparser
from pathlib import Path
_d = os.path.dirname(os.path.realpath(__file__))
if _d not in sys.path:
    sys.path.insert(0, _d)
import dx_sysutil as U

TITLE = 'Standard-Apps'
GROUP = 'PROGRAMME'
ICONS = ['preferences-desktop-default-applications-symbolic', 'application-x-executable-symbolic', 'view-app-grid-symbolic']
ORDER = 50

# Schlüssel -> (Titel, Beschreibung, Haupt-MIME-Typ, alle gesetzten MIME-Typen)
CATEGORIES = [
    ('browser', 'Webbrowser', 'Öffnet Internetadressen.', 'x-scheme-handler/http', ['x-scheme-handler/http', 'x-scheme-handler/https', 'text/html', 'application/xhtml+xml']),
    ('mail', 'E-Mail', 'Öffnet E-Mail-Adressen (mailto:).', 'x-scheme-handler/mailto', ['x-scheme-handler/mailto']),
    ('files', 'Dateimanager', 'Öffnet Ordner.', 'inode/directory', ['inode/directory']),
    ('terminal', 'Terminal', 'Wird für Befehle der Shell und des Systems verwendet.', None, []),
    ('text', 'Text', 'Textdateien.', 'text/plain', ['text/plain', 'text/markdown']),
    ('image', 'Bilder', 'Fotos und Grafiken.', 'image/png', ['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/bmp', 'image/svg+xml']),
    ('video', 'Videos', 'Filme und Aufnahmen.', 'video/mp4', ['video/mp4', 'video/x-matroska', 'video/webm', 'video/quicktime', 'video/x-msvideo']),
    ('audio', 'Musik', 'Audiodateien.', 'audio/mpeg', ['audio/mpeg', 'audio/flac', 'audio/ogg', 'audio/x-wav', 'audio/mp4']),
    ('pdf', 'PDF-Dokumente', '', 'application/pdf', ['application/pdf']),
    ('archive', 'Archive', 'ZIP, TAR, 7z, RAR …', 'application/zip', ['application/zip', 'application/x-tar', 'application/gzip', 'application/x-7z-compressed', 'application/vnd.rar']),
]
KNOWN_TERMINALS = ['ghostty', 'kitty', 'foot', 'alacritty', 'wezterm', 'konsole', 'gnome-terminal', 'xfce4-terminal', 'tilix', 'xterm']  # wie bin/dx-terminal

# ---------- reine Logik ----------

def parse_desktop(text, lang='de'):
    """Eintrag [Desktop Entry] einer .desktop-Datei -> Wörterbuch oder None (ungültig, kein Programm, versteckt)."""
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    try:
        cp.read_string(text or '')
    except configparser.Error:
        # nur den Abschnitt [Desktop Entry] retten
        m = re.search(r'^\[Desktop Entry\]\s*$(.*?)(?=^\[|\Z)', text or '', re.S | re.M)
        if not m:
            return None
        cp = configparser.RawConfigParser(strict=False, interpolation=None)
        cp.optionxform = str
        try:
            cp.read_string('[Desktop Entry]\n' + m.group(1))
        except configparser.Error:
            return None
    if not cp.has_section('Desktop Entry'):
        return None
    s = dict(cp.items('Desktop Entry'))
    if s.get('Type', 'Application') != 'Application':
        return None
    name = s.get('Name[%s]' % lang) or s.get('Name')
    if not name:
        return None
    flag = lambda k: s.get(k, '').strip().lower() == 'true'
    return {'name': name.strip(), 'icon': s.get('Icon', '').strip(), 'exec': s.get('Exec', '').strip(),
            'mimes': [m for m in s.get('MimeType', '').split(';') if m.strip()], 'hidden': flag('Hidden'), 'nodisplay': flag('NoDisplay')}


def app_dirs(env=None):
    env = os.environ if env is None else env
    home = Path(env.get('HOME', str(Path.home())))
    data_home = Path(env.get('XDG_DATA_HOME') or home / '.local/share')
    dirs = [data_home / 'applications']
    for d in (env.get('XDG_DATA_DIRS') or '/usr/local/share:/usr/share').split(':'):
        if d:
            dirs.append(Path(d) / 'applications')
    dirs += [Path('/var/lib/flatpak/exports/share/applications'), data_home / 'flatpak/exports/share/applications']
    seen, out = set(), []
    for d in dirs:
        if str(d) not in seen:
            seen.add(str(d))
            out.append(d)
    return out


def scan_apps(dirs=None, lang='de'):
    """Alle sichtbaren Programme: {desktop-id: Eintrag}. Frühere Ordner gewinnen (Nutzer vor System); defekte Dateien werden übersprungen."""
    apps = {}
    for base in (dirs if dirs is not None else app_dirs()):
        try:
            files = sorted(base.rglob('*.desktop'))
        except OSError:
            continue
        for f in files:
            did = str(f.relative_to(base)).replace('/', '-')
            if did in apps:
                continue
            try:
                e = parse_desktop(f.read_text(encoding='utf-8', errors='replace'), lang)
            except OSError:
                continue
            if e is None:
                continue
            e['id'] = did
            apps[did] = e   # auch versteckte merken, damit ein Nutzer-Eintrag mit Hidden=true das System-Programm verdeckt
    return {k: v for k, v in apps.items() if not v['hidden'] and not v['nodisplay']}


def candidates(apps, mime):
    """Programme, die den MIME-Typ behandeln, nach Name sortiert -> [(id, Name)]."""
    res = [(a['id'], a['name']) for a in apps.values() if mime in a['mimes']]
    return sorted(res, key=lambda t: (t[1].lower(), t[0]))


def installed_terminals(which=shutil.which):
    return [t for t in KNOWN_TERMINALS if which(t)]


def validate_desktop_id(did, apps):
    return isinstance(did, str) and did in apps and re.fullmatch(r'[A-Za-z0-9._+\-]+\.desktop', did) is not None


def validate_terminal(name, which=shutil.which):
    return isinstance(name, str) and name in KNOWN_TERMINALS and bool(which(name))


def build_set_default(key, did, apps):
    """Befehle (Liste von argv), die den Standard für die Kategorie setzen. Reihenfolge ausgeführt, kein pkexec nötig."""
    cat = next((c for c in CATEGORIES if c[0] == key), None)
    if cat is None or cat[3] is None:
        raise ValueError('Unbekannte Kategorie')
    if not validate_desktop_id(did, apps):
        raise ValueError('Unbekanntes Programm')
    cmds = []
    if key == 'browser':
        cmds.append(['xdg-settings', 'set', 'default-web-browser', did])
    cmds.append(['xdg-mime', 'default', did] + cat[4])
    return cmds


def parse_query_default(out):
    s = (out or '').strip().splitlines()
    return s[0].strip() if s and s[0].strip().endswith('.desktop') else ''


def terminal_file():
    return Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'draconyx' / 'terminal'


def current_terminal():
    try:
        return terminal_file().read_text(encoding='utf-8').splitlines()[0].strip()
    except (OSError, IndexError):
        return ''


def set_terminal(name, which=shutil.which):
    if not validate_terminal(name, which):
        raise ValueError('Unbekanntes oder nicht installiertes Terminal')
    U.atomic_write(terminal_file(), name + '\n')

# ---------- Seite ----------

def _fill(w, items, active):
    (w.clear if hasattr(w, 'clear') else w.remove_all)()
    for i, t in items:
        w.append(i, t)
    w.set_active_id(active or '')


def build(app):
    box = app.page(TITLE, 'Welches Programm Internetadressen, Dateien, Ordner und Medien öffnet. Wirkt für deinen Benutzer.')
    apps = {}
    sels, descs = {}, {}
    state = {'lock': True}

    def on_change(w, key):
        if state['lock']:
            return
        did = w.get_active_id()
        if not did:
            return
        try:
            cmds = build_set_default(key, did, apps)
        except ValueError as e:
            app.message(str(e))
            return

        def work():
            for c in cmds:
                rc, _, err = U.run(c, timeout=15)
                if rc != 0:
                    return err.strip() or 'Fehler %d' % rc
            return None
        U.bg(work, lambda res: app.message(('Standard gesetzt: %s' % apps[did]['name']) if res is None else 'Nicht geändert: %s' % res))

    def on_term(w):
        if state['lock'] or not w.get_active_id():
            return
        try:
            set_terminal(w.get_active_id())
            app.message('Terminal gespeichert.')
        except (ValueError, OSError) as e:
            app.message('Nicht gespeichert: %s' % e)

    for key, title, desc, mime, _all in CATEGORIES:
        w = U.make_select([('', 'Lade …')], '')
        w.connect('changed', (lambda w, _k=key: on_term(w)) if key == 'terminal' else (lambda w, _k=key: on_change(w, _k)))
        sels[key] = w
        app.row(box, title, w, desc + (' Gespeichert in ~/.config/draconyx/terminal.' if key == 'terminal' else ''))

    def work():
        found = scan_apps()
        cur = {}
        for key, _t, _d, mime, _a in CATEGORIES:
            if mime:
                rc, out, _ = U.run(['xdg-mime', 'query', 'default', mime], timeout=6)
                cur[key] = parse_query_default(out) if rc == 0 else ''
        return found, cur

    def done(res):
        if isinstance(res, Exception):
            app.message('Programme konnten nicht gelesen werden: %s' % res)
            state['lock'] = False
            return
        found, cur = res
        apps.update(found)
        for key, _t, _d, mime, _a in CATEGORIES:
            if key == 'terminal':
                terms = installed_terminals()
                c = current_terminal()
                _fill(sels[key], [(t, t) for t in terms] or [('', 'kein Terminal gefunden')], c if c in terms else (terms[0] if terms else ''))
                continue
            cands = candidates(apps, mime)
            c = cur.get(key, '')
            items = [] if c in dict(cands) else [('', '(nicht festgelegt)')] if not c else [(c, c + ' (nicht installiert)')]
            _fill(sels[key], items + cands, c)
        state['lock'] = False
        if not apps:
            app.message('Keine Programme gefunden (.desktop-Dateien fehlen).')
    U.bg(work, done)
