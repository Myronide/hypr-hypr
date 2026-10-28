"""Tests für settings_pages/page_audio.py: Parser und Befehlsbauer, ohne GTK, PipeWire oder echte Geräte."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "settings_pages"))
import page_audio as A  # noqa: E402


def vol(*pcts, ch=("front-left", "front-right")):
    return {c: {"value": int(p * 655.36), "value_percent": "%d%%" % p, "db": "0 dB"} for c, p in zip(ch, pcts)}


SINKS = json.dumps([
    {"index": 1, "name": "alsa_output.a", "description": "Lautsprecher", "mute": False, "volume": vol(40, 80),
     "active_port": "spk", "ports": [{"name": "spk", "description": "Lautsprecher", "availability": "available"},
                                     {"name": "hp", "description": "Kopfhörer", "availability": "not available"}]},
    {"index": 2, "name": "alsa_output.b", "description": "HDMI", "mute": True, "volume": vol(150, 150), "ports": [], "active_port": None},
])
SOURCES = json.dumps([
    {"name": "alsa_output.a.monitor", "description": "Monitor", "volume": vol(100, 100), "mute": False},
    {"name": "alsa_input.mic", "description": "Mikrofon", "volume": vol(55, ch=("mono",)), "mute": False, "ports": []},
])
INPUTS = json.dumps([
    {"index": 7, "volume": vol(67, 67), "mute": False, "corked": False,
     "properties": {"application.name": "Brave", "media.name": "Wiedergabe"}},
    {"index": 8, "volume": vol(100, 100), "properties": {"node.name": "loop", "node.virtual": "true"}},
    {"index": 9, "volume": {}, "properties": {"application.name": "Leer"}},
])
CARDS = json.dumps([
    {"name": "alsa_card.x", "properties": {"device.description": "Karte X"}, "active_profile": "analog",
     "profiles": {"off": {"description": "Aus", "available": True}, "analog": {"description": "Analog", "available": True},
                  "hdmi": {"description": "HDMI", "available": False}}},
])


class Parser(unittest.TestCase):
    def test_pactl_model(self):
        m = A.parse_pactl(SINKS, SOURCES, INPUTS, CARDS, "alsa_output.a", "alsa_input.mic")
        self.assertEqual([d["id"] for d in m["sinks"]], ["alsa_output.a", "alsa_output.b"])
        a = m["sinks"][0]
        self.assertTrue(a["default"])
        self.assertEqual(a["vol"], 80)
        self.assertAlmostEqual(a["balance"], 0.5)
        self.assertEqual([p["ok"] for p in a["ports"]], [True, False])
        self.assertTrue(m["sinks"][1]["mute"])
        self.assertEqual(m["sinks"][1]["vol"], 150)
        self.assertEqual([d["id"] for d in m["sources"]], ["alsa_input.mic"])   # Monitor ausgeblendet
        self.assertTrue(m["sources"][0]["default"])
        self.assertEqual([s["name"] for s in m["streams"]], ["Brave"])          # virtuelle/leere Streams weg
        self.assertEqual(m["streams"][0]["media"], "Wiedergabe")
        self.assertEqual([p["name"] for p in m["cards"][0]["profiles"]], ["off", "analog"])  # nicht verfügbare weg
        self.assertEqual(m["cards"][0]["active"], "analog")

    def test_garbage_never_raises(self):
        for bad in ("", "nicht json", "{}", "null", "[1, 2]", '[{"name": 5, "volume": 3}]', '[{"volume": {"a": null}}]'):
            m = A.parse_pactl(bad, bad, bad, bad)
            self.assertEqual(set(m), {"backend", "sinks", "sources", "streams", "cards"})

    def test_balance(self):
        self.assertEqual(A.balance_of([("front-left", 50), ("front-right", 50)]), 0.0)
        self.assertAlmostEqual(A.balance_of([("front-left", 100), ("front-right", 50)]), -0.5)
        self.assertEqual(A.balance_of([("mono", 50)]), 0.0)
        self.assertEqual(A.balance_of([]), 0.0)

    WPCTL = """PipeWire 'pipewire-0' [1.6.10]
 └─ Clients:
        37. WirePlumber                         [1.6.10]

