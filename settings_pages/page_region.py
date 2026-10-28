"""Aurora-Einstellungen: Region & Sprache (localectl)."""
import os, sys, re, json
_d = os.path.dirname(os.path.realpath(__file__))
if _d not in sys.path:
    sys.path.insert(0, _d)
import dx_sysutil as U

TITLE = 'Region & Sprache'
GROUP = 'SYSTEM'
ICONS = ['preferences-desktop-locale-symbolic', 'preferences-desktop-language-symbolic', 'preferences-desktop-keyboard-symbolic']
ORDER = 30

# Variable -> (Titel, Beschreibung)
CATEGORIES = [
    ('LANG', 'Systemsprache', 'Sprache der Menüs, Meldungen und Programme.'),
    ('LC_NUMERIC', 'Zahlen', 'Dezimal- und Tausendertrennzeichen.'),
    ('LC_TIME', 'Datum und Uhrzeit', 'Schreibweise von Datum, Wochentagen und Uhrzeit.'),
    ('LC_MONETARY', 'Währung', 'Währungssymbol und Schreibweise von Beträgen.'),
    ('LC_PAPER', 'Papierformat', 'Standardpapier beim Drucken (A4, Letter).'),
]
VARS = [c[0] for c in CATEGORIES]
_LOCALE_RE = re.compile(r'^[A-Za-z]{2,3}(_[A-Za-z0-9]{2,})?(\.[A-Za-z0-9\-]+)?(@[A-Za-z0-9]+)?$|^C(\.[A-Za-z0-9\-]+)?$|^POSIX$')

# ---------- reine Logik ----------

def parse_localectl_status(text):
    """`localectl status` -> {'locale': {VAR: Wert}, 'keymap': .., 'x11_layout': ..}. Robust gegen fehlende Zeilen."""
    res = {'locale': {}, 'keymap': None, 'x11_layout': None}
    in_locale = False
    for line in (text or '').splitlines():
        s = line.strip()
        m = re.match(r'System Locale:\s*(.*)$', s)
        if m:
            in_locale = True
            s = m.group(1)
        elif ':' in s and not re.match(r'^[A-Z_]+=', s):
            in_locale = False
            k, v = s.split(':', 1)
            if k.strip() == 'VC Keymap':
                res['keymap'] = v.strip() or None
            elif k.strip() == 'X11 Layout':
                res['x11_layout'] = v.strip() or None
            continue
        if in_locale:
            m = re.match(r'^([A-Z_]+)=(.*)$', s)
            if m:
                res['locale'][m.group(1)] = m.group(2).strip()
    return res


def parse_locale_list(text):
    return sorted({l.strip() for l in (text or '').splitlines() if _LOCALE_RE.match(l.strip())})


def parse_locale_gen(text):
    """Einträge in /etc/locale.gen (auch auskommentierte) -> Menge von 'de_DE.UTF-8'; nur zur Anzeige „erzeugbar“."""
    out = set()
    for line in (text or '').splitlines():
        m = re.match(r'^#?\s*([A-Za-z_]+(?:\.[A-Za-z0-9\-]+)?(?:@\w+)?)\s+[A-Za-z0-9\-]+\s*$', line)
        if m and '_' in m.group(1):
            out.add(m.group(1))
    return out


def locale_label(loc):
    """'de_DE.UTF-8' -> 'Deutsch (Deutschland) – de_DE.UTF-8' (nur wenige bekannte Namen, sonst die Kennung)."""
    langs = {'de': 'Deutsch', 'en': 'Englisch', 'fr': 'Französisch', 'es': 'Spanisch', 'it': 'Italienisch', 'nl': 'Niederländisch', 'pl': 'Polnisch',
             'pt': 'Portugiesisch', 'ru': 'Russisch', 'tr': 'Türkisch', 'ja': 'Japanisch', 'zh': 'Chinesisch', 'sv': 'Schwedisch', 'da': 'Dänisch',
             'cs': 'Tschechisch', 'C': 'Standard (C)'}
    lands = {'DE': 'Deutschland', 'AT': 'Österreich', 'CH': 'Schweiz', 'US': 'USA', 'GB': 'Vereinigtes Königreich', 'FR': 'Frankreich',
             'ES': 'Spanien', 'IT': 'Italien', 'NL': 'Niederlande', 'BE': 'Belgien', 'PL': 'Polen', 'PT': 'Portugal', 'BR': 'Brasilien',
             'CA': 'Kanada', 'AU': 'Australien', 'LU': 'Luxemburg', 'JP': 'Japan', 'CN': 'China', 'RU': 'Russland', 'TR': 'Türkei'}
    m = re.match(r'^([A-Za-z]+)(?:_([A-Za-z0-9]+))?', loc)
    if not m or m.group(1) not in langs:
        return loc
    name = langs[m.group(1)]
    if m.group(2):
        name += ' (%s)' % lands.get(m.group(2), m.group(2))
    return '%s – %s' % (name, loc)


