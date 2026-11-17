#!/usr/bin/env bash
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
#   A10 (ten sam audyt): znacznikiem kompletu była PIERWSZA forma, a plik szedł
#   wprost pod docelową nazwę — przerwany bieg (reboot w trakcie generowania
#   w tle) zostawiał „gotowe” bez reszty form i ucięty PNG w Super+W. Przerwę
#   test robi deterministycznie: generator przez runpy z podmienionym
#   zlib.compress / open, które w zadanej chwili kończą proces os._exit (jak
#   SIGKILL — bez sprzątania).
#   Uruchom: bash tests/dither-flux-sizes.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval)
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
# Jak install.sh [9.7]: pusty plan = nic nie startuje (generator bez rozmiarów
# rysowałby domyślne 1920x1080 i 2560x1600, czyli minuty).
generate() { ((${#FLUX_SIZES[@]})) || return 0; dither_flux_start "$GEN" "$OUT"; wait "$!"; }
# *.png (jak lista Super+W), które nie są całym PNG (sygnatura + IEND na końcu)
broken_pngs() {
    find "$OUT" -type f -iname '*.png' -exec python3 -c '
import sys
bad = 0
for p in sys.argv[1:]:
    d = open(p, "rb").read()
    bad += not (d.startswith(b"\x89PNG") and d[-8:-4] == b"IEND")
print(bad)' {} + 2>/dev/null | awk '{s += $1} END {print s + 0}'
}
# Generator z przerwą: INTERRUPT=after-compress (po INTERRUPT_CALLS plikach,
# przed zapisem następnego) albo mid-write (połowa pierwszego pliku na dysku).
cat > "$T/interrupt.py" <<'EOF'
import builtins, os, runpy, sys, zlib
gen = sys.argv[1]
sys.argv = [gen] + sys.argv[2:]
mode = os.environ["INTERRUPT"]
if mode == "after-compress":
    left = [int(os.environ["INTERRUPT_CALLS"])]
    real_compress = zlib.compress
    def compress(*a, **k):
        if left[0] == 0:
            os._exit(137)
        left[0] -= 1
        return real_compress(*a, **k)
    zlib.compress = compress
elif mode == "mid-write":
    real_open = builtins.open
    class Half:
        def __init__(self, f): self.f = f
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def write(self, b):
            self.f.write(b[:len(b) // 2]); self.f.flush(); os._exit(137)
    def fake_open(file, mode="r", *a, **k):
        f = real_open(file, mode, *a, **k)
        return Half(f) if "w" in mode and "b" in mode else f
    builtins.open = fake_open
runpy.run_path(gen, run_name="__main__")
EOF

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
rm -f "${M:?}"/*.dat
dat 'Virtual:1 x' 64x72 other
dither_flux_plan "$M" "$OUT"
check "tag oczyszczony do liter, cyfr i myślnika" 'has_size m-Virtual-1-x:64x72'
generate
check "pliki dla oczyszczonego tagu"           'complete_set m-Virtual-1-x 64x72'

echo "== A10: bieg przerwany po pierwszej formie nie melduje kompletu"
rm -rf "${OUT:?}"; rm -f "${M:?}"/*.dat; mkdir -p "$OUT"
dat eDP-1 64x64 primary
dat DP-1 80x64 secondary
dither_flux_plan "$M" "$OUT"
INTERRUPT=after-compress INTERRUPT_CALLS=2 python3 "$T/interrupt.py" "$GEN" "$OUT" milford-woda 2026 "${FLUX_SIZES[@]}" >/dev/null 2>&1
check "przerwa: pierwsza forma na dysku, druga nie" '[[ -f "$OUT/dither-flux-${FORMS[0]}-v1-64x64.png" && ! -e "$OUT/dither-flux-${FORMS[1]:-brak}-v1-64x64.png" ]]'
dither_flux_plan "$M" "$OUT"
check "po przerwie oba rozmiary wracają do kolejki" 'has_size v1:64x64 && has_size v2:80x64 && (( ${#FLUX_READY[@]} == 0 ))'
generate
check "następny bieg dorabia komplet"          'complete_set v1 64x64 && complete_set v2 80x64'
dither_flux_plan "$M" "$OUT"
check "dopiero teraz gotowe"                   '(( ${#FLUX_SIZES[@]} == 0 && ${#FLUX_READY[@]} == 2 ))'

echo "== A10: zapis przerwany w połowie pliku"
rm -rf "${OUT:?}"; mkdir -p "$OUT"
INTERRUPT=mid-write python3 "$T/interrupt.py" "$GEN" "$OUT" milford-woda 2026 v1:64x64 >/dev/null 2>&1
check "żaden *.png nie jest ucięty (lista Super+W)" '[[ "$(broken_pngs)" == 0 ]]'
check "nic pod docelową nazwą pierwszej formy" '[[ ! -e "$OUT/dither-flux-${FORMS[0]}-v1-64x64.png" ]]'
python3 "$GEN" "$OUT" milford-woda 2026 v1:64x64 >"$T/one.log" 2>&1
check "następny bieg: komplet, bez plików .part" 'complete_set v1 64x64 && [[ -z "$(find "$OUT" -name "*.part")" ]]'

echo "== znacznik kompletu = ostatnia forma generatora"
check "DITHER_FLUX_LAST_FORM to ostatnia z FORMS" '[[ "${FORMS[-1]}" == "$DITHER_FLUX_LAST_FORM" ]]'
last="$(sed -n 's/^  ✓ dither-flux-\(.*\)-v1-64x64\.png .*/\1/p' "$T/one.log" | tail -n 1)"
check "generator zapisuje ją jako ostatnią"   '[[ -n "$last" && "$last" == "$DITHER_FLUX_LAST_FORM" ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
((FAIL == 0))
