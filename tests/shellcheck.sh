#!/bin/bash
# =============================================
#   archenemy - tests/shellcheck.sh
#   Uruchamia `shellcheck -S info -e SC1091` na każdym śledzonym skrypcie: *.sh oraz
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
    M="$T/repo"; mkdir -p "$M/tests" "$T/bin" "$T/fx/ok" "$T/fx/new"
    cp "${BASH_SOURCE[0]}" "$M/tests/shellcheck.sh"
    for f in a b c; do printf '#!/bin/bash\necho %s\n' "$f" > "$M/$f.sh"; done
    printf '%s\n' 'a.sh SC2034' 'a.sh SC2034' 'b.sh SC2012' > "$M/tests/shellcheck.baseline"
    git -C "$M" init -q && git -C "$M" add a.sh b.sh c.sh tests || exit 1
    w='warning: x appears unused. Verify use (or export if used externally). [SC2034]'
    printf 'a.sh:2:1: %s\na.sh:3:1: %s\n' "$w" "$w" > "$T/fx/ok/a.sh"
    echo 'b.sh:2:6: note: Use find instead of ls to better handle non-alphanumeric filenames. [SC2012]' > "$T/fx/ok/b.sh"
    cp "$T/fx/ok/"* "$T/fx/new/"
    echo 'c.sh:2:6: note: Double quote to prevent globbing and word splitting. [SC2086]' > "$T/fx/new/c.sh"
    cat > "$T/bin/shellcheck" <<'MOCK'
#!/bin/bash
case "${MOCK_SC:-}" in
    broken) echo "shellcheck: error while loading shared libraries: libHSaeson-2.2.3.0-ghc9.6.6.so: cannot open shared object file: No such file or directory" >&2; exit 127 ;;
    silent) exit 127 ;;
    killed) kill -KILL $$ ;;
esac
rc=0
for f in "$@"; do [[ -f "$MOCK_SC_DIR/$f" ]] && { cat "$MOCK_SC_DIR/$f"; rc=1; }; done
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
out="$(cd "$REPO" && printf '%s\0' "${files[@]}" \
    | xargs -0 -n 4 -P "$(nproc 2>/dev/null || echo 2)" shellcheck -S info -e SC1091 -f gcc 2>&1)"
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
# linię, bez numerów linii — te się przesuwają). Stan z 2026-11-14 to 35
# dawnych znalezisk (głównie SC2016/SC2034 w testach z eval); test pada tylko
# na NOWYCH — każde ponad liczbę z bazy dla pary plik+kod. Naprawione
# usuwaj z bazy: `bash tests/shellcheck.sh --update-baseline`.
BASE="$REPO/tests/shellcheck.baseline"
keys() { sed -nE 's/^([^:]+):[0-9]+:[0-9]+: .*\[(SC[0-9]+)\]$/\1 \2/p' | sort; }
if [[ "${1:-}" == --update-baseline ]]; then
    keys <<< "$out" | sed '/^$/d' > "$BASE"; echo "baseline: $(grep -c . "$BASE") findings"; exit 0
fi
declare -A allowed=()
while read -r n k; do allowed[$k]=$n; done < <(sort "$BASE" 2>/dev/null | uniq -c | awk '{print $1, $2" "$3}')
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
echo "Result: ${#files[@]} files / $new new findings / $known known"
exit 1
