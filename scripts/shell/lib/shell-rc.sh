#!/usr/bin/env bash
# =============================================
#   archenemy - scripts/shell/lib/shell-rc.sh
#   Wspólny plik powłoki: jedno źródło aliasów, funkcji, zmiennych i PATH
#   użytkownika dla basha i zsh (właściciel 2026-11-09: „przełączać się
#   pomiędzy shellami bez utraty swoich komend”).
#   JEDNO ŹRÓDŁO PRAWDY — source'owane przez install/install.sh (krok 8m,
#   po cichu) i scripts/shell/shell-settings.sh (Super+A → [h]).
#   Nie uruchamiaj bezpośrednio — to biblioteka funkcji, bez efektów ubocznych
#   przy wczytaniu.
#
#   Warstwy:
#     config/shell/shellrc         — OSOBISTA (gitignore): plik użytkownika,
#                                    tworzony z szablonu niżej, edytowany w nvim
#     config/shell/keys.zsh        — OSOBISTY skrót ZLE (gitignore),
#                                    generowany wyłącznie przez tę bibliotekę
#     config/shell/zsh-defaults.zsh — WSPÓLNA (w gicie): historia, uzupełnianie
#     ~/.bashrc, ~/.zshrc          — tylko oznaczony blok, który wczytuje powyższe
#
#   Zapis do ~/.bashrc i ~/.zshrc: kopia `<plik>.bak-<czas>` przed każdą zmianą,
#   zapis PRZEZ plik (cat > plik), bo ~/.bashrc bywa symlinkiem do repo dotfiles
#   (mv podmieniłby symlink na zwykły plik). Ponowne wywołanie niczego nie dubluje.
#   Ścieżka aplikacji: JEDNO miejsce definicji niżej (ARCHENEMY_DIR, wołający
#   może podać własną). Blok w rc i alias `archenemy` liczą ścieżkę z niej —
#   względem $HOME, gdy się da — więc przeprowadzka aplikacji (decyzja
#   2026-11-09: ~/.local/share/archenemy) zmienia tylko tę linię, a ponowny
#   bieg install.sh sam odświeża bloki w rc-plikach.
#   Haki testowe: ARCHENEMY_SHELLS_FILE (zamiast /etc/shells).
# =============================================

: "${ARCHENEMY_DIR:=$HOME/archenemy}"
SHELL_RC_DIR="$ARCHENEMY_DIR/config/shell"
SHELLRC="$SHELL_RC_DIR/shellrc"
# shellcheck disable=SC2034  # czyta shell-settings.sh
ZSH_DEFAULTS="$SHELL_RC_DIR/zsh-defaults.zsh"
SHELL_KEYS="$SHELL_RC_DIR/keys.zsh"
SHELL_PLUGINS="$SHELL_RC_DIR/plugins.zsh"
SHELL_PLUGIN_NAMES=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions)
SHELL_BLOCK_BEGIN="# >>> archenemy shell >>>"
SHELL_BLOCK_END="# <<< archenemy shell <<<"
# Znacznik aliasu: ląduje w pliku użytkownika, więc po angielsku (właściciel
# 2026-11-09). Dawny polski znacznik z decyzji 2026-10-14 dalej rozpoznajemy
# (alias w ~/.bashrc albo w shellrc starych instalacji) i podmieniamy na nowy.
ARCHENEMY_ALIAS_MARK="# archenemy: TUI (Super+A) as a command"
ARCHENEMY_ALIAS_MARK_OLD="# archenemy: TUI (Super+A) jako komenda"
SHELLRC_BASH_MARK="# --- bash only ---"

