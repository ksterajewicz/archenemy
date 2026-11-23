#!/usr/bin/env bash
# =============================================
#   archenemy - tests/bluetooth.sh
#   Atrapy BlueZ, D-Bus, pacmana i systemctl; bez sprzętu i usług hosta.
#   Pomocnik install/bluetooth-installation.sh (D7): brama platformy pkg_gate
#   na jawnym os-release (ARCHENEMY_TEST=1 + ARCHENEMY_OS_RELEASE, nie host):
#   Fedora/NixOS/nieobsługiwana = kod 2, zero wywołań, flaga nietknięta,
#   instrukcja (Fedora: bluetooth.service, bluez, dbus-tools, bluetui; NixOS:
#   hardware.bluetooth.enable, pkgs.bluetui; flaga ikony ręcznie); Arch i
#   pochodna = dawna ścieżka, a porażka (także zapis flagi, brak binarki)
#   usuwa starą flagę.
#   Trwały wybór zasilania (data/bluetooth-power.dat, B2): toggle zapisuje
#   PRZED zmianą zasilania, niezapisywalny data/ = kod 1 bez zmiany. Strumień
#   egzekwuje "off" po KAŻDYM zdarzeniu systemowym — start paska (logowanie),
#   PrepareForSleep(false), InterfacesAdded hciN / pojawienie się w migawce,
#   NameOwnerChanged org.bluez, koniec rfkill — w oknie (ARCHENEMY_BT_WINDOW),
#   a poza oknem zapisuje zmiany z bluetui/telefonu po ARCHENEMY_BT_CONFIRM s.
#   Osobne FIFO na pasek (MOCK_EVENTS), wiek bluetoothd z atrapy ps; dwa i
#   trzy paski, zamrożenie przy uśpieniu/zamykaniu i zatrzymaniu bluetoothd,
#   limit prób (bez pętli), "on"/brak/śmieci, brak flagi i bluetoothctl.
#   Przypadki graniczne z przeglądu B3 (B4; expect = bez przerywania pakietu):
#   F1 nowy pasek a cudza oczekująca decyzja, F2 blokada PPM/strumień, F3
#   ciągły ruch D-Bus, F4 rfkill w jednej serii, F5 przerwa reconnectu, F6
#   zatrzymywanie bluetooth.service (atrapa systemctl is-active), F8 ponowienie
#   nieudanego zapisu (deny-save), F9 znikający /proc/<pid>/comm.
# =============================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/timing.sh
source "$REPO/tests/lib/timing.sh"
export REPO
python - <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time
import sys
sys.path.insert(0, str(Path(os.environ["REPO"]) / "tests/lib"))
from test_timing import seconds, wait_until, Lines

