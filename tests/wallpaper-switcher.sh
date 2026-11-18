#!/usr/bin/env bash
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
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

DESC_EDP="Thermotrex Corporation TL160ADMP03-0"
DESC_HDMI="Microstep MSI G241 0x00000603"
DESC_DP3="Dell U2720Q ABC123"

# ─── atrapy: demon hyprpapera (start/stop) + notify-send ─────────────────────
mkdir -p "$T/bin"
cat > "$T/bin/hyprpaper" <<'EOF'
#!/usr/bin/env bash
# Atrapa DEMONA: start = wczytanie hyprpaper.conf do stanu, w kolejności pliku
# (hyprpaper dodaje wpisy configu w tej samej kolejności — patrz mock/hyprctl).
conf="$HOME/archenemy/config/hypr/hyprpaper.conf"
# Log przed stanem: wołający widzi demona (pgrep) dopiero, gdy stan istnieje.
echo "DAEMON start" >> "${MOCK_LOG:-/dev/null}"
# Własna sesja (SID = PID) = brak terminala sterującego, więc zamknięcie okna
# TUI, z którego poszedł restart, nie zabije demona (SIGHUP).
[[ "$(awk '{print $6}' "/proc/$$/stat")" == "$$" ]] && echo "DAEMON own-session" >> "${MOCK_LOG:-/dev/null}"
: > "$MOCK_HYPRPAPER_STATE"
mon=""
while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*monitor[[:space:]]*=[[:space:]]*(.*)$ ]] && mon="${BASH_REMATCH[1]}"
    if [[ "$line" =~ ^[[:space:]]*path[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        printf '%s\t%s\n' "$mon" "${BASH_REMATCH[1]}" >> "$MOCK_HYPRPAPER_STATE"
    fi
done < "$conf"
EOF
cat > "$T/bin/pkill" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *hyprpaper* ]] && { rm -f "$MOCK_HYPRPAPER_STATE"; echo "DAEMON kill" >> "${MOCK_LOG:-/dev/null}"; exit 0; }
exit 1
EOF
cat > "$T/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *hyprpaper* && -f "$MOCK_HYPRPAPER_STATE" ]] && { echo 1234; exit 0; }
exit 1
EOF
cat > "$T/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
echo "NOTIFY: $*" >> "${MOCK_LOG:-/dev/null}"
EOF
# rofi: zapisuje wejście (z bajtami \0/\x1f) i argumenty wywołania nr N,
# odpowiada N-tą linią $MOCK_ROFI_ANSWERS; pusta linia/brak = Esc (kod 1).
cat > "$T/bin/rofi" <<'MOCK'
#!/usr/bin/env bash
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
#!/usr/bin/env bash
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
ln -s "$REPO/scripts/lib" "$A/scripts/lib"   # lib/runtime-dir.sh — katalog sesji (S12)
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
        three) setup_dat a
            printf 'MONITOR=DP-3\nROLE=other\nDESCRIPTION=%s\nORDER=3\n' "$DESC_DP3" > "$A/data/monitors/DP-3.dat" ;;
    esac
}

# Demon wstaje z podanej treści hyprpaper.conf (jak po zalogowaniu do sesji).
boot_daemon_with() {
    printf '%s\n' "$1" > "$A/config/hypr/hyprpaper.conf"
    hyprpaper
}

