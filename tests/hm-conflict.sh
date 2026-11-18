#!/usr/bin/env bash
# =============================================
#   archenemy - tests/hm-conflict.sh
#   Konflikt z home-managerem (D10): HM wkłada do $HOME dowiązania do
#   /nix/store. archenemy ma je wykryć PRZED jakąkolwiek zmianą i niczego
#   nie nadpisać, nie przenieść do .bak ani nie pisać przez nie — tylko
#   porada. Na atrapie HOME, bez Hyprlanda, bez roota, bez nix.
#   Dwa rodzaje sklepu: prawdziwa ścieżka /nix/store (dowiązania wiszące —
#   tak samo rozpoznawane, bo readlink -m) i atrapa z treścią
#   (ARCHENEMY_NIX_STORE, tylko z ARCHENEMY_TEST=1).
#   Sprawdza:
#     - Super+T (lib/switch-rice.sh): folder rice'a jako link HM, łańcuch
#       link → link → sklep, plik HM w prawdziwym katalogu, całe ~/.config
#       w sklepie → kod 3, powiadomienie, porada; ~/.config, wszystkie linki
#       i .current_rice bajt w bajt bez zmian; bez reloadu/waybara;
#       tryb „tylko linki” bez powiadomienia; bez konfliktu dawne zachowanie;
#     - install.sh [9] (wycinek jak w tests/install-link.sh): ⚠ + porada +
#       wpis w podsumowaniu, bez ✓ i bez „Rice linked”; powtórny bieg
#       identyczny (idempotencja odmowy); po usunięciu deklaracji HM
#       linkowanie, a trzeci bieg bez nowych .bak;
#     - ~/.bashrc z HM: rc_block_ensure = managed bez kopii i zapisu (także
#       łańcuch), aktualny blok w pliku HM = ok, zwykły symlink (stow) jak
#       dotąd; rc_migrate_apply odmawia bez dopisania do shellrc; wycinek
#       instalatora [8m] wypisuje blok do programs.bash.initExtra;
#     - ~/.config/mpd z plikiem HM: bez pytania o podmianę, wpis w podsumowaniu;
#     - ~/archenemy w sklepie: install.sh odmawia (kod 1) przed zapisem.
#   Zapisy tylko w $T (test_isolate, D7F R3).
#   Uruchom: bash tests/hm-conflict.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC2088  # check() robi eval; puste kolory dla wycinków; etykiety z dosłownym ~
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
test_isolate "$REPO/tests/hm-conflict.sh" "$@"   # D7F R3: zapisy poza $T wykrywalne
T="$(mktemp -d)" && [[ -n "$T" && -d "$T" && "$T" != / ]] || exit 1
trap 'rm -rf "${T:?}"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ─── atrapy: wszystko, co biblioteka mogłaby odpalić, zostawia ślad w logu ──
mkdir -p "$T/bin"
for c in hyprctl makoctl pkill pgrep waybar swayosd-server notify-send; do
    printf '#!/usr/bin/env bash\necho "%s: $*" >> "$MOCK_LOG"\nexit 0\n' "$c" > "$T/bin/$c"
done
find "$T/bin" -type f -exec chmod +x {} +
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log"
unset ARCHENEMY_NIX_STORE

A="$HOME/archenemy"; C="$HOME/.config"
mkdir -p "$A/rices/alfa/hypr" "$A/rices/alfa/waybar" "$A/rices/alfa/mako" \
         "$A/rices/beta/hypr" "$A/rices/beta/rofi" "$A/scripts/changing-theme-scripts" "$C"
ln -s "$REPO/scripts/changing-theme-scripts/lib" "$A/scripts/changing-theme-scripts/lib"
ln -s "$REPO/scripts/lib" "$A/scripts/lib"
LIB="$A/scripts/changing-theme-scripts/lib/switch-rice.sh"

# Stan „po Super+T beta”: nasze linki do beta + .current_rice.
reset_home() {
    rm -rf "${C:?}" "$A/.current_rice" "$HOME/.bashrc"; mkdir -p "$C"
    ln -s "$A/rices/beta/hypr" "$C/hypr"; ln -s "$A/rices/beta/rofi" "$C/rofi"
    echo beta > "$A/.current_rice"
}
# Migawka: każda ścieżka pod ~/.config z typem, celem linku i sumą treści + .current_rice.
snap() {
    { find "$C" -printf '%P %y %l\n' | LC_ALL=C sort
      find "$C" -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort
      cat "$A/.current_rice" 2>/dev/null; } > "$1"
}
switch() { RICE_NAME="$1" bash "$LIB" 2>"$T/err"; }

