#!/bin/bash

# =============================================
#   archenemy - rofi_theme_switcher.sh
#   Switch rice via rofi menu
# =============================================

ARCHENEMY_DIR="$HOME/archenemy"
SCRIPTS_DIR="$ARCHENEMY_DIR/scripts/changing-theme-scripts"

# ─── BUILD ROFI MENU ──────────────────────────────────────────────────────────

SCRIPT_NAME=$(ls "$SCRIPTS_DIR"/*.sh | xargs -I{} basename {} .sh | rofi -dmenu -i -p "Select rice:")

[[ -z "$SCRIPT_NAME" ]] && exit 0

# ─── RUN SELECTED SCRIPT ──────────────────────────────────────────────────────

bash "$SCRIPTS_DIR/$SCRIPT_NAME.sh"
