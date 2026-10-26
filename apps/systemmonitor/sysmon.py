#!/usr/bin/python3
"""Draconyx Systemmonitor: Übersicht, Programme (zusammengefasst), Prozesse, Leistung, Datenträger, Netzwerk, Sensoren, System."""
import math, os, platform, re, shutil, signal, socket, subprocess, sys, time
from collections import deque, defaultdict
from pathlib import Path
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib, Gio, Pango
import cairo
import psutil

HOME = Path.home()
HIST = 90                                    # Messpunkte je Verlauf (bei 1 s = 90 s)


# ---------------------------------------------------------------- Farben
def palette():
    c = {"bg": "#262a30", "surface": "#30353d", "text": "#edf1f7", "muted": "#a6b0be", "accent": "#4d8fe0", "accent_bright": "#6ba9ff"}
    for p in (HOME / ".config/draconyx/colors.json",):
        try:
            import json
            d = json.loads(p.read_text())
            c.update({"bg": d.get("bg", c["bg"]), "surface": d.get("surface", c["surface"]), "text": d.get("text", c["text"]),
                      "muted": d.get("muted", c["muted"]), "accent": d.get("accent", c["accent"]), "accent_bright": d.get("accentBright", c["accent_bright"])})
        except (OSError, ValueError):
            pass
    return c


PAL = palette()


def rgb(hexstr, a=1.0):
    h = hexstr.lstrip("#")
    return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)


CSS = """
* { font-family:"%(font)s","Inter","Sans"; outline-style:none; }
window { background:shade(%(bg)s,0.78); color:%(text)s; }
headerbar { background:shade(%(bg)s,0.78); border:0; box-shadow:none; min-height:52px; }
headerbar .title { font-weight:700; }
.side { background:shade(%(bg)s,0.70); border-right:1px solid alpha(white,0.05); padding:12px 10px; }
.side row { border-radius:10px; padding:9px 12px; margin:1px 0; color:%(muted)s; }
.side row:hover { background:alpha(white,0.05); color:%(text)s; }
.side row:selected { background:alpha(%(accent)s,0.22); color:%(text)s; }
.side-head { color:alpha(%(muted)s,0.8); font-size:10px; font-weight:700; letter-spacing:1.4px; padding:16px 12px 6px 12px; }
.card { background:alpha(white,0.04); border:1px solid alpha(white,0.06); border-radius:18px; padding:18px 20px; }
.card:hover { border-color:alpha(%(accent)s,0.35); }
.big { font-size:34px; font-weight:800; letter-spacing:-0.5px; }
.mid { font-size:18px; font-weight:700; }
.title-sm { font-size:11px; font-weight:700; letter-spacing:1.3px; color:%(muted)s; }
.muted { color:%(muted)s; font-size:12px; }
.page-title { font-size:26px; font-weight:800; letter-spacing:-0.3px; }
button { background:alpha(white,0.07); border:1px solid alpha(white,0.08); border-radius:10px; padding:6px 14px; color:%(text)s; box-shadow:none; text-shadow:none; }
button:hover { background:alpha(white,0.12); border-color:alpha(%(accent)s,0.6); }
button.suggested-action { background:%(accent)s; color:white; border-color:%(accent)s; font-weight:700; }
button.danger:hover { background:alpha(#ff6b6b,0.35); border-color:#ff6b6b; }
entry, searchentry { background:alpha(black,0.25); border:1px solid alpha(white,0.08); border-radius:10px; color:%(text)s; min-height:32px; }
treeview { background:transparent; color:%(text)s; }
treeview.view:selected { background:alpha(%(accent)s,0.28); color:%(text)s; }
treeview header button { background:alpha(white,0.04); border:0; border-radius:0; padding:8px 10px; font-weight:700; font-size:11px; color:%(muted)s; }
scrollbar slider { background:alpha(white,0.2); border-radius:99px; min-width:6px; }
progressbar trough { background:alpha(white,0.09); border-radius:99px; min-height:8px; }
progressbar progress { background:%(accent)s; border-radius:99px; min-height:8px; }
progressbar.warn progress { background:#ffc857; } progressbar.crit progress { background:#ff6b6b; }
""" % {**PAL, "font": "Inter"}


# ---------------------------------------------------------------- Hilfsfunktionen
def human(n, unit="B"):
    n = float(n)
    for u in ("", "K", "M", "G", "T"):
        if abs(n) < 1024:
            return ("%.0f %s%s" % (n, u, unit)) if u == "" or n >= 100 else ("%.1f %s%s" % (n, u, unit))
        n /= 1024
    return "%.1f P%s" % (n, unit)


def rate(n):
    return human(n) + "/s"


def label(text="", css="", xalign=0.0, wrap=False):
    l = Gtk.Label(label=text, xalign=xalign)
    if css:
        for c in css.split():
            l.get_style_context().add_class(c)
    if wrap:
        l.set_line_wrap(True)
    return l


class Series:
    def __init__(self, n=HIST):
        self.v = deque([0.0] * n, maxlen=n)

    def push(self, x):
        self.v.append(float(x))


