#!/usr/bin/env bash
# =============================================
#   archenemy - tests/install-platforms.sh
#   Kroki [6], [6.5] i [10] install.sh na każdej platformie (D6): Arch,
#   EndeavourOS (ID_LIKE=arch), Arch z --skip-packages, Fedora, Fedora
#   z --skip-packages i NixOS. Wycinki kroków są wycinane z install/install.sh
#   sedem po nagłówkach (jak w tests/install-summary.sh) i uruchamiane
#   z PRAWDZIWYM blokiem wykrycia platformy instalatora (pkg_route, PLATFORM,
#   manual_step, pułapka sudo -k) na jawnym os-release.
#   Pilnuje:
#     - pomocniki systemowe (ASUS, mikrokod, GPU, jądro, Bluetooth, VirtualBox
#       — atrapy-szpiedzy w atrapie repo) nie startują na Fedorze, NixOS ani
#       na Archu z --skip-packages, a [6.5] nie czyta nawet odpowiedzi;
#     - Fedora/NixOS: zero sudo (poza `sudo -k` z pułapki na Fedorze bez
#       flagi), zero pacman/dnf/ufw/systemctl enable — także przy aktywnej
#       UFW; brak fałszywego DONE w podsumowaniu;
#     - Arch: kody 0/1/2 pomocników → właściwy wpis DONE/SKIPPED, a pochodna
#       daje dokładnie to samo co Arch.
#   ATRAPY w PATH: sudo, pacman, yay, dnf, rpm, systemctl, ufw, modprobe,
#   usermod, mkinitcpio, grub-mkconfig — każda zapisuje wywołanie.
#   Bez roota, bez sieci.
#   Uruchom: bash tests/install-platforms.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval (zmienne żyją w eval); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$REPO/install/install.sh"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# cut_step <wzorzec początku> <wzorzec końca> <plik> — wycinek [początek, koniec)
cut_step() {
    local s e
    s=$(grep -n -m1 -- "$1" "$INST" | cut -d: -f1)
    e=$(grep -n -m1 -- "$2" "$INST" | cut -d: -f1)
    [[ -n "$s" && -n "$e" && "$e" -gt "$s" ]] || return 1
    sed -n "${s},$((e-1))p" "$INST" > "$3"
}

echo "== wycinki"
cut_step '^# ─── PLATFORMA' '^# ─── 1\. WELCOME' "$T/platform.sh"
cut_step '^# ─── 6\. DEVICE DETECTION' '^# ─── 6\.5 DRIVERS' "$T/step6.sh"
cut_step '^# ─── 6\.5 DRIVERS' '^# ─── 7\. BACKUP' "$T/step65.sh"
cut_step '^# ─── 10\. UFW' '^# ─── 11\. DONE' "$T/step10.sh"
for f in platform step6 step65 step10; do
    check "wycinek $f znaleziony, składnia poprawna" '[[ -s "$T/$f.sh" ]] && bash -n "$T/$f.sh"'
done
check "blok platformy wybiera ścieżkę przez pkg_route" 'grep -q "^if pkg_route; then" "$T/platform.sh"'

# ─── atrapy ──────────────────────────────────────────────────────────────────
mkdir -p "$T/bin"
for c in sudo pacman yay dnf rpm systemctl ufw modprobe usermod mkinitcpio grub-mkconfig; do
    cat > "$T/bin/$c" <<'EOF'
#!/usr/bin/env bash
name="${0##*/}"
echo "$name $*" >> "$CALLS"
case "$name" in
    sudo) [[ "${1:-}" == -k ]] && exit 0; exec "$@" ;;
    # systemctl [--user] is-enabled|is-active <jednostka> — prawda dla jednostek
    # z MOCK_ENABLED / MOCK_ACTIVE; zapis (enable, start…) zawsze „udany”.
    systemctl)
        [[ "${1:-}" == --user ]] && shift
        [[ "${1:-}" == --quiet ]] && shift
        case "${1:-}" in
            is-enabled) shift; [[ "${1:-}" == --quiet ]] && shift; [[ " ${MOCK_ENABLED:-} " == *" ${1:-} "* ]]; exit ;;
            is-active)  shift; [[ "${1:-}" == --quiet ]] && shift; [[ " ${MOCK_ACTIVE:-} " == *" ${1:-} "* ]]; exit ;;
        esac ;;
    ufw) [[ "${1:-}" == status && -n "${MOCK_UFW_ACTIVE:-}" ]] && printf 'Status: active\nDefault: deny (incoming), allow (outgoing)\n' ;;
esac
exit 0
EOF
    chmod +x "$T/bin/$c"
