#!/bin/bash
# =============================================
#   archenemy - tests/shell-cli-tools.sh
#   Katalog, bloki i nawigacja CLI na atrapach, bez zsh/pacman/narzędzi.
# =============================================
# shellcheck disable=SC1091,SC2016  # źródło z repo, dosłowny kod atrap
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1
export HOME="$T/home" ARCHENEMY_DIR="$T/home/archenemy" MOCK_ROOT="$T"
mkdir -p "$ARCHENEMY_DIR/config/shell" "$ARCHENEMY_DIR/scripts" "$T/bin"
cp -r "$REPO/scripts/shell" "$REPO/scripts/appbinds" "$ARCHENEMY_DIR/scripts/"
cp "$REPO/config/shell/cli-tools-v1.tsv" "$ARCHENEMY_DIR/config/shell/"
cp "$REPO/config/shell/cli-tools.tsv" "$ARCHENEMY_DIR/config/shell/"
source "$REPO/scripts/shell/lib/shell-rc.sh"
PASS=0; FAIL=0
check() {
    if "${@:2}"; then PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"
    else FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; fi
}
# Izolowany PATH gwarantuje brak prawdziwych fd, rg, zoxide, zsh i pacman.
for cmd in bash awk cut dirname mktemp mkdir ln rm cat grep sed date cp chmod mv timeout tput stty wc basename getent id sha256sum; do
    real="$(command -v "$cmd")" || exit 1
    ln -s "$real" "$T/bin/$cmd"
done
cat > "$T/bin/pacman" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_ROOT/pacman-log"
[[ ! -e "$MOCK_ROOT/fail" ]] || exit 1
[[ ! -e "$MOCK_ROOT/ghost" ]] || exit 0
command="$3"; [[ "$command" == ripgrep ]] && command=rg
cp "$MOCK_ROOT/tool" "$MOCK_ROOT/bin/$command"
chmod +x "$MOCK_ROOT/bin/$command"
MOCK
cat > "$T/bin/sudo" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_ROOT/sudo-log"
"$@"
MOCK
cat > "$T/tool" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_ROOT/tool-log"
if [[ "${1:-}" == init ]]; then
    printf 'z() { :; }; zi() { :; }\n'
fi
MOCK
printf '#!/bin/bash\nexit 0\n' > "$T/bin/clear"
chmod +x "$T/bin/"{sudo,pacman,clear}
export PATH="$T/bin" SHELL=/bin/bash TERM=xterm
S="$ARCHENEMY_DIR/scripts/shell/shell-settings.sh"
run() { printf '%b' "$1" | timeout 10 bash "$S" 2>&1; }
check 'katalog czyta trzy narzędzia i puste inicjalizacje' shell_cli_load
check 'fd nie ma inicjalizacji' test "${CLI_BASH_INIT[0]}${CLI_ZSH_INIT[0]}" = ''
for kind in bash zsh; do
    for name in "${CLI_NAMES[@]}"; do
        check "domyślnie wyłączone $kind/$name" bash -c 'source "$1"; ! shell_cli_enabled "$2" "$3"' _ "$REPO/scripts/shell/lib/shell-rc.sh" "$kind" "$name"
    done
