#!/bin/bash
# =============================================
#   archenemy - tests/packages-exist.sh
#   Czy każda nazwa z packages/*.txt naprawdę istnieje tam, skąd ją
#   instalujemy: listy *-pacman.txt → `pacman -Slq` (lokalna baza sync,
#   tylko odczyt, jedno wywołanie), listy *-aur.txt → AUR RPC v5 (jedno zapytanie `info`).
#   Powód (audyt bezpieczeństwa 2026-11-14, S3/S8): `protonvpn` i `omen-fan`
#   zniknęły z AUR — porzuconą nazwę może zarejestrować ktokolwiek i
#   `yay -S` zbudowałby jego PKGBUILD; `swayosd-git` budował niesprawdzony HEAD.
#   Reguły:
#     - w requirements-*.txt zakaz pakietów `-git` (sprawdzane zawsze, offline);
#     - nazwa z listy pacmana musi być w repo; jeśli jest tylko w AUR → ✗;
#     - nazwa z listy AUR musi być w AUR i NIE w oficjalnych repo (→ ✗,
#       przenieś na listę pacmana);
#     - brak sieci / pacmana = „skip”, NIGDY „✓”; bez bazy [multilib] skip
#       tylko dla nazw z multilib (steam, lib32-*), inne nieznane → ✗.
#   Haki testowe: ARCHENEMY_PKG_DIR (katalog list), ARCHENEMY_AUR_RPC_JSON
#   (plik z odpowiedzią RPC zamiast sieci; "offline" = udawany brak sieci).
#   Najpierw autotest logiki na atrapach w mktemp, potem prawdziwe listy.
#   Uruchom: bash tests/packages-exist.sh   (kod 0 = brak ✗; skip ≠ ✓)
# =============================================

# shellcheck disable=SC1111  # „” w komunikatach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  ? skip: $1"; }

# list_names <plik> — nazwy pakietów bez komentarzy i pustych linii
# (to samo cięcie co install.sh [5]: pierwsze słowo linii).
list_names() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%[[:space:]]*}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        printf '%s\n' "$line"
    done < "$1"
}

# aur_json <nazwy…> — odpowiedź RPC v5 `info` na stdout; kod 1 = brak sieci.
aur_json() {
    local hook="${ARCHENEMY_AUR_RPC_JSON:-}" url="https://aur.archlinux.org/rpc/v5/info?" n
    if [[ -n "$hook" ]]; then
        [[ "$hook" == offline ]] && return 1
        cat "$hook"; return 0
    fi
    command -v curl >/dev/null 2>&1 || return 1
    for n in "$@"; do url+="arg%5B%5D=$n&"; done
    curl -fsS -m 15 "${url%&}" 2>/dev/null
}

# is_multilib_name <nazwa> — nazwy z [multilib]; ten sam wzorzec co ostrzeżenie
# install.sh [5] (`case "$p" in steam|lib32-*)`, sprzężenie pilnuje autotest).
# Bez zsynchronizowanej bazy [multilib] (VPS, CI) skip dostają TYLKO one —
# każda inna nieznana nazwa to ✗ (R1 P1: literówka przechodziła jako skip).
is_multilib_name() { case "$1" in steam|lib32-*) return 0 ;; esac; return 1; }

