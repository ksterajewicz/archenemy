#!/usr/bin/env bash
# =============================================
#   archenemy - tests/gaming-diag.sh
#   Prawdziwy scripts/hypr/gaming-diag.sh (D9) na atrapach poleceń i atrapie
#   korzenia systemu plików (ARCHENEMY_FS_ROOT, tylko z ARCHENEMY_TEST=1):
#   żadna sonda nie czyta hosta (/sys, /proc, /etc, /var, journal, pacman, rpm).
#   Sprawdza per platforma (os-release przez install/lib/pkg.sh):
#     - Arch / pochodna: pakiety, obce (-Qm: zero ≠ błąd), NVIDIA 64/32
#       (zgodne, rozjazd, tylko 32-bit, brak obu bez GPU i z GPU), właściciel
#       binarki (pakiet, żaden, błąd), pacman.log (jest, brak, nieczytelny),
#       brak jednostki ≠ awaria, brak systemctl, pusty journal, poza sesją,
#       brak ICD, zawieszony pacman (limit zapytań);
#     - Fedora: jedno rpm -qa (wiele RPM i architektur, Vendor spoza Fedory),
#       rozjazd i686, biblioteki NVIDII pod rzeczywistą nazwą RPM (bieżące,
#       580xx, 470xx, negativo17; -cuda-libs nie), rpm -qf (pakiet, żaden, błąd), dracut zamiast
#       mkinitcpio, błąd/pusto rpm; obcy pacman ani razu nie wołany;
#     - NixOS: wersje ze ścieżek sklepu, /run/opengl-driver(-32) (zgodne,
#       rozjazd, brak), wrapper /run/wrappers i plik poza sklepem = nierozpoznany,
#       brak FHS (/usr) to nie awaria, historia/initramfs nie dotyczą;
#     - nieznana platforma i brak install/lib/pkg.sh: bez zgadywania, pacman
#       ani rpm nie wołane, znacznik partial z „platform”;
#     - nieudane sondy runtime (nvidia-smi, vulkaninfo, eglinfo: kod ≠ 0 albo
#       limit czasu) = partial z kluczem nvidia-smi/vulkan/egl, kod 2 (L4);
#     - kod 0/2 i znacznik „diagnosis: …” w ostatniej linii; --doctor wypisuje
#       wyłącznie znacznik, bez nvidia-smi i danych prywatnych; zły argument = 64;
#     - Super+A → [i] → 3 (run_diag_dump z appbinds.sh): ✓ Saved tylko przy
#       complete, ⚠ przy jawnym partial, ✗ przy innym kodzie/bez znacznika;
#       workspace-diag jak dotąd.
#   Opcja: GAMING_DIAG_REV=<rewizja sprzed D9, np. 0a3ca91> — scenariusze Archa także na skrypcie
#   z rewizji (ścieżki /sys /proc /etc /usr /var mechanicznie poprzedzone
#   korzeniem atrapy, prefiks usuwany z obu wyjść); dozwolone różnice to
#   wyłącznie wymienione poprawki fałszywych komunikatów i sekcja kompletności.
#   Zapisy tylko w $T (test_isolate, D7F R3).
#   Uruchom: bash tests/gaming-diag.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034,SC1111  # check() robi eval (zmienne czytane w eval, cudzysłowy „…” w etykietach)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
test_isolate "$REPO/tests/gaming-diag.sh" "$@"   # D7F R3: zapisy poza $T wykrywalne
# shellcheck source=tests/lib/timing.sh
source "$REPO/tests/lib/timing.sh"
# Limity czasu testu w jednym miejscu (tests/README-timing.md).
RUN_LIMIT=30        # s — ZABEZPIECZENIE: jeden bieg gaming-diag na atrapach (test_timeout, × ARCHENEMY_TEST_TIME_SCALE)
HANG_QT=1           # s — ARCHENEMY_QUERY_TIMEOUT w scenariuszach zawieszenia (parametr produktu, bez skali)
HANG_MAX=8          # s — KONTRAKT: górna granica całego biegu z jednym zawieszonym źródłem; bez skali —
                    #     większa granica przestałaby odróżniać działający limit zapytań od atrapy „sleep 30”
T="$(mktemp -d)" && [[ -n "$T" && -d "$T" && "$T" != / ]] || exit 1
trap 'rm -rf "${T:?}"' EXIT
test_environment_init "$T" || exit 1
test_timing_init "$T"
export TZ=UTC

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
has()   { [[ "$OUT" == *"$1"* ]]; }
calls() { grep -c "^$1 " "$GD_LOG" 2>/dev/null || true; }

# ─── narzędzia i atrapy ──────────────────────────────────────────────────────
SYSBIN="$T/sysbin"; BIN="$T/bin"; mkdir -p "$SYSBIN" "$BIN" "$T/log"
for c in bash cat grep sed awk tr sort uniq head tail basename dirname readlink wc ls timeout sleep env; do
    p="$(command -v "$c")" || { echo "brak narzędzia $c"; exit 1; }
    ln -s "$p" "$SYSBIN/$c"
done
export GD_LOG="$T/log/calls"

cat > "$BIN/pacman" <<'MOCK'
#!/usr/bin/env bash
echo "pacman $*" >> "$GD_LOG"
[[ "${GD_PACMAN:-ok}" == hang ]] && exec sleep 30
case "$1" in
    -Q)
        if [[ $# -eq 1 ]]; then
            case "${GD_PACMAN:-ok}" in
                fail) echo "error: could not open database" >&2; exit 1 ;;
                empty) exit 0 ;;
            esac
            printf '%s\n' "linux 6.17.1.arch1-1" "mesa 1:25.2.0-1" "hyprland 0.57.2-1" "zlib 1:1.3.1-2" "asusctl 6.3.8-1"
            [[ -n "${GD_NV64:-}" ]] && echo "nvidia-utils $GD_NV64"
            [[ -n "${GD_NV32:-}" ]] && echo "lib32-nvidia-utils $GD_NV32"
            exit 0
        fi
        # pacman -Q <nazwa> — tak pyta rewizja sprzed D9
        [[ "${GD_PACMAN:-ok}" == fail ]] && { echo "error: could not open database" >&2; exit 1; }
        case "$2" in nvidia-utils) v="${GD_NV64:-}" ;; lib32-nvidia-utils) v="${GD_NV32:-}" ;; *) v="" ;; esac
        [[ -n "$v" ]] && { echo "$2 $v"; exit 0; }
        echo "error: package '$2' was not found" >&2; exit 1 ;;
    -Qm)
        case "${GD_QM:-none}" in
            none) exit 1 ;;
            list) printf '%s\n' "asusctl-git 6.3.8.r1-1" "spotify 1.2-1"; exit 0 ;;
            fail) echo "error: could not open database" >&2; exit 1 ;;
        esac ;;
    -Qoq)
        case "${GD_QO:-owned}" in
            owned) echo asusctl; exit 0 ;;
            unowned) echo "error: No package owns $2" >&2; exit 1 ;;
            fail) echo "error: failed to read file '$2': Permission denied" >&2; exit 1 ;;
        esac ;;
