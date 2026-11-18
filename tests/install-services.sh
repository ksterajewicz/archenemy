#!/usr/bin/env bash
# =============================================
#   archenemy - tests/install-services.sh
#   Usługi install.sh (D7): power-profiles-daemon w [6], usługa mpd w [8l],
#   NetworkManager, zapora i audio w [10] — na każdej platformie, na
#   STANOWEJ atrapie systemctl. Wycinki kroków (sed po nagłówkach, jak
#   tests/install-platforms.sh) biegną z PRAWDZIWYM blokiem platformy
#   instalatora (pkg_route, manual_step, svc_check) na jawnym os-release.
#   Pilnuje:
#     - ✓ usługi dopiero po odczycie is-enabled I is-active: awaria enable,
#       kod 0 bez efektu, enabled-but-dead, częściowy start, brak busa
#       użytkownika — bez ✓/DONE, z ostrzeżeniem i wpisem w podsumowaniu;
#     - macierz mpd: usługa systemowa enabled/active, gniazdo użytkownika
#       enabled/active, usługa użytkownika enabled/active, zgoda i odmowa;
#     - NixOS: ani jednej porady `systemctl enable|disable|start|stop` ani
#       `chsh` (grep wyjścia KAŻDEGO biegu NixOS), deklaracje zamiast komend;
#     - Fedora: zero mutacji usług, firewalld nietknięty także przy aktywnych
#       UFW i firewalld, nazwy RPM (pipewire-pulseaudio, NetworkManager),
#       działający tuned-ppd = bez instalowania drugiego menedżera profili.
#   Parytet Archa z inną wersją instalatora (np. bazą przed D7):
#     INSTALL_SERVICES_REV=<rewizja> bash tests/install-services.sh
#   — dla każdego scenariusza Archa spoza „fałszywych ✓” te same pytania
#   i te same wywołania atrap (po odjęciu odczytów is-enabled/is-active,
#   które D7 dodaje), a dla sukcesów także to samo wyjście.
#   INSTALL_SERVICES_SRC=<plik> — testuj inny install.sh (np. bazę: czerwień).
#   Bez roota, bez sieci, zapisy wyłącznie pod $T (asercja: nic nowego w /).
#   Uruchom: bash tests/install-services.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111,SC2154  # check() robi eval (zmienne żyją w eval, o_/c_/r_/s_ z eval w parytecie); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="${INSTALL_SERVICES_SRC:-$REPO/install/install.sh}"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
# D7F R3: cały pakiet w przestrzeni nazw z overlayem (zapisy poza $T wykrywalne, host nietknięty).
test_isolate "$REPO/tests/install-services.sh" "$@"
ROOT_BEFORE="$(find / -mindepth 1 -maxdepth 1 -printf "%f\n" | LC_ALL=C sort)"
T="$(mktemp -d)" && [[ -n "$T" && -d "$T" && "$T" != / ]] || { echo "mktemp -d nie zadziałał — przerywam bez zapisu"; exit 1; }
trap 'rm -rf "${T:?}"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# cut_step <plik źródłowy> <wzorzec początku> <wzorzec końca> <cel> — [początek, koniec)
cut_step() {
    local s e
    s=$(grep -n -m1 -- "$2" "$1" | cut -d: -f1)
    e=$(grep -n -m1 -- "$3" "$1" | cut -d: -f1)
    [[ -n "$s" && -n "$e" && "$e" -gt "$s" ]] || return 1
    sed -n "${s},$((e-1))p" "$1" > "$4"
}
# cut_all <install.sh> <katalog> — wycinki platform/step6/step8l/step10.
# [8l]: od znacznika „>>> 8l” (albo, w starszych wersjach, od odczytu
# systemowego mpd.service) do `if command -v ncmpcpp`, bez ostatniego `fi`
# (zamyka zewnętrzny warunek „mpd jest zainstalowany”).
cut_all() {
    local src="$1" d="$2" start
    mkdir -p "${d:?}"
    cut_step "$src" '^# ─── PLATFORMA' '^# ─── 1\. WELCOME' "$d/platform.sh" || return 1
    cut_step "$src" '^# ─── 6\. DEVICE DETECTION' '^# ─── 6\.5 DRIVERS' "$d/step6.sh" || return 1
    cut_step "$src" '^# ─── 10\. UFW' '^# ─── 11\. DONE' "$d/step10.sh" || return 1
    start='^    # >>> 8l'
    grep -q -- "$start" "$src" || start='^    if systemctl is-enabled --quiet mpd.service'
    cut_step "$src" "$start" '^if command -v ncmpcpp' "$d/step8l.raw" || return 1
    local last
    last=$(grep -n '^fi$' "$d/step8l.raw" | tail -1 | cut -d: -f1)
    [[ -n "$last" ]] || return 1
    sed "${last}d" "$d/step8l.raw" > "$d/step8l.sh"
}

echo "== wycinki"
check "wycinki z install.sh znalezione" 'cut_all "$INST" "${T:?}/cur"'
for f in platform step6 step8l step10; do
    check "wycinek $f: składnia poprawna" '[[ -s "$T/cur/$f.sh" ]] && bash -n "$T/cur/$f.sh"'
done
REV="${INSTALL_SERVICES_REV:-}"
if [[ -n "$REV" ]]; then
    git -C "$REPO" show "$REV:install/install.sh" > "${T:?}/install.rev.sh" || { echo "  ✗ brak install.sh w $REV"; exit 1; }
    check "wycinki z $REV znalezione" 'cut_all "$T/install.rev.sh" "$T/rev"'
fi

# ─── atrapy ──────────────────────────────────────────────────────────────────
# systemctl: stan w $ST/<system|user>/<jednostka bez .service>.{enabled,active}.
#   MOCK_ENABLE=ok (domyślnie: enable [--now] ustawia enabled [+active]) |
#     fail (kod 1, nic) | noop (kod 0, nic — „kod 0 bez efektu”) |
#     dead (kod 0, enabled, ale nie active);
#   MOCK_ENABLE_SKIP="<jednostki>" — tych enable nie rusza (częściowy start);
#   MOCK_NOBUS=1 — każde wywołanie --user: brak busa (kod 1).
mkdir -p "${T:?}/bin"
cat > "${T:?}/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
echo "systemctl $*" >> "${CALLS:?}"
scope=system; args=(); now=0
for a in "$@"; do case "$a" in --user) scope=user ;; --quiet|-q) ;; --now) now=1 ;; *) args+=("$a") ;; esac; done
if [[ "$scope" == user && -n "${MOCK_NOBUS:-}" ]]; then
    echo "Failed to connect to bus: No medium found" >&2; exit 1
