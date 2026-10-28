"""Tests der Seiten Drucker, Benachrichtigungen, Design, Geräte: nur reine Logik, ohne Anzeige, mit Temp-HOME und Attrappen.
Es werden keine echten Einstellungen verändert und keine echten Programme gestartet."""
import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
PAGES = ROOT / 'settings_pages'
sys.path.insert(0, str(PAGES))


def load(name):
    spec = importlib.util.spec_from_file_location('t_' + name, PAGES / (name + '.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


import _devlib as D  # noqa: E402

PR, NO, DE, HW = load('page_printers'), load('page_notifications'), load('page_design'), load('page_hardware')


class TempEnv(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.env = mock.patch.dict(os.environ, {'HOME': self.tmp.name, 'XDG_CONFIG_HOME': self.tmp.name + '/.config', 'XDG_DATA_HOME': self.tmp.name + '/.local/share'})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()


class IniTests(TempEnv):
    def test_set_keeps_other_lines(self):
        t = '# Kommentar\n[Settings]\ngtk-font-name=Inter, 10\ngtk-cursor-theme-name=alt\n\n[Andere]\nx=1\n'
        r = D.ini_set(t, 'Settings', 'gtk-cursor-theme-name', 'neu')
        self.assertIn('gtk-cursor-theme-name=neu', r)
        self.assertIn('# Kommentar', r)
        self.assertIn('gtk-font-name=Inter, 10', r)
        self.assertIn('[Andere]\nx=1', r)
        self.assertEqual(r.count('gtk-cursor-theme-name'), 1)

    def test_set_adds_key_before_next_section(self):
        t = '[A]\na=1\n\n[B]\nb=2\n'
        r = D.ini_set(t, 'A', 'c', '3')
        self.assertEqual(r, '[A]\na=1\nc=3\n\n[B]\nb=2\n')

    def test_set_creates_section_and_empty(self):
        self.assertEqual(D.ini_set('', 'S', 'k', 'v'), '[S]\nk=v\n')
        self.assertEqual(D.ini_set('[A]\na=1\n', 'S', 'k', 'v'), '[A]\na=1\n\n[S]\nk=v\n')

    def test_set_rejects_newlines(self):
        with self.assertRaises(ValueError):
            D.ini_set('', 'S', 'k', 'v\nevil=1')

    def test_get_ignores_comment(self):
        self.assertEqual(D.ini_get('[S]\n#k=0\nk = 5\n', 'S', 'k'), '5')
        self.assertIsNone(D.ini_get('[S]\nk=5\n', 'T', 'k'))

    def test_atomic_write_backup_and_symlink(self):
        f = self.home / 'a.json'
        f.write_text('alt')
        D.atomic_write(f, 'neu', '.vor-aurora')
        D.atomic_write(f, 'neuer', '.vor-aurora')
        self.assertEqual(f.read_text(), 'neuer')
        self.assertEqual((self.home / 'a.json.vor-aurora').read_text(), 'alt')
        real = self.home / 'real.txt'
        real.write_text('x')
        link = self.home / 'link.txt'
        link.symlink_to(real)
        D.atomic_write(link, 'y')
        self.assertTrue(link.is_symlink())
        self.assertEqual(real.read_text(), 'y')
        self.assertFalse([p for p in self.home.iterdir() if p.name.endswith('.tmp')])

    def test_parse_gsettings(self):
        self.assertEqual(D.parse_gsettings("'Papirus-Dark'\n"), 'Papirus-Dark')
        self.assertEqual(D.parse_gsettings('uint32 24\n'), '24')

    def test_run_cmd_missing_program(self):
        r = D.run_cmd(['/nicht/vorhanden/xyz'], 2)
        self.assertEqual(r.returncode, 127)


class PrinterTests(unittest.TestCase):
    LPSTAT = ('printer HP_Laser is idle.  enabled since Mon 01 Jan 2026 10:00:00 AM CET\n\tForm mounted:\n\tDescription: HP LaserJet\n\tLocation: Büro\n\tConnection: direct\n'
              'printer Foto now printing Foto-7.  enabled since Mon 01 Jan 2026\n\tDescription: Foto\n'
              'printer Alt disabled since Mon 01 Jan 2026 - Paused\n'
              'system default destination: HP_Laser\n')

    def test_parse_printers(self):
        p, d = PR.parse_printers(self.LPSTAT)
        self.assertEqual([x['name'] for x in p], ['HP_Laser', 'Foto', 'Alt'])
        self.assertEqual([x['state'] for x in p], ['idle', 'printing', 'disabled'])
        self.assertEqual(p[0]['description'], 'HP LaserJet')
        self.assertEqual(d, 'HP_Laser')
        self.assertEqual(PR.parse_printers('lpstat: Scheduler is not running.\nno system default destination\n'), ([], None))

    def test_parse_jobs_and_cancel(self):
        j = PR.parse_jobs('HP_Laser-12   jason   1024   Mon 01 Jan 2026 10:00:00 AM CET\nFoto-3 anna 99 heute\n')
        self.assertEqual([x['id'] for x in j], ['HP_Laser-12', 'Foto-3'])
        self.assertEqual(j[0]['printer'], 'HP_Laser')
        self.assertEqual(PR.cmd_cancel('HP_Laser-12'), ['cancel', 'HP_Laser-12'])
        for bad in ('-a', 'x; rm -rf ~', '12', '', 'a b-1'):
            with self.assertRaises(ValueError):
                PR.cmd_cancel(bad)

    def test_parse_devices(self):
        t = ('network dnssd://HP%20Color%20LaserJet._ipp._tcp.local/?uuid=abc\ndirect usb://Brother/HL-1110?serial=1\nnetwork socket\nnetwork lpd\n'
             'network ipp\ndirect hp\n')
        d = PR.parse_devices(t)
        self.assertEqual(len(d), 2)
        self.assertEqual(d[0]['label'], 'HP Color LaserJet (Netzwerk)')
        self.assertIn('Brother', d[1]['label'])
        self.assertEqual(PR.suggest_name(d[0]['label']), 'HP_Color_LaserJet')

    def test_models_and_scanners(self):
        m = PR.parse_models('drv:///a.drv/x.ppd HP LaserJet 1010\neverywhere IPP Everywhere\nfoo Canon MG\n', 'hp laser')
        self.assertEqual(m, [('drv:///a.drv/x.ppd', 'HP LaserJet 1010')])
        s = PR.parse_scanners("device `airscan:e0:Canon' is a eSCL Canon MG scanner\nNo scanners were identified.\n")
        self.assertEqual(len(s), 1)
        self.assertEqual(PR.parse_service('LoadState=loaded\nActiveState=inactive\n'), 'inactive')
        self.assertEqual(PR.parse_service('LoadState=not-found\nActiveState=inactive\n'), 'missing')

    def test_commands_quoting(self):
        self.assertEqual(PR.cmd_add('Buero-1', 'ipp://10.0.0.5/ipp/print', 'everywhere'),
                         ['lpadmin', '-p', 'Buero-1', '-E', '-v', 'ipp://10.0.0.5/ipp/print', '-m', 'everywhere'])
        for name, uri, drv in (('a b', 'ipp://x/y', 'everywhere'), ('ok', 'ipp://x y', 'everywhere'), ('ok', 'file:///etc/passwd', 'everywhere'),
                               ('ok', 'ipp://x/y', '--evil'), ('-x', 'ipp://x/y', 'everywhere'), ('ok', 'ipp://x/y;rm', 'a b')):
            with self.assertRaises(ValueError):
                PR.cmd_add(name, uri, drv)
        self.assertEqual(PR.cmd_default('X'), ['lpoptions', '-d', 'X'])
        self.assertEqual(PR.cmd_remove('X'), ['lpadmin', '-x', 'X'])
        self.assertEqual(PR.cmd_testpage('X')[:3], ['lp', '-d', 'X'])
        self.assertEqual(PR.cmd_enable_cups(), ['pkexec', 'systemctl', 'enable', '--now', 'cups.service'])
        with self.assertRaises(ValueError):
            PR.cmd_remove('x;y')


class NotificationTests(TempEnv):
    def test_load_missing_uses_system_fallback(self):
        sysf = self.home / 'sys.json'
        sysf.write_text('{"timeout": 10}')
        data, err, existed = NO.load_config(self.home / 'nope.json', str(sysf))
        self.assertEqual((data, err, existed), ({'timeout': 10}, None, False))
        self.assertEqual(NO.load_config(self.home / 'nope.json', str(self.home / 'x'))[0], {})

    def test_broken_file_never_overwritten(self):
        f = self.home / 'config.json'
        f.write_text('{ kaputt')
        data, err, _ = NO.load_config(f)
        self.assertTrue(err)
        self.assertEqual(f.read_text(), '{ kaputt')
        f.write_text('[1,2]')
        self.assertTrue(NO.load_config(f)[1])

    def test_save_with_backup_keeps_foreign_keys(self):
        f = self.home / 'swaync' / 'config.json'
        f.parent.mkdir()
        f.write_text(json.dumps({'fremd': {'a': 1}, 'timeout': 5}))
        data, err, _ = NO.load_config(f)
        NO.save_config(f, NO.set_option(data, 'timeout', 8))
        new = json.loads(f.read_text())
        self.assertEqual(new['fremd'], {'a': 1})
        self.assertEqual(new['timeout'], 8)
        self.assertEqual(json.loads((f.parent / 'config.json.vor-aurora').read_text())['timeout'], 5)

    def test_options_validated(self):
        for k, v in (('positionX', 'oben'), ('timeout', -1), ('timeout', 'x'), ('unbekannt', 1), ('timeout', True and 9999)):
            with self.assertRaises(ValueError):
                NO.set_option({}, k, v)
        self.assertEqual(NO.set_option({'a': 1}, 'positionX', 'left'), {'a': 1, 'positionX': 'left'})

    def test_mute_rules_roundtrip(self):
        d = {'notification-visibility': {'fremd': {'state': 'muted', 'app-name': 'x'}}}
        d = NO.add_mute(d, 'Dis.cord (x)', 'ignored')
        self.assertIn('fremd', d['notification-visibility'])
        rules = NO.mute_rules(d)
        self.assertEqual([(r[1], r[2]) for r in rules], [('Dis.cord (x)', 'ignored')])
        rule = rules[0][0]
        self.assertEqual(d['notification-visibility'][rule]['app-name'], r'^Dis\.cord\ \(x\)$')
        d = NO.remove_mute(d, rule)
        self.assertEqual(list(d['notification-visibility']), ['fremd'])
        with self.assertRaises(ValueError):
            NO.remove_mute(d, 'fremd')
        for bad in ('', 'a\nb', 'x' * 81):
            with self.assertRaises(ValueError):
                NO.add_mute({}, bad)
        with self.assertRaises(ValueError):
            NO.add_mute({}, 'a', 'enabled')

    def test_sound(self):
        cmd = NO.sound_command(50, "/tmp/it's a.oga")
        self.assertIn('--volume=32768', cmd)
        self.assertIn("'/tmp/it'\"'\"'s a.oga'", cmd)
        d = NO.set_sound({'x': 1}, True, 50, '/a.oga')
        self.assertEqual(NO.sound_state(d), (True, 50))
        self.assertEqual(d['x'], 1)
        d2 = NO.set_sound(d, False, 50, None)
        self.assertEqual(NO.sound_state(d2)[0], False)
        with self.assertRaises(ValueError):
            NO.set_sound({}, True, 50, None)

    def test_misc(self):
        self.assertEqual(NO.parse_busctl_comm('NameHasOwner=1\nComm=dunst\nPID=5\n'), 'dunst')
        self.assertIsNone(NO.parse_busctl_comm(''))
        self.assertEqual((NO.parse_dnd('true\n'), NO.parse_dnd('false'), NO.parse_dnd('x')), (True, False, None))
        self.assertEqual(NO.cmd_dnd(True), ['swaync-client', '-dn', '-sw'])
        self.assertEqual(NO.cmd_dnd(False), ['swaync-client', '-df', '-sw'])
        self.assertEqual(NO.cmd_preview()[0], 'notify-send')
        self.assertNotIn('--action', ' '.join(NO.cmd_preview()))
        self.assertNotIn('-A', NO.cmd_preview())


class DesignTests(TempEnv):
    def mk_theme(self, base, name, cursors=False, icons=False, hidden=False):
        d = Path(base) / name
        d.mkdir(parents=True)
        txt = '[Icon Theme]\nName=%s\n' % name
        if icons:
            txt += 'Directories=48x48/apps\n'
        if hidden:
            txt += 'Hidden=true\n'
        (d / 'index.theme').write_text(txt)
        if cursors:
            (d / 'cursors').mkdir()
        return d

    def test_find_themes_filters_cursor_from_icons(self):
        base = self.home / 'icons'
        self.mk_theme(base, 'Papirus', icons=True)
        self.mk_theme(base, 'Bibata', cursors=True)
        self.mk_theme(base, 'Breeze', cursors=True, icons=True)
        self.mk_theme(base, 'Versteckt', icons=True, hidden=True)
        self.mk_theme(base, 'default', cursors=True)
        self.mk_theme(base, 'hicolor', icons=True)
        icons, cursors = DE.find_icon_themes([base, self.home / 'gibtsnicht'])
        self.assertEqual(sorted(icons), ['Breeze', 'Papirus'])
        self.assertEqual(sorted(cursors), ['Bibata', 'Breeze'])

    def test_gtk_themes(self):
        b = self.home / 'themes'
        (b / 'Adw' / 'gtk-3.0').mkdir(parents=True)
        (b / 'Leer').mkdir()
        self.assertEqual(list(DE.find_gtk_themes([b])), ['Adw'])

    def test_apply_cursor_writes_files_and_commands(self):
        cfg = self.home / '.config'
        (cfg / 'gtk-3.0').mkdir(parents=True)
        (cfg / 'gtk-3.0/settings.ini').write_text('[Settings]\ngtk-font-name=Inter 10\ngtk-cursor-theme-name=alt\n')
        (cfg / 'kcminputrc').write_text('[Keyboard]\nrepeat=1\n[Mouse]\ncursorTheme=alt\n')
        (self.home / '.icons/default').mkdir(parents=True)
        (self.home / '.icons/default/index.theme').write_text('[Icon Theme]\nName=Default\nInherits=Alt\n')
        calls = []
        warn = DE.apply_cursor('Bibata', 36, {'Bibata': 'Bibata'}, lambda a: calls.append(a) or True)
        self.assertEqual(warn, [])
        g3 = (cfg / 'gtk-3.0/settings.ini').read_text()
        self.assertIn('gtk-font-name=Inter 10', g3)
        self.assertIn('gtk-cursor-theme-name=Bibata', g3)
        self.assertIn('gtk-cursor-theme-size=36', g3)
        self.assertIn('gtk-cursor-theme-size=36', (cfg / 'gtk-4.0/settings.ini').read_text())
        kc = (cfg / 'kcminputrc').read_text()
        self.assertIn('repeat=1', kc)
        self.assertIn('cursorTheme=Bibata', kc)
        self.assertIn('cursorSize=36', kc)
        idx = (self.home / '.icons/default/index.theme').read_text()
        self.assertIn('Inherits=Bibata', idx)
        self.assertIn('Name=Default', idx)
        self.assertEqual(calls[-1], ['hyprctl', 'setcursor', 'Bibata', '36'])
        self.assertEqual(calls[0], ['gsettings', 'set', DE.IFACE, 'cursor-theme', "'Bibata'"])
        self.assertEqual(calls[1][-1], '36')

    def test_apply_cursor_validates_before_writing(self):
        for t, s in (('Unbekannt', 24), ('Bibata', 'x'), ('Bibata', 4), ('../../etc', 24)):
            with self.assertRaises(ValueError):
                DE.apply_cursor(t, s, {'Bibata': 'B'}, lambda a: True)
        self.assertFalse((self.home / '.config').exists())
        self.assertFalse((self.home / '.icons').exists())

    def test_warnings_when_tool_missing(self):
        w = DE.apply_cursor('B', 24, {'B': 'B'}, lambda a: a[0] != 'hyprctl')
        self.assertEqual(w, ['hyprctl'])

    def test_apply_icons_and_gtk(self):
        cfg = self.home / '.config'
        (cfg).mkdir()
        (cfg / 'kdeglobals').write_text('[General]\nColorScheme=Breeze\n[Icons]\nTheme=alt\n')
        calls = []
        DE.apply_icons('Papirus', {'Papirus': 'P'}, lambda a: calls.append(a) or True)
        kd = (cfg / 'kdeglobals').read_text()
        self.assertIn('Theme=Papirus', kd)
        self.assertIn('ColorScheme=Breeze', kd)
        self.assertIn('gtk-icon-theme-name=Papirus', (cfg / 'gtk-3.0/settings.ini').read_text())
        self.assertEqual(calls[0][-2:], ['icon-theme', "'Papirus'"])
        with self.assertRaises(ValueError):
            DE.apply_icons('Evil', {'Papirus': 'P'}, lambda a: True)
        calls.clear()
        DE.apply_gtk('Adw', True, {'Adw': 'Adw'}, lambda a: calls.append(a) or True)
        self.assertIn('gtk-application-prefer-dark-theme=true', (cfg / 'gtk-4.0/settings.ini').read_text())
        self.assertIn('gtk-theme-name=Adw', (cfg / 'gtk-3.0/settings.ini').read_text())
        self.assertIn("'prefer-dark'", calls[0])
        calls.clear()
        DE.apply_gtk(None, False, {}, lambda a: calls.append(a) or True)
        self.assertEqual(len(calls), 1)
        self.assertIn('gtk-application-prefer-dark-theme=false', (cfg / 'gtk-3.0/settings.ini').read_text())

    def test_qt_and_current(self):
        lua = 'hl.env("QT_QPA_PLATFORMTHEME", "kde")\nhl.env("GTK_THEME", "adw-gtk3-dark")\nhl.env("QT_QPA_PLATFORM", "wayland;xcb")\n'
        self.assertEqual(DE.read_qt_env(lua), {'QT_QPA_PLATFORMTHEME': 'kde', 'GTK_THEME': 'adw-gtk3-dark'})
        (self.home / '.config/gtk-3.0').mkdir(parents=True)
        (self.home / '.config/gtk-3.0/settings.ini').write_text('[Settings]\ngtk-cursor-theme-name=win8\ngtk-cursor-theme-size=48\ngtk-application-prefer-dark-theme=true\n')
        c = DE.read_current()
        self.assertEqual((c['cursor'], c['size'], c['dark']), ('win8', 48, True))

    def test_dummy_in_path_logs_calls(self):
        """Attrappen im PATH: real_runner startet nur sie, nie echte Programme."""
        bindir = self.home / 'bin'
        bindir.mkdir()
        log = self.home / 'calls.log'
        for n in ('gsettings', 'hyprctl'):
            p = bindir / n
            p.write_text('#!/bin/sh\necho "%s $@" >> "%s"\n' % (n, log))
            p.chmod(p.stat().st_mode | stat.S_IXUSR)
        with mock.patch.dict(os.environ, {'PATH': str(bindir)}):
            w = DE.apply_cursor('B', 24, {'B': 'B'}, DE.real_runner)
        self.assertEqual(w, [])
        lines = log.read_text().splitlines()
        self.assertEqual(len(lines), 3)
        self.assertEqual(lines[-1], 'hyprctl setcursor B 24')


class HardwareTests(unittest.TestCase):
    LSBLK = json.dumps({'blockdevices': [
        {'name': 'sda', 'path': '/dev/sda', 'type': 'disk', 'rm': False, 'hotplug': False, 'model': 'Samsung', 'fstype': None, 'children': [
            {'name': 'sda1', 'path': '/dev/sda1', 'type': 'part', 'fstype': 'vfat', 'mountpoints': ['/boot/efi'], 'size': '512M'},
            {'name': 'sda2', 'path': '/dev/sda2', 'type': 'part', 'fstype': 'swap', 'mountpoints': ['[SWAP]']}]},
        {'name': 'sdb', 'path': '/dev/sdb', 'type': 'disk', 'rm': True, 'hotplug': True, 'model': 'USB Stick', 'children': [
            {'name': 'sdb1', 'path': '/dev/sdb1', 'type': 'part', 'fstype': 'exfat', 'label': 'STICK', 'size': '16G', 'mountpoints': [None], 'ro': False}]},
        {'name': 'loop0', 'path': '/dev/loop0', 'type': 'loop', 'fstype': 'squashfs', 'mountpoints': ['/snap/x']},
        {'name': 'zram0', 'path': '/dev/zram0', 'type': 'disk', 'fstype': 'swap'}]})

    def test_lsblk(self):
        d = HW.parse_lsblk(self.LSBLK)
        self.assertEqual([x['path'] for x in d], ['/dev/sda1', '/dev/sdb1'])
        usb = d[1]
        self.assertTrue(usb['removable'])
        self.assertEqual((usb['disk'], usb['mounts'], usb['label']), ('/dev/sdb', [], 'STICK'))
        self.assertTrue(HW.is_system_mount('/boot/efi'))
        self.assertFalse(HW.is_system_mount('/run/media/u/STICK'))
        self.assertEqual(HW.parse_lsblk('kein json'), [])
        self.assertEqual(HW.parse_lsblk('{"blockdevices":[{"name":"s","type":"part","fstype":"ext4","mountpoint":"/mnt/x"}]}')[0]['mounts'], ['/mnt/x'])

    def test_device_validation_and_commands(self):
        d = HW.parse_lsblk(self.LSBLK)
        self.assertTrue(HW.valid_device('/dev/sdb1', d))
        for bad in ('/dev/sdz9', '/dev/sdb1; rm', '/etc/passwd', '', None, '/dev/../etc/x'):
            self.assertFalse(HW.valid_device(bad, d))
        self.assertEqual(HW.cmd_mount('/dev/sdb1'), ['udisksctl', 'mount', '--no-user-interaction', '-b', '/dev/sdb1'])
        self.assertEqual(HW.cmd_unmount('/dev/sdb1')[1], 'unmount')
        self.assertEqual(HW.cmd_poweroff('/dev/sdb')[1], 'power-off')

    def test_lsusb_and_firmware(self):
        u = HW.parse_lsusb('Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub\nBus 001 Device 002: ID 1235:8210 Focusrite Scarlett 2i2\nMüll\n')
        self.assertEqual(len(u), 2)
        self.assertTrue(u[0]['hub'])
        self.assertFalse(u[1]['hub'])
        self.assertIn('Keine Firmware-Updates', HW.firmware_summary(2, 'No updatable devices\n', ''))
        self.assertIn('Es gibt Firmware-Updates', HW.firmware_summary(0, 'Devices with updates\n', ''))
        self.assertIn('fehlgeschlagen', HW.firmware_summary(1, '', 'Fehler'))
        self.assertEqual(HW.clean_text('\x1b[1mfett\x1b[0m\n\n'), 'fett')


class ModuleInterface(unittest.TestCase):
    def test_interface(self):
        for m in (PR, NO, DE, HW):
            self.assertIsInstance(m.TITLE, str)
            self.assertTrue(callable(m.build))
            self.assertIsInstance(m.ICONS, list)
        self.assertEqual(len({m.TITLE for m in (PR, NO, DE, HW)}), 4)
        self.assertEqual(DE.GROUP, 'DARSTELLUNG')


if __name__ == '__main__':
    unittest.main()
