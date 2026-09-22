#!/bin/bash
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
#   Uruchom: bash tests/rice-autostart.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA="$(command -v lua5.4 || command -v lua || true)"
if [[ -z "$LUA" ]]; then echo "brak interpretera lua5.4 — pomijam"; exit 0; fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

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
local handlers, execs = {}, {}
hl = proxy()
rawset(hl, "on", function(ev, fn) if ev == "hyprland.start" then handlers[#handlers + 1] = fn end end)
rawset(hl, "exec_cmd", function(cmd) execs[#execs + 1] = cmd end)
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
done

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
