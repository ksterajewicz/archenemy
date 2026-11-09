#!/bin/bash
# =============================================
#   archenemy - tests/shell-settings.sh
#   Super+A → [h] (scripts/shell/shell-settings.sh) sterowane z wejścia
#   standardowego, na atrapie $HOME i atrapach getent/chsh/sudo/pacman/nvim
#   (passwd w pliku). Bez roota, zapis tylko w mktemp; prawdziwy chsh nigdy.
#   Sprawdzamy, że:
#     - zmiana na zsh doinstalowuje pakiet tylko po „y”, tworzy ~/.zshrc
#       z blokiem, przenosi linie z ~/.bashrc za zgodą, a powłokę logowania
#       zmienia chsh dopiero po zgodzie; sukces = odczyt passwd,
#     - komunikat mówi, jak wrócić, i powrót do basha działa bez duplikatów,
#     - edycja w nvim: zapis bez błędu → wskazówka przeładowania; błąd
#       składni → ostrzeżenie i wybór przywróć/zostaw,
#     - menu główne Super+A ma pozycję [h] z powłoką w stanie.
#   Uruchom: bash tests/shell-settings.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC2088,SC2059  # check() robi eval; ~ w opisach; printf z wejściem testu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

H="$T/home"; A="$H/archenemy"; BIN="$T/bin"
mkdir -p "$A/config/shell" "$A/scripts" "$BIN"
mkdir -p "$A/scripts/hypr"; cp -r "$REPO/scripts/shell" "$REPO/scripts/appbinds" "$A/scripts/"; cp -r "$REPO/scripts/hypr/lib" "$A/scripts/hypr/"
cp "$REPO/config/shell/zsh-defaults.zsh" "$A/config/shell/"
S="$A/scripts/shell/shell-settings.sh"

