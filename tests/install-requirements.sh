#!/bin/bash
# =============================================
#   archenemy - tests/install-requirements.sh
#   Krok [5] install.sh (wycinek „CHECK REQUIREMENTS”) na atrapie pacmana
#   z provides: pakiet jest zainstalowany tylko pod DOKŁADNIE swoją nazwą.
#   I5 z przeglądu 2026-11-15: `pacman -Qi swayosd` znajdował swayosd-git
#   (provides=swayosd), więc [5] pisało ✓, a extra/swayosd nigdy nie trafiał
#   do instalacji. Atrapa sudo tylko loguje; bez roota, bez sieci.
#   Uruchom: bash tests/install-requirements.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval)
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

S=$(grep -n '^# ─── 5. CHECK REQUIREMENTS' "$INST" | cut -d: -f1)
E=$(grep -n '^# ─── 6. DEVICE DETECTION' "$INST" | cut -d: -f1)
sed -n "${S},$((E-1))p" "$INST" > "$T/step5.sh"

mkdir -p "$T/bin" "$T/sys"
# Jak prawdziwy pacman (`pacman -Qq sh` → bash): -Qi/-Qq <nazwa> znajduje
# pakiet o tej nazwie ALBO pakiet, który ją dostarcza. Baza: „nazwa właściciel”.
cat > "$T/bin/pacman" <<'EOF'
#!/bin/bash
case "$1" in
    -Qi|-Qq)
        while read -r name owner; do
            [[ "$name" == "$2" ]] || continue
            if [[ "$1" == -Qq ]]; then echo "$owner"; else echo "Name            : $owner"; fi
            exit 0
        done < "$MOCK_PKGDB"
        echo "error: package '$2' was not found" >&2
        exit 1 ;;
esac
exit 1
EOF
printf '#!/bin/bash\necho "$*" >> "%s/sudo.log"\n' "$T" > "$T/bin/sudo"
chmod +x "$T/bin"/*
# Okrojony PATH: bez prawdziwego yay (gałąź AUR kończy się „yay not available”).
for c in bash cat; do ln -s "$(command -v "$c")" "$T/sys/$c"; done

run_step5() {   # run_step5 <wymagane pacman> <wymagane AUR> <baza „nazwa właściciel”…>
    tr ' ' '\n' <<< "$1" > "$T/req-pacman.txt"
    tr ' ' '\n' <<< "$2" > "$T/req-aur.txt"
    shift 2
    printf '%s\n' "$@" > "$T/pkgdb"
    rm -f "$T/sudo.log"
    out="$(env PATH="$T/bin:$T/sys" MOCK_PKGDB="$T/pkgdb" ARCHENEMY_DIR="$T/none" \
        PACMAN_REQ="$T/req-pacman.txt" AUR_REQ="$T/req-aur.txt" \
        RED= GREEN= YELLOW= CYAN= NC= \
        bash -c 'source "$1"; printf "SKIPPED: %s\n" "${SUMMARY_SKIPPED[@]}"' _ "$T/step5.sh" < /dev/null 2>&1)"
    sudo_log="$(cat "$T/sudo.log" 2>/dev/null)"
}

echo "== [5]: dostawca (provides) to nie ten pakiet"
run_step5 "hyprland swayosd waybar" "brave-bin" \
    "hyprland hyprland" "swayosd swayosd-git" "brave-bin brave-bin"
check "pakiet pod własną nazwą → ✓"                '[[ "$out" == *"✓ hyprland"* && "$out" != *"missing: hyprland"* ]]'
check "swayosd od swayosd-git → ✗ z nazwą dostawcy" '[[ "$out" == *"✗ missing: swayosd (installed: swayosd-git, which only provides it)"* ]]'
check "brak pakietu → ✗ missing"                    '[[ "$out" == *"✗ missing: waybar"* ]]'
check "swayosd trafia do transakcji pacmana"        '[[ "$sudo_log" == "pacman -S --needed swayosd waybar" ]]'
check "AUR pod własną nazwą → ✓, bez yay"           '[[ "$out" == *"✓ brave-bin"* && "$out" != *"SKIPPED: REQUIRED AUR"* ]]'

echo "== [5]: lista AUR tak samo"
run_step5 "hyprland" "brave-bin" "hyprland hyprland" "brave-bin TEST-brave-provider"
check "brave-bin od innego pakietu → ✗ missing"     '[[ "$out" == *"✗ missing: brave-bin (installed: TEST-brave-provider"* ]]'
check "brakujący AUR w podsumowaniu (bez yay)"      '[[ "$out" == *"SKIPPED: REQUIRED AUR packages skipped (no yay): brave-bin"* ]]'
check "komplet pacmana → brak transakcji"           '[[ -z "$sudo_log" ]]'

echo "== [5]: wszystko pod własnymi nazwami"
run_step5 "hyprland swayosd" "brave-bin" "hyprland hyprland" "swayosd swayosd" "brave-bin brave-bin"
check "zero ✗ i zero wywołań sudo"                  '[[ "$out" != *"✗"* && -z "$sudo_log" ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
