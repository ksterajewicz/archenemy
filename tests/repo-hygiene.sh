#!/bin/bash
# =============================================
#   archenemy - tests/repo-hygiene.sh
#   Higiena repozytorium: rzeczy, które same z siebie brudzą working tree
#   użytkownika i blokują `git pull` (update-archenemy.sh, Super+A → [u]).
#   Bez roota, bez zapisu poza mktemp — czyta tylko indeks gita.
#
#   Powód powstania (audyt 2026-09-23): install.sh stracił bit wykonywania
#   w indeksie (commit 7f54012), a trzy biblioteki w scripts/ nigdy go nie
#   miały; README każe `chmod +x`, a install.sh robi `chmod +x` na wszystkich
#   scripts/**/*.sh — każda instalacja zmieniała tryb plików śledzonych,
#   git widział modyfikację i pull odmawiał (laptop 2026-09-17:
#   `M install/install.sh`, `M …/gen-workspaces.sh`, `M …/timer-state.sh`).
#   Uruchom: bash tests/repo-hygiene.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "== skrypty .sh w indeksie gita mają bit wykonywania (100755)"
bad=$(git -C "$REPO" ls-files -s -- '*.sh' | awk '$1 != "100755" {print $4}')
if [[ -z "$bad" ]]; then
    ok "wszystkie *.sh = 100755 (chmod +x z README/install.sh nie brudzi drzewa)"
else
    while IFS= read -r f; do fail "$f bez bitu wykonywania — git update-index --chmod=+x $f"; done <<< "$bad"
fi

echo "== atrapy w tests/mock są wykonywalne"
bad=$(git -C "$REPO" ls-files -s -- 'tests/mock/*' | awk '$1 != "100755" {print $4}')
if [[ -z "$bad" ]]; then ok "tests/mock/* = 100755"; else fail "bez bitu: $bad"; fi

echo "== hyprctl dispatch w składni Lua"
# Config w Lua: `hyprctl dispatch X` = hl.dispatch(X). Stara forma
# (`dispatch workspace 2`) to błąd składni Lua, a skrypty zwykle tłumią wyjście,
# więc akcja po prostu się nie dzieje — tak guard i scroll waybara milczały
# od migracji na Lua do audytu pod Hyprlanda 0.57.
bad=$(git -C "$REPO" grep -nE 'hyprctl dispatch +[a-z]+ ' -- 'scripts/*' 'install/*' 'rices/*' 'config/*' ':!*.bak' || true)
if [[ -z "$bad" ]]; then ok "brak hyprctl dispatch w starej składni"; else fail "stara składnia: $bad"; fi