Audio
 ├─ Devices:
 │      61. Sound Blaster                       [alsa]
 │  
 ├─ Sinks:
 │      62. Scarlett Line [vol: 0.40]
 │  *   69. Analoges Stereo                     [vol: 0.82]
 │     131. HDMI [VG270U E]                     [vol: 0.02 MUTED]
 │  
 ├─ Sources:
 │  *  112. Mikrofon                            [vol: 1.00]
 │  
 └─ Streams:
        81. mpv
             83. output_FL

Video
 └─ Devices:
        30. Kamera                              [v4l2]
"""

    def test_wpctl(self):
        m = A.parse_wpctl_status(self.WPCTL)
        self.assertEqual([(d["id"], d["vol"], d["default"], d["mute"]) for d in m["sinks"]],
                         [("62", 40.0, False, False), ("69", 82.0, True, False), ("131", 2.0, False, True)])
        self.assertEqual([d["id"] for d in m["sources"]], ["112"])
        self.assertEqual(A.parse_wpctl_status("")["sinks"], [])
        self.assertEqual(A.parse_wpctl_status("Müll\n├─ Sinks:\n│ kaputt")["sinks"], [])


class Collect(unittest.TestCase):
    def fake(self, table):
        def run(args, timeout=4):
            for key, (rc, out, err) in table.items():
                if args[:len(key)] == list(key):
                    return subprocess.CompletedProcess(args, rc, out, err)
            return subprocess.CompletedProcess(args, 1, "", "unbekannt")
        return run

    def test_pactl_path(self):
        run = self.fake({("pactl", "--format=json", "list", "sinks"): (0, SINKS, ""),
                         ("pactl", "--format=json", "list", "sources"): (0, SOURCES, ""),
                         ("pactl", "get-default-sink"): (0, "alsa_output.b\n", "")})
        m, err = A.collect(run, have=lambda n: n == "pactl")
        self.assertIsNone(err)
        self.assertTrue(m["sinks"][1]["default"])
        self.assertEqual(m["streams"], [])

    def test_no_server(self):
        run = self.fake({("pactl",): (1, "", "Connection refused"), ("wpctl",): (1, "", "Could not connect to PipeWire")})
        m, err = A.collect(run, have=lambda n: True)
        self.assertIsNone(m)
        self.assertIn("Audiodienst", err)

    def test_fallback_wpctl(self):
        run = self.fake({("wpctl", "status"): (0, Parser.WPCTL, "")})
        m, err = A.collect(run, have=lambda n: n == "wpctl")
        self.assertEqual(m["backend"], "wpctl")

    def test_no_tools(self):
        m, err = A.collect(self.fake({}), have=lambda n: False)
        self.assertIsNone(m)
        self.assertIn("pactl", err)

    def test_timeout_message(self):
        self.assertIn("Zeitüberschreitung", A.err_hint("Command timed out after 4 seconds"))


class Commands(unittest.TestCase):
    def test_volume_pactl_keeps_balance(self):
        c = A.volume_cmd("pactl", "sink", "dev", 80, ["front-left", "front-right"], 0.5)
        self.assertEqual(c, ["pactl", "set-sink-volume", "dev", "40%", "80%"])
        self.assertEqual(A.volume_cmd("pactl", "source", "m", 55, ["mono"]), ["pactl", "set-source-volume", "m", "55%"])
        self.assertEqual(A.volume_cmd("pactl", "stream", "7", 10, ["a", "b"])[:3], ["pactl", "set-sink-input-volume", "7"])

    def test_volume_limits(self):
        self.assertEqual(A.volume_cmd("pactl", "sink", "d", 400, ["mono"])[-1], "100%")
        self.assertEqual(A.volume_cmd("pactl", "sink", "d", 400, ["mono"], boost=True)[-1], "150%")
        self.assertEqual(A.volume_cmd("pactl", "sink", "d", -5, ["mono"])[-1], "0%")
        self.assertIsNone(A.volume_cmd("pactl", "sink", "d", "abc"))
        self.assertIsNone(A.volume_cmd("pactl", "sink", "d", float("nan")))
        self.assertIsNone(A.volume_cmd("pactl", "sink", "", 50))
        self.assertIsNone(A.volume_cmd("pactl", "unsinn", "d", 50))

    def test_wpctl_cmds(self):
        self.assertEqual(A.volume_cmd("wpctl", "sink", "69", 65), ["wpctl", "set-volume", "69", "0.65"])
        self.assertEqual(A.mute_cmd("wpctl", "sink", "69", True), ["wpctl", "set-mute", "69", "1"])
        self.assertEqual(A.default_cmd("wpctl", "sink", "69"), ["wpctl", "set-default", "69"])

    def test_others(self):
        self.assertEqual(A.mute_cmd("pactl", "source", "m", False), ["pactl", "set-source-mute", "m", "0"])
        self.assertEqual(A.mute_cmd("pactl", "stream", "7", True), ["pactl", "set-sink-input-mute", "7", "1"])
        self.assertEqual(A.default_cmd("pactl", "source", "m"), ["pactl", "set-default-source", "m"])
        self.assertEqual(A.profile_cmd("card", "analog"), ["pactl", "set-card-profile", "card", "analog"])
        self.assertIsNone(A.profile_cmd("", "x"))
        self.assertEqual(A.port_cmd("sink", "d", "hp"), ["pactl", "set-sink-port", "d", "hp"])
        self.assertIsNone(A.port_cmd("stream", "d", "hp"))

    def test_balance_extremes(self):
        self.assertEqual(A.channel_percents(100, ["front-left", "front-right"], -1), [100, 0])
        self.assertEqual(A.channel_percents(100, ["front-left", "front-right", "lfe"], 1), [0, 100, 100])
        self.assertEqual(A.channel_percents(50, ["front-left", "front-right"], 9), [0, 50])   # Balance begrenzt

    def test_tone_wav(self):
        with tempfile.TemporaryDirectory() as d:
            p = A.write_tone_wav(Path(d) / "x" / "t.wav", "left", seconds=0.2)
            with wave.open(str(p)) as w:
                self.assertEqual(w.getnchannels(), 2)
                data = w.readframes(w.getnframes())
            right = [int.from_bytes(data[i + 2:i + 4], "little", signed=True) for i in range(0, len(data), 4)]
            left = [int.from_bytes(data[i:i + 2], "little", signed=True) for i in range(0, len(data), 4)]
            self.assertEqual(max(map(abs, right)), 0)
            self.assertGreater(max(map(abs, left)), 1000)
            self.assertEqual(os.listdir(p.parent), ["t.wav"])   # keine Reste

    def test_tone_cmd(self):
        with mock.patch.object(A, "which", lambda n: "/bin/" + n if n == "paplay" else None):
            self.assertEqual(A.tone_cmd("pactl", "dev", "/t.wav"), ["paplay", "--device=dev", "/t.wav"])
        with mock.patch.object(A, "which", lambda n: "/bin/" + n if n == "pw-play" else None):
            self.assertEqual(A.tone_cmd("pactl", "dev", "/t.wav"), ["pw-play", "--target=dev", "/t.wav"])
        with mock.patch.object(A, "which", lambda n: None):
            self.assertIsNone(A.tone_cmd("pactl", "dev", "/t.wav"))

    def test_default_run_missing_program(self):
        r = A.default_run(["gibt-es-nicht-xyz"])
        self.assertNotEqual(r.returncode, 0)

    def test_module_interface(self):
        self.assertIsInstance(A.TITLE, str)
        self.assertTrue(callable(A.build))


if __name__ == "__main__":
    unittest.main()
