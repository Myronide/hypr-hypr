"""Aurora-Einstellungen: Über dieses System (Hardware, Versionen, Software-Updates, Speicher)."""
import os, sys, re, json, shutil, subprocess
from pathlib import Path
_d = os.path.dirname(os.path.realpath(__file__))
if _d not in sys.path:
    sys.path.insert(0, _d)
import dx_sysutil as U

TITLE = 'Über dieses System'
GROUP = 'SYSTEM'
ICONS = ['help-about-symbolic', 'computer-symbolic', 'dialog-information-symbolic']
ORDER = 90

REAL_FS = {'ext2', 'ext3', 'ext4', 'btrfs', 'xfs', 'f2fs', 'vfat', 'exfat', 'ntfs', 'ntfs3', 'fuseblk', 'jfs', 'reiserfs', 'zfs', 'bcachefs'}

# ---------- reine Logik ----------

def parse_os_release(text):
    kv = U.parse_kv(text)
    return {k: v.strip('"\'') for k, v in kv.items()}


def parse_cpu(text):
    """/proc/cpuinfo -> (Modellname, logische Kerne)."""
    names = re.findall(r'^model name\s*:\s*(.+)$', text or '', re.M)
    n = len(re.findall(r'^processor\s*:', text or '', re.M))
    model = re.sub(r'\s+', ' ', names[0]).strip() if names else ''
    if not model:
        m = re.search(r'^(?:Hardware|Model)\s*:\s*(.+)$', text or '', re.M)
        model = m.group(1).strip() if m else 'unbekannt'
    return model, n


def parse_meminfo(text):
    """-> (gesamt, verfügbar) in Byte; fehlend 0."""
    def get(k):
        m = re.search(r'^%s:\s+(\d+)\s*kB' % k, text or '', re.M)
        return int(m.group(1)) * 1024 if m else 0
    return get('MemTotal'), get('MemAvailable')


def fmt_uptime(sec):
    try:
        s = int(float(sec))
    except (TypeError, ValueError):
        return '?'
    d, r = divmod(s, 86400)
    h, r = divmod(r, 3600)
    m = r // 60
    parts = (['%d Tag%s' % (d, '' if d == 1 else 'e')] if d else []) + (['%d Std.' % h] if h or d else []) + ['%d Min.' % m]
    return ' '.join(parts)


def parse_gpus(text):
    """`lspci -mm` -> Liste von GPU-Namen (VGA, 3D, Display)."""
    gpus = []
    for line in (text or '').splitlines():
        try:
            import shlex
            p = shlex.split(line)
        except ValueError:
            continue
        if len(p) >= 4 and re.search(r'VGA|3D controller|Display controller', p[1]):
            gpus.append('%s %s' % (p[2], p[3]))
    return gpus


def parse_mounts(text):
    """/proc/mounts -> [(Gerät, Einhängepunkt, Typ)] nur echte Dateisysteme, je Gerät einmal (Btrfs-Subvolumes), kürzester Pfad zuerst."""
    seen, out = {}, []
    for line in (text or '').splitlines():
        p = line.split()
        if len(p) < 3 or p[2] not in REAL_FS or not p[0].startswith('/'):
            continue
        mp = p[1].replace('\\040', ' ')
        if p[0] in seen and len(seen[p[0]][1]) <= len(mp):
            continue
        seen[p[0]] = (p[0], mp, p[2])
    return sorted(seen.values(), key=lambda t: t[1])


def disk_usage(mounts, statvfs=os.statvfs):
    res = []
    for dev, mp, fs in mounts:
        try:
            st = statvfs(mp)
        except OSError:
            continue
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        if total:
            res.append({'dev': dev, 'mount': mp, 'fs': fs, 'total': total, 'used': total - st.f_bfree * st.f_frsize, 'free': free})
    return res


def parse_monitors(text):
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        return []
    out = []
    for m in data if isinstance(data, list) else []:
        if isinstance(m, dict) and 'name' in m:
            out.append('%s: %s×%s @ %s Hz, Skalierung %s%s' % (m.get('name'), m.get('width', '?'), m.get('height', '?'),
                       round(float(m.get('refreshRate', 0) or 0)), m.get('scale', 1), ' – ' + str(m['description']) if m.get('description') else ''))
    return out


