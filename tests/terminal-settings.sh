#!/bin/bash
# Testy przełącznika copy on select i nawigacji jego ekranu Super+A.
# shellcheck disable=SC2016,SC2034  # check() ewaluje asercje i używa ich lokalnych zmiennych
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

CONFIG="$T/alacritty.toml"
cat > "$CONFIG" <<'CONF'
[window]
opacity = 0.8
[selection]
save_to_clipboard = true # keep this comment
[font]
size = 12
CONF
S="$REPO/scripts/appbinds/terminal-settings.sh"
export ALACRITTY_CONFIG="$CONFIG"
cp "$CONFIG" "$T/original"
check "reads initial on state" '[[ "$(bash "$S" summary)" == on ]]'
bash "$S" off >/dev/null
check "switches on to off" '[[ "$(bash "$S" show)" == off ]]'
check "changes only setting value" 'diff -u <(sed "s/save_to_clipboard = true/save_to_clipboard = false/" "$T/original") "$CONFIG" >/dev/null'
check "creates first-change backup" 'cmp -s "$T/original" "$CONFIG.bak"'
before="$(sha256sum "$CONFIG")"
bash "$S" off >/dev/null
check "same value is idempotent" '[[ "$(sha256sum "$CONFIG")" == "$before" ]]'
bash "$S" on >/dev/null
check "switches off to on" '[[ "$(bash "$S" show)" == on ]]'
check "does not replace original backup" 'cmp -s "$T/original" "$CONFIG.bak"'

mkdir -p "$T/home/archenemy/scripts" "$T/home/.config/alacritty"
cp -R "$REPO/scripts/appbinds" "$T/home/archenemy/scripts/"
cp "$T/original" "$T/home/.config/alacritty/alacritty.toml"
HOME="$T/home" ALACRITTY_CONFIG="$T/home/.config/alacritty/alacritty.toml" \
    bash -c 'printf "\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\033[B\n\nq" | timeout 8 bash "$1/scripts/appbinds/appbinds.sh"' _ "$T/home/archenemy" >/dev/null 2>&1
check "main menu arrows open terminal settings and Enter toggles off" '[[ "$(ALACRITTY_CONFIG="$T/home/.config/alacritty/alacritty.toml" bash "$S" show)" == off ]]'

rm "$CONFIG"
out="$(bash "$S" off)"
check "missing config reports issue without failing" '[[ "$out" == *"config not found"* ]]'
cat > "$CONFIG" <<'CONF'
[selection]
semantic_escape_chars = ",;:"
CONF
out="$(bash "$S" off)"
check "missing setting line reports issue without failing" '[[ "$out" == *"line not found"* ]]'

echo ""
echo "Result: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
