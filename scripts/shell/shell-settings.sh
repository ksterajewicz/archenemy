#!/bin/bash
# shellcheck disable=SC1091,SC2088,SC2001  # źródła są względem SELF_DIR; ~ w UI; wcięcie listy sedem

# =============================================
#   archenemy - shell-settings.sh
#   Powłoka: wybór bash/zsh, edycja wspólnego pliku oraz skrót vi w zsh.
#   Jedyna droga do tych funkcji, woła ją TUI Super+A → [h].
#   UI po angielsku (kontekst Super+A, decyzja właściciela 2026-07-12).
#
#   Użycie:  shell-settings.sh                 → menu
#            shell-settings.sh summary | brief → skrót dla menu głównego
#            shell-settings.sh edit            → nvim + kontrola składni
#            shell-settings.sh switch bash|zsh → zmiana powłoki logowania
#            shell-settings.sh migrate         → linie z ~/.bashrc do pliku wspólnego
#
#   Plik wspólny i bloki w ~/.bashrc / ~/.zshrc: scripts/shell/lib/shell-rc.sh
#   (ta sama biblioteka co install.sh [8m]). Powłoka logowania czytana z passwd
#   (getent), bo $SHELL zostaje stary do ponownego zalogowania; sukces chsh =
#   odczyt passwd równy wyborowi, nie kod wyjścia.
#
#   Kody wyjścia: 0 zrobione albo świadomie anulowane, 1 błąd.
# =============================================

set -uo pipefail

# ARCHENEMY_DIR ustawia biblioteka niżej (jedno miejsce ze ścieżką aplikacji).
SELF_DIR="$(dirname "${BASH_SOURCE[0]}")"
BASHRC="$HOME/.bashrc"
ZSHRC="$HOME/.zshrc"
# shellcheck source=lib/shell-rc.sh
source "$SELF_DIR/lib/shell-rc.sh"
# shellcheck source=../appbinds/lib/tui.sh
source "$SELF_DIR/../appbinds/lib/tui.sh"

# Ścieżka do wyświetlenia: ~ zamiast katalogu domowego.
tilde() { printf '%s' "${1/#$HOME/\~}"; }

rc_of() { if [[ "$1" == zsh ]]; then echo "$ZSHRC"; else echo "$BASHRC"; fi; }

# Co plik rc robi z plikiem wspólnym — jedna fraza dla menu.
rc_state() {
    local rc="$1"
    if [[ ! -e "$rc" ]]; then printf 'not created'
    elif rc_block_present "$rc"; then printf 'loads the shared file'
    else printf 'does not load the shared file'
    fi
}

alias_count() {
    local n=0
    [[ -f "$SHELLRC" ]] && n="$(grep -cE '^[[:space:]]*alias[[:space:]]' "$SHELLRC")"
    if (( n == 1 )); then printf '1 alias'; else printf '%d aliases' "$n"; fi
}

# Zalogowany w innej powłoce niż passwd → zmiana działa dopiero po relogu.
relogin_pending() {
    local now="${SHELL:-}"
    [[ -n "$now" && "$(basename "$now")" != "$(login_shell)" ]]
}

summary() {
    local sh; sh="$(login_shell)"
    if relogin_pending; then printf '%s, log in again' "$sh"; else printf '%s' "$sh"; fi
}

brief() {
    printf 'Login shell  %s\n' "$(summary)"
    printf 'Your file    %s\n' "$(alias_count)"
    printf '~/.bashrc    %s\n' "$(rc_state "$BASHRC")"
    if [[ -e "$ZSHRC" ]] || command -v zsh >/dev/null 2>&1; then
        printf '~/.zshrc     %s\n' "$(rc_state "$ZSHRC")"
    else
        printf 'zsh          not installed\n'
    fi
}

