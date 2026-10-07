#!/bin/bash
# =============================================
#   archenemy - tests/virtualbox.sh
#   Testy instalatora VirtualBoksa (install/virtualbox-installation.sh)
#   na ATRAPACH: sudo, pacman, modinfo, modprobe, uname, id, getent,
#   usermod w PATH, a katalog modułów jądra i /sys/module podmienione
#   hakami ARCHENEMY_MODULES_DIR / ARCHENEMY_SYSMODULE_DIR na katalogi
#   w mktemp. Bez roota, bez sieci, bez dotykania prawdziwego systemu.
#
#   Pilnuje: nagłówków każdego jądra w transakcji, sukcesu = vboxdrv
#   realnie załadowany (nie kod pacmana), kodu 2 przy jądrze bez restartu
#   i starej wersji modułu, oraz że grupa vboxusers zmienia się tylko
#   po jawnym „y”.
#   Uruchom: bash tests/virtualbox.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval (zmienne żyją w eval); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VB="$REPO/install/virtualbox-installation.sh"
if ! grep -q 'ARCHENEMY_MODULES_DIR' "$VB" || ! grep -q 'ARCHENEMY_SYSMODULE_DIR' "$VB"; then
    echo "✗ $VB bez haków testowych — nie uruchamiam (ładowałby prawdziwe moduły)"
    exit 1
fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── atrapy ──────────────────────────────────────────────────────────────────
mkdir -p "$T/bin"
cat > "$T/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
# pacman: -S logowane (porażka na żądanie MOCK_PACMAN_FAIL=1); -Qi = pakiet
# „jest”, chyba że wymieniony w MOCK_NOT_INSTALLED.
cat > "$T/bin/pacman" <<'EOF'
#!/bin/bash
echo "pacman $*" >> "$MOCK_LOG"
if [[ "$1" == "-Qi" ]]; then
    [[ " ${MOCK_NOT_INSTALLED:-} " != *" $2 "* ]]; exit
