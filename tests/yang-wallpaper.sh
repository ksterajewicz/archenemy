#!/usr/bin/env bash
# =============================================
#   archenemy - tests/yang-wallpaper.sh
#   Generator tapety rice'a yang (scripts/wallpapers/gen_yang_wallpaper.py,
#   „zaćmienie w negatywie”): wynik deterministyczny i zgodny z repo.
#     - dwa biegi do mktemp → ten sam SHA-256 każdego PNG (stałe ziarno
#       losowego zaokrąglenia, zero zależności od czasu i środowiska),
#     - pierwszy bieg = pliki w wallpapers/yang/ bajt w bajt (PNG w repo
#       to naprawdę wynik generatora, nie ręczna edycja),
#     - rozmiary v1 1920×1080 i v2 2560×1600 (konwencja Super+W),
#     - najciemniejszy poziom ≥ 110 (#6E6E73) — na nim stoi rachunek
#       kontrastu tekstu na szkle w README (sekcja yang); zmiana stałych
#       generatora, która przyciemni rant, wymaga nowego rachunku.
#   Bez roota, zapis tylko w mktemp.
#   Uruchom: bash tests/yang-wallpaper.sh   (kod 0 = wszystko przeszło)
# =============================================

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

GEN="$REPO/scripts/wallpapers/gen_yang_wallpaper.py"
FILES=(yang-eclipse-v1-1920x1080.png yang-eclipse-v2-2560x1600.png)

echo "== dwa biegi generatora"
for run in a b; do
    if out="$(cd "$T" && python3 -I "$GEN" "$T/$run" 2>&1)"; then ok "bieg $run: $(grep -c "^✓" <<< "$out") PNG"
    else fail "bieg $run padł: $out"; fi
done

echo "== deterministyczność i zgodność z repo"
for f in "${FILES[@]}"; do
    a="$(sha256sum "$T/a/$f" 2>/dev/null | cut -d' ' -f1)"
    b="$(sha256sum "$T/b/$f" 2>/dev/null | cut -d' ' -f1)"
    r="$(sha256sum "$REPO/wallpapers/yang/$f" 2>/dev/null | cut -d' ' -f1)"
    if [[ -n "$a" && "$a" == "$b" ]]; then ok "$f: dwa biegi → ten sam SHA-256 (${a:0:12}…)"
    else fail "$f: biegi różne (${a:-brak} vs ${b:-brak})"; fi
    if [[ -n "$a" && "$a" == "$r" ]]; then ok "$f: = wallpapers/yang/$f"
    else fail "$f: inny niż w repo (${r:-brak pliku}) — przebuduj: python3 scripts/wallpapers/gen_yang_wallpaper.py"; fi
done

echo "== rozmiary i najciemniejszy poziom (PNG typ 3 z paletą)"
cat > "$T/png.py" <<'PY'
import struct, sys, zlib
data = open(sys.argv[1], "rb").read()
assert data[:8] == b"\x89PNG\r\n\x1a\n", "brak sygnatury PNG"
pos, idat, plte = 8, b"", b""
while pos < len(data):
    n, tag = struct.unpack(">I4s", data[pos:pos + 8])
    body = data[pos + 8:pos + 8 + n]
    if tag == b"IHDR":
        w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
    elif tag == b"PLTE":
        plte = body
    elif tag == b"IDAT":
        idat += body
    pos += 12 + n
assert depth == 8 and ctype == 3, f"oczekiwano 8-bit indeksowany, jest {depth}/{ctype}"
raw = zlib.decompress(idat)
stride = w + 1
assert len(raw) == stride * h
assert all(raw[y * stride] == 0 for y in range(h)), "filtr wiersza inny niż 0"
levels = set()
for y in range(h):
    levels.update(raw[y * stride + 1:(y + 1) * stride])
dark = min(levels)
r, g, b = plte[dark * 3:dark * 3 + 3]
print(f"{w}x{h} {dark} #{r:02X}{g:02X}{b:02X}")
PY
for f in "${FILES[@]}"; do
    want="${f#yang-eclipse-v?-}"; want="${want%.png}"
    info="$(python3 -I "$T/png.py" "$T/a/$f" 2>&1)" || { fail "$f: nieczytelny PNG: $info"; continue; }
    read -r dims dark hex <<< "$info"
    if [[ "$dims" == "$want" ]]; then ok "$f: $dims"; else fail "$f: $dims zamiast $want"; fi
    if (( dark >= 110 )); then ok "$f: najciemniejszy poziom $dark ($hex) ≥ 110 — rachunek kontrastu z README aktualny"
    else fail "$f: najciemniejszy poziom $dark ($hex) < 110 — przelicz kontrast w README (sekcja yang)"; fi
done

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
(( FAIL == 0 ))
