#!/usr/bin/env bash
# =============================================
#   archenemy - tests/shell-platforms.sh
#   Super+A → [h] (scripts/shell/shell-settings.sh) per platforma (D8):
#   wtyczki zsh, narzędzia CLI, zsh/chsh i podpowiedź neovim na Archu,
#   EndeavourOS (ID_LIKE=arch), Fedorze 44, NixOS, Ubuntu i bez
#   install/lib/pkg.sh. Platforma = jawny os-release (ARCHENEMY_OS_RELEASE
#   przy ARCHENEMY_TEST=1); pliki wtyczek pod ARCHENEMY_FS_ROOT.
#   Sprawdzamy, że nowe backendy nie obchodzą zgód: te same pytania i ich
#   domyślne odpowiedzi (wtyczki [y/N], CLI i zsh [Y/n]), stan dopiero po
#   potwierdzonym pakiecie + pliku/komendzie, Fedora tylko dnf z repozytoriów
#   Fedory (nigdy pacman, choć atrapa pacmana jest w PATH), pakiet bez RPM =
#   porada bez pytania, NixOS bez sudo/chsh/nix-env i bez „/bin/…” w poradach.
#   Izolowany PATH: atrapy sudo, pacman, dnf, rpm, chsh, getent, nvim,
#   nix-env, nix, nixos-rebuild zapisują każde wywołanie.
#   Opcje:
#     SHELL_PLATFORMS_SRC=<rewizja> — badany kod z tej rewizji (dowód, że
#       test pada na bazie);
#     SHELL_PLATFORMS_REV=<rewizja> — parytet Archa: scenariusze Archa także
#       na kodzie z rewizji; porównanie wyjścia, wywołań i plików HOME.
#   Uruchom: bash tests/shell-platforms.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval (zmienne żyją w eval); atrapy to dosłowny kod
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)" && [[ -n "$T" && -d "$T" && "$T" != / ]] || exit 1
trap 'rm -rf "${T:?}"' EXIT
test_environment_init "$T" || exit 1
ROOT_BEFORE="$(find / -mindepth 1 -maxdepth 1 2>/dev/null | sort)"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

H="$T/home"; A="$H/archenemy"; BIN="$T/bin"; ZBIN="$T/zbin"; FSROOT="$T/root"
export CALLS="$T/calls" ST="$T/state" ZBIN FSROOT
mkdir -p "$BIN" "$ZBIN" "$ST" "$T/os" "$T/src"

# ─── kod badany i (opcjonalnie) baza parytetu ────────────────────────────────
SRC="$REPO"
if [[ -n "${SHELL_PLATFORMS_SRC:-}" ]]; then
    SRC="$T/src/cur"; mkdir -p "$SRC"
    git -C "$REPO" archive "$SHELL_PLATFORMS_SRC" scripts config install packages | tar -x -C "$SRC" || { echo "✗ brak $SHELL_PLATFORMS_SRC"; exit 1; }
    echo "  (badany kod z rewizji $SHELL_PLATFORMS_SRC)"
fi
BASE=""
if [[ -n "${SHELL_PLATFORMS_REV:-}" ]]; then
    BASE="$T/src/base"; mkdir -p "$BASE"
    git -C "$REPO" archive "$SHELL_PLATFORMS_REV" scripts config | tar -x -C "$BASE" || { echo "✗ brak $SHELL_PLATFORMS_REV"; exit 1; }
    echo "  (parytet Archa z rewizją $SHELL_PLATFORMS_REV)"
fi

# ─── os-release ──────────────────────────────────────────────────────────────
printf 'ID=arch\n' > "$T/os/arch"
printf 'ID=endeavouros\nID_LIKE=arch\n' > "$T/os/endeavouros"
printf 'ID=fedora\nVERSION_ID=44\n' > "$T/os/fedora"
printf 'ID=nixos\nVERSION_ID=26.05\n' > "$T/os/nixos"
printf 'ID=ubuntu\nVERSION_ID=24.04\n' > "$T/os/ubuntu"
export ARCHENEMY_TEST=1 ARCHENEMY_FS_ROOT="$FSROOT" ARCHENEMY_OSTREE_MARKER="$T/no-ostree"

