#!/usr/bin/env bash
# =============================================
#   archenemy - tests/zsh-rice-look.sh
#   Wygląd zsh idzie za rice'em (decyzja właściciela 2026-11-09l: „wygląd
#   zsh musi się również zmieniać w zależności od tego jaki rice jest
#   załadowany, więc nie może być to czysty starship”).
#   Łańcuch: blok „archenemy shell” w ~/.zshrc (rc_block_text zsh) →
#   config/shell/zsh-defaults.zsh → config/shell/rice-look.zsh →
#   ~/.config/zsh/colors.zsh (dowiązanie z Super+T do rices/<rice>/zsh).
#   Na atrapie $HOME (prawdziwy lib/switch-rice.sh w trybie „tylko linki”,
#   ~/archenemy jako dowiązanie do ~/.local/share/archenemy) sprawdzamy:
#     - blok zsh wczytuje zsh-defaults.zsh, a ten rice-look.zsh po ustawieniu
#       domyślnego promptu;
#     - po przełączeniu na rice X wczytany jest colors.zsh rice'a X (style
#       podświetlania), prompt bez Starshipa jest w kolorach X, po zmianie
#       na Y — kolory Y; każdy rice spoza bety ma ARCHENEMY_PROMPT_*;
#     - Starship (atrapa w PATH): STARSHIP_CONFIG = ~/.config/zsh/starship.toml
#       i start Starshipa przy domyślnym prompcie; bez Starshipa zmienna nie
#       powstaje; własny ~/.config/starship.toml albo inny STARSHIP_CONFIG
#       zostaje; już uruchomiony Starship nie startuje drugi raz;
#       ARCHENEMY_ZSH_STARSHIP=0 wyłącza start;
#     - własny prompt użytkownika zostaje; brak ~/.config/zsh, własny katalog
#       ~/.config/zsh (np. ZDOTDIR) albo obce dowiązanie: nic nie jest
#       wczytywane, zero błędów, zero śmieci w zmiennych.
#   Prawdziwego zsh i starshipa nie ma na serwerze: rice-look.zsh jest pisany
#   we wspólnym podzbiorze zsh i basha, więc wykonujemy go bashem; zsh -n
#   i zsh -i tylko, gdy zsh jest w systemie (inaczej pominięte i wypisane).
#   Uruchom: bash tests/zsh-rice-look.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC1091,SC2016,SC2034  # źródło z dynamicznego REPO; check() robi eval
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  – $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ── atrapa: ~/archenemy → ~/.local/share/archenemy (adres z decyzji 2026-11-09)
H="$T/home"
A="$H/.local/share/archenemy"
mkdir -p "$A/scripts/changing-theme-scripts" "$A/config/shell" "$H/.config" "$T/bin" "$T/run"
chmod 700 "$T/run"
ln -s .local/share/archenemy "$H/archenemy"
ln -s "$REPO/rices" "$A/rices"
ln -s "$REPO/scripts/lib" "$A/scripts/lib"
ln -s "$REPO/scripts/changing-theme-scripts/lib" "$A/scripts/changing-theme-scripts/lib"
cp "$REPO/config/shell/zsh-defaults.zsh" "$REPO/config/shell/rice-look.zsh" "$A/config/shell/"
LOOK="$A/config/shell/rice-look.zsh"

# Atrapa starshipa: `starship init zsh` definiuje funkcję jak prawdziwy
# skrypt startowy (prompt_starship_precmd) i ustawia rozpoznawalny PROMPT.
STAR="$T/star-bin"; mkdir -p "$STAR"
cat > "$STAR/starship" <<EOF
#!/usr/bin/env bash
echo "starship \$*" >> "$T/starship.log"
[[ "\$1 \$2" == "init zsh" ]] && printf '%s\n' 'prompt_starship_precmd() { :; }' 'PROMPT=TEST_STARSHIP_PROMPT'
exit 0
EOF
chmod +x "$STAR/starship"
# PATH atrapy: tylko narzędzia, których potrzebuje rice-look.zsh — prawdziwy
# starship na laptopie nie może wejść do scenariuszy „bez Starshipa”.
for tool in readlink tr bash; do ln -s "$(command -v "$tool")" "$T/bin/$tool"; done
BASH_BIN="$(command -v bash)"
BASE_PATH="$T/bin"

