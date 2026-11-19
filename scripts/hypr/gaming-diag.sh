#!/usr/bin/env bash

# =============================================
#   archenemy - gaming-diag.sh
#   Zrzut stanu GPU/gier do diagnozy (TYLKO ODCZYT — niczego nie zmienia,
#   nie wymaga sudo). Odpowiada na pytania:
#     - które GPU system w ogóle widzi (iGPU / NVIDIA) i czy dGPU nie jest
#       wyłączony sprzętowo (ASUS: dgpu_disable / tryb MUX),
#     - czy sterownik NVIDII pasuje do działającego jądra (moduł, DKMS,
#       biblioteki 64-bit vs 32-bit), czy dGPU zasypia i się budzi,
#     - na którym GPU renderuje Hyprland i z jakimi zmiennymi środowiska,
#     - które pakiety ASUS/GPU są zainstalowane i kiedy się zmieniały,
#     - co obciąża maszynę (animowana tapeta, profil energii, zasilanie),
#     - jeśli gra jest uruchomiona: na którym GPU FAKTYCZNIE się liczy.
#
#   Platforma (D9) z install/lib/pkg.sh (pkg_route, sam odczyt os-release):
#     Arch i pochodne — pacman (-Q, -Qm = pakiety obce: AUR albo inne źródło
#       spoza baz sync, nie dowód AUR), pacman.log, mkinitcpio;
#     Fedora — jedno `rpm -qa` (wersje, architektury, Vendor: spoza
#       repozytoriów Fedory = COPR/RPM Fusion/producent), rpm -qf, czas
#       instalacji z bazy rpm zamiast historii, dracut; bez dnf (sieć, cache);
#     NixOS — bez nix CLI: wersje ze ścieżek sklepu Nix uruchamianych
#       poleceń i /run/opengl-driver(-32); AUR, historia i initramfs nie
#       dotyczą (deklaratywnie);
#     nieznana — bez zgadywania menedżera pakietów (żadnego obcego pacmana).
#   Brak jednostki albo ścieżki to nie awaria; czego nie dało się sprawdzić,
#   trafia do sekcji „kompletność” i znacznika w ostatniej linii:
#     diagnosis: complete                         → kod 0
#     diagnosis: partial; not checked: a, b       → kod 2
#
#   Użycie: gaming-diag.sh [> plik]
#           gaming-diag.sh --doctor   (archenemy doctor --full: tylko sondy
#             pakietów/sterownika, bez nvidia-smi i bez danych prywatnych —
#             wypisuje wyłącznie znacznik)
#   Najlepiej dwa razy: raz bez gry, raz w trakcie gry (okno gry otwarte).
#   Wynik zawiera opisy sprzętu (modele, numery seryjne monitorów) — do
#   prywatnej diagnozy, nie do publicznego zgłoszenia.
#   Haki testowe (tylko ARCHENEMY_TEST=1): ARCHENEMY_FS_ROOT — korzeń atrapy
#   dla /sys /proc /etc /usr /var /run; ARCHENEMY_NIX_STORE (zamiast
#   /nix/store); ARCHENEMY_QUERY_TIMEOUT (limit zapytań, domyślnie 20 s).
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE=dump
case "${1:-}" in
    "") ;;
    --doctor) MODE=doctor ;;
    *) echo "Usage: gaming-diag.sh [--doctor]" >&2; exit 64 ;;
esac

R=""; NIX_STORE=/nix/store; QT=20
if [[ "${ARCHENEMY_TEST:-}" == 1 ]]; then
    R="${ARCHENEMY_FS_ROOT:-}"
    NIX_STORE="${ARCHENEMY_NIX_STORE:-/nix/store}"
    QT="${ARCHENEMY_QUERY_TIMEOUT:-20}"
fi

section() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
# Wartość pliku sysfs albo „-” (brak pliku = funkcja nieobecna, nie błąd).
sysval() { [[ -r "$1" ]] && tr -d '\n' <"$1" 2>/dev/null || printf -- '-'; }
# Zapytanie bazy pakietów/systemd z limitem: zawieszone źródło = błąd, nie cisza.
# W --doctor limit trzyma doctor (0,35 s, sprzątanie grupy) — bez procesu timeout.
q() { if [[ "$MODE" != doctor ]] && have timeout; then timeout "$QT" "$@"; else "$@"; fi; }

# Czego nie sprawdzono: klucz (kontrakt znacznika) i powód (sekcja kompletność).
NOT_CHECKED=()
NOTES=()
mark() {
    local k
    for k in "${NOT_CHECKED[@]}"; do [[ "$k" == "$1" ]] && return 0; done
    NOT_CHECKED+=("$1"); NOTES+=("$1 — $2")
}

# [.] zamiast \. — awk -v przetwarza sekwencje ucieczki i gubiłby backslash.
GAME_RE='^(steam_app_[0-9]+|gamescope|.*[.]exe)$'

PLATFORM=unknown
if [[ -r "$SELF_DIR/../../install/lib/pkg.sh" ]]; then
    # shellcheck source=../../install/lib/pkg.sh
    if source "$SELF_DIR/../../install/lib/pkg.sh" 2>/dev/null && pkg_route 2>/dev/null; then
        PLATFORM="$PKG_ROUTE"
    fi
fi

