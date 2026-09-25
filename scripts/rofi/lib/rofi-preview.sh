#!/bin/bash
# =============================================
#   archenemy - scripts/rofi/lib/rofi-preview.sh
#   Podglądy PNG w menu rofi (Super+W, Super+T) — biblioteka source'owana
#   przez rofi_wallpaper_switcher.sh i rofi_theme_switcher.sh.
#
#   Mechanizm: wpis rofi -dmenu w postaci `etykieta\0icon\x1f/abs/plik.png`
#   (rofi-script(5), opcje wiersza) + -show-icons. rofi wybiera i zwraca
#   SAMĄ etykietę, więc logika menu w skryptach zostaje bez zmian.
#
#   Układ: siatka 3 kolumny z dużą ikoną nad podpisem — nadpisywana przez
#   -theme-str TYLKO w tych menu, gdy choć jeden wpis ma podgląd. Każdy
#   motyw rice'a (rices/*/rofi/themes/*.rasi) ma ten sam szkielet:
#   window 520px, listview 8 linii, element poziomy, element-icon 20px —
#   nadpisujemy dokładnie te właściwości, kolory/ramki/zaokrąglenia rice'a
#   zostają. Wpis bez podglądu (← Back, przełączniki) ma po prostu puste
#   pole ikony.
#
#   Miniatury tapet (warstwa maszynowa, data/thumbs/ — /data/ w .gitignore):
#   generowane leniwie przy otwarciu menu, klucz = sha1(ścieżka) + mtime,
#   więc edytowany plik dostaje nową miniaturę, a stara jest kasowana.
#   Narzędzie (pierwsze dostępne, każde za `command -v`):
#     1. glycin-thumbnailer   — pakiet glycin; zależność gdk-pixbuf2 >= 2.44,
#                               a ten — zależność rofi (rofi → gdk-pixbuf2 →
#                               glycin), więc jest wszędzie, gdzie jest rofi,
#     2. gdk-pixbuf-thumbnailer — starsze gdk-pixbuf2 (< 2.44) go dostarczały,
#     3. magick               — imagemagick, jeśli ktoś ma,
#     4. brak / błąd / limit czasu → ikoną jest ORYGINALNY obraz (rofi go
#        wczyta, tylko wolniej). Menu nigdy nie pada przez miniatury.
#   Limit: THUMB_TIMEOUT s na plik i THUMB_BUDGET s na całe menu — pierwsze
#   otwarcie z dziesiątkami nowych tapet nie zawiesza skrótu.
# =============================================

THUMB_DIR="${THUMB_DIR:-$HOME/archenemy/data/thumbs}"
THUMB_SIZE=320        # dłuższy bok miniatury (px) — 2× pole ikony, ostre na HiDPI
THUMB_TIMEOUT=3       # s na jeden plik
THUMB_BUDGET=6        # s na wszystkie brakujące miniatury jednego otwarcia menu
THUMB_TOOL=""
THUMB_DEADLINE=0

# Rozmiar pola ikony w siatce — podgląd 16:9 skaluje się do szerokości pola.
ROFI_PREVIEW_ICON_SIZE="160px"

# Motyw siatki dla menu z podglądami; $1 = liczba wpisów (liczba wierszy
# siatki = tyle, ile potrzeba, najwyżej 3 — reszta przewija się jak lista).
rofi_preview_theme() {
    local n="${1:-9}" lines
    lines=$(( (n + 2) / 3 ))
    (( lines < 1 )) && lines=1
    (( lines > 3 )) && lines=3
    printf 'window { width: 960px; } listview { columns: 3; lines: %d; } element { orientation: vertical; } element-icon { size: %s; } element-text { horizontal-align: 0.5; }' \
        "$lines" "$ROFI_PREVIEW_ICON_SIZE"
}

