#!/bin/bash

# =============================================
#   archenemy - kernel-install.sh
#   Installs an alternative kernel + headers.
#
#   Minimal skeleton — flesh out as needed.
# =============================================

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

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
    sudo pacman -S --needed "$KERNEL" "$KERNEL-headers"
    echo -e "${GREEN}✓ $KERNEL installed.${NC}"
    # Nowy kernel bez wpisu w bootloaderze jest niebootowalny.
    regenerate_bootloader "kernel $KERNEL"
fi
