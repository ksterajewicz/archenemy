#!/bin/bash
# =============================================
#   archenemy - tests/install-aur.sh
#   Kroki AUR instalatora (install/lib/aur.sh, K6+K7 z audytu
#   bezpieczeństwa 2026-11-14) na atrapach git/makepkg/yay/pagera w mktemp:
#   yay budowany w świeżym katalogu mktemp (nie /tmp/yay) i sprzątany,
#   przegląd PKGBUILD na żądanie, ✓ tylko gdy yay naprawdę jest w PATH,
#   `--answerdiff All` wyłącznie po „y”. Bez sieci, bez roota.
#   Uruchom: bash tests/install-aur.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2034,SC2016,SC1111  # kolory czyta biblioteka; check() robi eval na cytowanym wyrażeniu; „” w etykietach to tekst
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

mkdir -p "$T/bin" "$T/tmp" "$T/log"
export TMPDIR="$T/tmp" LOG="$T/log"
# git clone <url> <katalog> → katalog z PKGBUILD; MOCK_CLONE_FAIL=1 = błąd sieci.
cat > "$T/bin/git" <<'EOF'
#!/bin/bash
[[ "$1" == clone ]] || exit 1
[[ -n "${MOCK_CLONE_FAIL:-}" ]] && exit 128
mkdir -p "$3" && echo 'pkgname=yay' > "$3/PKGBUILD" && echo "$3" > "$LOG/clone-dir"
EOF
# makepkg -si → zapisuje katalog budowy; MOCK_MAKEPKG_INSTALLS=1 „instaluje” yay.
cat > "$T/bin/makepkg" <<'EOF'
#!/bin/bash
pwd > "$LOG/makepkg-cwd"
[[ -n "${MOCK_MAKEPKG_INSTALLS:-}" ]] && printf '#!/bin/bash\necho "$*" > "$LOG/yay-args"\n' > "$MOCK_BIN/yay" && chmod +x "$MOCK_BIN/yay"
exit "${MOCK_MAKEPKG_RC:-0}"
EOF
cat > "$T/bin/pager" <<'EOF'
#!/bin/bash
echo "$1" > "$LOG/paged"
EOF
chmod +x "$T/bin"/*
# PATH tylko z atrap i potrzebnych narzędzi: prawdziwy yay w systemie
# (np. na maszynie dewelopera) zafałszowałby test „✓ tylko gdy yay jest w PATH”.
mkdir -p "$T/sys"
for c in bash mktemp rm cat mkdir dirname chmod find; do ln -s "$(command -v "$c")" "$T/sys/$c"; done
export PATH="$T/bin:$T/sys" MOCK_BIN="$T/bin" PAGER="$T/bin/pager"
RED='' GREEN='' YELLOW='' NC=''

reset_case() { rm -rf "$T/log"/* "$T/bin/yay"; unset MOCK_CLONE_FAIL MOCK_MAKEPKG_INSTALLS MOCK_MAKEPKG_RC; }
run_boot() {   # run_boot <stdin> — aur_bootstrap_yay w osobnym bashu; wyjście + RC
    out="$(printf '%b' "$1" | bash -c 'source "$0"; aur_bootstrap_yay' "$REPO/install/lib/aur.sh" 2>&1)"; RC=$?
}

echo "== budowa yay: świeży mktemp, sprzątanie, odczytany wynik"
reset_case; mkdir -p "$T/tmp/yay"; echo podstawiony > "$T/tmp/yay/PKGBUILD"
export MOCK_MAKEPKG_INSTALLS=1
run_boot '\n'
check "Enter przy przeglądzie → makepkg uruchomiony"  '[[ -f "$LOG/makepkg-cwd" && $RC -eq 0 ]]'
check "budowa w mktemp, nie w stałym \$TMPDIR/yay"     '[[ "$(cat "$LOG/makepkg-cwd")" == "$T/tmp/archenemy-yay."*"/yay" ]]'
check "katalog budowy usunięty po biegu"              '[[ ! -e "$(dirname "$(cat "$LOG/clone-dir")")" ]]'
check "podstawiony \$TMPDIR/yay nietknięty i nieużyty" '[[ "$(cat "$T/tmp/yay/PKGBUILD")" == podstawiony ]]'
check "zdanie o AUR przed budową"                     '[[ "$out" == *"comes from the AUR"* ]]'
check "✓ dopiero gdy yay jest w PATH"                 '[[ "$out" == *"✓ yay installed"* && -x "$T/bin/yay" ]]'

echo "== przegląd PKGBUILD na żądanie"
reset_case; export MOCK_MAKEPKG_INSTALLS=1
run_boot 'y\nn\n'
check "„y” → pager dostaje PKGBUILD"                  '[[ "$(cat "$LOG/paged" 2>/dev/null)" == */yay/PKGBUILD ]]'
check "odmowa po przeglądzie → makepkg NIE rusza"     '[[ ! -f "$LOG/makepkg-cwd" && $RC -ne 0 ]]'
check "odmowa → brak ✓"                               '[[ "$out" != *"✓ yay installed"* ]]'
reset_case; export MOCK_MAKEPKG_INSTALLS=1
run_boot 'y\ny\n'
check "przegląd + „y” → budowa"                       '[[ -f "$LOG/makepkg-cwd" && $RC -eq 0 ]]'

echo "== porażki bez fałszywego ✓"
reset_case
run_boot '\n'
check "makepkg 0, ale yay nie w PATH → ✗"             '[[ $RC -ne 0 && "$out" != *"✓ yay installed"* ]]'
reset_case; export MOCK_CLONE_FAIL=1
run_boot '\n'
check "nieudany clone → ✗, makepkg nie rusza"         '[[ $RC -ne 0 && ! -f "$LOG/makepkg-cwd" ]]'
check "nieudany clone → bez śmieci w \$TMPDIR"         '[[ -z "$(find "$T/tmp" -maxdepth 1 -name "archenemy-yay.*")" ]]'

echo "== yay -S: zdanie o AUR i --answerdiff All tylko po „y”"
reset_case; export MOCK_MAKEPKG_INSTALLS=1; run_boot '\n'
out="$(printf '\n' | bash -c 'source "$0"; aur_install brave-bin' "$REPO/install/lib/aur.sh" 2>&1)"
check "domyślnie bez --answerdiff"                    '[[ "$(cat "$LOG/yay-args")" == "-S --needed brave-bin" ]]'
check "zdanie o AUR przed yay -S"                     '[[ "$out" == *"user-submitted PKGBUILDs"* ]]'
out="$(printf 'y\n' | bash -c 'source "$0"; aur_install brave-bin' "$REPO/install/lib/aur.sh" 2>&1)"
check "„y” → --answerdiff All"                        '[[ "$(cat "$LOG/yay-args")" == "-S --needed --answerdiff All brave-bin" ]]'

echo "== install.sh używa biblioteki"
INST="$(cat "$REPO/install/install.sh")"
check "brak stałego /tmp/yay"                         '[[ "$INST" != *"/tmp/yay"* ]]'
check "brak gołego yay -S (zawsze przez aur_install)" '[[ "$INST" != *"yay -S --needed \""* ]]'
check "install.sh source’uje install/lib/aur.sh"      '[[ "$INST" == *"source \"\$ARCHENEMY_DIR/install/lib/aur.sh\""* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
