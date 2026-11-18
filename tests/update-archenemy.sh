#!/usr/bin/env bash
# =============================================
#   archenemy - tests/update-archenemy.sh
#   Testy regresji aktualizatora (scripts/appbinds/update-archenemy.sh,
#   Super+A → [u]) na PRAWDZIWYM gicie: lokalne repo „origin” (bare) i klon
#   w atrapie $HOME. Bez sieci, bez roota, bez zapisu poza mktemp.
#
#   Powód powstania (audyt 2026-09-23): sprawdzenia `if ! git … | sed …` bez
#   pipefail brały kod wyjścia seda, więc nieudany fetch/pull/stash pop
#   kończył się komunikatem „✓ Updated”; a opcja „main” przełączała
#   na gałąź starszą o dziesiątki commitów (sprzed migracji configu na Lua).
#   Każdy scenariusz niżej PADA na kodzie sprzed poprawki.
#   Uruchom: bash tests/update-archenemy.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval na cytowanym wyrażeniu (zmienne żyją w eval); „” w etykietach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPD="$REPO/scripts/appbinds/update-archenemy.sh"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# Tożsamość gita tylko dla testu (stash i commity jej wymagają); bez configu globalnego.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"
A="$HOME/archenemy"
# Platforma jawnie (D8): Arch, chyba że scenariusz poda inny os-release.
mkdir -p "$T/os"
printf 'ID=arch\n' > "$T/os/arch"; printf 'ID=endeavouros\nID_LIKE=arch\n' > "$T/os/endeavouros"
printf 'ID=fedora\nVERSION_ID=44\n' > "$T/os/fedora"; printf 'ID=nixos\n' > "$T/os/nixos"; printf 'ID=ubuntu\n' > "$T/os/ubuntu"
export ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os/arch"
g() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# ─── origin: main (stary) ← dev (nowszy o 2 commity) ─────────────────────────
S="$T/seed"
mkdir -p "$S/install"
git init -q -b main "$S"
printf '#!/usr/bin/env bash\necho INSTALL-RAN\n' > "$S/install/install.sh"   # celowo 100644
echo v1 > "$S/f.txt"
g "$S" add -A; g "$S" commit -m main-v1
g "$S" checkout -b dev
echo v2 > "$S/f.txt"; g "$S" commit -am dev-v2
echo v3 > "$S/g.txt"; g "$S" add g.txt; g "$S" commit -m dev-v3
git clone -q --bare "$S" "$T/origin.git"

fresh_clone() {   # fresh_clone <gałąź>
    rm -rf "$A"; mkdir -p "$HOME"
    git clone -q -b "$1" "$T/origin.git" "$A"
}
upstream_commit() {   # upstream_commit <gałąź> <plik> <treść> — nowy commit na origin
    local w="$T/w"
    rm -rf "$w"; git clone -q -b "$1" "$T/origin.git" "$w"
    mkdir -p "$(dirname "$w/$2")"
    echo "$3" > "$w/$2"; g "$w" add -A; g "$w" commit -m "up-$3"; g "$w" push origin "$1"
}
run_upd() {   # run_upd <klawisze> — stdin: wybór gałęzi, odpowiedzi, Entery
    printf '%b' "$1" | bash "$UPD" 2>&1
}
head_of() { git -C "$A" rev-parse "$1" 2>/dev/null; }

echo "== aktualizacja szczęśliwa"
fresh_clone dev
upstream_commit dev f.txt v4
out=$(run_upd '1n\n')
check "HEAD = origin/dev po aktualizacji"      '[[ "$(head_of HEAD)" == "$(head_of origin/dev)" ]]'
check "komunikat sukcesu"                      '[[ "$out" == *"✓ Updated"* ]]'

echo "== N1: pull odrzucony (lokalny commit + nowy upstream = brak fast-forward)"
fresh_clone dev
echo lokalne > "$A/h.txt"; g "$A" add h.txt; g "$A" commit -m lokalny
upstream_commit dev f.txt v5
before=$(head_of HEAD)
out=$(run_upd '1\n\n')
check "brak fałszywego „✓ Updated”"     '[[ "$out" != *"✓ Updated"* ]]'
check "jawny błąd pulla"                       '[[ "$out" == *"✗ Pull"* ]]'
check "HEAD bez zmian"                         '[[ "$(head_of HEAD)" == "$before" ]]'

