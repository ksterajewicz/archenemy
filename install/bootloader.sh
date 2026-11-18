#!/usr/bin/env bash

# =============================================
#   archenemy - bootloader.sh (biblioteka)
#   Wykrywa bootloader i regeneruje jego konfigurację, żeby świeżo
#   zainstalowany mikrokod / kernel realnie się załadował.
#   Źródłowana (source) przez cpudrivers-installation.sh i kernel-install.sh.
#   Poza Archem i pochodnymi regenerate_bootloader nic nie robi: instrukcja, kod 2.
#
#   Zasada bezpieczeństwa: GRUB regenerujemy automatycznie (grub-mkconfig
#   ogarnia i wczesny initrd mikrokodu, i wpisy dla nowych kerneli). Dla
#   systemd-boot i nierozpoznanych NIE ruszamy wpisów rozruchowych — błędny
#   initrd zostawia maszynę bez bootu — tylko wypisujemy dokładne kroki ręczne.
# =============================================

# Własne kolory (biblioteka bywa źródłowana zanim wołający je zdefiniuje).
_BL_GREEN='\033[0;32m'; _BL_YELLOW='\033[1;33m'; _BL_RED='\033[0;31m'; _BL_NC='\033[0m'

# Brama platformy (D6) siedzi W regenerate_bootloader: funkcję można zawołać
# po samym `source`, bez pomocnika z własną bramą. pkg_gate pochodzi
# z install/lib/pkg.sh (wczytanej tu, jeśli wołający jej nie wczytał).
# Samo source niczego nie wywołuje i nigdy nie kończy procesu wołającego —
# brak biblioteki wychodzi dopiero w regenerate_bootloader (kod 1).
if ! declare -F pkg_gate >/dev/null; then
    _bl_self="${BASH_SOURCE[0]}"
    [[ "$_bl_self" == */* ]] || _bl_self="./$_bl_self"
    # shellcheck source=install/lib/pkg.sh
    source "${_bl_self%/*}/lib/pkg.sh" 2>/dev/null || true
    unset _bl_self
fi

# Hak testowy (tests/bootloader.sh): katalog /boot podmieniany na atrapę
# w mktemp — TYLKO przy ARCHENEMY_TEST=1, jak haki instalatora GPU (K10,
# audyt bezpieczeństwa 2026-11-14): zmienna odziedziczona przypadkiem ze
# środowiska nie przekieruje `sudo grub-mkconfig -o` w inne miejsce.
_BL_BOOT_DIR=/boot
if [[ "${ARCHENEMY_TEST:-}" == 1 ]]; then
    _BL_BOOT_DIR="${ARCHENEMY_BOOT_DIR:-/boot}"
fi

# Wypisuje: grub | systemd-boot | unknown
detect_bootloader() {
    if command -v grub-mkconfig &>/dev/null && [[ -f "$_BL_BOOT_DIR/grub/grub.cfg" ]]; then
        echo "grub"
    elif { command -v bootctl &>/dev/null && bootctl is-installed &>/dev/null; } \
         || [[ -d "$_BL_BOOT_DIR/loader/entries" ]]; then
        echo "systemd-boot"
    else
        echo "unknown"
    fi
}

# regenerate_bootloader "<opis kontekstu>"
# Zwraca: 0 = zregenerowano (GRUB), 1 = próba się nie powiodła (także brak
#         install/lib/pkg.sh — platforma nieznana), 2 = wymagany krok ręczny
#         (systemd-boot / nieznany bootloader / platforma inna niż Arch).
regenerate_bootloader() {
    local context="${1:-boot configuration change}"
    local bl
    if ! declare -F pkg_gate >/dev/null; then
        echo -e "  ${_BL_RED}✗ install/lib/pkg.sh is not loaded — platform unknown, boot configuration unchanged.${_BL_NC}"
        return 1
    fi
    # Poza Archem i pochodnymi: bez wykrywania i bez grub-mkconfig, /boot nietknięty.
    if ! pkg_gate "Boot configuration ($context)"; then
        case "$PKG_ROUTE" in
            fedora)
                echo "    Fedora's kernel and microcode packages update the boot entries themselves"
                echo "    (kernel-install, BLS). If they look wrong: sudo grub2-mkconfig -o /boot/grub2/grub.cfg" ;;
            nixos)
                echo "    NixOS writes the boot entries itself: sudo nixos-rebuild boot (or switch)."
                echo "    Do not edit /boot by hand." ;;
        esac
        return 2
    fi
    bl="$(detect_bootloader)"

    case "$bl" in
        grub)
            echo -e "  GRUB detected — regenerating $_BL_BOOT_DIR/grub/grub.cfg..."
            if sudo grub-mkconfig -o "$_BL_BOOT_DIR/grub/grub.cfg"; then
                echo -e "  ${_BL_GREEN}✓ GRUB updated ($context).${_BL_NC}"
                return 0
            else
                echo -e "  ${_BL_RED}✗ grub-mkconfig failed — run manually:${_BL_NC}"
                echo -e "      sudo grub-mkconfig -o $_BL_BOOT_DIR/grub/grub.cfg"
                return 1
            fi
            ;;
        systemd-boot)
            echo -e "  ${_BL_YELLOW}systemd-boot detected — entries are not modified automatically${_BL_NC}"
            echo -e "  ${_BL_YELLOW}(an invalid entry prevents booting). Finish manually for: $context${_BL_NC}"
            echo -e "    • kernel: check that /boot/loader/entries/*.conf has 'linux' and 'initrd' lines"
            echo -e "      for the new kernel. With system kernel-install, find the NEW kernel"
            echo -e "      version (not the running one: \$(uname -r) is the old version) with:"
            echo -e "        ls /usr/lib/modules"
            echo -e "        sudo kernel-install add <NEW-KERNEL-VERSION> /boot/vmlinuz-<KERNEL>"
            echo -e "    • microcode: add BEFORE the main initrd line in every entry:"
            echo -e "        initrd  /amd-ucode.img      # AMD"
            echo -e "        initrd  /intel-ucode.img    # Intel"
            return 2
            ;;
        *)
            echo -e "  ${_BL_YELLOW}⚠ Bootloader not recognized — update the boot configuration${_BL_NC}"
            echo -e "  ${_BL_YELLOW}  manually for: $context${_BL_NC}"
            return 2
            ;;
    esac
}
