#!/bin/bash

# =============================================
#   archenemy - monitor-settings.sh
#   Monitory na żywo: jedyna droga dla Super+A → [n], bez ponownego biegu
#   install.sh. Zmiana trybu, pozycji i skali, dodanie nowego monitora, zmiana
#   numeracji, usunięcie odpiętego. UI po angielsku (kontekst Super+A — decyzja
#   właściciela 2026-07-12).
#
#   Zapis do data/monitors/*.dat, regeneracja monitorshyprl.lua i przy zmianie
#   układu workspaces-monitors.lua (te same generatory co install.sh), reload,
#   odczyt stanu z `hyprctl monitors`.
#
#   Zmiana wchodzi NA PRÓBĘ: zły tryb może dać czarny ekran, więc bez klawisza
#   `y` w ciągu CONFIRM_SECONDS wraca poprzedni stan. Zamknięcie okna (SIGHUP)
#   też cofa. Kopia obejmuje cały data/monitors i oba pliki Lua, bo dodanie
#   monitora rusza numery i opisy także w istniejących plikach .dat.
#
#   Plik .dat nosi nazwę złącza z dnia zapisu, a ta bywa zajęta przez odpięty
#   monitor, więc nowy dostaje wtedy sufiks (HDMI-A-1-2.dat). Prawdziwa nazwa
#   jest w MONITOR=.
#
#   Użycie: monitor-settings.sh           menu
#           monitor-settings.sh summary   skrót dla listy menu głównego
#           monitor-settings.sh brief     monitory do podglądu w menu głównym
#           monitor-settings.sh notify    powiadomienie o nowym monitorze
#                                         (hl.on("monitor.added"), autostart-common.lua)
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
MON_DIR="$ARCHENEMY_DIR/data/monitors"
MON_CONF="$ARCHENEMY_DIR/config/hypr/monitorshyprl.lua"
WS_CONF="$ARCHENEMY_DIR/config/hypr/workspaces-monitors.lua"
MODE_DAT="$ARCHENEMY_DIR/data/workspace-mode.dat"
CONFIRM_SECONDS=15

# shellcheck source=/dev/null
source "$ARCHENEMY_DIR/scripts/appbinds/lib/tui.sh"
# shellcheck source=lib/monitor-id.sh
source "$ARCHENEMY_DIR/scripts/hypr/lib/monitor-id.sh"
# shellcheck source=lib/gen-monitors.sh
source "$ARCHENEMY_DIR/scripts/hypr/lib/gen-monitors.sh"
# shellcheck source=lib/gen-workspaces.sh
source "$ARCHENEMY_DIR/scripts/hypr/lib/gen-workspaces.sh"
# shellcheck source=lib/hypr-apply.sh
source "$ARCHENEMY_DIR/scripts/hypr/lib/hypr-apply.sh"

declare -a DATS=() NEW_MONS=()
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

# Opis monitora z pól make/model/serial, jak install.sh [3]. Pusto = nieużyteczny.
live_short_desc() {
    local line on=0 make="" model="" serial=""
    while IFS= read -r line; do
        case "$line" in
            "Monitor $1 (ID "*) on=1; continue ;;
            'Monitor '*) on=0 ;;
        esac
        (( on )) || continue
        if [[ "$line" =~ ^[[:space:]]*make:[[:space:]]*(.*)$ ]]; then make="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*model:[[:space:]]*(.*)$ ]]; then model="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*serial:[[:space:]]*(.*)$ ]]; then serial="${BASH_REMATCH[1]}"
        fi
    done < <(hyprctl monitors 2>/dev/null)
    monitor_short_desc "$make" "$model" "$serial"
}

