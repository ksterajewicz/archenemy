#!/bin/bash
# =============================================
#   archenemy - tests/install-summary.sh
#   Czy install.sh mówi prawdę o tym, co zrobił: kroki opcjonalne, które się
#   nie udały, trafiają do podsumowania [11], a baner nie ogłasza pełnego
#   sukcesu. Wycinki kroków są wycinane z install/install.sh sedem po
#   nagłówkach (jak [9] w tests/install-link.sh) i uruchamiane na atrapach
#   sudo/pacman/yay w mktemp. Bez roota, bez sieci.
#   Powód powstania (audyt 2026-11-05, Z3): jedna zła pozycja w dodatkach
#   anulowała całą transakcję pacmana, a podsumowanie milczało.
#   Uruchom: bash tests/install-summary.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval (zmienne żyją w eval)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$REPO/install/install.sh"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# cut_step <wzorzec początku> <wzorzec końca> <plik> — wycinek [początek, koniec)
cut_step() {
    local s e
    s=$(grep -n -m1 -- "$1" "$INST" | cut -d: -f1)
    e=$(grep -n -m1 -- "$2" "$INST" | cut -d: -f1)
    [[ -n "$s" && -n "$e" && "$e" -gt "$s" ]] || return 1
    sed -n "${s},$((e-1))p" "$INST" > "$3"
}

# run_step <wycinek> <stdin> → stdout+stderr; SUMMARY_* do $T/summary.
# Kolory puste, ARCHENEMY_DIR = atrapa repo; install/lib/aur.sh jak w install.sh.
run_step() {
    ARCHENEMY_DIR="$A" GREEN='' NC='' YELLOW='' RED='' CYAN='' BLUE='' \
    bash -c 'declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=(); source "$3"; source "$1"
             printf "DONE=%s\n" "${SUMMARY_DONE[@]}" > "$2"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}" >> "$2"' \
        _ "$1" "$T/summary" "$REPO/install/lib/aur.sh" <<<"$2" 2>&1
}

# ─── atrapy ──────────────────────────────────────────────────────────────────
mkdir -p "$T/bin"
cat > "$T/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
# pacman: -Qi <pkg> = zainstalowany, jeśli jest w MOCK_INSTALLED; -S logowane,
# nieznana nazwa (MOCK_PACMAN_UNKNOWN) anuluje całą transakcję jak prawdziwy.
cat > "$T/bin/pacman" <<'EOF'
#!/bin/bash
echo "pacman $*" >> "$MOCK_LOG"
if [[ "$1" == "-Qi" ]]; then
    [[ " ${MOCK_INSTALLED:-} " == *" $2 "* ]]; exit
fi
for a in "$@"; do
    [[ -n "${MOCK_PACMAN_UNKNOWN:-}" && "$a" == "$MOCK_PACMAN_UNKNOWN" ]] && { echo "error: target not found: $a" >&2; exit 1; }
done
exit 0
EOF
cat > "$T/bin/yay" <<'EOF'
#!/bin/bash
echo "yay $*" >> "$MOCK_LOG"
[[ "${MOCK_YAY_FAIL:-0}" == 1 ]] && exit 1
exit 0
EOF
chmod +x "$T/bin"/*
export PATH="$T/bin:$PATH"
export MOCK_LOG="$T/log"

A="$T/archenemy"
mkdir -p "$A/packages" "$A/install"
printf 'btop\nkeepassxc\nbadname\n' > "$A/packages/additional-packages-pacman.txt"
printf 'megasync\n' > "$A/packages/additional-packages-aur.txt"

# ─── [5] dodatki: wynik pacmana i yay w podsumowaniu (Z3) ────────────────────
echo "== [5] dodatkowe pakiety"
cut_step '^read -rp "Would you like to install additional useful packages' '^# ─── 6\. DEVICE DETECTION' "$T/step5.sh"
check "wycinek [5] (dodatki) znaleziony"         '[[ -s "$T/step5.sh" ]]'

: > "$MOCK_LOG"
out=$(MOCK_PACMAN_UNKNOWN=badname run_step "$T/step5.sh" $'y\n1 3\n')
check "zła nazwa: pacman wołany"                 'grep -q "pacman -S --needed btop badname" "$MOCK_LOG"'
check "zła nazwa: jawny błąd na ekranie"         '[[ "$out" == *"✗"*"btop"* ]]'
check "zła nazwa: porażka w podsumowaniu"        'grep -q "^SKIPPED=.*btop.*badname" "$T/summary"'

out=$(MOCK_PACMAN_UNKNOWN=badname MOCK_INSTALLED="btop" run_step "$T/step5.sh" $'y\n1 3\n')
check "w podsumowaniu tylko to, czego nie ma"    'grep -q "^SKIPPED=.*badname" "$T/summary" && ! grep -q "^SKIPPED=.*btop" "$T/summary"'

out=$(run_step "$T/step5.sh" $'y\n1 2\n')
check "udana instalacja: podsumowanie czyste"    '! grep -q "^SKIPPED=." "$T/summary" && [[ "$out" != *"✗"* ]]'

out=$(MOCK_YAY_FAIL=1 run_step "$T/step5.sh" $'y\n4\nn\n')
check "AUR: porażka yay w podsumowaniu"          'grep -q "^SKIPPED=.*megasync" "$T/summary"'

out=$(run_step "$T/step5.sh" $'y\n4\nn\n')
check "AUR: udany yay — podsumowanie czyste"     '! grep -q "^SKIPPED=." "$T/summary"'

# Bez yay: PATH tylko z atrapami i bashem (yay bywa w /usr/bin maszyny testowej).
mkdir -p "$T/bin-noyay"
for b in sudo pacman; do ln -sf "$T/bin/$b" "$T/bin-noyay/$b"; done
ln -sf "$(command -v bash)" "$T/bin-noyay/bash"
out=$(PATH="$T/bin-noyay" run_step "$T/step5.sh" $'y\n4\n')
check "AUR bez yay: pominięcie w podsumowaniu"   'grep -q "^SKIPPED=.*megasync" "$T/summary"'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
