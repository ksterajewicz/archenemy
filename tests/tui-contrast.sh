#!/bin/bash
# =============================================
#   archenemy - tests/tui-contrast.sh
#   Kolory TUI Super+A (scripts/appbinds/lib/tui.sh) względem alacritty każdego
#   rice'a: akcent i kolory stanu muszą mieć kontrast WCAG co najmniej 4,5:1.
#
#   Powód powstania (2026-11-05): zwykłe ANSI blue na white-blue ma 2,6:1, więc
#   numery i ramki menu były ledwo czytelne na domyślnym rice.
#   Uruchom: bash tests/tui-contrast.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

mkdir -p "$T/a"
rows=""
for dir in "$REPO"/rices/*/; do
    rice="$(basename "$dir")"
    [[ -f "$dir/alacritty/alacritty.toml" ]] || continue
    echo "$rice" > "$T/a/.current_rice"
    code="$(ARCHENEMY_DIR="$T/a" bash -c 'source "$1/scripts/appbinds/lib/tui.sh"; tui_accent_code' _ "$REPO")"
    rows+="$rice $code"$'\n'
done

printf '%s' "$rows" | REPO="$REPO" python3 -I -c '
import os, sys, tomllib
NAMES = {91: "red", 92: "green", 93: "yellow", 94: "blue", 95: "magenta", 96: "cyan"}
def lum(h):
    h = h.strip().lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
def ratio(a, b):
    x, y = sorted((lum(a), lum(b)), reverse=True)
    return (x + 0.05) / (y + 0.05)
ok = bad = 0
for row in sys.stdin:
    rice, code = row.split()
    with open(f"{os.environ['"'"'REPO'"'"']}/rices/{rice}/alacritty/alacritty.toml", "rb") as f:
        col = tomllib.load(f)["colors"]
    bg = col["primary"]["background"]
    for c in sorted({91, 92, 93, int(code)}):
        r = ratio(col["bright"][NAMES[c]], bg)
        if r >= 4.5:
            ok += 1
            print(f"  ✓ {rice} {NAMES[c]} {r:.1f}:1")
        else:
            bad += 1
            print(f"  ✗ {rice} {NAMES[c]} {r:.1f}:1")
print()
print(f"Wynik: {ok} ✓ / {bad} ✗")
sys.exit(1 if bad else 0)
'
