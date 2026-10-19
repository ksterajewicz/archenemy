#!/bin/bash

# =============================================
#   archenemy - keyboard-layouts.sh
#   Układy klawiatury użytkownika: lista 1–4 układów XKB w wybranej
#   kolejności (XKB obsługuje najwyżej 4 grupy). Jedyna droga do tej
#   funkcji — wołają ją TUI Super+A → [k] i bindy Super+Ctrl+1…4.
#
#   Użycie:  keyboard-layouts.sh show            → zapisana lista (np. pl,us)
#            keyboard-layouts.sh presets         → kod<TAB>nazwa gotowych układów
#            keyboard-layouts.sh name <kod>      → nazwa układu (z evdev.lst)
#            keyboard-layouts.sh set <a,b,…>     → zapis + reload + sprawdzenie
#            keyboard-layouts.sh reset           → pl,us (domyślne rice'ów)
#            keyboard-layouts.sh switch <1-4>    → przełącz na układ nr N listy
#
#   Super+K (następny układ) zostaje w rice'ach bez zmian. Pierwszy układ
#   listy jest aktywny po starcie sesji.
#
#   Warstwa OSOBISTA (poza gitem):
#     data/keyboard-layouts.dat      — lista po przecinku (źródło prawdy)
#     config/hypr/keyboard-layouts.lua — generowany z .dat; rice'y parytetu
#                                    require'ują go PO bloku input (wygrywa
#                                    z `kb_layout = "pl,us"` rice'a; hl.config
#                                    ustawia klucze pojedynczo — Hyprland v0.56.2).
#
#   Kody wyjścia: 0 ok, 1 zła lista / błąd zapisu / numer spoza listy,
#   2 zapisane, ale Hyprland pokazuje inną listę albo nie dało się jej odczytać.
# =============================================

ARCHENEMY_DIR="$HOME/archenemy"
DAT="$ARCHENEMY_DIR/data/keyboard-layouts.dat"
LUA="$ARCHENEMY_DIR/config/hypr/keyboard-layouts.lua"
DEFAULT="pl,us"
MAX=4
# Lista układów XKB z xkeyboard-config (zależność libxkbcommon/Hyprlanda);
# hak dla testów. Brak pliku = akceptujemy kod o poprawnej składni.
XKB_RULES="${ARCHENEMY_XKB_RULES:-/usr/share/X11/xkb/rules/evdev.lst}"

# Gotowe układy w TUI (europejskie + angielski US/UK). Inny kod XKB można
# wpisać ręcznie — sprawdzany w evdev.lst.
PRESETS=(
    "pl	Polish"           "us	English (US)"     "gb	English (UK)"
    "de	German"           "at	German (Austria)" "ch	German (Switzerland)"
    "fr	French"           "be	Belgian"          "nl	Dutch"
    "es	Spanish"          "pt	Portuguese"       "it	Italian"
    "si	Slovenian"        "hr	Croatian"         "rs	Serbian"
    "ba	Bosnian"          "cz	Czech"            "sk	Slovak"
    "hu	Hungarian"        "ro	Romanian"         "bg	Bulgarian"
    "gr	Greek"            "ru	Russian"          "ua	Ukrainian"
    "by	Belarusian"       "lt	Lithuanian"       "lv	Latvian"
    "ee	Estonian"         "fi	Finnish"          "se	Swedish"
    "no	Norwegian"        "dk	Danish"           "is	Icelandic"
    "tr	Turkish"
)

# Nazwa układu z sekcji „! layout” evdev.lst (pusto = nie ma takiego kodu).
xkb_name() {
    [[ -r "$XKB_RULES" ]] || return 1
    awk -v k="$1" '/^! /{ sec = $2; next } sec == "layout" && $1 == k {
        $1 = ""; sub(/^ +/, ""); print; exit }' "$XKB_RULES"
}

valid_code() {
    local c="$1"
    [[ "$c" =~ ^[a-z]{2,3}$ ]] || return 1
    [[ -r "$XKB_RULES" ]] || return 0
    [[ -n "$(xkb_name "$c")" ]]
}

