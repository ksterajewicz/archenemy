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

# shellcheck source=lib/tui.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tui.sh"

pause() { read -rp "  Press Enter to go back..." _; }

clear
tui_header "update archenemy"

if [[ ! -d "$ARCHENEMY_DIR/.git" ]]; then
    echo -e "  ${RED}✗ ${ARCHENEMY_DIR} is not a git repository — cannot update.${NC}"
    pause
    exit 0
fi

cur_branch="$(git -C "$ARCHENEMY_DIR" branch --show-current 2>/dev/null)"
[[ -z "$cur_branch" ]] && cur_branch="(detached HEAD)"

echo -e "  Current branch: ${CYAN}${cur_branch}${NC}"
echo -e "    ${BLUE}1${NC}) dev  — latest changes, may be unstable"
echo -e "    ${BLUE}2${NC}) main — stable releases only"
echo ""
ans="$(read_key "  Update from [1-2, Esc = cancel]: ")"
target=""
case "$ans" in
    1) target="dev" ;;
    2) target="main" ;;
    ""|$'\e') echo -e "  ${YELLOW}Cancelled.${NC}"; pause; exit 0 ;;
    *)  echo -e "  ${RED}✗ Pick 1 or 2.${NC}"; pause; exit 0 ;;
esac

echo ""
echo -e "  ${CYAN}→ Fetching origin/${target}...${NC}"
if ! git -C "$ARCHENEMY_DIR" fetch origin "$target" 2>&1 | sed 's/^/    /'; then
    echo -e "  ${RED}✗ Fetch failed — check the network / SSH key.${NC}"
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
    echo -e "  ${YELLOW}⚠ Branch ${target} is older than what you have: ${missing:-?} of your commits are not in origin/${target}.${NC}"
    echo -e "  ${YELLOW}  Switching takes your configuration back to ${target} (rices and scripts missing there will disappear).${NC}"
    if ! confirm "Switch to ${target} anyway?" N; then
        echo -e "  ${YELLOW}Staying on ${cur_branch}.${NC}"
        pause
        exit 0
    fi
fi

# Lokalne zmiany w plikach śledzonych przez git → schowaj (git stash), żeby
# pull ich nie zgubił ani nie odmówił z powodu konfliktu. --untracked-files=no,
# bo pliki nieśledzone (warstwa maszynowa/osobista) i tak nie kolidują z pull.
# Stash też BEZ -u (spójnie z tym sprawdzeniem): -u zdejmowało z dysku pliki
# nieśledzone (np. własne tapety w wallpapers/) na czas aktualizacji, a gdy
# pop nie przeszedł, wracały tylko do schowka (audyt 2026-09-25).
stashed=0
if [[ -n "$(git -C "$ARCHENEMY_DIR" status --porcelain --untracked-files=no)" ]]; then
    echo -e "  ${YELLOW}⚠ You have local changes in tracked files.${NC}"
    if ! confirm "Stash them and restore after the update?" Y; then
        echo -e "  ${RED}✗ Cancelled — commit or discard your changes first.${NC}"
        pause
        exit 0
    fi
    if git -C "$ARCHENEMY_DIR" stash push -m "update-archenemy.sh $(date +%FT%T)" >/dev/null; then
        stashed=1
        echo -e "  ${GREEN}✓ Local changes stashed.${NC}"
    else
        echo -e "  ${RED}✗ Stash failed — stopping.${NC}"
        pause
        exit 0
    fi
fi

# Przywrócenie schowka z RZETELNYM wynikiem: przy konflikcie git zostawia
# wpis w `git stash list`, więc zmiany nie giną — mówimy, gdzie są.
restore_stash() {
    [[ $stashed -eq 1 ]] || return 0
    echo -e "  ${CYAN}→ Restoring your local changes...${NC}"
    if git -C "$ARCHENEMY_DIR" stash pop 2>&1 | sed 's/^/    /'; then
        echo -e "  ${GREEN}✓ Local changes restored.${NC}"
    else
        echo -e "  ${RED}✗ Could not restore automatically — your changes are in the stash (git stash list); resolve the conflict and run git stash pop.${NC}"
    fi
}

echo -e "  ${CYAN}→ Switching to ${target}...${NC}"
if ! git -C "$ARCHENEMY_DIR" checkout "$target" 2>&1 | sed 's/^/    /'; then
    echo -e "  ${RED}✗ Checkout failed.${NC}"
    restore_stash
    pause
    exit 0
fi

echo -e "  ${CYAN}→ Pulling ${target}...${NC}"
if ! git -C "$ARCHENEMY_DIR" pull --ff-only origin "$target" 2>&1 | sed 's/^/    /'; then
    echo -e "  ${RED}✗ Pull failed (no fast-forward?). Resolve it manually with git.${NC}"
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
    echo -e "  ${GREEN}✓ Updated to the latest ${target}.${NC}"
elif git -C "$ARCHENEMY_DIR" merge-base --is-ancestor "origin/$target" HEAD 2>/dev/null; then
    ahead="$(git -C "$ARCHENEMY_DIR" rev-list --count "origin/$target..HEAD" 2>/dev/null)"
    echo -e "  ${YELLOW}⚠ You have ${ahead} local commits on top of origin/${target} — the code differs from the repository.${NC}"
else
    echo -e "  ${RED}✗ After the update HEAD does not match origin/${target} — check: git -C ~/archenemy status${NC}"
    pause
    exit 0
fi
echo ""
echo -e "  Your settings (binds, autostart, rice, monitors, volume...) are outside"
echo -e "  git — ${GREEN}they stay unchanged${NC}."
echo ""
if confirm "Run install.sh now to regenerate machine files?" Y; then
    # -f, nie -x: uruchamiamy przez `bash`, bit wykonywania nie jest potrzebny
    # (brak bitu w indeksie gita blokował tu instalację — audyt 2026-09-23).
    if [[ -f "$ARCHENEMY_DIR/install/install.sh" ]]; then
        bash "$ARCHENEMY_DIR/install/install.sh"
    else
        echo -e "  ${RED}✗ install/install.sh not found.${NC}"
    fi
fi
# Bez pauzy menu główne wyczyściłoby ekran razem z wynikiem aktualizacji.
pause
