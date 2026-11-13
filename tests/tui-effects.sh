#!/bin/bash
# =============================================
#   archenemy - tests/tui-effects.sh
#   Strażnik: funkcja TUI Super+A nie może przestać działać niezauważenie.
#
#   Powód powstania (zgłoszenie właściciela 2026-11-13): w [n] nie dało się zmienić,
#   który monitor stoi po której stronie, a wszystkie testy były zielone, bo żaden
#   nie sprawdzał SKUTKU tej drogi (pozycji odczytanej z Hyprlanda).
#
#   Pilnuje czterech rzeczy, bez Hyprlanda i bez zapisu poza mktemp:
#     1. każda pozycja menu głównego (MENU_KEYS w appbinds.sh) ma wiersz w
#        tests/tui-effects.list, a pozycja zmieniająca stan wskazuje test skutku,
#        który naprawdę istnieje;
#     2. każdy skrypt otwierany z menu ma własny pakiet w tests/;
#     3. każda forma pozycji monitora (XxY, auto i litery z ask_position) ma test,
#        który porównuje wybór z .dat, z Lua i z `hyprctl monitors` (placed);
#     4. monitor-settings.sh nie ma gołego `return`: po nieudanym teście oddaje ono
#        kod 1 i wołający kończył cały dialog bez słowa.
#   Na końcu strażnik sprawdza sam siebie: na kopii z dopisaną pozycją menu i na
#   kopii z gołym `return` musi paść.
#   Uruchom: bash tests/tui-effects.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016  # wzorce seda i tekst skryptu są dosłowne
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${TUI_EFFECTS_APP:-$REPO/scripts/appbinds/appbinds.sh}"
MON="${TUI_EFFECTS_MON:-$REPO/scripts/hypr/monitor-settings.sh}"
LIST="$REPO/tests/tui-effects.list"
MON_TEST="$REPO/tests/monitor-settings.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "== pozycje menu głównego mają test skutku"
mapfile -t KEYS < <(sed -n 's/^MENU_KEYS=(\(.*\))$/\1/p' "$APP" | tr -s ' ' '\n')
if ((${#KEYS[@]} >= 10)); then ok "MENU_KEYS odczytane (${#KEYS[@]})"; else fail "MENU_KEYS nie do odczytania z appbinds.sh"; fi
mapfile -t ROWS < <(grep -v -e '^#' -e '^[[:space:]]*$' "$LIST")
for key in "${KEYS[@]}"; do
    found=0
    for row in "${ROWS[@]}"; do
        IFS='|' read -r rkey kind suite marker <<<"$row"
        [[ "$rkey" == "$key" ]] || continue
        found=1
        case "$kind" in
            read) ;;
            state)
                if [[ ! -f "$REPO/tests/$suite" ]]; then
                    fail "[$key] pakiet tests/$suite nie istnieje"
                elif [[ -z "$marker" ]] || ! grep -Fq -- "$marker" "$REPO/tests/$suite"; then
                    fail "[$key] w tests/$suite nie ma testu skutku: $marker"
                fi ;;
            *) fail "[$key] nieznany rodzaj '$kind' (state albo read)" ;;
        esac
    done
    if (( found )); then ok "[$key] opisane w tui-effects.list"; else fail "[$key] bez wiersza w tests/tui-effects.list (dopisz test skutku)"; fi
done
for row in "${ROWS[@]}"; do
    [[ " ${KEYS[*]} " == *" ${row%%|*} "* ]] || fail "wiersz dla [${row%%|*}], którego nie ma w MENU_KEYS"
done

echo "== skrypty otwierane z menu mają własny pakiet"
while IFS= read -r script; do
    name="$(basename "$script")"
    if [[ -f "$REPO/tests/$name" ]]; then ok "$name"; else fail "$name bez tests/$name"; fi
done < <(sed -n '/^run_item() {/,/^}/p' "$APP" | grep -o 'scripts/[a-z/-]*\.sh' | sort -u)

echo "== każda forma pozycji monitora ma test skutku"
# Wiersz `run '…<forma>\ny\n'`, a zaraz po nim check z placed albo lua_pos.
form_tested() {
    local next
    next="$(grep -E -A1 -- "run '[^']*\\\\n$1\\\\ny\\\\n'" "$MON_TEST" | grep -E '^check ')"
    [[ "$next" == *"placed "* || "$next" == *"lua_pos "* ]]
}
letters="$(sed -n 's/.*"\$ASK_POS" =~ ^(\[\([a-z]*\)\]).*/\1/p' "$MON")"
if [[ -n "$letters" ]]; then ok "formy z ask_position: XxY auto $letters"; else fail "nie znaleziono liter pozycji w ask_position"; fi
for (( i = 0; i < ${#letters}; i++ )); do
    if form_tested "${letters:i:1} [0-9]+"; then ok "forma '${letters:i:1} N'"; else fail "forma '${letters:i:1} N' bez testu z placed"; fi
done
if form_tested '-?[0-9]+x-?[0-9]+'; then ok "forma XxY"; else fail "forma XxY bez testu z placed"; fi
if form_tested 'auto'; then ok "forma auto"; else fail "forma auto bez testu skutku"; fi
if grep -Eq "run '[^']*\\\\nl [0-9]+\\\\nn\\\\n'" "$MON_TEST" && grep -Fq 'live_pos HDMI-A-1)" == 1920x0' "$MON_TEST"; then
    ok "odmowa potwierdzenia: odczyt powrotu"
else
    fail "brak testu, że po odmowie Hyprland wraca do starej pozycji"
fi

echo "== monitor-settings.sh bez gołego return"
bare="$(grep -n -E '(^|[;&|{]|then|else)[[:space:]]*return[[:space:]]*(;|$|#|\})' "$MON")"
if [[ -z "$bare" ]]; then ok "każdy return ma jawny kod"; else fail "gołe return: $(tr '\n' ' ' <<<"$bare" | cut -c1-200)"; fi

# Strażnik, który nie umie paść, niczego nie pilnuje.
if [[ -z "${TUI_EFFECTS_APP:-}${TUI_EFFECTS_MON:-}" ]]; then
    echo "== strażnik pada, gdy powinien"
    T="$(mktemp -d)"
    trap 'rm -rf "$T"' EXIT
    sed 's/^MENU_KEYS=(\(.*\))$/MENU_KEYS=(\1 z)/' "$APP" > "$T/appbinds.sh"
    out="$(TUI_EFFECTS_APP="$T/appbinds.sh" bash "${BASH_SOURCE[0]}" 2>&1)"; rc=$?
    if (( rc != 0 )) && [[ "$out" == *"[z] bez wiersza"* ]]; then ok "nowa pozycja menu bez testu = czerwono"; else fail "nowa pozycja menu przeszła bez testu"; fi
    { cat "$MON"; printf 'broken() {\n    ((${#DATS[@]})) || return\n}\n'; } > "$T/monitor-settings.sh"
    out="$(TUI_EFFECTS_MON="$T/monitor-settings.sh" bash "${BASH_SOURCE[0]}" 2>&1)"; rc=$?
    if (( rc != 0 )) && [[ "$out" == *"gołe return"* ]]; then ok "gołe return = czerwono"; else fail "gołe return przeszło"; fi
fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
