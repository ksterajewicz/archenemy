#!/usr/bin/env bash
# =============================================
#   archenemy - tests/rofi-power-menu.sh
#   Menu zasilania Super+prawy Shift (scripts/rofi/rofi_power_menu.sh) na
#   atrapach rofi, pidof i systemctl. Atrapa systemctl tylko zapisuje
#   wywołanie: test NICZEGO nie wyłącza ani nie restartuje, a bez atrapy
#   na początku PATH odmawia uruchomienia skryptu.
#
#   Powód powstania (audyt 2026-11-05, KT7): skrypt, który wyłącza komputer,
#   nie miał testu. Sprawdzane: pod hyprlockiem od razu poweroff bez menu
#   (DECYZJE 2026-07-28), poza blokadą dwa kroki z potwierdzeniem „Yes”,
#   Esc albo „No” niczego nie robią, UI po angielsku (DECYZJE 2026-07-12).
#   Od 2026-11-22 oba kroki idą w jednym oknie rofi (tryb skryptowy); atrapa
#   rofi to tests/lib/mock_rofi.py — jej nagłówek opisuje modelowany kontrakt.
#   Zgłoszenie właściciela 2026-11-22 („gdy klika się za szybko, to laptop się
#   nie wyłącza”): dwa procesy rofi gubiły wejście wysłane między oknami.
#   Pakiet pilnuje więc: jeden proces rofi na oba kroki, wiersze niosące swoją
#   akcję w polu info, podrobione wywołania zwrotne bez skutku, akcja w tle
#   nietrzymająca okna i to samo wiązanie we wszystkich rice'ach.
#   Decyzja właściciela 2026-11-22 (wariant C): Enter zatwierdza przy
#   puszczeniu klawisza (`-kb-accept-entry '!Return,!KP_Enter'`), żeby
#   przytrzymany Enter nie przeszedł przez pytanie „Are you sure?”. Pakiet
#   pilnuje, że skrypt podaje tę opcję, a atrapa modeluje jej regułę ze źródeł
#   libnkutils (wciśnięcie z powtarzaniem kontra puszczenie).
#   Atrapa nie ma zegara ani okna: szybkości ani prawdziwej klawiatury na żywym
#   rofi/Hyprlandzie nie sprawdza (kroki na laptopie — raport zlecenia, README
#   „Verification”).
#   Uruchom: bash tests/rofi-power-menu.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
# shellcheck source=tests/lib/timing.sh
source "$REPO/tests/lib/timing.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1
test_timing_init "$T"
PM="$REPO/scripts/rofi/rofi_power_menu.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

mkdir -p "$T/bin"
# systemctl: tylko zapis wywołania. Plik $T/systemctl.hold = akcja „wisi”
# (np. czeka na agenta polkit), dopóki ten plik istnieje.
printf '#!/usr/bin/env bash\necho "$*" >> "%s/systemctl.log"\nwhile [[ -e "%s/systemctl.hold" ]]; do sleep 0.05; done\n' "$T" "$T" > "$T/bin/systemctl"
# pidof: hyprlock „działa”, gdy istnieje plik $T/locked.
printf '#!/usr/bin/env bash\n[[ "$1" == hyprlock && -f "%s/locked" ]]\n' "$T" > "$T/bin/pidof"
# rofi: atrapa trybu skryptowego (jeden proces = jedno okno), stan w $MOCK_ROFI.
cp "$REPO/tests/lib/mock_rofi.py" "$T/bin/rofi"
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" ARCHENEMY_DIR="$T/no-repo" MOCK_ROFI="$T"
[[ "$(command -v systemctl)" == "$T/bin/systemctl" ]] || { echo "  ✗ atrapa systemctl nie jest pierwsza w PATH — przerywam"; exit 1; }
[[ "$(command -v rofi)" == "$T/bin/rofi" ]] || { echo "  ✗ atrapa rofi nie jest pierwsza w PATH — przerywam"; exit 1; }

