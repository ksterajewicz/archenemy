#!/usr/bin/env bash
# =============================================
#   archenemy - src/system-theme/build.sh
#   Składa motywy systemowe (ekran logowania SDDM, menu GRUB-a) ze źródeł
#   repo do WSKAZANEGO katalogu. Niczego nie instaluje i nie dotyka systemu
#   — do /usr/share i /boot kopiuje dopiero install/system-theme-installation.sh;
#   te same katalogi biorą narzędzia podglądu (src/system-theme/tools/).
#
#   Źródła:
#     rices/<rice>/system-theme.conf      tokeny rice'a (tapety logowania,
#                                         kolory menu GRUB-a) — czytane jako
#                                         dane, nigdy wykonywane;
#     src/system-theme/sddm/<rice>/       układ ekranu logowania rice'a;
#     src/system-theme/sddm/components/   logika wspólna wszystkich rice'ów;
#     src/system-theme/grub/assets.py     obrazki menu GRUB-a.
#
#   Użycie:
#     build.sh rices sddm|grub
#         rice'y z kompletem źródeł danego motywu, po jednym w linii
#     build.sh sddm <rice> <katalog>
#         kompletny motyw SDDM (Main.qml, components/, tapety rice'a);
#         katalog nie może istnieć albo musi być pusty
#     build.sh grub <katalog> [-H WYSOKOŚĆ] [-g GLIF] [-t FONT.ttf] [-y FONT.ttf]
#                             [-a RICE:LOGO]
#         JEDEN katalog motywu GRUB-a dla wszystkich rice'ów naraz:
#           theme-<rice>-distro.txt, theme-<rice>-archenemy.txt  warianty
#           <rice>-logo.png, <rice>-select_*.png                 obrazki rice'a
#           text.pf2, small.pf2, logo.pf2                        fonty wspólne
#         Aktywny wariant to plik theme.txt — przełączenie rice'a albo logo
#         podmienia tylko ten jeden plik (bez grub-mkconfig).
#         -H  wysokość ekranu w pikselach (domyślnie 1080): rozmiary fontów
#             i odstępów GRUB-a są w pikselach, nie skalują się same
#         -g  glif logo dystrybucji (domyślnie scripts/waybar/launcher-logo.sh
#             glyph — glify dystrybucji żyją w repo wyłącznie tam)
#         -t  font tekstu (domyślnie zainstalowany JetBrainsMono Nerd Font Mono)
#         -y  font glifu (domyślnie zainstalowany Symbols Nerd Font Mono)
#         -a  od razu zapisz theme.txt dla RICE:LOGO (LOGO: distro|archenemy)
#   Wymaga: python3; dla GRUB-a grub-mkfont (pakiet grub) i fc-match, gdy
#   fonty nie są podane przez -t/-y. Kod 0 = katalog gotowy.
# =============================================

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO/src/system-theme"

die() { echo "build.sh: $*" >&2; exit 1; }

usage() {
    sed -n '/^#   Użycie:/,/^#   fonty nie są podane/p' "${BASH_SOURCE[0]}" | sed 's/^#   \{0,1\}//' >&2
    exit 2
}

valid_rice() { [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,39}$ ]]; }

# conf_value <rice> <KLUCZ> — wartość KLUCZ="..." z deklaracji rice'a.
# Plik jest danymi: żadnego source ani eval.
conf_value() {
    local file="$REPO/rices/$1/system-theme.conf" line
    [[ -f "$file" ]] || return 1
    line="$(grep -m1 -E "^$2=\"[^\"]*\"[[:space:]]*\$" "$file")" || return 1
    line="${line#*=\"}"
    printf '%s\n' "${line%\"*}"
}

