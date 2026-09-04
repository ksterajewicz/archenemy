#!/bin/bash

# =============================================
#   archenemy - timer.sh
#   Timer (odliczanie) dla waybara — moduł custom/timer, return-type json.
#   Osobna wyspa po prawej od zegara; opcjonalny, domyślnie WYŁĄCZONY.
#
#   Włączanie, domyślny czas i kolor tekstu: TUI Super+A → [t] timer
#   (pliki data/timer-*.dat, warstwa maszynowa poza gitem).
#
#   KOLOR IDZIE PRZEZ PANGO, NIE PRZEZ CSS: tekst jest owinięty w
#   <span color='#rrggbb'>, więc jest czerwony (albo dowolny wybrany w TUI)
#   niezależnie od rice'a i bez dotykania style.css. Pigułka pod spodem
#   zostaje w palecie rice'a (CSS), zmienia się tylko kolor cyfr.
#
#   Wyłączony w TUI = pusty "text" → waybar chowa moduł, a wyśrodkowany
#   zegar wraca dokładnie na środek. Klasa "off" dodatkowo zeruje pigułkę
#   w CSS, gdyby pusty moduł mimo wszystko został narysowany.
#
#   Sterowanie (waybar woła timer-ctl.sh): LPM start/pauza, PPM reset,
#   scroll ±1 min. Odświeżanie: interval 1 (odliczanie musi tykać) + signal 11
#   (natychmiastowy push po kliknięciu i po zmianach w TUI).
#
#   Użycie: timer.sh   (woła waybar; wypisuje jedną linię JSON)
# =============================================

set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/timer-state.sh
source "$HOME/archenemy/scripts/waybar/lib/timer-state.sh"

# Ikony stanu — glify Nerd Font z tego samego bloku MDI co reszta paska
# (󰓅 profil, 󰍬 mikrofon, 󰕾 głośność). Gdyby font ich nie miał, podmieniasz
# je TU, w jednym miejscu.
ICON_IDLE="󰔟"     # klepsydra: stoi albo odlicza
ICON_PAUSED="󰏤"   # pauza
ICON_DONE="󰀦"     # alarm: odliczone do zera

# ─── Wyłączony w TUI = moduł znika z paska ────────────────────────────────────
if ! timer_enabled; then
    printf '{"text":"","class":"off"}\n'
    exit 0
fi

timer_load_state

# ─── Dobiegnięcie do zera ─────────────────────────────────────────────────────
# Wykryć może to TYLKO ten skrypt (odpalany co sekundę) — kliknięcia lecą
# przez timer-ctl.sh, a nic nie woła go „samo z siebie" o właściwej porze.
# Dlatego render wyjątkowo ZAPISUJE stan: przejście running → finished plus
# jednorazowe powiadomienie (flaga notified w pliku stanu; bez niej mako
# dostawałoby popup co sekundę).
if [[ "$TIMER_STATUS" == "running" ]] && (( $(timer_remaining_now) <= 0 )); then
    TIMER_STATUS="finished"
    TIMER_REMAINING=0
    TIMER_END=0
    if (( TIMER_NOTIFIED == 0 )); then
        TIMER_NOTIFIED=1
        command -v notify-send &>/dev/null && \
            notify-send -u critical "archenemy" "Timer finished."
    fi
    timer_save_state
fi

remaining="$(timer_remaining_now)"
clock="$(timer_format "$remaining")"

# ─── Ikona + tooltip wg stanu ─────────────────────────────────────────────────
case "$TIMER_STATUS" in
    running)  icon="$ICON_IDLE";   state_text="running"  ;;
    paused)   icon="$ICON_PAUSED"; state_text="paused"   ;;
    finished) icon="$ICON_DONE";   state_text="finished" ;;
    *)        icon="$ICON_IDLE";   state_text="stopped"  ;;
esac

# ─── Wyjście JSON (return-type: json) ─────────────────────────────────────────
# Tekst w markupie pango — waybar renderuje etykiety przez set_markup, tak samo
# jak przygaszone sekundy zegara. Kolor jest zwalidowany w bibliotece
# (^#[0-9a-fA-F]{6}$), więc do markupu nie trafi nic, co mogłoby go rozbić.
printf '{"text":"<span color='"'"'%s'"'"'>%s %s</span>","class":"%s","tooltip":"Timer: %s — %s\\nLMB start/pause · RMB reset · scroll ±1 min (stopped or paused)"}\n' \
    "$(timer_color)" "$icon" "$clock" "$TIMER_STATUS" "$state_text" "$clock"
