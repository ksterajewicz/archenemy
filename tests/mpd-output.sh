#!/bin/bash
# =============================================
#   archenemy - tests/mpd-output.sh
#   Wyjście audio mpd z Super+A → [o] (scripts/appbinds/lib/mpd-output.sh) na
#   atrapie tests/mock/mpc. Bez mpd, bez roota, zapis tylko w mktemp.
#
#   Powód powstania (audyt TUI 2026-11-05, A1–A3): menu meldowało „✓” przy
#   ciszy, bo fifo wizualizera maskowało awarię wyjścia głównego, pusta kolejka
#   pomijała test, a zapis trafiał do pliku, którego mpd nie czytał.
#   Uruchom: bash tests/mpd-output.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

mkdir -p "$T/bin" "$T/mpd" "$T/home/archenemy/config/mpd" "$T/home/archenemy/data" "$T/home/.config"
cp "$REPO/tests/mock/mpc" "$T/bin/mpc"
printf '#!/bin/bash\nif [[ "$*" == *is-active* ]]; then exit "${MOCK_SYSTEM_MPD:-1}"; fi\nexit "${MOCK_RESTART:-0}"\n' > "$T/bin/systemctl"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/sleep"
chmod +x "$T/bin/"*
export HOME="$T/home" PATH="$T/bin:$PATH" MOCK_MPD="$T/mpd"
export MOCK_MPD_CONF="$HOME/archenemy/config/mpd/output.conf"
ln -s "$HOME/archenemy/config/mpd" "$HOME/.config/mpd"
ARCHENEMY_DIR="$HOME/archenemy"

write_dat() { printf '%s\n' "$2" > "$1"; }
# shellcheck source=../scripts/appbinds/lib/mpd-output.sh
source "$REPO/scripts/appbinds/lib/mpd-output.sh"

setup() { rm -f "$T/mpd/"*; echo "${1:-stopped}" > "$T/mpd/state"; echo 1 > "$T/mpd/fifo"; touch "$T/mpd/queue"; }

echo "== test odtwarzania"
setup; apply_mpd_output alsa hw:0,0 >"$T/out"; rc=$?
check "działające ALSA → kod 0"                '[[ $rc -eq 0 ]]'
check "output.conf ma urządzenie"              'grep -q "device      \"hw:0,0\"" "$MOCK_MPD_CONF"'
check "nazwa wyjścia w .dat i conf zgodna"     '[[ "$(<"$MPD_OUTPUT_DAT")" == "alsa hw:0,0" ]] && grep -q "name        \"ALSA hw:0,0\"" "$MOCK_MPD_CONF"'
check "fifo wraca po teście"                   '[[ "$(<"$T/mpd/fifo")" == 1 ]]'

setup; MOCK_MPD_BROKEN=1 apply_mpd_output alsa hw:0,0 >"$T/out"; rc=$?
check "awaria przy żywym fifo → wykryta (A1)"  '[[ $rc -eq 1 ]]'
check "powód porażki z mpd"                    'grep -q "Failed to open" "$T/out"'
check "fifo wraca także po porażce"            '[[ "$(<"$T/mpd/fifo")" == 1 ]]'
check "błąd mpd wyczyszczony"                  '[[ ! -s "$T/mpd/error" ]]'

echo "== pusta kolejka"
setup; rm "$T/mpd/queue"; apply_mpd_output alsa hw:0,0 >"$T/out"; rc=$?
check "bez utworów kod 3, nie sukces (A2)"     '[[ $rc -eq 3 ]]'
check "nic nie grało"                          '! grep -qx "mpc play" "$T/mpd/log"'

echo "== stan odtwarzania"
setup stopped; apply_mpd_output pipewire >/dev/null
check "stopped zostaje stopped"                '[[ "$(<"$T/mpd/state")" == stopped ]]'
setup paused; apply_mpd_output pipewire >/dev/null
check "paused zostaje paused"                  '[[ "$(<"$T/mpd/state")" == paused ]]'
setup playing; apply_mpd_output pipewire >/dev/null
check "playing gra dalej"                      '[[ "$(<"$T/mpd/state")" == playing ]]'

echo "== mpd nie słucha tego configu"
setup; MOCK_MPD_NAME=Other apply_mpd_output alsa hw:0,0 >"$T/out"; rc=$?
check "wyjścia nie ma na liście → porażka"     '[[ $rc -eq 1 ]] && grep -q "does not list" "$T/out"'
setup; MOCK_RESTART=1 apply_mpd_output pipewire >"$T/out"; rc=$?
check "restart nieudany → porażka"             '[[ $rc -eq 1 ]]'

check "podlinkowany config → brak blokady"     'mpd_output_blocker >/dev/null'
out="$(MOCK_SYSTEM_MPD=0 mpd_output_blocker)"; rc=$?
check "mpd systemowy → blokada"                '[[ $rc -eq 1 && "$out" == *"system service"* ]]'
rm "$HOME/.config/mpd"
out="$(mpd_output_blocker)"; rc=$?
check "brak linku → blokada (A3)"              '[[ $rc -eq 1 && "$out" == *"not linked"* ]]'
mkdir "$HOME/.config/mpd"
check "cudzy katalog → blokada"                '! mpd_output_blocker >/dev/null'
rmdir "$HOME/.config/mpd"; ln -s "$HOME/archenemy/config/mpd" "$HOME/.config/mpd"

echo "== stan w menu"
setup; apply_mpd_output pipewire >/dev/null
check "bieżące wyjście z mpd, bez fifo (A5)"   '[[ "$(mpd_current_output)" == PipeWire ]]'
touch "$T/mpd/down"; rm "$MOCK_MPD_CONF"
mpc() { return 1; }
check "mpd nie odpowiada → zapisany wybór"     '[[ "$(mpd_current_output)" == *"saved, mpd not responding"* ]]'
unset -f mpc

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
