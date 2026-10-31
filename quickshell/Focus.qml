pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Fokus-Zeit: Timer, Stoppuhr und Pomodoro. Läuft in der Shell weiter, auch wenn der Kalender zu ist;
// die Uhr in der Leiste zeigt die Restzeit. Pomodoro schaltet in der Arbeitsphase „Nicht stören“ ein.
Singleton {
    id: f

    property string mode: "pomodoro"      // timer | stopwatch | pomodoro (gewählter Reiter)
    property bool running: false          // zählt gerade
    property bool started: false          // gestartet (läuft oder pausiert)
    property string runMode: ""           // Modus des laufenden Vorgangs
    property real total: 25 * 60          // Dauer der aktuellen Phase in Sekunden (Timer/Pomodoro)
    property real left: 25 * 60           // Restzeit in Sekunden
    property real elapsed: 0              // Stoppuhr
    property string phase: "focus"        // Pomodoro: focus | break | long
    property int round: 1                 // Pomodoro: wievielte Arbeitsphase (1..4)
    property int timerMin: 10             // Timer-Voreinstellung in Minuten
    property int focusMin: 25
    property int breakMin: 5
    property int longMin: 15
    property bool autoDnd: true           // Arbeitsphase schaltet „Nicht stören“ ein
    property bool dndByUs: false

    property real _endMs: 0               // Timer/Pomodoro: Zielzeit
    property real _startMs: 0             // Stoppuhr: Startzeit minus bisher gelaufen

    readonly property bool active: started && (runMode === mode || true)
    // Kurztext für die Leiste, z. B. "24:13" (leer, wenn nichts läuft)
    readonly property string barText: !started ? "" : fmt(runMode === "stopwatch" ? elapsed : left)
    readonly property real progress: !started ? 0 : (runMode === "stopwatch" ? (elapsed % 60) / 60 : (total > 0 ? 1 - left / total : 0))
    readonly property string phaseLabel: runMode === "pomodoro" ? (phase === "focus" ? "Fokus" : (phase === "long" ? "Lange Pause" : "Pause")) : (runMode === "timer" ? "Timer" : "Stoppuhr")

    function fmt(s) {
        s = Math.max(0, Math.round(s));
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
        const two = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + two(m) + ":" + two(x) : two(m) + ":" + two(x);
    }

    function _phaseSeconds(p) { return (p === "focus" ? focusMin : (p === "long" ? longMin : breakMin)) * 60; }

    function start() {
        if (mode === "stopwatch") {
            runMode = "stopwatch";
            if (!started) elapsed = 0;
            _startMs = Date.now() - elapsed * 1000;
        } else {
            if (!started || runMode !== mode) {
                runMode = mode;
                if (mode === "timer") total = timerMin * 60;
                else { phase = "focus"; round = 1; total = _phaseSeconds("focus"); }
                left = total;
            }
            _endMs = Date.now() + left * 1000;
        }
        started = true; running = true;
        if (runMode === "pomodoro") _dnd(phase === "focus");
    }
    function pause() { if (!running) return; _tick(); running = false; }
    function toggle() { if (running) pause(); else start(); }
    function reset() {
        running = false; started = false; elapsed = 0;
        if (runMode === "pomodoro") _dnd(false);
        runMode = "";
        if (mode === "timer") { total = timerMin * 60; left = total; }
        else if (mode === "pomodoro") { phase = "focus"; round = 1; total = _phaseSeconds("focus"); left = total; }
    }
    function setMode(m) {
        if (started && runMode !== m) return;      // laufenden Vorgang nicht überschreiben
        mode = m;
        if (!started) { if (m === "timer") { total = timerMin * 60; left = total; } else if (m === "pomodoro") { total = _phaseSeconds(phase); left = total; } }
    }
    function setTimerMin(m) { timerMin = Math.max(1, Math.min(600, m)); if (!started && mode === "timer") { total = timerMin * 60; left = total; } }
    function addMinute(d) { if (mode === "timer") { if (started && runMode === "timer") { _endMs += d * 60000; _tick(); total = Math.max(total, left); } else setTimerMin(timerMin + d); } }

    function _dnd(on) {
        if (!autoDnd) return;
        if (on && !dndByUs && !Global.dnd) { Quickshell.execDetached(["swaync-client", "-dn", "-sw"]); dndByUs = true; }
        else if (!on && dndByUs) { Quickshell.execDetached(["swaync-client", "-df", "-sw"]); dndByUs = false; }
    }
    function _notify(title, body) { Quickshell.execDetached(["notify-send", "-a", "Hypr Hypr", "-i", "alarm-symbolic", "-u", "normal", title, body]); }

    function _tick() {
        if (!running) return;
        if (runMode === "stopwatch") { elapsed = (Date.now() - _startMs) / 1000; return; }
        left = Math.max(0, (_endMs - Date.now()) / 1000);
        if (left > 0) return;
        if (runMode === "timer") {
            running = false; started = false; runMode = ""; left = total;
            _notify("Timer abgelaufen", Math.round(total / 60) + " Minuten sind um.");
            return;
        }
        // Pomodoro: nächste Phase
        if (phase === "focus") {
            const longNext = round % 4 === 0;
            phase = longNext ? "long" : "break";
            _notify("Fokus-Phase geschafft", longNext ? "Zeit für eine lange Pause (" + longMin + " Min)." : "Kurze Pause (" + breakMin + " Min).");
            _dnd(false);
        } else {
            if (phase === "long") round = 1; else round++;
            phase = "focus";
            _notify("Pause vorbei", "Nächste Fokus-Phase: " + focusMin + " Minuten.");
            _dnd(true);
        }
        total = _phaseSeconds(phase); left = total; _endMs = Date.now() + left * 1000;
    }

    Timer { interval: 250; repeat: true; running: f.running; onTriggered: f._tick() }
}
