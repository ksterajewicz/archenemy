#!/usr/bin/env bash
# =============================================
#   archenemy - tests/shellcheck.sh
#   Uruchamia `shellcheck -x -S info -e SC1091` na każdym śledzonym skrypcie: *.sh oraz
#   atrapach tests/mock/* (K9 z audytu bezpieczeństwa 2026-11-14 — ręczny
#   bieg znalazł 7× SC2086, niecytowane ścieżki pod sudo w instalatorze GPU).
#   SC1091 wyłączone: `source` ze ścieżek liczonych w czasie biegu
#   ($ARCHENEMY_DIR/…) i tak nie jest do śledzenia statycznie.
#   Brak shellchecka = „skip”, nigdy ✓ (pakiet nie jest na listach archenemy —
#   to narzędzie dewelopera; CI w .github/workflows/tests.yml go instaluje).
#   Zepsuty albo zabity shellcheck (np. rc 127 po częściowej aktualizacji
#   bibliotek Haskella) = ✗: każdy wiersz wyjścia spoza formatu gcc i kod
#   xargs spoza {0, 123} to porażka. Pilnuje autotest na atrapie (na starcie).
#   Pliki idą równolegle (xargs -P): całe repo jednym procesem to minuty.
#   Uruchom: bash tests/shellcheck.sh   (kod 0 = zero NOWYCH znalezisk albo skip)
#            bash tests/shellcheck.sh --selftest   (sam autotest, kilka sekund)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── autotest na atrapie shellchecka (atrapa repo w mktemp, bez prawdziwego narzędzia) ──
# Kopia tego skryptu biegnie w atrapie repo z ARCHENEMY_SHELLCHECK_NESTED=1
# (w kopii autotest się nie uruchamia — bez rekurencji). Atrapa drukuje
# prawdziwy format gcc: poziomy info i style to „note:”, nie „info:”/„style:”.
selftest() (
    # shellcheck source=tests/lib/environment.sh
    source "$REPO/tests/lib/environment.sh"
    T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
    test_environment_init "$T" || exit 1
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    M="$T/repo"; mkdir -p "$M/tests" "$T/bin" "$T/fx/ok" "$T/fx/new" "$T/fx/upd"
    cp "${BASH_SOURCE[0]}" "$M/tests/shellcheck.sh"
    for f in a b c; do printf '#!/usr/bin/env bash\necho %s\n' "$f" > "$M/$f.sh"; done
    # Baza z komentarzami: linia „#…” i komentarz po dwóch polach (nie zmieniają limitu).
    printf '%s\n' '# known findings' 'a.sh SC2034  # read by eval' 'a.sh SC2034' 'b.sh SC2012' > "$T/base"
    cp "$T/base" "$M/tests/shellcheck.baseline"
    git -C "$M" init -q && git -C "$M" add a.sh b.sh c.sh tests || exit 1
    w='warning: x appears unused. Verify use (or export if used externally). [SC2034]'
    printf 'a.sh:2:1: %s\na.sh:3:1: %s\n' "$w" "$w" > "$T/fx/ok/a.sh"
    echo 'b.sh:2:6: note: Use find instead of ls to better handle non-alphanumeric filenames. [SC2012]' > "$T/fx/ok/b.sh"
    cp "$T/fx/ok/"* "$T/fx/new/"
    echo 'c.sh:2:6: note: Double quote to prevent globbing and word splitting. [SC2086]' > "$T/fx/new/c.sh"
    # upd: jedno SC2034 i SC2012 naprawione, nowe SC2086 w c.sh.
    printf 'a.sh:2:1: %s\n' "$w" > "$T/fx/upd/a.sh"; cp "$T/fx/new/c.sh" "$T/fx/upd/"
    cat > "$T/bin/shellcheck" <<'MOCK'
#!/usr/bin/env bash
[[ -n "${MOCK_SC_ARGS:-}" ]] && printf '%s\n' "$*" >> "$MOCK_SC_ARGS"
case "${MOCK_SC:-}" in
    broken) echo "shellcheck: error while loading shared libraries: libHSaeson-2.2.3.0-ghc9.6.6.so: cannot open shared object file: No such file or directory" >&2; exit 127 ;;
    silent) exit 127 ;;
    killed) kill -KILL $$ ;;