# Szablon pliku użytkownika. Tekst widzi użytkownik, więc po angielsku.
shellrc_template() {
    cat <<'EOF'
# =============================================
#   archenemy - your shell file (bash AND zsh)
#
#   One place for your aliases, functions, environment variables and PATH.
#   ~/.bashrc and ~/.zshrc only load this file (the "archenemy shell" block),
#   so your commands come along when you switch shells (Super+A -> [h]).
#
#   Rules:
#   - Everything in "common" must work in BOTH shells: alias, export,
#     PATH="$HOME/bin:$PATH", simple functions  name() { ...; }.
#   - Things only one shell understands (shopt, bind, setopt, bindkey,
#     zsh glob qualifiers) go into "bash only" / "zsh only" at the bottom.
#     Both shells still PARSE the whole file, so if bash chokes on some zsh
#     syntax, keep that line in ~/.zshrc below the archenemy block instead.
#   - This file is read by interactive terminals. Apply changes: open a new
#     terminal, or run  exec $SHELL
#   - It lives in the archenemy folder (config/shell/shellrc) but is NOT
#     tracked by git (personal layer, .gitignore): updates never touch it.
#     Back it up like your dotfiles.
#
#   Edit: Super+A -> [h] -> 1 (opens neovim and checks the syntax after),
#   or type `archenemy` in a terminal.
# =============================================

# --- common: bash and zsh ---


# --- bash only ---
if [ -n "${BASH_VERSION:-}" ]; then
    :
fi

# --- zsh only ---
if [ -n "${ZSH_VERSION:-}" ]; then
    :
fi

# vim: set ft=bash:
EOF
}

# Tworzy plik użytkownika, gdy go nie ma. stdout: created | exists.
shellrc_ensure() {
    if [[ -e "$SHELLRC" ]]; then
        echo exists
        return 0
    fi
    mkdir -p "$SHELL_RC_DIR" || return 1
    shellrc_template > "$SHELLRC" || return 1
    echo created
}

# Zamienia czytelną sekwencję ZLE na jedną linię bindkey.
shell_keys_text() {
    local sequence="$1" escaped
    [[ "$sequence" =~ ^(\^([@A-Z\[\\\]\^_?]|\[0-7]{3})|\\e|\\M-|\\C-|[[:print:]])+$ ]] || return 1
    # Apostrof ma być przekazany w notacji ZLE, nigdy jako składnia powłoki.
    [[ "$sequence" != *"'"* ]] || return 1
    escaped="$sequence"
    printf "bindkey -M emacs '%s' vi-cmd-mode\n" "$escaped"
}

# Zapis atomowy pliku osobistego z kopią poprzedniej wersji.
shell_keys_write() {
    local sequence="$1" text tmp bak=""
    text="$(shell_keys_text "$sequence")" || return 1
    mkdir -p "$SHELL_RC_DIR" || return 1
    if [[ -e "$SHELL_KEYS" ]]; then
        [[ "$(<"$SHELL_KEYS")" == "$text" ]] && { echo unchanged; return 0; }
        bak="$(rc_backup "$SHELL_KEYS")" || return 1
    fi
    tmp="$(mktemp "$SHELL_KEYS.XXXXXX")" || return 1
    chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
    if ! printf '%s\n' "$text" > "$tmp" || ! mv -f "$tmp" "$SHELL_KEYS"; then
        rm -f "$tmp"
        return 1
    fi
    [[ -n "$bak" ]] && echo "$bak" >&2
    echo written
}

# Usunięcie pliku przywraca domyślne wiązanie zsh (^X^V).
shell_keys_reset() {
    local bak
    [[ -e "$SHELL_KEYS" ]] || { echo unchanged; return 0; }
    bak="$(rc_backup "$SHELL_KEYS")" || return 1
    rm -f "$SHELL_KEYS" || return 1
    echo "$bak" >&2
    echo reset
}

# Stan czytamy jako dane, nigdy nie wykonujemy pliku osobistego w TUI.
shell_plugin_enabled() {
    [[ -f "$SHELL_PLUGINS" ]] && grep -qxF "# archenemy plugin: $1=1" "$SHELL_PLUGINS"
}