echo "== angielskie komunikaty instalatorów"
# Zgrubny strażnik pojedynczych linii: komentarze kodu są dozwolone,
# ale wypisywane opisy plików i odkładane podsumowania też są tekstem użytkownika.
# grep -F rozpoznaje pełne ciągi bajtów, niezależnie od locale awk.
user_message_lines() {
    awk '
        /^[[:space:]]*#/ { next }
        /(echo|printf|print[(]|read[[:space:]]+-[[:alpha:]]*p|die|warn|log|SUMMARY_(DONE|SKIPPED).*\+=|UFW_FAIL=|regenerate_bootloader)/ {
            print FILENAME ":" FNR ":" $0
        }
    ' "$@"
}
polish_text() {
    grep -F -e ą -e ć -e ę -e ł -e ń -e ó -e ś -e ź -e ż \
        -e Ą -e Ć -e Ę -e Ł -e Ń -e Ó -e Ś -e Ź -e Ż
}
mapfile -t generators < <(git -C "$REPO" ls-files 'scripts/**/gen-*.sh')
files=("$REPO"/install/*.sh "$REPO"/install/lib/*.sh "$REPO/scripts/archenemy-doctor.sh")
for f in "${generators[@]}"; do files+=("$REPO/$f"); done
bad=$(user_message_lines "${files[@]}" | polish_text || true)
if [[ -z "$bad" ]]; then ok "brak polskich liter w komunikatach instalatorów i generatorów"; else fail "polski tekst użytkownika: $bad"; fi
if printf '%s\n' 'echo "⚠ →"' | LC_ALL=C polish_text >/dev/null; then
    fail "strażnik myli symbole z polskimi literami"
else
    ok "symbole ⚠/→ są dozwolone także przy LC_ALL=C"
fi
if printf '%s\n' 'echo "Zażółć"' | LC_ALL=C polish_text >/dev/null; then
    ok "strażnik rozpoznaje polski tekst także przy LC_ALL=C"
else
    fail "strażnik przepuszcza polski tekst"
fi

echo "== dane maszynowe w plikach śledzonych"
# K14 (audyt bezpieczeństwa 2026-11-14): repo jest publiczne, a nazwa
# interfejsu (MangoHud `network=wlo1` we wszystkich rice'ach) albo ścieżka
# /home/<login> zdradzają maszynę i nie działają u innych. Ogólne
# przykłady (/home/x, /home/user) są dozwolone; "$T/home/…" w testach nie
# pasuje, bo przed /home stoi nazwa zmiennej.
machine_data() {
    grep -E -e '^[^#]*\bnetwork=[[:alnum:]]' -e '(^|[^[:alnum:]_}$])/home/[a-z_][a-z0-9_-]*' \
        | grep -vE '/home/(x|user|username|you)([^a-z0-9_-]|$)'
}
bad=$(git -C "$REPO" grep -nI -e 'network=' -e '/home/' -- . ':!tests/repo-hygiene.sh' ':!wallpapers' | machine_data || true)
if [[ -z "$bad" ]]; then ok "brak nazw interfejsów i /home/<login> w plikach śledzonych"; else fail "dane maszynowe: $bad"; fi
if printf '%s\n' 'network=wlo1' 'x="/home/kst/archenemy"' | machine_data >/dev/null \
   && [[ $(printf '%s\n' 'network=wlo1' 'x="/home/kst/archenemy"' | machine_data | grep -c .) -eq 2 ]]; then
    ok "strażnik łapie network=wlo1 i /home/<login>"
else
    fail "strażnik przepuszcza network=wlo1 albo /home/<login>"
fi
# shellcheck disable=SC2016  # dosłowny "$T" to właśnie badany przykład
if printf '%s\n' 'network' '# np. network=wlo1 w komentarzu' 'HOME="$T/home/archenemy"' 'echo x:x:1:1::/home/x:/bin/zsh' | machine_data >/dev/null; then
    fail "strażnik myli ogólne przykłady z danymi maszyny"
else
    ok "ogólne przykłady (network, \$T/home, /home/x, komentarz) dozwolone"
fi

echo "== testy wykonania Lua: brak lua5.4 = widoczny skip, nie OK ani cisza"
# R1 C2: CI ma tylko lua 5.5, a bez lua5.4 mouse-settings.sh dopisywał sztuczne
# OK, keyboard-layouts.sh i machine-layer.sh pomijały wykonanie wygenerowanego Lua
# bez śladu. Pakiet, który sprawdza `command -v lua5.4`, ma w gałęzi bez
# interpretera wywołać skip z tym tekstem i liczyć go w wierszu wyniku.
mapfile -t lua_tests < <(git -C "$REPO" grep -lF 'command -v lua5.4 >/dev/null' -- 'tests/*.sh' ':!tests/repo-hygiene.sh')
bad=""
for f in "${lua_tests[@]}"; do
    grep -qF 'skip "lua5.4 is not installed' "$REPO/$f" || bad+=" $f"
done
if [[ -z "$bad" ]]; then ok "${#lua_tests[@]} pakiety z lua5.4 mają skip zamiast OK lub ciszy"
else fail "bez skip przy braku lua5.4:$bad"; fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
