#!/usr/bin/env bash
# =============================================
#   archenemy - system-theme-installation.sh
#   Opcjonalnie: ekran logowania SDDM i menu startu GRUB-a w wyglądzie
#   rice'ów archenemy. Wszystko opt-in (pytania domyślnie N), cudzy motyw
#   nie jest zastępowany bez osobnego „y”, a całość cofa --remove.
#
#   Co robi (tylko to, co dotyczy tej maszyny):
#     SDDM — gdy SDDM jest włączonym menedżerem logowania:
#       /usr/share/sddm/themes/archenemy-<rice>/      motyw każdego rice'a
#       /etc/sddm.conf.d/20-archenemy-theme.conf      wybór motywu
#     GRUB — gdy GRUB jest używanym bootloaderem:
#       /boot/grub/themes/archenemy/                  jeden katalog, wszystkie rice'y
#       /etc/default/grub                             GRUB_THEME= (kopia: grub.archenemy.bak)
#       jedna regeneracja grub.cfg (install/bootloader.sh)
#     Zawsze:
#       /usr/local/lib/archenemy/system-theme-sync    skrypt roota: przenosi rice,
#                                                     logo, tapetę i monitor logowania
#       /etc/archenemy/system-theme.conf              czyje wybory czyta ten skrypt
#     Po osobnym „y”:
#       archenemy-system-theme.path/.service          usługa roota: zmiana rice'a
#                                                     (Super+T), logo, monitora
#                                                     logowania (Super+A) albo tapety
#                                                     (Super+W) sama przełącza oba motywy
#   Motywy powstają ze źródeł repo (src/system-theme/build.sh) w katalogu
#   tymczasowym jako zwykły użytkownik; root tylko kopiuje gotowe pliki.
#   Uszkodzony albo brakujący motyw GRUB-a nie blokuje startu systemu (GRUB
#   wraca do menu tekstowego — sprawdzone w QEMU, GRUB 2.16).
#
#   Użycie:
#     system-theme-installation.sh              instalacja (pyta)
#     system-theme-installation.sh --confirmed  jak wyżej, bez pierwszego
#                                               pytania (zadał je install.sh)
#     system-theme-installation.sh --remove     cofnięcie wszystkiego
#   Kod 0 = stan sprawdzony (także „nie ma czego motywować” i odmowa na
#   pytanie); 1 = popraw ręcznie według komunikatu; 2 = krok ręczny poza
#   Archem, nic nie zmieniono (brama platformy).
#
#   Haki testowe (tests/system-theme.sh), tylko z ARCHENEMY_TEST=1:
#   ARCHENEMY_SYSROOT — katalog podstawiany za / dla plików systemowych;
#   ARCHENEMY_BOOT_DIR — /boot (hak install/bootloader.sh).
# =============================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
retry='bash ~/archenemy/install/system-theme-installation.sh'

MODE=install; CONFIRMED=0
for arg in "$@"; do
    case "$arg" in
        --remove)    MODE=remove ;;
        --confirmed) CONFIRMED=1 ;;
        *) echo "Usage: system-theme-installation.sh [--confirmed | --remove]" >&2; exit 1 ;;
    esac
done

# ─── PLATFORMA ────────────────────────────────────────────────────────────────
# Wszystko niżej to ścieżki Archa (/boot/grub, grub-mkconfig, katalog motywów
# SDDM). Poza Archem i pochodnymi: instrukcja i kod 2, zanim padnie polecenie.
# shellcheck source=install/lib/pkg.sh
if ! source "$ROOT/install/lib/pkg.sh"; then
    echo -e "  ${RED}✗ Cannot load install/lib/pkg.sh — platform unknown, nothing was changed.${NC}"
    exit 1
fi
if ! pkg_gate "Login screen and boot menu themes"; then
    case "$PKG_ROUTE" in
        fedora)
            echo "    Fedora keeps GRUB in /boot/grub2 and regenerates it with grub2-mkconfig;"
            echo "    this helper only knows the Arch layout. The theme sources are in"
            echo "    src/system-theme/ (build.sh builds them into any directory)." ;;
        nixos)
            echo "    NixOS sets both from configuration.nix:"
            echo "      services.displayManager.sddm.theme and boot.loader.grub.theme"
            echo "    The theme sources are in src/system-theme/ (build.sh builds them)." ;;
    esac
    exit 2