esac
rc=0
for f in "$@"; do
    [[ -f "$MOCK_SC_DIR/$f" ]] && { cat "$MOCK_SC_DIR/$f"; rc=1; }
    # partial: jeden plik pada jak prawdziwy shellcheck pod LANG=C na komunikacie
    # z „ż” (wiersz spoza formatu gcc, znalezisko zgubione, rc 2), reszta działa.
    [[ "${MOCK_SC:-}" == partial && "$f" == c.sh ]] && { echo "c.sh: <stdout>: commitBuffer: invalid argument (cannot encode character '\\380')" >&2; rc=2; }
done
exit "$rc"
MOCK
    chmod +x "$T/bin/shellcheck"
    fails=0
    # expect <opis> <kod> <fragment> <argument skryptu albo ""> <zmienne env…>
    expect() {
        local desc="$1" want_rc="$2" want="$3" arg="$4" out rc; shift 4
        out="$(env PATH="$T/bin:$PATH" ARCHENEMY_SHELLCHECK_NESTED=1 "$@" bash "$M/tests/shellcheck.sh" ${arg:+"$arg"} 2>&1)"; rc=$?
        if [[ $rc == "$want_rc" && "$out" == *"$want"* ]] && { [[ $want_rc == 0 ]] || [[ "$out" != *✓* ]]; }; then
            echo "  ✓ autotest: $desc"
        else
            fails=$((fails + 1)); echo "  ✗ autotest: $desc — rc=$rc, expected $want_rc and: $want"
            sed 's/^/      | /' <<< "$out" | tail -n 6
        fi
    }
    expect "known findings (note:, warning:) → ✓" 0 "no new findings (3 known" "" MOCK_SC_DIR="$T/fx/ok"
    expect "new SC2086 → ✗" 1 "✗ c.sh:2:6: note:" "" MOCK_SC_DIR="$T/fx/new"
    expect "shellcheck without its libraries (rc 127) → ✗, never ✓" 1 "error while loading shared libraries" "" MOCK_SC=broken MOCK_SC_DIR="$T/fx/ok"
    expect "silent rc 127 → ✗" 1 "shellcheck did not finish cleanly" "" MOCK_SC=silent MOCK_SC_DIR="$T/fx/ok"
    expect "shellcheck killed (SIGKILL, xargs 125) → ✗" 1 "xargs exit 125" "" MOCK_SC=killed MOCK_SC_DIR="$T/fx/ok"
    # Tu xargs daje 123 przy poprawnych znaleziskach z a.sh i b.sh — łapie to
    # TYLKO sprawdzanie wierszy spoza formatu gcc (pozostałe przypadki padają na
    # wszystkich plikach naraz i łapie je też warunek „123 bez znaleziska”).
    expect "one file breaks (line outside gcc format), others report → ✗, never ✓" 1 "commitBuffer: invalid argument" "" MOCK_SC=partial MOCK_SC_DIR="$T/fx/ok"
    # --update-baseline tylko usuwa (R1 C5): naprawione wypadają, nowe nie wchodzą.
    expect "broken shellcheck with --update-baseline → ✗" 1 "did not finish cleanly" --update-baseline MOCK_SC=broken MOCK_SC_DIR="$T/fx/ok"
    if cmp -s "$T/base" "$M/tests/shellcheck.baseline"; then echo "  ✓ autotest: broken shellcheck leaves the baseline untouched"
    else fails=$((fails + 1)); echo "  ✗ autotest: broken shellcheck changed the baseline"; fi
    expect "--update-baseline with a new finding → ✗, not added" 1 "not added to the baseline" --update-baseline MOCK_SC_DIR="$T/fx/upd"
    want=$'# known findings\na.sh SC2034  # read by eval'
    if [[ "$(cat "$M/tests/shellcheck.baseline")" == "$want" ]]; then echo "  ✓ autotest: --update-baseline removed only fixed entries, kept comments"
    else fails=$((fails + 1)); echo "  ✗ autotest: baseline after --update-baseline:"; sed 's/^/      | /' "$M/tests/shellcheck.baseline"; fi
    expect "new finding still ✗ after --update-baseline" 1 "✗ c.sh:2:6: note:" "" MOCK_SC_DIR="$T/fx/upd"
    # Ręcznie dopisany wyjątek w edytorze bez końcowego „\n”: ostatni wpis też się liczy.
    printf 'a.sh SC2034\na.sh SC2034\nb.sh SC2012' > "$M/tests/shellcheck.baseline"
    expect "baseline without a final newline: last entry still counts" 0 "no new findings (3 known" "" MOCK_SC_DIR="$T/fx/ok"
    # Każde wywołanie z -x: bez niego `source` działa tylko w obrębie jednej
    # partii xargs -n 4 i wynik zależy od kolejności plików (scalenie 2026-11-15).
    : > "$T/args"
    env PATH="$T/bin:$PATH" ARCHENEMY_SHELLCHECK_NESTED=1 MOCK_SC_DIR="$T/fx/ok" MOCK_SC_ARGS="$T/args" \
        bash "$M/tests/shellcheck.sh" >/dev/null 2>&1
    if [[ -s "$T/args" ]] && ! grep -qvE '(^| )-x( |$)' "$T/args"; then
        echo "  ✓ autotest: every shellcheck call has -x (sources followed across xargs batches)"
    else fails=$((fails + 1)); echo "  ✗ autotest: shellcheck called without -x:"; sed 's/^/      | /' "$T/args"; fi
    exit "$fails"
)
SELF_FAIL=0
if [[ -z "${ARCHENEMY_SHELLCHECK_NESTED:-}" ]]; then
    echo "== autotest (fake shellcheck in a temporary repo)"
    selftest; SELF_FAIL=$?
    if ((SELF_FAIL)); then echo "Result: autotest failed ($SELF_FAIL)"; exit 1; fi
    if [[ "${1:-}" == --selftest ]]; then echo "Result: autotest passed"; exit 0; fi
