"""Statische Regressionen fuer Alt+Tab aus Vollbild-Spielen (ohne Sitzung, ohne Fenster)."""
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GameFocusTests(unittest.TestCase):
    def test_raise_orders_zorder_before_focus(self):
        # alter_zorder gibt auf einem Desktop mit Vollbild-Fenster den Fokus an dieses zurueck: erst nach oben, dann fokussieren.
        src = (ROOT / 'quickshell/Global.qml').read_text()
        body = src[src.index('function raise(a)'):src.index('function minimizeH')]
        self.assertLess(body.index('alter_zorder'), body.index('hl.dsp.focus'))
        timer = body[body.index('Timer { id: raiseTimer'):]
        self.assertLess(timer.index('alter_zorder'), timer.index('hl.dsp.focus'))

    def test_switcher_binds_ignore_shortcut_inhibitors(self):
        src = (ROOT / 'hypr/hyprland.lua').read_text()
        for bid in ('switcher_next', 'switcher_prev', 'switcher_commit', 'switcher_commit_shift',
                    'switcher_cancel', 'free_mouse', 'window_kill'):
            line = next(l for l in src.splitlines() if l.startswith('B("%s"' % bid))
            self.assertIn('dont_inhibit = true', line, bid)

    def test_game_rules_present(self):
        src = (ROOT / 'hypr/hyprland.lua').read_text()
        self.assertRegex(src, r'games-steam.*\n.*no_shortcuts_inhibit = true')

    def test_free_mouse_works_with_one_monitor(self):
        src = (ROOT / 'hypr/hyprland.lua').read_text()
        body = src[src.index('local function freeMouse'):src.index('B("free_mouse"')]
        self.assertIn('last = true', body)


if __name__ == '__main__':
    unittest.main()


class GameDesktopTests(unittest.TestCase):
    def test_games_module_wired(self):
        self.assertIn('require("dx_games")', (ROOT / 'hypr/hyprland.lua').read_text())
        self.assertIn('dx_games.lua', (ROOT / 'install.sh').read_text())
        src = (ROOT / 'hypr/dx_games.lua').read_text()
        for needle in ('window.open', 'window.active', 'follow = false', 'cursor.move', 'moved[addr]'):
            self.assertIn(needle, src)
