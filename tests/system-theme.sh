#!/usr/bin/env bash
# =============================================
#   archenemy - tests/system-theme.sh
#   Motywy systemowe: ekran logowania SDDM i menu GRUB-a per rice.
#     A. src/system-theme/build.sh + grub/assets.py — składanie motywów;
#     B. src/system-theme/system-theme-sync.sh — skrypt roota: rice, logo,
#        monitor logowania i tapeta jako DANE NIEZAUFANE;
#     C. install/system-theme-installation.sh — instalacja opt-in, cudza
#        konfiguracja, --remove.
#   ATRAPY w PATH: sudo, systemctl, grub-mkconfig, grub-mkfont, fc-match,
#   sddm, bootctl — żadna nie dotyka systemu. Pliki systemowe żyją pod
#   ARCHENEMY_SYSROOT w mktemp (hak działa tylko z ARCHENEMY_TEST=1), /boot
#   pod ARCHENEMY_BOOT_DIR. Przed pierwszym biegiem test sprawdza, że sudo,
#   systemctl i grub-mkconfig to atrapy — inaczej odmawia.
#   Czego NIE obejmuje (tylko żywa maszyna): prawdziwy greeter SDDM i GRUB
#   (podgląd: src/system-theme/tools/), zrzucanie uprawnień przez setpriv
#   (wymaga prawdziwego roota), jednostka .path systemd.
#   Uruchom: bash tests/system-theme.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval (zmienne żyją w eval); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$REPO/src/system-theme/build.sh"
SYNC="$REPO/src/system-theme/system-theme-sync.sh"
INST="$REPO/install/system-theme-installation.sh"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── atrapy ───────────────────────────────────────────────────────────────────
mkdir -p "$T/bin" "$T/fonts"
cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >> "$MOCK_LOG"
exec "$@"
EOF
cat > "$T/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$MOCK_LOG"
[[ "$1" == is-active ]] && exit "${MOCK_ACTIVE_RC:-0}"
exit 0
EOF
# grub-mkconfig: przy kodzie 0 zapisuje grub.cfg tak jak prawdziwy — z linią
# motywu, gdy /etc/default/grub (atrapa) ustawia GRUB_THEME.
cat > "$T/bin/grub-mkconfig" <<'EOF'
#!/usr/bin/env bash
echo "grub-mkconfig $*" >> "$MOCK_LOG"
[[ "${MOCK_GRUB_RC:-0}" == 0 ]] || exit "$MOCK_GRUB_RC"
theme="$(grep -E '^GRUB_THEME=' "$ARCHENEMY_SYSROOT/etc/default/grub" | tail -n1 | cut -d= -f2- | tr -d '"')"
{ echo "# TEST grub.cfg"; [[ -n "$theme" ]] && echo "set theme=(\$root)$theme"; } > "$2"
exit 0
EOF
# grub-mkfont: plik .pf2 z opisem wywołania (nazwa, rozmiar, zakres).
cat > "$T/bin/grub-mkfont" <<'EOF'
#!/usr/bin/env bash
echo "grub-mkfont $*" >> "$MOCK_LOG"
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && out="$2"; shift; done
echo "PF2 TEST" > "$out"
EOF
cat > "$T/bin/fc-match" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *"JetBrainsMono Nerd Font Mono"*) printf 'JetBrainsMono Nerd Font Mono\t%s\n' "$MOCK_FONTS/text.ttf" ;;
    *"Symbols Nerd Font Mono"*)       printf 'Symbols Nerd Font Mono\t%s\n' "$MOCK_FONTS/symbols.ttf" ;;
    *) printf 'DejaVu Sans\t/nonexistent.ttf\n' ;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/sddm"
