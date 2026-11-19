#!/usr/bin/env bash
# =============================================
#   archenemy - bluetooth.sh
#   Opcjonalny moduł strumieniowy waybara; SIGUSR1 odświeża flagę.
#   Źródła: man waybar-custom(5), bluetoothctl(1), dbus-monitor(1).
#
#   Pamięć wyboru PPM (2026-11-19): toggle zapisuje on|off do
#   data/bluetooth-power.dat (warstwa maszynowa poza gitem, atomowo: mktemp
#   + mv). BlueZ sam zasilania nie pamięta: /var/lib/bluetooth/<adapter>/settings
#   nie ma klucza Powered (src/adapter.c, store_adapter_info), a AutoEnable
#   (domyślnie true od BlueZ 5.65, plugins/policy.c) włącza każdy znaleziony
#   kontroler. Dlatego strumień, gdy plik mówi "off", wyłącza kontroler RAZ na
#   start sesji: znacznik z boot_id w prywatnym katalogu sesji
#   (scripts/lib/runtime-dir.sh), więc restart waybara (Super+T, drugi pasek)
#   nie cofa ręcznego włączenia z bluetui/bluemana/telefonu. Na kontroler
#   czekamy najwyżej RESTORE_WAIT s od startu strumienia (BlueZ i kontroler
#   mogą wstać po waybarze — budzi nas zdarzenie D-Bus, bez odpytywania);
#   kontroler obecny, ale wyłączony = jeszcze RESTORE_SETTLE s na spóźnione
#   AutoEnable, potem koniec: późniejsze włączenie to decyzja użytkownika.
#   "on", brak pliku, śmieci, brak flagi ikony, boot_id albo katalogu sesji =
#   nie ingerujemy (zachowanie sprzed tej funkcji). Reset: rm data/bluetooth-power.dat.
# =============================================
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLAG="$ROOT/data/bluetooth-enabled.dat"
POWER_FILE="$ROOT/data/bluetooth-power.dat"
BOOT_ID_FILE=/proc/sys/kernel/random/boot_id
RESTORE_WAIT=120
RESTORE_SETTLE=10
# Haki testowe tylko z ARCHENEMY_TEST=1 (tests/bluetooth.sh).
if [[ "${ARCHENEMY_TEST:-}" == 1 ]]; then
    BOOT_ID_FILE="${ARCHENEMY_BOOT_ID_FILE:-$BOOT_ID_FILE}"
    [[ "${ARCHENEMY_BT_RESTORE_WAIT:-}" =~ ^[0-9]+$ ]] && RESTORE_WAIT=$ARCHENEMY_BT_RESTORE_WAIT
    [[ "${ARCHENEMY_BT_RESTORE_SETTLE:-}" =~ ^[0-9]+$ ]] && RESTORE_SETTLE=$ARCHENEMY_BT_RESTORE_SETTLE
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

