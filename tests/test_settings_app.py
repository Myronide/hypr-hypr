"""Tests für Aurora-Einstellungen (preferences.py, monitors.py, Hilfsprogramme) ohne Anzeige und ohne Live-Sitzung.
Alle Dateizugriffe laufen in einem Temp-HOME; hyprctl/qs werden nie gestartet."""
import importlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "aurora_runtime"))


class TempHome(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.env = mock.patch.dict(os.environ, {"HOME": self.tmp.name, "XDG_RUNTIME_DIR": self.tmp.name}, clear=False)
        self.env.start()
        (self.home / ".config/hypr/aurora").mkdir(parents=True)
        import preferences, monitors
        self.P = importlib.reload(preferences)
        self.M = importlib.reload(monitors)
        self.shell = self.home / ".local/state/draconyx/settings.json"
        # niemals echte Programme starten
        self.run = mock.patch("subprocess.run", side_effect=FileNotFoundError("kein Programm im Test")).start()
        mock.patch("subprocess.Popen", side_effect=FileNotFoundError("kein Programm im Test")).start()

    def tearDown(self):
        mock.patch.stopall()
        self.env.stop()
        self.tmp.cleanup()


class PreferencesTests(TempHome):
    def test_atomic_write_replaces_without_leftovers(self):
        f = self.home / "a/b.txt"
        self.P.atomic_write(f, "eins")
        self.P.atomic_write(f, "zwei")
        self.assertEqual(f.read_text(), "zwei")
        self.assertEqual([p.name for p in f.parent.iterdir()], ["b.txt"])

    def test_atomic_write_failure_keeps_old_file(self):
        f = self.home / "x.txt"
        self.P.atomic_write(f, "alt")
        with mock.patch("os.replace", side_effect=OSError("voll")):
            with self.assertRaises(OSError):
                self.P.atomic_write(f, "neu")
        self.assertEqual(f.read_text(), "alt")
        self.assertEqual([p.name for p in self.home.iterdir() if p.name.endswith(".tmp")], [])

    def test_load_preferences_survives_garbage(self):
        pj = self.P.BASE / "preferences.json"
        self.assertEqual(self.P.load_preferences(), self.P.DEFAULTS)           # fehlt
        for text in ("", "{kaputt", "[1,2]", "null", '"text"'):
            pj.write_text(text)
            self.assertEqual(self.P.load_preferences(), self.P.DEFAULTS, text)

    def test_load_preferences_wrong_types_fall_back(self):
        (self.P.BASE / "preferences.json").write_text(json.dumps({"rounding": "viel", "blur": "ja", "tile_gap": 7, "shortcuts": [1], "dock_opacity": 1}))
        p = self.P.load_preferences()
        self.assertEqual(p["rounding"], self.P.DEFAULTS["rounding"])
        self.assertIs(p["blur"], self.P.DEFAULTS["blur"])
        self.assertEqual(p["tile_gap"], 7)
        self.assertEqual(p["dock_opacity"], 1)
        self.assertNotIn("shortcuts", p)

    def test_modifier_invalid_and_missing(self):
        self.assertEqual(self.P.modifier_mode(), "super")
        d = self.home / ".config/draconyx"
        d.mkdir(parents=True)
        (d / "modifier").write_text("quatsch\n")
        self.assertEqual(self.P.modifier_mode(), "super")
        with self.assertRaises(ValueError):
            self.P.set_modifier_mode("quatsch")
        self.P.set_modifier_mode("ctrl-alt")
        self.assertEqual(self.P.modifier_mode(), "ctrl-alt")

    def test_keymap_validation(self):
        d = self.home / ".config/draconyx"
        d.mkdir(parents=True)
        (d / "keymap").write_text("../../etc\n")
        self.assertEqual(self.P.current_keymap(), "de")

    def test_save_with_broken_values_writes_clamped_lua(self):
        p = self.P.DEFAULTS.copy()
        p.update(rounding="abc", border_size=99, blur_size=-4, motion="x", scroll_speed="kaputt", dock_opacity="?", titlebar_height=None)
        self.P.save_preferences(p)
        lua = (self.P.BASE / "preferences.lua").read_text()
        self.assertIn("border_size=6", lua)
        self.assertIn("scroll_factor=1.00", lua)
        self.assertIn("size=1,", lua)
        self.assertTrue((self.P.BASE / "preferences.css").exists())

    def test_save_rejects_bad_shortcut_before_writing(self):
        lua = self.P.BASE / "preferences.lua"
        lua.write_text("-- alt\n")
        p = self.P.DEFAULTS.copy()
        p["shortcuts"] = {"launcher": 'SUPER + A"); os.execute("x")'}
        with self.assertRaises(ValueError):
            self.P.save_preferences(p)
        self.assertEqual(lua.read_text(), "-- alt\n")

    def test_save_shortcut_ctrl_alt(self):
        self.P.set_modifier_mode("ctrl-alt")
        p = self.P.DEFAULTS.copy()
        p["shortcuts"] = {"launcher": "super + space", "unbekannt": "egal ###"}
        self.P.save_preferences(p)
        lua = (self.P.BASE / "preferences.lua").read_text()
        self.assertIn('hl.bind("CTRL + ALT + space"', lua)
        self.assertNotIn("unbekannt", lua)

    def test_save_without_waybar_or_hyprctl_does_not_crash(self):
        self.P.save_preferences(self.P.DEFAULTS.copy())
        self.run.assert_not_called()

    def test_normalize_combo(self):
        n = self.P.normalize_combo
        self.assertEqual(n("super+shift+f"), "SUPER + SHIFT + f")
        self.assertEqual(n("ALT + mouse:272"), "ALT + mouse:272")
        self.assertEqual(n("XF86AudioMute"), "XF86AudioMute")
        self.assertEqual(n("  "), "")
        for bad in ("SUPER +", "+ A", "SUPER + SUPER + A", "FOO + A", "SUPER + SHIFT", "mouse:272", "A; rm -rf", "SUPER + A\nB", 'A"', None, 5, "SUPER + mouse:999"):
            with self.assertRaises(ValueError, msg=repr(bad)):
                n(bad)

    def test_find_conflict(self):
        binds = {"a": ("Start", "SUPER + A"), "b": ("Browser", "SUPER+B"), "c": ("Aus", "")}
        self.assertEqual(self.P.find_conflict(binds, "b", "super + a"), "Start")
        self.assertIsNone(self.P.find_conflict(binds, "a", "SUPER + A"))   # sich selbst nicht
        self.assertIsNone(self.P.find_conflict(binds, "a", ""))
        self.assertEqual(self.P.find_conflict(binds, "a", "SUPER + b"), "Browser")

    def test_binds_conf_roundtrip_and_garbage(self):
        f = self.home / ".config/draconyx/binds.conf"
        self.assertEqual(self.P.read_binds_conf(f), {})
        f.parent.mkdir(parents=True)
        f.write_bytes(b"x=SUPER + A\n#kommentar=1\nkeingleich\n=leer\ny=\n\xff\xfe=bin\n")
        got = self.P.read_binds_conf(f)
        self.assertEqual(got["x"], "SUPER + A")
        self.assertEqual(got["y"], "")
        self.assertNotIn("", got)
        self.P.write_binds_conf({"q": "ALT + Tab"}, f)
        self.assertEqual(self.P.read_binds_conf(f), {"q": "ALT + Tab"})

    def test_reset_keys(self):
        p = {"rounding": 3, "motion": 2.0, "x": 1}
        self.P.reset_keys(p, ("rounding", "motion"))
        self.assertEqual(p["rounding"], self.P.DEFAULTS["rounding"])
        self.assertNotIn("motion", p)
        self.assertEqual(p["x"], 1)


class ShellSettingsTests(TempHome):
    def test_update_keeps_foreign_keys_and_fresh_values(self):
        self.shell.parent.mkdir(parents=True)
        self.shell.write_text(json.dumps({"barStyle": "dock", "a": 1}))
        data, ok = self.P.shell_settings_read(self.shell)
        self.assertTrue(ok)
        # die Shell schreibt zwischendurch selbst
        self.shell.write_text(json.dumps({"barStyle": "dock", "a": 1, "shellNew": True}))
        self.P.shell_settings_update({"a": 2}, self.shell)
        now = json.loads(self.shell.read_text())
        self.assertEqual(now, {"barStyle": "dock", "a": 2, "shellNew": True})

    def test_missing_file_is_created(self):
        self.P.shell_settings_update({"k": 1}, self.shell)
        self.assertEqual(json.loads(self.shell.read_text()), {"k": 1})

    def test_corrupt_file_is_never_overwritten(self):
        self.shell.parent.mkdir(parents=True)
        for text in ("{kaputt", "[1,2,3]"):
            self.shell.write_text(text)
            with self.assertRaises(ValueError):
                self.P.shell_settings_update({"k": 1}, self.shell)
            self.assertEqual(self.shell.read_text(), text)
            self.assertTrue(Path(str(self.shell) + ".defekt").exists())

    def test_no_tmp_leftovers(self):
        self.P.shell_settings_update({"k": 1}, self.shell)
        self.assertEqual([p.name for p in self.shell.parent.iterdir()], ["settings.json"])


class BackgroundTests(TempHome):
    def test_missing_image(self):
        p = self.P.DEFAULTS.copy()
        for wall in ("", "/gibt/es/nicht.png"):
            p["wallpaper"] = wall
            with self.assertRaises(ValueError):
                self.P.apply_background(p)

    def test_bad_monitor_name_rejected(self):
        img = self.home / "b.png"
        img.write_bytes(b"x")
        p = self.P.DEFAULTS.copy()
        p.update(wallpaper=str(img), wallpaper_monitor="DP-1\n}\nexec = x")
        with self.assertRaises(ValueError):
            self.P.apply_background(p)
        self.assertFalse((self.P.BASE / "hyprpaper.conf").exists())

    def test_missing_hyprpaper_reports_error(self):
        img = self.home / "b.png"
        img.write_bytes(b"x")
        p = self.P.DEFAULTS.copy()
        p.update(wallpaper=str(img), wallpaper_monitor="DP-1")
        with self.assertRaises(ValueError):
            self.P.apply_background(p)   # hyprpaper/pkill fehlen (Attrappe wirft FileNotFoundError)
        self.assertIn("monitor = DP-1", (self.P.BASE / "hyprpaper.conf").read_text())


class ExportImportTests(TempHome):
    def test_roundtrip(self):
        self.P.set_modifier_mode("both")
        self.P.write_binds_conf({"launcher": "SUPER + A"})
        self.P.shell_settings_update({"barStyle": "dock", "weWallpapers": {"DP-1": "x"}}, self.shell)
        out = self.home / "export.json"
        self.P.export_settings(out)
        data = json.loads(out.read_text())
        self.assertNotIn("weWallpapers", data["shell"])
        # alles verändern, dann importieren
        self.P.set_modifier_mode("caps")
        self.P.write_binds_conf({})
        self.P.shell_settings_update({"barStyle": "bar", "extra": 1}, self.shell)
        done = self.P.import_settings(out)
        self.assertIn("Shell", done)
        self.assertEqual(self.P.modifier_mode(), "both")
        self.assertEqual(self.P.read_binds_conf(), {"launcher": "SUPER + A"})
        shell = json.loads(self.shell.read_text())
        self.assertEqual(shell["barStyle"], "dock")
        self.assertEqual(shell["extra"], 1)                      # nicht Enthaltenes bleibt
        self.assertEqual(shell["weWallpapers"], {"DP-1": "x"})   # Wallpaper-Zuordnung wird nie überschrieben

    def test_invalid_imports_change_nothing(self):
        self.P.write_binds_conf({"a": "SUPER + A"})
        f = self.home / "bad.json"
        cases = ["nix", "[]", json.dumps({"format": "anders"}),
                 json.dumps({"format": self.P.EXPORT_FORMAT, "binds": {"a": 'X"; os.exit()'}}),
                 json.dumps({"format": self.P.EXPORT_FORMAT, "modifier": "foo"}),
                 json.dumps({"format": self.P.EXPORT_FORMAT, "shell": [1]})]
        for c in cases:
            f.write_text(c)
            with self.assertRaises(ValueError, msg=c):
                self.P.import_settings(f)
        self.assertEqual(self.P.read_binds_conf(), {"a": "SUPER + A"})
        with self.assertRaises(ValueError):
            self.P.import_settings(self.home / "fehlt.json")


class MonitorTests(TempHome):
    def test_live_ignores_garbage(self):
        good = {"name": "DP-1", "description": "A\nB", "width": 1920, "height": 1080, "refreshRate": 60.0, "x": 0, "y": 0, "scale": 1.0,
                "transform": 0, "availableModes": ["1920x1080@60.00Hz", "kaputt"]}
        data = [good, {"name": "DP-2"}, {"name": 'x"}'}, "text", {"name": "", "width": 1}, dict(good, name="HDMI-A-1", scale=0)]
        with mock.patch.object(self.M, "_run", return_value=json.dumps(data)):
            mons = self.M.live()
        self.assertEqual([m["name"] for m in mons], ["DP-1", "HDMI-A-1"])
        self.assertEqual(mons[0]["desc"], "A B")
        self.assertEqual(mons[1]["scale"], 1.0)
        for bad in ("", "{}", "null", "[[]]"):
            with mock.patch.object(self.M, "_run", return_value=bad):
                self.assertEqual(self.M.live(), [])
        with mock.patch.object(self.M, "_run", side_effect=FileNotFoundError):
            self.assertEqual(self.M.live(), [])
        with mock.patch.object(self.M, "_run", side_effect=subprocess.TimeoutExpired("hyprctl", 10)):
            self.assertEqual(self.M.live(), [])

    def mon(self, name="DP-1", x=0, **kw):
        m = {"name": name, "desc": name, "w": 1920, "h": 1080, "hz": 60.0, "x": x, "y": 0, "scale": 1.0, "transform": 0, "disabled": False, "modes": []}
        m.update(kw)
        return m

    def test_write_config_atomic_and_keeps_extras(self):
        conf = self.home / ".config/hypr/monitors_local.lua"
        conf.parent.mkdir(parents=True, exist_ok=True)
        conf.write_text('hl.monitor({\n output = "DP-1",\n mode = "1x1@1",\n vrr = 1,\n})\n')
        backup = self.M.write_config([self.mon(), self.mon("DP-2", 1920)], conf)
        self.assertTrue(Path(backup).exists())
        text = conf.read_text()
        self.assertIn("vrr = 1", text)
        self.assertIn('position = "1920x0"', text)
        self.assertEqual(set(self.M.parse_config(conf)), {"DP-1", "DP-2"})
        self.assertEqual([p.name for p in conf.parent.iterdir() if p.name.endswith(".tmp")], [])

    def test_apply_live_without_hyprctl(self):
        self.assertFalse(self.M.apply_live([self.mon()], self.home / "nix.lua"))
        with mock.patch("subprocess.run", side_effect=subprocess.TimeoutExpired("hyprctl", 10)):
            self.assertFalse(self.M.apply_live([self.mon()], self.home / "nix.lua"))

    def test_apply_live_error_output(self):
        ok = subprocess.CompletedProcess([], 0, "ok", "")
        err = subprocess.CompletedProcess([], 0, "Lua error: x", "")
        with mock.patch("subprocess.run", return_value=ok):
            self.assertTrue(self.M.apply_live([self.mon()], self.home / "nix.lua"))
        with mock.patch("subprocess.run", return_value=err):
            self.assertFalse(self.M.apply_live([self.mon()], self.home / "nix.lua"))

    def test_snap_and_logical_size_edge_cases(self):
        one = [self.mon()]
        self.assertEqual(self.M.snap(one, 0, 500, 500), (0, 0))
        self.assertEqual(self.M.logical_size(self.mon(scale=0)), (1920, 1080))
        self.assertEqual(self.M.logical_size(self.mon(transform=1)), (1080, 1920))
        two = [self.mon(), self.mon("DP-2", 5000)]
        x, y = self.M.snap(two, 1, 5000, 0)
        self.assertEqual((x, y), (1920, 0))
        self.M.normalize([self.mon(disabled=True)])   # nur ausgeschaltete: kein Absturz

    def test_watchdog_command_is_started_detached(self):
        with mock.patch("subprocess.Popen") as popen:
            self.assertTrue(self.M.start_watchdog([self.mon()], self.home / "marker", 1))
        args = popen.call_args[0][0]
        self.assertEqual(args[1], "-c")
        self.assertIn(str(self.home / "marker"), args[2])
        compile(args[2], "watchdog", "exec")   # gültiger Python-Text


class ScriptTests(TempHome):
    def test_mode_status_with_broken_state(self):
        mock.patch.stopall()   # echtes subprocess für das Skript selbst (nur Python im Temp-HOME)
        for text in (None, "{kaputt", "[1]", '{"mode": "tiling"}'):
            state = self.home / "aurora-layout-state.json"
            state.unlink(missing_ok=True)
            if text is not None:
                state.write_text(text)
            r = subprocess.run([sys.executable, "-I", str(ROOT / "mode")], capture_output=True, text=True, timeout=20,
                               env={"HOME": self.tmp.name, "XDG_RUNTIME_DIR": self.tmp.name, "PATH": "/nonexistent"})
            self.assertEqual(r.returncode, 0, r.stderr)
            out = json.loads(r.stdout)
            self.assertEqual(out["class"], "tiling" if text and "tiling" in text else "floating")

    def test_mode_toggle_without_desktop_ui(self):
        mock.patch.stopall()
        r = subprocess.run([sys.executable, "-I", str(ROOT / "mode"), "--toggle"], capture_output=True, text=True, timeout=20,
                           env={"HOME": self.tmp.name, "XDG_RUNTIME_DIR": self.tmp.name, "PATH": "/nonexistent"})
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("Traceback", r.stderr)

    def test_system_menu_without_rofi(self):
        mock.patch.stopall()
        r = subprocess.run([sys.executable, "-I", str(ROOT / "system-menu")], capture_output=True, text=True, timeout=20,
                           env={"HOME": self.tmp.name, "PATH": "/nonexistent"})
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("Traceback", r.stderr)

    def test_desktop_ui_shim_without_qs(self):
        mock.patch.stopall()
        shell = self.home / ".config/quickshell/draconyx"
        shell.mkdir(parents=True)
        (shell / "shell.qml").write_text("")
        for cmd in ("mode", "minimize", "launcher", "controls", "show-desktop", "layout-cycle"):
            r = subprocess.run([sys.executable, "-I", str(ROOT / "desktop-ui"), cmd], capture_output=True, text=True, timeout=30,
                               env={"HOME": self.tmp.name, "XDG_RUNTIME_DIR": self.tmp.name, "PATH": "/nonexistent"})
            self.assertEqual(r.returncode, 0, (cmd, r.stderr))
            self.assertNotIn("Traceback", r.stderr, cmd)


class OtherModuleTests(TempHome):
    def test_dock_visibility_helpers_handle_missing_keys(self):
        try:
            import gi
            gi.require_version("Gtk", "3.0")
            import dock_visibility as dv
        except Exception as e:  # pragma: no cover
            self.skipTest("GTK nicht verfügbar: %s" % e)
        m = {"id": 0, "name": "DP-1", "x": 0, "y": 0, "width": 1920, "height": 1080, "scale": 0, "activeWorkspace": {"id": 1}}
        self.assertEqual(len(dv.dock_rect(m)), 4)
        w = {"mapped": True, "hidden": False, "monitor": 0, "workspace": {"id": 1}}
        self.assertFalse(dv.overlaps_dock(w, m))                       # ohne at/size
        self.assertFalse(dv.overlaps_dock(dict(w, at=[0, 0], size=[10, 10]), dict(m, activeWorkspace={})))
        self.assertTrue(dv.overlaps_dock(dict(w, at=[0, 1000], size=[500, 80]), m))

    def test_notes_write_is_atomic(self):
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("notizen", ROOT / "apps/notizen/notizen.py")
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
        except Exception as e:  # pragma: no cover
            self.skipTest("GTK nicht verfügbar: %s" % e)
        f = self.home / "n.txt"
        mod.write_note(f, "Hallo")
        mod.write_note(f, "Welt")
        self.assertEqual(f.read_text(), "Welt")
        self.assertEqual([p.name for p in self.home.iterdir() if p.name.endswith(".tmp")], [])

    def test_sysmon_palette_rejects_bad_colors(self):
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("sysmon", ROOT / "apps/systemmonitor/sysmon.py")
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
        except Exception as e:  # pragma: no cover
            self.skipTest("Abhängigkeit fehlt: %s" % e)
        d = self.home / ".config/draconyx"
        d.mkdir(parents=True)
        for text in ("[1]", "kaputt", json.dumps({"bg": "rot", "accent": "#112233"})):
            (d / "colors.json").write_text(text)
            pal = mod.palette()
            self.assertTrue(pal["bg"].startswith("#") and len(pal["bg"]) == 7)
        self.assertEqual(pal["accent"], "#112233")
        self.assertEqual(len(mod.rgb("zzzzzz")), 4)


if __name__ == "__main__":
    unittest.main()
