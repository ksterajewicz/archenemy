#!/bin/bash

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
    notify-send "archenemy" "switch-rice.sh: RICE_NAME not set (broken stub)."
    exit 1
fi

ARCHENEMY_DIR="$HOME/archenemy"
RICE_DIR="$ARCHENEMY_DIR/rices/$RICE_NAME"
CONFIG_DIR="$HOME/.config"
CURRENT_RICE="$ARCHENEMY_DIR/.current_rice"
DATA_DIR="$ARCHENEMY_DIR/data"

# ─── KONTROLA WSTĘPNA ─────────────────────────────────────────────────────────

if [[ ! -d "$RICE_DIR" ]]; then
    notify-send "archenemy" "Rice '$RICE_NAME' not found in $ARCHENEMY_DIR/rices."
    exit 1
fi

# Już aktywny? Nakładamy MIMO TO (re-apply): wcześniejszy early-exit czynił
# na wpół nałożony rice (przerwane przełączenie, ręcznie skasowany symlink)
# nienaprawialnym z menu — .current_rice mówił „aktywny", a stan był popsuty.
# Ponowne nałożenie jest idempotentne i tanie.

# ─── SYMLINKI ─────────────────────────────────────────────────────────────────

# Sprzątanie: usuń z ~/.config KAŻDY symlink wskazujący na jakikolwiek rice.
# Bez tego zostałyby foldery poprzedniego motywu, których nowy rice nie ma
# (np. mako z innego rice'a) — cichy przeciek wyglądu.
# Kanonizujemy OBIE strony porównania: readlink -f daje ścieżkę fizyczną,
# a $HOME bywa logiczny (np. /home jako symlink) — porównanie fizycznej
# z logiczną nigdy nie pasowało i sprzątanie cicho się pomijało.
RICES_REAL=$(readlink -f "$ARCHENEMY_DIR/rices")
for link in "$CONFIG_DIR"/*; do
    [[ -L "$link" ]] || continue
    target=$(readlink -f "$link")
    [[ -n "$RICES_REAL" && "$target" == "$RICES_REAL/"* ]] && rm "$link"
done

for src in "$RICE_DIR"/*/; do
    [[ -d "$src" ]] || continue
    name=$(basename "$src")
    dest="$CONFIG_DIR/$name"

    # Prawdziwy katalog użytkownika (nie symlink)? Odłóż kopię zapasową.
    [[ -e "$dest" && ! -L "$dest" ]] && mv "$dest" "$dest.bak-$(date +%Y%m%d_%H%M%S)"
    [[ -L "$dest" ]] && rm "$dest"

    ln -s "${src%/}" "$dest"
done

echo "$RICE_NAME" > "$CURRENT_RICE"

# ─── PRZYWRÓĆ OSTATNIĄ TAPETĘ (jeśli była) ───────────────────────────────────

WALLPAPER_SWITCHER="$ARCHENEMY_DIR/scripts/rofi/rofi_wallpaper_switcher.sh"
if [[ -f "$DATA_DIR/wallpaper.dat" && -f "$WALLPAPER_SWITCHER" ]]; then
    bash "$WALLPAPER_SWITCHER" --restore
fi

# ─── PRZEŁADOWANIE ───────────────────────────────────────────────────────────

hyprctl reload

# Waybar nie łapie zmian configu po hyprctl reload — trzeba go zrestartować.
# Poczekaj, aż stara instancja REALNIE zniknie: start nowej obok umierającej
# = dwa waybary (podwójny pasek na monitorze) + "Failed to register: Timeout"
# przy rejestracji IPC. Po ~2 s dobij pkill -9 (gdyby waybar wisiał).
pkill waybar
for _ in $(seq 1 20); do
    pgrep -x waybar >/dev/null || break
    sleep 0.1
done
if pgrep -x waybar >/dev/null; then
    pkill -9 waybar
    sleep 0.2
fi
waybar & disown

# Mako czyta config tylko przy starcie — bez reloadu notyfikacje zostają
# w motywie POPRZEDNIEGO rice'a (np. białe mako w tronie).
makoctl reload >/dev/null 2>&1

# swayosd-server też czyta style.css tylko przy starcie (brak live-reloadu),
# więc po zmianie rice'a restart, żeby OSD jasności miało motyw nowego rice'a.
if command -v swayosd-server >/dev/null 2>&1; then
    pkill -x swayosd-server 2>/dev/null
    swayosd-server & disown
fi

# hyprpaper.conf jest wspólny (warstwa maszynowa, symlink w każdym rice),
# więc restart hyprpapera przy zmianie rice'a nie jest już potrzebny —
# tapety przywraca --restore wyżej (z własnym fallbackiem restartu).

notify-send "archenemy" "Rice '$RICE_NAME' applied."
