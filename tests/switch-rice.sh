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
#   Uruchom: bash tests/switch-rice.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC2088  # check() robi eval (zmienne żyją w eval); ~ w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'xargs -r kill 2>/dev/null < "$T/waybar.pids"; rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── atrapy ──────────────────────────────────────────────────────────────────
mkdir -p "$T/bin"
for c in hyprctl makoctl pkill; do printf '#!/bin/bash\nexit 0\n' > "$T/bin/$c"; done
# waybar żyje w tle jak prawdziwy (MOCK_WAYBAR_SLEEP s) — sprawdza, czy nie
# dziedziczy blokady przełącznika; PID-y do posprzątania w $T/waybar.pids.
printf '#!/bin/bash\necho $$ >> "$MOCK_PIDS"\nexec sleep "${MOCK_WAYBAR_SLEEP:-0}"\n' > "$T/bin/waybar"
printf '#!/bin/bash\nexit 1\n' > "$T/bin/pgrep"            # nic nie działa w tle
printf '#!/bin/bash\necho "NOTIFY: $*" >> "$MOCK_LOG"\n' > "$T/bin/notify-send"
chmod +x "$T/bin"/*
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log" MOCK_PIDS="$T/waybar.pids"

# ─── atrapa $HOME/archenemy: dwa rice'y + prawdziwa biblioteka przełącznika ──
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run"
A="$HOME/archenemy"; C="$HOME/.config"
mkdir -p "$A/rices/alfa/hypr" "$A/rices/alfa/mako" "$A/rices/beta/hypr" "$A/rices/beta/waybar" \
         "$A/scripts/changing-theme-scripts" "$C" "$XDG_RUNTIME_DIR"
ln -s "$REPO/scripts/changing-theme-scripts/lib" "$A/scripts/changing-theme-scripts/lib"
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

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
