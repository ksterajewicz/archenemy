#!/usr/bin/env bash
# =============================================
#   archenemy - tests/dnd.sh
#   Dzwonek „nie przeszkadzać” (2026-11-23): scripts/waybar/dnd.sh na
#   atrapie makoctl (tests/mock/makoctl) i atrapach pgrep/pkill, plus
#   configi waybara i maka wszystkich rice'ów.
#   Przypadki: brak makoctl, mako nie działa (zero wywołań makoctl — bez
#   aktywacji D-Bus), stan notify/dnd z "makoctl mode", dokładne dopasowanie
#   nazwy trybu, przełączenie w obie strony z zachowaniem innych trybów,
#   sygnał RTMIN+13 do waybara, makoctl z błędem / bez zmiany stanu /
#   zawieszony (limit czasu), poprawny JSON z podpowiedzią kliknięcia,
#   kod wyjścia modułu zawsze 0. Configi: custom/dnd raz w modules-right
#   7 rice'ów parytetu, signal 13 tylko tam, interval całkowity, style
#   stanów w CSS, beta bez modułu; każdy mako/config chowa powiadomienia
#   w DND i przepuszcza krytyczne (sekcja po [mode=do-not-disturb]).
#   Strażnik: każde notify-send w scripts/ config/ rices/ install/ ma
#   "-a archenemy" zaraz po nazwie komendy (z kontrolą negatywną).
#   Bez roota, bez maka i waybara, zapis tylko w mktemp.
#   Uruchom: bash tests/dnd.sh   (kod 0 = wszystko przeszło)
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

SCRIPT="$REPO/scripts/waybar/dnd.sh"

if [[ ! -f "$SCRIPT" ]]; then
    fail "brak scripts/waybar/dnd.sh"
    echo ""; echo "Wynik: $PASS ✓ / $FAIL ✗"; exit 1
fi

