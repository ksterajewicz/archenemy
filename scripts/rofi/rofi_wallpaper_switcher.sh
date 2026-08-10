#!/bin/bash

# =============================================
#   archenemy - rofi_wallpaper_switcher.sh
#   Przełącznik tapet (rofi): dowolny plik z wallpapers/,
#   na monitor z fokusem albo na wszystkie monitory.
#
#   Użycie:
#     rofi_wallpaper_switcher.sh              interaktywnie (menu rofi)
#     rofi_wallpaper_switcher.sh --restore    przywróć ostatnie tapety po cichu
#     rofi_wallpaper_switcher.sh CEL          bez menu: plik (ścieżka względem
#                                             wallpapers/ albo absolutna) → wszystkie
#                                             monitory (para v1/v2 jeśli istnieje);
#                                             folder zestawu → v1=primary, v2=secondary
#
#   Menu ma na górze przełącznik "[x] Upload to all monitors" (domyślnie
#   zaznaczony). Zaznaczony: tapeta idzie na wszystkie monitory — a gdy obok
#   wybranego pliku *v1*/*v2* leży druga połowa pary, primary dostaje v1,
#   secondary v2. Odznaczony: tapeta trafia tylko na monitor z fokusem.
#
#   Drugi przełącznik "[ ] Set as hyprlock background (no blur)" (domyślnie
#   odznaczony): zaznaczony — wybrana tapeta idzie też jako `path` w
#   hyprlock-background-<rice>.conf (blur_size/blur_passes → 0, reszta pól
#   rice'a — brightness/contrast/noise/vibrancy — nietknięta). Eliminuje
#   koszt żywego zrzutu ekranu + blur przy każdym Super+L (zgłoszenie
#   właściciela: hyprlock wolny). Odznaczony — hyprlock wraca do domyślnego
#   `path = screenshot` + blur.
#
#   Stan: data/wallpaper.dat w formacie "monitor=ścieżka" (po linii na monitor).
#   Stary format (sama nazwa zestawu) jest migrowany automatycznie.
#   Stan hyprlocka: data/hyprlock-wallpaper.dat — "off" albo bezwzględna
#   ścieżka ostatnio wybranego obrazu; wczytywany też przy --restore, żeby
#   wybór właściciela przeżył przełączenie rice'a (Super+T).
# =============================================

ARCHENEMY_DIR="$HOME/archenemy"
WALLPAPERS_DIR="$ARCHENEMY_DIR/wallpapers"
DATA_DIR="$ARCHENEMY_DIR/data"
WALLPAPER_DAT="$DATA_DIR/wallpaper.dat"
HYPRLOCK_DAT="$DATA_DIR/hyprlock-wallpaper.dat"
# Warstwa maszynowa (gitignore) — rice'y linkują do tego pliku relatywnym
# symlinkiem, więc hyprpaper czyta go przez ~/.config/hypr/hyprpaper.conf.
HYPRPAPER_CONF="$ARCHENEMY_DIR/config/hypr/hyprpaper.conf"
# Warstwa maszynowa (gitignore) — każdy rice'owy hyprlock.conf source'uje
# swój plik (patrz install.sh [8h]); trzy realne rice'y, beta dziedziczy
# symlinkiem hyprlock.conf z white-blue.
HYPRLOCK_BG_FILES=(
    "$ARCHENEMY_DIR/config/hypr/hyprlock-background-white-blue.conf"
    "$ARCHENEMY_DIR/config/hypr/hyprlock-background-tron.conf"
    "$ARCHENEMY_DIR/config/hypr/hyprlock-background-asia-n-rice.conf"
)

TOGGLE_ON="[x] Upload to all monitors"
TOGGLE_OFF="[ ] Upload to all monitors"
LOCK_TOGGLE_ON="[x] Set as hyprlock background (no blur)"
LOCK_TOGGLE_OFF="[ ] Set as hyprlock background (no blur)"

# ─── RESOLVE MONITORS FROM data/monitors/*.dat ───────────────────────────────

MONITOR1=""   # primary  -> dostaje v1
MONITOR2=""   # secondary -> dostaje v2

