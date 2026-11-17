#!/usr/bin/env bash
# =============================================
#   archenemy - tests/platform-map.sh
#   Spójność mapy pakietów packages/platform-map.tsv (D3, Fedora i NixOS
#   w wariancie A, decyzje właściciela 2026-11-17) z listami Archa:
#     - format: dokładnie 10 pól rozdzielonych tabulatorem, żadne nie jest
#       puste („-” zamiast pustego — `read` z IFS=tab skleja puste pola),
#       unikalne id, dozwolone źródła i statusy, URL https;
#     - KAŻDY wpis czterech list packages/*.txt i kolumny „pacman package”
#       z config/shell/cli-tools.tsv ma wiersz (id = arch_name = nazwa,
#       arch_source zgodne z listą) — nowy pakiet w liście bez wiersza = ✗;
#     - każda dosłowna nazwa z instalacji doraźnych (`pacman -S --needed …`,
#       tablice PKGS w install/*.sh i scripts/**/*.sh) ma wiersz, a wiersz
#       spoza list ma ślad w kodzie (żadnych martwych wierszy);
#     - żadnych zamienników -git; COPR tylko nett00n/hyprland (jedyny
#       zatwierdzony); status ok ⇒ są nazwy i źródło; źródło spoza
#       repozytoriów Fedory ma własny URL zamiast mdapi;
#     - test negatywny: kopia repo z dopisanym pakietem w liście bez
#       wiersza mapy musi dać ✗.
#   Mapa to dane: test czyta ją zwykłym `read`, nigdy eval/source.
#   Bez sieci, bez roota.
#   Uruchom: bash tests/platform-map.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

# list_names <plik> — nazwy pakietów z listy (jak install.sh [5]: pierwsze
# słowo wiersza, bez pustych i komentarzy).
list_names() {
    local pkg
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
        pkg="${pkg%%[[:space:]]*}"
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        printf '%s\n' "$pkg"
    done < "$1"
}

