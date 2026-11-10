#!/bin/bash
# =============================================
#   archenemy - scripts/appbinds/lib/fonts.sh
#   Font użytkownika ponad fontem rice'a (Super+A → [f]). Jedyne miejsce, które
#   czyta i zapisuje wybór; source'owana przez font-settings.sh i skrypty rofi,
#   bez efektów ubocznych przy wczytaniu.
#
#   Warstwa osobista POZA repozytorium: ~/.config/archenemy/fonts/
#     family          wybrana rodzina (brak pliku = font rice'a)
#     family.prev     poprzednia wartość (pusta = font rice'a), do cofnięcia
#     alacritty.toml  [font.normal] family — importowany przez rices/*/alacritty
#   Domyślny font rice'a leży w rices/<rice>/alacritty/font.toml. Alacritty
#   wczytuje importy po kolei, pomija brakujące, a plik importujący wczytuje
#   na końcu — dlatego rodzina nie może stać w alacritty.toml rice'a.
#   Rozmiary zostają z rice'a: zmieniamy tylko rodzinę.
# =============================================

FONT_REPO="${ARCHENEMY_DIR:-$HOME/archenemy}"
FONT_DIR="${ARCHENEMY_FONT_DIR:-$HOME/.config/archenemy/fonts}"
FONT_FC_LIST="${ARCHENEMY_FC_LIST:-fc-list}"

font_active_rice() {
    local file="$FONT_REPO/.current_rice" rice=""
    [[ -f "$file" ]] && rice="$(<"$file")"
    printf '%s' "$rice"
}

