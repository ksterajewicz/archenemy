#!/usr/bin/env bash
# =============================================
#   archenemy - tests/switch-rice.sh
#   Testy przełącznika rice'ów (scripts/changing-theme-scripts/lib/
#   switch-rice.sh) na atrapie $HOME i ~/.config w mktemp; hyprctl, waybar,
#   makoctl, notify-send, pkill, pgrep — atrapy w PATH. Bez Hyprlanda,
#   bez roota.
#
#   Powód powstania (audyt 2026-09-23): (1) każdy symlink w ~/.config o
#   nazwie folderu rice'a był kasowany bez kopii — także cudzy (np. GNU
#   stow), a repo jest publiczne i nie może psuć cudzej konfiguracji;
#   (2) brak blokady + `ln -s` bez -n: dwa szybkie Super+T mogły utworzyć
#   link WEWNĄTRZ rices/<rice>/<folder>/ i zostawić mieszany rice.
#   Inwariant z INSTRUCTIONS: przełączenie usuwa WSZYSTKIE symlinki do
#   rices/ przed podlinkowaniem nowego (brak wycieku poprzedniego rice'a).
#   T7 (audyt 2026-11-05): zajęta blokada musi kończyć się kodem 1 bez
#   zmiany rice'a — mutant „kod 0” przechodził cały run-all.
#   yang (2026-11-20): prawdziwe stuby yin.sh → yang.sh na kopii rices/:
#   każdy folder yang podlinkowany, nic z yin, launcher/rofi/hyprlock yang.
#   R3 (2026-11-24): własny ~/.config/zsh (ZDOTDIR) zostaje nietknięty,
#   wygląd zsh idzie do ~/.config/archenemy-zsh; migracja starego
#   dowiązania ~/.config/zsh → rices/ i przywrócenie kopii zsh.bak-<czas>.
#   Uruchom: bash tests/switch-rice.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC2088  # check() robi eval (zmienne żyją w eval); ~ w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'xargs -r kill 2>/dev/null < "$T/waybar.pids"; rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── atrapy ──────────────────────────────────────────────────────────────────
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/makoctl"
printf '#!/usr/bin/env bash\necho "pkill $*" >> "$MOCK_LOG"\nexit 0\n' > "$T/bin/pkill"
# hyprctl: log wywołań; plik $MOCK_BROKEN = config rice'a beta ma błąd, widoczny
# w configerrors od chwili podlinkowania (Hyprland z autoreloadem czyta zmiany
# przez inotify jeszcze przed `hyprctl reload`).
cat > "$T/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
echo "hyprctl $*" >> "$MOCK_LOG"
if [[ "$1" == configerrors ]]; then
    [[ -f "$MOCK_BROKEN" && "$(readlink "$HOME/.config/hypr")" == */rices/beta/hypr ]] && echo "hl.bind: bad rule in beta"
    echo
