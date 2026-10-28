"""Aurora-Einstellungen: Seite „Netzwerk“ (NetworkManager über nmcli).

Aufbau: oben reine Logik (Parser, Validierung, Befehlsbauer, Aktionen über `nm()`), ohne GTK und ohne Anzeige testbar
(tests/test_page_network.py); unten die Oberfläche (`build`).

Passwörter: werden NIE als Argument übergeben (sichtbar in /proc/<pid>/cmdline und `ps`). Gewählte Lösung:
`nmcli --ask` liest fehlende Geheimnisse von der Standardeingabe; wir schreiben das Passwort per Pipe (stdin) hinein.
Beim Hotspot wird das Profil ohne Passwort angelegt (psk-flags=2 „immer nachfragen“) und beim Start mit `--ask` per stdin
beantwortet; das Passwort wird dabei nirgends gespeichert, nicht im Prozessbaum und nicht in einer Datei.
"""
import ipaddress
import os
import re
import shutil
import socket
import subprocess
import sys
import threading

TITLE = 'Netzwerk'
GROUP = 'SYSTEM'
ICONS = ['network-wireless-symbolic', 'network-workgroup-symbolic']
ORDER = 10

NMCLI = 'nmcli'
HOTSPOT_NAME = 'Aurora-Hotspot'
UUID_RE = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
IFACE_RE = re.compile(r'^[A-Za-z0-9_.:@+-]{1,15}$')
VPN_TYPES = ('vpn', 'wireguard')
HIDDEN_TYPES = ('loopback', 'bridge', 'tun', 'tap', 'veth', 'dummy', 'vlan', 'bond', 'team', 'ovs-bridge', 'ovs-port', 'ovs-interface', 'generic')


# ---------------------------------------------------------------- Programme starten
def have(prog):
    return shutil.which(prog) is not None


def run(args, timeout=15, input_text=None):
    """Programm mit Zeitlimit starten. Rückgabe (Code, stdout, stderr); 127 = fehlt/Fehler, 124 = Zeitüberschreitung.
    Kein Shell-Aufruf, Argumente nur als Liste; feste Sprache, damit die Ausgaben parsebar bleiben."""
    if not have(args[0]):
        return 127, '', 'Programm nicht gefunden: ' + args[0]
    env = dict(os.environ, LC_ALL='C.UTF-8', LANG='C.UTF-8')
    env.pop('LANGUAGE', None)
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, input=input_text, env=env)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, '', 'Zeitüberschreitung'
    except (OSError, subprocess.SubprocessError) as e:
        return 127, '', str(e)


def nm(args, timeout=15, input_text=None):
    return run([NMCLI] + list(args), timeout, input_text)


def nm_error_text(rc, err):
    """nmcli-Fehler als lesbarer deutscher Hinweis."""
    e = (err or '').strip()
    low = e.lower()
    if rc == 127:
        return 'NetworkManager (nmcli) ist nicht installiert oder nicht erreichbar.'
    if rc == 124 or 'timeout' in low or 'timed out' in low:
        return 'Zeitüberschreitung: Die Aktion hat zu lange gedauert.'
    if 'networkmanager is not running' in low or 'not running' in low:
        return 'Der NetworkManager-Dienst läuft nicht.'
    if 'secrets were required' in low or 'no secrets' in low or 'password' in low and 'invalid' in low:
        return 'Das Passwort wurde nicht akzeptiert oder fehlt.'
    if 'no network with ssid' in low:
        return 'Ein WLAN mit diesem Namen wurde nicht gefunden.'
    if 'no suitable device' in low or 'device' in low and 'not found' in low or 'no wi-fi device' in low:
        return 'Es wurde kein passender Netzwerkadapter gefunden.'
    if 'not authorized' in low or 'permission denied' in low or 'insufficient privileges' in low:
        return 'Dafür fehlt die Berechtigung.'
    if 'activation failed' in low or 'connection activation failed' in low:
        return 'Die Verbindung konnte nicht aufgebaut werden. ' + (e.splitlines()[-1] if e else '')
    return e.splitlines()[-1] if e else 'Unbekannter Fehler (Code %s).' % rc


# ---------------------------------------------------------------- nmcli -t Parser
def split_t(line, maxsplit=-1):
    """Zeile der terse-Ausgabe (`nmcli -t`) an unmaskierten ':' trennen; `\\:` und `\\\\` werden zurückgewandelt."""
    parts, cur, i, n = [], [], 0, len(line)
    while i < n:
        c = line[i]
        if c == '\\' and i + 1 < n:
            cur.append(line[i + 1])
            i += 2
            continue
        if c == ':' and (maxsplit < 0 or len(parts) < maxsplit):
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    parts.append(''.join(cur))
    return parts


def _rows(text, n):
    for line in (text or '').splitlines():
        if not line.strip():
            continue
        f = split_t(line)
        if len(f) < n:
            f += [''] * (n - len(f))
        elif len(f) > n:  # überzählige ':' im letzten Feld wieder zusammenfügen
            f = f[:n - 1] + [':'.join(f[n - 1:])]
        yield f


def parse_devices(text):
    """`-f DEVICE,TYPE,STATE,CONNECTION device status`"""
    return [{'device': d, 'type': t, 'state': s, 'connection': c} for d, t, s, c in _rows(text, 4)]


def parse_connections(text):
    """`-f NAME,UUID,TYPE,DEVICE connection show`"""
    return [{'name': n, 'uuid': u, 'type': t, 'device': d} for n, u, t, d in _rows(text, 4)]


def parse_wifi(text):
    """`-f IN-USE,SSID,SIGNAL,SECURITY,CHAN,RATE device wifi list`; je SSID ein Eintrag (stärkster), aktiver zuerst."""
    best = {}
    for use, ssid, sig, sec, chan, rate in _rows(text, 6):
        if not ssid.strip():
            continue  # unsichtbare/versteckte Netze ohne Namen
        try:
            sig_i = max(0, min(100, int(sig)))
        except ValueError:
            sig_i = 0
        e = {'ssid': ssid, 'signal': sig_i, 'security': '' if sec.strip() in ('', '--') else sec.strip(), 'active': use.strip() == '*', 'chan': chan.strip(), 'rate': rate.strip()}
        old = best.get(ssid)
        if old is None or (e['active'] and not old['active']) or (e['active'] == old['active'] and e['signal'] > old['signal']):
            best[ssid] = e
    return sorted(best.values(), key=lambda e: (not e['active'], -e['signal'], e['ssid'].lower()))


def parse_kv(text):
    """`key:value`-Zeilen (nmcli -t connection show X / device show X) -> {schlüssel: [werte]}; '[n]' am Schlüssel wird entfernt."""
    out = {}
    for line in (text or '').splitlines():
        if ':' not in line:
            continue
        k, v = split_t(line, 1)
        k = re.sub(r'\[\d+\]$', '', k.strip())
        v = v.strip()
        out.setdefault(k, [])
        if v and v != '--':
            out[k].append(v)
    return out


def first(d, key, default=''):
    v = d.get(key)
    return v[0] if v else default