fi
d="${ST:?}/$scope"; mkdir -p "$d"
cmd="${args[0]:-}"; units=("${args[@]:1}"); units=("${units[@]%.service}")
case "$cmd" in
    # show -p Listen --value <gniazdo>: MOCK_LISTEN (jak systemd: „adres (Stream)”),
    # MOCK_SHOW_RC — kod odczytu (D7F R5).
    show) [[ -n "${MOCK_LISTEN:-}" ]] && printf '%s\n' "$MOCK_LISTEN"; exit "${MOCK_SHOW_RC:-0}" ;;
    is-enabled) [[ -e "$d/${units[0]}.enabled" ]]; exit ;;
    is-active)  [[ -e "$d/${units[0]}.active" ]]; exit ;;
    enable)
        case "${MOCK_ENABLE:-ok}" in
            fail) echo "Failed to enable unit: Unit ${units[0]} does not exist" >&2; exit 1 ;;
            noop) exit 0 ;;
        esac
        for u in "${units[@]}"; do
            [[ " ${MOCK_ENABLE_SKIP:-} " == *" $u "* || " ${MOCK_ENABLE_SKIP:-} " == *" $u.service "* ]] && continue
            : > "$d/$u.enabled"
            [[ $now -eq 1 && "${MOCK_ENABLE:-ok}" == ok ]] && : > "$d/$u.active"
        done
        exit 0 ;;
esac
exit 0
MOCK
# Pozostałe atrapy: zapis wywołania; sudo wykonuje dalej; ufw aktywna
# z MOCK_UFW_ACTIVE; rpm -q: zainstalowane tylko nazwy z MOCK_RPM_INSTALLED.
for c in sudo pacman yay dnf rpm ufw chsh; do
    cat > "${T:?}/bin/$c" <<'MOCK'
#!/usr/bin/env bash
name="${0##*/}"
echo "$name $*" >> "${CALLS:?}"
case "$name" in
    sudo) [[ "${1:-}" == -k ]] && exit 0; exec "$@" ;;
    # MOCK_UFW_FAIL=<podkomenda> — ta podkomenda ufw kończy się kodem 1 (osobne awarie UFW, R4).
    ufw)  [[ -n "${MOCK_UFW_FAIL:-}" && "${1:-}" == "$MOCK_UFW_FAIL" ]] && exit 1
          [[ "${1:-}" == status && -n "${MOCK_UFW_ACTIVE:-}" ]] && printf 'Status: active\nDefault: deny (incoming), allow (outgoing)\n' ;;
    rpm)
        [[ "${1:-}" == -q ]] || exit 2; shift
        [[ "${1:-}" == --qf ]] && shift 2
        rc=0
        for p in "$@"; do
            if [[ " ${MOCK_RPM_INSTALLED:-} " == *" $p "* ]]; then echo "$p"
            else echo "package $p is not installed"; rc=1; fi
        done
        exit "$rc" ;;
esac
exit 0
MOCK
done
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" CALLS="$T/calls" ST="$T/state"

# Atrapa repo: biblioteka i mapa prawdziwe, pomocniki BT/VB jako szpiedzy,
# profile-get.sh wypisuje MOCK_PROFILE.
A="$T/archenemy"
mkdir -p "$A/install/lib" "$A/packages" "$A/scripts/waybar" "$A/data"
cp "$REPO/install/lib/pkg.sh" "$A/install/lib/"
cp "$REPO/packages/platform-map.tsv" "$A/packages/"
for n in bluetooth-installation virtualbox-installation asus-installation; do
    # MOCK_HELPER_RC — kod wyjścia pomocnika (kontrakt 0/2/inne, parytet R4).
    printf '#!/usr/bin/env bash\necho "RUN %s" >> "$CALLS"\nexit "${MOCK_HELPER_RC:-0}"\n' "$n" > "$A/install/$n.sh"
done
printf '#!/usr/bin/env bash\necho "${MOCK_PROFILE:-balanced}"\n' > "$A/scripts/waybar/profile-get.sh"
chmod +x "$A/install/"*.sh "$A/scripts/waybar/profile-get.sh"

OS="$T/os"; mkdir -p "$OS"
printf 'NAME="Arch Linux"\nID=arch\n'                    > "$OS/arch"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=44\n' > "$OS/fedora"
printf 'NAME=NixOS\nID=nixos\nVERSION_ID=26.05\n'        > "$OS/nixos"

