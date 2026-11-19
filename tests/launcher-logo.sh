#!/usr/bin/env bash
# =============================================
#   archenemy - tests/launcher-logo.sh
#   Skrypt modułu custom/launcher waybara: scripts/waybar/launcher-logo.sh
#   (2026-11-19). Logo w lewym boxie paska: domyślnie glif dystrybucji z
#   /etc/os-release, opcjonalnie logo archenemy (Æ, obraz z CSS) — wybór
#   w TUI Super+A → [l], stan w data/launcher-logo.dat.
#   Osobny pakiet, bo tests/waybar-launcher.sh czyta tylko pliki repo
#   (config, CSS, symlinki), a tu uruchamiamy skrypt na atrapie HOME i
#   os-release (hak ARCHENEMY_OS_RELEASE, tylko z ARCHENEMY_TEST=1).
#   Przypadki: brak .dat, distro, archenemy, śmieci w pliku, Arch, pochodna
#   Archa przez ID_LIKE, Fedora, NixOS, nieznana, brak os-release; tryb i
#   nazwa dystrybucji dla TUI; kod wyjścia zawsze 0 (niezerowy chowa moduł).
#   Bez roota, zapis tylko w mktemp.
#   Uruchom: bash tests/launcher-logo.sh   (kod 0 = wszystko przeszło)
# =============================================

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

# Atrapa ~/archenemy: skrypt i biblioteka os-release pod tymi samymi ścieżkami
# względnymi co w repo, własny katalog data/.
H="$T/home"; A="$H/archenemy"; DAT="$A/data/launcher-logo.dat"
mkdir -p "$A/scripts/waybar" "$A/install/lib" "$A/data"
cp "$REPO/scripts/waybar/launcher-logo.sh" "$A/scripts/waybar/" 2>/dev/null
cp "$REPO/install/lib/pkg.sh" "$A/install/lib/"
SCRIPT="$A/scripts/waybar/launcher-logo.sh"
export HOME="$H" ARCHENEMY_TEST=1

# Glify z bajtów UTF-8, żeby ten plik nie zawierał glifów (repo trzyma je
# wyłącznie w scripts/waybar/launcher-logo.sh — tests/waybar-launcher.sh).
G_ARCH=$(printf '\xf3\xb0\xa3\x87')     # U+F08C7 md-arch
G_FEDORA=$(printf '\xf3\xb0\xa3\x9b')   # U+F08DB md-fedora
G_NIXOS=$(printf '\xf3\xb1\x84\x85')    # U+F1105 md-nix
G_LINUX=$(printf '\xf3\xb0\x8c\xbd')    # U+F033D md-linux

osr() { printf '%s\n' "$@" > "$T/os-release"; export ARCHENEMY_OS_RELEASE="$T/os-release"; }
# run [argumenty] → RC i OUT (stdout); stderr osobno w $T/err.
run() { OUT="$(bash "$SCRIPT" "$@" 2>"$T/err")"; RC=$?; }
expect() {   # expect <opis> <oczekiwana linia JSON> [argumenty]
    local what="$1" want="$2"; shift 2
    run "$@"
    if [[ "$RC" == 0 && "$OUT" == "$want" && ! -s "$T/err" ]]; then ok "$what"
    else fail "$what: kod=$RC wyjście=[$OUT] stderr=[$(head -c 200 "$T/err")] (oczekiwano [$want])"; fi
}
# is <oczekiwane wyjście> <opis> — po run: kod 0 i dokładnie to wyjście.
is() {
    if [[ "$RC" == 0 && "$OUT" == "$1" ]]; then ok "$2"
    else fail "$2: kod=$RC [$(printf '%q' "$OUT")]"; fi
}
json_distro() { printf '{"text":"%s","class":"distro"}' "$1"; }
JSON_AE='{"text":" ","class":"archenemy"}'

if [[ ! -f "$SCRIPT" ]]; then
    fail "brak scripts/waybar/launcher-logo.sh"
    echo ""; echo "Wynik: $PASS ✓ / $FAIL ✗"; exit 1
fi

echo "== tryb z data/launcher-logo.dat (os-release: Arch)"
osr 'NAME="Arch Linux"' 'PRETTY_NAME="Arch Linux"' 'ID=arch'
rm -f "$DAT"
expect "brak pliku .dat → distro (glif Archa)"         "$(json_distro "$G_ARCH")"
echo distro > "$DAT"
expect "distro → glif dystrybucji"                     "$(json_distro "$G_ARCH")"
echo archenemy > "$DAT"
expect "archenemy → spacja + klasa archenemy"          "$JSON_AE"
printf 'archenemy' > "$DAT"
expect "archenemy bez końca linii"                     "$JSON_AE"
printf '  archenemy  \n' > "$DAT"
expect "archenemy z białymi znakami"                   "$JSON_AE"
printf 'Archenemy\n' > "$DAT"
expect "Archenemy (wielka litera) = śmieci → distro"   "$(json_distro "$G_ARCH")"
printf 'garbage\x01{"text":"x"}\n' > "$DAT"
expect "śmieci w pliku → distro"                       "$(json_distro "$G_ARCH")"
: > "$DAT"
expect "pusty plik → distro"                           "$(json_distro "$G_ARCH")"
rm -f "$DAT"; mkdir "$DAT"
expect "katalog zamiast pliku → distro, cicho"         "$(json_distro "$G_ARCH")"
rmdir "$DAT"
rm -rf "$A/data"
expect "brak katalogu data/ → distro"                  "$(json_distro "$G_ARCH")"
mkdir -p "$A/data"

