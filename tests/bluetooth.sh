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

repo = Path(os.environ['REPO'])
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    for name in ['scripts/waybar', 'install', 'data', 'bin']:
        (root / name).mkdir(parents=True)
    for name in ['scripts/waybar/bluetooth.sh', 'install/bluetooth-installation.sh']:
        shutil.copy2(repo / name, root / name)
    env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'], MOCK_ROOT=tmp)
    mocks = {
        'bluetoothctl': '''#!/bin/bash
printf 'bluetoothctl %s\\n' "$*" >> "$MOCK_ROOT/log"
shift 2
state=$(cat "$MOCK_ROOT/state")
case "$1" in
 show)
  [[ "$state" == missing ]] && exit 0
  echo 'Controller 00:11:22:33:44:55 (public)'
  if [[ "$state" == disabled ]]; then echo 'Powered: no'; else echo 'Powered: yes'; fi ;;
 devices) [[ "$state" != connected ]] || printf 'Device AA:BB:CC:DD:EE:FF Headphones "A" <&>\\nDevice 11:22:33:44:55:66 Keyboard\\n' ;;
 power) echo "power $2" >> "$MOCK_ROOT/log" ;;
esac
exit 0
''',
        'dbus-monitor': '''#!/bin/bash
printf 'dbus-monitor %s\\n' "$*" >> "$MOCK_ROOT/log"
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
