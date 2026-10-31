"""Tests der Systemseiten (Datum & Zeit, Region, Benutzer, Standard-Apps, Über): nur Logik, ohne Display, ohne echte Systemänderung."""
import json, os, sys, tempfile, unittest, stat
from pathlib import Path
from unittest import mock

PAGES = Path(__file__).resolve().parent.parent / 'settings_pages'
sys.path.insert(0, str(PAGES))
import dx_sysutil as U
import page_datetime as DT
import page_region as RG
import page_users as US
import page_defaults as DF
import page_about as AB


class Util(unittest.TestCase):
    def test_shell_update_keeps_other_keys_and_is_atomic(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / 'd' / 'settings.json'
            p.parent.mkdir()
            p.write_text(json.dumps({'a': 1, 'showSeconds': False}))
            U.shell_update({'showSeconds': True}, p)
            self.assertEqual(json.loads(p.read_text()), {'a': 1, 'showSeconds': True})
            self.assertEqual(U.shell_get('showSeconds', path=p), True)
            self.assertEqual(sorted(x.name for x in p.parent.iterdir() if x.suffix == '.tmp'), [])

    def test_shell_update_refuses_corrupt_file(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / 'settings.json'
            p.write_text('{kaputt')
            with self.assertRaises(ValueError):
                U.shell_update({'x': 1}, p)
            self.assertEqual(p.read_text(), '{kaputt')
            self.assertTrue((Path(t) / 'settings.json.defekt').exists())

    def test_shell_update_creates_missing(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / 'neu' / 'settings.json'
            U.shell_update({'showDate': False}, p)
            self.assertEqual(json.loads(p.read_text()), {'showDate': False})

    def test_run_missing_program_and_timeout(self):
        self.assertEqual(U.run(['gibt-es-garantiert-nicht-xyz'])[0], 127)
        self.assertEqual(U.run(['sleep', '5'], timeout=0.2)[0], 124)

    def test_fmt_bytes(self):
        self.assertEqual(U.fmt_bytes(512), '512 B')
        self.assertEqual(U.fmt_bytes(1536), '1,5 KiB')
        self.assertEqual(U.fmt_bytes(None), '?')

    def test_quote(self):
        self.assertEqual(U.quote_cmd(['a b', "x'y"]), "'a b' 'x'\"'\"'y'")


class DateTime(unittest.TestCase):
    SHOW = 'Timezone=Europe/Berlin\nLocalRTC=no\nCanNTP=yes\nNTP=yes\nNTPSynchronized=yes\nTimeUSec=Wed 2026-10-28 13:49:22 CET\nRTCTimeUSec=Wed 2026-10-28 12:49:22 UTC\n'

    def test_parse_show(self):
        r = DT.parse_timedatectl_show(self.SHOW)
        self.assertEqual(r['timezone'], 'Europe/Berlin')
        self.assertTrue(r['ntp'] and r['synced'] and r['can_ntp'])
        self.assertFalse(r['local_rtc'])
        self.assertIn('UTC', r['rtc_time'])

    def test_parse_show_garbage(self):
        r = DT.parse_timedatectl_show('Müll ohne Gleichheit\n\n')
        self.assertIsNone(r['timezone'])
        self.assertIsNone(r['ntp'])
        self.assertEqual(DT.parse_timedatectl_show(None)['time'], None)

    def test_timezones(self):
        z = DT.parse_timezones('Europe/Berlin\nAmerica/Argentina/Buenos_Aires\nUTC\n bad zone \n../etc/passwd\n\n')
        self.assertEqual(z, ['America/Argentina/Buenos_Aires', 'Europe/Berlin', 'UTC'])

    def test_tz_validation_and_command(self):
        z = ['Europe/Berlin', 'UTC']
        self.assertEqual(DT.build_set_timezone('Europe/Berlin', z), ['pkexec', 'timedatectl', 'set-timezone', 'Europe/Berlin'])
        for bad in ('Europe/Berlinn', '', None, 'UTC; rm -rf /', '-h'):
            with self.assertRaises(ValueError):
                DT.build_set_timezone(bad, z)

    def test_date_time_strict(self):
        self.assertEqual(DT.validate_date('2026-02-28'), '2026-02-28')
        self.assertEqual(DT.validate_date('05.03.2026'), '2026-03-05')
        for bad in ('2026-02-30', '2026-13-01', '26-1-1', '', 'heute', '2026-02-28; reboot', '1969-12-31'):
            self.assertIsNone(DT.validate_date(bad), bad)
        self.assertEqual(DT.validate_time('9:05'), '09:05:00')
        self.assertEqual(DT.validate_time('23:59:59'), '23:59:59')
        for bad in ('24:00', '12:60', '12:00:60', '1200', 'ab:cd', ''):
            self.assertIsNone(DT.validate_time(bad), bad)

    def test_set_time_command(self):
        self.assertEqual(DT.build_set_time('2026-10-28', '8:30'), ['pkexec', 'timedatectl', 'set-time', '2026-10-28 08:30:00'])
        with self.assertRaises(ValueError):
            DT.build_set_time('2026-10-28', '25:00')

    def test_ntp_command(self):
        self.assertEqual(DT.build_set_ntp(True)[-2:], ['set-ntp', 'true'])
        self.assertEqual(DT.build_set_ntp(False)[-2:], ['set-ntp', 'false'])

    def test_shell_clock_changes(self):
        self.assertEqual(DT.shell_clock_changes(show_seconds=1), {'showSeconds': True})
        self.assertEqual(DT.shell_clock_changes(show_date=0), {'showDate': False})
        self.assertEqual(DT.shell_clock_changes(), {})


class Region(unittest.TestCase):
    STATUS = '   System Locale: LANG=de_DE.UTF-8\n                  LC_TIME=en_GB.UTF-8\n       VC Keymap: de\n      X11 Layout: de\n'

    def test_parse_status(self):
        r = RG.parse_localectl_status(self.STATUS)
        self.assertEqual(r['locale'], {'LANG': 'de_DE.UTF-8', 'LC_TIME': 'en_GB.UTF-8'})
        self.assertEqual(r['keymap'], 'de')

    def test_parse_status_empty_and_unset(self):
        self.assertEqual(RG.parse_localectl_status('System Locale: n/a\n')['locale'], {})
        self.assertEqual(RG.parse_localectl_status('')['locale'], {})

    def test_locale_list(self):
        self.assertEqual(RG.parse_locale_list('C.UTF-8\nde_DE.UTF-8\nen_US.UTF-8\nunsinn zeile\n;rm\n'), ['C.UTF-8', 'de_DE.UTF-8', 'en_US.UTF-8'])

    def test_locale_gen(self):
        s = RG.parse_locale_gen('# Kommentar text\n#de_DE.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n#  fr_FR ISO-8859-1\n')
        self.assertEqual(s, {'de_DE.UTF-8', 'en_US.UTF-8', 'fr_FR'})

    def test_command(self):
        av = ['de_DE.UTF-8', 'en_US.UTF-8']
        self.assertEqual(RG.build_set_locale({'LANG': 'de_DE.UTF-8', 'LC_TIME': 'en_US.UTF-8', 'LC_PAPER': 'de_DE.UTF-8', 'LC_NUMERIC': ''}, av),
                         ['pkexec', 'localectl', 'set-locale', 'LANG=de_DE.UTF-8', 'LC_TIME=en_US.UTF-8'])

    def test_validation(self):
        av = ['de_DE.UTF-8']
        for bad in ({'LANG': 'xx_XX.UTF-8'}, {'LANG': ''}, {}, {'LANG': 'de_DE.UTF-8', 'PATH': 'de_DE.UTF-8'}, {'LANG': 'de_DE.UTF-8 LC_ALL=C'}):
            with self.assertRaises(ValueError):
                RG.build_set_locale(bad, av)

    def test_paper_and_label(self):
        self.assertEqual(RG.paper_name('297', '210'), 'A4')
        self.assertEqual(RG.paper_name('279', '216'), 'Letter')
        self.assertEqual(RG.paper_name('x', 1), '?')
        self.assertTrue(RG.locale_label('de_DE.UTF-8').startswith('Deutsch (Deutschland)'))
        self.assertEqual(RG.locale_label('zz_ZZ'), 'zz_ZZ')

    def test_preview_handles_missing_locale(self):
        r = RG.preview({'LANG': 'C.UTF-8'})
        self.assertIsInstance(r, dict)
        self.assertEqual(RG.preview({'LANG': 'x; rm -rf /'}), {})


class Users(unittest.TestCase):
    def test_validate(self):
        self.assertTrue(US.validate_login('syntaxjason'))
        for b in ('Root', '1abc', '', 'a b', '-x', 'a;b', 'x' * 40):
            self.assertFalse(US.validate_login(b), b)
        self.assertEqual(US.validate_display_name('  Jason S.  '), 'Jason S.')
        for b in ('', 'a:b', 'a,b', 'a\nb', 'a=b', 'x' * 101, None):
            self.assertIsNone(US.validate_display_name(b), repr(b))

    def test_command_quoting(self):
        self.assertEqual(US.build_set_fullname('jason', 'Jason $(rm) "x" -y'), ['pkexec', 'usermod', '-c', 'Jason $(rm) "x" -y', '--', 'jason'])
        with self.assertRaises(ValueError):
            US.build_set_fullname('ja son', 'x')
        with self.assertRaises(ValueError):
            US.build_set_fullname('jason', 'a:b')

    def test_crop(self):
        self.assertEqual(US.square_crop(400, 200), (100, 0, 200))
        self.assertEqual(US.square_crop(100, 300), (0, 100, 100))

    def test_sessions(self):
        s = US.parse_sessions('  2 1000 syntaxjason seat0 tty1\n c1 1000 syntaxjason\nmüll\n\n')
        self.assertEqual([x['id'] for x in s], ['2', 'c1'])
        self.assertEqual(s[0]['seat'], 'seat0')
        self.assertEqual(US.parse_session_show('Type=wayland\nActive=yes\nRemote=no\n')['type'], 'wayland')

    def test_account_info(self):
        i = US.account_info()
        self.assertTrue(i['login'] and i['home'])

    def test_password_command_uses_dx_terminal(self):
        with mock.patch.object(US.U, 'find_bin', return_value='/x/hyhy-terminal'):
            self.assertEqual(US.password_command(), ['/x/hyhy-terminal', '--', 'passwd'])
        with mock.patch.object(US.U, 'find_bin', return_value=None):
            self.assertIsNone(US.password_command())

    def test_save_face(self):
        try:
            import gi
            gi.require_version('GdkPixbuf', '2.0')
            from gi.repository import GdkPixbuf
        except Exception:
            self.skipTest('GdkPixbuf fehlt')
        with tempfile.TemporaryDirectory() as t:
            src = Path(t) / 'src.png'
            GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 600, 300).savev(str(src), 'png', [], [])
            dest = Path(t) / 'home' / '.face'
            dest.parent.mkdir()
            US.save_face(src, dest)
            pb = GdkPixbuf.Pixbuf.new_from_file(str(dest))
            self.assertEqual((pb.get_width(), pb.get_height()), (256, 256))
            self.assertEqual([p.name for p in dest.parent.iterdir()], ['.face'])
            bad = Path(t) / 'bad.png'
            bad.write_text('kein bild')
            with self.assertRaises(Exception):
                US.save_face(bad, dest)
            self.assertEqual(GdkPixbuf.Pixbuf.new_from_file(str(dest)).get_width(), 256)


DESKTOP = """[Desktop Entry]
Type=Application
Name=Firefox
Name[de]=Firefox Browser
Icon=firefox
Exec=firefox %u
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;

[Desktop Action new]
Name=Neues Fenster
"""


class Defaults(unittest.TestCase):
    def test_parse_desktop(self):
        e = DF.parse_desktop(DESKTOP)
        self.assertEqual(e['name'], 'Firefox Browser')
        self.assertIn('x-scheme-handler/http', e['mimes'])
        self.assertEqual(DF.parse_desktop(DESKTOP, 'fr')['name'], 'Firefox')

    def test_parse_desktop_broken(self):
        self.assertIsNone(DF.parse_desktop(''))
        self.assertIsNone(DF.parse_desktop('kein ini'))
        self.assertIsNone(DF.parse_desktop('[Desktop Entry]\nType=Link\nName=x\n'))
        self.assertIsNone(DF.parse_desktop('[Desktop Entry]\nExec=x\n'))          # ohne Name
        e = DF.parse_desktop('[Desktop Entry]\nName=A\nName=B\nHidden=true\nNoDisplay=True\nMimeType=;;a/b;\n')   # doppelter Schlüssel
        self.assertTrue(e['hidden'] and e['nodisplay'])
        self.assertEqual(e['mimes'], ['a/b'])
        e = DF.parse_desktop('Zeile ohne Abschnitt\n[Desktop Entry]\nName=Ok\n')
        self.assertEqual(e['name'], 'Ok')

    def make_dirs(self, t):
        u, s = Path(t) / 'u', Path(t) / 's'
        (u / 'sub').mkdir(parents=True)
        s.mkdir()
        (s / 'firefox.desktop').write_text(DESKTOP)
        (s / 'hidden.desktop').write_text('[Desktop Entry]\nName=H\nNoDisplay=true\nMimeType=text/html;\n')
        (s / 'kaputt.desktop').write_bytes(b'\xff\xfe\x00[[')
        (u / 'firefox.desktop').write_text('[Desktop Entry]\nName=Mein Firefox\nMimeType=text/html;\nExec=ff\n')
        (u / 'sub' / 'x.desktop').write_text('[Desktop Entry]\nName=Sub\nExec=x\n')
        return [u, s, Path(t) / 'fehlt']

    def test_scan_prefers_user_and_skips_hidden(self):
        with tempfile.TemporaryDirectory() as t:
            apps = DF.scan_apps(self.make_dirs(t))
            self.assertEqual(apps['firefox.desktop']['name'], 'Mein Firefox')
            self.assertNotIn('hidden.desktop', apps)
            self.assertIn('sub-x.desktop', apps)
            self.assertEqual(DF.candidates(apps, 'text/html'), [('firefox.desktop', 'Mein Firefox')])

    def test_commands(self):
        apps = {'firefox.desktop': {'name': 'F'}}
        self.assertEqual(DF.build_set_default('browser', 'firefox.desktop', apps),
                         [['xdg-settings', 'set', 'default-web-browser', 'firefox.desktop'],
                          ['xdg-mime', 'default', 'firefox.desktop', 'x-scheme-handler/http', 'x-scheme-handler/https', 'text/html', 'application/xhtml+xml']])
        self.assertEqual(DF.build_set_default('pdf', 'firefox.desktop', apps), [['xdg-mime', 'default', 'firefox.desktop', 'application/pdf']])
        for key, did in (('pdf', 'evil.desktop'), ('nix', 'firefox.desktop'), ('terminal', 'firefox.desktop'), ('pdf', '../x.desktop')):
            with self.assertRaises(ValueError):
                DF.build_set_default(key, did, apps)

    def test_query_parse(self):
        self.assertEqual(DF.parse_query_default('firefox.desktop\n'), 'firefox.desktop')
        self.assertEqual(DF.parse_query_default(''), '')
        self.assertEqual(DF.parse_query_default('Fehler: x\n'), '')

    def test_terminal_file(self):
        with tempfile.TemporaryDirectory() as t, mock.patch.dict(os.environ, {'XDG_CONFIG_HOME': t}):
            self.assertEqual(DF.current_terminal(), '')
            which = lambda n: '/usr/bin/' + n if n in ('kitty', 'foot') else None
            DF.set_terminal('kitty', which)
            self.assertEqual((Path(t) / 'draconyx/terminal').read_text(), 'kitty\n')
            self.assertEqual(DF.current_terminal(), 'kitty')
            for bad in ('xterm', 'rm -rf /', '', None, '../kitty'):
                with self.assertRaises(ValueError):
                    DF.set_terminal(bad, which)
            self.assertEqual(DF.installed_terminals(which), ['kitty', 'foot'])

    def test_app_dirs_order(self):
        d = DF.app_dirs({'HOME': '/h', 'XDG_DATA_HOME': '/h/d', 'XDG_DATA_DIRS': '/a:/b'})
        self.assertEqual([str(x) for x in d[:3]], ['/h/d/applications', '/a/applications', '/b/applications'])
        self.assertIn('/var/lib/flatpak/exports/share/applications', [str(x) for x in d])


class About(unittest.TestCase):
    def test_parsers(self):
        self.assertEqual(AB.parse_os_release('PRETTY_NAME="Garuda Linux"\nID=garuda\n')['PRETTY_NAME'], 'Garuda Linux')
        cpu, n = AB.parse_cpu('processor\t: 0\nmodel name\t: AMD  Ryzen 7\nprocessor\t: 1\nmodel name\t: AMD  Ryzen 7\n')
        self.assertEqual((cpu, n), ('AMD Ryzen 7', 2))
        self.assertEqual(AB.parse_cpu('')[0], 'unbekannt')
        self.assertEqual(AB.parse_meminfo('MemTotal:  1024 kB\nMemAvailable:  512 kB\n'), (1048576, 524288))
        self.assertEqual(AB.parse_meminfo('Müll'), (0, 0))
        self.assertEqual(AB.fmt_uptime(90061), '1 Tag 1 Std. 1 Min.')
        self.assertEqual(AB.fmt_uptime('x'), '?')
        self.assertEqual(AB.parse_gpus('01:00.0 "VGA compatible controller" "NVIDIA Corporation" "AD104 [RTX 4070]" -ra1\n00:1f.3 "Audio device" "Intel" "x"\nkaputt "\n'),
                         ['NVIDIA Corporation AD104 [RTX 4070]'])

    def test_mounts_and_usage(self):
        m = AB.parse_mounts('/dev/nvme0n1p2 / btrfs rw 0 0\n/dev/nvme0n1p2 /home btrfs rw 0 0\ntmpfs /tmp tmpfs rw 0 0\n/dev/sda1 /run/media/u/Daten\\040X ntfs3 rw 0 0\nproc /proc proc rw 0 0\n')
        self.assertEqual([x[1] for x in m], ['/', '/run/media/u/Daten X'])
        sv = lambda p: mock.Mock(f_blocks=100, f_frsize=4096, f_bfree=40, f_bavail=30)
        u = AB.disk_usage(m, sv)
        self.assertEqual((u[0]['total'], u[0]['used'], u[0]['free']), (409600, 245760, 122880))
        self.assertEqual(AB.disk_usage(m, mock.Mock(side_effect=OSError)), [])

    def test_monitors(self):
        r = AB.parse_monitors(json.dumps([{'name': 'DP-1', 'width': 2560, 'height': 1440, 'refreshRate': 143.97, 'scale': 1.0, 'description': 'X'}]))
        self.assertEqual(r, ['DP-1: 2560×1440 @ 144 Hz, Skalierung 1.0 – X'])
        self.assertEqual(AB.parse_monitors('kein json'), [])
        self.assertEqual(AB.parse_monitors('{}'), [])

    def test_checkupdates(self):
        self.assertEqual(AB.parse_checkupdates(0, 'a 1 -> 2\nb 1 -> 3\n')[0], 2)
        self.assertEqual(AB.parse_checkupdates(2, '')[0], 0)
        self.assertIsNone(AB.parse_checkupdates(1, '')[0])

    def test_dir_size(self):
        with tempfile.TemporaryDirectory() as t:
            (Path(t) / 'a').mkdir()
            (Path(t) / 'a/f').write_bytes(b'x' * 100)
            (Path(t) / 'g').write_bytes(b'y' * 50)
            os.symlink('/etc', Path(t) / 'link')
            self.assertEqual(AB.dir_size(t), 150)
            self.assertEqual(AB.dir_size(Path(t) / 'fehlt'), 0)

    def test_commands(self):
        self.assertEqual(AB.build_empty_trash(), ['gio', 'trash', '--empty'])
        with mock.patch.object(AB.U, 'find_bin', return_value='/b/hyhy-terminal'):
            c = AB.terminal_update_cmd()
            self.assertEqual(c[:3], ['/b/hyhy-terminal', '--', 'sh'])
        with mock.patch.object(AB.U, 'find_bin', return_value=None):
            self.assertIsNone(AB.terminal_update_cmd())

    def test_collect_info_without_tools(self):
        with mock.patch.object(AB.U, 'run', return_value=(127, '', 'fehlt')):
            i = AB.collect_info()
        self.assertEqual(i['gpus'], [])
        self.assertEqual(i['monitors'], [])
        self.assertIn('Kernel:', AB.info_text(i))


class FakeTools(unittest.TestCase):
    """Schreibpfade nur gegen Attrappen im PATH: Aufrufe werden protokolliert, nichts am echten System geändert."""

    def test_pkexec_stub_receives_exact_args(self):
        with tempfile.TemporaryDirectory() as t:
            log = Path(t) / 'log'
            stub = Path(t) / 'pkexec'
            stub.write_text('#!/bin/sh\nfor a in "$@"; do printf "%s\\n" "$a"; done >> ' + str(log) + '\n')
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
            with mock.patch.dict(os.environ, {'PATH': t + os.pathsep + os.environ['PATH']}):
                rc, _, _ = U.run(US.build_set_fullname('jason', 'Ja $(x) son'))
            self.assertEqual(rc, 0)
            self.assertEqual(log.read_text().splitlines(), ['usermod', '-c', 'Ja $(x) son', '--', 'jason'])


if __name__ == '__main__':
    unittest.main()
