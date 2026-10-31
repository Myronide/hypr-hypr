"""Hypr Hypr/Aurora: Bildschirme erkennen, anordnen und in ~/.config/hypr/monitors_local.lua speichern.

Gemeinsam genutzt von der Einstellungs-App (Seite „Bildschirme“) und dem Installer (dx-monitors init).
Reine Logik ohne GTK, damit sie sich ohne Anzeige testen lässt.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CONF = Path.home() / ".config/hypr/monitors_local.lua"
MANAGED = ("output", "mode", "position", "scale", "transform", "disabled")   # alles andere (HDR, vrr …) bleibt unverändert


def _run(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=10).stdout


def _atomic_write(path, text):
    """Temp-Datei im selben Ordner + Ersetzen: nie eine halb geschriebene monitors_local.lua."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix="." + path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def live():
    """Alle Bildschirme (auch ausgeschaltete) aus dem laufenden Hyprland."""
    try:
        data = json.loads(_run(["hyprctl", "monitors", "all", "-j"]))
    except (OSError, ValueError, subprocess.SubprocessError):
        return []
    if not isinstance(data, list):
        return []
    out = []
    for m in data:
        if not isinstance(m, dict) or not isinstance(m.get("name"), str) or not m["name"]:
            continue
        if not re.fullmatch(r"[A-Za-z0-9_.:\-]+", m["name"]):
            continue   # Name kommt in Lua-Text und Hyprland-Befehle: nur harmlose Zeichen
        modes = []
        for s in m.get("availableModes", []):
            g = re.match(r"(\d+)x(\d+)@([\d.]+)Hz", s)
            if g:
                modes.append((int(g[1]), int(g[2]), float(g[3])))
        try:
            scale = round(float(m.get("scale", 1)), 2)
            out.append({
                "name": m["name"], "desc": str(m.get("description", "")).replace("\n", " "), "w": int(m["width"]), "h": int(m["height"]),
                "hz": float(m.get("refreshRate", 60)), "x": int(m["x"]), "y": int(m["y"]), "scale": scale if scale > 0 else 1.0,
                "transform": int(m.get("transform", 0)), "disabled": bool(m.get("disabled", False)), "modes": modes,
            })
        except (KeyError, TypeError, ValueError):
            continue   # unvollständiger Eintrag: überspringen statt abstürzen
    return out


def logical_size(m):
    w, h = m["w"] / (m["scale"] or 1), m["h"] / (m["scale"] or 1)
    return (h, w) if m["transform"] % 2 else (w, h)


# ---------------------------------------------------------------- Anordnen
def _overlap(ax, ay, aw, ah, bx, by, bw, bh):
    return ax < bx + bw - 0.5 and bx < ax + aw - 0.5 and ay < by + bh - 0.5 and by < ay + ah - 0.5


def snap(mons, idx, x, y):
    """Setzt Bildschirm idx möglichst nahe an (x, y), aber bündig an einem anderen und ohne Überlappung."""
    me = mons[idx]
    w, h = logical_size(me)
    others = [(m, *logical_size(m)) for i, m in enumerate(mons) if i != idx and not m["disabled"]]
    if not others:
        return 0, 0
    cands = []
    for o, ow, oh in others:
        ox, oy = o["x"], o["y"]
        ys = [oy, oy + oh - h, oy + (oh - h) / 2, min(max(y, oy - h + 80), oy + oh - 80)]
        xs = [ox, ox + ow - w, ox + (ow - w) / 2, min(max(x, ox - w + 80), ox + ow - 80)]
        for cy in ys:
            cands += [(ox + ow, cy), (ox - w, cy)]            # rechts / links daneben
        for cx in xs:
            cands += [(cx, oy + oh), (cx, oy - h)]            # darunter / darüber
    best, bd = None, None
    for cx, cy in cands:
        if any(_overlap(cx, cy, w, h, o["x"], o["y"], ow, oh) for o, ow, oh in others):
            continue
        d = (cx - x) ** 2 + (cy - y) ** 2
        if bd is None or d < bd:
            best, bd = (cx, cy), d
    if best is None:
        o, ow, oh = others[0]
        best = (o["x"] + ow, o["y"])
    return round(best[0]), round(best[1])


def normalize(mons):
    """Alle Positionen so verschieben, dass links/oben bei 0 beginnt."""
    act = [m for m in mons if not m["disabled"]]
    if not act:
        return
    mx, my = min(m["x"] for m in act), min(m["y"] for m in act)
    for m in act:
        m["x"] -= mx
        m["y"] -= my


# ---------------------------------------------------------------- Konfiguration lesen / schreiben
def parse_config(path=CONF):
    """Vorhandene hl.monitor({...})-Blöcke: Name -> {Schlüssel: Wert-Text}. Wir behalten damit HDR, vrr, bitdepth …"""
    try:
        text = Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    out = {}
    for m in re.finditer(r"hl\.monitor\s*\(\s*\{(.*?)\}\s*\)", text, re.S):
        body = re.sub(r"--[^\n]*", "", m.group(1))
        kv = {k: v.strip() for k, v in re.findall(r'(\w+)\s*=\s*("[^"]*"|[^,\n}]+)', body)}
        name = kv.get("output", "").strip('"')
        if name:
            out[name] = kv
    return out


