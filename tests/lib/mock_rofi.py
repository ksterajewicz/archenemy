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
#   Klawisze zatwierdzające (`-kb-accept-entry`, domyślnie
#   `Control+j,Control+m,Return,KP_Enter`, source/keyb.c:110–113; opcja z linii
#   poleceń zastępuje całą listę) według libnkutils w wersji przypiętej w rofi
#   2.0.0 (bindings/src/bindings.c:528–533, 803–816, 1104–1110) i powtarzania
#   klawiszy po stronie klienta (source/wayland/display.c:394–450):
#     - wpis bez `!` zatwierdza przy wciśnięciu, więc klawisz trzymany
#       zatwierdza zaznaczony wiersz KAŻDEJ kolejnej listy (powtarzanie),
#     - wpis z `!` zatwierdza raz, przy puszczeniu; powtarzanie nic nie robi,
#     - `!` poza pierwszym znakiem to błąd składni: rofi pokazuje okno błędu
#       zamiast menu (kod 2 atrapy),
#     - klawisz spoza listy niczego nie zatwierdza.
#   To model reguły przeczytanej w źródłach, nie dowód zachowania żywego rofi.
#   JEDEN proces atrapy = JEDNO okno: każdy start dopisuje linię do
#   $MOCK_ROFI/rofi.calls, więc pakiet widzi, czy drugi krok menu dostał
#   własny proces (dawny błąd: wejście między dwoma oknami przepadało).
#
#   Pliki w $MOCK_ROFI:
#     answers    — kolejne odpowiedzi „użytkownika”, po jednej w linii:
#                  tekst wiersza = wybór (Enter / dwuklik), pusta linia albo
#                  koniec pliku = Esc, `custom:<tekst>` = Enter na wpisanym
#                  tekście spoza listy, `key:<klawisz>` = klawisz wciśnięty
#                  i puszczony, `hold:<klawisz>` = klawisz wciśnięty i trzymany
#                  dłużej niż opóźnienie powtarzania, potem puszczony; nazwa
#                  klawisza jak we wpisie kb-accept-entry (`Return`,
#                  `Control+j`), zatwierdzany jest zaznaczony, czyli pierwszy
#                  wiersz. Wszystkie leżą w pliku od początku,
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
ACCEPT_DEFAULT = 'Control+j,Control+m,Return,KP_Enter'
# Trzymany klawisz na wciśnięciu powtarza się bez końca; atrapa przerywa po
# tylu listach, żeby błąd skryptu nie zawiesił pakietu.
REPEAT_LIMIT = 50


def accept_keys(spec):
    """kb-accept-entry → {klawisz: 'press' | 'release'}; None = błąd składni."""
    keys = {}
    for entry in spec.split(','):
        if not entry:
            continue
        release = entry.startswith('!')
        name = entry[1:] if release else entry
        if not name or '!' in name:
            return None
        keys[name] = 'release' if release else 'press'
    return keys


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
        if args[i] in ('-show', '-modes', '-modi', '-theme-str', '-p', '-kb-accept-entry') and i + 1 < len(args):
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
    accept = accept_keys(opts.get('-kb-accept-entry', ACCEPT_DEFAULT))
    if accept is None:
        append('rofi.log', '!! błąd składni kb-accept-entry: ' + opts['-kb-accept-entry'])
        return 2

    prompt = name
    no_custom = False
    held = False        # klawisz zatwierdzający na wciśnięciu jest trzymany
    repeats = 0
    headers, rows = run_mode(command, {'ROFI_RETV': '0'})
    while True:
        prompt = headers.get('prompt', prompt)
        no_custom = headers.get('no-custom', 'true' if no_custom else 'false') == 'true'
        if not rows:
            return 0
        append('rofi.log', prompt + ' => ' + '|'.join(text for text, _ in rows))
        append('rofi.info', '|'.join(text + '=' + f.get('info', '') for text, f in rows))

        if held:
            repeats += 1
            if repeats > REPEAT_LIMIT:
                append('rofi.log', '!! trzymany klawisz: lista wraca bez końca')
                return 1
            answer = rows[0][0]
        else:
            answer = next_answer()
            if answer == '':
                return 1
            kind, _, key = answer.partition(':')
            if kind in ('key', 'hold'):
                if key not in accept:
                    continue
                # Na wciśnięciu trzymany klawisz zatwierdza teraz i przy każdym
                # powtórzeniu; przy puszczeniu — jeden raz, jak zwykłe naciśnięcie.
                held = kind == 'hold' and accept[key] == 'press'
                answer = rows[0][0]
            elif kind == 'custom':
                if no_custom:
                    continue
                headers, rows = run_mode(command, {'ROFI_RETV': '2'}, key)
                continue
        chosen = [f for text, f in rows if text == answer]
        if not chosen:
            append('rofi.log', '!! brak wiersza: ' + answer)
            return 1
        if chosen[0].get('nonselectable') == 'true':
            held = False
            continue
        extra = {'ROFI_RETV': '1'}
        if 'info' in chosen[0]:
            extra['ROFI_INFO'] = chosen[0]['info']
        headers, rows = run_mode(command, extra, answer)


if __name__ == '__main__':
    sys.exit(main())
