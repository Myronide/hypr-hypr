"""Aurora-Einstellungen: Geräte & Anschlüsse (USB, Laufwerke, Firmware, Thunderbolt). Reine Logik oben (testbar), GTK in build()."""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import _devlib as D  # noqa: E402

TITLE = 'Geräte & Anschlüsse'
GROUP = 'SYSTEM'
ICONS = ['drive-removable-media-symbolic', 'drive-harddisk-symbolic', 'media-removable-symbolic']
ORDER = 50

LSBLK_COLS = 'NAME,PATH,LABEL,SIZE,TYPE,FSTYPE,MOUNTPOINTS,RM,HOTPLUG,RO,MODEL,PKNAME'
DEV_RE = re.compile(r'^/dev/[A-Za-z0-9_./-]+$')
SYSTEM_MOUNTS = ('/', '/boot', '/boot/efi', '/efi', '/home', '/usr', '/var', '/etc', '/opt', '/nix', '/tmp', '/srv', '/gnu')
SKIP_FS = {'swap', 'crypto_LUKS', 'LVM2_member', 'linux_raid_member', 'zfs_member'}


# ---------- reine Logik ----------
def parse_lsusb(text):
    """`lsusb` -> [{bus, dev, id, name, hub}]."""
    out = []
    for line in (text or '').splitlines():
        m = re.match(r'^Bus (\d+) Device (\d+): ID ([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\s*(.*)$', line.strip())
        if m:
            name = m.group(4).strip() or 'Unbekanntes Gerät'
            out.append({'bus': m.group(1), 'dev': m.group(2), 'id': m.group(3).lower(), 'name': name, 'hub': 'root hub' in name.lower()})
    return out


def _mounts(node):
    mps = node.get('mountpoints')
    if mps is None:
        mps = [node.get('mountpoint')]
    return [m for m in mps if m]


def _truthy(v):
    return v is True or v in ('1', 1, 'true')


def parse_lsblk(text):
    """`lsblk -J` -> flache Liste von Datenträgern mit Dateisystem:
    {path, name, label, size, fstype, mounts, removable, readonly, disk, model}. disk = übergeordnetes Gerät (für Auswerfen)."""
    try:
        data = json.loads(text or '')
    except ValueError:
        return []
    out = []

    def walk(nodes, disk=None, model=''):
        for n in nodes or []:
            if not isinstance(n, dict):
                continue
            typ = n.get('type') or ''
            path = n.get('path') or ('/dev/' + str(n.get('name', '')))
            top = disk
            mdl = (n.get('model') or model or '').strip()
            if typ in ('disk', 'rom') and top is None:
                top = {'path': path, 'removable': _truthy(n.get('rm')) or _truthy(n.get('hotplug')), 'model': mdl}
            fs = n.get('fstype')
            if fs and fs not in SKIP_FS and typ not in ('loop',) and not str(n.get('name', '')).startswith('zram'):
                out.append({'path': path, 'name': n.get('name', ''), 'label': (n.get('label') or '').strip(), 'size': n.get('size') or '',
                            'fstype': fs, 'mounts': _mounts(n), 'readonly': _truthy(n.get('ro')),
                            'removable': bool(top and top['removable']), 'disk': top['path'] if top else None,
                            'model': (top or {}).get('model', '') or mdl})
            walk(n.get('children'), top, mdl)
    walk(data.get('blockdevices'), None)
    return out


def is_system_mount(mp):
    return mp in SYSTEM_MOUNTS or any(mp.startswith(s + '/') for s in ('/boot', '/usr', '/var', '/etc'))


def valid_device(path, known):
    return bool(DEV_RE.match(path or '')) and path in {d['path'] for d in known}


def cmd_mount(path):
    return ['udisksctl', 'mount', '--no-user-interaction', '-b', path]


def cmd_unmount(path):
    return ['udisksctl', 'unmount', '--no-user-interaction', '-b', path]


def cmd_poweroff(disk):
    return ['udisksctl', 'power-off', '--no-user-interaction', '-b', disk]


def clean_text(text, limit=40):
    lines = [l.rstrip() for l in D.strip_ansi(text).splitlines() if l.strip() and not re.match(r'^[\s⠀-⣿|/\\-]+$', l)]
    if len(lines) > limit:
        lines = lines[:limit] + ['…']
    return '\n'.join(lines)


