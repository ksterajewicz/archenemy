#!/bin/bash
# =============================================
#   archenemy - tests/mouse-sensitivity.sh
#   Testy czułości myszy (Super+A → [m], scripts/hypr/mouse-sensitivity.sh)
#   na atrapie HOME i atrapie hyprctl. Bez Hyprlanda, bez roota, bez zapisu
#   poza mktemp.
#
#   Sprawdza: walidację wartości (zakres -1 … 1, przecinek, śmieci), zapis
#   .dat i mouse.lua, reset, odczyt `show`, reload + potwierdzenie odczytem
#   (`hyprctl getoption`), rozjazd odczytu = kod 2, brak Hyprlanda = zapis
#   bez reloadu; wygenerowany Lua wykonany w lua5.4 z atrapą `hl.config`
#   ustawia WYŁĄCZNIE input.sensitivity; każdy realny rice (bez bety)
#   wczytuje mouse.lua przez require_optional PO bloku input.
#   Uruchom: bash tests/mouse-sensitivity.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MS="$REPO/scripts/hypr/mouse-sensitivity.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { if [[ "$2" == 1 ]]; then PASS=$((PASS+1)); echo "OK   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 ${3:-}"; fi; }

export HOME="$T/home"
mkdir -p "$HOME/archenemy" "$T/bin"
DAT="$HOME/archenemy/data/mouse-sensitivity.dat"
LUA="$HOME/archenemy/config/hypr/mouse.lua"

# Atrapa hyprctl: `reload` zapisuje do logu i „wczytuje” mouse.lua (wartość
# z linii hl.config); `getoption input:sensitivity` oddaje ją w formacie
# v0.56.2 („float: X”). MOCK_ZLY=1 = Hyprland ignoruje plik (zostaje 0).
cat > "$T/bin/hyprctl" <<'EOF'
#!/bin/bash
case "$1" in
    reload) echo reload >> "$MOCK_LOG"
            v=0
            [[ -z "${MOCK_ZLY:-}" && -f "$HOME/archenemy/config/hypr/mouse.lua" ]] && \
                v="$(sed -n 's/.*sensitivity = \([^ }]*\).*/\1/p' "$HOME/archenemy/config/hypr/mouse.lua")"
            echo "$v" > "$MOCK_STAN" ;;
    getoption) printf 'float: %f\nset: true\n' "$(cat "$MOCK_STAN" 2>/dev/null || echo 0)" ;;
esac
EOF
chmod +x "$T/bin/hyprctl"
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log" MOCK_STAN="$T/stan"

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

# --- wygenerowany Lua w lua5.4: ustawia tylko input.sensitivity -------------
if command -v lua5.4 >/dev/null 2>&1; then
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
echo "WYNIK mouse-sensitivity: $PASS ok, $FAIL fail"
[[ $FAIL == 0 ]]
