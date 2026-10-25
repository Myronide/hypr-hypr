#!/usr/bin/env bash
# Draconyx / Aurora – Einrichtung auf einem Arch-System mit Hyprland 0.56.x
#   ./install.sh            alles einrichten (fragt vor Paketen und überschreibt nichts Eigenes)
#   ./install.sh --no-we    ohne Wallpaper Engine bauen
#   ./install.sh --yes      Rückfragen mit "ja" beantworten
#   ./install.sh --no-packages   keine Pakete installieren
# Danach: in Hyprland neu anmelden (oder `qs -c draconyx` starten).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
CONF="$HOME/.config"
DO_WE=1; ASSUME_YES=0; DO_PKGS=1
for a in "$@"; do case "$a" in --no-we) DO_WE=0;; --yes|-y) ASSUME_YES=1;; --no-packages) DO_PKGS=0;; esac; done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
ask()  { [ "$ASSUME_YES" = 1 ] && return 0; read -r -p "$1 [j/N] " r; [[ "$r" =~ ^[jJyY] ]]; }

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
rsync -a --exclude 'icons-src' --exclude 'logo-*.png' "$HERE/quickshell/" "$CONF/quickshell/draconyx/"
rm -rf "$HOME/.local/share/draconyx-hypr/qs-icons-src"; cp -r "$HERE/quickshell/icons-src" "$HOME/.local/share/draconyx-hypr/qs-icons-src"
cp -n "$HERE"/quickshell/logo-*.png "$HOME/.local/share/draconyx-hypr/" 2>/dev/null || true

say "Hilfsskripte nach ~/.local/bin"
install -m755 "$HERE"/bin/dx-* "$HOME/.local/bin/"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "~/.local/bin ist nicht im PATH.";; esac

say "Hyprland-Module nach $CONF/hypr (bestehende Dateien bleiben)"
mkdir -p "$CONF/hypr"
for f in dx_snap.lua dx_tiling.lua dx_zones.lua csd-apps; do install -m644 "$HERE/hypr/$f" "$CONF/hypr/$f"; done
[ -e "$CONF/hypr/monitors_local.lua" ] || { cp "$HERE/hypr/monitors_local.lua.example" "$CONF/hypr/monitors_local.lua"; warn "monitors_local.lua ist eine Vorlage von SyntaxJason – bitte an deine Monitore anpassen (hyprctl monitors)."; }
if [ -e "$CONF/hypr/hyprland.lua" ]; then
  warn "Du hast schon eine hyprland.lua – ich lasse sie unverändert."
  warn "Meine liegt als $CONF/hypr/hyprland.draconyx.lua; Binds/Autostart bei Bedarf übernehmen."
  cp "$HERE/hypr/hyprland.lua" "$CONF/hypr/hyprland.draconyx.lua"
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
  say "Wallpaper Engine bauen (Web-Wallpaper-Fix + Mausposition)"
  SRC="$HOME/.local/src/linux-wallpaperengine"; PREFIX="$HOME/.local/opt/linux-wallpaperengine"
  if [ ! -d "$SRC/.git" ]; then
    git clone --recurse-submodules https://github.com/Almamu/linux-wallpaperengine.git "$SRC"
    git -C "$SRC" checkout "$(cat "$HERE/wallpaper-engine/UPSTREAM_COMMIT")" 2>/dev/null || warn "Upstream-Stand nicht gefunden, nehme den neuesten (Patch passt eventuell nicht)."
    git -C "$SRC" submodule update --init --recursive
  fi
  if git -C "$SRC" apply --check "$HERE/patches/linux-wallpaperengine-fixes.patch" 2>/dev/null; then
    git -C "$SRC" apply "$HERE/patches/linux-wallpaperengine-fixes.patch"
  else
    warn "Patch schon angewendet oder nicht anwendbar – baue den vorhandenen Stand."
  fi
  cmake -B "$SRC/build" -S "$SRC" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -Wno-dev \
        -DCMAKE_CXX_FLAGS="-ffat-lto-objects -Wno-builtin-macro-redefined" -DCMAKE_C_FLAGS="-Wno-builtin-macro-redefined"
  cmake --build "$SRC/build" -j"$(nproc)"
  cmake --install "$SRC/build"
  say "Wallpaper Engine ist installiert: $PREFIX (Auswahl in der Taskleiste, Knopf mit dem Monitor-Symbol)"
fi

say "Fertig. Neu anmelden oder:  qs -c draconyx   (Einstellungen: Zahnrad in der Taskleiste)"