def firmware_summary(rc, out, err):
    """`fwupdmgr get-updates`: Rückgabe 0 = Updates vorhanden, 2 = nichts zu tun."""
    txt = clean_text(out or err)
    low = (out + ' ' + err).lower()
    if rc == 0:
        return 'Es gibt Firmware-Updates (nur Anzeige – installieren z. B. im Terminal mit „fwupdmgr update“):\n' + txt
    if rc == 2 or 'no updates' in low or 'no updatable' in low or 'no upgrades' in low:
        return 'Keine Firmware-Updates verfügbar.\n' + txt if txt else 'Keine Firmware-Updates verfügbar.'
    return 'Abfrage fehlgeschlagen (%s): %s' % (rc, txt or 'keine Ausgabe')


# ---------- Oberfläche ----------
def build(app):
    from gi.repository import Gtk
    box = app.page(TITLE, 'USB-Geräte, Laufwerke und Wechseldatenträger (einhängen, auswerfen), Firmware-Updates und Thunderbolt.')
    say = app.message
    st = {'drives': [], 'busy': False}

    app.section(box, 'Laufwerke und Wechseldatenträger')
    drives_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(drives_box, False, False, 0)
    app.section(box, 'USB-Geräte')
    usb_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(usb_box, False, False, 0)
    app.section(box, 'Firmware-Updates')
    fw_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(fw_box, False, False, 0)
    app.section(box, 'Thunderbolt')
    tb_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(tb_box, False, False, 0)

    def action(argv, ok, steps=None):
        say('Wird ausgeführt …')

        def work():
            for a in (steps or []) + [argv]:
                r = D.run_cmd(a, 30)
                if r.returncode != 0:
                    return r
            return r

        def done(res):
            if isinstance(res, Exception):
                say('Fehlgeschlagen: %s' % res)
            elif res.returncode != 0:
                say('Fehlgeschlagen: ' + ((res.stderr or res.stdout or '').strip().splitlines() or ['Fehler %s' % res.returncode])[-1])
            else:
                say(ok)
            refresh()
        D.bg(work, done)

    def do_mount(path):
        if not valid_device(path, st['drives']):
            return say('Unbekanntes Gerät.')
        action(cmd_mount(path), 'Eingehängt: %s' % path)

    def do_unmount(path):
        if not valid_device(path, st['drives']):
            return say('Unbekanntes Gerät.')
        action(cmd_unmount(path), 'Ausgehängt: %s' % path)

    def do_eject(d):
        if not valid_device(d['path'], st['drives']) or not DEV_RE.match(d['disk'] or ''):
            return say('Unbekanntes Gerät.')
        steps = [cmd_unmount(d['path'])] if d['mounts'] else []
        action(cmd_poweroff(d['disk']), 'Sicher entfernt – das Gerät kann abgezogen werden.', steps)

    def show_drives(drives):
        st['drives'] = drives
        D.ui_clear(drives_box)
        if not D.which('lsblk'):
            drives_box.pack_start(D.ui_label('lsblk fehlt (Paket util-linux).', 'row-desc'), False, False, 0)
        elif not drives:
            drives_box.pack_start(D.ui_label('Keine Laufwerke mit Dateisystem gefunden.', 'row-desc'), False, False, 0)
        have_ud = bool(D.which('udisksctl'))
        for d in drives:
            title = (d['label'] or d['model'] or d['name']) + ('  (%s)' % d['size'] if d['size'] else '')
            if d['mounts']:
                where = 'eingehängt unter ' + ', '.join(d['mounts'])
            else:
                where = 'nicht eingehängt'
            desc = ' · '.join([d['path'], d['fstype'], where] + (['Wechseldatenträger'] if d['removable'] else []) + (['schreibgeschützt'] if d['readonly'] else []))
            ws = []
            system = any(is_system_mount(m) for m in d['mounts'])
            if have_ud and not system:
                if d['mounts']:
                    ws.append(D.ui_button('Aushängen', lambda p=d['path']: do_unmount(p)))
                    if d['removable'] and d['disk']:
                        ws.append(D.ui_button('Auswerfen', lambda dd=d: do_eject(dd)))
                else:
                    ws.append(D.ui_button('Einhängen', lambda p=d['path']: do_mount(p)))
                    if d['removable'] and d['disk']:
                        ws.append(D.ui_button('Auswerfen', lambda dd=d: do_eject(dd)))
            elif system:
                desc += ' · Systemlaufwerk'
            drives_box.pack_start(D.ui_item(title, desc, *ws), False, False, 0)
        if drives and not have_ud:
            drives_box.pack_start(D.ui_label('Zum Ein- und Aushängen wird udisks2 benötigt (Paket „udisks2“).', 'row-desc'), False, False, 0)
        drives_box.pack_start(D.ui_item('Liste aktualisieren', '', D.ui_button('Aktualisieren', refresh)), False, False, 0)
        drives_box.show_all()

    def show_usb(devs):
        D.ui_clear(usb_box)
        if devs is None:
            usb_box.pack_start(D.ui_label('lsusb fehlt (Paket usbutils).', 'row-desc'), False, False, 0)
        else:
            real = [d for d in devs if not d['hub']]
            if not real:
                usb_box.pack_start(D.ui_label('Keine USB-Geräte gefunden.', 'row-desc'), False, False, 0)
            for d in real:
                usb_box.pack_start(D.ui_item(d['name'], 'Bus %s · Gerät %s · ID %s' % (d['bus'], d['dev'], d['id'])), False, False, 0)
            hubs = len(devs) - len(real)
            if hubs:
                usb_box.pack_start(D.ui_label('Dazu %d USB-Hauptknoten (Root-Hubs) des Rechners.' % hubs, 'row-desc'), False, False, 0)
        usb_box.show_all()

    def show_tb(text):
        D.ui_clear(tb_box)
        tb_box.pack_start(D.ui_label(text, 'row-desc', selectable=True), False, False, 0)
        tb_box.show_all()

    def refresh(*_):
        if st['busy']:
            return
        st['busy'] = True

        def work():
            r = {'drives': [], 'usb': None, 'tb': ''}
            if D.which('lsblk'):
                r['drives'] = parse_lsblk(D.run_cmd(['lsblk', '-J', '-o', LSBLK_COLS], 8).stdout)
            if D.which('lsusb'):
                r['usb'] = parse_lsusb(D.run_cmd(['lsusb'], 8).stdout)
            if not D.which('boltctl'):
                r['tb'] = 'boltctl ist nicht installiert (Paket „bolt“). Ohne Thunderbolt-Anschluss ist das nichts Schlimmes.'
            else:
                t = D.run_cmd(['boltctl', 'list'], 8)
                txt = clean_text(t.stdout)
                if t.returncode != 0:
                    r['tb'] = 'Thunderbolt-Dienst nicht erreichbar: %s' % (clean_text(t.stderr, 3) or 'keine Antwort')
                else:
                    r['tb'] = txt or 'Keine Thunderbolt-Geräte angeschlossen.'
            return r

        def done(r):
            st['busy'] = False
            if isinstance(r, Exception):
                return say('Geräteliste konnte nicht gelesen werden: %s' % r)
            show_drives(r['drives'])
            show_usb(r['usb'])
            show_tb(r['tb'])
        D.bg(work, done)

    # --- Firmware (nur auf Klick, kann das Netz brauchen) ---
    fw_out = D.ui_label('Noch nicht geprüft.', 'row-desc', selectable=True)

    def check_fw():
        if not D.which('fwupdmgr'):
            fw_out.set_text('fwupd ist nicht installiert (Paket „fwupd“).')
            return
        fw_out.set_text('Prüfe … (bis zu 40 Sekunden)')

        def work():
            return D.run_cmd(['fwupdmgr', 'get-updates', '--no-metadata-check', '--no-unreported-check'], 40, env=D.C_LOCALE())

        def done(r):
            if isinstance(r, Exception):
                fw_out.set_text('Abfrage fehlgeschlagen: %s' % r)
            elif r.returncode == 124:
                fw_out.set_text('Zeitlimit überschritten (fwupd antwortet nicht).')
            else:
                fw_out.set_text(firmware_summary(r.returncode, r.stdout or '', r.stderr or ''))
        D.bg(work, done)
    fw_box.pack_start(D.ui_item('Nach Updates suchen', 'Zeigt nur an, was laut lokalen Metadaten verfügbar ist. Installiert wird nichts.', D.ui_button('Prüfen', check_fw)), False, False, 0)
    fw_box.pack_start(fw_out, False, False, 0)
    fw_box.show_all()

    box.connect('map', refresh)
    return box
