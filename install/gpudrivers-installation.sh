#!/bin/bash

# =============================================
#   archenemy - gpudrivers-installation.sh
#   Instaluje sterowniki GPU dla wykrytej karty.
# =============================================

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Haki testowe (tests/gpudrivers.sh): katalog /etc i katalog modułów jądra
# podmieniane na atrapę w mktemp. W normalnym biegu nieustawione = system.
ETC_DIR="${ARCHENEMY_ETC_DIR:-/etc}"
KMOD_DIR="${ARCHENEMY_MODULES_DIR:-/usr/lib/modules}"

# ─── WYKRYWANIE GPU ───────────────────────────────────────────────────────────

# lspci (pciutils) bywa nieobecne na minimalnym Archu — bez guarda cała
# instalacja GPU cicho się pomijała z mylącym „nie dopasowano żadnego GPU".
if ! command -v lspci &>/dev/null; then
    echo -e "${YELLOW}lspci (pciutils) is missing — required to detect the GPU. Installing...${NC}"
    if ! sudo pacman -S --needed pciutils; then
        echo -e "${RED}✗ Could not install pciutils — install it manually (sudo pacman -S pciutils) and run this script again.${NC}"
        exit 1
    fi
fi

GPU_INFO="$(lspci | grep -Ei 'vga|3d|display')"
if [[ -z "$GPU_INFO" ]]; then
    echo -e "${YELLOW}lspci reports no GPU (vga/3d/display) — skipping driver installation.${NC}"
    exit 0
fi
echo -e "${YELLOW}Detected GPUs:${NC}"
echo "$GPU_INFO"
echo ""

PKGS=()
HAS_NVIDIA=0
PKG_FAILED=0
MULTILIB_ENABLED_NOW=0

# NVIDIA: sterownik open kontra własnościowy zależy od generacji karty, a tego
# nie da się pewnie odczytać z lspci — pytamy użytkownika, z sensowną domyślną.
choose_nvidia_variant() {
    echo -e "${YELLOW}Choose the NVIDIA kernel module variant:${NC}"
    echo "  1) nvidia-open-dkms   (recommended for Turing and newer: GTX 16xx / RTX 20xx+)"
    echo "  2) nvidia-dkms        (proprietary: Maxwell/Pascal and older, GTX 9xx/10xx)"
    read -rp "  Choice [default: 1]: " nv_choice
    case "$nv_choice" in
        2) PKGS+=(nvidia-dkms nvidia-utils) ;;
        *) PKGS+=(nvidia-open-dkms nvidia-utils) ;;
    esac
    # Warianty *-dkms budują moduł przy instalacji — bez nagłówków jądra
    # moduł nie powstaje, a nvidia-utils i tak blokuje nouveau (czarny
    # ekran). Nagłówki dla KAŻDEGO zainstalowanego jądra (pkgbase w
    # katalogu modułów — tak oznaczają się jądra z repozytoriów Archa).
    local d kernel
    for d in "$KMOD_DIR"/*/; do
        [[ -f "$d/pkgbase" ]] || continue
        kernel="$(<"$d/pkgbase")"
        [[ -n "$kernel" ]] && PKGS+=("${kernel}-headers")
    done
}

# Jądra (wersje z katalogu modułów), dla których NIE ma modułu nvidia —
# po jednej na linię; puste wyjście = moduł jest dla wszystkich.
nvidia_module_missing() {
    local d kver
    for d in "$KMOD_DIR"/*/; do
        [[ -f "$d/pkgbase" ]] || continue
        kver="$(basename "$d")"
        modinfo -k "$kver" nvidia &>/dev/null || echo "$kver"
    done
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
        echo -e "${YELLOW}NVIDIA driver already installed: $NV_INSTALLED${NC}"
        echo "  1) Update drivers"
        echo "  2) Switch variant (open ↔ proprietary)"
        echo "  3) Leave unchanged"
        read -rp "  Choice [default: 3]: " nv_action
        case "$nv_action" in
            1)
                # Aktualizacja samego sterownika to partial upgrade — moduł może
                # rozjechać się z jądrem (czarny ekran). Jedyna wspierana droga
                # na Archu to pełne -Syu; moduły DKMS przebudują się same.
                echo -e "  Full system upgrade (the safe approach on Arch)..."
                if sudo pacman -Syu; then
                    echo -e "  ${GREEN}✓ System and NVIDIA driver updated.${NC}"
                else
                    echo -e "  ${RED}✗ Upgrade failed — run manually: sudo pacman -Syu${NC}"
                fi
                ;;
            2)
                # pacman sam zaproponuje usunięcie konfliktującego wariantu.
                choose_nvidia_variant
                ;;
            *)
                echo -e "  Keeping $NV_INSTALLED unchanged (only adding missing configuration)."
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
    echo -e "${YELLOW}No known GPU matched — skipping.${NC}"
    exit 0
