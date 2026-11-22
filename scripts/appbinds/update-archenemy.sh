#!/usr/bin/env bash

# =============================================
#   archenemy - update-archenemy.sh
#   Aktualizator repo z TUI (Super+A → [u]). Pozwala wybrać gałąź (dev/main)
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
# shellcheck source=../waybar/lib/waybar-reload.sh
source "$(dirname "${BASH_SOURCE[0]}")/../waybar/lib/waybar-reload.sh"

pause() { read -rp "  Press Enter to go back..." _; }

# Platforma (D8): ta sama pkg_route co instalator — od niej zależy, co
# obiecujemy o install.sh. Arch i pochodne: dotychczasowe teksty i zakres
# ostrzeżenia (install/, packages/); NixOS dokłada nix/ (deklaracje pakietów).
UPD_ROUTE=""
# shellcheck source=../../install/lib/pkg.sh
if [[ -r "$(dirname "${BASH_SOURCE[0]}")/../../install/lib/pkg.sh" ]] \
        && source "$(dirname "${BASH_SOURCE[0]}")/../../install/lib/pkg.sh" && pkg_route 2>/dev/null; then
    UPD_ROUTE="$PKG_ROUTE"
fi
RISKY_PATHS=(install/ packages/)
[[ "$UPD_ROUTE" == nixos ]] && RISKY_PATHS+=(nix/)

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
if ! tui_menu 0 "dev — latest changes, may be unstable" "main — stable releases only"; then
    echo -e "  ${YELLOW}Cancelled.${NC}"; pause; exit 0
fi
if (( TUI_MENU_INDEX == 0 )); then target=dev; else target=main; fi

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

# Co przyjdzie z pull — pokazujemy PRZED czymkolwiek, co zmienia drzewo
# (K5, audyt bezpieczeństwa 2026-11-14: „nie wiem, co uruchamiam”). Lista
# nowych commitów (limit 30) i osobne ostrzeżenie, gdy zmienia się kod
# instalatora albo listy pakietów — to one pójdą potem przez sudo/yay.
# Krótki HEAD sprzed aktualizacji = droga powrotu wypisywana na końcu.
old_head="$(git -C "$ARCHENEMY_DIR" rev-parse --short=7 HEAD 2>/dev/null)"
risky=""
new_count="$(git -C "$ARCHENEMY_DIR" rev-list --count "HEAD..origin/$target" 2>/dev/null)"
if [[ "${new_count:-0}" -eq 0 ]]; then
    echo -e "  No new commits on origin/${target}."
else
    echo -e "  New commits on origin/${target} (${new_count}):"
    new_log="$(git -C "$ARCHENEMY_DIR" log --oneline --no-decorate -n 30 "HEAD..origin/$target" 2>/dev/null)"
    sed 's/^/    /' <<< "$new_log"
    (( new_count > 30 )) && echo "    … and $((new_count - 30)) more"
    risky="$(git -C "$ARCHENEMY_DIR" diff --name-only "HEAD...origin/$target" -- "${RISKY_PATHS[@]}" 2>/dev/null)"
    if [[ -n "$risky" ]]; then
        echo -e "  ${YELLOW}⚠ This update changes the installer or package lists — review before running install.sh:${NC}"
        head -n 20 <<< "$risky" | sed 's/^/    /'
    fi
