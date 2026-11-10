#!/bin/bash
# =============================================
#   archenemy - tests/power-profile.sh
#   Profile zasilania na ASUS-ach: scripts/waybar/profile-get.sh, asusprofile.sh
#   i profile-switch.sh na atrapie asusctl o składni 6.5.0.
#
#   Powód powstania (2026-11-05): skrypty wołały `asusctl profile -n` i `-p`, a od
#   asusctl 6.3.8 są tylko podkomendy, więc klik i klawisz profilu nie działały.
#   Atrapa wiernie odrzuca stare flagi (argh: „Unrecognized argument”, kod 1).
#   Uruchom: bash tests/power-profile.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016,SC2034  # check() robi eval na cytowanym wyrażeniu
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

H="$T/home"; A="$H/archenemy"
mkdir -p "$A/data" "$A/scripts/waybar" "$T/bin" "$T/run"
cp "$REPO"/scripts/waybar/{profile-get,profile-switch,asusprofile,universalprofile}.sh "$A/scripts/waybar/"
echo asus > "$A/data/hardware.dat"
export ARCHENEMY_PP_SYSFS="$T/platform_profile" XDG_RUNTIME_DIR="$T/run"
echo balanced > "$ARCHENEMY_PP_SYSFS"

# Wyjście `profile get` wg asusctl/src/main.rs 6.5.0. MOCK_NOOP = kod 0 bez zmiany.
cat > "$T/bin/asusctl" <<MOCK
#!/bin/bash
[[ "\$1" == profile ]] || exit 1
case "\$2" in
    get)
        [[ -f "$T/unsupported" ]] && { echo "Profiles not supported by either this kernel or by the laptop."; exit 1; }
        printf 'Active profile: %s\n\nAC profile Performance\nBattery profile Quiet\n' "\$(sed 's/./\U&/' "$ARCHENEMY_PP_SYSFS")"
        ;;
    next)
        [[ -f "$T/noop" ]] && exit 0
        if [[ "\$(cat "$ARCHENEMY_PP_SYSFS")" == balanced ]]; then echo performance > "$ARCHENEMY_PP_SYSFS"; else echo balanced > "$ARCHENEMY_PP_SYSFS"; fi
        ;;
    *) echo "Unrecognized argument: \$2" >&2; exit 1 ;;
esac
MOCK
cat > "$T/bin/systemctl" <<MOCK
#!/bin/bash
[[ "\$1" == is-active && ! -f "$T/asusd-dead" ]]
MOCK
cat > "$T/bin/powerprofilesctl" <<MOCK
#!/bin/bash
[[ -f "$T/ppd" ]] || exit 1
if [[ "\$1" == get ]]; then cat "$T/ppd"; else echo "\${2:-}" > "$T/ppd"; fi
MOCK
printf '#!/bin/bash\nexit 0\n' > "$T/bin/pkill"
printf '#!/bin/bash\necho "$*" >> "%s/notified"\n' "$T" > "$T/bin/notify-send"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/sleep"
chmod +x "$T"/bin/*
PATH="$T/bin:$PATH"
export HOME="$H"

get() { bash "$A/scripts/waybar/profile-get.sh"; }
switch() { bash "$A/scripts/waybar/profile-switch.sh" >/dev/null 2>&1; }

echo "== odczyt"
check "aktywny profil, nie ostatnia linia wyjścia" '[[ "$(get)" == "Balanced" ]]'
: > "$T/unsupported"
check "brak wsparcia: sysfs, nie treść błędu"      '[[ "$(get)" == "balanced" ]]'
echo power-saver > "$T/ppd"
check "brak wsparcia: najpierw ppd"                '[[ "$(get)" == "power-saver" ]]'
rm -f "$T/unsupported" "$T/ppd"

echo "== przełączanie"
check "klik zmienia profil"                        'switch && [[ "$(cat "$ARCHENEMY_PP_SYSFS")" == "performance" ]]'
check "powiadomienie z nową wartością"             '[[ "$(tail -1 "$T/notified")" == *"performance"* ]]'
check "pasek pokazuje nową wartość"                '[[ "$(get)" == "Performance" ]]'

echo "== kod 0 bez zmiany"
: > "$T/noop"
check "nie melduje sukcesu"                        '! switch'
check "krytyczne powiadomienie"                    '[[ "$(tail -1 "$T/notified")" == *"nie zadziałało"* ]]'
rm -f "$T/noop"

echo "== martwy asusd"
: > "$T/asusd-dead"
echo balanced > "$ARCHENEMY_PP_SYSFS"; echo balanced > "$T/ppd"
check "przełącza przez ppd"                        'switch; [[ "$(cat "$ARCHENEMY_PP_SYSFS")" == "balanced" && "$(cat "$T/ppd")" != "balanced" ]]'
rm -f "$T/asusd-dead" "$T/ppd"

echo "== stara składnia nie wraca"
check "żadnego asusctl profile -n/-p w kodzie"     '! grep -rnE "asusctl profile -[np]\b" "$REPO/scripts" "$REPO/install" "$REPO/config" --include=*.sh --include=*.lua | grep -v "^[^:]*:[0-9]*:[[:space:]]*#"'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
((FAIL == 0))
