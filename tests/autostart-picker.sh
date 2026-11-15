#!/bin/bash
# =============================================
#   archenemy - tests/autostart-picker.sh
#   Wybór autostartu Super+A → [p] na fałszywych katalogach XDG. Bez Hyprlanda,
#   zapis tylko w mktemp.
#
#   Powód powstania (audyt TUI 2026-11-05, U1–U5): lista bez stron, `q` gubiło
#   zmiany, usunięta aplikacja zostawała zaznaczona, a katalogi różniły się od rofi.
#   Uruchom: bash tests/autostart-picker.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

H="$T/home"; A="$H/archenemy"; DAT="$A/data/autostart-apps.dat"; LUA="$A/config/hypr/autostart-apps.lua"
SYS="$T/sys/applications"; LOC="$H/.local/share/applications"
mkdir -p "$A/data" "$A/config/hypr" "$A/scripts/hypr/lib" "$SYS/wine" "$LOC" "$T/bin" "$T/flat/applications"
cp "$REPO/scripts/hypr/lib/gen-autostart.sh" "$A/scripts/hypr/lib/"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/clear"; printf '#!/bin/bash\nexit 0\n' > "$T/bin/gtk-launch"; chmod +x "$T/bin/"*
export HOME="$H" PATH="$T/bin:$PATH" XDG_DATA_DIRS="$T/sys:$T/flat"
unset XDG_DATA_HOME

entry() { printf '[Desktop Entry]\nName=%s\nExec=x\n' "$2" > "$1"; }
for i in $(seq -w 1 40); do entry "$SYS/app$i.desktop" "App $i"; done
entry "$SYS/wine/game.desktop" "Wine Game"
entry "$T/flat/applications/org.flat.App.desktop" "Flat App"
entry "$SYS/over.desktop" "Over System"; entry "$LOC/over.desktop" "Over Local"
printf '[Desktop Entry]\nName=Hidden\nNoDisplay=true\n' > "$SYS/hidden.desktop"

pick() { printf "$1" | timeout 10 bash "$REPO/scripts/appbinds/autostart-picker.sh" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'; }

echo "== porażka generatora"
cat > "$T/bin/mktemp" <<'EOS'
#!/bin/bash
case "$*" in *autostart-apps.lua*) exit 1 ;; esac
exec /usr/bin/mktemp "$@"
EOS
chmod +x "$T/bin/mktemp"
out="$(pick "1\ns\n\n")"
check "brak pliku Lua → nie ma sukcesu"        '[[ "$out" != *"Saved"* && "$out" == *"Save failed"* ]]'
rm -f "$T/bin/mktemp" "$DAT" "$LUA"

echo "== katalogi jak w rofi"
out="$(pick 'q\n')"
check "podkatalog z ID ścieżkowym"        '[[ "$(pick "/Wine\nq\n")" == *"Wine Game"*"wine-game"* ]]'
check "XDG_DATA_DIRS (Flatpak)"           '[[ "$(pick "/Flat\nq\n")" == *"Flat App"* ]]'
out="$(pick '/Over\nq\n')"
check "katalog użytkownika nadpisuje"     '[[ "$out" == *"Over Local"* && "$out" != *"Over System"* ]]'
out="$(pick '/Hidden\nq\n')"
check "NoDisplay ukryte"                  '[[ "$out" == *"nothing matches"* ]]'

echo "== strony"
out="$(pick 'q\n')"
check "strona mieści się w oknie"         '[[ "$(grep -c "\[ \]" <<<"$out")" -le 15 && "$out" == *"page 1/"* ]]'
check "pierwsza strona bez końca listy"   '[[ "$out" != *"Wine Game"* || "$(grep -c "\[ \]" <<<"$out")" -le 15 ]]'
out="$(pick 'n\nq\n')"
check "n = następna strona"               '[[ "$out" == *"page 2/"* ]]'
out="$(pick 'n\np\nq\n')"
check "p = poprzednia strona"             '[[ "$(tail -12 <<<"$out")" == *"page 1/"* ]]'
out="$(pick 'p\nq\n')"
check "p na pierwszej stronie zostaje"    '[[ "$out" != *"page 0/"* ]]'
: > "$DAT"; out="$(pick '20\ns\n\n')"
check "numer z innej strony działa"       '[[ -s "$DAT" && "$(wc -l < "$DAT")" == 1 ]]'

echo "== zapis i wyjście"
: > "$DAT"; out="$(pick '1\ns\n\n')"
check "zapis mówi, kiedy zadziała"        '[[ "$out" == *"next login"* ]]'
check "gen-autostart emituje wpis"        'grep -q "gtk-launch" "$LUA"'
saved="$(<"$DAT")"
pick '2\nq\ny' >/dev/null
check "potwierdzone q nic nie zapisuje"   '[[ "$(<"$DAT")" == "$saved" ]]'
pick '2\nq\nns\n\n' >/dev/null
check "odmowa wraca do listy, zmiana żyje" '[[ "$(<"$DAT")" != "$saved" ]]'
out="$(pick 'q\n')"
check "q bez zmian nie pyta"              '[[ "$out" != *"Discard"* ]]'

echo "== nieaktualne wpisy"
printf 'gone-app\n' > "$DAT"
out="$(pick 'q\n')"
check "pokazane jako niezainstalowane"    '[[ "$out" == *"(not installed) gone-app"* ]]'
pick '1\ns\n\n' >/dev/null
check "dają się odznaczyć"                '[[ ! -s "$DAT" ]]'

