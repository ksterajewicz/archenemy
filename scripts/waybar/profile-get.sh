#!/bin/bash

# =============================================
#   archenemy - profile-get.sh
#   Wypisuje bieżący profil zasilania dla waybara.
#   Narzędzie wybiera wg data/hardware.dat, ale z łańcuchem
#   fallbacków: preferowane → alternatywne → sysfs → "brak".
#   ZAWSZE wypisuje tekst i kończy się kodem 0 — waybar
#   ukrywa cały moduł custom przy niezerowym kodzie wyjścia,
#   więc twardy guard `command -v X && X` potrafił "zgubić"
#   przełącznik z paska, gdy brakowało asusctl/
#   powerprofilesctl albo ich demon nie działał.
# =============================================

HARDWARE_DAT="$HOME/archenemy/data/hardware.dat"
HW_PROFILE="universal"
[[ -f "$HARDWARE_DAT" ]] && HW_PROFILE="$(<"$HARDWARE_DAT")"

# awk 'END {print $NF}' — ostatnie słowo OSTATNIEJ linii, odporne na
# wielolinijkowe / zmienne wyjście asusctl ("Active profile is Balanced")
get_asus()  { command -v asusctl >/dev/null 2>&1 && asusctl profile -p 2>/dev/null | awk 'END {print $NF}'; }
get_ppd()   { command -v powerprofilesctl >/dev/null 2>&1 && powerprofilesctl get 2>/dev/null; }
get_sysfs() { cat /sys/firmware/acpi/platform_profile 2>/dev/null; }

case "$HW_PROFILE" in
    asus) PROFILE="$(get_asus)"; [[ -n "$PROFILE" ]] || PROFILE="$(get_ppd)" ;;
    *)    PROFILE="$(get_ppd)";  [[ -n "$PROFILE" ]] || PROFILE="$(get_asus)" ;;
esac
[[ -n "$PROFILE" ]] || PROFILE="$(get_sysfs)"

# "brak" = widoczny stan błędu na pasku (zamiast znikającego modułu) —
# znaczy: żadne narzędzie profili nie działa, patrz profile-switch.sh
echo "${PROFILE:-brak}"
exit 0
