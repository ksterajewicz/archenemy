#!/bin/bash
# =============================================
#   archenemy - bluetooth-installation.sh
#   Opcjonalny Bluetooth: flaga dopiero po weryfikacji pakietów i usługi.
#   Kod 0 = gotowe; kod 1 = popraw ręcznie według komunikatu.
# =============================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
retry='bash ~/archenemy/install/bluetooth-installation.sh'
if ! sudo pacman -S --needed bluez bluez-utils dbus bluetui \
    || ! pacman -Q bluez bluez-utils dbus bluetui >/dev/null 2>&1 \
    || ! command -v bluetoothctl >/dev/null || ! command -v dbus-monitor >/dev/null \
    || ! command -v bluetui >/dev/null; then
    echo -e "  ${RED}✗ Bluetooth packages not verified. Retry: $retry${NC}"
    exit 1
fi
if ! sudo systemctl enable --now bluetooth \
    || ! systemctl is-enabled --quiet bluetooth \
    || ! systemctl is-active --quiet bluetooth; then
    echo -e "  ${RED}✗ Bluetooth service not enabled and active. Run: sudo systemctl enable --now bluetooth; then $retry${NC}"
    exit 1
fi
if ! mkdir -p "$ROOT/data" || ! touch "$ROOT/data/bluetooth-enabled.dat"; then
    echo -e "  ${RED}✗ Cannot save Bluetooth icon setting. Retry: $retry${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓ Bluetooth packages verified; service enabled and active; icon enabled (reload waybar).${NC}"
