"""Aurora-Einstellungen: Benachrichtigungen (swaync). Reine Logik oben (testbar), GTK-Oberfläche in build()."""
import json
import os
import re
import shlex
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import _devlib as D  # noqa: E402

TITLE = 'Benachrichtigungen'
GROUP = 'SYSTEM'
ICONS = ['preferences-system-notifications-symbolic', 'notifications-symbolic', 'dialog-information-symbolic']
ORDER = 30

SYSTEM_CONFIG = '/etc/xdg/swaync/config.json'
BACKUP_SUFFIX = '.vor-aurora'
RULE_PREFIX = 'aurora-app-'
SOUND_KEY = 'aurora-ton'
SOUND_FILES = ['/usr/share/sounds/freedesktop/stereo/message.oga', '/usr/share/sounds/freedesktop/stereo/message-new-instant.oga',
               '/usr/share/sounds/freedesktop/stereo/bell.oga']
POS_X = [('left', 'Links'), ('center', 'Mitte'), ('right', 'Rechts')]
POS_Y = [('top', 'Oben'), ('bottom', 'Unten')]
MUTE_STATES = {'muted': 'Nur im Verlauf (kein Popup)', 'ignored': 'Gar nicht anzeigen'}


# ---------- reine Logik ----------
def config_path():
    return D.config_home() / 'swaync' / 'config.json'


def load_config(path, fallback=SYSTEM_CONFIG):
    """-> (dict, Fehlertext oder None, existiert_nutzerdatei). Eine vorhandene, aber kaputte Datei wird NIE ersetzt (Fehlertext).
    Gibt es keine Nutzerdatei, dient die Systemdatei (falls gültig) als Vorlage."""
    p = Path(path)
    if p.exists():
        try:
            data = json.loads(p.read_text(encoding='utf-8'))
        except (OSError, ValueError) as e:
            return {}, 'Die Datei %s ist kein gültiges JSON (%s). Sie wird nicht verändert.' % (p, e), True
        if not isinstance(data, dict):
            return {}, 'Die Datei %s enthält kein JSON-Objekt. Sie wird nicht verändert.' % p, True
        return data, None, True
    try:
        data = json.loads(Path(fallback).read_text(encoding='utf-8'))
        if isinstance(data, dict):
            return data, None, False
    except (OSError, ValueError):
        pass
    return {}, None, False


def save_config(path, data):
    """Schreibt JSON atomar; eine bestehende Datei wird einmalig als config.json.vor-aurora gesichert."""
    json.loads(json.dumps(data))  # muss serialisierbar sein
    D.atomic_write(path, json.dumps(data, indent=2, ensure_ascii=False) + '\n', BACKUP_SUFFIX)


def set_option(data, key, value):
    allowed = {
        'positionX': lambda v: v in dict(POS_X),
        'positionY': lambda v: v in dict(POS_Y),
        'timeout': lambda v: isinstance(v, int) and 0 <= v <= 600,
        'timeout-low': lambda v: isinstance(v, int) and 0 <= v <= 600,
        'timeout-critical': lambda v: isinstance(v, int) and 0 <= v <= 600,
    }
    if key not in allowed or not allowed[key](value):
        raise ValueError('Ungültiger Wert für %s' % key)
    out = dict(data)
    out[key] = value
    return out


def slug(app):
    return re.sub(r'[^a-z0-9]+', '-', app.lower()).strip('-')[:60] or 'app'


def valid_app_name(app):
    return bool(app) and len(app) <= 80 and not re.search(r'[\x00-\x1f]', app)


def mute_rules(data):
    """Regeln, die diese Seite angelegt hat: [(regelname, app, state)]."""
    out = []
    vis = data.get('notification-visibility')
    if isinstance(vis, dict):
        for k, v in vis.items():
            if k.startswith(RULE_PREFIX) and isinstance(v, dict):
                pat = str(v.get('app-name', ''))
                m = re.match(r'^\^(.*)\$$', pat)
                app = re.sub(r'\\(.)', r'\1', m.group(1)) if m else pat
                out.append((k, app, str(v.get('state', ''))))
    return out


