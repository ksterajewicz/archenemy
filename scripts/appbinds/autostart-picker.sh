#!/bin/bash

# =============================================
#   archenemy - autostart-picker.sh
#   Wybór aplikacji odpalanych przy starcie Hyprlanda — checkboxy [x]/[ ]
#   na liście wszystkich wpisów .desktop, z filtrowaniem po nazwie.
#   Otwierany z Super+A → [u]. UI po angielsku (decyzja właściciela 2026-07-12).
#
#   Czysty bash (bez rofi/fzf/dialog — świadoma decyzja właściciela).
#   Wybór ląduje w data/autostart-apps.dat, z niego generator
#   scripts/hypr/lib/gen-autostart.sh robi config/hypr/autostart-apps.lua
#   (plik osobisty, poza gitem; rice'y require'ują go obok
#   autostartpersonalisation.lua, którego ta warstwa NIE dotyka).
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
# shellcheck source=lib/tui.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tui.sh"
DATA_DAT="$ARCHENEMY_DIR/data/autostart-apps.dat"
OUT_LUA="$ARCHENEMY_DIR/config/hypr/autostart-apps.lua"
GEN_LIB="$ARCHENEMY_DIR/scripts/hypr/lib/gen-autostart.sh"


# ─── ODKRYWANIE APLIKACJI ─────────────────────────────────────────────────────

declare -A APP_NAME=()      # ID → nazwa wyświetlana
declare -A SELECTED=()      # ID → 1, jeśli zaznaczona
declare -a ALL_IDS=()       # wszystkie ID, posortowane po nazwie

# Wyciągnij Name= i flagi ukrycia z jednego pliku .desktop.
# Czytamy tylko sekcję [Desktop Entry] — dalsze sekcje (Desktop Action ...)
# mają własne Name=, które nie jest nazwą aplikacji.
scan_desktop_file() {
    local file="$1" id="$2"
    local line section="" name="" hidden=0

    while IFS= read -r line; do
        if [[ "$line" == \[*\] ]]; then
            section="$line"
            [[ "$section" != "[Desktop Entry]" ]] && break
            continue
        fi
        [[ "$section" == "[Desktop Entry]" ]] || continue
        case "$line" in
            NoDisplay=true|NoDisplay=True|Hidden=true|Hidden=True) hidden=1; break ;;
            Name=*) [[ -z "$name" ]] && name="${line#Name=}" ;;
        esac
    done < "$file"

    [[ $hidden -eq 1 ]] && return 1
    APP_NAME["$id"]="$(trim "${name:-$id}")"
    [[ -z "${APP_NAME[$id]}" ]] && APP_NAME["$id"]="$id"
    return 0
}