# Menu dmenu z podglądami. Wejście: pary (etykieta, ikona) w dwóch tablicach
# przekazanych NAZWĄ: rofi_preview_menu PROMPT LABELS_VAR ICONS_VAR.
# Pusta ikona albo nieistniejący plik = wpis bez ikony. Gdy żaden wpis nie ma
# podglądu — zwykła lista motywu rice'a (bez -theme-str). Wypisuje wybór.
rofi_preview_menu() {
    local prompt="$1" i any=0
    local -n _labels="$2" _icons="$3"
    local -a args=(-dmenu -i -p "$prompt")
    for i in "${!_labels[@]}"; do
        [[ -n "${_icons[$i]:-}" && -f "${_icons[$i]}" ]] && { any=1; break; }
    done
    (( any )) && args+=(-show-icons -theme-str "$(rofi_preview_theme "${#_labels[@]}")")
    for i in "${!_labels[@]}"; do
        if [[ -n "${_icons[$i]:-}" && -f "${_icons[$i]}" ]]; then
            printf '%s\0icon\x1f%s\n' "${_labels[$i]}" "${_icons[$i]}"
        else
            printf '%s\n' "${_labels[$i]}"
        fi
    done | rofi "${args[@]}"
}

# ─── miniatury ──────────────────────────────────────────────────────────────

# Wywołaj raz przed serią thumb_get: wybór narzędzia + start budżetu czasu.
thumb_init() {
    THUMB_TOOL=""
    if command -v glycin-thumbnailer >/dev/null 2>&1; then THUMB_TOOL=glycin
    elif command -v gdk-pixbuf-thumbnailer >/dev/null 2>&1; then THUMB_TOOL=gdk-pixbuf
    elif command -v magick >/dev/null 2>&1; then THUMB_TOOL=magick
    fi
    THUMB_DEADLINE=$(( SECONDS + THUMB_BUDGET ))
}

# Ścieżka → file:// URL (glycin-thumbnailer przyjmuje TYLKO URL; zwykła
# ścieżka kończy się „Operation not supported" i kodem 0). Bajtowo, w
# locale C — spacje, apostrofy, `&`, UTF-8 w nazwach tapet.
file_url() {
    local LC_ALL=C s="$1" out="" c i
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [A-Za-z0-9/._~-]) out+="$c" ;;
            *) printf -v c '%%%02X' "'$c"; out+="$c" ;;
        esac
    done
    printf 'file://%s' "$out"
}

# Jedno wywołanie narzędzia: $1 źródło, $2 plik wyjściowy (.png).
# Kod wyjścia nic nie znaczy (glycin zwraca 0 także przy błędzie) —
# wołający sprawdza, czy plik wyjściowy ma treść.
thumb_generate() {
    local src="$1" out="$2"
    case "$THUMB_TOOL" in
        glycin)
            timeout -k 1 "$THUMB_TIMEOUT" glycin-thumbnailer \
                --input "$(file_url "$src")" --output "$out" --size "$THUMB_SIZE" >/dev/null 2>&1 ;;
        gdk-pixbuf)
            timeout -k 1 "$THUMB_TIMEOUT" gdk-pixbuf-thumbnailer \
                -s "$THUMB_SIZE" "$src" "$out" >/dev/null 2>&1 ;;
        magick)
            # [0] = pierwsza klatka (gif/webp animowany); png: wymusza format
            timeout -k 1 "$THUMB_TIMEOUT" magick "${src}[0]" -auto-orient \
                -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}>" -strip "png:$out" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

# Miniatura obrazu $1 → REPLY (bez podpowłoki: budżet czasu i narzędzie
# żyją w zmiennych tego procesu). Zawsze ustawia REPLY na coś, co da się
# pokazać: gotową/świeżą miniaturę albo — przy braku narzędzia, błędzie
# lub wyczerpanym budżecie — oryginał.
thumb_get() {
    local src="$1" key mtime out tmp
    REPLY="$src"
    mtime=$(stat -c %Y -- "$src" 2>/dev/null) || return 0
    key=$(printf '%s' "$src" | sha1sum) || return 0
    key="${key%% *}"
    out="$THUMB_DIR/$key-$mtime.png"
    if [[ -s "$out" ]]; then REPLY="$out"; return 0; fi
    [[ -n "$THUMB_TOOL" ]] || return 0
    (( SECONDS < THUMB_DEADLINE )) || return 0
    mkdir -p "$THUMB_DIR" 2>/dev/null || return 0
    # Zapis przez plik tymczasowy obok docelowego: przerwany timeoutem
    # generator nie zostawia uciętego PNG pod właściwą nazwą.
    tmp=$(mktemp --suffix=.png "$THUMB_DIR/.gen-XXXXXX" 2>/dev/null) || return 0
    if thumb_generate "$src" "$tmp"; [[ -s "$tmp" ]]; then
        chmod 644 "$tmp"
        # Plik edytowany (inny mtime) — stara miniatura tej ścieżki znika.
        rm -f -- "$THUMB_DIR/$key"-*.png
        mv -f -- "$tmp" "$out" && REPLY="$out"
    else
        rm -f -- "$tmp"
    fi
    return 0
}
