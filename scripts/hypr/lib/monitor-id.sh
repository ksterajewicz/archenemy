#!/usr/bin/env bash
# =============================================
#   archenemy - lib/monitor-id.sh
#   Tożsamość monitora w warstwie maszynowej — JEDNO źródło prawdy.
#   Nie uruchamiaj bezpośrednio — to biblioteka funkcji; source'ują ją
#   install/install.sh, workspace-mode-switch.sh, workspace-orphan-guard.sh
#   i rofi_wallpaper_switcher.sh.
#
#   Problem (złapany na żywo 2026-09-21): nazwa złącza (eDP-2, HDMI-A-1) NIE
#   jest stała — po restarcie/przepięciu Hyprland potrafi nadać eDP-1 i
#   HDMI-A-3 tym samym fizycznym ekranom. Reguły hl.monitor/hl.workspace_rule
#   celujące w nazwę z dnia instalacji przestają wtedy pasować: monitor
#   spada na regułę fallback (preferred/auto), a jego dekada workspace'ów
#   staje się sierotą (Hyprland tworzy 21, 22…).
#
#   Rozwiązanie: selektor "desc:<producent model seria>" — z EDID, nie zmienia
#   się z gniazdem. Składamy go z pól make/model/serial (to „krótki opis”
#   Hyprlanda), NIE z linii description: — ta bywa dłuższa (backend potrafi
#   doklejać sufiks z nazwą złącza w nawiasie), a krótka forma jest jej
#   prefiksem. Dopasowanie po prefiksie ("desc:"+opis zaczyna się od
#   selektora) robią tak samo Hyprland (Monitor.cpp matchesStaticSelector:
#   pełny ALBO krótki opis), hyprpaper (WallpaperMatcher.cpp) i hyprlock
#   (Renderer.cpp).
#   INTEGRALNOŚĆ (projekt publiczny — cudze maszyny): desc: wchodzi TYLKO gdy
#   opis jest niepusty, bez znaków specjalnych (monitor_desc_usable) i
#   UNIKALNY wśród wykrytych monitorów (install.sh [3]: dwa identyczne
#   monitory bez numeru seryjnego → oba zostają przy nazwie złącza, bo
#   selektor po prefiksie trafiłby w oba). Każdy przypadek brzegowy = dawne
#   zachowanie, nigdy gorsze.
#   install.sh [3] zapisuje DESCRIPTION= do data/monitors/<nazwa>.dat; gdy
#   opisu brak (stare .dat sprzed 2026-09-21, pusty EDID) selektorem zostaje
#   nazwa złącza — dokładnie dawne zachowanie.
# =============================================

# Czy opis nadaje się na selektor: niepusty, bez znaków, które rozerwałyby
# Lua/hyprlang/wallpaper.dat/regex guarda (cudzysłów, backslash, '#', '=',
# znaki sterujące). Przecinki Hyprland sam usuwa z opisu (Monitor.cpp).
# Nie nadaje się → wołający zostaje przy nazwie złącza (dawne zachowanie).
monitor_desc_usable() {
    local d="$1"
    [[ -n "$d" ]] || return 1
    [[ "$d" == *[\"\\#=]* ]] && return 1
    [[ "$d" == *[[:cntrl:]]* ]] && return 1
    return 0
}

# Selektor monitora z pliku .dat: "desc:<opis>" albo nazwa złącza.
monitor_selector_from_dat() {
    local dat="$1" desc name
    desc=$(grep -m1 '^DESCRIPTION=' "$dat" 2>/dev/null | cut -d= -f2-)
    if monitor_desc_usable "$desc"; then
        printf 'desc:%s\n' "$desc"
    else
        name=$(grep -m1 '^MONITOR=' "$dat" 2>/dev/null | cut -d= -f2-)
        printf '%s\n' "${name:-$(basename "$dat" .dat)}"
    fi
}

# Nazwa złącza, pod którą selektor jest TERAZ podłączony (wg hyprctl monitors).
# Pusty wynik = nic nie pasuje (monitor odpięty / hyprctl nie odpowiada).
# Dopasowanie desc: po prefiksie — jak w Hyprlandzie.
monitor_live_name() {
    local sel="$1" line name="" desc
    if [[ "$sel" != desc:* ]]; then
        hyprctl monitors 2>/dev/null | grep -q "^Monitor $sel (ID " && printf '%s\n' "$sel"
        return 0
    fi
    while IFS= read -r line; do
        case "$line" in
            'Monitor '*)
                name="${line#Monitor }"
                name="${name%% *}"
                ;;
            *'description: '*)
                desc="${line#*description: }"
                if [[ -n "$name" && "desc:$desc" == "$sel"* ]]; then
                    printf '%s\n' "$name"
                    return 0
                fi
                ;;
        esac
    done < <(hyprctl monitors 2>/dev/null)
    return 0
}

# Literał stringu Lua (cudzysłów i backslash w opisie z EDID nie mogą
# rozerwać hl.monitor({ output = "..." })).
lua_string() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"\n' "$s"
}