cat > "$T/bin/bootctl" <<'EOF'
#!/usr/bin/env bash
echo "bootctl $*" >> "$MOCK_LOG"
[[ "$1" == is-installed && "${MOCK_BOOTCTL:-0}" == 1 ]]
EOF
chmod +x "$T/bin"/*
: > "$T/fonts/text.ttf"; : > "$T/fonts/symbols.ttf"
mkdir -p "$T/nosddm"
for c in sudo systemctl grub-mkconfig grub-mkfont fc-match bootctl; do cp "$T/bin/$c" "$T/nosddm/$c"; done
REAL_PATH="$PATH"
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log" MOCK_FONTS="$T/fonts"
for c in sudo systemctl grub-mkconfig; do
    if [[ "$(command -v "$c")" != "$T/bin/$c" ]]; then
        echo "✗ $c nie jest atrapą ($(command -v "$c")) — nie uruchamiam (dotknąłby systemu)"
        exit 1
    fi
done
printf 'NAME="Arch Linux"\nID=arch\n' > "$T/os-release-arch"
printf 'NAME="Fedora Linux"\nID=fedora\n' > "$T/os-release-fedora"
S="$T/sys"
export ARCHENEMY_TEST=1 ARCHENEMY_SYSROOT="$S" ARCHENEMY_BOOT_DIR="$S/boot" ARCHENEMY_OS_RELEASE="$T/os-release-arch"
GLYPH="$(bash "$REPO/scripts/waybar/launcher-logo.sh" glyph)"
A="$HOME/archenemy"            # katalog stanu użytkownika (atrapa)
THEMES="$S/usr/share/sddm/themes"
DROPIN="$S/etc/sddm.conf.d/20-archenemy-theme.conf"
GDIR="$S/boot/grub/themes/archenemy"
GDEF="$S/etc/default/grub"

# PNG 1×1 i JPEG-podobny nagłówek — prawdziwe sygnatury, treść bez znaczenia.
printf '\x89PNG\r\n\x1a\nTESTPNG-ONE' > "$T/one.png"
printf '\x89PNG\r\n\x1a\nTESTPNG-TWO-LONGER' > "$T/two.png"
printf '\xff\xd8\xff\xe0TESTJPEG' > "$T/photo.jpg"
echo "this is not an image" > "$T/notes.txt"

echo "== A: build.sh — składanie motywów"
rices_sddm="$(bash "$BUILD" rices sddm)"; rices_grub="$(bash "$BUILD" rices grub)"
# Każdy rice z rices/ poza legacy white-blue_beta ma oba motywy (parytet rice'ów).
expected="$(find "$REPO/rices" -mindepth 1 -maxdepth 1 -type d ! -name white-blue_beta -printf '%f\n' | sort)"
check "każdy rice poza betą ma ekran logowania"    '[[ "$(sort <<< "$rices_sddm")" == "$expected" ]]'
check "każdy rice poza betą ma menu GRUB-a"        '[[ "$(sort <<< "$rices_grub")" == "$expected" ]]'
check "legacy white-blue_beta bez własnych motywów" '! grep -qx white-blue_beta <<< "$rices_sddm$rices_grub"'
complete=1
while IFS= read -r r; do
    bash "$BUILD" sddm "$r" "$T/b/sddm-$r" >/dev/null 2>&1 || complete=0
    for f in Main.qml theme.conf metadata.desktop components/Greeter.qml components/Seat.qml components/Backdrop.qml; do
        [[ -s "$T/b/sddm-$r/$f" ]] || complete=0
    done
    # Tapeta rice'a albo tło rysowane przez układ (rice bez stałej tapety w repo).
    if grep -q '^SDDM_WALLPAPER_169=' "$REPO/rices/$r/system-theme.conf"; then
        [[ -s "$T/b/sddm-$r/background-169.png" && -s "$T/b/sddm-$r/background-1610.png" ]] || complete=0
    else
        grep -q 'builtin: false' "$T/b/sddm-$r/Main.qml" && [[ ! -e "$T/b/sddm-$r/background-169.png" ]] || complete=0
    fi
    grep -q '^QtVersion=6$' "$T/b/sddm-$r/metadata.desktop" || complete=0
    grep -q "^Theme-Id=archenemy-$r\$" "$T/b/sddm-$r/metadata.desktop" || complete=0
    grep -Eq '^followWallpaper=[01]$' "$T/b/sddm-$r/theme.conf" || complete=0
    grep -q '^loginScreen=$' "$T/b/sddm-$r/theme.conf" || complete=0
    # Każdy układ stawia formularz przez Seat (monitor logowania), nie na
    # sztywno. yin i yang dzielą układ components/EclipseLogin.qml.
    layout="$T/b/sddm-$r/Main.qml"
    grep -q '^EclipseLogin {}$' "$layout" && layout="$T/b/sddm-$r/components/EclipseLogin.qml"
    grep -q 'Seat {' "$layout" && grep -q 'visible: seat.here' "$layout" || complete=0
    grep -q 'Backdrop {' "$layout" || complete=0
    grep -q 'Mark {' "$layout" || complete=0
    grep -q 'primaryScreen' "$layout" && complete=0
    # Pusta lista użytkowników SDDM nie może zablokować logowania: pole idzie
    # przez greeter.submit (nazwa, potem hasło), a F2/F3 zmieniają użytkownika
    # i sesję bez myszy.
    grep -q 'onAccepted: greeter.submit(text)' "$layout" && grep -q 'plain: greeter.needsName' "$layout" || complete=0
    grep -q 'enabledChoice: greeter.canSwitchUser' "$layout" || complete=0
    grep -q 'onSwitchUser: greeter.nextUser()' "$layout" && grep -q 'onSwitchSession: greeter.nextSession()' "$layout" || complete=0
    grep -q 'greeter.login(' "$layout" && complete=0
    # Warstwa z efektem znika w rendererze programowym — nigdy na sztywno.
    grep -q 'layer.enabled: true' "$layout" && complete=0
    # Kolory układu istnieją w theme.conf tego rice'a (literówka = niewidoczny tekst).
    while IFS= read -r token; do
        grep -q "^$token=" "$T/b/sddm-$r/theme.conf" || { complete=0; echo "    brak klucza $token w theme.conf rice'a $r"; }
    done < <(grep -oE 'config\.[A-Za-z]+' "$layout" "$T/b/sddm-$r/components/PowerRow.qml" | sed 's/.*config\.//' | sort -u)
done <<< "$rices_sddm"
check "każdy motyw SDDM kompletny (QML, QtVersion=6, tło, Seat, logo, klucze kolorów)" '(( complete ))'
check "Seat: kliknięcie na monitorze bez formularza przenosi go tam (config.loginScreen)" 'grep -q "onClicked: config.loginScreen = seat.own" "$REPO/src/system-theme/sddm/components/Seat.qml" && grep -q "enabled: !seat.here" "$REPO/src/system-theme/sddm/components/Seat.qml"'
check "Greeter: nazwa wpisana ręcznie zastępuje pustą listę użytkowników" 'grep -q "readonly property bool needsName: !listed && typedUser === \"\"" "$REPO/src/system-theme/sddm/components/Greeter.qml" && grep -q "function submit(text)" "$REPO/src/system-theme/sddm/components/Greeter.qml"'
check "primaryScreen tylko w Seat.qml (stała SDDM z chwili startu okna)" '[[ "$(grep -l primaryScreen "$REPO"/src/system-theme/sddm/components/*.qml "$REPO"/src/system-theme/sddm/*/Main.qml | xargs -n1 basename)" == Seat.qml ]]'
check "SDDM: niepusty katalog docelowy → odmowa"   '! bash "$BUILD" sddm yin "$T/b/sddm-yin" 2>/dev/null'
check "SDDM: nieznany rice → odmowa, bez katalogu" '! bash "$BUILD" sddm nope "$T/b/x" 2>/dev/null && [[ ! -e "$T/b/x" ]]'
check "SDDM: zła nazwa rice'a → odmowa"            '! bash "$BUILD" sddm "../yin" "$T/b/y" 2>/dev/null && [[ ! -e "$T/b/y" ]]'
svg_d="$(grep -o ' d="[^"]*"' "$REPO/assets/logo/archenemy-ae.svg" | head -1)"; svg_d="${svg_d# d=\"}"; svg_d="${svg_d%\"}"
check "logo Æ: Mark.qml rysuje tę samą ścieżkę co assets/logo/archenemy-ae.svg" \
    '[[ -n "$svg_d" ]] && grep -qF "PathSvg { path: \"$svg_d\" }" "$REPO/src/system-theme/sddm/components/Mark.qml"'

: > "$MOCK_LOG"
bash "$BUILD" grub "$T/b/grub" -a tron:archenemy >/dev/null 2>&1; rc=$?
check "GRUB: katalog zbudowany (kod 0)"            '[[ $rc -eq 0 ]]'
complete=1
while IFS= read -r r; do
    for f in "theme-$r-distro.txt" "theme-$r-archenemy.txt" "$r-logo.png" "$r-select_c.png" "$r-select_w.png" "$r-select_e.png"; do
        [[ -s "$T/b/grub/$f" ]] || complete=0
    done
    grep -q "selected_item_pixmap_style = \"$r-select_\*.png\"" "$T/b/grub/theme-$r-distro.txt" || complete=0
    grep -q "file = \"$r-logo.png\"" "$T/b/grub/theme-$r-archenemy.txt" || complete=0
    grep -qF "text = \"$GLYPH\"" "$T/b/grub/theme-$r-distro.txt" || complete=0
    grep -q 'id = "__timeout__"' "$T/b/grub/theme-$r-distro.txt" || complete=0
done <<< "$rices_grub"
check "GRUB: oba warianty logo i obrazki każdego rice'a" '(( complete ))'
check "GRUB: fonty wspólne z nazwami archenemy"   '[[ -s "$T/b/grub/text.pf2" && -s "$T/b/grub/small.pf2" && -s "$T/b/grub/logo.pf2" ]] && grep -q -- "-n archenemy text -s 22 " "$MOCK_LOG" && grep -q -- "-n archenemy logo -s 104 " "$MOCK_LOG"'
check "GRUB: -a zapisuje theme.txt wybranego wariantu" 'cmp -s "$T/b/grub/theme.txt" "$T/b/grub/theme-tron-archenemy.txt"'
check "GRUB: w katalogu nie ma nic wykonywalnego ani obcego" '[[ -z "$(find "$T/b/grub" -type f ! -name "*.txt" ! -name "*.png" ! -name "*.pf2")" ]]'
png_info="$(python3 - "$T/b/grub/tron-logo.png" <<'PY'
import struct, sys, zlib
data = open(sys.argv[1], "rb").read()
assert data[:8] == b"\x89PNG\r\n\x1a\n"
w, h, depth, kind = struct.unpack(">IIBB", data[16:26])
raw, pos = b"", 8
while pos < len(data):
    n, tag = struct.unpack(">I4s", data[pos:pos + 8])
    if tag == b"IDAT":
        raw += data[pos + 8:pos + 8 + n]
    pos += 12 + n
px = zlib.decompress(raw)
def at(x, y):
    o = y * (w * 4 + 1) + 1 + x * 4
    return px[o:o + 4]
# środek górnej belki litery E (pełny kolor) i lewy górny róg (pusto)
print(w, h, depth, kind, at(int(w * 0.75), int(h * 0.16)).hex(), at(1, 1).hex())
PY
)"
check "logo Æ: PNG 104×104 RGBA, kolor trona w literze, róg przezroczysty" '[[ "$png_info" == "104 104 8 6 00e5ffff 00e5ff00" ]]'
: > "$MOCK_LOG"
bash "$BUILD" grub "$T/b/grub4k" -H 2160 >/dev/null 2>&1
check "GRUB: wysokość 2160 podwaja rozmiary"       'grep -q "item_height = 96" "$T/b/grub4k/theme-tron-distro.txt" && grep -q -- "-s 44 " "$MOCK_LOG" && [[ ! -e "$T/b/grub4k/theme.txt" ]]'
check "GRUB: zła wysokość → odmowa"                '! bash "$BUILD" grub "$T/b/g1" -H 99999 2>/dev/null && ! bash "$BUILD" grub "$T/b/g2" -H abc 2>/dev/null'
check "GRUB: glif ASCII albo dwa znaki → odmowa"   '! bash "$BUILD" grub "$T/b/g3" -g A 2>/dev/null && ! bash "$BUILD" grub "$T/b/g4" -g "$GLYPH$GLYPH" 2>/dev/null'
check "GRUB: brak fontu w systemie → odmowa z nazwą pakietu" 'out="$(MOCK_FONTS=/nonexistent bash "$BUILD" grub "$T/b/g5" 2>&1)"; [[ $? -ne 0 && "$out" == *"ttf-jetbrains-mono-nerd"* ]]'
# Deklaracja rice'a to dane: wartość z poleceniem nie jest wykonywana.
mkdir -p "$T/repo2/rices/evil" && cp -r "$REPO/src" "$REPO/assets" "$REPO/scripts" "$REPO/install" "$T/repo2/" 2>/dev/null
printf 'GRUB_BACKGROUND="$(touch %s/pwned)"\nGRUB_TEXT="#000000"\n' "$T" > "$T/repo2/rices/evil/system-theme.conf"
bash "$T/repo2/src/system-theme/build.sh" grub "$T/b/g6" >/dev/null 2>&1; rc=$?
check "deklaracja rice'a to dane: polecenie w wartości nie wykonane, budowa odmawia" '[[ $rc -ne 0 && ! -e "$T/pwned" ]]'

