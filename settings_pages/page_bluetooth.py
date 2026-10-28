"""Aurora-Einstellungen: Seite „Bluetooth“ (Adapter, Sichtbarkeit, Suche, Geräte koppeln/verbinden/entfernen).

Reine Logik (Parser, Befehlsbauer, Diagnose) steht oben und braucht kein GTK und kein Bluetooth; die Oberfläche steht in build().
Benutzt `bluetoothctl` (BlueZ) nicht-interaktiv mit Zeitlimit, `rfkill` nur zum Aufheben einer Software-Sperre.
Es wird nur geschrieben, wenn der Nutzer etwas ändert."""
import os
import re
import subprocess
import threading

TITLE = 'Bluetooth'
GROUP = 'SYSTEM'
ICONS = ['bluetooth-symbolic', 'preferences-system-bluetooth-symbolic']
ORDER = 30

TIMEOUT = 4
MAC_RE = re.compile(r'^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$')
_ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]|\x01|\x02|\r')


# ---------------------------------------------------------------- reine Logik
def which(name):
    for d in os.environ.get('PATH', '').split(os.pathsep):
        p = os.path.join(d, name)
        if d and os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def default_run(args, timeout=TIMEOUT):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as e:
        return subprocess.CompletedProcess(args, 127, '', str(e))


def clean(text):
    return _ANSI.sub('', text or '')


def valid_mac(mac):
    return isinstance(mac, str) and bool(MAC_RE.match(mac.upper()))


def parse_devices(text):
    """`bluetoothctl devices` -> [(MAC, Name)] ohne Duplikate, ignoriert Fremdzeilen ([NEW]/[CHG] usw.)."""
    seen, out = set(), []
    for line in clean(text).splitlines():
        m = re.match(r'^\s*(?:\[\w+\]\s*)?Device\s+((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})\s*(.*?)\s*$', line)
        if m and m.group(1).upper() not in seen:
            mac = m.group(1).upper()
            seen.add(mac)
            out.append((mac, m.group(2) or mac))
    return out


def _yes(v):
    return str(v).strip().lower() == 'yes'


def _props(text):
    props = {}
    for line in clean(text).splitlines():
        m = re.match(r'^\s+([A-Za-z][\w .]*?):\s*(.*?)\s*$', line)
        if m and m.group(1) not in props:
            props[m.group(1)] = m.group(2)
    return props


def parse_info(text, mac='', fallback_name=''):
    """`bluetoothctl info MAC` -> Gerätedict. Nicht verfügbare Geräte ergeben None."""
    t = clean(text)
    if not t.strip() or 'not available' in t.split('\n')[0] or not re.search(r'^Device\s', t.lstrip(), re.M):
        return None
    p = _props(t)
    battery = None
    m = re.search(r'\((\d{1,3})\)', p.get('Battery Percentage', ''))
    if m:
        battery = min(100, int(m.group(1)))
    return {'mac': mac.upper(), 'name': p.get('Alias') or p.get('Name') or fallback_name or mac,
            'icon': p.get('Icon', ''), 'paired': _yes(p.get('Paired')), 'trusted': _yes(p.get('Trusted')),
            'connected': _yes(p.get('Connected')), 'blocked': _yes(p.get('Blocked')), 'battery': battery}


def parse_show(text):
    """`bluetoothctl show` -> Adapterdict oder None, wenn kein Adapter."""
    t = clean(text)
    if not t.strip() or 'No default controller' in t or not t.lstrip().startswith('Controller'):
        return None
    p = _props(t)
    first = t.lstrip().splitlines()[0].split()
    return {'mac': first[1] if len(first) > 1 else '', 'name': p.get('Alias') or p.get('Name') or 'Bluetooth',
            'powered': _yes(p.get('Powered')) , 'discoverable': _yes(p.get('Discoverable')),
            'pairable': _yes(p.get('Pairable')), 'discovering': _yes(p.get('Discovering'))}


def parse_rfkill(text):
    """`rfkill list bluetooth` -> (soft_blockiert, hard_blockiert, gefunden)."""
    t = clean(text)
    if 'Bluetooth' not in t:
        return False, False, False
    soft = bool(re.search(r'Soft blocked:\s*yes', t))
    hard = bool(re.search(r'Hard blocked:\s*yes', t))
    return soft, hard, True


