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
# zrzut 2026-09-21 po naprawie reguł: 21 (HDMI, dekada 11-20) i 22 (eDP, 1-10) bez reguły
# (reguły tylko dla dwóch realnych monitorów — z DP-9 z fixture wyżej 21 byłby zwykłą sierotą)
generate_workspaces_monitors "$A/config/hypr/workspaces-monitors.lua" decades "eDP-2"$'\t'"desc:$DESC_EDP" "HDMI-A-1"$'\t'"desc:$DESC_HDMI"
: > "$MOCK_LOG"; MOCK_MONS=both MOCK_WS=stale bash "$A/scripts/hypr/workspace-orphan-guard.sh" --sweep </dev/null
check "21 bez reguły na HDMI → okna na 11"     'grep -q "movetoworkspacesilent 11,address:0xaaaa" "$MOCK_LOG" && grep -q "movetoworkspacesilent 11,address:0xcccc" "$MOCK_LOG"'
check "22 bez reguły na eDP → okno na 2, fokus za nim" 'grep -q "movetoworkspacesilent 2,address:0xbbbb" "$MOCK_LOG" && grep -q "dispatch workspace 2$" "$MOCK_LOG"'
check "nic nie leci do dekady cudzego monitora" '! grep -q "movetoworkspacesilent 1,address:0xaaaa" "$MOCK_LOG"'
# monitor bez własnej dekady (reguły tylko dla panelu) → jego 21 zostaje w spokoju
generate_workspaces_monitors "$A/config/hypr/workspaces-monitors.lua" decades "eDP-2"$'\t'"desc:$DESC_EDP"
: > "$MOCK_LOG"; MOCK_MONS=both MOCK_WS=stale bash "$A/scripts/hypr/workspace-orphan-guard.sh" --sweep </dev/null
check "monitor bez dekady → jego workspace nietknięty" '! grep -q "address:0xaaaa" "$MOCK_LOG" && grep -q "movetoworkspacesilent 2,address:0xbbbb" "$MOCK_LOG"'
cp "$T/dec.lua" "$A/config/hypr/workspaces-monitors.lua"

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

echo "== install.sh [3]–[3.7] (wycinek: przerwanie NIE kasuje starych .dat; komplet podmieniany po [3.7])"
# Audyt 2026-09-25: `rm -f data/monitors/*.dat` szło w [3], PRZED pytaniami
# [3.5]–[3.7] — Ctrl-C w trakcie zostawiał data/monitors/ pusty. Nowe .dat
# powstają w data/monitors.new.XXXXXX i wchodzą na miejsce po ostatnim pytaniu.
S=$(grep -n '^# ─── 3. CHECK MONITORS' "$REPO/install/install.sh" | cut -d: -f1)
E=$(grep -n '^# ─── 4. CHECK YAY' "$REPO/install/install.sh" | cut -d: -f1)
sed -n "${S},$((E-1))p" "$REPO/install/install.sh" > "$T/step3-37.sh"
I="$T/inst3"; mkdir -p "$I/monitors"
printf 'MONITOR=DP-OLD\nRESOLUTION=1x1\nROLE=primary\nORDER=1\n' > "$I/monitors/DP-OLD.dat"
# Odpowiedzi: [3.5] 5×Enter na monitor (2 monitory), [3.6] Enter — potem stdin
# WISI na pytaniu [3.7] i po 2 s przychodzi SIGINT (= Ctrl-C użytkownika).
exec 3< <(printf '\n\n\n\n\n\n\n\n\n\n\n'; sleep 30)
feeder=$!
MOCK_MONS=both ARCHENEMY_DIR="$REPO" DATA_DIR="$I" GREEN= NC= YELLOW= BLUE= CYAN= RED= \
    timeout -s INT 2 bash "$T/step3-37.sh" <&3 >/dev/null 2>&1