class Graph(Gtk.DrawingArea):
    """Flächenverlauf mit Verlauf-Füllung. series: Liste von (Series, (r,g,b)); maximum: feste Obergrenze oder None = automatisch."""
    def __init__(self, series, maximum=100.0, height=70, grid=True):
        super().__init__()
        self.series, self.maximum, self.grid = series, maximum, grid
        self.set_size_request(120, height)
        self.set_hexpand(True)
        self.connect("draw", self.on_draw)

    def on_draw(self, w, cr):
        W, H = w.get_allocated_width(), w.get_allocated_height()
        mx = self.maximum or max(1e-6, max((max(s.v) for s, _ in self.series), default=1) * 1.15)
        if self.grid:
            cr.set_line_width(1)
            for i in range(1, 4):
                y = H * i / 4
                cr.set_source_rgba(1, 1, 1, 0.05); cr.move_to(0, y); cr.line_to(W, y); cr.stroke()
        for s, col in self.series:
            pts = list(s.v); n = len(pts)
            if n < 2:
                continue
            xs = [W * i / (n - 1) for i in range(n)]
            ys = [H - 2 - (H - 6) * min(1.0, v / mx) for v in pts]
            cr.move_to(xs[0], H)
            cr.line_to(xs[0], ys[0])
            for i in range(1, n):          # weiche Kurve
                cx = (xs[i - 1] + xs[i]) / 2
                cr.curve_to(cx, ys[i - 1], cx, ys[i], xs[i], ys[i])
            cr.line_to(xs[-1], H); cr.close_path()
            g = cairo.LinearGradient(0, 0, 0, H)
            g.add_color_stop_rgba(0, col[0], col[1], col[2], 0.38); g.add_color_stop_rgba(1, col[0], col[1], col[2], 0.02)
            cr.set_source(g); cr.fill()
            cr.move_to(xs[0], ys[0])
            for i in range(1, n):
                cx = (xs[i - 1] + xs[i]) / 2
                cr.curve_to(cx, ys[i - 1], cx, ys[i], xs[i], ys[i])
            cr.set_source_rgba(col[0], col[1], col[2], 1); cr.set_line_width(2); cr.stroke()
        return False


