#!/bin/bash
# =============================================
#   archenemy - tests/install-tui-entry.sh
#   Test kroku [8m] install.sh: wpis „archenemy” w rofi (.desktop), wspólny
#   plik powłoki z blokiem w ~/.bashrc i alias `archenemy` w pliku wspólnym —
#   na atrapie $HOME w mktemp. Wycinek [8m] jest
#   wycinany z install/install.sh sedem (jak [9] w tests/install-link.sh).
#   Sprawdzamy, że:
#     - .desktop ma bezwzględną ścieżkę (Exec nie rozwija ~), klasę okna
#       Super+A i przechodzi desktop-file-validate (jeśli jest),
#     - istniejący .desktop użytkownika nie jest nadpisywany,
#     - ~/.bashrc dostaje blok wczytujący config/shell/shellrc po cichu (bez
#       pytania), z kopią .bak-<czas>; drugi bieg niczego nie zmienia,
#     - alias trafia do pliku wspólnego raz (drugi bieg nie pyta i nie dubluje),
#       „n” go nie dopisuje, cudzy alias wygrywa, przy zsh też się dopisuje,
#     - alias dopisany dawniej do ~/.bashrc przechodzi do pliku wspólnego bez
#       pytania, a ~/.bashrc wraca do treści sprzed tamtego kroku (+ blok),
#     - dopisany alias faktycznie uruchamia TUI w nowej powłoce basha.
#   Uruchom: bash tests/install-tui-entry.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC2088  # check() robi eval (zmienne żyją w eval); ~ w opisach
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
    mkdir -p "$h/archenemy/scripts/appbinds" "$h/archenemy/scripts/shell/lib"
    cp "$REPO/scripts/shell/lib/shell-rc.sh" "$h/archenemy/scripts/shell/lib/"
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
R="$H/archenemy/config/shell/shellrc"
check "plik wspólny utworzony"                   '[[ -f "$R" ]] && bash -n "$R"'
check "alias dopisany raz do pliku wspólnego"    '[[ $(grep -c "^alias archenemy=" "$R") -eq 1 ]]'
check "alias nie w ~/.bashrc"                    '! grep -q "^alias archenemy=" "$H/.bashrc"'
check "~/.bashrc ma jeden blok wczytujący"       '[[ $(grep -cxF "# >>> archenemy shell >>>" "$H/.bashrc") -eq 1 ]]'
check "kopia ~/.bashrc przed zmianą"             '[[ -n "$(find "$H" -maxdepth 1 -name ".bashrc.bak-*")" ]]'
check "treść bashrc użytkownika nietknięta"      'grep -qx "export FOO=1" "$H/.bashrc"'
check "[8m] pyta tylko o alias (jedno read)"    '[[ $(grep -c "read -rp" "$T/step8m.sh") -eq 1 ]]'
check "SUMMARY_DONE zgłasza alias"               'grep -q "^DONE=.archenemy. command added" "$T/summary"'
check "export FOO do przeniesienia w [h]"        'grep -q "^SKIPPED=1 line(s) of your ~/.bashrc" "$T/summary"'
RUN=$(HOME="$H" bash -c 'shopt -s expand_aliases; source ~/.bashrc
archenemy x' 2>&1)
check "alias uruchamia TUI w nowym bashu"        '[[ "$RUN" == "TUI-OK x" ]]'

echo "── scenariusz 2: drugi bieg na tej samej maszynie"
cp "$H/.bashrc" "$T/bashrc.before"; cp "$R" "$T/shellrc.before"
nbak=$(find "$H" -maxdepth 1 -name ".bashrc.bak-*" | wc -l)
OUT=$(run_step "$H" /bin/bash "y")
check "bashrc bez zmian (brak duplikatu)"        'cmp -s "$H/.bashrc" "$T/bashrc.before"'
check "plik wspólny bez zmian"                   'cmp -s "$R" "$T/shellrc.before"'
check "bez nowej kopii"                          '[[ $(find "$H" -maxdepth 1 -name ".bashrc.bak-*" | wc -l) -eq $nbak ]]'
check "drugi bieg nie pyta"                      '[[ "$OUT" != *"[Y/n]"* ]]'
check "komunikat: alias już jest"                '[[ "$OUT" == *"już jest"* ]]'

echo "── scenariusz 3: własny .desktop użytkownika + odpowiedź n"
H=$(new_home c3)
D="$H/.local/share/applications/archenemy.desktop"
mkdir -p "$(dirname "$D")"; echo "MÓJ" > "$D"
OUT=$(run_step "$H" /bin/bash "n")
check "własny .desktop nienadpisany"             '[[ "$(cat "$D")" == "MÓJ" ]]'
check "n → brak aliasu"                          '! grep -q "archenemy=" "$H/.bashrc" "$H/archenemy/config/shell/shellrc"'
check "n → wpis w SUMMARY_SKIPPED"               'grep -q "^SKIPPED=.archenemy. command (your choice)" "$T/summary"'

echo "── scenariusz 4: cudzy alias archenemy w bashrc"
H=$(new_home c4)
echo "alias archenemy='cd ~/archenemy'" >> "$H/.bashrc"
cp "$H/.bashrc" "$T/bashrc.before"
OUT=$(run_step "$H" /bin/bash "y")
check "cudzy alias zostaje"                      'grep -qx "alias archenemy='"'"'cd ~/archenemy'"'"'" "$H/.bashrc"'
check "nic nie dopisane do pliku wspólnego"      '! grep -q "archenemy=" "$H/archenemy/config/shell/shellrc"'
check "drugi bieg z cudzym aliasem bez zmian"    'cp "$H/.bashrc" "$T/b4"; run_step "$H" /bin/bash "y" >/dev/null; cmp -s "$H/.bashrc" "$T/b4"'

echo "── scenariusz 5: powłoka zsh"
H=$(new_home c5)
OUT=$(run_step "$H" /usr/bin/zsh "y")
check "zsh → alias w pliku wspólnym"             'grep -q "^alias archenemy=" "$H/archenemy/config/shell/shellrc"'
check "zsh → ~/.zshrc nie tworzony po cichu"     '[[ ! -e "$H/.zshrc" ]]'
check "zsh → podpowiedź Super+A → [h]"           'grep -q "^SKIPPED=Your ~/.zshrc does not load" "$T/summary"'
check "zsh → .desktop i tak powstaje"            '[[ -f "$H/.local/share/applications/archenemy.desktop" ]]'

echo "── scenariusz 6: brak ~/.bashrc"
H=$(new_home c6); rm "$H/.bashrc"
OUT=$(run_step "$H" /bin/bash "")
check "bashrc utworzony z blokiem"               'grep -qxF "# >>> archenemy shell >>>" "$H/.bashrc"'
RUN=$(HOME="$H" bash -ic 'archenemy y' 2>/dev/null)
check "bash -i: alias z pliku wspólnego"         '[[ "$RUN" == "TUI-OK y" ]]'

echo "── scenariusz 7: znak \$ w ścieżce → bez wpisu w rofi"
H=$(new_home 'c$7')
OUT=$(run_step "$H" /bin/bash "n")
check "brak .desktop przy \$ w ścieżce"          '[[ ! -e "$H/.local/share/applications/archenemy.desktop" ]]'
check "powód w SUMMARY_SKIPPED"                  'grep -q "^SKIPPED=archenemy.desktop" "$T/summary"'

echo "── scenariusz 8: alias z dawnego [8m] w ~/.bashrc"
H=$(new_home c8)
cp "$H/.bashrc" "$T/bashrc.pre"
printf '\n# archenemy: TUI (Super+A) jako komenda\nalias archenemy='"'"'~/archenemy/scripts/appbinds/appbinds.sh'"'"'\n' >> "$H/.bashrc"
OUT=$(run_step "$H" /bin/bash "")
check "bez pytania"                              '[[ "$OUT" != *"[Y/n]"* ]]'
check "alias w pliku wspólnym raz"               '[[ $(grep -c "^alias archenemy=" "$H/archenemy/config/shell/shellrc") -eq 1 ]]'
sed '/^# >>> archenemy shell >>>$/,/^# <<< archenemy shell <<<$/d' "$H/.bashrc" | sed '$d' > "$T/bashrc.noblock"
check "~/.bashrc = sprzed [8m] + blok"           'cmp -s "$T/bashrc.noblock" "$T/bashrc.pre"'
RUN=$(HOME="$H" bash -c 'shopt -s expand_aliases; source ~/.bashrc
archenemy z' 2>&1)
check "alias działa po przeniesieniu"            '[[ "$RUN" == "TUI-OK z" ]]'
cp "$H/.bashrc" "$T/b8"; run_step "$H" /bin/bash "" >/dev/null
check "drugi bieg bez zmian"                     'cmp -s "$H/.bashrc" "$T/b8"'

echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