echo "== N1: konflikt przy przywracaniu schowka"
fresh_clone dev
echo lokalna-wersja > "$A/f.txt"
upstream_commit dev f.txt upstream-wersja
out=$(run_upd '1yn\n\n')
check "brak fałszywego „przywrócone”"          '[[ "$out" != *"✓ Local changes restored"* ]]'
check "jawny błąd przywracania"                '[[ "$out" == *"✗ Could not restore"* ]]'
check "zmiany dalej w schowku (nic nie ginie)" '[[ -n "$(git -C "$A" stash list)" ]]'
# K3 (audyt bezpieczeństwa 2026-11-14): po konflikcie schowka drzewo ma
# znaczniki konfliktu — żadnego „✓”, żadnego pytania o instalator; nawet
# wpisane „y” nie może uruchomić install.sh (z sudo) na takim drzewie.
check "konflikt schowka: brak „✓ Updated”"      '[[ "$out" != *"✓ Updated"* ]]'
check "konflikt schowka: brak pytania o install.sh" '[[ "$out" != *"Run install.sh"* ]]'
fresh_clone dev
echo lokalna-wersja > "$A/f.txt"
upstream_commit dev f.txt upstream-wersja-k3
out=$(run_upd '1yy\n\n')
check "konflikt schowka + „y”: install.sh się nie uruchamia" '[[ "$out" != *INSTALL-RAN* ]]'

# A7 (przegląd 2026-11-15): dawna rada „resolve the conflict and run git
# stash pop” nie działa — pop na pliku z konfliktem kończy się „needs merge”
# (rc 128), a po `git add` nakłada schowek drugi raz (nowy konflikt). Działa
# to, co mówi man git-stash: rozwiąż, `git add`, `git stash drop`. Test robi
# dokładnie to, co wypisuje aktualizator.
echo "== A7: rada po konflikcie schowka (rozwiąż, git add, git stash drop) działa"
fresh_clone dev
echo lokalna-wersja > "$A/f.txt"; echo lokalna-g > "$A/g.txt"   # f.txt: konflikt, g.txt: bez
upstream_commit dev f.txt upstream-wersja-a7
out=$(run_upd '1yn\n\n')
check "A7: rada mówi git add i git stash drop, nie „run git stash pop”" '[[ "$out" == *"git add those files, then git stash drop"* && "$out" != *"run git stash pop"* ]]'
check "A7: po konflikcie: f.txt nierozwiązany, wpis w schowku" '[[ "$(git -C "$A" diff --name-only --diff-filter=U)" == f.txt && -n "$(git -C "$A" stash list)" ]]'
want_f=$'upstream-wersja-a7\nlokalna-wersja'
printf '%s\n' "$want_f" > "$A/f.txt"                              # rozwiązanie: obie zmiany
check "A7: dawna rada (stash pop po poprawce pliku) odmawia, wpis zostaje" '! git -C "$A" stash pop >/dev/null 2>&1 && [[ -n "$(git -C "$A" stash list)" ]]'
check "A7: git add + git stash drop → rc 0" 'git -C "$A" add f.txt && git -C "$A" stash drop >/dev/null 2>&1'
check "A7: schowek pusty, bez konfliktów, obie zmiany i g.txt na miejscu" '[[ -z "$(git -C "$A" stash list)" && -z "$(git -C "$A" diff --name-only --diff-filter=U)" && "$(<"$A/f.txt")" == "$want_f" && "$(<"$A/g.txt")" == lokalna-g ]]'
out=$(run_upd '1yn\n')
check "A7: następna aktualizacja po radzie przechodzi" '[[ "$out" == *"✓ Local changes restored"* && "$out" == *"✓ Updated"* ]]'
# Pop nieudany BEZ konfliktu (atrapa gita odmawia `stash pop`): nic nie weszło
# do drzewa, więc rada „git stash drop” zgubiłaby zmiany — ma paść samo pop.
mkdir -p "$T/fakegit"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [[ "$a" == pop ]] && { echo "error: TEST simulated failure" >&2; exit 1; }; done\nexec %q "$@"\n' "$(command -v git)" > "$T/fakegit/git"
chmod +x "$T/fakegit/git"
fresh_clone dev
echo lokalna-g > "$A/g.txt"
upstream_commit dev f.txt upstream-a7-bez-konfliktu
out=$(printf '%b' '1yn\n\n' | PATH="$T/fakegit:$PATH" bash "$UPD" 2>&1)
check "A7: pop bez konfliktu — rada „git stash pop”, nigdy „drop”" '[[ "$out" == *"✗ Could not restore"* && "$out" == *"then run git stash pop"* && "$out" != *"stash drop"* && "$out" != *"✓ Updated"* ]]'
check "A7: pop bez konfliktu — po radzie zmiany wracają" 'git -C "$A" stash pop >/dev/null 2>&1 && [[ "$(<"$A/g.txt")" == lokalna-g && -z "$(git -C "$A" stash list)" ]]'

