"""Reine Logik (ohne GTK) für die Seiten Tastatur, Maus & Touchpad und Eingabehilfen.
Wird von den page_*.py-Modulen geladen und von tests/test_page_input.py ohne Anzeige getestet.
Die Werte liegen in ~/.config/draconyx/input.json und werden von hypr/dx_input.lua angewendet."""
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

BASE_LST = '/usr/share/X11/xkb/rules/base.lst'

# Grenzen (müssen zu hypr/dx_input.lua passen)
LIMITS = {
    'repeat_delay': (100, 2000), 'repeat_rate': (1, 100), 'sensitivity': (-1.0, 1.0),
    'touchpad_scroll_factor': (0.1, 5.0), 'zoom_factor': (1.0, 10.0), 'cursor_size': (16, 96),
}
BOOL_KEYS = ('numlock', 'natural_scroll_mouse', 'natural_scroll_touchpad', 'tap_to_click', 'two_finger_scroll', 'tap_and_drag',
             'drag_lock', 'disable_while_typing', 'left_handed', 'reduce_animations')
MAX_LAYOUTS = 4
LAYOUT_RE = re.compile(r'[A-Za-z0-9_]{1,16}')
VARIANT_RE = re.compile(r'[A-Za-z0-9_\-]{1,32}')
OPTION_RE = re.compile(r'[A-Za-z0-9_]+:[A-Za-z0-9_\-.]+')


def config_dir():
    return Path(os.environ.get('HOME') or str(Path.home())) / '.config' / 'draconyx'


def input_path():
    return config_dir() / 'input.json'


