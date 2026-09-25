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
#   hl.bind(mainMod .. " + KEY", hl.dsp.exec_cmd("CMD"))
BIND_LINE_RE='^hl\.bind\(mainMod[[:space:]]*\.\.[[:space:]]*" \+ ([A-Za-z0-9_]+)",[[:space:]]*hl\.dsp\.exec_cmd\("(.*)"\)\)'

# user_bind_lines <plik> — wypisuje bindy w formacie TUI, po jednym na linię:
#   <numer linii w pliku><TAB><KEY><TAB><CMD>
# w kolejności z pliku. Brak pliku = brak bindów (kod 0).
user_bind_lines() {
    local file="$1" n=0 line
    [[ -f "$file" ]] || return 0
    while IFS= read -r line; do
        n=$((n + 1))
        [[ "$line" =~ $BIND_LINE_RE ]] || continue
        printf '%d\t%s\t%s\n' "$n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
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