done
export PATH="$T/bin:$PATH" CALLS="$T/calls"

# Atrapa repo: biblioteka i mapa prawdziwe, pomocniki-szpiedzy (kod z
# MOCK_<NAZWA>_RC), profile-get.sh wypisuje MOCK_PROFILE.
A="$T/archenemy"
mkdir -p "$A/install/lib" "$A/packages" "$A/scripts/waybar" "$A/data"
cp "$REPO/install/lib/pkg.sh" "$A/install/lib/"
cp "$REPO/packages/platform-map.tsv" "$A/packages/"
HELPERS=(asus-installation cpudrivers-installation gpudrivers-installation kernel-install bluetooth-installation virtualbox-installation)
for n in "${HELPERS[@]}"; do
    v="MOCK_$(tr 'a-z-' 'A-Z_' <<< "${n%%-*}")_RC"
    printf '#!/usr/bin/env bash\necho "RUN %s" >> "$CALLS"\nexit "${%s:-0}"\n' "$n" "$v" > "$A/install/$n.sh"
done
printf '#!/usr/bin/env bash\necho "${MOCK_PROFILE:-balanced}"\n' > "$A/scripts/waybar/profile-get.sh"
chmod +x "$A/install/"*.sh "$A/scripts/waybar/profile-get.sh"

OS="$T/os"; mkdir -p "$OS"
printf 'NAME="Arch Linux"\nID=arch\n'                       > "$OS/arch"
printf 'NAME="EndeavourOS"\nID=endeavouros\nID_LIKE=arch\n' > "$OS/endeavouros"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=44\n'    > "$OS/fedora"
printf 'NAME=NixOS\nID=nixos\nVERSION_ID=26.05\n'           > "$OS/nixos"
# Działające sieć i audio (D7F R1: pulse + backend pipewire/wireplumber enabled i active).
AUDIO_UP="NetworkManager pipewire-pulse.socket pipewire.socket wireplumber.service"
# Platformy: <nazwa>|<os-release>|<SKIP_PACKAGES>
P_ARCH="arch|arch|0"; P_EOS="endeavouros|endeavouros|0"; P_ASKIP="arch+skip|arch|1"
P_FED="fedora|fedora|0"; P_FSKIP="fedora+skip|fedora|1"; P_NIX="nixos|nixos|0"
NONARCH=("$P_FED" "$P_FSKIP" "$P_NIX")

# step <platforma> <wycinek> <stdin> — blok platformy instalatora + wycinek
# w świeżym bashu; wynik: $out, $rest (nieprzeczytane stdin), $calls,
# $done/$skipped (podsumowanie, po wpisie w wierszu).
step() {
    local plat os skip
    IFS='|' read -r plat os skip <<< "$1"
    : > "$CALLS"; rm -f "$A/data/hardware.dat" "$A/data/bluetooth-enabled.dat"
    printf '%b' "$3" > "$T/stdin"
    local all
    all="$( { ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$OS/$os" ARCHENEMY_OSTREE_MARKER="$T/no-ostree" \
        ARCHENEMY_DIR="$A" DATA_DIR="$A/data" SKIP_PACKAGES="$skip" \
        GREEN='' NC='' YELLOW='' RED='' CYAN='' BLUE='' \
        bash -c 'set -uo pipefail; declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=()
                 source "$1"; source "$2"
                 printf "DONE=%s\n" "${SUMMARY_DONE[@]}" > "$3"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}" >> "$3"' \
        _ "$T/platform.sh" "$T/$2.sh" "$T/summary"
        echo "@@END@@"; cat; } < "$T/stdin" 2>&1 )"
    out="${all%%@@END@@*}"
    rest="${all#*@@END@@}"; rest="${rest#$'\n'}"
    calls="$(<"$CALLS")"
    done_="$(grep '^DONE=.' "$T/summary")"
    skipped="$(grep '^SKIPPED=.' "$T/summary")"
}
ran() { grep -qx "RUN $1" "$CALLS"; }
no_helpers() { ! grep -q '^RUN ' "$CALLS"; }
# Na Fedorze/NixOS: jedyne dozwolone sudo to `sudo -k` z pułapki (Fedora bez flagi).
no_mutation() {
    ! grep -vx 'sudo -k' "$CALLS" | grep -qE '^(sudo|pacman|yay|dnf|ufw|modprobe|usermod|mkinitcpio|grub-mkconfig) ' \
        && ! grep -qE '^systemctl (--user )?(enable|disable|start|restart|stop|mask)' "$CALLS"
}
sudo_k_only() {   # sudo_k_only <platforma> — NixOS i Fedora z flagą: zero sudo, nawet -k
    case "$1" in
        fedora\|*\|0) ! grep -vx 'sudo -k' "$CALLS" | grep -q '^sudo ' ;;
        *) ! grep -q '^sudo ' "$CALLS" ;;
    esac
}

