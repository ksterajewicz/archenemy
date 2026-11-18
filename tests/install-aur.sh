#!/usr/bin/env bash
# =============================================
#   archenemy - tests/install-aur.sh
#   Kroki AUR instalatora (install/lib/aur.sh, K6+K7 z audytu
#   bezpieczeństwa 2026-11-14) na atrapach git/makepkg/yay/pagera w mktemp:
#   yay budowany w świeżym katalogu mktemp (nie /tmp/yay) i sprzątany,
#   przegląd PKGBUILD na żądanie, ✓ tylko gdy yay naprawdę jest w PATH,
#   `--diffmenu --answerdiff All` wyłącznie po „y” (I3); przegląd działa bez less (pager
#   z zapasem i GIT_PAGER dla yay, I1 z przeglądu 2026-11-15); Ctrl+C w [4]
#   zatrzymuje install.sh (I2, wycinek [4]–[5]); yay zawsze ze stałego adresu
#   AUR, zmienna środowiska go nie podmienia (R1 I4). Bez sieci, bez roota.
#   Uruchom: bash tests/install-aur.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2034,SC2016,SC1111  # kolory czyta biblioteka; check() robi eval na cytowanym wyrażeniu; „” w etykietach to tekst
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

mkdir -p "$T/bin" "$T/tmp" "$T/log"
export TMPDIR="$T/tmp" LOG="$T/log"
# git clone <url> <katalog> → katalog z PKGBUILD (adres do clone-url); MOCK_CLONE_FAIL=1 = błąd sieci.
cat > "$T/bin/git" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == clone ]] || exit 1
[[ -n "${MOCK_CLONE_FAIL:-}" ]] && exit 128
mkdir -p "$3" && echo 'pkgname=yay' > "$3/PKGBUILD" && echo "$3" > "$LOG/clone-dir" && echo "$2" > "$LOG/clone-url"
EOF
# makepkg -si → zapisuje katalog budowy; MOCK_MAKEPKG_INSTALLS=1 „instaluje” yay.
cat > "$T/bin/makepkg" <<'EOF'
#!/usr/bin/env bash
pwd > "$LOG/makepkg-cwd"
[[ -n "${MOCK_MAKEPKG_INSTALLS:-}" ]] && printf '#!/usr/bin/env bash\necho "$*" > "$LOG/yay-args"\necho "${GIT_PAGER-<unset>}" > "$LOG/yay-git-pager"\n' > "$MOCK_BIN/yay" && chmod +x "$MOCK_BIN/yay"
exit "${MOCK_MAKEPKG_RC:-0}"
EOF
cat > "$T/bin/pager" <<'EOF'
#!/usr/bin/env bash
echo "$1" > "$LOG/paged"
EOF
chmod +x "$T/bin"/*
# PATH tylko z atrap i potrzebnych narzędzi: prawdziwy yay w systemie
# (np. na maszynie dewelopera) zafałszowałby test „✓ tylko gdy yay jest w PATH”.
# Bez less (świeży Arch go nie ma — I1); more osobno, żeby sprawdzić też cat.
mkdir -p "$T/sys" "$T/sys-more"
for c in bash sh env mktemp rm cat mkdir dirname chmod find sleep setsid timeout; do ln -s "$(command -v "$c")" "$T/sys/$c"; done
ln -s "$(command -v more)" "$T/sys-more/more"
ORIG_PATH="$PATH"
export PATH="$T/bin:$T/sys" MOCK_BIN="$T/bin" PAGER="$T/bin/pager"
RED='' GREEN='' YELLOW='' NC=''

reset_case() { rm -rf "$T/log"/* "$T/bin/yay"; unset MOCK_CLONE_FAIL MOCK_MAKEPKG_INSTALLS MOCK_MAKEPKG_RC; }
run_boot() {   # run_boot <stdin> — aur_bootstrap_yay w osobnym bashu; wyjście + RC
    out="$(printf '%b' "$1" | bash -c 'source "$0"; aur_bootstrap_yay' "$REPO/install/lib/aur.sh" 2>&1)"; RC=$?
}

echo "== budowa yay: świeży mktemp, sprzątanie, odczytany wynik"
reset_case; mkdir -p "$T/tmp/yay"; echo podstawiony > "$T/tmp/yay/PKGBUILD"
export MOCK_MAKEPKG_INSTALLS=1
run_boot '\n'
check "Enter przy przeglądzie → makepkg uruchomiony"  '[[ -f "$LOG/makepkg-cwd" && $RC -eq 0 ]]'
check "budowa w mktemp, nie w stałym \$TMPDIR/yay"     '[[ "$(cat "$LOG/makepkg-cwd")" == "$T/tmp/archenemy-yay."*"/yay" ]]'
check "katalog budowy usunięty po biegu"              '[[ ! -e "$(dirname "$(cat "$LOG/clone-dir")")" ]]'
check "podstawiony \$TMPDIR/yay nietknięty i nieużyty" '[[ "$(cat "$T/tmp/yay/PKGBUILD")" == podstawiony ]]'
check "zdanie o AUR przed budową"                     '[[ "$out" == *"comes from the AUR"* ]]'
check "✓ dopiero gdy yay jest w PATH"                 '[[ "$out" == *"✓ yay installed"* && -x "$T/bin/yay" ]]'

echo "== źródło yay: stały adres AUR, bez haka ze środowiska (R1 I4)"
# Dawny hak ARCHENEMY_YAY_URL (bez bramki ARCHENEMY_TEST) podmieniał repo, które
# makepkg -si instaluje przez sudo pacman -U; testy go nie używały.
reset_case; export MOCK_MAKEPKG_INSTALLS=1 ARCHENEMY_YAY_URL="file://$T/obce-yay"
run_boot '\n'
unset ARCHENEMY_YAY_URL
check "ARCHENEMY_YAY_URL w środowisku nie zmienia źródła yay" '[[ "$(cat "$LOG/clone-url" 2>/dev/null)" == https://aur.archlinux.org/yay.git ]]'

echo "== przegląd PKGBUILD na żądanie"
reset_case; export MOCK_MAKEPKG_INSTALLS=1
run_boot 'y\nn\n'
check "„y” → pager dostaje PKGBUILD"                  '[[ "$(cat "$LOG/paged" 2>/dev/null)" == */yay/PKGBUILD ]]'
check "odmowa po przeglądzie → makepkg NIE rusza"     '[[ ! -f "$LOG/makepkg-cwd" && $RC -ne 0 ]]'
check "odmowa → brak ✓"                               '[[ "$out" != *"✓ yay installed"* ]]'
reset_case; export MOCK_MAKEPKG_INSTALLS=1
run_boot 'y\ny\n'
check "przegląd + „y” → budowa"                       '[[ -f "$LOG/makepkg-cwd" && $RC -eq 0 ]]'

