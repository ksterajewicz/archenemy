#!/bin/bash

# =============================================
#   archenemy - gaming-diag.sh
#   Zrzut stanu GPU/gier do diagnozy (TYLKO ODCZYT — niczego nie zmienia,
#   nie wymaga sudo). Odpowiada na pytania:
#     - które GPU system w ogóle widzi (iGPU / NVIDIA) i czy dGPU nie jest
#       wyłączony sprzętowo (ASUS: dgpu_disable / tryb MUX),
#     - czy sterownik NVIDII pasuje do działającego jądra (moduł, DKMS,
#       nvidia-utils vs lib32-nvidia-utils), czy dGPU zasypia i się budzi,
#     - na którym GPU renderuje Hyprland i z jakimi zmiennymi środowiska,
#     - które pakiety ASUS/GPU są zainstalowane i kiedy się zmieniały,
#     - co obciąża maszynę (animowana tapeta, profil energii, zasilanie),
#     - jeśli gra jest uruchomiona: na którym GPU FAKTYCZNIE się liczy.
#
#   Użycie: gaming-diag.sh [> plik]
#   Najlepiej dwa razy: raz bez gry, raz w trakcie gry (okno gry otwarte).
#   Wynik zawiera opisy sprzętu (modele, numery seryjne monitorów) — do
#   prywatnej diagnozy, nie do publicznego zgłoszenia.
# =============================================

set -uo pipefail

ARCHENEMY_DIR="$HOME/archenemy"

section() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
# Wartość pliku sysfs albo „-” (brak pliku = funkcja nieobecna, nie błąd).
sysval() { [[ -r "$1" ]] && tr -d '\n' <"$1" 2>/dev/null || printf -- '-'; }

# [.] zamiast \. — awk -v przetwarza sekwencje ucieczki i gubiłby backslash.
GAME_RE='^(steam_app_[0-9]+|gamescope|.*[.]exe)$'

section "system"
echo "date: $(date '+%F %T')"
echo "kernel: $(uname -r)"
echo "cmdline: $(cat /proc/cmdline 2>/dev/null)"
echo "laptop: $(sysval /sys/class/dmi/id/sys_vendor) / $(sysval /sys/class/dmi/id/product_name) / board $(sysval /sys/class/dmi/id/board_name) / BIOS $(sysval /sys/class/dmi/id/bios_version)"
if [[ -d "$ARCHENEMY_DIR/.git" ]]; then
    echo "archenemy: $(git -C "$ARCHENEMY_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git -C "$ARCHENEMY_DIR" log -1 --format='%h %cs %s' 2>/dev/null)"
    echo "installed-head.dat: $(cat "$ARCHENEMY_DIR/data/installed-head.dat" 2>/dev/null || echo BRAK)"
    echo "zmiany w drzewie: $(git -C "$ARCHENEMY_DIR" status --porcelain 2>/dev/null | wc -l)"
fi
echo "current rice: $(cat "$ARCHENEMY_DIR/.current_rice" 2>/dev/null || echo BRAK)"

section "pakiety (GPU / ASUS / gry)"
# Jeden wzorzec zamiast listy nazw — łapie też warianty z AUR (-git, -dkms, 580xx).
pacman -Q 2>/dev/null | grep -E '^(linux[^ ]*|nvidia[^ ]*|lib32-nvidia[^ ]*|opencl-nvidia[^ ]*|egl-wayland[^ ]*|mesa|lib32-mesa|vulkan-[^ ]*|lib32-vulkan-[^ ]*|intel-media-driver|libva-[^ ]*|asusctl[^ ]*|rog-control-center[^ ]*|supergfxctl[^ ]*|cardwire[^ ]*|switcheroo-control|power-profiles-daemon|tlp[^ ]*|auto-cpufreq|optimus-manager[^ ]*|envycontrol|gamemode|lib32-gamemode|gamescope[^ ]*|mangohud[^ ]*|steam[^ ]*|hyprland[^ ]*|aquamarine[^ ]*|dkms) '
echo "--- z AUR (pacman -Qm, filtr GPU/ASUS):"
pacman -Qm 2>/dev/null | grep -Ei 'nvidia|asus|rog-|supergfx|cardwire|linux|mesa|vulkan|hypr' || echo "(brak)"
NV_U="$(pacman -Q nvidia-utils 2>/dev/null | awk '{print $2}')"
NV_U32="$(pacman -Q lib32-nvidia-utils 2>/dev/null | awk '{print $2}')"
if [[ -n "$NV_U" || -n "$NV_U32" ]]; then
    if [[ "$NV_U" == "$NV_U32" ]]; then
        echo "nvidia-utils = lib32-nvidia-utils: OK ($NV_U)"
    else
        echo "!! ROZJAZD nvidia-utils ($NV_U) vs lib32-nvidia-utils (${NV_U32:-BRAK}) — 32-bitowe gry/Proton"
    fi
