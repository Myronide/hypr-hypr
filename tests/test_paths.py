"""bin/hyhy-paths: Umbenennung draconyx -> hypr-hypr mit Symlinks, und die 2.x-Sperre (ab 1.6.3). Läuft in einem Wegwerf-HOME."""
import os, subprocess, tempfile, unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "bin" / "hyhy-paths"


class Paths(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name)
        self.env = dict(os.environ, HOME=str(self.home))

    def tearDown(self):
        self._tmp.cleanup()

    def run_dx(self, *args):
        return subprocess.run([str(SCRIPT), *args], env=self.env, capture_output=True, text=True)

    def write(self, rel, text="x"):
        p = self.home / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def install_json(self, version, rel=".config/draconyx/install.json"):
        self.write(rel, '{"version": "%s"}' % version)

    # --- Migration -----------------------------------------------------------
    def test_old_dir_is_moved_and_symlinked(self):
        self.write(".config/draconyx/terminal", "ghostty")
        self.assertEqual(self.run_dx("migrate").returncode, 0)
        new = self.home / ".config/hypr-hypr"
        old = self.home / ".config/draconyx"
        self.assertTrue(new.is_dir() and not new.is_symlink())
        self.assertEqual((new / "terminal").read_text(), "ghostty")
        self.assertTrue(old.is_symlink())
        self.assertEqual((old / "terminal").read_text(), "ghostty")   # alter Pfad liest weiter

    def test_fresh_home_creates_new_dirs_and_links(self):
        self.assertEqual(self.run_dx("migrate").returncode, 0)
        for new, old in [(".config/hypr-hypr", ".config/draconyx"),
                         (".local/state/hypr-hypr", ".local/state/draconyx"),
                         (".local/share/hypr-hypr", ".local/share/draconyx-hypr"),
                         (".cache/hypr-hypr", ".cache/draconyx"),
                         (".local/share/hypr-hypr-backups", ".local/share/draconyx-backups")]:
            self.assertTrue((self.home / new).is_dir(), new)
            self.assertTrue((self.home / old).is_symlink(), old)

    def test_quickshell_dir_is_linked_so_qs_c_draconyx_still_works(self):
        self.write(".config/quickshell/draconyx/shell.qml", "// shell")
        self.run_dx("migrate")
        self.assertEqual((self.home / ".config/quickshell/draconyx/shell.qml").read_text(), "// shell")
        self.assertEqual((self.home / ".config/quickshell/hypr-hypr/shell.qml").read_text(), "// shell")

    def test_both_existing_merges_without_overwriting_and_keeps_original(self):
        self.write(".config/draconyx/terminal", "alt")
        self.write(".config/draconyx/only-old", "o")
        self.write(".config/hypr-hypr/terminal", "neu")
        self.run_dx("migrate")
        new = self.home / ".config/hypr-hypr"
        self.assertEqual((new / "terminal").read_text(), "neu")          # neuer Stand gewinnt
        self.assertEqual((new / "only-old").read_text(), "o")            # fehlendes wird übernommen
        backups = list((self.home / ".local/share/hypr-hypr-backups").glob("migrate-*/draconyx/terminal"))
        self.assertEqual(len(backups), 1)                                 # Original bleibt in der Sicherung
        self.assertEqual(backups[0].read_text(), "alt")

    def test_second_run_changes_nothing(self):
        self.write(".config/draconyx/terminal", "t")
        self.run_dx("migrate")
        before = sorted(str(p) for p in self.home.rglob("*"))
        r = self.run_dx("migrate")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(str(p) for p in self.home.rglob("*")), before)

    # --- 2.x-Sperre ----------------------------------------------------------
    def test_update_to_2x_blocked_below_1_6_3(self):
        self.install_json("1.6.2")
        r = self.run_dx("gate", "2.0.0")
        self.assertEqual(r.returncode, 1)
        self.assertIn("1.6.3", r.stdout)

    def test_update_to_2x_allowed_from_1_6_3(self):
        self.install_json("1.6.3")
        self.assertEqual(self.run_dx("gate", "2.0.0").returncode, 0)

    def test_update_to_2x_allowed_from_newer_1x(self):
        self.install_json("1.9.0", rel=".config/hypr-hypr/install.json")
        self.assertEqual(self.run_dx("gate", "2.0.1").returncode, 0)

    def test_1x_updates_are_never_blocked(self):
        self.install_json("1.0.0")
        self.assertEqual(self.run_dx("gate", "1.6.3").returncode, 0)

    def test_unknown_installed_version_blocks_2x(self):
        self.assertEqual(self.run_dx("gate", "2.0.0").returncode, 1)

    # --- Befehle dx-* -> hyhy-* ----------------------------------------------
    def test_links_make_old_command_names_point_to_new_ones(self):
        bindir = self.home / ".local/bin"
        bindir.mkdir(parents=True)
        (bindir / "hyhy-doctor").write_text("#!/bin/sh\necho doc\n")
        (bindir / "dx-doctor").write_text("old copy")                  # alte Kopie aus der Vorgängerversion
        self.run_dx("links")
        self.assertTrue((bindir / "dx-doctor").is_symlink())
        self.assertEqual((bindir / "dx-doctor").resolve(), (bindir / "hyhy-doctor").resolve())
        self.assertEqual(self.run_dx("links").returncode, 0)            # zweiter Lauf ist unschädlich

    def test_links_create_legacy_name_for_fresh_install(self):
        bindir = self.home / ".local/bin"
        bindir.mkdir(parents=True)
        (bindir / "hyhy-apps").write_text("x")
        self.run_dx("links")
        self.assertTrue((bindir / "dx-apps").is_symlink())


if __name__ == "__main__":
    unittest.main()
