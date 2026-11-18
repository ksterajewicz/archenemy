#!/usr/bin/env bash
# =============================================
#   archenemy - install/lib/pkg.sh
#   Warstwa pakietów per dystrybucja (D4, EKSPERYMENTALNE; Fedora i NixOS
#   w wariancie A, decyzje właściciela 2026-11-17). Arch jest platformą
#   referencyjną: na Archu funkcje wołają DOKŁADNIE te same komendy co
#   install.sh i install/lib/aur.sh (`pacman -Qi`, `sudo pacman -S --needed`,
#   `aur_install` → `yay -S --needed`). install.sh (D5) prowadzi jednak Archa
#   i jego pochodne dotychczasowym kodem kroków [2]/[4]/[5], a tej biblioteki
#   używa do wykrycia platformy oraz na Fedorze i NixOS.
#
#   Dane: packages/platform-map.tsv — czytane zwykłym `read`, nigdy eval/source;
#   każda nazwa pakietu przechodzi przez whitelistę znaków, zanim trafi do sudo
#   (pierwszy znak alfanumeryczny, więc bez `--` przed nazwami), listy dzielone
#   bez rozwijania ścieżek; nieznany status/źródło albo niespójne pola = zła mapa.
#   Source nie robi nic poza definicją funkcji (żadnych zapytań ani instalacji).
#
#   API (komunikaty po angielsku, funkcje nie wychodzą z procesu):
#     pkg_detect             PKG_PLATFORM=arch|fedora|nixos (+ PKG_OS_ID, PKG_OS_VERSION);
#                            0 = obsługiwana, 1 = odmowa (inne ID, Fedora Atomic) — przed
#                            jakimkolwiek zapisem
#     pkg_arch_derivative    0 = pochodna Archa (ID≠arch, ID_LIKE zawiera „arch”: EndeavourOS,
#                            Manjaro…), 1 = nie; bez komunikatów i bez ustawiania PKG_PLATFORM —
#                            install.sh prowadzi pochodne starą ścieżką Archa (decyzja 2026-11-17)
#     pkg_route              ścieżka instalatora: PKG_ROUTE=arch (Arch i pochodne) | fedora | nixos;
#                            1 = odmowa jak pkg_detect (PKG_ROUTE pusty). Tej samej funkcji używa
#                            install.sh i każdy pomocnik systemowy install/*.sh — nigdy
#                            odziedziczonej zmiennej PLATFORM
#     pkg_gate <co>          brama pomocników systemowych (D6): 0 = Arch/pochodna, pomocnik działa
#                            jak dotąd; 2 = inna platforma — wypisuje „nic nie zmieniono” i zachętę
#                            do kroku ręcznego (PKG_ROUTE=fedora|nixos; instrukcję dopisuje
#                            pomocnik) albo brak wsparcia (PKG_ROUTE pusty). Nic nie pyta, nie
#                            woła sudo ani żadnego polecenia poza odczytem os-release
#     pkg_installed <id>     0 jest, 1 brak, 2 błąd zapytania / nieznany id,
#                            3 nie da się sprawdzić na tej platformie (brak sondy);
#                            zapytania rpm/pacman z LC_ALL=C — wynik nie zależy od języka
#     pkg_install <id…>      tylko domyślne źródło platformy (Arch: pacman + AUR przez yay,
#                            Fedora: `sudo dnf install --repo=fedora --repo=updates` (DNF5),
#                            sukces = rpm -q każdej nazwy — stan, nie kod dnf: dnf ≠ 0 przy
#                            komplecie nazw daje 0 z ostrzeżeniem). 0 wszystko zainstalowane,
#                            1 porażka (PKG_FAILED),
#                            2 nieznany id / zła mapa, 3 część pominięta (PKG_SKIPPED: ręczne,
#                            niedostępne, systemowe albo wymagające pkg_install_extra),
#                            4 platforma nieobsługiwana, 5 NixOS (deklaratywnie — nic nie robi)
#     pkg_install_extra <id…> Fedora: COPR nett00n/hyprland i repo Brave — pokazuje źródło
#                            i URL, pyta [y/N] osobno dla każdego źródła; bez „y” nic nie
#                            włącza. Kody jak pkg_install; inne platformy → 2
#     pkg_hint <id>          jedna linia: jak zainstalować/skonfigurować na tej platformie
#     pkg_version <id>       wypisuje wersję pierwszego pakietu; 0 ok, 1 brak, 2 nie da się
#                            odczytać (błąd), 3 poniżej min_version z mapy. NixOS: tylko
#                            nixos=ok z sondą cmd: — wersja ze ścieżki sklepu Nix, do której
#                            prowadzi pierwsza komenda (<hash>-<atrybut>-<wersja>); inaczej 2
#     pkg_min_version <id>   wypisuje min_version z mapy; 0 jest, 1 brak minimum („-”), 2 zły id
#     pkg_version_ge <v> <min> 0 = v ≥ min (sort -V, jak pkg_version)
#
#   NixOS: nigdy nix-env, nix profile ani nixos-rebuild — tylko sondy i podpowiedzi.
#   Fedora: bez --skip-unavailable/--skip-broken/--allowerasing i bez -y (dnf pyta sam).
#   Haki testowe (tylko ARCHENEMY_TEST=1): ARCHENEMY_OS_RELEASE (plik os-release),
#   ARCHENEMY_OSTREE_MARKER (zamiast /run/ostree-booted), ARCHENEMY_PKG_MAP (mapa),
#   ARCHENEMY_YUM_REPOS_DIR (zamiast /etc/yum.repos.d), ARCHENEMY_NIX_STORE (zamiast /nix/store).
# =============================================