echo "== przegląd bez less (I1): pager z zapasem, \$PAGER przez sh -c"
# Dawniej "${PAGER:-less}": bez less „less: command not found” zamiast PKGBUILD.
boot_paged() {   # boot_paged <PATH> <PAGER> — „y” przy przeglądzie, potem odmowa budowy
    reset_case
    out="$(printf 'y\nn\n' | PATH="$1" PAGER="$2" bash -c 'source "$0"; aur_bootstrap_yay' "$REPO/install/lib/aur.sh" 2>&1)"; RC=$?
}
TAB=$'\t'
boot_paged "$T/bin:$T/sys:$T/sys-more" ''
check "bez PAGER i less → more pokazuje PKGBUILD"     '[[ "$out" == *"pkgname=yay"* && "$out" != *"not found"* ]]'
check "po przeglądzie dalej pytanie o budowę"         '[[ "$out" == *"not built at your request"* && ! -f "$LOG/makepkg-cwd" ]]'
boot_paged "$T/bin:$T/sys" ''
check "bez less i more → cat pokazuje PKGBUILD"       '[[ "$out" == *"pkgname=yay"* && "$out" != *"not found"* ]]'
boot_paged "$T/bin:$T/sys" 'cat -n'
check "PAGER z argumentami („cat -n”) działa"         '[[ "$out" == *"1${TAB}pkgname=yay"* ]]'
boot_paged "$T/bin:$T/sys:$T/sys-more" 'no-such-pager -R'
check "PAGER bez programu → zapas, PKGBUILD widać"    '[[ "$out" == *"pkgname=yay"* && "$out" == *"using a fallback pager"* ]]'

echo "== porażki bez fałszywego ✓"
reset_case
run_boot '\n'
check "makepkg 0, ale yay nie w PATH → ✗"             '[[ $RC -ne 0 && "$out" != *"✓ yay installed"* ]]'
reset_case; export MOCK_CLONE_FAIL=1
run_boot '\n'
check "nieudany clone → ✗, makepkg nie rusza"         '[[ $RC -ne 0 && ! -f "$LOG/makepkg-cwd" ]]'
check "nieudany clone → bez śmieci w \$TMPDIR"         '[[ -z "$(find "$T/tmp" -maxdepth 1 -name "archenemy-yay.*")" ]]'

