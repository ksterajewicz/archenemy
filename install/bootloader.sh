#!/bin/bash

# =============================================
#   archenemy - bootloader.sh (biblioteka)
#   Wykrywa bootloader i regeneruje jego konfigurację, żeby świeżo
#   zainstalowany mikrokod / kernel realnie się załadował.
#   Źródłowana (source) przez cpudrivers-installation.sh i kernel-install.sh.
#
#   Zasada bezpieczeństwa: GRUB regenerujemy automatycznie (grub-mkconfig
#   ogarnia i wczesny initrd mikrokodu, i wpisy dla nowych kerneli). Dla
#   systemd-boot i nierozpoznanych NIE ruszamy wpisów rozruchowych — błędny
#   initrd zostawia maszynę bez bootu — tylko wypisujemy dokładne kroki ręczne.
# =============================================

# Własne kolory (biblioteka bywa źródłowana zanim wołający je zdefiniuje).
_BL_GREEN='\033[0;32m'; _BL_YELLOW='\033[1;33m'; _BL_RED='\033[0;31m'; _BL_NC='\033[0m'

# Wypisuje: grub | systemd-boot | unknown
detect_bootloader() {
    if command -v grub-mkconfig &>/dev/null && [[ -f /boot/grub/grub.cfg ]]; then
        echo "grub"
    elif { command -v bootctl &>/dev/null && bootctl is-installed &>/dev/null; } \
         || [[ -d /boot/loader/entries ]]; then
        echo "systemd-boot"
    else
        echo "unknown"
    fi
}

# regenerate_bootloader "<opis kontekstu>"
# Zwraca: 0 = zregenerowano (GRUB), 1 = próba się nie powiodła,
#         2 = wymagany krok ręczny (systemd-boot / nieznany).
regenerate_bootloader() {
    local context="${1:-zmiana rozruchowa}"
    local bl
    bl="$(detect_bootloader)"

    case "$bl" in
        grub)
            echo -e "  Wykryto GRUB — regeneruję /boot/grub/grub.cfg..."
            if sudo grub-mkconfig -o /boot/grub/grub.cfg; then
                echo -e "  ${_BL_GREEN}✓ GRUB zaktualizowany ($context).${_BL_NC}"
                return 0
            else
                echo -e "  ${_BL_RED}✗ grub-mkconfig nie powiódł się — uruchom ręcznie:${_BL_NC}"
                echo -e "      sudo grub-mkconfig -o /boot/grub/grub.cfg"
                return 1
            fi
            ;;
        systemd-boot)
            echo -e "  ${_BL_YELLOW}Wykryto systemd-boot — nie modyfikuję wpisów automatycznie${_BL_NC}"
            echo -e "  ${_BL_YELLOW}(błędny wpis = brak bootu). Dokończ ręcznie dla: $context${_BL_NC}"
            echo -e "    • kernel: sprawdź, czy /boot/loader/entries/*.conf ma linie 'linux' i 'initrd'"
            echo -e "      dla nowego kernela. Z systemowym kernel-install — wersję NOWEGO"
            echo -e "      kernela (nie działającego: \$(uname -r) wskazuje stary!) znajdziesz przez:"
            echo -e "        ls /usr/lib/modules"
            echo -e "        sudo kernel-install add <WERSJA-NOWEGO-KERNELA> /boot/vmlinuz-<KERNEL>"
            echo -e "    • mikrokod: dodaj PRZED główną linią initrd w każdym wpisie:"
            echo -e "        initrd  /amd-ucode.img      # AMD"
            echo -e "        initrd  /intel-ucode.img    # Intel"
            return 2
            ;;
        *)
            echo -e "  ${_BL_YELLOW}⚠ Nie rozpoznano bootloadera — zaktualizuj konfigurację rozruchową${_BL_NC}"
            echo -e "  ${_BL_YELLOW}  ręcznie dla: $context${_BL_NC}"
            return 2
            ;;
    esac
}
