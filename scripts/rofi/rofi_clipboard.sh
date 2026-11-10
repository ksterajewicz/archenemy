#!/bin/bash
# =============================================
#   archenemy - rofi_clipboard.sh
#   Historia schowka Super+C; wybór kopiuje, Ctrl+V wkleja.
# =============================================
set -uo pipefail
umask 077
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/rofi/lib/rofi-preview.sh
source "$SCRIPT_DIR/lib/rofi-preview.sh"

message() {
    printf '%s\n' "$1" >&2
    if command -v rofi >/dev/null 2>&1; then
        rofi -e "$1" >/dev/null 2>&1 || :
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send archenemy "$1" || :
    fi
}
for dependency in rofi cliphist wl-copy; do
    case "$dependency" in
        rofi) package=rofi-wayland ;;
        cliphist) package=cliphist ;;
        wl-copy) package=wl-clipboard ;;
    esac
    if ! command -v "$dependency" >/dev/null 2>&1; then
        message "Clipboard history requires $dependency. Install package: $package."
        exit 1
    fi
done

# Indeksy rofi odnoszą się do tablic, nigdy do tekstu schowka.
# Brak bazy przy pierwszym uruchomieniu to również pusta historia.
if ! history=$(cliphist list 2>&1); then
    if [[ "$history" == *'please store something first'* ]]; then
        message 'Clipboard history is empty'
        exit 0
    fi
    message 'Cannot read clipboard history. Check cliphist configuration.'
    exit 1
fi
IDS=(); LABELS=(); ICONS=(); HAVE_ICONS=0
CACHE_DIR=""
trap '[[ -z "$CACHE_DIR" ]] || rm -rf -- "$CACHE_DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
thumb_init
while IFS= read -r row; do
    [[ "$row" == *$'\t'* ]] || continue
    id=${row%%$'\t'*}
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    label=${row#*$'\t'}
    # cliphist już spłaszcza tekst; usuń również znaki sterujące/metadane rofi.
    label=$(printf '%s' "$label" | tr '\t\r\n' '   ' | tr -d '[:cntrl:]')
    label=${label:0:120}
    icon=""
    if [[ "$label" =~ ^\[\[\ binary\ data\ .*\ (png|jpeg|gif|bmp|tiff)\ [0-9]+x[0-9]+\ \]\]$ ]] && (( SECONDS < THUMB_DEADLINE )); then
        # Prywatny cache tylko na czas menu: wipe/delete nie zostawiają kopii obrazów.
        if [[ -z "$CACHE_DIR" ]]; then
            cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
            if mkdir -p -- "$cache_root"; then
                CACHE_DIR=$(mktemp -d "$cache_root/archenemy-clipboard.XXXXXX") || CACHE_DIR=""
            fi
            THUMB_DIR="$CACHE_DIR/thumbs"
        fi
        if [[ -n "$CACHE_DIR" ]]; then
            raw="$CACHE_DIR/$id"
            if timeout -k 1 1 cliphist decode "$id" > "$raw" 2>/dev/null && [[ -s "$raw" ]]; then
                thumb_get "$raw"
                icon=$REPLY
            fi
        fi
    fi
    [[ -z "$icon" ]] || HAVE_ICONS=1
    IDS+=("$id"); LABELS+=("$label"); ICONS+=("$icon")
done <<< "$history"
count=${#IDS[@]}
if (( count == 0 )); then
    message 'Clipboard history is empty'
    exit 0
fi

# Zwykła lista bieżącego motywu; wspólna biblioteka służy tylko miniaturom.
entry_menu() {
    local actions="$1" i
    for i in "${!IDS[@]}"; do
        printf '%s' "${LABELS[$i]}"
        [[ -z "${ICONS[$i]}" ]] || printf '\0icon\x1f%s' "${ICONS[$i]}"
        printf '\n'
    done
    if [[ "$actions" == yes ]]; then printf 'Delete entry\nClear history\n'; fi
}
select_entry() {
    # Miniatury obrazów: motywy mają ikonę 20px, więc powiększ ją tylko gdy są obrazy.
    local -a theme=()
    (( HAVE_ICONS )) && theme=(-theme-str 'element-icon { size: 3em; }')
    entry_menu "$2" | rofi -dmenu -i -p "$1" -no-custom -format i -no-sort -show-icons "${theme[@]}"
}
selected=$(select_entry 'Clipboard history:' yes) || exit 0
[[ "$selected" =~ ^[0-9]+$ && ${#selected} -lt 9 ]] || exit 0
selected=$((10#$selected))
if (( selected < count )); then
    if ! cliphist decode "${IDS[$selected]}" | wl-copy; then
        message 'Cannot copy clipboard entry. It may have been removed.'
        exit 1
    fi
elif (( selected == count )); then
    selected=$(select_entry 'Delete entry:' no) || exit 0
    [[ "$selected" =~ ^[0-9]+$ && ${#selected} -lt 9 ]] || exit 0
    selected=$((10#$selected))
    (( selected < count )) || exit 0
    if ! printf '%s\n' "${IDS[$selected]}" | cliphist delete; then
        message 'Cannot delete clipboard entry.'
        exit 1
    fi
elif (( selected == count + 1 )); then
    answer=$(printf 'No\nYes\n' | rofi -dmenu -i -p 'Clear history?' -no-custom -format i -no-sort) || exit 0
    [[ "$answer" == 1 ]] || exit 0
    if ! cliphist wipe; then
        message 'Cannot clear clipboard history.'
        exit 1
    fi
fi