class Ring(Gtk.DrawingArea):
    """Ringanzeige 0..100 mit Zahl in der Mitte."""
    def __init__(self, size=96):
        super().__init__()
        self.value, self.text, self.size = 0.0, "", size
        self.set_size_request(size, size)
        self.connect("draw", self.on_draw)

    def set(self, v, text):
        self.value, self.text = v, text
        self.queue_draw()

    def on_draw(self, w, cr):
        W, H = w.get_allocated_width(), w.get_allocated_height()
        r = min(W, H) / 2 - 8
        cx, cy = W / 2, H / 2
        cr.set_line_width(9); cr.set_line_cap(cairo.LINE_CAP_ROUND)
        cr.set_source_rgba(1, 1, 1, 0.09); cr.arc(cx, cy, r, 0, 2 * math.pi); cr.stroke()
        v = max(0.0, min(100.0, self.value))
        col = rgb(PAL["accent"]) if v < 70 else ((1, 0.78, 0.34, 1) if v < 90 else (1, 0.42, 0.42, 1))
        if v > 0.5:
            cr.set_source_rgba(*col); cr.arc(cx, cy, r, -math.pi / 2, -math.pi / 2 + 2 * math.pi * v / 100); cr.stroke()
        cr.set_source_rgba(*rgb(PAL["text"]))
        cr.select_font_face("Inter", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(self.size / 4.2)
        e = cr.text_extents(self.text)
        cr.move_to(cx - e.width / 2 - e.x_bearing, cy - e.height / 2 - e.y_bearing); cr.show_text(self.text)
        return False


def bar(value=0.0):
    b = Gtk.ProgressBar(); b.set_fraction(value)
    return b


def set_bar(b, frac):
    b.set_fraction(max(0.0, min(1.0, frac)))
    sc = b.get_style_context()
    sc.remove_class("warn"); sc.remove_class("crit")
    if frac >= 0.9: sc.add_class("crit")
    elif frac >= 0.7: sc.add_class("warn")


# ---------------------------------------------------------------- Messung
class Stats:
    def __init__(self):
        self.cpu = Series(); self.mem = Series(); self.swap = Series()
        self.net_dn = Series(); self.net_up = Series(); self.dsk_r = Series(); self.dsk_w = Series(); self.gpu = Series(); self.vram = Series()
        self.cores = psutil.cpu_count(logical=True)
        self.per_cpu = [0.0] * self.cores
        self.cpu_total = 0.0
        self._net = psutil.net_io_counters(); self._dsk = psutil.disk_io_counters(); self._t = time.time()
        self.net_rate = (0, 0); self.dsk_rate = (0, 0)
        self.gpu_info = None
        self.temp = None
        psutil.cpu_percent(None, percpu=True)
        self.apps = []
        self.app_info = AppInfo()

    def tick(self):
        now = time.time(); dt = max(0.2, now - self._t); self._t = now
        self.per_cpu = psutil.cpu_percent(None, percpu=True)
        self.cpu_total = sum(self.per_cpu) / max(1, len(self.per_cpu))
        self.cpu.push(self.cpu_total)
        vm = psutil.virtual_memory(); sw = psutil.swap_memory()
        self.vm, self.sw = vm, sw
        self.mem.push(vm.percent); self.swap.push(sw.percent)
        n = psutil.net_io_counters()
        self.net_rate = ((n.bytes_recv - self._net.bytes_recv) / dt, (n.bytes_sent - self._net.bytes_sent) / dt); self._net = n
        self.net_dn.push(self.net_rate[0]); self.net_up.push(self.net_rate[1])
        d = psutil.disk_io_counters()
        if d and self._dsk:
            self.dsk_rate = ((d.read_bytes - self._dsk.read_bytes) / dt, (d.write_bytes - self._dsk.write_bytes) / dt)
        self._dsk = d
        self.dsk_r.push(self.dsk_rate[0]); self.dsk_w.push(self.dsk_rate[1])
        self.temp = cpu_temp()
        self.gpu_info = gpu_read()
        if self.gpu_info:
            self.gpu.push(self.gpu_info.get("util", 0)); self.vram.push(self.gpu_info.get("vram_pct", 0))


def cpu_temp():
    try:
        t = psutil.sensors_temperatures()
    except (AttributeError, OSError):
        return None
    for key in ("k10temp", "coretemp", "zenpower", "cpu_thermal", "acpitz"):
        if key in t and t[key]:
            vals = [x.current for x in t[key] if x.current]
            if vals:
                return max(vals)
    return None


_gpu_cache = {"t": 0, "v": None}


def gpu_read():
    if time.time() - _gpu_cache["t"] < 1.5:
        return _gpu_cache["v"]
    _gpu_cache["t"] = time.time()
    info = None
    try:
        for card in sorted(Path("/sys/class/drm").glob("card[0-9]")):
            dev = card / "device"
            if (dev / "gpu_busy_percent").exists():
                util = float((dev / "gpu_busy_percent").read_text())
                used = int((dev / "mem_info_vram_used").read_text()) if (dev / "mem_info_vram_used").exists() else 0
                tot = int((dev / "mem_info_vram_total").read_text()) if (dev / "mem_info_vram_total").exists() else 0
                temp = None
                for h in dev.glob("hwmon/hwmon*/temp1_input"):
                    temp = int(h.read_text()) / 1000
                name = "AMD Radeon"
                try:
                    name = (dev / "product_name").read_text().strip()
                except OSError:
                    pass
                info = {"name": name, "util": util, "vram_used": used, "vram_total": tot, "vram_pct": 100 * used / tot if tot else 0, "temp": temp}
                break
    except (OSError, ValueError):
        info = None
    if info is None and shutil.which("nvidia-smi"):
        try:
            out = subprocess.run(["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits"],
                                 capture_output=True, text=True, timeout=3).stdout.strip().splitlines()[0].split(", ")
            used, tot = float(out[2]) * 1048576, float(out[3]) * 1048576
            info = {"name": out[0], "util": float(out[1]), "vram_used": used, "vram_total": tot, "vram_pct": 100 * used / tot if tot else 0, "temp": float(out[4])}
        except (OSError, ValueError, IndexError, subprocess.SubprocessError):
            info = None
    _gpu_cache["v"] = info
    return info


# ---------------------------------------------------------------- Programme (Prozesse zu Apps zusammenfassen)
ALIASES = {"steamwebhelper": "steam", "steam-runtime-launcher-service": "steam", "pipewire-pulse": "pipewire", "wireplumber": "pipewire",
           "kwin_wayland": "kwin", "plasmashell": "plasma", "Hyprland": "hyprland", ".Hyprland-wrapped": "hyprland", "qs": "quickshell",
           "gjs": "gjs", "code": "code", "chrome": "chrome", "firefox-bin": "firefox", "Isolated Web Co": "firefox", "WebExtensions": "firefox",
           "Web Content": "firefox", "RDD Process": "firefox", "Socket Process": "firefox", "Privileged Cont": "firefox", "Utility Process": "firefox"}


class AppInfo:
    """Programmname und Symbol aus den Desktop-Einträgen (Programm-Dateiname -> Anzeigename)."""
    def __init__(self):
        self.by_exec = {}
        self.cache = {}
        for a in Gio.AppInfo.get_all():
            try:
                cmd = a.get_commandline() or ""
            except Exception:
                continue
            m = re.match(r"\s*(?:env\s+\S+=\S+\s+)*(\S+)", cmd)
            if m:
                self.by_exec.setdefault(os.path.basename(m.group(1)).lower(), a)
            wm = a.get_string("StartupWMClass") if hasattr(a, "get_string") else None
            if wm:
                self.by_exec.setdefault(wm.lower(), a)

    def lookup(self, key):
        if key in self.cache:
            return self.cache[key]
        a = self.by_exec.get(key.lower())
        res = (a.get_display_name(), a.get_icon()) if a else (key, None)
        self.cache[key] = res
        return res


def app_key(p):
    try:
        name = p.name()
        exe = os.path.basename(p.exe() or "") or name
    except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
        return None
    base = name
    if name in ("python", "python3", "node", "bash", "sh", "java", "electron"):    # Interpreter: nach dem Skript/Programm benennen
        try:
            cl = p.cmdline()
            for part in cl[1:]:
                if not part.startswith("-"):
                    base = os.path.basename(part); break
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    elif len(name) >= 15 and exe.lower().startswith(name.lower()[:14]):            # Kernel kürzt Namen auf 15 Zeichen
        base = exe
    return ALIASES.get(base, base)


def gather(app_info):
    procs = []
    for p in psutil.process_iter(["pid", "name", "username", "cpu_percent", "memory_info", "num_threads", "status", "ppid", "create_time"]):
        try:
            i = p.info
            if i["pid"] == 0:
                continue
            procs.append((p, i))
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    groups = defaultdict(lambda: {"cpu": 0.0, "mem": 0, "n": 0, "pids": [], "threads": 0})
    for p, i in procs:
        k = app_key(p)
        if not k:
            continue
        g = groups[k]
        g["cpu"] += i["cpu_percent"] or 0.0
        g["mem"] += (i["memory_info"].rss if i["memory_info"] else 0)
        g["n"] += 1; g["pids"].append(i["pid"]); g["threads"] += i["num_threads"] or 0
    out = []
    for k, g in groups.items():
        disp, icon = app_info.lookup(k)
        out.append({"key": k, "name": disp, "icon": icon, **g})
    return procs, out


# ---------------------------------------------------------------- Seiten
class Page(Gtk.ScrolledWindow):
    def __init__(self, title, sub=""):
        super().__init__()
        self.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=28)
        self.box.pack_start(label(title, "page-title"), False, False, 0)
        if sub:
            self.box.pack_start(label(sub, "muted", wrap=True), False, False, 0)
        self.add(self.box)

    def update(self, s):
        pass


def card(title=""):
    f = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    f.get_style_context().add_class("card")
    if title:
        f.pack_start(label(title.upper(), "title-sm"), False, False, 0)
    return f


