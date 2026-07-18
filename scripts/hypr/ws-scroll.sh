#!/bin/bash

# =============================================
#   archenemy - ws-scroll.sh
#   Scroll workspace'ów dla waybara (on-scroll-up/down) — kierunek
#   dyspozytora zależy od TRYBU workspace'ów (data/workspace-mode.dat):
#     decades → r±1 (w obrębie dekady monitora z fokusem)
#     shared  → e±1 (globalnie, następny/poprzedni istniejący)
#
#   Bindy KLAWIATURY nie przechodzą przez ten skrypt — install.sh [8b]
#   generuje je natywnie do workspaces-monitors.conf (zero forka shella
#   na naciśnięcie). Waybarowy config.jsonc jest tracked+wizualny, więc
#   nie jest generowany per tryb — stąd ten jeden wspólny wrapper.
#
#   Użycie: ws-scroll.sh up|down
# =============================================

set -uo pipefail

MODE_DAT="$HOME/archenemy/data/workspace-mode.dat"

# Brak pliku (np. stara instalacja przed wprowadzeniem trybów) → decades,
# czyli dotychczasowe zachowanie.
MODE="decades"
[[ -f "$MODE_DAT" ]] && MODE="$(<"$MODE_DAT")"

case "${1:-}" in
    up)   dir="+1" ;;
    down) dir="-1" ;;
    *)    echo "użycie: ws-scroll.sh up|down" >&2; exit 1 ;;
esac

prefix="r"
[[ "$MODE" == "shared" ]] && prefix="e"

exec hyprctl dispatch workspace "${prefix}${dir}"
