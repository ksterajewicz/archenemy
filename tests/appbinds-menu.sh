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
cp "$REPO"/scripts/hypr/lib/{gen-workspaces,gen-monitors,monitor-id,hypr-apply}.sh "$A/scripts/hypr/lib/"
cp "$REPO/scripts/hypr/monitor-settings.sh" "$A/scripts/hypr/"
mkdir -p "$A/scripts/appbinds/lib"; cp "$REPO/scripts/appbinds/lib/tui.sh" "$A/scripts/appbinds/lib/"
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

echo "== menu główne"
cp "$REPO"/scripts/hypr/{keyboard-layouts,mouse-settings}.sh "$A/scripts/hypr/"
mkdir -p "$A/scripts/appbinds"
printf '#!/bin/bash\nread -r x < "%s/sink" && echo "$x"\n' "$T" > "$A/scripts/appbinds/audio-devices.sh"
echo "Family 17h HD Audio Controller Speaker + Headphones" > "$T/sink"
printf 'de,us\n' > "$A/data/keyboard-layouts.dat"; echo 0.3 > "$A/data/mouse-sensitivity.dat"
printf 'firefox\n# x\n\nsteam\n' > "$A/data/autostart-apps.dat"
echo ticks > "$A/data/volume-bar-style.dat"; echo 1 > "$A/data/timer-enabled.dat"; echo decades > "$A/data/workspace-mode.dat"
out="$(tui 'q')"
check "nagłówek mówi, czym to jest (R2)"       '[[ "$out" == *"archenemy  settings"* ]]'
check "grupy"                                  '[[ "$out" == *"Binds"*"Desktop"*"Bar"*"Apps"*"System"* ]]'
check "stan: workspace i monitor"              '[[ "$out" =~ w\ +workspaces\ +decades && "$out" =~ n\ +monitors\ +1920x1080@60 ]]'
check "stan: klawiatura i mysz"                '[[ "$out" =~ k\ +keyboard\ +de,us && "$out" =~ m\ +mouse\ +0.3 ]]'
check "stan: pasek i timer"                    '[[ "$out" =~ v\ +volume\ bar\ +ticks && "$out" =~ t\ +timer\ +on ]]'
check "stan: autostart bez komentarzy"         '[[ "$out" =~ u\ +autostart\ +2\ apps ]]'
check "długi opis audio ucięty"                '[[ "$out" == *"Family 17h HD Audio"*"…"* ]]'
check "podpowiedź klawiszy"                    '[[ "$out" == *"↑↓ move"*"Enter or letter open"*"q quit"* ]]'
check "ekran mieści się w oknie 27×90"         '[[ "$(wc -l <<<"$out")" -le 27 && "$(wc -L <<<"$out")" -le 90 ]]'

echo "== strzałki i Enter"
out="$(tui '\e[B\n\n\nq')"
check "w dół + Enter otwiera drugą pozycję"    '[[ "$out" == *"archenemy  edit bind"* ]]'
out="$(tui '\e[A\nq')"
check "w górę z pierwszej = ostatnia"          '[[ "$out" == *"Commit"* ]]'
out="$(tui '\e[F\e[B\e[H\nq')"
check "End, zawinięcie, Home"                  '[[ "$(grep -c "Update" <<<"$out")" -ge 1 ]]'
out="$(tui 'xzq')"
check "nieznana litera nic nie otwiera"        '[[ "$out" != *"Press Enter"* ]]'
tui 'v\e\n\e[Bq' >/dev/null; rc=$?
check "po akcji pętla działa dalej"            '[[ $rc -eq 0 ]]'

echo "== podgląd"
reset; tui 'ag\nls c\\d\n\nq' >/dev/null
out="$(tui 'q')"
check "skrót w podglądzie"                     '[[ "$out" == *"1  Super g"*"ls c"* ]]'
check "backslash nie jest sekwencją"           '[[ "$out" == *"c\d"* ]]'
reset; out="$(tui 'q')"
check "pusta lista skrótów"                    '[[ "$out" == *"No binds yet."* ]]'
out="$(tui '\e[B\e[B\e[B\e[B\e[B\e[Bq')"
check "podgląd [k]: układy"                    '[[ "$out" == *"2  us"*"Super+Ctrl+2"* ]]'
out="$(tui '\e[A\e[A\e[A\e[A\e[Aq')"
check "podgląd [u]: aplikacje"                 '[[ "$out" == *"firefox"* || "$out" == *"steam"* ]]'
out="$(tui '\e[A\e[A\e[Aq')"
check "podgląd [o]: wyjście i wejście"         '[[ "$out" == *"Output"*"Input"* ]]'
out="$(tui '\e[A\e[Aq')"
check "podgląd [i]: opis"                      '[[ "$out" == *"config check"* ]]'

