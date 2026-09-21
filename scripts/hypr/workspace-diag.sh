#!/bin/bash

# =============================================
#   archenemy - workspace-diag.sh
#   Zrzut stanu workspace'ów do diagnozy (TYLKO ODCZYT — niczego nie zmienia).
#   Zbiera w jednym miejscu wszystko, co trzeba porównać, gdy pasek pokazuje
#   podwójną "1" albo Super+1..0 / scroll nie trafia tam, gdzie powinien:
#     - tryb workspace'ów i numeracja monitorów (warstwa maszynowa),
#     - reguły z generowanego workspaces-monitors.lua vs. to, co Hyprland
#       faktycznie trzyma (hyprctl workspacerules),
#     - monitory, workspace'y i okna (id + nazwa + monitor),
#     - bindy Super+cyfra, błędy configu, stan guarda sierot i waybara,
#     - nazwy/opisy monitorów TERAZ vs reguły hl.monitor z monitorshyprl.lua
#       (nazwa złącza potrafi się zmienić między restartami),
#     - linie z logu Hyprlanda o przenoszeniu workspace'ów i o tym, którą
#       regułę monitora zastosowano (brak reguły / nadpisanie z wlr-output-management).
#
#   Użycie: workspace-diag.sh [> plik]
#   Najlepiej: zrzut PRZED Super+T i zaraz PO — i porównać (diff).
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
DATA_DIR="$ARCHENEMY_DIR/data"
WS_CONF="$ARCHENEMY_DIR/config/hypr/workspaces-monitors.lua"

section() { printf '\n===== %s =====\n' "$1"; }

if ! command -v hyprctl >/dev/null 2>&1; then
    echo "hyprctl not found — run inside a Hyprland session." >&2
    exit 1
fi

section "wersje"
echo "date: $(date '+%F %T')"
hyprctl version 2>/dev/null | head -n 2
command -v waybar >/dev/null 2>&1 && echo "waybar: $(waybar --version 2>/dev/null | head -n 1)"
echo "socat: $(command -v socat || echo BRAK)"

section "warstwa maszynowa"
echo "workspace-mode.dat: $(cat "$DATA_DIR/workspace-mode.dat" 2>/dev/null || echo BRAK)"
echo "current rice: $(cat "$ARCHENEMY_DIR/.current_rice" 2>/dev/null || echo BRAK)"
for f in "$DATA_DIR"/monitors/*.dat; do
    [[ -e "$f" ]] || { echo "data/monitors: BRAK plików"; break; }
    printf '%s: %s\n' "$(basename "$f")" "$(grep -E '^(ORDER|ROLE|POSITION)=' "$f" | tr '\n' ' ')"
done

section "workspaces-monitors.lua (reguły)"
if [[ -f "$WS_CONF" ]]; then
    grep -n '^hl\.workspace_rule' "$WS_CONF"
    echo "bindów hl.bind w pliku: $(grep -c '^hl\.bind' "$WS_CONF")"
else
    echo "BRAK $WS_CONF"
fi

section "hyprctl monitors"
hyprctl monitors 2>/dev/null | grep -E '^Monitor|active workspace|focused|disabled'

# Monitory: nazwa złącza (DP-1, HDMI-A-1…) potrafi się ZMIENIĆ między
# restartami/przepięciami (dock USB-C, inne gniazdo) — a reguły hl.monitor
# i hl.workspace_rule z warstwy maszynowej celują w nazwę z dnia instalacji.
# Zestawienie: co widzi Hyprland teraz (z opisem, który jest stały) vs. do
# jakich nazw strzela monitorshyprl.lua. Rozjazd = monitor spada na regułę
# fallback (preferred/auto), a jego dekada workspace'ów staje się sierotą.
section "monitory: nazwy i opisy TERAZ vs reguły z monitorshyprl.lua"
hyprctl monitors all 2>/dev/null | grep -E '^Monitor|^\s*(description|make|model|serial|disabled):' | sed 's/^\s*/  /'
MON_CONF="$ARCHENEMY_DIR/config/hypr/monitorshyprl.lua"
if [[ -f "$MON_CONF" ]]; then
    grep -n '^hl\.monitor' "$MON_CONF"
else
    echo "BRAK $MON_CONF"
fi

section "hyprctl workspaces (id / nazwa / monitor / okna)"
hyprctl workspaces 2>/dev/null | grep -E '^workspace ID|^\s*windows:' | paste - - | sed 's/\t/  /g'
echo "activeworkspace: $(hyprctl activeworkspace 2>/dev/null | head -n 1)"

section "hyprctl workspacerules (co Hyprland naprawdę trzyma)"
hyprctl workspacerules 2>/dev/null | grep -E '^Workspace rule|monitor:|defaultName:|default:' | paste - - - - 2>/dev/null | sed 's/\t/  /g'

section "hyprctl clients (adres / klasa / workspace)"
hyprctl clients 2>/dev/null | grep -E '^Window|^\s*class:|^\s*workspace:' | paste - - - | sed 's/\t/  /g'

section "bindy na cyfry (hyprctl binds — bindy Lua widać tylko jako __lua)"
# Każdy bind to blok: bind* / modmask / submap / key / keycode / ... — tu
# tylko klawisz + maska, bo dyspozytor Lua jest nieczytelny (numer referencji).
echo "bindów łącznie: $(hyprctl binds 2>/dev/null | grep -c '^bind')"
hyprctl binds 2>/dev/null | grep -E '^\s*(modmask|key):' | paste - - | grep -E 'key: [0-9]$' | sed 's/\t/  /g'

section "hyprctl configerrors"
hyprctl configerrors 2>/dev/null

section "guard sierot i waybar"
pgrep -af "workspace-orphan-guard.sh" || echo "guard: NIE DZIAŁA"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/archenemy-workspace-guard.lock"
if [[ -e "$LOCK" ]]; then
    if flock -n "$LOCK" true 2>/dev/null; then echo "lock guarda: wolny (demon nie trzyma)"; else echo "lock guarda: zajęty (demon żyje)"; fi
fi
echo "waybar procesów: $(pgrep -xc waybar)"

section "log Hyprlanda — przenoszenie workspace'ów (ostatnie 40 linii)"
LOG="${XDG_RUNTIME_DIR:-}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/hyprland.log"
if [[ -f "$LOG" ]]; then
    grep -E 'moveWorkspaceToMonitor|ensurePersistentWorkspacesPresent|ensureWorkspacesOnAssignedMonitors|Plugging gap|seen this monitor|config reload|Removed monitor|onDisconnect|Your config|No rule found for|No rules configured|wlr_output_manager override|failed to apply rule' "$LOG" | tail -n 40
else
    echo "BRAK $LOG"
fi
