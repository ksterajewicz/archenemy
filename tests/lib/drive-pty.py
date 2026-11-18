#!/usr/bin/env python3
# =============================================
#   archenemy - tests/lib/drive-pty.py
#   Uruchamia polecenie w terminalu (pty) i odpowiada na jego pytania według
#   listy. Bez terminala `read -p` nie drukuje promptu, więc testy podające
#   odpowiedzi potokiem nie widzą, na które pytanie odpowiadają — tu każda
#   odpowiedź idzie dopiero na rozpoznane pytanie.
#   Użycie: drive-pty.py <odpowiedzi> <transkrypcja> <zadane> <polecenie…>
#     odpowiedzi — linie "wzorzec<TAB>odpowiedź" (regex dopasowany do końca
#                  bieżącego, niezakończonego wiersza; pierwszy pasujący
#                  wygrywa; pusta odpowiedź = Enter; # = komentarz),
#     transkrypcja — całe wyjście bez kodów ANSI,
#     zadane — po jednej linii na pytanie: "pytanie => odpowiedź".
#   Kod wyjścia = kod polecenia; 124, gdy polecenie stoi na wierszu bez
#   pasującego wzorca dłużej niż DRIVE_IDLE s (domyślnie 15) albo cały bieg
#   trwa dłużej niż DRIVE_TIMEOUT s (domyślnie 300) — w zadanych "!! …".
# =============================================
import codecs
import os
import pty
import re
import select
import signal
import sys
import time

answers_path, transcript_path, asked_path = sys.argv[1:4]
command = sys.argv[4:]
rules = []
with open(answers_path, encoding='utf-8') as f:
    for line in f:
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        pattern, _, answer = line.partition('\t')
        rules.append((re.compile(pattern + r'\s*$'), answer))

ansi = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][A-Z0-9]|\r')
idle_limit = float(os.environ.get('DRIVE_IDLE', '15'))
deadline = time.monotonic() + float(os.environ.get('DRIVE_TIMEOUT', '300'))

pid, fd = pty.fork()
if pid == 0:
    os.execvp(command[0], command)

decoder = codecs.getincrementaldecoder('utf-8')('replace')
transcript, asked = [], []
tail = ''
last_output = time.monotonic()
stuck = None
while True:
    now = time.monotonic()
    if now > deadline:
        stuck = 'timeout'
    elif tail.strip() and now - last_output > idle_limit:
        stuck = 'no answer for: ' + tail.strip()
    if stuck:
        asked.append('!! ' + stuck)
        os.kill(pid, signal.SIGKILL)
        break
    if not select.select([fd], [], [], 0.2)[0]:
        continue
    try:
        data = os.read(fd, 65536)
    except OSError:          # EIO: wszystkie procesy zamknęły terminal
        break
    if not data:
        break
    last_output = now
    text = ansi.sub('', decoder.decode(data))
    transcript.append(text)
    tail = (tail + text).rsplit('\n', 1)[-1]
    for rx, answer in rules:
        if rx.search(tail):
            asked.append(f'{tail.strip()} => {answer}')
            os.write(fd, (answer + '\n').encode())
            tail = ''
            break

_, status = os.waitpid(pid, 0)
os.close(fd)
with open(transcript_path, 'w', encoding='utf-8') as f:
    f.write(''.join(transcript))
with open(asked_path, 'w', encoding='utf-8') as f:
    f.write(''.join(a + '\n' for a in asked))
if stuck:
    sys.exit(124)
code = os.waitstatus_to_exitcode(status)
sys.exit(code if code >= 0 else 128 - code)