active_of() {   # co hyprpaper POKAZUJE na monitorze $1 (nazwa od początku linii: DP-1 ≠ eDP-1)
    local line
    while IFS= read -r line; do
        [[ "$line" == "$1: "* ]] && { printf '%s\n' "${line#"$1": }"; return; }
    done < <(hyprctl hyprpaper listactive)
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

echo "== C2: eDP-1 i DP-1 naraz — nazwa złącza to przyrostek drugiej (A1, audyt 2026-11-05)"
# listactive wypisuje eDP-1 przed DP-1; dopasowanie „DP-1: ” bez kotwicy brało
# linię eDP-1, więc zgodny ekran wyglądał na rozjazd: restart demona i fałszywe
# „failed to apply”.
printf 'MONITOR=eDP-1\nROLE=secondary\nORDER=1\n' > "$A/data/monitors/eDP-1.dat"
printf 'MONITOR=DP-1\nROLE=primary\nORDER=2\n'   > "$A/data/monitors/DP-1.dat"
rm -f "$A/data/monitors/DP-2.dat"
boot_daemon_with "wallpaper {
    monitor = eDP-1
    path = $WP/stara-v2.png
}
wallpaper {
    monitor = DP-1
    path = $WP/stara-v1.png
}"
printf 'eDP-1=%s\nDP-1=%s\n' "$WP/stara-v2.png" "$WP/stara-v1.png" > "$A/data/wallpaper.dat"
: > "$MOCK_LOG"
MOCK_MONS=edpdp bash "$SW" "zestaw/nowa-v1.png" >/dev/null 2>&1
check "DP-1 (primary) pokazuje v1, eDP-1 v2"    '[[ "$(MOCK_MONS=edpdp active_of DP-1)" == "$WP/nowa-v1.png" && "$(MOCK_MONS=edpdp active_of eDP-1)" == "$WP/nowa-v2.png" ]]'
check "zgodny ekran: bez restartu demona"     '! grep -q "DAEMON kill" "$MOCK_LOG"'
check "zgodny ekran: sukces, nie 'failed'"    'grep -q "NOTIFY: .*applied" "$MOCK_LOG" && ! grep -q "failed to apply" "$MOCK_LOG"'

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
check "restart we własnej sesji (A3: przeżyje zamknięcie okna TUI)" 'grep -q "DAEMON own-session" "$MOCK_LOG"'
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

echo "== F2: trzeci monitor (Super+A → [n] dodaje .dat)"
# Dawniej przełącznik znał tylko primary i secondary: trzeci ekran zostawał bez
# tapety, a przy fokusie na nim wybór lądował na primary.
setup_dat three
boot_daemon_with "wallpaper {
    monitor = desc:$DESC_HDMI
    path = $WP/stara-v1.png
}
wallpaper {
    monitor = desc:$DESC_EDP
    path = $WP/stara-v2.png
}"
printf 'desc:%s=%s\ndesc:%s=%s\n' "$DESC_HDMI" "$WP/stara-v1.png" "$DESC_EDP" "$WP/stara-v2.png" > "$A/data/wallpaper.dat"
MOCK_MONS=three bash "$SW" --restore >/dev/null 2>&1
check "--restore: nowy monitor dostaje tapetę secondary" '[[ "$(MOCK_MONS=three active_of DP-3)" == "$WP/stara-v2.png" ]]'
check "--restore: zapisane tapety bez zmian"  '[[ "$(MOCK_MONS=three active_of HDMI-A-3)" == "$WP/stara-v1.png" && "$(MOCK_MONS=three active_of eDP-1)" == "$WP/stara-v2.png" ]]'
check "--restore: wpis nowego monitora w wallpaper.dat" 'grep -qxF "desc:$DESC_DP3=$WP/stara-v2.png" "$A/data/wallpaper.dat"'
MOCK_MONS=three bash "$SW" "zestaw/nowa-v1.png" >/dev/null 2>&1
check "wszystkie monitory: primary v1, reszta v2" '[[ "$(MOCK_MONS=three active_of HDMI-A-3)" == "$WP/nowa-v1.png" && "$(MOCK_MONS=three active_of eDP-1)" == "$WP/nowa-v2.png" && "$(MOCK_MONS=three active_of DP-3)" == "$WP/nowa-v2.png" ]]'
MOCK_MONS=three bash "$SW" "zestaw" >/dev/null 2>&1
check "folder zestawu: trzeci monitor też"    '[[ "$(MOCK_MONS=three active_of DP-3)" == *"-v2.png" ]]'

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
# Z10 (audyt 2026-11-05): „initial” leciało PRZED ustawieniem tapety, więc
# install.sh meldował „✓ Initial wallpaper applied”, choć hyprpaper nic nie
# pokazał. Demon, który nie wstaje (IPC milczy, restart nie pomaga): wynik
# dopiero po apply_ipc, z dopiskiem -failed.
mkdir -p "$T/bin-deadpaper"
printf '#!/usr/bin/env bash\necho "DAEMON dead" >> "${MOCK_LOG:-/dev/null}"\nexit 1\n' > "$T/bin-deadpaper/hyprpaper"
chmod +x "$T/bin-deadpaper/hyprpaper"
setup_dat a
rm -f "$MOCK_HYPRPAPER_STATE"
out=$(PATH="$T/bin-deadpaper:$PATH" MOCK_MONS=both bash "$SW" --init "$WP/stara-v1.png" 2>/dev/null)
check "--init, hyprpaper nie wstaje → initial-failed" '[[ "$out" == initial-failed ]]'
printf 'desc:%s=%s\n' "$DESC_HDMI" "$WP/nowa-v1.png" > "$A/data/wallpaper.dat"
out=$(PATH="$T/bin-deadpaper:$PATH" MOCK_MONS=both bash "$SW" --init "$WP/stara-v1.png" 2>/dev/null)
check "--init ze stanem, hyprpaper nie wstaje → restored-failed" '[[ "$out" == restored-failed ]]'
setup_dat a
boot_daemon_with ""
out=$(MOCK_MONS=both bash "$SW" --init "$WP/stara-v1.png" 2>/dev/null)
check "--init: tapeta na ekranie → dokładnie initial" '[[ "$out" == initial ]]'

