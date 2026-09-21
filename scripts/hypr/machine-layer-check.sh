#!/bin/bash

# =============================================
#   archenemy - machine-layer-check.sh
#   Samokontrola warstwy maszynowej na starcie sesji (TYLKO ODCZYT +
#   powiadomienie). Start z hl.on("hyprland.start") we wspólnym
#   config/hypr/workspaces.lua — dziedziczą wszystkie rice'y.
#
#   Zasada integralności (2026-09-21): pliki generowane przez install.sh
#   opisują maszynę Z DNIA INSTALACJI. Gdy rzeczywistość odjedzie (inna
#   nazwa złącza, odpięty monitor, plik skasowany), Hyprland nie zgłasza
#   błędu — po prostu cicho stosuje fallback, a użytkownik widzi „wszystko
#   się sypie” bez wskazówki. Ten skrypt zamienia cichy fallback w JEDNO
#   powiadomienie z instrukcją. Nic nie naprawia sam.
#
#   Sprawdza:
#     1. każdy plik warstwy maszynowej wymagany przez hyprland.lua istnieje,
#     2. każda reguła hl.monitor (poza fallbackiem output = "") pasuje do
#        jakiegoś PODŁĄCZONEGO monitora (nazwa albo desc: po prefiksie),
#     3. każdy monitor w reguły hl.workspace_rule jest podłączony,
#     4. żaden podłączony monitor nie został bez własnej reguły hl.monitor.
#   Odpięty monitor zewnętrzny to normalna sytuacja (laptop w drodze) —
#   dlatego 2/3 alarmują dopiero, gdy ŻADNA reguła nie pasuje do NICZEGO
#   (to znaczy zmieniły się nazwy, a nie że czegoś chwilowo nie ma).
#
#   Użycie: machine-layer-check.sh [--quiet]   (kod 0 = OK, 1 = problemy;
#           bez --quiet raport na stdout, z problemami także notify-send)
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
HYPR_DIR="$ARCHENEMY_DIR/config/hypr"
MON_CONF="$HYPR_DIR/monitorshyprl.lua"
WS_CONF="$HYPR_DIR/workspaces-monitors.lua"
# shellcheck source=scripts/hypr/lib/monitor-id.sh
source "$ARCHENEMY_DIR/scripts/hypr/lib/monitor-id.sh"

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

PROBLEMS=()
problem() { PROBLEMS+=("$1"); }

# 1. pliki generowane (lista = require() w rices/*/hypr/hyprland.lua)
for f in monitorshyprl.lua workspaces-monitors.lua hardware-keys.lua gpu-env.lua \
         autostartpersonalisation.lua appbinds.lua hyprpaper.conf; do
    [[ -e "$HYPR_DIR/$f" ]] || problem "brak config/hypr/$f"
done

# Podłączone monitory: nazwy + opisy (pełny i krótki „make model serial”).
declare -A LIVE_NAMES=()
LIVE_DESCS=()
if command -v hyprctl >/dev/null 2>&1; then
    name=""
    while IFS= read -r line; do
        case "$line" in
            'Monitor '*) name="${line#Monitor }"; name="${name%% *}"; [[ -n "$name" ]] && LIVE_NAMES[$name]=1 ;;
            *'description: '*) LIVE_DESCS+=("${line#*description: }") ;;
        esac
    done < <(hyprctl monitors 2>/dev/null)
fi

selector_matches_live() {
    local sel="$1" d
    if [[ "$sel" == desc:* ]]; then
        for d in "${LIVE_DESCS[@]}"; do [[ "desc:$d" == "$sel"* ]] && return 0; done
        return 1
    fi
    [[ -n "${LIVE_NAMES[$sel]:-}" ]]
}

if ((${#LIVE_NAMES[@]})); then
    # 2. reguły monitorów
    if [[ -f "$MON_CONF" ]]; then
        rules=0; hits=0
        while IFS= read -r sel; do
            [[ -z "$sel" ]] && continue      # fallback output = ""
            rules=$((rules + 1))
            selector_matches_live "$sel" && hits=$((hits + 1))
        done < <(sed -n 's/^hl\.monitor({ output = "\([^"]*\)".*$/\1/p' "$MON_CONF")
        if (( rules > 0 && hits == 0 )); then
            problem "żadna reguła monitora z monitorshyprl.lua nie pasuje do podłączonych monitorów (${!LIVE_NAMES[*]}) — zmieniły się nazwy złączy?"
        fi
        # 4. monitor bez reguły
        for n in "${!LIVE_NAMES[@]}"; do
            covered=0
            while IFS= read -r sel; do
                [[ -z "$sel" ]] && continue
                if [[ "$sel" == desc:* ]]; then
                    d=$(hyprctl monitors 2>/dev/null | awk -v m="$n" '/^Monitor /{cur=$2} cur==m && /description: /{sub(/^[ \t]*description: /,""); print; exit}')
                    [[ "desc:$d" == "$sel"* ]] && covered=1
                else
                    [[ "$sel" == "$n" ]] && covered=1
                fi
            done < <(sed -n 's/^hl\.monitor({ output = "\([^"]*\)".*$/\1/p' "$MON_CONF")
            (( covered )) || problem "monitor $n nie ma własnej reguły w monitorshyprl.lua (dostaje fallback preferred/auto)"
        done
    fi
    # 3. reguły workspace'ów
    if [[ -f "$WS_CONF" ]]; then
        rules=0; hits=0
        while IFS= read -r sel; do
            rules=$((rules + 1))
            selector_matches_live "$sel" && hits=$((hits + 1))
        done < <(sed -n 's/^hl\.workspace_rule({ workspace = "[0-9]\+", monitor = "\([^"]\+\)".*$/\1/p' "$WS_CONF" | sort -u)
        if (( rules > 0 && hits == 0 )); then
            problem "żadna reguła workspace'ów z workspaces-monitors.lua nie pasuje do podłączonych monitorów"
        fi
    fi
fi

if ((${#PROBLEMS[@]} == 0)); then
    (( QUIET )) || echo "machine layer: OK"
    exit 0
fi

(( QUIET )) || printf 'machine layer: %s\n' "${PROBLEMS[@]}"
if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "archenemy: machine layer out of date" \
        "$(printf '%s\n' "${PROBLEMS[@]}")
Fix: run ~/archenemy/install/install.sh again (steps [3]–[3.7] re-read the monitors), then log out and back in."
fi
exit 1
