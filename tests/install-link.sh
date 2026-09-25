#!/bin/bash
# =============================================
#   archenemy - tests/install-link.sh
#   Test kroku [9] install.sh (symlinki rice'a do ~/.config) na atrapie $HOME
#   w mktemp. Wycinek [9] jest wycinany z install/install.sh sedem (jak [3]
#   w tests/machine-layer.sh) i uruchamiany z podstawionymi zmiennymi; sam
#   krok woła prawdziwą bibliotekę lib/switch-rice.sh w trybie
#   SWITCH_RICE_LINK_ONLY=1. Bez Hyprlanda, bez roota.
#
#   Powód powstania (audyt 2026-09-25): [9] miał własną kopię pętli
#   linkującej i robił `rm` na KAŻDYM symlinku o nazwie folderu rice'a —
#   także cudzym (np. GNU stow), bez kopii. Sprawdzamy, że:
#     - cudzy symlink i prawdziwy katalog trafiają do .bak-<ts>, nie giną,
#     - link do INNEGO rice'a jest sprzątany (inwariant: brak wycieku),
#     - w trybie link-only nic nie restartuje waybara/hyprctl,
#     - instalator ogłasza ✓ dopiero po zaobserwowanym linku.
#   Uruchom: bash tests/install-link.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval (zmienne żyją w eval); puste kolory dla wycinka
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── atrapy: wszystko, co biblioteka mogłaby odpalić POZA trybem link-only,
#     zostawia ślad w $MOCK_LOG — w link-only log ma zostać pusty.
mkdir -p "$T/bin"
for c in hyprctl makoctl pkill pgrep waybar swayosd-server notify-send; do
    printf '#!/bin/bash\necho "%s: $*" >> "$MOCK_LOG"\nexit 0\n' "$c" > "$T/bin/$c"
