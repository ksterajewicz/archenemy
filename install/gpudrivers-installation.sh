#!/bin/bash

# =============================================
#   archenemy - gpudrivers-installation.sh
#   Instaluje sterowniki GPU dla wykrytej karty.
# =============================================

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# ─── WYKRYWANIE GPU ───────────────────────────────────────────────────────────

GPU_INFO="$(lspci | grep -Ei 'vga|3d|display')"
echo -e "${YELLOW}Wykryte GPU:${NC}"
echo "$GPU_INFO"
echo ""

PKGS=()
HAS_NVIDIA=0

# NVIDIA: sterownik open kontra własnościowy zależy od generacji karty, a tego
# nie da się pewnie odczytać z lspci — pytamy użytkownika, z sensowną domyślną.
choose_nvidia_variant() {
    echo -e "${YELLOW}Wybierz wariant modułów jądra NVIDIA:${NC}"
    echo "  1) nvidia-open-dkms   (zalecane dla Turing i nowszych: GTX 16xx / RTX 20xx+)"
    echo "  2) nvidia-dkms        (własnościowy: Maxwell/Pascal i starsze, GTX 9xx/10xx)"
    read -rp "  Wybór [default: 1]: " nv_choice
    case "$nv_choice" in
        2) PKGS+=(nvidia-dkms nvidia-utils) ;;
        *) PKGS+=(nvidia-open-dkms nvidia-utils) ;;
    esac
}

if grep -qi 'nvidia' <<<"$GPU_INFO"; then
    HAS_NVIDIA=1

    # Wykryj już zainstalowany wariant — wtedy proponujemy aktualizację lub
    # zmianę wariantu zamiast ponownej instalacji.
    NV_INSTALLED=""
    for p in nvidia-open-dkms nvidia-dkms nvidia-open nvidia; do
        pacman -Qi "$p" &>/dev/null && { NV_INSTALLED="$p"; break; }
    done

    if [[ -n "$NV_INSTALLED" ]]; then
        echo -e "${YELLOW}Sterownik NVIDIA już zainstalowany: $NV_INSTALLED${NC}"
        echo "  1) Aktualizuj sterowniki"
        echo "  2) Zmień wariant (open ↔ własnościowy)"
        echo "  3) Zostaw bez zmian"
        read -rp "  Wybór [default: 3]: " nv_action
        case "$nv_action" in
            1)
                # Aktualizacja samego sterownika to partial upgrade — moduł może
                # rozjechać się z jądrem (czarny ekran). Jedyna wspierana droga
                # na Archu to pełne -Syu; moduły DKMS przebudują się same.
                echo -e "  Pełna aktualizacja systemu (bezpieczna droga na Archu)..."
                if sudo pacman -Syu; then
                    echo -e "  ${GREEN}✓ System i sterownik NVIDIA zaktualizowane.${NC}"
                else
                    echo -e "  ${RED}✗ Aktualizacja nie powiodła się — uruchom ręcznie: sudo pacman -Syu${NC}"
                fi
                ;;
            2)
                # pacman sam zaproponuje usunięcie konfliktującego wariantu.
                choose_nvidia_variant
                ;;
            *)
                echo -e "  Zostawiam $NV_INSTALLED bez zmian (dociągnę tylko brakującą konfigurację)."
                ;;
        esac
    else
        choose_nvidia_variant
    fi
fi

grep -qi 'amd\|radeon' <<<"$GPU_INFO" && PKGS+=(mesa vulkan-radeon libva-mesa-driver)
grep -qi 'intel'       <<<"$GPU_INFO" && PKGS+=(mesa vulkan-intel intel-media-driver)