# Blok w pliku rc z komunikatem. Kod 1 tylko przy błędzie.
ensure_block() {
    local rc="$1" kind="$2" res bak
    res="$(rc_block_ensure "$rc" "$kind" 2>"$TMPD/bak")" || {
        if [[ "$res" == broken ]]; then
            echo -e "  ${RED}✗ $(tilde "$rc") has '${SHELL_BLOCK_BEGIN}' without its end line — fix it by hand.${NC}"
        else
            echo -e "  ${RED}✗ Could not write $(tilde "$rc").${NC}"
        fi
        return 1
    }
    bak="$(<"$TMPD/bak")"
    case "$res" in
        created) echo -e "  ${GREEN}✓ $(tilde "$rc") created, it loads your shared file.${NC}" ;;
        added)   echo -e "  ${GREEN}✓ $(tilde "$rc") now loads your shared file (backup: $(tilde "$bak")).${NC}" ;;
        updated) echo -e "  ${GREEN}✓ archenemy block in $(tilde "$rc") refreshed (backup: $(tilde "$bak")).${NC}" ;;
    esac
}

# Alias `archenemy` dopisany kiedyś do ~/.bashrc → do pliku wspólnego, żeby
# działał też w zsh. To linia archenemy, nie użytkownika, więc bez pytania.
move_legacy_alias() {
    local st bak
    st="$(archenemy_alias_state "$BASHRC" "$ZSHRC")"
    [[ "$st" == legacy* ]] || return 0
    if bak="$(archenemy_alias_move "${st#legacy }")"; then
        echo -e "  ${GREEN}✓ The 'archenemy' command moved to your shared file (backup: $(tilde "$bak")).${NC}"
    else
        echo -e "  ${YELLOW}⚠ Could not move the 'archenemy' command from $(tilde "${st#legacy }").${NC}"
    fi
}

# Linie z ~/.bashrc do pliku wspólnego, po pokazaniu ich i za zgodą.
# $1 = powód pytania (tekst). Kod 0 także przy odmowie.
offer_migration() {
    local why="$1" preview n moved
    preview="$(rc_migrate_preview "$BASHRC")"
    [[ -n "$preview" ]] || return 0
    n="$(grep -cv '^[[:space:]]*#' <<<"$preview")"
    echo ""
    echo -e "  Your ~/.bashrc has ${BOLD}${n}${NC} line(s) that work in both shells:"
    sed 's/^/      /' <<<"$preview"
    echo ""
    if ! confirm "Move them into the shared file${why}? A dated copy of ~/.bashrc is kept." Y; then
        echo -e "  ${YELLOW}Left in ~/.bashrc. Move them later: Super+A → [h] → 3.${NC}"
        return 0
    fi
    shellrc_ensure >/dev/null
    # rc_migrate_apply liczy też komentarze nad liniami — tu ta sama liczba co na liście.
    if moved="$(rc_migrate_apply "$BASHRC")" && (( moved > 0 )); then
        echo -e "  ${GREEN}✓ ${n} line(s) moved to $(tilde "$SHELLRC").${NC}"
        echo -e "  ${CYAN}Prompt, history, functions and other bash-only lines stay in ~/.bashrc.${NC}"
    else
        echo -e "  ${RED}✗ Moving failed; ~/.bashrc and the shared file were not changed past the backup.${NC}"
        return 1
    fi
}

reload_hint() {
    echo -e "  ${CYAN}Takes effect in new terminals. In this one: exec \$SHELL${NC}"
}

vi_key_current() {
    local sequence
    if [[ -f "$SHELL_KEYS" ]]; then
        sequence="$(sed -nE "s/^bindkey -M emacs '([^']*)' vi-cmd-mode$/\\1/p" "$SHELL_KEYS" | head -n1)"
        [[ -n "$sequence" ]] && { printf '%s' "$sequence"; return; }
    fi
    printf '^X^V'
}

# Czytelną postać klawisza sprowadza do zapisu zwracanego przez bindkey.
vi_key_normalize() {
    local key="$1"
    key="${key//^[/\\e}"
    key="${key//ESC-/\\e}"
    key="${key//\\C-/^}"
    printf '%s' "$key"
}