done
OUT="$(run 'jjjjj\nq')"
check 'cała droga do CLI strzałkami i q bez zapisu' bash -c '[[ "$1" == *"All choices start disabled"* && ! -e "$2" ]]' _ "$OUT" "$SHELL_RC_DIR/cli-tools.bash"
OUT="$(run '6\n\e')"
check 'lista pokazuje stan i licencje' bash -c '[[ "$1" == *"[ ] fd (MIT OR Apache-2.0)"* && "$1" == *"[ ] ripgrep (MIT OR Unlicense)"* && "$1" == *"[ ] zoxide (MIT)"* ]]' _ "$OUT"
OUT="$(run '6\n\nn')"
check 'odmowa bez zapisu i instalacji' bash -c '[[ ! -e "$1" && ! -e "$2" && ! -e "$3" ]]' _ "$SHELL_RC_DIR/cli-tools.bash" "$T/pacman-log" "$HOME/.bashrc"
check 'pytanie pokazuje polecenie i domyślne Y' bash -c '[[ "$1" == *"sudo pacman -S --needed fd"* && "$1" == *"[Y/n]"* ]]' _ "$OUT"
OUT="$(run '6\n\n\e')"
check 'Esc w zgodzie bez instalacji' test ! -e "$T/pacman-log"
OUT="$(run '6\n\n\n')"
check 'Enter zatwierdza instalację i włącza fd bash' shell_cli_enabled bash fd
check 'dokładna transakcja pacman' grep -qxF -- '-S --needed fd' "$T/pacman-log"
check 'sudo użyte jawnie' grep -qxF -- 'pacman -S --needed fd' "$T/sudo-log"
check 'rc ładuje osobisty plik bash' grep -qF 'cli-tools.bash' "$HOME/.bashrc"
cp "$SHELL_RC_DIR/cli-tools.bash" "$T/first"
check 'ponowny zapis no-op' test "$(shell_cli_write bash fd 1)" = unchanged
check 'no-op nie tworzy backupu' bash -c '! compgen -G "$1.bak-*" >/dev/null' _ "$SHELL_RC_DIR/cli-tools.bash"
check 'stan zsh pozostał wyłączony' bash -c 'source "$1"; ! shell_cli_enabled zsh fd' _ "$REPO/scripts/shell/lib/shell-rc.sh"
OUT="$(run '6\n\n')"
check 'Enter wyłącza i usuwa dokładny blok' bash -c '! grep -qF "archenemy CLI: fd" "$1"' _ "$SHELL_RC_DIR/cli-tools.bash"
check 'pakiet zostaje w PATH po wyłączeniu' command -v fd
check 'kopia zachowuje poprzedni stan' bash -c 'for f in "$1".bak-*; do cmp_data="$(cat "$f")"; [[ "$cmp_data" == "$(cat "$2")" ]] && exit 0; done; exit 1' _ "$SHELL_RC_DIR/cli-tools.bash" "$T/first"
OUT="$(run '6\n\n')"
check 'ponowne włączenie daje identyczną treść' test "$(cat "$SHELL_RC_DIR/cli-tools.bash")" = "$(cat "$T/first")"
OUT="$(run '6\e[B\n\n')"
check 'strzałka wybiera zsh niezależnie' shell_cli_enabled zsh fd
check 'zshrc ładuje osobisty plik zsh' grep -qF 'cli-tools.zsh' "$HOME/.zshrc"
OUT="$(run '6\n\e[B\ny')"
check 'strzałka wybiera ripgrep i sprawdza rg' shell_cli_enabled bash ripgrep
check 'pakiet ripgrep zamiast rg' grep -qxF -- '-S --needed ripgrep' "$T/pacman-log"
OUT="$(run '6\n\e[B\e[B\ny')"
check 'zoxide bash włączony' shell_cli_enabled bash zoxide
OUT="$(run '6j\njj\n')"
check 'j wybiera shell i narzędzie' shell_cli_enabled zsh zoxide
check 'loader bash i zsh ma poprawną składnię' bash -n "$SHELL_RC_DIR/cli-tools.bash" "$SHELL_RC_DIR/cli-tools.zsh"
for kind in bash zsh; do
    check "loader $kind działa bez zsh i nie rusza cd" bash -c 'cd() { : sentinel; }; before="$(declare -f cd)"; source "$1"; [[ "$(declare -f cd)" == "$before" ]] && declare -F z zi >/dev/null' _ "$SHELL_RC_DIR/cli-tools.$kind"
    check "init dostaje $kind" grep -qxF "init $kind" "$T/tool-log"
