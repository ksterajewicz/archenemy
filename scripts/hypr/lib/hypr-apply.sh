#!/usr/bin/env bash
# =============================================
#   archenemy - lib/hypr-apply.sh
#   Reload Hyprlanda z odczytem wyniku: sukces = brak NOWYCH błędów configu, nie
#   kod wyjścia. Source'owana przez appbinds.sh, workspace-mode-switch.sh
#   i monitor-settings.sh, bez efektów ubocznych przy wczytaniu.
# =============================================

# Błędy z ostatniego wczytania configu. Pusto = brak; hyprctl drukuje wtedy
# pustą linię (src/ipc/s1/Commands.cpp: configErrorsRequest).
hypr_config_errors() {
    hyprctl configerrors 2>/dev/null | sed '/^[[:space:]]*$/d'
}

# Kody: 0 wczytane bez nowych błędów, 1 Hyprland nie odpowiada, 2 nowe błędy
# (lista na stdout), 3 brak sesji Hyprlanda: zmiana wejdzie przy następnym starcie.
#
# $1 = błędy odczytane hypr_config_errors PRZED zapisem pliku (pusto = nie było).
# Odczyt „przed” musi paść przed zapisem: Hyprland z autoreloadem (domyślnie
# misc:disable_autoreload = false) wczytuje zmieniony plik przez inotify, zanim
# padnie `hyprctl reload`, więc odczyt po zapisie już zawierał nowy błąd —
# „przed” == „po”, kod 0 i fałszywe „no config errors” bez cofnięcia zmiany.
# Bez argumentu „przed” czytane tu (tylko dla reloadu bez zapisu).
hypr_reload_checked() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1 || return 3
    local before after
    if (( $# )); then before="$1"; else before="$(hypr_config_errors)"; fi
    hyprctl reload >/dev/null 2>&1 || return 1
    after="$(hypr_config_errors)"
    if [[ -n "$after" && "$after" != "$before" ]]; then
        printf '%s\n' "$after"
        return 2
    fi
    return 0
}
