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

# Deklarowany wybór archenemy; nie jest pomiarem fontu otwartego terminala.
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
    local want="$1" name found=1
    # Odczytaj całą listę: wczesny return zrywa potok producenta (SIGPIPE).
    while IFS= read -r name; do
        [[ "$name" == "$want" ]] && found=0
    done < <(font_installed 1)
    return "$found"
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

# Każdy cel, także blokada, musi być zwykłym plikiem albo nie istnieć.
font_targets_safe() {
    local target
    for target in alacritty.toml family family.prev .lock; do
        [[ ! -L "$FONT_DIR/$target" ]] || return 1
        [[ ! -e "$FONT_DIR/$target" || -f "$FONT_DIR/$target" ]] || return 1
    done
}

# Transakcja obejmuje konfigurację, wybór i historię. Kopie twarde zachowują
# oryginały przed publikacją; rollback nie używa mv, które mogło zawieść.
# Podpowłoka zwalnia blokadę również przy błędzie i sygnale.
font_apply() (
    local name="$1" prev stage target failed=0 committed=0
    local -a targets=(alacritty.toml family family.prev)
    if [[ -n "$name" && "${2:-}" != undo ]]; then
        font_name_valid "$name" || return 2
        font_installed_has "$name" || return 3
    fi
    font_dir_safe || return 4
    font_targets_safe || return 1
    exec 8>>"$FONT_DIR/.lock" || return 1
    flock -x 8 || return 1
    font_targets_safe || return 1
    if [[ "${2:-}" == undo ]]; then
        name="$(font_previous)" || return 1
        if [[ -n "$name" ]]; then
            font_name_valid "$name" || return 2
            font_installed_has "$name" || return 3
        fi
    fi
    prev="$(font_override)"
    stage="$(mktemp -d "$FONT_DIR/.transaction.XXXXXX")" || return 1
    # shellcheck disable=SC2329  # wywoływana przez trap EXIT
    font_transaction_cleanup() {
        local item rollback_failed=0
        if (( ! committed )); then
            for item in "${targets[@]}"; do
                if [[ -f "$stage/old/$item" ]]; then
                    cp -p --remove-destination -- "$stage/old/$item" "$FONT_DIR/$item" || rollback_failed=1
                    cmp -s -- "$stage/old/$item" "$FONT_DIR/$item" || rollback_failed=1
                elif [[ -f "$stage/ready" ]]; then
                    rm -f -- "$FONT_DIR/$item" || rollback_failed=1
                fi
            done
        fi
        if (( rollback_failed )); then
            echo "Font rollback failed; originals retained in $stage/old" >&2
        else
            rm -rf -- "$stage"
        fi
    }
    trap font_transaction_cleanup EXIT
    trap 'exit 1' HUP INT TERM
    mkdir "$stage/old" "$stage/new" || return 1
    for target in "${targets[@]}"; do
        if [[ -e "$FONT_DIR/$target" ]]; then
            ln -T -- "$FONT_DIR/$target" "$stage/old/$target" || return 1
        fi
    done
    # Dopiero komplet kopii pozwala usuwać cele nieobecne przed transakcją.
    touch "$stage/ready" || return 1
    printf '%s' "${prev:+$prev$'\n'}" >"$stage/new/family.prev" || return 1
    if [[ -n "$name" ]]; then
        printf '%s\n' "$name" >"$stage/new/family" || return 1
        printf '# archenemy font choice (Super+A -> [f]).\n[font.normal]\nfamily = "%s"\n' "$name" >"$stage/new/alacritty.toml" || return 1
    fi
    chmod 644 "$stage/new/"* || return 1
    for target in "${targets[@]}"; do
        if [[ -f "$stage/new/$target" ]]; then
            mv -fT -- "$stage/new/$target" "$FONT_DIR/$target" || { failed=1; break; }
        elif [[ -e "$FONT_DIR/$target" ]]; then
            mv -T -- "$FONT_DIR/$target" "$stage/removed-$target" || { failed=1; break; }
        fi
    done
    (( failed == 0 )) || return 1
    # Wynik publikacji musi odpowiadać przygotowanej treści.
    [[ ! -L "$FONT_DIR/family.prev" && -f "$FONT_DIR/family.prev" ]] || return 1
    [[ "$(cat "$FONT_DIR/family.prev")" == "$prev" ]] || return 1
    if [[ -n "$name" ]]; then
        [[ ! -L "$FONT_DIR/family" && ! -L "$FONT_DIR/alacritty.toml" ]] || return 1
        [[ "$(font_override)" == "$name" && "$(font_toml_family "$FONT_DIR/alacritty.toml")" == "$name" ]] || return 1
    else
        [[ ! -e "$FONT_DIR/family" && ! -e "$FONT_DIR/alacritty.toml" ]] || return 1
    fi
    committed=1
)

# Konfiguracja na dysku nie potwierdza fontu w oknie (CLI -c/-o, zoom,
# brak obserwacji pierwszego importu). Własnych konfiguracji nie interpretujemy
# jak konfiguracji rice'a; identyczność sprawdzamy po rozwiązaniu symlinków.
font_terminal_scope() {
    local active expected
    if [[ ( -n "${TERM_PROGRAM:-}" && "$TERM_PROGRAM" != Alacritty ) ||
          ( -z "${TERM_PROGRAM:-}" && "${TERM:-}" != alacritty ) ]]; then
        printf 'other or unknown terminal'
        return
    fi
    active="$(readlink -f -- "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml" 2>/dev/null)"
    expected="$(readlink -f -- "$FONT_REPO/rices/$(font_active_rice)/alacritty/alacritty.toml" 2>/dev/null)"
    if [[ -n "$active" && "$active" == "$expected" ]]; then
        printf 'rice Alacritty config; open a new terminal'
    else
        printf 'personal or unknown Alacritty config; import and local overrides unverified'
    fi
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
        "alacritty" yes "open a new terminal; requires rice config imports" \
        "terminal apps" yes "follow their terminal; personal configs unverified" \
        "rofi menus" yes "launcher, power, rice and wallpaper menus; next open" \
        "fastfetch" yes "archenemy choice, unverified terminal; next run" \
        "waybar" no "GTK CSS import of a missing file stops the bar" \
        "mako" no "a missing include aborts its config" \
        "hyprlock" no "labels cannot be overridden; lock screen kept safe" \
        "Wi-Fi menu" no "networkmanager-dmenu starts rofi itself" \
        "swayosd, MangoHud" no "built-in fonts, not set by rices" \
        "GTK/Qt apps" no "not set by archenemy"
}
