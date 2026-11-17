#!/usr/bin/env bash
# =============================================
#   archenemy - tests/pkg.sh
#   Warstwa pakietów install/lib/pkg.sh (D4, Fedora i NixOS w wariancie A,
#   decyzje 2026-11-17) na atrapach os-release, sudo, pacman, yay, dnf, rpm,
#   fc-list oraz nix-env / nix / nixos-rebuild (każda zapisuje wywołanie):
#     - wykrycie: arch / fedora / nixos z os-release bez eval (wartości
#       w cudzysłowach, próba wstrzyknięcia), fallback /usr/lib/os-release
#       (unshare -rm; bez niego skip), hak pliku tylko pod ARCHENEMY_TEST=1,
#       inne ID i Fedora Atomic → odmowa przed jakimkolwiek poleceniem;
#       pkg_arch_derivative (ID_LIKE=arch, ID≠arch) bez komunikatów; source
#       bez dirname w PATH;
#     - Arch = stare komendy: `pacman -Qi`, `sudo pacman -S --needed`,
#       `yay -S --needed` przez aur_install (zgodność z install.sh sprawdzana
#       na tekście instalatora);
#     - Fedora: dokładne nazwy (rpm -q --qf '%{NAME}\n'), jeden id → wiele
#       RPM, offline/błąd dnf i zepsuta baza rpm, zero flag maskujących braki,
#       COPR/Brave tylko przez pkg_install_extra po „y” (n, Enter, EOF = nic);
#     - NixOS: żadnej mutacji (ani sudo, ani nix-env/nix/nixos-rebuild),
#       tylko sondy i podpowiedzi;
#     - mapa jako dane: zła linia albo nazwa ze znakami powłoki = odmowa;
#       samo `source` biblioteki nie woła żadnego polecenia.
#   Bez sieci, bez roota.
#   Uruchom: bash tests/pkg.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval na cytowanym wyrażeniu (czyta RC, INST, AURLIB); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  - skip: $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

LIB="$REPO/install/lib/pkg.sh"
mkdir -p "$T/bin" "$T/sys" "$T/state" "$T/os" "$T/repos"
export STATE="$T/state" CALLS="$T/state/calls"

# ── atrapy ──
# sudo: zapisuje i wykonuje resztę (atrapa polecenia też się zapisze).
cat > "$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >> "$CALLS"
exec "$@"
EOF
# pacman: -Qi <nazwa> (jest, gdy w state/pacman-db), -Q <nazwa> (wersja),
# -S --needed <nazwy…> (dopisuje do bazy; MOCK_PACMAN_FAIL=1 = porażka).
cat > "$T/bin/pacman" <<'EOF'
#!/usr/bin/env bash
echo "pacman $*" >> "$CALLS"
db="$STATE/pacman-db"; touch "$db"
case "$1" in
    -Qi) grep -qx "$2 .*" "$db" ;;
    -Q)  line="$(grep -m1 "^$2 " "$db")" || exit 1; echo "$line" ;;
    -S)  shift; [[ "$1" == --needed ]] && shift
         [[ -n "${MOCK_PACMAN_FAIL:-}" ]] && exit 1
         for p in "$@"; do grep -q "^$p " "$db" || echo "$p 1.0-1" >> "$db"; done ;;
    *) exit 2 ;;
esac
EOF
cat > "$T/bin/yay" <<'EOF'
#!/usr/bin/env bash
echo "yay $*" >> "$CALLS"
exit "${MOCK_YAY_RC:-0}"
EOF
# rpm -q --qf '%{NAME}\n'|'%{VERSION}\n' <nazwy…>: baza state/rpm-db („nazwa wersja”).
# MOCK_RPM_BROKEN=1 — błąd bazy; MOCK_RPM_ALIAS=X:Y — pytanie o X zwraca nazwę Y
# (jak dopasowanie po provides — tego nie wolno uznać za dokładną nazwę).
cat > "$T/bin/rpm" <<'EOF'
#!/usr/bin/env bash
echo "rpm $*" >> "$CALLS"
db="$STATE/rpm-db"; touch "$db"
[[ "$1" == -q && "$2" == --qf ]] || exit 2
fmt="$3"; shift 3
if [[ -n "${MOCK_RPM_BROKEN:-}" ]]; then echo "error: cannot open Packages database in /var/lib/rpm" >&2; exit 1; fi
miss=0
for p in "$@"; do
    if [[ -n "${MOCK_RPM_ALIAS:-}" && "$p" == "${MOCK_RPM_ALIAS%%:*}" ]]; then echo "${MOCK_RPM_ALIAS#*:}"; continue; fi
    line="$(grep -m1 "^$p " "$db")"
    if [[ -z "$line" ]]; then echo "package $p is not installed"; miss=$((miss + 1)); continue; fi
    case "$fmt" in
        '%{NAME}\n') echo "${line%% *}" ;;
        '%{VERSION}\n') echo "${line#* }" ;;
    esac
