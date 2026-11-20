#!/usr/bin/env bash

# =============================================
#   archenemy - install.sh
#   Installs dependencies and sets up symlinks
#   Usage: install.sh [--skip-packages]
#     --skip-packages  install no packages at all (Hyprland, yay, requirements,
#                      extras, ad-hoc packages of later steps) — requirements
#                      are still checked and reported. Always on for NixOS.
# =============================================

# -e is intentionally omitted: this installer has many optional steps and a
# declined/failed optional step must not abort the whole run. Criticals are
# checked explicitly instead.
set -uo pipefail

# Nigdy jako root (K8, audyt bezpieczeństwa 2026-11-14): instalator sam woła
# sudo tam, gdzie trzeba; jako root makepkg/yay budowałyby AUR z uprawnieniami
# roota, a $HOME wskazywałby /root zamiast domu użytkownika.
if [[ $EUID -eq 0 ]]; then
    echo "Error: do not run install.sh as root or with sudo — run it as your user; it asks for sudo when needed."
    exit 1
fi

# ─── FLAGI ────────────────────────────────────────────────────────────────────
# Przed czymkolwiek innym: nieznana opcja = odmowa, nic nie zapisane.
usage() {
    echo "Usage: install.sh [--skip-packages]"
    echo "  --skip-packages  do not install any package (requirements are still checked);"
    echo "                   always on for NixOS"
}
SKIP_PACKAGES=0
for arg in "$@"; do
    case "$arg" in
        --skip-packages) SKIP_PACKAGES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown option: $arg"; usage; exit 1 ;;
    esac
done

ARCHENEMY_DIR="$HOME/archenemy"
RICES_DIR="$ARCHENEMY_DIR/rices"
CONFIG_DIR="$HOME/.config"
PACMAN_REQ="$ARCHENEMY_DIR/packages/requirements-pacman.txt"
AUR_REQ="$ARCHENEMY_DIR/packages/requirements-aur.txt"
CURRENT_RICE="$ARCHENEMY_DIR/.current_rice"
DEFAULT_RICE="white-blue"
MONITOR_CONF="$ARCHENEMY_DIR/config/hypr/monitorshyprl.lua"
DATA_DIR="$ARCHENEMY_DIR/data"

# Track what happens for the final summary
declare -a SUMMARY_DONE=()
declare -a SUMMARY_SKIPPED=()

# ─── SANITY: are we actually in the archenemy repo at ~/archenemy? ─────────────
if [[ ! -d "$RICES_DIR" || ! -d "$ARCHENEMY_DIR/packages" ]]; then
    echo "Error: expected the archenemy repo at $ARCHENEMY_DIR (with rices/ and packages/)."
    echo "Clone it to your home directory: git clone <repo> ~/archenemy"
    exit 1
