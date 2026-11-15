#!/bin/bash
# =============================================
#   archenemy - tests/install-summary.sh
#   Czy install.sh mówi prawdę o tym, co zrobił: kroki opcjonalne, które się
#   nie udały, trafiają do podsumowania [11], a baner nie ogłasza pełnego
#   sukcesu. Wycinki kroków są wycinane z install/install.sh sedem po
#   nagłówkach (jak [9] w tests/install-link.sh) i uruchamiane na atrapach
#   sudo/pacman/yay w mktemp. Bez roota, bez sieci.
#   Powód powstania (audyt 2026-11-05, Z3): jedna zła pozycja w dodatkach
#   anulowała całą transakcję pacmana, a podsumowanie milczało.
#   Uruchom: bash tests/install-summary.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval (zmienne żyją w eval)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$REPO/install/install.sh"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# cut_step <wzorzec początku> <wzorzec końca|EOF> <plik> — wycinek [początek, koniec)
cut_step() {
    local s e
    s=$(grep -n -m1 -- "$1" "$INST" | cut -d: -f1)
    if [[ "$2" == EOF ]]; then e=$(( $(wc -l < "$INST") + 1 ))
    else e=$(grep -n -m1 -- "$2" "$INST" | cut -d: -f1); fi
    [[ -n "$s" && -n "$e" && "$e" -gt "$s" ]] || return 1
    sed -n "${s},$((e-1))p" "$INST" > "$3"
}

# run_step <wycinek> <stdin> [kod przed wycinkiem] → stdout+stderr; SUMMARY_*
# do $T/summary. Kolory puste, ARCHENEMY_DIR = atrapa repo; install/lib/aur.sh
# jak w install.sh.
run_step() {
    ARCHENEMY_DIR="$A" GREEN='' NC='' YELLOW='' RED='' CYAN='' BLUE='' \
    bash -c 'declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=(); source "$3"; eval "$4"; source "$1"
             printf "DONE=%s\n" "${SUMMARY_DONE[@]}" > "$2"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}" >> "$2"' \
        _ "$1" "$T/summary" "$REPO/install/lib/aur.sh" "${3:-}" <<<"$2" 2>&1
}

# ─── atrapy ──────────────────────────────────────────────────────────────────
mkdir -p "$T/bin"
cat > "$T/bin/sudo" <<'EOF'
#!/bin/bash
[[ "$1" == -k ]] && exit 0
exec "$@"
EOF
# pacman: -Qi <pkg> = zainstalowany, jeśli jest w MOCK_INSTALLED; -S logowane,
# nieznana nazwa (MOCK_PACMAN_UNKNOWN) anuluje całą transakcję jak prawdziwy.
cat > "$T/bin/pacman" <<'EOF'
#!/bin/bash
echo "pacman $*" >> "$MOCK_LOG"
if [[ "$1" == "-Qi" ]]; then
    [[ " ${MOCK_INSTALLED:-} " == *" $2 "* ]]; exit
fi
for a in "$@"; do
    [[ -n "${MOCK_PACMAN_UNKNOWN:-}" && "$a" == "$MOCK_PACMAN_UNKNOWN" ]] && { echo "error: target not found: $a" >&2; exit 1; }
