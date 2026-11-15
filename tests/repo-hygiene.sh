#!/bin/bash
# =============================================
#   archenemy - tests/repo-hygiene.sh
#   Higiena repozytorium: rzeczy, które same z siebie brudzą working tree
#   użytkownika i blokują `git pull` (update-archenemy.sh, Super+A → [u]).
#   Bez roota, bez zapisu poza mktemp — czyta indeks gita i pliki śledzone;
#   jedynie bloki lua5.4 testów wykonuje (w mktemp, z PATH bez lua5.4).
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
# Sam tekst skip w pliku nie wystarcza (przegląd P3-4: `false && skip …`
# przechodził), więc strażnik WYKONUJE każdy blok `if command -v lua5.4 … fi`
# każdego takiego pakietu, osobno, z PATH bez lua5.4 (dowiązania w mktemp) razem
# z jego skip() i ostatnim echo (wiersz wyniku — jedyny, który pokazuje run-all):
# blok ma wywołać skip, a wiersz wyniku pokazać 1 pominięcie (scalenie
# 2026-11-15: drugi blok bez skip przechodził, bo czytany był tylko pierwszy;
# warunek wcięty albo w innej formie = ✗, bo nie da się go wyciąć). Całych pakietów nie
# uruchamia (trzy to ok. 4 min na 1 rdzeniu pod obciążeniem). Gałąź z lua5.4
# nie biegnie; gdyby warunek się zepsuł, `bash -u` przerywa ją na pierwszej
# nieustawionej zmiennej, a HOME leży w mktemp.
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1
NOLUA="$T/nolua"; mkdir -p "$NOLUA"
declare -A seen=(); links=()
IFS=: read -ra path_dirs <<< "$PATH"
for d in "${path_dirs[@]}"; do
    [[ -n "$d" && -d "$d" ]] || continue
    for p in "$d"/*; do
        n="${p##*/}"
        [[ -n "${seen[$n]:-}" || "$n" == lua5.4 || -d "$p" || ! -x "$p" ]] && continue
        seen[$n]=1; links+=("$p")
    done
