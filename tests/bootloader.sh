#!/usr/bin/env bash
# =============================================
#   archenemy - tests/bootloader.sh
#   Testy kroków instalatora, które dotykają rozruchu (KT2 z audytu
#   2026-11-05: żaden test ich nie wymieniał):
#     install/bootloader.sh — wykrycie GRUB / systemd-boot / nieznany
#       i regeneracja (GRUB automatycznie, reszta tylko kroki ręczne);
#     install/kernel-install.sh — jądro + nagłówki, bootloader dopiero
#       po sprawdzeniu obu pakietów w bazie pacmana;
#     install/cpudrivers-installation.sh — mikrokod według producenta CPU.
#   ATRAPY w PATH: sudo, pacman, grub-mkconfig, bootctl — żadna nic nie
#   zapisuje poza dziennikiem w mktemp. /boot i /proc/cpuinfo podmieniają
#   haki ARCHENEMY_BOOT_DIR / ARCHENEMY_CPUINFO, działające tylko
#   z ARCHENEMY_TEST=1. Przed pierwszym biegiem test sprawdza, że sudo,
#   pacman, grub-mkconfig i bootctl to atrapy — inaczej odmawia (jako root
#   prawdziwe sudo naprawdę zainstalowałoby pakiet). Platforma: jawny
#   os-release Archa; bramy innych platform — tests/helper-gates.sh.
#   Uruchom: bash tests/bootloader.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval (zmienne żyją w eval); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BL="$REPO/install/bootloader.sh"
KI="$REPO/install/kernel-install.sh"
CPU="$REPO/install/cpudrivers-installation.sh"
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
mkdir -p "$T/bin" "$T/nogrub"
cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >> "$MOCK_LOG"
exec "$@"
EOF
# pacman: -S dopisuje pakiety do atrapy bazy (MOCK_DB), chyba że są
# w MOCK_PACMAN_DROP (kod 0, a pakietu nie ma); MOCK_PACMAN_FAIL=1 = kod 1.
# -Qi <pakiet> = jest w MOCK_DB.
cat > "$T/bin/pacman" <<'EOF'
#!/usr/bin/env bash
echo "pacman $*" >> "$MOCK_LOG"
if [[ "$1" == -Qi ]]; then
    grep -qx -- "$2" "$MOCK_DB"; exit
fi
if [[ "$1" == -S ]]; then
    [[ "${MOCK_PACMAN_FAIL:-0}" == 1 ]] && exit 1
    for p in "${@:2}"; do
        [[ "$p" == -* || " ${MOCK_PACMAN_DROP:-} " == *" $p "* ]] && continue
        echo "$p" >> "$MOCK_DB"
    done
