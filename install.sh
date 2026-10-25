#!/usr/bin/env bash
# Draconyx / Aurora – Einrichtung auf einem Arch-System mit Hyprland 0.56.x
#   ./install.sh            alles einrichten (fragt vor Paketen und überschreibt nichts Eigenes)
#   ./install.sh --no-we    ohne Wallpaper Engine bauen
#   ./install.sh --ask      vor Paketinstallationen nachfragen (Standard: alles automatisch)
#   ./install.sh --restart  Shell und Hyprland-Konfiguration auch ohne Änderungen neu laden
#   ./install.sh --no-packages   keine Pakete installieren
#   ./install.sh --force    Wallpaper Engine auch ohne Änderung neu bauen
# Mehrfach ausführen ist ungefährlich: es wird nur angewendet, was neu oder geändert ist.
# Danach: in Hyprland neu anmelden (oder `qs -c draconyx` starten).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------- 0. Sicherheitstor: nur mit sudo
# Der Installer ändert deine Konfiguration und startet die Shell neu – deshalb läuft er nur nach einer sudo-Freigabe
# (versehentliche Aufrufe, auch durch Skripte oder KI-Werkzeuge, laufen so ins Leere).
#   sudo ./install.sh       → wird automatisch als dein normaler Benutzer weitergeführt (Dateien gehören dir, nicht root)
#   ./install.sh            → verlangt zuerst das sudo-Passwort
if [ "$(id -u)" -eq 0 ]; then
  if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = root ]; then
    echo "Bitte nicht als root anmelden, sondern als normaler Benutzer:  sudo ./install.sh" >&2; exit 1
  fi
  UID_REAL="$(id -u "$SUDO_USER")"
  exec sudo -u "$SUDO_USER" -H env DX_VIA_SUDO=1 XDG_RUNTIME_DIR="/run/user/$UID_REAL" \
       ${DX_NO_START:+DX_NO_START="$DX_NO_START"} "${BASH_SOURCE[0]}" "$@"
fi
if [ "${DX_VIA_SUDO:-0}" != 1 ]; then
  printf '\033[1;33m!!\033[0m  Zur Sicherheit brauche ich die sudo-Freigabe (der Installer ändert deine Konfiguration).\n'
  sudo -v || { echo "Abgebrochen: keine sudo-Freigabe." >&2; exit 1; }
fi
REPO="$HERE"
CONF="$HOME/.config"
DO_WE=1; ASSUME_YES=1; DO_PKGS=1; FORCE=0; CHANGED=0; RESTART=0
for a in "$@"; do case "$a" in --no-we) DO_WE=0;; --force) FORCE=1;; --yes|-y) ASSUME_YES=1;; --ask) ASSUME_YES=0;; --restart) RESTART=1;; --no-packages) DO_PKGS=0;; esac; done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
ask()  { [ "$ASSUME_YES" = 1 ] && return 0; read -r -p "$1 [j/N] " r; [[ "$r" =~ ^[jJyY] ]]; }
# Eigene Einstellungen werden nie überschrieben. Zur Sicherheit wandert alles, was der Installer ersetzt, vorher hierhin:
BACKUP="$HOME/.local/share/draconyx-backups/install-$(date +%Y%m%d-%H%M%S)"
backup_file() {   # backup_file DATEI  (Pfad bleibt unter dem Sicherungsordner erhalten)
  local f="$1"; [ -e "$f" ] || return 0
  local rel="${f#$HOME/}"; mkdir -p "$BACKUP/$(dirname "$rel")" && cp -a "$f" "$BACKUP/$rel" 2>/dev/null || true
}
# put QUELLE ZIEL [MODUS]: kopiert nur, wenn die Datei neu oder anders ist
put() {
  local src="$1" dst="$2" mode="${3:-644}"
  if [ -e "$dst" ] && cmp -s "$src" "$dst"; then chmod "$mode" "$dst" 2>/dev/null || true; return 0; fi   # Inhalt gleich: nur den Modus (ausführbar?) sicherstellen
  backup_file "$dst"
  install -D -m"$mode" "$src" "$dst"; CHANGED=$((CHANGED+1)); echo "    aktualisiert: ${dst/#$HOME/~}"
}

