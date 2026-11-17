#!/usr/bin/env bash
# =============================================
#   archenemy - tests/rice-autostart.sh
#   Wykonuje hyprland.lua KAŻDEGO rice'a na atrapie API Hyprlanda (Lua 5.4,
#   `hl.*` jako rekurencyjna atrapa) i sprawdza, co odpala się na starcie
#   sesji (hl.on("hyprland.start")). Pliki warstwy maszynowej, których nie ma
#   w repo (generuje je install.sh), są pomijane jak brak pliku.
#   Bez Hyprlanda, bez roota, bez zapisu poza mktemp.
#
#   Powód powstania (audyt 2026-09-23): `flux-wall.sh autostart` stał tylko
#   w crt i dither-flux, więc animacja wybrana w Super+W (wybór globalny,
#   decyzja 2026-09-07j) nie wracała po zalogowaniu do pozostałych rice'ów.
#   Teraz żyje we wspólnym config/hypr/autostart-common.lua — ma odpalić się
#   DOKŁADNIE RAZ w każdym ricu (dwa razy = restart animacji przy starcie).
#   Reguły okien z `move` (A4, audyt 2026-11-05): Hyprland liczy je muParserem,
#   w którym `%` nie jest operatorem — błąd wyrażenia tylko centruje okno, bez
#   wpisu w configerrors. Test liczy pozycję okna na ekranie 1920x1080, jak
#   zrobiłby Hyprland: okno PiP ma stać w prawym dolnym rogu, 10 px od krawędzi.
#   Uruchom: bash tests/rice-autostart.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA="$(command -v lua5.4 || command -v lua || true)"
if [[ -z "$LUA" ]]; then echo "brak interpretera lua5.4 — pomijam"; exit 0; fi
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

# Atrapa: HOME/archenemy → repo; require(ścieżka) = dofile, brak pliku = nic.
cat > "$T/harness.lua" <<'EOF'
local repo, rice_file = arg[1], arg[2]
local function proxy()
    return setmetatable({}, {
        __index = function() return proxy() end,
        __call  = function() return proxy() end,
    })