POWEROFF="󰐥  Power off"; REBOOT="󰜉  Reboot"
# run <odpowiedzi rofi, po jednej w linii> — wynik w RC. Akcja (systemctl)
# startuje w tle, więc bieg zbiera stderr przez $(…): podstawienie kończy się
# dopiero, gdy stderr zamkną WSZYSTKIE procesy potomne, także atrapa systemctl.
# Dzięki temu „bez systemctl” znaczy „nie uruchomiono”, a nie „jeszcze nie zdążył”.
run() {
    rm -f "$T/systemctl.log" "$T/rofi.log" "$T/rofi.info" "$T/rofi.calls"
    printf '%s' "$1" > "$T/answers"
    ERR="$(test_timeout 20 bash "${2:-$PM}" 2>&1 >/dev/null </dev/null)"; RC=$?
}
calls() { cat "$T/systemctl.log" 2>/dev/null; }
menus() { grep -c . "$T/rofi.log" 2>/dev/null || true; }
windows() { grep -c . "$T/rofi.calls" 2>/dev/null || true; }

echo "== pod hyprlockiem"
touch "$T/locked"
run ""
check "od razu systemctl poweroff, kod 0"           '[[ "$(calls)" == poweroff && $RC == 0 ]]'
check "bez menu rofi (brak klawiatury pod blokadą)" '[[ ! -e "$T/rofi.calls" ]]'
rm "$T/locked"

echo "== menu i potwierdzenie"
run "$POWEROFF"$'\n'"Yes"$'\n'
check "Power off + Yes → poweroff"                  '[[ "$(calls)" == poweroff ]]'
check "pierwsze menu: Power, dwie pozycje"          '[[ "$(head -n1 "$T/rofi.log")" == "Power => $POWEROFF|$REBOOT" ]]'
check "drugie menu: Are you sure?, Yes|No"          '[[ "$(sed -n 2p "$T/rofi.log")" == "Are you sure? => Yes|No" && "$(menus)" == 2 ]]'
check "motyw kompaktowy (2 linie, bez wyszukiwania)" 'grep -q "lines: 2" "$T/theme" && grep -q "children: \[ prompt \]" "$T/theme"'
run "$REBOOT"$'\n'"Yes"$'\n'
check "Reboot + Yes → reboot"                       '[[ "$(calls)" == reboot ]]'

echo "== nic się nie dzieje"
run "$POWEROFF"$'\n'"No"$'\n'
check "Power off + No → bez systemctl"              '[[ -z "$(calls)" && "$(menus)" == 2 ]]'
run $'\n'
check "Esc w pierwszym menu → bez potwierdzenia"    '[[ -z "$(calls)" && "$(menus)" == 1 ]]'
run "$REBOOT"$'\n\n'
check "Esc w potwierdzeniu → bez systemctl"         '[[ -z "$(calls)" ]]'
run "custom:Power off"$'\n'"Yes"$'\n'
check "wpisany tekst spoza listy + Yes → nic"       '[[ -z "$(calls)" ]]'
run "$POWEROFF"$'\n'"custom:yes"$'\n'
check "potwierdzenie tylko wierszem Yes z listy"    '[[ -z "$(calls)" && "$(windows)" == 1 ]]'

echo "== jedno okno na oba kroki (szybkie wejście nie przepada)"
# Obie odpowiedzi leżą w kolejce, zanim menu cokolwiek pokaże — jak dwa szybkie
# Entery. Dawny błąd: drugi krok dostawał własny proces rofi, a wejście wysłane
# między zamknięciem pierwszego okna i pojawieniem się drugiego przepadało.
run "$POWEROFF"$'\n'"Yes"$'\n'
check "oba kroki w jednym procesie rofi → poweroff" '[[ "$(windows)" == 1 && "$(menus)" == 2 && "$(calls)" == poweroff ]]'
check "tryb skryptowy pod nazwą pliku, bez -dmenu"  'grep -qF -- "-show archenemy-power -modes archenemy-power:rofi_power_menu.sh" "$T/rofi.calls" && ! grep -qF -- "-dmenu" "$T/rofi.calls"'
check "kod 0, nic na stderr"                        '[[ $RC == 0 && -z "$ERR" ]]'
# rofi dzieli listę trybów na „,” i „#”, a polecenie trybu na słowa.
D="$T/dir with space, comma #hash"
mkdir -p "$D" && cp "$PM" "$D/"
run "$REBOOT"$'\n'"Yes"$'\n' "$D/rofi_power_menu.sh"
check "ścieżka ze spacją, przecinkiem i # → reboot" '[[ "$(calls)" == reboot && "$(windows)" == 1 ]]'

