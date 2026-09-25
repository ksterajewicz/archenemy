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
#     flux-wall.sh start [opcje]         jak restore, ale głośno; opcje → flux-wall
#     flux-wall.sh stop | status
#     flux-wall.sh doctor               zrzut stanu do diagnozy (repo, binarka,
#                                        shadery, wybór, proces, log) — tylko odczyt
#
#   Kody: 0 ok · 1 użycie/zła nazwa · 2 brak binarki · 3 start nieudany (log) ·
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
LOG="${XDG_RUNTIME_DIR:-/tmp}/flux-wall.log"

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
do_stop() {
    pkill -x flux-wall 2>/dev/null
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
    # shellcheck disable=SC2086  # FLUX_WALL_ARGS to celowo lista argumentów
    setsid "$BIN" -s "$SHADER" "${PALETTE_ARGS[@]}" "${AUDIO_ARGS[@]}" "${DITHER_ARGS[@]}" $FLUX_WALL_ARGS "$@" >"$LOG" 2>&1 &
    sleep 0.5
    if pgrep -x flux-wall >/dev/null; then
        [[ "$quiet" == quiet ]] || echo "flux-wall działa: $(basename "$SHADER" .frag) (log: $LOG)"
        exit 0
    fi
    [[ "$quiet" == quiet ]] && exit 0
    echo "flux-wall NIE wystartował — ostatnie linie logu:" >&2
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
    if [[ -f "$LOG" ]]; then
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
