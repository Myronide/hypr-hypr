"""Tests für settings_pages/page_network.py: Parser, Validierung, Befehlsbauer und Aktionen mit Attrappen-nmcli.
Kein Display, kein echtes Netz, nmcli/pkexec/gsettings werden nie echt gestartet (PATH zeigt nur auf Attrappen)."""
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
spec = importlib.util.spec_from_file_location('page_network', ROOT / 'settings_pages/page_network.py')
N = importlib.util.module_from_spec(spec)
spec.loader.exec_module(N)

U = '1a4d2859-6c6a-37f9-9ff3-d39857cd3605'


class ParserTests(unittest.TestCase):
    def test_split_escaped(self):
        self.assertEqual(N.split_t(r'a\:b:c\\d:e'), ['a:b', 'c\\d', 'e'])
        self.assertEqual(N.split_t('k:v:w', 1), ['k', 'v:w'])

    def test_devices_and_connections(self):
        d = N.parse_devices('enp10s0:ethernet:connected:Kabelgebundene Verbindung 1\nwlp9s0:wifi:unavailable:\n\n')
        self.assertEqual(d[0]['connection'], 'Kabelgebundene Verbindung 1')
        self.assertEqual(d[1]['state'], 'unavailable')
        c = N.parse_connections('Caf\\:e WLAN:%s:802-11-wireless:wlp9s0\nkurz:x' % U)
        self.assertEqual(c[0]['name'], 'Caf:e WLAN')
        self.assertEqual(c[1]['device'], '')

    def test_wifi_dedupe_and_order(self):
        t = ' :Heim:40:WPA2:6:130 Mbit/s\n*:Heim:80:WPA2:11:270 Mbit/s\n :Heim:90:WPA2:1:54 Mbit/s\n :Offen\\:Cafe:70::1:54 Mbit/s\n :   :50:WPA2:1:1\n :Alt:abc:WPA1 WPA2:3:1'
        w = N.parse_wifi(t)
        self.assertEqual([x['ssid'] for x in w], ['Heim', 'Offen:Cafe', 'Alt'])
        self.assertTrue(w[0]['active'])
        self.assertEqual(w[0]['signal'], 80)
        self.assertEqual(w[1]['security'], '')
        self.assertEqual(w[2]['signal'], 0)

    def test_kv(self):
        kv = N.parse_kv('IP4.ADDRESS[1]:192.168.88.29/24\nIP4.ADDRESS[2]:10.0.0.2/8\nGENERAL.HWADDR:74:56:3C:CD:78:12\nipv4.gateway:--\nipv6.addresses:fd00\\:1/64')
        self.assertEqual(kv['IP4.ADDRESS'], ['192.168.88.29/24', '10.0.0.2/8'])
        self.assertEqual(N.first(kv, 'GENERAL.HWADDR'), '74:56:3C:CD:78:12')
        self.assertEqual(kv['ipv4.gateway'], [])
        self.assertEqual(kv['ipv6.addresses'], ['fd00:1/64'])

    def test_radio_rfkill(self):
        self.assertEqual(N.parse_radio('disabled:enabled\n'), (False, True))
        self.assertIsNone(N.parse_radio(''))
        self.assertEqual(N.parse_rfkill(json.dumps({'': [{'hard': 'blocked', 'soft': 'unblocked'}]})), {'hard': True, 'soft': False})
        self.assertIsNone(N.parse_rfkill('kaputt'))

    def test_pick_connections(self):
        cs = [{'name': n, 'uuid': U, 'type': t, 'device': ''} for n, t in (('a', '802-3-ethernet'), ('b', 'bridge'), ('c', 'wireguard'), ('d', 'vpn'), ('e', 'loopback'))]
        self.assertEqual([c['name'] for c in N.pick_connections(cs, False)], ['a'])
        self.assertEqual([c['name'] for c in N.pick_connections(cs, True)], ['c', 'd'])

    def test_errors_german(self):
        self.assertIn('nicht installiert', N.nm_error_text(127, ''))
        self.assertIn('Zeitüberschreitung', N.nm_error_text(124, ''))
        self.assertIn('läuft nicht', N.nm_error_text(8, 'Error: NetworkManager is not running.'))
        self.assertIn('adapter', N.nm_error_text(10, 'Error: No suitable device found'))