class Overview(Page):
    def __init__(self, s):
        super().__init__("Übersicht", "Der Zustand deines Rechners auf einen Blick.")
        grid = Gtk.Grid(column_spacing=14, row_spacing=14, column_homogeneous=True)
        self.box.pack_start(grid, False, False, 0)
        self.cards = {}
        self.col = 0
        def add(key, title, row, col, w=1):
            c = card(title); grid.attach(c, col, row, w, 1); self.cards[key] = c; return c
        # Prozessor
        c = add("cpu", "Prozessor", 0, 0)
        top = Gtk.Box(spacing=14); self.cpu_ring = Ring(92); top.pack_start(self.cpu_ring, False, False, 0)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2); self.cpu_l1 = label("", "mid"); self.cpu_l2 = label("", "muted"); self.cpu_l3 = label("", "muted")
        for x in (self.cpu_l1, self.cpu_l2, self.cpu_l3): v.pack_start(x, False, False, 0)
        top.pack_start(v, True, True, 0); c.pack_start(top, False, False, 0)
        self.cpu_g = Graph([(s.cpu, rgb(PAL["accent"])[:3])]); c.pack_start(self.cpu_g, False, False, 0)
        # Speicher
        c = add("mem", "Arbeitsspeicher", 0, 1)
        top = Gtk.Box(spacing=14); self.mem_ring = Ring(92); top.pack_start(self.mem_ring, False, False, 0)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2); self.mem_l1 = label("", "mid"); self.mem_l2 = label("", "muted"); self.mem_l3 = label("", "muted")
        for x in (self.mem_l1, self.mem_l2, self.mem_l3): v.pack_start(x, False, False, 0)
        top.pack_start(v, True, True, 0); c.pack_start(top, False, False, 0)
        self.mem_g = Graph([(s.mem, (0.42, 0.85, 0.55))]); c.pack_start(self.mem_g, False, False, 0)
        # Grafikkarte
        c = add("gpu", "Grafikkarte", 0, 2)
        top = Gtk.Box(spacing=14); self.gpu_ring = Ring(92); top.pack_start(self.gpu_ring, False, False, 0)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2); self.gpu_l1 = label("", "mid"); self.gpu_l2 = label("", "muted"); self.gpu_l3 = label("", "muted")
        for x in (self.gpu_l1, self.gpu_l2, self.gpu_l3): v.pack_start(x, False, False, 0)
        top.pack_start(v, True, True, 0); c.pack_start(top, False, False, 0)
        self.gpu_g = Graph([(s.gpu, (0.95, 0.6, 0.3))]); c.pack_start(self.gpu_g, False, False, 0)
        # Netzwerk
        c = add("net", "Netzwerk", 1, 0)
        self.net_l1 = label("", "mid"); self.net_l2 = label("", "muted"); c.pack_start(self.net_l1, False, False, 0); c.pack_start(self.net_l2, False, False, 0)
        self.net_g = Graph([(s.net_dn, (0.42, 0.66, 1.0)), (s.net_up, (0.95, 0.5, 0.8))], maximum=None); c.pack_start(self.net_g, False, False, 0)
        # Datenträger
        c = add("dsk", "Datenträger", 1, 1)
        self.dsk_l1 = label("", "mid"); self.dsk_l2 = label("", "muted"); c.pack_start(self.dsk_l1, False, False, 0); c.pack_start(self.dsk_l2, False, False, 0)
        self.dsk_b = bar(); c.pack_start(self.dsk_b, False, False, 0)
        self.dsk_g = Graph([(s.dsk_r, (0.5, 0.85, 0.95)), (s.dsk_w, (1.0, 0.75, 0.35))], maximum=None, height=50); c.pack_start(self.dsk_g, False, False, 0)
        # System
        c = add("sys", "System", 1, 2)
        self.sys_l = [label("", "muted") for _ in range(6)]
        for x in self.sys_l: c.pack_start(x, False, False, 0)
        # Programme-Zusammenfassung
        self.box.pack_start(label("PROGRAMME – WER VERBRAUCHT WAS", "title-sm"), False, False, 6)
        self.apps_row = Gtk.Box(spacing=14, homogeneous=True); self.box.pack_start(self.apps_row, False, False, 0)
        self.cpu_apps = card("Meiste Prozessorlast"); self.mem_apps = card("Meiste Arbeitsspeicher-Belegung")
        self.apps_row.pack_start(self.cpu_apps, True, True, 0); self.apps_row.pack_start(self.mem_apps, True, True, 0)
        self.cpu_rows, self.mem_rows = [], []
        for box, store in ((self.cpu_apps, self.cpu_rows), (self.mem_apps, self.mem_rows)):
            for _ in range(6):
                r = Gtk.Box(spacing=10); img = Gtk.Image(); img.set_pixel_size(28); img.set_size_request(30, 30)
                name = label("", ""); name.set_ellipsize(Pango.EllipsizeMode.END); name.set_max_width_chars(22)
                sub = label("", "muted"); b = bar()
                v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3); head = Gtk.Box(); head.pack_start(name, True, True, 0); head.pack_end(sub, False, False, 0)
                v.pack_start(head, False, False, 0); v.pack_start(b, False, False, 0)
                r.pack_start(img, False, False, 0); r.pack_start(v, True, True, 0); box.pack_start(r, False, False, 4)
                store.append((r, img, name, sub, b))
        self.boot = datetime_boot()
        self.cpu_name = cpu_model()

    def update(self, s):
        self.cpu_ring.set(s.cpu_total, "%d%%" % round(s.cpu_total))
        f = psutil.cpu_freq()
        self.cpu_l1.set_text(self.cpu_name[:30]); self.cpu_l2.set_text("%d Kerne / %d Threads" % (psutil.cpu_count(logical=False) or s.cores, s.cores))
        self.cpu_l3.set_text(("%.2f GHz" % (f.current / 1000) if f else "") + (" · %.0f °C" % s.temp if s.temp else ""))
        vm, sw = s.vm, s.sw
        self.mem_ring.set(vm.percent, "%d%%" % round(vm.percent))
        self.mem_l1.set_text("%s von %s" % (human(vm.used), human(vm.total))); self.mem_l2.set_text("verfügbar: " + human(vm.available))
        self.mem_l3.set_text("Auslagerung: %s von %s" % (human(sw.used), human(sw.total)) if sw.total else "keine Auslagerung")
        g = s.gpu_info
        if g:
            self.gpu_ring.set(g["util"], "%d%%" % round(g["util"])); self.gpu_l1.set_text(g["name"][:30])
            self.gpu_l2.set_text("Videospeicher %s / %s" % (human(g["vram_used"]), human(g["vram_total"])) if g["vram_total"] else "")
            self.gpu_l3.set_text("%.0f °C" % g["temp"] if g.get("temp") else "")
        else:
            self.gpu_ring.set(0, "–"); self.gpu_l1.set_text("Keine Daten"); self.gpu_l2.set_text("Auslastung nur für AMD und NVIDIA"); self.gpu_l3.set_text("")
        self.net_l1.set_text("↓ %s    ↑ %s" % (rate(s.net_rate[0]), rate(s.net_rate[1])))
        n = s._net; self.net_l2.set_text("seit dem Start: ↓ %s  ↑ %s" % (human(n.bytes_recv), human(n.bytes_sent)))
        try:
            du = psutil.disk_usage("/"); self.dsk_l1.set_text("%s von %s belegt" % (human(du.used), human(du.total))); set_bar(self.dsk_b, du.percent / 100)
        except OSError:
            pass
        self.dsk_l2.set_text("lesen %s · schreiben %s" % (rate(s.dsk_rate[0]), rate(s.dsk_rate[1])))
        up = time.time() - psutil.boot_time(); d, rem = divmod(int(up), 86400); h, rem = divmod(rem, 3600)
        la = os.getloadavg()
        vals = ["Läuft seit " + ("%d Tg " % d if d else "") + "%d Std %d Min" % (h, rem // 60), "Last: %.2f  %.2f  %.2f" % la,
                "%s %s" % (platform.system(), platform.release().split("-")[0]), socket.gethostname(), "Prozesse: %d" % len(psutil.pids()),
                "Angemeldet: " + ", ".join(sorted({u.name for u in psutil.users()})) if psutil.users() else ""]
        for l, v in zip(self.sys_l, vals): l.set_text(v)
        apps = s.apps
        for rows, key, fmt, top in ((self.cpu_rows, "cpu", lambda a: "%.1f %%" % a["cpu"], max(1.0, max((a["cpu"] for a in apps), default=1))),
                                    (self.mem_rows, "mem", lambda a: human(a["mem"]), max(1.0, max((a["mem"] for a in apps), default=1)))):
            ordered = sorted(apps, key=lambda a: -a[key])[:6]
            for (r, img, name, sub, b), a in zip(rows, ordered + [None] * (6 - len(ordered))):
                r.set_visible(a is not None)
                if a:
                    name.set_text("%s%s" % (a["name"], " ×%d" % a["n"] if a["n"] > 1 else "")); sub.set_text(fmt(a))
                    if a["icon"]: img.set_from_gicon(a["icon"], Gtk.IconSize.LARGE_TOOLBAR)
                    else: img.set_from_icon_name("application-x-executable", Gtk.IconSize.LARGE_TOOLBAR)
                    b.set_fraction(a[key] / top)


def datetime_boot():
    return psutil.boot_time()


def cpu_model():
    try:
        for l in Path("/proc/cpuinfo").read_text().splitlines():
            if l.startswith("model name"):
                return re.sub(r"\s+", " ", l.split(":", 1)[1]).strip().replace("(R)", "").replace("(TM)", "").replace(" CPU", "")
    except OSError:
        pass
    return platform.processor() or "Prozessor"


class Programs(Page):
    """Zusammengefasste Programme: ein Eintrag je App mit allen ihren Prozessen."""
    def __init__(self, s):
        super().__init__("Programme", "Alle Prozesse eines Programms zusammengefasst – so siehst du, was wirklich Platz und Leistung braucht.")
        bar_ = Gtk.Box(spacing=10); self.q = Gtk.SearchEntry(placeholder_text="Programm suchen …"); self.q.connect("search-changed", lambda *_: self.refilter())
        kill = Gtk.Button(label="Programm beenden"); kill.get_style_context().add_class("danger"); kill.connect("clicked", self.kill_selected)
        bar_.pack_start(self.q, True, True, 0); bar_.pack_end(kill, False, False, 0); self.box.pack_start(bar_, False, False, 0)
        self.store = Gtk.ListStore(object, str, str, float, str, int, str)     # icon, name, cpu-text, cpu, mem-text, n, key
        self.filter = self.store.filter_new(); self.filter.set_visible_func(lambda m, i, d: self.q.get_text().lower() in (m[i][1] or "").lower())
        self.sort = Gtk.TreeModelSort(model=self.filter); self.sort.set_sort_column_id(3, Gtk.SortType.DESCENDING)
        tv = Gtk.TreeView(model=self.sort); tv.set_headers_visible(True)
        col = Gtk.TreeViewColumn("Programm"); ir = Gtk.CellRendererPixbuf(); ir.set_property("stock-size", Gtk.IconSize.LARGE_TOOLBAR); tr = Gtk.CellRendererText(); tr.set_property("ellipsize", Pango.EllipsizeMode.END)
        col.pack_start(ir, False); col.pack_start(tr, True); col.add_attribute(ir, "gicon", 0); col.add_attribute(tr, "text", 1); col.set_expand(True); col.set_sort_column_id(1); tv.append_column(col)
        for title, idx, sortc in (("Prozessor", 2, 3), ("Speicher", 4, 4), ("Prozesse", 5, 5)):
            r = Gtk.CellRendererText(); r.set_property("xalign", 1.0); c = Gtk.TreeViewColumn(title, r, text=idx); c.set_sort_column_id(sortc); c.set_min_width(110); tv.append_column(c)
        self.tv = tv; self.mem_sort = {}
        sc = Gtk.ScrolledWindow(); sc.set_min_content_height(480); sc.add(tv); self.box.pack_start(sc, True, True, 0)
        self.rows = {}

    def refilter(self): self.filter.refilter()

    def update(self, s):
        seen = set()
        for a in s.apps:
            seen.add(a["key"]); vals = (a["icon"], a["name"], "%.1f %%" % a["cpu"], a["cpu"], human(a["mem"]), a["n"], a["key"])
            if a["key"] in self.rows:
                it = self.rows[a["key"]]
                for i, v in enumerate(vals): self.store.set_value(it, i, v)
            else:
                self.rows[a["key"]] = self.store.append(list(vals))
        for k in list(self.rows):
            if k not in seen:
                try: self.store.remove(self.rows[k])
                except Exception: pass
                del self.rows[k]

    def kill_selected(self, *_):
        m, it = self.tv.get_selection().get_selected()
        if not it: return
        key = m[it][6]; name = m[it][1]
        d = Gtk.MessageDialog(transient_for=self.get_toplevel(), modal=True, message_type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.YES_NO, text="„%s“ beenden?" % name)
        d.format_secondary_text("Alle Prozesse dieses Programms werden beendet. Nicht gespeicherte Arbeit geht verloren.")
        if d.run() == Gtk.ResponseType.YES:
            for a in self.get_toplevel().stats.apps:
                if a["key"] == key:
                    for pid in a["pids"]:
                        try: os.kill(pid, signal.SIGTERM)
                        except OSError: pass
        d.destroy()


class Processes(Page):
    def __init__(self, s):
        super().__init__("Prozesse", "Jeder einzelne Prozess. Klick auf eine Spalte sortiert.")
        bar_ = Gtk.Box(spacing=10); self.q = Gtk.SearchEntry(placeholder_text="Prozess oder PID suchen …"); self.q.connect("search-changed", lambda *_: self.filter.refilter())
        t = Gtk.Button(label="Beenden"); t.connect("clicked", lambda *_: self.sig(signal.SIGTERM))
        k = Gtk.Button(label="Erzwingen"); k.get_style_context().add_class("danger"); k.connect("clicked", lambda *_: self.sig(signal.SIGKILL))
        bar_.pack_start(self.q, True, True, 0); bar_.pack_end(k, False, False, 0); bar_.pack_end(t, False, False, 0); self.box.pack_start(bar_, False, False, 0)
        self.store = Gtk.ListStore(int, str, str, float, str, int, str, int)          # pid, name, user, cpu, mem-text, threads, status, mem-bytes
        self.filter = self.store.filter_new(); self.filter.set_visible_func(lambda m, i, d: not self.q.get_text() or self.q.get_text().lower() in ("%s %d" % (m[i][1], m[i][0])).lower())
        self.sort = Gtk.TreeModelSort(model=self.filter); self.sort.set_sort_column_id(3, Gtk.SortType.DESCENDING)
        tv = Gtk.TreeView(model=self.sort)
        for title, idx, sortc, align, minw in (("Name", 1, 1, 0.0, 220), ("PID", 0, 0, 1.0, 70), ("Benutzer", 2, 2, 0.0, 100), ("Prozessor", 3, 3, 1.0, 90), ("Speicher", 4, 7, 1.0, 100), ("Threads", 5, 5, 1.0, 70), ("Status", 6, 6, 0.0, 90)):
            r = Gtk.CellRendererText(); r.set_property("xalign", align)
            if idx == 3: c = Gtk.TreeViewColumn(title, r); c.set_cell_data_func(r, lambda col, cell, m, it, d: cell.set_property("text", "%.1f %%" % m[it][3]))
            else: c = Gtk.TreeViewColumn(title, r, text=idx)
            c.set_sort_column_id(sortc); c.set_min_width(minw); c.set_resizable(True); tv.append_column(c)
        self.tv = tv; self.rows = {}
        sc = Gtk.ScrolledWindow(); sc.set_min_content_height(520); sc.add(tv); self.box.pack_start(sc, True, True, 0)

    def update(self, s):
        seen = set()
        for p, i in s.procs:
            pid = i["pid"]; seen.add(pid); mem = i["memory_info"].rss if i["memory_info"] else 0
            vals = [pid, i["name"] or "?", i["username"] or "", i["cpu_percent"] or 0.0, human(mem), i["num_threads"] or 0, i["status"] or "", mem]
            if pid in self.rows:
                it = self.rows[pid]
                for k, v in enumerate(vals): self.store.set_value(it, k, v)
            else: self.rows[pid] = self.store.append(vals)
        for pid in list(self.rows):
            if pid not in seen:
                try: self.store.remove(self.rows[pid])
                except Exception: pass
                del self.rows[pid]

    def sig(self, sg):
        m, it = self.tv.get_selection().get_selected()
        if it:
            try: os.kill(m[it][0], sg)
            except OSError as e: print(e)


class Performance(Page):
    def __init__(self, s):
        super().__init__("Leistung", "Prozessor und Speicher im Detail.")
        c = card("Prozessor – alle Kerne"); self.box.pack_start(c, False, False, 0)
        self.total_g = Graph([(s.cpu, rgb(PAL["accent"])[:3])], height=110); c.pack_start(self.total_g, False, False, 0)
        self.core_bars = []
        grid = Gtk.Grid(column_spacing=16, row_spacing=6, column_homogeneous=True); c.pack_start(grid, False, False, 6)
        for i in range(s.cores):
            b = bar(); l = label("Kern %d" % (i + 1), "muted"); v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            top = Gtk.Box(); lab = label("", "muted"); top.pack_start(l, True, True, 0); top.pack_end(lab, False, False, 0); v.pack_start(top, False, False, 0); v.pack_start(b, False, False, 0)
            grid.attach(v, i % 4, i // 4, 1, 1); self.core_bars.append((b, lab))
        c2 = card("Arbeitsspeicher"); self.box.pack_start(c2, False, False, 0)
        self.mem_g = Graph([(s.mem, (0.42, 0.85, 0.55))], height=90); c2.pack_start(self.mem_g, False, False, 0)
        self.mem_rows = {}
        for k in ("Belegt", "Zwischengespeichert", "Puffer", "Frei", "Auslagerung"):
            row = Gtk.Box(); l = label(k, "muted"); v = label("", ""); row.pack_start(l, True, True, 0); row.pack_end(v, False, False, 0); c2.pack_start(row, False, False, 0); self.mem_rows[k] = v

    def update(self, s):
        fr = psutil.cpu_freq(percpu=True) or []
        for i, ((b, lab), v) in enumerate(zip(self.core_bars, s.per_cpu)):
            set_bar(b, v / 100); lab.set_text("%d%%%s" % (round(v), (" · %.1f GHz" % (fr[i].current / 1000) if i < len(fr) and fr[i].current else "")))
        vm = s.vm; sw = s.sw
        vals = {"Belegt": human(vm.used), "Zwischengespeichert": human(getattr(vm, "cached", 0)), "Puffer": human(getattr(vm, "buffers", 0)),
                "Frei": human(vm.free), "Auslagerung": "%s von %s" % (human(sw.used), human(sw.total))}
        for k, v in vals.items(): self.mem_rows[k].set_text(v)


class Disks(Page):
    def __init__(self, s):
        super().__init__("Datenträger", "Belegung und Geschwindigkeit.")
        c = card("Lesen und Schreiben"); self.box.pack_start(c, False, False, 0)
        self.l = label("", "mid"); c.pack_start(self.l, False, False, 0)
        c.pack_start(Graph([(s.dsk_r, (0.5, 0.85, 0.95)), (s.dsk_w, (1.0, 0.75, 0.35))], maximum=None, height=90), False, False, 0)
        self.parts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10); self.box.pack_start(self.parts, False, False, 0); self.rows = {}; self.t = 0

    def update(self, s):
        self.l.set_text("lesen %s    schreiben %s" % (rate(s.dsk_rate[0]), rate(s.dsk_rate[1])))
        if time.time() - self.t < 5: return
        self.t = time.time()
        for p in psutil.disk_partitions():
            if p.fstype in ("squashfs", "tmpfs", "devtmpfs", "overlay") or p.mountpoint.startswith(("/snap", "/boot/efi", "/var/lib/docker")): continue
            try: u = psutil.disk_usage(p.mountpoint)
            except OSError: continue
            if p.mountpoint not in self.rows:
                c = card(); h = label(p.mountpoint, "mid"); sub = label("", "muted"); b = bar(); c.pack_start(h, False, False, 0); c.pack_start(sub, False, False, 0); c.pack_start(b, False, False, 0)
                self.parts.pack_start(c, False, False, 0); c.show_all(); self.rows[p.mountpoint] = (sub, b)
            sub, b = self.rows[p.mountpoint]; sub.set_text("%s · %s  —  %s von %s belegt (%d %%), frei: %s" % (p.device, p.fstype, human(u.used), human(u.total), u.percent, human(u.free))); set_bar(b, u.percent / 100)


class Network(Page):
    def __init__(self, s):
        super().__init__("Netzwerk", "Geschwindigkeit und Schnittstellen.")
        c = card("Verlauf"); self.box.pack_start(c, False, False, 0)
        self.l = label("", "mid"); c.pack_start(self.l, False, False, 0)
        c.pack_start(Graph([(s.net_dn, (0.42, 0.66, 1.0)), (s.net_up, (0.95, 0.5, 0.8))], maximum=None, height=110), False, False, 0)
        c.pack_start(label("blau = empfangen · rosa = gesendet", "muted"), False, False, 0)
        self.ifs = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10); self.box.pack_start(self.ifs, False, False, 0); self.rows = {}; self.t = 0

    def update(self, s):
        self.l.set_text("↓ %s    ↑ %s" % (rate(s.net_rate[0]), rate(s.net_rate[1])))
        if time.time() - self.t < 3: return
        self.t = time.time()
        stats = psutil.net_if_stats(); addrs = psutil.net_if_addrs(); io = psutil.net_io_counters(pernic=True)
        for name, st in stats.items():
            if name == "lo" or not st.isup: continue
            ips = [a.address for a in addrs.get(name, []) if a.family == socket.AF_INET]
            if name not in self.rows:
                c = card(); h = label(name, "mid"); sub = label("", "muted"); c.pack_start(h, False, False, 0); c.pack_start(sub, False, False, 0)
                self.ifs.pack_start(c, False, False, 0); c.show_all(); self.rows[name] = sub
            n = io.get(name); self.rows[name].set_text("%s · %s Mbit/s · empfangen %s · gesendet %s" % (", ".join(ips) or "keine IPv4", st.speed or "?", human(n.bytes_recv) if n else "–", human(n.bytes_sent) if n else "–"))


