#!/usr/bin/env bash
# =============================================
#   archenemy - tests/helper-gates.sh
#   Bramy platformy pomocników systemowych install/*.sh (D6): uruchomione
#   WPROST (bez install.sh) poza Archem i jego pochodnymi kończą się kodem 2
#   z instrukcją dla tej platformy — bez pytania (stdin nieprzeczytany), bez
#   jakiegokolwiek polecenia z PATH i bez zmiany atrap /etc, /boot,
#   katalogu modułów i /sys/module.
#   Platforma = jawny os-release (ARCHENEMY_OS_RELEASE przy ARCHENEMY_TEST=1):
#   Arch, pochodna (ID_LIKE=arch), Fedora, Fedora Atomic, NixOS, Ubuntu, brak
#   pliku. Odziedziczone PLATFORM=arch nie otwiera bramy.
#   SZPIEDZY w PATH: sudo, pacman, yay, dnf, rpm, systemctl, mkinitcpio,
#   grub-mkconfig, grub2-mkconfig, bootctl, kernel-install, dkms, modprobe,
#   usermod, modinfo, lspci, supergfxctl, getent, id, uname — każdy zapisuje
#   wywołanie i udaje, że narzędzia Archa są (lspci widzi NVIDIA+AMD+Intel,
#   pacman ma sterownik NVIDIA i porzucone pakiety ASUS-a); sudo niczego nie
#   wykonuje. Na Archu i pochodnej brama jest otwarta: pochodna daje DOKŁADNIE
#   to samo co Arch (wyjście, kod, wywołania, migawka).
#   Parytet z bazą (opcjonalnie): HELPER_GATES_REV=<rewizja> uruchamia
#   scenariusze Archa i pochodnej także na pomocnikach z tej rewizji
#   (git archive) i porównuje wyjście, kod, wywołania i migawkę.
#   Szczegółowe zachowanie na Archu: tests/gpudrivers.sh, bootloader.sh,
#   asus-installation.sh, virtualbox.sh (jawny os-release Archa).
#   Uruchom: bash tests/helper-gates.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval (zmienne żyją w eval); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── szpiedzy ────────────────────────────────────────────────────────────────
SPIES=(sudo pacman yay dnf rpm systemctl mkinitcpio grub-mkconfig grub2-mkconfig bootctl
       kernel-install dkms modprobe usermod modinfo lspci supergfxctl getent id uname)
mkdir -p "$T/bin" "$T/bin-nolspci"
for c in "${SPIES[@]}"; do
    cat > "$T/bin/$c" <<'EOF'
#!/usr/bin/env bash
name="${0##*/}"
echo "$name $*" >> "$CALLS"
case "$name" in
    lspci) printf '%s\n' \
        '01:00.0 VGA compatible controller: NVIDIA Corporation AD106M [GeForce RTX 4070 Max-Q / Mobile]' \
        '05:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Radeon 780M' \
        '00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics]' ;;
    pacman) [[ "${1:-}" == -Qq && -z "${2:-}" ]] && printf '%s\n' asusctl-git supergfxctl asusctltray-git ;;
    id) [[ "${1:-}" == -un ]] && echo tester || echo "tester wheel" ;;
    uname) echo "${MOCK_KVER:-6.16.1-arch1-1}" ;;
    supergfxctl) echo Hybrid ;;
esac
exit 0
EOF
    chmod +x "$T/bin/$c"
    [[ "$c" == lspci ]] || ln -s "$T/bin/$c" "$T/bin-nolspci/$c"
done
# PATH „bez lspci”: szpiedzy bez lspci + same potrzebne narzędzia (prawdziwe
# lspci z /usr/bin hosta nie może się wkraść).
for c in bash env cat dirname readlink grep awk tr basename sed head tail sort cut wc mkdir rm cp tee; do
    p="$(command -v "$c")" && ln -s "$p" "$T/bin-nolspci/$c"
done
NOLSPCI_PATH="$T/bin-nolspci"
BASE_PATH="$PATH"
export PATH="$T/bin:$BASE_PATH" CALLS="$T/calls" USER=tester MOCK_KVER=6.16.1-arch1-1
for c in "${SPIES[@]}"; do
    if [[ "$(command -v "$c")" != "$T/bin/$c" ]]; then
        echo "✗ $c nie jest szpiegiem ($(command -v "$c")) — nie uruchamiam (dotknąłby systemu)"
        exit 1
    fi
done

# ─── os-release i atrapy systemu ─────────────────────────────────────────────
OS="$T/os"; mkdir -p "$OS"
printf 'NAME="Arch Linux"\nID=arch\n'                        > "$OS/arch"
printf 'NAME="EndeavourOS"\nID=endeavouros\nID_LIKE=arch\n'  > "$OS/endeavouros"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=44\n'     > "$OS/fedora"
printf 'ID=fedora\nVERSION_ID=44\nVARIANT_ID=silverblue\n'   > "$OS/silverblue"
printf 'NAME=NixOS\nID=nixos\nVERSION_ID=26.05\n'            > "$OS/nixos"
printf 'NAME=Ubuntu\nID=ubuntu\nID_LIKE=debian\n'            > "$OS/ubuntu"
# „none”: ścieżka nieistniejąca — os-release nieczytelny.

