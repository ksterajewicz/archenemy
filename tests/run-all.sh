#!/bin/bash
# =============================================
#   archenemy - tests/run-all.sh
#   Uruchamia wszystkie pakiety testów z tests/*.sh (poza sobą) i podaje
#   zbiorczy wynik. Każdy pakiet działa na atrapach w mktemp — bez
#   Hyprlanda, bez roota, bez zapisu poza katalogami tymczasowymi.
#   Uruchom: bash tests/run-all.sh   (kod 0 = wszystkie pakiety zielone)
# =============================================

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=()
for t in "$DIR"/*.sh; do
    [[ "$(basename "$t")" == run-all.sh ]] && continue
    if out="$(bash "$t" 2>&1)"; then
        echo "✓ $(basename "$t") — ${out##*$'\n'}"
    else
        echo "✗ $(basename "$t")"
        grep '✗' <<< "$out" | sed 's/^/    /'
        failed+=("$(basename "$t")")
    fi
done
echo ""
if ((${#failed[@]})); then echo "NIEZIELONE: ${failed[*]}"; exit 1; fi
echo "Wszystkie pakiety zielone."