# NVIDIA (VGA/3D) na szynie PCI — odczyt sysfs, bez budzenia karty.
nvidia_on_bus() {
    local d v c
    for d in "$R"/sys/bus/pci/devices/*; do
        v=""; c=""
        read -r v < "$d/vendor" 2>/dev/null; read -r c < "$d/class" 2>/dev/null
        [[ "$v" == 0x10de && "$c" == 0x03* ]] && return 0
    done
    return 1
}

# nvidia_compare <nazwa64> <nazwa32> <wersja64> <wersja32> <źródło> — rozjazd
# raportowany na każdej platformie; brak obu to jawny stan, nie cisza.
nvidia_compare() {
    if [[ -n "$3" || -n "$4" ]]; then
        if [[ "$3" == "$4" ]]; then
            echo "$1 = $2: OK ($3)"
        else
            echo "!! ROZJAZD $1 (${3:-BRAK}) vs $2 (${4:-BRAK}) — 32-bitowe gry/Proton"
        fi
    elif nvidia_on_bus; then
        echo "!! $1 / $2: brak obu, choć NVIDIA jest na szynie PCI — nouveau albo sterownik spoza $5"
    else
        echo "$1 / $2: brak obu — bez NVIDII na szynie PCI (porównanie 64/32-bit nie dotyczy)"
    fi
}

# store_name <ścieżka> — „nazwa-wersja” z /nix/store/<hash>-nazwa-wersja/…; 1 = poza sklepem.
store_name() {
    [[ "$1" =~ ^"$NIX_STORE"/[a-z0-9]{32}-([^/]+) ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}

sec_system() {
    section "system"
    echo "date: $(date '+%F %T')"
    echo "kernel: $(uname -r)"
    echo "cmdline: $(cat "$R"/proc/cmdline 2>/dev/null)"
    echo "laptop: $(sysval "$R"/sys/class/dmi/id/sys_vendor) / $(sysval "$R"/sys/class/dmi/id/product_name) / board $(sysval "$R"/sys/class/dmi/id/board_name) / BIOS $(sysval "$R"/sys/class/dmi/id/bios_version)"
    [[ "$PLATFORM" == arch ]] || echo "platforma: $PLATFORM (Arch jest platformą referencyjną; Fedora i NixOS eksperymentalnie)"
    if [[ -d "$ARCHENEMY_DIR/.git" ]]; then
        echo "archenemy: $(git -C "$ARCHENEMY_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git -C "$ARCHENEMY_DIR" log -1 --format='%h %cs %s' 2>/dev/null)"
        echo "installed-head.dat: $(cat "$ARCHENEMY_DIR/data/installed-head.dat" 2>/dev/null || echo BRAK)"
        echo "zmiany w drzewie: $(git -C "$ARCHENEMY_DIR" status --porcelain 2>/dev/null | wc -l)"
    fi
    echo "current rice: $(cat "$ARCHENEMY_DIR/.current_rice" 2>/dev/null || echo BRAK)"
}

# ── pakiety per platforma ────────────────────────────────────────────────────

PKGS=""
RPMS=""

pkgs_arch() {
    local out rc b path owner
    # Jeden wzorzec zamiast listy nazw — łapie też warianty z AUR (-git, -dkms, 580xx).
    if ! have pacman; then
        echo "!! brak polecenia pacman — pakiety nie sprawdzone"
        mark packages "brak polecenia pacman"; mark foreign "brak polecenia pacman"
        mark nvidia-32bit "brak polecenia pacman"
    else
        PKGS="$(q pacman -Q 2>/dev/null)"; rc=$?
        if ((rc != 0)) || [[ -z "$PKGS" ]]; then
            echo "!! pacman -Q nie powiódł się (kod $rc) — pakiety nie sprawdzone"
            mark packages "pacman -Q nie powiódł się (kod $rc)"; PKGS=""
        else
            grep -E '^(linux[^ ]*|nvidia[^ ]*|lib32-nvidia[^ ]*|opencl-nvidia[^ ]*|egl-wayland[^ ]*|mesa|lib32-mesa|vulkan-[^ ]*|lib32-vulkan-[^ ]*|intel-media-driver|libva-[^ ]*|asusctl[^ ]*|rog-control-center[^ ]*|supergfxctl[^ ]*|cardwire[^ ]*|switcheroo-control|power-profiles-daemon|tlp[^ ]*|auto-cpufreq|optimus-manager[^ ]*|envycontrol|gamemode|lib32-gamemode|gamescope[^ ]*|mangohud[^ ]*|steam[^ ]*|hyprland[^ ]*|aquamarine[^ ]*|dkms) ' <<<"$PKGS"
        fi
        # -Qm = obce względem baz sync (AUR albo pakiet z innego źródła);
        # bez wyników pacman kończy się kodem 1 bez komunikatu — to zero, nie błąd.
        echo "--- obce (pacman -Qm: AUR albo inne źródło spoza repozytoriów, filtr GPU/ASUS):"
        out="$(LC_ALL=C q pacman -Qm 2>&1)"; rc=$?
        if { ((rc == 0)) || { ((rc == 1)) && [[ -z "$out" ]]; }; } && ! grep -q '^error: ' <<<"$out"; then
            grep -v '^warning: ' <<<"$out" | grep -Ei 'nvidia|asus|rog-|supergfx|cardwire|linux|mesa|vulkan|hypr' || echo "(brak)"
        else
            echo "!! pacman -Qm nie powiódł się (kod $rc) — pakiety obce nie sprawdzone"
            mark foreign "pacman -Qm nie powiódł się (kod $rc)"
        fi
        if [[ -n "$PKGS" ]]; then
            nvidia_compare nvidia-utils lib32-nvidia-utils \
                "$(awk '$1 == "nvidia-utils" {print $2}' <<<"$PKGS")" \
                "$(awk '$1 == "lib32-nvidia-utils" {print $2}' <<<"$PKGS")" "repozytoriów Archa"
        else
            echo "nvidia-utils vs lib32-nvidia-utils: nie sprawdzono (brak listy pakietów)"
            mark nvidia-32bit "brak listy pakietów"
        fi
    fi
    for b in asusctl rog-control-center supergfxctl; do
        have "$b" || continue
        if ! have pacman; then
            echo "$b → pakiet: nie sprawdzono (brak pacmana)"; mark owners "brak polecenia pacman"; continue
        fi
        path="$(command -v "$b")"
        if owner="$(LC_ALL=C q pacman -Qoq "$path" 2>/dev/null)" && [[ -n "$owner" ]]; then
            echo "$b → pakiet: $owner"
        elif [[ "$(LC_ALL=C q pacman -Qoq "$path" 2>&1 >/dev/null)" == *"No package owns"* ]]; then
            echo "$b → pakiet: żaden (plik spoza pakietów — instalacja ręczna?)"
        else
            echo "$b → pakiet: nie sprawdzono (pacman -Qo nie powiódł się)"; mark owners "pacman -Qo nie powiódł się"
        fi
    done
}

pkgs_fedora() {
    local rc b path out native v64 v32 name
    local -a nvlibs=()
    if ! have rpm; then
        echo "!! brak polecenia rpm — pakiety nie sprawdzone"
        for b in packages foreign nvidia-32bit history; do mark "$b" "brak polecenia rpm"; done
    else
        RPMS="$(LC_ALL=C q rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{INSTALLTIME}\t%{VENDOR}\n' 2>/dev/null)"; rc=$?
        if ((rc != 0)) || [[ -z "$RPMS" ]]; then
            echo "!! rpm -qa nie powiódł się (kod $rc) — pakiety nie sprawdzone"
            for b in packages foreign nvidia-32bit history; do mark "$b" "rpm -qa nie powiódł się (kod $rc)"; done
            RPMS=""
        else
            awk -F'\t' '$1 ~ /^(kernel(-core|-devel|-modules)?|akmods|akmod-nvidia.*|kmod-nvidia.*|xorg-x11-drv-nvidia.*|nvidia-.*|mesa-.*|vulkan-.*|intel-media-driver|libva.*|asusctl.*|rog-control-center|supergfxctl.*|switcheroo-control|power-profiles-daemon|tuned(-ppd)?|gamemode|gamescope|mangohud|steam|hyprland.*|aquamarine|dkms)$/ {print $1, $2, $3}' <<<"$RPMS" | sort
            echo "--- spoza repozytoriów Fedory (Vendor RPM inny niż Fedora Project: COPR, RPM Fusion, producent; filtr GPU/ASUS):"
            awk -F'\t' '$5 != "Fedora Project" && tolower($1) ~ /nvidia|asus|rog-|supergfx|cardwire|kernel|mesa|vulkan|hypr/ {print $1, $2, $3, "[" $5 "]"}' <<<"$RPMS" | sort | grep . || echo "(brak)"
            # Rzeczywiste NAME z rpm -qa (przegląd D8–D10 L3): RPM Fusion
            # xorg-x11-drv-nvidia-libs oraz gałęzie legacy
            # xorg-x11-drv-nvidia-<NNN>xx-libs (580xx: Maxwell/Pascal/Volta,
            # 470xx: Kepler; nazwa ze specu xorg-x11-drv-nvidia-580xx, subpakiet
            # „libs”), negativo17: nvidia-driver-libs. -cuda-libs to CUDA, nie GL.
            native="$(uname -m)"; v64=""; v32=""; name=xorg-x11-drv-nvidia-libs
            nvlibs=(xorg-x11-drv-nvidia-libs)
            mapfile -t -O 1 nvlibs < <(awk -F'\t' '$1 ~ /^xorg-x11-drv-nvidia-[0-9]+xx-libs$/ {print $1}' <<<"$RPMS" | sort -u)
            nvlibs+=(nvidia-driver-libs)
            for b in "${nvlibs[@]}"; do
                v64="$(awk -F'\t' -v n="$b" -v a="$native" '$1 == n && $3 == a {print $2; exit}' <<<"$RPMS")"
                v32="$(awk -F'\t' -v n="$b" '$1 == n && $3 == "i686" {print $2; exit}' <<<"$RPMS")"
                [[ -n "$v64$v32" ]] && { name="$b"; break; }
            done
            nvidia_compare "$name.$native" "$name.i686" "$v64" "$v32" "RPM Fusion"
        fi
    fi
    for b in asusctl rog-control-center supergfxctl; do
        have "$b" || continue
        if ! have rpm; then echo "$b → pakiet: nie sprawdzono (brak rpm)"; mark owners "brak polecenia rpm"; continue; fi
        path="$(readlink -f "$(command -v "$b")")"
        out="$(LC_ALL=C q rpm -qf --qf '%{NAME}\n' "$path" 2>&1)"; rc=$?
        if ((rc == 0)) && [[ -n "$out" ]]; then echo "$b → pakiet: ${out%%$'\n'*}"
        elif [[ "$out" == *"is not owned by any package"* ]]; then echo "$b → pakiet: żaden (plik spoza RPM — instalacja ręczna?)"
        else echo "$b → pakiet: nie sprawdzono (rpm -qf nie powiódł się)"; mark owners "rpm -qf nie powiódł się"; fi
    done
}

pkgs_nixos() {
    local c path n v64 v32 any=0
    echo "NixOS: pakiety deklaratywne — bez nix CLI; wersje ze ścieżek sklepu Nix uruchamianych poleceń:"
    for c in Hyprland hyprctl nvidia-smi vulkaninfo gamescope gamemoderun mangohud steam asusctl supergfxctl; do
        have "$c" || continue
        any=1
        path="$(readlink -f "$(command -v "$c")")"
        if n="$(store_name "$path")"; then echo "$c: $n"
        else echo "$c: poza sklepem Nix (nierozpoznane)"; fi
    done
    ((any)) || echo "(żadne z poleceń GPU/gier nie jest w PATH)"
    echo "--- obce / AUR: nie dotyczy (NixOS)"
    # hardware.graphics: /run/opengl-driver (64-bit) i /run/opengl-driver-32 (enable32Bit).
    v64=""; v32=""
    path="$(readlink -f "$R/run/opengl-driver/lib/libGLX_nvidia.so.0" 2>/dev/null)"
    [[ -e "$R/run/opengl-driver/lib/libGLX_nvidia.so.0" ]] && { v64="$(store_name "$path")" || v64="nierozpoznana"; }
    path="$(readlink -f "$R/run/opengl-driver-32/lib/libGLX_nvidia.so.0" 2>/dev/null)"
    [[ -e "$R/run/opengl-driver-32/lib/libGLX_nvidia.so.0" ]] && { v32="$(store_name "$path")" || v32="nierozpoznana"; }
    [[ "$v64" == nvidia-x11-* ]] && { v64="${v64#nvidia-x11-}"; v64="${v64%%-*}"; }
    [[ "$v32" == nvidia-x11-* ]] && { v32="${v32#nvidia-x11-}"; v32="${v32%%-*}"; }
    nvidia_compare "/run/opengl-driver" "/run/opengl-driver-32" "$v64" "$v32" "hardware.nvidia (configuration.nix)"
    [[ "$v64" == nierozpoznana || "$v32" == nierozpoznana ]] && mark nvidia-32bit "biblioteka NVIDIA poza sklepem Nix"
    for c in asusctl rog-control-center supergfxctl; do
        have "$c" || continue
        path="$(command -v "$c")"
        if n="$(store_name "$(readlink -f "$path")")"; then echo "$c → pakiet: $n"
        elif [[ "$path" == "$R"/run/wrappers/* ]]; then echo "$c → pakiet: nierozpoznany (wrapper NixOS w /run/wrappers)"; mark owners "wrapper bez ścieżki sklepu"
        else echo "$c → pakiet: nierozpoznany (poza sklepem Nix)"; mark owners "plik poza sklepem Nix"; fi
    done
}

sec_packages() {
    section "pakiety (GPU / ASUS / gry)"
    case "$PLATFORM" in
        arch) pkgs_arch ;;
        fedora) pkgs_fedora ;;
        nixos) pkgs_nixos ;;
        *)
            echo "!! platforma nieobsługiwana albo nieznana — pakiety nie sprawdzone (bez zgadywania menedżera pakietów)"
            for b in packages foreign nvidia-32bit owners; do mark "$b" "nieznana platforma"; done ;;
    esac
}

sec_history() {
    local ts rest
    case "$PLATFORM" in
        arch)
            section "historia pacmana (GPU / jądro / ASUS / Hyprland, ostatnie 40)"
            if [[ -r "$R"/var/log/pacman.log && -f "$R"/var/log/pacman.log ]]; then
                grep -E '\[ALPM\] (installed|upgraded|downgraded|removed) (linux[^ ]*|nvidia[^ ]*|lib32-nvidia[^ ]*|mesa|lib32-mesa|vulkan-[^ ]*|asusctl[^ ]*|rog-control-center[^ ]*|supergfxctl[^ ]*|cardwire[^ ]*|power-profiles-daemon|hyprland|aquamarine) ' \
                    "$R"/var/log/pacman.log | tail -n 40
            elif [[ -e "$R"/var/log/pacman.log ]]; then
                echo "!! /var/log/pacman.log nieczytelny — historia nie sprawdzona"
                mark history "/var/log/pacman.log nieczytelny"
            else
                echo "(brak /var/log/pacman.log)"
                mark history "brak /var/log/pacman.log"
            fi ;;
        fedora)
            section "historia RPM (czas instalacji z bazy rpm — tylko obecne wersje, bez dnf history; ostatnie 40)"
            if [[ -n "$RPMS" ]]; then
                awk -F'\t' '$4 ~ /^[0-9]+$/ && $1 ~ /^(kernel(-core)?|akmod-nvidia|kmod-nvidia.*|xorg-x11-drv-nvidia.*|nvidia-.*|mesa-.*|vulkan-.*|asusctl|rog-control-center|supergfxctl|power-profiles-daemon|hyprland|aquamarine)$/ {print $4 "\t" $1 "-" $2 "." $3}' <<<"$RPMS" \
                    | sort -n | tail -n 40 | while IFS=$'\t' read -r ts rest; do printf '%(%F %T)T %s\n' "$ts" "$rest"; done
            else
                echo "(brak danych rpm — patrz sekcja pakietów)"
            fi ;;
        nixos)
            section "historia pakietów"
            echo "nie dotyczy (NixOS: zmiany to generacje systemu — nie są wypisywane)" ;;
        *)
            section "historia pakietów"
            echo "!! nieznana platforma — historia nie sprawdzona"
            mark history "nieznana platforma" ;;
    esac
}

sec_pci() {
    local c dev drv conns r d p
    section "GPU na szynie PCI"
    if have lspci; then
        lspci -nnk 2>/dev/null | grep -EA3 'VGA|3D controller|Display controller' | grep -Ev '^\s*Subsystem'
    else
        echo "BRAK lspci (pciutils)"
    fi
    echo "--- karty DRM (boot_vga=1 → tę Hyprland bierze domyślnie)"
    for c in "$R"/sys/class/drm/card[0-9]; do
        [[ -e "$c" ]] || { echo "(brak /sys/class/drm/card*)"; break; }
        dev="$(readlink -f "$c/device")"
        drv="$(basename "$(readlink -f "$c/device/driver" 2>/dev/null)" 2>/dev/null)"
        conns="$(for k in "$c"-*; do [[ -e "$k/status" ]] && printf '%s=%s ' "${k##*/"${c##*/}"-}" "$(sysval "$k/status")"; done)"
        printf '%s: pci=%s vendor=%s driver=%s boot_vga=%s | %s\n' "${c##*/}" "${dev##*/}" \
            "$(sysval "$c/device/vendor")" "${drv:--}" "$(sysval "$c/device/boot_vga")" "$conns"
    done
    for r in "$R"/sys/class/drm/renderD*; do
        [[ -e "$r" ]] || continue
        printf '%s: driver=%s\n' "${r##*/}" "$(basename "$(readlink -f "$r/device/driver" 2>/dev/null)" 2>/dev/null)"
    done
    echo "--- dGPU NVIDIA: zasilanie (odczyt PRZED nvidia-smi — nvidia-smi budzi kartę)"
    NV_FOUND=0
    for d in "$R"/sys/bus/pci/devices/*; do
        [[ "$(sysval "$d/vendor")" == "0x10de" ]] || continue
        [[ "$(sysval "$d/class")" == 0x03* ]] || continue
        NV_FOUND=1
        printf '%s: runtime_status=%s control=%s power_state=%s d3cold_allowed=%s link=%s x%s\n' "${d##*/}" \
            "$(sysval "$d/power/runtime_status")" "$(sysval "$d/power/control")" "$(sysval "$d/power_state")" \
            "$(sysval "$d/d3cold_allowed")" "$(sysval "$d/current_link_speed")" "$(sysval "$d/current_link_width")"
    done
    [[ "$NV_FOUND" -eq 0 ]] && echo "!! brak urządzenia NVIDIA (VGA/3D) na szynie PCI"
    for p in "$R"/proc/driver/nvidia/gpus/*/power; do
        [[ -r "$p" ]] && { echo "--- ${p#"$R"}"; cat "$p"; }
    done
}

# unit_state <jednostka> ae|ea — stan usługi; brak jednostki ≠ awaria.
unit_state() {
    local u="$1" a e
    if ! have systemctl; then
        echo "$u: nie sprawdzono (brak systemctl)"; mark services "brak systemctl"; return
    fi
    a="$(q systemctl is-active "$u" 2>/dev/null)"
    e="$(q systemctl is-enabled "$u" 2>/dev/null)"
    if [[ -z "$e" || "$e" == not-found ]] && [[ "$(q systemctl show -p LoadState --value "$u" 2>/dev/null)" == not-found ]]; then
        echo "$u: brak jednostki (nie zainstalowana — to nie awaria)"; return
    fi
    [[ -z "$a" ]] && mark services "systemctl nie odpowiada"
    if [[ "$2" == ae ]]; then echo "$u: active=$a enabled=$e"; else echo "$u: enabled=$e active=$a"; fi
}

sec_asus() {
    local a u
    section "ASUS (dGPU / MUX / profil)"
    for a in dgpu_disable gpu_mux_mode egpu_enable throttle_thermal_policy; do
        echo "asus-nb-wmi/$a: $(sysval "$R/sys/devices/platform/asus-nb-wmi/$a")"
    done
    if [[ -d "$R"/sys/class/firmware-attributes/asus-armoury/attributes ]]; then
        for a in dgpu_disable gpu_mux_mode egpu_enable; do
            echo "asus-armoury/$a: $(sysval "$R/sys/class/firmware-attributes/asus-armoury/attributes/$a/current_value")"
        done
    else
        echo "asus-armoury: brak (/sys/class/firmware-attributes/asus-armoury)"
    fi
    echo "platform_profile: $(sysval "$R"/sys/firmware/acpi/platform_profile) (dostępne: $(sysval "$R"/sys/firmware/acpi/platform_profile_choices))"
    have asusctl && echo "asusctl: $(timeout 5 asusctl --version 2>&1 | head -n 3 | tr '\n' ' ')"
    for u in asusd power-profiles-daemon supergfxd; do unit_state "$u" ae; done
    have powerprofilesctl && echo "powerprofilesctl get: $(timeout 5 powerprofilesctl get 2>&1)"
    if have supergfxctl; then
        echo "supergfxctl -g: $(timeout 5 supergfxctl -g 2>&1)"
        echo "supergfxctl -S: $(timeout 5 supergfxctl -S 2>&1)"
    fi
    have cardwire && echo "cardwire: zainstalowany ($(command -v cardwire))"
}

sec_power() {
    local s
    section "zasilanie i CPU"
    for s in "$R"/sys/class/power_supply/*; do
        [[ -e "$s/type" ]] || continue
        case "$(sysval "$s/type")" in
            Mains)   echo "${s##*/}: online=$(sysval "$s/online")" ;;
            Battery) echo "${s##*/}: $(sysval "$s/status") $(sysval "$s/capacity")% limit=$(sysval "$s/charge_control_end_threshold")" ;;
        esac
    done
    echo "cpufreq: driver=$(sysval "$R"/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver) governor=$(sysval "$R"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) epp=$(sysval "$R"/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)"
}