echo "== K4: pytanie o install.sh domyślnie N i z ostrzeżeniem o sudo"
fresh_clone dev
upstream_commit dev f.txt v4-k4
out=$(run_upd '1\n\n')
check "Enter przy pytaniu → install.sh się NIE uruchamia" '[[ "$out" != *INSTALL-RAN* ]]'
check "pytanie mówi, że instalator poprosi o sudo"      '[[ "$out" == *"will ask for sudo"* && "$out" == *"[y/N]"* ]]'
check "aktualizacja i tak udana"                        '[[ "$out" == *"✓ Updated"* ]]'

echo "== N1: fetch nieudany (origin nieosiągalny)"
fresh_clone dev
g "$A" remote set-url origin "$T/nie-ma-takiego.git"
before=$(head_of HEAD)
out=$(run_upd '1\n\n')
check "jawny błąd fetcha"                      '[[ "$out" == *"✗ Fetch"* ]]'
check "brak fałszywego „✓ Updated”"     '[[ "$out" != *"✓ Updated"* ]]'
check "HEAD bez zmian"                         '[[ "$(head_of HEAD)" == "$before" ]]'

echo "== N3: gałąź starsza niż obecny stan (main za dev) — wybór zostaje, ale z potwierdzeniem"
fresh_clone dev
before=$(head_of HEAD)
out=$(run_upd '2\n\n')
check "ostrzeżenie o cofnięciu"                '[[ "$out" == *"is older than"* ]]'
check "domyślnie (Enter) zostaje na dev"       '[[ "$(git -C "$A" branch --show-current)" == dev && "$(head_of HEAD)" == "$before" ]]'
check "brak „✓ Updated”"                '[[ "$out" != *"✓ Updated"* ]]'
fresh_clone dev
out=$(run_upd '2yn\n')
check "potwierdzone „y” → przełączone na main" '[[ "$(git -C "$A" branch --show-current)" == main && "$(head_of HEAD)" == "$(head_of origin/main)" ]]'

echo "== N3: przełączenie do przodu (main → dev) dalej działa"
fresh_clone main
out=$(run_upd '1n\n')
check "na dev = origin/dev"                    '[[ "$(git -C "$A" branch --show-current)" == dev && "$(head_of HEAD)" == "$(head_of origin/dev)" ]]'

echo "== lokalne commity ponad origin: ostrzeżenie zamiast „✓”"
fresh_clone dev
echo lokalne > "$A/h.txt"; g "$A" add h.txt; g "$A" commit -m lokalny
out=$(run_upd '1n\n')
check "ostrzeżenie o lokalnych commitach"      '[[ "$out" == *"local commits"* ]]'
check "brak „✓ Updated”"                '[[ "$out" != *"✓ Updated"* ]]'

