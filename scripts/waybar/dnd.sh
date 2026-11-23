#!/usr/bin/env bash
# =============================================
#   archenemy - dnd.sh
#   Dzwonek „nie przeszkadzać” w waybarze (moduł custom/dnd, return-type
#   json, 2026-11-23). Kliknięcie przełącza tryb mako "do-not-disturb";
#   sekcja [mode=do-not-disturb] w rices/*/mako/config chowa wtedy
#   powiadomienia (invisible=1), a [mode=do-not-disturb urgency=critical]
#   zostawia widoczne krytyczne (błędy profilu, bateria, alarmy).
#
#   Stan czytany WYŁĄCZNIE z "makoctl mode" (lista trybów, jeden na linię —
#   makoctl.c, run_mode, mako 1.11.0) — żadnego własnego pliku stanu, który
#   rozjechałby się z makiem (restart maka zaczyna od samego "default").
#   Przełączanie przez -a/-r, nie -t: -t jest dopiero od mako 1.9. Sukces =
#   stan odczytany po zmianie, nie kod wyjścia makoctl.
#
#   Mako nie działa (albo brak makoctl) → ikona "unavailable", kod 0 i ZERO
#   wywołań makoctl: mako ma plik aktywacji D-Bus (fr.emersion.mako.service),
#   więc samo makoctl potrafiłoby je uruchomić — pasek nie startuje demona.
#   Każde makoctl z limitem czasu (zawieszony D-Bus nie blokuje paska).
#
#   Odświeżanie: config ma "signal": 13 (toggle sam woła pkill -RTMIN+13,
#   więc skrót czy TUI odświeżą pasek tą samą drogą) i "interval": 10 jako
#   backstop — waybar startuje w hyprland.lua PRZED makiem, a restart maka
#   zeruje tryby; bez interwału ikona „niedostępne” wisiałaby do kliknięcia.
#
#   Użycie: dnd.sh          (woła waybar; jedna linia JSON, kod zawsze 0)
#           dnd.sh state    (notify|dnd|unavailable)
#           dnd.sh toggle   (przełącza; kod 0 = stan odczytany po zmianie
#                            jest odwrotny, 1 = mako nie działa / nie przyjęło)
# =============================================

set -uo pipefail
export LC_ALL=C

MODE=do-not-disturb
SIGNAL=13
MAKO_TIMEOUT=2

GLYPH_NOTIFY="󰂚"        # U+F009A nf-md-bell
GLYPH_DND="󰂛"           # U+F009B nf-md-bell_off
GLYPH_UNAVAILABLE="󱏨"   # U+F13E8 nf-md-bell_cancel_outline

# Mako tego użytkownika działa (pgrep, procps-ng z requirements) i jest makoctl.
mako_available() {
    command -v makoctl >/dev/null 2>&1 || return 1
    pgrep -u "$(id -u)" -x mako >/dev/null 2>&1
}

mako_ctl() {
    timeout "$MAKO_TIMEOUT" makoctl "$@" 2>/dev/null
}

# notify|dnd|unavailable — z listy trybów, dokładne dopasowanie linii.
dnd_state() {
    local modes line
    if ! mako_available || ! modes="$(mako_ctl mode)"; then
        printf 'unavailable\n'
        return
    fi
    while IFS= read -r line; do
        if [[ "$line" == "$MODE" ]]; then
            printf 'dnd\n'
            return
        fi
    done <<< "$modes"
    printf 'notify\n'
}

dnd_toggle() {
    local before after want rc=1
    before="$(dnd_state)"
    case "$before" in
        notify) want=dnd;    mako_ctl mode -a "$MODE" >/dev/null ;;
        dnd)    want=notify; mako_ctl mode -r "$MODE" >/dev/null ;;
        *)      want="" ;;
    esac
    if [[ -n "$want" ]]; then
        after="$(dnd_state)"
        [[ "$after" == "$want" ]] && rc=0
    fi
    # Ten sam sygnał co w configu; bez działającego waybara pkill daje 1 — bez znaczenia.
    pkill "-RTMIN+$SIGNAL" -x waybar >/dev/null 2>&1
    return "$rc"
}

render() {
    local text class tooltip
    case "$(dnd_state)" in
        dnd)
            text="$GLYPH_DND"; class=dnd
            tooltip='Do not disturb: on (critical notifications still show)\nClick: show notifications' ;;
        notify)
            text="$GLYPH_NOTIFY"; class=notify
            tooltip='Notifications: on\nClick: do not disturb' ;;
        *)
            text="$GLYPH_UNAVAILABLE"; class=unavailable
            tooltip='Notifications: mako is not running\nClick: check again' ;;
    esac
    # Same stałe napisy (bez cudzysłowów i ukośników) — JSON składany ręcznie.
    printf '{"text":"%s","alt":"%s","class":"%s","tooltip":"%s"}\n' "$text" "$class" "$class" "$tooltip"
}

case "${1:-}" in
    state)  dnd_state ;;
    toggle) dnd_toggle; exit $? ;;
    *)      render ;;
esac
exit 0