def parse_radio(text):
    """`-t -f WIFI,WWAN radio` -> (wifi_an, wwan_an); None wenn unlesbar."""
    line = next((l for l in (text or '').splitlines() if l.strip()), '')
    f = split_t(line)
    if len(f) < 2:
        return None
    return f[0].strip() == 'enabled', f[1].strip() == 'enabled'


def parse_rfkill(text):
    """`rfkill -J` -> {'hard': bool, 'soft': bool} über alle Geräte (grob, nur für Hinweise)."""
    import json
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        return None
    devs = [d for lst in data.values() if isinstance(lst, list) for d in lst if isinstance(d, dict)]
    return {'hard': any(d.get('hard') == 'blocked' for d in devs), 'soft': any(d.get('soft') == 'blocked' for d in devs)}


CONNECTIVITY_DE = {'full': 'Internet erreichbar', 'limited': 'Eingeschränkt (kein Internet)', 'portal': 'Anmeldung im Browser nötig (Portal)',
                   'none': 'Keine Verbindung', 'unknown': 'Unbekannt'}
STATE_DE = {'connected': 'Verbunden', 'connected (externally)': 'Verbunden (extern verwaltet)', 'disconnected': 'Getrennt', 'unavailable': 'Nicht verfügbar',
            'unmanaged': 'Nicht verwaltet', 'connecting (prepare)': 'Verbindet …', 'connecting (configuring)': 'Verbindet …',
            'connecting (need authentication)': 'Anmeldung nötig …', 'connecting (getting ip configuration)': 'Adresse wird bezogen …',
            'connecting (checking ip connectivity)': 'Verbindet …', 'deactivating': 'Trennt …', 'unavailable (disabled)': 'Aus'}
TYPE_DE = {'ethernet': 'Kabel', '802-3-ethernet': 'Kabel', 'wifi': 'WLAN', '802-11-wireless': 'WLAN', 'vpn': 'VPN', 'wireguard': 'WireGuard',
           'bridge': 'Bridge', 'tun': 'Tunnel', 'loopback': 'Loopback', 'gsm': 'Mobilfunk', 'bluetooth': 'Bluetooth', 'wifi-p2p': 'WLAN Direkt'}


