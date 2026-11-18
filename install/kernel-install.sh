#!/usr/bin/env bash

# =============================================
#   archenemy - kernel-install.sh
#   Installs an alternative kernel + headers.
#
#   Minimal skeleton — flesh out as needed.
# =============================================

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# ─── PLATFORMA (D6) ───────────────────────────────────────────────────────────
# Jądra i nagłówki to pakiety pacmana + regeneracja GRUB-a — kod Archa.
# Platformę wykrywa pkg_gate z install/lib/pkg.sh — ta sama funkcja wyboru
# ścieżki co w install.sh, nie odziedziczona zmienna PLATFORM.
# Poza Archem i pochodnymi: instrukcja i kod 2, zanim padnie pytanie.
# shellcheck source=install/lib/pkg.sh
if ! source "$(dirname "$(readlink -f "$0")")/lib/pkg.sh"; then
    echo -e "${RED}✗ Cannot load install/lib/pkg.sh — platform unknown, nothing was changed.${NC}"
    exit 1
fi
if ! pkg_gate "Alternative kernel"; then
    case "$PKG_ROUTE" in
        fedora)
            echo "    Fedora ships its own kernel (package kernel, updated with sudo dnf upgrade);"
            echo "    linux-zen and linux-lts are not available there, and archenemy installs no other kernel." ;;
        nixos)
            echo "    In configuration.nix, then nixos-rebuild boot:"
            echo "      boot.kernelPackages = pkgs.linuxPackages_zen;      # zen"
            echo "      boot.kernelPackages = pkgs.linuxPackages_latest;   # newest stable"
            echo "    Without the option NixOS uses its default LTS kernel (pkgs.linuxPackages)." ;;
    esac
    exit 2
fi

# Wspólna obsługa bootloadera (regeneracja configu po instalacji kernela).
source "$(dirname "$(readlink -f "$0")")/bootloader.sh"

echo -e "${YELLOW}Available kernels:${NC}"
echo "  1) linux        (stable, default)"
echo "  2) linux-zen    (desktop/latency tuned)"
echo "  3) linux-lts    (long-term support)"
echo ""
read -rp "Select kernel to install [default: skip]: " choice

case "$choice" in
    1) KERNEL="linux" ;;
    2) KERNEL="linux-zen" ;;
    3) KERNEL="linux-lts" ;;
    *) echo -e "${YELLOW}No kernel selected — skipping.${NC}"; exit 0 ;;
esac

read -rp "Install $KERNEL and $KERNEL-headers? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    # Sukces = OBA pakiety realnie w bazie pacmana (kernel i nagłówki), nie sam
    # kod wyjścia (audyt 2026-09-25: „✓ installed" i regeneracja bootloadera
    # leciały także po nieudanym pacmanie — wpis dla kernela, którego nie ma).
    sudo pacman -S --needed "$KERNEL" "$KERNEL-headers"
    MISSING=()
    for pkg in "$KERNEL" "$KERNEL-headers"; do
        pacman -Qi "$pkg" &>/dev/null || MISSING+=("$pkg")
    done
    if [[ ${#MISSING[@]} -eq 0 ]]; then
        echo -e "${GREEN}✓ $KERNEL + $KERNEL-headers installed.${NC}"
        # Nowy kernel bez wpisu w bootloaderze jest niebootowalny.
        regenerate_bootloader "kernel $KERNEL"
        # Kod regeneracji = kod skryptu, kontrakt z install.sh [6.5]: 0 gotowe,
        # 1 grub-mkconfig padł, 2 wpisy bootowania do poprawienia ręcznie.
        exit $?
    else
        echo -e "${RED}✗ Not installed: ${MISSING[*]} — check pacman output above; bootloader unchanged.${NC}"
        # Skrypt jest wołany przez install.sh jako osobny proces (bash …),
        # więc niezerowy kod nie przerywa instalatora — tylko sygnalizuje stan.
        exit 1
    fi
fi
