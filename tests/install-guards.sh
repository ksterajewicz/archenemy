#!/usr/bin/env bash
# =============================================
#   archenemy - tests/install-guards.sh
#   Strażniki instalatora z audytu bezpieczeństwa 2026-11-14:
#     K8  — install.sh odmawia biegu jako root (zanim cokolwiek zapisze);
#     K10 — haki ARCHENEMY_ETC_DIR/ARCHENEMY_MODULES_DIR instalatora GPU
#           działają tylko przy ARCHENEMY_TEST=1, ścieżki pod sudo cytowane;
#           tak samo haki instalatora VirtualBoksa (I6, przegląd 2026-11-15);
#     K18 — `sudo -k` po ostatnim użyciu sudo w install.sh, a pułapka EXIT
#           unieważnia hasło także po Ctrl+C i exit z [2] (I4, przegląd 2026-11-15);
#     D5  — nieznana opcja i nieobsługiwana dystrybucja: odmowa przed [2], nic
#           nie zapisane; --skip-packages bez Hyprlanda: instrukcja zamiast pacmana;
#           [2] na Fedorze: Hyprland tylko z COPR po „y”, na NixOS: instrukcja.
#   Bez sudo i bez zapisu poza mktemp (install.sh dostaje pusty $HOME).
#   Uruchom: bash tests/install-guards.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$REPO/install/install.sh"
GPU="$REPO/install/gpudrivers-installation.sh"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# Atrapy dla biegów install.sh: sudo tylko loguje (pułapka EXIT woła `sudo -k`
# także jako użytkownik — prawdziwego sudo test nie rusza), clear i sleep nic.
mkdir -p "$T/m"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/sudo.log"\n' "$T" > "$T/m/sudo"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/m/clear"; cp "$T/m/clear" "$T/m/sleep"
chmod +x "$T/m"/*

echo "== K8: install.sh a root"
# Pusty $HOME: bez strażnika install.sh zatrzymałby się na braku ~/archenemy,
# więc rozróżniamy komunikaty. EUID nie da się podrobić — test zależy od tego,
# kto go uruchamia (VPS/CI: root, laptop: użytkownik); oba przypadki sprawdzone.
out="$(HOME="$T/home" PATH="$T/m:$PATH" bash "$INST" < /dev/null 2>&1)"; rc=$?
if [[ $EUID -eq 0 ]]; then
    check "root → odmowa z kodem 1"              '[[ $rc -eq 1 && "$out" == *"do not run install.sh as root"* ]]'
    check "root → nic nie zapisane w \$HOME"     '[[ -z "$(ls -A "$T/home")" ]]'
else
    check "użytkownik → strażnik roota przepuszcza" '[[ "$out" != *"as root"* && "$out" == *"expected the archenemy repo"* ]]'
fi
guard_line=$(grep -n 'EUID -eq 0' "$INST" | head -1 | cut -d: -f1)
first_write=$(grep -nE '^(mkdir|ln|cp|mv|rm|echo .*>|printf .*>)' "$INST" | head -1 | cut -d: -f1)
check "strażnik przed pierwszym zapisem w pliku"  '[[ -n "$guard_line" && -n "$first_write" && $guard_line -lt $first_write ]]'

echo "== K18: sudo -k po ostatnim sudo"
last_sudo=$(grep -nE '^[^#]*\bsudo\b' "$INST" | grep -v 'sudo -k' | tail -1 | cut -d: -f1)
k_line=$(grep -nE '^[^#]*sudo -k' "$INST" | tail -1 | cut -d: -f1)
check "sudo -k istnieje i stoi za ostatnim sudo"  '[[ -n "$k_line" && $k_line -gt $last_sudo ]]'

echo "== K18 (I4): sudo -k na KAŻDYM wyjściu — pułapka EXIT"
# Dawniej `sudo -k` stało tylko na zwykłym końcu: Ctrl+C, exit z [2] czy
# przerwanie przez `set -u` zostawiały hasło w pamięci sudo na 5 minut.
# Pierwsze WYWOŁANIE sudo (bez komunikatów: strażnik roota pisze „with sudo”).
first_sudo=$(grep -nE '^[^#]*\bsudo\b' "$INST" | grep -vE 'sudo -k|echo|read' | head -1 | cut -d: -f1)
exit_traps="$(grep -nE '^[^#]*\btrap\b.*\bEXIT\b' "$INST")"
first_trap=$(head -1 <<< "$exit_traps" | cut -d: -f1)
check "pułapka EXIT po strażniku, przed pierwszym sudo" '[[ -n "$first_trap" && $first_trap -gt $guard_line && $first_trap -lt $first_sudo && "$(head -1 <<< "$exit_traps")" == *"sudo -k"* ]]'
no_k="$(grep -v 'sudo -k' <<< "$exit_traps")"
check "każda pułapka EXIT w install.sh woła sudo -k"   '[[ -n "$exit_traps" && -z "$no_k" ]]'
[[ -n "$no_k" ]] && sed 's/^/      /' <<< "$no_k"
# Prawdziwy install.sh bez strażnika roota (testy biegną też jako root) na
# atrapach: brak hyprctl → krok [2]. Atrapa sudo tylko loguje.
# install/ z repo: install.sh przed [2] wczytuje install/lib/pkg.sh (wykrycie
# platformy, D5); os-release atrapy = Arch, niezależnie od maszyny testu.
H="$T/home-i4"; mkdir -p "$H/archenemy/rices" "$H/archenemy/packages" "$T/sys"
ln -s "$REPO/install" "$H/archenemy/install"
printf 'NAME="Arch Linux"\nID=arch\n' > "$T/os-release-arch"
export ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os-release-arch"
sed '/^if \[\[ \$EUID -eq 0 \]\]; then$/,/^fi$/d' "$INST" > "$T/inst-noguard.sh"
for c in bash env setsid timeout; do ln -s "$(command -v "$c")" "$T/sys/$c"; done
run_inst() {   # run_inst <odpowiedzi> [argumenty] — install.sh bez strażnika; wynik: out, rc
    rm -f "$T/sudo.log"
    out="$(printf '%b' "$1" | env HOME="$H" PATH="$T/m:$T/sys" bash "$T/inst-noguard.sh" "${@:2}" 2>&1)"; rc=$?
}
run_inst 'y\n'
check "[2] odpowiedź y → exit 0, sudo -k po pacman" '[[ $rc -eq 0 && "$(cat "$T/sudo.log" 2>/dev/null)" == *"pacman -S --needed hyprland"* && "$(tail -1 "$T/sudo.log")" == -k ]]'
run_inst 'n\n'
check "[2] odpowiedź n → exit 0 i sudo -k"   '[[ $rc -eq 0 && "$out" == *"Exiting."* && "$(tail -1 "$T/sudo.log" 2>/dev/null)" == -k ]]'

echo "== D5: flagi i platforma — odmowa, zanim cokolwiek zapisze"
run_inst '' --no-such-flag
check "nieznana opcja → kod 1, usage, zero sudo (przed wykryciem platformy nie ma czego unieważniać)" '[[ $rc -eq 1 && "$out" == *"unknown option: --no-such-flag"* && "$out" == *"Usage: install.sh [--skip-packages]"* && ! -s "$T/sudo.log" ]]'
run_inst '' --help
check "--help → kod 0, usage" '[[ $rc -eq 0 && "$out" == *"--skip-packages"* ]]'
printf 'ID=ubuntu\nID_LIKE=debian\n' > "$T/os-release-ubuntu"
ARCHENEMY_OS_RELEASE="$T/os-release-ubuntu" run_inst 'y\n'
check "Ubuntu → kod 1 przed [2], zero sudo (także -k)" '[[ $rc -eq 1 && "$out" == *"Unsupported distribution (ID=ubuntu)"* && "$out" == *"nothing was installed"* && "$out" != *"Hyprland"* && ! -s "$T/sudo.log" ]]'
check "Ubuntu → nic nie zapisane w \$HOME" '[[ "$(cd "$H" && find . -mindepth 1 | sort | tr "\n" " ")" == "./archenemy ./archenemy/install ./archenemy/packages ./archenemy/rices " ]]'
run_inst 'y\n' --skip-packages
check "--skip-packages, brak Hyprlanda → instrukcja, kod 1, bez pacmana" '[[ $rc -eq 1 && "$out" == *"sudo pacman -S --needed hyprland"* && "$(grep -vx -- -k "$T/sudo.log" 2>/dev/null)" == "" ]]'
# Krok [2] poza Archem. Atrapa rpm (sam bash — PATH testu nie ma grep):
# hyprland „jest”, gdy sudo.log ma już `dnf install hyprland` (sudo tylko loguje).
printf '#!/usr/bin/env bash\n[[ "$1" == -q ]] || exit 2; shift; [[ "$1" == --qf ]] && shift 2\nfor p in "$@"; do if [[ "$p" == hyprland && -e "%s/sudo.log" && "$(<"%s/sudo.log")" == *"dnf install hyprland"* ]]; then echo "$p"; else echo "package $p is not installed"; exit 1; fi; done\n' "$T" "$T" > "$T/m/rpm"
chmod +x "$T/m/rpm"
printf 'ID=fedora\nVERSION_ID=44\n' > "$T/os-release-fedora"
printf 'ID=nixos\nVERSION_ID=26.05\n' > "$T/os-release-nixos"
ARCHENEMY_OS_RELEASE="$T/os-release-fedora" ARCHENEMY_OSTREE_MARKER="$T/none" run_inst 'n\n'
check "[2] Fedora, COPR bez zgody → Exiting., kod 0, nic nie włączone" '[[ $rc -eq 0 && "$out" == *"COPR nett00n/hyprland"* && "$out" == *"Exiting."* && "$(grep -vx -- -k "$T/sudo.log" 2>/dev/null)" == "" ]]'
ARCHENEMY_OS_RELEASE="$T/os-release-fedora" ARCHENEMY_OSTREE_MARKER="$T/none" run_inst 'y\n'
check "[2] Fedora, COPR po y → copr enable + dnf install hyprland, bez pacmana" '[[ $rc -eq 0 && "$out" == *"Hyprland installed."* ]] && grep -qx "dnf copr enable nett00n/hyprland" "$T/sudo.log" && grep -qx "dnf install hyprland" "$T/sudo.log" && ! grep -q pacman "$T/sudo.log"'
ARCHENEMY_OS_RELEASE="$T/os-release-nixos" run_inst 'y\n'
check "[2] NixOS → opcja programs.hyprland.enable, kod 1, zero sudo (także -k)" '[[ $rc -eq 1 && "$out" == *"programs.hyprland.enable"* && "$out" == *"0.56"* && ! -s "$T/sudo.log" ]]'
ARCHENEMY_OS_RELEASE="$T/os-release-fedora" ARCHENEMY_OSTREE_MARKER="$T/none" run_inst '' --skip-packages
check "[2] Fedora --skip-packages → instrukcja, kod 1, zero sudo (także -k)" '[[ $rc -eq 1 && "$out" == *"dnf"* && ! -s "$T/sudo.log" ]]'
# Ctrl+C przy pytaniu [2]: SIGINT do grupy procesów w nowej sesji z domyślną
# obsługą SIGINT, na znacznik w wyjściu (echo przed `read`; prompt `read -p`
# bez TTY się nie drukuje). Wejście otwarte, dopóki instalator żyje.
rm -f "$T/sudo.log" "$T/int.pid"; : > "$T/int.out"
exec 3< <(for ((i = 0; i < 300; i++)); do [[ "$(<"$T/int.out")" == *"Do you allow me"* ]] && break; sleep 0.1; done
          pid="$(<"$T/int.pid")"; kill -INT -- "-$pid" 2>/dev/null
          for ((i = 0; i < 300; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done)
feeder=$!
timeout 30 env --default-signal=INT HOME="$H" PATH="$T/m:$T/sys" \
    setsid bash -c 'echo $$ > "$1"; exec bash "$2"' _ "$T/int.pid" "$T/inst-noguard.sh" <&3 >"$T/int.out" 2>&1
rc=$?
exec 3<&-; wait "$feeder" 2>/dev/null
check "Ctrl+C przy [2] → SIGINT (130) i sudo -k" '[[ $rc -eq 130 && "$(<"$T/int.out")" == *"Do you allow me"* && "$(cat "$T/sudo.log" 2>/dev/null)" == -k ]]'

echo "== K10: haki instalatora GPU tylko przy ARCHENEMY_TEST=1"
hooks="$(sed -n '/^# Haki testowe/,/^fi$/p' "$GPU")"
probe() { env -i PATH="$PATH" "$@" bash -c "$hooks"$'\n''echo "$ETC_DIR|$KMOD_DIR"'; }
check "bez ARCHENEMY_TEST hak ignorowany → /etc"  '[[ "$(probe ARCHENEMY_ETC_DIR=/tmp/zly ARCHENEMY_MODULES_DIR=/tmp/zly)" == "/etc|/usr/lib/modules" ]]'
check "ARCHENEMY_TEST=1 → atrapa"                 '[[ "$(probe ARCHENEMY_TEST=1 ARCHENEMY_ETC_DIR=/tmp/atrapa ARCHENEMY_MODULES_DIR=/tmp/m)" == "/tmp/atrapa|/tmp/m" ]]'
check "ARCHENEMY_TEST=0 → hak ignorowany"         '[[ "$(probe ARCHENEMY_TEST=0 ARCHENEMY_ETC_DIR=/tmp/zly)" == "/etc|/usr/lib/modules" ]]'
unquoted="$(grep -nE '\bsudo\b.*[^"]\$ETC_DIR' "$GPU")"
check "każde \$ETC_DIR w linii z sudo jest cytowane" '[[ -z "$unquoted" ]]'
[[ -n "$unquoted" ]] && sed 's/^/      /' <<< "$unquoted"

echo "== I6: haki instalatora VirtualBoksa tylko przy ARCHENEMY_TEST=1"
# Blok haków do pierwszej pustej linii (nie do „fi”): w wersji bez bramki
# „fi” nie ma, a zakres do następnego „fi” wykonałby resztę instalatora.
VB="$REPO/install/virtualbox-installation.sh"
vb_hooks="$(sed -n '/^# Haki testowe/,/^$/p' "$VB")"
vb_probe() { env -i PATH="$PATH" "$@" bash -c "$vb_hooks"$'\n''echo "$KMOD_DIR|$SYSMOD_DIR"'; }
check "bez ARCHENEMY_TEST haki ignorowane → system" '[[ "$(vb_probe ARCHENEMY_MODULES_DIR=/tmp/zly ARCHENEMY_SYSMODULE_DIR=/tmp/zly)" == "/usr/lib/modules|/sys/module" ]]'
check "ARCHENEMY_TEST=1 → atrapa"                   '[[ "$(vb_probe ARCHENEMY_TEST=1 ARCHENEMY_MODULES_DIR=/tmp/m ARCHENEMY_SYSMODULE_DIR=/tmp/s)" == "/tmp/m|/tmp/s" ]]'
check "ARCHENEMY_TEST=0 → haki ignorowane"          '[[ "$(vb_probe ARCHENEMY_TEST=0 ARCHENEMY_SYSMODULE_DIR=/tmp/zly)" == "/usr/lib/modules|/sys/module" ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
