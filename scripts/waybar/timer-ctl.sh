#!/bin/bash

# =============================================
#   archenemy - timer-ctl.sh
#   Sterowanie timerem waybara (moduł custom/timer). Woła to pasek
#   (kliknięcia i scroll) oraz TUI Super+A → [t] po zmianie domyślnego czasu.
#
#   Użycie:
#     timer-ctl.sh toggle       LPM  — start / pauza / wznów / skasuj alarm
#     timer-ctl.sh reset        PPM  — z powrotem na domyślny czas, stop
#     timer-ctl.sh adjust +1    scroll ↑ — +1 minuta
#     timer-ctl.sh adjust -1    scroll ↓ — -1 minuta
#
#   Scroll działa TYLKO gdy timer stoi albo jest zapauzowany (decyzja
#   właściciela 2026-09-04) — podkręcanie biegnącego odliczania w locie
#   byłoby mylące, więc w stanie running to świadomy no-op.
#
#   Stan trzyma data/timer-state.dat (zapis atomowy w bibliotece). Po każdej
#   zmianie leci signal 11 do waybara = pasek przerysowuje się natychmiast,
#   bez czekania na sekundowy interval.
# =============================================

set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/timer-state.sh
source "$HOME/archenemy/scripts/waybar/lib/timer-state.sh"

CMD="${1:-}"
ARG="${2:-}"

timer_load_state
now="$(date +%s)"
duration_secs=$(( $(timer_duration_minutes) * 60 ))

case "$CMD" in
    toggle)
        case "$TIMER_STATUS" in
            running)
                # Pauza: zamrażamy resztę policzoną z zegara ściennego.
                TIMER_REMAINING=$(( TIMER_END - now ))
                (( TIMER_REMAINING < 0 )) && TIMER_REMAINING=0
                TIMER_END=0
                TIMER_STATUS="paused"
                ;;
            paused|stopped)
                # Start/wznowienie. Zero sekund nie da się wystartować —
                # wracamy wtedy do domyślnego czasu z TUI.
                (( TIMER_REMAINING <= 0 )) && TIMER_REMAINING="$duration_secs"
                TIMER_END=$(( now + TIMER_REMAINING ))
                TIMER_STATUS="running"
                TIMER_NOTIFIED=0
                ;;
            finished)
                # Kliknięcie na odliczonym timerze = zgaś alarm i ustaw od nowa.
                TIMER_STATUS="stopped"
                TIMER_REMAINING="$duration_secs"
                TIMER_END=0
                TIMER_NOTIFIED=0
                ;;
        esac
        ;;
    reset)
        TIMER_STATUS="stopped"
        TIMER_REMAINING="$duration_secs"
        TIMER_END=0
        TIMER_NOTIFIED=0
        ;;
    adjust)
        # Tylko przy zatrzymanym/zapauzowanym odliczaniu (patrz nagłówek).
        [[ "$TIMER_STATUS" == "stopped" || "$TIMER_STATUS" == "paused" ]] || exit 0
        case "$ARG" in
            +1|1) TIMER_REMAINING=$(( TIMER_REMAINING + 60 )) ;;
            -1)   TIMER_REMAINING=$(( TIMER_REMAINING - 60 )) ;;
            *)    echo "timer-ctl.sh: adjust wymaga +1 albo -1" >&2; exit 1 ;;
        esac
        # Dół 1 minuta (timer na zero jest bez sensu), góra jak w TUI.
        (( TIMER_REMAINING < 60 )) && TIMER_REMAINING=60
        (( TIMER_REMAINING > TIMER_MAX_MINUTES * 60 )) && TIMER_REMAINING=$(( TIMER_MAX_MINUTES * 60 ))
        ;;
    *)
        echo "Użycie: timer-ctl.sh {toggle|reset|adjust +1|adjust -1}" >&2
        exit 1
        ;;
esac

timer_save_state
pkill -RTMIN+11 waybar 2>/dev/null
exit 0
