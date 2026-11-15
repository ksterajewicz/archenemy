#!/bin/bash
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
for c in makoctl pkill; do printf '#!/bin/bash\nexit 0\n' > "$T/bin/$c"; done
# hyprctl: log wywołań; plik $MOCK_BROKEN = config rice'a beta ma błąd, widoczny
# w configerrors od chwili podlinkowania (Hyprland z autoreloadem czyta zmiany
# przez inotify jeszcze przed `hyprctl reload`).
cat > "$T/bin/hyprctl" <<'MOCK'
#!/bin/bash
echo "hyprctl $*" >> "$MOCK_LOG"
if [[ "$1" == configerrors ]]; then
    [[ -f "$MOCK_BROKEN" && "$(readlink "$HOME/.config/hypr")" == */rices/beta/hypr ]] && echo "hl.bind: bad rule in beta"
    echo
fi
exit 0
MOCK
# waybar żyje w tle jak prawdziwy (MOCK_WAYBAR_SLEEP s) — sprawdza, czy nie
# dziedziczy blokady przełącznika; PID-y do posprzątania w $T/waybar.pids.
printf '#!/bin/bash\necho $$ >> "$MOCK_PIDS"\nexec sleep "${MOCK_WAYBAR_SLEEP:-0}"\n' > "$T/bin/waybar"
printf '#!/bin/bash\nexit 1\n' > "$T/bin/pgrep"            # nic nie działa w tle
printf '#!/bin/bash\necho "NOTIFY: $*" >> "$MOCK_LOG"\n' > "$T/bin/notify-send"
chmod +x "$T/bin"/*
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log" MOCK_PIDS="$T/waybar.pids" MOCK_BROKEN="$T/beta-broken"

# ─── atrapa $HOME/archenemy: dwa rice'y + prawdziwa biblioteka przełącznika ──
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run"
A="$HOME/archenemy"; C="$HOME/.config"
mkdir -p "$A/rices/alfa/hypr" "$A/rices/alfa/mako" "$A/rices/beta/hypr" "$A/rices/beta/waybar" \
         "$A/scripts/changing-theme-scripts" "$C" "$XDG_RUNTIME_DIR"
ln -s "$REPO/scripts/changing-theme-scripts/lib" "$A/scripts/changing-theme-scripts/lib"
ln -s "$REPO/scripts/hypr" "$A/scripts/hypr"    # lib/hypr-apply.sh (reload z odczytem błędów)
# Atrapa flux-walla: zapisuje, który rice widzi w .current_rice w chwili autostartu.
mkdir -p "$A/scripts/wallpapers"
printf '#!/bin/bash\necho "FLUXWALL $1 rice=$(cat "$HOME/archenemy/.current_rice")" >> "$MOCK_LOG"\n' > "$A/scripts/wallpapers/flux-wall.sh"
for r in alfa beta; do
    printf '#!/bin/bash\nRICE_NAME="%s"\nsource "$(dirname "$(readlink -f "$0")")/lib/switch-rice.sh"\n' "$r" \
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
check "bez sesji Hyprlanda: bez reloadu, Rice applied"   '! grep -q "^hyprctl reload" "$MOCK_LOG" && grep -q "NOTIFY: archenemy Rice .beta. applied" "$MOCK_LOG"'

echo "== Super+T: 'applied' tylko po reloadzie bez nowych błędów configu (A15)"
HYPRLAND_INSTANCE_SIGNATURE=fake-instance sw alfa; : > "$MOCK_LOG"; touch "$MOCK_BROKEN"
HYPRLAND_INSTANCE_SIGNATURE=fake-instance sw beta; rm -f "$MOCK_BROKEN"
check "błąd configu: reload przez hyprctl"                'grep -q "^hyprctl reload" "$MOCK_LOG"'
check "błąd configu: bez 'applied'"                       '! grep -q "applied" "$MOCK_LOG"'
check "błąd configu: treść błędu w powiadomieniu"         'grep -q "NOTIFY: .*config error.*bad rule in beta" "$MOCK_LOG"'
: > "$MOCK_LOG"; HYPRLAND_INSTANCE_SIGNATURE=fake-instance sw alfa
check "czysty config: reload i Rice applied"              'grep -q "^hyprctl reload" "$MOCK_LOG" && grep -q "NOTIFY: archenemy Rice .alfa. applied" "$MOCK_LOG"'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