# Podłączone monitory, których nie obejmuje żaden .dat. Monitor przepięty do innego
# gniazda ma ten sam opis EDID, więc nie jest nowy.
new_monitors() {
    local -A known=()
    local f live name
    for f in "$MON_DIR"/*.dat; do
        [[ -e "$f" ]] || continue
        live="$(monitor_live_name "$(monitor_selector_from_dat "$f")")"
        [[ -n "$live" ]] && known[$live]=1
    done
    while IFS= read -r name; do
        [[ -z "$name" || -n "${known[$name]:-}" ]] || printf '%s\n' "$name"
    done < <(hyprctl monitors 2>/dev/null | sed -n 's/^Monitor \([^ ]*\) (ID .*/\1/p')
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

# Jedno pole w .dat, tmp + mv. Pola brakującego dopisujemy na końcu.
monitor_dat_set() {
    local dat="$1" key="$2" value="$3" tmp
    tmp="$(mktemp "${dat}.XXXXXX")" || return 1
    if grep -q "^$key=" "$dat"; then
        awk -v k="$key" -v v="$value" 'index($0, k "=") == 1 { print k "=" v; next } { print }' "$dat" > "$tmp"
    else
        { cat "$dat"; printf '%s=%s\n' "$key" "$value"; } > "$tmp"
    fi
    chmod 644 "$tmp"
    mv "$tmp" "$dat"
}

# Reguły workspace'ów dla bieżącego trybu, ten sam generator co install.sh [8b].
regen_workspaces() {
    local mode="decades" tmp
    local -a entries=()
    [[ -f "$MODE_DAT" ]] && mode="$(<"$MODE_DAT")"
    mapfile -t entries < <(monitor_entries_ordered "$MON_DIR")
    ((${#entries[@]})) || return 1
    tmp="$(mktemp "${WS_CONF}.XXXXXX")" || return 1
    if ! generate_workspaces_monitors "$tmp" "$mode" "${entries[@]}"; then
        rm -f "$tmp"
        return 1
    fi
    chmod 644 "$tmp"
    mv "$tmp" "$WS_CONF"
}

# ─── PRÓBA I COFNIĘCIE ───────────────────────────────────────────────────────

BACKUP_DIR=""
PENDING=0

backup_state() {
    BACKUP_DIR="$(mktemp -d)" || { echo -e "  ${RED}✗ mktemp failed.${NC}"; return 1; }
    mkdir "$BACKUP_DIR/monitors"
    cp -p "$MON_DIR"/*.dat "$BACKUP_DIR/monitors/" 2>/dev/null
    cp -p "$MON_CONF" "$BACKUP_DIR/lua" 2>/dev/null || : > "$BACKUP_DIR/lua"
    cp -p "$WS_CONF" "$BACKUP_DIR/ws" 2>/dev/null
    PENDING=1
}

# Najpierw kopiowanie, potem usuwanie nowych plików: przerwanie w trakcie nie
# zostawi pustego katalogu.
rollback() {
    (( PENDING )) || return 0
    local f
    cp -p "$BACKUP_DIR/monitors/"*.dat "$MON_DIR/" 2>/dev/null
    for f in "$MON_DIR"/*.dat; do
        [[ -e "$BACKUP_DIR/monitors/$(basename "$f")" ]] || rm -f "$f"
    done
    cp -p "$BACKUP_DIR/lua" "$MON_CONF"
    if [[ -f "$BACKUP_DIR/ws" ]]; then cp -p "$BACKUP_DIR/ws" "$WS_CONF"; else rm -f "$WS_CONF"; fi
    PENDING=0
    hypr_reload_checked >/dev/null
}

cleanup() { [[ -z "$BACKUP_DIR" ]] || rm -rf "$BACKUP_DIR"; BACKUP_DIR=""; }
trap 'rollback; cleanup; exit 129' HUP
trap 'rollback; cleanup; exit 143' TERM
trap 'rollback; cleanup; exit 130' INT
trap 'rollback; cleanup' EXIT

# Numery monitorów mają iść od lewej. Zmiana pozycji może to rozjechać, a nowa
# numeracja przenosi workspace'y, więc o niej mówimy, nie robimy jej sami.
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
    echo -e "  ${YELLOW}  numbering; press r in this menu to renumber them.${NC}"
}

# Tapety dither-flux pod nową rozdzielczość, w tle. Nic nie blokuje.
refresh_dither_flux() {
    local gen="$ARCHENEMY_DIR/scripts/wallpapers/gen_dither_flux_wallpaper.py"
    local out="$ARCHENEMY_DIR/wallpapers/dither-flux/generated"
    local lib="$ARCHENEMY_DIR/scripts/wallpapers/lib/dither-flux-sizes.sh"
    if [[ ! -f "$gen" || ! -f "$lib" ]] || ! command -v python3 >/dev/null 2>&1; then
        echo -e "  ${YELLOW}  dither-flux wallpapers keep the old size: python3 or the generator is missing.${NC}"
        return 0
    fi
    # shellcheck source=/dev/null
    source "$lib"
    dither_flux_plan "$MON_DIR" "$out"
    ((${#FLUX_SIZES[@]})) || return 0
    dither_flux_start "$gen" "$out"
    echo -e "  ${CYAN}  dither-flux wallpapers for this size are being generated in the background.${NC}"
}

# Po zmianie układu: tapety i workspace'y za nim nadążają. Bez sesji nie ma czego
# odświeżać, pliki wejdą przy następnym starcie Hyprlanda.
after_layout_change() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
    local script mode="decades"
    [[ -f "$MODE_DAT" ]] && mode="$(<"$MODE_DAT")"
    script="$ARCHENEMY_DIR/scripts/rofi/rofi_wallpaper_switcher.sh"
    [[ -f "$script" ]] && bash "$script" --restore >/dev/null 2>&1
    script="$ARCHENEMY_DIR/scripts/hypr/workspace-orphan-guard.sh"
    [[ -f "$script" ]] && bash "$script" --rehome >/dev/null 2>&1
    [[ "$mode" == "shared" ]] && echo -e "  ${CYAN}  Open windows keep their workspaces; new rules apply to new ones.${NC}"
}

# Generatory, reload, odczyt, potwierdzenie. Argumenty: nazwa żywego monitora (pusto
# = bez próby, np. usunięcie odpiętego), plik .dat do sprawdzenia, 1 = także
# workspace'y. Kod 0 = zapisane, 1 = cofnięte albo nieudane.
commit_change() {
    local name="$1" dat="$2" regen="$3" errors rc key=""
    if ! generate_monitors_conf "$MON_CONF" "$MON_DIR" \
        || { (( regen )) && ! regen_workspaces; }; then
        rollback; cleanup
        echo -e "  ${RED}✗ Could not write the monitor config.${NC}"
        return 1
    fi

    errors="$(hypr_reload_checked)"; rc=$?
    case $rc in
        0) ;;
        2) rollback; cleanup
           echo -e "  ${RED}✗ Hyprland reports a config error, change undone:${NC}"
           printf '    %s\n' "$errors" | head -5
           return 1 ;;
        3) PENDING=0; cleanup
           echo -e "  ${YELLOW}⚠ No Hyprland session — saved, applies when Hyprland starts.${NC}"
           return 0 ;;
        *) rollback; cleanup
           echo -e "  ${YELLOW}⚠ Hyprland did not respond — change undone.${NC}"
           return 1 ;;
    esac

    if [[ -z "$name" ]]; then
        PENDING=0; cleanup
        return 0
    fi
    # Monitor odpięty w trakcie: nie ma czego oglądać ani potwierdzać.
    if [[ -z "$(live_state "$name")" ]]; then
        rollback; cleanup
        echo -e "  ${YELLOW}⚠ ${name} is gone, change undone.${NC}"
        return 1
    fi
    if ! state_matches "$name" "$dat"; then
        echo -e "  ${YELLOW}⚠ Hyprland shows something else: $(live_state "$name")${NC}"
        echo -e "  ${YELLOW}  (mode, Hz, position, scale; it may have adjusted a value it rejected).${NC}"
    fi
    echo -e "  ${CYAN}Look at the screen.${NC} Press ${GREEN}y${NC} within ${CONFIRM_SECONDS} s to keep it; anything else goes back."
    IFS= read -rsn1 -t "$CONFIRM_SECONDS" key
    if [[ "$key" == "y" || "$key" == "Y" ]]; then
        PENDING=0; cleanup
        echo -e "  ${GREEN}✓ Monitor ${name}: $(live_state "$name")${NC}"
        return 0
    fi
    rollback; cleanup
    echo -e "  ${YELLOW}↩ Back to the previous setting.${NC}"
    return 1
}

# Kod 0 = zapisane, 1 = cofnięte albo nieudane.
apply_change() {
    local dat="$1" name="$2" res="$3" rate="$4" pos="$5" scale="$6" old_res
    old_res="$(monitor_dat_get "$dat" RESOLUTION)"
    backup_state || return 1
    if ! write_monitor_dat "$dat" "$res" "$rate" "$pos" "$scale"; then
        rollback; cleanup
        echo -e "  ${RED}✗ Could not write the monitor config.${NC}"
        return 1
    fi
    commit_change "$name" "$dat" 0 || return 1
    warn_if_order_changed
    [[ "$res" == "$old_res" ]] || refresh_dither_flux
}

# ─── NUMERACJA ───────────────────────────────────────────────────────────────

# Propozycja jak install.sh [3.6]: pozycja X rosnąco, pozycja auto na końcu.
proposed_order() {
    local f pos
    for f in "${DATS[@]}"; do
        pos="$(monitor_dat_get "$f" POSITION)"
        [[ "$pos" =~ ^(-?[0-9]+)x ]] && printf '%s\t%s\n' "${BASH_REMATCH[1]}" "$f"
    done | sort -n -s -k1,1 | cut -f2-
    for f in "${DATS[@]}"; do
        pos="$(monitor_dat_get "$f" POSITION)"
        [[ "$pos" =~ ^-?[0-9]+x ]] || printf '%s\n' "$f"
    done
}

# Wynik: tablica ORDER_PICK, pliki .dat w kolejności numerów. Kod 1 = koniec wejścia.
declare -a ORDER_PICK=()
pick_order() {
    local k n ok seen
    local -a picks=() reordered=()
    mapfile -t ORDER_PICK < <(proposed_order)
    ((${#ORDER_PICK[@]} > 1)) || return 0
    while :; do
        echo -e "  Numbers run left to right:"
        for k in "${!ORDER_PICK[@]}"; do
            printf "    ${BLUE}%d${NC}) %-10s position %s\n" "$((k + 1))" \
                "$(monitor_dat_get "${ORDER_PICK[$k]}" MONITOR)" "$(monitor_dat_get "${ORDER_PICK[$k]}" POSITION)"
        done
        read -rp "  Enter = accept, or your own order, e.g. 2 1: " -a picks || return 1
        ((${#picks[@]} > 0)) || return 0
        ok=1; seen=" "
        ((${#picks[@]} == ${#ORDER_PICK[@]})) || ok=0
        for n in "${picks[@]}"; do
            if [[ ! "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#ORDER_PICK[@]} )) || [[ "$seen" == *" $n "* ]]; then
                ok=0
            fi
            seen+="$n "
        done
        if (( ok )); then
            reordered=()
            for n in "${picks[@]}"; do reordered+=("${ORDER_PICK[$((n - 1))]}"); done
            ORDER_PICK=("${reordered[@]}")
            return 0
        fi
        echo -e "  ${RED}✗ Use each number from the list once.${NC}"
    done
}

write_order() {
    local f k=1
    for f in "${ORDER_PICK[@]}"; do
        monitor_dat_set "$f" ORDER "$k"
        k=$((k + 1))
    done
}

renumber_monitors() {
    if ((${#DATS[@]} < 2)); then
        echo -e "  ${YELLOW}One monitor, nothing to renumber.${NC}"
        return 0
    fi
    pick_order || return 1
    if [[ "${ORDER_PICK[*]}" == "${DATS[*]}" ]]; then
        echo -e "  ${YELLOW}Nothing changed.${NC}"
        return 0
    fi
    backup_state || return 1
    write_order
    commit_change "" "" 1 || return 1
    echo -e "  ${GREEN}✓ Monitor numbers updated.${NC}"
    after_layout_change
}

# ─── NOWY MONITOR ────────────────────────────────────────────────────────────

# Nazwa pliku wolna także wtedy, gdy złącze zajmuje wpis odpiętego monitora.
free_dat_path() {
    local path="$MON_DIR/$1.dat" n=2
    while [[ -e "$path" ]]; do
        path="$MON_DIR/$1-$n.dat"
        n=$((n + 1))
    done
    printf '%s\n' "$path"
}

# Rola, której jeszcze nikt nie ma: primary, potem secondary, potem other.
default_role() {
    local f roles=" "
    for f in "${DATS[@]}"; do roles+="$(monitor_dat_get "$f" ROLE) "; done
    if [[ "$roles" != *" primary "* ]]; then echo primary
    elif [[ "$roles" != *" secondary "* ]]; then echo secondary
    else echo other
    fi
}

# Opis nierozróżnialny z istniejącym wpisem: oba monitory schodzą na nazwy złączy,
# jak w install.sh [3]. Wynik: zmienna NEW_DESC.
NEW_DESC=""
settle_description() {
    local f desc live new="$NEW_DESC"
    [[ -n "$new" ]] || return 0
    for f in "${DATS[@]}"; do
        desc="$(monitor_dat_get "$f" DESCRIPTION)"
        [[ -n "$desc" ]] || continue
        monitor_descs_collide "$new" "$desc" || continue
        live="$(monitor_live_name "desc:$desc")"
        monitor_dat_set "$f" DESCRIPTION ""
        [[ -n "$live" ]] && monitor_dat_set "$f" MONITOR "$live"
        echo -e "  ${YELLOW}⚠ Same EDID description as $(basename "$f" .dat): both are told apart by connector name.${NC}"
        NEW_DESC=""
    done
}

# Pytania wspólne dla zmiany i dodania. Wynik: ASK_POS, ASK_SCALE. Kod 1 = koniec wejścia.
ASK_POS=""
ASK_SCALE=""
ask_position() {
    while :; do
        read -rp "  Position XxY or auto [$1]: " ASK_POS || return 1
        ASK_POS="$(trim "${ASK_POS:-$1}")"
        [[ "$ASK_POS" =~ ^-?[0-9]+x-?[0-9]+$ || "$ASK_POS" == "auto" ]] && return 0
        echo -e "  ${RED}✗ Use XxY, e.g. 1920x0, or auto.${NC}"
    done
}
ask_scale() {
    while :; do
        read -rp "  Scale, e.g. 1, 1.25, 1.5, 2 [$1]: " ASK_SCALE || return 1
        ASK_SCALE="$(trim "${ASK_SCALE:-$1}")"
        # `auto` z instalatora zostaje, gdy Enter; liczba musi być dodatnia.
        [[ "$ASK_SCALE" == "$1" ]] && return 0
        [[ "$ASK_SCALE" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v s="$ASK_SCALE" 'BEGIN { exit !(s > 0) }' && return 0
        echo -e "  ${RED}✗ Use a positive number.${NC}"
    done
}

add_monitor() {
    local name="$1" mode hz pos scale res rate role def_role desc dat f
    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        echo -e "  ${RED}✗ No Hyprland session, so ${name} cannot be checked.${NC}"
        return 1
    fi
    read -r mode hz pos scale <<<"$(live_state "$name")"
    if [[ -z "$mode" ]]; then
        echo -e "  ${RED}✗ ${name} is gone.${NC}"
        return 1
    fi
    desc="$(live_short_desc "$name")"
    echo -e "  New monitor ${CYAN}${name}${NC}${desc:+: $desc}, now ${mode} at ${pos}, scale ${scale}"

    res="$mode"
    rate="$(LC_ALL=C printf '%.0f' "$hz")"
    pick_mode "$name"
    if [[ -n "$PICKED_MODE" ]]; then
        res="${PICKED_MODE%%@*}"; rate="${PICKED_MODE#*@}"
    fi
    ask_position "$pos" || return 1
    pos="$ASK_POS"
    ask_scale "$scale" || return 1
    scale="$ASK_SCALE"
    def_role="$(default_role)"
    while :; do
        read -rp "  Wallpaper role primary/secondary/other [${def_role}]: " role || return 1
        role="$(trim "${role:-$def_role}")"
        [[ "$role" == "primary" || "$role" == "secondary" || "$role" == "other" ]] && break
        echo -e "  ${RED}✗ Pick primary, secondary or other.${NC}"
    done

    backup_state || return 1
    NEW_DESC="$desc"
    settle_description
    # Primary jest jeden: poprzedni dostaje rolę, która wypadłaby nowemu.
    if [[ "$role" == "primary" && "$def_role" != "primary" ]]; then
        for f in "${DATS[@]}"; do
            [[ "$(monitor_dat_get "$f" ROLE)" == "primary" ]] && monitor_dat_set "$f" ROLE "$def_role"
        done
    fi
    dat="$(free_dat_path "$name")"
    printf 'MONITOR=%s\nRESOLUTION=%s\nRATE=%s\nPOSITION=%s\nSCALE=%s\nROLE=%s\nDESCRIPTION=%s\n' \
        "$name" "$res" "$rate" "$pos" "$scale" "$role" "$NEW_DESC" > "$dat"
    load_dats
    if ! pick_order; then
        rollback; cleanup
        return 1
    fi
    write_order
    load_dats
    commit_change "$name" "$dat" 1 || return 1
    after_layout_change
    refresh_dither_flux
}

# ─── USUNIĘCIE ODPIĘTEGO ─────────────────────────────────────────────────────

forget_monitor() {
    local dat="$1" name role ans f live first="" k=1
    name="$(monitor_dat_get "$dat" MONITOR)"
    if ((${#DATS[@]} < 2)); then
        echo -e "  ${YELLOW}${name} is the only saved monitor, so it stays.${NC}"
        return 0
    fi
    read -rp "  Forget ${name}? Its number and workspaces go away [y/N]: " ans || return 1
    [[ "$ans" == "y" || "$ans" == "Y" ]] || return 0

    role="$(monitor_dat_get "$dat" ROLE)"
    backup_state || return 1
    rm -f "$dat"
    load_dats
    # Numery bez dziury: w shared numer to domowy workspace.
    for f in "${DATS[@]}"; do
        monitor_dat_set "$f" ORDER "$k"
        k=$((k + 1))
    done
    # Primary przechodzi na pierwszy podłączony monitor, inaczej tapeta v1 nie ma gdzie iść.
    if [[ "$role" == "primary" ]]; then
        for f in "${DATS[@]}"; do
            live="$(monitor_live_name "$(monitor_selector_from_dat "$f")")"
            [[ -n "$first" ]] || first="$f"
            if [[ -n "$live" ]]; then first="$f"; break; fi
        done
        monitor_dat_set "$first" ROLE primary
    fi
    commit_change "" "" 1 || return 1
    echo -e "  ${GREEN}✓ ${name} forgotten.${NC}"
    after_layout_change
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
        [[ -n "$live" ]] || echo -ne "  ${YELLOW}(not connected, pick to forget)${NC}"
        echo ""
    done
    for i in "${!NEW_MONS[@]}"; do
        printf "    ${BLUE}%d${NC}) %-10s ${GREEN}new, pick to set up${NC}\n" "$((i + 1 + ${#DATS[@]}))" "${NEW_MONS[$i]}"
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
        forget_monitor "$dat"
        return
    fi
    res="$(monitor_dat_get "$dat" RESOLUTION)"; rate="$(monitor_dat_get "$dat" RATE)"
    pos="$(monitor_dat_get "$dat" POSITION)"; scale="$(monitor_dat_get "$dat" SCALE)"

    pick_mode "$live"
    if [[ -n "$PICKED_MODE" ]]; then
        res="${PICKED_MODE%%@*}"; rate="${PICKED_MODE#*@}"
    fi

    ask_position "$pos" || return 1
    new_pos="$ASK_POS"
    ask_scale "$scale" || return 1
    new_scale="$ASK_SCALE"

    if [[ "$res" == "$(monitor_dat_get "$dat" RESOLUTION)" && "$rate" == "$(monitor_dat_get "$dat" RATE)" \
        && "$new_pos" == "$pos" && "$new_scale" == "$scale" ]]; then
        echo -e "  ${YELLOW}Nothing changed.${NC}"
        return 0
    fi
    apply_change "$dat" "$live" "$res" "$rate" "$new_pos" "$new_scale"
}

menu() {
    local ans total hint="Monitor number"
    load_dats
    mapfile -t NEW_MONS < <(new_monitors)
    clear
    tui_header "monitors"
    if ((${#DATS[@]} == 0)); then
        echo -e "  ${RED}✗ No monitor data in ${MON_DIR} — run ./install/install.sh first.${NC}"
    else
        print_monitors
        echo ""
        total=$(( ${#DATS[@]} + ${#NEW_MONS[@]} ))
        ((${#DATS[@]} < 2)) || hint+=", r = renumber left to right"
        read -rp "  ${hint} (Enter = back): " ans
        ans="$(trim "$ans")"
        [[ -z "$ans" ]] && return 0
        if [[ "$ans" == "r" ]]; then
            renumber_monitors
        elif [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#DATS[@]} )); then
            edit_monitor "${DATS[$((ans - 1))]}"
        elif [[ "$ans" =~ ^[0-9]+$ ]] && (( ans > ${#DATS[@]} && ans <= total )); then
            add_monitor "${NEW_MONS[$((ans - 1 - ${#DATS[@]}))]}"
        else
            echo -e "  ${RED}✗ There is no monitor number '${ans}'.${NC}"
        fi
    fi
    echo ""
    read -rp "  Press Enter to go back..." _
}

# Powiadomienie z hl.on("monitor.added"). Na starcie sesji każdy monitor jest
# „dodany”, a o monitorze bez reguły mówi wtedy machine-layer-check.sh, więc młoda
# sesja milczy. Brak .dat = system bez install.sh, tu nie ma czego ustawiać.
notify_new() {
    local age name
    age="$(ps -o etimes= -C Hyprland 2>/dev/null | sort -n | head -1 | tr -d ' ')"
    [[ "$age" =~ ^[0-9]+$ ]] && (( age < 30 )) && return 0
    command -v notify-send >/dev/null 2>&1 || return 0
    # Opis EDID pojawia się chwilę po zdarzeniu.
    sleep 1
    load_dats
    ((${#DATS[@]})) || return 0
    while IFS= read -r name; do
        [[ -n "$name" ]] && notify-send "archenemy: new monitor" "${name}: Super+A → [n] sets it up."
    done < <(new_monitors)
}

case "${1:-}" in
    summary)
        load_dats
        mapfile -t NEW_MONS < <(new_monitors)
        if ((${#DATS[@]} == 1)); then
            printf '%s' "$(dat_mode "${DATS[0]}")"
        else
            printf '%d screens' "${#DATS[@]}"
        fi
        ((${#NEW_MONS[@]} == 0)) || printf ', %d new' "${#NEW_MONS[@]}"
        ;;
    brief)
        load_dats
        for dat in "${DATS[@]}"; do
            live="$(monitor_live_name "$(monitor_selector_from_dat "$dat")")"
            printf '%s  %s  x%s\n' "${live:-$(monitor_dat_get "$dat" MONITOR)}" "$(dat_mode "$dat")" "$(monitor_dat_get "$dat" SCALE)"
            [[ -n "$live" ]] || echo "(not connected)"
        done
        while IFS= read -r name; do
            [[ -z "$name" ]] || printf '%s  new, needs setup\n' "$name"
        done < <(new_monitors)
        ;;
    notify) notify_new ;;
    "") menu ;;
    *) echo "usage: monitor-settings.sh [summary|brief|notify]" >&2; exit 1 ;;
esac
