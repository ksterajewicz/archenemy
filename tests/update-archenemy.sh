#!/bin/bash
# =============================================
#   archenemy - tests/update-archenemy.sh
#   Testy regresji aktualizatora (scripts/appbinds/update-archenemy.sh,
#   Super+A → [p]) na PRAWDZIWYM gicie: lokalne repo „origin” (bare) i klon
#   w atrapie $HOME. Bez sieci, bez roota, bez zapisu poza mktemp.
#
#   Powód powstania (audyt 2026-09-23): sprawdzenia `if ! git … | sed …` bez
#   pipefail brały kod wyjścia seda, więc nieudany fetch/pull/stash pop
#   kończył się komunikatem „✓ Zaktualizowano”; a opcja „main” przełączała
#   na gałąź starszą o dziesiątki commitów (sprzed migracji configu na Lua).
#   Każdy scenariusz niżej PADA na kodzie sprzed poprawki.
#   Uruchom: bash tests/update-archenemy.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPD="$REPO/scripts/appbinds/update-archenemy.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# Tożsamość gita tylko dla testu (stash i commity jej wymagają); bez configu globalnego.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"
A="$HOME/archenemy"
g() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# ─── origin: main (stary) ← dev (nowszy o 2 commity) ─────────────────────────
S="$T/seed"
mkdir -p "$S/install"
git init -q -b main "$S"
printf '#!/bin/bash\necho INSTALL-RAN\n' > "$S/install/install.sh"   # celowo 100644
echo v1 > "$S/f.txt"
g "$S" add -A; g "$S" commit -m main-v1
g "$S" checkout -b dev
echo v2 > "$S/f.txt"; g "$S" commit -am dev-v2
echo v3 > "$S/g.txt"; g "$S" add g.txt; g "$S" commit -m dev-v3
git clone -q --bare "$S" "$T/origin.git"

fresh_clone() {   # fresh_clone <gałąź>
    rm -rf "$A"; mkdir -p "$HOME"
    git clone -q -b "$1" "$T/origin.git" "$A"
}
upstream_commit() {   # upstream_commit <gałąź> <plik> <treść> — nowy commit na origin
    local w="$T/w"
    rm -rf "$w"; git clone -q -b "$1" "$T/origin.git" "$w"
    echo "$3" > "$w/$2"; g "$w" add -A; g "$w" commit -m "up-$3"; g "$w" push origin "$1"
}
run_upd() {   # run_upd <klawisze> — stdin: wybór gałęzi, odpowiedzi, Entery
    printf '%b' "$1" | bash "$UPD" 2>&1
}
head_of() { git -C "$A" rev-parse "$1" 2>/dev/null; }

echo "== aktualizacja szczęśliwa"
fresh_clone dev
upstream_commit dev f.txt v4
out=$(run_upd '1n\n')
check "HEAD = origin/dev po aktualizacji"      '[[ "$(head_of HEAD)" == "$(head_of origin/dev)" ]]'
check "komunikat sukcesu"                      '[[ "$out" == *"✓ Zaktualizowano"* ]]'

echo "== N1: pull odrzucony (lokalny commit + nowy upstream = brak fast-forward)"
fresh_clone dev
echo lokalne > "$A/h.txt"; g "$A" add h.txt; g "$A" commit -m lokalny
upstream_commit dev f.txt v5
before=$(head_of HEAD)
out=$(run_upd '1\n\n')
check "brak fałszywego „✓ Zaktualizowano”"     '[[ "$out" != *"✓ Zaktualizowano"* ]]'
check "jawny błąd pulla"                       '[[ "$out" == *"✗ Pull"* ]]'
check "HEAD bez zmian"                         '[[ "$(head_of HEAD)" == "$before" ]]'

echo "== N1: konflikt przy przywracaniu schowka"
fresh_clone dev
echo lokalna-wersja > "$A/f.txt"
upstream_commit dev f.txt upstream-wersja
out=$(run_upd '1yn\n\n')
check "brak fałszywego „przywrócone”"          '[[ "$out" != *"✓ Lokalne zmiany przywrócone"* ]]'
check "jawny błąd przywracania"                '[[ "$out" == *"✗ Nie udało się przywrócić"* ]]'
check "zmiany dalej w schowku (nic nie ginie)" '[[ -n "$(git -C "$A" stash list)" ]]'

echo "== N1: fetch nieudany (origin nieosiągalny)"
fresh_clone dev
g "$A" remote set-url origin "$T/nie-ma-takiego.git"
before=$(head_of HEAD)
out=$(run_upd '1\n\n')
check "jawny błąd fetcha"                      '[[ "$out" == *"✗ Fetch"* ]]'
check "brak fałszywego „✓ Zaktualizowano”"     '[[ "$out" != *"✓ Zaktualizowano"* ]]'
check "HEAD bez zmian"                         '[[ "$(head_of HEAD)" == "$before" ]]'

echo "== N3: gałąź starsza niż obecny stan (main za dev) — wybór zostaje, ale z potwierdzeniem"
fresh_clone dev
before=$(head_of HEAD)
out=$(run_upd '2\n\n')
check "ostrzeżenie o cofnięciu"                '[[ "$out" == *"jest starsza niż to, co masz teraz"* ]]'
check "domyślnie (Enter) zostaje na dev"       '[[ "$(git -C "$A" branch --show-current)" == dev && "$(head_of HEAD)" == "$before" ]]'
check "brak „✓ Zaktualizowano”"                '[[ "$out" != *"✓ Zaktualizowano"* ]]'
fresh_clone dev
out=$(run_upd '2yn\n')
check "potwierdzone „y” → przełączone na main" '[[ "$(git -C "$A" branch --show-current)" == main && "$(head_of HEAD)" == "$(head_of origin/main)" ]]'

echo "== N3: przełączenie do przodu (main → dev) dalej działa"
fresh_clone main
out=$(run_upd '1n\n')
check "na dev = origin/dev"                    '[[ "$(git -C "$A" branch --show-current)" == dev && "$(head_of HEAD)" == "$(head_of origin/dev)" ]]'

echo "== lokalne commity ponad origin: ostrzeżenie zamiast „✓”"
fresh_clone dev
echo lokalne > "$A/h.txt"; g "$A" add h.txt; g "$A" commit -m lokalny
out=$(run_upd '1n\n')
check "ostrzeżenie o lokalnych commitach"      '[[ "$out" == *"lokalnych commitów"* ]]'
check "brak „✓ Zaktualizowano”"                '[[ "$out" != *"✓ Zaktualizowano"* ]]'

echo "== install.sh bez prawa wykonywania nadal się uruchamia"
fresh_clone dev
check "install.sh w klonie jest 100644"        '[[ ! -x "$A/install/install.sh" ]]'
out=$(run_upd '1y\n')
check "instalator uruchomiony"                 '[[ "$out" == *INSTALL-RAN* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