esac
exit 1
MOCK

cat > "$BIN/rpm" <<'MOCK'
#!/usr/bin/env bash
echo "rpm $*" >> "$GD_LOG"
[[ "${GD_RPM:-ok}" == hang ]] && exec sleep 30
case "$1" in
    -qa)
        case "${GD_RPM:-ok}" in
            fail) echo "error: rpmdb open failed" >&2; exit 1 ;;
            empty) exit 0 ;;
        esac
        row() { printf '%s\t%s\t%s\t%s\t%s\n' "$@"; }
        row kernel-core 6.17.1-300.fc44 x86_64 1762000000 "Fedora Project"
        row mesa-dri-drivers 25.2.0-1.fc44 x86_64 1762000100 "Fedora Project"
        row mesa-dri-drivers 25.2.0-1.fc44 i686 1762000100 "Fedora Project"
        row hyprland 0.57.2-1.fc44 x86_64 1762000200 "Fedora Copr - user nett00n"
        row zlib 1.3.1-2.fc44 x86_64 1762000050 "Fedora Project"
        # GD_NV_NAME: rzeczywista NAZWA RPM bibliotek (RPM Fusion 580xx/470xx, negativo17).
        [[ -n "${GD_NV64:-}" ]] && row "${GD_NV_NAME:-xorg-x11-drv-nvidia-libs}" "$GD_NV64" x86_64 1762000300 "RPM Fusion"
        [[ -n "${GD_NV32:-}" ]] && row "${GD_NV_NAME:-xorg-x11-drv-nvidia-libs}" "$GD_NV32" i686 1762000301 "RPM Fusion"
        exit 0 ;;
    -qf)
        case "${GD_RPMQF:-owned}" in
            owned) echo asusctl; exit 0 ;;
            unowned) echo "file ${4:-?} is not owned by any package"; exit 1 ;;
            fail) echo "error: rpmdb open failed" >&2; exit 1 ;;
        esac ;;
esac
exit 1
MOCK

cat > "$BIN/systemctl" <<'MOCK'
#!/usr/bin/env bash
echo "systemctl $*" >> "$GD_LOG"
u="${*: -1}"
case "$1" in
    is-active) [[ "${GD_UNITS:-ok}" == missing ]] && { echo inactive; exit 3; }; echo active ;;
    is-enabled)
        [[ "${GD_UNITS:-ok}" == missing ]] && { echo "Failed to get unit file state for $u.service: No such file or directory" >&2; exit 1; }
        echo enabled ;;
    show) [[ "${GD_UNITS:-ok}" == missing ]] && echo not-found || echo loaded ;;
esac
exit 0
MOCK

cat > "$BIN/journalctl" <<'MOCK'
#!/usr/bin/env bash
echo "journalctl $*" >> "$GD_LOG"
[[ "${GD_KLOG:-ok}" == ok ]] && echo "Nov 18 12:00:00 host kernel: NVRM: loading NVIDIA UNIX Open Kernel Module 580.95"
exit 0
MOCK

cat > "$BIN/hyprctl" <<'MOCK'
#!/usr/bin/env bash
echo "hyprctl $*" >> "$GD_LOG"
case "$1" in
    version) echo "Hyprland 0.57.2 built from branch" ;;
    monitors) printf 'Monitor eDP-1 (ID 0):\n\tdescription: Panel SERIAL-EDID-PRIVATE-123\n' ;;
    getoption) echo "int: 1" ;;
    configerrors) : ;;
    clients) printf 'Window 1 -> game:\n\tclass: steam_app_123\n\tpid: 4242\n' ;;
esac
exit 0
MOCK

printf '#!/usr/bin/env bash\ncase "$1" in -r) echo 6.17.1-test ;; -m) echo x86_64 ;; *) echo Linux ;; esac\n' > "$BIN/uname"
printf '#!/usr/bin/env bash\necho "2026-11-18 12:00:00"\n' > "$BIN/date"
printf '#!/usr/bin/env bash\necho "00:02.0 VGA compatible controller [0300]: Intel [8086:a7a0]"\necho "\tKernel driver in use: i915"\n' > "$BIN/lspci"
printf '#!/usr/bin/env bash\necho 580.95\n' > "$BIN/modinfo"
printf '#!/usr/bin/env bash\necho "nvidia_drm 139264 1"\n' > "$BIN/lsmod"
printf '#!/usr/bin/env bash\necho "  PID %%CPU %%MEM COMMAND"\necho " 4242 99.0  5.0 fakegame"\n' > "$BIN/ps"
printf '#!/usr/bin/env bash\ncase "$*" in "-x Hyprland") [[ -n "${GD_SESSION:-}" ]] && echo 4243 ;; "-cx waybar") echo 1 ;; *) exit 1 ;; esac\n' > "$BIN/pgrep"
printf '#!/usr/bin/env bash\necho "fixture wheel"\n' > "$BIN/id"
printf '#!/usr/bin/env bash\necho "asusctl $*" >> "$GD_LOG"\necho "asusctl 6.3.8"\n' > "$BIN/asusctl"
# Sondy runtime (L4): GD_NVSMI / GD_VK / GD_EGL = fail → kod 1 (sonda dostępna,
# ale zawodzi), timeout → kod 124 (jak `timeout`), inaczej kod 0.
cat > "$BIN/nvidia-smi" <<'MOCK'
#!/usr/bin/env bash
echo "nvidia-smi $*" >> "$GD_LOG"
case "${GD_NVSMI:-ok}" in
    fail) echo "GPU-PROBE-FAILED: NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver."; exit 1 ;;
    timeout) exit 124 ;;
