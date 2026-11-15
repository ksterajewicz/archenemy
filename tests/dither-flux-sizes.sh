#!/bin/bash
# =============================================
#   archenemy - tests/dither-flux-sizes.sh
#   Tapety dither-flux pod monitory z data/monitors/*.dat: plan
#   (scripts/wallpapers/lib/dither-flux-sizes.sh) i PRAWDZIWY generator
#   (scripts/wallpapers/gen_dither_flux_wallpaper.py) na rozmiarach ok. 64 px,
#   bez Hyprlanda, w mktemp. Skutek = pliki PNG w generated/, nie argumenty.
#
#   Powód powstania (audyt 2026-11-05, A5): monitor z rolą other dostaje tag
#   m-<złącze> (np. m-HDMI-A-1), a generator przyjmował tylko [a-z0-9]+. Brał
#   taki tag za filtr form i kończył kodem 0 bez żadnego pliku, także bez v1/v2.
#   tests/monitor-settings.sh podstawia atrapę generatora, więc tego nie widział.
#   Uruchom: bash tests/dither-flux-sizes.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016  # check() robi eval na cytowanym wyrażeniu
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

if ! command -v python3 >/dev/null 2>&1; then
    echo "  ? skip: brak python3 (pakiet python z packages/requirements-pacman.txt)"
    echo "Wynik: pominięte (brak python3)"
    exit 0
fi
export PYTHONDONTWRITEBYTECODE=1    # import generatora nie zostawia __pycache__ w repo

GEN="$REPO/scripts/wallpapers/gen_dither_flux_wallpaper.py"
# shellcheck source=scripts/wallpapers/lib/dither-flux-sizes.sh
source "$REPO/scripts/wallpapers/lib/dither-flux-sizes.sh"
M="$T/monitors"; OUT="$T/generated"
mkdir -p "$M"

# Formy z generatora (moduł ma strażnika __main__, import niczego nie rysuje).
mapfile -t FORMS < <(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gen", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print("\n".join(f[0] for f in mod.FORMS))' "$GEN")
check "generator ma listę form" '(( ${#FORMS[@]} >= 1 ))'

dat() { printf 'MONITOR=%s\nRESOLUTION=%s\nROLE=%s\n' "$1" "$2" "$3" > "$M/$1.dat"; }
# plik PNG (sygnatura) dla każdej formy; $1 = tag, $2 = rozdzielczość
complete_set() {
    local form f
    for form in "${FORMS[@]}"; do
        f="$OUT/dither-flux-$form-$1-$2.png"
        [[ "$(head -c 4 "$f" 2>/dev/null | od -An -c | tr -d ' ')" == '211PNG' ]] || return 1
    done
}
has_size() { local s; for s in "${FLUX_SIZES[@]}"; do [[ "$s" == "$1" ]] && return 0; done; return 1; }
generate() { dither_flux_start "$GEN" "$OUT"; wait "$!"; }

echo "== A5: monitor z rolą other nie blokuje tapet dither-flux"
dat eDP-1 64x64 primary
dat DP-1 80x64 secondary
dat HDMI-A-1 96x64 other
dither_flux_plan "$M" "$OUT"
check "plan: v1, v2 i tag other z nazwy złącza" 'has_size v1:64x64 && has_size v2:80x64 && has_size m-HDMI-A-1:96x64 && (( ${#FLUX_SIZES[@]} == 3 ))'
generate
check "primary: komplet form v1"               'complete_set v1 64x64'
check "secondary: komplet form v2"             'complete_set v2 80x64'
check "other: komplet form m-HDMI-A-1"         'complete_set m-HDMI-A-1 96x64'
dither_flux_plan "$M" "$OUT"
check "drugi plan: nic do zrobienia, 3 gotowe" '(( ${#FLUX_SIZES[@]} == 0 && ${#FLUX_READY[@]} == 3 ))'

echo "== nazwa złącza ze znakiem spoza tagu (dwukropek, spacja)"
rm -f "$M"/*.dat
dat 'Virtual:1 x' 64x72 other
dither_flux_plan "$M" "$OUT"
check "tag oczyszczony do liter, cyfr i myślnika" 'has_size m-Virtual-1-x:64x72'
generate
check "pliki dla oczyszczonego tagu"           'complete_set m-Virtual-1-x 64x72'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
((FAIL == 0))
