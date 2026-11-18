#!/usr/bin/env bash
# =============================================
#   archenemy - scripts/lib/hm-conflict.sh (biblioteka, source)
#   Pliki, którymi zarządza home-manager (D10): HM wkłada do $HOME dowiązania
#   do /nix/store (xdg.configFile, programs.*, home.file). archenemy NIGDY
#   ich nie nadpisuje, nie przenosi do .bak i nie pisze przez nie (sklep
#   jest tylko do odczytu, a następny `home-manager switch` i tak by je
#   odtworzył albo nadpisał nasz link) — wypisuje poradę i nic nie zmienia.
#   Globalnego `force` HM nie doradzamy: oba narzędzia nadpisywałyby się
#   nawzajem przy każdym przełączeniu.
#   Woła: lib/switch-rice.sh (Super+T, re-apply, install.sh [9]),
#   install/install.sh [9] i [8l]; shell-rc.sh ma własną jednolinijkową
#   kontrolę (rc_store_managed) dla ~/.bashrc i ~/.zshrc.
#   Tylko odczyty: readlink/find, bez żadnego zapisu.
# =============================================

# Sklep Nix; hak testów ARCHENEMY_NIX_STORE działa tylko z ARCHENEMY_TEST=1
# (atrapa sklepu z treścią — prawdziwego /nix/store na Archu nie ma).
HM_STORE_DIR="/nix/store"
[[ "${ARCHENEMY_TEST:-}" == 1 && -n "${ARCHENEMY_NIX_STORE:-}" ]] && HM_STORE_DIR="$ARCHENEMY_NIX_STORE"

# hm_store_link <ścieżka> — 0, gdy ścieżka po rozwinięciu wszystkich
# dowiązań (także rodziców, np. ~/.config → sklep, i łańcuchów link → link)
# leży w /nix/store. Działa też dla dowiązań wiszących (readlink -m).
hm_store_link() {
    local r
    r="$(readlink -m -- "$1" 2>/dev/null)" || return 1
    [[ "$r" == "$HM_STORE_DIR" || "$r" == "$HM_STORE_DIR"/* ]]
}

# hm_conflicts <cel> — ścieżki pod <cel>, którymi zarządza HM (stdout, jedna
# na linię; kod 0 = są). <cel> sam w sklepie albo prawdziwy katalog
# z dowiązaniami do sklepu w środku (HM linkuje też pojedyncze pliki, np.
# xdg.configFile."waybar/config"). Do dowiązań-katalogów nie wchodzimy:
# link do rices/ to nasz, a cudzy (stow) i tak idzie do .bak w całości.
hm_conflicts() {
    local dest="$1" l found=1
    if [[ -e "$dest" || -L "$dest" ]] && hm_store_link "$dest"; then
        printf '%s\n' "$dest"; return 0
    fi
    [[ -d "$dest" && ! -L "$dest" ]] || return 1
    while IFS= read -r -d '' l; do
        hm_store_link "$l" && { printf '%s\n' "$l"; found=0; }
    done < <(find "$dest" -type l -print0 2>/dev/null)
    return "$found"
}

# hm_rice_conflicts <katalog rice'a> <katalog config> — hm_conflicts dla
# każdego folderu rice'a; zarządzany rodzic (~/.config w sklepie) też liczy.
hm_rice_conflicts() {
    local rice="$1" config="$2" src found=1
    if hm_store_link "$config"; then printf '%s\n' "$config"; return 0; fi
    for src in "$rice"/*/; do
        [[ -d "$src" ]] || continue
        hm_conflicts "$config/$(basename "$src")" && found=0
    done
    return "$found"
}

# hm_advice <ścieżka…> — porada (angielski, jak reszta komunikatów).
hm_advice() {
    local p
    echo "home-manager manages these paths (links into $HM_STORE_DIR); archenemy did not change anything:"
    for p in "$@"; do echo "  ${p/#$HOME/\~} -> $(readlink -- "$p" 2>/dev/null || echo '?')"; done
    echo "Remove those entries from your home-manager configuration (xdg.configFile.\"<name>\","
    echo "home.file, programs.<name> settings, wayland.windowManager.hyprland), run home-manager switch,"
    echo "then run this again. Do not set force on them: archenemy and home-manager would overwrite each other."
}
