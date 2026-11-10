#!/bin/bash
# =============================================
#   Zgodność menu wierszowych z potokami i strzałkami.
# =============================================
set -uo pipefail
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/appbinds/lib/tui.sh"
check() {
    local input="$1" want="$2" rc=0
    tui_menu_lines 0 one two three <<<"$input" >/dev/null || rc=$?
    [[ "$rc:$TUI_MENU_INDEX" == "$want" ]] || { echo "✗ menu: $input → $rc:$TUI_MENU_INDEX, expected $want"; exit 1; }
}
check 2 0:1
check $'\e[B' 0:1
check j 0:1
check k 0:2
check $'\e[A' 0:2
check $'\e' 1:2
check '' 1:2
check 9 2:2
# shellcheck disable=SC2034  # skróty odczytuje wspólna biblioteka
TUI_MENU_KEYS=(a b c)
check c 0:2
check q 1:2
items=(); for (( i=1; i<=12; i++ )); do items+=("item $i"); done
tui_menu_lines 0 "${items[@]}" <<<12 >/dev/null
[[ "$TUI_MENU_INDEX" == 11 ]] || exit 1
if tui_menu_lines 0 one </dev/null >/dev/null; then exit 1; fi
echo 'Wynik: menu wierszowe — zielone'

# PTY uruchamia rzeczywistą ścieżkę terminalową, także przy małym oknie.
python - "$(dirname "${BASH_SOURCE[0]}")/../scripts/appbinds/lib/tui.sh" <<'PYTEST'
import os, pty, select, subprocess, sys, time
lib = sys.argv[1]
def run(code, keys):
    master, slave = pty.openpty()
    proc = subprocess.Popen(['bash', '-c', 'source "$1"; ' + code, '_', lib], stdin=slave, stdout=slave, stderr=slave,
                            env={**os.environ, 'ARCHENEMY_TUI_SIZE': '8 100'})
    os.close(slave)
    output = b''
    sent = False
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if select.select([master], [], [], .1)[0]:
            try: chunk = os.read(master, 65536)
            except OSError: break
            output += chunk
            if not sent and output:
                time.sleep(.05)
                os.write(master, keys); sent = True
        if proc.poll() is not None: break
    try: proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill(); raise AssertionError(('PTY timeout', output))
    os.close(master)
    assert proc.wait() == 0, output
    return output.decode(errors='replace')
code = 'items=(); for ((i=1;i<=12;i++)); do items+=("item $i"); done; tui_menu_lines 0 "${items[@]}"; echo RESULT:$TUI_MENU_INDEX'
out = run(code, b'12\n')
assert 'RESULT:11' in out, out
out = run(code, b'\x1b[F\n')
assert 'RESULT:11' in out and '12) item 12' in out, out
assert '\x1b[6A' in out and '\x1b[14A' not in out, out
out = run('TUI_MENU_CAPTURE_DIGITS=1; TUI_MENU_NUMBERS=(21 22); tui_menu 0 app21 app22 "Save [s]"; echo RESULT:$TUI_MENU_INPUT', b'21\n')
assert '21) app21' in out and '22) app22' in out and '3) Save' not in out and 'RESULT:21' in out, out
from pathlib import Path
monitor = Path(lib).resolve().parents[2] / 'hypr/monitor-settings.sh'
source = monitor.read_text()
functions = source[source.index('pick_number() {'):source.index('split_picked_mode() {')]
code = 'ARCHENEMY_TUI_SIZE="15 100"; ' + functions + '\nlive_resolutions() { printf "1920x1080\\n1280x720\\n"; }; live_rates() { echo CALLED >&2; }; if pick_mode test 1920x1080; then exit 1; fi; echo RESULT:cancel'
out = run(code, b'\x1b')
assert 'RESULT:cancel' in out and 'CALLED' not in out, out
assert out.count('1) 1920x1080') == 1, out
print('PTY: numery 12/21, globalne etykiety i przewijanie — zielone')
PYTEST