# white-blue_beta jest zamrożony (AGENTS.md): bez nowych mechanizmów, więc bez
# nadpisania. Rice bez font.toml też (np. starszy fork).
font_rice_supported() {
    local rice="$1"
    [[ -n "$rice" && "$rice" != white-blue_beta && "$rice" != */* ]] || return 1
    [[ -f "$FONT_REPO/rices/$rice/alacritty/font.toml" ]]
}

# Pierwsza wartość `family = "..."` z pliku TOML (bez parsera — pliki są nasze).
font_toml_family() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    sed -n 's/^[[:space:]]*family[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n1
}

font_rice_default() {
    local rice="$1" f
    f="$(font_toml_family "$FONT_REPO/rices/$rice/alacritty/font.toml")"
    [[ -n "$f" ]] || f="$(font_toml_family "$FONT_REPO/rices/$rice/alacritty/alacritty.toml")"
    printf '%s' "$f"
}

# Rozmiar terminala z [font] size w alacritty.toml rice'a.
font_rice_size() {
    local file="$FONT_REPO/rices/$1/alacritty/alacritty.toml"
    [[ -f "$file" ]] || return 0
    awk '
        /^\[font\][[:space:]]*$/ { in_font=1; next }
        /^\[/ { in_font=0 }
        in_font && /^[[:space:]]*size[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]#].*$/, ""); print; exit }
    ' "$file"
}

# Rozmiar menu rofi z `font: "Rodzina N";` w config.rasi rice'a (wszystkie: 11).
font_rofi_size() {
    local file="$FONT_REPO/rices/$1/rofi/config.rasi" size=""
    [[ -f "$file" ]] && size="$(sed -n 's/^[[:space:]]*font:[[:space:]]*"[^"]* \([0-9][0-9.]*\)";.*/\1/p' "$file" | head -n1)"
    printf '%s' "${size:-11}"
}

# Nazwa rodziny trafia do TOML, rasi, wzorca fontconfig i na terminal. Zamiast
# kodować każdy z tych formatów odrzucamy znaki, które w którymś coś znaczą:
# sterujące (też C1 w UTF-8), cudzysłów, backslash, `$`, `:` i `,` (fontconfig).
font_name_valid() {
    local name="$1" LC_ALL=C
    [[ -n "$name" && ${#name} -le 128 ]] || return 1
    [[ "$name" != [[:space:]]* && "$name" != *[[:space:]] ]] || return 1
    [[ "$name" != *[[:cntrl:]]* ]] || return 1
    [[ "$name" != *$'\xc2'[$'\x80'-$'\x9f']* ]] || return 1
    case "$name" in
        *'"'*|*\\*|*'$'*|*:*|*,*|*'`'*) return 1 ;;
    esac
    return 0
}

# Zapisany wybór; pusto, gdy go nie ma albo plik jest uszkodzony.
font_override() {
    local file="$FONT_DIR/family" name=""
    [[ -f "$file" ]] || return 0
    IFS= read -r name <"$file" || [[ -n "$name" ]] || return 0
    font_name_valid "$name" && printf '%s' "$name"
}

# Font, którego terminal faktycznie używa w aktywnym rice'ie.
font_effective() {
    local rice over
    rice="$(font_active_rice)"
    over="$(font_override)"
    if [[ -n "$over" ]] && font_rice_supported "$rice"; then
        printf '%s' "$over"
    else
        font_rice_default "$rice"
    fi
}

# Argument -theme-str dla rofi albo pusto (brak wyboru = motyw rice'a bez zmian).
# Selektory jak w motywach rice'ów: *, prompt, entry.
font_rofi_theme_str() {
    local rice over size
    rice="$(font_active_rice)"
    over="$(font_override)"
    [[ -n "$over" ]] && font_rice_supported "$rice" || return 0
    size="$(font_rofi_size "$rice")"
    printf '* { font: "%s %s"; } prompt { font: "%s %s"; } entry { font: "%s %s"; }' \
        "$over" "$size" "$over" "$size" "$over" "$size"
}

# Zainstalowane rodziny, po jednej w wierszu, posortowane i bez duplikatów.
# $1 = 1 → wszystkie; inaczej tylko o stałej szerokości (spacing mono/dual/charcell).
# fc-list wypisuje „Rodzina,Nazwa lokalna:spacing=100”; bierzemy pierwszą nazwę.
font_installed() {
    local all="${1:-0}" name
    timeout 5 "$FONT_FC_LIST" : family spacing 2>/dev/null \
        | awk -v all="$all" '
            {
                line = $0; mono = 0
                if (match(line, /:spacing=[0-9]+$/)) {
                    if (substr(line, RSTART + 9) + 0 >= 90) mono = 1
                    line = substr(line, 1, RSTART - 1)
                }
                split(line, parts, ","); fam = parts[1]
                if (fam != "" && (all == 1 || mono)) print fam
            }' \
        | LC_ALL=C sort -u \
        | while IFS= read -r name; do
            font_name_valid "$name" && printf '%s\n' "$name"
        done
    return 0
}

font_installed_has() {
    local want="$1" name
    while IFS= read -r name; do
        [[ "$name" == "$want" ]] && return 0
    done < <(font_installed 1)
    return 1
}

# Czy rodzina ma glif Nerd Font (U+F303, logo Archa). Fontconfig rozumie `-`
# jako separator rozmiaru, więc go escapujemy.
font_has_nerd_glyphs() {
    local pattern="${1//-/\\-}"
    [[ -n "$(timeout 5 "$FONT_FC_LIST" "$pattern:charset=f303" family 2>/dev/null)" ]]
}

# Katalog stanu nie może prowadzić do repozytorium (np. symlink do rices/).
# Sprawdzamy przed mkdir (readlink -m), żeby nie zostawić katalogu w repo.
font_dir_safe() {
    local resolved repo
    resolved="$(readlink -m -- "$FONT_DIR")" || return 1
    repo="$(readlink -f -- "$FONT_REPO" 2>/dev/null)" || repo=""
    if [[ -n "$repo" && ( "$resolved" == "$repo" || "$resolved" == "$repo/"* ) ]]; then
        return 1
    fi
    mkdir -p -- "$FONT_DIR"
}

# Atomowy zapis jednej treści: plik tymczasowy obok i mv.
font_write_file() {
    local file="$1" content="$2" tmp
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    if ! printf '%s' "$content" >"$tmp" || ! chmod 644 "$tmp" || ! mv -f -- "$tmp" "$file"; then
        rm -f -- "$tmp"
        return 1
    fi
}

# Ustawia rodzinę ($1) albo usuwa wybór (pusty $1). Najpierw kopia poprzedniej
# wartości, potem plik alacritty, na końcu `family` — stan pokazuje wybór
# dopiero, gdy konfiguracja jest gotowa. Kody: 0 ok, 1 błąd zapisu,
# 2 niepoprawna nazwa, 3 font niezainstalowany, 4 katalog wskazuje repo.
font_apply() {
    local name="$1" prev
    if [[ -n "$name" ]]; then
        font_name_valid "$name" || return 2
        font_installed_has "$name" || return 3
    fi
    font_dir_safe || return 4
    prev="$(font_override)"
    font_write_file "$FONT_DIR/family.prev" "${prev:+$prev$'\n'}" || return 1
    if [[ -z "$name" ]]; then
        rm -f -- "$FONT_DIR/family" "$FONT_DIR/alacritty.toml" || return 1
        return 0
    fi
    font_write_file "$FONT_DIR/alacritty.toml" "# archenemy font choice (Super+A -> [f]). Delete this file to use the rice font.
[font.normal]
family = \"$name\"
" || return 1
    font_write_file "$FONT_DIR/family" "$name"$'\n' || return 1
}

font_previous() {
    local file="$FONT_DIR/family.prev" name=""
    [[ -f "$file" ]] || return 1
    IFS= read -r name <"$file" || true
    [[ -z "$name" ]] || font_name_valid "$name" || return 1
    printf '%s' "$name"
}

# Konsumenci: nazwa<TAB>yes/no<TAB>kiedy/dlaczego. Jedno źródło dla ekranu,
# podglądu w menu głównym i README.
font_coverage() {
    printf '%s\t%s\t%s\n' \
        "alacritty" yes "live reload; new windows always" \
        "terminal apps" yes "nvim, ncmpcpp, btop follow alacritty" \
        "rofi menus" yes "launcher, power, rice and wallpaper menus; next open" \
        "fastfetch" yes "FONT row; next run" \
        "waybar" no "GTK CSS import of a missing file stops the bar" \
        "mako" no "a missing include aborts its config" \
        "hyprlock" no "labels cannot be overridden; lock screen kept safe" \
        "Wi-Fi menu" no "networkmanager-dmenu starts rofi itself" \
        "swayosd, MangoHud" no "built-in fonts, not set by rices" \
        "GTK/Qt apps" no "not set by archenemy"
}