def signal_bars(sig):
    return '▂▄▆█'[: max(1, min(4, (sig + 24) // 25))] if sig > 0 else '·'


def security_text(sec):
    return 'Offen' if not sec else sec.replace('WPA3', 'WPA3').replace('--', 'Offen')


def is_open(sec):
    return not sec


def is_enterprise(sec):
    return '802.1X' in (sec or '')


def pick_connections(conns, vpn):
    """Verbindungen für die Listen: VPN-Typen oder normale (ohne Bridges/Loopback/technische Typen)."""
    if vpn:
        return [c for c in conns if c['type'] in VPN_TYPES]
    return [c for c in conns if c['type'] not in VPN_TYPES and c['type'] not in HIDDEN_TYPES]


def friendly_state(state):
    return STATE_DE.get(state, state)


# ---------------------------------------------------------------- Validierung
def valid_ip(s, version):
    try:
        a = ipaddress.ip_address(s.strip())
    except ValueError:
        return False
    return a.version == version and not (a.is_unspecified or a.is_multicast)


def split_list(s):
    return [x for x in re.split(r'[\s,;]+', s or '') if x]


def parse_addresses(s, version):
    """Zeilen/Kommas 'ip/prefix' -> (liste, fehler). Strikt: Präfix Pflicht, passende IP-Familie, keine Adresse 0.0.0.0/Multicast."""
    out = []
    for item in split_list(s):
        if '/' not in item:
            return None, 'Adresse „%s“ braucht eine Präfixlänge (z. B. 192.168.1.10/24).' % item
        ip, _, pre = item.partition('/')
        if not pre.isdigit() or not valid_ip(ip, version):
            return None, 'Ungültige IPv%d-Adresse: „%s“.' % (version, item)
        if int(pre) < 1 or int(pre) > (32 if version == 4 else 128):
            return None, 'Ungültige Präfixlänge in „%s“.' % item
        out.append(str(ipaddress.ip_interface(item)))
    return out, ''


def parse_dns(s, version):
    out = []
    for item in split_list(s):
        if not valid_ip(item, version):
            return None, 'Ungültiger DNS-Server (IPv%d): „%s“.' % (version, item)
        out.append(str(ipaddress.ip_address(item)))
    return out, ''


def valid_mtu(s):
    s = (s or '').strip().lower()
    if s in ('', '0', 'auto', 'automatisch'):
        return 0, ''
    if not s.isdigit() or not 576 <= int(s) <= 9216:
        return None, 'Die MTU muss leer (automatisch) oder zwischen 576 und 9216 liegen.'
    return int(s), ''


def valid_priority(s):
    s = str(s).strip()
    if not re.fullmatch(r'-?\d{1,3}', s) or not -999 <= int(s) <= 999:
        return None, 'Die Priorität muss eine ganze Zahl zwischen -999 und 999 sein.'
    return int(s), ''


def valid_ssid(s):
    b = (s or '').encode('utf-8', 'ignore')
    if not 1 <= len(b) <= 32 or any(c < 32 for c in b):
        return 'Der Netzwerkname (SSID) muss 1 bis 32 Zeichen lang sein.'
    if s.startswith('-'):
        return 'Netzwerknamen mit führendem „-“ werden hier nicht unterstützt.'
    return ''


def valid_wpa_password(p):
    if re.fullmatch(r'[0-9A-Fa-f]{64}', p or ''):
        return ''
    n = len((p or '').encode('utf-8'))
    if n < 8:
        return 'Das Passwort muss mindestens 8 Zeichen lang sein.'
    if n > 63:
        return 'Das Passwort darf höchstens 63 Zeichen lang sein.'
    if '\n' in p or '\r' in p:
        return 'Das Passwort darf keinen Zeilenumbruch enthalten.'
    return ''


def valid_hostname(h):
    if not h or len(h) > 63 or not re.fullmatch(r'[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?', h):
        return 'Rechnername: 1 bis 63 Zeichen, nur Buchstaben, Ziffern und „-“, nicht am Anfang/Ende ein „-“.'
    return ''


def valid_conn_name(n):
    if not n.strip() or len(n) > 100 or any(ord(c) < 32 for c in n):
        return 'Der Name muss 1 bis 100 Zeichen lang sein und darf keine Steuerzeichen enthalten.'
    return ''


def valid_host(h):
    return bool(re.fullmatch(r'[A-Za-z0-9._:\[\]-]{1,253}', h or ''))


def valid_port(p):
    return str(p).isdigit() and 0 <= int(p) <= 65535


# ---------------------------------------------------------------- Befehlsbauer (nur Argumentlisten, keine Ausführung)
def need_uuid(u):
    if not UUID_RE.match(u or ''):
        raise ValueError('Ungültige Verbindungs-ID')
    return u


def cmd_connection_up(uuid):
    return ['connection', 'up', 'uuid', need_uuid(uuid)]


def cmd_connection_down(uuid):
    return ['connection', 'down', 'uuid', need_uuid(uuid)]


def cmd_connection_delete(uuid):
    return ['connection', 'delete', 'uuid', need_uuid(uuid)]


def cmd_rename(uuid, name):
    err = valid_conn_name(name)
    if err:
        raise ValueError(err)
    return ['connection', 'modify', 'uuid', need_uuid(uuid), 'connection.id', name.strip()]


def cmd_autoconnect(uuid, on, priority=None):
    a = ['connection', 'modify', 'uuid', need_uuid(uuid), 'connection.autoconnect', 'yes' if on else 'no']
    if priority is not None:
        a += ['connection.autoconnect-priority', str(int(priority))]
    return a


def cmd_ip_settings(uuid, ctype, v4, v6, mtu):
    """v4/v6: dict(method, addresses:str, gateway:str, dns:str). mtu: str. Wirft ValueError mit deutschem Text bei ungültiger Eingabe."""
    a = ['connection', 'modify', 'uuid', need_uuid(uuid)]
    for ver, cfg in ((4, v4), (6, v6)):
        p = 'ipv%d.' % ver
        method = cfg['method']
        if method not in ('auto', 'manual', 'disabled'):
            raise ValueError('Unbekannte Methode')
        dns, err = parse_dns(cfg.get('dns', ''), ver)
        if err:
            raise ValueError(err)
        if method == 'manual':
            addrs, err = parse_addresses(cfg.get('addresses', ''), ver)
            if err:
                raise ValueError(err)
            if not addrs:
                raise ValueError('IPv%d manuell: mindestens eine Adresse eintragen.' % ver)
            gw = (cfg.get('gateway') or '').strip()
            if gw and not valid_ip(gw, ver):
                raise ValueError('Ungültiges Gateway (IPv%d): „%s“.' % (ver, gw))
            a += [p + 'method', 'manual', p + 'addresses', ', '.join(addrs), p + 'gateway', str(ipaddress.ip_address(gw)) if gw else '']
        else:
            a += [p + 'method', method, p + 'addresses', '', p + 'gateway', '']
        a += [p + 'dns', ' '.join(dns) if method != 'disabled' else '']
    m, err = valid_mtu(mtu)
    if err:
        raise ValueError(err)
    key = {'802-3-ethernet': '802-3-ethernet.mtu', '802-11-wireless': '802-11-wireless.mtu'}.get(ctype)
    if key:
        a += [key, str(m) if m else 'auto']
    return a


def cmd_wifi_connect(ssid, hidden=False, ifname=None, ask=False):
    """Passwort nie hier: bei ask=True liest nmcli es von stdin (--ask)."""
    err = valid_ssid(ssid)
    if err:
        raise ValueError(err)
    a = (['--ask'] if ask else []) + ['device', 'wifi', 'connect', ssid]
    if hidden:
        a += ['hidden', 'yes']
    if ifname:
        if not IFACE_RE.match(ifname):
            raise ValueError('Ungültiger Adaptername')
        a += ['ifname', ifname]
    return a


def cmd_hotspot_add(ssid, ifname, name=HOTSPOT_NAME):
    err = valid_ssid(ssid)
    if err:
        raise ValueError(err)
    if not IFACE_RE.match(ifname or ''):
        raise ValueError('Ungültiger Adaptername')
    return ['connection', 'add', 'type', 'wifi', 'ifname', ifname, 'con-name', name, 'autoconnect', 'no', 'ssid', ssid,
            '802-11-wireless.mode', 'ap', '802-11-wireless.band', 'bg', 'ipv4.method', 'shared', 'ipv6.method', 'ignore',
            '802-11-wireless-security.key-mgmt', 'wpa-psk', '802-11-wireless-security.psk-flags', '2']


def cmd_hotspot_up(uuid):
    return ['--ask', 'connection', 'up', 'uuid', need_uuid(uuid)]


def cmd_import(kind, path):
    if kind not in ('wireguard', 'openvpn'):
        raise ValueError('Unbekannter VPN-Typ')
    return ['connection', 'import', 'type', kind, 'file', path]


def vpn_kind_for(path):
    return 'openvpn' if path.lower().endswith(('.ovpn',)) else 'wireguard'


def cmd_radio(which, on):
    if which not in ('wifi', 'all'):
        raise ValueError('radio')
    return ['radio', which, 'on' if on else 'off']


def gsettings_proxy_cmds(cfg):
    """cfg: mode ('none'|'manual'|'auto'), http/https/socks (host,port), autoconfig. Liste von gsettings-Argumentlisten."""
    mode = cfg.get('mode')
    if mode not in ('none', 'manual', 'auto'):
        raise ValueError('Unbekannter Proxy-Modus')
    cmds = [['gsettings', 'set', 'org.gnome.system.proxy', 'mode', mode]]
    if mode == 'manual':
        for sect in ('http', 'https', 'socks'):
            host, port = (cfg.get(sect) or ('', '0'))
            host = (host or '').strip()
            port = str(port or '0').strip() or '0'
            if host and not valid_host(host):
                raise ValueError('Ungültiger Proxy-Rechner bei %s.' % sect.upper())
            if not valid_port(port):
                raise ValueError('Ungültiger Port bei %s (0–65535).' % sect.upper())
            schema = 'org.gnome.system.proxy.' + sect
            cmds.append(['gsettings', 'set', schema, 'host', host])
            cmds.append(['gsettings', 'set', schema, 'port', port])
    if mode == 'auto':
        url = (cfg.get('autoconfig') or '').strip()
        if url and not re.fullmatch(r'(https?|file)://[^\s\'"]+', url):
            raise ValueError('Ungültige Adresse der Proxy-Konfigurationsdatei (http://, https:// oder file://).')
        cmds.append(['gsettings', 'set', 'org.gnome.system.proxy', 'autoconfig-url', url])
    return cmds


def parse_gsettings_str(s):
    s = (s or '').strip()
    if len(s) >= 2 and s[0] == s[-1] == "'":
        return s[1:-1]
    return s


# ---------------------------------------------------------------- Aktionen (Ergebnis (ok, text))
def act(args, ok_text, timeout=30, input_text=None):
    rc, out, err = nm(args, timeout, input_text)
    if rc == 0:
        return True, ok_text
    return False, nm_error_text(rc, err or out)


def do_wifi_connect(ssid, password, hidden=False, ifname=None, secured=True):
    if secured:
        e = valid_wpa_password(password)
        if e:
            return False, e
    try:
        args = cmd_wifi_connect(ssid, hidden, ifname, ask=secured)
    except ValueError as e:
        return False, str(e)
    return act(args, 'Mit „%s“ verbunden.' % ssid, 60, (password + '\n') if secured else None)


def do_hotspot_start(ssid, password, ifname):
    err = valid_ssid(ssid) or valid_wpa_password(password)
    if err:
        return False, err
    # altes Profil gleichen Namens entfernen, damit nicht mehrere entstehen
    rc, out, _ = nm(['-t', '-f', 'NAME,UUID', 'connection', 'show'])
    for line in out.splitlines() if rc == 0 else []:
        f = split_t(line)
        if len(f) >= 2 and f[0] == HOTSPOT_NAME and UUID_RE.match(f[1]):
            nm(cmd_connection_delete(f[1]))
    try:
        add = cmd_hotspot_add(ssid, ifname)
    except ValueError as e:
        return False, str(e)
    rc, out, err = nm(add)
    if rc != 0:
        return False, nm_error_text(rc, err or out)
    m = re.search(r'\(([0-9a-fA-F-]{36})\)', out)
    uuid = m.group(1) if m else ''
    if not UUID_RE.match(uuid):
        return False, 'Der Hotspot konnte nicht angelegt werden (keine Verbindungs-ID erhalten).'
    ok, text = act(cmd_hotspot_up(uuid), 'Hotspot „%s“ ist aktiv.' % ssid, 60, password + '\n')
    if not ok:
        nm(cmd_connection_delete(uuid))
    return ok, text


def do_hotspot_stop(uuid):
    ok, text = act(cmd_connection_down(uuid), 'Hotspot beendet.')
    if ok:
        nm(cmd_connection_delete(uuid))
    return ok, text


def load_connection_details(uuid):
    rc, out, err = nm(['-t', 'connection', 'show', 'uuid', need_uuid(uuid)])
    if rc != 0:
        return None, nm_error_text(rc, err)
    return parse_kv(out), ''


def read_status():
    """Alles Lesende für Übersicht + Listen, in einem Thread aufrufen. Wirft nie."""
    st = {'nm': have(NMCLI), 'error': '', 'devices': [], 'connections': [], 'wifi': [], 'radio': None, 'connectivity': '', 'active': None,
          'rfkill': None, 'hostname': '', 'wifi_dev': ''}
    try:
        st['hostname'] = socket.gethostname()
    except OSError:
        pass
    if not st['nm']:
        st['error'] = 'NetworkManager (nmcli) ist nicht installiert. Diese Seite kann ohne NetworkManager nichts verwalten.'
        return st
    rc, out, err = nm(['-t', '-f', 'DEVICE,TYPE,STATE,CONNECTION', 'device', 'status'], 8)
    if rc != 0:
        st['error'] = nm_error_text(rc, err)
        return st
    st['devices'] = parse_devices(out)
    rc, out, _ = nm(['-t', '-f', 'NAME,UUID,TYPE,DEVICE', 'connection', 'show'], 8)
    if rc == 0:
        st['connections'] = parse_connections(out)
    rc, out, _ = nm(['-t', '-f', 'WIFI,WWAN', 'radio'], 5)
    if rc == 0:
        st['radio'] = parse_radio(out)
    rc, out, _ = nm(['-t', '-g', 'CONNECTIVITY', 'general'], 5)
    st['connectivity'] = out.strip() if rc == 0 else ''
    wd = next((d for d in st['devices'] if d['type'] == 'wifi'), None)
    st['wifi_dev'] = wd['device'] if wd else ''
    if wd and st['radio'] and st['radio'][0] and wd['state'] != 'unavailable':
        rc, out, _ = nm(['-t', '-f', 'IN-USE,SSID,SIGNAL,SECURITY,CHAN,RATE', 'device', 'wifi', 'list', '--rescan', 'no'], 10)
        if rc == 0:
            st['wifi'] = parse_wifi(out)
    prim = next((d for d in st['devices'] if d['type'] in ('ethernet', 'wifi') and d['state'].startswith('connected')), None)
    if prim and IFACE_RE.match(prim['device']):
        rc, out, _ = nm(['-t', 'device', 'show', prim['device']], 8)
        if rc == 0:
            kv = parse_kv(out)
            speed = ''
            if prim['type'] == 'ethernet':
                try:
                    with open('/sys/class/net/%s/speed' % prim['device']) as f:
                        v = int(f.read().strip())
                    speed = '%d MBit/s' % v if v > 0 else ''
                except (OSError, ValueError):
                    pass
            sig = next((w for w in st['wifi'] if w['active']), None)
            if sig and prim['type'] == 'wifi':
                speed = sig['rate']
            st['active'] = {'device': prim['device'], 'type': prim['type'], 'name': prim['connection'], 'ip4': kv.get('IP4.ADDRESS', []),
                            'ip6': kv.get('IP6.ADDRESS', []), 'gw4': first(kv, 'IP4.GATEWAY'), 'gw6': first(kv, 'IP6.GATEWAY'),
                            'dns': kv.get('IP4.DNS', []) + kv.get('IP6.DNS', []), 'mac': first(kv, 'GENERAL.HWADDR'),
                            'mtu': first(kv, 'GENERAL.MTU'), 'signal': sig['signal'] if sig else None, 'speed': speed}
    if have('rfkill'):
        rc, out, _ = run(['rfkill', '-J'], 5)
        if rc == 0:
            st['rfkill'] = parse_rfkill(out)
    return st


def read_firewall():
    """Nur lesend: welche Firewall-Dienste laufen (systemctl is-active braucht kein Root)."""
    res = []
    if not have('systemctl'):
        return res
    for unit, label in (('ufw', 'ufw'), ('firewalld', 'firewalld'), ('nftables', 'nftables'), ('iptables', 'iptables')):
        rc, out, _ = run(['systemctl', 'is-active', unit], 5)
        state = out.strip()
        if state in ('active', 'inactive', 'failed', 'activating'):
            rc2, en, _ = run(['systemctl', 'is-enabled', unit], 5)
            res.append((label, state, en.strip()))
    return res


def firewall_text(items):
    if not items:
        return 'Kein bekannter Firewall-Dienst (ufw, firewalld, nftables) gefunden.'
    de = {'active': 'läuft', 'inactive': 'gestoppt', 'failed': 'fehlgeschlagen', 'activating': 'startet'}
    en = {'enabled': 'beim Start aktiv', 'disabled': 'beim Start aus', 'static': 'beim Start aus', 'masked': 'gesperrt'}
    return '\n'.join('%s: %s (%s)' % (n, de.get(s, s), en.get(e, e or 'unbekannt')) for n, s, e in items)


def read_proxy():
    if not have('gsettings'):
        return None
    cfg = {}
    rc, out, _ = run(['gsettings', 'get', 'org.gnome.system.proxy', 'mode'], 4)
    if rc != 0:
        return None
    cfg['mode'] = parse_gsettings_str(out)
    for sect in ('http', 'https', 'socks'):
        rc1, h, _ = run(['gsettings', 'get', 'org.gnome.system.proxy.' + sect, 'host'], 4)
        rc2, p, _ = run(['gsettings', 'get', 'org.gnome.system.proxy.' + sect, 'port'], 4)
        cfg[sect] = (parse_gsettings_str(h) if rc1 == 0 else '', p.strip() if rc2 == 0 and p.strip().isdigit() else '0')
    rc, out, _ = run(['gsettings', 'get', 'org.gnome.system.proxy', 'autoconfig-url'], 4)
    cfg['autoconfig'] = parse_gsettings_str(out) if rc == 0 else ''
    return cfg


def current_hostname():
    if have('hostnamectl'):
        rc, out, _ = run(['hostnamectl', 'hostname'], 4)
        if rc == 0 and out.strip():
            return out.strip()
    try:
        return socket.gethostname()
    except OSError:
        return ''


def do_set_hostname(name):
    err = valid_hostname(name)
    if err:
        return False, err
    rc, out, e = run(['pkexec', 'hostnamectl', 'set-hostname', name], 60)
    if rc == 0:
        return True, 'Rechnername geändert. Laufende Programme sehen ihn teils erst nach einem Neustart.'
    if rc == 126 or rc == 127 and 'nicht gefunden' not in e:
        return False, 'Die Anmeldung wurde abgebrochen oder verweigert.'
    if rc == 127:
        return False, 'pkexec ist nicht installiert.'
    return False, nm_error_text(rc, e)


# ================================================================ Oberfläche
def build(app):
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, GLib, Pango

    box = app.page(TITLE, 'WLAN, Kabel, VPN, Proxy, Rechnername und Firewall – verwaltet über NetworkManager. Änderungen wirken sofort.')
    state = {'st': None, 'busy': False}

    def bg(fn, done=None):
        """fn im Thread, done(Ergebnis) in der UI-Schleife."""
        def work():
            try:
                res = fn()
            except Exception as e:  # nie den Thread kaputtgehen lassen
                res = (False, 'Fehler: %s' % e)
            if done:
                GLib.idle_add(lambda: (done(res), False)[1])
        threading.Thread(target=work, daemon=True).start()

    def say(text):
        app.message(text)

    def label(text='', cls=None, wrap=True):
        l = Gtk.Label(label=text, xalign=0)
        l.set_line_wrap(wrap)
        l.set_selectable(False)
        if cls:
            l.get_style_context().add_class(cls)
        return l

    def clear(c):
        for ch in c.get_children():
            c.remove(ch)
            ch.destroy()

    def confirm(title, text, ok='OK'):
        d = Gtk.MessageDialog(transient_for=app.window, modal=True, message_type=Gtk.MessageType.QUESTION, text=title)
        d.format_secondary_text(text)
        d.add_button('Abbrechen', Gtk.ResponseType.CANCEL)
        d.add_button(ok, Gtk.ResponseType.OK)
        r = d.run()
        d.destroy()
        return r == Gtk.ResponseType.OK

    def ask_text(title, text, default='', password=False, ok='OK'):
        d = Gtk.Dialog(title=title, transient_for=app.window, modal=True)
        d.add_button('Abbrechen', Gtk.ResponseType.CANCEL)
        d.add_button(ok, Gtk.ResponseType.OK)
        d.set_default_response(Gtk.ResponseType.OK)
        c = d.get_content_area()
        c.set_spacing(8)
        c.set_border_width(14)
        c.pack_start(label(text), False, False, 0)
        e = Gtk.Entry(text=default, activates_default=True)
        e.set_width_chars(34)
        if password:
            e.set_visibility(False)
            e.set_input_purpose(Gtk.InputPurpose.PASSWORD)
            sh = Gtk.CheckButton(label='Passwort anzeigen')
            sh.connect('toggled', lambda b: e.set_visibility(b.get_active()))
        c.pack_start(e, False, False, 0)
        if password:
            c.pack_start(sh, False, False, 0)
        d.show_all()
        r = d.run()
        val = e.get_text()
        d.destroy()
        return val if r == Gtk.ResponseType.OK else None

    def result_cb(refresh=True):
        def cb(res):
            ok, text = res
            say(text)
            if not ok:
                notice(text, True)
            if refresh:
                reload_all()
        return cb

    notices = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    box.pack_start(notices, False, False, 0)

    def notice(text, err=False):
        clear(notices)
        if text:
            l = label(text, 'row-desc')
            notices.pack_start(l, False, False, 0)
            notices.show_all()

    def listbox_container():
        c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        c.get_style_context().add_class('setting-row')
        return c

    def item_row(title, sub, buttons):
        r = Gtk.Box(spacing=10)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        a = label(title, 'row-title')
        a.set_ellipsize(Pango.EllipsizeMode.END)
        t.pack_start(a, False, False, 0)
        if sub:
            t.pack_start(label(sub, 'row-desc'), False, False, 0)
        r.pack_start(t, True, True, 0)
        for text, cb in buttons:
            b = Gtk.Button(label=text)
            b.set_valign(Gtk.Align.CENTER)
            b.connect('clicked', lambda *_a, cb=cb: cb())
            r.pack_end(b, False, False, 0)
        r.show_all()
        return r

    # ---------------- Übersicht
    app.section(box, 'Übersicht')
    ov = listbox_container()
    box.pack_start(ov, False, False, 0)
    app.page_index.setdefault(TITLE, []).append('status verbindung ip gateway dns signal geschwindigkeit internet flugmodus')
    airplane_sw = Gtk.Switch()
    airplane_sw.set_valign(Gtk.Align.CENTER)
    wifi_sw = Gtk.Switch()
    wifi_sw.set_valign(Gtk.Align.CENTER)
    guard = {'on': False}

    def on_airplane(sw, _p):
        if guard['on']:
            return
        on = sw.get_active()
        bg(lambda: act(cmd_radio('all', not on), 'Flugmodus ist an.' if on else 'Funk ist wieder an.'), result_cb())

    def on_wifi(sw, _p):
        if guard['on']:
            return
        on = sw.get_active()
        bg(lambda: act(cmd_radio('wifi', on), 'WLAN ist an.' if on else 'WLAN ist aus.'), result_cb())

    airplane_sw.connect('notify::active', on_airplane)
    wifi_sw.connect('notify::active', on_wifi)
    app.row(box, 'Flugmodus', airplane_sw, 'Schaltet WLAN und Mobilfunk gemeinsam aus (nmcli radio all). Ein Hardware-Schalter am Gerät wird nicht überschrieben.')
    rf_note = label('', 'row-desc')
    box.pack_start(rf_note, False, False, 0)

    def check_internet():
        say('Internetverbindung wird geprüft …')
        bg(lambda: nm(['-t', '-g', 'CONNECTIVITY', 'networking', 'connectivity', 'check'], 25),
           lambda r: (say(CONNECTIVITY_DE.get(r[1].strip(), 'Prüfung fehlgeschlagen.') if r[0] == 0 else nm_error_text(r[0], r[2])), reload_all()))

    app.button(box, 'Internet prüfen', 'Jetzt prüfen', check_internet, 'Fragt über NetworkManager ab, ob das Internet erreichbar ist.')

    def fill_overview(st):
        clear(ov)
        if st['error']:
            ov.pack_start(label(st['error']), False, False, 0)
            ov.show_all()
            return
        a = st['active']
        lines = []
        if a:
            lines.append(('Verbindung', '%s: %s' % (TYPE_DE.get(a['type'], a['type']), a['name'] or a['device'])))
            lines.append(('Adapter', a['device']))
            if a['ip4']:
                lines.append(('IPv4-Adresse', ', '.join(a['ip4'])))
            if a['gw4']:
                lines.append(('Gateway', a['gw4']))
            if a['ip6']:
                lines.append(('IPv6-Adresse', ', '.join(a['ip6'][:3])))
            if a['dns']:
                lines.append(('DNS-Server', ', '.join(a['dns'])))
            if a['mac']:
                lines.append(('MAC-Adresse', a['mac']))
            if a['signal'] is not None:
                lines.append(('Signal', '%d %%  %s' % (a['signal'], signal_bars(a['signal']))))
            if a['speed']:
                lines.append(('Geschwindigkeit', a['speed']))
        else:
            lines.append(('Verbindung', 'Keine aktive Kabel- oder WLAN-Verbindung.'))
        lines.append(('Internet', CONNECTIVITY_DE.get(st['connectivity'], 'Unbekannt')))
        if not any(d['type'] in ('ethernet', 'wifi') for d in st['devices']):
            lines.append(('Hinweis', 'Es wurde kein Netzwerkadapter gefunden.'))
        g = Gtk.Grid(column_spacing=18, row_spacing=3)
        for i, (k, v) in enumerate(lines):
            g.attach(label(k, 'row-desc'), 0, i, 1, 1)
            vl = label(v, 'row-title')
            vl.set_selectable(True)
            g.attach(vl, 1, i, 1, 1)
        ov.pack_start(g, False, False, 0)
        ov.show_all()

    # ---------------- WLAN
    app.section(box, 'WLAN')
    app.row(box, 'WLAN', wifi_sw, 'Schaltet den WLAN-Funk ein oder aus.')
    wifi_note = label('', 'row-desc')
    box.pack_start(wifi_note, False, False, 0)
    wifi_list = listbox_container()
    box.pack_start(wifi_list, False, False, 0)
    wbtns = Gtk.Box(spacing=8)
    scan_b = Gtk.Button(label='Neu suchen')
    hid_b = Gtk.Button(label='Verstecktes Netzwerk …')
    wbtns.pack_start(scan_b, False, False, 0)
    wbtns.pack_start(hid_b, False, False, 0)
    box.pack_start(wbtns, False, False, 0)

    def scan():
        say('Suche nach WLAN-Netzwerken …')
        bg(lambda: nm(['device', 'wifi', 'rescan'], 15), lambda r: (reload_all(), say('Suche abgeschlossen.')))

    scan_b.connect('clicked', lambda *_: scan())

    def connect_wifi(w, hidden=False):
        ssid = w['ssid'] if w else ask_text('Verstecktes Netzwerk', 'Name (SSID) des versteckten Netzwerks:', ok='Weiter')
        if not ssid:
            return
        err = valid_ssid(ssid)
        if err:
            notice(err, True)
            return
        known = next((c for c in (state['st'] or {}).get('connections', []) if c['name'] == ssid and c['type'] == '802-11-wireless'), None)
        if known and not hidden:
            say('Verbinde mit „%s“ …' % ssid)
            bg(lambda: act(cmd_connection_up(known['uuid']), 'Mit „%s“ verbunden.' % ssid, 60), result_cb())
            return
        secured = True if hidden or not w else not is_open(w['security'])
        if hidden:
            sec = ask_yes_no_secured()
            if sec is None:
                return
            secured = sec
        if w and is_enterprise(w['security']):
            notice('„%s“ ist ein Unternehmens-WLAN (802.1X). Das kann hier noch nicht eingerichtet werden.' % ssid, True)
            return
        pw = ''
        if secured:
            pw = ask_text('Mit „%s“ verbinden' % ssid, 'Passwort für das Netzwerk (mindestens 8 Zeichen):', password=True, ok='Verbinden')
            if pw is None:
                return
        say('Verbinde mit „%s“ …' % ssid)
        ifn = (state['st'] or {}).get('wifi_dev') or None
        bg(lambda: do_wifi_connect(ssid, pw, hidden, ifn, secured), result_cb())

    def ask_yes_no_secured():
        d = Gtk.MessageDialog(transient_for=app.window, modal=True, message_type=Gtk.MessageType.QUESTION, text='Ist das Netzwerk mit einem Passwort geschützt?')
        d.add_button('Abbrechen', Gtk.ResponseType.CANCEL)
        d.add_button('Ohne Passwort', Gtk.ResponseType.NO)
        d.add_button('Mit Passwort', Gtk.ResponseType.YES)
        r = d.run()
        d.destroy()
        return None if r not in (Gtk.ResponseType.YES, Gtk.ResponseType.NO) else r == Gtk.ResponseType.YES

    hid_b.connect('clicked', lambda *_: connect_wifi(None, True))

    def disconnect_wifi(dev):
        if not IFACE_RE.match(dev or ''):
            return
        bg(lambda: act(['device', 'disconnect', dev], 'WLAN getrennt.'), result_cb())

    def fill_wifi(st):
        clear(wifi_list)
        radio = st['radio']
        if st['error'] or not st['wifi_dev']:
            wifi_note.set_text('' if st['error'] else 'Kein WLAN-Adapter gefunden.')
            wifi_sw.set_sensitive(False)
            return
        wifi_sw.set_sensitive(radio is not None)
        if radio and not radio[0]:
            wifi_note.set_text('WLAN ist ausgeschaltet.')
        elif not st['wifi']:
            wifi_note.set_text('Keine Netzwerke in Reichweite gefunden (zuletzt gespeicherte Liste). „Neu suchen“ aktualisiert sie.')
        else:
            wifi_note.set_text('')
        for w in st['wifi'][:40]:
            sub = '%s  ·  %d %%  %s  ·  %s' % ('Verbunden' if w['active'] else security_text(w['security']), w['signal'], signal_bars(w['signal']), security_text(w['security']) if w['active'] else ('Kanal ' + w['chan'] if w['chan'] else ''))
            btns = [('Trennen', lambda d=st['wifi_dev']: disconnect_wifi(d))] if w['active'] else [('Verbinden', lambda w=w: connect_wifi(w))]
            wifi_list.pack_start(item_row(w['ssid'], sub, btns), False, False, 0)
        wifi_list.show_all()

    # Hotspot
    app.section(box, 'Hotspot')
    hs_note = label('', 'row-desc')
    box.pack_start(hs_note, False, False, 0)
    hs_ssid = Gtk.Entry(text=(state.get('host') or 'Aurora') + '-Hotspot', max_length=32)
    hs_pw = Gtk.Entry(visibility=False, placeholder_text='Passwort (mind. 8 Zeichen)')
    hs_pw.set_input_purpose(Gtk.InputPurpose.PASSWORD)
    hs_box = Gtk.Box(spacing=8)
    hs_start = Gtk.Button(label='Hotspot starten')
    hs_stop = Gtk.Button(label='Hotspot beenden')
    hs_box.pack_start(hs_start, False, False, 0)
    hs_box.pack_start(hs_stop, False, False, 0)
    app.row(box, 'Name des Hotspots', hs_ssid, 'Netzwerkname (SSID), 1 bis 32 Zeichen.')
    app.row(box, 'Passwort des Hotspots', hs_pw, 'Mindestens 8 Zeichen (WPA2). Es wird nicht gespeichert.')
    app.row(box, 'Hotspot', hs_box, 'Teilt die Internetverbindung des Kabels über das WLAN. Dabei ist der Adapter nicht mit einem anderen WLAN verbunden.')

    def start_hotspot(*_):
        ssid, pw = hs_ssid.get_text(), hs_pw.get_text()
        err = valid_ssid(ssid) or valid_wpa_password(pw)
        if err:
            notice(err, True)
            return
        dev = (state['st'] or {}).get('wifi_dev')
        if not dev:
            notice('Kein WLAN-Adapter gefunden.', True)
            return
        if not confirm('Hotspot starten?', 'Der WLAN-Adapter wird für den Hotspot verwendet; eine bestehende WLAN-Verbindung wird dabei getrennt.', 'Starten'):
            return
        say('Hotspot wird gestartet …')
        bg(lambda: do_hotspot_start(ssid, pw, dev), result_cb())

    def stop_hotspot(*_):
        uid = hs_state.get('uuid')
        if uid:
            bg(lambda: do_hotspot_stop(uid), result_cb())

    hs_state = {}
    hs_start.connect('clicked', start_hotspot)
    hs_stop.connect('clicked', stop_hotspot)

    def fill_hotspot(st):
        act_hs = next((c for c in st['connections'] if c['name'] == HOTSPOT_NAME and c['device']), None)
        hs_state['uuid'] = act_hs['uuid'] if act_hs else ''
        hs_stop.set_sensitive(bool(act_hs))
        hs_start.set_sensitive(bool(st['wifi_dev']) and not act_hs)
        hs_note.set_text('Hotspot „%s“ ist aktiv.' % HOTSPOT_NAME if act_hs else '')

    # ---------------- Gespeicherte Verbindungen
    app.section(box, 'Gespeicherte Verbindungen')
    conn_list = listbox_container()
    box.pack_start(conn_list, False, False, 0)

    def forget(c):
        if not confirm('Verbindung „%s“ vergessen?' % c['name'], 'Das gespeicherte Profil (inklusive Passwort) wird gelöscht. Die Verbindung muss danach neu eingerichtet werden.', 'Vergessen'):
            return
        bg(lambda: act(cmd_connection_delete(c['uuid']), 'Verbindung „%s“ vergessen.' % c['name']), result_cb())

    def rename(c):
        n = ask_text('Verbindung umbenennen', 'Neuer Name für „%s“:' % c['name'], c['name'], ok='Umbenennen')
        if n is None or n.strip() == c['name']:
            return
        try:
            args = cmd_rename(c['uuid'], n)
        except ValueError as e:
            notice(str(e), True)
            return
        bg(lambda: act(args, 'Umbenannt in „%s“.' % n.strip()), result_cb())

    def toggle_conn(c):
        if c['device']:
            bg(lambda: act(cmd_connection_down(c['uuid']), 'Getrennt.'), result_cb())
        else:
            say('Verbinde „%s“ …' % c['name'])
            bg(lambda: act(cmd_connection_up(c['uuid']), 'Verbunden mit „%s“.' % c['name'], 60), result_cb())

    def details(c):
        bg(lambda: load_connection_details(c['uuid']), lambda r: open_details(c, r))

    def fill_conns(st, target, vpn):
        clear(target)
        items = pick_connections(st['connections'], vpn)
        if st['error']:
            return
        if not items:
            target.pack_start(label('Keine VPN-Verbindungen vorhanden.' if vpn else 'Keine gespeicherten Verbindungen.', 'row-desc'), False, False, 0)
        for c in items:
            sub = TYPE_DE.get(c['type'], c['type']) + ('  ·  aktiv auf %s' % c['device'] if c['device'] else '')
            if vpn:
                btns = [('Trennen' if c['device'] else 'Verbinden', lambda c=c: toggle_conn(c)), ('Löschen', lambda c=c: forget(c))]
            else:
                btns = [('Vergessen', lambda c=c: forget(c)), ('Umbenennen', lambda c=c: rename(c)), ('Details …', lambda c=c: details(c)),
                        ('Trennen' if c['device'] else 'Verbinden', lambda c=c: toggle_conn(c))]
            target.pack_start(item_row(c['name'], sub, btns), False, False, 0)
        target.show_all()

    def open_details(c, res):
        kv, err = res
        if kv is None:
            notice(err, True)
            return
        d = Gtk.Dialog(title='Details: ' + c['name'], transient_for=app.window, modal=True)
        d.add_button('Abbrechen', Gtk.ResponseType.CANCEL)
        d.add_button('Speichern', Gtk.ResponseType.OK)
        d.set_default_size(560, -1)
        ca = d.get_content_area()
        ca.set_border_width(14)
        ca.set_spacing(8)
        g = Gtk.Grid(column_spacing=12, row_spacing=6)
        ca.pack_start(g, True, True, 0)
        row_i = [0]

        def add(lbl, w):
            g.attach(label(lbl), 0, row_i[0], 1, 1)
            w.set_hexpand(True)
            g.attach(w, 1, row_i[0], 1, 1)
            row_i[0] += 1
            return w

        ctype = c['type']
        mtu_key = {'802-3-ethernet': '802-3-ethernet.mtu', '802-11-wireless': '802-11-wireless.mtu'}.get(ctype)
        auto = add('Automatisch verbinden', Gtk.Switch(active=first(kv, 'connection.autoconnect', 'yes') == 'yes', halign=Gtk.Align.START))
        prio = add('Priorität (höher = bevorzugt)', Gtk.Entry(text=first(kv, 'connection.autoconnect-priority', '0')))
        mac = first(kv, '802-3-ethernet.mac-address') or first(kv, '802-11-wireless.mac-address') or '(automatisch, vom Adapter)'
        macl = label(mac, 'row-title')
        macl.set_selectable(True)
        add('MAC-Adresse', macl)
        mtu_cur = first(kv, mtu_key, 'auto') if mtu_key else ''
        mtu = None
        if mtu_key:
            mtu = add('MTU (leer = automatisch)', Gtk.Entry(text='' if mtu_cur in ('auto', '0') else mtu_cur))
        widgets = {}
        for ver in (4, 6):
            p = 'ipv%d.' % ver
            cur = first(kv, p + 'method', 'auto')
            cb = Gtk.ComboBoxText()
            for k, t in (('auto', 'Automatisch (DHCP)'), ('manual', 'Manuell'), ('disabled', 'Deaktiviert')):
                cb.append(k, t)
            cb.set_active_id(cur if cur in ('auto', 'manual', 'disabled') else 'auto')
            add('IPv%d' % ver, cb)
            ad = add('  Adressen (z. B. %s)' % ('192.168.1.10/24' if ver == 4 else 'fd00::10/64'), Gtk.Entry(text=', '.join(kv.get(p + 'addresses', []))))
            gw = add('  Gateway', Gtk.Entry(text=first(kv, p + 'gateway')))
            dn = add('  DNS-Server (mit Komma getrennt)', Gtk.Entry(text=', '.join(x for v in kv.get(p + 'dns', []) for x in split_list(v))))
            widgets[ver] = (cb, ad, gw, dn)
        d.show_all()
        while True:
            r = d.run()
            if r != Gtk.ResponseType.OK:
                break
            pr, perr = valid_priority(prio.get_text() or '0')
            if perr:
                notice(perr, True)
                continue
            try:
                cfgs = []
                for ver in (4, 6):
                    cb, ad, gw, dn = widgets[ver]
                    cfgs.append({'method': cb.get_active_id(), 'addresses': ad.get_text(), 'gateway': gw.get_text(), 'dns': dn.get_text()})
                args = cmd_ip_settings(c['uuid'], ctype, cfgs[0], cfgs[1], mtu.get_text() if mtu else '')
                args2 = cmd_autoconnect(c['uuid'], auto.get_active(), pr)
            except ValueError as e:
                notice(str(e), True)
                continue
            d.destroy()

            def save():
                ok, t = act(args2, 'Gespeichert.')
                if not ok:
                    return ok, t
                ok, t = act(args, 'Gespeichert.')
                if ok and c['device']:
                    ok, t = act(cmd_connection_up(c['uuid']), 'Gespeichert und angewendet.', 60)
                return ok, t
            bg(save, result_cb())
            return
        d.destroy()

    # ---------------- VPN
    app.section(box, 'VPN')
    vpn_list = listbox_container()
    box.pack_start(vpn_list, False, False, 0)

    def import_vpn(*_):
        dlg = Gtk.FileChooserDialog(title='VPN-Datei importieren (WireGuard .conf oder OpenVPN .ovpn)', transient_for=app.window, action=Gtk.FileChooserAction.OPEN)
        dlg.add_button('Abbrechen', Gtk.ResponseType.CANCEL)
        dlg.add_button('Importieren', Gtk.ResponseType.OK)
        r = dlg.run()
        path = dlg.get_filename()
        dlg.destroy()
        if r != Gtk.ResponseType.OK or not path:
            return
        try:
            args = cmd_import(vpn_kind_for(path), path)
        except ValueError as e:
            notice(str(e), True)
            return
        say('Importiere VPN …')
        bg(lambda: act(args, 'VPN importiert.', 30), result_cb())

    app.button(box, 'VPN importieren', 'Datei wählen …', import_vpn, 'WireGuard (.conf) oder OpenVPN (.ovpn). Der Typ wird an der Endung erkannt.')

    # ---------------- Proxy
    app.section(box, 'Proxy')
    proxy_box = listbox_container()
    box.pack_start(proxy_box, False, False, 0)
    proxy_w = {}

    def build_proxy():
        cfg = read_proxy()
        if cfg is None:
            proxy_box.pack_start(label('Proxy-Einstellungen sind nicht verfügbar (gsettings oder das GNOME-Proxy-Schema fehlt).', 'row-desc'), False, False, 0)
            return
        mode = Gtk.ComboBoxText()
        for k, t in (('none', 'Kein Proxy'), ('manual', 'Manuell'), ('auto', 'Automatisch (Konfigurationsdatei)')):
            mode.append(k, t)
        mode.set_active_id(cfg['mode'] if cfg['mode'] in ('none', 'manual', 'auto') else 'none')
        g = Gtk.Grid(column_spacing=10, row_spacing=6)
        g.attach(label('Modus'), 0, 0, 1, 1)
        g.attach(mode, 1, 0, 3, 1)
        ents = {}
        for i, sect in enumerate(('http', 'https', 'socks')):
            h = Gtk.Entry(text=cfg[sect][0], hexpand=True)
            p = Gtk.Entry(text=cfg[sect][1], width_chars=6)
            g.attach(label(sect.upper() + '-Proxy'), 0, i + 1, 1, 1)
            g.attach(h, 1, i + 1, 1, 1)
            g.attach(label('Port'), 2, i + 1, 1, 1)
            g.attach(p, 3, i + 1, 1, 1)
            ents[sect] = (h, p)
        au = Gtk.Entry(text=cfg['autoconfig'], hexpand=True)
        g.attach(label('Konfigurationsdatei (URL)'), 0, 4, 1, 1)
        g.attach(au, 1, 4, 3, 1)
        save = Gtk.Button(label='Proxy übernehmen')
        save.set_halign(Gtk.Align.START)

        def do_save(*_):
            c2 = {'mode': mode.get_active_id(), 'autoconfig': au.get_text()}
            for sect, (h, p) in ents.items():
                c2[sect] = (h.get_text(), p.get_text())
            try:
                cmds = gsettings_proxy_cmds(c2)
            except ValueError as e:
                notice(str(e), True)
                return

            def work():
                for cm in cmds:
                    rc, _o, er = run(cm, 8)
                    if rc != 0:
                        return False, 'Proxy konnte nicht gespeichert werden: ' + (er.strip() or 'Fehler')
                return True, 'Proxy gespeichert.'
            bg(work, result_cb(False))
        save.connect('clicked', do_save)
        proxy_box.pack_start(g, False, False, 0)
        proxy_box.pack_start(save, False, False, 4)
        proxy_box.pack_start(label('Gilt für Programme, die den GNOME-/System-Proxy beachten (z. B. Browser, GTK-Apps). Nicht jedes Programm tut das.', 'row-desc'), False, False, 0)

    build_proxy()

    # ---------------- Rechnername
    app.section(box, 'Rechnername')
    host_e = Gtk.Entry(text=current_hostname(), max_length=63)
    host_b = Gtk.Button(label='Rechnernamen ändern')
    hb = Gtk.Box(spacing=8)
    hb.pack_start(host_e, True, True, 0)
    hb.pack_start(host_b, False, False, 0)
    app.row(box, 'Name dieses Rechners', hb, 'Ändern verlangt Administratorrechte (Anmeldefenster von pkexec) und geschieht nur nach Klick auf den Knopf.')

    def set_host(*_):
        n = host_e.get_text().strip()
        err = valid_hostname(n)
        if err:
            notice(err, True)
            return
        if n == current_hostname():
            say('Der Name ist schon so gesetzt.')
            return
        if not confirm('Rechnernamen ändern?', 'Der Rechner heißt danach „%s“. Dafür wird das Administratorpasswort abgefragt.' % n, 'Ändern'):
            return
        bg(lambda: do_set_hostname(n), result_cb(False))
    host_b.connect('clicked', set_host)

    # ---------------- Firewall
    app.section(box, 'Firewall (nur Anzeige)')
    fw_label = label('Wird gelesen …', 'row-desc')
    fw_label.set_selectable(True)
    box.pack_start(fw_label, False, False, 0)
    bg(read_firewall, lambda items: fw_label.set_text(firewall_text(items)))

    # ---------------- laden / aktualisieren
    rb = Gtk.Button(label='Seite aktualisieren')
    rb.set_halign(Gtk.Align.START)
    rb.connect('clicked', lambda *_: reload_all())
    box.pack_start(rb, False, False, 8)

    def apply_state(st):
        state['st'] = st
        state['busy'] = False
        guard['on'] = True
        try:
            if st['error']:
                notice(st['error'])
            rd = st['radio']
            wifi_sw.set_active(bool(rd and rd[0]))
            airplane_sw.set_active(bool(rd and not rd[0] and not rd[1]))
            airplane_sw.set_sensitive(rd is not None)
            fill_overview(st)
            fill_wifi(st)
            fill_hotspot(st)
            fill_conns(st, conn_list, False)
            fill_conns(st, vpn_list, True)
            rk = st['rfkill']
            rf_note.set_text('Ein Hardware-Schalter blockiert den Funk – bitte am Gerät umlegen.' if rk and rk['hard'] else '')
        finally:
            guard['on'] = False

    def reload_all():
        if state['busy']:
            return False
        state['busy'] = True
        bg(read_state_safe, apply_state)
        return False

    def read_state_safe():
        try:
            return read_status()
        except Exception as e:
            return {'nm': True, 'error': 'Netzwerkstatus konnte nicht gelesen werden: %s' % e, 'devices': [], 'connections': [], 'wifi': [], 'radio': None,
                    'connectivity': '', 'active': None, 'rfkill': None, 'hostname': '', 'wifi_dev': ''}

    def tick():
        if box.get_mapped():
            reload_all()
        return True

    GLib.timeout_add_seconds(20, tick)
    reload_all()