# modprobe.d i initramfs — ścieżki per platforma; brak pliku ≠ brak konfiguracji.
nvidia_config() {
    local -a dirs=("$R"/etc/modprobe.d "$R"/usr/lib/modprobe.d) found=() conf=()
    local d
    echo "--- modprobe.d (nvidia/nouveau)"
    [[ "$PLATFORM" == nixos ]] && dirs=("$R"/etc/modprobe.d)
    for d in "${dirs[@]}"; do [[ -d "$d" ]] && found+=("$d"); done
    if ((${#found[@]})); then
        grep -rHs -E 'nvidia|nouveau' "${found[@]}" 2>/dev/null | sed "s#^$R/#/#" | grep -v ':\s*#' || echo "(nic)"
    elif [[ "$PLATFORM" == nixos ]]; then
        echo "(brak /etc/modprobe.d — NixOS: boot.extraModprobeConfig / boot.blacklistedKernelModules)"
    else
        echo "(brak katalogów modprobe.d)"
    fi
    case "$PLATFORM" in
        arch) echo "mkinitcpio: $(grep -E '^MODULES=' "$R"/etc/mkinitcpio.conf 2>/dev/null || echo BRAK)" ;;
        fedora)
            for d in "$R"/etc/dracut.conf "$R"/etc/dracut.conf.d/*.conf "$R"/usr/lib/dracut/dracut.conf.d/*.conf; do
                [[ -f "$d" ]] && conf+=("$d")
            done
            if ((${#conf[@]})); then
                echo "dracut: $(grep -HsE '^[[:space:]]*(add_drivers|force_drivers|omit_drivers)\+?=' "${conf[@]}" | sed "s#^$R/#/#" | tr '\n' ' ')"
            else
                echo "dracut: brak plików dracut.conf (domyślna konfiguracja Fedory)"
            fi ;;
        nixos) echo "initramfs: nie dotyczy (NixOS: boot.initrd.kernelModules w configuration.nix)" ;;
        *) echo "initramfs: nie sprawdzono (nieznana platforma)"; mark initramfs "nieznana platforma" ;;
    esac
}

sec_nvidia() {
    local u
    section "sterownik NVIDIA"
    echo "moduł dla $(uname -r): $(modinfo -F version nvidia 2>/dev/null || echo 'BRAK (modinfo nvidia)')"
    echo "załadowany: $(sysval "$R"/sys/module/nvidia/version)"
    lsmod 2>/dev/null | grep -E '^nvidia' || echo "lsmod: brak modułów nvidia"
    have dkms && { echo "--- dkms status"; dkms status 2>&1; }
    echo "nvidia_drm modeset=$(sysval "$R"/sys/module/nvidia_drm/parameters/modeset) fbdev=$(sysval "$R"/sys/module/nvidia_drm/parameters/fbdev)"
    [[ -r "$R"/proc/driver/nvidia/params ]] && grep -E '^(DynamicPowerManagement|EnableS0ixPowerManagement|PreserveVideoMemoryAllocations):' "$R"/proc/driver/nvidia/params
    nvidia_config
    for u in nvidia-suspend nvidia-hibernate nvidia-resume nvidia-powerd; do unit_state "$u" ea; done
    if have nvidia-smi; then
        echo "--- nvidia-smi"
        timeout 15 nvidia-smi --query-gpu=name,driver_version,pstate,power.draw,clocks.gr,utilization.gpu,temperature.gpu --format=csv 2>&1
        timeout 15 nvidia-smi 2>&1 | sed -n '/Processes:/,$p'
    else
        echo "BRAK nvidia-smi"
    fi
}

sec_klog() {
    local klog
    section "dziennik jądra (bieżący rozruch, GPU/ASUS)"
    klog="$(q journalctl -k -b --no-pager 2>/dev/null)"
    if [[ -n "$klog" ]]; then
        grep -Ei 'nvidia|NVRM|nouveau|i915|xe |amdgpu|asus|drm.*(error|fail)' <<<"$klog" | tail -n 40
    else
        echo "(pusto albo brak dostępu do journalctl -k — użytkownik spoza grupy wheel/systemd-journal)"
        mark kernel-log "journalctl -k pusty albo bez dostępu"
    fi
}

sec_hyprland() {
    local pid o hlog
    section "Hyprland"
    pid="$(pgrep -x Hyprland | head -n 1)"
    if [[ -n "$pid" ]]; then
        echo "--- środowisko procesu Hyprland (GPU)"
        tr '\0' '\n' <"$R/proc/$pid/environ" 2>/dev/null | grep -E '^(AQ_|GBM_|__GLX|__NV|__VK|LIBVA|DRI_PRIME|VK_|WLR_|MESA_)' || echo "(brak zmiennych GPU)"
    fi
    echo "--- gpu-env.lua (warstwa maszynowa)"
    cat "$ARCHENEMY_DIR/config/hypr/gpu-env.lua" 2>/dev/null || echo BRAK
    if have hyprctl && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        hyprctl version 2>/dev/null | head -n 1
        echo "--- hyprctl monitors"
        hyprctl monitors 2>/dev/null | grep -E '^Monitor|description|currentFormat|vrr|solitary|activelyTearing|tearingBlockedBy|directScanoutTo|directScanoutBlockedBy|availableModes' | sed 's/availableModes: \(.\{120\}\).*/availableModes: \1…/'
        for o in render:direct_scanout misc:vrr general:allow_tearing cursor:no_hardware_cursors; do
            echo "$o = $(hyprctl getoption "$o" 2>/dev/null | head -n 1)"
        done
        echo "configerrors: $(hyprctl configerrors 2>/dev/null | head -n 5 | tr '\n' ' ')"
        hlog="${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"
        if [[ -r "$hlog" ]]; then
            echo "--- log Hyprlanda (DRM/GPU/renderer)"
            grep -Ei 'drm|gpu|renderer|egl|nvidia|primary|explicit sync|backend' "$hlog" | head -n 40
        fi
    else
        echo "(poza sesją Hyprlanda — pomijam hyprctl)"
        mark hyprland "poza sesją Hyprlanda"
    fi
}

# Pliki ICD Vulkana: FHS na Archu/Fedorze, runtime paths na NixOS.
vulkan_icd() {
    local d f names
    local -a dirs
    case "$PLATFORM" in
        arch)
            if [[ -d "$R"/usr/share/vulkan/icd.d ]]; then
                ls "$R"/usr/share/vulkan/icd.d/ 2>/dev/null | tr '\n' ' '; echo
            else
                echo "(brak /usr/share/vulkan/icd.d — żaden sterownik Vulkan nie jest zainstalowany)"
            fi
            return ;;
        nixos) dirs=(/run/opengl-driver/share/vulkan/icd.d /run/opengl-driver-32/share/vulkan/icd.d) ;;
        *) dirs=(/usr/share/vulkan/icd.d /etc/vulkan/icd.d) ;;
    esac
    for d in "${dirs[@]}"; do
        if [[ -d "$R$d" ]]; then
            names=""
            for f in "$R$d"/*; do [[ -e "$f" ]] && names+="${f##*/} "; done
            echo "$d: ${names:-(pusto)}"
        else echo "$d: brak"; fi
    done
    if [[ "$PLATFORM" == unknown ]] && [[ ! -d "$R${dirs[0]}" && ! -d "$R${dirs[1]}" ]]; then
        mark vulkan-icd "nieznana platforma, brak ścieżek FHS"
    fi
}

