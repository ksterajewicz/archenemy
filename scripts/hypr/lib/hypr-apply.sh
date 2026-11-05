#!/bin/bash
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
hypr_reload_checked() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1 || return 3
    local before after
    before="$(hypr_config_errors)"
    hyprctl reload >/dev/null 2>&1 || return 1
    after="$(hypr_config_errors)"
    if [[ -n "$after" && "$after" != "$before" ]]; then
        printf '%s\n' "$after"
        return 2
    fi
    return 0
}
