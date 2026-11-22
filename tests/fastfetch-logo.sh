#!/usr/bin/env bash
# =============================================
#   archenemy - tests/fastfetch-logo.sh
#   Logo fastfetcha na każdym rice idzie za „system logo” (decyzja właściciela
#   2026-11-22: „fastfetch też ma iść za system logo”; wcześniej 2026-11-18:
#   zawsze logo dystrybucji): domyślnie wbudowane logo WYKRYTEJ dystrybucji
#   w kolorach rice'a, w trybie archenemy znak Æ w pierwszym kolorze rice'a.
#   Każdy rices/*/fastfetch/config.jsonc (po rozwiązaniu dowiązań) ma:
#     - "logo" z "type": "auto" i "source" = plik warstwy maszynowej
#       ~/archenemy/data/fastfetch-logo.txt: plik jest → logo z pliku (Æ);
#       pliku nie ma → fastfetch sam wybiera logo dystrybucji (Arch na Archu,
#       Fedora na Fedorze, NixOS na NixOS; stałe "source": "arch" pokazywało
#       logo Archa także na Fedorze i NixOS),
#     - żadnego pliku z logo w katalogu rice'a (znak Æ leży raz, w
#       assets/logo/archenemy-ae.txt, i powstaje z archenemy-ae.svg),
#     - kolory "1"–"6" jako kody SGR: logo Arch i Fedora zużywa $1–$2, NixOS
#       $1–$6 (fastfetch 2.71, sprawdzone renderem z kolorami 1–9) — brak
#       numeru = ta część logo w domyślnym kolorze fastfetcha, nie rice'a.
#   Z fastfetchem w PATH dodatkowo: logo Arch/Fedora/NixOS nie zużywa numerów
#   powyżej 6, a render configu każdego rice'a z każdym z tych logo nie ma
#   ani jednego koloru spoza bloku "color" (bez fastfetcha: widoczny skip).
#   Logo dystrybucji rysuje fastfetch ze swojego zestawu znaków — w repo nie
#   ma pliku z logo dystrybucji. Plik w warstwie maszynowej zakłada i usuwa
#   scripts/waybar/launcher-logo.sh sync (sprawdzane niżej na atrapie HOME).
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
SOURCE = "~/archenemy/data/fastfetch-logo.txt"
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
    if logo.get("type") != "auto":
        return f"\"type\": {json.dumps(logo.get('type'))} zamiast \"auto\" — logo nie idzie za system logo"
    if logo.get("source") != SOURCE:
        return f"\"source\": {json.dumps(logo.get('source'))} zamiast pliku warstwy maszynowej {SOURCE}"
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
SRC='"source": "~/archenemy/data/fastfetch-logo.txt"'
declare -A CASES=(
    [dobry]="{ // komentarz \"x\"
  \"\$schema\": \"https://example.invalid/s.json\", \"logo\": {\"type\": \"auto\", $SRC, $GOOD}}"
    [source-arch]="{\"logo\": {\"source\": \"arch\", \"type\": \"auto\", $GOOD}}"
    [builtin-bez-source]="{\"logo\": {\"type\": \"builtin\", $GOOD}}"
    [auto-bez-source]="{\"logo\": {\"type\": \"auto\", $GOOD}}"
    [type-file]="{\"logo\": {\"type\": \"file\", \"source\": \"~/.config/fastfetch/logo.txt\", $GOOD}}"
    [bez-typu]="{\"logo\": {$SRC, $GOOD}}"
    [bez-logo]='{"modules": ["title"]}'
    [bez-koloru-3]="{\"logo\": {\"type\": \"auto\", $SRC, \"color\": {\"1\":\"34\",\"2\":\"36\",\"4\":\"36\",\"5\":\"34\",\"6\":\"36\"}}}"
    [tylko-1-2]="{\"logo\": {\"type\": \"auto\", $SRC, \"color\": {\"1\":\"34\",\"2\":\"36\"}}}"
)
for name in dobry source-arch builtin-bez-source auto-bez-source type-file bez-typu bez-logo bez-koloru-3 tylko-1-2; do
    printf '%s\n' "${CASES[$name]}" > "$T/$name.jsonc"
    why="$(python3 -I "$T/check.py" "$T/$name.jsonc")"
    if [[ "$name" == dobry ]]; then
        if [[ -z "$why" ]]; then ok "dobry config przechodzi (komentarz z cudzysłowem, https:// w łańcuchu)"
        else fail "dobry config odrzucony: $why"; fi
    elif [[ -n "$why" ]]; then ok "$name odrzucony: $why"
    else fail "$name przepuszczony — sprawdzarka nic nie dowodzi"; fi