class ValidationTests(unittest.TestCase):
    def test_ip(self):
        self.assertTrue(N.valid_ip('192.168.1.1', 4))
        self.assertTrue(N.valid_ip('fd00::1', 6))
        for bad in ('999.1.1.1', '1.2.3', '0.0.0.0', '224.0.0.1', '1.2.3.4; rm -rf /', '$(id)', '', '1.1.1.1 ', 'fd00::1'):
            if bad == '1.1.1.1 ':
                continue  # Leerraum wird absichtlich getrimmt
            self.assertFalse(N.valid_ip(bad, 4), bad)
        self.assertFalse(N.valid_ip('::1', 4))

    def test_addresses(self):
        self.assertEqual(N.parse_addresses('192.168.1.10/24, 10.0.0.2/8', 4), (['192.168.1.10/24', '10.0.0.2/8'], ''))
        for bad in ('192.168.1.10', '192.168.1.10/33', '192.168.1.10/0', '192.168.1.10/x', 'a/24', '1.2.3.4/24;ls', 'fd00::1/64'):
            self.assertIsNone(N.parse_addresses(bad, 4)[0], bad)
        self.assertEqual(N.parse_addresses('fd00::1/64', 6)[0], ['fd00::1/64'])

    def test_misc(self):
        self.assertEqual(N.valid_mtu('')[0], 0)
        self.assertEqual(N.valid_mtu('1500')[0], 1500)
        for b in ('10', '99999', 'abc', '-5', '1500; x'):
            self.assertIsNone(N.valid_mtu(b)[0])
        self.assertEqual(N.valid_priority('-10')[0], -10)
        self.assertIsNone(N.valid_priority('1000')[0])
        self.assertIsNone(N.valid_priority('x')[0])
        self.assertEqual(N.valid_ssid('Heim'), '')
        self.assertNotEqual(N.valid_ssid(''), '')
        self.assertNotEqual(N.valid_ssid('x' * 33), '')
        self.assertNotEqual(N.valid_ssid('-evil'), '')
        self.assertEqual(N.valid_wpa_password('12345678'), '')
        self.assertNotEqual(N.valid_wpa_password('1234567'), '')
        self.assertNotEqual(N.valid_wpa_password('x' * 64), '')
        self.assertEqual(N.valid_wpa_password('a' * 64), '')
        self.assertEqual(N.valid_hostname('draconyx-pc'), '')
        for b in ('', '-a', 'a-', 'a b', 'a;b', 'a' * 64, 'ä'):
            self.assertNotEqual(N.valid_hostname(b), '', b)
        self.assertTrue(N.valid_port('8080'))
        self.assertFalse(N.valid_port('70000'))
        self.assertFalse(N.valid_host("a';b"))


