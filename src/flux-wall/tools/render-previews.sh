#!/bin/bash
# =============================================
#   archenemy - src/flux-wall/tools/render-previews.sh
#   Kadry podglądu animacji do menu Super+W → Animations/:
#   src/flux-wall/shaders/previews/<rice>/<animacja>.png (256x144, w repo).
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
#     * dźwięk: `--audio synth` (wbudowany syntezator) dla wizualizacji
#       muzyki (`#pragma flux audio 1` we .frag albo .update.glsl — ta sama
#       reguła co flux-wall.sh list-audio), cisza dla reszty,
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
SIZE="256x144"
FPS=30

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

# Flagi ditheru tylko, gdy offscreen je zna (usage idzie na stderr, kod 2).
DITHER_FLAGS=0
"$OFF" --help 2>&1 | grep -q -- '--dither' && DITHER_FLAGS=1

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
    args=(-s "$SIZE" -f "$FPS")
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
        audio=silence; is_audio "$name" && audio=synth
        job="$TMP/job"; rm -rf "$job"; mkdir -p "$job"
        if "$OFF" "$SHADERS/$name.frag" -o "$job" "${args[@]}" -t "$t" --audio "$audio" >"$TMP/log" 2>&1; then
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
(( failed == 0 ))