# Szablon bez ustawiania zmiennych konfiguracyjnych wtyczek użytkownika.
# Faza completion musi poprzedzać compinit; pozostałe wtyczki są na końcu.
shell_plugins_text() {
    local autosuggestions="$1" highlighting="$2" completions="$3"
    printf '%s\n' '# >>> archenemy zsh plugins >>>' \
        '# Managed by Super+A -> [h] -> 5. Changes keep a dated backup.' \
        '# Disable a plugin in that menu, then open a new terminal.' \
        "# archenemy plugin: zsh-autosuggestions=$autosuggestions" \
        "# archenemy plugin: zsh-syntax-highlighting=$highlighting" \
        "# archenemy plugin: zsh-completions=$completions"
    cat <<'EOF'
if [[ "${archenemy_plugins_phase:-}" == completion ]]; then
EOF
    if [[ "$completions" == 1 ]]; then
        cat <<'EOF'
    if [[ -d /usr/share/zsh/site-functions && "${fpath[(Ie)/usr/share/zsh/site-functions]}" == 0 ]]; then
        fpath+=(/usr/share/zsh/site-functions)
    fi
EOF
    fi
    printf '%s\n' '    return 0' 'fi'
    if [[ "$autosuggestions" == 1 ]]; then
        printf '%s\n' 'if [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then' \
            '    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' 'fi'
    fi
    if [[ "$highlighting" == 1 ]]; then
        printf '%s\n' 'if [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then' \
            '    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' 'fi'
    fi
    printf '%s\n' '# <<< archenemy zsh plugins <<<' 'return 0'
}

# Odmawiamy zastąpienia obcego lub ręcznie zmienionego pliku, nawet ze znacznikiem.
shell_plugins_managed() {
    [[ -e "$SHELL_PLUGINS" || -L "$SHELL_PLUGINS" ]] || return 0
    [[ -f "$SHELL_PLUGINS" && ! -L "$SHELL_PLUGINS" ]] || return 1
    local name expected
    local -a states=()
    for name in "${SHELL_PLUGIN_NAMES[@]}"; do
        if shell_plugin_enabled "$name"; then states+=(1); else states+=(0); fi
    done
    expected="$(shell_plugins_text "${states[@]}")"
    [[ "$(<"$SHELL_PLUGINS")" == "$expected" ]]
}

# Jedyny zapis plugins.zsh: atomowo, z kopią; ponowny zapis jest no-op.
shell_plugin_write() {
    local plugin="$1" enabled="$2" name text tmp bak="" known=0
    local -a states=()
    [[ "$enabled" == 0 || "$enabled" == 1 ]] || return 1
    shell_plugins_managed || return 1
    for name in "${SHELL_PLUGIN_NAMES[@]}"; do
        if [[ "$name" == "$plugin" ]]; then
            states+=("$enabled"); known=1
        elif shell_plugin_enabled "$name"; then states+=(1)
        else states+=(0)
        fi
    done
    (( known )) || return 1
    text="$(shell_plugins_text "${states[@]}")" || return 1
    if [[ -f "$SHELL_PLUGINS" ]]; then
        [[ "$(<"$SHELL_PLUGINS")" == "$text" ]] && { echo unchanged; return 0; }
        bak="$(rc_backup "$SHELL_PLUGINS")" || return 1
    fi
    mkdir -p "$SHELL_RC_DIR" || return 1
    tmp="$(mktemp "$SHELL_PLUGINS.XXXXXX")" || return 1
    if ! printf '%s\n' "$text" > "$tmp" || ! mv -f "$tmp" "$SHELL_PLUGINS"; then
        rm -f "$tmp"
        return 1
    fi
    [[ -n "$bak" ]] && echo "$bak" >&2
    echo written
}

# Kopia zapasowa z datą obok pliku; stdout: ścieżka kopii. -L: przy symlinku
# kopiujemy treść, nie sam link.
rc_backup() {
    local f="$1" bak n=1
    bak="$f.bak-$(date +%Y%m%d_%H%M%S)"
    while [[ -e "$bak" ]]; do n=$((n + 1)); bak="$f.bak-$(date +%Y%m%d_%H%M%S)-$n"; done
    cp -pL "$f" "$bak" || return 1
    echo "$bak"
}

# Treść pliku tymczasowego do celu przez sam plik (symlink zostaje symlinkiem).
rc_write() {
    local target="$1" tmp="$2"
    cat "$tmp" > "$target" || return 1
    rm -f "$tmp"
}

