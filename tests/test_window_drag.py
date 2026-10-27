"""Regressionen ohne Fenster, Mausbewegungen oder Verbindung zur Live-Sitzung."""
import json
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class DragTests(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(ROOT / 'bin/dx-window-drag'))
        self.drag = self.module['drag']
        self.g = self.drag.__globals__
        self.commands = []
        self.released = False
        self.clock = 0
        self.points = iter([(100, 90), (120, 90), (140, 90), (160, 90), (180, 90)])
        self.g['call'] = self.call
        self.g['mouse_up_since'] = lambda t: self.released
        self.g['cursor'] = lambda: next(self.points)

    def call(self, command):
        self.commands.append(command)
        if command == 'j/clients':
            # Absichtlich veraltete Position: darf kein Abbruchkriterium sein.
            return json.dumps([dict(address='0x123', floating=True, fullscreen=0,
                                    at=[50, 100], monitor=0)])
        if command == 'j/monitors':
            return json.dumps([dict(id=0, name='DP-1', x=0, y=0, width=2560, height=1440)])
        return 'ok'

    def run_drag(self, report=None):
        def tick():
            self.clock += .001
            return self.clock
        with patch('time.monotonic', tick), patch('time.sleep'):
            self.drag('0x123', lambda: True, report, start=(100, 90), started_ns=1)

    def test_delayed_geometry_does_not_abort_drag(self):
        positions = []
        def report(pos):
            positions.append(pos)
            if len(positions) == 3:
                self.released = True
        self.run_drag(report)
        self.assertEqual(positions, [(90, 100), (110, 100), (130, 100)])
        self.assertFalse(any('activewindow' in c for c in self.commands))
        self.assertIn('endDrag', self.commands[-1])

    def test_click_does_not_restore_or_move(self):
        def cursor():
            self.released = True
            return 101, 90
        self.g['cursor'] = cursor
        self.run_drag()
        self.assertFalse(any(c.startswith('eval') for c in self.commands))

    def test_release_before_process_start(self):
        self.released = True
        self.run_drag()
        self.assertEqual(self.commands, [])

    def test_release_during_setup_never_moves(self):
        original = self.call
        def call(command):
            result = original(command)
            if 'beginDrag' in command:
                self.released = True
            return result
        self.g['call'] = call
        self.run_drag()
        self.assertFalse(any('moveDrag' in c for c in self.commands))
        self.assertIn('endDrag', self.commands[-1])

    def test_release_during_monitor_query_never_moves(self):
        original = self.call
        def call(command):
            result = original(command)
            if command == 'j/monitors':
                self.released = True
            return result
        self.g['call'] = call
        self.run_drag()
        self.assertFalse(any('moveDrag' in c for c in self.commands))

    def test_error_still_releases_animation_ownership(self):
        original = self.call
        def call(command):
            if 'moveDrag' in command:
                raise OSError('Sitzung beendet')
            return original(command)
        self.g['call'] = call
        with self.assertRaises(OSError):
            self.run_drag()
        self.assertIn('endDrag', self.commands[-1])

    def test_monitor_coordinates_use_scale_and_rotation(self):
        monitors = [dict(id=1, x=0, y=0, width=3840, height=2160, scale=2),
                    dict(id=2, x=1920, y=0, width=1920, height=1080, scale=1, transform=1)]
        find = self.module['monitor_at']
        self.assertEqual(find(monitors, 1919, 100)['id'], 1)
        self.assertEqual(find(monitors, 1920, 100)['id'], 2)
        self.assertIsNone(find(monitors, 3000, 100))


if __name__ == '__main__':
    unittest.main()