fi
exit 0
MOCK
# waybar żyje w tle jak prawdziwy (MOCK_WAYBAR_SLEEP s) — sprawdza, czy nie
# dziedziczy blokady przełącznika; PID-y do posprzątania w $T/waybar.pids.
printf '#!/usr/bin/env bash\necho $$ >> "$MOCK_PIDS"\nexec sleep "${MOCK_WAYBAR_SLEEP:-0}"\n' > "$T/bin/waybar"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pgrep"            # nic nie działa w tle
printf '#!/usr/bin/env bash\necho "NOTIFY: $*" >> "$MOCK_LOG"\n' > "$T/bin/notify-send"
chmod +x "$T/bin"/*
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log" MOCK_PIDS="$T/waybar.pids" MOCK_BROKEN="$T/beta-broken"

# ─── atrapa $HOME/archenemy: dwa rice'y + prawdziwa biblioteka przełącznika ──
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run"
A="$HOME/archenemy"; C="$HOME/.config"
mkdir -p "$A/rices/alfa/hypr" "$A/rices/alfa/mako" "$A/rices/beta/hypr" "$A/rices/beta/waybar" \
         "$A/scripts/changing-theme-scripts" "$C" "$XDG_RUNTIME_DIR"
ln -s "$REPO/scripts/changing-theme-scripts/lib" "$A/scripts/changing-theme-scripts/lib"
ln -s "$REPO/scripts/hypr" "$A/scripts/hypr"    # lib/hypr-apply.sh (reload z odczytem błędów)
ln -s "$REPO/scripts/lib" "$A/scripts/lib"   # lib/runtime-dir.sh — katalog sesji (S12)
# Atrapa flux-walla: zapisuje, który rice widzi w .current_rice w chwili autostartu.
mkdir -p "$A/scripts/wallpapers"
printf '#!/usr/bin/env bash\necho "FLUXWALL $1 rice=$(cat "$HOME/archenemy/.current_rice")" >> "$MOCK_LOG"\n' > "$A/scripts/wallpapers/flux-wall.sh"
for r in alfa beta; do
    printf '#!/usr/bin/env bash\nRICE_NAME="%s"\nsource "$(dirname "$(readlink -f "$0")")/lib/switch-rice.sh"\n' "$r" \
        > "$A/scripts/changing-theme-scripts/$r.sh"
done
sw() { bash "$A/scripts/changing-theme-scripts/$1.sh" >/dev/null 2>&1; }
link_of() { readlink "$C/$1"; }
links_inside_rices() { find "$A/rices" -type l | wc -l; }

echo "== przełączenie i inwariant sprzątania"
sw alfa
check "hypr → alfa"                             '[[ "$(link_of hypr)" == "$A/rices/alfa/hypr" ]]'
check "mako → alfa"                             '[[ "$(link_of mako)" == "$A/rices/alfa/mako" ]]'
sw beta
check "hypr → beta"                             '[[ "$(link_of hypr)" == "$A/rices/beta/hypr" ]]'
check "mako z alfy usunięty (brak wycieku)"     '[[ ! -e "$C/mako" && ! -L "$C/mako" ]]'
check ".current_rice = beta"                    '[[ "$(<"$A/.current_rice")" == beta ]]'

echo "== cudzy symlink (np. GNU stow) nie znika bez kopii"
rm -f "$C"/hypr "$C"/waybar
mkdir -p "$T/dotfiles/waybar"; echo moje > "$T/dotfiles/waybar/config"
ln -s "$T/dotfiles/waybar" "$C/waybar"
sw beta
check "waybar → beta"                           '[[ "$(link_of waybar)" == "$A/rices/beta/waybar" ]]'
check "cudzy link zachowany jako .bak-*"        'ls -d "$C"/waybar.bak-* >/dev/null 2>&1 && [[ "$(readlink "$(ls -d "$C"/waybar.bak-* | head -n1)")" == "$T/dotfiles/waybar" ]]'
check "cudze pliki nietknięte"                  '[[ "$(<"$T/dotfiles/waybar/config")" == moje ]]'

echo "== prawdziwy katalog użytkownika → .bak (dawne zachowanie)"
rm -rf "$C"/mako*; mkdir -p "$C/mako"; echo moj > "$C/mako/config"
sw alfa
check "mako → alfa, katalog w .bak-*"           '[[ "$(link_of mako)" == "$A/rices/alfa/mako" ]] && ls -d "$C"/mako.bak-* >/dev/null 2>&1'

echo "== dwa szybkie przełączenia naraz (Super+T ×2)"
bad=0
for _ in $(seq 1 25); do
    sw alfa & sw beta & wait
    if (( $(links_inside_rices) > 0 )); then bad=1; break; fi
    cur="$(<"$A/.current_rice")"
    [[ "$(link_of hypr)" == "$A/rices/$cur/hypr" ]] || { bad=2; break; }
done
check "brak linków wewnątrz rices/ (25 prób)"   '[[ $bad -ne 1 ]]'
check "~/.config zgodny z .current_rice"        '[[ $bad -ne 2 ]]'
find "$A/rices" -type l -delete 2>/dev/null

echo "== blokada nie zostaje w procesach tła (kolejne Super+T nie wisi)"
start=$(date +%s)
MOCK_WAYBAR_SLEEP=60 sw alfa; MOCK_WAYBAR_SLEEP=60 sw beta
check "dwa przełączenia po sobie < 10 s"        '(( $(date +%s) - start < 10 ))'

echo "== zajęta blokada: drugie Super+T czeka, a po limicie nic nie zmienia (T7)"
# Proces trzymający blokadę: exec sleep zostawia ten sam PID z otwartym fd, więc
# kill zwalnia blokadę od razu. Znacznik w pliku = blokada naprawdę wzięta.
LOCK="$XDG_RUNTIME_DIR/archenemy-switch-rice.lock"
sw beta
( exec 8>"$LOCK"; flock 8; : > "$T/held"; exec sleep 30 ) & holder=$!
for _ in $(seq 1 200); do [[ -e "$T/held" ]] && break; sleep 0.05; done
: > "$MOCK_LOG"
SWITCH_RICE_LOCK_WAIT=1 sw alfa; rc=$?
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; rm -f "$T/held"
check "zajęta blokada: kod 1, nie sukces"              '(( rc == 1 ))'
check "zajęta blokada: rice bez zmian (beta)"         '[[ "$(<"$A/.current_rice")" == beta && "$(link_of hypr)" == "$A/rices/beta/hypr" ]]'
check "zajęta blokada: powiadomienie, bez 'applied'"  'grep -q "NOTIFY: .*Another rice switch" "$MOCK_LOG" && ! grep -q "applied" "$MOCK_LOG"'
( exec 8>"$LOCK"; flock 8; : > "$T/held"; sleep 1 ) & holder=$!
for _ in $(seq 1 200); do [[ -e "$T/held" ]] && break; sleep 0.05; done
SWITCH_RICE_LOCK_WAIT=10 sw alfa; rc=$?
wait "$holder" 2>/dev/null; rm -f "$T/held"
check "blokada zwolniona w trakcie czekania: przełącza" '(( rc == 0 )) && [[ "$(<"$A/.current_rice")" == alfa && "$(link_of hypr)" == "$A/rices/alfa/hypr" ]]'

echo "== kolejność skutków: flux-wall startuje już dla nowego rice'a (T9)"
# Flaga --dither idzie za rice'em z .current_rice — autostart przed zapisem
# .current_rice puściłby animację z flagą POPRZEDNIEGO rice'a.
sw alfa; : > "$MOCK_LOG"; sw beta
check "autostart flux-walla widzi .current_rice = beta"  'grep -qx "FLUXWALL autostart rice=beta" "$MOCK_LOG"'
check "autostart przed powiadomieniem o wyniku"          '[[ "$(grep -n "^FLUXWALL" "$MOCK_LOG" | cut -d: -f1)" -lt "$(grep -n "^NOTIFY" "$MOCK_LOG" | tail -1 | cut -d: -f1)" ]]'
check "bez sesji Hyprlanda: bez reloadu, Rice applied"   '! grep -q "^hyprctl reload" "$MOCK_LOG" && grep -q "NOTIFY: -a archenemy archenemy Rice .beta. applied" "$MOCK_LOG"'

echo "== Super+T: waybar uruchomiony od nowa (config i skrypty modułów, np. tryb launchera)"
# Waybar czyta config tylko na starcie (scripts/waybar/lib/waybar-reload.sh),
# więc zmiana rice'a musi zatrzymać stary proces i wystartować nowy — wtedy
# custom/launcher uruchamia launcher-logo.sh i czyta data/launcher-logo.dat.
n0=$(wc -l < "$T/waybar.pids" 2>/dev/null || echo 0); : > "$MOCK_LOG"
sw alfa
n1=$n0; for _ in $(seq 1 40); do n1=$(wc -l < "$T/waybar.pids" 2>/dev/null || echo 0); (( n1 > n0 )) && break; sleep 0.05; done
check "stary waybar zatrzymany (pkill -x waybar)"        'grep -qx "pkill -x waybar" "$MOCK_LOG"'
check "nowy waybar wystartował"                           '(( n1 == n0 + 1 ))'

echo "== Super+T: 'applied' tylko po reloadzie bez nowych błędów configu (A15)"
HYPRLAND_INSTANCE_SIGNATURE=fake-instance sw alfa; : > "$MOCK_LOG"; touch "$MOCK_BROKEN"
HYPRLAND_INSTANCE_SIGNATURE=fake-instance sw beta; rm -f "$MOCK_BROKEN"
check "błąd configu: reload przez hyprctl"                'grep -q "^hyprctl reload" "$MOCK_LOG"'
check "błąd configu: bez 'applied'"                       '! grep -q "applied" "$MOCK_LOG"'
check "błąd configu: treść błędu w powiadomieniu"         'grep -q "NOTIFY: .*config error.*bad rule in beta" "$MOCK_LOG"'
: > "$MOCK_LOG"; HYPRLAND_INSTANCE_SIGNATURE=fake-instance sw alfa
check "czysty config: reload i Rice applied"              'grep -q "^hyprctl reload" "$MOCK_LOG" && grep -q "NOTIFY: -a archenemy archenemy Rice .alfa. applied" "$MOCK_LOG"'

echo "== Super+T yin → yang: prawdziwe stuby i katalogi rices/yin, rices/yang"
# Kopie prawdziwych rice'ów (white-blue = cel względnych linków
# networkmanager-dmenu i ncmpcpp/bindings; assets/logo/rices = cel
# waybar/launcher.svg) w osobnej atrapie $HOME — repo zostaje nietknięte.
Y="$T/home-yang"; YA="$Y/archenemy"; YC="$Y/.config"
mkdir -p "$YA/rices" "$YA/scripts/changing-theme-scripts" "$YA/scripts/wallpapers" "$YA/assets/logo" "$YC"
for r in white-blue yin yang; do cp -a "$REPO/rices/$r" "$YA/rices/$r"; done
cp -a "$REPO/assets/logo/rices" "$YA/assets/logo/rices"
ln -s "$REPO/scripts/changing-theme-scripts/lib" "$YA/scripts/changing-theme-scripts/lib"
ln -s "$REPO/scripts/hypr" "$YA/scripts/hypr"
ln -s "$REPO/scripts/lib" "$YA/scripts/lib"
cp "$REPO/scripts/changing-theme-scripts/yin.sh" "$REPO/scripts/changing-theme-scripts/yang.sh" "$YA/scripts/changing-theme-scripts/"
cp "$A/scripts/wallpapers/flux-wall.sh" "$YA/scripts/wallpapers/flux-wall.sh"
HOME="$Y" bash "$YA/scripts/changing-theme-scripts/yin.sh" >/dev/null 2>&1
: > "$MOCK_LOG"
HOME="$Y" bash "$YA/scripts/changing-theme-scripts/yang.sh" >/dev/null 2>&1; yang_rc=$?
mapfile -t yang_dirs < <(cd "$YA/rices/yang" && for d in */; do echo "${d%/}"; done)
yang_bad=""
for d in "${yang_dirs[@]}"; do [[ "$(readlink "$YC/$d")" == "$YA/rices/yang/$d" ]] || yang_bad+=" $d"; done
check "stub yang.sh: kod 0, .current_rice = yang"         '[[ $yang_rc -eq 0 && "$(<"$YA/.current_rice")" == yang ]]'
check "każdy z ${#yang_dirs[@]} katalogów rices/yang podlinkowany${yang_bad:+ (brak:$yang_bad)}" '[[ ${#yang_dirs[@]} -ge 12 && -z "$yang_bad" ]]'
check "żaden link do rices/yin nie został (sprzątanie pary)" '! find "$YC" -maxdepth 1 -type l -lname "*/rices/yin/*" | grep -q .'
check "linki ~/.config = katalogi yang (nic ponad)"        '[[ $(find "$YC" -maxdepth 1 -type l | wc -l) -eq ${#yang_dirs[@]} ]]'
check "networkmanager-dmenu przez link do white-blue"     '[[ -f "$YC/networkmanager-dmenu/config.ini" ]]'
check "waybar/launcher.svg = logo yang (#0C0C0E) przez link" 'grep -q "fill=\"#0C0C0E\"" "$YC/waybar/launcher.svg"'
check "rofi: @theme yang.rasi istnieje przez link"         'grep -qF "@theme \"~/.config/rofi/themes/yang.rasi\"" "$YC/rofi/config.rasi" && [[ -f "$YC/rofi/themes/yang.rasi" ]]'
check "hyprlock: tło z hyprlock-background-yang.conf"      'grep -qx "source = ~/archenemy/config/hypr/hyprlock-background-yang.conf" "$YC/hypr/hyprlock.conf"'
check "flux-wall autostart już dla yang"                   'grep -q "^FLUXWALL autostart rice=yang$" "$MOCK_LOG"'
check "waybar wystartował od nowa"                         'grep -q "^pkill -x waybar" "$MOCK_LOG"'
check "repo bez zmian: rices/yang bez nowych linków"       '[[ $(find "$REPO/rices/yang" -type l | wc -l) -eq 4 ]]'

