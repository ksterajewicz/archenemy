#!/bin/bash
# =============================================
#   Wspólna izolacja środowiska testów na atrapach.
#   Wczytaj przed mktemp; po ustawieniu trap wywołaj test_environment_init "$T".
# =============================================

# Pierwszy mktemp nie może dziedziczyć niezapisywalnego TMPDIR sesji.
export TMPDIR=/tmp LC_ALL=C.UTF-8 SHELL=/bin/bash
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
# Domyślne ścieżki XDG podążają za HOME, także gdy scenariusz zmienia HOME.
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

test_environment_init() {
    export HOME="$1/home" XDG_RUNTIME_DIR="$1/run" TMPDIR="$1/tmp"
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$TMPDIR" || return 1
    chmod 700 "$XDG_RUNTIME_DIR"
}
