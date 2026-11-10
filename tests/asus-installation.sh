#!/bin/bash
# =============================================
#   archenemy - tests/asus-installation.sh
#   Instalator narzędzi ASUS (install/asus-installation.sh) na atrapach pacman,
#   sudo, systemctl i supergfxctl. Bez roota, bez sieci.
#
#   Powód powstania: AUR ma kilku dostawców `asusctl` wykluczających się nawzajem,
#   więc sukces to pakiet o nazwie asusctl, nie cokolwiek, co ją dostarcza.
#   Uruchom: bash tests/asus-installation.sh   (kod 0 = wszystko przeszło)
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

mkdir -p "$T/bin"
export MOCK_DB="$T/installed" MOCK_LOG="$T/log"
printf '#!/bin/bash\nexec "$@"\n' > "$T/bin/sudo"

# Baza pakietów: plik z nazwami. -Qq <nazwa> znajduje też dostawcę, jak prawdziwy
# pacman (query.c: alpm_find_satisfier). -S podmienia pakiety w konflikcie.
cat > "$T/bin/pacman" <<'MOCK'
#!/bin/bash
echo "pacman $*" >> "$MOCK_LOG"
provider() {
    case "$1" in
        asusctl) grep -xE 'asusctl|asusctl-devel-git|asusctl-git|asusctl-x11|asusctl-nosystemd' "$MOCK_DB" ;;
        rog-control-center) grep -xE 'rog-control-center|asusctl-devel-git|rog-control-center-x11|rog-control-center-nosystemd' "$MOCK_DB" ;;
        *) grep -x "$1" "$MOCK_DB" ;;
    esac
}
case "$1" in
    -Qq)
        if [[ -z "${2:-}" ]]; then cat "$MOCK_DB"; exit 0; fi
        provider "$2" | head -1; [[ -n "$(provider "$2")" ]]; exit ;;
    -S)
        [[ "${MOCK_PACMAN_FAIL:-0}" == 1 ]] && exit 1
        [[ "${MOCK_PACMAN_NOOP:-0}" == 1 ]] && exit 0
        sed -i -E '/^(asusctl-devel-git|asusctl-git|asusctl-x11|asusctl-nosystemd|rog-control-center-x11|rog-control-center-nosystemd)$/d' "$MOCK_DB"
        printf 'asusctl\nrog-control-center\n' >> "$MOCK_DB"
        exit 0 ;;
    -Rns)
        shift
        for p in "$@"; do sed -i "/^$p\$/d" "$MOCK_DB"; done
        exit 0 ;;
esac
exit 1
MOCK

# systemctl: is-active mówi prawdę o tym, czy start/restart się udał.
cat > "$T/bin/systemctl" <<'MOCK'
#!/bin/bash
echo "systemctl $*" >> "$MOCK_LOG"
case "$1" in
    start|restart) [[ "${MOCK_ASUSD_DEAD:-0}" == 1 ]] || : > "$MOCK_LOG.active" ;;
    is-active) [[ -f "$MOCK_LOG.active" ]]; exit ;;
esac
exit 0
MOCK

cat > "$T/bin/supergfxctl" <<'MOCK'
#!/bin/bash
echo "${MOCK_GFX_MODE:-Hybrid}"
MOCK
chmod +x "$T"/bin/*
BASE_PATH="$PATH"

run() {  # run <odpowiedź> <pakiety...>: świeża baza, wynik w $out i $rc
    local answer="$1"; shift
    printf '%s\n' "$@" > "$MOCK_DB"
    : > "$MOCK_LOG"; rm -f "$MOCK_LOG.active"
    out="$(printf '%s\n' "$answer" | PATH="$T/bin:$BASE_PATH" bash "$REPO/install/asus-installation.sh" 2>&1)"
    rc=$?
}
installed() { grep -qx "$1" "$MOCK_DB"; }

echo "== czysta maszyna"
run "" hyprland
check "kod 0"                                 '[[ $rc -eq 0 ]]'
check "oba pakiety zainstalowane"             'installed asusctl && installed rog-control-center'
check "instaluje przez pacman --needed"       'grep -q "pacman -S --needed asusctl rog-control-center" "$MOCK_LOG"'
check "bez nazwy repo (użytkownicy [ogc])"    '! grep -q "extra/" "$MOCK_LOG"'
check "start, nie enable: unit bez [Install]" 'grep -q "systemctl start asusd" "$MOCK_LOG" && ! grep -q "systemctl enable" "$MOCK_LOG"'

echo "== pakiet z AUR"
run "" asusctl-devel-git
check "uprzedza o pytaniu pacmana"            '[[ "$out" == *"AUR packages found: asusctl-devel-git"* ]]'
check "podmieniony"                           '! installed asusctl-devel-git && installed asusctl'
check "kod 0"                                 '[[ $rc -eq 0 ]]'
check "restart: stary demon nie zostaje"      'grep -q "systemctl restart asusd" "$MOCK_LOG"'
check "pacman, nie jawne usuwanie"            '! grep -q -- "-Rns" "$MOCK_LOG"'

echo "== odmowa w pacmanie"
MOCK_PACMAN_FAIL=1 run "" asusctl-x11
check "kod 1"                                 '[[ $rc -eq 1 ]]'
check "nie melduje sukcesu"                   '[[ "$out" != *"✓"* ]]'
check "demon nietknięty"                      '! grep -q "systemctl" "$MOCK_LOG"'

echo "== pacman bez błędu, a dostawcą dalej AUR"
MOCK_PACMAN_NOOP=1 run "" asusctl-git rog-control-center
check "kod 1"                                 '[[ $rc -eq 1 ]]'
check "pokazuje, kto dostarcza"               '[[ "$out" == *"asusctl-git"* ]]'

echo "== asusd nie wstaje"
MOCK_ASUSD_DEAD=1 run "" hyprland
check "kod 2"                                 '[[ $rc -eq 2 ]]'
check "mówi o restarcie"                      '[[ "$out" == *"restart the computer"* ]]'

echo "== porzucone pakiety"
run "n" supergfxctl asusctltray-git
check "pyta"                                  '[[ "$out" == *"Unsupported ASUS packages found: asusctltray-git supergfxctl"* ]]'
check "n = zostają"                           'installed supergfxctl && installed asusctltray-git'
check "instalacja i tak idzie"                '[[ $rc -eq 0 ]]'
run "" supergfxctl
check "Enter = zostają"                       'installed supergfxctl'
run "y" supergfxctl asusctltray-git
check "y = usunięte"                          '! installed supergfxctl && ! installed asusctltray-git'

echo "== supergfxctl w trybie Integrated"
MOCK_GFX_MODE=Integrated run "y" supergfxctl asusctltray-git
check "ostrzega"                              '[[ "$out" == *"Integrated"* ]]'
check "supergfxctl zostaje"                   'installed supergfxctl'
check "reszta nadal do usunięcia"             '! installed asusctltray-git'
MOCK_GFX_MODE=Integrated run "y" supergfxctl
check "brak innych: bez pytania"              '[[ "$out" != *"Remove them"* ]]'

echo "== spięcie z instalatorem"
check "install.sh woła ten skrypt"            'grep -q "install/asus-installation.sh" "$REPO/install/install.sh"'
check "install.sh bez AUR dla ASUS-a"         '! grep -qE "yay .*(asusctl|rog-control)" "$REPO/install/install.sh"'
check "tryb 100755 w gicie albo pliku"        '[[ -x "$REPO/install/asus-installation.sh" ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
((FAIL == 0))