# ─── [6] urządzenie: ASUS, PPD, profil ───────────────────────────────────────
echo "== [6] ASUS i profil zasilania"
for p in "$P_FED" "$P_FSKIP" "$P_NIX" "$P_ASKIP"; do
    name="${p%%|*}"
    step "$p" step6 '1\n'
    check "[6] $name, ASUS: pomocnik niewywołany, krok ręczny w podsumowaniu" \
        'no_helpers && grep -q "^SKIPPED=ASUS tools (asusctl) — not done on" <<< "$skipped" && ! grep -q "^DONE=ASUS" <<< "$done_"'
    check "[6] $name, ASUS: hardware.dat = asus, profil w DONE (profile-get odpowiada)" \
        '[[ "$(<"$A/data/hardware.dat")" == asus ]] && grep -q "^DONE=Hardware profile: asus (active profile: balanced)" <<< "$done_"'
done
for p in "${NONARCH[@]}"; do
    name="${p%%|*}"
    step "$p" step6 '1\n'
    check "[6] $name, ASUS: zero sudo/pacman/dnf/systemctl enable" 'no_mutation && sudo_k_only "$p"'
done
step "$P_FED" step6 '1\n'
check "[6] Fedora, ASUS: pkg_hint (przewodnik asus-linux), PPD przez systemctl jako porada" \
    '[[ "$out" == *"asus-linux.org/guides/fedora-guide"* && "$out" == *"sudo systemctl enable --now power-profiles-daemon"* ]]'
step "$P_NIX" step6 '1\n'
check "[6] NixOS, ASUS: services.asusd.enable i services.power-profiles-daemon.enable" \
    '[[ "$out" == *"services.asusd.enable"* && "$out" == *"services.power-profiles-daemon.enable = true;"* ]]'
step "$P_ASKIP" step6 '1\n'
check "[6] Arch+skip, ASUS: ponowne uruchomienie pomocnika jako instrukcja, bez pacmana" \
    '[[ "$out" == *"bash ~/archenemy/install/asus-installation.sh"* ]] && ! grep -q "^pacman" "$CALLS"'
for rc in 0 1 2; do
    MOCK_ASUS_RC=$rc step "$P_ARCH" step6 '1\n'
    case $rc in
        0) want='^DONE=ASUS: asusctl \+ rog-control-center from the Arch repo, asusd running' ;;
        1) want='^SKIPPED=ASUS: installation failed' ;;
        2) want='^SKIPPED=ASUS: packages installed, asusd not running yet: reboot' ;;
    esac
    check "[6] Arch, ASUS kod $rc → właściwy wpis podsumowania, pomocnik raz" \
        'ran asus-installation && [[ $(grep -c "^RUN " "$CALLS") -eq 1 ]] && grep -qE "$want" <<< "$done_"$'"'"'\n'"'"'"$skipped"'
    [[ $rc -eq 0 ]] || check "[6] Arch, ASUS kod $rc: bez DONE dla ASUS-a" '! grep -q "^DONE=ASUS" <<< "$done_"'
done
for p in "$P_ARCH" "$P_FED" "$P_NIX"; do
    name="${p%%|*}"
    MOCK_PROFILE=brak step "$p" step6 '2\n'
    check "[6] $name, profil „brak”: SKIPPED zamiast DONE" \
        'grep -q "^SKIPPED=Hardware profile: universal — profile tool is NOT responding" <<< "$skipped" && ! grep -q "^DONE=Hardware profile" <<< "$done_"'
done
MOCK_PROFILE=brak step "$P_FED" step6 '1\n'
check "[6] Fedora, profil „brak”: porada dnf swap tuned-ppd, bez asus-installation.sh" '[[ "$out" == *"sudo dnf swap tuned-ppd power-profiles-daemon"* && "$out" != *"asus-installation.sh"* ]]'
MOCK_PROFILE=brak step "$P_NIX" step6 '1\n'
check "[6] NixOS, profil „brak”: opcje NixOS, bez asus-installation.sh i sudo" '[[ "$out" == *"services.asusd.enable = true;"* && "$out" != *"asus-installation.sh"* && "$out" != *sudo* ]]'