# ---------------------------------------------------------------- Prüfen
def clean_value(key, value):
    """Gibt den geprüften (ggf. begrenzten) Wert zurück, sonst ValueError."""
    if key == 'layouts':
        if not isinstance(value, list):
            raise ValueError('layouts: Liste erwartet')
        out = []
        for e in value[:MAX_LAYOUTS]:
            lay = e.get('layout') if isinstance(e, dict) else e
            var = (e.get('variant') or '') if isinstance(e, dict) else ''
            if not isinstance(lay, str) or not LAYOUT_RE.fullmatch(lay):
                raise ValueError('Ungültiges Layout: %r' % (lay,))
            if not isinstance(var, str) or (var and not VARIANT_RE.fullmatch(var)):
                raise ValueError('Ungültige Variante: %r' % (var,))
            out.append({'layout': lay, 'variant': var})
        return out
    if key == 'kb_options':
        if not isinstance(value, list):
            raise ValueError('kb_options: Liste erwartet')
        out = []
        for o in value:
            if not isinstance(o, str) or not OPTION_RE.fullmatch(o):
                raise ValueError('Ungültige Tastaturoption: %r' % (o,))
            if o not in out:
                out.append(o)
        return out
    if key == 'accel_profile':
        if value not in ('flat', 'adaptive'):
            raise ValueError('Beschleunigungsprofil: flat oder adaptive')
        return value
    if key in BOOL_KEYS:
        if not isinstance(value, bool):
            raise ValueError('%s: Ja/Nein erwartet' % key)
        return value
    if key in LIMITS:
        lo, hi = LIMITS[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or value != value or value in (float('inf'), float('-inf')):
            raise ValueError('%s: Zahl erwartet' % key)
        v = min(max(value, lo), hi)
        return int(round(v)) if key in ('repeat_delay', 'repeat_rate', 'cursor_size') else round(float(v), 3)
    raise ValueError('Unbekannter Schlüssel: %s' % key)


KNOWN_KEYS = ('layouts', 'kb_options', 'accel_profile') + BOOL_KEYS + tuple(LIMITS)


# ---------------------------------------------------------------- Lesen / Schreiben
def load_input(path=None):
    """Liest input.json; fehlende oder kaputte Datei ergibt {}. Ungültige Einzelwerte werden verworfen."""
    p = Path(path) if path else input_path()
    try:
        if p.stat().st_size > 64 * 1024:
            return {}
        data = json.loads(p.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    out = {}
    for k, v in data.items():
        if k in KNOWN_KEYS:
            try:
                out[k] = clean_value(k, v)
            except ValueError:
                pass
        elif isinstance(k, str):
            out[k] = v   # fremde Schlüssel (z. B. Merkfelder anderer Seiten) bleiben erhalten
    return out


def atomic_write_text(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name + '.', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def save_input(data, path=None):
    """Schreibt input.json atomar. Bekannte Schlüssel werden geprüft (ValueError bei Unsinn), None-Werte entfallen."""
    out = {}
    for k, v in data.items():
        if v is None:
            continue
        out[k] = clean_value(k, v) if k in KNOWN_KEYS else v
    atomic_write_text(path or input_path(), json.dumps(out, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    return out


def update_input(changes, path=None):
    """Mischt Änderungen ein (Wert None = Schlüssel entfernen = Standard) und schreibt. Gibt die neue Tabelle zurück."""
    data = load_input(path)
    for k, v in changes.items():
        if v is None:
            data.pop(k, None)
        else:
            data[k] = clean_value(k, v) if k in KNOWN_KEYS else v
    return save_input(data, path)


def apply_live(timeout=5):
    """Sagt der laufenden Hyprland-Sitzung, die Datei neu einzulesen. Gibt True zurück, wenn der Aufruf lief."""
    exe = shutil.which('hyprctl')
    if not exe or not os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        return False
    try:
        r = subprocess.run([exe, 'eval', 'DXInput.apply()'], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return False
    return r.returncode == 0


# ---------------------------------------------------------------- xkb: base.lst
def parse_base_lst(path=BASE_LST):
    """Liest die XKB-Regeldatei. Ergebnis: {'layouts': [(code, Beschreibung)], 'variants': {layout: [(variante, Beschreibung)]},
    'options': {gruppe: [(option, Beschreibung)]}, 'groups': {gruppe: Beschreibung}}. Fehlende Datei ergibt leere Tabellen."""
    res = {'layouts': [], 'variants': {}, 'options': {}, 'groups': {}}
    try:
        lines = Path(path).read_text(encoding='utf-8', errors='replace').splitlines()
    except OSError:
        return res
    section = ''
    for raw in lines:
        if raw.startswith('!'):
            section = raw[1:].strip()
            continue
        if not raw.strip() or not raw.startswith(' '):
            continue
        parts = raw.strip().split(None, 1)
        if len(parts) != 2:
            continue
        name, desc = parts
        desc = desc.strip().replace('&lt;', '<').replace('&gt;', '>').replace('&amp;', '&')
        if section == 'layout':
            if LAYOUT_RE.fullmatch(name):
                res['layouts'].append((name, desc))
        elif section == 'variant':
            m = re.match(r'([A-Za-z0-9_]+): (.*)$', desc)
            if m and VARIANT_RE.fullmatch(name):
                res['variants'].setdefault(m.group(1), []).append((name, m.group(2)))
        elif section == 'option':
            if ':' in name:
                if OPTION_RE.fullmatch(name):
                    res['options'].setdefault(name.split(':', 1)[0], []).append((name, desc))
            else:
                res['groups'][name] = desc
    return res


def search_layouts(layouts, query):
    """Filtert (code, beschreibung)-Paare nach einer Suchanfrage (Groß-/Kleinschreibung egal, alle Wörter müssen passen)."""
    words = (query or '').lower().split()
    return [(c, d) for c, d in layouts if all(w in (c + ' ' + d).lower() for w in words)]


def layout_label(layout, variant, lst=None):
    desc = dict(lst['layouts']).get(layout, layout) if lst else layout
    if variant:
        vd = dict(lst['variants'].get(layout, [])).get(variant, variant) if lst else variant
        return '%s – %s' % (desc, vd)
    return desc


def short_layout_code(layout, variant):
    return layout + ('(%s)' % variant if variant else '')


# ---------------------------------------------------------------- kb_options
SWITCH_CHOICES = [  # Umschalt-Tastenkombination (grp:...)
    ('', 'Keine Tastenkombination'),
    ('grp:alt_shift_toggle', 'Alt + Umschalt'),
    ('grp:ctrl_shift_toggle', 'Strg + Umschalt'),
    ('grp:win_space_toggle', 'Win + Leertaste'),
    ('grp:alt_space_toggle', 'Alt + Leertaste'),
    ('grp:ctrl_space_toggle', 'Strg + Leertaste'),
    ('grp:ctrl_alt_toggle', 'Strg + Alt'),
    ('grp:shifts_toggle', 'Beide Umschalttasten gleichzeitig'),
    ('grp:alts_toggle', 'Beide Alt-Tasten gleichzeitig'),
    ('grp:caps_toggle', 'Feststelltaste'),
    ('grp:lalt_lshift_toggle', 'Linke Alt + Linke Umschalt'),
    ('grp:menu_toggle', 'Menütaste'),
    ('grp:sclk_toggle', 'Rollen-Taste'),
]
CAPS_CHOICES = [  # Feststelltaste (caps:... / ctrl:nocaps)
    ('', 'Normal (Großschreibung festhalten)'),
    ('caps:escape', 'Zusätzliche Esc-Taste'),
    ('caps:swapescape', 'Esc und Feststelltaste vertauschen'),
    ('ctrl:nocaps', 'Wie Strg-Taste'),
    ('caps:ctrl_modifier', 'Zusätzliche Strg-Taste (bleibt Feststelltaste)'),
    ('caps:backspace', 'Zusätzliche Rücktaste'),
    ('caps:shiftlock', 'Umschalt-Feststeller (alle Tasten)'),
    ('caps:none', 'Ausgeschaltet'),
]
COMPOSE_CHOICES = [  # Compose-Taste (compose:...)
    ('', 'Keine'),
    ('compose:ralt', 'Rechte Alt-Taste'),
    ('compose:rctrl', 'Rechte Strg-Taste'),
    ('compose:menu', 'Menütaste'),
    ('compose:caps', 'Feststelltaste'),
    ('compose:prsc', 'Druck-Taste'),
    ('compose:sclk', 'Rollen-Taste'),
    ('compose:ins', 'Einfg-Taste'),
    ('compose:paus', 'Pause-Taste'),
    ('compose:rwin', 'Rechte Win-Taste'),
    ('compose:102', 'Taste „<>“'),
]
_PREFIX_OF = {'switch': ('grp:',), 'caps': ('caps:', 'ctrl:nocaps'), 'compose': ('compose:',)}


def options_get(options, kind):
    """Aktuell gewählte Option der Art 'switch', 'caps' oder 'compose' ('' wenn keine)."""
    for o in options or []:
        if any(o.startswith(p) for p in _PREFIX_OF[kind]):
            return o
    return ''


def options_set(options, kind, value):
    """Neue Optionsliste: Optionen der Art kind ersetzt, alle anderen unverändert. value '' = entfernen."""
    if value and not OPTION_RE.fullmatch(value):
        raise ValueError('Ungültige Tastaturoption: %r' % (value,))
    out = [o for o in (options or []) if not any(o.startswith(p) for p in _PREFIX_OF[kind])]
    if value:
        out.append(value)
    return out


def options_string(options):
    return ','.join(options or [])


def kb_summary(data, default_layout='de'):
    """Lesbare Zusammenfassung der Belegung aus input.json (ohne Hyprland)."""
    lays = data.get('layouts') or [{'layout': default_layout, 'variant': ''}]
    return ', '.join(short_layout_code(e['layout'], e['variant']) for e in lays)


# ---------------------------------------------------------------- Geräte
def parse_devices(js):
    """Ergebnis von `hyprctl devices -j` -> [(Art, Name)]; unbekannte Form ergibt []."""
    out = []
    if not isinstance(js, dict):
        return out
    kinds = (('mice', 'Maus'), ('keyboards', 'Tastatur'), ('tablets', 'Grafiktablett'), ('touch', 'Touch'))
    for key, label in kinds:
        for d in js.get(key) or []:
            if isinstance(d, dict) and isinstance(d.get('name'), str):
                out.append((label, d['name']))
    return out


def read_devices(timeout=5):
    exe = shutil.which('hyprctl')
    if not exe:
        return None
    try:
        r = subprocess.run([exe, 'devices', '-j'], capture_output=True, text=True, timeout=timeout)
        return parse_devices(json.loads(r.stdout)) if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def list_gamepads(sys_dir='/sys/class/input'):
    """Spielcontroller (js*-Geräte) mit Namen aus /sys/class/input. Nur Anzeige."""
    out = []
    try:
        names = sorted(os.listdir(sys_dir))
    except OSError:
        return out
    for n in names:
        if re.fullmatch(r'js\d+', n):
            try:
                name = (Path(sys_dir) / n / 'device' / 'name').read_text(errors='replace').strip()
            except OSError:
                name = 'Unbekannt'
            out.append((n, name or 'Unbekannt'))
    return out


def current_cursor(env=None):
    """(Thema, Größe) des Zeigers aus den Umgebungsvariablen von Hyprland; nur Anzeige."""
    env = os.environ if env is None else env
    theme = env.get('XCURSOR_THEME') or 'Standard'
    try:
        size = int(env.get('XCURSOR_SIZE') or 24)
    except ValueError:
        size = 24
    return theme, min(max(size, 8), 256)
