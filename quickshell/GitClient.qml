import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Draconyx Git: einfacher Git-Client. Änderungen stagen/unstagen (Klick, Pfeil oder Ziehen), committen,
// Verlauf mit Cherry-Pick, Branches, Pull (Rebase), Push, Fetch, Stash, Konflikt-Leiste und Erkennung
// von gelöschten/umbenannten Remote-Branches. Läuft als Layer-Fenster (Alt+F4 trifft die Shell nicht).
PanelWindow {
    id: gcl
    visible: Global.gitOpen
    screen: Global.screenByName(Global.popupScreen)
    anchors.bottom: !Global.barTop
    anchors.top: Global.barTop
    anchors.left: true
    margins.bottom: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.top: Math.round(Global.barHeight + Global.barMargin * 2 + 4)
    margins.left: Global.popupLeft() + 600 + 6          // rechts neben dem Coding-Space-Feld (600 breit)
    readonly property int mainW: 560
    readonly property int diffW: 600
    readonly property bool diffOpen: detailTitle !== "" || diffLines.length > 0
    implicitWidth: mainW + (diffOpen ? diffW + 6 : 0)
    implicitHeight: 640
    exclusionMode: ExclusionMode.Ignore      // Abstand zur Leiste kommt aus den Rändern; die Leisten-Reservierung nicht doppelt rechnen
    color: "transparent"
    WlrLayershell.namespace: "draconyx-code"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // ---------------- Zustand ----------------
    readonly property string repo: Global.gitRepo
    readonly property string repoName: repo.substring(repo.lastIndexOf("/") + 1)
    property bool isRepo: true
    property string branch: ""
    property string upstream: ""
    property int ahead: 0
    property int behind: 0
    property var unstaged: []            // [{ x, y, path, kind }] kind: M A D R ? U
    property var staged: []
    property var branches: []            // [{ name, remote, current, upstream, gone }]
    property var commits: []             // [{ hash, short, author, when, subject, refs }]
    property var picked: ({})            // hash -> true (Mehrfachauswahl)
    property string lastPicked: ""
    property string viewRef: "HEAD"      // Branch, dessen Verlauf angezeigt wird
    property string tab: "changes"       // changes | history
    property string selFile: ""
    property bool selStaged: false
    property var diffLines: []
    property string detailTitle: ""
    property string op: ""               // laufende Operation: rebase | cherry-pick | merge
    property var warnings: []            // [{ text, fix, label }]
    property string remoteDefault: ""
    property string logText: ""
    property bool busy: false
    property string confirm: ""          // zweiter Klick nötig (z. B. "discard:pfad")
    property string newBranchName: ""

    readonly property color addColor: "#6ee05c"
    readonly property color delColor: "#ff6b6b"

    onVisibleChanged: if (visible) { selFile = ""; diffLines = []; picked = ({}); viewRef = "HEAD"; tab = "changes"; confirm = ""; refreshAll(); checkRemote(); }
    onRepoChanged: if (visible) { refreshAll(); checkRemote(); }

    // ---------------- Git ausführen (nacheinander) ----------------
    property var queue: []
    property var current: null
    Process {
        id: proc
        environment: ({ "GIT_TERMINAL_PROMPT": "0", "GIT_EDITOR": "true", "GIT_SEQUENCE_EDITOR": "true", "LC_ALL": "C.UTF-8", "GIT_ASKPASS": "true" })
        stdout: StdioCollector {
            onStreamFinished: {
                const j = gcl.current;
                if (!j) return;
                let out = text, code = 0;
                const i = out.lastIndexOf("__EXIT:");
                if (i >= 0) { code = parseInt(out.substring(i + 7)); out = out.substring(0, i); }
                gcl.current = null; gcl.busy = false;
                if (j.cb) j.cb(out, code);
                gcl.pump();
            }
        }
    }
    function run(args, cb, merge) { queue.push({ args: args, cb: cb, merge: !!merge, raw: false }); pump(); }
    function runRaw(cmd, cb) { queue.push({ cmd: cmd, cb: cb, raw: true }); pump(); }
    function pump() {
        if (current || queue.length === 0) return;
        const j = queue.shift();
        current = j; busy = true;
        if (j.raw) proc.command = ["sh", "-c", "\"$@\"; echo \"__EXIT:$?\""].concat(["sh"], j.cmd);
        else proc.command = ["sh", "-c", j.merge ? "\"$@\" 2>&1; echo \"__EXIT:$?\"" : "\"$@\" 2>/dev/null; echo \"__EXIT:$?\"", "sh", "git", "-C", repo].concat(j.args);
        proc.running = true;
    }
    // Aktion mit Protokoll; danach alles neu laden
    function act(label, args, after) {
        logText = "$ git " + args.join(" ") + "\n";
        run(args, (out, code) => {
            logText += (out.trim() !== "" ? out.trim() + "\n" : "") + (code === 0 ? "✓ " + label : "✗ " + label + " (Code " + code + ")");
            confirm = "";
            if (after) after(code);
            refreshAll();
        }, true);
    }

    // ---------------- Laden ----------------
    function refreshAll() {
        if (repo === "") return;
        loadStatus(); loadBranches(); loadLog(); loadOp();
    }
    function loadStatus() {
        run(["status", "--porcelain=v1", "-b", "-z", "--untracked-files=all"], (out, code) => {
            if (code !== 0) { isRepo = false; return; }
            isRepo = true;
            const parts = out.split("\0");
            const un = [], st = [];
            let i = 0;
            if (parts.length > 0 && parts[0].startsWith("## ")) {
                const h = parts[0].substring(3);
                const m = h.match(/^(.*?)(?:\.\.\.(\S+))?(?: \[(.*)\])?$/);
                branch = m ? m[1].replace(/^No commits yet on /, "").replace(/^HEAD \(no branch\)/, "(losgelöst)") : h;
                upstream = m && m[2] ? m[2] : "";
                const tr = m && m[3] ? m[3] : "";
                const a = tr.match(/ahead (\d+)/), b = tr.match(/behind (\d+)/);
                ahead = a ? parseInt(a[1]) : 0; behind = b ? parseInt(b[1]) : 0;
                i = 1;
            }
            for (; i < parts.length; i++) {
                const e = parts[i];
                if (e.length < 4) continue;
                const x = e[0], y = e[1], path = e.substring(3);
                if (x === "R" || x === "C") i++;                       // nächster Eintrag = alter Name
                if (x === "?" && y === "?") { un.push({ x: x, y: y, path: path, kind: "?" }); continue; }
                if (x !== " ") st.push({ x: x, y: y, path: path, kind: x });
                if (y !== " ") un.push({ x: x, y: y, path: path, kind: y });
            }
            unstaged = un; staged = st;
            if (selFile !== "") showDiff(selFile, selStaged);
        });
    }
    function loadBranches() {
        run(["for-each-ref", "--format=%(refname)\t%(refname:short)\t%(HEAD)\t%(upstream:short)\t%(upstream:track)", "refs/heads", "refs/remotes"], (out, code) => {
            const l = [];
            for (const line of out.split("\n")) {
                if (line === "") continue;
                const p = line.split("\t");
                if (p[0].endsWith("/HEAD")) continue;
                const remote = p[0].startsWith("refs/remotes/");
                l.push({ name: p[1], remote: remote, current: p[2] === "*", upstream: p[3] || "", gone: (p[4] || "").indexOf("gone") >= 0 });
            }
            branches = l;
            computeWarnings();
        });
    }
    function loadLog() {
        run(["log", viewRef, "--date=relative", "--pretty=format:%H%x1f%h%x1f%an%x1f%ar%x1f%s%x1f%D", "-n", "400"], (out, code) => {
            const l = [];
            for (const line of out.split("\n")) {
                if (line === "") continue;
                const p = line.split("\x1f");
                l.push({ hash: p[0], short: p[1], author: p[2], when: p[3], subject: p[4], refs: p[5] || "" });
            }
            commits = l;
        });
    }
    function loadOp() {
        runRaw(["sh", "-c", "cd \"$0\" && d=$(git rev-parse --git-dir) && { { [ -d \"$d/rebase-merge\" ] || [ -d \"$d/rebase-apply\" ]; } && echo rebase; [ -f \"$d/CHERRY_PICK_HEAD\" ] && echo cherry-pick; [ -f \"$d/MERGE_HEAD\" ] && echo merge; }; true", repo], (out, code) => {
            op = out.trim().split("\n")[0] || "";
        });
    }

    // Gelöschte/umbenannte Remote-Branches: Upstream "gone" oder Standard-Branch des Remotes weicht ab
    function computeWarnings() {
        const w = [];
        for (const b of branches) {
            if (b.remote || !b.gone) continue;
            if (remoteDefault !== "" && remoteDefault !== b.name.replace(/^/, "")) {
                w.push({ text: "Remote-Branch '" + b.upstream + "' von '" + b.name + "' existiert nicht mehr – gelöscht oder umbenannt. Das Remote nutzt jetzt '" + remoteDefault + "'.",
                         label: "'" + b.name + "' → '" + remoteDefault + "' umstellen", kind: "rename", local: b.name, target: remoteDefault });
            } else {
                w.push({ text: "Remote-Branch '" + b.upstream + "' von '" + b.name + "' existiert nicht mehr.", label: "Upstream entfernen", kind: "unset", local: b.name, target: "" });
            }
        }
        if (remoteDefault !== "" && branch !== "" && branch !== "(losgelöst)") {
            let hasLocal = false;
            for (const b of branches) if (!b.remote && b.name === remoteDefault) hasLocal = true;
            let hasRemote = false;
            for (const b of branches) if (b.remote && b.name.endsWith("/" + remoteDefault)) hasRemote = true;
            if (!hasLocal && hasRemote && w.length === 0)
                w.push({ text: "Das Remote nutzt '" + remoteDefault + "' als Standard-Branch (lokal noch nicht ausgecheckt).", label: "'" + remoteDefault + "' auschecken", kind: "checkout", local: "", target: remoteDefault });
        }
        warnings = w;
    }
    function checkRemote() {
        // Remote-Standard-Branch (kurzes Netzwerk-Timeout)
        runRaw(["timeout", "8", "git", "-C", repo, "ls-remote", "--symref", "origin", "HEAD"], (out, code) => {
            const m = out.match(/ref: refs\/heads\/(\S+)\s+HEAD/);
            remoteDefault = m ? m[1] : "";
            computeWarnings();
        });
    }
    function fixWarning(w) {
        if (w.kind === "rename") {
            act("Branch umgestellt", ["branch", "-m", w.local, w.target], () => {
                act("Upstream gesetzt", ["fetch", "origin", "--prune"], () => {
                    run(["branch", "-u", "origin/" + w.target, w.target], () => {
                        run(["remote", "set-head", "origin", "-a"], () => refreshAll());
                    });
                });
            });
        } else if (w.kind === "unset") act("Upstream entfernt", ["branch", "--unset-upstream", w.local]);
        else if (w.kind === "checkout") act("Ausgecheckt", ["checkout", w.target]);
    }
    Timer {
        interval: 60000; repeat: true; running: gcl.visible && gcl.isRepo
        onTriggered: { gcl.run(["fetch", "--all", "--prune", "--quiet"], () => { gcl.refreshAll(); gcl.checkRemote(); }); }
    }

    // ---------------- Claude Code Session (je Repository fortlaufend) ----------------
    // Jede Anfrage läuft als "claude -p" in der Session des Repos (--session-id beim ersten Mal, danach --resume):
    // Claude kennt so den bisherigen Verlauf, es läuft aber kein Dauerprozess im Leerlauf.
    property bool claudeBusy: false
    property string claudeMode: ""          // "msg" | "fix"
    property string claudeStatus: ""
    function uuid4() {
        const h = "0123456789abcdef"; let o = "";
        for (let i = 0; i < 32; i++) {
            let c = h[Math.floor(Math.random() * 16)];
            if (i === 12) c = "4"; if (i === 16) c = h[8 + Math.floor(Math.random() * 4)];
            o += c; if (i === 7 || i === 11 || i === 15 || i === 19) o += "-";
        }
        return o;
    }
    Process {
        id: claudeProc
        workingDirectory: gcl.repo
        environment: ({ "PATH": Theme.home + "/.local/bin:/usr/local/bin:/usr/bin:/bin", "GIT_TERMINAL_PROMPT": "0", "GIT_EDITOR": "true" })
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                const mode = gcl.claudeMode;
                gcl.claudeBusy = false;
                if (mode === "msg") {
                    // nur die Nachricht übernehmen (ggf. Code-Zäune entfernen)
                    commitMsg.text = out.replace(/^```[a-z]*\n?/i, "").replace(/\n?```$/, "").trim();
                    gcl.claudeStatus = "";
                    if (out !== "") { gcl.logText = "✓ Claude: " + commitMsg.text.split("\n")[0]; console.log("EV claude-msg " + commitMsg.text.split("\n")[0]); }
                    if (out === "") gcl.logText = "✗ Claude hat keine Commit-Nachricht geliefert";
                } else {
                    gcl.logText += "\n" + (out !== "" ? "Claude: " + out : "Claude: (keine Ausgabe)") + "\n✓ Claude fertig";
                    gcl.refreshAll();
                }
            }
        }
    }
    readonly property var claudeDeny: ["Bash(git push --force:*)", "Bash(git push -f:*)", "Bash(git push --force-with-lease:*)", "Bash(git reset --hard:*)", "Bash(git clean:*)", "Bash(rm:*)", "Bash(git branch -D:*)"]
    function askClaude(mode, prompt, tools) {
        if (claudeBusy || repo === "") return;
        const sess = Object.assign({}, Global.gitSessions);
        let sid = sess[repo];
        const fresh = !sid;
        if (fresh) { sid = uuid4(); sess[repo] = sid; Global.gitSessions = sess; }
        claudeMode = mode; claudeBusy = true;
        claudeStatus = mode === "msg" ? "Claude schreibt die Commit-Nachricht …" : "Claude arbeitet …";
        const cmd = [Theme.home + "/.local/bin/claude", "-p", prompt, fresh ? "--session-id" : "--resume", sid,
                     "--model", "sonnet", "--allowedTools"].concat(tools)
                    .concat(["--disallowedTools"]).concat(claudeDeny)
                    .concat(["--append-system-prompt", "Du arbeitest im Git-Client des Nutzers (Draconyx). Kein force-push, kein hard reset, keine Löschungen ohne ausdrückliche Bitte. " +
                              (mode === "msg" ? "Commit-Nachrichten schreibst du IMMER auf Englisch."
                                              : "Deine Erklärungen an den Nutzer sind kurz und auf Deutsch; Commit-Nachrichten, die du selbst erzeugst, sind IMMER auf Englisch.")]);
        claudeProc.command = cmd;
        claudeProc.running = true;
    }
    function claudeCommitMessage() {
        if (staged.length === 0) { logText = "✗ Erst Dateien stagen, dann kann Claude die Nachricht schreiben"; return; }
        askClaude("msg",
            "Schreibe eine Commit-Nachricht für die aktuell gestageten Änderungen (git diff --cached). Schau dir mit git log -n 10 den Stil der letzten Commits an (z. B. Conventional Commits, falls dort genutzt). " +
            "Die Commit-Nachricht MUSS auf Englisch sein (Imperativ, Titelzeile höchstens ca. 72 Zeichen), egal in welcher Sprache die früheren Commits oder dieser Auftrag sind. " +
            "Antworte AUSSCHLIESSLICH mit der Commit-Nachricht (Titelzeile, bei Bedarf Leerzeile und kurzer englischer Text), ohne Erklärung, ohne Anführungszeichen, ohne Code-Block. Führe keine Änderungen aus.",
            ["Bash(git diff:*)", "Bash(git log:*)", "Bash(git status:*)", "Bash(git show:*)"]);
    }
    function claudeDo(text) {
        const t = text.trim();
        if (t === "") return;
        logText = "Du → Claude: " + t + "\n";
        askClaude("fix",
            "Aufgabe im Repository " + repo + " (Branch " + branch + ", Upstream " + (upstream || "keiner") + "): " + t +
            "\n\nLetzte Ausgabe des Git-Clients:\n" + logText.slice(-1500) +
            "\nStatus: " + unstaged.length + " nicht gestaged, " + staged.length + " gestaged" + (op !== "" ? ", laufende Operation: " + op : "") +
            ". Führe die nötigen git-Befehle selbst aus (bei Konflikten die Dateien lösen und fortsetzen). Fasse am Ende in 1–3 Sätzen zusammen, was du getan hast.",
            ["Bash(git:*)", "Read", "Edit", "Write", "Bash(ls:*)", "Bash(cat:*)"]);
    }
    function claudeFixLast() {
        claudeDo("Das Letzte ist fehlgeschlagen oder hängt (z. B. Pull/Rebase/Konflikt). Finde die Ursache und behebe das Problem sicher.");
    }

    // ---------------- Diff ----------------
    function showDiff(path, isStaged) {
        selFile = path; selStaged = isStaged; detailTitle = path;
        let kind = "";
        for (const f of (isStaged ? staged : unstaged)) if (f.path === path) kind = f.kind;
        const done = (out) => { diffLines = out.split("\n").slice(0, 4000); };
        if (kind === "?") run(["diff", "--no-index", "--", "/dev/null", path], done);
        else run(isStaged ? ["diff", "--cached", "--", path] : ["diff", "--", path], done);
    }
    function showCommit(hash) {
        selFile = ""; detailTitle = hash.substring(0, 8);
        run(["show", "--stat", "--format=%an <%ae>%n%ad%n%n%B", "--date=local", hash], (out) => { diffLines = out.split("\n").slice(0, 400); });
    }
    function showCommitDiff(hash) {
        run(["show", "--format=", hash], (out) => { diffLines = out.split("\n").slice(0, 4000); });
    }

    // ---------------- Aktionen ----------------
    function stage(paths) { act("Gestaged", ["add", "--"].concat(paths)); }
    function unstage(paths) { act("Entfernt", ["restore", "--staged", "--"].concat(paths)); }
    function discard(f) {
        if (f.kind === "?") act("Datei gelöscht", ["clean", "-f", "--", f.path]);
        else act("Änderung verworfen", ["checkout", "--", f.path]);
    }
    function commit() {
        const msg = commitMsg.text.trim();
        if (msg === "" || staged.length === 0) return;
        act("Commit", ["commit", "-m", msg], (code) => { if (code === 0) commitMsg.text = ""; });
    }
    function togglePick(hash, multi) {
        const o = multi ? Object.assign({}, picked) : {};
        if (multi && o[hash]) delete o[hash]; else o[hash] = true;
        picked = o; lastPicked = hash;
        showCommit(hash);
    }
    function pickedOldestFirst() {
        const l = [];
        for (const c of commits) if (picked[c.hash]) l.push(c.hash);
        return l.reverse();
    }
    function cherryPick() {
        const l = pickedOldestFirst();
        if (l.length === 0) return;
        act("Cherry-Pick (" + l.length + ")", ["cherry-pick"].concat(l), () => { picked = ({}); });
    }
    function pushNow() {
        if (upstream === "") act("Push", ["push", "-u", "origin", branch]);
        else act("Push", ["push"]);
    }
    function checkoutBranch(b) {
        if (b.remote) act("Ausgecheckt", ["checkout", "--track", b.name]);
        else act("Ausgecheckt", ["checkout", b.name]);
    }
    function hasChanges() { return unstaged.length + staged.length > 0; }

    // ---------------- Oberfläche ----------------
    Surface {
        id: mainPanel
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
        width: gcl.mainW
        level: 2
        radius: Theme.rXl

        // ===== Kopf =====
        Item {
            id: head
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 92
            Row {
                anchors.left: parent.left; anchors.leftMargin: 20; y: 12
                spacing: 12
                Rectangle {
                    width: 34; height: 34; radius: 11
                    gradient: Gradient { GradientStop { position: 0; color: Theme.accent } GradientStop { position: 1; color: Theme.accentDeep } }
                    Icon { anchors.centerIn: parent; name: "branch"; size: 18 }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: gcl.repoName; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold }
                    Text {
                        text: gcl.isRepo ? gcl.branch + (gcl.upstream !== "" ? "  →  " + gcl.upstream : "  (kein Upstream)")
                                          + (gcl.ahead > 0 ? "   ↑" + gcl.ahead : "") + (gcl.behind > 0 ? "   ↓" + gcl.behind : "") : "Kein Git-Repository"
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
                    }
                }
            }
            Row {
                anchors.left: parent.left; anchors.leftMargin: 16; y: 54
                spacing: 5
                visible: gcl.isRepo
                Repeater {
                    model: [
                        { t: "Fetch", a: "fetch" }, { t: "Pull ↻", a: "pull" }, { t: "Push", a: "push" },
                        { t: "Stash", a: "stash" }, { t: "Pop", a: "pop" }, { t: "⟳", a: "reload" }
                    ]
                    BarButton {
                        required property var modelData
                        implicitHeight: 28; padding: 11; radiusSize: 14
                        color: hovered ? Theme.accentHover : Theme.tile
                        Text { text: modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                        onClicked: {
                            switch (modelData.a) {
                            case "fetch": gcl.act("Fetch", ["fetch", "--all", "--prune"], () => gcl.checkRemote()); break;
                            case "pull": gcl.act("Pull (Rebase)", ["pull", "--rebase", "--autostash"]); break;
                            case "push": gcl.pushNow(); break;
                            case "stash": gcl.act("Stash", ["stash", "push", "-u"]); break;
                            case "pop": gcl.act("Stash pop", ["stash", "pop"]); break;
                            default: gcl.refreshAll(); gcl.checkRemote();
                            }
                        }
                    }
                }
            }
            BarButton {
                anchors.right: parent.right; anchors.rightMargin: 14; y: 12
                minWidth: 30; implicitHeight: 30; radiusSize: 15
                color: hovered ? Qt.rgba(1, 0.42, 0.42, 0.25) : Theme.tile
                Icon { name: "close"; size: 13 }
                onClicked: { Global.gitOpen = false; gcl.detailTitle = ""; gcl.diffLines = []; }
            }
        }

        // ===== Warn- und Konfliktleisten =====
        Column {
            id: bars
            anchors.top: head.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 16; anchors.rightMargin: 16
            spacing: 6
            Rectangle {
                visible: gcl.op !== ""
                width: parent.width; height: 40; radius: 12
                color: Qt.rgba(1, 0.78, 0.34, 0.14); border.color: Theme.amber
                Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                       text: (gcl.op === "rebase" ? "Rebase" : gcl.op === "cherry-pick" ? "Cherry-Pick" : "Merge") + " läuft – Konflikte lösen, Dateien stagen, dann fortsetzen"
                       color: Theme.amber; font.family: Theme.font; font.pixelSize: Theme.fsS }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    BarButton { implicitHeight: 28; padding: 12; radiusSize: 14; color: hovered ? Theme.accentHover : Theme.tile
                        Text { text: "Fortsetzen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                        onClicked: gcl.act("Fortgesetzt", gcl.op === "merge" ? ["commit", "--no-edit"] : [gcl.op, "--continue"]) }
                    BarButton { implicitHeight: 28; padding: 12; radiusSize: 14; color: hovered ? Qt.rgba(1, 0.42, 0.42, 0.3) : Theme.tile
                        Text { text: "Abbrechen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                        onClicked: gcl.act("Abgebrochen", gcl.op === "merge" ? ["merge", "--abort"] : [gcl.op, "--abort"]) }
                }
            }
            Repeater {
                model: gcl.warnings
                Rectangle {
                    required property var modelData
                    width: bars.width; height: 40; radius: 12
                    color: Qt.rgba(1, 0.42, 0.42, 0.12); border.color: Theme.red
                    Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.right: fixBtn.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                           text: modelData.text; elide: Text.ElideRight; color: Theme.red; font.family: Theme.font; font.pixelSize: Theme.fsS }
                    BarButton {
                        id: fixBtn
                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: 28; padding: 12; radiusSize: 14; color: hovered ? Theme.accentHover : Theme.accent
                        Text { text: modelData.label; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsS }
                        onClicked: gcl.fixWarning(modelData)
                    }
                }
            }
        }

        // ===== Kein Repository =====
        Column {
            visible: !gcl.isRepo
            anchors.centerIn: parent
            spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Hier ist noch kein Git-Repository."; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsM }
            BarButton {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: 36; padding: 18; radiusSize: 18; color: hovered ? Theme.accentHover : Theme.accent
                Text { text: "git init"; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsM }
                onClicked: gcl.act("Repository angelegt", ["init"])
            }
        }

        // ===== Körper =====
        Item {
            id: body
            visible: gcl.isRepo
            anchors.top: bars.bottom; anchors.topMargin: 8
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: logBox.top
            anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.bottomMargin: 8

            // ---- Hauptbereich ----
            Item {
                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                anchors.left: parent.left

                Row {
                    id: tabs
                    spacing: 6
                    Repeater {
                        model: [{ k: "changes", t: "Änderungen (" + (gcl.unstaged.length + gcl.staged.length) + ")" }, { k: "history", t: "Verlauf" }, { k: "branches", t: "Branches" }]
                        BarButton {
                            required property var modelData
                            implicitHeight: 30; padding: 12; radiusSize: 15
                            active: gcl.tab === modelData.k
                            color: gcl.tab === modelData.k ? Theme.accentSoft : (hovered ? Theme.tileHover : Theme.tile)
                            Text { text: modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                            onClicked: { gcl.tab = modelData.k; gcl.diffLines = []; gcl.detailTitle = ""; gcl.selFile = ""; if (modelData.k === "changes") gcl.loadStatus(); else if (modelData.k === "history") gcl.loadLog(); }
                        }
                    }
                    Text {
                        visible: gcl.tab === "history"
                        anchors.verticalCenter: parent.verticalCenter
                        text: " " + gcl.viewRef
                        color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
                    }
                }

                // ================= Änderungen =================
                Item {
                    id: changes
                    visible: gcl.tab === "changes"
                    anchors.top: tabs.bottom; anchors.topMargin: 8
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom

                    // Liste "Nicht gestaged"
                    Rectangle {
                        id: unBox
                        anchors.top: parent.top; anchors.left: parent.left
                        width: parent.width; height: (parent.height - commitBox.height - 20) / 2
                        radius: 14; color: gcl.dragOver === "un" ? Theme.accentSoft : Theme.tile
                        border.color: gcl.dragOver === "un" ? Theme.accent : "transparent"
                        Text { x: 14; y: 8; text: "Nicht gestaged (" + gcl.unstaged.length + ")"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold }
                        BarButton { anchors.right: parent.right; anchors.rightMargin: 8; y: 3; implicitHeight: 24; padding: 10; radiusSize: 12; visible: gcl.unstaged.length > 0
                            color: hovered ? Theme.accentHover : "transparent"
                            Text { text: "Alle stagen ›"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                            onClicked: gcl.stage(gcl.unstaged.map(f => f.path)) }
                        ListView {
                            anchors.fill: parent; anchors.topMargin: 30; anchors.margins: 6
                            clip: true; spacing: 1; boundsBehavior: Flickable.StopAtBounds
                            model: gcl.unstaged
                            delegate: FileRow { staged: false; width: ListView.view.width }
                        }
                    }
                    // Liste "Gestaged"
                    Rectangle {
                        id: stBox
                        anchors.top: unBox.bottom; anchors.topMargin: 10; anchors.left: parent.left
                        width: parent.width; height: unBox.height
                        radius: 14; color: gcl.dragOver === "st" ? Theme.accentSoft : Theme.tile
                        border.color: gcl.dragOver === "st" ? Theme.accent : "transparent"
                        Text { x: 14; y: 8; text: "Gestaged (" + gcl.staged.length + ")"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold }
                        BarButton { anchors.right: parent.right; anchors.rightMargin: 8; y: 3; implicitHeight: 24; padding: 10; radiusSize: 12; visible: gcl.staged.length > 0
                            color: hovered ? Theme.accentHover : "transparent"
                            Text { text: "‹ Alle entfernen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                            onClicked: gcl.unstage(gcl.staged.map(f => f.path)) }
                        ListView {
                            anchors.fill: parent; anchors.topMargin: 30; anchors.margins: 6
                            clip: true; spacing: 1; boundsBehavior: Flickable.StopAtBounds
                            model: gcl.staged
                            delegate: FileRow { staged: true; width: ListView.view.width }
                        }
                    }
                    // Commit
                    Rectangle {
                        id: commitBox
                        anchors.left: parent.left; anchors.bottom: parent.bottom
                        width: parent.width; height: 112; radius: 14; color: Theme.tile
                        TextEdit {
                            id: commitMsg
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 12; height: 58
                            color: Theme.text; selectionColor: Theme.accent; wrapMode: TextEdit.Wrap
                            font.family: Theme.font; font.pixelSize: Theme.fsS
                            Keys.onPressed: event => { if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { gcl.commit(); event.accepted = true; } }
                            Text { visible: commitMsg.text === ""; text: "Commit-Nachricht (Strg+Enter = Commit)"; color: Theme.textDim; font: commitMsg.font }
                        }
                        BarButton {
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                            implicitHeight: 32; padding: 16; radiusSize: 16
                            color: gcl.staged.length > 0 && commitMsg.text.trim() !== "" ? (hovered ? Theme.accentBright : Theme.accent) : Theme.tile
                            Text { text: "Commit (" + gcl.staged.length + ")"; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
                            onClicked: gcl.commit()
                        }
                        BarButton {
                            id: claudeMsgBtn
                            visible: Global.claudeAvailable
                            anchors.left: parent.left; anchors.leftMargin: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                            implicitHeight: 32; padding: 12; radiusSize: 16
                            color: gcl.claudeBusy ? Theme.accentSoft : (hovered ? Theme.accentHover : Theme.tile)
                            Row {
                                spacing: 6
                                Image { source: "file://" + Theme.iconDir + "claude-logo.svg"; sourceSize: Qt.size(32, 32); width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: gcl.claudeBusy && gcl.claudeMode === "msg" ? "schreibt …" : "Nachricht"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs; anchors.verticalCenter: parent.verticalCenter }
                            }
                            onClicked: gcl.claudeCommitMessage()
                        }
                        BarButton {
                            anchors.left: Global.claudeAvailable ? claudeMsgBtn.right : parent.left; anchors.leftMargin: Global.claudeAvailable ? 6 : 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                            implicitHeight: 32; padding: 12; radiusSize: 16; color: hovered ? Theme.accentHover : Theme.tile
                            Text { text: "Amend"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                            onClicked: gcl.act("Commit geändert", commitMsg.text.trim() !== "" ? ["commit", "--amend", "-m", commitMsg.text.trim()] : ["commit", "--amend", "--no-edit"])
                        }
                    }
                }

                // ================= Verlauf =================
                Item {
                    id: history
                    visible: gcl.tab === "history"
                    anchors.top: tabs.bottom; anchors.topMargin: 8
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom

                    Rectangle {
                        id: logBoxList
                        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                        width: parent.width; radius: 14; color: Theme.tile
                        Row {
                            id: pickBar
                            x: 10; y: 6; spacing: 6
                            BarButton { implicitHeight: 26; padding: 10; radiusSize: 13; visible: gcl.pickedOldestFirst().length > 0
                                color: hovered ? Theme.accentBright : Theme.accent
                                Text { text: "Cherry-Pick auf " + gcl.branch + " (" + gcl.pickedOldestFirst().length + ")"; color: "white"; font.family: Theme.font; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold }
                                onClicked: gcl.cherryPick() }
                            BarButton { implicitHeight: 26; padding: 10; radiusSize: 13; visible: gcl.pickedOldestFirst().length === 1
                                color: hovered ? Theme.accentHover : Theme.bg2
                                Text { text: "Revert"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                                onClicked: gcl.act("Revert", ["revert", "--no-edit", gcl.pickedOldestFirst()[0]]) }
                            BarButton { implicitHeight: 26; padding: 10; radiusSize: 13; visible: gcl.pickedOldestFirst().length === 1
                                color: hovered ? Theme.accentHover : Theme.bg2
                                Text { text: "Hierhin zurücksetzen (soft)"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                                onClicked: gcl.act("Reset soft", ["reset", "--soft", gcl.pickedOldestFirst()[0]]) }
                            BarButton { implicitHeight: 26; padding: 10; radiusSize: 13; visible: gcl.pickedOldestFirst().length === 1
                                color: gcl.confirm === "reset-hard" ? Qt.rgba(1, 0.42, 0.42, 0.4) : (hovered ? Theme.accentHover : Theme.bg2)
                                Text { text: gcl.confirm === "reset-hard" ? "Wirklich? (hart)" : "Reset hart"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                                onClicked: { if (gcl.confirm === "reset-hard") gcl.act("Reset hard", ["reset", "--hard", gcl.pickedOldestFirst()[0]]); else gcl.confirm = "reset-hard"; } }
                        }
                        Text {
                            visible: gcl.pickedOldestFirst().length === 0
                            x: 14; y: 11
                            text: "Klick = auswählen  ·  Strg+Klick = mehrere  ·  Doppelklick = auschecken"
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs
                        }
                        ListView {
                            anchors.fill: parent; anchors.topMargin: 38; anchors.margins: 6
                            clip: true; spacing: 1; boundsBehavior: Flickable.StopAtBounds
                            model: gcl.commits
                            delegate: Rectangle {
                                id: crow
                                required property var modelData
                                width: ListView.view.width; height: 46; radius: 9
                                readonly property bool on: gcl.picked[modelData.hash] === true
                                color: on ? Theme.accentSoft : (cma.containsMouse ? Theme.tileHover : "transparent")
                                Column {
                                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    Text { width: parent.width; elide: Text.ElideRight; text: crow.modelData.subject; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
                                    Row {
                                        spacing: 8
                                        Text { text: crow.modelData.short; color: Theme.accentBright; font.family: Theme.fontMono; font.pixelSize: Theme.fsXs }
                                        Text { text: crow.modelData.author + " · " + crow.modelData.when; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                                        Text { visible: crow.modelData.refs !== ""; text: crow.modelData.refs.replace(/HEAD -> /, "● "); color: Theme.green; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                                    }
                                }
                                MouseArea {
                                    id: cma
                                    anchors.fill: parent; hoverEnabled: true
                                    onClicked: mouse => gcl.togglePick(crow.modelData.hash, (mouse.modifiers & Qt.ControlModifier) !== 0)
                                    onDoubleClicked: gcl.act("Ausgecheckt (losgelöst)", ["checkout", crow.modelData.hash])
                                }
                            }
                        }
                    }
                }

                // ================= Branches =================
                Rectangle {
                    id: branchesTab
                    visible: gcl.tab === "branches"
                    anchors.top: tabs.bottom; anchors.topMargin: 8
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    radius: 14; color: Theme.tile
            // ---- Seitenleiste: Branches ----
                Text { id: sideTitle; x: 14; y: 10; text: "Branches"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs; font.weight: Font.DemiBold }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 8; y: 4; spacing: 4
                    BarButton { minWidth: 28; implicitHeight: 26; radiusSize: 13; color: hovered ? Theme.accentHover : "transparent"
                        Icon { name: "add"; size: 13 }
                        onClicked: { newBranchRow.visible = !newBranchRow.visible; if (newBranchRow.visible) newBranchInput.forceActiveFocus(); } }
                }
                Rectangle {
                    id: newBranchRow
                    visible: false
                    anchors.top: sideTitle.bottom; anchors.topMargin: 6
                    anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 8; anchors.rightMargin: 8
                    height: 32; radius: 16; color: Theme.bg2
                    border.color: newBranchInput.activeFocus ? Theme.accent : Theme.borderSoft
                    TextInput {
                        id: newBranchInput
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; verticalAlignment: Text.AlignVCenter
                        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS; clip: true
                        Keys.onEscapePressed: { newBranchRow.visible = false; text = ""; }
                        Keys.onReturnPressed: {
                            const n = text.trim().replace(/\s+/g, "-");
                            if (n === "") return;
                            const from = gcl.lastPicked !== "" && gcl.tab === "history" ? [gcl.lastPicked] : [];
                            gcl.act("Branch angelegt", ["checkout", "-b", n].concat(from));
                            text = ""; newBranchRow.visible = false;
                        }
                        Text { visible: parent.text === ""; text: gcl.tab === "history" && gcl.lastPicked !== "" ? "Neuer Branch ab Commit …" : "Neuer Branch …"; color: Theme.textDim; font: parent.font }
                    }
                }
                ListView {
                    id: branchList
                    anchors.top: newBranchRow.visible ? newBranchRow.bottom : sideTitle.bottom
                    anchors.topMargin: 6
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 6
                    clip: true; spacing: 1
                    boundsBehavior: Flickable.StopAtBounds
                    model: gcl.branches
                    delegate: Rectangle {
                        id: brow
                        required property var modelData
                        width: ListView.view.width; height: 32; radius: 9
                        readonly property bool viewing: gcl.viewRef === modelData.name
                        color: viewing ? Theme.accentSoft : (bma.containsMouse ? Theme.tileHover : "transparent")
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                            Text { text: brow.modelData.current ? "●" : (brow.modelData.remote ? "☁" : "○"); color: brow.modelData.current ? Theme.green : Theme.textDim; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                width: 380
                                text: brow.modelData.name + (brow.modelData.gone ? "  (weg)" : "")
                                elide: Text.ElideRight
                                color: brow.modelData.gone ? Theme.red : Theme.text
                                font.family: Theme.font; font.pixelSize: Theme.fsS; font.weight: brow.modelData.current ? Font.DemiBold : Font.Normal
                            }
                        }
                        MouseArea {
                            id: bma
                            anchors.fill: parent; hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) { gcl.branchMenu = { b: brow.modelData, y: brow.y + mouse.y }; return; }
                                gcl.viewRef = brow.modelData.name; gcl.tab = "history"; gcl.picked = ({}); gcl.loadLog();
                            }
                            onDoubleClicked: gcl.checkoutBranch(brow.modelData)
                        }
                    }
                }
                }
            }
        }

        // ===== Branch-Kontextmenü =====
        MouseArea { anchors.fill: parent; visible: gcl.branchMenu !== null; z: 20; onClicked: gcl.branchMenu = null }
        Surface {
            visible: gcl.branchMenu !== null
            z: 21; level: 3; radius: Theme.rM
            x: 16 + 20; y: Math.min(head.height + 40 + (gcl.branchMenu ? gcl.branchMenu.y : 0), parent.height - height - 20)
            width: 230; height: bmCol.implicitHeight + 12
            Column {
                id: bmCol
                anchors.fill: parent; anchors.margins: 6; spacing: 2
                Repeater {
                    model: gcl.branchMenu ? [
                        { t: "Auschecken", a: "co" },
                        { t: "In '" + gcl.branch + "' mergen", a: "merge" },
                        { t: "'" + gcl.branch + "' darauf rebasen", a: "rebase" },
                        { t: "Verlauf anzeigen", a: "view" },
                        { t: "Löschen", a: "del" }
                    ] : []
                    MenuRow {
                        required property var modelData
                        width: bmCol.width
                        label: modelData.t
                        onTriggered: {
                            const b = gcl.branchMenu.b; gcl.branchMenu = null;
                            if (modelData.a === "co") gcl.checkoutBranch(b);
                            else if (modelData.a === "merge") gcl.act("Merge", ["merge", b.name]);
                            else if (modelData.a === "rebase") gcl.act("Rebase", ["rebase", b.name]);
                            else if (modelData.a === "view") { gcl.viewRef = b.name; gcl.tab = "history"; gcl.loadLog(); }
                            else if (modelData.a === "del") gcl.act("Branch gelöscht", b.remote ? ["push", "origin", "--delete", b.name.replace(/^[^/]+\//, "")] : ["branch", "-D", b.name]);
                        }
                    }
                }
            }
        }

        // ===== Protokoll =====
        Rectangle {
            id: logBox
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.bottomMargin: 14
            height: 112; radius: 12; color: Theme.bg0
            visible: gcl.isRepo
            Flickable {
                id: logFlick
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: claudeRow.top
                anchors.margins: 8
                contentHeight: logTxt.implicitHeight; clip: true
                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                Text { id: logTxt; width: logFlick.width; wrapMode: Text.Wrap
                    text: gcl.busy ? gcl.logText + "\n…" : (gcl.logText !== "" ? gcl.logText : "Bereit")
                    color: gcl.logText.indexOf("✗") >= 0 ? Theme.red : Theme.textDim
                    font.family: Theme.fontMono; font.pixelSize: 11 }
            }
            Rectangle {
                id: claudeRow
                visible: Global.claudeAvailable
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: Global.claudeAvailable ? 6 : 0; height: Global.claudeAvailable ? 32 : 0; radius: 16
                color: Theme.tile; border.color: claudeIn.activeFocus ? Theme.accent : Theme.borderSoft
                Image { id: cIcon2; source: "file://" + Theme.iconDir + "claude-logo.svg"; sourceSize: Qt.size(32, 32); width: 16; height: 16
                        anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; opacity: gcl.claudeBusy ? 0.5 : 1 }
                TextInput {
                    id: claudeIn
                    anchors.left: cIcon2.right; anchors.leftMargin: 8; anchors.right: fixBtn2.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; selectionColor: Theme.accent; clip: true
                    font.family: Theme.font; font.pixelSize: Theme.fsS
                    enabled: !gcl.claudeBusy
                    Keys.onReturnPressed: { gcl.claudeDo(text); text = ""; }
                    Text { visible: claudeIn.text === ""; color: Theme.textDim; font: claudeIn.font
                           text: gcl.claudeBusy ? gcl.claudeStatus : "Claude soll git machen … (z. B. „Pull-Konflikt lösen“)" }
                }
                BarButton {
                    id: fixBtn2
                    anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: 24; padding: 12; radiusSize: 12
                    color: gcl.logText.indexOf("✗") >= 0 || gcl.op !== "" ? (hovered ? Theme.accentBright : Theme.accent) : (hovered ? Theme.accentHover : Theme.tile)
                    Text { text: "Problem fixen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
                    onClicked: gcl.claudeFixLast()
                }
            }
        }
    }

    // Diff-/Detail-Feld hängt rechts am Git-Feld und klappt nur bei Auswahl auf
    Surface {
        id: diffPanel
        visible: gcl.diffOpen
        anchors.top: parent.top; anchors.bottom: parent.bottom
        x: gcl.mainW + 6
        width: gcl.diffW
        level: 2
        radius: Theme.rXl
        DiffView {
            anchors.fill: parent; anchors.margins: 10
            showCommitButton: gcl.tab === "history"
        }
    }

    property var branchMenu: null
    property string dragOver: ""

    // ---------------- Wiederverwendbare Teile ----------------
    // Dateizeile (Klick = Diff, Pfeil/Ziehen = stagen/entfernen, Papierkorb = verwerfen)
    component FileRow: Rectangle {
        id: fr
        required property var modelData
        required property int index
        property bool staged: false
        height: 30; radius: 8
        readonly property bool sel: gcl.selFile === modelData.path && gcl.selStaged === staged
        color: sel ? Theme.accentSoft : (fma.containsMouse ? Theme.tileHover : "transparent")
        Row {
            anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            Text {
                width: 14; horizontalAlignment: Text.AlignHCenter
                text: fr.modelData.kind === "?" ? "U" : fr.modelData.kind
                color: fr.modelData.kind === "D" ? gcl.delColor : (fr.modelData.kind === "M" ? Theme.amber : gcl.addColor)
                font.family: Theme.fontMono; font.pixelSize: 12; font.weight: Font.Bold
            }
            Text { width: 380; elide: Text.ElideMiddle; text: fr.modelData.path; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsS }
        }
        MouseArea {
            id: fma
            anchors.fill: parent; hoverEnabled: true
            property point grab
            property bool moved: false
            onPressed: mouse => { grab = Qt.point(mouse.x, mouse.y); moved = false; }
            onPositionChanged: mouse => {
                if (!(pressedButtons & Qt.LeftButton)) return;
                if (!moved && Math.abs(mouse.x - grab.x) + Math.abs(mouse.y - grab.y) > 8) { moved = true; gcl.dragFile = fr.modelData.path; }
                if (moved) {
                    const p = fma.mapToItem(changes, mouse.x, mouse.y);
                    gcl.dragPos = p;
                    const inUn = p.x >= unBox.x && p.x <= unBox.x + unBox.width && p.y >= unBox.y && p.y <= unBox.y + unBox.height;
                    const inSt = p.x >= stBox.x && p.x <= stBox.x + stBox.width && p.y >= stBox.y && p.y <= stBox.y + stBox.height;
                    gcl.dragOver = inUn ? "un" : (inSt ? "st" : "");
                }
            }
            onReleased: mouse => {
                if (!moved) return;
                const target = gcl.dragOver;
                gcl.dragFile = ""; gcl.dragOver = "";
                if (target === "st" && !fr.staged) gcl.stage([fr.modelData.path]);
                else if (target === "un" && fr.staged) gcl.unstage([fr.modelData.path]);
            }
            onClicked: gcl.showDiff(fr.modelData.path, fr.staged)
            onDoubleClicked: { if (fr.staged) gcl.unstage([fr.modelData.path]); else gcl.stage([fr.modelData.path]); }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 2
            visible: fma.containsMouse || discardBtn.hovered || moveBtn.hovered
            BarButton {
                id: discardBtn
                visible: !fr.staged
                minWidth: 26; implicitHeight: 24; radiusSize: 12
                color: gcl.confirm === "discard:" + fr.modelData.path ? Qt.rgba(1, 0.42, 0.42, 0.45) : (hovered ? Qt.rgba(1, 0.42, 0.42, 0.25) : "transparent")
                Text { text: gcl.confirm === "discard:" + fr.modelData.path ? "?" : "✕"; color: gcl.delColor; font.pixelSize: 12 }
                onClicked: { if (gcl.confirm === "discard:" + fr.modelData.path) gcl.discard(fr.modelData); else gcl.confirm = "discard:" + fr.modelData.path; }
            }
            BarButton {
                id: moveBtn
                minWidth: 26; implicitHeight: 24; radiusSize: 12
                color: hovered ? Theme.accentHover : "transparent"
                Text { text: fr.staged ? "‹" : "›"; color: Theme.text; font.pixelSize: 16 }
                onClicked: { if (fr.staged) gcl.unstage([fr.modelData.path]); else gcl.stage([fr.modelData.path]); }
            }
        }
    }

    // Diff/Detail-Anzeige
    component DiffView: Rectangle {
        property bool showCommitButton: false
        radius: 14; color: Theme.bg0
        Text { x: 14; y: 8; width: parent.width - 200; elide: Text.ElideMiddle; text: gcl.detailTitle !== "" ? gcl.detailTitle : "Keine Auswahl"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fsXs }
        BarButton {
            anchors.right: parent.right; anchors.rightMargin: 6; y: 3
            minWidth: 24; implicitHeight: 24; radiusSize: 12; color: hovered ? Qt.rgba(1, 0.42, 0.42, 0.25) : Theme.tile
            Icon { name: "close"; size: 11 }
            onClicked: { gcl.detailTitle = ""; gcl.diffLines = []; gcl.selFile = ""; }
        }
        BarButton {
            visible: parent.showCommitButton && gcl.lastPicked !== ""
            anchors.right: parent.right; anchors.rightMargin: 38; y: 3
            implicitHeight: 24; padding: 10; radiusSize: 12; color: hovered ? Theme.accentHover : Theme.tile
            Text { text: "Änderungen anzeigen"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fsXs }
            onClicked: gcl.showCommitDiff(gcl.lastPicked)
        }
        ListView {
            anchors.fill: parent; anchors.topMargin: 28; anchors.margins: 8
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: gcl.diffLines
            delegate: Text {
                required property string modelData
                width: ListView.view.width
                text: modelData === "" ? " " : modelData
                color: modelData.startsWith("+") && !modelData.startsWith("+++") ? gcl.addColor
                     : modelData.startsWith("-") && !modelData.startsWith("---") ? gcl.delColor
                     : modelData.startsWith("@@") ? Theme.accentBright : Theme.textDim
                font.family: Theme.fontMono; font.pixelSize: 12
                wrapMode: Text.NoWrap; elide: Text.ElideRight
            }
        }
    }

    property string dragFile: ""
    property point dragPos: Qt.point(0, 0)
    // Zieh-Vorschau über allem
    Rectangle {
        visible: gcl.dragFile !== ""
        parent: changes
        x: gcl.dragPos.x + 12; y: gcl.dragPos.y + 8
        width: dragTxt.implicitWidth + 24; height: 28; radius: 14; color: Theme.accent; z: 50
        Text { id: dragTxt; anchors.centerIn: parent; text: gcl.dragFile; color: "white"; font.family: Theme.font; font.pixelSize: 12 }
    }
}
