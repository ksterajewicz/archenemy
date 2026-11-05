#!/bin/bash

# =============================================
#   archenemy - monitor-settings.sh
#   Rozdzielczość, odświeżanie, pozycja i skala monitora na żywo: jedyna droga
#   dla Super+A → [n], bez ponownego biegu install.sh.
#   UI po angielsku (kontekst Super+A — decyzja właściciela 2026-07-12).
#
#   Zapis do data/monitors/<nazwa>.dat, regeneracja monitorshyprl.lua
#   (lib/gen-monitors.sh, to samo źródło co install.sh), reload, odczyt stanu
#   z `hyprctl monitors`.
#
#   Zmiana wchodzi NA PRÓBĘ: zły tryb może dać czarny ekran, więc bez klawisza
#   `y` w ciągu CONFIRM_SECONDS wraca poprzedni stan. Zamknięcie okna (SIGHUP)
#   też cofa. Numer monitora (ORDER) i rola zostają bez zmian: numerację L→P
#   ustala install.sh [3.6], od niej zależą workspace'y.
#
#   Użycie: monitor-settings.sh           menu
#           monitor-settings.sh summary   skrót dla menu głównego
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
MON_DIR="$ARCHENEMY_DIR/data/monitors"
MON_CONF="$ARCHENEMY_DIR/config/hypr/monitorshyprl.lua"
CONFIRM_SECONDS=15

# shellcheck source=/dev/null
source "$ARCHENEMY_DIR/scripts/appbinds/lib/tui.sh"
# shellcheck source=lib/monitor-id.sh
source "$ARCHENEMY_DIR/scripts/hypr/lib/monitor-id.sh"
# shellcheck source=lib/gen-monitors.sh
source "$ARCHENEMY_DIR/scripts/hypr/lib/gen-monitors.sh"
# shellcheck source=lib/hypr-apply.sh
source "$ARCHENEMY_DIR/scripts/hypr/lib/hypr-apply.sh"

declare -a DATS=()
load_dats() { mapfile -t DATS < <(monitor_dats_sorted "$MON_DIR"); }

# Tryb w zapisie .dat: rozdzielczość albo rozdzielczość@odświeżanie.
dat_mode() {
    local res rate
    res="$(monitor_dat_get "$1" RESOLUTION)"; rate="$(monitor_dat_get "$1" RATE)"
    printf '%s%s' "$res" "${rate:+@$rate}"
}

# Linia stanu monitora z `hyprctl monitors`: "<WxH> <Hz> <XxY> <skala>".
# Format: src/ipc/s1/Commands.cpp, "\t{}x{}@{:.5f} at {}x{}" i "\tscale: {}".
live_state() {
    hyprctl monitors 2>/dev/null | awk -v m="Monitor $1 (ID " '
        index($0, m) == 1 { on = 1; next }
        /^Monitor /       { on = 0 }
        on && $2 == "at" && $1 ~ /^[0-9]+x[0-9]+@/ { split($1, a, "@"); mode = a[1]; hz = a[2]; pos = $3 }
        on && /^[ \t]*scale: / { print mode, hz, pos, $2; exit }'
}

# Tryby monitora, po jednym w linii, bez powtórzeń, w kolejności Hyprlanda.
live_modes() {
    hyprctl monitors 2>/dev/null | awk -v m="Monitor $1 (ID " '
        index($0, m) == 1 { on = 1; next }
        /^Monitor /       { on = 0 }
        on && /availableModes:/ {
            for (i = 2; i <= NF; i++) { sub(/Hz$/, "", $i); if (!seen[$i]++) print $i }
            exit
        }'
}