# ---------------------------------------------------------------- 0b. Berechtigungen
# Dateien, die früher durch ein "sudo" root gehören (oder nicht beschreibbar sind), werden dem Benutzer zurückgegeben,
# damit der Installer und die Shell überall schreiben können.
for d in "$CONF/hypr" "$CONF/quickshell" "$CONF/draconyx" "$HOME/.local/bin" "$HOME/.local/share/draconyx-hypr" \
         "$HOME/.local/state/draconyx" "$HOME/.local/opt" "$HOME/.local/src" "$HOME/.cache/aurora" "$HOME/.cache/draconyx"; do
  [ -e "$d" ] || continue
  if [ -n "$(find "$d" -maxdepth 5 \( -user root -o ! -writable \) -print -quit 2>/dev/null)" ]; then
    say "Berechtigungen reparieren: ${d/#$HOME/~}"
    sudo chown -R "$(id -un):$(id -gn)" "$d" && chmod -R u+rwX "$d" || warn "Konnte Berechtigungen für $d nicht setzen."
  fi
done
mkdir -p "$CONF/hypr" "$CONF/quickshell" "$CONF/draconyx" "$HOME/.local/bin" "$HOME/.local/state/draconyx" "$HOME/.local/share/draconyx-hypr" "$HOME/.cache/aurora"
for need in "$CONF/hypr" "$CONF/quickshell" "$HOME/.local/bin"; do
  [ -w "$need" ] || { echo "Kein Schreibzugriff auf $need – bitte prüfen." >&2; exit 1; }
done

# ---------------------------------------------------------------- 0c. Einstellungen sichern (nur kopieren, nichts wird verändert)
for f in "$CONF/draconyx/terminal" "$CONF/draconyx/window-mode" "$CONF/draconyx/colors.json" "$CONF/draconyx/modifier" "$CONF/draconyx/binds.conf" \
         "$HOME/.local/state/draconyx/settings.json" "$CONF/hypr/aurora/preferences.json" "$CONF/hypr/aurora/preferences.lua" \
         "$CONF/hypr/aurora/palette.css" "$CONF/hypr/hyprland.lua" "$CONF/hypr/monitors_local.lua" "$HOME/.config/brave-flags.conf"; do
  backup_file "$f"
done
[ -d "$BACKUP" ] && say "Einstellungen gesichert in ${BACKUP/#$HOME/~}"

# ---------------------------------------------------------------- 1. Pakete
PKGS=(quickshell jq python python-gobject python-pillow gtk3 grim wl-clipboard zenity xdotool git rsync ttf-inter papirus-icon-theme
      kitty ghostty dolphin swaync hypridle hyprlock cliphist plocate)
WE_PKGS=(base-devel cmake glm sdl2 wayland-protocols ffmpeg mpv glfw glew freeglut lz4 libpulse libcups at-spi2-core
         nss libxcomposite libxdamage nspr libxrandr)
missing=()
for p in "${PKGS[@]}" $([ "$DO_WE" = 1 ] && echo "${WE_PKGS[@]}"); do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ "$DO_PKGS" = 1 ] && [ "${#missing[@]}" -gt 0 ]; then
  say "Fehlende Pakete: ${missing[*]}"
  if ask "Mit sudo pacman installieren?"; then sudo pacman -S --needed --noconfirm "${missing[@]}" || warn "Einige Pakete ließen sich nicht installieren – bitte von Hand nachholen."
  else warn "Übersprungen. Ohne diese Pakete funktionieren Teile nicht."; fi
fi

# ---------------------------------------------------------------- 2. Dateien
say "Shell (Quickshell) nach $CONF/quickshell/draconyx"
mkdir -p "$CONF/quickshell/draconyx" "$HOME/.local/bin" "$HOME/.local/state/draconyx" "$CONF/draconyx" "$HOME/.local/share/draconyx-hypr"
n=$(rsync -ai --exclude 'icons-src' --exclude 'logo-*.png' "$HERE/quickshell/" "$CONF/quickshell/draconyx/" | grep -c '^>f' || true)
[ "$n" -gt 0 ] && { echo "    $n Shell-Dateien aktualisiert"; CHANGED=$((CHANGED+n)); } || echo "    Shell ist aktuell"
rsync -a --delete "$HERE/quickshell/icons-src/" "$HOME/.local/share/draconyx-hypr/qs-icons-src/"
cp -n "$HERE"/quickshell/logo-*.png "$HOME/.local/share/draconyx-hypr/" 2>/dev/null || true

say "Hilfsskripte nach ~/.local/bin"
for f in "$HERE"/bin/dx-*; do put "$f" "$HOME/.local/bin/$(basename "$f")" 755; done
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "~/.local/bin ist nicht im PATH.";; esac

