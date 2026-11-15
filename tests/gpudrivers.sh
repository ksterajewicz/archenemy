#!/bin/bash
# =============================================
#   archenemy - tests/gpudrivers.sh
#   Testy instalatora sterowników GPU (install/gpudrivers-installation.sh)
#   na ATRAPACH: sudo, pacman, lspci, modinfo, mkinitcpio w PATH, a /etc
#   i katalog modułów jądra podmienione hakami ARCHENEMY_ETC_DIR /
#   ARCHENEMY_MODULES_DIR na katalogi w mktemp. Bez roota, bez sieci,
#   bez dotykania prawdziwego systemu.
#
#   Powód powstania (audyt 2026-09-23): wynik `pacman -S` niesprawdzany
#   („✓” zawsze), warianty *-dkms bez nagłówków jądra, a MODULES +
#   `mkinitcpio -P` szły także wtedy, gdy moduł nvidia nie powstał (ryzyko
#   czarnego ekranu); po włączeniu [multilib] `pacman -Sy` = częściowa
#   aktualizacja. Wersji sprzed poprawki NIE da się tu uruchomić — nie ma
#   haków i pisałaby do prawdziwego /etc — więc test odmawia bez nich.
#   Uruchom: bash tests/gpudrivers.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval (zmienne żyją w eval); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPU="$REPO/install/gpudrivers-installation.sh"
if ! grep -q 'ARCHENEMY_ETC_DIR' "$GPU" || ! grep -q 'ARCHENEMY_MODULES_DIR' "$GPU"; then
    echo "✗ $GPU bez haków testowych — nie uruchamiam (dotknąłby prawdziwego /etc)"
    exit 1
fi
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── atrapy ──────────────────────────────────────────────────────────────────
mkdir -p "$T/bin"
cat > "$T/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
# lspci: MOCK_PCI = wiersze „<klasa PCI> <wiersz lspci>”; `-d ::<klasa>` filtruje
# po klasie jak pciutils („x” = dowolna cyfra), bez -d drukuje wszystko.
cat > "$T/bin/lspci" <<'EOF'
#!/bin/bash
pci="${MOCK_PCI:-0300 01:00.0 VGA compatible controller: NVIDIA Corporation AD106M [GeForce RTX 4070 Max-Q / Mobile]}"
want=""
[[ "${1:-}" == -d && "${2:-}" == ::* ]] && want="${2#::}"
while read -r cls line; do
    [[ -n "$cls" ]] || continue
    if [[ -n "$want" ]]; then
        pat="${want//x/?}"   # wzorzec glob, dlatego $pat bez cudzysłowu
        [[ "$cls" == $pat ]] || continue
    fi
    printf '%s\n' "$line"
done <<<"$pci"
EOF
# pacman: -Qi <pkg> = zainstalowany, jeśli jest w MOCK_INSTALLED; -S/-Syu
# logowane; porażka na żądanie: instalacji sterownika (MOCK_PACMAN_FAIL=1),
# lib32 (MOCK_PACMAN_FAIL_LIB32=1), samego -Syu ze ścieżki „1) Update”
# (MOCK_PACMAN_FAIL_SYU=1).
cat > "$T/bin/pacman" <<'EOF'
#!/bin/bash
echo "pacman $*" >> "$MOCK_LOG"
if [[ "$1" == "-Qi" ]]; then
    [[ " ${MOCK_INSTALLED:-} " == *" $2 "* ]]; exit
