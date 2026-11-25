#!/usr/bin/env bash

# =============================================
#   archenemy - lib/switch-rice.sh (biblioteka)
#   Wspólna logika przełączania rice'a — źródłowana (source) przez
#   stuby scripts/changing-theme-scripts/*.sh, które ustawiają
#   RICE_NAME i nic więcej. Jedna implementacja zamiast trzech kopii:
#   każda zmiana (makoctl reload, czekanie na waybar, ...) wchodzi RAZ,
#   parytet rice'ów jest strukturalny, nie przez copy-paste.
#   Wzorzec jak install/bootloader.sh (biblioteka źródłowana).
#
#   Katalog lib/ NIE pojawia się w menu rofi — rofi_theme_switcher
#   globuje płasko: scripts/changing-theme-scripts/*.sh.
# =============================================

# Stub musi ustawić RICE_NAME przed source.
if [[ -z "${RICE_NAME:-}" ]]; then
    notify-send -a archenemy "archenemy" "switch-rice.sh: RICE_NAME not set (broken stub)."
    exit 1
fi

ARCHENEMY_DIR="$HOME/archenemy"
RICE_DIR="$ARCHENEMY_DIR/rices/$RICE_NAME"
CONFIG_DIR="$HOME/.config"
CURRENT_RICE="$ARCHENEMY_DIR/.current_rice"
DATA_DIR="$ARCHENEMY_DIR/data"

# ─── KONTROLA WSTĘPNA ─────────────────────────────────────────────────────────

if [[ ! -d "$RICE_DIR" ]]; then
    notify-send -a archenemy "archenemy" "Rice '$RICE_NAME' not found in $ARCHENEMY_DIR/rices."
    exit 1
fi

# ─── BLOKADA ──────────────────────────────────────────────────────────────────
# Dwa szybkie Super+T to dwa równoległe procesy: bez blokady jeden kasował
# link, drugi robił `ln -s` do jeszcze istniejącego linku-katalogu i nowy
# link lądował WEWNĄTRZ rices/<rice>/<folder>/ (mieszany rice, śmieci w repo
# — audyt 2026-09-23). Drugie przełączenie czeka na pierwsze i nakłada się
# po nim (wygrywa ostatni wybór). Procesy tła (waybar, swayosd, tapety)
# dostają `9>&-` — inaczej trzymałyby blokadę do końca sesji.
# SWITCH_RICE_LOCK_WAIT: ile sekund czekać (domyślnie 30) — tests/switch-rice.sh
# skraca go, żeby sprawdzić zajętą blokadę bez 30 s czekania.
# Blokada leży w prywatnym katalogu sesji (lib/runtime-dir.sh): we wspólnym
# /tmp inny użytkownik mógł ją założyć i zająć pierwszy (audyt S12). Bez
# takiego katalogu przełączenie odmawia, zamiast wracać do /tmp.
# shellcheck source=scripts/lib/runtime-dir.sh
source "$ARCHENEMY_DIR/scripts/lib/runtime-dir.sh"
if ! RUN_DIR="$(archenemy_runtime_dir)"; then
    notify-send -a archenemy "archenemy" "No private runtime directory (XDG_RUNTIME_DIR) — rice switch cancelled."
    exit 1
fi
LOCK_FILE="$RUN_DIR/archenemy-switch-rice.lock"
LOCK_WAIT="${SWITCH_RICE_LOCK_WAIT:-30}"
[[ "$LOCK_WAIT" =~ ^[0-9]+$ ]] || LOCK_WAIT=30
exec 9>"$LOCK_FILE"
if ! flock -w "$LOCK_WAIT" 9; then
    notify-send -a archenemy "archenemy" "Another rice switch is still running — try again."
    exit 1
fi

# Już aktywny? Nakładamy MIMO TO (re-apply): wcześniejszy early-exit czynił
# na wpół nałożony rice (przerwane przełączenie, ręcznie skasowany symlink)
# nienaprawialnym z menu — .current_rice mówił „aktywny", a stan był popsuty.
# Ponowne nałożenie jest idempotentne i tanie.