# ─── własny ~/.config/zsh (ZDOTDIR) i migracja (R3, 2026-11-24) ──────────────
# Do 2026-11-24 rice'y miały folder zsh/, więc Super+T odkładał prawdziwy
# ~/.config/zsh użytkownika (popularny ZDOTDIR: .zshrc, historia) do
# zsh.bak-<czas> i linkował tam wygląd rice'a — powłoka „znikała”. Wygląd zsh
# leży teraz w rices/<rice>/archenemy-zsh/ (→ ~/.config/archenemy-zsh), a
# przełącznik jednorazowo sprząta po starej wersji. Atrapy $HOME z kopią
# prawdziwych rices/ (yin, yang, white-blue) z sekcji wyżej.
zhome() {
    local h="$1"
    mkdir -p "$h/archenemy/scripts/changing-theme-scripts" "$h/archenemy/scripts/wallpapers" "$h/.config"
    cp -a "$YA/rices" "$h/archenemy/rices"; cp -a "$YA/assets" "$h/archenemy/assets"
    ln -s "$REPO/scripts/changing-theme-scripts/lib" "$h/archenemy/scripts/changing-theme-scripts/lib"
    ln -s "$REPO/scripts/hypr" "$h/archenemy/scripts/hypr"
    ln -s "$REPO/scripts/lib" "$h/archenemy/scripts/lib"
    cp "$YA/scripts/changing-theme-scripts/"{yin,yang}.sh "$h/archenemy/scripts/changing-theme-scripts/"
    cp "$A/scripts/wallpapers/flux-wall.sh" "$h/archenemy/scripts/wallpapers/"
}
zsw() { HOME="$1" bash "$1/archenemy/scripts/changing-theme-scripts/$2.sh" >/dev/null 2>&1; }
no_zsh_bak() { ! compgen -G "$1/.config/zsh.bak-*" >/dev/null; }

