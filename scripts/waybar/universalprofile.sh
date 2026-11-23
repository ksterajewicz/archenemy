#!/usr/bin/env bash

# =============================================
#   archenemy - universalprofile.sh
#   Przełącza profil zasilania przez powerprofilesctl
#   i WERYFIKUJE efekt odczytem po zmianie (parytet
#   z asusprofile.sh): sukces = `get` zwraca nowy profil.
#   Przy porażce zapisuje diagnozę do pliku w
#   XDG_RUNTIME_DIR i wychodzi kodem 1 — profile-switch.sh
#   pokazuje wtedy błąd zamiast udawać sukces.
# =============================================

# Diagnoza w prywatnym katalogu sesji (lib/runtime-dir.sh, S12); bez niego
# pusta ścieżka = bez pliku diagnozy (nigdy wspólny /tmp, nigdy rm na /dev/null).
# shellcheck source=scripts/lib/runtime-dir.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-dir.sh"
ERR_FILE="$(archenemy_runtime_dir)/archenemy-profile-err" || ERR_FILE=""

# Kolejność cyklu. Nie każdy sprzęt ma wszystkie trzy: bez sterownika platformy
# (część AMD, desktopy) ppd nie wystawia `performance`. Dawniej cykl był stały,
# a pierwszy krok z `balanced` to zawsze `performance` — klik nigdy nic nie
# zmieniał i za każdym razem wisiało krytyczne powiadomienie (audyt 2026-11-05,
# A8). Dlatego: (1) cykl tylko po profilach z `powerprofilesctl list` (wiersze
# nagłówka „[*] <nazwa>:”, aktywny z gwiazdką); pusta albo nieczytelna lista =
# pełny cykl jak dawniej; (2) profil, którego nie udało się ustawić (odczyt `get`
# po zmianie się nie zgadza), pomijamy i próbujemy następnego.
ALL_PROFILES=("power-saver" "balanced" "performance")

LISTED="$(powerprofilesctl list 2>/dev/null | sed -nE 's/^[*[:space:]]*([a-z-]+):[[:space:]]*$/\1/p')"
PROFILES=()
for p in "${ALL_PROFILES[@]}"; do
    grep -qxF -- "$p" <<< "$LISTED" && PROFILES+=("$p")
done
((${#PROFILES[@]})) || PROFILES=("${ALL_PROFILES[@]}")

CURRENT=$(powerprofilesctl get 2>/dev/null)

# Indeks bieżącego profilu (nieznany → 0, czyli przejście na następny po pierwszym)
CURRENT_IDX=0
for i in "${!PROFILES[@]}"; do
    if [[ "${PROFILES[$i]}" == "$CURRENT" ]]; then
        CURRENT_IDX=$i
        break
    fi
done

# Kolejne profile (cyklicznie) aż do skutku; sam bieżący nie jest „zmianą”.
NEXT=""
for (( step = 1; step <= ${#PROFILES[@]}; step++ )); do
    try="${PROFILES[$(( (CURRENT_IDX + step) % ${#PROFILES[@]} ))]}"
    [[ "$try" == "$CURRENT" ]] && continue
    out="$(powerprofilesctl set "$try" 2>&1)"
    ACTUAL="$(powerprofilesctl get 2>/dev/null)"
    if [[ "$ACTUAL" == "$try" ]]; then
        NEXT="$try"
        break
    fi
    err="$out"
    [[ -n "$err" ]] || err="powerprofilesctl set $try: profil po zmianie to '$ACTUAL'"
done

if [[ -z "$NEXT" ]]; then
    [[ -n "${err:-}" ]] || err="powerprofilesctl: brak innego profilu niż '$CURRENT'"
    [[ -n "$ERR_FILE" ]] && printf '%s\n' "$err" | head -2 > "$ERR_FILE"
    exit 1
fi

pkill -RTMIN+8 waybar
command -v notify-send >/dev/null 2>&1 && notify-send -a archenemy "archenemy" "Power profile: $NEXT"
[[ -n "$ERR_FILE" ]] && rm -f "$ERR_FILE"
exit 0