# ─── [6.5] mikrokod, GPU, jądro ──────────────────────────────────────────────
echo "== [6.5] sterowniki i jądro"
for p in "${NONARCH[@]}" "$P_ASKIP"; do
    name="${p%%|*}"
    step "$p" step65 'y\ny\ny\n'
    check "[6.5] $name: żaden z trzech pomocników, odpowiedzi nieprzeczytane" 'no_helpers && [[ "$rest" == "$(<"$T/stdin")" ]]'
    check "[6.5] $name: krok ręczny na ekranie, bez fałszywego DONE i bez FAILED" \
        '[[ "$out" == *"CPU microcode, GPU drivers, kernel: not done automatically on"* && -z "$done_" ]] && ! grep -q FAILED <<< "$skipped"'
done
for p in "${NONARCH[@]}"; do
    name="${p%%|*}"
    step "$p" step65 'y\ny\ny\n'
    check "[6.5] $name: zero sudo/pacman/mkinitcpio/grub-mkconfig" 'no_mutation && sudo_k_only "$p"'
done
step "$P_FED" step65 'y\ny\ny\n'
check "[6.5] Fedora: narzędzia Fedory (RPM Fusion), bez ścieżki pomocników Archa" '[[ "$out" == *"use Fedora'"'"'s tools (NVIDIA: RPM Fusion)"* && "$out" != *"cpudrivers-installation"* ]]'
step "$P_NIX" step65 'y\ny\ny\n'
check "[6.5] NixOS: hardware.* i boot.kernelPackages" '[[ "$out" == *"hardware.*, boot.kernelPackages"* ]]'
step "$P_ASKIP" step65 'y\ny\ny\n'
check "[6.5] Arch+skip: polecenia trzech pomocników jako instrukcja" '[[ "$out" == *"install/{cpudrivers-installation,gpudrivers-installation,kernel-install}.sh"* ]]'
step "$P_ARCH" step65 'y\ny\ny\n'
check "[6.5] Arch, kody 0: trzy pomocniki, podsumowanie czyste" '[[ $(grep -c "^RUN " "$CALLS") -eq 3 && -z "$skipped" ]]'
MOCK_CPUDRIVERS_RC=2 MOCK_GPUDRIVERS_RC=1 MOCK_KERNEL_RC=2 step "$P_ARCH" step65 'y\ny\ny\n'
check "[6.5] Arch, kody 2/1/2: wpisy bootowania ×2 i FAILED dla GPU" \
    '[[ $(grep -c "boot entries need the manual steps" <<< "$skipped") -eq 2 ]] && grep -q "^SKIPPED=GPU drivers — installation FAILED" <<< "$skipped" && [[ -z "$done_" ]]'

# ─── [10] zapora, sieć, Bluetooth, VirtualBox, audio ────────────────────────
echo "== [10] usługi i pomocniki opcjonalne"
for p in "${NONARCH[@]}"; do
    name="${p%%|*}"
    for ufw in "" 1; do
        MOCK_UFW_ACTIVE=$ufw step "$p" step10 'y\ny\ny\ny\n'
        check "[10] $name${ufw:+, aktywna UFW}: Bluetooth i VirtualBox niewywołane, zero ufw/sudo/enable" \
            'no_helpers && no_mutation && sudo_k_only "$p" && ! grep -q "^ufw" "$CALLS"'
        # D6F L3 (przegląd Codexa): pominięty Bluetooth nie zostawia flagi ikony.
        check "[10] $name${ufw:+, aktywna UFW}: brak data/bluetooth-enabled.dat po pominięciu Bluetooth" '[[ ! -e "$A/data/bluetooth-enabled.dat" ]]'
        check "[10] $name${ufw:+, aktywna UFW}: bez pytań, bez DONE; sieć i audio jako kroki ręczne w podsumowaniu" \
            '[[ "$rest" == "$(<"$T/stdin")" && -z "$done_" ]] && grep -q "^SKIPPED=NetworkManager — not done on" <<< "$skipped" && grep -q "^SKIPPED=Audio (pipewire-pulse) — not done on" <<< "$skipped"'
    done
done
MOCK_ENABLED="$AUDIO_UP" MOCK_ACTIVE="$AUDIO_UP" step "$P_NIX" step10 ''
check "[10] NixOS, usługi już działają: tylko odczyty systemctl, podsumowanie puste" \
    'no_mutation && ! grep -q "^sudo" "$CALLS" && grep -q "^systemctl is-enabled --quiet NetworkManager" "$CALLS" && [[ -z "$done_" && -z "$skipped" ]]'
step "$P_FED" step10 ''
check "[10] Fedora: firewalld nietknięty, NetworkManager przez systemctl jako porada" \
    '[[ "$out" == *"Fedora uses firewalld, left as it is"* && "$out" == *"sudo systemctl enable --now NetworkManager"* ]]'
