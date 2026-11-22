#!/usr/bin/env bash
# =============================================
#   archenemy - src/system-theme/system-theme-sync.sh
#   Przenosi wybory użytkownika na ekran logowania SDDM i menu GRUB-a:
#   aktywny rice (Super+T), logo systemu i monitor logowania (Super+A),
#   tapetę (Super+W). Działa jako ROOT — pliki obu motywów są systemowe.
#
#   Nie uruchamiaj tego pliku z repo jako root. Instalator
#   (install/system-theme-installation.sh) kopiuje go do
#   /usr/local/lib/archenemy/system-theme-sync jako plik roota i dopiero tę
#   kopię woła usługa archenemy-system-theme.service (po zmianie plików
#   stanu) albo użytkownik: sudo /usr/local/lib/archenemy/system-theme-sync
#
#   Zasada: wszystko z katalogu użytkownika to DANE NIEZAUFANE.
#     * pliki stanu czyta proces z uprawnieniami użytkownika (setpriv), z
#       limitem rozmiaru i czasu — dowiązanie do cudzego pliku nic nie da;
#     * nazwa rice'a i monitora musi pasować do wzorca, a rice mieć motyw
#       zainstalowany przez roota; logo to tylko distro albo archenemy;
#     * tapeta jest kopiowana do katalogu motywu tylko jako zwykły plik
#       PNG albo JPEG do 64 MiB;
#     * nic stąd nie jest wykonywane ani wklejane do polecenia.
#   Ustawienia roota: /etc/archenemy/system-theme.conf (pisze instalator):
#     STATE_USER=<login>   czyje wybory obowiązują
#     STATE_DIR=<ścieżka>  katalog archenemy tego użytkownika
#     GLYPH=<znak>         glif logo dystrybucji
#     SDDM=1|0  GRUB=1|0   które motywy są zainstalowane
#
#   Co zmienia:
#     /etc/sddm.conf.d/20-archenemy-theme.conf      [Theme] Current=archenemy-<rice>
#     /usr/share/sddm/themes/archenemy-<rice>/theme.conf.user, user-wallpaper
#     /boot/grub/themes/archenemy/theme.txt         kopia theme-<rice>-<logo>.txt
#   grub.cfg nie jest regenerowany: wskazuje stały plik theme.txt.
#   Rice bez motywu (np. własny rice użytkownika) = nic się nie zmienia.
#   Kod 0 = stan zgodny z wyborami (także „nic do zrobienia”); 1 = błąd.
#
#   Hak testowy (tests/system-theme.sh), tylko z ARCHENEMY_TEST=1:
#   ARCHENEMY_SYSROOT — katalog podstawiany za / dla plików systemowych.
# =============================================

set -uo pipefail

SYSROOT=""
if [[ "${ARCHENEMY_TEST:-}" == 1 ]]; then
    SYSROOT="${ARCHENEMY_SYSROOT:-}"
else
    # Skrypt roota nie ufa odziedziczonemu PATH.
    PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
    export PATH
fi

CONF="$SYSROOT/etc/archenemy/system-theme.conf"
SDDM_THEMES="$SYSROOT/usr/share/sddm/themes"
SDDM_DROPIN="$SYSROOT/etc/sddm.conf.d/20-archenemy-theme.conf"
GRUB_THEME_DIR="$SYSROOT/boot/grub/themes/archenemy"
WALLPAPER_MAX=$(( 64 * 1024 * 1024 ))

say() { echo "system-theme-sync: $*"; }
die() { echo "system-theme-sync: $*" >&2; exit 1; }

# ─── USTAWIENIA ROOTA ─────────────────────────────────────────────────────────

conf_value() {
    local line
    line="$(grep -m1 -E "^$1=" "$CONF" 2>/dev/null)" || return 1
    printf '%s\n' "${line#*=}"
}

[[ -f "$CONF" ]] || die "$CONF not found — run install/system-theme-installation.sh"
if (( EUID == 0 )) && [[ -z "$SYSROOT" ]]; then
    # Plik ustawień wskazuje, czyje dane czytamy — musi należeć do roota.
    [[ "$(stat -c '%u' "$CONF")" == 0 && "$(stat -c '%A' "$CONF")" != ?????w* && "$(stat -c '%A' "$CONF")" != ????????w* ]] \
        || die "$CONF must be owned by root and not writable by others"
