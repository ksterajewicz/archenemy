#!/bin/bash
# =============================================
#   Zgodność menu wierszowych z potokami i strzałkami.
# =============================================
set -uo pipefail
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/appbinds/lib/tui.sh"
check() {
    local input="$1" want="$2" rc=0
    tui_menu_lines 0 one two three <<<"$input" >/dev/null || rc=$?
    [[ "$rc:$TUI_MENU_INDEX" == "$want" ]] || { echo "✗ menu: $input → $rc:$TUI_MENU_INDEX, expected $want"; exit 1; }
}
check 2 0:1
check $'\e[B' 0:1
check j 0:1
check k 0:2
check $'\e[A' 0:2
check $'\e' 1:2
check '' 1:2
check 9 2:2
# shellcheck disable=SC2034  # skróty odczytuje wspólna biblioteka
TUI_MENU_KEYS=(a b c)
check c 0:2
check q 1:2
items=(); for (( i=1; i<=12; i++ )); do items+=("item $i"); done
tui_menu_lines 0 "${items[@]}" <<<12 >/dev/null
[[ "$TUI_MENU_INDEX" == 11 ]] || exit 1
if tui_menu_lines 0 one </dev/null >/dev/null; then exit 1; fi
echo 'Wynik: menu wierszowe — zielone'