colour_value() {
    local value
    value="$(conf_value "$1" "$2")" || die "rices/$1/system-theme.conf: $2 is missing"
    [[ "$value" =~ ^#[0-9A-Fa-f]{6}$ ]] || die "rices/$1/system-theme.conf: $2 must be #RRGGBB"
    printf '%s\n' "$value"
}

has_sddm() { [[ -f "$SRC/sddm/$1/Main.qml" ]] && conf_value "$1" SDDM_WALLPAPER_169 >/dev/null; }
has_grub() { conf_value "$1" GRUB_BACKGROUND >/dev/null; }

list_rices() {
    local conf rice
    for conf in "$REPO"/rices/*/system-theme.conf; do
        [[ -f "$conf" ]] || continue
        rice="${conf%/system-theme.conf}"; rice="${rice##*/}"
        valid_rice "$rice" || continue
        "has_$1" "$rice" && printf '%s\n' "$rice"
    done
}

# ─── SDDM ─────────────────────────────────────────────────────────────────────

build_sddm() {
    local rice="$1" out="$2" key target file
    valid_rice "$rice" || die "bad rice name '$rice'"
    has_sddm "$rice" || die "rice '$rice' has no login screen sources (src/system-theme/sddm/$rice/ and rices/$rice/system-theme.conf)"
    if [[ -e "$out" ]]; then
        [[ -d "$out" && -z "$(ls -A "$out")" ]] || die "'$out' exists and is not an empty directory"
    fi
    mkdir -p "$out" || die "cannot create '$out'"
    for file in Main.qml theme.conf metadata.desktop; do
        [[ -f "$SRC/sddm/$rice/$file" ]] || die "src/system-theme/sddm/$rice/$file is missing"
        cp "$SRC/sddm/$rice/$file" "$out/$file" || die "cannot copy $file"
    done
    grep -q '^QtVersion=6$' "$out/metadata.desktop" \
        || die "src/system-theme/sddm/$rice/metadata.desktop needs QtVersion=6 (SDDM would look for a Qt5 greeter)"
    mkdir -p "$out/components" || die "cannot create '$out/components'"
    cp "$SRC"/sddm/components/*.qml "$out/components/" || die "cannot copy components"
    for key in 169 1610; do
        file="$(conf_value "$rice" "SDDM_WALLPAPER_$key")" || die "rices/$rice/system-theme.conf: SDDM_WALLPAPER_$key is missing"
        [[ "$file" == wallpapers/*.png && "$file" != *..* ]] \
            || die "rices/$rice/system-theme.conf: SDDM_WALLPAPER_$key must be a .png under wallpapers/"
        [[ -f "$REPO/$file" ]] || die "$file (SDDM_WALLPAPER_$key of $rice) does not exist"
        target="$out/background-$key.png"
        cp "$REPO/$file" "$target" || die "cannot copy $file"
    done
    chmod -R u=rwX,go=rX "$out"
}

# ─── GRUB ─────────────────────────────────────────────────────────────────────

# Font po nazwie rodziny: plik z fontconfig, ale tylko gdy to naprawdę ta
# rodzina (fc-match zawsze coś zwraca — bez kontroli wszedłby font zastępczy).
font_file() {
    local family="$1" found
    command -v fc-match >/dev/null 2>&1 || return 1
    found="$(fc-match -f '%{family}\t%{file}\n' "$family:style=Regular" 2>/dev/null | head -1)"
    [[ "${found%%$'\t'*}" == *"$family"* && -f "${found#*$'\t'}" ]] || return 1
    printf '%s\n' "${found#*$'\t'}"
}

build_grub() {
    local out="$1"; shift
    local height=1080 glyph="" text_font="" symbol_font="" activate="" opt
    OPTIND=1
    while getopts ":H:g:t:y:a:" opt; do
        case "$opt" in
            H) height="$OPTARG" ;;
            g) glyph="$OPTARG" ;;
            t) text_font="$OPTARG" ;;
            y) symbol_font="$OPTARG" ;;
            a) activate="$OPTARG" ;;
            *) usage ;;
        esac
    done
    if ! [[ "$height" =~ ^[0-9]{3,4}$ ]] || (( 10#$height < 480 || 10#$height > 4320 )); then
        die "bad screen height '$height' (480-4320)"
    fi
    height=$(( 10#$height ))
    command -v python3 >/dev/null 2>&1 || die "python3 not found"
    command -v grub-mkfont >/dev/null 2>&1 || die "grub-mkfont not found (package: grub)"
    if [[ -z "$text_font" ]]; then
        text_font="$(font_file "JetBrainsMono Nerd Font Mono")" \
            || die "JetBrainsMono Nerd Font Mono is not installed (package: ttf-jetbrains-mono-nerd) — or pass -t FONT.ttf"
    fi
    if [[ -z "$symbol_font" ]]; then
        symbol_font="$(font_file "Symbols Nerd Font Mono")" \
            || die "Symbols Nerd Font Mono is not installed (package: ttf-nerd-fonts-symbols-mono) — or pass -y FONT.ttf"
    fi
    [[ -f "$text_font" ]] || die "font '$text_font' not found"
    [[ -f "$symbol_font" ]] || die "font '$symbol_font' not found"
    [[ -n "$glyph" ]] || glyph="$(bash "$REPO/scripts/waybar/launcher-logo.sh" glyph 2>/dev/null)"
    # Glif to dokładnie jeden znak spoza ASCII; jego numer podaje python
    # (printf '%d' "'x" zależy od ustawień regionalnych powłoki).
    local codepoint
    codepoint="$(python3 -c 'import sys
g = sys.argv[1]
print("0x%X" % ord(g) if len(g) == 1 and ord(g) > 0x7F else "")' "$glyph" 2>/dev/null)"
    [[ -n "$codepoint" ]] || die "the distro glyph must be one non-ASCII character"

    if [[ -e "$out" ]]; then
        [[ -d "$out" && -z "$(ls -A "$out")" ]] || die "'$out' exists and is not an empty directory"
    fi
    mkdir -p "$out" || die "cannot create '$out'"

    # Wymiary zaprojektowane dla ekranu 1080 px, przeliczane na wysokość ekranu.
    px() { echo $(( ($1 * height + 540) / 1080 )); }
    local text_size small_size logo_size item_height menu_width
    text_size="$(px 22)"; small_size="$(px 15)"; logo_size="$(px 104)"
    item_height="$(px 48)"; menu_width="$(px 620)"

    # Łacina z rozszerzeniem A i typografia; reszta znaków idzie z unicode.pf2
    # GRUB-a. Ostrzeżenia grub-mkfont o cechach fontu są tylko przy błędzie.
    local ranges="0x20-0x17F,0x2010-0x2027" font_log
    font_log="$(grub-mkfont -n "archenemy text" -s "$text_size" -r "$ranges" -o "$out/text.pf2" "$text_font" 2>&1)" \
        || die "grub-mkfont failed for the menu font: $font_log"
    font_log="$(grub-mkfont -n "archenemy small" -s "$small_size" -r "$ranges" -o "$out/small.pf2" "$text_font" 2>&1)" \
        || die "grub-mkfont failed for the small font: $font_log"
    font_log="$(grub-mkfont -n "archenemy logo" -s "$logo_size" -r "$codepoint-$codepoint" -o "$out/logo.pf2" "$symbol_font" 2>&1)" \
        || die "grub-mkfont failed for the distro glyph: $font_log"
    [[ -s "$out/text.pf2" && -s "$out/small.pf2" && -s "$out/logo.pf2" ]] || die "grub-mkfont wrote an empty font"

    local rice count=0 background text selected dim accent fill logo style variant logo_block left stroke
    left="50%-$(( menu_width / 2 ))"
    while IFS= read -r rice; do
        background="$(colour_value "$rice" GRUB_BACKGROUND)" || exit 1
        text="$(colour_value "$rice" GRUB_TEXT)" || exit 1
        selected="$(colour_value "$rice" GRUB_SELECTED)" || exit 1
        dim="$(colour_value "$rice" GRUB_DIM)" || exit 1
        accent="$(colour_value "$rice" GRUB_ACCENT)" || exit 1
        fill="$(colour_value "$rice" GRUB_FILL)" || exit 1
        logo="$(colour_value "$rice" GRUB_LOGO)" || exit 1
        style="$(conf_value "$rice" GRUB_SELECT)" || die "rices/$rice/system-theme.conf: GRUB_SELECT is missing"
        [[ "$style" == bar || "$style" == frame ]] || die "rices/$rice/system-theme.conf: GRUB_SELECT must be bar or frame"
        # Kreska zaznaczenia jest grubsza niż ramka dookoła pozycji.
        if [[ "$style" == bar ]]; then stroke="$(px 3)"; else stroke="$(px 2)"; fi
        python3 "$SRC/grub/assets.py" "$out" "$rice" "$REPO/assets/logo/archenemy-ae.svg" "$logo_size" \
            "$logo" "$style" "$accent" "$fill" "$stroke" "$(px 16)" \
            || die "assets.py failed for $rice"
        for variant in distro archenemy; do
            if [[ "$variant" == archenemy ]]; then
                logo_block="+ image {
    left = $left
    top = 24%
    width = $logo_size
    height = $logo_size
    file = \"$rice-logo.png\"
}"
            else
                logo_block="+ label {
    left = $left
    top = 24%
    width = $(( logo_size * 2 ))
    height = $(( logo_size * 3 / 2 ))
    align = \"left\"
    text = \"$glyph\"
    font = \"archenemy logo Regular $logo_size\"
    color = \"$logo\"
}"
            fi
            cat > "$out/theme-$rice-$variant.txt" <<THEME
# archenemy — GRUB theme: $rice, $variant logo, for a screen $height px high.
# Generated by src/system-theme/build.sh — do not edit, re-run the installer.
title-text: ""
desktop-color: "$background"
terminal-font: "archenemy small Regular $small_size"
$logo_block
+ boot_menu {
    left = $left
    top = 24%+$(px 168)
    width = $menu_width
    height = $(( item_height * 6 ))
    item_font = "archenemy text Regular $text_size"
    item_color = "$text"
    selected_item_color = "$selected"
    item_height = $item_height
    item_padding = 0
    item_spacing = $(px 6)
    icon_width = 0
    icon_height = 0
    item_icon_space = 0
    selected_item_pixmap_style = "$rice-select_*.png"
    scrollbar = false
}
+ label {
    id = "__timeout__"
    left = $left
    top = 100%-$(px 116)
    width = $menu_width
    height = $(px 24)
    align = "left"
    text = "starting in %d s"
    font = "archenemy small Regular $small_size"
    color = "$dim"
}
+ label {
    left = $left
    top = 100%-$(px 84)
    width = $menu_width
    height = $(px 24)
    align = "left"
    text = "enter boot   e edit   c command line"
    font = "archenemy small Regular $small_size"
    color = "$dim"
}
THEME
        done
        count=$(( count + 1 ))
    done < <(list_rices grub)
    (( count > 0 )) || die "no rice declares GRUB colours (rices/<rice>/system-theme.conf)"

    if [[ -n "$activate" ]]; then
        [[ "$activate" =~ ^([a-z0-9][a-z0-9_-]*):(distro|archenemy)$ ]] || die "bad -a '$activate' (expected RICE:distro or RICE:archenemy)"
        [[ -f "$out/theme-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}.txt" ]] || die "no GRUB theme for '$activate'"
        cp "$out/theme-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}.txt" "$out/theme.txt" || die "cannot write theme.txt"
    fi
    chmod -R u=rwX,go=rX "$out"
}

# ─── WEJŚCIE ──────────────────────────────────────────────────────────────────

case "${1:-}" in
    rices)
        [[ $# -eq 2 && ( "$2" == sddm || "$2" == grub ) ]] || usage
        list_rices "$2"
        ;;
    sddm)
        [[ $# -eq 3 ]] || usage
        build_sddm "$2" "$3"
        ;;
    grub)
        [[ $# -ge 2 ]] || usage
        build_grub "${@:2}"
        ;;
    *) usage ;;
esac