class BuilderTests(unittest.TestCase):
    def test_uuid_guard(self):
        with self.assertRaises(ValueError):
            N.cmd_connection_up('x; reboot')
        self.assertEqual(N.cmd_connection_up(U), ['connection', 'up', 'uuid', U])

    def test_ip_settings_manual(self):
        a = N.cmd_ip_settings(U, '802-3-ethernet', {'method': 'manual', 'addresses': '192.168.1.10/24', 'gateway': '192.168.1.1', 'dns': '1.1.1.1, 9.9.9.9'},
                              {'method': 'auto', 'addresses': '', 'gateway': '', 'dns': ''}, '1400')
        self.assertEqual(a[:4], ['connection', 'modify', 'uuid', U])
        self.assertIn('192.168.1.10/24', a)
        self.assertEqual(a[a.index('ipv4.dns') + 1], '1.1.1.1 9.9.9.9')
        self.assertEqual(a[a.index('802-3-ethernet.mtu') + 1], '1400')
        self.assertEqual(a[a.index('ipv6.method') + 1], 'auto')

    def test_ip_settings_rejects(self):
        auto = {'method': 'auto', 'addresses': '', 'gateway': '', 'dns': ''}
        for cfg in ({'method': 'manual', 'addresses': '', 'gateway': '', 'dns': ''},
                    {'method': 'manual', 'addresses': '1.2.3.4/24', 'gateway': '1.2.3.4;id', 'dns': ''},
                    {'method': 'auto', 'addresses': '', 'gateway': '', 'dns': '8.8.8.8 $(id)'},
                    {'method': 'evil', 'addresses': '', 'gateway': '', 'dns': ''}):
            with self.assertRaises(ValueError):
                N.cmd_ip_settings(U, '802-3-ethernet', cfg, auto, '')
        with self.assertRaises(ValueError):
            N.cmd_ip_settings(U, '802-3-ethernet', auto, auto, '12')

    def test_wifi_connect_no_password_in_args(self):
        a = N.cmd_wifi_connect('Heim', hidden=True, ifname='wlp9s0', ask=True)
        self.assertEqual(a, ['--ask', 'device', 'wifi', 'connect', 'Heim', 'hidden', 'yes', 'ifname', 'wlp9s0'])
        with self.assertRaises(ValueError):
            N.cmd_wifi_connect('x', ifname='wl; id')

    def test_hotspot_no_psk_value(self):
        a = N.cmd_hotspot_add('Mein Netz', 'wlp9s0')
        self.assertIn('802-11-wireless-security.psk-flags', a)
        self.assertNotIn('802-11-wireless-security.psk', a)

    def test_proxy_cmds(self):
        c = N.gsettings_proxy_cmds({'mode': 'manual', 'http': ('proxy.local', '3128'), 'https': ('', '0'), 'socks': ('', '')})
        self.assertIn(['gsettings', 'set', 'org.gnome.system.proxy.http', 'host', 'proxy.local'], c)
        with self.assertRaises(ValueError):
            N.gsettings_proxy_cmds({'mode': 'manual', 'http': ('a;b', '1')})
        with self.assertRaises(ValueError):
            N.gsettings_proxy_cmds({'mode': 'manual', 'http': ('a', '99999')})
        with self.assertRaises(ValueError):
            N.gsettings_proxy_cmds({'mode': 'auto', 'autoconfig': "javascript:alert('x')"})
        self.assertEqual(N.parse_gsettings_str("'manual'"), 'manual')

    def test_import_kind(self):
        self.assertEqual(N.vpn_kind_for('/a/b.OVPN'), 'openvpn')
        self.assertEqual(N.vpn_kind_for('/a/wg0.conf'), 'wireguard')
        self.assertEqual(N.cmd_import('wireguard', '/a/wg0.conf')[:4], ['connection', 'import', 'type', 'wireguard'])


