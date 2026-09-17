#!/bin/bash

# =============================================
#   archenemy - flux-wall.sh
#   Steruje flux-wall — tapetą liczoną shaderem na GPU (src/flux-wall).
#
#   Dwa źródła prawdy, w tej kolejności:
#     1. WYBÓR UŻYTKOWNIKA — data/flux-wall.dat (warstwa maszynowa, Super+W):
#        "off"    → animacja wyłączona wszędzie,
#        "<nazwa>" → animacja <nazwa> (src/flux-wall/shaders/<nazwa>.frag)
#                    w KAŻDYM ricu, w jego palecie,
#        brak pliku → zachowanie domyślne rice'a (pkt 2).
#     2. DEKLARACJA RICE'A — rices/<rice>/flux-wall.conf:
#        FLUX_WALL_PALETTE   "bg,ink,acc" (hex) — paleta tego rice'a,
#        FLUX_WALL_SHADER    domyślny shader (ścieżka względem repo),
#        FLUX_WALL_ARGS      argumenty (np. --battery),
#        FLUX_WALL_AUTOSTART 1 = animacja domyślnie włączona w tym ricu
#                            (bez wyboru użytkownika), 0 = domyślnie wyłączona.
#        Rice bez pliku: paleta domyślna binarki, autostart 0.
#
#   WIZUALIZACJA MUZYKI — bez przełącznika (decyzja właściciela 2026-09-08):
#   audio włącza sam flux-wall, gdy shader deklaruje `#pragma flux audio 1`.
#   Wrapper podaje tylko nazwę monitora domyślnego sinku z pactl jako fallback
#   po @DEFAULT_MONITOR@. Nasłuch to WYŁĄCZNIE wyjście (to, co słychać).
#
#   Użycie:
#     flux-wall.sh autostart | restore   z hyprland.lua i z przełącznika rice'ów:
#                                        stop starej instancji, start wg reguł
#                                        wyżej. CICHY: nic do zrobienia = kod 0.
#     flux-wall.sh select <nazwa>        Super+W: zapisz wybór i zastosuj
#     flux-wall.sh off                   Super+W: wyłącz i zapamiętaj
#     flux-wall.sh list                  nazwy dostępnych animacji (po linii)
#     flux-wall.sh list-audio            nazwy animacji będących wizualizacją muzyki
#     flux-wall.sh start [opcje]         jak restore, ale głośno; opcje → flux-wall
#     flux-wall.sh stop | status
#
#   Kody: 0 ok · 1 użycie/zła nazwa · 2 brak binarki · 3 start nieudany (log) ·
#         4 nic do uruchomienia (off / rice bez autostartu)
#
#   Fallback jest w architekturze, nie tu: hyprpaper działa ZAWSZE, a flux-wall
#   rysuje na warstwie `bottom` — nad nim, pod oknami.
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
BIN="$ARCHENEMY_DIR/src/flux-wall/build/flux-wall"
SHADERS_DIR="$ARCHENEMY_DIR/src/flux-wall/shaders"
CURRENT_RICE_FILE="$ARCHENEMY_DIR/.current_rice"
DATA_DIR="$ARCHENEMY_DIR/data"
CHOICE_DAT="$DATA_DIR/flux-wall.dat"
LOG="${XDG_RUNTIME_DIR:-/tmp}/flux-wall.log"

# ─── odczyt konfiguracji ──────────────────────────────────────────────────────

FLUX_WALL_PALETTE=""; FLUX_WALL_SHADER=""; FLUX_WALL_ARGS=""; FLUX_WALL_AUTOSTART=0

load_rice_conf() {
    local rice conf
    [[ -f "$CURRENT_RICE_FILE" ]] || return 1
    rice="$(<"$CURRENT_RICE_FILE")"; rice="${rice//[[:space:]]/}"
    [[ -n "$rice" ]] || return 1
    conf="$ARCHENEMY_DIR/rices/$rice/flux-wall.conf"
    [[ -f "$conf" ]] || return 1
    # shellcheck disable=SC1090  # ścieżka zależy od bieżącego rice'a; plik jest w repo
    source "$conf"
    return 0
}

read_choice() {   # → "off" | nazwa | "" (brak wyboru)
    local c=""
    [[ -f "$CHOICE_DAT" ]] && c="$(<"$CHOICE_DAT")"
    echo "${c//[[:space:]]/}"
}

write_choice() {  # zapis atomowy tmp+mv (wzorzec repo)
    local tmp
    mkdir -p "$DATA_DIR"
    tmp=$(mktemp "$CHOICE_DAT.XXXXXX") || return 1
    printf '%s\n' "$1" > "$tmp"; chmod 644 "$tmp"; mv "$tmp" "$CHOICE_DAT"
}