fi
# shellcheck source=install/bootloader.sh
if ! source "$ROOT/install/bootloader.sh"; then
    echo -e "  ${RED}✗ Cannot load install/bootloader.sh — nothing was changed.${NC}"
    exit 1
fi

SYSROOT=""
[[ "${ARCHENEMY_TEST:-}" == 1 ]] && SYSROOT="${ARCHENEMY_SYSROOT:-}"

BUILD="$ROOT/src/system-theme/build.sh"
SYNC_SRC="$ROOT/src/system-theme/system-theme-sync.sh"
SYNC="$SYSROOT/usr/local/lib/archenemy/system-theme-sync"
CONF="$SYSROOT/etc/archenemy/system-theme.conf"
SDDM_THEMES="$SYSROOT/usr/share/sddm/themes"
SDDM_DROPIN="$SYSROOT/etc/sddm.conf.d/20-archenemy-theme.conf"
GRUB_DEFAULT="$SYSROOT/etc/default/grub"
GRUB_BACKUP="$GRUB_DEFAULT.archenemy.bak"
# _BL_BOOT_DIR: /boot albo atrapa z haka install/bootloader.sh.
GRUB_THEME_DIR="$_BL_BOOT_DIR/grub/themes/archenemy"
GRUB_THEME_PATH="/boot/grub/themes/archenemy/theme.txt"
UNIT_DIR="$SYSROOT/etc/systemd/system"
UNIT_PATH="$UNIT_DIR/archenemy-system-theme.path"
UNIT_SERVICE="$UNIT_DIR/archenemy-system-theme.service"
STATE_DIR="$HOME/archenemy"

