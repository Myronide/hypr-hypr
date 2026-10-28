"""Tests für settings_pages/page_bluetooth.py: Parser, Diagnose und Befehlsbauer, ohne GTK und ohne Bluetooth."""
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "settings_pages"))
import page_bluetooth as B  # noqa: E402

SHOW = """Controller BC:C7:46:99:71:9F (public)
\tName: Host
\tAlias: Mein Rechner
\tPowered: yes
\tDiscoverable: no
\tPairable: yes
\tDiscovering: no
\tUUID: Audio Sink                (0000110b-0000-1000-8000-00805f9b34fb)
"""
INFO = """Device 20:18:5B:0B:18:35 (public)
\tName: Kopfhörer
\tAlias: Meine Kopfhörer
\tIcon: audio-card
\tPaired: yes
\tTrusted: yes
\tBlocked: no
\tConnected: yes
\tBattery Percentage: 0x5a (90)
"""
RFKILL = "4: hci0: Bluetooth\n\tSoft blocked: %s\n\tHard blocked: %s\n"


class Parser(unittest.TestCase):
    def test_devices(self):
        t = "Device AA:BB:CC:DD:EE:01 Maus\n\x1b[0;94m[NEW]\x1b[0m Device AA:BB:CC:DD:EE:02 \nDevice aa:bb:cc:dd:ee:01 Doppelt\nMüll\n[CHG] Controller X"
        self.assertEqual(B.parse_devices(t), [("AA:BB:CC:DD:EE:01", "Maus"), ("AA:BB:CC:DD:EE:02", "AA:BB:CC:DD:EE:02")])
        self.assertEqual(B.parse_devices(""), [])
        self.assertEqual(B.parse_devices(None), [])

    def test_info(self):
        d = B.parse_info(INFO, "20:18:5b:0b:18:35")
        self.assertEqual((d["name"], d["paired"], d["trusted"], d["connected"], d["battery"], d["mac"]),
                         ("Meine Kopfhörer", True, True, True, 90, "20:18:5B:0B:18:35"))
        self.assertIsNone(B.parse_info("Device 00:00:00:00:00:01 not available\n", "x"))
        self.assertIsNone(B.parse_info("", "x"))
        self.assertIsNone(B.parse_info("Unsinn", "x"))
        self.assertIsNone(B.parse_info(INFO.replace("0x5a (90)", "kaputt"), "x")["battery"])

    def test_show(self):
        a = B.parse_show(SHOW)
        self.assertEqual((a["name"], a["powered"], a["discoverable"], a["pairable"], a["discovering"]),
                         ("Mein Rechner", True, False, True, False))
        self.assertIsNone(B.parse_show("No default controller available\n"))
        self.assertIsNone(B.parse_show(""))

    def test_rfkill(self):
        self.assertEqual(B.parse_rfkill(RFKILL % ("yes", "no")), (True, False, True))
        self.assertEqual(B.parse_rfkill(RFKILL % ("no", "yes")), (False, True, True))
        self.assertEqual(B.parse_rfkill(""), (False, False, False))


class Diagnose(unittest.TestCase):
    def test_states(self):
        self.assertEqual(B.diagnose(SHOW, 0)[0], "ok")
        self.assertEqual(B.diagnose("", 127, bt_missing=True)[0], "nobin")
        self.assertEqual(B.diagnose("No default controller available", 1, RFKILL % ("no", "yes"))[0], "hardblock")
        self.assertEqual(B.diagnose("No default controller available", 1, RFKILL % ("yes", "no"))[0], "softblock")
        self.assertEqual(B.diagnose("No default controller available", 0, "")[0], "noadapter")
        self.assertEqual(B.diagnose("", 1)[0], "nodaemon")
        self.assertEqual(B.diagnose("Command timed out", 127)[0], "timeout")
        for st in ("nobin", "hardblock"):
            self.assertTrue(B.diagnose("", 1, RFKILL % ("no", "yes"), st == "nobin")[1])


