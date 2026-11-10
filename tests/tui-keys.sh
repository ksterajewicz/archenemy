#!/bin/bash
# =============================================
#   archenemy - tests/tui-keys.sh
#   Klawisze TUI Super+A (scripts/appbinds/lib/tui.sh + prawdziwe appbinds.sh
#   i update-archenemy.sh). Bez roota, zapis tylko w mktemp.
#
#   Powód powstania (audyt TUI 2026-11-05, K1–K3): strzałka działała jak Esc i
#   zamykała menu, a Esc na pytaniu [Y/n] w aktualizatorze uruchamiał instalator.
#   Uruchom: bash tests/tui-keys.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# shellcheck source=../scripts/appbinds/lib/tui.sh
source "$REPO/scripts/appbinds/lib/tui.sh"
key() { printf '%b' "$1" | read_key "" 2>/dev/null; }
yes_no() { printf '%b' "$1" | confirm "q?" "$2" 2>/dev/null; }

echo "== read_key"
check "zwykły klawisz"                    '[[ "$(key q)" == q ]]'
check "sam Esc"                           '[[ "$(key "\e")" == $'"'"'\e'"'"' ]]'
check "Enter = pusto"                     '[[ -z "$(key "\n")" ]]'
check "strzałka pominięta, liczy się q"   '[[ "$(key "\e[Aq")" == q ]]'
check "SS3 pominięte"                     '[[ "$(key "\eOPq")" == q ]]'
check "Delete (z tyldą) pominięte"        '[[ "$(key "\e[3~q")" == q ]]'
check "koniec wejścia → kod 1"            '! key "" >/dev/null'

echo "== confirm"
check "[Y/n] Enter = tak"                 'yes_no "\n" Y'
check "[Y/n] y = tak"                     'yes_no y Y'
check "[Y/n] n = nie"                     '! yes_no n Y'
check "[Y/n] Esc = nie"                   '! yes_no "\e" Y'
check "[Y/n] inny klawisz = nie"          '! yes_no x Y'
check "[y/N] Enter = nie"                 '! yes_no "\n" N'
check "[y/N] Esc = nie"                   '! yes_no "\e" N'
check "[y/N] y = tak"                     'yes_no y N'

check "[y/N] strzałka w górę = tak" 'yes_no "\e[A\n" N'
check "[Y/n] strzałka w dół = nie" '! yes_no "\e[B\n" Y'
check "j/k zmieniają odpowiedź" 'yes_no "k\n" N'
check "EOF nie zatwierdza" '! yes_no "" Y'
# Otwarte wejście bez danych: rzeczywisty timeout, bez oczekiwania 15 sekund.
start=$SECONDS
if TUI_MENU_TIMEOUT=1 confirm "timeout" Y < <(sleep 2) 2>/dev/null; then
    fail "timeout nie zatwierdza"
else
    check "timeout kończy przed zamknięciem wejścia" '(( SECONDS - start < 2 ))'
fi

check "cyfra 1 nie zatwierdza Y" '! yes_no "1\n" Y'
check "cyfra 1 nie zatwierdza N" '! yes_no "1\n" N'

echo "== menu główne"
H="$T/home"; mkdir -p "$H/archenemy/config/hypr" "$H/archenemy/data" "$T/bin"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/clear"; chmod +x "$T/bin/clear"
tui() { printf '%b' "$1" | HOME="$H" PATH="$T/bin:$PATH" timeout 10 bash "$REPO/scripts/appbinds/appbinds.sh" 2>&1; }
out="$(tui '\e[A\e[Bq')"; rc=$?
check "strzałki nie zamykają, q zamyka"   '[[ $rc -eq 0 ]]'
tui '' >/dev/null; rc=$?
check "koniec wejścia kończy pętlę (K3)"  '[[ $rc -eq 0 ]]'
out="$(tui 'v\e[A\n\nq')"; rc=$?
check "strzałka w podmenu nie blokuje"    '[[ $rc -eq 0 ]]'

echo "== aktualizator: Esc nie uruchamia instalatora (K2)"
g() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}" >/dev/null; }
git init -q --bare "$T/origin.git"
A="$H/archenemy"; rm -rf "$A"; git init -q -b dev "$A"
mkdir -p "$A/install"; printf '#!/bin/bash\necho INSTALL-RAN\n' > "$A/install/install.sh"; echo v1 > "$A/f"
g "$A" add -A; g "$A" commit -m v1
git -C "$A" remote add origin "$T/origin.git"; git -C "$A" push -q origin dev
upd() { printf '%b' "$1" | HOME="$H" bash "$REPO/scripts/appbinds/update-archenemy.sh" 2>&1; }
out="$(upd '1\e\n')"
check "Esc na [Y/n] → bez instalatora"    '[[ "$out" != *INSTALL-RAN* && "$out" == *"Updated"* ]]'
out="$(upd '1\n\n')"
check "Enter na [Y/n] → instalator"       '[[ "$out" == *INSTALL-RAN* ]]'
echo zmiana > "$A/f"
out="$(upd '1\e\n')"
check "Esc na stash → anulowane"          '[[ "$out" == *Cancelled* && "$(<"$A/f")" == zmiana && -z "$(git -C "$A" stash list)" ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
