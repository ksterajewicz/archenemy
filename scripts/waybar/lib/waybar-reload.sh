#!/usr/bin/env bash

# =============================================
#   archenemy - lib/waybar-reload.sh
#   Czy działający waybar zna aktualny config paska — i przeładowanie, gdy nie.
#   Source'ują to: scripts/appbinds/appbinds.sh (bar_change_report: [v] [l] [t])
#   i scripts/appbinds/update-archenemy.sh (po udanej aktualizacji).
#   Biblioteka — NIE uruchamiaj bezpośrednio.
#
#   Skąd potrzeba (diagnoza 2026-11-19): Waybar 0.15.0 czyta config TYLKO na
#   starcie (src/client.cpp, Client::main → config.load); inotify pilnuje
#   jedynie style.css ("reload_style_on_change"). git pull / [u] podmienia
#   config.jsonc rice'a pod działającym paskiem, więc nowy moduł albo nowy
#   "signal" (custom/launcher: 12) nie istnieje, dopóki waybar nie wczyta
#   configu od nowa — sygnał RTMIN+N trafia w proces (pkill oddaje 0), ale
#   żaden moduł go nie słucha i pasek stoi do restartu (u właściciela:
#   restart sprzętu). SIGUSR2 = domyślne "on-sigusr2": "reload" (man waybar(5):
#   „basically equivalent to restarting with updated config”) — config i CSS
#   wczytane od nowa, skrypty modułów uruchomione ponownie, bez nowego procesu.
#
#   Nieaktualny = plik configu zmieniony (mtime, przez symlink rice'a) nie
#   wcześniej niż start któregoś procesu waybar (ps etimes). Ta sama sekunda
#   liczy się jako nieaktualny: zbędny reload to mignięcie paska, przeoczony
#   to pasek bez zmiany aż do restartu.
# =============================================

# Pliki configu, które może czytać waybar (src/config.cpp: katalogi
# $XDG_CONFIG_HOME/waybar i ~/.config/waybar, nazwy config i config.jsonc).
waybar_config_files() {
    local d n
    for d in "${XDG_CONFIG_HOME:-$HOME/.config}/waybar" "$HOME/.config/waybar"; do
        for n in config config.jsonc; do
            [[ -f "$d/$n" ]] && printf '%s\n' "$d/$n"
        done
    done
}

# Kod 0, gdy działa waybar starszy niż jego config. Kod 1 także wtedy, gdy nie
# da się tego ocenić (brak procesu, configu albo ps) — wtedy zostaje zwykły
# sygnał odświeżenia, jak przed tą poprawką.
waybar_config_stale() {
    local f m newest=0 pid el now
    while IFS= read -r f; do
        m="$(stat -L -c %Y -- "$f" 2>/dev/null)" || continue
        [[ "$m" =~ ^[0-9]+$ ]] && (( m > newest )) && newest=$m
    done < <(waybar_config_files)
    (( newest > 0 )) || return 1
    now="$(date +%s)"
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        el="$(ps -o etimes= -p "$pid" 2>/dev/null)"
        el="${el//[[:space:]]/}"
        [[ "$el" =~ ^[0-9]+$ ]] || continue
        (( newest >= now - el )) && return 0
    done < <(pgrep -x waybar 2>/dev/null)
    return 1
}

# Przeładowanie configu i stylu wszystkich instancji waybara. Kod pkill:
# 0 = sygnał doszedł do co najmniej jednego procesu.
waybar_reload() {
    pkill -USR2 -x waybar 2>/dev/null
}
