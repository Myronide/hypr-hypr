"""Aurora-Einstellungen: Seite „Ton“ (Ausgabe/Eingabe, Lautstärke je Gerät und App, Soundprofile, Balance, Test-Ton).

Reine Logik (Parser, Befehlsbauer) steht oben und braucht weder GTK noch PipeWire; die Oberfläche steht in build().
Bevorzugt wird `pactl --format=json` (pipewire-pulse), ohne pactl ein reduzierter Rückfall auf `wpctl`.
Es wird nur geschrieben, wenn der Nutzer etwas ändert."""
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import threading
import wave
from pathlib import Path

TITLE = 'Ton'
GROUP = 'SYSTEM'
ICONS = ['audio-volume-high-symbolic', 'audio-speakers-symbolic']
ORDER = 20

TIMEOUT = 4          # Sekunden je Lesebefehl
MAX_NORMAL = 100
MAX_BOOST = 150


# ---------------------------------------------------------------- reine Logik
def which(name):
    for d in os.environ.get('PATH', '').split(os.pathsep):
        p = os.path.join(d, name)
        if d and os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def default_run(args, timeout=TIMEOUT):
    """Programm mit Zeitlimit; fehlendes Programm/Zeitüberschreitung ergibt ein fehlgeschlagenes Ergebnis."""
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as e:
        return subprocess.CompletedProcess(args, 127, '', str(e))


def _json_list(text):
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        return []
    return [x for x in data if isinstance(x, dict)] if isinstance(data, list) else []


def _pct(v):
    """'65%' / 0.65 / 65536 -> nichts Sinnvolles erraten; nur Prozentzeichenketten."""
    m = re.match(r'\s*(-?\d+(?:\.\d+)?)\s*%', str(v))
    return float(m.group(1)) if m else None


def _volumes(vol):
    """Lautstärke-Objekt von pactl -> Liste (Kanalname, Prozent) in Eingabereihenfolge."""
    out = []
    if isinstance(vol, dict):
        for ch, v in vol.items():
            p = _pct(v.get('value_percent')) if isinstance(v, dict) else None
            if p is None and isinstance(v, dict) and isinstance(v.get('value'), (int, float)):
                p = v['value'] * 100.0 / 65536
            if p is not None:
                out.append((str(ch), p))
    return out


def channel_side(ch):
    """-1 links, +1 rechts, 0 Mitte/sonstige."""
    c = ch.lower()
    if 'left' in c or c.endswith('-l') or c in ('fl', 'rl', 'sl'):
        return -1
    if 'right' in c or c.endswith('-r') or c in ('fr', 'rr', 'sr'):
        return 1
    return 0


def balance_of(vols):
    """Balance -1..1 aus Kanallautstärken (wie PulseAudio)."""
    left = [p for ch, p in vols if channel_side(ch) < 0]
    right = [p for ch, p in vols if channel_side(ch) > 0]
    if not left or not right:
        return 0.0
    l, r = max(left), max(right)
    if l <= 0 and r <= 0:
        return 0.0
    if r > l:
        return round(1 - l / r, 3)
    if l > r:
        return round(-(1 - r / l), 3)
    return 0.0


def _device(d, kind, default):
    name = str(d.get('name', ''))
    props = d.get('properties') if isinstance(d.get('properties'), dict) else {}
    vols = _volumes(d.get('volume'))
    ports = []
    for p in d.get('ports') or []:
        if isinstance(p, dict) and p.get('name'):
            ports.append({'name': str(p['name']), 'desc': str(p.get('description') or p['name']),
                          'ok': str(p.get('availability', '')) != 'not available'})
    return {
        'kind': kind, 'id': name, 'name': name,
        'desc': str(d.get('description') or props.get('device.description') or name),
        'vol': max([p for _, p in vols], default=0.0), 'channels': [c for c, _ in vols],
        'volumes': vols, 'balance': balance_of(vols), 'mute': bool(d.get('mute')),
        'default': name == default, 'ports': ports,
        'port': d.get('active_port') if isinstance(d.get('active_port'), str) else None,
        'state': str(d.get('state', '')),
    }


def _stream_name(d):
    props = d.get('properties') if isinstance(d.get('properties'), dict) else {}
    for k in ('application.name', 'application.process.binary', 'node.name', 'media.name'):
        if props.get(k):
            n = str(props[k])
            media = str(props.get('media.name') or '')
            return n, (media if media and media != n else '')
    return 'Unbekannte App', ''


