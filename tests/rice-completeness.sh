#!/usr/bin/env bash
# =============================================
#   archenemy - tests/rice-completeness.sh
#   Każdy rice ma komplet WŁASNYCH konfiguracji (polecenie właściciela
#   2026-11-24: „czy przy nowych riceach są zrobione adekwatne do nich
#   odpowiedniki na przykład neovima, ncmpcpp itd”). Luka, którą to łapie:
#   yin i yang weszły bez zsh/ (dziś archenemy-zsh/: colors.zsh,
#   starship.toml), a asia-n-rice
#   brał wygląd MangoHuda z white-blue przez dowiązanie.
#   Dla każdego rices/<rice>/ spoza EXCEPTIONS:
#     - każdy plik z REQUIRED_FILES istnieje (po rozwiązaniu dowiązań) i nie
#       jest pusty; REQUIRED_LINKS to dowiązania do warstwy maszynowej
#       (w gołym checkoucie wiszą z założenia, więc tylko -L);
#     - rofi/themes/ ma co najmniej jeden motyw *.rasi;
#     - zero pustych katalogów i pustych plików w całym rice'u;
#     - plik wyglądu leży w folderze TEGO rice'a: dowiązanie do innego rice'a
#       wolno tylko dla konfiguracji funkcjonalnych z INHERITABLE
#       (usankcjonowane dziedziczenie, jak networkmanager-dmenu);
#     - paleta: tło z alacritty ([colors.primary] background) występuje
#       w nvim/lua/config/colorscheme.lua i w archenemy-zsh/colors.zsh;
#     - żaden rice (także beta) nie ma folderu zsh/: Super+T linkuje folder
#       do ~/.config/<nazwa>, a ~/.config/zsh bywa ZDOTDIR-em użytkownika
#       (R3 2026-11-24: Super+T odkładał go do .bak i powłoka „znikała”).
#   Jedno źródło listy: REQUIRED_FILES + REQUIRED_LINKS niżej, zgodne
#   z rice'ami referencyjnymi white-blue i tron (test pilnuje, że ich
#   katalogi najwyższego poziomu są dokładnie te z listy — nowy program
#   w referencji bez wpisu tutaj = ✗). Nowy program w rice'ach = wpis tutaj.
#   white-blue_beta to artefakt legacy (tylko bug-fixy, bez nowych funkcji,
#   bez system-theme.conf) — poza testem.
#   Tylko odczyt repo, bez roota i bez zapisu.
#   Uruchom: bash tests/rice-completeness.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RICES="$REPO/rices"
export LC_ALL=C.UTF-8

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

REFERENCES=(white-blue tron)
EXCEPTIONS=(white-blue_beta)
REQUIRED_FILES=(
    alacritty/alacritty.toml
    alacritty/font.toml
    fastfetch/config.jsonc
    hypr/hyprland.lua
    hypr/hyprlock.conf
    mako/config
    MangoHud/MangoHud.conf
    mpv/mpv.conf
    ncmpcpp/config
    ncmpcpp/bindings
    networkmanager-dmenu/config.ini
    nvim/init.lua
    nvim/lua/config/cmp.lua
    nvim/lua/config/colorscheme.lua
    nvim/lua/config/lazy.lua
    nvim/lua/config/lsp.lua
    nvim/lua/config/options.lua
    nvim/lua/config/telescope.lua
    rofi/config.rasi
    swayosd/style.css
    waybar/config.jsonc
    waybar/style.css
    archenemy-zsh/colors.zsh
    archenemy-zsh/starship.toml
    flux-wall.conf
    system-theme.conf
    preview.png
)
REQUIRED_LINKS=(hypr/hyprpaper.conf)
# Konfiguracje bez własnego wyglądu (kolory daje rofi rice'a albo nie ma
# ich wcale) — wspólne przez commitowane dowiązanie względne.
INHERITABLE=(networkmanager-dmenu ncmpcpp/bindings hypr/hyprpaper.conf)

is_in() { local x="$1"; shift; local y; for y in "$@"; do [[ "$x" == "$y" ]] && return 0; done; return 1; }

# Ścieżka (albo któryś jej przodek w rice'u) z listy INHERITABLE?
inheritable() {
    local rel="$1" i
    for i in "${INHERITABLE[@]}"; do
        [[ "$rel" == "$i" || "$rel" == "$i/"* ]] && return 0
    done
    return 1
}