# svc <system|user> <jednostka> <enabled|active|both> — stan przed biegiem.
svc() {
    mkdir -p "${ST:?}/$1"
    case "$3" in
        enabled) : > "$ST/$1/$2.enabled" ;;
        active)  : > "$ST/$1/$2.active" ;;
        both)    : > "$ST/$1/$2.enabled"; : > "$ST/$1/$2.active" ;;
    esac
}
# run <platforma[+skip]> <wycinek> <stdin> [katalog wycinków] — wynik: $out,
# $rest (nieprzeczytane stdin), $calls, $done_/$skipped (podsumowanie).
# Stan atrapy ($ST) ustawia wołający PRZED run i zostaje do reset.
run() {
    local plat="${1%+skip}" skip=0 d="${4:-$T/cur}" all
    [[ "$1" == *+skip ]] && skip=1
    : > "$CALLS"; rm -f "$A/data/hardware.dat"
    printf '%b' "$3" > "$T/stdin"
    mkdir -p "$ST"
    all="$( { ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$OS/$plat" ARCHENEMY_OSTREE_MARKER="$T/no-ostree" \
        ARCHENEMY_DIR="$A" DATA_DIR="$A/data" CONFIG_DIR="$T/home/.config" SKIP_PACKAGES="$skip" \
        GREEN='' NC='' YELLOW='' RED='' CYAN='' BLUE='' \
        bash -c 'set -uo pipefail; declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=()
                 # read -p bez terminala nie pokazuje pytania — zapisujemy je sami.
                 read() { if [[ "${1:-}" == -rp ]]; then echo "ASK: $2" >&2; builtin read -r "${@:3}"; else builtin read "$@"; fi; }
                 source "$1"; source "$2"
                 printf "DONE=%s\n" "${SUMMARY_DONE[@]}" > "$3"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}" >> "$3"' \
        _ "$d/platform.sh" "$d/$2.sh" "$T/summary"
        echo "@@END@@"; cat; } < "$T/stdin" 2>&1 )"
    out="${all%%@@END@@*}"
    rest="${all#*@@END@@}"; rest="${rest#$'\n'}"
    calls="$(<"$CALLS")"
    done_="$(grep '^DONE=.' "$T/summary")"
    skipped="$(grep '^SKIPPED=.' "$T/summary")"
}
reset() { rm -rf "${ST:?}"; unset MOCK_LISTEN MOCK_SHOW_RC MOCK_ENABLE MOCK_ENABLE_SKIP MOCK_NOBUS MOCK_UFW_ACTIVE MOCK_RPM_INSTALLED MOCK_PROFILE MOCK_HELPER_RC MOCK_UFW_FAIL; }
called() { grep -qxF -- "$1" <<< "$calls"; }
# Mutacje usług i systemu; `sudo -k` z pułapki bloku platformy (Arch, Fedora
# bez flagi) to nie mutacja — NixOS i Fedora z flagą nie wołają sudo wcale
# (sprawdza no_sudo).
mutations() { grep -vxE 'sudo -k|sudo ufw status( verbose)?' <<< "$calls" | grep -E '^(sudo |pacman -S|yay|dnf|ufw (default|enable|disable|allow|deny)|chsh)|^systemctl( --user)? (enable|disable|start|stop|restart|mask|unmask|reload)( |$)'; }
no_sudo() { ! grep -q '^sudo' <<< "$calls"; }
no_mutation() { [[ -z "$(mutations)" ]]; }
# NixOS: żadnej imperatywnej porady usług ani powłoki w wyjściu (D7).
nix_clean() { ! grep -qE 'systemctl( --user)? (enable|disable|start|stop)|chsh' <<< "$out"; }
NIX_RUNS=0; NIX_DIRTY=""
nix_run() {   # nix_run <wycinek> <stdin> — bieg NixOS + grep wyjścia
    run nixos "$1" "$2"
    NIX_RUNS=$((NIX_RUNS + 1))
    nix_clean && no_mutation && no_sudo || NIX_DIRTY+=" $1#$NIX_RUNS"
}

# ─── [6] power-profiles-daemon ───────────────────────────────────────────────
echo "== [6] power-profiles-daemon"
reset; run arch step6 '3\n'
check "Arch: enable --now, potem odczyt is-enabled i is-active" \
    'called "sudo systemctl enable --now power-profiles-daemon" && grep -A2 -x "sudo systemctl enable --now power-profiles-daemon" <<< "$calls" | grep -q "is-enabled --quiet power-profiles-daemon" && called "systemctl is-active --quiet power-profiles-daemon"'
check "Arch: działa — cisza, bez wpisu PPD w podsumowaniu" '[[ "$out" != *"power-profiles-daemon is"* ]] && ! grep -q "power-profiles-daemon" <<< "$skipped"'
for mode in fail noop dead; do
    reset; MOCK_ENABLE=$mode run arch step6 '3\n'
    check "Arch, enable $mode: ostrzeżenie z poleceniem, wpis w podsumowaniu, bez ✓ PPD" \
        '[[ "$out" == *"⚠ power-profiles-daemon is"*"systemctl status power-profiles-daemon"* && "$out" != *"✓ power-profiles"* ]] && grep -q "^SKIPPED=power-profiles-daemon — " <<< "$skipped"'
done
reset; MOCK_ENABLE=dead run arch step6 '3\n'
check "Arch, enabled-but-dead: wpis „enabled but not running”" 'grep -q "^SKIPPED=power-profiles-daemon — enabled but not running" <<< "$skipped"'
reset; run arch+skip step6 '3\n'
check "Arch+skip: bez pacmana, usługa włączona i sprawdzona" '! grep -q "^pacman" <<< "$calls" && called "systemctl is-active --quiet power-profiles-daemon"'
reset; svc system power-profiles-daemon both; run fedora step6 '3\n'
check "Fedora, PPD enabled+active: ✓ po odczycie, zero mutacji" '[[ "$out" == *"✓ power-profiles-daemon enabled and running"* ]] && no_mutation'
reset; svc system power-profiles-daemon enabled; run fedora step6 '3\n'
check "Fedora, PPD enabled-but-dead: ostrzeżenie, wpis, bez ✓" '[[ "$out" == *"power-profiles-daemon is enabled but not running"* && "$out" != *"✓ power-profiles"* ]] && grep -q "^SKIPPED=power-profiles-daemon — enabled but not running" <<< "$skipped" && no_mutation'
reset; svc system tuned-ppd both; MOCK_RPM_INSTALLED="tuned-ppd" run fedora step6 '3\n'
check "Fedora, działa tuned-ppd: rozpoznany, bez instalowania drugiego menedżera" \
    '[[ "$out" == *"tuned-ppd (Fedora'"'"'s default) is running"* && "$out" == *"dnf swap tuned-ppd power-profiles-daemon"* ]] && ! grep -qE "dnf install.*power-profiles-daemon" <<< "$out" && no_mutation'
check "Fedora, tuned-ppd: wpis w podsumowaniu (opcjonalna podmiana)" 'grep -q "^SKIPPED=Power profiles: tuned-ppd kept" <<< "$skipped"'
reset; MOCK_RPM_INSTALLED="tuned-ppd" run fedora step6 '3\n'
check "Fedora, tuned-ppd zainstalowany, nie działa: polecenie sprawdzenia tuned-ppd, bez dnf install PPD" \
    '[[ "$out" == *"systemctl status tuned-ppd"* ]] && ! grep -qE "dnf install.*power-profiles-daemon" <<< "$out" && no_mutation'
reset; MOCK_RPM_INSTALLED="power-profiles-daemon" run fedora step6 '3\n'
check "Fedora, PPD zainstalowany, wyłączony: tylko systemctl jako porada, wpis" \
    '[[ "$out" == *"power-profiles-daemon: not done automatically on Fedora — sudo systemctl enable --now power-profiles-daemon"* ]] && grep -q "^SKIPPED=power-profiles-daemon — not done on Fedora" <<< "$skipped" && no_mutation'
