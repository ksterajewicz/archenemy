#!/usr/bin/env bash
# =============================================
#   archenemy - src/flux-wall/tools/render-previews.sh
#   Kadry podglądu animacji do menu Super+W → Animations/:
#   src/flux-wall/shaders/previews/<rice>/<animacja>.png (480x270, w repo).
#
#   Kadr ma wyglądać jak animacja na pulpicie przy grającej muzyce (decyzja
#   właściciela 2026-11-24, wariant 3A), więc jest liczony w rozdzielczości
#   EKRANU (1920x1080) i dopiero pomniejszany 4× (offscreen --downscale,
#   uśrednianie w świetle liniowym). Shadery mają elementy w pikselach
#   (cząstka 1 px, raster Bayera 8 px, poświata 9 px): kadr liczony wprost
#   w 256x144 miał ślady ~100× gęstsze niż na ekranie i słupki zlane w plamę
#   (audyt 2026-11-24, U11). 480 px to też pełna ostrość pola ikony rofi na
#   HiDPI (160 px × skala; miniatury tapet mają 320 px).
#
#   Narzędzie deweloperskie (jak offscreen — NIE uruchamia go install.sh):
#   odpal po dodaniu/zmianie shadera albo palety rice'a i zacommituj PNG-i.
#   Renderuje PRAWDZIWY shader tym samym engine.c co na żywo
#   (tools/offscreen, EGL surfaceless — llvmpipe wystarczy, bez ekranu):
#     * paleta: FLUX_WALL_PALETTE z rices/<rice>/flux-wall.conf (każdy rice
#       z tym plikiem; white-blue_beta go nie ma — brak kadrów, menu pokaże
#       wtedy zwykłą listę),
#     * dither: --dither gdy FLUX_WALL_DITHER=1, inaczej --no-dither — ale
#       tylko jeśli offscreen zna te flagi (jego usage wspomina --dither);
#       starszy offscreen dostaje dawne wywołanie bez nich,
#     * dźwięk: `--audio music` (wbudowany syntezator pełnego pasma: stopa,
#       werbel, bas, akord, hi-hat, szum różowy — widmo jak w gotowym miksie)
#       dla wizualizacji muzyki (`#pragma flux audio 1` we .frag albo
#       .update.glsl — ta sama reguła co flux-wall.sh list-audio), cisza dla
#       reszty; starszy offscreen bez `music` dostaje dawne `synth`,
#     * rozmiar: `-s 1920x1080 --downscale 4`, jeśli offscreen zna
#       --downscale; starszy — dawne 256x144 wprost,
#     * klatki: 30/s, a dla shaderów z `#pragma flux rate` ponad 120 — 60/s
#       (silnik robi najwyżej 4 kroki symulacji na klatkę; dither-rain ma
#       240 kroków/s i przy 30 klatkach/s leciałby o połowę wolniej),
#     * chwila kadru: shader cząstkowy (jest <nazwa>.update.glsl) —
#       1.5 × `#pragma flux life` (akumulator zanika z exp(-dt/life), po
#       1.5·life ma ~78% stanu ustalonego), w granicach 4..15 s; pragmy
#       `warmup` nie liczymy, bo offscreen jej nie używa (tylko --once na
#       żywo); jednoprzebiegowy — 6 s (spektrogram zdąży się zapełnić).
#
#   Użycie: render-previews.sh [-r RICE]... [-a ANIMACJA]... [-o KATALOG]
#     -r RICE      tylko ten rice (można powtarzać; domyślnie wszystkie z
#                  rices/*/flux-wall.conf)
#     -a ANIMACJA  tylko ta animacja (można powtarzać; domyślnie każdy
#                  shaders/*.frag; nazwa z apostrofem: -a "orb-spinnin'")
#     -o KATALOG   zapis gdzie indziej niż shaders/previews (do przeglądu)
#   Brak build/offscreen → `make -C src/flux-wall tools` robi to samo co
#   ręcznie. Kod 0 = wszystkie kadry zapisane.
# =============================================

set -uo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$FW/../.." && pwd)"
OFF="$FW/build/offscreen"
SHADERS="$FW/shaders"
OUT="$SHADERS/previews"
RENDER_SIZE="1920x1080"     # rozdzielczość liczenia = typowy ekran
DOWNSCALE=4                 # → 480x270 w repo
OLD_SIZE="256x144"          # offscreen bez --downscale

RICES=(); ANIMS=()
while (( $# )); do
    case "$1" in
        -r) RICES+=("${2:?-r wymaga nazwy rice}"); shift 2 ;;
        -a) ANIMS+=("${2:?-a wymaga nazwy animacji}"); shift 2 ;;
        -o) OUT="${2:?-o wymaga katalogu}"; shift 2 ;;
        -h|--help) sed -n '3,/^# =====/{/^# =====/d;p;}' "${BASH_SOURCE[0]}" | sed 's/^#   \{0,1\}//'; exit 0 ;;
        *) echo "render-previews.sh: nieznana opcja '$1' (zobacz --help)" >&2; exit 2 ;;
    esac
done

if [[ ! -x "$OFF" ]]; then
    echo "Brak $OFF — buduję: make -C src/flux-wall tools"
    make -C "$FW" tools >/dev/null || { echo "render-previews.sh: make tools padło" >&2; exit 1; }
fi