# Dopisuje pary sekwencja/widget: statyczne, bieżące i wpisane przez użytkownika.
vi_key_parse_bindings() {
    local line key widget pattern quote
    quote="['\"]"
    pattern="^[[:space:]]*bindkey([[:space:]]+-M[[:space:]]+emacs)?[[:space:]]+${quote}([^'\"]+)${quote}[[:space:]]+([^[:space:]]+)"
    while IFS= read -r line; do
        if [[ "$line" =~ $pattern ]]; then
            key="$(vi_key_normalize "${BASH_REMATCH[2]}")"
            widget="${BASH_REMATCH[3]}"
            printf '%s\t%s\n' "$key" "$widget"
        fi
    done
}

vi_key_bindings() {
    local file line
    if [[ -f "$ARCHENEMY_DIR/config/shell/emacs-default-bindings.txt" ]]; then
        while IFS=$'\t' read -r key widget; do
            [[ -z "$key" || "$key" == \#* ]] || printf '%s\t%s\n' "$key" "$widget"
        done < "$ARCHENEMY_DIR/config/shell/emacs-default-bindings.txt"
    fi
    if command -v zsh >/dev/null 2>&1; then
        zsh -f -c 'bindkey -M emacs' 2>/dev/null | vi_key_parse_bindings
    fi
    for file in "$SHELLRC" "$ZSHRC"; do
        [[ -f "$file" ]] || continue
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*bindkey[[:space:]] ]] || continue
            printf '%s\n' "$line"
        done < "$file" | vi_key_parse_bindings
    done
}

# Odczytuje surową sekwencję do pierwszej przerwy; Esc samodzielnie anuluje.
vi_key_read_sequence() {
    local prompt="$1" char byte count=0 sequence="" chunk=""
    printf '%b' "$prompt" >&2
    if ! IFS= read -r -s -N 1 char || [[ -z "$char" ]]; then
        echo >&2
        return 1
    fi
    while :; do
        (( count += 1 ))
        (( count <= 16 )) || { echo >&2; return 2; }
        printf -v byte '%d' "'${char}"
        if [[ -n "$sequence" ]] && { (( byte == 10 )) || (( byte == 13 )); }; then break; fi
        if (( byte == 27 )); then
            if [[ -z "$sequence" ]]; then
                if ! IFS= read -r -s -N 1 -t 0.18 char || [[ -z "$char" ]]; then
                    echo >&2
                    return 1
                fi
                (( count += 1 ))
                printf -v byte '%d' "'${char}"
                sequence='\e'
            else
                sequence+='\e'
                if ! IFS= read -r -s -N 1 -t 0.18 char || [[ -z "$char" ]]; then break; fi
                (( count += 1 ))
                printf -v byte '%d' "'${char}"
            fi
        fi
        if (( byte == 0 )); then chunk='^@'
        elif (( byte >= 1 && byte <= 26 )); then printf -v chunk '^%b' "\\$(printf '%03o' "$((byte + 64))")"
        elif (( byte >= 28 && byte <= 31 )); then
            case "$byte" in 28) chunk="^\\" ;; 29) chunk='^]' ;; 30) chunk='^^' ;; 31) chunk='^_' ;; esac
        elif (( byte == 127 )); then chunk='^?'
        elif (( byte >= 32 && byte <= 126 )); then
            if [[ "$char" == "'" ]]; then chunk='\\x27'; else chunk="$char"; fi
        else
            echo >&2
            return 2
        fi
        sequence+="$chunk"
        if ! IFS= read -r -s -N 1 -t 0.18 char || [[ -z "$char" ]]; then break; fi
    done
    echo >&2
    printf '%s' "$sequence"
}

vi_key_validate_sequence() {
    local sequence="$1"
    [[ "$sequence" =~ ^(\^([@A-Z\[\\\]\^_?]|\[0-7]{3})|\\e|\\M-|\\C-|\\x[0-9A-Fa-f]{2}|[[:print:]])+$ ]] || return 1
    [[ ! "$sequence" =~ ^[[:print:]]$ ]]
}