echo "== K: wszystkie monitory, tapeta dither-flux — para z nazwy wybranego pliku (A7)"
# generated/ trzyma kilka form i rozdzielczości w jednym katalogu; dawne
# `find -iname "*v2*" | head -n1` dawało drugiemu monitorowi tę samą, przypadkową
# formę dla każdego wyboru (kolejność katalogu, różna między maszynami).
setup_dat a
sed -i '$a RESOLUTION=2560x1600' "$A/data/monitors/eDP-1.dat"
G="$A/wallpapers/dither-flux/generated"; mkdir -p "$G"
for f in atraktor-v1-1920x1080 atraktor-v2-1920x1200 atraktor-v2-2560x1600 \
         przeplyw-v1-1920x1080 przeplyw-v2-2560x1600 przeplyw2-v1-1920x1080 przeplyw2-v2-2560x1600; do
    : > "$G/dither-flux-$f.png"
done
boot_daemon_with ""
pair_ok=1
for form in atraktor przeplyw przeplyw2; do
    MOCK_MONS=both bash "$SW" "dither-flux/generated/dither-flux-$form-v1-1920x1080.png" >/dev/null 2>&1
    p="$(MOCK_MONS=both active_of HDMI-A-3)"; s2="$(MOCK_MONS=both active_of eDP-1)"
    if [[ "$p" != "$G/dither-flux-$form-v1-1920x1080.png" || "$s2" != "$G/dither-flux-$form-v2-2560x1600.png" ]]; then
        pair_ok=0; echo "    $form: primary ${p##*/}, secondary ${s2##*/}"
    fi