done
((${#links[@]})) && ln -s -t "$NOLUA" -- "${links[@]}"
# lua_skip_ok <plik> — KAŻDY blok lua5.4 (od `if command -v lua5.4 >/dev/null`
# na początku wiersza do `fi` na początku wiersza), wykonany osobno bez lua5.4,
# woła skip, a ostatnie echo pliku (wiersz wyniku) pokazuje 1 pominięcie.
# Każde niekomentowane wystąpienie warunku musi być takim blokiem: wcięty blok
# albo inna forma warunku to ✗, nie cichy brak sprawdzenia. Powód porażki
# w LUA_WHY, liczba sprawdzonych bloków dopisywana do LUA_BLOCKS.
LUA_BLOCKS=0
lua_skip_ok() {
    local blk def res out n_blk n_all k
    LUA_WHY=""
    def="$(grep -m1 -E '^skip\(\) *\{' "$1")"
    res="$(grep -E '^echo ' "$1" | tail -n 1)"
    [[ -n "$def" ]] || { LUA_WHY="brak skip()"; return 1; }
    [[ -n "$res" ]] || { LUA_WHY="brak wiersza wyniku"; return 1; }
    n_blk="$(grep -c '^if command -v lua5\.4 >/dev/null' "$1")"
    n_all="$(grep -vE '^[[:space:]]*#' "$1" | grep -cF 'command -v lua5.4 >/dev/null')"
    (( n_blk > 0 && n_blk == n_all )) || { LUA_WHY="blok niewycinalny ($n_blk z $n_all)"; return 1; }
    for ((k = 1; k <= n_blk; k++)); do
        blk="$(awk -v k="$k" '/^if command -v lua5\.4 >\/dev\/null/ {on = (++i == k)} on {print} on && /^fi$/ {exit}' "$1")"
        out="$(cd "$T" && env -i HOME="$HOME" PATH="$NOLUA" LC_ALL=C.UTF-8 \
            bash -u -c "PASS=0 FAIL=0 SKIP=0"$'\n'"$def"$'\n'"$blk"$'\n'"$res" 2>&1)"
        [[ "$out" == *'skip: lua5.4 is not installed'* && "$(tail -n 1 <<< "$out")" =~ (skipped:\ 1|\ 1\ skip)$ ]] \
            || { LUA_WHY="blok $k z $n_blk bez skip"; return 1; }
    done
    LUA_BLOCKS=$((LUA_BLOCKS + n_blk))
}
mapfile -t lua_tests < <(git -C "$REPO" grep -lF 'command -v lua5.4 >/dev/null' -- 'tests/*.sh' ':!tests/repo-hygiene.sh')
bad=""
for f in "${lua_tests[@]}"; do
    lua_skip_ok "$REPO/$f" || bad+=" $f ($LUA_WHY)"
done
if [[ -z "$bad" ]]; then ok "${#lua_tests[@]} pakiety z lua5.4 ($LUA_BLOCKS bloków): bez lua5.4 każdy blok woła skip, wiersz wyniku liczy pominięcie"
else fail "bez skip przy braku lua5.4 (blok wykonany z PATH bez lua5.4):$bad"; fi
# Kontrola strażnika: gałąź bez lua5.4, która nie woła skip (mutacja z przeglądu).
sed 's/^\( *\)skip "lua5.4 is not installed/\1false \&\& skip "lua5.4 is not installed/' \
    "$REPO/tests/machine-layer.sh" > "$T/mutant.sh"
if ! cmp -s "$REPO/tests/machine-layer.sh" "$T/mutant.sh" && ! lua_skip_ok "$T/mutant.sh"; then
    ok "strażnik łapie gałąź bez lua5.4, która nie woła skip (false && skip)"
else
    fail "strażnik przepuszcza gałąź bez lua5.4 bez skip (albo machine-layer.sh nie ma już skip lua5.4)"
fi
# Kontrola strażnika na atrapach pakietów (scalenie 2026-11-15: tui dopisało
# w machine-layer.sh drugi blok lua5.4 bez skip, a strażnik czytał tylko
# pierwszy): każdy blok osobno, plik bez skip() i blok, którego nie da się
# wyciąć (wcięty), to ✗; poprawny pakiet z dwoma blokami to ✓.
# Atrapy to tekst pakietów: $PASS, $SKIP i $1 mają trafić do plików dosłownie.
# shellcheck disable=SC2016
{
    SK='skip "lua5.4 is not installed (atrapa)"'
    DEF='skip() { SKIP=$((SKIP + 1)); echo "  ? skip: $1"; }'
    mk_fx() {   # mk_fx <plik> <gałąź else bloku 1> <gałąź else bloku 2> <definicja skip()>
        printf '%s\n' '#!/bin/bash' 'PASS=0; FAIL=0; SKIP=0' "$4" \
            'if command -v lua5.4 >/dev/null 2>&1; then' '    PASS=$((PASS + 1))' 'else' "    $2" 'fi' \
            'echo "== druga sekcja"' \
            'if command -v lua5.4 >/dev/null 2>&1; then' '    PASS=$((PASS + 1))' 'else' "    $3" 'fi' \
            'echo "Wynik: $PASS ✓ / $FAIL ✗ / $SKIP skip"' > "$1"
    }
    mk_fx "$T/fx-ok.sh" "$SK" "$SK" "$DEF"
    mk_fx "$T/fx-second.sh" "$SK" 'echo "  - pominięte"' "$DEF"
    mk_fx "$T/fx-nodef.sh" "$SK" "$SK" ''
    printf '%s\n' '#!/bin/bash' 'PASS=0; FAIL=0; SKIP=0' "$DEF" 'run() {' \
        '    if command -v lua5.4 >/dev/null 2>&1; then :; else' "        $SK" '    fi' '}' 'run' \
        'echo "Wynik: $PASS ✓ / $FAIL ✗ / $SKIP skip"' > "$T/fx-indent.sh"
}
fx_bad=""
lua_skip_ok "$T/fx-ok.sh" || fx_bad+=" poprawny-odrzucony"
lua_skip_ok "$T/fx-second.sh" && fx_bad+=" drugi-blok-bez-skip"
lua_skip_ok "$T/fx-nodef.sh" && fx_bad+=" bez-skip()"
lua_skip_ok "$T/fx-indent.sh" && fx_bad+=" wcięty-blok"
if [[ -z "$fx_bad" ]]; then ok "strażnik na atrapach: każdy blok osobno, bez skip() i wcięty blok = ✗, poprawny = ✓"
else fail "strażnik na atrapach przepuszcza albo odrzuca źle:$fx_bad"; fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
