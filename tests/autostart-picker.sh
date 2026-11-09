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
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

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

echo "== generator"
printf 'dobra.app\nzła"nazwa\n' > "$DAT"
source "$REPO/scripts/hypr/lib/gen-autostart.sh"
generate_autostart_apps "$DAT" "$LUA"
check "znak psujący Lua pominięty"        'grep -q "dobra.app" "$LUA" && ! grep -q "nazwa" "$LUA"'
check "plik bez resztek tymczasowych"     '[[ -z "$(ls "$A/config/hypr" | grep -v "^autostart-apps.lua$")" ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