echo "== yay -S: zdanie o AUR i --diffmenu --answerdiff All tylko po „y”"
reset_case; export MOCK_MAKEPKG_INSTALLS=1; run_boot '\n'
out="$(printf '\n' | bash -c 'source "$0"; aur_install brave-bin' "$REPO/install/lib/aur.sh" 2>&1)"
check "domyślnie bez --answerdiff"                    '[[ "$(cat "$LOG/yay-args")" == "-S --needed brave-bin" ]]'
check "zdanie o AUR przed yay -S"                     '[[ "$out" == *"user-submitted PKGBUILDs"* ]]'
out="$(printf 'y\n' | bash -c 'source "$0"; aur_install brave-bin' "$REPO/install/lib/aur.sh" 2>&1)"
check "„y” → --diffmenu --answerdiff All (I3)"        '[[ "$(cat "$LOG/yay-args")" == "-S --needed --diffmenu --answerdiff All brave-bin" ]]'

echo "== yay -S z przeglądem bez less (I1): GIT_PAGER, który istnieje"
# yay pokazuje diffy przez `git diff`; bez less git kończy się „unable to
# execute pager 'less'”. Atrapa yay zapisuje GIT_PAGER, który dostała.
inst_paged() {   # inst_paged <odpowiedź> <PATH> [zmienna=wartość…] — aur_install brave-bin
    local ans="$1" path="$2"; shift 2
    out="$(printf '%b' "$ans" | env -u GIT_PAGER PATH="$path" PAGER='' "$@" bash -c 'source "$0"; aur_install brave-bin' "$REPO/install/lib/aur.sh" 2>&1)"
}
inst_paged 'y\n' "$T/bin:$T/sys:$T/sys-more"
check "„y”, bez less → GIT_PAGER=more"                '[[ "$(cat "$LOG/yay-git-pager")" == more ]]'
inst_paged 'y\n' "$T/bin:$T/sys"
check "„y”, bez less i more → GIT_PAGER=cat"          '[[ "$(cat "$LOG/yay-git-pager")" == cat ]]'
inst_paged 'y\n' "$T/bin:$T/sys" GIT_PAGER=my-pager
check "GIT_PAGER użytkownika zostaje"                 '[[ "$(cat "$LOG/yay-git-pager")" == my-pager ]]'
inst_paged '\n' "$T/bin:$T/sys"
check "bez przeglądu GIT_PAGER nieustawiony"          '[[ "$(cat "$LOG/yay-git-pager")" == "<unset>" ]]'

echo "== Ctrl+C w [4] zatrzymuje install.sh (I2)"
# Wycinek prawdziwego install.sh: nagłówek do [1] bez strażnika roota (testy
# biegną też jako root) + kroki [4] i [5]. Ctrl+C jak z terminala: SIGINT do
# całej grupy procesów, w nowej sesji (setsid) z domyślną obsługą SIGINT
# (proces w tle w nieinteraktywnej powłoce miałby go ignorowany). Sygnał idzie
# na znacznik w wyjściu, nie po stałym czasie. Dawniej podpowłoka robiła
# `exit 130`, a instalator jechał dalej do [5] „Install missing…? [Y/n]”.
INST="$REPO/install/install.sh"
( PATH="$ORIG_PATH"   # grep/sed/cut są poza okrojonym PATH testu
  W=$(grep -n '^# ─── 1. WELCOME' "$INST" | cut -d: -f1)
  S4=$(grep -n '^# ─── 4. CHECK YAY' "$INST" | cut -d: -f1)
  S6=$(grep -n '^# ─── 6. DEVICE DETECTION' "$INST" | cut -d: -f1)
  sed -n "1,$((W-1))p" "$INST" | sed '/^if \[\[ \$EUID -eq 0 \]\]; then$/,/^fi$/d'
  sed -n "${S4},$((S6-1))p" "$INST" ) > "$T/step4-5.sh"
