#!/bin/bash
# =============================================
#   archenemy - tests/wallpaper-switcher.sh
#   Testy regresji przełącznika tapet (scripts/rofi/rofi_wallpaper_switcher.sh)
#   na ATRAPIE hyprctl + atrapie demona hyprpapera (tests/mock/hyprctl).
#   Bez Hyprlanda, bez roota, bez zapisu poza mktemp.
#
#   Powód powstania (2026-09-22): po przejściu warstwy maszynowej na selektory
#   desc: tapety przestały się zmieniać — hyprpaper dostawał polecenie IPC po
#   NAZWIE ZŁĄCZA, a w swojej liście ustawień miał wcześniejszy wpis z configu
#   po desc:, który wygrywał dopasowanie (pierwszy pasujący). Do tego stary
#   data/wallpaper.dat trzymał DRUGI wpis tego samego ekranu po nazwie złącza.
#   Oba przypadki mają tu test, który PADA na kodzie sprzed poprawki.
#
#   Zasada integralności warstwy maszynowej — trzy scenariusze .dat:
#     A. opis EDID dostępny      → selektor desc:,
#     B. brak opisu (stare .dat) → nazwa złącza (dawne zachowanie),
#     C. opisy nierozróżnialne   → nazwy złączy.
#
#   H–J (2026-09-25): podglądy PNG w menu (rofi_preview_menu, lib/
#   rofi-preview.sh) na atrapie rofi, która zapisuje stdin/argumenty i
#   odpowiada kolejną linią z $MOCK_ROFI_ANSWERS. Miniatury: atrapa
#   glycin-thumbnailer (liczy wywołania), cache po mtime, brak narzędzia.
#   Uruchom: bash tests/wallpaper-switcher.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

DESC_EDP="Thermotrex Corporation TL160ADMP03-0"
DESC_HDMI="Microstep MSI G241 0x00000603"

