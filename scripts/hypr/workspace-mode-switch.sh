#!/usr/bin/env bash

# =============================================
#   archenemy - workspace-mode-switch.sh
#   Przełącza tryb workspace'ów na żywo (shared <-> decades) BEZ ponownego
#   biegu install.sh. Wołany z TUI Super+A (appbinds.sh) albo wprost.
#   UI po angielsku (kontekst Super+A — decyzja właściciela 2026-07-12).
#
#   Co robi:
#     1. odtwarza kolejność monitorów L->P z data/monitors/*.dat (ORDER=k),
#     2. regeneruje config/hypr/workspaces-monitors.lua przez wspólną
#        bibliotekę lib/gen-workspaces.sh (JEDNO źródło prawdy z install.sh),
#     3. zapisuje nowy tryb do data/workspace-mode.dat (atomowo) i odczytuje
#        go; gdy zapis się nie udał, stare reguły wracają i nie ma reloadu,
#     4. hyprctl reload — bindy Super+1..0 i reguły workspace'ów wchodzą od razu,
#     5. guard sierot: przy ->decades startuje go, jeśli nie działa (w shared
#        sesja go nie odpala), i sprawdza, czy proces żyje; przy ->shared guard
#        sam robi się bierny.
#   Zielone „✓” pada dopiero po odczycie skutku (plik trybu, configerrors, pgrep).
#
#   Użycie: workspace-mode-switch.sh <shared|decades|toggle>
#   Kody: 0 = przełączone i odczytane, 1 = nic się nie zmieniło, 2 = tryb
#   zapisany, ale Hyprland albo guard go nie potwierdził.
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
DATA_DIR="$ARCHENEMY_DIR/data"
MON_DIR="$DATA_DIR/monitors"
MODE_DAT="$DATA_DIR/workspace-mode.dat"
WS_CONF="$ARCHENEMY_DIR/config/hypr/workspaces-monitors.lua"
GUARD="$ARCHENEMY_DIR/scripts/hypr/workspace-orphan-guard.sh"
LIB="$ARCHENEMY_DIR/scripts/hypr/lib/gen-workspaces.sh"

GREEN='\033[0;92m'; YELLOW='\033[0;93m'; RED='\033[0;91m'; CYAN='\033[0;96m'; NC='\033[0m'

notify() { command -v notify-send &>/dev/null && notify-send -a archenemy "archenemy" "$1"; }

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
# shellcheck source=/dev/null
source "$ARCHENEMY_DIR/scripts/hypr/lib/monitor-id.sh"
# shellcheck source=/dev/null
source "$ARCHENEMY_DIR/scripts/hypr/lib/gen-monitors.sh"

# ─── Kolejność monitorów L->P z data/monitors/*.dat (ORDER=k) ───
# To ten sam wkład, który install.sh podaje generatorowi: wpis
# "<nazwa złącza><TAB><selektor desc:>" (lib/monitor-id.sh). Brak plików =
# brak wiedzy o numeracji → nie zgadujemy, każemy przejść install.sh.
ORDERED_LR=()
NAMES_LR=()
if [[ -d "$MON_DIR" ]]; then
    mapfile -t ORDERED_LR < <(monitor_entries_ordered "$MON_DIR")
    for entry in "${ORDERED_LR[@]}"; do NAMES_LR+=("${entry%%$'\t'*}"); done
fi