reset; run fedora step6 '3\n'
check "Fedora, brak PPD i tuned-ppd: dnf install power-profiles-daemon jako porada" \
    '[[ "$out" == *"sudo dnf install --repo=fedora --repo=updates power-profiles-daemon && sudo systemctl enable --now power-profiles-daemon"* ]] && no_mutation'
reset; nix_run step6 '3\n'
check "NixOS: services.power-profiles-daemon.enable, wpis, zero mutacji" '[[ "$out" == *"services.power-profiles-daemon.enable = true;"* ]] && grep -q "^SKIPPED=power-profiles-daemon — not done on NixOS" <<< "$skipped" && no_mutation'
reset; svc system power-profiles-daemon both; nix_run step6 '3\n'
check "NixOS, zadeklarowany PPD działa: ✓ po odczycie, bez porady" '[[ "$out" == *"✓ power-profiles-daemon enabled and running"* && "$out" != *"services.power-profiles-daemon.enable"* ]]'

# ─── [8l] usługa mpd ─────────────────────────────────────────────────────────
echo "== [8l] usługa mpd"
reset; run arch step8l 'y\n'
check "Arch, zgoda: enable --now, odczyt enabled+active, ✓ i DONE" \
    'called "systemctl --user enable --now mpd.service" && called "systemctl --user is-active --quiet mpd.service" && [[ "$out" == *"✓ mpd.service (user) enabled"* ]] && grep -q "^DONE=mpd user service enabled" <<< "$done_"'
for mode in fail noop dead; do
    reset; MOCK_ENABLE=$mode run arch step8l 'y\n'
    check "Arch, zgoda, enable $mode: ✗ z poleceniem, wpis, bez ✓ i DONE" \
        '[[ "$out" == *"✗ "*"journalctl --user -u mpd"* && "$out" != *"✓ mpd"* && -z "$done_" ]] && grep -q "^SKIPPED=mpd user service (" <<< "$skipped"'
done
reset; MOCK_NOBUS=1 run arch step8l 'y\n'
check "Arch, brak busa użytkownika: zgoda → ✗ i wpis, bez ✓" '[[ "$out" == *"✗ systemctl --user enable --now mpd.service failed"* && -z "$done_" ]] && grep -q "^SKIPPED=mpd user service (enable failed" <<< "$skipped"'
reset; run arch step8l 'n\n'
check "Arch, odmowa: bez enable, wpis „your choice”" '! grep -q " enable " <<< "$calls" && grep -q "^SKIPPED=mpd user service not enabled (your choice)" <<< "$skipped" && [[ -z "$done_" ]]'
reset; svc user mpd both; run arch step8l 'y\n'
check "Arch, usługa użytkownika enabled+active: ✓ already, bez pytania i zmian" '[[ "$out" == *"✓ mpd user service already enabled"* && "$rest" == "y" ]] && no_mutation'
reset; svc user mpd enabled; run arch step8l 'y\n'
check "Arch, usługa użytkownika enabled-but-dead: ostrzeżenie, wpis, bez ✓, bez pytania i zmian" \
    '[[ "$out" == *"mpd user service is enabled but not running — check: systemctl --user status mpd"* && "$out" != *"✓"* && "$rest" == "y" ]] && grep -q "^SKIPPED=mpd user service — enabled but not running" <<< "$skipped" && no_mutation'
for st in enabled active; do
    reset; svc system mpd "$st"; svc user mpd both; run arch step8l 'y\n'
    check "Arch, systemowy mpd $st (+ usługa użytkownika): pominięty, bez pytania i zmian" \
        '[[ "$out" == *"mpd runs as a SYSTEM service"* && "$out" != *"✓"* && "$rest" == "y" ]] && grep -q "^SKIPPED=mpd user service (system-wide mpd is enabled)" <<< "$skipped" && no_mutation'
    reset; svc user mpd.socket "$st"; svc user mpd both; run arch step8l 'y\n'
    check "Arch, gniazdo użytkownika $st: ostrzeżenie o 6600 z komendą, bez ✓ i zmian" \
        '[[ "$out" == *"mpd.socket (user) is enabled"* && "$out" == *"systemctl --user disable --now mpd.socket && systemctl --user enable --now mpd.service"* && "$out" != *"✓"* ]] && grep -q "^SKIPPED=mpd.socket listens on port 6600" <<< "$skipped" && no_mutation'
done
# D7F R5: na Fedorze i NixOS „wszystkie interfejsy” dopiero po odczycie Listen
# (home-manager domyślnie słucha na 127.0.0.1); bez odczytu — porada warunkowa.
for p in nixos fedora; do
    reset; svc user mpd.socket enabled; export MOCK_LISTEN='[::]:6600 (Stream)'
    if [[ $p == nixos ]]; then nix_run step8l ''; else run fedora step8l ''; fi
    check "$p, gniazdo na [::]:6600: ostrzeżenie o sieci z odczytanym adresem, wpis, bez zmian" \
        '[[ "$out" == *"listens on [::]:6600"*"reachable from your network"* ]] && called "systemctl --user show -p Listen --value mpd.socket" && grep -q "^SKIPPED=mpd.socket listens on \[::\]:6600" <<< "$skipped" && no_mutation'
    reset; svc user mpd.socket enabled; export MOCK_LISTEN='127.0.0.1:6600 (Stream)'
    if [[ $p == nixos ]]; then nix_run step8l ''; else run fedora step8l ''; fi
    check "$p, gniazdo na 127.0.0.1:6600: tylko lokalnie — bez „ALL interfaces”, bez ⚠ i wpisu" \
        '[[ "$out" == *"listens only locally (127.0.0.1:6600)"* && "$out" != *"ALL interfaces"* && "$out" != *"reachable from your network"* && "$out" != *"⚠ mpd.socket"* ]] && ! grep -q "^SKIPPED=mpd.socket" <<< "$skipped" && no_mutation'
    reset; svc user mpd.socket enabled; export MOCK_SHOW_RC=1
    if [[ $p == nixos ]]; then nix_run step8l ''; else run fedora step8l ''; fi
    check "$p, gniazdo bez odczytu Listen: porada warunkowa, bez twierdzenia o ekspozycji" \
        '[[ "$out" == *"could not read what it listens on"* && "$out" == *"if it shows [::]:6600 or 0.0.0.0:6600"* && "$out" != *"ALL interfaces"* ]] && grep -q "^SKIPPED=mpd.socket — check what it listens on" <<< "$skipped" && no_mutation'
