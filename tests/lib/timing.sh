#!/usr/bin/env bash
# Wspólna skala zabezpieczeń, domyślnie 1; brak kalibracji przez zgadywanie.
TEST_TIMING_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_timing.py"
ARCHENEMY_TEST_TIME_SCALE="$(python3 "$TEST_TIMING_LIB" scale)" || exit 2
export ARCHENEMY_TEST_TIME_SCALE
# API timeout przyjmuje ułamkowe sekundy; nie zaokrąglamy w dół.
test_seconds() { awk -v base="$1" -v scale="$ARCHENEMY_TEST_TIME_SCALE" 'BEGIN { printf "%.17g\n", base * scale }'; }
test_timeout() {
    local base="$1" rc; shift
    timeout -k "$(test_seconds 5)" "$(test_seconds "$base")" "$@"; rc=$?
    if (( rc == 124 || rc == 137 )); then
        [[ -z "${TEST_TIMING_FAILURE_FILE:-}" ]] || printf 'kod=%s baza=%s skala=%s: %s\n' "$rc" "$base" "$ARCHENEMY_TEST_TIME_SCALE" "$*" >> "$TEST_TIMING_FAILURE_FILE"
        echo "ZABEZPIECZENIE: kod $rc; baza=$base s, skala=$ARCHENEMY_TEST_TIME_SCALE; $*" >&2
    fi
    return "$rc"
}
test_wait_file() { python3 "$TEST_TIMING_LIB" wait-file "$@"; }
# Marker przechodzi przez podpowłoki $(…), więc asercja samej treści nie
# zamieni uciętego wyjścia po timeout w zielony wynik pakietu.
test_timing_init() { export TEST_TIMING_FAILURE_FILE="$1/harness-timeouts.log"; }
test_timing_ok() {
    if [[ -s "${TEST_TIMING_FAILURE_FILE:-}" ]]; then
        echo "✗ ZABEZPIECZENIE: wystąpiły timeouty harnessu:" >&2
        cat "$TEST_TIMING_FAILURE_FILE" >&2
        return 1
    fi
}