fi
echo ""

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
# Kod 1 = konflikt: drzewo ma znaczniki konfliktu, więc wołający nie melduje
# „✓” i nie proponuje install.sh (audyt bezpieczeństwa 2026-11-14, K3).
# Rada zależy od stanu (A7, przegląd 2026-11-15): po konflikcie zmiany SĄ
# już w drzewie (ze znacznikami), a wpis w schowku to kopia — kolejny
# `git stash pop` daje „needs merge”, a po `git add` nakłada schowek drugi
# raz; działa: rozwiąż, `git add`, `git stash drop` (man git-stash). Gdy pop
# padł bez konfliktu, nic nie weszło do drzewa — wtedy `drop` zgubiłby
# zmiany, więc radzimy samo `git stash pop` po usunięciu przyczyny.
restore_stash() {
    [[ $stashed -eq 1 ]] || return 0
    echo -e "  ${CYAN}→ Restoring your local changes...${NC}"
    if git -C "$ARCHENEMY_DIR" stash pop 2>&1 | sed 's/^/    /'; then
        echo -e "  ${GREEN}✓ Local changes restored.${NC}"
        return 0
    fi
    local conflicted
    conflicted="$(git -C "$ARCHENEMY_DIR" diff --name-only --diff-filter=U 2>/dev/null)"
    if [[ -n "$conflicted" ]]; then
        echo -e "  ${RED}✗ Could not restore automatically — conflict in:${NC}"
        head -n 10 <<< "$conflicted" | sed 's/^/    /'
        echo -e "  ${RED}  A copy of your changes stays in the stash (git stash list). To finish, in ~/archenemy:${NC}"
        echo -e "  ${RED}  fix the conflict markers, git add those files, then git stash drop (not git stash pop).${NC}"
    else
        echo -e "  ${RED}✗ Could not restore automatically — your changes are still in the stash (git stash list).${NC}"
        echo -e "  ${RED}  Fix the error above, then run git stash pop in ~/archenemy.${NC}"
    fi
    return 1
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

if ! restore_stash; then
    echo -e "  ${YELLOW}⚠ The code is at origin/${target}, but the update is not finished: bring your local changes back first (see above).${NC}"
    echo -e "  ${YELLOW}  Afterwards start the installer yourself: bash ~/archenemy/install/install.sh${NC}"
    pause
    exit 0
fi

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
if [[ -n "$old_head" && "$(git -C "$ARCHENEMY_DIR" rev-parse --short=7 HEAD 2>/dev/null)" != "$old_head" ]]; then
    echo -e "  To go back: git switch --detach ${old_head}   (run in ~/archenemy)"
fi
# Pasek: działający waybar nie czyta configu ponownie (lib/waybar-reload.sh),
# więc po pullu, który zmienił config rice'a albo skrypty modułów
# (scripts/waybar — moduły z samym "signal" uruchamiają je raz), przeładuj go
# od razu (SIGUSR2). Bez tego nowy moduł albo sygnał nie istnieje aż do
# restartu waybara — u właściciela: do restartu sprzętu (2026-11-19).
if pgrep -x waybar >/dev/null 2>&1; then
    bar_scripts=""
    [[ -n "$old_head" ]] && bar_scripts="$(git -C "$ARCHENEMY_DIR" diff --name-only "$old_head" HEAD -- scripts/waybar 2>/dev/null)"
    if waybar_config_stale || [[ -n "$bar_scripts" ]]; then
        if waybar_reload; then
            echo -e "  ${GREEN}✓ Waybar reloaded — the bar uses the updated config.${NC}"
        else
            echo -e "  ${YELLOW}⚠ Waybar did not take the reload signal — the bar keeps the old config until waybar restarts (Super+T or log in again).${NC}"
        fi
    fi
fi
# Logo fastfetcha idzie za „system logo”: plik w warstwie maszynowej bywa
# nieaktualny po pullu (nowy znak) albo nie istnieje u kogoś, kto wybrał logo
# przed 2026-11-22. Cicho, bez sudo; porażka nie zatrzymuje aktualizacji.
if [[ -f "$ARCHENEMY_DIR/scripts/waybar/launcher-logo.sh" ]]; then
    bash "$ARCHENEMY_DIR/scripts/waybar/launcher-logo.sh" sync 2>/dev/null || true
fi
echo ""
echo -e "  Your settings (binds, autostart, rice, monitors, volume...) are outside"
echo -e "  git — ${GREEN}they stay unchanged${NC}."
echo ""
# Podsumowanie TUŻ nad pytaniem o instalator (A3, przegląd 2026-11-15): lista
# i ⚠ z K5 stoją przed pull, więc wyjście pulla przewija je poza okno Super+A
# (ok. 27 wierszy). Liczone po pull z <old_head>..HEAD, czyli to, co naprawdę
# weszło (przy dev → main: cofnięte commity). ⚠ powtarza listę sprzed pull —
# ten sam zakres install/ packages/, bez nowego liczenia.
plural() { if [[ "$1" == 1 ]]; then echo "1 $2"; else echo "$1 $2s"; fi; }
if [[ -n "$old_head" && "$(git -C "$ARCHENEMY_DIR" rev-parse --short=7 HEAD 2>/dev/null)" != "$old_head" ]]; then
    added="$(git -C "$ARCHENEMY_DIR" rev-list --count "$old_head..HEAD" 2>/dev/null)"
    removed="$(git -C "$ARCHENEMY_DIR" rev-list --count "HEAD..$old_head" 2>/dev/null)"
    stat="$(git -C "$ARCHENEMY_DIR" diff --shortstat "$old_head" HEAD 2>/dev/null)"
    stat="${stat# }"
    summary=""
    [[ "${added:-0}" -gt 0 ]] && summary+="$(plural "$added" "new commit"), "
    [[ "${removed:-0}" -gt 0 ]] && summary+="$(plural "$removed" commit) rolled back, "
    echo -e "  This update: ${summary}${stat:-no file changes}."
    if [[ -n "$risky" ]]; then
        if [[ "$UPD_ROUTE" == nixos ]]; then
            echo -e "  ${YELLOW}⚠ install/, packages/ or nix/ changed ($(plural "$(grep -c . <<< "$risky")" file)) — review before running install.sh or rebuilding:${NC}"
            echo -e "    git -C ~/archenemy diff ${old_head} HEAD -- install packages nix"
        else
            echo -e "  ${YELLOW}⚠ install/ or packages/ changed ($(plural "$(grep -c . <<< "$risky")" file)) — review before running install.sh:${NC}"
            echo -e "    git -C ~/archenemy diff ${old_head} HEAD -- install packages"
        fi
    fi
    # Motywy ekranu logowania i menu startu to KOPIE w systemie (pliki roota):
    # po pullu, który zmienił ich źródła, zostają stare aż do ponownego biegu
    # pomocnika. Tylko gdy motywy są zainstalowane (ustawienia roota istnieją).
    theme_sysroot=""
    [[ "${ARCHENEMY_TEST:-}" == 1 ]] && theme_sysroot="${ARCHENEMY_SYSROOT:-}"
    if [[ -f "$theme_sysroot/etc/archenemy/system-theme.conf" ]] \
        && [[ -n "$(git -C "$ARCHENEMY_DIR" diff --name-only "$old_head" HEAD -- src/system-theme 'rices/*/system-theme.conf' install/system-theme-installation.sh 2>/dev/null)" ]]; then
        echo -e "  ${YELLOW}⚠ Login screen / boot menu themes changed — the copies in the system are older. Refresh them:${NC}"
        echo -e "    bash ~/archenemy/install/system-theme-installation.sh"
    fi
fi
# Domyślnie NIE (K4, audyt bezpieczeństwa 2026-11-14): instalator pochodzi
# z kodu pobranego przed chwilą i woła sudo — jeden Enter nie może go
# uruchomić. Przypomnienie o zaległym biegu daje machine-layer-check.sh.
# Zgoda na aktualizację ≠ zgoda na instalator ani na dodatkowe repozytoria:
# tekst mówi, co instalator zrobi na tej platformie; dodatkowe źródła Fedory
# (COPR, Brave) i tak pytają osobno w install.sh.
case "$UPD_ROUTE" in
    arch)   install_q="Run install.sh now to regenerate machine files? It will ask for sudo." ;;
    fedora) install_q="Run install.sh now to regenerate machine files? It will ask for sudo (dnf); extra repositories are asked about separately." ;;
    nixos)  install_q="Run install.sh now to regenerate machine files? On NixOS it installs nothing and does not use sudo; packages go into your configuration." ;;
    *)      install_q="" ;;
esac
if [[ -z "$install_q" ]]; then
    echo -e "  ${YELLOW}install.sh supports Arch Linux, Fedora and NixOS only — it would refuse this distribution, so it is not offered here.${NC}"
elif confirm "$install_q" N; then
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