switch() {
    HOME="$H" XDG_RUNTIME_DIR="$T/run" RICE_NAME="$1" SWITCH_RICE_LINK_ONLY=1 \
        bash "$H/archenemy/scripts/changing-theme-scripts/lib/switch-rice.sh" >/dev/null 2>"$T/switch.err"
}

# look [ZMIENNA=wartość …] — wczytuje rice-look.zsh tak, jak robi to blok
# (archenemy_shell_dir względem $HOME), i wypisuje stan po nim. START_PROMPT
# = PROMPT przed wczytaniem (domyślnie ten z zsh-defaults.zsh), PRE = kod
# wykonany wcześniej (np. Starship uruchomiony w ~/.zshrc użytkownika).
look() {
    : > "$T/starship.log"
    env -i HOME="$H" PATH="$BASE_PATH" LC_ALL=C.UTF-8 START_PROMPT='[%n@%m %1~]%# ' "$@" "$BASH_BIN" -c '
        eval "${PRE-}"
        PROMPT="$START_PROMPT"
        archenemy_shell_dir="$HOME/archenemy/config/shell"
        . "$archenemy_shell_dir/rice-look.zsh"
        unset archenemy_shell_dir
        printf "PROMPT=%s\n" "$PROMPT"
        printf "STARSHIP_CONFIG=%s\n" "${STARSHIP_CONFIG-<unset>}"
        printf "STYLE=%s\n" "${ZSH_HIGHLIGHT_STYLES[default]-<unset>}"
        printf "SUGGEST=%s\n" "${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE-<unset>}"
        printf "LEFT=%s\n" "$(compgen -v archenemy_ | tr "\n" " ")"' 2>"$T/look.err"
}
val() { sed -n "s/^$1=//p" <<<"$OUT"; }
rice_var() { sed -n "s/^$2='\\(.*\\)'\$/\\1/p" "$REPO/rices/$1/zsh/colors.zsh"; }
rice_style() { sed -n "s/^ZSH_HIGHLIGHT_STYLES\\[default\\]='\\(.*\\)'\$/\\1/p" "$REPO/rices/$1/zsh/colors.zsh"; }
colored_prompt() {
    local t p o e
    t="$(rice_var "$1" ARCHENEMY_PROMPT_TEXT)"; p="$(rice_var "$1" ARCHENEMY_PROMPT_PATH)"
    o="$(rice_var "$1" ARCHENEMY_PROMPT_OK)"; e="$(rice_var "$1" ARCHENEMY_PROMPT_ERROR)"
    printf '%s' "%F{$t}[%n@%m %F{$p}%1~%F{$t}]%(?.%F{$o}.%F{$e})%#%f "
}
OWN="$H/.config/zsh/starship.toml"

echo "== łańcuch: blok zsh → zsh-defaults.zsh → rice-look.zsh"
(
    export HOME="$H" ARCHENEMY_DIR="$H/archenemy"
    # shellcheck source=../scripts/shell/lib/shell-rc.sh
    source "$REPO/scripts/shell/lib/shell-rc.sh"
    rc_block_text zsh
) > "$T/block"
check "blok zsh wczytuje zsh-defaults.zsh" 'grep -qF "/zsh-defaults.zsh\"; fi" "$T/block"'
check "zsh-defaults wczytuje rice-look.zsh po domyślnym prompcie" \
    'awk '\''/PROMPT=.\[%n@%m %1~\]%# / { a=NR } /source .*rice-look\.zsh/ { b=NR } END { exit !(a && b && a < b) }'\'' "$REPO/config/shell/zsh-defaults.zsh"'
check "rice-look.zsh parsuje się w bashu" 'bash -n "$REPO/config/shell/rice-look.zsh"'
if command -v zsh >/dev/null 2>&1; then
    check "rice-look.zsh i zsh-defaults.zsh parsują się w zsh" 'zsh -n "$REPO/config/shell/rice-look.zsh" && zsh -n "$REPO/config/shell/zsh-defaults.zsh"'
