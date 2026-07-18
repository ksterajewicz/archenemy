#!/bin/bash

# =============================================
#   archenemy - rofi_network.sh
#   Menu sieci: reskan Wi-Fi + networkmanager_dmenu.
#
#   networkmanager_dmenu sam nie odświeża listy sieci,
#   więc bez reskanu menu pokazuje nieaktualne wyniki.
# =============================================

# Reskan tylko, gdy jest czym skanować (nmcli = NetworkManager)
if command -v nmcli &>/dev/null; then
    # rescan zgłasza błąd np. przy wyłączonym radiu — ignorujemy, menu i tak działa
    if nmcli device wifi rescan &>/dev/null; then
        command -v notify-send &>/dev/null \
            && notify-send -t 1500 "archenemy" "Skanuję sieci Wi-Fi…"
        sleep 1.5   # chwila na spłynięcie wyników skanu
    fi
fi

exec networkmanager_dmenu
