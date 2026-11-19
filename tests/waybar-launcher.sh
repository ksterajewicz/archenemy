#!/usr/bin/env bash
# =============================================
#   archenemy - tests/waybar-launcher.sh
#   Lewy box waybara: moduł custom/launcher (2026-11-19). Tekst i klasę daje
#   scripts/waybar/launcher-logo.sh (exec, return-type json, signal 12):
#   domyślnie glif dystrybucji (klasa distro), opcjonalnie logo projektu Æ
#   (klasa archenemy) — wybór w Super+A → [l]. Znak Æ wstawia CSS GTK:
#   #custom-launcher.archenemy { background-image: url("launcher.svg") },
#   gdzie rices/<rice>/waybar/launcher.svg to śledzony symlink do
#   assets/logo/rices/<rice>.svg. Pakiet pilnuje warunków, bez których
#   launcher po cichu znika albo wygląda inaczej (GTK nie zgłasza błędów w pasku):
#     - względny url() GTK liczy od katalogu style.css (GFile, bez realpath),
#       więc launcher.svg musi leżeć obok style.css i wskazywać plik w repo
#       także przez link ~/.config/waybar → rices/<rice>/waybar;
#     - Waybar (src/client.cpp, setupCss) wczytuje plik ścieżką tylko wtedy,
#       gdy transform_8bit_to_hex nic nie przepisał; kolor #RRGGBBAA = CSS
#       z danych (load_from_data) i względny url() przestaje działać;
#     - "format" musi przepuścić tekst skryptu ({}): stała spacja z czasów
#       samego Æ zgubiłaby glif; bez "interval" (Waybar custom.cpp: sam
#       "signal" = waitingWorker, skrypt raz + po sygnale), sygnał 12 wolny;
#     - obraz tylko pod klasą .archenemy, glif (kolor, rozmiar) pod .distro;
#     - skrót `background:` w regułach launchera zeruje background-image;
#     - glify dystrybucji żyją tylko w scripts/waybar/launcher-logo.sh.
#   Sam skrypt (tryby, os-release) testuje tests/launcher-logo.sh.
#   Bez roota, zapis tylko w mktemp (atrapa ~/.config z linkiem do rice'a).
#   Uruchom: bash tests/waybar-launcher.sh   (kod 0 = wszystko przeszło)
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

LOGO_DIR="$REPO/assets/logo"
# Rice'y z launcherem — z listy modułów configu, nie z ręcznej listy.
mapfile -t WITH < <(cd "$REPO/rices" && grep -l '"custom/launcher"' -- */waybar/config.jsonc | cut -d/ -f1 | sort)
mapfile -t ALL < <(cd "$REPO/rices" && for d in */; do echo "${d%/}"; done | sort)

echo "== rice'y z custom/launcher"
if [[ "${WITH[*]}" == "crt dither-flux tron yin" ]]; then
    ok "launcher mają: ${WITH[*]}"
else
    fail "launcher mają: ${WITH[*]:-(żaden)} (oczekiwano crt dither-flux tron yin — nowy rice z launcherem: dopisz go tu i daj mu launcher.svg)"
fi

echo "== config.jsonc: exec launcher-logo.sh, json, format {}, signal 12, bez interval, obie akcje"
for r in "${WITH[@]}"; do
    out=$(python3 - "$REPO/rices/$r/waybar/config.jsonc" <<'EOF'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'"custom/launcher":\s*\{(.*?)\n\s*\}', s, re.S)
if not m:
    print('brak bloku'); sys.exit()
b = m.group(1)
def val(k):
    f = re.search(r'"' + k + r'":\s*("(?:[^"\\]|\\.)*"|[0-9.]+)', b)
    return f.group(1) if f else None
print('exec=' + str(val('exec')), 'json=' + str(val('return-type')), 'format=' + str(val('format')),
      'signal=' + str(val('signal')), 'interval=' + str(val('interval')),
      'lpm=' + str('"on-click": "~/archenemy/scripts/rofi/rofi_drun.sh"' in b),
      'ppm=' + str('"on-click-right": "~/archenemy/scripts/rofi/rofi_power_menu.sh"' in b))
EOF
)
    if [[ "$out" == 'exec="~/archenemy/scripts/waybar/launcher-logo.sh" json="json" format="{}" signal=12 interval=None lpm=True ppm=True' ]]; then
        ok "$r: exec launcher-logo.sh, json, format {}, signal 12, bez interval, LPM rofi_drun, PPM power menu"
    else fail "$r: $out"; fi