# PKGS bywa puste także przy NVIDII (ścieżki „aktualizuj"/„zostaw") — wtedy
# nie wychodzimy, tylko przechodzimy do kroków poinstalacyjnych (idempotentne).
if [[ ${#PKGS[@]} -eq 0 && "$HAS_NVIDIA" -eq 0 ]]; then
    echo -e "${YELLOW}Nie dopasowano żadnego znanego GPU — pomijam.${NC}"
    exit 0
fi

if [[ ${#PKGS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}Proponowane pakiety: ${PKGS[*]}${NC}"
    read -rp "Zainstalować? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}Pominięto.${NC}"; exit 0; }

    sudo pacman -S --needed "${PKGS[@]}"
    echo -e "${GREEN}✓ Sterowniki GPU zainstalowane.${NC}"
fi

# ─── MULTILIB + LIB32 (32-bit Vulkan/GL dla Steama i gier Proton/Wine) ────────

# Włącza repo [multilib] w /etc/pacman.conf: odkomentowuje standardowy blok,
# a gdy go w ogóle nie ma — dopisuje na końcu. Backup: .bak-archenemy.
ensure_multilib() {
    if grep -qE '^\[multilib\]' /etc/pacman.conf; then
        echo -e "  ${GREEN}✓ Repo [multilib] już włączone.${NC}"
        return 0
    fi
    sudo cp /etc/pacman.conf /etc/pacman.conf.bak-archenemy
    if grep -qE '^#\[multilib\]' /etc/pacman.conf; then
        sudo sed -i '/^#\[multilib\]$/,/^#Include = \/etc\/pacman.d\/mirrorlist$/ s/^#//' /etc/pacman.conf
    else
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
    fi
    if grep -qE '^\[multilib\]' /etc/pacman.conf; then
        echo -e "  ${GREEN}✓ Włączono [multilib] (backup: /etc/pacman.conf.bak-archenemy).${NC}"
        sudo pacman -Sy
    else
        echo -e "  ${RED}✗ Nie udało się włączyć [multilib] — zrób to ręcznie w /etc/pacman.conf.${NC}"
        return 1
    fi
}

# Bez lib32 nie ma 32-bitowego Vulkan/GL — klient Steam i duża część gier
# Proton/Wine nie wystartuje. Dobieramy pakiety do wykrytej karty.
LIB32_PKGS=()
[[ "$HAS_NVIDIA" -eq 1 ]] && LIB32_PKGS+=(lib32-nvidia-utils)
grep -qi 'amd\|radeon' <<<"$GPU_INFO" && LIB32_PKGS+=(lib32-mesa lib32-vulkan-radeon)
grep -qi 'intel'       <<<"$GPU_INFO" && LIB32_PKGS+=(lib32-mesa lib32-vulkan-intel)

MISSING32=()
for p in "${LIB32_PKGS[@]}"; do
    pacman -Qi "$p" &>/dev/null || MISSING32+=("$p")
done

if [[ ${#MISSING32[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}Wsparcie 32-bit dla gier (Steam/Proton/Wine): ${MISSING32[*]}${NC}"
    read -rp "Zainstalować? (włączy repo [multilib], jeśli trzeba) [Y/n]: " ans32
    if [[ ! "$ans32" =~ ^[Nn]$ ]]; then
        if ensure_multilib; then
            sudo pacman -S --needed "${MISSING32[@]}"
            echo -e "${GREEN}✓ Pakiety lib32 zainstalowane.${NC}"
        fi
    else
        echo -e "${YELLOW}Pominięto — bez lib32 Steam i 32-bitowe gry nie wystartują.${NC}"
    fi
elif [[ ${#LIB32_PKGS[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}✓ Pakiety lib32 dla gier już zainstalowane.${NC}"
fi

# ─── NVIDIA: KROKI POINSTALACYJNE ─────────────────────────────────────────────
# Na Wayландzie NVIDIA wymaga DRM KMS. Ustawiamy go przez modprobe.d
# (options nvidia_drm modeset=1) — działa niezależnie od bootloadera, w
# przeciwieństwie do parametru jądra nvidia_drm.modeset=1. Moduły dokładamy do
# initramfs, żeby KMS działał od wczesnego bootu (brak migotania/czarnego ekranu).
if [[ "$HAS_NVIDIA" -eq 1 ]]; then
    echo ""
    echo -e "${YELLOW}Konfiguruję NVIDIA pod Wayland/Hyprland...${NC}"

    # 1) DRM KMS przez modprobe.d
    MODPROBE_CONF=/etc/modprobe.d/nvidia.conf
    if [[ -f "$MODPROBE_CONF" ]] && grep -q 'nvidia_drm' "$MODPROBE_CONF"; then
        echo -e "  ${GREEN}✓ $MODPROBE_CONF już ustawia nvidia_drm — nie ruszam.${NC}"
    else
        echo 'options nvidia_drm modeset=1 fbdev=1' | sudo tee "$MODPROBE_CONF" >/dev/null
        echo -e "  ${GREEN}✓ $MODPROBE_CONF (modeset=1 fbdev=1).${NC}"
    fi

    # 2) Moduły NVIDIA w initramfs (wczesny KMS)
    MKINIT=/etc/mkinitcpio.conf
    if [[ -f "$MKINIT" ]]; then
        if grep -qE '^MODULES=.*nvidia_drm' "$MKINIT"; then
            echo -e "  ${GREEN}✓ mkinitcpio już ma moduły NVIDIA.${NC}"
        else
            sudo cp "$MKINIT" "$MKINIT.bak-archenemy"
            # Wstaw 4 moduły na początek tablicy MODULES=(...) — działa i dla pustej.
            sudo sed -i -E \
                's/^(MODULES=\()(.*)(\))/\1nvidia nvidia_modeset nvidia_uvm nvidia_drm \2\3/' \
                "$MKINIT"
            echo -e "  ${GREEN}✓ Dopisano moduły NVIDIA do $MKINIT (backup: .bak-archenemy).${NC}"
            if sudo mkinitcpio -P; then
                echo -e "  ${GREEN}✓ initramfs przebudowany.${NC}"
            else
                echo -e "  ${RED}✗ mkinitcpio -P nie powiódł się — sprawdź $MKINIT (backup obok).${NC}"
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠ Brak $MKINIT — pomijam wczesne moduły (użyj swojego generatora initramfs).${NC}"
    fi

    # 3) Zmienne środowiskowe Hyprlanda (GBM_BACKEND, LIBVA_DRIVER_NAME, ...)
    #    generuje już główny install.sh do config/hypr/gpu-env.conf — tu ich nie
    #    dublujemy, żeby nie rozjechać się z warstwą maszynową.
    echo -e "  ${YELLOW}Zmienne Wayland dla NVIDIA ustawia install.sh (config/hypr/gpu-env.conf).${NC}"
    echo -e "  ${YELLOW}Zrestartuj system, aby modeset i moduły weszły w życie.${NC}"
fi