E="$T/etc"; B="$T/boot"; M="$T/modules"; S="$T/sys"
reset_system() {
    rm -rf "${E:?}" "${B:?}" "${M:?}" "${S:?}"; : > "$CALLS"
    mkdir -p "$E/modprobe.d" "$B/grub" "$B/loader/entries" "$M/$MOCK_KVER" "$S"
    printf '[options]\n#[multilib]\n#Include = /etc/pacman.d/mirrorlist\n' > "$E/pacman.conf"
    printf 'MODULES=()\nHOOKS=(base udev)\n' > "$E/mkinitcpio.conf"
    echo "# TEST grub.cfg" > "$B/grub/grub.cfg"
    printf 'title TEST\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\n' > "$B/loader/entries/arch.conf"
    : > "$B/initramfs-linux.img"
    echo linux > "$M/$MOCK_KVER/pkgbase"; : > "$M/$MOCK_KVER/nvidia.ko"; echo 7.2.16 > "$M/$MOCK_KVER/vboxdrv.ko"
    cpu GenuineIntel
}
cpu() { printf 'processor\t: 0\nvendor_id\t: %s\n' "$1" > "$T/cpuinfo"; }
snap() { (cd "$T" && find etc boot modules sys -printf '%p %m %s\n' | sort; find etc boot modules sys -type f -exec md5sum {} + | sort); }
export ARCHENEMY_TEST=1 ARCHENEMY_ETC_DIR="$E" ARCHENEMY_BOOT_DIR="$B" ARCHENEMY_MODULES_DIR="$M" \
    ARCHENEMY_SYSMODULE_DIR="$S" ARCHENEMY_CPUINFO="$T/cpuinfo" ARCHENEMY_OSTREE_MARKER="$T/no-ostree"

# run <skrypt> <os> <odpowiedzi> [zmienne env…] — pomocnik wprost (bash <skrypt>),
# stdin ze zwykłego pliku: po wyjściu pomocnika `cat` wypisuje to, czego nie
# przeczytał (read w bashu cofa się w pliku do końca przeczytanej linii).
# Wynik: $out (bez reszty), $rc, $rest, $calls, $before/$after (migawki).
run() {
    local script="$1" os="$2" answers="$3"; shift 3
    reset_system
    printf '%b' "$answers" > "$T/stdin"
    before="$(snap)"
    local all
    all="$( { env "$@" ARCHENEMY_OS_RELEASE="$OS/$os" bash "$script"; echo "@@RC=$?@@"; cat; } < "$T/stdin" 2>&1 )"
    out="${all%%@@RC=*}"
    rc="${all#*@@RC=}"; rc="${rc%%@@*}"
    rest="${all#*@@RC=*@@}"; rest="${rest#$'\n'}"
    # Komunikaty basha („<skrypt>: line N: …”) bez ścieżki i numeru linii —
    # brama przesuwa linie, a parytet porównuje zachowanie, nie numerację.
    norm="$(sed -E 's|^[^ ]*: line [0-9]+: |<bash>: |' <<< "$out")"
    after="$(snap)"
    calls="$(<"$CALLS")"
}
# gated <etykieta> <oczekiwany tekst…> — po `run`: kod 2, zero wywołań, migawka
# bez zmian, stdin nietknięty, „nothing was changed”, bez ✓ i każdy tekst w $out.
gated() {
    local label="$1" why="" t; shift
    [[ "$rc" == 2 ]] || why+=" kod=$rc"
    [[ -z "$calls" ]] || why+=" wywołania: ${calls//$'\n'/; }"
    [[ "$after" == "$before" ]] || why+=" zmieniona atrapa systemu"
    [[ "$rest" == "$(<"$T/stdin")" ]] || why+=" przeczytane stdin (pytanie)"
    [[ "$out" == *"nothing was changed"* ]] || why+=" brak „nothing was changed”"
    [[ "$out" != *"✓"* ]] || why+=" ✓ w wyjściu"
    for t in "$@"; do [[ "$out" == *"$t"* ]] || why+=" brak tekstu „$t”"; done
    if [[ -z "$why" ]]; then ok "$label"; else fail "$label —$why"; fi
}
# Teksty platform: nagłówek z pkg_gate + instrukcja pomocnika.
FED="nothing was changed on Fedora"; NIX="nothing was changed on NixOS"
UNS="not supported by archenemy"

# Platformy z zamkniętą bramą: <os> <oczekiwany nagłówek>.
CLOSED=("fedora|$FED" "nixos|$NIX" "ubuntu|$UNS" "silverblue|$UNS" "none|$UNS")

