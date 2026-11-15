#!/bin/bash
# =============================================
#   archenemy - tests/run-all.sh
#   Uruchamia wszystkie pakiety testów z tests/*.sh (poza sobą) i podaje
#   zbiorczy wynik. Każdy pakiet działa na atrapach w mktemp — bez
#   Hyprlanda, bez roota, bez zapisu poza katalogami tymczasowymi.
#   Glob obejmuje też shell-cli-tools.sh (bash/zsh i instalacja na atrapach).
#   Limit czasu na pakiet (T8, audyt 2026-11-05: jedna regresja wieszała cały
#   bieg bez słowa): RUN_ALL_TIMEOUT sekund, domyślnie 600, 0 = bez limitu.
#   Po limicie pakiet i jego procesy potomne dostają SIGTERM, po 10 s SIGKILL,
#   a wynik to „✗ <pakiet> — zawieszony”. Pakiet dostaje stdin z /dev/null.
#   Ctrl+C, SIGTERM albo zamknięcie terminala (SIGHUP) przerywa cały bieg
#   razem z bieżącym pakietem.
#   Pakiet z kodem 0 to ✓, także gdy coś pominął (semantyka pominięć: T2).
#   Test tego pliku: tests/run-all-timeout.sh.
#   Uruchom: bash tests/run-all.sh   (kod 0 = wszystkie pakiety zielone)
# =============================================

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMIT="${RUN_ALL_TIMEOUT:-600}"
if [[ ! "$LIMIT" =~ ^[0-9]+$ ]]; then
    echo "RUN_ALL_TIMEOUT musi być liczbą całkowitą sekund (0 = bez limitu), jest: $LIMIT" >&2
    exit 2
fi
# Wyjście pakietu idzie do pliku, nie do $(…): proces potomny, który przeżyje
# zabicie pakietu (np. własna sesja przez setsid), nie trzyma wtedy otwartej
# rury i nie blokuje biegu.
LOG="$(mktemp 2>/dev/null || TMPDIR=/tmp mktemp)" || { echo "run-all: mktemp nie działa" >&2; exit 2; }
trap 'rm -f "$LOG"' EXIT
tpid="" name=""
# `timeout` przenosi się do własnej grupy procesów (dzięki temu zabija też
# procesy potomne pakietu), więc ani Ctrl+C, ani SIGHUP po zamknięciu
# terminala do niego nie docierają — przerwanie przekazujemy sami.
interrupted() {
    if [[ -n "$tpid" ]]; then
        kill -TERM "$tpid" 2>/dev/null
        wait "$tpid" 2>/dev/null
    fi
    echo ""
    echo "PRZERWANO${name:+ na $name}."
    exit 130
}
trap interrupted INT TERM HUP
failed=()
for t in "$DIR"/*.sh; do
    name="$(basename "$t")"
    [[ "$name" == run-all.sh ]] && continue
    start=$SECONDS
    # W tle, bo tylko `wait` da się przerwać pułapką; SIGINT i SIGQUIT
    # przywrócone, bo proces w tle nieinteraktywnej powłoki ma je ignorowane
    # (pułapka INT w pakiecie albo w testowanym instalatorze by nie działała).
    env --default-signal=INT,QUIT timeout -k 10 "$LIMIT" bash "$t" < /dev/null > "$LOG" 2>&1 &
    tpid=$!
    wait "$tpid"; rc=$?
    tpid=""
    out="$(<"$LOG")"
    if ((rc == 0)); then
        echo "✓ $name — ${out##*$'\n'}"
    elif ((LIMIT > 0 && (rc == 124 || rc == 137) && SECONDS - start >= LIMIT)); then
        # 124: zabity SIGTERM-em po limicie; 137: dobity SIGKILL-em po -k 10.
        echo "✗ $name — zawieszony: brak wyniku po $LIMIT s (limit RUN_ALL_TIMEOUT), przerwany"
        echo "    ostatnie wiersze wyjścia:"
        tail -n 3 <<< "$out" | sed 's/^/      /'
        failed+=("$name")
    else
        echo "✗ $name"
        grep '✗' <<< "$out" | sed 's/^/    /'
        failed+=("$name")
    fi
done
name=""
echo ""
if ((${#failed[@]})); then echo "NIEZIELONE: ${failed[*]}"; exit 1; fi
echo "Wszystkie pakiety zielone."
