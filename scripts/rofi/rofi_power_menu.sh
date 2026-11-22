#!/usr/bin/env bash

# =============================================
#   archenemy - rofi_power_menu.sh
#   Menu zasilania (rofi): wyłączenie / restart.
#   Otwierane przez Super + prawy Shift.
#   UI po angielsku (decyzja właściciela 2026-07-12).
# =============================================

POWEROFF="󰐥  Power off"
REBOOT="󰜉  Reboot"
YES="Yes"
NO="No"
MODE="archenemy-power"

# ── Tryb skryptowy rofi (rofi-script(5)) ─────────────────────────────────────
# Oba kroki (wybór akcji, potwierdzenie) idą w JEDNYM oknie rofi. Dawniej były
# to dwa osobne procesy `rofi -dmenu`: między zamknięciem pierwszego okna a
# pojawieniem się drugiego klawiatura i mysz wracały do okna pod spodem, więc
# szybkie drugie Enter albo kliknięcie przepadało i pytanie „Are you sure?”
# zostawało bez odpowiedzi (zgłoszenie właściciela 2026-11-22: „gdy klika się
# za szybko, to laptop się nie wyłącza”). W trybie skryptowym rofi woła ten sam
# plik: bez argumentu po listę startową (ROFI_RETV=0), a po wyborze wiersza
# z jego tekstem w $1 (ROFI_RETV=1) i polem „info” wiersza w ROFI_INFO.
# Wypisane wiersze zastępują listę w tym samym oknie, brak wierszy zamyka rofi.
# Zdarzenia wejścia czekają w kolejce tego jednego okna, więc nic nie ginie.
#
# Bezpieczeństwo: wyłączenie nadal wymaga DWÓCH wyborów (akcja, potem „Yes”);
# jedno przypadkowe Enter albo kliknięcie w chwili otwarcia kończy się najwyżej
# na pytaniu. Każdy wiersz niesie w „info”, co robi, a akcja rusza tylko przy
# zgodnej parze tekst + info — tekst wpisany z klawiatury (no-custom), „No”,
# Esc i wszystko nieznane zamykają menu bez skutku.
# Świadoma cena szybkości: drugim wyborem jest KAŻDE kolejne zatwierdzenie,
# także powtarzanie przytrzymanego Entera (po opóźnieniu powtarzania klawiszy,
# domyślnie 600 ms) i trzecie kliknięcie tej samej serii. Opóźnienie przed
# „Yes” odrzucałoby właśnie szybkie podwójne Enter, o które chodziło w zgłoszeniu.
power_menu_header() { printf '\0prompt\x1f%s\n\0no-custom\x1ftrue\n' "$1"; }
power_menu_row()    { printf '%s\0info\x1f%s\n' "$1" "$2"; }

power_menu_confirm() {
    power_menu_header "Are you sure?"
    power_menu_row "$YES" "do:$1"
    power_menu_row "$NO"  "cancel"
}

# Akcja startuje w tle, odcięta od potoku: rofi czeka na koniec wyjścia skryptu
# (rofi-script(5), „Executing external program”), a systemctl może czekać na
# agenta polkit — okno menu z wyłączną klawiaturą nie może wtedy wisieć.
# stderr zostaje (rofi go nie czyta): błąd systemctl trafia do logu sesji.
power_menu_run() { systemctl "$1" </dev/null >/dev/null & }

power_menu_step() {
    case "${ROFI_RETV:-}" in
        0)  power_menu_header "Power"
            power_menu_row "$POWEROFF" "ask:poweroff"
            power_menu_row "$REBOOT"   "ask:reboot" ;;
        1)  case "${1:-}|${ROFI_INFO:-}" in
                "$POWEROFF|ask:poweroff") power_menu_confirm poweroff ;;
                "$REBOOT|ask:reboot")     power_menu_confirm reboot ;;
                "$YES|do:poweroff")       power_menu_run poweroff ;;
                "$YES|do:reboot")         power_menu_run reboot ;;
            esac ;;
    esac
}

if [[ -n "${ROFI_RETV:-}" ]]; then
    power_menu_step "$@"
    exit 0
fi

# Pod blokadą (hyprlock / ext-session-lock-v1) protokół rezerwuje wejście
# wyłącznie dla klienta blokady — rofi nie dostałoby klawiatury. Dlatego
# przy aktywnym hyprlocku wyłączamy bezpośrednio, bez menu i potwierdzenia
# (akord Super+prawy Shift jest nie do trafienia przypadkiem). Bind w rice'ach
# ma flagę "l" (bindl), żeby w ogóle odpalił się przy zablokowanym ekranie.
if pidof hyprlock >/dev/null 2>&1; then
    systemctl poweroff
    exit 0
fi

# Kompaktowe okno bez pola wyszukiwania — 2 pozycje, motyw rice'a zostaje
THEME_STR='
window   { width: 340px; }
listview { lines: 2; fixed-height: false; }
inputbar { children: [ prompt ]; }
'
# Font z Super+A → [f] (scripts/appbinds/lib/fonts.sh); pusto = font rice'a.
FONT_LIB="${ARCHENEMY_DIR:-$HOME/archenemy}/scripts/appbinds/lib/fonts.sh"
# shellcheck source=/dev/null
[[ -f "$FONT_LIB" ]] && THEME_STR+="$( source "$FONT_LIB" && font_rofi_theme_str )"

# rofi dzieli listę trybów na „,” i „#”, a polecenie trybu na słowa, więc
# zamiast ścieżki dostaje samą nazwę pliku, a katalog skryptu idzie na początek
# PATH (rofi szuka polecenia trybu w PATH). ROFI_INFO z otoczenia nie może
# udawać wyboru wiersza.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
SELF_NAME="$(basename "${BASH_SOURCE[0]}")"
unset ROFI_INFO ROFI_DATA
PATH="$SELF_DIR:$PATH" rofi -show "$MODE" -modes "$MODE:$SELF_NAME" -theme-str "$THEME_STR"
exit 0
