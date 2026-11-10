#!/bin/bash

# =============================================
#   archenemy - font-settings.sh
#   Super+A → [f]: font rice'a albo własny, wybrany z zainstalowanych.
#   Logika i zapis: lib/fonts.sh (warstwa osobista ~/.config/archenemy/fonts/).
#   Polecenia: menu (domyślne) | summary | brief | current | list [--all]
#              | set <rodzina> | reset | undo
# =============================================

set -uo pipefail
ARCHENEMY_DIR="${ARCHENEMY_DIR:-$HOME/archenemy}"
LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
# shellcheck source=lib/fonts.sh
source "$LIB_DIR/fonts.sh"

# Czas na decyzję w każdym menu tego ekranu (jak próba monitora: bez wiszenia).
MENU_TIMEOUT="${ARCHENEMY_FONT_MENU_TIMEOUT:-120}"

summary() {
    local over rice
    over="$(font_override)"
    rice="$(font_active_rice)"
    if [[ -z "$over" ]]; then
        printf 'rice default'
    elif font_rice_supported "$rice"; then
        printf '%s' "$over"
    else
        printf '%s (not in this rice)' "$over"
    fi
}

# Wiersz fastfetcha: rodzina i rozmiar terminala, jak moduł terminalfont.
current() {
    local font size
    font="$(font_effective)"
    [[ -n "$font" ]] || { echo "unknown"; return 0; }
    size="$(font_rice_size "$(font_active_rice)")"
    if [[ -n "$size" ]]; then printf '%s (%spt)\n' "$font" "$size"; else printf '%s\n' "$font"; fi
}

brief() {
    local rice over
    rice="$(font_active_rice)"
    over="$(font_override)"
    echo "Rice font: $(font_rice_default "$rice")"
    echo "Your font: ${over:-none, rice default}"
    font_rice_supported "$rice" || echo "This rice keeps its own font."
    echo ""
    echo "Covered:"
    font_coverage | awk -F'\t' '$2 == "yes" { print "  " $1 }'
    echo "Not covered:"
    font_coverage | awk -F'\t' '$2 == "no" { print "  " $1 }'
}

apply_message() {
    local rc="$1" name="$2"
    case "$rc" in
        0) if [[ -n "$name" ]]; then
               echo -e "  ${GREEN}✓ Font: ${name}.${NC}"
           else
               echo -e "  ${GREEN}✓ Back to the rice font.${NC}"
           fi
           echo "  Alacritty reloads open windows by itself; rofi menus and fastfetch use it next time."
           echo "  Waybar, mako and hyprlock keep the rice font (see the table)."
           echo "  Saved in $FONT_DIR (outside the repository); the previous value is kept for undo." ;;
        2) echo -e "  ${RED}✗ Font name has characters archenemy does not write into configs; no changes made.${NC}" ;;
        3) echo -e "  ${RED}✗ Font is no longer installed; no changes made.${NC}" ;;
        4) echo -e "  ${RED}✗ $FONT_DIR points into the repository; no changes made.${NC}" ;;
        *) echo -e "  ${RED}✗ Cannot write $FONT_DIR; no changes made.${NC}" ;;
    esac
}

print_status() {
    local rice def over name covered note
    rice="$(font_active_rice)"
    def="$(font_rice_default "$rice")"
    over="$(font_override)"
    tui_fit "Rice" 14; echo "  $FIT${rice:-unknown}"
    tui_fit "Rice font" 14; echo "  $FIT${def:-unknown}"
    tui_fit "Your font" 14; echo "  $FIT${over:-none, rice default}"
    if ! font_rice_supported "$rice"; then
        echo -e "  ${YELLOW}This rice keeps its own font; your choice applies in the other rices.${NC}"
    fi
    echo ""
    tui_fit "Applies to" 19; local head="$FIT"
    tui_fit "Covered" 9
    echo -e "  ${DIM}${head}${FIT}Why / when${NC}"
    while IFS=$'\t' read -r name covered note; do
        tui_fit "$name" 19; local col="$FIT"
        tui_fit "$covered" 9
        if [[ "$covered" == yes ]]; then
            echo -e "  ${col}${GREEN}${FIT}${NC}${DIM}${note}${NC}"
        else
            echo -e "  ${col}${YELLOW}${FIT}${NC}${DIM}${note}${NC}"
        fi
    done < <(font_coverage)
    echo ""
}

# Próbka rysowana bieżącym fontem terminala; o nowym foncie mówimy tylko,
# czy ma ikony Nerd Font (fontconfig), bez dodatkowych zależności.
preview_font() {
    local name="$1"
    echo ""
    echo -e "  ${BOLD}${name}${NC}"
    echo "    AaBbCc 0O 1lI {}[]()<>=> ~/archenemy \$ ls -la"
    if font_has_nerd_glyphs "$name"; then
        echo -e "    ${GREEN}Nerd Font icons: yes${NC}"
        [[ "${TERM:-}" == alacritty* ]] && echo "     󰍉 󰕾 󰂄 󰖩"
    else
        echo -e "    ${YELLOW}Nerd Font icons: no — icons in the terminal may show as boxes${NC}"
    fi
    echo -e "  ${DIM}The sample uses your current terminal font; the new one shows after applying.${NC}"
}

