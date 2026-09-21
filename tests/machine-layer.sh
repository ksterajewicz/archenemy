#!/bin/bash
# =============================================
#   archenemy - tests/machine-layer.sh
#   Testy regresji warstwy maszynowej na ATRAPIE hyprctl (tests/mock/hyprctl
#   odtwarza prawdziwy zrzut z 2026-09-21: monitory eDP-1 i HDMI-A-3, których
#   nazwy złączy zmieniły się po restarcie względem eDP-2 / HDMI-A-1 z dnia
#   instalacji). Bez Hyprlanda, bez roota, bez zapisu poza mktemp.
#
#   Zasada integralności: każdy generator warstwy maszynowej i każdy skrypt,
#   który czyta data/monitors/*.dat, ma tu test na trzy przypadki:
#     A. opis EDID dostępny        → selektor desc:, przeżywa zmianę nazwy,
#     B. brak opisu (stare .dat)   → nazwa złącza, dokładnie dawne zachowanie,
#     C. opisy nierozróżnialne     → nazwy złączy (install.sh [3]).
#   Uruchom: bash tests/machine-layer.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC1091,SC1007,SC2034  # check() robi eval na cytowanym wyrażeniu; źródła przez $REPO; puste kolory dla wycinka install.sh
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export PATH="$REPO/tests/mock:$PATH"
export MOCK_LOG="$T/dispatch.log"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── środowisko: $HOME/archenemy = linki do repo + własna warstwa maszynowa ───
H="$T/home"; A="$H/archenemy"
mkdir -p "$A/config/hypr" "$A/data/monitors" "$A/scripts/hypr"
ln -s "$REPO/scripts/hypr/lib" "$A/scripts/hypr/lib"
for s in workspace-orphan-guard.sh machine-layer-check.sh workspace-mode-switch.sh; do
    ln -s "$REPO/scripts/hypr/$s" "$A/scripts/hypr/$s"
done
export HOME="$H"

DESC_EDP="Thermotrex Corporation TL160ADMP03-0"
DESC_HDMI="Microstep MSI G241 0x00000603"
printf 'MONITOR=eDP-2\nRESOLUTION=2560x1600\nRATE=240\nPOSITION=0x0\nSCALE=1.3333334\nROLE=secondary\nDESCRIPTION=%s\nORDER=1\n' "$DESC_EDP"  > "$A/data/monitors/eDP-2.dat"
printf 'MONITOR=HDMI-A-1\nRESOLUTION=1920x1080\nRATE=144\nPOSITION=1925x123\nSCALE=1\nROLE=primary\nDESCRIPTION=%s\nORDER=2\n' "$DESC_HDMI" > "$A/data/monitors/HDMI-A-1.dat"
echo decades > "$A/data/workspace-mode.dat"

# shellcheck source=../scripts/hypr/lib/monitor-id.sh
source "$REPO/scripts/hypr/lib/monitor-id.sh"
# shellcheck source=../scripts/hypr/lib/gen-workspaces.sh
source "$REPO/scripts/hypr/lib/gen-workspaces.sh"

echo "== lib/monitor-id.sh"
check "A: selektor z .dat = desc:"            '[[ "$(monitor_selector_from_dat "$A/data/monitors/eDP-2.dat")" == "desc:$DESC_EDP" ]]'
printf 'MONITOR=DP-9\nORDER=3\n' > "$T/old.dat"
check "B: stary .dat bez opisu = nazwa"       '[[ "$(monitor_selector_from_dat "$T/old.dat")" == "DP-9" ]]'
printf 'MONITOR=DP-8\nDESCRIPTION=Foo "Bar"\n' > "$T/bad.dat"
check "opis z cudzysłowem = nazwa (bezpiecznik)" '[[ "$(monitor_selector_from_dat "$T/bad.dat")" == "DP-8" ]]'
check "desc: → żywa nazwa po zmianie złącza"  '[[ "$(MOCK_MONS=both monitor_live_name "desc:$DESC_HDMI")" == "HDMI-A-3" ]]'
check "desc: odpiętego monitora → pusto"      '[[ -z "$(MOCK_MONS=edp monitor_live_name "desc:$DESC_HDMI")" ]]'
check "stara nazwa → pusto (nie ma eDP-2)"    '[[ -z "$(MOCK_MONS=both monitor_live_name eDP-2)" ]]'
check "lua_string cytuje \\ i \""             '[[ "$(lua_string "a\"b\\c")" == "\"a\\\"b\\\\c\"" ]]'
check "monitor_desc_usable odrzuca pusty/#/=" '! monitor_desc_usable "" && ! monitor_desc_usable "a#b" && ! monitor_desc_usable "a=b" && monitor_desc_usable "$DESC_EDP"'

