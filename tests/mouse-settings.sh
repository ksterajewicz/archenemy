#!/bin/bash
# =============================================
#   archenemy - tests/mouse-settings.sh
#   Testy ustawień myszy (Super+A → [m], scripts/hypr/mouse-settings.sh)
#   na atrapie HOME i atrapie hyprctl. Bez Hyprlanda, bez roota, bez zapisu
#   poza mktemp.
#
#   Sprawdza: walidację wartości (zakres -1 … 1, przecinek, śmieci), zapis
#   .dat i mouse.lua, reset, odczyt `show`, reload + potwierdzenie odczytem
#   (`hyprctl getoption`), rozjazd odczytu = kod 2, brak Hyprlanda = zapis
#   bez reloadu; wygenerowany Lua wykonany w lua5.4 z atrapą `hl.config`
#   ustawia WYŁĄCZNIE input.sensitivity; każdy realny rice (bez bety)
#   wczytuje mouse.lua przez require_optional PO bloku input.
#   Plus szybkość z docelowego DPI, DPI i polling na atrapie ratbagctl, menu.
#   Uruchom: bash tests/mouse-settings.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MS="$REPO/scripts/hypr/mouse-settings.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { if [[ "$2" == 1 ]]; then PASS=$((PASS+1)); echo "OK   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 ${3:-}"; fi; }

export HOME="$T/home"
mkdir -p "$HOME/archenemy" "$T/bin" "$T/rb"
DAT="$HOME/archenemy/data/mouse-sensitivity.dat"
LUA="$HOME/archenemy/config/hypr/mouse.lua"

# Atrapa hyprctl: `reload` zapisuje do logu i „wczytuje” mouse.lua, a `getoption`
# oddaje wartość w formacie dispatchGetOption: „float: X”, „str: X”, „bool: X”.
# MOCK_ZLY=1 = Hyprland ignoruje plik. MOCK_V056=1 = logiczne jako „int: 1” (v0.56.2).
cat > "$T/bin/hyprctl" <<'EOF'
#!/bin/bash
l="$HOME/archenemy/config/hypr/mouse.lua"
val() { [[ -f "$MOCK_STAN" ]] && sed -n "s/.*[ {]$1 = \"\{0,1\}\([^ \",}]*\).*/\1/p" "$MOCK_STAN"; }
case "$1" in
    reload) echo reload >> "$MOCK_LOG"
            rm -f "$MOCK_STAN"
            [[ -z "${MOCK_ZLY:-}" && -f "$l" ]] && cp "$l" "$MOCK_STAN" ;;
    getoption)
        case "$2" in
            input:sensitivity) printf 'float: %f\nset: true\n' "$(v="$(val sensitivity)"; echo "${v:-0}")" ;;
            input:scroll_factor) printf 'float: %f\nset: true\n' "$(v="$(val scroll_factor)"; echo "${v:-1}")" ;;
            input:accel_profile) v="$(val accel_profile)"; printf 'str: %s\nset: true\n' "${v:-flat}" ;;
            input:natural_scroll|input:left_handed)
                v="$(val "${2#input:}")"; v="${v:-false}"
                if [[ -n "${MOCK_V056:-}" ]]; then [[ "$v" == true ]] && v=1 || v=0; printf 'int: %s\nset: true\n' "$v"
                else printf 'bool: %s\nset: true\n' "$v"; fi ;;
            *) echo "no such option" ;;
        esac ;;
esac
EOF
# Atrapa ratbagctl w formacie func_dpi_get / func_report_rate_get z libratbag 0.18.
# MOCK_RATBAG=none = brak myszy, =dead = bez ratbagd: kod 0 i pusto, =stuck = mysz
# ignoruje zapis. Stan w plikach MOCK_RB.dpi i MOCK_RB.rate.
cat > "$T/rb/ratbagctl" <<'EOF'
#!/bin/bash
case "${MOCK_RATBAG:-}" in dead) exit 0 ;; none) echo "No devices available."; exit 0 ;; esac
if [[ "$1" == list ]]; then
    printf '%-20s %-32s\n' "hollering-marmot:" "Logitech G Pro"
    [[ -n "${MOCK_RB_TWO:-}" ]] && printf '%-20s %-32s\n' "sleeping-puppy:" "Razer Viper"
    exit 0