def parse_pactl(sinks, sources, inputs, cards, default_sink='', default_source=''):
    """Eingaben: Textausgaben von `pactl --format=json list …`. Liefert das Modell (nie eine Ausnahme)."""
    model = {'backend': 'pactl', 'sinks': [], 'sources': [], 'streams': [], 'cards': []}
    for d in _json_list(sinks):
        if d.get('name'):
            model['sinks'].append(_device(d, 'sink', default_sink))
    for d in _json_list(sources):
        n = str(d.get('name', ''))
        if n and not n.endswith('.monitor') and not d.get('monitor_of_sink'):
            model['sources'].append(_device(d, 'source', default_source))
    for d in _json_list(inputs):
        props = d.get('properties') if isinstance(d.get('properties'), dict) else {}
        if str(props.get('node.virtual', '')) == 'true' or str(props.get('device.class', '')) == 'filter':
            continue
        vols = _volumes(d.get('volume'))
        if d.get('index') is None or not vols:
            continue
        name, media = _stream_name(d)
        model['streams'].append({'id': str(d['index']), 'name': name, 'media': media,
                                 'vol': max(p for _, p in vols), 'channels': [c for c, _ in vols],
                                 'mute': bool(d.get('mute')), 'corked': bool(d.get('corked'))})
    for d in _json_list(cards):
        props = d.get('properties') if isinstance(d.get('properties'), dict) else {}
        profs = []
        pd = d.get('profiles') if isinstance(d.get('profiles'), dict) else {}
        for pname, p in pd.items():
            if isinstance(p, dict) and p.get('available', True):
                profs.append({'name': str(pname), 'desc': str(p.get('description') or pname)})
        if d.get('name') and len(profs) > 0:
            model['cards'].append({'name': str(d['name']),
                                   'desc': str(props.get('device.description') or props.get('device.product.name') or d['name']),
                                   'active': str(d.get('active_profile') or ''), 'profiles': profs})
    return model


_WP_LINE = re.compile(r'^[\s│├└─]*(\*)?\s*(\d+)\.\s+(.*?)(?:\s+\[vol:\s*([\d.]+)(?:\s+MUTED)?\])?\s*$')


def parse_wpctl_status(text):
    """`wpctl status` -> Modell mit Sinks/Sources (ohne Streams/Karten). Robust gegen Abweichungen."""
    model = {'backend': 'wpctl', 'sinks': [], 'sources': [], 'streams': [], 'cards': []}
    section = None
    for raw in (text or '').splitlines():
        h = re.match(r'^[\s│├└─]*[├└]─\s*(\w+):\s*$', raw)
        if h:
            section = h.group(1)
            continue
        if raw.strip() and not raw[0].isspace() and raw[0] not in '│├└':
            section = None      # neue Hauptgruppe (Audio, Video, Settings)
            continue
        if section not in ('Sinks', 'Sources'):
            continue
        m = _WP_LINE.match(raw)
        if not m:
            continue
        default, ident, desc, vol = m.groups()
        muted = 'MUTED' in raw
        try:
            v = float(vol) * 100 if vol is not None else 0.0
        except ValueError:
            v = 0.0
        dev = {'kind': 'sink' if section == 'Sinks' else 'source', 'id': ident, 'name': ident,
               'desc': desc.strip(), 'vol': v, 'channels': [], 'volumes': [], 'balance': 0.0,
               'mute': muted, 'default': bool(default), 'ports': [], 'port': None, 'state': ''}
        model['sinks' if section == 'Sinks' else 'sources'].append(dev)
    return model


def collect(run=default_run, have=which):
    """Liest den Audiozustand. Rückgabe (Modell, Fehlertext); bei Fehler Modell None."""
    err = ''
    if have('pactl'):
        r = run(['pactl', '--format=json', 'list', 'sinks'])
        if r.returncode == 0:
            def out(args):
                x = run(args)
                return x.stdout if x.returncode == 0 else ''
            return parse_pactl(r.stdout, out(['pactl', '--format=json', 'list', 'sources']),
                               out(['pactl', '--format=json', 'list', 'sink-inputs']),
                               out(['pactl', '--format=json', 'list', 'cards']),
                               out(['pactl', 'get-default-sink']).strip(),
                               out(['pactl', 'get-default-source']).strip()), None
        err = (r.stderr or '').strip()
    if have('wpctl'):
        r = run(['wpctl', 'status'])
        if r.returncode == 0:
            return parse_wpctl_status(r.stdout), None
        err = err or (r.stderr or '').strip()
        return None, err_hint(err)
    if err:
        return None, err_hint(err)
    return None, 'Weder „pactl“ noch „wpctl“ gefunden. Bitte pipewire-pulse bzw. wireplumber installieren.'