# Flagi ditheru tylko, gdy offscreen je zna. Usage idzie na stderr z kodem 2 —
# do zmiennej, nie `| grep -q`: przy pipefail kod 2 offscreena przykryłby
# trafienie grepa i flagi nigdy by nie poszły.
DITHER_FLAGS=0; SIZE_ARGS=(-s "$OLD_SIZE"); AUDIO_MODE=synth
usage_text="$("$OFF" --help 2>&1)"
[[ "$usage_text" == *--dither* ]] && DITHER_FLAGS=1
[[ "$usage_text" == *--downscale* ]] && SIZE_ARGS=(-s "$RENDER_SIZE" --downscale "$DOWNSCALE")
[[ "$usage_text" == *"synth|music"* ]] && AUDIO_MODE=music

if (( ${#RICES[@]} == 0 )); then
    for conf in "$REPO"/rices/*/flux-wall.conf; do
        [[ -f "$conf" ]] || continue
        r="${conf%/flux-wall.conf}"; RICES+=("${r##*/}")
    done
fi
if (( ${#ANIMS[@]} == 0 )); then
    for f in "$SHADERS"/*.frag; do
        [[ -f "$f" ]] || continue
        f="${f##*/}"; ANIMS+=("${f%.frag}")
    done
fi

# rices/<rice>/flux-wall.conf → "PALETA DITHER" (podpowłoka: zmienne pliku
# nie wyciekają między rice'ami; plik jest w repo, jak w flux-wall.sh).
rice_conf() {
    (
        FLUX_WALL_PALETTE=""; FLUX_WALL_DITHER=0
        # shellcheck disable=SC1090  # ścieżka zależy od rice'a; plik jest w repo
        source "$1" >/dev/null 2>&1
        printf '%s %s\n' "$FLUX_WALL_PALETTE" "${FLUX_WALL_DITHER:-0}"
    )
}

is_audio() {     # ta sama reguła co flux-wall.sh is_audio_shader
    grep -qs '^#pragma flux audio 1' "$SHADERS/$1.update.glsl" "$SHADERS/$1.frag"
}

frame_fps() {    # klatki na sekundę liczenia (patrz nagłówek)
    local rate
    rate=$(sed -n 's/^#pragma flux rate[[:space:]]\{1,\}\([0-9.]\{1,\}\).*/\1/p' "$SHADERS/$1.update.glsl" 2>/dev/null | head -n1)
    awk -v r="${rate:-60}" 'BEGIN { print (r > 120 ? 60 : 30) }'
}

frame_time() {   # chwila kadru w sekundach (patrz nagłówek)
    local name="$1" life
    if [[ -f "$SHADERS/$name.update.glsl" ]]; then
        life=$(sed -n 's/^#pragma flux life[[:space:]]\{1,\}\([0-9.]\{1,\}\).*/\1/p' "$SHADERS/$name.update.glsl" | head -n1)
        awk -v l="${life:-4}" 'BEGIN { t = l * 1.5; if (t < 4) t = 4; if (t > 15) t = 15; printf "%.2f", t }'
    else
        echo "6.00"
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok=0; failed=0
for rice in "${RICES[@]}"; do
    conf="$REPO/rices/$rice/flux-wall.conf"
    if [[ ! -f "$conf" ]]; then
        echo "✗ $rice: brak rices/$rice/flux-wall.conf — pomijam" >&2; failed=$((failed + 1)); continue
    fi
    read -r palette dither < <(rice_conf "$conf")
    args=("${SIZE_ARGS[@]}")
    [[ -n "$palette" ]] && args+=(-p "$palette")
    if (( DITHER_FLAGS )); then
        if [[ "$dither" == "1" ]]; then args+=(--dither); else args+=(--no-dither); fi
    fi
    mkdir -p "$OUT/$rice"
    for name in "${ANIMS[@]}"; do
        # nazwy jak w flux-wall.sh shader_path: bez `/` i `..` (apostrof OK)
        if [[ ! "$name" =~ ^[a-z0-9\'-]+$ || ! -f "$SHADERS/$name.frag" ]]; then
            echo "✗ $rice/$name: nie ma takiej animacji" >&2; failed=$((failed + 1)); continue
        fi
        t="$(frame_time "$name")"
        audio=silence; is_audio "$name" && audio="$AUDIO_MODE"
        job="$TMP/job"; rm -rf "$job"; mkdir -p "$job"
        if "$OFF" "$SHADERS/$name.frag" -o "$job" "${args[@]}" -f "$(frame_fps "$name")" -t "$t" --audio "$audio" >"$TMP/log" 2>&1; then
            png=("$job"/*.png)
            if [[ -f "${png[0]}" ]]; then
                mv -f "${png[0]}" "$OUT/$rice/$name.png"
                echo "✓ $rice/$name (t=${t}s, audio=$audio)"
                ok=$((ok + 1)); continue
            fi
        fi
        echo "✗ $rice/$name — offscreen:" >&2; tail -n 3 "$TMP/log" | sed 's/^/    /' >&2
        failed=$((failed + 1))
    done
done

echo ""
echo "Kadry: $ok zapisanych, $failed błędów → ${OUT#"$REPO"/}/<rice>/<animacja>.png"
(( DITHER_FLAGS )) || echo "(offscreen bez --dither/--no-dither — kadry w jego domyślnym trybie)"
[[ "${SIZE_ARGS[1]}" == "$RENDER_SIZE" ]] || echo "(offscreen bez --downscale — kadry $OLD_SIZE liczone wprost; przebuduj: make -C src/flux-wall tools)"
(( failed == 0 ))
