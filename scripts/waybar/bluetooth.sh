#!/usr/bin/env bash
# =============================================
#   archenemy - bluetooth.sh
#   Opcjonalny moduł strumieniowy waybara; SIGUSR1 odświeża flagę.
#   Źródła: man waybar-custom(5), bluetoothctl(1), dbus-monitor(1).
#
#   Trwały wybór zasilania (2026-11-19, B2): data/bluetooth-power.dat
#   (on|off, warstwa maszynowa poza gitem, zapis atomowy mktemp + mv) to
#   ŹRÓDŁO PRAWDY o woli użytkownika. BlueZ zasilania nie pamięta (brak klucza
#   Powered w /var/lib/bluetooth), a AutoEnable (domyślnie true od 5.65)
#   włącza kontroler przy każdym jego pojawieniu się: start bluetoothd,
#   hotplug, ponowna rejestracja po wybudzeniu; rfkill unblock też włącza.
#   Dlatego strumień:
#   - po zdarzeniach systemowych (start strumienia = logowanie/restart paska,
#     kontroler się pojawia, bluetoothd wstaje, PrepareForSleep(false) logind,
#     koniec blokady rfkill) otwiera OKNO o długości WINDOW s: wyrównuje stan
#     do pliku, a włączenie no→yes przy "off" cofa (power off, najwyżej
#     ENFORCE_MAX prób na okno — bez pętli) i NIE zapisuje go jako woli;
#   - poza oknem każdą zmianę Powered (bluetui, blueman, telefon) zapisuje do
#     pliku po CONFIRM s, jeśli stan się utrzymał i w międzyczasie nie było
#     zdarzenia systemowego — bluetoothd przy SIGTERM sam wyłącza kontroler
#     (adapter_shutdown), a PrepareForSleep/Shutdown(true) zamrażają zapis.
#   Okna są zakotwiczone w zdarzeniach, które widzą wszystkie strumienie
#   (każdy pasek = osobny proces), więc dwa paski decydują tak samo. Okno
#   startu strumienia liczy się od startu bluetoothd (ps etimes): nowy pasek
#   przy starym bluetoothd nie cofa włączenia, które drugi pasek zapisuje.
#   Przypadki graniczne z przeglądu B3 (B4, 2026-11-20): zmiana w trakcie
#   potwierdzania jest ogłaszana innym paskom (PENDING_FILE) — pasek
#   startujący w tym czasie ją przejmuje, zamiast cofać (F1); jedna blokada
#   flock obejmuje PPM (odczyt, zapis, power, wycofanie) oraz zapisy i power
#   strumieni (F2).
#   RMB zapisuje plik PRZED zmianą zasilania, więc nigdy nie jest cofany.
#   "on" w oknie: kontroler wyłączony jest włączany (potrzebne przy
#   AutoEnable=false). Brak pliku/śmieci = brak egzekwowania; brak flagi
#   ikony = nic. Reset: rm data/bluetooth-power.dat.
# =============================================
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLAG="$ROOT/data/bluetooth-enabled.dat"
POWER_FILE="$ROOT/data/bluetooth-power.dat"
# Wspólny stan pasków (B4): katalog sesji (tmpfs użytkownika), bez niego data/.
STATE_DIR=${XDG_RUNTIME_DIR:-}
[[ -n "$STATE_DIR" && -d "$STATE_DIR" && -w "$STATE_DIR" ]] || STATE_DIR=${POWER_FILE%/*}
PENDING_FILE="$STATE_DIR/archenemy-bluetooth.pending"
LOCK_FILE="$STATE_DIR/archenemy-bluetooth.lock"
LOCK_WAIT=8
WINDOW=15
CONFIRM=2
ENFORCE_MAX=3
# Haki testowe tylko z ARCHENEMY_TEST=1 (tests/bluetooth.sh).
if [[ "${ARCHENEMY_TEST:-}" == 1 ]]; then
    [[ "${ARCHENEMY_BT_WINDOW:-}" =~ ^[0-9]+$ ]] && WINDOW=$ARCHENEMY_BT_WINDOW
    [[ "${ARCHENEMY_BT_CONFIRM:-}" =~ ^[0-9]+$ ]] && CONFIRM=$ARCHENEMY_BT_CONFIRM
fi
monitor_pid=''
sleeper=''
cleanup() {
    [[ -z "$monitor_pid" ]] || kill "$monitor_pid" 2>/dev/null || :
    [[ -z "$sleeper" ]] || kill "$sleeper" 2>/dev/null || :
    [[ -z "$monitor_pid" ]] || wait "$monitor_pid" 2>/dev/null || :
    [[ -z "$sleeper" ]] || wait "$sleeper" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP

# $1 (opcjonalny) = migawka "bluetoothctl show" z tick — jedno show na serię.
render() {
    local info devices state=disabled icon='󰂲' tooltip='Bluetooth: off'
    if [[ ! -f "$FLAG" ]] || ! command -v bluetoothctl >/dev/null \
        || ! command -v timeout >/dev/null || ! command -v python >/dev/null; then
        printf '{"text":"","class":"off"}\n'
        return
    fi
    if (( $# )); then info=$1; else info=$(timeout 3 bluetoothctl show 2>/dev/null) || info=''; fi
    if [[ "$info" != *'Controller '* ]]; then
        printf '{"text":"","class":"off"}\n'
        return
    fi
    if [[ "$info" == *'Powered: yes'* ]]; then
        state=enabled; icon='󰂯'; tooltip='Bluetooth: on'
        devices=$(timeout 3 bluetoothctl devices Connected 2>/dev/null) || devices=''
        # BlueZ miesza rekordy z komunikatami asynchronicznymi na stdout.
        devices=$(python -c 'import re,sys
text = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", sys.stdin.read())
text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text).replace("\r", "")
for line in text.splitlines():
    match = re.fullmatch(r"Device (?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2} (\S.*)", line)
    if match:
        print(match[1])' <<< "$devices")
        if [[ -n "$devices" ]]; then
            state=connected; icon='󰂱'
            tooltip="Bluetooth: connected"$'\n'"$devices"
        fi
    fi
    # Nazwy urządzeń są niezaufane: osobno kodowanie JSON i escapowanie Pango.
    python -c 'import html,json,sys; print(json.dumps(dict(text=sys.argv[1], **{"class":sys.argv[2]}, tooltip=html.escape(sys.argv[3])+"\nLMB: bluetui · RMB: power on/off")))' "$icon" "$state" "$tooltip"
}
trap render USR1

# Wybór z pliku: dokładnie "on" albo "off", z końcowym \n albo bez; wszystko
# inne = brak decyzji (kod 1). Bajty przez od, bo read po cichu gubi NUL.
power_choice() {
    local bytes
    [[ -f "$POWER_FILE" && -r "$POWER_FILE" ]] || return 1
    bytes=$(od -An -tx1 -N5 -- "$POWER_FILE" 2>/dev/null | tr -d ' \n') || return 1
    case "$bytes" in
        6f6e|6f6e0a)       printf 'on\n' ;;
        6f6666|6f66660a)   printf 'off\n' ;;
        *) return 1 ;;
    esac
}

# Błąd zapisu wyboru: stderr (log waybara) i powiadomienie — PPM nie ma
# innego kanału, a cichy sukces bez pamięci wyboru wróciłby po restarcie.
save_error() {
    printf '%s\n' "$1" >&2
    command -v notify-send >/dev/null 2>&1 && notify-send -u critical "archenemy" "$1"
}

# Blokada transakcji (F2 z B3): odczyt wyboru, zapis, power i wycofanie PPM
# oraz zapisy i power strumieni idą po kolei, więc wycofanie nieudanego PPM
# nie nadpisze nowszego wyboru. Bez flock albo pliku blokady — jak dawniej;
# zajęta dłużej niż LOCK_WAIT s = kod 1 (PPM ma wtedy 2× timeout 3 s).
lock_fd=''
lock_take() {
    [[ -z "$lock_fd" ]] || return 0
    command -v flock >/dev/null 2>&1 || return 0
    { exec {lock_fd}>>"$LOCK_FILE"; } 2>/dev/null || { lock_fd=''; return 0; }
    flock -w "$LOCK_WAIT" "$lock_fd" 2>/dev/null && return 0
    exec {lock_fd}>&-
    lock_fd=''
    return 1
}
lock_drop() {
    [[ -n "$lock_fd" ]] || return 0
    exec {lock_fd}>&-
    lock_fd=''
}

# ─── Egzekwowanie i synchronizacja wyboru (opis w nagłówku) ─────────────────
# Czas w setnych sekundy z /proc/uptime (CLOCK_BOOTTIME: monotoniczny, liczy
# też uśpienie — okno sprzed uśpienia wygasa po wybudzeniu); bez /proc: SECONDS.
now=0
clock() {
    local up=''
    { read -r up _ < /proc/uptime; } 2>/dev/null
    if [[ "$up" =~ ^([0-9]+)\.([0-9]{2}) ]]; then
        now=$(( 10#${BASH_REMATCH[1]} * 100 + 10#${BASH_REMATCH[2]} ))
    else
        now=$(( SECONDS * 100 ))
    fi
}
known=''          # ostatnio widziany stan: on|off|blocked|none ('' = jeszcze nic)
window_until=0    # koniec okna egzekwowania
enforce=0         # 1 = wyrównaj stan do pliku przy najbliższej migawce
enforce_count=0   # polecenia power w bieżącym oknie (limit ENFORCE_MAX)
retry_at=0        # ponowienie nieudanego power
save_value=''     # zmiana czekająca na potwierdzenie
save_at=0
sleeping=0        # PrepareForSleep(true) … (false)
shutting=0        # PrepareForShutdown(true)
snap=''           # migawka z ostatniego tick (dla render)
save_notified=0
save_base=''      # plik w chwili zmiany: nowszy wybór kogoś innego wygrywa
fresh=0           # 1 = pierwsza migawka po starcie strumienia
pending_mine=''   # nasz wpis w PENDING_FILE
p_value=''; p_at=0
# Oczekująca decyzja (F1 z B3): "on|off <termin>" w PENDING_FILE. Zmiana spoza
# paska czeka CONFIRM s; pasek startujący w tym czasie (drugi monitor, restart
# waybara) przejmuje ją zamiast cofać do starego pliku. Wpis zostaje po wyjściu
# strumienia — właśnie restart paska musi go zobaczyć; nieaktualny wygasa.
pending_set() {
    local tmp
    pending_mine="$1 $2"
    tmp=$(mktemp "$PENDING_FILE.XXXXXX" 2>/dev/null) || return 0
    if ! { printf '%s\n' "$pending_mine" > "$tmp" && mv -f "$tmp" "$PENDING_FILE"; } 2>/dev/null; then
        rm -f "$tmp"
    fi
}
pending_drop() {
    local line=''
    save_value=''; save_at=0
    [[ -n "$pending_mine" ]] || return 0
    { read -r line < "$PENDING_FILE"; } 2>/dev/null
    [[ "$line" != "$pending_mine" ]] || rm -f "$PENDING_FILE"
    pending_mine=''
}
# Świeży wpis innego paska: termin w przyszłości, ale nie dalej niż CONFIRM
# (wpis sprzed restartu systemu w data/ ma termin z innego uptime).
pending_get() {
    local line=''
    { read -r line < "$PENDING_FILE"; } 2>/dev/null
    [[ "$line" =~ ^(on|off)\ ([0-9]+)$ ]] || return 1
    p_value=${BASH_REMATCH[1]}; p_at=$(( 10#${BASH_REMATCH[2]} ))
    (( p_at > now && p_at <= now + CONFIRM * 100 + 100 ))
}
open_window() {
    clock
    (( now + WINDOW * 100 > window_until )) && window_until=$(( now + WINDOW * 100 ))
    enforce=1; enforce_count=0; retry_at=0
    pending_drop
}
# Okno startu strumienia od startu bluetoothd: AutoEnable działa tuż po nim.
# Wiek nieznany (brak ps albo procesu) = okno od teraz, bo "off" ma wygrać.
start_window() {
    local age=''
    command -v ps >/dev/null 2>&1 && age=$(ps -o etimes= -C bluetoothd 2>/dev/null | head -n 1)
    age=${age//[[:space:]]/}
    clock
    enforce=1; enforce_count=0; retry_at=0
    if [[ "$age" =~ ^[0-9]+$ ]]; then
        (( age < WINDOW )) && window_until=$(( now + (WINDOW - age) * 100 ))
    else
        window_until=$(( now + WINDOW * 100 ))
    fi
}
# Klasyfikacja linii dbus-monitor; sygnał = nagłówek "signal … member=X",
# argumenty w kolejnych liniach. Ścieżka adaptera, nie urządzenia (dev_*).
ev_arg=''
classify() {
    local line=$1
    case "$line" in
        signal*member=PrepareForSleep*)    ev_arg='sleep'; return ;;
        signal*member=PrepareForShutdown*) ev_arg=shutdown; return ;;
        signal*member=InterfacesAdded*|signal*member=InterfacesRemoved*) ev_arg=object; return ;;
        signal*member=NameOwnerChanged*)   ev_arg=''; open_window; return ;;
        signal*) ev_arg=''; return ;;
    esac
    case "$ev_arg" in
        sleep)
            if [[ "$line" =~ ^[[:space:]]*boolean\ true$ ]]; then sleeping=1; pending_drop
            elif [[ "$line" =~ ^[[:space:]]*boolean\ false$ ]]; then sleeping=0; open_window; fi ;;
        shutdown)
            if [[ "$line" =~ ^[[:space:]]*boolean\ true$ ]]; then shutting=1; pending_drop
            elif [[ "$line" =~ ^[[:space:]]*boolean\ false$ ]]; then shutting=0; fi ;;
        object)
            [[ "$line" =~ ^[[:space:]]*object\ path\ \"/org/bluez/hci[0-9]+\"$ ]] && open_window ;;
    esac
    ev_arg=''
}
# $1 = zmiana do zapisu, $2 = plik w chwili zmiany. Pod blokadą: plik inny
# niż wtedy = nowszy wybór (PPM, inny pasek) — ten wygrywa, nic nie piszemy.
save_choice() {
    local tmp file
    if lock_take; then
        file=$(power_choice) || file=''
        if [[ "$file" == "$1" || "$file" != "$2" ]]; then lock_drop; return 0; fi
        mkdir -p "${POWER_FILE%/*}" 2>/dev/null
        if tmp=$(mktemp "$POWER_FILE.XXXXXX" 2>/dev/null); then
            chmod 644 "$tmp" 2>/dev/null
            if printf '%s\n' "$1" > "$tmp" 2>/dev/null && mv -f "$tmp" "$POWER_FILE" 2>/dev/null; then
                lock_drop
                return 0
            fi
            rm -f "$tmp"
        fi
        lock_drop
    fi
    # Zasilania nie ruszamy; powiadomienie raz na strumień, stderr zawsze.
    if (( save_notified )); then
        printf '%s\n' "Bluetooth was turned $1 outside the bar, but the choice was not saved (cannot write $POWER_FILE)." >&2
    else
        save_notified=1
        save_error "Bluetooth was turned $1 outside the bar, but the choice was not saved (cannot write $POWER_FILE)."
    fi
    return 1
}
# Jedna migawka na serię zdarzeń albo termin timera. Zwraca 0, gdy zmieniła
# zasilanie (trzeba nowej migawki do render).
tick() {
    local cur choice want in_window=0 adopt=$fresh
    fresh=0
    snap=''
    if [[ ! -f "$FLAG" ]] || ! command -v bluetoothctl >/dev/null || ! command -v timeout >/dev/null; then
        known=''; pending_drop
        return 1
    fi
    snap=$(timeout 3 bluetoothctl show 2>/dev/null) || snap=''
    if [[ "$snap" != *'Controller '* ]]; then cur=none
    elif [[ "$snap" == *'PowerState: off-blocked'* ]]; then cur=blocked
    elif [[ "$snap" == *'Powered: yes'* ]]; then cur=on
    else cur=off; fi
    clock
    # Pojawienie się kontrolera i koniec blokady rfkill to zdarzenia systemowe
    # nawet bez sygnału (np. szybki replug zlany w jedną serię).
    if [[ "$known" == none && "$cur" != none ]] || [[ "$known" == blocked && "$cur" != blocked ]]; then
        open_window
    fi
    (( now < window_until )) && in_window=1
    if [[ "$cur" == none || "$cur" == blocked ]]; then
        [[ "$known" == "$cur" ]] || pending_drop
        known=$cur
        return 1
    fi
    choice=$(power_choice) || choice=''
    if (( shutting )); then known=$cur; return 1; fi
    if (( in_window )) && [[ "$known" == off && "$cur" == on && "$choice" == off ]]; then
        enforce=1    # AutoEnable po zdarzeniu systemowym
    elif (( ! sleeping )) && [[ ( "$known" == on || "$known" == off ) && "$cur" != "$known" ]]; then
        # Poza oknem każda zmiana; w oknie tylko yes→no (system sam nie wyłącza,
        # a no→yes w oknie przy "on"/braku decyzji to AutoEnable).
        if (( ! in_window )) || [[ "$cur" == off ]]; then
            save_value=$cur; save_at=$(( now + CONFIRM * 100 ))
            save_base=$(power_choice) || save_base=''
            pending_set "$save_value" "$save_at"
        fi
    fi
    known=$cur
    if (( enforce )); then
        want=$choice
        if [[ -z "$want" || "$want" == "$cur" ]]; then
            enforce=0
        elif (( adopt )) && pending_get && [[ "$p_value" == "$cur" ]]; then
            # Start strumienia, a inny pasek właśnie potwierdza zmianę spoza paska
            # (F1): przejmujemy ją z jego terminem zamiast cofać do starego pliku.
            enforce=0
            save_value=$cur; save_at=$p_at
            save_base=$(power_choice) || save_base=''
        elif (( retry_at <= now )); then
            if (( enforce_count >= ENFORCE_MAX )); then
                enforce=0
                printf '%s\n' "Bluetooth: gave up turning the controller $want after $ENFORCE_MAX attempts." >&2
            elif ! lock_take; then
                retry_at=$(( now + 100 ))
            else
                # Wybór ponownie pod blokadą: PPM mógł go właśnie zmienić.
                want=$(power_choice) || want=''
                if [[ -z "$want" || "$want" == "$cur" ]]; then
                    enforce=0
                else
                    enforce_count=$(( enforce_count + 1 ))
                    if timeout 3 bluetoothctl power "$want" >/dev/null 2>&1; then
                        lock_drop
                        enforce=0; retry_at=0; known=$want
                        pending_drop
                        return 0
                    fi
                    retry_at=$(( now + 100 ))
                fi
                lock_drop
            fi
        fi
    fi
    if [[ -n "$save_value" ]] && (( save_at <= now )); then
        [[ "$cur" == "$save_value" ]] && (( ! sleeping && ! shutting )) && save_choice "$save_value" "$save_base"
        pending_drop
    fi
    return 1
}
# Najbliższy termin timera jako argument read -t ('' = brak).
next_timeout() {
    local at=0 d
    clock
    [[ -n "$save_value" ]] && at=$save_at
    (( enforce && retry_at > now )) && { (( at == 0 || retry_at < at )) && at=$retry_at; }
    (( at )) || { printf ''; return; }
    d=$(( at - now )); (( d < 1 )) && d=1
    printf '%d.%02d' $(( d / 100 )) $(( d % 100 ))
}
step() {
    if tick; then render; else render "$snap"; fi
}

case "${1:-stream}" in
    status) render; exit ;;
    toggle)
        [[ -f "$FLAG" ]] && command -v bluetoothctl >/dev/null && command -v timeout >/dev/null || exit 0
        # Cała transakcja pod blokadą (F2): drugi PPM czeka na koniec pierwszego.
        if ! lock_take; then
            save_error "Bluetooth power not changed: another Bluetooth power change is still running."
            exit 1
        fi
        info=$(timeout 3 bluetoothctl show 2>/dev/null) || exit 1
        [[ "$info" == *'Controller '* ]] || exit 0
        if [[ "$info" == *'Powered: yes'* ]]; then power=off; else power=on; fi
        # Wybór zapisany PRZED zmianą zasilania: strumień widzi już nową wolę
        # (nie cofa włączenia w oknie), a niezapisywalny data/ to błąd bez
        # żadnej zmiany. Nieudane power = przywrócenie poprzedniego pliku.
        mkdir -p "${POWER_FILE%/*}" 2>/dev/null
        if ! tmp=$(mktemp "$POWER_FILE.XXXXXX"); then
            save_error "Bluetooth power not changed: the choice could not be saved (cannot write $POWER_FILE)."
            exit 1
        fi
        prev=''
        if [[ -e "$POWER_FILE" ]]; then
            if ! { prev=$(mktemp "$POWER_FILE.XXXXXX") && cp -p -- "$POWER_FILE" "$prev" 2>/dev/null; }; then
                rm -f "$tmp" "$prev"
                save_error "Bluetooth power not changed: the choice could not be saved (cannot write $POWER_FILE)."
                exit 1
            fi
        fi
        chmod 644 "$tmp" 2>/dev/null   # mktemp daje 600; jak inne data/*.dat
        if ! { printf '%s\n' "$power" > "$tmp" && mv -f "$tmp" "$POWER_FILE" \
            && [[ "$(power_choice)" == "$power" ]]; }; then
            rm -f "$tmp"
            if [[ -n "$prev" ]]; then mv -f "$prev" "$POWER_FILE"; fi
            save_error "Bluetooth power not changed: the choice could not be saved (cannot write $POWER_FILE)."
            exit 1
        fi
        timeout 3 bluetoothctl power "$power" >/dev/null 2>&1
        rc=$?
        if (( rc != 0 )); then
            # Wycofanie tylko naszego zapisu (bez flock nikt tego nie gwarantuje).
            if [[ "$(power_choice)" == "$power" ]]; then
                if [[ -n "$prev" ]]; then mv -f "$prev" "$POWER_FILE"; else rm -f "$POWER_FILE"; fi
            else
                rm -f "$prev"
            fi
            exit "$rc"
        fi
        [[ -z "$prev" ]] || rm -f "$prev"
        exit 0 ;;
    open)
        [[ -f "$FLAG" ]] && command -v bluetui >/dev/null && command -v alacritty >/dev/null || exit 0
        exec alacritty --class bluetui -e bluetui ;;
esac

start_window
fresh=1
while :; do
    if ! command -v dbus-monitor >/dev/null; then
        step
        # Bez zdarzeń D-Bus: rzadkie odpytywanie, częstsze w oknie i przy timerach.
        clock
        if (( enforce || save_at || now < window_until )); then wait_s=1; else wait_s=60; fi
        sleep "$wait_s" & sleeper=$!
        wait "$sleeper" || :
        sleeper=''
        continue
    fi
    # Subskrypcja przed migawką. ObjectManager obejmuje hotplug kontrolera,
    # NameOwnerChanged ponowny start BlueZ, logind uśpienie i zamknięcie
    # systemu (sygnały rozgłoszeniowe — zwykły AddMatch, bez uprawnień);
    # EOF magistrali uruchamia reconnect.
    exec {events}< <(exec dbus-monitor --system \
        "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'" \
        "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager'" \
        "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.bluez'" \
        "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" \
        "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForShutdown'" 2>/dev/null)
    monitor_pid=$!
    step
    partial=''
    while :; do
        timeout_s=$(next_timeout)
        if IFS= read -r ${timeout_s:+-t "$timeout_s"} -u "$events" line; then
            line=$partial$line; partial=''
            classify "$line"
            if [[ "$line" == signal* ]]; then
                # Jedna migawka po serii; argumenty sygnałów klasyfikujemy, zaległych
                # zmian RSSI nie odtwarzamy.
                while IFS= read -r -t 0.3 -u "$events" line; do classify "$partial$line"; partial=''; done
                partial=$line
                step
            fi
        else
            rc=$?
            # >128: timeout timera albo read przerwany przez SIGUSR1 — nie koniec
            # strumienia. Niepełna linia zostaje na następny odczyt.
            if (( rc > 128 )); then
                partial+=$line
                tick && render
                continue
            fi
            break
        fi
    done
    exec {events}<&-
    wait "$monitor_pid" 2>/dev/null || :
    monitor_pid=''
    sleep 5 & sleeper=$!
    wait "$sleeper" || :
    sleeper=''
done
