#!/bin/bash
# =============================================
#   archenemy - tests/shell-rc.sh
#   Biblioteka wspólnego pliku powłoki (scripts/shell/lib/shell-rc.sh) na
#   atrapie $HOME w mktemp. Sprawdzamy, że:
#     - plik użytkownika powstaje z szablonu raz i parsuje się w bashu,
#     - blok wczytujący w ~/.bashrc jest jeden po wielu biegach, zmiana bloku
#       podmienia go w miejscu, każda zmiana zostawia kopię .bak-<czas>,
#       symlink ~/.bashrc zostaje symlinkiem, blok bez końca nie jest ruszany,
#     - migracja przenosi tylko bezpieczne linie (alias/export/zmienne),
#       zostawia prompt, funkcje i bloki, nie dubluje i drugi raz nic nie robi,
#     - alias `archenemy` z dawnego kroku [8m] przechodzi do pliku wspólnego,
#       a ~/.bashrc wraca do treści sprzed tamtego kroku,
#     - prawdziwy `bash -i` widzi przeniesione aliasy,
#     - zsh, jeśli jest w systemie, też (bez zsh: pominięte i wypisane).
#   Uruchom: bash tests/shell-rc.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC2088  # check() robi eval; ~ w opisach testów
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

H="$T/home"
mkdir -p "$H/archenemy/config/shell" "$T/bin"
cp "$REPO/config/shell/zsh-defaults.zsh" "$H/archenemy/config/shell/"
export HOME="$H" ARCHENEMY_DIR="$H/archenemy"
# shellcheck source=../scripts/shell/lib/shell-rc.sh
source "$REPO/scripts/shell/lib/shell-rc.sh"
B="$H/.bashrc"
baks() { find "$H" -maxdepth 1 -name "${1:-.bashrc}.bak-*" | wc -l; }

# ~/.bashrc z Archa (skel) + rzeczy użytkownika, w tym takie, które MUSZĄ zostać.
cat > "$B" <<'EOF'
#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# TEST: moje skróty
alias TESTgs='git status'
alias TESTll="ls -la"
export PATH="$HOME/TESTbin:$PATH"
TESTVAR=1
HISTSIZE=5000
shopt -s autocd
TESTfn() {
alias TESTinner='echo nie'
}
if [ -d /opt ]; then
export TESTINIF=1
fi
export TESTMULTI="a
b"
source /usr/share/TEST/none.sh

# archenemy: TUI (Super+A) jako komenda
alias archenemy='~/archenemy/scripts/appbinds/appbinds.sh'
EOF
cp "$B" "$T/bashrc.orig"

echo "== plik użytkownika"
check "utworzony"                         '[[ "$(shellrc_ensure)" == created && -f "$SHELLRC" ]]'
check "drugi raz: exists"                 '[[ "$(shellrc_ensure)" == exists ]]'
check "szablon parsuje się w bashu"       'bash -n "$SHELLRC"'
check "szablon ma sekcje"                 'grep -qxF "$SHELLRC_BASH_MARK" "$SHELLRC" && grep -qxF "# --- zsh only ---" "$SHELLRC"'

echo "== alias archenemy z dawnego [8m]"
check "stan: legacy w ~/.bashrc"          '[[ "$(archenemy_alias_state "$B")" == "legacy $B" ]]'
bak="$(archenemy_alias_move "$B")"
check "kopia ~/.bashrc przed zmianą"      '[[ -f "$bak" ]] && cmp -s "$bak" "$T/bashrc.orig"'
check "znacznik raz w shellrc"            '[[ $(grep -cxF "$ARCHENEMY_ALIAS_MARK" "$SHELLRC") -eq 1 ]]'
check "alias w sekcji common"             'awk -v m="$SHELLRC_BASH_MARK" '"'"'$0 == m { exit 1 } /^alias archenemy=/ { f = 1 } END { exit !f }'"'"' "$SHELLRC"'
check "~/.bashrc bez znacznika i aliasu"  '! grep -q "archenemy" "$B"'
head -n -3 "$T/bashrc.orig" > "$T/bashrc.pre8m"
check "~/.bashrc = treść sprzed [8m]"     'cmp -s "$B" "$T/bashrc.pre8m"'
check "stan: ours"                        '[[ "$(archenemy_alias_state "$B")" == ours ]]'

