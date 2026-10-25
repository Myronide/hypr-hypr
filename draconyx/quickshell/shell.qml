// Draconyx Shell: Taskleiste, Startmenü, Schnelleinstellungen, Kalender
// Start: qs -c draconyx      Steuern: qs -c draconyx ipc call shell <funktion>
import QtQuick
import Quickshell
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
        function toggleCalendar(): void { Global.toggleCalendar(""); }
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
