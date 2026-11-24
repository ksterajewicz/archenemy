#!/usr/bin/env bash
# =============================================
#   archenemy - tests/run-all.sh
#   Uruchamia wszystkie pakiety testów z tests/*.sh (poza sobą) i podaje
#   zbiorczy wynik. Każdy pakiet działa na atrapach w mktemp — bez
#   Hyprlanda, bez roota, bez zapisu poza katalogami tymczasowymi.
#   Glob obejmuje też shell-cli-tools.sh (bash/zsh i instalacja na atrapach).
#   Glob obejmuje też rice-completeness.sh (komplet konfiguracji każdego rice'a).
#   Limit czasu na pakiet (T8, audyt 2026-11-05: jedna regresja wieszała cały
#   bieg bez słowa): RUN_ALL_TIMEOUT sekund, domyślnie 600, 0 = bez limitu.
#   Po limicie pakiet i jego procesy potomne dostają SIGTERM, po 10 s SIGKILL,
#   a wynik to „✗ <pakiet> — timeout pakietu” (nie dowód zawieszenia).
#   Pakiet dostaje stdin z /dev/null; pełne logi porażek zostają w mktemp.
#   Ctrl+C, SIGTERM albo zamknięcie terminala (SIGHUP) przerywa cały bieg
#   razem z bieżącym pakietem.
#   Pakiet z kodem 0 to ✓, także gdy coś pominął (semantyka pominięć: T2).
#   Test tego pliku: tests/run-all-timeout.sh.
#   Uruchom: bash tests/run-all.sh   (kod 0 = wszystkie pakiety zielone)
# =============================================

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib/timing.sh
source "$DIR/lib/timing.sh"
LIMIT="${RUN_ALL_TIMEOUT:-$(python3 "$TEST_TIMING_LIB" seconds-ceil 600)}"
if [[ ! "$LIMIT" =~ ^[0-9]+$ ]]; then
    echo "RUN_ALL_TIMEOUT musi być liczbą całkowitą sekund (0 = bez limitu), jest: $LIMIT" >&2
    exit 2
fi
# Wyjście pakietu idzie do pliku, nie do $(…): proces potomny, który przeżyje
# zabicie pakietu (np. własna sesja przez setsid), nie trzyma wtedy otwartej
# rury i nie blokuje biegu.
LOG_DIR="$(mktemp -d /tmp/archenemy-run-all-XXXXXX)" || exit 2
keep_logs=0
cleanup_logs() { (( keep_logs )) || rm -rf "$LOG_DIR"; }
trap cleanup_logs EXIT
tpid="" name=""
# Nadzorca tworzy osobną sesję dla pakietu (dzięki temu zabija też
# procesy potomne pakietu), więc ani Ctrl+C, ani SIGHUP po zamknięciu
# terminala do pakietu nie docierają — przerwanie przekazujemy sami.
interrupted() {
    keep_logs=1
    echo "Pełne logi: $LOG_DIR"
    if [[ -n "$tpid" ]]; then
        kill -TERM "$tpid" 2>/dev/null
        wait "$tpid" 2>/dev/null; rc=$?
        printf '%s\n' "$rc" > "$LOG_DIR/$name.rc"
        echo "    pełne wyjście: $LOG; kod wyjścia: $LOG_DIR/$name.rc"
    fi
    echo ""
    echo "PRZERWANO${name:+ na $name}."
    exit 130
}
trap interrupted INT TERM HUP
echo "ZABEZPIECZENIE: RUN_ALL_TIMEOUT=$LIMIT s; ARCHENEMY_TEST_TIME_SCALE=$ARCHENEMY_TEST_TIME_SCALE (jawny RUN_ALL_TIMEOUT bez mnożenia)"
failed=()
for t in "$DIR"/*.sh; do
    name="$(basename "$t")"
    [[ "$name" == run-all.sh ]] && continue
    LOG="$LOG_DIR/$name.log"
    marker="$LOG_DIR/$name.timeout"
    # W tle, bo tylko `wait` da się przerwać pułapką; SIGINT i SIGQUIT
    # przywrócone, bo proces w tle nieinteraktywnej powłoki ma je ignorowane
    # (pułapka INT w pakiecie albo w testowanym instalatorze by nie działała).
    # SIGHUP też: bieg spod nohup (albo zadanie w tle narzędzia) dziedziczy go
    # ignorowanego, a bash nie złapie pułapką sygnału ignorowanego na wejściu —
    # testy SIGHUP pakietów zależałyby od tego, kto puścił bieg. Zamknięcie
    # terminala i tak nie trafia do pakietu (osobna sesja pakietu), więc
    # nohup dalej chroni sam run-all.
    env --default-signal=INT,QUIT,HUP python3 "$DIR/lib/test_timing.py" guard "$LIMIT" 10 "$marker" bash "$t" < /dev/null > "$LOG" 2>&1 &
    tpid=$!
    wait "$tpid"; rc=$?
    tpid=""
    printf '%s\n' "$rc" > "$LOG_DIR/$name.rc"
    if ((rc == 0)); then
        out="$(tail -n 1 "$LOG")"
        echo "✓ $name — $out"
    else
        keep_logs=1
        if [[ -f "$marker" ]]; then
            echo "✗ $name — timeout pakietu: przekroczono $LIMIT s (RUN_ALL_TIMEOUT); kod $rc"
        else
            echo "✗ $name — kod $rc (bez przekroczenia RUN_ALL_TIMEOUT)"
        fi
        echo "    pełne wyjście: $LOG; kod wyjścia: $LOG_DIR/$name.rc"
        echo "    ostatnie 200 linii:"
        tail -n 200 "$LOG" | sed 's/^/      /'
        failed+=("$name")
    fi
done
name=""
echo ""
if ((${#failed[@]})); then echo "NIEZIELONE: ${failed[*]}"; exit 1; fi
echo "Wszystkie pakiety zielone."
