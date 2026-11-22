#!/usr/bin/env bash
# =============================================
#   archenemy - tests/rofi-power-menu.sh
#   Menu zasilania Super+prawy Shift (scripts/rofi/rofi_power_menu.sh) na
#   atrapach rofi, pidof i systemctl. Atrapa systemctl tylko zapisuje
#   wywołanie: test NICZEGO nie wyłącza ani nie restartuje, a bez atrapy
#   na początku PATH odmawia uruchomienia skryptu.
#
#   Powód powstania (audyt 2026-11-05, KT7): skrypt, który wyłącza komputer,
#   nie miał testu. Sprawdzane: pod hyprlockiem od razu poweroff bez menu
#   (DECYZJE 2026-07-28), poza blokadą dwa kroki z potwierdzeniem „Yes”,
#   Esc albo „No” niczego nie robią, UI po angielsku (DECYZJE 2026-07-12).
#   Od 2026-11-22 oba kroki idą w jednym oknie rofi (tryb skryptowy); atrapa
#   rofi to tests/lib/mock_rofi.py — jej nagłówek opisuje modelowany kontrakt.
#   Uruchom: bash tests/rofi-power-menu.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
# shellcheck source=tests/lib/timing.sh
source "$REPO/tests/lib/timing.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1
test_timing_init "$T"
PM="$REPO/scripts/rofi/rofi_power_menu.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

mkdir -p "$T/bin"
# systemctl: tylko zapis wywołania.
printf '#!/usr/bin/env bash\necho "$*" >> "%s/systemctl.log"\n' "$T" > "$T/bin/systemctl"
# pidof: hyprlock „działa”, gdy istnieje plik $T/locked.
printf '#!/usr/bin/env bash\n[[ "$1" == hyprlock && -f "%s/locked" ]]\n' "$T" > "$T/bin/pidof"
# rofi: atrapa trybu skryptowego (jeden proces = jedno okno), stan w $MOCK_ROFI.
cp "$REPO/tests/lib/mock_rofi.py" "$T/bin/rofi"
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" ARCHENEMY_DIR="$T/no-repo" MOCK_ROFI="$T"
[[ "$(command -v systemctl)" == "$T/bin/systemctl" ]] || { echo "  ✗ atrapa systemctl nie jest pierwsza w PATH — przerywam"; exit 1; }
[[ "$(command -v rofi)" == "$T/bin/rofi" ]] || { echo "  ✗ atrapa rofi nie jest pierwsza w PATH — przerywam"; exit 1; }

POWEROFF="󰐥  Power off"; REBOOT="󰜉  Reboot"
# run <odpowiedzi rofi, po jednej w linii> — wynik w RC. Akcja (systemctl)
# startuje w tle, więc bieg zbiera stderr przez $(…): podstawienie kończy się
# dopiero, gdy stderr zamkną WSZYSTKIE procesy potomne, także atrapa systemctl.
# Dzięki temu „bez systemctl” znaczy „nie uruchomiono”, a nie „jeszcze nie zdążył”.
run() {
    rm -f "$T/systemctl.log" "$T/rofi.log" "$T/rofi.info" "$T/rofi.calls"
    printf '%s' "$1" > "$T/answers"
    ERR="$(test_timeout 20 bash "${2:-$PM}" 2>&1 >/dev/null </dev/null)"; RC=$?
}
calls() { cat "$T/systemctl.log" 2>/dev/null; }
menus() { grep -c . "$T/rofi.log" 2>/dev/null || true; }
windows() { grep -c . "$T/rofi.calls" 2>/dev/null || true; }

echo "== pod hyprlockiem"
touch "$T/locked"
run ""
check "od razu systemctl poweroff, kod 0"           '[[ "$(calls)" == poweroff && $RC == 0 ]]'
check "bez menu rofi (brak klawiatury pod blokadą)" '[[ ! -e "$T/rofi.calls" ]]'
rm "$T/locked"

echo "== menu i potwierdzenie"
run "$POWEROFF"$'\n'"Yes"$'\n'
check "Power off + Yes → poweroff"                  '[[ "$(calls)" == poweroff ]]'
check "pierwsze menu: Power, dwie pozycje"          '[[ "$(head -n1 "$T/rofi.log")" == "Power => $POWEROFF|$REBOOT" ]]'
check "drugie menu: Are you sure?, Yes|No"          '[[ "$(sed -n 2p "$T/rofi.log")" == "Are you sure? => Yes|No" && "$(menus)" == 2 ]]'
check "motyw kompaktowy (2 linie, bez wyszukiwania)" 'grep -q "lines: 2" "$T/theme" && grep -q "children: \[ prompt \]" "$T/theme"'
run "$REBOOT"$'\n'"Yes"$'\n'
check "Reboot + Yes → reboot"                       '[[ "$(calls)" == reboot ]]'

echo "== nic się nie dzieje"
run "$POWEROFF"$'\n'"No"$'\n'
check "Power off + No → bez systemctl"              '[[ -z "$(calls)" && "$(menus)" == 2 ]]'
run $'\n'
check "Esc w pierwszym menu → bez potwierdzenia"    '[[ -z "$(calls)" && "$(menus)" == 1 ]]'
run "$REBOOT"$'\n\n'
check "Esc w potwierdzeniu → bez systemctl"         '[[ -z "$(calls)" ]]'
run "custom:Power off"$'\n'"Yes"$'\n'
check "wpisany tekst spoza listy + Yes → nic"       '[[ -z "$(calls)" ]]'
run "$POWEROFF"$'\n'"custom:yes"$'\n'
check "potwierdzenie tylko wierszem Yes z listy"    '[[ -z "$(calls)" && "$(windows)" == 1 ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
test_timing_ok && ((FAIL == 0))
