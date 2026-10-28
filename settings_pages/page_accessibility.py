"""Aurora-Seite „Eingabehilfen“: Animationen reduzieren, Zeigergröße, Bildschirmlupe, hoher Kontrast, Bildschirmtastatur, Screenreader.
Werte landen in ~/.config/draconyx/input.json und werden von hypr/dx_input.lua angewendet."""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

TITLE = 'Eingabehilfen'
GROUP = 'SYSTEM'
ICONS = ['preferences-desktop-accessibility-symbolic', 'org.gnome.Settings-accessibility-symbolic']
ORDER = 22

OSK_PROGRAMS = ('wvkbd-mobintl', 'wvkbd-deskintl', 'squeekboard', 'onboard')


def high_contrast_active(colors_path):
    try:
        return json.loads(open(colors_path, encoding='utf-8').read()).get('preset') == 'kontrast'
    except (OSError, ValueError, AttributeError):
        return False


def current_preset(colors_path):
    try:
        p = json.loads(open(colors_path, encoding='utf-8').read()).get('preset')
        return p if p in ('aurora', 'draconyx') else 'aurora'
    except (OSError, ValueError, AttributeError):
        return 'aurora'


def build(app):
    from gi.repository import Gtk
    import shutil
    from pathlib import Path
    import dx_inputlib as lib
    import dx_inputui as ui

    saver = ui.Saver(app)
    box = app.page(TITLE, 'Hilfen für Sehen, Zeigen und Tippen: weniger Animationen, größerer Zeiger, Bildschirmlupe, hoher Kontrast, Bildschirmtastatur und Screenreader.')

    app.section(box, 'Sehen')
    ui.switch(app, saver, box, 'Animationen reduzieren', 'reduce_animations', False, 'Schaltet alle Fenster- und Arbeitsflächen-Animationen ab. Ruhiger und etwas schneller.')

    # Zeigergröße
    ui.spin(app, saver, box, 'Zeigergröße', 'cursor_size', 24, 'In Pixeln (16 bis 96, Standard 24). Gilt sofort für Hyprland; bereits laufende Programme übernehmen sie erst nach einem Neustart.')

    # Lupe
    zoom = ui.scale(app, saver, box, 'Bildschirmlupe', 'zoom_factor', 1.0, 'Vergrößerung des Bildschirms um den Mauszeiger (1,0 = aus, bis 10). Zurück auf 1,0 schaltet die Lupe ab.', step=0.25, digits=2, marks=(1.0, 2.0, 4.0))
    row = Gtk.Box(spacing=6)
    for text, f in (('Aus (1×)', 1.0), ('2×', 2.0), ('3×', 3.0), ('4×', 4.0)):
        b = Gtk.Button(label=text)
        b.connect('clicked', lambda *_, f=f: zoom.set_value(f))
        row.pack_start(b, False, False, 0)
    app.row(box, 'Lupe schnell wählen', row)
    ui.note(app, box, 'Die Lupe folgt dem Mauszeiger. Für eigene Skripte oder Tastenkombinationen gibt es den Befehl: hyprctl eval "DXInput.zoom(2)" (Faktor 1 bis 10, gilt bis zum nächsten Neuladen).')

    # hoher Kontrast
    colors = Path.home() / '.config/draconyx/colors.json'
    tool = Path.home() / '.local/bin/dx-colors'
    hc = Gtk.Switch(active=high_contrast_active(colors))
    st = {'busy': False}

    def hc_changed(w, _):
        if st['busy']:
            return
        target = 'kontrast' if w.get_active() else current_preset_before[0]
        if not tool.exists():
            app.message('dx-colors fehlt – Farbwelt kann nicht gewechselt werden.')
            return
        ui.run_async([str(tool), 'preset', target], lambda rc, o: app.message('Farbwelt: %s.' % ('Hoher Kontrast' if target == 'kontrast' else target) if rc == 0 else 'Farbwelt konnte nicht gewechselt werden.'), timeout=20)
    current_preset_before = [current_preset(colors)]
    hc.connect('notify::active', hc_changed)
    app.row(box, 'Hoher Kontrast', hc, 'Schwarzer Hintergrund, weiße Schrift, gelber Akzent für Taskleiste, Menüs und Aurora. Beim Ausschalten kehrt die Farbwelt „%s“ zurück (eigene Akzentfarben gehen dabei verloren).' % current_preset_before[0])

    app.section(box, 'Tippen')
    osk = next((p for p in OSK_PROGRAMS if shutil.which(p)), None)

    def start_osk(*_):
        try:
            subprocess.Popen([shutil.which(osk)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            app.message('Bildschirmtastatur gestartet.')
        except OSError as e:
            app.message('Bildschirmtastatur konnte nicht gestartet werden: %s' % e)
    b = Gtk.Button(label='Starten' if osk else 'Nicht installiert')
    b.set_sensitive(bool(osk))
    b.connect('clicked', start_osk)
    app.row(box, 'Bildschirmtastatur', b, ('Gefunden: %s.' % osk) if osk else 'Keine Bildschirmtastatur gefunden. Installiere z. B. „wvkbd“ (Arch: pacman -S wvkbd) oder „onboard“.')
    ui.note(app, box, 'Haftende Tasten und Verzögerte Tasten (AccessX) gibt es unter Wayland/Hyprland nicht: Weder Hyprland noch libinput kennen sie, und XKB bietet dafür keine Option. Als Ersatz hilft die Compose-Taste und eine längere Wiederholverzögerung auf der Seite „Tastatur“.')

    app.section(box, 'Screenreader')
    orca = shutil.which('orca')

    def start_orca(*_):
        try:
            subprocess.Popen([orca, '--replace'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            app.message('Orca gestartet.')
        except OSError as e:
            app.message('Orca konnte nicht gestartet werden: %s' % e)
    b = Gtk.Button(label='Orca starten' if orca else 'Nicht installiert')
    b.set_sensitive(bool(orca))
    b.connect('clicked', start_orca)
    app.row(box, 'Screenreader', b, 'Orca liest Programme laut vor, die Barrierefreiheit unterstützen (GTK, Qt, Firefox).' if orca else 'Orca ist nicht installiert (Arch: pacman -S orca). Die Draconyx-Shell selbst bietet keine Screenreader-Unterstützung.')

    app.section(box, 'Textgröße')
    ui.note(app, box, 'Eine globale Textskalierung gibt es in der Shell nicht. Schrift und Größen der Oberfläche wählst du unter „Farben & Schrift“.')

    ui.reset_button(app, saver, box, ['reduce_animations', 'cursor_size', 'zoom_factor'])