# ─── BŁĘDY CONFIGU „PRZED” ────────────────────────────────────────────────────
# Odczyt PRZED podlinkowaniem: Hyprland z autoreloadem wczytuje zmieniony config
# przez inotify, zanim padnie `hyprctl reload`, więc odczyt po linkowaniu mógłby
# już zawierać nowy błąd i reload wyglądałby na czysty (lib/hypr-apply.sh).
# Bez reloadu ani powiadomień w trybie „tylko linki” (install.sh [9]).
HYPR_APPLY_LIB="$ARCHENEMY_DIR/scripts/hypr/lib/hypr-apply.sh"
if [[ -f "$HYPR_APPLY_LIB" ]]; then
    # shellcheck source=../../hypr/lib/hypr-apply.sh
    source "$HYPR_APPLY_LIB"
else
    # Niepełne drzewo: dawny goły reload, bez odczytu błędów.
    hypr_config_errors() { :; }
    hypr_reload_checked() { hyprctl reload >/dev/null 2>&1 || return 1; }
fi
HYPR_ERRORS_BEFORE=""
[[ "${SWITCH_RICE_LINK_ONLY:-0}" == 1 ]] || HYPR_ERRORS_BEFORE="$(hypr_config_errors)"

# ─── HOME-MANAGER (D10) ───────────────────────────────────────────────────────
# Przed JAKĄKOLWIEK zmianą (sprzątanie, .bak, ln, .current_rice): folder
# rice'a, plik w nim albo samo ~/.config jako dowiązanie do /nix/store =
# zarządza tym home-manager. Wtedy nic nie ruszamy — porada na stderr,
# powiadomienie (poza trybem „tylko linki”) i kod 3. Bez biblioteki
# (niepełne drzewo) dawne zachowanie.
HM_LIB="$ARCHENEMY_DIR/scripts/lib/hm-conflict.sh"
if [[ -f "$HM_LIB" ]]; then
    # shellcheck source=../../lib/hm-conflict.sh
    source "$HM_LIB"
    mapfile -t HM_HITS < <(hm_rice_conflicts "$RICE_DIR" "$CONFIG_DIR")
    if (( ${#HM_HITS[@]} > 0 )); then
        hm_advice "${HM_HITS[@]}" >&2
        [[ "${SWITCH_RICE_LINK_ONLY:-0}" == 1 ]] || notify-send -a archenemy -u critical "archenemy" \
            "Rice '$RICE_NAME' not applied: home-manager manages ${HM_HITS[0]/#$HOME/\~} (nothing changed). Remove it from your home-manager configuration, then try again."
        exit 3
    fi
fi

# ─── SYMLINKI ─────────────────────────────────────────────────────────────────

# Sprzątanie: usuń z ~/.config KAŻDY symlink wskazujący na jakikolwiek rice.
# Bez tego zostałyby foldery poprzedniego motywu, których nowy rice nie ma
# (np. mako z innego rice'a) — cichy przeciek wyglądu.
# Kanonizujemy OBIE strony porównania: readlink -f daje ścieżkę fizyczną,
# a $HOME bywa logiczny (np. /home jako symlink) — porównanie fizycznej
# z logiczną nigdy nie pasowało i sprzątanie cicho się pomijało.
RICES_REAL=$(readlink -f "$ARCHENEMY_DIR/rices")
OLD_ZSH_LINK=0
for link in "$CONFIG_DIR"/*; do
    [[ -L "$link" ]] || continue
    target=$(readlink -f "$link")
    if [[ -n "$RICES_REAL" && "$target" == "$RICES_REAL/"* ]]; then
        rm "$link"
        [[ "$link" == "$CONFIG_DIR/zsh" ]] && OLD_ZSH_LINK=1
    fi
done

# ─── MIGRACJA: ~/.config/zsh ZDOTDIR-a (R3, 2026-11-24) ──────────────────────
# Do 2026-11-24 wygląd zsh był folderem rices/<rice>/zsh, więc Super+T
# odkładał prawdziwy ~/.config/zsh użytkownika (popularny ZDOTDIR: .zshrc,
# historia) do zsh.bak-<czas> i linkował tam rice — powłoka „znikała”. Dziś
# folder nazywa się archenemy-zsh (→ ~/.config/archenemy-zsh, nazwa, której
# nikt inny nie używa), a ~/.config/zsh nie jest przez nas ruszany.
# Sprzątanie po starej wersji, jednorazowe i tylko przez mv: stare dowiązanie
# ~/.config/zsh → rices/ usunęła pętla wyżej (było nasze). Jeśli właśnie je
# usunęliśmy, miejsce jest wolne i leży kopia o NASZYM wzorcu nazwy
# zsh.bak-RRRRMMDD_GGMMSS, wraca najnowsza (nazwa sortuje się po czasie).
# Kopia będąca dowiązaniem do rices/ to nasz link bez danych — zniknęła już
# w pętli wyżej. Starsze kopie i inne nazwy zostają.
# Bez starego dowiązania nic nie przywracamy: użytkownik naprawił już sam.
if (( OLD_ZSH_LINK )) && [[ ! -e "$CONFIG_DIR/zsh" && ! -L "$CONFIG_DIR/zsh" ]]; then
    zsh_bak=""
    for b in "$CONFIG_DIR"/zsh.bak-*; do
        [[ "${b##*/}" =~ ^zsh\.bak-[0-9]{8}_[0-9]{6}$ ]] || continue
        [[ -e "$b" || -L "$b" ]] && zsh_bak="$b"
    done
    if [[ -n "$zsh_bak" ]] && mv "$zsh_bak" "$CONFIG_DIR/zsh"; then
        zsh_msg="Restored ~/.config/zsh from ${zsh_bak##*/} (an earlier rice switch had moved it there). Rice zsh colours now live in ~/.config/archenemy-zsh."
        echo "$zsh_msg"
        [[ "${SWITCH_RICE_LINK_ONLY:-0}" == 1 ]] || notify-send -a archenemy "archenemy" "$zsh_msg"
    fi
fi

for src in "$RICE_DIR"/*/; do
    [[ -d "$src" ]] || continue
    name=$(basename "$src")
    dest="$CONFIG_DIR/$name"

    # Coś użytkownika na miejscu folderu rice'a? Odłóż kopię zapasową, nigdy
    # nie kasuj: prawdziwy katalog ALBO symlink spoza rices/ (np. GNU stow —
    # repo jest publiczne, cudza konfiguracja nie może zniknąć; linki do
    # rices/ usunęła już pętla sprzątająca wyżej).
    if [[ -e "$dest" || -L "$dest" ]]; then
        mv "$dest" "$dest.bak-$(date +%Y%m%d_%H%M%S)"
    fi

    # -n: link-katalog na miejscu docelowym to plik do podmiany, nie katalog
    # do wejścia (bez -n link lądował wewnątrz starego rice'a).
    ln -sfn "${src%/}" "$dest"
done

echo "$RICE_NAME" > "$CURRENT_RICE"

# Tryb „tylko linki" (install.sh [9]): symlinki + .current_rice i koniec —
# bez tapety, flux-wall, hyprctl reload, restartu waybara/swayosd i
# powiadomień. Instalator sam ogłasza wynik, a restart paska w środku
# instalacji (albo bez działającego Hyprlanda) nie ma sensu. Jedna
# implementacja linkowania zamiast kopii pętli w install.sh (audyt 2026-09-25).
[[ "${SWITCH_RICE_LINK_ONLY:-0}" == 1 ]] && exit 0

# ─── PRZYWRÓĆ OSTATNIĄ TAPETĘ (jeśli była) ───────────────────────────────────

WALLPAPER_SWITCHER="$ARCHENEMY_DIR/scripts/rofi/rofi_wallpaper_switcher.sh"
if [[ -f "$DATA_DIR/wallpaper.dat" && -f "$WALLPAPER_SWITCHER" ]]; then
    bash "$WALLPAPER_SWITCHER" --restore 9>&-
fi

# ─── FLUX-WALL (tapeta liczona shaderem) ─────────────────────────────────────
# Rice deklaruje ją plikiem rices/<rice>/flux-wall.conf. `autostart` zatrzymuje
# instancję poprzedniego rice'a i startuje dla nowego, jeśli ma deklarację;
# brak binarki (install.sh nie zbudował) lub brak deklaracji = cicho nic —
# hyprpaper zostaje tapetą (działa zawsze, flux-wall rysuje nad nim).
FLUX_WALL="$ARCHENEMY_DIR/scripts/wallpapers/flux-wall.sh"
[[ -f "$FLUX_WALL" ]] && bash "$FLUX_WALL" autostart 9>&-

# ─── PRZEŁADOWANIE ───────────────────────────────────────────────────────────

# Sukces = brak NOWYCH błędów configu po reloadzie, nie kod wyjścia hyprctl
# (kody: lib/hypr-apply.sh). Wynik ogłasza powiadomienie na końcu.
HYPR_RELOAD_ERRORS="$(hypr_reload_checked "$HYPR_ERRORS_BEFORE" 9>&-)"
HYPR_RELOAD_RC=$?

# Waybar nie łapie zmian configu po hyprctl reload — trzeba go zrestartować.
# Poczekaj, aż stara instancja REALNIE zniknie: start nowej obok umierającej
# = dwa waybary (podwójny pasek na monitorze) + "Failed to register: Timeout"
# przy rejestracji IPC. Po ~2 s dobij pkill -9 (gdyby waybar wisiał).
# -x = dokładna nazwa procesu (parytet z pgrep -x niżej), nie regex „zawiera".
pkill -x waybar
for _ in $(seq 1 20); do
    pgrep -x waybar >/dev/null || break
    sleep 0.1
done
if pgrep -x waybar >/dev/null; then
    pkill -9 -x waybar
    sleep 0.2
fi
waybar 9>&- & disown

# Mako czyta config tylko przy starcie — bez reloadu notyfikacje zostają
# w motywie POPRZEDNIEGO rice'a (np. białe mako w tronie).
makoctl reload >/dev/null 2>&1

# swayosd-server też czyta style.css tylko przy starcie (brak live-reloadu),
# więc po zmianie rice'a restart, żeby OSD jasności miało motyw nowego rice'a.
# Ten sam wyścig co przy waybarze wyżej (stara instancja obok nowej) —
# poczekaj, aż naprawdę zniknie, zanim odpalisz kolejną.
if command -v swayosd-server >/dev/null 2>&1; then
    pkill -x swayosd-server 2>/dev/null
    for _ in $(seq 1 20); do
        pgrep -x swayosd-server >/dev/null || break
        sleep 0.1
    done
    pgrep -x swayosd-server >/dev/null && pkill -9 -x swayosd-server 2>/dev/null
    swayosd-server 9>&- & disown
fi

# hyprpaper.conf jest wspólny (warstwa maszynowa, symlink w każdym rice),
# więc restart hyprpapera przy zmianie rice'a nie jest już potrzebny —
# tapety przywraca --restore wyżej (z własnym fallbackiem restartu).

# „applied” tylko, gdy Hyprland wczytał config bez nowych błędów (albo nie ma
# sesji: zmiana wejdzie przy starcie). Inaczej krytyczne powiadomienie z
# pierwszym błędem — linki zostają, poprawkę wskazuje treść błędu.
case $HYPR_RELOAD_RC in
    0|3) notify-send -a archenemy "archenemy" "Rice '$RICE_NAME' applied." ;;
    2)   notify-send -a archenemy -u critical "archenemy" "Rice '$RICE_NAME' switched, but Hyprland reports a config error: $(head -n1 <<<"$HYPR_RELOAD_ERRORS")" ;;
    *)   notify-send -a archenemy -u critical "archenemy" "Rice '$RICE_NAME' switched, but Hyprland did not respond to reload — reload it manually." ;;
esac