class FakeBin(unittest.TestCase):
    """Attrappen im PATH: protokollieren argv + stdin in LOG und liefern feste Ausgaben."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        self.log = d / 'log.jsonl'
        bindir = d / 'bin'
        bindir.mkdir()
        script = '#!' + sys.executable + '''
import sys, json, os
log = os.environ["FAKE_LOG"]
data = "" if sys.stdin.isatty() else sys.stdin.read()
open(log, "a").write(json.dumps({"prog": os.path.basename(sys.argv[0]), "argv": sys.argv[1:], "stdin": data}) + "\\n")
a = sys.argv[1:]
if "add" in a and "con-name" in a:
    print("Connection 'Aurora-Hotspot' (%s) successfully added." % os.environ["FAKE_UUID"])
if a[:3] == ["-t", "-f", "NAME,UUID"]:
    print("Aurora-Hotspot:%s" % os.environ["FAKE_UUID"])
sys.exit(int(os.environ.get("FAKE_RC", "0")))
'''
        for n in ('nmcli', 'pkexec', 'gsettings', 'hostnamectl'):
            p = bindir / n
            p.write_text(script)
            p.chmod(p.stat().st_mode | stat.S_IEXEC)
        self.env = mock.patch.dict(os.environ, {'PATH': str(bindir), 'FAKE_LOG': str(self.log), 'FAKE_UUID': U, 'HOME': self.tmp.name})
        self.env.start()
        os.environ.pop('FAKE_RC', None)

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def calls(self):
        return [json.loads(l) for l in self.log.read_text().splitlines()] if self.log.exists() else []


class ActionTests(FakeBin):
    def test_wifi_password_only_on_stdin(self):
        ok, _ = N.do_wifi_connect('Heim', 'geheim1234', ifname='wlp9s0')
        self.assertTrue(ok)
        c = self.calls()[-1]
        self.assertNotIn('geheim1234', ' '.join(c['argv']))
        self.assertEqual(c['stdin'], 'geheim1234\n')
        self.assertEqual(c['argv'][:5], ['--ask', 'device', 'wifi', 'connect', 'Heim'])

    def test_wifi_short_password_rejected_without_call(self):
        ok, t = N.do_wifi_connect('Heim', 'kurz')
        self.assertFalse(ok)
        self.assertIn('8', t)
        self.assertEqual(self.calls(), [])

    def test_open_network_no_ask(self):
        N.do_wifi_connect('Cafe', '', secured=False)
        self.assertEqual(self.calls()[-1]['argv'], ['device', 'wifi', 'connect', 'Cafe'])

    def test_failure_text(self):
        os.environ['FAKE_RC'] = '4'
        ok, t = N.do_wifi_connect('Heim', 'geheim1234')
        self.assertFalse(ok)
        self.assertTrue(t)

    def test_hotspot_flow(self):
        ok, _ = N.do_hotspot_start('Mein-Hotspot', 'passwort123', 'wlp9s0')
        self.assertTrue(ok)
        cs = self.calls()
        self.assertTrue(all('passwort123' not in ' '.join(c['argv']) for c in cs))
        up = cs[-1]
        self.assertEqual(up['argv'], ['--ask', 'connection', 'up', 'uuid', U])
        self.assertEqual(up['stdin'], 'passwort123\n')
        # altes Profil wurde zuerst gelöscht
        self.assertIn(['connection', 'delete', 'uuid', U], [c['argv'] for c in cs])

    def test_hotspot_validation_no_call(self):
        self.assertFalse(N.do_hotspot_start('x', '123', 'wlp9s0')[0])
        self.assertEqual(self.calls(), [])

    def test_hotspot_stop(self):
        self.assertTrue(N.do_hotspot_stop(U)[0])
        self.assertEqual([c['argv'][:2] for c in self.calls()], [['connection', 'down'], ['connection', 'delete']])

    def test_hostname_uses_pkexec_list(self):
        self.assertTrue(N.do_set_hostname('neuer-name')[0])
        c = self.calls()[-1]
        self.assertEqual((c['prog'], c['argv']), ('pkexec', ['hostnamectl', 'set-hostname', 'neuer-name']))
        n = len(self.calls())
        self.assertFalse(N.do_set_hostname('a;reboot')[0])
        self.assertEqual(len(self.calls()), n)

    def test_missing_nmcli(self):
        with mock.patch.dict(os.environ, {'PATH': '/nonexistent'}):
            st = N.read_status()
            self.assertIn('nicht installiert', st['error'])
            self.assertEqual(N.read_proxy(), None)
            self.assertIn('Kein bekannter', N.firewall_text(N.read_firewall()))


class ImportTests(unittest.TestCase):
    def test_module_interface(self):
        self.assertTrue(callable(N.build))
        self.assertIsInstance(N.TITLE, str)


if __name__ == '__main__':
    unittest.main()
