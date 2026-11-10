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
#     - wszystko, co biblioteka zapisuje u użytkownika (i wspólna warstwa
#       config/shell), jest po angielsku: czysty $HOME bez polskich znaków
#       i słów; dawny polski znacznik aliasu jest rozpoznawany i podmieniany.
#   Uruchom: bash tests/shell-rc.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC1091,SC2016,SC2034,SC2088  # źródło z dynamicznego REPO; check() robi eval; ~ w opisach testów
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
check "w shellrc nowy znacznik, bez dawnego" '! grep -qxF "$ARCHENEMY_ALIAS_MARK_OLD" "$SHELLRC"'

echo "== dawny polski znacznik w shellrc (instalacje sprzed 2026-11-09)"
sed -i "s|^$ARCHENEMY_ALIAS_MARK\$|$ARCHENEMY_ALIAS_MARK_OLD|" "$SHELLRC"
cp "$SHELLRC" "$T/shellrc.oldmark"
check "dawny znacznik: stan ours"         '[[ "$(archenemy_alias_state "$B")" == ours ]]'
nsb() { find "$SHELL_RC_DIR" -maxdepth 1 -name "shellrc.bak-*" | wc -l; }
n0=$(nsb)
sbak="$(archenemy_alias_mark_refresh)"
check "odświeżenie: kopia = stara treść"  '[[ -f "$sbak" ]] && cmp -s "$sbak" "$T/shellrc.oldmark"'
check "odświeżenie: nowy znacznik raz"    '[[ $(grep -cxF "$ARCHENEMY_ALIAS_MARK" "$SHELLRC") -eq 1 ]] && ! grep -qxF "$ARCHENEMY_ALIAS_MARK_OLD" "$SHELLRC"'
check "odświeżenie: zmieniona tylko ta linia" '[[ "$(diff "$T/shellrc.oldmark" "$SHELLRC" | grep -c "^[<>]")" -eq 2 ]]'
check "odświeżenie drugi raz: no-op"      '[[ -z "$(archenemy_alias_mark_refresh)" && $(nsb) -eq $((n0 + 1)) ]]'
printf '\n%s\nalias archenemy=x\n' "$ARCHENEMY_ALIAS_MARK_OLD" > "$T/rc-old"
check "dawny znacznik w rc: legacy"       '[[ "$(SHELLRC=/nonexistent archenemy_alias_state "$T/rc-old")" == "legacy $T/rc-old" ]]'

echo "== blok wczytujący w ~/.bashrc"
n0=$(baks)
check "dopisany"                          '[[ "$(rc_block_ensure "$B" bash 2>/dev/null)" == added ]]'
check "kopia przy dopisaniu"              '[[ $(baks) -eq $((n0 + 1)) ]]'
check "drugi raz: ok"                     '[[ "$(rc_block_ensure "$B" bash 2>/dev/null)" == ok ]]'
check "bez nowej kopii przy ok"           '[[ $(baks) -eq $((n0 + 1)) ]]'
check "dokładnie jeden blok"              '[[ $(grep -cxF "$SHELL_BLOCK_BEGIN" "$B") -eq 1 ]]'
check "blok = wzorzec"                    '[[ "$(rc_block_current "$B")" == "$(rc_block_text bash)" ]]'
check "blok bash bez zsh-defaults"        '! grep -q zsh-defaults "$B"'
check "blok bash bez keys.zsh"             '! grep -q keys.zsh "$B"'
check "ścieżka w bloku raz, względem \$HOME" '[[ $(rc_block_current "$B" | grep -c "archenemy/config/shell") -eq 1 ]] && grep -qxF "archenemy_shell_dir=\"\$HOME/archenemy/config/shell\"" "$B"'
sed -i 's|^# Added by archenemy.*|# stara wersja bloku|' "$B"
check "zmieniony blok: updated"           '[[ "$(rc_block_ensure "$B" bash 2>/dev/null)" == updated ]]'
check "po updated nadal jeden blok"       '[[ $(grep -cxF "$SHELL_BLOCK_BEGIN" "$B") -eq 1 && "$(rc_block_current "$B")" == "$(rc_block_text bash)" ]]'
check "linie użytkownika nietknięte"      'grep -qx "alias TESTgs='"'"'git status'"'"'" "$B" && grep -qx "shopt -s autocd" "$B"'
check "~/.bashrc parsuje się"             'bash -n "$B"'

