#!/usr/bin/env bash
# =============================================
#   archenemy - tests/runtime-platforms.sh
#   Porady runtime poza instalatorem per platforma (D8) — procesy startowane
#   później z Super+A albo z Hyprlanda, więc platforma to jawny os-release
#   (ARCHENEMY_OS_RELEASE przy ARCHENEMY_TEST=1), nigdy odziedziczone
#   PLATFORM/PKG_ROUTE (test je podstawia jako „arch”, żeby to wykazać):
#     - mysz (Super+A → [m]): porada sprzętowego DPI bez ratbagctl
#       (Arch: dotychczasowy tekst; Fedora: RPM libratbag-ratbagd z mapy;
#       NixOS: services.ratbagd.enable), emulacja zostaje, zero instalacji;
#     - workspace-orphan-guard: JEDNO powiadomienie mówiące, czego brak —
#       socat (porada per platforma) albo gniazda zdarzeń Hyprlanda (socat
#       jest) — sonda co 2 s i wyjście po 5 nieudanych odczytach Hyprlanda;
#     - odbiorcy runtime: każdy aktywny rice (także yin i yang) woła wspólne TUI
#       Super+A (→ [h]/[m]/[u]) i wspólne workspaces.lua (guard).
#   Opcje: RUNTIME_PLATFORMS_REV=<rewizja> — scenariusze Archa także na
#   kodzie z rewizji, porównanie wyjścia/powiadomień i wywołań;
#   RUNTIME_PLATFORMS_SRC=<rewizja> — badany kod z rewizji (dowód czerwieni).
#   Aktualizator (porady i zakres ostrzeżeń): tests/update-archenemy.sh.
#   Uruchom: bash tests/runtime-platforms.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval (zmienne żyją w eval); atrapy to dosłowny kod
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
test_isolate "$REPO/tests/runtime-platforms.sh" "$@"   # D7F R3: zapisy poza $T wykrywalne
# shellcheck source=tests/lib/timing.sh
source "$REPO/tests/lib/timing.sh"   # limity harnessu × ARCHENEMY_TEST_TIME_SCALE (tests/README-timing.md)
T="$(mktemp -d)" && [[ -n "$T" && -d "$T" && "$T" != / ]] || exit 1
trap 'rm -rf "${T:?}"' EXIT
test_environment_init "$T" || exit 1
test_timing_init "$T"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

SRC="$REPO"
if [[ -n "${RUNTIME_PLATFORMS_SRC:-}" ]]; then
    SRC="$T/src"; mkdir -p "$SRC"
    git -C "$REPO" archive "$RUNTIME_PLATFORMS_SRC" scripts install packages | tar -x -C "$SRC" || exit 1
    echo "  (badany kod z rewizji $RUNTIME_PLATFORMS_SRC)"
fi
BASE=""
if [[ -n "${RUNTIME_PLATFORMS_REV:-}" ]]; then
    BASE="$T/base"; mkdir -p "$BASE"
    git -C "$REPO" archive "$RUNTIME_PLATFORMS_REV" scripts install packages | tar -x -C "$BASE" || exit 1   # od D8 skrypty czytają install/lib/pkg.sh
    echo "  (parytet Archa z rewizją $RUNTIME_PLATFORMS_REV)"
fi

mkdir -p "${T:?}/os" "${T:?}/bin" "${T:?}/gbin" "${T:?}/sbin"
printf 'ID=arch\n' > "$T/os/arch"
printf 'ID=endeavouros\nID_LIKE=arch\n' > "$T/os/endeavouros"
printf 'ID=fedora\nVERSION_ID=44\n' > "$T/os/fedora"
printf 'ID=nixos\n' > "$T/os/nixos"
printf 'ID=ubuntu\n' > "$T/os/ubuntu"
export ARCHENEMY_TEST=1 ARCHENEMY_OSTREE_MARKER="$T/no-ostree" CALLS="$T/calls"
# Odziedziczone zmienne instalatora nie mogą wybierać platformy.
export PLATFORM=arch PKG_ROUTE=arch

