#!/bin/bash
# =============================================
#   archenemy - install/lib/aur.sh
#   Wspólne kroki AUR instalatora (source z install.sh): budowa yay i
#   instalacja pakietów z AUR. Jedno miejsce dla [4], [5] i [6].
#   Audyt bezpieczeństwa 2026-11-14 (S11, K6+K7):
#     - yay budowany w świeżym `mktemp -d` (trap sprząta), nie w stałym
#       /tmp/yay, który inny użytkownik mógł podstawić przed nami;
#     - przed makepkg pytanie „Review PKGBUILD?” (domyślnie N), przed
#       `yay -S` zdanie, czym jest AUR, i opt-in `--answerdiff All`
#       (yay pokaże diff każdego PKGBUILD przed budową).
#   Haki testowe: ARCHENEMY_YAY_URL (repo yay), PAGER (podgląd PKGBUILD).
#   Funkcje nie wychodzą z procesu — zwracają kod; komunikaty po angielsku.
# =============================================

# aur_bootstrap_yay — buduje i instaluje yay; 0 = `command -v yay` po biegu.
aur_bootstrap_yay() {
    local rc
    # Podpowłoka: trap sprzątający żyje tylko w niej, więc nie nadpisuje
    # trapów install.sh (np. katalogu monitors.new z [3]); Ctrl-C też sprząta.
    (
        build="$(mktemp -d "${TMPDIR:-/tmp}/archenemy-yay.XXXXXX")" || exit 1
        trap 'rm -rf "$build"' EXIT
        trap 'exit 130' INT TERM
        git clone "${ARCHENEMY_YAY_URL:-https://aur.archlinux.org/yay.git}" "$build/yay" || exit 1
        echo -e "  yay comes from the AUR (user-submitted, not checked by Arch); its PKGBUILD runs on this machine."
        read -rp "Review PKGBUILD before building? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            "${PAGER:-less}" "$build/yay/PKGBUILD"
            read -rp "Build and install yay now? [y/N]: " ans
            if [[ ! "$ans" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}⚠ yay not built at your request.${NC}"
                exit 1
            fi
        fi
        cd "$build/yay" && makepkg -si
    )
    rc=$?
    # Sukces = odczytany stan, nie kod makepkg.
    if [[ $rc -eq 0 ]] && command -v yay >/dev/null 2>&1; then
        echo -e "${GREEN}✓ yay installed.${NC}"
        return 0
    fi
    echo -e "${RED}✗ yay is not installed — AUR packages will be skipped.${NC}"
    return 1
}

# aur_install <pakiet…> — `yay -S --needed` z pytaniem o przegląd diffów;
# zwraca kod yay (wołający sam decyduje o podsumowaniu).
aur_install() {
    local ans
    local -a review=()
    echo -e "  AUR packages are built from user-submitted PKGBUILDs (not checked by Arch): $*"
    read -rp "Review each PKGBUILD diff before building (yay --answerdiff All)? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] && review=(--answerdiff All)
    yay -S --needed "${review[@]}" "$@"
}