echo "== Super+T yin → yang: własny ~/.config/zsh (ZDOTDIR) zostaje nietknięty"
Z="$T/home-zdotdir"; zhome "$Z"
mkdir -p "$Z/.config/zsh"
printf 'echo moj-zshrc\n' > "$Z/.config/zsh/.zshrc"; printf ': 1:0;ls\n' > "$Z/.config/zsh/.zsh_history"
zsw "$Z" yin; zsw "$Z" yang
check "~/.config/zsh to dalej prawdziwy katalog"           '[[ -d "$Z/.config/zsh" && ! -L "$Z/.config/zsh" ]]'
check ".zshrc i historia bez zmian"                        '[[ "$(<"$Z/.config/zsh/.zshrc")" == "echo moj-zshrc" && "$(<"$Z/.config/zsh/.zsh_history")" == ": 1:0;ls" ]]'
check "brak zsh.bak-* (nic nie przeniesione)"              'no_zsh_bak "$Z"'
check "wygląd zsh: ~/.config/archenemy-zsh → rices/yang/archenemy-zsh" '[[ "$(readlink "$Z/.config/archenemy-zsh")" == "$Z/archenemy/rices/yang/archenemy-zsh" && -s "$Z/.config/archenemy-zsh/colors.zsh" ]]'
check "żaden rice nie ma już folderu zsh/"                 '! compgen -G "$REPO/rices/*/zsh" >/dev/null'