def parse_checkupdates(rc, out):
    """checkupdates: 0 = Updates, 2 = keine, sonst Fehler -> (Anzahl oder None, Zeilen)."""
    if rc == 0:
        lines = [l for l in (out or '').splitlines() if l.strip()]
        return len(lines), lines
    if rc == 2:
        return 0, []
    return None, []


def dir_size(path, limit_seconds=20):
    """Summe der Dateigrößen ohne Symlinks zu folgen; Fehler einzelner Einträge werden übersprungen."""
    import time
    end = time.monotonic() + limit_seconds
    total, stack = 0, [str(path)]
    while stack and time.monotonic() < end:
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        if e.is_symlink():
                            continue
                        if e.is_dir(follow_symlinks=False):
                            stack.append(e.path)
                        else:
                            total += e.stat(follow_symlinks=False).st_size
                    except OSError:
                        pass
        except OSError:
            pass
    return total


def trash_dir():
    return Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share') / 'Trash'


def build_empty_trash():
    """Befehl zum Leeren des Papierkorbs (nur nach Bestätigung aufrufen)."""
    return ['gio', 'trash', '--empty']


def update_command():
    """Befehl im Terminal: Garuda-Update, sonst pacman -Syu; hält danach offen."""
    base = 'garuda-update' if shutil.which('garuda-update') else 'sudo pacman -Syu'
    return ['sh', '-c', base + '; echo; printf "Fertig. Eingabetaste zum Schließen …"; read _']


def terminal_update_cmd():
    t = U.find_bin('dx-terminal')
    return [t, '--'] + update_command() if t else None