vi_key_conflicts() {
    local wanted="$1" existing widget found=0
    if [[ "$wanted" != ^* && "$wanted" != \\?* ]]; then
        printf '  - a printable character is the prefix of %s (self-insert); typing it will wait for KEYTIMEOUT.\n' "$wanted"
        found=1
    fi
    while IFS=$'\t' read -r existing widget; do
        existing="$(vi_key_normalize "$existing")"
        [[ -n "$existing" ]] || continue
        if [[ "$existing" == "$wanted" ]]; then
            printf '  - %s replaces the existing %s binding.\n' "$wanted" "$widget"
            found=1
        elif [[ "$existing" == "$wanted"* ]]; then
            printf '  - %s is a prefix of existing %s (%s); ZLE will wait for KEYTIMEOUT.\n' "$wanted" "$existing" "$widget"
            found=1
        elif [[ "$wanted" == "$existing"* ]]; then
            printf '  - existing %s (%s) is a prefix; the new sequence changes its timeout behavior.\n' "$existing" "$widget"
            found=1
        fi
    done < <(vi_key_bindings)
    (( found ))
}

vi_key_menu() {
    local key sequence current
    while :; do
        current="$(vi_key_current)"
        clear
        tui_header "vi mode key"
        printf '  Current key: %s\n\n' "$current"
        echo -e "    ${BLUE}1${NC}) set a new key combination"
        echo -e "    ${BLUE}2${NC}) restore the zsh default (^X^V)"
        echo ""
        key="$(read_key "  Choose [1-2, Esc = back]: ")" || return 0
        case "$key" in
            1)
                sequence="$(vi_key_read_sequence '  Press the key combination (Esc = cancel): ')"
                case "$?" in
                    1) echo -e "  ${YELLOW}Cancelled; no changes made.${NC}"; continue ;;
                    2) echo -e "  ${RED}✗ Invalid or too long key sequence.${NC}"; continue ;;
                esac
                if ! vi_key_validate_sequence "$sequence"; then
                    echo -e "  ${RED}✗ Use a non-empty ASCII key combination; a single printable key cannot be used.${NC}"
                    continue
                fi
                if vi_key_conflicts "$sequence"; then
                    echo -e "  ${YELLOW}This key combination may change an existing binding or its timeout behavior.${NC}"
                    if ! confirm "Replace/overlap the listed binding(s)?" N; then
                        echo -e "  ${YELLOW}No changes made.${NC}"
                        return 0
                    fi
                fi
                if shell_keys_write "$sequence" >/dev/null; then
                    printf '  %b✓ Saved key %s.%b\n' "$GREEN" "$sequence" "$NC"
                    reload_hint
                else
                    echo -e "  ${RED}✗ Could not save the key.${NC}"
                    return 1
                fi
                return 0
                ;;
            2)
                if shell_keys_reset >/dev/null; then
                    echo -e "  ${GREEN}✓ Restored the zsh default key (^X^V).${NC}"
                    reload_hint
                else
                    echo -e "  ${RED}✗ Could not restore the default key.${NC}"
                fi
                return 0
                ;;
            ''|$'\e'|q|Q) return 0 ;;
            *) continue ;;
        esac
    done
}

