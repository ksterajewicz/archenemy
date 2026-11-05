#!/bin/bash

# =============================================
#   archenemy - asus-installation.sh
#   Narzędzia ASUS: asusctl + rog-control-center z oficjalnego repo Archa,
#   bez AUR-u. Woła go install.sh [6]; można też uruchomić samodzielnie.
# =============================================

# AUR ma kilku dostawców tego samego `asusctl`, wykluczających się nawzajem,
# a część jest martwa (decyzja właściciela 2026-10-14, stan AUR 2026-11-05):
# repo extra ma binarne paczki z tagów upstreamu, aktualizowane przez `pacman -Syu`.
# Do przełączania GPU nie instalujemy nic: poradnik asus-linux mówi, że supergfxctl
# nie jest potrzebny.
#
# Bez `extra/asusctl`: użytkownik z dopisanym repo [ogc] dostaje paczkę stamtąd.
#
# asusd startuje z reguły udev, a jego unit nie ma sekcji [Install], więc
# `systemctl enable` nic nie daje (asusctl 6.5.0: asusd.service, .INSTALL).
#
# Kody wyjścia (kontrakt z install.sh [6]):
#   0 — pakiety z repo, asusd działa
#   1 — pacman się nie udał albo na maszynie nadal jest paczka z AUR
#   2 — pakiety są, asusd nie wstał: zwykle wystarczy restart komputera

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

PKGS=(asusctl rog-control-center)

# Zadeklarowany konflikt z PKGS: pacman sam proponuje podmianę w jednej transakcji,
# więc nieudana instalacja nie zostawia maszyny bez asusctl.
REPLACED_BY_PACMAN=(asusctl-devel-git asusctl-git asusctl-x11 asusctl-nosystemd
    rog-control-center-x11 rog-control-center-nosystemd)

# Bez konfliktu: same nie znikną. asusctl-nosystemd-dinit blokowałby też podmianę
# asusctl-nosystemd, bo od niego zależy, dlatego ten krok idzie przed instalacją.
LEFTOVERS=(asusctl-nosystemd-dinit asusctltray-git plasma6-applets-supergfxctl
    supergfxctl supergfxctl-git)

# Dokładne nazwy: `pacman -Q <nazwa>` znajduje też pakiet, który tylko ją dostarcza.
declare -A INSTALLED=()
while IFS= read -r p; do INSTALLED[$p]=1; done < <(pacman -Qq 2>/dev/null)

found_among() {
    local p
    for p in "$@"; do
        [[ -n "${INSTALLED[$p]:-}" ]] && printf '%s\n' "$p"
    done
}
mapfile -t FOUND_REPLACED < <(found_among "${REPLACED_BY_PACMAN[@]}")
mapfile -t FOUND_LEFTOVERS < <(found_among "${LEFTOVERS[@]}")

# supergfxctl zostawia kartę w ostatnim trybie. Usunięty w trybie Integrated
# zostawiłby dGPU wyłączone i nie byłoby czym jej włączyć.
if [[ " ${FOUND_LEFTOVERS[*]} " == *" supergfxctl"* ]] && command -v supergfxctl >/dev/null 2>&1; then
    GFX_MODE="$(timeout 5 supergfxctl -g 2>/dev/null)"
    if [[ -n "$GFX_MODE" && "$GFX_MODE" != "Hybrid" ]]; then
        echo -e "${YELLOW}⚠ supergfxctl is in ${GFX_MODE} mode. Removing it now could leave the graphics${NC}"
        echo -e "${YELLOW}  card off, so it stays. Run: supergfxctl -m Hybrid, log out, run this again.${NC}"
        mapfile -t FOUND_LEFTOVERS < <(printf '%s\n' "${FOUND_LEFTOVERS[@]}" | grep -v 'supergfxctl')
    fi
fi

if ((${#FOUND_LEFTOVERS[@]})); then
    echo -e "${YELLOW}Unsupported ASUS packages found: ${FOUND_LEFTOVERS[*]}${NC}"
    echo "  Not needed with asusctl from the official repo."
    read -rp "  Remove them? [y/N]: " ans || ans=""
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        if sudo pacman -Rns "${FOUND_LEFTOVERS[@]}"; then
            echo -e "${GREEN}✓ Removed: ${FOUND_LEFTOVERS[*]}${NC}"
        else
            echo -e "${YELLOW}⚠ pacman did not remove them, continuing.${NC}"
        fi
    fi
fi

if ((${#FOUND_REPLACED[@]})); then
    echo -e "${YELLOW}AUR packages found: ${FOUND_REPLACED[*]}${NC}"
    echo "  pacman will ask to remove them. Answer y: the official packages replace them."
fi

echo "Installing ${PKGS[*]}..."
if ! sudo pacman -S --needed "${PKGS[@]}"; then
    echo -e "${RED}✗ pacman failed, ${PKGS[*]} not installed.${NC}"
    exit 1
fi
# Sukces = zainstalowany pakiet o tej nazwie, nie jego zastępnik.
for p in "${PKGS[@]}"; do
    if [[ "$(pacman -Qq "$p" 2>/dev/null)" != "$p" ]]; then
        echo -e "${RED}✗ ${p} is still provided by: $(pacman -Qq "$p" 2>/dev/null || echo nothing).${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ ${PKGS[*]} installed.${NC}"

# Podmiana pakietu nie restartuje demona: stary proces działałby dalej ze skasowaną binarką.
ACTION=start
((${#FOUND_REPLACED[@]})) && ACTION=restart
sudo systemctl "$ACTION" asusd.service 2>/dev/null
if systemctl is-active --quiet asusd.service 2>/dev/null; then
    echo -e "${GREEN}✓ asusd is running.${NC}"
    exit 0
fi
echo -e "${YELLOW}⚠ asusd is not running yet. It starts from a udev rule at boot: restart the computer.${NC}"
exit 2