fi
for b in asusctl rog-control-center supergfxctl; do
    have "$b" && echo "$b → pakiet: $(pacman -Qoq "$(command -v "$b")" 2>/dev/null)"
done

section "historia pacmana (GPU / jądro / ASUS / Hyprland, ostatnie 40)"
if [[ -r /var/log/pacman.log ]]; then
    grep -E '\[ALPM\] (installed|upgraded|downgraded|removed) (linux[^ ]*|nvidia[^ ]*|lib32-nvidia[^ ]*|mesa|lib32-mesa|vulkan-[^ ]*|asusctl[^ ]*|rog-control-center[^ ]*|supergfxctl[^ ]*|cardwire[^ ]*|power-profiles-daemon|hyprland|aquamarine) ' \
        /var/log/pacman.log | tail -n 40
else
    echo "(brak /var/log/pacman.log)"
fi

section "GPU na szynie PCI"
if have lspci; then
    lspci -nnk 2>/dev/null | grep -EA3 'VGA|3D controller|Display controller' | grep -Ev '^\s*Subsystem'
else
    echo "BRAK lspci (pciutils)"
fi
echo "--- karty DRM (boot_vga=1 → tę Hyprland bierze domyślnie)"
for c in /sys/class/drm/card[0-9]; do
    [[ -e "$c" ]] || { echo "(brak /sys/class/drm/card*)"; break; }
    dev="$(readlink -f "$c/device")"
    drv="$(basename "$(readlink -f "$c/device/driver" 2>/dev/null)" 2>/dev/null)"
    conns="$(for k in "$c"-*; do [[ -e "$k/status" ]] && printf '%s=%s ' "${k##*/"${c##*/}"-}" "$(sysval "$k/status")"; done)"
    printf '%s: pci=%s vendor=%s driver=%s boot_vga=%s | %s\n' "${c##*/}" "${dev##*/}" \
        "$(sysval "$c/device/vendor")" "${drv:--}" "$(sysval "$c/device/boot_vga")" "$conns"
done
for r in /sys/class/drm/renderD*; do
    [[ -e "$r" ]] || continue
    printf '%s: driver=%s\n' "${r##*/}" "$(basename "$(readlink -f "$r/device/driver" 2>/dev/null)" 2>/dev/null)"
done
echo "--- dGPU NVIDIA: zasilanie (odczyt PRZED nvidia-smi — nvidia-smi budzi kartę)"
NV_FOUND=0
for d in /sys/bus/pci/devices/*; do
    [[ "$(sysval "$d/vendor")" == "0x10de" ]] || continue
    [[ "$(sysval "$d/class")" == 0x03* ]] || continue
    NV_FOUND=1
    printf '%s: runtime_status=%s control=%s power_state=%s d3cold_allowed=%s link=%s x%s\n' "${d##*/}" \
        "$(sysval "$d/power/runtime_status")" "$(sysval "$d/power/control")" "$(sysval "$d/power_state")" \
        "$(sysval "$d/d3cold_allowed")" "$(sysval "$d/current_link_speed")" "$(sysval "$d/current_link_width")"
