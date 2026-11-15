#!/bin/bash
# =============================================
#   archenemy - tests/timer.sh
#   Timer waybara (scripts/waybar/timer.sh + lib/timer-state.sh): przejście
#   running → finished i jedno powiadomienie na atrapie notify-send.
#
#   Powód powstania (audyt 2026-11-05, A11): na dwóch monitorach waybar ma dwa
#   paski i każdy co sekundę odpala własny timer.sh. Oba czytały „running”,
#   a flaga `notified` trafiała do pliku dopiero po notify-send, więc
#   „Timer finished.” przychodziło dwa razy. Atrapa notify-send czeka 1 s jak
#   demon powiadomień, który odpowiada z opóźnieniem.
#   Uruchom: bash tests/timer.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
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

A="$HOME/archenemy"; D="$A/data"; ST="$D/timer-state.dat"
mkdir -p "$A/scripts/waybar/lib" "$D" "$T/bin"
cp "$REPO/scripts/waybar/timer.sh" "$A/scripts/waybar/"
cp "$REPO/scripts/waybar/lib/timer-state.sh" "$A/scripts/waybar/lib/"
cat > "$T/bin/notify-send" <<MOCK
#!/bin/bash
echo "\$*" >> "$T/notify.log"
sleep 1
MOCK
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
echo 1 > "$D/timer-enabled.dat"

# Odliczanie skończyło się 5 s temu, powiadomienia jeszcze nie było.
expired() { : > "$T/notify.log"; printf 'status=running\nremaining=0\nend=%s\nnotified=0\n' "$(( $(date +%s) - 5 ))" > "$ST"; }
render() { bash "$A/scripts/waybar/timer.sh"; }
notes() { grep -c . "$T/notify.log"; }

echo "== jeden pasek"
expired
out="$(render)"
check "powiadomienie: Timer finished."            '[[ "$(notes)" == 1 && "$(<"$T/notify.log")" == *"Timer finished."* ]]'
check "stan finished + notified=1"                 'grep -qx status=finished "$ST" && grep -qx notified=1 "$ST"'
check "render pokazuje finished"                   '[[ "$out" == *"\"class\":\"finished\""* ]]'
out="$(render)"
check "następny tik bez powiadomienia"             '[[ "$(notes)" == 1 && "$out" == *"\"class\":\"finished\""* ]]'

echo "== dwa paski naraz (dwa monitory)"
expired
render > "$T/out1" & p1=$!
render > "$T/out2" & p2=$!
wait "$p1" "$p2"
check "jedno powiadomienie, nie dwa"               '[[ "$(notes)" == 1 ]]'
check "oba paski pokazują finished"                'grep -q "\"class\":\"finished\"" "$T/out1" && grep -q "\"class\":\"finished\"" "$T/out2"'
check "stan finished + notified=1"                 'grep -qx status=finished "$ST" && grep -qx notified=1 "$ST"'
check "żadnych plików pomocniczych w data/"        '[[ "$(cd "$D" && echo *)" == "timer-enabled.dat timer-state.dat" ]]'

echo "== biegnący timer"
: > "$T/notify.log"; printf 'status=running\nremaining=0\nend=%s\nnotified=0\n' "$(( $(date +%s) + 120 ))" > "$ST"
out="$(render)"
check "przed zerem bez powiadomienia i zapisu"     '[[ "$(notes)" == 0 && "$out" == *"\"class\":\"running\""* ]] && grep -qx status=running "$ST"'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
((FAIL == 0))