def validate_selection(sel, available):
    """sel: {VAR: Locale oder ''}. Nur bekannte Variablen, nur Locales aus der Liste; LANG ist Pflicht. -> bereinigtes Dict, sonst ValueError."""
    avail = set(available)
    out = {}
    for k, v in (sel or {}).items():
        if k not in VARS:
            raise ValueError('Unbekannte Variable: %s' % k)
        if not v:
            continue
        if v not in avail:
            raise ValueError('Locale nicht installiert: %s' % v)
        out[k] = v
    if 'LANG' not in out:
        raise ValueError('Eine Systemsprache muss gewählt sein')
    return out


def build_set_locale(sel, available):
    """Alle gesetzten Variablen auf einmal (localectl ersetzt die gesamte Liste); abweichende Formate nur, wenn sie von LANG abweichen."""
    s = validate_selection(sel, available)
    args = ['localectl', 'set-locale', 'LANG=' + s['LANG']]
    for k in VARS[1:]:
        if k in s and s[k] != s['LANG']:
            args.append('%s=%s' % (k, s[k]))
    return U.pk(args)


def paper_name(height_mm, width_mm):
    try:
        h, w = int(height_mm), int(width_mm)
    except (TypeError, ValueError):
        return '?'
    return {(297, 210): 'A4', (420, 297): 'A3', (279, 216): 'Letter', (356, 216): 'Legal', (216, 279): 'Letter'}.get((h, w), '%d × %d mm' % (h, w))


_PREVIEW_PY = r'''
import locale, json, datetime, sys
loc = sys.argv[1:]
cats = [locale.LC_NUMERIC, locale.LC_TIME, locale.LC_MONETARY, locale.LC_MESSAGES]
res = {}
def setl(c, l):
    try:
        locale.setlocale(c, l); return True
    except locale.Error:
        return False
res['num'] = res['date'] = res['cur'] = None
if loc[0] and setl(locale.LC_NUMERIC, loc[0]): res['num'] = locale.format_string('%.2f', 1234567.891, grouping=True)
if loc[1] and setl(locale.LC_TIME, loc[1]):
    d = datetime.datetime(2026, 3, 9, 14, 5, 7); res['date'] = d.strftime('%A, %x  %X')
if loc[2] and setl(locale.LC_MONETARY, loc[2]):
    try: res['cur'] = locale.currency(1234.5, grouping=True)
    except Exception: res['cur'] = None
print(json.dumps(res))
'''


def preview(sel, timeout=6):
    """Vorschau der Formate in einem Kindprozess (setlocale ist prozessweit, nie im GTK-Prozess). -> Dict mit num/date/cur/paper (oder None)."""
    lang = sel.get('LANG', '')
    args = [sel.get('LC_NUMERIC') or lang, sel.get('LC_TIME') or lang, sel.get('LC_MONETARY') or lang]
    if not all(_LOCALE_RE.match(a) for a in args if a):
        return {}
    rc, out, _ = U.run([sys.executable, '-I', '-c', _PREVIEW_PY] + args, timeout=timeout)
    res = {}
    if rc == 0:
        try:
            res = json.loads(out.strip().splitlines()[-1])
        except (ValueError, IndexError):
            res = {}
    pl = sel.get('LC_PAPER') or lang
    if pl and _LOCALE_RE.match(pl):
        env = dict(os.environ, LC_ALL=pl)
        rc, h, _ = U.run(['locale', '-c', 'LC_PAPER'], env=env)
        vals = [x for x in h.split() if x.lstrip('-').isdigit()]
        if rc == 0 and len(vals) >= 2:
            res['paper'] = paper_name(vals[0], vals[1])
    return res


# ---------- Seite ----------