# Atrapy: makoctl z repo, pgrep (mako „działa”, gdy jest plik running)
# i pkill (tylko zapis wywołania — prawdziwy waybar hosta nic nie dostaje).
export MOCK_MAKO="$T/mako"
mkdir -p "$T/bin" "$T/bin-nomako" "$MOCK_MAKO"
cp "$REPO/tests/mock/makoctl" "$T/bin/makoctl"
cat > "$T/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
echo "pgrep $*" >> "$MOCK_MAKO/pgrep.log"
[[ -f "$MOCK_MAKO/running" ]]
EOF
cat > "$T/bin/pkill" <<'EOF'
#!/usr/bin/env bash
echo "pkill $*" >> "$MOCK_MAKO/pkill.log"
exit 1
EOF
# PATH bez makoctl: tylko to, czego skrypt i atrapy potrzebują (na laptopie
# w systemowym PATH jest prawdziwe makoctl — nie może się tu załapać).
cp "$T/bin/pgrep" "$T/bin/pkill" "$T/bin-nomako/"
for tool in bash env id timeout; do ln -s "$(command -v "$tool")" "$T/bin-nomako/$tool"; done
chmod 755 "$T"/bin/* "$T"/bin-nomako/pgrep "$T"/bin-nomako/pkill
BASE_PATH="$PATH"

# Glify z bajtów UTF-8 (U+F009A bell, U+F009B bell_off, U+F13E8 bell_cancel_outline).
G_NOTIFY=$(printf '\xf3\xb0\x82\x9a')
G_DND=$(printf '\xf3\xb0\x82\x9b')
G_UNAVAILABLE=$(printf '\xf3\xb1\x8f\xa8')

reset_mako() {   # reset_mako <tryb>... — świeży stan atrapy, mako działa
    rm -f "$MOCK_MAKO"/*
    printf '%s\n' "$@" > "$MOCK_MAKO/modes"
    : > "$MOCK_MAKO/log"; : > "$MOCK_MAKO/pkill.log"; : > "$MOCK_MAKO/pgrep.log"
    touch "$MOCK_MAKO/running"
}
# run [argumenty] → RC, OUT (stdout), stderr w $T/err; PATH z atrapami.
run() { OUT="$(PATH="$T/bin:$BASE_PATH" bash "$SCRIPT" "$@" 2>"$T/err")"; RC=$?; }
modes() { tr '\n' ' ' < "$MOCK_MAKO/modes"; }
# state_is <oczekiwany stan> <opis> — dnd.sh state: kod 0 i dokładnie ten stan.
state_is() {
    run state
    if [[ "$RC" == 0 && "$OUT" == "$1" ]]; then ok "$2"; else fail "$2: kod=$RC [$OUT]"; fi
}
# json_is <klasa> <glif> <opis> — po run: kod 0, pusty stderr, JSON z tą klasą,
# alt = klasa, tekst = glif i podpowiedź z „Click:” w drugiej linii.
json_is() {
    local verdict
    verdict=$(python3 -c 'import json,sys
d = json.loads(sys.argv[1])
want = dict(text=sys.argv[3], alt=sys.argv[2], **{"class": sys.argv[2]})
lines = d.get("tooltip", "").split("\n")
print("ok" if all(d.get(k) == v for k, v in want.items()) and len(lines) == 2 and lines[1].startswith("Click: ") else "zly")' "$OUT" "$1" "$2" 2>/dev/null)
    if [[ "$RC" == 0 && ! -s "$T/err" && "$verdict" == ok ]]; then ok "$3"
    else fail "$3: kod=$RC wyjście=[$OUT] stderr=[$(head -c 200 "$T/err")]"; fi
}

echo '== bez maka: ikona „niedostępne”, kod 0, bez wywołań makoctl'
reset_mako default
OUT="$(PATH="$T/bin-nomako" "$T/bin-nomako/bash" "$SCRIPT" 2>"$T/err")"; RC=$?
json_is unavailable "$G_UNAVAILABLE" "brak makoctl w PATH → unavailable"
rm -f "$MOCK_MAKO/running"
run
json_is unavailable "$G_UNAVAILABLE" "mako nie działa → unavailable"
if [[ ! -s "$MOCK_MAKO/log" ]]; then ok "mako nie działa → makoctl nie wołane (bez aktywacji D-Bus)"
else fail "makoctl wołane bez maka: $(tr '\n' ';' < "$MOCK_MAKO/log")"; fi
if grep -qx "pgrep -u $(id -u) -x mako" "$MOCK_MAKO/pgrep.log"; then ok "pgrep tylko po makach tego użytkownika"
else fail "pgrep: $(tr '\n' ';' < "$MOCK_MAKO/pgrep.log")"; fi
run toggle
if [[ "$RC" == 1 && ! -s "$MOCK_MAKO/log" && "$(modes)" == "default " ]]; then ok "toggle bez maka → kod 1, nic nie zmienia"
else fail "toggle bez maka: kod=$RC log=[$(tr '\n' ';' < "$MOCK_MAKO/log")] tryby=[$(modes)]"; fi
if grep -qx -- "pkill -RTMIN+13 -x waybar" "$MOCK_MAKO/pkill.log"; then ok "toggle bez maka i tak odświeża pasek"
else fail "brak pkill: $(tr '\n' ';' < "$MOCK_MAKO/pkill.log")"; fi

echo "== stan z makoctl mode"
reset_mako default
run
json_is notify "$G_NOTIFY" "tryb default → dzwonek (notify)"
state_is notify "state → notify"
reset_mako default do-not-disturb
run
json_is dnd "$G_DND" "default + do-not-disturb → przekreślony dzwonek (dnd)"
state_is dnd "state → dnd"
reset_mako do-not-disturb
state_is dnd "sam do-not-disturb → dnd"
reset_mako default do-not-disturb-later " do-not-disturb" Do-Not-Disturb
state_is notify "podobne nazwy trybów to nie DND"
: > "$MOCK_MAKO/modes"
state_is notify "pusta lista trybów → notify"

echo "== przełączanie"
reset_mako default away
run toggle
if [[ "$RC" == 0 && "$(modes)" == "default away do-not-disturb " ]]; then ok "notify → dnd, inne tryby zostają"
else fail "toggle 1: kod=$RC tryby=[$(modes)]"; fi
if grep -qx -- "makoctl mode -a do-not-disturb" "$MOCK_MAKO/log"; then ok "włączenie przez makoctl mode -a"
else fail "log: $(tr '\n' ';' < "$MOCK_MAKO/log")"; fi
if [[ "$(grep -cx -- "pkill -RTMIN+13 -x waybar" "$MOCK_MAKO/pkill.log")" == 1 ]]; then ok "jeden sygnał RTMIN+13 do waybara"
else fail "pkill: $(tr '\n' ';' < "$MOCK_MAKO/pkill.log")"; fi
run
json_is dnd "$G_DND" "po przełączeniu moduł pokazuje dnd"
run toggle
if [[ "$RC" == 0 && "$(modes)" == "default away " ]]; then ok "dnd → notify, inne tryby zostają"
else fail "toggle 2: kod=$RC tryby=[$(modes)]"; fi
if grep -qx -- "makoctl mode -r do-not-disturb" "$MOCK_MAKO/log"; then ok "wyłączenie przez makoctl mode -r"
else fail "log: $(tr '\n' ';' < "$MOCK_MAKO/log")"; fi
if ! grep -q -- " -t " "$MOCK_MAKO/log"; then ok "bez -t (dopiero od mako 1.9)"
else fail "użyto -t"; fi

echo "== makoctl z błędem, bez zmiany stanu, zawieszony"
reset_mako default
touch "$MOCK_MAKO/down"
run
json_is unavailable "$G_UNAVAILABLE" "makoctl kod 1 → unavailable, moduł kod 0"
run toggle
if [[ "$RC" == 1 ]]; then ok "toggle przy błędzie makoctl → kod 1"; else fail "toggle przy błędzie: kod=$RC"; fi
reset_mako default
touch "$MOCK_MAKO/stuck"
run toggle
if [[ "$RC" == 1 && "$(modes)" == "default " ]]; then ok "mako nie przyjęło zmiany → kod 1 (sukces = odczytany stan)"
else fail "stuck: kod=$RC tryby=[$(modes)]"; fi
reset_mako default
touch "$MOCK_MAKO/hang"
start=$SECONDS
run
elapsed=$((SECONDS - start))
json_is unavailable "$G_UNAVAILABLE" "zawieszony makoctl → unavailable"
if (( elapsed <= 10 )); then ok "limit czasu makoctl (${elapsed} s)"
else fail "moduł czekał ${elapsed} s na zawieszone makoctl"; fi

PARITY=(white-blue tron asia-n-rice dither-flux crt yin yang)
ALL_RICES=("${PARITY[@]}" white-blue_beta)
echo "== configi waybara (7 rice'ów parytetu) i beta"
cfg_out=$(python3 - "$REPO" "${PARITY[@]}" <<'PY'
import json, re, sys
repo, rices = sys.argv[1], sys.argv[2:]
def load(rice):
    text = open(f"{repo}/rices/{rice}/waybar/config.jsonc").read()
    return json.loads(re.sub(r"//[^\n]*", "", text))
for rice in rices:
    c = load(rice)
    m = c.get("custom/dnd", {})
    checks = {
        "raz w modules-right": c.get("modules-right", []).count("custom/dnd") == 1,
        "exec dnd.sh": m.get("exec") == "~/archenemy/scripts/waybar/dnd.sh",
        "return-type json": m.get("return-type") == "json",
        "signal 13": m.get("signal") == 13,
        "interval całkowity 10": type(m.get("interval")) is int and m.get("interval") == 10,
        "on-click toggle": m.get("on-click") == "~/archenemy/scripts/waybar/dnd.sh toggle",
        "sygnał 13 tylko u custom/dnd": [k for k, v in c.items() if isinstance(v, dict) and v.get("signal") == 13] == ["custom/dnd"],
    }
    for name, good in checks.items():
        print(("ok" if good else "FAIL") + f" {rice}: {name}")
    css = open(f"{repo}/rices/{rice}/waybar/style.css").read()
    for sel in ("#custom-dnd", "#custom-dnd.dnd", "#custom-dnd.unavailable"):
        print(("ok" if sel in css else "FAIL") + f" {rice}: style {sel}")
beta = open(f"{repo}/rices/white-blue_beta/waybar/config.jsonc").read()
print(("ok" if "custom/dnd" not in beta else "FAIL") + " white-blue_beta: bez modułu (beta zamrożona)")
PY
)
while IFS= read -r line; do
    case "$line" in
        ok\ *) ok "${line#ok }" ;;
        *)     fail "${line#FAIL }" ;;
    esac
done <<< "$cfg_out"

echo "== mako: DND chowa, krytyczne przechodzą (wszystkie rice'y, beta przez symlink)"
for rice in "${ALL_RICES[@]}"; do
    f="$REPO/rices/$rice/mako/config"
    verdict=$(python3 - "$f" <<'PY'
import re, sys
sections, cur = [], None
for raw in open(sys.argv[1]):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    m = re.fullmatch(r"\[(.*)\]", line)
    if m:
        cur = (frozenset(m[1].split()), {})
        sections.append(cur)
    elif cur is not None and "=" in line:
        k, v = line.split("=", 1)
        cur[1][k] = v
dnd = frozenset({"mode=do-not-disturb"})
crit = frozenset({"mode=do-not-disturb", "urgency=critical"})
def last(crits, key):
    # ostatnia wartość key wśród sekcji, których kryteria pasują do crits
    vals = [opts[key] for k, opts in sections if k <= crits and key in opts]
    return vals[-1] if vals else None
normal = frozenset({"mode=do-not-disturb", "urgency=normal"})
low = frozenset({"mode=do-not-disturb", "urgency=low"})
good = last(normal, "invisible") == "1" and last(low, "invisible") == "1" and last(crit, "invisible") == "0"
print("ok" if good else f"zly normal={last(normal, 'invisible')} low={last(low, 'invisible')} critical={last(crit, 'invisible')}")
PY
)
    if [[ "$verdict" == ok ]]; then ok "$rice: DND chowa normal/low, critical widoczne"
    else fail "$rice: $verdict"; fi
done

# Każde wywołanie notify-send w kodzie repo ma "-a archenemy" zaraz po nazwie
# komendy — po tym mako odróżnia powiadomienia archenemy od aplikacji
# (sekcje [mode=do-not-disturb app-name=archenemy]). Bez flagi libnotify
# wysyła app-name "notify-send", jak każdy cudzy skrypt, i DND by je schował.
# Pomija komentarze i "command -v notify-send". Wypisuje plik:linia naruszeń.
untagged_notify() {
    python3 - "$@" <<'PY'
import os, re, sys
call = re.compile(r"(?<![\w-])notify-send(?![\w-])")
for root in sys.argv[1:]:
    for dirpath, _, files in os.walk(root):
        for name in sorted(files):
            path = os.path.join(dirpath, name)
            try:
                lines = open(path, encoding="utf-8").read().splitlines()
            except (UnicodeDecodeError, OSError):
                continue
            for no, line in enumerate(lines, 1):
                if line.lstrip().startswith("#"):
                    continue
                for m in call.finditer(line):
                    if line[:m.start()].endswith("command -v "):
                        continue
                    if not re.match(r" -a archenemy(\s|$)", line[m.end():]):
                        print(f"{path}:{no}")
PY
}

echo "== notify-send zawsze z -a archenemy (DND przepuszcza tylko archenemy)"
hits=$(untagged_notify "$REPO/scripts" "$REPO/config" "$REPO/rices" "$REPO/install")
if [[ -z "$hits" ]]; then ok "scripts/ config/ rices/ install/: każde notify-send ma -a archenemy"
else fail "notify-send bez -a archenemy: $(tr '\n' ' ' <<< "${hits//$REPO\//}")"; fi
n_calls=$(grep -rhoE 'notify-send -a archenemy( |$)' "$REPO/scripts" | wc -l)
if (( n_calls >= 36 )); then ok "wywołania z -a archenemy w scripts/: $n_calls (≥ 36 z inwentarza 2026-11-23)"
else fail "tylko $n_calls wywołań notify-send -a archenemy w scripts/ (strażnik nic nie widzi?)"; fi
# Kontrola negatywna: strażnik łapie każdą postać wywołania bez flagi.
mkdir -p "$T/guard"
cat > "$T/guard/bad.sh" <<'EOF'
notify-send "archenemy" "zwykłe"
command -v notify-send >/dev/null && notify-send -u low "archenemy" "po &&"
notify-send -u critical -a archenemy "archenemy" "flaga nie na początku"
x || notify-send --app-name=archenemy "archenemy" "długa postać"
EOF
cat > "$T/guard/good.sh" <<'EOF'
# notify-send w komentarzu nie jest wywołaniem
command -v notify-send >/dev/null 2>&1 || return 0
notify-send -a archenemy "archenemy" "dobrze"
command -v notify-send &>/dev/null && notify-send -a archenemy -u critical "archenemy" \
    "dalej w następnej linii"
EOF
hits=$(untagged_notify "$T/guard")
if [[ "$hits" == "$T/guard/bad.sh:1"$'\n'"$T/guard/bad.sh:2"$'\n'"$T/guard/bad.sh:3"$'\n'"$T/guard/bad.sh:4" ]]
then ok "kontrola negatywna: 4 wywołania bez -a archenemy złapane, poprawne i komentarze przepuszczone"
else fail "kontrola negatywna strażnika: [$(tr '\n' ' ' <<< "${hits//$T\//}")]"; fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
(( FAIL == 0 ))