fi
exit 0
EOF
# grub-mkconfig tylko loguje — nigdy nie pisze pliku z -o (bez haka
# wskazywałby prawdziwy /boot/grub/grub.cfg).
cat > "$T/bin/grub-mkconfig" <<'EOF'
#!/usr/bin/env bash
echo "grub-mkconfig $*" >> "$MOCK_LOG"
exit "${MOCK_GRUB_RC:-0}"
EOF
# bootctl: tylko is-installed (MOCK_BOOTCTL=1 = systemd-boot zainstalowany);
# każde inne wywołanie zostaje w dzienniku i oblewa test „bez zmian”.
cat > "$T/bin/bootctl" <<'EOF'
#!/usr/bin/env bash
echo "bootctl $*" >> "$MOCK_LOG"
[[ "$1" == is-installed && "${MOCK_BOOTCTL:-0}" == 1 ]]
EOF
chmod +x "$T/bin"/*
cp "$T/bin/bootctl" "$T/nogrub/bootctl"   # PATH bez grub-mkconfig (wbudowane bash wystarczą)
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log" MOCK_DB="$T/db"
for c in sudo pacman grub-mkconfig bootctl; do
    if [[ "$(command -v "$c")" != "$T/bin/$c" ]]; then
        echo "✗ $c nie jest atrapą ($(command -v "$c")) — nie uruchamiam (dotknąłby systemu)"
        exit 1
    fi
done

B="$T/boot"
# boot <grub|sdboot|none> — świeża atrapa /boot, czysty dziennik i baza pacmana.
boot() {
    rm -rf "${B:?}"; mkdir -p "$B"; : > "$MOCK_LOG"; : > "$MOCK_DB"
    case "$1" in
        grub)   mkdir -p "$B/grub"; echo "# TEST grub.cfg" > "$B/grub/grub.cfg" ;;
        sdboot) mkdir -p "$B/loader/entries"
                printf 'title TEST Arch\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=LABEL=TEST rw\n' \
                    > "$B/loader/entries/arch.conf" ;;
    esac
}
snap() { (cd "$B" && find . -type f -exec md5sum {} + | sort); }
untouched() { [[ "$(snap)" == "$before" ]] && ! grep -q '^grub-mkconfig' "$MOCK_LOG" \
    && ! grep -v '^bootctl is-installed' "$MOCK_LOG" | grep -q '^bootctl'; }
regenerated() { grep -qx "grub-mkconfig -o $B/grub/grub.cfg" "$MOCK_LOG"; }
installed() { grep -qx "sudo pacman -S --needed $*" "$MOCK_LOG"; }
no_install() { ! grep -q '^pacman -S' "$MOCK_LOG"; }
# Jawny Arch (brama platformy D6, install/lib/pkg.sh): wynik nie zależy od
# dystrybucji hosta. Inne platformy: tests/helper-gates.sh.
printf 'NAME="Arch Linux"\nID=arch\n' > "$T/os-release-arch"
export ARCHENEMY_TEST=1 ARCHENEMY_BOOT_DIR="$B" ARCHENEMY_OS_RELEASE="$T/os-release-arch"
# lib '<kod>' — kod w świeżym bashu z wczytanym install/bootloader.sh.
lib() { bash -c 'source "$0"; '"$1" "$BL" 2>&1; }
cpuinfo() { printf 'processor\t: 0\nvendor_id\t: %s\nmodel name\t: TEST CPU\n' "$1" > "$T/cpuinfo"; }
export ARCHENEMY_CPUINFO="$T/cpuinfo"
run_ki()  { printf '%b' "$1" | bash "$KI" 2>&1; }
run_cpu() { printf '%b' "$1" | bash "$CPU" 2>&1; }

echo "== A: bootloader.sh — wykrycie"
boot grub
check "grub.cfg + grub-mkconfig → grub"                 '[[ "$(lib detect_bootloader)" == grub ]]'
check "grub.cfg bez grub-mkconfig w PATH → nie grub"     '[[ "$(PATH="$T/nogrub" "$BASH" -c "source \"$BL\"; detect_bootloader")" == unknown ]]'
boot none
check "bootctl is-installed → systemd-boot"             '[[ "$(MOCK_BOOTCTL=1 lib detect_bootloader)" == systemd-boot ]]'
check "pusty /boot, bootctl bez systemd-boot → unknown"  '[[ "$(lib detect_bootloader)" == unknown ]]'
boot sdboot
check "katalog loader/entries bez bootctl → systemd-boot" '[[ "$(lib detect_bootloader)" == systemd-boot ]]'

echo "== B: bootloader.sh — regeneracja"
boot grub
out="$(lib 'regenerate_bootloader "TEST ctx"; echo "rc=$?"')"
check "GRUB: grub-mkconfig -o grub.cfg przez sudo"       'regenerated && grep -qx "sudo grub-mkconfig -o $B/grub/grub.cfg" "$MOCK_LOG"'
check "GRUB: ✓ z kontekstem, kod 0"                     '[[ "$out" == *"✓ GRUB updated (TEST ctx)."* && "$out" == *"rc=0"* ]]'
boot grub
out="$(MOCK_GRUB_RC=1 lib 'regenerate_bootloader "TEST ctx"; echo "rc=$?"')"
check "GRUB pada: ✗ z komendą ręczną, kod 1, bez ✓"     '[[ "$out" == *"✗ grub-mkconfig failed"* && "$out" == *"sudo grub-mkconfig -o"* && "$out" == *"rc=1"* && "$out" != *"✓"* ]]'
boot sdboot; before="$(snap)"
out="$(lib 'regenerate_bootloader "TEST ctx"; echo "rc=$?"')"
check "systemd-boot: wpisy nietknięte, bez grub-mkconfig" 'untouched'
check "systemd-boot: kroki ręczne z kontekstem, kod 2"  '[[ "$out" == *"Finish manually for: TEST ctx"* && "$out" == *"initrd  /intel-ucode.img"* && "$out" == *"rc=2"* ]]'
check "systemd-boot: bez modeset w krokach (nie cmdline)" '[[ "$out" != *modeset* ]]'
boot none; before="$(snap)"
out="$(lib 'regenerate_bootloader "TEST ctx"; echo "rc=$?"')"
check "nieznany: nic nie zmienione, ostrzeżenie, kod 2" 'untouched && [[ "$out" == *"Bootloader not recognized"* && "$out" == *"TEST ctx"* && "$out" == *"rc=2"* ]]'

echo "== C: kernel-install.sh"
boot grub
out="$(run_ki '\n')"; rc=$?
check "Enter przy wyborze jądra: pominięte, kod 0, bez pacmana" '[[ $rc -eq 0 && "$out" == *"No kernel selected"* ]] && no_install'
boot grub
out="$(run_ki '2\n\n')"; rc=$?
check "linux-zen, Enter przy [y/N]: domyślne nie, kod 0" '[[ $rc -eq 0 && "$out" != *"installed."* ]] && no_install && ! regenerated'
boot grub
out="$(run_ki '2\nn\n')"; rc=$?
check "linux-zen, odpowiedź n: bez instalacji, kod 0"   '[[ $rc -eq 0 ]] && no_install && ! regenerated'
boot grub
out="$(run_ki '2\ny\n')"; rc=$?
check "linux-zen: jądro i nagłówki jedną transakcją"    'installed linux-zen linux-zen-headers'
check "linux-zen: ✓ i GRUB zregenerowany, kod 0"        '[[ $rc -eq 0 && "$out" == *"✓ linux-zen + linux-zen-headers installed."* && "$out" == *"✓ GRUB updated (kernel linux-zen)."* ]] && regenerated'
# D6F L3 (przegląd Codexa): kod 1 z grub-mkconfig po udanej instalacji
# przechodzi przez WYWOŁUJĄCY kernel-install.sh (kontrakt z install.sh [6.5]).
boot grub
out="$(MOCK_GRUB_RC=1 run_ki '2\ny\n')"; rc=$?
check "linux-zen, grub-mkconfig pada: kernel-install kończy się kodem 1, bez ✓ GRUB" '[[ $rc -eq 1 && "$out" == *"✓ linux-zen + linux-zen-headers installed."* && "$out" == *"✗ grub-mkconfig failed"* && "$out" != *"✓ GRUB"* ]]'
boot grub
out="$(MOCK_PACMAN_DROP=linux-lts-headers run_ki '3\ny\n')"; rc=$?
check "brak nagłówków mimo kodu 0: ✗, kod 1"            '[[ $rc -eq 1 && "$out" == *"✗ Not installed: linux-lts-headers"* && "$out" != *"✓ linux-lts"* ]]'
check "brak nagłówków: bootloader nietknięty"          '! regenerated'
boot grub
out="$(MOCK_PACMAN_FAIL=1 run_ki '1\ny\n')"; rc=$?
check "pacman pada: ✗ z oboma pakietami, kod 1, bez GRUB-a" '[[ $rc -eq 1 && "$out" == *"✗ Not installed: linux linux-headers"* ]] && ! regenerated'
boot sdboot; before="$(snap)"
out="$(run_ki '2\ny\n')"
check "systemd-boot: ✓ jądra, wpisy nietknięte"         '[[ "$out" == *"✓ linux-zen + linux-zen-headers installed."* ]] && untouched'
check "systemd-boot: kroki kernel-install dla jądra"    '[[ "$out" == *"Finish manually for: kernel linux-zen"* && "$out" == *"kernel-install add"* ]]'

echo "== D: cpudrivers-installation.sh"
boot grub; cpuinfo GenuineIntel
out="$(run_cpu 'y\n')"; rc=$?
check "Intel: intel-ucode, ✓ i GRUB, kod 0"             'installed intel-ucode && [[ $rc -eq 0 && "$out" == *"✓ intel-ucode installed."* && "$out" == *"(microcode intel-ucode)"* ]] && regenerated'
boot grub; cpuinfo AuthenticAMD
out="$(run_cpu 'y\n')"; rc=$?
check "AMD: amd-ucode, ✓ i GRUB, kod 0"                 'installed amd-ucode && [[ $rc -eq 0 && "$out" == *"✓ amd-ucode installed."* ]] && regenerated'
boot grub; cpuinfo GenuineIntel
out="$(MOCK_GRUB_RC=1 run_cpu 'y\n')"; rc=$?
check "Intel, grub-mkconfig pada: cpudrivers kończy się kodem 1, bez ✓ GRUB (D6F L3)" '[[ $rc -eq 1 && "$out" == *"✓ intel-ucode installed."* && "$out" == *"✗ grub-mkconfig failed"* && "$out" != *"✓ GRUB"* ]]'
boot grub; cpuinfo TESTVENDOR
out="$(run_cpu 'y\n')"; rc=$?
check "nieznany producent: pominięte, kod 0, bez pacmana" '[[ $rc -eq 0 && "$out" == *"Unknown CPU vendor"* ]] && no_install && ! regenerated'
boot grub; cpuinfo GenuineIntel
out="$(run_cpu 'n\n')"; rc=$?
check "odpowiedź n: bez instalacji i GRUB-a, kod 0"     '[[ $rc -eq 0 ]] && no_install && ! regenerated'
boot grub; cpuinfo GenuineIntel
out="$(MOCK_PACMAN_FAIL=1 run_cpu 'y\n')"; rc=$?
check "pacman pada: ✗, kod 1, bootloader nietknięty"    '[[ $rc -eq 1 && "$out" == *"✗ intel-ucode was not installed"* && "$out" != *"✓ intel-ucode"* ]] && ! regenerated'
boot grub; cpuinfo GenuineIntel
out="$(MOCK_PACMAN_DROP=intel-ucode run_cpu 'y\n')"; rc=$?
check "kod 0, a pakietu brak w bazie: ✗, kod 1, bez GRUB-a" '[[ $rc -eq 1 && "$out" == *"✗ intel-ucode was not installed"* ]] && ! regenerated'
boot sdboot; before="$(snap)"; cpuinfo AuthenticAMD
out="$(run_cpu 'y\n')"
check "systemd-boot: wpisy nietknięte, krok initrd mikrokodu" 'untouched && [[ "$out" == *"Finish manually for: microcode amd-ucode"* && "$out" == *"initrd  /amd-ucode.img"* ]]'

echo "== E: haki tylko z ARCHENEMY_TEST=1"
probe() { env -i PATH="$PATH" "$@" bash -c 'source "$0"; echo "$_BL_BOOT_DIR"' "$BL"; }
check "bootloader: bez ARCHENEMY_TEST hak ignorowany"   '[[ "$(probe ARCHENEMY_BOOT_DIR=/tmp/zly)" == /boot ]]'
check "bootloader: ARCHENEMY_TEST=0 → /boot"            '[[ "$(probe ARCHENEMY_TEST=0 ARCHENEMY_BOOT_DIR=/tmp/zly)" == /boot ]]'
check "bootloader: ARCHENEMY_TEST=1 → atrapa"           '[[ "$(probe ARCHENEMY_TEST=1 ARCHENEMY_BOOT_DIR=/tmp/atrapa)" == /tmp/atrapa ]]'
# Bez ARCHENEMY_TEST skrypt czyta prawdziwy /proc/cpuinfo; stdin pusty, więc
# na pytanie o mikrokod pada „nie” — atrapy w PATH i tak niczego nie instalują.
boot grub; cpuinfo TESTVENDOR
out="$(env -u ARCHENEMY_TEST bash "$CPU" < /dev/null 2>&1)"
check "cpudrivers: bez ARCHENEMY_TEST hak ignorowany"   '[[ "$out" != *TESTVENDOR* ]] && no_install'
# Linie z komendą sudo (komunikaty `echo` z gotową komendą dla użytkownika
# nie są wykonywane); niecytowana ścieżka pod sudo = dzielenie na słowa.
sudo_lines="$(grep -nE '^[^#]*\bsudo\b' "$BL" | grep -v 'echo ')"
unquoted="$(grep -E '[^"]\$_BL_BOOT_DIR' <<< "$sudo_lines")"
check "każde \$_BL_BOOT_DIR pod sudo cytowane"           '[[ -n "$sudo_lines" && -z "$unquoted" ]]'
[[ -n "$unquoted" ]] && sed 's/^/      /' <<< "$unquoted"

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