echo "== B: system-theme-sync.sh — wybory użytkownika jako dane"
# sysroot <z tapetami?> — świeży system: motywy yin/tron + zmyślony rice „demo”
# (motyw bazowy dla demo_beta), katalog GRUB-a, ustawienia roota.
sysroot() {
    rm -rf "$S" "$A"; mkdir -p "$THEMES" "$S/etc/archenemy" "$S/boot/grub/themes" "$A/data/monitors"
    cp -r "$T/b/sddm-yin" "$THEMES/archenemy-yin"; cp -r "$T/b/sddm-tron" "$THEMES/archenemy-tron"
    cp -r "$T/b/sddm-tron" "$THEMES/archenemy-demo"
    cp -r "$T/b/grub" "$GDIR"; rm -f "$GDIR/theme.txt"
    cp "$GDIR/theme-tron-distro.txt" "$GDIR/theme-demo-distro.txt"
    printf 'STATE_USER=%s\nSTATE_DIR=%s\nGLYPH=%s\nSDDM=1\nGRUB=1\n' "$(id -un)" "$A" "$GLYPH" > "$S/etc/archenemy/system-theme.conf"
    : > "$MOCK_LOG"
}
sync() { bash "$SYNC" 2>&1; }
user_conf() { cat "$THEMES/archenemy-$1/theme.conf.user" 2>/dev/null; }
current() { grep -m1 '^Current=' "$DROPIN" 2>/dev/null | cut -d= -f2; }

