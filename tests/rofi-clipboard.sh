#!/bin/bash
# =============================================
#   archenemy - tests/rofi-clipboard.sh
#   Atrapy bez Wayland; wszystkie zapisy wyłącznie w mktemp.
# =============================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CACHE_HOME="$T/cache" TMPDIR="$T" TEST_DIR="$T"
mkdir -p "$HOME" "$T/bin"
export PATH="$T/bin:$PATH"
GATE="$REPO/scripts/rofi/rofi_clipboard.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else fail "$label"; fi; }
cat > "$T/bin/cliphist" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_DIR/commands"
case "$1" in
    list) cat "$TEST_DIR/history"; exit "${LIST_RC:-0}" ;;
    decode) [[ "${DECODE_FAIL:-0}" == 0 ]] || exit 1; printf 'full entry %s\nsecond line\n' "$2" ;;
    delete) cat > "$TEST_DIR/deleted" ;;
    wipe) : > "$TEST_DIR/wiped" ;;
esac
MOCK
cat > "$T/bin/wl-copy" <<'MOCK'
#!/bin/bash
cat > "$TEST_DIR/copied"
MOCK
cat > "$T/bin/rofi" <<'MOCK'
#!/usr/bin/python3
import os, pathlib, sys
p=pathlib.Path(os.environ['TEST_DIR'])
args=sys.argv[1:]
with (p/'rofi-args').open('a') as f: f.write(repr(args)+'\n')
if '-e' in args:
    (p/'message').write_text(args[args.index('-e')+1]); sys.exit(0)
n=len(list(p.glob('menu-*')))
(p/f'menu-{n}').write_bytes(sys.stdin.buffer.read())
answers=(p/'answers').read_text().splitlines()
a=answers.pop(0) if answers else 'ESC'
(p/'answers').write_text('\n'.join(answers)+'\n' if answers else '')
if a=='ESC': sys.exit(1)
print(a)
MOCK
# Miniatury są atrapami: sprawdzamy protokół i sprzątanie, nie renderowanie PNG.
cat > "$T/bin/glycin-thumbnailer" <<'MOCK'
#!/bin/bash
while (($#)); do
    if [[ "$1" == --output ]]; then printf 'thumbnail' > "$2"; break; fi
    shift
done
MOCK
chmod +x "$T/bin/"*
reset_case() {
    rm -f "$T/"{commands,copied,deleted,wiped,message,rofi-args,menu-*}
    printf '92\tfirst\tline\r\n11\tsecond entry\n' > "$T/history"
    printf '%s\n' "$@" > "$T/answers"
}
run() { "$GATE" > "$T/stdout" 2> "$T/stderr"; RC=$?; }
reset_case 1; run
check 'selected index decodes the matching ID' grep -qx 'decode 11' "$T/commands"
printf 'full entry 11\nsecond line\n' > "$T/expected"
check 'full multiline content reaches wl-copy' cmp -s "$T/expected" "$T/copied"
check 'one line per entry, no control characters' python3 -c 'import pathlib,sys; b=pathlib.Path(sys.argv[1]).read_bytes(); assert b == b"first line \nsecond entry\nDelete entry\nClear history\n"' "$T/menu-0"
check 'text-only menu creates no cache' test ! -e "$XDG_CACHE_HOME"
check 'text-only menu has no icon override' bash -c '! grep -q element-icon "$1"' _ "$T/rofi-args"
reset_case ESC
printf '92\t%s\n' "$(printf '%160s' x)" > "$T/history"
run
check 'long preview is limited to 120 characters' python3 -c 'import pathlib,sys; assert len(pathlib.Path(sys.argv[1]).read_text().splitlines()[0]) == 120' "$T/menu-0"
reset_case ESC; run
check 'Esc performs no clipboard operation' test "$(cat "$T/commands")" = list
reset_case 999; run
check 'invalid index performs no clipboard operation' test "$(cat "$T/commands")" = list
reset_case 2 1; run
check 'Delete entry passes ID through stdin' test "$(cat "$T/deleted")" = 11
check 'delete does not decode or copy text' test ! -e "$T/copied"
reset_case 3 0; run
check 'clear defaults to No' test ! -e "$T/wiped"
reset_case 3 ESC; run
check 'Esc cancels clear confirmation' test ! -e "$T/wiped"
reset_case 3 1; run
check 'confirmed clear invokes wipe' test -f "$T/wiped"
reset_case; : > "$T/history"; run
check 'empty history shows English message' test "$(cat "$T/message")" = 'Clipboard history is empty'
check 'empty history opens no choice menu' test ! -e "$T/menu-0"
reset_case; printf 'opening db: please store something first' > "$T/history"
LIST_RC=1 run
check 'missing database is an empty history' test "$RC" = 0
reset_case; printf 'permission denied' > "$T/history"; LIST_RC=1 run
check 'database errors are reported as errors' test "$RC" = 1
reset_case 0; DECODE_FAIL=1 run
check 'decode failure is reported' test "$RC" = 1
reset_case ESC; printf '92\t[[ binary data 1 KiB png 32x32 ]]\n' > "$T/history"; run
check 'image entry carries rofi icon metadata' python3 -c 'import pathlib,sys; b=pathlib.Path(sys.argv[1]).read_bytes(); assert b"\0icon\x1f" in b; assert b"thumbnail" in b or b"archenemy-clipboard." in b' "$T/menu-0"
check 'image previews decode only numeric ID' grep -qx 'decode 92' "$T/commands"
check 'icon size override only with images' grep -q 'element-icon' "$T/rofi-args"
check 'private image cache is removed on Esc' test -z "$(find "$XDG_CACHE_HOME" -mindepth 1 -print -quit)"
# Izolowany PATH pozwala sprawdzić braki także na maszynie z prawdziwym cliphist.
mkdir "$T/limited"
ln -s "$(command -v dirname)" "$T/limited/dirname"
for missing in cliphist wl-copy rofi; do
    for binary in cliphist wl-copy rofi; do
        rm -f "$T/limited/$binary"
        [[ "$binary" == "$missing" ]] || ln -s "$T/bin/$binary" "$T/limited/$binary"
    done
    reset_case
    PATH="$T/limited" /bin/bash "$GATE" > "$T/stdout" 2> "$T/stderr"; RC=$?
    case "$missing" in cliphist) package=cliphist;; wl-copy) package=wl-clipboard;; rofi) package=rofi-wayland;; esac
    check "missing $missing reports package $package" grep -q "Install package: $package" "$T/stderr"
done
for rice in white-blue tron asia-n-rice dither-flux crt; do
    check "Super+C bind in $rice" grep -Fq 'hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("~/archenemy/scripts/rofi/rofi_clipboard.sh"))' "$REPO/rices/$rice/hypr/hyprland.lua"
done
if grep -q rofi_clipboard "$REPO/rices/white-blue_beta/hypr/hyprland.lua"; then
    fail 'frozen beta has no new bind'
else
    ok 'frozen beta has no new bind'
fi
echo "Result: $PASS passed / $FAIL failed"
[[ "$FAIL" == 0 ]]