# ─── izolowany PATH ──────────────────────────────────────────────────────────
for c in bash sh awk cut dirname mktemp mkdir ln rm cat grep sed date cp chmod mv timeout tput stty wc \
         basename id sha256sum tail head cmp sort tr readlink env touch find; do
    real="$(command -v "$c")" || { echo "✗ brak narzędzia $c"; exit 1; }
    ln -sf "$real" "$BIN/$c"
done
# artifact <nazwa pakietu> <katalog prefiksu ścieżek wtyczek> — co „instaluje”
# atrapa menedżera: komendę w $ZBIN albo plik wtyczki pod $FSROOT.
cat > "$BIN/artifact" <<'EOF'
#!/usr/bin/env bash
mkcmd() { [[ -n "${MOCK_NOCMD:-}" ]] && return 0; printf '#!/usr/bin/env bash\nexec bash "$@"\n' > "$ZBIN/$1"; chmod +x "$ZBIN/$1"; }
mkfile() { [[ -n "${MOCK_NOFILE:-}" ]] && return 0; mkdir -p "${1%/*}"; printf 'echo %s >> "$ST/load-order"\n' "${1##*/}" > "$1"; }
case "$1" in
    zsh) mkcmd zsh ;;
    fd|fd-find) mkcmd fd ;;
    ripgrep) mkcmd rg ;;
    zoxide) mkcmd zoxide ;;
    neovim) mkcmd nvim ;;
    zsh-autosuggestions|zsh-syntax-highlighting) mkfile "$FSROOT$2/$1/$1.zsh" ;;
esac
EOF
cat > "$BIN/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >> "${CALLS:?}"
exec "$@"
EOF
# pacman: -Q/-Qi <nazwa> z $ST/pacman-db; MOCK_PACMAN_QERR — błąd bazy;
# -S --needed <nazwa>: MOCK_FAIL = porażka, MOCK_GHOST = kod 0 bez efektu.
cat > "$BIN/pacman" <<'EOF'
#!/usr/bin/env bash
echo "pacman $*" >> "${CALLS:?}"
touch "${ST:?}/pacman-db"
case "$1" in
    -Q|-Qi) [[ -z "${MOCK_PACMAN_QERR:-}" ]] || { echo "error: failed to initialize alpm library" >&2; exit 1; }
            grep -qxF "$2" "$ST/pacman-db" ;;
    -S) shift; [[ "$1" == --needed ]] && shift
        [[ -z "${MOCK_FAIL:-}" ]] || exit 1
        [[ -z "${MOCK_GHOST:-}" ]] || exit 0
        for p in "$@"; do echo "$p" >> "$ST/pacman-db"; artifact "$p" /usr/share/zsh/plugins; done ;;
    *) exit 2 ;;
esac
EOF
# dnf install [--repo=…] <nazwy…>: MOCK_FAIL = porażka, MOCK_GHOST = kod 0 bez
# efektu, MOCK_NOFILE/MOCK_NOCMD = RPM jest, ale pliku/komendy brak.
cat > "$BIN/dnf" <<'EOF'
#!/usr/bin/env bash
echo "dnf $*" >> "${CALLS:?}"
[[ "$1" == install ]] || exit 2
shift
[[ -z "${MOCK_FAIL:-}" ]] || exit 1
[[ -z "${MOCK_GHOST:-}" ]] || exit 0
for p in "$@"; do
    [[ "$p" == --* ]] && continue
    echo "$p" >> "${ST:?}/rpm-db"; artifact "$p" /usr/share
done
EOF
# rpm -q --qf '%{NAME}\n' <nazwy…>: dokładne nazwy z $ST/rpm-db; MOCK_RPM_BROKEN = błąd bazy.
cat > "$BIN/rpm" <<'EOF'
#!/usr/bin/env bash
echo "rpm $*" >> "${CALLS:?}"
touch "${ST:?}/rpm-db"
[[ "$1" == -q && "$2" == --qf ]] || exit 2
shift 3
[[ -z "${MOCK_RPM_BROKEN:-}" ]] || { echo "error: cannot open Packages database" >&2; exit 1; }
miss=0
for p in "$@"; do
    if grep -qxF "$p" "$ST/rpm-db"; then echo "$p"; else echo "package $p is not installed"; miss=$((miss + 1)); fi
