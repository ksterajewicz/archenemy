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
#   Numeracja (r) zmienia tylko numery i workspace'y, nigdy pozycji ekranów.
#
#   Układ w przestrzeni: pozycja to lewy górny róg w pikselach LOGICZNYCH, czyli
#   po skali i obrocie (wiki Hyprlanda, „Positioning”). Monitory nie mogą na siebie
#   nachodzić, bo Hyprland takiego nie zarejestruje, więc odmawiamy już przy pytaniu.
#   Stąd kolejność pytań: tryb, skala, dopiero pozycja.
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

# Rozdzielczości monitora, bez powtórzeń, w kolejności Hyprlanda (malejąco).
live_resolutions() { live_modes "$1" | cut -d@ -f1 | awk '!seen[$0]++'; }

# Odświeżania dla rozdzielczości, od najwyższego.
live_rates() { live_modes "$1" | awk -F@ -v r="$2" '$1 == r { print $2 }' | sort -rn; }

live_transform() {
    hyprctl monitors 2>/dev/null | awk -v m="Monitor $1 (ID " '
        index($0, m) == 1 { on = 1; next }
        /^Monitor /       { on = 0 }
        on && /^[ \t]*transform: / { print $2; exit }'
}

# Rozmiar logiczny "szer wys": piksele przez skalę, obrót o 90° zamienia boki.
# `hyprctl monitors` drukuje skalę z dwiema cyframi ("\tscale: {:.2f}"), a Hyprland
# trzyma wielokrotność 1/120, która dzieli rozdzielczość bez reszty (Monitor.cpp,
# applyMonitorRule: od round(skala * 120) w górę i w dół). Liczymy tak samo, inaczej
# panel 2560 przy 1.33 wychodzi na 1925 zamiast 1920 i styk 1920x0 uchodzi za
# nakładanie, a `r N` zostawia szczelinę (zgłoszenie 2026-11-13).
logical_size() {
    awk -v m="$1" -v s="$2" -v t="${3:-0}" '
        function whole(v) { v -= int(v + 0.5); return v > -0.000001 && v < 0.000001 }
        function fits(k) { return k > 0 && (a[1] * 120) % k == 0 && (a[2] * 120) % k == 0 }
        BEGIN {
        split(m, a, "x")
        if (s <= 0) s = 1
        w = a[1] / s; h = a[2] / s
        if (!whole(w) || !whole(h)) {
            k0 = int(s * 120 + 0.5)
            for (i = 0; i < 90 && !k; i++) {
                if (fits(k0 + i)) k = k0 + i
                else if (fits(k0 - i)) k = k0 - i
            }
            if (k) { w = a[1] * 120 / k; h = a[2] * 120 / k }
        }
        if (t % 2) { x = w; w = h; h = x }
        printf "%d %d\n", w + 0.5, h + 0.5 }'
}

# Skale, które dzielą rozdzielczość bez reszty; inne Hyprland poprawia po swojemu.
clean_scales() {
    awk -v m="$1" 'BEGIN {
        split(m, a, "x")
        n = split("1/1 5/4 4/3 3/2 8/5 5/3 7/4 2/1 9/4 5/2 3/1", f, " ")
        for (i = 1; i <= n; i++) {
            split(f[i], p, "/")
            if ((a[1] * p[2]) % p[1] || (a[2] * p[2]) % p[1]) continue
            v = sprintf("%.5f", p[1] / p[2]); sub(/0+$/, "", v); sub(/\.$/, "", v)
            o = o (o == "" ? "" : ", ") v
        }
        print o }'
}

