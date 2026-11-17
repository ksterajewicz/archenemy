#!/usr/bin/env bash
# =============================================
#   archenemy - install/lib/pkg.sh
#   Warstwa pakietów per dystrybucja (D4, EKSPERYMENTALNE; Fedora i NixOS
#   w wariancie A, decyzje właściciela 2026-11-17). Arch jest platformą
#   referencyjną: na Archu funkcje wołają DOKŁADNIE te same komendy co
#   install.sh i install/lib/aur.sh (`pacman -Qi`, `sudo pacman -S --needed`,
#   `aur_install` → `yay -S --needed`). install.sh jeszcze tego nie używa (D5).
#
#   Dane: packages/platform-map.tsv — czytane zwykłym `read`, nigdy eval/source;
#   każda nazwa pakietu przechodzi przez whitelistę znaków, zanim trafi do sudo.
#   Source nie robi nic poza definicją funkcji (żadnych zapytań ani instalacji).
#
#   API (komunikaty po angielsku, funkcje nie wychodzą z procesu):
#     pkg_detect             PKG_PLATFORM=arch|fedora|nixos (+ PKG_OS_ID, PKG_OS_VERSION);
#                            0 = obsługiwana, 1 = odmowa (inne ID, Fedora Atomic) — przed
#                            jakimkolwiek zapisem
#     pkg_installed <id>     0 jest, 1 brak, 2 błąd zapytania / nieznany id,
#                            3 nie da się sprawdzić na tej platformie (brak sondy)
#     pkg_install <id…>      tylko domyślne źródło platformy (Arch: pacman + AUR przez yay,
#                            Fedora: `sudo dnf install` z repozytoriów Fedory, sukces = rpm -q
#                            każdej nazwy). 0 wszystko zainstalowane, 1 porażka (PKG_FAILED),
#                            2 nieznany id / zła mapa, 3 część pominięta (PKG_SKIPPED: ręczne,
#                            niedostępne, systemowe albo wymagające pkg_install_extra),
#                            4 platforma nieobsługiwana, 5 NixOS (deklaratywnie — nic nie robi)
#     pkg_install_extra <id…> Fedora: COPR nett00n/hyprland i repo Brave — pokazuje źródło
#                            i URL, pyta [y/N] osobno dla każdego źródła; bez „y” nic nie
#                            włącza. Kody jak pkg_install; inne platformy → 2
#     pkg_hint <id>          jedna linia: jak zainstalować/skonfigurować na tej platformie
#     pkg_version <id>       wypisuje wersję pierwszego pakietu; 0 ok, 1 brak, 2 nie da się
#                            odczytać (NixOS, błąd), 3 poniżej min_version z mapy
#
#   NixOS: nigdy nix-env, nix profile ani nixos-rebuild — tylko sondy i podpowiedzi.
#   Fedora: bez --skip-unavailable/--skip-broken/--allowerasing i bez -y (dnf pyta sam).
#   Haki testowe (tylko ARCHENEMY_TEST=1): ARCHENEMY_OS_RELEASE (plik os-release),
#   ARCHENEMY_OSTREE_MARKER (zamiast /run/ostree-booted), ARCHENEMY_PKG_MAP (mapa),
#   ARCHENEMY_YUM_REPOS_DIR (zamiast /etc/yum.repos.d).
# =============================================

PKG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_PLATFORM=""
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

pkg_detect() {
    local f="" variant marker="/run/ostree-booted"
    if _pkg_test && [[ -n "${ARCHENEMY_OS_RELEASE:-}" ]]; then
        f="$ARCHENEMY_OS_RELEASE"
    elif [[ -r /etc/os-release ]]; then
        f=/etc/os-release
    elif [[ -r /usr/lib/os-release ]]; then
        f=/usr/lib/os-release
    fi
    PKG_PLATFORM=""
    if [[ -z "$f" || ! -r "$f" ]]; then
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

# ── mapa ─────────────────────────────────────────────────────────────────────

_pkg_name_ok() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9+._-]*$ ]]; }

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
    local line tabs id an asrc fn fsrc na ck mv stt url extra n=0 w sf sn
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
        for w in $an $fn; do
            [[ "$w" == - ]] && continue
            _pkg_name_ok "$w" || { echo "  Invalid package name in map line $n — refusing to use the map." >&2; return 2; }
        done
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

# _pkg_rpm_check <nazwa…> — dokładne nazwy przez `rpm -q --qf '%{NAME}\n'`:
# 0 wszystkie są, 1 czegoś brak (PKG_RPM_MISSING), 2 błąd zapytania.
_pkg_rpm_check() {
    local out line
    PKG_RPM_MISSING=()
    out="$(rpm -q --qf '%{NAME}\n' "$@" 2>&1)"
    local -A seen=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^package\ (.+)\ is\ not\ installed$ ]]; then
            PKG_RPM_MISSING+=("${BASH_REMATCH[1]}")
        else
            seen[$line]=1
        fi
    done <<< "$out"
    local n
    for n in "$@"; do
        [[ -n "${seen[$n]:-}" ]] && continue
        [[ " ${PKG_RPM_MISSING[*]} " == *" $n "* ]] && continue
        # Ani nazwa, ani „not installed” — rpm zwrócił coś innego (zepsuta baza…).
        return 2
    done
    ((${#PKG_RPM_MISSING[@]} == 0)) && return 0
    return 1
}

# ── API ──────────────────────────────────────────────────────────────────────

pkg_installed() {
    local id="$1" rc
    _pkg_ready "$id" || { rc=$?; ((rc == 4)) && return 2; return "$rc"; }
    case "$PKG_PLATFORM" in
        arch)
            # Jak install.sh [5].
            pacman -Qi "${_PKG_ARCH[$id]}" &>/dev/null && return 0
            return 1 ;;
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
                        fedora) echo "sudo dnf install $names" ;;
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

pkg_version() {
    local id="$1" v first min rc
    _pkg_ready "$id" || return 2
    case "$PKG_PLATFORM" in
        arch)
            v="$(pacman -Q "${_PKG_ARCH[$id]}" 2>/dev/null)" || return 1
            v="${v#* }"; v="${v#*:}"; v="${v%-*}" ;;
        fedora)
            [[ "${_PKG_FNAMES[$id]}" != - ]] || return 2
            read -r first _ <<< "${_PKG_FNAMES[$id]}"
            _pkg_rpm_check "$first"; rc=$?
            ((rc == 0)) || return "$rc"
            v="$(rpm -q --qf '%{VERSION}\n' "$first" 2>/dev/null)" || return 2 ;;
        *) return 2 ;;
    esac
    [[ -n "$v" ]] || return 2
    printf '%s\n' "$v"
    min="${_PKG_MIN[$id]}"
    if [[ "$min" != - && "$(printf '%s\n%s\n' "$min" "$v" | sort -V | head -n1)" != "$min" ]]; then
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
                sudo dnf install "${fed[@]}"
                _pkg_fedora_verify "${fed[@]}" || rc=1
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
                sudo dnf install "${copr[@]}"
                _pkg_fedora_verify "${copr[@]}" || rc=1
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
                sudo dnf install "${brave[@]}"
                _pkg_fedora_verify "${brave[@]}" || rc=1
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