echo "== rozmiar okna"
out="$(ARCHENEMY_TUI_SIZE="27 60" tui 'q')"
check "wąskie okno: bez podglądu, ile wejdzie" '[[ "$out" != *"│"* && "$out" == *"workspaces"* && "$(wc -L <<<"$out")" -le 60 ]]'
out="$(ARCHENEMY_TUI_SIZE="14 90" tui 'q')"
check "niskie okno mieści się"                 '[[ "$(wc -l <<<"$out")" -le 14 ]]'
out="$(ARCHENEMY_TUI_SIZE="14 90" tui '\e[A\e[Fq')"
check "zaznaczenie jedzie z oknem"             '[[ "$(tail -14 <<<"$out")" == *"update archenemy"* ]]'

echo "== akcent wg rice'a"
echo white-blue > "$A/.current_rice"
raw="$(printf q | timeout 10 bash "$REPO/scripts/appbinds/appbinds.sh" 2>&1)"
check "white-blue: bright blue"                '[[ "$raw" == *$'"'"'\e[0;94m'"'"'* ]]'
check "bez zwykłego ANSI blue"                 '[[ "$raw" != *$'"'"'\e[0;34m'"'"'* ]]'
echo tron > "$A/.current_rice"
raw="$(printf q | timeout 10 bash "$REPO/scripts/appbinds/appbinds.sh" 2>&1)"
check "tron: bright cyan"                      '[[ "$raw" == *$'"'"'\e[0;96m'"'"'* ]]'
rm "$A/.current_rice"

rm -f "$A/scripts/appbinds/audio-devices.sh" "$A/scripts/hypr/keyboard-layouts.sh"
out="$(tui 'q')"
check "brak skryptu = sama etykieta"           '[[ "$out" =~ o\ +audio && "$out" =~ k\ +keyboard ]]'

echo "== [n] monitory"
out="$(tui 'n\n\nq')"
check "[n] otwiera monitory"                   '[[ "$out" == *"archenemy  monitors"* ]]'

echo "== [i] diagnostyka"
printf '#!/bin/bash\necho report-ok\nexit 0\n' > "$A/scripts/hypr/machine-layer-check.sh"
printf '#!/bin/bash\necho ws-dump\n' > "$A/scripts/hypr/workspace-diag.sh"
out="$(tui 'i1\nq')"
check "kontrola: raport i wynik"               '[[ "$out" == *"report-ok"*"Config matches"* ]]'
printf '#!/bin/bash\necho bad\nexit 1\n' > "$A/scripts/hypr/machine-layer-check.sh"
out="$(tui 'i1\nq')"
check "kontrola: problemy bez sukcesu"         '[[ "$out" == *"Problems found"* && "$out" != *"Config matches"* ]]'
out="$(tui 'i2\nq')"
check "zrzut w pliku i na ekranie"             '[[ "$out" == *"ws-dump"*"Saved to"* ]] && grep -qx ws-dump "$H"/archenemy-diag-workspaces-*.txt'
out="$(tui 'i3\nq')"
check "brak skryptu zgłoszony"                 '[[ "$out" == *"Missing"*"gaming-diag.sh"* ]]'
printf '#!/bin/bash\nexit 0\n' > "$A/scripts/hypr/gaming-diag.sh"
out="$(tui 'i3\nq')"
check "pusty zrzut to nie sukces"              '[[ "$out" == *"produced no output"* && "$out" != *"Saved to"* ]] && ! ls "$H"/archenemy-diag-gaming-* >/dev/null 2>&1'
out="$(tui 'i\nq')"
check "Enter anuluje"                          '[[ "$out" == *"Cancelled"* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
