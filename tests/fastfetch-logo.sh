#!/usr/bin/env bash
# =============================================
#   archenemy - tests/fastfetch-logo.sh
#   Logo fastfetcha na każdym rice (decyzja właściciela 2026-11-18: „zawsze,
#   na wszystkich rice mają być tu loga distro”): wbudowane logo WYKRYTEJ
#   dystrybucji w kolorach rice'a. Każdy rices/*/fastfetch/config.jsonc (po
#   rozwiązaniu dowiązań) ma:
#     - "logo" z "type": "builtin" i bez "source" (autodetekcja: Arch na
#       Archu, Fedora na Fedorze, NixOS na NixOS; stałe "source": "arch"
#       pokazywało logo Archa także na Fedorze i NixOS),
#     - żadnego logo z pliku ("type": "file", logo.txt w katalogu),
#     - kolory "1"–"6" jako kody SGR: logo Arch i Fedora zużywa $1–$2, NixOS
#       $1–$6 (fastfetch 2.71, sprawdzone renderem z kolorami 1–9) — brak
#       numeru = ta część logo w domyślnym kolorze fastfetcha, nie rice'a.
#   Z fastfetchem w PATH dodatkowo: logo Arch/Fedora/NixOS nie zużywa numerów
#   powyżej 6, a render configu każdego rice'a z każdym z tych logo nie ma
#   ani jednego koloru spoza bloku "color" (bez fastfetcha: widoczny skip).
#   Logo rysuje fastfetch ze swojego zestawu znaków — w repo nie ma pliku
#   z logo dystrybucji.
#   Bez roota, zapis tylko w mktemp (HOME i XDG w mktemp).
#   Uruchom: bash tests/fastfetch-logo.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  ? skip: $1"; }

# Sprawdzarka jednego configu: wypisuje pusty wiersz (OK) albo powód błędu.
# jsonc → json: komentarze // poza łańcuchami (w "$schema" jest https://).
cat > "$T/check.py" <<'PY'
import json, re, sys
from pathlib import Path

SLOTS = [str(i) for i in range(1, 7)]
SGR = re.compile(r'^[0-9]+(;[0-9]+)*$')

def strip(text):
    out, i, q = [], 0, False
    while i < len(text):
        c = text[i]
        if q:
            out.append(c)
            if c == "\\": out.append(text[i + 1]); i += 1
            elif c == '"': q = False
        elif c == '"': q = True; out.append(c)
        elif text.startswith("//", i):
            while i < len(text) and text[i] != "\n": i += 1
            continue
        else: out.append(c)
        i += 1
    return "".join(out)

def problem(path):
    try:
        d = json.loads(strip(Path(path).read_text(encoding="utf-8")))
    except (OSError, ValueError) as e:
        return f"nieczytelny config: {e}"
    logo = d.get("logo")
    if not isinstance(logo, dict):
        return "brak bloku \"logo\" (domyślne kolory fastfetcha zamiast palety rice'a)"
    if logo.get("type") != "builtin":
        return f"\"type\": {json.dumps(logo.get('type'))} zamiast \"builtin\""
    if "source" in logo:
        return f"stałe \"source\": {json.dumps(logo['source'])} — logo nie idzie za wykrytą dystrybucją"
    color = logo.get("color")
    if not isinstance(color, dict):
        return "brak \"color\" w bloku logo"
    missing = [s for s in SLOTS if not (isinstance(color.get(s), str) and SGR.match(color[s]))]
    if missing:
        return "brak kolorów " + ",".join(missing) + " (logo NixOS zużywa 1–6, Arch i Fedora 1–2)"
    return ""

if __name__ == "__main__":
    if sys.argv[1] == "--colors":
        d = json.loads(strip(Path(sys.argv[2]).read_text(encoding="utf-8")))
        print("\n".join(sorted(set(d["logo"]["color"][s] for s in SLOTS))))
    else:
        print(problem(sys.argv[1]))
PY