def diagnose(show_text, show_rc, rfkill_text='', bt_missing=False):
    """Aus den Rohausgaben einen deutschen Hinweis ableiten. Rückgabe (Statusschlüssel, Text)."""
    if bt_missing:
        return 'nobin', 'Das Programm „bluetoothctl“ fehlt. Bitte das Paket „bluez-utils“ installieren.'
    t = clean(show_text)
    if parse_show(t):
        return 'ok', ''
    soft, hard, found = parse_rfkill(rfkill_text)
    if hard:
        return 'hardblock', 'Bluetooth ist per Schalter am Gerät (Hardware) ausgeschaltet. Bitte den Funkschalter bzw. die Flugmodus-Taste benutzen.'
    if found and soft:
        return 'softblock', 'Bluetooth ist per Software gesperrt (Flugmodus/rfkill).'
    low = t.lower() + ' ' + (show_text or '').lower()
    if 'timed out' in low or show_rc == 124:
        return 'timeout', 'Der Bluetooth-Dienst antwortet nicht (Zeitüberschreitung).'
    if 'no default controller' in low:
        if rfkill_text and not found:
            return 'noadapter', 'Kein Bluetooth-Adapter gefunden. Ist ein Adapter angesteckt und eingeschaltet?'
        return 'noadapter', 'Kein Bluetooth-Adapter verfügbar. Ist ein Adapter angesteckt, und läuft der Dienst „bluetooth“?'
    if show_rc != 0 or not t.strip():
        return 'nodaemon', 'Der Bluetooth-Dienst läuft nicht. Starten mit: sudo systemctl enable --now bluetooth'
    return 'nodaemon', 'Bluetooth ist nicht erreichbar.'


def collect(run=default_run, have=which):
    """Liest Adapter und Geräte. Rückgabe dict: status, hint, adapter, devices, rfkill_soft."""
    res = {'status': 'ok', 'hint': '', 'adapter': None, 'devices': [], 'soft': False}
    rf = ''
    if have('rfkill'):
        r = run(['rfkill', 'list', 'bluetooth'])
        rf = r.stdout if r.returncode == 0 else ''
        res['soft'] = parse_rfkill(rf)[0]
    if not have('bluetoothctl'):
        res['status'], res['hint'] = diagnose('', 127, rf, bt_missing=True)
        return res
    r = run(['bluetoothctl', 'show'])
    st, hint = diagnose(r.stdout + (r.stderr if r.returncode else ''), r.returncode, rf)
    res['status'], res['hint'] = st, hint
    if st != 'ok':
        return res
    res['adapter'] = parse_show(r.stdout)
    if not res['adapter']['powered']:
        res['hint'] = 'Bluetooth ist ausgeschaltet.'
        return res
    d = run(['bluetoothctl', 'devices'])
    for mac, name in parse_devices(d.stdout if d.returncode == 0 else ''):
        i = run(['bluetoothctl', 'info', mac])
        dev = parse_info(i.stdout if i.returncode == 0 else '', mac, name)
        if dev:
            res['devices'].append(dev)
    res['devices'].sort(key=lambda x: (not x['connected'], not x['paired'], x['name'].lower()))
    return res


def group_of(dev):
    return 'connected' if dev['connected'] else 'paired' if dev['paired'] else 'nearby'


# Befehlsbauer ---------------------------------------------------------------
def power_cmds(on, soft_blocked=False):
    cmds = []
    if on and soft_blocked:
        cmds.append(['rfkill', 'unblock', 'bluetooth'])
    cmds.append(['bluetoothctl', 'power', 'on' if on else 'off'])
    return cmds


def discoverable_cmd(on):
    return ['bluetoothctl', 'discoverable', 'on' if on else 'off']


def scan_cmd(seconds=60):
    return ['bluetoothctl', '--timeout', str(int(max(5, min(seconds, 300)))), 'scan', 'on']


def device_cmd(action, mac):
    """action: connect, disconnect, pair, trust, untrust, remove. Ungültige Adresse ergibt None."""
    if not valid_mac(mac) or action not in ('connect', 'disconnect', 'pair', 'trust', 'untrust', 'remove'):
        return None
    mac = mac.upper()
    if action == 'pair':
        return ['bluetoothctl', '--agent', 'NoInputNoOutput', '--timeout', '40', 'pair', mac]
    if action == 'connect':
        return ['bluetoothctl', '--timeout', '20', 'connect', mac]
    if action == 'disconnect':
        return ['bluetoothctl', '--timeout', '10', 'disconnect', mac]
    return ['bluetoothctl', action, mac]


