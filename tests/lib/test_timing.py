"""Zabezpieczenia harnessu; zegar i kontrakty produktu pozostają bez skali."""
import math
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time


def time_scale():
    raw = os.environ.get('ARCHENEMY_TEST_TIME_SCALE', '1')
    try:
        scale = float(raw)
    except ValueError:
        scale = float('nan')
    if not math.isfinite(scale) or not 1 <= scale <= 10:
        raise ValueError('ARCHENEMY_TEST_TIME_SCALE: wymagane skończone 1..10, jest: ' + raw)
    return scale


def seconds(base):
    return base * time_scale()


def wait_until(predicate, base, label):
    deadline = time.monotonic() + seconds(base)
    while True:
        if predicate():
            return
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError(f'ZABEZPIECZENIE: {label}; limit={seconds(base):g} s, skala={time_scale():g}')
        time.sleep(min(0.02, remaining))


class Lines:
    # os.read zamiast TextIO.readline: select nie widzi bufora TextIO, a sama
    # gotowość deskryptora nie gwarantuje pełnej linii ani końca oczekiwania.
    def __init__(self, stream):
        self.stream = stream
        self.pending = b''

    def receive(self, base=5):
        deadline = time.monotonic() + seconds(base)
        while b'\n' not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.stream], [], [], remaining)[0]:
                raise AssertionError(f'ZABEZPIECZENIE: brak pełnej linii strumienia; limit={seconds(base):g} s')
            chunk = os.read(self.stream.fileno(), 65536)
            assert chunk, 'strumień zamknięty przed pełną linią'
            self.pending += chunk
        line, self.pending = self.pending.split(b'\n', 1)
        return line.decode()

    def ready(self, timeout):
        # timeout obserwacji kontraktu przekazywany bez skali.
        return bool(self.pending) or bool(select.select([self.stream], [], [], timeout)[0])


def guard(limit, grace, marker, command):
    # Osobna sesja i jawny znacznik od nadzorcy: rc124/137 dziecka nie dowodzi
    # przekroczenia czasu. Plik znacznika tworzy wyłącznie ten nadzorca.
    proc = subprocess.Popen(command, start_new_session=True)
    interrupted = False

    def terminate(signum, frame):
        nonlocal interrupted
        interrupted = True
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, terminate)
    deadline = time.monotonic() + limit if limit else float('inf')
    while proc.poll() is None and not interrupted and time.monotonic() < deadline:
        try:
            proc.wait(timeout=0.05)
        except subprocess.TimeoutExpired:
            pass
    if proc.poll() is not None and not interrupted:
        return proc.returncode if proc.returncode >= 0 else 128 - proc.returncode
    expired = not interrupted
    if expired:
        Path(marker).write_text('RUN_ALL_TIMEOUT\n')
    terminate(None, None)
    forced = False
    try:
        proc.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        forced = True
    # Także wnuki ignorujące TERM po wcześniejszym wyjściu rodzica.
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait()
    return (137 if forced else 124) if expired else 130


def dialog(script, prefix, prompt, suffix='', delay=0, hup=False, after_prompt=''):
    # Standalone test uruchomiony spod nohup także musi móc dostarczyć HUP.
    proc = subprocess.Popen(['env', '--default-signal=INT,QUIT,HUP', 'bash', script], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            start_new_session=True)
    output = bytearray()
    try:
        proc.stdin.write(prefix.encode()); proc.stdin.flush()
        deadline = time.monotonic() + seconds(10)
        while prompt.encode() not in output:
            remaining = deadline - time.monotonic()
            assert remaining > 0, 'ZABEZPIECZENIE: brak promptu ' + prompt
            assert select.select([proc.stdout], [], [], remaining)[0], 'ZABEZPIECZENIE: brak promptu ' + prompt
            data = os.read(proc.stdout.fileno(), 65536)
            assert data, 'proces zakończył się przed promptem ' + prompt
            output.extend(data)
        if hup:
            proc.send_signal(signal.SIGHUP)
            # Wejście zostaje otwarte: EOF nie może udawać reakcji na HUP.
            proc.wait(timeout=seconds(5))
            os.set_blocking(proc.stdout.fileno(), False)
            while True:
                try:
                    chunk = os.read(proc.stdout.fileno(), 65536)
                except BlockingIOError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
            assert proc.returncode == 129, f'HUP: oczekiwano 129, jest {proc.returncode}'
            print('KONTRAKT: rollback po HUP (kod 129), bez EOF')
        else:
            # Celowa przerwa między bajtami klawisza: fixture, nie watchdog.
            proc.stdin.write(after_prompt.encode()); proc.stdin.flush()
            time.sleep(delay)
            rest, _ = proc.communicate(suffix.encode(), timeout=seconds(10))
            output.extend(rest)
            assert proc.returncode == 0, f'dialog: kod {proc.returncode}'
        sys.stdout.buffer.write(output)
    except BaseException:
        sys.stderr.buffer.write(output)
        raise
    finally:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=seconds(5))
        proc.stdin.close()
        proc.stdout.close()


def main():
    mode, *args = sys.argv[1:]
    if mode == 'scale':
        print(repr(time_scale()))
    elif mode == 'seconds-ceil':
        print(math.ceil(seconds(float(args[0]))))
    elif mode == 'guard':
        return guard(float(args[0]), float(args[1]), args[2], args[3:])
    elif mode == 'monitor-hup':
        dialog(args[0], args[1], 'Keep this monitor setting?', hup=True)
    elif mode == 'shell-key':
        dialog(args[0], '41', 'Press the key combination, then Enter',
               after_prompt='\x18', suffix='\x19\n', delay=0.5)
    elif mode == 'wait-pid':
        def stopped():
            stat = Path('/proc') / args[1] / 'stat'
            try:
                state = stat.read_text().rsplit(') ', 1)[1]
            except (FileNotFoundError, ProcessLookupError):
                # PID może zniknąć między sprawdzeniem ścieżki a open/read.
                return True
            return state.startswith('Z')
        wait_until(stopped, float(args[0]), 'koniec PID ' + args[1])
    elif mode == 'wait-file':
        def ready_file():
            try:
                return Path(args[1]).stat().st_size > 0
            except FileNotFoundError:
                return False
        wait_until(ready_file, float(args[0]), 'plik ' + args[1])
    else:
        raise ValueError('nieznana operacja: ' + mode)
    return 0


if __name__ == '__main__':
    sys.exit(main())
