#!/bin/bash

# =============================================
#   archenemy - flux-wall.sh
#   Steruje flux-wall — tapetą liczoną shaderem na GPU (src/flux-wall).
#
#   Rice DEKLARUJE, że używa flux-wall, plikiem rices/<rice>/flux-wall.conf
#   (paleta, shader, argumenty). Brak pliku = rice zostaje przy hyprpaper.
#   Bieżący rice: .current_rice (zapisuje lib/switch-rice.sh).
#
#   Użycie:
#     flux-wall.sh autostart      z hyprland.lua rice'a i z przełącznika rice'ów:
#                                 zatrzymaj stary, uruchom dla bieżącego rice'a,
#                                 jeśli ma flux-wall.conf. CICHY: brak binarki lub
#                                 conf = kod 0 i nic — hyprpaper zostaje tapetą.
#     flux-wall.sh start [opcje]  jak autostart, ale głośno (do ręcznego testu);
#                                 opcje idą do flux-wall (np. -f 30, --once)
#     flux-wall.sh stop
#     flux-wall.sh status         działa? (kod 0/1)
#
#   Kody: 0 ok · 1 użycie · 2 brak binarki (install.sh nie zbudował) ·
#         3 flux-wall nie wystartował (log) · 4 bieżący rice nie ma flux-wall.conf
#
#   Fallback jest wbudowany w architekturę, nie w ten skrypt: hyprpaper działa
#   ZAWSZE (autostart każdego rice'a), a flux-wall rysuje na warstwie `bottom`,
#   czyli nad nim i pod oknami — gdy flux-wall padnie, widać tapetę hyprpapera.
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
BIN="$ARCHENEMY_DIR/src/flux-wall/build/flux-wall"
CURRENT_RICE_FILE="$ARCHENEMY_DIR/.current_rice"
LOG="${XDG_RUNTIME_DIR:-/tmp}/flux-wall.log"

# Konfiguracja z pliku rice'a — plik jest w repo (kontrolowany), source jest ok.
load_rice_conf() {
    local rice
    [[ -f "$CURRENT_RICE_FILE" ]] || return 1
    rice="$(<"$CURRENT_RICE_FILE")"
    rice="${rice//[[:space:]]/}"
    [[ -n "$rice" ]] || return 1
    CONF="$ARCHENEMY_DIR/rices/$rice/flux-wall.conf"
    [[ -f "$CONF" ]] || return 1
    FLUX_WALL_PALETTE=""; FLUX_WALL_SHADER=""; FLUX_WALL_ARGS=""
    # shellcheck disable=SC1090  # ścieżka zależy od bieżącego rice'a
    source "$CONF"
    [[ -n "$FLUX_WALL_PALETTE" && -n "$FLUX_WALL_SHADER" ]] || return 1
    SHADER="$ARCHENEMY_DIR/$FLUX_WALL_SHADER"
    [[ -f "$SHADER" ]] || return 1
    return 0
}

do_stop() { pkill -x flux-wall 2>/dev/null; }

do_start() {
    local quiet="$1"; shift
    if [[ ! -x "$BIN" ]]; then
        [[ "$quiet" == quiet ]] && exit 0
        echo "flux-wall.sh: brak binarki $BIN — uruchom ./install/install.sh (krok [9.6]) albo 'make' w src/flux-wall" >&2
        exit 2
    fi
    if ! load_rice_conf; then
        do_stop   # poprzedni rice mógł mieć flux-wall — nowy nie ma, więc zejść z ekranu
        [[ "$quiet" == quiet ]] && exit 0
        echo "flux-wall.sh: bieżący rice nie deklaruje flux-wall (brak rices/<rice>/flux-wall.conf)" >&2
        exit 4
    fi
    do_stop
    # setsid: proces nie ginie z terminalem ani z powłoką, która go odpaliła.
    # shellcheck disable=SC2086  # FLUX_WALL_ARGS to celowo lista argumentów
    setsid "$BIN" -s "$SHADER" -p "$FLUX_WALL_PALETTE" $FLUX_WALL_ARGS "$@" >"$LOG" 2>&1 &
    sleep 0.5
    if pgrep -x flux-wall >/dev/null; then
        [[ "$quiet" == quiet ]] || echo "flux-wall działa (rice $(<"$CURRENT_RICE_FILE"), log: $LOG)"
        exit 0
    fi
    [[ "$quiet" == quiet ]] && exit 0
    echo "flux-wall NIE wystartował — ostatnie linie logu:" >&2
    tail -5 "$LOG" >&2
    exit 3
}

case "${1:-}" in
    autostart) shift; do_start quiet "$@" ;;
    start)     shift; do_start loud "$@" ;;
    stop)      do_stop && echo "flux-wall zatrzymany" || echo "flux-wall nie działał" ;;
    status)    pgrep -x flux-wall >/dev/null ;;
    *)         echo "Użycie: flux-wall.sh autostart | start [opcje] | stop | status" >&2; exit 1 ;;
esac