done
check "v1 wybranej formy na primary, v2 TEJ SAMEJ formy na secondary" '(( pair_ok == 1 ))'
MOCK_MONS=both bash "$SW" "dither-flux/generated/dither-flux-atraktor-v1-1920x1080.png" >/dev/null 2>&1
check "z dwóch v2 tej formy: rozdzielczość monitora z .dat" '[[ "$(MOCK_MONS=both active_of eDP-1)" == "$G/dither-flux-atraktor-v2-2560x1600.png" ]]'
MOCK_MONS=both bash "$SW" "dither-flux/generated/dither-flux-przeplyw-v2-2560x1600.png" >/dev/null 2>&1
check "wybór v2: primary dostaje v1 tej samej formy" '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$G/dither-flux-przeplyw-v1-1920x1080.png" && "$(MOCK_MONS=both active_of eDP-1)" == "$G/dither-flux-przeplyw-v2-2560x1600.png" ]]'
: > "$G/dither-flux-samotna-v1-1920x1080.png"
MOCK_MONS=both bash "$SW" "dither-flux/generated/dither-flux-samotna-v1-1920x1080.png" >/dev/null 2>&1
check "forma bez pary: ten sam plik na obu"     '[[ "$(MOCK_MONS=both active_of eDP-1)" == "$G/dither-flux-samotna-v1-1920x1080.png" ]]'
rm -rf "$A/wallpapers/dither-flux"
# Inne rozszerzenie to dalej ta sama para (przegląd A7, R1): city-v1.jpg +
# city-v2.png. Rozszerzenie rozstrzyga tylko remis, a para musi być obrazem.
M="$A/wallpapers/miasto"; mkdir -p "$M"
: > "$M/city-v1.jpg"; : > "$M/city-v2.txt"
MOCK_MONS=both bash "$SW" "miasto/city-v1.jpg" >/dev/null 2>&1
check "plik, który nie jest obrazem, nie jest parą" '[[ "$(MOCK_MONS=both active_of eDP-1)" == "$M/city-v1.jpg" ]]'
: > "$M/city-v2.png"
MOCK_MONS=both bash "$SW" "miasto/city-v1.jpg" >/dev/null 2>&1
check "para z innym rozszerzeniem: city-v1.jpg + city-v2.png" '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$M/city-v1.jpg" && "$(MOCK_MONS=both active_of eDP-1)" == "$M/city-v2.png" ]]'
: > "$M/city-v2.jpg"
MOCK_MONS=both bash "$SW" "miasto/city-v1.jpg" >/dev/null 2>&1
check "remis nazw: wygrywa to samo rozszerzenie" '[[ "$(MOCK_MONS=both active_of eDP-1)" == "$M/city-v2.jpg" ]]'
rm -rf "$M"

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

echo '== L: menu — „Upload to all monitors” i monitor z fokusem (T7)'
# Skutek na ekranie (listactive atrapy), nie tekst powiadomienia. W atrapie
# fokus ma eDP-1 (secondary), primary to HDMI-A-3.
start_old() {
    setup_dat a
    boot_daemon_with "wallpaper {
    monitor = desc:$DESC_HDMI
    path = $WP/stara-v1.png
}
wallpaper {
    monitor = desc:$DESC_EDP
    path = $WP/stara-v2.png
}"
    printf 'desc:%s=%s\ndesc:%s=%s\n' "$DESC_HDMI" "$WP/stara-v1.png" "$DESC_EDP" "$WP/stara-v2.png" > "$A/data/wallpaper.dat"
}
start_old
menu "Wallpapers/" "zestaw/nowa-v1.png"
check "domyślnie wszystkie: primary v1, secondary v2"  '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/nowa-v1.png" && "$(MOCK_MONS=both active_of eDP-1)" == "$WP/nowa-v2.png" ]]'
start_old
menu "[x] Upload to all monitors" "Wallpapers/" "zestaw/nowa-v1.png"
check "odznaczone: tylko monitor z fokusem dostaje plik" '[[ "$(MOCK_MONS=both active_of eDP-1)" == "$WP/nowa-v1.png" ]]'
check "odznaczone: drugi monitor bez zmian"            '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/stara-v1.png" ]] && grep -qxF "desc:$DESC_HDMI=$WP/stara-v1.png" "$A/data/wallpaper.dat"'

