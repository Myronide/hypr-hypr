#!/usr/bin/env bash
# Privater, unsichtbarer Hyprland: kwin_wayland --virtual (eigener dbus) + verschachteltes Hyprland. Beruehrt weder Display noch Monitore des Nutzers.
# Aufruf: vhl.sh <hyprland.lua> [HOME-Ordner]    Zustand: $VHL_ENV (Standard: <skriptordner>/vhl.env), danach:  source vhl.env
set -u
CFG=${1:?Aufruf: vhl.sh <hyprland.lua> [HOME]}; CFG=$(readlink -f "$CFG")
D=$(cd "$(dirname "$0")" && pwd); ENVF=${VHL_ENV:-$D/vhl.env}
[ -e "$ENVF" ] && { echo "$ENVF existiert schon (vhl-stop.sh zuerst)" >&2; exit 1; }
VHOME=${2:-$(mktemp -d "$D/vhl-home.XXXXXX")}; mkdir -p "$VHOME/.config" "$VHOME/.local/share" "$VHOME/.cache" "$VHOME/.local/state"
RT=/run/user/1000; SOCK=vhl-kwin-$$
ls "$RT/hypr" > "$VHOME/.before"; ls "$RT" | grep -E '^wayland-[0-9]+$' > "$VHOME/.wbefore"
HOME=$VHOME XDG_CONFIG_HOME=$VHOME/.config XDG_DATA_HOME=$VHOME/.local/share XDG_CACHE_HOME=$VHOME/.cache XDG_STATE_HOME=$VHOME/.local/state \
 env -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS setsid dbus-run-session -- kwin_wayland --virtual --socket $SOCK --width 1920 --height 1080 --no-lockscreen --no-global-shortcuts > "$VHOME/kwin.log" 2>&1 &
DBP=$!
for i in $(seq 50); do [ -S "$RT/$SOCK" ] && break; sleep 0.2; done
[ -S "$RT/$SOCK" ] || { echo "kwin kam nicht hoch" >&2; kill $DBP 2>/dev/null; exit 1; }
KWP=$(pgrep -P $DBP -x kwin_wayland | head -1)
# WAYLAND_DISPLAY zeigt NUR auf den privaten kwin, DISPLAY ist leer: Hyprland kann nicht auf den Nutzer-Bildschirm
env -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY WAYLAND_DISPLAY=$SOCK HOME=$VHOME XDG_CONFIG_HOME=$VHOME/.config XDG_DATA_HOME=$VHOME/.local/share XDG_CACHE_HOME=$VHOME/.cache XDG_STATE_HOME=$VHOME/.local/state \
 setsid Hyprland -c "$CFG" > "$VHOME/hl.log" 2>&1 &
HP=$!
SIG=""; WD=""
for i in $(seq 60); do
  SIG=$(ls "$RT/hypr" | diff "$VHOME/.before" - | sed -n 's/^> //p' | head -1)
  WD=$(ls "$RT" | grep -E '^wayland-[0-9]+$' | diff "$VHOME/.wbefore" - | sed -n 's/^> //p' | head -1)
  [ -n "$SIG" ] && [ -n "$WD" ] && break; sleep 0.2
done
[ -n "$SIG" ] && [ -n "$WD" ] || { echo "Hyprland nicht gestartet, siehe $VHOME/hl.log" >&2; kill $HP $KWP $DBP 2>/dev/null; exit 1; }
sleep 2
cat > "$ENVF" <<EOF
# vhl-Zustand (source diese Datei). Nur fuer die private Instanz.
export HYPRLAND_INSTANCE_SIGNATURE=$SIG
export WAYLAND_DISPLAY=$WD
unset DISPLAY
export HOME=$VHOME XDG_CONFIG_HOME=$VHOME/.config XDG_DATA_HOME=$VHOME/.local/share XDG_CACHE_HOME=$VHOME/.cache XDG_STATE_HOME=$VHOME/.local/state
export VHL_KWIN_SOCKET=$SOCK VHL_DBUS_PID=$DBP VHL_KWIN_PID=${KWP:-} VHL_HYPRLAND_PID=$HP VHL_HOME=$VHOME
EOF
echo "OK: source $ENVF   (Instanz $SIG, Display $WD)"
