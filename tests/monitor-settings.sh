#!/bin/bash
# =============================================
#   archenemy - tests/monitor-settings.sh
#   Zmiana monitora Super+A → [n] (scripts/hypr/monitor-settings.sh) na atrapie
#   hyprctl, która czyta wygenerowany monitorshyprl.lua. Bez Hyprlanda, zapis
#   tylko w mktemp.
#
#   Powód powstania (audyt TUI 2026-11-05): monitory dało się zmienić tylko
#   przez install.sh, a zły tryb na żywo może zostawić czarny ekran. Dodawanie
#   nowego monitora, numeracja i usuwanie odpiętego: plan 2026-11-05. Rozdzielczość
#   i odświeżanie osobno, mapa, pozycja obok monitora, sąsiedzi za krawędzią.
#   Uruchom: bash tests/monitor-settings.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

H="$T/home"; A="$H/archenemy"; D="$A/data/monitors"; LUA="$A/config/hypr/monitorshyprl.lua"
WS="$A/config/hypr/workspaces-monitors.lua"; MODE="$A/data/workspace-mode.dat"
mkdir -p "$D" "$A/config/hypr" "$A/scripts/hypr/lib" "$A/scripts/appbinds/lib" "$A/scripts/rofi" "$A/scripts/wallpapers/lib" "$T/bin"
cp "$REPO"/scripts/hypr/lib/{monitor-id,gen-monitors,gen-workspaces,hypr-apply}.sh "$A/scripts/hypr/lib/"
cp "$REPO/scripts/appbinds/lib/tui.sh" "$A/scripts/appbinds/lib/"
cp "$REPO/scripts/hypr/monitor-settings.sh" "$A/scripts/hypr/"
cp "$REPO/scripts/wallpapers/lib/dither-flux-sizes.sh" "$A/scripts/wallpapers/lib/"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/clear"; printf '#!/bin/bash\nexit 0\n' > "$T/bin/sleep"
# Atrapy kroków po zmianie układu: log wywołań zamiast tapet i workspace'ów.
printf '#!/bin/bash\necho "wallpaper $*" >> "%s/after"\n' "$T" > "$A/scripts/rofi/rofi_wallpaper_switcher.sh"
printf '#!/bin/bash\necho "guard $*" >> "%s/after"\n' "$T" > "$A/scripts/hypr/workspace-orphan-guard.sh"
printf '#!/usr/bin/env python3\nimport sys\nopen("%s/gen", "w").write(" ".join(sys.argv[1:]))\n' "$T" > "$T/gen.py"
printf '#!/bin/bash\necho "$*" >> "%s/notified"\n' "$T" > "$T/bin/notify-send"
printf '#!/bin/bash\ncat "%s/age" 2>/dev/null\n' "$T" > "$T/bin/ps"

# Atrapa hyprctl: `monitors` w formacie src/ipc/s1/Commands.cpp, reload stosuje
# reguły z pliku Lua. `dead` = brak odpowiedzi, `badscale` = błąd configu,
# `stubborn` = Hyprland ignoruje skalę, `offline` = HDMI-A-1 odpięty, `third` =
# podpięty nowy DP-2, `vanish` = DP-2 znika przy reloadzie, `twin` = HDMI-A-1 ma ten
# sam opis EDID co DP-2.
cat > "$T/bin/hyprctl" <<EOS
#!/bin/bash
echo "hyprctl \$*" >> "$T/log"
[[ -f "$T/dead" ]] && exit 1
rule() { sed -n "s|^hl.monitor({ output = \"\$1\", mode = \"\([^\"]*\)\", position = \"\([^\"]*\)\", scale = \([^ ]*\) })\$|\1 \2 \3|p" "$LUA"; }
show() {
  read -r mode pos scale <<<"\$3"
  [[ -f "$T/stubborn" ]] && scale=1
  [[ "\$mode" == *@* ]] || mode="\$mode@60"
  printf 'Monitor %s (ID %s):\n\t%s at %s\n\tdescription: %s\n\tscale: %s\n\tavailableModes: 2560x1440@165.00Hz 2560x1440@60.00Hz 1920x1080@60.00Hz 1920x1080@60.00Hz\n\n' "\$1" "\$2" "\$mode" "\$pos" "\$4" "\$scale"
}
case "\$1" in
  reload) [[ -f "$T/vanish" ]] && rm -f "$T/third"
    if grep -q 'scale = 9' "$LUA"; then echo 'hl.monitor: bad scale' > "$T/errors"; else : > "$T/errors"; fi; echo ok ;;
  configerrors) cat "$T/errors" 2>/dev/null; echo ;;
  monitors)
    show eDP-1 0 "\$(rule 'desc:Maker Panel 123')" 'Maker Panel 123 (eDP-1)'
    d='x"y'; [[ -f "$T/twin" ]] && d='Acme Wide 99 (HDMI-A-1)'
    r="\$(rule 'HDMI-A-1')"; [[ -n "\$r" ]] || r="\$(rule 'desc:Acme Wide 99')"
    [[ -f "$T/offline" ]] || show HDMI-A-1 1 "\$r" "\$d"
    if [[ -f "$T/third" ]]; then
      r="\$(rule 'desc:Acme Wide 99')"; [[ -n "\$r" ]] || r="\$(rule 'DP-2')"
      show DP-2 2 "\${r:-2560x1440@60.00000 3840x0 1.00}" 'Acme Wide 99 (DP-2)'
      printf '\tmake: Acme\n\tmodel: Wide\n\tserial: 99\n\n'
    fi
    ;;