echo "== gen-workspaces.sh"
generate_workspaces_monitors "$T/dec.lua" decades "eDP-2"$'\t'"desc:$DESC_EDP" "HDMI-A-1"$'\t'"desc:$DESC_HDMI" "DP-9"
check "A: decades — panel 1-10 po desc:"     'grep -q "workspace = \"1\", monitor = \"desc:$DESC_EDP\", default = true" "$T/dec.lua"'
check "A: decades — zewnętrzny 11-20 po desc:" 'grep -q "workspace = \"11\", monitor = \"desc:$DESC_HDMI\", default = true, default_name = \"1\"" "$T/dec.lua"'
check "B: wpis bez TAB-a = nazwa (DP-9 → 21)" 'grep -q "workspace = \"21\", monitor = \"DP-9\"" "$T/dec.lua"'
check "inwariant: 1 reguła = 1 linia (guard)" '[[ $(grep -c "^hl\.workspace_rule({ workspace = \"[0-9]*\", monitor = \"" "$T/dec.lua") -eq 30 ]]'
generate_workspaces_monitors "$T/sh.lua" shared "eDP-2"$'\t'"desc:$DESC_EDP" "HDMI-A-1"$'\t'"desc:$DESC_HDMI"
check "A: shared — 2 domowe reguły po desc:" '[[ $(grep -c "monitor = \"desc:" "$T/sh.lua") -eq 2 ]]'
if command -v lua5.4 >/dev/null 2>&1; then
    check "Lua: plik wczytuje się z atrapą hl.*" 'lua5.4 -e "hl={workspace_rule=function(t) assert(type(t.workspace)==\"string\" and type(t.monitor)==\"string\") end, bind=function() end, dsp={focus=function() end, window={move=function() end}}}" -e "dofile(\"$T/dec.lua\")" </dev/null'
fi

echo "== workspace-orphan-guard.sh"
cp "$T/dec.lua" "$A/config/hypr/workspaces-monitors.lua"
: > "$MOCK_LOG"; MOCK_MONS=both bash "$A/scripts/hypr/workspace-orphan-guard.sh" --sweep </dev/null
check "oba podłączone (nowe nazwy) → nic nie przenosi" '[[ ! -s "$MOCK_LOG" ]]'
: > "$MOCK_LOG"; MOCK_MONS=edp bash "$A/scripts/hypr/workspace-orphan-guard.sh" --sweep </dev/null
check "HDMI odpięty → okno z 11 na 1"         'grep -q "movetoworkspacesilent 1,address:0xaaaa" "$MOCK_LOG"'

echo "== workspace-mode-switch.sh"
MOCK_MONS=both bash "$A/scripts/hypr/workspace-mode-switch.sh" shared >/dev/null 2>&1 </dev/null
check "przełącznik trybu emituje desc:"      'grep -q "monitor = \"desc:$DESC_HDMI\"" "$A/config/hypr/workspaces-monitors.lua" && [[ "$(<"$A/data/workspace-mode.dat")" == shared ]]'

echo "== machine-layer-check.sh"
for f in hardware-keys.lua gpu-env.lua autostartpersonalisation.lua appbinds.lua hyprpaper.conf; do : > "$A/config/hypr/$f"; done
{
    echo "hl.monitor({ output = \"desc:$DESC_EDP\", mode = \"2560x1600@240\", position = \"0x0\", scale = 1.3333334 })"
    echo "hl.monitor({ output = \"desc:$DESC_HDMI\", mode = \"1920x1080@144\", position = \"1925x123\", scale = 1 })"
    echo "hl.monitor({ output = \"\", mode = \"preferred\", position = \"auto\", scale = 1 })"
} > "$A/config/hypr/monitorshyprl.lua"
check "A: reguły desc: + nowe nazwy → OK"     'MOCK_MONS=both bash "$A/scripts/hypr/machine-layer-check.sh" >/dev/null 2>&1 </dev/null'
check "HDMI odpięty → nadal OK (nie alarmuj)" 'MOCK_MONS=edp bash "$A/scripts/hypr/machine-layer-check.sh" >/dev/null 2>&1 </dev/null'
{
    echo "hl.monitor({ output = \"eDP-2\", mode = \"2560x1600@240\", position = \"0x0\", scale = 1.3333334 })"
    echo "hl.monitor({ output = \"HDMI-A-1\", mode = \"1920x1080@144\", position = \"1925x123\", scale = 1 })"
    echo "hl.monitor({ output = \"\", mode = \"preferred\", position = \"auto\", scale = 1 })"
} > "$A/config/hypr/monitorshyprl.lua"
check "stare nazwy (zrzut 2026-09-21) → ALARM" '! MOCK_MONS=both bash "$A/scripts/hypr/machine-layer-check.sh" >/dev/null 2>&1 </dev/null'
rm -f "$A/config/hypr/appbinds.lua"
check "brak pliku generowanego → ALARM"      '! MOCK_MONS=both bash "$A/scripts/hypr/machine-layer-check.sh" 2>&1 </dev/null | grep -q "brak config/hypr/appbinds.lua"'

echo "== install.sh [3] (wycinek: detekcja + opis + unikalność)"
S=$(grep -n '^# ─── 3. CHECK MONITORS' "$REPO/install/install.sh" | cut -d: -f1)
E=$(grep -n '^# ─── 3.5 MONITOR LAYOUT' "$REPO/install/install.sh" | cut -d: -f1)
sed -n "${S},$((E-1))p" "$REPO/install/install.sh" > "$T/step3.sh"
out=$(MOCK_MONS=both ARCHENEMY_DIR="$REPO" DATA_DIR="$T/inst" GREEN= NC= YELLOW= BLUE= CYAN= RED= bash -c "source '$T/step3.sh'; echo \"\${CUR_DESC[eDP-1]}|\${CUR_DESC[HDMI-A-3]}\"" 2>/dev/null | tail -n1)
check "A: [3] składa opis z make/model/serial" '[[ "$out" == "$DESC_EDP|$DESC_HDMI" ]]'
out=$(MOCK_MONS=twins ARCHENEMY_DIR="$REPO" DATA_DIR="$T/inst2" GREEN= NC= YELLOW= BLUE= CYAN= RED= bash -c "source '$T/step3.sh'; echo \"[\${CUR_DESC[DP-1]}|\${CUR_DESC[DP-2]}]\"" 2>/dev/null | tail -n1)
check "C: dwa identyczne monitory → bez desc:" '[[ "$out" == "[|]" ]]'

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
