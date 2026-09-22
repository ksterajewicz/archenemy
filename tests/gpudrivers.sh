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
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

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
cat > "$T/bin/lspci" <<'EOF'
#!/bin/bash
echo "01:00.0 VGA compatible controller: NVIDIA Corporation AD106M [GeForce RTX 4070 Max-Q / Mobile]"
EOF
# pacman: -Qi <pkg> = zainstalowany, jeśli jest w MOCK_INSTALLED; -S/-Syu
# logowane, porażka instalacji na żądanie (MOCK_PACMAN_FAIL=1).
cat > "$T/bin/pacman" <<'EOF'
#!/bin/bash
echo "pacman $*" >> "$MOCK_LOG"
if [[ "$1" == "-Qi" ]]; then
    [[ " ${MOCK_INSTALLED:-} " == *" $2 "* ]]; exit
fi
[[ "${MOCK_PACMAN_FAIL:-0}" == 1 && "$*" == *nvidia-open-dkms* ]] && exit 1
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
EOF
chmod +x "$T/bin"/*
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
    export ARCHENEMY_ETC_DIR="$T/etc" ARCHENEMY_MODULES_DIR="$T/modules"
}
# stdin: wariant (1 = open-dkms), potwierdzenie instalacji, odpowiedź lib32
run_gpu() { printf '%b' "$1" | bash "$GPU" 2>&1; }

echo "== A: instalacja udana, moduł zbudowany"
setup "linux-6.16"
out=$(MOCK_INSTALLED="" run_gpu '1\ny\nn\n')
check "nagłówki jądra w transakcji"            'grep -q "pacman -S --needed.*nvidia-open-dkms.*linux-headers" "$MOCK_LOG"'
check "moduły NVIDIA w MODULES"                'grep -q "^MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm" "$T/etc/mkinitcpio.conf"'
check "initramfs przebudowany"                 'grep -q "mkinitcpio -P" "$MOCK_LOG"'
check "modeset przez modprobe.d"               'grep -q "modeset=1" "$T/etc/modprobe.d/nvidia.conf"'

echo "== B: instalacja nieudana"
setup "linux-6.16"
out=$(MOCK_INSTALLED="" MOCK_PACMAN_FAIL=1 run_gpu '1\ny\nn\n')
check "brak fałszywego „✓ zainstalowane”"      '[[ "$out" != *"✓ Sterowniki GPU zainstalowane"* ]]'
check "jawny błąd"                             '[[ "$out" == *"✗ Instalacja pakietów nie powiodła się"* ]]'
check "MODULES nietknięte"                     'grep -q "^MODULES=()$" "$T/etc/mkinitcpio.conf"'
check "initramfs NIE przebudowany"             '! grep -q mkinitcpio "$MOCK_LOG"'

echo "== C: moduł nie powstał dla jednego z jąder"
setup "linux-6.16" -- "linux-lts-6.12"
out=$(MOCK_INSTALLED="" run_gpu '1\ny\nn\n')
check "nagłówki obu jąder"                     'grep -q "linux-headers" "$MOCK_LOG" && grep -q "linux-lts-headers" "$MOCK_LOG"'
check "ostrzeżenie wskazuje jądro"             '[[ "$out" == *"linux-lts-6.12"* ]]'
check "MODULES nietknięte"                     'grep -q "^MODULES=()$" "$T/etc/mkinitcpio.conf"'
check "initramfs NIE przebudowany"             '! grep -q mkinitcpio "$MOCK_LOG"'

echo "== D: włączenie [multilib] bez częściowej aktualizacji"
setup "linux-6.16"
out=$(MOCK_INSTALLED="nvidia-open-dkms nvidia-utils" run_gpu '3\ny\n')
check "multilib odkomentowany"                 'grep -q "^\[multilib\]" "$T/etc/pacman.conf"'
check "brak gołego pacman -Sy"                 '! grep -qx "pacman -Sy" "$MOCK_LOG"'
check "lib32 w pełnym -Syu"                    'grep -q "pacman -Syu --needed lib32-nvidia-utils" "$MOCK_LOG"'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