done
exit "$miss"
EOF
cat > "$BIN/chsh" <<'EOF'
#!/usr/bin/env bash
echo "chsh $*" >> "${CALLS:?}"
[[ -z "${MOCK_CHSH_FAIL:-}" ]] || exit 1
[[ "$1" == -s ]] && echo "$2" > "${ST:?}/passwd"
EOF
cat > "$BIN/getent" <<'EOF'
#!/usr/bin/env bash
echo "x:x:1000:1000::$HOME:$(cat "${ST:?}/passwd")"
EOF
for c in nix-env nix nixos-rebuild; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "${CALLS:?}"\n' "$c" > "$BIN/$c"
done
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/clear"
chmod +x "$BIN"/*
export PATH="$BIN:$ZBIN" SHELL=/usr/bin/bash TERM=xterm ARCHENEMY_SHELLS_FILE="$T/shells"

# ─── świeży HOME i bieg ──────────────────────────────────────────────────────
# fresh <os> [kod: cur|base|nolib] — nowy HOME, czyste atrapy; pakiety
# systemu ustawia scenariusz po fresh (np. echo zsh >> "$ST/rpm-db").
fresh() {
    local os="$1" code="${2:-cur}" from="$SRC"
    rm -rf "${H:?}" "${ZBIN:?}"/* "${FSROOT:?}" "${ST:?}"/*
    mkdir -p "$A/config/shell" "$A/scripts/hypr" "$FSROOT"
    : > "$CALLS"
    [[ "$code" == base ]] && from="$BASE"
    cp -r "$from/scripts/shell" "$from/scripts/appbinds" "$A/scripts/"
    [[ -d "$from/scripts/hypr/lib" ]] && cp -r "$from/scripts/hypr/lib" "$A/scripts/hypr/"
    cp "$from/config/shell/zsh-defaults.zsh" "$from/config/shell/emacs-default-bindings.txt" \
       "$from/config/shell/cli-tools.tsv" "$from/config/shell/cli-tools-v1.tsv" "$A/config/shell/"
    if [[ "$code" == cur ]]; then
        mkdir -p "$A/install" "$A/packages"
        cp -r "$from/install/lib" "$A/install/"
        cp "$from/packages/platform-map.tsv" "$A/packages/"
    fi
    printf '[[ $- != *i* ]] && return\nPS1=x\n' > "$H/.bashrc"
    echo /usr/bin/bash > "$ST/passwd"
    printf '/bin/sh\n/usr/bin/bash\n%s\n' "$ZBIN/zsh" > "$T/shells"
    export ARCHENEMY_OS_RELEASE="$T/os/$os"
    unset MOCK_FAIL MOCK_GHOST MOCK_NOFILE MOCK_NOCMD MOCK_RPM_BROKEN MOCK_PACMAN_QERR MOCK_CHSH_FAIL
}
# run <wejście> [argumenty] — wyjście (bez kolorów) w $OUT, kod w $RC.
run() {
    local input="$1"; shift
    OUT="$(printf '%b' "$input" | timeout 15 bash "$A/scripts/shell/shell-settings.sh" "$@" 2>&1 | sed -E -e 's/\x1b\[[0-9;]*[A-Za-z]//g' -e 's/bak-[0-9_]+(-[0-9]+)?/bak-<ts>/g'; exit "${PIPESTATUS[1]}")"
    RC=$?
}
calls() { cat "$CALLS"; }
no_call() { ! grep -qE -- "$1" "$CALLS"; }
has_call() { grep -qxF -- "$1" "$CALLS"; }
P="$A/config/shell/plugins.zsh"
enabled() { [[ -f "$P" ]] && grep -qxF "# archenemy plugin: $1=1" "$P"; }
cli_on() { [[ -f "$A/config/shell/cli-tools.$1" ]] && grep -qxF "# >>> archenemy CLI: $2 >>>" "$A/config/shell/cli-tools.$1"; }
# Migawka plików osobistych HOME (bez kodu aplikacji); daty kopii znormalizowane.
snap() {
    (cd "$H" && find . -path ./archenemy/scripts -prune -o -path ./archenemy/install -prune -o \
        -path ./archenemy/packages -prune -o -type f -print | sort | while IFS= read -r f; do
        case "$f" in ./archenemy/config/shell/zsh-defaults.zsh|./archenemy/config/shell/emacs-default-bindings.txt|./archenemy/config/shell/cli-tools*.tsv) continue ;; esac
        printf '%s %s\n' "$(sed -E 's/bak-[0-9_]+(-[0-9]+)?/bak-<ts>/g' <<< "$f")" \
            "$(sed -E -e 's/bak-[0-9_]+(-[0-9]+)?/bak-<ts>/g' -e 's/on [0-9]{4}-[0-9]{2}-[0-9]{2}/on <date>/' "$f" | sha256sum | cut -c1-16)"
    done)
}
NIXBAD='sudo |nix-env|^nix |nixos-rebuild|chsh|pacman|dnf'

echo "== Fedora: wtyczki zsh (dnf z repozytoriów Fedory, [y/N], plik wtyczki)"
fresh fedora
run '5 \n'
check "Enter = odmowa: zero dnf, brak plugins.zsh" '[[ ! -e "$P" ]] && no_call "^dnf" && no_call "^pacman"'
check "pytanie [y/N] z poleceniem dnf z mapy" '[[ "$OUT" == *"sudo dnf install --repo=fedora --repo=updates zsh-autosuggestions"* && "$OUT" == *"Install zsh-autosuggestions? [y/N]"* ]]'
fresh fedora
run '5 y'
check "y: dokładnie sudo dnf install --repo=fedora --repo=updates zsh-autosuggestions" 'has_call "sudo dnf install --repo=fedora --repo=updates zsh-autosuggestions"'
check "y: stan zapisany po rpm -q i pliku" 'enabled zsh-autosuggestions && has_call "rpm -q --qf %{NAME}\n zsh-autosuggestions"'
check "loader v2: ścieżki Fedory, linia platformy, suma" 'grep -qxF "# archenemy plugin paths: fedora" "$P" && grep -qF "/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh" "$P" && ! grep -qF "/usr/share/zsh/plugins" "$P" && tail -n1 "$P" | grep -q "^# archenemy managed sha256: "'
check "pacman w PATH nigdy nie wołany na Fedorze" 'no_call "^pacman"'
check "blok ~/.zshrc po sukcesie" 'grep -qF "plugins.zsh" "$H/.zshrc"'
for mode in MOCK_FAIL MOCK_GHOST MOCK_NOFILE; do
    fresh fedora; export "$mode=1"
    run '5 yx'
    check "$mode: stan nie zapisany, komunikat ✗" '[[ ! -e "$P" && "$OUT" == *"✗"* && ! -e "$H/.zshrc" ]]'
done
check "MOCK_NOFILE: komunikat o brakującym pliku" '[[ "$OUT" == *"/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh is missing"* ]]'
fresh fedora; export MOCK_RPM_BROKEN=1
run '5 yx'
check "błąd zapytania rpm ≠ brak: bez pytania i bez dnf" '[[ ! -e "$P" && "$OUT" == *"rpm query failed"* && "$OUT" != *"[y/N]"* ]] && no_call "^dnf"'
fresh fedora
run '5jj yx'
check "zsh-completions: unavailable — porada bez pytania, bez dnf, stan nie zapisany" '[[ ! -e "$P" && "$OUT" == *"Not available on Fedora"* && "$OUT" != *"[y/N]"* ]] && no_call "^dnf"'
fresh fedora
echo zsh-syntax-highlighting >> "$ST/rpm-db"; artifact zsh-syntax-highlighting /usr/share
run '5j '
check "pakiet i plik już są: bez pytania i bez dnf, stan zapisany" 'enabled zsh-syntax-highlighting && [[ "$OUT" != *"[y/N]"* ]] && no_call "^dnf"'
echo zsh-autosuggestions >> "$ST/rpm-db"; artifact zsh-autosuggestions /usr/share
run '5 '
sed "s|/usr/share/|$FSROOT/usr/share/|g" "$P" > "$T/loader"
rm -f "$ST/load-order"
check "loader v2 ładuje się w bashu" 'bash -c "source \"\$1\"" _ "$T/loader"'
check "autosuggestions przed highlighting" '[[ "$(cat "$ST/load-order")" == $'"'"'zsh-autosuggestions.zsh\nzsh-syntax-highlighting.zsh'"'"' ]]'
rm -f "$ST/load-order"
# zsh: functions = tablica asocjacyjna zdefiniowanych funkcji; w bashu odwzorowana jawnie.
bash -c 'declare -A functions=([_zsh_autosuggest_start]=1); ZSH_HIGHLIGHT_VERSION=0.8.0; source "$1"' _ "$T/loader"
check "jedna droga ładowania: wtyczki już załadowane (NixOS/HM/system) nie ładują się drugi raz" '[[ ! -e "$ST/load-order" ]]'
rm -rf "${FSROOT:?}/usr"
check "brak plików wtyczek nie psuje startu" 'bash -c "source \"\$1\"" _ "$T/loader"'

echo "== Fedora: narzędzia CLI (fd-find → fd, ripgrep → rg, [Y/n])"
fresh fedora
run '6\n\n\e'
check "Esc: bez dnf i bez stanu" 'no_call "^dnf" && ! cli_on bash fd'
check "pytanie [Y/n] z RPM fd-find" '[[ "$OUT" == *"sudo dnf install --repo=fedora --repo=updates fd-find"* && "$OUT" == *"[Y/n]"* ]]'
fresh fedora
run '6\n\n\n'
check "Enter: dnf fd-find, komenda fd, stan bash/fd" 'has_call "sudo dnf install --repo=fedora --repo=updates fd-find" && cli_on bash fd && ! cli_on zsh fd && no_call "^pacman"'
fresh fedora
run '6\n\e[B\ny'
check "ripgrep: RPM ripgrep, weryfikacja rg" 'has_call "sudo dnf install --repo=fedora --repo=updates ripgrep" && cli_on bash ripgrep'
for mode in MOCK_FAIL MOCK_GHOST MOCK_NOCMD; do
    fresh fedora; export "$mode=1"
    run '6\n\n\nx'
    check "$mode: narzędzie nie włączone" '! cli_on bash fd && [[ "$OUT" == *"tool remains disabled"* ]]'
done
fresh fedora; artifact fd
run '6\n\n'
check "komenda już jest: bez pytania i bez dnf" 'cli_on bash fd && no_call "^dnf" && [[ "$OUT" != *"[Y/n]"* ]]'

echo "== Fedora: zsh i chsh"
fresh fedora
run 'n' switch zsh
check "odmowa: kod 0, bez dnf, bez ~/.zshrc" '[[ $RC == 0 && ! -e "$H/.zshrc" ]] && no_call "^dnf"'
check "pytanie [Y/n] z RPM zsh" '[[ "$OUT" == *"Install it now (sudo dnf install --repo=fedora --repo=updates zsh)? [Y/n]"* ]]'
fresh fedora; export MOCK_FAIL=1
run 'y' switch zsh
check "dnf zawodzi: kod 1, bez ~/.zshrc, bez chsh" '[[ $RC == 1 && ! -e "$H/.zshrc" ]] && no_call "^chsh"'
fresh fedora; export MOCK_GHOST=1
run 'y' switch zsh
check "dnf kod 0 bez binarki: kod 1" '[[ $RC == 1 && ! -e "$H/.zshrc" ]] && no_call "^chsh"'
fresh fedora
run 'yyn' switch zsh
check "zgoda: dnf zsh, chsh -s ze /etc/shells, passwd odczytany" 'has_call "sudo dnf install --repo=fedora --repo=updates zsh" && has_call "chsh -s $ZBIN/zsh" && [[ "$(<"$ST/passwd")" == "$ZBIN/zsh" && "$OUT" == *"Login shell: zsh"* ]] && no_call "^pacman"'
check "rekomendacja autosuggestions odrzucona: stan bez zmian" '! enabled zsh-autosuggestions'

echo "== Fedora: neovim"
fresh fedora
run '' edit
check "brak nvim: porada dnf z mapy, kod 1" '[[ $RC == 1 && "$OUT" == *"neovim is missing: sudo dnf install --repo=fedora --repo=updates neovim"* && "$OUT" != *pacman* ]]'

echo "== NixOS: wyłącznie deklaracje"
U="$(id -un)"
fresh nixos
run '5 y\ny'
check "autosuggestions bez profilu: opcja NixOS/HM i pkgs.*, bez pytania, bez stanu" '[[ ! -e "$P" && "$OUT" == *"programs.zsh.autosuggestions.enable = true;"* && "$OUT" == *"programs.zsh.autosuggestion.enable"* && "$OUT" == *"pkgs.zsh-autosuggestions"* && "$OUT" != *"[y/N]"* ]]'
check "zero sudo/pacman/dnf/nix-env/nixos-rebuild/chsh" 'no_call "$NIXBAD"'
fresh nixos
mkdir -p "$H/.nix-profile/share/zsh/plugins/zsh-autosuggestions"; : > "$H/.nix-profile/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
run '5 '
check "plik w ~/.nix-profile: stan zapisany, loader v2 nixos" 'enabled zsh-autosuggestions && grep -qxF "# archenemy plugin paths: nixos" "$P" && grep -qF "\"\$HOME/.nix-profile/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh\"" "$P" && no_call "$NIXBAD"'
fresh nixos
mkdir -p "$FSROOT/etc/profiles/per-user/$U/share/zsh-syntax-highlighting"; : > "$FSROOT/etc/profiles/per-user/$U/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
run '5j '
check "plik w /etc/profiles/per-user/<user>: znaleziony, stan zapisany" 'enabled zsh-syntax-highlighting && grep -qF "/etc/profiles/per-user/\$USER/share/zsh-syntax-highlighting/" "$P"'
fresh nixos
mkdir -p "$FSROOT/run/current-system/sw/share/zsh/plugins/zsh-autosuggestions"; : > "$FSROOT/run/current-system/sw/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
run '5 '
check "plik w profilu systemowym (/share/zsh linkowane): znaleziony" 'enabled zsh-autosuggestions'
fresh nixos
run '5jj x'
check "zsh-completions: NixOS ładuje je sam, nic do włączenia" '[[ ! -e "$P" && "$OUT" == *"nothing to enable here"* && "$OUT" == *"pkgs.zsh-completions"* ]] && no_call "$NIXBAD"'
fresh nixos
run '6\n\n\nx'
check "CLI fd: porada pkgs.fd, bez pytania i stanu" '! cli_on bash fd && [[ "$OUT" == *"pkgs.fd"* && "$OUT" != *"[Y/n]"* ]] && no_call "$NIXBAD"'
fresh nixos
cp "$H/.bashrc" "$T/bashrc0"
run 'y\ny\ny' switch zsh
check "zsh brak: deklaracja programs.zsh.enable + users.users.$U.shell = pkgs.zsh, kod 0" '[[ $RC == 0 && "$OUT" == *"programs.zsh.enable = true;"* && "$OUT" == *"users.users.$U.shell = pkgs.zsh;"* ]]'
check "zsh brak: żadnych plików, zero wywołań, bez chsh i /bin/ w tekście" '[[ ! -e "$H/.zshrc" ]] && cmp -s "$H/.bashrc" "$T/bashrc0" && no_call "$NIXBAD" && [[ "$OUT" != *chsh* && "$OUT" != */bin/* ]]'
fresh nixos; artifact zsh
run 'n\ny\ny' switch zsh
check "zsh obecny: bloki rc, deklaracja, passwd bez zmian, zero chsh (także w tekście)" '[[ $RC == 0 && -f "$H/.zshrc" && "$(<"$ST/passwd")" == /usr/bin/bash && "$OUT" == *"users.users.$U.shell = pkgs.zsh;"* && "$OUT" != *chsh* ]] && no_call "$NIXBAD"'
fresh nixos; artifact zsh; echo "$ZBIN/zsh" > "$ST/passwd"
run 'y\ny' switch bash
check "powrót do basha: pkgs.bashInteractive, bez chsh i bez /bin/bash" '[[ $RC == 0 && "$OUT" == *"users.users.$U.shell = pkgs.bashInteractive;"* && "$OUT" != *chsh* && "$OUT" != */bin/bash* && "$(<"$ST/passwd")" == "$ZBIN/zsh" ]] && no_call "$NIXBAD"'
fresh nixos
run '' edit
check "brak nvim: pkgs.neovim, bez pacmana" '[[ $RC == 1 && "$OUT" == *"pkgs.neovim"* && "$OUT" != *pacman* ]]'