esac
EOS
chmod +x "$T/bin/"*
export HOME="$H" PATH="$T/bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test

reset() {
    printf 'MONITOR=eDP-2\nRESOLUTION=1920x1080\nRATE=60.00\nPOSITION=0x0\nSCALE=1\nROLE=primary\nDESCRIPTION=Maker Panel 123\nORDER=1\n' > "$D/eDP-2.dat"
    printf 'MONITOR=HDMI-A-1\nRESOLUTION=1920x1080\nRATE=60.00\nPOSITION=1920x0\nSCALE=1\nROLE=secondary\nDESCRIPTION=x"y\nORDER=2\n' > "$D/HDMI-A-1.dat"
    rm -f "${D:?}/DP-2.dat" "${D:?}/DP-2-2.dat" "${MODE:?}"
    gen_all
    cp "$D/eDP-2.dat" "$T/dat.orig"; cp "$LUA" "$T/lua.orig"; cp "$WS" "$T/ws.orig"
    : > "$T/log"; : > "$T/errors"; : > "$T/after"; : > "$T/notified"
    rm -f "$T/dead" "$T/stubborn" "$T/offline" "$T/third" "$T/vanish" "$T/twin" "$T/age" "$T/gen"
    rm -f "$A/scripts/wallpapers/gen_dither_flux_wallpaper.py"
}
gen_all() {
    ( source "$A/scripts/hypr/lib/monitor-id.sh"; source "$A/scripts/hypr/lib/gen-monitors.sh"; source "$A/scripts/hypr/lib/gen-workspaces.sh"
      generate_monitors_conf "$LUA" "$D"
      mapfile -t e < <(monitor_entries_ordered "$D")
      generate_workspaces_monitors "$WS" "$(cat "$MODE" 2>/dev/null || echo decades)" "${e[@]}" )
}
run() { printf "$1" | timeout 10 bash "$A/scripts/hypr/monitor-settings.sh" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
get() { grep -m1 "^$2=" "$D/$1.dat" | cut -d= -f2-; }
unchanged() { cmp -s "$D/eDP-2.dat" "$T/dat.orig" && cmp -s "$LUA" "$T/lua.orig" && cmp -s "$WS" "$T/ws.orig" && [[ "$(ls "$D" | wc -l)" == 2 ]]; }
summary() { bash "$A/scripts/hypr/monitor-settings.sh" summary; }

echo "== generator"
reset
check "format jak w install.sh [8a]"           'grep -qx "hl.monitor({ output = \"desc:Maker Panel 123\", mode = \"1920x1080@60.00\", position = \"0x0\", scale = 1 })" "$LUA"'
check "opis ze znakiem specjalnym = złącze"    'grep -q "output = \"HDMI-A-1\"" "$LUA"'
check "reguła fallback na końcu"               '[[ "$(tail -1 "$LUA")" == *"output = \"\", mode = \"preferred\""* ]]'
check "komentarz z nazwą złącza"               'grep -qx -- "-- eDP-2" "$LUA"'
sed -i 's/^RATE=.*/RATE=/; s/^RESOLUTION=.*/RESOLUTION=preferred/' "$D/eDP-2.dat"
( source "$A/scripts/hypr/lib/monitor-id.sh"; source "$A/scripts/hypr/lib/gen-monitors.sh"; generate_monitors_conf "$LUA" "$D" )
check "tryb bez odświeżania"                   'grep -q "mode = \"preferred\", position = \"0x0\"" "$LUA"'

echo "== lista"
reset; touch "$T/offline"; out="$(run '\n')"
check "żywa nazwa zamiast tej z instalacji"    '[[ "$out" == *"eDP-1"*"1920x1080@60.00 at 0x0, scale 1"* ]]'
check "odpięty monitor oznaczony"              '[[ "$out" == *"not connected"* ]]'
check "Enter wraca bez reloadu"                '! grep -q "hyprctl reload" "$T/log"'
out="$(run '2\n\n')"
check "odpiętego nie zmienia"                  '[[ "$out" == *"is not connected"* ]] && unchanged'
out="$(run '7\n\n')"
check "zły numer monitora"                     '[[ "$out" == *"no monitor number"* ]]'

echo "== zmiana z potwierdzeniem"
reset; out="$(run '1\n1\n1\n1.5\n\ny\n')"
check "tryb z listy zapisany"                  '[[ "$(get eDP-2 RESOLUTION)" == 2560x1440 && "$(get eDP-2 RATE)" == 165.00 ]]'
check "skala zapisana"                         '[[ "$(get eDP-2 SCALE)" == 1.5 ]]'
check "numer, rola i opis bez zmian"           '[[ "$(get eDP-2 ORDER)" == 1 && "$(get eDP-2 ROLE)" == primary && "$(get eDP-2 DESCRIPTION)" == "Maker Panel 123" ]]'
check "Lua z selektorem desc:"                 'grep -q "desc:Maker Panel 123\", mode = \"2560x1440@165.00\", position = \"0x0\", scale = 1.5" "$LUA"'
check "sukces pokazuje stan z Hyprlanda"       '[[ "$out" == *"✓ Monitor eDP-1: 2560x1440 165.00 0x0 1.5"* ]]'
check "uwaga o tapetach dither"                '[[ "$out" == *"dither-flux"* ]]'
check "bez plików tymczasowych"                '[[ "$(find "$D" "$A/config/hypr" -name "*.??????" | wc -l)" == 0 ]]'

echo "== duplikat trybu"
reset; out="$(run '1\n3\n\n\n\n\n')"
check "lista bez powtórzeń"                    '[[ "$out" == *"Pick a number"* ]]'

echo "== cofnięcie"
reset; out="$(run '1\n1\n\n\n\nn\n')"
check "inny klawisz cofa"                      'unchanged && [[ "$out" == *"Back to the previous"* ]]'
check "po cofnięciu drugi reload"              '[[ "$(grep -c "hyprctl reload" "$T/log")" == 2 ]]'
reset; out="$(run '1\n1\n\n\n\n')"
check "brak klawisza cofa"                     'unchanged'
reset; out="$(run '1\n\n9\n\n\n')"
check "błąd configu cofa"                      'unchanged && [[ "$out" == *"config error"*"bad scale"* ]]'
reset; touch "$T/dead"; out="$(run '1\n1\n\n\n\n\n')"; rm "$T/dead"
check "martwy Hyprland cofa"                   'unchanged'
reset; ( printf '1\n1\n\n\n\n'; /usr/bin/sleep 2 ) | bash "$A/scripts/hypr/monitor-settings.sh" >/dev/null 2>&1 &
pid=$!
for _ in $(seq 1 200); do grep -q "hyprctl reload" "$T/log" && break; /usr/bin/sleep 0.02; done
/usr/bin/sleep 0.2; kill -HUP "$pid"; wait "$pid"
check "zamknięcie okna cofa"                   'unchanged'

echo "== bez sesji"
reset; out="$(printf '1\n\n2\n\n\n' | HYPRLAND_INSTANCE_SIGNATURE= bash "$A/scripts/hypr/monitor-settings.sh" 2>&1)"
check "bez Hyprlanda brak żywego monitora"     '[[ "$out" == *"not connected"* || "$out" == *"No Hyprland"* ]]'

echo "== walidacja"
reset; out="$(run '1\n\nabc\n0\n1.25\nfoo\n10x10\ny\n')"
check "zła pozycja i skala pytają ponownie"    '[[ "$out" == *"Use a positive number"*"Use XxY"* ]]'
check "poprawne wartości zapisane"             '[[ "$(get eDP-2 POSITION)" == 10x10 && "$(get eDP-2 SCALE)" == 1.25 ]]'
reset; out="$(run '1\n\n\n\n\n')"
check "bez zmian nic nie przeładowuje"         '[[ "$out" == *"Nothing changed"* ]] && ! grep -q "hyprctl reload" "$T/log"'

echo "== odczyt stanu"
reset; touch "$T/stubborn"; out="$(run '1\n\n2\n\ny\n')"
check "inna skala w Hyprlandzie = ostrzeżenie" '[[ "$out" == *"Hyprland shows something else"* ]]'

echo "== rozdzielczość i odświeżanie osobno"
reset; out="$(run '1\n1\n2\n\n\ny\n')"
check "druga częstotliwość z listy"            '[[ "$(get eDP-2 RESOLUTION)" == 2560x1440 && "$(get eDP-2 RATE)" == 60.00 ]]'
check "lista odświeżania od najwyższego"       '[[ "$out" == *"Refresh rate for 2560x1440"*"165.00"*"60.00"* ]]'
reset; out="$(run '1\n1\n\n\n\ny\n')"
check "Enter przy nowej = najwyższa"           '[[ "$(get eDP-2 RATE)" == 165.00 ]]'
reset; out="$(run '1\n2\n\n\n\n')"
check "jedna częstotliwość: bez pytania"       '[[ "$out" != *"Refresh rate for"* && "$out" == *"Nothing changed"* ]]'
reset; out="$(run '1\np\n\n\ny\n')"
check "preferred: bez Hz"                      '[[ "$(get eDP-2 RESOLUTION)" == preferred && -z "$(get eDP-2 RATE)" ]]'
check "preferred w Lua"                        'grep -q "mode = \"preferred\", position = \"0x0\"" "$LUA"'
reset; run '1\nf\n\n\ny\n' >/dev/null
check "highrr"                                 '[[ "$(get eDP-2 RESOLUTION)" == highrr ]]'
reset; run '1\nh\n\n\ny\n' >/dev/null
check "highres"                                '[[ "$(get eDP-2 RESOLUTION)" == highres ]]'

echo "== mapa i pozycja obok monitora"
reset; out="$(run '\n')"
check "mapa: oba monitory"                     '[[ "$out" == *"┌"*"1 eDP-1"*"2 HDMI-A-1"* ]]'
check "mapa: rozdzielczości"                   '[[ "$out" == *"1920x1080"* ]]'
reset; sed -i 's/^POSITION=.*/POSITION=0x1080/' "$D/HDMI-A-1.dat"; gen_all; out="$(run '\n')"
check "mapa: układ pionowy"                    '[[ "$(grep -n "1 eDP-1" <<<"$out" | head -1 | cut -d: -f1)" -lt "$(grep -n "2 HDMI-A-1" <<<"$out" | head -1 | cut -d: -f1)" ]]'
check "mapa: pionowo boksy się nie nakładają"  '[[ "$(grep -c "└" <<<"$out")" == 2 && "$(grep -c "┌" <<<"$out")" == 2 ]]'
reset; out="$(run '1\n\n\nl 2\n\n\n')"
check "l 2 przy tej pozycji = nic do zmiany"   '[[ "$out" == *"→ 0x0"* && "$out" == *"Nothing changed"* ]]'
reset; out="$(run '2\n\n\nb 1\ny\n')"
check "b 1 = pod monitorem 1"                  '[[ "$(get HDMI-A-1 POSITION)" == 0x1080 && "$out" == *"→ 0x1080"* ]]'
reset; run '2\n\n\na 1\ny\n' >/dev/null
check "a 1 = nad monitorem 1"                  '[[ "$(get HDMI-A-1 POSITION)" == 0x-1080 ]]'
reset; run '2\n\n\nl 1\ny\n' >/dev/null
check "l 1 = na lewo, ujemnie"                 '[[ "$(get HDMI-A-1 POSITION)" == -1920x0 ]]'
reset; run '1\n\n2\nr 2\ny\n' >/dev/null
check "na prawo liczy się z sąsiada"           '[[ "$(get eDP-2 POSITION)" == 3840x0 ]]'
reset; run '1\n\n2\nl 2\ny\n' >/dev/null
check "na lewo liczy się po skali"             '[[ "$(get eDP-2 POSITION)" == 960x0 ]]'
reset; out="$(run '1\n\n\nr 1\nr 7\n\n\n')"
check "sam obok siebie i brak numeru"          '[[ "$out" == *"Pick another connected"*"Pick another connected"* ]] && unchanged'
reset; out="$(run '1\n\n\n100x0\n\n\n')"
check "nakładanie odrzucone"                   '[[ "$out" == *"overlaps HDMI-A-1"* ]] && unchanged'
reset; out="$(run '1\n\n\n10000x0\ny\n')"
check "daleko od reszty przechodzi"            '[[ "$(get eDP-2 POSITION)" == 10000x0 ]]'

echo "== skale"
reset; out="$(run '1\n1\n\n\n\n\n')"
check "czyste skale pod rozdzielczość"         '[[ "$out" == *"Clean scales for 2560x1440: 1, 1.25, 1.33333, 1.6, 1.66667, 2, 2.5"* ]]'
reset; out="$(run '1\n\n\n\n\n')"
check "inna rozdzielczość, inna lista"         '[[ "$out" == *"Clean scales for 1920x1080: 1, 1.25, 1.33333, 1.5, 1.6, 1.66667, 2, 2.5, 3"* ]]'

echo "== sąsiedzi za krawędzią"
reset; out="$(run '1\n1\n\n\n\ny\n')"
check "szerszy monitor pcha sąsiada"           '[[ "$(get HDMI-A-1 POSITION)" == 2560x0 && "$out" == *"HDMI-A-1 moves to 2560x0"* ]]'
reset; run '1\n1\n\n\n\nn\n' >/dev/null
check "cofnięcie wraca sąsiada"                '[[ "$(get HDMI-A-1 POSITION)" == 1920x0 ]]'
reset; run '1\n\n2\n\ny\n' >/dev/null
check "większa skala: sąsiad dosuwa się"       '[[ "$(get HDMI-A-1 POSITION)" == 960x0 ]]'
reset; out="$(run '1\n1\n\n\n5000x0\ny\n')"
check "własna pozycja: sąsiad zostaje"         '[[ "$(get HDMI-A-1 POSITION)" == 1920x0 && "$out" != *"stay attached"* ]]'
reset; sed -i 's/^POSITION=.*/POSITION=auto/' "$D/HDMI-A-1.dat"; gen_all; run '1\n1\n\n\n\ny\n' >/dev/null
check "pozycja auto nietknięta"                '[[ "$(get HDMI-A-1 POSITION)" == auto ]]'
reset; touch "$T/third"
printf 'MONITOR=DP-2\nRESOLUTION=2560x1440\nRATE=60\nPOSITION=3840x0\nSCALE=1\nROLE=other\nDESCRIPTION=Acme Wide 99\nORDER=3\n' > "$D/DP-2.dat"; gen_all
run '1\n1\n\n\n\ny\n' >/dev/null
check "łańcuch: trzeci też się przesuwa"       '[[ "$(get HDMI-A-1 POSITION)" == 2560x0 && "$(get DP-2 POSITION)" == 4480x0 ]]'
rm -f "$D/DP-2.dat"

echo "== numeracja"
reset; out="$(run '1\n\n\n4000x0\ny\n')"
check "pozycja rozjeżdża numery → uwaga"       '[[ "$out" == *"no longer run left to right"*"press r"* ]]'
check "numer zostaje"                          '[[ "$(get eDP-2 ORDER)" == 1 ]]'
reset; out="$(run '1\n\n\n0x100\ny\n')"
check "ta sama kolejność bez uwagi"            '[[ "$out" != *"left to right"* ]]'

echo "== nowy monitor: lista"
reset; touch "$T/third"; out="$(run '\n')"
check "nowy monitor na liście"                 '[[ "$out" == *"3) DP-2"*"new, pick to set up"* ]]'
check "skrót liczy nowy"                       '[[ "$(summary)" == "2 screens, 1 new" ]]'
check "podgląd pokazuje nowy"                  '[[ "$(bash "$A/scripts/hypr/monitor-settings.sh" brief)" == *"DP-2  new, needs setup"* ]]'
reset
check "bez nowego skrót jak dawniej"           '[[ "$(summary)" == "2 screens" ]]'

echo "== nowy monitor: dodanie"
reset; touch "$T/third"; out="$(run '3\n\n\n\n\n\n\ny\n')"
check "plik .dat z odczytu Hyprlanda"          '[[ "$(get DP-2 MONITOR)" == DP-2 && "$(get DP-2 RESOLUTION)" == 2560x1440 && "$(get DP-2 RATE)" == 60 && "$(get DP-2 POSITION)" == 3840x0 ]]'
check "rola i numer"                           '[[ "$(get DP-2 ROLE)" == other && "$(get DP-2 ORDER)" == 3 ]]'
check "opis EDID jak w install.sh"             '[[ "$(get DP-2 DESCRIPTION)" == "Acme Wide 99" ]]'
check "reguła monitora po opisie"              'grep -q "output = \"desc:Acme Wide 99\", mode = \"2560x1440@60\", position = \"3840x0\"" "$LUA"'
check "dekada workspace-ów"                    'grep -q "workspace = \"21\", monitor = \"desc:Acme Wide 99\", default = true, default_name = \"1\"" "$WS"'
check "istniejące monitory bez zmian numeru"   '[[ "$(get eDP-2 ORDER)" == 1 && "$(get HDMI-A-1 ORDER)" == 2 ]]'
check "potem już nie jest nowy"                '[[ "$(summary)" == "3 screens" ]]'
check "tapety i workspace-y nadążają"          'grep -qx "wallpaper --restore" "$T/after" && grep -qx "guard --rehome" "$T/after"'
check "bez plików tymczasowych"                '[[ "$(find "$D" "$A/config/hypr" -name "*.??????" | wc -l)" == 0 ]]'
reset; printf 'shared\n' > "$MODE"; gen_all; touch "$T/third"; run '3\n\n\n\n\n\n\ny\n' >/dev/null
check "shared: domowy workspace 3"             'grep -q "workspace = \"3\", monitor = \"desc:Acme Wide 99\", default = true" "$WS"'
reset; touch "$T/third"; out="$(run '3\n1\n1\n1.5\n\n\n\ny\n')"
check "tryb i skala z kreatora"                '[[ "$(get DP-2 RESOLUTION)" == 2560x1440 && "$(get DP-2 RATE)" == 165.00 && "$(get DP-2 SCALE)" == 1.5 ]]'

echo "== nowy monitor: numeracja"
reset; touch "$T/third"; out="$(run '3\n\n\n\n-2560x0\n\n\ny\n')"
check "po lewej = numer 1"                     '[[ "$(get DP-2 ORDER)" == 1 && "$(get eDP-2 ORDER)" == 2 && "$(get HDMI-A-1 ORDER)" == 3 ]]'
check "panel wbudowany trzyma dekadę 1-10"     'grep -q "workspace = \"1\", monitor = \"desc:Maker Panel 123\"" "$WS"'
reset; touch "$T/third"; out="$(run '3\n\n\n\n\n\n1 1\n3 2 1\ny\n')"
check "zła kolejność pyta ponownie"            '[[ "$out" == *"Use each number"* ]]'
check "własna kolejność"                       '[[ "$(get DP-2 ORDER)" == 1 && "$(get eDP-2 ORDER)" == 3 ]]'

echo "== nowy monitor: cofnięcie"
reset; touch "$T/third"; out="$(run '3\n\n\n\n\n\n\nn\n')"
check "inny klawisz usuwa dodane"              'unchanged && [[ ! -e "$D/DP-2.dat" ]]'
check "cofnięcie bez tapet i strażnika"        '[[ ! -s "$T/after" ]]'
reset; touch "$T/third"; out="$(run '3\n\n\n9\n\n\n\n\n')"
check "błąd configu cofa dodanie"              'unchanged && [[ "$out" == *"config error"* ]]'
reset; touch "$T/third" "$T/vanish"; out="$(run '3\n\n\n\n\n\n\n\n')"
check "odpięcie w trakcie cofa"                'unchanged && [[ "$out" == *"DP-2 is gone"* ]]'
reset; touch "$T/third"; out="$(run '3\n\n')"
check "przerwany kreator nic nie zapisuje"     'unchanged'
reset; touch "$T/third"; ( printf '3\n\n\n\n\n\n\n'; /usr/bin/sleep 2 ) | bash "$A/scripts/hypr/monitor-settings.sh" >/dev/null 2>&1 &
pid=$!
for _ in $(seq 1 200); do grep -q "hyprctl reload" "$T/log" && break; /usr/bin/sleep 0.02; done
/usr/bin/sleep 0.2; kill -HUP "$pid"; wait "$pid"
check "zamknięcie okna cofa dodanie"           'unchanged'
reset; touch "$T/third"; out="$(printf '3\n\n' | HYPRLAND_INSTANCE_SIGNATURE= bash "$A/scripts/hypr/monitor-settings.sh" 2>&1)"
check "bez sesji odmawia"                      '[[ "$out" == *"No Hyprland session"* ]] && unchanged'

echo "== nowy monitor: przypadki brzegowe"
reset; touch "$T/third" "$T/offline"
printf 'MONITOR=DP-2\nRESOLUTION=1920x1080\nRATE=60\nPOSITION=5000x0\nSCALE=1\nROLE=other\nDESCRIPTION=Old Screen 1\nORDER=3\n' > "$D/DP-2.dat"
out="$(run '4\n\n\n\n\n\n\ny\n')"
check "zajęta nazwa pliku = sufiks"            '[[ -e "$D/DP-2-2.dat" && "$(get DP-2-2 MONITOR)" == DP-2 && "$(get DP-2 DESCRIPTION)" == "Old Screen 1" ]]'
check "oba monitory mają reguły workspace-ów"  'grep -q "desc:Old Screen 1" "$WS" && grep -q "desc:Acme Wide 99" "$WS"'
reset; touch "$T/third" "$T/twin"; sed -i 's/^DESCRIPTION=.*/DESCRIPTION=Acme Wide 99/' "$D/HDMI-A-1.dat"; gen_all
out="$(run '3\n\n\n\nr 2\n\n\ny\n')"
check "bliźniak: wspólna reguła = ta sama pozycja, trzeba ją zmienić" '[[ "$out" == *"overlaps HDMI-A-1"* ]]'
check "bliźniak: ostrzeżenie"                  '[[ "$out" == *"Same EDID description"* ]]'
check "bliźniak: drugi egzemplarz jest nowy"   '[[ -e "$D/DP-2.dat" ]]'
check "bliźniak: oba po nazwie złącza"         '[[ -z "$(get DP-2 DESCRIPTION)" && -z "$(get HDMI-A-1 DESCRIPTION)" ]] && grep -q "output = \"DP-2\"" "$LUA" && grep -q "output = \"HDMI-A-1\"" "$LUA"'
reset; touch "$T/third"; sed -i 's/^ROLE=.*/ROLE=other/' "$D/HDMI-A-1.dat"; out="$(run '3\n\n\n\n\n\n\ny\n')"
check "brakująca rola jest domyślna"           '[[ "$(get DP-2 ROLE)" == secondary ]]'
reset; touch "$T/third"; out="$(run '3\n\n\n\n\nprimary\n\ny\n')"
check "nowy primary zastępuje starego"         '[[ "$(get DP-2 ROLE)" == primary && "$(get eDP-2 ROLE)" == other ]]'
reset; touch "$T/third"; cp "$T/gen.py" "$A/scripts/wallpapers/gen_dither_flux_wallpaper.py"; out="$(run '3\n\n\n\n\n\n\ny\n')"
for _ in $(seq 1 100); do [[ -s "$T/gen" ]] && break; /usr/bin/sleep 0.02; done
check "tapety dither pod nowy rozmiar w tle"   'grep -q "m-DP-2:2560x1440" "$T/gen" && [[ "$out" == *"generated in the background"* ]]'
reset; cp "$T/gen.py" "$A/scripts/wallpapers/gen_dither_flux_wallpaper.py"; out="$(run '1\n1\n\n\n\ny\n')"
for _ in $(seq 1 100); do [[ -s "$T/gen" ]] && break; /usr/bin/sleep 0.02; done
check "zmiana rozdzielczości też je generuje"  'grep -q "v1:2560x1440" "$T/gen"'

echo "== numeracja z menu"
reset; sed -i 's/^POSITION=.*/POSITION=4000x0/' "$D/eDP-2.dat"; out="$(run 'r\n\n\n')"
check "r numeruje od lewej"                    '[[ "$(get HDMI-A-1 ORDER)" == 1 && "$(get eDP-2 ORDER)" == 2 ]]'
check "r przepisuje workspace-y"               'grep -q "hl.workspace_rule" "$WS" && grep -qx "guard --rehome" "$T/after" && grep -q "hyprctl reload" "$T/log"'
reset; out="$(run 'r\n\n\n')"
check "bez zmian bez reloadu"                  '[[ "$out" == *"Nothing changed"* ]] && ! grep -q "hyprctl reload" "$T/log" && unchanged'

echo "== usuwanie odpiętego"
reset; touch "$T/offline"; out="$(run '2\ny\n\n')"
check "wpis usunięty"                          '[[ ! -e "$D/HDMI-A-1.dat" && "$out" == *"forgotten"* ]]'
check "reguła workspace-ów znika"              '! grep -q "HDMI-A-1\", default" "$WS" && grep -qx "guard --rehome" "$T/after"'
reset; touch "$T/offline"; out="$(run '2\nn\n\n')"
check "odmowa zostawia wpis"                   'unchanged'
reset; touch "$T/offline"; sed -i 's/^ROLE=.*/ROLE=primary/' "$D/HDMI-A-1.dat"; sed -i 's/^ROLE=.*/ROLE=secondary/' "$D/eDP-2.dat"; out="$(run '2\ny\n\n')"
check "primary przechodzi na podłączony"       '[[ "$(get eDP-2 ROLE)" == primary && "$(get eDP-2 ORDER)" == 1 ]]'
reset; printf 'MONITOR=DP-9\nRESOLUTION=1920x1080\nRATE=60\nPOSITION=0x0\nSCALE=1\nROLE=primary\nDESCRIPTION=Gone 9\nORDER=1\n' > "$D/DP-9.dat"; rm "$D/eDP-2.dat" "$D/HDMI-A-1.dat"; out="$(run '1\ny\n\n')"
check "ostatni wpis zostaje"                   '[[ -e "$D/DP-9.dat" && "$out" == *"only saved monitor"* ]]'
rm -f "$D/DP-9.dat"

echo "== powiadomienie"
notify() { bash "$A/scripts/hypr/monitor-settings.sh" notify; }
reset; touch "$T/third"; echo 100 > "$T/age"; notify
check "nowy monitor: powiadomienie"            'grep -q "DP-2: Super+A → \[n\]" "$T/notified"'
reset; echo 100 > "$T/age"; notify
check "znany monitor: cisza"                   '[[ ! -s "$T/notified" ]]'
reset; touch "$T/third"; echo 5 > "$T/age"; notify
check "start sesji: cisza"                     '[[ ! -s "$T/notified" ]]'

echo "== skrót"
reset
check "dwa ekrany"                             '[[ "$(summary)" == "2 screens" ]]'
touch "$T/offline"; rm "$D/HDMI-A-1.dat"
check "jeden ekran = tryb"                     '[[ "$(summary)" == 1920x1080@60.00 ]]'
rm "$D"/*.dat; out="$(run '\n')"
check "brak danych o monitorach"               '[[ "$out" == *"No monitor data"* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
