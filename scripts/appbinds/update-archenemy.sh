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
#
#   Każdy krok gita idzie przez `| sed` (wcięcie wyjścia), więc bez
#   pipefail `if !` sprawdzałby kod seda, nie gita — nieudany fetch/pull/
#   stash pop kończył się „✓” (audyt 2026-09-23, tests/update-archenemy.sh).
# =============================================

set -o pipefail

ARCHENEMY_DIR="$HOME/archenemy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

pause() { read -rp "  Enter, aby wrócić..." _; }

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
    ""|$'\e') echo -e "  ${YELLOW}Anulowano.${NC}"; pause; exit 0 ;;
    *)  echo -e "  ${RED}✗ Wybierz 1 albo 2.${NC}"; pause; exit 0 ;;
esac

echo ""
echo -e "  ${CYAN}→ Pobieram zmiany z origin/${target}...${NC}"
if ! git -C "$ARCHENEMY_DIR" fetch origin "$target" 2>&1 | sed 's/^/    /'; then
    echo -e "  ${RED}✗ Fetch nie powiódł się — sprawdź sieć / klucz SSH.${NC}"
    pause
    exit 0
fi

# Przełączenie na gałąź, która NIE zawiera obecnego stanu (np. main dziesiątki
# commitów za dev, sprzed migracji configu na Lua), cofa configi — wybór
# zostaje (właściciel testuje main na żywym sprzęcie, decyzja 2026-09-23),
# ale tylko po jawnym potwierdzeniu, domyślnie NIE. Po cofnięciu instalator
# (pytanie na końcu) przelinkowuje rice z tamtej wersji. Ta sama gałąź idzie
# dalej bez pytania: rozjazd historii i tak zatrzyma pull --ff-only.
if [[ "$target" != "$cur_branch" ]] \
   && ! git -C "$ARCHENEMY_DIR" merge-base --is-ancestor HEAD "origin/$target" 2>/dev/null; then
    missing="$(git -C "$ARCHENEMY_DIR" rev-list --count "origin/$target..HEAD" 2>/dev/null)"
    echo -e "  ${YELLOW}⚠ Gałąź ${target} jest starsza niż to, co masz teraz: ${missing:-?} commitów Twojego obecnego stanu na niej nie ma.${NC}"
    echo -e "  ${YELLOW}  Przełączenie cofnie konfigurację do wersji z ${target} (rice'y i skrypty, których tam nie ma, znikną z ~/.config).${NC}"
    back="$(read_key "  Mimo to przełączyć na ${target}? [y/N]: ")"
    if [[ ! "$back" =~ ^[Yy]$ ]]; then
        echo -e "  ${YELLOW}Zostaję na ${cur_branch}.${NC}"
        pause
        exit 0
    fi
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
        pause
        exit 0
    fi
    if git -C "$ARCHENEMY_DIR" stash push -u -m "update-archenemy.sh $(date +%FT%T)" >/dev/null; then
        stashed=1
        echo -e "  ${GREEN}✓ Lokalne zmiany schowane.${NC}"
    else
        echo -e "  ${RED}✗ Schowanie (stash) nie powiodło się — przerywam.${NC}"
        pause
        exit 0
    fi
fi

# Przywrócenie schowka z RZETELNYM wynikiem: przy konflikcie git zostawia
# wpis w `git stash list`, więc zmiany nie giną — mówimy, gdzie są.
restore_stash() {
    [[ $stashed -eq 1 ]] || return 0
    echo -e "  ${CYAN}→ Przywracam Twoje lokalne zmiany...${NC}"
    if git -C "$ARCHENEMY_DIR" stash pop 2>&1 | sed 's/^/    /'; then
        echo -e "  ${GREEN}✓ Lokalne zmiany przywrócone.${NC}"
    else
        echo -e "  ${RED}✗ Nie udało się przywrócić automatycznie — zmiany leżą w schowku (git stash list); rozwiąż konflikt ręcznie.${NC}"
    fi
}

echo -e "  ${CYAN}→ Przełączam na ${target}...${NC}"
if ! git -C "$ARCHENEMY_DIR" checkout "$target" 2>&1 | sed 's/^/    /'; then
    echo -e "  ${RED}✗ Checkout nie powiódł się.${NC}"
    restore_stash
    pause
    exit 0
fi

echo -e "  ${CYAN}→ Ściągam najnowsze ${target}...${NC}"
if ! git -C "$ARCHENEMY_DIR" pull --ff-only origin "$target" 2>&1 | sed 's/^/    /'; then
    echo -e "  ${RED}✗ Pull nie powiódł się (brak fast-forward?). Rozwiąż ręcznie przez git.${NC}"
    restore_stash
    pause
    exit 0
fi

restore_stash

# Sukces = zaobserwowany stan, nie kod wyjścia: HEAD musi równać się
# origin/<gałąź>. Lokalne commity ponad origin (pull --ff-only mówi wtedy
# „Already up to date”) to nie błąd, ale kod ≠ repozytorium — mówimy o tym.
head_now="$(git -C "$ARCHENEMY_DIR" rev-parse HEAD 2>/dev/null)"
head_remote="$(git -C "$ARCHENEMY_DIR" rev-parse "origin/$target" 2>/dev/null)"
if [[ -n "$head_now" && "$head_now" == "$head_remote" ]]; then
    echo -e "  ${GREEN}✓ Zaktualizowano do najnowszego ${target}.${NC}"
elif git -C "$ARCHENEMY_DIR" merge-base --is-ancestor "origin/$target" HEAD 2>/dev/null; then
    ahead="$(git -C "$ARCHENEMY_DIR" rev-list --count "origin/$target..HEAD" 2>/dev/null)"
    echo -e "  ${YELLOW}⚠ Masz ${ahead} lokalnych commitów ponad origin/${target} — kod różni się od repozytorium.${NC}"
else
    echo -e "  ${RED}✗ Po aktualizacji HEAD nie zgadza się z origin/${target} — sprawdź: git -C ~/archenemy status${NC}"
    pause
    exit 0
fi
echo ""
echo -e "  Twoje ustawienia (bindy, autostart, rice, monitory, wolumin...) są poza"
echo -e "  gitem — ${GREEN}zostają bez zmian${NC}."
echo ""
rerun="$(read_key "  Uruchomić teraz install.sh, żeby dogenerować pliki maszynowe? [Y/n]: ")"
if [[ ! "$rerun" =~ ^[Nn]$ ]]; then
    # -f, nie -x: uruchamiamy przez `bash`, bit wykonywania nie jest potrzebny
    # (brak bitu w indeksie gita blokował tu instalację — audyt 2026-09-23).
    if [[ -f "$ARCHENEMY_DIR/install/install.sh" ]]; then
        bash "$ARCHENEMY_DIR/install/install.sh"
    else
        echo -e "  ${RED}✗ Nie znaleziono install/install.sh.${NC}"
        pause
    fi
fi