hv="$(hyprland --version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+' | head -1 | tr -d v)"
if [ -n "$hv" ] && [ "$(printf '%s\n0.55\n' "$hv" | sort -V | head -1)" != "0.55" ]; then
  warn "Deine Hyprland-Version ($hv) kennt noch keine Lua-Konfiguration (ab 0.55) – Draconyx braucht ein Update von Hyprland."
fi
say "Hyprland-Module nach $CONF/hypr (bestehende Dateien bleiben)"
mkdir -p "$CONF/hypr"
for f in dx_snap.lua dx_tiling.lua dx_zones.lua dx_binds.lua csd-apps; do put "$HERE/hypr/$f" "$CONF/hypr/$f" 644; done
# Monitore: NICHT automatisch aktiv schalten (die Vorlage stammt von SyntaxJasons Rechner). Eigene Datei bleibt unangetastet.
put "$HERE/hypr/monitors_local.lua.example" "$CONF/hypr/monitors_local.lua.example" 644
if [ -e "$CONF/hypr/hyprland.lua" ] && cmp -s "$HERE/hypr/hyprland.lua" "$CONF/hypr/hyprland.lua"; then
  :   # schon unsere hyprland.lua
elif [ -e "$CONF/hypr/hyprland.lua" ] && ! grep -qE 'aurora|draconyx|dx_binds' "$CONF/hypr/hyprland.lua"; then
  # Reine Hyprland-Standardkonfiguration (nichts von Aurora/Draconyx darin): ohne unsere Datei würde sich gar nichts ändern.
  # Deshalb ersetzen wir sie – die alte Datei wird vorher gesichert, und ihre Monitor-Einstellungen übernehmen wir.
  say "Reine Hyprland-Konfiguration gefunden – Draconyx wird eingerichtet (Sicherung der alten: $BACKUP)"
  backup_file "$CONF/hypr/hyprland.lua"
  if [ ! -e "$CONF/hypr/monitors_local.lua" ]; then
    python3 -I - "$CONF/hypr/hyprland.lua" "$CONF/hypr/monitors_local.lua" <<'PY' || true
import re, sys
src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
out, i = [], 0
while True:
    m = re.search(r"hl\.monitor\s*\(", src[i:])
    if not m: break
    a = i + m.start(); j = i + m.end(); depth = 1
    while j < len(src) and depth:
        depth += {"(": 1, ")": -1}.get(src[j], 0); j += 1
    out.append(src[a:j]); i = j
if out:
    open(sys.argv[2], "w").write("-- Monitore aus deiner vorherigen hyprland.lua übernommen\n" + "\n".join(out) + "\n")
    print("    Monitor-Einstellungen übernommen:", len(out))
PY
  fi
  cp "$HERE/hypr/hyprland.lua" "$CONF/hypr/hyprland.lua"; CHANGED=$((CHANGED+1))
elif [ -e "$CONF/hypr/hyprland.lua" ]; then
  warn "Du hast schon eine hyprland.lua – ich lasse sie unverändert."
  warn "Meine liegt als $CONF/hypr/hyprland.draconyx.lua; Binds/Autostart bei Bedarf übernehmen."
  put "$HERE/hypr/hyprland.lua" "$CONF/hypr/hyprland.draconyx.lua" 644
else
  cp "$HERE/hypr/hyprland.lua" "$CONF/hypr/hyprland.lua"
fi
FRESH_LOCK=0
for f in hypridle.conf hyprlock.conf; do
  if [ ! -e "$CONF/hypr/$f" ]; then cp "$HERE/hypr/$f" "$CONF/hypr/$f"; [ "$f" = hyprlock.conf ] && FRESH_LOCK=1; fi
done
# persönliche Pfade im Sperrbildschirm neutralisieren (Bild muss der Nutzer selbst setzen)
[ "$FRESH_LOCK" = 1 ] && sed -i "s|/home/syntaxjason|$HOME|g" "$CONF/hypr/hyprlock.conf" 2>/dev/null || true

say "Aurora-Einstellungen: verknüpfe settings-app, preferences.py, settings.css"
A="$CONF/hypr/aurora"; mkdir -p "$A"
for f in settings-app preferences.py settings.css; do [ -e "$A/$f" ] || ln -s "$REPO/$f" "$A/$f"; done

