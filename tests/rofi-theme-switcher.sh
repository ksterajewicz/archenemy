#!/bin/bash
# =============================================
#   archenemy - tests/rofi-theme-switcher.sh
#   Menu Super+T (scripts/rofi/rofi_theme_switcher.sh) z podglądami
#   rices/<RICE_NAME>/preview.png — na atrapie rofi (zapisuje wejście i
#   argumenty, odpowiada zadaną linią) i atrapie $HOME/archenemy w mktemp.
#   Bez Hyprlanda, bez roota.
#
#   Sprawdza: wpis z podglądem niesie `\0icon\x1f<ścieżka>` do istniejącego
#   pliku; ścieżkę wyznacza RICE_NAME ze stubu (etykieta ≠ folder); rice bez
#   podglądu = wpis bez zmian; bez żadnego podglądu — zwykła lista motywu;
#   wybór uruchamia stub; literówka nie. Do tego stan repo: każdy stub z
#   scripts/changing-theme-scripts/ ma w repo rices/<RICE_NAME>/preview.png
#   (poprawny PNG — makieta 640x360 z gen_rice_preview.py albo prawdziwy
#   zrzut ekranu dowolnego rozmiaru, którym właściciel ją podmieni).
#   Uruchom: bash tests/rofi-theme-switcher.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── atrapy ──────────────────────────────────────────────────────────────────
mkdir -p "$T/bin"
cat > "$T/bin/rofi" <<'MOCK'
#!/bin/bash
cat > "$MOCK_ROFI_DIR/in"
printf '%s\n' "$@" > "$MOCK_ROFI_DIR/args"
[[ -n "${MOCK_ROFI_ANSWER:-}" ]] || exit 1
printf '%s\n' "$MOCK_ROFI_ANSWER"
MOCK
printf '#!/bin/bash\necho "NOTIFY: $*" >> "$MOCK_LOG"\n' > "$T/bin/notify-send"
chmod +x "$T/bin"/*
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log" MOCK_ROFI_DIR="$T/rofi"
mkdir -p "$MOCK_ROFI_DIR"

# ─── atrapa $HOME/archenemy: dwa stuby, jeden rice z podglądem ──────────────
export HOME="$T/home"
A="$HOME/archenemy"
mkdir -p "$A/scripts/rofi" "$A/scripts/changing-theme-scripts" "$A/rices/alfa" "$A/rices/beta"
ln -s "$REPO/scripts/rofi/rofi_theme_switcher.sh" "$A/scripts/rofi/rofi_theme_switcher.sh"
ln -s "$REPO/scripts/rofi/lib" "$A/scripts/rofi/lib"
# Stub „Alfa Look" → folder alfa (etykieta celowo inna niż folder).
printf '#!/bin/bash\nRICE_NAME="alfa"\necho "RAN alfa" >> "$MOCK_LOG"\n' > "$A/scripts/changing-theme-scripts/Alfa Look.sh"
printf '#!/bin/bash\nRICE_NAME="beta"\necho "RAN beta" >> "$MOCK_LOG"\n' > "$A/scripts/changing-theme-scripts/beta.sh"
printf 'PNG' > "$A/rices/alfa/preview.png"
SW="$A/scripts/rofi/rofi_theme_switcher.sh"

rofi_in() { tr '\000\037' '|#' < "$MOCK_ROFI_DIR/in"; }
run() { : > "$MOCK_LOG"; MOCK_ROFI_ANSWER="${1:-}" bash "$SW" >/dev/null 2>&1; }

echo "== podglądy rice'ów"
run ""
check "rice z podglądem: \\0icon\\x1f + ścieżka RICE_NAME" 'rofi_in | grep -qxF "Alfa Look|icon#$A/rices/alfa/preview.png"'
check "rice bez podglądu: wpis bez zmian"     'rofi_in | grep -qx "beta"'
check "siatka: -show-icons, 3 kolumny, 1 wiersz" 'grep -qx -- "-show-icons" "$MOCK_ROFI_DIR/args" && grep -q "columns: 3; lines: 1;" "$MOCK_ROFI_DIR/args"'
check "Esc: nic nie uruchomione"              '[[ ! -s "$MOCK_LOG" ]]'

echo "== wybór"
run "Alfa Look"
check "wybór uruchamia stub (etykieta ze spacją)" 'grep -qx "RAN alfa" "$MOCK_LOG"'
run "literowka"
check "literówka: powiadomienie, żaden stub"  'grep -q "NOTIFY: .*No such rice script" "$MOCK_LOG" && ! grep -q "^RAN" "$MOCK_LOG"'

echo "== żaden rice bez podglądu → zwykła lista motywu"
rm -f "$A/rices/alfa/preview.png"
run ""
check "zero ikon i bez -theme-str"            '! grep -q $'"'"'\x1f'"'"' "$MOCK_ROFI_DIR/in" && ! grep -q -- "-theme-str" "$MOCK_ROFI_DIR/args"'

echo "== repo: każdy stub ma rices/<RICE_NAME>/preview.png (poprawny PNG)"
for stub in "$REPO"/scripts/changing-theme-scripts/*.sh; do
    rice=$(sed -n 's/^RICE_NAME="\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$stub" | head -n1)
    png="$REPO/rices/$rice/preview.png"
    # sygnatura PNG + IHDR: szerokość/wysokość (big-endian) z bajtów 16..23
    dims=$(od -An -tu1 -j16 -N8 "$png" 2>/dev/null | awk '{ printf "%dx%d", $1*16777216+$2*65536+$3*256+$4, $5*16777216+$6*65536+$7*256+$8 }')
    sig=$(od -An -tx1 -N8 "$png" 2>/dev/null | tr -d ' \n')
    check "$(basename "$stub" .sh) → rices/$rice/preview.png" '[[ "$sig" == "89504e470d0a1a0a" && "$dims" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]'
done

echo ""
echo "passed: $PASS, failed: $FAIL"
(( FAIL == 0 ))
