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
#   Agent polkit (D7, C-D7: nowe wywołanie w yin): każdy aktywny rice startuje
#   go DOKŁADNIE RAZ przez scripts/hypr/polkit-agent.sh, nie gołym systemctl.
#   Skrypt na atrapie systemctl: sukces = cisza; brak jednostki, brak busa
#   użytkownika i brak systemctl = kod 0, nic na wyjściu, jedna linia w logu
#   prywatnego katalogu sesji; bez takiego katalogu — bez logu i bez /tmp.
#   Uruchom: bash tests/rice-autostart.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA="$(command -v lua5.4 || command -v lua || true)"
if [[ -z "$LUA" ]]; then echo "brak interpretera lua5.4 — pomijam"; exit 0; fi
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
# D7F R3: cały pakiet w przestrzeni nazw z overlayem (zapisy poza $T wykrywalne, host nietknięty).
test_isolate "$REPO/tests/rice-autostart.sh" "$@"
# Zapisy wyłącznie pod $T (D7): pusty $T po nieudanym mktemp zamieniałby
# "$T/…" w ścieżki w / — stąd twarde sprawdzenie i ${T:?} przy każdym zapisie.
ROOT_BEFORE="$(find / -mindepth 1 -maxdepth 1 -printf "%f\n" | LC_ALL=C sort)"
T="$(mktemp -d)" && [[ -n "$T" && -d "$T" && "$T" != / ]] || { echo "mktemp -d nie zadziałał — przerywam bez zapisu"; exit 1; }
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
    # shellcheck disable=SC2088  # literalna komenda z configu Lua, nie ścieżka powłoki
    n="$(grep -cxF '~/archenemy/scripts/hypr/polkit-agent.sh' <<< "$out")"
    if [[ "$n" -eq 1 ]] && ! grep -q '^systemctl ' <<< "$out"; then ok "$rice: agent polkit przez polkit-agent.sh dokładnie raz, bez gołego systemctl"
    else fail "$rice: polkit-agent.sh $n razy albo goły systemctl w autostarcie"; fi
    n="$(grep -cx 'BIND SUPER + TAB => ~/archenemy/scripts/hypr/window-history.sh restore' <<< "$out")"
    if [[ "$n" -eq 1 ]]; then ok "$rice: Super+Tab → window-history.sh restore"
    else fail "$rice: bind Super+Tab $n razy (ma być 1)"; fi
done

# ─── scripts/hypr/polkit-agent.sh na atrapie systemctl ───────────────────────
echo "== polkit-agent.sh"
AGENT="$REPO/scripts/hypr/polkit-agent.sh"
mkdir -p "${T:?}/pbin" "${T:?}/nosysctl" "${T:?}/run" && chmod 700 "${T:?}/run"
# MOCK_POLKIT: ok | nounit | nobus — jak prawdziwy systemctl (komunikat na stderr, kod ≠ 0).
# shellcheck disable=SC2016  # treść atrapy: zmienne mają się rozwinąć w atrapie, nie tutaj
printf '%s\n' '#!/usr/bin/env bash' 'echo "systemctl $*" >> "$POLKIT_CALLS"' \
    'case "${MOCK_POLKIT:-ok}" in' \
    '    nounit) echo "Failed to start hyprpolkitagent.service: Unit hyprpolkitagent.service not found." >&2; exit 5 ;;' \
    '    nobus)  echo "Failed to connect to bus: No medium found" >&2; exit 1 ;;' \
    'esac' 'exit 0' > "${T:?}/pbin/systemctl"
chmod +x "${T:?}/pbin/systemctl"
# Wąski PATH: tylko to, czego skrypt potrzebuje (bez systemctl hosta).
for c in bash env date dirname cat stat mkdir; do
    ln -sf "$(command -v "$c")" "${T:?}/pbin/$c"; ln -sf "$(command -v "$c")" "${T:?}/nosysctl/$c"