# ─── atrapy: demon hyprpapera (start/stop) + notify-send ─────────────────────
mkdir -p "$T/bin"
cat > "$T/bin/hyprpaper" <<'EOF'
#!/bin/bash
# Atrapa DEMONA: start = wczytanie hyprpaper.conf do stanu, w kolejności pliku
# (hyprpaper dodaje wpisy configu w tej samej kolejności — patrz mock/hyprctl).
conf="$HOME/archenemy/config/hypr/hyprpaper.conf"
: > "$MOCK_HYPRPAPER_STATE"
mon=""
while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*monitor[[:space:]]*=[[:space:]]*(.*)$ ]] && mon="${BASH_REMATCH[1]}"
    if [[ "$line" =~ ^[[:space:]]*path[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        printf '%s\t%s\n' "$mon" "${BASH_REMATCH[1]}" >> "$MOCK_HYPRPAPER_STATE"
    fi
done < "$conf"
echo "DAEMON start" >> "${MOCK_LOG:-/dev/null}"
EOF
cat > "$T/bin/pkill" <<'EOF'
#!/bin/bash
[[ "$*" == *hyprpaper* ]] && { rm -f "$MOCK_HYPRPAPER_STATE"; echo "DAEMON kill" >> "${MOCK_LOG:-/dev/null}"; exit 0; }
exit 1
EOF
cat > "$T/bin/pgrep" <<'EOF'
#!/bin/bash
[[ "$*" == *hyprpaper* && -f "$MOCK_HYPRPAPER_STATE" ]] && { echo 1234; exit 0; }
exit 1
EOF
cat > "$T/bin/notify-send" <<'EOF'
#!/bin/bash
echo "NOTIFY: $*" >> "${MOCK_LOG:-/dev/null}"
EOF
# rofi: zapisuje wejście (z bajtami \0/\x1f) i argumenty wywołania nr N,
# odpowiada N-tą linią $MOCK_ROFI_ANSWERS; pusta linia/brak = Esc (kod 1).
cat > "$T/bin/rofi" <<'MOCK'
#!/bin/bash
n=$(( $(cat "$MOCK_ROFI_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$MOCK_ROFI_DIR/count"
cat > "$MOCK_ROFI_DIR/in-$n"
printf '%s\n' "$@" > "$MOCK_ROFI_DIR/args-$n"
ans=$(sed -n "${n}p" "$MOCK_ROFI_ANSWERS" 2>/dev/null)
[[ -n "$ans" ]] || exit 1
printf '%s\n' "$ans"
MOCK
# glycin-thumbnailer (osobny katalog — scenariusz „brak narzędzia" wyjmuje
# go z PATH). Jak prawdziwy: przy błędzie kod 0 i brak pliku (MOCK_THUMB_FAIL=1).
mkdir -p "$T/thumbbin"
cat > "$T/thumbbin/glycin-thumbnailer" <<'MOCK'
#!/bin/bash
echo "GLYCIN $*" >> "$MOCK_LOG"
out=""
while (( $# )); do case "$1" in --output) out="$2"; shift 2 ;; *) shift ;; esac; done
[[ -n "${MOCK_THUMB_FAIL:-}" ]] && exit 0
printf 'PNGTHUMB' > "$out"
MOCK
chmod +x "$T/bin"/* "$T/thumbbin"/*
export PATH="$REPO/tests/mock:$T/bin:$T/thumbbin:$PATH"
export MOCK_HYPRPAPER_STATE="$T/hyprpaper.state"
export MOCK_LOG="$T/log"

# ─── środowisko: $HOME/archenemy = skrypty z repo + własna warstwa maszynowa ──
H="$T/home"; A="$H/archenemy"
mkdir -p "$A/config/hypr" "$A/data/monitors" "$A/scripts/hypr" "$A/scripts/rofi" "$A/wallpapers/zestaw"
ln -s "$REPO/scripts/hypr/lib" "$A/scripts/hypr/lib"
ln -s "$REPO/scripts/rofi/rofi_wallpaper_switcher.sh" "$A/scripts/rofi/rofi_wallpaper_switcher.sh"
ln -s "$REPO/scripts/rofi/lib" "$A/scripts/rofi/lib"
export HOME="$H"
SW="$A/scripts/rofi/rofi_wallpaper_switcher.sh"
WP="$A/wallpapers/zestaw"
for f in stara-v1.png stara-v2.png nowa-v1.png nowa-v2.png; do : > "$WP/$f"; done

# Warstwa maszynowa dla scenariusza; $1 = a|b|c
setup_dat() {
    rm -f "$A/data/monitors"/*.dat "$A/data/wallpaper.dat" "$A/config/hypr/hyprpaper.conf"
    case "$1" in
        a)  printf 'MONITOR=eDP-1\nROLE=secondary\nDESCRIPTION=%s\nORDER=1\n' "$DESC_EDP"  > "$A/data/monitors/eDP-1.dat"
            printf 'MONITOR=HDMI-A-3\nROLE=primary\nDESCRIPTION=%s\nORDER=2\n' "$DESC_HDMI" > "$A/data/monitors/HDMI-A-3.dat" ;;
        b)  printf 'MONITOR=eDP-1\nROLE=secondary\nORDER=1\n'  > "$A/data/monitors/eDP-1.dat"
            printf 'MONITOR=HDMI-A-3\nROLE=primary\nORDER=2\n' > "$A/data/monitors/HDMI-A-3.dat" ;;
        c)  printf 'MONITOR=DP-1\nROLE=primary\nORDER=1\n'   > "$A/data/monitors/DP-1.dat"
            printf 'MONITOR=DP-2\nROLE=secondary\nORDER=2\n' > "$A/data/monitors/DP-2.dat" ;;
    esac
}

# Demon wstaje z podanej treści hyprpaper.conf (jak po zalogowaniu do sesji).
boot_daemon_with() {
    printf '%s\n' "$1" > "$A/config/hypr/hyprpaper.conf"
    hyprpaper
}

active_of() {   # co hyprpaper POKAZUJE na monitorze $1
    hyprctl hyprpaper listactive | grep -m1 -F "$1: " | sed "s/^$1: //"
}

echo "== A: opis EDID (desc:) — zmiana tapety musi być widoczna"
setup_dat a
# Sesja startuje z configu wygenerowanego przy instalacji (klucze desc:)
boot_daemon_with "wallpaper {
    monitor = desc:$DESC_HDMI
    path = $WP/stara-v1.png
}
wallpaper {
    monitor = desc:$DESC_EDP
    path = $WP/stara-v2.png
}"
printf 'desc:%s=%s\ndesc:%s=%s\n' "$DESC_HDMI" "$WP/stara-v1.png" "$DESC_EDP" "$WP/stara-v2.png" > "$A/data/wallpaper.dat"
: > "$MOCK_LOG"
MOCK_MONS=both bash "$SW" "zestaw/nowa-v1.png" >/dev/null 2>&1
check "primary (HDMI) pokazuje nową tapetę"   '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/nowa-v1.png" ]]'
check "secondary (eDP) pokazuje parę v2"      '[[ "$(MOCK_MONS=both active_of eDP-1)" == "$WP/nowa-v2.png" ]]'
check "IPC poszło selektorem desc:, nie nazwą" 'grep -q "IPC wallpaper desc:$DESC_HDMI ->" "$MOCK_LOG"'
check "bez restartu demona (IPC wystarczyło)" '! grep -q "DAEMON kill" "$MOCK_LOG"'
check "powiadomienie o sukcesie"              'grep -q "NOTIFY: .*applied" "$MOCK_LOG"'

echo "== A2: stary wallpaper.dat po nazwach złączy (plik sprzed 2026-09-21)"
setup_dat a
boot_daemon_with "wallpaper {
    monitor = desc:$DESC_HDMI
    path = $WP/stara-v1.png
}
wallpaper {
    monitor = desc:$DESC_EDP
    path = $WP/stara-v2.png
}"
printf 'eDP-1=%s\nHDMI-A-3=%s\n' "$WP/stara-v2.png" "$WP/stara-v1.png" > "$A/data/wallpaper.dat"
: > "$MOCK_LOG"
MOCK_MONS=both bash "$SW" "zestaw/nowa-v1.png" >/dev/null 2>&1
check "jeden wpis na monitor w wallpaper.dat" '[[ $(wc -l < "$A/data/wallpaper.dat") -eq 2 ]]'
check "klucze przepisane na desc:"            '! grep -qE "^(eDP-1|HDMI-A-3)=" "$A/data/wallpaper.dat"'
check "hyprpaper.conf: 2 bloki, oba desc:"    '[[ $(grep -c "^wallpaper {" "$A/config/hypr/hyprpaper.conf") -eq 2 && $(grep -c "monitor = desc:" "$A/config/hypr/hyprpaper.conf") -eq 2 ]]'
check "ekran: nowa tapeta na obu monitorach"  '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/nowa-v1.png" && "$(MOCK_MONS=both active_of eDP-1)" == "$WP/nowa-v2.png" ]]'

echo "== A3: martwy wpis po starej nazwie złącza (eDP-2 sprzed zmiany)"
setup_dat a
boot_daemon_with "wallpaper {
    monitor = desc:$DESC_EDP
    path = $WP/stara-v2.png
}"
printf 'eDP-2=%s\ndesc:%s=%s\n' "$WP/stara-v1.png" "$DESC_EDP" "$WP/stara-v2.png" > "$A/data/wallpaper.dat"
: > "$MOCK_LOG"
MOCK_MONS=both bash "$SW" "zestaw/nowa-v1.png" >/dev/null 2>&1
check "wpis nieistniejącego złącza wypada"    '! grep -q "^eDP-2=" "$A/data/wallpaper.dat"'

echo "== B: stare .dat bez opisu — dawne zachowanie (klucz = nazwa złącza)"
setup_dat b
boot_daemon_with "wallpaper {
    monitor = HDMI-A-3
    path = $WP/stara-v1.png
}
wallpaper {
    monitor = eDP-1
    path = $WP/stara-v2.png
}"
printf 'HDMI-A-3=%s\neDP-1=%s\n' "$WP/stara-v1.png" "$WP/stara-v2.png" > "$A/data/wallpaper.dat"
: > "$MOCK_LOG"
MOCK_MONS=both bash "$SW" "zestaw/nowa-v1.png" >/dev/null 2>&1
check "klucze zostają nazwami złączy"         '[[ $(grep -c "^HDMI-A-3=\|^eDP-1=" "$A/data/wallpaper.dat") -eq 2 && ! -s <(grep "desc:" "$A/data/wallpaper.dat") ]]'
check "ekran: nowa tapeta na obu monitorach"  '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/nowa-v1.png" && "$(MOCK_MONS=both active_of eDP-1)" == "$WP/nowa-v2.png" ]]'

echo "== C: dwa identyczne monitory (bez desc: — install.sh [3])"
setup_dat c
boot_daemon_with "wallpaper {
    monitor = DP-1
    path = $WP/stara-v1.png
}
wallpaper {
    monitor = DP-2
    path = $WP/stara-v2.png
}"
printf 'DP-1=%s\nDP-2=%s\n' "$WP/stara-v1.png" "$WP/stara-v2.png" > "$A/data/wallpaper.dat"
: > "$MOCK_LOG"
MOCK_MONS=twins bash "$SW" "zestaw/nowa-v1.png" >/dev/null 2>&1
check "każdy bliźniak dostaje swoją połowę pary" '[[ "$(MOCK_MONS=twins active_of DP-1)" == "$WP/nowa-v1.png" && "$(MOCK_MONS=twins active_of DP-2)" == "$WP/nowa-v2.png" ]]'

echo "== D: monitor odpięty — jego wpis zostaje w configu, IPC go pomija"
setup_dat a
boot_daemon_with "wallpaper {
    monitor = desc:$DESC_EDP
    path = $WP/stara-v2.png
}"
printf 'desc:%s=%s\ndesc:%s=%s\n' "$DESC_HDMI" "$WP/stara-v1.png" "$DESC_EDP" "$WP/stara-v2.png" > "$A/data/wallpaper.dat"
: > "$MOCK_LOG"
MOCK_MONS=edp bash "$SW" "zestaw/nowa-v1.png" >/dev/null 2>&1
check "odpięty monitor: brak IPC"             '! grep -q "IPC wallpaper desc:$DESC_HDMI" "$MOCK_LOG"'
check "odpięty monitor: wpis czeka w configu" 'grep -q "monitor = desc:$DESC_HDMI" "$A/config/hypr/hyprpaper.conf"'
check "podpięty monitor: tapeta zmieniona"    '[[ "$(MOCK_MONS=edp active_of eDP-1)" == "$WP/nowa-v2.png" ]]'

echo "== E: demon nie żyje — restart czyta świeży config i to też sprawdzamy"
setup_dat a
printf 'desc:%s=%s\ndesc:%s=%s\n' "$DESC_HDMI" "$WP/stara-v1.png" "$DESC_EDP" "$WP/stara-v2.png" > "$A/data/wallpaper.dat"
rm -f "$MOCK_HYPRPAPER_STATE"    # hyprpaper padł
: > "$MOCK_LOG"
MOCK_MONS=both bash "$SW" "zestaw/nowa-v1.png" >/dev/null 2>&1
check "demon wystartował ponownie"            'grep -q "DAEMON start" "$MOCK_LOG"'
check "po restarcie ekran ma nową tapetę"     '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/nowa-v1.png" ]]'
check "sukces, nie fałszywy alarm"            'grep -q "NOTIFY: .*applied" "$MOCK_LOG" && ! grep -q "failed to apply" "$MOCK_LOG"'

echo "== F: --restore (Super+T) nie mnoży wpisów i przywraca to samo"
setup_dat a
boot_daemon_with "wallpaper {
    monitor = desc:$DESC_HDMI
    path = $WP/nowa-v1.png
}
wallpaper {
    monitor = desc:$DESC_EDP
    path = $WP/nowa-v2.png
}"
printf 'eDP-1=%s\ndesc:%s=%s\n' "$WP/nowa-v2.png" "$DESC_HDMI" "$WP/nowa-v1.png" > "$A/data/wallpaper.dat"
: > "$MOCK_LOG"
MOCK_MONS=both bash "$SW" --restore >/dev/null 2>&1
check "--restore: jeden wpis na monitor"      '[[ $(wc -l < "$A/data/wallpaper.dat") -eq 2 ]] && ! grep -q "^eDP-1=" "$A/data/wallpaper.dat"'
check "--restore: ekran bez zmian"            '[[ "$(MOCK_MONS=both active_of eDP-1)" == "$WP/nowa-v2.png" ]]'

echo "== G: --init (install.sh [9.5]) nie nadpisuje wyboru użytkownika"
# Audyt 2026-09-23: każdy ponowny bieg install.sh (zalecany po pullu) wołał
# przełącznik z PIERWSZYM plikiem z wallpapers/ i kasował wybór z Super+W.
setup_dat a
boot_daemon_with "wallpaper {
    monitor = desc:$DESC_HDMI
    path = $WP/nowa-v1.png
}
wallpaper {
    monitor = desc:$DESC_EDP
    path = $WP/nowa-v2.png
}"
printf 'desc:%s=%s\ndesc:%s=%s\n' "$DESC_HDMI" "$WP/nowa-v1.png" "$DESC_EDP" "$WP/nowa-v2.png" > "$A/data/wallpaper.dat"
out=$(MOCK_MONS=both bash "$SW" --init "$WP/stara-v1.png" 2>/dev/null)
check "--init z zapisanym wyborem → restored"  '[[ "$out" == *restored* ]]'
check "--init: wybór w .dat bez zmian"         'grep -q "nowa-v1.png" "$A/data/wallpaper.dat" && ! grep -q "stara" "$A/data/wallpaper.dat"'
check "--init: ekran dalej pokazuje wybór"     '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/nowa-v1.png" ]]'
setup_dat a
boot_daemon_with ""
out=$(MOCK_MONS=both bash "$SW" --init "$WP/stara-v1.png" 2>/dev/null)
check "--init bez stanu → initial"             '[[ "$out" == *initial* ]]'
check "--init bez stanu: pierwsza tapeta"      '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/stara-v1.png" ]]'
setup_dat a
printf 'desc:%s=%s\n' "$DESC_HDMI" "$WP/skasowana.png" > "$A/data/wallpaper.dat"
boot_daemon_with ""
out=$(MOCK_MONS=both bash "$SW" --init "$WP/stara-v1.png" 2>/dev/null)
check "--init ze stanem na skasowany plik → initial" '[[ "$out" == *initial* && "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/stara-v1.png" ]]'

# ─── H–J: podglądy w menu (atrapa rofi) ─────────────────────────────────────
export MOCK_ROFI_DIR="$T/rofi" MOCK_ROFI_ANSWERS="$T/rofi.answers"
THUMBS="$A/data/thumbs"
X1F=$'\x1f'
# menu ODPOWIEDZI... — uruchamia przełącznik z odpowiedziami rofi po kolei
menu() {
    rm -rf "$MOCK_ROFI_DIR"; mkdir -p "$MOCK_ROFI_DIR"
    printf '%s\n' "$@" > "$MOCK_ROFI_ANSWERS"
    MOCK_MONS=both bash "$SW" >/dev/null 2>&1
}
# wejście rofi nr $1 w czytelnej postaci: \0 → "|", \x1f → "#"
rofi_in() { tr '\000\037' '|#' < "$MOCK_ROFI_DIR/in-$1"; }
# ikona wpisu o etykiecie $2 w wejściu nr $1 (pusto = wpis bez ikony)
icon_of() { rofi_in "$1" | awk -v l="$2" 'index($0, l "|icon#") == 1 { print substr($0, length(l) + 7); exit }'; }
glycin_calls() { grep -c '^GLYCIN' "$MOCK_LOG"; }
n_thumbs() { find "$THUMBS" -name '*.png' 2>/dev/null | wc -l; }

echo "== H: Wallpapers/ — miniatury w data/thumbs/, cache po mtime"
setup_dat a
boot_daemon_with ""
mkdir -p "$A/wallpapers/inne"
: > "$A/wallpapers/inne/o'neil tapeta.png"
rm -rf "$THUMBS"; : > "$MOCK_LOG"
menu "Wallpapers/" ""
check "menu główne bez ikon i bez siatki"      '! grep -q "$X1F" "$MOCK_ROFI_DIR/in-1" && ! grep -q -- "-theme-str" "$MOCK_ROFI_DIR/args-1"'
check "← Back bez ikony"                      'rofi_in 2 | grep -qx "← Back"'
all_thumbs=1
for f in zestaw/stara-v1.png zestaw/nowa-v2.png "inne/o'neil tapeta.png"; do
    ic="$(icon_of 2 "$f")"
    [[ "$ic" == "$THUMBS"/*.png && -s "$ic" ]] || { all_thumbs=0; echo "    brak miniatury: $f → '$ic'"; }
done
check "każda tapeta ma ikonę = istniejąca miniatura"   '(( all_thumbs == 1 ))'
check "siatka: -show-icons + columns w -theme-str"    'grep -qx -- "-show-icons" "$MOCK_ROFI_DIR/args-2" && grep -q "columns: 3" "$MOCK_ROFI_DIR/args-2"'
check "glycin dostał URL (spacja/apostrof zakodowane)" 'grep -qF "file://$A/wallpapers/inne/o%27neil%20tapeta.png" "$MOCK_LOG"'
n_files=$(find "$A/wallpapers" -type f -name '*.png' | wc -l)
check "po jednej miniaturze na plik"           '[[ $(n_thumbs) -eq $n_files ]]'
: > "$MOCK_LOG"
menu "Wallpapers/" ""
check "drugie otwarcie: nic nie generuje"      '[[ $(glycin_calls) -eq 0 ]]'
old_icon="$(icon_of 2 zestaw/nowa-v1.png)"
touch -d '+1 min' "$WP/nowa-v1.png"
: > "$MOCK_LOG"
menu "Wallpapers/" ""
new_icon="$(icon_of 2 zestaw/nowa-v1.png)"
check "zmieniony plik: dokładnie jedna nowa miniatura" '[[ $(glycin_calls) -eq 1 && "$new_icon" != "$old_icon" && -s "$new_icon" ]]'
check "zmieniony plik: stara miniatura skasowana"      '[[ ! -e "$old_icon" && $(n_thumbs) -eq $n_files ]]'
check "brak plików tymczasowych w data/thumbs"         '[[ -z "$(find "$THUMBS" -name ".gen-*")" ]]'

echo "== I: miniatura niemożliwa → ikoną jest oryginał, menu działa"
rm -rf "$THUMBS"
MOCK_THUMB_FAIL=1 menu "Wallpapers/" ""
check "błąd narzędzia (kod 0, brak pliku): oryginał"   '[[ "$(icon_of 2 zestaw/stara-v1.png)" == "$WP/stara-v1.png" ]]'
check "błąd narzędzia: nic nie zostaje w data/thumbs"  '[[ -z "$(find "$THUMBS" -type f 2>/dev/null)" ]]'
# PATH bez żadnego narzędzia do miniatur: farma dowiązań do /usr/bin i /bin
# bez glycin-thumbnailer / gdk-pixbuf-thumbnailer / magick.
mkdir -p "$T/sysbin"
for d in /usr/bin /bin; do
    for b in "$d"/*; do
        n="${b##*/}"
        case "$n" in glycin-thumbnailer|gdk-pixbuf-thumbnailer|magick) continue ;; esac
        [[ -e "$T/sysbin/$n" || -L "$T/sysbin/$n" ]] || ln -s "$b" "$T/sysbin/$n"
    done
done
rm -rf "$THUMBS"; : > "$MOCK_LOG"
PATH="$REPO/tests/mock:$T/bin:$T/sysbin" menu "Wallpapers/" ""
check "brak narzędzia: oryginał jako ikona"    '[[ "$(icon_of 2 zestaw/stara-v1.png)" == "$WP/stara-v1.png" ]]'
check "brak narzędzia: menu mimo to pokazane"  '[[ "$(icon_of 2 "inne/o'"'"'neil tapeta.png")" == "$A/wallpapers/inne/o'"'"'neil tapeta.png" ]]'
rm -rf "$A/wallpapers/inne"

echo "== J: Animations/ — kadry previews/<aktywny rice>/<animacja>.png"
SH="$A/src/flux-wall/shaders"
mkdir -p "$A/scripts/wallpapers" "$A/src/flux-wall/build" "$SH/previews/testrice"
ln -sf "$REPO/scripts/wallpapers/flux-wall.sh" "$A/scripts/wallpapers/flux-wall.sh"
printf '#!/bin/bash\nexit 0\n' > "$A/src/flux-wall/build/flux-wall"; chmod +x "$A/src/flux-wall/build/flux-wall"
for n in plain nopreview "orb-spinnin'"; do printf 'void main(){}\n' > "$SH/$n.frag"; done
printf '#pragma flux audio 1\n' > "$SH/orb-spinnin'.update.glsl"
printf 'PNG' > "$SH/previews/testrice/plain.png"
printf 'PNG' > "$SH/previews/testrice/orb-spinnin'.png"
echo testrice > "$A/.current_rice"
menu "Animations/" ""
check "animacja z kadrem ma ikonę"             '[[ "$(icon_of 2 plain)" == "$SH/previews/testrice/plain.png" ]]'
check "apostrof + dopisek ♪: ikona z kadrem"   '[[ "$(icon_of 2 "orb-spinnin'"'"'   ♪ music visualisation")" == "$SH/previews/testrice/orb-spinnin'"'"'.png" ]]'
check "animacja bez kadru: wpis bez zmian"     'rofi_in 2 | grep -qx "nopreview"'
check "← Back bez ikony, siatka włączona"      'rofi_in 2 | grep -qx "← Back" && grep -q "columns: 3" "$MOCK_ROFI_DIR/args-2"'
echo norice > "$A/.current_rice"
menu "Animations/" ""
check "rice bez kadrów: zwykła lista, zero ikon" '! grep -q "$X1F" "$MOCK_ROFI_DIR/in-2" && ! grep -q -- "-theme-str" "$MOCK_ROFI_DIR/args-2" && rofi_in 2 | grep -qx "plain"'

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
