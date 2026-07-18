#!/bin/bash

# =============================================
#   archenemy - rofi_power_menu.sh
#   Menu zasilania (rofi): wyłączenie / restart.
#   Otwierane przez Super + prawy Shift.
#   UI po angielsku (decyzja właściciela 2026-07-12).
# =============================================

POWEROFF="󰐥  Power off"
REBOOT="󰜉  Reboot"

# Kompaktowe okno bez pola wyszukiwania — 2 pozycje, motyw rice'a zostaje
THEME_STR='
window   { width: 340px; }
listview { lines: 2; fixed-height: false; }
inputbar { children: [ prompt ]; }
'

CHOICE=$(printf '%s\n%s\n' "$POWEROFF" "$REBOOT" \
    | rofi -dmenu -i -p "Power" -theme-str "$THEME_STR")
[[ -z "$CHOICE" ]] && exit 0

# Potwierdzenie — jedno przypadkowe Enter nie może wyłączyć komputera
CONFIRM=$(printf 'Yes\nNo\n' \
    | rofi -dmenu -i -p "Are you sure?" -theme-str "$THEME_STR")
[[ "$CONFIRM" != "Yes" ]] && exit 0

case "$CHOICE" in
    "$POWEROFF") systemctl poweroff ;;
    "$REBOOT")   systemctl reboot ;;
esac
