#!/bin/bash

# =============================================
#   archenemy - flux-wall.sh
#   Steruje flux-wall — tapetą liczoną shaderem na GPU (src/flux-wall).
#
#   Dwa źródła prawdy, w tej kolejności:
#     1. WYBÓR UŻYTKOWNIKA — data/flux-wall.dat (warstwa maszynowa, Super+W):
#        "off"    → animacja wyłączona wszędzie,
#        "<nazwa>" → animacja <nazwa> (src/flux-wall/shaders/<nazwa>.frag)
#                    w KAŻDYM ricu, w jego palecie,
#        brak pliku → zachowanie domyślne rice'a (pkt 2).
#     2. DEKLARACJA RICE'A — rices/<rice>/flux-wall.conf:
#        FLUX_WALL_PALETTE   "bg,ink,acc" (hex) — paleta tego rice'a,
#        FLUX_WALL_SHADER    domyślny shader (ścieżka względem repo),
#        FLUX_WALL_ARGS      argumenty (np. --battery),
#        FLUX_WALL_AUTOSTART 1 = animacja domyślnie włączona w tym ricu
#                            (bez wyboru użytkownika), 0 = domyślnie wyłączona.
#        FLUX_WALL_DITHER    1 = raster Bayera (--dither), 0 = gładki gradient
#                            palety (--no-dither). Cecha RICE'A, nie animacji:
#                            obowiązuje każdą animację z Super+W (wybór jest
#                            globalny), a Super+T (autostart) przełącza ją
#                            na żywo. Brak klucza = 0.
#        Rice bez pliku: paleta domyślna binarki, autostart 0, dither 0.
#
#   WIZUALIZACJA MUZYKI — bez przełącznika (decyzja właściciela 2026-09-08):
#   audio włącza sam flux-wall, gdy shader deklaruje `#pragma flux audio 1`.
#   Wrapper podaje tylko nazwę monitora domyślnego sinku z pactl jako fallback
#   po @DEFAULT_MONITOR@. Nasłuch to WYŁĄCZNIE wyjście (to, co słychać).
#
#   Użycie:
#     flux-wall.sh autostart | restore   z hyprland.lua i z przełącznika rice'ów:
#                                        stop starej instancji, start wg reguł
#                                        wyżej. CICHY: nic do zrobienia = kod 0.
#     flux-wall.sh select <nazwa>        Super+W: zapisz wybór i zastosuj
#     flux-wall.sh off                   Super+W: wyłącz i zapamiętaj
#     flux-wall.sh list                  nazwy dostępnych animacji (po linii)
#     flux-wall.sh list-audio            nazwy animacji będących wizualizacją muzyki
#     flux-wall.sh start [opcje]         jak restore, ale głośno; opcje → flux-wall;
#                                        „działa” dopiero po PIERWSZEJ klatce na ekranie
#                                        (plik --ready-file w prywatnym katalogu sesji,
#                                        limit FLUX_WALL_READY_TIMEOUT sekund, domyślnie 10;
#                                        stara binarka: żywa po 0,5 s; bez katalogu sesji
#                                        klatki nie potwierdzi → kod 3, proces zostaje)
#     flux-wall.sh stop | status
#     flux-wall.sh doctor-safe          sonda bez source konfiguracji (publiczny doctor)
#     flux-wall.sh doctor               zrzut stanu do diagnozy (repo, binarka,
#                                        shadery, wybór, proces, log) — tylko odczyt
#
#   Kody: 0 ok · 1 użycie/zła nazwa · 2 brak binarki · 3 start nieudany albo
#         bez pierwszej klatki w limicie albo bez możliwości jej potwierdzenia
#         (log; proces wtedy zostaje) ·
#         4 nic do uruchomienia (off / rice bez autostartu)
#
#   Fallback jest w architekturze, nie tu: hyprpaper działa ZAWSZE, a flux-wall
#   rysuje na warstwie `bottom` — nad nim, pod oknami.
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
BIN="$ARCHENEMY_DIR/src/flux-wall/build/flux-wall"
SHADERS_DIR="$ARCHENEMY_DIR/src/flux-wall/shaders"
CURRENT_RICE_FILE="$ARCHENEMY_DIR/.current_rice"
DATA_DIR="$ARCHENEMY_DIR/data"
CHOICE_DAT="$DATA_DIR/flux-wall.dat"
# Najdłuższe czekanie `start` na plik gotowości (READY, liczony niżej obok LOG).
READY_TIMEOUT="${FLUX_WALL_READY_TIMEOUT:-10}"
[[ "$READY_TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] || READY_TIMEOUT=10

# Bezpieczna sonda publicznego doctora: nigdy nie wykonuje konfiguracji.
# Wszystkie odczyty są ograniczone; dowiązania muszą zostać w drzewie repo.
if [[ "${1:-}" == doctor-safe ]]; then
    exec python - "$ARCHENEMY_DIR" <<'PY'
import os
from pathlib import Path
import re
import stat
import sys

repo = Path(sys.argv[1]).resolve()
def read_repo(path, maximum=65536):
    try:
        resolved = path.resolve()
        if not resolved.is_relative_to(repo):
            return None
        info = resolved.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_size > maximum:
            return None
        fd = os.open(resolved, os.O_RDONLY | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > maximum:
                return None
            data = stream.read(maximum + 1)
            return data.decode('utf-8', errors='replace') if len(data) <= maximum else None
    except (OSError, RuntimeError):
        return None

rice = (read_repo(repo / '.current_rice', 256) or '').strip()
if not re.fullmatch(r'[a-z0-9_-]+', rice):
    print('Rice configuration: rejected')
    sys.exit(1)
conf = repo / 'rices' / rice / 'flux-wall.conf'
try:
    allowed = conf.resolve().is_relative_to(repo / 'rices')
except (OSError, RuntimeError):
    allowed = False
if not allowed:
    print('Rice configuration: rejected')
    sys.exit(1)
text = read_repo(conf)
print('Rice configuration: present (not executed)' if text is not None else 'Rice configuration: absent or rejected')
print('Binary: ' + ('present' if (repo / 'src/flux-wall/build/flux-wall').is_file() else 'absent'))
sys.exit(0 if text is not None else 1)
PY
fi

# Log i plik gotowości w prywatnym katalogu sesji (lib/runtime-dir.sh, S12),
# tym samym co w przełączniku tapet; nigdy we wspólnym /tmp. Liczone po sondzie
# doctora, bo ta niczego nie zakłada.
# Plik gotowości: binarka tworzy go z PID-em po PIERWSZEJ klatce na ekranie
# (--ready-file); `start` czeka na niego najwyżej READY_TIMEOUT sekund.
# Bez katalogu: log do /dev/null (jest tylko pisany i czytany), a pliku
# gotowości nie ma — `start` nie potwierdzi klatki, więc nie mówi „działa”
# (kod 3, proces zostaje; patrz wait_ready).
# shellcheck source=scripts/lib/runtime-dir.sh
source "$ARCHENEMY_DIR/scripts/lib/runtime-dir.sh"
RUN_DIR="$(archenemy_runtime_dir)" || RUN_DIR=""
LOG=/dev/null; READY=""
if [[ -n "$RUN_DIR" ]]; then
    LOG="$RUN_DIR/flux-wall.log"
    READY="$RUN_DIR/flux-wall.ready"
fi

# ─── odczyt konfiguracji ──────────────────────────────────────────────────────

FLUX_WALL_PALETTE=""; FLUX_WALL_SHADER=""; FLUX_WALL_ARGS=""; FLUX_WALL_AUTOSTART=0; FLUX_WALL_DITHER=0

load_rice_conf() {
    local rice conf
    [[ -f "$CURRENT_RICE_FILE" ]] || return 1
    rice="$(<"$CURRENT_RICE_FILE")"; rice="${rice//[[:space:]]/}"
    [[ -n "$rice" ]] || return 1
    conf="$ARCHENEMY_DIR/rices/$rice/flux-wall.conf"
    [[ -f "$conf" ]] || return 1
    # shellcheck disable=SC1090  # ścieżka zależy od bieżącego rice'a; plik jest w repo
    source "$conf"
    return 0
}

read_choice() {   # → "off" | nazwa | "" (brak wyboru)
    local c=""
    [[ -f "$CHOICE_DAT" ]] && c="$(<"$CHOICE_DAT")"
    echo "${c//[[:space:]]/}"
}

write_choice() {  # zapis atomowy tmp+mv (wzorzec repo)
    local tmp
    mkdir -p "$DATA_DIR"
    tmp=$(mktemp "$CHOICE_DAT.XXXXXX") || return 1
    printf '%s\n' "$1" > "$tmp"; chmod 644 "$tmp"; mv "$tmp" "$CHOICE_DAT"
}

shader_path() {   # nazwa → ścieżka; pusto, gdy nie ma pliku
    local name="$1"
    # Dozwolone: małe litery, cyfry, myślnik i apostrof (orb-spinnin' —
    # decyzja właściciela 2026-09-17c); nigdy `/` ani `..` — nazwa staje się ścieżką.
    [[ "$name" =~ ^[a-z0-9\'-]+$ ]] || return 1
    [[ -f "$SHADERS_DIR/$name.frag" ]] && echo "$SHADERS_DIR/$name.frag"
}

list_shaders() {  # nazwy dostępnych animacji, po jednej na linię (bez .frag)
    local f
    for f in "$SHADERS_DIR"/*.frag; do
        [[ -f "$f" ]] || continue
        f="${f##*/}"; echo "${f%.frag}"
    done
}

# Wizualizacje muzyki: shader (frag albo update) deklaruje `#pragma flux audio 1`.
is_audio_shader() {  # nazwa → 0 gdy wizualizacja
    local n="$1"
    grep -qs '^#pragma flux audio 1' "$SHADERS_DIR/$n.update.glsl" "$SHADERS_DIR/$n.frag"
}

list_audio_shaders() {
    local n
    while IFS= read -r n; do is_audio_shader "$n" && echo "$n"; done < <(list_shaders)
}

# Nazwa monitora domyślnego sinku jako fallback dla flux-walla (który najpierw
# próbuje @DEFAULT_MONITOR@). Binarka sprzed wizualizacji (git pull bez
# install.sh/make) nie zna --audio-device — wtedy nic nie podajemy.
audio_args() {      # ustawia AUDIO_ARGS
    AUDIO_ARGS=()
    local sink
    command -v pactl >/dev/null 2>&1 || return 0
    "$BIN" --help 2>&1 | grep -q -- '--audio-device' || return 0
    sink="$(pactl get-default-sink 2>/dev/null)"
    [[ -n "$sink" ]] && AUDIO_ARGS=("--audio-device=${sink}.monitor")
}

# Raster z deklaracji AKTYWNEGO rice'a (po load_rice_conf), niezależnie od
# animacji. Binarka sprzed flagi (git pull bez make) jej nie zna i rysuje
# raster jak dawniej — wtedy nic nie podajemy, żeby w ogóle wystartowała.
dither_args() {     # ustawia DITHER_ARGS
    DITHER_ARGS=()
    "$BIN" --help 2>&1 | grep -q -- '--no-dither' || return 0
    if [[ "$FLUX_WALL_DITHER" == "1" ]]; then DITHER_ARGS=(--dither)
    else DITHER_ARGS=(--no-dither); fi
}

# Binarka z --ready-file potwierdza pierwszą klatkę plikiem. Sprzed flagi
# (git pull bez make) nic nie podajemy — start sprawdzamy jak dawniej.
# Zna flagę, ale nie ma prywatnego katalogu sesji (READY pusty): pliku nie
# podajemy (nie wracamy do wspólnego /tmp), a READY_UNCONFIRMED=1 zabrania
# wait_ready meldować „rysuje” — potwierdzić nie ma czym.
# --help do zmiennej, nie `| grep -q` (pipefail + SIGPIPE = fałszywe „nie”).
ready_args() {      # ustawia READY_ARGS i READY_UNCONFIRMED
    READY_ARGS=(); READY_UNCONFIRMED=0
    [[ "$("$BIN" --help 2>&1)" == *--ready-file* ]] || return 0
    if [[ -n "$READY" ]]; then READY_ARGS=(--ready-file "$READY")
    else READY_UNCONFIRMED=1; fi
    return 0
}

# PID $1 to żywy flux-wall (pgrep -x widzi go pod tą nazwą)?
is_flux_pid() {
    local p
    while read -r p; do [[ "$p" == "$1" ]] && return 0; done < <(pgrep -x flux-wall 2>/dev/null)
    return 1
}

# Czy flux-wall naprawdę rysuje. Sam żywy proces po 0,5 s nic nie znaczył:
# shader kompiluje się, a powierzchnia EGL powstaje dopiero przy pierwszym
# configure, więc błąd (kod 3) przychodził po ~0,9 s, na wolnym GPU później
# — Super+W meldował „applied”, a animacji nie było (audyt 2026-11-05, F7).
# Czekamy więc na plik gotowości z PID-em żywego flux-walla (pierwsza klatka
# na ekranie), najwyżej READY_TIMEOUT s; $1 = PID z `$!`.
# Kod: 0 rysuje · 1 proces padł · 2 żyje, ale bez klatki w limicie ·
# 3 żyje po 0,5 s, ale bez prywatnego katalogu sesji klatki nie potwierdzimy.
# Binarka sprzed --ready-file: jak dawniej, żywy proces po 0,5 s = 0.
wait_ready() {
    local child="$1" i pid
    if ((${#READY_ARGS[@]} == 0)); then
        sleep 0.5
        pgrep -x flux-wall >/dev/null || return 1
        ((READY_UNCONFIRMED == 0)) || return 3
        return 0
    fi
    for ((i = 0; i < READY_TIMEOUT * 10; i++)); do
        if [[ -s "$READY" ]]; then
            pid="$(<"$READY")"; pid="${pid//[[:space:]]/}"
            [[ "$pid" =~ ^[0-9]+$ ]] && is_flux_pid "$pid" && return 0
        fi
        # dziecko przed exec ma jeszcze inną nazwę, więc najpierw kill -0 po PID-zie
        kill -0 "$child" 2>/dev/null || pgrep -x flux-wall >/dev/null || return 1
        sleep 0.1
    done
    return 2
}

# Ustala, czy i z czym startować. Ustawia SHADER i PALETTE_ARGS.
resolve() {
    local choice
    choice="$(read_choice)"
    load_rice_conf || true
    PALETTE_ARGS=()
    [[ -n "$FLUX_WALL_PALETTE" ]] && PALETTE_ARGS=(-p "$FLUX_WALL_PALETTE")

    if [[ "$choice" == "off" ]]; then
        return 1
    elif [[ -n "$choice" ]]; then
        SHADER="$(shader_path "$choice")" || SHADER=""
        if [[ -z "$SHADER" ]]; then
            echo "flux-wall.sh: wybrana animacja '$choice' nie istnieje — wracam do domyślnej rice'a" >&2
            SHADER=""
        fi
    fi
    if [[ -z "${SHADER:-}" ]]; then
        # brak wyboru (albo wybór nieistniejący): domyślne zachowanie rice'a
        [[ "$FLUX_WALL_AUTOSTART" == "1" && -n "$FLUX_WALL_SHADER" ]] || return 1
        SHADER="$ARCHENEMY_DIR/$FLUX_WALL_SHADER"
        [[ -f "$SHADER" ]] || return 1
    fi
    return 0
}

# Zabij i POCZEKAJ, aż proces naprawdę zniknie — do_start startuje nową
# instancję zaraz po tym wywołaniu; bez czekania stara i nowa nakładały się
# na tej samej powierzchni Wayland (ten sam wyścig, który miał waybar).
# Kod: 0 = proces był i zniknął, 1 = nic nie działało (stop/off mówią wtedy
# „nie działał”; wcześniej pętla niżej oddawała 0 także bez procesu).
do_stop() {
    pkill -x flux-wall 2>/dev/null || return 1
    for _ in $(seq 1 20); do
        pgrep -x flux-wall >/dev/null || return 0
        sleep 0.1
    done
    pkill -9 -x flux-wall 2>/dev/null
}

do_start() {
    local quiet="$1"; shift
    if [[ ! -x "$BIN" ]]; then
        [[ "$quiet" == quiet ]] && exit 0
        echo "flux-wall.sh: brak binarki $BIN — uruchom ./install/install.sh (krok [9.6]) albo 'make' w src/flux-wall" >&2
        exit 2
    fi
    if ! resolve; then
        do_stop
        [[ "$quiet" == quiet ]] && exit 0
        echo "flux-wall.sh: nic do uruchomienia (animacja wyłączona albo rice bez autostartu; Super+W → Animation)" >&2
        exit 4
    fi
    do_stop
    audio_args
    dither_args
    ready_args
    [[ -z "$READY" ]] || rm -f "$READY"
    # shellcheck disable=SC2086  # FLUX_WALL_ARGS to celowo lista argumentów
    setsid "$BIN" -s "$SHADER" "${PALETTE_ARGS[@]}" "${AUDIO_ARGS[@]}" "${DITHER_ARGS[@]}" "${READY_ARGS[@]}" $FLUX_WALL_ARGS "$@" >"$LOG" 2>&1 &
    local child=$! rc
    # autostart/restore: cicho, jak dawniej (0,5 s i kod 0 — wyniku nikt nie melduje)
    if [[ "$quiet" == quiet ]]; then sleep 0.5; exit 0; fi
    wait_ready "$child"; rc=$?
    if ((rc == 0)); then
        echo "flux-wall działa: $(basename "$SHADER" .frag) (log: $LOG)"
        exit 0
    fi
    if ((rc == 2)); then
        echo "flux-wall nie potwierdził pierwszej klatki w ${READY_TIMEOUT} s (proces żyje, zostawiony) — ostatnie linie logu:" >&2
    elif ((rc == 3)); then
        echo "flux-wall uruchomiony, ale pierwszej klatki nie potwierdzę: brak prywatnego katalogu sesji (scripts/lib/runtime-dir.sh), więc bez pliku gotowości i logu (proces żyje, zostawiony)" >&2
    else
        echo "flux-wall NIE wystartował — ostatnie linie logu:" >&2
    fi
    tail -5 "$LOG" >&2
    exit 3
}

# Zrzut stanu do diagnozy „animacje nie działają / nie ma ich w menu" — jedno
# polecenie zamiast pięciu pytań (wzorzec scripts/hypr/workspace-diag.sh).
# Tylko odczyt. Najczęstsze przyczyny, które ma wyłapać: klon za origin
# (brak shaderów), binarka sprzed kontraktu audio (git pull bez install.sh —
# rozpoznawana po nazwie uniformu `audio_wave_peak` w pliku), stary wybór
# w flux-wall.dat, proces, który nie wstał (log).
doctor() {
    local newest_src bin_ok=0 n_all n_audio choice rice=""
    echo "== repo"
    if command -v git >/dev/null 2>&1 && git -C "$ARCHENEMY_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$ARCHENEMY_DIR" log --oneline -1 2>/dev/null
        git -C "$ARCHENEMY_DIR" status -sb 2>/dev/null | head -1
    else
        echo "$ARCHENEMY_DIR: nie jest repozytorium gita"
    fi
    echo "== binarka"
    if [[ -x "$BIN" ]]; then
        bin_ok=1
        echo "$BIN  ($(stat -c '%y' "$BIN" 2>/dev/null | cut -d. -f1))"
        newest_src="$(ls -t "$ARCHENEMY_DIR"/src/flux-wall/*.c "$ARCHENEMY_DIR"/src/flux-wall/*.h 2>/dev/null | head -1)"
        if [[ -n "$newest_src" && "$newest_src" -nt "$BIN" ]]; then
            echo "  ⚠ źródła nowsze niż binarka (${newest_src##*/}) — uruchom ./install/install.sh albo make -C src/flux-wall"
        fi
        if grep -a -q 'audio_wave_peak' "$BIN"; then
            echo "  kontrakt audio: stereo + przebieg (audio_wave) — aktualny"
        else
            echo "  ⚠ binarka NIE zna audio_wave — sprzed 2026-09-17; oscyloskop i nowe wizualizacje nie zadziałają, przebuduj"
        fi
    else
        echo "⚠ brak $BIN — ./install/install.sh (krok [9.6]) albo make -C src/flux-wall"
    fi
    echo "== shadery ($SHADERS_DIR)"
    n_all="$(list_shaders | wc -l)"; n_audio="$(list_audio_shaders | wc -l)"
    echo "animacji: $n_all, w tym wizualizacji muzyki: $n_audio"
    list_audio_shaders | sed 's/^/  ♪ /'
    echo "== wybór"
    choice="$(read_choice)"
    [[ -f "$CURRENT_RICE_FILE" ]] && { rice="$(<"$CURRENT_RICE_FILE")"; rice="${rice//[[:space:]]/}"; }
    echo "rice: ${rice:-<brak .current_rice>}"
    if [[ -z "$choice" ]]; then
        echo "flux-wall.dat: <brak pliku> → domyślne zachowanie rice'a"
    elif [[ "$choice" == "off" ]]; then
        echo "flux-wall.dat: off"
    elif shader_path "$choice" >/dev/null; then
        echo "flux-wall.dat: $choice (plik istnieje)"
    else
        echo "flux-wall.dat: $choice  ⚠ takiego shadera nie ma — wrapper cofnie się do domyślnego rice'a"
    fi
    load_rice_conf && echo "flux-wall.conf: PALETTE=${FLUX_WALL_PALETTE:-<brak>} SHADER=${FLUX_WALL_SHADER:-<brak>} AUTOSTART=$FLUX_WALL_AUTOSTART DITHER=$FLUX_WALL_DITHER ARGS=${FLUX_WALL_ARGS:-<brak>}"
    echo "== proces"
    if pgrep -x flux-wall >/dev/null 2>&1; then
        echo "flux-wall działa (pid $(pgrep -x flux-wall | tr '\n' ' '))"
    else
        echo "flux-wall nie działa"
    fi
    # Bez prywatnego katalogu sesji LOG to /dev/null — powiedz to wprost, zamiast
    # „brak /dev/null (proces nigdy nie wystartował…)”.
    if [[ -z "$RUN_DIR" ]]; then
        echo "== log: brak prywatnego katalogu sesji (scripts/lib/runtime-dir.sh), więc log nie jest zapisywany"
    elif [[ -f "$LOG" ]]; then
        echo "== log ($LOG, ostatnie 10 linii)"
        tail -10 "$LOG"
    else
        echo "== log: brak $LOG (proces nigdy nie wystartował z wrappera w tej sesji)"
    fi
    [[ $bin_ok -eq 1 ]]
}

case "${1:-}" in
    autostart|restore) shift; do_start quiet "$@" ;;
    start)             shift; do_start loud "$@" ;;
    select)
        name="${2:-}"
        if [[ -z "$name" ]] || ! shader_path "$name" >/dev/null; then
            echo "flux-wall.sh: nieznana animacja '${name}'. Dostępne: $(list_shaders | tr '\n' ' ')" >&2
            exit 1
        fi
        write_choice "$name" || exit 1
        exec "$0" start
        ;;
    off)
        write_choice off || exit 1
        do_stop && echo "animacja wyłączona" || echo "animacja wyłączona (nie działała)"
        ;;
    list)      list_shaders ;;
    list-audio) list_audio_shaders ;;
    stop)      do_stop && echo "flux-wall zatrzymany" || echo "flux-wall nie działał" ;;
    status)    pgrep -x flux-wall >/dev/null ;;
    doctor)    doctor ;;
    *)         echo "Użycie: flux-wall.sh autostart|restore | select <nazwa> | off | list | list-audio | start [opcje] | stop | status | doctor" >&2; exit 1 ;;
esac
