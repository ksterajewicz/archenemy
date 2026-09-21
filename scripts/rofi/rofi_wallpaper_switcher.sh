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
#   Menu jest dwupoziomowe (2026-09-08 — właściciel: „trudno się połapać"):
#     [x] Upload to all monitors / [ ] Set as hyprlock background   (przełączniki)
#     Wallpapers/     → podmenu: pliki z wallpapers/ (+ „← Back")
#     Animations/     → podmenu: animacje flux-wall; wizualizacje muzyki
#                       (shader z `#pragma flux audio 1`) mają dopisek
#                       „♪ music visualisation" (+ „← Back")
#     Animation: off  → wyłącza animację (pod folderami)
#   Foldery animacji tylko gdy flux-wall jest zbudowany. Wybór animacji idzie
#   do scripts/wallpapers/flux-wall.sh select|off (zapis w data/flux-wall.dat);
#   nie dotyka stanu tapety hyprpapera — animacja rysuje NAD nią.
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
# swój plik (patrz install.sh [8h]); pięć realnych rice'ów, beta dziedziczy
# symlinkiem hyprlock.conf z white-blue.
HYPRLOCK_BG_FILES=(
    "$ARCHENEMY_DIR/config/hypr/hyprlock-background-white-blue.conf"
    "$ARCHENEMY_DIR/config/hypr/hyprlock-background-tron.conf"
    "$ARCHENEMY_DIR/config/hypr/hyprlock-background-asia-n-rice.conf"
    "$ARCHENEMY_DIR/config/hypr/hyprlock-background-dither-flux.conf"
    "$ARCHENEMY_DIR/config/hypr/hyprlock-background-crt.conf"
)

TOGGLE_ON="[x] Upload to all monitors"
TOGGLE_OFF="[ ] Upload to all monitors"
LOCK_TOGGLE_ON="[x] Set as hyprlock background (no blur)"
LOCK_TOGGLE_OFF="[ ] Set as hyprlock background (no blur)"
FLUX_WALL="$ARCHENEMY_DIR/scripts/wallpapers/flux-wall.sh"
FLUX_WALL_BIN="$ARCHENEMY_DIR/src/flux-wall/build/flux-wall"
ANIM_PREFIX="Animation: "
FOLDER_WALL="Wallpapers/"
FOLDER_ANIM="Animations/"
BACK="← Back"
AUDIO_SUFFIX="   ♪ music visualisation"
ANIM_OFF="${ANIM_PREFIX}off"

# ─── RESOLVE MONITORS FROM data/monitors/*.dat ───────────────────────────────

# Monitory jako SELEKTORY ("desc:<opis EDID>" z lib/monitor-id.sh, albo nazwa
# złącza dla starych .dat) — nazwa złącza zmienia się po restarcie
# (eDP-2 → eDP-1), a hyprpaper.conf i hyprlock rozumieją desc: tak samo jak
# Hyprland. Do IPC hyprpapera idzie ŻYWA nazwa (monitor_live_name).
# shellcheck source=scripts/hypr/lib/monitor-id.sh
source "$ARCHENEMY_DIR/scripts/hypr/lib/monitor-id.sh"

MONITOR1=""   # primary  -> dostaje v1
MONITOR2=""   # secondary -> dostaje v2

