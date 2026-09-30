#!/bin/bash

# =============================================
#   archenemy - window-history.sh
#   Przywracanie ostatnio zamkniętych aplikacji (Super+Tab).
#
#   Hyprland nie pamięta zamkniętych okien, a po `closewindow` okna nie ma
#   już w `hyprctl clients` — z czego je odtworzyć, trzeba wiedzieć WCZEŚNIEJ.
#   Dlatego demon (start z hl.on("hyprland.start") we wspólnym
#   autostart-common.lua) trzyma migawkę otwartych okien: adres, PID,
#   klasę, komendę (/proc/<pid>/cmdline) i katalog roboczy procesu. Gdy
#   okno znika z listy, a jego proces nie ma już żadnego innego okna,
#   wpis trafia na stos zamkniętych (najnowszy na końcu, max MAX_ENTRIES).
#
#   `restore` (bind Super+Tab w każdym ricu parytetu) zdejmuje najnowszy
#   wpis, którego proces już NIE żyje, i uruchamia komendę ponownie w tym
#   samym katalogu, na bieżącym workspasie. Wpisy żywych procesów są
#   pomijane (zostają na stosie): okno zamknięte do zasobnika (Steam,
#   Discord), okno dialogowe portalu czy agenta polkit to nie „zamknięta
#   aplikacja” — ponowne uruchomienie dałoby drugą instancję demona.
#   Kolejne Super+Tab sięgają coraz dalej wstecz (jak Ctrl+Shift+T).
#
#   Źródła komendy, w kolejności:
#     * klasa steam_app_<id> (gry Steama) → `steam steam://rungameid/<id>`
#       — binarka gry uruchomiona bez Steama/Protona zwykle nie wstaje,
#     * proces we flatpaku (/proc/<pid>/root/.flatpak-info) →
#       `flatpak run <id>` — ścieżka z wnętrza piaskownicy nie istnieje
#       na hoście,
#     * inaczej dosłowne argv procesu.
#   Pomijane: własne okna narzędzi archenemy (klasa archenemy-*, np. TUI
#   Super+A) i okna bez PID.
#
#   Stan żyje tylko w sesji: $XDG_RUNTIME_DIR/archenemy-window-history/
#   (tmpfs, 0700, znika po wylogowaniu). Komendy mogą zawierać ścieżki
#   plików — nie zapisujemy ich na dysk. Środowiska procesu nie
#   odtwarzamy (może zawierać sekrety).
#
#   Wywołanie:
#     window-history.sh daemon    demon (jedna instancja na sesję, flock)
#     window-history.sh restore   przywróć ostatnio zamkniętą aplikację
#     window-history.sh list      stos zamkniętych (najnowsze na dole)
#     window-history.sh refresh   jednorazowa migawka (testy / ręcznie)
#   Testy: bash tests/window-history.sh
# =============================================

set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
STATE_DIR="$RUNTIME/archenemy-window-history"
OPEN_TSV="$STATE_DIR/open.tsv"       # adres  pid  start  klasa  cwd  komenda
CLOSED_TSV="$STATE_DIR/closed.tsv"   # pid  start  czas_zamknięcia  klasa  cwd  komenda
STATE_LOCK="$STATE_DIR/.lock"
SESSION_ID="$STATE_DIR/session"      # HYPRLAND_INSTANCE_SIGNATURE, do którego należy stan
DAEMON_LOCK="$RUNTIME/archenemy-window-history.lock"
MAX_ENTRIES=20
# Po Super+Q proces potrzebuje chwili, żeby umrzeć. Świeżo zamknięty wpis
# z wciąż żywym procesem czeka na jego śmierć najwyżej tyle sekund, zanim
# `restore` uzna go za aplikację działającą w tle.
EXIT_GRACE="${ARCHENEMY_WH_EXIT_GRACE:-2}"   # hak testowy

mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
touch "$OPEN_TSV" "$CLOSED_TSV"

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send -u low "archenemy" "$1"
}

