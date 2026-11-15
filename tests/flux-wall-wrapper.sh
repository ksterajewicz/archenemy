#!/bin/bash
# =============================================
#   archenemy - tests/flux-wall-wrapper.sh
#   Skutek komend scripts/wallpapers/flux-wall.sh: start, select, off, stop,
#   status, autostart i doctor (audyt 2026-11-05, KT8: dotąd test sprawdzał
#   tylko argumenty, bo atrapy pgrep/pkill zawsze dawały 1 — wynik `stop`,
#   `off`, `start` i `doctor` nie był nigdzie sprawdzany).
#
#   Atrapy ze STANEM procesu: fałszywa binarka flux-wall dopisuje swój PID
#   do $FW_STATE/pids i żyje, dopóki nie dostanie sygnału; pgrep/pkill
#   w PATH widzą i zabijają WYŁĄCZNIE PID-y z tego pliku — test nigdy nie
#   dotyka prawdziwego flux-walla na maszynie, na której go uruchomiono.
#   Sukces = odczytany stan (żyjący proces, plik wyboru, kod wyjścia),
#   nie sam tekst komunikatu.
#   Uruchom: bash tests/flux-wall-wrapper.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC1111  # „” w komunikatach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
export FW_STATE="$T/state"

# Sprzątanie: każda instancja atrapy, także ta, która ignoruje SIGTERM.
cleanup() {
    local pid
    if [[ -f "$FW_STATE/pids" ]]; then
        while read -r pid; do [[ "$pid" =~ ^[0-9]+$ ]] && kill -9 "$pid" 2>/dev/null; done < "$FW_STATE/pids"
    fi
    rm -rf "$T"
}
trap cleanup EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

A="$HOME/archenemy"; BIN="$A/src/flux-wall/build/flux-wall"
mkdir -p "$A/src/flux-wall/build" "$A/src/flux-wall/shaders" "$A/scripts/wallpapers" "$A/data" \
         "$A/rices/test-rice" "$A/scripts/lib" "$T/bin" "$FW_STATE"
cp "$REPO/scripts/wallpapers/flux-wall.sh" "$A/scripts/wallpapers/"
cp "$REPO/scripts/lib/runtime-dir.sh" "$A/scripts/lib/"   # katalog sesji na log i plik gotowości (S12)
WRAP="$A/scripts/wallpapers/flux-wall.sh"
for n in alpha beta; do printf '#version 300 es\nvoid main(){}\n' > "$A/src/flux-wall/shaders/$n.frag"; done
printf '%s\n' 'FLUX_WALL_PALETTE="000000,777777,FFFFFF"' 'FLUX_WALL_SHADER="src/flux-wall/shaders/alpha.frag"' \
    'FLUX_WALL_AUTOSTART=1' 'FLUX_WALL_DITHER=0' > "$A/rices/test-rice/flux-wall.conf"
echo test-rice > "$A/.current_rice"
: > "$FW_STATE/pids"

# Fałszywa binarka. FW_MOCK: ok (żyje do sygnału; po FW_MOCK_READY_DELAY s
# „pierwsza klatka” = PID w pliku z --ready-file) | fail-fast (kod 3 po 0,1 s) |
# fail-late (kod 3 po 0,8 s — jak błąd EGL/shadera przy pierwszej powierzchni)
# | hang (żyje, klatki nigdy nie ma) | bad-pid (żyje, w pliku gotowości cudzy
# PID — nie może się liczyć); FW_MOCK_IGNORE_TERM=1 — ignoruje SIGTERM
# (do_stop musi dobić -9); FW_MOCK_OLD=1 — binarka sprzed --ready-file.
cat > "$BIN" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == --help ]]; then
    if [[ "${FW_MOCK_OLD:-0}" == 1 ]]; then
        echo "Użycie: flux-wall -s shader.frag [--no-audio] [--dither | --no-dither]" >&2
    else
        echo "Użycie: flux-wall -s shader.frag [--no-audio] [--dither | --no-dither] [--ready-file plik]" >&2
    fi
    exit 0
fi
echo $$ >> "$FW_STATE/pids"
printf '%s\n' "$*" > "$FW_STATE/args.$$"
ready=""; prev=""
for a in "$@"; do [[ "$prev" == --ready-file ]] && ready="$a"; prev="$a"; done
case "${FW_MOCK:-ok}" in
    fail-fast) sleep 0.1; echo "flux-wall: shader: błąd kompilacji (atrapa)" >&2; exit 3 ;;
    fail-late) sleep 0.8; echo "flux-wall: eglCreateWindowSurface (atrapa)" >&2; exit 3 ;;
