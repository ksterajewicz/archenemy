#!/usr/bin/env bash
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
# shellcheck source=tests/lib/timing.sh
source "$REPO/tests/lib/timing.sh"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1
test_timing_init "$T"

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
mkdir -p "$A/scripts/lib"; cp "$REPO/scripts/lib/runtime-dir.sh" "$A/scripts/lib/"   # katalog sesji (S12)
mkdir -p "$A/scripts/appbinds/lib"; cp "$REPO/scripts/appbinds/lib/tui.sh" "$A/scripts/appbinds/lib/"
printf 'MONITOR=DP-1\nRESOLUTION=1920x1080\nRATE=60\nPOSITION=0x0\nSCALE=1\nROLE=primary\nDESCRIPTION=\nORDER=1\n' > "$A/data/monitors/DP-1.dat"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/pkill"; printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pgrep"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/notify-send"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/setsid"
printf 'hl.bind(mainMod .. " + Q", hl.dsp.window.close())\nhl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))\n' > "$H/.config/hypr/hyprland.lua"
printf '#define XKB_KEY_F5 0xffc2\n#define XKB_KEY_semicolon 0x3b\n#define XKB_KEY_Return 0xff0d\n' > "$T/keysyms.h"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/clear"
# Atrapa hyprctl: reload ocenia appbinds.lua; klawisz `badkey` albo plik
# $T/failreload = błąd configu. Plik $T/autoreload = Hyprland z autoreloadem
# (misc:disable_autoreload = false): plik wczytany przez inotify zaraz po
# zapisie, więc błąd jest w configerrors, zanim padnie `hyprctl reload` —
# `badkey` w bindach albo plik reguł workspace'ów podmieniony (inny i-węzeł niż
# zapisany w $T/ws.inode).
cat > "$T/bin/hyprctl" <<EOS
#!/usr/bin/env bash
echo "hyprctl \$*" >> "$T/log"
[[ -f "$T/dead" ]] && exit 1
case "\$1" in
  reload) if grep -q badkey "$BINDS" 2>/dev/null || [[ -f "$T/failreload" ]]; then echo 'hl.bind: Unknown key: badkey' > "$T/errors"; else : > "$T/errors"; fi; echo ok ;;
  configerrors)
    if [[ -f "$T/autoreload" ]]; then
      if grep -q badkey "$BINDS" 2>/dev/null; then echo 'hl.bind: Unknown key: badkey'
      elif [[ -f "$T/ws.inode" && "\$(stat -c %i "$A/config/hypr/workspaces-monitors.lua")" != "\$(cat "$T/ws.inode")" ]]; then echo 'hl.workspace_rule: bad rule'; fi
    else cat "$T/errors" 2>/dev/null; fi
    echo ;;
  monitors) cat "$T/hypr-monitors" 2>/dev/null ;;
esac
EOS
# Atrapa systemctl: usługa motywów systemowych „działa”, gdy jest plik
# theme-service-active ([l] system logo, [g] login screen).
cat > "$T/bin/systemctl" <<EOS
#!/usr/bin/env bash
echo "systemctl \$*" >> "$T/log"
[[ "\$1" == is-active ]] && { [[ -f "$T/theme-service-active" ]]; exit; }
exit 0
EOS
# Atrapy procesów: guard „żyje”, gdy setsid go wystartował (plik guard-alive),
# chyba że guard-broken; waybar żyje, gdy jest plik waybar-alive.
cat > "$T/bin/pgrep" <<EOS
#!/usr/bin/env bash
case "\$*" in
  *workspace-orphan-guard*) [[ -f "$T/guard-alive" ]] ;;
  *waybar*) [[ -f "$T/waybar-alive" ]] && echo 4242 ;;
  *) exit 1 ;;
esac
EOS
# Atrapa ps: czas życia waybara (pid 4242) z pliku waybar-etimes (domyślnie
# doba). Stary config = plik w ~/.config/waybar zmieniony po starcie paska.
cat > "$T/bin/ps" <<EOS
#!/usr/bin/env bash
if [[ "\$*" == "-o etimes= -p 4242" ]]; then cat "$T/waybar-etimes" 2>/dev/null || echo 86400; exit 0; fi
exec "$(command -v ps)" "\$@"
EOS
cat > "$T/bin/setsid" <<EOS
#!/usr/bin/env bash
[[ "\$*" == *workspace-orphan-guard* && ! -f "$T/guard-broken" ]] && touch "$T/guard-alive"
exit 0
EOS
# pkill trafia tylko w żywego waybara (jak prawdziwy: kod 1 bez procesu);
# plik pkill-fails = waybar jest, ale sygnał nie dochodzi.
cat > "$T/bin/pkill" <<EOS
#!/usr/bin/env bash
echo "pkill \$*" >> "$T/log"
[[ -f "$T/waybar-alive" && ! -f "$T/pkill-fails" ]]
EOS
touch "$T/waybar-alive"
# mv, które nie umie zapisać pliku o nazwie z mv-fails (pełny dysk).
REAL_MV="$(command -v mv)"
cat > "$T/bin/mv" <<EOS
#!/usr/bin/env bash
if [[ -f "$T/mv-fails" && "\${!#}" == */"\$(<"$T/mv-fails")" ]]; then echo "mv: cannot move" >&2; exit 1; fi
exec "$REAL_MV" "\$@"
EOS
chmod +x "$T/bin/"*
# Krótsze czekanie na start guarda niż domyślna sekunda (atrapa setsid działa w tle).
export ARCHENEMY_GUARD_SETTLE=0.3
export HOME="$H" PATH="$T/bin:$PATH" ARCHENEMY_XKB_KEYSYMS="$T/keysyms.h" HYPRLAND_INSTANCE_SIGNATURE=test

