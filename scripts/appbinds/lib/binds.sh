#!/bin/bash
# =============================================
#   archenemy - scripts/appbinds/lib/binds.sh
#   Biblioteka do bindów użytkownika (config/hypr/appbinds.lua) dla TUI
#   Super+A. Source'owana przez appbinds.sh i tests/appbinds.sh — bez
#   efektów ubocznych przy wczytaniu.
#
#   JEDNO źródło wyboru linii: user_bind_lines. Lista [numer) klawisz → cmd]
#   i usuwanie [d] N muszą patrzeć na dokładnie te same linie pliku — kiedyś
#   lista brała tylko linie w formacie TUI, a usuwanie liczyło każde
#   `^hl.bind(`, więc po ręcznie dopisanym bindzie w innej formie „[d] N”
#   kasowało inną linię niż pokazana (audyt 2026-09-25).
# =============================================

# Format linii bindu, jaki zapisuje TUI (i jedyny, jaki TUI obsługuje):
#   hl.bind(mainMod .. " + [MOD + ]KEY", hl.dsp.exec_cmd("CMD"))
# MOD = SHIFT, CTRL, ALT; CMD z ucieczką Lua dla " i \.
BIND_LINE_RE='^hl\.bind\(mainMod[[:space:]]*\.\.[[:space:]]*" \+ (((SHIFT|CTRL|ALT) \+ )*[A-Za-z0-9_]+)",[[:space:]]*hl\.dsp\.exec_cmd\("(.*)"\)\)[[:space:]]*$'

lua_escape() {
    local s="${1//\\/\\\\}"
    printf '%s' "${s//\"/\\\"}"
}

lua_unescape() {
    local s="${1//\\\"/\"}"
    printf '%s' "${s//\\\\/\\}"
}

# format_bind_line <klawisze> <komenda> — linia pliku; jedno miejsce formatu.
format_bind_line() {
    printf 'hl.bind(mainMod .. " + %s", hl.dsp.exec_cmd("%s"))' "$1" "$(lua_escape "$2")"
}

# user_bind_lines <plik> — wypisuje bindy w formacie TUI, po jednym na linię:
#   <numer linii w pliku><TAB><KEY><TAB><CMD>
# w kolejności z pliku. Brak pliku = brak bindów (kod 0).
user_bind_lines() {
    local file="$1" n=0 line
    [[ -f "$file" ]] || return 0
    while IFS= read -r line; do
        n=$((n + 1))
        [[ "$line" =~ $BIND_LINE_RE ]] || continue
        printf '%d\t%s\t%s\n' "$n" "${BASH_REMATCH[1]}" "$(lua_unescape "${BASH_REMATCH[4]}")"
    done < "$file"
}

# list_binds — ponumerowana lista bindów z $BINDS_CONF (numer = pozycja na
# liście, NIE numer linii pliku; ten sam numer przyjmuje remove_bind_by_index).
list_binds() {
    local i=0 lineno key cmd
    while IFS=$'\t' read -r lineno key cmd; do
        i=$((i + 1))
        printf "    ${CYAN:-}%2d)${NC:-} Super + ${BLUE:-}%-12s${NC:-} → %s\n" "$i" "$key" "$cmd"
    done < <(user_bind_lines "$BINDS_CONF")
    if [[ $i -eq 0 ]]; then
        echo -e "    ${YELLOW:-}(no custom binds yet — add your first!)${NC:-}"
    fi
    return 0
}

# other_bind_count <plik> — bindy dopisane ręcznie, których TUI nie zarządza.
other_bind_count() {
    local all
    [[ -f "$1" ]] || { echo 0; return 0; }
    all="$(grep -c '^hl\.bind(' "$1")"
    echo "$(( ${all:-0} - $(bind_count "$1") ))"
}

# bind_count <plik> — liczba bindów widocznych na liście.
bind_count() {
    local n
    n="$(user_bind_lines "$1" | wc -l)"
    printf '%s\n' "${n// /}"
}

# remove_bind_by_index <plik> <N> — usuwa N-ty bind z listy (numeracja jak w
# list_binds), po numerze linii pliku. Kod 1 = nie ma takiego numeru.
remove_bind_by_index() {
    local file="$1" idx="$2" lineno
    [[ "$idx" =~ ^[1-9][0-9]*$ ]] || return 1
    lineno="$(user_bind_lines "$file" | sed -n "${idx}p" | cut -f1)"
    [[ -n "$lineno" ]] || return 1
    sed -i "${lineno}d" "$file"
}

# replace_bind_command <plik> <N> <komenda> — zmienia komendę N-tego bindu,
# bez ruszania klawisza i pozostałych linii. Kod 1 = nie ma takiego numeru.
replace_bind_command() {
    local file="$1" idx="$2" cmd="$3" entry lineno key tmp n=0 line
    [[ "$idx" =~ ^[1-9][0-9]*$ ]] || return 1
    entry="$(user_bind_lines "$file" | sed -n "${idx}p")"
    [[ -n "$entry" ]] || return 1
    lineno="$(cut -f1 <<<"$entry")"
    key="$(cut -f2 <<<"$entry")"
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        if ((n == lineno)); then format_bind_line "$key" "$cmd"; echo; else printf '%s\n' "$line"; fi
    done < "$file" > "$tmp"
    chmod --reference="$file" "$tmp" 2>/dev/null
    mv "$tmp" "$file"
}