fi

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "  ? skip: shellcheck is not installed (sudo pacman -S shellcheck)"
    echo "Result: skipped (no shellcheck)"
    exit 0
fi

mapfile -d '' -t files < <(git -C "$REPO" ls-files -z -- '*.sh' 'tests/mock/*')
((${#files[@]})) || { echo "  ✗ no tracked scripts found"; exit 1; }

# Wyjście gcc: plik:linia:kolumna: poziom: opis [SCxxxx] — jedno znalezisko na linię;
# poziomy to error, warning i note (info i style drukują się jako „note”).
# -x: shellcheck bez niego idzie za `source` tylko wtedy, gdy plik źródłowy jest
# w TYM SAMYM wywołaniu, a xargs -n 4 tnie listę na partie — wynik zależał od
# tego, czy biblioteka trafiła do partii pliku (scalenie 2026-11-15: nowy
# scripts/lib/runtime-dir.sh przesunął listę o 1 i rofi_clipboard.sh dostał
# fałszywe SC2034 THUMB_DIR, którego używa lib/rofi-preview.sh). Ścieżki
# z dyrektyw `# shellcheck source=…` są względem korzenia repo (cd "$REPO").
out="$(cd "$REPO" && printf '%s\0' "${files[@]}" \
    | xargs -0 -n 4 -P "$(nproc 2>/dev/null || echo 2)" shellcheck -x -S info -e SC1091 -f gcc 2>&1)"
xrc=$?   # kod xargs (pipefail): 0 = czysto, 123 = któryś bieg zwrócił 1–125

# Zepsuty albo zabity shellcheck nie może dać ✓ (R1 C1): błąd ładowania bibliotek
# to rc 127, którego xargs nie odróżnia od zwykłych znalezisk (oba → 123), więc
# każdy wiersz spoza formatu gcc = porażka; kod spoza {0, 123} (124: rc 255,
# 125: zabity sygnałem — xargs przerywa i reszty plików nie sprawdza) też;
# 123 bez ani jednego znaleziska znaczy błąd, który nic nie wypisał.
GCC_RE='^[^:]+:[0-9]+:[0-9]+: (error|warning|note): .*\[SC[0-9]+\]$'
bad=() valid=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ $GCC_RE ]]; then valid=$((valid + 1)); else bad+=("$line"); fi
done <<< "$out"
if ((${#bad[@]})) || [[ $xrc != 0 && $xrc != 123 ]] || [[ $xrc == 123 && $valid == 0 ]]; then
    echo "  ✗ shellcheck did not finish cleanly (xargs exit $xrc) — result not trusted"
    for line in "${bad[@]:0:5}"; do echo "      $line"; done
    ((${#bad[@]} > 5)) && echo "      … $((${#bad[@]} - 5)) more line(s)"
    echo "Result: shellcheck failed (xargs exit $xrc, ${#bad[@]} unparsable line(s))"
    exit 1
fi

# Baza znanych znalezisk (tests/shellcheck.baseline: „plik SCxxxx”, jedno na
# linię, bez numerów linii — te się przesuwają; linie „#…” i puste są pomijane,
# a po dwóch polach może stać komentarz). Stan z 2026-11-14 to 35 dawnych
# znalezisk (głównie SC2016/SC2034 w testach z eval); test pada tylko na
# NOWYCH — każde ponad liczbę z bazy dla pary plik+kod.
# Baza tylko maleje (R1 C5): `bash tests/shellcheck.sh --update-baseline` usuwa
# naprawione wpisy (część wspólna starej bazy i bieżących znalezisk, krotności
# i komentarze zostają), a nowych NIGDY nie dopisuje — te naprawiaj w kodzie;
# świadomy wyjątek dopisuje się do bazy ręcznie, z komentarzem. Bieg z zepsutym
# narzędziem kończy się wyżej (✗), więc nie wyczyści bazy.
BASE="$REPO/tests/shellcheck.baseline"
keys() { sed -nE 's/^([^:]+):[0-9]+:[0-9]+: .*\[(SC[0-9]+)\]$/\1 \2/p' | sort; }
update=0
if [[ "${1:-}" == --update-baseline ]]; then
    update=1
    declare -A cur=()
    while read -r f c; do
        [[ -n "${f:-}" ]] && cur["$f $c"]=$(( ${cur["$f $c"]:-0} + 1 ))
    done < <(keys <<< "$out")
    kept=() removed=0
    if [[ -f "$BASE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            read -r f c _ <<< "$line"
            if [[ -z "${f:-}" || "$f" == \#* ]]; then kept+=("$line"); continue; fi
            if (( ${cur["$f $c"]:-0} > 0 )); then
                cur["$f $c"]=$(( ${cur["$f $c"]} - 1 )); kept+=("$line")
            else
                removed=$((removed + 1))
            fi
        done < "$BASE"
    fi
    if ((${#kept[@]})); then printf '%s\n' "${kept[@]}" > "$BASE"; else : > "$BASE"; fi
    echo "baseline: $removed fixed finding(s) removed; new findings are never added"
fi
declare -A allowed=()
if [[ -f "$BASE" ]]; then
    # `|| [[ -n … ]]`: ostatni wpis bez końcowego „\n” (ręczna edycja) też się liczy.
    while read -r f c _ || [[ -n "${f:-}" ]]; do
        [[ -z "${f:-}" || "$f" == \#* ]] && continue
        allowed["$f $c"]=$(( ${allowed["$f $c"]:-0} + 1 ))
    done < "$BASE"
fi
new=0 known=0
while read -r n f c; do
    [[ -n "${f:-}" ]] || continue
    a=${allowed["$f $c"]:-0}
    if (( n > a )); then
        new=$((new + n - a))
        grep -F "$f:" <<< "$out" | grep -F "[$c]" | sed 's/^/  ✗ /'
    fi
    known=$((known + (n < a ? n : a)))
done < <(keys <<< "$out" | uniq -c)
if (( new == 0 )); then
    echo "  ✓ ${#files[@]} scripts: no new findings ($known known in tests/shellcheck.baseline)"
    echo "Result: ${#files[@]} files / 0 new / $known known"
    exit 0
fi
((update)) && echo "  $new new finding(s) not added to the baseline."
echo "  Fix new findings in the code. A deliberate exception goes into"
echo "  tests/shellcheck.baseline by hand (one 'file SCxxxx' line, with a # comment)."
echo "Result: ${#files[@]} files / $new new findings / $known known"
exit 1
