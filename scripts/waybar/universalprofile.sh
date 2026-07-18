#!/bin/bash

# =============================================
#   archenemy - universalprofile.sh
#   Przełącza profil zasilania przez powerprofilesctl
#   i WERYFIKUJE efekt odczytem po zmianie (parytet
#   z asusprofile.sh): sukces = `get` zwraca nowy profil.
#   Przy porażce zapisuje diagnozę do pliku w
#   XDG_RUNTIME_DIR i wychodzi kodem 1 — profile-switch.sh
#   pokazuje wtedy błąd zamiast udawać sukces.
# =============================================

ERR_FILE="${XDG_RUNTIME_DIR:-/tmp}/archenemy-profile-err"

PROFILES=("power-saver" "balanced" "performance")

CURRENT=$(powerprofilesctl get 2>/dev/null)

# Indeks bieżącego profilu (nieznany → 0, czyli przejście na "balanced")
CURRENT_IDX=0
for i in "${!PROFILES[@]}"; do
    if [[ "${PROFILES[$i]}" == "$CURRENT" ]]; then
        CURRENT_IDX=$i
        break
    fi
done

# Następny profil (cyklicznie)
NEXT_IDX=$(( (CURRENT_IDX + 1) % ${#PROFILES[@]} ))
NEXT="${PROFILES[$NEXT_IDX]}"

out="$(powerprofilesctl set "$NEXT" 2>&1)"
ACTUAL="$(powerprofilesctl get 2>/dev/null)"

if [[ "$ACTUAL" != "$NEXT" ]]; then
    printf '%s\n' "${out:-powerprofilesctl set $NEXT: profil po zmianie to '$ACTUAL'}" \
        | head -2 > "$ERR_FILE"
    exit 1
fi

pkill -RTMIN+8 waybar
command -v notify-send >/dev/null 2>&1 && notify-send "archenemy" "Power profile: $NEXT"
rm -f "$ERR_FILE"
exit 0