sec_vulkan() {
    section "Vulkan / GL"
    vulkan_icd
    if have vulkaninfo; then
        echo "--- vulkaninfo --summary (domyślnie)"
        timeout 15 vulkaninfo --summary 2>/dev/null | grep -E '^GPU[0-9]|deviceName|deviceType|driverName|driverInfo'
        if have prime-run; then
            echo "--- prime-run vulkaninfo --summary"
            timeout 15 prime-run vulkaninfo --summary 2>/dev/null | grep -E '^GPU[0-9]|deviceName|deviceType|driverName'
        fi
    else
        case "$PLATFORM" in
            nixos) echo "BRAK vulkaninfo (pkgs.vulkan-tools)" ;;
            *) echo "BRAK vulkaninfo (pakiet vulkan-tools)" ;;
        esac
    fi
    if [[ "$PLATFORM" == arch ]] || have prime-run; then
        echo "prime-run: $(command -v prime-run || echo BRAK)"
    else
        echo "prime-run: BRAK (archowe nvidia-prime; tu offload przez __NV_PRIME_RENDER_OFFLOAD=1 albo nvidia-offload na NixOS — to nie awaria)"
    fi
    have eglinfo && timeout 10 eglinfo -B 2>/dev/null | grep -E 'Wayland platform|OpenGL core profile renderer|OpenGL renderer' | head -n 4
}