esac
if [[ "${FW_MOCK_IGNORE_TERM:-0}" == 1 ]]; then trap '' TERM; else trap 'exit 0' TERM; fi
if [[ "${FW_MOCK:-ok}" == ok && -n "$ready" ]]; then
    sleep "${FW_MOCK_READY_DELAY:-0.05}"; echo $$ > "$ready"
elif [[ "${FW_MOCK:-ok}" == bad-pid && -n "$ready" ]]; then
    echo 1 > "$ready"
fi
while :; do sleep 0.1; done
EOF

# pgrep/pkill: tylko `-x flux-wall` (tak woła wrapper), tylko PID-y atrapy.
# Żywy = istnieje i nie jest zombie.
cat > "$T/bin/pgrep" <<'EOF'
#!/bin/bash
[[ "$*" == "-x flux-wall" ]] || { echo "atrapa pgrep: nieznane argumenty: $*" >&2; exit 2; }
found=1
while read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    st="$(cut -d' ' -f3 "/proc/$pid/stat" 2>/dev/null)" || continue
    [[ -n "$st" && "$st" != Z ]] || continue
    echo "$pid"; found=0
done < "$FW_STATE/pids"
exit $found
EOF
cat > "$T/bin/pkill" <<'EOF'
#!/bin/bash
sig=TERM
[[ "${1:-}" == -9 ]] && { sig=KILL; shift; }
[[ "$*" == "-x flux-wall" ]] || { echo "atrapa pkill: nieznane argumenty: $*" >&2; exit 2; }
echo "$sig" >> "$FW_STATE/signals"
pids="$("$(dirname "$0")/pgrep" -x flux-wall)" || exit 1
for pid in $pids; do kill -s "$sig" "$pid" 2>/dev/null; done
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' > "$T/bin/pactl"
chmod +x "$BIN" "$T/bin/"*
export PATH="$T/bin:$PATH"

# wrap <komenda…> → OUT (stdout+stderr), RC
wrap() { OUT="$(bash "$WRAP" "$@" 2>&1)"; RC=$?; }
alive() { "$T/bin/pgrep" -x flux-wall; }          # PID-y żywych atrap (po linii)
n_alive() { local p; p="$(alive)"; if [[ -z "$p" ]]; then echo 0; else wc -l <<< "$p"; fi; }
choice() { cat "$A/data/flux-wall.dat" 2>/dev/null; }
# shader, z którym wystartował proces o danym PID-zie (argument po -s)
shader_of() { local a; a="$(<"$FW_STATE/args.$1")"; a="${a#*-s }"; a="${a%% *}"; basename "$a" .frag; }

echo "start / status / stop"
wrap start
pid1="$(alive)"
if [[ $RC -eq 0 && "$OUT" == *"flux-wall działa: alpha"* && $(n_alive) -eq 1 ]]; then
    ok "start: kod 0, „działa: alpha”, żyje 1 proces (pid $pid1)"
else fail "start: rc=$RC, żywych $(n_alive), wyjście: $OUT"; fi
if [[ -n "$pid1" && "$(shader_of "$pid1")" == alpha ]]; then ok "start: binarka dostała shader rice'a (alpha)"
else fail "start: argumenty: $(cat "$FW_STATE/args.$pid1" 2>/dev/null)"; fi
if bash "$WRAP" status; then ok "status: kod 0, gdy działa"; else fail "status: kod $? przy działającym procesie"; fi

wrap start
pid2="$(alive)"
if [[ $RC -eq 0 && $(n_alive) -eq 1 && -n "$pid2" && "$pid2" != "$pid1" ]]; then
    ok "drugi start: stara instancja zabita i pogrzebana, żyje tylko nowa ($pid1 → $pid2)"
else fail "drugi start: rc=$RC, żywe: $(alive | tr '\n' ' ')"; fi

wrap stop
if [[ $RC -eq 0 && "$OUT" == "flux-wall zatrzymany" && $(n_alive) -eq 0 ]]; then ok "stop: proces zniknął, „flux-wall zatrzymany”"
else fail "stop: rc=$RC, żywych $(n_alive), wyjście: $OUT"; fi
if bash "$WRAP" status; then fail "status: kod 0 po stop"; else ok "status: kod 1, gdy nie działa"; fi
wrap stop
if [[ $RC -eq 0 && "$OUT" == "flux-wall nie działał" ]]; then ok "stop bez procesu: „flux-wall nie działał”"
else fail "stop bez procesu: rc=$RC, wyjście: $OUT"; fi

