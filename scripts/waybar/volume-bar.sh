#!/bin/bash

# =============================================
#   archenemy - volume-bar.sh
#   Pasek głośności dla waybara (moduł custom/volumebar, return-type json).
#   Zamiast tekstu "{icon} {volume}%" rysuje pasek wypełnienia z liczbą %.
#
#   Styl paska bierze z data/volume-bar-style.dat (przełączalny na żywo w
#   TUI Super+A → [v] volume bar); fallback "segments":
#     segments → ▮▮▮▮▮▮▯▯▯▯   blocks → ██████░░░░
#   Pasek ma stałą liczbę komórek (CELLS); wypełnienie liczone z procentu
#   z capem 100% — boost >100% daje pełny pasek + realną liczbę (klasa boost).
#
#   Reaguje na zmiany: interval:1 (backstop: pavucontrol/BT) + signal 10
#   (klawisze sprzętowe i scroll wołają pkill -RTMIN+10 waybar). Ten sam
#   backstop 1s wykrywa też wpięcie/odpięcie słuchawek — Active Port
#   domyślnego sinka z pactl podmienia ikonę głośnika na słuchawki i z
#   powrotem, bez osobnego triggera.
#
#   Użycie: volume-bar.sh   (woła waybar; wypisuje jedną linię JSON)
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
STYLE_DAT="$ARCHENEMY_DIR/data/volume-bar-style.dat"
SINK="@DEFAULT_AUDIO_SINK@"
CELLS=10

STYLE="segments"
[[ -f "$STYLE_DAT" ]] && STYLE="$(<"$STYLE_DAT")"

# ─── Odczyt głośności ─────────────────────────────────────────────────────────
# wpctl get-volume: "Volume: 0.60" albo "Volume: 0.60 [MUTED]"
raw="$(wpctl get-volume "$SINK" 2>/dev/null)"
vol="$(printf '%s' "$raw" | awk '{print $2}')"           # 0.60
[[ "$vol" =~ ^[0-9]+([.][0-9]+)?$ ]] || vol="0"
muted=0
[[ "$raw" == *"[MUTED]"* ]] && muted=1

# Procent (round), np. 0.60 → 60, 1.5 → 150
pct="$(awk -v v="$vol" 'BEGIN { printf "%d", (v*100)+0.5 }')"

# Wypełnienie paska: procent z capem 100% na CELLS komórek
fill_pct="$pct"; (( fill_pct > 100 )) && fill_pct=100
filled="$(awk -v p="$fill_pct" -v c="$CELLS" 'BEGIN { printf "%d", (p*c/100)+0.5 }')"
(( filled > CELLS )) && filled=$CELLS
(( filled < 0 )) && filled=0
empty=$(( CELLS - filled ))

# ─── Render paska wg stylu ────────────────────────────────────────────────────
repeat() { local n="$1" ch="$2" out=""; while (( n-- > 0 )); do out+="$ch"; done; printf '%s' "$out"; }

case "$STYLE" in
    blocks)
        bar="$(repeat "$filled" '█')$(repeat "$empty" '░')"
        ;;
    *)  # segments (domyślny)
        STYLE="segments"
        bar="$(repeat "$filled" '▮')$(repeat "$empty" '▯')"
        ;;
esac

# ─── Wykrycie słuchawek ───────────────────────────────────────────────────────
# Active Port domyślnego sinka z pactl (pipewire-pulse) — nazwy portów
# słuchawkowych zawierają "headphone"/"headset" (analog i USB); reszta
# (speaker, hdmi, line-out...) to głośniki.
headphones=0
default_sink="$(pactl get-default-sink 2>/dev/null)"
if [[ -n "$default_sink" ]]; then
    active_port="$(pactl list sinks 2>/dev/null | awk -v target="$default_sink" '
        /^Sink #/            { name="" }
        /^\tName: /           { name=$2 }
        name==target && /^\tActive Port: / { print $3 }
    ' | tail -n1)"
    [[ "$active_port" =~ [Hh]eadphone|[Hh]eadset ]] && headphones=1
fi

# ─── Ikona głośnika + klasa ───────────────────────────────────────────────────
if (( muted )); then
    icon="󰖁"; class="muted"
elif (( headphones )); then
    icon="󰋋"
    if (( pct > 100 )); then class="boost"; else class="normal"; fi
else
    if   (( pct == 0 ));  then icon="󰕿"
    elif (( pct < 50 ));  then icon="󰖀"
    else                       icon="󰕾"
    fi
    if (( pct > 100 )); then class="boost"; else class="normal"; fi
fi

# ─── Wyjście JSON (return-type: json) ─────────────────────────────────────────
# Tekst: ikona + pasek + procent. Wartości bez znaków łamiących JSON.
# Procent wyrównany do 3 znaków (%3d): etykieta ma stałą długość niezależnie
# od 0% / 60% / 150%, więc moduł nie zmienia szerokości przy kręceniu głośnością
# — to (a nie sztywna szerokość w px w CSS) trzyma obszar scrolla na miejscu.
printf '{"text":"%s %s %3d%%","class":"%s","percentage":%d,"tooltip":"Volume: %d%%"}\n' \
    "$icon" "$bar" "$pct" "$class" "$fill_pct" "$pct"