echo "== Super+T: folder rice'a jako link home-managera (/nix/store)"
reset_home
ln -s /nix/store/aaaa-home-manager-files/.config/waybar "$C/waybar"
snap "$T/s0"; : > "$MOCK_LOG"
switch alfa; rc=$?
snap "$T/s1"
check "kod 3"                                     '[[ $rc -eq 3 ]]'
check "~/.config i .current_rice bez zmian"       'cmp -s "$T/s0" "$T/s1"'
check "link HM nietknięty, bez .bak"              '[[ "$(readlink "$C/waybar")" == /nix/store/aaaa-home-manager-files/.config/waybar ]] && ! ls -d "$C"/*.bak-* >/dev/null 2>&1'
check "nasze stare linki (beta) zostały"          '[[ "$(readlink "$C/hypr")" == "$A/rices/beta/hypr" && -L "$C/rofi" ]]'
check "powiadomienie krytyczne z nazwą ścieżki"   'grep -q "notify-send: -u critical archenemy Rice .alfa. not applied: home-manager manages ~/.config/waybar (nothing changed)" "$MOCK_LOG"'
check "porada na stderr: usuń deklarację, bez force" 'grep -q "Remove those entries from your home-manager configuration" "$T/err" && grep -q "Do not set force" "$T/err" && grep -q "~/.config/waybar -> /nix/store/aaaa" "$T/err"'
check "bez reloadu, waybara, makoctl"             '! grep -qE "^(hyprctl: reload|waybar|makoctl|pkill)" "$MOCK_LOG"'

echo "== Super+T: łańcuch link → link → sklep, plik HM w katalogu, całe ~/.config"
reset_home
mkdir -p "$T/dot"; ln -s /nix/store/bbbb-mako-config "$T/dot/mako"; ln -s "$T/dot/mako" "$C/mako"
snap "$T/s0"; switch alfa; rc=$?; snap "$T/s1"
check "łańcuch: kod 3 i bez zmian"                '[[ $rc -eq 3 ]] && cmp -s "$T/s0" "$T/s1"'
reset_home
mkdir -p "$C/hypr.real"; rm "$C/hypr"; mv "$C/hypr.real" "$C/hypr"
echo "# mine" > "$C/hypr/own.conf"; ln -s /nix/store/cccc-home-manager-files/.config/hypr/hyprland.conf "$C/hypr/hyprland.conf"
snap "$T/s0"; switch alfa; rc=$?; snap "$T/s1"
check "plik HM w prawdziwym katalogu: kod 3"      '[[ $rc -eq 3 ]] && cmp -s "$T/s0" "$T/s1" && grep -q "~/.config/hypr/hyprland.conf -> /nix/store/cccc" "$T/err"'
H2="$T/home2"; mkdir -p "$H2/archenemy/scripts/changing-theme-scripts"
ln -s "$A/rices" "$H2/archenemy/rices"; ln -s "$REPO/scripts/lib" "$H2/archenemy/scripts/lib"
ln -s "$REPO/scripts/changing-theme-scripts/lib" "$H2/archenemy/scripts/changing-theme-scripts/lib"
ln -s /nix/store/dddd-home-manager-files/.config "$H2/.config"
HOME="$H2" RICE_NAME=alfa bash "$H2/archenemy/scripts/changing-theme-scripts/lib/switch-rice.sh" 2>"$T/err"; rc=$?
check "~/.config w sklepie: kod 3, nic nie powstało" '[[ $rc -eq 3 && "$(readlink "$H2/.config")" == /nix/store/dddd-home-manager-files/.config && ! -e "$H2/archenemy/.current_rice" ]]'

echo "== Super+T: tryb "tylko linki" i atrapa sklepu z treścią"
reset_home
ST="$T/store"; mkdir -p "$ST/eeee-hm-files/waybar"; echo hm > "$ST/eeee-hm-files/waybar/config"
ln -s "$ST/eeee-hm-files/waybar" "$C/waybar"
snap "$T/s0"; : > "$MOCK_LOG"
ARCHENEMY_TEST=1 ARCHENEMY_NIX_STORE="$ST" RICE_NAME=alfa SWITCH_RICE_LINK_ONLY=1 bash "$LIB" 2>"$T/err"; rc=$?
snap "$T/s1"
check "link-only: kod 3, bez powiadomienia"       '[[ $rc -eq 3 ]] && cmp -s "$T/s0" "$T/s1" && [[ ! -s "$MOCK_LOG" ]] && [[ "$(<"$ST/eeee-hm-files/waybar/config")" == hm ]]'
switch alfa; rc=$?
check "ten sam link bez haka = zwykły cudzy link (.bak, kod 0)" '[[ $rc -eq 0 && "$(readlink "$C/waybar")" == "$A/rices/alfa/waybar" ]] && ls -d "$C"/waybar.bak-* >/dev/null 2>&1'

