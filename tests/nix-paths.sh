#!/usr/bin/env bash
# =============================================
#   archenemy - tests/nix-paths.sh
#   Ścieżki bez FHS (D10, NixOS EKSPERYMENTALNE) na atrapie systemu plików
#   (ARCHENEMY_TEST=1 + ARCHENEMY_FS_ROOT): bez /usr/share, z plikami tylko
#   w profilach Nix. Sprawdza:
#     - scripts/hypr/keyboard-layouts.sh znajduje evdev.lst w profilu
#       (~/.nix-profile, ~/.local/state/nix/profile, /etc/profiles/per-user/<u>,
#       /run/current-system/sw) albo w $XKB_CONFIG_ROOT, więc nazwy układów
#       i walidacja kodów działają także z TUI [k] i bindów Super+Ctrl+N
#       (oba wołają ten sam skrypt — bez przekazywania zmiennych sesji);
#       ARCHENEMY_XKB_RULES wygrywa; na Archu (/usr/share jest) nic się nie
#       zmienia, także gdy profil Nix też ma plik; bez żadnego pliku dawne
#       zachowanie (składnia kodu);
#     - wtyczki zsh na NixOS: shell_plugin_paths i plik v2 bez /usr/share,
#       wyłącznie ścieżki profili; Arch dalej /usr/share/zsh/plugins.
#   NIX_PATHS_REV=<rev> uruchamia część XKB na keyboard-layouts.sh z tej
#   rewizji (dowód czerwieni na bazie). Zapisy tylko w $T (test_isolate).
#   Uruchom: bash tests/nix-paths.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC2088  # check() robi eval (zmienne czyta eval); etykiety z dosłownym ~
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
test_isolate "$REPO/tests/nix-paths.sh" "$@"   # D7F R3: zapisy poza $T wykrywalne
T="$(mktemp -d)" && [[ -n "$T" && -d "$T" && "$T" != / ]] || exit 1
trap 'rm -rf "${T:?}"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

KL="$REPO/scripts/hypr/keyboard-layouts.sh"
if [[ -n "${NIX_PATHS_REV:-}" ]]; then
    git -C "$REPO" show "$NIX_PATHS_REV:scripts/hypr/keyboard-layouts.sh" > "$T/kl-rev.sh" || exit 1
    KL="$T/kl-rev.sh"
    echo "(keyboard-layouts.sh z rewizji $NIX_PATHS_REV)"
fi
unset ARCHENEMY_XKB_RULES XKB_CONFIG_ROOT HYPRLAND_INSTANCE_SIGNATURE
USER_NAME="$(id -un)"

# Atrapa evdev.lst: <plik> <nazwa dla „pl”> — rozpoznamy, który plik wygrał.
evdev() {
    mkdir -p "$(dirname "$1")"
    printf '%s\n' '! model' '  pc105           Generic 105-key PC' '! layout' \
        '  us              English (US)' "  pl              $2" '! variant' > "$1"
}
# kl <fs-root> <args…> — skrypt na atrapie FS; HOME w $T.
kl() { local root="$1"; shift; ARCHENEMY_TEST=1 ARCHENEMY_FS_ROOT="$root" bash "$KL" "$@"; }
fresh() { rm -rf "$HOME/.nix-profile" "$HOME/.local/state/nix" "$HOME/archenemy"; mkdir -p "$HOME/archenemy/config/hypr"; }
XR=share/X11/xkb/rules/evdev.lst

