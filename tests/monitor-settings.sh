#!/bin/bash
# =============================================
#   archenemy - tests/monitor-settings.sh
#   Zmiana monitora Super+A → [n] (scripts/hypr/monitor-settings.sh) na atrapie
#   hyprctl, która czyta wygenerowany monitorshyprl.lua. Bez Hyprlanda, zapis
#   tylko w mktemp.
#
#   Powód powstania (audyt TUI 2026-11-05): monitory dało się zmienić tylko
#   przez install.sh, a zły tryb na żywo może zostawić czarny ekran.
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
mkdir -p "$D" "$A/config/hypr" "$A/scripts/hypr/lib" "$A/scripts/appbinds/lib" "$T/bin"
cp "$REPO"/scripts/hypr/lib/{monitor-id,gen-monitors,hypr-apply}.sh "$A/scripts/hypr/lib/"
cp "$REPO/scripts/appbinds/lib/tui.sh" "$A/scripts/appbinds/lib/"
cp "$REPO/scripts/hypr/monitor-settings.sh" "$A/scripts/hypr/"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/clear"; printf '#!/bin/bash\nexit 0\n' > "$T/bin/sleep"

# Atrapa hyprctl: `monitors` w formacie src/ipc/s1/Commands.cpp, reload stosuje
# reguły z pliku Lua. `dead` = brak odpowiedzi, `badscale` = błąd configu,
# `stubborn` = Hyprland ignoruje skalę, `offline` = HDMI-A-1 odpięty.
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
  reload) if grep -q 'scale = 9' "$LUA"; then echo 'hl.monitor: bad scale' > "$T/errors"; else : > "$T/errors"; fi; echo ok ;;
  configerrors) cat "$T/errors" 2>/dev/null; echo ;;
  monitors)
    show eDP-1 0 "\$(rule 'desc:Maker Panel 123')" 'Maker Panel 123 (eDP-1)'
    [[ -f "$T/offline" ]] || show HDMI-A-1 1 "\$(rule 'HDMI-A-1')" 'x"y'
    ;;
esac
EOS
chmod +x "$T/bin/"*
export HOME="$H" PATH="$T/bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test