done
# Sygnał 12 należy tylko do launchera: inny moduł z 12 odświeżałby się razem
# z nim, a pkill -RTMIN+12 z TUI trafiałby w cudzy moduł.
others=$(cd "$REPO" && python3 - rices/*/waybar/config.jsonc <<'EOF'
import re, sys
for f in sys.argv[1:]:
    s = open(f, encoding='utf-8').read()
    for m in re.finditer(r'"([a-z/_-]+)":\s*\{([^{}]*)\}', s, re.S):
        if re.search(r'"signal":\s*12\b', m.group(2)) and m.group(1) != 'custom/launcher':
            print(f + ':' + m.group(1))
EOF
)
rtmin=$(git -C "$REPO" grep -nE '^[^#]*RTMIN\+12([^0-9]|$)' -- scripts/ | grep -v '^scripts/appbinds/appbinds.sh:' || true)
if [[ -z "$others" && -z "$rtmin" ]]; then ok "sygnał 12 tylko dla custom/launcher (pkill -RTMIN+12 tylko w appbinds.sh)"
else fail "sygnał 12 zajęty także przez: ${others}${rtmin}"; fi

echo "== style.css: obraz tylko w .archenemy, glif w .distro, bez #RRGGBBAA, bez skrótu background"
HEX8_RE='#[0-9A-Fa-f]{8}([^0-9A-Fa-f]|$)'
for r in "${WITH[@]}"; do
    css="$REPO/rices/$r/waybar/style.css"
    rule_of() { awk -v sel="$1 {" '$0 == sel {f=1} f{print} f&&/^\}/{exit}' "$css"; }
    base=$(rule_of '#custom-launcher')
    ae=$(rule_of '#custom-launcher.archenemy')
    distro=$(rule_of '#custom-launcher.distro')
    all=$(awk '/^#custom-launcher[^ ]* \{/{f=1} f{print} f&&/^\}/{f=0}' "$css")
    if [[ "$ae" == *'background-image:    url("launcher.svg");'* && "$ae" == *'background-size:'* ]]; then ok "$r: #custom-launcher.archenemy → url(\"launcher.svg\")"
    else fail "$r: brak background-image url(\"launcher.svg\") w #custom-launcher.archenemy"; fi
    n_img=$(grep -c 'background-image' <<< "$all")
    if [[ "$n_img" == 1 && "$base" != *background-image* && "$distro" != *background-image* ]]; then ok "$r: obraz tylko w trybie archenemy"
    else fail "$r: background-image poza .archenemy (deklaracji z obrazem: $n_img)"; fi
    if [[ "$distro" == *'font-size:'* && "$distro" == *'color:'* && "$base" != *'font-size'* && "$base" != *'color:'* ]]; then ok "$r: glif (kolor, rozmiar) tylko w .distro"
    else fail "$r: .distro bez koloru/rozmiaru glifu albo glif w regule wspólnej"; fi
    if [[ "$base" == *'margin:'* && "$base" == *'border-right:'* ]]; then ok "$r: margines i hairline wspólne dla obu trybów"
    else fail "$r: #custom-launcher bez wspólnego marginesu/hairline"; fi
    if grep -qE '^[[:space:]]*background:' <<< "$all"; then
        fail "$r: reguła launchera ma skrót background: — zeruje obraz (użyj background-color)"
    else ok "$r: reguły launchera bez skrótu background"; fi
    hits=$(grep -nE "$HEX8_RE" "$css" || true)
    if [[ -z "$hits" ]]; then ok "$r: brak kolorów #RRGGBBAA (Waybar wczyta plik ścieżką)"
    else fail "$r: #RRGGBBAA → Waybar wczyta CSS jako tekst i url() nie zadziała: $hits"; fi
done
# Kontrola wzorca: łapie 8 cyfr, przepuszcza 6 i rgba().
hits=$(printf '%s\n' 'color: #11223344;' 'a{color:#AABBCCDD}' | grep -cE "$HEX8_RE")
miss=$(printf '%s\n' 'color: #112233;' 'color: rgba(1, 2, 3, 0.5);' 'color: #1122334;' | grep -cE "$HEX8_RE")
if [[ "$hits" == 2 && "$miss" == 0 ]]; then ok "wzorzec #RRGGBBAA łapie 8 cyfr, przepuszcza 6/7 i rgba()"
else fail "wzorzec #RRGGBBAA łapie źle (trafienia $hits z 2, fałszywe $miss)"; fi

echo "== launcher.svg: śledzony symlink do assets/logo/rices/<rice>.svg"
for r in "${WITH[@]}"; do
    rel="rices/$r/waybar/launcher.svg"
    mode=$(git -C "$REPO" ls-files -s -- "$rel" | awk '{print $1}')
    target=$(readlink "$REPO/$rel" 2>/dev/null || true)
    if [[ "$mode" == 120000 && "$target" == "../../../assets/logo/rices/$r.svg" && -f "$LOGO_DIR/rices/$r.svg" ]]; then
        ok "$r: $rel → $target (w indeksie jako symlink)"
    else
        fail "$r: $rel tryb=${mode:-brak w gicie} cel=${target:-brak}"
    fi
done
for r in "${ALL[@]}"; do
    [[ " ${WITH[*]} " == *" $r "* ]] && continue
    if [[ -e "$REPO/rices/$r/waybar/launcher.svg" || -L "$REPO/rices/$r/waybar/launcher.svg" ]]; then fail "$r nie ma launchera, a ma waybar/launcher.svg"
    else ok "$r: bez launchera i bez launcher.svg"; fi
done

echo "== atrapa ~/.config/waybar (link jak ln -sfn w lib/switch-rice.sh)"
# GTK: rodzic GFile pliku style.css (tekstowo, bez realpath) + "launcher.svg";
# jądro rozwiązuje potem oba linki fizycznie. Sprawdzamy, że ta ścieżka po
# każdej zmianie rice'a wskazuje plik koloru TEGO rice'a.
mkdir -p "$T/home/.config"
ln -s "$REPO" "$T/home/archenemy"
for r in "${WITH[@]}"; do
    ln -sfn "$T/home/archenemy/rices/$r/waybar" "$T/home/.config/waybar"
    css_dir=$(dirname "$T/home/.config/waybar/style.css")
    got=$(readlink -f "$css_dir/launcher.svg" 2>/dev/null || true)
    want=$(readlink -f "$LOGO_DIR/rices/$r.svg")
    if [[ -n "$got" && "$got" == "$want" ]]; then ok "$r: ~/.config/waybar/launcher.svg → assets/logo/rices/$r.svg"
    else fail "$r: ~/.config/waybar/launcher.svg → ${got:-nic}"; fi
done

echo "== assets/logo: jedna geometria, bez fontów i zasobów zewnętrznych"
out=$(python3 - "$LOGO_DIR" <<'EOF'
import glob, os, sys
import xml.etree.ElementTree as ET
d = sys.argv[1]
NS = '{http://www.w3.org/2000/svg}'
files = [os.path.join(d, 'archenemy-ae.svg')] + sorted(glob.glob(os.path.join(d, 'rices', '*.svg')))
paths, bad = set(), []
for f in files:
    raw = open(f, encoding='utf-8').read()
    root = ET.fromstring(raw)
    tags = sorted({e.tag.replace(NS, '') for e in root.iter()})
    if tags != ['path', 'svg', 'title']:
        bad.append(f'{os.path.basename(f)}: elementy {tags}')
    if any(k in raw for k in ('href', 'url(', '@import', 'font')):
        bad.append(f'{os.path.basename(f)}: odwołanie zewnętrzne/font')
    p = root.findall(NS + 'path')
    if len(p) != 1:
        bad.append(f'{os.path.basename(f)}: {len(p)} ścieżek')
    else:
        paths.add(p[0].get('d'))
print(f'pliki={len(files)} geometrie={len(paths)}', *bad, sep='\n')
EOF
)
if [[ "$out" == "pliki=9 geometrie=1" ]]; then ok "9 plików SVG (baza + 8 wariantów), jedna geometria, tylko svg/title/path"
else fail "assets/logo: $out"; fi

echo "== glify dystrybucji tylko w scripts/waybar/launcher-logo.sh"
# Wzorce z bajtów UTF-8, żeby ten plik sam siebie nie łapał. Glif w configu
# albo w CSS obszedłby wybór z TUI (Super+A → [l]) i jedno miejsce podmiany.
ONLY="scripts/waybar/launcher-logo.sh"
for g in 'F08C7 \xf3\xb0\xa3\x87' 'F08DB \xf3\xb0\xa3\x9b' 'F1105 \xf3\xb1\x84\x85' 'F033D \xf3\xb0\x8c\xbd'; do
    cp="U+${g%% *}"
    # shellcheck disable=SC2059  # wzorzec bajtów to celowo format printf
    GLYPH=$(printf "${g#* }")
    files=$(git -C "$REPO" grep -lF "$GLYPH" -- . || true)
    if [[ "$files" == "$ONLY" ]]; then ok "$cp tylko w $ONLY"
    else fail "$cp w: ${files:-(nigdzie — skrypt go zgubił)}"; fi
done

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
(( FAIL == 0 ))