echo "== M: menu — tło hyprlocka bez rozmycia i powrót do zrzutu (T7)"
LB=("$A/config/hypr/hyprlock-background-white-blue.conf" "$A/config/hypr/hyprlock-background-tron.conf")
lock_default() {
    local f
    for f in "${LB[@]}"; do
        printf 'background {\n    monitor =\n    path = screenshot\n    blur_size = 7\n    blur_passes = 3\n    brightness = 0.55\n}\n' > "$f"
    done
    rm -f "$A/data/hyprlock-wallpaper.dat"
}
# wszystkie pliki tła mają path=$1, blur_size=$2, blur_passes=$3 i nietkniętą jasność
lock_is() {
    local f
    for f in "${LB[@]}"; do
        grep -qxF "    path = $1" "$f" && grep -qxF "    blur_size = $2" "$f" && grep -qxF "    blur_passes = $3" "$f" \
            && grep -qxF "    brightness = 0.55" "$f" || return 1
    done
}
start_old; lock_default
menu "Wallpapers/" "zestaw/nowa-v1.png"
check "ptaszek odznaczony (domyślnie): hyprlock dalej na zrzucie" 'lock_is screenshot 7 3'
menu "[ ] Set as hyprlock background (no blur)" "Wallpapers/" "zestaw/nowa-v2.png"
check "zaznaczony: tło = wybrany plik, bez rozmycia, jasność rice'a zostaje" 'lock_is "$WP/nowa-v2.png" 0 0'
check "zaznaczony: wybór zapisany w hyprlock-wallpaper.dat" '[[ "$(<"$A/data/hyprlock-wallpaper.dat")" == "$WP/nowa-v2.png" ]]'
menu "Wallpapers/" "zestaw/stara-v1.png"
check "ptaszek zapamiętany: kolejny wybór też idzie na hyprlock" 'lock_is "$WP/stara-v1.png" 0 0'
for f in "${LB[@]}"; do sed -i 's|^    path = .*|    path = screenshot|' "$f"; done
MOCK_MONS=both bash "$SW" --restore >/dev/null 2>&1
check "--restore (Super+T) przywraca tło hyprlocka"    'lock_is "$WP/stara-v1.png" 0 0'
menu "[x] Set as hyprlock background (no blur)" "Wallpapers/" "zestaw/nowa-v1.png"
check "odznaczony: powrót do zrzutu z rozmyciem"       'lock_is screenshot 7 3 && [[ "$(<"$A/data/hyprlock-wallpaper.dat")" == off ]]'
rm -f "${LB[@]}" "$A/data/hyprlock-wallpaper.dat"

