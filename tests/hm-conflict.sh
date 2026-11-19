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
#       instalatora [8m] wypisuje blok do programs.bash.initExtra; cały [8m]
#       (aż do ALIAS_STATE i SHELL_MOVABLE) oraz [h] migrate ze starym aliasem
#       w pliku HM: bez kopii, bez aliasu w shellrc, plik HM bez zmian (L1);
#     - ~/.config/mpd z plikiem HM: bez pytania o podmianę, wpis w podsumowaniu;
#     - ~/archenemy w sklepie: install.sh odmawia (kod 1) przed zapisem.
#   Opcja: HM_CONFLICT_REV=<rewizja> — cały [8m] z dawnym aliasem w zwykłym
#   ~/.bashrc (Arch, bez HM) porównany z rewizją bajt w bajt.
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

echo "== Super+T: tryb 'tylko linki' i atrapa sklepu z treścią"
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
check "podsumowanie bez fałszywego broken block" '[[ "$out" == *"SKIPPED=Your ~/.bashrc comes from home-manager"* && "$out" != *"without its end"* ]]'
check "bez nowej kopii w HOME"                    '[[ $(find "$HOME" -maxdepth 1 -name ".bashrc.bak-*" | wc -l) -eq $n_rcbak ]]'

# L1 (przegląd D8–D10): dawny wycinek kończył się na pierwszym `esac`, a cały
# [8m] idzie dalej do ALIAS_STATE i migracji starego aliasu. Plik HM z dawnym
# znacznikiem aliasu nie może dostać kopii ani zmiany, a shellrc — aliasu.
echo "== install.sh cały [8m] i Super+A → [h]: stary alias w ~/.bashrc z home-managera"
ARCHENEMY_DIR="$A"   # archenemy_alias_line w atrapie i przy przeniesieniu
S8A=$(grep -n '^APPBINDS_SH="$ARCHENEMY_DIR/scripts/appbinds/appbinds.sh"' "$REPO/install/install.sh" | cut -d: -f1)
E8A=$(grep -n '^SUMMARY_DONE+=("Machine-local configs generated' "$REPO/install/install.sh" | cut -d: -f1)
[[ -n "$S8A" && -n "$E8A" ]] && sed -n "${S8A},$((E8A-1))p" "$REPO/install/install.sh" > "$T/step8m-all.sh"
check "cały [8m] znaleziony (blok rc, ALIAS_STATE, migracja aliasu)" '[[ -n "$S8A" && -n "$E8A" ]] && grep -q "^ALIAS_STATE=" "$T/step8m-all.sh" && grep -q "archenemy_alias_move" "$T/step8m-all.sh" && grep -q "^SHELL_MOVABLE=" "$T/step8m-all.sh"'
hm_alias_fixture() {   # $1 = znacznik; plik HM: aktualny blok + alias dawnego [8m]
    mkdir -p "$ST/mmmm-hm-files"
    { echo "# from home-manager"; rc_block_text bash; echo ""; echo "$1"; archenemy_alias_line; } > "$ST/mmmm-hm-files/bashrc"
    cp "$ST/mmmm-hm-files/bashrc" "$T/hm-alias.before"
    rm -f "$HOME/.bashrc" "$HOME"/.bashrc.bak-*; ln -s "$ST/mmmm-hm-files/bashrc" "$HOME/.bashrc"
    rm -f "$SHELLRC" "$SHELLRC".bak-*; shellrc_ensure >/dev/null; cp "$SHELLRC" "$T/shellrc-alias.before"
}
hm_alias_untouched() {
    cmp -s "$ST/mmmm-hm-files/bashrc" "$T/hm-alias.before" && cmp -s "$SHELLRC" "$T/shellrc-alias.before" \
        && ! ls "$HOME"/.bashrc.bak-* "$SHELLRC".bak-* >/dev/null 2>&1 && [[ "$(readlink "$HOME/.bashrc")" == "$ST/mmmm-hm-files/bashrc" ]]
}
HM_STAYS="managed by home-manager: the old 'archenemy' alias stays there"
HM_SKIP="SKIPPED='archenemy' command stays in your home-manager ~/.bashrc"
hm_alias_fixture "$ARCHENEMY_ALIAS_MARK_OLD"
res="$(ARCHENEMY_TEST=1 ARCHENEMY_NIX_STORE="$ST" archenemy_alias_move "$HOME/.bashrc" 2>&1)"; rc=$?
check "archenemy_alias_move na pliku HM: kod 2, bez kopii, rc i shellrc bez zmian" '[[ $rc -eq 2 && -z "$res" ]] && hm_alias_untouched'
for mark in "$ARCHENEMY_ALIAS_MARK_OLD" "$ARCHENEMY_ALIAS_MARK"; do
    hm_alias_fixture "$mark"
    out="$(ARCHENEMY_DIR="$A" BASHRC="$HOME/.bashrc" ZSHRC="$HOME/.zshrc" ARCHENEMY_TEST=1 ARCHENEMY_NIX_STORE="$ST" \
        GREEN='' NC='' YELLOW='' RED='' bash -c '
        declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=(); source "$1"; source "$2"
        printf "DONE=%s\n" "${SUMMARY_DONE[@]}"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}"' _ "$REPO/scripts/shell/lib/shell-rc.sh" "$T/step8m-all.sh" </dev/null 2>&1)"
    check "[8m] (${mark##*) }): plik HM, shellrc i HOME bez kopii i zmian" 'hm_alias_untouched'
    check "[8m] (${mark##*) }): ⚠ zamiast ✓ przeniesienia, wpis w podsumowaniu" '[[ "$out" == *"$HM_STAYS"* && "$out" != *"moved to the shared file"* && "$out" == *"$HM_SKIP"* && "$out" != *"DONE='"'"'archenemy'"'"' command moved"* && "$out" != *"stay bash-only until you move them"* ]]'