echo "== plik nieśledzony (własna tapeta w wallpapers/) zostaje na dysku przez aktualizację"
fresh_clone dev
mkdir -p "$A/wallpapers"; echo moja > "$A/wallpapers/moja.jpg"
echo lokalna-wersja > "$A/f.txt"                   # zmiana śledzona → stash
upstream_commit dev g.txt v6
out=$(run_upd '1yn\n')
check "tapeta na dysku po udanej aktualizacji"     '[[ -f "$A/wallpapers/moja.jpg" && "$(cat "$A/wallpapers/moja.jpg")" == moja ]]'
check "HEAD = origin/dev"                          '[[ "$(head_of HEAD)" == "$(head_of origin/dev)" ]]'
# Ten sam plik przy KONFLIKCIE pop: ze `stash -u` tapeta lądowała w schowku
# (trzeci rodzic wpisu stash), bez -u nigdy nie opuszcza dysku.
fresh_clone dev
mkdir -p "$A/wallpapers"; echo moja > "$A/wallpapers/moja.jpg"
echo lokalna-wersja > "$A/f.txt"
upstream_commit dev f.txt upstream-wersja-2
out=$(run_upd '1yn\n\n')
check "konflikt pop zgłoszony"                     '[[ "$out" == *"✗ Could not restore"* ]]'
check "tapeta na dysku mimo konfliktu schowka"     '[[ -f "$A/wallpapers/moja.jpg" ]]'
check "schowek bez plików nieśledzonych"           '[[ -z "$(git -C "$A" show --stat "stash@{0}^3" 2>/dev/null)" ]]'

echo "== wspólny plik powłoki (config/shell/shellrc, gitignore) przeżywa aktualizację"
upstream_commit dev .gitignore "$(cat "$REPO/.gitignore")"
fresh_clone dev
mkdir -p "$A/config/shell"; printf "alias TESTmoj='ls'\n" > "$A/config/shell/shellrc"
cp "$A/config/shell/shellrc" "$T/shellrc.before"
echo lokalna-wersja > "$A/f.txt"                   # zmiana śledzona → stash i pop
upstream_commit dev g.txt v7
check "shellrc ignorowany przez gita"              '[[ -z "$(git -C "$A" status --porcelain --ignored=no -- config/shell)" ]]'
out=$(run_upd '1yn\n')
check "HEAD = origin/dev"                          '[[ "$(head_of HEAD)" == "$(head_of origin/dev)" ]]'
check "shellrc bez zmian po aktualizacji"          'cmp -s "$A/config/shell/shellrc" "$T/shellrc.before"'

echo "== wybory strzałkami"
fresh_clone dev
before=$(head_of HEAD)
out=$(run_upd '\e\n')
check "Esc przed fetch pozostawia HEAD" '[[ "$(head_of HEAD)" == "$before" && "$out" != *"Fetching"* ]]'
fresh_clone dev
out=$(run_upd '\e[B\n\e[A\nn\n')
check "strzałki: main i zgoda na cofnięcie" '[[ "$(git -C "$A" branch --show-current)" == main ]]'
fresh_clone dev
echo local > "$A/f.txt"
out=$(run_upd '1\e[B\n\n')
check "strzałki: odmowa schowka zachowuje plik" '[[ "$(<"$A/f.txt")" == local && -z "$(git -C "$A" stash list)" ]]'
fresh_clone dev
out=$(run_upd '1\e[A\e[B\n\n')   # domyślnie N (K4): ↑ na Yes, ↓ z powrotem na No
check "strzałki: odmowa instalatora" '[[ "$out" != *INSTALL-RAN* ]]'

echo "== K5: lista zmian przed pull, ostrzeżenie dla install/ i packages/, droga powrotu"
fresh_clone dev
old7=$(git -C "$A" rev-parse --short=7 HEAD)
upstream_commit dev install/extra.sh k5-instalator
out=$(run_upd '1n\n')
check "lista nowych commitów przed pull"            '[[ "$out" == *"up-k5-instalator"* && "$out" == *"New commits"* ]]'
check "ostrzeżenie o zmianach w install/"            '[[ "$out" == *"⚠ This update changes the installer or package lists"* && "$out" == *"install/extra.sh"* ]]'
check "droga powrotu z poprzednim HEAD"              '[[ "$out" == *"To go back: git switch --detach $old7"* ]]'
fresh_clone dev
upstream_commit dev f.txt k5-zwykly
out=$(run_upd '1n\n')
check "zmiana poza install/ i packages/ — bez ostrzeżenia" '[[ "$out" == *"up-k5-zwykly"* && "$out" != *"changes the installer"* ]]'
fresh_clone dev
out=$(run_upd '1n\n')
check "brak nowych commitów — komunikat zamiast pustej listy" '[[ "$out" == *"No new commits"* && "$out" != *"To go back"* ]]'
w="$T/w30"; rm -rf "$w"; git clone -q -b dev "$T/origin.git" "$w"
for i in $(seq 1 32); do echo "$i" > "$w/f.txt"; g "$w" commit -am "seria-$i"; done; g "$w" push origin dev
fresh_clone dev
git -C "$A" fetch -q origin dev; git -C "$A" reset -q --hard "$(git -C "$A" rev-parse 'origin/dev~32')"
out=$(run_upd '1n\n'); NL=$'\n'
check "limit 30 commitów + licznik reszty"          '[[ "$out" == *"seria-32"* && "$out" == *"seria-3"* && "$out" != *"seria-2$NL"* && "$out" == *"2 more"* ]]'