sysroot; echo tron > "$A/.current_rice"
out="$(sync)"; rc=$?
check "rice tron: SDDM Current=archenemy-tron, kod 0" '[[ $rc -eq 0 && "$(current)" == archenemy-tron ]]'
check "bez pliku logo: logo=distro i glif z ustawień roota" '[[ "$(user_conf tron)" == *"logo=distro"* && "$(user_conf tron)" == *"distroGlyph=$GLYPH"* ]]'
check "GRUB: theme.txt = wariant tron + distro"    'cmp -s "$GDIR/theme.txt" "$GDIR/theme-tron-distro.txt"'
check "bez monitorów i wyboru: loginScreen pusty (monitor główny)" '[[ "$(user_conf tron)" == *$'"'"'\nloginScreen=\n'"'"'* ]]'
ino="$(stat -c '%i %Y' "$THEMES/archenemy-tron/theme.conf.user" "$DROPIN" "$GDIR/theme.txt")"
sync >/dev/null
check "drugi bieg bez zmian nie przepisuje plików" '[[ "$(stat -c "%i %Y" "$THEMES/archenemy-tron/theme.conf.user" "$DROPIN" "$GDIR/theme.txt")" == "$ino" ]]'
echo archenemy > "$A/data/launcher-logo.dat"; sync >/dev/null
check "logo archenemy: SDDM i GRUB przełączone"    '[[ "$(user_conf tron)" == *"logo=archenemy"* ]] && cmp -s "$GDIR/theme.txt" "$GDIR/theme-tron-archenemy.txt"'
echo "archenemy; rm -rf /" > "$A/data/launcher-logo.dat"; sync >/dev/null
check "śmieci w pliku logo → distro"               '[[ "$(user_conf tron)" == *"logo=distro"* ]] && cmp -s "$GDIR/theme.txt" "$GDIR/theme-tron-distro.txt"'
echo yin > "$A/.current_rice"; sync >/dev/null
check "Super+T na yin: oba motywy na yin"          '[[ "$(current)" == archenemy-yin ]] && cmp -s "$GDIR/theme.txt" "$GDIR/theme-yin-distro.txt"'
before="$(cd "$S" && find . -type f -exec md5sum {} + | sort)"
for bad_rice in "../../etc" "tron;id" 'tron$(id)' "TRON" "" "no-such-rice" "-rf"; do
    printf '%s\n' "$bad_rice" > "$A/.current_rice"; sync >/dev/null || true
done
check "zła nazwa rice'a i rice bez motywu: nic się nie zmienia" '[[ "$(cd "$S" && find . -type f -exec md5sum {} + | sort)" == "$before" ]]'
rm -f "$A/.current_rice"; out="$(sync)"; rc=$?
check "brak .current_rice: kod 0, nic nie zmienione" '[[ $rc -eq 0 && "$(cd "$S" && find . -type f -exec md5sum {} + | sort)" == "$before" ]]'
echo demo_beta > "$A/.current_rice"; sync >/dev/null
check "rice beta bez motywu bierze motyw rice'a bazowego" '[[ "$(current)" == archenemy-demo ]] && cmp -s "$GDIR/theme.txt" "$GDIR/theme-demo-distro.txt"'
rm -rf "$THEMES/archenemy-evil"; ln -s "$T" "$THEMES/archenemy-evil"; echo evil > "$A/.current_rice"; sync >/dev/null
check "motyw będący dowiązaniem jest pomijany"     '[[ "$(current)" == archenemy-demo && ! -e "$T/theme.conf.user" ]]'

echo "-- monitor logowania"
sysroot; echo tron > "$A/.current_rice"
printf 'MONITOR=HDMI-A-1\nRESOLUTION=2560x1440\nROLE=primary\nDESCRIPTION=TEST Vendor M1 0001\n' > "$A/data/monitors/HDMI-A-1.dat"
printf 'MONITOR=eDP-1\nRESOLUTION=1920x1200\nROLE=secondary\nDESCRIPTION=\n' > "$A/data/monitors/eDP-1.dat"
sync >/dev/null
check "domyślnie: monitor główny archenemy (ROLE=primary)" '[[ "$(user_conf tron)" == *"loginScreen=HDMI-A-1"* ]]'
echo eDP-1 > "$A/data/login-screen.dat"; sync >/dev/null
check "wybór z TUI: loginScreen=eDP-1"             '[[ "$(user_conf tron)" == *"loginScreen=eDP-1"* ]]'
echo primary > "$A/data/login-screen.dat"; sync >/dev/null
check "wybór „primary” wraca do monitora głównego" '[[ "$(user_conf tron)" == *"loginScreen=HDMI-A-1"* ]]'
printf 'eDP-1\nbackground=/etc/shadow\n' > "$A/data/login-screen.dat"; sync >/dev/null
check "druga linia pliku wyboru nie trafia do motywu" '[[ "$(user_conf tron)" == *"loginScreen=eDP-1"* && "$(user_conf tron)" != *shadow* && "$(grep -c "" "$THEMES/archenemy-tron/theme.conf.user")" -eq 5 ]]'
echo 'DP-1;x=y' > "$A/data/login-screen.dat"; sync >/dev/null
check "śmieci w wyborze monitora → monitor główny"  '[[ "$(user_conf tron)" == *"loginScreen=HDMI-A-1"* ]]'

