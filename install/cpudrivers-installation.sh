#!/usr/bin/env bash

# =============================================
#   archenemy - cpudrivers-installation.sh
#   Installs CPU microcode for the detected vendor.
#
#   Minimal skeleton — flesh out as needed.
# =============================================

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# ─── PLATFORMA (D6) ───────────────────────────────────────────────────────────
# Mikrokod to pakiet pacmana + regeneracja GRUB-a — kod Archa.
# Platformę wykrywa pkg_gate z install/lib/pkg.sh — ta sama funkcja wyboru
# ścieżki co w install.sh, nie odziedziczona zmienna PLATFORM.
# Poza Archem i pochodnymi: instrukcja i kod 2, zanim padnie pytanie.
# shellcheck source=install/lib/pkg.sh
if ! source "$(dirname "$(readlink -f "$0")")/lib/pkg.sh"; then
    echo -e "${RED}✗ Cannot load install/lib/pkg.sh — platform unknown, nothing was changed.${NC}"
    exit 1
fi
if ! pkg_gate "CPU microcode"; then
    case "$PKG_ROUTE" in
        fedora)
            echo "    Fedora installs and updates CPU microcode itself (Intel: microcode_ctl,"
            echo "    AMD: amd-ucode-firmware from linux-firmware) and loads it at boot — keep it current: sudo dnf upgrade" ;;
        nixos)
            echo "    In configuration.nix, then nixos-rebuild boot:"
            echo "      hardware.cpu.intel.updateMicrocode = true;   # Intel"
            echo "      hardware.cpu.amd.updateMicrocode = true;     # AMD" ;;
    esac
    exit 2
fi

# Wspólna obsługa bootloadera (regeneracja configu po instalacji mikrokodu).
source "$(dirname "$(readlink -f "$0")")/bootloader.sh"

# ─── DETECT CPU VENDOR ────────────────────────────────────────────────────────

# Hak testowy (tests/bootloader.sh): plik atrapy zamiast /proc/cpuinfo —
# TYLKO przy ARCHENEMY_TEST=1 (jak haki instalatora GPU, K10).
CPUINFO=/proc/cpuinfo
if [[ "${ARCHENEMY_TEST:-}" == 1 ]]; then
    CPUINFO="${ARCHENEMY_CPUINFO:-/proc/cpuinfo}"
fi
VENDOR="$(grep -m1 '^vendor_id' "$CPUINFO" | awk '{print $NF}')"
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
        regenerate_bootloader "microcode $UCODE"
        # Kod regeneracji = kod skryptu, kontrakt z install.sh [6.5]: 0 gotowe,
        # 1 grub-mkconfig padł, 2 wpisy bootowania do poprawienia ręcznie.
        exit $?
    else
        echo -e "${RED}✗ $UCODE was not installed — check pacman output above; bootloader unchanged.${NC}"
        # Skrypt jest wołany przez install.sh jako osobny proces (bash …),
        # więc niezerowy kod nie przerywa instalatora — tylko sygnalizuje stan.
        exit 1
    fi
fi
