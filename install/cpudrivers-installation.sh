#!/bin/bash

# =============================================
#   archenemy - cpudrivers-installation.sh
#   Installs CPU microcode for the detected vendor.
#
#   Minimal skeleton — flesh out as needed.
# =============================================

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Wspólna obsługa bootloadera (regeneracja configu po instalacji mikrokodu).
source "$(dirname "$(readlink -f "$0")")/bootloader.sh"

# ─── DETECT CPU VENDOR ────────────────────────────────────────────────────────

VENDOR="$(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $NF}')"
echo -e "${YELLOW}Detected CPU vendor: ${VENDOR:-unknown}${NC}"

case "$VENDOR" in
    GenuineIntel)
        UCODE="intel-ucode"
        ;;
    AuthenticAMD)
        UCODE="amd-ucode"
        ;;
    *)
        echo -e "${YELLOW}Unknown CPU vendor — skipping microcode.${NC}"
        exit 0
        ;;
esac

read -rp "Install $UCODE? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    # Sukces = pakiet realnie w bazie pacmana, nie sam kod wyjścia (audyt
    # 2026-09-25: „✓ installed" i regeneracja GRUB-a leciały także po
    # nieudanym pacmanie — wpis initrd wskazywałby nieistniejący obraz).
    if sudo pacman -S --needed "$UCODE" && pacman -Qi "$UCODE" &>/dev/null; then
        echo -e "${GREEN}✓ $UCODE installed.${NC}"
        # Mikrokod ładuje bootloader wczesnym initrd — sam pakiet nic nie robi,
        # dopóki config bootloadera się do niego nie odwoła.
        regenerate_bootloader "mikrokod $UCODE"
    else
        echo -e "${RED}✗ $UCODE NIE zainstalowany — sprawdź wyjście pacmana wyżej; bootloader bez zmian.${NC}"
        # Skrypt jest wołany przez install.sh jako osobny proces (bash …),
        # więc niezerowy kod nie przerywa instalatora — tylko sygnalizuje stan.
        exit 1
    fi
fi
