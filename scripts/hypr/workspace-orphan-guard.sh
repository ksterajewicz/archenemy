#!/bin/bash

# =============================================
#   archenemy - workspace-orphan-guard.sh
#   Demon (start z hl.on("hyprland.start") we wspólnym workspaces.lua).
#
#   Problem: po odpięciu monitora Hyprland przenosi jego
#   workspace'y (11-20, 21-30, ...) na pozostały ekran — pasek
#   pokazuje wtedy dwa workspace'y "1" (id 1 oraz id 11
#   z defaultName:1), a okna "znikają": lądują poza zasięgiem
#   Super+1..0 (bindy r~N sięgają tylko dekady swojego monitora).
#
#   Sierota powstaje też bez odpinania: scroll/klik/przeniesienie
#   okna poza dekadę żywego monitora tworzy workspace przypięty
#   do monitora, którego nie ma.
#
#   Trzeci rodzaj (2026-09-21): workspace BEZ ŻADNEJ reguły (np. 21, 22).
#   Gdy reguły celowały w nieaktualne nazwy złączy, Hyprland dla żywych
#   monitorów wziął pierwsze wolne numery poza dekadami
#   (Monitor.cpp findAvailableDefaultWS pomija id związane z innym
#   monitorem). Po naprawie reguł (install.sh, hyprctl reload) te
#   workspace'y ZOSTAJĄ — reload nie przenosi istniejących — i pasek
#   pokazuje „21 22". Guard scala je do dekady monitora, na którym leżą
#   (21 na HDMI z dekadą 11-20 → 11), o ile ten monitor jakąś dekadę ma.
#
#   Rozwiązanie: po zdarzeniach socket2 (monitorremoved,
#   configreloaded, createworkspace, movewindow) guard scala
#   osierocone workspace'y — okna z 10N+i trafiają na
#   odpowiednik "i" w dekadzie pierwszego podłączonego monitora,
#   pusty sierota znika sam (nie jest persistent). Podpięcie
#   monitora z powrotem obsługuje sam Hyprland (reguły
#   workspace = N, monitor:X działają przy connect).
#
#   Reguły przypięcia czyta z generowanego (maszynowego)
#   workspaces-monitors.lua — patrz install.sh [8b]. Wzorzec seda niżej
#   jest sprzężony z formatem emisji gen-workspaces.sh (JEDNA linia na
#   hl.workspace_rule) — zmieniasz tam, zmieniasz tu.
#   Wywołanie ręczne: workspace-orphan-guard.sh --sweep
#   (jednorazowe sprzątanie, bez demona).
# =============================================

set -uo pipefail

WS_MON_CONF="$HOME/archenemy/config/hypr/workspaces-monitors.lua"
WS_MODE_DAT="$HOME/archenemy/data/workspace-mode.dat"

# Reguły celują w selektor "desc:<opis>" (albo nazwę złącza w starych
# generacjach) — dopasowanie jak w Hyprlandzie: nazwa równa albo
# "desc:"+opis zaczyna się od selektora. Patrz lib/monitor-id.sh.
selector_is_connected() {
    local sel="$1" d
    if [[ "$sel" == desc:* ]]; then
        for d in "${connected_desc[@]}"; do
            [[ "desc:$d" == "$sel"* ]] && return 0
        done
        return 1
    fi
    [[ -n "${connected[$sel]:-}" ]]
}

# Tryb shared (globalne workspace'y 1-10): dekady-sieroty nie istnieją,
# demon jest zbędny. Sprawdzane też w merge_orphans, żeby żywy demon
# z poprzedniej sesji stał się bezczynny po zmianie trybu bez re-loginu.
ws_mode_is_shared() {
    [[ -f "$WS_MODE_DAT" && "$(<"$WS_MODE_DAT")" == "shared" ]]
}

