#!/usr/bin/env bash

# =============================================
#   archenemy - launcher-logo.sh
#   Logo systemu: lewy box waybara (moduł custom/launcher, return-type
#   json), a od 2026-11-22 także ekran logowania SDDM i menu GRUB-a
#   (src/system-theme/ — biorą stąd tryb i glif dystrybucji).
#   Dwa tryby (wybór: TUI Super+A → [l] system logo; plik
#   data/launcher-logo.dat — nazwa sprzed rozszerzenia na cały system,
#   zostaje, żeby nikt nie stracił wyboru; warstwa maszynowa poza gitem,
#   przeżywa zmianę rice'a):
#     distro    (domyślnie, także bez pliku albo ze śmieciami w nim) — glif
#               Nerd Font wykrytej dystrybucji, jak przed 2026-11-19;
#     archenemy — logo projektu (Æ): tekst to jedna spacja, obraz daje CSS
#               rice'a (#custom-launcher.archenemy → launcher.svg). Spacja,
#               bo moduł custom z pustym tekstem jest ukryty (Waybar
#               custom.cpp, update()).
#   Klasa w JSON-ie (distro|archenemy) wybiera reguły w style.css rice'a.
#
#   Odświeżanie: config ma "signal": 12 i nie ma "interval" — Waybar (0.15.0,
#   custom.cpp, konstruktor) uruchamia wtedy skrypt raz na starcie i ponownie
#   dopiero po pkill -RTMIN+12 waybar (TUI po zapisie wyboru). Config waybar
#   czyta tylko na starcie: pasek sprzed git pull nie zna "signal": 12, więc
#   TUI i [u] przeładowują go wtedy SIGUSR2 (lib/waybar-reload.sh).
#
#   Dystrybucja z os-release przez install/lib/pkg.sh (_pkg_os_file,
#   _pkg_os_value): plik czytany jako dane, nigdy eval/source; hak testowy
#   ARCHENEMY_OS_RELEASE działa tylko z ARCHENEMY_TEST=1. Pierwsze trafienie
#   w ID, potem kolejno w ID_LIKE: arch (i pochodne: EndeavourOS, Manjaro…),
#   fedora, nixos; reszta i brak os-release → ogólny pingwin.
#
#   Te cztery glify dystrybucji żyją w repo WYŁĄCZNIE tutaj (tests/waybar-launcher.sh).
#   Kody punktów sprawdzone w glyphnames.json Nerd Fonts 3.5.1 (2026-11-19).
#
#   Użycie: launcher-logo.sh          (woła waybar; jedna linia JSON)
#           launcher-logo.sh mode     (tryb: distro|archenemy — stan w TUI)
#           launcher-logo.sh distro   (nazwa wykrytej dystrybucji — podgląd TUI)
#           launcher-logo.sh glyph    (sam glif dystrybucji — motywy systemowe)
#   Kod wyjścia zawsze 0: niezerowy schowałby moduł bez śladu.
# =============================================

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGO_DAT="$HOME/archenemy/data/launcher-logo.dat"

GLYPH_ARCH="󰣇"     # U+F08C7 nf-md-arch
GLYPH_FEDORA="󰣛"   # U+F08DB nf-md-fedora
GLYPH_NIXOS="󱄅"    # U+F1105 nf-md-nix
GLYPH_LINUX="󰌽"    # U+F033D nf-md-linux (nieznana dystrybucja)

# Bez biblioteki (np. niepełny checkout) nie ma odczytu os-release → pingwin.
OS_LIB=0
# shellcheck source=SCRIPTDIR/../../install/lib/pkg.sh
source "$SELF_DIR/../../install/lib/pkg.sh" 2>/dev/null && OS_LIB=1

# Tryb z pliku stanu: tylko dokładne "archenemy" (pierwsza linia, białe znaki
# pominięte) włącza Æ; wszystko inne to domyślne distro.
logo_mode() {
    local mode=""
    [[ -f "$LOGO_DAT" && -r "$LOGO_DAT" ]] && { IFS= read -r mode < "$LOGO_DAT"; } 2>/dev/null
    mode="${mode//[[:space:]]/}"
    [[ "$mode" == archenemy ]] || mode=distro
    printf '%s\n' "$mode"
}

# Ścieżka os-release albo kod 1.
os_file() {
    (( OS_LIB )) || return 1
    _pkg_os_file 2>/dev/null
}

# arch|fedora|nixos|other — pierwsze trafienie w ID, potem w ID_LIKE.
distro_key() {
    local f w
    local -a words=()
    if f="$(os_file)"; then
        # read -ra dzieli bez rozwijania ścieżek (jak pkg_arch_derivative).
        read -ra words <<< "$(_pkg_os_value "$f" ID) $(_pkg_os_value "$f" ID_LIKE)"
    fi
    for w in "${words[@]}"; do
        case "$w" in
            arch|fedora|nixos) printf '%s\n' "$w"; return 0 ;;
        esac
    done
    printf 'other\n'
}

# Nazwa do podglądu TUI: PRETTY_NAME, NAME, ID albo "unknown"; bez znaków
# sterujących (tekst z pliku trafia na terminal) i najwyżej 40 znaków.
distro_name() {
    local f name="" key
    if f="$(os_file)"; then
        for key in PRETTY_NAME NAME ID; do
            name="$(_pkg_os_value "$f" "$key")"
            name="${name//[[:cntrl:]]/}"
            [[ -n "$name" ]] && break
        done
    fi
    name="${name:0:40}"
    printf '%s\n' "${name:-unknown}"
}

distro_glyph() {
    case "$(distro_key)" in
        arch)   printf '%s' "$GLYPH_ARCH" ;;
        fedora) printf '%s' "$GLYPH_FEDORA" ;;
        nixos)  printf '%s' "$GLYPH_NIXOS" ;;
        *)      printf '%s' "$GLYPH_LINUX" ;;
    esac
}

case "${1:-}" in
    mode)   logo_mode ;;
    distro) distro_name ;;
    glyph)  printf '%s\n' "$(distro_glyph)" ;;
    *)
        if [[ "$(logo_mode)" == archenemy ]]; then
            printf '{"text":" ","class":"archenemy"}\n'
        else
            printf '{"text":"%s","class":"distro"}\n' "$(distro_glyph)"
        fi
        ;;
esac
exit 0