done
reset; svc user mpd.socket enabled; export MOCK_LISTEN='[::]:6600 (Stream)'; nix_run step8l ''
check "NixOS, gniazdo: deklaratywne wyłączenie (startWhenNeeded / systemd.user.sockets.mpd.enable), bez komend" \
    '[[ "$out" == *"services.mpd.network.startWhenNeeded = false;"* && "$out" == *"systemd.user.sockets.mpd.enable = false;"* && "$out" == *"systemd.user.services.mpd"* ]] && grep -q "^SKIPPED=mpd.socket listens on .*NixOS" <<< "$skipped" && nix_clean && no_mutation'
reset; svc user mpd.socket enabled; export MOCK_LISTEN='127.0.0.1:6600 (Stream)'; run arch step8l 'y\n'
check "Arch: spakowany mpd.socket — ostrzeżenie jak przed D7F, bez odczytu Listen" \
    '[[ "$out" == *"listens on port 6600 on ALL interfaces"* ]] && ! called "systemctl --user show -p Listen --value mpd.socket"'
reset; nix_run step8l ''
check "NixOS, nic: deklaracja systemd.user.services.mpd na ~/.config/mpd/mpd.conf, wpis" \
    '[[ "$out" == *'"'"'${pkgs.mpd}/bin/mpd --no-daemon %h/.config/mpd/mpd.conf'"'"'* ]] && grep -q "^SKIPPED=mpd user service — not done on NixOS" <<< "$skipped" && no_mutation'
reset; svc user mpd enabled; nix_run step8l ''
check "NixOS, zadeklarowana usługa martwa: ostrzeżenie, bez ✓" '[[ "$out" == *"mpd user service is enabled but not running"* && "$out" != *"✓"* ]]'
reset; svc system mpd active; nix_run step8l ''
check "NixOS, systemowy mpd: pozostawiony" '[[ "$out" == *"mpd runs as a SYSTEM service"* ]] && no_mutation'
reset; run fedora step8l 'y\n'
check "Fedora, nic: porada systemctl --user, wpis, bez pytania i zmian" \
    '[[ "$out" == *"mpd user service: not done automatically on Fedora — systemctl --user enable --now mpd.service"* && "$rest" == "y" ]] && grep -q "^SKIPPED=mpd user service — not done on Fedora" <<< "$skipped" && no_mutation'
reset; svc user mpd.socket active; export MOCK_SHOW_RC=1; run fedora step8l ''
check "Fedora, gniazdo active, bez odczytu: polecenie odczytu Listen w poradzie, bez zmian" '[[ "$out" == *"systemctl --user show -p Listen mpd.socket"* ]] && no_mutation'
reset; svc user mpd enabled; run fedora step8l ''
check "Fedora, usługa martwa: ostrzeżenie, bez ✓" '[[ "$out" == *"mpd user service is enabled but not running"* && "$out" != *"✓"* ]] && no_mutation'

# ─── [10] zapora, NetworkManager, audio ──────────────────────────────────────
echo "== [10] zapora, NetworkManager, audio"
# Wspólne tło biegów Archa: aktywna i włączona UFW (bez pytania o nią),
# odpowiedzi kolejno: NetworkManager (gdy pyta), Bluetooth n, VirtualBox n.
arch10() { svc system ufw enabled; MOCK_UFW_ACTIVE=1 run arch step10 "$1"; }
# Działające audio = pulse (socket) i backend (pipewire.socket, wireplumber), każde enabled+active (D7F R1).
audio_ok() { svc user pipewire-pulse.socket both; svc user pipewire.socket both; svc user wireplumber both; }
reset; svc system NetworkManager both; audio_ok; arch10 'n\nn\n'
check "Arch, NM enabled+active: ✓ already, bez pytania" '[[ "$out" == *"✓ NetworkManager already enabled."* ]] && ! grep -q "^ASK: Enable NetworkManager" <<< "$out" && ! grep -q "NetworkManager" <<< "$(mutations)"'
reset; svc system NetworkManager enabled; audio_ok; arch10 'n\nn\n'
check "Arch, NM enabled-but-dead: ostrzeżenie, wpis, bez ✓, bez pytania i zmian" \
    '[[ "$out" == *"NetworkManager is enabled but not running — check: systemctl status NetworkManager"* && "$out" != *"✓ NetworkManager"* ]] && ! grep -q "^ASK: Enable NetworkManager" <<< "$out" && grep -q "^SKIPPED=NetworkManager — enabled but not running" <<< "$skipped" && [[ -z "$(mutations)" ]]'
reset; audio_ok; arch10 '\nn\nn\n'
check "Arch, NM zgoda: enable --now, odczyt enabled+active, ✓ i DONE" \
    'called "sudo systemctl enable --now NetworkManager" && called "systemctl is-active --quiet NetworkManager" && [[ "$out" == *"✓ NetworkManager enabled."* ]] && grep -q "^DONE=NetworkManager enabled" <<< "$done_"'
for mode in fail noop dead; do
    reset; audio_ok; MOCK_ENABLE=$mode arch10 '\nn\nn\n'
    check "Arch, NM enable $mode: ✗ z poleceniem, wpis, bez ✓ i DONE" \
        '[[ "$out" == *"✗ NetworkManager NOT enabled"*"systemctl status NetworkManager"* && "$out" != *"✓ NetworkManager"* ]] && ! grep -q "^DONE=NetworkManager" <<< "$done_" && grep -q "^SKIPPED=NetworkManager — enable failed" <<< "$skipped"'
