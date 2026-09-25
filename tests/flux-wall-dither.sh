#!/bin/bash
# =============================================
#   archenemy - tests/flux-wall-dither.sh
#   Raster Bayera jako cecha RICE'A, nie animacji (zgłoszenie właściciela
#   2026-09-25: „dither pokazuje się w wizualizacjach muzyki nawet w ricach
#   bez ditheru”). Dwie części:
#
#   1. Wrapper (zawsze): scripts/wallpapers/flux-wall.sh na atrapie HOME
#      z fałszywą binarką, która zapisuje swoje argumenty. --dither ma
#      dostać WYŁĄCZNIE aktywny rice z FLUX_WALL_DITHER=1 (dither-flux),
#      dla każdej animacji z Super+W; reszta --no-dither; stary conf bez
#      klucza i rice bez pliku = --no-dither; binarka sprzed flagi — żadnej
#      z nich. pkill/pgrep/pactl są atrapami: test nigdy nie dotyka
#      prawdziwego flux-walla na maszynie, na której go uruchomiono.
#   2. Render (gdy jest `make -C src/flux-wall tools`): każdy shader
#      z rastrem offscreen z --dither i --no-dither. --dither → tylko trzy
#      kolory palety; --no-dither → ponad 16 kolorów (gradient, bez rastra);
#      domyślnie = --no-dither bajt w bajt; shader bez rastra (spectrogram)
#      nie zmienia się od flagi. Bez narzędzia: SKIP tej części, kod 0.
#   Uruchom: bash tests/flux-wall-dither.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="$REPO/src/flux-wall"
OFF="$FW/build/offscreen"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

# ─── 1. wrapper: wybór flagi z aktywnego rice'a ──────────────────────────────

echo "flux-wall.sh → --dither / --no-dither"
H="$T/home"; A="$H/archenemy"
mkdir -p "$A/src/flux-wall/build" "$A/src/flux-wall/shaders" "$A/scripts/wallpapers" "$A/data" "$T/bin" "$T/run"
cp "$REPO/scripts/wallpapers/flux-wall.sh" "$A/scripts/wallpapers/"
cp -r "$REPO/rices" "$A/rices"
for n in dither-flux bars orb-static; do : > "$A/src/flux-wall/shaders/$n.frag"; done
# rice ze starym confem (sprzed klucza) — ma działać jak 0
mkdir -p "$A/rices/old-rice"
printf '%s\n' 'FLUX_WALL_PALETTE="000000,777777,FFFFFF"' 'FLUX_WALL_SHADER="src/flux-wall/shaders/dither-flux.frag"' \
    'FLUX_WALL_AUTOSTART=1' > "$A/rices/old-rice/flux-wall.conf"

# fałszywa binarka: --help jak prawdziwa (albo stara bez flagi), inaczej log argumentów
cat > "$A/src/flux-wall/build/flux-wall" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == --help ]]; then
    if [[ -f "$HOME/old-binary" ]]; then echo "Użycie: flux-wall -s shader.frag [--no-audio]" >&2
    else echo "Użycie: flux-wall -s shader.frag [--no-audio] [--dither | --no-dither]" >&2; fi
    exit 0
fi
printf '%s\n' "$*" > "$HOME/args.log"
EOF
chmod +x "$A/src/flux-wall/build/flux-wall"
for b in pkill pgrep; do printf '#!/bin/sh\nexit 1\n' > "$T/bin/$b"; done
printf '#!/bin/sh\nexit 0\n' > "$T/bin/pactl"
chmod +x "$T/bin/"*

# run_wrapper <rice> <wybór|""> → argumenty, z którymi wrapper uruchomił binarkę
run_wrapper() {
    local rice="$1" choice="$2"
    echo "$rice" > "$A/.current_rice"
    if [[ -n "$choice" ]]; then echo "$choice" > "$A/data/flux-wall.dat"; else rm -f "$A/data/flux-wall.dat"; fi
    rm -f "$H/args.log"
    HOME="$H" XDG_RUNTIME_DIR="$T/run" PATH="$T/bin:$PATH" bash "$A/scripts/wallpapers/flux-wall.sh" autostart
    for _ in $(seq 1 30); do [[ -s "$H/args.log" ]] && break; sleep 0.1; done
    cat "$H/args.log" 2>/dev/null
}

# expect <rice> <wybór> <--dither|--no-dither|none>
expect() {
    local rice="$1" choice="$2" want="$3" got flag
    got="$(run_wrapper "$rice" "$choice")"
    if [[ -z "$got" ]]; then fail "$rice / ${choice:-<brak wyboru>}: binarka nie wystartowała"; return; fi
    flag=none
    [[ " $got " == *" --dither "* ]] && flag=--dither
    [[ " $got " == *" --no-dither "* ]] && flag="${flag/none/}--no-dither"
    if [[ "$flag" == "$want" ]]; then ok "$rice / ${choice:-<brak wyboru>} → $want"
    else fail "$rice / ${choice:-<brak wyboru>}: oczekiwane $want, argumenty: $got"; fi
}