done
hm_alias_fixture "$ARCHENEMY_ALIAS_MARK_OLD"
printf 'ID=arch\n' > "$T/os-arch"
out="$(ARCHENEMY_DIR="$A" ARCHENEMY_TEST=1 ARCHENEMY_NIX_STORE="$ST" ARCHENEMY_OS_RELEASE="$T/os-arch" \
    bash "$REPO/scripts/shell/shell-settings.sh" migrate </dev/null 2>&1)"
check "Super+A → [h] migrate: blok w HM aktualny, alias zostaje, bez kopii i zmian" 'hm_alias_untouched && [[ "$out" == *"$HM_STAYS"* && "$out" != *"moved to your shared file"* ]]'
rm -f "$HOME/.bashrc"; { echo "# stow"; echo ""; echo "$ARCHENEMY_ALIAS_MARK_OLD"; archenemy_alias_line; } > "$T/dot/bashrc-legacy"
ln -s "$T/dot/bashrc-legacy" "$HOME/.bashrc"
check "zwykły symlink ze starym aliasem: przeniesienie jak dotąd" 'bak="$(archenemy_alias_move "$HOME/.bashrc")" && [[ -f "$bak" ]] && ! grep -q "^alias archenemy=" "$T/dot/bashrc-legacy" && grep -qxF "$ARCHENEMY_ALIAS_MARK" "$SHELLRC"'
rm -f "$HOME/.bashrc" "$HOME"/.bashrc.bak-*

# L5 (przegląd D8–D10): parytet Archa dla całego [8m] z dawnym aliasem
# w zwykłym ~/.bashrc — wyjście, DONE/SKIPPED, ~/.bashrc, shellrc i liczba
# kopii jak w rewizji (HM_CONFLICT_REV=<rewizja>, np. baza gałęzi).
if [[ -n "${HM_CONFLICT_REV:-}" ]]; then
    echo "== parytet Archa: cały [8m], dawny alias w zwykłym ~/.bashrc = $HM_CONFLICT_REV"
    PB="$T/parity-base"; mkdir -p "$PB"
    git -C "$REPO" show "$HM_CONFLICT_REV:install/install.sh" > "$PB/install.sh" \
        && git -C "$REPO" show "$HM_CONFLICT_REV:scripts/shell/lib/shell-rc.sh" > "$PB/shell-rc.sh" || exit 1
    slice8m() {
        local s e
        s=$(grep -n '^APPBINDS_SH="$ARCHENEMY_DIR/scripts/appbinds/appbinds.sh"' "$1" | cut -d: -f1)
        e=$(grep -n '^SUMMARY_DONE+=("Machine-local configs generated' "$1" | cut -d: -f1)
        # Biblioteka danej rewizji wczytana wcześniej (p8m); `source` z wycinka
        # wskazywałby na nieistniejące $A/scripts — usuwamy go po obu stronach.
        [[ -n "$s" && -n "$e" ]] && sed -n "${s},$((e-1))p" "$1" | grep -vxF 'source "$ARCHENEMY_DIR/scripts/shell/lib/shell-rc.sh"'
    }
    slice8m "$PB/install.sh" > "$T/p8m-base.sh"; slice8m "$REPO/install/install.sh" > "$T/p8m-cur.sh"
    p8m() {   # p8m <shell-rc.sh> <wycinek> → wyjście i stan po biegu (znaczniki czasu kopii znormalizowane)
        rm -rf "$HOME/.bashrc" "$HOME"/.bashrc.bak-* "$SHELLRC" "$SHELLRC".bak-* "$HOME/.local/share/applications/archenemy.desktop"
        { echo "# my bashrc"; echo "alias ll='ls -l'"; echo ""; echo "$ARCHENEMY_ALIAS_MARK_OLD"; archenemy_alias_line; } > "$HOME/.bashrc"
        ARCHENEMY_DIR="$A" BASHRC="$HOME/.bashrc" ZSHRC="$HOME/.zshrc" GREEN='' NC='' YELLOW='' RED='' bash -c '
            declare -a SUMMARY_DONE=() SUMMARY_SKIPPED=(); source "$1"; source "$2"
            printf "DONE=%s\n" "${SUMMARY_DONE[@]}"; printf "SKIPPED=%s\n" "${SUMMARY_SKIPPED[@]}"' _ "$1" "$2" </dev/null 2>&1
        echo "--- ~/.bashrc"; cat "$HOME/.bashrc"; echo "--- shellrc"; cat "$SHELLRC"
        echo "--- kopie: $(find "$HOME" "$(dirname "$SHELLRC")" -maxdepth 1 -name '*.bak-*' | wc -l)"
    }
    norm8m() { sed -E 's/\.bak-[0-9]{8}_[0-9]{6}(-[0-9]+)?/.bak-<ts>/g'; }
    p_base="$(p8m "$PB/shell-rc.sh" "$T/p8m-base.sh" | norm8m)"
    p_cur="$(p8m "$REPO/scripts/shell/lib/shell-rc.sh" "$T/p8m-cur.sh" | norm8m)"
    check "Arch [8m] z dawnym aliasem = $HM_CONFLICT_REV (wyjście, podsumowanie, rc, shellrc, kopie)" '[[ -s "$T/p8m-base.sh" && "$p_base" == "$p_cur" && "$p_cur" == *"moved to the shared file"* ]]'
    [[ "$p_base" == "$p_cur" ]] || diff <(printf '%s\n' "$p_base") <(printf '%s\n' "$p_cur") | head -20
    rm -rf "$HOME/.bashrc" "$HOME"/.bashrc.bak-* "$SHELLRC".bak-* "$HOME/.local/share/applications/archenemy.desktop"
fi

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