# Podłączone monitory z numerami z listy menu, w pikselach logicznych.
declare -a ROW_NUM=() ROW_NAME=() ROW_DAT=() ROW_X=() ROW_Y=() ROW_W=() ROW_H=() ROW_RES=()
add_row() {
    local num="$1" name="$2" dat="$3" mode hz pos scale w h
    read -r mode hz pos scale <<<"$(live_state "$name")"
    [[ -n "$mode" && "$pos" =~ ^(-?[0-9]+)x(-?[0-9]+)$ ]] || return 0
    local x="${BASH_REMATCH[1]}" y="${BASH_REMATCH[2]}"
    read -r w h <<<"$(logical_size "$mode" "$scale" "$(live_transform "$name")")"
    ROW_NUM+=("$num"); ROW_NAME+=("$name"); ROW_DAT+=("$dat"); ROW_RES+=("$mode")
    ROW_X+=("$x"); ROW_Y+=("$y"); ROW_W+=("$w"); ROW_H+=("$h")
}
load_layout() {
    local i name
    ROW_NUM=(); ROW_NAME=(); ROW_DAT=(); ROW_X=(); ROW_Y=(); ROW_W=(); ROW_H=(); ROW_RES=()
    for i in "${!DATS[@]}"; do
        name="$(monitor_live_name "$(monitor_selector_from_dat "${DATS[$i]}")")"
        [[ -z "$name" ]] || add_row "$((i + 1))" "$name" "${DATS[$i]}"
    done
    for i in "${!NEW_MONS[@]}"; do
        add_row "$((i + 1 + ${#DATS[@]}))" "${NEW_MONS[$i]}" ""
    done
}

row_of() {
    local i
    for i in "${!ROW_NUM[@]}"; do
        [[ "${ROW_NUM[$i]}" == "$1" ]] && { printf '%s' "$i"; return 0; }
    done
    return 1
}

