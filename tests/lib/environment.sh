#!/usr/bin/env bash
# =============================================
#   Wspólna izolacja środowiska testów na atrapach.
#   Wczytaj przed mktemp; po ustawieniu trap wywołaj test_environment_init "$T".
# =============================================

# Pierwszy mktemp nie może dziedziczyć niezapisywalnego TMPDIR sesji.
export TMPDIR=/tmp LC_ALL=C.UTF-8 SHELL=/bin/bash
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
# Domyślne ścieżki XDG podążają za HOME, także gdy scenariusz zmienia HOME.
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

# ── izolacja zapisów (D7F R3, przegląd Codexa D7) ──────────────────────────
# test_isolate <ścieżka pakietu> [argumenty] — wołane na samym początku
# pakietu: uruchamia go ponownie w prywatnej przestrzeni nazw (unshare -rm)
# z overlayem na każdym katalogu z ISOLATE_DIRS (górne warstwy w /dev/shm).
# Zapis, nadpisanie albo usunięcie czegokolwiek pod tymi katalogami trafia
# wyłącznie do górnej warstwy — prawdziwy system zostaje nietknięty, a
# test_escapes widzi każdą zmianę, także głęboko (np. /tmp/<cudzy>/plik,
# /root/…), bez fałszywych alarmów od innych procesów hosta.
# Zasięg: tylko katalogi, które udało się nakryć (lista w $ARCHENEMY_ISOLATED/dirs;
# /run się nie nakrywa — podmontowania). Nie obejmuje /dev/shm, /proc, /sys
# ani samego / (nazwy w / sprawdzają pakiety osobno). Bez unshare/overlay
# (np. kontener bez przestrzeni użytkownika) pakiet biegnie jak dotąd,
# a test_escapes zwraca 2 (pakiet wypisuje pominięcie, nie ✓).
# ARCHENEMY_NO_ISOLATE=1 wyłącza mechanizm.
ISOLATE_DIRS=(/tmp /var /root /home /etc /usr /opt /srv /boot /mnt)
test_isolate() {
    [[ -n "${ARCHENEMY_ISOLATED:-}" || -n "${ARCHENEMY_NO_ISOLATE:-}" ]] && return 0
    command -v unshare >/dev/null 2>&1 && unshare -rm true 2>/dev/null || return 0
    local base rc
    base="$(mktemp -d /dev/shm/archenemy-iso.XXXXXX 2>/dev/null)" && [[ -n "$base" && -d "$base" ]] || return 0
    # shellcheck disable=SC2016  # kod dla bash -c w przestrzeni nazw
    unshare -rm --propagation private bash -c '
        base="$1"; shift
        for d in "${@:2:$1}"; do
            [[ -d "$d" && ! -L "$d" ]] || continue
            n="${d//\//_}"; mkdir -p "$base/$n/u" "$base/$n/w" || continue
            mount -t overlay overlay -o "lowerdir=$d,upperdir=$base/$n/u,workdir=$base/$n/w" "$d" 2>/dev/null \
                && printf "%s\n" "$d" >> "$base/dirs"
        done
        shift "$(( $1 + 1 ))"
        export ARCHENEMY_ISOLATED="$base"
        cd "$PWD" 2>/dev/null || true   # katalog roboczy przez overlay, nie spod niego
        exec bash "$@"' _ "$base" "${#ISOLATE_DIRS[@]}" "${ISOLATE_DIRS[@]}" "$@"
    rc=$?
    rm -rf "${base:?}"
    exit "$rc"
}
# test_escapes <T> — ścieżki zmienione (utworzone, nadpisane, usunięte) poza <T>
# w nakrytych katalogach, po jednej na linię. 0 = żadnych, 1 = są, 2 = brak izolacji.
test_escapes() {
    [[ -n "${ARCHENEMY_ISOLATED:-}" && -s "$ARCHENEMY_ISOLATED/dirs" ]] || return 2
    local d rel p found=0
    while IFS= read -r d; do
        while IFS= read -r rel; do
            p="$d/${rel#./}"
            [[ "$p" == "$1" || "$p" == "$1"/* ]] && continue
            printf '%s\n' "$p"; found=1
        done < <(cd "$ARCHENEMY_ISOLATED/${d//\//_}/u" && find . -mindepth 1 \( ! -type d -o -type d -empty \) -print)
    done < "$ARCHENEMY_ISOLATED/dirs"
    return "$found"
}
# test_isolation_dirs — nakryte katalogi w jednej linii (do etykiet).
test_isolation_dirs() { [[ -n "${ARCHENEMY_ISOLATED:-}" ]] && tr '\n' ' ' < "$ARCHENEMY_ISOLATED/dirs"; }

test_environment_init() {
    export HOME="$1/home" XDG_RUNTIME_DIR="$1/run" TMPDIR="$1/tmp"
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$TMPDIR" || return 1
    chmod 700 "$XDG_RUNTIME_DIR"
}