done
[[ "$NV_FOUND" -eq 0 ]] && echo "!! brak urządzenia NVIDIA (VGA/3D) na szynie PCI"
for p in /proc/driver/nvidia/gpus/*/power; do
    [[ -r "$p" ]] && { echo "--- $p"; cat "$p"; }
done

section "ASUS (dGPU / MUX / profil)"
for a in dgpu_disable gpu_mux_mode egpu_enable throttle_thermal_policy; do
    echo "asus-nb-wmi/$a: $(sysval "/sys/devices/platform/asus-nb-wmi/$a")"
done
if [[ -d /sys/class/firmware-attributes/asus-armoury/attributes ]]; then
    for a in dgpu_disable gpu_mux_mode egpu_enable; do
        echo "asus-armoury/$a: $(sysval "/sys/class/firmware-attributes/asus-armoury/attributes/$a/current_value")"
    done
else
    echo "asus-armoury: brak (/sys/class/firmware-attributes/asus-armoury)"
fi
echo "platform_profile: $(sysval /sys/firmware/acpi/platform_profile) (dostępne: $(sysval /sys/firmware/acpi/platform_profile_choices))"
have asusctl && echo "asusctl: $(timeout 5 asusctl --version 2>&1 | head -n 3 | tr '\n' ' ')"
for u in asusd power-profiles-daemon supergfxd; do
    echo "$u: active=$(systemctl is-active "$u" 2>/dev/null) enabled=$(systemctl is-enabled "$u" 2>/dev/null)"
done
have powerprofilesctl && echo "powerprofilesctl get: $(timeout 5 powerprofilesctl get 2>&1)"
if have supergfxctl; then
    echo "supergfxctl -g: $(timeout 5 supergfxctl -g 2>&1)"
    echo "supergfxctl -S: $(timeout 5 supergfxctl -S 2>&1)"
fi
have cardwire && echo "cardwire: zainstalowany ($(command -v cardwire))"

section "zasilanie i CPU"
for s in /sys/class/power_supply/*; do
    [[ -e "$s/type" ]] || continue
    case "$(sysval "$s/type")" in
        Mains)   echo "${s##*/}: online=$(sysval "$s/online")" ;;
        Battery) echo "${s##*/}: $(sysval "$s/status") $(sysval "$s/capacity")% limit=$(sysval "$s/charge_control_end_threshold")" ;;
    esac
done
echo "cpufreq: driver=$(sysval /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver) governor=$(sysval /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) epp=$(sysval /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)"

section "sterownik NVIDIA"
echo "moduł dla $(uname -r): $(modinfo -F version nvidia 2>/dev/null || echo 'BRAK (modinfo nvidia)')"
echo "załadowany: $(sysval /sys/module/nvidia/version)"
lsmod 2>/dev/null | grep -E '^nvidia' || echo "lsmod: brak modułów nvidia"
have dkms && { echo "--- dkms status"; dkms status 2>&1; }
echo "nvidia_drm modeset=$(sysval /sys/module/nvidia_drm/parameters/modeset) fbdev=$(sysval /sys/module/nvidia_drm/parameters/fbdev)"
[[ -r /proc/driver/nvidia/params ]] && grep -E '^(DynamicPowerManagement|EnableS0ixPowerManagement|PreserveVideoMemoryAllocations):' /proc/driver/nvidia/params
echo "--- modprobe.d (nvidia/nouveau)"
grep -rHs -E 'nvidia|nouveau' /etc/modprobe.d /usr/lib/modprobe.d 2>/dev/null | grep -v ':\s*#' || echo "(nic)"
echo "mkinitcpio: $(grep -E '^MODULES=' /etc/mkinitcpio.conf 2>/dev/null || echo BRAK)"
for u in nvidia-suspend nvidia-hibernate nvidia-resume nvidia-powerd; do
    echo "$u: enabled=$(systemctl is-enabled "$u" 2>/dev/null) active=$(systemctl is-active "$u" 2>/dev/null)"
done
if have nvidia-smi; then
    echo "--- nvidia-smi"
    timeout 15 nvidia-smi --query-gpu=name,driver_version,pstate,power.draw,clocks.gr,utilization.gpu,temperature.gpu --format=csv 2>&1
    timeout 15 nvidia-smi 2>&1 | sed -n '/Processes:/,$p'
else
    echo "BRAK nvidia-smi"
fi

section "dziennik jądra (bieżący rozruch, GPU/ASUS)"
KLOG="$(journalctl -k -b --no-pager 2>/dev/null)"
if [[ -n "$KLOG" ]]; then
    grep -Ei 'nvidia|NVRM|nouveau|i915|xe |amdgpu|asus|drm.*(error|fail)' <<<"$KLOG" | tail -n 40
else
    echo "(pusto albo brak dostępu do journalctl -k — użytkownik spoza grupy wheel/systemd-journal)"
fi