def copy_to_clipboard(text):
    """wl-copy bleibt als Hintergrundprozess bestehen und hält Ausgabekanäle offen: darum Popen mit DEVNULL statt run(capture_output). -> (Code,'','')"""
    try:
        p = subprocess.Popen(['wl-copy'], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        p.stdin.write(text.encode('utf-8'))
        p.stdin.close()
        return (p.wait(timeout=5), '', '')
    except (OSError, subprocess.SubprocessError, ValueError) as e:
        return (1, '', str(e))


def read_text(path):
    try:
        return Path(path).read_text(encoding='utf-8', errors='replace')
    except OSError:
        return ''


def aurora_versions():
    here = Path(os.path.realpath(__file__)).parent.parent
    ver = ''
    for p in (here / 'VERSION', Path.home() / '.config/draconyx/VERSION'):
        ver = read_text(p).strip()
        if ver:
            break
    inst = ''
    try:
        d = json.loads(read_text(Path.home() / '.config/draconyx/install.json') or '{}')
        if isinstance(d, dict):
            inst = ', '.join('%s %s' % (k, v) for k, v in d.items() if isinstance(v, (str, int, float)) and k in ('version', 'installed', 'date', 'commit', 'installedAt'))
    except ValueError:
        pass
    return ver, inst


def collect_info():
    """Sammelt alles Lesbare (Thread). Jedes fehlende Programm ergibt nur einen leeren Wert."""
    os_rel = parse_os_release(read_text('/etc/os-release'))
    cpu, threads = parse_cpu(read_text('/proc/cpuinfo'))
    total, avail = parse_meminfo(read_text('/proc/meminfo'))
    up = read_text('/proc/uptime').split()
    info = {
        'distro': os_rel.get('PRETTY_NAME') or os_rel.get('NAME') or 'unbekannt',
        'kernel': U.run(['uname', '-r'])[1].strip(),
        'host': (read_text('/proc/sys/kernel/hostname') or U.run(['hostname'])[1]).strip(),
        'uptime': fmt_uptime(up[0]) if up else '?',
        'cpu': '%s (%d Threads)' % (cpu, threads) if threads else cpu,
        'gpus': parse_gpus(U.run(['lspci', '-mm'])[1]),
        'ram': (total, avail),
        'disks': disk_usage(parse_mounts(read_text('/proc/mounts'))),
        'monitors': parse_monitors(U.run(['hyprctl', '-j', 'monitors'])[1]),
    }
    hv = U.run(['hyprctl', 'version', '-j'])[1]
    try:
        info['hyprland'] = json.loads(hv).get('tag') or json.loads(hv).get('version') or ''
    except (ValueError, AttributeError):
        info['hyprland'] = ''
    qv = U.run(['qs', '--version'])[1].strip()
    info['quickshell'] = qv
    info['aurora'], info['install'] = aurora_versions()
    return info


def info_text(info):
    t, a = info['ram']
    lines = ['Distribution: %s' % info['distro'], 'Kernel: %s' % info['kernel'], 'Rechnername: %s' % info['host'], 'Laufzeit: %s' % info['uptime'],
             'Prozessor: %s' % info['cpu']]
    lines += ['Grafik: %s' % g for g in info['gpus']] or ['Grafik: unbekannt']
    lines.append('Arbeitsspeicher: %s gesamt, %s verfügbar' % (U.fmt_bytes(t), U.fmt_bytes(a)))
    lines += ['Datenträger %s: %s von %s belegt' % (d['mount'], U.fmt_bytes(d['used']), U.fmt_bytes(d['total'])) for d in info['disks']]
    lines += ['Bildschirm %s' % m for m in info['monitors']]
    lines.append('Hyprland: %s' % (info['hyprland'] or '–'))
    lines.append('Quickshell: %s' % (info['quickshell'] or '–'))
    lines.append('Hypr Hypr/Aurora: %s%s' % (info['aurora'] or '–', ' (%s)' % info['install'] if info['install'] else ''))
    return '\n'.join(lines)

# ---------- Seite ----------

def build(app):
    from gi.repository import Gtk
    box = app.page(TITLE, 'Hardware, Versionen, Software-Updates und Speicherbelegung dieses Computers.')
    labels = {}
    for key, title in (('distro', 'Distribution'), ('kernel', 'Kernel'), ('host', 'Rechnername'), ('uptime', 'Laufzeit'), ('cpu', 'Prozessor'), ('gpu', 'Grafik'),
                       ('ram', 'Arbeitsspeicher'), ('mon', 'Bildschirme'), ('hypr', 'Hyprland'), ('qs', 'Quickshell'), ('aurora', 'Hypr Hypr / Aurora')):
        labels[key] = U.info_label('…')
        app.row(box, title, labels[key], '')
    store = {'info': None}

    def copy():
        if not store['info']:
            app.message('Die Angaben werden noch gelesen.')
            return
        if not shutil.which('wl-copy'):
            app.message('wl-copy fehlt (Paket wl-clipboard).')
            return
        text = info_text(store['info'])

        def done(res):
            app.message('Systeminfo kopiert.' if not isinstance(res, Exception) and res[0] == 0 else 'Kopieren fehlgeschlagen.')
        U.bg(lambda: copy_to_clipboard(text), done)
    app.button(box, 'Systeminfo kopieren', 'Kopieren', copy, 'Legt die obigen Angaben in die Zwischenablage (z. B. für Fehlerberichte).')

    app.section(box, 'Software')
    upd = U.info_label('Suche nach Updates …')
    app.row(box, 'Verfügbare Updates', upd, 'Zählt über checkupdates (pacman-contrib), ohne etwas zu installieren.')

    def run_update():
        cmd = terminal_update_cmd()
        if not cmd:
            app.message('dx-terminal wurde nicht gefunden.')
            return
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            app.message('Terminal mit dem Update-Befehl geöffnet – dort bestätigen.')
        except OSError as e:
            app.message('Terminal konnte nicht gestartet werden: %s' % e)
    app.button(box, 'Updates installieren', 'Im Terminal öffnen', run_update, 'Öffnet ein Terminal mit dem Update-Befehl. Es wird nichts im Hintergrund installiert.')

    def check():
        def work():
            if not shutil.which('checkupdates'):
                return None
            rc, out, _ = U.run(['checkupdates'], timeout=90)
            return parse_checkupdates(rc, out)

        def done(res):
            if isinstance(res, Exception) or res is None:
                upd.set_text('Nicht prüfbar: checkupdates fehlt (Paket pacman-contrib). Im Terminal aktualisieren geht trotzdem.')
            elif res[0] is None:
                upd.set_text('Die Prüfung ist fehlgeschlagen (Netzwerk oder Paketdatenbank gesperrt).')
            elif res[0] == 0:
                upd.set_text('Das System ist aktuell.')
            else:
                upd.set_text('%d Update%s verfügbar.' % (res[0], '' if res[0] == 1 else 's'))
        U.bg(work, done)
    check()
    app.button(box, 'Erneut prüfen', 'Prüfen', lambda: (upd.set_text('Suche nach Updates …'), check()), '')

    app.section(box, 'Speicher')
    disks = U.info_label('Lese Datenträger …')
    app.row(box, 'Belegung je Einhängepunkt', disks, '')
    trash = U.info_label('Berechne …')
    app.row(box, 'Papierkorb', trash, '')
    cache = U.info_label('Berechne …')
    app.row(box, 'Paket-Cache', cache, '/var/cache/pacman/pkg – nur Anzeige. Aufräumen im Terminal, z. B. mit paccache.')

    def empty_trash():
        if not U.confirm(app, 'Papierkorb leeren?', 'Alle Dateien im Papierkorb werden endgültig gelöscht. Das lässt sich nicht rückgängig machen.'):
            return
        cmd = build_empty_trash()
        if not shutil.which(cmd[0]):
            app.message('gio fehlt – Papierkorb kann hier nicht geleert werden.')
            return

        def done(res):
            ok = not isinstance(res, Exception) and res[0] == 0
            app.message('Papierkorb geleert.' if ok else 'Papierkorb konnte nicht geleert werden.')
            sizes()
        U.bg(lambda: U.run(cmd, timeout=120), done)
    app.button(box, 'Papierkorb leeren', 'Papierkorb leeren …', empty_trash, 'Fragt vorher nach.')

    def sizes():
        U.bg(lambda: (dir_size(trash_dir() / 'files'), dir_size('/var/cache/pacman/pkg')), lambda r: (
            (trash.set_text('Größe unbekannt'), cache.set_text('Größe unbekannt')) if isinstance(r, Exception) else
            (trash.set_text(U.fmt_bytes(r[0]) if r[0] else 'leer'), cache.set_text(U.fmt_bytes(r[1]) if r[1] else 'leer oder nicht lesbar'))))
    sizes()

    def fill(info):
        if isinstance(info, Exception):
            labels['distro'].set_text('Angaben konnten nicht gelesen werden: %s' % info)
            return
        store['info'] = info
        t, a = info['ram']
        labels['distro'].set_text(info['distro'])
        labels['kernel'].set_text(info['kernel'] or '–')
        labels['host'].set_text(info['host'] or '–')
        labels['uptime'].set_text(info['uptime'])
        labels['cpu'].set_text(info['cpu'])
        labels['gpu'].set_text('\n'.join(info['gpus']) or 'nicht erkannt (lspci fehlt?)')
        labels['ram'].set_text('%s gesamt, %s verfügbar' % (U.fmt_bytes(t), U.fmt_bytes(a)) if t else '–')
        labels['mon'].set_text('\n'.join(info['monitors']) or 'nicht lesbar (läuft Hyprland?)')
        labels['hypr'].set_text(info['hyprland'] or '–')
        labels['qs'].set_text(info['quickshell'] or '–')
        labels['aurora'].set_text((info['aurora'] or 'unbekannt') + (' (%s)' % info['install'] if info['install'] else ''))
        disks.set_text('\n'.join('%s  (%s, %s): %s von %s belegt, %s frei' % (d['mount'], d['dev'], d['fs'], U.fmt_bytes(d['used']), U.fmt_bytes(d['total']), U.fmt_bytes(d['free']))
                                 for d in info['disks']) or 'Keine Datenträger gefunden.')
    U.bg(collect_info, fill)
