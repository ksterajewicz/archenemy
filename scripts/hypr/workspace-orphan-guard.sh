#!/bin/bash

# =============================================
#   archenemy - workspace-orphan-guard.sh
#   Demon (exec-once ze wspólnego workspaces.conf).
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
#   Rozwiązanie: po zdarzeniach socket2 (monitorremoved,
#   configreloaded, createworkspace, movewindow) guard scala
#   osierocone workspace'y — okna z 10N+i trafiają na
#   odpowiednik "i" w dekadzie pierwszego podłączonego monitora,
#   pusty sierota znika sam (nie jest persistent). Podpięcie
#   monitora z powrotem obsługuje sam Hyprland (reguły
#   workspace = N, monitor:X działają przy connect).
#
#   Reguły przypięcia czyta z generowanego (maszynowego)
#   workspaces-monitors.conf — patrz install.sh [8b].
#   Wywołanie ręczne: workspace-orphan-guard.sh --sweep
#   (jednorazowe sprzątanie, bez demona).
# =============================================

set -uo pipefail

WS_MON_CONF="$HOME/archenemy/config/hypr/workspaces-monitors.conf"
WS_MODE_DAT="$HOME/archenemy/data/workspace-mode.dat"

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
    local -A connected=()
    local name
    while IFS= read -r name; do
        [[ -n "$name" ]] && connected["$name"]=1
    done < <(hyprctl monitors 2>/dev/null | sed -n 's/^Monitor \(\S\+\) (ID [0-9]\+):$/\1/p')
    # hyprctl nie odpowiada / zero monitorów — nie ruszaj niczego
    ((${#connected[@]})) || return 0

    # Reguły przypięcia: "workspace = <id>, monitor:<nazwa>, ..." →
    # sieroty (monitor odpięty) + baza dekady pierwszego żywego monitora.
    local -a orphan_ids=()
    local min_alive="" id mon
    while read -r id mon; do
        if [[ -n "${connected[$mon]:-}" ]]; then
            [[ -z "$min_alive" || "$id" -lt "$min_alive" ]] && min_alive=$id
        else
            orphan_ids+=("$id")
        fi
    done < <(sed -n 's/^workspace = \([0-9]\+\), monitor:\([^,]\+\).*$/\1 \2/p' "$WS_MON_CONF")
    ((${#orphan_ids[@]})) || return 0

    local base=0
    [[ -n "$min_alive" ]] && base=$((min_alive - 1))

    # Istniejące workspace'y (puste sieroty Hyprland ubija sam — pomijamy je).
    local -A existing=()
    while IFS= read -r id; do existing["$id"]=1; done \
        < <(hyprctl workspaces 2>/dev/null | sed -n 's/^workspace ID \(-\?[0-9]\+\).*$/\1/p')

    local clients active
    clients=$(hyprctl clients 2>/dev/null)
    active=$(hyprctl activeworkspace 2>/dev/null | sed -n 's/^workspace ID \(-\?[0-9]\+\).*$/\1/p')

    # Okna sieroty → odpowiednik w żywej dekadzie (11→1, 13→3; odwrotnie 2→12).
    local from target addr ws line
    for from in "${orphan_ids[@]}"; do
        [[ -n "${existing[$from]:-}" ]] || continue
        target=$((base + (from - 1) % 10 + 1))
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