# check_lists <katalog> — wszystkie reguły dla czterech list w katalogu.
check_lists() {
    local dir="$1" f n json have_pacman=1 have_multilib=1 aur_ok=1
    local -a pac=() aur=()
    for f in "$dir"/requirements-*.txt; do
        [[ -f "$f" ]] || continue
        while IFS= read -r n; do
            [[ "$n" == *-git ]] && fail "$(basename "$f"): $n — wymagany pakiet -git buduje niesprawdzony HEAD"
        done < <(list_names "$f")
    done
    for f in "$dir"/*-pacman.txt; do [[ -f "$f" ]] && mapfile -t -O "${#pac[@]}" pac < <(list_names "$f"); done
    for f in "$dir"/*-aur.txt;    do [[ -f "$f" ]] && mapfile -t -O "${#aur[@]}" aur < <(list_names "$f"); done

    # Jedno `pacman -Slq` (wszystkie zsynchronizowane repo, tylko odczyt) zamiast
    # `pacman -Si` na nazwę — każde wywołanie pacmana to ~1 s czytania baz.
    local repo_names="" multi
    command -v pacman >/dev/null 2>&1 && repo_names="$(pacman -Slq 2>/dev/null)"
    [[ -n "$repo_names" ]] || have_pacman=0
    multi="$(pacman -Slq multilib 2>/dev/null)"; [[ -n "$multi" ]] || have_multilib=0
    repo_names=$'\n'"$repo_names"$'\n'
    in_repo() { [[ "$repo_names" == *$'\n'"$1"$'\n'* ]]; }
    # Jedno zapytanie RPC dla list AUR i dla nazw pacmana (wykrycie „tylko w AUR”).
    if json="$(aur_json "${aur[@]}" "${pac[@]}")" && [[ "$json" == *'"resultcount"'* ]]; then :; else aur_ok=0; json=""; fi
    in_aur() { [[ "$json" == *"\"Name\":\"$1\""* ]]; }

    for n in "${pac[@]}"; do
        if ((!have_pacman)); then skip "$n — brak pacmana albo bazy sync (pacman -Sy robi właściciel)"; continue; fi
        if in_repo "$n"; then ok "pacman: $n"; continue; fi
        if ((aur_ok)) && in_aur "$n"; then fail "pacman: $n jest tylko w AUR — przenieś na listę *-aur.txt"
        elif ((!have_multilib)) && is_multilib_name "$n"; then skip "$n — pakiet z [multilib], a baza [multilib] nie jest zsynchronizowana"
        elif ((!have_multilib)); then fail "pacman: $n — nie istnieje w repo (pacman -Slq; bez [multilib] skip tylko dla steam i lib32-*; nieaktualna baza? pacman -Sy robi właściciel)"
        else fail "pacman: $n — nie istnieje w repo (pacman -Slq; nieaktualna baza? pacman -Sy robi właściciel)"
        fi
    done
    for n in "${aur[@]}"; do
        if ((have_pacman)) && in_repo "$n"; then fail "AUR: $n jest w oficjalnych repo — przenieś na listę *-pacman.txt"
        elif ((!aur_ok)); then skip "$n — AUR RPC niedostępne (brak sieci)"
        elif ! in_aur "$n"; then fail "AUR: $n — nie istnieje (nazwę może zarejestrować ktokolwiek)"
        else ok "AUR: $n"
        fi
    done
}

# ── autotest logiki na atrapach (bez sieci, bez prawdziwego pacmana) ─────────
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1
mkdir -p "$T/bin" "$T/pkg"
cat > "$T/bin/pacman" <<'EOF'
#!/bin/bash
case "$*" in
    "-Slq") printf 'hyprland\nswayosd\n'; [[ -n "${MOCK_MULTILIB_MISSING:-}" ]] || printf 'steam\nlib32-gamemode\n' ;;
    "-Slq multilib") [[ -n "${MOCK_MULTILIB_MISSING:-}" ]] || printf 'steam\nlib32-gamemode\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$T/bin/pacman"
printf 'hyprland\n# komentarz\nswayosd-git\n' > "$T/pkg/requirements-pacman.txt"
printf 'brave-bin\n' > "$T/pkg/requirements-aur.txt"
printf 'vscodium\nsteam\nlib32-gamemode\nhyprlandd\n' > "$T/pkg/additional-packages-pacman.txt"
printf 'omen-fan\nswayosd\n' > "$T/pkg/additional-packages-aur.txt"
printf '{"resultcount":2,"results":[{"Name":"brave-bin"},{"Name":"vscodium"}],"type":"multiinfo","version":5}' > "$T/rpc.json"

selftest() {   # selftest <opis> <oczekiwany fragment> <env…>
    local desc="$1" want="$2" out; shift 2
    out="$(env PATH="$T/bin:$PATH" "$@" bash "${BASH_SOURCE[0]}" --lists-only "$T/pkg" 2>&1)"
    if [[ "$out" == *"$want"* ]]; then ok "autotest: $desc"; else fail "autotest: $desc — brak „$want”"; fi
}
if [[ "${1:-}" == --lists-only ]]; then
    check_lists "$2"
    echo "Result: $PASS passed / $FAIL failed / $SKIP skipped"
    ((FAIL == 0)); exit
fi

echo "== autotest logiki (atrapa pacmana, fałszywa odpowiedź RPC)"
selftest "-git w wymaganych → ✗" "✗ requirements-pacman.txt: swayosd-git" ARCHENEMY_AUR_RPC_JSON="$T/rpc.json"
selftest "nazwa AUR, której nie ma → ✗" "✗ AUR: omen-fan — nie istnieje" ARCHENEMY_AUR_RPC_JSON="$T/rpc.json"
selftest "pakiet z extra na liście AUR → ✗" "✗ AUR: swayosd jest w oficjalnych repo" ARCHENEMY_AUR_RPC_JSON="$T/rpc.json"
selftest "nazwa pacmana tylko w AUR → ✗" "✗ pacman: vscodium jest tylko w AUR" ARCHENEMY_AUR_RPC_JSON="$T/rpc.json"
selftest "istniejąca nazwa AUR → ✓" "✓ AUR: brave-bin" ARCHENEMY_AUR_RPC_JSON="$T/rpc.json"
selftest "brak [multilib] lokalnie → skip, nie ✗" "? skip: steam" ARCHENEMY_AUR_RPC_JSON="$T/rpc.json" MOCK_MULTILIB_MISSING=1
selftest "brak [multilib] → skip także dla lib32-*" "? skip: lib32-gamemode" ARCHENEMY_AUR_RPC_JSON="$T/rpc.json" MOCK_MULTILIB_MISSING=1
selftest "brak [multilib]: literówka spoza multilib → ✗, nie skip" "✗ pacman: hyprlandd" ARCHENEMY_AUR_RPC_JSON="$T/rpc.json" MOCK_MULTILIB_MISSING=1
selftest "z [multilib]: literówka → ✗" "✗ pacman: hyprlandd" ARCHENEMY_AUR_RPC_JSON="$T/rpc.json"
# shellcheck disable=SC2016  # dosłowny tekst z install.sh, nie rozwinięcie zmiennej
if grep -qF 'case "$p" in steam|lib32-*)' "$REPO/install/install.sh"; then ok "autotest: wzorzec nazw [multilib] taki sam jak w install.sh [5]"
else fail "autotest: install.sh [5] zmienił wzorzec nazw [multilib] — zsynchronizuj is_multilib_name"; fi
selftest "brak sieci → skip dla AUR" "? skip: brave-bin — AUR RPC niedostępne" ARCHENEMY_AUR_RPC_JSON=offline
out="$(env PATH="$T/bin:$PATH" ARCHENEMY_AUR_RPC_JSON=offline bash "${BASH_SOURCE[0]}" --lists-only "$T/pkg" 2>&1)"
if [[ "$out" == *"✓ AUR:"* ]]; then fail "autotest: bez sieci pojawił się ✓ dla AUR"; else ok "autotest: bez sieci żadnego ✓ dla AUR"; fi

echo "== prawdziwe listy packages/*.txt"
check_lists "${ARCHENEMY_PKG_DIR:-$REPO/packages}"

echo ""
echo "Result: $PASS passed / $FAIL failed / $SKIP skipped"
((FAIL == 0))
