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
#   Pamięć wyboru PPM (data/bluetooth-power.dat): zapis atomowy przy toggle,
#   niezapisywalny data/ = kod 1 bez zmiany zasilania; „restart laptopa” =
#   nowy boot_id (ARCHENEMY_BOOT_ID_FILE) i pusty katalog sesji — z "off"
#   strumień wyłącza kontroler raz, "on"/brak/śmieci nic; ręczne włączenie
#   i restart waybara nie są cofane; późny kontroler, spóźnione AutoEnable,
#   limity okien (ARCHENEMY_BT_RESTORE_WAIT/_SETTLE), brak bluetoothctl.
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
    for name in ['scripts/waybar/bluetooth.sh', 'scripts/lib/runtime-dir.sh', 'install/bluetooth-installation.sh', 'install/lib/pkg.sh', 'packages/platform-map.tsv']:
        shutil.copy2(repo / name, root / name)
    osr = root / 'os'
    osr.mkdir()
    for key, text in {'arch': 'NAME="Arch Linux"\nID=arch\n', 'endeavouros': 'NAME="EndeavourOS"\nID=endeavouros\nID_LIKE=arch\n',
                      'fedora': 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=44\n', 'nixos': 'NAME=NixOS\nID=nixos\nVERSION_ID=26.05\n',
                      'ubuntu': 'NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\n'}.items():
        (osr / key).write_text(text)
    real_touch = shutil.which('touch')
    real_mktemp = shutil.which('mktemp')
    # Prywatny katalog sesji w drzewie testu (rwx------), nigdy /run/user hosta;
    # boot_id z pliku testowego — „restart laptopa” = nowa treść tego pliku.
    (root / 'runtime').chmod(0o700)
    env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'], MOCK_ROOT=tmp, ARCHENEMY_TEST='1',
               ARCHENEMY_OS_RELEASE=str(osr / 'arch'), ARCHENEMY_OSTREE_MARKER=str(osr / 'none'),
               ARCHENEMY_RUNTIME_SYSTEM=str(root / 'no-run-user'), ARCHENEMY_BOOT_ID_FILE=str(root / 'boot_id'))
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
state=$(cat "$MOCK_ROOT/state")
case "$1" in
 show)
  [[ "$state" == missing ]] && exit 0
  echo 'Controller 00:11:22:33:44:55 (public)'
  if [[ "$state" == disabled ]]; then echo 'Powered: no'; else echo 'Powered: yes'; fi ;;
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
exec cat "$MOCK_ROOT/events"
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
 is-active) [[ "${FAIL_ACTIVE:-0}" == 0 ]] ;;