echo "== XKB: NixOS bez /usr/share — evdev.lst z profilu Nix"
NIX="$T/fs-nixos"; mkdir -p "$NIX/etc"
fresh; evdev "$HOME/.nix-profile/$XR" "Polish (home profile)"
check "~/.nix-profile: name pl = nazwa z profilu" '[[ "$(kl "$NIX" name pl)" == "Polish (home profile)" ]]'
check "~/.nix-profile: nieznany kod xx odrzucony" '! kl "$NIX" set xx 2>"$T/err" && grep -q "not a known XKB layout code" "$T/err"'
check "~/.nix-profile: set pl,us zapisany"        'kl "$NIX" set pl,us >/dev/null && [[ "$(<"$HOME/archenemy/data/keyboard-layouts.dat")" == pl,us ]]'
fresh; evdev "$HOME/.local/state/nix/profile/$XR" "Polish (state profile)"
check "~/.local/state/nix/profile"                '[[ "$(kl "$NIX" name pl)" == "Polish (state profile)" ]] && ! kl "$NIX" set xx 2>/dev/null'
fresh; evdev "$NIX/etc/profiles/per-user/$USER_NAME/$XR" "Polish (per-user)"
check "/etc/profiles/per-user/<user>"             '[[ "$(kl "$NIX" name pl)" == "Polish (per-user)" ]] && ! kl "$NIX" set xx 2>/dev/null'
evdev "$NIX/run/current-system/sw/$XR" "Polish (system)"
check "per-user wygrywa z profilem systemowym"    '[[ "$(kl "$NIX" name pl)" == "Polish (per-user)" ]]'
rm -rf "$NIX/etc/profiles"
check "/run/current-system/sw"                    '[[ "$(kl "$NIX" name pl)" == "Polish (system)" ]] && ! kl "$NIX" set xx 2>/dev/null'
evdev "$HOME/.nix-profile/$XR" "Polish (home profile)"
check "profil domowy wygrywa z systemowym"        '[[ "$(kl "$NIX" name pl)" == "Polish (home profile)" ]]'
fresh; rm -rf "$NIX/run"; evdev "$NIX/xkbroot/rules/evdev.lst" "Polish (XKB_CONFIG_ROOT)"
check "\$XKB_CONFIG_ROOT/rules/evdev.lst"          '[[ "$(XKB_CONFIG_ROOT=/xkbroot kl "$NIX" name pl)" == "Polish (XKB_CONFIG_ROOT)" ]]'
evdev "$T/own.lst" "Polish (own)"
check "ARCHENEMY_XKB_RULES wygrywa"               '[[ "$(ARCHENEMY_XKB_RULES="$T/own.lst" XKB_CONFIG_ROOT=/xkbroot kl "$NIX" name pl)" == "Polish (own)" ]]'
fresh; rm -rf "$NIX/xkbroot"
check "brak pliku: dawne zachowanie (składnia kodu)" 'kl "$NIX" set xx >/dev/null 2>"$T/err" && [[ "$(kl "$NIX" name pl)" == Polish ]]'

echo "== XKB: Arch — /usr/share bez zmian, także obok profilu Nix"
ARCH="$T/fs-arch"; evdev "$ARCH/usr/$XR" "Polish (usr/share)"
fresh; evdev "$HOME/.nix-profile/$XR" "Polish (home profile)"
check "/usr/share wygrywa z ~/.nix-profile"       '[[ "$(kl "$ARCH" name pl)" == "Polish (usr/share)" ]]'
check "/usr/share wygrywa z XKB_CONFIG_ROOT"      'evdev "$ARCH/xkbroot/rules/evdev.lst" x; [[ "$(XKB_CONFIG_ROOT=/xkbroot kl "$ARCH" name pl)" == "Polish (usr/share)" ]]'
if [[ -r /usr/share/X11/xkb/rules/evdev.lst ]]; then
    want="$(awk '/^! /{s=$2;next} s=="layout" && $1=="pl" {$1="";sub(/^ +/,"");print;exit}' /usr/share/X11/xkb/rules/evdev.lst)"
    check "ARCHENEMY_FS_ROOT bez ARCHENEMY_TEST=1 ignorowany (host /usr/share)" \
        '[[ "$(ARCHENEMY_FS_ROOT="$NIX" bash "$KL" name pl)" == "$want" ]]'
else
    echo "  – skip: host bez /usr/share/X11/xkb/rules/evdev.lst"
fi

echo "== wtyczki zsh: NixOS tylko profile, bez /usr/share"
# shellcheck source=scripts/shell/lib/shell-rc.sh
ARCHENEMY_DIR="$HOME/archenemy" source "$REPO/scripts/shell/lib/shell-rc.sh"
paths=""
for p in zsh-autosuggestions zsh-syntax-highlighting zsh-completions; do paths+="$(shell_plugin_paths nixos "$p")"$'\n'; done
check "shell_plugin_paths nixos: bez /usr/share"  '[[ "$paths" != *"/usr/share"* ]]'
check "shell_plugin_paths nixos: każda ścieżka z profilu" '
    bad=0; while IFS= read -r l; do [[ -z "$l" ]] && continue
        [[ "$l" == "\$HOME/.nix-profile/"* || "$l" == "\$HOME/.local/state/nix/profile/"* || "$l" == "/etc/profiles/per-user/\$USER/"* || "$l" == /run/current-system/sw/* ]] || bad=1
    done <<< "$paths"; [[ $bad == 0 ]]'
v2="$(shell_plugins_v2_text nixos 1 1 1)"
check "plik v2 nixos: bez /usr/share"             '[[ "$v2" != *"/usr/share"* && "$v2" == *"# archenemy plugin paths: nixos"* ]]'
check "Arch: /usr/share/zsh/plugins jak dotąd"     '[[ "$(shell_plugin_paths arch zsh-autosuggestions)" == /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]'

echo "== izolacja"
if escaped="$(test_escapes "$T")"; then ok "zero zapisów poza \$T w: $(test_isolation_dirs)"
elif [[ $? == 2 ]]; then echo "  – izolacja niedostępna (unshare/overlay)"
else fail "zapisy poza \$T: ${escaped//$'\n'/ }"; fi
echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