# Edycja w neovimie. Po zapisie: kontrola składni w każdej zainstalowanej
# powłoce; błąd = ostrzeżenie i wybór: popraw, przywróć sprzed edycji, zostaw.
edit_shellrc() {
    local before errs key sh
    if ! command -v nvim >/dev/null 2>&1; then
        echo -e "  ${RED}✗ neovim is missing: sudo pacman -S neovim${NC}"
        return 1
    fi
    shellrc_ensure >/dev/null || { echo -e "  ${RED}✗ Cannot create $(tilde "$SHELLRC").${NC}"; return 1; }
    sh="$(login_shell)"
    if [[ "$sh" == bash || "$sh" == zsh ]] && ! rc_block_present "$(rc_of "$sh")"; then
        echo -e "  ${YELLOW}⚠ $(tilde "$(rc_of "$sh")") does not load the shared file yet.${NC}"
        if confirm "Add the archenemy block to it?" Y; then ensure_block "$(rc_of "$sh")" "$sh" || return 1; fi
    fi
    before="$TMPD/before"
    cp "$SHELLRC" "$before"
    while :; do
        nvim "$SHELLRC"
        if cmp -s "$before" "$SHELLRC"; then
            echo -e "  ${CYAN}No changes.${NC}"
            return 0
        fi
        if errs="$(shellrc_check)"; then
            if command -v zsh >/dev/null 2>&1; then
                echo -e "  ${GREEN}✓ Saved. bash -n and zsh -n: no syntax errors.${NC}"
            else
                echo -e "  ${GREEN}✓ Saved. bash -n: no syntax errors.${NC}"
            fi
            reload_hint
            return 0
        fi
        echo -e "  ${RED}✗ Syntax error, new terminals would print it and skip the rest of the file:${NC}"
        sed 's/^/      /' <<<"$errs"
        echo ""
        echo -e "    ${BLUE}e${NC}) edit again   ${BLUE}r${NC}) restore the version from before this edit   ${BLUE}k${NC}) keep it anyway"
        key="$(read_key "  Choose [e/r/k]: ")" || return 1
        case "$key" in
            e|E|"") continue ;;
            r|R) cat "$before" > "$SHELLRC"; echo -e "  ${GREEN}✓ Restored.${NC}"; return 0 ;;
            *) echo -e "  ${YELLOW}⚠ Kept with the error.${NC}"; return 1 ;;
        esac
    done
}

# Zmiana powłoki logowania: pakiet (zsh), pliki rc z blokiem, migracja za
# zgodą, chsh za zgodą, odczyt passwd i instrukcja powrotu.
switch_shell() {
    local target="$1" cur path back
    case "$target" in
        bash|zsh) ;;
        *) echo -e "  ${RED}✗ Choose bash or zsh.${NC}"; return 1 ;;
    esac
    cur="$(login_shell)"
    if ! command -v "$target" >/dev/null 2>&1; then
        if [[ "$target" != zsh ]]; then
            echo -e "  ${RED}✗ ${target} is not installed.${NC}"
            return 1
        fi
        echo -e "  zsh is not installed. It comes from the Arch repo (package ${BOLD}zsh${NC})."
        if ! confirm "Install it now (sudo pacman -S --needed zsh)?" Y; then
            echo -e "  ${YELLOW}Cancelled, nothing changed.${NC}"
            return 0
        fi
        if ! sudo pacman -S --needed zsh || ! command -v zsh >/dev/null 2>&1; then
            echo -e "  ${RED}✗ zsh was not installed, see pacman output above.${NC}"
            return 1
        fi
        echo -e "  ${GREEN}✓ zsh installed.${NC}"
    fi

    shellrc_ensure >/dev/null || { echo -e "  ${RED}✗ Cannot create $(tilde "$SHELLRC").${NC}"; return 1; }
    # Oba pliki rc wczytują plik wspólny: powrót do drugiej powłoki zastaje
    # te same komendy. ~/.zshrc tworzymy tylko przy wyborze zsh.
    ensure_block "$BASHRC" bash || return 1
    if [[ "$target" == zsh || -e "$ZSHRC" ]]; then ensure_block "$ZSHRC" zsh || return 1; fi
    move_legacy_alias
    if [[ "$target" == zsh ]]; then offer_migration " so zsh has them too" || return 1; fi

    if [[ "$cur" == "$target" ]]; then
        echo -e "  ${GREEN}✓ ${target} is already your login shell.${NC}"
        relogin_pending && echo -e "  ${CYAN}Log out and back in to start it in new terminals.${NC}"
        return 0
    fi
    if ! path="$(shell_path_for "$target")"; then
        echo -e "  ${RED}✗ ${target} is not listed in /etc/shells, chsh would refuse it.${NC}"
        return 1
    fi
    echo ""
    if ! confirm "Make ${target} your login shell (chsh -s ${path}, asks for your password)?" Y; then
        echo -e "  ${YELLOW}Login shell unchanged (${cur}). Try ${target} in a terminal by typing: ${target}${NC}"
        return 0
    fi
    chsh -s "$path"
    if [[ "$(login_shell)" != "$target" ]]; then
        echo -e "  ${RED}✗ Login shell is still $(login_shell), chsh did not change it.${NC}"
        return 1
    fi
    back="$(shell_path_for "$cur" 2>/dev/null || echo "/bin/$cur")"
    echo -e "  ${GREEN}✓ Login shell: ${target}. Log out and back in, then new terminals start ${target}.${NC}"
    echo -e "  ${CYAN}Your aliases and PATH: $(tilde "$SHELLRC"), read by both shells.${NC}"
    echo -e "  ${CYAN}Back to ${cur} any time: Super+A → [h] → 2, or in a terminal: chsh -s ${back}${NC}"
}