fi
# D10: checkout w /nix/store (np. ~/archenemy jako link z home-managera) jest
# tylko do odczytu, a instalator i Super+T piszą w nim warstwy osobistą
# i maszynową (data/, config/, .current_rice) — odmowa, zanim cokolwiek zapiszemy.
NIX_STORE_DIR=/nix/store
[[ "${ARCHENEMY_TEST:-}" == 1 && -n "${ARCHENEMY_NIX_STORE:-}" ]] && NIX_STORE_DIR="$ARCHENEMY_NIX_STORE"
if [[ "$(readlink -m -- "$ARCHENEMY_DIR")" == "$NIX_STORE_DIR"/* ]]; then
    echo "Error: $ARCHENEMY_DIR points into $NIX_STORE_DIR, which is read-only."
    echo "archenemy writes its personal and machine layers into the checkout: keep a writable clone,"
    echo "git clone <repo> ~/archenemy, and do not manage ~/archenemy with home-manager."
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── PLATFORMA (D5, inne dystrybucje EKSPERYMENTALNE) ─────────────────────────
# install/lib/pkg.sh wykrywa dystrybucję z os-release, zanim cokolwiek zapiszemy.
# Arch i jego pochodne (EndeavourOS, Manjaro… — decyzja właściciela 2026-11-17)
# idą DOTYCHCZASOWYM kodem kroków [2]/[4]/[5]: te same pytania, komendy i skutki;
# biblioteki używa tylko Fedora i NixOS. Inna dystrybucja = odmowa tutaj.
# shellcheck source=install/lib/pkg.sh
if ! source "$ARCHENEMY_DIR/install/lib/pkg.sh"; then
    echo "Error: cannot load $ARCHENEMY_DIR/install/lib/pkg.sh — is the repo complete?"
    exit 1
fi
# pkg_route: ta sama funkcja wyboru ścieżki co w pomocnikach install/*.sh (D6).
if pkg_route; then
    PLATFORM="$PKG_ROUTE"
else
    echo "Error: nothing was installed or changed."
    exit 1
fi
case "$PLATFORM" in
    fedora) PLATFORM_NAME="Fedora" ;;
    nixos)  PLATFORM_NAME="NixOS"; SKIP_PACKAGES=1 ;;   # deklaratywnie: nigdy instalacji
    *)      PLATFORM_NAME="Arch Linux" ;;
esac
# Etykieta komunikatów o krokach pominiętych przez platformę albo flagę.
PLATFORM_LABEL="$PLATFORM_NAME"
[[ "$PLATFORM" == arch ]] && PLATFORM_LABEL="Arch Linux with --skip-packages"

# Hasło sudo unieważniane na KAŻDYM wyjściu (K18; I4 z przeglądu 2026-11-15):
# Ctrl+C, exit z [2], przerwanie przez `set -u` — nie tylko na zwykłym końcu.
# Tylko tam, gdzie instalator używa sudo (P4 z przeglądu D5): Arch (także
# z --skip-packages: usługi w [6]–[10]) i Fedora z instalacją dnf. NixOS
# i Fedora z --skip-packages nie wołają sudo wcale — więc i `sudo -k`. Przed
# wykryciem platformy sudo nie pada, pułapka nie jest potrzebna.
# `trap … EXIT` zastępuje poprzednią pułapkę, więc pułapki z [3] (katalog
# monitors.new) też kończą się `sudo -k` z tym samym warunkiem; zmieniasz
# jedną — zmień wszystkie (pilnuje tests/install-guards.sh).
USES_SUDO=1
[[ "$PLATFORM" != arch && "$SKIP_PACKAGES" -eq 1 ]] && USES_SUDO=0
[[ "$USES_SUDO" == 0 ]] || trap 'sudo -k 2>/dev/null' EXIT

# manual_step <co> <jak zrobić to ręcznie> [summary] — zamiast kroku, którego na
# tej platformie (albo z --skip-packages) instalator nie wykonuje. Instalatory
# systemowe i usługi z kroków [6]–[10] działają dziś tylko na Archu; Fedora/NixOS
# dostaną je w etapach D6/D7 planu. „summary” = wpis w podsumowaniu [11].
manual_step() {
    echo -e "  ${YELLOW}⚠ $1: not done automatically on $PLATFORM_LABEL — $2${NC}"
    [[ "${3:-}" == summary ]] && SUMMARY_SKIPPED+=("$1 — not done on $PLATFORM_LABEL: $2")
    return 0
}

# svc_check [--user] <jednostka> — SAM ODCZYT stanu usługi (D7), bez zmian:
# 0 = enabled i active, 1 = enabled, ale nie działa (inactive/failed),
# 2 = nie enabled (albo brak jednostki/busa użytkownika). ✓ usługi dopiero po 0:
# kod 0 z `systemctl enable --now` ani samo is-enabled nie dowodzą, że usługa
# działa. Kolejność odczytów: is-enabled, potem is-active (jak dotychczasowe
# odczyty kroków), a przy „nie enabled” is-active nie pada wcale.
svc_check() {
    local -a scope=()
    [[ "$1" == --user ]] && { scope=(--user); shift; }
    systemctl "${scope[@]}" is-enabled --quiet "$1" 2>/dev/null || return 2
    systemctl "${scope[@]}" is-active --quiet "$1" 2>/dev/null || return 1
    return 0
}
# svc_dead <co> <polecenie sprawdzenia> — usługa enabled, ale martwa: ostrzeżenie
# z poleceniem do ręcznego sprawdzenia i wpis w podsumowaniu, bez ✓ i bez zmian.
svc_dead() {
    echo -e "  ${YELLOW}⚠ $1 is enabled but not running — check: $2${NC}"
    SUMMARY_SKIPPED+=("$1 — enabled but not running, check: $2")
}

# ─── 1. WELCOME ───────────────────────────────────────────────────────────────

clear
echo -e "${BLUE}"
echo "  ┌─────────────────────────────────────┐"
echo "  │           archenemy                 │"
echo "  │                        made by kst  │"
echo "  └─────────────────────────────────────┘"
echo -e "${NC}"
echo -e "  Welcome to archenemy install script!"
echo ""
# Na Archu bez flagi nic nowego na ekranie (wyjście identyczne z dotychczasowym).
if [[ "$PLATFORM" != arch ]]; then
    echo -e "  ${YELLOW}$PLATFORM_NAME support is experimental — Arch Linux remains the reference platform.${NC}"
fi
if [[ "$PLATFORM" == nixos ]]; then
    echo -e "  ${YELLOW}NixOS is declarative: archenemy installs nothing (--skip-packages is always on).${NC}"
    echo -e "  ${YELLOW}It checks the requirements and tells you what to add to your configuration.${NC}"
elif [[ "$SKIP_PACKAGES" -eq 1 ]]; then
    echo -e "  ${YELLOW}--skip-packages: no package will be installed; requirements are only checked.${NC}"
fi
[[ "$PLATFORM" != arch || "$SKIP_PACKAGES" -eq 1 ]] && echo ""
sleep 3

# ─── 2. CHECK HYPRLAND ────────────────────────────────────────────────────────

if ! command -v hyprctl &>/dev/null; then
    echo -e "${RED}Hyprland is not installed.${NC}"
    if [[ "$SKIP_PACKAGES" -eq 1 ]]; then
        # Bez instalacji nie ma czego dalej konfigurować: instrukcja i koniec.
        case "$PLATFORM" in
            arch)   echo -e "Install it yourself: sudo pacman -S --needed hyprland" ;;
            nixos)  echo -e "$(pkg_hint hyprland) — archenemy needs Hyprland 0.56 or newer"
                    echo -e "(nixos-26.05 ships 0.55.4: use nixos-unstable or the Hyprland flake)." ;;
            *)      echo -e "Install it yourself (Hyprland 0.56 or newer): $(pkg_hint hyprland)" ;;
        esac
        echo -e "${YELLOW}Then reboot, log in to Hyprland and run install.sh again.${NC}"
        exit 1
    fi
    if [[ "$PLATFORM" == fedora ]]; then
        # Hyprland Fedory jest za stary (< 0.56, Lua): jedyne źródło to COPR
        # nett00n/hyprland — pkg_install_extra pokazuje je i pyta [y/N].
        echo -e "Fedora's own Hyprland is older than 0.56, which archenemy needs."
        pkg_install_extra hyprland
        case $? in
            0)  echo ""
                echo -e "${GREEN}Hyprland installed.${NC}"
                echo -e "${YELLOW}Please reboot and log in to Hyprland. Then run install.sh again.${NC}"
                exit 0 ;;
            3)  echo -e "${YELLOW}Exiting.${NC}"
                exit 0 ;;
            *)  echo ""
                echo -e "${RED}✗ Hyprland installation failed — check the dnf output above and retry.${NC}"
                exit 1 ;;
        esac
    fi
    echo -e "Do you allow me to install Hyprland? It is required for this to work."
    read -rp "[y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        # Sukces ogłaszamy dopiero po sprawdzeniu kodu wyjścia pacmana —
        # „Hyprland installed." przy nieudanej instalacji wprowadzał w błąd.
        if sudo pacman -S --needed hyprland; then
            echo ""
            echo -e "${GREEN}Hyprland installed.${NC}"
            echo -e "${YELLOW}Please reboot and log in to Hyprland. Then run install.sh again.${NC}"
        else
            echo ""
            echo -e "${RED}✗ Hyprland installation failed — check pacman output above and retry.${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Exiting.${NC}"
    fi
    exit 0
fi

echo -e "${GREEN}✓ Hyprland found.${NC}"

# ─── 2b. ZGODNOŚĆ WERSJI (Fedora, NixOS) ──────────────────────────────────────
# P1 z przeglądu D5: PRZED pierwszym zapisem (mkdir data/monitors w [3]).
# Configi Lua potrzebują Hyprlanda ≥ min z mapy (0.56) — DZIAŁAJĄCEJ instancji
# (to ona przeładuje config w [11]) i, na Fedorze, pakietu (wejdzie po
# ponownym logowaniu); tapety — hyprpapera ≥ 0.8.2 (packages/platform-map.tsv).
# Niezgodność = komunikat, kod 1, zero zapisów i instalacji. Brak hyprpapera
# zgłasza [5] (Fedora doinstaluje go z COPR, który ma wersję z mapy). Wersja
# NIEUSTALONA (NixOS: hyprpaper spoza sklepu Nix, Fedora: błąd zapytania rpm
# o hyprpaper albo hyprland) też = odmowa (Dodatek 3 i B1 do D5F): zgodności
# nie da się potwierdzić przed zapisami. Brak pakietu hyprland na Fedorze
# (Hyprland spoza rpm) odmową nie jest — decyduje działająca sesja.
# Arch BEZ tej kontroli (parytet z bazą; wersje trzyma repozytorium Archa).
# hypr_running_version — wersja z 1. linii `hyprctl version`: „Hyprland <wersja>
# built from branch …” (src/helpers/SystemInfo.cpp, v0.56.2 i v0.57.1).
hypr_running_version() {
    local out
    out="$(hyprctl version 2>/dev/null)" || return 1
    [[ "${out%%$'\n'*}" =~ ^Hyprland\ v?([0-9]+(\.[0-9]+)+)([[:space:]]|$) ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}
if [[ "$PLATFORM" != arch ]]; then
    VERSION_PROBLEMS=()
    HYPR_NOTE=""
    HYPR_MIN="$(pkg_min_version hyprland)" || HYPR_MIN=0.56
    PAPER_MIN="$(pkg_min_version hyprpaper)" || PAPER_MIN=0.8.2
    if [[ "$PLATFORM" == nixos ]]; then
        HYPR_UPGRADE="nixos-26.05 ships 0.55.4: use nixos-unstable or the Hyprland flake (programs.hyprland.package)"
    else
        HYPR_UPGRADE="upgrade from COPR: $(pkg_hint hyprland)"
    fi
    if HYPR_RUN="$(hypr_running_version)"; then
        if ! pkg_version_ge "$HYPR_RUN" "$HYPR_MIN"; then
            VERSION_PROBLEMS+=("running Hyprland is $HYPR_RUN — archenemy needs $HYPR_MIN or newer (Lua configs)")
        fi
    else
        VERSION_PROBLEMS+=("cannot read the version of the running Hyprland (hyprctl version) — run install.sh inside a Hyprland $HYPR_MIN+ session")
    fi
    if [[ "$PLATFORM" == fedora ]]; then
        # B1 (przegląd D5F): rc 1 (brak pakietu, np. Hyprland spoza rpm) —
        # bez odmowy, decyduje działająca sesja, pakiet zgłosi [5]; rc 2
        # (błąd zapytania rpm, pusta wersja) — nieustalona = odmowa.
        HYPR_PKG="$(pkg_version hyprland)"
        case $? in
            0) [[ -n "${HYPR_RUN:-}" ]] && ! pkg_version_ge "$HYPR_RUN" "$HYPR_MIN" \
                   && HYPR_UPGRADE="Hyprland $HYPR_PKG is installed — log out and back in to Hyprland, then run install.sh again" ;;
            1) HYPR_NOTE="hyprland package not installed — checked in [5]" ;;
            3) VERSION_PROBLEMS+=("installed Hyprland package is $HYPR_PKG — archenemy needs $HYPR_MIN or newer") ;;
            *) VERSION_PROBLEMS+=("cannot determine the installed Hyprland package version (rpm -q hyprland failed) — archenemy needs $HYPR_MIN or newer; $(pkg_hint hyprland)") ;;
        esac
    fi
    PAPER_VER="$(pkg_version hyprpaper)"
    case $? in
        0) PAPER_NOTE="hyprpaper $PAPER_VER" ;;
        1) PAPER_NOTE="hyprpaper not installed yet (checked in [5])" ;;
        3) PAPER_NOTE=""
           VERSION_PROBLEMS+=("hyprpaper is $PAPER_VER — archenemy needs $PAPER_MIN or newer; $(pkg_hint hyprpaper)") ;;
        *) PAPER_NOTE=""
           if [[ "$PLATFORM" == nixos ]]; then
               PAPER_WHY="it does not resolve to a Nix store path /nix/store/<hash>-hyprpaper-<version>"
           else
               PAPER_WHY="rpm -q hyprpaper failed"
           fi
           VERSION_PROBLEMS+=("cannot determine the hyprpaper version — archenemy needs $PAPER_MIN or newer ($PAPER_WHY); $(pkg_hint hyprpaper)") ;;
    esac
    if ((${#VERSION_PROBLEMS[@]})); then
        for p in "${VERSION_PROBLEMS[@]}"; do echo -e "${RED}✗ $p${NC}"; done
        # Bez powtórki: przy błędzie rpm podpowiedź pakietu jest już w komunikacie.
        [[ "${VERSION_PROBLEMS[*]}" == *Hyprland* && "${VERSION_PROBLEMS[*]}" != *"$(pkg_hint hyprland)"* ]] \
            && echo -e "  Hyprland: $HYPR_UPGRADE"
        echo -e "${YELLOW}Nothing was installed or changed.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Hyprland $HYPR_RUN (running${HYPR_NOTE:+; $HYPR_NOTE})${PAPER_NOTE:+, $PAPER_NOTE} — versions compatible.${NC}"
fi
echo ""

# ─── 3. CHECK MONITORS ────────────────────────────────────────────────────────

echo -e "${CYAN}[3] Detecting monitors...${NC}"

# Oprócz nazw czytamy z hyprctl AKTUALNE ustawienia (rozdzielczość, Hz,
# pozycję, skalę) — będą domyślnymi odpowiedziami w kroku [3.5], więc
# Enter wszędzie = zostaw układ tak, jak działa teraz.
MONITOR_NAMES=()
declare -A CUR_RES
declare -A CUR_RATE
declare -A CUR_POS
declare -A CUR_SCALE
# Opis z EDID (producent+model+seria) — TRWAŁA tożsamość monitora; nazwa
# złącza (eDP-2 → eDP-1, HDMI-A-1 → HDMI-A-3) zmienia się po restarcie/
# przepięciu i rozjeżdżała reguły warstwy maszynowej (live 2026-09-21).
# Generatory [8a]/[8b] i tapety celują w "desc:<opis>" — lib/monitor-id.sh.
declare -A CUR_DESC
declare -A CUR_MAKE CUR_MODEL CUR_SERIAL
source "$ARCHENEMY_DIR/scripts/hypr/lib/monitor-id.sh"

cur_mon=""
while IFS= read -r line; do
    if [[ "$line" =~ ^Monitor[[:space:]]+([^[:space:]]+) ]]; then
        cur_mon="${BASH_REMATCH[1]}"
        MONITOR_NAMES+=("$cur_mon")
    elif [[ -n "$cur_mon" && "$line" =~ ([0-9]+x[0-9]+)@([0-9]+(\.[0-9]+)?)(Hz)?[[:space:]]+at[[:space:]]+(-?[0-9]+x-?[0-9]+) ]]; then
        CUR_RES[$cur_mon]="${BASH_REMATCH[1]}"
        # hyprctl podaje np. 239.998 — zaokrąglamy do trybu, który user zna (240).
        # LC_ALL=C: w polskim locale printf oczekuje przecinka i "239.998" byłoby błędem.
        CUR_RATE[$cur_mon]=$(LC_ALL=C printf '%.0f' "${BASH_REMATCH[2]}")
        CUR_POS[$cur_mon]="${BASH_REMATCH[5]}"
    elif [[ -n "$cur_mon" && "$line" =~ scale:[[:space:]]*([0-9]+(\.[0-9]+)?) ]]; then
        CUR_SCALE[$cur_mon]="${BASH_REMATCH[1]}"
    elif [[ -n "$cur_mon" && "$line" =~ ^[[:space:]]*make:[[:space:]]*(.*)$ ]]; then
        CUR_MAKE[$cur_mon]="${BASH_REMATCH[1]}"
    elif [[ -n "$cur_mon" && "$line" =~ ^[[:space:]]*model:[[:space:]]*(.*)$ ]]; then
        CUR_MODEL[$cur_mon]="${BASH_REMATCH[1]}"
    elif [[ -n "$cur_mon" && "$line" =~ ^[[:space:]]*serial:[[:space:]]*(.*)$ ]]; then
        CUR_SERIAL[$cur_mon]="${BASH_REMATCH[1]}"
    fi
done < <(hyprctl monitors)

if [[ ${#MONITOR_NAMES[@]} -eq 0 ]]; then
    echo -e "${RED}No monitors detected. Make sure Hyprland is running.${NC}"
    exit 1
fi

# Opis = "make model serial" (krótki opis Hyprlanda, prefiks pełnego), bez
# przecinków (Hyprland je usuwa). Do selektora desc: trafia TYLKO opis
# użyteczny (monitor_desc_usable) i UNIKALNY: gdy opis jednego monitora jest
# prefiksem opisu innego (identyczne modele bez numeru seryjnego), dopasowanie
# po prefiksie objęłoby oba — wtedy oba zostają przy nazwie złącza.
for mon in "${MONITOR_NAMES[@]}"; do
    CUR_DESC[$mon]="$(monitor_short_desc "${CUR_MAKE[$mon]:-}" "${CUR_MODEL[$mon]:-}" "${CUR_SERIAL[$mon]:-}")"
done
for mon in "${MONITOR_NAMES[@]}"; do
    [[ -n "${CUR_DESC[$mon]}" ]] || continue
    for other in "${MONITOR_NAMES[@]}"; do
        [[ "$other" == "$mon" || -z "${CUR_DESC[$other]:-}" ]] && continue
        if monitor_descs_collide "${CUR_DESC[$mon]}" "${CUR_DESC[$other]}"; then
            echo -e "  ${YELLOW}⚠ $mon and $other have indistinguishable EDID descriptions: ${CUR_DESC[$mon]} — rules will use connector names.${NC}"
            CUR_DESC[$mon]=""; CUR_DESC[$other]=""
        fi
    done
done

echo -e "  ${GREEN}Detected monitors:${NC}"
for i in "${!MONITOR_NAMES[@]}"; do
    mon="${MONITOR_NAMES[$i]}"
    echo "    $((i+1))) $mon — ${CUR_RES[$mon]:-?}@${CUR_RATE[$mon]:-?}Hz, position ${CUR_POS[$mon]:-?}, scale ${CUR_SCALE[$mon]:-?}"
    echo "       description (EDID): ${CUR_DESC[$mon]:-NONE — rules will use the connector name}"
done
echo ""

mkdir -p "$DATA_DIR/monitors"
# Nowe .dat powstają w katalogu tymczasowym OBOK data/monitors/ i trafiają na
# miejsce dopiero po ostatnim pytaniu [3.7] (commit_monitor_dats) — dotąd
# `rm -f *.dat` szło tutaj, PRZED pytaniami [3.5]–[3.7], i Ctrl-C w trakcie
# zostawiał data/monitors/ pusty (audyt 2026-09-25). Konsumenci
# (gen-workspaces.sh, wallpaper switcher, [8a], [9.7]) czytają
# data/monitors/*.dat — do commitu widzą stary komplet, po nim tylko nowy.
# Katalog po biegu zabitym bez trapa (SIGKILL) sprzątamy tu; własny — trapem.
rm -rf "$DATA_DIR"/monitors.new.*
MON_TMP="$(mktemp -d "$DATA_DIR/monitors.new.XXXXXX")"
# Ta pułapka zastępuje tę spod wykrycia platformy — `sudo -k` (z warunkiem USES_SUDO) musi zostać (K18).
trap 'rm -rf "$MON_TMP"; [[ "${USES_SUDO:-1}" == 0 ]] || sudo -k 2>/dev/null' EXIT
# Podmiana: stare .dat (także po monitorach, których już nie ma — inaczej
# wallpaper switcher mógłby wybrać odłączony monitor jako primary/secondary)
# znikają w tej samej chwili, w której wchodzą nowe (mv w obrębie data/ =
# rename, bez okna z pustym katalogiem dłuższym niż kilka syscalli).
commit_monitor_dats() {
    rm -f "$DATA_DIR/monitors"/*.dat
    mv "$MON_TMP"/*.dat "$DATA_DIR/monitors/"
    rmdir "$MON_TMP"
    # Katalog już pusty i usunięty — wraca sama pułapka sudo (K18).
    trap '[[ "${USES_SUDO:-1}" == 0 ]] || sudo -k 2>/dev/null' EXIT
}

declare -A MON_RES
declare -A MON_RATE
declare -A MON_POS
declare -A MON_SCALE
declare -A MON_ORDER

# ─── 3.5 MONITOR LAYOUT ───────────────────────────────────────────────────────

echo -e "${CYAN}[3.5] Configure monitor layout...${NC}"
echo ""

# Obecna rola monitora = ROLE z .dat, którego selektor (desc: albo nazwa złącza,
# lib/monitor-id.sh) wskazuje TERAZ ten monitor — tak samo rozwiązują go tapety.
# Stare data/monitors/*.dat leżą na miejscu do [3.7]. Enter w pytaniu o rolę =
# ta rola: nagłówek obiecuje „keep current setting”, a rola szła z kolejności
# monitora i ponowny bieg zamieniał primary/secondary, czyli tapety v1/v2
# (audyt 2026-11-05, Z4). Trafienie po desc: wygrywa z trafieniem po nazwie
# (dwa przebiegi). ORDER nadal z pozycji X w [3.6] (DECYZJE 2026-07-17 D3).
declare -A PREV_ROLE=()
declare -A MON_ROLE=()
for pass in name desc; do
    for f in "$DATA_DIR/monitors"/*.dat; do
        [[ -f "$f" ]] || continue
        sel="$(monitor_selector_from_dat "$f")"
        if [[ "$sel" == desc:* ]]; then kind=desc; else kind=name; fi
        [[ "$kind" == "$pass" ]] || continue
        role="$(grep -m1 '^ROLE=' "$f" | cut -d= -f2-)"
        [[ "$role" == primary || "$role" == secondary || "$role" == other ]] || continue
        live="$(monitor_live_name "$sel")"
        [[ -n "$live" ]] && PREV_ROLE[$live]="$role"
    done
done

# Monitor bez obecnej roli (nowy albo .dat z dawną nazwą złącza): pierwsza rola,
# której nie ma żaden inny podłączony monitor — wybór z tego biegu, a dla
# monitorów jeszcze przed pytaniem ich obecna rola. Jak default_role
# w monitor-settings.sh; świeża instalacja = dawne „pierwszy primary, drugi
# secondary, reszta other”.
first_free_role() {
    local m r taken=" "
    for m in "${MONITOR_NAMES[@]}"; do
        [[ "$m" == "$1" ]] && continue
        r="${MON_ROLE[$m]:-${PREV_ROLE[$m]:-}}"
        taken+="$r "
    done
    if [[ "$taken" != *" primary "* ]]; then echo primary
    elif [[ "$taken" != *" secondary "* ]]; then echo secondary
    else echo other
    fi
}

for mon in "${MONITOR_NAMES[@]}"; do
    echo -e "${YELLOW}Monitor: ${BLUE}$mon${NC}  ${NC}(Enter = keep current setting)${NC}"

    # Domyślne = to, co monitor robi TERAZ (odczytane w [3]); gdy odczyt się
    # nie udał — bezpieczne 'preferred'/'auto', którymi Hyprland sam zarządzi.
    def_res="${CUR_RES[$mon]:-preferred}"
    def_rate="${CUR_RATE[$mon]:-}"
    def_pos="${CUR_POS[$mon]:-auto}"
    def_scale="${CUR_SCALE[$mon]:-1}"

    while :; do
        read -rp "  Resolution [${def_res}]: " res
        res="${res:-$def_res}"
        [[ "$res" =~ ^[0-9]+x[0-9]+$ || "$res" == "preferred" || "$res" == "highres" || "$res" == "highrr" ]] && break
        echo -e "  ${YELLOW}⚠ Format: WIDTHxHEIGHT (e.g. 1920x1080) or preferred/highres/highrr.${NC}"
    done

    if [[ "$res" == "preferred" || "$res" == "highres" || "$res" == "highrr" ]]; then
        # Te tryby same dobierają częstotliwość — 'preferred@144' to błędny zapis
        rate=""
    else
        while :; do
            read -rp "  Refresh rate in Hz [${def_rate:-auto}]: " rate
            rate="${rate:-$def_rate}"
            [[ -z "$rate" || "$rate" =~ ^[0-9]+(\.[0-9]+)?$ ]] && break
            echo -e "  ${YELLOW}⚠ Enter a number (e.g. 144) or press Enter.${NC}"
        done
    fi

    while :; do
        read -rp "  Position XxY [${def_pos}]: " pos
        pos="${pos:-$def_pos}"
        pos="${pos// /x}"   # akceptuj też zapis '1920 0'
        [[ "$pos" =~ ^-?[0-9]+x-?[0-9]+$ || "$pos" == "auto" ]] && break
        echo -e "  ${YELLOW}⚠ Format: XxY (e.g. 1920x0) or 'auto'.${NC}"
    done

    while :; do
        read -rp "  Scale [${def_scale}]: " scale
        scale="${scale:-$def_scale}"
        [[ "$scale" =~ ^[0-9]+(\.[0-9]+)?$ || "$scale" == "auto" ]] && break
        echo -e "  ${YELLOW}⚠ Enter a number (e.g. 1, 1.33, 2) or 'auto'.${NC}"
    done

    # Domyślna rola: obecna (PREV_ROLE), inaczej pierwsza wolna.
    # (rofi_wallpaper_switcher.sh maps primary→v1, secondary→v2.)
    def_role="${PREV_ROLE[$mon]:-$(first_free_role "$mon")}"
    while :; do
        read -rp "  Role (primary/secondary/other) [${def_role}]: " role
        role="${role:-$def_role}"
        [[ "$role" == "primary" || "$role" == "secondary" || "$role" == "other" ]] && break
        echo -e "  ${YELLOW}⚠ Choose: primary, secondary or other.${NC}"
    done
    MON_ROLE[$mon]="$role"

    # Poza [3.5] (MON_ROLE = tylko domyślne następnych monitorów) rola żyje
    # wyłącznie w .dat (czyta ją wallpaper switcher) — od 2026-07-17 [8b] nie
    # czyta ról, workspace'ami rządzi ORDER+tryb.
    MON_RES[$mon]="$res"
    MON_RATE[$mon]="$rate"
    MON_POS[$mon]="$pos"
    MON_SCALE[$mon]="$scale"

    {
        echo "MONITOR=$mon"
        echo "RESOLUTION=$res"
        echo "RATE=$rate"
        echo "POSITION=$pos"
        echo "SCALE=$scale"
        echo "ROLE=$role"
        echo "DESCRIPTION=${CUR_DESC[$mon]:-}"
    } > "$MON_TMP/$mon.dat"

    echo -e "  ${GREEN}✓ $mon.dat ready (saved to data/monitors/ after [3.7])${NC}"
    echo ""
done

# ─── 3.6 MONITOR NUMBERING (lewa→prawa) ──────────────────────────────────────

echo -e "${CYAN}[3.6] Monitor numbering (left→right)...${NC}"
echo ""
echo -e "  Monitors get numbers ${YELLOW}1, 2, 3…${NC} counted ${YELLOW}from left to right${NC}"
echo -e "  (monitor 1 = leftmost on the desk). These numbers determine workspace"
echo -e "  assignment — choose the mode in the next step."
echo ""

# Propozycja automatyczna: sortowanie po współrzędnej X pozycji z [3.5].
# Pozycja 'auto'/nieparsowalna → na koniec listy (stabilnie, w kolejności z [3]).
ORDER_PROPOSED=()
_with_x=()
_without_x=()
for i in "${!MONITOR_NAMES[@]}"; do
    mon="${MONITOR_NAMES[$i]}"
    if [[ "${MON_POS[$mon]}" =~ ^(-?[0-9]+)x-?[0-9]+$ ]]; then
        _with_x+=("${BASH_REMATCH[1]} $i")
    else
        _without_x+=("$i")
    fi
done
if [[ ${#_with_x[@]} -gt 0 ]]; then
    while read -r _ i; do
        [[ -n "$i" ]] && ORDER_PROPOSED+=("$i")
    done < <(printf '%s\n' "${_with_x[@]}" | sort -n -s -k1,1)
fi
if [[ ${#_without_x[@]} -gt 0 ]]; then
    ORDER_PROPOSED+=("${_without_x[@]}")
fi

if [[ ${#MONITOR_NAMES[@]} -eq 1 ]]; then
    mon="${MONITOR_NAMES[0]}"
    MON_ORDER[$mon]=1
    echo "ORDER=1" >> "$MON_TMP/$mon.dat"
    echo -e "  ${GREEN}✓ One monitor ($mon) — number 1.${NC}"
else
    while :; do
        echo -e "  Proposed numbering (from X positions):"
        for k in "${!ORDER_PROPOSED[@]}"; do
            i="${ORDER_PROPOSED[$k]}"
            mon="${MONITOR_NAMES[$i]}"
            echo "    $((k+1))) $mon  (position ${MON_POS[$mon]})"
        done
        read -rp "  Enter = confirm, or enter your own order using list numbers (e.g. '2 1'): " -a picks
        [[ ${#picks[@]} -eq 0 ]] && break
        if [[ ${#picks[@]} -ne ${#ORDER_PROPOSED[@]} ]]; then
            echo -e "  ${YELLOW}⚠ Enter exactly ${#ORDER_PROPOSED[@]} numbers (one per monitor).${NC}"
            continue
        fi
        _ok=1
        _seen=""
        for n in "${picks[@]}"; do
            [[ "$n" =~ ^[0-9]+$ ]] || { _ok=0; break; }
            # 10#: „08” to dla basha zła liczba ósemkowa — błąd rozwinięcia
            # kończył cały instalator (audyt 2026-11-05, Z12).
            n=$((10#$n))
            if (( n < 1 || n > ${#ORDER_PROPOSED[@]} )) || [[ " $_seen " == *" $n "* ]]; then
                _ok=0
                break
            fi
            _seen+=" $n"
        done
        if [[ $_ok -eq 0 ]]; then
            echo -e "  ${YELLOW}⚠ Use each number from 1..${#ORDER_PROPOSED[@]} exactly once.${NC}"
            continue
        fi
        _reordered=()
        for n in $_seen; do
            _reordered+=("${ORDER_PROPOSED[$((n - 1))]}")
        done
        ORDER_PROPOSED=("${_reordered[@]}")
        break
    done
    ordk=1
    for i in "${ORDER_PROPOSED[@]}"; do
        mon="${MONITOR_NAMES[$i]}"
        MON_ORDER[$mon]=$ordk
        echo "ORDER=$ordk" >> "$MON_TMP/$mon.dat"
        echo -e "  ${GREEN}✓ $ordk → $mon${NC}"
        ordk=$((ordk + 1))
    done
fi
echo ""

# ─── 3.7 WORKSPACE MODE ──────────────────────────────────────────────────────

echo -e "${CYAN}[3.7] Workspace mode...${NC}"
echo ""
echo -e "  1) ${GREEN}shared${NC}  — 10 shared workspaces (1-10) across all monitors."
echo -e "     Monitor k (left→right numbering) has home workspace k. Super+1..0 works"
echo -e "     globally. Handles monitor unplugging without a guard daemon."
echo -e "  2) ${GREEN}decades${NC} — each monitor has its OWN workspaces 1-10 (isolated"
echo -e "     decades). Super+1..0 works on the focused monitor. A daemon"
echo -e "     merges workspaces when a monitor is unplugged."
echo ""
while :; do
    # Koniec wejścia (Ctrl-D, potok bez odpowiedzi) — to pytanie nie ma
    # domyślnej, więc pętla kręciła się bez końca (audyt 2026-11-05, Z13).
    # Kończymy jak Ctrl-C: trap sprząta nowe .dat, stare zostają na miejscu.
    if ! read -rp "  Choose mode [1/2]: " ws_choice && [[ -z "$ws_choice" ]]; then
        echo ""
        echo -e "  ${RED}✗ No answer (input closed) — stopping, data/monitors/ left unchanged.${NC}"
        exit 1
    fi
    case "$ws_choice" in
        1) WS_MODE="shared";  break ;;
        2) WS_MODE="decades"; break ;;
        *) echo -e "  ${YELLOW}⚠ Enter 1 or 2.${NC}" ;;
    esac
done
# Ostatnie pytanie o monitory za nami — dopiero teraz podmieniamy
# data/monitors/*.dat (patrz [3]).
commit_monitor_dats
echo -e "  ${GREEN}✓ data/monitors/*.dat saved (${#MONITOR_NAMES[@]} monitors)${NC}"
echo "$WS_MODE" > "$DATA_DIR/workspace-mode.dat"
echo -e "  ${GREEN}✓ Workspace mode: $WS_MODE${NC}"
echo ""

# ─── 4. CHECK YAY ─────────────────────────────────────────────────────────────

# shellcheck source=install/lib/aur.sh
source "$ARCHENEMY_DIR/install/lib/aur.sh"

if [[ "$PLATFORM" != arch ]]; then
    echo -e "${CYAN}[4] AUR helper (yay): not used on $PLATFORM_NAME.${NC}"
else
echo -e "${CYAN}[4] Checking yay...${NC}"

if ! command -v yay &>/dev/null; then
    echo -e "${YELLOW}yay not found.${NC}"
    if [[ "$SKIP_PACKAGES" -eq 1 ]]; then
        echo -e "${YELLOW}⚠ Not installed (--skip-packages) — AUR packages will be skipped without yay.${NC}"
        ans=n
    else
        read -rp "Install yay? [y/N]: " ans
    fi
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed git base-devel
        # Budowa w mktemp -d z przeglądem PKGBUILD (install/lib/aur.sh, K6+K7).
        aur_bootstrap_yay
    else
        [[ "$SKIP_PACKAGES" -eq 1 ]] || echo -e "${YELLOW}⚠ AUR packages will be skipped without yay.${NC}"
    fi
else
    echo -e "${GREEN}✓ yay found.${NC}"
fi
fi

echo ""

# ─── 5. CHECK REQUIREMENTS ────────────────────────────────────────────────────

echo -e "${CYAN}[5] Checking requirements...${NC}"
echo ""

# list_ids <plik…> — wpisy list pakietów tak jak czytają je pętle Archa niżej
# (pierwsze słowo linii, bez pustych i komentarzy); id mapy = nazwa z listy.
list_ids() {
    local f pkg
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r pkg || [[ -n "$pkg" ]]; do
            pkg="${pkg%%[[:space:]]*}"
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            printf '%s\n' "$pkg"
        done < "$f"
    done
}

# platform_check <id…> — Fedora/NixOS: stan każdego id przez pkg_installed;
# wynik w PLAT_MISSING (brak albo błąd zapytania) i PLAT_UNCHECKED (bez sondy).
platform_check() {
    local id
    PLAT_MISSING=(); PLAT_UNCHECKED=()
    for id in "$@"; do
        pkg_installed "$id"
        case $? in
            0) echo -e "  ${GREEN}✓ $id${NC}" ;;
            1) PLAT_MISSING+=("$id"); echo -e "  ${RED}✗ missing: $id${NC}" ;;
            3) PLAT_UNCHECKED+=("$id"); echo -e "  ${YELLOW}? not checked: $id — $(pkg_hint "$id")${NC}" ;;
            *) PLAT_MISSING+=("$id"); echo -e "  ${RED}✗ cannot query: $id${NC}" ;;
        esac
    done
}

# platform_install <etykieta> <id…> — Fedora: domyślne repo przez pkg_install,
# COPR nett00n/hyprland i repo Brave przez pkg_install_extra (każde źródło
# osobno [y/N]); sukces = ponowny odczyt pkg_installed. power-profiles-daemon
# osobną transakcją: tuned-ppd (domyślny na Fedora Workstation) jest z nim
# sprzeczny, dnf odmawia, a instalator NIE podmienia pakietów (bez
# --allowerasing; decyzja właściciela 2026-11-17) — reszta nie przepada przez
# tę jedną odmowę. Niezainstalowane: podpowiedź i wpis w podsumowaniu.
platform_install() {
    local label="$1" id
    shift
    local -a main=() ppd=() still=()
    local ppd_conflict=0
    for id in "$@"; do
        if [[ "$id" == power-profiles-daemon ]]; then ppd+=("$id"); else main+=("$id"); fi
    done
    if ((${#main[@]})); then
        pkg_install "${main[@]}"
        if ((${#PKG_SKIPPED[@]})); then
            local -a rest=("${PKG_SKIPPED[@]}")
            pkg_install_extra "${rest[@]}"
        fi
    fi
    if ((${#ppd[@]})) && ! pkg_install power-profiles-daemon \
            && rpm -q tuned-ppd >/dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠ power-profiles-daemon conflicts with tuned-ppd (Fedora's default), and archenemy${NC}"
        echo -e "  ${YELLOW}  does not replace installed packages. The bar's profile switcher needs powerprofilesctl:${NC}"
        echo -e "  ${YELLOW}  sudo dnf swap tuned-ppd power-profiles-daemon${NC}"
        SUMMARY_SKIPPED+=("power-profiles-daemon — conflicts with tuned-ppd, switch manually: sudo dnf swap tuned-ppd power-profiles-daemon")
        ppd_conflict=1
    fi
    for id in "$@"; do
        pkg_installed "$id" >/dev/null 2>&1 || still+=("$id")
    done
    for id in "${still[@]}"; do
        [[ "$id" == power-profiles-daemon && $ppd_conflict -eq 1 ]] && continue
        echo -e "  ${RED}✗ not installed: $id${NC} — $(pkg_hint "$id")"
        SUMMARY_SKIPPED+=("$label not installed: $id — $(pkg_hint "$id")")
    done
}

if [[ "$PLATFORM" != arch ]]; then
    mapfile -t REQ_IDS < <(list_ids "$PACMAN_REQ" "$AUR_REQ")
    platform_check "${REQ_IDS[@]}"
    if [[ ${#PLAT_MISSING[@]} -gt 0 ]]; then
        echo ""
        if [[ "$PLATFORM" == nixos ]]; then
            # pkg_install na NixOS niczego nie zmienia — wypisuje, co dodać do konfiguracji.
            pkg_install "${PLAT_MISSING[@]}"
            SUMMARY_SKIPPED+=("REQUIRED packages missing — add them to your NixOS configuration: ${PLAT_MISSING[*]}")
        elif [[ "$SKIP_PACKAGES" -eq 1 ]]; then
            for id in "${PLAT_MISSING[@]}"; do echo "  $id: $(pkg_hint "$id")"; done
            SUMMARY_SKIPPED+=("REQUIRED packages not installed (--skip-packages): ${PLAT_MISSING[*]}")
        else
            read -rp "Install missing packages with dnf? [Y/n]: " ans
            if [[ ! "$ans" =~ ^[Nn]$ ]]; then
                platform_install "REQUIRED package" "${PLAT_MISSING[@]}"
            else
                SUMMARY_SKIPPED+=("REQUIRED packages skipped by request: ${PLAT_MISSING[*]}")
            fi
        fi
    fi
    if [[ ${#PLAT_UNCHECKED[@]} -gt 0 && "$PLATFORM" == fedora ]]; then
        SUMMARY_SKIPPED+=("Not checked on Fedora (install manually, see README): ${PLAT_UNCHECKED[*]}")
    fi
else
MISSING_PACMAN=()
if [[ -f "$PACMAN_REQ" ]]; then
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
        pkg="${pkg%%[[:space:]]*}"
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        if ! pacman -Qi "$pkg" &>/dev/null; then
            MISSING_PACMAN+=("$pkg")
            echo -e "  ${RED}✗ missing: $pkg${NC}"
        else
            echo -e "  ${GREEN}✓ $pkg${NC}"
        fi
    done < "$PACMAN_REQ"
fi

if [[ ${#MISSING_PACMAN[@]} -gt 0 && "$SKIP_PACKAGES" -eq 1 ]]; then
    echo ""
    echo -e "  ${YELLOW}⚠ Not installed (--skip-packages): sudo pacman -S --needed ${MISSING_PACMAN[*]}${NC}"
    SUMMARY_SKIPPED+=("REQUIRED pacman packages not installed (--skip-packages): ${MISSING_PACMAN[*]} (sudo pacman -S --needed ${MISSING_PACMAN[*]})")
elif [[ ${#MISSING_PACMAN[@]} -gt 0 ]]; then
    echo ""
    # Pakiety WYMAGANE → default-Yes; odmowę i niepowodzenie rejestrujemy
    # w SUMMARY_SKIPPED (dotąd default-No bez śladu — nieudana/odrzucona
    # instalacja kończyła się czystym podsumowaniem, a configi wołały
    # nieistniejące binarki).
    read -rp "Install missing pacman packages? [Y/n]: " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        if ! sudo pacman -S --needed "${MISSING_PACMAN[@]}"; then
            echo -e "${RED}✗ pacman failed to install required packages.${NC}"
            SUMMARY_SKIPPED+=("REQUIRED pacman packages — installation FAILED: ${MISSING_PACMAN[*]}")
        fi
    else
        SUMMARY_SKIPPED+=("REQUIRED pacman packages skipped by request: ${MISSING_PACMAN[*]}")
    fi
fi

echo ""

MISSING_AUR=()
if [[ -f "$AUR_REQ" ]]; then
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
        pkg="${pkg%%[[:space:]]*}"
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        if ! pacman -Qi "$pkg" &>/dev/null; then
            MISSING_AUR+=("$pkg")
            echo -e "  ${RED}✗ missing: $pkg${NC}"
        else
            echo -e "  ${GREEN}✓ $pkg${NC}"
        fi
    done < "$AUR_REQ"
fi

if [[ ${#MISSING_AUR[@]} -gt 0 && "$SKIP_PACKAGES" -eq 1 ]]; then
    echo ""
    echo -e "  ${YELLOW}⚠ Not installed (--skip-packages): yay -S --needed ${MISSING_AUR[*]}${NC}"
    SUMMARY_SKIPPED+=("REQUIRED AUR packages not installed (--skip-packages): ${MISSING_AUR[*]} (yay -S --needed ${MISSING_AUR[*]})")
elif [[ ${#MISSING_AUR[@]} -gt 0 ]]; then
    echo ""
    # Jak wyżej: wymagane → default-Yes + rejestr niepowodzeń w SUMMARY_SKIPPED.
    read -rp "Install missing AUR packages with yay? [Y/n]: " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        if command -v yay &>/dev/null; then
            if ! aur_install "${MISSING_AUR[@]}"; then
                echo -e "${RED}✗ yay failed to install required packages.${NC}"
                SUMMARY_SKIPPED+=("REQUIRED AUR packages — installation FAILED: ${MISSING_AUR[*]}")
            fi
        else
            echo -e "${YELLOW}⚠ yay not available — skipping AUR packages.${NC}"
            SUMMARY_SKIPPED+=("REQUIRED AUR packages skipped (no yay): ${MISSING_AUR[*]}")
        fi
    else
        SUMMARY_SKIPPED+=("REQUIRED AUR packages skipped by request: ${MISSING_AUR[*]}")
    fi
fi
fi

echo ""
# ─── 5b. ADDITIONAL PACKAGES ──────────────────────────────────────────────────

if [[ "$PLATFORM" == nixos ]]; then
    echo -e "  Additional packages: add the ones you want from packages/additional-packages-*.txt"
    echo -e "  to your NixOS configuration (archenemy installs nothing on NixOS)."
elif [[ "$SKIP_PACKAGES" -eq 1 ]]; then
    echo -e "  Additional packages: skipped (--skip-packages)."
elif [[ "$PLATFORM" == fedora ]]; then
    read -rp "Would you like to install additional useful packages? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        mapfile -t ADD_IDS < <(list_ids "$ARCHENEMY_DIR/packages/additional-packages-pacman.txt" \
                                        "$ARCHENEMY_DIR/packages/additional-packages-aur.txt")
        echo ""
        echo -e "  ${CYAN}Additional programs:${NC}"
        for i in "${!ADD_IDS[@]}"; do printf "    %2d) %s\n" "$((i+1))" "${ADD_IDS[$i]}"; done
        echo ""
        read -rp "  Pick numbers (e.g. 1 3 7), Enter to skip: " -a picks
        sel_ids=()
        for n in "${picks[@]}"; do
            [[ "$n" =~ ^[0-9]+$ ]] || continue
            idx=$((10#$n - 1))
            (( idx >= 0 && idx < ${#ADD_IDS[@]} )) || continue
            sel_ids+=("${ADD_IDS[$idx]}")
        done
        # Pakiety spoza repo Fedory (RPM Fusion, producenci) dostają podpowiedź.
        [[ ${#sel_ids[@]} -gt 0 ]] && platform_install "Additional package" "${sel_ids[@]}"
    fi
else
read -rp "Would you like to install additional useful packages? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    ADD_PACMAN="$ARCHENEMY_DIR/packages/additional-packages-pacman.txt"
    ADD_AUR="$ARCHENEMY_DIR/packages/additional-packages-aur.txt"

    # Zbuduj listę dostępnych opcjonalnych programów (nazwa + źródło).
    ADD_NAMES=()
    ADD_SRC=()
    for pair in "pacman:$ADD_PACMAN" "aur:$ADD_AUR"; do
        src="${pair%%:*}"
        file="${pair#*:}"
        [[ -f "$file" ]] || continue
        while IFS= read -r pkg || [[ -n "$pkg" ]]; do
            pkg="${pkg%%[[:space:]]*}"
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            ADD_NAMES+=("$pkg")
            ADD_SRC+=("$src")
        done < "$file"
    done

    if [[ ${#ADD_NAMES[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}⚠ No entries in packages/additional-packages-*.txt${NC}"
    else
        echo ""
        echo -e "  ${CYAN}Additional programs:${NC}"
        for i in "${!ADD_NAMES[@]}"; do
            if [[ "${ADD_SRC[$i]}" == "aur" ]]; then
                printf "    %2d) %s ${YELLOW}(AUR)${NC}\n" "$((i+1))" "${ADD_NAMES[$i]}"
            else
                printf "    %2d) %s\n" "$((i+1))" "${ADD_NAMES[$i]}"
            fi
        done
        echo ""
        read -rp "  Pick numbers (e.g. 1 3 7), Enter to skip: " -a picks

        sel_pacman=()
        sel_aur=()
        for n in "${picks[@]}"; do
            [[ "$n" =~ ^[0-9]+$ ]] || continue
            idx=$((10#$n - 1))   # 10#: „08” nie jest liczbą ósemkową (Z12)
            (( idx >= 0 && idx < ${#ADD_NAMES[@]} )) || continue
            if [[ "${ADD_SRC[$idx]}" == "aur" ]]; then
                sel_aur+=("${ADD_NAMES[$idx]}")
            else
                sel_pacman+=("${ADD_NAMES[$idx]}")
            fi
        done

        # steam i pakiety lib32-* wymagają repo [multilib] — ostrzeż, zanim
        # pacman się wysypie. Włączanie multilib robi instalator GPU.
        NEEDS_MULTILIB=0
        for p in "${sel_pacman[@]}"; do
            case "$p" in steam|lib32-*) NEEDS_MULTILIB=1 ;; esac
        done
        if [[ "$NEEDS_MULTILIB" -eq 1 ]] && ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
            echo -e "  ${YELLOW}⚠ Selected packages require [multilib], which is disabled —${NC}"
            echo -e "  ${YELLOW}  installation will fail. Enable it with the GPU installer${NC}"
            echo -e "  ${YELLOW}  (install/gpudrivers-installation.sh) or manually in /etc/pacman.conf.${NC}"
        fi

        # Wynik sprawdzany (audyt 2026-11-05, Z3): jedna nieznana nazwa albo
        # brak [multilib] anuluje CAŁĄ transakcję pacmana, a podsumowanie
        # dotąd milczało. Przy porażce wypisujemy to, czego pacman -Qi nie
        # widzi (wcześniej zainstalowane pakiety nie są porażką).
        if [[ ${#sel_pacman[@]} -gt 0 ]]; then
            if ! sudo pacman -S --needed "${sel_pacman[@]}"; then
                add_missing=()
                for p in "${sel_pacman[@]}"; do
                    pacman -Qi "$p" &>/dev/null || add_missing+=("$p")
                done
                [[ ${#add_missing[@]} -gt 0 ]] || add_missing=("${sel_pacman[@]}")
                echo -e "  ${RED}✗ pacman failed — not installed: ${add_missing[*]}${NC}"
                echo -e "  ${RED}  One unknown name cancels the whole transaction; check the pacman output above.${NC}"
                SUMMARY_SKIPPED+=("Additional pacman packages — installation FAILED: ${add_missing[*]} (retry: sudo pacman -S --needed ${add_missing[*]})")
            fi
        fi
        if [[ ${#sel_aur[@]} -gt 0 ]]; then
            if command -v yay &>/dev/null; then
                if ! aur_install "${sel_aur[@]}"; then
                    echo -e "  ${RED}✗ yay failed to install: ${sel_aur[*]}${NC}"
                    SUMMARY_SKIPPED+=("Additional AUR packages — installation FAILED: ${sel_aur[*]} (retry: yay -S --needed ${sel_aur[*]})")
                fi
            else
                echo -e "  ${YELLOW}⚠ yay unavailable — skipping AUR packages: ${sel_aur[*]}${NC}"
                SUMMARY_SKIPPED+=("Additional AUR packages skipped (no yay): ${sel_aur[*]}")
            fi
        fi
    fi
fi
fi

echo ""

# ─── 6. DEVICE DETECTION ──────────────────────────────────────────────────────

echo -e "${CYAN}[6] Device selection...${NC}"

# Autodetekcja po DMI: producent sprzętu ustawia tylko DEFAULT menu —
# wybór nadal należy do użytkownika (enter = zatwierdzenie podpowiedzi).
DMI_VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
HW_DEFAULT=3
if [[ "${DMI_VENDOR,,}" == *asus* ]]; then
    HW_DEFAULT=1
    echo -e "  ${GREEN}ASUS hardware detected${NC} ($DMI_VENDOR)."
elif [[ -n "$DMI_VENDOR" ]]; then
    echo "  Detected manufacturer: $DMI_VENDOR"
fi
echo "  1) ASUS ROG notebook"
echo "  2) HP Omen"
echo "  3) Other"
echo ""
read -rp "  Select your device [default: $HW_DEFAULT]: " hw_choice
hw_choice="${hw_choice:-$HW_DEFAULT}"

# Installs + enables power-profiles-daemon. Używa go uniwersalny przełącznik profili,
# a na ASUS-ach pracuje razem z asusctl (poradnik asus-linux: „designed to work
# primarily with power-profiles-daemon”) i jest też drogą zapasową, gdy asusd nie żyje.
setup_universal_ppd() {
    # Poza Archem usług nie zmieniamy (D7): sam odczyt stanu i instrukcja;
    # samokontrola niżej i tak odczyta profil.
    local ppd
    if [[ "$PLATFORM" != arch ]]; then
        svc_check power-profiles-daemon; ppd=$?
        if [[ $ppd -eq 0 ]]; then
            echo -e "  ${GREEN}✓ power-profiles-daemon enabled and running.${NC}"
        elif [[ $ppd -eq 1 ]]; then
            svc_dead "power-profiles-daemon" "systemctl status power-profiles-daemon"
        elif [[ "$PLATFORM" == nixos ]]; then
            manual_step "power-profiles-daemon" "services.power-profiles-daemon.enable = true;" summary
        elif rpm -q tuned-ppd >/dev/null 2>&1; then
            # Fedora Workstation: tuned-ppd (domyślny menedżer profili, to samo
            # API D-Bus) wyklucza się z power-profiles-daemon — drugiego menedżera
            # nie każemy instalować ani włączać. powerprofilesctl (przełącznik na
            # pasku) jest tylko w pakiecie power-profiles-daemon, stąd jedyna
            # porada: podmiana zamiast instalacji (packages.fedoraproject.org,
            # pliki tuned-ppd 2.28 i power-profiles-daemon 0.30, F44).
            if svc_check tuned-ppd; then
                echo -e "  ${YELLOW}⚠ Power profiles: tuned-ppd (Fedora's default) is running — archenemy does not install a second profile manager.${NC}"
            else
                echo -e "  ${YELLOW}⚠ Power profiles: tuned-ppd (Fedora's default) is installed, but not enabled and running — check: systemctl status tuned-ppd${NC}"
            fi
            echo -e "    The bar's profile switcher needs powerprofilesctl, which only power-profiles-daemon has. Optional, replaces tuned-ppd:"
            echo -e "    sudo dnf swap tuned-ppd power-profiles-daemon && sudo systemctl enable --now power-profiles-daemon"
            SUMMARY_SKIPPED+=("Power profiles: tuned-ppd kept (no powerprofilesctl for the bar) — optional: sudo dnf swap tuned-ppd power-profiles-daemon && sudo systemctl enable --now power-profiles-daemon")
        elif pkg_installed power-profiles-daemon >/dev/null 2>&1; then
            manual_step "power-profiles-daemon" "sudo systemctl enable --now power-profiles-daemon" summary
        else
            manual_step "power-profiles-daemon" "$(pkg_hint power-profiles-daemon) && sudo systemctl enable --now power-profiles-daemon" summary
        fi
        return
    fi
    echo -e "  Setting up power-profiles-daemon."
    [[ "$SKIP_PACKAGES" -eq 1 ]] || sudo pacman -S --needed power-profiles-daemon
    sudo systemctl enable --now power-profiles-daemon 2>/dev/null
    # D7: ✓ i cisza dopiero po odczycie enabled + active; kod 0 bez efektu,
    # awaria enable albo martwa usługa = ostrzeżenie i wpis w podsumowaniu.
    svc_check power-profiles-daemon; ppd=$?
    if [[ $ppd -eq 1 ]]; then
        svc_dead "power-profiles-daemon" "systemctl status power-profiles-daemon"
    elif [[ $ppd -eq 2 ]]; then
        echo -e "  ${YELLOW}⚠ power-profiles-daemon is not enabled — check: systemctl status power-profiles-daemon${NC}"
        SUMMARY_SKIPPED+=("power-profiles-daemon — not enabled: sudo systemctl enable --now power-profiles-daemon")
    fi
}

case "$hw_choice" in
    1)
        HW_PROFILE="asus"
        echo -e "  ${GREEN}✓ ASUS ROG selected.${NC}"
        echo ""
        # Kod wyjścia to kontrakt (0 gotowe, 2 potrzebny restart, inaczej porażka),
        # opis w skrypcie. Decyzja właściciela 2026-10-14: pakiety z repo, nie z AUR.
        # Instalator ASUS instaluje pakiety i startuje asusd — tylko Arch bez flagi.
        if [[ "$PLATFORM" != arch ]]; then
            manual_step "ASUS tools (asusctl)" "$(pkg_hint asusctl)" summary
        elif [[ "$SKIP_PACKAGES" -eq 1 ]]; then
            manual_step "ASUS tools (asusctl)" "bash ~/archenemy/install/asus-installation.sh" summary
        else
        bash "$ARCHENEMY_DIR/install/asus-installation.sh"
        case $? in
            0) SUMMARY_DONE+=("ASUS: asusctl + rog-control-center from the Arch repo, asusd running") ;;
            2) SUMMARY_SKIPPED+=("ASUS: packages installed, asusd not running yet: reboot") ;;
            *) SUMMARY_SKIPPED+=("ASUS: installation failed, profiles via power-profiles-daemon (retry: bash ~/archenemy/install/asus-installation.sh)") ;;
        esac
        fi
        setup_universal_ppd
        ;;
    2)
        HW_PROFILE="universal"
        echo -e "  ${GREEN}✓ HP Omen selected.${NC}"
        echo ""
        setup_universal_ppd
        ;;
    *)
        HW_PROFILE="universal"
        echo -e "  ${GREEN}✓ Other device selected.${NC}"
        echo ""
        setup_universal_ppd
        ;;
esac

# Save hardware profile — waybar's profileswitcher module reads this at runtime
# (scripts/waybar/profile-get.sh + profile-switch.sh), so no per-rice config
# rewriting is needed and the same repo works on any machine.
echo "$HW_PROFILE" > "$DATA_DIR/hardware.dat"

# Samokontrola: dokładnie to, co pokaże moduł waybara. "brak" = żadne
# narzędzie profili nie odpowiada — mówimy o tym głośno już teraz,
# zamiast zostawiać cichy sukces i pusty/zepsuty moduł na pasku.
PROFILE_CHECK="$(bash "$ARCHENEMY_DIR/scripts/waybar/profile-get.sh" 2>/dev/null)"
if [[ -z "$PROFILE_CHECK" || "$PROFILE_CHECK" == "brak" ]]; then
    echo -e "  ${RED}✗ Profile switcher is not working (profile-get.sh → \"brak\").${NC}"
    # Porada per platforma (P2 z przeglądu D5): asus-installation.sh woła
    # `sudo pacman -S`, więc poza Archem — instrukcje z manual_step kroku [6].
    case "$PLATFORM" in
        fedora) echo -e "    ASUS: $(pkg_hint asusctl). Other devices: sudo systemctl enable --now power-profiles-daemon"
                echo -e "    (if tuned-ppd is installed, first: sudo dnf swap tuned-ppd power-profiles-daemon)." ;;
        nixos)  echo -e "    Set in configuration.nix, then nixos-rebuild switch — ASUS: services.asusd.enable = true;"
                echo -e "    and services.power-profiles-daemon.enable = true;. Other devices: services.power-profiles-daemon.enable = true;" ;;
        *)      echo -e "    ASUS: bash ~/archenemy/install/asus-installation.sh. Other devices: systemctl enable --now power-profiles-daemon." ;;
    esac
    SUMMARY_SKIPPED+=("Hardware profile: $HW_PROFILE — profile tool is NOT responding, the bar will show \"brak\"")
else
    SUMMARY_DONE+=("Hardware profile: $HW_PROFILE (active profile: $PROFILE_CHECK)")
fi

echo ""

# ─── 6.5 DRIVERS + KERNEL (optional) ─────────────────────────────────────────

echo -e "${CYAN}[6.5] Optional drivers & kernel...${NC}"

# Kod wyjścia każdego instalatora trafia do podsumowania (audyt 2026-11-05,
# Z8: dotąd nieczytany, a baner ogłaszał pełny sukces). Kontrakt: 0 = gotowe
# albo pominięte z wyboru, 2 = zainstalowane, ale wpisy bootowania trzeba
# poprawić ręcznie (regenerate_bootloader: systemd-boot/nieznany), inny = porażka.
run_driver_installer() {   # run_driver_installer <etykieta> <skrypt w install/>
    local rc
    bash "$ARCHENEMY_DIR/install/$2"; rc=$?
    case "$rc" in
        0) ;;
        2) SUMMARY_SKIPPED+=("$1 — installed, but the boot entries need the manual steps printed above") ;;
        *) SUMMARY_SKIPPED+=("$1 — installation FAILED (details above; retry: bash ~/archenemy/install/$2)") ;;
    esac
}

# Instalatory sterowników i jądra (pacman, mkinitcpio, GRUB) — tylko Arch bez flagi.
case "$PLATFORM:$SKIP_PACKAGES" in
    fedora:*) manual_step "CPU microcode, GPU drivers, kernel" "use Fedora's tools (NVIDIA: RPM Fusion), see README" ;;
    nixos:*)  manual_step "CPU microcode, GPU drivers, kernel" "set them in your NixOS configuration (hardware.*, boot.kernelPackages)" ;;
    *:1)      manual_step "CPU microcode, GPU drivers, kernel" "bash ~/archenemy/install/{cpudrivers-installation,gpudrivers-installation,kernel-install}.sh" ;;
    *)
read -rp "  Run CPU microcode installer? [y/N]: " ans
[[ "$ans" =~ ^[Yy]$ ]] && run_driver_installer "CPU microcode" cpudrivers-installation.sh

read -rp "  Run GPU drivers installer? [y/N]: " ans
[[ "$ans" =~ ^[Yy]$ ]] && run_driver_installer "GPU drivers" gpudrivers-installation.sh

read -rp "  Run kernel installer? [y/N]: " ans
[[ "$ans" =~ ^[Yy]$ ]] && run_driver_installer "Kernel" kernel-install.sh
        ;;
esac

echo ""

# ─── 7. BACKUP ────────────────────────────────────────────────────────────────

echo -e "${CYAN}[7] Backup...${NC}"

# Rice, który krok [9] REALNIE podlinkuje — liczony tutaj, bo kopia zapasowa
# musi obejmować foldery TEGO rice'a (audyt 2026-09-25: [7] iterował
# DEFAULT_RICE, a [9] linkował TARGET_RICE — folder obecny tylko w aktywnym
# ricie, np. mako, szedł do .bak bez kopii w backups/).
# Ponowny bieg instalatora respektuje aktywny rice: jeśli .current_rice
# wskazuje istniejący rice, symlinkujemy TEN rice — dotąd każdy bieg cicho
# przywracał DEFAULT_RICE (white-blue) i nadpisywał wybór użytkownika.
TARGET_RICE="$DEFAULT_RICE"
if [[ -f "$CURRENT_RICE" ]]; then
    _cur_rice="$(<"$CURRENT_RICE")"
    if [[ -n "$_cur_rice" && -d "$RICES_DIR/$_cur_rice" ]]; then
        TARGET_RICE="$_cur_rice"
    fi
fi

echo -e "Everything is about to be set up. Would you like to create a backup of your current ~/.config?"
read -rp "[y/N]: " ans

if [[ "$ans" =~ ^[Yy]$ ]]; then
    BACKUP_NAME="backup-$(date +%Y%m%d_%H%M%S)"
    BACKUP_DIR="$ARCHENEMY_DIR/backups/$BACKUP_NAME"
    mkdir -p "$BACKUP_DIR"

    for src in "$RICES_DIR/$TARGET_RICE"/*/; do
        [[ -d "$src" ]] || continue
        name=$(basename "$src")
        dest="$CONFIG_DIR/$name"
        if [[ -e "$dest" && ! -L "$dest" ]]; then
            cp -r "$dest" "$BACKUP_DIR/$name"
            echo -e "  ${GREEN}✓ backed up ~/.config/$name${NC}"
        fi
    done
    echo -e "  ${BLUE}Backup saved in backups/$BACKUP_NAME.${NC}"
fi

echo ""

# ─── 8. GENERATE MACHINE-LOCAL CONFIGS ───────────────────────────────────────
# Pliki per-maszyna (w .gitignore) — hyprland.lua je require'uje, więc każdy
# musi istnieć, nawet pusty, żeby Hyprland nie zgłaszał błędów konfiguracji.

echo -e "${CYAN}[8] Generating machine-local configs...${NC}"
HYPR_LOCAL_DIR="$ARCHENEMY_DIR/config/hypr"
mkdir -p "$HYPR_LOCAL_DIR"

# 8a. Monitory (rozdzielczość/pozycja/skala) — emisja Lua (hl.monitor) z
# data/monitors/*.dat. Generator wydzielony do biblioteki (jedno źródło prawdy
# ze zmianą na żywo, Super+A → [n]).
declare -A MON_SELECTOR
for mon in "${MONITOR_NAMES[@]}"; do
    MON_SELECTOR[$mon]=$(monitor_selector_from_dat "$DATA_DIR/monitors/$mon.dat")
done
source "$ARCHENEMY_DIR/scripts/hypr/lib/gen-monitors.sh"
generate_monitors_conf "$MONITOR_CONF" "$DATA_DIR/monitors"
echo -e "  ${GREEN}✓ monitorshyprl.lua${NC}"

# 8b. Workspace'y wg trybu (shared/decades — data/workspace-mode.dat z [3.7])
# i numeracji monitorów L→P (ORDER z [3.6]).
# Generator wydzielony do biblioteki (jedno źródło prawdy; używa jej też
# scripts/hypr/workspace-mode-switch.sh). Definiuje is_internal_panel()
# i generate_workspaces_monitors().
source "$ARCHENEMY_DIR/scripts/hypr/lib/gen-workspaces.sh"

# Monitory w kolejności ORDER (L→P) — wejście dla generatora: wpis
# "<nazwa złącza><TAB><selektor>" (nazwa decyduje o panelu wbudowanym,
# selektor desc: trafia do reguł — patrz lib/monitor-id.sh).
ORDERED_LR=()
while IFS=$'\t' read -r _ mon; do
    [[ -n "$mon" ]] && ORDERED_LR+=("$mon"$'\t'"${MON_SELECTOR[$mon]}")
done < <(for mon in "${MONITOR_NAMES[@]}"; do
    printf '%s\t%s\n' "${MON_ORDER[$mon]}" "$mon"
done | sort -n -s -k1,1)

generate_workspaces_monitors "$HYPR_LOCAL_DIR/workspaces-monitors.lua" "$WS_MODE" "${ORDERED_LR[@]}"
echo -e "  ${GREEN}✓ workspaces-monitors.lua (mode: $WS_MODE, ${#ORDERED_LR[@]} monitors)${NC}"

# 8c. Bindy sprzętowe (klawisze ASUS ROG tylko na ASUS-ach) — emisja Lua
{
    echo "-- generated by archenemy install.sh"
    if [[ "$HW_PROFILE" == "asus" ]]; then
        echo "-- ASUS ROG top-row keys"
        echo "hl.bind(\"XF86Launch1\", hl.dsp.exec_cmd(\"rog-control-center\"))"
        # Klawisz profilu idzie DOKŁADNIE tą samą drogą co klik w module waybara:
        # profile-switch.sh weryfikuje efekt w sysfs, przy martwym asusd spada na
        # power-profiles-daemon, a przy totalnej awarii wysyła krytyczne
        # powiadomienie z prawdziwym błędem. Surowe `asusctl` (tak było do
        # 2026-09-07) potrafi wyjść zerem NIC nie zmieniając — pęknięcie
        # asusctl↔asusd, decyzja 2026-07-15 — a `pkill` w tej samej linii odświeżał
        # pasek również po nieudanej zmianie, więc klawisz wyglądał na martwy i nie
        # dawał żadnej informacji. Odświeżenie paska (RTMIN+8) robią teraz skrypty
        # profili, wyłącznie po POTWIERDZONEJ zmianie.
        echo "hl.bind(\"XF86Launch4\", hl.dsp.exec_cmd(\"~/archenemy/scripts/waybar/profile-switch.sh\"))"
    else
        echo "-- No hardware binds for this profile ($HW_PROFILE)"
    fi
} > "$HYPR_LOCAL_DIR/hardware-keys.lua"
echo -e "  ${GREEN}✓ hardware-keys.lua ($HW_PROFILE)${NC}"

# 8d. Zmienne środowiskowe GPU (wg wykrytej karty)
GPU_KIND="unknown"
if command -v lspci &>/dev/null; then
    # Klasa PCI 03xx (VGA/3D/display), jak w gpudrivers-installation.sh — grep
    # 'vga|3d|display' po całym wierszu łapał adres PCI 3d:00.0 (audyt Z14).
    GPU_INFO=$(lspci -d ::03xx 2>/dev/null)
    grep -qi 'nvidia' <<<"$GPU_INFO" && GPU_KIND="nvidia"
    [[ "$GPU_KIND" == "unknown" ]] && grep -qi 'amd\|radeon' <<<"$GPU_INFO" && GPU_KIND="amd"
    [[ "$GPU_KIND" == "unknown" ]] && grep -qi 'intel' <<<"$GPU_INFO" && GPU_KIND="intel"
fi
{
    echo "-- generated by archenemy install.sh — GPU: $GPU_KIND"
    if [[ "$GPU_KIND" == "nvidia" ]]; then
        echo "hl.env(\"LIBVA_DRIVER_NAME\", \"nvidia\")"
        echo "hl.env(\"__GLX_VENDOR_LIBRARY_NAME\", \"nvidia\")"
        echo "hl.env(\"GBM_BACKEND\", \"nvidia-drm\")"
        echo "hl.env(\"NVD_BACKEND\", \"direct\")"
        echo "hl.env(\"__GL_GSYNC_ALLOWED\", \"1\")"
        echo "hl.env(\"__GL_VRR_ALLOWED\", \"1\")"
    else
        echo "-- GPU $GPU_KIND needs no additional variables"
    fi
} > "$HYPR_LOCAL_DIR/gpu-env.lua"
echo -e "  ${GREEN}✓ gpu-env.lua ($GPU_KIND)${NC}"

# 8e. Autostart osobisty (nie nadpisuj, jeśli użytkownik już ma swój)
AUTOSTART_CONF="$HYPR_LOCAL_DIR/autostartpersonalisation.lua"
if [[ ! -f "$AUTOSTART_CONF" ]]; then
    {
        echo "-- generated by archenemy install.sh"
        echo "-- Personal autostart for this machine — add your apps"
        echo "-- (hl.exec_cmd inside hl.on(\"hyprland.start\", ...) replaces exec-once)."
        if [[ "$HW_PROFILE" == "asus" ]]; then
            echo "hl.on(\"hyprland.start\", function()"
            echo "    hl.exec_cmd(\"rog-control-center\")"
            echo "    -- hl.exec_cmd(\"megasync\")"
            echo "end)"
        else
            echo "-- hl.on(\"hyprland.start\", function()"
            echo "--     hl.exec_cmd(\"megasync\")"
            echo "-- end)"
        fi
    } > "$AUTOSTART_CONF"
    echo -e "  ${GREEN}✓ autostartpersonalisation.lua (new)${NC}"
else
    echo -e "  ${YELLOW}⚠ autostartpersonalisation.lua already exists, left as it is.${NC}"
fi

# 8f. Bindy aplikacji użytkownika (edycja przez Super+A — nie nadpisuj)
# local mainMod jest tu konieczny: require() = osobny scope Lua, plik nie
# widzi zmiennych z hyprland.lua rice'a.
APPBINDS_CONF="$HYPR_LOCAL_DIR/appbinds.lua"
if [[ ! -f "$APPBINDS_CONF" ]]; then
    {
        echo "-- generated by archenemy install.sh"
        echo "-- Your app shortcuts — edit via Super+A (scripts/appbinds/appbinds.sh)."
        echo "local mainMod = \"SUPER\""
    } > "$APPBINDS_CONF"
    echo -e "  ${GREEN}✓ appbinds.lua (new)${NC}"
else
    echo -e "  ${YELLOW}⚠ appbinds.lua already exists, left as it is.${NC}"
fi

# 8g. hyprpaper.conf (warstwa maszynowa — rice'y wskazują na niego symlinkiem;
# bez pliku symlink byłby zepsuty i hyprpaper nie wystartuje; nie nadpisuj,
# bo trzyma aktualny wybór tapet — wypełnia go rofi_wallpaper_switcher.sh)
HYPRPAPER_MACHINE_CONF="$HYPR_LOCAL_DIR/hyprpaper.conf"
if [[ ! -f "$HYPRPAPER_MACHINE_CONF" ]]; then
    {
        echo "# generated by archenemy - do not edit by hand"
        echo "# Set the wallpaper via Super+W (rofi_wallpaper_switcher.sh)."
        # Wyłącz splash hyprpapera (cytat/wersja Hyprlanda rysowana na tapecie).
        echo "splash = false"
    } > "$HYPRPAPER_MACHINE_CONF"
    echo -e "  ${GREEN}✓ hyprpaper.conf (new)${NC}"
else
    echo -e "  ${YELLOW}⚠ hyprpaper.conf already exists, left as it is.${NC}"
fi

# 8h. hyprlock-background-<rice>.conf (warstwa maszynowa — rice'y wskazują na
# te pliki przez `source =`; bez nich hyprlock nie wystartuje; nie nadpisuj,
# bo trzyma aktualny wybór właściciela — wypełnia go rofi_wallpaper_switcher.sh
# przez checkbox "Set as hyprlock background")
generate_hyprlock_background() {
    local out="$1" brightness="$2"
    [[ -f "$out" ]] && { echo -e "  ${YELLOW}⚠ $(basename "$out") already exists, left as it is.${NC}"; return; }
    {
        echo "# generated by archenemy install.sh - do not edit by hand"
        echo "# Lock screen background. Default: live screenshot + blur."
        echo "# Change via Super+W -> [ ] Set as hyprlock background (no blur)."
        echo "background {"
        echo "    monitor ="
        echo "    path       = screenshot"
        echo "    blur_size  = 7"
        echo "    blur_passes = 3"
        echo "    noise      = 0.012"
        echo "    contrast   = 1.05"
        echo "    brightness = $brightness"
        echo "    vibrancy   = 0.18"
        echo "}"
    } > "$out"
    echo -e "  ${GREEN}✓ $(basename "$out") (new)${NC}"
}
generate_hyprlock_background "$HYPR_LOCAL_DIR/hyprlock-background-white-blue.conf" "0.85"
# tron: ciemniej niż white-blue — blokada ma wyglądać jak zgaszony Grid.
generate_hyprlock_background "$HYPR_LOCAL_DIR/hyprlock-background-tron.conf" "0.55"
generate_hyprlock_background "$HYPR_LOCAL_DIR/hyprlock-background-asia-n-rice.conf" "0.85"
# dither-flux: przygaszone jak fiord w ulewie, ale raster tapety ma zostać czytelny.
generate_hyprlock_background "$HYPR_LOCAL_DIR/hyprlock-background-dither-flux.conf" "0.70"
# crt: zgaszony kineskop — ciemno jak w tronie, nad tym świecący zegar.
generate_hyprlock_background "$HYPR_LOCAL_DIR/hyprlock-background-crt.conf" "0.60"
# yin: przygaszony, rozmyty pulpit pod taflą matowego szkła z zegarem.
generate_hyprlock_background "$HYPR_LOCAL_DIR/hyprlock-background-yin.conf" "0.60"
# yang: odwrotność yin — jasny pulpit bez przygaszania (ciemny tekst na jasnej
# tafli; przyciemnione tło tylko odbierałoby mu kontrastu).
generate_hyprlock_background "$HYPR_LOCAL_DIR/hyprlock-background-yang.conf" "1.00"

# 8i. Styl paska głośności waybara (przełączalny w Super+A → [v]) — seed
# domyślny. volume-bar.sh ma fallback "line", ale seed daje wykrywalność
# i spójność z workspace-mode.dat. Istniejącego pliku NIE nadpisujemy — stare
# nazwy stylów volume-bar.sh sam interpretuje jako "line".
VOLSTYLE_DAT="$DATA_DIR/volume-bar-style.dat"
if [[ ! -f "$VOLSTYLE_DAT" ]]; then
    mkdir -p "$DATA_DIR"
    echo "line" > "$VOLSTYLE_DAT"
    echo -e "  ${GREEN}✓ volume-bar-style.dat (line)${NC}"
else
    echo -e "  ${YELLOW}⚠ volume-bar-style.dat already exists, left as it is.${NC}"
fi

# 8j. Autostart aplikacji wybranych w TUI (Super+A → [p]) — warstwa RÓWNOLEGŁA
# do autostartpersonalisation.lua (tamten zostaje w pełni ręczny). Generujemy
# zawsze, także jako pusty stub: rice'y require'ują ten plik, więc musi istnieć
# po świeżej instalacji i po ponownym biegu instalatora (git pull).
# Generator wydzielony do biblioteki (jedno źródło prawdy z pickerem TUI).
source "$ARCHENEMY_DIR/scripts/hypr/lib/gen-autostart.sh"
generate_autostart_apps "$DATA_DIR/autostart-apps.dat" "$HYPR_LOCAL_DIR/autostart-apps.lua"
echo -e "  ${GREEN}✓ autostart-apps.lua${NC}"

# 8k. Timer waybara (moduł custom/timer; ustawienia w Super+A → [t]) — seed
# domyślnych. Timer jest OPCJONALNY, dlatego enabled=0: świeża instalacja ma
# pasek jak dotąd, dopóki właściciel go nie włączy. Skrypty timera mają własne
# fallbacki, ale seed daje wykrywalność (pliki widać w data/) i spójność
# z volume-bar-style.dat. Istniejących plików NIE nadpisujemy. Stanu biegu
# (timer-state.dat) nie seedujemy — tworzy go pierwsze kliknięcie w pasek.
seed_dat() {
    local file="$1" value="$2"
    if [[ ! -f "$file" ]]; then
        mkdir -p "$DATA_DIR"
        echo "$value" > "$file"
        echo -e "  ${GREEN}✓ $(basename "$file") ($value)${NC}"
    else
        echo -e "  ${YELLOW}⚠ $(basename "$file") already exists, left as it is.${NC}"
    fi
}
seed_dat "$DATA_DIR/timer-enabled.dat"  "0"
seed_dat "$DATA_DIR/timer-duration.dat" "25"
seed_dat "$DATA_DIR/timer-color.dat"    "#ff0000"

# 8l. Music stack (OPCJONALNY — rekomendacja, nie wymóg; właściciel 2026-09-20).
# Pakiety mpd/mpc/ncmpcpp/mpv siedzą w additional-packages — ten krok robi
# cokolwiek TYLKO gdy binarka jest zainstalowana, i NIGDY nie nadpisuje
# istniejącej konfiguracji użytkownika:
#   - config/mpd/output.conf (warstwa maszynowa: wyjście audio, domyślnie
#     pipewire; przepisuje je Super+A → [o] → 3) i local.conf (osobista) — stub
#     tylko gdy pliku nie ma;
#   - ~/.config/mpd → symlink do config/mpd, ale istniejący PRAWDZIWY katalog
#     albo cudzy (także wiszący) link (albo ~/.mpdconf, ~/.mpd) zostaje
#     nietknięty bez jawnego „y" — cudzy mpd.conf może wskazywać bibliotekę
#     na NAS-ie i bazę budowaną godzinami;
#   - usługa użytkownika włączana wyłącznie po pytaniu [y/N]; gdy mpd działa
#     jako usługa SYSTEMOWA — tylko informacja (dwa mpd = konflikt portu/karty);
#     włączony przez użytkownika mpd.socket = ostrzeżenie (port 6600 w sieci);
#   - ~/.local/share/applications/ncmpcpp.desktop (wpis dla rofi drun i dla
#     [p] autostart) kopiowany tylko gdy go nie ma.
# Drugi bieg instalatora jest no-op (same „istnieje — nie ruszam").
MPD_CONF_DIR="$ARCHENEMY_DIR/config/mpd"
if command -v mpd >/dev/null 2>&1; then
    echo -e "  ${CYAN}Music stack: mpd${NC}"
    mkdir -p "$HOME/.local/state/mpd/playlists"

    if [[ ! -f "$MPD_CONF_DIR/output.conf" ]]; then
        {
            echo "# generated by archenemy install.sh — mpd audio output (machine layer)."
            echo "# Switch via Super+A → [o] → 3 (pipewire recommended; alsa = exclusive mode)."
            echo "audio_output {"
            echo "    type  \"pipewire\""
            echo "    name  \"PipeWire\""
            echo "}"
        } > "$MPD_CONF_DIR/output.conf"
        echo -e "  ${GREEN}✓ config/mpd/output.conf (pipewire)${NC}"
    else
        echo -e "  ${YELLOW}⚠ config/mpd/output.conf already exists, left as it is.${NC}"
    fi
    seed_dat "$DATA_DIR/mpd-output.dat" "pipewire"

    if [[ ! -f "$MPD_CONF_DIR/local.conf" ]]; then
        {
            echo "# archenemy — Your mpd overrides (personal layer, outside git)."
            echo "# Example, another library:  music_directory \"/mnt/music\""
            echo "# This file is loaded at the end of mpd.conf (include_optional)."
        } > "$MPD_CONF_DIR/local.conf"
        echo -e "  ${GREEN}✓ config/mpd/local.conf (empty stub)${NC}"
    else
        echo -e "  ${YELLOW}⚠ config/mpd/local.conf already exists, left as it is.${NC}"
    fi

    MPD_USER_DIR="$CONFIG_DIR/mpd"
    # ✓ dopiero po odczycie linku (audyt 2026-11-05, Z11): wiszący symlink
    # ~/.config/mpd umykał testowi -e, `ln -s` padał na istniejącej nazwie,
    # a ✓ i SUMMARY_DONE i tak leciały — mpd czytał nie ten config. Wiszący
    # link to też cudzy ~/.config/mpd, więc bez „y” go nie podmieniamy.
    # `ln -T`: na prawdziwym katalogu, którego mv nie przeniósł, ln nie
    # utworzy linku W ŚRODKU niego.
    mpd_link_ok() {
        [[ -L "$MPD_USER_DIR" && "$(readlink -f "$MPD_USER_DIR")" == "$(readlink -f "$MPD_CONF_DIR")" ]]
    }
    mpd_link_failed() {
        echo -e "  ${RED}✗ ~/.config/mpd is not linked to config/mpd — mpd will not read archenemy's config.${NC}"
        SUMMARY_SKIPPED+=("mpd config NOT linked: ln -sT $MPD_CONF_DIR $MPD_USER_DIR (move ~/.config/mpd away first if it exists)")
    }
    # D10: ~/.config/mpd (albo plik w nim) z home-managera → bez pytania
    # o podmianę: przeniesienie do .bak i tak cofnąłby następny switch HM.
    MPD_HM=""
    if [[ -f "$ARCHENEMY_DIR/scripts/lib/hm-conflict.sh" ]]; then
        # shellcheck source=../scripts/lib/hm-conflict.sh
        source "$ARCHENEMY_DIR/scripts/lib/hm-conflict.sh"
        MPD_HM="$(hm_conflicts "$MPD_USER_DIR" | head -n1)"
    fi
    if mpd_link_ok; then
        echo -e "  ${GREEN}✓ ~/.config/mpd → config/mpd (already linked)${NC}"
    elif [[ -n "$MPD_HM" ]]; then
        echo -e "  ${YELLOW}⚠ ${MPD_HM/#$HOME/\~} is managed by home-manager (link into /nix/store), left as it is.${NC}"
        echo -e "    To use archenemy's mpd config, remove it from your home-manager configuration and run install.sh again."
        SUMMARY_SKIPPED+=("mpd config NOT linked: home-manager manages ${MPD_HM/#$HOME/\~} — remove it from your home-manager configuration, then run install.sh again")
    elif [[ -e "$MPD_USER_DIR" || -L "$MPD_USER_DIR" || -e "$HOME/.mpdconf" || -d "$HOME/.mpd" ]]; then
        echo -e "  ${YELLOW}⚠ You already have an mpd config (~/.config/mpd, ~/.mpdconf or ~/.mpd).${NC}"
        [[ -L "$MPD_USER_DIR" && ! -e "$MPD_USER_DIR" ]] \
            && echo -e "    ~/.config/mpd is a broken link (→ $(readlink "$MPD_USER_DIR"))."
        echo -e "    archenemy does NOT replace it automatically. You can replace it now (the old directory"
        echo -e "    will be kept as ~/.config/mpd.bak-<timestamp>) or manually later."
        read -rp "  Replace ~/.config/mpd with archenemy's config now (backup kept)? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            [[ -e "$MPD_USER_DIR" || -L "$MPD_USER_DIR" ]] && mv "$MPD_USER_DIR" "$MPD_USER_DIR.bak-$(date +%Y%m%d_%H%M%S)"
            ln -sT "$MPD_CONF_DIR" "$MPD_USER_DIR"
            if mpd_link_ok; then
                echo -e "  ${GREEN}✓ ~/.config/mpd → config/mpd (previous kept as .bak)${NC}"
                [[ -e "$HOME/.mpdconf" || -d "$HOME/.mpd" ]] && echo -e "  ${YELLOW}⚠ ~/.mpdconf / ~/.mpd are kept — mpd reads ~/.config/mpd/mpd.conf first.${NC}"
                SUMMARY_DONE+=("mpd config linked (previous kept as .bak)")
            else
                mpd_link_failed
            fi
        else
            echo -e "  ${YELLOW}⚠ Keeping your mpd config. The ncmpcpp theme still works;${NC}"
            echo -e "    the ncmpcpp visualizer needs a fifo output in your mpd.conf (see config/mpd/mpd.conf)."
            SUMMARY_SKIPPED+=("mpd: existing user config kept (archenemy's config/mpd not linked)")
        fi
    else
        ln -sT "$MPD_CONF_DIR" "$MPD_USER_DIR"
        if mpd_link_ok; then
            echo -e "  ${GREEN}✓ ~/.config/mpd → config/mpd${NC}"
            SUMMARY_DONE+=("mpd config linked (~/.config/mpd → config/mpd)")
        else
            mpd_link_failed
        fi
    fi

    # >>> 8l: usługa mpd (wycinek dla tests/install-services.sh) >>>
    # Deklaracja usługi użytkownika na NixOS (P3 z przeglądu D5):
    # `systemctl --user enable mpd` zakłada jednostkę z pakietu, a jednostek
    # pakietów NixOS nie ładuje z samego environment.systemPackages (do tego jest
    # systemd.packages; nixpkgs pkgs/by-name/mp/mpd/package.nix ustawia tylko
    # systemd_system_unit_dir w $out) — nie zgadujemy, deklarujemy; services.mpd
    # z home-managera pisze WŁASNY mpd.conf do sklepu (modules/services/mpd.nix:
    # ExecStart … --no-daemon ${mpdConf}). Stąd jawna usługa użytkownika
    # (systemd.user.services, NixOS nixos/modules/system/boot/systemd/user.nix)
    # na config archenemy: mpd bierze plik konfiguracji jako argument pozycyjny
    # (src/CommandLine.cxx).
    MPD_NIX_DECL="declare it in configuration.nix (it reads archenemy's ~/.config/mpd/mpd.conf):
      systemd.user.services.mpd = { description = \"Music Player Daemon (archenemy config)\";
        wantedBy = [ \"default.target\" ]; serviceConfig.ExecStart = \"\${pkgs.mpd}/bin/mpd --no-daemon %h/.config/mpd/mpd.conf\"; };
      then nixos-rebuild switch. Not home-manager services.mpd: it generates its own mpd.conf."
    if systemctl is-enabled --quiet mpd.service 2>/dev/null || systemctl is-active --quiet mpd.service 2>/dev/null; then
        echo -e "  ${YELLOW}⚠ mpd runs as a SYSTEM service — skipping the user service${NC}"
        echo -e "    (two mpd instances conflict over port 6600 and the sound card). Left as it is."
        SUMMARY_SKIPPED+=("mpd user service (system-wide mpd is enabled)")
    elif systemctl --user is-enabled --quiet mpd.socket 2>/dev/null || systemctl --user is-active --quiet mpd.socket 2>/dev/null; then
        # mpd.socket z pakietu ma ListenStream=6600 (wszystkie interfejsy), a mpd
        # aktywowany gniazdem pomija bind_to_address "localhost" z mpd.conf
        # (src/Listen.cxx) — mpd bez hasła słucha w całej sieci, a instalator
        # mówił „already enabled” (audyt 2026-11-05, S13). Wyboru użytkownika
        # nie zmieniamy: mówimy wprost i podajemy komendę.
        if [[ "$PLATFORM" == arch ]]; then
            echo -e "  ${YELLOW}⚠ mpd.socket (user) is enabled: socket activation listens on port 6600 on ALL interfaces${NC}"
            echo -e "    and ignores bind_to_address \"localhost\" from mpd.conf, so mpd (no password) is reachable"
            echo -e "    from your network unless a firewall blocks the port. To keep it local:"
            echo -e "    systemctl --user disable --now mpd.socket && systemctl --user enable --now mpd.service"
            SUMMARY_SKIPPED+=("mpd.socket listens on port 6600 on all interfaces (bind_to_address ignored) — to keep mpd local: systemctl --user disable --now mpd.socket && systemctl --user enable --now mpd.service")
        else
            # D7F R5 (przegląd Codexa D7): poza Archem jednostka nie jest ta
            # z pakietu Archa (home-manager: ListenStream = listenAddress:port,
            # domyślnie 127.0.0.1) — o ekspozycji mówimy dopiero po odczycie
            # Listen; bez odczytu porada warunkowa.
            MPD_LISTEN="$(systemctl --user show -p Listen --value mpd.socket 2>/dev/null)" || MPD_LISTEN=""
            MPD_EXPOSED=unknown; MPD_ADDRS=""
            read -ra MPD_TOKENS <<< "$MPD_LISTEN"
            for t in "${MPD_TOKENS[@]}"; do
                [[ "$t" == \(* ]] && continue
                MPD_ADDRS+="${MPD_ADDRS:+ }$t"
                if [[ "$t" =~ ^(127\.[0-9.]+|\[::1\]|localhost):[0-9]+$ || "$t" == /* || "$t" == @* ]]; then
                    [[ "$MPD_EXPOSED" == yes ]] || MPD_EXPOSED=no
                else
                    MPD_EXPOSED=yes
                fi
            done
            if [[ "$PLATFORM" == nixos ]]; then
                MPD_FIX="remove the socket from your configuration — home-manager: services.mpd.network.startWhenNeeded = false; NixOS: systemd.user.sockets.mpd.enable = false; — then rebuild, and for the user service $MPD_NIX_DECL"
                MPD_FIX_SHORT="remove it from your NixOS/home-manager configuration (services.mpd.network.startWhenNeeded = false; or systemd.user.sockets.mpd.enable = false;) and rebuild"
            else
                MPD_FIX="systemctl --user disable --now mpd.socket && systemctl --user enable --now mpd.service"
                MPD_FIX_SHORT="$MPD_FIX"
            fi
            case "$MPD_EXPOSED" in
                yes)
                    echo -e "  ${YELLOW}⚠ mpd.socket (user) is enabled and listens on ${MPD_ADDRS}: mpd (no password) is reachable from your network${NC}"
                    echo -e "    unless a firewall blocks the port (socket activation ignores bind_to_address \"localhost\"). To keep it local:"
                    echo -e "    $MPD_FIX"
                    SUMMARY_SKIPPED+=("mpd.socket listens on ${MPD_ADDRS} (bind_to_address ignored) — to keep mpd local, ${MPD_FIX_SHORT}") ;;
                no)
                    echo -e "  mpd.socket (user) is enabled and listens only locally (${MPD_ADDRS}) — left as it is." ;;
                *)
                    echo -e "  ${YELLOW}⚠ mpd.socket (user) is enabled; archenemy could not read what it listens on.${NC}"
                    echo -e "    Check: systemctl --user show -p Listen mpd.socket — if it shows [::]:6600 or 0.0.0.0:6600, mpd (no password)"
                    echo -e "    is reachable from your network (socket activation ignores bind_to_address \"localhost\"). Then, to keep it local:"
                    echo -e "    $MPD_FIX"
                    SUMMARY_SKIPPED+=("mpd.socket — check what it listens on (systemctl --user show -p Listen mpd.socket); if [::]:6600 or 0.0.0.0:6600: ${MPD_FIX_SHORT}") ;;
            esac
        fi
    elif svc_check --user mpd.service; MPD_SVC=$?; [[ $MPD_SVC -ne 2 ]]; then
        # D7: ✓ dopiero po enabled + active (dotąd samo is-enabled).
        if [[ $MPD_SVC -eq 0 ]]; then
            echo -e "  ${GREEN}✓ mpd user service already enabled${NC}"
        else
            svc_dead "mpd user service" "systemctl --user status mpd; journalctl --user -u mpd"
        fi
    elif [[ "$PLATFORM" == nixos ]]; then
        manual_step "mpd user service" "$MPD_NIX_DECL"
        SUMMARY_SKIPPED+=("mpd user service — not done on NixOS: declare systemd.user.services.mpd (see above), then nixos-rebuild switch")
    elif [[ "$PLATFORM" != arch ]]; then
        # Fedora: usługi zostają ręczne (D7); pakiet mpd ma jednostkę użytkownika.
        manual_step "mpd user service" "systemctl --user enable --now mpd.service" summary
    else
        read -rp "  Enable mpd as your user service now (systemctl --user enable --now mpd)? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            if ! systemctl --user enable --now mpd.service; then
                echo -e "  ${RED}✗ systemctl --user enable --now mpd.service failed — check: journalctl --user -u mpd${NC}"
                SUMMARY_SKIPPED+=("mpd user service (enable failed — see journalctl --user -u mpd)")
            elif svc_check --user mpd.service; then
                echo -e "  ${GREEN}✓ mpd.service (user) enabled${NC}"
                SUMMARY_DONE+=("mpd user service enabled")
            else
                # Kod 0 bez efektu (D7): nie enabled albo nie działa po starcie.
                echo -e "  ${RED}✗ mpd.service (user) is not enabled and running after systemctl --user enable --now — check: systemctl --user status mpd; journalctl --user -u mpd${NC}"
                SUMMARY_SKIPPED+=("mpd user service (not running after enable — check: systemctl --user status mpd; journalctl --user -u mpd)")
            fi
        else
            SUMMARY_SKIPPED+=("mpd user service not enabled (your choice): systemctl --user enable --now mpd")
        fi
    fi
    # <<< 8l: usługa mpd <<<
fi

if command -v ncmpcpp >/dev/null 2>&1; then
    NCMPCPP_DESKTOP="$HOME/.local/share/applications/ncmpcpp.desktop"
    if [[ -e "$NCMPCPP_DESKTOP" ]]; then
        echo -e "  ${YELLOW}⚠ $(basename "$NCMPCPP_DESKTOP") already exists, left as it is.${NC}"
    else
        mkdir -p "$(dirname "$NCMPCPP_DESKTOP")"
        cp "$ARCHENEMY_DIR/config/applications/ncmpcpp.desktop" "$NCMPCPP_DESKTOP"
        echo -e "  ${GREEN}✓ ncmpcpp.desktop → rofi (Super+R) and [p] autostart${NC}"
    fi
fi

# 8m. TUI Super+A także z rofi i z terminala (właściciel 2026-10-14) oraz
#     wspólny plik powłoki (właściciel 2026-11-09).
#   - ~/.local/share/applications/archenemy.desktop — wpis „archenemy” w rofi:
#     to samo pływające okno co Super+A (klasa archenemy-appbinds = te same
#     reguły okna). Plik GENEROWANY, nie kopiowany z repo: pole Exec w .desktop
#     nie rozwija `~` ani $HOME, więc potrzebna bezwzględna ścieżka tej maszyny
#     (warstwa osobista, poza gitem). Istniejącego pliku nie ruszamy.
#   - config/shell/shellrc — aliasy, funkcje i PATH użytkownika dla basha i zsh
#     (warstwa osobista, gitignore); ~/.bashrc dostaje tylko oznaczony blok,
#     który go wczytuje. PO CICHU, bez nowych pytań: wybór powłoki i
#     przenoszenie własnych linii z ~/.bashrc należą do Super+A → [h].
#     Każda zmiana ~/.bashrc zostawia kopię .bak-<czas>; drugi bieg = no-op.
#     Logika: scripts/shell/lib/shell-rc.sh (ta sama co w TUI).
#   - alias `archenemy` — TUI w bieżącym terminalu. Repo jest publiczne:
#     pytamy przed dopisaniem, dopisujemy raz (znacznik); cudzy alias o tej
#     nazwie wygrywa. Od 2026-11-09 trafia do pliku wspólnego, więc działa
#     w bashu i zsh; alias dopisany dawniej do ~/.bashrc przenosimy tam sam.
#     `~` w aliasie, nie rozwinięta ścieżka — repo zawsze leży w ~/archenemy
#     (pilnuje tego start instalatora).
APPBINDS_SH="$ARCHENEMY_DIR/scripts/appbinds/appbinds.sh"
ARCHENEMY_DESKTOP="$HOME/.local/share/applications/archenemy.desktop"
if [[ -e "$ARCHENEMY_DESKTOP" ]]; then
    echo -e "  ${YELLOW}⚠ archenemy.desktop already exists, left as it is.${NC}"
elif [[ "$APPBINDS_SH" == *[\"\`\$\\]* ]]; then
    # Te znaki wymagałyby ucieczek w cudzysłowie pola Exec — nie ryzykujemy.
    echo -e "  ${YELLOW}⚠ The path $APPBINDS_SH contains \" \` \$ or \\, skipping the rofi entry.${NC}"
    SUMMARY_SKIPPED+=("archenemy.desktop (rofi entry) — unusual characters in \$HOME")
else
    mkdir -p "$(dirname "$ARCHENEMY_DESKTOP")"
    cat > "$ARCHENEMY_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=archenemy
GenericName=archenemy settings
Comment=App shortcuts, autostart, workspace mode and updates (same as Super+A)
Exec=alacritty --class archenemy-appbinds -e "$APPBINDS_SH"
Icon=preferences-desktop-keyboard-shortcuts
Terminal=false
Categories=Settings;
Keywords=archenemy;appbinds;shortcuts;autostart;update;
EOF
    echo -e "  ${GREEN}✓ archenemy.desktop → rofi (Super+R) opens the Super+A menu${NC}"
fi

# shellcheck source=../scripts/shell/lib/shell-rc.sh
source "$ARCHENEMY_DIR/scripts/shell/lib/shell-rc.sh"
BASHRC="$HOME/.bashrc"
ZSHRC="$HOME/.zshrc"
if [[ "$(shellrc_ensure)" == created ]]; then
    echo -e "  ${GREEN}✓ config/shell/shellrc: your aliases, functions and PATH for bash and zsh (Super+A → [h])${NC}"
    SUMMARY_DONE+=("Shared shell file: ${SHELLRC/#$HOME/\~} (bash and zsh read it; edit: Super+A → [h])")
fi
SHELL_BAK_FILE="$(mktemp)"
SHELL_RES="$(rc_block_ensure "$BASHRC" bash 2>"$SHELL_BAK_FILE")"
SHELL_BAK="$(cat "$SHELL_BAK_FILE" 2>/dev/null)"
rm -f "$SHELL_BAK_FILE"
case "$SHELL_RES" in
    ok)      echo -e "  ${GREEN}✓ ~/.bashrc already loads the shared file${NC}" ;;
    created) echo -e "  ${GREEN}✓ ~/.bashrc created, it loads the shared file${NC}" ;;
    added|updated)
        echo -e "  ${GREEN}✓ ~/.bashrc loads the shared file (archenemy block; backup: ${SHELL_BAK/#$HOME/\~})${NC}"
        SUMMARY_DONE+=("Your ~/.bashrc loads the shared shell file (backup: ${SHELL_BAK/#$HOME/\~})") ;;
    managed)
        echo -e "  ${YELLOW}⚠ ~/.bashrc is managed by home-manager (link into /nix/store), left as it is.${NC}"
        echo -e "    Add these lines to programs.bash.initExtra in your home-manager configuration, then run home-manager switch:"
        rc_block_text bash | sed 's/^/      /'
        SUMMARY_SKIPPED+=("Your ~/.bashrc comes from home-manager: add the archenemy block (shown in step [8m]) to programs.bash.initExtra") ;;
    *)
        echo -e "  ${YELLOW}⚠ ~/.bashrc has the start of the archenemy block without its end, left as it is: fix it by hand.${NC}"
        SUMMARY_SKIPPED+=("Your ~/.bashrc has a broken archenemy block (no '$SHELL_BLOCK_END' line) — fix it by hand") ;;
esac
# ~/.zshrc tylko odświeżamy, gdy blok już w nim jest; dopisuje go Super+A → [h].
if rc_block_present "$ZSHRC"; then
    if [[ "$(rc_block_ensure "$ZSHRC" zsh 2>/dev/null)" == managed ]]; then
        SUMMARY_SKIPPED+=("Your ~/.zshrc comes from home-manager and has an old archenemy block: update it in programs.zsh.initContent (Super+A → [h] shows the lines)")
    fi
elif [[ "$(basename "${SHELL:-}")" == zsh || -e "$ZSHRC" ]]; then
    SUMMARY_SKIPPED+=("Your ~/.zshrc does not load the shared shell file yet: Super+A → [h] → switch to zsh")
fi

ALIAS_STATE="$(archenemy_alias_state "$BASHRC" "$ZSHRC")"
case "$ALIAS_STATE" in
    ours)
        echo -e "  ${GREEN}✓ the 'archenemy' command is already in the shared file${NC}"
        # Dawny polski znacznik nad aliasem → angielski; drugi bieg = no-op.
        if ! SHELL_BAK="$(archenemy_alias_mark_refresh)"; then
            echo -e "  ${YELLOW}⚠ Could not update the comment above the 'archenemy' alias in ${SHELLRC/#$HOME/\~}.${NC}"
        elif [[ -n "$SHELL_BAK" ]]; then
            echo -e "  ${GREEN}✓ Comment above the 'archenemy' alias updated (backup: ${SHELL_BAK/#$HOME/\~})${NC}"
        fi ;;
    own)  echo -e "  ${YELLOW}⚠ you already have your own 'archenemy' alias, left as it is.${NC}" ;;
    legacy*)
        SHELL_BAK="$(archenemy_alias_move "${ALIAS_STATE#legacy }")"
        case $? in
            0)  echo -e "  ${GREEN}✓ the 'archenemy' command moved to the shared file (works in zsh too; backup: ${SHELL_BAK/#$HOME/\~})${NC}"
                SUMMARY_DONE+=("'archenemy' command moved to the shared shell file") ;;
            2)  # Plik z home-managera: bez kopii, bez zapisu, alias zostaje (L1).
                ALIAS_RC="${ALIAS_STATE#legacy }"
                echo -e "  ${YELLOW}⚠ ${ALIAS_RC/#$HOME/\~} is managed by home-manager: the old 'archenemy' alias stays there.${NC}"
                echo -e "    Remove it from your home-manager configuration and re-run install.sh to add it to the shared file."
                SUMMARY_SKIPPED+=("'archenemy' command stays in your home-manager ${ALIAS_RC/#$HOME/\~} — remove the old alias there, then re-run install.sh") ;;
            *)  echo -e "  ${YELLOW}⚠ Could not move the 'archenemy' command, it stays where it was.${NC}" ;;
        esac ;;
    *)
        read -rp "  Add the 'archenemy' command (opens the Super+A menu in the terminal, bash and zsh)? [Y/n]: " ans_alias
        if [[ "$ans_alias" =~ ^[Nn]$ ]]; then
            SUMMARY_SKIPPED+=("'archenemy' command (your choice) — re-run install.sh to add it")
        elif archenemy_alias_add; then
            echo -e "  ${GREEN}✓ the 'archenemy' command added to the shared file (open a new terminal or run: exec \$SHELL)${NC}"
            SUMMARY_DONE+=("'archenemy' command added to the shared shell file")
        else
            echo -e "  ${RED}✗ Could not add the alias to $SHELLRC.${NC}"
            SUMMARY_SKIPPED+=("'archenemy' command — writing the shared shell file failed")
        fi ;;
esac
SHELL_MOVABLE="$(rc_migrate_preview "$BASHRC" | grep -cv '^[[:space:]]*#')"
# ~/.bashrc z home-managera: [h] → 3 i tak niczego z niego nie przenosi.
if (( SHELL_MOVABLE > 0 )) && ! rc_store_managed "$BASHRC"; then
    SUMMARY_SKIPPED+=("$SHELL_MOVABLE line(s) of your ~/.bashrc (aliases, exports) stay bash-only until you move them: Super+A → [h] → 3")
fi

SUMMARY_DONE+=("Machine-local configs generated (GPU: $GPU_KIND)")
echo ""

# ─── 9. SYMLINKS ──────────────────────────────────────────────────────────────

echo -e "${CYAN}[9] Creating symlinks for rice '$TARGET_RICE'...${NC}"

# Linkowanie robi wspólna biblioteka przełącznika (lib/switch-rice.sh — ta
# sama, którą woła Super+T): flock, sprzątanie linków do INNYCH rice'ów,
# cudzy symlink (np. GNU stow) lub prawdziwy katalog → .bak-<ts> (nigdy rm),
# ln -sfn, zapis .current_rice. Dotąd [9] miał własną kopię pętli, która
# kasowała KAŻDY symlink na miejscu folderu rice'a — także spoza rices/
# (audyt 2026-09-25). SWITCH_RICE_LINK_ONLY=1 = bez tapety, hyprctl reload
# i restartu waybara w środku instalacji. Osobny proces (bash …), bo
# biblioteka kończy się `exit` przy błędzie, a instalator ma iść dalej.
SWITCH_RICE_LIB="$ARCHENEMY_DIR/scripts/changing-theme-scripts/lib/switch-rice.sh"
RICES_REAL="$(readlink -f "$RICES_DIR")"
# D10: home-manager (dowiązania do /nix/store) w miejscu folderu rice'a, w nim
# albo jako całe ~/.config → nie wołamy biblioteki wcale (ona też by odmówiła
# z kodem 3): żadnego sprzątania, .bak, linku ani .current_rice, tylko porada.
HM_HITS=()
if [[ -f "$ARCHENEMY_DIR/scripts/lib/hm-conflict.sh" ]]; then
    # shellcheck source=../scripts/lib/hm-conflict.sh
    source "$ARCHENEMY_DIR/scripts/lib/hm-conflict.sh"
    mapfile -t HM_HITS < <(hm_rice_conflicts "$RICES_DIR/$TARGET_RICE" "$CONFIG_DIR")
fi
LINK_PRE_BAK=()   # cudze rzeczy, które biblioteka zaraz odłoży do .bak (do komunikatu)
for src in "$RICES_DIR/$TARGET_RICE"/*/; do
    [[ -d "$src" ]] || continue
    name=$(basename "$src")
    dest="$CONFIG_DIR/$name"
    if [[ -L "$dest" ]]; then
        [[ "$(readlink -f "$dest")" == "$RICES_REAL/"* ]] || LINK_PRE_BAK+=("$name")
    elif [[ -e "$dest" ]]; then
        LINK_PRE_BAK+=("$name")
    fi
done

LINK_FAIL=0
if (( ${#HM_HITS[@]} > 0 )); then
    for name in "${HM_HITS[@]}"; do
        echo -e "  ${YELLOW}⚠ ${name/#$HOME/\~} is managed by home-manager (link into /nix/store), left as it is.${NC}"
    done
    hm_advice "${HM_HITS[@]}" | sed 's/^/    /'
    SUMMARY_SKIPPED+=("Rice '$TARGET_RICE' NOT linked: home-manager manages ${HM_HITS[0]/#$HOME/\~} — remove it from your home-manager configuration, run home-manager switch, then run install.sh again")
    LINK_FAIL=2   # podsumowanie już ma wpis z poradą
elif RICE_NAME="$TARGET_RICE" SWITCH_RICE_LINK_ONLY=1 bash "$SWITCH_RICE_LIB"; then
    # Sukces = zaobserwowany link, nie kod wyjścia biblioteki.
    for src in "$RICES_DIR/$TARGET_RICE"/*/; do
        [[ -d "$src" ]] || continue
        name=$(basename "$src")
        if [[ "$(readlink "$CONFIG_DIR/$name" 2>/dev/null)" == "${src%/}" ]]; then
            echo -e "  ${GREEN}✓ ~/.config/$name → ${src%/}${NC}"
        else
            echo -e "  ${RED}✗ ~/.config/$name does not point to ${src%/}${NC}"
            LINK_FAIL=1
        fi
    done
    for name in "${LINK_PRE_BAK[@]}"; do
        bak="$(ls -d "$CONFIG_DIR/$name".bak-* 2>/dev/null | tail -n1)"
        echo -e "  ${YELLOW}⚠ Your previous ~/.config/$name was kept as ${bak##*/}${NC}"
    done
else
    echo -e "  ${RED}✗ lib/switch-rice.sh failed (another switch holding the lock? missing rice?).${NC}"
    LINK_FAIL=1
fi
if [[ $LINK_FAIL -eq 0 ]]; then
    SUMMARY_DONE+=("Rice '$TARGET_RICE' symlinked into ~/.config")
elif [[ $LINK_FAIL -eq 1 ]]; then
    SUMMARY_SKIPPED+=("Rice '$TARGET_RICE' NOT fully linked — run scripts/changing-theme-scripts/$TARGET_RICE.sh (Super+T)")
fi
echo ""

# ─── 9.5 SCRIPTS + INITIAL WALLPAPER ─────────────────────────────────────────

echo -e "${CYAN}[9.5] Finishing touches...${NC}"

# Make all archenemy scripts executable
find "$ARCHENEMY_DIR/scripts" -name "*.sh" -exec chmod +x {} \;
echo -e "  ${GREEN}✓ Scripts made executable.${NC}"

# Screenshots directory (hyprshot output)
mkdir -p "$HOME/Screenshots"

# Tapeta: przy pierwszej instalacji pierwszy plik z wallpapers/, żeby hyprpaper
# miał poprawny config od pierwszego startu; przy ponownym biegu (zalecanym po
# każdym pullu) zostaje wybór użytkownika z Super+W — `--init` przywraca go,
# gdy data/wallpaper.dat wskazuje istniejący plik (audyt 2026-09-23: dawniej
# każdy bieg nadpisywał wybór pierwszą tapetą).
WALLPAPER_SWITCHER="$ARCHENEMY_DIR/scripts/rofi/rofi_wallpaper_switcher.sh"
FIRST_WP=$(find "$ARCHENEMY_DIR/wallpapers" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    2>/dev/null | sort | head -n1)
WP_RESULT="$(bash "$WALLPAPER_SWITCHER" --init "$FIRST_WP")"
# Przełącznik wypisuje wynik dopiero po zastosowaniu tapety (audyt 2026-11-05,
# Z10: dawniej „initial” padało przed ustawieniem i tu leciało ✓). Szukamy
# całego wiersza z wynikiem — na stdout może trafić też obce wyjście.
# Log leży tam, gdzie pisze go przełącznik: prywatny katalog sesji
# (lib/runtime-dir.sh, S12), nigdy wspólny /tmp; --existing, bo instalator
# tylko go wskazuje. Bez katalogu przełącznik loguje do /dev/null.
# shellcheck source=scripts/lib/runtime-dir.sh
source "$ARCHENEMY_DIR/scripts/lib/runtime-dir.sh"
WP_LOG="$(archenemy_runtime_dir --existing)/archenemy-hyprpaper-err.log" \
    || WP_LOG="none, no private runtime directory"
case "$(grep -x -m1 -E 'restored|initial|none|restored-failed|initial-failed' <<< "$WP_RESULT")" in
    restored)
        echo -e "  ${GREEN}✓ Wallpaper kept — your last choice restored.${NC}"
        SUMMARY_DONE+=("Wallpaper kept (last choice restored)") ;;
    initial)
        echo -e "  ${GREEN}✓ Initial wallpaper applied.${NC}"
        SUMMARY_DONE+=("Initial wallpaper applied") ;;
    restored-failed|initial-failed)
        echo -e "  ${YELLOW}⚠ Wallpaper not shown — hyprpaper did not apply it. Log: $WP_LOG${NC}"
        SUMMARY_SKIPPED+=("wallpaper — hyprpaper did not show it (log: $WP_LOG); pick one with Super+W after logging back in") ;;
    none)
        echo -e "  ${YELLOW}⚠ No wallpapers found in wallpapers/ — use Super+W after adding some.${NC}"
        SUMMARY_SKIPPED+=("initial wallpaper (none in wallpapers/)") ;;
    *)
        echo -e "  ${YELLOW}⚠ Wallpaper not set — the wallpaper switcher gave no result.${NC}"
        SUMMARY_SKIPPED+=("wallpaper — the switcher gave no result; pick one with Super+W") ;;
esac
echo ""

# ─── 9.6 FLUX-WALL (tapeta liczona shaderem) ─────────────────────────────────
# Pierwszy komponent KOMPILOWANY w repo. Build jest opcjonalny z definicji:
# każde niepowodzenie (brak kompilatora, brak nagłówków, błąd make) zostawia
# tapety w hyprpaper jak dotąd i trafia do SUMMARY_SKIPPED — nigdy nie
# przerywa instalacji i nigdy nie zostawia czarnego ekranu.

echo -e "${CYAN}[9.6] Building flux-wall (shader wallpaper)...${NC}"

FLUX_WALL_DIR="$ARCHENEMY_DIR/src/flux-wall"
FLUX_WALL_MISSING=()
for tool in gcc make pkg-config wayland-scanner; do
    command -v "$tool" &>/dev/null || FLUX_WALL_MISSING+=("$tool")
done
for mod in wayland-client wayland-egl egl glesv2 libpulse-simple; do
    pkg-config --exists "$mod" 2>/dev/null || FLUX_WALL_MISSING+=("pkg-config:$mod")
done

if [[ ${#FLUX_WALL_MISSING[@]} -gt 0 ]]; then
    echo -e "  ${YELLOW}⚠ flux-wall skipped — missing: ${FLUX_WALL_MISSING[*]}${NC}"
    echo -e "    (packages: base-devel wayland mesa libpulse; wallpapers stay in hyprpaper)"
    SUMMARY_SKIPPED+=("flux-wall NOT built — missing: ${FLUX_WALL_MISSING[*]} (wallpapers via hyprpaper)")
elif ! FLUX_WALL_LOG=$(make -C "$FLUX_WALL_DIR" 2>&1); then
    echo -e "  ${RED}✗ flux-wall: build failed — last lines:${NC}"
    echo "$FLUX_WALL_LOG" | tail -5 | sed 's/^/    /'
    SUMMARY_SKIPPED+=("flux-wall NOT built — make failed (wallpapers via hyprpaper; details: make -C src/flux-wall)")
elif [[ -x "$FLUX_WALL_DIR/build/flux-wall" ]]; then
    echo -e "  ${GREEN}✓ flux-wall built: src/flux-wall/build/flux-wall${NC}"
    echo -e "    start: scripts/wallpapers/flux-wall.sh start   stop: ... stop"
    SUMMARY_DONE+=("flux-wall built (scripts/wallpapers/flux-wall.sh start)")
else
    echo -e "  ${RED}✗ flux-wall: make succeeded but the binary is missing${NC}"
    SUMMARY_SKIPPED+=("flux-wall NOT built — make succeeded, binary missing (wallpapers via hyprpaper)")
fi

# Wybór animacji z Super+W (data/flux-wall.dat) może wskazywać shader, którego
# już nie ma (np. usunięty z repo). Wrapper i tak by go pominął, ale CICHO —
# użytkownik widziałby tylko, że „animacja zniknęła". Decyzja właściciela
# 2026-09-08: nieaktualny wpis kasujemy tutaj, jawnie, z wpisem w podsumowaniu.
FLUX_CHOICE_DAT="$ARCHENEMY_DIR/data/flux-wall.dat"
if [[ -f "$FLUX_CHOICE_DAT" ]]; then
    FLUX_CHOICE="$(<"$FLUX_CHOICE_DAT")"; FLUX_CHOICE="${FLUX_CHOICE//[[:space:]]/}"
    # Migracja nazw (2026-09-17): wybór zostaje zamiast być skasowany jako
    # „nieistniejący". dither-orb → orb-spinnin' (rename + static), a wizualizacje
    # muzyki dla crt straciły przedrostek „dither-" (decyzja właściciela).
    FLUX_OLD_CHOICE="$FLUX_CHOICE"
    case "$FLUX_CHOICE" in
        dither-orb|dither-orb-spinnin\') FLUX_CHOICE="orb-spinnin'" ;;
        dither-orb-static|dither-scope|dither-scope-xy|dither-bars|dither-waterfall|dither-rings|dither-radar|dither-tunnel)
            FLUX_CHOICE="${FLUX_CHOICE#dither-}" ;;
    esac
    if [[ "$FLUX_CHOICE" != "$FLUX_OLD_CHOICE" ]]; then
        printf '%s\n' "$FLUX_CHOICE" > "$FLUX_CHOICE_DAT"
        echo -e "  ${GREEN}✓ flux-wall: choice '$FLUX_OLD_CHOICE' migrated to \"$FLUX_CHOICE\" (renamed)${NC}"
    fi
    if [[ -n "$FLUX_CHOICE" && "$FLUX_CHOICE" != "off" && ! -f "$FLUX_WALL_DIR/shaders/$FLUX_CHOICE.frag" ]]; then
        rm -f "$FLUX_CHOICE_DAT"
        echo -e "  ${YELLOW}⚠ Selected animation '$FLUX_CHOICE' no longer exists — choice cleared,${NC}"
        echo -e "    restoring the rice default animation (Super+W → Animation to choose another)."
        SUMMARY_DONE+=("flux-wall: cleared choice of missing animation '$FLUX_CHOICE' (Super+W → Animation)")
    fi
fi
echo ""

# ─── 9.7 TAPETY DITHER-FLUX POD REALNE MONITORY ──────────────────────────────
# Generator maluje raster 1 px, więc tapeta musi mieć DOKŁADNIE rozdzielczość
# monitora — skalowanie przez hyprpaper rozmywa ziarno. Rozdzielczości i role
# bierzemy z data/monitors/*.dat ([3.5]): primary → v1, secondary → v2 (tak
# paruje je przełącznik Super+W), pozostałe → m-<nazwa>. Wynik do
# wallpapers/dither-flux/generated/ (poza gitem). Czysty Python liczy kilka
# minut, więc generowanie idzie W TLE — instalator nie czeka; pliki pojawiają
# się w Super+W, gdy będą gotowe. Idempotentne: gotowe pliki pomijane.

echo -e "${CYAN}[9.7] Generating dither-flux wallpapers for detected monitors...${NC}"

FLUX_GEN="$ARCHENEMY_DIR/scripts/wallpapers/gen_dither_flux_wallpaper.py"
FLUX_OUT="$ARCHENEMY_DIR/wallpapers/dither-flux/generated"
if command -v python3 &>/dev/null && [[ -f "$FLUX_GEN" ]]; then
    source "$ARCHENEMY_DIR/scripts/wallpapers/lib/dither-flux-sizes.sh"
    dither_flux_plan "$DATA_DIR/monitors" "$FLUX_OUT"
    for _flux in "${FLUX_READY[@]}"; do
        echo -e "  ${GREEN}✓ $_flux — already generated${NC}"
    done
    for _flux in "${FLUX_SIZES[@]}"; do
        echo -e "  → $_flux"
    done
    if [[ ${#FLUX_SIZES[@]} -gt 0 ]]; then
        dither_flux_start "$FLUX_GEN" "$FLUX_OUT"
        echo -e "  ${GREEN}✓ generating in background (${FLUX_SIZES[*]}); log: wallpapers/dither-flux/generated/generate.log${NC}"
        SUMMARY_DONE+=("dither-flux: wallpapers for ${FLUX_SIZES[*]} generating in background (available in Super+W in a few minutes)")
    elif [[ ${#FLUX_SKIPPED_MONS[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}✓ nothing to do${NC}"
    fi
    if [[ ${#FLUX_SKIPPED_MONS[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠ skipped: ${FLUX_SKIPPED_MONS[*]}${NC}"
        SUMMARY_SKIPPED+=("dither-flux: wallpapers NOT generated for: ${FLUX_SKIPPED_MONS[*]} — enter a WxH resolution in [3.5] or run from a Hyprland session")
    fi
else
    echo -e "  ${YELLOW}⚠ python3 or generator missing — using only repo dither-flux wallpapers (v1/v2)${NC}"
    SUMMARY_SKIPPED+=("dither-flux: monitor wallpaper generation skipped (no python3)")
fi
echo ""

# ─── 10. UFW + SYSTEMD ────────────────────────────────────────────────────────

echo -e "${CYAN}[10] Optional configuration...${NC}"

# Działającej zapory nie ruszamy: ponowny bieg (zalecany po każdym pullu) po
# „y” znów wołał `ufw default deny incoming` / `allow outgoing` i po cichu
# nadpisywał polityki ustawione przez użytkownika (audyt 2026-11-05, S7).
# Stan czyta `ufw status` (wymaga roota); bez ufw albo bez odczytu = pytanie.
# Zapora poza Archem: Fedora ma firewalld, NixOS networking.firewall — UFW nie
# instalujemy i nie włączamy (D6). --skip-packages bez ufw: nie pytamy.
if [[ "$PLATFORM" == fedora ]]; then
    manual_step "Firewall" "Fedora uses firewalld, left as it is (archenemy does not install UFW)"
elif [[ "$PLATFORM" == nixos ]]; then
    manual_step "Firewall" "set networking.firewall in your NixOS configuration"
elif [[ "$SKIP_PACKAGES" -eq 1 ]] && ! command -v ufw >/dev/null 2>&1; then
    manual_step "UFW firewall" "ufw is not installed — run install.sh again after: sudo pacman -S --needed ufw"
else
    UFW_STATUS=""
    command -v ufw >/dev/null 2>&1 && UFW_STATUS="$(sudo ufw status verbose 2>/dev/null)"
    if grep -q '^Status: active' <<< "$UFW_STATUS"; then
        echo -e "  ${GREEN}✓ UFW firewall already active — your policies and rules are left as they are.${NC}"
        UFW_DEFAULTS="$(sed -n 's/^Default: //p' <<< "$UFW_STATUS")"
        [[ -n "$UFW_DEFAULTS" ]] && echo "    Default: $UFW_DEFAULTS"
        if ! systemctl is-enabled --quiet ufw 2>/dev/null; then
            echo -e "  ${YELLOW}⚠ ufw.service is not enabled — the firewall will be off after a reboot.${NC}"
            SUMMARY_SKIPPED+=("UFW is active now but does not start at boot: sudo systemctl enable ufw")
        fi
        ans=n
    else
        # Skutki włączenia wprost: domyślne polityki ORAZ /etc/ufw/sysctl.conf,
        # który ufw nakłada przy starcie (rp_filter=1 zamiast 2 z systemd,
        # accept_redirects=0) — plan bezpieczeństwa 2026-11-14 (Y1).
        echo "  UFW firewall: blocks incoming connections, outgoing stay allowed. Starting it"
        echo "  also applies /etc/ufw/sysctl.conf (strict reverse-path filtering rp_filter=1,"
        echo "  ICMP redirects ignored), which some VPN setups do not like. Serving anything"
        echo "  to your LAN (Steam Remote Play and LAN game transfers, KDE Connect, LocalSend)"
        echo "  stops working until you allow it with: sudo ufw allow ..."
        read -rp "Enable the UFW firewall with these defaults? [y/N]: " ans
    fi
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        # Każdy krok sprawdzany osobno — dotąd „✓ UFW configured" leciało nawet
        # gdy pacman/ufw/systemctl zawiodły (audyt 2026-09-25). Sukces = ufw
        # zgłasza „Status: active" I usługa jest włączona, nie kod wyjścia.
        UFW_FAIL=""
        if [[ "$SKIP_PACKAGES" -eq 0 ]] && ! sudo pacman -S --needed ufw; then
            UFW_FAIL="pacman (ufw package)"
        elif ! sudo ufw default deny incoming || ! sudo ufw default allow outgoing; then
            UFW_FAIL="ufw default deny/allow"
        elif ! sudo ufw enable || ! sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
            UFW_FAIL="ufw enable (status is not 'active')"
        elif ! sudo systemctl enable ufw || ! systemctl is-enabled --quiet ufw; then
            UFW_FAIL="systemctl enable ufw"
        fi
        if [[ -z "$UFW_FAIL" ]]; then
            echo -e "  ${GREEN}✓ UFW configured.${NC}"
            SUMMARY_DONE+=("UFW configured")
        else
            echo -e "  ${RED}✗ UFW NOT configured — failed: $UFW_FAIL${NC}"
            SUMMARY_SKIPPED+=("UFW — failed: $UFW_FAIL (finish manually: sudo ufw enable && sudo systemctl enable ufw)")
        fi
    fi
fi

# NetworkManager to twarde wymaganie (moduł sieci waybara, Super+N) — pomijamy
# tylko, gdy już jest włączony I działa (D7: dotąd samo is-enabled dawało ✓).
# Włączony, ale martwy: ostrzeżenie bez pytania i bez zmian.
if svc_check NetworkManager; NM_SVC=$?; [[ $NM_SVC -ne 2 ]]; then
    if [[ $NM_SVC -eq 0 ]]; then
        echo -e "  ${GREEN}✓ NetworkManager already enabled.${NC}"
    else
        svc_dead "NetworkManager" "systemctl status NetworkManager (network module and Super+N need it)"
    fi
elif [[ "$PLATFORM" == fedora ]]; then
    manual_step "NetworkManager" "$(pkg_hint networkmanager) && sudo systemctl enable --now NetworkManager.service (network module and Super+N need it; it takes over from iwd/systemd-networkd)" summary
elif [[ "$PLATFORM" == nixos ]]; then
    manual_step "NetworkManager" "networking.networkmanager.enable = true; (network module and Super+N need it)" summary
else
    echo -e "  ${YELLOW}Warning: if you use iwd/systemd-networkd, NetworkManager will take over networking.${NC}"
    read -rp "Enable NetworkManager (required by the network module)? [Y/n]: " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        # Sukces = usługa realnie włączona I działa (is-enabled + is-active, D7),
        # nie kod systemctl.
        if sudo systemctl enable --now NetworkManager && svc_check NetworkManager; then
            echo -e "  ${GREEN}✓ NetworkManager enabled.${NC}"
            SUMMARY_DONE+=("NetworkManager enabled")
        else
            echo -e "  ${RED}✗ NetworkManager NOT enabled and running — check: systemctl status NetworkManager${NC}"
            SUMMARY_SKIPPED+=("NetworkManager — enable failed (network module and Super+N will not work): sudo systemctl enable --now NetworkManager")
        fi
    else
        SUMMARY_SKIPPED+=("NetworkManager (network module and Super+N will not work)")
    fi
fi

# Bluetooth jest opcjonalny; osobny instalator weryfikuje stan przed flagą.
# Pomocnik instaluje bluez/bluetui pacmanem i włącza usługę — tylko Arch bez flagi.
case "$PLATFORM:$SKIP_PACKAGES" in
    # Te same instrukcje wypisuje sam pomocnik uruchomiony wprost (brama D7, kod 2).
    fedora:*) manual_step "Bluetooth (optional)" "sudo dnf install bluez dbus-tools && sudo systemctl enable --now bluetooth.service; bluetui: $(pkg_hint bluetui); bar icon: touch ~/archenemy/data/bluetooth-enabled.dat" ;;
    nixos:*)  manual_step "Bluetooth (optional)" "hardware.bluetooth.enable = true; plus pkgs.bluetui, nixos-rebuild switch; bar icon: touch ~/archenemy/data/bluetooth-enabled.dat" ;;
    *:1)      manual_step "Bluetooth (optional)" "bash ~/archenemy/install/bluetooth-installation.sh" ;;
    *)
read -rp "Set up Bluetooth and its bar icon (bluez, bluez-utils, bluetui)? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    if bash "$ARCHENEMY_DIR/install/bluetooth-installation.sh"; then
        SUMMARY_DONE+=("Bluetooth enabled with bluetui and bar icon (reload waybar)")
    else
        SUMMARY_SKIPPED+=("Bluetooth — setup incomplete; retry: bash ~/archenemy/install/bluetooth-installation.sh")
    fi
fi
        ;;
esac

# VirtualBox jest opcjonalny i NIE leży w additional-packages: sam pakiet bez
# nagłówków jądra i modułu vboxdrv nie uruchomi żadnej maszyny. Pakiety,
# nagłówki, moduł i grupę vboxusers załatwia osobny skrypt; kod wyjścia to
# kontrakt (0 gotowe, 2 potrzebny restart, inaczej porażka) — opis w skrypcie.
case "$PLATFORM:$SKIP_PACKAGES" in
    fedora:*) manual_step "VirtualBox (optional)" "see VirtualBox's Linux downloads (RPM Fusion has it too)" ;;
    nixos:*)  manual_step "VirtualBox (optional)" "virtualisation.virtualbox.host.enable = true;" ;;
    *:1)      manual_step "VirtualBox (optional)" "bash ~/archenemy/install/virtualbox-installation.sh" ;;
    *)
read -rp "Install Oracle VirtualBox (virtual machines)? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    bash "$ARCHENEMY_DIR/install/virtualbox-installation.sh"
    case $? in
        0) SUMMARY_DONE+=("VirtualBox installed (vboxdrv loaded)") ;;
        2) SUMMARY_SKIPPED+=("VirtualBox — installed, but vboxdrv is not running in the current kernel: reboot") ;;
        *) SUMMARY_SKIPPED+=("VirtualBox — installation failed (details above; retry: bash ~/archenemy/install/virtualbox-installation.sh)") ;;
    esac
fi
        ;;
esac

# Audio: pavucontrol i moduł głośności waybara mówią po PulseAudio — serwer
# dostarcza pipewire-pulse (socket użytkownika, na Archu włączany presetem).
# D7: ✓ dopiero po odczycie active I enabled; działający, ale niewłączony
# (po ponownym zalogowaniu nie wstanie) = ostrzeżenie, bez zmian.
AUDIO_UNITS=(pipewire.socket pipewire-pulse.socket wireplumber.service)
audio_units_ok() {
    local u
    for u in "${AUDIO_UNITS[@]}"; do svc_check --user "$u" || return 1; done
}
# D7F R1 (przegląd Codexa): „already running” = TA SAMA jednostka pulse
# (socket albo usługa) enabled i active ORAZ backend: pipewire (socket albo
# usługa) i wireplumber.service, każdy enabled i active. Dawne „(socket LUB
# usługa active) I (socket LUB usługa enabled)” dawało ✓ dla aktywnego, ale
# wyłączonego socketu przy martwej włączonej usłudze, a backendu nie czytało.
audio_backend_ok() {
    { svc_check --user pipewire.socket || svc_check --user pipewire.service; } \
        && svc_check --user wireplumber.service
}
if systemctl --user is-active --quiet pipewire-pulse.socket \
   || systemctl --user is-active --quiet pipewire-pulse.service; then
    if svc_check --user pipewire-pulse.socket || svc_check --user pipewire-pulse.service; then
        if audio_backend_ok; then
            echo -e "  ${GREEN}✓ Audio (pipewire-pulse) already running.${NC}"
        else
            echo -e "  ${YELLOW}⚠ Audio: pipewire-pulse is running, but its backend (pipewire, wireplumber) is not enabled and running. Check: systemctl --user status pipewire.socket wireplumber.service${NC}"
            SUMMARY_SKIPPED+=("Audio — pipewire/wireplumber not enabled and running, check: systemctl --user status pipewire.socket wireplumber.service")
        fi
    elif systemctl --user is-enabled --quiet pipewire-pulse.socket 2>/dev/null \
         || systemctl --user is-enabled --quiet pipewire-pulse.service 2>/dev/null; then
        # Coś jest enabled, coś active — ale nie ta sama jednostka.
        echo -e "  ${YELLOW}⚠ Audio (pipewire-pulse): no unit is both enabled and running (the running one will not start at the next login). Check: systemctl --user status pipewire-pulse.socket pipewire-pulse.service${NC}"
        SUMMARY_SKIPPED+=("Audio (pipewire-pulse) — no unit both enabled and running, check: systemctl --user status pipewire-pulse.socket pipewire-pulse.service")
    else
        echo -e "  ${YELLOW}⚠ Audio (pipewire-pulse) is running, but not enabled — it will not start at the next login. Check: systemctl --user status pipewire-pulse.socket${NC}"
        SUMMARY_SKIPPED+=("Audio (pipewire-pulse) — running but not enabled, check: systemctl --user status pipewire-pulse.socket")
    fi
elif [[ "$PLATFORM" == nixos ]]; then
    manual_step "Audio (pipewire-pulse)" "services.pipewire.enable = true; services.pipewire.pulse.enable = true;" summary
elif [[ "$PLATFORM" != arch ]]; then
    # Fedora: pakiet RPM to pipewire-pulseaudio, jednostki jak na Archu.
    manual_step "Audio (pipewire-pulse)" "$(pkg_hint pipewire-pulse) wireplumber, then: systemctl --user enable --now ${AUDIO_UNITS[*]}" summary
elif systemctl --user enable --now "${AUDIO_UNITS[@]}" &>/dev/null; then
    if audio_units_ok; then
        echo -e "  ${GREEN}✓ pipewire-pulse started.${NC}"
        SUMMARY_DONE+=("Audio: pipewire-pulse started")
    else
        # Kod 0 bez efektu albo częściowy start (D7).
        echo -e "  ${YELLOW}⚠ Audio: systemctl returned success, but ${AUDIO_UNITS[*]} are not all enabled and running.${NC}"
        echo -e "    Check: systemctl --user status ${AUDIO_UNITS[*]} — or log out and back in."
        SUMMARY_SKIPPED+=("audio: pipewire-pulse not running after enable — check: systemctl --user status ${AUDIO_UNITS[*]}")
    fi
else
    echo -e "  ${YELLOW}⚠ Could not start pipewire-pulse — log out and back in.${NC}"
    SUMMARY_SKIPPED+=("audio: pipewire-pulse (re-login required)")
fi

echo ""

# ─── 11. DONE ─────────────────────────────────────────────────────────────────

# Stos muzyczny jest opcjonalny — przypomnij tylko tym, którzy go mają.
if command -v mpd >/dev/null 2>&1 || command -v ncmpcpp >/dev/null 2>&1; then
    SUMMARY_DONE+=("Music stack (optional): mpd + mpc + ncmpcpp go together; audio output: Super+A → [o] → 3")
fi

# Wersja kodu, z której powstała warstwa maszynowa — machine-layer-check.sh
# porównuje ją z HEAD na starcie sesji i mówi, gdy po pullu trzeba ponownie
# przejść install.sh (audyt 2026-09-23). data/ jest poza gitem.
if git -C "$ARCHENEMY_DIR" rev-parse HEAD >/dev/null 2>&1; then
    mkdir -p "$ARCHENEMY_DIR/data"
    printf 'COMMIT=%s\nDATE=%s\n' "$(git -C "$ARCHENEMY_DIR" rev-parse HEAD)" "$(date -Iseconds)" \
        > "$ARCHENEMY_DIR/data/installed-head.dat"
fi

echo -e "${CYAN}[11] Summary${NC}"
if [[ ${#SUMMARY_DONE[@]} -gt 0 ]]; then
    for item in "${SUMMARY_DONE[@]}"; do
        echo -e "  ${GREEN}✓ $item${NC}"
    done
fi
if [[ ${#SUMMARY_SKIPPED[@]} -gt 0 ]]; then
    for item in "${SUMMARY_SKIPPED[@]}"; do
        echo -e "  ${YELLOW}⚠ skipped: $item${NC}"
    done
fi
echo ""

# Baner zależy od listy pominięć (audyt 2026-11-05, Z8): „Everything is set
# up” tylko wtedy, gdy nic nie trafiło do SUMMARY_SKIPPED — dotąd leciał
# także po nieudanym pacmanie, sterowniku czy jądrze. Tekst w ramce tylko
# ASCII: printf wyrównuje bajtami.
if [[ ${#SUMMARY_SKIPPED[@]} -eq 0 ]]; then
    echo -e "${BLUE}"
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   Everything is set up. Have fun!   │"
else
    echo -e "${YELLOW}"
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   Setup finished with warnings:     │"
    printf '  │   %-34s│\n' "${#SUMMARY_SKIPPED[@]} item(s) skipped or failed," \
        "see the summary above."
fi
echo "  │                                     │"
echo "  │   If everything is working,         │"
echo "  │   leave a star on GitHub :)         │"
echo "  │   github.com/ksterajewicz/archenemy │"
echo "  └─────────────────────────────────────┘"
echo -e "${NC}"

# Koniec pracy z sudo (K18): unieważnij zapamiętane hasło, żeby przez
# następne minuty żaden inny proces użytkownika nie dostał roota bez pytania.
# Już tutaj, przed ostatnim pytaniem; przerwane biegi łapie pułapka EXIT
# ustawiona po wykryciu platformy. Bez sudo w tym biegu (USES_SUDO=0) — nic.
[[ "$USES_SUDO" == 0 ]] || sudo -k 2>/dev/null

# Pasek, tapetę, powiadomienia, OSD i schowek rice uruchamia w
# hl.on("hyprland.start"), a reload tego zdarzenia nie wywołuje. Po pierwszej
# instalacji (sesja z domyślnym configiem) pełny wygląd daje dopiero ponowne
# zalogowanie — dotąd nic o tym nie mówiło (audyt 2026-11-05, Z9).
echo -e "${YELLOW}After the first install, log out and back in once: the bar, wallpaper,${NC}"
echo -e "${YELLOW}notifications and clipboard start with the Hyprland session, a reload does not start them.${NC}"
echo ""
read -rp "Reload Hyprland now? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    # hyprctl reload wypisuje „ok" przy sukcesie; błąd configu lub brak
    # socketu = inny tekst / niezerowy kod — dotąd ✓ leciało bezwarunkowo.
    if RELOAD_OUT="$(hyprctl reload 2>&1)" && [[ "$RELOAD_OUT" == ok* ]]; then
        echo -e "${GREEN}✓ Hyprland reloaded.${NC}"
    else
        echo -e "${RED}✗ Hyprland reload failed:${NC} ${RELOAD_OUT:-no response}"
        echo -e "  Check the config (hyprctl reload) or log out and back in."
    fi
fi
