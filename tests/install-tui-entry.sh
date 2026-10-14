#!/bin/bash
# =============================================
#   archenemy - tests/install-tui-entry.sh
#   Test kroku [8m] install.sh: wpis „archenemy” w rofi (.desktop) i alias
#   `archenemy` w ~/.bashrc — na atrapie $HOME w mktemp. Wycinek [8m] jest
#   wycinany z install/install.sh sedem (jak [9] w tests/install-link.sh).
#   Sprawdzamy, że:
#     - .desktop ma bezwzględną ścieżkę (Exec nie rozwija ~), klasę okna
#       Super+A i przechodzi desktop-file-validate (jeśli jest),
#     - istniejący .desktop użytkownika nie jest nadpisywany,
#     - alias trafia do ~/.bashrc raz (drugi bieg nie pyta i nie dubluje),
#       „n” niczego nie zmienia, cudzy alias i powłoka inna niż bash = pominięcie,
#     - dopisany alias faktycznie uruchamia TUI w nowej powłoce basha.
#   Uruchom: bash tests/install-tui-entry.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval (zmienne żyją w eval)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── wycinek [8m] z install.sh ───────────────────────────────────────────────
S=$(grep -n '^# 8m\. ' "$REPO/install/install.sh" | cut -d: -f1)
E=$(grep -n '^SUMMARY_DONE+=("Machine-local configs generated' "$REPO/install/install.sh" | cut -d: -f1)
sed -n "${S},$((E-1))p" "$REPO/install/install.sh" > "$T/step8m.sh"
check "wycinek [8m] znaleziony"                 '[[ -n "$S" && -n "$E" && -s "$T/step8m.sh" ]]'

# run_step <home> <shell> <odpowiedź na pytanie> → stdout; SUMMARY_* do $T/summary
run_step() {
    HOME="$1" SHELL="$2" ARCHENEMY_DIR="$1/archenemy" \
    GREEN='' NC='' YELLOW='' RED='' \
    bash -c 'declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=(); source "$1"
             printf "DONE=%s\n" "${SUMMARY_DONE[@]}" > "$2"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}" >> "$2"' \
        _ "$T/step8m.sh" "$T/summary" <<<"$3" 2>&1
}

# atrapa repo: TUI = skrypt, który tylko się przedstawia
new_home() {
    local h="$T/$1"
    mkdir -p "$h/archenemy/scripts/appbinds"
    printf '#!/bin/bash\necho "TUI-OK $*"\n' > "$h/archenemy/scripts/appbinds/appbinds.sh"
    chmod +x "$h/archenemy/scripts/appbinds/appbinds.sh"
    printf '# bashrc użytkownika\nexport FOO=1\n' > "$h/.bashrc"
    echo "$h"
}

echo "── scenariusz 1: świeża maszyna, bash, odpowiedź Enter (domyślnie tak)"
H=$(new_home "a b")   # spacja w $HOME — cudzysłów w Exec musi ją utrzymać
D="$H/.local/share/applications/archenemy.desktop"
OUT=$(run_step "$H" /bin/bash "")
check ".desktop utworzony"                       '[[ -f "$D" ]]'
check "Exec z bezwzględną ścieżką w cudzysłowie" 'grep -qxF "Exec=alacritty --class archenemy-appbinds -e \"$H/archenemy/scripts/appbinds/appbinds.sh\"" "$D"'
check "Exec bez ~"                               '! grep -q "^Exec=.*~" "$D"'
if command -v desktop-file-validate >/dev/null 2>&1; then
    check "desktop-file-validate bez błędów"     'desktop-file-validate "$D" >/dev/null 2>&1'
fi
check "alias dopisany raz"                       '[[ $(grep -c "^alias archenemy=" "$H/.bashrc") -eq 1 ]]'
check "treść bashrc użytkownika nietknięta"      'grep -qx "export FOO=1" "$H/.bashrc"'
check "SUMMARY_DONE zgłasza alias"               'grep -q "^DONE=.archenemy. command added" "$T/summary"'
RUN=$(HOME="$H" bash -c 'shopt -s expand_aliases; source ~/.bashrc
archenemy x' 2>&1)
check "alias uruchamia TUI w nowym bashu"        '[[ "$RUN" == "TUI-OK x" ]]'

echo "── scenariusz 2: drugi bieg na tej samej maszynie"
cp "$H/.bashrc" "$T/bashrc.before"
OUT=$(run_step "$H" /bin/bash "y")
check "bashrc bez zmian (brak duplikatu)"        'cmp -s "$H/.bashrc" "$T/bashrc.before"'
check "drugi bieg nie pyta"                      '[[ "$OUT" != *"[Y/n]"* ]]'
check "komunikat: alias już jest"                '[[ "$OUT" == *"już jest"* ]]'

echo "── scenariusz 3: własny .desktop użytkownika + odpowiedź n"
H=$(new_home c3)
D="$H/.local/share/applications/archenemy.desktop"
mkdir -p "$(dirname "$D")"; echo "MÓJ" > "$D"
cp "$H/.bashrc" "$T/bashrc.before"
OUT=$(run_step "$H" /bin/bash "n")
check "własny .desktop nienadpisany"             '[[ "$(cat "$D")" == "MÓJ" ]]'
check "n → bashrc bez zmian"                     'cmp -s "$H/.bashrc" "$T/bashrc.before"'
check "n → wpis w SUMMARY_SKIPPED"               'grep -q "^SKIPPED=.archenemy. command (your choice)" "$T/summary"'

echo "── scenariusz 4: cudzy alias archenemy w bashrc"
H=$(new_home c4)
echo "alias archenemy='cd ~/archenemy'" >> "$H/.bashrc"
cp "$H/.bashrc" "$T/bashrc.before"
OUT=$(run_step "$H" /bin/bash "y")
check "cudzy alias zostaje, nic nie dopisane"    'cmp -s "$H/.bashrc" "$T/bashrc.before"'

echo "── scenariusz 5: powłoka zsh"
H=$(new_home c5)
cp "$H/.bashrc" "$T/bashrc.before"
OUT=$(run_step "$H" /usr/bin/zsh "y")
check "zsh → bashrc bez zmian"                   'cmp -s "$H/.bashrc" "$T/bashrc.before"'
check "zsh → podpowiedź w SUMMARY_SKIPPED"       'grep -q "^SKIPPED=.archenemy. command — not bash" "$T/summary"'
check "zsh → .desktop i tak powstaje"            '[[ -f "$H/.local/share/applications/archenemy.desktop" ]]'

echo "── scenariusz 6: brak ~/.bashrc"
H=$(new_home c6); rm "$H/.bashrc"
OUT=$(run_step "$H" /bin/bash "")
check "bashrc utworzony z aliasem"               'grep -q "^alias archenemy=" "$H/.bashrc"'

echo "── scenariusz 7: znak \$ w ścieżce → bez wpisu w rofi"
H=$(new_home 'c$7')
OUT=$(run_step "$H" /bin/bash "n")
check "brak .desktop przy \$ w ścieżce"          '[[ ! -e "$H/.local/share/applications/archenemy.desktop" ]]'
check "powód w SUMMARY_SKIPPED"                  'grep -q "^SKIPPED=archenemy.desktop" "$T/summary"'

echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