echo "stop: proces ignorujący SIGTERM"
FW_MOCK_IGNORE_TERM=1 bash "$WRAP" start >/dev/null 2>&1
pid3="$(alive)"
: > "$FW_STATE/signals"
wrap stop
# po -9 wrapper nie czeka (kill jest asynchroniczny) — daj procesowi do 1 s
for _ in $(seq 1 10); do [[ $(n_alive) -eq 0 ]] && break; sleep 0.1; done
sigs="$(tr '\n' ' ' < "$FW_STATE/signals")"
if [[ -n "$pid3" && $(n_alive) -eq 0 && "$sigs" == "TERM KILL " ]]; then ok "stop: po ~2 s bez skutku TERM dobija -9 (sygnały: $sigs)"
else fail "stop: żywych $(n_alive), sygnały: $sigs, wyjście: $OUT"; fi

echo "select / off / autostart"
wrap select beta
pid4="$(alive)"
if [[ $RC -eq 0 && "$(choice)" == beta && $(n_alive) -eq 1 && "$(shader_of "$pid4")" == beta ]]; then
    ok "select beta: zapisany wybór, żyje proces z beta.frag"
else fail "select beta: rc=$RC, wybór '$(choice)', żywych $(n_alive), wyjście: $OUT"; fi
wrap select gamma
if [[ $RC -eq 1 && "$(choice)" == beta && "$(alive)" == "$pid4" ]]; then
    ok "select nieistniejącej: kod 1, wybór i proces bez zmian"
else fail "select gamma: rc=$RC, wybór '$(choice)', żywe: $(alive | tr '\n' ' ')"; fi
wrap off
if [[ $RC -eq 0 && "$(choice)" == off && $(n_alive) -eq 0 && "$OUT" == "animacja wyłączona" ]]; then
    ok "off: wybór „off”, proces zniknął"
else fail "off: rc=$RC, wybór '$(choice)', żywych $(n_alive), wyjście: $OUT"; fi
wrap off
if [[ $RC -eq 0 && "$OUT" == "animacja wyłączona (nie działała)" ]]; then ok "off bez procesu: „(nie działała)”"
else fail "off bez procesu: rc=$RC, wyjście: $OUT"; fi
wrap autostart
if [[ $RC -eq 0 && -z "$OUT" && $(n_alive) -eq 0 ]]; then ok "autostart przy „off”: cicho, kod 0, nic nie startuje"
else fail "autostart przy off: rc=$RC, żywych $(n_alive), wyjście: $OUT"; fi
wrap start
if [[ $RC -eq 4 && $(n_alive) -eq 0 ]]; then ok "start przy „off”: kod 4, nic nie startuje"
else fail "start przy off: rc=$RC, żywych $(n_alive)"; fi
rm -f "$A/data/flux-wall.dat"
wrap autostart
if [[ $RC -eq 0 && -z "$OUT" && $(n_alive) -eq 1 ]]; then ok "autostart bez wyboru: rice z AUTOSTART=1 startuje cicho"
else fail "autostart bez wyboru: rc=$RC, żywych $(n_alive), wyjście: $OUT"; fi

echo "doctor"
pid5="$(alive)"
wrap doctor
if [[ $RC -eq 0 && "$OUT" == *"flux-wall działa (pid $pid5 )"* && "$OUT" == *"rice: test-rice"* \
      && "$OUT" == *"flux-wall.dat: <brak pliku>"* ]]; then
    ok "doctor przy działającym: pid $pid5, rice, brak wyboru, kod 0"
else fail "doctor przy działającym: rc=$RC, wyjście: $OUT"; fi
bash "$WRAP" stop >/dev/null 2>&1
echo gamma > "$A/data/flux-wall.dat"
wrap doctor
if [[ $RC -eq 0 && "$OUT" == *"flux-wall nie działa"* && "$OUT" != *"flux-wall działa ("* \
      && "$OUT" == *"flux-wall.dat: gamma  ⚠ takiego shadera nie ma"* ]]; then
    ok "doctor po stop: „nie działa”, ostrzeżenie o nieistniejącym wyborze"
else fail "doctor po stop: rc=$RC, wyjście: $OUT"; fi
rm -f "$A/data/flux-wall.dat"

# „działa” tylko po potwierdzonej PIERWSZEJ klatce (audyt 2026-11-05, F7):
# dawniej wrapper patrzył na żywy proces po 0,5 s, a błąd EGL/shadera przy
# pierwszej powierzchni przychodzi później (prawdziwy bad.frag na llvmpipe:
# ok. 0,9 s) — Super+W meldował „applied”, a animacji nie było.
echo "start: potwierdzenie pierwszej klatki"
READY="$XDG_RUNTIME_DIR/flux-wall.ready"
FW_MOCK=fail-late wrap start
if [[ $RC -eq 3 && "$OUT" != *"flux-wall działa"* && "$OUT" == *"eglCreateWindowSurface (atrapa)"* && $(n_alive) -eq 0 ]]; then
    ok "binarka pada po 0,8 s (kod 3): wrapper kod 3 i ogon logu, bez „działa”"