done
exit 0
EOF
cat > "$T/bin/yay" <<'EOF'
#!/bin/bash
echo "yay $*" >> "$MOCK_LOG"
[[ "${MOCK_YAY_FAIL:-0}" == 1 ]] && exit 1
exit 0
EOF
chmod +x "$T/bin"/*
export PATH="$T/bin:$PATH"
export MOCK_LOG="$T/log"

A="$T/archenemy"
mkdir -p "$A/packages" "$A/install"
printf 'btop\nkeepassxc\nbadname\n' > "$A/packages/additional-packages-pacman.txt"
printf 'megasync\n' > "$A/packages/additional-packages-aur.txt"

# ─── [5] dodatki: wynik pacmana i yay w podsumowaniu (Z3) ────────────────────
echo "== [5] dodatkowe pakiety"
cut_step '^read -rp "Would you like to install additional useful packages' '^# ─── 6\. DEVICE DETECTION' "$T/step5.sh"
check "wycinek [5] (dodatki) znaleziony"         '[[ -s "$T/step5.sh" ]]'

: > "$MOCK_LOG"
out=$(MOCK_PACMAN_UNKNOWN=badname run_step "$T/step5.sh" $'y\n1 3\n')
check "zła nazwa: pacman wołany"                 'grep -q "pacman -S --needed btop badname" "$MOCK_LOG"'
check "zła nazwa: jawny błąd na ekranie"         '[[ "$out" == *"✗"*"btop"* ]]'
check "zła nazwa: porażka w podsumowaniu"        'grep -q "^SKIPPED=.*btop.*badname" "$T/summary"'

out=$(MOCK_PACMAN_UNKNOWN=badname MOCK_INSTALLED="btop" run_step "$T/step5.sh" $'y\n1 3\n')
check "w podsumowaniu tylko to, czego nie ma"    'grep -q "^SKIPPED=.*badname" "$T/summary" && ! grep -q "^SKIPPED=.*btop" "$T/summary"'

out=$(run_step "$T/step5.sh" $'y\n1 2\n')
check "udana instalacja: podsumowanie czyste"    '! grep -q "^SKIPPED=." "$T/summary" && [[ "$out" != *"✗"* ]]'

out=$(MOCK_YAY_FAIL=1 run_step "$T/step5.sh" $'y\n4\nn\n')
check "AUR: porażka yay w podsumowaniu"          'grep -q "^SKIPPED=.*megasync" "$T/summary"'

out=$(run_step "$T/step5.sh" $'y\n4\nn\n')
check "AUR: udany yay — podsumowanie czyste"     '! grep -q "^SKIPPED=." "$T/summary"'

# Bez yay: PATH tylko z atrapami i bashem (yay bywa w /usr/bin maszyny testowej).
mkdir -p "$T/bin-noyay"
for b in sudo pacman; do ln -sf "$T/bin/$b" "$T/bin-noyay/$b"; done
ln -sf "$(command -v bash)" "$T/bin-noyay/bash"
out=$(PATH="$T/bin-noyay" run_step "$T/step5.sh" $'y\n4\n')
check "AUR bez yay: pominięcie w podsumowaniu"   'grep -q "^SKIPPED=.*megasync" "$T/summary"'

# Audyt 2026-11-05, Z12: „08” w $((n - 1)) to zła liczba ósemkowa — błąd
# rozwinięcia kończył cały instalator, wybór dodatków przepadał.
cp "$A/packages/additional-packages-pacman.txt" "$T/add-pacman.bak"
printf 'btop\nkeepassxc\nbadname\np4\np5\np6\np7\np8\n' > "$A/packages/additional-packages-pacman.txt"
: > "$MOCK_LOG"
out=$(run_step "$T/step5.sh" $'y\n08 02\n'); rc=$?
check "liczba z zerem (08): wybór dociera do pacmana" '[[ $rc -eq 0 ]] && grep -q "pacman -S --needed p8 keepassxc$" "$MOCK_LOG"'
cp "$T/add-pacman.bak" "$A/packages/additional-packages-pacman.txt"

# ─── [6.5] sterowniki i jądro: kody wyjścia instalatorów (Z8) ────────────────
echo "== [6.5] sterowniki i jądro"
cut_step '^# ─── 6\.5 DRIVERS' '^# ─── 7\. BACKUP' "$T/step65.sh"
check "wycinek [6.5] znaleziony"                 '[[ -s "$T/step65.sh" ]]'
# Atrapy instalatorów: kod wyjścia z MOCK_<CPUDRIVERS|GPUDRIVERS|KERNEL>_RC.
for n in cpudrivers-installation gpudrivers-installation kernel-install; do
    v="MOCK_$(tr 'a-z-' 'A-Z_' <<< "${n%%-*}")_RC"
    printf '#!/bin/bash\necho "RUN %s" >> "$MOCK_LOG"\nexit "${%s:-0}"\n' "$n" "$v" > "$A/install/$n.sh"
done
: > "$MOCK_LOG"
out=$(run_step "$T/step65.sh" $'y\ny\ny\n')
check "wszystkie kody 0: podsumowanie czyste"    '[[ $(grep -c "^RUN" "$MOCK_LOG") -eq 3 ]] && ! grep -q "^SKIPPED=." "$T/summary"'
out=$(MOCK_CPUDRIVERS_RC=1 MOCK_GPUDRIVERS_RC=1 MOCK_KERNEL_RC=1 run_step "$T/step65.sh" $'y\ny\ny\n')
check "mikrokod: porażka w podsumowaniu"         'grep -q "^SKIPPED=CPU microcode.*FAILED.*cpudrivers-installation.sh" "$T/summary"'
check "GPU: porażka w podsumowaniu"              'grep -q "^SKIPPED=GPU drivers.*FAILED.*gpudrivers-installation.sh" "$T/summary"'
check "jądro: porażka w podsumowaniu"            'grep -q "^SKIPPED=Kernel.*FAILED.*kernel-install.sh" "$T/summary"'
out=$(MOCK_CPUDRIVERS_RC=2 MOCK_KERNEL_RC=2 run_step "$T/step65.sh" $'y\nn\ny\n')
check "kod 2: wpisy bootowania do ręcznej poprawy" '[[ $(grep -c "^SKIPPED=.*boot entries" "$T/summary") -eq 2 ]] && ! grep -q "^SKIPPED=.*FAILED" "$T/summary"'
: > "$MOCK_LOG"
out=$(MOCK_CPUDRIVERS_RC=1 run_step "$T/step65.sh" $'n\nn\nn\n')
check "odmowa: instalatory nie wołane"           '[[ ! -s "$MOCK_LOG" ]] && ! grep -q "^SKIPPED=." "$T/summary"'

# ─── [8l] mpd: ✓ dopiero, gdy ~/.config/mpd naprawdę wskazuje config/mpd (Z11) ─
echo "== [8l] link ~/.config/mpd"
cut_step '^# 8l\. Music stack' '^if command -v ncmpcpp' "$T/step8l.sh"
check "wycinek [8l] (mpd) znaleziony"            '[[ -s "$T/step8l.sh" ]]'
# Atrapy: mpd jest zainstalowany; systemctl — nic nie jest włączone.
printf '#!/bin/bash\nexit 0\n' > "$T/bin/mpd"
printf '#!/bin/bash\nexit 1\n' > "$T/bin/systemctl"
chmod +x "$T/bin/mpd" "$T/bin/systemctl"
mkdir -p "$A/config/mpd" "$HOME/.config"
MPD_PRE='CONFIG_DIR="$HOME/.config"; DATA_DIR="$ARCHENEMY_DIR/data"; seed_dat() { :; }'
MPD_LINK="$HOME/.config/mpd"
mpd_reset() { rm -rf "$MPD_LINK" "$MPD_LINK".bak-*; }
mpd_linked() { [[ -L "$MPD_LINK" && "$(readlink -f "$MPD_LINK")" == "$(readlink -f "$A/config/mpd")" ]]; }

mpd_reset
out=$(run_step "$T/step8l.sh" $'n\n' "$MPD_PRE")
check "brak configu: link do config/mpd, ✓ i DONE" 'mpd_linked && [[ "$out" == *"✓ ~/.config/mpd → config/mpd"* ]] && grep -q "^DONE=mpd config linked" "$T/summary"'

# Wiszący link (np. po przeniesieniu repo): -e go nie widzi, ln padał,
# a ✓ i SUMMARY_DONE i tak leciały (audyt 2026-11-05, Z11).
mpd_reset; ln -s "$T/nonexistent/mpd" "$MPD_LINK"
out=$(run_step "$T/step8l.sh" $'n\nn\n' "$MPD_PRE")
check "wiszący link, odmowa: link nietknięty, bez ✓" '[[ "$(readlink "$MPD_LINK")" == "$T/nonexistent/mpd" && "$out" != *"✓ ~/.config/mpd"* ]] && ! grep -q "^DONE=mpd config linked" "$T/summary"'
check "wiszący link, odmowa: pytanie i wpis w SKIPPED" '[[ "$out" == *"broken link"* ]] && grep -q "^SKIPPED=mpd: existing user config kept" "$T/summary"'
mpd_reset; ln -s "$T/nonexistent/mpd" "$MPD_LINK"
out=$(run_step "$T/step8l.sh" $'y\nn\n' "$MPD_PRE")
check "wiszący link, y: link podmieniony, stary jako .bak" 'mpd_linked && compgen -G "$MPD_LINK.bak-*" >/dev/null && [[ "$(readlink "$MPD_LINK".bak-*)" == "$T/nonexistent/mpd" ]] && grep -q "^DONE=mpd config linked" "$T/summary"'

# ln, który pada (np. pełny dysk): ✗ i SKIPPED zamiast ✓.
mkdir -p "$T/bin-noln"
printf '#!/bin/bash\necho "ln: failed" >&2\nexit 1\n' > "$T/bin-noln/ln"
chmod +x "$T/bin-noln/ln"
mpd_reset
out=$(PATH="$T/bin-noln:$PATH" run_step "$T/step8l.sh" $'n\n' "$MPD_PRE")
check "nieudany ln: ✗, SKIPPED, bez DONE"        '[[ "$out" == *"✗"*"mpd"* && "$out" != *"✓ ~/.config/mpd"* ]] && grep -q "^SKIPPED=mpd config NOT linked" "$T/summary" && ! grep -q "^DONE=mpd config linked" "$T/summary"'
mpd_reset; mkdir -p "$MPD_LINK"
out=$(PATH="$T/bin-noln:$PATH" run_step "$T/step8l.sh" $'y\nn\n' "$MPD_PRE")
check "y, nieudany ln: ✗, SKIPPED, bez DONE"     '[[ "$out" == *"✗"*"mpd"* ]] && grep -q "^SKIPPED=mpd config NOT linked" "$T/summary" && ! grep -q "^DONE=mpd config linked" "$T/summary"'
# mv, który pada (np. katalog bez prawa zapisu): prawdziwy ~/.config/mpd zostaje
# na miejscu, a `ln -sT` odmawia — zwykłe `ln -s` utworzyłoby link W ŚRODKU
# niego (~/.config/mpd/mpd), czyli obcy plik w configu użytkownika (przegląd P-3).
mkdir -p "$T/bin-nomv"
printf '#!/bin/bash\necho "mv: cannot move: Permission denied" >&2\nexit 1\n' > "$T/bin-nomv/mv"
chmod +x "$T/bin-nomv/mv"
mpd_reset; mkdir -p "$MPD_LINK"
out=$(PATH="$T/bin-nomv:$PATH" run_step "$T/step8l.sh" $'y\nn\n' "$MPD_PRE")
check "y, nieudany mv: ✗, SKIPPED, bez DONE"     '[[ "$out" == *"✗"*"mpd"* ]] && grep -q "^SKIPPED=mpd config NOT linked" "$T/summary" && ! grep -q "^DONE=mpd config linked" "$T/summary"'
check "y, nieudany mv: katalog nietknięty, bez linku w środku" '[[ -d "$MPD_LINK" && ! -L "$MPD_LINK" && ! -e "$MPD_LINK/mpd" && ! -L "$MPD_LINK/mpd" ]]'
mpd_reset

# ─── [9.5] tapeta: ✓ dopiero, gdy hyprpaper ją pokazał (Z10) ────────────────
echo "== [9.5] tapeta startowa"
cut_step '^# ─── 9\.5 SCRIPTS' '^# ─── 9\.6 FLUX-WALL' "$T/step95.sh"
check "wycinek [9.5] znaleziony"                 '[[ -s "$T/step95.sh" ]]'
# Atrapa przełącznika: wypisuje MOCK_WP_RESULT (wiersze jak z prawdziwego,
# łącznie z obcym wyjściem, np. logiem hyprpapera startowanego w tle).
mkdir -p "$A/scripts/rofi" "$A/scripts/lib" "$A/wallpapers"
: > "$A/wallpapers/a.png"
cp "$REPO/scripts/lib/runtime-dir.sh" "$A/scripts/lib/"   # katalog sesji z logiem hyprpapera (S12)
printf '#!/bin/bash\nprintf "%%s\\n" "$MOCK_WP_RESULT"\n' > "$A/scripts/rofi/rofi_wallpaper_switcher.sh"
out=$(MOCK_WP_RESULT=initial run_step "$T/step95.sh" '')
check "initial: ✓ i wpis w DONE"                 '[[ "$out" == *"✓ Initial wallpaper applied"* ]] && grep -q "^DONE=Initial wallpaper" "$T/summary" && ! grep -q "^SKIPPED=." "$T/summary"'
out=$(MOCK_WP_RESULT=initial-failed run_step "$T/step95.sh" '')
check "initial-failed: bez ✓, ⚠ w podsumowaniu"  '[[ "$out" != *"✓ Initial wallpaper"* && "$out" == *"⚠"*"hyprpaper"* ]] && grep -q "^SKIPPED=wallpaper.*hyprpaper" "$T/summary"'
out=$(MOCK_WP_RESULT=restored-failed run_step "$T/step95.sh" '')
check "restored-failed: bez ✓, ⚠ w podsumowaniu" '[[ "$out" != *"✓ Wallpaper kept"* ]] && grep -q "^SKIPPED=wallpaper.*hyprpaper" "$T/summary"'
# Log wskazany tam, gdzie pisze go przełącznik: prywatny katalog sesji
# (lib/runtime-dir.sh, S12; tu XDG_RUNTIME_DIR 0700 z test_environment_init).
check "porażka: log z prywatnego katalogu sesji"   '[[ "$out" == *"Log: $XDG_RUNTIME_DIR/archenemy-hyprpaper-err.log"* && "$out" != *"No such file"* && "$out" != *"not found"* ]] && grep -qF "(log: $XDG_RUNTIME_DIR/archenemy-hyprpaper-err.log)" "$T/summary"'
mkdir -p "$T/tmp-planted" "$T/evil"; ln -s "$T/evil" "$T/tmp-planted/archenemy-$UID"
out=$(XDG_RUNTIME_DIR="" ARCHENEMY_RUNTIME_SYSTEM="$T/none" TMPDIR="$T/tmp-planted" MOCK_WP_RESULT=initial-failed run_step "$T/step95.sh" '')
check "porażka bez prywatnego katalogu: bez ścieżki w /tmp, nic nie zakłada" '[[ "$out" == *"Log: none, no private runtime directory"* && "$out" != *"/tmp/archenemy-hyprpaper-err.log"* && -z "$(ls -A "$T/evil")" ]]'
out=$(MOCK_WP_RESULT=$'[LOG] hyprpaper starting\ninitial' run_step "$T/step95.sh" '')
check "obcy wiersz przed wynikiem nie myli kroku" '[[ "$out" == *"✓ Initial wallpaper applied"* ]]'
out=$(MOCK_WP_RESULT=none run_step "$T/step95.sh" '')
check "none: brak tapet w wallpapers/"           'grep -q "^SKIPPED=initial wallpaper (none in wallpapers/)" "$T/summary"'
out=$(MOCK_WP_RESULT='' run_step "$T/step95.sh" '')
check "brak wyniku: bez ✓ i bez none in wallpapers" '[[ "$out" != *"✓ Initial wallpaper"* && "$out" != *"✓ Wallpaper kept"* ]] && grep -q "^SKIPPED=wallpaper" "$T/summary" && ! grep -q "none in wallpapers" "$T/summary"'

# ─── [11] baner zależny od pominięć (Z8) ─────────────────────────────────────
echo "== [11] podsumowanie i baner"
cut_step '^# ─── 11\. DONE' EOF "$T/step11.sh"
check "wycinek [11] znaleziony"                  '[[ -s "$T/step11.sh" ]]'
box_even() {   # każda linia ramki banera ma tę samą szerokość (w znakach)
    local w="" l
    while IFS= read -r l; do
        [[ "$l" == "  "[┌│└]* ]] || continue
        [[ -z "$w" ]] && w=${#l}
        [[ ${#l} -eq $w ]] || return 1
    done <<< "$1"
    [[ -n "$w" ]]
}
out=$(run_step "$T/step11.sh" $'n\n' 'SUMMARY_DONE=("a")')
check "bez pominięć: pełny sukces"               '[[ "$out" == *"Everything is set up. Have fun!"* ]]'
check "bez pominięć: ramka równa"                'box_even "$out"'
out=$(run_step "$T/step11.sh" $'n\n' 'SUMMARY_SKIPPED=("GPU drivers — installation FAILED")')
check "z pominięciem: bez pełnego sukcesu"       '[[ "$out" != *"Everything is set up"* ]]'
check "z pominięciem: baner podaje liczbę"       '[[ "$out" == *"1 item(s)"* ]]'
check "z pominięciem: ramka równa"               'box_even "$out"'
out=$(run_step "$T/step11.sh" $'n\n' 'for i in $(seq 12); do SUMMARY_SKIPPED+=("x$i"); done')
check "12 pominięć: liczba i równa ramka"        '[[ "$out" == *"12 item(s)"* ]] && box_even "$out"'

# Z9: pasek, tapeta i powiadomienia startują w hl.on("hyprland.start") —
# reload ich nie uruchamia, więc po pierwszej instalacji trzeba się przelogować.
# read -p bez TTY nie drukuje promptu, więc kolejność sprawdzamy w źródle wycinka.
relogin_before_reload() {
    local note ask
    note=$(grep -n -m1 'After the first install, log out and back in' "$T/step11.sh" | cut -d: -f1)
    ask=$(grep -n -m1 'read -rp "Reload Hyprland now' "$T/step11.sh" | cut -d: -f1)
    [[ -n "$note" && -n "$ask" && "$note" -lt "$ask" ]]
}
out=$(run_step "$T/step11.sh" $'n\n')
check "informacja o ponownym logowaniu na ekranie" '[[ "$out" == *"After the first install, log out and back in"* && "$out" == *"reload does not start"* ]]'
check "informacja przed pytaniem o reload"       'relogin_before_reload'
check "rice uruchamia pasek przy starcie sesji (podstawa komunikatu)" 'grep -q "hl.on(\"hyprland.start\"" "$REPO/rices/white-blue/hypr/hyprland.lua" && grep -q "exec_cmd(\"waybar\")" "$REPO/rices/white-blue/hypr/hyprland.lua"'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