_RESULTS = [
    ('Pairing successful', True, 'Gekoppelt.'),
    ('Connection successful', True, 'Verbunden.'),
    ('Successful disconnected', True, 'Getrennt.'),
    ('Device has been removed', True, 'Gerät entfernt.'),
    ('trust succeeded', True, 'Als vertrauenswürdig markiert.'),
    ('untrust succeeded', True, 'Vertrauen entzogen.'),
    ('power on succeeded', True, 'Bluetooth eingeschaltet.'),
    ('power off succeeded', True, 'Bluetooth ausgeschaltet.'),
    ('AlreadyExists', True, 'Gerät ist bereits gekoppelt.'),
    ('AlreadyConnected', True, 'Gerät ist bereits verbunden.'),
    ('AuthenticationFailed', False, 'Kopplung abgelehnt (Authentifizierung fehlgeschlagen). Das Gerät braucht evtl. eine PIN, die hier nicht abgefragt wird.'),
    ('AuthenticationCanceled', False, 'Kopplung abgebrochen.'),
    ('AuthenticationTimeout', False, 'Zeitüberschreitung bei der Kopplung. Gerät in den Kopplungsmodus versetzen und erneut versuchen.'),
    ('page-timeout', False, 'Gerät antwortet nicht. Ist es eingeschaltet und in Reichweite?'),
    ('Page Timeout', False, 'Gerät antwortet nicht. Ist es eingeschaltet und in Reichweite?'),
    ('InProgress', False, 'Es läuft bereits ein Vorgang. Bitte kurz warten.'),
    ('not available', False, 'Gerät nicht (mehr) verfügbar. Suche erneut starten.'),
    ('Failed to pair', False, 'Kopplung fehlgeschlagen.'),
    ('Failed to connect', False, 'Verbinden fehlgeschlagen. Ist das Gerät eingeschaltet und in Reichweite?'),
    ('Failed to disconnect', False, 'Trennen fehlgeschlagen.'),
    ('Failed to remove', False, 'Entfernen fehlgeschlagen.'),
    ('Failed to set power', False, 'Adapter konnte nicht umgeschaltet werden (gesperrt?).'),
    ('org.bluez.Error', False, 'Bluetooth meldet einen Fehler.'),
]


def parse_result(out, rc=0):
    """Ausgabe eines Schreibbefehls -> (Erfolg, deutscher Text)."""
    t = clean(out)
    for key, ok, msg in _RESULTS:
        if key.lower() in t.lower():
            return ok, msg
    if rc == 127:
        return False, 'Programm nicht gefunden oder nicht erreichbar.'
    if rc == 124:
        return False, 'Zeitüberschreitung.'
    return (rc == 0), ('Erledigt.' if rc == 0 else 'Befehl fehlgeschlagen.')


BATTERY_ICON = ((90, 'battery-full-symbolic'), (50, 'battery-good-symbolic'), (20, 'battery-low-symbolic'), (0, 'battery-caution-symbolic'))


def device_status_text(dev):
    parts = []
    if dev['connected']:
        parts.append('Verbunden')
    elif dev['paired']:
        parts.append('Gekoppelt')
    else:
        parts.append('In der Nähe')
    if dev['trusted']:
        parts.append('vertrauenswürdig')
    if dev['battery'] is not None:
        parts.append('Akku %d %%' % dev['battery'])
    if dev['blocked']:
        parts.append('gesperrt')
    return ' · '.join(parts)


