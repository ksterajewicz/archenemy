#!/bin/bash

# =============================================
#   archenemy - update-archenemy.sh
#   Aktualizator repo z TUI (Super+A → [p]). Pozwala wybrać gałąź (dev/main)
#   i pociągnąć najnowsze zmiany bez utraty personalizacji.
#
#   Warstwy MASZYNOWA i OSOBISTA (monitory, appbinds.lua, autostart, itd.)
#   są poza gitem (.gitignore) — zwykły `git pull` ich nie rusza, więc
#   przetrwają zawsze. Jedyne co może kolidować, to LOKALNE zmiany w
#   plikach śledzonych przez git (np. ręcznie poprawiony rice) — te
#   są chowane przez `git stash` przed pull i przywracane po nim, więc
#   też nie giną.
# =============================================

ARCHENEMY_DIR="$HOME/archenemy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Jeden klawisz bez Enter — spójne z appbinds.sh (Escape = anuluj).
read_key() {
    local prompt="$1" key=""
    IFS= read -rsn1 -p "$prompt" key
    echo "" >&2
    printf '%s' "$key"
}

echo -e "${BLUE}"
echo "  ┌─────────────────────────────────────┐"
echo "  │      archenemy · update             │"
echo "  └─────────────────────────────────────┘"
echo -e "${NC}"

if [[ ! -d "$ARCHENEMY_DIR/.git" ]]; then
    echo -e "  ${RED}✗ ${ARCHENEMY_DIR} nie jest repozytorium git — nie mogę aktualizować.${NC}"
    read -rp "  Enter, aby wrócić..." _
    exit 0
fi

cur_branch="$(git -C "$ARCHENEMY_DIR" branch --show-current 2>/dev/null)"
[[ -z "$cur_branch" ]] && cur_branch="(odpięty HEAD)"

echo -e "  Obecna gałąź: ${CYAN}${cur_branch}${NC}"
echo -e "    ${BLUE}1${NC}) dev  — najnowsze zmiany, mogą być niestabilne"
echo -e "    ${BLUE}2${NC}) main — tylko stabilne wydania"
echo ""
ans="$(read_key "  Aktualizuj z [1-2, Esc = anuluj]: ")"
target=""
case "$ans" in
    1) target="dev" ;;
    2) target="main" ;;
    ""|$'\e') echo -e "  ${YELLOW}Anulowano.${NC}"; read -rp "  Enter, aby wrócić..." _; exit 0 ;;
    *)  echo -e "  ${RED}✗ Wybierz 1 albo 2.${NC}"; read -rp "  Enter, aby wrócić..." _; exit 0 ;;
esac

echo ""
echo -e "  ${CYAN}→ Pobieram zmiany z origin/${target}...${NC}"
if ! git -C "$ARCHENEMY_DIR" fetch origin "$target" 2>&1 | sed 's/^/    /'; then
    echo -e "  ${RED}✗ Fetch nie powiódł się — sprawdź sieć / klucz SSH.${NC}"
    read -rp "  Enter, aby wrócić..." _
    exit 0
fi

# Lokalne zmiany w plikach śledzonych przez git → schowaj (git stash), żeby
# pull ich nie zgubił ani nie odmówił z powodu konfliktu. --untracked-files=no,
# bo pliki nieśledzone (warstwa maszynowa/osobista) i tak nie kolidują z pull.
stashed=0
if [[ -n "$(git -C "$ARCHENEMY_DIR" status --porcelain --untracked-files=no)" ]]; then
    echo -e "  ${YELLOW}⚠ Masz lokalne zmiany w plikach śledzonych przez git.${NC}"
    sans="$(read_key "  Schować je i przywrócić po aktualizacji? [Y/n]: ")"
    if [[ "$sans" =~ ^[Nn]$ ]]; then
        echo -e "  ${RED}✗ Anulowano — najpierw scommituj albo odrzuć zmiany.${NC}"
        read -rp "  Enter, aby wrócić..." _
        exit 0
    fi
    if git -C "$ARCHENEMY_DIR" stash push -u -m "update-archenemy.sh $(date +%FT%T)" >/dev/null; then
        stashed=1
        echo -e "  ${GREEN}✓ Lokalne zmiany schowane.${NC}"
    else
        echo -e "  ${RED}✗ Schowanie (stash) nie powiodło się — przerywam.${NC}"
        read -rp "  Enter, aby wrócić..." _
        exit 0
    fi
fi

echo -e "  ${CYAN}→ Przełączam na ${target}...${NC}"
if ! git -C "$ARCHENEMY_DIR" checkout "$target" 2>&1 | sed 's/^/    /'; then
    echo -e "  ${RED}✗ Checkout nie powiódł się.${NC}"
    [[ $stashed -eq 1 ]] && git -C "$ARCHENEMY_DIR" stash pop
    read -rp "  Enter, aby wrócić..." _
    exit 0
fi

echo -e "  ${CYAN}→ Ściągam najnowsze ${target}...${NC}"
if ! git -C "$ARCHENEMY_DIR" pull --ff-only origin "$target" 2>&1 | sed 's/^/    /'; then
    echo -e "  ${RED}✗ Pull nie powiódł się (brak fast-forward?). Rozwiąż ręcznie przez git.${NC}"
    if [[ $stashed -eq 1 ]]; then
        echo -e "  ${YELLOW}Przywracam Twoje schowane zmiany...${NC}"
        git -C "$ARCHENEMY_DIR" stash pop
    fi
    read -rp "  Enter, aby wrócić..." _
    exit 0
fi

if [[ $stashed -eq 1 ]]; then
    echo -e "  ${CYAN}→ Przywracam Twoje lokalne zmiany...${NC}"
    if git -C "$ARCHENEMY_DIR" stash pop 2>&1 | sed 's/^/    /'; then
        echo -e "  ${GREEN}✓ Lokalne zmiany przywrócone.${NC}"
    else
        echo -e "  ${RED}✗ Nie udało się przywrócić automatycznie — rozwiąż konflikt ręcznie (git stash list).${NC}"
    fi
fi

echo -e "  ${GREEN}✓ Zaktualizowano do najnowszego ${target}.${NC}"
echo ""
echo -e "  Twoje ustawienia (bindy, autostart, rice, monitory, wolumin...) są poza"
echo -e "  gitem — ${GREEN}zostają bez zmian${NC}."
echo ""
rerun="$(read_key "  Uruchomić teraz install.sh, żeby dogenerować pliki maszynowe? [Y/n]: ")"
if [[ ! "$rerun" =~ ^[Nn]$ ]]; then
    if [[ -x "$ARCHENEMY_DIR/install/install.sh" ]]; then
        bash "$ARCHENEMY_DIR/install/install.sh"
    else
        echo -e "  ${RED}✗ Nie znaleziono install/install.sh albo brak praw wykonywania.${NC}"
        read -rp "  Enter, aby wrócić..." _
    fi
fi
