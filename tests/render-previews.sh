#!/usr/bin/env bash
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
#     * wynik w shaders/previews/<rice>/<nazwa>.png, także z apostrofem,
#     * offscreen z --downscale i `music` (decyzja właściciela 2026-11-24,
#       3A): kadr liczony w 1920x1080 i pomniejszany 4×, dźwięk pełnego
#       pasma, 60 klatek/s dla shaderów z tempem ponad 120 kroków/s; starszy
#       offscreen dostaje dawne 256x144 i `synth`.
#   Na końcu KOMPLET kadrów w repo (bez atrapy): każdy rice z flux-wall.conf
#   × każda animacja ma PNG 480x270 i nie ma kadrów osieroconych — rice
#   yang nie miał żadnego i menu Animations było w nim bez obrazków
#   (audyt 2026-11-24, U13).
#   Powód (2026-09-25): wykrywanie flag przez `offscreen --help | grep -q`
#   przy pipefail zawsze padało (usage kończy się kodem 2) — kadry
#   dither-flux wychodziły bez rastra.
#   Uruchom: bash tests/render-previews.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── kopia drzewa: skrypt + atrapa offscreena + shadery + dwa rice'y ─────────
FW="$T/src/flux-wall"
mkdir -p "$FW/tools" "$FW/build" "$FW/shaders" "$T/rices/rasta" "$T/rices/gladki"
cp "$REPO/src/flux-wall/tools/render-previews.sh" "$FW/tools/"
cat > "$FW/build/offscreen" <<'MOCK'
#!/usr/bin/env bash
# usage na stderr z kodem 2 — jak prawdziwy offscreen
if [[ "$1" == --help ]]; then
    echo "offscreen <shader.frag> -o <katalog> [--audio synth${MOCK_USAGE_NEW:+|music}|silence]${MOCK_USAGE_DITHER:+ [--dither | --no-dither]}${MOCK_USAGE_NEW:+ [--downscale N]}" >&2
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
check "offscreen bez --downscale: dawne 256x144 wprost, 30 klatek/s" '[[ $(grep -- " -s 256x144 " "$MOCK_LOG" | grep -c -- " -f 30 ") -eq 6 ]] && ! grep -q -- "--downscale" "$MOCK_LOG"'

echo "== offscreen zna --downscale i --audio music"
printf 'void main(){}\n' > "$FW/shaders/fast.frag"
printf '#pragma flux life 1.6\n#pragma flux rate 240\n' > "$FW/shaders/fast.update.glsl"
: > "$MOCK_LOG"
MOCK_USAGE_DITHER=1 MOCK_USAGE_NEW=1 bash "$RP" -r gladki >/dev/null 2>&1; rc=$?
check "kod 0, 4 kadry"                            '[[ $rc -eq 0 && $(wc -l < "$MOCK_LOG") -eq 4 ]]'
check "liczenie w 1920x1080, zapis 4× mniejszy"   '[[ $(grep -c -- " -s 1920x1080 --downscale 4 " "$MOCK_LOG") -eq 4 ]]'
check "wizualizacja: --audio music, reszta cisza" '[[ "$(call "orb-spinnin'"'"'" 031533)" == *"--audio music"* && "$(call plain 031533)" == *"--audio silence"* ]]'
check "tempo 240 kroków/s → 60 klatek/s, reszta 30" '[[ "$(call fast 031533)" == *" -f 60 "* && "$(call slow 031533)" == *" -f 30 "* && "$(call plain 031533)" == *" -f 30 "* ]]'
rm -f "$FW/shaders/fast.frag" "$FW/shaders/fast.update.glsl" "$FW/shaders/previews/gladki/fast.png"

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

# ─── komplet kadrów w repo (prawdziwe pliki, bez atrapy) ─────────────────────
echo "== repo: każdy rice z flux-wall.conf × każda animacja ma kadr 480x270"
PREV="$REPO/src/flux-wall/shaders/previews"
png_size() {   # szerokość i wysokość z nagłówka IHDR („W H”); pusto, gdy to nie PNG
    local b
    read -r -a b < <(od -An -tu1 -N24 "$1" 2>/dev/null | tr -s ' \n' ' ')
    [[ ${#b[@]} -eq 24 && "${b[0]}" == 137 && "${b[1]}" == 80 && "${b[2]}" == 78 && "${b[3]}" == 71 ]] || return 1
    echo "$(( (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19] )) $(( (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23] ))"
}
rices=0; frames=0; missing=(); wrong=(); orphans=()
for conf in "$REPO"/rices/*/flux-wall.conf; do
    [[ -f "$conf" ]] || continue
    rice="${conf%/flux-wall.conf}"; rice="${rice##*/}"; rices=$((rices + 1))
    for frag in "$REPO"/src/flux-wall/shaders/*.frag; do
        name="${frag##*/}"; name="${name%.frag}"
        png="$PREV/$rice/$name.png"
        if [[ ! -s "$png" ]]; then missing+=("$rice/$name"); continue; fi
        frames=$((frames + 1))
        [[ "$(png_size "$png")" == "480 270" ]] || wrong+=("$rice/$name: $(png_size "$png" || echo 'nie PNG')")
    done
done
for png in "$PREV"/*/*.png; do
    [[ -f "$png" ]] || continue
    rel="${png#"$PREV"/}"; rice="${rel%%/*}"; name="${rel#*/}"; name="${name%.png}"
    [[ -f "$REPO/rices/$rice/flux-wall.conf" && -f "$REPO/src/flux-wall/shaders/$name.frag" ]] || orphans+=("$rel")
done
check "są rice'y z flux-wall.conf i kadry ($rices rice'ów, $frames kadrów)" '[[ $rices -ge 7 && $frames -ge 140 ]]'
if [[ ${#missing[@]} -eq 0 ]]; then ok "żadnego brakującego kadru (także yang)"
else fail "brak ${#missing[@]} kadrów, np.: ${missing[*]:0:6} — src/flux-wall/tools/render-previews.sh"; fi
if [[ ${#wrong[@]} -eq 0 ]]; then ok "wszystkie kadry to PNG 480x270"
else fail "${#wrong[@]} kadrów w innym rozmiarze, np.: ${wrong[*]:0:4}"; fi
if [[ ${#orphans[@]} -eq 0 ]]; then ok "żadnego kadru bez rice'a albo bez animacji"
else fail "kadry osierocone: ${orphans[*]:0:6}"; fi

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
