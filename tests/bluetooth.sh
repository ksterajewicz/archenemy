#!/bin/bash
# =============================================
#   archenemy - tests/bluetooth.sh
#   Atrapy BlueZ, D-Bus, pacmana i systemctl; bez sprzętu i usług hosta.
# =============================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO
python - <<'PY'
import json
import os
from pathlib import Path
import re
import select
import shutil
import signal
import subprocess
import tempfile
import time

repo = Path(os.environ['REPO'])
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    for name in ['scripts/waybar', 'install', 'data', 'bin', 'home', 'config', 'cache', 'state-home', 'runtime']:
        (root / name).mkdir(parents=True)
    for name in ['scripts/waybar/bluetooth.sh', 'install/bluetooth-installation.sh']:
        shutil.copy2(repo / name, root / name)
    env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'], MOCK_ROOT=tmp)
    for key in ['DBUS_SESSION_BUS_ADDRESS', 'WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE']:
        env.pop(key, None)
    env.update(HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'config'),
               XDG_CACHE_HOME=str(root / 'cache'), XDG_STATE_HOME=str(root / 'state-home'),
               XDG_DATA_HOME=str(root / 'data'), XDG_RUNTIME_DIR=str(root / 'runtime'), TMPDIR=tmp)
    mocks = {
        'bluetoothctl': '''#!/bin/bash
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
 power) echo "power $2" >> "$MOCK_ROOT/log" ;;
esac
exit 0
''',
        'dbus-monitor': '''#!/bin/bash
printf 'dbus-monitor %s\\n' "$*" >> "$MOCK_ROOT/log"
[[ "${MOCK_EOF:-0}" == 0 ]] || exit 0
exec cat "$MOCK_ROOT/events"
''',
        'sudo': '#!/bin/bash\nexec "$@"\n',
        'pacman': '''#!/bin/bash
printf 'pacman %s\\n' "$*" >> "$MOCK_ROOT/log"
if [[ "$1" == -S ]]; then [[ "${FAIL_INSTALL:-0}" == 0 ]]; else [[ "${FAIL_QUERY:-0}" == 0 ]]; fi
''',
        'systemctl': '''#!/bin/bash
printf 'systemctl %s\\n' "$*" >> "$MOCK_ROOT/log"
case "$1" in
 enable) [[ "${FAIL_ENABLE:-0}" == 0 ]] ;;
 is-enabled) [[ "${FAIL_ENABLED:-0}" == 0 ]] ;;
 is-active) [[ "${FAIL_ACTIVE:-0}" == 0 ]] ;;
esac
''',
        'bluetui': '#!/bin/bash\nexit 0\n',
        'alacritty': '#!/bin/bash\nprintf "alacritty %s\\n" "$*" >> "$MOCK_ROOT/log"\n',
    }
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
        return subprocess.run(args, env=env | (extra or {}), text=True, capture_output=True, timeout=10)
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
    check(data['class'] == 'connected' and elapsed < 1,
          f'pojedynczy render {elapsed:.3f} s < 1 s mimo semantyki wewnętrznego --timeout')
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

    # Strumień reaguje na sygnały magistrali i USR1, bez uruchamiania sondy co sekundę.
    os.mkfifo(root / 'events')
    state.write_text('disabled')
    proc = subprocess.Popen([str(bar)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    def receive():
        assert select.select([proc.stdout], [], [], 5)[0], 'brak aktualizacji strumienia'
        return json.loads(proc.stdout.readline())
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
            time.sleep(0.7)
            renders = log.read_text().count('bluetoothctl show') - before
            check(1 <= renders <= 2, f'seria 100 zdarzeń daje {renders} render(y), najwyżej 2')
            flag.unlink()
            proc.send_signal(signal.SIGUSR1)
            check(receive()['text'] == '', 'USR1 ponownie odczytuje flagę')
            flag.touch()
            state.write_text('enabled')
            proc.send_signal(signal.SIGUSR1)
            check(receive()['class'] == 'enabled', 'USR1 przywraca ikonę')
            check(not select.select([proc.stdout], [], [], 0.2)[0], 'strumień bez okresowego odpytywania')
            matches = log.read_text()
            check('org.bluez' in matches and 'PropertiesChanged' in matches and 'ObjectManager' in matches and 'NameOwnerChanged' in matches, 'subskrypcje właściwości, hotplug i restartu BlueZ')
    finally:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
        check(not proc.stderr.read(), 'strumień bez błędów stderr')

    # EOF wymusza opóźniony reconnect i nową migawkę, bez ciasnej pętli.
    state.write_text('enabled')
    proc = subprocess.Popen([str(bar)], env=env | {'MOCK_EOF': '1'}, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        check(receive()['class'] == 'enabled', 'EOF: pierwsza migawka')
        started = time.monotonic()
        before = log.read_text().count('dbus-monitor ')
        check(not select.select([proc.stdout], [], [], 0.5)[0], 'EOF: brak natychmiastowego reconnectu')
        assert select.select([proc.stdout], [], [], 7)[0], 'brak reconnectu po EOF'
        check(json.loads(proc.stdout.readline())['class'] == 'enabled'
              and time.monotonic() - started >= 4.5
              and log.read_text().count('dbus-monitor ') == before + 1,
              'EOF: ponowna subskrypcja i migawka po 5 s')
    finally:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.communicate(timeout=5)

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
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    descendants = children(proc.pid)
                    if len(descendants) == 1 and any(('sleep' if eof else 'cat') in
                                           Path(f'/proc/{pid}/comm').read_text()
                                           for pid in descendants if Path(f'/proc/{pid}/comm').exists()):
                        break
                    time.sleep(0.02)
                else:
                    raise AssertionError('nie uruchomiono oczekiwanego potomka')
                if group:
                    os.killpg(proc.pid, signal.SIGTERM)
                else:
                    proc.terminate()
                _, errors = proc.communicate(timeout=3)
                check(proc.returncode == 0 and not errors and not any(alive(pid) for pid in descendants),
                      f'sprzątanie potomków: EOF={eof}, killpg={group}')
            finally:
                os.close(holder)
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.communicate(timeout=3)
                for pid in descendants:
                    if alive(pid):
                        os.kill(pid, signal.SIGKILL)

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
    # Sprawdzamy także prawdziwy blok [10], w tym odmowę i podsumowanie.
    main = (repo / 'install/install.sh').read_text()
    block = main[main.index('# Bluetooth jest opcjonalny'):main.index('# VirtualBox jest opcjonalny')]
    for answer, failure in [('n', False), ('y', False), ('y', True)]:
        flag.unlink(missing_ok=True)
        log.write_text('')
        code = 'SUMMARY_DONE=(); SUMMARY_SKIPPED=();\n' + block + '\nprintf "DONE=%s\\n" "${SUMMARY_DONE[*]}"; printf "SKIPPED=%s\\n" "${SUMMARY_SKIPPED[*]}"'
        result = subprocess.run(['/bin/bash', '-c', code], env=env | {'ARCHENEMY_DIR': tmp, 'FAIL_INSTALL': str(int(failure))}, input=answer+'\n', text=True, capture_output=True, timeout=10)
        check(flag.exists() == (answer == 'y' and not failure), 'krok [10]: flaga ' + answer + '/' + str(failure))
        if answer == 'n':
            check(not log.read_text(), 'odmowa [10] bez instalacji')
        elif failure:
            check('SKIPPED=Bluetooth' in result.stdout and 'retry: bash' in result.stdout, 'porażka [10] w podsumowaniu z poleceniem')
        else:
            check('DONE=Bluetooth enabled' in result.stdout, 'sukces [10] w podsumowaniu')
    for rice in ['white-blue', 'tron', 'asia-n-rice', 'dither-flux', 'crt']:
        text = (repo / 'rices' / rice / 'waybar/config.jsonc').read_text()
        config = json.loads(re.sub(r'//[^\n]*', '', text))
        module = config['custom/bluetooth']
        check(config['modules-right'].count('custom/bluetooth') == 1 and 'interval' not in module and 'signal' not in module and module['exec-on-event'] is False, 'konfiguracja strumienia: ' + rice)
        check('#custom-bluetooth.off' in (repo / 'rices' / rice / 'waybar/style.css').read_text(), 'styl pustego modułu: ' + rice)
    check('custom/bluetooth' not in (repo / 'rices/white-blue_beta/waybar/config.jsonc').read_text(), 'beta bez zmian')
    check(run('git', '-C', str(repo), 'check-ignore', 'data/bluetooth-enabled.dat').returncode == 0, 'flaga ignorowana przez git')
    print(f'Wynik: {checks} ✓ / 0 ✗')
PY