fi
[[ "${MOCK_PACMAN_FAIL:-0}" == 1 && "$*" == *nvidia-open-dkms* ]] && exit 1
[[ "${MOCK_PACMAN_FAIL_LIB32:-0}" == 1 && "$*" == *lib32-* ]] && exit 1
[[ "${MOCK_PACMAN_FAIL_SYU:-0}" == 1 && "$*" == "-Syu" ]] && exit 1
exit 0
EOF
# modinfo -k <kver> nvidia: moduł „jest”, gdy w atrapie leży <kver>/nvidia.ko
cat > "$T/bin/modinfo" <<'EOF'
#!/bin/bash
[[ "$1" == "-k" && -f "$ARCHENEMY_MODULES_DIR/$2/nvidia.ko" ]]
EOF
cat > "$T/bin/mkinitcpio" <<'EOF'
#!/bin/bash
echo "mkinitcpio $*" >> "$MOCK_LOG"
[[ "${MOCK_MKINIT_FAIL:-0}" != 1 ]]   # MOCK_MKINIT_FAIL=1 = przebudowa nieudana
EOF
# tee, które nic nie zapisze (np. system plików tylko do odczytu) — w PATH
# tylko przypadku I, pozostałe przypadki mają prawdziwe tee.
mkdir -p "$T/bin-tee-fail"
cat > "$T/bin-tee-fail/tee" <<'EOF'
#!/bin/bash
cat >/dev/null
echo "tee: $*: Read-only file system" >&2
exit 1
EOF
chmod +x "$T/bin"/* "$T/bin-tee-fail/tee"
export PATH="$T/bin:$PATH"
export MOCK_LOG="$T/log"

setup() {   # setup <kernele z modułem…> -- <kernele bez modułu…>
    rm -rf "${T:?}/etc" "${T:?}/modules"; : > "$MOCK_LOG"
    mkdir -p "$T/etc/modprobe.d" "$T/modules"
    printf 'MODULES=()\nHOOKS=(base udev)\n' > "$T/etc/mkinitcpio.conf"
    printf '[options]\n#[multilib]\n#Include = /etc/pacman.d/mirrorlist\n' > "$T/etc/pacman.conf"
    local with=1 k
    for k in "$@"; do
        [[ "$k" == -- ]] && { with=0; continue; }
        mkdir -p "$T/modules/$k"
        echo "${k%-*}" > "$T/modules/$k/pkgbase"   # linux-lts-6.12 → linux-lts
        [[ "$with" -eq 1 ]] && : > "$T/modules/$k/nvidia.ko"
    done
    export ARCHENEMY_TEST=1 ARCHENEMY_ETC_DIR="$T/etc" ARCHENEMY_MODULES_DIR="$T/modules"
}
# stdin: wariant (1 = open-dkms), potwierdzenie instalacji, odpowiedź lib32
run_gpu() { printf '%b' "$1" | bash "$GPU" 2>&1; }

echo "== A: instalacja udana, moduł zbudowany"
setup "linux-6.16"
out=$(MOCK_INSTALLED="" run_gpu '1\ny\nn\n'); rc=$?
check "kod wyjścia 0"                          '[[ $rc -eq 0 ]]'
check "nagłówki jądra w transakcji"            'grep -q "pacman -S --needed.*nvidia-open-dkms.*linux-headers" "$MOCK_LOG"'
check "moduły NVIDIA w MODULES"                'grep -q "^MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm" "$T/etc/mkinitcpio.conf"'
check "initramfs przebudowany"                 'grep -q "mkinitcpio -P" "$MOCK_LOG"'
check "modeset przez modprobe.d"               'grep -q "modeset=1" "$T/etc/modprobe.d/nvidia.conf"'

echo "== B: instalacja nieudana"
setup "linux-6.16"
out=$(MOCK_INSTALLED="" MOCK_PACMAN_FAIL=1 run_gpu '1\ny\nn\n'); rc=$?
check "kod wyjścia ≠ 0 (install.sh [6.5] wpisuje porażkę do podsumowania)" '[[ $rc -ne 0 ]]'
check "brak fałszywego „✓ zainstalowane”"      '[[ "$out" != *"✓ GPU drivers installed"* ]]'
check "jawny błąd"                             '[[ "$out" == *"✗ Package installation failed"* ]]'
check "MODULES nietknięte"                     'grep -q "^MODULES=()$" "$T/etc/mkinitcpio.conf"'
check "initramfs NIE przebudowany"             '! grep -q mkinitcpio "$MOCK_LOG"'

echo "== C: moduł nie powstał dla jednego z jąder"
setup "linux-6.16" -- "linux-lts-6.12"
out=$(MOCK_INSTALLED="" run_gpu '1\ny\nn\n'); rc=$?
check "kod wyjścia ≠ 0 (initramfs nie skończony)" '[[ $rc -ne 0 ]]'
check "nagłówki obu jąder"                     'grep -q "linux-headers" "$MOCK_LOG" && grep -q "linux-lts-headers" "$MOCK_LOG"'
check "ostrzeżenie wskazuje jądro"             '[[ "$out" == *"linux-lts-6.12"* ]]'
check "MODULES nietknięte"                     'grep -q "^MODULES=()$" "$T/etc/mkinitcpio.conf"'
check "initramfs NIE przebudowany"             '! grep -q mkinitcpio "$MOCK_LOG"'

echo "== D: włączenie [multilib] bez częściowej aktualizacji"
setup "linux-6.16"
out=$(MOCK_INSTALLED="nvidia-open-dkms nvidia-utils" run_gpu '3\ny\n'); rc=$?
check "kod wyjścia 0"                          '[[ $rc -eq 0 ]]'
check "multilib odkomentowany"                 'grep -q "^\[multilib\]" "$T/etc/pacman.conf"'
check "brak gołego pacman -Sy"                 '! grep -qx "pacman -Sy" "$MOCK_LOG"'
check "lib32 w pełnym -Syu"                    'grep -q "pacman -Syu --needed lib32-nvidia-utils" "$MOCK_LOG"'

echo "== E: lib32 nie zainstalowane"
setup "linux-6.16"
out=$(MOCK_INSTALLED="nvidia-open-dkms nvidia-utils" MOCK_PACMAN_FAIL_LIB32=1 run_gpu '3\ny\n'); rc=$?
check "jawny błąd lib32"                       '[[ "$out" == *"✗ lib32 installation failed"* ]]'
check "kod wyjścia ≠ 0"                        '[[ $rc -ne 0 ]]'

echo "== F: odmowa instalacji = nie porażka"
setup "linux-6.16"
out=$(MOCK_INSTALLED="" run_gpu '1\nn\n'); rc=$?
check "Skipped, kod wyjścia 0"                 '[[ "$out" == *"Skipped."* && $rc -eq 0 ]]'

# Audyt 2026-11-05, Z14: `grep -Ei 'vga|3d|display'` na całym lspci łapał adres
# PCI „3d:00.0” — karta sieciowa Intela na szynie 0x3d dawała sterowniki Intela.
# GPU = urządzenie klasy PCI 03xx (VGA 0300, 3D 0302, display 0380).
PCI_AMD_NET=$'0300 03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23\n0280 3d:00.0 Network controller: Intel Corporation Wi-Fi 6 AX201'
echo "== G: adres PCI 3d: to nie GPU"
setup "linux-6.16"
out=$(MOCK_PCI="$PCI_AMD_NET" run_gpu 'n\n'); rc=$?
check "AMD wykryte, sieciówka Intela nie"      '[[ "$out" == *"Navi 23"* && "$out" != *"Network controller"* ]]'
check "propozycja bez pakietów Intela"         '[[ "$out" == *"Proposed packages: mesa vulkan-radeon libva-mesa-driver"* && "$out" != *"vulkan-intel"* && $rc -eq 0 ]]'
out=$(MOCK_PCI=$'0280 3d:00.0 Network controller: Intel Corporation Wi-Fi 6 AX201\n0302 3e:00.0 3D controller: NVIDIA Corporation GA107M' run_gpu '1\nn\n'); rc=$?
check "3D controller (klasa 0302) to GPU"      '[[ "$out" == *"GA107M"* && "$out" != *"Network controller"* && "$out" != *"vulkan-intel"* ]]'
out=$(MOCK_PCI=$'0280 3d:00.0 Network controller: Intel Corporation Wi-Fi 6 AX201' run_gpu ''); rc=$?
check "bez GPU: nic nie proponuje, kod 0"      '[[ "$out" == *"reports no GPU"* && "$out" != *"Proposed packages"* && $rc -eq 0 ]]'

echo "== G: install.sh [8d] (gpu-env.lua) — ta sama klasa PCI"
INST="$REPO/install/install.sh"
S=$(grep -n '^# 8d\. ' "$INST" | cut -d: -f1); E=$(grep -n '^# 8e\. ' "$INST" | cut -d: -f1)
sed -n "${S},$((E-1))p" "$INST" > "$T/step8d.sh"
mkdir -p "$T/hl"
gpu_kind() { MOCK_PCI="$1" HYPR_LOCAL_DIR="$T/hl" GREEN='' NC='' bash "$T/step8d.sh" >/dev/null 2>&1; head -n1 "$T/hl/gpu-env.lua"; }
check "wycinek [8d] znaleziony"                '[[ -s "$T/step8d.sh" ]]'
check "[8d] AMD + sieciówka Intela na 3d: → amd" '[[ "$(gpu_kind "$PCI_AMD_NET")" == *"GPU: amd" ]]'
check "[8d] sama sieciówka na 3d: → unknown"   '[[ "$(gpu_kind "0280 3d:00.0 Network controller: Intel Corporation Wi-Fi 6 AX201")" == *"GPU: unknown" ]]'

# Przegląd 2026-11-15 (P-2): każde „✗” daje kod ≠ 0 — inaczej install.sh [6.5]
# nie wpisze porażki do podsumowania, a baner ogłosi pełny sukces. Każdy
# przypadek psuje DOKŁADNIE jeden krok, reszta przechodzi, więc kod ≠ 0 pochodzi
# tylko z niego; pozostałe trzy miejsca STEP_FAILED=1 sprawdzają przypadki B, C, E.
echo "== H: aktualizacja sterownika (pełne -Syu)"
NV_ALL="nvidia-open-dkms nvidia-utils lib32-nvidia-utils"
setup "linux-6.16"
out=$(MOCK_INSTALLED="$NV_ALL" run_gpu '1\n'); rc=$?
check "udane -Syu: ✓ i kod wyjścia 0"          '[[ "$out" == *"✓ System and NVIDIA driver updated"* && $rc -eq 0 ]]'
setup "linux-6.16"
out=$(MOCK_INSTALLED="$NV_ALL" MOCK_PACMAN_FAIL_SYU=1 run_gpu '1\n'); rc=$?
check "nieudane -Syu: jawny błąd"              '[[ "$out" == *"✗ Upgrade failed"* ]]'
check "reszta kroków przeszła (initramfs)"     'grep -q "mkinitcpio -P" "$MOCK_LOG"'
check "nieudane -Syu: kod wyjścia ≠ 0"         '[[ $rc -ne 0 ]]'

echo "== I: [multilib] nie dał się włączyć"
setup "linux-6.16"
printf '[options]\n' > "$T/etc/pacman.conf"   # bez bloku multilib → dopisanie przez tee -a
PCI_AMD='0300 03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23'
out=$(MOCK_PCI="$PCI_AMD" PATH="$T/bin-tee-fail:$PATH" run_gpu 'y\ny\n'); rc=$?
check "sterowniki AMD zainstalowane"           '[[ "$out" == *"✓ GPU drivers installed"* ]]'
check "jawny błąd [multilib]"                  '[[ "$out" == *"✗ Could not enable [multilib]"* ]]'
check "lib32 bez instalacji"                   '! grep -q "pacman -S.* lib32-" "$MOCK_LOG"'
check "kod wyjścia ≠ 0"                        '[[ $rc -ne 0 ]]'

echo "== J: mkinitcpio -P nieudane"
setup "linux-6.16"
out=$(MOCK_INSTALLED="" MOCK_MKINIT_FAIL=1 run_gpu '1\ny\nn\n'); rc=$?
check "moduły NVIDIA w MODULES"                'grep -q "^MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm" "$T/etc/mkinitcpio.conf"'
check "jawny błąd mkinitcpio"                  '[[ "$out" == *"✗ mkinitcpio -P failed"* ]]'
check "kod wyjścia ≠ 0"                        '[[ $rc -ne 0 ]]'

echo "== K: brak aktywnej linii MODULES=(…)"
setup "linux-6.16"
printf '#MODULES=()\nHOOKS=(base udev)\n' > "$T/etc/mkinitcpio.conf"
out=$(MOCK_INSTALLED="" run_gpu '1\ny\nn\n'); rc=$?
check "jawny błąd z instrukcją"                '[[ "$out" == *"✗ No active MODULES=(...) line"* ]]'
check "initramfs NIE przebudowany"             '! grep -q mkinitcpio "$MOCK_LOG"'
check "kod wyjścia ≠ 0"                        '[[ $rc -ne 0 ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