echo "-- tapeta"
rm -f "$A/data/login-screen.dat"
printf 'desc:TEST Vendor M1 0001=%s\neDP-1=%s\n' "$T/one.png" "$T/photo.jpg" > "$A/data/wallpaper.dat"
sync >/dev/null
check "tron idzie za tapetą: kopia tapety monitora logowania" 'cmp -s "$THEMES/archenemy-tron/user-wallpaper" "$T/one.png" && [[ "$(user_conf tron)" == *"background=user-wallpaper"* ]]'
check "znacznik kopii to skrót, bez ścieżki użytkownika" '[[ "$(cat "$THEMES/archenemy-tron/user-wallpaper.stamp")" =~ ^[0-9a-f]{64}$ ]]'
ino="$(stat -c '%i' "$THEMES/archenemy-tron/user-wallpaper")"; sync >/dev/null
check "ta sama tapeta nie jest kopiowana drugi raz" '[[ "$(stat -c "%i" "$THEMES/archenemy-tron/user-wallpaper")" == "$ino" ]]'
echo eDP-1 > "$A/data/login-screen.dat"; sync >/dev/null
check "inny monitor logowania → jego tapeta (JPEG)" 'cmp -s "$THEMES/archenemy-tron/user-wallpaper" "$T/photo.jpg"'
rm -f "$A/data/login-screen.dat"
printf 'desc:TEST Vendor M1 0001=%s\n' "$T/two.png" > "$A/data/wallpaper.dat"; sync >/dev/null
check "Super+W: nowa tapeta zastępuje kopię"       'cmp -s "$THEMES/archenemy-tron/user-wallpaper" "$T/two.png"'
printf 'UNKNOWN-9=%s\n' "$T/one.png" > "$A/data/wallpaper.dat"; sync >/dev/null
check "brak linii monitora logowania → pierwsza poprawna" 'cmp -s "$THEMES/archenemy-tron/user-wallpaper" "$T/one.png"'
for bad_wall in "$T/notes.txt" "$T/missing.png" "relative/one.png" "$T" "/dev/zero"; do
    printf 'eDP-1=%s\n' "$bad_wall" > "$A/data/wallpaper.dat"; sync >/dev/null
    [[ ! -e "$THEMES/archenemy-tron/user-wallpaper" && "$(user_conf tron)" == *$'\nbackground=' ]] || { fail "odrzucona tapeta: $bad_wall"; continue; }
    ok "nie-obraz / brak pliku / katalog / urządzenie odrzucone: ${bad_wall##*/}"
    printf 'eDP-1=%s\n' "$T/one.png" > "$A/data/wallpaper.dat"; sync >/dev/null
done
check "po odrzuceniu poprawna tapeta wraca"        'cmp -s "$THEMES/archenemy-tron/user-wallpaper" "$T/one.png"'
check "w katalogu motywu nie zostają pliki tymczasowe" '[[ -z "$(find "$THEMES" -name ".user-wallpaper.*")" ]]'
echo yin > "$A/.current_rice"; sync >/dev/null
check "yin nie idzie za tapetą (followWallpaper=0)" '[[ ! -e "$THEMES/archenemy-yin/user-wallpaper" && "$(user_conf yin)" == *$'"'"'\nbackground='"'"' ]]'

echo "-- zmiana w trakcie biegu usługi (systemd nie budzi jej drugi raz)"
sysroot; echo tron > "$A/.current_rice"
( sleep 0.4; echo yin > "$A/.current_rice" ) &
INVOCATION_ID=test SYSTEM_THEME_SETTLE=1 bash "$SYNC" >/dev/null 2>&1; wait
check "pod systemd: zapis podczas ciszy po obiegu jest zastosowany" '[[ "$(current)" == archenemy-yin ]] && cmp -s "$GDIR/theme.txt" "$GDIR/theme-yin-distro.txt"'
start=$SECONDS; echo tron > "$A/.current_rice"; sync >/dev/null
check "uruchomienie ręczne nie czeka"               '[[ "$(current)" == archenemy-tron ]] && (( SECONDS - start <= 1 ))'

echo "-- ustawienia roota"
sysroot; echo tron > "$A/.current_rice"
sed -i 's/^SDDM=1/SDDM=0/' "$S/etc/archenemy/system-theme.conf"; sync >/dev/null
check "SDDM=0: tylko GRUB"                         '[[ ! -e "$DROPIN" ]] && cmp -s "$GDIR/theme.txt" "$GDIR/theme-tron-distro.txt"'
sysroot; echo tron > "$A/.current_rice"
sed -i 's/^GRUB=1/GRUB=0/' "$S/etc/archenemy/system-theme.conf"; sync >/dev/null
check "GRUB=0: tylko SDDM"                         '[[ "$(current)" == archenemy-tron && ! -e "$GDIR/theme.txt" ]]'
rm -f "$S/etc/archenemy/system-theme.conf"; out="$(sync)"; rc=$?
check "brak ustawień roota: kod 1 z nazwą instalatora" '[[ $rc -eq 1 && "$out" == *"system-theme-installation.sh"* ]]'
printf 'STATE_USER=%s\nSTATE_DIR=relative/dir\n' "$(id -un)" > "$S/etc/archenemy/system-theme.conf"; out="$(sync)"; rc=$?
check "zły STATE_DIR: kod 1"                       '[[ $rc -eq 1 && "$out" == *"bad STATE_DIR"* ]]'