def err_hint(err):
    low = err.lower()
    if 'timed out' in low:
        return 'Der Audiodienst antwortet nicht (Zeitüberschreitung).'
    if 'connection refused' in low or 'no such file' in low or 'verbindung' in low or 'not connect' in low or 'could not connect' in low:
        return 'Kein laufender Audiodienst gefunden. Läuft PipeWire (systemctl --user status pipewire pipewire-pulse wireplumber)?'
    return 'Audio konnte nicht gelesen werden' + (': ' + err.splitlines()[0] if err else '.')


# Befehlsbauer ---------------------------------------------------------------
def clamp_percent(p, boost=False):
    try:
        v = float(p)
    except (TypeError, ValueError):
        return None
    if math.isnan(v) or math.isinf(v):
        return None
    return max(0.0, min(v, MAX_BOOST if boost else MAX_NORMAL))


def channel_percents(percent, channels, balance=0.0):
    """Prozentwerte je Kanal für Gesamtlautstärke und Balance (-1 links … +1 rechts)."""
    b = max(-1.0, min(1.0, float(balance or 0)))
    out = []
    for ch in channels or ['mono']:
        s = channel_side(ch)
        f = (1 - max(b, 0)) if s < 0 else (1 + min(b, 0)) if s > 0 else 1.0
        out.append(int(round(percent * f)))
    return out


def volume_cmd(backend, kind, ident, percent, channels=None, balance=0.0, boost=False):
    p = clamp_percent(percent, boost)
    if p is None or not ident:
        return None
    if backend == 'wpctl':
        return ['wpctl', 'set-volume', str(ident), '%.2f' % (p / 100)]
    sub = {'sink': 'set-sink-volume', 'source': 'set-source-volume', 'stream': 'set-sink-input-volume'}.get(kind)
    if not sub:
        return None
    return ['pactl', sub, str(ident)] + ['%d%%' % v for v in channel_percents(p, channels, balance)]


def mute_cmd(backend, kind, ident, mute):
    if not ident:
        return None
    if backend == 'wpctl':
        return ['wpctl', 'set-mute', str(ident), '1' if mute else '0']
    sub = {'sink': 'set-sink-mute', 'source': 'set-source-mute', 'stream': 'set-sink-input-mute'}.get(kind)
    return ['pactl', sub, str(ident), '1' if mute else '0'] if sub else None


def default_cmd(backend, kind, ident):
    if not ident:
        return None
    if backend == 'wpctl':
        return ['wpctl', 'set-default', str(ident)]
    sub = {'sink': 'set-default-sink', 'source': 'set-default-source'}.get(kind)
    return ['pactl', sub, str(ident)] if sub else None


def profile_cmd(card, profile):
    return ['pactl', 'set-card-profile', str(card), str(profile)] if card and profile else None


def port_cmd(kind, ident, port):
    sub = {'sink': 'set-sink-port', 'source': 'set-source-port'}.get(kind)
    return ['pactl', sub, str(ident), str(port)] if sub and ident and port else None