# A3 (przegląd 2026-11-15): lista i ⚠ K5 stoją PRZED pull, więc wyjście
# pulla przewija je poza okno Super+A (ok. 27 wierszy), zanim padnie pytanie
# o install.sh. Podsumowanie musi stać w wierszach tuż nad tym pytaniem.
echo "== A3: podsumowanie tuż przed pytaniem o install.sh"
before_question() {   # 3 wiersze tuż nad pytaniem o install.sh
    sed -n '/Run install.sh now/q;p' <<< "$out" | tail -n 3
}
fresh_clone dev
old7=$(git -C "$A" rev-parse --short=7 HEAD)
w="$T/wa3"; rm -rf "$w"; git clone -q -b dev "$T/origin.git" "$w"
mkdir -p "$w/install" "$w/packages"
for i in 1 2 3 4 5 6 7 8; do echo "$i" > "$w/a3-$i.txt"; done
echo a3 > "$w/install/a3.sh"; echo a3 > "$w/packages/a3.txt"
g "$w" add -A; g "$w" commit -m a3-pierwszy
echo a3-zmiana > "$w/a3-1.txt"; g "$w" commit -am a3-drugi; g "$w" push origin dev
out=$(run_upd '1n\n'); pre=$(before_question)
check "A3: liczba commitów i plików tuż nad pytaniem"  '[[ "$pre" == *"This update: 2 new commits, 10 files changed, 10 insertions(+)"* ]]'
check "A3: ⚠ install/ packages/ tuż nad pytaniem"      '[[ "$pre" == *"⚠ install/ or packages/ changed (2 files)"* ]]'
check "A3: komenda przeglądu z poprzednim HEAD"        '[[ "$pre" == *"git -C ~/archenemy diff $old7 HEAD -- install packages"* ]]'
check "A3: ⚠ przed pull zostaje (zakres K5 bez zmian)" '[[ "$out" == *"⚠ This update changes the installer or package lists"* && "$out" == *"packages/a3.txt"* ]]'
fresh_clone dev
upstream_commit dev f.txt a3-zwykly
out=$(run_upd '1n\n'); pre=$(before_question)
check "A3: zwykła zmiana — podsumowanie bez ⚠"         '[[ "$pre" == *"This update: 1 new commit, 1 file changed"* && "$pre" != *"⚠"* ]]'
fresh_clone dev
out=$(run_upd '1n\n')
check "A3: bez nowych commitów — bez podsumowania"     '[[ "$out" != *"This update:"* && "$out" == *"Run install.sh now"* ]]'
fresh_clone dev
out=$(run_upd '2yn\n'); pre=$(before_question)
check "A3: dev → main — podsumowanie mówi o cofniętych commitach" '[[ "$pre" == *"This update: "*" commits rolled back, "*"changed"* && "$pre" != *"new commit"* ]]'

echo "== install.sh bez prawa wykonywania nadal się uruchamia"
fresh_clone dev
check "install.sh w klonie jest 100644"        '[[ ! -x "$A/install/install.sh" ]]'
out=$(run_upd '1y\n')
check "instalator uruchomiony"                 '[[ "$out" == *INSTALL-RAN* ]]'

