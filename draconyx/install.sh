#!/usr/bin/env bash
# Draconyx / Aurora – Einrichtung auf einem Arch-System mit Hyprland 0.56.x
#   ./install.sh            alles einrichten (fragt vor Paketen und überschreibt nichts Eigenes)
#   ./install.sh --no-we    ohne Wallpaper Engine bauen
#   ./install.sh --yes      Rückfragen mit "ja" beantworten
#   ./install.sh --no-packages   keine Pakete installieren
#   ./install.sh --force    Wallpaper Engine auch ohne Änderung neu bauen
# Mehrfach ausführen ist ungefährlich: es wird nur angewendet, was neu oder geändert ist.
# Danach: in Hyprland neu anmelden (oder `qs -c draconyx` starten).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
CONF="$HOME/.config"
DO_WE=1; ASSUME_YES=0; DO_PKGS=1; FORCE=0; CHANGED=0
for a in "$@"; do case "$a" in --no-we) DO_WE=0;; --force) FORCE=1;; --yes|-y) ASSUME_YES=1;; --no-packages) DO_PKGS=0;; esac; done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
ask()  { [ "$ASSUME_YES" = 1 ] && return 0; read -r -p "$1 [j/N] " r; [[ "$r" =~ ^[jJyY] ]]; }
# put QUELLE ZIEL [MODUS]: kopiert nur, wenn die Datei neu oder anders ist
put() {
  local src="$1" dst="$2" mode="${3:-644}"
  if [ -e "$dst" ] && cmp -s "$src" "$dst"; then return 0; fi
  install -D -m"$mode" "$src" "$dst"; CHANGED=$((CHANGED+1)); echo "    aktualisiert: ${dst/#$HOME/~}"
}

# ---------------------------------------------------------------- 1. Pakete
PKGS=(quickshell jq python python-gobject gtk3 grim wl-clipboard zenity git rsync ttf-inter papirus-icon-theme
      kitty ghostty dolphin swaync hypridle hyprlock cliphist plocate)
WE_PKGS=(base-devel cmake glm sdl2 wayland-protocols ffmpeg mpv glfw glew freeglut lz4 libpulse libcups at-spi2-core
         nss libxcomposite libxdamage nspr libxrandr)
missing=()
for p in "${PKGS[@]}" $([ "$DO_WE" = 1 ] && echo "${WE_PKGS[@]}"); do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ "$DO_PKGS" = 1 ] && [ "${#missing[@]}" -gt 0 ]; then
  say "Fehlende Pakete: ${missing[*]}"
  if ask "Mit sudo pacman installieren?"; then sudo pacman -S --needed "${missing[@]}" || warn "Einige Pakete ließen sich nicht installieren – bitte von Hand nachholen."
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

say "Hyprland-Module nach $CONF/hypr (bestehende Dateien bleiben)"
mkdir -p "$CONF/hypr"
for f in dx_snap.lua dx_tiling.lua dx_zones.lua dx_binds.lua csd-apps; do put "$HERE/hypr/$f" "$CONF/hypr/$f" 644; done
[ -e "$CONF/hypr/monitors_local.lua" ] || { cp "$HERE/hypr/monitors_local.lua.example" "$CONF/hypr/monitors_local.lua"; warn "monitors_local.lua ist eine Vorlage von SyntaxJason – bitte an deine Monitore anpassen (hyprctl monitors)."; }
if [ -e "$CONF/hypr/hyprland.lua" ] && cmp -s "$HERE/hypr/hyprland.lua" "$CONF/hypr/hyprland.lua"; then
  :   # schon unsere hyprland.lua
elif [ -e "$CONF/hypr/hyprland.lua" ]; then
  warn "Du hast schon eine hyprland.lua – ich lasse sie unverändert."
  warn "Meine liegt als $CONF/hypr/hyprland.draconyx.lua; Binds/Autostart bei Bedarf übernehmen."
  put "$HERE/hypr/hyprland.lua" "$CONF/hypr/hyprland.draconyx.lua" 644
else
  cp "$HERE/hypr/hyprland.lua" "$CONF/hypr/hyprland.lua"
fi
for f in hypridle.conf hyprlock.conf; do [ -e "$CONF/hypr/$f" ] || cp "$HERE/hypr/$f" "$CONF/hypr/$f"; done
# persönliche Pfade im Sperrbildschirm neutralisieren (Bild muss der Nutzer selbst setzen)
sed -i "s|/home/syntaxjason|$HOME|g" "$CONF/hypr/hyprlock.conf" 2>/dev/null || true

say "Aurora-Einstellungen: verknüpfe settings-app, preferences.py, settings.css"
A="$CONF/hypr/aurora"; mkdir -p "$A"
for f in settings-app preferences.py settings.css; do [ -e "$A/$f" ] || ln -s "$REPO/$f" "$A/$f"; done

# ---------------------------------------------------------------- 3. Standardwerte
[ -e "$CONF/draconyx/terminal" ] || { for t in ghostty kitty foot alacritty konsole; do command -v "$t" >/dev/null && { echo "$t" > "$CONF/draconyx/terminal"; break; }; done; }
[ -e "$CONF/draconyx/window-mode" ] || echo floating > "$CONF/draconyx/window-mode"
"$HOME/.local/bin/dx-colors" preset aurora
[ -e "$HOME/.config/brave-flags.conf" ] || printf '%s\n' '--ozone-platform=x11' > "$HOME/.config/brave-flags.conf"

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
  for f in desktop-ui start-desktop start-dock background-restore; do
    [ -e "$AU/$f" ] && [ ! -L "$AU/$f" ] && cp -n "$AU/$f" "$AU/$f.vor-shell"
    put "$REPO/$f" "$AU/$f" 755
  done
fi
if pgrep -x waybar >/dev/null; then
  say "waybar läuft noch – wird beendet (die Taskleiste kommt jetzt aus der Shell)"
  pkill -x waybar || true
fi
for p in $(pgrep -x python3 || true); do
  if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'desktop-ui daemon'; then say "altes Aurora-Dock beenden (PID $p)"; kill "$p" || true; fi
done
if [ "${DX_NO_START:-0}" != 1 ] && command -v qs >/dev/null && ! qs -c draconyx ipc show >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  say "Shell starten"
  hyprctl dispatch "hl.dsp.exec_cmd(\"sh -c 'QS_ICON_THEME=Papirus-Dark exec qs -c draconyx'\")" >/dev/null 2>&1 || true
fi

[ "$CHANGED" -eq 0 ] && say "Alles war schon auf dem neuesten Stand." || say "$CHANGED Teile aktualisiert."
say "Fertig. Neu anmelden oder:  qs -c draconyx   (Einstellungen: Zahnrad in der Taskleiste)"
