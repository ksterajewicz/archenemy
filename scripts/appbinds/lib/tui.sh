#!/bin/bash
# =============================================
#   archenemy - scripts/appbinds/lib/tui.sh
#   Wspólna obsługa klawiatury i drobiazgi TUI Super+A. Source'owana przez
#   appbinds.sh, autostart-picker.sh, update-archenemy.sh i testy, bez efektów
#   ubocznych przy wczytaniu.
# =============================================

# shellcheck disable=SC2034  # kolory dla skryptów source'ujących tę bibliotekę
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Czysty bashowy trim — NIE `| xargs`: xargs robi przetwarzanie cudzysłowów,
# więc `sh -c 'btop; read'` gubił apostrofy, a samotny apostrof wysypywał
# cały pipe („unmatched single quote" → „Empty command").
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Jeden klawisz bez Enter (menu/potwierdzenia — nie wolne wpisywanie tekstu).
# Zwraca $'\e' dla samego Escape, żeby wołający mógł potraktować go jak
# anulowanie. Strzałki, Home, F1… to sekwencje zaczynające się od Escape:
# czytamy je do końca i ignorujemy, inaczej strzałka działałaby jak Esc, a reszta
# sekwencji wpadałaby do następnego pola. Kod 1 = koniec wejścia.
read_key() {
    local prompt="$1" key="" next=""
    while :; do
        if ! IFS= read -rsn1 -p "$prompt" key && [[ -z "$key" ]]; then
            echo "" >&2
            return 1
        fi
        prompt=""
        if [[ "$key" == $'\e' ]] && IFS= read -rsn1 -t 0.02 next && [[ "$next" == "[" || "$next" == "O" ]]; then
            while IFS= read -rsn1 -t 0.02 next; do
                [[ "$next" =~ ^[A-Za-z~]$ ]] && break
            done
            continue
        fi
        break
    done
    echo "" >&2
    printf '%s' "$key"
}

# Pytanie tak/nie jednym klawiszem. Kod 0 = tak. confirm <pytanie> <Y|N>:
# Y = Enter znaczy tak, N = Enter znaczy nie. Esc i każdy inny klawisz to
# zawsze NIE, niezależnie od domyślnej (audyt TUI 2026-11-05: Esc na [Y/n]
# uruchamiał instalator).
confirm() {
    local question="$1" default="${2:-N}" hint="[y/N]" key
    [[ "$default" == "Y" ]] && hint="[Y/n]"
    key="$(read_key "  ${question} ${hint}: ")" || return 1
    case "$key" in
        y|Y) return 0 ;;
        "")  [[ "$default" == "Y" ]] ;;
        *)   return 1 ;;
    esac
}

# Zapis jednowartościowego pliku warstwy maszynowej (data/*.dat) — atomowo
# (tmp + mv), bo moduły waybara czytają te pliki co sekundę i nie mogą trafić
# na zapis w połowie. Jedno miejsce dla wszystkich menu TUI.
write_dat() {
    local file="$1" value="$2" tmp
    mkdir -p "$(dirname "$file")"
    tmp="$(mktemp "${file}.XXXXXX")" || { echo -e "  ${RED}✗ mktemp failed.${NC}"; return 1; }
    printf '%s\n' "$value" > "$tmp"
    chmod 644 "$tmp"   # mktemp daje 600 — zachowaj zwykłe prawa (jak inne data/*.dat)
    mv "$tmp" "$file"
}