else
    skip "zsh nie jest zainstalowany: zsh -n pominięty (live-only)"
fi

echo "== każdy rice spoza bety: kolory promptu w colors.zsh"
for dir in "$REPO"/rices/*/; do
    rice="$(basename "$dir")"
    [[ "$rice" == white-blue_beta ]] && continue
    bad=""
    for v in ARCHENEMY_PROMPT_TEXT ARCHENEMY_PROMPT_PATH ARCHENEMY_PROMPT_OK ARCHENEMY_PROMPT_ERROR; do
        [[ "$(rice_var "$rice" "$v")" =~ ^#[0-9A-Fa-f]{6}$ ]] || bad+=" $v"
    done
    check "$rice: ARCHENEMY_PROMPT_* w formacie #RRGGBB" '[[ -z "$bad" ]]'
    switch "$rice"; OUT="$(look)"
    check "$rice: po Super+T prompt i style z tego rice'a" \
        '[[ "$(val PROMPT)" == "$(colored_prompt "$rice")" && "$(val STYLE)" == "$(rice_style "$rice")" && ! -s "$T/look.err" ]]'
done

echo "== przełączenie X → Y bez Starshipa"
switch crt; OUT="$(look)"
check "crt: ~/.config/zsh → rices/crt/zsh" '[[ "$(readlink "$H/.config/zsh")" == "$H/archenemy/rices/crt/zsh" ]]'
check "crt: colors.zsh wczytany (style i podpowiedzi)" '[[ "$(val STYLE)" == "$(rice_style crt)" && "$(val SUGGEST)" == fg=* ]]'
check "crt: prompt w kolorach crt" '[[ "$(val PROMPT)" == "$(colored_prompt crt)" ]]'
check "bez starshipa: STARSHIP_CONFIG nie powstaje" '[[ "$(val STARSHIP_CONFIG)" == "<unset>" && ! -s "$T/starship.log" ]]'
check "zero błędów i zero zmiennych roboczych" '[[ ! -s "$T/look.err" && -z "$(val LEFT | tr -d " ")" ]]'
switch yin; OUT="$(look)"
check "yin po crt: prompt i style yin" '[[ "$(val PROMPT)" == "$(colored_prompt yin)" && "$(val STYLE)" == "$(rice_style yin)" ]]'

echo "== Starship zainstalowany (atrapa)"
BASE_PATH="$STAR:$T/bin"
OUT="$(look)"
check "STARSHIP_CONFIG = ~/.config/zsh/starship.toml" '[[ "$(val STARSHIP_CONFIG)" == "$OWN" ]]'
check "domyślny prompt: Starship uruchomiony raz" '[[ "$(val PROMPT)" == TEST_STARSHIP_PROMPT && "$(grep -c "^starship init zsh$" "$T/starship.log")" -eq 1 ]]'
check "style podświetlania i tak z rice'a" '[[ "$(val STYLE)" == "$(rice_style yin)" && ! -s "$T/look.err" ]]'
OUT="$(look STARSHIP_CONFIG="$OWN")"
check "STARSHIP_CONFIG z powłoki-rodzica (ten sam plik) zostaje nasz" '[[ "$(val STARSHIP_CONFIG)" == "$OWN" && "$(val PROMPT)" == TEST_STARSHIP_PROMPT ]]'
OUT="$(look PRE='prompt_starship_precmd() { :; }' START_PROMPT='TEST_USER_STARSHIP')"
check "Starship już uruchomiony w ~/.zshrc: bez drugiego startu, config rice'a" \
    '[[ "$(val STARSHIP_CONFIG)" == "$OWN" && "$(val PROMPT)" == TEST_USER_STARSHIP && ! -s "$T/starship.log" ]]'
OUT="$(look STARSHIP_CONFIG=/TEST/own/starship.toml)"
check "inny STARSHIP_CONFIG użytkownika zostaje, bez startu" \
    '[[ "$(val STARSHIP_CONFIG)" == /TEST/own/starship.toml && "$(val PROMPT)" == "$(colored_prompt yin)" && ! -s "$T/starship.log" ]]'
echo 'format = "TEST"' > "$H/.config/starship.toml"
OUT="$(look)"
check "własny ~/.config/starship.toml: bez STARSHIP_CONFIG i bez startu" \
    '[[ "$(val STARSHIP_CONFIG)" == "<unset>" && "$(val PROMPT)" == "$(colored_prompt yin)" && ! -s "$T/starship.log" ]]'
check "własny ~/.config/starship.toml nietknięty" '[[ "$(<"$H/.config/starship.toml")" == "format = \"TEST\"" ]]'
rm -f "$H/.config/starship.toml"
OUT="$(look ARCHENEMY_ZSH_STARSHIP=0)"
check "ARCHENEMY_ZSH_STARSHIP=0: bez Starshipa, prompt w kolorach rice'a" \
    '[[ "$(val STARSHIP_CONFIG)" == "<unset>" && "$(val PROMPT)" == "$(colored_prompt yin)" && ! -s "$T/starship.log" ]]'

echo "== cudza konfiguracja zostaje"
OUT="$(look START_PROMPT='TEST %~ > ')"
check "własny prompt: bez zmian i bez startu Starshipa, style z rice'a" \
    '[[ "$(val PROMPT)" == "TEST %~ > " && ! -s "$T/starship.log" && "$(val STYLE)" == "$(rice_style yin)" && "$(val STARSHIP_CONFIG)" == "$OWN" ]]'
BASE_PATH="$T/bin"
switch white-blue_beta; OUT="$(look)"
check "beta (bez ARCHENEMY_PROMPT_*): prompt domyślny, style bety" \
    '[[ "$(val PROMPT)" == "[%n@%m %1~]%# " && "$(val STYLE)" == "$(rice_style white-blue_beta)" && ! -s "$T/look.err" ]]'
rm "$H/.config/zsh"
OUT="$(look)"; rc=$?
check "brak ~/.config/zsh: kod 0, nic nie wczytane, zero błędów" \
    '[[ $rc -eq 0 && "$(val PROMPT)" == "[%n@%m %1~]%# " && "$(val STYLE)" == "<unset>" && ! -s "$T/look.err" && -z "$(val LEFT | tr -d " ")" ]]'
mkdir -p "$H/.config/zsh"
printf '%s\n' "ZSH_HIGHLIGHT_STYLES[default]='TEST_OWN'" "ARCHENEMY_PROMPT_TEXT='#000000'" > "$H/.config/zsh/colors.zsh"
OUT="$(look)"
check "własny katalog ~/.config/zsh (ZDOTDIR): colors.zsh NIE wczytany" '[[ "$(val STYLE)" == "<unset>" && "$(val PROMPT)" == "[%n@%m %1~]%# " && ! -s "$T/look.err" ]]'
rm -rf "$H/.config/zsh"
mkdir -p "$T/stow/zsh"; cp "$REPO/rices/crt/zsh/colors.zsh" "$T/stow/zsh/"
ln -s "$T/stow/zsh" "$H/.config/zsh"
OUT="$(look)"
check "obce dowiązanie ~/.config/zsh (np. stow): nic nie wczytane" '[[ "$(val STYLE)" == "<unset>" && "$(val PROMPT)" == "[%n@%m %1~]%# " ]]'
rm "$H/.config/zsh"

echo "== prawdziwy zsh -i (tylko, gdy zsh jest w systemie)"
if command -v zsh >/dev/null 2>&1; then
    switch crt
    printf '%s\n' "archenemy_shell_dir=\"\$HOME/archenemy/config/shell\"" \
        '. "$archenemy_shell_dir/zsh-defaults.zsh"' 'unset archenemy_shell_dir' > "$H/.zshrc"
    ZOUT="$(env -i HOME="$H" PATH="/usr/bin:/bin" TERM=dumb zsh -ic 'print -r -- "$PROMPT|${ZSH_HIGHLIGHT_STYLES[default]}"' 2>"$T/zsh.err")"
    check "zsh -i: prompt i style crt" '[[ "$ZOUT" == "$(colored_prompt crt)|$(rice_style crt)" ]]'
else
    skip "zsh nie jest zainstalowany: zsh -i pominięty (live-only)"
fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗ / $SKIP skip"
(( FAIL == 0 ))