done
rm "$T/bin/zoxide"
check 'brak binarki nie psuje startu shella' bash -c 'source "$1"' _ "$SHELL_RC_DIR/cli-tools.bash"
check 'wyłączenie usuwa tylko wybrany blok' shell_cli_write bash ripgrep 0
check 'pozostały blok jest zachowany' shell_cli_enabled bash fd
check 'blok wyłączonego ripgrep zniknął' bash -c 'source "$1"; ! shell_cli_enabled bash ripgrep' _ "$REPO/scripts/shell/lib/shell-rc.sh"
# Nowy wiersz wystarcza, także gdy narzędzie obsługuje tylko jeden shell.
printf 'demo\thttps://example.org/demo\tMIT\tdemo\tdemo\tzsh\t\tprintf demo-loaded\\n\n' >> "$SHELL_RC_DIR/cli-tools.tsv"
OUT="$(run '6\nk\nq')"
check 'niewspierany shell pokazany i bez zmian' bash -c '[[ "$1" == *"[-] demo (MIT)"* && "$1" == *"Unavailable for bash: demo"* ]]' _ "$OUT"
check 'niewspierany shell odrzucony w bibliotece' bash -c 'source "$1"; ! shell_cli_write bash demo 1' _ "$REPO/scripts/shell/lib/shell-rc.sh"
OUT="$(run '6j\nk\ny')"
check 'nowy wiersz działa bez zmiany logiki' shell_cli_enabled zsh demo
check 'nowy init zapisany' grep -qF 'printf demo-loaded' "$SHELL_RC_DIR/cli-tools.zsh"
# Dawny plik bez sumy rozpoznajemy mimo zmiany inicjalizacji w nowym katalogu.
shell_cli_body bash > "$SHELL_RC_DIR/cli-tools.bash"
cp "$SHELL_RC_DIR/cli-tools.bash" "$T/legacy-cli"
sed -i 's/zoxide init bash/zoxide init bash --hook prompt/' "$SHELL_RC_DIR/cli-tools.tsv"
check 'stary katalog nie blokuje wyłączenia' shell_cli_write bash fd 0
check 'migracja zachowuje kopię starego pliku' bash -c 'for f in "$1".bak-*; do [[ "$(cat "$f")" == "$(cat "$2")" ]] && exit 0; done; exit 1' _ "$SHELL_RC_DIR/cli-tools.bash" "$T/legacy-cli"
# Podpisana stara treść pozostaje zarządzana także po usunięciu pozycji z katalogu.
sed -i '/^demo\t/d' "$SHELL_RC_DIR/cli-tools.tsv"
check 'usunięty wpis nie blokuje wyłączenia w podpisanym pliku' shell_cli_write zsh fd 0
check 'usunięte narzędzie znika przy regeneracji' bash -c '! grep -qF "archenemy CLI: demo" "$1"' _ "$SHELL_RC_DIR/cli-tools.zsh"
# Próby zapisu obcej treści i symlinku odrzucamy bez jej wykonania.
printf '\ntouch "$MOCK_ROOT/pwned"\n' >> "$SHELL_RC_DIR/cli-tools.zsh"
cp "$SHELL_RC_DIR/cli-tools.zsh" "$T/custom"
OUT="$(run '6j\n\nx')"
check 'obca treść nie jest wykonywana ani nadpisana' bash -c '[[ ! -e "$1" && "$(cat "$2")" == "$(cat "$3")" ]]' _ "$T/pwned" "$T/custom" "$SHELL_RC_DIR/cli-tools.zsh"
check 'TUI ostrzega o obcej treści' bash -c '[[ "$1" == *"custom content"* ]]' _ "$OUT"
rm "$SHELL_RC_DIR/cli-tools.zsh"
ln -s "$T/custom" "$SHELL_RC_DIR/cli-tools.zsh"
check 'symlink odrzucony' bash -c 'source "$1"; ! shell_cli_write zsh fd 1' _ "$REPO/scripts/shell/lib/shell-rc.sh"
# Nieudana instalacja albo pozorny sukces bez binarki nie włącza narzędzia.
shell_cli_write bash zoxide 0 >/dev/null 2>&1
for failure in fail ghost; do
    : > "$T/$failure"
    OUT="$(run '6\njj\nyx')"
    check "$failure: brak stanu po instalacji" bash -c 'source "$1"; ! shell_cli_enabled bash zoxide' _ "$REPO/scripts/shell/lib/shell-rc.sh"
    rm "$T/$failure"
done
# Git jest potrzebny wyłącznie do sprawdzenia ignorowania w prawdziwym repo.
/usr/bin/git -C "$REPO" check-ignore -q config/shell/cli-tools.bash &&
    /usr/bin/git -C "$REPO" check-ignore -q config/shell/cli-tools.zsh.bak-20260101
check 'osobiste pliki i kopie ignorowane' test "$?" = 0
printf '\nWynik: %s ✓ / %s ✗\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
