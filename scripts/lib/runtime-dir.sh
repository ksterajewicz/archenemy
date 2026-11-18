#!/usr/bin/env bash
# =============================================
#   archenemy - lib/runtime-dir.sh
#   Prywatny katalog sesji na blokady, stan i logi — JEDNO miejsce wyboru.
#   Biblioteka — NIE uruchamiaj bezpośrednio. Source'ują ją skrypty, które
#   trzymają coś w katalogu sesji (switch-rice, window-history, guard
#   workspace'ów, monitor-settings, tapety, flux-wall, profile zasilania).
#
#   Problem (audyt 2026-11-05, S12): dawny zapas ${XDG_RUNTIME_DIR:-/tmp}
#   kładł blokady, stan Super+Tab i logi we wspólnym /tmp, gdy zmiennej
#   brakowało (su, cron, sesja bez logind). Inny użytkownik maszyny mógł
#   założyć te pliki pierwszy: zająć blokadę, czytać logi albo podsunąć
#   window-history.sh komendę do uruchomienia przy Super+Tab.
#
#   archenemy_runtime_dir wypisuje pierwszy katalog, który jest NASZ
#   (właściciel = bieżący użytkownik, zwykły katalog, nie symlink) i nikt
#   poza nami nie ma do niego praw (rwx------, jak wymaga specyfikacja XDG):
#     1. $XDG_RUNTIME_DIR (zwykła sesja),
#     2. /run/user/<UID> (ta sama sesja, gdy zmienna zginęła po drodze),
#     3. ${TMPDIR:-/tmp}/archenemy-<UID>, zakładany przez mkdir -m 700.
#   --existing: bez zakładania katalogu z p. 3 (diagnostyka tylko czyta).
#   Kod 1 i pusty wynik = żaden się nie nadaje (np. ktoś inny założył
#   katalog z p. 3 przed nami). Wołający wtedy odmawia albo pomija blokadę
#   czy log, ale nigdy nie wraca do wspólnego /tmp.
#   ARCHENEMY_RUNTIME_SYSTEM — hak testowy zamiast /run/user/<UID>.
#   Testy: bash tests/runtime-dir.sh
# =============================================

# Nasz katalog z prawami tylko dla właściciela (bity grupy i innych = 0).
_archenemy_private_dir() {
    local d="$1" mode
    [[ -n "$d" && -d "$d" && ! -L "$d" && -O "$d" ]] || return 1
    mode="$(stat -c %a "$d" 2>/dev/null)" || return 1
    [[ "$mode" =~ ^[0-7]+$ ]] || return 1
    (( (8#$mode & 8#077) == 0 && (8#$mode & 8#700) == 8#700 ))
}

archenemy_runtime_dir() {
    local d
    for d in "${XDG_RUNTIME_DIR:-}" "${ARCHENEMY_RUNTIME_SYSTEM:-/run/user/$UID}"; do
        if _archenemy_private_dir "$d"; then
            printf '%s\n' "$d"
            return 0
        fi
    done
    d="${TMPDIR:-/tmp}"
    d="${d%/}/archenemy-$UID"
    [[ "${1:-}" == --existing || -e "$d" || -L "$d" ]] || mkdir -m 700 "$d" 2>/dev/null
    if _archenemy_private_dir "$d"; then
        printf '%s\n' "$d"
        return 0
    fi
    return 1
}