if [[ -d "$DATA_DIR/monitors" ]]; then
    for dat in "$DATA_DIR/monitors"/*.dat; do
        [[ -f "$dat" ]] || continue
        mon=$(grep '^MONITOR='  "$dat" | cut -d= -f2)
        role=$(grep '^ROLE='    "$dat" | cut -d= -f2)
        if [[ "$role" == "primary" && -z "$MONITOR1" ]]; then
            MONITOR1="$mon"
        elif [[ -z "$MONITOR2" && "$role" != "primary" ]]; then
            MONITOR2="$mon"
        fi
    done
fi

# Fallback: pytamy hyprctl — omijając monitor zajęty już jako MONITOR2,
# żeby primary i secondary nie wskazały tego samego wyjścia.
if [[ -z "$MONITOR1" ]]; then
    mapfile -t DETECTED < <(hyprctl monitors | grep "^Monitor" | awk '{print $2}')
    for m in "${DETECTED[@]}"; do
        [[ "$m" == "$MONITOR2" ]] && continue
        MONITOR1="$m"
        break
    done
    [[ -z "$MONITOR2" && -n "${DETECTED[1]}" ]] && MONITOR2="${DETECTED[1]}"
fi

# Jedyny monitor mógł dostać rolę secondary — wtedy robi za primary.
if [[ -z "$MONITOR1" && -n "$MONITOR2" ]]; then
    MONITOR1="$MONITOR2"
    MONITOR2=""
fi

if [[ -z "$MONITOR1" ]]; then
    notify-send "archenemy" "Could not resolve any monitor. Run install.sh first."
    exit 1
fi

# ─── HELPERS ──────────────────────────────────────────────────────────────────

# Monitor z fokusem (fallback: primary, gdy hyprctl nie odpowie).
focused_monitor() {
    local m
    m=$(hyprctl monitors 2>/dev/null | awk '/^Monitor/{m=$2} /focused: yes/{print m; exit}')
    echo "${m:-$MONITOR1}"
}

declare -A STATE   # monitor -> ścieżka tapety

# Wczytaj data/wallpaper.dat (nowy format monitor=ścieżka; inne linie pomija).
load_state() {
    [[ -f "$WALLPAPER_DAT" ]] || return 0
    while IFS='=' read -r mon path; do
        [[ -n "$mon" && -n "$path" ]] && STATE[$mon]="$path"
    done < "$WALLPAPER_DAT"
}

# Zestaw folderowy (stary model): v1 → primary, v2 → secondary.
apply_set_folder() {
    local dir="$1" v1 v2
    v1=$(find "$dir" -maxdepth 1 -iname "*v1*" | head -n1)
    v2=$(find "$dir" -maxdepth 1 -iname "*v2*" | head -n1)
    if [[ -z "$v1" ]]; then
        notify-send "archenemy" "Missing v1 wallpaper in folder '$(basename "$dir")'."
        return 1
    fi
    STATE[$MONITOR1]="$v1"
    [[ -n "$MONITOR2" && -n "$v2" ]] && STATE[$MONITOR2]="$v2"
    return 0
}

# Plik na wszystkie monitory; jeśli obok leży druga połowa pary v1/v2,
# primary dostaje v1, secondary v2 — inaczej ten sam plik wszędzie.
apply_file_allmon() {
    local f="$1" p="$1" s="$1" base dir pair
    base=$(basename "$f")
    dir=$(dirname "$f")
    shopt -s nocasematch
    if [[ "$base" == *v1* ]]; then
        pair=$(find "$dir" -maxdepth 1 -iname "*v2*" | head -n1)
        [[ -n "$pair" ]] && s="$pair"
    elif [[ "$base" == *v2* ]]; then
        pair=$(find "$dir" -maxdepth 1 -iname "*v1*" | head -n1)
        [[ -n "$pair" ]] && p="$pair"
    fi
    shopt -u nocasematch
    STATE[$MONITOR1]="$p"
    [[ -n "$MONITOR2" ]] && STATE[$MONITOR2]="$s"
}

# Zapisz stan i wygeneruj hyprpaper.conf (blok wallpaper{} na monitor).
# Zapis atomowy (tmp + mv w tym samym katalogu): crash w połowie zapisu nie
# zostawia uciętego wallpaper.dat / hyprpaper.conf (stary zapis w miejscu
# psuł stan przy przerwaniu między truncate a append).
save_and_generate() {
    local mon tmp_dat tmp_conf
    mkdir -p "$DATA_DIR" "$(dirname "$HYPRPAPER_CONF")"
    tmp_dat=$(mktemp "$WALLPAPER_DAT.XXXXXX") || return 1
    tmp_conf=$(mktemp "$HYPRPAPER_CONF.XXXXXX") || { rm -f "$tmp_dat"; return 1; }
    {
        echo "# generated by archenemy - do not edit by hand"
        echo "# hyprpaper >= 0.8 syntax (wallpaper blocks)"
        # Wyłącz splash hyprpapera (cytat/wersja Hyprlanda rysowana na tapecie).
        echo "splash = false"
    } > "$tmp_conf"
    for mon in "${!STATE[@]}"; do
        echo "$mon=${STATE[$mon]}" >> "$tmp_dat"
        {
            echo ""
            echo "wallpaper {"
            echo "    monitor = $mon"
            echo "    path = ${STATE[$mon]}"
            echo "    fit_mode = cover"
            echo "}"
        } >> "$tmp_conf"
    done
    chmod 644 "$tmp_dat" "$tmp_conf"   # mktemp daje 600 — zachowaj zwykłe prawa
    mv "$tmp_dat" "$WALLPAPER_DAT"
    mv "$tmp_conf" "$HYPRPAPER_CONF"
}

# Ustaw tło hyprlocka we wszystkich rice'ach (state = "off" albo ścieżka pliku).
# Nadpisuje WYŁĄCZNIE path/blur_size/blur_passes — brightness/contrast/noise/
# vibrancy per rice zostają nietknięte, więc tożsamość wizualna rice'a (np.
# przyciemniony tron) przeżywa włączenie/wyłączenie tej opcji. Restart/reload
# niepotrzebny: hyprlock czyta swój config od zera przy każdym Super+L.
apply_hyprlock_background() {
    local state="$1" f tmp path blur_size blur_passes path_esc
    if [[ "$state" == "off" ]]; then
        path="screenshot"; blur_size=7; blur_passes=3
    else
        path="$state"; blur_size=0; blur_passes=0
    fi
    # Ścieżka pochodzi z nazwy pliku użytkownika i trafia do PRAWEJ strony
    # podmiany seda — escapujemy znaki specjalne: `&` (= całe dopasowanie),
    # `\` oraz `|` (delimiter). Bez tego nazwa z `&` rozbija ścieżkę, a z `|`
    # wysypuje seda i pusty tmp nadpisałby dobry plik (hyprlock traci tło).
    path_esc=$(printf '%s' "$path" | sed -e 's/[\\&|]/\\&/g')
    for f in "${HYPRLOCK_BG_FILES[@]}"; do
        [[ -f "$f" ]] || continue
        tmp=$(mktemp "$f.XXXXXX") || continue
        # Guard: tylko udany sed nadpisuje plik — błąd zostawia oryginał.
        if sed -E \
            -e "s|^([[:space:]]*path[[:space:]]*=).*|\\1 ${path_esc}|" \
            -e "s|^([[:space:]]*blur_size[[:space:]]*=).*|\\1 ${blur_size}|" \
            -e "s|^([[:space:]]*blur_passes[[:space:]]*=).*|\\1 ${blur_passes}|" \
            "$f" > "$tmp"; then
            chmod 644 "$tmp"
            mv "$tmp" "$f"
        else
            rm -f "$tmp"
        fi
    done
    tmp=$(mktemp "$HYPRLOCK_DAT.XXXXXX") || return 1
    printf '%s\n' "$state" > "$tmp"
    chmod 644 "$tmp"
    mkdir -p "$DATA_DIR"
    mv "$tmp" "$HYPRLOCK_DAT"
}

# Zaaplikuj stan przez IPC (hyprpaper >= 0.8); gdy IPC padnie — restart daemona,
# który wczyta świeżo wygenerowany hyprpaper.conf.
apply_ipc() {
    local mon ok=1
    for mon in "${!STATE[@]}"; do
        hyprctl hyprpaper wallpaper "$mon, ${STATE[$mon]}, cover" &>/dev/null || ok=0
    done
    if [[ "$ok" -eq 0 ]]; then
        pkill hyprpaper
        hyprpaper & disown
    fi
}

# ─── MIGRACJA STAREGO FORMATU ─────────────────────────────────────────────────
# Stary wallpaper.dat trzymał samą nazwę zestawu — zamieniamy na monitor=ścieżka.

if [[ -f "$WALLPAPER_DAT" ]] && ! grep -q '=' "$WALLPAPER_DAT"; then
    legacy=$(<"$WALLPAPER_DAT")
    [[ -n "$legacy" && -d "$WALLPAPERS_DIR/$legacy" ]] && apply_set_folder "$WALLPAPERS_DIR/$legacy"
fi
load_state

# ─── PICK WALLPAPER ───────────────────────────────────────────────────────────

MODE_ALL=1    # ptaszek "Upload to all monitors" — domyślnie zaznaczony
MODE_LOCK=0   # ptaszek "Set as hyprlock background" — domyślnie odznaczony
LOCK_STATE="off"
[[ -f "$HYPRLOCK_DAT" ]] && LOCK_STATE="$(<"$HYPRLOCK_DAT")"
[[ "$LOCK_STATE" != "off" ]] && MODE_LOCK=1

if [[ "$1" == "--restore" ]]; then
    # Stan już wczytany (plus ewentualna migracja) — tylko odtwórz. Hyprlock
    # niezależnie od tapety pulpitu — przeżywa Super+T tak samo.
    apply_hyprlock_background "$LOCK_STATE"
    [[ ${#STATE[@]} -eq 0 ]] && exit 0
    save_and_generate
    apply_ipc
    exit 0
elif [[ -n "$1" ]]; then
    # Wywołanie bezpośrednie: absolutny plik / plik względem wallpapers/ / folder zestawu.
    if [[ -f "$1" ]]; then
        apply_file_allmon "$1"
        CHOICE="$1"
    elif [[ -f "$WALLPAPERS_DIR/$1" ]]; then
        apply_file_allmon "$WALLPAPERS_DIR/$1"
        CHOICE="$1"
    elif [[ -d "$WALLPAPERS_DIR/$1" ]]; then
        apply_set_folder "$WALLPAPERS_DIR/$1" || exit 1
        CHOICE="$1"
    else
        notify-send "archenemy" "No such wallpaper: $1"
        exit 1
    fi
else
    # Menu: wszystkie obrazy z wallpapers/ (rekurencyjnie), ścieżki względne.
    mapfile -t FILES < <(find "$WALLPAPERS_DIR" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        | sort)

    if [[ ${#FILES[@]} -eq 0 ]]; then
        notify-send "archenemy" "No wallpapers found in $WALLPAPERS_DIR"
        exit 1
    fi

    REL=()
    for f in "${FILES[@]}"; do
        REL+=("${f#"$WALLPAPERS_DIR"/}")
    done

    # Pętla menu: wybranie przełącznika odwraca ptaszek i otwiera menu ponownie.
    while :; do
        if [[ "$MODE_ALL" -eq 1 ]]; then
            toggle="$TOGGLE_ON"
        else
            toggle="$TOGGLE_OFF"
        fi
        if [[ "$MODE_LOCK" -eq 1 ]]; then
            lock_toggle="$LOCK_TOGGLE_ON"
        else
            lock_toggle="$LOCK_TOGGLE_OFF"
        fi
        CHOICE=$(printf '%s\n' "$toggle" "$lock_toggle" "${REL[@]}" | rofi -dmenu -i -p "Select wallpaper:")
        [[ -z "$CHOICE" ]] && exit 0
        if [[ "$CHOICE" == "$TOGGLE_ON" ]]; then
            MODE_ALL=0
            continue
        elif [[ "$CHOICE" == "$TOGGLE_OFF" ]]; then
            MODE_ALL=1
            continue
        elif [[ "$CHOICE" == "$LOCK_TOGGLE_ON" ]]; then
            MODE_LOCK=0
            continue
        elif [[ "$CHOICE" == "$LOCK_TOGGLE_OFF" ]]; then
            MODE_LOCK=1
            continue
        fi
        break
    done

    FILE="$WALLPAPERS_DIR/$CHOICE"
    # rofi -dmenu zwraca wpisany tekst także BEZ dopasowania — bez guarda zły
    # path szedł do wallpaper.dat + hyprpaper.conf i wracał przy --restore
    # (guard jak w gałęzi wywołania bezpośredniego wyżej).
    if [[ ! -f "$FILE" ]]; then
        notify-send "archenemy" "No such wallpaper: $CHOICE"
        exit 1
    fi
    if [[ "$MODE_ALL" -eq 1 ]]; then
        apply_file_allmon "$FILE"
    else
        STATE[$(focused_monitor)]="$FILE"
    fi

    # Hyprlock: tylko w tej (interaktywnej) gałęzi — bezpośrednie wywołanie
    # CLI nie dotyka stanu hyprlocka, poza zakresem tego menu.
    if [[ "$MODE_LOCK" -eq 1 ]]; then
        apply_hyprlock_background "$FILE"
    elif [[ "$LOCK_STATE" != "off" ]]; then
        apply_hyprlock_background "off"
    fi
fi

# ─── APPLY + SAVE ─────────────────────────────────────────────────────────────

save_and_generate
apply_ipc

[[ "$1" != "--restore" ]] && notify-send "archenemy" "Wallpaper '$CHOICE' applied."
exit 0