def add_mute(data, app, state='muted'):
    if not valid_app_name(app):
        raise ValueError('Ungültiger App-Name.')
    if state not in MUTE_STATES:
        raise ValueError('Ungültiger Zustand.')
    out = dict(data)
    vis = dict(out.get('notification-visibility') or {})
    vis[RULE_PREFIX + slug(app)] = {'state': state, 'app-name': '^%s$' % re.escape(app)}
    out['notification-visibility'] = vis
    return out


def remove_mute(data, rule):
    if not rule.startswith(RULE_PREFIX):
        raise ValueError('Nur eigene Regeln können entfernt werden.')
    out = dict(data)
    vis = dict(out.get('notification-visibility') or {})
    vis.pop(rule, None)
    out['notification-visibility'] = vis
    return out


def sound_file(candidates=None):
    for f in (candidates or SOUND_FILES):
        if os.path.isfile(f):
            return f
    return None


def sound_command(volume_percent, file):
    """Skript für swaync: spielt den Ton nur, wenn Nicht stören aus ist. Alles sicher gequotet."""
    vol = max(0, min(100, int(volume_percent)))
    pa = int(round(vol * 65536 / 100))
    return '[ "$(swaync-client -D -sw)" = false ] && paplay --volume=%d %s' % (pa, shlex.quote(file))


def sound_state(data):
    """-> (an, lautstärke in %) aus dem Skript-Eintrag dieser Seite."""
    s = (data.get('scripts') or {}).get(SOUND_KEY) if isinstance(data.get('scripts'), dict) else None
    if not isinstance(s, dict):
        return False, 70
    m = re.search(r'--volume=(\d+)', str(s.get('exec', '')))
    return True, (int(round(int(m.group(1)) * 100 / 65536)) if m else 70)


def set_sound(data, enabled, volume_percent, file):
    out = dict(data)
    scripts = dict(out.get('scripts') or {})
    if enabled:
        if not file:
            raise ValueError('Keine Tondatei gefunden.')
        scripts[SOUND_KEY] = {'exec': sound_command(volume_percent, file), 'app-name': '.*', 'run-on': 'receive'}
    else:
        scripts.pop(SOUND_KEY, None)
    out['scripts'] = scripts
    return out


def parse_busctl_comm(text):
    m = re.search(r'^Comm=(\S+)', text or '', re.M)
    return m.group(1) if m else None


def parse_dnd(out):
    s = (out or '').strip().lower()
    if s in ('true', 'false'):
        return s == 'true'
    return None


def cmd_dnd(on):
    return ['swaync-client', '-dn' if on else '-df', '-sw']


def cmd_clear():
    return ['swaync-client', '-C', '-sw']


def cmd_reload():
    return ['swaync-client', '-R', '-sw']


def cmd_preview():
    return ['notify-send', '-a', 'Aurora', '-i', 'preferences-system-notifications', '-t', '6000',
            'Vorschau', 'So sieht eine Benachrichtigung mit den aktuellen Einstellungen aus.']