step "$P_NIX" step10 ''
check "[10] NixOS: networking.firewall, networkmanager, pipewire, bluetooth, virtualbox jako opcje" \
    '[[ "$out" == *"networking.firewall"* && "$out" == *"networking.networkmanager.enable = true;"* && "$out" == *"services.pipewire.pulse.enable = true;"* && "$out" == *"hardware.bluetooth.enable = true;"* && "$out" == *"virtualisation.virtualbox.host.enable = true;"* ]]'
MOCK_ENABLED="$AUDIO_UP" MOCK_ACTIVE="$AUDIO_UP" step "$P_ASKIP" step10 'n\n'
check "[10] Arch+skip: Bluetooth i VirtualBox niewywołane, polecenia pomocników jako instrukcja, bez flagi ikony" \
    'no_helpers && [[ ! -e "$A/data/bluetooth-enabled.dat" ]] && [[ "$out" == *"bash ~/archenemy/install/bluetooth-installation.sh"* && "$out" == *"bash ~/archenemy/install/virtualbox-installation.sh"* ]]'
# Arch: UFW n, NetworkManager włączony, Bluetooth y, VirtualBox y.
for rc in 0 1 2; do
    MOCK_ENABLED="$AUDIO_UP" MOCK_ACTIVE="$AUDIO_UP" MOCK_VIRTUALBOX_RC=$rc MOCK_BLUETOOTH_RC=$rc \
        step "$P_ARCH" step10 'n\ny\ny\n'
    case $rc in
        0) want='^DONE=VirtualBox installed \(vboxdrv loaded\)' ;;
        1) want='^SKIPPED=VirtualBox — installation failed' ;;
        2) want='^SKIPPED=VirtualBox — installed, but vboxdrv is not running in the current kernel: reboot' ;;
    esac
    check "[10] Arch, VirtualBox kod $rc → właściwy wpis, pomocnik raz" \
        'ran virtualbox-installation && [[ $(grep -c "^RUN virtualbox" "$CALLS") -eq 1 ]] && grep -qE "$want" <<< "$done_"$'"'"'\n'"'"'"$skipped"'
    [[ $rc -eq 0 ]] || check "[10] Arch, VirtualBox kod $rc: bez DONE dla VirtualBoksa" '! grep -q "^DONE=VirtualBox" <<< "$done_"'
    if [[ $rc -eq 0 ]]; then
        check "[10] Arch, Bluetooth kod 0 → DONE" 'ran bluetooth-installation && grep -q "^DONE=Bluetooth enabled" <<< "$done_"'
    else
        check "[10] Arch, Bluetooth kod $rc → SKIPPED, bez DONE" 'grep -q "^SKIPPED=Bluetooth — setup incomplete" <<< "$skipped" && ! grep -q "^DONE=Bluetooth" <<< "$done_"'
    fi
done
MOCK_ENABLED="$AUDIO_UP" MOCK_ACTIVE="$AUDIO_UP" step "$P_ARCH" step10 'n\nn\nn\n'
check "[10] Arch, odmowa Bluetooth i VirtualBox: pomocniki niewywołane, bez wpisów" \
    'no_helpers && ! grep -qE "^(DONE|SKIPPED)=(VirtualBox|Bluetooth)" <<< "$done_"$'"'"'\n'"'"'"$skipped"'

# ─── pochodna = Arch ─────────────────────────────────────────────────────────
echo "== EndeavourOS (ID_LIKE=arch) = Arch"
same_as_arch() {   # same_as_arch <wycinek> <stdin> — wyjście, wywołania, podsumowanie
    local a_out a_calls a_sum
    step "$P_ARCH" "$1" "$2"; a_out="$out"; a_calls="$calls"; a_sum="$(<"$T/summary")"
    step "$P_EOS" "$1" "$2"
    [[ "$out" == "$a_out" && "$calls" == "$a_calls" && "$(<"$T/summary")" == "$a_sum" ]]
}
export MOCK_ASUS_RC=2 MOCK_GPUDRIVERS_RC=1 MOCK_VIRTUALBOX_RC=2
check "[6] ASUS: pochodna = Arch"  'same_as_arch step6 "1\n"'
check "[6.5]: pochodna = Arch"     'same_as_arch step65 "y\ny\ny\n"'
check "[10]: pochodna = Arch"      'same_as_arch step10 "y\nn\ny\ny\n"'
unset MOCK_ASUS_RC MOCK_GPUDRIVERS_RC MOCK_VIRTUALBOX_RC

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
