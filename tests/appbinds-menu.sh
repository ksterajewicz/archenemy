#!/bin/bash
# =============================================
#   archenemy - tests/appbinds-menu.sh
#   Prawdziwe menu TUI Super+A sterowane z wejścia standardowego, na fałszywym
#   HOME i atrapie hyprctl. Bez Hyprlanda, zapis tylko w mktemp.
#
#   Powód powstania (audyt TUI 2026-11-05, F1–F3): reload meldował sukces bez
#   sprawdzenia, a [a] przyjmowało klawisz, którego Hyprland nie zna.
#   Uruchom: bash tests/appbinds-menu.sh   (kod 0 = wszystko przeszło)
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

H="$T/home"; A="$H/archenemy"; BINDS="$A/config/hypr/appbinds.lua"
mkdir -p "$A/config/hypr" "$A/data/monitors" "$H/.config/hypr" "$T/bin" "$A/scripts/waybar/lib" "$A/scripts/hypr/lib"
cp "$REPO"/scripts/waybar/lib/timer-state.sh "$A/scripts/waybar/lib/"
cp "$REPO"/scripts/waybar/timer-ctl.sh "$A/scripts/waybar/"
cp "$REPO"/scripts/hypr/workspace-mode-switch.sh "$A/scripts/hypr/"
cp "$REPO"/scripts/hypr/lib/{gen-workspaces,monitor-id,hypr-apply}.sh "$A/scripts/hypr/lib/"
printf 'MONITOR=DP-1\nRESOLUTION=1920x1080\nRATE=60\nPOSITION=0x0\nSCALE=1\nROLE=primary\nDESCRIPTION=\nORDER=1\n' > "$A/data/monitors/DP-1.dat"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/pkill"; printf '#!/bin/bash\nexit 1\n' > "$T/bin/pgrep"; printf '#!/bin/bash\nexit 0\n' > "$T/bin/notify-send"; printf '#!/bin/bash\nexit 0\n' > "$T/bin/setsid"
printf 'hl.bind(mainMod .. " + Q", hl.dsp.window.close())\nhl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))\n' > "$H/.config/hypr/hyprland.lua"
printf '#define XKB_KEY_F5 0xffc2\n#define XKB_KEY_semicolon 0x3b\n#define XKB_KEY_Return 0xff0d\n' > "$T/keysyms.h"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/clear"
# Atrapa hyprctl: reload ocenia appbinds.lua; klawisz `badkey` = błąd configu.
cat > "$T/bin/hyprctl" <<EOS
#!/bin/bash
echo "hyprctl \$*" >> "$T/log"
[[ -f "$T/dead" ]] && exit 1
case "\$1" in
  reload) if grep -q badkey "$BINDS" 2>/dev/null; then echo 'hl.bind: Unknown key: badkey' > "$T/errors"; else : > "$T/errors"; fi; echo ok ;;
  configerrors) cat "$T/errors" 2>/dev/null; echo ;;
esac
EOS
chmod +x "$T/bin/"*
export HOME="$H" PATH="$T/bin:$PATH" ARCHENEMY_XKB_KEYSYMS="$T/keysyms.h" HYPRLAND_INSTANCE_SIGNATURE=test