fi
[[ "$1" == hollering-marmot || "$1" == sleeping-puppy ]] || exit 1
echo "$1" >> "$MOCK_RB.dev"
case "$2 $3" in
    "dpi get") echo "$(cat "$MOCK_RB.dpi")dpi" ;;
    "dpi get-all") echo "400 800 1600 3200" ;;
    "dpi set") [[ "${MOCK_RATBAG:-}" == stuck ]] || echo "$4" > "$MOCK_RB.dpi" ;;
    "rate get") cat "$MOCK_RB.rate" ;;
    "rate get-all") echo "125 500 1000" ;;
    "rate set") echo "$4" > "$MOCK_RB.rate" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$T/rb/ratbagctl"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/sleep"
chmod +x "$T/bin/hyprctl"
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log" MOCK_STAN="$T/stan" MOCK_RB="$T/rbstate"

# --- bez Hyprlanda: zapis bez reloadu ----------------------------------------
unset HYPRLAND_INSTANCE_SIGNATURE
out="$(bash "$MS" 0.3)"; rc=$?
ok "bez Hyprlanda: kod 0" "$([[ $rc == 0 ]] && echo 1)"
ok "bez Hyprlanda: .dat = 0.3" "$([[ "$(cat "$DAT")" == 0.3 ]] && echo 1)"
ok "bez Hyprlanda: brak reloadu" "$([[ ! -f "$T/log" ]] && echo 1)"
ok "show = 0.3" "$([[ "$(bash "$MS" show)" == 0.3 ]] && echo 1)"

# --- walidacja ---------------------------------------------------------------
for zle in 1.5 -2 abc "" "0.3.1" "--1" "1e3"; do
    bash "$MS" "$zle" >/dev/null 2>&1; rc=$?
    ok "zła wartość '$zle' → kod 1, .dat bez zmian" "$([[ $rc == 1 && "$(cat "$DAT")" == 0.3 ]] && echo 1)"