class Sensors(Page):
    def __init__(self, s):
        super().__init__("Sensoren", "Temperaturen, Lüfter und Akku, soweit dein Rechner sie meldet.")
        self.c = card(); self.box.pack_start(self.c, False, False, 0); self.rows = {}; self.t = 0

    def update(self, s):
        if time.time() - self.t < 2: return
        self.t = time.time()
        try: temps = psutil.sensors_temperatures()
        except (AttributeError, OSError): temps = {}
        try: fans = psutil.sensors_fans()
        except (AttributeError, OSError): fans = {}
        items = []
        for chip, lst in temps.items():
            for t in lst: items.append(("%s – %s" % (chip, t.label or "Sensor"), "%.0f °C" % t.current))
        for chip, lst in fans.items():
            for f in lst: items.append(("%s – %s" % (chip, f.label or "Lüfter"), "%d U/min" % f.current))
        try:
            bat = psutil.sensors_battery()
            if bat: items.append(("Akku", "%d %% %s" % (bat.percent, "(lädt)" if bat.power_plugged else "")))
        except (AttributeError, OSError): pass
        for k, v in items:
            if k not in self.rows:
                row = Gtk.Box(); l = label(k, "muted"); val = label("", ""); row.pack_start(l, True, True, 0); row.pack_end(val, False, False, 0); self.c.pack_start(row, False, False, 3); row.show_all(); self.rows[k] = val
            self.rows[k].set_text(v)
        if not items and not self.rows: self.c.pack_start(label("Keine Sensoren gefunden.", "muted"), False, False, 0); self.c.show_all()


