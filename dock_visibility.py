"""Visibility policy for Aurora's two dock surfaces; no workspace reservation while adaptive."""
import json,os,signal,time
from pathlib import Path
from gi.repository import GLib


def dock_rect(m):
    scale=m.get('scale') or 1   # 0 würde durch Null teilen
    return (m['x']+18,m['y']+m['height']/scale-78,m['width']/scale-36,60)


def overlaps_dock(w,m):
    if not w.get('mapped') or w.get('hidden') or w.get('monitor')!=m['id']:return False
    ws=w.get('workspace') or {};active=(m.get('activeWorkspace') or {}).get('id')
    if ws.get('id')!=active and not w.get('pinned'):return False
    if ws.get('id',0)<0:return False
    if w.get('fullscreen')==2:return True
    try:x,y=w['at'];width,height=w['size']
    except (KeyError,TypeError,ValueError):return False
    dx,dy,dw,dh=dock_rect(m)
    return width>0 and height>0 and x<dx+dw and x+width>dx and y<dy+dh and y+height>dy


class DockVisibility:
    def __init__(self,ui):
        self.ui=ui;self.visible=True;self.hide_at=None;self.last_pid=None;self.last_sent=None;self.last_scan=0
        self.reveal_at=None;self.mode=None;self.last_error=None
        GLib.timeout_add(125,self.tick)

    def waybar_pid(self,now):
        if now-self.last_scan<1:return self.last_pid
        self.last_scan=now
        try:
            pid=int((Path(os.environ['XDG_RUNTIME_DIR'])/'aurora-waybar.pid').read_text())
            args=(Path('/proc')/str(pid)/'cmdline').read_bytes().split(b'\0')
            if b'waybar' not in args or str(Path.home()/'.config/waybar/config.jsonc').encode() not in args:pid=None
        except (OSError,ValueError):pid=None
        if pid and pid!=self.last_pid:
            # A PID file precedes Waybar's signal handlers during startup. Wait for
            # its mapped panel before sending a signal (default SIGUSR2 terminates).
            try:
                layers=json.loads(self.ui.visibility_ctl('-j','layers'))
                ready=any(layer.get('pid')==pid and layer.get('namespace')=='aurora' for monitor in layers.values() for level in monitor.get('levels',{}).values() for layer in level)
                if not ready:return None
            except (ValueError,OSError):return None
        if pid!=self.last_pid:self.last_sent=None
        self.last_pid=pid;return pid

    def set_visible(self,visible,now):
        ui=self.ui
        if self.visible!=visible:
            self.visible=visible
            if visible:ui.dock.show_all()
            else:ui.dock.hide()
        pid=self.waybar_pid(now)
        if pid and self.last_sent!=visible:
            try:os.kill(pid,signal.SIGUSR2 if visible else signal.SIGUSR1);self.last_sent=visible
            except ProcessLookupError:self.last_pid=None;self.last_sent=None

    def reset(self):
        self.mode=None;self.last_scan=0;self.last_sent=None;self.hide_at=None;self.reveal_at=None

    def tick(self):
        try:
            ui=self.ui;now=time.monotonic();mode=ui.prefs.get('dock_visibility','always')
            if mode not in ('always','dodge','auto'):mode='always'
            if mode!=self.mode:
                self.mode=mode;self.hide_at=None;self.reveal_at=None
                self.set_visible(True,now)
            monitors=getattr(ui,'visibility_monitors',[])
            m=next((m for m in monitors if m.get('name')==ui.prefs.get('dock_monitor')),None)
            if not m:return True
            if mode=='always':self.set_visible(True,now);return True
            # Use the compositor's global logical coordinates, including fractional scaling.
            point=json.loads(ui.visibility_ctl('-j','cursorpos'));px,py=point['x'],point['y']
            scale=m.get('scale') or 1
            width=m['width']/scale;height=m['height']/scale
            edge=m['x']+18<=px<m['x']+width-18 and m['y']+height-3<=py<m['y']+height
            dx,dy,dw,dh=dock_rect(m)
            hover=self.visible and dx<=px<dx+dw and dy<=py<m['y']+height
            busy=bool(ui.dragging_pin or ui.popover or ui.preview_panel or ui.control_panel or ui.popup)
            if edge:
                if self.reveal_at is None:self.reveal_at=now+.12
            else:self.reveal_at=None
            reveal=edge and self.reveal_at is not None and now>=self.reveal_at
            blocked=any(overlaps_dock(w,m) for w in getattr(ui,'visibility_windows',[]))
            want=busy or hover or reveal or (mode=='dodge' and not blocked)
            if want:
                self.hide_at=None;self.set_visible(True,now)
            else:
                if self.hide_at is None:self.hide_at=now+.65
                if now>=self.hide_at:self.set_visible(False,now)
        except Exception as e:
            # A temporary IPC/monitor change must never strand an unreachable dock.
            self.set_visible(True,time.monotonic())
            if str(e)!=self.last_error:self.last_error=str(e);print('Dock visibility:',e,flush=True)   # nicht alle 125 ms dieselbe Zeile
        return True