# Ścieżka jako wyrażenie do pliku rc: "$HOME/<reszta>", gdy leży w katalogu
# domowym i nie ma znaków specjalnych (ten sam plik działa po zmianie $HOME),
# inaczej ścieżka bezwzględna w cudzysłowie %q (bash i zsh czytają ją tak samo).
rc_path_expr() {
    local p="$1" rel="${1#"$HOME"/}"
    if [[ "$rel" != "$p" && "$rel" =~ ^[A-Za-z0-9._/+-]+$ ]]; then
        # shellcheck disable=SC2016  # $HOME ma trafić do pliku dosłownie
        printf '"$HOME/%s"' "$rel"
    else
        printf '%q' "$p"
    fi
}

# Linia aliasu `archenemy` do pliku wspólnego. `~` w aliasie rozwija się przy
# użyciu, w obu powłokach; poza $HOME — ścieżka zacytowana dwukrotnie (%q),
# bo wartość aliasu jest jeszcze raz parsowana.
archenemy_alias_line() {
    local target="$ARCHENEMY_DIR/scripts/appbinds/appbinds.sh" rel q
    rel="${target#"$HOME"/}"
    if [[ "$rel" != "$target" && "$rel" =~ ^[A-Za-z0-9._/+-]+$ ]]; then
        printf "alias archenemy='~/%s'\n" "$rel"
    else
        printf -v q '%q' "$target"
        printf 'alias archenemy=%q\n' "$q"
    fi
}

# Blok wczytujący dla bash albo zsh. Ścieżka występuje w nim RAZ (zmienna
# archenemy_shell_dir, potem unset), żeby przeprowadzka zmieniała jedną linię.
# shellcheck disable=SC2016  # $archenemy_shell_dir ma trafić do pliku dosłownie
rc_block_text() {
    local kind="$1"
    echo "$SHELL_BLOCK_BEGIN"
    echo "# Added by archenemy: loads your shared shell file (aliases, functions"
    echo "# and PATH for bash and zsh). Edit it, or switch shells: Super+A -> [h]."
    echo "archenemy_shell_dir=$(rc_path_expr "$SHELL_RC_DIR")"
    if [[ "$kind" == zsh ]]; then
        echo 'if [ -f "$archenemy_shell_dir/zsh-defaults.zsh" ]; then . "$archenemy_shell_dir/zsh-defaults.zsh"; fi'
        echo 'if [ -f "$archenemy_shell_dir/keys.zsh" ]; then . "$archenemy_shell_dir/keys.zsh"; fi'
    fi
    echo 'if [ -f "$archenemy_shell_dir/shellrc" ]; then . "$archenemy_shell_dir/shellrc"; fi'
    echo 'unset archenemy_shell_dir'
    echo "$SHELL_BLOCK_END"
}

# Obecny blok z pliku (od znacznika do znacznika włącznie).
rc_block_current() {
    awk -v b="$SHELL_BLOCK_BEGIN" -v e="$SHELL_BLOCK_END" '
        $0 == b { on = 1 } on { print } on && $0 == e { exit }' "$1"
}

# Czy plik ma kompletny blok? 0 tak, 1 nie.
rc_block_present() {
    [[ -f "$1" ]] && grep -qxF "$SHELL_BLOCK_BEGIN" "$1" && grep -qxF "$SHELL_BLOCK_END" "$1"
}