done
chmod +x "$T/bin"/*
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log"

# ─── atrapa $HOME/archenemy: dwa rice'y + prawdziwa biblioteka przełącznika ──
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run"
A="$HOME/archenemy"; C="$HOME/.config"
mkdir -p "$A/rices/alfa/hypr" "$A/rices/alfa/waybar" "$A/rices/alfa/mako" \
         "$A/rices/beta/hypr" "$A/rices/beta/rofi" \
         "$A/scripts/changing-theme-scripts" "$C" "$XDG_RUNTIME_DIR"
ln -s "$REPO/scripts/changing-theme-scripts/lib" "$A/scripts/changing-theme-scripts/lib"

# ─── wycinek [9] z install.sh ────────────────────────────────────────────────
S=$(grep -n '^# ─── 9. SYMLINKS' "$REPO/install/install.sh" | cut -d: -f1)
E=$(grep -n '^# ─── 9.5 SCRIPTS' "$REPO/install/install.sh" | cut -d: -f1)
sed -n "${S},$((E-1))p" "$REPO/install/install.sh" > "$T/step9.sh"
check "wycinek [9] znaleziony"                  '[[ -n "$S" && -n "$E" && -s "$T/step9.sh" ]]'

# run_step9 <rice> → stdout wycinka; SUMMARY_* zrzucane do $T/summary
run_step9() {
    ARCHENEMY_DIR="$A" RICES_DIR="$A/rices" CONFIG_DIR="$C" CURRENT_RICE="$A/.current_rice" \
    TARGET_RICE="$1" GREEN='' NC='' YELLOW='' BLUE='' CYAN='' RED='' \
    bash -c 'declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=(); source "$1"
             printf "DONE=%s\n" "${SUMMARY_DONE[@]}" > "$2"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}" >> "$2"' \
        _ "$T/step9.sh" "$T/summary" 2>&1
}
link_of() { readlink "$C/$1"; }

echo "== cudzy symlink (GNU stow) i prawdziwy katalog → .bak, link innego rice'a sprzątnięty"
mkdir -p "$T/dotfiles/waybar"; echo moje > "$T/dotfiles/waybar/config"
ln -s "$T/dotfiles/waybar" "$C/waybar"            # cudzy symlink (spoza rices/)
mkdir -p "$C/hypr"; echo moj > "$C/hypr/hyprland.conf"   # prawdziwy katalog użytkownika
ln -s "$A/rices/beta/rofi" "$C/rofi"              # link poprzedniego rice'a (alfa nie ma rofi)
: > "$MOCK_LOG"
out="$(run_step9 alfa)"
check "hypr → alfa"                              '[[ "$(link_of hypr)" == "$A/rices/alfa/hypr" ]]'
check "waybar → alfa"                            '[[ "$(link_of waybar)" == "$A/rices/alfa/waybar" ]]'
check "mako → alfa"                              '[[ "$(link_of mako)" == "$A/rices/alfa/mako" ]]'
check "cudzy symlink zachowany jako waybar.bak-*" 'ls -d "$C"/waybar.bak-* >/dev/null 2>&1 && [[ "$(readlink "$(ls -d "$C"/waybar.bak-* | head -n1)")" == "$T/dotfiles/waybar" ]]'
check "cudze pliki nietknięte"                   '[[ "$(<"$T/dotfiles/waybar/config")" == moje ]]'
check "katalog użytkownika w hypr.bak-*"         '[[ "$(cat "$C"/hypr.bak-*/hyprland.conf)" == moj ]]'
check "link do innego rice'a (rofi) sprzątnięty" '[[ ! -e "$C/rofi" && ! -L "$C/rofi" ]]'
check ".current_rice = alfa"                     '[[ "$(<"$A/.current_rice")" == alfa ]]'
check "link-only: bez hyprctl/waybar/notify"     '[[ ! -s "$MOCK_LOG" ]]'
check "brak linków wewnątrz rices/"              '[[ $(find "$A/rices" -type l | wc -l) -eq 0 ]]'
check "instalator: ✓ dla każdego folderu"        '[[ "$out" == *"✓ ~/.config/hypr → $A/rices/alfa/hypr"* && "$out" == *"✓ ~/.config/waybar → "* && "$out" == *"✓ ~/.config/mako → "* ]]'
check "instalator: komunikat o .bak dla waybar i hypr" '[[ "$out" == *"~/.config/waybar zachowany jako waybar.bak-"* && "$out" == *"~/.config/hypr zachowany jako hypr.bak-"* ]]'
check "SUMMARY_DONE: rice podlinkowany"          'grep -q "^DONE=Rice .alfa. symlinked" "$T/summary" && ! grep -q "^SKIPPED=Rice" "$T/summary"'

echo "== ponowny bieg (idempotencja): brak nowych .bak, linki bez zmian"
n_bak_before=$(ls -d "$C"/*.bak-* | wc -l)
out="$(run_step9 alfa)"
check "linki nadal → alfa"                       '[[ "$(link_of hypr)" == "$A/rices/alfa/hypr" && "$(link_of waybar)" == "$A/rices/alfa/waybar" ]]'
check "bez nowych .bak"                          '[[ $(ls -d "$C"/*.bak-* | wc -l) -eq $n_bak_before ]]'
check "bez komunikatu o .bak"                    '[[ "$out" != *"zachowany jako"* ]]'

echo "== błąd biblioteki → ✗ i SUMMARY_SKIPPED, nie ✓"
out="$(run_step9 nie-ma-takiego)"
check "brak ✓ przy nieistniejącym ricie"         '[[ "$out" != *"✓ ~/.config"* && "$out" == *"✗"* ]]'
check "SUMMARY_SKIPPED zamiast DONE"             'grep -q "^SKIPPED=Rice .nie-ma-takiego. NIE podlinkowany" "$T/summary" && ! grep -q "^DONE=Rice" "$T/summary"'
check "poprzednie linki (alfa) nietknięte"       '[[ "$(link_of hypr)" == "$A/rices/alfa/hypr" && "$(<"$A/.current_rice")" == alfa ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
