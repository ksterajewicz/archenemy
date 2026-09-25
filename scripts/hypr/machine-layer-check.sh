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
#     4. żaden podłączony monitor nie został bez własnej reguły hl.monitor,
#     5. kod repo nie zmienił się od ostatniego install.sh w katalogach, które
#        install.sh przetwarza (data/installed-head.dat — audyt 2026-09-23).
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

# 5. wersja kodu a ostatni install.sh. Kod powstaje gdzie indziej, a maszyna
#    bywa na innej wersji niż ta, z której wygenerowano warstwę maszynową
#    (2026-09-17: laptop 10 commitów za origin, zgłoszenia dotyczyły starego
#    kodu). install.sh zapisuje COMMIT do data/installed-head.dat; alarm tylko
#    przy zmianach w install/ scripts/ config/ rices/ src/ packages/ —
#    dokumentacja nie wymaga ponownej instalacji. Brak pliku (instalacja
#    sprzed tej zmiany) albo brak gita = cisza, jak dotąd.
INSTALLED_DAT="$ARCHENEMY_DIR/data/installed-head.dat"
if [[ -f "$INSTALLED_DAT" ]] && git -C "$ARCHENEMY_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    inst="$(sed -n 's/^COMMIT=//p' "$INSTALLED_DAT")"
    head="$(git -C "$ARCHENEMY_DIR" rev-parse HEAD 2>/dev/null)"
    if [[ -n "$inst" && -n "$head" && "$inst" != "$head" ]]; then
        if ! git -C "$ARCHENEMY_DIR" cat-file -e "${inst}^{commit}" 2>/dev/null; then
            problem "kod repo (${head:0:7}) nie pochodzi z wersji ostatniej instalacji (${inst:0:7}) — uruchom ponownie install.sh"
        else
            n=$(git -C "$ARCHENEMY_DIR" diff --name-only "$inst" HEAD -- install scripts config rices src packages 2>/dev/null | wc -l)
            (( n > 0 )) && problem "kod zaktualizowany od ostatniego install.sh (${inst:0:7} → ${head:0:7}, zmienione pliki: $n) — pliki generowane mogą być nieaktualne"
        fi
    fi
    (( QUIET )) || echo "installed from: ${inst:0:7} · repo HEAD: ${head:0:7}"
fi

# Podłączone monitory: nazwy + opisy (pełny i krótki „make model serial”).
# Jedno wywołanie hyprctl — LIVE_DESC_OF[nazwa] = opis, do sprawdzeń per monitor.
declare -A LIVE_NAMES=() LIVE_DESC_OF=()
LIVE_DESCS=()
if command -v hyprctl >/dev/null 2>&1; then
    name=""
    while IFS= read -r line; do
        case "$line" in
            'Monitor '*) name="${line#Monitor }"; name="${name%% *}"; [[ -n "$name" ]] && LIVE_NAMES[$name]=1 ;;
            *'description: '*) LIVE_DESCS+=("${line#*description: }"); [[ -n "$name" ]] && LIVE_DESC_OF[$name]="${line#*description: }" ;;
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
                    [[ "desc:${LIVE_DESC_OF[$n]:-}" == "$sel"* ]] && covered=1
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