# Czy Hyprland pokazuje to, co zapisaliśmy. Kod 0 = tak. Argumenty: nazwa, plik .dat.
# Tryby preferred/highres/highrr i pozycja auto: decyduje Hyprland, nie ma z czym
# porównać. Monitor może przełączać tryb chwilę po reloadzie, stąd kilka odczytów.
state_matches() {
    local name="$1" dat="$2" res rate pos scale mode hz lpos lscale _i
    res="$(monitor_dat_get "$dat" RESOLUTION)"; rate="$(monitor_dat_get "$dat" RATE)"
    pos="$(monitor_dat_get "$dat" POSITION)"; scale="$(monitor_dat_get "$dat" SCALE)"
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        read -r mode hz lpos lscale <<<"$(live_state "$name")"
        if [[ ! "$res" =~ ^[0-9]+x[0-9]+$ || "$res" == "$mode" ]] \
            && [[ "$pos" == "auto" || "$pos" == "$lpos" ]] \
            && awk -v a="${rate:-$hz}" -v b="${hz:-0}" -v s="$scale" -v t="${lscale:-0}" \
                'function d(x, y) { return x > y ? x - y : y - x }
                 BEGIN { exit !(d(a, b) < 0.6 && (s == "auto" || d(s, t) < 0.005)) }'; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

# Zapis pól do .dat: tmp + mv, inne pola (ORDER, ROLE, DESCRIPTION) bez zmian.
write_monitor_dat() {
    local dat="$1" res="$2" rate="$3" pos="$4" scale="$5" tmp
    tmp="$(mktemp "${dat}.XXXXXX")" || return 1
    sed -e "s|^RESOLUTION=.*|RESOLUTION=$res|" -e "s|^RATE=.*|RATE=$rate|" \
        -e "s|^POSITION=.*|POSITION=$pos|" -e "s|^SCALE=.*|SCALE=$scale|" "$dat" > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$dat"
}

# ─── PRÓBA I COFNIĘCIE ───────────────────────────────────────────────────────

BACKUP_DIR=""
PENDING_DAT=""

rollback() {
    [[ -n "$PENDING_DAT" ]] || return 0
    cp -p "$BACKUP_DIR/dat" "$PENDING_DAT"
    cp -p "$BACKUP_DIR/lua" "$MON_CONF"
    PENDING_DAT=""
    hypr_reload_checked >/dev/null
}

cleanup() { [[ -z "$BACKUP_DIR" ]] || rm -rf "$BACKUP_DIR"; BACKUP_DIR=""; }
trap 'rollback; cleanup; exit 129' HUP
trap 'rollback; cleanup; exit 143' TERM
trap 'rollback; cleanup; exit 130' INT
trap 'rollback; cleanup' EXIT

# Numery monitorów mają iść od lewej. Pozycja może to rozjechać, a numerację
# zmienia install.sh [3.6], więc tylko o tym mówimy.
warn_if_order_changed() {
    local want="" have="" list="" f pos
    for f in "${DATS[@]}"; do
        pos="$(monitor_dat_get "$f" POSITION)"
        # Pozycja auto: nie wiemy, co jest po lewej, więc nie ma o czym mówić.
        [[ "$pos" =~ ^(-?[0-9]+)x ]] || return 0
        want+="$(basename "$f" .dat)"$'\n'
        list+="${BASH_REMATCH[1]}"$'\t'"$(basename "$f" .dat)"$'\n'
    done
    have="$(sort -n -s -k1,1 <<<"$list" | sed '/^$/d' | cut -f2)"$'\n'
    [[ "$have" == "$want" ]] && return 0
    echo -e "  ${YELLOW}⚠ Monitor numbers no longer run left to right. Workspaces keep the old${NC}"
    echo -e "  ${YELLOW}  numbering; ./install/install.sh step [3.6] renumbers them.${NC}"
}

# Kod 0 = zapisane, 1 = cofnięte albo nieudane.
apply_change() {
    local dat="$1" name="$2" res="$3" rate="$4" pos="$5" scale="$6" errors rc key="" old_res
    old_res="$(monitor_dat_get "$dat" RESOLUTION)"
    BACKUP_DIR="$(mktemp -d)" || { echo -e "  ${RED}✗ mktemp failed.${NC}"; return 1; }
    cp -p "$dat" "$BACKUP_DIR/dat"
    cp -p "$MON_CONF" "$BACKUP_DIR/lua" 2>/dev/null || : > "$BACKUP_DIR/lua"

    PENDING_DAT="$dat"
    write_monitor_dat "$dat" "$res" "$rate" "$pos" "$scale" \
        && generate_monitors_conf "$MON_CONF" "$MON_DIR" \
        || { rollback; cleanup; echo -e "  ${RED}✗ Could not write the monitor config.${NC}"; return 1; }

    errors="$(hypr_reload_checked)"; rc=$?
    case $rc in
        0) ;;
        2) rollback; cleanup
           echo -e "  ${RED}✗ Hyprland reports a config error, change undone:${NC}"
           printf '    %s\n' "$errors" | head -5
           return 1 ;;
        3) PENDING_DAT=""; cleanup
           echo -e "  ${YELLOW}⚠ No Hyprland session — saved, applies when Hyprland starts.${NC}"
           return 0 ;;
        *) rollback; cleanup
           echo -e "  ${YELLOW}⚠ Hyprland did not respond — change undone.${NC}"
           return 1 ;;
    esac

    if ! state_matches "$name" "$dat"; then
        echo -e "  ${YELLOW}⚠ Hyprland shows something else: $(live_state "$name")${NC}"
        echo -e "  ${YELLOW}  (mode, Hz, position, scale; it may have adjusted a value it rejected).${NC}"
    fi
    echo -e "  ${CYAN}Look at the screen.${NC} Press ${GREEN}y${NC} within ${CONFIRM_SECONDS} s to keep it; anything else goes back."
    IFS= read -rsn1 -t "$CONFIRM_SECONDS" key
    if [[ "$key" == "y" || "$key" == "Y" ]]; then
        PENDING_DAT=""; cleanup
        echo -e "  ${GREEN}✓ Monitor ${name}: $(live_state "$name")${NC}"
        warn_if_order_changed
        [[ "$res" == "$old_res" ]] \
            || echo -e "  ${YELLOW}  dither-flux wallpapers match the old resolution until ./install/install.sh runs.${NC}"
        return 0
    fi
    rollback; cleanup
    echo -e "  ${YELLOW}↩ Back to the previous setting.${NC}"
    return 1
}