H4="$T/home4"; mkdir -p "$H4/archenemy/rices" "$H4/archenemy/packages" "$T/bin4"
# Nagłówek wykrywa dystrybucję (D5): atrapa os-release Archa, nie maszyna testu.
printf 'ID=arch\n' > "$T/os-release-arch"
PATH="$ORIG_PATH" ln -s "$REPO/install" "$H4/archenemy/install"
echo testpkg > "$H4/archenemy/packages/requirements-pacman.txt"
printf '#!/usr/bin/env bash\nexec "$MOCK_BIN/git" "$@"\n' > "$T/bin4/git"
printf '#!/usr/bin/env bash\necho "$*" >> "$LOG/sudo"\n' > "$T/bin4/sudo"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin4/pacman"
# Jak prawdziwy makepkg (/usr/bin/makepkg:113-114): na SIGINT sprząta
# i zgłasza ten sam sygnał ponownie. MOCK_MAKEPKG_WAIT=1 = długa budowa.
cat > "$T/bin4/makepkg" <<'EOF'
#!/usr/bin/env bash
trap 'echo "==> ERROR: Aborted by user!"; trap - INT; kill -INT $$' INT
echo MOCK-MAKEPKG-RUNNING
[[ -n "${MOCK_MAKEPKG_WAIT:-}" ]] && sleep 30
exit 0
EOF
chmod +x "$T/bin4"/*
run_int() {   # run_int <znacznik albo pusto> <odpowiedzi> [zmienna=wartość…] — wynik: out, RC
    local mark="$1" answers="$2" feeder; shift 2
    rm -f "$T/int.pid" "$T/log"/*; : > "$T/int.out"
    exec 3< <(printf '%b' "$answers"
              [[ -n "$mark" ]] || exit 0
              for ((i = 0; i < 300; i++)); do [[ "$(<"$T/int.out")" == *"$mark"* ]] && break; sleep 0.1; done
              pid="$(<"$T/int.pid")"
              kill -INT -- "-$pid" 2>/dev/null
              # Wejście otwarte, dopóki instalator żyje (albo doszedł do [5]).
              for ((i = 0; i < 300; i++)); do
                  kill -0 "$pid" 2>/dev/null || break
                  [[ "$(<"$T/int.out")" == *"[5]"* ]] && break
                  sleep 0.1
              done)
    feeder=$!
    timeout 30 env --default-signal=INT HOME="$H4" PATH="$T/bin4:$T/sys" \
        ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os-release-arch" "$@" \
        setsid bash -c 'echo $$ > "$1"; exec bash "$2"' _ "$T/int.pid" "$T/step4-5.sh" \
        <&3 >"$T/int.out" 2>&1
    RC=$?
    exec 3<&-; wait "$feeder" 2>/dev/null
    out="$(<"$T/int.out")"
}
run_int '' 'y\n\n'
check "kontrola bez Ctrl+C: bieg dochodzi do [5]"    '[[ $RC -eq 0 && "$out" == *"MOCK-MAKEPKG-RUNNING"* && "$out" == *"[5] Checking requirements"* ]]'
run_int MOCK-MAKEPKG-RUNNING 'y\n\n' MOCK_MAKEPKG_WAIT=1
check "Ctrl+C w makepkg → install.sh ginie od SIGINT" '[[ $RC -eq 130 && "$out" == *"Aborted by user"* ]]'
check "Ctrl+C w makepkg → brak [5] i instalacji"     '[[ "$out" != *"[5]"* && "$(cat "$LOG/sudo" 2>/dev/null)" != *testpkg* ]]'
check "Ctrl+C w makepkg → katalog budowy usunięty"   '[[ -z "$(find "$T/tmp" -maxdepth 1 -name "archenemy-yay.*")" ]]'
run_int "comes from the AUR" 'y\n'
check "Ctrl+C przy „Review PKGBUILD?” → koniec, bez [5]" '[[ $RC -eq 130 && "$out" != *"[5]"* && "$out" != *MOCK-MAKEPKG-RUNNING* ]]'
check "Ctrl+C przy pytaniu → katalog budowy usunięty" '[[ -z "$(find "$T/tmp" -maxdepth 1 -name "archenemy-yay.*")" ]]'

echo "== install.sh używa biblioteki"
INST="$(cat "$REPO/install/install.sh")"
check "brak stałego /tmp/yay"                         '[[ "$INST" != *"/tmp/yay"* ]]'
check "brak gołego yay -S (zawsze przez aur_install)" '[[ "$INST" != *"yay -S --needed \""* ]]'
check "install.sh source’uje install/lib/aur.sh"      '[[ "$INST" == *"source \"\$ARCHENEMY_DIR/install/lib/aur.sh\""* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
