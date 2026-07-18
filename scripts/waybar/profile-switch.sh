#!/bin/bash

# =============================================
#   archenemy - profile-switch.sh
#   Przełącza profil zasilania po kliknięciu w waybarze.
#   Lustrzana logika profile-get.sh: hardware.dat wskazuje
#   preferencję, ale gdy preferowane narzędzie nie działa,
#   przełączamy tym, które działa — inaczej klik nic nie
#   robił, choć pasek pokazywał profil (z fallbacku).
#   Gdy nic nie działa: powiadomienie zamiast ciszy.
# =============================================

SCRIPTS_DIR="$HOME/archenemy/scripts/waybar"
HARDWARE_DAT="$HOME/archenemy/data/hardware.dat"
HW_PROFILE="universal"
[[ -f "$HARDWARE_DAT" ]] && HW_PROFILE="$(<"$HARDWARE_DAT")"

# "Działa" = binarka jest I jej DEMON żyje. Dla ASUS testujemy asusd przez
# systemd, NIE przez `asusctl profile -p`: na nowszych asusctl ta flaga
# zmieniła znaczenie i zwraca pusto, przez co klik twierdził, że nic nie
# działa, choć asusd i `asusctl profile -n` (samo przełączanie) działają.
# PPD ma stabilne CLI, więc jego żywotność nadal sprawdzamy przez `get`.
asus_ok() { command -v asusctl >/dev/null 2>&1 && systemctl is-active --quiet asusd 2>/dev/null; }
ppd_ok()  { command -v powerprofilesctl >/dev/null 2>&1 && [[ -n "$(powerprofilesctl get 2>/dev/null)" ]]; }

# Nie `exec` — skrypty profili weryfikują EFEKT (sysfs/get) i przy braku
# zmiany wychodzą kodem 1, więc próbujemy kolejnego narzędzia. Żywy demon
# nie gwarantuje działającego klienta (asusctl po aktualizacji bez
# restartu asusd wychodzi zerem, nic nie zmieniając).
case "$HW_PROFILE" in
    asus)
        asus_ok && bash "$SCRIPTS_DIR/asusprofile.sh" && exit 0
        ppd_ok  && bash "$SCRIPTS_DIR/universalprofile.sh" && exit 0
        ;;
    *)
        ppd_ok  && bash "$SCRIPTS_DIR/universalprofile.sh" && exit 0
        asus_ok && bash "$SCRIPTS_DIR/asusprofile.sh" && exit 0
        ;;
esac

# Nic nie zadziałało — pokaż PRAWDZIWY błąd ostatniej próby (jeśli jest),
# nie tylko ogólną instrukcję.
ERR_FILE="${XDG_RUNTIME_DIR:-/tmp}/archenemy-profile-err"
DIAG=""
[[ -f "$ERR_FILE" ]] && DIAG="$(head -1 "$ERR_FILE")"
command -v notify-send >/dev/null 2>&1 && notify-send -u critical "archenemy" \
    "Przełączenie profilu nie zadziałało.${DIAG:+ Błąd: $DIAG.} ASUS: po aktualizacji asusctl zrestartuj demona (sudo systemctl restart asusd); świeża instalacja: systemctl enable --now asusd. Inne: power-profiles-daemon (systemctl enable --now power-profiles-daemon)."
exit 1
