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
#   Pliki idą równolegle (xargs -P): całe repo jednym procesem to minuty.
#   Uruchom: bash tests/shellcheck.sh   (kod 0 = zero NOWYCH znalezisk albo skip)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "  ? skip: shellcheck is not installed (sudo pacman -S shellcheck)"
    echo "Result: skipped (no shellcheck)"
    exit 0
fi

mapfile -d '' -t files < <(git -C "$REPO" ls-files -z -- '*.sh' 'tests/mock/*')
((${#files[@]})) || { echo "  ✗ no tracked scripts found"; exit 1; }

# Wyjście gcc: plik:linia:kolumna: poziom: opis [SCxxxx] — jedno znalezisko na linię.
out="$(cd "$REPO" && printf '%s\0' "${files[@]}" \
    | xargs -0 -n 4 -P "$(nproc 2>/dev/null || echo 2)" shellcheck -S info -e SC1091 -f gcc 2>&1)"

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