# Blok w ~/.bashrc albo ~/.zshrc: dopisany, odświeżony albo bez zmian.
# stdout: created | added | updated | ok | broken (początek bez końca: nie
# ruszamy, bo nie wiemy, gdzie kończy się blok, a gdzie linie użytkownika).
# Przy zmianie istniejącego pliku stderr dostaje ścieżkę kopii.
rc_block_ensure() {
    local rc="$1" kind="$2" want tmp bak
    want="$(rc_block_text "$kind")"
    if [[ ! -e "$rc" ]]; then
        {
            if [[ "$kind" == bash ]]; then
                echo "# ~/.bashrc, created by archenemy"
                echo ""
                echo "# If not running interactively, don't do anything"
                # shellcheck disable=SC2016  # tekst do pliku, nie do rozwinięcia
                echo '[[ $- != *i* ]] && return'
            else
                echo "# ~/.zshrc, created by archenemy"
            fi
            echo ""
            echo "$want"
        } > "$rc" || return 1
        echo created
        return 0
    fi
    if grep -qxF "$SHELL_BLOCK_BEGIN" "$rc"; then
        if ! grep -qxF "$SHELL_BLOCK_END" "$rc"; then
            echo broken
            return 1
        fi
        if [[ "$(rc_block_current "$rc")" == "$want" ]]; then
            echo ok
            return 0
        fi
        bak="$(rc_backup "$rc")" || return 1
        tmp="$(mktemp)" || return 1
        awk -v b="$SHELL_BLOCK_BEGIN" -v e="$SHELL_BLOCK_END" -v w="$want" '
            $0 == b && !done { print w; skip = 1; next }
            skip { if ($0 == e) { skip = 0; done = 1 }; next }
            { print }' "$rc" > "$tmp" && rc_write "$rc" "$tmp" || return 1
        echo "$bak" >&2
        echo updated
        return 0
    fi
    bak="$(rc_backup "$rc")" || return 1
    tmp="$(mktemp)" || return 1
    { cat "$rc"; [[ -z "$(tail -c1 "$rc")" ]] || echo ""; echo ""; echo "$want"; } > "$tmp" \
        && rc_write "$rc" "$tmp" || return 1
    echo "$bak" >&2
    echo added
}

# Tekst z pliku $2 do sekcji „common” pliku użytkownika (przed sekcją „bash
# only”; bez niej na koniec). Linie, które już są w pliku dosłownie, pomijamy,
# z wyjątkiem pustych. stdout: liczba dopisanych niepustych linii.
shellrc_append_common() {
    local add="$1" tmp
    shellrc_ensure >/dev/null || return 1
    tmp="$(mktemp "$SHELLRC.XXXXXX")" || return 1
    awk -v mark="$SHELLRC_BASH_MARK" -v addf="$add" -v cnt="$tmp.count" '
        function flush(   i) { for (i = 1; i <= n; i++) print add[i]; if (n) print ""; n = 0 }
        BEGIN {
            while ((getline l < ARGV[1]) > 0) have[l] = 1
            close(ARGV[1])
            while ((getline l < addf) > 0) if (l == "" || !(l in have)) { add[++n] = l; if (l != "") real++ }
        }
        $0 == mark && !done { flush(); done = 1 }
        { print }
        END { if (!done) { print ""; flush() }; print real + 0 > cnt }
    ' "$SHELLRC" > "$tmp" || { rm -f "$tmp" "$tmp.count"; return 1; }
    if [[ "$(<"$tmp.count")" -eq 0 ]]; then
        rm -f "$tmp" "$tmp.count"
        echo 0
        return 0
    fi
    cat "$tmp.count"
    rm -f "$tmp.count"
    rc_write "$SHELLRC" "$tmp"
}