esac
''',
        'bluetui': '#!/usr/bin/env bash\nexit 0\n',
        'alacritty': '#!/usr/bin/env bash\nprintf "alacritty %s\\n" "$*" >> "$MOCK_ROOT/log"\n',
    }
    # touch z FAIL_TOUCH=1 = błąd zapisu flagi (root omija prawa pliku, więc atrapa).
    mocks['touch'] = '#!/usr/bin/env bash\n[[ "${FAIL_TOUCH:-0}" == 0 ]] || exit 1\nexec ' + real_touch + ' "$@"\n'
    # mktemp z FAIL_MKTEMP=1 = niezapisywalny katalog data/ (z tego samego powodu).
    mocks['mktemp'] = ('#!/usr/bin/env bash\nif [[ "${FAIL_MKTEMP:-0}" != 0 ]]; then\n'
                       ' echo "mktemp: failed to create file via template \'$1\': Permission denied" >&2; exit 1\nfi\n'
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
        path = Path(f'/proc/{pid}/task/{pid}/children')
        return [int(x) for x in path.read_text().split()] if path.exists() else []
    def alive(pid):
        path = Path(f'/proc/{pid}/stat')
        return path.exists() and path.read_text().split(') ', 1)[1][0] != 'Z'
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
                    return len(descendants) == 1 and any(('sleep' if eof else 'cat') in
                           Path(f'/proc/{pid}/comm').read_text()
                           for pid in descendants if Path(f'/proc/{pid}/comm').exists())
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

    # ─── Pamięć wyboru PPM: data/bluetooth-power.dat, przywrócenie raz na start ───
    power = root / 'data/bluetooth-power.dat'
    marker = root / 'runtime/archenemy-bluetooth-restore'
    boot = root / 'boot_id'
    changed = 'signal sender=:1.2 -> destination=(null destination) interface=org.freedesktop.DBus.Properties; member=PropertiesChanged\n'
    def power_calls():
        return [line for line in log.read_text().splitlines() if line.startswith('power ')]
    def fresh_boot(n):
        # Restart laptopa: nowy boot_id i pusty katalog sesji (tmpfs /run/user).
        boot.write_text(f'TEST-boot-{n}\n')
        marker.unlink(missing_ok=True)
        log.write_text('')
    def start(extra=None):
        global proc
        proc = subprocess.Popen([str(bar)], env=env | (extra or {}), stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, start_new_session=True)
        return receive()
    def stop():
        # Linia JSON bywa odebrana, zanim python renderu wyjdzie; TERM w tej
        # chwili daje „Terminated” na stderr. Czekamy na sam nasłuch (cat).
        def idle():
            pids = children(proc.pid)
            return bool(pids) and all(Path(f'/proc/{pid}/comm').exists()
                                      and Path(f'/proc/{pid}/comm').read_text().strip() == 'cat' for pid in pids)
        wait_until(idle, 3, 'strumień bezczynny przed TERM')
        os.killpg(proc.pid, signal.SIGTERM)
        _, errors = proc.communicate(timeout=seconds(5))
        return proc.returncode == 0 and not errors
    def event(value):
        state.write_text(value)
        with (root / 'events').open('w', buffering=1) as events:
            events.write(changed)
        return receive()
    flag.touch()
    fresh_boot(1)
    for value, target, after in [('enabled', 'off', 'disabled'), ('disabled', 'on', 'enabled'), ('connected', 'off', 'disabled')]:
        state.write_text(value)
        result = run(str(bar), 'toggle')
        check(result.returncode == 0 and power.read_text() == target + '\n' and state.read_text().strip() == after,
              f'PPM zapisuje wybór: {value} → {target}')
    check(sorted(p.name for p in (root / 'data').iterdir()) == ['bluetooth-enabled.dat', 'bluetooth-power.dat'],
          'zapis atomowy: w data/ bez plików tymczasowych')
    power.write_text('on\n')
    state.write_text('enabled')
    log.write_text('')
    result = run(str(bar), 'toggle', extra={'FAIL_MKTEMP': '1'})
    check(result.returncode == 1 and 'cannot write' in result.stderr and 'bluetooth-power.dat' in result.stderr
          and 'not changed' in result.stderr,
          'niezapisywalny data/: kod 1 i czytelny błąd na stderr')
    check(power.read_text() == 'on\n' and state.read_text().strip() == 'enabled' and not power_calls(),
          'niezapisywalny data/: zasilanie i stary wybór nietknięte')
    check('notify-send' in log.read_text() and 'bluetooth-power.dat' in log.read_text(),
          'niezapisywalny data/: powiadomienie z nazwą pliku')
    log.write_text('')
    result = run(str(bar), 'toggle', extra={'FAIL_POWER': '1'})
    check(result.returncode != 0 and power.read_text() == 'on\n', 'nieudane power off: wybór niezapisany')
    check(sorted(p.name for p in (root / 'data').iterdir()) == ['bluetooth-enabled.dat', 'bluetooth-power.dat'],
          'nieudane power off: bez pliku tymczasowego')

    holder = os.open(root / 'events', os.O_RDWR | os.O_NONBLOCK)
    try:
        # Restart z „off”: AutoEnable włączył kontroler, strumień wyłącza go raz.
        power.write_text('off\n')
        fresh_boot(2)
        state.write_text('enabled')
        check(start()['class'] == 'disabled' and power_calls() == ['power off'], 'restart z off: kontroler wyłączony raz')
        check(marker.read_text().strip() == 'TEST-boot-2', 'znacznik przywrócenia = boot_id')
        check(event('enabled')['class'] == 'enabled' and power_calls() == ['power off'],
              'ręczne włączenie (bluetui) po starcie nie jest cofane')
        check(stop(), 'restart z off: strumień bez błędów')
        check(start()['class'] == 'enabled' and power_calls() == ['power off'],
              'restart waybara (Super+T) w tej samej sesji nie cofa ręcznego włączenia')
        check(stop(), 'restart waybara: strumień bez błędów')
        # Drugi restart laptopa: znów raz.
        fresh_boot(3)
        state.write_text('enabled')
        check(start()['class'] == 'disabled' and power_calls() == ['power off'], 'kolejny restart z off: znów raz')
        check(stop(), 'kolejny restart: strumień bez błędów')
        # „on”, brak pliku i śmieci = brak decyzji: zero power.
        for content in ['on\n', None, '', 'OFF\n', 'of\n', 'off off\n', 'offline\n', '\x00off\n', 'off\x1b[0m\n']:
            fresh_boot(4)
            power.unlink(missing_ok=True)
            if content is not None:
                power.write_bytes(content.encode())
            state.write_text('enabled')
            check(start()['class'] == 'enabled' and not power_calls(), f'start z {content!r}: kontroler nieruszany')
            check(stop(), f'start z {content!r}: strumień bez błędów')
        # Bez flagi ikony nie ingerujemy (moduł wyłączony).
        power.write_text('off\n')
        fresh_boot(5)
        flag.unlink()
        state.write_text('enabled')
        check(start()['text'] == '' and not power_calls(), 'bez flagi ikony: brak przywracania')
        check(stop(), 'bez flagi: strumień bez błędów')
        flag.touch()
        # Bez boot_id (niedostępny plik) = zachowanie jak dziś.
        fresh_boot(6)
        boot.unlink()
        state.write_text('enabled')
        check(start()['class'] == 'enabled' and not power_calls(), 'bez boot_id: brak przywracania')
        check(stop(), 'bez boot_id: strumień bez błędów')
        # Kontroler (albo BlueZ) wstaje po waybarze: zdarzenie D-Bus, potem off.
        fresh_boot(7)
        state.write_text('missing')
        check(start()['class'] == 'off' and not power_calls(), 'brak kontrolera na starcie: bez błędu, bez power')
        check(not reader.ready(0.5), 'brak kontrolera: bez pętli odpytywania')
        check(event('enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'kontroler pojawia się później: wyłączony raz')
        check(stop(), 'późny kontroler: strumień bez błędów')
        # AutoEnable po pojawieniu się kontrolera: najpierw Powered: no, potem yes.
        fresh_boot(8)
        state.write_text('disabled')
        check(start()['class'] == 'disabled' and not power_calls(), 'kontroler wyłączony na starcie: bez power')
        check(event('enabled')['class'] == 'disabled' and power_calls() == ['power off'],
              'AutoEnable chwilę po starcie: wyłączony raz')
        check(stop(), 'AutoEnable z opóźnieniem: strumień bez błędów')
        # Po oknie oczekiwania włączenie to decyzja użytkownika, nie AutoEnable.
        fresh_boot(9)
        state.write_text('disabled')
        check(start({'ARCHENEMY_BT_RESTORE_SETTLE': '1'})['class'] == 'disabled', 'okno AutoEnable 1 s: start')
        time.sleep(2.2)
        check(event('enabled')['class'] == 'enabled' and not power_calls(), 'włączenie po oknie AutoEnable nie jest cofane')
        check(marker.read_text().strip() == 'TEST-boot-9', 'po oknie: znacznik zapisany')
        check(stop(), 'okno AutoEnable: strumień bez błędów')
        fresh_boot(10)
        state.write_text('missing')
        check(start({'ARCHENEMY_BT_RESTORE_WAIT': '1'})['class'] == 'off', 'limit czekania na kontroler 1 s: start')
        time.sleep(2.2)
        check(event('enabled')['class'] == 'enabled' and not power_calls(), 'kontroler po limicie czekania: nieruszany')
        check(stop(), 'limit czekania: strumień bez błędów')
        # Wybór „on” z PPM w trakcie oczekiwania kończy przywracanie.
        power.write_text('off\n')
        fresh_boot(11)
        state.write_text('missing')
        start()
        power.write_text('on\n')
        check(event('enabled')['class'] == 'enabled' and not power_calls(), 'zmiana wyboru na on w trakcie oczekiwania')
        check(stop(), 'zmiana wyboru: strumień bez błędów')
        # Brak bluetoothctl: bez błędu i bez pętli.
        (root / 'bin/bluetoothctl').rename(root / 'bluetoothctl.off')
        if shutil.which('bluetoothctl', path=os.environ['PATH']) is None:
            power.write_text('off\n')
            fresh_boot(12)
            before = log.read_text().count('dbus-monitor ')
            check(start()['text'] == '' and not reader.ready(0.5), 'brak bluetoothctl: pusty moduł, bez pętli')
            check(log.read_text().count('dbus-monitor ') == before + 1 and not power_calls(), 'brak bluetoothctl: jedna subskrypcja, zero power')
            check(stop(), 'brak bluetoothctl: strumień bez błędów')
        else:
            print('  - pominięte: bluetoothctl jest w PATH hosta (brak binarki)')
        (root / 'bluetoothctl.off').rename(root / 'bin/bluetoothctl')
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate(timeout=seconds(5))
        os.close(holder)
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
    print(f'Wynik: {checks} ✓ / 0 ✗')
PY
