#!/bin/bash

# =============================================
#   archenemy - rofi_theme_switcher.sh
#   Switch rice via rofi menu
# =============================================

ARCHENEMY_DIR="$HOME/archenemy"
SCRIPTS_DIR="$ARCHENEMY_DIR/scripts/changing-theme-scripts"

# ─── BUILD ROFI MENU ──────────────────────────────────────────────────────────

# Płaski glob *.sh (podfolder lib/ celowo niewidoczny w menu); pętla zamiast
# `ls | xargs` — xargs interpretuje cudzysłowy/spacje w nazwach (SC2011).
SCRIPT_NAME=$(for f in "$SCRIPTS_DIR"/*.sh; do basename "$f" .sh; done \
    | rofi -dmenu -i -p "Select rice:")

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