echo "== Super+T bez konfliktu: dawne zachowanie"
reset_home; : > "$MOCK_LOG"
switch alfa; rc=$?
check "kod 0, linki alfa, rofi (beta) sprzątnięty, .current_rice" '[[ $rc -eq 0 && "$(readlink "$C/hypr")" == "$A/rices/alfa/hypr" && ! -e "$C/rofi" && "$(<"$A/.current_rice")" == alfa ]]'
check "zwykły przebieg: reload i powiadomienie"   'grep -q "^hyprctl: reload" "$MOCK_LOG" && grep -q "applied" "$MOCK_LOG"'

echo "== install.sh [9]: odmowa, powtórka (idempotencja), potem linkowanie"
S9=$(grep -n '^# ─── 9. SYMLINKS' "$REPO/install/install.sh" | cut -d: -f1)
E9=$(grep -n '^# ─── 9.5 SCRIPTS' "$REPO/install/install.sh" | cut -d: -f1)
sed -n "${S9},$((E9-1))p" "$REPO/install/install.sh" > "$T/step9.sh"
check "wycinek [9] znaleziony"                    '[[ -n "$S9" && -n "$E9" && -s "$T/step9.sh" ]]'
run_step9() {
    ARCHENEMY_DIR="$A" RICES_DIR="$A/rices" CONFIG_DIR="$C" CURRENT_RICE="$A/.current_rice" \
    TARGET_RICE="$1" GREEN='' NC='' YELLOW='' BLUE='' CYAN='' RED='' \
    bash -c 'declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=(); source "$1"
             printf "DONE=%s\n" "${SUMMARY_DONE[@]}" > "$2"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}" >> "$2"' \
        _ "$T/step9.sh" "$T/summary" 2>&1
}
reset_home
ln -s /nix/store/ffff-home-manager-files/.config/waybar "$C/waybar"
snap "$T/s0"; : > "$MOCK_LOG"
out1="$(run_step9 alfa)"; cp "$T/summary" "$T/sum1"; snap "$T/s1"
check "⚠ z nazwą ścieżki"                         '[[ "$out1" == *"⚠ ~/.config/waybar is managed by home-manager (link into /nix/store), left as it is."* ]]'
check "porada w wyjściu"                          '[[ "$out1" == *"Remove those entries from your home-manager configuration"* ]]'
check "bez ✓ i bez komunikatu o błędzie biblioteki" '[[ "$out1" != *"✓"* && "$out1" != *"lib/switch-rice.sh failed"* && "$out1" != *"was kept as"* ]]'
check "podsumowanie: SKIPPED z poradą, bez DONE"  'grep -q "^SKIPPED=Rice .alfa. NOT linked: home-manager manages ~/.config/waybar" "$T/sum1" && ! grep -q "^DONE=Rice" "$T/sum1" && ! grep -q "NOT fully linked" "$T/sum1"'
check "~/.config i .current_rice bez zmian"       'cmp -s "$T/s0" "$T/s1" && [[ ! -s "$MOCK_LOG" ]]'
out2="$(run_step9 alfa)"; snap "$T/s2"
check "powtórny bieg: to samo wyjście i stan"     '[[ "$out1" == "$out2" ]] && cmp -s "$T/summary" "$T/sum1" && cmp -s "$T/s0" "$T/s2"'
rm "$C/waybar"   # użytkownik usunął deklarację HM i zrobił home-manager switch
out3="$(run_step9 alfa)"
check "po usunięciu deklaracji: linki i DONE"     '[[ "$(readlink "$C/waybar")" == "$A/rices/alfa/waybar" && "$out3" == *"✓ ~/.config/waybar → "* ]] && grep -q "^DONE=Rice .alfa. symlinked" "$T/summary"'
n_bak=$(find "$C" -maxdepth 1 -name '*.bak-*' | wc -l)
out4="$(run_step9 alfa)"
check "trzeci bieg: bez nowych .bak, linki te same" '[[ $(find "$C" -maxdepth 1 -name "*.bak-*" | wc -l) -eq $n_bak && "$(readlink "$C/hypr")" == "$A/rices/alfa/hypr" && "$out4" != *"was kept as"* ]]'