if [[ ${#ORDERED_LR[@]} -eq 0 ]]; then
    echo -e "  ${RED}✗ No monitor data in $MON_DIR — run ./install/install.sh first.${NC}" >&2
    exit 1
fi

# ─── Regeneracja workspaces-monitors.lua (atomowo: tmp + mv) ───
tmp="$(mktemp "${WS_CONF}.XXXXXX")" || { echo -e "  ${RED}✗ mktemp failed.${NC}" >&2; exit 1; }
if ! generate_workspaces_monitors "$tmp" "$TARGET" "${ORDERED_LR[@]}"; then
    rm -f "$tmp"
    echo -e "  ${RED}✗ Generation failed — mode unchanged.${NC}" >&2
    exit 1
fi
# Kopia starych reguł: gdy zapis trybu się nie uda, reguły i bindy muszą wrócić,
# bo guard, ws-scroll i waybar czytają tryb z workspace-mode.dat.
ws_backup=""
if [[ -f "$WS_CONF" ]]; then
    if ! ws_backup="$(mktemp "${WS_CONF}.XXXXXX")" || ! cp -p "$WS_CONF" "$ws_backup"; then
        rm -f "$tmp" "$ws_backup"
        echo -e "  ${RED}✗ Could not back up ${WS_CONF} — mode unchanged.${NC}" >&2
        exit 1
    fi
fi
# Błędy configu PRZED zapisem reguł (lib/hypr-apply.sh: odczyt po zapisie łapałby
# już błąd wczytany autoreloadem i reload wyglądałby na czysty).
# shellcheck source=/dev/null
source "$ARCHENEMY_DIR/scripts/hypr/lib/hypr-apply.sh"
errors_before="$(hypr_config_errors)"
if ! mv "$tmp" "$WS_CONF"; then
    rm -f "$tmp" "$ws_backup"
    echo -e "  ${RED}✗ Could not write ${WS_CONF} — mode unchanged.${NC}" >&2
    exit 1
fi

# ─── Zapis trybu (atomowo) z odczytem ───
# Dowodem jest zawartość pliku, nie kod wyjścia mv.
tmp_mode="$(mktemp "${MODE_DAT}.XXXXXX")" && printf '%s\n' "$TARGET" > "$tmp_mode" && mv "$tmp_mode" "$MODE_DAT"
if [[ ! -f "$MODE_DAT" || "$(<"$MODE_DAT")" != "$TARGET" ]]; then
    [[ -n "${tmp_mode:-}" ]] && rm -f "$tmp_mode"
    if [[ -n "$ws_backup" ]]; then mv "$ws_backup" "$WS_CONF"; else rm -f "$WS_CONF"; fi
    echo -e "  ${RED}✗ Could not save the mode to ${MODE_DAT} — still '${CURRENT}', workspace rules put back, Hyprland not reloaded.${NC}" >&2
    exit 1
fi
[[ -n "$ws_backup" ]] && rm -f "$ws_backup"

SUMMARY="${CYAN}${CURRENT}${NC} → ${CYAN}${TARGET}${NC}  (${#ORDERED_LR[@]} monitors, L→R: ${NAMES_LR[*]})"
RESULT=0   # 0 = wszystko odczytane, 2 = zapisane, ale nie potwierdzone

# ─── Reload Hyprlanda ───
# Zielony komunikat o trybie pada dopiero po przeładowaniu bez błędów.
reload_errors="$(hypr_reload_checked "$errors_before")"
case $? in
    0) echo -e "  ${GREEN}✓ Hyprland reloaded, no config errors.${NC}"
       echo -e "  ${GREEN}✓ Workspace mode: ${SUMMARY}" ;;
    1) echo -e "  ${YELLOW}⚠ Hyprland did not respond — reload it manually.${NC}"
       echo -e "  ${YELLOW}Saved: workspace mode ${SUMMARY}"; RESULT=2 ;;
    2) echo -e "  ${RED}✗ Hyprland reports a config error:${NC}"; printf '    %s\n' "$reload_errors" | head -5
       echo -e "  ${YELLOW}⚠ Workspace mode saved as '${TARGET}', but Hyprland did not take the config cleanly — fix the error above or switch back (Super+A → [w]).${NC}"; RESULT=2 ;;
    3) echo -e "  ${YELLOW}⚠ No Hyprland session — the mode applies when Hyprland starts.${NC}"
       echo -e "  ${YELLOW}Saved: workspace mode ${SUMMARY}"; RESULT=2 ;;
esac

# ─── Guard sierot ───
# decades wymaga żywego demona; sesja wstała w shared go nie odpaliła
# (guard kończy na starcie w trybie shared). Startujemy, jeśli nie działa.
# shared: nic nie robimy — merge_orphans w guardzie jest no-op w shared,
# a przy następnym starcie sesji guard i tak sam się wyłączy.
guard_running() { pgrep -f "workspace-orphan-guard.sh" &>/dev/null; }
if [[ "$TARGET" == "decades" ]]; then
    if guard_running; then
        echo -e "  ${GREEN}✓ Orphan guard already running.${NC}"
    elif command -v hyprctl &>/dev/null; then
        setsid bash "$GUARD" &>/dev/null &
        # Sukces to proces odczytany po starcie: guard, który od razu wyszedł
        # (zajęty lock, brak pliku), nie może dostać zielonego komunikatu.
        sleep "${ARCHENEMY_GUARD_SETTLE:-1}"
        if guard_running; then
            echo -e "  ${GREEN}✓ Orphan guard started.${NC}"
            command -v socat &>/dev/null || echo -e "  ${YELLOW}⚠ socat missing — guard runs in 2 s polling mode (install socat + relogin for event mode).${NC}"
        else
            echo -e "  ${RED}✗ Orphan guard did not start — workspaces of an unplugged monitor will not be merged. Log out and back in, or run: bash ${GUARD} &${NC}"
            RESULT=2
        fi
    else
        echo -e "  ${YELLOW}⚠ No hyprctl — orphan guard not started (will start on next login).${NC}"
    fi
fi

# ─── Podpowiedź: reload nie przenosi istniejących okien ───
echo -e "  ${YELLOW}Note:${NC} open windows keep their current workspace numbers; for a clean"
echo -e "        re-sort (esp. decade defaultName) relog or move windows manually."
if (( RESULT == 0 )); then notify "Workspace mode → ${TARGET}"; else notify "Workspace mode → ${TARGET} saved, not confirmed — see Super+A → [w]"; fi
exit "$RESULT"
