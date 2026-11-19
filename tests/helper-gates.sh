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
# sudo loguje i NIE wykonuje polecenia; `sudo pacman -S` zapisuje tylko stan atrapy bazy.
[[ "$name" == sudo && "${1:-}" == pacman && "${2:-}" == -S ]] && for a in "${@:3}"; do [[ "$a" == -* ]] || echo "$a" >> "$CALLS.installed"; done
case "$name" in
    # MOCK_LSPCI: all (domyślnie: NVIDIA+AMD+Intel) | nvidia | amd | intel —
    # osobne konfiguracje PCI (uwaga przeglądu Codexa D6: jeden łączny zestaw).
    lspci)
        [[ "${MOCK_LSPCI:-all}" == all || "$MOCK_LSPCI" == nvidia ]] && echo '01:00.0 VGA compatible controller: NVIDIA Corporation AD106M [GeForce RTX 4070 Max-Q / Mobile]'
        [[ "${MOCK_LSPCI:-all}" == all || "$MOCK_LSPCI" == amd ]] && echo '05:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Radeon 780M'
        [[ "${MOCK_LSPCI:-all}" == all || "$MOCK_LSPCI" == intel ]] && echo '00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics]'
        true ;;
    # pacman -Qi: zainstalowany, chyba że nazwa jest w MOCK_PKG_MISSING i nie
    # „zainstalowało” jej wcześniejsze (sudo) pacman -S tego biegu (uwaga
    # przeglądu Codexa D6: NVIDIA w parytecie była zawsze zainstalowana).
    pacman)
        if [[ "${1:-}" == -Qq && -z "${2:-}" ]]; then printf '%s\n' asusctl-git supergfxctl asusctltray-git
        elif [[ "${1:-}" == -Qi && " ${MOCK_PKG_MISSING:-} " == *" ${2:-} "* ]] && ! grep -qxF -- "${2:-}" "$CALLS.installed" 2>/dev/null; then exit 1
        fi ;;
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
    rm -rf "${E:?}" "${B:?}" "${M:?}" "${S:?}" "${CALLS:?}.installed"; : > "$CALLS"
    mkdir -p "$E/modprobe.d" "$B/loader/entries" "$M/$MOCK_KVER" "$S"
    printf '[options]\n#[multilib]\n#Include = /etc/pacman.d/mirrorlist\n' > "$E/pacman.conf"
    printf 'MODULES=()\nHOOKS=(base udev)\n' > "$E/mkinitcpio.conf"
    # BOOT=sdboot: bez grub.cfg (wykrycie systemd-boot po loader/entries).
    [[ "${BOOT:-grub}" == grub ]] && { mkdir -p "$B/grub"; echo "# TEST grub.cfg" > "$B/grub/grub.cfg"; }
    printf 'title TEST\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\n' > "$B/loader/entries/arch.conf"
    : > "$B/initramfs-linux.img"
    [[ -n "${NO_PKGBASE:-}" ]] || echo linux > "$M/$MOCK_KVER/pkgbase"
    : > "$M/$MOCK_KVER/nvidia.ko"; echo 7.2.16 > "$M/$MOCK_KVER/vboxdrv.ko"
    cpu "${CPU_VENDOR:-GenuineIntel}"
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
    norm="$(norm_out <<< "$out")"
    after="$(snap)"
    calls="$(<"$CALLS")"
}
# norm_out — komunikaty basha („<skrypt>: line N: …”) do porównania z bazą:
# znane katalogi robocze (kopia bazy, repo, $T, wrapper base-<nazwa>) →
# wspólne <dir>/, numer linii → <N> (brama przesuwa linie). Względna nazwa
# pliku ZOSTAJE (D6F L2, przegląd Codexa: dawne `s|^[^ ]*: line N: |<bash>: |`
# zrównywało komunikaty różnych plików, np. bootloader.sh i lib/pkg.sh).
BASE="$T/base"
norm_out() {
    sed -E -e "s|$BASE/|<dir>/|g" -e "s|$REPO/|<dir>/|g" -e "s|$T/base-|<dir>/|g" -e "s|$T/|<dir>/|g" \
        -e 's|^(<dir>/[^ :]+): line [0-9]+: |\1: line <N>: |'
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
    check "$label: Arch — brama otwarta (pomocnik działa dalej)" '[[ ( -n "$a_calls" || -n "$a_out" ) && "$a_out" != *"nothing was changed"* ]]'
    run "$script" endeavouros "$answers" "$@"
    check "$label: EndeavourOS (ID_LIKE=arch) = Arch (wyjście, kod, wywołania, atrapy)" \
        '[[ "$out" == "$a_out" && "$rc" == "$a_rc" && "$calls" == "$a_calls" && "$after" == "$a_after" ]]'
    if [[ -n "${HELPER_GATES_REV:-}" ]]; then
        local os base="$BASE/install/${script##*/install/}"
        # Wrapper z $T (wywołania biblioteki): ta sama treść z install/ z rewizji.
        if [[ "$script" == "$T"/* ]]; then
            base="$T/base-${script##*/}"
            sed "s|$REPO/install/|$BASE/install/|g" "$script" > "$base"
        fi
        for os in arch endeavouros; do
            run "$script" "$os" "$answers" "$@"
            local n_norm="$norm" n_rc="$rc" n_calls="$calls" n_after="$after"
            run "$base" "$os" "$answers" "$@"
            check "$label: $os = $HELPER_GATES_REV (wyjście, kod, wywołania, atrapy)" \
                '[[ "$norm" == "$n_norm" && "$rc" == "$n_rc" && "$calls" == "$n_calls" && "$after" == "$n_after" ]]'
        done
    fi
}
# Samotest normalizacji (D6F L2, odtworzenie L2-normalizacja.py odwrócone):
# różne pliki z tym samym komunikatem pozostają różne, ten sam plik z innym
# katalogiem i numerem linii — równy, zmiana treści komunikatu widoczna.
n1="$(norm_out <<< "$BASE/install/bootloader.sh: line 81: write failed")"
n2="$(norm_out <<< "$REPO/install/lib/pkg.sh: line 475: write failed")"
n3="$(norm_out <<< "$REPO/install/bootloader.sh: line 90: write failed")"
n4="$(norm_out <<< "$REPO/install/bootloader.sh: line 90: permission denied")"
check "normalizacja: różne pliki z tym samym komunikatem pozostają różne" '[[ "$n1" != "$n2" && "$n2" == "<dir>/install/lib/pkg.sh: line <N>: write failed" ]]'
check "normalizacja: ten sam plik, inny katalog i numer linii → równe" '[[ "$n1" == "$n3" && "$n1" == "<dir>/install/bootloader.sh: line <N>: write failed" ]]'
check "normalizacja: zmiana treści komunikatu widoczna" '[[ "$n3" != "$n4" ]]'
check "normalizacja: wrapper bazy (\$T/base-<nazwa>) = wrapper bieżący" '[[ "$(norm_out <<< "$T/base-w.sh: line 3: x")" == "$(norm_out <<< "$T/w.sh: line 5: x")" ]]'

if [[ -n "${HELPER_GATES_REV:-}" ]]; then
    mkdir -p "$BASE"
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
    for gpu in nvidia amd intel; do
        run "$GPU" "$os" '1\ny\ny\ny\n' MOCK_LSPCI=$gpu MOCK_PKG_MISSING="nvidia-open-dkms nvidia-dkms nvidia-open nvidia"
        gated "GPU $os, tylko $gpu (osobny zestaw PCI), NVIDIA niezainstalowana: brama zamknięta" "$head"
    done
done
run "$GPU" fedora 'y\n'
gated "GPU Fedora: Mesa, lib32 (i686) i NVIDIA z RPM Fusion" "mesa-vulkan-drivers.i686" "akmod-nvidia" "https://rpmfusion.org/Howto/NVIDIA"
check "GPU Fedora: bez archowych porad (pacman, mkinitcpio, multilib)" '[[ "$out" != *pacman* && "$out" != *mkinitcpio* && "$out" != *multilib* ]]'
# L3 (przegląd D8–D10): akmod-nvidia (bieżąca gałąź, 590+) nie obsługuje
# Maxwell/Pascal/Volta — porada według generacji jak w NixOS (R2); nazwy RPM
# Fusion: xorg-x11-drv-nvidia-580xx(-libs) ze specu pakietu, akmod-<kmod>.
# fed_branch <generacja> → „<akmod> <libs.i686>” z bloku tej generacji.
fed_branch() {
    awk -v g="$1" '
        index($0, g) && /:$/ { on = 1; next }
        on && /sudo dnf install akmod-nvidia/ { sub(/.*sudo dnf install /, ""); print; exit }' <<< "$out"
}
check "GPU Fedora: Turing+ → akmod-nvidia + xorg-x11-drv-nvidia-libs.i686" '[[ "$(fed_branch Turing)" == "akmod-nvidia xorg-x11-drv-nvidia-libs.i686" ]]'
check "GPU Fedora: Pascal/Maxwell/Volta → akmod-nvidia-580xx + -580xx-libs.i686" '[[ "$(fed_branch Pascal)" == "akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx-libs.i686" ]]'
check "GPU Fedora: Kepler → akmod-nvidia-470xx + -470xx-libs.i686" '[[ "$(fed_branch Kepler)" == "akmod-nvidia-470xx xorg-x11-drv-nvidia-470xx-libs.i686" ]]'
check "GPU Fedora: bez bezwarunkowego „install akmod-nvidia”" '[[ "$out" != *"then install akmod-nvidia"* ]]'
run "$GPU" nixos 'y\n'
gated "GPU NixOS: opcje hardware.graphics i hardware.nvidia" "hardware.graphics.enable = true;" "hardware.graphics.enable32Bit = true;" \
    'services.xserver.videoDrivers = [ "nvidia" ];' "hardware.nvidia.modesetting.enable = true;"
# D6F L1 (przegląd Codexa): open zależnie od generacji karty, gałąź sterownika,
# warunek unfree i przewodnik — nie bezwarunkowe open = true.
check "GPU NixOS: open = true tylko dla Turing i nowszych, open = false dla starszych" \
    '[[ "$out" == *"Turing"*"hardware.nvidia.open = true;"* && "$out" == *"hardware.nvidia.open = false;"* && "$(grep -c "hardware.nvidia.open = true;" <<< "$out")" == 1 ]] && ! grep -qE "^ *hardware\.nvidia\.open = true; hardware" <<< "$out"'
check "GPU NixOS: gałąź sterownika (hardware.nvidia.package, legacy dla starych kart)" \
    '[[ "$out" == *"hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;"* && "$out" == *"legacy_470"* ]]'
# D7F R2 (przegląd Codexa D7): stable = production (595.x w nixpkgs f6840765)
# nie obsługuje Pascal/Maxwell — gałąź musi wynikać z generacji karty.
# gen_branch <generacja> → „open=<…> package=<gałąź>” z bloku tej generacji.
gen_branch() {
    awk -v g="$1" '
        index($0, g) && /:$/ { on = 1; next }
        on && /hardware\.nvidia\.open = / { o = $0; sub(/.*hardware\.nvidia\.open = /, "", o); sub(/;.*/, "", o) }
        on && /nvidiaPackages\./ { p = $0; sub(/.*nvidiaPackages\./, "", p); sub(/;.*/, "", p); print "open=" o " package=" p; exit }' <<< "$out"
}
check "GPU NixOS: Turing+ → open = true, nvidiaPackages.stable (production)" '[[ "$(gen_branch Turing)" == "open=true package=stable" && "$out" == *"production"* ]]'
check "GPU NixOS: Pascal/Maxwell → open = false, nvidiaPackages.legacy_580" '[[ "$(gen_branch Pascal)" == "open=false package=legacy_580" ]]'
check "GPU NixOS: Kepler → open = false, nvidiaPackages.legacy_470" '[[ "$(gen_branch Kepler)" == "open=false package=legacy_470" ]]'
check "GPU NixOS: uwaga o zależności nazw od wersji nixpkgs (nvidia-x11/default.nix)" '[[ "$out" == *"depend on your nixpkgs version"* && "$out" == *"pkgs/os-specific/linux/nvidia-x11/default.nix"* ]]'
check "GPU NixOS: warunek unfree i przewodnik NixOS" \
    '[[ "$out" == *"nixpkgs.config.allowUnfree = true;"* && "$out" == *"allowUnfreePredicate"* && "$out" == *"https://wiki.nixos.org/wiki/NVIDIA"* ]]'
check "GPU NixOS: bez sudo w instrukcji (deklaratywnie)" '[[ "$out" != *sudo* ]]'
run "$GPU" ubuntu 'y\n'
check "GPU Ubuntu: komunikat pkg_detect o nieobsługiwanej dystrybucji" '[[ "$out" == *"Unsupported distribution (ID=ubuntu)"* ]]'
no_lib "$GPU"
parity "GPU NVIDIA zainstalowana, „zostaw”, lib32 tak" "$GPU" '3\ny\n'
parity "GPU NVIDIA zainstalowana, wybór open-dkms, tak, lib32 nie" "$GPU" '1\ny\nn\n'
NV_ALL="nvidia-open-dkms nvidia-dkms nvidia-open nvidia"
run "$GPU" arch '1\ny\nn\n' MOCK_PKG_MISSING="$NV_ALL"
check "GPU Arch, NVIDIA niezainstalowana: rzeczywista ścieżka nowej instalacji (pacman -S nvidia-open-dkms)" \
    '[[ "$out" != *"NVIDIA driver already installed"* ]] && grep -q "^sudo pacman -S .*nvidia-open-dkms" <<< "$calls"'
parity "GPU nowa instalacja open-dkms (NVIDIA niezainstalowana), tak, lib32 nie" "$GPU" '1\ny\nn\n' MOCK_PKG_MISSING="$NV_ALL"
for gpu in nvidia amd intel; do
    parity "GPU tylko $gpu (osobny zestaw PCI), tak, lib32 tak" "$GPU" 'y\ny\ny\ny\n' MOCK_LSPCI=$gpu MOCK_PKG_MISSING="$NV_ALL"
done
parity "GPU bez lspci" "$GPU" 'y\ny\ny\n' PATH="$NOLSPCI_PATH"

CPU="$REPO/install/cpudrivers-installation.sh"
KI="$REPO/install/kernel-install.sh"
BL="$REPO/install/bootloader.sh"

echo "== CPU: cpudrivers-installation.sh wprost"
for row in "${CLOSED[@]}"; do
    os="${row%%|*}"; head="${row#*|}"
    for CPU_VENDOR in GenuineIntel AuthenticAMD TESTVENDOR; do
        run "$CPU" "$os" 'y\ny\n'
        gated "CPU $os, $CPU_VENDOR, „y”: kod 2 przed pytaniem, bez pacmana i GRUB-a" "$head"
    done
    CPU_VENDOR=GenuineIntel
    run "$CPU" "$os" 'y\n' PLATFORM=arch
    gated "CPU $os z odziedziczonym PLATFORM=arch: brama zamknięta" "$head"
done
run "$CPU" fedora 'y\n'
# Uwaga przeglądu Codexa D6: podpakiet AMD Fedory to amd-ucode-firmware (z linux-firmware).
gated "CPU Fedora: microcode_ctl / amd-ucode-firmware zarządzane przez Fedorę" "microcode_ctl" "amd-ucode-firmware from linux-firmware" "sudo dnf upgrade"
run "$CPU" nixos 'y\n'
gated "CPU NixOS: hardware.cpu.{intel,amd}.updateMicrocode" "hardware.cpu.intel.updateMicrocode = true;" "hardware.cpu.amd.updateMicrocode = true;"
check "CPU NixOS/Fedora: bez porad initrd systemd-boot" '[[ "$out" != *initrd* ]]'
no_lib "$CPU"
for CPU_VENDOR in GenuineIntel AuthenticAMD TESTVENDOR; do
    parity "CPU $CPU_VENDOR, „y”, GRUB" "$CPU" 'y\n'
    parity "CPU $CPU_VENDOR, „n”" "$CPU" 'n\n'
done
CPU_VENDOR=AuthenticAMD BOOT=sdboot parity "CPU AMD, „y”, systemd-boot" "$CPU" 'y\n'
unset CPU_VENDOR

echo "== Jądro: kernel-install.sh wprost"
for row in "${CLOSED[@]}"; do
    os="${row%%|*}"; head="${row#*|}"
    for ans in '1\ny\n' '2\ny\n' '3\ny\n' 'y\ny\n'; do
        run "$KI" "$os" "$ans"
        gated "jądro $os, odpowiedzi ${ans//\\n/ }: kod 2, bez pacmana i GRUB-a" "$head"
    done
done
run "$KI" fedora '2\ny\n'
gated "jądro Fedora: własne jądro Fedory, bez zen/lts" "package kernel" "sudo dnf upgrade"
run "$KI" nixos '2\ny\n'
gated "jądro NixOS: boot.kernelPackages" "boot.kernelPackages = pkgs.linuxPackages_zen;" "pkgs.linuxPackages_latest"
no_lib "$KI"
for ans in '1\ny\n' '2\ny\n' '3\ny\n' '2\nn\n' '\n'; do
    parity "jądro, odpowiedzi ${ans//\\n/ }" "$KI" "$ans"
done
BOOT=sdboot parity "jądro zen, systemd-boot" "$KI" '2\ny\n'

echo "== Bootloader: install/bootloader.sh — start, source, regenerate_bootloader"
# Wywołania biblioteki: start wprost, samo source (wołający żyje dalej) i
# source + regenerate_bootloader przy rozpoznanym GRUB-ie albo systemd-boot.
printf 'source "%s"; echo "after-source rc=$?"\n' "$BL" > "$T/bl-source.sh"
printf 'source "%s"; regenerate_bootloader "TEST ctx"; echo "regen rc=$?"\n' "$BL" > "$T/bl-regen.sh"
for row in "${CLOSED[@]}"; do
    os="${row%%|*}"; head="${row#*|}"
    run "$BL" "$os" 'y\n'
    check "bootloader.sh $os wprost: kod 0, bez wyjścia, zero wywołań, /boot nietknięty" \
        '[[ "$rc" == 0 && -z "$out" && -z "$calls" && "$after" == "$before" ]]'
    run "$T/bl-source.sh" "$os" 'y\n'
    check "bootloader.sh $os po source: wołający żyje dalej, zero wywołań" \
        '[[ "$out" == "after-source rc=0"$'"'"'\n'"'"' && -z "$calls" && "$after" == "$before" ]]'
    for BOOT in grub sdboot; do
        run "$T/bl-regen.sh" "$os" 'y\n'
        rc="${out##*regen rc=}"; rc="${rc%%$'\n'*}"
        gated "regenerate_bootloader $os, $BOOT: kod 2, bez grub-mkconfig/bootctl, /boot nietknięty" "$head" "Boot configuration (TEST ctx)"
        check "regenerate_bootloader $os, $BOOT: bez archowych porad initrd/kernel-install" \
            '[[ "$out" != *initrd* && "$out" != *"grub-mkconfig -o"* && "$out" != *"kernel-install add"* ]]'
    done
    unset BOOT
done
run "$T/bl-regen.sh" fedora ''
check "regenerate_bootloader Fedora: kernel-install/BLS i grub2-mkconfig jako porada" '[[ "$out" == *"kernel-install, BLS"* && "$out" == *"sudo grub2-mkconfig -o /boot/grub2/grub.cfg"* ]]'
run "$T/bl-regen.sh" nixos ''
check "regenerate_bootloader NixOS: nixos-rebuild boot, /boot nie ręcznie, bez sudo w tekście (L6)" '[[ "$out" == *"nixos-rebuild boot"* && "$out" == *"Do not edit /boot by hand."* && "$out" != *sudo* ]]'
mkdir -p "$T/bl-nolib"; cp "$BL" "$T/bl-nolib/"
printf 'source "%s"; echo "after-source rc=$?"; regenerate_bootloader "TEST ctx"; echo "regen rc=$?"\n' "$T/bl-nolib/bootloader.sh" > "$T/bl-nolib-call.sh"
run "$T/bl-nolib-call.sh" arch ''
check "bootloader.sh bez install/lib/pkg.sh: source bez błędu, regenerate → ✗, kod 1, zero wywołań" \
    '[[ "$out" == *"after-source rc=0"* && "$out" == *"pkg.sh is not loaded"* && "$out" == *"regen rc=1"* && -z "$calls" && "$after" == "$before" ]]'
for BOOT in grub sdboot; do
    parity "regenerate_bootloader, $BOOT" "$T/bl-regen.sh" ''
done
unset BOOT

ASUS="$REPO/install/asus-installation.sh"

echo "== ASUS: asus-installation.sh wprost (porzucone pakiety AUR na „dysku”)"
for row in "${CLOSED[@]}"; do
    os="${row%%|*}"; head="${row#*|}"
    for ans in 'y\ny\ny\n' 'n\n' ''; do
        run "$ASUS" "$os" "$ans"
        gated "ASUS $os, odpowiedzi ${ans//\\n/ }: kod 2, bez pytania o usuwanie, zero pacman/sudo/systemctl" "$head"
    done
    run "$ASUS" "$os" 'y\n' PLATFORM=arch
    gated "ASUS $os z odziedziczonym PLATFORM=arch: brama zamknięta" "$head"
done
run "$ASUS" fedora 'y\n'
gated "ASUS Fedora: pkg_hint asusctl (przewodnik asus-linux dla Fedory)" "asusctl + rog-control-center: Not packaged for Fedora — install manually: https://asus-linux.org/guides/fedora-guide/"
check "ASUS Fedora: bez archowych porad (pacman, AUR)" '[[ "$out" != *pacman* && "$out" != *AUR* ]]'
run "$ASUS" nixos 'y\n'
gated "ASUS NixOS: services.asusd.enable" "services.asusd.enable = true;" "Configure the NixOS option services.asusd.enable"
check "ASUS NixOS: bez sudo w instrukcji" '[[ "$out" != *sudo* ]]'
no_lib "$ASUS"
parity "ASUS porzucone pakiety, „y”" "$ASUS" 'y\n'
parity "ASUS porzucone pakiety, „n”" "$ASUS" 'n\n'

VB="$REPO/install/virtualbox-installation.sh"

echo "== VirtualBox: virtualbox-installation.sh wprost"
for row in "${CLOSED[@]}"; do
    os="${row%%|*}"; head="${row#*|}"
    for ans in 'y\ny\n' ''; do
        run "$VB" "$os" "$ans"
        gated "VirtualBox $os (jądro z pkgbase), odpowiedzi ${ans//\\n/ }: kod 2, zero pacman/modprobe/usermod" "$head"
        NO_PKGBASE=1 run "$VB" "$os" "$ans"
        gated "VirtualBox $os (bez pkgbase), odpowiedzi ${ans//\\n/ }: kod 2, bez instalacji mimo braku jądra Archa" "$head"
    done
    run "$VB" "$os" 'y\n' PLATFORM=arch
    gated "VirtualBox $os z odziedziczonym PLATFORM=arch: brama zamknięta" "$head"
done
run "$VB" fedora 'y\n'
gated "VirtualBox Fedora: Oracle/RPM Fusion, vboxusers jako porada" "https://www.virtualbox.org/wiki/Linux_Downloads" "akmod-VirtualBox" "sudo usermod -aG vboxusers tester"
check "VirtualBox Fedora: bez archowych nagłówków (pacman, -headers)" '[[ "$out" != *pacman* && "$out" != *-headers* ]]'
run "$VB" nixos 'y\n'
gated "VirtualBox NixOS: virtualisation.virtualbox.host + vboxusers" "virtualisation.virtualbox.host.enable = true;" 'users.extraGroups.vboxusers.members = [ "tester" ];'
check "VirtualBox NixOS: bez sudo w instrukcji" '[[ "$out" != *sudo* ]]'
run "$VB" fedora 'y\n' -u USER
check "VirtualBox bez \$USER: <your-user>, bez wywołania id" '[[ "$out" == *"vboxusers <your-user>"* && -z "$calls" ]]'
no_lib "$VB"
parity "VirtualBox, „y” na grupę" "$VB" 'y\n'
parity "VirtualBox, odmowa grupy" "$VB" 'n\n'
NO_PKGBASE=1 parity "VirtualBox bez pkgbase" "$VB" 'y\n'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
