#!/bin/bash

# =============================================
#   archenemy - workspace-mode-switch.sh
#   Przełącza tryb workspace'ów na żywo (shared <-> decades) BEZ ponownego
#   biegu install.sh. Wołany z TUI Super+A (appbinds.sh) albo wprost.
#   UI po angielsku (kontekst Super+A — decyzja właściciela 2026-07-12).
#
#   Co robi:
#     1. odtwarza kolejność monitorów L->P z data/monitors/*.dat (ORDER=k),
#     2. regeneruje config/hypr/workspaces-monitors.conf przez wspólną
#        bibliotekę lib/gen-workspaces.sh (JEDNO źródło prawdy z install.sh),
#     3. zapisuje nowy tryb do data/workspace-mode.dat (atomowo),
#     4. hyprctl reload — bindy Super+1..0 i reguły workspace'ów wchodzą od razu,
#     5. guard sierot: przy ->decades startuje go, jeśli nie działa (w shared
#        sesja go nie odpala); przy ->shared guard sam robi się bierny.
#
#   Użycie: workspace-mode-switch.sh <shared|decades|toggle>
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
DATA_DIR="$ARCHENEMY_DIR/data"
MON_DIR="$DATA_DIR/monitors"
MODE_DAT="$DATA_DIR/workspace-mode.dat"
WS_CONF="$ARCHENEMY_DIR/config/hypr/workspaces-monitors.conf"
GUARD="$ARCHENEMY_DIR/scripts/hypr/workspace-orphan-guard.sh"
LIB="$ARCHENEMY_DIR/scripts/hypr/lib/gen-workspaces.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

notify() { command -v notify-send &>/dev/null && notify-send "archenemy" "$1"; }

# ─── Argument: docelowy tryb ───
usage() { echo "usage: workspace-mode-switch.sh <shared|decades|toggle>" >&2; exit 1; }

# Aktualny tryb (brak pliku → decades, spójnie z ws-scroll.sh i guardem).
CURRENT="decades"
[[ -f "$MODE_DAT" ]] && CURRENT="$(<"$MODE_DAT")"

TARGET="${1:-}"
case "$TARGET" in
    shared|decades) ;;
    toggle) [[ "$CURRENT" == "shared" ]] && TARGET="decades" || TARGET="shared" ;;
    *) usage ;;
esac

if [[ "$TARGET" == "$CURRENT" ]]; then
    echo -e "  ${YELLOW}Already in '${TARGET}' mode — nothing to do.${NC}"
    exit 0
fi

# ─── Biblioteka generatora (jedno źródło prawdy z install.sh) ───
if [[ ! -f "$LIB" ]]; then
    echo -e "  ${RED}✗ Missing $LIB — run install.sh once.${NC}" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB"

# ─── Kolejność monitorów L->P z data/monitors/*.dat (ORDER=k) ───
# To ten sam wkład, który install.sh podaje generatorowi. Brak plików = brak
# wiedzy o numeracji → nie zgadujemy, każemy przejść install.sh.
ORDERED_LR=()
if [[ -d "$MON_DIR" ]]; then
    while IFS= read -r mon; do
        [[ -n "$mon" ]] && ORDERED_LR+=("$mon")
    done < <(
        for f in "$MON_DIR"/*.dat; do
            [[ -e "$f" ]] || continue
            ord="$(grep -m1 '^ORDER=' "$f" | cut -d= -f2)"
            [[ -n "$ord" ]] && printf '%s\t%s\n' "$ord" "$(basename "$f" .dat)"
        done | sort -n -s -k1,1 | cut -f2
    )
fi

if [[ ${#ORDERED_LR[@]} -eq 0 ]]; then
    echo -e "  ${RED}✗ No monitor data in $MON_DIR — run ./install/install.sh first.${NC}" >&2
    exit 1
fi

# ─── Regeneracja workspaces-monitors.conf (atomowo: tmp + mv) ───
tmp="$(mktemp "${WS_CONF}.XXXXXX")" || { echo -e "  ${RED}✗ mktemp failed.${NC}" >&2; exit 1; }
if ! generate_workspaces_monitors "$tmp" "$TARGET" "${ORDERED_LR[@]}"; then
    rm -f "$tmp"
    echo -e "  ${RED}✗ Generation failed — mode unchanged.${NC}" >&2
    exit 1
fi
mv "$tmp" "$WS_CONF"

# ─── Zapis trybu (atomowo) ───
tmp_mode="$(mktemp "${MODE_DAT}.XXXXXX")" && printf '%s\n' "$TARGET" > "$tmp_mode" && mv "$tmp_mode" "$MODE_DAT"

echo -e "  ${GREEN}✓ Workspace mode: ${CYAN}${CURRENT}${NC} → ${CYAN}${TARGET}${NC}  (${#ORDERED_LR[@]} monitors, L→R: ${ORDERED_LR[*]})"

# ─── Reload Hyprlanda ───
if command -v hyprctl &>/dev/null; then
    hyprctl reload &>/dev/null && echo -e "  ${GREEN}✓ Hyprland reloaded.${NC}"
else
    echo -e "  ${YELLOW}⚠ hyprctl unavailable — reload Hyprland manually.${NC}"
fi

# ─── Guard sierot ───
# decades wymaga żywego demona; sesja wstała w shared go nie odpaliła
# (guard kończy na starcie w trybie shared). Startujemy, jeśli nie działa.
# shared: nic nie robimy — merge_orphans w guardzie jest no-op w shared,
# a przy następnym starcie sesji guard i tak sam się wyłączy.
if [[ "$TARGET" == "decades" ]]; then
    if pgrep -f "workspace-orphan-guard.sh" &>/dev/null; then
        echo -e "  ${GREEN}✓ Orphan guard already running.${NC}"
    elif command -v hyprctl &>/dev/null; then
        setsid bash "$GUARD" &>/dev/null &
        echo -e "  ${GREEN}✓ Orphan guard started.${NC}"
        command -v socat &>/dev/null || echo -e "  ${YELLOW}⚠ socat missing — guard runs in 2 s polling mode (install socat + relogin for event mode).${NC}"
    else
        echo -e "  ${YELLOW}⚠ No hyprctl — orphan guard not started (will start on next login).${NC}"
    fi
fi

# ─── Podpowiedź: reload nie przenosi istniejących okien ───
echo -e "  ${YELLOW}Note:${NC} open windows keep their current workspace numbers; for a clean"
echo -e "        re-sort (esp. decade defaultName) relog or move windows manually."
notify "Workspace mode → ${TARGET}"