# ---------------------------------------------------------------- 3. Standardwerte
[ -e "$CONF/draconyx/terminal" ] || { for t in ghostty kitty foot alacritty konsole; do command -v "$t" >/dev/null && { echo "$t" > "$CONF/draconyx/terminal"; break; }; done; }
[ -e "$CONF/draconyx/window-mode" ] || echo floating > "$CONF/draconyx/window-mode"
# Farben: nur beim ersten Mal die Aurora-Voreinstellung setzen; vorhandene (auch angepasste) Farben bleiben
if [ -e "$CONF/draconyx/colors.json" ]; then "$HOME/.local/bin/dx-colors" ensure; else "$HOME/.local/bin/dx-colors" preset aurora; fi
# Brave über XWayland starten, damit sein Minimieren-Symbol bei Hyprland ankommt – nur nötig OHNE das native Aurora-Plugin
# (mit Plugin läuft Brave sauber als Wayland-Fenster, XWayland wäre bei gebrochener Skalierung unscharf)
if hyprctl plugin list 2>/dev/null | grep -q aurora-native; then
  if head -1 "$HOME/.config/brave-flags.conf" 2>/dev/null | grep -q '^# Draconyx'; then rm -f "$HOME/.config/brave-flags.conf"; echo "    brave-flags.conf entfernt (natives Plugin vorhanden)"; fi
else
  [ -e "$HOME/.config/brave-flags.conf" ] || printf '%s\n%s\n' '# Draconyx: Brave über XWayland starten, damit das Minimieren-Symbol funktioniert (ohne natives Aurora-Plugin).' '--ozone-platform=x11' > "$HOME/.config/brave-flags.conf"
fi