done
exit "$miss"
EOF
# dnf: install <nazwy…> (dopisuje do rpm-db; MOCK_DNF_FAIL=1 = offline, nic
# nie instaluje), copr enable, config-manager addrepo — tylko zapis.
cat > "$T/bin/dnf" <<'EOF'
#!/usr/bin/env bash
echo "dnf $*" >> "$CALLS"
db="$STATE/rpm-db"; touch "$db"
case "$1" in
    install)
        [[ -n "${MOCK_DNF_FAIL:-}" ]] && { echo "Curl error (6): Couldn't resolve host name" >&2; exit 1; }
        shift
        for p in "$@"; do grep -q "^$p " "$db" || echo "$p ${MOCK_DNF_VERSION:-1.0}" >> "$db"; done ;;
    copr|config-manager) exit "${MOCK_DNF_REPO_RC:-0}" ;;
    *) exit 2 ;;
esac
EOF
cat > "$T/bin/fc-list" <<'EOF'
#!/usr/bin/env bash
echo "fc-list $*" >> "$CALLS"
cat "$STATE/fonts" 2>/dev/null
EOF
for c in nix-env nix nixos-rebuild nix-channel; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$CALLS"\n' "$c" > "$T/bin/$c"
done
chmod +x "$T/bin"/*
# PATH tylko z atrap i potrzebnych narzędzi: na tej maszynie są prawdziwe
# pacman i yay — nie mogą zafałszować testu.
for c in bash sh env cat dirname sort head grep touch mkdir rm sed tr chmod; do ln -s "$(command -v "$c")" "$T/sys/$c"; done
ORIG_PATH="$PATH"
export PATH="$T/bin:$T/sys"
export RED='' GREEN='' YELLOW='' NC=''

osr() { printf '%s\n' "$@" > "$T/os/os-release"; }
reset_state() {
    rm -f "$STATE"/*
    touch "$CALLS"
    unset MOCK_PACMAN_FAIL MOCK_YAY_RC MOCK_RPM_BROKEN MOCK_RPM_ALIAS MOCK_DNF_FAIL MOCK_DNF_REPO_RC MOCK_DNF_VERSION
    rm -f "$T/repos"/*
}
# run <stdin> <kod bash…> — świeży bash z biblioteką i hakami testowymi;
# wyjście w $OUT, kod w $RC, wywołania atrap w $T/state/calls.
run() {
    local input="$1"; shift
    OUT="$(printf '%b' "$input" | ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os/os-release" \
        ARCHENEMY_OSTREE_MARKER="$T/os/ostree-booted" ARCHENEMY_YUM_REPOS_DIR="$T/repos" \
        bash -c 'source "$1"; shift; eval "$*"' _ "$LIB" "$@" 2>&1)"
    RC=$?
}
calls() { cat "$CALLS"; }
has_call() { grep -qxF -- "$1" "$CALLS"; }
no_call_re() { ! grep -qE -- "$1" "$CALLS"; }

echo "== source bez skutków ubocznych"
reset_state
run '' 'true'
check "source + nic: zero wywołań poleceń" '[[ $RC -eq 0 && ! -s "$CALLS" ]]'

echo "== pkg_detect"
reset_state; osr 'NAME="Arch Linux"' 'ID=arch'
run '' 'pkg_detect; echo "rc=$? p=$PKG_PLATFORM"'
check "ID=arch → arch" '[[ "$OUT" == *"rc=0 p=arch"* ]]'
osr 'NAME="Fedora Linux"' 'ID="fedora"' 'VERSION_ID="44"' 'VARIANT_ID=workstation'
run '' 'pkg_detect; echo "rc=$? p=$PKG_PLATFORM v=$PKG_OS_VERSION"'
check "ID=\"fedora\" w cudzysłowach → fedora, VERSION_ID=44" '[[ "$OUT" == *"rc=0 p=fedora v=44"* ]]'
osr "ID='nixos'" 'VERSION_ID="26.05"'
run '' 'pkg_detect; echo "rc=$? p=$PKG_PLATFORM"'
check "ID='nixos' → nixos" '[[ "$OUT" == *"rc=0 p=nixos"* ]]'
osr 'ID=ubuntu' 'ID_LIKE=debian'
run '' 'pkg_detect; echo "rc=$? p=[$PKG_PLATFORM]"'
check "ID=ubuntu → odmowa, PKG_PLATFORM pusty" '[[ "$OUT" == *"rc=1 p=[]"* && "$OUT" == *"Unsupported distribution (ID=ubuntu)"* ]]'
osr 'ID=endeavouros' 'ID_LIKE=arch'
run '' 'pkg_detect; echo "rc=$?"'
check "pochodna Archa (ID_LIKE=arch) → odmowa, tylko jawne ID" '[[ "$OUT" == *"rc=1"* ]]'
echo "== pkg_arch_derivative (D5: pochodne Archa → stara ścieżka Archa w install.sh)"
for os in 'ID=endeavouros|ID_LIKE=arch' 'ID=manjaro|ID_LIKE="arch"' 'ID=cachyos|ID_LIKE="arch"' 'ID=garuda|ID_LIKE="arch archlinux"'; do
    IFS='|' read -ra lines <<< "$os"; reset_state; osr "${lines[@]}"
    run '' 'pkg_arch_derivative; echo "rc=$? p=[$PKG_PLATFORM]"'
    check "${lines[0]} (${lines[1]}) → pochodna, bez PKG_PLATFORM i bez poleceń" '[[ "$OUT" == "rc=0 p=[]" && ! -s "$CALLS" ]]'
done
for os in 'ID=arch' 'ID=arch|ID_LIKE=arch' 'ID=fedora' 'ID=nixos' 'ID=ubuntu|ID_LIKE=debian' 'ID=archcraft' 'ID_LIKE=arch' 'ID=x|ID_LIKE="archlinux"'; do
    IFS='|' read -ra lines <<< "$os"; osr "${lines[@]}"
    run '' 'pkg_arch_derivative; echo "rc=$?"'
    check "${os//|/ } → nie pochodna (tylko słowo „arch” w ID_LIKE, ID≠arch)" '[[ "$OUT" == "rc=1" ]]'
done
rm -f "$T/os/os-release"
run '' 'pkg_arch_derivative; echo "rc=$?"'
check "brak os-release → nie pochodna, bez komunikatu" '[[ "$OUT" == "rc=1" ]]'
# install.sh source'uje bibliotekę także przy okrojonym PATH (bez dirname).
mkdir -p "$T/nodirname"; PATH="$ORIG_PATH" ln -sf "$(PATH="$ORIG_PATH" command -v bash)" "$T/nodirname/bash"
OUT="$(cd "$REPO/install" && PATH="$T/nodirname" bash -c 'source lib/pkg.sh; echo "dir=$PKG_LIB_DIR"' 2>&1)"
check "source bez dirname w PATH: PKG_LIB_DIR poprawny, bez błędów" '[[ "$OUT" == "dir=$REPO/install/lib" ]]'
osr 'ID=fedora' 'VERSION_ID=44' 'VARIANT_ID=silverblue'
run '' 'pkg_detect; echo "rc=$?"'
check "Fedora Silverblue (VARIANT_ID) → odmowa" '[[ "$OUT" == *"rc=1"* && "$OUT" == *"Fedora Atomic"* ]]'
osr 'ID=fedora' 'VERSION_ID=44' 'VARIANT_ID=cosmic-atomic'
run '' 'pkg_detect; echo "rc=$?"'
check "Fedora COSMIC Atomic → odmowa" '[[ "$OUT" == *"rc=1"* ]]'
osr 'ID=fedora' 'VERSION_ID=44'
touch "$T/os/ostree-booted"
run '' 'pkg_detect; echo "rc=$?"'
check "znacznik /run/ostree-booted (atrapa) → odmowa" '[[ "$OUT" == *"rc=1"* ]]'
rm -f "$T/os/ostree-booted"
# Wstrzyknięcie: wartości to tekst, nie kod.
osr "ID=\$(touch $T/state/pwned)" "VERSION_ID=\`touch $T/state/pwned2\`" 'ID=arch'
run '' 'pkg_detect; echo "rc=$? id=$PKG_OS_ID"'
check "os-release z \$(…) i \`…\` → nic nie wykonane, odmowa" '[[ "$OUT" == *"rc=1"* && ! -e "$T/state/pwned" && ! -e "$T/state/pwned2" ]]'
reset_state; osr 'ID=ubuntu'
run '' 'pkg_install waybar; echo "rc=$?"'
check "pkg_install na nieobsługiwanej → 4, zero poleceń" '[[ "$OUT" == *"rc=4"* && ! -s "$CALLS" ]]'
# Hak pliku działa tylko pod ARCHENEMY_TEST=1: bez niego czytany jest
# prawdziwy os-release tej maszyny.
real_id="$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d "\"'")"
osr 'ID=nixos'
OUT="$(ARCHENEMY_OS_RELEASE="$T/os/os-release" bash -c 'source "$1"; pkg_detect >/dev/null 2>&1; echo "p=$PKG_OS_ID"' _ "$LIB")"
check "ARCHENEMY_OS_RELEASE bez ARCHENEMY_TEST=1 ignorowany (ID=${real_id:-?})" '[[ "$OUT" == "p=$real_id" ]]'
# Fallback /usr/lib/os-release: /etc bez os-release w przestrzeni montowań.
if PATH="$ORIG_PATH" command -v unshare >/dev/null 2>&1 \
        && PATH="$ORIG_PATH" unshare -rm true 2>/dev/null; then
    mkdir -p "$T/etc-empty"
    printf 'ID=fedora\nVERSION_ID=45\n' > "$T/os/usr-lib-os-release"
    OUT="$(PATH="$ORIG_PATH" unshare -rm bash -c '
        mount --bind "$1" /etc && mount --bind "$2" /usr/lib/os-release || exit 9
        source "$3"; pkg_detect >/dev/null 2>&1; echo "rc=$? p=$PKG_PLATFORM v=$PKG_OS_VERSION"' \
        _ "$T/etc-empty" "$T/os/usr-lib-os-release" "$LIB" 2>&1)"
    if [[ "$OUT" == *"rc=9"* || -z "$OUT" ]]; then
        skip "fallback /usr/lib/os-release: mount w unshare niedostępny ($OUT)"
    else
        check "brak /etc/os-release → /usr/lib/os-release (fedora 45)" '[[ "$OUT" == "rc=0 p=fedora v=45" ]]'
    fi
else
    skip "fallback /usr/lib/os-release: brak unshare -rm"
fi

echo "== Arch: te same komendy co install.sh"
# Wzorce w instalatorze, z którymi pkg.sh ma być zgodny (D5 podmieni je na API).
INST="$(cat "$REPO/install/install.sh")"
check "install.sh [5] nadal: pacman -Qi \"\$pkg\" / sudo pacman -S --needed / aur_install" \
    '[[ "$INST" == *'\''pacman -Qi "$pkg" &>/dev/null'\''* && "$INST" == *'\''sudo pacman -S --needed "${MISSING_PACMAN[@]}"'\''* && "$INST" == *'\''aur_install "${MISSING_AUR[@]}"'\''* ]]'
AURLIB="$(cat "$REPO/install/lib/aur.sh")"
check "aur.sh nadal: yay -S --needed" '[[ "$AURLIB" == *'\''yay -S --needed "${review[@]}" "$@"'\''* ]]'
reset_state; osr 'ID=arch'
echo "hyprland 0.57.2-1" > "$STATE/pacman-db"
run '' 'pkg_installed hyprland; echo "a=$?"; pkg_installed waybar; echo "b=$?"'
check "pkg_installed: pacman -Qi dokładnej nazwy, 0/1" '[[ "$OUT" == *"a=0"*"b=1"* ]] && has_call "pacman -Qi hyprland" && has_call "pacman -Qi waybar"'
reset_state
run 'n\n' 'pkg_install waybar pipewire-pulse brave-bin; echo "rc=$?"'
check "pkg_install: sudo pacman -S --needed (lista) + yay -S --needed (AUR, bez przeglądu po n)" \
    '[[ "$OUT" == *"rc=0"* ]] && has_call "sudo pacman -S --needed waybar pipewire-pulse" && has_call "yay -S --needed brave-bin"'
check "Arch: ani dnf, ani rpm" 'no_call_re "^(dnf|rpm|sudo dnf)"'
reset_state; export MOCK_PACMAN_FAIL=1
run '' 'pkg_install waybar mako; echo "rc=$? failed=${PKG_FAILED[*]}"'
unset MOCK_PACMAN_FAIL
check "pacman zawiódł → 1, PKG_FAILED = brakujące" '[[ "$OUT" == *"rc=1 failed=waybar mako"* ]]'
reset_state; rm -f "$T/bin/yay"
run '' 'pkg_install brave-bin; echo "rc=$?"'
check "brak yay → 1 i żadnego wywołania yay" '[[ "$OUT" == *"rc=1"* && "$OUT" == *"yay not available"* ]] && no_call_re "^yay"'
printf '#!/usr/bin/env bash\necho "yay $*" >> "$CALLS"\nexit "${MOCK_YAY_RC:-0}"\n' > "$T/bin/yay"; chmod +x "$T/bin/yay"
reset_state; echo "hyprland 1:0.55.4-2" > "$STATE/pacman-db"
run '' 'pkg_version hyprland; echo "rc=$?"'
check "pkg_version: 0.55.4 (bez epoki i pkgrel) < min 0.56 → 3" '[[ "$OUT" == *"0.55.4"*"rc=3"* ]]'
reset_state; echo "hyprland 0.57.2-1" > "$STATE/pacman-db"
run '' 'pkg_version hyprland; echo "rc=$?"'
check "pkg_version: 0.57.2 ≥ 0.56 → 0" '[[ "$OUT" == *"0.57.2"*"rc=0"* ]]'
run '' 'pkg_hint waybar; pkg_hint brave-bin'
check "pkg_hint Arch: pacman / yay" '[[ "$OUT" == *"sudo pacman -S --needed waybar"* && "$OUT" == *"yay -S --needed brave-bin"* ]]'

echo "== Fedora"
osr 'ID=fedora' 'VERSION_ID=44'
reset_state
run '' 'pkg_install waybar libpulse base-devel; echo "rc=$?"'
check "jeden id → wiele RPM: sudo dnf install waybar pulseaudio-libs-devel pulseaudio-utils gcc make pkgconf-pkg-config" \
    '[[ "$OUT" == *"rc=0"* ]] && has_call "sudo dnf install waybar pulseaudio-libs-devel pulseaudio-utils gcc make pkgconf-pkg-config"'
check "sukces sprawdzony rpm -q --qf %{NAME} każdej nazwy" "has_call \"rpm -q --qf %{NAME}\\\\n waybar pulseaudio-libs-devel pulseaudio-utils gcc make pkgconf-pkg-config\""
check "Fedora: ani pacman, ani yay" 'no_call_re "^(pacman|yay|sudo pacman)"'
reset_state; echo "pulseaudio-libs 17.0" > "$STATE/rpm-db"; echo "pulseaudio-utils 17.0" >> "$STATE/rpm-db"
run '' 'pkg_installed libpulse; echo "rc=$?"'
check "dokładna nazwa: pulseaudio-libs ≠ pulseaudio-libs-devel → brak (1)" '[[ "$OUT" == *"rc=1"* ]]'
reset_state; export MOCK_RPM_ALIAS="python3:python3.14"
run '' 'pkg_installed python; echo "rc=$?"'
unset MOCK_RPM_ALIAS
check "rpm zwraca inną nazwę niż pytana → błąd (2), nie „jest”" '[[ "$OUT" == *"rc=2"* ]]'
reset_state; export MOCK_RPM_BROKEN=1
run '' 'pkg_installed waybar; echo "rc=$?"'
unset MOCK_RPM_BROKEN
check "zepsuta baza rpm → 2 (błąd zapytania, nie „brak”)" '[[ "$OUT" == *"rc=2"* ]]'
reset_state; export MOCK_DNF_FAIL=1
run '' 'pkg_install waybar mako; echo "rc=$? failed=${PKG_FAILED[*]}"'
unset MOCK_DNF_FAIL
check "offline (dnf zawiódł) → 1, PKG_FAILED z rpm -q" '[[ "$OUT" == *"rc=1 failed=waybar mako"* ]]'
check "dnf bez -y, --skip-unavailable, --skip-broken, --allowerasing" 'no_call_re "dnf .*(-y( |$)|--assumeyes|--skip-unavailable|--skip-broken|--allowerasing|--nobest)"'
reset_state
run '' 'pkg_install hyprland networkmanager-dmenu discord waybar; echo "rc=$? skipped=${PKG_SKIPPED[*]}"'
check "pkg_install: COPR, ręczne i RPM Fusion pominięte (3), instaluje tylko waybar" \
    '[[ "$OUT" == *"rc=3 skipped=hyprland networkmanager-dmenu discord"* ]] && has_call "sudo dnf install waybar" && no_call_re "copr|config-manager|hyprland"'
for ans in 'n\n' '\n' ''; do
    reset_state
    run "$ans" 'pkg_install_extra hyprland hyprpaper; echo "rc=$?"'
    check "pkg_install_extra bez zgody ($(printf '%q' "$ans")) → 3, zero dnf" '[[ "$OUT" == *"rc=3"* && "$OUT" == *"nett00n/hyprland"* && "$OUT" == *"copr-be.cloud.fedoraproject.org"* ]] && no_call_re "^(sudo|dnf)"'
done
reset_state
run 'y\n' 'pkg_install_extra hyprland hyprpaper; echo "rc=$?"'
check "zgoda y → dnf5-plugins, copr enable nett00n/hyprland, dnf install hyprland hyprpaper" \
    '[[ "$OUT" == *"rc=0"* ]] && has_call "sudo dnf install dnf5-plugins" && has_call "sudo dnf copr enable nett00n/hyprland" && has_call "sudo dnf install hyprland hyprpaper"'
reset_state; export MOCK_DNF_REPO_RC=1
run 'y\n' 'pkg_install_extra hyprland; echo "rc=$?"'
unset MOCK_DNF_REPO_RC
check "copr enable zawiódł → 1, bez dnf install hyprland" '[[ "$OUT" == *"rc=1"* ]] && ! has_call "sudo dnf install hyprland"'
reset_state
run 'y\n' 'pkg_install_extra brave-bin; echo "rc=$?"'
check "Brave po y: config-manager addrepo --from-repofile + dnf install brave-browser" \
    '[[ "$OUT" == *"rc=0"* ]] && has_call "sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo" && has_call "sudo dnf install brave-browser"'
reset_state; touch "$T/repos/brave-browser.repo"
run 'y\n' 'pkg_install_extra brave-bin; echo "rc=$?"'
check "repo Brave już jest → bez addrepo, tylko install" '[[ "$OUT" == *"rc=0"* ]] && no_call_re "config-manager" && has_call "sudo dnf install brave-browser"'
reset_state
run 'y\ny\n' 'pkg_install_extra discord steam waybar; echo "rc=$? skipped=${PKG_SKIPPED[*]}"'
check "pkg_install_extra: RPM Fusion i repo Fedory nie są jego (3), zero poleceń" '[[ "$OUT" == *"rc=3 skipped=discord steam waybar"* && ! -s "$CALLS" ]]'
run '' 'pkg_hint networkmanager-dmenu; pkg_hint discord; pkg_hint hyprland; pkg_hint waybar; pkg_hint ttf-iosevka-nerd'
check "pkg_hint Fedora: ręcznie z URL, RPM Fusion, COPR, dnf, fonty" \
    '[[ "$OUT" == *"install manually: https://github.com/firecat53/networkmanager-dmenu"* && "$OUT" == *"Enable RPM Fusion"*"sudo dnf install discord"* && "$OUT" == *"sudo dnf copr enable nett00n/hyprland && sudo dnf install hyprland"* && "$OUT" == *"sudo dnf install waybar"* && "$OUT" == *"nerd-fonts/releases"* ]]'
reset_state; echo "hyprland 0.57.2" > "$STATE/rpm-db"
run '' 'pkg_version hyprland; echo "rc=$?"'
check "pkg_version Fedora: rpm %{VERSION} 0.57.2 → 0" '[[ "$OUT" == *"0.57.2"*"rc=0"* ]] && has_call "rpm -q --qf %{VERSION}\\n hyprland"'
reset_state; osr 'ID=fedora' 'VERSION_ID=46'
run 'n\n' 'pkg_install_extra hyprland; echo "rc=$?"'
check "Fedora spoza sprawdzonych wydań → ostrzeżenie przy COPR" '[[ "$OUT" == *"checked for Fedora 43 44 45, not 46"* ]]'

echo "== NixOS: bez mutacji"
osr 'ID=nixos' 'VERSION_ID=26.05'
reset_state
run '' 'pkg_install hyprland waybar coreutils; echo "rc=$?"'
check "pkg_install → 5 (deklaratywnie) z podpowiedziami" '[[ "$OUT" == *"rc=5"* && "$OUT" == *"programs.hyprland.enable"* && "$OUT" == *"pkgs.waybar"* && "$OUT" == *"base NixOS system"* ]]'
check "NixOS: zero sudo, nix-env, nix, nixos-rebuild, pacman, dnf" '! grep -qE "^(sudo|nix-env|nix|nixos-rebuild|nix-channel|pacman|dnf|yay) " "$CALLS"'
reset_state
run 'y\n' 'pkg_install_extra brave-bin; echo "rc=$?"'
check "pkg_install_extra na NixOS → 2, zero poleceń" '[[ "$OUT" == *"rc=2"* ]] && ! grep -qE "^(sudo|nix|dnf)" "$CALLS"'
printf '#!/usr/bin/env bash\n' > "$T/bin/waybar"; chmod +x "$T/bin/waybar"
echo "Iosevka Nerd Font,Iosevka NF" > "$STATE/fonts"
run '' 'pkg_installed waybar; echo "a=$?"; pkg_installed mako; echo "b=$?"; pkg_installed papirus-icon-theme; echo "c=$?"; pkg_installed ttf-iosevka-nerd; echo "d=$?"; pkg_installed ttf-jetbrains-mono-nerd; echo "e=$?"'
check "sondy: cmd jest 0, brak 1, bez sondy 3, font jest 0, brak 1" '[[ "$OUT" == *"a=0"*"b=1"*"c=3"*"d=0"*"e=1"* ]]'
run '' 'pkg_version waybar; echo "rc=$?"'
check "pkg_version na NixOS → 2 (brak bazy pakietów)" '[[ "$OUT" == *"rc=2"* ]]'
rm -f "$T/bin/waybar"

echo "== mapa jako dane"
osr 'ID=fedora' 'VERSION_ID=44'
reset_state
run '' 'pkg_installed nie-ma-takiego; echo "rc=$?"'
check "nieznany id → 2" '[[ "$OUT" == *"rc=2"* && "$OUT" == *"Unknown package id"* ]]'
printf 'zly\tzly\tpacman\tfoo;touch\tfedora\t-\t-\t-\tfedora=ok;nixos=ok\thttps://x.invalid/\n' > "$T/state/map-inj.tsv"
OUT="$(ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os/os-release" ARCHENEMY_PKG_MAP="$T/state/map-inj.tsv" \
    bash -c 'source "$1"; pkg_install zly; echo "rc=$?"' _ "$LIB" 2>&1)"
check "nazwa ze znakami powłoki w mapie → odmowa (2), zero poleceń" '[[ "$OUT" == *"rc=2"* && "$OUT" == *"Invalid package name"* ]] && ! grep -q "^sudo" "$CALLS"'
printf 'krotki\tkrotki\tpacman\n' > "$T/state/map-bad.tsv"
OUT="$(ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os/os-release" ARCHENEMY_PKG_MAP="$T/state/map-bad.tsv" \
    bash -c 'source "$1"; pkg_install krotki; echo "rc=$?"' _ "$LIB" 2>&1)"
check "zła liczba pól → odmowa całej mapy (2)" '[[ "$OUT" == *"rc=2"* && "$OUT" == *"Malformed package map line 1"* ]]'
OUT="$(ARCHENEMY_OS_RELEASE="$T/os/os-release" ARCHENEMY_PKG_MAP="$T/state/map-bad.tsv" \
    bash -c 'source "$1"; _pkg_load_map; echo "rc=$?"' _ "$LIB" 2>&1)"
check "ARCHENEMY_PKG_MAP bez ARCHENEMY_TEST=1 ignorowany (mapa repo)" '[[ "$OUT" == *"rc=0"* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗ / $SKIP skip"
((FAIL == 0))