else fail "fail-late: rc=$RC, żywych $(n_alive), wyjście: $OUT"; fi
FW_MOCK_READY_DELAY=1.2 wrap start
pid6="$(alive)"
if [[ $RC -eq 0 && "$OUT" == *"flux-wall działa: alpha"* && -n "$pid6" && -s "$READY" && "$(<"$READY")" == "$pid6" ]]; then
    ok "wolny start (klatka po 1,2 s): „działa” dopiero po pierwszej klatce"
else fail "wolny start: rc=$RC, żywe: $(alive | tr '\n' ' '), plik gotowości: $(cat "$READY" 2>/dev/null), wyjście: $OUT"; fi
if [[ -n "$pid6" && "$(<"$FW_STATE/args.$pid6")" == *"--ready-file $READY"* ]]; then ok "binarka dostała --ready-file \$XDG_RUNTIME_DIR/flux-wall.ready"
else fail "brak --ready-file w argumentach: $(cat "$FW_STATE/args.$pid6" 2>/dev/null)"; fi
bash "$WRAP" stop >/dev/null 2>&1
# plik gotowości z poprzedniej instancji (pid6, już martwy) nie może się liczyć
FLUX_WALL_READY_TIMEOUT=1 FW_MOCK=hang wrap start
if [[ $RC -eq 3 && "$OUT" == *"nie potwierdził pierwszej klatki"* && "$OUT" != *"flux-wall działa:"* && $(n_alive) -eq 1 ]]; then
    ok "brak klatki w limicie (1 s): kod 3, stary plik gotowości się nie liczy, proces zostaje"
else fail "hang: rc=$RC, żywych $(n_alive), wyjście: $OUT"; fi
if [[ ! -e "$READY" ]]; then ok "start kasuje plik gotowości poprzedniej instancji"
else fail "stary plik gotowości został: $(cat "$READY")"; fi
bash "$WRAP" stop >/dev/null 2>&1
FLUX_WALL_READY_TIMEOUT=1 FW_MOCK=bad-pid wrap start
if [[ $RC -eq 3 && "$OUT" == *"nie potwierdził pierwszej klatki"* ]]; then ok "plik gotowości z PID-em, który nie jest flux-wallem → nie liczy się"
else fail "bad-pid: rc=$RC, wyjście: $OUT"; fi
bash "$WRAP" stop >/dev/null 2>&1
FW_MOCK_OLD=1 wrap start
pid8="$(alive)"
if [[ $RC -eq 0 && "$OUT" == *"flux-wall działa: alpha"* && -n "$pid8" && "$(<"$FW_STATE/args.$pid8")" != *--ready-file* ]]; then
    ok "binarka sprzed --ready-file: bez flagi, jak dawniej (żywy proces po 0,5 s)"
else fail "stara binarka: rc=$RC, argumenty: $(cat "$FW_STATE/args.$pid8" 2>/dev/null), wyjście: $OUT"; fi
bash "$WRAP" stop >/dev/null 2>&1

# Log i plik gotowości tylko w prywatnym katalogu sesji (lib/runtime-dir.sh,
# S12), nie w gołym $XDG_RUNTIME_DIR ani we wspólnym /tmp. /run/user/<UID>
# zastępuje hak ARCHENEMY_RUNTIME_SYSTEM (test nie dotyka prawdziwego).
echo "start: plik gotowości w prywatnym katalogu sesji"
mkdir -m 755 "$T/xdg-open"; mkdir -m 700 "$T/sys"
XDG_RUNTIME_DIR="$T/xdg-open" ARCHENEMY_RUNTIME_SYSTEM="$T/sys" wrap start
pid9="$(alive)"
if [[ $RC -eq 0 && "$OUT" == *"flux-wall działa: alpha (log: $T/sys/flux-wall.log)"* && -n "$pid9" \
      && "$(<"$FW_STATE/args.$pid9")" == *"--ready-file $T/sys/flux-wall.ready"* \
      && "$(cat "$T/sys/flux-wall.ready" 2>/dev/null)" == "$pid9" && -z "$(ls -A "$T/xdg-open")" ]]; then
    ok "XDG_RUNTIME_DIR 0755: plik gotowości i log w /run/user/<UID>, nic w XDG"