# ---------------------------------------------------------------- 4. Wallpaper Engine (repariert)
if [ "$DO_WE" = 1 ]; then
  SRC="$HOME/.local/src/linux-wallpaperengine"; PREFIX="$HOME/.local/opt/linux-wallpaperengine"
  STAMP="$PREFIX/.draconyx-build"
  WANT="$(cat "$HERE/patches/linux-wallpaperengine-fixes.patch" "$HERE/wallpaper-engine/UPSTREAM_COMMIT" | sha256sum | cut -c1-16)"
  if [ "$FORCE" != 1 ] && [ -x "$PREFIX/linux-wallpaperengine" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$WANT" ]; then
    say "Wallpaper Engine ist aktuell – nichts zu bauen"
  else
    say "Wallpaper Engine bauen (Web-Wallpaper-Fix + Mausposition)"
    if [ ! -d "$SRC/.git" ]; then
      git clone --recurse-submodules https://github.com/Almamu/linux-wallpaperengine.git "$SRC"
      git -C "$SRC" checkout "$(cat "$HERE/wallpaper-engine/UPSTREAM_COMMIT")" 2>/dev/null || warn "Upstream-Stand nicht gefunden, nehme den neuesten (Patch passt eventuell nicht)."
      git -C "$SRC" submodule update --init --recursive
    fi
    if git -C "$SRC" apply --reverse --check "$HERE/patches/linux-wallpaperengine-fixes.patch" 2>/dev/null; then
      echo "    Patch ist schon angewendet"
    elif git -C "$SRC" apply --check "$HERE/patches/linux-wallpaperengine-fixes.patch" 2>/dev/null; then
      git -C "$SRC" apply "$HERE/patches/linux-wallpaperengine-fixes.patch"
    else
      warn "Patch nicht anwendbar – baue den vorhandenen Stand."
    fi
    cmake -B "$SRC/build" -S "$SRC" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -Wno-dev \
          -DCMAKE_CXX_FLAGS="-ffat-lto-objects -Wno-builtin-macro-redefined" -DCMAKE_C_FLAGS="-Wno-builtin-macro-redefined"
    cmake --build "$SRC/build" -j"$(nproc)"      # nur was sich geändert hat (Build-Ordner bleibt erhalten)
    cmake --install "$SRC/build" >/dev/null
    echo "$WANT" > "$STAMP"; CHANGED=$((CHANGED+1))
    say "Wallpaper Engine ist installiert: $PREFIX"
  fi
fi

# ---------------------------------------------------------------- 5. Aurora komplett auf die Shell umstellen
# Aurora-Skripte (Dock, Launcher, Alt+Tab, Modus, Minimieren) reichen bei vorhandener Shell nur noch an Quickshell weiter;
# waybar und das alte GTK-Dock starten nicht mehr.
AU="$CONF/hypr/aurora"
if [ -e "$AU/desktop-ui" ] || [ -e "$AU/start-desktop" ]; then
  say "Aurora-Skripte auf die Shell umstellen (Sicherungen: *.vor-shell)"
  for f in desktop-ui desktop.lua start-desktop start-dock background-restore; do
    [ -e "$AU/$f" ] && [ ! -L "$AU/$f" ] && cp -n "$AU/$f" "$AU/$f.vor-shell"
    put "$REPO/$f" "$AU/$f" 755
  done
fi
# Alter Aurora-Hintergrund-Renderer: beenden und entfernen (Wallpaper Engine läuft jetzt aus der Shell; der alte lag sonst
# unter dem neuen Wallpaper und kam beim Abwählen wieder zum Vorschein)
for p in $(pgrep -f '[a]urora/native/wallpaper/aurora-wallpaper' || true); do kill "$p" 2>/dev/null || true; done
rm -f "$XDG_RUNTIME_DIR/aurora-wallpaper-pids.json"
for d in "$AU/native/wallpaper" "$REPO/native/wallpaper"; do
  [ -e "$d/aurora-wallpaper" ] && { rm -f "$d/aurora-wallpaper"; say "alten Hintergrund-Renderer entfernt ($d)"; }
done
if pgrep -x waybar >/dev/null; then
  say "waybar läuft noch – wird beendet (die Taskleiste kommt jetzt aus der Shell)"
  pkill -x waybar || true
fi
for p in $(pgrep -x python3 || true); do
  if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'desktop-ui daemon'; then say "altes Aurora-Dock beenden (PID $p)"; kill "$p" || true; fi
done
# ---------------------------------------------------------------- 6. Alles anwenden: Hyprland neu laden, Shell neu starten
# Läuft vollautomatisch; nur wenn sich etwas geändert hat (oder mit --restart). DX_NO_START=1 überspringt das.
if [ "${DX_NO_START:-0}" != 1 ] && { [ "$CHANGED" -gt 0 ] || [ "$RESTART" = 1 ]; }; then
  # laufende Hyprland-Sitzung finden, auch wenn das Skript außerhalb davon gestartet wurde
  if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    for d in $(ls -t "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" 2>/dev/null); do
      if HYPRLAND_INSTANCE_SIGNATURE="$d" hyprctl version >/dev/null 2>&1; then export HYPRLAND_INSTANCE_SIGNATURE="$d"; break; fi
    done
  fi
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    say "Hyprland-Konfiguration neu laden"
    hyprctl reload >/dev/null 2>&1 || warn "hyprctl reload fehlgeschlagen"
    sleep 1; err="$(hyprctl configerrors 2>/dev/null | head -3)"; [ -n "$err" ] && warn "Konfigurationsfehler: $err"
    if command -v qs >/dev/null; then
      say "Shell neu starten"
      qs -c draconyx kill >/dev/null 2>&1 || true
      sleep 1
      # übrig gebliebene Wächter der alten Shell beenden (die neue startet sie selbst)
      for p in $(pgrep -x python3 || true); do
        c="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)"
        case "$c" in *dx-x11-iconify*|*dx-ui-bridge*|*desktop-ui\ daemon*|*settings-app*) kill "$p" 2>/dev/null || true;; esac
      done
      hyprctl dispatch "hl.dsp.exec_cmd(\"sh -c 'QS_ICON_THEME=Papirus-Dark exec qs -c draconyx'\")" >/dev/null 2>&1 || true
      for _ in $(seq 1 20); do qs -c draconyx ipc show >/dev/null 2>&1 && break; sleep 0.5; done
      if qs -c draconyx ipc show >/dev/null 2>&1; then
        say "Shell läuft"
        sleep 3; qs -c draconyx ipc call shell weReapply >/dev/null 2>&1 || true    # Wallpaper Engine mit den gespeicherten Wallpapern neu starten
      else
        warn "Die Shell ist nicht angesprungen – prüfe:  dx-doctor"
      fi
    fi
  else
    warn "Keine laufende Hyprland-Sitzung gefunden – Shell und Konfiguration werden beim nächsten Anmelden geladen."
  fi
fi

[ "$CHANGED" -eq 0 ] && say "Alles war schon auf dem neuesten Stand." || say "$CHANGED Teile aktualisiert."
say "Fertig. Einstellungen: Zahnrad in der Taskleiste. Bei Problemen:  dx-doctor"
