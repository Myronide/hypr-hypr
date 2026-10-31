#!/usr/bin/python3
"""Hypr Hypr Notizen: Liste links, Editor rechts, speichert selbst. Jede Notiz ist eine Textdatei in ~/Documents/Draconyx-Notizen."""
import os, re, tempfile, time
from pathlib import Path
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib

DIR = Path.home() / "Documents" / "Draconyx-Notizen"


def write_note(path, text):
    """Atomar speichern (Temp-Datei + Ersetzen): ein Absturz mitten im Schreiben darf keine Notiz zerstören."""
    path = Path(path)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".notiz.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try: os.unlink(tmp)
        except OSError: pass
        raise


def title_of(text, fallback):
    for line in text.splitlines():
        if line.strip():
            return line.strip().lstrip("#").strip()[:60] or fallback
    return fallback


class Notes(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.draconyx.Notizen")
        self.win = None
        self.current = None
        self.save_id = 0
        self.loading = False

    def do_activate(self):
        if self.win:
            self.win.present(); return
        st = Gtk.Settings.get_default()
        st.set_property("gtk-application-prefer-dark-theme", True)
        css = Gtk.CssProvider()
        for p in (Path.home() / ".config/hypr/aurora/settings.css",):     # Aurora-Aussehen, falls vorhanden
            if p.exists():
                try: css.load_from_path(str(p))
                except GLib.Error: pass
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        try:
            DIR.mkdir(parents=True, exist_ok=True)
        except OSError as e:
            print("Notizen: Ordner nicht anlegbar:", e, flush=True)
        self.win = Gtk.ApplicationWindow(application=self, title="Notizen")
        self.win.set_default_size(900, 600)
        self.win.connect("delete-event", lambda *_: (self.flush(), False)[1])     # offene Eingabe beim Schließen sichern
        head = Gtk.HeaderBar(title="Notizen", show_close_button=True)
        self.win.set_titlebar(head)
        new = Gtk.Button(label="Neue Notiz"); new.get_style_context().add_class("suggested-action"); new.connect("clicked", self.new_note)
        dele = Gtk.Button(label="Löschen"); dele.connect("clicked", self.delete_note)
        head.pack_start(new); head.pack_end(dele)
        body = Gtk.Box(); self.win.add(body)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin=10); left.set_size_request(260, -1)
        self.search = Gtk.SearchEntry(placeholder_text="Suchen …"); self.search.connect("search-changed", lambda *_: self.refill())
        left.pack_start(self.search, False, False, 0)
        self.list = Gtk.ListBox(); self.list.connect("row-selected", self.on_select)
        sc = Gtk.ScrolledWindow(); sc.add(self.list); left.pack_start(sc, True, True, 0)
        body.pack_start(left, False, False, 0)
        self.view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=18, right_margin=18, top_margin=16, bottom_margin=16)
        self.buf = self.view.get_buffer(); self.buf.connect("changed", self.on_change)
        sc2 = Gtk.ScrolledWindow(); sc2.add(self.view); body.pack_start(sc2, True, True, 0)
        self.refill()
        if not self.list.get_children():
            self.new_note()
        else:
            self.list.select_row(self.list.get_row_at_index(0))
        self.win.show_all()

    def files(self):
        q = self.search.get_text().strip().lower()
        out = []
        try:
            names = list(DIR.glob("*.txt"))
        except OSError:
            names = []
        def mtime(p):
            try: return p.stat().st_mtime
            except OSError: return 0
        for f in sorted(names, key=lambda p: -mtime(p)):
            try: text = f.read_text(encoding="utf-8", errors="replace")
            except OSError: continue
            if q and q not in text.lower(): continue
            out.append((f, text))
        return out

    def refill(self, keep=None):
        for c in self.list.get_children():
            self.list.remove(c)
        for f, text in self.files():
            row = Gtk.ListBoxRow(); row.path = f
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, margin=8)
            t = Gtk.Label(label=title_of(text, "(leer)"), xalign=0); t.set_ellipsize(3)
            d = Gtk.Label(label=time.strftime("%d.%m.%Y %H:%M", time.localtime(mtime(f))), xalign=0)
            d.get_style_context().add_class("subtitle")
            box.pack_start(t, False, False, 0); box.pack_start(d, False, False, 0); row.add(box); self.list.add(row)
            if keep and f == keep:
                self.list.select_row(row)
        self.list.show_all()

    def on_select(self, lb, row):
        if not row or row.path == self.current: return     # gleiche Notiz (nach dem Speichern neu gewählt): Cursor nicht verlieren
        self.flush()
        self.current = row.path
        self.loading = True
        try: self.buf.set_text(row.path.read_text(encoding="utf-8", errors="replace"))
        except OSError: self.buf.set_text("")
        self.loading = False

    def on_change(self, *_):
        if self.loading or not self.current: return
        if self.save_id: GLib.source_remove(self.save_id)
        self.save_id = GLib.timeout_add(600, self.flush)

    def flush(self):
        if self.save_id:
            GLib.source_remove(self.save_id); self.save_id = 0
        if self.current and self.current.exists():
            start, end = self.buf.get_bounds()
            text = self.buf.get_text(start, end, True)
            try: old = self.current.read_text(encoding="utf-8", errors="replace")
            except OSError: old = None
            if text != old:
                try: write_note(self.current, text)
                except OSError as e:
                    print("Notizen: Speichern fehlgeschlagen:", e, flush=True); return False
                self.refill(keep=self.current)
        return False

    def new_note(self, *_):
        self.flush()
        f = DIR / ("Notiz-%s.txt" % time.strftime("%Y%m%d-%H%M%S"))
        try: write_note(f, "")
        except OSError as e:
            print("Notizen: Neue Notiz nicht anlegbar:", e, flush=True); return
        self.search.set_text("")
        self.refill(keep=f)
        self.view.grab_focus()

    def delete_note(self, *_):
        if not self.current: return
        d = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.QUESTION,
                              buttons=Gtk.ButtonsType.YES_NO, text="Diese Notiz löschen?")
        r = d.run(); d.destroy()
        if r == Gtk.ResponseType.YES:
            try: self.current.unlink(missing_ok=True)
            except OSError as e: print("Notizen: Löschen fehlgeschlagen:", e, flush=True)
            self.current = None
            self.refill()
            rows = self.list.get_children()
            if rows: self.list.select_row(rows[0])
            else: self.new_note()


if __name__ == "__main__":
    Notes().run(None)
