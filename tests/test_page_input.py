"""Tests der reinen Logik hinter den Seiten Tastatur / Maus & Touchpad / Eingabehilfen (settings_pages/dx_inputlib.py). Ohne Anzeige, ohne Hyprland."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'settings_pages'))
import dx_inputlib as lib  # noqa: E402

LST = """! model
  pc105           Generic 105-key PC

! layout
  us              English (US)
  de              German
  fr              French
  br/oken         Kaputt

! variant
  nodeadkeys      de: German (no dead keys)
  dvorak          us: English (Dvorak)
  oss             fr: French (alt.)
  mystery         zz without colon

! option
  grp                  Switching to another layout
  grp:alt_shift_toggle Alt+Shift
  caps:escape          Make Caps Lock an additional Esc
  compose:102          The "&lt; &gt;" key
"""


class Home(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        mock.patch.dict(os.environ, {'HOME': self.tmp.name}).start()
        self.path = self.home / '.config/draconyx/input.json'

    def tearDown(self):
        mock.patch.stopall()
        self.tmp.cleanup()


class BaseLst(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.NamedTemporaryFile('w', suffix='.lst', delete=False)
        self.tmp.write(LST)
        self.tmp.close()
        self.r = lib.parse_base_lst(self.tmp.name)

    def tearDown(self):
        os.unlink(self.tmp.name)

    def test_layouts(self):
        self.assertEqual([c for c, _ in self.r['layouts']], ['us', 'de', 'fr'])   # "br/oken" fällt heraus
        self.assertEqual(dict(self.r['layouts'])['de'], 'German')

    def test_variants_grouped_by_layout(self):
        self.assertEqual(self.r['variants']['de'], [('nodeadkeys', 'German (no dead keys)')])
        self.assertNotIn('zz', self.r['variants'])

    def test_options_and_entities(self):
        self.assertIn(('grp:alt_shift_toggle', 'Alt+Shift'), self.r['options']['grp'])
        self.assertEqual(self.r['options']['compose'][0][1], 'The "< >" key')
        self.assertEqual(self.r['groups']['grp'], 'Switching to another layout')

    def test_missing_file(self):
        self.assertEqual(lib.parse_base_lst('/nonexistent/base.lst')['layouts'], [])

    def test_search(self):
        self.assertEqual([c for c, _ in lib.search_layouts(self.r['layouts'], 'ger')], ['de'])
        self.assertEqual([c for c, _ in lib.search_layouts(self.r['layouts'], 'ENGLISH us')], ['us'])
        self.assertEqual(len(lib.search_layouts(self.r['layouts'], '')), 3)
        self.assertEqual(lib.search_layouts(self.r['layouts'], 'zzzz'), [])

    def test_label(self):
        self.assertEqual(lib.layout_label('de', 'nodeadkeys', self.r), 'German – German (no dead keys)')
        self.assertEqual(lib.layout_label('xx', '', self.r), 'xx')

    @unittest.skipUnless(os.path.exists(lib.BASE_LST), 'keine xkb-Regeln installiert')
    def test_real_file_has_german(self):
        r = lib.parse_base_lst()
        self.assertIn('de', dict(r['layouts']))
        self.assertTrue(r['variants'].get('de'))
        self.assertIn('grp:alt_shift_toggle', dict(r['options']['grp']))


class Options(unittest.TestCase):
    def test_roundtrip_keeps_foreign_options(self):
        o = ['lv3:ralt_switch', 'grp:alt_shift_toggle']
        o = lib.options_set(o, 'caps', 'caps:escape')
        self.assertEqual(lib.options_get(o, 'caps'), 'caps:escape')
        self.assertEqual(lib.options_get(o, 'switch'), 'grp:alt_shift_toggle')
        o = lib.options_set(o, 'switch', 'grp:win_space_toggle')
        self.assertEqual(sorted(o), ['caps:escape', 'grp:win_space_toggle', 'lv3:ralt_switch'])
        o = lib.options_set(o, 'caps', '')
        self.assertEqual(lib.options_get(o, 'caps'), '')
        self.assertEqual(lib.options_string(o), 'lv3:ralt_switch,grp:win_space_toggle')

    def test_ctrl_nocaps_counts_as_caps_choice(self):
        o = lib.options_set(['caps:escape'], 'caps', 'ctrl:nocaps')
        self.assertEqual(o, ['ctrl:nocaps'])

    def test_rejects_injection(self):
        for bad in ('caps:esc,ape', 'a b:c', '../x', 'caps', 'x:y;z'):
            with self.assertRaises(ValueError):
                lib.options_set([], 'caps', bad)

    def test_choices_are_valid_options(self):
        for items in (lib.SWITCH_CHOICES, lib.CAPS_CHOICES, lib.COMPOSE_CHOICES):
            for v, t in items:
                self.assertTrue(v == '' or lib.OPTION_RE.fullmatch(v), v)
                self.assertTrue(t)

    @unittest.skipUnless(os.path.exists(lib.BASE_LST), 'keine xkb-Regeln installiert')
    def test_choices_exist_in_base_lst(self):
        known = {o for g in lib.parse_base_lst()['options'].values() for o, _ in g}
        for items in (lib.SWITCH_CHOICES, lib.CAPS_CHOICES, lib.COMPOSE_CHOICES):
            for v, _ in items:
                if v:
                    self.assertIn(v, known)


class Validation(unittest.TestCase):
    def test_limits_clamped(self):
        self.assertEqual(lib.clean_value('repeat_rate', 5000), 100)
        self.assertEqual(lib.clean_value('repeat_delay', 3), 100)
        self.assertEqual(lib.clean_value('sensitivity', -9), -1.0)
        self.assertEqual(lib.clean_value('zoom_factor', 99), 10.0)
        self.assertEqual(lib.clean_value('cursor_size', 24.4), 24)
        self.assertIsInstance(lib.clean_value('repeat_rate', 25.0), int)

    def test_wrong_types(self):
        for k, v in (('repeat_rate', 'x'), ('repeat_rate', True), ('repeat_rate', float('nan')), ('numlock', 1), ('accel_profile', 'turbo'),
                     ('layouts', 'de'), ('layouts', [{'layout': 'd e'}]), ('layouts', [3]), ('kb_options', 'caps:none'), ('kb_options', ['x']),
                     ('unbekannt', 1)):
            with self.assertRaises(ValueError, msg=(k, v)):
                lib.clean_value(k, v)

    def test_layouts_capped_and_normalised(self):
        v = lib.clean_value('layouts', ['de', {'layout': 'us', 'variant': 'dvorak'}, 'fr', 'es', 'it'])
        self.assertEqual(len(v), 4)
        self.assertEqual(v[0], {'layout': 'de', 'variant': ''})


class Storage(Home):
    def test_missing_and_broken_file(self):
        self.assertEqual(lib.load_input(), {})
        self.path.parent.mkdir(parents=True)
        for text in ('', '{', '[1]', '"x"', 'null', '\x00\x01'):
            self.path.write_text(text)
            self.assertEqual(lib.load_input(), {}, text)

    def test_oversized_file_ignored(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text('{"x": "' + 'a' * 70000 + '"}')
        self.assertEqual(lib.load_input(), {})

    def test_invalid_entries_dropped_on_load(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text(json.dumps({'repeat_rate': 'schnell', 'repeat_delay': 300, 'merkfeld': 1}))
        self.assertEqual(lib.load_input(), {'repeat_delay': 300, 'merkfeld': 1})

    def test_update_merges_and_removes(self):
        lib.update_input({'repeat_rate': 40, 'numlock': False})
        lib.update_input({'numlock': None, 'left_handed': True})
        self.assertEqual(json.loads(self.path.read_text()), {'left_handed': True, 'repeat_rate': 40})

    def test_update_rejects_bad_value_without_touching_file(self):
        lib.update_input({'repeat_rate': 40})
        before = self.path.read_text()
        with self.assertRaises(ValueError):
            lib.update_input({'accel_profile': 'turbo'})
        self.assertEqual(self.path.read_text(), before)

    def test_atomic_no_leftovers_and_failure_keeps_old(self):
        lib.update_input({'repeat_rate': 40})
        before = self.path.read_text()
        with mock.patch('os.replace', side_effect=OSError('voll')):
            with self.assertRaises(OSError):
                lib.update_input({'repeat_rate': 50})
        self.assertEqual(self.path.read_text(), before)
        self.assertEqual([p.name for p in self.path.parent.iterdir()], ['input.json'])   # keine Temp-Reste

    def test_unicode_and_stable_output(self):
        lib.save_input({'merk': 'äöü'})
        self.assertIn('äöü', self.path.read_text(encoding='utf-8'))


class Hyprland(Home):
    def test_apply_live_needs_session(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            with mock.patch('subprocess.run') as run:
                self.assertFalse(lib.apply_live())
                run.assert_not_called()

    def test_apply_live_command_and_errors(self):
        with mock.patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE': 'test_sig'}), mock.patch('shutil.which', return_value='/usr/bin/hyprctl'):
            with mock.patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
                self.assertTrue(lib.apply_live())
                self.assertEqual(run.call_args[0][0], ['/usr/bin/hyprctl', 'eval', 'DXInput.apply()'])
                self.assertIn('timeout', run.call_args[1])
            with mock.patch('subprocess.run', side_effect=subprocess.TimeoutExpired('x', 5)):
                self.assertFalse(lib.apply_live())

    def test_parse_devices(self):
        js = {'mice': [{'name': 'm1'}, {'x': 1}], 'keyboards': [{'name': 'k1'}], 'tablets': None}
        self.assertEqual(lib.parse_devices(js), [('Maus', 'm1'), ('Tastatur', 'k1')])
        self.assertEqual(lib.parse_devices([]), [])
        self.assertEqual(lib.parse_devices(None), [])

    def test_read_devices_without_hyprctl(self):
        with mock.patch('shutil.which', return_value=None):
            self.assertIsNone(lib.read_devices())

    def test_gamepads(self):
        with tempfile.TemporaryDirectory() as d:
            for n, name in (('js0', 'Pad\n'), ('js1', None), ('event3', 'Maus'), ('jsx', 'x')):
                (Path(d) / n / 'device').mkdir(parents=True)
                if name:
                    (Path(d) / n / 'device' / 'name').write_text(name)
            self.assertEqual(lib.list_gamepads(d), [('js0', 'Pad'), ('js1', 'Unbekannt')])
        self.assertEqual(lib.list_gamepads('/nonexistent'), [])

    def test_cursor(self):
        self.assertEqual(lib.current_cursor({'XCURSOR_THEME': 'X', 'XCURSOR_SIZE': '32'}), ('X', 32))
        self.assertEqual(lib.current_cursor({'XCURSOR_SIZE': 'abc'}), ('Standard', 24))
        self.assertEqual(lib.current_cursor({'XCURSOR_SIZE': '9999'})[1], 256)


class Contrast(unittest.TestCase):
    def test_preset_has_all_colours_and_contrast(self):
        src = (ROOT / 'bin/dx-colors').read_text()
        ns = {}
        start = src.index('PRESETS = {')
        end = src.index('HEX = ')
        exec(src[start:end], ns)
        p = ns['PRESETS']
        self.assertEqual(set(p['kontrast']), set(p['aurora']))
        def lum(h):
            c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
            c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        def ratio(a, b):
            la, lb = sorted((lum(a), lum(b)), reverse=True)
            return (la + 0.05) / (lb + 0.05)
        k = p['kontrast']
        self.assertGreaterEqual(ratio(k['bg'], k['text']), 15)
        self.assertGreaterEqual(ratio(k['bg'], k['muted']), 7)
        self.assertGreaterEqual(ratio(k['bg'], k['accent']), 7)


class PagesImport(unittest.TestCase):
    def test_modules_define_interface(self):
        import importlib.util
        for f in ('page_keyboard', 'page_pointer', 'page_accessibility'):
            spec = importlib.util.spec_from_file_location('t_' + f, ROOT / 'settings_pages' / (f + '.py'))
            m = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(m)
            self.assertIsInstance(m.TITLE, str)
            self.assertTrue(callable(m.build))
            self.assertTrue(m.ICONS)


if __name__ == '__main__':
    unittest.main()
