#!/usr/bin/env bash
# =============================================
#   archenemy - tests/waybar-dimmed.sh
#   Stany „wyłączone/wyciszone” w waybarze wyglądają jednakowo (zgłoszenie
#   właściciela 2026-11-24: wyciszony mikrofon nie był przygaszany, a
#   dzwonek „nie przeszkadzać” po włączeniu rozjaśniał się do akcentu).
#   Rodzinę stanów sprawdza test, nie wzrok — w KAŻDYM rice'ie z glob-a
#   rices/*/waybar/ (także beta):
#     - każdy stan przygaszenia modułu obecnego w pasku ma jawną regułę
#       `color` w style.css: #custom-micmute.muted, #custom-volumebar.muted,
#       #pulseaudio.muted (beta), #custom-bluetooth.disabled,
#       #custom-dnd.dnd i #custom-dnd.unavailable;
#     - wszystkie mają TEN SAM kolor (jeden kolor przygaszenia na rice);
#     - ten kolor nie jest kolorem tekstu modułów, hovera ani stanów
#       wyróżnionych (#custom-bluetooth.connected, #custom-volumebar.boost)
#       i różni się od tekstu modułów co najmniej MIN_CONTRAST (WCAG) —
#       przygaszenie ma być widać;
#     - custom/micmute daje klasę: exec scripts/waybar/micmute.sh,
#       return-type json (bez tego waybar nie dostaje klasy i CSS nie ma
#       czego przygasić), interval całkowity 1, signal 9.
#   Sam skrypt scripts/waybar/micmute.sh na atrapie wpctl: wyciszony →
#   klasa muted, włączony → unmuted, wpctl z błędem albo brak wpctl →
#   unmuted, kod 0 zawsze (niezerowy chowa moduł).
#   Bez roota, bez PipeWire i waybara, zapis tylko w mktemp.
#   Uruchom: bash tests/waybar-dimmed.sh   (kod 0 = wszystko przeszło)
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

SCRIPT="$REPO/scripts/waybar/micmute.sh"

echo "== scripts/waybar/micmute.sh (atrapa wpctl)"
if [[ ! -f "$SCRIPT" ]]; then
    fail "brak scripts/waybar/micmute.sh"
else
    # Atrapa wpctl: odpowiedź z $MOCK_WPCTL (muted|unmuted|error); wywołania w logu.
    mkdir -p "$T/bin" "$T/bin-nowpctl"
    cat > "$T/bin/wpctl" <<'EOF'
#!/usr/bin/env bash
echo "wpctl $*" >> "$MOCK_LOG"
case "$MOCK_WPCTL" in
    muted)   echo 'Volume: 0.40 [MUTED]' ;;
    unmuted) echo 'Volume: 0.40' ;;
    *)       echo 'Object not found' >&2; exit 1 ;;
esac
EOF
    chmod 755 "$T/bin/wpctl"
    for tool in bash env timeout; do ln -s "$(command -v "$tool")" "$T/bin-nowpctl/$tool"; done
    export MOCK_LOG="$T/wpctl.log"
    # Glify z bajtów UTF-8 (U+F036D microphone_off, U+F036C microphone).
    G_MUTED=$(printf '\xf3\xb0\x8d\xad')
    G_UNMUTED=$(printf '\xf3\xb0\x8d\xac')
    # check_mic <PATH> <stan atrapy> <klasa> <glif> <opis>
    check_mic() {
        local out rc verdict
        : > "$MOCK_LOG"
        out="$(PATH="$1" MOCK_WPCTL="$2" bash "$SCRIPT" 2>"$T/err")"; rc=$?
        verdict="$(python3 -c 'import json, sys
try:
    d = json.loads(sys.argv[1])
except ValueError:
    print("nie JSON"); sys.exit()
want = {"text": sys.argv[3], "class": sys.argv[2], "alt": sys.argv[2]}
bad = [k for k, v in want.items() if d.get(k) != v]
print("ok" if not bad and sys.argv[1].count("\n") == 0 else "złe pola: " + ",".join(bad))' "$out" "$3" "$4")"
        if [[ "$rc" == 0 && "$verdict" == ok && ! -s "$T/err" ]]; then ok "$5"
        else fail "$5: kod=$rc, $verdict, stderr=[$(head -c 200 "$T/err")] [$out]"; fi
    }
    check_mic "$T/bin:$PATH" muted   muted   "$G_MUTED"   "wyciszony → klasa muted, glif mikrofonu przekreślonego"
    if grep -q -- '@DEFAULT_AUDIO_SOURCE@' "$MOCK_LOG"; then ok "pyta domyślne źródło (@DEFAULT_AUDIO_SOURCE@)"
    else fail "wpctl wołane bez @DEFAULT_AUDIO_SOURCE@: $(cat "$MOCK_LOG")"; fi
    check_mic "$T/bin:$PATH" unmuted unmuted "$G_UNMUTED" "włączony → klasa unmuted"
    check_mic "$T/bin:$PATH" error   unmuted "$G_UNMUTED" "wpctl z błędem → unmuted, kod 0"
    check_mic "$T/bin-nowpctl"  muted unmuted "$G_UNMUTED" "brak wpctl → unmuted, kod 0"
fi

