#!/usr/bin/env bash
# =============================================
#   archenemy - src/system-theme/tools/render-grub.sh
#   Podgląd motywu GRUB-a do pliku PNG — prawdziwy GRUB w maszynie QEMU,
#   bez dotykania /boot i bez restartu komputera.
#
#   Narzędzie deweloperskie (jak src/flux-wall/tools — NIE uruchamia go
#   install.sh). Kroki:
#     1. `grub-mkstandalone -O x86_64-efi` buduje jeden plik EFI z motywem
#        i przykładowym menu w środku (memdisk): trzy wpisy jak na świeżym
#        Archu — system, „Advanced options”, „UEFI Firmware Settings”;
#     2. QEMU + OVMF (UEFI) startuje go z katalogu udającego partycję EFI
#        (`file=fat:rw:`), ekran VGA w zadanej rozdzielczości;
#     3. po odczekaniu `screendump -f png` z monitora QEMU zapisuje PNG.
#   Fonty: każdy *.pf2 z katalogu motywu jest ładowany jawnie (`loadfont`)
#   — glob w grub.cfg wymaga modułu regexp, a prawdziwy grub-mkconfig też
#   ładuje fonty motywu po nazwach.
#
#   Użycie: render-grub.sh [-s SZERxWYS] [-w SEKUNDY] [-t SEKUNDY]
#                          <katalog motywu> <wynik.png>
#     -s  rozdzielczość ekranu (domyślnie 1920x1080)
#     -w  ile sekund czekać od startu QEMU do zrzutu (domyślnie 20 — tyle
#         potrzebuje emulacja bez KVM na jednym rdzeniu; z KVM wystarczy 6)
#     -t  odliczanie menu w sekundach (domyślnie 30, widać pasek postępu;
#         -1 = bez odliczania)
#     <katalog motywu> musi zawierać theme.txt. Katalog bez theme.txt da się
#     wymusić zmienną RENDER_GRUB_ALLOW_BROKEN=1 — do sprawdzenia, co GRUB
#     pokazuje przy brakującym albo uszkodzonym motywie.
#   Wymaga: grub (grub-mkstandalone + moduły x86_64-efi), qemu-system-x86,
#   edk2-ovmf, socat. Inne położenie OVMF: zmienne
#   OVMF_CODE i OVMF_VARS. Pamięć gościa 256 MB; przy mniej niż
#   RENDER_MIN_MEM_MB (domyślnie 500) wolnej pamięci gospodarza narzędzie
#   odmawia. Kod 0 = PNG zapisany.
# =============================================

set -uo pipefail

SIZE="1920x1080"
WAIT=20
MENU_TIMEOUT=30
OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"
MIN_MEM_MB="${RENDER_MIN_MEM_MB:-500}"

usage() {
    sed -n '/^#   Użycie:/,/^#   odmawia/p' "${BASH_SOURCE[0]}" | sed 's/^#   \{0,1\}//' >&2
    exit 2
}

while getopts ":s:w:t:" opt; do
    case "$opt" in
        s) SIZE="$OPTARG" ;;
        w) WAIT="$OPTARG" ;;
        t) MENU_TIMEOUT="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 2 ]] || usage
THEME="$1"; OUT="$2"

[[ "$SIZE" =~ ^([0-9]+)x([0-9]+)$ ]] || { echo "render-grub: bad size '$SIZE' (expected WIDTHxHEIGHT)" >&2; exit 2; }
XRES="${BASH_REMATCH[1]}"; YRES="${BASH_REMATCH[2]}"
[[ "$WAIT" =~ ^[0-9]+$ ]] || { echo "render-grub: bad wait '$WAIT' (expected whole seconds)" >&2; exit 2; }
[[ "$MENU_TIMEOUT" =~ ^(-1|[0-9]+)$ ]] || { echo "render-grub: bad timeout '$MENU_TIMEOUT'" >&2; exit 2; }
[[ "$MIN_MEM_MB" =~ ^[0-9]+$ ]] || MIN_MEM_MB=500
[[ -d "$THEME" ]] || { echo "render-grub: theme directory '$THEME' not found" >&2; exit 1; }
if [[ ! -f "$THEME/theme.txt" && "${RENDER_GRUB_ALLOW_BROKEN:-0}" != 1 ]]; then
    echo "render-grub: '$THEME' has no theme.txt" >&2
    exit 1
