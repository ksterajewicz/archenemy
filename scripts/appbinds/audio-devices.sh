#!/bin/bash
# =============================================
#   archenemy - audio-devices.sh
#   Domyślne wyjście i wejście audio całego systemu: jedyna droga dla
#   Super+A → [o]. Mówi z PipeWire przez pactl (pipewire-pulse), tak jak
#   volume-bar.sh. Porty jednej karty (głośniki/gniazdo słuchawek), profile
#   i strumienie aplikacji zostają w pavucontrol.
#
#   Użycie:
#     audio-devices.sh list sink|source      nazwa<TAB>opis, po jednym na linię
#     audio-devices.sh current sink|source   nazwa domyślnego urządzenia
#     audio-devices.sh describe sink|source  opis domyślnego urządzenia
#     audio-devices.sh set sink|source NAZWA ustaw i sprawdź
#   Kody: 0 gotowe, 1 zły argument albo brak pactl/serwera, 2 serwer nie przyjął.
#   Sukces = odczytany stan (`pactl get-default-*`), nie kod wyjścia pactl.
# =============================================

set -uo pipefail

kind_ok() { [[ "${1:-}" == "sink" || "${1:-}" == "source" ]]; }

# Monitory wyjść (*.monitor) to nie mikrofony, więc nie ma ich na liście wejść.
list_devices() {
    LC_ALL=C pactl list "${1}s" 2>/dev/null | awk '
        /^(Sink|Source) #/ { name = "" }
        /^\tName: /        { name = substr($0, 8) }
        /^\tDescription: / {
            if (name != "" && name !~ /\.monitor$/) print name "\t" substr($0, 15)
        }'
}

current_device() { pactl "get-default-$1" 2>/dev/null; }

usage() { echo "usage: $(basename "$0") list|current|describe sink|source; set sink|source NAME" >&2; exit 1; }

command -v pactl >/dev/null 2>&1 || { echo "✗ pactl not found (package libpulse)" >&2; exit 1; }
cmd="${1:-}"; kind="${2:-}"
kind_ok "$kind" || usage
pactl info >/dev/null 2>&1 || { echo "✗ audio server is not responding (pipewire-pulse)" >&2; exit 1; }

case "$cmd" in
    list) list_devices "$kind" ;;
    current) current_device "$kind"; echo ;;
    describe)
        cur="$(current_device "$kind")"
        list_devices "$kind" | awk -F'\t' -v n="$cur" '$1 == n { print $2; found = 1 } END { if (!found) print n }'
        ;;
    set)
        name="${3:-}"
        [[ -n "$name" ]] || usage
        if ! list_devices "$kind" | cut -f1 | grep -Fqx -- "$name"; then
            echo "✗ no such device: $name" >&2
            exit 1
        fi
        pactl "set-default-$kind" "$name" 2>/dev/null
        got=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            got="$(current_device "$kind")"
            [[ "$got" == "$name" ]] && break
            sleep 0.1
        done
        if [[ "$got" != "$name" ]]; then
            echo "⚠ the audio server still reports '${got:-nothing}'" >&2
            exit 2
        fi
        # Grające strumienie przenosimy jawnie: aplikacja z zapamiętanym
        # urządzeniem nie poszłaby za nowym domyślnym. Nagrywania nie ruszamy,
        # bo flux-wall czyta monitor wyjścia i nie może trafić na mikrofon.
        moved=0
        if [[ "$kind" == "sink" ]]; then
            while read -r id _; do
                [[ -n "$id" ]] || continue
                pactl move-sink-input "$id" "$name" 2>/dev/null && moved=$((moved + 1))
            done < <(pactl list short sink-inputs 2>/dev/null)
            pkill -RTMIN+10 waybar 2>/dev/null
        fi
        if ((moved)); then echo "✓ default $kind set ($moved playing streams moved)"; else echo "✓ default $kind set"; fi
        ;;
    *) usage ;;
esac