class SystemInfo(Page):
    def __init__(self, s):
        super().__init__("System", "Steckbrief deines Rechners.")
        c = card(); self.box.pack_start(c, False, False, 0)
        os_name = platform.platform()
        try:
            for l in Path("/etc/os-release").read_text().splitlines():
                if l.startswith("PRETTY_NAME="): os_name = l.split("=", 1)[1].strip('"')
        except OSError: pass
        gpu = (gpu_read() or {}).get("name", "–")
        rows = [("Betriebssystem", os_name), ("Kernel", platform.release()), ("Rechner", socket.gethostname()), ("Prozessor", cpu_model()),
                ("Kerne / Threads", "%s / %s" % (psutil.cpu_count(logical=False), psutil.cpu_count())), ("Arbeitsspeicher", human(psutil.virtual_memory().total)),
                ("Grafikkarte", gpu), ("Desktop", os.environ.get("XDG_CURRENT_DESKTOP", "–")), ("Sitzung", os.environ.get("XDG_SESSION_TYPE", "–")),
                ("Gestartet", time.strftime("%d.%m.%Y %H:%M", time.localtime(psutil.boot_time())))]
        for k, v in rows:
            r = Gtk.Box(); r.pack_start(label(k, "muted"), True, True, 0); r.pack_end(label(v), False, False, 0); c.pack_start(r, False, False, 4)


