#!/bin/bash
# =============================================
#   archenemy - tests/flux-wall-bars.sh
#   Regresja „bars": kreski szczytu (peak hold) tylko na lewej połowie
#   ekranu (zgłoszenie 2026-09-21, drugi monitor). Przyczyna: stempel
#   cząstki (GL_POINTS, rozmiar 1) celowany w środek piksela xc lądował po
#   rasteryzacji w xc-1, gdy błąd float przy NDC > 0 (prawa połowa) — a
#   bars.frag czytał dokładnie jedną kolumnę. Zmierzone offscreen: lewa 937
#   stempli w xc, prawa 15 (wszystkie w xc-1).
#
#   Test: render bez ekranu (src/flux-wall/tools/offscreen, EGL surfaceless,
#   llvmpipe wystarczy) PRAWDZIWEGO bars.frag przy 1920x1080 (HDMI) i
#   2560x1600 (panel); tools/pngstat.py marks liczy kreski szczytu (dolne
#   krawędzie wiszących kresek) po obu połowach — muszą być po obu stronach
#   i w proporcji 0.5..2. Na klatce sprzed poprawki: lewa 73, prawa 0 (1920)
#   i 38/0 (2560); po poprawce 73/73 i 82/82. Kod 0 = OK. Bez zbudowanego
#   `make -C src/flux-wall tools` test kończy się kodem 0 z komunikatem SKIP
#   (narzędzia dev nie są budowane przez install.sh).
#   Surowe stemple akumulatora: tools/bars-accum-debug.frag + pngstat.py accum.
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="$REPO/src/flux-wall"
OFF="$FW/build/offscreen"
if [[ ! -x "$OFF" ]]; then
    echo "SKIP: brak $OFF — zbuduj: make -C src/flux-wall tools"
    exit 0
fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

FAIL=0
for size in 1920x1080 2560x1600; do
    mkdir -p "$T/out-$size"
    if ! "$OFF" "$FW/shaders/bars.frag" -o "$T/out-$size" -s "$size" -f 144 -t 4 --audio synth >"$T/log-$size" 2>&1; then
        echo "  ✗ $size: offscreen padł:"; tail -n 3 "$T/log-$size"; FAIL=1; continue
    fi
    printf '  %s: ' "$size"
    python3 "$FW/tools/pngstat.py" marks "$T/out-$size/bars-04.00.png" | tr '\n' ' ' || FAIL=1
    echo
done
(( FAIL == 0 )) && echo "flux-wall bars: OK" || echo "flux-wall bars: BŁĄD"
exit $FAIL
