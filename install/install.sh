#!/bin/bash

# =============================================
#   archenemy - install.sh
#   Installs dependencies and sets up symlinks
# =============================================

# -e is intentionally omitted: this installer has many optional steps and a
# declined/failed optional step must not abort the whole run. Criticals are
# checked explicitly instead.
set -uo pipefail

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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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
sleep 3

# ─── 2. CHECK HYPRLAND ────────────────────────────────────────────────────────

if ! command -v hyprctl &>/dev/null; then
    echo -e "${RED}Hyprland is not installed.${NC}"
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
trap 'rm -rf "$MON_TMP"' EXIT
# Podmiana: stare .dat (także po monitorach, których już nie ma — inaczej
# wallpaper switcher mógłby wybrać odłączony monitor jako primary/secondary)
# znikają w tej samej chwili, w której wchodzą nowe (mv w obrębie data/ =
# rename, bez okna z pustym katalogiem dłuższym niż kilka syscalli).
commit_monitor_dats() {
    rm -f "$DATA_DIR/monitors"/*.dat
    mv "$MON_TMP"/*.dat "$DATA_DIR/monitors/"
    rmdir "$MON_TMP"
    trap - EXIT
}

declare -A MON_RES
declare -A MON_RATE
declare -A MON_POS
declare -A MON_SCALE
declare -A MON_ORDER

# ─── 3.5 MONITOR LAYOUT ───────────────────────────────────────────────────────

echo -e "${CYAN}[3.5] Configure monitor layout...${NC}"
echo ""

mon_idx=0
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

    # Sensible default: first monitor = primary, second = secondary, rest = other.
    # (rofi_wallpaper_switcher.sh maps primary→v1, secondary→v2.)
    case "$mon_idx" in
        0) def_role="primary" ;;
        1) def_role="secondary" ;;
        *) def_role="other" ;;
    esac
    while :; do
        read -rp "  Role (primary/secondary/other) [${def_role}]: " role
        role="${role:-$def_role}"
        [[ "$role" == "primary" || "$role" == "secondary" || "$role" == "other" ]] && break
        echo -e "  ${YELLOW}⚠ Choose: primary, secondary or other.${NC}"
    done

    # Rola NIE trafia do tablicy — od 2026-07-17 [8b] nie czyta ról (workspace'y
    # rządzi ORDER+tryb); rola żyje tylko w .dat (czyta ją wallpaper switcher).
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
    mon_idx=$((mon_idx + 1))
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
            if [[ ! "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#ORDER_PROPOSED[@]} )) \
               || [[ " $_seen " == *" $n "* ]]; then
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
        for n in "${picks[@]}"; do
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
    read -rp "  Choose mode [1/2]: " ws_choice
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

echo -e "${CYAN}[4] Checking yay...${NC}"

if ! command -v yay &>/dev/null; then
    echo -e "${YELLOW}yay not found.${NC}"
    read -rp "Install yay? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed git base-devel
        rm -rf /tmp/yay
        if git clone https://aur.archlinux.org/yay.git /tmp/yay \
           && ( cd /tmp/yay && makepkg -si ); then
            echo -e "${GREEN}✓ yay installed.${NC}"
        else
            echo -e "${RED}✗ yay build failed — AUR packages will be skipped.${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ AUR packages will be skipped without yay.${NC}"
    fi
else
    echo -e "${GREEN}✓ yay found.${NC}"
fi

echo ""

# ─── 5. CHECK REQUIREMENTS ────────────────────────────────────────────────────

echo -e "${CYAN}[5] Checking requirements...${NC}"
echo ""

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

if [[ ${#MISSING_PACMAN[@]} -gt 0 ]]; then
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

if [[ ${#MISSING_AUR[@]} -gt 0 ]]; then
    echo ""
    # Jak wyżej: wymagane → default-Yes + rejestr niepowodzeń w SUMMARY_SKIPPED.
    read -rp "Install missing AUR packages with yay? [Y/n]: " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        if command -v yay &>/dev/null; then
            if ! yay -S --needed "${MISSING_AUR[@]}"; then
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

echo ""
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
            idx=$((n - 1))
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

        if [[ ${#sel_pacman[@]} -gt 0 ]]; then
            sudo pacman -S --needed "${sel_pacman[@]}"
        fi
        if [[ ${#sel_aur[@]} -gt 0 ]]; then
            if command -v yay &>/dev/null; then
                yay -S --needed "${sel_aur[@]}"
            else
                echo -e "  ${YELLOW}⚠ yay unavailable — skipping AUR packages: ${sel_aur[*]}${NC}"
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
    echo -e "  Setting up power-profiles-daemon."
    sudo pacman -S --needed power-profiles-daemon
    sudo systemctl enable --now power-profiles-daemon 2>/dev/null
}

case "$hw_choice" in
    1)
        HW_PROFILE="asus"
        echo -e "  ${GREEN}✓ ASUS ROG selected.${NC}"
        echo ""
        # Kod wyjścia to kontrakt (0 gotowe, 2 potrzebny restart, inaczej porażka),
        # opis w skrypcie. Decyzja właściciela 2026-10-14: pakiety z repo, nie z AUR.
        bash "$ARCHENEMY_DIR/install/asus-installation.sh"
        case $? in
            0) SUMMARY_DONE+=("ASUS: asusctl + rog-control-center from the Arch repo, asusd running") ;;
            2) SUMMARY_SKIPPED+=("ASUS: packages installed, asusd not running yet: reboot") ;;
            *) SUMMARY_SKIPPED+=("ASUS: installation failed, profiles via power-profiles-daemon (retry: bash ~/archenemy/install/asus-installation.sh)") ;;
        esac
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
    echo -e "    ASUS: bash ~/archenemy/install/asus-installation.sh. Other devices: systemctl enable --now power-profiles-daemon."
    SUMMARY_SKIPPED+=("Hardware profile: $HW_PROFILE — profile tool is NOT responding, the bar will show \"brak\"")
else
    SUMMARY_DONE+=("Hardware profile: $HW_PROFILE (active profile: $PROFILE_CHECK)")
fi

echo ""

# ─── 6.5 DRIVERS + KERNEL (optional) ─────────────────────────────────────────

echo -e "${CYAN}[6.5] Optional drivers & kernel...${NC}"

read -rp "  Run CPU microcode installer? [y/N]: " ans
[[ "$ans" =~ ^[Yy]$ ]] && bash "$ARCHENEMY_DIR/install/cpudrivers-installation.sh"

read -rp "  Run GPU drivers installer? [y/N]: " ans
[[ "$ans" =~ ^[Yy]$ ]] && bash "$ARCHENEMY_DIR/install/gpudrivers-installation.sh"

read -rp "  Run kernel installer? [y/N]: " ans
[[ "$ans" =~ ^[Yy]$ ]] && bash "$ARCHENEMY_DIR/install/kernel-install.sh"

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
    GPU_INFO=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display')
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
#     (albo ~/.mpdconf, ~/.mpd) zostaje nietknięty bez jawnego „y" — cudzy
#     mpd.conf może wskazywać bibliotekę na NAS-ie i bazę budowaną godzinami;
#   - usługa użytkownika włączana wyłącznie po pytaniu [y/N]; gdy mpd działa
#     jako usługa SYSTEMOWA — tylko informacja (dwa mpd = konflikt portu/karty);
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
    if [[ -L "$MPD_USER_DIR" && "$(readlink -f "$MPD_USER_DIR")" == "$(readlink -f "$MPD_CONF_DIR")" ]]; then
        echo -e "  ${GREEN}✓ ~/.config/mpd → config/mpd (already linked)${NC}"
    elif [[ -e "$MPD_USER_DIR" || -e "$HOME/.mpdconf" || -d "$HOME/.mpd" ]]; then
        echo -e "  ${YELLOW}⚠ You already have an mpd config (~/.config/mpd, ~/.mpdconf or ~/.mpd).${NC}"
        echo -e "    archenemy does NOT replace it automatically. You can replace it now (the old directory"
        echo -e "    will be kept as ~/.config/mpd.bak-<timestamp>) or manually later."
        read -rp "  Replace ~/.config/mpd with archenemy's config now (backup kept)? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            [[ -e "$MPD_USER_DIR" ]] && mv "$MPD_USER_DIR" "$MPD_USER_DIR.bak-$(date +%Y%m%d_%H%M%S)"
            ln -s "$MPD_CONF_DIR" "$MPD_USER_DIR"
            echo -e "  ${GREEN}✓ ~/.config/mpd → config/mpd (previous kept as .bak)${NC}"
            [[ -e "$HOME/.mpdconf" || -d "$HOME/.mpd" ]] && echo -e "  ${YELLOW}⚠ ~/.mpdconf / ~/.mpd are kept — mpd reads ~/.config/mpd/mpd.conf first.${NC}"
            SUMMARY_DONE+=("mpd config linked (previous kept as .bak)")
        else
            echo -e "  ${YELLOW}⚠ Keeping your mpd config. The ncmpcpp theme still works;${NC}"
            echo -e "    the ncmpcpp visualizer needs a fifo output in your mpd.conf (see config/mpd/mpd.conf)."
            SUMMARY_SKIPPED+=("mpd: existing user config kept (archenemy's config/mpd not linked)")
        fi
    else
        ln -s "$MPD_CONF_DIR" "$MPD_USER_DIR"
        echo -e "  ${GREEN}✓ ~/.config/mpd → config/mpd${NC}"
        SUMMARY_DONE+=("mpd config linked (~/.config/mpd → config/mpd)")
    fi

    if systemctl is-enabled --quiet mpd.service 2>/dev/null || systemctl is-active --quiet mpd.service 2>/dev/null; then
        echo -e "  ${YELLOW}⚠ mpd runs as a SYSTEM service — skipping the user service${NC}"
        echo -e "    (two mpd instances conflict over port 6600 and the sound card). Left as it is."
        SUMMARY_SKIPPED+=("mpd user service (system-wide mpd is enabled)")
    elif systemctl --user is-enabled --quiet mpd.service 2>/dev/null || systemctl --user is-enabled --quiet mpd.socket 2>/dev/null; then
        echo -e "  ${GREEN}✓ mpd user service already enabled${NC}"
    else
        read -rp "  Enable mpd as your user service now (systemctl --user enable --now mpd)? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            if systemctl --user enable --now mpd.service; then
                echo -e "  ${GREEN}✓ mpd.service (user) enabled${NC}"
                SUMMARY_DONE+=("mpd user service enabled")
            else
                echo -e "  ${RED}✗ systemctl --user enable --now mpd.service failed — check: journalctl --user -u mpd${NC}"
                SUMMARY_SKIPPED+=("mpd user service (enable failed — see journalctl --user -u mpd)")
            fi
        else
            SUMMARY_SKIPPED+=("mpd user service not enabled (your choice): systemctl --user enable --now mpd")
        fi
    fi
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
    *)
        echo -e "  ${YELLOW}⚠ ~/.bashrc has the start of the archenemy block without its end, left as it is: fix it by hand.${NC}"
        SUMMARY_SKIPPED+=("Your ~/.bashrc has a broken archenemy block (no '$SHELL_BLOCK_END' line) — fix it by hand") ;;
esac
# ~/.zshrc tylko odświeżamy, gdy blok już w nim jest; dopisuje go Super+A → [h].
if rc_block_present "$ZSHRC"; then
    rc_block_ensure "$ZSHRC" zsh >/dev/null 2>&1
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
        if SHELL_BAK="$(archenemy_alias_move "${ALIAS_STATE#legacy }")"; then
            echo -e "  ${GREEN}✓ the 'archenemy' command moved to the shared file (works in zsh too; backup: ${SHELL_BAK/#$HOME/\~})${NC}"
            SUMMARY_DONE+=("'archenemy' command moved to the shared shell file")
        else
            echo -e "  ${YELLOW}⚠ Could not move the 'archenemy' command, it stays where it was.${NC}"
        fi ;;
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
if (( SHELL_MOVABLE > 0 )); then
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
if RICE_NAME="$TARGET_RICE" SWITCH_RICE_LINK_ONLY=1 bash "$SWITCH_RICE_LIB"; then
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
else
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
case "${WP_RESULT%%$'\n'*}" in
    restored)
        echo -e "  ${GREEN}✓ Wallpaper kept — your last choice restored.${NC}"
        SUMMARY_DONE+=("Wallpaper kept (last choice restored)") ;;
    initial)
        echo -e "  ${GREEN}✓ Initial wallpaper applied.${NC}"
        SUMMARY_DONE+=("Initial wallpaper applied") ;;
    *)
        echo -e "  ${YELLOW}⚠ No wallpapers found in wallpapers/ — use Super+W after adding some.${NC}"
        SUMMARY_SKIPPED+=("initial wallpaper (none in wallpapers/)") ;;
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

read -rp "Auto-configure UFW firewall? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    # Każdy krok sprawdzany osobno — dotąd „✓ UFW configured" leciało nawet
    # gdy pacman/ufw/systemctl zawiodły (audyt 2026-09-25). Sukces = ufw
    # zgłasza „Status: active" I usługa jest włączona, nie kod wyjścia.
    UFW_FAIL=""
    if ! sudo pacman -S --needed ufw; then
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

# NetworkManager to twarde wymaganie (moduł sieci waybara, Super+N) — pomijamy
# tylko, gdy już jest włączony.
if systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    echo -e "  ${GREEN}✓ NetworkManager already enabled.${NC}"
else
    echo -e "  ${YELLOW}Warning: if you use iwd/systemd-networkd, NetworkManager will take over networking.${NC}"
    read -rp "Enable NetworkManager (required by the network module)? [Y/n]: " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        # Sukces = usługa realnie włączona (is-enabled), nie kod systemctl.
        if sudo systemctl enable --now NetworkManager && systemctl is-enabled --quiet NetworkManager; then
            echo -e "  ${GREEN}✓ NetworkManager enabled.${NC}"
            SUMMARY_DONE+=("NetworkManager enabled")
        else
            echo -e "  ${RED}✗ NetworkManager NOT enabled — check: systemctl status NetworkManager${NC}"
            SUMMARY_SKIPPED+=("NetworkManager — enable failed (network module and Super+N will not work): sudo systemctl enable --now NetworkManager")
        fi
    else
        SUMMARY_SKIPPED+=("NetworkManager (network module and Super+N will not work)")
    fi
fi

# Bluetooth jest opcjonalny — bluez instalujemy PRZED enable, żeby nie było
# błędu o nieistniejącym bluetooth.service.
read -rp "Set up bluetooth (installs bluez)? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    # pacman i systemctl sprawdzane osobno; sukces = bluetooth.service
    # realnie włączony, nie kod wyjścia (audyt 2026-09-25).
    if ! sudo pacman -S --needed bluez bluez-utils; then
        echo -e "  ${RED}✗ bluez NOT installed — skipping bluetooth.service.${NC}"
        SUMMARY_SKIPPED+=("Bluetooth — pacman did not install bluez/bluez-utils")
    elif sudo systemctl enable --now bluetooth && systemctl is-enabled --quiet bluetooth; then
        echo -e "  ${GREEN}✓ Bluetooth enabled.${NC}"
        SUMMARY_DONE+=("Bluetooth enabled")
    else
        echo -e "  ${RED}✗ bluetooth.service NOT enabled — check: systemctl status bluetooth${NC}"
        SUMMARY_SKIPPED+=("Bluetooth — bluez installed, but enable bluetooth.service failed")
    fi
fi

# VirtualBox jest opcjonalny i NIE leży w additional-packages: sam pakiet bez
# nagłówków jądra i modułu vboxdrv nie uruchomi żadnej maszyny. Pakiety,
# nagłówki, moduł i grupę vboxusers załatwia osobny skrypt; kod wyjścia to
# kontrakt (0 gotowe, 2 potrzebny restart, inaczej porażka) — opis w skrypcie.
read -rp "Install Oracle VirtualBox (virtual machines)? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    bash "$ARCHENEMY_DIR/install/virtualbox-installation.sh"
    case $? in
        0) SUMMARY_DONE+=("VirtualBox installed (vboxdrv loaded)") ;;
        2) SUMMARY_SKIPPED+=("VirtualBox — installed, but vboxdrv is not running in the current kernel: reboot") ;;
        *) SUMMARY_SKIPPED+=("VirtualBox — installation failed (details above; retry: bash ~/archenemy/install/virtualbox-installation.sh)") ;;
    esac
fi

# Audio: pavucontrol i moduł głośności waybara mówią po PulseAudio — serwer
# dostarcza pipewire-pulse (socket użytkownika, na Archu włączany presetem).
if systemctl --user is-active --quiet pipewire-pulse.socket \
   || systemctl --user is-active --quiet pipewire-pulse.service; then
    echo -e "  ${GREEN}✓ Audio (pipewire-pulse) already running.${NC}"
elif systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service &>/dev/null; then
    echo -e "  ${GREEN}✓ pipewire-pulse started.${NC}"
    SUMMARY_DONE+=("Audio: pipewire-pulse started")
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

echo -e "${BLUE}"
echo "  ┌─────────────────────────────────────┐"
echo "  │   Everything is set up. Have fun!   │"
echo "  │                                     │"
echo "  │   If everything is working,         │"
echo "  │   leave a star on GitHub :)         │"
echo "  │   github.com/ksterajewicz/archenemy │"
echo "  └─────────────────────────────────────┘"
echo -e "${NC}"

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