# ---------------------------------------------------------------- Fenster
class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Systemmonitor")
        self.set_default_size(1180, 800)
        self.stats = Stats(); self.stats.procs = []
        hb = Gtk.HeaderBar(title="Systemmonitor", show_close_button=True); self.set_titlebar(hb)
        body = Gtk.Box(); self.add(body)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=140)
        self.pages = [("Übersicht", Overview(self.stats), "utilities-system-monitor-symbolic"), ("Programme", Programs(self.stats), "view-app-grid-symbolic"),
                      ("Prozesse", Processes(self.stats), "view-list-symbolic"), ("Leistung", Performance(self.stats), "speedometer-symbolic"),
                      ("Datenträger", Disks(self.stats), "drive-harddisk-symbolic"), ("Netzwerk", Network(self.stats), "network-wireless-symbolic"),
                      ("Sensoren", Sensors(self.stats), "temperature-symbolic"), ("System", SystemInfo(self.stats), "computer-symbolic")]
        side = Gtk.ListBox(); side.get_style_context().add_class("side"); side.set_size_request(220, -1)
        sc = Gtk.ScrolledWindow(); sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC); sc.add(side); body.pack_start(sc, False, False, 0); body.pack_start(self.stack, True, True, 0)
        theme = Gtk.IconTheme.get_default(); self.rows = {}
        for title, page, icon in self.pages:
            self.stack.add_named(page, title)
            r = Gtk.ListBoxRow(); r.page = title; bx = Gtk.Box(spacing=12); ic = icon if theme.has_icon(icon) else "applications-system-symbolic"
            bx.pack_start(Gtk.Image.new_from_icon_name(ic, Gtk.IconSize.MENU), False, False, 0); bx.pack_start(Gtk.Label(label=title, xalign=0), True, True, 0); r.add(bx); side.add(r); self.rows[title] = r
        side.connect("row-selected", lambda lb, r: r and self.stack.set_visible_child_name(r.page))
        side.select_row(self.rows["Übersicht"])
        self.show_all()
        self.tick(); GLib.timeout_add(1000, self.tick)

    def tick(self):
        s = self.stats
        s.tick()
        vis = self.stack.get_visible_child_name()
        if vis in ("Übersicht", "Programme", "Prozesse") or int(time.time()) % 3 == 0:     # Prozessliste nur wenn nötig (schont die CPU)
            s.procs, s.apps = gather(s.app_info)
        for title, page, _ in self.pages:
            if title == vis or title == "Übersicht":
                try: page.update(s)
                except Exception as e: print("Fehler in", title, e, file=sys.stderr)
        return True


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.draconyx.Systemmonitor"); self.win = None

    def do_activate(self):
        if self.win: self.win.present(); return
        st = Gtk.Settings.get_default(); st.set_property("gtk-application-prefer-dark-theme", True)
        css = Gtk.CssProvider(); css.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        self.win = Window(self)


if __name__ == "__main__":
    App().run(None)
