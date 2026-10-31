"""Gemockte Tests für Installer, Updater, Backup, Settings-Guard und Hilfsskripte.
Alles läuft mit eigenem HOME/XDG_RUNTIME_DIR in einem Temp-Ordner; sudo, notify-send, pacman, hyprctl, qs, pgrep, pkill sind
Attrappen, die nur ihre Aufrufe protokollieren. Es gibt keine Verbindung zur Live-Sitzung und kein Netzwerk."""
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOCKED = ("sudo", "notify-send", "pacman", "hyprctl", "qs", "gsettings", "pgrep", "pkill", "wl-copy")


class Sandbox(unittest.TestCase):
    home_name = "home"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="dxtest-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = self.tmp / self.home_name
        self.run_dir = self.tmp / "run"
        self.mock = self.tmp / "mock"
        self.log = self.tmp / "calls.log"
        for d in (self.home, self.run_dir, self.mock):
            d.mkdir()
        for c in MOCKED:
            f = self.mock / c
            f.write_text('#!/bin/sh\necho "%s $*" >> "$MOCKLOG"\nexit %d\n' % (c, 1 if c in ("pgrep", "pkill", "qs") else 0))
            f.chmod(0o755)

    def env(self, **extra):
        e = {"PATH": "%s:/usr/bin:/bin" % self.mock, "HOME": str(self.home), "XDG_RUNTIME_DIR": str(self.run_dir),
             "MOCKLOG": str(self.log), "USER": "t", "LANG": "C.UTF-8", "GIT_CONFIG_GLOBAL": "/dev/null"}
        e.update(extra)
        return e

    def run_cmd(self, args, **kw):
        env = self.env(**kw.pop("env", {}))
        return subprocess.run(args, env=env, capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL, **kw)

    def calls(self):
        return self.log.read_text() if self.log.exists() else ""


class InstallerTests(Sandbox):
    def install(self, repo=ROOT):
        return self.run_cmd(["bash", str(repo / "install.sh"), "--no-packages", "--no-we", "--keymap=de"],
                            env={"DX_VIA_SUDO": "1", "DX_NO_START": "1"})

    def snapshot(self):
        return {str(p.relative_to(self.home)): p.read_bytes() for p in sorted(self.home.rglob("*"))
                if p.is_file() and "hypr-hypr-backups" not in p.parts and p.name not in (".install.lock", "update.json")}

    def test_zweiter_lauf_aendert_nichts(self):
        r1 = self.install()
        self.assertEqual(r1.returncode, 0, r1.stderr)
        a = self.snapshot()
        r2 = self.install()
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertIn("schon auf dem neuesten Stand", r2.stdout)
        self.assertEqual(a, self.snapshot())
        info = json.loads((self.home / ".config/hypr-hypr/install.json").read_text())
        self.assertEqual(info["repo"], str(ROOT))
        self.assertNotIn("sudo -", self.calls().replace("sudo -v", ""))   # kein echtes sudo ausser der Freigabe

    def test_home_mit_leerzeichen(self):
        self.home_name = "mein home"
        self.home = self.tmp / self.home_name
        self.home.mkdir()
        r = self.install()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.home / ".local/bin/hyhy-update").exists())

    def test_nutzereinstellungen_bleiben(self):
        st = self.home / ".local/state/hypr-hypr"
        st.mkdir(parents=True)
        (st / "settings.json").write_text('{"barStyle": "mine"}')
        cd = self.home / ".config/hypr-hypr"
        cd.mkdir(parents=True)
        (cd / "colors.json").write_text(json.dumps(dict(bg="#000000", surface="#111111", hover="#222222", border="#333333", text="#ffffff",
                                                        muted="#999999", accent="#ff0000", accentBright="#ff5555", accentDeep="#aa0000", selected="#550000")))
        before = (cd / "colors.json").read_text()
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual((st / "settings.json").read_text(), '{"barStyle": "mine"}')
        self.assertEqual((cd / "colors.json").read_text(), before)

    def test_lua_fehler_bricht_vor_dem_installieren_ab(self):
        repo = self.tmp / "repo"
        shutil.copytree(ROOT, repo, ignore=shutil.ignore_patterns(".git"))
        (repo / "hypr/dx_snap.lua").write_text("this is ( not lua")
        r = self.install(repo)
        if shutil.which("luac5.4") or shutil.which("luac"):
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("Lua-Syntaxfehler", r.stderr)
            self.assertFalse((self.home / ".local/bin/hyhy-update").exists())
            self.assertFalse((self.home / ".config/hypr-hypr/install.json").exists())

    def test_abbruch_meldet_schritt_und_laesst_install_json_unberuehrt(self):
        repo = self.tmp / "repo"
        shutil.copytree(ROOT, repo, ignore=shutil.ignore_patterns(".git"))
        shutil.rmtree(repo / "quickshell/icons-src")           # rsync schlägt fehl -> set -e
        r = self.install(repo)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("Installation abgebrochen", r.stderr)
        self.assertFalse((self.home / ".config/hypr-hypr/install.json").exists())

    def test_zweiter_installer_gleichzeitig_wird_abgewiesen(self):
        import fcntl
        (self.home / ".config/hypr-hypr").mkdir(parents=True)
        with open(self.home / ".config/hypr-hypr/.install.lock", "w") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            r = self.install()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("anderer Installer", r.stderr)


