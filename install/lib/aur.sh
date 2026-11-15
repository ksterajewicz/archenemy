#!/bin/bash
# =============================================
#   archenemy - install/lib/aur.sh
#   Wspólne kroki AUR instalatora (source z install.sh): budowa yay i
#   instalacja pakietów z AUR. Jedno miejsce dla [4], [5] i [6].
#   Audyt bezpieczeństwa 2026-11-14 (S11, K6+K7):
#     - yay budowany w świeżym `mktemp -d` (trap sprząta), nie w stałym
#       /tmp/yay, który inny użytkownik mógł podstawić przed nami;
#     - przed makepkg pytanie „Review PKGBUILD?” (domyślnie N), przed
#       `yay -S` zdanie, czym jest AUR, i opt-in `--diffmenu --answerdiff All`
#       (yay pokaże diff każdego PKGBUILD przed budową; `--diffmenu`, bo samo
#       --answerdiff nic nie daje, gdy użytkownik wyłączył menu diffów —
#       I3 z przeglądu 2026-11-15).
#   Przegląd 2026-11-15 (I1): świeży Arch nie ma less (base, base-devel ani
#   git go nie ciągną), więc pager idzie z zapasem: $PAGER → less → more
#   (util-linux, w base) → cat; yay dostaje ten sam pager jako GIT_PAGER.
#   Haki testowe: ARCHENEMY_YAY_URL (repo yay), PAGER (podgląd PKGBUILD).
#   Funkcje nie wychodzą z procesu — zwracają kod; komunikaty po angielsku.
# =============================================

# aur_pager_cmd — wypisuje polecenie pagera, które na pewno istnieje:
# $PAGER, gdy jego pierwsze słowo jest poleceniem (może mieć argumenty,
# np. „less -R”), potem less, more, cat. Wynik jest dla `sh -c`.
aur_pager_cmd() {
    local first
    read -r first _ <<< "${PAGER:-}"
    if [[ -n "$first" ]]; then
        if command -v "$first" >/dev/null 2>&1; then
            printf '%s\n' "$PAGER"
            return 0
        fi
        echo "  PAGER ($PAGER) not found — using a fallback pager." >&2
    fi
    for first in less more cat; do
        if command -v "$first" >/dev/null 2>&1; then
            printf '%s\n' "$first"
            return 0
        fi
    done
    return 1
}

# aur_page <plik> — pokazuje plik pagerem z aur_pager_cmd. Napis $PAGER idzie
# przez sh -c: cytowane "$PAGER" brało „cat -n” za nazwę jednego programu.
aur_page() {
    local cmd
    if ! cmd="$(aur_pager_cmd)"; then
        echo "  No pager found (less, more, cat) — cannot show $1."
        return 1
    fi
    sh -c "$cmd \"\$1\"" aur-pager "$1"
}

# aur_bootstrap_yay — buduje i instaluje yay; 0 = `command -v yay` po biegu.
aur_bootstrap_yay() {
    local rc
    # Podpowłoka: trap sprzątający żyje tylko w niej, więc nie nadpisuje
    # trapów install.sh (np. katalogu monitors.new z [3]); Ctrl-C też sprząta.
    (
        build="$(mktemp -d "${TMPDIR:-/tmp}/archenemy-yay.XXXXXX")" || exit 1
        trap 'rm -rf "$build"' EXIT
        # Ctrl-C (I2, przegląd 2026-11-15): sprzątanie, potem ten sam sygnał
        # jeszcze raz, już bez pułapki — podpowłoka ginie od SIGINT, więc
        # install.sh też staje. Dawne `exit 130` było zwykłym wyjściem: bash
        # uznawał sygnał za obsłużony i instalator jechał dalej do [5].
        trap 'rm -rf "$build"; trap - INT; kill -INT "$BASHPID"' INT
        trap 'rm -rf "$build"; trap - TERM; kill -TERM "$BASHPID"' TERM
        git clone "${ARCHENEMY_YAY_URL:-https://aur.archlinux.org/yay.git}" "$build/yay" || exit 1
        echo -e "  yay comes from the AUR (user-submitted, not checked by Arch); its PKGBUILD runs on this machine."
        read -rp "Review PKGBUILD before building? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            aur_page "$build/yay/PKGBUILD"
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
    local ans pager
    local -a review=() pager_env=()
    echo -e "  AUR packages are built from user-submitted PKGBUILDs (not checked by Arch): $*"
    read -rp "Review each PKGBUILD diff before building (yay --diffmenu --answerdiff All)? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        # --diffmenu: `yay --diffmenu=false --save` wyłącza menu diffów na stałe
        # i wtedy samo --answerdiff All budowało bez przeglądu (yay 13.0.1).
        review=(--diffmenu --answerdiff All)
        # yay pokazuje diffy przez `git diff`, a git bez less kończy się
        # „unable to execute pager 'less'” i przeglądu nie ma (I1). Pager
        # wybrany przez użytkownika (GIT_PAGER, core.pager) zostaje.
        if [[ -z "${GIT_PAGER:-}" ]] && ! git config --get core.pager >/dev/null 2>&1 \
                && pager="$(aur_pager_cmd)"; then
            pager_env=(GIT_PAGER="$pager")
        fi
    fi
    env "${pager_env[@]}" yay -S --needed "${review[@]}" "$@"
}
