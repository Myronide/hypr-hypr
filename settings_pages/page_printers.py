"""Aurora-Einstellungen: Drucker & Scanner (CUPS, SANE). Reine Logik oben (testbar), GTK-Oberfläche in build()."""
import os
import re
import shlex
import sys
from urllib.parse import unquote, urlsplit

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import _devlib as D  # noqa: E402

TITLE = 'Drucker & Scanner'
GROUP = 'SYSTEM'
ICONS = ['printer-symbolic', 'printer']
ORDER = 40

PACKAGES = 'cups, cups-filters (für Netzwerkdrucker zusätzlich avahi und nss-mdns, für Scanner sane und sane-airscan)'
NAME_RE = re.compile(r'^[A-Za-z0-9_][A-Za-z0-9_-]{0,126}$')
JOB_RE = re.compile(r'^[A-Za-z0-9_.@:-]+-\d+$')
URI_RE = re.compile(r'^(ipp|ipps|http|https|socket|lpd|dnssd|usb|smb|hp|hpfax|beh)://\S+$')
DRIVER_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.:+/@-]{0,199}$')
TESTPAGE = '/usr/share/cups/data/testprint'


# ---------- reine Logik ----------
def parse_printers(text):
    """Ausgabe von `lpstat -p -d -l` (LC_ALL=C) -> (Druckerliste, Standarddrucker oder None)."""
    printers, default, cur = [], None, None
    for line in (text or '').splitlines():
        m = re.match(r'^printer (\S+) (.*)$', line)
        if m:
            rest = m.group(2)
            low = rest.lower()
            state = 'idle'
            if low.startswith('disabled') or ' disabled ' in low:
                state = 'disabled'
            elif low.startswith('now printing'):
                state = 'printing'
            cur = {'name': m.group(1), 'state': state, 'status': rest.strip(), 'description': '', 'location': '', 'connection': '', 'uri': ''}
            printers.append(cur)
            continue
        m = re.match(r'^system default destination: (\S+)\s*$', line)
        if m:
            default = m.group(1)
            cur = None
            continue
        if cur is not None and line[:1] in ('\t', ' '):
            k, _, v = line.strip().partition(':')
            k = k.strip().lower()
            if k == 'description':
                cur['description'] = v.strip()
            elif k == 'location':
                cur['location'] = v.strip()
            elif k == 'connection':
                cur['connection'] = v.strip()
    return printers, default


