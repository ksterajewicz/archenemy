#!/bin/bash
# =============================================
#   archenemy - tests/focus-highlight.sh
#   config/hypr/focus-highlight.lua na atrapie API Hyprlanda (Lua 5.4):
#   neon gaśnie po wyjściu kursora z monitora aktywnego okna i wraca.
#   Bez Hyprlanda; prawdziwy efekt kolorów sprawdza się tylko na żywo.
#   Uruchom: bash tests/focus-highlight.sh   (kod 0 = wszystko przeszło)
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

cat > "$T/t.lua" <<'LUA'
local cfg, handlers, active = {}, {}, nil
local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print("  ✓ " .. name)
    else fail = fail + 1; print("  ✗ " .. name) end
end
local function reset(shadow_inactive)
    cfg = {
        ["general:col.active_border"] = { colors = { "0xFF00E5FF", "0xFF7DF9FF" }, angle = 45 },
        ["general:col.inactive_border"] = { colors = { "0xAA0E2A33" }, angle = 0 },
        ["decoration:shadow:color"] = { colors = { "0x4500E5FF" }, angle = 0 },
        ["decoration:shadow:color_inactive"] = shadow_inactive,
    }
end
hl = {
    on = function(ev, fn) handlers[ev] = fn end,
    get_active_window = function() return active end,
    get_config = function(key) return cfg[key] end,
    config = function(t)
        if t.general then cfg["general:col.active_border"] = t.general["col.active_border"] end
        if t.decoration then cfg["decoration:shadow:color"] = t.decoration.shadow.color end
    end,
}
local function neon() return cfg["general:col.active_border"].colors[1] == "0xFF00E5FF" end
local function glow() return cfg["decoration:shadow:color"].colors[1] == "0x4500E5FF" end
local M1, M2 = { id = 1 }, { id = 2 }
local W1 = { monitor = M1 }

reset({ colors = { "0x30000000" }, angle = 0 })
dofile(arg[1])
active = W1

handlers["monitor.focused"](M2)
check("kursor na monitorze bez okna → ramka gaśnie", not neon())
check("poświata gaśnie", not glow())
check("ramka = kolor nieaktywnego", cfg["general:col.active_border"].colors[1] == "0xAA0E2A33")
handlers["monitor.focused"](M2)
handlers["monitor.focused"](M1)
check("powrót kursora → ramka wraca, także po podwójnym zdarzeniu", neon())
check("powrót kursora → pełny gradient", #cfg["general:col.active_border"].colors == 2)
check("powrót kursora → poświata wraca", glow())

handlers["monitor.focused"](M2)
handlers["window.active"]()
check("fokus na oknie (Super+strzałka) → neon wraca", neon() and glow())

active = nil
handlers["monitor.focused"](M2)
check("brak aktywnego okna → nic nie gaśnie", neon())

active = W1
-- Wczytanie pliku od nowa = nowy stan Lua, jak po reloadzie Hyprlanda.
reset(nil); dofile(arg[1])
handlers["monitor.focused"](M2)
check("rice bez color_inactive → poświata nietknięta", glow() and not neon())
reset({ colors = { "0xFFFFFFFF" }, angle = 0 }); dofile(arg[1])
handlers["monitor.focused"](M2)
check("color_inactive = -1 (biel) → bez białej poświaty", glow())

-- Hyprland oddaje kolor obcięty: gdyby paletę czytać co cykl, ramka by ciemniała.
reset({ colors = { "0x30000000" }, angle = 0 }); dofile(arg[1])
local real_get = hl.get_config
local reads = 0
hl.get_config = function(key) reads = reads + 1; return real_get(key) end
for _ = 1, 3 do handlers["monitor.focused"](M2); handlers["monitor.focused"](M1) end
hl.get_config = real_get
check("kolory czytane raz na stan Lua (bez dryfu po cyklach)", reads == 4 and neon())

hl.on = function() error("unknown event") end
check("starszy Hyprland bez zdarzeń → config dalej się ładuje", pcall(dofile, arg[1]))

print(""); print(("Wynik: %d ✓ / %d ✗"):format(pass, fail))
os.exit(fail == 0)
LUA
"$LUA" "$T/t.lua" "$REPO/config/hypr/focus-highlight.lua"
