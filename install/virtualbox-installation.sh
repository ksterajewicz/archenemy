#!/bin/bash

# =============================================
#   archenemy - virtualbox-installation.sh
#   Instaluje Oracle VirtualBox (host): pakiety,
#   moduły jądra (DKMS) i grupę vboxusers.
# =============================================

# Sam `pacman -S virtualbox` nie daje działającego VirtualBoksa: jedynym
# dostawcą modułów hosta w repo jest virtualbox-host-dkms (gotowe
# virtualbox-host-modules-arch zniknęło), DKMS buduje vboxdrv tylko dla
# jąder z zainstalowanymi nagłówkami, a moduł wchodzi dopiero po restarcie
# albo modprobe. Bez tego maszyna wirtualna nie startuje („Kernel driver
# not installed”). Źródło: Arch Wiki „VirtualBox”, sekcja instalacji hosta.
#
# Kody wyjścia (kontrakt z install.sh [10]):
#   0 — vboxdrv załadowany w działającym jądrze, VirtualBox gotowy
#   1 — instalacja pakietów albo budowa modułu nie powiodła się
#   2 — pakiety i moduł są, ale vboxdrv nie działa w bieżącym jądrze
#       (jądro zaktualizowane bez restartu albo stara wersja modułu) — restart

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Haki testowe (tests/virtualbox.sh): katalog modułów jądra i /sys/module
# podmieniane na atrapę w mktemp. W normalnym biegu nieustawione = system.
KMOD_DIR="${ARCHENEMY_MODULES_DIR:-/usr/lib/modules}"
SYSMOD_DIR="${ARCHENEMY_SYSMODULE_DIR:-/sys/module}"

# ─── PAKIETY ──────────────────────────────────────────────────────────────────

