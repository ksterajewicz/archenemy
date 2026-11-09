#!/bin/bash
# =============================================
#   archenemy - tests/shell-plugins.sh
#   Wtyczki zsh: stan, zapis, kopie i TUI na atrapach pacman/chsh.
#   Zsh nie jest wymagany. Wykonanie loadera w bashu testuje źródła i guardy;
#   fazę fpath i położenie względem compinit sprawdzamy osobno statycznie.
# =============================================
# shellcheck disable=SC1091,SC2016  # biblioteka z repo, dosłowne skrypty atrap
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" ARCHENEMY_DIR="$T/home/archenemy"
mkdir -p "$ARCHENEMY_DIR/config/shell" "$ARCHENEMY_DIR/scripts" "$T/bin"
cp -r "$REPO/scripts/shell" "$REPO/scripts/appbinds" "$ARCHENEMY_DIR/scripts/"
cp "$REPO/config/shell/"*.zsh "$ARCHENEMY_DIR/config/shell/"
source "$REPO/scripts/shell/lib/shell-rc.sh"
PASS=0; FAIL=0
check() {
    if "${@:2}"; then PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"
    else FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; fi
}
S="$ARCHENEMY_DIR/scripts/shell/shell-settings.sh"
export MOCK_ROOT="$T"
cat > "$T/bin/pacman" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_ROOT/pacman-log"
case "$1" in
    -Q) grep -qxF "$2" "$MOCK_ROOT/packages" ;;
    -S)
        [[ ! -e "$MOCK_ROOT/fail" ]] || exit 1
        [[ -e "$MOCK_ROOT/ghost" ]] || printf '%s\n' "$3" >> "$MOCK_ROOT/packages"
        ;;
    *) exit 1 ;;
esac
MOCK
cat > "$T/bin/sudo" <<'MOCK'
#!/bin/bash
"$@"
MOCK
cat > "$T/bin/getent" <<'MOCK'
#!/bin/bash
printf 'test:x:1000:1000::%s:%s\n' "$HOME" "$(cat "$MOCK_ROOT/passwd")"
MOCK
cat > "$T/bin/chsh" <<'MOCK'
#!/bin/bash
[[ ! -e "$MOCK_ROOT/chsh-fail" ]] || exit 1
printf '%s\n' "$2" > "$MOCK_ROOT/passwd"
MOCK
printf '#!/bin/bash\nexit 0\n' > "$T/bin/clear"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/zsh"
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" SHELL=/bin/bash ARCHENEMY_SHELLS_FILE="$T/shells"
printf '/bin/bash\n%s/bin/zsh\n' "$T" > "$T/shells"
printf '/bin/bash\n' > "$T/passwd"
: > "$T/packages"
: > "$T/pacman-log"
run() { printf '%b' "$1" | timeout 10 bash "$S" 2>&1; }

check 'domyślnie brak pliku i wszystkie wyłączone' test ! -e "$SHELL_PLUGINS"
for name in "${SHELL_PLUGIN_NAMES[@]}"; do
    if shell_plugin_enabled "$name"; then check 'domyślnie wyłączona' false; fi
done
OUT="$(run '5\e')"
check 'checklista ma trzy opisy, recommended i Space/Enter' bash -c '[[ "$1" == *"[ ] zsh-autosuggestions"* && "$1" == *recommended* && "$1" == *"colors valid and invalid commands"* && "$1" == *"additional command completions"* && "$1" == *"Space/Enter: toggle"* ]]' _ "$OUT"
check 'Esc nie zapisuje ustawień' test ! -e "$SHELL_PLUGINS"
OUT="$(run '5 \nn')"
check 'Enter na instalacji domyślnie odmawia' test ! -e "$SHELL_PLUGINS"
check 'pokazano komendę instalacji' bash -c '[[ "$1" == *"sudo pacman -S --needed zsh-autosuggestions"* ]]' _ "$OUT"
check 'instalacja domyślnie N' grep -qF 'confirm "Install ${plugin}?" N' "$S"
check 'bez zgody brak transakcji' bash -c '! grep -q -- "^-S" "$1"' _ "$T/pacman-log"
OUT="$(run '5 y')"
check 'Spacja i zgoda instalują oraz zapisują stan' shell_plugin_enabled zsh-autosuggestions
check 'pacman dostał dokładnie żądaną transakcję' grep -qxF -- '-S --needed zsh-autosuggestions' "$T/pacman-log"
check 'włączenie zapewnia blok zshrc' grep -qF 'zsh-defaults.zsh' "$HOME/.zshrc"
cp "$SHELL_PLUGINS" "$T/first"
check 'identyczny zapis no-op' test "$(shell_plugin_write zsh-autosuggestions 1)" = unchanged
check 'idempotencja bez kopii' bash -c '! compgen -G "$1.bak-*" >/dev/null' _ "$SHELL_PLUGINS"
OUT="$(run '5\n')"
check 'Enter wyłącza zaznaczoną wtyczkę' bash -c 'source "$1"; ! shell_plugin_enabled zsh-autosuggestions' _ "$REPO/scripts/shell/lib/shell-rc.sh"
check 'kopia zawiera poprzedni stan' bash -c 'for file in "$1".bak-*; do cmp -s "$file" "$2" && exit 0; done; exit 1' _ "$SHELL_PLUGINS" "$T/first"
check 'pakiet zostaje po wyłączeniu' grep -qxF zsh-autosuggestions "$T/packages"
OUT="$(run '5jj y')"
check 'j/j i Space włączają completions' shell_plugin_enabled zsh-completions
OUT="$(run '5\e[B y')"
check 'strzałka i Space włączają highlighting' shell_plugin_enabled zsh-syntax-highlighting
OUT="$(run '5\e[A\n')"
check 'strzałka w górę zawija i Enter wyłącza completions' bash -c 'source "$1"; ! shell_plugin_enabled zsh-completions' _ "$REPO/scripts/shell/lib/shell-rc.sh"
OUT="$(bash "$S" summary)"
check 'summary wymienia aktywną wtyczkę' bash -c '[[ "$1" == *"plugins: zsh-syntax-highlighting"* ]]' _ "$OUT"