esac
echo "NVIDIA GeForce RTX, 580.95, P8"
MOCK
mkdir -p "$T/vkbin"
cat > "$T/vkbin/vulkaninfo" <<'MOCK'
#!/usr/bin/env bash
echo "vulkaninfo $*" >> "$GD_LOG"
case "${GD_VK:-ok}" in fail) echo "ERROR: [Loader Message] vkCreateInstance failed" >&2; exit 1 ;; timeout) exit 124 ;; esac
echo "GPU0:"; echo "	deviceName = Intel(R) Graphics"; echo "	driverName = Intel open-source Mesa driver"
MOCK
cat > "$T/vkbin/eglinfo" <<'MOCK'
#!/usr/bin/env bash
echo "eglinfo $*" >> "$GD_LOG"
case "${GD_EGL:-ok}" in fail) exit 1 ;; timeout) exit 124 ;; esac
echo "Wayland platform:"; echo "OpenGL core profile renderer: Mesa Intel(R) Graphics"
MOCK
find "$T/vkbin" -type f -exec chmod +x {} +
find "$BIN" -type f -exec chmod +x {} +   # nie przez dowiązania (D8: chmod podąża za linkami)

# path_without <cmd…> — katalog atrap bez wymienionych poleceń (scenariusz „brak polecenia”).
path_without() {
    local d="$T/pv/$*" f
    d="${d// /_}"; mkdir -p "$d"
    for f in "$BIN"/*; do
        [[ " $* " == *" ${f##*/} "* ]] || ln -sf "$f" "$d/${f##*/}"
    done
    printf '%s\n' "$d"
}

# ─── atrapa korzenia (sysfs, /proc, /etc, /var, /usr) ───────────────────────
# mkroot <katalog> [gpu] — gpu: urządzenie NVIDIA na szynie PCI.
mkroot() {
    local r="$1" dev
    rm -rf "$r"; mkdir -p "$r"
    mkdir -p "$r/sys/devices/pci/0000:00:02.0" "$r/sys/drivers/i915" "$r/sys/class/drm/card0" \
             "$r/sys/class/drm/card0-eDP-1" "$r/sys/class/drm/renderD128" "$r/sys/bus/pci/devices" \
             "$r/sys/class/power_supply/AC" "$r/sys/class/dmi/id" "$r/proc/4242/fd" "$r/proc/4243" \
             "$r/etc/modprobe.d" "$r/usr/lib/modprobe.d" "$r/var/log" "$r/usr/share/vulkan/icd.d"
    dev="$r/sys/devices/pci/0000:00:02.0"
    echo 0x8086 > "$dev/vendor"; echo 0x030000 > "$dev/class"; echo 1 > "$dev/boot_vga"
    ln -s ../../../drivers/i915 "$dev/driver"
    ln -s ../../../devices/pci/0000:00:02.0 "$r/sys/class/drm/card0/device"
    ln -s ../../../devices/pci/0000:00:02.0 "$r/sys/class/drm/renderD128/device"
    ln -s ../../../devices/pci/0000:00:02.0 "$r/sys/bus/pci/devices/0000:00:02.0"
    echo connected > "$r/sys/class/drm/card0-eDP-1/status"
    if [[ "${2:-}" == gpu ]]; then
        dev="$r/sys/devices/pci/0000:01:00.0"; mkdir -p "$dev/power"
        echo 0x10de > "$dev/vendor"; echo 0x030200 > "$dev/class"; echo suspended > "$dev/power/runtime_status"
        ln -s ../../../devices/pci/0000:01:00.0 "$r/sys/bus/pci/devices/0000:01:00.0"
    fi
    echo Mains > "$r/sys/class/power_supply/AC/type"; echo 1 > "$r/sys/class/power_supply/AC/online"
    echo "FIXTURE-VENDOR" > "$r/sys/class/dmi/id/sys_vendor"
    echo "BOOT_IMAGE=/vmlinuz root=UUID=fixture quiet" > "$r/proc/cmdline"
    ln -s /dev/dri/renderD128 "$r/proc/4242/fd/3"; echo fakegame > "$r/proc/4242/comm"
    printf 'AQ_DRM_DEVICES=/dev/dri/card0\0HOME=/x\0' > "$r/proc/4243/environ"
    printf 'DXVK_FILTER=1\0' > "$r/proc/4242/environ"
    echo "options nvidia_drm modeset=1" > "$r/etc/modprobe.d/nvidia.conf"
    echo "MODULES=(nvidia nvidia_drm)" > "$r/etc/mkinitcpio.conf"
    printf '%s\n' "[2026-11-01T10:00:00+0100] [ALPM] upgraded nvidia-utils (580.82-1 -> 580.95-1)" \
                  "[2026-11-01T10:00:01+0100] [ALPM] installed zlib (1.3)" > "$r/var/log/pacman.log"
    touch "$r/usr/share/vulkan/icd.d/intel_icd.x86_64.json" "$r/usr/share/vulkan/icd.d/nvidia_icd.json"
}

# Instalacja skryptu jak w ~/archenemy: scripts/hypr + install/lib/pkg.sh.
A="$HOME/archenemy"
mkdir -p "$A/scripts/hypr" "$A/install/lib" "$A/config/hypr"
cp "$REPO/scripts/hypr/gaming-diag.sh" "$A/scripts/hypr/gaming-diag.sh"
cp "$REPO/install/lib/pkg.sh" "$A/install/lib/pkg.sh"
echo "-- gpu env fixture" > "$A/config/hypr/gpu-env.lua"
echo white-blue > "$A/.current_rice"

osr() { printf '%s\n' "$@" > "$T/os-release"; }
FSR="$T/root"

