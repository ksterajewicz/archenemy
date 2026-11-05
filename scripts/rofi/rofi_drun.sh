#!/bin/bash

# =============================================
#   archenemy - rofi_drun.sh
#   Launcher aplikacji (Super+R, ikona w waybarze): `rofi -show drun`
#   z bramką na tekst wpisany ręcznie.
#
#   Enter przy pustej liście (tekst nie pasuje do żadnej aplikacji) rofi
#   traktuje jak polecenie i próbuje je wykonać, a przy braku binarki pokazuje
#   okno błędu „Failed to execute” (rofi 2.0.0, source/modes/drun.c,
#   MENU_CUSTOM_INPUT; `-no-custom` działa tylko w dmenu). Wpisanie `reboot`
#   wykonałoby więc reboot. Tryb drun nie ma opcji, która to wyłącza, ale
#   wpisany tekst i wpisy .desktop idą przez ten sam szablon `run-command`
#   (helper_execute_command), dlatego bramka stoi właśnie tam: uruchamiamy
#   tylko to, co ma wpis Exec= w plikach .desktop. Reszta = cisza, kod 0.
#
#   Wpisy Terminal=true idą przez `run-shell-command`, czyli obok bramki.
#   Tekst z niedomkniętym cudzysłowem rofi odrzuci sam, zanim tu dotrze.
# =============================================

set -uo pipefail

# Pierwszy token Exec= bez otwierającego cudzysłowu, jak po sparsowaniu przez
# rofi (g_shell_parse_argv). Kod 0 = binarka należy do wpisu .desktop.
is_desktop_command() {
    local bin="$1" dir value found_any=0 entries
    local -a dirs=()
    IFS=: read -ra dirs <<<"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for dir in "${dirs[@]}"; do
        [[ -d "$dir/applications" ]] || continue
        entries="$(grep -rhs --include='*.desktop' '^Exec=' "$dir/applications")" || continue
        found_any=1
        while IFS= read -r value; do
            value="${value#Exec=}"
            value="${value#[\"\']}"
            case "$value" in
                "$bin"|"$bin "*|"$bin\""*|"$bin'"*) return 0 ;;
            esac
        done <<<"$entries"
    done
    # Żadnego wpisu w żadnym katalogu = zepsute środowisko, nie literówka.
    # Lepiej przepuścić niż odciąć launcher od wszystkich aplikacji.
    ((found_any)) || return 0
    return 1
}

if [[ "${1:-}" == "--exec" ]]; then
    shift
    (($#)) || exit 0
    is_desktop_command "$1" || exit 0
    exec "$@"
fi

# Ścieżka w pojedynczym cudzysłowie, bo rofi parsuje szablon jak powłoka,
# a nie rozwija `~`. Znak ' w $HOME wymaga zamiany, by nie rozerwać szablonu.
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SELF="${SELF//\'/\'\\\'\'}"
exec rofi -show drun -run-command "'$SELF' --exec {cmd}" "$@"
