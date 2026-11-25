#!/usr/bin/env bash
# =============================================
#   archenemy - tests/flux-wall-rate.sh
#   Animacje flux-wall w rytmie monitora (decyzja właściciela 2026-11-24):
#   krok symulacji cząstek idzie za odświeżaniem monitora (engine.h:
#   flux_sim_rate) — na 144 Hz jeden krok na klatkę zamiast 60 kroków/s
#   rozłożonych nierówno po 144 klatkach. Obraz NIE może przez to zależeć od
#   Hz: ta sama jasność (silnik skaluje ślad: inc · step_scale) i to samo
#   tempo ruchu (shadery liczą „na krok” przez dt albo step_scale).
#
#   Test: KAŻDA animacja cząstkowa (shaders/*.update.glsl) renderowana bez
#   ekranu (src/flux-wall/tools/offscreen, EGL surfaceless) dwa razy —
#   w tempie nominalnym (60 klatek/s) i jak na monitorze 144 Hz
#   (`-f 144 --hz 144`) — i porównanie klatki po 3 s: średnia jasność
#   i udział zapalonych pikseli (tools/pngstat.py same, tolerancja 15 %).
#   Łapie grube zależności od Hz: silnik bez skalowania śladu (2,4× jaśniej)
#   albo shader pola przepływu ze stałym krokiem (dither-flow sprzed zmiany:
#   zapalone 20,5 % → 14,7 %). Mniejszych (deszcz szybszy o 20 %) nie widać
#   w statystyce kadru — pilnuje ich reguła step_scale w engine.h i test GL
#   w test.c („P4”).
#   Kod 0 = OK. Bez `make -C src/flux-wall tools` kod 0 i komunikat SKIP
#   (narzędzia dev nie są budowane przez install.sh).
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/timing.sh
source "$REPO/tests/lib/timing.sh"
FW="$REPO/src/flux-wall"
OFF="$FW/build/offscreen"
if [[ ! -x "$OFF" ]]; then
    echo "SKIP: brak $OFF — zbuduj: make -C src/flux-wall tools"
    exit 0
fi
usage_text="$("$OFF" --help 2>&1)"
if [[ "$usage_text" != *--hz* ]]; then
    echo "SKIP: $OFF nie zna --hz (stara binarka) — przebuduj: make -C src/flux-wall tools"
    exit 0
fi
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1
test_timing_init "$T"

PASS=0; FAIL=0
mkdir -p "$T/nominal" "$T/hz144"
for upd in "$FW"/shaders/*.update.glsl; do
    [[ -f "$upd" ]] || continue
    name="${upd##*/}"; name="${name%.update.glsl}"
    frag="$FW/shaders/$name.frag"
    if ! test_timeout 300 "$OFF" "$frag" -o "$T/nominal" -s 256x144 -f 60 -t 3 --audio synth >"$T/log" 2>&1 \
        || ! test_timeout 300 "$OFF" "$frag" -o "$T/hz144" -s 256x144 -f 144 --hz 144 -t 3 --audio synth >>"$T/log" 2>&1; then
        echo "  ✗ $name: offscreen padł:"; tail -n 3 "$T/log" | sed 's/^/      /'
        FAIL=$((FAIL + 1)); continue
    fi
    if out="$(python3 "$FW/tools/pngstat.py" same "$T/nominal/$name-03.00.png" "$T/hz144/$name-03.00.png" 0.15 2>&1)"; then
        echo "  ✓ $name: 60 Hz / 144 Hz — $out"; PASS=$((PASS + 1))
    else
        echo "  ✗ $name: obraz zależy od Hz monitora — $out"; FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
test_timing_ok || FAIL=$((FAIL + 1))
(( PASS > 0 && FAIL == 0 ))