# parity <etykieta> <skrypt> <odpowiedzi> [env…] — Arch i pochodna: brama otwarta
# (pomocnik coś wywołał), a pochodna = Arch co do bajtu.
parity() {
    local label="$1" script="$2" answers="$3"; shift 3
    local a_out a_rc a_calls a_after
    run "$script" arch "$answers" "$@"
    a_out="$out"; a_rc="$rc"; a_calls="$calls"; a_after="$after"
    check "$label: Arch — brama otwarta (pomocnik działa dalej)" '[[ -n "$a_calls" && "$a_out" != *"nothing was changed"* ]]'
    run "$script" endeavouros "$answers" "$@"
    check "$label: EndeavourOS (ID_LIKE=arch) = Arch (wyjście, kod, wywołania, atrapy)" \
        '[[ "$out" == "$a_out" && "$rc" == "$a_rc" && "$calls" == "$a_calls" && "$after" == "$a_after" ]]'
    if [[ -n "${HELPER_GATES_REV:-}" ]]; then
        local os base="$BASE/install/${script##*/install/}"
        for os in arch endeavouros; do
            run "$script" "$os" "$answers" "$@"
            local n_norm="$norm" n_rc="$rc" n_calls="$calls" n_after="$after"
            run "$base" "$os" "$answers" "$@"
            check "$label: $os = $HELPER_GATES_REV (wyjście, kod, wywołania, atrapy)" \
                '[[ "$norm" == "$n_norm" && "$rc" == "$n_rc" && "$calls" == "$n_calls" && "$after" == "$n_after" ]]'
        done
    fi
}
if [[ -n "${HELPER_GATES_REV:-}" ]]; then
    BASE="$T/base"; mkdir -p "$BASE"
    if ! git -C "$REPO" archive "$HELPER_GATES_REV" install | tar -x -C "$BASE"; then
        echo "✗ nie da się wypakować install/ z $HELPER_GATES_REV"; exit 1
    fi
    echo "  (parytet Archa z pomocnikami z rewizji $HELPER_GATES_REV)"
fi

# no_lib <skrypt> — kopia pomocnika bez install/lib/pkg.sh obok: kod 1, zero wywołań.
no_lib() {
    mkdir -p "$T/nolib"; cp "$1" "$T/nolib/"
    run "$T/nolib/${1##*/}" fedora 'y\ny\ny\n'
    check "${1##*/} bez install/lib/pkg.sh: ✗, kod 1, zero wywołań, stdin nietknięty" \
        '[[ "$rc" == 1 && -z "$calls" && "$after" == "$before" && "$rest" == "$(<"$T/stdin")" && "$out" == *"Cannot load install/lib/pkg.sh"* ]]'
}

GPU="$REPO/install/gpudrivers-installation.sh"

echo "== GPU: gpudrivers-installation.sh wprost"
for row in "${CLOSED[@]}"; do
    os="${row%%|*}"; head="${row#*|}"
    for ans in 'y\ny\ny\ny\ny\ny\n' '1\ny\ny\n' '2\ny\nY\n' '3\n'; do
        run "$GPU" "$os" "$ans"
        gated "GPU $os, odpowiedzi ${ans//\\n/ }: kod 2, nic nie wywołane i nie zmienione" "$head"
    done
    run "$GPU" "$os" 'y\ny\ny\n' PLATFORM=arch
    gated "GPU $os z odziedziczonym PLATFORM=arch: brama nadal zamknięta" "$head"
    run "$GPU" "$os" 'y\ny\ny\n' PATH="$NOLSPCI_PATH"
    gated "GPU $os bez lspci: bez instalacji pciutils" "$head"
done
run "$GPU" fedora 'y\n'
gated "GPU Fedora: Mesa, lib32 (i686) i NVIDIA z RPM Fusion" "mesa-vulkan-drivers.i686" "akmod-nvidia" "https://rpmfusion.org/Howto/NVIDIA"
check "GPU Fedora: bez archowych porad (pacman, mkinitcpio, multilib)" '[[ "$out" != *pacman* && "$out" != *mkinitcpio* && "$out" != *multilib* ]]'
run "$GPU" nixos 'y\n'
gated "GPU NixOS: opcje hardware.graphics i hardware.nvidia" "hardware.graphics.enable = true;" "hardware.graphics.enable32Bit = true;" \
    'services.xserver.videoDrivers = [ "nvidia" ];' "hardware.nvidia.open = true;" "hardware.nvidia.modesetting.enable = true;"
check "GPU NixOS: bez sudo w instrukcji (deklaratywnie)" '[[ "$out" != *sudo* ]]'
run "$GPU" ubuntu 'y\n'
check "GPU Ubuntu: komunikat pkg_detect o nieobsługiwanej dystrybucji" '[[ "$out" == *"Unsupported distribution (ID=ubuntu)"* ]]'
no_lib "$GPU"
parity "GPU NVIDIA zainstalowana, „zostaw”, lib32 tak" "$GPU" '3\ny\n'
parity "GPU nowa instalacja open-dkms, tak, lib32 nie" "$GPU" '1\ny\nn\n'
parity "GPU bez lspci" "$GPU" 'y\ny\ny\n' PATH="$NOLSPCI_PATH"

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
