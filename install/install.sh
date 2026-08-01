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
    fi
done < <(hyprctl monitors)

if [[ ${#MONITOR_NAMES[@]} -eq 0 ]]; then
    echo -e "${RED}No monitors detected. Make sure Hyprland is running.${NC}"
    exit 1
fi

echo -e "  ${GREEN}Detected monitors:${NC}"
for i in "${!MONITOR_NAMES[@]}"; do
    mon="${MONITOR_NAMES[$i]}"
    echo "    $((i+1))) $mon — ${CUR_RES[$mon]:-?}@${CUR_RATE[$mon]:-?}Hz, pozycja ${CUR_POS[$mon]:-?}, skala ${CUR_SCALE[$mon]:-?}"
done
echo ""

mkdir -p "$DATA_DIR/monitors"
# Sprzątamy .dat po monitorach, których już nie ma — inaczej wallpaper switcher
# mógłby wybrać odłączony monitor jako primary/secondary.
rm -f "$DATA_DIR/monitors"/*.dat

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
    echo -e "${YELLOW}Monitor: ${BLUE}$mon${NC}  ${NC}(Enter = zostaw obecne ustawienie)${NC}"

    # Domyślne = to, co monitor robi TERAZ (odczytane w [3]); gdy odczyt się
    # nie udał — bezpieczne 'preferred'/'auto', którymi Hyprland sam zarządzi.
    def_res="${CUR_RES[$mon]:-preferred}"
    def_rate="${CUR_RATE[$mon]:-}"
    def_pos="${CUR_POS[$mon]:-auto}"
    def_scale="${CUR_SCALE[$mon]:-1}"

    while :; do
        read -rp "  Rozdzielczość [${def_res}]: " res
        res="${res:-$def_res}"
        [[ "$res" =~ ^[0-9]+x[0-9]+$ || "$res" == "preferred" || "$res" == "highres" || "$res" == "highrr" ]] && break
        echo -e "  ${YELLOW}⚠ Format: SZERxWYS (np. 1920x1080) albo preferred/highres/highrr.${NC}"
    done

    if [[ "$res" == "preferred" || "$res" == "highres" || "$res" == "highrr" ]]; then
        # Te tryby same dobierają częstotliwość — 'preferred@144' to błędny zapis
        rate=""
    else
        while :; do
            read -rp "  Odświeżanie w Hz [${def_rate:-auto}]: " rate
            rate="${rate:-$def_rate}"
            [[ -z "$rate" || "$rate" =~ ^[0-9]+(\.[0-9]+)?$ ]] && break
            echo -e "  ${YELLOW}⚠ Podaj liczbę (np. 144) albo Enter.${NC}"
        done
    fi

    while :; do
        read -rp "  Pozycja XxY [${def_pos}]: " pos
        pos="${pos:-$def_pos}"
        pos="${pos// /x}"   # akceptuj też zapis '1920 0'
        [[ "$pos" =~ ^-?[0-9]+x-?[0-9]+$ || "$pos" == "auto" ]] && break
        echo -e "  ${YELLOW}⚠ Format: XxY (np. 1920x0) albo 'auto'.${NC}"
    done

    while :; do
        read -rp "  Skala [${def_scale}]: " scale
        scale="${scale:-$def_scale}"
        [[ "$scale" =~ ^[0-9]+(\.[0-9]+)?$ || "$scale" == "auto" ]] && break
        echo -e "  ${YELLOW}⚠ Podaj liczbę (np. 1, 1.33, 2) albo 'auto'.${NC}"
    done

    # Sensible default: first monitor = primary, second = secondary, rest = other.
    # (rofi_wallpaper_switcher.sh maps primary→v1, secondary→v2.)
    case "$mon_idx" in
        0) def_role="primary" ;;
        1) def_role="secondary" ;;
        *) def_role="other" ;;
    esac
    while :; do
        read -rp "  Rola (primary/secondary/other) [${def_role}]: " role
        role="${role:-$def_role}"
        [[ "$role" == "primary" || "$role" == "secondary" || "$role" == "other" ]] && break
        echo -e "  ${YELLOW}⚠ Wybierz: primary, secondary albo other.${NC}"
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
    } > "$DATA_DIR/monitors/$mon.dat"

    echo -e "  ${GREEN}✓ Saved data/monitors/$mon.dat${NC}"
    echo ""
    mon_idx=$((mon_idx + 1))
done

# ─── 3.6 MONITOR NUMBERING (lewa→prawa) ──────────────────────────────────────

echo -e "${CYAN}[3.6] Monitor numbering (left→right)...${NC}"
echo ""
echo -e "  Monitory dostają numery ${YELLOW}1, 2, 3…${NC} liczone ${YELLOW}od lewej do prawej${NC}"
echo -e "  (monitor 1 = skrajnie lewy na biurku). Od tych numerów zależy przydział"
echo -e "  workspace'ów — tryb wybierzesz w następnym kroku."
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
    echo "ORDER=1" >> "$DATA_DIR/monitors/$mon.dat"
    echo -e "  ${GREEN}✓ Jeden monitor ($mon) — numer 1.${NC}"
else
    while :; do
        echo -e "  Proponowana numeracja (z pozycji X):"
        for k in "${!ORDER_PROPOSED[@]}"; do
            i="${ORDER_PROPOSED[$k]}"
            mon="${MONITOR_NAMES[$i]}"
            echo "    $((k+1))) $mon  (pozycja ${MON_POS[$mon]})"
        done
        read -rp "  Enter = zatwierdź, albo wpisz własną kolejność numerami z listy (np. '2 1'): " -a picks
        [[ ${#picks[@]} -eq 0 ]] && break
        if [[ ${#picks[@]} -ne ${#ORDER_PROPOSED[@]} ]]; then
            echo -e "  ${YELLOW}⚠ Podaj dokładnie ${#ORDER_PROPOSED[@]} numerów (po jednym na monitor).${NC}"
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
            echo -e "  ${YELLOW}⚠ To musi być permutacja liczb 1..${#ORDER_PROPOSED[@]} (bez powtórzeń).${NC}"
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
        echo "ORDER=$ordk" >> "$DATA_DIR/monitors/$mon.dat"
        echo -e "  ${GREEN}✓ $ordk → $mon${NC}"
        ordk=$((ordk + 1))
    done
fi
echo ""

# ─── 3.7 WORKSPACE MODE ──────────────────────────────────────────────────────

echo -e "${CYAN}[3.7] Workspace mode...${NC}"
echo ""
echo -e "  1) ${GREEN}shared${NC}  — 10 wspólnych workspace'ów (1-10) dla wszystkich monitorów."
echo -e "     Monitor k (numeracja L→P) ma domowy workspace k. Super+1..0 działa"
echo -e "     globalnie. Odporny na odpinanie monitora (bez demona-guarda)."
echo -e "  2) ${GREEN}decades${NC} — każdy monitor ma WŁASNE workspace'y 1-10 (izolowane"
echo -e "     dekady). Super+1..0 działa w obrębie monitora z fokusem. Demon"
echo -e "     scala workspace'y po odpięciu monitora."
echo ""
while :; do
    read -rp "  Wybierz tryb [1/2]: " ws_choice
    case "$ws_choice" in
        1) WS_MODE="shared";  break ;;
        2) WS_MODE="decades"; break ;;
        *) echo -e "  ${YELLOW}⚠ Wpisz 1 albo 2.${NC}" ;;
    esac
done
echo "$WS_MODE" > "$DATA_DIR/workspace-mode.dat"
echo -e "  ${GREEN}✓ Tryb workspace'ów: $WS_MODE${NC}"
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
            echo -e "${RED}✗ pacman zgłosił błąd przy pakietach wymaganych.${NC}"
            SUMMARY_SKIPPED+=("WYMAGANE pakiety pacman — instalacja NIE powiodła się: ${MISSING_PACMAN[*]}")
        fi
    else
        SUMMARY_SKIPPED+=("WYMAGANE pakiety pacman pominięte na życzenie: ${MISSING_PACMAN[*]}")
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
                echo -e "${RED}✗ yay zgłosił błąd przy pakietach wymaganych.${NC}"
                SUMMARY_SKIPPED+=("WYMAGANE pakiety AUR — instalacja NIE powiodła się: ${MISSING_AUR[*]}")
            fi
        else
            echo -e "${YELLOW}⚠ yay not available — skipping AUR packages.${NC}"
            SUMMARY_SKIPPED+=("WYMAGANE pakiety AUR pominięte (brak yay): ${MISSING_AUR[*]}")
        fi
    else
        SUMMARY_SKIPPED+=("WYMAGANE pakiety AUR pominięte na życzenie: ${MISSING_AUR[*]}")
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
        echo -e "  ${YELLOW}⚠ Brak pozycji w packages/additional-packages-*.txt${NC}"
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
            echo -e "  ${YELLOW}⚠ Wybrane pakiety wymagają repo [multilib], które jest wyłączone —${NC}"
            echo -e "  ${YELLOW}  ich instalacja się nie powiedzie. Włącz je instalatorem GPU${NC}"
            echo -e "  ${YELLOW}  (install/gpudrivers-installation.sh) albo ręcznie w /etc/pacman.conf.${NC}"
        fi

        if [[ ${#sel_pacman[@]} -gt 0 ]]; then
            sudo pacman -S --needed "${sel_pacman[@]}"
        fi
        if [[ ${#sel_aur[@]} -gt 0 ]]; then
            if command -v yay &>/dev/null; then
                yay -S --needed "${sel_aur[@]}"
            else
                echo -e "  ${YELLOW}⚠ yay niedostępny — pomijam z AUR: ${sel_aur[*]}${NC}"
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
    echo -e "  ${GREEN}Wykryto sprzęt ASUS${NC} ($DMI_VENDOR)."
elif [[ -n "$DMI_VENDOR" ]]; then
    echo "  Wykryty producent: $DMI_VENDOR"
fi
echo "  1) ASUS ROG notebook"
echo "  2) HP Omen"
echo "  3) Other"
echo ""
read -rp "  Select your device [default: $HW_DEFAULT]: " hw_choice
hw_choice="${hw_choice:-$HW_DEFAULT}"

# Installs + enables power-profiles-daemon (used by the universal profile switcher)
setup_universal_ppd() {
    echo -e "  Using universal power profiles (power-profiles-daemon)."
    sudo pacman -S --needed power-profiles-daemon
    sudo systemctl enable --now power-profiles-daemon 2>/dev/null
}

# Czy narzędzie ASUS jest gotowe = asusctl zainstalowany I demon asusd żyje.
# Nie testujemy przez `asusctl profile -p` — na nowszych asusctl ta flaga
# zwraca pusto mimo działającego asusd (patrz scripts/waybar/profile-switch.sh).
asusctl_responds() {
    command -v asusctl &>/dev/null && systemctl is-active --quiet asusd 2>/dev/null
}

case "$hw_choice" in
    1)
        HW_PROFILE="asus"
        echo -e "  ${GREEN}✓ ASUS ROG selected.${NC}"
        echo ""
        if command -v yay &>/dev/null; then
            echo -e "  Installing asusctl and rog-control-center..."
            yay -S --needed asusctl rog-control-center
            # asusd musi działać, inaczej przełącznik profili (asusctl profile) nie zadziała
            if systemctl list-unit-files asusd.service &>/dev/null; then
                sudo systemctl enable --now asusd.service
                echo -e "  ${GREEN}✓ asusd enabled.${NC}"
            else
                echo -e "  ${YELLOW}⚠ Brak asusd.service — włącz daemon asusd ręcznie.${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠ yay not available — install asusctl / rog-control-center manually.${NC}"
        fi
        # Domknięcie ścieżki ASUS: gdy asusctl mimo wszystko nie odpowiada
        # (brak yay, nieudana instalacja, asusd nie wstał), profile mają działać
        # od pierwszego startu — stawiamy ppd jako fallback. Skrypty waybara
        # i tak wrócą do asusctl, gdy tylko zacznie odpowiadać.
        if ! asusctl_responds; then
            echo -e "  ${YELLOW}⚠ asusctl nie odpowiada — stawiam power-profiles-daemon jako fallback.${NC}"
            setup_universal_ppd
        fi
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
    echo -e "  ${RED}✗ Przełącznik profili nie działa (profile-get.sh → \"brak\").${NC}"
    echo -e "    ASUS: zainstaluj asusctl i włącz asusd. Inne: systemctl enable --now power-profiles-daemon."
    SUMMARY_SKIPPED+=("Hardware profile: $HW_PROFILE — narzędzie profili NIE odpowiada, pasek pokaże \"brak\"")
else
    SUMMARY_DONE+=("Hardware profile: $HW_PROFILE (aktywny profil: $PROFILE_CHECK)")
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
echo -e "Everything is about to be set up. Would you like to create a backup of your current ~/.config?"
read -rp "[y/N]: " ans

if [[ "$ans" =~ ^[Yy]$ ]]; then
    BACKUP_NAME="backup-$(date +%Y%m%d_%H%M%S)"
    BACKUP_DIR="$ARCHENEMY_DIR/backups/$BACKUP_NAME"
    mkdir -p "$BACKUP_DIR"

    for src in "$RICES_DIR/$DEFAULT_RICE"/*/; do
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
# Pliki per-maszyna (w .gitignore) — hyprland.conf je source'uje, więc każdy
# musi istnieć, nawet pusty, żeby Hyprland nie zgłaszał błędów konfiguracji.

echo -e "${CYAN}[8] Generating machine-local configs...${NC}"
HYPR_LOCAL_DIR="$ARCHENEMY_DIR/config/hypr"
mkdir -p "$HYPR_LOCAL_DIR"

# 8a. Monitory (rozdzielczość/pozycja/skala) — emisja Lua (hl.monitor)
{
    echo "-- generated by archenemy install.sh"
    echo "-- Monitors"
    for mon in "${MONITOR_NAMES[@]}"; do
        res="${MON_RES[$mon]}"
        rate="${MON_RATE[$mon]}"
        pos="${MON_POS[$mon]}"
        scale="${MON_SCALE[$mon]}"

        if [[ -n "$rate" ]]; then
            echo "hl.monitor({ output = \"$mon\", mode = \"${res}@${rate}\", position = \"$pos\", scale = $scale })"
        else
            echo "hl.monitor({ output = \"$mon\", mode = \"$res\", position = \"$pos\", scale = $scale })"
        fi
    done
    # Pusty output = reguła fallback dla monitorów bez własnej reguły.
    echo "hl.monitor({ output = \"\", mode = \"preferred\", position = \"auto\", scale = 1 })"
} > "$MONITOR_CONF"
echo -e "  ${GREEN}✓ monitorshyprl.lua${NC}"

# 8b. Workspace'y wg trybu (shared/decades — data/workspace-mode.dat z [3.7])
# i numeracji monitorów L→P (ORDER z [3.6]).
# Generator wydzielony do biblioteki (jedno źródło prawdy; używa jej też
# scripts/hypr/workspace-mode-switch.sh). Definiuje is_internal_panel()
# i generate_workspaces_monitors().
source "$ARCHENEMY_DIR/scripts/hypr/lib/gen-workspaces.sh"

# Monitory w kolejności ORDER (L→P) — wejście dla generatora.
ORDERED_LR=()
while read -r _ mon; do
    [[ -n "$mon" ]] && ORDERED_LR+=("$mon")
done < <(for mon in "${MONITOR_NAMES[@]}"; do
    echo "${MON_ORDER[$mon]} $mon"
done | sort -n -s -k1,1)

generate_workspaces_monitors "$HYPR_LOCAL_DIR/workspaces-monitors.lua" "$WS_MODE" "${ORDERED_LR[@]}"
echo -e "  ${GREEN}✓ workspaces-monitors.lua (tryb: $WS_MODE, ${#ORDERED_LR[@]} monitors)${NC}"

# 8c. Bindy sprzętowe (klawisze ASUS ROG tylko na ASUS-ach) — emisja Lua
{
    echo "-- generated by archenemy install.sh"
    if [[ "$HW_PROFILE" == "asus" ]]; then
        echo "-- Górne klawisze ASUS ROG"
        echo "hl.bind(\"XF86Launch1\", hl.dsp.exec_cmd(\"rog-control-center\"))"
        echo "hl.bind(\"XF86Launch4\", hl.dsp.exec_cmd(\"asusctl profile -n\"))"
    else
        echo "-- Brak bindów sprzętowych dla tego profilu ($HW_PROFILE)"
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
        echo "-- Karta $GPU_KIND nie wymaga dodatkowych zmiennych"
    fi
} > "$HYPR_LOCAL_DIR/gpu-env.lua"
echo -e "  ${GREEN}✓ gpu-env.lua ($GPU_KIND)${NC}"

# 8e. Autostart osobisty (nie nadpisuj, jeśli użytkownik już ma swój)
AUTOSTART_CONF="$HYPR_LOCAL_DIR/autostartpersonalisation.lua"
if [[ ! -f "$AUTOSTART_CONF" ]]; then
    {
        echo "-- generated by archenemy install.sh"
        echo "-- Osobisty autostart tej maszyny — dopisz swoje aplikacje"
        echo "-- (hl.exec_cmd wewnątrz hl.on(\"hyprland.start\", ...) = dawne exec-once)."
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
    echo -e "  ${GREEN}✓ autostartpersonalisation.lua (nowy)${NC}"
else
    echo -e "  ${YELLOW}⚠ autostartpersonalisation.lua istnieje — nie ruszam.${NC}"
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
    echo -e "  ${GREEN}✓ appbinds.lua (nowy)${NC}"
else
    echo -e "  ${YELLOW}⚠ appbinds.lua istnieje — nie ruszam.${NC}"
fi

# 8g. hyprpaper.conf (warstwa maszynowa — rice'y wskazują na niego symlinkiem;
# bez pliku symlink byłby zepsuty i hyprpaper nie wystartuje; nie nadpisuj,
# bo trzyma aktualny wybór tapet — wypełnia go rofi_wallpaper_switcher.sh)
HYPRPAPER_MACHINE_CONF="$HYPR_LOCAL_DIR/hyprpaper.conf"
if [[ ! -f "$HYPRPAPER_MACHINE_CONF" ]]; then
    {
        echo "# generated by archenemy - do not edit by hand"
        echo "# Tapetę ustawisz przez Super+W (rofi_wallpaper_switcher.sh)."
        # Wyłącz splash hyprpapera (cytat/wersja Hyprlanda rysowana na tapecie).
        echo "splash = false"
    } > "$HYPRPAPER_MACHINE_CONF"
    echo -e "  ${GREEN}✓ hyprpaper.conf (nowy)${NC}"
else
    echo -e "  ${YELLOW}⚠ hyprpaper.conf istnieje — nie ruszam.${NC}"
fi

SUMMARY_DONE+=("Machine-local configs generated (GPU: $GPU_KIND)")
echo ""

# ─── 9. SYMLINKS ──────────────────────────────────────────────────────────────

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

echo -e "${CYAN}[9] Creating symlinks for rice '$TARGET_RICE'...${NC}"

LINK_TS=$(date +%Y%m%d_%H%M%S)
for src in "$RICES_DIR/$TARGET_RICE"/*/; do
    [[ -d "$src" ]] || continue
    name=$(basename "$src")
    dest="$CONFIG_DIR/$name"

    [[ -L "$dest" ]] && rm "$dest"
    [[ -e "$dest" ]] && mv "$dest" "$dest.bak-$LINK_TS"

    ln -s "$src" "$dest"
    echo -e "  ${GREEN}✓ ~/.config/$name → $src${NC}"
done

echo "$TARGET_RICE" > "$CURRENT_RICE"
SUMMARY_DONE+=("Rice '$TARGET_RICE' symlinked into ~/.config")
echo ""

# ─── 9.5 SCRIPTS + INITIAL WALLPAPER ─────────────────────────────────────────

echo -e "${CYAN}[9.5] Finishing touches...${NC}"

# Make all archenemy scripts executable
find "$ARCHENEMY_DIR/scripts" -name "*.sh" -exec chmod +x {} \;
echo -e "  ${GREEN}✓ Scripts made executable.${NC}"

# Screenshots directory (hyprshot output)
mkdir -p "$HOME/Screenshots"

# Ustaw pierwszą tapetę, żeby hyprpaper miał poprawny config od pierwszego startu
WALLPAPER_SWITCHER="$ARCHENEMY_DIR/scripts/rofi/rofi_wallpaper_switcher.sh"
FIRST_WP=$(find "$ARCHENEMY_DIR/wallpapers" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    2>/dev/null | sort | head -n1)
if [[ -n "$FIRST_WP" ]]; then
    bash "$WALLPAPER_SWITCHER" "$FIRST_WP"
    echo -e "  ${GREEN}✓ Initial wallpaper applied.${NC}"
    SUMMARY_DONE+=("Initial wallpaper applied")
else
    echo -e "  ${YELLOW}⚠ No wallpapers found in wallpapers/ — use Super+W after adding some.${NC}"
    SUMMARY_SKIPPED+=("initial wallpaper (none in wallpapers/)")
fi
echo ""

# ─── 10. UFW + SYSTEMD ────────────────────────────────────────────────────────

echo -e "${CYAN}[10] Optional configuration...${NC}"

read -rp "Auto-configure UFW firewall? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    sudo pacman -S --needed ufw
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw enable
    sudo systemctl enable ufw
    echo -e "  ${GREEN}✓ UFW configured.${NC}"
    SUMMARY_DONE+=("UFW configured")
fi

# NetworkManager to twarde wymaganie (moduł sieci waybara, Super+N) — pomijamy
# tylko, gdy już jest włączony.
if systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    echo -e "  ${GREEN}✓ NetworkManager już włączony.${NC}"
else
    echo -e "  ${YELLOW}Uwaga: jeśli używasz iwd/systemd-networkd, NetworkManager przejmie sieć.${NC}"
    read -rp "Enable NetworkManager (wymagany przez moduł sieci)? [Y/n]: " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        sudo systemctl enable --now NetworkManager
        SUMMARY_DONE+=("NetworkManager enabled")
    else
        SUMMARY_SKIPPED+=("NetworkManager (moduł sieci i Super+N nie zadziałają)")
    fi
fi

# Bluetooth jest opcjonalny — bluez instalujemy PRZED enable, żeby nie było
# błędu o nieistniejącym bluetooth.service.
read -rp "Set up bluetooth (installs bluez)? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    sudo pacman -S --needed bluez bluez-utils
    sudo systemctl enable --now bluetooth
    echo -e "  ${GREEN}✓ Bluetooth enabled.${NC}"
    SUMMARY_DONE+=("Bluetooth enabled")
fi

# Audio: pavucontrol i moduł głośności waybara mówią po PulseAudio — serwer
# dostarcza pipewire-pulse (socket użytkownika, na Archu włączany presetem).
if systemctl --user is-active --quiet pipewire-pulse.socket \
   || systemctl --user is-active --quiet pipewire-pulse.service; then
    echo -e "  ${GREEN}✓ Audio (pipewire-pulse) już działa.${NC}"
elif systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service &>/dev/null; then
    echo -e "  ${GREEN}✓ pipewire-pulse uruchomiony.${NC}"
    SUMMARY_DONE+=("Audio: pipewire-pulse started")
else
    echo -e "  ${YELLOW}⚠ Nie udało się uruchomić pipewire-pulse — wyloguj i zaloguj się ponownie.${NC}"
    SUMMARY_SKIPPED+=("audio: pipewire-pulse (wymagany re-login)")
fi

echo ""

# ─── 11. DONE ─────────────────────────────────────────────────────────────────

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
    hyprctl reload
    echo -e "${GREEN}✓ Hyprland reloaded.${NC}"
fi