class Collect(unittest.TestCase):
    def run_fake(self, powered=True):
        calls = []

        def run(args, timeout=4):
            calls.append(args)
            if args[:2] == ["bluetoothctl", "show"]:
                return subprocess.CompletedProcess(args, 0, SHOW if powered else SHOW.replace("Powered: yes", "Powered: no"), "")
            if args[:2] == ["bluetoothctl", "devices"]:
                return subprocess.CompletedProcess(args, 0, "Device 20:18:5B:0B:18:35 K\nDevice AA:BB:CC:DD:EE:02 Neu\n", "")
            if args[:2] == ["bluetoothctl", "info"]:
                if args[2] == "20:18:5B:0B:18:35":
                    return subprocess.CompletedProcess(args, 0, INFO, "")
                return subprocess.CompletedProcess(args, 0, "Device AA:BB:CC:DD:EE:02 (public)\n\tName: Neu\n\tPaired: no\n\tConnected: no\n", "")
            return subprocess.CompletedProcess(args, 1, "", "")
        return run, calls

    def test_ok(self):
        run, calls = self.run_fake()
        r = B.collect(run, have=lambda n: n == "bluetoothctl")
        self.assertEqual(r["status"], "ok")
        self.assertEqual([B.group_of(d) for d in r["devices"]], ["connected", "nearby"])
        self.assertTrue(all(c[0] == "bluetoothctl" for c in calls))
        self.assertTrue(all(c[1] in ("show", "devices", "info") for c in calls))   # nur lesend

    def test_off(self):
        run, _ = self.run_fake(powered=False)
        r = B.collect(run, have=lambda n: n == "bluetoothctl")
        self.assertEqual(r["devices"], [])
        self.assertIn("ausgeschaltet", r["hint"])

    def test_missing_and_down(self):
        r = B.collect(lambda a, timeout=4: subprocess.CompletedProcess(a, 127, "", "x"), have=lambda n: False)
        self.assertEqual(r["status"], "nobin")
        r = B.collect(lambda a, timeout=4: subprocess.CompletedProcess(a, 1, "", ""), have=lambda n: n == "bluetoothctl")
        self.assertEqual(r["status"], "nodaemon")


class Commands(unittest.TestCase):
    def test_power(self):
        self.assertEqual(B.power_cmds(False), [["bluetoothctl", "power", "off"]])
        self.assertEqual(B.power_cmds(True, True), [["rfkill", "unblock", "bluetooth"], ["bluetoothctl", "power", "on"]])
        self.assertEqual(B.power_cmds(True), [["bluetoothctl", "power", "on"]])
        self.assertEqual(B.discoverable_cmd(True), ["bluetoothctl", "discoverable", "on"])

    def test_device(self):
        m = "aa:bb:cc:dd:ee:01"
        self.assertEqual(B.device_cmd("connect", m)[-2:], ["connect", "AA:BB:CC:DD:EE:01"])
        self.assertEqual(B.device_cmd("trust", m), ["bluetoothctl", "trust", "AA:BB:CC:DD:EE:01"])
        self.assertEqual(B.device_cmd("remove", m)[1], "remove")
        self.assertIn("pair", B.device_cmd("pair", m))
        for bad in ("", "xx", "AA:BB:CC:DD:EE", "AA:BB:CC:DD:EE:01; rm -rf", None, 5, "--help"):
            self.assertIsNone(B.device_cmd("connect", bad))
        self.assertIsNone(B.device_cmd("format", m))

    def test_scan(self):
        self.assertEqual(B.scan_cmd(60), ["bluetoothctl", "--timeout", "60", "scan", "on"])
        self.assertEqual(B.scan_cmd(100000)[2], "300")
        self.assertEqual(B.scan_cmd(-1)[2], "5")

    def test_results(self):
        self.assertEqual(B.parse_result("Connection successful"), (True, "Verbunden."))
        self.assertFalse(B.parse_result("Failed to connect: org.bluez.Error.Failed")[0])
        self.assertFalse(B.parse_result("Failed to pair: org.bluez.Error.AuthenticationFailed")[0])
        self.assertEqual(B.parse_result("", 0)[0], True)
        self.assertEqual(B.parse_result("", 124)[0], False)

    def test_status_text(self):
        d = B.parse_info(INFO, "20:18:5B:0B:18:35")
        self.assertEqual(B.device_status_text(d), "Verbunden · vertrauenswürdig · Akku 90 %")

    def test_module_interface(self):
        self.assertIsInstance(B.TITLE, str)
        self.assertTrue(callable(B.build))


if __name__ == "__main__":
    unittest.main()