echo "== migracja: stare dowiązanie ~/.config/zsh → rices/<rice>/zsh, bez kopii"
M1="$T/home-mig1"; zhome "$M1"
ln -s "$M1/archenemy/rices/yin/zsh" "$M1/.config/zsh"
: > "$MOCK_LOG"; zsw "$M1" yang
check "stare dowiązanie usunięte"                          '[[ ! -e "$M1/.config/zsh" && ! -L "$M1/.config/zsh" ]]'
check "nowe miejsce podlinkowane, zsh.bak-* nie powstał"   '[[ "$(readlink "$M1/.config/archenemy-zsh")" == "$M1/archenemy/rices/yang/archenemy-zsh" ]] && no_zsh_bak "$M1"'
check "bez komunikatu o przywróceniu"                      '! grep -q "Restored" "$MOCK_LOG"'

echo "== migracja: stare dowiązanie + kopia z dawnego Super+T → kopia wraca na miejsce"
M2="$T/home-mig2"; zhome "$M2"
ln -s "$M2/archenemy/rices/yin/zsh" "$M2/.config/zsh"
mkdir -p "$M2/.config/zsh.bak-20261124_181217" "$M2/.config/zsh.bak-20261123_090000"
printf 'echo nowszy\n' > "$M2/.config/zsh.bak-20261124_181217/.zshrc"
printf 'echo starszy\n' > "$M2/.config/zsh.bak-20261123_090000/.zshrc"
mkdir -p "$M2/.config/zsh.bak-moja"; printf 'echo obca\n' > "$M2/.config/zsh.bak-moja/.zshrc"
: > "$MOCK_LOG"; zsw "$M2" yang
check "najnowsza kopia przywrócona do ~/.config/zsh (mv)"  '[[ -d "$M2/.config/zsh" && ! -L "$M2/.config/zsh" && "$(<"$M2/.config/zsh/.zshrc")" == "echo nowszy" && ! -e "$M2/.config/zsh.bak-20261124_181217" ]]'
check "starsza kopia i obca nazwa nietknięte"              '[[ "$(<"$M2/.config/zsh.bak-20261123_090000/.zshrc")" == "echo starszy" && "$(<"$M2/.config/zsh.bak-moja/.zshrc")" == "echo obca" ]]'
check "powiadomienie o przywróceniu"                       'grep -q "NOTIFY: .*Restored ~/.config/zsh from zsh.bak-20261124_181217" "$MOCK_LOG"'
check "wygląd zsh w nowym miejscu"                         '[[ "$(readlink "$M2/.config/archenemy-zsh")" == "$M2/archenemy/rices/yang/archenemy-zsh" ]]'
: > "$MOCK_LOG"; zsw "$M2" yin
check "kolejny Super+T: przywrócony katalog nietknięty, starsza kopia dalej leży" '[[ "$(<"$M2/.config/zsh/.zshrc")" == "echo nowszy" && -d "$M2/.config/zsh.bak-20261123_090000" ]] && ! grep -q "Restored" "$MOCK_LOG"'