MIN_CONTRAST=1.5
echo "== kolor przygaszenia w każdym rice'ie (rices/*/waybar/, min. kontrast z tekstem $MIN_CONTRAST)"
css_out=$(python3 - "$REPO" "$MIN_CONTRAST" <<'PY'
import glob, json, os, re, sys
repo, min_contrast = sys.argv[1], float(sys.argv[2])

# Moduł w pasku → selektory jego stanów przygaszenia.
DIM = {
    "custom/micmute":   ["#custom-micmute.muted"],
    "custom/volumebar": ["#custom-volumebar.muted"],
    "pulseaudio":       ["#pulseaudio.muted"],
    "custom/bluetooth": ["#custom-bluetooth.disabled"],
    "custom/dnd":       ["#custom-dnd.dnd", "#custom-dnd.unavailable"],
}
# Moduł → selektory, których kolorem przygaszenie być NIE może.
BRIGHT = {
    "custom/micmute":   ["#custom-micmute", "#custom-micmute:hover"],
    "custom/volumebar": ["#custom-volumebar", "#custom-volumebar:hover", "#custom-volumebar.boost"],
    "pulseaudio":       ["#pulseaudio", "#pulseaudio:hover"],
    "custom/bluetooth": ["#custom-bluetooth", "#custom-bluetooth:hover", "#custom-bluetooth.connected"],
    "custom/dnd":       ["#custom-dnd", "#custom-dnd:hover"],
}

def colors(css):
    """Selektor → kolor z OSTATNIEJ reguły, która go wymienia i ustawia color."""
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    found = {}
    for sels, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
        decl = re.findall(r"(?<![-\w])color\s*:\s*([^;]+?)\s*(?:;|$)", body)
        if not decl:
            continue
        for sel in sels.split(","):
            found[" ".join(sel.split())] = decl[-1].lower()
    return found

def lum(hexcolor):
    h = hexcolor.lstrip("#")
    if not re.fullmatch(r"[0-9a-f]{6}", h):
        return None
    out = 0.0
    for weight, i in ((0.2126, 0), (0.7152, 2), (0.0722, 4)):
        c = int(h[i:i + 2], 16) / 255
        out += weight * (c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out

def contrast(a, b):
    la, lb = lum(a), lum(b)
    if la is None or lb is None:
        return None
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

rices = sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(f"{repo}/rices/*/waybar"))
print(f"info rice'ów: {len(rices)} ({' '.join(rices)})")
for rice in rices:
    text = open(f"{repo}/rices/{rice}/waybar/config.jsonc").read()
    cfg = json.loads(re.sub(r"//[^\n]*", "", text))
    bar = [m for key in ("modules-left", "modules-center", "modules-right") for m in cfg.get(key, [])]
    col = colors(open(f"{repo}/rices/{rice}/waybar/style.css").read())
    present = [m for m in DIM if m in bar]
    dims = {}
    for module in present:
        for sel in DIM[module]:
            if sel in col:
                dims[sel] = col[sel]
                print(f"ok {rice}: jawny kolor {sel} ({col[sel]})")
            else:
                print(f"FAIL {rice}: brak reguły color dla {sel}")
    shades = sorted(set(dims.values()))
    if len(shades) == 1:
        print(f"ok {rice}: jeden kolor przygaszenia {shades[0]} ({len(dims)} stanów)")
    elif shades:
        groups = ", ".join(f"{c}: " + " ".join(s for s, v in dims.items() if v == c) for c in shades)
        print(f"FAIL {rice}: różne kolory przygaszenia — {groups}")
    for module in present:
        for sel in BRIGHT[module]:
            if sel in col and col[sel] in shades:
                print(f"FAIL {rice}: przygaszenie ma kolor {sel} ({col[sel]})")
    base = col.get("#custom-micmute")
    if base is None:
        print(f"FAIL {rice}: brak koloru tekstu #custom-micmute")
        continue
    for shade in shades:
        c = contrast(shade, base)
        if c is None:
            print(f"FAIL {rice}: kolor {shade} albo {base} nie jest #rrggbb (nie da się policzyć kontrastu)")
        elif c >= min_contrast:
            print(f"ok {rice}: przygaszenie {shade} odróżnia się od tekstu {base} ({c:.2f}:1)")
        else:
            print(f"FAIL {rice}: przygaszenie {shade} za bliskie tekstu {base} ({c:.2f}:1 < {min_contrast})")
    # Moduł mikrofonu musi dostawać klasę od skryptu.
    if "custom/micmute" in bar:
        m = cfg.get("custom/micmute", {})
        checks = {
            "exec micmute.sh": m.get("exec") == "~/archenemy/scripts/waybar/micmute.sh",
            "return-type json": m.get("return-type") == "json",
            "interval całkowity 1": type(m.get("interval")) is int and m.get("interval") == 1,
            "signal 9": m.get("signal") == 9,
        }
        for name, good in checks.items():
            print(("ok" if good else "FAIL") + f" {rice}: custom/micmute {name}")
PY
)
while IFS= read -r line; do
    case "$line" in
        ok\ *)   ok "${line#ok }" ;;
        info\ *) echo "  · ${line#info }" ;;
        *)       fail "${line#FAIL }" ;;
    esac
done <<< "$css_out"

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
(( FAIL == 0 ))
