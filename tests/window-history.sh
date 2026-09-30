#!/bin/bash
# =============================================
#   archenemy - tests/window-history.sh
#   Testy przywracania zamkniętych aplikacji (Super+Tab,
#   scripts/hypr/window-history.sh) na atrapie `hyprctl clients` i PRAWDZIWYCH
#   procesach (atrapa aplikacji = skrypt bash w mktemp). Bez Hyprlanda, bez
#   roota, bez zapisu poza mktemp.
#
#   Sprawdza: migawkę i wykrycie zamknięcia, ponowne uruchomienie z tymi samymi
#   argumentami w tym samym katalogu, pomijanie żywych procesów (okno do
#   zasobnika / dialog), okno procesu z innymi oknami, wyścig „Super+Q →
#   natychmiast Super+Tab”, deduplikację i limit stosu, wyjątki (archenemy-*,
#   gry Steama), awarię hyprctl, to, że przywrócona aplikacja nie trzyma
#   blokady stanu, oraz demona: zdarzenia socket2 (prawdziwy socket przez
#   socat), jedna instancja i czysty stan przy nowej instancji Hyprlanda.
#   Uruchom: bash tests/window-history.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WH="$REPO/scripts/hypr/window-history.sh"
T="$(mktemp -d)"
PIDS=()
cleanup() {
    local p
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
    pkill -f "$T/bin/fakeapp" 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

mkdir -p "$T/bin" "$T/run" "$T/dir with space"
export XDG_RUNTIME_DIR="$T/run"
export MOCK_CLIENTS="$T/clients.txt"
export APP_LOG="$T/app.log"
export NOTIFY_LOG="$T/notify.log"
export STEAM_LOG="$T/steam.log"
export ARCHENEMY_WH_EXIT_GRACE=2
: > "$APP_LOG"; : > "$NOTIFY_LOG"
STATE="$XDG_RUNTIME_DIR/archenemy-window-history"

# Atrapa hyprctl: `clients` w formacie tekstowym HyprCtl.cpp v0.56.2
# (składany z plików okien), MOCK_FAIL=1 = kompozytor nie odpowiada.
cat > "$T/bin/hyprctl" <<'EOF'
#!/bin/bash
[[ "${MOCK_FAIL:-0}" == 1 ]] && { echo "HYPRLAND_INSTANCE_SIGNATURE was not set! (Is Hyprland running?)"; exit 1; }
case "$1" in
  clients)
    if [[ -s "$MOCK_CLIENTS" ]]; then cat "$MOCK_CLIENTS"; else echo "no open windows"; fi ;;
  monitors) echo "Monitor eDP-1 (ID 0):" ;;
esac
EOF
cat > "$T/bin/notify-send" <<'EOF'
#!/bin/bash
echo "$*" >> "$NOTIFY_LOG"
EOF
cat > "$T/bin/steam" <<'EOF'
#!/bin/bash
echo "$*" >> "$STEAM_LOG"
EOF
# Atrapa aplikacji: zapisuje katalog i argumenty, potem żyje do zabicia.
cat > "$T/bin/fakeapp" <<'EOF'
#!/bin/bash
echo "$PWD|$*" >> "$APP_LOG"
trap 'kill $! 2>/dev/null; exit 0' TERM
sleep 300 & wait
EOF
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"

# Okno w formacie hyprctl: adres pid klasa
declare -A WINDOWS=()
render_clients() {
    local addr
    : > "$MOCK_CLIENTS"
    for addr in "${!WINDOWS[@]}"; do
        local pid="${WINDOWS[$addr]%%|*}" class="${WINDOWS[$addr]#*|}"
        printf 'Window %s -> tytuł %s:\n\tmapped: 1\n\thidden: 0\n\tworkspace: 1 (1)\n\tfloating: 0\n\tclass: %s\n\ttitle: tytuł\n\tinitialClass: %s\n\tpid: %s\n\txwayland: 0\n\n' \
            "$addr" "$addr" "$class" "$class" "$pid" >> "$MOCK_CLIENTS"
    done
}
open_win()  { WINDOWS["$1"]="$2|$3"; render_clients; }
close_win() { unset 'WINDOWS[$1]'; render_clients; }
spawn() {   # katalog argumenty... → PID atrapy aplikacji w $SPAWNED
    local dir="$1"; shift
    ( cd "$dir" && exec "$T/bin/fakeapp" "$@" ) >/dev/null 2>&1 7>&- &
    SPAWNED=$!
    PIDS+=("$SPAWNED")
    sleep 0.2
}
wait_dead() { local i; for i in $(seq 1 30); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done; }
closed_count() { grep -c . "$STATE/closed.tsv" 2>/dev/null || true; }
wait_log() {   # czekaj, aż przywrócona aplikacja dopisze linię do logu
    local n="$1" i
    for i in $(seq 1 30); do [[ $(grep -c . "$APP_LOG") -ge $n ]] && return 0; sleep 0.1; done
}

