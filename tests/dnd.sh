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

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
(( FAIL == 0 ))