sec_load() {
    section "obciążenie"
    echo "flux-wall: $(pgrep -af 'flux-wall' | grep -v -e gaming-diag -e pgrep | head -n 3 | tr '\n' ';' || true)"
    echo "flux-wall.dat: $(cat "$ARCHENEMY_DIR/data/flux-wall.dat" 2>/dev/null || echo BRAK)"
    echo "waybar procesów: $(pgrep -cx waybar)"
    echo "--- top CPU"
    ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -n 12
    echo "grupy: $(id -nG)"
    have gamemoded && echo "gamemoded -s: $(timeout 5 gamemoded -s 2>&1 | tr '\n' ' ')"
    echo "gamemode.ini: $([[ -f "$HOME/.config/gamemode.ini" ]] && echo jest || echo BRAK)"
    echo "--- Steam: opcje uruchamiania (ile gier z jaką linią)"
    cat "$HOME"/.local/share/Steam/userdata/*/config/localconfig.vdf "$HOME"/.steam/steam/userdata/*/config/localconfig.vdf 2>/dev/null \
        | grep -E '"LaunchOptions"' | sed 's/^[[:space:]]*//' | sort | uniq -c | head -n 15 || echo "(brak localconfig.vdf albo żadna gra nie ma opcji uruchamiania)"
}

sec_gpu_users() {
    local r fd t pid
    section "kto teraz używa GPU (urządzenia otwarte przez procesy)"
    # Mapa renderD → sterownik, żeby było widać, czy proces trzyma iGPU czy NVIDIĘ.
    declare -gA RENDER_DRV=()
    for r in "$R"/sys/class/drm/renderD*; do
        [[ -e "$r" ]] && RENDER_DRV["/dev/dri/${r##*/}"]="$(basename "$(readlink -f "$r/device/driver" 2>/dev/null)" 2>/dev/null)"
    done
    for fd in "$R"/proc/[0-9]*/fd/*; do
        t="$(readlink "$fd" 2>/dev/null)" || continue
        case "$t" in
            /dev/dri/renderD*|/dev/nvidia[0-9]*) ;;
            *) continue ;;
        esac
        pid="${fd#"$R"/proc/}"; pid="${pid%%/*}"
        printf '%s %s %s %s\n' "$pid" "$(cat "$R/proc/$pid/comm" 2>/dev/null)" "$t" "${RENDER_DRV[$t]:-}"
    done | sort -u -k1,1n -k3,3 | awk '{printf "pid=%s %s → %s %s\n", $1, $2, $3, $4} END {if (NR == 0) print "(żaden proces nie trzyma renderD/nvidia)"}'
}

sec_game() {
    local games gpid gcls fd t
    section "gra (okna steam_app_* / gamescope / *.exe)"
    if have hyprctl && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        games="$(hyprctl clients 2>/dev/null | awk -v re="$GAME_RE" '
            /^\tclass: / { cls = $2 }
            /^\tpid: /   { if (cls ~ re) print $2, cls; cls = "" }')"
        if [[ -z "$games" ]]; then
            echo "brak otwartej gry — uruchom grę i odpal skrypt ponownie (ta sekcja pokaże, na którym GPU się liczy)"
        else
            while read -r gpid gcls; do
                echo "gra: $gcls pid=$gpid"
                for fd in "$R"/proc/"$gpid"/fd/*; do
                    t="$(readlink "$fd" 2>/dev/null)" || continue
                    case "$t" in /dev/dri/*|/dev/nvidia*) echo "  otwarte: $t ${RENDER_DRV[$t]:-}" ;; esac
                done | sort -u
                echo "  env: $(tr '\0' '\n' <"$R/proc/$gpid/environ" 2>/dev/null | grep -E '^(__NV_PRIME|__GLX|__VK_LAYER_NV|DRI_PRIME|MESA_VK_DEVICE_SELECT|DXVK_FILTER|VKD3D_FILTER|PROTON_|MANGOHUD|LD_PRELOAD)' | tr '\n' ' ')"
            done <<<"$games"
        fi
    else
        echo "(poza sesją Hyprlanda)"
    fi
}

# diagnosis: complete | partial; not checked: a, b — kontrakt dla doctora i Super+A.
marker() {
    local list
    if ((${#NOT_CHECKED[@]})); then
        list="$(IFS=,; printf '%s' "${NOT_CHECKED[*]}")"
        printf 'diagnosis: partial; not checked: %s\n' "${list//,/, }"
    else
        echo "diagnosis: complete"
    fi
}

[[ "$PLATFORM" == unknown ]] && mark platform "nieobsługiwana albo nieznana dystrybucja (os-release, install/lib/pkg.sh)"
if [[ "$MODE" == doctor ]]; then
    # Doctor odrzuca surowe wyjście: liczy się tylko znacznik na deskryptorze 3.
    exec 3>&1 >/dev/null 2>&1
    sec_packages
    sec_history
    nvidia_config
    vulkan_icd
    marker >&3
    ((${#NOT_CHECKED[@]})) && exit 2
    exit 0
fi

sec_system
sec_packages
sec_history
sec_pci
sec_asus
sec_power
sec_nvidia
sec_klog
sec_hyprland
sec_vulkan
sec_load
sec_gpu_users
sec_game

section "kompletność"
if ((${#NOT_CHECKED[@]})); then
    printf 'nie sprawdzono: %s\n' "${NOTES[@]}"
else
    echo "wszystkie sekcje sprawdzone"
fi
echo
echo "koniec zrzutu"
marker
((${#NOT_CHECKED[@]})) && exit 2
exit 0
