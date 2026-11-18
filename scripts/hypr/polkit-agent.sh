#!/usr/bin/env bash
# =============================================
#   archenemy - polkit-agent.sh
#   Start agenta polkit sesji (hyprpolkitagent) z autostartu rice'ów:
#   hl.exec_cmd("~/archenemy/scripts/hypr/polkit-agent.sh") w hl.on("hyprland.start").
#
#   Dotąd rice'y wołały wprost `systemctl --user start hyprpolkitagent`
#   (yin dostał to samo przy scaleniu, C-D7). Brak jednostki (pakiet
#   niezainstalowany; NixOS bez systemd.packages) albo brak busa użytkownika
#   kończył się błędem systemctl w logu sesji. Teraz: ta sama jednostka, bez
#   enable i bez tworzenia jednostek; porażka = jedna cicha linia w logu
#   prywatnego katalogu sesji (scripts/lib/runtime-dir.sh), zawsze kod 0.
#   Bez prywatnego katalogu sesji log jest pomijany (nigdy wspólny /tmp).
#   Log: <katalog sesji>/archenemy-polkit-agent.log
#   Testy: bash tests/rice-autostart.sh
# =============================================

ARCHENEMY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if ! err="$(systemctl --user start hyprpolkitagent 2>&1)"; then
    # shellcheck source=scripts/lib/runtime-dir.sh
    if source "$ARCHENEMY_DIR/scripts/lib/runtime-dir.sh" 2>/dev/null \
        && RUN_DIR="$(archenemy_runtime_dir)" && [[ -n "$RUN_DIR" ]]; then
        printf '%s systemctl --user start hyprpolkitagent failed: %s — install hyprpolkitagent (README) or start your own polkit agent\n' \
            "$(date -Iseconds)" "${err//$'\n'/ }" >> "$RUN_DIR/archenemy-polkit-agent.log" 2>/dev/null
    fi
fi
exit 0