# Numery linii pliku rc, które bezpiecznie przenieść do pliku wspólnego:
# jednolinijkowe `alias …=`, `export X=…`, `X=…` od pierwszej kolumny, ze
# zbalansowanymi cudzysłowami, poza funkcjami, if/for/case i blokiem archenemy,
# razem z komentarzami tuż nad nimi. Zostają: prompt i historia basha (PS1,
# PROMPT_COMMAND, HIST*, BASH*), shopt/bind/complete/source, funkcje, bloki.
rc_migrate_candidates() {
    [[ -f "$1" ]] || return 0
    awk -v b="$SHELL_BLOCK_BEGIN" -v e="$SHELL_BLOCK_END" '
        function balanced(l,   t) {
            t = l; gsub(/\\\\/, "", t); gsub(/\\"/, "", t); gsub(/\\\047/, "", t)
            return (gsub(/\047/, "", t) % 2 == 0) && (gsub(/"/, "", t) % 2 == 0)
        }
        function candidate(l,   name) {
            if (l ~ /\\$/ || !balanced(l)) return 0
            if (l ~ /^alias[ \t]+[^ \t=]+=/) return 1
            if (l ~ /^(export[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=/) {
                name = l; sub(/^export[ \t]+/, "", name); sub(/=.*/, "", name)
                return name !~ /^(PS[0-9]|PROMPT_COMMAND|PROMPT_DIRTRIM|HIST[A-Z_]*|BASH[A-Z_]*|SHELL|SHLVL|IFS)$/
            }
            return 0
        }
        inblock { if ($0 == e) inblock = 0; nc = 0; next }
        $0 == b { inblock = 1; nc = 0; next }
        depth { if ($0 ~ /^(}|fi|done|esac)([ \t;#]|$)/) depth = 0; nc = 0; next }
        /^(function[ \t]|[A-Za-z_][A-Za-z0-9_:.-]*[ \t]*\(\))/ { if ($0 !~ /}[ \t;]*$/) depth = 1; nc = 0; next }
        /^(if|for|while|until|case|select)[ \t]/ { if ($0 !~ /(^|[ \t;])(fi|done|esac)([ \t;]|$)/) depth = 1; nc = 0; next }
        /^[ \t]*#/ { cbuf[++nc] = NR; next }
        candidate($0) { for (i = 1; i <= nc; i++) print cbuf[i]; nc = 0; print NR; next }
        { nc = 0 }
    ' "$1"
}

# Podgląd kandydatów: same linie (bez numerów), po jednej.
rc_migrate_preview() {
    local rc="$1"
    awk 'NR == FNR { want[$1] = 1; next } FNR in want' <(rc_migrate_candidates "$rc") "$rc"
}

# Przeniesienie kandydatów z pliku rc do pliku wspólnego: najpierw kopia rc,
# potem zapis do shellrc, dopiero na końcu usunięcie z rc — przy błędzie po
# drodze nic nie ginie. stdout: liczba przeniesionych linii (0 = nic do roboty).
rc_migrate_apply() {
    local rc="$1" add tmp bak
    local -a nums=()
    mapfile -t nums < <(rc_migrate_candidates "$rc")
    if ((${#nums[@]} == 0)); then echo 0; return 0; fi
    bak="$(rc_backup "$rc")" || return 1
    add="$(mktemp)" || return 1
    {
        echo "# moved from ${rc/#$HOME/\~} on $(date +%Y-%m-%d) (backup: ${bak/#$HOME/\~})"
        rc_migrate_preview "$rc"
    } > "$add"
    shellrc_append_common "$add" >/dev/null || { rm -f "$add"; return 1; }
    rm -f "$add"
    tmp="$(mktemp)" || return 1
    awk 'NR == FNR { drop[$1] = 1; next } !(FNR in drop)' <(printf '%s\n' "${nums[@]}") "$rc" > "$tmp" \
        && rc_write "$rc" "$tmp" || return 1
    echo "${#nums[@]}"
}

# Czy plik ma znacznik aliasu (nowy albo dawny)? 0 tak, 1 nie.
archenemy_alias_marked() {
    grep -qxF -e "$ARCHENEMY_ALIAS_MARK" -e "$ARCHENEMY_ALIAS_MARK_OLD" "$1" 2>/dev/null
}

# Stan komendy `archenemy`: ours (znacznik w shellrc), legacy (znacznik w rc
# z czasów przed plikiem wspólnym), own (własny alias użytkownika gdziekolwiek),
# none. Argumenty: pliki rc do przejrzenia.
archenemy_alias_state() {
    local f
    if archenemy_alias_marked "$SHELLRC"; then echo ours; return; fi
    for f in "$@"; do
        if archenemy_alias_marked "$f"; then echo "legacy $f"; return; fi
    done
    for f in "$SHELLRC" "$@"; do
        if grep -qE '^[[:space:]]*alias[[:space:]]+archenemy=' "$f" 2>/dev/null; then echo own; return; fi
    done
    echo none
}

# Alias `archenemy` do pliku wspólnego (działa w bash i zsh).
archenemy_alias_add() {
    local add
    add="$(mktemp)" || return 1
    { echo "$ARCHENEMY_ALIAS_MARK"; archenemy_alias_line; } > "$add"
    shellrc_append_common "$add" >/dev/null || { rm -f "$add"; return 1; }
    rm -f "$add"
    archenemy_alias_marked "$SHELLRC"
}

# Dawny polski znacznik w shellrc → nowy, angielski. Zmieniamy tylko linię
# równą znacznikowi (to linia archenemy, nie użytkownika), z kopią przed
# zmianą. stdout: ścieżka kopii albo nic, gdy nie było czego zmieniać.
archenemy_alias_mark_refresh() {
    local tmp bak
    grep -qxF "$ARCHENEMY_ALIAS_MARK_OLD" "$SHELLRC" 2>/dev/null || return 0
    bak="$(rc_backup "$SHELLRC")" || return 1
    tmp="$(mktemp "$SHELLRC.XXXXXX")" || return 1
    # shellcheck disable=SC2015  # błąd awk lub zapisu ma wspólną ścieżkę sprzątania
    awk -v o="$ARCHENEMY_ALIAS_MARK_OLD" -v n="$ARCHENEMY_ALIAS_MARK" '
        $0 == o { print n; next } { print }' "$SHELLRC" > "$tmp" \
        && rc_write "$SHELLRC" "$tmp" || { rm -f "$tmp"; return 1; }
    echo "$bak"
}

# Alias dopisany do ~/.bashrc przez dawny krok [8m] (pusta linia, znacznik,
# alias) → do pliku wspólnego; z rc znika dokładnie to, co dopisał tamten krok.
# stdout: ścieżka kopii rc.
archenemy_alias_move() {
    local rc="$1" tmp bak
    archenemy_alias_add || return 1
    bak="$(rc_backup "$rc")" || return 1
    tmp="$(mktemp)" || return 1
    awk -v m="$ARCHENEMY_ALIAS_MARK" -v o="$ARCHENEMY_ALIAS_MARK_OLD" '
        { line[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                if (line[i] == m || line[i] == o) {
                    drop[i] = 1
                    if (line[i + 1] ~ /^alias archenemy=/) drop[i + 1] = 1
                    if (i > 1 && line[i - 1] == "") drop[i - 1] = 1
                }
            }
            for (i = 1; i <= NR; i++) if (!(i in drop)) print line[i]
        }' "$rc" > "$tmp" && rc_write "$rc" "$tmp" || return 1
    echo "$bak"
}

# Powłoka logowania z passwd (nie z $SHELL: ten zostaje stary do ponownego
# zalogowania). stdout: nazwa, np. bash, zsh.
login_shell() {
    local sh
    sh="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
    [[ -n "$sh" ]] || sh="${SHELL:-}"
    basename "${sh:-unknown}"
}

# Pełna ścieżka powłoki z /etc/shells (chsh przyjmuje tylko takie). stdout:
# pierwsza wykonywalna pozycja o danej nazwie; kod 1, gdy jej brak.
shell_path_for() {
    local name="$1" line
    while IFS= read -r line; do
        [[ "$line" == /* && "$(basename "$line")" == "$name" && -x "$line" ]] && { echo "$line"; return 0; }
    done < "${ARCHENEMY_SHELLS_FILE:-/etc/shells}"
    return 1
}

# Kontrola składni pliku wspólnego w każdej zainstalowanej powłoce.
# stdout: komunikaty błędów z prefiksem powłoki; kod 1 przy błędzie.
shellrc_check() {
    local out rc=0
    if ! out="$(bash -n "$SHELLRC" 2>&1)"; then
        printf 'bash: %s\n' "$out"; rc=1
    fi
    if command -v zsh >/dev/null 2>&1 && ! out="$(zsh -n "$SHELLRC" 2>&1)"; then
        printf 'zsh: %s\n' "$out"; rc=1
    fi
    return "$rc"
}