exec 3<&-; kill "$feeder" 2>/dev/null
check "przerwany bieg: stary .dat zostaje"     '[[ -f "$I/monitors/DP-OLD.dat" ]]'
check "przerwany bieg: nowe .dat NIE na miejscu" '[[ ! -e "$I/monitors/eDP-1.dat" && ! -e "$I/monitors/HDMI-A-3.dat" ]]'
check "przerwany bieg: katalog tymczasowy sprzątnięty (trap)" '! ls -d "$I"/monitors.new.* >/dev/null 2>&1'
# Pełny bieg: te same odpowiedzi + „1" (shared) w [3.7].
mkdir -p "$I/monitors.new.STALE"   # resztka po biegu zabitym bez trapa (SIGKILL)
out=$(printf '\n\n\n\n\n\n\n\n\n\n\n1\n' | MOCK_MONS=both ARCHENEMY_DIR="$REPO" DATA_DIR="$I" GREEN= NC= YELLOW= BLUE= CYAN= RED= bash "$T/step3-37.sh" 2>&1)
check "pełny bieg: nowe .dat na miejscu"       '[[ -f "$I/monitors/eDP-1.dat" && -f "$I/monitors/HDMI-A-3.dat" ]]'
check "pełny bieg: stary .dat (odpięty monitor) usunięty" '[[ ! -e "$I/monitors/DP-OLD.dat" ]]'
check "pełny bieg: .dat kompletny (opis, rola, ORDER)" 'grep -q "^DESCRIPTION=$DESC_HDMI$" "$I/monitors/HDMI-A-3.dat" && grep -q "^ROLE=" "$I/monitors/HDMI-A-3.dat" && grep -q "^ORDER=[12]$" "$I/monitors/eDP-1.dat" && grep -q "^ORDER=[12]$" "$I/monitors/HDMI-A-3.dat"'
check "pełny bieg: bez katalogów tymczasowych (także resztki)" '! ls -d "$I"/monitors.new.* >/dev/null 2>&1'
check "pełny bieg: workspace-mode.dat = shared" '[[ "$(<"$I/workspace-mode.dat")" == shared ]]'
check "pełny bieg: komunikat o zapisie po [3.7]" '[[ "$out" == *"data/monitors/*.dat zapisane (2 monitors)"* ]]'

echo "== wersja kodu a ostatni install.sh (data/installed-head.dat)"
# Audyt 2026-09-23: laptop działał na innej wersji niż repo i nic tego nie
# mówiło. Alarm tylko przy zmianach w katalogach przetwarzanych przez
# install.sh; brak pliku (instalacja sprzed zmiany) = cisza.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git -C "$A" init -q && git -C "$A" add -A && git -C "$A" commit -qm start
ver_msg() { MOCK_MONS=both bash "$A/scripts/hypr/machine-layer-check.sh" 2>&1 </dev/null | grep -c "od ostatniego install.sh\|wersji ostatniej instalacji"; }
check "brak installed-head.dat → cisza"        '[[ $(ver_msg) -eq 0 ]]'
printf 'COMMIT=%s\nDATE=x\n' "$(git -C "$A" rev-parse HEAD)" > "$A/data/installed-head.dat"
check "HEAD = zainstalowany → cisza"           '[[ $(ver_msg) -eq 0 ]]'
echo doc > "$A/README.md"; git -C "$A" add README.md; git -C "$A" commit -qm doc
check "zmiana tylko w dokumentacji → cisza"    '[[ $(ver_msg) -eq 0 ]]'
mkdir -p "$A/scripts/nowe"; echo x > "$A/scripts/nowe/x.sh"; git -C "$A" add scripts/nowe; git -C "$A" commit -qm kod
check "zmiana w scripts/ → ALARM"              '[[ $(ver_msg) -eq 1 ]]'
printf 'COMMIT=%s\n' 0123456789abcdef0123456789abcdef01234567 > "$A/data/installed-head.dat"
check "nieznany commit (przepisana historia) → ALARM" '[[ $(ver_msg) -eq 1 ]]'
rep=$(MOCK_MONS=both bash "$A/scripts/hypr/machine-layer-check.sh" 2>&1 </dev/null)   # całość, bez grep -q (SIGPIPE + pipefail)
check "raport podaje obie wersje"              '[[ "$rep" == *"installed from: 0123456 · repo HEAD:"* ]]'

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