expect dither-flux ""          --dither
expect dither-flux bars        --dither
expect dither-flux "orb-static" --dither
for r in white-blue tron crt asia-n-rice; do
    expect "$r" bars        --no-dither
    expect "$r" dither-flux --no-dither
done
expect old-rice ""              --no-dither
expect white-blue_beta bars     --no-dither
# Super+T: ten sam wybór, zmiana rice'a → flaga idzie za rice'em
expect dither-flux bars --dither
expect tron bars        --no-dither
# binarka sprzed flagi: bez --dither/--no-dither (inaczej getopt → kod 1, brak tapety)
touch "$H/old-binary"
expect dither-flux bars none
expect crt bars         none
rm -f "$H/old-binary"

# deklaracje w repo: 1 tylko w dither-flux
for conf in "$REPO"/rices/*/flux-wall.conf; do
    r="$(basename "$(dirname "$conf")")"
    v="$(sed -n 's/^FLUX_WALL_DITHER=//p' "$conf")"
    want=0; [[ "$r" == dither-flux ]] && want=1
    if [[ "$v" == "$want" ]]; then ok "rices/$r/flux-wall.conf: FLUX_WALL_DITHER=$v"
    else fail "rices/$r/flux-wall.conf: FLUX_WALL_DITHER='${v}' (ma być $want)"; fi
done
# przełącznik rice'ów zapisuje .current_rice PRZED `flux-wall.sh autostart` — inaczej flaga szłaby za starym rice'em
SW="$REPO/scripts/changing-theme-scripts/lib/switch-rice.sh"
# shellcheck disable=SC2016  # szukamy dosłownego tekstu `$CURRENT_RICE` / `$FLUX_WALL` w skrypcie
l_cur="$(grep -n '> "\$CURRENT_RICE"' "$SW" | head -1 | cut -d: -f1)"
# shellcheck disable=SC2016
l_fw="$(grep -n '"\$FLUX_WALL" autostart' "$SW" | head -1 | cut -d: -f1)"
if [[ -n "$l_cur" && -n "$l_fw" && "$l_cur" -lt "$l_fw" ]]; then ok "switch-rice.sh: .current_rice (l. $l_cur) przed autostartem flux-walla (l. $l_fw)"
else fail "switch-rice.sh: kolejność .current_rice / flux-wall autostart (l. ${l_cur:-?} / ${l_fw:-?})"; fi

# ─── 2. render: raster tylko przy --dither ───────────────────────────────────

echo "offscreen: --dither vs --no-dither"
if [[ ! -x "$OFF" ]]; then
    echo "  SKIP render: brak $OFF — zbuduj: make -C src/flux-wall tools"
else
    PAL="0F1A24,5C87A3,D8E6EE"
    render() {  # render <frag> <katalog> [flaga]
        mkdir -p "$2"
        "$OFF" "$1" -o "$2" -s 320x180 -f 15 -t 2 --audio synth -p "$PAL" ${3:+"$3"} >"$2/log" 2>&1
    }
    for frag in "$FW"/shaders/*.frag; do
        n="$(basename "$frag" .frag)"
        png="$n-02.00.png"
        if ! render "$frag" "$T/d/$n" --dither || ! render "$frag" "$T/s/$n" --no-dither; then
            fail "$n: offscreen padł: $(tail -n 1 "$T/d/$n/log" "$T/s/$n/log" 2>/dev/null | tr '\n' ' ')"; continue
        fi
        if ! grep -q 'bayer8' "$frag"; then
            if cmp -s "$T/d/$n/$png" "$T/s/$n/$png"; then ok "$n: bez rastra w kodzie — flaga nic nie zmienia"
            else fail "$n: shader bez rastra, a --dither zmienił obraz"; fi
            continue
        fi
        if res="$(PYTHONDONTWRITEBYTECODE=1 python3 - "$FW/tools" "$PAL" "$T/d/$n/$png" "$T/s/$n/$png" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
from pngstat import read_png
pal = {bytes.fromhex(h) for h in sys.argv[2].split(',')}
def colors(path):
    W, H, bpp, b = read_png(path)
    return {b[k:k + 3] for k in range(0, W * H * bpp, bpp)}
d, s = colors(sys.argv[3]), colors(sys.argv[4])
extra = d - pal
print(f"dither: {len(d)} kolory{' (spoza palety: ' + str(len(extra)) + ')' if extra else ''}, gładko: {len(s)} kolorów")
sys.exit(0 if not extra and len(d) >= 2 and len(s) > 16 else 1)
EOF
)"; then ok "$n: $res"
        else fail "$n: $res"; fi
    done
    # domyślny tryb offscreen = --no-dither (jak binarka)
    render "$FW/shaders/dither-flux.frag" "$T/def"
    if cmp -s "$T/def/dither-flux-02.00.png" "$T/s/dither-flux/dither-flux-02.00.png"; then ok "offscreen bez flagi = --no-dither"
    else fail "offscreen bez flagi różni się od --no-dither"; fi
fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