# Szpiedzy: każde polecenie, które mogłoby instalować albo włączać usługę.
for c in sudo pacman yay dnf rpm systemctl nix-env nix nixos-rebuild; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "${CALLS:?}"\nexit 0\n' "$c" > "$T/bin/$c"
done
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/clear"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/hyprctl"
chmod +x "$T/bin/"*

echo "== mysz: porada sprzętowego DPI bez ratbagctl"
mouse() {   # mouse <os> [kod: cur|base] — menu (Enter = Back) → $OUT, wywołania → $C
    local ms="$SRC/scripts/hypr/mouse-settings.sh"
    [[ "${2:-cur}" == base ]] && ms="$BASE/scripts/hypr/mouse-settings.sh"
    rm -rf "${T:?}/home"; mkdir -p "$T/home/archenemy"; : > "$CALLS"
    OUT="$(printf '8\n' | test_timeout 15 env HOME="$T/home" ARCHENEMY_OS_RELEASE="$T/os/$1" PATH="$T/bin:/usr/bin:/bin" \
        bash "$ms" 2>&1 | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')"
    C="$(cat "$CALLS")"
}
if command -v ratbagctl >/dev/null 2>&1 && [[ "$(command -v ratbagctl)" != "$T"/* ]]; then
    echo "  – ratbagctl w systemie: PATH testu i tak go pomija (/usr/bin w PATH) — pomijam myszy"
else
    mouse arch; a_out="$OUT"
    check "Arch: dotychczasowa porada pacmana" '[[ "$OUT" == *"Real hardware DPI and polling rate: sudo pacman -S libratbag"* && -z "$C" ]]'
    mouse endeavouros
    check "EndeavourOS = Arch" '[[ "$OUT" == "$a_out" && -z "$C" ]]'
    mouse fedora
    check "Fedora: RPM libratbag-ratbagd z mapy, bez pacmana, zero wywołań" '[[ "$OUT" == *"sudo dnf install --repo=fedora --repo=updates libratbag-ratbagd"* && "$OUT" != *pacman* && -z "$C" ]]'
    mouse nixos
    check "NixOS: services.ratbagd.enable, bez sudo i pacmana, zero wywołań" '[[ "$OUT" == *"services.ratbagd.enable = true;"* && "$OUT" != *pacman* && "$OUT" != *"sudo "* && -z "$C" ]]'
    mouse ubuntu
    check "Ubuntu: porada ogólna, zero wywołań" '[[ "$OUT" == *"with your distribution'"'"'s tools"* && "$OUT" != *pacman* && -z "$C" ]]'
    check "emulowane DPI zostaje w menu na każdej platformie" '[[ "$OUT" == *"DPI: not set"* ]]'
    if [[ -n "$BASE" ]]; then
        mouse arch base
        check "Arch = $RUNTIME_PLATFORMS_REV (całe menu)" '[[ "$OUT" == "$a_out" && -z "$C" ]]'
    fi
fi

echo "== workspace-orphan-guard: tryb awaryjny"
# Izolowany PATH guarda: prawdziwe narzędzia bez socat, atrapy hyprctl
# (monitors odpowiada MOCK_HYPR_OK razy, potem Hyprland „umiera”),
# notify-send (zapis) i sleep (bez czekania).
for c in bash dirname flock seq sed stat mkdir cat grep sort head cut tr awk; do
    ln -sf "$(command -v "$c")" "$T/gbin/$c"
done
cat > "$T/gbin/hyprctl" <<'EOF'
#!/usr/bin/env bash
echo "hyprctl $*" >> "${CALLS:?}"
[[ "$1" == monitors ]] || exit 1
n=$(( $(cat "$CALLS.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS.n"
(( n <= ${MOCK_HYPR_OK:-3} )) || exit 1
echo "Monitor DP-1 (ID 0):"
EOF
cat > "$T/gbin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CALLS:?}.notify"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/gbin/sleep"
printf '#!/usr/bin/env bash\necho "socat $*" >> "${CALLS:?}"\nexit 0\n' > "$T/sbin/socat"
for c in sudo pacman dnf systemctl nix-env; do cp "$T/bin/$c" "$T/gbin/$c"; done
find "$T/gbin" "$T/sbin" -maxdepth 1 -type f -exec chmod +x {} +   # nie przez dowiązania do /usr/bin

BASH_BIN="$(command -v bash)"   # timeout i env z PATH testu (test_timeout), nie z $path guarda
guard() {   # guard <os> <socat: yes|no> <socket: yes|no> [kod] → $RC, $N (powiadomienia), $C
    local g="$SRC/scripts/hypr/workspace-orphan-guard.sh" path="$T/gbin"
    [[ "${4:-cur}" == base ]] && g="$BASE/scripts/hypr/workspace-orphan-guard.sh"
    rm -rf "${T:?}/home" "${T:?}/run"; mkdir -p "$T/home/archenemy" "$T/run/hypr/sig"; chmod 700 "$T/run"
    : > "$CALLS"; rm -f "$CALLS.n" "$CALLS.notify"
    [[ "$2" == yes ]] && path="$T/sbin:$path"
    [[ "$3" == yes ]] && python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$T/run/hypr/sig/.socket2.sock"
    HOME="$T/home" XDG_RUNTIME_DIR="$T/run" HYPRLAND_INSTANCE_SIGNATURE=sig ARCHENEMY_OS_RELEASE="$T/os/$1" \
        test_timeout 20 env PATH="$path" "$BASH_BIN" "$g" < /dev/null > "$T/guard-out" 2>&1
    RC=$?
    N="$(cat "$CALLS.notify" 2>/dev/null)"
    C="$(grep -vE '^hyprctl monitors$' "$CALLS")"
    MON="$(grep -cx 'hyprctl monitors' "$CALLS")"
}
nl=$'\n'
guard arch no no; a_n="$N"
check "Arch bez socat: kod 0 po 5 nieudanych odczytach (3 udane + 5)" '[[ $RC == 0 && "$MON" == 8 ]]'
check "Arch bez socat: jedno powiadomienie, dotychczasowy tekst" '[[ "$N" == "-a archenemy -u low archenemy workspace-guard: brak socat — działam sondą co 2 s (szybciej: sudo pacman -S socat i przeloguj)." ]]'
check "Arch bez socat: zero instalacji" '[[ -z "$C" ]]'
guard endeavouros no no
check "EndeavourOS = Arch" '[[ "$N" == "$a_n" && $RC == 0 && -z "$C" ]]'
guard fedora no yes
check "Fedora bez socat: jedno powiadomienie z RPM z mapy" '[[ "$N" != *"$nl"* && "$N" == *"brak socat"* && "$N" == *"sudo dnf install --repo=fedora --repo=updates socat"* && "$N" != *pacman* && $RC == 0 && -z "$C" ]]'
guard nixos no yes
check "NixOS bez socat: pkgs.socat, bez sudo i pacmana" '[[ "$N" != *"$nl"* && "$N" == *"pkgs.socat"* && "$N" != *pacman* && "$N" != *"sudo "* && $RC == 0 && -z "$C" ]]'
guard ubuntu no no
check "Ubuntu bez socat: porada ogólna" '[[ "$N" == *"brak socat"* && "$N" == *"narzędziami dystrybucji"* && "$N" != *pacman* && -z "$C" ]]'
for os in arch fedora nixos; do
    guard "$os" yes no
    check "$os: socat jest, brak gniazda — mówi o gnieździe, nie o socat; sonda i wyjście" '[[ "$N" != *"$nl"* && "$N" == *"brak gniazda zdarzeń Hyprlanda"* && "$N" != *"brak socat"* && "$N" != *pacman* && $RC == 0 && "$MON" == 8 && -z "$C" ]]'
done
guard fedora yes yes
check "socat i gniazdo są: tryb zdarzeń, bez powiadomienia" '[[ -z "$N" && $RC == 0 && "$C" == *"socat -U - UNIX-CONNECT:"* ]]'
if [[ -n "$BASE" ]]; then
    guard arch no no base
    check "Arch bez socat = $RUNTIME_PLATFORMS_REV (powiadomienie, kod, odczyty)" '[[ "${N#-a archenemy }" == "${a_n#-a archenemy }" && $RC == 0 && "$MON" == 8 && -z "$C" ]]'
    # L5 (przegląd D8–D10): ścieżka socat dotąd bez parytetu.
    guard arch yes yes; c_n="$N"; c_rc="$RC"; c_c="$C"; c_mon="$MON"
    guard arch yes yes base
    check "Arch socat i gniazdo = $RUNTIME_PLATFORMS_REV (tryb zdarzeń: wywołania, kod, cisza)" '[[ "$N" == "$c_n" && "$RC" == "$c_rc" && "$C" == "$c_c" && "$MON" == "$c_mon" && -z "$N" ]]'
    guard arch yes no; c_n="$N"; c_rc="$RC"; c_c="$C"; c_mon="$MON"
    guard arch yes no base
    # Jedyna zamierzona różnica: baza mówiła „brak socat” mimo socat w PATH.
    check "Arch socat bez gniazda = $RUNTIME_PLATFORMS_REV poza tekstem powiadomienia (kod, odczyty, wywołania)" '[[ "$RC" == "$c_rc" && "$C" == "$c_c" && "$MON" == "$c_mon" && "$N" != *"$nl"* && "$c_n" != *"$nl"* && ( "${N#-a archenemy }" == "${c_n#-a archenemy }" || ( "$N" == *"brak socat"* && "$c_n" == *"brak gniazda zdarzeń Hyprlanda"* ) ) ]]'
fi

echo "== odbiorcy runtime: rice'y (także yin i yang) → wspólne TUI i guard"
for r in white-blue tron asia-n-rice dither-flux crt yin yang; do
    f="$REPO/rices/$r/hypr/hyprland.lua"
    check "$r: Super+A = wspólne appbinds.sh" 'grep -qE "^local appbinds += \".*~/archenemy/scripts/appbinds/appbinds\.sh\"" "$f" && grep -qF "hl.bind(mainMod .. \" + A\", hl.dsp.exec_cmd(appbinds))" "$f"'
    check "$r: wspólne workspaces.lua (start guarda)" 'grep -qF "require(HOME .. \"/archenemy/config/hypr/workspaces.lua\")" "$f"'
done
check "workspaces.lua startuje guard ze wspólnego scripts/hypr" 'grep -qF "~/archenemy/scripts/hypr/workspace-orphan-guard.sh" "$REPO/config/hypr/workspaces.lua"'
check "TUI: [h]/[m]/[u] → wspólne skrypty z poradami per platforma" 'grep -qF "h) bash \"\$ARCHENEMY_DIR/scripts/shell/shell-settings.sh\"" "$REPO/scripts/appbinds/appbinds.sh" && grep -qF "m) bash \"\$ARCHENEMY_DIR/scripts/hypr/mouse-settings.sh\"" "$REPO/scripts/appbinds/appbinds.sh" && grep -qF "u) bash \"\$ARCHENEMY_DIR/scripts/appbinds/update-archenemy.sh\"" "$REPO/scripts/appbinds/appbinds.sh"'

if escaped="$(test_escapes "$T")"; then ok "zero zapisów poza \$T w: $(test_isolation_dirs)"
elif [[ $? == 2 ]]; then echo "  – izolacja niedostępna (unshare/overlay)"
else fail "zapisy poza \$T: ${escaped//$'\n'/ }"; fi
echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
test_timing_ok && [[ "$FAIL" -eq 0 ]]
