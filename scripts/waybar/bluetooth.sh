#!/bin/bash
# =============================================
#   archenemy - bluetooth.sh
#   Opcjonalny moduł strumieniowy waybara; SIGUSR1 odświeża flagę.
#   Źródła: man waybar-custom(5), bluetoothctl(1), dbus-monitor(1).
# =============================================
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLAG="$ROOT/data/bluetooth-enabled.dat"
monitor_pid=''
sleeper=''
cleanup() {
    [[ -z "$monitor_pid" ]] || kill "$monitor_pid" 2>/dev/null || :
    [[ -z "$sleeper" ]] || kill "$sleeper" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP

render() {
    local info devices state=disabled icon='󰂲' tooltip='Bluetooth: off'
    if [[ ! -f "$FLAG" ]] || ! command -v bluetoothctl >/dev/null; then
        printf '{"text":"","class":"off"}\n'
        return
    fi
    info=$(bluetoothctl --timeout 3 show 2>/dev/null) || info=''
    if [[ "$info" != *'Controller '* ]]; then
        printf '{"text":"","class":"off"}\n'
        return
    fi
    if [[ "$info" == *'Powered: yes'* ]]; then
        state=enabled; icon='󰂯'; tooltip='Bluetooth: on'
        devices=$(bluetoothctl --timeout 3 devices Connected 2>/dev/null) || devices=''
        if [[ -n "$devices" ]]; then
            state=connected; icon='󰂱'
            tooltip="Bluetooth: connected"$'\n'"$(sed -nE 's/^Device [[:xdigit:]:]+ //p' <<< "$devices")"
        fi
    fi
    # Nazwy urządzeń są niezaufane: osobno kodowanie JSON i escapowanie Pango.
    command -v python >/dev/null || { printf '{"text":"","class":"off"}\n'; return; }
    python -c 'import html,json,sys; print(json.dumps(dict(text=sys.argv[1], **{"class":sys.argv[2]}, tooltip=html.escape(sys.argv[3])+"\nLMB: bluetui · RMB: power on/off")))' "$icon" "$state" "$tooltip"
}
trap render USR1

case "${1:-stream}" in
    status) render; exit ;;
    toggle)
        [[ -f "$FLAG" ]] && command -v bluetoothctl >/dev/null || exit 0
        info=$(bluetoothctl --timeout 3 show 2>/dev/null) || exit 1
        [[ "$info" == *'Controller '* ]] || exit 0
        if [[ "$info" == *'Powered: yes'* ]]; then power=off; else power=on; fi
        bluetoothctl --timeout 3 power "$power" >/dev/null 2>&1
        exit $? ;;
    open)
        [[ -f "$FLAG" ]] && command -v bluetui >/dev/null && command -v alacritty >/dev/null || exit 0
        exec alacritty --class bluetui -e bluetui ;;
esac

while :; do
    if ! command -v dbus-monitor >/dev/null; then
        render
        sleep 60 & sleeper=$!
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
    render
    while :; do
        if IFS= read -r -u "$events" line; then
            [[ "$line" != signal* ]] || render
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