done
for para in "0,25:0.25" "-.5:-0.5" "+1:1" "-1:-1" "1.000:1" "-0:0" "0.333:0.33"; do
    bash "$MS" "${para%%:*}" >/dev/null 2>&1
    ok "wartość '${para%%:*}' zapisana jako '${para#*:}'" "$([[ "$(cat "$DAT")" == "${para#*:}" ]] && echo 1)" "($(cat "$DAT"))"
done

# --- z Hyprlandem: reload + potwierdzenie odczytem ---------------------------
export HYPRLAND_INSTANCE_SIGNATURE=atrapa
rm -f "$T/log"
out="$(bash "$MS" -0.4)"; rc=$?
ok "Hyprland: kod 0 i komunikat ✓" "$([[ $rc == 0 && "$out" == *"✓ mouse sensitivity: -0.4"* ]] && echo 1)" "$out"
ok "Hyprland: jeden reload" "$([[ "$(grep -c reload "$T/log")" == 1 ]] && echo 1)"
ok "mouse.lua: dokładnie input.sensitivity = -0.4" "$(grep -qx 'hl.config({ input = { sensitivity = -0.4 } })' "$LUA" && echo 1)"
out="$(MOCK_ZLY=1 bash "$MS" 0.7 2>&1)"; rc=$?
ok "rozjazd odczytu → kod 2 z ostrzeżeniem" "$([[ $rc == 2 && "$out" == *"configerrors"* ]] && echo 1)" "$rc $out"
out="$(bash "$MS" reset)"; rc=$?
ok "reset → 0, kod 0" "$([[ $rc == 0 && "$(cat "$DAT")" == 0 ]] && echo 1)"
ls "$HOME/archenemy/config/hypr/"*.?????? >/dev/null 2>&1
ok "brak plików tymczasowych mktemp" "$([[ $? != 0 ]] && echo 1)"

# --- pozostałe opcje Hyprlanda -----------------------------------------------
export HYPRLAND_INSTANCE_SIGNATURE=atrapa
SET="$HOME/archenemy/data/mouse-settings.dat"
bash "$MS" reset >/dev/null; rm -f "$SET"
out="$(bash "$MS" accel adaptive)"; rc=$?
ok "accel: odczyt potwierdza" "$([[ $rc == 0 && "$out" == *"acceleration: adaptive"* ]] && echo 1)" "$out"
ok "accel: w Lua" "$(grep -q 'accel_profile = "adaptive"' "$LUA" && echo 1)"
out="$(bash "$MS" accel custom 2>&1)"; rc=$?
ok "accel: zła wartość" "$([[ $rc == 1 && "$(grep -c accel_profile "$LUA")" == 1 ]] && echo 1)"
out="$(bash "$MS" scroll 1,5)"; rc=$?
ok "scroll: przecinek i odczyt" "$([[ $rc == 0 && "$(grep -m1 SCROLL "$SET")" == "SCROLL=1.5" ]] && echo 1)" "$out"
for zla in 0 11 abc ""; do
    bash "$MS" scroll "$zla" >/dev/null 2>&1; rc=$?
    ok "scroll: '$zla' odrzucone" "$([[ $rc == 1 ]] && echo 1)"
done
out="$(bash "$MS" natural on)"; rc=$?
ok "natural on: bool w 0.57" "$([[ $rc == 0 ]] && echo 1)" "$out"
out="$(MOCK_V056=1 bash "$MS" left on)"; rc=$?
ok "left on: int w 0.56" "$([[ $rc == 0 ]] && echo 1)" "$out"
ok "Lua: true, nie on" "$(grep -q 'natural_scroll = true, left_handed = true' "$LUA" && echo 1)"
out="$(MOCK_V056=1 bash "$MS" left off)"; rc=$?
ok "left off: int w 0.56" "$([[ $rc == 0 ]] && grep -q 'left_handed = false' "$LUA" && echo 1)" "$out"
out="$(MOCK_ZLY=1 bash "$MS" natural on 2>&1)"; rc=$?
ok "natural: odczyt inny niż zapis = kod 2" "$([[ $rc == 2 && "$out" == *"reports 'false'"* ]] && echo 1)" "$out"
bash "$MS" natural maybe >/dev/null 2>&1; rc=$?
ok "natural: zła wartość" "$([[ $rc == 1 ]] && echo 1)"
bash "$MS" scroll reset >/dev/null; bash "$MS" accel reset >/dev/null; bash "$MS" natural reset >/dev/null; bash "$MS" left reset >/dev/null
ok "reset usuwa klucze: zostaje sama szybkość" "$(grep -qx 'hl.config({ input = { sensitivity = 0 } })' "$LUA" && echo 1)"
ok "reset nie gubi BASE_DPI" "$(bash "$MS" base 1600 >/dev/null; bash "$MS" scroll 2 >/dev/null; bash "$MS" scroll reset >/dev/null; grep -q 'BASE_DPI=1600' "$SET" && echo 1)"

# --- DPI programowe ----------------------------------------------------------
rm -f "$SET"
out="$(bash "$MS" soft-dpi 800 2>&1)"; rc=$?
ok "soft-dpi bez DPI myszy" "$([[ $rc == 1 && "$out" == *"base"* ]] && echo 1)" "$out"
bash "$MS" base 50 >/dev/null 2>&1; rc=$?
ok "base: za mało" "$([[ $rc == 1 ]] && echo 1)"
bash "$MS" base 1600 >/dev/null
bash "$MS" soft-dpi 800 >/dev/null
ok "800 z 1600 DPI = połowa" "$([[ "$(bash "$MS" show)" == "-0.5" ]] && echo 1)" "$(bash "$MS" show)"
ok "skrót pokazuje DPI" "$([[ "$(bash "$MS" summary)" == "-0.5, about 800 DPI" ]] && echo 1)" "$(bash "$MS" summary)"
bash "$MS" soft-dpi 3200 >/dev/null
ok "dwukrotność = 1" "$([[ "$(bash "$MS" show)" == "1" ]] && echo 1)"
out="$(bash "$MS" soft-dpi 3300 2>&1)"; rc=$?
ok "ponad zasięg odrzucone" "$([[ $rc == 1 && "$out" == *"up to 3200"* && "$(bash "$MS" show)" == "1" ]] && echo 1)" "$out"
bash "$MS" accel adaptive >/dev/null
ok "adaptive: bez liczby DPI" "$([[ "$(bash "$MS" summary)" == "1" ]] && echo 1)" "$(bash "$MS" summary)"
ok "brief: stan" "$([[ "$(bash "$MS" brief)" == *"Accel  adaptive"* ]] && echo 1)"
bash "$MS" accel reset >/dev/null; bash "$MS" reset >/dev/null

# --- DPI sprzętowe -----------------------------------------------------------
echo 1600 > "$MOCK_RB.dpi"; echo 1000 > "$MOCK_RB.rate"
rb() { PATH="$T/rb:$PATH" bash "$MS" "$@" 2>&1; }
D=hollering-marmot
ok "dpi-get bez sufiksu dpi" "$([[ "$(rb dpi-get $D)" == 1600 ]] && echo 1)" "$(rb dpi-get $D)"
out="$(rb dpi-set $D 800)"; rc=$?
ok "dpi-set: odczyt z myszy" "$([[ $rc == 0 && "$out" == "✓ DPI: 800 DPI" && "$(cat "$MOCK_RB.dpi")" == 800 ]] && echo 1)" "$out"
out="$(rb dpi-set $D 900)"; rc=$?
ok "dpi-set: wartość spoza listy" "$([[ $rc == 1 && "$out" == *"nearest is 800"* && "$(cat "$MOCK_RB.dpi")" == 800 ]] && echo 1)" "$out"
out="$(rb dpi-set $D abc)"; rc=$?
ok "dpi-set: nie liczba" "$([[ $rc == 1 ]] && echo 1)"
out="$(MOCK_RATBAG=stuck rb dpi-set $D 1600)"; rc=$?
ok "dpi-set: mysz ignoruje = kod 2" "$([[ $rc == 2 && "$out" == *"reports '800'"* ]] && echo 1)" "$out"
out="$(rb rate-set $D 500)"; rc=$?
ok "rate-set: odczyt" "$([[ $rc == 0 && "$(cat "$MOCK_RB.rate")" == 500 ]] && echo 1)" "$out"
out="$(rb rate-set $D 250)"; rc=$?
ok "rate-set: spoza listy" "$([[ $rc == 1 && "$out" == *"nearest is 125"* ]] && echo 1)" "$out"

# --- menu --------------------------------------------------------------------
printf '#!/bin/bash\nexit 0\n' > "$T/bin/clear"
menu() { printf "$1" | bash "$MS" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
mkdir -p "$HOME/archenemy/scripts"
out="$(menu '\n')"
ok "bez libratbag: podpowiedź" "$([[ "$out" == *"pacman -S libratbag"* && "$out" == *"Speed"*"Scroll speed"* ]] && echo 1)" "$out"
ok "bez libratbag: bez wiersza polling" "$([[ "$out" != *"Polling rate"* ]] && echo 1)"
menu '1\n0.25\n\n\n' >/dev/null
ok "menu: szybkość" "$([[ "$(bash "$MS" show)" == 0.25 ]] && echo 1)"
menu '1\n\n\n' >/dev/null
ok "menu: Enter anuluje" "$([[ "$(bash "$MS" show)" == 0.25 ]] && echo 1)"
menu '2\n1000\n1500\n\n\n' >/dev/null
ok "menu: DPI programowe" "$([[ "$(bash "$MS" show)" == 0.5 ]] && echo 1)" "$(bash "$MS" show)"
out="$(menu '4\n2\n\n\n')"
ok "menu: przyspieszenie" "$(grep -q 'ACCEL=adaptive' "$SET" && echo 1)" "$out"
menu '4\n3\n\n\n' >/dev/null
menu '6\n\n\n' >/dev/null
ok "menu: przełącznik on" "$(grep -q 'NATURAL=on' "$SET" && echo 1)"
menu '6\n\n\n' >/dev/null
ok "menu: przełącznik off" "$(grep -q 'NATURAL=off' "$SET" && echo 1)"
out="$(menu '9\n\n\n')"
ok "menu: zły numer" "$([[ "$out" == *"no number on this list"* ]] && echo 1)"

PATH="$T/rb:$PATH"
out="$(menu '\n')"
ok "z libratbag: DPI z myszy" "$([[ "$out" == *"1600 DPI, stored in Logitech G Pro"* || "$out" == *"800 DPI, stored in Logitech G Pro"* ]] && echo 1)" "$out"
ok "z libratbag: polling" "$([[ "$out" == *"Polling rate"*"Hz"* ]] && echo 1)"
menu '2\n3200\n\n\n' >/dev/null
ok "menu: DPI sprzętowe" "$([[ "$(cat "$MOCK_RB.dpi")" == 3200 ]] && echo 1)"
menu '3\n125\n\n\n' >/dev/null
ok "menu: polling" "$([[ "$(cat "$MOCK_RB.rate")" == 125 ]] && echo 1)"
out="$(menu '2\n\n\n')"
ok "menu: lista DPI" "$([[ "$out" == *"supports: 400 800 1600 3200"* ]] && echo 1)" "$out"
: > "$MOCK_RB.dev"
out="$(MOCK_RB_TWO=1 menu '2\n2\n400\n\n\n')"
ok "dwie myszy: wybór" "$(grep -q sleeping-puppy "$MOCK_RB.dev" && [[ "$out" == *"Razer Viper"* ]] && echo 1)" "$out"
out="$(MOCK_RATBAG=none menu '\n')"
ok "brak myszy w libratbag" "$([[ "$out" == *"no supported mouse"* && "$out" != *"Polling rate"* ]] && echo 1)" "$out"
out="$(MOCK_RATBAG=dead menu '2\n\n\n')"
ok "ratbagd nie działa: emulacja" "$([[ "$out" == *"emulated"* ]] && echo 1)" "$out"

# --- nawigacja strzałkami -----------------------------------------------------
menu '\e[B\e[B\e[B\e[B\n\e[A\e[A\n\n\n' >/dev/null
ok "strzałki: przyspieszenie adaptive" "$(grep -q 'ACCEL=adaptive' "$SET" && echo 1)"
before="$(bash "$MS" show)"
menu '\e\n' >/dev/null
ok "Esc nie zmienia szybkości" "$([[ "$(bash "$MS" show)" == "$before" ]] && echo 1)"
: > "$MOCK_RB.dev"
MOCK_RB_TWO=1 menu 'j\n2\n800\n\n\n' >/dev/null
ok "j wybiera drugą mysz" "$(grep -q sleeping-puppy "$MOCK_RB.dev" && echo 1)"

# --- wygenerowany Lua w lua5.4: ustawia tylko input.sensitivity -------------
if command -v lua5.4 >/dev/null 2>&1; then
    rm -f "$HOME/archenemy/data/mouse-settings.dat"
    bash "$MS" 0.55 >/dev/null
    # Harness w osobnym pliku: przy `lua5.4 -e … plik` plik byłby skryptem, nie arg[1].
    cat > "$T/harness.lua" <<'EOF'
        local klucze = {}
        hl = { config = function(t)
            local function walk(p, x) for k, v in pairs(x) do
                if type(v) == "table" then walk(p .. k .. ".", v) else klucze[#klucze + 1] = p .. k .. "=" .. tostring(v) end end end
            walk("", t) end }
        dofile(arg[1]); print(table.concat(klucze, ","))
EOF
    wynik="$(lua5.4 "$T/harness.lua" "$LUA" 2>&1)"
    ok "Lua: jedyny klucz input.sensitivity=0.55" "$([[ "$wynik" == "input.sensitivity=0.55" ]] && echo 1)" "$wynik"
else
    ok "lua5.4 dostępne (pominięto test wykonania)" 1
fi

# --- rice'y: require_optional mouse.lua po bloku input, beta bez ------------
for r in white-blue tron asia-n-rice dither-flux crt; do
    f="$REPO/rices/$r/hypr/hyprland.lua"
    n_in="$(grep -n 'accel_profile = "flat"' "$f" | head -1 | cut -d: -f1)"
    n_req="$(grep -n 'require_optional(HOME .. "/archenemy/config/hypr/mouse.lua")' "$f" | cut -d: -f1)"
    ok "$r: mouse.lua wczytywany raz, po bloku input" "$([[ -n "$n_req" && "$n_req" != *$'\n'* && "$n_req" -gt "$n_in" ]] && echo 1)" "in=$n_in req=$n_req"
done
ok "white-blue_beta: bez mouse.lua (legacy)" "$(grep -q 'mouse.lua' "$REPO/rices/white-blue_beta/hypr/hyprland.lua" || echo 1)"
ok "mouse.lua w .gitignore" "$(grep -qx '/config/hypr/mouse.lua' "$REPO/.gitignore" && echo 1)"

echo ""
echo "WYNIK mouse-settings: $PASS ok, $FAIL fail"
[[ $FAIL == 0 ]]
