#!/usr/bin/env bash
# =============================================
#   archenemy - bluetooth-installation.sh
#   Opcjonalny Bluetooth: flaga dopiero po weryfikacji pakietów i usługi.
#   Kod 0 = gotowe; kod 1 = popraw ręcznie według komunikatu (stara flaga
#   ikony usunięta — pasek nie pokazuje modułu bez działającego BlueZ);
#   kod 2 = krok ręczny poza Archem, nic nie zmieniono (brama platformy D7).
# =============================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
retry='bash ~/archenemy/install/bluetooth-installation.sh'
FLAG="$ROOT/data/bluetooth-enabled.dat"

# ─── PLATFORMA (D7) ───────────────────────────────────────────────────────────
# Wszystko niżej to kod Archa: sudo pacman i sudo systemctl enable --now.
# Wzorzec jak sześć pomocników z D6: pkg_gate z install/lib/pkg.sh (ta sama
# funkcja wyboru ścieżki co install.sh), nie odziedziczone PLATFORM. Poza
# Archem i pochodnymi: instrukcja i kod 2, zanim padnie jakiekolwiek polecenie;
# flagi ikony nie ruszamy (włącza ją użytkownik, gdy BlueZ działa).
# shellcheck source=install/lib/pkg.sh
if ! source "$ROOT/install/lib/pkg.sh"; then
    echo -e "  ${RED}✗ Cannot load install/lib/pkg.sh — platform unknown, nothing was changed.${NC}"
    exit 1
fi
if ! pkg_gate "Bluetooth"; then
    case "$PKG_ROUTE" in
        fedora)
            # bluez-utils Archa (bluetoothctl) jest w RPM bluez, dbus-monitor w dbus-tools
            # (packages.fedoraproject.org, F44); bluetui według packages/platform-map.tsv.
            echo "    sudo dnf install bluez dbus-tools          (bluetoothctl, dbus-monitor)"
            echo "    sudo systemctl enable --now bluetooth.service"
            echo "    bluetui: $(pkg_hint bluetui)" ;;
        nixos)
            echo "    hardware.bluetooth.enable = true;          (BlueZ and bluetooth.service)"
            echo "    bluetui: $(pkg_hint bluetui)"
            echo "    then nixos-rebuild switch" ;;
    esac
    if [[ "$PKG_ROUTE" == fedora || "$PKG_ROUTE" == nixos ]]; then
        echo "    Bar icon: once bluetoothctl show lists your adapter, turn it on yourself:"
        echo "      touch ~/archenemy/data/bluetooth-enabled.dat   (then reload waybar; rm it to hide the icon)"
    fi
    exit 2
fi

# fail <komunikat> — porażka na Archu: stara flaga z wcześniejszego biegu nie
# zostaje (D7), bo ikona obiecywałaby działający Bluetooth.
fail() {
    rm -f "$FLAG"
    echo -e "  ${RED}✗ $1${NC}"
    [[ -e "$FLAG" ]] && echo -e "  ${RED}✗ Could not remove the old icon setting: rm $FLAG${NC}"
    exit 1
}
if ! sudo pacman -S --needed bluez bluez-utils dbus bluetui \
    || ! pacman -Q bluez bluez-utils dbus bluetui >/dev/null 2>&1 \
    || ! command -v bluetoothctl >/dev/null || ! command -v dbus-monitor >/dev/null \
    || ! command -v bluetui >/dev/null; then
    fail "Bluetooth packages not verified. Retry: $retry"
fi
if ! sudo systemctl enable --now bluetooth \
    || ! systemctl is-enabled --quiet bluetooth \
    || ! systemctl is-active --quiet bluetooth; then
    fail "Bluetooth service not enabled and active. Run: sudo systemctl enable --now bluetooth; then $retry"
fi
if ! mkdir -p "$ROOT/data" || ! touch "$FLAG"; then
    fail "Cannot save Bluetooth icon setting. Retry: $retry"
fi
echo -e "  ${GREEN}✓ Bluetooth packages verified; service enabled and active; icon enabled (reload waybar).${NC}"