fi
STATE_USER="$(conf_value STATE_USER)" || die "$CONF: STATE_USER is missing"
STATE_DIR="$(conf_value STATE_DIR)" || die "$CONF: STATE_DIR is missing"
GLYPH="$(conf_value GLYPH)" || GLYPH=""
WITH_SDDM="$(conf_value SDDM)" || WITH_SDDM=0
WITH_GRUB="$(conf_value GRUB)" || WITH_GRUB=0
[[ "$STATE_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "$CONF: bad STATE_USER"
[[ "$STATE_DIR" == /* && "$STATE_DIR" != *[[:cntrl:]]* && "$STATE_DIR" != *..* ]] || die "$CONF: bad STATE_DIR"
GLYPH="${GLYPH//[[:cntrl:]]/}"; GLYPH="${GLYPH:0:1}"

# Root zrzuca uprawnienia do użytkownika przy każdym odczycie jego plików.
# Wyjątki: proces bez roota (i tak nie ma więcej praw) oraz testy na
# atrapach z podstawionym katalogiem systemowym.
STATE_UID=""; STATE_GID=""; DROP=0
if (( EUID == 0 )) && [[ -z "$SYSROOT" ]]; then
    DROP=1
    STATE_UID="$(id -u "$STATE_USER" 2>/dev/null)" || die "user '$STATE_USER' does not exist"
    STATE_GID="$(id -g "$STATE_USER" 2>/dev/null)" || die "user '$STATE_USER' has no group"
    (( STATE_UID != 0 )) || die "STATE_USER must not be root"
    command -v setpriv >/dev/null 2>&1 || die "setpriv not found (package: util-linux)"
fi

as_user() {
    if (( DROP )); then
        setpriv --reuid="$STATE_UID" --regid="$STATE_GID" --clear-groups -- "$@"
    else
        "$@"
    fi
}

# ─── CZYTANIE STANU UŻYTKOWNIKA ───────────────────────────────────────────────

# Pierwsza linia pliku bez białych znaków, najwyżej 256 bajtów; brak = pusto.
state_token() {
    local value=""
    value="$(as_user timeout 5 head -c 256 -- "$STATE_DIR/$1" 2>/dev/null | head -n1 | tr -d '[:space:]\000')" || true
    printf '%s\n' "$value"
}

# Odcisk wszystkich plików stanu — zmiana w trakcie pracy = jeszcze jeden obieg.
fingerprint() {
    {
        local f
        for f in .current_rice data/launcher-logo.dat data/login-screen.dat data/wallpaper.dat; do
            printf '%s\n' "== $f"
            as_user timeout 5 head -c 65536 -- "$STATE_DIR/$f" 2>/dev/null | tr -d '\000'
        done
    } | sha256sum | cut -d' ' -f1
}

valid_connector() { [[ "$1" =~ ^[A-Za-z][A-Za-z0-9-]{0,31}$ ]]; }

# monitor_lookup primary | <nazwa złącza>
# Szuka w data/monitors/*.dat monitora głównego (ROLE=primary) albo o danej
# nazwie złącza. Ustawia MON_NAME (nazwa złącza z pliku) i MON_SELECTOR
# (klucz tego monitora w wallpaper.dat: "desc:<opis>" albo nazwa — jak
# scripts/hypr/lib/monitor-id.sh). Nic nie znaleziono = oba puste.
MON_NAME=""; MON_SELECTOR=""
monitor_lookup() {
    local want="$1" dat content name role desc count=0
    MON_NAME=""; MON_SELECTOR=""
    while IFS= read -r dat; do
        (( ++count > 16 )) && break
        content="$(as_user timeout 5 head -c 4096 -- "$dat" 2>/dev/null | tr -d '\000')" || continue
        name="$(grep -m1 '^MONITOR=' <<< "$content" | cut -d= -f2-)"
        role="$(grep -m1 '^ROLE=' <<< "$content" | cut -d= -f2-)"
        desc="$(grep -m1 '^DESCRIPTION=' <<< "$content" | cut -d= -f2-)"
        valid_connector "$name" || continue
        if [[ "$want" == primary ]]; then
            [[ "$role" == primary ]] || continue
        else
            [[ "${name^^}" == "${want^^}" ]] || continue
        fi
        MON_NAME="$name"
        if [[ -n "$desc" && "$desc" != *[\"\\#=]* && "$desc" != *[[:cntrl:]]* ]]; then
            MON_SELECTOR="desc:$desc"
        else
            MON_SELECTOR="$name"
        fi
        return 0
    done < <(as_user timeout 5 find "$STATE_DIR/data/monitors" -maxdepth 1 -type f -name '*.dat' 2>/dev/null | sort)
    return 1
}

# Ścieżka tapety z data/wallpaper.dat ("monitor=ścieżka" po linii): linia
# monitora logowania, a bez niej pierwsza poprawna.
wallpaper_path() {
    local selector="$1" data line first="" hit=""
    data="$(as_user timeout 5 head -c 65536 -- "$STATE_DIR/data/wallpaper.dat" 2>/dev/null | tr -d '\000')" || return 1
    while IFS= read -r line; do
        [[ "$line" == *=/* ]] || continue
        [[ -n "$first" ]] || first="${line#*=}"
        if [[ -n "$selector" && "${line%%=*}" == "$selector" ]]; then
            hit="${line#*=}"
            break
        fi
    done <<< "$data"
    hit="${hit:-$first}"
    [[ -n "$hit" ]] || return 1
    printf '%s\n' "$hit"
}

# ─── ZAPIS ────────────────────────────────────────────────────────────────────

# write_if_changed <plik> <treść> — zapis przez plik tymczasowy i mv.
write_if_changed() {
    local file="$1" content="$2" tmp
    if [[ -f "$file" && "$(cat "$file" 2>/dev/null)" == "$content" ]]; then
        return 0
    fi
    tmp="$(mktemp "$file.XXXXXX")" || return 1
    if printf '%s\n' "$content" > "$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$file"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# sync_wallpaper <katalog motywu> <ścieżka z wallpaper.dat>
# Kod 0 = w katalogu motywu leży aktualna kopia (plik user-wallpaper).
sync_wallpaper() {
    local theme="$1" path="$2" stat_line size key tmp magic
    [[ "$path" == /* && "$path" != *[[:cntrl:]]* && ${#path} -le 4096 ]] || return 1
    as_user timeout 5 test -f "$path" 2>/dev/null || return 1
    stat_line="$(as_user timeout 5 stat -L -c '%s %Y %i' -- "$path" 2>/dev/null)" || return 1
    size="${stat_line%% *}"
    [[ "$size" =~ ^[0-9]{1,12}$ ]] || return 1
    (( size > 0 && size <= WALLPAPER_MAX )) || return 1
    # Znacznik to skrót, nie ścieżka: katalog motywu czytają wszyscy.
    key="$(printf '%s|%s' "$path" "$stat_line" | sha256sum | cut -d' ' -f1)"
    if [[ -f "$theme/user-wallpaper" && "$(cat "$theme/user-wallpaper.stamp" 2>/dev/null)" == "$key" ]]; then
        return 0
    fi
    tmp="$(mktemp "$theme/.user-wallpaper.XXXXXX")" || return 1
    if ! as_user timeout 30 head -c $(( WALLPAPER_MAX + 1 )) -- "$path" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"; return 1
    fi
    size="$(stat -c '%s' "$tmp")"
    magic="$(head -c 8 "$tmp" | od -An -tx1 | tr -d ' \n')"
    if (( size == 0 || size > WALLPAPER_MAX )) || [[ "$magic" != 89504e470d0a1a0a && "$magic" != ffd8ff* ]]; then
        rm -f "$tmp"; return 1
    fi
    if ! chmod 644 "$tmp" || ! mv -f "$tmp" "$theme/user-wallpaper"; then
        rm -f "$tmp"; return 1
    fi
    printf '%s\n' "$key" > "$theme/user-wallpaper.stamp"
    return 0
}

# ─── JEDEN OBIEG ──────────────────────────────────────────────────────────────

apply() {
    local rice logo screen want theme variant background="" path

    rice="$(state_token .current_rice)"
    [[ "$rice" =~ ^[a-z0-9][a-z0-9_-]{0,39}$ ]] || { say "no valid rice in .current_rice — nothing changed"; return 0; }
    logo="$(state_token data/launcher-logo.dat)"
    [[ "$logo" == archenemy ]] || logo=distro

    # Monitor logowania: jawny wybór albo monitor główny archenemy.
    want="$(state_token data/login-screen.dat)"
    screen=""
    if valid_connector "$want" && [[ "$want" != primary ]]; then
        screen="$want"
        monitor_lookup "$want" || true
    elif monitor_lookup primary; then
        screen="$MON_NAME"
    fi

    # ── SDDM ──
    if [[ "$WITH_SDDM" == 1 ]]; then
        theme="$SDDM_THEMES/archenemy-$rice"
        # Rice beta nie ma własnego motywu — bierze motyw rice'a bazowego.
        [[ -d "$theme" || "$rice" != *_beta ]] || theme="$SDDM_THEMES/archenemy-${rice%_beta}"
        if [[ -f "$theme/Main.qml" && ! -L "$theme" ]]; then
            if grep -q '^followWallpaper=1$' "$theme/theme.conf" 2>/dev/null \
                && path="$(wallpaper_path "$MON_SELECTOR")" && sync_wallpaper "$theme" "$path"; then
                background="user-wallpaper"
            else
                rm -f "$theme/user-wallpaper" "$theme/user-wallpaper.stamp"
            fi
            write_if_changed "$theme/theme.conf.user" "[General]
logo=$logo
distroGlyph=$GLYPH
loginScreen=$screen
background=$background" || { say "cannot write $theme/theme.conf.user"; return 1; }
            mkdir -p "${SDDM_DROPIN%/*}" || return 1
            write_if_changed "$SDDM_DROPIN" "# archenemy: login screen theme of the active rice. Written by
# /usr/local/lib/archenemy/system-theme-sync — remove with
# install/system-theme-installation.sh --remove
[Theme]
Current=${theme##*/}" || { say "cannot write $SDDM_DROPIN"; return 1; }
            say "login screen: ${theme##*/}, logo $logo, screen ${screen:-primary}, wallpaper ${background:-rice default}"
        else
            say "rice '$rice' has no installed login screen theme — login screen unchanged"
        fi
    fi

    # ── GRUB ──
    if [[ "$WITH_GRUB" == 1 ]]; then
        variant="$GRUB_THEME_DIR/theme-$rice-$logo.txt"
        [[ -f "$variant" || "$rice" != *_beta ]] || variant="$GRUB_THEME_DIR/theme-${rice%_beta}-$logo.txt"
        if [[ -f "$variant" && ! -L "$variant" ]]; then
            if ! cmp -s "$variant" "$GRUB_THEME_DIR/theme.txt"; then
                # Podmiana przez mv: GRUB nigdy nie widzi połowy pliku.
                if ! cp "$variant" "$GRUB_THEME_DIR/theme.txt.new" \
                    || ! mv -f "$GRUB_THEME_DIR/theme.txt.new" "$GRUB_THEME_DIR/theme.txt"; then
                    rm -f "$GRUB_THEME_DIR/theme.txt.new"
                    say "cannot write $GRUB_THEME_DIR/theme.txt"
                    return 1
                fi
            fi
            say "boot menu: ${variant##*/}"
        else
            say "rice '$rice' has no installed boot menu theme — boot menu unchanged"
        fi
    fi
    return 0
}

# Zmiana pliku stanu w trakcie pracy nie budzi usługi drugi raz (systemd nie
# kolejkuje zdarzeń .path dla działającej usługi) — stąd porównanie odcisku.
rc=0
for _ in 1 2 3; do
    before="$(fingerprint)"
    apply || rc=1
    [[ "$(fingerprint)" == "$before" ]] && break
done
exit "$rc"