# Mapa monitorów w terminalu: proporcje układu, nie dokładna skala.
print_map() {
    ((${#ROW_NUM[@]})) || return 0
    local i cols
    cols="$(tput cols 2>/dev/null)"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    (( cols > 62 )) && cols=62
    for i in "${!ROW_NUM[@]}"; do
        printf '%s %s %s %s %s %s %s\n' "${ROW_NUM[$i]}" "${ROW_NAME[$i]}" \
            "${ROW_X[$i]}" "${ROW_Y[$i]}" "${ROW_W[$i]}" "${ROW_H[$i]}" "${ROW_RES[$i]}"
    done | awk -v cols="$((cols - 6))" '
        function put(r, c, s) { cell[r, c] = s; if (r > mr) mr = r; if (c > mc) mc = c }
        function text(r, c, s, width,    k) {
            for (k = 1; k <= length(s) && k <= width; k++) put(r, c + k - 1, substr(s, k, 1))
        }
        { n++; num[n] = $1; name[n] = $2; x[n] = $3; y[n] = $4; w[n] = $5; h[n] = $6; res[n] = $7
          if (n == 1 || $3 < lx) lx = $3
          if (n == 1 || $4 < ty) ty = $4
          if ($3 + $5 > rx) rx = $3 + $5
          if ($4 + $6 > by) by = $4 + $6
          if (n == 1 || $5 < minw) minw = $5
          if (n == 1 || $6 < minh) minh = $6 }
        END {
            # Skala liczona od najmniejszego ekranu, żeby każdy zmieścił podpis. Zaokrąglenie
            # wspólne dla krawędzi, więc stykające się monitory stykają się na mapie.
            sx = minw / 26; if ((rx - lx) / sx > cols) sx = (rx - lx) / cols
            if (minw / sx < 14) sx = minw / 14
            sy = minh / 5
            for (i = 1; i <= n; i++) {
                c0 = int((x[i] - lx) / sx + 0.5); c1 = int((x[i] + w[i] - lx) / sx + 0.5) - 1
                r0 = int((y[i] - ty) / sy + 0.5); r1 = int((y[i] + h[i] - ty) / sy + 0.5) - 1
                for (c = c0; c <= c1; c++) { put(r0, c, "─"); put(r1, c, "─") }
                for (r = r0; r <= r1; r++) { put(r, c0, "│"); put(r, c1, "│") }
                put(r0, c0, "┌"); put(r0, c1, "┐"); put(r1, c0, "└"); put(r1, c1, "┘")
                for (r = r0 + 1; r < r1; r++) for (c = c0 + 1; c < c1; c++) put(r, c, " ")
                text(r0 + 1, c0 + 2, num[i] " " name[i], c1 - c0 - 3)
                text(r0 + 2, c0 + 2, res[i], c1 - c0 - 3)
            }
            for (r = 0; r <= mr; r++) {
                line = "    "
                for (c = 0; c <= mc; c++) line = line (((r, c) in cell) ? cell[r, c] : " ")
                sub(/ +$/, "", line); print line
            }
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

# Czy numery (kolejność DATS) idą od lewej wg zapisanych pozycji. Kod 0 = tak.
order_follows_layout() {
    local want="" have="" list="" f pos
    for f in "${DATS[@]}"; do
        pos="$(monitor_dat_get "$f" POSITION)"
        # Pozycja auto: nie wiemy, co jest po lewej, więc nie ma o czym mówić.
        [[ "$pos" =~ ^(-?[0-9]+)x ]] || return 0
        want+="$(basename "$f" .dat)"$'\n'
        list+="${BASH_REMATCH[1]}"$'\t'"$(basename "$f" .dat)"$'\n'
    done
    have="$(sort -n -s -k1,1 <<<"$list" | sed '/^$/d' | cut -f2)"$'\n'
    [[ "$have" == "$want" ]]
}

# Numery monitorów mają iść od lewej. Zmiana pozycji może to rozjechać, a nowa
# numeracja przenosi workspace'y, więc o niej mówimy, nie robimy jej sami.
warn_if_order_changed() {
    order_follows_layout && return 0
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
    local name="$1" dat="$2" regen="$3" errors rc
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
    # Sukces to stan odczytany z Hyprlanda, także dla sąsiadów przesuniętych razem
    # z monitorem. Rozjazd nie dostaje zielonego ✓ nawet po klawiszu y.
    local differs=0 move
    if ! state_matches "$name" "$dat"; then
        differs=1
        echo -e "  ${YELLOW}⚠ Hyprland shows something else: $(live_state "$name")${NC}"
        echo -e "  ${YELLOW}  (mode, Hz, position, scale; it may have adjusted a value it rejected).${NC}"
    fi
    for move in "${MOVES[@]}"; do
        state_matches "${move##*|}" "${move%%|*}" && continue
        differs=1
        echo -e "  ${YELLOW}⚠ ${move##*|} did not move: Hyprland shows $(live_state "${move##*|}")${NC}"
    done
    echo -e "  ${CYAN}Look at the screen.${NC} Press ${GREEN}y${NC} within ${CONFIRM_SECONDS} s to keep it; Esc, No or timeout goes back."
    if TUI_MENU_TIMEOUT="$CONFIRM_SECONDS" confirm "Keep this monitor setting?" N; then
        PENDING=0; cleanup
        if (( differs )); then
            echo -e "  ${YELLOW}⚠ Saved, but Hyprland shows ${name}: $(live_state "$name")${NC}"
            echo -e "  ${YELLOW}  The saved setting and the screen differ; run hyprctl configerrors to see why.${NC}"
        else
            echo -e "  ${GREEN}✓ Monitor ${name}: $(live_state "$name")${NC}"
        fi
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
    local move target
    for move in "${MOVES[@]}"; do
        target="${move#*|}"
        monitor_dat_set "${move%%|*}" POSITION "${target%|*}"
        echo -e "  ${CYAN}${target#*|} moves to ${target%|*} to stay attached.${NC}"
    done
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
    local k n ok seen line
    local -a picks=() reordered=()
    mapfile -t ORDER_PICK < <(proposed_order)
    ((${#ORDER_PICK[@]} > 1)) || return 0
    while :; do
        echo -e "  Numbers run left to right:"
        for k in "${!ORDER_PICK[@]}"; do
            printf "    ${BLUE}%d${NC}) %-10s position %s\n" "$((k + 1))" \
                "$(monitor_dat_get "${ORDER_PICK[$k]}" MONITOR)" "$(monitor_dat_get "${ORDER_PICK[$k]}" POSITION)"
        done
        if [[ -t 0 ]]; then
            pick_order_menu || return 1
            return 0
        fi
        IFS= read -rp "  Enter = accept, or your own order, e.g. 2 1: " line || return 1
        if [[ "$line" == *$'\e'* || "$line" == j* || "$line" == k* || "${line,,}" == [ac] ]]; then
            pick_order_menu "$line" || return 1
            return 0
        fi
        read -ra picks <<<"$line"
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

# Wybór monitora dla każdego kolejnego numeru, bez wpisywania permutacji. Etykieta
# mówi o numerach: „position” brzmiało jak układ ekranów w przestrzeni, a to menu
# zmienia tylko numery i workspace'y (zgłoszenie 2026-11-13).
pick_order_menu() {
    local first="${1:-}" i
    local -a labels=() remaining=("${ORDER_PICK[@]}") chosen=() TUI_MENU_KEYS=(a c)
    if [[ -n "$first" ]]; then
        tui_menu 0 "Accept proposed order [a]" "Choose each number [c]" <<<"$first" || return 1
    else
        tui_menu 0 "Accept proposed order [a]" "Choose each number [c]" || return 1
    fi
    (( TUI_MENU_INDEX != 0 )) || return 0
    TUI_MENU_KEYS=()
    while ((${#remaining[@]})); do
        echo "  Pick monitor number $((${#chosen[@]} + 1)):"
        labels=()
        for i in "${remaining[@]}"; do labels+=("$(monitor_dat_get "$i" MONITOR)"); done
        tui_menu_lines 0 "${labels[@]}" || return 1
        chosen+=("${remaining[$TUI_MENU_INDEX]}")
        unset 'remaining[TUI_MENU_INDEX]'
        remaining=("${remaining[@]}")
    done
    ORDER_PICK=("${chosen[@]}")
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
    # Numery to nie układ: kolejność inna niż od lewej nie przestawia ekranów.
    load_dats
    if ! order_follows_layout; then
        echo -e "  ${YELLOW}⚠ Only the numbers changed, the screens did not move. To change which screen is on${NC}"
        echo -e "  ${YELLOW}  which side, pick a monitor from the list and set its Position (l 2 = left of 2).${NC}"
    fi
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
    local cur="$1" self="$2" w="$3" h="$4" old_w="${5:-$3}" old_h="${6:-$4}" i dir x y hit n
    MOVES=()
    echo -e "  Position: ${BLUE}XxY${NC} in logical pixels, ${BLUE}auto${NC}, or next to a monitor from the list:"
    echo -e "  ${BLUE}l 2${NC} left of 2, ${BLUE}r 2${NC} right of 2, ${BLUE}a 2${NC} above 2, ${BLUE}b 2${NC} below 2."
    while :; do
        read -rp "  Position [$cur]: " ASK_POS || return 1
        ASK_POS="$(trim "${ASK_POS:-$cur}")"
        if [[ "$ASK_POS" =~ ^([lrab])[[:space:]]*([0-9]+)$ ]]; then
            dir="${BASH_REMATCH[1]}"
            if [[ "${BASH_REMATCH[2]}" == "$self" ]] || ! i="$(row_of "${BASH_REMATCH[2]}")"; then
                echo -e "  ${RED}✗ Pick another connected monitor from the list.${NC}"
                continue
            fi
            case "$dir" in
                l) ASK_POS="$(( ROW_X[i] - w ))x${ROW_Y[i]}" ;;
                r) ASK_POS="$(( ROW_X[i] + ROW_W[i] ))x${ROW_Y[i]}" ;;
                a) ASK_POS="${ROW_X[i]}x$(( ROW_Y[i] - h ))" ;;
                b) ASK_POS="${ROW_X[i]}x$(( ROW_Y[i] + ROW_H[i] ))" ;;
            esac
            echo -e "  ${CYAN}→ ${ASK_POS}${NC}"
        fi
        [[ "$ASK_POS" == "auto" ]] && return 0
        if [[ ! "$ASK_POS" =~ ^(-?[0-9]+)x(-?[0-9]+)$ ]]; then
            echo -e "  ${RED}✗ Use XxY, e.g. 1920x0, auto, or l/r/a/b with a number.${NC}"
            continue
        fi
        x="${BASH_REMATCH[1]}"; y="${BASH_REMATCH[2]}"
        # Pozycja bez zmian przy innym rozmiarze: sąsiedzi idą za krawędzią.
        [[ "$ASK_POS" == "$cur" ]] && neighbours_follow "$self" "$x" "$y" "$old_w" "$old_h" "$w" "$h"
        hit=""
        for i in "${!ROW_NUM[@]}"; do
            [[ "${ROW_NUM[$i]}" == "$self" ]] && continue
            if (( x < ROW_X[i] + ROW_W[i] && x + w > ROW_X[i] && y < ROW_Y[i] + ROW_H[i] && y + h > ROW_Y[i] )); then
                hit="${ROW_NAME[$i]}"; n="${ROW_NUM[$i]}"
                break
            fi
        done
        [[ -n "$hit" ]] || return 0
        # Sama odmowa zostawiała bez wyjścia kogoś, kto chce zamienić ekrany stronami:
        # miejsce docelowe zawsze zajmuje ten drugi. Mówimy, którą formą to zrobić.
        echo -e "  ${RED}✗ That overlaps ${hit} (${ROW_W[$i]}x${ROW_H[$i]} at ${ROW_X[$i]}x${ROW_Y[$i]}), and Hyprland would not register it.${NC}"
        echo -e "  ${YELLOW}  To change sides put this monitor beside it: l ${n}, r ${n}, a ${n} or b ${n}. Or move ${hit} first.${NC}"
        MOVES=()
        load_layout
    done
}

# Sąsiedzi przyklejeni do prawej i dolnej krawędzi zmienianego monitora przesuwają
# się razem z nią, także łańcuchem. Inaczej zmiana rozdzielczości zostawia nakładkę
# albo przerwę. Pozycja `auto` należy do Hyprlanda, tej nie ruszamy.
# Wynik: wiersze przesunięte w ROW_X/ROW_Y, MOVES = "<plik .dat>|<XxY>|<nazwa>".
declare -a MOVES=()
neighbours_follow() {
    local self="$1" x="$2" y="$3" old_w="$4" old_h="$5" w="$6" h="$7" i edge pass=1
    local dx=$(( w - old_w )) dy=$(( h - old_h ))
    local -a edges=()
    local -A moved=()
    (( dx || dy )) || return 0
    if (( dx )); then
        edges=("$(( x + old_w ))")
        while (( pass )); do
            pass=0
            for i in "${!ROW_NUM[@]}"; do
                [[ "${ROW_NUM[$i]}" == "$self" || -n "${moved[$i]:-}" ]] && continue
                for edge in "${edges[@]}"; do
                    (( ROW_X[i] == edge )) || continue
                    edges+=("$(( ROW_X[i] + ROW_W[i] ))")
                    ROW_X[i]=$(( ROW_X[i] + dx ))
                    moved[$i]=1; pass=1
                    break
                done
            done
        done
    fi
    if (( dy )); then
        edges=("$(( y + old_h ))"); pass=1
        local -A moved_y=()
        while (( pass )); do
            pass=0
            for i in "${!ROW_NUM[@]}"; do
                [[ "${ROW_NUM[$i]}" == "$self" || -n "${moved_y[$i]:-}" ]] && continue
                for edge in "${edges[@]}"; do
                    (( ROW_Y[i] == edge )) || continue
                    edges+=("$(( ROW_Y[i] + ROW_H[i] ))")
                    ROW_Y[i]=$(( ROW_Y[i] + dy ))
                    moved[$i]=1; moved_y[$i]=1; pass=1
                    break
                done
            done
        done
    fi
    for i in "${!moved[@]}"; do
        [[ -n "${ROW_DAT[$i]}" && "$(monitor_dat_get "${ROW_DAT[$i]}" POSITION)" != "auto" ]] || continue
        MOVES+=("${ROW_DAT[$i]}|${ROW_X[$i]}x${ROW_Y[$i]}|${ROW_NAME[$i]}")
    done
}

ask_scale() {
    local clean=""
    [[ -z "${2:-}" ]] || clean="$(clean_scales "$2")"
    [[ -z "$clean" ]] || echo -e "  Clean scales for $2: ${CYAN}${clean}${NC}"
    while :; do
        read -rp "  Scale [$1]: " ASK_SCALE || return 1
        ASK_SCALE="$(trim "${ASK_SCALE:-$1}")"
        # `auto` z instalatora zostaje, gdy Enter; liczba musi być dodatnia.
        [[ "$ASK_SCALE" == "$1" ]] && return 0
        [[ "$ASK_SCALE" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v s="$ASK_SCALE" 'BEGIN { exit !(s > 0) }' && return 0
        echo -e "  ${RED}✗ Use a positive number.${NC}"
    done
}

# Rozmiar logiczny po zmianie. Tryby preferred/highres/highrr i skala auto: nie znamy
# wyniku z góry, więc liczymy z tego, co Hyprland pokazuje teraz.
# Wynik: NEW_W, NEW_H.
NEW_W=0
NEW_H=0
new_logical_size() {
    local name="$1" res="$2" scale="$3" mode hz pos live_scale
    read -r mode hz pos live_scale <<<"$(live_state "$name")"
    [[ "$res" =~ ^[0-9]+x[0-9]+$ ]] || res="$mode"
    [[ "$scale" =~ ^[0-9.]+$ ]] || scale="$live_scale"
    read -r NEW_W NEW_H <<<"$(logical_size "$res" "$scale" "$(live_transform "$name")")"
}

add_monitor() {
    local name="$1" num="$2" mode hz pos scale res rate role def_role desc dat f
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
    pick_mode "$name" "$res" || return 1
    split_picked_mode
    ask_scale "$scale" "$res" || return 1
    scale="$ASK_SCALE"
    new_logical_size "$name" "$res" "$scale"
    ask_position "$pos" "$num" "$NEW_W" "$NEW_H" || return 1
    pos="$ASK_POS"
    MOVES=()
    def_role="$(default_role)"
    while :; do
        local initial=0
        local -a roles=(primary secondary other) TUI_MENU_KEYS=(primary secondary other)
        case "$def_role" in secondary) initial=1 ;; other) initial=2 ;; esac
        echo "  Wallpaper role [${def_role}]:"
        if [[ -t 0 ]]; then
            tui_menu "$initial" "${roles[@]}" || return 1
            role="${roles[$TUI_MENU_INDEX]}"
        else
            IFS= read -r role || return 1
            role="$(trim "${role:-$def_role}")"
            if [[ "$role" == *$'\e'* || "$role" == j* || "$role" == k* || "$role" =~ ^[1-3]$ ]]; then
                tui_menu "$initial" "${roles[@]}" <<<"$role" || return 1
                role="${roles[$TUI_MENU_INDEX]}"
            fi
        fi
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
    if [[ -t 0 ]]; then
        confirm "Forget ${name}? Its number and workspaces go away" N || return 0
    else
        IFS= read -r ans || return 1
        confirm "Forget ${name}? Its number and workspaces go away" N <<<"$ans" || return 0
    fi

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

# Numer z listy albo Enter. Wynik: zmienna PICK (pusto = Enter). Kod 1 = koniec wejścia.
PICK=""
pick_number() {
    local prompt="$1" max="$2" extra="${3:-}" i rc
    local -a labels=("${GRID[@]}") TUI_MENU_KEYS=()
    PICK=""
    for (( i=0; i<max; i++ )); do TUI_MENU_KEYS+=(""); done
    for (( i=0; i<${#extra}; i++ )); do
        case "${extra:i:1}" in
            p) labels+=("monitor's preferred [p]") ;;
            h) labels+=("highest resolution [h]") ;;
            f) labels+=("highest refresh rate [f]") ;;
        esac
        TUI_MENU_KEYS+=("${extra:i:1}")
    done
    labels+=("keep current setting")
    while :; do
        echo "$prompt"
        rc=0
        tui_menu_lines "$((${#labels[@]} - 1))" "${labels[@]}" || rc=$?
        (( rc != 1 )) || { [[ "${TUI_MENU_CANCELLED:-0}" == 1 ]] && return 1; return 0; }
        if (( rc == 2 )); then
            echo -e "  ${RED}✗ Pick a number from the list.${NC}"
            continue
        fi
        if (( TUI_MENU_INDEX < max )); then
            PICK=$((TUI_MENU_INDEX + 1))
        elif (( TUI_MENU_INDEX < max + ${#extra} )); then
            PICK="${extra:TUI_MENU_INDEX-max:1}"
        fi
        return 0
    done
}

print_grid() {
    local i
    for i in "${!GRID[@]}"; do
        printf "  ${BLUE}%3d${NC}) %-14s" "$((i + 1))" "${GRID[$i]}"
        (( (i + 1) % 3 == 0 )) && echo ""
    done
    (( ${#GRID[@]} % 3 == 0 )) || echo ""
}

# Najpierw rozdzielczość, potem odświeżanie dla niej. Argumenty: nazwa, obecna
# rozdzielczość. Wynik: PICKED_MODE (WxH@Hz albo słowo Hyprlanda), pusto = bez zmian.
PICKED_MODE=""
declare -a GRID=()
pick_mode() {
    local name="$1" cur="$2" res
    PICKED_MODE=""
    mapfile -t GRID < <(live_resolutions "$name")
    if ((${#GRID[@]} == 0)); then
        echo -e "  ${YELLOW}⚠ Hyprland lists no modes for ${name}, keeping the current one.${NC}"
        return 0
    fi
    local -a ress=("${GRID[@]}")
    echo ""
    echo -e "  Resolution, now ${CYAN}${cur}${NC}:"
    [[ -t 0 ]] || print_grid
    echo -e "    ${BLUE}p${NC}) monitor's preferred   ${BLUE}h${NC}) highest resolution   ${BLUE}f${NC}) highest refresh rate"
    pick_number "  Resolution number (Enter = keep): " "${#ress[@]}" phf || return 1
    case "$PICK" in
        p) PICKED_MODE="preferred"; return 0 ;;
        h) PICKED_MODE="highres"; return 0 ;;
        f) PICKED_MODE="highrr"; return 0 ;;
        "") res="$cur" ;;
        *) res="${ress[$((PICK - 1))]}" ;;
    esac

    mapfile -t GRID < <(live_rates "$name" "$res")
    # Tryb bez listy odświeżania (preferred/highres/highrr, rozdzielczość spoza listy
    # Hyprlanda) zostaje. Kod MUSI być 0: gołe `return` oddawało 1 z nieudanego testu
    # i cały dialog kończył się bez słowa, zanim padło pytanie o skalę i pozycję.
    ((${#GRID[@]})) || return 0
    if ((${#GRID[@]} == 1)); then
        [[ "$res" == "$cur" ]] || PICKED_MODE="$res@${GRID[0]}"
        return 0
    fi
    local -a rates=("${GRID[@]}")
    echo ""
    echo -e "  Refresh rate for ${CYAN}${res}${NC}, Hz:"
    [[ -t 0 ]] || print_grid
    if [[ "$res" == "$cur" ]]; then
        pick_number "  Rate number (Enter = keep): " "${#rates[@]}" || return 1
        [[ -n "$PICK" ]] && PICKED_MODE="$res@${rates[$((PICK - 1))]}"
    else
        pick_number "  Rate number (Enter = ${rates[0]}): " "${#rates[@]}" || return 1
        PICKED_MODE="$res@${rates[$((${PICK:-1} - 1))]}"
    fi
    return 0
}

# PICKED_MODE do zmiennych res i rate wołającego. Słowa typu preferred nie mają @.
split_picked_mode() {
    [[ -n "$PICKED_MODE" ]] || return 0
    res="${PICKED_MODE%%@*}"
    rate=""
    [[ "$PICKED_MODE" != *@* ]] || rate="${PICKED_MODE#*@}"
}

edit_monitor() {
    local dat="$1" num="$2" name sel live res rate pos scale new_pos new_scale
    sel="$(monitor_selector_from_dat "$dat")"
    live="$(monitor_live_name "$sel")"
    name="$(monitor_dat_get "$dat" MONITOR)"
    if [[ -z "$live" ]]; then
        echo -e "  ${RED}✗ ${name} is not connected, so a change could not be checked.${NC}"
        forget_monitor "$dat"
        return "$?"
    fi
    res="$(monitor_dat_get "$dat" RESOLUTION)"; rate="$(monitor_dat_get "$dat" RATE)"
    pos="$(monitor_dat_get "$dat" POSITION)"; scale="$(monitor_dat_get "$dat" SCALE)"

    pick_mode "$live" "$res" || return 1
    split_picked_mode

    ask_scale "$scale" "$res" || return 1
    new_scale="$ASK_SCALE"

    new_logical_size "$live" "$res" "$new_scale"
    local row old_w="" old_h=""
    if row="$(row_of "$num")"; then old_w="${ROW_W[$row]}"; old_h="${ROW_H[$row]}"; fi
    ask_position "$pos" "$num" "$NEW_W" "$NEW_H" "$old_w" "$old_h" || return 1
    new_pos="$ASK_POS"

    if [[ "$res" == "$(monitor_dat_get "$dat" RESOLUTION)" && "$rate" == "$(monitor_dat_get "$dat" RATE)" \
        && "$new_pos" == "$pos" && "$new_scale" == "$scale" ]]; then
        echo -e "  ${YELLOW}Nothing changed.${NC}"
        return 0
    fi
    apply_change "$dat" "$live" "$res" "$rate" "$new_pos" "$new_scale"
}

menu() {
    local ans total hint="Monitor number" rc i
    local -a labels=() TUI_MENU_KEYS=()
    load_dats
    mapfile -t NEW_MONS < <(new_monitors)
    clear
    tui_header "monitors"
    if ((${#DATS[@]} == 0)); then
        echo -e "  ${RED}✗ No monitor data in ${MON_DIR} — run ./install/install.sh first.${NC}"
    else
        print_monitors
        load_layout
        echo ""
        print_map
        echo ""
        total=$(( ${#DATS[@]} + ${#NEW_MONS[@]} ))
        ((${#DATS[@]} < 2)) || hint+=", r = renumber left to right"
        for i in "${!DATS[@]}"; do
            labels+=("$(monitor_dat_get "${DATS[$i]}" MONITOR) — $(dat_mode "${DATS[$i]}")")
            TUI_MENU_KEYS+=("")
        done
        for i in "${NEW_MONS[@]}"; do labels+=("$i — new, pick to set up"); TUI_MENU_KEYS+=(""); done
        if ((${#DATS[@]} >= 2)); then
            labels+=("renumber left to right [r]"); TUI_MENU_KEYS+=(r)
        fi
        echo "  ${hint} (Esc = back):"
        rc=0
        tui_menu_lines 0 "${labels[@]}" || rc=$?
        (( rc != 1 )) || return 0
        ans=$(( TUI_MENU_INDEX + 1 ))
        if (( rc == 2 )); then ans="invalid"
        elif (( TUI_MENU_INDEX == total )); then ans=r
        fi
        if [[ "$ans" == "r" ]]; then
            renumber_monitors
        elif [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#DATS[@]} )); then
            edit_monitor "${DATS[$((ans - 1))]}" "$ans"
        elif [[ "$ans" =~ ^[0-9]+$ ]] && (( ans > ${#DATS[@]} && ans <= total )); then
            add_monitor "${NEW_MONS[$((ans - 1 - ${#DATS[@]}))]}" "$ans"
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