done

echo "== każdy rice: logo systemu (plik Æ albo wykryta dystrybucja) w kolorach rice'a"
mapfile -t RICES < <(cd "$REPO/rices" && for d in */; do echo "${d%/}"; done | sort)
if (( ${#RICES[@]} == 0 )); then fail "brak katalogów w rices/"; fi
for rice in "${RICES[@]}"; do
    cfg="$REPO/rices/$rice/fastfetch/config.jsonc"
    real="$(readlink -f -- "$cfg" 2>/dev/null || true)"
    if [[ -z "$real" || ! -f "$real" ]]; then fail "$rice: brak fastfetch/config.jsonc (albo wiszący link)"; continue; fi
    case "$real" in "$REPO"/rices/*) ;; *) fail "$rice: config wskazuje poza rices/ ($real)"; continue ;; esac
    why="$(python3 -I "$T/check.py" "$real")"
    if [[ -z "$why" ]]; then ok "$rice: auto + plik warstwy maszynowej, kolory 1–6"; else fail "$rice: $why"; fi
    extra="$(find "$(dirname "$real")" -mindepth 1 -maxdepth 1 ! -name config.jsonc -printf '%f ' 2>/dev/null)"
    if [[ -z "$extra" ]]; then ok "$rice: w fastfetch/ tylko config.jsonc (żadnego pliku z logo)"
    else fail "$rice: w fastfetch/ zbędne pliki: $extra"; fi
done

echo "== znak Æ jako tekst i launcher-logo.sh sync"
AE="$REPO/assets/logo/archenemy-ae.txt"
if [[ -s "$AE" && "$(python3 -I "$REPO/assets/logo/gen_text_logo.py" --print 2>/dev/null)" == "$(cat "$AE")" ]]; then
    ok "archenemy-ae.txt = wynik gen_text_logo.py (ta sama geometria co archenemy-ae.svg)"
else fail "archenemy-ae.txt różni się od wyniku gen_text_logo.py — uruchom: python3 assets/logo/gen_text_logo.py"; fi
cat > "$T/shape.py" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
body = [lines[0][2:]] + lines[1:-1]
good = lines[0].startswith("$1") and lines[-1] == "" and 8 <= len(body) <= 19
good = good and all(len(l) <= 38 and set(l) <= set(" █▀▄") for l in body)
good = good and sum(l.count("█") for l in body) > 100
print("ok" if good else "bad")
PY
if [[ "$(python3 -I "$T/shape.py" "$AE" 2>/dev/null)" == ok ]]; then
    ok "znak Æ: zaczyna się od \$1, najwyżej 19 wierszy × 38 znaków (jak logo Archa), same półbloki"
else fail "archenemy-ae.txt ma zły kształt (\$1 na początku, ≤ 19 × 38, znaki ▀▄█ i spacja)"; fi
# sync na atrapie HOME; skrypt z repo, więc znak bierze z assets/logo repo.
FH="$T/fhome"; mkdir -p "$FH/archenemy/data"
fsync() { HOME="$FH" bash "$REPO/scripts/waybar/launcher-logo.sh" sync; }
FL="$FH/archenemy/data/fastfetch-logo.txt"
fsync; rc=$?
if [[ $rc -eq 0 && ! -e "$FL" ]]; then ok "sync bez wyboru (distro): pliku logo nie ma, kod 0"; else fail "sync w trybie distro: kod $rc albo plik istnieje"; fi
echo archenemy > "$FH/archenemy/data/launcher-logo.dat"; fsync; rc=$?
if [[ $rc -eq 0 ]] && cmp -s "$FL" "$AE"; then ok "sync w trybie archenemy: plik logo = znak Æ, kod 0"; else fail "sync w trybie archenemy: kod $rc albo zły plik"; fi
ino="$(stat -c %i "$FL" 2>/dev/null)"; fsync
if [[ "$(stat -c %i "$FL" 2>/dev/null)" == "$ino" ]]; then ok "sync bez zmiany nie przepisuje pliku"; else fail "sync przepisał niezmieniony plik"; fi
echo "stary znak" > "$FL"; fsync
if cmp -s "$FL" "$AE"; then ok "sync podmienia nieaktualny plik logo"; else fail "sync zostawił nieaktualny plik logo"; fi
echo "archenemy; rm -rf /" > "$FH/archenemy/data/launcher-logo.dat"; fsync; rc=$?
if [[ $rc -eq 0 && ! -e "$FL" ]]; then ok "śmieci w wyborze = distro: plik logo usunięty"; else fail "śmieci w wyborze: plik logo został"; fi
echo archenemy > "$FH/archenemy/data/launcher-logo.dat"; chmod 555 "$FH/archenemy/data"
if [[ "$(id -u)" == 0 ]]; then skip "niezapisywalny katalog: root pisze mimo trybu 555"
else
    fsync; rc=$?
    if [[ $rc -ne 0 && ! -e "$FL" ]]; then ok "niezapisywalny katalog: kod 1, bez pliku"; else fail "niezapisywalny katalog: kod $rc"; fi
fi
chmod 755 "$FH/archenemy/data"

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
    # Oba tryby na prawdziwym fastfetchu i configu rice'a, HOME = atrapa:
    # bez pliku logo wykrytej dystrybucji (żadnego półbloku Æ), z plikiem znak Æ
    # w pierwszym kolorze rice'a i żadnego koloru spoza bloku "color".
    mark_line="$(sed -n '3p' "$AE")"
    for rice in "${RICES[@]}"; do
        real="$(readlink -f -- "$REPO/rices/$rice/fastfetch/config.jsonc" 2>/dev/null || true)"
        [[ -f "$real" ]] || continue
        mapfile -t allowed < <(python3 -I "$T/check.py" --colors "$real" 2>/dev/null)
        echo distro > "$FH/archenemy/data/launcher-logo.dat"; fsync
        plain="$(HOME="$FH" fastfetch --config "$real" --structure Break --pipe false 2>&1)"; prc=$?
        echo archenemy > "$FH/archenemy/data/launcher-logo.dat"; fsync
        mark="$(HOME="$FH" fastfetch --config "$real" --structure Break --pipe false 2>&1)"; mrc=$?
        bad=""
        while IFS= read -r seq; do
            code="${seq#$'\e['}"; code="${code%m}"
            [[ -z "$code" || "$code" == 1 ]] && continue
            hit=0
            for a in "${allowed[@]}"; do [[ "$code" == "$a" ]] && hit=1; done
            (( hit )) || bad+="$code "
        done < <(printf '%s' "$mark" | grep -o $'\e\\[[0-9;]*m' | sort -u)
        if [[ $prc -eq 0 && "$plain" != *"█"* && "$plain" != *"fastfetch-logo"* && -n "${plain//[[:space:]]/}" ]]; then
            ok "$rice: bez pliku fastfetch rysuje logo dystrybucji (bez błędu o brakującym pliku)"
        else fail "$rice: tryb distro — kod $prc albo w wyjściu jest znak Æ / błąd pliku"; fi
        if [[ $mrc -eq 0 && "$mark" == *"$mark_line"* && -z "$bad" ]]; then ok "$rice: z plikiem fastfetch rysuje znak Æ tylko w kolorach rice'a"
        else fail "$rice: tryb archenemy — kod $mrc, brak znaku Æ albo kolory spoza palety: $bad"; fi
    done
fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗ / $SKIP skip"
(( FAIL == 0 ))
