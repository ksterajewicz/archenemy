#!/bin/bash
# =============================================
#   archenemy - tests/rofi-drun.sh
#   Bramka launchera scripts/rofi/rofi_drun.sh: wpisany tekst bez wpisu
#   .desktop nie uruchamia się i nie daje błędu, aplikacje działają dalej.
#   Atrapy katalogów XDG i atrapa rofi, bez roota, zapis tylko w mktemp.
#   Uruchom: bash tests/rofi-drun.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
GATE="$REPO/scripts/rofi/rofi_drun.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

mkdir -p "$T/bin" "$T/share/applications/wine" "$T/home/.local/share/applications"
export HOME="$T/home" XDG_DATA_DIRS="$T/share" PATH="$T/bin:$PATH"
unset XDG_DATA_HOME

# Atrapy binarek zapisują, że się uruchomiły, razem z argumentami.
for b in app-a app-b app-c app-d forbidden; do
    printf '#!/bin/bash\necho "%s $*" >> "$RAN"\n' "$b" > "$T/bin/$b"
    chmod +x "$T/bin/$b"
done
export RAN="$T/ran.log"

printf '[Desktop Entry]\nExec=app-a %%U\n' > "$T/share/applications/a.desktop"
printf '[Desktop Entry]\nExec=app-b --flag\n' > "$T/share/applications/wine/b.desktop"
printf '[Desktop Entry]\nExec="%s/bin/app-c" %%f\n' "$T" > "$T/share/applications/c.desktop"
printf '[Desktop Entry]\nExec=app-d\n' > "$T/home/.local/share/applications/d.desktop"
printf '[Desktop Entry]\nTryExec=forbidden\nExec=other\n' > "$T/share/applications/e.desktop"

ran() { : > "$RAN"; "$GATE" --exec "$@"; RC=$?; }

echo "== bramka --exec"
ran app-a
[[ $RC -eq 0 && "$(<"$RAN")" == "app-a " ]] && ok "wpis .desktop uruchamia aplikację" || fail "app-a: rc=$RC, $(<"$RAN")"
ran app-b --flag
[[ "$(<"$RAN")" == "app-b --flag" ]] && ok "podkatalog applications/ i argumenty" || fail "app-b: $(<"$RAN")"
ran "$T/bin/app-c" plik
[[ "$(<"$RAN")" == "app-c plik" ]] && ok "Exec w cudzysłowie" || fail "app-c: $(<"$RAN")"
ran app-d
[[ "$(<"$RAN")" == "app-d " ]] && ok "wpis z ~/.local/share/applications" || fail "app-d: $(<"$RAN")"

ran siga
[[ $RC -eq 0 && ! -s "$RAN" ]] && ok "brak aplikacji → cisza, kod 0 (bez okna błędu)" || fail "siga: rc=$RC"
ran forbidden
[[ $RC -eq 0 && ! -s "$RAN" ]] && ok "istniejąca binarka bez Exec= się nie uruchamia" || fail "forbidden: rc=$RC, $(<"$RAN")"
ran app
[[ ! -s "$RAN" ]] && ok "prefiks nazwy to nie trafienie" || fail "prefiks: $(<"$RAN")"

: > "$RAN"; "$GATE" --exec; RC=$?
[[ $RC -eq 0 && ! -s "$RAN" ]] && ok "puste wywołanie → cisza" || fail "puste: rc=$RC"

XDG_DATA_DIRS="$T/nic" HOME="$T/nic" ran app-a
[[ "$(<"$RAN")" == "app-a " ]] && ok "brak jakichkolwiek wpisów → launcher nie odcięty" || fail "bez wpisów: $(<"$RAN")"

echo "== start rofi"
printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "$RAN"\n' > "$T/bin/rofi"
chmod +x "$T/bin/rofi"
: > "$RAN"; "$GATE"
mapfile -t ARGS < "$RAN"
[[ "${ARGS[0]:-}" == -show && "${ARGS[1]:-}" == drun && "${ARGS[2]:-}" == -run-command ]] && ok "rofi -show drun z run-command" || fail "argumenty: ${ARGS[*]:-}"
[[ "${ARGS[3]:-}" == "'$GATE' --exec {cmd}" ]] && ok "szablon: ścieżka w cudzysłowie, bez ~" || fail "szablon: ${ARGS[3]:-}"

echo "== drogi do launchera"
if grep -rn --include='hyprland.lua' --include='config.jsonc' 'rofi -show' "$REPO/rices" >/dev/null; then
    fail "rice woła rofi -show obok rofi_drun.sh"
else
    ok "rice'y i waybar idą przez rofi_drun.sh"
fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
