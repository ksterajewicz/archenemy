#!/usr/bin/env bash
# =============================================
#   archenemy - tests/runtime-dir.sh
#   Prywatny katalog sesji (scripts/lib/runtime-dir.sh) i jego wołający.
#
#   Powód powstania (audyt 2026-11-05, S12): skrypty brały
#   ${XDG_RUNTIME_DIR:-/tmp}, więc bez zmiennej blokady, stan Super+Tab i logi
#   lądowały we wspólnym /tmp, gdzie inny użytkownik mógł je założyć pierwszy.
#   Tu: żadnego takiego zapasu w kodzie, wybór katalogu (własny, 0700, nie
#   symlink), odmowa przy podstawionym katalogu i window-history.sh, które
#   wtedy niczego nie zapisuje. /run/user/<UID> zastępuje hak
#   ARCHENEMY_RUNTIME_SYSTEM, więc test nie dotyka prawdziwego katalogu sesji.
#   Uruchom: bash tests/runtime-dir.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
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

echo "== kod bez zapasu we wspólnym /tmp"
hits="$(grep -rnE 'XDG_RUNTIME_DIR:-(/tmp|\$\{?TMPDIR)' "$REPO/scripts" "$REPO/config" "$REPO/install" \
    --include='*.sh' --include='*.lua' --include='*.py' | grep -v '^[^:]*:[0-9]*:[[:space:]]*\(#\|--\)')"
check "żadnego \${XDG_RUNTIME_DIR:-/tmp} w skryptach"  '[[ -z "$hits" ]]'
[[ -z "$hits" ]] || sed 's/^/      /' <<< "$hits"

# shellcheck source=scripts/lib/runtime-dir.sh
source "$REPO/scripts/lib/runtime-dir.sh"
mkdir -m 700 "$T/xdg" "$T/sys" "$T/evil"
mkdir -m 755 "$T/open"
mkdir -m 1777 "$T/shared"
pick() { XDG_RUNTIME_DIR="$1" ARCHENEMY_RUNTIME_SYSTEM="$2" TMPDIR="$3" archenemy_runtime_dir "${@:4}"; }
FB() { printf '%s/archenemy-%s' "$1" "$UID"; }

echo "== wybór katalogu"
check "XDG_RUNTIME_DIR 0700 = on"                     '[[ "$(pick "$T/xdg" "$T/sys" "$T/tA")" == "$T/xdg" ]]'
check "XDG 0755 pominięty → /run/user/<UID>"          '[[ "$(pick "$T/open" "$T/sys" "$T/tA")" == "$T/sys" ]]'
check "XDG = wspólny katalog 1777 pominięty"          '[[ "$(pick "$T/shared" "$T/sys" "$T/tA")" == "$T/sys" ]]'
ln -s "$T/xdg" "$T/xdg-link"
check "XDG jako symlink pominięty"                    '[[ "$(pick "$T/xdg-link" "$T/sys" "$T/tA")" == "$T/sys" ]]'
mkdir -p "$T/tA"
out="$(pick "" "$T/none" "$T/tA")"; rc=$?
check "bez obu: własny $(basename "$(FB x)") w TMPDIR"  '[[ $rc == 0 && "$out" == "$(FB "$T/tA")" ]]'
check "zapasowy katalog ma prawa 700"                 '[[ "$(stat -c %a "$(FB "$T/tA")")" == 700 ]]'
check "drugie wywołanie: ten sam katalog"             '[[ "$(pick "" "$T/none" "$T/tA")" == "$(FB "$T/tA")" ]]'
mkdir -p "$T/tB"
out="$(pick "" "$T/none" "$T/tB" --existing)"; rc=$?
check "--existing niczego nie zakłada"                '[[ $rc == 1 && -z "$out" && ! -e "$(FB "$T/tB")" ]]'

echo "== odmowa przy podstawionym katalogu"
mkdir -p "$T/tC"; ln -s "$T/evil" "$(FB "$T/tC")"
out="$(pick "" "$T/none" "$T/tC")"; rc=$?
check "zapasowy jako symlink → kod 1, pusto"          '[[ $rc == 1 && -z "$out" ]]'
mkdir -p "$T/tD"; mkdir -m 777 "$(FB "$T/tD")"
out="$(pick "" "$T/none" "$T/tD")"; rc=$?
check "zapasowy 0777 → kod 1"                         '[[ $rc == 1 && -z "$out" ]]'
mkdir -p "$T/tE"; mkdir -m 700 "$(FB "$T/tE")"
if chown 65534 "$(FB "$T/tE")" 2>/dev/null && [[ ! -O "$(FB "$T/tE")" ]]; then
    out="$(pick "" "$T/none" "$T/tE")"; rc=$?
    check "zapasowy innego użytkownika → kod 1"       '[[ $rc == 1 && -z "$out" ]]'
else
    echo "  ? pominięte: chown na innego użytkownika niedostępny"
fi

echo "== window-history.sh bez prywatnego katalogu"
# Stary kod z zapasem /tmp pisałby tu do PRAWDZIWEGO /tmp — wtedy tylko ✗.
if [[ -n "$hits" ]]; then
    fail "window-history.sh: pominięte, bo kod ma jeszcze zapas /tmp"
    echo ""; echo "Wynik: $PASS ✓ / $FAIL ✗"; exit 1
fi
WH="$REPO/scripts/hypr/window-history.sh"
out="$(XDG_RUNTIME_DIR="" ARCHENEMY_RUNTIME_SYSTEM="$T/none" TMPDIR="$T/tC" bash "$WH" list 2>&1)"; rc=$?
check "odmawia (kod ≠ 0) z komunikatem"               '[[ $rc != 0 && "$out" == *"no private runtime directory"* ]]'
check "nic nie trafia do podstawionego katalogu"      '[[ -z "$(ls -A "$T/evil")" ]]'
mkdir -p "$T/tF"
XDG_RUNTIME_DIR="" ARCHENEMY_RUNTIME_SYSTEM="$T/none" TMPDIR="$T/tF" bash "$WH" list >/dev/null 2>&1; rc=$?
check "z własnym zapasowym: stan w nim, 0700"         '[[ $rc == 0 && "$(stat -c %a "$(FB "$T/tF")/archenemy-window-history")" == 700 ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
((FAIL == 0))