echo "== nieobsługiwana dystrybucja i brak biblioteki"
for v in ubuntu nolib; do
    if [[ "$v" == nolib ]]; then fresh arch; rm -rf "${A:?}/install"; else fresh ubuntu; fi
    run '5 yx'
    check "$v: wtyczka odrzucona bez wywołań" '[[ ! -e "$P" && "$OUT" == *"only on Arch, Fedora and NixOS"* && ! -s "$CALLS" ]]'
    run '6\n\n\nx'
    check "$v: CLI odrzucone bez wywołań" '! cli_on bash fd && [[ "$OUT" == *"only on Arch, Fedora and NixOS"* && ! -s "$CALLS" ]]'
    run 'y\ny' switch zsh
    check "$v: brak zsh — kod 1, bez instalacji" '[[ $RC == 1 && ! -e "$H/.zshrc" && ! -s "$CALLS" ]]'
done
fresh ubuntu; artifact zsh
run 'y\nn\n' switch zsh
check "ubuntu z zsh: chsh po zgodzie (to nie pakiet), passwd odczytany" 'has_call "chsh -s $ZBIN/zsh" && [[ "$(<"$ST/passwd")" == "$ZBIN/zsh" ]] && no_call "^(sudo|pacman|dnf)"'

echo "== Arch: EndeavourOS = Arch; parytet z bazą (SHELL_PLATFORMS_REV)"
# Scenariusze Archa: <etykieta>|<przygotowanie>|<wejście>|<argumenty>
ARCH_CASES=(
    "wtyczka: odmowa Enter||5 \\nn|"
    "wtyczka: instalacja y||5 y|"
    "wtyczka: pacman zawodzi|export MOCK_FAIL=1|5 yx|"
    "wtyczka: kod 0 bez pakietu|export MOCK_GHOST=1|5 yx|"
    "wtyczka: błąd zapytania pacmana|export MOCK_PACMAN_QERR=1|5 yx|"
    "wtyczka: completions|echo zsh-completions >> \"\$ST/pacman-db\"|5jj |"
    "wtyczka: brak pacmana|rm -f \"\$BIN/pacman.off\"; mv \"\$BIN/pacman\" \"\$BIN/pacman.off\"|5 yx|"
    "CLI: Esc||6\\n\\n\\e|"
    "CLI: fd Enter||6\\n\\n\\n|"
    "CLI: ripgrep y||6\\n\\e[B\\ny|"
    "CLI: porażka|export MOCK_FAIL=1|6\\n\\n\\nx|"
    "CLI: kod 0 bez komendy|export MOCK_GHOST=1|6\\n\\n\\nx|"
    "zsh: odmowa instalacji||n|switch zsh"
    "zsh: pacman zawodzi|export MOCK_FAIL=1|y|switch zsh"
    "zsh: kod 0 bez binarki|export MOCK_GHOST=1|y|switch zsh"
    "zsh: pełna zmiana + rekomendacja||yyyy|switch zsh"
    "zsh: odmowa chsh|artifact zsh|n|switch zsh"
    "zsh: chsh zawodzi|artifact zsh; export MOCK_CHSH_FAIL=1|y|switch zsh"
    "bash: powrót|artifact zsh; echo \"\$ZBIN/zsh\" > \"\$ST/passwd\"|y|switch bash"
    "edycja: brak nvim|||edit"
)
arch_case() {   # arch_case <os> <kod> <przygotowanie> <wejście> <argumenty> → $OUT $RC $C $F
    fresh "$1" "$2"
    eval "$3"
    # shellcheck disable=SC2086  # argumenty scenariusza celowo dzielone
    run "$4" $5
    [[ -e "$BIN/pacman.off" ]] && mv "$BIN/pacman.off" "$BIN/pacman"
    C="$(calls)"; F="$(snap)"
}
for row in "${ARCH_CASES[@]}"; do
    IFS='|' read -r label prep input args <<< "$row"
    arch_case arch cur "$prep" "$input" "$args"
    a_out="$OUT"; a_rc="$RC"; a_c="$C"; a_f="$F"
    check "Arch $label: tylko pacman/chsh, nigdy dnf/rpm/nix" 'no_call "^(dnf|rpm|nix-env|nix|nixos-rebuild) "'
    arch_case endeavouros cur "$prep" "$input" "$args"
    check "EndeavourOS $label = Arch (wyjście, kod, wywołania, pliki)" '[[ "$OUT" == "$a_out" && "$RC" == "$a_rc" && "$C" == "$a_c" && "$F" == "$a_f" ]]'
    if [[ -n "$BASE" ]]; then
        arch_case arch base "$prep" "$input" "$args"
        why=""
        [[ "$OUT" == "$a_out" ]] || why+=" wyjście"
        [[ "$RC" == "$a_rc" ]] || why+=" kod"
        [[ "$C" == "$a_c" ]] || why+=" wywołania"
        [[ "$F" == "$a_f" ]] || why+=" pliki"
        if [[ -z "$why" ]]; then ok "Arch $label = $SHELL_PLATFORMS_REV (pytania/wyjście, kod, wywołania, pliki)"
        else fail "Arch $label ≠ $SHELL_PLATFORMS_REV:$why"; diff <(echo "$OUT") <(echo "$a_out") | head -n 6; fi
    fi