def lua_block(m, extras=None):
    lines = ['    output   = "%s",' % m["name"]]
    if m["disabled"]:
        lines.append("    disabled = true,")
    else:
        lines.append('    mode     = "%dx%d@%s",' % (m["w"], m["h"], ("%.2f" % m["hz"]).rstrip("0").rstrip(".")))
        lines.append('    position = "%dx%d",' % (m["x"], m["y"]))
        lines.append("    scale    = %s," % ("%g" % m["scale"]))
        if m["transform"]:
            lines.append("    transform = %d," % m["transform"])
    for k, v in (extras or {}).items():
        if k not in MANAGED and not m["disabled"]:
            lines.append("    %s = %s," % (k, v))
    return "-- %s\nhl.monitor({\n%s\n})\n" % (m["desc"] or m["name"], "\n".join(lines))


def write_config(mons, path=CONF):
    """Schreibt monitors_local.lua (alte Datei vorher gesichert). Gibt den Sicherungspfad zurück (oder '')."""
    path = Path(path)
    old = parse_config(path)
    backup = ""
    if path.exists():
        backup = str(path) + ".vor-" + time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(path, backup)
    parts = ["-- Monitore dieses Rechners – geschrieben von Aurora (Einstellungen → Bildschirme). Von Hand änderbar;\n"
             "-- HDR/vrr/bitdepth-Zeilen bleiben beim nächsten Speichern erhalten. Mit `hyprctl reload` sofort sichtbar.\n"]
    for m in mons:
        parts.append(lua_block(m, old.get(m["name"])))
    parts.append('-- Alles andere (z. B. ein neu angeschlossener Monitor): rechts anhängen\n'
                 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })\n')
    _atomic_write(path, "\n".join(parts))
    return backup


def apply_live(mons, extras_from=CONF):
    """Wendet die Anordnung sofort an (ohne zu speichern). True, wenn Hyprland alles angenommen hat."""
    old = parse_config(extras_from)
    ok = True
    for m in mons:
        block = lua_block(m, old.get(m["name"]))
        code = re.sub(r"^--[^\n]*\n", "", block)
        try:
            r = subprocess.run(["hyprctl", "eval", code], capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            return False   # kein hyprctl / Hyprland hängt: nicht weitermachen
        if r.returncode != 0 or ("error" in (r.stdout + r.stderr).lower()):
            ok = False
    return ok


def start_watchdog(prev, marker, delay=22):
    """Sicherheitsnetz für die 15-Sekunden-Rückfrage: ein eigener Prozess stellt die alte Anordnung wieder her, wenn bis
    zum Ablauf keine Marker-Datei existiert – auch wenn die Einstellungs-App währenddessen abstürzt oder beendet wird."""
    code = ("import sys,os,time,json;sys.path.insert(0,%r);import monitors;"
            "time.sleep(%d);\nif not os.path.exists(%r): monitors.apply_live(json.loads(sys.argv[1]))" % (str(Path(__file__).resolve().parent), delay, str(marker)))
    try:
        Path(marker).unlink(missing_ok=True)
        subprocess.Popen([sys.executable, "-c", code, json.dumps(prev)], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except OSError:
        return False


def init_config(path=CONF):
    """Installer: gibt es noch keine monitors_local.lua, aus dem laufenden Zustand eine anlegen (richtige Namen, Modi, Lage)."""
    if Path(path).exists():
        return 0
    mons = live()
    if not mons:
        return 0
    normalize(mons)
    write_config(mons, path)
    return len(mons)


def sync_missing(path=CONF):
    """Vor jedem Neuladen der Hyprland-Konfiguration: Bildschirme, die in monitors_local.lua NICHT ausdrücklich stehen, mit ihrem
    aktuellen Zustand eintragen. Sonst fällt ein Bildschirm, den man von Hand (z. B. per hyprctl oder einem anderen Programm)
    angeordnet hat, nach jedem Neuladen/Update wieder auf die automatische Anordnung zurück. Ausdrücklich eingetragene Bildschirme
    bleiben unverändert (die Datei ist die Wahrheit). Gibt die Zahl der ergänzten Bildschirme zurück."""
    path = Path(path)
    if not path.exists():
        return init_config(path)
    have = parse_config(path)
    mons = [m for m in live() if not m["disabled"] and m["name"] not in have]
    if not mons:
        return 0
    text = path.read_text(encoding="utf-8")
    shutil.copy2(path, str(path) + ".vor-" + time.strftime("%Y%m%d-%H%M%S"))
    new = "\n".join(lua_block(m) for m in mons) + "\n"
    i = re.search(r'^\s*hl\.monitor\s*\(\s*\{\s*output\s*=\s*""', text, re.M)
    text = text[:i.start()] + new + text[i.start():] if i else text.rstrip("\n") + "\n\n" + new
    _atomic_write(path, text)
    return len(mons)


def active_count():
    return len([m for m in live() if not m["disabled"]])
