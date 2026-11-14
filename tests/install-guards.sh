#!/bin/bash
# =============================================
#   archenemy - tests/install-guards.sh
#   Strażniki instalatora z audytu bezpieczeństwa 2026-11-14:
#     K8  — install.sh odmawia biegu jako root (zanim cokolwiek zapisze);
#     K10 — haki ARCHENEMY_ETC_DIR/ARCHENEMY_MODULES_DIR instalatora GPU
#           działają tylko przy ARCHENEMY_TEST=1, ścieżki pod sudo cytowane;
#     K18 — `sudo -k` po ostatnim użyciu sudo w install.sh.
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

echo "== K8: install.sh a root"
# Pusty $HOME: bez strażnika install.sh zatrzymałby się na braku ~/archenemy,
# więc rozróżniamy komunikaty. EUID nie da się podrobić — test zależy od tego,
# kto go uruchamia (VPS/CI: root, laptop: użytkownik); oba przypadki sprawdzone.
out="$(HOME="$T/home" bash "$INST" < /dev/null 2>&1)"; rc=$?
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

echo "== K10: haki instalatora GPU tylko przy ARCHENEMY_TEST=1"
hooks="$(sed -n '/^# Haki testowe/,/^fi$/p' "$GPU")"
probe() { env -i PATH="$PATH" "$@" bash -c "$hooks"$'\n''echo "$ETC_DIR|$KMOD_DIR"'; }
check "bez ARCHENEMY_TEST hak ignorowany → /etc"  '[[ "$(probe ARCHENEMY_ETC_DIR=/tmp/zly ARCHENEMY_MODULES_DIR=/tmp/zly)" == "/etc|/usr/lib/modules" ]]'
check "ARCHENEMY_TEST=1 → atrapa"                 '[[ "$(probe ARCHENEMY_TEST=1 ARCHENEMY_ETC_DIR=/tmp/atrapa ARCHENEMY_MODULES_DIR=/tmp/m)" == "/tmp/atrapa|/tmp/m" ]]'
check "ARCHENEMY_TEST=0 → hak ignorowany"         '[[ "$(probe ARCHENEMY_TEST=0 ARCHENEMY_ETC_DIR=/tmp/zly)" == "/etc|/usr/lib/modules" ]]'
unquoted="$(grep -nE '\bsudo\b.*[^"]\$ETC_DIR' "$GPU")"
check "każde \$ETC_DIR w linii z sudo jest cytowane" '[[ -z "$unquoted" ]]'
[[ -n "$unquoted" ]] && sed 's/^/      /' <<< "$unquoted"

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