tui() { printf "$1" | test_timeout 10 bash "$REPO/scripts/appbinds/appbinds.sh" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }
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
reset; touch "$T/autoreload"; out="$(tui 'abadkey\nls\n\nq')"; rm "$T/autoreload"
check "autoreload przed reloadem: błąd zgłoszony (A2)"  '[[ "$out" == *"config error"* && "$out" != *"no config errors"* ]]'
check "autoreload przed reloadem: bind cofnięty (A2)"   '[[ "$(cat "$BINDS")" == "$before" ]]'
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
before="$(cat "$BINDS")"
out="$(tui 'd1\n\nq')"
check "[d] Enter nie usuwa" '[[ "$(cat "$BINDS")" == "$before" ]]'
out="$(tui 'd1\ny\nq')"
check "[d] usuwa i sprawdza reload"       '! grep -Fq "\"ls\"" "$BINDS" && [[ "$out" == *"no config errors"* ]]'

echo "== [a]/[e]/[d] zielone ✓ dopiero po odczycie skutku"
# Zapis, który nie udaje się także rootowi: limit rozmiaru pliku 1 KiB przy pliku
# bindów większym niż 1 KiB. SIGXFSZ jest ignorowany, więc zapis oddaje EFBIG.
tui_nowrite() { ( trap '' XFSZ; ulimit -f 1; tui "$1" ); }
big() {
    local i
    reset; printf 'hl.bind(mainMod .. " + g", hl.dsp.exec_cmd("ls"))\n' >> "$BINDS"
    for i in $(seq 30); do echo "-- padding $i ................................................"; done >> "$BINDS"
    before="$(cat "$BINDS")"
}
reset; out="$(tui 'ag\nls\n\nq')"
check "[a] ✓ Added dopiero po wyniku reloadu"     '[[ "$out" == *"no config errors"*"✓ Added: Super + g"* ]]'
rm -f "$T/keysyms.h"; reset; out="$(tui 'abadkey\nls\n\nq')"; printf '#define XKB_KEY_F5 0xffc2\n' > "$T/keysyms.h"
check "[a] błąd configu: bez ✓ Added"             '[[ "$out" != *"✓ Added"* && "$out" == *"removed again"* ]]'
reset; touch "$T/dead"; out="$(tui 'ag\nls\n\nq')"; rm "$T/dead"
check "[a] martwy Hyprland: Saved, bez ✓ Added"   '[[ "$out" != *"✓ Added"* && "$out" == *"Saved: Super + g"* ]]'
big; out="$(tui_nowrite 'ah\npwd\n\nq')"
check "[a] nieudany zapis: bez ✓, plik bez zmian" '[[ "$out" != *"✓ Added"* && "$out" == *"Could not write"* && "$(cat "$BINDS")" == "$before" ]]'
check "[a] nieudany zapis: bez reloadu"           '! grep -q "hyprctl reload" "$T/log"'
big; out="$(tui 'e1\ndate\n\nq')"
check "[e] ✓ Changed dopiero po wyniku reloadu"   '[[ "$out" == *"no config errors"*"✓ Changed"* ]]'
big; out="$(tui 'e1\nbadkey\n\nq')"
check "[e] błąd configu: bez ✓ Changed, cofnięte" '[[ "$out" != *"✓ Changed"* && "$out" == *"Change undone"* && "$(cat "$BINDS")" == "$before" ]]'
big; out="$(tui_nowrite 'e1\ndate\n\nq')"
check "[e] nieudany zapis: bez ✓, plik bez zmian" '[[ "$out" != *"✓ Changed"* && "$out" == *"Could not write"* && "$(cat "$BINDS")" == "$before" ]]'
big; out="$(tui 'd1\ny\nq')"
check "[d] ✓ Removed dopiero po wyniku reloadu"   '[[ "$out" == *"no config errors"*"✓ Removed"* ]]'
big; touch "$T/failreload"; out="$(tui 'd1\ny\nq')"; rm "$T/failreload"
check "[d] błąd configu: bez ✓ Removed, bind wraca" '[[ "$out" != *"✓ Removed"* && "$out" == *"Bind restored"* && "$(cat "$BINDS")" == "$before" ]]'
big; out="$(tui_nowrite 'd1\ny\nq')"
check "[d] nieudany zapis: bez ✓, plik bez zmian" '[[ "$out" != *"✓ Removed"* && "$out" == *"Could not write"* && "$(cat "$BINDS")" == "$before" ]]'