echo "== blok wczytujący w ~/.bashrc"
n0=$(baks)
check "dopisany"                          '[[ "$(rc_block_ensure "$B" bash 2>/dev/null)" == added ]]'
check "kopia przy dopisaniu"              '[[ $(baks) -eq $((n0 + 1)) ]]'
check "drugi raz: ok"                     '[[ "$(rc_block_ensure "$B" bash 2>/dev/null)" == ok ]]'
check "bez nowej kopii przy ok"           '[[ $(baks) -eq $((n0 + 1)) ]]'
check "dokładnie jeden blok"              '[[ $(grep -cxF "$SHELL_BLOCK_BEGIN" "$B") -eq 1 ]]'
check "blok = wzorzec"                    '[[ "$(rc_block_current "$B")" == "$(rc_block_text bash)" ]]'
check "blok bash bez zsh-defaults"        '! grep -q zsh-defaults "$B"'
sed -i 's|^# Added by archenemy.*|# stara wersja bloku|' "$B"
check "zmieniony blok: updated"           '[[ "$(rc_block_ensure "$B" bash 2>/dev/null)" == updated ]]'
check "po updated nadal jeden blok"       '[[ $(grep -cxF "$SHELL_BLOCK_BEGIN" "$B") -eq 1 && "$(rc_block_current "$B")" == "$(rc_block_text bash)" ]]'
check "linie użytkownika nietknięte"      'grep -qx "alias TESTgs='"'"'git status'"'"'" "$B" && grep -qx "shopt -s autocd" "$B"'
check "~/.bashrc parsuje się"             'bash -n "$B"'

echo "== migracja linii użytkownika"
PREV="$(rc_migrate_preview "$B")"
check "alias ls/grep do przeniesienia"    'grep -qx "alias ls='"'"'ls --color=auto'"'"'" <<<"$PREV"'
check "komentarz nad aliasem idzie z nim" 'grep -qx "# TEST: moje skróty" <<<"$PREV"'
check "export PATH i zmienna"             'grep -qx "export PATH=\"\$HOME/TESTbin:\$PATH\"" <<<"$PREV" && grep -qx "TESTVAR=1" <<<"$PREV"'
check "PS1 i HISTSIZE zostają"            '! grep -q "^PS1=\|^HISTSIZE=" <<<"$PREV"'
check "shopt/source zostają"              '! grep -q "^shopt\|^source" <<<"$PREV"'
check "alias w funkcji zostaje"           '! grep -q TESTinner <<<"$PREV"'
check "export w if zostaje"               '! grep -q TESTINIF <<<"$PREV"'
check "wieloliniowy export zostaje"       '! grep -q TESTMULTI <<<"$PREV"'
check "blok archenemy nie jest ruszany"   '! grep -qF "archenemy/config/shell" <<<"$PREV"'
echo "alias TESTgs='git status'" >> "$SHELLRC.add"   # już jest w shellrc → bez duplikatu
shellrc_append_common "$SHELLRC.add" >/dev/null; rm -f "$SHELLRC.add"
n0=$(baks)
moved="$(rc_migrate_apply "$B")"
check "przeniesiono 7 linii"              '[[ "$moved" == 7 ]]'
check "kopia przed migracją"              '[[ $(baks) -eq $((n0 + 1)) ]]'
check "alias TESTgs raz w shellrc"        '[[ $(grep -cx "alias TESTgs='"'"'git status'"'"'" "$SHELLRC") -eq 1 ]]'
check "TESTll w shellrc, nie w bashrc"    'grep -q "^alias TESTll=" "$SHELLRC" && ! grep -q "^alias TESTll=" "$B"'
check "PS1 nadal w ~/.bashrc"             'grep -q "^PS1=" "$B"'
check "funkcja nadal w ~/.bashrc"         'grep -q "^TESTfn()" "$B" && grep -q TESTinner "$B"'
check "przeniesione przed sekcją bash"    'awk -v m="$SHELLRC_BASH_MARK" '"'"'$0 == m { exit 1 } /^alias TESTll=/ { f = 1 } END { exit !f }'"'"' "$SHELLRC"'
check "shellrc parsuje się w bashu"       'bash -n "$SHELLRC"'
cp "$B" "$T/b2"; cp "$SHELLRC" "$T/s2"
check "drugi raz: 0"                      '[[ "$(rc_migrate_apply "$B")" == 0 ]]'
check "drugi raz: pliki bez zmian"        'cmp -s "$B" "$T/b2" && cmp -s "$SHELLRC" "$T/s2"'
check "blok nadal jeden"                  '[[ $(grep -cxF "$SHELL_BLOCK_BEGIN" "$B") -eq 1 ]]'