pick_font() {
    local all=0 i initial over chosen rc
    local -a fonts=() labels=() TUI_MENU_KEYS=() TUI_MENU_NUMBERS=()
    local TUI_MENU_TIMEOUT="$MENU_TIMEOUT"
    over="$(font_override)"
    while :; do
        mapfile -t fonts < <(font_installed "$all")
        if (( ${#fonts[@]} == 0 )) && (( all == 0 )); then
            echo -e "  ${YELLOW}No monospace fonts found; showing all installed fonts.${NC}"
            all=1
            mapfile -t fonts < <(font_installed 1)
        fi
        if (( ${#fonts[@]} == 0 )); then
            echo -e "  ${RED}✗ fc-list returned no fonts; no changes made.${NC}"
            return 1
        fi
        labels=("${fonts[@]}")
        TUI_MENU_KEYS=(); TUI_MENU_NUMBERS=()
        initial=0
        for i in "${!fonts[@]}"; do
            TUI_MENU_KEYS+=("")
            TUI_MENU_NUMBERS+=("$((i + 1))")
            [[ "${fonts[$i]}" == "$over" ]] && initial=$i
        done
        if (( all == 0 )); then labels+=("show all installed fonts [a]"); else labels+=("show monospace fonts only [a]"); fi
        TUI_MENU_KEYS+=(a)
        TUI_MENU_NUMBERS+=("")
        echo "  ${#fonts[@]} $( (( all == 0 )) && echo monospace || echo installed ) fonts:"
        if ! tui_menu "$initial" "${labels[@]}"; then
            echo -e "  ${YELLOW}Cancelled.${NC}"
            return 1
        fi
        if (( TUI_MENU_INDEX == ${#fonts[@]} )); then
            all=$(( 1 - all ))
            continue
        fi
        chosen="${fonts[$TUI_MENU_INDEX]}"
        break
    done
    preview_font "$chosen"
    echo ""
    if ! confirm "Use ${chosen}?" Y; then
        echo -e "  ${YELLOW}Cancelled.${NC}"
        return 1
    fi
    font_apply "$chosen"; rc=$?
    apply_message "$rc" "$chosen"
}

menu() {
    # shellcheck source=lib/tui.sh
    source "$LIB_DIR/tui.sh"
    local over prev def rc
    local -a items=() TUI_MENU_KEYS=()
    # shellcheck disable=SC2034  # czyta tui_menu (zakres dynamiczny)
    local TUI_MENU_TIMEOUT="$MENU_TIMEOUT"
    clear 2>/dev/null || true
    tui_header "fonts"
    print_status
    over="$(font_override)"
    def="$(font_rice_default "$(font_active_rice)")"
    items=("use the rice font (${def:-unknown}) [d]" "choose from installed fonts [l]")
    TUI_MENU_KEYS=(d l)
    if prev="$(font_previous)" && [[ "$prev" != "$over" ]]; then
        items+=("undo last change (back to ${prev:-the rice font}) [u]")
        TUI_MENU_KEYS+=(u)
    fi
    if ! tui_menu 1 "${items[@]}"; then
        echo -e "  ${YELLOW}Cancelled.${NC}"
        return 0
    fi
    case "${TUI_MENU_KEYS[$TUI_MENU_INDEX]}" in
        d) if [[ -z "$over" ]]; then
               echo "  Already using the rice font; no changes made."
           else
               font_apply ""; rc=$?
               apply_message "$rc" ""
           fi ;;
        l) pick_font ;;
        u) font_apply "$prev"; rc=$?
           apply_message "$rc" "$prev" ;;
    esac
}

case "${1:-menu}" in
    menu) menu ;;
    summary) summary ;;
    brief) brief ;;
    current) current ;;
    list) font_installed "$([[ "${2:-}" == --all ]] && echo 1 || echo 0)" ;;
    set)
        [[ $# -ge 2 ]] || { echo "Usage: $0 set <family>" >&2; exit 2; }
        # shellcheck source=lib/tui.sh
        source "$LIB_DIR/tui.sh"
        font_apply "$2"; rc=$?
        apply_message "$rc" "$2"
        exit "$rc" ;;
    reset)
        # shellcheck source=lib/tui.sh
        source "$LIB_DIR/tui.sh"
        font_apply ""; rc=$?
        apply_message "$rc" ""
        exit "$rc" ;;
    undo)
        # shellcheck source=lib/tui.sh
        source "$LIB_DIR/tui.sh"
        prev="$(font_previous)" || { echo "Nothing to undo." >&2; exit 1; }
        font_apply "$prev"; rc=$?
        apply_message "$rc" "$prev"
        exit "$rc" ;;
    *) echo "Usage: $0 [menu|summary|brief|current|list [--all]|set <family>|reset|undo]" >&2; exit 2 ;;
esac
