#!/bin/bash
# =============================================
#   archenemy - tests/repo-hygiene.sh
#   Higiena repozytorium: rzeczy, które same z siebie brudzą working tree
#   użytkownika i blokują `git pull` (update-archenemy.sh, Super+A → [p]).
#   Bez roota, bez zapisu poza mktemp — czyta tylko indeks gita.
#
#   Powód powstania (audyt 2026-09-23): install.sh stracił bit wykonywania
#   w indeksie (commit 7f54012), a trzy biblioteki w scripts/ nigdy go nie
#   miały; README każe `chmod +x`, a install.sh robi `chmod +x` na wszystkich
#   scripts/**/*.sh — każda instalacja zmieniała tryb plików śledzonych,
#   git widział modyfikację i pull odmawiał (laptop 2026-09-17:
#   `M install/install.sh`, `M …/gen-workspaces.sh`, `M …/timer-state.sh`).
#   Uruchom: bash tests/repo-hygiene.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "== skrypty .sh w indeksie gita mają bit wykonywania (100755)"
bad=$(git -C "$REPO" ls-files -s -- '*.sh' | awk '$1 != "100755" {print $4}')
if [[ -z "$bad" ]]; then
    ok "wszystkie *.sh = 100755 (chmod +x z README/install.sh nie brudzi drzewa)"
else
    while IFS= read -r f; do fail "$f bez bitu wykonywania — git update-index --chmod=+x $f"; done <<< "$bad"
fi

echo "== atrapy w tests/mock są wykonywalne"
bad=$(git -C "$REPO" ls-files -s -- 'tests/mock/*' | awk '$1 != "100755" {print $4}')
if [[ -z "$bad" ]]; then ok "tests/mock/* = 100755"; else fail "bez bitu: $bad"; fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