fi
for cmd in grub-mkstandalone qemu-system-x86_64 socat; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "render-grub: '$cmd' not found (see the header for packages)" >&2; exit 1; }
done
for f in "$OVMF_CODE" "$OVMF_VARS"; do
    [[ -r "$f" ]] || { echo "render-grub: UEFI firmware '$f' not found (set OVMF_CODE / OVMF_VARS)" >&2; exit 1; }
done

mem_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)"
if [[ "$mem_kb" =~ ^[0-9]+$ ]] && (( mem_kb / 1024 < MIN_MEM_MB )); then
    echo "render-grub: only $((mem_kb / 1024)) MB of memory available (need $MIN_MEM_MB) — not starting QEMU" >&2
    exit 1
fi

THEME="$(cd "$THEME" && pwd)"
OUT_DIR="$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)" \
    || { echo "render-grub: output directory of '$OUT' not found" >&2; exit 1; }
OUT="$OUT_DIR/$(basename "$OUT")"

WORK="$(mktemp -d)"
QEMU_PID=""
cleanup() {
    [[ -n "$QEMU_PID" ]] && kill "$QEMU_PID" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

# ─── PRZYKŁADOWE MENU ─────────────────────────────────────────────────────────
# ($root) rozwija GRUB, nie bash — stąd pojedyncze cudzysłowy.
# shellcheck disable=SC2016
{
    printf 'insmod all_video\ninsmod gfxterm\ninsmod gfxmenu\ninsmod png\ninsmod jpeg\ninsmod tga\n'
    printf 'set gfxmode=%s,auto\n' "$SIZE"
    printf 'loadfont ($root)/boot/grub/fonts/unicode.pf2\n'
    for f in "$THEME"/*.pf2; do
        [[ -f "$f" ]] || continue
        printf 'loadfont ($root)/boot/grub/themes/preview/%s\n' "$(basename "$f")"
    done
    printf 'terminal_output gfxterm\n'
    printf 'set theme=($root)/boot/grub/themes/preview/theme.txt\nexport theme\n'
    printf 'set timeout=%s\nset default=0\n' "$MENU_TIMEOUT"
    printf "menuentry 'Arch Linux' { true }\n"
    printf "submenu 'Advanced options for Arch Linux' { menuentry 'Arch Linux, with Linux linux' { true } }\n"
    printf "menuentry 'UEFI Firmware Settings' { true }\n"
} > "$WORK/grub.cfg"

mkdir -p "$WORK/esp/EFI/BOOT"
if ! grub-mkstandalone -O x86_64-efi -o "$WORK/esp/EFI/BOOT/BOOTX64.EFI" \
        --locales= --themes= --fonts=unicode \
        "boot/grub/grub.cfg=$WORK/grub.cfg" \
        "boot/grub/themes/preview=$THEME" 2> "$WORK/mkstandalone.log"; then
    echo "render-grub: grub-mkstandalone failed:" >&2
    cat "$WORK/mkstandalone.log" >&2
    exit 1
fi
cp "$OVMF_VARS" "$WORK/vars.fd" || exit 1

# ─── QEMU ─────────────────────────────────────────────────────────────────────
# KVM, gdy jest; inaczej emulacja (tcg). Bez sieci, bez okna.
qemu-system-x86_64 -machine q35 -accel kvm -accel tcg -m 256 -nodefaults -display none \
    -device "VGA,xres=$XRES,yres=$YRES" \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$WORK/vars.fd" \
    -drive "format=raw,file=fat:rw:$WORK/esp" \
    -net none -monitor "unix:$WORK/monitor.sock,server,nowait" \
    > "$WORK/qemu.log" 2>&1 &
QEMU_PID=$!

sleep "$WAIT"
if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    echo "render-grub: QEMU exited early:" >&2
    cat "$WORK/qemu.log" >&2
    QEMU_PID=""
    exit 1
fi
echo "screendump $WORK/shot.png -f png" | socat - "unix-connect:$WORK/monitor.sock" >/dev/null 2>&1
# Monitor odpowiada przed zapisaniem pliku — poczekaj na komplet danych.
for _ in $(seq 1 50); do
    [[ -s "$WORK/shot.png" ]] && break
    sleep 0.1
done
sleep 0.3
echo "quit" | socat - "unix-connect:$WORK/monitor.sock" >/dev/null 2>&1
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

if [[ ! -s "$WORK/shot.png" ]]; then
    echo "render-grub: no screenshot from QEMU" >&2
    exit 1
fi
if ! cp "$WORK/shot.png" "$OUT"; then
    echo "render-grub: could not write '$OUT'" >&2
    exit 1
fi
echo "render-grub: $OUT"
