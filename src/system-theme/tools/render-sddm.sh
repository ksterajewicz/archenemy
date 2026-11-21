#!/usr/bin/env bash
# =============================================
#   archenemy - src/system-theme/tools/render-sddm.sh
#   Podgląd motywu SDDM do pliku PNG — bez ekranu i bez uruchamiania SDDM.
#
#   Narzędzie deweloperskie (jak src/flux-wall/tools — NIE uruchamia go
#   install.sh): prawdziwy greeter Qt6 w trybie testowym
#   (`sddm-greeter-qt6 --test-mode --theme <katalog>`) pod Xvfb, zrzut
#   całego ekranu przez `import`.
#
#   Zrzut nie może zdradzać maszyny, na której powstał (rendery trafiają do
#   publicznego repo), a greeter w trybie testowym czyta prawdziwą listę
#   użytkowników i sesji. Dlatego całość biegnie w prywatnej przestrzeni
#   nazw (`unshare -rm`, jak test_isolate w tests/lib/environment.sh):
#     * /etc/passwd przykryty atrapą z jednym użytkownikiem `archenemy`,
#     * /usr/local/share przykryty tmpfs z jedną sesją „Hyprland” (SDDM
#       pokazuje sesje Wayland tylko, gdy istnieje /dev/dri — na serwerze
#       bez karty graficznej atrapa trafia więc do xsessions),
#     * /etc/hostname przykryty atrapą `archenemy`.
#   Host zostaje nietknięty; bez przestrzeni nazw narzędzie odmawia.
#
#   Użycie: render-sddm.sh [-s SZERxWYS] [-f KATALOG_FONTÓW] [-w SEKUNDY]
#                          <katalog motywu> <wynik.png>
#     -s  rozmiar ekranu (domyślnie 1920x1080)
#     -f  dodatkowy katalog fontów (np. rozpakowany ttf-jetbrains-mono-nerd,
#         gdy font nie jest zainstalowany w systemie); można powtarzać
#     -w  ile sekund czekać na narysowanie motywu (domyślnie 10; llvmpipe
#         na jednym rdzeniu potrzebuje kilku sekund)
#   Wymaga: sddm (sddm-greeter-qt6), xorg-server-xvfb (xvfb-run),
#   imagemagick (import), util-linux (unshare). Kod 0 = PNG zapisany.
#   Ostrzeżenia QML greetera idą na stderr — puste = motyw wczytał się czysto.
# =============================================

set -uo pipefail

SIZE="1920x1080"
WAIT=10
FONT_DIRS=()

usage() {
    sed -n '/^#   Użycie:/,/^#   Ostrzeżenia/p' "${BASH_SOURCE[0]}" | sed 's/^#   \{0,1\}//' >&2
    exit 2
}