echo "== glif według os-release (ID, ID_LIKE)"
rm -f "$DAT"
osr 'ID=endeavouros' 'ID_LIKE=arch' 'NAME="EndeavourOS"'
expect "pochodna Archa przez ID_LIKE=arch"             "$(json_distro "$G_ARCH")"
osr 'ID="manjaro"' 'ID_LIKE="arch"'
expect "pochodna Archa, wartości w cudzysłowie"        "$(json_distro "$G_ARCH")"
osr "ID='fedora'" 'NAME="Fedora Linux"'
expect "Fedora (apostrofy)"                            "$(json_distro "$G_FEDORA")"
osr 'ID=nobara' 'ID_LIKE="rhel centos fedora"'
expect "pochodna Fedory przez ID_LIKE"                 "$(json_distro "$G_FEDORA")"
osr 'ID=nixos' 'NAME=NixOS'
expect "NixOS"                                         "$(json_distro "$G_NIXOS")"
osr 'ID=debian' 'NAME="Debian GNU/Linux"'
expect "nieznana (Debian) → pingwin"                   "$(json_distro "$G_LINUX")"
osr 'ID=ubuntu' 'ID_LIKE=debian'
expect "nieznana z ID_LIKE spoza listy → pingwin"      "$(json_distro "$G_LINUX")"
osr 'NAME=bez-id'
expect "os-release bez ID → pingwin"                   "$(json_distro "$G_LINUX")"
# shellcheck disable=SC2016  # $(…) ma zostać tekstem — sprawdzamy brak eval
osr 'ID=$(touch '"$T"'/pwned)' 'ID_LIKE="arch;touch '"$T"'/pwned2"'
expect "wartości nie są wykonywane (bez eval)"         "$(json_distro "$G_LINUX")"
if [[ ! -e "$T/pwned" && ! -e "$T/pwned2" ]]; then ok "os-release nie jest wykonywany"
else fail "os-release wykonany jak kod"; fi
export ARCHENEMY_OS_RELEASE="$T/nie-ma-takiego-pliku"
expect "brak os-release (hak) → pingwin"               "$(json_distro "$G_LINUX")"
echo archenemy > "$DAT"
expect "brak os-release + archenemy → Æ"               "$JSON_AE"
rm -f "$DAT"

echo "== hak ARCHENEMY_OS_RELEASE tylko z ARCHENEMY_TEST=1"
osr 'ID=nixos'
OUT="$(ARCHENEMY_TEST='' bash "$SCRIPT" 2>/dev/null)"
if [[ "$OUT" != "$(json_distro "$G_NIXOS")" ]]; then ok "bez ARCHENEMY_TEST hak ignorowany (czyta system)"
else fail "hak działa bez ARCHENEMY_TEST=1"; fi

echo "== tryb i nazwa dla TUI"
osr 'NAME="Arch Linux"' 'PRETTY_NAME="Arch Linux"' 'ID=arch'
rm -f "$DAT"; run mode
is distro "mode: brak pliku → distro"
echo archenemy > "$DAT"; run mode
is archenemy "mode: archenemy"
echo junk > "$DAT"; run mode
is distro "mode: śmieci → distro"
run distro
is "Arch Linux" "distro: PRETTY_NAME"
osr 'NAME=NixOS' 'ID=nixos'; run distro
is "NixOS" "distro: NAME, gdy brak PRETTY_NAME"
osr 'ID=fedora'; run distro
is "fedora" "distro: ID, gdy brak nazw"
osr "PRETTY_NAME=\"Evil$(printf '\033')[31m Linux$(printf '\t')x\""; run distro
is "Evil[31m Linuxx" "distro: znaki sterujące wycięte"
export ARCHENEMY_OS_RELEASE="$T/nie-ma-takiego-pliku"; run distro
is "unknown" "distro: brak os-release → unknown"
run bogus-argument
is "$(json_distro "$G_LINUX")" "nieznany argument: kod 0 i JSON (waybar nie chowa modułu)"

echo "== brak biblioteki os-release (stary checkout) → pingwin, kod 0"
mv "$A/install/lib/pkg.sh" "$T/pkg.sh.bak"
osr 'ID=arch'
expect "bez install/lib/pkg.sh → pingwin"              "$(json_distro "$G_LINUX")"
mv "$T/pkg.sh.bak" "$A/install/lib/pkg.sh"

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
(( FAIL == 0 ))