shader_path() {   # nazwa → ścieżka; pusto, gdy nie ma pliku
    local name="$1"
    # Dozwolone: małe litery, cyfry, myślnik i apostrof (dither-orb-spinnin' —
    # decyzja właściciela 2026-09-17c); nigdy `/` ani `..` — nazwa staje się ścieżką.
    [[ "$name" =~ ^[a-z0-9\'-]+$ ]] || return 1
    [[ -f "$SHADERS_DIR/$name.frag" ]] && echo "$SHADERS_DIR/$name.frag"
}

list_shaders() {  # nazwy dostępnych animacji, po jednej na linię (bez .frag)
    local f
    for f in "$SHADERS_DIR"/*.frag; do
        [[ -f "$f" ]] || continue
        f="${f##*/}"; echo "${f%.frag}"
    done
}

# Wizualizacje muzyki: shader (frag albo update) deklaruje `#pragma flux audio 1`.
is_audio_shader() {  # nazwa → 0 gdy wizualizacja
    local n="$1"
    grep -qs '^#pragma flux audio 1' "$SHADERS_DIR/$n.update.glsl" "$SHADERS_DIR/$n.frag"
}

list_audio_shaders() {
    local n
    while IFS= read -r n; do is_audio_shader "$n" && echo "$n"; done < <(list_shaders)
}

# Nazwa monitora domyślnego sinku jako fallback dla flux-walla (który najpierw
# próbuje @DEFAULT_MONITOR@). Binarka sprzed wizualizacji (git pull bez
# install.sh/make) nie zna --audio-device — wtedy nic nie podajemy.
audio_args() {      # ustawia AUDIO_ARGS
    AUDIO_ARGS=()
    local sink
    command -v pactl >/dev/null 2>&1 || return 0
    "$BIN" --help 2>&1 | grep -q -- '--audio-device' || return 0
    sink="$(pactl get-default-sink 2>/dev/null)"
    [[ -n "$sink" ]] && AUDIO_ARGS=("--audio-device=${sink}.monitor")
}

# Ustala, czy i z czym startować. Ustawia SHADER i PALETTE_ARGS.
resolve() {
    local choice
    choice="$(read_choice)"
    load_rice_conf || true
    PALETTE_ARGS=()
    [[ -n "$FLUX_WALL_PALETTE" ]] && PALETTE_ARGS=(-p "$FLUX_WALL_PALETTE")

    if [[ "$choice" == "off" ]]; then
        return 1
    elif [[ -n "$choice" ]]; then
        SHADER="$(shader_path "$choice")" || SHADER=""
        if [[ -z "$SHADER" ]]; then
            echo "flux-wall.sh: wybrana animacja '$choice' nie istnieje — wracam do domyślnej rice'a" >&2
            SHADER=""
        fi
    fi
    if [[ -z "${SHADER:-}" ]]; then
        # brak wyboru (albo wybór nieistniejący): domyślne zachowanie rice'a
        [[ "$FLUX_WALL_AUTOSTART" == "1" && -n "$FLUX_WALL_SHADER" ]] || return 1
        SHADER="$ARCHENEMY_DIR/$FLUX_WALL_SHADER"
        [[ -f "$SHADER" ]] || return 1
    fi
    return 0
}

# Zabij i POCZEKAJ, aż proces naprawdę zniknie — do_start startuje nową
# instancję zaraz po tym wywołaniu; bez czekania stara i nowa nakładały się
# na tej samej powierzchni Wayland (ten sam wyścig, który miał waybar).
do_stop() {
    pkill -x flux-wall 2>/dev/null
    for _ in $(seq 1 20); do
        pgrep -x flux-wall >/dev/null || return 0
        sleep 0.1
    done
    pkill -9 -x flux-wall 2>/dev/null
}

do_start() {
    local quiet="$1"; shift
    if [[ ! -x "$BIN" ]]; then
        [[ "$quiet" == quiet ]] && exit 0
        echo "flux-wall.sh: brak binarki $BIN — uruchom ./install/install.sh (krok [9.6]) albo 'make' w src/flux-wall" >&2
        exit 2
    fi
    if ! resolve; then
        do_stop
        [[ "$quiet" == quiet ]] && exit 0
        echo "flux-wall.sh: nic do uruchomienia (animacja wyłączona albo rice bez autostartu; Super+W → Animation)" >&2
        exit 4
    fi
    do_stop
    audio_args
    # shellcheck disable=SC2086  # FLUX_WALL_ARGS to celowo lista argumentów
    setsid "$BIN" -s "$SHADER" "${PALETTE_ARGS[@]}" "${AUDIO_ARGS[@]}" $FLUX_WALL_ARGS "$@" >"$LOG" 2>&1 &
    sleep 0.5
    if pgrep -x flux-wall >/dev/null; then
        [[ "$quiet" == quiet ]] || echo "flux-wall działa: $(basename "$SHADER" .frag) (log: $LOG)"
        exit 0
    fi
    [[ "$quiet" == quiet ]] && exit 0
    echo "flux-wall NIE wystartował — ostatnie linie logu:" >&2
    tail -5 "$LOG" >&2
    exit 3
}

case "${1:-}" in
    autostart|restore) shift; do_start quiet "$@" ;;
    start)             shift; do_start loud "$@" ;;
    select)
        name="${2:-}"
        if [[ -z "$name" ]] || ! shader_path "$name" >/dev/null; then
            echo "flux-wall.sh: nieznana animacja '${name}'. Dostępne: $(list_shaders | tr '\n' ' ')" >&2
            exit 1
        fi
        write_choice "$name" || exit 1
        exec "$0" start
        ;;
    off)
        write_choice off || exit 1
        do_stop && echo "animacja wyłączona" || echo "animacja wyłączona (nie działała)"
        ;;
    list)      list_shaders ;;
    list-audio) list_audio_shaders ;;
    stop)      do_stop && echo "flux-wall zatrzymany" || echo "flux-wall nie działał" ;;
    status)    pgrep -x flux-wall >/dev/null ;;
    *)         echo "Użycie: flux-wall.sh autostart|restore | select <nazwa> | off | list | list-audio | start [opcje] | stop | status" >&2; exit 1 ;;
esac