done
reset; audio_ok; arch10 'n\nn\nn\n'
check "Arch, NM odmowa: bez enable, wpis" '! grep -q "enable --now NetworkManager" <<< "$calls" && grep -q "^SKIPPED=NetworkManager (network module" <<< "$skipped"'
reset; svc system NetworkManager both; audio_ok; arch10 'n\nn\n'
check "Arch, audio: socket pulse + backend enabled+active → ✓ already, bez enable" '[[ "$out" == *"✓ Audio (pipewire-pulse) already running."* ]] && ! grep -q "^systemctl --user enable" <<< "$calls" && called "systemctl --user is-active --quiet wireplumber.service"'
reset; svc system NetworkManager both; svc user pipewire-pulse both; svc user pipewire both; svc user wireplumber both; arch10 'n\nn\n'
check "Arch, audio: sama usługa pulse i usługa pipewire enabled+active → ✓" '[[ "$out" == *"✓ Audio (pipewire-pulse) already running."* ]] && ! grep -q "^SKIPPED=Audio" <<< "$skipped"'
# D7F R1 (odtworzenie proby-uslug.py): ✓ wymaga tej samej jednostki enabled+active
# i żywego backendu — na każdej platformie (gałąź stoi przed podziałem platform).
for p in arch fedora nixos; do
    reset; svc system NetworkManager both; svc system ufw enabled
    svc user pipewire-pulse.socket active; svc user pipewire-pulse enabled; svc user pipewire.socket both; svc user wireplumber both
    MOCK_UFW_ACTIVE=1 run "$p" step10 'n\nn\n'
    check "$p, audio: aktywny wyłączony socket + włączona martwa usługa → ⚠, wpis, bez ✓ i zmian" \
        '[[ "$out" != *"✓ Audio"* && "$out" == *"no unit is both enabled and running"* ]] && grep -q "^SKIPPED=Audio (pipewire-pulse) — no unit both enabled and running" <<< "$skipped" && ! grep -q "^systemctl --user enable" <<< "$calls"'
    reset; svc system NetworkManager both; svc system ufw enabled
    svc user pipewire-pulse.socket both; svc user pipewire.socket enabled; svc user wireplumber enabled
    MOCK_UFW_ACTIVE=1 run "$p" step10 'n\nn\n'
    check "$p, audio: socket pulse działa, pipewire i wireplumber martwe → ⚠ backendu, wpis, bez ✓" \
        '[[ "$out" != *"✓ Audio"* && "$out" == *"backend (pipewire, wireplumber) is not enabled and running"* ]] && grep -q "^SKIPPED=Audio — pipewire/wireplumber not enabled and running" <<< "$skipped" && called "systemctl --user is-active --quiet pipewire.socket" && ! grep -q "^systemctl --user enable" <<< "$calls"'
done
reset; svc system NetworkManager both; svc user pipewire-pulse.socket both; svc user pipewire.socket both; svc user wireplumber enabled; arch10 'n\nn\n'
check "Arch, audio: tylko wireplumber martwy → ⚠ backendu, bez ✓" '[[ "$out" != *"✓ Audio"* && "$out" == *"backend (pipewire, wireplumber)"* ]]'
reset; svc system NetworkManager both; svc user pipewire-pulse.socket active; arch10 'n\nn\n'
check "Arch, audio: socket active, nie enabled → ostrzeżenie, wpis, bez ✓ i zmian" \
    '[[ "$out" == *"Audio (pipewire-pulse) is running, but not enabled"* && "$out" != *"✓ Audio"* ]] && grep -q "^SKIPPED=Audio (pipewire-pulse) — running but not enabled" <<< "$skipped" && ! grep -q "^systemctl --user enable" <<< "$calls"'
reset; svc system NetworkManager both; arch10 'n\nn\n'
check "Arch, audio: enable --now trzech jednostek, odczyt każdej, ✓ i DONE" \
    'called "systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service" && called "systemctl --user is-active --quiet wireplumber.service" && [[ "$out" == *"✓ pipewire-pulse started."* ]] && grep -q "^DONE=Audio: pipewire-pulse started" <<< "$done_"'
for mode in noop dead; do
    reset; svc system NetworkManager both; MOCK_ENABLE=$mode arch10 'n\nn\n'
    check "Arch, audio enable $mode (kod 0 bez efektu): ostrzeżenie, wpis, bez ✓ i DONE" \
        '[[ "$out" == *"are not all enabled and running"* && "$out" != *"✓ pipewire"* ]] && ! grep -q "^DONE=Audio" <<< "$done_" && grep -q "^SKIPPED=audio: pipewire-pulse not running after enable" <<< "$skipped"'
done
reset; svc system NetworkManager both; MOCK_ENABLE_SKIP="wireplumber.service" arch10 'n\nn\n'
check "Arch, audio częściowo (wireplumber nie wstał): ostrzeżenie, bez ✓" '[[ "$out" == *"are not all enabled and running"* && "$out" != *"✓ pipewire"* ]] && ! grep -q "^DONE=Audio" <<< "$done_"'
reset; svc system NetworkManager both; MOCK_ENABLE=fail arch10 'n\nn\n'
check "Arch, audio enable fail: dotychczasowe „log out and back in”, wpis" '[[ "$out" == *"Could not start pipewire-pulse"* ]] && grep -q "^SKIPPED=audio: pipewire-pulse (re-login required)" <<< "$skipped"'
reset; svc system NetworkManager both; MOCK_NOBUS=1 arch10 'n\nn\n'
check "Arch, audio bez busa użytkownika: bez ✓, wpis" '[[ "$out" != *"✓ pipewire"* && "$out" != *"✓ Audio"* ]] && grep -q "^SKIPPED=audio: pipewire-pulse" <<< "$skipped"'

for p in fedora fedora+skip; do
    reset; svc system firewalld both; svc system ufw both; MOCK_UFW_ACTIVE=1 run "$p" step10 'y\ny\ny\ny\n'
    check "$p, aktywne UFW i firewalld: zero ufw/systemctl mutujących, firewalld nietknięty" \
        'no_mutation && ! grep -q "^ufw" <<< "$calls" && [[ "$out" == *"Fedora uses firewalld, left as it is"* ]] && ! grep -qiE "(disable|stop|mask).*firewalld|firewalld.*(disable|stop)" <<< "$out" && [[ "$rest" == "$(<"$T/stdin")" ]]'