def write_tone_wav(path, side, seconds=1.2, rate=44100):
    """Schreibt einen kurzen Sinuston (side: 'left', 'right', 'both') atomar nach path."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    freq = {'left': 440.0, 'right': 660.0, 'both': 523.25}[side]
    n = int(rate * seconds)
    frames = bytearray()
    for i in range(n):
        env = min(1.0, i / (rate * 0.03), (n - i) / (rate * 0.1))
        v = int(0.35 * 32767 * env * math.sin(2 * math.pi * freq * i / rate))
        lv = v if side in ('left', 'both') else 0
        rv = v if side in ('right', 'both') else 0
        frames += lv.to_bytes(2, 'little', signed=True) + rv.to_bytes(2, 'little', signed=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), suffix='.tmp')
    os.close(fd)
    try:
        with wave.open(tmp, 'wb') as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(bytes(frames))
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    return path


def tone_cmd(backend, sink, wav):
    if which('paplay') and backend != 'wpctl':
        return ['paplay', '--device=' + str(sink), str(wav)]
    if which('pw-play'):
        return ['pw-play', '--target=' + str(sink), str(wav)]
    if which('paplay'):
        return ['paplay', str(wav)]
    return None


def tone_dir():
    base = os.environ.get('XDG_CACHE_HOME') or os.path.join(os.path.expanduser('~'), '.cache')
    return Path(base) / 'aurora'


# ---------------------------------------------------------------- Oberfläche
def build(app):
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import GLib, Gtk

    box = app.page(TITLE, 'Ausgabe- und Eingabegeräte, Lautstärke je Gerät und App, Soundprofile, Balance und Test-Ton.')
    app.page_index[TITLE].append('lautstärke stumm mikrofon lautsprecher kopfhörer hdmi standardgerät audio sound pipewire verstärkung balance test-ton')
    S = {'model': None, 'sig': None, 'loading': False, 'dirty': {}, 'timers': {}, 'upd': False,
         'boost': False, 'widgets': {}}

    notice = Gtk.Label(label='', xalign=0)
    notice.set_line_wrap(True)
    notice.get_style_context().add_class('row-desc')
    box.pack_start(notice, False, False, 0)
    boost_sw = Gtk.Switch()
    boost_sw.set_valign(Gtk.Align.CENTER)
    app.row(box, 'Verstärkung über 100 %', boost_sw,
            'Erlaubt Lautstärken bis 150 %. Das kann verzerren und Lautsprecher schädigen; wirkt nur in diesem Fenster.')
    dyn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    box.pack_start(dyn, False, False, 0)

    def write(cmd, then_refresh=False):
        if not cmd:
            return

        def work():
            r = app.run_tool(cmd, timeout=TIMEOUT)
            def done():
                if r.returncode != 0:
                    app.message('Ton: Änderung fehlgeschlagen' + ((' – ' + r.stderr.strip().splitlines()[0]) if r.stderr.strip() else '.'))
                if then_refresh:
                    refresh()
                return False
            GLib.idle_add(done)
        threading.Thread(target=work, daemon=True).start()

    def label_for(v):
        return '%d %%' % round(v)

    def row_frame(title, sub=''):
        row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        row.get_style_context().add_class('setting-row')
        t = Gtk.Label(label=title, xalign=0)
        t.set_line_wrap(True)
        t.get_style_context().add_class('row-title')
        row.pack_start(t, False, False, 0)
        if sub:
            d = Gtk.Label(label=sub, xalign=0)
            d.set_line_wrap(True)
            d.get_style_context().add_class('row-desc')
            row.pack_start(d, False, False, 0)
        return row, t

    def vol_controls(parent, key, kind, item):
        """Regler + Stumm-Knopf + Prozentanzeige; schreibt entleert (entprellt)."""
        hb = Gtk.Box(spacing=10)
        mx = MAX_BOOST if (S['boost'] or item['vol'] > 100) else MAX_NORMAL
        sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, mx, 1)
        sc.set_draw_value(False)
        sc.set_hexpand(True)
        if mx > 100:
            sc.add_mark(100, Gtk.PositionType.BOTTOM, None)
        mute = Gtk.ToggleButton(label='Stumm')
        pct = Gtk.Label(label=label_for(item['vol']))
        pct.set_width_chars(6)
        hb.pack_start(sc, True, True, 0)
        hb.pack_start(pct, False, False, 0)
        hb.pack_start(mute, False, False, 0)
        parent.pack_start(hb, False, False, 0)
        w = {'scale': sc, 'mute': mute, 'pct': pct, 'item': item, 'kind': kind}
        S['widgets'][key] = w
        set_state(w, item)

        def on_scale(_s):
            pct.set_text(label_for(sc.get_value()))
            if S['upd']:
                return
            S['dirty'][key] = GLib.get_monotonic_time()
            if key in S['timers']:
                GLib.source_remove(S['timers'][key])

            def fire():
                S['timers'].pop(key, None)
                it = w['item']
                bal = balance_value(key)
                write(volume_cmd(S['model']['backend'], kind, it['id'], sc.get_value(), it['channels'], bal, S['boost'] or it['vol'] > 100))
                return False
            S['timers'][key] = GLib.timeout_add(120, fire)
        sc.connect('value-changed', on_scale)

        def on_mute(b):
            if S['upd']:
                return
            S['dirty'][key] = GLib.get_monotonic_time()
            write(mute_cmd(S['model']['backend'], kind, w['item']['id'], b.get_active()))
        mute.connect('toggled', on_mute)
        return w

    def balance_value(key):
        w = S['widgets'].get(key)
        bs = w.get('balance') if w else None
        return bs.get_value() / 100.0 if bs else (w['item']['balance'] if w else 0.0)

    def set_state(w, item):
        w['item'] = item
        S['upd'] = True
        try:
            if w['scale'].get_adjustment().get_upper() < item['vol']:
                w['scale'].set_range(0, MAX_BOOST)
            w['scale'].set_value(item['vol'])
            w['pct'].set_text(label_for(item['vol']))
            w['mute'].set_active(item['mute'])
            if 'balance' in w:
                w['balance'].set_value(item['balance'] * 100)
        finally:
            S['upd'] = False

    def device_card(item):
        key = item['kind'] + ':' + item['id']
        title = item['desc'] + ('   (Standard)' if item['default'] else '')
        row, _ = row_frame(title)
        hb = Gtk.Box(spacing=8)
        if not item['default']:
            b = Gtk.Button(label='Als Standard verwenden')
            b.connect('clicked', lambda *_: write(default_cmd(S['model']['backend'], item['kind'], item['id']), True))
            hb.pack_start(b, False, False, 0)
        if item['ports'] and len(item['ports']) > 1:
            cb = Gtk.ComboBoxText()
            for p in item['ports']:
                cb.append(p['name'], p['desc'] + ('' if p['ok'] else ' (nicht angeschlossen)'))
            cb.set_active_id(item['port'])

            def on_port(c):
                if not S['upd'] and c.get_active_id() and c.get_active_id() != item['port']:
                    write(port_cmd(item['kind'], item['id'], c.get_active_id()), True)
            cb.connect('changed', on_port)
            hb.pack_start(Gtk.Label(label='Anschluss:'), False, False, 6)
            hb.pack_start(cb, False, False, 0)
        if hb.get_children():
            row.pack_start(hb, False, False, 0)
        w = vol_controls(row, key, item['kind'], item)
        if item['kind'] == 'sink' and S['model']['backend'] == 'pactl' and len(item['channels']) >= 2:
            bh = Gtk.Box(spacing=10)
            bh.pack_start(Gtk.Label(label='Balance', xalign=0), False, False, 0)
            bs = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, -100, 100, 1)
            bs.set_draw_value(False)
            bs.set_hexpand(True)
            bs.add_mark(0, Gtk.PositionType.BOTTOM, None)
            bs.set_value(item['balance'] * 100)
            w['balance'] = bs
            bh.pack_start(Gtk.Label(label='Links'), False, False, 0)
            bh.pack_start(bs, True, True, 0)
            bh.pack_start(Gtk.Label(label='Rechts'), False, False, 0)
            row.pack_start(bh, False, False, 0)

            def on_bal(_s):
                if S['upd']:
                    return
                S['dirty'][key] = GLib.get_monotonic_time()
                w['scale'].emit('value-changed')
            bs.connect('value-changed', on_bal)
            th = Gtk.Box(spacing=8)
            th.pack_start(Gtk.Label(label='Test-Ton:'), False, False, 0)
            for text, side in (('Links', 'left'), ('Rechts', 'right'), ('Beide', 'both')):
                tb = Gtk.Button(label=text)
                tb.connect('clicked', lambda _b, s=side: play_tone(item['id'], s))
                th.pack_start(tb, False, False, 0)
            row.pack_start(th, False, False, 0)
        dyn.pack_start(row, False, False, 0)

    def play_tone(sink, side):
        def work():
            msg = None
            try:
                wav = write_tone_wav(tone_dir() / ('test-%s.wav' % side), side)
                cmd = tone_cmd(S['model']['backend'] if S['model'] else 'pactl', sink, wav)
                if not cmd:
                    msg = 'Test-Ton: weder „paplay“ noch „pw-play“ gefunden.'
                else:
                    r = app.run_tool(cmd, timeout=8)
                    if r.returncode != 0:
                        msg = 'Test-Ton konnte nicht abgespielt werden.'
            except (OSError, ValueError) as e:
                msg = 'Test-Ton: ' + str(e)
            if msg:
                GLib.idle_add(lambda: app.message(msg) or False)
        threading.Thread(target=work, daemon=True).start()

    def stream_card(item):
        key = 'stream:' + item['id']
        row, _ = row_frame(item['name'] + ('   (pausiert)' if item['corked'] else ''), item['media'])
        item2 = dict(item)
        item2['balance'] = 0.0
        item2['id'] = item['id']
        vol_controls(row, key, 'stream', item2)
        dyn.pack_start(row, False, False, 0)

    def card_row(c):
        row, _ = row_frame(c['desc'], 'Soundprofil der Karte (z. B. Analog, HDMI, Pro Audio)')
        cb = Gtk.ComboBoxText()
        for p in c['profiles']:
            cb.append(p['name'], p['desc'])
        cb.set_active_id(c['active'])
        cb.set_halign(Gtk.Align.START)

        def on_prof(x):
            if not S['upd'] and x.get_active_id() and x.get_active_id() != c['active']:
                write(profile_cmd(c['name'], x.get_active_id()), True)
        cb.connect('changed', on_prof)
        row.pack_start(cb, False, False, 0)
        dyn.pack_start(row, False, False, 0)

    def heading(text):
        l = Gtk.Label(label=text.upper(), xalign=0)
        l.get_style_context().add_class('section-title')
        dyn.pack_start(l, False, False, 0)

    def signature(m):
        return (m['backend'], S['boost'],
                tuple((d['kind'], d['id'], d['desc'], d['default'], d['port'], len(d['channels'])) for d in m['sinks'] + m['sources']),
                tuple((s['id'], s['name'], s['corked']) for s in m['streams']),
                tuple((c['name'], c['active']) for c in m['cards']))

    def render(m):
        for c in dyn.get_children():
            dyn.remove(c)
            c.destroy()
        S['widgets'] = {}
        S['upd'] = True
        try:
            heading('Ausgabe')
            if not m['sinks']:
                heading('  (keine Ausgabegeräte gefunden)')
            for d in m['sinks']:
                device_card(d)
            heading('Eingabe (Mikrofon-Pegel)')
            if not m['sources']:
                heading('  (keine Eingabegeräte gefunden)')
            for d in m['sources']:
                device_card(d)
            heading('Lautstärke je App')
            if m['streams']:
                for s in m['streams']:
                    stream_card(s)
            else:
                row, _ = row_frame('Zurzeit gibt keine App Ton aus.' if m['backend'] == 'pactl'
                                   else 'Lautstärke je App ist nur mit „pactl“ (pipewire-pulse) verfügbar.')
                dyn.pack_start(row, False, False, 0)
            if m['cards']:
                heading('Soundprofile')
                for c in m['cards']:
                    card_row(c)
        finally:
            S['upd'] = False
        dyn.show_all()

    def apply_model(m, err):
        S['loading'] = False
        if m is None:
            notice.set_text(err or 'Audio nicht verfügbar.')
            notice.show()
            S['model'] = None
            S['sig'] = None
            for c in dyn.get_children():
                dyn.remove(c)
                c.destroy()
            return False
        notice.set_text('' if m['backend'] == 'pactl' else 'Hinweis: „pactl“ fehlt, es wird der Rückfall „wpctl“ benutzt (ohne Apps, Balance und Soundprofile).')
        S['model'] = m
        sig = signature(m)
        now = GLib.get_monotonic_time()
        if sig != S['sig']:
            if any(now - t < 2000000 for t in S['dirty'].values()):
                return False        # gerade am Regler: Neuaufbau später
            S['sig'] = sig
            render(m)
        else:
            items = {d['kind'] + ':' + d['id']: d for d in m['sinks'] + m['sources']}
            items.update({'stream:' + s['id']: dict(s, balance=0.0) for s in m['streams']})
            for key, w in S['widgets'].items():
                if key in items and now - S['dirty'].get(key, 0) > 2000000:
                    set_state(w, items[key])
        return False

    def refresh(*_):
        if S['loading']:
            return False
        S['loading'] = True

        def work():
            try:
                m, err = collect(lambda a, timeout=TIMEOUT: app.run_tool(a, timeout=timeout))
            except Exception as e:      # Parser darf die Seite nie zum Absturz bringen
                m, err = None, 'Audio konnte nicht gelesen werden: %r' % (e,)
            GLib.idle_add(apply_model, m, err)
        threading.Thread(target=work, daemon=True).start()
        return False

    def on_boost(sw, _p):
        S['boost'] = sw.get_active()
        S['sig'] = None
        refresh()
    boost_sw.connect('notify::active', on_boost)

    tick = {'id': 0}

    def on_map(_w):
        refresh()
        if not tick['id']:
            tick['id'] = GLib.timeout_add_seconds(3, lambda: (refresh(), True)[1])

    def on_unmap(_w):
        if tick['id']:
            GLib.source_remove(tick['id'])
            tick['id'] = 0
    box.connect('map', on_map)
    box.connect('unmap', on_unmap)
    notice.set_text('Audio wird gelesen …')