echo "== osobisty skrót ZLE"
check "generator Ctrl+X Ctrl+Y"             '[[ "$(shell_keys_text "^X^Y")" == "bindkey -M emacs '\''^X^Y'\'' vi-cmd-mode" ]]'
check "generator Alt+v"                     '[[ "$(shell_keys_text "\\ev")" == "bindkey -M emacs '\''\\ev'\'' vi-cmd-mode" ]]'
check "zapis osobistego skrótu"              '[[ "$(shell_keys_write "^X^Y")" == written && "$(<"$SHELL_KEYS")" == "bindkey -M emacs '\''^X^Y'\'' vi-cmd-mode" ]]'
check "keys.zsh kończy się nową linią"          '[[ "$(tail -c1 "$SHELL_KEYS" | od -An -t x1 | tr -d "[:space:]")" == 0a ]]'
check "drugi zapis: no-op"                   '[[ "$(shell_keys_write "^X^Y")" == unchanged ]]'
check "brak plików mktemp po zapisie"        '[[ -z "$(find "$SHELL_RC_DIR" -maxdepth 1 -name "keys.zsh.??????")" ]]'
n0="$(find "$SHELL_RC_DIR" -maxdepth 1 -name 'keys.zsh.bak-*' | wc -l)"
check "zapis zmienionej wartości robi backup" '[[ "$(shell_keys_write "^]")" == written && $(find "$SHELL_RC_DIR" -maxdepth 1 -name "keys.zsh.bak-*" | wc -l) -eq $((n0 + 1)) ]]'
check "reset usuwa wpis"                     '[[ "$(shell_keys_reset)" == reset && ! -e "$SHELL_KEYS" ]]'
check "reset drugi raz: no-op"               '[[ "$(shell_keys_reset)" == unchanged ]]'

Z_TEST="$H/.zshrc-block-test"
printf '# user zshrc\n' > "$Z_TEST"
check "blok zsh dodany"                      '[[ "$(rc_block_ensure "$Z_TEST" zsh 2>/dev/null)" == added ]]'
check "kolejność defaults, keys, shellrc"     'awk '\''/zsh-defaults.zsh/ { a=NR } /keys.zsh/ { b=NR } /shellrc"/ { c=NR } END { exit !(a && b && c && a < b && b < c) }'\'' "$Z_TEST"'
check "blok zsh = wzorzec"                   '[[ "$(rc_block_current "$Z_TEST")" == "$(rc_block_text zsh)" ]]'
sed -i 's|^# Added by archenemy.*|# stara wersja zsh bloku|' "$Z_TEST"
check "zmieniony blok zsh odświeżony"        '[[ "$(rc_block_ensure "$Z_TEST" zsh 2>/dev/null)" == updated && "$(rc_block_current "$Z_TEST")" == "$(rc_block_text zsh)" ]]'
check "odświeżony blok nadal pojedynczy"     '[[ $(grep -cxF "$SHELL_BLOCK_BEGIN" "$Z_TEST") -eq 1 ]]'

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
check "zshrc: zsh-defaults przed shellrc" '[[ $(grep -n zsh-defaults "$Z" | cut -d: -f1) -lt $(grep -n "/shellrc\"; fi" "$Z" | cut -d: -f1) ]]'
check "zshrc: drugi raz ok"               '[[ "$(rc_block_ensure "$Z" zsh)" == ok ]]'
if command -v zsh >/dev/null 2>&1; then
    OUT="$(HOME="$H" ZDOTDIR="$H" zsh -ic 'alias TESTll; echo "V=$TESTVAR"' 2>/dev/null)"
    check "zsh -i widzi alias i zmienną"  '[[ "$OUT" == *"TESTll="* && "$OUT" == *"V=1"* ]]'
    check "zsh-defaults parsuje się"      'zsh -n "$H/archenemy/config/shell/zsh-defaults.zsh"'