# Nagłówki dla KAŻDEGO zainstalowanego jądra z repo Archa (pkgbase w katalogu
# modułów) — ten sam wzór co warianty *-dkms w gpudrivers-installation.sh.
PKGS=(virtualbox virtualbox-host-dkms)
KVERS=()
for d in "$KMOD_DIR"/*/; do
    [[ -f "$d/pkgbase" ]] || continue
    kernel="$(<"$d/pkgbase")"
    [[ -n "$kernel" ]] || continue
    KVERS+=("$(basename "$d")")
    [[ " ${PKGS[*]} " == *" ${kernel}-headers "* ]] || PKGS+=("${kernel}-headers")
done

if [[ ${#KVERS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}⚠ No Arch kernel found (pkgbase in $KMOD_DIR) —${NC}"
    echo -e "${YELLOW}  install your kernel headers manually, or DKMS cannot build vboxdrv.${NC}"
fi

echo -e "${YELLOW}Installing: ${PKGS[*]}${NC}"
if ! sudo pacman -S --needed "${PKGS[@]}"; then
    echo -e "${RED}✗ pacman failed — VirtualBox was not installed.${NC}"
    exit 1
fi
for p in virtualbox virtualbox-host-dkms; do
    if ! pacman -Qi "$p" &>/dev/null; then
        echo -e "${RED}✗ Package $p is not installed despite the install attempt — check pacman output.${NC}"
        exit 1
    fi
done
echo -e "  ${GREEN}✓ VirtualBox packages installed.${NC}"

# ─── MODUŁ JĄDRA ──────────────────────────────────────────────────────────────

# Sukces = moduł zbudowany (modinfo go widzi), nie kod wyjścia pacmana —
# hak DKMS przy braku nagłówków tylko ostrzega i nic nie buduje.
MISSING=()
for kver in "${KVERS[@]}"; do
    modinfo -k "$kver" vboxdrv &>/dev/null || MISSING+=("$kver")
done

RUNNING="$(uname -r)"
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "  ${RED}✗ vboxdrv is not built for these kernels: ${MISSING[*]}${NC}"
    echo -e "  ${RED}  Check: dkms status; install missing headers: sudo pacman -S <kernel>-headers;${NC}"
    echo -e "  ${RED}  then: sudo dkms autoinstall${NC}"
fi

if [[ ! -d "$KMOD_DIR/$RUNNING" ]]; then
    # Jądro zaktualizowane, a system nie zrestartowany — modułów działającego
    # jądra już nie ma na dysku, modprobe nic tu nie załaduje.
    echo -e "  ${YELLOW}⚠ The running kernel $RUNNING no longer has modules on disk (updated without reboot).${NC}"
    echo -e "  ${YELLOW}  Reboot — vboxdrv will load automatically (modules-load.d).${NC}"
    exit 2
fi
if [[ " ${MISSING[*]} " == *" $RUNNING "* ]]; then
    exit 1
fi

if [[ -d "$SYSMOD_DIR/vboxdrv" ]]; then
    # Już załadowany — po aktualizacji pakietu w pamięci może siedzieć stara
    # wersja. Porównujemy tylko, gdy obie wersje da się odczytać.
    loaded_ver="$(cat "$SYSMOD_DIR/vboxdrv/version" 2>/dev/null || true)"
    built_ver="$(modinfo -k "$RUNNING" -F version vboxdrv 2>/dev/null || true)"
    if [[ -n "$loaded_ver" && -n "$built_ver" && "$loaded_ver" != "$built_ver" ]]; then
        echo -e "  ${YELLOW}⚠ Loaded vboxdrv $loaded_ver, built $built_ver —${NC}"
        echo -e "  ${YELLOW}  shut down virtual machines and run: sudo vboxreload (or reboot).${NC}"
        exit 2
    fi
    echo -e "  ${GREEN}✓ vboxdrv already loaded.${NC}"
else
    # vboxnetadp/vboxnetflt są potrzebne tylko dla sieci bridged/host-only —
    # ich porażka nie blokuje maszyn wirtualnych, więc tylko ostrzegamy.
    sudo modprobe vboxdrv
    if [[ ! -d "$SYSMOD_DIR/vboxdrv" ]]; then
    echo -e "  ${RED}✗ modprobe vboxdrv did not load the module — check: sudo dmesg | grep -i vbox${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✓ vboxdrv loaded.${NC}"
    for m in vboxnetadp vboxnetflt; do
        sudo modprobe "$m" && [[ -d "$SYSMOD_DIR/$m" ]] \
            || echo -e "  ${YELLOW}⚠ $m not loaded — bridged/host-only networking will work after reboot.${NC}"
    done
fi

# ─── GRUPA vboxusers (USB w maszynach wirtualnych) ────────────────────────────

# Grupę tworzy pakiet (sysusers.d), ale nikogo do niej nie dodaje. Zmiana
# grup użytkownika to decyzja użytkownika — pytamy, domyślnie nie.
# Bez `| grep -q` — z pipefail wczesne wyjście grepa daje fałszywą porażkę.
VB_USER="${USER:-$(id -un)}"
in_vboxusers() { [[ " $(id -nG "$VB_USER" 2>/dev/null) " == *" vboxusers "* ]]; }
if in_vboxusers; then
    echo -e "  ${GREEN}✓ $VB_USER is already in vboxusers.${NC}"
elif ! getent group vboxusers &>/dev/null; then
    echo -e "  ${YELLOW}⚠ vboxusers group is missing — USB in virtual machines will not work (the package should create it).${NC}"
else
    read -rp "  Add $VB_USER to vboxusers (USB devices in virtual machines)? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        sudo usermod -aG vboxusers "$VB_USER"
        if in_vboxusers; then
            echo -e "  ${GREEN}✓ Added to vboxusers — takes effect after logging in again.${NC}"
        else
            echo -e "  ${RED}✗ Could not add user to vboxusers — run manually: sudo usermod -aG vboxusers $VB_USER${NC}"
        fi
    fi
fi

echo -e "  ${YELLOW}Guest Additions for non-Arch guests: sudo pacman -S virtualbox-guest-iso${NC}"
exit 0
