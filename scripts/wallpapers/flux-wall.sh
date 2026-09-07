#!/bin/bash

# =============================================
#   archenemy - flux-wall.sh
#   Uruchamia/zatrzymuje flux-wall — tapetę liczoną shaderem na GPU
#   (src/flux-wall). Etap prototypu: uruchamiane RĘCZNIE do live-testu;
#   integracja z Super+W i przełącznikiem rice'ów przyjdzie po nim.
#
#   Użycie:
#     flux-wall.sh start [opcje flux-wall...]   start (paleta rice'a, --battery)
#     flux-wall.sh stop                         zatrzymaj
#     flux-wall.sh status                       działa? (kod 0/1)
#
#   Paleta: domyślnie milford-woda (rice dither-flux). Gdy binarki nie ma
#   (install.sh nie zbudował — brak kompilatora, błąd builda), skrypt kończy
#   się kodem 2 i NIC nie zmienia: tapeta zostaje w hyprpaper jak dotąd.
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
BIN="$ARCHENEMY_DIR/src/flux-wall/build/flux-wall"
SHADER="$ARCHENEMY_DIR/src/flux-wall/shaders/dither-flux.frag"
PALETTE="0F1A24,5C87A3,D8E6EE"   # milford-woda: góry, woda, piana
LOG="${XDG_RUNTIME_DIR:-/tmp}/flux-wall.log"

case "${1:-}" in
    start)
        shift
        if [[ ! -x "$BIN" ]]; then
            echo "flux-wall.sh: brak binarki $BIN — uruchom ./install/install.sh (krok flux-wall) albo 'make' w src/flux-wall" >&2
            exit 2
        fi
        [[ -f "$SHADER" ]] || { echo "flux-wall.sh: brak shadera $SHADER" >&2; exit 2; }
        pkill -x flux-wall 2>/dev/null
        # setsid: proces nie ginie z terminalem, z którego go odpalono do testu.
        setsid "$BIN" -s "$SHADER" -p "$PALETTE" --battery -v "$@" >"$LOG" 2>&1 &
        sleep 0.5
        if pgrep -x flux-wall >/dev/null; then
            echo "flux-wall działa (log: $LOG)"
        else
            echo "flux-wall NIE wystartował — ostatnie linie logu:" >&2
            tail -5 "$LOG" >&2
            exit 3
        fi
        ;;
    stop)
        pkill -x flux-wall 2>/dev/null && echo "flux-wall zatrzymany" || echo "flux-wall nie działał"
        ;;
    status)
        pgrep -x flux-wall >/dev/null
        ;;
    *)
        echo "Użycie: flux-wall.sh start [opcje] | stop | status" >&2
        exit 1
        ;;
esac
