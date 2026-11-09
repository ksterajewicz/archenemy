#!/bin/bash
# =============================================
#   archenemy - scripts/appbinds/lib/tui.sh
#   Wspólna obsługa klawiatury i drobiazgi TUI Super+A. Source'owana przez
#   appbinds.sh, autostart-picker.sh, update-archenemy.sh i testy, bez efektów
#   ubocznych przy wczytaniu.
# =============================================

# Jeden akcent na rice, reszta to przygaszony tekst i kolory stanu. Wyłącznie paleta
# bright: zwykłe ANSI na white-blue ma kontrast 2,4–3,6:1 (blue 2,6:1), więc numery
# i ramki były ledwo czytelne. tests/tui-contrast.sh pilnuje 4,5:1 w każdym rice.
tui_accent_code() {
    local rice="" file="${ARCHENEMY_DIR:-$HOME/archenemy}/.current_rice"
    [[ -f "$file" ]] && rice="$(<"$file")"
    case "$rice" in
        white-blue|white-blue_beta) echo 94 ;;
        asia-n-rice) echo 95 ;;
        *) echo 96 ;;
    esac
}

# shellcheck disable=SC2034  # kolory dla skryptów source'ujących tę bibliotekę
ACCENT="\\033[0;$(tui_accent_code)m"
# shellcheck disable=SC2034
BOLD='\033[1m'
# shellcheck disable=SC2034
DIM='\033[2m'
# shellcheck disable=SC2034
RED='\033[0;91m'
# shellcheck disable=SC2034
GREEN='\033[0;92m'
# shellcheck disable=SC2034
YELLOW='\033[0;93m'
# shellcheck disable=SC2034
BLUE="$ACCENT"
# shellcheck disable=SC2034
CYAN="$ACCENT"
NC='\033[0m'

# Rozmiar okna do TUI_ROWS i TUI_COLS. ARCHENEMY_TUI_SIZE="wiersze kolumny" to hak
# dla testów; bez terminala zostaje rozmiar okna Super+A.
tui_size() {
    local size="${ARCHENEMY_TUI_SIZE:-}"
    [[ -n "$size" ]] || size="$( { stty size </dev/tty; } 2>/dev/null)"
    read -r TUI_ROWS TUI_COLS <<<"$size"
    [[ "${TUI_ROWS:-}" =~ ^[0-9]+$ && "${TUI_COLS:-}" =~ ^[0-9]+$ && "$TUI_ROWS" -gt 0 && "$TUI_COLS" -gt 0 ]] \
        || { TUI_ROWS=27; TUI_COLS=90; }
}

