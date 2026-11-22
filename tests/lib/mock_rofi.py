#!/usr/bin/env python3
# =============================================
#   archenemy - tests/lib/mock_rofi.py
#   Atrapa rofi w trybie skryptowym dla tests/rofi-power-menu.sh (pakiet
#   kopiuje ją jako `rofi` na początek PATH). Modeluje kontrakt rofi 2.0.0
#   (source/modes/script.c, rofi-script(5)):
#     - `-show NAZWA -modes NAZWA:POLECENIE`; polecenie dzielone na słowa jak
#       w powłoce i szukane w PATH (g_shell_parse_argv, G_SPAWN_SEARCH_PATH),
#     - start: polecenie bez argumentu, ROFI_RETV=0,
#     - wybór wiersza: polecenie z tekstem wiersza w argumencie, ROFI_RETV=1,
#       ROFI_INFO tylko wtedy, gdy wiersz ma pole info,
#     - rofi czyta wyjście polecenia DO KOŃCA (blokująco), linia zaczynająca
#       się od NUL to nagłówek `klucz\x1fwartość`, reszta to wiersze
#       `tekst\0klucz\x1fwartość…`,
#     - są wiersze → ta sama instancja pokazuje nową listę; brak → koniec,
#     - no-custom=true: tekst spoza listy nie trafia do polecenia.
#   JEDEN proces atrapy = JEDNO okno: każdy start dopisuje linię do
#   $MOCK_ROFI/rofi.calls, więc pakiet widzi, czy drugi krok menu dostał
#   własny proces (dawny błąd: wejście między dwoma oknami przepadało).
#
#   Pliki w $MOCK_ROFI:
#     answers    — kolejne odpowiedzi „użytkownika”, po jednej w linii:
#                  tekst wiersza = wybór (Enter / dwuklik), pusta linia albo
#                  koniec pliku = Esc, `custom:<tekst>` = Enter na wpisanym
#                  tekście spoza listy. Wszystkie leżą w pliku od początku,
#                  czyli wejście „szybsze niż menu”: nic nie czeka na ekran.
#     rofi.log   — po jednej linii na pokazaną listę: `prompt => w1|w2`,
#     rofi.info  — pola info tych wierszy: `w1=info1|w2=info2`,
#     rofi.calls — po jednej linii na start procesu,
#     theme      — ostatni -theme-str.
#   Kod wyjścia: 0 po zamknięciu przez polecenie, 1 po Esc, 2 przy wywołaniu,
#   którego ta atrapa nie modeluje (np. -dmenu).
# =============================================
import os
import shlex
import subprocess
import sys

state = os.environ['MOCK_ROFI']


def append(name, line):
    with open(os.path.join(state, name), 'a', encoding='utf-8') as f:
        f.write(line + '\n')


def next_answer():
    path = os.path.join(state, 'answers')
    try:
        with open(path, encoding='utf-8') as f:
            lines = f.read().split('\n')
    except FileNotFoundError:
        return ''
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines[1:]))
    return lines[0]


def run_mode(command, extra_env, arg=None):
    """Zwraca (nagłówki, wiersze); wiersz = (tekst, {pole: wartość})."""
    env = dict(os.environ)
    env.pop('ROFI_RETV', None)
    env.update(extra_env)
    env['ROFI_OUTSIDE'] = str(os.getpid())
    argv = shlex.split(command) + ([arg] if arg is not None else [])
    # stdout przez potok czytany do końca, stderr dziedziczony — jak w rofi.
    out = subprocess.run(argv, env=env, stdout=subprocess.PIPE, check=False).stdout
    headers, rows = {}, []
    for raw in out.split(b'\n'):
        if not raw:
            continue
        if raw.startswith(b'\0'):
            key, _, value = raw[1:].decode('utf-8').partition('\x1f')
            headers[key] = value
            continue
        text, _, extras = raw.partition(b'\0')
        fields = extras.decode('utf-8').split('\x1f') if extras else []
        rows.append((text.decode('utf-8'), dict(zip(fields[0::2], fields[1::2]))))
    return headers, rows


def main():
    args = sys.argv[1:]
    opts = {}
    i = 0
    while i < len(args):
        if args[i] in ('-show', '-modes', '-modi', '-theme-str', '-p') and i + 1 < len(args):
            opts[args[i]] = args[i + 1]
            i += 1
        else:
            opts[args[i]] = ''
        i += 1
    append('rofi.calls', ' '.join(a for a in args if '\n' not in a))
    with open(os.path.join(state, 'theme'), 'w', encoding='utf-8') as f:
        f.write(opts.get('-theme-str', ''))

    show = opts.get('-show', '')
    modes = opts.get('-modes', opts.get('-modi', ''))
    name, _, command = modes.partition(':')
    if '-dmenu' in opts or not show or name != show or not command:
        append('rofi.log', '!! wywołanie spoza trybu skryptowego: ' + ' '.join(args[:4]))
        return 2

    prompt = name
    no_custom = False
    headers, rows = run_mode(command, {'ROFI_RETV': '0'})
    while True:
        prompt = headers.get('prompt', prompt)
        no_custom = headers.get('no-custom', 'true' if no_custom else 'false') == 'true'
        if not rows:
            return 0
        append('rofi.log', prompt + ' => ' + '|'.join(text for text, _ in rows))
        append('rofi.info', '|'.join(text + '=' + f.get('info', '') for text, f in rows))

        answer = next_answer()
        if answer == '':
            return 1
        if answer.startswith('custom:'):
            if no_custom:
                continue
            headers, rows = run_mode(command, {'ROFI_RETV': '2'}, answer[len('custom:'):])
            continue
        chosen = [f for text, f in rows if text == answer]
        if not chosen:
            append('rofi.log', '!! brak wiersza: ' + answer)
            return 1
        if chosen[0].get('nonselectable') == 'true':
            continue
        extra = {'ROFI_RETV': '1'}
        if 'info' in chosen[0]:
            extra['ROFI_INFO'] = chosen[0]['info']
        headers, rows = run_mode(command, extra, answer)


if __name__ == '__main__':
    sys.exit(main())