# Czas startu procesu (pole 22 /proc/<pid>/stat) — odróżnia proces od
# innego, który po nim dostał ten sam PID. Pusty = proces nie istnieje.
# comm w nawiasach może zawierać spacje, więc tniemy po OSTATNIM ')'.
proc_start() {
    local stat
    stat=$(cat "/proc/$1/stat" 2>/dev/null) || return 0
    stat="${stat##*) }"
    # shellcheck disable=SC2086  # celowy podział na pola
    set -- $stat
    # $1 = stan (pole 3), $20 = starttime (pole 22). Zombie = już martwy.
    [[ "$1" == Z ]] && return 0
    printf '%s' "${20:-}"
}

proc_alive() {   # pid start → 0, gdy TEN SAM proces nadal działa
    local now
    now=$(proc_start "$1")
    [[ -n "$now" && "$now" == "$2" ]]
}

# Komenda do ponownego uruchomienia, jako jeden napis w formacie `printf %q`
# (bezpieczny do `eval` — każdy argument osobno zacytowany).
capture_cmd() {
    local pid="$1" class="$2" name="" line
    if [[ "$class" =~ ^steam_app_([1-9][0-9]*)$ ]]; then
        printf '%q %q' steam "steam://rungameid/${BASH_REMATCH[1]}"
        return
    fi
    if [[ -r "/proc/$pid/root/.flatpak-info" ]]; then
        while IFS= read -r line; do
            [[ "$line" == name=* ]] && { name="${line#name=}"; break; }
        done < "/proc/$pid/root/.flatpak-info"
        if [[ -n "$name" ]]; then
            printf '%q %q %q' flatpak run "$name"
            return
        fi
    fi
    local -a argv=()
    mapfile -d '' -t argv < "/proc/$pid/cmdline" 2>/dev/null || return 0
    ((${#argv[@]})) || return 0
    printf '%q ' "${argv[@]}"
}

# Jedno przejście: migawka okien → wykrycie zamkniętych → nowa migawka.
# Wołać pod blokadą STATE_LOCK.
refresh_locked() {
    local clients
    clients=$(hyprctl clients 2>/dev/null) || return 0
    # Zero okien to dosłownie "no open windows" (HyprCtl.cpp clientsRequest).
    # Każdy inny wynik bez "Window " (błąd, kompozytor nie odpowiada) = nie
    # ruszamy stanu — inaczej „zamknęlibyśmy” naraz wszystkie okna.
    [[ "$clients" == *"Window "* || "$clients" == "no open windows" ]] || return 0

    # Format tekstowy wg src/debug/HyprCtl.cpp v0.56.2: "Window <adres> -> <tytuł>:"
    # i pola po tabulatorze; lista obejmuje tylko okna zmapowane.
    local -A cur_pid=() cur_class=() pid_has_window=()
    local addr="" line
    while IFS= read -r line; do
        case "$line" in
            'Window '*' -> '*)
                addr="${line#Window }"
                addr="${addr%% *}"
                ;;
            $'\tclass: '*)
                [[ -n "$addr" ]] && cur_class["$addr"]="${line#$'\tclass: '}"
                ;;
            $'\tpid: '*)
                [[ -n "$addr" ]] || continue
                cur_pid["$addr"]="${line#$'\tpid: '}"
                pid_has_window["${cur_pid[$addr]}"]=1
                ;;
        esac
    done <<< "$clients"

    local tmp_open tmp_closed now pid start class cwd cmd
    tmp_open=$(mktemp "$OPEN_TSV.XXXXXX") || return 0
    now=$(date +%s)
    local -a closed_new=()
    local -A known=() queued=()

    # Poprzednia migawka: okno, którego nie ma (albo pod tym samym adresem
    # siedzi już inny proces), jest zamknięte.
    while IFS=$'\t' read -r addr pid start class cwd cmd; do
        [[ -n "$addr" ]] || continue
        if [[ "${cur_pid[$addr]:-}" == "$pid" ]]; then
            known["$addr"]=1
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$addr" "$pid" "$start" "$class" "$cwd" "$cmd" >> "$tmp_open"
            continue
        fi
        [[ -n "$pid" && "$cmd" != - ]] || continue
        # Proces ma jeszcze inne okno (dialog, drugie okno przeglądarki) —
        # aplikacja działa dalej, nie ma czego przywracać.
        [[ -n "${pid_has_window[$pid]:-}" ]] && continue
        # Proces z kilkoma oknami zamkniętymi naraz — jeden wpis.
        [[ -n "${queued[$pid:$start]:-}" ]] && continue
        queued["$pid:$start"]=1
        closed_new+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$pid" "$start" "$now" "$class" "$cwd" "$cmd")")
    done < "$OPEN_TSV"

    # Nowe okna: komendę i katalog trzeba złapać TERAZ, póki proces żyje.
    for addr in "${!cur_pid[@]}"; do
        [[ -n "${known[$addr]:-}" ]] && continue
        pid="${cur_pid[$addr]}"
        class="${cur_class[$addr]:-}"
        class="${class//$'\t'/ }"
        # Puste pole = "-": tabulator jest białym znakiem IFS, więc `read`
        # skleja sąsiednie tabulatory i puste pole przesunęłoby kolumny.
        [[ -n "$class" ]] || class="-"
        start="-" cwd="-" cmd="-"
        if [[ "$pid" =~ ^[1-9][0-9]*$ && "$class" != archenemy-* ]]; then
            start=$(proc_start "$pid")
            if [[ -n "$start" ]]; then
                cmd=$(capture_cmd "$pid" "$class")
                [[ -n "$cmd" ]] || cmd="-"
                cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null) || cwd=""
                cwd=$(printf '%q' "$cwd")
            else
                start="-"
            fi
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$addr" "$pid" "$start" "$class" "$cwd" "$cmd" >> "$tmp_open"
    done
    mv "$tmp_open" "$OPEN_TSV"

    ((${#closed_new[@]})) || return 0
    # Stos: ten sam proces (PID + start) tylko raz — np. demon portalu, który
    # zamknął kilka okien dialogowych, zajmuje jedno miejsce, nie dziesięć.
    # Starszy wpis tego samego procesu wypada, nowy idzie na wierzch.
    tmp_closed=$(mktemp "$CLOSED_TSV.XXXXXX") || return 0
    while IFS= read -r line; do
        IFS=$'\t' read -r pid start _ <<< "$line"
        [[ -n "$pid" && -z "${queued[$pid:$start]:-}" ]] && printf '%s\n' "$line"
    done < "$CLOSED_TSV" > "$tmp_closed"
    printf '%s\n' "${closed_new[@]}" >> "$tmp_closed"
    tail -n "$MAX_ENTRIES" "$tmp_closed" > "$CLOSED_TSV"
    rm -f "$tmp_closed"
}

refresh() {
    (
        flock -w 5 9 || exit 0
        refresh_locked
    ) 9>"$STATE_LOCK"
}

# Zdejmuje ze stosu najnowszy wpis martwego procesu i wypisuje go
# (klasa<TAB>cwd<TAB>komenda). Pusty wynik = nic do przywrócenia.
pop_entry() {
    (
        flock -w 5 9 || exit 0
        refresh_locked
        local -a lines=()
        mapfile -t lines < "$CLOSED_TSV"
        local i pid start closed_at class cwd cmd now
        for ((i = ${#lines[@]} - 1; i >= 0; i--)); do
            IFS=$'\t' read -r pid start closed_at class cwd cmd <<< "${lines[$i]}"
            [[ -n "$cmd" && "$cmd" != - ]] || continue
            if proc_alive "$pid" "$start"; then
                # Świeżo zamknięte okno: daj procesowi chwilę na wyjście.
                now=$(date +%s)
                while proc_alive "$pid" "$start" && (( now - closed_at < EXIT_GRACE )); do
                    sleep 0.1
                    now=$(date +%s)
                done
                proc_alive "$pid" "$start" && continue
            fi
            unset 'lines[i]'
            if ((${#lines[@]})); then
                printf '%s\n' "${lines[@]}" > "$CLOSED_TSV"
            else
                : > "$CLOSED_TSV"
            fi
            printf '%s\t%s\t%s\n' "$class" "$cwd" "$cmd"
            exit 0
        done
    ) 9>"$STATE_LOCK"
}

restore() {
    local entry class cwd cmd dir
    entry=$(pop_entry)
    if [[ -z "$entry" ]]; then
        notify "Nothing to restore"
        return 0
    fi
    IFS=$'\t' read -r class cwd cmd <<< "$entry"
    [[ "$class" != - ]] || class="window"

    local -a argv=()
    eval "argv=($cmd)"
    if ! command -v "${argv[0]}" >/dev/null 2>&1; then
        notify "Can't restore ${class}: ${argv[0]} not found"
        return 1
    fi
    eval "dir=$cwd"
    [[ -n "$dir" && -d "$dir" ]] || dir="$HOME"
    # Blokada stanu jest już zwolniona (pop_entry to podpowłoka), więc
    # uruchamiana aplikacja nie dziedziczy deskryptora 9 — gdyby dziedziczyła,
    # trzymałaby blokadę do końca życia i demon stanąłby na flocku.
    ( cd "$dir" && setsid -f "${argv[@]}" </dev/null >/dev/null 2>&1 )
}

list() {
    local pid start closed_at class cwd cmd state
    while IFS=$'\t' read -r pid start closed_at class cwd cmd; do
        [[ -n "$pid" ]] || continue
        state="closed"
        proc_alive "$pid" "$start" && state="running"
        printf '%s\t%s\t%s\n' "$state" "$class" "$cmd"
    done < "$CLOSED_TSV"
}

daemon() {
    # Jedna instancja demona na sesję.
    exec 8>"$DAEMON_LOCK" || exit 0
    flock -n 8 || exit 0

    # Start razem z kompozytorem — poczekaj, aż hyprctl odpowiada.
    for _ in $(seq 1 50); do
        hyprctl monitors &>/dev/null && break
        sleep 0.2
    done
    # XDG_RUNTIME_DIR przeżywa ponowne zalogowanie, gdy trwa inna sesja
    # użytkownika (np. SSH). Migawka z poprzedniego Hyprlanda „zamknęłaby”
    # wtedy naraz wszystkie jego okna — nowy kompozytor = czysty stan.
    (
        flock -w 5 9 || exit 0
        if [[ "$(cat "$SESSION_ID" 2>/dev/null)" != "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
            : > "$OPEN_TSV"
            : > "$CLOSED_TSV"
            printf '%s\n' "${HYPRLAND_INSTANCE_SIGNATURE:-}" > "$SESSION_ID"
        fi
    ) 9>"$STATE_LOCK"
    refresh

    local sock="$RUNTIME/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"
    if command -v socat >/dev/null 2>&1 && [[ -S "$sock" ]]; then
        # openwindow/closewindow nie mają wariantu v2 (Window.cpp v0.56.2 —
        # jedno postEvent na zdarzenie). Paczkę zdarzeń (np. zamknięcie kilku
        # okien naraz) zbieramy do jednego przejścia.
        socat -U - "UNIX-CONNECT:$sock" 2>/dev/null | while IFS= read -r line; do
            case "$line" in
                'openwindow>>'*|'closewindow>>'*)
                    while IFS= read -r -t 0.05 line; do :; done
                    refresh
                    ;;
            esac
        done
    else
        # Awaryjnie (brak socat / socketa): sonda co 2 s. `restore` i tak
        # robi własne przejście, więc przywracanie działa — gubi się tylko
        # okno otwarte i zamknięte między dwiema sondami.
        local fails=0
        while sleep 2; do
            if hyprctl monitors &>/dev/null; then
                fails=0
                refresh
            else
                # Hyprland nie żyje — nie trzymaj blokady następnej sesji.
                fails=$((fails + 1))
                (( fails >= 5 )) && exit 0
            fi
        done
    fi
}

case "${1:-}" in
    daemon)  daemon ;;
    restore) restore ;;
    list)    list ;;
    refresh) refresh ;;
    *)
        echo "Usage: $(basename "$0") daemon|restore|list|refresh" >&2
        exit 2
        ;;
esac