if [[ -d "$DATA_DIR/monitors" ]]; then
    for dat in "$DATA_DIR/monitors"/*.dat; do
        [[ -f "$dat" ]] || continue
        mon=$(monitor_selector_from_dat "$dat")
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

# Monitor z fokusem jako SELEKTOR (klucz STATE); fallback: primary, gdy
# hyprctl nie odpowie albo fokus stoi na monitorze spoza data/monitors.
focused_monitor() {
    local m sel
    m=$(hyprctl monitors 2>/dev/null | awk '/^Monitor/{m=$2} /focused: yes/{print m; exit}')
    for sel in "$MONITOR1" "$MONITOR2"; do
        [[ -n "$sel" && -n "$m" && "$(monitor_live_name "$sel")" == "$m" ]] && { echo "$sel"; return; }
    done
    echo "$MONITOR1"
}

declare -A STATE   # monitor -> ścieżka tapety

# Wczytaj data/wallpaper.dat (nowy format monitor=ścieżka; inne linie pomija).
load_state() {
    [[ -f "$WALLPAPER_DAT" ]] || return 0
    while IFS='=' read -r mon path; do
        [[ -n "$mon" && -n "$path" ]] || continue
        # Klucz sprzed selektorów desc: (goła nazwa złącza) — trzymaj tylko,
        # gdy to nie jest po prostu stara nazwa monitora znanego dziś z .dat
        # (inaczej hyprpaper.conf rósłby o martwe bloki po każdej zmianie nazwy).
        if [[ "$mon" != desc:* && "$mon" != "$MONITOR1" && "$mon" != "$MONITOR2" ]]; then
            [[ -n "$(monitor_live_name "$mon")" ]] || continue
        fi
        STATE[$mon]="$path"
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
# który wczyta świeżo wygenerowany hyprpaper.conf (save_and_generate poszło
# przed tym wywołaniem, więc świeży proces sam pokaże poprawny stan — IPC nie
# trzeba powtarzać po restarcie).
#
# `timeout` na każde wywołanie: klient hyprctl czeka na odpowiedź hyprpapera
# BEZ WŁASNEGO LIMITU CZASU (źródło: hyprctl/src/hyprpaper/Hyprpaper.cpp,
# doWallpaper() — pętla `while (!canExit) socket->dispatchEvents(true);`).
# Zawieszony/zajęty demon (np. dekodowanie dużej świeżo wygenerowanej tapety
# dither-flux) zawiesiłby CAŁY skrót rofi bez żadnej informacji zwrotnej —
# dokładnie objaw zgłoszony 2026-09-17 („tapety się nie chciały zmieniać”).
#
# Restart robiony jak waybar/swayosd-server w lib/switch-rice.sh: poczekaj,
# aż stara instancja REALNIE zniknie, zanim odpalisz nową (start obok
# umierającej = dwie instancje walczące o warstwę background), dobij -9 po
# ~2 s, i POCZEKAJ na start nowej — bez tego restart mógł nie pomóc, a
# skrypt i tak kończył z notyfikacją "applied" (fałszywy sukces).
#
# Zwraca 0 = tapeta poszła (IPC albo restart), 1 = restart też nie pomógł
# (wołający pokazuje krytyczne powiadomienie zamiast fałszywego sukcesu).
apply_ipc() {
    local mon ok=1 err_log="${XDG_RUNTIME_DIR:-/tmp}/archenemy-hyprpaper-err.log"
    : > "$err_log"
    local live
    for mon in "${!STATE[@]}"; do
        # selektor desc: → nazwa złącza TERAZ; odpięty monitor pomijamy
        # (hyprpaper.conf i tak trzyma jego wpis na następne podpięcie)
        live=$(monitor_live_name "$mon")
        [[ -n "$live" ]] || continue
        timeout 3 hyprctl hyprpaper wallpaper "$live, ${STATE[$mon]}, cover" >>"$err_log" 2>&1 || ok=0
    done
    [[ "$ok" -eq 1 ]] && return 0

    pkill -x hyprpaper 2>/dev/null
    for _ in $(seq 1 20); do
        pgrep -x hyprpaper >/dev/null || break
        sleep 0.1
    done
    if pgrep -x hyprpaper >/dev/null; then
        pkill -9 -x hyprpaper 2>/dev/null
        sleep 0.2
    fi
    hyprpaper & disown
    for _ in $(seq 1 20); do
        pgrep -x hyprpaper >/dev/null && return 0
        sleep 0.1
    done
    return 1
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
    apply_ipc || notify-send -u critical "archenemy" "Wallpaper restore failed — hyprpaper didn't come back up. Log: ${XDG_RUNTIME_DIR:-/tmp}/archenemy-hyprpaper-err.log"
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

    # Animacje (flux-wall) — tylko gdy binarka istnieje; bez niej pozycje
    # obiecywałyby coś, czego install.sh nie zbudował. Wizualizacje muzyki
    # dostają dopisek — audio włącza się dla nich samo (flux-wall czyta pragmę).
    ANIM=()
    if [[ -x "$FLUX_WALL_BIN" && -f "$FLUX_WALL" ]]; then
        mapfile -t AUDIO_NAMES < <(bash "$FLUX_WALL" list-audio 2>/dev/null)
        while IFS= read -r name; do
            [[ -n "$name" ]] || continue
            label="$name"
            for an in "${AUDIO_NAMES[@]}"; do [[ "$an" == "$name" ]] && label="${name}${AUDIO_SUFFIX}"; done
            ANIM+=("$label")
        done < <(bash "$FLUX_WALL" list 2>/dev/null)
    fi

    # Pętla menu: przełączniki odwracają ptaszek i otwierają menu ponownie;
    # foldery otwierają podmenu, „← Back" wraca na górę.
    CHOICE=""; KIND=""
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
        TOP=("$toggle" "$lock_toggle" "$FOLDER_WALL")
        [[ ${#ANIM[@]} -gt 0 ]] && TOP+=("$FOLDER_ANIM" "$ANIM_OFF")
        SEL=$(printf '%s\n' "${TOP[@]}" | rofi -dmenu -i -p "Select wallpaper:")
        [[ -z "$SEL" ]] && exit 0
        case "$SEL" in
            "$TOGGLE_ON")      MODE_ALL=0; continue ;;
            "$TOGGLE_OFF")     MODE_ALL=1; continue ;;
            "$LOCK_TOGGLE_ON") MODE_LOCK=0; continue ;;
            "$LOCK_TOGGLE_OFF") MODE_LOCK=1; continue ;;
            "$ANIM_OFF")       KIND="anim-off"; break ;;
            "$FOLDER_WALL")
                SUB=$(printf '%s\n' "$BACK" "${REL[@]}" | rofi -dmenu -i -p "Wallpapers:")
                [[ -z "$SUB" ]] && exit 0
                [[ "$SUB" == "$BACK" ]] && continue
                CHOICE="$SUB"; KIND="file"; break ;;
            "$FOLDER_ANIM")
                SUB=$(printf '%s\n' "$BACK" "${ANIM[@]}" | rofi -dmenu -i -p "Animations:")
                [[ -z "$SUB" ]] && exit 0
                [[ "$SUB" == "$BACK" ]] && continue
                CHOICE="${SUB%"$AUDIO_SUFFIX"}"; KIND="anim"; break ;;
            *) continue ;;   # wpisany tekst bez dopasowania — menu wraca
        esac
    done

    # Animacja: osobna droga — wybór zapisuje i stosuje flux-wall.sh, stan tapety
    # hyprpapera zostaje nietknięty (animacja rysuje nad nią).
    if [[ "$KIND" == "anim-off" ]]; then
        bash "$FLUX_WALL" off >/dev/null 2>&1
        notify-send "archenemy" "Animation off."
        exit 0
    elif [[ "$KIND" == "anim" ]]; then
        anim="$CHOICE"
        if bash "$FLUX_WALL" select "$anim" >/dev/null 2>&1; then
            notify-send "archenemy" "Animation '$anim' applied."
            exit 0
        fi
        notify-send -u critical "archenemy" "Animation '$anim' failed to start — see ${XDG_RUNTIME_DIR:-/tmp}/flux-wall.log"
        exit 1
    fi

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
if apply_ipc; then
    notify-send "archenemy" "Wallpaper '$CHOICE' applied."
else
    notify-send -u critical "archenemy" "Wallpaper '$CHOICE' failed to apply — hyprpaper didn't come back up. Log: ${XDG_RUNTIME_DIR:-/tmp}/archenemy-hyprpaper-err.log"
fi
exit 0
