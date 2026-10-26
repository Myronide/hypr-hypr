// Draconyx Shell: Taskleiste, Startmenü, Schnelleinstellungen, Kalender
// Start: qs -c draconyx      Steuern: qs -c draconyx ipc call shell <funktion>
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    Variants {
        model: Quickshell.screens
        Desktop {}
    }

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    Variants {
        model: Quickshell.screens
        DismissCatcher {}
    }

    Variants {
        model: Quickshell.screens
        SnapPreview {}
    }

    Variants {
        model: Quickshell.screens
        GridEditor {}
    }

    StartMenu {}
    ControlCenter {}
    CalendarPopup {}
    AltTab { id: altTab }
    TaskView {}
    CodeSpace { extraGrab: gitClient }
    WallpaperPicker {}
    SearchOverlay {}
    SnipTool {}
    UpdateProgress {}
    Connectivity {}
    Clipboard {}
    Osd {}
    TitleBars {}
    Shortcuts {}
    SnipEditor { id: snipEditor }
    GitClient { id: gitClient }
    WindowMenu {}

    IpcHandler {
        target: "switcher"
        function next(): void { altTab.next(); }
        function prev(): void { altTab.prev(); }
        function commit(): void { altTab.commit(); }
        function cancel(): void { altTab.cancel(); }
    }

    IpcHandler {
        target: "shell"
        function toggleStart(): void { Global.toggleStart(""); }
        function toggleControl(): void { Global.toggleControl(""); }
        function toggleConn(): void { Global.toggleConn(""); }
        function barItem(key: string, on: bool): void { Global.setItem(key, on); }
        function toggleClip(): void { Global.toggleClip(""); }
        function toggleShortcuts(): void { Global.toggleShortcuts(""); }
        function osd(icon: string, label: string, value: real): void { Global.osdRequest(icon, label, value); }
        function openConn(tab: string): void { Global.openConn(tab, ""); }
        function toggleCalendar(): void { Global.toggleCalendar(""); }
        // Fokus-Zeit: toggle | start | pause | reset | pomodoro | timer | stopwatch | open
        function focusCmd(a: string): void {
            if (a === "toggle") Focus.toggle(); else if (a === "start") Focus.start(); else if (a === "pause") Focus.pause(); else if (a === "reset") Focus.reset();
            else if (a === "pomodoro" || a === "timer" || a === "stopwatch") Focus.setMode(a);
            else if (a === "open") { Global.calTab = "focus"; if (!Global.calendarOpen) Global.toggleCalendar(""); }
        }
        function closeAll(): void { Global.closeAll(); }
        function toggleAutohide(): void { Global.autohide = !Global.autohide; }
        function search(text: string): void { Global.testQuery = text; }
        function desktopSelect(x: int, y: int, w: int, h: int): void { Global.testSelect = (w > 0) ? { x: x, y: y, w: w, h: h } : null; }
        function closeGrid(): void { Global.closeGrid(); }
        function editZones(): void { Global.showZones("", "edit"); }
        function pickZone(): void { Global.showZones("", "pick"); }
        function flashZones(): void { Global.showZones("", "flash"); }
        function cycleZones(): void { Global.cyclePreset(Global.focusedScreenName()); Global.showZones("", "flash"); }
        function windowMenu(addr: string, x: int, y: int): void { Global.closeAll(); Global.winMenu = { addr: addr, x: x, y: y }; }
        function codeEnter(path: string): void { Global.codeEnter(path); }
        function toggleCode(): void { Global.toggleCode(""); }
        function toggleWe(): void { Global.toggleWe(""); }
        function gitShow(path: string, staged: bool): void { gitClient.showDiff(path, staged); }
        function gitView(ref: string): void { gitClient.viewRef = ref; gitClient.tab = "history"; gitClient.loadLog(); }
        function gitClaudeMsg(): void { gitClient.claudeCommitMessage(); }
        function gitClaude(t: string): void { gitClient.claudeDo(t); }
        // Minimieren-Knopf (Plugin/Titelleiste): minimiert oder holt das Fenster zurück
        function toggleMinAddr(addr: string): void {
            const a = addr.startsWith("0x") ? addr : "0x" + addr;
            const bare = a.substring(2).toLowerCase();
            for (const t of Hyprland.toplevels.values) {
                if (String(t.address).toLowerCase().replace(/^0x/, "") === bare) {
                    if (Global.isMinimizedH(t)) Global.restoreAddr(a); else Global.minimizeAddr(a);
                    return;
                }
            }
            Global.minimizeAddr(a);
        }
        function minimizeActive(): void {
            const t = Hyprland.activeToplevel;
            if (t) Global.minimizeAddr("0x" + String(t.address).replace(/^0x/, ""));
        }
        function searchBox(text: string): void { Global.searchTest = text; }
        function editImage(path: string): void { Global.editFile = path; Global.popupScreen = Global.focusedScreenName(); Global.editOpen = true; }
        function editDemo(): void { snipEditor.demo(); }
        function editDeliver(mode: string): void { snipEditor.deliver(mode); }
        function updateCheck(): void { Global.checkUpdate(true); }
        function updateRun(): void { Global.runUpdate(); }
        function snip(mode: string): void { Global.snip(mode); }
        function toggleSearchBox(): void { Global.toggleSearchBox(""); }
        function fullscreenBar(v: string): void { Global.fullscreenBar = v; }
        function barPartHide(v: bool): void { Global.barPartHide = v; }
        function barStyle(v: string): void { Global.barStyle = v; }
        function openSettings(): void { Global.openSettings(); }
        function setStartLogo(v: string): void { Global.startLogo = v; }
        function gitStage(path: string): void { gitClient.stage([path]); }
        function gitCommit(msg: string): void { gitClient.act("Commit", ["commit", "-m", msg]); }
        function gitPick(hash: string): void { gitClient.picked = ({}); gitClient.togglePick(hash, false); gitClient.cherryPick(); }
        function gitFix(): void { if (gitClient.warnings.length > 0) gitClient.fixWarning(gitClient.warnings[0]); }
        function openGit(path: string): void { Global.openGit(path); }
        function codeClone(url: string): void { Global.codeClone(url); }
        function newWorkspace(name: string): void { Global.codeNewWorkspace(name); }
        function weReapply(): void { Global.weApply(); }
        function toggleTaskView(): void { Global.toggleTaskView(""); }
        function focusApp(id: string): void {
            for (const t of ToplevelManager.toplevels.values) if (t.appId === id) { Global.focusToplevel(t); return; }
        }
        function appInfo(id: string): string {
            for (const t of ToplevelManager.toplevels.values) if (t.appId === id)
                return JSON.stringify({ minimized: Global.isMinimized(t), activated: t.activated, ws: Global.wsNameOf(Global.hyprFor(t)) });
            return "keins";
        }
        function setMinHandler(on: bool): void { Global.handleMinimized = on; }
        function minimizeTitle(title: string): void {
            for (const t of ToplevelManager.toplevels.values) if (t.title === title) { t.minimized = true; return; }
        }
        function focusTitle(title: string): void {
            for (const t of ToplevelManager.toplevels.values) if (t.title === title) { Global.focusToplevel(t); return; }
        }
        function minimizeApp(id: string): void {
            for (const t of ToplevelManager.toplevels.values) if (t.appId === id) t.minimized = true;
        }
    }
}