# Tło terminala rice'a: [colors.primary] background z alacritty.toml.
alacritty_bg() {
    python3 - "$1" <<'PY'
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as f:
        print(tomllib.load(f)["colors"]["primary"]["background"])
except (OSError, KeyError, ValueError):
    pass
PY
}

echo "── lista wymagań zgodna z rice'ami referencyjnymi (${REFERENCES[*]})"
want="$(for p in "${REQUIRED_FILES[@]}" "${REQUIRED_LINKS[@]}"; do echo "${p%%/*}"; done | sort -u)"
for ref in "${REFERENCES[@]}"; do
    have="$(find "$RICES/$ref" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -u)"
    if [[ "$have" == "$want" ]]; then
        ok "$ref: katalogi i pliki najwyższego poziomu = lista testu"
    else
        fail "$ref: rozjazd z listą testu: $(diff <(echo "$want") <(echo "$have") | grep '^[<>]' | tr '\n' ' ')"
    fi
done

# ~/.config/zsh to częsty ZDOTDIR (.zshrc, historia) — żaden rice, także
# wyjątek z EXCEPTIONS, nie może mieć folderu o tej nazwie (R3, 2026-11-24).
echo "── folder zsh/ w rice'ach (zderzenie z ZDOTDIR=~/.config/zsh)"
zsh_dirs="$(find "$RICES" -mindepth 2 -maxdepth 2 -name zsh -printf '%P ' 2>/dev/null)"
if [[ -z "$zsh_dirs" ]]; then ok "żaden rice nie ma folderu zsh/ (wygląd zsh: archenemy-zsh/)"
else fail "folder zsh/ zabrałby ~/.config/zsh użytkownika: $zsh_dirs"; fi

for dir in "$RICES"/*/; do
    rice="$(basename "$dir")"
    is_in "$rice" "${EXCEPTIONS[@]}" && { echo "── $rice: wyjątek (beta), pominięty"; continue; }
    echo "── $rice"
    real_rice="$(readlink -f "$dir")"

    missing=() empty=() foreign=()
    for rel in "${REQUIRED_FILES[@]}"; do
        p="$dir$rel"
        if [[ ! -f "$p" ]]; then missing+=("$rel"); continue; fi
        [[ -s "$p" ]] || empty+=("$rel")
        real="$(readlink -f "$p")"
        if [[ "$real" != "$real_rice/"* ]] && ! inheritable "$rel"; then
            foreign+=("$rel → ${real#"$RICES/"}")
        fi
    done
    for rel in "${REQUIRED_LINKS[@]}"; do
        [[ -L "$dir$rel" ]] || missing+=("$rel (dowiązanie)")
    done
    themes=("$dir"rofi/themes/*.rasi)
    [[ -f "${themes[0]}" ]] || missing+=("rofi/themes/*.rasi")

    if (( ${#missing[@]} == 0 )); then ok "$rice: komplet plików"
    else fail "$rice: brak: ${missing[*]}"; fi
    if (( ${#empty[@]} == 0 )); then ok "$rice: wymagane pliki niepuste"
    else fail "$rice: puste: ${empty[*]}"; fi
    if (( ${#foreign[@]} == 0 )); then ok "$rice: wygląd we własnym folderze (dziedziczone tylko: ${INHERITABLE[*]})"
    else fail "$rice: wygląd z innego rice'a: ${foreign[*]}"; fi

    # Puste katalogi i pliki w całym rice'u (także za dowiązaniami).
    holes="$(find -L "$dir" -mindepth 1 \( -type d -o -type f \) -empty -printf '%P\n' 2>/dev/null | sort)"
    if [[ -z "$holes" ]]; then ok "$rice: zero pustych katalogów i plików"
    else fail "$rice: puste: $(echo "$holes" | tr '\n' ' ')"; fi

    bg="$(alacritty_bg "$dir/alacritty/alacritty.toml")"
    if [[ ! "$bg" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
        fail "$rice: alacritty bez [colors.primary] background w formacie #RRGGBB (jest: '$bg')"
        continue
    fi
    for rel in nvim/lua/config/colorscheme.lua archenemy-zsh/colors.zsh; do
        if [[ -f "$dir$rel" ]] && grep -qiF -- "$bg" "$dir$rel"; then ok "$rice: $rel używa tła rice'a $bg"
        else fail "$rice: $rel nie zawiera tła rice'a $bg (paleta z innego rice'a albo brak pliku)"; fi
    done
done

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗ / $SKIP skip"
(( FAIL == 0 ))