# gd [ZMIENNA=wartość…] [-- argumenty] — bieg skryptu; OUT (stdout+stderr), RC, CALLS.
gd() {
    local -a vars=() args=()
    while (($#)) && [[ "$1" != -- ]]; do vars+=("$1"); shift; done
    (($#)) && { shift; args=("$@"); }
    : > "$GD_LOG"
    OUT="$(test_timeout "$RUN_LIMIT" env -i HOME="$HOME" TZ=UTC LC_ALL=C.UTF-8 TMPDIR="$TMPDIR" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" GD_LOG="$GD_LOG" \
        PATH="${GD_PATH:-$BIN}:$SYSBIN" ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os-release" \
        ARCHENEMY_FS_ROOT="$FSR" ARCHENEMY_NIX_STORE="$T/nix/store" "${vars[@]}" \
        bash "${GD_SCRIPT:-$A/scripts/hypr/gaming-diag.sh}" "${args[@]}" 2>&1)"
    RC=$?
    OUT="${OUT//"$FSR"/}"
    LAST="${OUT##*$'\n'}"
}

echo "gaming-diag (D9): platformy na atrapach"
SESSION=(GD_SESSION=1 HYPRLAND_INSTANCE_SIGNATURE=fixture)

# ─── Arch ────────────────────────────────────────────────────────────────────
osr 'NAME="Arch Linux"' ID=arch
mkroot "$FSR" gpu
gd "${SESSION[@]}" GD_NV64=580.95-1 GD_NV32=580.95-1
check "Arch komplet: kod 0, ostatnia linia „diagnosis: complete”" '[[ $RC == 0 && "$LAST" == "diagnosis: complete" ]]'
check "Arch: pakiety GPU z pacman -Q, wersje 64/32 zgodne" 'has "nvidia-utils 580.95-1" && has "nvidia-utils = lib32-nvidia-utils: OK (580.95-1)" && ! has "zlib"'
check "Arch: -Qm bez pakietów obcych (kod 1, pusto) = „(brak)”, nie błąd; nagłówek nie nazywa tego AUR-em" 'has "--- obce (pacman -Qm: AUR albo inne źródło" && has "(brak)" && ! has "z AUR"'
check "Arch: właściciel binarki, pacman.log, mkinitcpio, ICD, jednostki" 'has "asusctl → pakiet: asusctl" && has "upgraded nvidia-utils" && has "mkinitcpio: MODULES=(nvidia nvidia_drm)" && has "intel_icd.x86_64.json nvidia_icd.json" && has "asusd: active=active enabled=enabled"'
check "Arch: platforma bez dodatkowej linii (parytet), bez rpm" '! has "platforma:" && [[ $(calls rpm) == 0 ]]'
gd "${SESSION[@]}" GD_NV64=580.95-1 GD_NV32=580.82-1 GD_QM=list
check "Arch rozjazd 64/32 i lista obcych z filtrem" 'has "!! ROZJAZD nvidia-utils (580.95-1) vs lib32-nvidia-utils (580.82-1)" && has "asusctl-git 6.3.8.r1-1" && ! has spotify'
gd "${SESSION[@]}" GD_NV32=580.95-1
check "Arch tylko 32-bit: BRAK zamiast pustych nawiasów" 'has "!! ROZJAZD nvidia-utils (BRAK) vs lib32-nvidia-utils (580.95-1)"'
gd "${SESSION[@]}"
check "Arch brak obu przy NVIDII na szynie: jawny komunikat" 'has "!! nvidia-utils / lib32-nvidia-utils: brak obu, choć NVIDIA jest na szynie PCI" && [[ $RC == 0 ]]'
mkroot "$FSR"
gd "${SESSION[@]}"
check "Arch bez GPU NVIDIA: „bez NVIDII”, to nie awaria (kod 0)" 'has "brak obu — bez NVIDII na szynie PCI" && [[ $RC == 0 && "$LAST" == "diagnosis: complete" ]]'
mkroot "$FSR" gpu
gd "${SESSION[@]}" GD_PACMAN=fail
check "Arch pacman -Q błąd: jawnie, partial packages+nvidia-32bit, kod 2" 'has "!! pacman -Q nie powiódł się" && [[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: packages, nvidia-32bit" ]]'
gd "${SESSION[@]}" GD_PACMAN=empty
check "Arch pacman -Q pusto = błąd sondy, nie zero" '[[ $RC == 2 && "$LAST" == *"packages"* ]]'
gd "${SESSION[@]}" GD_QM=fail GD_NV64=1 GD_NV32=1
check "Arch -Qm błąd ≠ „(brak)”: partial foreign" 'has "!! pacman -Qm nie powiódł się" && ! has "(brak)" && [[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: foreign" ]]'
# L4 (przegląd D8–D10): dostępna, ale nieudana sonda runtime to nie „sprawdzone”.
gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1 GD_NVSMI=fail
check "nvidia-smi kod 1: partial nvidia-smi, kod 2, nie „wszystkie sekcje sprawdzone”" '[[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: nvidia-smi" ]] && has "GPU-PROBE-FAILED" && ! has "wszystkie sekcje sprawdzone" && has "nvidia-smi — nvidia-smi zakończył się kodem 1"'
gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1 GD_NVSMI=timeout
check "nvidia-smi limit czasu: partial nvidia-smi z powodem" '[[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: nvidia-smi" ]] && has "nvidia-smi — nvidia-smi przekroczył limit 15 s"'
GD_PATH="$T/vkbin:$BIN" gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1
check "vulkaninfo i eglinfo działają: complete, kod 0, wyniki w zrzucie" '[[ $RC == 0 && "$LAST" == "diagnosis: complete" ]] && has "deviceName = Intel(R) Graphics" && has "OpenGL core profile renderer: Mesa"'
GD_PATH="$T/vkbin:$BIN" gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1 GD_VK=fail
check "vulkaninfo kod 1: partial vulkan, kod 2" '[[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: vulkan" ]] && has "vulkan — vulkaninfo --summary zakończył się kodem 1"'
GD_PATH="$T/vkbin:$BIN" gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1 GD_EGL=timeout
check "eglinfo limit czasu: partial egl, kod 2" '[[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: egl" ]] && has "egl — eglinfo -B przekroczył limit 10 s"'
GD_PATH="$T/vkbin:$BIN" gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1 GD_NVSMI=fail GD_VK=fail GD_EGL=fail
check "trzy nieudane sondy: wszystkie klucze w znaczniku" '[[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: nvidia-smi, vulkan, egl" ]]'
gd GD_NV64=1 GD_NV32=1 GD_NVSMI=fail -- --doctor
check "--doctor nadal bez nvidia-smi (awaria sondy go nie dotyczy)" '[[ $RC == 0 && "$OUT" == "diagnosis: complete" && $(calls nvidia-smi) == 0 ]]'
gd "${SESSION[@]}" GD_QO=unowned GD_NV64=1 GD_NV32=1
check "Arch binarka spoza pakietów: „żaden”, kompletne" 'has "asusctl → pakiet: żaden" && [[ $RC == 0 ]]'
gd "${SESSION[@]}" GD_QO=fail GD_NV64=1 GD_NV32=1
check "Arch błąd pacman -Qo: partial owners" 'has "pakiet: nie sprawdzono (pacman -Qo" && [[ "$LAST" == *"owners"* && $RC == 2 ]]'
rm "$FSR/var/log/pacman.log"
gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1
check "Arch brak pacman.log: partial history" 'has "(brak /var/log/pacman.log)" && [[ "$LAST" == "diagnosis: partial; not checked: history" ]]'
mkdir "$FSR/var/log/pacman.log"   # root omija bity uprawnień — „nieczytelny” = nie zwykły plik
gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1
check "Arch pacman.log nieczytelny: jawnie, nie „brak”" 'has "!! /var/log/pacman.log nieczytelny" && [[ "$LAST" == *history* ]]'
mkroot "$FSR" gpu
gd "${SESSION[@]}" GD_UNITS=missing GD_NV64=1 GD_NV32=1
check "Arch brak jednostek: „brak jednostki”, to nie awaria (kod 0)" 'has "asusd: brak jednostki (nie zainstalowana" && has "nvidia-powerd: brak jednostki" && [[ $RC == 0 ]]'
GD_PATH="$(path_without systemctl)" gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1
check "Arch bez systemctl: partial services" 'has "asusd: nie sprawdzono (brak systemctl)" && [[ "$LAST" == "diagnosis: partial; not checked: services" ]]'
gd GD_KLOG=empty GD_NV64=1 GD_NV32=1
check "Arch pusty journal i poza sesją: partial kernel-log, hyprland" '[[ "$LAST" == "diagnosis: partial; not checked: kernel-log, hyprland" && $RC == 2 ]]'
rm -rf "$FSR/usr/share/vulkan"
gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1
check "Arch brak katalogu ICD: jawny komunikat zamiast pustej linii" 'has "(brak /usr/share/vulkan/icd.d"'
rmdir "$FSR/usr/lib/modprobe.d"
gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1
check "Arch bez /usr/lib/modprobe.d: trafienie z /etc bez fałszywego „(nic)”" 'has "/etc/modprobe.d/nvidia.conf:options nvidia_drm modeset=1" && ! has "(nic)"'
mkroot "$FSR" gpu
start=$SECONDS
gd "${SESSION[@]}" GD_PACMAN=hang ARCHENEMY_QUERY_TIMEOUT="$HANG_QT"
check "Arch zawieszony pacman: limit zapytań, partial, KONTRAKT: bieg < ${HANG_MAX} s" '[[ $RC == 2 && "$LAST" == *packages* && $((SECONDS - start)) -lt $HANG_MAX ]]'
osr 'NAME="EndeavourOS"' ID=endeavouros ID_LIKE=arch
gd "${SESSION[@]}" GD_NV64=1 GD_NV32=1
check "pochodna Archa (ID_LIKE=arch): ścieżka Archa, komplet" '[[ $RC == 0 && $(calls pacman) -gt 0 ]] && has "mkinitcpio:"'

# ─── tryb --doctor ───────────────────────────────────────────────────────────
osr ID=arch
gd GD_NV64=1 GD_NV32=1 -- --doctor
check "--doctor: jedna linia — sam znacznik, kod 0" '[[ $RC == 0 && "$OUT" == "diagnosis: complete" ]]'
check "--doctor: bez nvidia-smi (nie budzi dGPU), journala, hyprctl, systemctl" '[[ $(calls nvidia-smi) == 0 && $(calls journalctl) == 0 && $(calls hyprctl) == 0 && $(calls systemctl) == 0 ]]'
gd GD_PACMAN=fail -- --doctor
check "--doctor przy błędzie: partial z kluczami, kod 2, nic więcej" '[[ $RC == 2 && "$OUT" == "diagnosis: partial; not checked: packages, nvidia-32bit" ]]'
gd -- --bogus
check "zły argument: kod 64, bez zrzutu" '[[ $RC == 64 && "$OUT" == Usage:* ]]'

# ─── Fedora ──────────────────────────────────────────────────────────────────
osr 'NAME="Fedora Linux"' ID=fedora VERSION_ID=44
gd "${SESSION[@]}" GD_NV64=3:580.95-1.fc44 GD_NV32=3:580.95-1.fc44
check "Fedora komplet: kod 0, jedno rpm -qa, obcy pacman ani razu" '[[ $RC == 0 && "$LAST" == "diagnosis: complete" && $(calls pacman) == 0 && $(grep -c "^rpm -qa" "$GD_LOG") == 1 ]]'
check "Fedora: wiele RPM i architektur (mesa x86_64 + i686), bez obcych nazw" 'has "mesa-dri-drivers 25.2.0-1.fc44 i686" && has "mesa-dri-drivers 25.2.0-1.fc44 x86_64" && ! has "zlib 1.3"'
check "Fedora: spoza repozytoriów = Vendor (COPR, RPM Fusion), nie AUR" 'has "spoza repozytoriów Fedory" && has "hyprland 0.57.2-1.fc44 x86_64 [Fedora Copr - user nett00n]" && has "[RPM Fusion]" && ! has "AUR"'
check "Fedora: NVIDIA x86_64 = i686" 'has "xorg-x11-drv-nvidia-libs.x86_64 = xorg-x11-drv-nvidia-libs.i686: OK (3:580.95-1.fc44)"'
check "Fedora: rpm -qf, historia z czasu instalacji, dracut zamiast mkinitcpio" 'has "asusctl → pakiet: asusctl" && has "historia RPM" && has "2025-11-01 12:31:40 xorg-x11-drv-nvidia-libs-3:580.95-1.fc44.x86_64" && has "dracut:" && ! has "mkinitcpio" && has "platforma: fedora"'
gd "${SESSION[@]}" GD_NV64=3:580.95-1.fc44 GD_NV32=3:580.82-1.fc44
check "Fedora rozjazd i686" 'has "!! ROZJAZD xorg-x11-drv-nvidia-libs.x86_64 (3:580.95-1.fc44) vs xorg-x11-drv-nvidia-libs.i686 (3:580.82-1.fc44)"'
# L3 (przegląd D8–D10): `rpm -qa` zwraca rzeczywiste NAME — gałęzie legacy
# RPM Fusion (xorg-x11-drv-nvidia-580xx-libs, -470xx-libs) i negativo17
# (nvidia-driver-libs) też są bibliotekami NVIDII; -cuda-libs nie jest.
gd "${SESSION[@]}" GD_NV_NAME=xorg-x11-drv-nvidia-580xx-libs GD_NV64=3:580.95-1.fc44 GD_NV32=3:580.82-1.fc44
check "Fedora 580xx (Maxwell/Pascal): rozjazd 64/32 rozpoznany" 'has "!! ROZJAZD xorg-x11-drv-nvidia-580xx-libs.x86_64 (3:580.95-1.fc44) vs xorg-x11-drv-nvidia-580xx-libs.i686 (3:580.82-1.fc44)" && ! has "brak obu"'
gd "${SESSION[@]}" GD_NV_NAME=xorg-x11-drv-nvidia-470xx-libs GD_NV64=3:470.256.02-1.fc44 GD_NV32=3:470.256.02-1.fc44
check "Fedora 470xx (Kepler): zgodne 64/32" 'has "xorg-x11-drv-nvidia-470xx-libs.x86_64 = xorg-x11-drv-nvidia-470xx-libs.i686: OK (3:470.256.02-1.fc44)" && [[ $RC == 0 ]]'
gd "${SESSION[@]}" GD_NV_NAME=nvidia-driver-libs GD_NV32=3:580.95-1.fc44
check "Fedora negativo17: tylko 32-bit = ROZJAZD z BRAK" 'has "!! ROZJAZD nvidia-driver-libs.x86_64 (BRAK) vs nvidia-driver-libs.i686 (3:580.95-1.fc44)"'
gd "${SESSION[@]}" GD_NV_NAME=xorg-x11-drv-nvidia-580xx-cuda-libs GD_NV64=3:580.95-1.fc44 GD_NV32=3:580.95-1.fc44
check "Fedora: -cuda-libs to nie biblioteki GL/Vulkan — brak obu przy GPU" 'has "brak obu, choć NVIDIA jest na szynie PCI"'
gd "${SESSION[@]}"
check "Fedora bez sterownika NVIDIA przy GPU: jawnie, wskazuje RPM Fusion" 'has "brak obu, choć NVIDIA jest na szynie PCI — nouveau albo sterownik spoza RPM Fusion"'
gd "${SESSION[@]}" GD_RPM=fail
check "Fedora rpm -qa błąd: partial packages, foreign, nvidia-32bit, history" '[[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: packages, foreign, nvidia-32bit, history" ]] && has "!! rpm -qa nie powiódł się"'
gd "${SESSION[@]}" GD_RPM=empty
check "Fedora rpm -qa pusto = błąd, nie zero" '[[ $RC == 2 && "$LAST" == *packages* ]]'
gd "${SESSION[@]}" GD_RPMQF=unowned GD_NV64=1 GD_NV32=1
check "Fedora plik spoza RPM: „żaden”" 'has "asusctl → pakiet: żaden (plik spoza RPM" && [[ $RC == 0 ]]'
gd "${SESSION[@]}" GD_RPMQF=fail GD_NV64=1 GD_NV32=1
check "Fedora rpm -qf błąd: partial owners" '[[ "$LAST" == "diagnosis: partial; not checked: owners" ]]'
start=$SECONDS
gd "${SESSION[@]}" GD_RPM=hang ARCHENEMY_QUERY_TIMEOUT="$HANG_QT"
check "Fedora zawieszony rpm: partial, KONTRAKT: bieg < ${HANG_MAX} s" '[[ $RC == 2 && "$LAST" == *packages* && $((SECONDS - start)) -lt $HANG_MAX ]]'
osr ID=fedora VARIANT_ID=silverblue
gd "${SESSION[@]}"
check "Fedora Atomic: nieobsługiwana, bez rpm i pacmana" '[[ $RC == 2 && "$LAST" == *platform* && $(calls rpm) == 0 && $(calls pacman) == 0 ]]'

# ─── NixOS ───────────────────────────────────────────────────────────────────
osr 'NAME=NixOS' ID=nixos
store="$T/nix/store"; H32=0123456789abcdfghijklmnpqrsvwxyz
mkroot "$FSR" gpu
rm -rf "${FSR:?}/usr" "$FSR/etc/mkinitcpio.conf" "$FSR/var/log/pacman.log" "$store" "$T/profile"
mkdir -p "$store/$H32-hyprland-0.57.2/bin" "$store/$H32-nvidia-x11-580.95.05-6.17.1/lib" \
         "$store/${H32/0/1}-nvidia-x11-580.95.05-6.17.1/lib" "$store/$H32-nvidia-x11-580.82.07-6.17.1/lib" \
         "$T/profile/bin" "$FSR/run/opengl-driver/lib" "$FSR/run/opengl-driver/share/vulkan/icd.d" \
         "$FSR/run/opengl-driver-32/lib" "$FSR/run/wrappers/bin"
cp "$BIN/hyprctl" "$store/$H32-hyprland-0.57.2/bin/hyprctl"
touch "$store/$H32-nvidia-x11-580.95.05-6.17.1/lib/libGLX_nvidia.so.0" "$store/${H32/0/1}-nvidia-x11-580.95.05-6.17.1/lib/libGLX_nvidia.so.0" \
      "$store/$H32-nvidia-x11-580.82.07-6.17.1/lib/libGLX_nvidia.so.0" "$FSR/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
ln -s "$store/$H32-hyprland-0.57.2/bin/hyprctl" "$T/profile/bin/hyprctl"
ln -s "$store/$H32-nvidia-x11-580.95.05-6.17.1/lib/libGLX_nvidia.so.0" "$FSR/run/opengl-driver/lib/libGLX_nvidia.so.0"
ln -s "$store/${H32/0/1}-nvidia-x11-580.95.05-6.17.1/lib/libGLX_nvidia.so.0" "$FSR/run/opengl-driver-32/lib/libGLX_nvidia.so.0"
NIXPATH="$T/profile/bin:$(path_without hyprctl asusctl)"
GD_PATH="$NIXPATH" gd "${SESSION[@]}"
check "NixOS komplet bez FHS: kod 0, bez pacmana i rpm (obce w PATH)" '[[ $RC == 0 && "$LAST" == "diagnosis: complete" && $(calls pacman) == 0 && $(calls rpm) == 0 ]]'
check "NixOS: wersja ze ścieżki sklepu, AUR/historia/initramfs nie dotyczą" 'has "hyprctl: hyprland-0.57.2" && has "obce / AUR: nie dotyczy (NixOS)" && has "nie dotyczy (NixOS: zmiany to generacje" && has "initramfs: nie dotyczy (NixOS" && ! has "mkinitcpio"'
check "NixOS: /run/opengl-driver 64 = 32, ICD z runtime paths, brak /usr ≠ awaria" 'has "/run/opengl-driver = /run/opengl-driver-32: OK (580.95.05)" && has "/run/opengl-driver/share/vulkan/icd.d: nvidia_icd.x86_64.json" && ! has "pacman.log"'
check "NixOS: nazwy generacji i ścieżki sklepu z hashem nie trafiają do zrzutu" '! has "$H32"'
ln -sfn "$store/$H32-nvidia-x11-580.82.07-6.17.1/lib/libGLX_nvidia.so.0" "$FSR/run/opengl-driver-32/lib/libGLX_nvidia.so.0"
GD_PATH="$NIXPATH" gd "${SESSION[@]}"
check "NixOS rozjazd 64/32" 'has "!! ROZJAZD /run/opengl-driver (580.95.05) vs /run/opengl-driver-32 (580.82.07)"'
rm -rf "$FSR/run/opengl-driver-32"
GD_PATH="$NIXPATH" gd "${SESSION[@]}"
check "NixOS bez 32-bit (enable32Bit): rozjazd z BRAK" 'has "/run/opengl-driver-32 (BRAK)"'
rm -rf "$FSR/run/opengl-driver"
rm "$FSR/sys/bus/pci/devices/0000:01:00.0"
GD_PATH="$NIXPATH" gd "${SESSION[@]}"
check "NixOS bez sterownika i bez GPU: „bez NVIDII”, ICD „brak”, kod 0" 'has "bez NVIDII na szynie PCI" && has "/run/opengl-driver/share/vulkan/icd.d: brak" && [[ $RC == 0 ]]'
cp "$BIN/asusctl" "$FSR/run/wrappers/bin/asusctl"; chmod +x "$FSR/run/wrappers/bin/asusctl"
GD_PATH="$FSR/run/wrappers/bin:$NIXPATH" gd "${SESSION[@]}"
check "NixOS wrapper /run/wrappers: nierozpoznany, partial owners" 'has "asusctl → pakiet: nierozpoznany (wrapper NixOS" && [[ "$LAST" == "diagnosis: partial; not checked: owners" ]]'
GD_PATH="$T/profile/bin:$BIN" gd "${SESSION[@]}"
check "NixOS binarka poza sklepem: nierozpoznana, partial owners" 'has "asusctl → pakiet: nierozpoznany (poza sklepem Nix)" && [[ "$LAST" == *owners* ]]'

# ─── nieznana platforma i brak biblioteki ────────────────────────────────────
mkroot "$FSR" gpu
osr 'NAME=Debian' ID=debian
gd "${SESSION[@]}"
check "nieznana: bez zgadywania (pacman/rpm ani razu), partial z platform" '[[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: platform, packages, foreign, nvidia-32bit, owners, history, initramfs" && $(calls pacman) == 0 && $(calls rpm) == 0 ]] && has "platforma nieobsługiwana albo nieznana"'
osr ID=arch
mv "$A/install/lib/pkg.sh" "$T/pkg.sh.off"
gd "${SESSION[@]}"
check "brak install/lib/pkg.sh: platforma nieznana, nie archowa" '[[ $RC == 2 && "$LAST" == "diagnosis: partial; not checked: platform"* && $(calls pacman) == 0 ]]'
mv "$T/pkg.sh.off" "$A/install/lib/pkg.sh"

# ─── Super+A → [i] → 3: ✓ Saved tylko przy pełnej albo jawnie częściowej ────
echo
echo "Super+A → diagnostyka: zapis zrzutu"
fn="$(sed -n '/^run_diag_dump() {/,/^}/p' "$REPO/scripts/appbinds/appbinds.sh")"
[[ -n "$fn" ]] || fail "run_diag_dump nie znaleziony w appbinds.sh"
eval "$fn"
GREEN="" YELLOW="" RED="" NC=""
D="$T/diag"; mkdir -p "$D/scripts/hypr"
dump() {   # dump <kod> <ostatnia linia> [workspace]
    local s="$D/scripts/hypr/${3:-gaming}-diag.sh"
    printf '#!/usr/bin/env bash\necho "zrzut prywatny"\n[[ -n "%s" ]] && echo "%s"\nexit %s\n' "$2" "$2" "$1" > "$s"
    rm -f "$HOME"/archenemy-diag-*
    if [[ -n "${3:-}" ]]; then
        OUT="$(ARCHENEMY_DIR="$D" PATH="$SYSBIN:$BIN" run_diag_dump workspace-diag.sh workspaces 2>&1)"
    else
        OUT="$(ARCHENEMY_DIR="$D" PATH="$SYSBIN:$BIN" run_diag_dump gaming-diag.sh gaming status 2>&1)"
    fi
}
dump 0 "diagnosis: complete"
check "complete (kod 0): ✓ Saved, plik w HOME, ostrzeżenie o prywatności" 'has "✓ Saved to $HOME/archenemy-diag-gaming-" && has "keep it private" && compgen -G "$HOME/archenemy-diag-gaming-*" >/dev/null'
dump 2 "diagnosis: partial; not checked: kernel-log, hyprland"
check "partial (kod 2): ⚠ Saved z listą, bez ✓" 'has "⚠ Saved to" && has "not checked: kernel-log, hyprland" && ! has "✓"'
dump 1 ""
check "kod 1 bez znacznika: ✗, bez „Saved”, plik zostaje" 'has "✗ gaming-diag.sh did not finish (exit code 1)" && ! has "Saved" && compgen -G "$HOME/archenemy-diag-gaming-*" >/dev/null'
dump 0 "koniec zrzutu"
check "kod 0 bez znacznika (stary skrypt): ✗, nie ✓ Saved" 'has "✗" && ! has "Saved"'
dump 2 "diagnosis: complete"
check "kod 2 ze znacznikiem complete (niespójne): ✗" 'has "✗" && ! has "Saved"'
dump 1 "" workspace
check "workspace-diag jak dotąd: ✓ Saved niezależnie od kodu" 'has "✓ Saved to $HOME/archenemy-diag-workspaces-"'
rm -f "$HOME"/archenemy-diag-*

# ─── parytet Archa z rewizją ─────────────────────────────────────────────────
# diff_ok <wzorzec> — każda różniąca się linia (−rewizja / +HEAD, bez sekcji
# kompletności i znacznika) pasuje do wzorca dozwolonych poprawek.
if [[ -n "${GAMING_DIAG_REV:-}" ]]; then
    echo
    echo "Parytet Archa z $GAMING_DIAG_REV"
    BASE="$T/base-gaming-diag.sh"
    git -C "$REPO" show "$GAMING_DIAG_REV:scripts/hypr/gaming-diag.sh" \
        | sed -E -e 's#^set -uo pipefail$#&\nR="${ARCHENEMY_FS_ROOT:-}"#' \
                 -e 's#([ "(<#])/(sys|proc|etc|usr|var)/#\1${R}/\2/#g' > "$BASE" || exit 1
    FIX_COMMON='^[-+]--- (z AUR \(pacman -Qm, filtr GPU/ASUS\)|obce \(pacman -Qm: AUR albo inne źródło spoza repozytoriów, filtr GPU/ASUS\)):$'
    norm_new() { awk '/^===== kompletność =====$/ {skip = 1} /^koniec zrzutu$/ {skip = 0} !skip' <<<"$1" | sed '$d'; }
    parity() {   # parity <etykieta> <wzorzec poprawki|-> zmienne…
        local label="$1" fix="$2" base new bad
        shift 2
        GD_SCRIPT="$BASE" gd "$@"; base="$OUT"
        gd "$@"; new="$(norm_new "$OUT")"
        bad="$(diff --unchanged-line-format= --old-line-format='-%L' --new-line-format='+%L' <(printf '%s\n' "$base") <(printf '%s\n' "$new") \
            | grep -Ev "$FIX_COMMON" | { if [[ "$fix" == - ]]; then cat; else grep -Ev "$fix"; fi; })"
        if [[ -z "$bad" ]]; then ok "Arch = $GAMING_DIAG_REV: $label"; else fail "Arch ≠ $GAMING_DIAG_REV: $label: ${bad//$'\n'/ | }"; fi
    }
    osr ID=arch; mkroot "$FSR" gpu
    parity "komplet w sesji" - "${SESSION[@]}" GD_NV64=580.95-1 GD_NV32=580.95-1
    parity "rozjazd i obce" - "${SESSION[@]}" GD_NV64=580.95-1 GD_NV32=580.82-1 GD_QM=list
    parity "poza sesją, pusty journal" - GD_KLOG=empty GD_NV64=1 GD_NV32=1
    parity "tylko 32-bit (BRAK zamiast pustych nawiasów)" '^[-+]!! ROZJAZD nvidia-utils \((BRAK)?\) vs lib32-nvidia-utils \(580\.95-1\)' "${SESSION[@]}" GD_NV32=580.95-1
    parity "brak obu przy GPU (nowa linia zamiast ciszy)" '^\+!! nvidia-utils / lib32-nvidia-utils: brak obu' "${SESSION[@]}"
    parity "binarka spoza pakietów" '^[-+]asusctl → pakiet: ?(żaden \(plik spoza pakietów — instalacja ręczna\?\))?$' "${SESSION[@]}" GD_QO=unowned GD_NV64=1 GD_NV32=1
    parity "brak jednostek" '^-(asusd|power-profiles-daemon|supergfxd): active=inactive enabled=$|^-nvidia-(suspend|hibernate|resume|powerd): enabled= active=inactive$|^\+[a-z-]+: brak jednostki \(nie zainstalowana — to nie awaria\)$' "${SESSION[@]}" GD_UNITS=missing GD_NV64=1 GD_NV32=1
    parity "błąd pacman -Q" '^\+!! pacman -Q nie powiódł się|^\+nvidia-utils vs lib32-nvidia-utils: nie sprawdzono' "${SESSION[@]}" GD_PACMAN=fail
    # L4/L5: nieudane nvidia-smi — to samo wyjście sondy, dochodzi tylko linia „!!”.
    parity "nieudane nvidia-smi (kod 1)" '^\+!! nvidia-smi — kod 1$' "${SESSION[@]}" GD_NVSMI=fail GD_NV64=1 GD_NV32=1
    parity "błąd pacman -Qm" '^-\(brak\)$|^\+!! pacman -Qm nie powiódł się' "${SESSION[@]}" GD_QM=fail GD_NV64=1 GD_NV32=1
    rm -rf "$FSR/usr/share/vulkan"
    parity "brak katalogu ICD" '^-$|^\+\(brak /usr/share/vulkan/icd\.d' "${SESSION[@]}" GD_NV64=1 GD_NV32=1
    mkroot "$FSR" gpu; rm "$FSR/var/log/pacman.log"
    parity "brak pacman.log" - "${SESSION[@]}" GD_NV64=1 GD_NV32=1
    mkroot "$FSR" gpu; rmdir "$FSR/usr/lib/modprobe.d"
    parity "brak /usr/lib/modprobe.d (bez fałszywego „(nic)” obok trafień)" '^-\(nic\)$' "${SESSION[@]}" GD_NV64=1 GD_NV32=1
    mkroot "$FSR" gpu
    osr 'NAME="EndeavourOS"' ID=endeavouros ID_LIKE=arch
    parity "pochodna Archa" - "${SESSION[@]}" GD_NV64=580.95-1 GD_NV32=580.95-1
fi

echo
if escaped="$(test_escapes "$T")"; then ok "zero zapisów poza \$T w: $(test_isolation_dirs)"
elif [[ $? == 2 ]]; then echo "  – izolacja niedostępna (unshare/overlay)"
else fail "zapisy poza \$T: ${escaped//$'\n'/ }"; fi
echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
test_timing_ok && [[ "$FAIL" -eq 0 ]]