# Etap wewnętrzny: już w przestrzeni nazw (patrz niżej).
if [[ "${1:-}" != --inside ]]; then
    while getopts ":s:f:w:" opt; do
        case "$opt" in
            s) SIZE="$OPTARG" ;;
            f) FONT_DIRS+=("$OPTARG") ;;
            w) WAIT="$OPTARG" ;;
            *) usage ;;
        esac
    done
    shift $((OPTIND - 1))
    [[ $# -eq 2 ]] || usage
    THEME="$1"; OUT="$2"

    [[ "$SIZE" =~ ^[0-9]+x[0-9]+$ ]] || { echo "render-sddm: bad size '$SIZE' (expected WIDTHxHEIGHT)" >&2; exit 2; }
    [[ "$WAIT" =~ ^[0-9]+$ ]] || { echo "render-sddm: bad wait '$WAIT' (expected whole seconds)" >&2; exit 2; }
    [[ -f "$THEME/Main.qml" && -f "$THEME/metadata.desktop" ]] \
        || { echo "render-sddm: '$THEME' is not an SDDM theme (Main.qml and metadata.desktop required)" >&2; exit 1; }
    for d in "${FONT_DIRS[@]}"; do
        [[ -d "$d" ]] || { echo "render-sddm: font directory '$d' not found" >&2; exit 1; }
    done
    for cmd in sddm-greeter-qt6 xvfb-run import unshare; do
        command -v "$cmd" >/dev/null 2>&1 || { echo "render-sddm: '$cmd' not found (see the header for packages)" >&2; exit 1; }
    done
    unshare -rm true 2>/dev/null \
        || { echo "render-sddm: user/mount namespaces unavailable — refusing to render with real user names" >&2; exit 1; }

    THEME="$(cd "$THEME" && pwd)"
    OUT_DIR="$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)" \
        || { echo "render-sddm: output directory of '$OUT' not found" >&2; exit 1; }
    OUT="$OUT_DIR/$(basename "$OUT")"

    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT

    # Atrapy danych systemu widziane przez greeter.
    printf 'root:x:0:0:root:/root:/bin/sh\narchenemy:x:1000:1000:archenemy:/nonexistent:/bin/sh\n' > "$WORK/passwd"
    printf 'archenemy\n' > "$WORK/hostname"
    # SessionModel (SDDM 0.21) czyta sesje Wayland tylko przy istniejącym
    # /dev/dri; jedna atrapa w jednym katalogu = jedna pozycja na liście.
    if [[ -e /dev/dri ]]; then SESSIONS="$WORK/share/wayland-sessions"; else SESSIONS="$WORK/share/xsessions"; fi
    mkdir -p "$SESSIONS"
    printf '[Desktop Entry]\nName=Hyprland\nExec=true\nType=Application\n' > "$SESSIONS/hyprland.desktop"

    # Fonty spoza systemu: własny fonts.conf = systemowy + podane katalogi.
    if (( ${#FONT_DIRS[@]} > 0 )); then
        {
            printf '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">\n<fontconfig>\n'
            printf '  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>\n'
            for d in "${FONT_DIRS[@]}"; do
                printf '  <dir>%s</dir>\n' "$(cd "$d" && pwd)"
            done
            printf '  <cachedir>%s</cachedir>\n</fontconfig>\n' "$WORK/fontcache"
        } > "$WORK/fonts.conf"
    fi

    unshare -rm -- bash "${BASH_SOURCE[0]}" --inside "$WORK" "$THEME" "$OUT" "$SIZE" "$WAIT"
    rc=$?
    if [[ $rc -eq 0 && -s "$OUT" ]]; then
        echo "render-sddm: $OUT"
        exit 0
    fi
    echo "render-sddm: render failed (code $rc)" >&2
    exit 1
fi

# ─── W PRZESTRZENI NAZW ───────────────────────────────────────────────────────
shift
WORK="$1"; THEME="$2"; OUT="$3"; SIZE="$4"; WAIT="$5"

mount --bind "$WORK/passwd" /etc/passwd || exit 1
[[ -f /etc/hostname ]] && { mount --bind "$WORK/hostname" /etc/hostname || exit 1; }
mount -t tmpfs tmpfs /usr/local/share || exit 1
cp -r "$WORK/share/." /usr/local/share/ || exit 1

[[ -f "$WORK/fonts.conf" ]] && export FONTCONFIG_FILE="$WORK/fonts.conf"
export HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export WORK THEME OUT WAIT

# Jedna powłoka pod xvfb-run: greeter w tle, zrzut, sprzątanie greetera.
# shellcheck disable=SC2016  # zmienne rozwija powłoka wewnętrzna (są wyeksportowane)
xvfb-run -a -s "-screen 0 ${SIZE}x24 -nolisten tcp" bash -c '
    sddm-greeter-qt6 --test-mode --theme "$THEME" 2> "$WORK/greeter.log" >/dev/null &
    greeter=$!
    sleep "$WAIT"
    if ! kill -0 "$greeter" 2>/dev/null; then
        echo "render-sddm: greeter exited before the screenshot" >&2
        cat "$WORK/greeter.log" >&2
        exit 1
    fi
    import -window root "$OUT"
    rc=$?
    kill "$greeter" 2>/dev/null
    wait "$greeter" 2>/dev/null
    exit $rc
'
rc=$?
# Ostrzeżenia motywu (błędy QML, brakujące pliki) — bez szumu sterownika.
grep -E 'qml|QML|\.qml|file://|Cannot|cannot|not found|No such' "$WORK/greeter.log" >&2 || true
exit $rc