echo "== ~/.bashrc z home-managera"
# shellcheck source=scripts/shell/lib/shell-rc.sh
ARCHENEMY_DIR="$A" source "$REPO/scripts/shell/lib/shell-rc.sh"
mkdir -p "$A/config/shell"
rm -f "$HOME/.bashrc"; ln -s /nix/store/gggg-home-manager-files/.bashrc "$HOME/.bashrc"
res="$(rc_block_ensure "$HOME/.bashrc" bash 2>"$T/err")"; rc=$?
check "rc_block_ensure: managed, kod 1"           '[[ "$res" == managed && $rc -eq 1 ]]'
check "bez kopii i bez zmiany linku"              '! ls "$HOME"/.bashrc.bak-* >/dev/null 2>&1 && [[ ! -s "$T/err" && "$(readlink "$HOME/.bashrc")" == /nix/store/gggg-home-manager-files/.bashrc ]]'
rm -f "$HOME/.bashrc"; ln -s "$T/dot/bashrc-chain" "$HOME/.bashrc"; ln -sf /nix/store/hhhh/.bashrc "$T/dot/bashrc-chain"
check "łańcuch do sklepu: managed"                '[[ "$(rc_block_ensure "$HOME/.bashrc" bash 2>/dev/null)" == managed ]]'
mkdir -p "$ST/iiii-hm-files"; { echo "# from home-manager"; rc_block_text bash; } > "$ST/iiii-hm-files/bashrc"
rm -f "$HOME/.bashrc"; ln -s "$ST/iiii-hm-files/bashrc" "$HOME/.bashrc"
check "plik HM z aktualnym blokiem: ok"           '[[ "$(ARCHENEMY_TEST=1 ARCHENEMY_NIX_STORE="$ST" rc_block_ensure "$HOME/.bashrc" bash 2>/dev/null)" == ok ]]'
printf '%s\n' "alias ll='ls -l'" > "$ST/iiii-hm-files/bashrc"
cp "$ST/iiii-hm-files/bashrc" "$T/hm-bashrc.before"
check "plik HM bez bloku: managed, treść bez zmian" '[[ "$(ARCHENEMY_TEST=1 ARCHENEMY_NIX_STORE="$ST" rc_block_ensure "$HOME/.bashrc" bash 2>/dev/null)" == managed ]] && cmp -s "$ST/iiii-hm-files/bashrc" "$T/hm-bashrc.before"'
shellrc_ensure >/dev/null; cp "$SHELLRC" "$T/shellrc.before"
check "rc_migrate_apply odmawia, shellrc bez zmian" '! ARCHENEMY_TEST=1 ARCHENEMY_NIX_STORE="$ST" rc_migrate_apply "$HOME/.bashrc" >/dev/null 2>&1 && cmp -s "$SHELLRC" "$T/shellrc.before" && cmp -s "$ST/iiii-hm-files/bashrc" "$T/hm-bashrc.before"'
check "bez haka ten sam plik = zwykły link: migracja działa" 'n="$(rc_migrate_apply "$HOME/.bashrc" 2>/dev/null)" && [[ "$n" -ge 1 ]] && grep -qF "alias ll=" "$SHELLRC"'
rm -f "$HOME/.bashrc"; echo '# stow' > "$T/dot/bashrc-stow"; ln -s "$T/dot/bashrc-stow" "$HOME/.bashrc"
check "zwykły symlink (stow): blok dopisany przez link jak dotąd" '[[ "$(rc_block_ensure "$HOME/.bashrc" bash 2>/dev/null)" == added && -L "$HOME/.bashrc" ]] && grep -qxF "$SHELL_BLOCK_BEGIN" "$T/dot/bashrc-stow"'

echo "== install.sh [8m]: ~/.bashrc z home-managera"
S8=$(grep -n '^SHELL_BAK_FILE="$(mktemp)"' "$REPO/install/install.sh" | cut -d: -f1)
E8=$(awk -v s="$S8" 'NR > s && /^esac$/ { print NR; exit }' "$REPO/install/install.sh")
sed -n "${S8},${E8}p" "$REPO/install/install.sh" > "$T/step8m.sh"
check "wycinek [8m] znaleziony"                   '[[ -n "$S8" && -n "$E8" ]] && grep -q "managed)" "$T/step8m.sh"'
rm -f "$HOME/.bashrc"; ln -s /nix/store/jjjj-home-manager-files/.bashrc "$HOME/.bashrc"
n_rcbak=$(find "$HOME" -maxdepth 1 -name '.bashrc.bak-*' | wc -l)
out="$(ARCHENEMY_DIR="$A" BASHRC="$HOME/.bashrc" GREEN='' NC='' YELLOW='' RED='' bash -c '
    declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=(); source "$1"; source "$2"
    printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}"' _ "$REPO/scripts/shell/lib/shell-rc.sh" "$T/step8m.sh" 2>&1)"