echo "== migawka i zamknięcie =="
spawn "$T/dir with space" alpha "two words" 'q"uote'
A=$SPAWNED
open_win aaa1 "$A" fakeapp
bash "$WH" refresh
check "okno w migawce" '[[ $(grep -c . "$STATE/open.tsv") -eq 1 ]]'
check "katalog stanu 0700" '[[ $(stat -c %a "$STATE") == 700 ]]'
close_win aaa1
kill "$A"; wait_dead "$A"
bash "$WH" refresh
check "zamknięte okno na stosie" '[[ $(closed_count) -eq 1 ]]'
check "list pokazuje wpis jako closed" 'bash "$WH" list | grep -q "^closed	fakeapp	"'

echo "== restore: te same argumenty, ten sam katalog =="
: > "$APP_LOG"
bash "$WH" restore
wait_log 1
check "aplikacja wstała z identycznymi argumentami i katalogiem" \
    '[[ "$(head -1 "$APP_LOG")" == "$T/dir with space|alpha two words q\"uote" ]]'
check "stos pusty po przywróceniu" '[[ $(closed_count) -eq 0 ]]'
check "przywrócona aplikacja nie trzyma blokady stanu" 'flock -n "$STATE/.lock" true'
pkill -f "$T/bin/fakeapp alpha" 2>/dev/null
: > "$NOTIFY_LOG"
bash "$WH" restore
check "pusty stos → powiadomienie Nothing to restore" 'grep -q "Nothing to restore" "$NOTIFY_LOG"'

echo "== proces z innym oknem nie trafia na stos =="
spawn "$T" multi
M=$SPAWNED
open_win bbb1 "$M" fakeapp
open_win bbb2 "$M" fakeapp
bash "$WH" refresh
close_win bbb2
bash "$WH" refresh
check "zamknięcie jednego z dwóch okien procesu — brak wpisu" '[[ $(closed_count) -eq 0 ]]'

echo "== żywy proces (zasobnik/dialog) jest pomijany =="
spawn "$T" older
O=$SPAWNED
open_win ccc1 "$O" fakeapp
bash "$WH" refresh
close_win ccc1; kill "$O"; wait_dead "$O"
bash "$WH" refresh
close_win bbb1          # ostatnie okno procesu M — proces żyje dalej (zasobnik)
bash "$WH" refresh
check "dwa wpisy na stosie" '[[ $(closed_count) -eq 2 ]]'
: > "$APP_LOG"
start_ts=$(date +%s)
bash "$WH" restore
wait_log 1
check "przywrócona starsza, martwa aplikacja (nie żywy proces z zasobnika)" 'grep -q "|older" "$APP_LOG"'
check "żywy wpis został na stosie" 'bash "$WH" list | grep -q "^running	"'
check "czekanie na żywy proces ograniczone EXIT_GRACE" '[[ $(( $(date +%s) - start_ts )) -le 4 ]]'
pkill -f "$T/bin/fakeapp older" 2>/dev/null
kill "$M"; wait_dead "$M"

echo "== wyścig: Super+Q i od razu Super+Tab =="
: > "$STATE/closed.tsv"
spawn "$T" slowexit
S=$SPAWNED
open_win ddd1 "$S" fakeapp
bash "$WH" refresh
close_win ddd1
( sleep 0.6; kill "$S" ) &
: > "$APP_LOG"
bash "$WH" restore
wait_log 1
check "restore poczekał na śmierć procesu i przywrócił właściwą aplikację" 'grep -q "|slowexit" "$APP_LOG"'
pkill -f "$T/bin/fakeapp slowexit" 2>/dev/null

echo "== wyjątki =="
: > "$STATE/closed.tsv"
spawn "$T" tui
U=$SPAWNED
open_win eee1 "$U" archenemy-appbinds
bash "$WH" refresh
close_win eee1; kill "$U"; wait_dead "$U"
bash "$WH" refresh
check "okno narzędzia archenemy-* nie trafia na stos" '[[ $(closed_count) -eq 0 ]]'
spawn "$T" game
G=$SPAWNED
open_win fff1 "$G" steam_app_620
bash "$WH" refresh
close_win fff1; kill "$G"; wait_dead "$G"
bash "$WH" refresh
: > "$STEAM_LOG"
bash "$WH" restore
sleep 0.3
check "gra Steama wraca przez steam://rungameid/<id>" 'grep -qx "steam://rungameid/620" "$STEAM_LOG"'
open_win ggg1 0 xwayland-bez-pid
bash "$WH" refresh
close_win ggg1
bash "$WH" refresh
check "okno bez PID nie trafia na stos" '[[ $(closed_count) -eq 0 ]]'