done
export POLKIT_CALLS="${T:?}/polkit-calls"
polkit_run() {   # polkit_run <stan> <PATH> <XDG_RUNTIME_DIR> — wynik w $p_rc, $p_out, $p_log
    : > "$POLKIT_CALLS"; rm -f "${T:?}/run/archenemy-polkit-agent.log"
    p_out="$(MOCK_POLKIT="$1" PATH="$2" XDG_RUNTIME_DIR="$3" ARCHENEMY_RUNTIME_SYSTEM="${T:?}/none" \
        TMPDIR="${T:?}/tmpdir" "${T:?}/pbin/bash" "$AGENT" 2>&1)"; p_rc=$?
    p_log="$(cat "${T:?}/run/archenemy-polkit-agent.log" 2>/dev/null)"
}
polkit_run ok "${T:?}/pbin" "${T:?}/run"
if [[ $p_rc -eq 0 && -z "$p_out" && -z "$p_log" && "$(<"$POLKIT_CALLS")" == "systemctl --user start hyprpolkitagent" ]]; then
    ok "polkit-agent.sh: jednostka jest — start użytkownika, bez enable, cisza, bez logu"
else fail "polkit-agent.sh ok: rc=$p_rc out=$p_out log=$p_log calls=$(<"$POLKIT_CALLS")"; fi
for st in nounit nobus; do
    polkit_run "$st" "${T:?}/pbin" "${T:?}/run"
    if [[ $p_rc -eq 0 && -z "$p_out" && "$(grep -c . <<< "$p_log")" -eq 1 && "$p_log" == *"start hyprpolkitagent failed"* ]] \
        && ! grep -qE 'enable|daemon-reload' "$POLKIT_CALLS"; then
        ok "polkit-agent.sh $st: kod 0, nic na wyjściu sesji, jedna linia w logu"
    else fail "polkit-agent.sh $st: rc=$p_rc out=$p_out log=$p_log"; fi
done
polkit_run ok "${T:?}/nosysctl" "${T:?}/run"
if [[ $p_rc -eq 0 && -z "$p_out" && "$p_log" == *"start hyprpolkitagent failed"* ]]; then
    ok "polkit-agent.sh bez systemctl w PATH: kod 0, cisza, wpis w logu"
else fail "polkit-agent.sh bez systemctl: rc=$p_rc out=$p_out log=$p_log"; fi
# Brak katalogu sesji, a w TMPDIR cudzy (zły) katalog archenemy-<UID>: bez logu i bez /tmp.
mkdir -p "${T:?}/tmpdir/archenemy-$UID" && chmod 755 "${T:?}/tmpdir/archenemy-$UID"
polkit_run nounit "${T:?}/pbin" ""
if [[ $p_rc -eq 0 && -z "$p_out" && -z "$(find "${T:?}/tmpdir" -type f)" ]]; then
    ok "polkit-agent.sh bez prywatnego katalogu sesji: kod 0, cisza, żadnego logu"
else fail "polkit-agent.sh bez katalogu sesji: rc=$p_rc out=$p_out pliki=$(find "${T:?}/tmpdir" -type f)"; fi
if [[ "$(grep -c 'systemctl --user start hyprpolkitagent' "$REPO/rices/white-blue_beta/hypr/hyprland.lua")" -eq 1 ]]; then
    ok "white-blue_beta zamrożona: dawna linia bez zmian"
else fail "white-blue_beta: zmieniona linia agenta polkit"; fi

# Po biegu w / nie ma nowych wpisów (zapis poza $T = porażka).
# D7F R3: żadnej zmiany poza $T w nakrytych katalogach (także głęboko: /tmp/<cudzy>/…, /root/…).
if escaped="$(test_escapes "$T")"; then ok "zero zapisów poza \$T w: $(test_isolation_dirs)"
elif [[ $? == 2 ]]; then echo "  – izolacja niedostępna (unshare/overlay): sprawdzane tylko nazwy w /"
else fail "zapisy poza \$T: ${escaped//$'\n'/ }"; fi
root_new="$(comm -13 <(echo "$ROOT_BEFORE") <(find / -mindepth 1 -maxdepth 1 -printf "%f\n" | LC_ALL=C sort))"
if [[ -z "$root_new" ]]; then ok "żadnych nowych plików w / po biegu"
else fail "nowe wpisy w / po biegu: ${root_new//$'\n'/ }"; fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
