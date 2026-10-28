#!/usr/bin/env bash
# Beendet genau die PIDs aus vhl.env und raeumt eigene Sockets/Instanz-Ordner auf. Aufruf: vhl-stop.sh [--keep-home]
D=$(cd "$(dirname "$0")" && pwd); ENVF=${VHL_ENV:-$D/vhl.env}; RT=/run/user/1000
[ -f "$ENVF" ] || { echo "kein $ENVF"; exit 0; }
. "$ENVF"
chk() { [ -n "$1" ] && grep -aq "$2" "/proc/$1/cmdline" 2>/dev/null; }
chk "$VHL_HYPRLAND_PID" Hyprland && kill "$VHL_HYPRLAND_PID"
for i in $(seq 25); do [ -d "/proc/$VHL_HYPRLAND_PID" ] || break; sleep 0.2; done
chk "$VHL_KWIN_PID" kwin_wayland && kill "$VHL_KWIN_PID"
chk "$VHL_DBUS_PID" dbus-run-session && kill "$VHL_DBUS_PID"
sleep 1
case "$HYPRLAND_INSTANCE_SIGNATURE" in efb5*_*) rm -rf "$RT/hypr/$HYPRLAND_INSTANCE_SIGNATURE";; esac
[ -n "$VHL_KWIN_SOCKET" ] && rm -f "$RT/$VHL_KWIN_SOCKET" "$RT/$VHL_KWIN_SOCKET.lock"
rm -f "$RT/$WAYLAND_DISPLAY.lock" 2>/dev/null; [ -S "$RT/$WAYLAND_DISPLAY" ] || rm -f "$RT/$WAYLAND_DISPLAY"
[ "$1" = "--keep-home" ] || case "$VHL_HOME" in "$D"/vhl-home.*) rm -rf "$VHL_HOME";; esac
rm -f "$ENVF"; echo gestoppt