# ---------------------------------------------------------------- Oberfläche
def build(app):
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import GLib, Gtk

    box = app.page(TITLE, 'Bluetooth-Adapter, Sichtbarkeit, Suche sowie Geräte koppeln, verbinden und entfernen.')
    app.page_index[TITLE].append('bluetooth kopfhörer maus tastatur controller koppeln verbinden trennen vertrauen adapter funk akku')
    S = {'loading': False, 'sig': None, 'res': None, 'upd': False, 'scan': None, 'busy': False, 'dirty_until': 0}

    notice = Gtk.Label(label='Bluetooth wird gelesen …', xalign=0)
    notice.set_line_wrap(True)
    notice.get_style_context().add_class('row-desc')
    box.pack_start(notice, False, False, 0)

    ctl = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    box.pack_start(ctl, False, False, 0)
    power_sw = Gtk.Switch()
    disc_sw = Gtk.Switch()
    scan_btn = Gtk.Button(label='Suche starten')
    for w in (power_sw, disc_sw):
        w.set_valign(Gtk.Align.CENTER)
    app.row(ctl, 'Bluetooth', power_sw, 'Schaltet den Bluetooth-Adapter ein oder aus.')
    app.row(ctl, 'Für andere Geräte sichtbar', disc_sw, 'Andere Geräte können diesen Rechner finden, solange das eingeschaltet ist.')
    app.row(ctl, 'Nach Geräten suchen', scan_btn, 'Sucht etwa eine Minute lang nach Geräten in der Nähe.')
    dyn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    box.pack_start(dyn, False, False, 0)

    def say(text):
        app.message(text)

    def background(cmds, done_msg=None):
        """Befehle nacheinander in einem Thread; Ergebnis als Meldung, danach neu lesen."""
        S['busy'] = True

        def work():
            ok, msg = True, ''
            for c in cmds:
                r = app.run_tool(c, timeout=45 if 'pair' in c else 25)
                ok, msg = parse_result((r.stdout or '') + (r.stderr or ''), r.returncode)
                if not ok and not (c[:2] == ['bluetoothctl', 'trust']):
                    break

            def fin():
                S['busy'] = False
                say(msg if not ok or not done_msg else done_msg)
                refresh()
                return False
            GLib.idle_add(fin)
        threading.Thread(target=work, daemon=True).start()

    def act(action, mac):
        c = device_cmd(action, mac)
        if c:
            say({'connect': 'Verbinde …', 'disconnect': 'Trenne …', 'pair': 'Koppele … (Gerät im Kopplungsmodus halten)',
                 'trust': 'Markiere …', 'untrust': 'Entziehe Vertrauen …', 'remove': 'Entferne …'}[action])
            done = {'connect': 'Verbunden.', 'disconnect': 'Getrennt.', 'trust': 'Als vertrauenswürdig markiert.',
                    'untrust': 'Vertrauen entzogen.', 'remove': 'Gerät entfernt.'}
            if action == 'pair':
                background([c, device_cmd('trust', mac), device_cmd('connect', mac)], 'Gekoppelt und verbunden.')
            else:
                background([c], done[action])

    def confirm_remove(dev):
        d = Gtk.MessageDialog(transient_for=app.window, modal=True, message_type=Gtk.MessageType.QUESTION,
                              buttons=Gtk.ButtonsType.OK_CANCEL, text='„%s“ entfernen?' % dev['name'])
        d.format_secondary_text('Die Kopplung wird gelöscht. Zum erneuten Benutzen muss das Gerät neu gekoppelt werden.')
        r = d.run()
        d.destroy()
        if r == Gtk.ResponseType.OK:
            act('remove', dev['mac'])

    def device_row(dev):
        row = Gtk.Box(spacing=12)
        row.get_style_context().add_class('setting-row')
        labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        t = Gtk.Label(label=dev['name'], xalign=0)
        t.get_style_context().add_class('row-title')
        d = Gtk.Label(label='%s   %s' % (device_status_text(dev), dev['mac']), xalign=0)
        d.get_style_context().add_class('row-desc')
        labels.pack_start(t, False, False, 0)
        labels.pack_start(d, False, False, 0)
        row.pack_start(labels, True, True, 0)
        btns = Gtk.Box(spacing=6)
        btns.set_valign(Gtk.Align.CENTER)

        def add(text, fn):
            b = Gtk.Button(label=text)
            b.connect('clicked', lambda *_: fn())
            btns.pack_start(b, False, False, 0)
        if dev['connected']:
            add('Trennen', lambda: act('disconnect', dev['mac']))
        elif dev['paired']:
            add('Verbinden', lambda: act('connect', dev['mac']))
        else:
            add('Koppeln', lambda: act('pair', dev['mac']))
        if dev['paired']:
            add('Vertrauen entziehen' if dev['trusted'] else 'Vertrauen', lambda: act('untrust' if dev['trusted'] else 'trust', dev['mac']))
            add('Entfernen', lambda: confirm_remove(dev))
        row.pack_end(btns, False, False, 0)
        return row

    def heading(text):
        l = Gtk.Label(label=text.upper(), xalign=0)
        l.get_style_context().add_class('section-title')
        dyn.pack_start(l, False, False, 0)

    def render(res):
        for c in dyn.get_children():
            dyn.remove(c)
            c.destroy()
        names = (('connected', 'Verbunden'), ('paired', 'Gekoppelt'), ('nearby', 'In der Nähe'))
        shown = False
        for key, title in names:
            devs = [d for d in res['devices'] if group_of(d) == key]
            if devs:
                shown = True
                heading(title)
                for d in devs:
                    dyn.pack_start(device_row(d), False, False, 0)
        if not shown and res['adapter'] and res['adapter']['powered']:
            heading('Geräte')
            l = Gtk.Label(label='Keine Geräte gefunden. „Nach Geräten suchen“ starten und das Gerät in den Kopplungsmodus versetzen.', xalign=0)
            l.set_line_wrap(True)
            l.get_style_context().add_class('row-desc')
            dyn.pack_start(l, False, False, 0)
        dyn.show_all()

    def scanning():
        p = S['scan']
        return p is not None and p.poll() is None

    def apply_res(res):
        S['loading'] = False
        S['res'] = res
        ad = res['adapter']
        S['upd'] = True
        try:
            ctl.set_sensitive(res['status'] in ('ok', 'softblock'))
            notice.set_text(res['hint'])
            notice.set_visible(bool(res['hint']))
            power_sw.set_active(bool(ad and ad['powered']))
            power_sw.set_sensitive(res['status'] in ('ok', 'softblock'))
            disc_sw.set_active(bool(ad and ad['discoverable']))
            disc_sw.set_sensitive(bool(ad and ad['powered']))
            on = scanning() or bool(ad and ad['discovering'])
            scan_btn.set_label('Suche beenden' if on else 'Suche starten')
            scan_btn.set_sensitive(bool(ad and ad['powered']))
        finally:
            S['upd'] = False
        sig = (res['status'], tuple((d['mac'], d['name'], d['paired'], d['trusted'], d['connected'], d['battery'], d['blocked']) for d in res['devices']),
               bool(ad and ad['powered']))
        if sig != S['sig']:
            S['sig'] = sig
            render(res)
        return False

    def refresh(*_):
        if S['loading']:
            return False
        S['loading'] = True

        def work():
            try:
                res = collect(lambda a, timeout=TIMEOUT: app.run_tool(a, timeout=timeout))
            except Exception as e:
                res = {'status': 'nodaemon', 'hint': 'Bluetooth konnte nicht gelesen werden: %r' % (e,), 'adapter': None, 'devices': [], 'soft': False}
            GLib.idle_add(apply_res, res)
        threading.Thread(target=work, daemon=True).start()
        return False

    def on_power(sw, _p):
        if S['upd']:
            return
        soft = bool(S['res'] and S['res'].get('soft'))
        say('Schalte Bluetooth ein …' if sw.get_active() else 'Schalte Bluetooth aus …')
        background(power_cmds(sw.get_active(), soft))
    power_sw.connect('notify::active', on_power)

    def on_disc(sw, _p):
        if not S['upd']:
            background([discoverable_cmd(sw.get_active())])
    disc_sw.connect('notify::active', on_disc)

    def stop_scan():
        p = S['scan']
        S['scan'] = None
        if p is not None and p.poll() is None:
            try:
                p.terminate()
                threading.Thread(target=lambda: p.wait(timeout=5), daemon=True).start()
            except (OSError, subprocess.SubprocessError):
                pass

    def on_scan(_b):
        if scanning():
            stop_scan()
            scan_btn.set_label('Suche starten')
            say('Suche beendet.')
            GLib.timeout_add(600, lambda: (refresh(), False)[1])
            return
        try:
            S['scan'] = subprocess.Popen(scan_cmd(60), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            scan_btn.set_label('Suche beenden')
            say('Suche läuft … (etwa eine Minute)')
        except OSError as e:
            say('Suche konnte nicht gestartet werden: %s' % e)
    scan_btn.connect('clicked', on_scan)

    tick = {'id': 0}

    def on_map(_w):
        refresh()
        if not tick['id']:
            tick['id'] = GLib.timeout_add_seconds(4, lambda: (refresh(), True)[1])

    def on_unmap(_w):
        if tick['id']:
            GLib.source_remove(tick['id'])
            tick['id'] = 0
        stop_scan()
    box.connect('map', on_map)
    box.connect('unmap', on_unmap)