echo "== C: system-theme-installation.sh"
# machine <sddm+grub|sdboot|nodm> — świeża maszyna przed instalacją.
machine() {
    rm -rf "$S" "$A"; mkdir -p "$S/etc/systemd/system" "$S/etc/default" "$S/boot" "$A/data/monitors"
    printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\n#GRUB_THEME="/path/to/gfxtheme"\nGRUB_GFXMODE=auto\n' > "$GDEF"
    case "$1" in
        sddm+grub) ln -s /usr/lib/systemd/system/sddm.service "$S/etc/systemd/system/display-manager.service"
                   mkdir -p "$S/boot/grub"; echo "# TEST grub.cfg" > "$S/boot/grub/grub.cfg" ;;
        sdboot)    mkdir -p "$S/boot/loader/entries" ;;
        nodm)      mkdir -p "$S/boot/grub"; echo "# TEST grub.cfg" > "$S/boot/grub/grub.cfg" ;;
    esac
    echo tron > "$A/.current_rice"
    printf 'MONITOR=eDP-1\nRESOLUTION=2560x1600\nROLE=primary\nDESCRIPTION=\n' > "$A/data/monitors/eDP-1.dat"
    : > "$MOCK_LOG"
}
inst() { printf '%b' "$1" | bash "$INST" "${@:2}" 2>&1; }
snap() { (cd "$S" && find . \( -type f -o -type l \) -exec md5sum {} + 2>/dev/null | sort); }

machine sddm+grub; before="$(snap)"
out="$(inst '')"; rc=$?
check "domyślne N: nic nie zmienione, kod 0, bez sudo" '[[ $rc -eq 0 && "$(snap)" == "$before" && ! -s "$MOCK_LOG" && "$out" == *"Nothing was changed"* ]]'
check "przed pytaniem: lista zapisów i droga powrotu" '[[ "$out" == *"/boot/grub/themes/archenemy/"* && "$out" == *"--remove"* && "$out" == *"does not stop the boot"* ]]'

machine sddm+grub
out="$(inst 'y\nn\n')"; rc=$?
check "y + N na usługę: kod 0"                     '[[ $rc -eq 0 ]]'
check "motywy SDDM wszystkich rice'ów w systemie"  '[[ -f "$THEMES/archenemy-yin/Main.qml" && -f "$THEMES/archenemy-tron/components/Seat.qml" ]]'
check "SDDM wskazuje motyw aktywnego rice'a (odczyt)" '[[ "$(current)" == archenemy-tron && "$out" == *"SDDM theme now: archenemy-tron"* ]]'
check "GRUB: katalog motywu z wysokością ekranu z warstwy maszynowej" 'cmp -s "$GDIR/theme.txt" "$GDIR/theme-tron-distro.txt" && grep -q "screen 1600 px high" "$GDIR/theme.txt"'
check "GRUB_THEME ustawiony, kopia pliku sprzed zmiany" 'grep -qx "GRUB_THEME=\"/boot/grub/themes/archenemy/theme.txt\"" "$GDEF" && ! grep -q "^GRUB_THEME" "$GDEF.archenemy.bak" && grep -q "^#GRUB_THEME=" "$GDEF"'
check "jedna regeneracja grub.cfg, grub.cfg wskazuje motyw" '[[ "$(grep -c "^grub-mkconfig" "$MOCK_LOG")" -eq 1 ]] && grep -q "themes/archenemy/theme.txt" "$S/boot/grub/grub.cfg"'
check "skrypt roota i ustawienia zainstalowane"    '[[ -x "$S/usr/local/lib/archenemy/system-theme-sync" ]] && cmp -s "$S/usr/local/lib/archenemy/system-theme-sync" "$SYNC" && grep -qx "STATE_DIR=$A" "$S/etc/archenemy/system-theme.conf" && grep -qx "STATE_USER=$(id -un)" "$S/etc/archenemy/system-theme.conf"'
check "bez „y” usługa nie powstaje"                 '[[ ! -e "$S/etc/systemd/system/archenemy-system-theme.path" ]] && ! grep -q "^systemctl" "$MOCK_LOG" && [[ "$out" == *"Service not installed"* ]]'
check "motyw w systemie nie zawiera dowiązań do katalogu użytkownika" '[[ -z "$(find "$THEMES" "$GDIR" -type l)" ]]'
out="$(inst 'y\nn\n')"; rc=$?
check "ponowny bieg: kod 0, kopia grub nie nadpisana, jedna linia GRUB_THEME" '[[ $rc -eq 0 ]] && ! grep -q "^GRUB_THEME" "$GDEF.archenemy.bak" && [[ "$(grep -c "^GRUB_THEME=" "$GDEF")" -eq 1 ]]'