migrate() {
    shellrc_ensure >/dev/null || return 1
    ensure_block "$BASHRC" bash || return 1
    move_legacy_alias
    if [[ -z "$(rc_migrate_preview "$BASHRC")" ]]; then
        echo -e "  ${GREEN}✓ Nothing to move: ~/.bashrc has no plain alias/export lines left.${NC}"
        return 0
    fi
    offer_migration ""
}

menu() {
    local key cur other n
    while :; do
        cur="$(login_shell)"
        other=zsh; [[ "$cur" == zsh ]] && other=bash
        n="$(rc_migrate_candidates "$BASHRC" | wc -l)"
        clear
        tui_header "shell"
        printf "  %-14s %s\n" "Login shell" "$(summary)"
        if [[ -f "$SHELLRC" ]]; then
            printf "  %-14s %s, %s\n" "Your file" "$(tilde "$SHELLRC")" "$(alias_count)"
        else
            printf "  %-14s %s (created on first edit)\n" "Your file" "$(tilde "$SHELLRC")"
        fi
        printf "  %-14s %s\n" "~/.bashrc" "$(rc_state "$BASHRC")"
        if command -v zsh >/dev/null 2>&1; then
            printf "  %-14s %s\n" "~/.zshrc" "$(rc_state "$ZSHRC")"
        else
            printf "  %-14s %s\n" "zsh" "not installed"
        fi
        echo ""
        echo -e "    ${BLUE}1${NC}) edit your aliases, functions and PATH in neovim"
        echo -e "    ${BLUE}2${NC}) switch to ${other}"
        if (( n > 0 )); then
            echo -e "    ${BLUE}3${NC}) move lines from ~/.bashrc into your file"
        fi
        echo -e "    ${BLUE}4${NC}) vi mode key"
        echo ""
        key="$(read_key "  Choose [1-4, Esc = back]: ")" || return 0
        case "$key" in
            1) edit_shellrc ;;
            2) switch_shell "$other" ;;
            3) if (( n > 0 )); then migrate; else continue; fi ;;
            4) vi_key_menu ;;
            ""|$'\e'|q|Q) return 0 ;;
            *) continue ;;
        esac
        echo ""
        read -rp "  Press Enter to continue..." _ || return 0
    done
}

TMPD="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMPD"' EXIT

case "${1:-}" in
    "") menu ;;
    summary) summary; echo ;;
    brief) brief ;;
    edit) edit_shellrc ;;
    switch) switch_shell "${2:-}" ;;
    migrate) migrate ;;
    *) echo "✗ use: shell-settings.sh [summary|brief|edit|switch bash|zsh|migrate]" >&2; exit 1 ;;
esac
