#!/bin/bash
# =============================================
#   archenemy - tests/audio-devices.sh
#   Wybór wyjścia i wejścia systemu (scripts/appbinds/audio-devices.sh) na
#   atrapie tests/mock/pactl. Bez PipeWire, zapis tylko w mktemp.
#   Uruchom: bash tests/audio-devices.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1
AD="$REPO/scripts/appbinds/audio-devices.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

mkdir -p "$T/bin"
cp "$REPO/tests/mock/pactl" "$T/bin/pactl"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/pkill"; printf '#!/bin/bash\nexit 0\n' > "$T/bin/sleep"
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" MOCK_PA="$T"
reset() { : > "$T/log"; echo alsa_output.pci.analog > "$T/default-sink"; echo alsa_input.pci.analog > "$T/default-source"; }
reset

echo "== lista"
sinks="$(bash "$AD" list sink)"
check "dwa wyjścia, nazwa<TAB>opis"            '[[ "$sinks" == $'"'"'alsa_output.pci.analog\tBuilt-in Audio Analog Stereo\nbluez_output.headset\tWH-1000XM4'"'"' ]]'
sources="$(bash "$AD" list source)"
check "monitor wyjścia to nie mikrofon"        '[[ "$sources" == $'"'"'alsa_input.pci.analog\tBuilt-in Audio Mic'"'"' ]]'
check "opis domyślnego wyjścia"                '[[ "$(bash "$AD" describe sink)" == "Built-in Audio Analog Stereo" ]]'

echo "== ustawianie"
out="$(bash "$AD" set sink bluez_output.headset)"; rc=$?
check "wyjście zmienione, kod 0"               '[[ $rc -eq 0 && "$(<"$T/default-sink")" == bluez_output.headset ]]'
check "grające strumienie przeniesione"        'grep -q "move-sink-input 101 bluez_output.headset" "$T/log" && grep -q "move-sink-input 102" "$T/log"'
check "raport liczy strumienie"                '[[ "$out" == *"2 playing streams moved"* ]]'
reset; bash "$AD" set source alsa_input.pci.analog >/dev/null
check "zmiana wejścia nie rusza strumieni"     '! grep -q "move-s" "$T/log"'

reset; out="$(MOCK_PA_STUCK=1 bash "$AD" set sink bluez_output.headset 2>&1)"; rc=$?
check "serwer ignoruje zmianę → kod 2, bez ✓"  '[[ $rc -eq 2 && "$out" != *"✓"* ]]'
check "strumienie nietknięte po porażce"       '! grep -q "move-sink-input" "$T/log"'
reset; out="$(bash "$AD" set sink nie-ma 2>&1)"; rc=$?
check "nieznane urządzenie → kod 1"            '[[ $rc -eq 1 && "$out" == *"no such device"* ]]'
check "złe argumenty → kod 1"                  '! bash "$AD" list foo 2>/dev/null'

touch "$T/down"
out="$(bash "$AD" list sink 2>&1)"; rc=$?
check "martwy serwer → komunikat, kod 1"       '[[ $rc -eq 1 && "$out" == *"not responding"* ]]'
rm "$T/down"

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