# Tekst dokładnie na szerokość w FIT: ucięty z „…” albo dopełniony spacjami. Liczy
# znaki, nie bajty: printf %-Ns w bashu liczy bajty i rozjeżdża kolumny na „…”.
# shellcheck disable=SC2034  # wynik czytają wołający
FIT=""
tui_fit() {
    local s="$1" w="$2"
    (( ${#s} > w )) && s="${s:0:w-1}…"
    # shellcheck disable=SC2034
    printf -v FIT '%s%*s' "$s" "$(( w - ${#s} ))" ""
}

# Nagłówek każdego ekranu Super+A: nazwa, ekran, rice po prawej, cienka linia.
tui_header() {
    local title="$1" rice="" width pad line
    [[ -f "${ARCHENEMY_DIR:-$HOME/archenemy}/.current_rice" ]] && rice="$(<"${ARCHENEMY_DIR:-$HOME/archenemy}/.current_rice")"
    tui_size
    width=$(( TUI_COLS - 4 ))
    (( width > 84 )) && width=84
    pad=$(( width - 11 - ${#title} ))
    (( pad < 0 )) && pad=0
    printf -v line '%*s' "$width" ""
    echo ""
    printf "  %b%b  %s%*s%b\n" "${BOLD}archenemy${NC}" "$DIM" "$title" "$pad" "$rice" "$NC"
    printf "  %b%s%b\n\n" "$DIM" "${line// /─}" "$NC"
}

# Czysty bashowy trim — NIE `| xargs`: xargs robi przetwarzanie cudzysłowów,
# więc `sh -c 'btop; read'` gubił apostrofy, a samotny apostrof wysypywał
# cały pipe („unmatched single quote" → „Empty command").
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Jeden klawisz bez Enter (menu/potwierdzenia — nie wolne wpisywanie tekstu).
# Zwraca $'\e' dla samego Escape, żeby wołający mógł potraktować go jak
# anulowanie. Strzałki, Home, F1… to sekwencje zaczynające się od Escape:
# czytamy je do końca i ignorujemy, inaczej strzałka działałaby jak Esc, a reszta
# sekwencji wpadałaby do następnego pola. Kod 1 = koniec wejścia.
read_key() {
    local prompt="$1" key="" next=""
    while :; do
        if ! IFS= read -rsn1 -p "$prompt" key && [[ -z "$key" ]]; then
            echo "" >&2
            return 1
        fi
        prompt=""
        if [[ "$key" == $'\e' ]] && IFS= read -rsn1 -t 0.02 next && [[ "$next" == "[" || "$next" == "O" ]]; then
            while IFS= read -rsn1 -t 0.02 next; do
                [[ "$next" =~ ^[A-Za-z~]$ ]] && break
            done
            continue
        fi
        break
    done
    echo "" >&2
    printf '%s' "$key"
}

# Klawisz menu głównego na stdout: up, down, home, end, enter, esc, ignored albo
# sam znak. Kod 1 = koniec wejścia.
read_key_nav() {
    local key="" next="" seq=""
    local -a timeout_args=()
    [[ -z "${TUI_KEY_TIMEOUT:-}" ]] || timeout_args=(-t "$TUI_KEY_TIMEOUT")
    if ! IFS= read -rsn1 "${timeout_args[@]}" key && [[ -z "$key" ]]; then
        return 1
    fi
    if [[ -z "$key" ]]; then
        echo enter
    elif [[ "$key" != $'\e' ]]; then
        printf '%s' "$key"
    elif IFS= read -rsn1 -t 0.02 next && [[ "$next" == "[" || "$next" == "O" ]]; then
        while IFS= read -rsn1 -t 0.02 next; do
            seq+="$next"
            [[ "$next" =~ ^[A-Za-z~]$ ]] && break
        done
        case "$seq" in
            A) echo up ;;
            B) echo down ;;
            H|1~|7~) echo home ;;
            F|4~|8~) echo end ;;
            *) echo ignored ;;
        esac
    else
        echo esc
    fi
}

# Lista wyboru: tui_menu <indeks początkowy od 0> <etykieta>…
# Wynik w TUI_MENU_INDEX, kod 0 = wybór, 1 = Esc/q/EOF. Czyta stdin także bez
# TTY; tylko terminal cofa kursor do przerysowania listy. Nagłówek rysuje wołający.
# Opcjonalna tablica TUI_MENU_KEYS dodaje skróty literowe (poza j/k/q).
# shellcheck disable=SC2034  # wynik czyta skrypt wywołujący
TUI_MENU_INDEX=0
# shellcheck disable=SC2034
tui_menu() {
    local selected="$1" key i width hint remaining
    local deadline=$(( SECONDS + ${TUI_MENU_TIMEOUT:-0} ))
    shift
    local -a items=("$@")
    local count=${#items[@]}
    (( count > 0 )) || return 1
    (( selected >= 0 && selected < count )) || selected=0
    while :; do
        tui_size
        width=$(( TUI_COLS - 6 ))
        (( width > 0 )) || width=1
        for i in "${!items[@]}"; do
            tui_fit "$(( i + 1 ))) ${items[$i]}" "$width"
            if (( i == selected )); then
                printf '  %b› %s%b\n' "${ACCENT}\033[7m" "$FIT" "$NC"
            else
                printf '    %s\n' "$FIT"
            fi
        done
        hint="↑/↓ or j/k: move · Enter: select · 1-${count}: select · Esc: back"
        [[ "${TUI_MENU_CHECKLIST:-0}" == 1 ]] && hint="↑/↓ or j/k: move · Space/Enter: toggle · Esc: back"
        tui_fit "$hint" "$width"
        printf '\n    %b%s%b\n' "$DIM" "$FIT" "$NC"
        remaining=""
        if (( ${TUI_MENU_TIMEOUT:-0} > 0 )); then
            remaining=$(( deadline - SECONDS ))
            (( remaining > 0 )) || return 1
        fi
        key="$(TUI_KEY_TIMEOUT="$remaining" read_key_nav)" || return 1
        case "$key" in
            up|k) selected=$(( (selected + count - 1) % count )) ;;
            down|j) selected=$(( (selected + 1) % count )) ;;
            home) selected=0 ;;
            end) selected=$(( count - 1 )) ;;
            enter|$'\r') TUI_MENU_INDEX=$selected; return 0 ;;
            ' ')
                if [[ "${TUI_MENU_CHECKLIST:-0}" == 1 ]]; then
                    TUI_MENU_INDEX=$selected; return 0
                fi
                ;;
            esc|q|Q) return 1 ;;
            [1-9])
                if [[ "${TUI_MENU_CAPTURE_DIGITS:-0}" == 1 ]]; then
                    # Stary picker przyjmuje także wiele numerów i numery >9.
                    local rest=""
                    IFS= read -r rest || return 1
                    TUI_MENU_INPUT="$key$rest"
                    TUI_MENU_INDEX=-1
                    return 0
                fi
                if (( key <= count )); then
                    TUI_MENU_INDEX=$(( key - 1 ))
                    return 0
                fi
                ;;
            *)
                for i in "${!items[@]}"; do
                    if [[ "${key,,}" == "${TUI_MENU_KEYS[$i]:-}" ]]; then
                        TUI_MENU_INDEX=$i
                        return 0
                    fi
                done
                [[ "${TUI_MENU_CANCEL_UNKNOWN:-0}" == 1 ]] && return 1
                ;;
        esac
        [[ -t 1 ]] && printf '\033[%dA\r' "$(( count + 2 ))"
    done
}

