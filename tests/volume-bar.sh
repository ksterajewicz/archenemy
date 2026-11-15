#!/bin/bash
# =============================================
#   archenemy - tests/volume-bar.sh
#   Moduł głośności waybara (scripts/waybar/volume-bar.sh) na atrapach
#   pactl i wpctl. Bez PipeWire, zapis tylko w mktemp.
#
#   Powód powstania (audyt 2026-11-05, A9): `pactl list sinks` drukuje
#   etykiety w języku użytkownika („Nazwa:”, „Aktywny port:”), a skrypt szukał
#   angielskich „Name:” i „Active Port:”. W polskim locale ikona słuchawek nie
#   pojawiała się nigdy. Atrapa tłumaczy etykiety jak gettext w glibc:
#   LANGUAGE wygrywa z LANG/LC_*, chyba że locale to C.
#   Uruchom: bash tests/volume-bar.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1
VB="$REPO/scripts/waybar/volume-bar.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

mkdir -p "$T/bin"
# Port aktywny domyślnego wyjścia w pliku $T/port. Drugie wyjście (HDMI) ma
# port słuchawkowy, żeby test złapał czytanie portu nie tego wyjścia.
cat > "$T/bin/pactl" <<MOCK
#!/bin/bash
loc="\${LC_ALL:-\${LC_MESSAGES:-\${LANG:-C}}}"
lang=C
case "\$loc" in C|C.*|POSIX) ;; *) lang="\${LANGUAGE:-\$loc}" ;; esac
case "\$1" in
    get-default-sink) echo alsa_output.pci.analog ;;
    list)
        if [[ "\$lang" == pl* ]]; then s="Odpływ"; n="Nazwa"; p="Aktywny port"
        else s="Sink"; n="Name"; p="Active Port"; fi
        printf '%s #50\n\t%s: alsa_output.pci.hdmi\n\t%s: hdmi-output-0-headphones\n\n' "\$s" "\$n" "\$p"
        printf '%s #61\n\t%s: alsa_output.pci.analog\n\t%s: %s\n' "\$s" "\$n" "\$p" "\$(cat "$T/port")"
        ;;
esac
exit 0
MOCK
printf '#!/bin/bash\necho "Volume: 0.60"\n' > "$T/bin/wpctl"
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"

# Uruchamia moduł w zadanym locale (LC_ALL z environment.sh zdjęty).
bar() { env -u LC_ALL LANG="$1" LANGUAGE="${2:-}" bash "$VB"; }
HP="󰋋"

echo "== słuchawki niezależnie od locale"
echo analog-output-headphones > "$T/port"
out="$(bar pl_PL.UTF-8 pl)"
check "polskie locale: ikona słuchawek"          '[[ "$out" == *"$HP"* ]]'
out="$(bar en_US.UTF-8 pl)"
check "LANGUAGE=pl przy angielskim LANG"         '[[ "$out" == *"$HP"* ]]'
out="$(bar en_US.UTF-8)"
check "angielskie locale: ikona słuchawek"       '[[ "$out" == *"$HP"* ]]'

echo "== głośnik"
echo analog-output-speaker > "$T/port"
out="$(bar pl_PL.UTF-8 pl)"
check "polskie locale: głośnik, nie słuchawki"   '[[ "$out" != *"$HP"* && "$out" == *"󰕾"* ]]'
check "JSON z procentem"                         '[[ "$out" == *"\"percentage\":60,"* && "$out" == *"\"class\":\"normal\""* ]]'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
((FAIL == 0))