ok()   { echo -e "  ${GREEN}✓ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; }
bad()  { echo -e "  ${RED}✗ $1${NC}"; }
ask()  { local reply; read -rp "  $1 [y/N]: " reply || reply=""; [[ "$reply" =~ ^[Yy]$ ]]; }

if (( EUID == 0 )) && [[ "${ARCHENEMY_TEST:-}" != 1 ]]; then
    bad "Run this as your own user, not as root — it asks for sudo where needed."
    exit 1
fi

# ─── ODCZYT STANU SYSTEMU ─────────────────────────────────────────────────────

# Czy SDDM jest włączonym menedżerem logowania (display-manager.service).
sddm_is_display_manager() {
    local link="$UNIT_DIR/display-manager.service" target
    command -v sddm >/dev/null 2>&1 || return 1
    [[ -L "$link" ]] || return 1
    target="$(readlink "$link")"
    [[ "${target##*/}" == sddm.service ]]
}

# Motyw, który SDDM naprawdę weźmie: ostatni Current= w sekcji [Theme]
# w kolejności czytania SDDM (domyślne pakietu, /etc/sddm.conf.d po nazwie,
# na końcu /etc/sddm.conf). Ustawia SDDM_THEME i SDDM_THEME_FILE (pusto =
# nikt nie ustawił).
SDDM_THEME=""; SDDM_THEME_FILE=""
sddm_effective_theme() {
    local file value
    local LC_ALL=C
    SDDM_THEME=""; SDDM_THEME_FILE=""
    for file in "$SYSROOT"/usr/lib/sddm/sddm.conf.d/*.conf "$SYSROOT"/etc/sddm.conf.d/*.conf "$SYSROOT/etc/sddm.conf"; do
        [[ -f "$file" ]] || continue
        value="$(awk '
            /^[[:space:]]*\[/ { section = $0; gsub(/[[:space:]]/, "", section) }
            section == "[Theme]" && /^[[:space:]]*Current[[:space:]]*=/ {
                sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print "=" $0
            }' "$file" | tail -n1)"
        [[ -n "$value" ]] || continue
        SDDM_THEME="${value#=}"; SDDM_THEME_FILE="$file"
    done
}

# Ostatnia niezakomentowana wartość klucza z /etc/default/grub (bez cudzysłowów).
grub_default_value() {
    local line
    line="$(grep -E "^[[:space:]]*$1=" "$GRUB_DEFAULT" 2>/dev/null | tail -n1)" || return 1
    line="${line#*=}"; line="${line%\"}"; line="${line#\"}"; line="${line%\'}"; line="${line#\'}"
    printf '%s\n' "$line"
}

# ─── USUWANIE ─────────────────────────────────────────────────────────────────

remove_all() {
    local dir failed=0 old_theme tmp
    echo -e "${CYAN}Removing archenemy login screen and boot menu themes...${NC}"

    if [[ -e "$UNIT_PATH" || -e "$UNIT_SERVICE" ]]; then
        sudo systemctl disable --now archenemy-system-theme.path >/dev/null 2>&1 || true
        sudo rm -f "$UNIT_PATH" "$UNIT_SERVICE"
        sudo systemctl daemon-reload >/dev/null 2>&1 || true
        if [[ -e "$UNIT_PATH" || -e "$UNIT_SERVICE" ]]; then bad "Could not remove the systemd units in $UNIT_DIR"; failed=1
        else ok "Automatic switching service removed"; fi
    fi

    if [[ -e "$SDDM_DROPIN" ]]; then
        sudo rm -f "$SDDM_DROPIN"
        if [[ -e "$SDDM_DROPIN" ]]; then bad "Could not remove $SDDM_DROPIN"; failed=1
        else ok "SDDM is back on its own theme setting"; fi
    fi
    for dir in "$SDDM_THEMES"/archenemy-*/; do
        # Tylko katalogi, które wyglądają na nasze (metadane motywu archenemy).
        [[ -d "$dir" && ! -L "${dir%/}" ]] || continue
        grep -q '^Theme-Id=archenemy-' "$dir/metadata.desktop" 2>/dev/null || continue
        sudo rm -rf "${dir%/}"
        [[ -e "${dir%/}" ]] && { bad "Could not remove ${dir%/}"; failed=1; }
    done

    # GRUB: najpierw konfiguracja przestaje wskazywać motyw, dopiero potem
    # znika katalog — inaczej GRUB przy starcie czekałby na brakujący plik.
    if [[ "$(grub_default_value GRUB_THEME 2>/dev/null)" == "$GRUB_THEME_PATH" ]]; then
        old_theme=""
        [[ -f "$GRUB_BACKUP" ]] && old_theme="$(grep -E '^[[:space:]]*GRUB_THEME=' "$GRUB_BACKUP" | tail -n1)"
        tmp="$(mktemp)" || { bad "mktemp failed"; return 1; }
        if [[ -n "$old_theme" ]]; then
            awk -v keep="$old_theme" '/^[[:space:]]*GRUB_THEME=/ { if (!done) { print keep; done = 1 } next } { print }' "$GRUB_DEFAULT" > "$tmp"
        else
            grep -vE '^[[:space:]]*GRUB_THEME=' "$GRUB_DEFAULT" > "$tmp"
        fi
        if sudo cp "$tmp" "$GRUB_DEFAULT" && [[ "$(grub_default_value GRUB_THEME 2>/dev/null)" != "$GRUB_THEME_PATH" ]]; then
            ok "GRUB_THEME restored in /etc/default/grub (the backup stays: ${GRUB_BACKUP##*/})"
            if regenerate_bootloader "boot menu theme removed"; then
                sudo rm -rf "$GRUB_THEME_DIR"
            else
                warn "grub.cfg was not regenerated — $GRUB_THEME_DIR stays until it is. Run: sudo grub-mkconfig -o /boot/grub/grub.cfg"
                failed=1
            fi
        else
            bad "Could not restore GRUB_THEME in /etc/default/grub — the theme directory stays."
            failed=1
        fi
        rm -f "$tmp"
    elif [[ -d "$GRUB_THEME_DIR" ]]; then
        # Konfiguracja już nie wskazuje naszego motywu — katalog jest zbędny.
        sudo rm -rf "$GRUB_THEME_DIR"
    fi
    [[ -e "$GRUB_THEME_DIR" && $failed -eq 0 ]] && { bad "Could not remove $GRUB_THEME_DIR"; failed=1; }

    sudo rm -f "$SYNC" "$CONF"
    sudo rmdir "${SYNC%/*}" "${CONF%/*}" 2>/dev/null || true
    [[ -e "$SYNC" || -e "$CONF" ]] && { bad "Could not remove $SYNC or $CONF"; failed=1; }

    if (( failed )); then
        bad "Removal incomplete — see the messages above. Retry: $retry --remove"
        return 1
    fi
    ok "archenemy system themes removed"
    return 0
}

if [[ "$MODE" == remove ]]; then
    remove_all
    exit $?
fi

# ─── INSTALACJA: CO DOTYCZY TEJ MASZYNY ───────────────────────────────────────

echo -e "${CYAN}Login screen (SDDM) and boot menu (GRUB) in the look of your rice${NC}"
for needed in "$BUILD" "$SYNC_SRC"; do
    [[ -f "$needed" ]] || { bad "Missing ${needed#"$ROOT"/} — update archenemy first."; exit 1; }
done

WANT_SDDM=0; WANT_GRUB=0
if sddm_is_display_manager; then
    WANT_SDDM=1
elif command -v sddm >/dev/null 2>&1; then
    echo "  SDDM is installed but is not the enabled display manager — login screen skipped."
else
    echo "  SDDM is not installed — login screen skipped (archenemy does not install a display manager)."
fi
BOOTLOADER="$(detect_bootloader)"
if [[ "$BOOTLOADER" == grub ]]; then
    WANT_GRUB=1
elif [[ "$BOOTLOADER" == systemd-boot ]]; then
    echo "  systemd-boot has no themes — boot menu skipped."
else
    echo "  GRUB not detected — boot menu skipped."
fi
if (( ! WANT_SDDM && ! WANT_GRUB )); then
    echo "  Nothing to theme on this machine — nothing was changed."
    exit 0
fi

# Cudza konfiguracja: nie zastępujemy bez osobnego „y”, a plików, które
# wygrywają z naszymi, nie edytujemy wcale.
if (( WANT_SDDM )); then
    sddm_effective_theme
    if [[ "$SDDM_THEME_FILE" == "$SYSROOT/etc/sddm.conf" && "$SDDM_THEME" != archenemy-* ]]; then
        warn "/etc/sddm.conf sets Current=${SDDM_THEME:-<empty>} and wins over /etc/sddm.conf.d."
        echo "    archenemy does not edit that file. Remove the Current= line there, then run: $retry"
        WANT_SDDM=0
    elif [[ -n "$SDDM_THEME" && "$SDDM_THEME" != archenemy-* ]]; then
        echo "  SDDM uses the theme '$SDDM_THEME' (set in ${SDDM_THEME_FILE#"$SYSROOT"})."
        if ! ask "Use the archenemy login screen instead?"; then
            echo "  Login screen left as it is."
            WANT_SDDM=0
        fi
    fi
fi
if (( WANT_GRUB )); then
    if [[ ! -f "$GRUB_DEFAULT" ]]; then
        warn "/etc/default/grub not found — boot menu skipped."
        WANT_GRUB=0
    elif [[ "$(grub_default_value GRUB_TERMINAL_OUTPUT 2>/dev/null)" == console ]]; then
        warn "GRUB_TERMINAL_OUTPUT=console in /etc/default/grub: GRUB shows a text menu and ignores themes."
        echo "    Comment that line out, then run: $retry"
        WANT_GRUB=0
    else
        current_grub_theme="$(grub_default_value GRUB_THEME 2>/dev/null || true)"
        if [[ -n "$current_grub_theme" && "$current_grub_theme" != "$GRUB_THEME_PATH" ]]; then
            echo "  GRUB uses the theme '$current_grub_theme' (GRUB_THEME in /etc/default/grub)."
            if ! ask "Use the archenemy boot menu instead?"; then
                echo "  Boot menu left as it is."
                WANT_GRUB=0
            fi
        fi
    fi
fi
if (( ! WANT_SDDM && ! WANT_GRUB )); then
    echo "  Nothing was changed."
    exit 0
fi

echo "  This will write, as root:"
(( WANT_SDDM )) && echo "    /usr/share/sddm/themes/archenemy-<rice>/ and /etc/sddm.conf.d/20-archenemy-theme.conf"
(( WANT_GRUB )) && echo "    /boot/grub/themes/archenemy/, GRUB_THEME in /etc/default/grub (backup kept) and regenerate grub.cfg"
echo "    /usr/local/lib/archenemy/system-theme-sync and /etc/archenemy/system-theme.conf"
(( WANT_GRUB )) && echo "  A broken GRUB theme does not stop the boot: GRUB falls back to its text menu."
echo "  Undo everything: $retry --remove"
if (( ! CONFIRMED )) && ! ask "Continue?"; then
    echo "  Nothing was changed."
    exit 0
fi

# ─── BUDOWANIE (bez roota) ────────────────────────────────────────────────────

WORK="$(mktemp -d)" || { bad "mktemp failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

GLYPH="$(bash "$ROOT/scripts/waybar/launcher-logo.sh" glyph 2>/dev/null)"
RICE_NOW=""
[[ -f "$STATE_DIR/.current_rice" ]] && { IFS= read -r RICE_NOW < "$STATE_DIR/.current_rice"; } 2>/dev/null
RICE_NOW="${RICE_NOW//[[:space:]]/}"
LOGO_NOW="$(bash "$ROOT/scripts/waybar/launcher-logo.sh" mode 2>/dev/null)"
[[ "$LOGO_NOW" == archenemy ]] || LOGO_NOW=distro

SDDM_RICES=()
if (( WANT_SDDM )); then
    mapfile -t SDDM_RICES < <(bash "$BUILD" rices sddm)
    if (( ${#SDDM_RICES[@]} == 0 )); then
        warn "No rice has login screen sources — login screen skipped."
        WANT_SDDM=0
    fi
    for rice in "${SDDM_RICES[@]}"; do
        if ! bash "$BUILD" sddm "$rice" "$WORK/sddm/archenemy-$rice"; then
            bad "Building the login screen of '$rice' failed — nothing was changed. Retry: $retry"
            exit 1
        fi
    done
fi

if (( WANT_GRUB )); then
    # GRUB liczy rozmiary w pikselach, więc potrzebna jest wysokość ekranu, na
    # którym firmware pokazuje menu: w laptopie to ekran wbudowany (eDP, LVDS,
    # DSI), inaczej monitor główny z warstwy maszynowej (data/monitors).
    # Bez danych: 1080. Położenia w motywie są w procentach — pomyłka zmienia
    # tylko wielkość liter.
    HEIGHT=""; HEIGHT_PRIMARY=""
    for dat in "$STATE_DIR"/data/monitors/*.dat; do
        [[ -f "$dat" ]] || continue
        res="$(grep -m1 '^RESOLUTION=' "$dat" | cut -d= -f2-)"
        [[ "$res" =~ ^[0-9]+x([0-9]{3,4})([^0-9]|$) ]] || continue
        case "$(grep -m1 '^MONITOR=' "$dat" | cut -d= -f2-)" in
            eDP*|LVDS*|DSI*) HEIGHT="${BASH_REMATCH[1]}" ;;
        esac
        grep -q '^ROLE=primary$' "$dat" && HEIGHT_PRIMARY="${BASH_REMATCH[1]}"
    done
    HEIGHT="${HEIGHT:-${HEIGHT_PRIMARY:-1080}}"
    (( 10#$HEIGHT >= 480 && 10#$HEIGHT <= 4320 )) || HEIGHT=1080
    GRUB_RICES="$(bash "$BUILD" rices grub)"
    ACTIVATE="${GRUB_RICES%%$'\n'*}:$LOGO_NOW"
    grep -qx -- "$RICE_NOW" <<< "$GRUB_RICES" && ACTIVATE="$RICE_NOW:$LOGO_NOW"
    grep -qx -- "${RICE_NOW%_beta}" <<< "$GRUB_RICES" && ACTIVATE="${RICE_NOW%_beta}:$LOGO_NOW"
    if ! bash "$BUILD" grub "$WORK/grub" -H "$HEIGHT" -g "$GLYPH" -a "$ACTIVATE"; then
        bad "Building the boot menu theme failed — nothing was changed. Retry: $retry"
        exit 1
    fi
fi

# ─── KOPIOWANIE (root) ────────────────────────────────────────────────────────

FAILED=0
if (( WANT_SDDM )); then
    sudo mkdir -p "$SDDM_THEMES" || FAILED=1
    for rice in "${SDDM_RICES[@]}"; do
        target="$SDDM_THEMES/archenemy-$rice"
        if ! sudo rm -rf "$target" || ! sudo cp -r "$WORK/sddm/archenemy-$rice" "$target" \
            || ! sudo chmod -R u=rwX,go=rX "$target" || [[ ! -f "$target/Main.qml" ]]; then
            bad "Could not install $target"
            FAILED=1
        fi
    done
    (( FAILED )) || ok "Login screen themes installed: ${SDDM_RICES[*]}"
fi

if (( WANT_GRUB && ! FAILED )); then
    # Nowy katalog obok, potem zamiana nazw: GRUB nie zobaczy połowy motywu.
    if sudo mkdir -p "${GRUB_THEME_DIR%/*}" && sudo rm -rf "$GRUB_THEME_DIR.new" "$GRUB_THEME_DIR.old" \
        && sudo cp -r "$WORK/grub" "$GRUB_THEME_DIR.new"; then
        [[ -d "$GRUB_THEME_DIR" ]] && sudo mv "$GRUB_THEME_DIR" "$GRUB_THEME_DIR.old"
        if sudo mv "$GRUB_THEME_DIR.new" "$GRUB_THEME_DIR"; then
            sudo rm -rf "$GRUB_THEME_DIR.old"
        else
            [[ -d "$GRUB_THEME_DIR.old" ]] && sudo mv "$GRUB_THEME_DIR.old" "$GRUB_THEME_DIR"
            FAILED=1
        fi
    else
        FAILED=1
    fi
    if (( FAILED )) || [[ ! -f "$GRUB_THEME_DIR/theme.txt" ]]; then
        bad "Could not install $GRUB_THEME_DIR"
        FAILED=1
    else
        ok "Boot menu theme installed in /boot/grub/themes/archenemy"
        # GRUB_THEME: kopia pliku raz, potem jedna linia; wynik odczytany z pliku.
        if [[ "$(grub_default_value GRUB_THEME 2>/dev/null || true)" != "$GRUB_THEME_PATH" ]]; then
            [[ -e "$GRUB_BACKUP" ]] || sudo cp -p "$GRUB_DEFAULT" "$GRUB_BACKUP"
            tmp="$WORK/grub-default"
            if grep -qE '^[[:space:]]*GRUB_THEME=' "$GRUB_DEFAULT"; then
                awk -v line="GRUB_THEME=\"$GRUB_THEME_PATH\"" \
                    '/^[[:space:]]*GRUB_THEME=/ { if (!done) { print line; done = 1 } next } { print }' "$GRUB_DEFAULT" > "$tmp"
            else
                { cat "$GRUB_DEFAULT"; printf '\n# archenemy: boot menu theme (remove with install/system-theme-installation.sh --remove)\nGRUB_THEME="%s"\n' "$GRUB_THEME_PATH"; } > "$tmp"
            fi
            if [[ ! -f "$GRUB_BACKUP" ]] || ! sudo cp "$tmp" "$GRUB_DEFAULT" \
                || [[ "$(grub_default_value GRUB_THEME 2>/dev/null || true)" != "$GRUB_THEME_PATH" ]]; then
                bad "Could not set GRUB_THEME in /etc/default/grub"
                FAILED=1
            fi
        fi
        if (( ! FAILED )); then
            if regenerate_bootloader "boot menu theme" \
                && grep -q 'themes/archenemy/theme.txt' "$_BL_BOOT_DIR/grub/grub.cfg" 2>/dev/null; then
                ok "grub.cfg points to the archenemy theme (visible at the next boot)"
            else
                warn "grub.cfg does not mention the theme yet. Run: sudo grub-mkconfig -o /boot/grub/grub.cfg"
                FAILED=1
            fi
        fi
    fi
fi

# ─── SKRYPT ROOTA I PIERWSZE ZASTOSOWANIE ─────────────────────────────────────

if (( ! FAILED )); then
    printf 'STATE_USER=%s\nSTATE_DIR=%s\nGLYPH=%s\nSDDM=%s\nGRUB=%s\n' \
        "$(id -un)" "$STATE_DIR" "$GLYPH" "$WANT_SDDM" "$WANT_GRUB" > "$WORK/system-theme.conf"
    if sudo install -D -m 755 "$SYNC_SRC" "$SYNC" && sudo install -D -m 644 "$WORK/system-theme.conf" "$CONF"; then
        if sync_log="$(sudo "$SYNC" 2>&1)"; then
            while IFS= read -r line; do [[ -n "$line" ]] && echo "    ${line#system-theme-sync: }"; done <<< "$sync_log"
            if (( WANT_SDDM )); then
                sddm_effective_theme
                if [[ "$SDDM_THEME" == archenemy-* ]]; then ok "SDDM theme now: $SDDM_THEME (visible at the next login screen)"
                else warn "SDDM still resolves to '${SDDM_THEME:-its default}' — your current rice may have no login screen yet."; fi
            fi
        else
            bad "The first run of system-theme-sync failed:"
            while IFS= read -r line; do echo "    $line"; done <<< "$sync_log"
            FAILED=1
        fi
    else
        bad "Could not install $SYNC or $CONF"
        FAILED=1
    fi
fi

if (( FAILED )); then
    bad "Setup incomplete — see the messages above. Undo: $retry --remove"
    exit 1
fi

# ─── USŁUGA (osobne „y”) ──────────────────────────────────────────────────────

echo ""
echo "  Automatic switching: a small root service watches your rice, system logo,"
echo "  wallpaper and login screen choice, and applies them to the login screen and"
echo "  boot menu by itself. Without it, run after a change:"
echo "    sudo /usr/local/lib/archenemy/system-theme-sync"
if [[ -f "$UNIT_PATH" ]] || ask "Install the automatic switching service?"; then
    # Ścieżka trafia do pliku jednostki systemd — tylko bezpieczne znaki.
    if [[ ! "$STATE_DIR" =~ ^/[A-Za-z0-9._/@+-]+$ ]]; then
        warn "Your home path has characters a systemd unit cannot carry safely — service skipped."
    else
        cat > "$WORK/unit.path" <<EOF
# archenemy: przełącza ekran logowania i menu startu po zmianie wyborów
# użytkownika. Zakłada install/system-theme-installation.sh, usuwa --remove.
[Unit]
Description=archenemy: watch rice, logo, wallpaper and login screen choices

[Path]
PathChanged=$STATE_DIR/.current_rice
PathChanged=$STATE_DIR/data/launcher-logo.dat
PathChanged=$STATE_DIR/data/login-screen.dat
PathChanged=$STATE_DIR/data/wallpaper.dat
Unit=archenemy-system-theme.service

[Install]
WantedBy=multi-user.target
EOF
        cat > "$WORK/unit.service" <<'EOF'
# archenemy: jeden obieg skryptu roota (kopia z repo, plik roota).
[Unit]
Description=archenemy: apply the rice to the login screen and boot menu
# Szybkie zmiany pod rząd nie mogą wyłączyć pilnowania plików.
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/local/lib/archenemy/system-theme-sync
NoNewPrivileges=yes
ProtectHome=read-only
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes
EOF
        if sudo install -D -m 644 "$WORK/unit.path" "$UNIT_PATH" && sudo install -D -m 644 "$WORK/unit.service" "$UNIT_SERVICE" \
            && sudo systemctl daemon-reload && sudo systemctl enable --now archenemy-system-theme.path \
            && systemctl is-active --quiet archenemy-system-theme.path; then
            ok "Automatic switching is on (archenemy-system-theme.path)"
        else
            bad "The service is not active. Check: systemctl status archenemy-system-theme.path"
            echo "    The themes themselves are installed; switch by hand with the command above."
            exit 1
        fi
    fi
else
    echo "  Service not installed — switch by hand with the command above."
fi

echo ""
ok "Done. Undo everything: $retry --remove"
exit 0