# adhoc_names <repo> — dosłowne nazwy pakietów z instalacji doraźnych:
# słowa po `pacman -S --needed` oraz elementy tablic PKGS/LIB32_PKGS
# i przypisań UCODE=/KERNEL= w install/*.sh i scripts/*.sh (git: * obejmuje podkatalogi). Słowa ze
# zmienną, cudzysłowem albo operatorem powłoki są pomijane (to nie nazwy).
adhoc_names() {
    local line rest w
    while IFS= read -r line; do
        line="${line#*:}"; line="${line#*:}"   # plik:linia:
        rest=""
        if [[ "$line" =~ pacman\ -S\ --needed\ (.*)$ ]]; then
            rest="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ (^|[^A-Za-z_])(LIB32_)?PKGS\+?=\((.*)\) ]]; then
            rest="${BASH_REMATCH[3]}"
        elif [[ "$line" =~ (UCODE|KERNEL)=\"([a-z0-9-]+)\" ]]; then
            rest="${BASH_REMATCH[2]}"
        fi
        # Koniec polecenia: ; | & ) (np. „--needed hyprland; then”, „zsh)?”).
        rest="${rest%%[;|&)]*}"
        for w in $rest; do
            case "$w" in
                *'$'*|*'"'*|*"'"*|*\\*|*'<'*|*'>'*|-*) continue ;;
            esac
            [[ "$w" =~ ^[a-z0-9][a-z0-9+._-]*$ ]] && printf '%s\n' "$w"
        done
    done < <(git -C "$1" grep -nE 'pacman -S --needed |PKGS\+?=\(|(UCODE|KERNEL)="' -- 'install/*.sh' 'scripts/*.sh')
}

# check_map <repo> — wszystkie reguły; wypisuje ✓/✗ i zwraca liczbę porażek.
check_map() {
    local R="$1" MAP="$1/packages/platform-map.tsv" n=0 bad=0
    local line tabs id an asrc fn fsrc na ck mv stt url extra fs ns
    local -A ROW=() SRC=() LISTED=()
    local before=$FAIL

    [[ -f "$MAP" ]] || { fail "brak $MAP"; return 1; }

    # ── format ──
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        n=$((n + 1))
        tabs="${line//[^$'\t']/}"
        if [[ ${#tabs} -ne 9 ]]; then
            fail "wiersz $n: ${#tabs} tabulatorów zamiast 9: ${line:0:60}"; bad=1; continue
        fi
        IFS=$'\t' read -r id an asrc fn fsrc na ck mv stt url extra <<< "$line"
        if [[ -z "$url" || -n "$extra" ]]; then
            fail "wiersz $n ($id): puste pole (wpisz -)"; bad=1; continue
        fi
        if [[ -n "${ROW[$id]:-}" ]]; then fail "powtórzony id: $id"; bad=1; fi
        ROW[$id]="$an"; SRC[$id]="$asrc"
        [[ "$id" =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || { fail "$id: niedozwolone znaki w id"; bad=1; }
        [[ "$asrc" == pacman || "$asrc" == aur ]] || { fail "$id: arch_source=$asrc (pacman|aur)"; bad=1; }
        case "$fsrc" in
            fedora|copr:nett00n/hyprland|vendor:brave|rpmfusion-free|rpmfusion-nonfree|-) ;;
            *) fail "$id: niedozwolone fedora_source=$fsrc"; bad=1 ;;
        esac
        if [[ ! "$stt" =~ ^fedora=(ok|manual|unavailable|system-managed)\;nixos=(ok|manual|unavailable|system-managed)$ ]]; then
            fail "$id: status=$stt (fedora=<s>;nixos=<s>)"; bad=1; continue
        fi
        fs="${BASH_REMATCH[1]}"; ns="${BASH_REMATCH[2]}"
        [[ "$url" =~ ^https://[^[:space:]]+$ ]] || { fail "$id: source_url nie jest https: $url"; bad=1; }
        [[ "$ck" == - || "$ck" =~ ^cmd:[A-Za-z0-9._+-]+(,[A-Za-z0-9._+-]+)*$ || "$ck" =~ ^font:[A-Za-z0-9\ ]+$ ]] \
            || { fail "$id: check=$ck (cmd:a,b | font:<rodzina> | -)"; bad=1; }
        [[ "$mv" == - || "$mv" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { fail "$id: min_version=$mv"; bad=1; }
        # Żadnych zamienników -git (plan D3; ruchomy HEAD zamiast wydania).
        if [[ " $an $fn $na " =~ -git[[:space:]] ]]; then fail "$id: pakiet -git w mapie"; bad=1; fi
        if [[ "$fs" == ok && ( "$fn" == - || "$fsrc" == - ) ]]; then
            fail "$id: fedora=ok bez nazw RPM albo źródła"; bad=1
        fi
        if [[ "$fsrc" == rpmfusion-* && "$fs" == ok ]]; then
            fail "$id: RPM Fusion nie jest zatwierdzonym opt-in — status manual"; bad=1
        fi
        if [[ "$fsrc" != fedora && "$fsrc" != - && "$url" == https://mdapi.fedoraproject.org/* ]]; then
            fail "$id: źródło $fsrc bez własnego URL"; bad=1
        fi
        if [[ "$ns" == ok && ( "$na" == - || "$na" =~ \.enable$ ) ]]; then
            fail "$id: nixos=ok wymaga atrybutu nixpkgs (opcja NixOS = system-managed)"; bad=1
        fi
    done < "$MAP"
    ((n > 0)) || { fail "mapa bez wierszy"; return 1; }
    ((bad)) || ok "format: $n wierszy po 10 pól, statusy, źródła i URL poprawne"

    # ── cztery listy Archa i katalog CLI ──
    local f src p miss
    for f in requirements-pacman:pacman requirements-aur:aur additional-packages-pacman:pacman additional-packages-aur:aur; do
        src="${f#*:}"; f="$R/packages/${f%%:*}.txt"
        miss=()
        while IFS= read -r p; do
            LISTED[$p]=1
            if [[ -z "${ROW[$p]:-}" ]]; then miss+=("$p")
            elif [[ "${ROW[$p]}" != "$p" || "${SRC[$p]}" != "$src" ]]; then miss+=("$p(arch_name/arch_source)")
            fi
        done < <(list_names "$f")
        if ((${#miss[@]})); then fail "$(basename "$f"): bez wiersza mapy: ${miss[*]}"
        else ok "$(basename "$f"): każdy wpis ma wiersz ($src)"; fi
    done
    miss=()
    while IFS=$'\t' read -r _ _ _ p _; do
        [[ -n "$p" ]] || continue
        LISTED[$p]=1
        [[ -n "${ROW[$p]:-}" ]] || miss+=("$p")
    done < <(grep -v '^#' "$R/config/shell/cli-tools.tsv")
    if ((${#miss[@]})); then fail "cli-tools.tsv: bez wiersza mapy: ${miss[*]}"
    else ok "cli-tools.tsv: każdy pakiet ma wiersz"; fi

    # ── instalacje doraźne ──
    local -A ADHOC=()
    miss=()
    while IFS= read -r p; do
        ADHOC[$p]=1
        [[ -n "${ROW[$p]:-}" ]] || miss+=("$p")
    done < <(adhoc_names "$R" | sort -u)
    if ((${#ADHOC[@]} == 0)); then fail "nie znaleziono żadnej instalacji doraźnej (zepsuty wzorzec?)"
    elif ((${#miss[@]})); then fail "instalacje doraźne bez wiersza mapy: ${miss[*]}"
    else ok "instalacje doraźne (${#ADHOC[@]} nazw): każda ma wiersz"; fi
    # Wiersz spoza list musi mieć ślad w install/ albo scripts/ (nazwa
    # dosłownie albo — dla <jądro>-headers — nazwa jądra przy „-headers”).
    local -a stale=()
    local hits
    for id in "${!ROW[@]}"; do
        [[ -n "${LISTED[$id]:-}" || -n "${ADHOC[$id]:-}" ]] && continue
        hits="$(git -C "$R" grep -lwF -e "$id" -- install scripts 2>/dev/null)"
        if [[ -z "$hits" && "$id" == *-headers ]]; then
            [[ -n "${ADHOC[${id%-headers}]:-}" ]] && hits="$(git -C "$R" grep -lF -e '-headers' -- install)"
        fi
        [[ -n "$hits" ]] || stale+=("$id")
    done
    if ((${#stale[@]})); then fail "martwe wiersze (brak w listach i w kodzie): ${stale[*]}"
    else ok "brak martwych wierszy"; fi

    return $((FAIL - before))
}

echo "== platform-map.tsv: repo"
check_map "$REPO"

echo "== test negatywny: nowy pakiet w liście bez wiersza mapy"
# Kopia śledzonych plików do atrapy repo (git grep potrzebuje indeksu).
M="$T/repo"
mkdir -p "$M"
git -C "$REPO" ls-files -z -- packages config/shell/cli-tools.tsv install scripts \
    | (cd "$REPO" && xargs -0 cp --parents -t "$M")
# Mapa z drzewa roboczego (także przed jej pierwszym commitem).
cp "$REPO/packages/platform-map.tsv" "$M/packages/platform-map.tsv"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
echo "testnowy-pakiet" >> "$M/packages/requirements-pacman.txt"
git -C "$M" init -q && git -C "$M" add -A >/dev/null 2>&1
SAVED_PASS=$PASS SAVED_FAIL=$FAIL
neg_out="$(check_map "$M")"; neg_rc=$?
PASS=$SAVED_PASS FAIL=$SAVED_FAIL
if ((neg_rc > 0)) && [[ "$neg_out" == *"requirements-pacman.txt: bez wiersza mapy: testnowy-pakiet"* ]]; then
    ok "dopisany testnowy-pakiet bez wiersza → ✗ (zgodnie z oczekiwaniem)"
else
    fail "test negatywny nie wykrył pakietu bez wiersza (rc=$neg_rc)"
    sed 's/^/      /' <<< "$neg_out"
fi

echo "== test negatywny: pakiet -git i nieznany COPR"
SAVED_PASS=$PASS SAVED_FAIL=$FAIL
cp "$REPO/packages/platform-map.tsv" "$M/packages/platform-map.tsv"
printf 'testnowy-pakiet\ttestnowy-pakiet\tpacman\ttestnowy-pakiet-git\tcopr:obcy/repo\t-\t-\t-\tfedora=ok;nixos=unavailable\thttps://example.invalid/\n' \
    >> "$M/packages/platform-map.tsv"
neg_out="$(check_map "$M")"; neg_rc=$?
PASS=$SAVED_PASS FAIL=$SAVED_FAIL
if ((neg_rc > 0)) && [[ "$neg_out" == *"pakiet -git w mapie"* && "$neg_out" == *"niedozwolone fedora_source=copr:obcy/repo"* ]]; then
    ok "wiersz z -git i obcym COPR → ✗"
else
    fail "test negatywny -git/COPR nie zadziałał (rc=$neg_rc)"
fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
((FAIL == 0))