echo "== Enter zatwierdza przy puszczeniu klawisza"
# Odpowiedzi atrapy: key:<klawisz> = wciśnięty i puszczony, hold:<klawisz> =
# trzymany dłużej niż opóźnienie powtarzania. Wiązanie z „!” czeka na
# puszczenie, więc powtarzanie niczego nie zatwierdza; bez „!” trzymany klawisz
# zatwierdza każdą kolejną listę (tests/lib/mock_rofi.py, nagłówek).
run "key:Return"$'\n'"key:Return"$'\n'
check "skrypt podaje -kb-accept-entry !Return,!KP_Enter" 'grep -qF -- "-kb-accept-entry !Return,!KP_Enter" "$T/rofi.calls"'
check "szybkie Enter-Enter → poweroff w jednym oknie" '[[ "$(calls)" == poweroff && "$(windows)" == 1 && "$(menus)" == 2 ]]'
run "key:KP_Enter"$'\n'"key:KP_Enter"$'\n'
check "Enter klawiatury numerycznej tak samo"       '[[ "$(calls)" == poweroff ]]'
run "hold:Return"$'\n'
check "przytrzymany Enter: pytanie pokazane, bez systemctl" '[[ -z "$(calls)" && "$(sed -n 2p "$T/rofi.log")" == "Are you sure? => Yes|No" && "$(menus)" == 2 ]]'
run "hold:Return"$'\n'"key:Return"$'\n'
check "po puszczeniu dopiero nowy Enter potwierdza"  '[[ "$(calls)" == poweroff && "$(menus)" == 2 ]]'
# Opcja zastępuje całą domyślną listę rofi, więc Ctrl+j i Ctrl+m odpadają.
run "key:Control+j"$'\n'"key:Control+m"$'\n'
check "Ctrl+j i Ctrl+m nie zatwierdzają w tym menu"  '[[ -z "$(calls)" ]] && ! grep -q "Are you sure" "$T/rofi.log"'
# Kontrola atrapy: ten sam skrypt bez opcji (domyślne wiązania rofi, Enter na
# wciśnięciu) — przytrzymany Enter przechodzi przez pytanie. Bez tej różnicy
# sprawdzenia wyżej nie zauważyłyby usunięcia opcji.
mkdir -p "$T/press" && cp "$PM" "$T/press/" &&
    sed -i 's/ -kb-accept-entry "\$ACCEPT_KEYS"//' "$T/press/rofi_power_menu.sh"
run "hold:Return"$'\n' "$T/press/rofi_power_menu.sh"
check "bez opcji przytrzymany Enter wyłącza (atrapa rozróżnia)" '! cmp -s "$PM" "$T/press/rofi_power_menu.sh" && [[ "$(calls)" == poweroff ]] && ! grep -qF -- "-kb-accept-entry" "$T/rofi.calls"'

echo "== wiersze niosą swoją akcję (pole info)"
run "$POWEROFF"$'\n'"No"$'\n'
check "krok 1: ask:poweroff, ask:reboot"            '[[ "$(head -n1 "$T/rofi.info")" == "$POWEROFF=ask:poweroff|$REBOOT=ask:reboot" ]]'
check "krok 2 po Power off: Yes=do:poweroff"        '[[ "$(sed -n 2p "$T/rofi.info")" == "Yes=do:poweroff|No=cancel" && -z "$(calls)" ]]'
run "$REBOOT"$'\n'"No"$'\n'
check "krok 2 po Reboot: Yes=do:reboot"             '[[ "$(sed -n 2p "$T/rofi.info")" == "Yes=do:reboot|No=cancel" && -z "$(calls)" ]]'