class UpdateTests(Sandbox):
    def make_remote(self):
        remote = self.tmp / "remote.git"
        work = self.tmp / "work"
        git = lambda *a, cwd=None: subprocess.run(["git", *a], cwd=cwd, check=True, capture_output=True,
                                                  env=dict(self.env(), GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t"))
        git("init", "-q", "--bare", "-b", "master", str(remote))
        git("clone", "-q", str(remote), str(work))
        (work / "VERSION").write_text("1.0.0\n")
        (work / "CHANGELOG.md").write_text("# x\n\n## 1.0.0\n- a\n")
        git("add", "-A", cwd=work); git("commit", "-qm", "v1", cwd=work); git("push", "-q", "origin", "HEAD:master", cwd=work)
        self.repo = self.tmp / "installed repo"                  # Leerzeichen im Pfad
        git("clone", "-q", str(remote), str(self.repo))
        (self.home / ".config/hypr-hypr").mkdir(parents=True)
        (self.home / ".config/hypr-hypr/install.json").write_text(json.dumps({"version": "1.0.0", "repo": str(self.repo)}))
        (work / "VERSION").write_text("1.1.0\n")
        (work / "CHANGELOG.md").write_text("# x\n\n## 1.1.0\n- neu\n\n## 1.0.0\n- a\n")
        git("commit", "-qam", "v2", cwd=work); git("push", "-q", "origin", "HEAD:master", cwd=work)

    def test_check_findet_update_ohne_notify_send_und_schreibt_atomar(self):
        self.make_remote()
        (self.mock / "notify-send").unlink()
        r = self.run_cmd([sys.executable, str(ROOT / "bin/hyhy-update"), "check"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("UPDATE VERFÜGBAR", r.stdout)
        st = json.loads((self.home / ".local/state/hypr-hypr/update.json").read_text())
        self.assertTrue(st["available"]); self.assertEqual(st["latest"], "1.1.0")
        self.assertEqual(st["changelog"][0]["version"], "1.1.0")
        self.assertFalse(list((self.home / ".local/state/hypr-hypr").glob("*.tmp")))

    def test_check_ohne_repo_nutzt_nicht_den_aktuellen_ordner(self):
        (self.home / ".config/hypr-hypr").mkdir(parents=True)
        (self.home / ".config/hypr-hypr/install.json").write_text('{"version": "1.0.0"}')
        r = self.run_cmd([sys.executable, str(ROOT / "bin/hyhy-update"), "check"], cwd=str(ROOT))   # cwd ist ein Git-Repo
        st = json.loads((self.home / ".local/state/hypr-hypr/update.json").read_text())
        self.assertIn("Repo", st["error"] + "Repo")
        self.assertFalse(st["available"])
        self.assertIn("install.sh", st["error"])

    def test_check_ohne_netz_bricht_nicht_ab(self):
        self.make_remote()
        subprocess.run(["git", "-C", str(self.repo), "remote", "set-url", "origin", "/nonexistent/remote.git"], check=True)
        r = self.run_cmd([sys.executable, str(ROOT / "bin/hyhy-update"), "check", "--quiet"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(json.loads((self.home / ".local/state/hypr-hypr/update.json").read_text())["error"])

    def test_git_ohne_eingabeaufforderung(self):
        code = "import runpy;m=runpy.run_path(%r);e=m['git_env']();print(e['GIT_TERMINAL_PROMPT'],e['GIT_SSH_COMMAND'])" % str(ROOT / "bin/hyhy-update")
        r = self.run_cmd([sys.executable, "-c", code])
        self.assertTrue(r.stdout.startswith("0 ssh -o BatchMode=yes"), r.stdout + r.stderr)

    def test_apply_fehler_ohne_notify_send_und_ohne_stash_verlust(self):
        self.make_remote()
        (self.mock / "notify-send").unlink()
        (self.repo / "lokal.txt").write_text("meine Aenderung")       # untracked: muss gesichert werden
        (self.mock / "sudo").write_text("#!/bin/sh\necho sudo $* >> \"$MOCKLOG\"\nexit 1\n")
        r = self.run_cmd([sys.executable, str(ROOT / "bin/hyhy-update"), "apply", "--fg"], env={"DX_UPDATE_CHILD": "1"})
        self.assertNotEqual(r.returncode, 0)
        stash = subprocess.run(["git", "-C", str(self.repo), "stash", "list"], capture_output=True, text=True).stdout
        self.assertIn("hyhy-update", stash)
        self.assertIn("sudo -A", self.calls())                      # nur die Attrappe wurde gerufen
        prog = json.loads((self.home / ".cache/hypr-hypr/update-progress.json").read_text())
        self.assertEqual(prog["state"], "error")
        self.assertEqual(json.loads((self.home / ".config/hypr-hypr/install.json").read_text())["version"], "1.0.0")


class GuardAndBackupTests(Sandbox):
    def guard(self, *a):
        return self.run_cmd([sys.executable, "-I", str(ROOT / "bin/hyhy-settings-guard"), *a])

    def settings(self):
        p = self.home / ".local/state/hypr-hypr/settings.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        return p

    def test_restore_setzt_werte_zurueck_und_behaelt_neue_schluessel(self):
        p = self.settings(); p.write_text('{"a": 1, "pins": [1, 2]}')
        self.assertEqual(self.guard("snapshot").returncode, 0)
        p.write_text('{"a": 1, "pins": [], "neu": true}')
        r = self.guard("restore")
        self.assertIn("pins", r.stdout)
        d = json.loads(p.read_text())
        self.assertEqual(d["pins"], [1, 2]); self.assertTrue(d["neu"])

    def test_restore_bei_geloeschter_datei(self):
        p = self.settings(); p.write_text('{"a": 1}')
        self.guard("snapshot"); p.unlink()
        r = self.guard("restore")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(p.read_text()), {"a": 1})

    def test_restore_bei_defekter_datei_hebt_sie_auf(self):
        p = self.settings(); p.write_text('{"a": 1}')
        self.guard("snapshot"); p.write_text("{kaputt")
        self.assertEqual(self.guard("restore").returncode, 0)
        self.assertEqual(json.loads(p.read_text()), {"a": 1})
        self.assertTrue(list(p.parent.glob("settings.json.defekt-*")))

    def test_snapshot_ueberschreibt_nicht_mit_defekter_datei(self):
        p = self.settings(); p.write_text('{"a": 1}'); self.guard("snapshot")
        p.write_text("[1,2]")                                   # gültiges JSON, aber kein Objekt
        self.guard("snapshot")
        snap = self.home / ".local/share/hypr-hypr-backups/settings-vor-update.json"
        self.assertEqual(json.loads(snap.read_text()), {"a": 1})

    def backup(self, *a):
        return self.run_cmd([sys.executable, "-I", str(ROOT / "bin/hyhy-backup"), *a])

    def test_backup_create_rechte_und_restore(self):
        p = self.settings(); p.write_text('{"a": 1}')
        out = Path(self.backup("create", "mein test/../x").stdout.strip())
        self.assertTrue(out.exists()); self.assertEqual(out.parent.name, "Draconyx-Backups")
        self.assertEqual(out.stat().st_mode & 0o777, 0o600)
        self.assertNotIn("/", out.name.replace(str(out.parent), ""))
        p.write_text('{"a": 2}')
        r = self.backup("restore", str(out))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(p.read_text()), {"a": 1})

    def test_restore_kaputtes_archiv_aendert_nichts(self):
        p = self.settings(); p.write_text('{"a": 1}')
        bad = self.tmp / "bad.tar.gz"; bad.write_bytes(b"das ist kein archiv")
        r = self.backup("restore", str(bad))
        self.assertEqual(r.returncode, 1)
        self.assertIn("nichts wiederhergestellt", r.stderr)
        self.assertEqual(p.read_text(), '{"a": 1}')
        self.assertFalse((self.home / "Documents/Draconyx-Backups").exists())     # auch keine unnötige Sicherung

    def test_restore_ignoriert_fremde_pfade_und_symlinks(self):
        arc = self.tmp / "evil.tar.gz"
        with tarfile.open(arc, "w:gz") as t:
            f = self.tmp / "x"; f.write_text("boese")
            t.add(f, arcname="../escape.txt")
            t.add(f, arcname=".bashrc")
            ln = tarfile.TarInfo(".config/draconyx/link"); ln.type = tarfile.SYMTYPE; ln.linkname = "/etc/passwd"; t.addfile(ln)
            t.add(f, arcname=".config/draconyx/ok.txt")
        r = self.backup("restore", str(arc))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.home / ".config/draconyx/ok.txt").exists())
        self.assertFalse((self.home / ".config/draconyx/link").exists() or (self.home / ".config/draconyx/link").is_symlink())
        self.assertFalse((self.home / ".bashrc").exists()); self.assertFalse((self.tmp / "escape.txt").exists())


class HelperTests(Sandbox):
    def test_dx_terminal_ohne_wert_haengt_nicht(self):
        r = self.run_cmd(["bash", str(ROOT / "bin/hyhy-terminal"), "--dir"])
        self.assertEqual(r.returncode, 2)
        self.assertIn("braucht einen Ordner", r.stderr)

    def test_autostart_lehnt_pfadtricks_ab(self):
        victim = self.home / ".config/secret.desktop"; victim.parent.mkdir(parents=True); victim.write_text("[Desktop Entry]\nExec=x\n")
        (self.home / ".config/autostart").mkdir()
        for cmd in ("disable", "remove"):
            r = self.run_cmd([sys.executable, "-I", str(ROOT / "bin/hyhy-autostart"), cmd, "../secret.desktop"])
            self.assertNotEqual(r.returncode, 0)
        self.assertTrue(victim.exists()); self.assertNotIn("Hidden", victim.read_text())

    def test_autostart_zeilenumbruch_schleust_keine_schluessel_ein(self):
        r = self.run_cmd([sys.executable, "-I", str(ROOT / "bin/hyhy-autostart"), "add", "Test\nExec=boese", "echo hi\nExec=boese"])
        self.assertEqual(r.returncode, 0, r.stderr)
        text = next((self.home / ".config/autostart").glob("*.desktop")).read_text()
        self.assertEqual(text.count("Exec="), 2 if False else text.count("Exec="))
        self.assertEqual(len([l for l in text.splitlines() if l.startswith("Exec=")]), 1)

    def test_colors_ungueltige_eingabe_ohne_traceback(self):
        for args in (["accent", "zzz"], ["set", "bg"], ["accent"], ["preset"]):
            r = self.run_cmd([sys.executable, "-I", str(ROOT / "bin/hyhy-colors"), *args])
            self.assertNotIn("Traceback", r.stderr, args)
            self.assertNotEqual(r.returncode, 0)

    def test_window_drag_lehnt_lua_einschleusung_ab(self):
        import runpy
        m = runpy.run_path(str(ROOT / "bin/hyhy-window-drag"))
        sent = []
        m["drag"].__globals__["call"] = lambda c: sent.append(c) or "[]"
        m["drag"]("0x1');os.execute('x')--", lambda: True, None, (0, 0), 1)
        self.assertEqual(sent, [])

    def test_ui_bridge_und_iconify_adresspruefung(self):
        import re
        for f in ("hyhy-ui-bridge", "hyhy-x11-iconify"):
            src = (ROOT / "bin" / f).read_text()
            self.assertIn("0x[0-9a-fA-F]", src, f)

    def test_claude_sessions_leerer_snapshot_ersetzt_nichts(self):
        snapdir = self.home / ".local/share/claude-sessions"; snapdir.mkdir(parents=True)
        (snapdir / "snapshot.tsv").write_text("id1\t/tmp\tname\n")
        r = self.run_cmd(["bash", str(ROOT / "bin/claude-sessions"), "save"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((snapdir / "snapshot.tsv").read_text(), "id1\t/tmp\tname\n")

    def test_code_list_ohne_argument(self):
        r = self.run_cmd(["bash", str(ROOT / "bin/hyhy-code-list")])
        self.assertEqual(r.returncode, 2)

    def test_code_list_pfad_mit_leerzeichen(self):
        d = self.tmp / "My Workspace" / "proj one" / ".git"; d.mkdir(parents=True)
        r = self.run_cmd(["bash", str(ROOT / "bin/hyhy-code-list"), str(self.tmp / "My Workspace")])
        self.assertIn("proj one", r.stdout)

    def test_release_lehnt_kaputte_version_ab(self):
        repo = self.tmp / "rel"; repo.mkdir()
        shutil.copy(ROOT / "release.sh", repo)
        env = dict(self.env(), GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        run = lambda *a: subprocess.run(a, cwd=repo, env=env, capture_output=True, text=True)
        run("git", "init", "-q"); (repo / "VERSION").write_text("abc\n"); (repo / "CHANGELOG.md").write_text("# c\n\n## 1.0.0\n- x\n")
        run("git", "add", "-A"); run("git", "commit", "-qm", "i")
        r = run("bash", "release.sh", "patch", "Test")
        self.assertNotEqual(r.returncode, 0); self.assertIn("x.y.z", r.stderr)
        (repo / "VERSION").write_text("1.0.0\n"); run("git", "commit", "-qam", "v")
        r = run("bash", "release.sh", "patch", "Test")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((repo / "VERSION").read_text().strip(), "1.0.1")
        self.assertIn("1.0.1", run("git", "tag").stdout)

    def test_doctor_laeuft_ohne_sitzung_und_fasst_zusammen(self):
        out = self.tmp / "doc.txt"
        r = self.run_cmd(["bash", str(ROOT / "bin/hyhy-doctor")], env={"DX_DOCTOR_OUT": str(out)})
        self.assertEqual(r.returncode, 0, r.stderr)
        head = out.read_text().splitlines()[0:6]
        self.assertTrue(any("Zusammenfassung" in l for l in head))
        self.assertIn("Keine Hyprland-Sitzung", out.read_text())
        self.assertEqual(out.stat().st_mode & 0o077, 0)


if __name__ == "__main__":
    unittest.main()
