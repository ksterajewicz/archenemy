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
#   Rozwiązanie: selektor "desc:<opis>" — opis (producent + model + numer
#   seryjny) pochodzi z EDID i nie zmienia się z gniazdem. Dopasowanie po
#   prefiksie ("desc:"+opis zaczyna się od selektora) — tak samo robią
#   Hyprland (Monitor.cpp matchesStaticSelector), hyprpaper
#   (WallpaperMatcher.cpp) i hyprlock (Renderer.cpp).
#   install.sh [3] zapisuje DESCRIPTION= do data/monitors/<nazwa>.dat; gdy
#   opisu brak (stare .dat sprzed 2026-09-21, pusty EDID) selektorem zostaje
#   nazwa złącza — dokładnie dawne zachowanie.
# =============================================

# Selektor monitora z pliku .dat: "desc:<opis>" albo nazwa złącza.
monitor_selector_from_dat() {
    local dat="$1" desc name
    desc=$(grep -m1 '^DESCRIPTION=' "$dat" 2>/dev/null | cut -d= -f2-)
    if [[ -n "$desc" ]]; then
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