else
    echo "  – zsh nie jest zainstalowany: test zsh -i pominięty (live-only)"
fi

echo "== inna ścieżka aplikacji (przeprowadzka, decyzja 2026-11-09)"
# Jedna zmienna: blok i alias idą za ARCHENEMY_DIR, a ponowne wywołanie
# odświeża blok (updated), zamiast dopisać drugi.
H2="$T/home2"; A2="$H2/.local/share/archenemy"
mkdir -p "$A2/scripts/appbinds" "$A2/config/shell"
printf '#!/bin/bash\necho "TUI2 $*"\n' > "$A2/scripts/appbinds/appbinds.sh"; chmod +x "$A2/scripts/appbinds/appbinds.sh"
printf '[[ $- != *i* ]] && return\n' > "$H2/.bashrc"
OUT="$(HOME="$H2" ARCHENEMY_DIR="$A2" bash -c 'source "$1"; rc_block_ensure "$HOME/.bashrc" bash 2>/dev/null; archenemy_alias_add && echo alias-ok' _ "$REPO/scripts/shell/lib/shell-rc.sh")"
check "blok i alias dodane"               '[[ "$OUT" == *added*alias-ok* ]]'
check "blok: \$HOME/.local/share/…"       'grep -qxF "archenemy_shell_dir=\"\$HOME/.local/share/archenemy/config/shell\"" "$H2/.bashrc"'
check "alias: ~/.local/share/…"           'grep -qxF "alias archenemy='"'"'~/.local/share/archenemy/scripts/appbinds/appbinds.sh'"'"'" "$A2/config/shell/shellrc"'
RUN="$(HOME="$H2" bash -ic 'archenemy x' 2>/dev/null)"
check "bash -i: alias z nowej ścieżki"    '[[ "$RUN" == "TUI2 x" ]]'
# stary blok (~/archenemy) → po przeprowadzce jeden odświeżony blok
OUT="$(HOME="$H2" ARCHENEMY_DIR="$H2/archenemy" bash -c 'source "$1"; rc_block_ensure "$HOME/.bashrc" bash 2>/dev/null' _ "$REPO/scripts/shell/lib/shell-rc.sh")"
OUT="$(HOME="$H2" ARCHENEMY_DIR="$A2" bash -c 'source "$1"; rc_block_ensure "$HOME/.bashrc" bash 2>/dev/null' _ "$REPO/scripts/shell/lib/shell-rc.sh")"
check "przeprowadzka: updated, jeden blok" '[[ "$OUT" == updated && $(grep -cxF "$SHELL_BLOCK_BEGIN" "$H2/.bashrc") -eq 1 ]] && grep -q "share/archenemy/config/shell" "$H2/.bashrc"'
# poza $HOME i ze spacją: ścieżka bezwzględna w cudzysłowie
A3="$T/opt dir/archenemy"; mkdir -p "$A3/scripts/appbinds" "$A3/config/shell"
cp "$A2/scripts/appbinds/appbinds.sh" "$A3/scripts/appbinds/"
H3="$T/home3"; mkdir -p "$H3"
HOME="$H3" ARCHENEMY_DIR="$A3" bash -c 'source "$1"; rc_block_ensure "$HOME/.bashrc" bash >/dev/null 2>&1; archenemy_alias_add' _ "$REPO/scripts/shell/lib/shell-rc.sh"
RUN="$(HOME="$H3" bash -ic 'archenemy y' 2>/dev/null)"
check "poza \$HOME ze spacją: bash -i działa" '[[ "$RUN" == "TUI2 y" ]]'

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