# D8: porada o instalatorze i zakres ostrzeżenia zależą od pkg_route (os-release),
# nie od zmiennych odziedziczonych po instalatorze. Arch: teksty i zakres bez zmian.
echo "== D8: platformy (Arch, EndeavourOS, Fedora, NixOS, Ubuntu)"
upd_os() {   # upd_os <os> <klawisze> — bieg aktualizatora z danym os-release
    printf '%b' "$2" | ARCHENEMY_OS_RELEASE="$T/os/$1" PLATFORM=arch PKG_ROUTE=arch bash "${UPDV:-$UPD}" 2>&1
}
fresh_clone dev
upstream_commit dev nix/packages.nix d8-nix
snapA="$T/snap-d8"; rm -rf "$snapA"; cp -a "$A" "$snapA"
out=$(upd_os nixos '1n\n'); pre=$(before_question)
check "NixOS: zmiana nix/ ostrzega przed pull i nad pytaniem" '[[ "$out" == *"⚠ This update changes the installer or package lists"* && "$out" == *"nix/packages.nix"* && "$pre" == *"install/, packages/ or nix/ changed (1 file)"* && "$pre" == *"-- install packages nix"* ]]'
check "NixOS: pytanie bez obietnicy sudo, domyślnie N" '[[ "$out" == *"On NixOS it installs nothing and does not use sudo"* && "$out" != *"will ask for sudo"* && "$out" == *"[y/N]"* && "$out" != *INSTALL-RAN* ]]'
rm -rf "$A"; cp -a "$snapA" "$A"
out=$(upd_os arch '1n\n')
check "Arch: nix/ poza zakresem ostrzeżenia (jak przed D8), pytanie o sudo" '[[ "$out" != *"changes the installer"* && "$out" == *"It will ask for sudo."* ]]'
arch_out="$out"
rm -rf "$A"; cp -a "$snapA" "$A"
out=$(upd_os endeavouros '1n\n')
check "EndeavourOS = Arch (całe wyjście)" '[[ "$out" == "$arch_out" ]]'
rm -rf "$A"; cp -a "$snapA" "$A"
out=$(upd_os fedora '1n\n')
check "Fedora: sudo przez dnf, dodatkowe repozytoria osobno" '[[ "$out" == *"It will ask for sudo (dnf); extra repositories are asked about separately."* && "$out" != *"or nix/"* ]]'
rm -rf "$A"; cp -a "$snapA" "$A"
out=$(upd_os ubuntu '1y\n')
check "Ubuntu: instalator nie oferowany, „y” go nie uruchamia" '[[ "$out" == *"install.sh supports Arch Linux, Fedora and NixOS only"* && "$out" != *"Run install.sh now"* && "$out" != *INSTALL-RAN* ]]'
check "Ubuntu: aktualizacja i tak udana" '[[ "$out" == *"✓ Updated"* ]]'

# Parytet z bazą (UPDATE_ARCHENEMY_REV=<rewizja>): te same scenariusze Archa na
# aktualizatorze z rewizji, na identycznej kopii klonu — całe wyjście równe.
if [[ -n "${UPDATE_ARCHENEMY_REV:-}" ]]; then
    echo "== parytet Archa z $UPDATE_ARCHENEMY_REV"
    mkdir -p "$T/base"
    git -C "$REPO" archive "$UPDATE_ARCHENEMY_REV" scripts/appbinds | tar -x -C "$T/base" || { echo "✗ brak $UPDATE_ARCHENEMY_REV"; exit 1; }
    parity_case() {   # parity_case <etykieta> <plik upstream> <klawisze>
        fresh_clone dev
        [[ -n "$2" ]] && upstream_commit dev "$2" "par-${2//\//-}"
        rm -rf "$snapA"; cp -a "$A" "$snapA"
        local head_out base_out
        head_out=$(upd_os arch "$3")
        rm -rf "$A"; cp -a "$snapA" "$A"
        base_out=$(UPDV="$T/base/scripts/appbinds/update-archenemy.sh" upd_os arch "$3")
        check "Arch $1 = $UPDATE_ARCHENEMY_REV (całe wyjście)" '[[ "$head_out" == "$base_out" ]]'
    }
    parity_case "zwykła zmiana, N" f.txt '1n\n'
    parity_case "zmiana install/, N" install/x.sh '1n\n'
    parity_case "zmiana packages/, Enter" packages/y.txt '1\n\n'
    parity_case "zmiana nix/, N" nix/packages.nix '1n\n'
    parity_case "bez nowych commitów, y" '' '1y\n'
fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