# ---------- Oberfläche ----------
def build(app):
    from gi.repository import Gtk
    box = app.page(TITLE, 'Nicht stören, Verlauf, Position und Dauer, Ton und stummgeschaltete Apps. Die Benachrichtigungen kommen vom Dienst swaync.')
    st = {'ready': False, 'swaync': False, 'sync': False, 'cfg': None, 'err': None, 'sound_file': sound_file(), 'paplay': bool(D.which('paplay'))}
    say = app.message

    notice = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(notice, False, False, 0)
    ctl = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    box.pack_start(ctl, False, False, 0)

    def action(argv, ok=None, timeout=10, after=None):
        def done(res):
            if isinstance(res, Exception) or res.returncode != 0:
                say('Fehlgeschlagen: ' + (str(res) if isinstance(res, Exception) else (res.stderr or res.stdout or 'Fehler %s' % res.returncode).strip()))
            elif ok:
                say(ok)
            if after:
                after()
        D.bg(lambda: D.run_cmd(argv, timeout), done)

    # --- Nicht stören ---
    dnd_sw = Gtk.Switch()

    def on_dnd(sw, _):
        if st['sync']:
            return
        action(cmd_dnd(sw.get_active()), 'Nicht stören ist %s.' % ('an' if sw.get_active() else 'aus'))
    dnd_sw.connect('notify::active', on_dnd)

    def refresh_dnd():
        def done(res):
            if isinstance(res, Exception):
                return
            v = parse_dnd(res.stdout)
            if v is not None and v != dnd_sw.get_active():
                st['sync'] = True
                dnd_sw.set_active(v)
                st['sync'] = False
        D.bg(lambda: D.run_cmd(['swaync-client', '-D', '-sw'], 5), done)

    app.section(ctl, 'Ruhe')
    app.row(ctl, 'Nicht stören', dnd_sw, 'Blendet Popups aus; Meldungen landen im Verlauf. Derselbe Zustand wie in der Taskleiste und im Kontrollzentrum. Die Arbeitsphase des Fokus-Timers kann ihn automatisch einschalten.')
    app.button(ctl, 'Verlauf löschen', 'Alle löschen', lambda: action(cmd_clear(), 'Verlauf gelöscht.'), 'Entfernt alle gesammelten Benachrichtigungen.')
    app.button(ctl, 'Vorschau', 'Testmeldung senden', lambda: action(cmd_preview(), None), 'Zeigt eine einfache Meldung (ohne Knöpfe) an der gewählten Stelle.')

    # --- Konfiguration ---
    app.section(ctl, 'Darstellung')
    cfg_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    ctl.pack_start(cfg_box, False, False, 0)
    mute_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)

    def write(mutator, ok):
        path = config_path()
        data, err, _ = load_config(path)
        if err:
            say(err)
            return False
        try:
            new = mutator(data)
            save_config(path, new)
        except (ValueError, OSError) as e:
            say('Nicht gespeichert: %s' % e)
            return False
        st['cfg'] = new
        say(ok)
        D.bg(lambda: D.run_cmd(cmd_reload(), 10))
        return True

    def num_spin(key, label, desc):
        data = st['cfg'] or {}
        cur = data.get(key, 10)
        sp = Gtk.SpinButton.new_with_range(0, 120, 1)
        sp.set_value(cur if isinstance(cur, int) else 10)
        sp.connect('value-changed', lambda w: None if st['sync'] else write(lambda d: set_option(d, key, w.get_value_as_int()), 'Anzeigedauer gespeichert.'))
        app.row(cfg_box, label, sp, desc)

    def populate():
        D.ui_clear(cfg_box)
        D.ui_clear(mute_box)
        data = st['cfg'] or {}
        if st['err']:
            cfg_box.pack_start(D.ui_label(st['err'], 'row-desc'), False, False, 0)
            cfg_box.show_all()
            return
        st['sync'] = True
        app.row(cfg_box, 'Position waagerecht', D.ui_choice(POS_X, data.get('positionX', 'right'), lambda v: write(lambda d: set_option(d, 'positionX', v), 'Position gespeichert.')), 'Wo die Popups am Bildschirmrand erscheinen.')
        app.row(cfg_box, 'Position senkrecht', D.ui_choice(POS_Y, data.get('positionY', 'top'), lambda v: write(lambda d: set_option(d, 'positionY', v), 'Position gespeichert.')))
        num_spin('timeout', 'Anzeigedauer (Sekunden)', 'Wie lange normale Meldungen stehen bleiben; 0 = bis zum Wegklicken.')
        num_spin('timeout-low', 'Anzeigedauer unwichtiger Meldungen', 'Für Meldungen mit niedriger Dringlichkeit.')
        num_spin('timeout-critical', 'Anzeigedauer wichtiger Meldungen', '0 = bleibt, bis man sie wegklickt.')
        # Ton
        on, vol = sound_state(data)
        if st['paplay'] and st['sound_file']:
            sw = Gtk.Switch(active=on)
            sp = Gtk.SpinButton.new_with_range(0, 100, 5)
            sp.set_value(vol)

            def snd(*_):
                if st['sync']:
                    return
                write(lambda d: set_sound(d, sw.get_active(), sp.get_value_as_int(), st['sound_file']), 'Ton gespeichert.')
            sw.connect('notify::active', snd)
            sp.connect('value-changed', lambda *_: snd() if sw.get_active() else None)
            app.row(cfg_box, 'Ton bei neuer Meldung', sw, 'swaync spielt von sich aus keinen Ton; die Seite trägt dafür ein kleines Skript ein (paplay). Bei „Nicht stören“ bleibt es still.')
            app.row(cfg_box, 'Lautstärke des Tons (%)', sp)
        else:
            cfg_box.pack_start(D.ui_label('Ton: nicht verfügbar (paplay aus „libpulse“ oder die freedesktop-Klänge aus „sound-theme-freedesktop“ fehlen).', 'row-desc'), False, False, 0)
        # Apps stummschalten
        app.section(cfg_box, 'Apps stummschalten')
        cfg_box.pack_start(mute_box, False, False, 0)
        fill_mute()
        st['sync'] = False
        cfg_box.show_all()

    mute_state = {'v': 'muted'}
    app_entry = Gtk.Entry(placeholder_text='App-Name wie in der Meldung', width_chars=24)

    def fill_mute():
        D.ui_clear(mute_box)
        data = st['cfg'] or {}
        rules = mute_rules(data)
        if not rules:
            mute_box.pack_start(D.ui_label('Keine Apps stummgeschaltet.', 'row-desc'), False, False, 0)
        for rule, appn, state in rules:
            mute_box.pack_start(D.ui_item(appn, MUTE_STATES.get(state, state), D.ui_button('Wieder erlauben', lambda r=rule: unmute(r))), False, False, 0)

        def add():
            name = app_entry.get_text().strip()
            if write(lambda d: add_mute(d, name, mute_state['v']), '„%s“ ist stummgeschaltet.' % name):
                app_entry.set_text('')
                fill_mute()
        sel = D.ui_select(list(MUTE_STATES.items()), mute_state['v'], lambda v: mute_state.__setitem__('v', v or 'muted'))
        mute_box.pack_start(D.ui_item('App hinzufügen', 'Der Name steht in der Meldung oft über dem Text (bei notify-send der Wert von -a).', app_entry, sel, D.ui_button('Stummschalten', add)), False, False, 0)
        mute_box.show_all()

    def unmute(rule):
        if write(lambda d: remove_mute(d, rule), 'Wieder erlaubt.'):
            fill_mute()

    def probe():
        have = bool(D.which('swaync'))
        running = D.run_cmd(['pgrep', '-x', 'swaync'], 3).returncode == 0
        owner = parse_busctl_comm(D.run_cmd(['busctl', '--user', 'status', 'org.freedesktop.Notifications'], 4).stdout) if D.which('busctl') else None
        return have, running, owner

    def probed(r):
        if isinstance(r, Exception):
            return
        have, running, owner = r
        D.ui_clear(notice)
        st['swaync'] = have and running
        if not have:
            msg = 'swaync ist nicht installiert (Paket „swaync“, Arch: „sudo pacman -S swaync“). Ohne diesen Dienst gibt es hier nichts einzustellen.'
            if owner:
                msg += ' Zurzeit nimmt „%s“ die Benachrichtigungen an; dessen Einstellungen bietet diese Seite nicht an.' % owner
            notice.pack_start(D.ui_item('Benachrichtigungsdienst fehlt', msg), False, False, 0)
        elif not running:
            msg = 'swaync ist installiert, läuft aber nicht.'
            if owner and owner != 'swaync':
                msg += ' Stattdessen nimmt „%s“ die Benachrichtigungen an – dessen Einstellungen gibt es hier nicht.' % owner
            else:
                msg += ' Er startet mit der Shell bzw. kann mit „swaync“ gestartet werden.'
            notice.pack_start(D.ui_item('swaync läuft nicht', msg), False, False, 0)
        notice.show_all()
        ctl.set_sensitive(have)
        if have:
            data, err, _ = load_config(config_path())
            st['cfg'], st['err'] = data, err
            populate()
            if running:
                refresh_dnd()

    def on_map(*_):
        D.bg(probe, probed)
    box.connect('map', on_map)
    from gi.repository import GLib

    def poll():
        if box.get_mapped() and st['swaync']:
            refresh_dnd()
        return True
    GLib.timeout_add_seconds(4, poll)
    return box