# Te same katalogi co rofi: XDG_DATA_DIRS (też Flatpak) i katalog użytkownika.
# Kolejność od najniższego priorytetu, bo późniejszy wpis nadpisuje wcześniejszy.
declare -a DESKTOP_DIRS=()
build_desktop_dirs() {
    local i
    local -a sys=()
    IFS=: read -ra sys <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    DESKTOP_DIRS=()
    for (( i = ${#sys[@]} - 1; i >= 0; i-- )); do
        DESKTOP_DIRS+=("${sys[$i]}/applications")
    done
    DESKTOP_DIRS+=("${XDG_DATA_HOME:-$HOME/.local/share}/applications")
}

# Zbierz wszystkie wpisy .desktop, także z podkatalogów. ID wg specyfikacji
# Desktop Entry: ścieżka względna z „-” zamiast „/”, taką nazwę zna gtk-launch.
discover_apps() {
    local dir file rel id
    declare -A seen=()

    for dir in "${DESKTOP_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r file; do
            rel="${file#"$dir"/}"
            id="${rel%.desktop}"
            id="${id//\//-}"
            # Późniejszy katalog nadpisuje wpis — usuń poprzedni ślad,
            # bo ten plik może być teraz ukryty (NoDisplay=true).
            unset "APP_NAME[$id]"
            if scan_desktop_file "$file" "$id"; then
                seen["$id"]=1
            else
                unset "seen[$id]"
            fi
        done < <(find -L "$dir" -type f -name '*.desktop' 2>/dev/null)
    done

    # Sortowanie po nazwie wyświetlanej (case-insensitive), ID po tabulatorze.
    mapfile -t ALL_IDS < <(
        for id in "${!seen[@]}"; do
            printf '%s\t%s\n' "${APP_NAME[$id]}" "$id"
        done | sort -f | cut -f2-
    )
}

# ─── STAN ZAZNACZENIA ─────────────────────────────────────────────────────────

load_selection() {
    local id
    [[ -f "$DATA_DAT" ]] || return 0
    while IFS= read -r id; do
        id="$(trim "$id")"
        [[ -z "$id" || "$id" == \#* ]] && continue
        SELECTED["$id"]=1
    done < "$DATA_DAT"
}

# Zaznaczone, a już niezainstalowane: pokazujemy na górze listy, żeby dało się
# je odznaczyć. Inaczej zostawałyby w pliku i każde logowanie odpalałoby
# gtk-launch na nieistniejący wpis.
add_missing_selected() {
    local id
    local -a missing=()
    for id in "${!SELECTED[@]}"; do
        [[ -n "${APP_NAME[$id]:-}" ]] && continue
        APP_NAME["$id"]="(not installed) $id"
        missing+=("$id")
    done
    ((${#missing[@]})) && ALL_IDS=("${missing[@]}" "${ALL_IDS[@]}")
    return 0
}

# Zapis atomowy (mktemp w tym samym katalogu + mv — wzorzec z
# rofi_wallpaper_switcher.sh), potem regeneracja pliku Lua.
save_selection() {
    local tmp id
    mkdir -p "$(dirname "$DATA_DAT")" "$(dirname "$OUT_LUA")"
    tmp="$(mktemp "${DATA_DAT}.XXXXXX")" || return 1
    for id in "${!SELECTED[@]}"; do
        printf '%s\n' "$id"
    done | sort > "$tmp"
    chmod 644 "$tmp"   # mktemp daje 600 — zachowaj zwykłe prawa
    mv "$tmp" "$DATA_DAT"

    if [[ -f "$GEN_LIB" ]]; then
        # shellcheck source=/dev/null
        source "$GEN_LIB"
        generate_autostart_apps "$DATA_DAT" "$OUT_LUA" || return 1
        return 0
    fi
    return 2
}

# ─── PĘTLA UI ─────────────────────────────────────────────────────────────────

FILTER=""
PAGE=0
DIRTY=0

# Tyle pozycji mieści się w oknie pod nagłówkiem i nad stopką. Lista bez stron
# uciekała poza ekran już przy kilkudziesięciu aplikacjach.
page_size() {
    local rows
    rows="$( { stty size </dev/tty; } 2>/dev/null | cut -d' ' -f1)"
    [[ "$rows" =~ ^[0-9]+$ ]] || rows=30
    rows=$(( rows - 15 ))
    (( rows < 5 )) && rows=5
    echo "$rows"
}

# Lista ID pasujących do filtru (podciąg nazwy, case-insensitive)
declare -a VIEW=()
build_view() {
    local id name needle
    VIEW=()
    needle="${FILTER,,}"
    for id in "${ALL_IDS[@]}"; do
        if [[ -z "$needle" ]]; then
            VIEW+=("$id")
        else
            name="${APP_NAME[$id],,}"
            [[ "$name" == *"$needle"* ]] && VIEW+=("$id")
        fi
    done
}

picker_loop() {
    local input token i id box count bad size pages
    while :; do
        build_view
        clear
        echo -e "${BLUE}"
        echo "  ┌─────────────────────────────────────┐"
        echo "  │      archenemy · autostart apps     │"
        echo "  └─────────────────────────────────────┘"
        echo -e "${NC}"
        if ! command -v gtk-launch &>/dev/null; then
            echo -e "  ${YELLOW}⚠ gtk-launch not found in PATH — the selection will be saved,${NC}"
            echo -e "  ${YELLOW}  but autostart will not work until you install it (gtk3).${NC}"
            echo ""
        fi
        if [[ -n "$FILTER" ]]; then
            echo -e "  Filter: ${CYAN}${FILTER}${NC}   (${#VIEW[@]} of ${#ALL_IDS[@]} apps)"
        else
            echo -e "  All apps (${#ALL_IDS[@]})"
        fi
        echo ""

        size="$(page_size)"
        pages=$(( (${#VIEW[@]} + size - 1) / size ))
        (( pages < 1 )) && pages=1
        (( PAGE >= pages )) && PAGE=$(( pages - 1 ))
        if [[ ${#VIEW[@]} -eq 0 ]]; then
            echo -e "    ${YELLOW}(nothing matches the filter)${NC}"
        else
            # Numery liczone na całej liście, więc nie zmieniają się między stronami.
            for (( i = PAGE * size + 1; i <= (PAGE + 1) * size && i <= ${#VIEW[@]}; i++ )); do
                id="${VIEW[$((i - 1))]}"
                if [[ -n "${SELECTED[$id]:-}" ]]; then
                    box="${GREEN}[x]${NC}"
                else
                    box="[ ]"
                fi
                printf "    ${CYAN}%3d)${NC} ${box} %-32s ${BLUE}%s${NC}\n" \
                    "$i" "${APP_NAME[$id]}" "$id"
            done
        fi

        count=0
        for id in "${!SELECTED[@]}"; do
            [[ -n "${SELECTED[$id]:-}" ]] && count=$((count + 1))
        done
        echo ""
        echo -e "  ${GREEN}${count} selected${NC}   page $(( PAGE + 1 ))/${pages}"
        echo ""
        echo -e "  numbers = toggle   ${CYAN}[n]${NC}/${CYAN}[p]${NC} page   ${CYAN}/text${NC} = filter   ${CYAN}/${NC} = clear filter   ${GREEN}[s]${NC} save   ${RED}[q]${NC} cancel"
        echo ""
        read -rp "  Choice: " input || return 0
        input="$(trim "$input")"

        case "$input" in
            "")  continue ;;
            "/") FILTER=""; PAGE=0; continue ;;
            /*)  FILTER="${input#/}"; PAGE=0; continue ;;
            n|N) (( PAGE + 1 < pages )) && PAGE=$(( PAGE + 1 )); continue ;;
            p|P) (( PAGE > 0 )) && PAGE=$(( PAGE - 1 )); continue ;;
            s|S)
                if save_selection; then
                    echo -e "  ${GREEN}✓ Saved ${count} apps. They start at your next login.${NC}"
                else
                    echo -e "  ${RED}✗ Save failed (missing generator or temp file).${NC}"
                fi
                read -rp "  Press Enter to continue..." _
                return 0
                ;;
            q|Q)
                (( DIRTY == 0 )) && return 0
                confirm "Discard your changes?" N && return 0
                continue
                ;;
        esac

        # Liczby oddzielone spacją — indeksy w AKTUALNIE wyświetlanej liście
        bad=0
        for token in $input; do
            if [[ ! "$token" =~ ^[0-9]+$ ]] || (( token < 1 || token > ${#VIEW[@]} )); then
                bad=1
                continue
            fi
            id="${VIEW[$((token - 1))]}"
            DIRTY=1
            if [[ -n "${SELECTED[$id]:-}" ]]; then
                unset "SELECTED[$id]"
            else
                SELECTED["$id"]=1
            fi
        done
        if [[ $bad -eq 1 ]]; then
            echo -e "  ${YELLOW}⚠ Some entries were not valid numbers on this list — skipped.${NC}"
            read -rp "  Press Enter to continue..." _
        fi
    done
}

# ─── START ────────────────────────────────────────────────────────────────────

build_desktop_dirs
discover_apps
load_selection
add_missing_selected

if [[ ${#ALL_IDS[@]} -eq 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}⚠ No .desktop applications found in:${NC}"
    for d in "${DESKTOP_DIRS[@]}"; do
        echo -e "      $d"
    done
    echo ""
    read -rp "  Press Enter to go back..." _
    exit 0
fi

picker_loop