echo "== kompletność: wszystko, co ląduje u użytkownika, po angielsku (właściciel 2026-11-09)"
# Czysty $HOME: każda ścieżka zapisu biblioteki (szablon, bloki created/added/
# updated, migracja z komentarzem, alias nowy i przeniesiony, odświeżenie
# dawnego znacznika, keys.zsh z kopią) plus wspólna warstwa z gita, która
# leży obok shellrc. Kopie .bak-* to poprzednia treść użytkownika — poza
# kontrolą. grep -F: dosłownie, niezależnie od locale i odmiany grepa.
H4="$T/home-en"; A4="$H4/archenemy"
mkdir -p "$A4/config/shell"
cp "$REPO/config/shell/zsh-defaults.zsh" "$REPO/config/shell/emacs-default-bindings.txt" "$A4/config/shell/"
printf '[[ $- != *i* ]] && return\nalias TESTen=1\n\n%s\nalias archenemy=x\n' "$ARCHENEMY_ALIAS_MARK_OLD" > "$H4/.bashrc"
printf '# own zshrc\n' > "$H4/.zshrc"
HOME="$H4" ARCHENEMY_DIR="$A4" bash -c '
    source "$1"
    shellrc_ensure
    archenemy_alias_move "$HOME/.bashrc"
    rc_block_ensure "$HOME/.bashrc" bash
    rc_migrate_apply "$HOME/.bashrc"
    rc_block_ensure "$HOME/.zshrc" zsh
    sed -i "s|^# Added by archenemy.*|# TEST old block|" "$HOME/.zshrc"; rc_block_ensure "$HOME/.zshrc" zsh
    rc_block_ensure "$HOME/.bashrc-new" bash
    rc_block_ensure "$HOME/.zshrc-new" zsh
    shell_keys_write "^X^Y"; shell_keys_write "^]"
    shell_plugin_write zsh-autosuggestions 1; shell_plugin_write zsh-syntax-highlighting 1; shell_plugin_write zsh-completions 1
    printf "%s\n" "$ARCHENEMY_ALIAS_MARK_OLD" >> "$SHELLRC"; archenemy_alias_mark_refresh
' _ "$REPO/scripts/shell/lib/shell-rc.sh" > "$T/en.log" 2>&1
check "wygenerowano shellrc, bloki i keys.zsh" '[[ -s "$A4/config/shell/shellrc" && -s "$A4/config/shell/keys.zsh" && -s "$H4/.bashrc-new" && -s "$H4/.zshrc-new" ]] && grep -qxF "$SHELL_BLOCK_BEGIN" "$H4/.zshrc" && grep -q "^# moved from" "$A4/config/shell/shellrc"'
find "$H4" -type f ! -name '*.bak-*' | sort > "$T/en.files"
PL_CHARS=(-e ą -e ć -e ę -e ł -e ń -e ó -e ś -e ź -e ż -e Ą -e Ć -e Ę -e Ł -e Ń -e Ó -e Ś -e Ź -e Ż -e '„' -e '”')
check "pliki użytkownika bez polskich znaków" '! xargs -d "\n" grep -nF "${PL_CHARS[@]}" < "$T/en.files"'
check "wspólna warstwa w gicie bez polskich znaków" '! grep -rnF "${PL_CHARS[@]}" "$REPO/config/shell"'
# Polskie słowa bez znaków diakrytycznych (np. dawny znacznik „jako komenda”).
check "pliki użytkownika bez polskich słów"  '! xargs -d "\n" grep -nwiE "jako|komenda|plik|pliku|nie|dla|oraz|albo|tylko|przed|kopia|alias dla|warstwa|historia|klawisze" < "$T/en.files"'
check "szablon shellrc bez polskich znaków"  '! shellrc_template | grep -F "${PL_CHARS[@]}"'

echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