echo "== prawdziwy bash -i"
OUT="$(HOME="$H" bash -ic 'alias TESTll; alias archenemy; echo "PATH=$PATH"; echo "V=$TESTVAR"' 2>/dev/null)"
check "alias TESTll widoczny"             '[[ "$OUT" == *"alias TESTll="* ]]'
check "alias archenemy widoczny"          '[[ "$OUT" == *"alias archenemy="* ]]'
check "PATH z shellrc"                    '[[ "$OUT" == *"$H/TESTbin:"* ]]'
check "zmienna z shellrc"                 '[[ "$OUT" == *"V=1"* ]]'

echo "== ~/.zshrc"
Z="$H/.zshrc"
check "brak pliku: created"               '[[ "$(rc_block_ensure "$Z" zsh)" == created ]]'
check "zshrc: zsh-defaults przed shellrc" '[[ $(grep -n zsh-defaults "$Z" | cut -d: -f1) -lt $(grep -n "shell/shellrc\"; fi" "$Z" | cut -d: -f1) ]]'
check "zshrc: drugi raz ok"               '[[ "$(rc_block_ensure "$Z" zsh)" == ok ]]'
if command -v zsh >/dev/null 2>&1; then
    OUT="$(HOME="$H" ZDOTDIR="$H" zsh -ic 'alias TESTll; echo "V=$TESTVAR"' 2>/dev/null)"
    check "zsh -i widzi alias i zmienną"  '[[ "$OUT" == *"TESTll="* && "$OUT" == *"V=1"* ]]'
    check "zsh-defaults parsuje się"      'zsh -n "$H/archenemy/config/shell/zsh-defaults.zsh"'
else
    echo "  – zsh nie jest zainstalowany: test zsh -i pominięty (live-only)"
fi

echo "== brzegi"
L="$T/dotfiles/bashrc"; mkdir -p "$T/dotfiles"; printf 'alias TESTx=1\n' > "$L"
ln -s "$L" "$H/.bashrc-link"
rc_block_ensure "$H/.bashrc-link" bash >/dev/null 2>&1
check "symlink zostaje symlinkiem"        '[[ -L "$H/.bashrc-link" ]] && grep -qxF "$SHELL_BLOCK_BEGIN" "$L"'
printf '%s\nalias TESTy=1\n' "$SHELL_BLOCK_BEGIN" > "$H/.broken"; cp "$H/.broken" "$T/broken"
check "blok bez końca: broken"            '[[ "$(rc_block_ensure "$H/.broken" bash 2>/dev/null)" == broken ]]'
check "blok bez końca: plik nietknięty"   'cmp -s "$H/.broken" "$T/broken"'
printf 'alias archenemy=echo\n' > "$H/.own"
rm -f "$SHELLRC"; shellrc_ensure >/dev/null
check "cudzy alias: own"                  '[[ "$(archenemy_alias_state "$H/.own")" == own ]]'
check "brak aliasu: none"                 '[[ "$(archenemy_alias_state "$T/b2-none")" == none ]]'
echo 'if then' >> "$SHELLRC"
check "błąd składni wykryty"              '! shellrc_check >/dev/null'
check "błąd z prefiksem powłoki"          '[[ "$(shellrc_check)" == bash:* ]]'
printf '/bin/sh\n/usr/bin/bash\n/usr/bin/TESTnone\n' > "$T/shells"
check "ścieżka z /etc/shells"             '[[ "$(ARCHENEMY_SHELLS_FILE="$T/shells" shell_path_for bash)" == /usr/bin/bash ]]'
check "brak w /etc/shells → kod 1"        '! ARCHENEMY_SHELLS_FILE="$T/shells" shell_path_for TESTnone >/dev/null'
printf '#!/bin/bash\necho "x:x:1:1::/home/x:/usr/bin/zsh"\n' > "$T/bin/getent"; chmod +x "$T/bin/getent"
check "login_shell z passwd"              '[[ "$(PATH="$T/bin:$PATH" login_shell)" == zsh ]]'

echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