check "⚠ i blok do programs.bash.initExtra"       '[[ "$out" == *"~/.bashrc is managed by home-manager"* && "$out" == *"programs.bash.initExtra"* && "$out" == *"# >>> archenemy shell >>>"* ]]'
check "podsumowanie bez fałszywego "broken block"" '[[ "$out" == *"SKIPPED=Your ~/.bashrc comes from home-manager"* && "$out" != *"without its end"* ]]'
check "bez nowej kopii w HOME"                    '[[ $(find "$HOME" -maxdepth 1 -name ".bashrc.bak-*" | wc -l) -eq $n_rcbak ]]'

echo "== install.sh [8l]: ~/.config/mpd z home-managera"
SM=$(grep -n '^    MPD_USER_DIR="$CONFIG_DIR/mpd"' "$REPO/install/install.sh" | cut -d: -f1)
EM=$(grep -n '^    # >>> 8l: usługa mpd' "$REPO/install/install.sh" | cut -d: -f1)
sed -n "${SM},$((EM-1))p" "$REPO/install/install.sh" > "$T/step8l.sh"
check "wycinek [8l] znaleziony"                   '[[ -n "$SM" && -n "$EM" && -s "$T/step8l.sh" ]]'
run_mpd() {
    ARCHENEMY_DIR="$A" CONFIG_DIR="$C" MPD_CONF_DIR="$A/config/mpd" GREEN='' NC='' YELLOW='' RED='' \
    bash -c 'declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=(); source "$1"
             printf "DONE=%s\n" "${SUMMARY_DONE[@]}"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}"' _ "$T/step8l.sh" 2>&1
}
mkdir -p "$A/config/mpd"; reset_home
mkdir -p "$C/mpd"; ln -s /nix/store/kkkk-home-manager-files/.config/mpd/mpd.conf "$C/mpd/mpd.conf"
snap "$T/s0"
out="$(printf 'y\n' | run_mpd)"; snap "$T/s1"
check "bez pytania o podmianę (y nieużyte), ⚠ i SKIPPED" '[[ "$out" != *"You already have an mpd config"* && "$out" == *"~/.config/mpd/mpd.conf is managed by home-manager"* && "$out" == *"SKIPPED=mpd config NOT linked: home-manager manages"* ]]'
check "~/.config/mpd bez zmian, bez .bak"         'cmp -s "$T/s0" "$T/s1"'
rm "$C/mpd/mpd.conf"; echo own > "$C/mpd/mpd.conf"
out="$(printf 'n\n' | run_mpd)"
check "zwykły katalog: dawne pytanie (n → zostaje)" '[[ "$out" == *"You already have an mpd config"* && "$out" == *"Keeping your mpd config"* ]]'

echo "== install.sh: ~/archenemy w sklepie Nix"
H3="$T/home3"; mkdir -p "$H3" "$ST/llll-archenemy/rices" "$ST/llll-archenemy/packages"
ln -s "$ST/llll-archenemy" "$H3/archenemy"
sed 's/^if \[\[ \$EUID -eq 0 \]\]; then$/if false; then  # tests\/hm-conflict.sh: bieg jako root/' "$REPO/install/install.sh" > "$T/install.sh"
out="$(HOME="$H3" ARCHENEMY_TEST=1 ARCHENEMY_NIX_STORE="$ST" bash "$T/install.sh" </dev/null 2>&1)"; rc=$?
check "kod 1 z wyjaśnieniem"                      '[[ $rc -eq 1 && "$out" == *"points into $ST, which is read-only"* ]]'
check "nic nie zapisane (HOME i checkout)"        '[[ "$(find "$H3" "$ST/llll-archenemy" -mindepth 1 | wc -l)" -eq 3 ]]'

echo "== izolacja"
if escaped="$(test_escapes "$T")"; then ok "zero zapisów poza \$T w: $(test_isolation_dirs)"
elif [[ $? == 2 ]]; then echo "  – izolacja niedostępna (unshare/overlay)"
else fail "zapisy poza \$T: ${escaped//$'\n'/ }"; fi
echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