echo "== migracja: bez starego dowiązania kopie zostają (decyzja użytkownika)"
M3="$T/home-mig3"; zhome "$M3"
mkdir -p "$M3/.config/zsh.bak-20261124_181217"; printf 'echo kopia\n' > "$M3/.config/zsh.bak-20261124_181217/.zshrc"
zsw "$M3" yang
check "brak ~/.config/zsh, kopia nietknięta"               '[[ ! -e "$M3/.config/zsh" && ! -L "$M3/.config/zsh" && -f "$M3/.config/zsh.bak-20261124_181217/.zshrc" ]]'

echo "== migracja: kopia, która sama jest dowiązaniem do rices/, nie wraca"
# Nasz link bez danych: sprząta go pętla „usuń każdy link do rices/”.
M4="$T/home-mig4"; zhome "$M4"
ln -s "$M4/archenemy/rices/yin/zsh" "$M4/.config/zsh"
ln -s "$M4/archenemy/rices/white-blue/zsh" "$M4/.config/zsh.bak-20261124_181217"
zsw "$M4" yang
check "~/.config/zsh nie istnieje (nic nie przywrócone)"   '[[ ! -e "$M4/.config/zsh" && ! -L "$M4/.config/zsh" ]]'

echo "== migracja w instalatorze (SWITCH_RICE_LINK_ONLY=1): komunikat na stdout"
M5="$T/home-mig5"; zhome "$M5"
ln -s "$M5/archenemy/rices/yin/zsh" "$M5/.config/zsh"
mkdir -p "$M5/.config/zsh.bak-20261124_181217"; printf 'echo moj\n' > "$M5/.config/zsh.bak-20261124_181217/.zshrc"
out="$(HOME="$M5" RICE_NAME=yang SWITCH_RICE_LINK_ONLY=1 bash "$M5/archenemy/scripts/changing-theme-scripts/lib/switch-rice.sh" 2>&1)"; rc=$?
check "kod 0, katalog przywrócony"                         '(( rc == 0 )) && [[ "$(<"$M5/.config/zsh/.zshrc")" == "echo moj" ]]'
check "stdout mówi, co przywrócono"                        '[[ "$out" == *"Restored ~/.config/zsh from zsh.bak-20261124_181217"* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