echo "== brakująca binarka =="
spawn "$T" gone
X=$SPAWNED
open_win hhh1 "$X" fakeapp
bash "$WH" refresh
close_win hhh1; kill "$X"; wait_dead "$X"
bash "$WH" refresh
# Ostatnie pole = komenda (printf %q) — podmień ją na nieistniejącą binarkę.
sed -i "s|\t[^\t]*$|\t$T/bin/nie-ma-mnie\\ arg|" "$STATE/closed.tsv"
: > "$NOTIFY_LOG"
bash "$WH" restore
check "brak binarki → powiadomienie, nie cisza" 'grep -q "not found" "$NOTIFY_LOG"'

echo "== awaria hyprctl nie zamyka okien =="
spawn "$T" survivor
V=$SPAWNED
open_win iii1 "$V" fakeapp
bash "$WH" refresh
kill "$V"; wait_dead "$V"
MOCK_FAIL=1 bash "$WH" refresh
check "hyprctl bez odpowiedzi → stan nietknięty" '[[ $(closed_count) -eq 0 && $(grep -c . "$STATE/open.tsv") -eq 1 ]]'
close_win iii1
bash "$WH" refresh
check "zero okien (\"no open windows\") → zamknięcie wykryte" '[[ $(closed_count) -eq 1 ]]'

echo "== limit stosu =="
: > "$STATE/closed.tsv"
for i in $(seq 1 23); do
    spawn "$T" "n$i"
    open_win "k$i" "$SPAWNED" fakeapp
    bash "$WH" refresh
    close_win "k$i"; kill "$SPAWNED"; wait_dead "$SPAWNED"
    bash "$WH" refresh
done
check "stos przycięty do 20 wpisów" '[[ $(closed_count) -eq 20 ]]'
check "najstarsze wypadły, najnowszy na końcu" '! grep -q "n3 *$" "$STATE/closed.tsv" && tail -1 "$STATE/closed.tsv" | grep -q "n23 *$"'

echo "== demon: zdarzenia socket2, jedna instancja, nowa sesja =="
# Stan z POPRZEDNIEGO Hyprlanda (XDG_RUNTIME_DIR przeżył relogin): stos
# i migawka mają zniknąć, a nie „zamknąć” wszystkie stare okna naraz.
echo "stara-sesja" > "$STATE/session"
printf 'dead1\t999999\t1\tfakeapp\t-\tfakeapp\\ stare\n' > "$STATE/open.tsv"
WINDOWS=(); render_clients
export HYPRLAND_INSTANCE_SIGNATURE="test-sig"
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
mkdir -p "$(dirname "$SOCK")"
mkfifo "$T/events"
socat -u "OPEN:$T/events" "UNIX-LISTEN:$SOCK" 2>/dev/null &
PIDS+=("$!")
exec 7>"$T/events"            # odblokowuje socat (czytelnik fifo)
for _ in $(seq 1 30); do [[ -S "$SOCK" ]] && break; sleep 0.1; done
# 7>&-: demon nie może trzymać pisarza fifo, inaczej EOF nigdy nie nadejdzie.
bash "$WH" daemon >/dev/null 2>&1 7>&- &
D=$!
PIDS+=("$D")
sleep 1
check "nowa instancja Hyprlanda → stary stos i migawka wyczyszczone" \
    '[[ $(closed_count) -eq 0 && "$(cat "$STATE/session")" == test-sig ]] && ! grep -q dead1 "$STATE/open.tsv"'
check "druga instancja demona wychodzi od razu (flock)" 'timeout 3 bash "$WH" daemon 7>&-'
spawn "$T" evented
E=$SPAWNED
open_win jjj1 "$E" fakeapp
echo "openwindow>>jjj1,1,fakeapp,tytuł" >&7
sleep 0.5
check "openwindow → migawka okna" 'grep -q "^jjj1	" "$STATE/open.tsv"'
close_win jjj1; kill "$E"; wait_dead "$E"
echo "closewindow>>jjj1" >&7
sleep 0.5
check "closewindow → wpis na stosie bez udziału restore" 'grep -q "fakeapp evented" "$STATE/closed.tsv"'
exec 7>&-                     # EOF socketa = koniec sesji Hyprlanda
for _ in $(seq 1 30); do kill -0 "$D" 2>/dev/null || break; sleep 0.1; done
check "demon kończy się po zamknięciu socketa" '! kill -0 "$D" 2>/dev/null'

echo ""
echo "window-history: $PASS ✓, $FAIL ✗"
[[ $FAIL -eq 0 ]]