echo "== strzałki i checkboxy"
: > "$DAT"; out="$(pick '\e[B\ns\n\n')"
check "strzałka przełącza drugi checkbox" 'grep -qx app02 "$DAT"'
saved="$(<"$DAT")"
pick 'j\n\e\ny' >/dev/null
check "Esc i potwierdzenie nie zapisują" '[[ "$(<"$DAT")" == "$saved" ]]'
: > "$DAT"; out="$(pick '\e[Fk\ns\n\n')"
check "strzałki wybierają zapis" '[[ "$out" == *"Saved 0 apps"* ]]'

echo "== ID ze spacją (np. skróty gier ze Steama)"
# Audyt 2026-11-05, Z7: generator pomijał ID spoza [A-Za-z0-9._+-], a picker
# i tak mówił „Saved N apps” — aplikacja wyglądała na zapisaną i nie startowała.
entry "$LOC/Space Game.desktop" "Space Game"
: > "$DAT"; out="$(pick '/Space\n1\ns\n\n')"
want_line="gtk-launch 'Space Game'"
check "ID ze spacją zapisany w .dat"      'grep -qx "Space Game" "$DAT"'
check "ID ze spacją trafia do autostartu" 'grep -qF "$want_line" "$LUA"'
check "Saved liczy wpisy z pliku Lua"     '[[ "$out" == *"Saved 1 apps"* ]]'
printf 'app01\nzły\tznak\n' > "$DAT"; out="$(pick 's\n\n')"
check "znak sterujący: zgłoszony, nie liczony" '[[ "$out" == *"Saved 1 apps"* && "$out" == *"Not saved"*"zły"* ]]'
rm -f "$LOC/Space Game.desktop"

echo "== generator"
printf '%s\n' dobra.app 'Space Game' 'zła"nazwa' "it's\\back" " padded.app "$'\r' $'zły\tznak' > "$DAT"
source "$REPO/scripts/hypr/lib/gen-autostart.sh"
generate_autostart_apps "$DAT" "$LUA"
skipped_expected=$'zły\tznak'
check "znak sterujący pominięty i zgłoszony" '[[ "${AUTOSTART_SKIPPED[*]-}" == "$skipped_expected" ]] && ! grep -q "znak" "$LUA"'
check "plik bez resztek tymczasowych"     '[[ -z "$(ls "$A/config/hypr" | grep -v "^autostart-apps.lua$")" ]]'
# Skutek, nie tekst: plik wykonuje Lua (atrapa hl), a każde polecenie idzie
# przez sh -c jak w Hyprlandzie; gtk-launch ma dostać ID jako JEDEN argument.
if command -v lua5.4 >/dev/null 2>&1; then
    mkdir -p "$T/launch"
    printf '#!/bin/bash\nprintf "%%s|%%s\\n" "$#" "$1" >> "%s"\n' "$T/launched" > "$T/launch/gtk-launch"
    chmod +x "$T/launch/gtk-launch"; : > "$T/launched"
    lua5.4 -e 'hl = { on = function(_, f) f() end, exec_cmd = function(c) io.write(c, "\0") end }' "$LUA" > "$T/cmds" 2>"$T/lua.err"
    while IFS= read -r -d '' c; do PATH="$T/launch:$PATH" sh -c "$c"; done < "$T/cmds"
    launched_expected="$(printf '1|%s\n' dobra.app 'Space Game' 'zła"nazwa' "it's\\back" padded.app)"
    check "każde ID dociera do gtk-launch jako jeden argument" '[[ ! -s "$T/lua.err" && "$(<"$T/launched")" == "$launched_expected" ]]'
else
    echo "  - pominięte: brak lua5.4 (wykonanie autostart-apps.lua)"
fi

# Rzeczywisty terminal: etykiety i wpisywane numery muszą wskazywać tę samą aplikację.
: > "$DAT"
if python - "$REPO/scripts/appbinds/autostart-picker.sh" "$DAT" <<'PYTEST'
import fcntl, os, pty, re, select, signal, struct, sys, termios, time
pid, master = pty.fork()
if pid == 0:
    os.execv('/bin/bash', ['bash', sys.argv[1]])
fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 110, 0, 0))
stage = 0
buffer = ''
all_output = ''
deadline = time.monotonic() + 8
while time.monotonic() < deadline:
    if not select.select([master], [], [], .1)[0]: continue
    try: chunk = os.read(master, 65536)
    except OSError: break
    if not chunk: break
    buffer += chunk.decode(errors='replace')
    all_output += chunk.decode(errors='replace')
    if 'Cancel [q/Esc]' not in buffer: continue
    clean = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', buffer)
    if stage == 0:
        os.write(master, b'n'); stage = 1; buffer = ''
    elif stage == 1 and '11) [ ] App 11' in clean:
        assert not re.search(r'\d+\) Next page', clean), clean
        os.write(master, b'11\n'); stage = 2; buffer = ''
    elif stage == 2 and '11) [x] App 11' in clean:
        os.write(master, b's\n'); stage = 3; buffer = ''
else:
    os.kill(pid, signal.SIGKILL)
os.close(master)
_, status = os.waitpid(pid, 0)
assert stage == 3 and os.waitstatus_to_exitcode(status) == 0, all_output
with open(sys.argv[2]) as file: assert file.read().strip() == 'app11'
PYTEST
then ok "TTY: globalny numer 11 na drugiej stronie zaznacza app11"
else fail "TTY: globalny numer 11 na drugiej stronie zaznacza app11"; fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