echo "== wywołanie zwrotne, tak jak woła je rofi"
# cb <ROFI_RETV> <ROFI_INFO albo - (brak)> [tekst wiersza]; wyjście w $T/cb.out.
# stderr znów przez $(…): bieg czeka na ewentualną akcję w tle.
cb() {
    local retv="$1" info="$2"; shift 2
    rm -f "$T/systemctl.log" "$T/cb.out"
    if [[ "$info" == - ]]; then
        ERR="$(ROFI_RETV="$retv" test_timeout 20 bash "$PM" "$@" 2>&1 >"$T/cb.out" </dev/null)"; RC=$?
    else
        ERR="$(ROFI_RETV="$retv" ROFI_INFO="$info" test_timeout 20 bash "$PM" "$@" 2>&1 >"$T/cb.out" </dev/null)"; RC=$?
    fi
}
# NUL → @, separator pól \x1f → ^ (format linii z rofi-script(5)).
wire() { tr '\0\037' '@^' < "$T/cb.out"; }
NL=$'\n'
WANT_START="@prompt^Power${NL}@no-custom^true${NL}${POWEROFF}@info^ask:poweroff${NL}${REBOOT}@info^ask:reboot"
WANT_ASK="@prompt^Are you sure?${NL}@no-custom^true${NL}Yes@info^do:poweroff${NL}No@info^cancel"
cb 0 -
check "start: prompt, no-custom, dwa wiersze z info" '[[ "$(wire)" == "$WANT_START" && -z "$(calls)" ]]'
cb 1 ask:poweroff "$POWEROFF"
check "Power off: pytanie w tym samym oknie, bez akcji" '[[ "$(wire)" == "$WANT_ASK" && -z "$(calls)" ]]'
cb 1 do:poweroff "Yes"
check "Yes + do:poweroff → poweroff, pusta lista"   '[[ "$(calls)" == poweroff && ! -s "$T/cb.out" && $RC == 0 ]]'
cb 1 do:reboot "Yes"
check "Yes + do:reboot → reboot, pusta lista"       '[[ "$(calls)" == reboot && ! -s "$T/cb.out" && $RC == 0 ]]'
# Podróbki: akcja wymaga zgodnej pary tekst + info z wybranego wiersza.
QUIET='[[ -z "$(calls)" && ! -s "$T/cb.out" && $RC == 0 ]]'
cb 1 - "Yes";                    check "Yes bez info → nic"                  "$QUIET"
cb 1 ask:poweroff "Yes";         check "Yes z info kroku 1 → nic"            "$QUIET"
cb 1 do:poweroff "No";           check "No z info do:poweroff → nic"         "$QUIET"
cb 1 do:poweroff "$POWEROFF";    check "Power off z info do:poweroff → nic"  "$QUIET"
cb 1 cancel "No";                check "No → nic, okno się zamyka"           "$QUIET"
cb 1 do:halt "Yes";              check "nieznana akcja w info → nic"         "$QUIET"
cb 2 do:poweroff "Yes";          check "tekst wpisany (ROFI_RETV=2) → nic"   "$QUIET"
cb 3 do:poweroff "Yes";          check "usunięcie wiersza (ROFI_RETV=3) → nic" "$QUIET"

echo "== akcja w tle nie trzyma okna menu"
# rofi czyta wyjście skryptu do końca. systemctl, który czeka (agent polkit),
# nie może przez to trzymać okna z wyłączną klawiaturą: bieg ma się skończyć,
# kiedy atrapa systemctl jeszcze trwa. Tu stderr idzie do pliku, żeby bieg
# NIE czekał na akcję.
rm -f "$T/systemctl.log" "$T/rofi.log" "$T/rofi.info" "$T/rofi.calls"
printf '%s\nYes\n' "$POWEROFF" > "$T/answers"
touch "$T/systemctl.hold"
test_timeout 20 bash "$PM" </dev/null >/dev/null 2>"$T/hold.err"; RC=$?
check "menu kończy się, gdy systemctl jeszcze trwa" '[[ $RC == 0 && -e "$T/systemctl.hold" ]]'
test_wait_file 10 "$T/systemctl.log"; W=$?
check "akcja mimo to wystartowała"                  '[[ $W == 0 && "$(calls)" == poweroff ]]'
rm -f "$T/systemctl.hold"

echo "== wiązanie w rice'ach"
# Poprawka siedzi we wspólnym skrypcie; każdy rice z tym bindem ma go wołać.
n=0; bad=""
for f in "$REPO"/rices/*/hypr/hyprland.lua; do
    grep -qF 'Shift_R"' "$f" || continue        # white-blue_beta nie ma tego bindu
    n=$((n + 1))
    line="$(grep -F 'local power_menu' "$f")"
    if [[ "$line" != *'= "~/archenemy/scripts/rofi/rofi_power_menu.sh"' ]] ||
       ! grep -qF 'hl.bind(mainMod .. " + SHIFT + Shift_R", hl.dsp.exec_cmd(power_menu), { release = true, locked = true })' "$f"; then
        bad+=" ${f#"$REPO"/}"
    fi
done
check "$n rice'ów: Super+prawy Shift woła wspólny skrypt" '[[ $n -ge 7 && -z "$bad" ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
test_timing_ok && ((FAIL == 0))
