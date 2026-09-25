#!/bin/bash
# =============================================
#   archenemy - tests/render-previews.sh
#   src/flux-wall/tools/render-previews.sh na ATRAPIE offscreena (zapisuje
#   argumenty, tworzy pusty PNG) w kopii drzewa w mktemp — bez GPU, bez
#   budowania. Sprawdza kontrakt wywołań, nie obraz:
#     * --dither tylko dla rice'a z FLUX_WALL_DITHER=1, --no-dither dla
#       reszty — i ŻADNEJ z tych flag, gdy usage offscreena ich nie zna,
#     * paleta z flux-wall.conf (-p), --audio synth tylko dla
#       `#pragma flux audio 1`, chwila kadru = 1.5 × life (4..15 s) dla
#       cząstkowych, 6 s dla jednoprzebiegowych,
#     * wynik w shaders/previews/<rice>/<nazwa>.png, także z apostrofem.
#   Powód (2026-09-25): wykrywanie flag przez `offscreen --help | grep -q`
#   przy pipefail zawsze padało (usage kończy się kodem 2) — kadry
#   dither-flux wychodziły bez rastra.
#   Uruchom: bash tests/render-previews.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── kopia drzewa: skrypt + atrapa offscreena + shadery + dwa rice'y ─────────
FW="$T/src/flux-wall"
mkdir -p "$FW/tools" "$FW/build" "$FW/shaders" "$T/rices/rasta" "$T/rices/gladki"
cp "$REPO/src/flux-wall/tools/render-previews.sh" "$FW/tools/"
cat > "$FW/build/offscreen" <<'MOCK'
#!/bin/bash
# usage na stderr z kodem 2 — jak prawdziwy offscreen
if [[ "$1" == --help ]]; then
    echo "offscreen <shader.frag> -o <katalog> [--audio synth|silence]${MOCK_USAGE_DITHER:+ [--dither | --no-dither]}" >&2
    exit 2
fi
echo "$*" >> "$MOCK_LOG"
frag="$1"; shift; out=""; t=""
while (( $# )); do case "$1" in -o) out="$2"; shift 2 ;; -t) t="$2"; shift 2 ;; *) shift ;; esac; done
n="${frag##*/}"; n="${n%.frag}"
printf 'PNG' > "$out/$n-$t.png"
MOCK
chmod +x "$FW/build/offscreen"
printf 'void main(){}\n' > "$FW/shaders/plain.frag"
printf 'void main(){}\n' > "$FW/shaders/orb-spinnin'.frag"
printf '#pragma flux audio 1\n#pragma flux life 2.5\n' > "$FW/shaders/orb-spinnin'.update.glsl"
printf 'void main(){}\n' > "$FW/shaders/slow.frag"
printf '#pragma flux life 10\n' > "$FW/shaders/slow.update.glsl"
printf 'FLUX_WALL_PALETTE="0F1A24,5C87A3,D8E6EE"\nFLUX_WALL_DITHER=1\n' > "$T/rices/rasta/flux-wall.conf"
printf 'FLUX_WALL_PALETTE="031533,3069AD,36D2D8"\nFLUX_WALL_DITHER=0\n' > "$T/rices/gladki/flux-wall.conf"
export MOCK_LOG="$T/log"
RP="$FW/tools/render-previews.sh"
call() { grep -F -- "$FW/shaders/$1.frag -o" "$MOCK_LOG" | grep -F -- "$2" | head -n1; }

echo "== offscreen zna --dither"
: > "$MOCK_LOG"
MOCK_USAGE_DITHER=1 bash "$RP" >/dev/null 2>&1; rc=$?
check "kod 0, 6 kadrów (2 rice × 3 animacje)"   '[[ $rc -eq 0 && $(wc -l < "$MOCK_LOG") -eq 6 ]]'
check "rice z FLUX_WALL_DITHER=1 → --dither"    '[[ $(grep -F -- "-p 0F1A24,5C87A3,D8E6EE" "$MOCK_LOG" | grep -c -- " --dither ") -eq 3 ]]'
check "rice z FLUX_WALL_DITHER=0 → --no-dither" '[[ $(grep -F -- "-p 031533,3069AD,36D2D8" "$MOCK_LOG" | grep -c -- " --no-dither ") -eq 3 ]]'
check "wizualizacja: --audio synth, reszta cisza" '[[ "$(call "orb-spinnin'"'"'" 0F1A24)" == *"--audio synth"* && "$(call plain 0F1A24)" == *"--audio silence"* ]]'
check "chwila: life 2.5 → 4 s, life 10 → 15 s, frag → 6 s" '[[ "$(call "orb-spinnin'"'"'" 0F1A24)" == *"-t 4.00 "* && "$(call slow 0F1A24)" == *"-t 15.00 "* && "$(call plain 0F1A24)" == *"-t 6.00 "* ]]'
check "kadry w previews/<rice>/<nazwa>.png (apostrof)" '[[ -s "$FW/shaders/previews/rasta/orb-spinnin'"'"'.png" && -s "$FW/shaders/previews/gladki/plain.png" ]]'

echo "== starszy offscreen (usage bez --dither)"
: > "$MOCK_LOG"
bash "$RP" -r rasta -a plain >/dev/null 2>&1; rc=$?
check "-r/-a: jeden kadr"                        '[[ $rc -eq 0 && $(wc -l < "$MOCK_LOG") -eq 1 ]]'
check "bez --dither i bez --no-dither"           '! grep -q -- "dither" "$MOCK_LOG"'

echo "== błędy"
bash "$RP" -r rasta -a nie-ma >/dev/null 2>&1; rc=$?
check "nieznana animacja → kod ≠ 0"              '[[ $rc -ne 0 ]]'
bash "$RP" -a "../x" >/dev/null 2>&1; rc=$?
check "nazwa z / odrzucona"                      '[[ $rc -ne 0 && ! -e "$FW/shaders/previews/rasta/../x.png" ]]'

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
