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
#   Uruchom: bash tests/wallpaper-switcher.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016  # check() robi eval na cytowanym wyrażeniu
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
chmod +x "$T/bin"/*
export PATH="$REPO/tests/mock:$T/bin:$PATH"
export MOCK_HYPRPAPER_STATE="$T/hyprpaper.state"
export MOCK_LOG="$T/log"

# ─── środowisko: $HOME/archenemy = skrypty z repo + własna warstwa maszynowa ──
H="$T/home"; A="$H/archenemy"
mkdir -p "$A/config/hypr" "$A/data/monitors" "$A/scripts/hypr" "$A/scripts/rofi" "$A/wallpapers/zestaw"
ln -s "$REPO/scripts/hypr/lib" "$A/scripts/hypr/lib"
ln -s "$REPO/scripts/rofi/rofi_wallpaper_switcher.sh" "$A/scripts/rofi/rofi_wallpaper_switcher.sh"
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

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
