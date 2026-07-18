#!/bin/bash

# =============================================
#   archenemy - asusprofile.sh
#   Przełącza profil przez asusd i WERYFIKUJE efekt w sysfs.
#
#   `asusctl profile -n` potrafi wyjść kodem 0 i ciszą, choć nic
#   nie zmienił (np. klient asusctl nowszy niż działający asusd
#   po aktualizacji bez restartu demona — wtedy też `profile -p`
#   zwraca pustkę). Sukces = ZMIANA wartości
#   /sys/firmware/acpi/platform_profile, nie kod wyjścia.
#
#   Kod 0 tylko przy potwierdzonej zmianie (albo przy braku
#   platform_profile w sysfs i czystym wyjściu asusctl).
#   Przy porażce zapisuje diagnozę do pliku w XDG_RUNTIME_DIR —
#   profile-switch.sh próbuje wtedy ppd i pokazuje ten błąd.
#
#   ARCHENEMY_PP_SYSFS — nadpisanie ścieżki sysfs w testach mock.
# =============================================

PP_SYSFS="${ARCHENEMY_PP_SYSFS:-/sys/firmware/acpi/platform_profile}"
ERR_FILE="${XDG_RUNTIME_DIR:-/tmp}/archenemy-profile-err"

before="$(cat "$PP_SYSFS" 2>/dev/null)"
out="$(asusctl profile -n 2>&1)"
rc=$?
sleep 0.4   # asusd potrzebuje chwili, żeby platform_profile się przestawił
after="$(cat "$PP_SYSFS" 2>/dev/null)"

ok=0
if [[ -n "$after" && "$after" != "$before" ]]; then
    ok=1
elif [[ -z "$before" && -z "$after" && $rc -eq 0 && -z "$out" ]]; then
    ok=1   # platforma bez platform_profile w sysfs — zaufaj czystemu wyjściu
fi

if [[ $ok -eq 1 ]]; then
    pkill -RTMIN+8 waybar
    command -v notify-send >/dev/null 2>&1 && \
        notify-send "archenemy" "Power profile: ${after:-zmieniony}"
    rm -f "$ERR_FILE"
    exit 0
fi

printf '%s\n' "${out:-asusctl profile -n: kod $rc, profil w sysfs bez zmian}" \
    | head -2 > "$ERR_FILE"
exit 1
