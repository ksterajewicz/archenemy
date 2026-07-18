#!/bin/bash

# =============================================
#   archenemy - tron.sh
#   Przełącza aktywny rice na: tron
#
#   Stub: cała logika w lib/switch-rice.sh (edytuj TAM, raz dla
#   wszystkich rice'ów). Nazwa pliku .sh = etykieta w menu rofi.
#   Nowy rice: skopiuj ten stub jako <etykieta>.sh i ustaw RICE_NAME
#   na nazwę folderu z rices/.
# =============================================

# shellcheck disable=SC2034  # konsumowane w source’owanej lib/switch-rice.sh
RICE_NAME="tron"
source "$(dirname "$(readlink -f "$0")")/lib/switch-rice.sh"