fi
[[ "${MOCK_PACMAN_FAIL:-0}" == 1 ]] && exit 1
exit 0
EOF
# modinfo -k <kver> [-F version] vboxdrv: moduł „jest”, gdy w atrapie leży
# <kver>/vboxdrv.ko; jego treść = wersja.
cat > "$T/bin/modinfo" <<'EOF'
#!/bin/bash
f="$ARCHENEMY_MODULES_DIR/$2/vboxdrv.ko"
[[ "$1" == "-k" && -f "$f" ]] || exit 1
[[ "${3:-}" == "-F" ]] && cat "$f"
exit 0
EOF
# modprobe <mod>: „ładuje” = tworzy /sys/module/<mod> z wersją zbudowaną dla
# działającego jądra; MOCK_MODPROBE_FAIL=1 → nic nie ładuje.
cat > "$T/bin/modprobe" <<'EOF'
#!/bin/bash
echo "modprobe $*" >> "$MOCK_LOG"
[[ "${MOCK_MODPROBE_FAIL:-0}" == 1 ]] && exit 1
mkdir -p "$ARCHENEMY_SYSMODULE_DIR/$1"
cat "$ARCHENEMY_MODULES_DIR/$MOCK_KVER/vboxdrv.ko" > "$ARCHENEMY_SYSMODULE_DIR/$1/version" 2>/dev/null
exit 0
EOF
cat > "$T/bin/uname" <<'EOF'
#!/bin/bash
echo "$MOCK_KVER"
EOF
# id -nG: grupy z pliku (usermod dopisuje), getent: grupa vboxusers istnieje
cat > "$T/bin/id" <<'EOF'
#!/bin/bash
[[ "$1" == "-un" ]] && { echo tester; exit 0; }
cat "$MOCK_GROUPS"
EOF
cat > "$T/bin/getent" <<'EOF'
#!/bin/bash
[[ "$*" == "group vboxusers" ]]
EOF
cat > "$T/bin/usermod" <<'EOF'
#!/bin/bash
echo "usermod $*" >> "$MOCK_LOG"
[[ "$1" == "-aG" ]] && printf ' %s' "$2" >> "$MOCK_GROUPS"
exit 0
EOF
chmod +x "$T/bin"/*
export PATH="$T/bin:$PATH"
export MOCK_LOG="$T/log" MOCK_GROUPS="$T/groups" USER=tester

setup() {   # setup <działające jądro> <kernele z modułem…> -- <kernele bez modułu…>
    rm -rf "${T:?}/modules" "${T:?}/sys"; : > "$MOCK_LOG"
    echo "tester wheel" > "$MOCK_GROUPS"
    mkdir -p "$T/modules" "$T/sys"
    export MOCK_KVER="$1"; shift
    local with=1 k
    for k in "$@"; do
        [[ "$k" == -- ]] && { with=0; continue; }
        mkdir -p "$T/modules/$k"
        echo "${k%-*}" > "$T/modules/$k/pkgbase"   # linux-lts-6.12 → linux-lts
        [[ "$with" -eq 1 ]] && echo "7.2.16" > "$T/modules/$k/vboxdrv.ko"
    done
    export ARCHENEMY_MODULES_DIR="$T/modules" ARCHENEMY_SYSMODULE_DIR="$T/sys"
}
# stdin: odpowiedź na pytanie o vboxusers; kod wyjścia w $rc
run_vb() { out=$(printf '%b' "$1" | bash "$VB" 2>&1); rc=$?; }

echo "== A: dwa jądra, moduł zbudowany, zgoda na vboxusers"
setup linux-7.2 linux-7.2 linux-lts-6.18
run_vb 'y\n'
check "kod 0"                                  '[[ $rc -eq 0 ]]'
check "virtualbox + host-dkms w transakcji"    'grep -q "pacman -S --needed virtualbox virtualbox-host-dkms" "$MOCK_LOG"'
check "nagłówki obu jąder"                     'grep -q -- "-S --needed.* linux-headers" "$MOCK_LOG" && grep -q "linux-lts-headers" "$MOCK_LOG"'
check "vboxdrv załadowany"                     '[[ -d "$T/sys/vboxdrv" ]] && grep -qx "modprobe vboxdrv" "$MOCK_LOG"'
check "moduły sieci załadowane"                'grep -qx "modprobe vboxnetadp" "$MOCK_LOG" && grep -qx "modprobe vboxnetflt" "$MOCK_LOG"'
check "dodany do vboxusers"                    'grep -q "usermod -aG vboxusers tester" "$MOCK_LOG"'

echo "== B: pacman zawodzi"
setup linux-7.2 linux-7.2
MOCK_PACMAN_FAIL=1 run_vb 'y\n'
check "kod 1"                                  '[[ $rc -eq 1 ]]'
check "brak modprobe"                          '! grep -q modprobe "$MOCK_LOG"'
check "brak usermod"                           '! grep -q usermod "$MOCK_LOG"'

echo "== C: pacman „udany”, a pakietu nie ma"
setup linux-7.2 linux-7.2
MOCK_NOT_INSTALLED="virtualbox-host-dkms" run_vb 'n\n'
check "kod 1"                                  '[[ $rc -eq 1 ]]'
check "brak fałszywego ✓ pakietów"             '[[ "$out" != *"✓ Pakiety VirtualBox zainstalowane"* ]]'

echo "== D: moduł nie powstał dla działającego jądra"
setup linux-7.2 linux-lts-6.18 -- linux-7.2
run_vb 'n\n'
check "kod 1"                                  '[[ $rc -eq 1 ]]'
check "ostrzeżenie wskazuje jądro"             '[[ "$out" == *"linux-7.2"* && "$out" == *"dkms status"* ]]'
check "brak modprobe"                          '! grep -q modprobe "$MOCK_LOG"'

echo "== E: moduł brak tylko dla drugiego jądra"
setup linux-7.2 linux-7.2 -- linux-lts-6.18
run_vb 'n\n'
check "kod 0 (działające jądro ma moduł)"      '[[ $rc -eq 0 ]]'
check "ostrzeżenie o linux-lts"                '[[ "$out" == *"linux-lts-6.18"* ]]'

echo "== F: jądro zaktualizowane bez restartu"
setup linux-7.1 linux-7.2
run_vb 'n\n'
check "kod 2"                                  '[[ $rc -eq 2 ]]'
check "brak modprobe"                          '! grep -q modprobe "$MOCK_LOG"'
check "prośba o restart"                       '[[ "$out" == *"Zrestartuj"* ]]'

echo "== G: vboxdrv już załadowany"
setup linux-7.2 linux-7.2
mkdir -p "$T/sys/vboxdrv"; echo "7.2.16" > "$T/sys/vboxdrv/version"
run_vb 'n\n'
check "kod 0, ta sama wersja"                  '[[ $rc -eq 0 ]]'
check "bez ponownego modprobe"                 '! grep -q modprobe "$MOCK_LOG"'
setup linux-7.2 linux-7.2
mkdir -p "$T/sys/vboxdrv"; echo "7.2.10" > "$T/sys/vboxdrv/version"
run_vb 'n\n'
check "kod 2 przy starej wersji w pamięci"     '[[ $rc -eq 2 && "$out" == *"vboxreload"* ]]'

echo "== H: modprobe nie ładuje modułu"
setup linux-7.2 linux-7.2
MOCK_MODPROBE_FAIL=1 run_vb 'n\n'
check "kod 1"                                  '[[ $rc -eq 1 ]]'
check "brak fałszywego ✓ vboxdrv"              '[[ "$out" != *"✓ vboxdrv załadowany"* ]]'

echo "== I: grupa vboxusers"
setup linux-7.2 linux-7.2
run_vb '\n'
check "Enter = bez usermod"                    '! grep -q usermod "$MOCK_LOG"'
setup linux-7.2 linux-7.2
echo "tester wheel vboxusers" > "$MOCK_GROUPS"
run_vb ''
check "już w grupie = bez pytania i usermod"   '! grep -q usermod "$MOCK_LOG" && [[ "$out" != *"Add tester"* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