section "Hyprland"
HYPR_PID="$(pgrep -x Hyprland | head -n 1)"
if [[ -n "$HYPR_PID" ]]; then
    echo "--- środowisko procesu Hyprland (GPU)"
    tr '\0' '\n' <"/proc/$HYPR_PID/environ" 2>/dev/null | grep -E '^(AQ_|GBM_|__GLX|__NV|__VK|LIBVA|DRI_PRIME|VK_|WLR_|MESA_)' || echo "(brak zmiennych GPU)"
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
    HLOG="${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"
    if [[ -r "$HLOG" ]]; then
        echo "--- log Hyprlanda (DRM/GPU/renderer)"
        grep -Ei 'drm|gpu|renderer|egl|nvidia|primary|explicit sync|backend' "$HLOG" | head -n 40
    fi
else
    echo "(poza sesją Hyprlanda — pomijam hyprctl)"
fi

section "Vulkan / GL"
ls /usr/share/vulkan/icd.d/ 2>/dev/null | tr '\n' ' '; echo
if have vulkaninfo; then
    echo "--- vulkaninfo --summary (domyślnie)"
    timeout 15 vulkaninfo --summary 2>/dev/null | grep -E '^GPU[0-9]|deviceName|deviceType|driverName|driverInfo'
    if have prime-run; then
        echo "--- prime-run vulkaninfo --summary"
        timeout 15 prime-run vulkaninfo --summary 2>/dev/null | grep -E '^GPU[0-9]|deviceName|deviceType|driverName'
    fi
else
    echo "BRAK vulkaninfo (pakiet vulkan-tools)"
fi
echo "prime-run: $(command -v prime-run || echo BRAK)"
have eglinfo && timeout 10 eglinfo -B 2>/dev/null | grep -E 'Wayland platform|OpenGL core profile renderer|OpenGL renderer' | head -n 4

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

section "kto teraz używa GPU (urządzenia otwarte przez procesy)"
# Mapa renderD → sterownik, żeby było widać, czy proces trzyma iGPU czy NVIDIĘ.
declare -A RENDER_DRV=()
for r in /sys/class/drm/renderD*; do
    [[ -e "$r" ]] && RENDER_DRV["/dev/dri/${r##*/}"]="$(basename "$(readlink -f "$r/device/driver" 2>/dev/null)" 2>/dev/null)"
done
for fd in /proc/[0-9]*/fd/*; do
    t="$(readlink "$fd" 2>/dev/null)" || continue
    case "$t" in
        /dev/dri/renderD*|/dev/nvidia[0-9]*) ;;
        *) continue ;;
    esac
    pid="${fd#/proc/}"; pid="${pid%%/*}"
    printf '%s %s %s %s\n' "$pid" "$(cat "/proc/$pid/comm" 2>/dev/null)" "$t" "${RENDER_DRV[$t]:-}"
done | sort -u -k1,1n -k3,3 | awk '{printf "pid=%s %s → %s %s\n", $1, $2, $3, $4} END {if (NR == 0) print "(żaden proces nie trzyma renderD/nvidia)"}'

section "gra (okna steam_app_* / gamescope / *.exe)"
if have hyprctl && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    GAMES="$(hyprctl clients 2>/dev/null | awk -v re="$GAME_RE" '
        /^\tclass: / { cls = $2 }
        /^\tpid: /   { if (cls ~ re) print $2, cls; cls = "" }')"
    if [[ -z "$GAMES" ]]; then
        echo "brak otwartej gry — uruchom grę i odpal skrypt ponownie (ta sekcja pokaże, na którym GPU się liczy)"
    else
        while read -r gpid gcls; do
            echo "gra: $gcls pid=$gpid"
            for fd in /proc/"$gpid"/fd/*; do
                t="$(readlink "$fd" 2>/dev/null)" || continue
                case "$t" in /dev/dri/*|/dev/nvidia*) echo "  otwarte: $t ${RENDER_DRV[$t]:-}" ;; esac
            done | sort -u
            echo "  env: $(tr '\0' '\n' <"/proc/$gpid/environ" 2>/dev/null | grep -E '^(__NV_PRIME|__GLX|__VK_LAYER_NV|DRI_PRIME|MESA_VK_DEVICE_SELECT|DXVK_FILTER|VKD3D_FILTER|PROTON_|MANGOHUD|LD_PRELOAD)' | tr '\n' ' ')"
        done <<<"$GAMES"
    fi
else
    echo "(poza sesją Hyprlanda)"
fi

echo
echo "koniec zrzutu"