tui() { printf "$1" | timeout 10 bash "$REPO/scripts/appbinds/appbinds.sh" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
reset() { printf -- '-- generated\nlocal mainMod = "SUPER"\n' > "$BINDS"; : > "$T/log"; : > "$T/errors"; }

echo "== [a] dodawanie"
reset; out="$(tui 'ag\nls\n\nq')"
check "bind zapisany"                     'grep -Fq "hl.bind(mainMod .. \" + g\", hl.dsp.exec_cmd(\"ls\"))" "$BINDS"'
check "sukces po odczycie configerrors"   '[[ "$out" == *"no config errors"* ]] && grep -q "hyprctl configerrors" "$T/log"'
reset; out="$(tui 'ashift+F5\nls\n\nq')"
check "SHIFT+F5 w formacie pliku"         'grep -Fq " + SHIFT + F5\"" "$BINDS"'
check "na liście z modyfikatorem"         '[[ "$out" == *"Super + SHIFT + F5"* ]]'
reset; tui 'aalt+shift+g\nls\n\nq' >/dev/null
check "stała kolejność modyfikatorów"     'grep -Fq " + SHIFT + ALT + g\"" "$BINDS"'
reset; out="$(tui 'ag\nnotify-send "a b" c\\d\ny\n\nq')"
check "cudzysłów i backslash uciekają"    'grep -Fq "exec_cmd(\"notify-send \\\"a b\\\" c\\\\d\"))" "$BINDS"'
check "lista pokazuje czystą komendę"     '[[ "$out" == *"→ notify-send \"a b\" c\\d"* ]]'

echo "== [a] odrzucanie"
reset; out="$(tui 'afoo\n\nq')"
check "nieznany klawisz odrzucony (F2)"   '[[ "$out" == *"not a key name"* ]] && ! grep -q foo "$BINDS"'
reset; out="$(tui 'a1+2+g\n\nq')"
check "zły modyfikator odrzucony"         '[[ "$out" == *"does not look like a key"* ]]'
reset; out="$(tui 'aq\n\nq')"
check "zajęty klawisz, inna wielkość"     '[[ "$out" == *"already taken"* ]]'
reset; out="$(tui 'ashift+f\n\nq')"
check "zajęta kombinacja z SHIFT"         '[[ "$out" == *"already taken"* ]]'
reset; out="$(tui 'ashift_r\n\nq')"
check "klawisz-modyfikator odrzucony"     '[[ "$out" == *"modifier key"* ]]'

echo "== [a] Hyprland nie przyjmuje"
reset; rm "$T/keysyms.h"; before="$(cat "$BINDS")"
out="$(tui 'abadkey\nls\n\nq')"
check "błąd configu zgłoszony (F1)"       '[[ "$out" == *"config error"* && "$out" == *"Unknown key"* ]]'
check "brak fałszywego sukcesu"           '[[ "$out" != *"no config errors"* ]]'
check "bind cofnięty"                     '[[ "$(cat "$BINDS")" == "$before" ]]'
printf '#define XKB_KEY_F5 0xffc2\n' > "$T/keysyms.h"
reset; touch "$T/dead"; out="$(tui 'ag\nls\n\nq')"; rm "$T/dead"
check "martwy Hyprland: bez ✓ reloadu"    '[[ "$out" != *"no config errors"* && "$out" == *"did not respond"* ]]'
reset; out="$(HYPRLAND_INSTANCE_SIGNATURE='' tui 'ag\nls\n\nq')"
check "bez sesji: wejdzie przy starcie"   '[[ "$out" == *"applies when Hyprland starts"* ]]'

echo "== [e] edycja i [d] usuwanie"
reset; printf 'hl.bind(mainMod .. " + g", hl.dsp.exec_cmd("ls"))\nhl.bind(mainMod .. " + h", hl.dsp.exec_cmd("pwd"))\n' >> "$BINDS"
tui 'e2\ndate\n\nq' >/dev/null
check "[e] zmienia komendę wybranego"     'grep -Fq " + h\", hl.dsp.exec_cmd(\"date\"))" "$BINDS" && grep -Fq "exec_cmd(\"ls\")" "$BINDS"'
out="$(tui 'e1\n\n\nq')"
check "[e] Enter nic nie zmienia"         '[[ "$out" == *Cancelled* ]] && grep -Fq "exec_cmd(\"ls\")" "$BINDS"'
out="$(tui 'd1\n\nq')"
check "[d] usuwa i sprawdza reload"       '! grep -Fq "\"ls\"" "$BINDS" && [[ "$out" == *"no config errors"* ]]'

echo "== bindy pisane ręcznie"
reset; printf 'hl.bind("SUPER + x", hl.dsp.exec("xterm"))\n' >> "$BINDS"
out="$(tui 'q')"
check "menu mówi o bindzie spoza listy"   '[[ "$out" == *"1 written by hand"* ]]'

echo "== [v] pasek głośności"
reset; out="$(tui 'v2\n\nq')"
check "wybór zapisany"                         '[[ "$(<"$A/data/volume-bar-style.dat")" == ticks && "$out" == *"Volume bar style: ticks"* ]]'
out="$(tui 'vx\n\nq')"
check "zły klawisz bez zmiany"                 '[[ "$(<"$A/data/volume-bar-style.dat")" == ticks && "$out" == *"Pick 1, 2 or 3"* ]]'
out="$(tui 'v\n\nq')"
check "Enter anuluje"                          '[[ "$out" == *"Cancelled"* ]]'
check "bez bety bez ostrzeżenia"               '[[ "$out" != *"white-blue_beta"* ]]'

echo "== [t] timer"
out="$(tui 't1\n\nq')"
check "włączenie zapisane"                     '[[ "$(<"$A/data/timer-enabled.dat")" == 1 && "$out" == *"Timer shown"* ]]'
out="$(tui 't240\n\nq')"
check "czas zapisany"                          '[[ "$(<"$A/data/timer-duration.dat")" == 40 ]]'
out="$(tui 't20\n\nq')"
check "czas spoza zakresu odrzucony"           '[[ "$(<"$A/data/timer-duration.dat")" == 40 && "$out" == *"not a number between"* ]]'
out="$(tui 't300ff00\n\nq')"
check "kolor dostaje #"                        '[[ "$(<"$A/data/timer-color.dat")" == "#00ff00" ]]'
out="$(tui 't3zielony\n\nq')"
check "zły kolor odrzucony"                    '[[ "$(<"$A/data/timer-color.dat")" == "#00ff00" && "$out" == *"not a #rrggbb"* ]]'

echo "== ostrzeżenie dla bety"
echo white-blue_beta > "$A/.current_rice"
out="$(tui 'v\n\nq')"
check "[v] ostrzega na becie (R4)"             '[[ "$out" == *"white-blue_beta has no volume bar"* ]]'
out="$(tui 't\n\nq')"
check "[t] ostrzega na becie (R4)"             '[[ "$out" == *"white-blue_beta has no timer"* ]]'
rm "$A/.current_rice"

echo "== [w] tryb workspace'ów"
echo decades > "$A/data/workspace-mode.dat"; reset
out="$(tui 'w\n\nq')"
check "Enter nie zmienia trybu"                '[[ "$(<"$A/data/workspace-mode.dat")" == decades && "$out" == *"Cancelled"* ]]'
out="$(tui 'wy\n\nq')"
check "tryb zmieniony i plik wygenerowany"     '[[ "$(<"$A/data/workspace-mode.dat")" == shared && -s "$A/config/hypr/workspaces-monitors.lua" ]]'
check "sukces po odczycie configerrors (F3)"   '[[ "$out" == *"no config errors"* ]] && grep -q "hyprctl configerrors" "$T/log"'
touch "$T/dead"; out="$(tui 'wy\n\nq')"; rm "$T/dead"
check "martwy Hyprland bez sukcesu (F3)"       '[[ "$out" == *"did not respond"* && "$out" != *"no config errors"* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