# Lista z wejścia → „a,b,c” (małe litery, bez spacji) albo błąd na stderr.
normalize_list() {
    local raw="${1,,}" c out=() seen=" "
    raw="${raw// /}"
    [[ -n "$raw" ]] || { echo "✗ empty layout list" >&2; return 1; }
    IFS=',' read -ra parts <<< "$raw"
    for c in "${parts[@]}"; do
        [[ -n "$c" ]] || continue
        valid_code "$c" || { echo "✗ '$c' is not a known XKB layout code" >&2; return 1; }
        [[ "$seen" == *" $c "* ]] && { echo "✗ '$c' is on the list twice" >&2; return 1; }
        seen+="$c "; out+=("$c")
    done
    (( ${#out[@]} >= 1 && ${#out[@]} <= MAX )) || { echo "✗ choose 1 to $MAX layouts (got ${#out[@]})" >&2; return 1; }
    local IFS=','; printf '%s' "${out[*]}"
}

current() {
    local v=""
    [[ -f "$DAT" ]] && v="$(normalize_list "$(<"$DAT")" 2>/dev/null)"
    printf '%s' "${v:-$DEFAULT}"
}

write_atomic() {
    local file="$1" content="$2" tmp
    mkdir -p "$(dirname "$file")" || return 1
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    printf '%s\n' "$content" > "$tmp" && chmod 644 "$tmp" && mv "$tmp" "$file"
}

hypr_running() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1
}

case "${1:-}" in
    show) current; echo; exit 0 ;;
    presets) printf '%s\n' "${PRESETS[@]}"; exit 0 ;;
    name)
        n="$(xkb_name "${2:-}")"
        if [[ -z "$n" ]]; then
            for p in "${PRESETS[@]}"; do [[ "${p%%	*}" == "${2:-}" ]] && n="${p#*	}"; done
        fi
        printf '%s\n' "${n:-${2:-}}"; exit 0 ;;
    switch)
        list="$(current)"; IFS=',' read -ra L <<< "$list"
        n="${2:-}"
        if [[ ! "$n" =~ ^[1-9]$ ]] || (( n > ${#L[@]} )); then
            command -v notify-send >/dev/null 2>&1 && \
                notify-send "archenemy" "No keyboard layout #${n} — you have ${#L[@]} (${list}). Super+A → [k] to add more." 2>/dev/null
            exit 1
        fi
        hypr_running || exit 1
        hyprctl switchxkblayout all "$((n - 1))" >/dev/null 2>&1
        exit $? ;;
    reset) value="$DEFAULT" ;;
    set) value="$(normalize_list "${2:-}")" || exit 1 ;;
    *) echo "usage: $(basename "$0") show | presets | name <code> | set <a,b,…> | reset | switch <1-$MAX>" >&2; exit 1 ;;
esac

write_atomic "$DAT" "$value" || { echo "✗ cannot write $DAT" >&2; exit 1; }
write_atomic "$LUA" "-- generated by archenemy (Super+A → [k]) — keyboard layouts, personal layer.
-- Source of truth: data/keyboard-layouts.dat; edit through the TUI, not here.
-- Order matters: #1 is active at login and on Super+Ctrl+1, #2 on Super+Ctrl+2…
hl.config({ input = { kb_layout = \"$value\" } })" || { echo "✗ cannot write $LUA" >&2; exit 1; }

if ! hypr_running; then
    echo "✓ saved: $value (applies when Hyprland starts)"
    exit 0
fi

hyprctl reload >/dev/null 2>&1
got=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    got="$(hyprctl getoption input:kb_layout 2>/dev/null | sed -n 's/^str: //p' | head -1)"
    [[ "$got" == "$value" ]] && { echo "✓ keyboard layouts: $value"; exit 0; }
    sleep 0.2
done
echo "⚠ saved $value, but Hyprland reports '${got:-nothing}' — check: hyprctl configerrors" >&2
exit 2