done
reset; run fedora step10 ''
check "Fedora, nic: porady z nazwami RPM (NetworkManager, pipewire-pulseaudio), wpisy, zero mutacji" \
    '[[ "$out" == *"sudo dnf install --repo=fedora --repo=updates NetworkManager && sudo systemctl enable --now NetworkManager.service"* && "$out" == *"pipewire-pulseaudio wireplumber, then: systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service"* ]] && grep -q "^SKIPPED=NetworkManager — not done on Fedora" <<< "$skipped" && grep -q "^SKIPPED=Audio (pipewire-pulse) — not done on Fedora" <<< "$skipped" && no_mutation'
check "Fedora: Bluetooth z bluez, dbus-tools, bluetooth.service, bluetui i flagą ikony" \
    '[[ "$out" == *"sudo dnf install bluez dbus-tools && sudo systemctl enable --now bluetooth.service"* && "$out" == *"github.com/pythops/bluetui"* && "$out" == *"data/bluetooth-enabled.dat"* ]]'
reset; svc system NetworkManager enabled; svc user pipewire-pulse.socket both; run fedora step10 ''
check "Fedora, NM enabled-but-dead: ostrzeżenie, bez ✓, zero mutacji" '[[ "$out" == *"NetworkManager is enabled but not running"* && "$out" != *"✓ NetworkManager"* ]] && no_mutation'
reset; svc system ufw both; MOCK_UFW_ACTIVE=1 nix_run step10 'y\ny\ny\ny\n'
check "NixOS, aktywna UFW: networking.firewall, opcje NM/pipewire/bluetooth, zero mutacji, bez pytań" \
    '[[ "$out" == *"networking.firewall"* && "$out" == *"networking.networkmanager.enable = true;"* && "$out" == *"services.pipewire.pulse.enable = true;"* && "$out" == *"hardware.bluetooth.enable = true;"* && "$out" == *"data/bluetooth-enabled.dat"* && "$rest" == "$(<"$T/stdin")" ]] && no_mutation'
reset; svc system NetworkManager both; audio_ok; nix_run step10 ''
check "NixOS, zadeklarowane usługi działają: ✓ po odczycie, bez porad i wpisów sieci/audio" \
    '[[ "$out" == *"✓ NetworkManager already enabled."* && "$out" == *"✓ Audio (pipewire-pulse) already running."* ]] && ! grep -qE "^SKIPPED=(NetworkManager|Audio)" <<< "$skipped"'
reset; svc system NetworkManager enabled; svc user pipewire-pulse.socket active; nix_run step10 ''
check "NixOS, NM martwy i audio niewłączone: ostrzeżenia, bez ✓" '[[ "$out" == *"NetworkManager is enabled but not running"* && "$out" == *"Audio (pipewire-pulse) is running, but not enabled"* && "$out" != *"✓"* ]]'
reset; MOCK_NOBUS=1 nix_run step10 ''
check "NixOS, brak busa użytkownika: opcje NixOS jako porada, bez ✓ audio" '[[ "$out" == *"services.pipewire.pulse.enable = true;"* && "$out" != *"✓ Audio"* ]]'

echo "== NixOS: grep wyjścia każdego biegu"
check "$NIX_RUNS biegów NixOS: ani razu systemctl enable/disable/start/stop ani chsh w poradach, zero mutacji${NIX_DIRTY:+ (brudne:$NIX_DIRTY)}" '[[ $NIX_RUNS -ge 10 && -z "$NIX_DIRTY" ]]'