# Katalog biblioteki bez dirname (source działa też przy okrojonym PATH).
_pkg_self="${BASH_SOURCE[0]}"
[[ "$_pkg_self" == */* ]] || _pkg_self="./$_pkg_self"
PKG_LIB_DIR="$(cd "${_pkg_self%/*}" && pwd)"
unset _pkg_self
PKG_PLATFORM=""
PKG_ROUTE=""
PKG_OS_ID=""
PKG_OS_VERSION=""
PKG_SKIPPED=()
PKG_FAILED=()

# Jedyne źródła spoza repozytoriów Fedory, które instalator może włączyć
# (opt-in, decyzja 2026-11-17). Reszta (RPM Fusion, producenci) = ręcznie.
PKG_COPR_PROJECT="nett00n/hyprland"
PKG_COPR_URL="https://copr-be.cloud.fedoraproject.org/results/nett00n/hyprland/"
PKG_BRAVE_REPOFILE="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"
PKG_BRAVE_URL="https://brave.com/linux/"
# Wydania Fedory, dla których COPR sprawdzono w repodata (raport D3, 2026-11-17).
PKG_COPR_VERIFIED="43 44 45"

_pkg_test() { [[ "${ARCHENEMY_TEST:-}" == 1 ]]; }

# _pkg_os_value <plik> <KLUCZ> — wartość z os-release bez eval: KLUCZ=wartość,
# opcjonalnie w "…" albo '…'. Brak klucza = pusty napis.
_pkg_os_value() {
    local line key val
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"
        [[ "$key" == "$2" ]] || continue
        val="${line#*=}"
        if [[ "$val" == \"*\" && ${#val} -ge 2 ]]; then val="${val:1:${#val}-2}"
        elif [[ "$val" == \'*\' && ${#val} -ge 2 ]]; then val="${val:1:${#val}-2}"
        fi
        printf '%s\n' "$val"
        return 0
    done < "$1"
}

# _pkg_os_file — ścieżka czytelnego os-release (hak testowy, /etc, /usr/lib); 1 = brak.
_pkg_os_file() {
    local f=""
    if _pkg_test && [[ -n "${ARCHENEMY_OS_RELEASE:-}" ]]; then
        f="$ARCHENEMY_OS_RELEASE"
    elif [[ -r /etc/os-release ]]; then
        f=/etc/os-release
    elif [[ -r /usr/lib/os-release ]]; then
        f=/usr/lib/os-release
    fi
    [[ -n "$f" && -r "$f" ]] || return 1
    printf '%s\n' "$f"
}

pkg_arch_derivative() {
    local f id w
    local -a like
    f="$(_pkg_os_file)" || return 1
    id="$(_pkg_os_value "$f" ID)"
    [[ -n "$id" && "$id" != arch ]] || return 1
    # read -ra dzieli bez rozwijania ścieżek (`for w in $(…)` zamieniłby „a*” w plik).
    read -ra like <<< "$(_pkg_os_value "$f" ID_LIKE)"
    for w in "${like[@]}"; do
        [[ "$w" == arch ]] && return 0
    done
    return 1
}

pkg_detect() {
    local f variant marker="/run/ostree-booted"
    PKG_PLATFORM=""
    if ! f="$(_pkg_os_file)"; then
        echo "  Cannot read /etc/os-release or /usr/lib/os-release — unknown distribution, nothing will be installed." >&2
        return 1
    fi
    PKG_OS_ID="$(_pkg_os_value "$f" ID)"
    PKG_OS_VERSION="$(_pkg_os_value "$f" VERSION_ID)"
    variant="$(_pkg_os_value "$f" VARIANT_ID)"
    _pkg_test && [[ -n "${ARCHENEMY_OSTREE_MARKER:-}" ]] && marker="$ARCHENEMY_OSTREE_MARKER"
    case "$PKG_OS_ID" in
        arch) PKG_PLATFORM=arch ;;
        nixos) PKG_PLATFORM=nixos ;;
        fedora)
            # Fedora Atomic (Silverblue, Kinoite, Sway/Budgie/COSMIC Atomic…) ma
            # rpm-ostree zamiast dnf — poza tą ścieżką.
            if [[ -e "$marker" || "$variant" == *atomic* || "$variant" =~ ^(silverblue|kinoite|sericea|onyx)$ ]]; then
                echo "  Fedora Atomic (rpm-ostree) is not supported by this installer — nothing will be installed." >&2
                return 1
            fi
            PKG_PLATFORM=fedora ;;
        *)
            echo "  Unsupported distribution (ID=${PKG_OS_ID:-?}): archenemy supports Arch Linux, and experimentally Fedora and NixOS. Nothing will be installed." >&2
            return 1 ;;
    esac
    return 0
}

pkg_route() {
    PKG_ROUTE=""
    if pkg_arch_derivative; then
        PKG_ROUTE=arch
        return 0
    fi
    pkg_detect || return 1
    PKG_ROUTE="$PKG_PLATFORM"
}

pkg_gate() {
    local name
    if pkg_route; then
        [[ "$PKG_ROUTE" == arch ]] && return 0
        name=Fedora; [[ "$PKG_ROUTE" == nixos ]] && name=NixOS
        echo "⚠ $1: archenemy does this automatically only on Arch Linux — nothing was changed on $name."
        echo "  Do it yourself on $name:"
    else
        echo "⚠ $1: this distribution is not supported by archenemy — nothing was changed."
        echo "  Use your distribution's own tools for it."
    fi
    return 2
}

# ── mapa ─────────────────────────────────────────────────────────────────────

_pkg_name_ok() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9+._-]*$ ]]; }

# _pkg_names_ok <pole> — „-” albo nazwy rozdzielone spacją, każda z whitelisty.
# read -ra: bez rozwijania ścieżek (`for w in $pole` zamieniał „pkg-*” w plik
# z katalogu roboczego, a do dnf trafiał surowy wzorzec).
_pkg_names_ok() {
    local w
    local -a ws
    [[ "$1" == - ]] && return 0
    read -ra ws <<< "$1"
    ((${#ws[@]})) || return 1
    for w in "${ws[@]}"; do _pkg_name_ok "$w" || return 1; done
}

# _pkg_row_ok <asrc> <fsrc> <nix> <check> <min> <sf> <sn> <url> — zbiór wartości
# i spójność pól (reguły tests/platform-map.sh, które dotyczą działania
# biblioteki: źródła, statusy, sonda, wersja, nixos=ok tylko z atrybutem
# nixpkgs — nie opcją *.enable, która dałaby podpowiedź „pkgs.services…” —
# i source_url tylko https); 1 = zła linia. Tylko w teście zostają reguły
# redakcyjne danych: zakaz pakietów -git i własny URL źródła spoza Fedory.
_pkg_row_ok() {
    local st
    [[ "$1" == pacman || "$1" == aur ]] || return 1
    case "$2" in fedora|"copr:$PKG_COPR_PROJECT"|vendor:brave|rpmfusion-free|rpmfusion-nonfree|-) ;; *) return 1 ;; esac
    for st in "$6" "$7"; do
        case "$st" in ok|manual|unavailable|system-managed) ;; *) return 1 ;; esac
    done
    [[ "$4" == - || "$4" =~ ^cmd:[A-Za-z0-9._+-]+(,[A-Za-z0-9._+-]+)*$ || "$4" =~ ^font:[A-Za-z0-9\ ]+$ ]] || return 1
    [[ "$5" == - || "$5" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
    # fedora=ok = instalowalne: nazwy i źródło, które pkg_install/_extra obsługują.
    if [[ "$6" == ok ]]; then
        case "$2" in fedora|"copr:$PKG_COPR_PROJECT"|vendor:brave) ;; *) return 1 ;; esac
    fi
    [[ "$7" != ok || ( "$3" != - && ! "$3" =~ \.enable$ ) ]] || return 1
    [[ "$8" =~ ^https://[^[:space:]]+$ ]] || return 1
}

# _pkg_load_map — wczytuje mapę raz; 0 ok, 2 brak/zła mapa (żadnych działań
# na częściowych danych: jedna zła linia = cała mapa odrzucona).
_pkg_load_map() {
    [[ -n "${_PKG_MAP_LOADED:-}" ]] && return 0
    local map="$PKG_LIB_DIR/../../packages/platform-map.tsv"
    _pkg_test && [[ -n "${ARCHENEMY_PKG_MAP:-}" ]] && map="$ARCHENEMY_PKG_MAP"
    declare -gA _PKG_ARCH=() _PKG_ASRC=() _PKG_FNAMES=() _PKG_FSRC=() _PKG_NIX=() \
        _PKG_CHECK=() _PKG_MIN=() _PKG_SF=() _PKG_SN=() _PKG_URL=()
    if [[ ! -r "$map" ]]; then
        echo "  Package map not found: $map" >&2
        return 2
    fi
    local line tabs id an asrc fn fsrc na ck mv stt url extra n=0 sf sn
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        [[ -z "$line" || "$line" == \#* ]] && continue
        tabs="${line//[^$'\t']/}"
        IFS=$'\t' read -r id an asrc fn fsrc na ck mv stt url extra <<< "$line"
        if [[ ${#tabs} -ne 9 || -z "$url" || -n "$extra" ]] || ! _pkg_name_ok "$id" \
                || [[ ! "$stt" =~ ^fedora=([a-z-]+)\;nixos=([a-z-]+)$ ]]; then
            echo "  Malformed package map line $n — refusing to use the map." >&2
            return 2
        fi
        # Zapamiętaj od razu: _pkg_name_ok niżej nadpisuje BASH_REMATCH.
        sf="${BASH_REMATCH[1]}"; sn="${BASH_REMATCH[2]}"
        # arch_name: dokładnie jedna nazwa; fedora_names: „-” albo same nazwy.
        if ! _pkg_name_ok "$an" || ! _pkg_names_ok "$fn" || { [[ "$sf" == ok ]] && [[ "$fn" == - ]]; }; then
            echo "  Invalid package name in map line $n — refusing to use the map." >&2
            return 2
        fi
        if ! _pkg_row_ok "$asrc" "$fsrc" "$na" "$ck" "$mv" "$sf" "$sn" "$url" || [[ -n "${_PKG_ARCH[$id]+x}" ]]; then
            echo "  Malformed package map line $n (unknown status/source, inconsistent fields or duplicate id) — refusing to use the map." >&2
            return 2
        fi
        _PKG_ARCH[$id]="$an"; _PKG_ASRC[$id]="$asrc"; _PKG_FNAMES[$id]="$fn"
        _PKG_FSRC[$id]="$fsrc"; _PKG_NIX[$id]="$na"; _PKG_CHECK[$id]="$ck"
        _PKG_MIN[$id]="$mv"; _PKG_SF[$id]="$sf"; _PKG_SN[$id]="$sn"
        _PKG_URL[$id]="$url"
    done < "$map"
    _PKG_MAP_LOADED=1
}

# _pkg_ready <id> — mapa wczytana, platforma wykryta, id znany.
_pkg_ready() {
    _pkg_load_map || return 2
    [[ -n "$PKG_PLATFORM" ]] || pkg_detect || return 4
    if [[ -z "${_PKG_ARCH[$1]+x}" ]]; then
        echo "  Unknown package id: $1 (not in packages/platform-map.tsv)" >&2
        return 2
    fi
}

# _pkg_probe <check> — sonda obecności: cmd:a,b (wszystkie w PATH),
# font:<rodzina> (fc-list). 0 jest, 1 brak, 3 brak sondy.
_pkg_probe() {
    local c fams
    case "$1" in
        cmd:*)
            local -a cmds
            IFS=, read -ra cmds <<< "${1#cmd:}"
            for c in "${cmds[@]}"; do command -v "$c" >/dev/null 2>&1 || return 1; done
            return 0 ;;
        font:*)
            command -v fc-list >/dev/null 2>&1 || return 3
            fams="$(fc-list : family 2>/dev/null)" || return 1
            [[ $'\n'"$fams"$'\n' == *"${1#font:}"* ]] && return 0
            return 1 ;;
    esac
    return 3
}

# Zapytania rpm/pacman: LC_ALL=C (komunikat braku po angielsku niezależnie od
# języka użytkownika) i pusty LANGUAGE — gettext czyta LANGUAGE przy każdym
# locale poza C, także przy C.UTF-8. dnf i pacman -S zostają w języku użytkownika.

# _pkg_rpm_check <nazwa…> — dokładne nazwy przez `rpm -q --qf '%{NAME}\n'`.
# Czytane tylko stdout (stderr rpm idzie do użytkownika) i kod wyjścia:
# 0 = rc 0 i każda nazwa wypisana dokładnie; 1 = rc≠0 i każdej brakującej
# odpowiada „package X is not installed” (PKG_RPM_MISSING); 2 = wszystko inne
# (obca linia — komunikat błędu, inna nazwa z provides —, nazwa bez odpowiedzi,
# rc niezgodny z odpowiedziami).
_pkg_rpm_check() {
    local out line rc n
    local -A want=() seen=() miss=()
    PKG_RPM_MISSING=()
    out="$(LC_ALL=C LANGUAGE='' rpm -q --qf '%{NAME}\n' "$@")"; rc=$?
    for n in "$@"; do want[$n]=1; done
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^package\ (.+)\ is\ not\ installed$ && -n "${want[${BASH_REMATCH[1]}]:-}" ]]; then
            miss[${BASH_REMATCH[1]}]=1
        elif [[ -n "${want[$line]:-}" ]]; then
            seen[$line]=1
        else
            return 2
        fi
    done <<< "$out"
    for n in "${!want[@]}"; do
        [[ -n "${seen[$n]:-}" && -n "${miss[$n]:-}" ]] && return 2
        [[ -n "${seen[$n]:-}" || -n "${miss[$n]:-}" ]] || return 2
    done
    for n in "$@"; do
        [[ -n "${miss[$n]:-}" && " ${PKG_RPM_MISSING[*]} " != *" $n "* ]] && PKG_RPM_MISSING+=("$n")
    done
    if ((${#PKG_RPM_MISSING[@]} == 0)); then
        ((rc == 0)) && return 0
        return 2
    fi
    ((rc != 0)) && return 1
    return 2
}

# _pkg_pacman_query <-Qi|-Q> <nazwa> — zapytanie pacmana (ta sama komenda co
# install.sh [5]); stdout przechodzi dalej. 0 jest; 1 = jedyny komunikat to
# „error: package 'X' was not found”; 2 = inny błąd (baza, uprawnienia…) —
# pacman daje rc 1 w obu przypadkach, więc rozróżnia je tylko tekst.
_pkg_pacman_query() {
    local err rc
    { err="$(LC_ALL=C LANGUAGE='' pacman "$1" "$2" 2>&1 >&3 3>&-)"; rc=$?; } 3>&1
    ((rc == 0)) && return 0
    [[ "$err" == "error: package '$2' was not found" ]] && return 1
    return 2
}

# ── API ──────────────────────────────────────────────────────────────────────

pkg_installed() {
    local id="$1" rc
    _pkg_ready "$id" || { rc=$?; ((rc == 4)) && return 2; return "$rc"; }
    case "$PKG_PLATFORM" in
        arch)
            # Jak install.sh [5].
            _pkg_pacman_query -Qi "${_PKG_ARCH[$id]}" >/dev/null
            return $? ;;
        fedora)
            if [[ "${_PKG_FNAMES[$id]}" != - ]]; then
                local -a names
                read -ra names <<< "${_PKG_FNAMES[$id]}"
                _pkg_rpm_check "${names[@]}"
                return $?
            fi
            _pkg_probe "${_PKG_CHECK[$id]}"; return $? ;;
        nixos)
            _pkg_probe "${_PKG_CHECK[$id]}"; return $? ;;
    esac
    return 2
}

pkg_hint() {
    local id="$1" names src url
    _pkg_ready "$id" || return 2
    url="${_PKG_URL[$id]}"
    case "$PKG_PLATFORM" in
        arch)
            if [[ "${_PKG_ASRC[$id]}" == aur ]]; then
                echo "yay -S --needed ${_PKG_ARCH[$id]}   (AUR)"
            else
                echo "sudo pacman -S --needed ${_PKG_ARCH[$id]}"
            fi ;;
        fedora)
            names="${_PKG_FNAMES[$id]}"; src="${_PKG_FSRC[$id]}"
            case "${_PKG_SF[$id]}" in
                ok)
                    case "$src" in
                        fedora) echo "sudo dnf install ${PKG_FEDORA_REPOS[*]} $names" ;;
                        copr:*) echo "sudo dnf copr enable ${src#copr:} && sudo dnf install $names   (COPR: $url)" ;;
                        vendor:brave) echo "sudo dnf config-manager addrepo --from-repofile=$PKG_BRAVE_REPOFILE && sudo dnf install $names   ($url)" ;;
                        *) echo "Install manually: $url" ;;
                    esac ;;
                manual)
                    if [[ "$src" == rpmfusion-* ]]; then
                        echo "Enable RPM Fusion ($url), then: sudo dnf install $names"
                    else
                        echo "Not packaged for Fedora — install manually: $url"
                    fi ;;
                unavailable) echo "Not available on Fedora: $url" ;;
                system-managed)
                    if [[ "$names" != - ]]; then echo "Managed by Fedora ($names): $url"
                    else echo "Managed by Fedora: $url"; fi ;;
            esac ;;
        nixos)
            names="${_PKG_NIX[$id]}"
            case "${_PKG_SN[$id]}" in
                ok) echo "Add to environment.systemPackages or home.packages: pkgs.${names// / pkgs.}" ;;
                system-managed)
                    if [[ "$names" == - ]]; then echo "Part of the base NixOS system"
                    else echo "Configure the NixOS option $names in configuration.nix"; fi ;;
                *) echo "Not available on NixOS: $url" ;;
            esac ;;
    esac
}

# _pkg_nix_version <id> — NixOS: wersja ze ścieżki sklepu, do której prowadzi
# pierwsza komenda sondy (readlink -f: /run/current-system/sw/bin/x albo profil
# użytkownika → <sklep>/<hash>-<nazwa>-<wersja>/bin/x). Nazwa = parseDrvName
# Nixa (wersja zaczyna się od pierwszego „-” z cyfrą) i musi równać się
# atrybutowi z mapy — inaczej (wrapper, inna paczka) wersji nie znamy: 2.
_pkg_nix_version() {
    local id="$1" store="/nix/store" cmd p seg
    _pkg_test && [[ -n "${ARCHENEMY_NIX_STORE:-}" ]] && store="$ARCHENEMY_NIX_STORE"
    [[ "${_PKG_SN[$id]}" == ok && "${_PKG_CHECK[$id]}" == cmd:* ]] || return 2
    cmd="${_PKG_CHECK[$id]#cmd:}"; cmd="${cmd%%,*}"
    p="$(command -v "$cmd")" || return 1
    p="$(readlink -f -- "$p" 2>/dev/null)" || return 2
    [[ "$p" == "$store"/* ]] || return 2
    seg="${p#"$store"/}"; seg="${seg%%/*}"
    [[ "$seg" =~ ^[0-9a-z]{32}-([^-]+(-[^0-9][^-]*)*)-([0-9][^/]*)$ ]] || return 2
    [[ "${BASH_REMATCH[1]}" == "${_PKG_NIX[$id]%% *}" ]] || return 2
    printf '%s\n' "${BASH_REMATCH[3]}"
}

pkg_version_ge() {
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

pkg_min_version() {
    _pkg_ready "$1" || return 2
    [[ "${_PKG_MIN[$1]}" != - ]] || return 1
    printf '%s\n' "${_PKG_MIN[$1]}"
}

pkg_version() {
    local id="$1" v first min rc
    _pkg_ready "$id" || return 2
    case "$PKG_PLATFORM" in
        nixos)
            v="$(_pkg_nix_version "$id")" || return $? ;;
        arch)
            v="$(_pkg_pacman_query -Q "${_PKG_ARCH[$id]}")" || return $?
            v="${v#* }"; v="${v#*:}"; v="${v%-*}" ;;
        fedora)
            [[ "${_PKG_FNAMES[$id]}" != - ]] || return 2
            read -r first _ <<< "${_PKG_FNAMES[$id]}"
            _pkg_rpm_check "$first"; rc=$?
            ((rc == 0)) || return "$rc"
            v="$(LC_ALL=C LANGUAGE='' rpm -q --qf '%{VERSION}\n' "$first" 2>/dev/null)" || return 2 ;;
        *) return 2 ;;
    esac
    [[ -n "$v" ]] || return 2
    printf '%s\n' "$v"
    min="${_PKG_MIN[$id]}"
    if [[ "$min" != - ]] && ! pkg_version_ge "$v" "$min"; then
        return 3
    fi
    return 0
}

# _pkg_fedora_verify <nazwa…> — po dnf: sukces = rpm -q każdej nazwy.
_pkg_fedora_verify() {
    _pkg_rpm_check "$@"
    case $? in
        0) return 0 ;;
        1) PKG_FAILED+=("${PKG_RPM_MISSING[@]}") ;;
        *) PKG_FAILED+=("$@") ;;
    esac
    return 1
}

# Repozytoria dla fedora_source=fedora (decyzja właściciela „A”, 2026-11-17):
# DNF5 `--repo` włącza w tej transakcji WYŁĄCZNIE wskazane repozytoria, więc
# pakiet z mapy „fedora” nie przyjdzie z COPR-a ani repo producenta, które
# użytkownik ma włączone. COPR/Brave (pkg_install_extra) — bez --repo.
PKG_FEDORA_REPOS=(--repo=fedora --repo=updates)

# _pkg_dnf_install [--fedora-repos] <nazwa…> — `sudo dnf install` (bez -y: dnf
# pyta sam), z --fedora-repos ograniczony do PKG_FEDORA_REPOS; wynik =
# _pkg_fedora_verify. Sukces to odczytany stan, nie kod dnf: przy kodzie ≠ 0
# i komplecie nazw w rpm (np. błąd scriptletu, nazwy już były) wynik 0, ale
# z ostrzeżeniem.
_pkg_dnf_install() {
    local rc
    local -a repos=()
    [[ "${1:-}" == --fedora-repos ]] && { repos=("${PKG_FEDORA_REPOS[@]}"); shift; }
    sudo dnf install "${repos[@]}" "$@"; rc=$?
    _pkg_fedora_verify "$@" || return 1
    ((rc == 0)) || echo "  ⚠ dnf exited with code $rc, but rpm reports all of these installed: $*"
    return 0
}

pkg_install() {
    local id rc=0 n
    local -a pac=() aur=() fed=() names
    PKG_SKIPPED=(); PKG_FAILED=()
    _pkg_load_map || return 2
    if [[ -z "$PKG_PLATFORM" ]]; then pkg_detect || return 4; fi
    for id in "$@"; do
        _pkg_ready "$id" || return 2
    done
    case "$PKG_PLATFORM" in
        nixos)
            echo "  NixOS is declarative — archenemy installs nothing. Add these to your configuration:"
            for id in "$@"; do echo "    $id: $(pkg_hint "$id")"; done
            PKG_SKIPPED=("$@")
            return 5 ;;
        arch)
            for id in "$@"; do
                if [[ "${_PKG_ASRC[$id]}" == aur ]]; then aur+=("${_PKG_ARCH[$id]}")
                else pac+=("${_PKG_ARCH[$id]}"); fi
            done
            # Te same komendy co install.sh [5] (pacman) i aur.sh (yay).
            if ((${#pac[@]})); then
                if ! sudo pacman -S --needed "${pac[@]}"; then
                    for n in "${pac[@]}"; do pacman -Qi "$n" &>/dev/null || PKG_FAILED+=("$n"); done
                    ((${#PKG_FAILED[@]})) || PKG_FAILED=("${pac[@]}")
                    rc=1
                fi
            fi
            if ((${#aur[@]})); then
                if ! command -v yay >/dev/null 2>&1; then
                    echo "  yay not available — skipping AUR packages: ${aur[*]}"
                    PKG_FAILED+=("${aur[@]}"); rc=1
                else
                    if ! declare -F aur_install >/dev/null; then
                        # shellcheck source=install/lib/aur.sh
                        source "$PKG_LIB_DIR/aur.sh"
                    fi
                    aur_install "${aur[@]}" || { PKG_FAILED+=("${aur[@]}"); rc=1; }
                fi
            fi
            return "$rc" ;;
        fedora)
            for id in "$@"; do
                if [[ "${_PKG_SF[$id]}" == ok && "${_PKG_FSRC[$id]}" == fedora ]]; then
                    read -ra names <<< "${_PKG_FNAMES[$id]}"
                    fed+=("${names[@]}")
                else
                    PKG_SKIPPED+=("$id")
                fi
            done
            if ((${#fed[@]})); then
                # Bez -y i bez flag maskujących braki: jedna nieznana nazwa =
                # odmowa całej transakcji, widoczna dla użytkownika.
                _pkg_dnf_install --fedora-repos "${fed[@]}" || rc=1
            fi
            ((rc)) && return 1
            ((${#PKG_SKIPPED[@]})) && return 3
            return 0 ;;
    esac
    return 4
}

# _pkg_confirm <pytanie> — [y/N]; tylko „y”/„Y” to zgoda (Enter, EOF = nie).
_pkg_confirm() {
    local ans=""
    read -rp "$1 [y/N]: " ans || return 1
    [[ "$ans" =~ ^[Yy]$ ]]
}

_pkg_repos_dir() {
    if _pkg_test && [[ -n "${ARCHENEMY_YUM_REPOS_DIR:-}" ]]; then
        printf '%s\n' "$ARCHENEMY_YUM_REPOS_DIR"
    else
        printf '%s\n' /etc/yum.repos.d
    fi
}

pkg_install_extra() {
    local id rc=0 src
    local -a copr=() brave=() names
    PKG_SKIPPED=(); PKG_FAILED=()
    _pkg_load_map || return 2
    if [[ -z "$PKG_PLATFORM" ]]; then pkg_detect || return 4; fi
    for id in "$@"; do _pkg_ready "$id" || return 2; done
    if [[ "$PKG_PLATFORM" != fedora ]]; then
        echo "  pkg_install_extra applies to Fedora only (platform: $PKG_PLATFORM)." >&2
        return 2
    fi
    for id in "$@"; do
        src="${_PKG_FSRC[$id]}"
        read -ra names <<< "${_PKG_FNAMES[$id]}"
        if [[ "${_PKG_SF[$id]}" == ok && "$src" == "copr:$PKG_COPR_PROJECT" ]]; then copr+=("${names[@]}")
        elif [[ "${_PKG_SF[$id]}" == ok && "$src" == vendor:brave ]]; then brave+=("${names[@]}")
        else PKG_SKIPPED+=("$id")
        fi
    done

    if ((${#copr[@]})); then
        echo "  Source: COPR $PKG_COPR_PROJECT — a community repository, not Fedora's own builds."
        echo "  $PKG_COPR_URL"
        echo "  Packages: ${copr[*]}"
        [[ " $PKG_COPR_VERIFIED " == *" $PKG_OS_VERSION "* ]] \
            || echo "  ⚠ This COPR was checked for Fedora $PKG_COPR_VERIFIED, not ${PKG_OS_VERSION:-?}."
        echo "  Commands: sudo dnf install dnf5-plugins; sudo dnf copr enable $PKG_COPR_PROJECT; sudo dnf install ${copr[*]}"
        if _pkg_confirm "  Enable COPR $PKG_COPR_PROJECT and install these packages?"; then
            if sudo dnf install dnf5-plugins && sudo dnf copr enable "$PKG_COPR_PROJECT"; then
                _pkg_dnf_install "${copr[@]}" || rc=1
            else
                echo "  ✗ Could not enable COPR $PKG_COPR_PROJECT."
                PKG_FAILED+=("${copr[@]}"); rc=1
            fi
        else
            echo "  COPR $PKG_COPR_PROJECT not enabled at your request."
            PKG_SKIPPED+=("${copr[@]}")
        fi
    fi

    if ((${#brave[@]})); then
        echo "  Source: Brave's own RPM repository ($PKG_BRAVE_URL)."
        echo "  Repository file: $PKG_BRAVE_REPOFILE"
        echo "  Packages: ${brave[*]}"
        if _pkg_confirm "  Add the Brave repository and install ${brave[*]}?"; then
            local ok_repo=0
            if [[ -e "$(_pkg_repos_dir)/brave-browser.repo" ]]; then
                ok_repo=1
            elif sudo dnf install dnf5-plugins \
                    && sudo dnf config-manager addrepo --from-repofile="$PKG_BRAVE_REPOFILE"; then
                ok_repo=1
            fi
            if ((ok_repo)); then
                _pkg_dnf_install "${brave[@]}" || rc=1
            else
                echo "  ✗ Could not add the Brave repository."
                PKG_FAILED+=("${brave[@]}"); rc=1
            fi
        else
            echo "  Brave repository not added at your request."
            PKG_SKIPPED+=("${brave[@]}")
        fi
    fi
    ((rc)) && return 1
    ((${#PKG_SKIPPED[@]})) && return 3
    return 0
}
