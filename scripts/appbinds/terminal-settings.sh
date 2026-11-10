#!/bin/bash

# =============================================
#   archenemy - terminal-settings.sh
#   Ustawienia Alacritty w aktywnej konfiguracji użytkownika.
# =============================================

set -uo pipefail
ARCHENEMY_DIR="${ARCHENEMY_DIR:-$HOME/archenemy}"
CONFIG="${ALACRITTY_CONFIG:-$HOME/.config/alacritty/alacritty.toml}"
BACKUP="${CONFIG}.bak"

read_state() {
    [[ -f "$CONFIG" ]] || return 0
    awk '
        /^\[selection\][[:space:]]*([#].*)?$/ { in_selection=1; next }
        /^\[/ { in_selection=0 }
        in_selection && /^[[:space:]]*save_to_clipboard[[:space:]]*=/ {
            if ($0 ~ /=([[:space:]]*)true([[:space:]]*(#.*)?)?$/) print "on"
            else if ($0 ~ /=([[:space:]]*)false([[:space:]]*(#.*)?)?$/) print "off"
            exit
        }
    ' "$CONFIG"
}

write_state() {
    local value="$1" toml_value tmp found current
    [[ "$value" == on || "$value" == off ]] || return 2
    [[ "$value" == on ]] && toml_value=true || toml_value=false
    if [[ ! -f "$CONFIG" ]]; then
        echo "⚠ Alacritty config not found: $CONFIG"
        return 0
    fi
    # Symlink rice'a prowadzi do pliku śledzonego; nie zapisujemy tam stanu osobistego.
    local resolved repo_root
    resolved="$(readlink -f -- "$CONFIG")" || return 1
    repo_root="$(readlink -f -- "$ARCHENEMY_DIR")" || return 1
    if [[ "$resolved" == "$repo_root/"* ]]; then
        echo "⚠ Rice config is inside the repository; no changes made."
        echo "Copy your Alacritty config outside the repository and use that personal config to change this setting."
        return 1
    fi
    found="$(awk '
        /^\[selection\][[:space:]]*([#].*)?$/ { in_selection=1; next }
        /^\[/ { in_selection=0 }
        in_selection && /^[[:space:]]*save_to_clipboard[[:space:]]*=/ { found=1 }
        END { if (found) print "yes" }
    ' "$CONFIG")"
    if [[ "$found" != yes ]]; then
        echo "⚠ save_to_clipboard line not found in [selection]: $CONFIG"
        return 0
    fi
    current="$(read_state)"
    if [[ "$current" == "$value" ]]; then
        echo "Copy on select is already $value; no changes made."
        return 0
    fi
    if [[ ! -e "$BACKUP" ]]; then
        cp -p -- "$CONFIG" "$BACKUP" || { echo "✗ Cannot create backup: $BACKUP"; return 1; }
    fi
    tmp="$(mktemp "${CONFIG}.XXXXXX")" || return 1
    if ! awk -v value="$toml_value" '
        /^\[selection\][[:space:]]*([#].*)?$/ { in_selection=1; print; next }
        /^\[/ { in_selection=0 }
        in_selection && /^[[:space:]]*save_to_clipboard[[:space:]]*=/ {
            sub(/=[[:space:]]*(true|false)/, "= " value)
            changed=1
        }
        { print }
        END { if (!changed) exit 1 }
    ' "$CONFIG" > "$tmp"; then
        rm -f -- "$tmp"
        echo "⚠ save_to_clipboard line not found in [selection]: $CONFIG"
        return 0
    fi
    if ! chmod --reference="$CONFIG" "$tmp" || ! mv -- "$tmp" "$CONFIG"; then
        rm -f -- "$tmp"
        echo "✗ Cannot update $CONFIG"
        return 1
    fi
    echo "✓ Copy on select: $value. Alacritty reloads this setting automatically. Backup: $BACKUP (restore it to undo)."
}

case "${1:-menu}" in
    summary|show) read_state || true; exit 0 ;;
    on|off) write_state "$1" ;;
    menu)
        # shellcheck source=lib/tui.sh
        # shellcheck disable=SC1091
        source "$(dirname "${BASH_SOURCE[0]}")/lib/tui.sh"
        state="$(read_state)"
        if [[ -z "$state" ]]; then
            echo "⚠ Cannot read copy on select: config or [selection].save_to_clipboard is missing."
            exit 0
        fi
        echo "  Copy on select is currently: $state"
        echo "  Backup is created on the first change and kept at: $BACKUP"
        # shellcheck disable=SC2034
        TUI_MENU_KEYS=(c)
        if tui_menu 0 "turn $([[ "$state" == on ]] && echo off || echo on)"; then
            [[ "$TUI_MENU_INDEX" == 0 ]] && write_state "$( [[ "$state" == on ]] && echo off || echo on )"
        else
            echo "Cancelled."
        fi
        ;;
    *) echo "Usage: $0 [menu|summary|show|on|off]" >&2; exit 2 ;;
esac