echo "== bindy pisane ręcznie"
reset; printf 'hl.bind("SUPER + x", hl.dsp.exec("xterm"))\n' >> "$BINDS"
out="$(tui 'q')"
check "menu mówi o bindzie spoza listy"   '[[ "$out" == *"1 written by hand"* ]]'

echo "== [l] logo systemu (pasek, ekran logowania, menu startu)"
# Prawdziwy scripts/waybar/launcher-logo.sh (tryb i nazwa dystrybucji) na
# atrapie os-release; skutek = data/launcher-logo.dat ORAZ to, co skrypt
# modułu waybara wypisuje po zmianie. Rice'y: tron ma launcher, white-blue nie.
mkdir -p "$A/install/lib" "$A/rices/tron/waybar" "$A/rices/white-blue/waybar"
cp "$REPO/scripts/waybar/launcher-logo.sh" "$A/scripts/waybar/"
cp "$REPO/install/lib/pkg.sh" "$A/install/lib/"
printf '"modules-left": ["custom/launcher", "hyprland/workspaces"],\n' > "$A/rices/tron/waybar/config.jsonc"
printf '"modules-left": ["hyprland/workspaces"],\n' > "$A/rices/white-blue/waybar/config.jsonc"
printf 'NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\nID=arch\n' > "$T/os-release"
LL="$A/data/launcher-logo.dat"
ltui() { ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os-release" tui "$1"; }
bar_json() { ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os-release" bash "$A/scripts/waybar/launcher-logo.sh"; }
rm -f "$LL"; : > "$T/log"
out="$(ltui 'q')"
check "[l] stan bez pliku: distro"             '[[ "$out" =~ l\ +system\ logo\ +distro ]]'
out="$(ARCHENEMY_TUI_SIZE="40 90" ltui 'q')"   # wysokie okno: cała lista naraz
check "[l] w grupie System przed [g] i [h]"    '[[ "$out" == *"Bar"*"v  volume bar"*"t  timer"*"System"*"l  system logo"*"g  login screen"*"h  shell"* ]]'
out="$(ltui '\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[Bq')"
check "[l] podgląd: obie opcje i dystrybucja"  '[[ "$out" == *"1  distro logo"*"Arch/Fedora/NixOS glyph"*"detected: Arch Linux"*"2  archenemy logo (Æ)"* ]]'
out="$(ltui 'l2\n\nq')"
check "[l] archenemy: plik i JSON paska"       '[[ "$(<"$LL")" == archenemy && "$(bar_json)" == "{\"text\":\" \",\"class\":\"archenemy\"}" ]]'
check "[l] waybar działa: ✓ po sygnale 12"     '[[ "$out" == *"detected distro: Arch Linux"*"✓ System logo: archenemy logo (Æ)"* ]] && grep -q "^pkill -RTMIN+12 -x waybar" "$T/log"'
out="$(ltui 'q')"
check "[l] stan po zmianie: archenemy"         '[[ "$out" =~ l\ +system\ logo\ +archenemy ]]'
: > "$T/log"; out="$(ltui 'l1\n\nq')"
check "[l] distro: plik i glif w JSON paska"   '[[ "$(<"$LL")" == distro && "$(bar_json)" == "{\"text\":\"$(printf "\xf3\xb0\xa3\x87")\",\"class\":\"distro\"}" ]]'
check "[l] distro: ✓ z nazwą dystrybucji"      '[[ "$out" == *"✓ System logo: distro logo (Arch Linux)"* ]] && grep -q "^pkill -RTMIN+12 -x waybar" "$T/log"'
out="$(ltui 'lx\n\nq')"
check "[l] zły klawisz bez zmiany"             '[[ "$(<"$LL")" == distro && "$out" == *"Cancelled"* && "$out" != *"✓ System logo"* ]]'
out="$(ltui 'l\n\nq')"
check "[l] Enter anuluje"                      '[[ "$(<"$LL")" == distro && "$out" == *"Cancelled"* ]]'
rm "$T/waybar-alive"; : > "$T/log"
out="$(ltui 'l2\n\nq')"
check "[l] bez waybara: zapisane, bez ✓"       '[[ "$(<"$LL")" == archenemy && "$out" != *"✓ System logo"* && "$out" == *"Saved: system logo archenemy"*"Waybar is not running"* ]] && ! grep -q "^pkill" "$T/log"'
touch "$T/waybar-alive" "$T/pkill-fails"
out="$(ltui 'l1\n\nq')"; rm "$T/pkill-fails"
check "[l] sygnał nie doszedł: bez ✓"          '[[ "$(<"$LL")" == distro && "$out" != *"✓ System logo"* && "$out" == *"did not take the refresh signal"* ]]'
echo launcher-logo.dat > "$T/mv-fails"; out="$(ltui 'l2\n\nq')"; rm "$T/mv-fails"
check "[l] nieudany zapis: bez ✓, plik bez zmian" '[[ "$(<"$LL")" == distro && "$out" != *"✓"* && "$out" != *"Saved"* && "$out" == *"Could not write"* ]] && ! compgen -G "$LL.*" >/dev/null'
# Niezapisywalny katalog bez sztuczek z rootem: data/ to zwykły plik.
mv "$A/data" "$T/data.bak"; printf 'not a directory\n' > "$A/data"; : > "$T/log"
out="$(ltui 'l2\n\nq')"
rm "$A/data"; mv "$T/data.bak" "$A/data"
check "[l] niezapisywalny katalog: czytelny błąd" '[[ "$out" == *"✗ Could not write $LL — cannot create a file in $A/data; nothing was changed."* && "$out" != *"✓"* && "$out" != *"Saved"* ]] && ! grep -q "^pkill" "$T/log"'
check "[l] niezapisywalny katalog: stary stan"    '[[ "$(<"$LL")" == distro ]]'
echo white-blue > "$A/.current_rice"; : > "$T/log"
out="$(ltui 'l2\n\nq')"
check "[l] rice bez launchera: zapisane, bez ✓" '[[ "$(<"$LL")" == archenemy && "$out" == *"white-blue has no launcher module — the logo shows in tron"* && "$out" == *"Saved: system logo archenemy. white-blue has no launcher module"* && "$out" != *"✓ System logo"* ]] && ! grep -q "^pkill" "$T/log"'
echo white-blue_beta > "$A/.current_rice"
out="$(ltui 'l1\n\nq')"
check "[l] beta: ostrzeżenie i bez ✓"           '[[ "$(<"$LL")" == distro && "$out" == *"white-blue_beta has no launcher module"* && "$out" == *"Saved: system logo distro"* && "$out" != *"✓ System logo"* ]]'
echo tron > "$A/.current_rice"; : > "$T/log"
out="$(ltui 'l2\n\nq')"
check "[l] rice z launcherem: ✓ po sygnale 12"  '[[ "$(<"$LL")" == archenemy && "$out" == *"✓ System logo: archenemy logo (Æ)"* && "$out" != *"has no launcher"* ]] && grep -q "^pkill -RTMIN+12 -x waybar" "$T/log"'
# Waybar starszy niż config (git pull / [u] pod działającym paskiem): moduł
# nie zna "signal": 12, więc zamiast RTMIN+12 idzie SIGUSR2 (reload configu).
mkdir -p "$H/.config/waybar"; WCFG="$H/.config/waybar/config.jsonc"; touch "$WCFG"
echo 3600 > "$T/waybar-etimes"; : > "$T/log"
out="$(ltui 'l1\n\nq')"
check "[l] stary config paska: ✓ po SIGUSR2"    '[[ "$(<"$LL")" == distro && "$out" == *"✓ System logo: distro logo (Arch Linux) (waybar reloaded: its config changed since it started)"* ]] && grep -q "^pkill -USR2 -x waybar" "$T/log" && ! grep -q "RTMIN" "$T/log"'
touch "$T/pkill-fails"; : > "$T/log"
out="$(ltui 'l2\n\nq')"; rm "$T/pkill-fails"
check "[l] stary config, reload nie doszedł: bez ✓" '[[ "$(<"$LL")" == archenemy && "$out" != *"✓ System logo"* && "$out" == *"Saved: system logo archenemy. Waybar still runs an older bar config"* ]]'
: > "$T/log"; out="$(tui 'v1\n\nq')"
check "[v] stary config paska: też SIGUSR2"     '[[ "$out" == *"✓ Volume bar style: line (waybar reloaded"* ]] && grep -q "^pkill -USR2 -x waybar" "$T/log" && ! grep -q "RTMIN" "$T/log"'
touch -d '-2 hours' "$WCFG"; echo 60 > "$T/waybar-etimes"; : > "$T/log"
out="$(ltui 'l1\n\nq')"
check "[l] config starszy niż waybar: RTMIN+12"  '[[ "$out" == *"✓ System logo: distro logo (Arch Linux)"* && "$out" != *"reloaded"* ]] && grep -q "^pkill -RTMIN+12 -x waybar" "$T/log" && ! grep -q "USR2" "$T/log"'
touch "$WCFG"; echo bzdura > "$T/waybar-etimes"; : > "$T/log"
out="$(ltui 'l2\n\nq')"
check "[l] nieczytelny czas waybara: RTMIN+12"   '[[ "$out" == *"✓ System logo: archenemy logo"* ]] && grep -q "^pkill -RTMIN+12 -x waybar" "$T/log" && ! grep -q "USR2" "$T/log"'
rm -rf "$H/.config/waybar" "$T/waybar-etimes"
echo white-blue > "$A/.current_rice"
check "[l] zmiana rice'a nie zmienia trybu"     '[[ "$(bar_json)" == "{\"text\":\" \",\"class\":\"archenemy\"}" ]]'
rm -f "$A/.current_rice" "$LL"

echo "-- [l] ekran logowania i menu startu (motywy systemowe)"
# Pliki systemowe pod ARCHENEMY_SYSROOT (hak tylko z ARCHENEMY_TEST=1);
# usługa roota to atrapa systemctl. Zielony ✓ wymaga ODCZYTU z motywu.
SYSR="$T/sysroot"; STC="$SYSR/usr/share/sddm/themes/archenemy-tron/theme.conf.user"
stui() { ARCHENEMY_TEST=1 ARCHENEMY_SYSROOT="$SYSR" ARCHENEMY_OS_RELEASE="$T/os-release" SYSTEM_THEME_WAIT=0 tui "$1"; }
echo tron > "$A/.current_rice"
out="$(stui 'l2\n\nq')"
check "[l] bez motywów systemowych: szara informacja, że to opcja" '[[ "$out" == *"not themed by archenemy (optional: bash ~/archenemy/install/system-theme-installation.sh)"* && "$out" != *"Login screen and boot menu use"* ]]'
mkdir -p "$SYSR/etc/archenemy" "$SYSR/etc/sddm.conf.d" "${STC%/*}"
printf 'STATE_USER=test\nSTATE_DIR=%s\nSDDM=1\nGRUB=1\n' "$A" > "$SYSR/etc/archenemy/system-theme.conf"
printf '[Theme]\nCurrent=archenemy-tron\n' > "$SYSR/etc/sddm.conf.d/20-archenemy-theme.conf"
printf '[General]\nlogo=distro\ndistroGlyph=x\nloginScreen=\nbackground=\n' > "$STC"
out="$(stui 'l2\n\nq')"
check "[l] motywy bez usługi: komenda ręczna, bez ✓" '[[ "$out" == *"do not follow by themselves here. Apply: sudo /usr/local/lib/archenemy/system-theme-sync"* && "$out" != *"✓ Login screen"* ]]'
touch "$T/theme-service-active"
out="$(stui 'l2\n\nq')"
check "[l] usługa działa, motyw jeszcze stary: bez ✓, komenda diagnozy" '[[ "$out" == *"has not picked it up yet"*"systemctl status archenemy-system-theme.service"* && "$out" != *"✓ Login screen"* ]]'
sed -i 's/^logo=.*/logo=archenemy/' "$STC"
out="$(stui 'l2\n\nq')"
check "[l] usługa działa i motyw ma nowe logo: ✓ po odczycie" '[[ "$out" == *"✓ Login screen and boot menu use the archenemy logo"* ]]'
sed -i 's/^SDDM=1/SDDM=0/' "$SYSR/etc/archenemy/system-theme.conf"
out="$(stui 'l1\n\nq')"
check "[l] sam GRUB (bez SDDM): informacja bez ✓"   '[[ "$out" == *"The boot menu follows through the archenemy-system-theme service"* && "$out" != *"✓ Login screen"* ]]'
sed -i 's/^SDDM=0/SDDM=1/' "$SYSR/etc/archenemy/system-theme.conf"
rm -f "$LL"

echo "== [g] monitor ekranu logowania"
LS="$A/data/login-screen.dat"
printf 'MONITOR=HDMI-A-1\nRESOLUTION=2560x1440\nRATE=60\nPOSITION=1920x0\nSCALE=1\nROLE=secondary\nDESCRIPTION=TEST Vendor M2 0002\nORDER=2\n' > "$A/data/monitors/HDMI-A-1.dat"
rm -f "$LS" "$T/hypr-monitors"
out="$(stui 'q')"
check "[g] stan bez pliku: primary"               '[[ "$out" =~ g\ +login\ screen\ +primary ]]'
out="$(stui 'g\n\nq')"
check "[g] lista: monitor główny i oba monitory z warstwy maszynowej" '[[ "$out" == *"1) primary monitor (default, now DP-1)"*"2) DP-1  · not connected  · primary"*"3) HDMI-A-1  TEST Vendor M2 0002  · not connected"* ]]'
check "[g] Enter anuluje, plik nie powstaje"      '[[ "$out" == *"Cancelled"* && ! -e "$LS" ]]'
check "[g] ekran mówi o powrocie na monitor główny" '[[ "$out" == *"not connected falls back to the primary monitor"* ]]'
printf 'Monitor DP-1 (ID 0):\n\tdescription: Other Panel 1\nMonitor HDMI-A-3 (ID 1):\n\tdescription: TEST Vendor M2 0002 (HDMI-A-3)\n' > "$T/hypr-monitors"
out="$(stui 'g3\n\nq')"
check "[g] wybór podłączonego monitora: żywa nazwa złącza w pliku" '[[ "$(<"$LS")" == HDMI-A-3 && "$out" == *"3) HDMI-A-3  TEST Vendor M2 0002  · connected"*"Saved: login screen on HDMI-A-3"* ]]'
check "[g] motyw jeszcze bez zmiany: bez ✓"       '[[ "$out" == *"has not picked it up yet"* && "$out" != *"✓ The login screen now uses"* ]]'
sed -i 's/^loginScreen=.*/loginScreen=HDMI-A-3/' "$STC"
out="$(stui 'g3\n\nq')"
check "[g] motyw ma wybrany monitor: ✓ po odczycie" '[[ "$out" == *"✓ The login screen now uses HDMI-A-3"* ]]'
out="$(stui 'q')"
check "[g] stan po zmianie: nazwa złącza"         '[[ "$out" =~ g\ +login\ screen\ +HDMI-A-3 ]]'
sed -i 's/^loginScreen=.*/loginScreen=DP-1/' "$STC"
out="$(stui 'g1\n\nq')"
check "[g] powrót na monitor główny: primary w pliku, ✓ dla jego złącza" '[[ "$(<"$LS")" == primary && "$out" == *"✓ The login screen now uses primary monitor (default, now DP-1)"* ]]'
out="$(stui 'g9\n\nq')"
check "[g] numer spoza listy: bez zmiany"         '[[ "$(<"$LS")" == primary && "$out" == *"Cancelled"* ]]'
echo 'HDMI-A-1; rm -rf /' > "$LS"; out="$(stui 'q')"
check "[g] śmieci w pliku: stan primary"          '[[ "$out" =~ g\ +login\ screen\ +primary ]]'
rm -rf "$A/data/monitors.bak"; mv "$A/data/monitors" "$A/data/monitors.bak"; mkdir -p "$A/data/monitors"
out="$(stui 'g1\n\nq')"
check "[g] bez zapisanych monitorów: podpowiedź [n], zapis primary" '[[ "$out" == *"No monitors saved yet"*"[n] monitors"* && "$(<"$LS")" == primary ]]'
rmdir "$A/data/monitors"; mv "$A/data/monitors.bak" "$A/data/monitors"
rm -f "$LS" "$A/data/monitors/HDMI-A-1.dat" "$T/hypr-monitors" "$T/theme-service-active" "$A/.current_rice"; rm -rf "$SYSR"

echo "== [v] pasek głośności"
reset; out="$(tui 'v2\n\nq')"
check "wybór zapisany"                         '[[ "$(<"$A/data/volume-bar-style.dat")" == ticks && "$out" == *"Volume bar style: ticks"* ]]'
out="$(tui 'vx\n\nq')"
check "zły klawisz bez zmiany"                 '[[ "$(<"$A/data/volume-bar-style.dat")" == ticks && "$out" == *"Cancelled"* ]]'
out="$(tui 'v\n\nq')"
check "Enter anuluje"                          '[[ "$out" == *"Cancelled"* ]]'
check "bez bety bez ostrzeżenia"               '[[ "$out" != *"white-blue_beta"* ]]'

echo "== [t] timer"
out="$(tui 't1\n\nq')"
check "włączenie zapisane"                     '[[ "$(<"$A/data/timer-enabled.dat")" == 1 && "$out" == *"Timer shown"* ]]'
out="$(tui 't2\n40\nq')"
check "czas zapisany"                          '[[ "$(<"$A/data/timer-duration.dat")" == 40 ]]'
out="$(tui 't2\n0\nq')"
check "czas spoza zakresu odrzucony"           '[[ "$(<"$A/data/timer-duration.dat")" == 40 && "$out" == *"not a number between"* ]]'
out="$(tui 't3\n00ff00\nq')"
check "kolor dostaje #"                        '[[ "$(<"$A/data/timer-color.dat")" == "#00ff00" ]]'
out="$(tui 't3\nzielony\nq')"
check "zły kolor odrzucony"                    '[[ "$(<"$A/data/timer-color.dat")" == "#00ff00" && "$out" == *"not a #rrggbb"* ]]'

echo "== [v]/[t] zielone ✓ tylko gdy waybar działa i przyjął sygnał"
VB="$A/data/volume-bar-style.dat"; TE="$A/data/timer-enabled.dat"
rm "$T/waybar-alive"; : > "$T/log"
out="$(tui 'v3\n\nq')"
check "[v] bez waybara: zapisane, bez ✓"       '[[ "$(<"$VB")" == solid && "$out" != *"✓ Volume bar style"* && "$out" == *"Saved: volume bar style solid"*"Waybar is not running"* ]]'
echo 0 > "$TE"; out="$(tui 't1\n\nq')"
check "[t] bez waybara: zapisane, bez ✓ shown" '[[ "$(<"$TE")" == 1 && "$out" != *"✓ Timer shown"* && "$out" == *"Saved: timer on"*"Waybar is not running"* ]]'
out="$(tui 't1\n\nq')"
check "[t] wyłączenie bez waybara: bez ✓"      '[[ "$(<"$TE")" == 0 && "$out" != *"✓ Timer hidden"* && "$out" == *"Saved: timer off"* ]]'
out="$(tui 't3\n112233\nq')"
check "[t] kolor bez waybara: bez ✓"           '[[ "$(<"$A/data/timer-color.dat")" == "#112233" && "$out" != *"✓ Timer colour"* && "$out" == *"Saved: timer colour #112233"* ]]'
check "bez waybara żadnego sygnału w ciemno"   '! grep -q "^pkill" "$T/log"'
touch "$T/waybar-alive" "$T/pkill-fails"
out="$(tui 'v1\n\nq')"
check "[v] sygnał nie doszedł: bez ✓"          '[[ "$(<"$VB")" == line && "$out" != *"✓ Volume bar style"* && "$out" == *"did not take the refresh signal"* ]]'
out="$(tui 't1\n\nq')"
check "[t] sygnał nie doszedł: bez ✓ shown"    '[[ "$(<"$TE")" == 1 && "$out" != *"✓ Timer shown"* && "$out" == *"did not take the refresh signal"* ]]'
rm "$T/pkill-fails"; : > "$T/log"
out="$(tui 'v2\n\nq')"
check "[v] waybar działa: ✓ po sygnale 10"     '[[ "$(<"$VB")" == ticks && "$out" == *"✓ Volume bar style: ticks"* ]] && grep -q "^pkill -RTMIN+10 -x waybar" "$T/log"'
echo 0 > "$TE"; out="$(tui 't1\n\nq')"
check "[t] waybar działa: ✓ po sygnale 11"     '[[ "$(<"$TE")" == 1 && "$out" == *"✓ Timer shown on the bar"* ]] && grep -q "^pkill -RTMIN+11 -x waybar" "$T/log"'
echo volume-bar-style.dat > "$T/mv-fails"; out="$(tui 'v3\n\nq')"; rm "$T/mv-fails"
check "[v] nieudany zapis: bez ✓, plik bez zmian" '[[ "$(<"$VB")" == ticks && "$out" != *"✓"* && "$out" != *"Saved"* && "$out" == *"Could not write"* ]] && ! compgen -G "$VB.*" >/dev/null'
echo white-blue_beta > "$A/.current_rice"
out="$(tui 't1\n\nq')"
check "[t] beta bez modułu: zapisane, bez ✓"   '[[ "$(<"$TE")" == 0 && "$out" != *"✓ Timer"* && "$out" == *"Saved: timer off"*"white-blue_beta"* ]]'
rm "$A/.current_rice"

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

echo "== [w] zielone ✓ dopiero po odczycie trybu, reloadu i guarda"
WSL="$A/config/hypr/workspaces-monitors.lua"
ws_from() { echo "$1" > "$A/data/workspace-mode.dat"; reset; cp "$WSL" "$T/ws.before"; rm -f "$T/guard-alive"; }
ws_from decades; out="$(tui 'wy\n\nq')"
check "[w] ✓ Workspace mode dopiero po wyniku reloadu"  '[[ "$out" == *"no config errors"*"✓ Workspace mode: decades → shared"* ]]'
ws_from decades; touch "$T/dead"; out="$(tui 'wy\n\nq')"; rm "$T/dead"
check "[w] martwy Hyprland: Saved, bez ✓ trybu"         '[[ "$out" != *"✓ Workspace mode"* && "$out" == *"Saved: workspace mode decades → shared"* ]]'
ws_from decades; touch "$T/failreload"; out="$(tui 'wy\n\nq')"; rm "$T/failreload"
check "[w] błąd configu: bez ✓ trybu"                   '[[ "$out" != *"✓ Workspace mode"* && "$out" == *"config error"* && "$out" == *"saved as"* ]]'
ws_from decades; stat -c %i "$WSL" > "$T/ws.inode"; touch "$T/autoreload"; out="$(tui 'wy\n\nq')"; rm "$T/autoreload" "$T/ws.inode"
check "[w] autoreload przed reloadem: bez ✓ trybu (A2)"  '[[ "$out" != *"✓ Workspace mode"* && "$out" == *"config error"* ]]'
ws_from decades; echo workspace-mode.dat > "$T/mv-fails"; out="$(tui 'wy\n\nq')"; rm "$T/mv-fails"
check "[w] nieudany zapis trybu: bez ✓, komunikat"      '[[ "$out" != *"✓ Workspace mode"* && "$out" == *"Could not save"* ]]'
check "[w] nieudany zapis trybu: tryb i reguły jak przedtem" '[[ "$(<"$A/data/workspace-mode.dat")" == decades ]] && cmp -s "$T/ws.before" "$WSL" && ! compgen -G "$A/data/workspace-mode.dat.*" >/dev/null && ! compgen -G "$WSL.*" >/dev/null'
check "[w] nieudany zapis trybu: bez reloadu"           '! grep -q "hyprctl reload" "$T/log"'
ws_from shared; out="$(tui 'wy\n\nq')"
check "[w] guard wystartowany i odczytany"              '[[ "$out" == *"✓ Orphan guard started"* && -f "$T/guard-alive" ]]'
ws_from shared; touch "$T/guard-broken"; out="$(tui 'wy\n\nq')"; rm "$T/guard-broken"
check "[w] guard nie wstał: bez ✓ guarda"               '[[ "$out" != *"✓ Orphan guard"* && "$out" == *"Orphan guard did not start"* ]]'
ws_from shared; touch "$T/guard-alive"; out="$(tui 'wy\n\nq')"
check "[w] guard już działa: bez drugiego startu"       '[[ "$out" == *"Orphan guard already running"* && "$out" != *"Orphan guard started"* ]]'
echo decades > "$A/data/workspace-mode.dat"

echo "== menu główne"
cp "$REPO"/scripts/hypr/{keyboard-layouts,mouse-settings}.sh "$A/scripts/hypr/"
mkdir -p "$A/scripts/appbinds"
printf '#!/usr/bin/env bash\nread -r x < "%s/sink" && echo "$x"\n' "$T" > "$A/scripts/appbinds/audio-devices.sh"
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
check "stan: autostart bez komentarzy"         '[[ "$out" =~ p\ +autostart\ +2\ apps ]]'
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
out="$(tui '\e[A\e[A\e[A\e[A\e[A\e[A\e[Aq')"   # od końca: u i h g l o p
check "podgląd [p]: aplikacje"                 '[[ "$out" == *"firefox"* || "$out" == *"steam"* ]]'
out="$(tui '\e[A\e[A\e[A\e[A\e[A\e[Aq')"   # [l] i [g] weszły między [o] a [h]
check "podgląd [o]: wyjście i wejście"         '[[ "$out" == *"Output"*"Input"* ]]'
out="$(tui '\e[A\e[Aq')"
check "podgląd [i]: opis"                      '[[ "$out" == *"config check"* ]]'

echo "== [p]/[u] otwierają właściwe narzędzia"
# Atrapy zapobiegają uruchomieniu aktualizatora i zapisowi autostartu.
printf '#!/usr/bin/env bash\necho opened-autostart\n' > "$A/scripts/appbinds/autostart-picker.sh"
printf '#!/usr/bin/env bash\necho opened-updater\n' > "$A/scripts/appbinds/update-archenemy.sh"
out="$(tui 'pq')"
check "[p] otwiera autostart"                   '[[ "$out" == *"opened-autostart"* && "$out" != *"opened-updater"* ]]'
out="$(tui 'uq')"
check "[u] otwiera aktualizator"                '[[ "$out" == *"opened-updater"* && "$out" != *"opened-autostart"* ]]'
out="$(tui '\e[Fq')"
check "podgląd [u]: aktualizacja"               '[[ "$out" == *"Update archenemy"*"Commit"* ]]'
rm "$A/scripts/appbinds/autostart-picker.sh" "$A/scripts/appbinds/update-archenemy.sh"

echo "== rozmiar okna"
out="$(ARCHENEMY_TUI_SIZE="27 60" tui 'q')"
check "wąskie okno: bez podglądu, ile wejdzie" '[[ "$out" != *"│"* && "$out" == *"workspaces"* && "$(wc -L <<<"$out")" -le 60 ]]'
out="$(ARCHENEMY_TUI_SIZE="14 90" tui 'q')"
check "niskie okno mieści się"                 '[[ "$(wc -l <<<"$out")" -le 14 ]]'
out="$(ARCHENEMY_TUI_SIZE="14 90" tui '\e[A\e[Fq')"
check "zaznaczenie jedzie z oknem"             '[[ "$(tail -14 <<<"$out")" == *"update archenemy"* ]]'

echo "== akcent wg rice'a"
echo white-blue > "$A/.current_rice"
raw="$(printf q | test_timeout 10 bash "$REPO/scripts/appbinds/appbinds.sh" 2>&1)"
check "white-blue: bright blue"                '[[ "$raw" == *$'"'"'\e[0;94m'"'"'* ]]'
check "bez zwykłego ANSI blue"                 '[[ "$raw" != *$'"'"'\e[0;34m'"'"'* ]]'
echo tron > "$A/.current_rice"
raw="$(printf q | test_timeout 10 bash "$REPO/scripts/appbinds/appbinds.sh" 2>&1)"
check "tron: bright cyan"                      '[[ "$raw" == *$'"'"'\e[0;96m'"'"'* ]]'
rm "$A/.current_rice"

rm -f "$A/scripts/appbinds/audio-devices.sh" "$A/scripts/hypr/keyboard-layouts.sh"
out="$(tui 'q')"
check "brak skryptu = sama etykieta"           '[[ "$out" =~ o\ +audio && "$out" =~ k\ +keyboard ]]'

echo "== [n] monitory"
out="$(tui 'n\n\nq')"
check "[n] otwiera monitory"                   '[[ "$out" == *"archenemy  monitors"* ]]'

echo "== [i] diagnostyka"
printf '#!/usr/bin/env bash\necho report-ok\nexit 0\n' > "$A/scripts/hypr/machine-layer-check.sh"
printf '#!/usr/bin/env bash\necho ws-dump\n' > "$A/scripts/hypr/workspace-diag.sh"
out="$(tui 'i1\nq')"
check "kontrola: raport i wynik"               '[[ "$out" == *"report-ok"*"Config matches"* ]]'
printf '#!/usr/bin/env bash\necho bad\nexit 1\n' > "$A/scripts/hypr/machine-layer-check.sh"
out="$(tui 'i1\nq')"
check "kontrola: problemy bez sukcesu"         '[[ "$out" == *"Problems found"* && "$out" != *"Config matches"* ]]'
out="$(tui 'i2\nq')"
check "zrzut w pliku i na ekranie"             '[[ "$out" == *"ws-dump"*"Saved to"* ]] && grep -qx ws-dump "$H"/archenemy-diag-workspaces-*.txt'
out="$(tui 'i3\nq')"
check "brak skryptu zgłoszony"                 '[[ "$out" == *"Missing"*"gaming-diag.sh"* ]]'
printf '#!/usr/bin/env bash\nexit 0\n' > "$A/scripts/hypr/gaming-diag.sh"
out="$(tui 'i3\nq')"
check "pusty zrzut to nie sukces"              '[[ "$out" == *"produced no output"* && "$out" != *"Saved to"* ]] && ! ls "$H"/archenemy-diag-gaming-* >/dev/null 2>&1'
out="$(tui 'i\nq')"
check "Enter anuluje"                          '[[ "$out" == *"Cancelled"* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
test_timing_ok && [[ $FAIL -eq 0 ]]
