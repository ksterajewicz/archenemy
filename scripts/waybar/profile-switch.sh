#!/usr/bin/env bash

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
# systemd: decyzja 2026-07-12, klient bez demona odpowiada niewiarygodnie.
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
# Ten sam plik diagnozy co w asusprofile.sh / universalprofile.sh (lib/runtime-dir.sh, S12).
# shellcheck source=scripts/lib/runtime-dir.sh
source "$SCRIPTS_DIR/../lib/runtime-dir.sh"
ERR_FILE="$(archenemy_runtime_dir)/archenemy-profile-err" || ERR_FILE=""
DIAG=""
[[ -n "$ERR_FILE" && -f "$ERR_FILE" ]] && DIAG="$(head -1 "$ERR_FILE")"
# Porada per platforma (przegląd D8–D10 L6): ta sama pkg_route co instalator.
# Arch, pochodne i brak biblioteki = dawna treść; NixOS = opcje
# configuration.nix, bez systemctl i sudo (system zmienia tylko konfiguracja).
HINT="ASUS: uruchom demona (sudo systemctl restart asusd), a przy braku asusctl: bash ~/archenemy/install/asus-installation.sh. Inne: power-profiles-daemon (systemctl enable --now power-profiles-daemon)."
PKG_LIB="$SCRIPTS_DIR/../../install/lib/pkg.sh"
# shellcheck source=install/lib/pkg.sh
if [[ -r "$PKG_LIB" ]] && source "$PKG_LIB" 2>/dev/null && pkg_route 2>/dev/null && [[ "$PKG_ROUTE" == nixos ]]; then
    HINT="NixOS: w configuration.nix services.asusd.enable = true; (ASUS) i services.power-profiles-daemon.enable = true;, potem nixos-rebuild switch."
fi
command -v notify-send >/dev/null 2>&1 && notify-send -u critical "archenemy" \
    "Przełączenie profilu nie zadziałało.${DIAG:+ Błąd: $DIAG.} $HINT"
exit 1