echo "== kontrola sprawdzarki (configi syntetyczne)"
GOOD='"color": {"1":"38;2;1;2;3","2":"97","3":"38;2;1;2;3","4":"97","5":"38;2;1;2;3","6":"97"}'
declare -A CASES=(
    [dobry]="{ // komentarz \"x\"
  \"\$schema\": \"https://example.invalid/s.json\", \"logo\": {\"type\": \"builtin\", $GOOD}}"
    [source-arch]="{\"logo\": {\"source\": \"arch\", \"type\": \"builtin\", $GOOD}}"
    [type-file]="{\"logo\": {\"type\": \"file\", \"source\": \"~/.config/fastfetch/logo.txt\", $GOOD}}"
    [bez-typu]="{\"logo\": {$GOOD}}"
    [bez-logo]='{"modules": ["title"]}'
    [bez-koloru-3]='{"logo": {"type": "builtin", "color": {"1":"34","2":"36","4":"36","5":"34","6":"36"}}}'
    [tylko-1-2]='{"logo": {"type": "builtin", "color": {"1":"34","2":"36"}}}'
)
for name in dobry source-arch type-file bez-typu bez-logo bez-koloru-3 tylko-1-2; do
    printf '%s\n' "${CASES[$name]}" > "$T/$name.jsonc"
    why="$(python3 -I "$T/check.py" "$T/$name.jsonc")"
    if [[ "$name" == dobry ]]; then
        if [[ -z "$why" ]]; then ok "dobry config przechodzi (komentarz z cudzysłowem, https:// w łańcuchu)"
        else fail "dobry config odrzucony: $why"; fi
    elif [[ -n "$why" ]]; then ok "$name odrzucony: $why"
    else fail "$name przepuszczony — sprawdzarka nic nie dowodzi"; fi
done

echo "== każdy rice: logo wykrytej dystrybucji w kolorach rice'a"
mapfile -t RICES < <(cd "$REPO/rices" && for d in */; do echo "${d%/}"; done | sort)
if (( ${#RICES[@]} == 0 )); then fail "brak katalogów w rices/"; fi
for rice in "${RICES[@]}"; do
    cfg="$REPO/rices/$rice/fastfetch/config.jsonc"
    real="$(readlink -f -- "$cfg" 2>/dev/null || true)"
    if [[ -z "$real" || ! -f "$real" ]]; then fail "$rice: brak fastfetch/config.jsonc (albo wiszący link)"; continue; fi
    case "$real" in "$REPO"/rices/*) ;; *) fail "$rice: config wskazuje poza rices/ ($real)"; continue ;; esac
    why="$(python3 -I "$T/check.py" "$real")"
    if [[ -z "$why" ]]; then ok "$rice: builtin bez source, kolory 1–6"; else fail "$rice: $why"; fi
    extra="$(find "$(dirname "$real")" -mindepth 1 -maxdepth 1 ! -name config.jsonc -printf '%f ' 2>/dev/null)"
    if [[ -z "$extra" ]]; then ok "$rice: w fastfetch/ tylko config.jsonc (żadnego pliku z logo)"
    else fail "$rice: w fastfetch/ zbędne pliki: $extra"; fi
done

echo "== render fastfetcha (numery kolorów logo i kolory rice'a)"
if ! command -v fastfetch >/dev/null 2>&1; then
    skip "brak fastfetch w PATH — render logo Arch/Fedora/NixOS pominięty"
else
    probe=()
    for i in 1 2 3 4 5 6 7 8 9; do probe+=(--logo-color-"$i" "38;5;$((200 + i))"); done
    for logo in arch Fedora NixOS; do
        out="$(fastfetch --config none --logo "$logo" --logo-type builtin "${probe[@]}" --structure Break --pipe false 2>&1)"
        used="$(printf '%s' "$out" | grep -o '38;5;20[1-9]m' | sort -u | sed 's/38;5;20//; s/m//' | tr '\n' ' ')"
        if [[ -z "$used" ]]; then fail "$logo: render bez kolorów logo — fastfetch nie zna tego logo?"
        elif [[ "$used" =~ [789] ]]; then fail "$logo zużywa kolory $used — dopisz brakujące numery do każdego rice'a i do tego testu"
        else ok "$logo zużywa kolory: $used(≤ 6)"; fi
    done
    for rice in "${RICES[@]}"; do
        real="$(readlink -f -- "$REPO/rices/$rice/fastfetch/config.jsonc" 2>/dev/null || true)"
        [[ -f "$real" ]] || continue
        mapfile -t allowed < <(python3 -I "$T/check.py" --colors "$real" 2>/dev/null)
        bad=""
        for logo in arch Fedora NixOS; do
            out="$(fastfetch --config "$real" --logo "$logo" --structure Break --pipe false 2>&1)"
            while IFS= read -r seq; do
                code="${seq#$'\e['}"; code="${code%m}"
                [[ -z "$code" || "$code" == 1 ]] && continue
                hit=0
                for a in "${allowed[@]}"; do [[ "$code" == "$a" ]] && hit=1; done
                (( hit )) || bad+="$logo:$code "
            done < <(printf '%s' "$out" | grep -o $'\e\\[[0-9;]*m' | sort -u)
        done
        if [[ -z "$bad" ]]; then ok "$rice: logo Arch, Fedora i NixOS tylko w kolorach rice'a"
        else fail "$rice: kolory spoza palety rice'a w logo: $bad"; fi
    done
fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗ / $SKIP skip"
(( FAIL == 0 ))
