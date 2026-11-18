#!/usr/bin/env bash
# =============================================
#   archenemy - tests/run-all-timeout.sh
#   Limit czasu na pakiet w tests/run-all.sh (T8 z audytu 2026-11-05: jedna
#   zawieszona regresja blokowała cały bieg bez komunikatu). Kopia run-all.sh
#   w mktemp z atrapami pakietów: zielony, „skip” z kodem 0, czerwony,
#   wiszący (z wnukiem, który też wisi), wiszący z ignorowanym SIGTERM
#   i z pułapką SIGINT (pakiet nie może dostać SIGINT-u ignorowanego), kod
#   124 przed limitem (zwykłe ✗, nie „zawieszony”) oraz przerwanie biegu
#   przez Ctrl+C (SIGINT), SIGTERM i zamknięty terminal (SIGHUP).
#   Każdy bieg kopii pilnuje zewnętrzny `timeout -k 5` (SIGTERM, po 5 s
#   SIGKILL), więc na kodzie bez limitu albo bez `-k` w run-all.sh test
#   kończy się ✗ zamiast wisieć. Trwa ok. 20 s (SIGKILL po 10 s).
#   Uruchom: bash tests/run-all-timeout.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval (zmienne żyją w eval); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
# Sprzątanie także po nieudanym scenariuszu: atrapy zapisują swoje PID-y
# (każda sekcja z wiszącymi pakietami we własnym katalogu pids*).
cleanup() {
    local f
    for f in "$T"/pids*/*.pid; do
        [[ -f "$f" ]] && kill -KILL "$(<"$f")" 2>/dev/null
    done
    rm -rf "$T"
}
trap cleanup EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
# proc_state <pid> — litera stanu z /proc/<pid>/stat: pole po ostatnim „) ”,
# bo nazwa procesu w nawiasie może mieć spacje. Brak procesu = kod 1.
proc_state() {
    local s
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    { read -r s < "/proc/$1/stat"; } 2>/dev/null || return 1
    s="${s##*) }"
    echo "${s%% *}"
}
# alive <plik z PID-em> — proces istnieje i nie jest zombie. Sam `kill -0`
# nie wystarcza: w kontenerze joba GitHub Actions PID 1 to `tail -f /dev/null`
# (bez --init), który nie zbiera osieroconych procesów, więc pakiet dobity
# SIGKILL-em zostaje tam zombie na zawsze.
alive() {
    local st
    [[ -f "$1" ]] && st="$(proc_state "$(<"$1")")" && [[ "$st" != Z ]]
}

export PIDS="$T/pids" RAN="$T/ran"
mkdir -p "$PIDS"

echo "== 0: alive() a zombie (kontener CI bez --init)"
# Zombie na zawołanie: rodzic po exec (sleep 5) nigdy nie woła wait na dziecko.
( sleep 0.1 & echo $! > "$T/zombie.pid"; exec sleep 5 ) &
zparent=$!
echo "$zparent" > "$T/zparent.pid"
zst=""
for _ in $(seq 50); do
    [[ -s "$T/zombie.pid" ]] && zst="$(proc_state "$(<"$T/zombie.pid")")" && [[ "$zst" == Z ]] && break
    sleep 0.1
done
check "zombie (kill -0 nadal go widzi) to proces martwy"   '[[ "$zst" == Z ]] && kill -0 "$(<"$T/zombie.pid")" && ! alive "$T/zombie.pid"'
check "działający proces to proces żywy"                   'alive "$T/zparent.pid"'
kill "$zparent" 2>/dev/null; wait "$zparent" 2>/dev/null

# suite <katalog> <pakiet…> — kopia run-all.sh i wybrane atrapy pakietów.
suite() {
    local d="$1"; shift
    mkdir -p "$d"
    cp "$REPO/tests/run-all.sh" "$d/run-all.sh"
    local p
    for p in "$@"; do cp "$T/stubs/$p" "$d/$p"; done
}
mkdir -p "$T/stubs"
cat > "$T/stubs/a-green.sh" <<'EOF'
echo a-green >> "$RAN"
echo "  ✓ jedno"
echo "Wynik: 1 ✓ / 0 ✗"
EOF
cat > "$T/stubs/b-hang.sh" <<'EOF'
echo b-hang >> "$RAN"
sleep 300 & echo $! > "$PIDS/b-grandchild.pid"
echo $$ > "$PIDS/b-hang.pid"
echo "  ✓ przed zawieszeniem"
echo "ZAWIESZONY-TUTAJ"
wait
EOF
cat > "$T/stubs/c-skip.sh" <<'EOF'
echo c-skip >> "$RAN"
echo "  ? skip: brak narzędzia"
echo "Result: skipped"
EOF
cat > "$T/stubs/d-red.sh" <<'EOF'
echo d-red >> "$RAN"
echo "  ✗ coś nie tak"
echo "Wynik: 0 ✓ / 1 ✗"
exit 1
EOF
cat > "$T/stubs/e-stubborn.sh" <<'EOF'
trap '' TERM
echo e-stubborn >> "$RAN"
sleep 300 & echo $! > "$PIDS/e-grandchild.pid"
echo $$ > "$PIDS/e-stubborn.pid"
wait
EOF
cat > "$T/stubs/f-slow.sh" <<'EOF'
sleep 2
echo "Wynik: wolny, ale skończony"
EOF
# Pułapka INT w pakiecie (jak w instalatorze, któremu testy wysyłają SIGINT):
# działa tylko, gdy run-all nie odda pakietu z SIGINT ignorowanym.
cat > "$T/stubs/g-int.sh" <<'EOF'
trap 'echo "Wynik: pułapka INT działa"; exit 0' INT
kill -INT $$
echo "  ✗ SIGINT zignorowany"
exit 1
EOF
# To samo dla SIGHUP: sygnał ignorowany na wejściu (nohup, zadanie w tle
# narzędzia) dziedziczy się i bash nie da go już złapać pułapką.
cat > "$T/stubs/g-hup.sh" <<'EOF'
trap 'echo "Wynik: pułapka HUP działa"; exit 0' HUP
kill -HUP $$
echo "  ✗ SIGHUP zignorowany"
exit 1
EOF
# Kod 124 bez przekroczenia limitu (np. własny `timeout` w pakiecie) to zwykła
# porażka, nie „zawieszony”.
cat > "$T/stubs/h-124.sh" <<'EOF'
echo "  ✗ własny timeout w pakiecie"
exit 124
EOF

echo "== A: wiszący pakiet przy RUN_ALL_TIMEOUT=2"
suite "$T/a" a-green.sh b-hang.sh c-skip.sh d-red.sh e-stubborn.sh
: > "$RAN"
t0=$SECONDS
out="$(RUN_ALL_TIMEOUT=2 timeout -k 5 45 bash "$T/a/run-all.sh" 2>&1)"; rc=$?
took=$((SECONDS - t0))
check "bieg kończy się sam (bez zewnętrznego limitu 45 s)" '[[ $rc -ne 124 && $took -lt 40 ]]'
check "kod 1 (są pakiety niezielone)"                     '[[ $rc -eq 1 ]]'
check "zielony pakiet: ✓ z ostatnim wierszem"              '[[ "$out" == *"✓ a-green.sh — Wynik: 1 ✓ / 0 ✗"* ]]'
check "wiszący: ✗ „zawieszony” z limitem w sekundach"      '[[ "$out" == *"✗ b-hang.sh — zawieszony: brak wyniku po 2 s"* ]]'
check "wiszący: widać ostatnie wiersze wyjścia"            '[[ "$out" == *"ZAWIESZONY-TUTAJ"* ]]'
check "wiszący pakiet i jego wnuk zabici"                  '! alive "$PIDS/b-hang.pid" && ! alive "$PIDS/b-grandchild.pid"'
check "pominięcie z kodem 0 nadal ✓ (semantyka T2 bez zmian)" '[[ "$out" == *"✓ c-skip.sh — Result: skipped"* ]]'
check "czerwony pakiet: ✗ bez „zawieszony”, z jego ✗"      'grep -qx "✗ d-red.sh" <<< "$out" && [[ "$out" == *"    ✗ coś nie tak"* ]]'
check "ignorujący SIGTERM: zawieszony i dobity SIGKILL"    '[[ "$out" == *"✗ e-stubborn.sh — zawieszony"* ]] && ! alive "$PIDS/e-stubborn.pid" && ! alive "$PIDS/e-grandchild.pid"'
check "podsumowanie wymienia trzy niezielone"              '[[ "$out" == *"NIEZIELONE: b-hang.sh d-red.sh e-stubborn.sh"* ]]'
check "każdy pakiet uruchomiony raz, po kolei"             '[[ "$(tr "\n" " " < "$RAN")" == "a-green b-hang c-skip d-red e-stubborn " ]]'

echo "== B: wartość RUN_ALL_TIMEOUT, kod 124 i SIGINT w pakiecie"
: > "$RAN"
out="$(RUN_ALL_TIMEOUT=abc timeout -k 5 10 bash "$T/a/run-all.sh" 2>&1)"; rc=$?
check "zła wartość: kod 2, komunikat, żaden pakiet nie ruszył" '[[ $rc -eq 2 && "$out" == *RUN_ALL_TIMEOUT* && ! -s "$RAN" ]]'
suite "$T/b" f-slow.sh
out="$(RUN_ALL_TIMEOUT=1 timeout -k 5 20 bash "$T/b/run-all.sh" 2>&1)"; rc=$?
check "limit 1 s: pakiet 2-sekundowy zawieszony"           '[[ $rc -eq 1 && "$out" == *"✗ f-slow.sh — zawieszony"* ]]'
out="$(RUN_ALL_TIMEOUT=0 timeout -k 5 20 bash "$T/b/run-all.sh" 2>&1)"; rc=$?
check "0 = bez limitu: ten sam pakiet ✓"                   '[[ $rc -eq 0 && "$out" == *"✓ f-slow.sh — Wynik: wolny, ale skończony"* ]]'
suite "$T/e" h-124.sh
out="$(RUN_ALL_TIMEOUT=10 timeout -k 5 20 bash "$T/e/run-all.sh" 2>&1)"; rc=$?
check "kod 124 przed limitem: zwykłe ✗, bez „zawieszony”"  '[[ $rc -eq 1 && "$out" != *zawieszony* ]] && grep -qx "✗ h-124.sh" <<< "$out" && [[ "$out" == *"    ✗ własny timeout w pakiecie"* ]]'
suite "$T/d" g-int.sh
out="$(RUN_ALL_TIMEOUT=10 timeout -k 5 20 bash "$T/d/run-all.sh" 2>&1)"; rc=$?
check "pakiet dostaje SIGINT jak z terminala, nie ignorowany" '[[ $rc -eq 0 && "$out" == *"✓ g-int.sh — Wynik: pułapka INT działa"* ]]'
suite "$T/g" g-hup.sh
# run-all puszczony z SIGHUP ignorowanym (jak spod nohup): pakiet i tak ma
# dostać domyślną obsługę, inaczej jego test SIGHUP zależy od tego, kto puścił bieg.
out="$(RUN_ALL_TIMEOUT=10 timeout -k 5 20 bash -c 'trap "" HUP; exec bash "$1"' _ "$T/g/run-all.sh" 2>&1)"; rc=$?
check "pakiet dostaje SIGHUP z domyślną obsługą, także spod nohup" '[[ $rc -eq 0 && "$out" == *"✓ g-hup.sh — Wynik: pułapka HUP działa"* ]]'

echo "== C: przerwanie biegu w trakcie wiszącego pakietu"
suite "$T/c" b-hang.sh
# interrupt <sygnał> <etykieta> — kopia run-all z wiszącym pakietem dostaje
# sygnał, gdy pakiet już działa (znacznik: jego plik PID). Każdy sygnał ma
# własny katalog PID-ów: pliki z sekcji A zostają dla cleanup (procesy, które
# przeżyły regresję, i tak zostaną dobite).
# Proces w tle nieinteraktywnej powłoki ma SIGINT ignorowany (i niepodmienialny
# pułapką) — env przywraca domyślny, jak przy Ctrl+C w terminalu. SIGHUP tak
# samo: test puszczony spod nohup (albo jako zadanie w tle narzędzia) dziedziczy
# go ignorowanego i pułapka HUP w run-all nie działa — dawało to 26 ✓ / 1 ✗
# w pełnym biegu, a 27/0 w terminalu (scalenie 2026-11-15).
interrupt() {
    local sig="$1" label="$2" guard runall_pid t0
    PIDS="$T/pids-c-$sig"; mkdir -p "$PIDS"
    RUN_ALL_TIMEOUT=60 env --default-signal=INT,HUP timeout -k 5 30 bash "$T/c/run-all.sh" > "$T/c-$sig.out" 2>&1 &
    guard=$!
    for _ in $(seq 100); do [[ -s "$PIDS/b-hang.pid" ]] && break; sleep 0.1; done
    runall_pid="$(pgrep -P "$guard" -f 'c/run-all.sh' | head -1)"
    [[ -n "$runall_pid" ]] && kill -"$sig" "$runall_pid"
    t0=$SECONDS
    for _ in $(seq 100); do kill -0 "$guard" 2>/dev/null || break; sleep 0.1; done
    took=$((SECONDS - t0))
    wait "$guard"; rc=$?
    out="$(<"$T/c-$sig.out")"
    check "$label: bieg przerwany od razu, kod 130"        '[[ -n "$runall_pid" && $rc -eq 130 && $took -lt 10 ]]'
    check "$label: komunikat wskazuje przerwany pakiet"    '[[ "$out" == *"PRZERWANO na b-hang.sh."* ]]'
    check "$label: przerwany pakiet i jego wnuk zabici"    '! alive "$PIDS/b-hang.pid" && ! alive "$PIDS/b-grandchild.pid"'
}
interrupt INT "Ctrl+C (SIGINT)"
interrupt TERM "SIGTERM"
# Zamknięty terminal: SIGHUP trafia do grupy procesów run-all (zadania powłoki),
# a nie do pakietu, który działa w osobnej grupie `timeout` — bez pułapki HUP
# w run-all pakiet z wnukiem przeżyłby zamknięcie terminala.
interrupt HUP "zamknięty terminal (SIGHUP)"

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
