pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Systemwerte für die Leiste (Prozessor, Speicher, Temperatur). Misst nur, solange der Leistenteil eingeschaltet ist.
Singleton {
    id: s
    property real cpu: 0           // Prozent
    property real mem: 0           // Prozent
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real temp: -1         // °C, -1 = unbekannt
    readonly property bool wanted: Global.item("stats")
    property var _last: null

    Timer { interval: 2000; repeat: true; running: s.wanted; triggeredOnStart: true; onTriggered: { p.running = false; p.running = true; } }
    Process {
        id: p
        command: ["sh", "-c",
            "head -1 /proc/stat; awk '/^MemTotal|^MemAvailable/{print $2}' /proc/meminfo; " +
            "for h in /sys/class/hwmon/hwmon*; do case \"$(cat $h/name 2>/dev/null)\" in k10temp|coretemp|zenpower) cat $h/temp1_input 2>/dev/null; break;; esac; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                if (l.length < 3) return;
                const f = l[0].trim().split(/\s+/).slice(1).map(Number);
                const idle = f[3] + (f[4] || 0), total = f.reduce((a, b) => a + b, 0);
                if (s._last) {
                    const dt = total - s._last.total, di = idle - s._last.idle;
                    if (dt > 0) s.cpu = Math.max(0, Math.min(100, 100 * (1 - di / dt)));
                }
                s._last = { idle: idle, total: total };
                const tot = Number(l[1]), avail = Number(l[2]);
                if (tot > 0) { s.memTotalGb = tot / 1048576; s.memUsedGb = (tot - avail) / 1048576; s.mem = 100 * (tot - avail) / tot; }
                s.temp = l.length > 3 && l[3].trim() !== "" ? Number(l[3]) / 1000 : -1;
            }
        }
    }
}
