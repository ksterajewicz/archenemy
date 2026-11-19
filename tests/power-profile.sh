#!/usr/bin/env bash
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
mkdir -p "$A/scripts/lib"; cp "$REPO/scripts/lib/runtime-dir.sh" "$A/scripts/lib/"   # katalog sesji (S12)
echo asus > "$A/data/hardware.dat"
export ARCHENEMY_PP_SYSFS="$T/platform_profile" XDG_RUNTIME_DIR="$T/run"
echo balanced > "$ARCHENEMY_PP_SYSFS"

# Wyjście `profile get` wg asusctl/src/main.rs 6.5.0. MOCK_NOOP = kod 0 bez zmiany.
cat > "$T/bin/asusctl" <<MOCK
#!/usr/bin/env bash
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
#!/usr/bin/env bash
[[ "\$1" == is-active && ! -f "$T/asusd-dead" ]]
MOCK
# ppd: profile z pliku ppd-profiles (domyślnie trzy); `set` innego = błąd jak
# w demonie, bez zmiany. `list` w układzie powerprofilesctl (od ostatniego,
# aktywny z „*”, pod nagłówkiem wiersze sterowników); ppd-nolist = list pada.
cat > "$T/bin/powerprofilesctl" <<MOCK
#!/usr/bin/env bash
[[ -f "$T/ppd" ]] || exit 1
avail="power-saver balanced performance"
[[ -f "$T/ppd-profiles" ]] && avail="\$(cat "$T/ppd-profiles")"
case "\$1" in
    get) cat "$T/ppd" ;;
    list)
        [[ -f "$T/ppd-nolist" ]] && exit 1
        sep=""
        for p in \$(printf '%s\\n' \$avail | tac); do
            m=" "; [[ "\$p" == "\$(cat "$T/ppd")" ]] && m="*"
            printf '%s%s %s:\\n    CpuDriver:\\tamd_pstate\\n    PlatformDriver:\\tplaceholder\\n' "\$sep" "\$m" "\$p"
            sep=\$'\\n'
        done ;;
    set)
        echo "set \${2:-}" >> "$T/ppd-calls"
        [[ " \$avail " == *" \${2:-} "* ]] || { echo "Failed to activate profile \${2:-}: not available" >&2; exit 1; }
        echo "\${2:-}" > "$T/ppd" ;;
    *) exit 1 ;;
esac
MOCK
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/pkill"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/notified"\n' "$T" > "$T/bin/notify-send"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/sleep"
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

echo "== ppd bez profilu performance (A8)"
# Sprzęt bez sterownika platformy: ppd ma tylko power-saver i balanced. Dawniej
# z balanced klik zawsze próbował performance, więc profil nigdy się nie zmieniał.
echo universal > "$A/data/hardware.dat"; : > "$T/asusd-dead"
echo balanced > "$T/ppd"; echo "power-saver balanced" > "$T/ppd-profiles"; : > "$T/notified"; : > "$T/ppd-calls"
check "klik: balanced → power-saver"               'switch && [[ "$(cat "$T/ppd")" == power-saver ]]'
check "klik: power-saver → balanced"               'switch && [[ "$(cat "$T/ppd")" == balanced ]]'
check "bez krytycznego powiadomienia"              '! grep -q "nie zadziałało" "$T/notified" && [[ "$(tail -1 "$T/notified")" == *"balanced"* ]]'
check "cykl z powerprofilesctl list: bez próby performance" '! grep -qx "set performance" "$T/ppd-calls"'
: > "$T/ppd-nolist"
check "list nie działa: nieudany krok pominięty"   'switch && [[ "$(cat "$T/ppd")" == power-saver ]]'
rm -f "$T/ppd-nolist"
echo "== ppd z trzema profilami: cykl jak dawniej"
rm -f "$T/ppd-profiles"; echo balanced > "$T/ppd"
check "balanced → performance → power-saver"       'switch && [[ "$(cat "$T/ppd")" == performance ]] && switch && [[ "$(cat "$T/ppd")" == power-saver ]]'
echo "== jeden profil: uczciwy błąd, nie pętla"
echo balanced > "$T/ppd-profiles"; echo balanced > "$T/ppd"; : > "$T/notified"
check "nie melduje sukcesu"                        '! switch && [[ "$(cat "$T/ppd")" == balanced ]]'
check "krytyczne powiadomienie z przyczyną"        '[[ "$(tail -1 "$T/notified")" == *"nie zadziałało"* ]]'
rm -f "$T/ppd-profiles" "$T/ppd" "$T/asusd-dead"; echo asus > "$A/data/hardware.dat"

echo "== porada po nieudanym kliku per platforma (L6, przegląd D8–D10)"
# Arch (i brak biblioteki platformy) = dawna treść bajt w bajt; NixOS: opcje
# configuration.nix, bez systemctl i sudo — nawet w poradzie.
OLD_HINT="Przełączenie profilu nie zadziałało. Błąd: asusctl profile next: kod 0, profil w sysfs bez zmian. ASUS: uruchom demona (sudo systemctl restart asusd), a przy braku asusctl: bash ~/archenemy/install/asus-installation.sh. Inne: power-profiles-daemon (systemctl enable --now power-profiles-daemon)."
fail_click() { : > "$T/noop"; : > "$T/notified"; switch; rm -f "$T/noop"; tail -1 "$T/notified"; }
check "bez install/lib/pkg.sh: dawna porada bez zmian" '[[ "$(fail_click)" == "-u critical archenemy $OLD_HINT" ]]'
mkdir -p "$A/install/lib" "$A/packages"; cp "$REPO/install/lib/pkg.sh" "$A/install/lib/"; cp "$REPO/packages/platform-map.tsv" "$A/packages/"
printf 'ID=arch\n' > "$T/os-arch"; printf 'ID=nixos\n' > "$T/os-nixos"
check "Arch: dawna porada bajt w bajt" '[[ "$(ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os-arch" fail_click)" == "-u critical archenemy $OLD_HINT" ]]'
nix_hint="$(ARCHENEMY_TEST=1 ARCHENEMY_OS_RELEASE="$T/os-nixos" fail_click)"
check "NixOS: opcje services.asusd / services.power-profiles-daemon" '[[ "$nix_hint" == *"nie zadziałało"* && "$nix_hint" == *"services.asusd.enable = true;"* && "$nix_hint" == *"services.power-profiles-daemon.enable = true;"* ]]'
check "NixOS: bez systemctl i sudo w poradzie" '[[ "$nix_hint" != *systemctl* && "$nix_hint" != *sudo* && "$nix_hint" != *asus-installation.sh* ]]'
rm -rf "$A/install" "$A/packages"

echo "== stara składnia nie wraca"
check "żadnego asusctl profile -n/-p w kodzie"     '! grep -rnE "asusctl profile -[np]\b" "$REPO/scripts" "$REPO/install" "$REPO/config" --include=*.sh --include=*.lua | grep -v "^[^:]*:[0-9]*:[[:space:]]*#"'

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
((FAIL == 0))