machine sddm+grub
printf 'MONITOR=HDMI-A-1\nRESOLUTION=2560x1440\nROLE=primary\nDESCRIPTION=\n' > "$A/data/monitors/HDMI-A-1.dat"
printf 'MONITOR=eDP-1\nRESOLUTION=1920x1200\nROLE=secondary\nDESCRIPTION=\n' > "$A/data/monitors/eDP-1.dat"
inst 'y\nn\n' >/dev/null
check "GRUB: laptop z monitorem zewnętrznym jako głównym → wysokość ekranu wbudowanego" 'grep -q "screen 1200 px high" "$GDIR/theme.txt"'
rm -f "$A/data/monitors/eDP-1.dat"; inst 'y\nn\n' >/dev/null
check "GRUB: bez ekranu wbudowanego → wysokość monitora głównego" 'grep -q "screen 1440 px high" "$GDIR/theme.txt"'
rm -f "$A"/data/monitors/*.dat; inst 'y\nn\n' >/dev/null
check "GRUB: bez danych o monitorach → 1080"       'grep -q "screen 1080 px high" "$GDIR/theme.txt"'

machine sddm+grub
out="$(inst 'y\n' --confirmed)"; rc=$?
check "--confirmed: pierwsze „y” idzie na usługę"   '[[ $rc -eq 0 && -f "$S/etc/systemd/system/archenemy-system-theme.path" && -f "$S/etc/systemd/system/archenemy-system-theme.service" ]]'
check "usługa: pilnuje czterech plików stanu"      'for f in .current_rice data/launcher-logo.dat data/login-screen.dat data/wallpaper.dat; do grep -qx "PathChanged=$A/$f" "$S/etc/systemd/system/archenemy-system-theme.path" || exit 1; done'
check "usługa: woła kopię roota, nie plik z repo"  'grep -qx "ExecStart=/usr/local/lib/archenemy/system-theme-sync" "$S/etc/systemd/system/archenemy-system-theme.service" && ! grep -q "$REPO\|$A" "$S/etc/systemd/system/archenemy-system-theme.service"'
check "usługa włączona i sprawdzona"               'grep -qx "sudo systemctl enable --now archenemy-system-theme.path" "$MOCK_LOG" && grep -q "^systemctl is-active" "$MOCK_LOG" && [[ "$out" == *"Automatic switching is on"* ]]'
machine sddm+grub
out="$(MOCK_ACTIVE_RC=3 inst 'y\ny\n')"; rc=$?
check "usługa nieaktywna po włączeniu: kod 1, bez ✓ usługi" '[[ $rc -eq 1 && "$out" == *"service is not active"* && "$out" != *"Automatic switching is on"* ]]'

echo "-- cudza konfiguracja"
machine sddm+grub; mkdir -p "$S/etc/sddm.conf.d"; printf '[Theme]\nCurrent=breeze\n' > "$S/etc/sddm.conf.d/10-theme.conf"
out="$(inst 'n\ny\nn\n')"; rc=$?
check "cudzy motyw SDDM + N: ekran logowania nietknięty, GRUB idzie dalej" '[[ $rc -eq 0 && ! -e "$DROPIN" && ! -d "$THEMES" && -f "$GDIR/theme.txt" && "$out" == *"uses the theme '"'"'breeze'"'"'"* ]]'
check "SDDM=0 w ustawieniach roota"                'grep -qx "SDDM=0" "$S/etc/archenemy/system-theme.conf"'
machine sddm+grub; mkdir -p "$S/etc/sddm.conf.d"; printf '[Theme]\nCurrent=breeze\n' > "$S/etc/sddm.conf.d/10-theme.conf"
out="$(inst 'y\ny\nn\n')"; rc=$?
check "cudzy motyw SDDM + y: nasz plik wygrywa, cudzy nietknięty" '[[ $rc -eq 0 && "$(current)" == archenemy-tron && "$out" == *"SDDM theme now: archenemy-tron"* ]] && grep -qx "Current=breeze" "$S/etc/sddm.conf.d/10-theme.conf"'
machine sddm+grub; printf '[Autologin]\nUser=x\n[Theme]\nCurrent=sugar\n' > "$S/etc/sddm.conf"
out="$(inst 'y\nn\n')"; rc=$?
check "/etc/sddm.conf ustawia motyw: nie edytujemy, SDDM pominięty" '[[ $rc -eq 0 && ! -e "$DROPIN" && "$out" == *"/etc/sddm.conf sets Current=sugar"* ]] && grep -qx "Current=sugar" "$S/etc/sddm.conf"'
machine sddm+grub; echo 'GRUB_THEME="/usr/share/grub/themes/starfield/theme.txt"' >> "$GDEF"
out="$(inst 'n\ny\nn\n')"; rc=$?
check "cudzy motyw GRUB + N: /etc/default/grub i /boot nietknięte" '[[ $rc -eq 0 && ! -d "$GDIR" && ! -e "$GDEF.archenemy.bak" && "$out" == *"starfield"* ]] && ! grep -q "^grub-mkconfig" "$MOCK_LOG" && grep -q starfield "$GDEF"'
machine sddm+grub; echo 'GRUB_THEME="/usr/share/grub/themes/starfield/theme.txt"' >> "$GDEF"
out="$(inst 'y\ny\nn\n')"; rc=$?
check "cudzy motyw GRUB + y: zastąpiony, stary w kopii" '[[ $rc -eq 0 ]] && grep -qx "GRUB_THEME=\"/boot/grub/themes/archenemy/theme.txt\"" "$GDEF" && ! grep -q starfield "$GDEF" && grep -q starfield "$GDEF.archenemy.bak"'
out="$(inst '' --remove)"; rc=$?
check "--remove po zastąpieniu: wraca cudzy GRUB_THEME" '[[ $rc -eq 0 ]] && grep -qx "GRUB_THEME=\"/usr/share/grub/themes/starfield/theme.txt\"" "$GDEF" && [[ ! -e "$GDIR" ]]'
machine sddm+grub; echo 'GRUB_TERMINAL_OUTPUT=console' >> "$GDEF"
out="$(inst 'y\nn\n')"; rc=$?
check "GRUB_TERMINAL_OUTPUT=console: menu pominięte z instrukcją" '[[ $rc -eq 0 && ! -d "$GDIR" && "$out" == *"ignores themes"* ]] && ! grep -q "^grub-mkconfig" "$MOCK_LOG" && [[ "$(current)" == archenemy-tron ]]'

machine sddm+grub; echo 'GRUB_TERMINAL="serial console"' >> "$GDEF"
out="$(inst 'y\nn\n')"; rc=$?
check "GRUB_TERMINAL=\"serial console\": menu pominięte, GRUB_THEME nietknięty" '[[ $rc -eq 0 && ! -d "$GDIR" && "$out" == *"text terminal"* ]] && ! grep -q "^GRUB_THEME" "$GDEF" && ! grep -q "^grub-mkconfig" "$MOCK_LOG"'
machine sddm+grub; printf 'GRUB_TERMINAL_OUTPUT=gfxterm\nGRUB_TERMINAL="serial"\n' >> "$GDEF"
out="$(inst 'y\nn\n')"; rc=$?
check "GRUB_TERMINAL wygrywa z GRUB_TERMINAL_OUTPUT (jak w grub-mkconfig)" '[[ $rc -eq 0 && ! -d "$GDIR" && "$out" == *"text terminal"* ]]'
machine sddm+grub; echo 'GRUB_TERMINAL_OUTPUT="gfxterm serial"' >> "$GDEF"
out="$(inst 'y\nn\n')"; rc=$?
check "terminal z gfxterm obok szeregowego: motyw instalowany" '[[ $rc -eq 0 && -f "$GDIR/theme.txt" ]] && grep -q "^GRUB_THEME=" "$GDEF"'
machine sddm+grub; sed -i 's/^GRUB_GFXMODE=.*/GRUB_GFXMODE=1920x1080x32,auto/' "$GDEF"
out="$(inst 'y\nn\n')"; rc=$?
check "jawny GRUB_GFXMODE wygrywa z rozdzielczością monitora" 'grep -q "screen 1080 px high" "$GDIR/theme.txt" && [[ "$out" == *"1080 px high (from GRUB_GFXMODE)"* ]]'
machine sddm+grub
out="$(inst 'y\nn\n')"; rc=$?
check "GRUB_GFXMODE=auto: wysokość ekranu wbudowanego i podpowiedź, jak ją zmienić" '[[ "$out" == *"1600 px high (from the laptop panel)"*"set GRUB_GFXMODE="* ]]'

