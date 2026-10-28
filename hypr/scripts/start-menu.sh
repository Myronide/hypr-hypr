#!/usr/bin/env bash
# Startmenü: Windows-Taste öffnet/schließt nwg-drawer, mittig über der Taskleiste.
# Größe wird je nach Monitor des Fokus berechnet. (Altlast: mit der Draconyx-Shell öffnet das Startmenü die Shell selbst.)
command -v nwg-drawer >/dev/null 2>&1 || { notify-send -a Draconyx "Startmenü" "nwg-drawer ist nicht installiert." 2>/dev/null; echo "nwg-drawer fehlt" >&2; exit 1; }
if pgrep -x nwg-drawer >/dev/null; then
    pkill -x nwg-drawer
    exit 0
fi

W=""; H=""; NAME=""
read -r W H NAME < <(timeout 5 hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | "\(.width) \(.height) \(.name)"' 2>/dev/null) || true
if ! [[ "$W" =~ ^[0-9]+$ && "$H" =~ ^[0-9]+$ ]] || [ -z "$NAME" ]; then
    echo "Kein fokussierter Monitor gefunden (läuft Hyprland?)" >&2; exit 1
fi
MW=680          # Breite des Menüs
MH=760          # Höhe des Menüs
BAR=76          # Platz für die schwebende Taskleiste unten
ML=$(( (W - MW) / 2 ))
[ "$ML" -lt 0 ] && ML=0
MT=$(( H - BAR - MH ))
[ "$MT" -lt 40 ] && MT=40

exec nwg-drawer -ovl -o "$NAME" -c 6 -is 52 -fscol 2 \
    -s drawer.css \
    -ml "$ML" -mr "$ML" -mt "$MT" -mb "$BAR" \
    -pblock "hyprlock" -pbexit "hyprctl dispatch 'hl.dsp.exit()'" \
    -pbpoweroff "systemctl poweroff" -pbreboot "systemctl reboot" -pbsleep "systemctl suspend" \
    -pbsize 28