def parse_device_uris(text):
    """`lpstat -v`: 'device for NAME: URI' -> {name: uri}."""
    out = {}
    for line in (text or '').splitlines():
        m = re.match(r'^device for (\S+): (\S+)\s*$', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def parse_jobs(text):
    """`lpstat -o` -> [{id, printer, user, size, when}]."""
    jobs = []
    for line in (text or '').splitlines():
        m = re.match(r'^(\S+)-(\d+)\s+(\S+)\s+(\d+)\s+(.*)$', line)
        if m:
            jobs.append({'id': '%s-%s' % (m.group(1), m.group(2)), 'printer': m.group(1), 'user': m.group(3),
                         'size': int(m.group(4)), 'when': m.group(5).strip()})
    return jobs


def parse_devices(text):
    """`lpinfo -v` -> [{cls, uri, label}], generische Einträge ohne Gerät (z. B. 'socket', 'lpd') entfallen."""
    devs, seen = [], set()
    for line in (text or '').splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            continue
        cls, uri = parts
        if cls not in ('network', 'direct', 'file', 'serial') or '://' not in uri:
            continue
        sp = urlsplit(uri)
        if not (sp.netloc or sp.path.strip('/')) or uri in seen:
            continue
        seen.add(uri)
        devs.append({'cls': cls, 'uri': uri, 'label': device_label(uri)})
    return devs


def device_label(uri):
    sp = urlsplit(uri)
    host = unquote(sp.netloc)
    if sp.scheme == 'dnssd':
        return re.sub(r'\._(ipp|ipps|printer|pdl-datastream)\._tcp.*$', '', host) + ' (Netzwerk)'
    if sp.scheme == 'usb':
        model = unquote(sp.path.strip('/').split('?')[0])
        return (host + ' ' + model).strip() + ' (USB)'
    return host + (unquote(sp.path) if sp.path else '') + ' (%s)' % sp.scheme


def parse_models(text, needle='', limit=300):
    """`lpinfo -m` -> [(id, Beschreibung)], gefiltert nach needle (Groß/Klein egal)."""
    out, n = [], needle.lower().split()
    for line in (text or '').splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and DRIVER_RE.match(parts[0]):
            hay = (parts[0] + ' ' + parts[1]).lower()
            if all(w in hay for w in n):
                out.append((parts[0], parts[1]))
                if len(out) >= limit:
                    break
    return out


def parse_scanners(text):
    """`scanimage -L` -> [Beschreibung]."""
    out = []
    for line in (text or '').splitlines():
        m = re.match(r"^device [`'](.+?)' is a (.+)$", line.strip())
        if m:
            out.append('%s  (%s)' % (m.group(2).strip(), m.group(1)))
    return out


def parse_service(text):
    """`systemctl show cups.service -p LoadState -p ActiveState` -> 'active' | 'inactive' | 'missing'."""
    d = dict(l.split('=', 1) for l in (text or '').splitlines() if '=' in l)
    if d.get('LoadState', '') in ('not-found', ''):
        return 'missing'
    return 'active' if d.get('ActiveState') == 'active' else 'inactive'


def suggest_name(label):
    s = re.sub(r'\(.*?\)', '', label)
    s = re.sub(r'[^A-Za-z0-9_-]+', '_', s).strip('_')
    return s[:60] or 'Drucker'


def valid_name(n):
    return bool(NAME_RE.match(n or ''))


def valid_uri(u):
    return bool(URI_RE.match(u or ''))


def cmd_add(name, uri, driver):
    """lpadmin-Aufruf zum Hinzufügen; 'everywhere' = treiberlos (IPP Everywhere)."""
    if not valid_name(name):
        raise ValueError('Ungültiger Druckername (erlaubt: Buchstaben, Ziffern, _ und -).')
    if not valid_uri(uri):
        raise ValueError('Ungültige Geräteadresse.')
    if driver != 'everywhere' and not DRIVER_RE.match(driver or ''):
        raise ValueError('Ungültiger Treiber.')
    return ['lpadmin', '-p', name, '-E', '-v', uri, '-m', driver]


def cmd_default(name):
    if not valid_name(name):
        raise ValueError('Ungültiger Druckername.')
    return ['lpoptions', '-d', name]


def cmd_remove(name):
    if not valid_name(name):
        raise ValueError('Ungültiger Druckername.')
    return ['lpadmin', '-x', name]


def cmd_testpage(name, testfile=TESTPAGE):
    if not valid_name(name):
        raise ValueError('Ungültiger Druckername.')
    return ['lp', '-d', name, '-t', 'Testseite (Aurora)', testfile]


def cmd_cancel(job):
    if not JOB_RE.match(job or ''):
        raise ValueError('Ungültige Auftragsnummer.')
    return ['cancel', job]


def cmd_enable_cups():
    return ['pkexec', 'systemctl', 'enable', '--now', 'cups.service']


def human_error(res):
    msg = (res.stderr or res.stdout or '').strip().splitlines()
    msg = msg[-1] if msg else 'Fehler %s' % res.returncode
    low = msg.lower()
    if 'forbidden' in low or 'unauthorized' in low or 'not authorized' in low:
        msg += ' – dafür fehlt die Berechtigung (Konto muss in der Gruppe „sys“/„wheel“ bzw. „lpadmin“ sein).'
    elif 'scheduler is not running' in low or 'bad file descriptor' in low:
        msg += ' – der Druckdienst läuft nicht.'
    return msg


# ---------- Oberfläche ----------
def build(app):
    from gi.repository import Gtk, GLib
    box = app.page(TITLE, 'Drucker einrichten, Standarddrucker wählen, Testseite drucken, Druckaufträge verwalten und Scanner anzeigen (CUPS, SANE).')
    st = {'driver_items': [('everywhere', 'Treiberlos (IPP Everywhere)')], 'devices': [], 'loaded': False, 'busy': False}

    def say(t):
        app.message(t)

    # --- Status ---
    app.section(box, 'Druckdienst')
    status_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(status_box, False, False, 0)
    app.section(box, 'Drucker')
    list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(list_box, False, False, 0)
    app.section(box, 'Druckaufträge')
    jobs_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(jobs_box, False, False, 0)
    app.section(box, 'Drucker hinzufügen')
    add_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(add_box, False, False, 0)
    app.section(box, 'Scanner')
    scan_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(scan_box, False, False, 0)

    def run_action(argv, ok_msg, after=None, timeout=30):
        say('Wird ausgeführt …')

        def work():
            return D.run_cmd(argv, timeout, env=D.C_LOCALE())

        def done(res):
            if isinstance(res, Exception) or res.returncode != 0:
                say('Fehlgeschlagen: ' + (str(res) if isinstance(res, Exception) else human_error(res)))
            else:
                say(ok_msg)
            if after:
                after()
        D.bg(work, done)

    # --- Status/Liste/Aufträge laden ---
    def refresh(*_):
        if st['busy']:
            return
        st['busy'] = True

        def work():
            r = {'have': bool(D.which('lpstat')), 'service': 'missing', 'printers': [], 'default': None, 'jobs': [], 'uris': {}, 'running': False}
            if not r['have']:
                return r
            sv = D.run_cmd(['systemctl', 'show', 'cups.service', '-p', 'LoadState', '-p', 'ActiveState'], 5)
            r['service'] = parse_service(sv.stdout) if sv.returncode == 0 else 'missing'
            chk = D.run_cmd(['lpstat', '-r'], 6, env=D.C_LOCALE())
            r['running'] = 'is running' in (chk.stdout or '') and 'not running' not in (chk.stdout or '')
            if r['running']:
                r['printers'], r['default'] = parse_printers(D.run_cmd(['lpstat', '-p', '-d', '-l'], 10, env=D.C_LOCALE()).stdout)
                r['uris'] = parse_device_uris(D.run_cmd(['lpstat', '-v'], 10, env=D.C_LOCALE()).stdout)
                r['jobs'] = parse_jobs(D.run_cmd(['lpstat', '-o'], 10, env=D.C_LOCALE()).stdout)
            return r

        def done(r):
            st['busy'] = False
            if isinstance(r, Exception):
                say('Druckerstatus konnte nicht gelesen werden: %s' % r)
                return
            show(r)
        D.bg(work, done)

    def enable_cups():
        if not D.which('pkexec'):
            say('pkexec fehlt – Dienst bitte im Terminal mit „sudo systemctl enable --now cups“ starten.')
            return
        run_action(cmd_enable_cups(), 'Druckdienst aktiviert.', refresh, timeout=120)

    def show(r):
        D.ui_clear(status_box)
        D.ui_clear(list_box)
        D.ui_clear(jobs_box)
        if not r['have']:
            status_box.pack_start(D.ui_item('CUPS ist nicht installiert', 'Zum Drucken werden diese Pakete benötigt: ' + PACKAGES + '. Installation z. B. mit „sudo pacman -S cups cups-filters“.'), False, False, 0)
            list_box.pack_start(D.ui_label('Ohne CUPS gibt es keine Druckerliste.', 'row-desc'), False, False, 0)
            list_box.show_all()
            status_box.show_all()
            return
        if r['running']:
            status_box.pack_start(D.ui_item('Druckdienst läuft', 'cups.service ist aktiv.', D.ui_button('Aktualisieren', refresh)), False, False, 0)
        elif r['service'] == 'missing':
            status_box.pack_start(D.ui_item('Druckdienst nicht gefunden', 'Die Programme sind da, aber es gibt keine Dienstdatei cups.service. Fehlt das Paket „cups“? Benötigt: ' + PACKAGES + '.', D.ui_button('Aktualisieren', refresh)), False, False, 0)
        else:
            status_box.pack_start(D.ui_item('Druckdienst läuft nicht', 'Zum Drucken muss cups.service laufen. Der Knopf aktiviert ihn dauerhaft (Passwortabfrage durch pkexec).', D.ui_button('Aktivieren und starten', enable_cups)), False, False, 0)
        if not r['running']:
            list_box.pack_start(D.ui_label('Solange der Druckdienst nicht läuft, gibt es keine Druckerliste.', 'row-desc'), False, False, 0)
        elif not r['printers']:
            list_box.pack_start(D.ui_label('Es ist noch kein Drucker eingerichtet. Unten kann einer hinzugefügt werden.', 'row-desc'), False, False, 0)
        for p in r['printers']:
            def mk(p=p):
                name = p['name']
                desc = ' · '.join(x for x in [{'idle': 'bereit', 'printing': 'druckt', 'disabled': 'angehalten'}.get(p['state'], p['state']),
                                              p['description'], p['location'], r['uris'].get(name, '')] if x)
                title = name + ('  (Standard)' if name == r['default'] else '')
                ws = []
                if name != r['default']:
                    ws.append(D.ui_button('Als Standard', lambda: set_default(name)))
                ws.append(D.ui_button('Testseite', lambda: test_page(name)))
                ws.append(D.ui_button('Entfernen', lambda: remove(name), True))
                return D.ui_item(title, desc, *ws)
            list_box.pack_start(mk(), False, False, 0)
        if r['running'] and not r['jobs']:
            jobs_box.pack_start(D.ui_label('Keine offenen Druckaufträge.', 'row-desc'), False, False, 0)
        for j in r['jobs']:
            def mkj(j=j):
                return D.ui_item('%s  (%s)' % (j['id'], j['user']), '%d Byte · %s' % (j['size'], j['when']), D.ui_button('Abbrechen', lambda: cancel(j['id'])))
            jobs_box.pack_start(mkj(), False, False, 0)
        for b in (status_box, list_box, jobs_box):
            b.show_all()

    def set_default(name):
        try:
            argv = cmd_default(name)
        except ValueError as e:
            return say(str(e))
        run_action(argv, '„%s“ ist jetzt der Standarddrucker.' % name, refresh)

    def test_page(name):
        if not os.path.exists(TESTPAGE):
            return say('Testseite %s nicht gefunden (Paket cups).' % TESTPAGE)
        try:
            argv = cmd_testpage(name)
        except ValueError as e:
            return say(str(e))
        run_action(argv, 'Testseite an „%s“ gesendet.' % name, refresh)

    def remove(name):
        if not D.ui_confirm(box, 'Drucker „%s“ wirklich entfernen?' % name, 'Entfernen'):
            return
        try:
            argv = cmd_remove(name)
        except ValueError as e:
            return say(str(e))
        run_action(argv, 'Drucker „%s“ entfernt.' % name, refresh)

    def cancel(job):
        try:
            argv = cmd_cancel(job)
        except ValueError as e:
            return say(str(e))
        run_action(argv, 'Auftrag %s abgebrochen.' % job, refresh)

    # --- Drucker hinzufügen ---
    dev_holder = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    name_entry = Gtk.Entry(placeholder_text='Name, z. B. Buerodrucker', width_chars=26)
    uri_entry = Gtk.Entry(placeholder_text='ipp://adresse/ipp/print', width_chars=34)
    search_entry = Gtk.Entry(placeholder_text='Hersteller/Modell filtern', width_chars=26)
    drv = {'sel': 'everywhere', 'text': ''}
    st['model_text'] = ''
    sel_dev = {'uri': None}

    def pick_device(i):
        d = next((x for x in st['devices'] if x['uri'] == i), None)
        if d:
            uri_entry.set_text(d['uri'])
            if not name_entry.get_text().strip():
                name_entry.set_text(suggest_name(d['label']))

    def rebuild_dev_select():
        D.ui_clear(dev_holder)
        if not st['devices']:
            dev_holder.pack_start(D.ui_label('Noch nichts gesucht oder nichts gefunden.', 'row-desc'), False, False, 0)
        else:
            items = [(d['uri'], d['label']) for d in st['devices']]
            dev_holder.pack_start(D.ui_select(items, None, pick_device), False, False, 0)
        dev_holder.show_all()

    def search_devices():
        if not D.which('lpinfo'):
            return say('lpinfo fehlt – Paket cups installieren.')
        say('Suche nach Druckern (kann bis zu 40 Sekunden dauern) …')

        def work():
            return D.run_cmd(['lpinfo', '--include-schemes', 'dnssd,usb,ipp,ipps', '-v'], 40, env=D.C_LOCALE())

        def done(res):
            if isinstance(res, Exception) or res.returncode != 0:
                say('Suche fehlgeschlagen: ' + (str(res) if isinstance(res, Exception) else human_error(res)))
                return
            st['devices'] = parse_devices(res.stdout)
            rebuild_dev_select()
            say('%d Gerät(e) gefunden.' % len(st['devices']))
        D.bg(work, done)

    drv_holder = Gtk.Box(spacing=6)

    def rebuild_drv():
        D.ui_clear(drv_holder)
        drv_holder.pack_start(D.ui_select(st['driver_items'], drv['sel'], lambda i: drv.__setitem__('sel', i or 'everywhere')), False, False, 0)
        drv_holder.show_all()

    def load_models():
        if not D.which('lpinfo'):
            return say('lpinfo fehlt – Paket cups installieren.')
        needle = search_entry.get_text().strip()
        if len(needle) < 2:
            return say('Bitte zuerst Hersteller oder Modell eintragen, um die lange Treiberliste zu filtern.')
        say('Treiberliste wird geladen …')

        def work():
            return D.run_cmd(['lpinfo', '-m'], 60, env=D.C_LOCALE())

        def done(res):
            if isinstance(res, Exception) or res.returncode != 0:
                return say('Treiberliste fehlgeschlagen: ' + (str(res) if isinstance(res, Exception) else human_error(res)))
            found = parse_models(res.stdout, needle)
            st['driver_items'] = [('everywhere', 'Treiberlos (IPP Everywhere)')] + found
            drv['sel'] = 'everywhere'
            rebuild_drv()
            say('%d passende Treiber.' % len(found))
        D.bg(work, done)

    def add_printer():
        name, uri = name_entry.get_text().strip(), uri_entry.get_text().strip()
        try:
            argv = cmd_add(name, uri, drv['sel'])
        except ValueError as e:
            return say(str(e))
        if not D.which('lpadmin'):
            return say('lpadmin fehlt – Paket cups installieren.')
        run_action(argv, 'Drucker „%s“ hinzugefügt.' % name, refresh, timeout=90)

    add_box.pack_start(D.ui_item('Gefundene Geräte', 'Sucht Netzwerkdrucker (Bonjour/dnssd) und per USB angeschlossene Drucker. Dafür muss der Druckdienst laufen; bei Netzwerkdruckern auch avahi.', D.ui_button('Suchen', search_devices)), False, False, 0)
    add_box.pack_start(dev_holder, False, False, 0)
    add_box.pack_start(D.ui_item('Adresse des Druckers', 'Aus der Liste übernommen oder von Hand, z. B. ipp://192.168.1.20/ipp/print oder socket://192.168.1.20:9100.', uri_entry), False, False, 0)
    add_box.pack_start(D.ui_item('Name', 'Nur Buchstaben, Ziffern, _ und -.', name_entry), False, False, 0)
    add_box.pack_start(D.ui_item('Treiber', 'Standard ist treiberlos (IPP Everywhere) und passt für die meisten Netzwerkdrucker seit etwa 2015. Für ältere Geräte einen Treiber suchen.', search_entry, D.ui_button('Treiber suchen', load_models)), False, False, 0)
    add_box.pack_start(drv_holder, False, False, 0)
    add_box.pack_start(D.ui_item('Drucker einrichten', 'Legt den Drucker in CUPS an und schaltet ihn ein (braucht die Berechtigung zur Druckerverwaltung).', D.ui_button('Hinzufügen', add_printer)), False, False, 0)
    rebuild_dev_select()
    rebuild_drv()
    add_box.show_all()

    # --- Scanner (nur Anzeige) ---
    def scan():
        D.ui_clear(scan_box)
        if not D.which('scanimage'):
            scan_box.pack_start(D.ui_item('SANE ist nicht installiert', 'Zum Anzeigen von Scannern wird das Paket „sane“ benötigt (für Netzwerkscanner zusätzlich „sane-airscan“).'), False, False, 0)
            scan_box.show_all()
            return
        scan_box.pack_start(D.ui_label('Suche nach Scannern …', 'row-desc'), False, False, 0)
        scan_box.show_all()

        def work():
            return D.run_cmd(['scanimage', '-L'], 15, env=D.C_LOCALE())

        def done(res):
            D.ui_clear(scan_box)
            found = [] if isinstance(res, Exception) else parse_scanners(res.stdout)
            if found:
                for s in found:
                    scan_box.pack_start(D.ui_item(s.split('  (')[0], s.split('  (', 1)[1].rstrip(')') if '  (' in s else '', ), False, False, 0)
            else:
                msg = 'Kein Scanner gefunden.' if isinstance(res, Exception) or res.returncode in (0, 1) else 'Scannersuche fehlgeschlagen: ' + human_error(res)
                scan_box.pack_start(D.ui_label(msg, 'row-desc'), False, False, 0)
            scan_box.pack_start(D.ui_item('Erneut suchen', 'Die Seite zeigt Scanner nur an; gescannt wird mit einem Scanprogramm (z. B. Skanlite oder simple-scan).', D.ui_button('Suchen', scan)), False, False, 0)
            scan_box.show_all()
        D.bg(work, done)

    def on_map(*_):
        refresh()
        if not st['loaded']:
            st['loaded'] = True
            scan()
    box.connect('map', on_map)
    return box