merge_orphans() {
    ws_mode_is_shared && return 0
    [[ -f "$WS_MON_CONF" ]] || return 0

    # Podłączone (aktywne) monitory — hyprctl monitors pomija wyłączone.
    # Nazwy i opisy (EDID) — reguły mogą celować w jedno albo drugie.
    local -A connected=()
    local -A desc_of=()
    local -a connected_desc=()
    local name="" line
    while IFS= read -r line; do
        case "$line" in
            'Monitor '*)
                name="${line#Monitor }"
                name="${name%% *}"
                [[ -n "$name" ]] && connected["$name"]=1
                ;;
            *'description: '*)
                connected_desc+=("${line#*description: }")
                [[ -n "$name" ]] && desc_of["$name"]="${line#*description: }"
                ;;
        esac
    done < <(hyprctl monitors 2>/dev/null)
    # hyprctl nie odpowiada / zero monitorów — nie ruszaj niczego
    ((${#connected[@]})) || return 0

    # Reguły przypięcia: hl.workspace_rule({ workspace = "<id>", monitor = "<nazwa>", ... })
    # → sieroty (monitor odpięty) + baza dekady pierwszego żywego monitora.
    local -a orphan_ids=()
    local -A ruled=()          # id → selektor monitora z reguły
    local -A decade_base=()    # nazwa żywego monitora → baza jego dekady (min id - 1)
    local min_alive="" id mon n
    while IFS=$'\t' read -r id mon; do
        ruled["$id"]="$mon"
        if selector_is_connected "$mon"; then
            [[ -z "$min_alive" || "$id" -lt "$min_alive" ]] && min_alive=$id
            for n in "${!connected[@]}"; do
                if [[ "$mon" == desc:* ]]; then
                    [[ "desc:${desc_of[$n]:-}" == "$mon"* ]] || continue
                else
                    [[ "$mon" == "$n" ]] || continue
                fi
                [[ -z "${decade_base[$n]:-}" || $((id - 1)) -lt "${decade_base[$n]}" ]] && decade_base["$n"]=$((id - 1))
            done
        else
            orphan_ids+=("$id")
        fi
    done < <(sed -n 's/^hl\.workspace_rule({ workspace = "\([0-9]\+\)", monitor = "\([^"]\+\)".*$/\1\t\2/p' "$WS_MON_CONF")

    local base=0
    [[ -n "$min_alive" ]] && base=$((min_alive - 1))

    # Istniejące workspace'y (puste sieroty Hyprland ubija sam — pomijamy je)
    # + monitor, na którym każdy leży (dla workspace'ów bez reguły).
    local -A existing=()
    local -A ws_monitor=()
    while IFS=$'\t' read -r id mon; do
        existing["$id"]=1
        ws_monitor["$id"]="$mon"
    done < <(hyprctl workspaces 2>/dev/null | sed -n 's/^workspace ID \(-\?[0-9]\+\) ([^)]*) on monitor \([^:]*\):.*$/\1\t\2/p')

    # Workspace'y BEZ reguły (poza wszystkimi dekadami, np. 21/22) na monitorze,
    # który MA dekadę → scal do tej dekady. Docelowy id niesiemy jako parę
    # "id:target" — reszta pętli używa jednego kodu przenoszenia.
    local -a merges=()
    for id in "${!existing[@]}"; do
        [[ "$id" =~ ^[0-9]+$ && "$id" -gt 0 ]] || continue     # specjalne (ujemne) pomijamy
        [[ -z "${ruled[$id]:-}" ]] || continue
        mon="${ws_monitor[$id]:-}"
        [[ -n "$mon" && -n "${decade_base[$mon]:-}" ]] || continue
        # ${...} zamiast decade_base[$mon] w $(( )): w kontekście arytmetycznym
        # bash liczy indeks "HDMI-A-3" jako HDMI - A - 3 (klucz "-3" → 0)
        merges+=("$id:$((${decade_base[$mon]} + (id - 1) % 10 + 1))")
    done
    for id in "${orphan_ids[@]}"; do
        [[ -n "${existing[$id]:-}" ]] || continue
        merges+=("$id:$((base + (id - 1) % 10 + 1))")
    done
    ((${#merges[@]})) || return 0

    local clients active
    clients=$(hyprctl clients 2>/dev/null)
    active=$(hyprctl activeworkspace 2>/dev/null | sed -n 's/^workspace ID \(-\?[0-9]\+\).*$/\1/p')

    # Okna sieroty → odpowiednik w żywej dekadzie (11→1, 13→3; odwrotnie 2→12);
    # workspace bez reguły → dekada swojego monitora (21 na HDMI 11-20 → 11).
    local from target addr ws pair
    for pair in "${merges[@]}"; do
        from="${pair%%:*}"
        target="${pair##*:}"
        [[ "$from" -ne "$target" ]] || continue
        addr=""
        while IFS= read -r line; do
            case "$line" in
                'Window '*' -> '*)
                    addr="${line#Window }"
                    addr="${addr%% *}"
                    ;;
                $'\t'"workspace: "*)
                    ws="${line#*workspace: }"
                    ws="${ws%% *}"
                    if [[ "$ws" == "$from" && -n "$addr" ]]; then
                        hyprctl dispatch movetoworkspacesilent "$target,address:0x$addr" >/dev/null 2>&1
                    fi
                    ;;
            esac
        done <<<"$clients"
        # Fokus stał na sierocie → przeskocz na cel (opróżniony sierota ginie).
        if [[ "$active" == "$from" ]]; then
            hyprctl dispatch workspace "$target" >/dev/null 2>&1
            active=$target
        fi
    done
}

# Tryb jednorazowy (testy / ręczne sprzątanie) — bez demona i bez locka.
if [[ "${1:-}" == "--sweep" ]]; then
    merge_orphans
    exit 0
fi

# Tryb shared — nie stawiaj demona w ogóle (bez locka i nasłuchu socket2).
ws_mode_is_shared && exit 0

# Jedna instancja demona na sesję.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/archenemy-workspace-guard.lock" || exit 0
flock -n 9 || exit 0

# exec-once startuje razem z kompozytorem — poczekaj aż hyprctl odpowiada.
for _ in $(seq 1 50); do
    hyprctl monitors &>/dev/null && break
    sleep 0.2
done

# Sprzątanie na starcie (restart guarda, reload — stan mógł zdążyć się popsuć).
merge_orphans

SOCK="${XDG_RUNTIME_DIR:-}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"

# Po scaleniu zdrenuj linie zakolejkowane w trakcie pracy: własne echa
# dispatchy guarda (movetoworkspacesilent → movewindowv2) i duplikaty v1
# re-triggerowały scalanie po każdym scaleniu. Jeśli w drenażu przyszedł
# świeży event monitora, zrób JEDNO powtórne scalenie — mógł zajść realny
# unplug, gdy pracowaliśmy.
drain_and_remerge() {
    local l monitor_event=""
    while IFS= read -r -t 0.1 l; do
        case "$l" in
            'monitorremoved'*|'configreloaded'*) monitor_event=1 ;;
        esac
    done
    if [[ -n "$monitor_event" ]]; then
        sleep 0.5
        merge_orphans
    fi
}

if command -v socat >/dev/null 2>&1 && [[ -S "$SOCK" ]]; then
    # Zdarzeniowo: monitorremoved = fizyczne odpięcie,
    # configreloaded = np. monitor disable po hyprctl reload.
    # createworkspace/movewindow = sierota potrafi powstać też BEZ odpinania
    # (scroll/klik/przeniesienie okna poza dekadę żywego monitora) — scal ją
    # od razu przy utworzeniu, zanim użytkownik zobaczy podwójną "1".
    # Dopasowujemy TYLKO warianty v2 (Hyprland emituje każdy event podwójnie:
    # v1+v2 — wzorzec 'createworkspace'* łapał oba i scalał dwukrotnie);
    # configreloaded nie ma wariantu v2.
    socat -U - "UNIX-CONNECT:$SOCK" 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            'monitorremovedv2>>'*|'configreloaded'*)
                sleep 0.5   # daj Hyprlandowi domknąć przenoszenie workspace'ów
                merge_orphans
                drain_and_remerge
                ;;
            'createworkspacev2>>'*|'movewindowv2>>'*)
                sleep 0.2   # okno podążające za createworkspace musi zdążyć wylądować
                merge_orphans
                drain_and_remerge
                ;;
        esac
    done
else
    # Awaryjnie (brak socat / socketa): sonda co 2 s. Zdarzeniowo jest lepiej —
    # sonda scala z opóźnieniem, więc widać "przeskakujące" okna. Daj znać.
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -u low "archenemy" "workspace-guard: brak socat — działam sondą co 2 s (szybciej: sudo pacman -S socat i przeloguj)."
    # Kontrola żywotności: po śmierci Hyprlanda hyprctl przestaje odpowiadać —
    # bez wyjścia martwy demon trzymałby flock w XDG_RUNTIME_DIR i głodził
    # guarda następnej sesji (tryb socat kończy się sam na EOF socketa).
    fails=0
    while sleep 2; do
        if hyprctl monitors &>/dev/null; then
            fails=0
            merge_orphans
        else
            fails=$((fails + 1))
            (( fails >= 5 )) && exit 0
        fi
    done
fi