fi

if [[ ${#PKGS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}Proposed packages: ${PKGS[*]}${NC}"
    read -rp "Install? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}Skipped.${NC}"; exit 0; }

    # Wynik sprawdzany: dawniej „✓” pojawiało się zawsze, a kroki
    # poinstalacyjne (initramfs) szły mimo nieudanej instalacji.
    if sudo pacman -S --needed "${PKGS[@]}"; then
        echo -e "${GREEN}✓ GPU drivers installed.${NC}"
    else
        PKG_FAILED=1
        echo -e "${RED}✗ Package installation failed — leaving initramfs unchanged. Fix the pacman error and run this script again.${NC}"
    fi
fi

# ─── MULTILIB + LIB32 (32-bit Vulkan/GL dla Steama i gier Proton/Wine) ────────

# Włącza repo [multilib] w $ETC_DIR/pacman.conf: odkomentowuje standardowy blok,
# a gdy go w ogóle nie ma — dopisuje na końcu. Backup: .bak-archenemy.
ensure_multilib() {
    if grep -qE '^\[multilib\]' $ETC_DIR/pacman.conf; then
        echo -e "  ${GREEN}✓ Repository [multilib] already enabled.${NC}"
        return 0
    fi
    sudo cp $ETC_DIR/pacman.conf $ETC_DIR/pacman.conf.bak-archenemy
    if grep -qE '^#\[multilib\]' $ETC_DIR/pacman.conf; then
        sudo sed -i '/^#\[multilib\]$/,/^#Include = \/etc\/pacman.d\/mirrorlist$/ s/^#//' $ETC_DIR/pacman.conf
    else
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a $ETC_DIR/pacman.conf >/dev/null
    fi
    if grep -qE '^\[multilib\]' $ETC_DIR/pacman.conf; then
        echo -e "  ${GREEN}✓ Enabled [multilib] (backup: $ETC_DIR/pacman.conf.bak-archenemy).${NC}"
        # Bez `pacman -Sy` tutaj: samo odświeżenie baz + instalacja to
        # częściowa aktualizacja (niewspierana na Archu). Instalacja lib32
        # niżej robi wtedy pełne -Syu w jednej transakcji.
        MULTILIB_ENABLED_NOW=1
    else
        echo -e "  ${RED}✗ Could not enable [multilib] — enable it manually in $ETC_DIR/pacman.conf.${NC}"
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
    echo -e "${YELLOW}32-bit gaming support (Steam/Proton/Wine): ${MISSING32[*]}${NC}"
    read -rp "Install? (enables [multilib] if needed) [Y/n]: " ans32
    if [[ ! "$ans32" =~ ^[Nn]$ ]]; then
        if ensure_multilib; then
            if [[ "$MULTILIB_ENABLED_NOW" -eq 1 ]]; then
                echo -e "  ${YELLOW}New repository requires new package databases: full system upgrade with lib32 (pacman -Syu).${NC}"
                LIB32_CMD=(sudo pacman -Syu --needed "${MISSING32[@]}")
            else
                LIB32_CMD=(sudo pacman -S --needed "${MISSING32[@]}")
            fi
            if "${LIB32_CMD[@]}"; then
                echo -e "${GREEN}✓ lib32 packages installed.${NC}"
            else
                echo -e "${RED}✗ lib32 installation failed — Steam/Proton may not start.${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}Skipped — Steam and 32-bit games will not start without lib32.${NC}"
    fi
elif [[ ${#LIB32_PKGS[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}✓ lib32 gaming packages already installed.${NC}"
fi

# ─── NVIDIA: KROKI POINSTALACYJNE ─────────────────────────────────────────────
# Na Wayландzie NVIDIA wymaga DRM KMS. Ustawiamy go przez modprobe.d
# (options nvidia_drm modeset=1) — działa niezależnie od bootloadera, w
# przeciwieństwie do parametru jądra nvidia_drm.modeset=1. Moduły dokładamy do
# initramfs, żeby KMS działał od wczesnego bootu (brak migotania/czarnego ekranu).
if [[ "$HAS_NVIDIA" -eq 1 ]]; then
    echo ""
    echo -e "${YELLOW}Configuring NVIDIA for Wayland/Hyprland...${NC}"

    # 1) DRM KMS przez modprobe.d
    MODPROBE_CONF="$ETC_DIR/modprobe.d/nvidia.conf"
    if [[ -f "$MODPROBE_CONF" ]] && grep -q 'nvidia_drm' "$MODPROBE_CONF"; then
        echo -e "  ${GREEN}✓ $MODPROBE_CONF already sets nvidia_drm — left as it is.${NC}"
    else
        echo 'options nvidia_drm modeset=1 fbdev=1' | sudo tee "$MODPROBE_CONF" >/dev/null
        echo -e "  ${GREEN}✓ $MODPROBE_CONF (modeset=1 fbdev=1).${NC}"
    fi

    # 2) Moduły NVIDIA w initramfs (wczesny KMS)
    MKINIT="$ETC_DIR/mkinitcpio.conf"
    NV_MISSING="$(nvidia_module_missing)"
    if [[ "$PKG_FAILED" -eq 1 ]]; then
        echo -e "  ${YELLOW}⚠ Skipping initramfs modules — driver installation failed.${NC}"
    elif [[ -n "$NV_MISSING" ]]; then
        # Moduł w MODULES bez zbudowanego modułu = mkinitcpio z błędem
        # albo start bez sterownika (czarny ekran) — nie ryzykujemy.
        echo -e "  ${RED}✗ The nvidia module is not built for kernel: $(tr '\n' ' ' <<<"$NV_MISSING")${NC}"
        echo -e "  ${RED}  Leaving $MKINIT unchanged. Check: dkms status; missing headers: sudo pacman -S <kernel>-headers;${NC}"
        echo -e "  ${RED}  then run this script again.${NC}"
    elif [[ -f "$MKINIT" ]]; then
        if grep -qE '^MODULES=.*nvidia_drm' "$MKINIT"; then
            echo -e "  ${GREEN}✓ mkinitcpio already has NVIDIA modules.${NC}"
        else
            sudo cp "$MKINIT" "$MKINIT.bak-archenemy"
            # Wstaw 4 moduły na początek tablicy MODULES=(...) — działa i dla pustej.
            sudo sed -i -E \
                's/^(MODULES=\()(.*)(\))/\1nvidia nvidia_modeset nvidia_uvm nvidia_drm \2\3/' \
                "$MKINIT"
            # sed nic nie robi, gdy linia MODULES=(...) jest zakomentowana albo
            # w formie MODULES=""— zweryfikuj wynik, zanim ogłosimy sukces.
            if grep -qE '^MODULES=.*nvidia_drm' "$MKINIT"; then
                echo -e "  ${GREEN}✓ Added NVIDIA modules to $MKINIT (backup: .bak-archenemy).${NC}"
                if sudo mkinitcpio -P; then
                    echo -e "  ${GREEN}✓ initramfs rebuilt.${NC}"
                else
                    echo -e "  ${RED}✗ mkinitcpio -P failed — check $MKINIT (backup alongside).${NC}"
                fi
            else
                echo -e "  ${RED}✗ No active MODULES=(...) line found in $MKINIT — add manually:${NC}"
                echo -e "      MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)"
                echo -e "      and rebuild initramfs: sudo mkinitcpio -P"
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠ No $MKINIT — skipping early modules (use your own initramfs generator).${NC}"
    fi

    # 3) Zmienne środowiskowe Hyprlanda (GBM_BACKEND, LIBVA_DRIVER_NAME, ...)
    #    generuje już główny install.sh do config/hypr/gpu-env.lua — tu ich nie
    #    dublujemy, żeby nie rozjechać się z warstwą maszynową.
    echo -e "  ${YELLOW}install.sh sets NVIDIA Wayland variables (config/hypr/gpu-env.lua).${NC}"
    echo -e "  ${YELLOW}Reboot to apply modeset and module changes.${NC}"
fi