end
local handlers, execs, binds = {}, {}, {}
hl = proxy()
rawset(hl, "on", function(ev, fn) if ev == "hyprland.start" then handlers[#handlers + 1] = fn end end)
rawset(hl, "exec_cmd", function(cmd) execs[#execs + 1] = cmd end)
-- Bindy z komendą: hl.bind(klawisz, hl.dsp.exec_cmd(cmd)) → "BIND klawisz => cmd"
local dsp = proxy()
rawset(dsp, "exec_cmd", function(cmd) return { exec = cmd } end)
rawset(hl, "dsp", dsp)
rawset(hl, "bind", function(key, action)
    if type(action) == "table" and rawget(action, "exec") then binds[#binds + 1] = key .. " => " .. action.exec end
end)
-- Reguły okien: rozmiar i pozycja (move) po dopasowaniu; pozycja jak w Hyprlandzie,
-- czyli wyrażenie muParsera na zmiennych monitora i okna. Zmienne: tylko te, które
-- reguły rice'ów dziś używają (nową dopisz po sprawdzeniu w źródłach Hyprlanda).
local sizes, moves = {}, {}
local function rule_key(r) local m = rawget(r, "match") or {}; return tostring(m.title or m.class) end
rawset(hl, "window_rule", function(r)
    if type(r) ~= "table" then return end
    if rawget(r, "size") then sizes[rule_key(r)] = r.size end
    if rawget(r, "move") then moves[#moves + 1] = { key = rule_key(r), move = r.move } end
end)
local function eval_expr(e, vars)
    if type(e) == "number" then return e end
    if type(e) ~= "string" or e:find("%", 1, true) or e:find("[^%w_ .+*/()-]") then return nil end
    for id in e:gmatch("[%a_][%w_]*") do if vars[id] == nil then return nil end end
    local f = load("return " .. e, "move", "t", vars)
    if not f then return nil end
    local ok, v = pcall(f)
    if ok and type(v) == "number" then return v end
    return nil
end
local home = os.getenv("HOME")
require = function(path)
    local p = path:gsub("^" .. home:gsub("%p", "%%%0") .. "/archenemy", repo)
    local f = io.open(p, "r")
    if not f then return end
    f:close()
    dofile(p)
end
dofile(rice_file)
for _, fn in ipairs(handlers) do fn() end
for _, c in ipairs(execs) do print(c) end
for _, b in ipairs(binds) do print("BIND " .. b) end
for _, m in ipairs(moves) do
    local sz = sizes[m.key] or { 0, 0 }
    local vars = { monitor_w = 1920, monitor_h = 1080, window_w = sz[1], window_h = sz[2] }
    local x, y = eval_expr(m.move[1], vars), eval_expr(m.move[2], vars)
    print(string.format("MOVE %s\t%s\t%s\t%s\t%s", m.key, x or "BAD", y or "BAD", sz[1], sz[2]))
end
EOF

for cfg in "$REPO"/rices/*/hypr/hyprland.lua; do
    rice="$(basename "$(dirname "$(dirname "$cfg")")")"
    if ! out="$(HOME="$T/home" "$LUA" "$T/harness.lua" "$REPO" "$cfg" 2>&1)"; then
        fail "$rice: config nie wykonał się na atrapie: ${out##*$'\n'}"
        continue
    fi
    n="$(grep -c 'flux-wall.sh autostart' <<< "$out")"
    if [[ "$n" -eq 1 ]]; then ok "$rice: flux-wall autostart dokładnie raz"
    else fail "$rice: flux-wall autostart $n razy (ma być 1)"; fi
    if grep -q 'workspace-orphan-guard.sh' <<< "$out"; then ok "$rice: wspólny workspaces.lua podpięty (guard)"
    else fail "$rice: brak guarda workspace'ów na starcie"; fi
    # Super+Tab (przywracanie zamkniętych aplikacji): demon ze wspólnego
    # autostartu dokładnie raz, bind w każdym ricu parytetu (beta zamrożona).
    n="$(grep -c '^[^B].*window-history.sh daemon' <<< "$out")"
    if [[ "$n" -eq 1 ]]; then ok "$rice: demon window-history dokładnie raz"
    else fail "$rice: demon window-history $n razy (ma być 1)"; fi
    # Pozycja z `move`: każde wyrażenie da się policzyć, a PiP stoi w rogu.
    bad="$(grep '^MOVE ' <<< "$out" | grep -F $'\tBAD' || true)"
    if [[ -z "$bad" ]]; then ok "$rice: każda reguła move to poprawne wyrażenie"
    else fail "$rice: reguła move, której Hyprland nie policzy (okno na środku): ${bad#MOVE }"; fi
    pip="$(grep -m1 -F 'MOVE ^(Picture-in-Picture)$'$'\t' <<< "$out" || true)"
    IFS=$'\t' read -r _ x y w h <<< "$pip"
    if [[ "$x" =~ ^-?[0-9.]+$ && "$y" =~ ^-?[0-9.]+$ ]] && (( ${x%.*} + w == 1910 && ${y%.*} + h == 1070 )); then
        ok "$rice: okno PiP w prawym dolnym rogu (10 px od krawędzi 1920x1080)"
    else fail "$rice: okno PiP nie w rogu: x=${x:-?} y=${y:-?} rozmiar ${w:-?}x${h:-?}"; fi
    [[ "$rice" == white-blue_beta ]] && continue
    n="$(grep -cx 'BIND SUPER + TAB => ~/archenemy/scripts/hypr/window-history.sh restore' <<< "$out")"
    if [[ "$n" -eq 1 ]]; then ok "$rice: Super+Tab → window-history.sh restore"
    else fail "$rice: bind Super+Tab $n razy (ma być 1)"; fi
done

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