render() {
    local info devices state=disabled icon='󰂲' tooltip='Bluetooth: off'
    if [[ ! -f "$FLAG" ]] || ! command -v bluetoothctl >/dev/null \
        || ! command -v timeout >/dev/null || ! command -v python >/dev/null; then
        printf '{"text":"","class":"off"}\n'
        return
    fi
    info=$(timeout 3 bluetoothctl show 2>/dev/null) || info=''
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

# ─── Przywrócenie "off" raz na start sesji (opis w nagłówku) ─────────────────
restore_pending=0
restore_settled=0
restore_until=0
restore_mark=''
boot_id=''
restore_init() {
    local rdir
    { IFS= read -r boot_id < "$BOOT_ID_FILE"; } 2>/dev/null
    [[ "$boot_id" =~ ^[A-Za-z0-9-]+$ ]] || return 0
    # shellcheck source=scripts/lib/runtime-dir.sh
    source "$ROOT/scripts/lib/runtime-dir.sh" 2>/dev/null || return 0
    rdir=$(archenemy_runtime_dir) || return 0
    restore_mark="$rdir/archenemy-bluetooth-restore"
    restore_pending=1
    restore_until=$(( SECONDS + RESTORE_WAIT ))
}
# Znacznik czytany przy każdej próbie: inny pasek (drugi monitor) mógł już
# przywrócić stan, a użytkownik — potem włączyć kontroler.
restore_done() {
    local v=''
    { IFS= read -r v < "$restore_mark"; } 2>/dev/null
    [[ "$v" == "$boot_id" ]]
}
restore_finish() {
    local tmp
    restore_pending=0
    tmp=$(mktemp "$restore_mark.XXXXXX" 2>/dev/null) || return 0
    { printf '%s\n' "$boot_id" > "$tmp" && mv -f "$tmp" "$restore_mark"; } 2>/dev/null || rm -f "$tmp"
}
restore_try() {
    local info
    (( restore_pending )) || return 0
    if restore_done; then restore_pending=0; return 0; fi
    if [[ ! -f "$FLAG" || "$(power_choice)" != off ]] || (( SECONDS >= restore_until )) \
        || ! command -v bluetoothctl >/dev/null || ! command -v timeout >/dev/null; then
        restore_finish
        return 0
    fi
    info=$(timeout 3 bluetoothctl show 2>/dev/null) || return 0
    [[ "$info" == *'Controller '* ]] || return 0
    if [[ "$info" == *'Powered: yes'* ]]; then
        # Porażka = kolejna próba przy następnym zdarzeniu, do limitu czasu.
        timeout 3 bluetoothctl power off >/dev/null 2>&1 && restore_finish
    elif (( ! restore_settled )); then
        restore_settled=1
        (( SECONDS + RESTORE_SETTLE < restore_until )) && restore_until=$(( SECONDS + RESTORE_SETTLE ))
    fi
    return 0
}

case "${1:-stream}" in
    status) render; exit ;;
    toggle)
        [[ -f "$FLAG" ]] && command -v bluetoothctl >/dev/null && command -v timeout >/dev/null || exit 0
        info=$(timeout 3 bluetoothctl show 2>/dev/null) || exit 1
        [[ "$info" == *'Controller '* ]] || exit 0
        if [[ "$info" == *'Powered: yes'* ]]; then power=off; else power=on; fi
        # Plik tymczasowy PRZED zmianą zasilania: niezapisywalny data/ to błąd
        # bez żadnej zmiany, a nie wybór, który po restarcie by przepadł.
        mkdir -p "${POWER_FILE%/*}" 2>/dev/null
        if ! tmp=$(mktemp "$POWER_FILE.XXXXXX"); then
            save_error "Bluetooth power not changed: the choice could not be saved (cannot write $POWER_FILE)."
            exit 1
        fi
        timeout 3 bluetoothctl power "$power" >/dev/null 2>&1
        rc=$?
        if (( rc != 0 )); then
            rm -f "$tmp"
            exit "$rc"
        fi
        chmod 644 "$tmp" 2>/dev/null   # mktemp daje 600; jak inne data/*.dat
        if printf '%s\n' "$power" > "$tmp" && mv -f "$tmp" "$POWER_FILE" \
            && [[ "$(power_choice)" == "$power" ]]; then
            exit 0
        fi
        rm -f "$tmp"
        save_error "Bluetooth is now $power, but the choice was not saved (cannot write $POWER_FILE); it will not survive a reboot."
        exit 1 ;;
    open)
        [[ -f "$FLAG" ]] && command -v bluetui >/dev/null && command -v alacritty >/dev/null || exit 0
        exec alacritty --class bluetui -e bluetui ;;
esac

restore_init
while :; do
    if ! command -v dbus-monitor >/dev/null; then
        restore_try
        render
        # Bez zdarzeń D-Bus czekanie na kontroler to rzadkie odpytywanie.
        sleep "$(( restore_pending ? 5 : 60 ))" & sleeper=$!
        wait "$sleeper" || :
        sleeper=''
        continue
    fi
    # Subskrypcja przed migawką. ObjectManager obejmuje hotplug kontrolera,
    # NameOwnerChanged ponowny start BlueZ; EOF magistrali uruchamia reconnect.
    exec {events}< <(exec dbus-monitor --system \
        "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'" \
        "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager'" \
        "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.bluez'" 2>/dev/null)
    monitor_pid=$!
    restore_try
    render
    while :; do
        if IFS= read -r -u "$events" line; then
            if [[ "$line" == signal* ]]; then
                # Jedna migawka po serii; nie odtwarzamy zaległych zmian RSSI.
                while IFS= read -r -t 0.3 -u "$events" line; do :; done
                restore_try
                render
            fi
        else
            # read przerwany przez SIGUSR1 nie oznacza końca strumienia.
            rc=$?
            (( rc > 128 )) && continue
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
