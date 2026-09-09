#!/bin/bash

# =============================================
#   archenemy - volume-bar.sh
#   Pasek głośności dla waybara (moduł custom/volumebar, return-type json).
#   Zamiast tekstu "{icon} {volume}%" rysuje pasek wypełnienia z liczbą %.
#
#   Styl paska bierze z data/volume-bar-style.dat (przełączalny na żywo w
#   TUI Super+A → [v] volume bar). Trzy style, fallback "line":
#     line  → ━━━━━━────         (domyślny: ciągła cienka kreska, ~2 px kreski)
#     ticks → ▮▮▮▮▮▮▯▯▯▯         (segmentowany wskaźnik)
#     solid → ▬▬▬▬▬▬▬▬▬▬▬▬────────  (gruby blok głośności na cienkiej linii,
#                                 dłuższy: 20 komórek zamiast 10 — jedna
#                                 komórka = dokładnie 5%, czyli jeden tick
#                                 scrolla przesuwa pasek o jedną komórkę)
#   Warstwa maszynowa (.dat) jest poza gitem i po aktualizacji repo może
#   trzymać nazwę sprzed 2026-09-03 ("segments"/"blocks" — style wycofane jako
#   za grube). KAŻDA nierozpoznana wartość spada na "line", więc stary plik
#   daje nowy domyślny wygląd, a nie pusty ani surowy pasek.
#   Pasek ma stałą liczbę komórek (CELLS — zależną od stylu); wypełnienie
#   liczone z procentu z capem 100% — boost >100% daje pełny pasek + realną
#   liczbę (klasa boost).
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

# Pion ikony słuchawek. Zgłoszenie właściciela 2026-09-04: glif słuchawek 󰋋
# siedzi w Iosevce NIŻEJ niż głośnik 󰕾 i mikrofon 󰍬 — ikony nie stoją w jednej
# linii. Korekta idzie pango-spanem na SAMYM glifie, nie CSS-em: reguła w
# style.css ruszyłaby cały moduł (pasek i procent razem z ikoną), a to różnica
# metryk jednego glifu. Jednostka `rise` = 1/1024 punktu: dodatnia w górę,
# ujemna w dół, 0 = bez korekty (wtedy skrypt nie owija ikony w ogóle).
# 512 ≈ ½ pt ≈ 0,7 px przy foncie 12 px — pierwsza kalibracja, dostrajasz TU.
ICON_RISE_HEADPHONES=512

STYLE="line"
[[ -f "$STYLE_DAT" ]] && STYLE="$(<"$STYLE_DAT")"
STYLE="${STYLE//[[:space:]]/}"   # plik pisany ręcznie potrafi mieć \n, spacje, CR

# Długość paska i znaki wypełnienia — JEDNO miejsce na styl, bo CELLS musi być
# znane przed liczeniem wypełnienia, a znaki dopiero przy rysowaniu.
# Nierozpoznana wartość (w tym nazwy stylów wycofanych) spada na "line".
case "$STYLE" in
    ticks) CELLS=10; CH_FILL='▮'; CH_EMPTY='▯' ;;
    solid) CELLS=20; CH_FILL='▬'; CH_EMPTY='─' ;;
    *)     CELLS=10; CH_FILL='━'; CH_EMPTY='─' ;;
esac

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

bar="$(repeat "$filled" "$CH_FILL")$(repeat "$empty" "$CH_EMPTY")"

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
    # Jedyna ikona z korektą pionu (patrz ICON_RISE_HEADPHONES na górze).
    if (( ICON_RISE_HEADPHONES != 0 )); then
        icon="<span rise='${ICON_RISE_HEADPHONES}'>󰋋</span>"
    else
        icon="󰋋"
    fi
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