# Awaria pacman i pozorny sukces nie mogą włączyć brakującego pakietu.
cp "$SHELL_PLUGINS" "$T/before-failure"
sed -i '/^zsh-completions$/d' "$T/packages"
touch "$T/fail"
OUT="$(run '5jj yx')"
check 'błąd instalacji zostawia stan' cmp -s "$SHELL_PLUGINS" "$T/before-failure"
check 'błąd instalacji jest widoczny' bash -c '[[ "$1" == *"was not installed"* ]]' _ "$OUT"
rm "$T/fail"
touch "$T/ghost"
OUT="$(run '5jj yx')"
check 'kod zero bez pacman -Q nie oznacza sukcesu' cmp -s "$SHELL_PLUGINS" "$T/before-failure"
rm "$T/ghost"

# Po chsh domyślne Y poleca wtyczkę, lecz transakcja nadal wymaga y/N.
sed -i '/^zsh-autosuggestions$/d' "$T/packages"
OUT="$(run '22y\nn')"
check 'po zmianie na zsh Enter proponuje osobną instalację' bash -c '[[ "$1" == *"Login shell: zsh"* && "$1" == *"sudo pacman -S --needed zsh-autosuggestions"* ]]' _ "$OUT"
check 'odmowa domyślnej rekomendacji nie zmienia stanu' cmp -s "$SHELL_PLUGINS" "$T/before-failure"
printf '/bin/bash\n' > "$T/passwd"
OUT="$(run '22y\ny')"
check 'Enter akceptuje rekomendację, osobne y instaluje' shell_plugin_enabled zsh-autosuggestions

# TUI i writer nie wykonują danych ani nie zastępują cudzej konfiguracji.
printf 'touch "%s/pwned"\n' "$T" >> "$SHELL_PLUGINS"
cp "$SHELL_PLUGINS" "$T/custom"
OUT="$(run '5 x')"
check 'ręcznie zmieniony plik zachowany' cmp -s "$SHELL_PLUGINS" "$T/custom"
check 'ostrzeżenie o obcej treści' bash -c '[[ "$1" == *"contains custom content"* ]]' _ "$OUT"
check 'stan nigdy nie jest eval/source w TUI' test ! -e "$T/pwned"
check 'biblioteka odmawia nadpisania obcej treści' bash -c 'source "$1"; ! shell_plugin_write zsh-autosuggestions 0' _ "$REPO/scripts/shell/lib/shell-rc.sh"
cp "$T/before-failure" "$SHELL_PLUGINS"
shell_plugin_write zsh-autosuggestions 1 >/dev/null 2>&1
shell_plugin_write zsh-completions 1 >/dev/null 2>&1
check 'nieznana wtyczka odrzucona' bash -c 'source "$1"; ! shell_plugin_write bogus 1' _ "$REPO/scripts/shell/lib/shell-rc.sh"

# Atrapy źródeł: wykonujemy faktyczne wygenerowane warunki, zmieniając tylko prefix.
mkdir -p "$T/share/zsh/plugins/zsh-autosuggestions" "$T/share/zsh/plugins/zsh-syntax-highlighting"
printf 'echo suggestions >> "$MOCK_ROOT/load-order"\n' > "$T/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
printf 'echo highlighting >> "$MOCK_ROOT/load-order"\n' > "$T/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
sed "s|/usr/share/|$T/share/|g" "$SHELL_PLUGINS" > "$T/loader"
check 'loader parsuje się bez zsh' bash -n "$T/loader"
check 'loader działa na atrapach i zachowuje zmienne użytkownika' bash -c 'ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE=custom; source "$1"; [[ "$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE" == custom ]]' _ "$T/loader"
check 'highlighting ładuje się po autosuggestions' test "$(cat "$T/load-order")" = $'suggestions\nhighlighting'
rm -r "$T/share"
check 'brak plików pakietu nie powoduje błędu startu' bash -c 'source "$1"' _ "$T/loader"
check 'fpath jest przed ładowaniem widgetów' awk '/fpath\+=/ { a=NR } /source .*zsh-autosuggestions/ { b=NR } /source .*zsh-syntax-highlighting/ { c=NR } END { exit !(a && a < b && b < c) }' "$SHELL_PLUGINS"
check 'defaults rejestruje completions przed compinit, widgety na końcu' awk '/archenemy_plugins_phase=completion/ { a=NR } /compinit -d/ { b=NR } /source .*plugins.zsh/ { c=NR } END { exit !(a && a < b && b < c) }' "$REPO/config/shell/zsh-defaults.zsh"
check 'plugins jest ignorowany przez git' git -C "$REPO" check-ignore -q config/shell/plugins.zsh
check 'backup jest ignorowany przez git' git -C "$REPO" check-ignore -q config/shell/plugins.zsh.bak-20260101
printf '\nWynik: %s ✓ / %s ✗\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
