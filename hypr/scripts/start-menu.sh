#!/usr/bin/env bash
# Startmenü: Windows-Taste öffnet/schließt nwg-drawer, mittig über der Taskleiste.
# Größe wird je nach Monitor des Fokus berechnet.
if pgrep -x nwg-drawer >/dev/null; then
    pkill -x nwg-drawer
    exit 0
fi

read -r W H NAME < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height) \(.name)"')
MW=680          # Breite des Menüs
MH=760          # Höhe des Menüs
BAR=76          # Platz für die schwebende Taskleiste unten
ML=$(( (W - MW) / 2 ))
MT=$(( H - BAR - MH ))
[ "$MT" -lt 40 ] && MT=40

exec nwg-drawer -ovl -o "$NAME" -c 6 -is 52 -fscol 2 \
    -s drawer.css \
    -ml "$ML" -mr "$ML" -mt "$MT" -mb "$BAR" \
    -pblock "hyprlock" -pbexit "hyprctl dispatch 'hl.dsp.exit()'" \
    -pbpoweroff "systemctl poweroff" -pbreboot "systemctl reboot" -pbsleep "systemctl suspend" \
    -pbsize 28
