# Weitere Einstellungsseiten

Jede Datei `page_<name>.py` hier ist eine Seite der Aurora-Einstellungen. Sie wird beim Start geladen, ein Fehler in einer Seite betrifft nur diese Seite (Meldung auf stderr).

Ein Modul liefert:

```python
TITLE = 'Ton'                       # Seitenname (eindeutig, auch Name in der Seitenleiste)
GROUP = 'SYSTEM'                    # Seitenleisten-Gruppe: ALLGEMEIN, PROGRAMME, DARSTELLUNG, SYSTEM oder eine neue
ICONS = ['audio-volume-high-symbolic']   # Symbolnamen (erstes vorhandenes wird genommen)
ORDER = 100                         # Reihenfolge innerhalb der Gruppe (kleiner = weiter oben)

def build(app):
    box = app.page(TITLE, 'Kurzbeschreibung (wird auch durchsucht)')
    app.row(box, 'Titel', widget, 'Beschreibung')       # Zeile mit Bedienelement
    app.button(box, 'Titel', 'Knopf', callback, 'Beschreibung')
    app.run_tool([...], timeout=10)                      # Programm mit Zeitlimit (nie blockieren)
```

Regeln: nie die UI-Schleife blockieren (lange Aufrufe in Threads, Ergebnis per `GLib.idle_add`), jedes externe Programm mit Zeitlimit und mit Prüfung, ob es existiert; Einstellungen nur schreiben, wenn der Nutzer etwas ändert; Dateien atomar ersetzen; Eingaben validieren; Texte auf Deutsch.
