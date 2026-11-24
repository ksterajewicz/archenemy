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
    MOCK_MONS="${MENU_MONS:-both}" bash "$SW" >/dev/null 2>&1
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
menu "Wallpapers/" "zestaw/nowa"
check "domyślnie wszystkie: primary v1, secondary v2"  '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$WP/nowa-v1.png" && "$(MOCK_MONS=both active_of eDP-1)" == "$WP/nowa-v2.png" ]]'
start_old
menu "[x] Upload to all monitors" "Wallpapers/" "zestaw/nowa"
# Kafel = wariant pod primary (v1); od 2026-11-24 (sekcja O) monitor z fokusem
# dostaje wariant pod siebie — tu secondary, więc v2 tego samego obrazu.
check "odznaczone: tylko monitor z fokusem dostaje plik (swój wariant v2)" '[[ "$(MOCK_MONS=both active_of eDP-1)" == "$WP/nowa-v2.png" ]]'
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
menu "Wallpapers/" "zestaw/nowa"
check "ptaszek odznaczony (domyślnie): hyprlock dalej na zrzucie" 'lock_is screenshot 7 3'
# Wpisana ścieżka pliku (nie podpis kafla) dalej działa — tu wariant v2.
menu "[ ] Set as hyprlock background (no blur)" "Wallpapers/" "zestaw/nowa-v2.png"
check "zaznaczony: tło = wybrany plik, bez rozmycia, jasność rice'a zostaje" 'lock_is "$WP/nowa-v2.png" 0 0'
check "zaznaczony: wybór zapisany w hyprlock-wallpaper.dat" '[[ "$(<"$A/data/hyprlock-wallpaper.dat")" == "$WP/nowa-v2.png" ]]'
menu "Wallpapers/" "zestaw/stara"
check "ptaszek zapamiętany: kolejny wybór też idzie na hyprlock" 'lock_is "$WP/stara-v1.png" 0 0'
for f in "${LB[@]}"; do sed -i 's|^    path = .*|    path = screenshot|' "$f"; done
MOCK_MONS=both bash "$SW" --restore >/dev/null 2>&1
check "--restore (Super+T) przywraca tło hyprlocka"    'lock_is "$WP/stara-v1.png" 0 0'
menu "[x] Set as hyprlock background (no blur)" "Wallpapers/" "zestaw/nowa"
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
# Kafle: po jednym na obraz (para v1/v2 = jeden kafel, sekcja O), podpis =
# nazwa obrazu (sekcja P).
for f in zestaw/stara zestaw/nowa "inne/o'neil tapeta"; do
    ic="$(icon_of 2 "$f")"
    [[ "$ic" == "$THUMBS"/*.png && -s "$ic" ]] || { all_thumbs=0; echo "    brak miniatury: $f → '$ic'"; }
done
check "każda tapeta ma ikonę = istniejąca miniatura"   '(( all_thumbs == 1 ))'
check "siatka: -show-icons + columns w -theme-str"    'grep -qx -- "-show-icons" "$MOCK_ROFI_DIR/args-2" && grep -q "columns: 3" "$MOCK_ROFI_DIR/args-2"'
check "glycin dostał URL (spacja/apostrof zakodowane)" 'grep -qF "file://$A/wallpapers/inne/o%27neil%20tapeta.png" "$MOCK_LOG"'
n_files=$(rofi_in 2 | grep -c '|icon#')
check "po jednej miniaturze na kafel (3: stara, nowa, o'neil)" '[[ $n_files -eq 3 && $(n_thumbs) -eq $n_files ]]'
: > "$MOCK_LOG"
menu "Wallpapers/" ""
check "drugie otwarcie: nic nie generuje"      '[[ $(glycin_calls) -eq 0 ]]'
old_icon="$(icon_of 2 zestaw/nowa)"
touch -d '+1 min' "$WP/nowa-v1.png"
: > "$MOCK_LOG"
menu "Wallpapers/" ""
new_icon="$(icon_of 2 zestaw/nowa)"
check "zmieniony plik: dokładnie jedna nowa miniatura" '[[ $(glycin_calls) -eq 1 && "$new_icon" != "$old_icon" && -s "$new_icon" ]]'
check "zmieniony plik: stara miniatura skasowana"      '[[ ! -e "$old_icon" && $(n_thumbs) -eq $n_files ]]'
check "brak plików tymczasowych w data/thumbs"         '[[ -z "$(find "$THUMBS" -name ".gen-*")" ]]'

echo "== I: miniatura niemożliwa → ikoną jest oryginał, menu działa"
rm -rf "$THUMBS"
MOCK_THUMB_FAIL=1 menu "Wallpapers/" ""
check "błąd narzędzia (kod 0, brak pliku): oryginał"   '[[ "$(icon_of 2 zestaw/stara)" == "$WP/stara-v1.png" ]]'
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
check "brak narzędzia: oryginał jako ikona"    '[[ "$(icon_of 2 zestaw/stara)" == "$WP/stara-v1.png" ]]'
check "brak narzędzia: menu mimo to pokazane"  '[[ "$(icon_of 2 "inne/o'"'"'neil tapeta")" == "$A/wallpapers/inne/o'"'"'neil tapeta.png" ]]'
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

echo "== O: Wallpapers/ bez duplikatów po kolejnych aktualizacjach (zgłoszenie 2026-11-24)"
# Objaw ze zrzutu właściciela: crt-scope-v1 i -v2, blue-hex-v1 i -v2 oraz wiele
# kafli dither-flux/generated/… — ten sam obraz kilka razy. Przyczyny: (1) menu
# pokazywało KAŻDY plik, a każdy zestaw z repo to para v1/v2 (każda aktualizacja
# z nowym zestawem dokładała dwa kafle); (2) install.sh [9.7] i Super+A → [n]
# generują trzy formy dither-flux pod KAŻDĄ parę tag:rozdzielczość z
# data/monitors i nic nie sprzątało plików pod monitory, których już nie ma
# (dok/bez doku, zmiana trybu, rola other po nazwie złącza).
# Symulacja: instalacja w doku → aktualizacja + install.sh bez doku →
# aktualizacja z nowym zestawem + install.sh w doku z trzecim monitorem.
rm -rf "$A/wallpapers"; mkdir -p "$A/wallpapers"
W="$A/wallpapers"; G="$W/dither-flux/generated"
mkdir -p "$W/crt" "$W/blue-hex" "$W/arch-white" "$W/own"
: > "$W/crt/crt-scope-v1-1920x1080.png"; : > "$W/crt/crt-scope-v2-2560x1600.png"
: > "$W/blue-hex/blue-hex-v1-1920x1080.png"; : > "$W/blue-hex/blue-hex-v2-2560x1600.png"
ln -s ../blue-hex/blue-hex-v1-1920x1080.png "$W/arch-white/arch-logo-v1-1920x1080.png"
ln -s ../blue-hex/blue-hex-v2-2560x1600.png "$W/arch-white/arch-logo-v2-2560x1600.png"
: > "$W/own/sunset.jpg"
# Dwa różne zdjęcia użytkownika z „v1” w środku nazwy: grupowanie nie może
# schować żadnego (łączy tylko nazwy różniące się tagiem i rozdzielczością).
: > "$W/own/trip-v1-plaza.png"; : > "$W/own/trip-v1-las.png"
# Atrapa generatora: te same nazwy co gen_dither_flux_wallpaper.py (forma-tag-WxH),
# formy w tej samej kolejności, ostatnia = znacznik kompletu.
cat > "$T/fakegen.py" <<'EOF'
import os, re, sys
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for form in ('przeplyw', 'atraktor', 'przeplyw2'):
    for arg in sys.argv[4:]:
        m = re.fullmatch(r'([A-Za-z0-9][A-Za-z0-9-]*):(\d+x\d+)', arg)
        if m:
            open(os.path.join(out, 'dither-flux-%s-%s-%s.png' % (form, m.group(1), m.group(2))), 'wb').write(b'PNG')
EOF
# install.sh [9.7]: plan → sprzątanie → generowanie (w tle; tu czekamy na koniec)
step_97() {
    (
        # shellcheck source=scripts/wallpapers/lib/dither-flux-sizes.sh
        source "$REPO/scripts/wallpapers/lib/dither-flux-sizes.sh"
        dither_flux_plan "$A/data/monitors" "$G"
        dither_flux_prune "$A/data/monitors" "$G"
        ((${#FLUX_SIZES[@]})) || exit 0
        dither_flux_start "$T/fakegen.py" "$G"; wait "$!"
    )
}
docked() {
    setup_dat "$1"
    sed -i '$a RESOLUTION=1920x1080' "$A/data/monitors/HDMI-A-3.dat"
    sed -i '$a RESOLUTION=2560x1600' "$A/data/monitors/eDP-1.dat"
    [[ -f "$A/data/monitors/DP-3.dat" ]] && sed -i '$a RESOLUTION=2560x1440' "$A/data/monitors/DP-3.dat"
    return 0
}
# 1. pierwsza instalacja w doku (HDMI primary 1920x1080, panel secondary 2560x1600)
docked a; step_97
# wybór z Super+W w doku: forma atraktor na obu ekranach
printf 'desc:%s=%s\ndesc:%s=%s\n' "$DESC_HDMI" "$G/dither-flux-atraktor-v1-1920x1080.png" \
    "$DESC_EDP" "$G/dither-flux-atraktor-v2-2560x1600.png" > "$A/data/wallpaper.dat"
# 2. aktualizacja + install.sh bez doku: sam panel, primary 2560x1600 ([3] pisze .dat od nowa)
rm -f "$A/data/monitors"/*.dat
printf 'MONITOR=eDP-1\nROLE=primary\nDESCRIPTION=%s\nRESOLUTION=2560x1600\nORDER=1\n' "$DESC_EDP" > "$A/data/monitors/eDP-1.dat"
step_97
# 3. aktualizacja z nowym zestawem (jak yin 2026-11-17) + install.sh w doku z trzecim monitorem
mkdir -p "$W/yin"; : > "$W/yin/yin-eclipse-v1-1920x1080.png"; : > "$W/yin/yin-eclipse-v2-2560x1600.png"
docked three; step_97
boot_daemon_with ""
menu "Wallpapers/" ""
mapfile -t O_LABELS < <(rofi_in 2 | sed 's/|icon#.*//' | grep -vxF "← Back")
# Klucz obrazu niezależny od implementacji: katalog + nazwa bez rozszerzenia,
# rozdzielczości i tagu wariantu (v1/v2, m-<złącze>).
img_key() { local k="${1%.*}"; k="${k%-[0-9]*x[0-9]*}"; k="${k%-m-*}"; k="${k%-v[12]}"; printf '%s\n' "$k"; }
O_DUPS="$(for l in "${O_LABELS[@]}"; do img_key "$l"; done | sort | uniq -d)"
O_KEYS="$(for l in "${O_LABELS[@]}"; do img_key "$l"; done | sort -u | paste -sd' ')"
O_WANT="blue-hex/blue-hex crt/crt-scope dither-flux/generated/dither-flux-atraktor dither-flux/generated/dither-flux-przeplyw dither-flux/generated/dither-flux-przeplyw2 own/sunset own/trip-v1-las own/trip-v1-plaza yin/yin-eclipse"
if [[ -n "$O_DUPS" || "$O_KEYS" != "$O_WANT" ]]; then
    echo "    menu Wallpapers/ (${#O_LABELS[@]} kafli):"; printf '      %s\n' "${O_LABELS[@]}"
fi
check "każdy obraz dokładnie raz (v1/v2 i rozdzielczości to jeden kafel)" '[[ -z "$O_DUPS" && ${#O_LABELS[@]} -eq 9 ]]'
check "żaden obraz nie zniknął z menu (też trip-v1-plaza i trip-v1-las)"          '[[ "$O_KEYS" == "$O_WANT" ]]'
check "kafel = nazwa obrazu (crt/crt-scope, forma dither-flux bez tagu)" 'printf "%s\n" "${O_LABELS[@]}" | grep -qxF "crt/crt-scope" && printf "%s\n" "${O_LABELS[@]}" | grep -qxF "dither-flux/generated/dither-flux-atraktor"'
O_GEN="$(cd "$G" && find . -maxdepth 1 -type f -name '*.png' | sed 's|^\./||' | sort | paste -sd' ')"
O_GEN_WANT=""
for form in atraktor przeplyw przeplyw2; do
    for tr in m-DP-3-2560x1440 v1-1920x1080 v2-2560x1600; do O_GEN_WANT+="dither-flux-$form-$tr.png "; done
done
O_GEN_WANT="$(tr ' ' '\n' <<< "$O_GEN_WANT" | grep . | sort | paste -sd' ')"
[[ "$O_GEN" == "$O_GEN_WANT" ]] || echo "    generated/: $O_GEN"
check "generated/: tylko pliki pod dzisiejsze monitory (3 formy × 3 ekrany)" '[[ "$O_GEN" == "$O_GEN_WANT" ]]'
check "pliki bez monitora przeniesione do generated/.bak-*, nie skasowane" '[[ -n "$(find "$G" -mindepth 2 -path "*/.bak-*/dither-flux-przeplyw-v1-2560x1600.png")" ]]'
# Upload to all monitors z kafla: primary v1, pozostałe v2 — jak dotąd.
menu "Wallpapers/" "crt/crt-scope"
check "kafel → primary v1, secondary v2"         '[[ "$(MOCK_MONS=both active_of HDMI-A-3)" == "$W/crt/crt-scope-v1-1920x1080.png" && "$(MOCK_MONS=both active_of eDP-1)" == "$W/crt/crt-scope-v2-2560x1600.png" ]]'
# Tylko monitor z fokusem (eDP-1 = secondary): dostaje SWÓJ wariant (v2), bo v2
# nie ma już osobnego kafla.
menu "[x] Upload to all monitors" "Wallpapers/" "blue-hex/blue-hex"
check "monitor z fokusem dostaje wariant pod siebie (secondary → v2)" '[[ "$(MOCK_MONS=both active_of eDP-1)" == "$W/blue-hex/blue-hex-v2-2560x1600.png" ]] && grep -qxF "desc:$DESC_HDMI=$W/crt/crt-scope-v1-1920x1080.png" "$A/data/wallpaper.dat"'
rm -rf "$W"; mkdir -p "$WP"
for f in stara-v1.png stara-v2.png nowa-v1.png nowa-v2.png; do : > "$WP/$f"; done

echo "== P: podpis = nazwa obrazu, trzeci monitor po rozdzielczości, jeden .bak (właściciel 2026-11-24: 1A, 3A, 4A)"
# 1A: kafel podpisany czystą nazwą obrazu (crt/crt-scope), nie ścieżką wariantu
# …-v1-1920x1080.png. 3A: monitor z rolą other (trzeci) dostaje plik dobrany do
# SWOJEJ rozdzielczości z .dat (wygenerowany m-<złącze> albo najbliższy ostry
# wariant), nie zawsze v2. 4A: w generated/ zostaje tylko ostatni .bak-*.
# Układ docked three: HDMI-A-3 primary 1920x1080, eDP-1 secondary 2560x1600,
# DP-3 other 2560x1440.
W="$A/wallpapers"; G="$W/dither-flux/generated"
rm -rf "$W"; mkdir -p "$W/crt" "$W/hi" "$W/own" "$G"
: > "$W/crt/crt-scope-v1-1920x1080.png"; : > "$W/crt/crt-scope-v2-2560x1600.png"
# Zestaw bez wariantu 2560x1440: ostry dla DP-3 jest v1-3840x2160 (pomniejszenie),
# v2-1920x1200 trzeba by powiększać (rozmycie).
: > "$W/hi/peak-v1-3840x2160.png"; : > "$W/hi/peak-v2-1920x1200.png"
for tr in v1-1920x1080 v2-2560x1600 m-DP-3-2560x1440; do : > "$G/dither-flux-atraktor-$tr.png"; done
# Dwa pliki o tej samej nazwie obrazu: oba muszą zostać rozróżnialne.
: > "$W/own/sunset.jpg"; : > "$W/own/sunset.png"; : > "$W/own/trip-v1-plaza.png"
docked three
boot_daemon_with ""
MENU_MONS=three menu "Wallpapers/" ""
mapfile -t P_LABELS < <(rofi_in 2 | sed 's/|icon#.*//' | grep -vxF "← Back")
P_GOT="$(printf '%s\n' "${P_LABELS[@]}" | LC_ALL=C sort | paste -sd' ')"
P_WANT="crt/crt-scope dither-flux/generated/dither-flux-atraktor hi/peak own/sunset.jpg own/sunset.png own/trip-v1-plaza"
[[ "$P_GOT" == "$P_WANT" ]] || echo "    kafle: $P_GOT"
check "1A: podpis = katalog/nazwa obrazu, bez tagu, rozdzielczości i rozszerzenia" '[[ "$P_GOT" == "$P_WANT" ]]'
check "1A: ta sama nazwa obrazu w dwóch plikach → podpis z rozszerzeniem, oba w menu" 'printf "%s\n" "${P_LABELS[@]}" | grep -qxF own/sunset.jpg && printf "%s\n" "${P_LABELS[@]}" | grep -qxF own/sunset.png'
check "1A: kafel z czystym podpisem ma miniaturę wariantu pod primary" '[[ "$(icon_of 2 crt/crt-scope)" == "$THUMBS"/*.png ]]'
MENU_MONS=three menu "Wallpapers/" "crt/crt-scope"
check "1A: wybór podpisu → primary v1, secondary v2" '[[ "$(MOCK_MONS=three active_of HDMI-A-3)" == "$W/crt/crt-scope-v1-1920x1080.png" && "$(MOCK_MONS=three active_of eDP-1)" == "$W/crt/crt-scope-v2-2560x1600.png" ]]'
check "1A: powiadomienie z nazwą obrazu" 'grep -qF "applied" "$MOCK_LOG" && grep -q "NOTIFY: archenemy Wallpaper .crt/crt-scope. applied" "$MOCK_LOG"'
check "3A: brak pliku 2560x1440 → najmniejszy pokrywający ekran (crt v2-2560x1600)" '[[ "$(MOCK_MONS=three active_of DP-3)" == "$W/crt/crt-scope-v2-2560x1600.png" ]]'
MENU_MONS=three menu "Wallpapers/" "own/sunset.png"
check "1A: podpis z rozszerzeniem → dokładnie ten plik" '[[ "$(MOCK_MONS=three active_of HDMI-A-3)" == "$W/own/sunset.png" && "$(MOCK_MONS=three active_of DP-3)" == "$W/own/sunset.png" ]]'
MENU_MONS=three menu "Wallpapers/" "crt/crt-scope-v2-2560x1600.png"
check "1A: wpisana ścieżka pliku dalej działa" '[[ "$(MOCK_MONS=three active_of HDMI-A-3)" == "$W/crt/crt-scope-v1-1920x1080.png" && "$(MOCK_MONS=three active_of eDP-1)" == "$W/crt/crt-scope-v2-2560x1600.png" ]]'
MENU_MONS=three menu "Wallpapers/" "dither-flux/generated/dither-flux-atraktor"
check "3A: trzeci monitor (other) dostaje swój m-DP-3-2560x1440, nie v2" '[[ "$(MOCK_MONS=three active_of DP-3)" == "$G/dither-flux-atraktor-m-DP-3-2560x1440.png" ]]'
check "3A: primary v1 i secondary v2 bez zmian" '[[ "$(MOCK_MONS=three active_of HDMI-A-3)" == "$G/dither-flux-atraktor-v1-1920x1080.png" && "$(MOCK_MONS=three active_of eDP-1)" == "$G/dither-flux-atraktor-v2-2560x1600.png" ]]'
MENU_MONS=three menu "Wallpapers/" "hi/peak"
check "3A: bez dokładnej rozdzielczości → v1-3840x2160, nie powiększane v2-1920x1200" '[[ "$(MOCK_MONS=three active_of DP-3)" == "$W/hi/peak-v1-3840x2160.png" ]]'
check "3A: secondary dalej v2 z pary" '[[ "$(MOCK_MONS=three active_of eDP-1)" == "$W/hi/peak-v2-1920x1200.png" ]]'
# 2A: tylko monitor z fokusem — tu fokus na trzecim, więc jego wariant.
MOCK_FOCUS=DP-3 MENU_MONS=three menu "[x] Upload to all monitors" "Wallpapers/" "crt/crt-scope"
check "2A+3A: fokus na trzecim → jego wariant, reszta bez zmian" '[[ "$(MOCK_MONS=three active_of DP-3)" == "$W/crt/crt-scope-v2-2560x1600.png" && "$(MOCK_MONS=three active_of HDMI-A-3)" == "$W/hi/peak-v1-3840x2160.png" ]]'
MOCK_FOCUS=DP-3 MENU_MONS=three menu "[x] Upload to all monitors" "Wallpapers/" "dither-flux/generated/dither-flux-atraktor"
check "2A+3A: fokus na trzecim, forma dither-flux → m-DP-3-2560x1440" '[[ "$(MOCK_MONS=three active_of DP-3)" == "$G/dither-flux-atraktor-m-DP-3-2560x1440.png" ]]'
# Super+A → [n] dodał trzeci monitor: --restore daje mu obraz secondary, ale w jego rozdzielczości.
printf 'desc:%s=%s\ndesc:%s=%s\n' "$DESC_HDMI" "$G/dither-flux-atraktor-v1-1920x1080.png" \
    "$DESC_EDP" "$G/dither-flux-atraktor-v2-2560x1600.png" > "$A/data/wallpaper.dat"
MOCK_MONS=three bash "$SW" --restore >/dev/null 2>&1
check "3A: --restore, nowy trzeci monitor → obraz secondary w swojej rozdzielczości" '[[ "$(MOCK_MONS=three active_of DP-3)" == "$G/dither-flux-atraktor-m-DP-3-2560x1440.png" ]]'
# Rola other bez znanej rozdzielczości (tryb nazwany) — jak dotąd v2.
sed -i '/^RESOLUTION=/d' "$A/data/monitors/DP-3.dat"
MENU_MONS=three menu "Wallpapers/" "dither-flux/generated/dither-flux-atraktor"
check "3A: other bez rozdzielczości w .dat → v2 jak dotąd" '[[ "$(MOCK_MONS=three active_of DP-3)" == "$G/dither-flux-atraktor-v2-2560x1600.png" ]]'

# 4A: tylko ostatni katalog .bak-* w generated/. Program kasuje WYŁĄCZNIE własne
# katalogi (format mktemp z dither_flux_prune: .bak-RRRRMMDD-GGMMSS-XXXX) w swoim
# generated/ — nigdy symlinku, pliku, innej nazwy ani niczego poza generated/.
rm -rf "$G"; mkdir -p "$G"
for b in .bak-20261101-120000-AbCd .bak-20261102-120000-EfGh; do
    mkdir -p "$G/$b"; printf 'PNG' > "$G/$b/dither-flux-przeplyw-v1-1024x768.png"
done
mkdir -p "$G/.bak-mine" "$W/dither-flux/.bak-20261101-120000-Zzzz"
mkdir -p "$T/outside"; : > "$T/outside/keep.png"; ln -s "$T/outside" "$G/.bak-20261103-120000-Link"
: > "$G/.bak-20261104-120000-File"
docked a
for f in atraktor przeplyw przeplyw2; do printf 'PNG' > "$G/dither-flux-$f-m-DP-3-2560x1440.png"; done
step_97
bak_dirs() { find "$G" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex '.*/\.bak-[0-9]{8}-[0-9]{6}-[A-Za-z0-9]{4}' | sort; }
mapfile -t P_BAK < <(bak_dirs)
check "4A: po sprzątaniu w generated/ jeden katalog .bak-* (ostatni)" '(( ${#P_BAK[@]} == 1 )) && [[ -f "${P_BAK[0]}/dither-flux-atraktor-m-DP-3-2560x1440.png" ]]'
check "4A: starsze .bak-* usunięte" '[[ ! -e "$G/.bak-20261101-120000-AbCd" && ! -e "$G/.bak-20261102-120000-EfGh" ]]'
check "4A: nietknięte: inna nazwa, symlink (i jego cel), plik, .bak poza generated/" '[[ -d "$G/.bak-mine" && -L "$G/.bak-20261103-120000-Link" && -f "$T/outside/keep.png" && -f "$G/.bak-20261104-120000-File" && -d "$W/dither-flux/.bak-20261101-120000-Zzzz" ]]'
step_97
mapfile -t P_BAK2 < <(bak_dirs)
check "4A: bieg bez nowych plików do odsunięcia: ten sam jeden .bak" '[[ "${P_BAK2[*]}" == "${P_BAK[*]}" ]]'
# Stan po T1 (kilka .bak-*, nic nowego do odsunięcia): zostaje najnowszy.
mkdir -p "$G/.bak-20261001-000000-Old1"; printf 'PNG' > "$G/.bak-20261001-000000-Old1/x.png"
step_97
mapfile -t P_BAK3 < <(bak_dirs)
check "4A: kilka starych .bak-*, nic nowego → zostaje tylko najnowszy" '[[ "${P_BAK3[*]}" == "${P_BAK[*]}" && ! -e "$G/.bak-20261001-000000-Old1" ]]'
# Zapisany wybór wskazuje plik w starym .bak (wpisana ścieżka) — ten katalog zostaje.
mkdir -p "$G/.bak-20261002-000000-Prot"; printf 'PNG' > "$G/.bak-20261002-000000-Prot/dither-flux-atraktor-v1-800x600.png"
printf 'desc:%s=%s\n' "$DESC_HDMI" "$G/.bak-20261002-000000-Prot/dither-flux-atraktor-v1-800x600.png" > "$A/data/wallpaper.dat"
step_97
check "4A: .bak z plikiem z zapisanego wyboru zostaje" '[[ -f "$G/.bak-20261002-000000-Prot/dither-flux-atraktor-v1-800x600.png" ]]'
rm -rf "$W" "$T/outside"; mkdir -p "$WP"
for f in stara-v1.png stara-v2.png nowa-v1.png nowa-v2.png; do : > "$WP/$f"; done

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
