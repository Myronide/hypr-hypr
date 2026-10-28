"""Aurora-Einstellungen: Datum & Zeit (timedatectl, Uhr der Shell)."""
import os, sys, re
from datetime import datetime
_d = os.path.dirname(os.path.realpath(__file__))
if _d not in sys.path:
    sys.path.insert(0, _d)
import dx_sysutil as U

TITLE = 'Datum & Zeit'
GROUP = 'SYSTEM'
ICONS = ['preferences-system-time-symbolic', 'appointment-symbolic', 'x-office-calendar-symbolic']
ORDER = 20

# ---------- reine Logik (ohne Display testbar) ----------

def parse_timedatectl_show(text):
    """Ausgabe von `timedatectl show` -> Wörterbuch mit festen Schlüsseln (fehlende Angaben None)."""
    kv = U.parse_kv(text)
    yes = lambda k: None if k not in kv else kv[k].lower() == 'yes'
    return {
        'timezone': kv.get('Timezone') or None,
        'ntp': yes('NTP'), 'can_ntp': yes('CanNTP'), 'synced': yes('NTPSynchronized'), 'local_rtc': yes('LocalRTC'),
        'time': kv.get('TimeUSec') or None, 'rtc_time': kv.get('RTCTimeUSec') or None,
    }


def parse_timezones(text):
    """`timedatectl list-timezones` -> sortierte Liste gültiger Namen (Zeilen mit Leerzeichen/Müll werden ignoriert)."""
    ok = re.compile(r'^[A-Za-z0-9_+\-]+(/[A-Za-z0-9_+\-]+){0,2}$')
    return sorted({l.strip() for l in (text or '').splitlines() if ok.match(l.strip())})


def validate_timezone(tz, zones):
    return isinstance(tz, str) and tz in set(zones)


def validate_date(text):
    """Strikt JJJJ-MM-TT (auch TT.MM.JJJJ) -> 'JJJJ-MM-TT' oder None."""
    t = (text or '').strip()
    m = re.fullmatch(r'(\d{4})-(\d{2})-(\d{2})', t) or None
    if m:
        y, mo, d = map(int, m.groups())
    else:
        m = re.fullmatch(r'(\d{2})\.(\d{2})\.(\d{4})', t)
        if not m:
            return None
        d, mo, y = map(int, m.groups())
    try:
        datetime(y, mo, d)
    except ValueError:
        return None
    if y < 1970 or y > 2200:
        return None
    return '%04d-%02d-%02d' % (y, mo, d)


def validate_time(text):
    """Strikt HH:MM oder HH:MM:SS (24 h) -> 'HH:MM:SS' oder None."""
    m = re.fullmatch(r'(\d{1,2}):(\d{2})(?::(\d{2}))?', (text or '').strip())
    if not m:
        return None
    h, mi, s = int(m.group(1)), int(m.group(2)), int(m.group(3) or 0)
    if h > 23 or mi > 59 or s > 59:
        return None
    return '%02d:%02d:%02d' % (h, mi, s)


def build_set_time(date_text, time_text):
    d, t = validate_date(date_text), validate_time(time_text)
    if not d or not t:
        raise ValueError('Datum oder Uhrzeit ungültig')
    return U.pk(['timedatectl', 'set-time', '%s %s' % (d, t)])


def build_set_timezone(tz, zones):
    if not validate_timezone(tz, zones):
        raise ValueError('Unbekannte Zeitzone')
    return U.pk(['timedatectl', 'set-timezone', tz])


def build_set_ntp(on):
    return U.pk(['timedatectl', 'set-ntp', 'true' if on else 'false'])


def shell_clock_changes(show_seconds=None, show_date=None):
    ch = {}
    if show_seconds is not None:
        ch['showSeconds'] = bool(show_seconds)
    if show_date is not None:
        ch['showDate'] = bool(show_date)
    return ch


# ---------- Seite ----------