else fail "XDG 0755: rc=$RC, argumenty: $(cat "$FW_STATE/args.$pid9" 2>/dev/null), w XDG: $(ls -A "$T/xdg-open"), wyjście: $OUT"; fi
bash "$WRAP" stop >/dev/null 2>&1
# Żaden katalog się nie nadaje (zapasowy archenemy-<UID> podstawiony jako
# dowiązanie): pliku gotowości nie ma gdzie położyć, więc nie wolno ani
# zgłosić „działa” bez klatki, ani czekać na plik, który nie powstanie.
mkdir -p "$T/tmp-planted" "$T/evil"; ln -s "$T/evil" "$T/tmp-planted/archenemy-$UID"
nodir() { XDG_RUNTIME_DIR="" ARCHENEMY_RUNTIME_SYSTEM="$T/none" TMPDIR="$T/tmp-planted" wrap "$@"; }
FLUX_WALL_READY_TIMEOUT=3 nodir start
pid10="$(alive)"
if [[ $RC -eq 3 && "$OUT" == *"pierwszej klatki nie potwierdzę"* && "$OUT" != *"flux-wall działa"* \
      && "$OUT" != *"nie potwierdził pierwszej klatki w"* && -n "$pid10" && $(n_alive) -eq 1 \
      && "$(<"$FW_STATE/args.$pid10")" != *--ready-file* && -z "$(ls -A "$T/evil")" ]]; then
    ok "bez prywatnego katalogu: kod 3 od razu (bez czekania na plik), bez „działa”, proces zostaje, nic w podstawionym"
else fail "bez katalogu: rc=$RC, żywych $(n_alive), argumenty: $(cat "$FW_STATE/args.$pid10" 2>/dev/null), w podstawionym: $(ls -A "$T/evil"), wyjście: $OUT"; fi
bash "$WRAP" stop >/dev/null 2>&1
FW_MOCK=fail-fast nodir start
if [[ $RC -eq 3 && "$OUT" == *"NIE wystartował"* && $(n_alive) -eq 0 ]]; then ok "bez prywatnego katalogu: padnięcie od razu nadal „NIE wystartował”"
else fail "bez katalogu, fail-fast: rc=$RC, żywych $(n_alive), wyjście: $OUT"; fi
FW_MOCK_OLD=1 nodir start
pid11="$(alive)"
if [[ $RC -eq 0 && "$OUT" == *"flux-wall działa: alpha"* && -n "$pid11" ]]; then ok "bez prywatnego katalogu, binarka sprzed --ready-file: jak dawniej"
else fail "bez katalogu, stara binarka: rc=$RC, wyjście: $OUT"; fi
bash "$WRAP" stop >/dev/null 2>&1
# doctor bez katalogu mówi, dlaczego logu nie ma — dawniej „brak /dev/null
# (proces nigdy nie wystartował…)”, choć proces startował, a log szedł donikąd.
nodir doctor
if [[ $RC -eq 0 && "$OUT" == *"== log: brak prywatnego katalogu sesji"* && "$OUT" != *"/dev/null"* \
      && -z "$(ls -A "$T/evil")" ]]; then ok "doctor bez prywatnego katalogu: „log: brak prywatnego katalogu sesji”, nic w podstawionym"
else fail "doctor bez katalogu: rc=$RC, w podstawionym: $(ls -A "$T/evil"), wyjście: $OUT"; fi

echo "start nieudany i brak binarki"
FW_MOCK=fail-fast wrap start
if [[ $RC -eq 3 && "$OUT" == *"NIE wystartował"* && "$OUT" == *"błąd kompilacji (atrapa)"* && $(n_alive) -eq 0 ]]; then
    ok "binarka pada od razu (kod 3): wrapper kod 3 i ogon logu"
else fail "fail-fast: rc=$RC, żywych $(n_alive), wyjście: $OUT"; fi
FW_MOCK=fail-fast wrap autostart
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "autostart z padającą binarką: cicho, kod 0 (hyprpaper zostaje)"
else fail "autostart fail-fast: rc=$RC, wyjście: $OUT"; fi
mv "$BIN" "$BIN.off"
wrap start
if [[ $RC -eq 2 && "$OUT" == *"brak binarki"* ]]; then ok "brak binarki: start kod 2"
else fail "brak binarki: rc=$RC, wyjście: $OUT"; fi
wrap autostart
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "brak binarki: autostart cicho, kod 0"
else fail "brak binarki, autostart: rc=$RC, wyjście: $OUT"; fi
mv "$BIN.off" "$BIN"

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