# ─── parytet Archa z rewizją ─────────────────────────────────────────────────
# Scenariusze <nazwa>|<wycinek>|<stdin>|<stan>|<env>|<wyjście: same|diff>
# poza „fałszywymi ✓”. Stan: lista „scope:jednostka:stan” przez svc().
if [[ -n "$REV" ]]; then
    echo "== parytet Archa z $REV"
    SCEN=(
        "PPD działa|step6|3\n|||same"
        "PPD awaria enable|step6|3\n||MOCK_ENABLE=fail|diff"
        "Arch+skip PPD|step6|3\n|||same"
        "mpd zgoda, sukces|step8l|y\n|||same"
        "mpd zgoda, awaria enable|step8l|y\n||MOCK_ENABLE=fail|same"
        "mpd zgoda, brak busa|step8l|y\n||MOCK_NOBUS=1|same"
        "mpd odmowa|step8l|n\n|||same"
        "mpd usługa użytkownika działa|step8l|y\n|user:mpd:both||same"
        "mpd systemowy enabled|step8l|y\n|system:mpd:enabled||same"
        "mpd systemowy active + użytkownika|step8l|y\n|system:mpd:active user:mpd:both||same"
        "mpd gniazdo enabled|step8l|y\n|user:mpd.socket:enabled||same"
        "mpd gniazdo active|step8l|y\n|user:mpd.socket:active||same"
        "[10] NM działa, audio działa|step10|n\nn\n|system:ufw:enabled system:NetworkManager:both user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both|MOCK_UFW_ACTIVE=1|same"
        "[10] sam socket pulse, backend martwy (naprawione fałszywe ✓)|step10|n\nn\n|system:ufw:enabled system:NetworkManager:both user:pipewire-pulse.socket:both|MOCK_UFW_ACTIVE=1|diff"
        "[10] aktywny wyłączony socket + martwa usługa (naprawione fałszywe ✓)|step10|n\nn\n|system:ufw:enabled system:NetworkManager:both user:pipewire-pulse.socket:active user:pipewire-pulse:enabled user:pipewire.socket:both user:wireplumber:both|MOCK_UFW_ACTIVE=1|diff"
        "[10] sama usługa pulse działa|step10|n\nn\n|system:ufw:enabled system:NetworkManager:both user:pipewire-pulse:both user:pipewire:both user:wireplumber:both|MOCK_UFW_ACTIVE=1|same"
        "[10] Bluetooth i VirtualBox: zgoda|step10|y\ny\n|system:ufw:enabled system:NetworkManager:both user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both|MOCK_UFW_ACTIVE=1|same"
        "[10] Bluetooth i VirtualBox: pomocniki kod 2|step10|y\ny\n|system:ufw:enabled system:NetworkManager:both user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both|MOCK_UFW_ACTIVE=1 MOCK_HELPER_RC=2|same"
        "[10] Bluetooth i VirtualBox: pomocniki zawodzą|step10|y\ny\n|system:ufw:enabled system:NetworkManager:both user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both|MOCK_UFW_ACTIVE=1 MOCK_HELPER_RC=1|same"
        "[10] UFW zgoda, awaria default|step10|y\nn\nn\n|system:NetworkManager:both user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both|MOCK_UFW_FAIL=default|same"
        "[10] UFW zgoda, status nieaktywny po enable|step10|y\nn\nn\n|system:NetworkManager:both user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both||same"
        "[10] UFW zgoda, awaria enable|step10|y\nn\nn\n|system:NetworkManager:both user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both|MOCK_UFW_FAIL=enable|same"
        "[10] UFW zgoda, awaria systemctl enable ufw|step10|y\nn\nn\n|system:NetworkManager:both user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both|MOCK_UFW_ACTIVE=1 MOCK_ENABLE=fail|same"
        "[6] ASUS, pomocnik 0|step6|1\n|||same"
        "[6] ASUS, pomocnik 2 (restart)|step6|1\n||MOCK_HELPER_RC=2|same"
        "[6] ASUS, pomocnik zawodzi|step6|1\n||MOCK_HELPER_RC=1|same"
        "[6] HP Omen|step6|2\n|||same"
        "[10] NM zgoda, audio enable|step10|\nn\nn\n|system:ufw:enabled|MOCK_UFW_ACTIVE=1|same"
        "[10] NM awaria enable, audio awaria|step10|\nn\nn\n|system:ufw:enabled|MOCK_UFW_ACTIVE=1 MOCK_ENABLE=fail|diff"
        "[10] NM odmowa|step10|n\nn\nn\n|system:ufw:enabled user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both|MOCK_UFW_ACTIVE=1|same"
        "[10] UFW pytanie, zgoda|step10|y\nn\nn\n|system:NetworkManager:both user:pipewire-pulse.socket:both user:pipewire.socket:both user:wireplumber:both||same"
        "[10] UFW odmowa, brak busa|step10|n\nn\nn\n|system:NetworkManager:both|MOCK_NOBUS=1|same"
    )
    # Dozwolona treść różnicy wyjścia/podsumowania w scenariuszach „diff”
    # (R4, przegląd D7: sama liczba wierszy niczego nie dowodzi). Zero różnic
    # też przechodzi — wobec 0a3ca91 PPD i NM już są po D7.
    declare -A DIFF_OK=(
        ["PPD awaria enable"]='power-profiles-daemon'
        ["[10] NM awaria enable, audio awaria"]='NetworkManager'
        ["[10] sam socket pulse, backend martwy (naprawione fałszywe ✓)"]='Audio'
        ["[10] aktywny wyłączony socket + martwa usługa (naprawione fałszywe ✓)"]='Audio'
    )
    # calls_parity <baza> <bieżące> — wywołania bazy są podciągiem bieżących
    # (ta sama kolejność, nic nie usunięte ani przestawione), a nadwyżka to
    # wyłącznie odczyty stanu `systemctl [--user] is-enabled|is-active --quiet`
    # (R4: dawny filtr usuwał odczyty po obu stronach i mógł ukryć zmianę).
    calls_parity() {
        local -a r c; local i=0 j=0
        mapfile -t r <<< "$1"; mapfile -t c <<< "$2"
        while (( j < ${#c[@]} )); do
            if (( i < ${#r[@]} )) && [[ "${c[j]}" == "${r[i]}" ]]; then i=$((i + 1))
            elif [[ ! "${c[j]}" =~ ^systemctl\ (--user\ )?is-(enabled|active)\ --quiet\  ]]; then return 1
            fi
            j=$((j + 1))
        done
        (( i == ${#r[@]} ))
    }
    # diff_only <wzorzec> <baza> <bieżące> — każdy różniący się wiersz pasuje do wzorca.
    diff_only() { ! diff <(echo "$2") <(echo "$3") | grep '^[<>]' | grep -vE -- "$1" | grep -q .; }
    prompts() { grep '^ASK: ' <<< "$1"; }
    for sc in "${SCEN[@]}"; do
        IFS='|' read -r name step input states envs outmode <<< "$sc"
        plat=arch; [[ "$name" == Arch+skip* ]] && plat=arch+skip
        for side in cur rev; do
            reset
            for s in $states; do IFS=: read -r a b c <<< "$s"; svc "$a" "$b" "$c"; done
            [[ -n "$envs" ]] && eval "export $envs"
            run "$plat" "$step" "$input" "$T/$side"
            eval "o_$side=\$out c_$side=\$calls r_$side=\$rest s_$side=\$(<\"\$T/summary\")"
            for e in $envs; do unset "${e%%=*}"; done
        done
        check "parytet $name: te same pytania, ta sama reszta stdin" '[[ "$(prompts "$o_cur")" == "$(prompts "$o_rev")" && "$r_cur" == "$r_rev" ]]'
        check "parytet $name: wywołania bazy w tej samej kolejności, nadwyżka tylko z odczytów stanu" 'calls_parity "$c_rev" "$c_cur"'
        if [[ "$outmode" == same ]]; then
            check "parytet $name: to samo wyjście i podsumowanie" '[[ "$o_cur" == "$o_rev" && "$s_cur" == "$s_rev" ]]'
        else
            pat="${DIFF_OK[$name]:?brak wzorca różnicy dla $name}"
            check "parytet $name: różnice wyjścia i podsumowania tylko w wierszach „$pat” ($(diff <(echo "$o_rev") <(echo "$o_cur") | grep -c '^[<>]') wierszy)" \
                'diff_only "$pat" "$o_rev" "$o_cur" && diff_only "$pat" "$s_rev" "$s_cur"'
        fi
    done
    reset
fi

# D7F R3: żadnej zmiany poza $T w nakrytych katalogach (także głęboko: /tmp/<cudzy>/…, /root/…).
if escaped="$(test_escapes "$T")"; then ok "zero zapisów poza \$T w: $(test_isolation_dirs)"
elif [[ $? == 2 ]]; then echo "  – izolacja niedostępna (unshare/overlay): sprawdzane tylko nazwy w /"
else fail "zapisy poza \$T: ${escaped//$'\n'/ }"; fi
root_new="$(comm -13 <(echo "$ROOT_BEFORE") <(find / -mindepth 1 -maxdepth 1 -printf "%f\n" | LC_ALL=C sort))"
check "żadnych nowych plików w / po biegu${root_new:+: ${root_new//$'\n'/ }}" '[[ -z "$root_new" ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