def build(app):
    from gi.repository import Gtk, GLib
    box = app.page(TITLE, 'Uhrzeit, Zeitzone, automatische Zeit (NTP) und Anzeige der Uhr in der Taskleiste.')
    state = {'info': {}, 'zones': [], 'busy': False}

    now = U.info_label('', False)
    now.get_style_context().add_class('row-title')
    app.row(box, 'Aktuelle Zeit', now, 'Systemzeit in der eingestellten Zeitzone.')
    status = U.info_label('Lese Zeitangaben …')
    app.row(box, 'Zeitzone und Synchronisation', status, 'Stand laut timedatectl.')
    hw = U.info_label('–')
    app.row(box, 'Hardware-Uhr (RTC)', hw, 'Nur Anzeige. Linux speichert sie normalerweise in UTC.')

    def tick():
        now.set_text(datetime.now().astimezone().strftime('%A, %d.%m.%Y  %H:%M:%S  (%Z)'))
        return True
    tick()
    GLib.timeout_add_seconds(1, tick)

    def run_priv(args, ok_text):
        if state['busy']:
            return
        state['busy'] = True
        app.message('Warte auf Berechtigung …')

        def done(res):
            state['busy'] = False
            if isinstance(res, Exception):
                app.message('Fehler: %s' % res)
            elif res[0] == 0:
                app.message(ok_text)
            elif res[0] in (126, 127) and 'nicht gefunden' in res[2]:
                app.message('Nicht möglich: %s' % res[2])
            else:
                app.message('Nicht geändert (%s)' % ((res[2] or '').strip().splitlines()[-1:] or ['abgebrochen'])[0])
            refresh()
        U.bg(lambda: U.run(args, timeout=120), done)

    # Automatische Zeit
    sw = Gtk.Switch()
    sw.set_valign(Gtk.Align.CENTER)
    guard = {'lock': False}

    def on_ntp(w, _):
        if guard['lock']:
            return
        run_priv(build_set_ntp(w.get_active()), 'Automatische Zeit %s.' % ('eingeschaltet' if w.get_active() else 'ausgeschaltet'))
    sw.connect('notify::active', on_ntp)
    app.row(box, 'Zeit automatisch einstellen', sw, 'Gleicht die Uhr über das Netzwerk ab (NTP). Bei „aus“ lässt sich die Zeit von Hand setzen. Änderung braucht Administratorrechte.')

    # Zeitzone: durchsuchbare Liste
    tzbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    search = Gtk.SearchEntry()
    search.set_placeholder_text('Zeitzone suchen, z. B. Berlin')
    store = Gtk.ListStore(str)
    flt = store.filter_new()
    flt.set_visible_func(lambda m, it, _: search.get_text().strip().lower().replace(' ', '_') in m[it][0].lower())
    tv = Gtk.TreeView(model=flt)
    tv.set_headers_visible(False)
    tv.append_column(Gtk.TreeViewColumn('Zeitzone', Gtk.CellRendererText(), text=0))
    sc = Gtk.ScrolledWindow()
    sc.set_min_content_height(190)
    sc.set_max_content_height(190)
    sc.add(tv)
    search.connect('search-changed', lambda e: flt.refilter())
    apply_tz = Gtk.Button(label='Zeitzone übernehmen')
    apply_tz.set_halign(Gtk.Align.START)

    def do_tz(*_):
        m, it = tv.get_selection().get_selected()
        if not it:
            app.message('Bitte zuerst eine Zeitzone auswählen.')
            return
        try:
            args = build_set_timezone(m[it][0], state['zones'])
        except ValueError as e:
            app.message(str(e))
            return
        run_priv(args, 'Zeitzone gesetzt: %s' % m[it][0])
    apply_tz.connect('clicked', do_tz)
    for w in (search, sc, apply_tz):
        tzbox.pack_start(w, False, False, 0)
    app.row(box, 'Zeitzone', tzbox, 'Nur Zonen aus der Systemliste. Änderung braucht Administratorrechte.')

    # manuell
    mbox = Gtk.Box(spacing=8)
    de = Gtk.Entry()
    de.set_width_chars(12)
    de.set_placeholder_text('JJJJ-MM-TT')
    te = Gtk.Entry()
    te.set_width_chars(10)
    te.set_placeholder_text('HH:MM:SS')
    setb = Gtk.Button(label='Setzen')
    for w in (de, te, setb):
        mbox.pack_start(w, False, False, 0)

    def do_set(*_):
        try:
            args = build_set_time(de.get_text(), te.get_text())
        except ValueError:
            app.message('Datum (JJJJ-MM-TT oder TT.MM.JJJJ) oder Uhrzeit (HH:MM[:SS], 24 h) ist ungültig.')
            return
        run_priv(args, 'Zeit gesetzt.')
    setb.connect('clicked', do_set)
    app.row(box, 'Zeit und Datum von Hand setzen', mbox, 'Nur möglich, wenn „Zeit automatisch einstellen“ aus ist. Vorbelegt mit der aktuellen Zeit.')

    # Uhr der Shell
    app.section(box, 'Uhr in der Taskleiste')
    ssw = Gtk.Switch(active=bool(U.shell_get('showSeconds', False)))
    dsw = Gtk.Switch(active=bool(U.shell_get('showDate', True)))

    def write(ch):
        try:
            U.shell_update(ch)
            app.message('Uhr gespeichert.')
        except (OSError, ValueError) as e:
            app.message('Shell-Einstellung nicht gespeichert: %s' % e)
    ssw.connect('notify::active', lambda w, _: write(shell_clock_changes(show_seconds=w.get_active())))
    dsw.connect('notify::active', lambda w, _: write(shell_clock_changes(show_date=w.get_active())))
    app.row(box, 'Sekunden anzeigen', ssw, 'Die Uhr der Taskleiste zeigt Stunden:Minuten:Sekunden.')
    app.row(box, 'Datum anzeigen', dsw, 'Datum (TT.MM.JJJJ) unter der Uhrzeit.')
    note = U.info_label('Die Taskleiste zeigt die Zeit fest im 24-Stunden-Format und das Datum als TT.MM.JJJJ; ein 12-Stunden-Format oder anderes Datumsformat gibt es in der Shell noch nicht.')
    note.get_style_context().add_class('row-desc')
    box.pack_start(note, False, False, 0)

    # Auffrischen
    def refresh():
        def work():
            rc, out, _ = U.run(['timedatectl', 'show'])
            if rc != 0:
                return None
            return parse_timedatectl_show(out)

        def done(info):
            if not isinstance(info, dict):
                status.set_text('timedatectl ist nicht verfügbar – Zeiteinstellungen können hier nicht gelesen oder geändert werden.')
                return
            state['info'] = info
            ntp = info.get('ntp')
            status.set_text('%s · %s' % (info.get('timezone') or 'Zeitzone unbekannt',
                'Synchronisiert' if info.get('synced') else ('Automatische Zeit an, noch nicht synchronisiert' if ntp else 'Automatische Zeit aus')))
            hw.set_text('%s%s' % (info.get('rtc_time') or 'nicht verfügbar', '  (Ortszeit!)' if info.get('local_rtc') else ''))
            guard['lock'] = True
            sw.set_active(bool(ntp))
            sw.set_sensitive(info.get('can_ntp') is not False)
            guard['lock'] = False
            for w in (de, te, setb):
                w.set_sensitive(not ntp)
            if not de.get_text():
                n = datetime.now()
                de.set_text(n.strftime('%Y-%m-%d'))
                te.set_text(n.strftime('%H:%M:%S'))
        U.bg(work, done)
    refresh()

    def load_zones():
        def work():
            rc, out, _ = U.run(['timedatectl', 'list-timezones'], timeout=10)
            return parse_timezones(out) if rc == 0 else []

        def done(zs):
            if isinstance(zs, Exception) or not zs:
                return
            state['zones'] = zs
            for z in zs:
                store.append([z])
            cur = state['info'].get('timezone')
            if cur in zs:
                for i, r in enumerate(flt):
                    if r[0] == cur:
                        tv.set_cursor(Gtk.TreePath(i))
                        break
        U.bg(work, done)
    load_zones()