done
fresh arch
run '5 y'
check "Arch: plugins.zsh to dalej zamrożony v1 z sumą (bez linii platformy)" 'bash -c "source \"\$1\"; body=\"\$(head -n -1 \"\$2\")\"; [[ \"\$body\" == \"\$(shell_plugins_v1_text 1 0 0)\" ]]" _ "$A/scripts/shell/lib/shell-rc.sh" "$P" && ! grep -q "plugin paths" "$P"'

echo "== shell-rc.sh: zamrożony v1 i tabela ścieżek"
LIBRC="$SRC/scripts/shell/lib/shell-rc.sh"
# Suma wszystkich 8 stanów v1 z 0a3ca91 (przed D8): v1 nie może się zmienić.
V1="$(ARCHENEMY_DIR="$A" bash -c 'source "$1"; for a in 0 1; do for b in 0 1; do for c in 0 1; do shell_plugins_v1_text $a $b $c; done; done; done | sha256sum' _ "$LIBRC")"
check "shell_plugins_v1_text bajt w bajt jak przed D8" '[[ "${V1%% *}" == 0b0e277c4b5bac299d4d6e78e22eef4dec98406a5db4e948840a44fe2670cefe ]]'
paths() { ARCHENEMY_DIR="$A" bash -c 'source "$1"; shell_plugin_paths "$2" "$3" | tr "\n" " "' _ "$LIBRC" "$1" "$2"; }
check "Arch (i pusta platforma): FHS Archa" '[[ "$(paths arch zsh-autosuggestions)" == "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh " && "$(paths "" zsh-completions)" == "/usr/share/zsh/site-functions " ]]'
check "Fedora: /usr/share/<nazwa>/<nazwa>.zsh (mdapi f44)" '[[ "$(paths fedora zsh-syntax-highlighting)" == "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh " ]]'
check "NixOS: profile od osobistego do systemowego, oba układy autosuggestions" '[[ "$(paths nixos zsh-autosuggestions)" == "\$HOME/.nix-profile/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \$HOME/.nix-profile/share/zsh-autosuggestions/zsh-autosuggestions.zsh "* && "$(paths nixos zsh-autosuggestions)" == *"/run/current-system/sw/share/zsh-autosuggestions/zsh-autosuggestions.zsh " && -z "$(paths nixos zsh-completions)" ]]'

ROOT_AFTER="$(find / -mindepth 1 -maxdepth 1 2>/dev/null | sort)"
check "żadnych nowych plików w /" '[[ "$ROOT_AFTER" == "$ROOT_BEFORE" ]]'
echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