repo = Path(os.environ['REPO'])
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    for name in ['scripts/waybar', 'install', 'data', 'bin', 'home', 'config', 'cache', 'state-home', 'runtime']:
        (root / name).mkdir(parents=True)
    (root / 'install/lib').mkdir()
    (root / 'packages').mkdir()
    (root / 'scripts/lib').mkdir()
    for name in ['scripts/waybar/bluetooth.sh', 'install/bluetooth-installation.sh', 'install/lib/pkg.sh', 'packages/platform-map.tsv']:
        shutil.copy2(repo / name, root / name)
    osr = root / 'os'
    osr.mkdir()
    for key, text in {'arch': 'NAME="Arch Linux"\nID=arch\n', 'endeavouros': 'NAME="EndeavourOS"\nID=endeavouros\nID_LIKE=arch\n',
                      'fedora': 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=44\n', 'nixos': 'NAME=NixOS\nID=nixos\nVERSION_ID=26.05\n',
                      'ubuntu': 'NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\n'}.items():
        (osr / key).write_text(text)
    real_touch = shutil.which('touch')
    real_mktemp = shutil.which('mktemp')
    (root / 'runtime').chmod(0o700)
    env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'], MOCK_ROOT=tmp, ARCHENEMY_TEST='1',
               ARCHENEMY_OS_RELEASE=str(osr / 'arch'), ARCHENEMY_OSTREE_MARKER=str(osr / 'none'))
    for key in ['DBUS_SESSION_BUS_ADDRESS', 'WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE']:
        env.pop(key, None)
    env.update(HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'config'),
               XDG_CACHE_HOME=str(root / 'cache'), XDG_STATE_HOME=str(root / 'state-home'),
               XDG_DATA_HOME=str(root / 'data'), XDG_RUNTIME_DIR=str(root / 'runtime'), TMPDIR=tmp)
    mocks = {
        'bluetoothctl': '''#!/usr/bin/env bash
printf 'bluetoothctl %s\\n' "$*" >> "$MOCK_ROOT/log"
# Wewnętrzny timeout utrzymuje proces przy życiu, zewnętrzny jest tylko limitem.
if [[ "$1" == --timeout ]]; then
 lifetime=$2
 trap 'sleep "$lifetime"' EXIT
 shift 2
fi
# MOCK_POWER_GATE=1: power czeka na gate-open i kończy się błędem (wyścig PPM, F2).
if [[ "${MOCK_POWER_GATE:-0}" == 1 && "$1" == power ]]; then
 echo "power $2" >> "$MOCK_ROOT/log"
 touch "$MOCK_ROOT/gate-ready"
 while [[ ! -e "$MOCK_ROOT/gate-open" ]]; do sleep 0.02; done
 exit 1
fi
state=$(cat "$MOCK_ROOT/state")
case "$1" in
 show)
  [[ "$state" == missing ]] && exit 0
  echo 'Controller 00:11:22:33:44:55 (public)'
  # blocked = rfkill: BlueZ pokazuje PowerState off-blocked.
  if [[ "$state" == disabled || "$state" == blocked ]]; then echo 'Powered: no'; else echo 'Powered: yes'; fi
  [[ "$state" != blocked ]] || echo 'PowerState: off-blocked' ;;
 devices)
  printf '\\033[0;33m[CHG] Device AA:BB:CC:DD:EE:FF RSSI: -65\\033[0m\\r\\n'
  if [[ "$state" != chg-only ]]; then
   printf '[NEW] Device AA:BB:CC:DD:EE:FF Noise\\n[DEL] Device AA:BB:CC:DD:EE:FF Noise\\nDiagnostic message\\nDevice AA:BB Invalid\\nDevice GG:BB:CC:DD:EE:FF Invalid\\n'
  fi
  [[ "$state" != connected ]] || printf '\\033[0;32mDevice AA:BB:CC:DD:EE:FF Headphones "A" <&>\\033[0m\\r\\nDevice 11:22:33:44:55:66 Keyboard\\n' ;;
 power)
  echo "power $2" >> "$MOCK_ROOT/log"
  # Jak BlueZ: zmiana zasilania widoczna w kolejnym show; bez kontrolera błąd.
  [[ "${FAIL_POWER:-0}" == 0 && "$state" != missing ]] || exit 1
  if [[ "$2" == on ]]; then echo enabled > "$MOCK_ROOT/state"; else echo disabled > "$MOCK_ROOT/state"; fi ;;
esac
exit 0
''',
        'dbus-monitor': '''#!/usr/bin/env bash
printf 'dbus-monitor %s\\n' "$*" >> "$MOCK_ROOT/log"
[[ "${MOCK_EOF:-0}" == 0 ]] || exit 0
exec cat "${MOCK_EVENTS:-$MOCK_ROOT/events}"
''',
        'sudo': '#!/usr/bin/env bash\nprintf "sudo %s\\n" "$*" >> "$MOCK_ROOT/log"\nexec "$@"\n',
        'dnf': '#!/usr/bin/env bash\nprintf "dnf %s\\n" "$*" >> "$MOCK_ROOT/log"\n',
        'rpm': '#!/usr/bin/env bash\nprintf "rpm %s\\n" "$*" >> "$MOCK_ROOT/log"\n',
        'pacman': '''#!/usr/bin/env bash
printf 'pacman %s\\n' "$*" >> "$MOCK_ROOT/log"
if [[ "$1" == -S ]]; then [[ "${FAIL_INSTALL:-0}" == 0 ]]; else [[ "${FAIL_QUERY:-0}" == 0 ]]; fi
''',
        'systemctl': '''#!/usr/bin/env bash
printf 'systemctl %s\\n' "$*" >> "$MOCK_ROOT/log"
case "$1" in
 enable) [[ "${FAIL_ENABLE:-0}" == 0 ]] ;;
 is-enabled) [[ "${FAIL_ENABLED:-0}" == 0 ]] ;;
 is-active)
  # Stan jednostki jak systemctl: unit_state (np. deactivating, F6), domyślnie active.
  unit=active
  [[ ! -f "$MOCK_ROOT/unit_state" ]] || unit=$(cat "$MOCK_ROOT/unit_state")
  [[ "${FAIL_ACTIVE:-0}" == 0 ]] || unit=inactive
  [[ "$2" == --quiet ]] || echo "$unit"
  [[ "$unit" == active ]] ;;
esac
''',
        'bluetui': '#!/usr/bin/env bash\nexit 0\n',
        # Wiek bluetoothd (ps -o etimes= -C bluetoothd); brak pliku = brak procesu.
        'ps': '#!/usr/bin/env bash\n[[ -f "$MOCK_ROOT/bluetoothd_age" ]] || exit 1\ncat "$MOCK_ROOT/bluetoothd_age"\n',
        'alacritty': '#!/usr/bin/env bash\nprintf "alacritty %s\\n" "$*" >> "$MOCK_ROOT/log"\n',
    }
    # touch z FAIL_TOUCH=1 = błąd zapisu flagi (root omija prawa pliku, więc atrapa).
    mocks['touch'] = '#!/usr/bin/env bash\n[[ "${FAIL_TOUCH:-0}" == 0 ]] || exit 1\nexec ' + real_touch + ' "$@"\n'
    # mktemp z FAIL_MKTEMP=1 = niezapisywalny katalog data/ (z tego samego powodu);
    # plik deny-save = odmowa w trakcie działania strumienia, odwracalna (F8);
    # MOCK_MKTEMP_GATE=1 = zapis wyboru czeka na gate-open (wyścig z PPM, F2).
    mocks['mktemp'] = ('#!/usr/bin/env bash\nif [[ "${FAIL_MKTEMP:-0}" != 0 || -e "$MOCK_ROOT/deny-save" ]]; then\n'
                       ' [[ ! -e "$MOCK_ROOT/deny-save" ]] || printf "mktemp-denied %s\\n" "$1" >> "$MOCK_ROOT/log"\n'
                       ' echo "mktemp: failed to create file via template \'$1\': Permission denied" >&2; exit 1\nfi\n'
                       'if [[ "${MOCK_MKTEMP_GATE:-0}" == 1 && "$1" == *bluetooth-power.dat.* ]]; then\n'
                       ' touch "$MOCK_ROOT/gate-ready"\n'
                       ' while [[ ! -e "$MOCK_ROOT/gate-open" ]]; do sleep 0.02; done\nfi\n'
                       'exec ' + real_mktemp + ' "$@"\n')
    mocks['notify-send'] = '#!/usr/bin/env bash\nprintf "notify-send %s\\n" "$*" >> "$MOCK_ROOT/log"\n'
    for name, code in mocks.items():
        f = root / 'bin' / name
        f.write_text(code)
        f.chmod(0o755)
    flag = root / 'data/bluetooth-enabled.dat'
    state = root / 'state'
    log = root / 'log'
    log.touch()
    state.write_text('enabled')
    bar = root / 'scripts/waybar/bluetooth.sh'
    installer = root / 'install/bluetooth-installation.sh'
    checks = 0
    def check(value, label):
        global checks
        assert value, label
        checks += 1
        print('  ✓ ' + label)
    # Przypadki graniczne B3 (F1–F9): expect nie przerywa pakietu, więc na
    # starym kodzie każdy z nich jest osobno czerwony; wynik zbiorczo na końcu.
    failures = []
    def expect(value, label):
        global checks
        if value:
            checks += 1
            print('  ✓ ' + label)
        else:
            failures.append(label)
            print('  ✗ ' + label, flush=True)
    def run(*args, extra=None):
        return subprocess.run(args, env=env | (extra or {}), text=True, capture_output=True, timeout=seconds(10))
    def status():
        result = run(str(bar), 'status')
        check(result.returncode == 0 and not result.stderr, 'status bez błędów')
        return json.loads(result.stdout)
    check(status()['text'] == '', 'brak flagi = pusty tekst')
    check(not log.read_text(), 'brak flagi = brak wywołań BlueZ')
    flag.touch()
    for value in ['missing', 'disabled', 'enabled', 'connected']:
        state.write_text(value)
        data = status()
        check(data['class'] == ('off' if value == 'missing' else value), 'stan ' + value)
        check(bool(data['text']) == (value != 'missing'), 'widoczność ' + value)
        if value == 'connected':
            check('Headphones &quot;A&quot; &lt;&amp;&gt;' in data['tooltip'] and 'Keyboard' in data['tooltip'], 'nazwy i escaping tooltipa')
    for value in ['chg-only', 'noise']:
        state.write_text(value)
        data = status()
        check(data['class'] == 'enabled' and data['tooltip'].startswith('Bluetooth: on\n')
              and not any(word in data['tooltip'] for word in ['RSSI', 'Noise', 'Invalid', 'Diagnostic']),
              'szum asynchroniczny bez połączonych urządzeń: ' + value)
    state.write_text('connected')
    started = time.monotonic()
    data = status()
    elapsed = time.monotonic() - started
    check(data['class'] == 'connected', 'pojedynczy render: stan connected')
    check(elapsed < 1,
          f'KONTRAKT: pojedynczy render {elapsed:.3f} s < 1 s mimo semantyki wewnętrznego --timeout')
    for value, target in [('disabled', 'on'), ('enabled', 'off')]:
        state.write_text(value)
        log.write_text('')
        check(run(str(bar), 'toggle').returncode == 0 and 'power ' + target in log.read_text(), 'PPM: power ' + target)
    log.write_text('')
    check(run(str(bar), 'open').returncode == 0 and 'alacritty --class bluetui -e bluetui' in log.read_text(), 'LPM: klasa bluetui')
    flag.unlink()
    log.write_text('')
    run(str(bar), 'toggle')
    run(str(bar), 'open')
    check(not log.read_text(), 'kliknięcia bez flagi są bezczynne')
    # Wybór z PPM wyżej zapisał data/bluetooth-power.dat; strumienie niżej startują
    # bez pliku i bez boot_id (= bez przywracania), jak przed tą funkcją.
    (root / 'data/bluetooth-power.dat').unlink(missing_ok=True)

    # Strumień reaguje na sygnały magistrali i USR1, bez uruchamiania sondy co sekundę.
    os.mkfifo(root / 'events')
    state.write_text('disabled')
    holder = os.open(root / 'events', os.O_RDWR | os.O_NONBLOCK)
    proc = subprocess.Popen([str(bar)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    reader_proc = None
    reader = None
    def receive(base=5):
        global reader_proc, reader
        if reader_proc is not proc:
            reader_proc, reader = proc, Lines(proc.stdout)
        return json.loads(reader.receive(base))
    try:
        check(receive()['text'] == '', 'strumień: bez flagi pusty tekst')
        flag.touch()
        proc.send_signal(signal.SIGUSR1)
        check(receive()['class'] == 'disabled', 'strumień: włączenie flagi')
        with (root / 'events').open('w', buffering=1) as events:
            for value in ['enabled', 'connected', 'missing']:
                state.write_text(value)
                events.write('signal sender=:1.2 -> destination=(null destination) interface=org.freedesktop.DBus.Properties; member=PropertiesChanged\n')
                check(receive()['class'] == ('off' if value == 'missing' else value), 'strumień zdarzeń: ' + value)
            before = log.read_text().count('bluetoothctl show')
            state.write_text('connected')
            events.write('signal RSSI changed\n' * 100)
            check(receive()['class'] == 'connected', 'seria 100 zdarzeń odświeża stan końcowy')
            # KONTRAKT: okno obserwacji debounce, bez mnożenia przez skalę.
            until = time.monotonic() + 0.7
            while reader.ready(max(0, until - time.monotonic())):
                receive()
                if time.monotonic() >= until:
                    break
            renders = log.read_text().count('bluetoothctl show') - before
            check(1 <= renders <= 2, f'KONTRAKT debounce 0,3 s: seria 100 zdarzeń daje {renders} render(y), najwyżej 2')
            flag.unlink()
            proc.send_signal(signal.SIGUSR1)
            check(receive()['text'] == '', 'USR1 ponownie odczytuje flagę')
            flag.touch()
            state.write_text('enabled')
            proc.send_signal(signal.SIGUSR1)
            check(receive()['class'] == 'enabled', 'USR1 przywraca ikonę')
            check(not reader.ready(0.2), 'strumień bez okresowego odpytywania')
            matches = log.read_text()
            check('org.bluez' in matches and 'PropertiesChanged' in matches and 'ObjectManager' in matches and 'NameOwnerChanged' in matches, 'subskrypcje właściwości, hotplug i restartu BlueZ')
            check("sender='org.freedesktop.login1'" in matches and "member='PrepareForSleep'" in matches
                  and "member='PrepareForShutdown'" in matches, 'subskrypcje logind: uśpienie/wybudzenie i zamykanie systemu')
    finally:
        os.killpg(proc.pid, signal.SIGTERM)
        _, errors = proc.communicate(timeout=seconds(5))
        check(not errors, 'strumień bez błędów stderr')
        os.close(holder)
        check(proc.returncode == 0, 'strumień zakończony bez błędów')

    # EOF wymusza opóźniony reconnect i nową migawkę, bez ciasnej pętli.
    state.write_text('enabled')
    proc = subprocess.Popen([str(bar)], env=env | {'MOCK_EOF': '1'}, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        check(receive()['class'] == 'enabled', 'EOF: pierwsza migawka')
        started = time.monotonic()
        before = log.read_text().count('dbus-monitor ')
        check(not reader.ready(0.5), 'EOF: brak natychmiastowego reconnectu')
        data = receive(7)
        check(data['class'] == 'enabled'
              and time.monotonic() - started >= 4.5
              and log.read_text().count('dbus-monitor ') == before + 1,
              'KONTRAKT reconnect 5 s: ponowna subskrypcja i migawka (dolna tolerancja 4,5 s)')
    finally:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.communicate(timeout=seconds(5))

    # Osobno TERM tylko do rodzica i killpg, zarówno przy nasłuchu, jak i reconnect.
    def children(pid):
        try:
            return [int(x) for x in Path(f'/proc/{pid}/task/{pid}/children').read_text().split()]
        except (FileNotFoundError, ProcessLookupError):
            return []
    def comm(pid):
        # F9: proces znika między exists() a read_text() — brak = brak gotowości.
        try:
            return Path(f'/proc/{pid}/comm').read_text().strip()
        except (FileNotFoundError, ProcessLookupError):
            return None
    def listening(pid):
        # Strumień czeka na zdarzenia: jedynym potomkiem jest nasłuch (cat).
        pids = children(pid)
        return bool(pids) and all(comm(child) == 'cat' for child in pids)
    def alive(pid):
        try:
            return Path(f'/proc/{pid}/stat').read_text().split(') ', 1)[1][0] != 'Z'
        except (FileNotFoundError, ProcessLookupError):
            return False
    for eof in [False, True]:
        for group in [False, True]:
            holder = os.open(root / 'events', os.O_RDWR | os.O_NONBLOCK)
            proc = subprocess.Popen([str(bar)], env=env | {'MOCK_EOF': str(int(eof))},
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    text=True, start_new_session=True)
            descendants = []
            try:
                receive()
                def expected_child():
                    descendants[:] = children(proc.pid)
                    return len(descendants) == 1 and any(('sleep' if eof else 'cat') == comm(pid)
                                                         for pid in descendants)
                wait_until(expected_child, 3, 'oczekiwany potomek strumienia')
                if group:
                    os.killpg(proc.pid, signal.SIGTERM)
                else:
                    proc.terminate()
                _, errors = proc.communicate(timeout=seconds(3))
                check(proc.returncode == 0 and not errors and not any(alive(pid) for pid in descendants),
                      f'sprzątanie potomków: EOF={eof}, killpg={group}')
            finally:
                os.close(holder)
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.communicate(timeout=seconds(3))
                for pid in descendants:
                    if alive(pid):
                        os.kill(pid, signal.SIGKILL)

    # ─── Trwały wybór zasilania (B2): egzekwowanie po zdarzeniach, zapis zmian ───
    power = root / 'data/bluetooth-power.dat'
    bt_age = root / 'bluetoothd_age'
    HDR = 'signal time=1.0 sender=:1.2 -> destination=(null destination) serial=1 path={}; interface={}; member={}\n'
    PROPS = 'org.freedesktop.DBus.Properties'
    OM = 'org.freedesktop.DBus.ObjectManager'
    LOGIN = 'org.freedesktop.login1.Manager'
    SIGNALS = {
        'changed': HDR.format('/org/bluez/hci0', PROPS, 'PropertiesChanged') + '   string "org.bluez.Adapter1"\n',
        'added': HDR.format('/', OM, 'InterfacesAdded') + '   object path "/org/bluez/hci0"\n   array [\n   ]\n',
        'removed': HDR.format('/', OM, 'InterfacesRemoved') + '   object path "/org/bluez/hci0"\n   array [\n   ]\n',
        'device': HDR.format('/', OM, 'InterfacesAdded') + '   object path "/org/bluez/hci0/dev_TEST"\n   array [\n   ]\n',
        'bluez-up': HDR.format('/org/freedesktop/DBus', 'org.freedesktop.DBus', 'NameOwnerChanged')
                    + '   string "org.bluez"\n   string ""\n   string ":1.9"\n',
        'bluez-down': HDR.format('/org/freedesktop/DBus', 'org.freedesktop.DBus', 'NameOwnerChanged')
                      + '   string "org.bluez"\n   string ":1.9"\n   string ""\n',
        'sleep': HDR.format('/org/freedesktop/login1', LOGIN, 'PrepareForSleep') + '   boolean true\n',
        'resume': HDR.format('/org/freedesktop/login1', LOGIN, 'PrepareForSleep') + '   boolean false\n',
        'shutdown': HDR.format('/org/freedesktop/login1', LOGIN, 'PrepareForShutdown') + '   boolean true\n',
    }
    # PropertiesChanged z argumentami jak w dbus-monitor (rfkill: PowerState off-blocked).
    def props(powered, power_state):
        return (HDR.format('/org/bluez/hci0', PROPS, 'PropertiesChanged') + '   string "org.bluez.Adapter1"\n   array [\n'
                f'      dict entry(\n         string "Powered"\n         variant             boolean {powered}\n      )\n'
                f'      dict entry(\n         string "PowerState"\n         variant             string "{power_state}"\n      )\n'
                '   ]\n   array [\n   ]\n')
    SIGNALS['blocked'] = props('false', 'off-blocked')
    SIGNALS['unblocked'] = props('true', 'on')
    FAST = {'ARCHENEMY_BT_CONFIRM': '1'}
    def power_calls():
        return [line for line in log.read_text().splitlines() if line.startswith('power ')]
    def setup(choice, value, age='3600'):
        # age = sekundy od startu bluetoothd (3600: dawno, brak okna startu paska).
        power.unlink(missing_ok=True)
        if choice is not None:
            power.write_bytes(choice.encode() if isinstance(choice, str) else choice)
        state.write_text(value)
        if age is None:
            bt_age.unlink(missing_ok=True)
        else:
            bt_age.write_text(age + '\n')
        log.write_text('')
    def choice_now():
        return power.read_bytes() if power.exists() else None
    def saved(expected, base=4):
        try:
            wait_until(lambda: choice_now() == expected.encode(), base, 'zapis ' + expected.strip())
            return True
        except AssertionError:
            return False
    def stays(expected, pause=1.8):
        # Dłużej niż ARCHENEMY_BT_CONFIRM=1 z zapasem.
        time.sleep(pause)
        return choice_now() == (None if expected is None else expected.encode())
    streams = []
    class Stream:
        # Osobne FIFO na pasek: jeden cat na FIFO, inaczej zdarzenie trafia do jednego.
        def __init__(self, name, extra=None):
            self.fifo = root / f'events-{name}'
            if not self.fifo.exists():
                os.mkfifo(self.fifo)
            self.holder = os.open(self.fifo, os.O_RDWR | os.O_NONBLOCK)
            self.proc = subprocess.Popen([str(bar)], env=env | {'MOCK_EVENTS': str(self.fifo)} | (extra or {}),
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                         start_new_session=True)
            streams.append(self)
            self.lines = Lines(self.proc.stdout)
            self.first = self.receive()
        def receive(self, base=5):
            return json.loads(self.lines.receive(base))
        def send(self, *names, value=None):
            if value is not None:
                state.write_text(value)
            with self.fifo.open('w') as fifo:
                fifo.write(''.join(SIGNALS[n] for n in names))
        def event(self, *names, value=None):
            self.send(*names, value=value)
            return self.receive()
        def quiet(self, pause):
            return not self.lines.ready(pause)
        def stop(self):
            # Linia JSON bywa odebrana, zanim python renderu wyjdzie; TERM w tej
            # chwili daje „Terminated” na stderr. Czekamy na sam nasłuch (cat).
            wait_until(lambda: listening(self.proc.pid), 3, 'strumień bezczynny przed TERM')
            os.killpg(self.proc.pid, signal.SIGTERM)
            _, self.errors = self.proc.communicate(timeout=seconds(5))
            os.close(self.holder)
            streams.remove(self)
            return self.proc.returncode == 0
        def clean(self):
            return self.stop() and not self.errors
    flag.touch()
    fresh = log.write_text
    # PPM: zapis wyboru (3 stany), atomowo, przed zmianą zasilania.
    for value, target, after in [('enabled', 'off', 'disabled'), ('disabled', 'on', 'enabled'), ('connected', 'off', 'disabled')]:
        state.write_text(value)
        result = run(str(bar), 'toggle')
        check(result.returncode == 0 and power.read_text() == target + '\n' and state.read_text().strip() == after,
              f'PPM zapisuje wybór: {value} → {target}')
    check(sorted(p.name for p in (root / 'data').iterdir()) == ['bluetooth-enabled.dat', 'bluetooth-power.dat'],
          'zapis atomowy: w data/ bez plików tymczasowych')
    power.write_text('on\n')
    state.write_text('enabled')
    fresh('')
    result = run(str(bar), 'toggle', extra={'FAIL_MKTEMP': '1'})
    check(result.returncode == 1 and 'cannot write' in result.stderr and 'bluetooth-power.dat' in result.stderr
          and 'not changed' in result.stderr,
          'niezapisywalny data/: kod 1 i czytelny błąd na stderr')
    check(power.read_text() == 'on\n' and state.read_text().strip() == 'enabled' and not power_calls(),
          'niezapisywalny data/: zasilanie i stary wybór nietknięte')
    check('notify-send' in log.read_text() and 'bluetooth-power.dat' in log.read_text(),
          'niezapisywalny data/: powiadomienie z nazwą pliku')
    for previous in [b'on\n', None]:
        power.unlink(missing_ok=True)
        if previous is not None:
            power.write_bytes(previous)
        state.write_text('enabled')
        fresh('')
        result = run(str(bar), 'toggle', extra={'FAIL_POWER': '1'})
        check(result.returncode != 0 and choice_now() == previous, f'nieudane power off: poprzedni wybór przywrócony ({previous!r})')
        check(sorted(p.name for p in (root / 'data').iterdir()) == ['bluetooth-enabled.dat'] + (['bluetooth-power.dat'] if previous else []),
              'nieudane power off: bez pliku tymczasowego')

    try:
        # ── Logowanie / start paska ──
        setup('off\n', 'enabled')
        s = Stream('a', FAST)
        check(s.first['class'] == 'disabled' and power_calls() == ['power off'] and choice_now() == b'off\n',
              'off + logowanie (start paska po AutoEnable z bootu): kontroler wyłączony, plik nietknięty')
        check(s.clean(), 'logowanie: strumień bez błędów')
        setup('off\n', 'enabled')
        s = Stream('a', FAST)
        check(s.first['class'] == 'disabled' and power_calls() == ['power off'],
              'wylogowanie i ponowne logowanie bez restartu: znów wyłączony (bez znacznika „raz na sesję”)')
        check(s.clean(), 'ponowne logowanie: strumień bez błędów')
        setup('on\n', 'disabled')
        s = Stream('a', FAST)
        check(s.first['class'] == 'enabled' and power_calls() == ['power on'],
              'on + logowanie przy wyłączonym kontrolerze (AutoEnable=false): włączony')
        check(s.clean(), 'on + logowanie: strumień bez błędów')
        # „on”-zgodny stan, brak pliku i śmieci = brak egzekwowania, także po wybudzeniu.
        for content in [b'on\n', None, b'', b'OFF\n', b'of\n', b'off off\n', b'offline\n', b'\x00off\n', b'off\x1b[0m\n']:
            setup(content, 'enabled')
            s = Stream('a', FAST)
            first = s.first
            again = s.event('sleep')
            again = s.event('resume', 'added', 'changed')
            check(first['class'] == 'enabled' and again['class'] == 'enabled' and not power_calls() and choice_now() == content,
                  f'{content!r} + logowanie i wybudzenie: kontroler i plik nieruszane')
            check(s.clean(), f'{content!r}: strumień bez błędów')
        flag.unlink()
        setup('off\n', 'enabled')
        s = Stream('a', FAST)
        check(s.first['text'] == '' and s.event('resume', 'changed')['text'] == '' and not power_calls(),
              'bez flagi ikony: brak egzekwowania')
        check(s.clean(), 'bez flagi: strumień bez błędów')
        flag.touch()

        # ── Wybudzenie z uśpienia ──
        setup('off\n', 'disabled')
        s = Stream('a', FAST)
        check(s.first['class'] == 'disabled' and not power_calls(), 'off zgodny ze stanem: bez power')
        s.event('sleep')
        check(s.event('resume', 'changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'off + wybudzenie (PrepareForSleep false) i AutoEnable: cofnięte')
        check(stays('off\n'), 'wybudzenie: AutoEnable nie zapisany jako wola użytkownika')
        s.event('resume', value='disabled')
        check(s.event('changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'] * 2,
              'AutoEnable chwilę po wybudzeniu (osobna seria w oknie): cofnięte')
        check(s.clean(), 'wybudzenie: strumień bez błędów')

        # ── Hotplug kontrolera ──
        setup('off\n', 'missing')
        s = Stream('a', FAST)
        check(s.first['class'] == 'off' and not power_calls(), 'brak kontrolera na starcie: bez błędu, bez power')
        check(s.quiet(0.5), 'brak kontrolera: bez pętli odpytywania')
        check(s.event('added', 'changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'off + hotplug (InterfacesAdded /org/bluez/hci0): wyłączony')
        check(s.clean(), 'hotplug: strumień bez błędów')
        # Każdy wariant w świeżym strumieniu: bez okna startu (dawny bluetoothd).
        setup('off\n', 'disabled')
        s = Stream('a', FAST)
        check(s.event('removed', 'added', 'changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'szybki replug w jednej serii (migawka bez braku kontrolera): wyłączony')
        check(s.clean(), 'szybki replug: strumień bez błędów')
        setup('off\n', 'missing')
        s = Stream('a', FAST)
        check(s.event('changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'pojawienie się kontrolera widoczne tylko w migawce (bez InterfacesAdded): wyłączony')
        check(s.clean(), 'pojawienie w migawce: strumień bez błędów')
        setup('off\n', 'disabled')
        s = Stream('a', FAST)
        check(s.event('device', 'changed', value='enabled')['class'] == 'enabled' and not power_calls() and saved('on\n'),
              'InterfacesAdded urządzenia (dev_*) nie otwiera okna: włączenie zapisane jako wola')
        check(s.clean(), 'urządzenie: strumień bez błędów')

        # ── Restart bluetoothd ──
        setup('off\n', 'disabled')
        s = Stream('a', FAST)
        check(s.event('bluez-down', value='missing')['class'] == 'off' and not power_calls(), 'bluetoothd zatrzymany: bez power')
        check(s.event('bluez-up', 'added', 'changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'off + restart bluetoothd (NameOwnerChanged) i AutoEnable: wyłączony')
        check(s.clean(), 'restart bluetoothd: strumień bez błędów')
        setup('off\n', 'disabled')
        s = Stream('a', FAST)
        check(s.event('bluez-up', 'changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'szybki restart bluetoothd (tylko NameOwnerChanged, kontroler bez przerwy): wyłączony')
        check(s.clean(), 'szybki restart: strumień bez błędów')
        # SIGTERM bluetoothd sam wyłącza kontroler (adapter_shutdown) — nie wola użytkownika.
        setup('on\n', 'enabled')
        s = Stream('a', {'ARCHENEMY_BT_CONFIRM': '2'})
        s.event('changed', value='disabled')
        s.event('bluez-down', value='missing')
        check(stays('on\n', 2.6), 'zatrzymanie bluetoothd (Powered false, potem utrata nazwy): wybór on nienadpisany')
        check(s.event('bluez-up', 'added', 'changed', value='enabled')['class'] == 'enabled' and not power_calls(),
              'on + start bluetoothd: AutoEnable zostaje, bez power')
        check(s.clean(), 'zatrzymanie bluetoothd: strumień bez błędów')

        # ── Użytkownik poza paskiem (bluetui, blueman, telefon) ──
        setup('off\n', 'disabled')
        s = Stream('a', FAST)
        check(s.event('changed', value='enabled')['class'] == 'enabled' and not power_calls() and saved('on\n'),
              'off + włączenie z bluetui poza oknem: zapis on, bez cofania')
        s.event('sleep')
        check(s.event('resume', 'changed', value='enabled')['class'] == 'enabled' and not power_calls(),
              'po włączeniu z bluetui: kolejne wybudzenie zostawia on')
        check(s.clean(), 'włączenie poza paskiem: strumień bez błędów')
        s = Stream('a', FAST)
        check(s.first['class'] == 'enabled' and not power_calls() and choice_now() == b'on\n',
              'po włączeniu z bluetui: restart paska / logowanie zostawia on')
        check(s.event('changed', value='disabled')['class'] == 'disabled' and not power_calls() and saved('off\n'),
              'wyłączenie z bluetui/telefonu poza paskiem: zapis off')
        check(s.event('resume', 'changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'po wyłączeniu z bluetui: wybudzenie i AutoEnable cofnięte')
        check(s.clean(), 'wyłączenie poza paskiem: strumień bez błędów')
        setup(None, 'enabled')
        s = Stream('a', FAST)
        check(s.event('changed', value='disabled')['class'] == 'disabled' and saved('off\n') and not power_calls(),
              'brak pliku + wyłączenie poza paskiem: plik off utworzony')
        check(power.stat().st_mode & 0o777 == 0o644
              and sorted(p.name for p in (root / 'data').iterdir()) == ['bluetooth-enabled.dat', 'bluetooth-power.dat'],
              'zapis ze strumienia: 644, atomowo, bez plików tymczasowych')
        check(s.clean(), 'brak pliku: strumień bez błędów')
        # Okno startu paska liczy się od startu bluetoothd (ps etimes).
        setup('off\n', 'disabled', age='0')
        s = Stream('a', FAST | {'ARCHENEMY_BT_WINDOW': '2'})
        check(s.event('changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'świeży bluetoothd: spóźnione AutoEnable w oknie startu cofnięte')
        time.sleep(2.3)
        check(s.event('changed', value='enabled')['class'] == 'enabled' and power_calls() == ['power off'] and saved('on\n'),
              'po oknie (2 s) włączenie to wola użytkownika: zapis on, bez cofania')
        check(s.clean(), 'okno startu: strumień bez błędów')
        setup('off\n', 'disabled', age=None)
        s = Stream('a', FAST)
        check(s.event('changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'nieznany wiek bluetoothd: okno od startu paska ("off" wygrywa)')
        check(s.clean(), 'nieznany wiek: strumień bez błędów')

        # ── Kilka pasków (każdy = osobny strumień) ──
        setup('off\n', 'disabled')
        SHORT = FAST | {'ARCHENEMY_BT_WINDOW': '2'}
        a, b = Stream('a', SHORT), Stream('b', SHORT)
        a.send('changed', value='enabled')
        b.send('changed')
        check(a.receive()['class'] == 'enabled' and b.receive()['class'] == 'enabled' and not power_calls() and saved('on\n'),
              'dwa paski: włączenie z bluetui zapisane, żaden strumień go nie cofa')
        check(stays('on\n') and not power_calls(), 'dwa paski: włączenie trwa po potwierdzeniu')
        a.send('changed', value='disabled')
        b.send('changed')
        a.receive(), b.receive()
        check(saved('off\n') and not power_calls(), 'dwa paski: wyłączenie poza paskiem zapisane')
        a.send('resume', 'changed', value='enabled')
        b.send('resume', 'changed')
        a.receive(), b.receive()
        calls = power_calls()
        check(1 <= len(calls) <= 2 and set(calls) == {'power off'} and state.read_text().strip() == 'disabled' and choice_now() == b'off\n',
              f'dwa paski + wybudzenie: wyłączony, {len(calls)} polecenie(a) power (≤ 2)')
        check(a.quiet(1.5) and b.quiet(0) and power_calls() == calls, 'dwa paski: bez pętli włącz/wyłącz')
        time.sleep(2.2)   # okno wybudzenia (2 s) w a i b minęło
        c = Stream('c', SHORT)
        for stream in (a, b, c):
            stream.send('changed', value='enabled')
        check(all(stream.receive()['class'] == 'enabled' for stream in (a, b, c)) and power_calls() == calls and saved('on\n'),
              'nowy pasek (monitor) przy dawnym bluetoothd: włączenie z bluetui chwilę po jego starcie nie jest cofane')
        check(all(stream.clean() for stream in (c, b, a)), 'kilka pasków: strumienie bez błędów')

        # ── Zmiana w trakcie okna ──
        setup('off\n', 'disabled')
        s = Stream('a', FAST)
        s.event('resume')
        result = run(str(bar), 'toggle')
        check(result.returncode == 0 and choice_now() == b'on\n' and power_calls() == ['power on'], 'PPM on w oknie: zapis i power on')
        check(s.event('changed')['class'] == 'enabled' and power_calls() == ['power on'] and stays('on\n'),
              'PPM on w oknie: plik zapisany przed zasilaniem, strumień nie cofa')
        check(s.event('changed', value='disabled')['class'] == 'disabled' and saved('off\n') and power_calls() == ['power on'],
              'wyłączenie z bluetui w oknie przy on: zapis off')
        renders = [s.event('changed', value='enabled')['class'] for _ in range(5)]
        check(power_calls().count('power off') == 3 and renders[:3] == ['disabled'] * 3 and renders[3:] == ['enabled'] * 2
              and choice_now() == b'off\n',
              'ciągłe włączanie w oknie: najwyżej 3 cofnięcia, potem bez pętli')
        check(s.stop() and 'gave up' in s.errors, 'limit prób: komunikat na stderr')

        # ── Niezapisywalny data/ w strumieniu ──
        setup('on\n', 'enabled')
        s = Stream('a', FAST | {'FAIL_MKTEMP': '1'})
        check(s.event('changed', value='disabled')['class'] == 'disabled' and stays('on\n')
              and not power_calls() and state.read_text().strip() == 'disabled',
              'niezapisywalny data/ (strumień): zasilanie nietknięte, stary wybór zostaje')
        check(s.stop() and 'cannot write' in s.errors and 'bluetooth-power.dat' in s.errors
              and log.read_text().count('notify-send') == 1,
              'niezapisywalny data/ (strumień): stderr i jedno powiadomienie z nazwą pliku')

        # ── Uśpienie, zamykanie systemu, rfkill: nie są wolą użytkownika ──
        setup('on\n', 'enabled')
        s = Stream('a', FAST)
        s.event('shutdown')
        s.event('changed', value='disabled')
        check(stays('on\n') and not power_calls(), 'PrepareForShutdown(true): wyłączenie przy zamykaniu systemu niezapisane')
        check(s.clean(), 'zamykanie: strumień bez błędów')
        setup('on\n', 'enabled')
        s = Stream('a', FAST)
        s.event('sleep')
        s.event('changed', value='disabled')
        check(stays('on\n') and not power_calls(), 'PrepareForSleep(true): zmiana w trakcie usypiania niezapisana')
        check(s.event('resume')['class'] == 'enabled' and power_calls() == ['power on'],
              'wybudzenie z on, kontroler wyłączony: włączony')
        check(s.clean(), 'uśpienie: strumień bez błędów')
        setup('off\n', 'disabled')
        s = Stream('a', FAST)
        s.event('blocked', value='blocked')
        check(s.event('unblocked', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'] and stays('off\n'),
              'off + rfkill block/unblock w osobnych seriach (BlueZ włącza po odblokowaniu): cofnięte')
        check(s.clean(), 'rfkill off: strumień bez błędów')
        # F4: szybki block/unblock w jednej serii — migawka widzi już on, przejście
        # rfkill jest tylko w argumentach wiadomości.
        setup('off\n', 'disabled')
        s = Stream('a', FAST)
        s.send('blocked', 'unblocked', value='enabled')
        expect(s.receive()['class'] == 'disabled' and power_calls() == ['power off'] and stays('off\n'),
               'F4: off + rfkill block/unblock w jednej serii (migawka bez off-blocked): cofnięte')
        expect(s.clean(), 'F4: strumień bez błędów')
        setup('on\n', 'enabled')
        s = Stream('a', FAST)
        s.event('changed', value='blocked')
        check(stays('on\n') and not power_calls(), 'on + rfkill block: wybór on nienadpisany')
        check(s.clean(), 'rfkill on: strumień bez błędów')

        # ── Nieudane power: ponowienie z timerem, limit, bez pętli ──
        setup('off\n', 'enabled')
        s = Stream('a', FAST | {'FAIL_POWER': '1'})
        try:
            wait_until(lambda: len(power_calls()) == 3, 5, 'trzy próby power off')
            retried = True
        except AssertionError:
            retried = False
        check(retried and s.quiet(1.5) and len(power_calls()) == 3 and choice_now() == b'off\n',
              'nieudane power off: 3 próby co 1 s, potem koniec, wybór nietknięty')
        check(s.stop() and 'gave up' in s.errors, 'nieudane power off: komunikat na stderr')

        # ── Przypadki graniczne z przeglądu B3 (F1–F9); każdy po swojemu sprząta ──
        def kill_streams():
            for stream in list(streams):
                if stream.proc.poll() is None:
                    os.killpg(stream.proc.pid, signal.SIGKILL)
                stream.proc.communicate(timeout=seconds(5))
                os.close(stream.holder)
            streams.clear()
        def gate_reset():
            for name in ['gate-ready', 'gate-open']:
                (root / name).unlink(missing_ok=True)
        def finished_or(proc, base):
            # Czeka na koniec procesu najwyżej base s (bez skali: limit atrapy to timeout 3 s).
            try:
                proc.wait(timeout=base)
            except subprocess.TimeoutExpired:
                pass
        # F1: drugi pasek startuje, gdy pierwszy potwierdza wyłączenie z bluetui.
        try:
            setup('on\n', 'enabled')
            CONF2 = {'ARCHENEMY_BT_CONFIRM': '2'}
            a = Stream('f1a', CONF2)
            a.event('changed', value='disabled')
            b = Stream('f1b', CONF2)
            expect(b.first['class'] == 'disabled' and 'power on' not in power_calls() and saved('off\n', 5)
                   and state.read_text().strip() == 'disabled' and stays('off\n'),
                   'F1: nowy pasek w trakcie potwierdzania wyłączenia z bluetui: off zapisane, bez power on')
            expect(b.clean() and a.clean(), 'F1: strumienie bez błędów')
        finally:
            kill_streams()
        # F2a: pierwszy PPM czeka na nieudane power, drugi PPM w tym czasie; wycofanie
        # pierwszego nie może nadpisać wyboru drugiego.
        try:
            gate_reset()
            setup('on\n', 'enabled')
            first = subprocess.Popen([str(bar), 'toggle'], env=env | {'MOCK_POWER_GATE': '1'},
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            wait_until(lambda: (root / 'gate-ready').exists(), 3, 'pierwszy PPM czeka na power')
            second = subprocess.Popen([str(bar), 'toggle'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            finished_or(second, 1.5)
            (root / 'gate-open').touch()
            first.communicate(timeout=seconds(10))
            second.communicate(timeout=seconds(15))
            expect(first.returncode != 0 and second.returncode == 0 and choice_now() == b'off\n'
                   and state.read_text().strip() == 'disabled',
                   'F2: dwa nakładające się PPM, pierwszy power nieudany: plik = ostatni udany wybór (off, wyłączony)')
        finally:
            gate_reset()
        # F2b: zapis ze strumienia (bluetui off) w toku, w tym czasie PPM on.
        try:
            setup('on\n', 'enabled')
            a = Stream('f2', FAST | {'MOCK_MKTEMP_GATE': '1'})
            a.event('changed', value='disabled')
            wait_until(lambda: (root / 'gate-ready').exists(), 4, 'zapis strumienia czeka')
            click = subprocess.Popen([str(bar), 'toggle'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            finished_or(click, 1.5)
            (root / 'gate-open').touch()
            click.communicate(timeout=seconds(15))
            time.sleep(0.5)
            expect(click.returncode == 0 and choice_now() == b'on\n' and state.read_text().strip() == 'enabled'
                   and stays('on\n'),
                   'F2: PPM on w trakcie zapisu off ze strumienia: wygrywa PPM (plik on, włączony)')
            expect(a.clean(), 'F2: strumień bez błędów')
        finally:
            kill_streams()
            gate_reset()
        # F3: ciągły ruch D-Bus (co 0,1 s) dłuższy niż okno po wybudzeniu.
        try:
            setup('off\n', 'disabled')
            a = Stream('f3', FAST | {'ARCHENEMY_BT_WINDOW': '3'})
            a.event('resume')
            state.write_text('enabled')
            started = time.monotonic()
            while time.monotonic() - started < 4.5:
                a.send('changed')
                time.sleep(0.1)
            during = power_calls(), state.read_text().strip()
            expect(during[0] == ['power off'] and during[1] == 'disabled' and stays('off\n'),
                   'F3: AutoEnable po wybudzeniu przy ciągłym ruchu D-Bus: cofnięte w oknie, nie zapisane')
            expect(a.clean(), 'F3: strumień bez błędów')
        finally:
            kill_streams()
        # F5: monitor D-Bus kończy się; w 5-sekundowej przerwie system włącza kontroler.
        try:
            setup('off\n', 'disabled')
            a = Stream('f5', FAST | {'MOCK_EOF': '1'})
            state.write_text('enabled')
            a.receive(10)
            try:
                wait_until(lambda: 'power off' in power_calls() or choice_now() == b'on\n', 12, 'F5: rozstrzygnięcie po reconnect')
            except AssertionError:
                pass
            expect(power_calls() == ['power off'] and state.read_text().strip() == 'disabled' and stays('off\n'),
                   'F5: włączenie w przerwie reconnectu: po ponownej subskrypcji cofnięte, nie zapisane')
            os.killpg(a.proc.pid, signal.SIGTERM)
            a.proc.communicate(timeout=seconds(5))
            expect(a.proc.returncode == 0, 'F5: strumień zakończony bez błędów')
            os.close(a.holder)
            streams.remove(a)
        finally:
            kill_streams()
        # F6: zatrzymywanie bluetooth.service trwa dłużej niż CONFIRM (kilka adapterów).
        unit = root / 'unit_state'
        try:
            setup('on\n', 'enabled')
            unit.write_text('deactivating\n')
            a = Stream('f6', FAST)
            a.event('changed', value='disabled')
            expect(stays('on\n') and not power_calls(),
                   'F6: Powered false w trakcie zatrzymywania bluetooth.service (> CONFIRM): wybór on nienadpisany')
            a.event('bluez-down', value='missing')
            unit.unlink()
            expect(a.event('bluez-up', 'added', 'changed', value='enabled')['class'] == 'enabled' and not power_calls()
                   and choice_now() == b'on\n',
                   'F6: po starcie bluetoothd: on zostaje, bez power')
            expect(a.clean(), 'F6: strumień bez błędów')
        finally:
            unit.unlink(missing_ok=True)
            kill_streams()
        # F8: wyłączenie z bluetui przy odmowie zapisu; zapis wraca bez kolejnego zdarzenia.
        deny = root / 'deny-save'
        try:
            setup('on\n', 'enabled')
            deny.touch()
            a = Stream('f8', FAST | {'ARCHENEMY_BT_SAVE_RETRY': '1'})
            a.event('changed', value='disabled')
            try:
                wait_until(lambda: 'notify-send' in log.read_text(), 5, 'F8: odmowa zapisu zgłoszona')
            except AssertionError:
                pass
            denied = choice_now()
            deny.unlink()
            expect(denied == b'on\n' and saved('off\n', 5) and log.read_text().count('notify-send') == 1 and not power_calls(),
                   'F8: nieudany zapis off ponowiony po odzyskaniu zapisu (bez kolejnego zdarzenia), jedno powiadomienie')
            expect(a.stop(), 'F8: strumień zakończony bez błędów')
            # Stała odmowa: ograniczona liczba prób, a wola zostaje w pamięci strumienia.
            setup('on\n', 'enabled')
            deny.touch()
            a = Stream('f8b', FAST | {'ARCHENEMY_BT_SAVE_RETRY': '1', 'ARCHENEMY_BT_SAVE_TRIES': '3'})
            a.event('changed', value='disabled')
            def denied_saves():
                return [line for line in log.read_text().splitlines()
                        if line.startswith('mktemp-denied') and 'bluetooth-power.dat.' in line]
            try:
                wait_until(lambda: len(denied_saves()) >= 3, 6, 'F8: trzy próby zapisu')
            except AssertionError:
                pass
            time.sleep(1.5)
            expect(len(denied_saves()) == 3 and choice_now() == b'on\n',
                   'F8: stała odmowa zapisu: dokładnie 3 próby (ARCHENEMY_BT_SAVE_TRIES), potem koniec')
            expect(a.event('resume', 'changed', value='enabled')['class'] == 'disabled' and power_calls() == ['power off'],
                   'F8: niezapisane off nadal chronione w strumieniu: wybudzenie i AutoEnable cofnięte')
            expect(a.stop() and 'gave up saving' in a.errors, 'F8: koniec prób zapisu zgłoszony na stderr')
        finally:
            deny.unlink(missing_ok=True)
            kill_streams()
        # F9: /proc/<pid>/comm znika między sprawdzeniem a odczytem — brak gotowości, nie wyjątek.
        sleeper_proc = subprocess.Popen(['sleep', '5'])
        real_read_text = Path.read_text
        def vanished(self, *args, **kwargs):
            if self.name == 'comm':
                raise FileNotFoundError(str(self))
            return real_read_text(self, *args, **kwargs)
        Path.read_text = vanished
        try:
            vanish_ok = listening(os.getpid()) is False
        except FileNotFoundError:
            vanish_ok = False
        finally:
            Path.read_text = real_read_text
            sleeper_proc.kill()
            sleeper_proc.wait()
        expect(vanish_ok, 'F9: znikający /proc/<pid>/comm w oczekiwaniu na nasłuch = brak gotowości, bez FileNotFoundError')

        # ── Brak bluetoothctl: bez błędu i bez pętli ──
        (root / 'bin/bluetoothctl').rename(root / 'bluetoothctl.off')
        if shutil.which('bluetoothctl', path=os.environ['PATH']) is None:
            setup('off\n', 'enabled')
            s = Stream('a', FAST)
            check(s.first['text'] == '' and s.quiet(0.5), 'brak bluetoothctl: pusty moduł, bez pętli')
            check(log.read_text().count('dbus-monitor ') == 1 and not power_calls(), 'brak bluetoothctl: jedna subskrypcja, zero power')
            check(s.clean(), 'brak bluetoothctl: strumień bez błędów')
        else:
            print('  - pominięte: bluetoothctl jest w PATH hosta (brak binarki)')
        (root / 'bluetoothctl.off').rename(root / 'bin/bluetoothctl')
    finally:
        for stream in list(streams):
            if stream.proc.poll() is None:
                os.killpg(stream.proc.pid, signal.SIGKILL)
                stream.proc.communicate(timeout=seconds(5))
            os.close(stream.holder)
        streams.clear()
    power.unlink(missing_ok=True)
    check(run('git', '-C', str(repo), 'check-ignore', 'data/bluetooth-power.dat').returncode == 0, 'wybór zasilania ignorowany przez git')

    for failure in ['FAIL_INSTALL', 'FAIL_QUERY', 'FAIL_ENABLE', 'FAIL_ENABLED', 'FAIL_ACTIVE', None]:
        flag.unlink(missing_ok=True)
        log.write_text('')
        result = run(str(installer), extra={failure: '1'} if failure else {})
        check(result.returncode == (1 if failure else 0), 'instalator: ' + str(failure))
        check(flag.exists() == (failure is None), 'flaga wyłącznie po pełnym sukcesie: ' + str(failure))
        if failure:
            check('✓' not in result.stdout and ('Retry:' in result.stdout or 'then bash' in result.stdout), 'błąd zawiera polecenie ręczne')
        if failure in ['FAIL_INSTALL', 'FAIL_QUERY']:
            check('systemctl' not in log.read_text(), 'bez usługi po błędzie pakietów')
        if failure is None:
            check('pacman -S --needed bluez bluez-utils dbus bluetui' in log.read_text(), 'pełna opcjonalna transakcja')
            check('is-active --quiet bluetooth' in log.read_text() and 'is-enabled --quiet bluetooth' in log.read_text(), 'weryfikacja aktywności i enable')
    # D7: stara flaga nie zostaje po porażce na Archu (także błąd zapisu flagi).
    for failure in ['FAIL_INSTALL', 'FAIL_QUERY', 'FAIL_ENABLE', 'FAIL_ACTIVE', 'FAIL_TOUCH']:
        flag.touch()
        result = run(str(installer), extra={failure: '1'})
        check(result.returncode == 1 and not flag.exists() and '✓' not in result.stdout, 'porażka usuwa starą flagę: ' + failure)
    # Brak binarki bluetui mimo udanej „instalacji”: bez flagi, polecenie ponowienia.
    (root / 'bin/bluetui').rename(root / 'bluetui.off')
    if shutil.which('bluetui', path=os.environ['PATH']) is None:
        flag.touch()
        result = run(str(installer))
        check(result.returncode == 1 and not flag.exists() and 'Retry:' in result.stdout, 'brak binarki bluetui: kod 1, bez flagi')
    else:
        print('  - pominięte: bluetui jest w PATH hosta (brak binarki)')
    (root / 'bluetui.off').rename(root / 'bin/bluetui')
    # D7: brama platformy pomocnika uruchomionego wprost.
    for plat in ['fedora', 'nixos', 'ubuntu']:
        for had_flag in [False, True]:
            flag.unlink(missing_ok=True)
            if had_flag:
                flag.touch()
            log.write_text('')
            result = run(str(installer), extra={'ARCHENEMY_OS_RELEASE': str(osr / plat), 'PLATFORM': 'arch', 'PKG_ROUTE': 'arch'})
            label = 'brama ' + plat + (' (z flagą)' if had_flag else '') + ': '
            check(result.returncode == 2, label + 'kod 2 mimo odziedziczonego PLATFORM=arch')
            check(not log.read_text(), label + 'zero wywołań sudo/pacman/dnf/rpm/systemctl/bluetoothctl')
            check(flag.exists() == had_flag, label + 'flaga ikony nietknięta')
            check('✓' not in result.stdout and 'nothing was changed' in result.stdout, label + 'bez ✓, „nothing was changed”')
            out = result.stdout
            if plat == 'fedora':
                check(all(t in out for t in ['sudo dnf install bluez dbus-tools', 'sudo systemctl enable --now bluetooth.service',
                                             'github.com/pythops/bluetui', 'touch ~/archenemy/data/bluetooth-enabled.dat']) and 'pacman' not in out,
                      label + 'bluez, dbus-tools, bluetooth.service, bluetui z mapy, flaga ręcznie')
            elif plat == 'nixos':
                check(all(t in out for t in ['hardware.bluetooth.enable = true;', 'pkgs.bluetui', 'nixos-rebuild switch',
                                             'touch ~/archenemy/data/bluetooth-enabled.dat']) and 'systemctl' not in out and 'pacman' not in out,
                      label + 'deklaracja + pkgs.bluetui, flaga ręcznie, bez systemctl')
            else:
                check('not supported' in out and 'bluetooth-enabled.dat' not in out, label + 'nieobsługiwana dystrybucja')
    flag.unlink(missing_ok=True)
    result = run(str(installer), extra={'ARCHENEMY_OS_RELEASE': str(osr / 'endeavouros')})
    check(result.returncode == 0 and flag.exists(), 'pochodna Archa (EndeavourOS): ścieżka Archa, flaga po sukcesie')
    # Sprawdzamy także prawdziwy blok [10], w tym odmowę i podsumowanie.
    main = (repo / 'install/install.sh').read_text()
    block = main[main.index('# Bluetooth jest opcjonalny'):main.index('# VirtualBox jest opcjonalny')]
    for answer, failure in [('n', False), ('y', False), ('y', True)]:
        flag.unlink(missing_ok=True)
        log.write_text('')
        code = 'SUMMARY_DONE=(); SUMMARY_SKIPPED=();\n' + block + '\nprintf "DONE=%s\\n" "${SUMMARY_DONE[*]}"; printf "SKIPPED=%s\\n" "${SUMMARY_SKIPPED[*]}"'
        # Platforma jawnie (Arch bez flagi), bash z PATH — nie FHS-owe /bin/bash.
        result = subprocess.run([shutil.which('bash'), '-c', code], env=env | {'ARCHENEMY_DIR': tmp, 'FAIL_INSTALL': str(int(failure)), 'PLATFORM': 'arch', 'SKIP_PACKAGES': '0'}, input=answer+'\n', text=True, capture_output=True, timeout=seconds(10))
        check(flag.exists() == (answer == 'y' and not failure), 'krok [10]: flaga ' + answer + '/' + str(failure))
        if answer == 'n':
            check(not log.read_text(), 'odmowa [10] bez instalacji')
        elif failure:
            check('SKIPPED=Bluetooth' in result.stdout and 'retry: bash' in result.stdout, 'porażka [10] w podsumowaniu z poleceniem')
        else:
            check('DONE=Bluetooth enabled' in result.stdout, 'sukces [10] w podsumowaniu')
    for rice in ['white-blue', 'tron', 'asia-n-rice', 'dither-flux', 'crt', 'yin', 'yang']:
        text = (repo / 'rices' / rice / 'waybar/config.jsonc').read_text()
        config = json.loads(re.sub(r'//[^\n]*', '', text))
        module = config['custom/bluetooth']
        check(config['modules-right'].count('custom/bluetooth') == 1 and 'interval' not in module and 'signal' not in module and module['exec-on-event'] is False, 'konfiguracja strumienia: ' + rice)
        check('#custom-bluetooth.off' in (repo / 'rices' / rice / 'waybar/style.css').read_text(), 'styl pustego modułu: ' + rice)
    check('custom/bluetooth' not in (repo / 'rices/white-blue_beta/waybar/config.jsonc').read_text(), 'beta bez zmian')
    check(run('git', '-C', str(repo), 'check-ignore', 'data/bluetooth-enabled.dat').returncode == 0, 'flaga ignorowana przez git')
    print(f'Wynik: {checks} ✓ / {len(failures)} ✗')
    for label in failures:
        print('  ✗ ' + label)
    if failures:
        sys.exit(1)
PY