echo "-- maszyny bez SDDM albo bez GRUB-a"
machine sdboot; before="$(snap)"
out="$(PATH="$T/nosddm:$REAL_PATH" inst 'y\ny\n')"; rc=$?
check "systemd-boot i brak SDDM: nic do zrobienia, kod 0, bez pytań o zapis" '[[ $rc -eq 0 && "$(snap)" == "$before" && "$out" == *"Nothing to theme"* ]] && ! grep -q "^sudo" "$MOCK_LOG"'
machine nodm
out="$(inst 'y\nn\n')"; rc=$?
check "SDDM zainstalowany, ale nie jest menedżerem logowania: tylko GRUB" '[[ $rc -eq 0 && ! -d "$THEMES" && -f "$GDIR/theme.txt" && "$out" == *"not the enabled display manager"* ]] && grep -qx "SDDM=0" "$S/etc/archenemy/system-theme.conf"'
machine sddm+grub
out="$(MOCK_GRUB_RC=1 inst 'y\ny\n')"; rc=$?
check "grub-mkconfig pada: kod 1, bez usługi, droga powrotu w komunikacie" '[[ $rc -eq 1 && "$out" == *"--remove"* && ! -e "$S/etc/systemd/system/archenemy-system-theme.path" && "$out" != *"✓ Done"* ]]'
machine sddm+grub; before="$(snap)"
out="$(ARCHENEMY_OS_RELEASE="$T/os-release-fedora" inst 'y\ny\n')"; rc=$?
check "Fedora: instrukcja, kod 2, nic nie zmienione" '[[ $rc -eq 2 && "$(snap)" == "$before" && "$out" == *"grub2"* ]] && ! grep -q "^sudo" "$MOCK_LOG"'
check "nieznany argument: kod 1 przed jakąkolwiek zmianą" 'out="$(inst "" --force)"; [[ $? -eq 1 && "$(snap)" == "$before" ]]'

echo "-- --remove"
machine sddm+grub; clean="$(snap)"
inst 'y\ny\n' >/dev/null; : > "$MOCK_LOG"
mkdir -p "$THEMES/archenemy-mine" "$THEMES/breeze"; echo "user theme" > "$THEMES/archenemy-mine/Main.qml"
out="$(inst '' --remove)"; rc=$?
check "--remove: kod 0, usługa wyłączona, pliki archenemy usunięte" '[[ $rc -eq 0 ]] && grep -qx "sudo systemctl disable --now archenemy-system-theme.path" "$MOCK_LOG" && [[ ! -e "$DROPIN" && ! -e "$GDIR" && ! -e "$THEMES/archenemy-tron" && ! -e "$S/usr/local/lib/archenemy" && ! -e "$S/etc/archenemy" && ! -e "$S/etc/systemd/system/archenemy-system-theme.path" ]]'
check "--remove: cudze katalogi motywów zostają"    '[[ -f "$THEMES/archenemy-mine/Main.qml" && -d "$THEMES/breeze" ]]'
check "--remove: GRUB_THEME zniknął, grub.cfg zregenerowany bez motywu" '! grep -q "^GRUB_THEME" "$GDEF" && [[ "$(grep -c "^grub-mkconfig" "$MOCK_LOG")" -eq 1 ]] && ! grep -q "themes/archenemy" "$S/boot/grub/grub.cfg"'
rm -rf "$THEMES/archenemy-mine" "$THEMES/breeze"; rmdir "$THEMES" "$S/usr/share/sddm" "$S/usr/share" "$S/usr/local/lib" "$S/usr/local" "$S/usr" "$S/etc/sddm.conf.d" "$S/boot/grub/themes" 2>/dev/null
check "po --remove system jak przed instalacją (plus kopia /etc/default/grub)" '[[ "$(snap | grep -v "grub.archenemy.bak\|default/grub$\|grub.cfg$")" == "$(echo "$clean" | grep -v "default/grub$\|grub.cfg$")" ]] && grep -q "^GRUB_GFXMODE=auto" "$GDEF"'
: > "$MOCK_LOG"; out="$(inst '' --remove)"; rc=$?
check "drugie --remove: kod 0, bez regeneracji GRUB-a" '[[ $rc -eq 0 ]] && ! grep -q "^grub-mkconfig" "$MOCK_LOG"'
machine sddm+grub; inst 'y\nn\n' >/dev/null; : > "$MOCK_LOG"
out="$(MOCK_GRUB_RC=1 inst '' --remove)"; rc=$?
check "--remove, grub-mkconfig pada: kod 1, katalog motywu zostaje (grub.cfg nadal go wskazuje)" '[[ $rc -eq 1 && -f "$GDIR/theme.txt" && "$out" == *"stays until"* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