# ─── MENU ────────────────────────────────────────────────────────────────────

print_monitors() {
    local i dat name live
    for i in "${!DATS[@]}"; do
        dat="${DATS[$i]}"
        name="$(monitor_dat_get "$dat" MONITOR)"
        live="$(monitor_live_name "$(monitor_selector_from_dat "$dat")")"
        printf "    ${BLUE}%d${NC}) %-10s %s at %s, scale %s" "$((i + 1))" "${live:-$name}" \
            "$(dat_mode "$dat")" "$(monitor_dat_get "$dat" POSITION)" "$(monitor_dat_get "$dat" SCALE)"
        [[ -n "$live" ]] || printf "  ${YELLOW}(not connected)${NC}"
        echo ""
    done
}

# Wynik: zmienna PICKED_MODE (WxH@Hz) albo pusto, gdy zostaje obecny.
PICKED_MODE=""
pick_mode() {
    local name="$1" i ans
    local -a modes=()
    PICKED_MODE=""
    mapfile -t modes < <(live_modes "$name")
    if ((${#modes[@]} == 0)); then
        echo -e "  ${YELLOW}⚠ Hyprland lists no modes for ${name}, keeping the current one.${NC}"
        return
    fi
    echo ""
    for i in "${!modes[@]}"; do
        printf "  ${BLUE}%3d${NC}) %-22s" "$((i + 1))" "${modes[$i]}"
        (( (i + 1) % 3 == 0 )) && echo ""
    done
    (( ${#modes[@]} % 3 == 0 )) || echo ""
    echo ""
    while :; do
        read -rp "  Mode number (Enter = keep): " ans || return
        ans="$(trim "$ans")"
        [[ -z "$ans" ]] && return
        if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#modes[@]} )); then
            PICKED_MODE="${modes[$((ans - 1))]}"
            return
        fi
        echo -e "  ${RED}✗ Pick a number from the list.${NC}"
    done
}

edit_monitor() {
    local dat="$1" name sel live res rate pos scale new_pos new_scale
    sel="$(monitor_selector_from_dat "$dat")"
    live="$(monitor_live_name "$sel")"
    name="$(monitor_dat_get "$dat" MONITOR)"
    if [[ -z "$live" ]]; then
        echo -e "  ${RED}✗ ${name} is not connected, so a change could not be checked.${NC}"
        return 1
    fi
    res="$(monitor_dat_get "$dat" RESOLUTION)"; rate="$(monitor_dat_get "$dat" RATE)"
    pos="$(monitor_dat_get "$dat" POSITION)"; scale="$(monitor_dat_get "$dat" SCALE)"

    pick_mode "$live"
    if [[ -n "$PICKED_MODE" ]]; then
        res="${PICKED_MODE%%@*}"; rate="${PICKED_MODE#*@}"
    fi

    while :; do
        read -rp "  Position XxY or auto [${pos}]: " new_pos || return 1
        new_pos="$(trim "${new_pos:-$pos}")"
        [[ "$new_pos" =~ ^-?[0-9]+x-?[0-9]+$ || "$new_pos" == "auto" ]] && break
        echo -e "  ${RED}✗ Use XxY, e.g. 1920x0, or auto.${NC}"
    done
    while :; do
        read -rp "  Scale, e.g. 1, 1.25, 1.5, 2 [${scale}]: " new_scale || return 1
        new_scale="$(trim "${new_scale:-$scale}")"
        # `auto` z instalatora zostaje, gdy Enter; liczba musi być dodatnia.
        [[ "$new_scale" == "$scale" ]] && break
        [[ "$new_scale" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v s="$new_scale" 'BEGIN { exit !(s > 0) }' && break
        echo -e "  ${RED}✗ Use a positive number.${NC}"
    done

    if [[ "$res" == "$(monitor_dat_get "$dat" RESOLUTION)" && "$rate" == "$(monitor_dat_get "$dat" RATE)" \
        && "$new_pos" == "$pos" && "$new_scale" == "$scale" ]]; then
        echo -e "  ${YELLOW}Nothing changed.${NC}"
        return 0
    fi
    apply_change "$dat" "$live" "$res" "$rate" "$new_pos" "$new_scale"
}

menu() {
    local ans
    load_dats
    clear
    echo -e "${BLUE}"
    echo "  ┌─────────────────────────────────────┐"
    echo "  │        archenemy · monitors         │"
    echo "  └─────────────────────────────────────┘"
    echo -e "${NC}"
    if ((${#DATS[@]} == 0)); then
        echo -e "  ${RED}✗ No monitor data in ${MON_DIR} — run ./install/install.sh first.${NC}"
    else
        print_monitors
        echo ""
        read -rp "  Monitor number (Enter = back): " ans
        ans="$(trim "$ans")"
        [[ -z "$ans" ]] && return 0
        if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#DATS[@]} )); then
            edit_monitor "${DATS[$((ans - 1))]}"
        else
            echo -e "  ${RED}✗ There is no monitor number '${ans}'.${NC}"
        fi
    fi
    echo ""
    read -rp "  Press Enter to go back..." _
}

case "${1:-}" in
    summary)
        load_dats
        if ((${#DATS[@]} == 1)); then
            printf '%s' "$(dat_mode "${DATS[0]}")"
        else
            printf '%d screens' "${#DATS[@]}"
        fi
        ;;
    "") menu ;;
    *) echo "usage: monitor-settings.sh [summary]" >&2; exit 1 ;;
esac