# Menu dawniej czytane całymi wierszami: terminal używa tui_menu, a potok
# zachowuje numery wielocyfrowe i puste anulowanie. Sekwencje strzałek w atrapach
# również trafiają do wspólnego dekodera. Kod 2 oznacza błędny wiersz.
# shellcheck disable=SC2034  # wynik czyta skrypt wywołujący
tui_menu_lines() {
    if [[ -t 0 ]]; then
        tui_menu "$@"
        return $?
    fi
    local line i
    IFS= read -r line || return 1
    line="$(trim "$line")"
    [[ -n "$line" ]] || return 1
    if [[ "$line" =~ ^[0-9]+$ ]]; then
        if (( 10#$line >= 1 && 10#$line < $# )); then
            TUI_MENU_INDEX=$(( 10#$line - 1 ))
            return 0
        fi
        return 2
    fi
    for (( i=0; i < $# - 1; i++ )); do
        if [[ "${line,,}" == "${TUI_MENU_KEYS[$i]:-}" ]]; then
            TUI_MENU_INDEX=$i
            return 0
        fi
    done
    case "$line" in
        *$'\e'*|*[jk]*) tui_menu "$@" <<<"$line" ;;
        q|Q) return 1 ;;
        *) return 2 ;;
    esac
}

# Potwierdzenie przez wspólne menu; Enter zachowuje domyślną odpowiedź.
# Esc/EOF i nieznany klawisz anulują. Limit czasu dotyczy całego wyboru,
# nie pojedynczego naciśnięcia — strzałki nie przedłużają próby monitora.
confirm() {
    local question="$1" default="${2:-N}" hint="[y/N]" initial=1
    local -a TUI_MENU_KEYS=(y n)
    local TUI_MENU_CANCEL_UNKNOWN=1 TUI_MENU_CHECKLIST=0 TUI_MENU_CAPTURE_DIGITS=0
    if [[ "$default" == "Y" ]]; then hint="[Y/n]"; initial=0; fi
    printf '  %s %s:\n' "$question" "$hint" >&2
    tui_menu "$initial" "Yes [y]" "No [n]" >&2 || return 1
    (( TUI_MENU_INDEX == 0 ))
}

# Zapis jednowartościowego pliku warstwy maszynowej (data/*.dat) — atomowo
# (tmp + mv), bo moduły waybara czytają te pliki co sekundę i nie mogą trafić
# na zapis w połowie. Jedno miejsce dla wszystkich menu TUI.
write_dat() {
    local file="$1" value="$2" tmp
    mkdir -p "$(dirname "$file")"
    tmp="$(mktemp "${file}.XXXXXX")" || { echo -e "  ${RED}✗ mktemp failed.${NC}"; return 1; }
    printf '%s\n' "$value" > "$tmp"
    chmod 644 "$tmp"   # mktemp daje 600 — zachowaj zwykłe prawa (jak inne data/*.dat)
    mv "$tmp" "$file"
}
