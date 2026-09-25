#!/bin/bash

# =============================================
#   archenemy - rofi_theme_switcher.sh
#   Switch rice via rofi menu
#
#   Każdy wpis ma podgląd rices/<RICE_NAME>/preview.png (siatka z dużymi
#   ikonami, scripts/rofi/lib/rofi-preview.sh). W repo leżą makiety z
#   scripts/wallpapers/gen_rice_preview.py — można je podmienić prawdziwym
#   zrzutem ekranu pod tą samą ścieżką. Brak pliku = wpis bez ikony.
# =============================================

ARCHENEMY_DIR="$HOME/archenemy"
SCRIPTS_DIR="$ARCHENEMY_DIR/scripts/changing-theme-scripts"
RICES_DIR="$ARCHENEMY_DIR/rices"

# shellcheck source=scripts/rofi/lib/rofi-preview.sh
source "$ARCHENEMY_DIR/scripts/rofi/lib/rofi-preview.sh"

# ─── BUILD ROFI MENU ──────────────────────────────────────────────────────────

# Płaski glob *.sh (podfolder lib/ celowo niewidoczny w menu); pętla zamiast
# `ls | xargs` — xargs interpretuje cudzysłowy/spacje w nazwach (SC2011).
# Etykieta = nazwa stubu; folder rice'a (a z nim podgląd) = RICE_NAME ze
# stubu — etykieta nie musi się równać nazwie folderu.
LABELS=(); ICONS=()
for f in "$SCRIPTS_DIR"/*.sh; do
    [[ -f "$f" ]] || continue
    LABELS+=("$(basename "$f" .sh)")
    rice=$(sed -n 's/^RICE_NAME="\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$f" | head -n1)
    icon=""
    [[ -n "$rice" && "$rice" != */* ]] && icon="$RICES_DIR/$rice/preview.png"
    ICONS+=("$icon")
done

SCRIPT_NAME=$(rofi_preview_menu "Select rice:" LABELS ICONS)

[[ -z "$SCRIPT_NAME" ]] && exit 0

# ─── RUN SELECTED SCRIPT ──────────────────────────────────────────────────────

# rofi -dmenu zwraca wpisany tekst także BEZ dopasowania do listy — bez guarda
# literówka szła w ciemno do basha (bash <dir>/<literówka>.sh).
RICE_SCRIPT="$SCRIPTS_DIR/$SCRIPT_NAME.sh"
if [[ ! -f "$RICE_SCRIPT" ]]; then
    command -v notify-send &>/dev/null && \
        notify-send -u critical "archenemy" "No such rice script: $SCRIPT_NAME"
    exit 1
fi

bash "$RICE_SCRIPT"
