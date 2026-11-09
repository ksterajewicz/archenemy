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
#     config/shell/zsh-defaults.zsh — WSPÓLNA (w gicie): historia, uzupełnianie
#     ~/.bashrc, ~/.zshrc          — tylko oznaczony blok, który wczytuje powyższe
#
#   Zapis do ~/.bashrc i ~/.zshrc: kopia `<plik>.bak-<czas>` przed każdą zmianą,
#   zapis PRZEZ plik (cat > plik), bo ~/.bashrc bywa symlinkiem do repo dotfiles
#   (mv podmieniłby symlink na zwykły plik). Ponowne wywołanie niczego nie dubluje.
#   Haki testowe: ARCHENEMY_SHELLS_FILE (zamiast /etc/shells).
# =============================================

SHELL_RC_DIR="${ARCHENEMY_DIR:-$HOME/archenemy}/config/shell"
SHELLRC="$SHELL_RC_DIR/shellrc"
# shellcheck disable=SC2034  # czyta shell-settings.sh
ZSH_DEFAULTS="$SHELL_RC_DIR/zsh-defaults.zsh"
SHELL_BLOCK_BEGIN="# >>> archenemy shell >>>"
SHELL_BLOCK_END="# <<< archenemy shell <<<"
# Znacznik aliasu z decyzji 2026-10-14 — ten sam tekst, żeby stare instalacje
# (alias w ~/.bashrc) dało się rozpoznać i przenieść.
ARCHENEMY_ALIAS_MARK="# archenemy: TUI (Super+A) jako komenda"
ARCHENEMY_ALIAS_LINE="alias archenemy='~/archenemy/scripts/appbinds/appbinds.sh'"
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
#   - It lives in ~/archenemy but is NOT tracked by git (personal layer,
#     .gitignore): updates never touch it. Back it up like your dotfiles.
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

# shellcheck disable=SC2016  # $HOME ma trafić do pliku dosłownie
# Blok wczytujący dla bash albo zsh. Ścieżki przez $HOME: repo zawsze leży
# w ~/archenemy (pilnuje tego start instalatora).
rc_block_text() {
    local kind="$1"
    echo "$SHELL_BLOCK_BEGIN"
    echo "# Added by archenemy. Your aliases, functions and PATH live in"
    echo "# ~/archenemy/config/shell/shellrc, shared by bash and zsh."
    echo "# Edit it with Super+A -> [h]. Switch shells there too."
    if [[ "$kind" == zsh ]]; then
        echo 'if [ -f "$HOME/archenemy/config/shell/zsh-defaults.zsh" ]; then . "$HOME/archenemy/config/shell/zsh-defaults.zsh"; fi'
    fi
    echo 'if [ -f "$HOME/archenemy/config/shell/shellrc" ]; then . "$HOME/archenemy/config/shell/shellrc"; fi'
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

# Stan komendy `archenemy`: ours (znacznik w shellrc), legacy (znacznik w rc
# z czasów przed plikiem wspólnym), own (własny alias użytkownika gdziekolwiek),
# none. Argumenty: pliki rc do przejrzenia.
archenemy_alias_state() {
    local f
    if grep -qxF "$ARCHENEMY_ALIAS_MARK" "$SHELLRC" 2>/dev/null; then echo ours; return; fi
    for f in "$@"; do
        if grep -qxF "$ARCHENEMY_ALIAS_MARK" "$f" 2>/dev/null; then echo "legacy $f"; return; fi
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
    printf '%s\n%s\n' "$ARCHENEMY_ALIAS_MARK" "$ARCHENEMY_ALIAS_LINE" > "$add"
    shellrc_append_common "$add" >/dev/null || { rm -f "$add"; return 1; }
    rm -f "$add"
    grep -qxF "$ARCHENEMY_ALIAS_MARK" "$SHELLRC"
}

# Alias dopisany do ~/.bashrc przez dawny krok [8m] (pusta linia, znacznik,
# alias) → do pliku wspólnego; z rc znika dokładnie to, co dopisał tamten krok.
# stdout: ścieżka kopii rc.
archenemy_alias_move() {
    local rc="$1" tmp bak
    archenemy_alias_add || return 1
    bak="$(rc_backup "$rc")" || return 1
    tmp="$(mktemp)" || return 1
    awk -v m="$ARCHENEMY_ALIAS_MARK" '
        { line[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                if (line[i] == m) {
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