echo "== N: zapisany wybór arch-white (logo Arch, usunięte 2026-11-17) → blue-hex"
# Stare pliki NIE istnieją (w repo zostały tylko przejściowe symlinki, tu ich
# nie ma) — więc zielony wynik dowodzi migracji ścieżek, nie symlinków.
OLDW="$A/wallpapers/arch-white"; NEWW="$A/wallpapers/blue-hex"
mkdir -p "$NEWW"; : > "$NEWW/blue-hex-v1-1920x1080.png"; : > "$NEWW/blue-hex-v2-2560x1600.png"
setup_dat a; lock_default
boot_daemon_with "wallpaper {
    monitor = desc:$DESC_HDMI
    path = $OLDW/arch-logo-v1-1920x1080.png
}"
printf 'desc:%s=%s\ndesc:%s=%s\n' "$DESC_HDMI" "$OLDW/arch-logo-v1-1920x1080.png" "$DESC_EDP" "$OLDW/arch-logo-v2-2560x1600.png" > "$A/data/wallpaper.dat"
printf '%s\n' "$OLDW/arch-logo-v1-1920x1080.png" > "$A/data/hyprlock-wallpaper.dat"
out=$(MOCK_MONS=both bash "$SW" --init "$WP/stara-v1.png" 2>/dev/null)
check "--init ze starym wyborem → restored (nie pierwsza tapeta)" '[[ "$out" == restored ]]'
check "wallpaper.dat: nowe ścieżki, zero arch-white"  'grep -qxF "desc:$DESC_HDMI=$NEWW/blue-hex-v1-1920x1080.png" "$A/data/wallpaper.dat" && grep -qxF "desc:$DESC_EDP=$NEWW/blue-hex-v2-2560x1600.png" "$A/data/wallpaper.dat" && ! grep -q arch-white "$A/data/wallpaper.dat"'
check "hyprpaper.conf bez arch-white"                 '! grep -q arch-white "$A/config/hypr/hyprpaper.conf"'
check "ekran pokazuje blue-hex v1 / v2"               '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$NEWW/blue-hex-v1-1920x1080.png" && "$(MOCK_MONS=both active_of eDP-1)" == "$NEWW/blue-hex-v2-2560x1600.png" ]]'
check "tło hyprlocka i jego stan przepisane"          'lock_is "$NEWW/blue-hex-v1-1920x1080.png" 0 0 && [[ "$(<"$A/data/hyprlock-wallpaper.dat")" == "$NEWW/blue-hex-v1-1920x1080.png" ]]'
# Najstarszy format wallpaper.dat: sama nazwa zestawu.
setup_dat a; lock_default
printf 'arch-white\n' > "$A/data/wallpaper.dat"
MOCK_MONS=both bash "$SW" --restore >/dev/null 2>&1
check "stary format (sama nazwa arch-white) → zestaw blue-hex"   'grep -qxF "desc:$DESC_HDMI=$NEWW/blue-hex-v1-1920x1080.png" "$A/data/wallpaper.dat" && ! grep -q arch-white "$A/data/wallpaper.dat"'
# Plik użytkownika o tej samej nazwie, ale spoza wallpapers/arch-white/, zostaje.
setup_dat a; : > "$WP/arch-logo-v1-1920x1080.png"
printf 'desc:%s=%s\n' "$DESC_HDMI" "$WP/arch-logo-v1-1920x1080.png" > "$A/data/wallpaper.dat"
MOCK_MONS=both bash "$SW" --restore >/dev/null 2>&1
check "ta sama nazwa w innym folderze bez zmian"      'grep -qxF "desc:$DESC_HDMI=$WP/arch-logo-v1-1920x1080.png" "$A/data/wallpaper.dat"'
rm -f "$WP/arch-logo-v1-1920x1080.png"
rm -rf "$NEWW" "${LB[@]}" "$A/data/hyprlock-wallpaper.dat"

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
printf '#!/usr/bin/env bash\nexit 0\n' > "$A/src/flux-wall/build/flux-wall"; chmod +x "$A/src/flux-wall/build/flux-wall"
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

echo "== J2: Animations/ → flux-wall.sh select: do flux-wall.dat tylko istniejąca animacja (T7)"
# rofi -dmenu oddaje też wpisany tekst bez dopasowania; nazwa staje się ścieżką
# shadera, więc select sprawdza ją, zanim cokolwiek zapisze.
echo plain > "$A/data/flux-wall.dat"
menu "Animations/" "orb-spinnin'   ♪ music visualisation"
check "wybór z menu w flux-wall.dat (apostrof, bez dopisku ♪)" '[[ "$(<"$A/data/flux-wall.dat")" == "orb-spinnin'"'"'" ]]'
bad_kept=1
for bad in "nie-ma-takiej" "../shaders/plain" "Plain" "plain;x"; do
    echo plain > "$A/data/flux-wall.dat"; : > "$MOCK_LOG"
    menu "Animations/" "$bad"
    if [[ "$(<"$A/data/flux-wall.dat")" != plain ]] || ! grep -q "NOTIFY: .*failed to start" "$MOCK_LOG"; then
        bad_kept=0; echo "    '$bad' → flux-wall.dat: $(<"$A/data/flux-wall.dat")"
    fi
done
check "zła nazwa (brak pliku, ../, wielkie litery, ;): wybór bez zmian, krytyczne powiadomienie" '(( bad_kept == 1 ))'

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