reset() {
    printf 'MONITOR=eDP-2\nRESOLUTION=1920x1080\nRATE=60.00\nPOSITION=0x0\nSCALE=1\nROLE=primary\nDESCRIPTION=Maker Panel 123\nORDER=1\n' > "$D/eDP-2.dat"
    printf 'MONITOR=HDMI-A-1\nRESOLUTION=1920x1080\nRATE=60.00\nPOSITION=1920x0\nSCALE=1\nROLE=secondary\nDESCRIPTION=x"y\nORDER=2\n' > "$D/HDMI-A-1.dat"
    ( source "$A/scripts/hypr/lib/monitor-id.sh"; source "$A/scripts/hypr/lib/gen-monitors.sh"; generate_monitors_conf "$LUA" "$D" )
    cp "$D/eDP-2.dat" "$T/dat.orig"; cp "$LUA" "$T/lua.orig"
    : > "$T/log"; : > "$T/errors"; rm -f "$T/dead" "$T/stubborn" "$T/offline"
}
run() { printf "$1" | timeout 10 bash "$A/scripts/hypr/monitor-settings.sh" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
get() { grep -m1 "^$2=" "$D/$1.dat" | cut -d= -f2-; }
unchanged() { cmp -s "$D/eDP-2.dat" "$T/dat.orig" && cmp -s "$LUA" "$T/lua.orig"; }

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
reset; out="$(run '1\n1\n\n1.5\ny\n')"
check "tryb z listy zapisany"                  '[[ "$(get eDP-2 RESOLUTION)" == 2560x1440 && "$(get eDP-2 RATE)" == 165.00 ]]'
check "skala zapisana"                         '[[ "$(get eDP-2 SCALE)" == 1.5 ]]'
check "numer, rola i opis bez zmian"           '[[ "$(get eDP-2 ORDER)" == 1 && "$(get eDP-2 ROLE)" == primary && "$(get eDP-2 DESCRIPTION)" == "Maker Panel 123" ]]'
check "Lua z selektorem desc:"                 'grep -q "desc:Maker Panel 123\", mode = \"2560x1440@165.00\", position = \"0x0\", scale = 1.5" "$LUA"'
check "sukces pokazuje stan z Hyprlanda"       '[[ "$out" == *"✓ Monitor eDP-1: 2560x1440 165.00 0x0 1.5"* ]]'
check "uwaga o tapetach dither"                '[[ "$out" == *"dither-flux"* ]]'
check "bez plików tymczasowych"                '[[ "$(find "$D" "$A/config/hypr" -name "*.??????" | wc -l)" == 0 ]]'

echo "== duplikat trybu"
reset; out="$(run '1\n4\n\n\ny\n')"
check "lista bez powtórzeń"                    '[[ "$out" == *"Pick a number"* ]]'

echo "== cofnięcie"
reset; out="$(run '1\n1\n\n\nn\n')"
check "inny klawisz cofa"                      'unchanged && [[ "$out" == *"Back to the previous"* ]]'
check "po cofnięciu drugi reload"              '[[ "$(grep -c "hyprctl reload" "$T/log")" == 2 ]]'
reset; out="$(run '1\n1\n\n\n')"
check "brak klawisza cofa"                     'unchanged'
reset; out="$(run '1\n\n\n9\n\n')"
check "błąd configu cofa"                      'unchanged && [[ "$out" == *"config error"*"bad scale"* ]]'
reset; touch "$T/dead"; out="$(run '1\n1\n\n\n\n')"; rm "$T/dead"
check "martwy Hyprland cofa"                   'unchanged'
reset; ( printf '1\n1\n\n\n'; /usr/bin/sleep 2 ) | bash "$A/scripts/hypr/monitor-settings.sh" >/dev/null 2>&1 &
pid=$!
for _ in $(seq 1 200); do grep -q "hyprctl reload" "$T/log" && break; /usr/bin/sleep 0.02; done
/usr/bin/sleep 0.2; kill -HUP "$pid"; wait "$pid"
check "zamknięcie okna cofa"                   'unchanged'

echo "== bez sesji"
reset; out="$(printf '1\n\n\n2\n\n' | HYPRLAND_INSTANCE_SIGNATURE= bash "$A/scripts/hypr/monitor-settings.sh" 2>&1)"
check "bez Hyprlanda brak żywego monitora"     '[[ "$out" == *"not connected"* || "$out" == *"No Hyprland"* ]]'

echo "== walidacja"
reset; out="$(run '1\n\nfoo\n10x10\nabc\n0\n1.25\ny\n')"
check "zła pozycja i skala pytają ponownie"    '[[ "$out" == *"Use XxY"*"Use a positive number"* ]]'
check "poprawne wartości zapisane"             '[[ "$(get eDP-2 POSITION)" == 10x10 && "$(get eDP-2 SCALE)" == 1.25 ]]'
reset; out="$(run '1\n\n\n\n\n')"
check "bez zmian nic nie przeładowuje"         '[[ "$out" == *"Nothing changed"* ]] && ! grep -q "hyprctl reload" "$T/log"'

echo "== odczyt stanu"
reset; touch "$T/stubborn"; out="$(run '1\n\n\n2\ny\n')"
check "inna skala w Hyprlandzie = ostrzeżenie" '[[ "$out" == *"Hyprland shows something else"* ]]'

echo "== numeracja"
reset; out="$(run '1\n\n4000x0\n\ny\n')"
check "pozycja rozjeżdża numery → uwaga"       '[[ "$out" == *"no longer run left to right"* ]]'
check "numer zostaje"                          '[[ "$(get eDP-2 ORDER)" == 1 ]]'
reset; out="$(run '1\n\n100x0\n\ny\n')"
check "ta sama kolejność bez uwagi"            '[[ "$out" != *"left to right"* ]]'

echo "== skrót"
reset
check "dwa ekrany"                             '[[ "$(bash "$A/scripts/hypr/monitor-settings.sh" summary)" == "2 screens" ]]'
rm "$D/HDMI-A-1.dat"
check "jeden ekran = tryb"                     '[[ "$(bash "$A/scripts/hypr/monitor-settings.sh" summary)" == 1920x1080@60.00 ]]'
rm "$D"/*.dat; out="$(run '\n')"
check "brak danych o monitorach"               '[[ "$out" == *"No monitor data"* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