def build(app):
    from gi.repository import Gtk
    box = app.page(TITLE, 'Systemsprache und Formate für Zahlen, Datum, Währung und Papier.')
    state = {'avail': [], 'current': {}, 'busy': False}
    lbl = U.info_label('Lese Spracheinstellungen …')
    app.row(box, 'Aktuell eingestellt', lbl, 'Laut localectl.')
    selects = {}
    for var, title, desc in CATEGORIES:
        w = U.make_select([('', 'wie Systemsprache')] if var != 'LANG' else [])
        selects[var] = w
        app.row(box, title, w, desc)
    prev = U.info_label('')
    app.row(box, 'Vorschau', prev, 'So sehen Zahlen, Datum, Währung und Papierformat mit der Auswahl aus.')
    note = U.info_label('Die Änderung gilt erst nach einer neuen Anmeldung (abmelden und wieder anmelden). Fehlt eine Sprache in der Liste, muss sie '
                        'zuerst in /etc/locale.gen aktiviert und mit „locale-gen“ erzeugt werden (Administratorrechte, nicht Teil dieser Seite).')
    note.get_style_context().add_class('row-desc')
    box.pack_start(note, False, False, 0)

    def selection():
        return {v: (w.get_active_id() or '') for v, w in selects.items()}

    def update_preview(*_):
        sel = selection()
        if not sel.get('LANG'):
            return

        def done(res):
            if isinstance(res, Exception) or not res:
                prev.set_text('Vorschau nicht verfügbar.')
                return
            lines = ['Zahl: %s' % (res.get('num') or '–'), 'Datum/Zeit: %s' % (res.get('date') or '–'),
                     'Währung: %s' % (res.get('cur') or '–'), 'Papier: %s' % (res.get('paper') or '–')]
            prev.set_text('\n'.join(lines))
        U.bg(lambda: preview(sel), done)

    apply_btn = Gtk.Button(label='Übernehmen')
    apply_btn.set_halign(Gtk.Align.START)

    def apply(*_):
        if state['busy']:
            return
        try:
            args = build_set_locale(selection(), state['avail'])
        except ValueError as e:
            app.message(str(e))
            return
        state['busy'] = True
        app.message('Warte auf Berechtigung …')

        def done(res):
            state['busy'] = False
            if isinstance(res, Exception):
                app.message('Fehler: %s' % res)
            elif res[0] == 0:
                app.message('Gespeichert. Bitte neu anmelden, damit es überall gilt.')
                load()
            else:
                app.message('Nicht geändert (%s)' % ((res[2] or '').strip().splitlines()[-1:] or ['abgebrochen'])[0])
        U.bg(lambda: U.run(args, timeout=120), done)
    apply_btn.connect('clicked', apply)
    app.row(box, 'Änderung speichern', apply_btn, 'Setzt die Auswahl systemweit (localectl set-locale). Braucht Administratorrechte; neu anmelden danach.')

    def load():
        def work():
            rc, out, _ = U.run(['localectl', 'status'])
            if rc != 0:
                return None
            st = parse_localectl_status(out)
            rc2, out2, _ = U.run(['localectl', 'list-locales'])
            avail = parse_locale_list(out2) if rc2 == 0 else []
            if not avail:
                try:
                    avail = sorted(parse_locale_gen(open('/etc/locale.gen', encoding='utf-8', errors='replace').read()))
                except OSError:
                    avail = []
            return st, avail

        def done(res):
            if not isinstance(res, tuple):
                lbl.set_text('localectl ist nicht verfügbar – Sprache kann hier nicht gelesen oder geändert werden.')
                return
            st, avail = res
            state['avail'], state['current'] = avail, st['locale']
            loc = st['locale']
            lbl.set_text(('%s · Tastaturbelegung: %s' % (locale_label(loc.get('LANG', '–')), st.get('keymap') or st.get('x11_layout') or 'unbekannt'))
                         + ('\nAbweichende Formate: ' + ', '.join('%s=%s' % kv for kv in loc.items() if kv[0] != 'LANG') if len(loc) > 1 else ''))
            for var, w in selects.items():
                if hasattr(w, 'clear'):
                    w.clear()
                    if var != 'LANG':
                        w.append('', 'wie Systemsprache')
                    for l in avail:
                        w.append(l, locale_label(l))
                else:
                    w.remove_all()
                    if var != 'LANG':
                        w.append('', 'wie Systemsprache')
                    for l in avail:
                        w.append(l, locale_label(l))
                cur = loc.get(var, '' if var != 'LANG' else (avail[0] if avail else ''))
                w.set_active_id(cur if cur in avail or cur == '' else '')
                if not state.get('connected'):
                    w.connect('changed', update_preview)
            state['connected'] = True
            update_preview()
        U.bg(work, done)
    load()