# passwd w pliku: getent czyta, chsh zapisuje (chyba że $T/chsh-fail).
echo "/usr/bin/bash" > "$T/passwd"
cat > "$BIN/getent" <<EOF
#!/bin/bash
echo "x:x:1000:1000::$H:\$(cat "$T/passwd")"
EOF
cat > "$BIN/chsh" <<EOF
#!/bin/bash
echo "chsh \$*" >> "$T/log"
[[ -f "$T/chsh-fail" ]] && exit 1
[[ "\$1" == -s ]] && echo "\$2" > "$T/passwd"
EOF
cat > "$BIN/sudo" <<'EOF'
#!/bin/bash
"$@"
EOF
# pacman „instaluje” zsh: atrapa, która przekazuje wszystko do basha (dla -n i -i).
cat > "$BIN/pacman" <<EOF
#!/bin/bash
echo "pacman \$*" >> "$T/log"
[[ -f "$T/pacman-fail" ]] && exit 1
printf '#!/bin/bash\nexec bash "\$@"\n' > "$T/zbin/zsh"; chmod +x "$T/zbin/zsh"
EOF
# nvim: wykonuje akcję z pliku (np. dopisuje linię), żeby udawać edycję.
cat > "$BIN/nvim" <<EOF
#!/bin/bash
echo "nvim \$*" >> "$T/log"
[[ -f "$T/nvim-action" ]] && bash "$T/nvim-action" "\$1"
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$BIN/clear"
mkdir -p "$T/zbin"
chmod +x "$BIN"/*
printf '/bin/sh\n/usr/bin/bash\n%s\n' "$T/zbin/zsh" > "$T/shells"
# PATH bez /usr/bin/zsh z systemu: „zsh nie jest zainstalowany”, dopóki pacman go nie zrobi.
SYS_PATH=""
for d in /usr/local/bin /usr/bin /bin; do [[ -x "$d/zsh" ]] || SYS_PATH+="$d:"; done
export HOME="$H" SHELL=/usr/bin/bash ARCHENEMY_SHELLS_FILE="$T/shells" PATH="$BIN:$T/zbin:${SYS_PATH%:}"
if command -v zsh >/dev/null 2>&1; then echo "  – zsh w systemie, scenariusz instalacji nieodtwarzalny"; fi

run() { local input="$1"; shift; printf "$input" | timeout 10 bash "$S" "$@" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
code() { local input="$1"; shift; printf "$input" | timeout 10 bash "$S" "$@" >/dev/null 2>&1; }

cat > "$H/.bashrc" <<'EOF'
[[ $- != *i* ]] && return
alias ls='ls --color=auto'
PS1='[\u@\h \W]\$ '
alias TESTgs='git status'

# archenemy: TUI (Super+A) jako komenda
alias archenemy='~/archenemy/scripts/appbinds/appbinds.sh'
EOF

echo "== stan"
check "summary: bash"                     '[[ "$(bash "$S" summary)" == bash ]]'
B="$(bash "$S" brief)"
check "brief: plik nie wczytywany"        '[[ "$B" == *"~/.bashrc    does not load the shared file"* ]]'
check "brief: zsh nie zainstalowany"      '[[ "$B" == *"zsh          not installed"* ]]'

echo "== switch zsh, odmowa instalacji"
: > "$T/log"
check "kod 0"                             'code "n" switch zsh'
check "pacman nie wołany"                 '! grep -q pacman "$T/log"'
check "~/.zshrc nie powstał"              '[[ ! -e "$H/.zshrc" ]]'
check "passwd bez zmian"                  '[[ "$(<"$T/passwd")" == /usr/bin/bash ]]'

echo "== switch zsh, pacman zawodzi"
touch "$T/pacman-fail"
check "kod 1"                             '! code "y" switch zsh'
rm -f "$T/pacman-fail"

echo "== switch zsh: instalacja, migracja, chsh"
: > "$T/log"
OUT="$(run "yyy" switch zsh)"
check "pacman -S --needed zsh"            'grep -qx "pacman -S --needed zsh" "$T/log"'
check "~/.zshrc z blokiem"                'grep -qxF "# >>> archenemy shell >>>" "$H/.zshrc"'
check "~/.zshrc wczytuje zsh-defaults"    'grep -q "zsh-defaults.zsh" "$H/.zshrc"'
check "~/.bashrc z blokiem"               'grep -qxF "# >>> archenemy shell >>>" "$H/.bashrc"'
check "alias archenemy w shellrc"         'grep -q "^alias archenemy=" "$A/config/shell/shellrc"'
check "pokazał linie do przeniesienia"    '[[ "$OUT" == *"alias TESTgs="* ]]'
check "TESTgs przeniesiony"               'grep -q "^alias TESTgs=" "$A/config/shell/shellrc" && ! grep -q "^alias TESTgs=" "$H/.bashrc"'
check "PS1 został w ~/.bashrc"            'grep -q "^PS1=" "$H/.bashrc"'
check "chsh -s ścieżka z /etc/shells"     'grep -qx "chsh -s $T/zbin/zsh" "$T/log"'
check "passwd: zsh"                       '[[ "$(<"$T/passwd")" == "$T/zbin/zsh" ]]'
check "komunikat sukcesu"                 '[[ "$OUT" == *"Login shell: zsh"* ]]'
check "jak wrócić"                        '[[ "$OUT" == *"Back to bash"* && "$OUT" == *"chsh -s /usr/bin/bash"* ]]'
check "kopie zapasowe ~/.bashrc"          '[[ -n "$(find "$H" -maxdepth 1 -name ".bashrc.bak-*")" ]]'
check "summary: zsh, relog"               '[[ "$(bash "$S" summary)" == "zsh, log in again" ]]'
check "summary po relogu: zsh"            '[[ "$(SHELL=$T/zbin/zsh bash "$S" summary)" == zsh ]]'
OUT2="$(HOME="$H" bash -ic "alias TESTgs" 2>/dev/null)"
check "bash -i nadal ma TESTgs"           '[[ "$OUT2" == *"git status"* ]]'

echo "== switch zsh drugi raz"
cp "$H/.bashrc" "$T/b1"; cp "$H/.zshrc" "$T/z1"; cp "$A/config/shell/shellrc" "$T/s1"
OUT="$(run "" switch zsh)"
check "już jest powłoką logowania"        '[[ "$OUT" == *"already your login shell"* ]]'
check "pliki bez zmian"                   'cmp -s "$H/.bashrc" "$T/b1" && cmp -s "$H/.zshrc" "$T/z1" && cmp -s "$A/config/shell/shellrc" "$T/s1"'

echo "== switch bash: odmowa chsh, potem zgoda"
: > "$T/log"
check "odmowa: kod 0"                     'code "n" switch bash'
check "odmowa: chsh nie wołany"           '! grep -q chsh "$T/log"'
OUT="$(run "y" switch bash)"
check "passwd: bash"                      '[[ "$(<"$T/passwd")" == /usr/bin/bash ]]'
check "jak wrócić do zsh"                 '[[ "$OUT" == *"Back to zsh"* ]]'
check "pliki rc i shellrc bez zmian"      'cmp -s "$H/.bashrc" "$T/b1" && cmp -s "$H/.zshrc" "$T/z1" && cmp -s "$A/config/shell/shellrc" "$T/s1"'

echo "== chsh zawodzi"
touch "$T/chsh-fail"
check "kod 1"                             '! code "y" switch zsh'
check "passwd bez zmian"                  '[[ "$(<"$T/passwd")" == /usr/bin/bash ]]'
check "komunikat o błędzie"               '[[ "$(run "y" switch zsh)" == *"chsh did not change it"* ]]'
rm -f "$T/chsh-fail"

echo "== edycja w nvim"
rm -f "$T/nvim-action"
check "bez zmian: komunikat"              '[[ "$(run "" edit)" == *"No changes."* ]]'
echo 'echo "alias TESTnew='"'"'echo nowy'"'"'" >> "$1"' > "$T/nvim-action"
OUT="$(run "" edit)"
check "zapis: brak błędów składni"        '[[ "$OUT" == *"no syntax errors"* ]]'
check "wskazówka exec \$SHELL"            '[[ "$OUT" == *'"'"'exec $SHELL'"'"'* ]]'
OUT2="$(HOME="$H" bash -ic "alias TESTnew" 2>/dev/null)"
check "bash -i widzi nowy alias"          '[[ "$OUT2" == *"echo nowy"* ]]'
cp "$A/config/shell/shellrc" "$T/s2"
echo 'echo "if then" >> "$1"' > "$T/nvim-action"
OUT="$(run "r" edit)"
check "błąd składni: ostrzeżenie"         '[[ "$OUT" == *"Syntax error"* && "$OUT" == *"bash: "* ]]'
check "r: przywrócone sprzed edycji"      'cmp -s "$A/config/shell/shellrc" "$T/s2"'
check "k: kod 1, błąd zostaje"            '! code "k" edit && grep -qx "if then" "$A/config/shell/shellrc"'
cp "$T/s2" "$A/config/shell/shellrc"; rm -f "$T/nvim-action"

echo "== migrate"
printf "alias TESTlater='true'\n" >> "$H/.bashrc"
check "n: nic nie przeniesione"           'code "n" migrate && grep -q "^alias TESTlater=" "$H/.bashrc"'
check "y: przeniesione"                   'code "y" migrate && grep -q "^alias TESTlater=" "$A/config/shell/shellrc" && ! grep -q "^alias TESTlater=" "$H/.bashrc"'
check "nic do przeniesienia"              '[[ "$(run "" migrate)" == *"Nothing to move"* ]]'

echo "== menu"
OUT="$(run "\e")"
check "menu: stan i pozycje"              '[[ "$OUT" == *"Login shell"* && "$OUT" == *"switch to zsh"* && "$OUT" == *"neovim"* ]]'
check "zły argument: kod 1"               '! bash "$S" nonsense >/dev/null 2>&1'

echo "== menu główne Super+A"
OUT="$(printf 'q' | ARCHENEMY_TUI_SIZE="40 120" timeout 10 bash "$A/scripts/appbinds/appbinds.sh" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')"
check "pozycja [h] shell"                 'grep -qE "h  shell +bash" <<<"$OUT"'
OUT="$(printf 'h\e' | ARCHENEMY_TUI_SIZE="40 120" timeout 10 bash "$A/scripts/appbinds/appbinds.sh" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')"
check "h otwiera menu powłoki"            '[[ "$OUT" == *"switch to zsh"* ]]'

echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
