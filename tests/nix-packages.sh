#!/usr/bin/env bash
# =============================================
#   archenemy - tests/nix-packages.sh
#   nix/packages.nix (D10, NixOS EKSPERYMENTALNE) BEZ nix — parser tekstowy
#   tests/lib/nix_packages.py; `nix-instantiate --parse/--eval` i build
#   dopiero w D11/D12 (README „NixOS”). Sprawdza:
#     - plik jest aktualny względem packages/platform-map.tsv
#       (nix/generate-packages.sh --check) i generator jest deterministyczny;
#     - składnia (zbalansowane nawiasy, kształt { pkgs }: { core fonts build
#       optional }), tylko pkgs.<atrybut>, brak opcji NixOS/HM i „-”, brak
#       duplikatów;
#     - pokrycie wszystkich 66 atrybutów z inwentarza D10 (62 wiersze
#       nixos=ok po rozwinięciu base-devel/wayland/libpulse) i zgodność
#       z mapą: dokładnie atrybuty nixos=ok + jawne dodatki spoza mapy;
#     - przydział grup (core/fonts/build/optional) i to, że żadna ścieżka
#       opcji z wierszy system-managed nie trafiła do listy;
#     - generator odrzuca opcję jako atrybut, wiersz nixos=ok poza listami
#       i atrybut z niedozwolonymi znakami; parser łapie każdą mutację.
#   Zapisy tylko w $T (test_isolate, D7F R3). Bez sieci, bez roota, bez nix.
#   Uruchom: bash tests/nix-packages.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC2016  # check() robi eval
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/environment.sh
source "$REPO/tests/lib/environment.sh"
test_isolate "$REPO/tests/nix-packages.sh" "$@"   # D7F R3: zapisy poza $T wykrywalne
T="$(mktemp -d)" && [[ -n "$T" && -d "$T" && "$T" != / ]] || exit 1
trap 'rm -rf "${T:?}"' EXIT
test_environment_init "$T" || exit 1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

GEN="$REPO/nix/generate-packages.sh"
NIXF="$REPO/nix/packages.nix"
PY="$REPO/tests/lib/nix_packages.py"
EXTRAS="xkeyboard_config,zlib"

# Inwentarz D10 (C-D8-10/raport-D10.md i raport-D10-2.md): 66 atrybutów.
printf '%s\n' hyprpaper hyprpolkitagent waybar rofi alacritty fastfetch neovim mako thunar \
    cliphist wl-clipboard hyprshot libpulseaudio pulseaudio pavucontrol playerctl brightnessctl \
    swayosd libnotify socat networkmanager_dmenu pciutils gcc gnumake pkg-config wayland \
    wayland-scanner libGL python3 gtk3 git nerd-fonts.iosevka nerd-fonts.jetbrains-mono \
    nerd-fonts.symbols-only noto-fonts papirus-icon-theme brave veracrypt discord btop \
    signal-desktop keepassxc proton-vpn libreoffice qbittorrent vlc mpv mpd mpc ncmpcpp zsh \
    zsh-autosuggestions zsh-syntax-highlighting zsh-completions fd ripgrep zoxide hyprpicker \
    networkmanagerapplet mangohud gamescope bluetui megasync protonup-qt rustdesk vscodium \
    > "$T/expect"
check "inwentarz: 66 unikalnych atrybutów"      '[[ $(sort -u "$T/expect" | wc -l) -eq 66 ]]'

# group_of <plik> <atrybut> — grupa, w której stoi atrybut (pusto = nigdzie).
group_of() {
    awk -v a="$2" '
        /^  [a-z]+ = [[{]/ { g = $1; next }
        g != "" && ($1 == "pkgs." a || $3 == "pkgs." a ";") { print g; exit }' "$1"
}

echo "== plik aktualny względem mapy, generator deterministyczny"
check "nix/packages.nix istnieje"                '[[ -f "$NIXF" ]]'
check "generate-packages.sh --check → 0"         'bash "$GEN" --check'
check "dwa przebiegi --stdout identyczne"        'bash "$GEN" --stdout > "$T/a" && bash "$GEN" --stdout > "$T/b" && cmp -s "$T/a" "$T/b"'
check "nagłówek: przypięta rewizja i data"       'grep -q "nixpkgs d5cc6833999746cffdfe0598f7bc801a57b887a9 (2026-11-13)" "$NIXF"'
check "nagłówek: lista nie włącza usług"         'grep -q "does NOT enable Hyprland, the portal, PAM" "$NIXF"'
check "funkcja { pkgs }:"                        'grep -qx "{ pkgs }:" "$NIXF"'

if ! command -v python3 >/dev/null 2>&1; then
    echo "  – skip: brak python3 (parser tekstowy)"
else
    echo "== parser tekstowy (bez nix): składnia, atrybuty, pokrycie, zgodność z mapą"
    out="$(python3 "$PY" "$NIXF" --expect "$T/expect" --map "$REPO/packages/platform-map.tsv" --extra "$EXTRAS")"
    rc=$?
    while IFS= read -r l; do
        case "$l" in ok\ *) ok "${l#ok }" ;; fail\ *) fail "${l#fail }" ;; esac
    done <<< "$out"
    check "parser: kod 0"                        '[[ $rc -eq 0 ]]'

    echo "== parser łapie mutacje"
    mutate() {   # mutate <opis> <sed-skrypt>
        sed "$2" "$NIXF" > "$T/mut.nix"
        if python3 "$PY" "$T/mut.nix" --expect "$T/expect" --map "$REPO/packages/platform-map.tsv" --extra "$EXTRAS" > "$T/mut.out"; then
            fail "mutacja przeszła: $1"
        else
            ok "mutacja wykryta: $1 ($(grep -m1 '^fail' "$T/mut.out" | cut -c6-70))"
        fi
    }
    mutate "opcja programs.hyprland.enable"      's/^    pkgs\.waybar$/    pkgs.programs.hyprland.enable/'
    mutate "opcja services.* w optional"         's/^    "btop" = pkgs\.btop;$/    "services.btop" = pkgs.services.btop;/'
    mutate "duplikat"                            's/^    pkgs\.rofi$/    pkgs.rofi\n    pkgs.rofi/'
    mutate "brak atrybutu z inwentarza"          '/^    pkgs\.socat$/d'
    mutate "atrybut spoza mapy"                  's/^    pkgs\.rofi$/    pkgs.rofi\n    pkgs.firefox/'
    mutate "niezbalansowany nawias"              '0,/^  \];$/s/^  \];$/  ];]/'
    mutate "brak ] listy"                        '0,/^  \];$/s/^  \];$/  ;/'
    mutate "goły minus zamiast atrybutu"           's/^    pkgs\.mako$/    -/'
    mutate "element bez pkgs."                   's/^    pkgs\.mako$/    mako/'
    mutate "klucz optional ≠ atrybut"            's/^    "btop" = pkgs\.btop;$/    "btop" = pkgs.htop;/'
fi

echo "== grupy i wiersze system-managed"
check "core: hyprpaper, brave, python3, papirus" '[[ "$(group_of "$NIXF" hyprpaper)$(group_of "$NIXF" brave)$(group_of "$NIXF" python3)$(group_of "$NIXF" papirus-icon-theme)" == corecorecorecore ]]'
check "core: pulseaudio (pactl), libpulseaudio w build" '[[ "$(group_of "$NIXF" pulseaudio)/$(group_of "$NIXF" libpulseaudio)" == core/build ]]'
check "fonts: 3 Nerd Fonts + noto-fonts"         '[[ "$(group_of "$NIXF" nerd-fonts.iosevka)$(group_of "$NIXF" nerd-fonts.jetbrains-mono)$(group_of "$NIXF" nerd-fonts.symbols-only)$(group_of "$NIXF" noto-fonts)" == fontsfontsfontsfonts ]]'
check "build: gcc gnumake pkg-config wayland wayland-scanner libGL zlib" '
    r=""; for a in gcc gnumake pkg-config wayland wayland-scanner libGL zlib; do r+="$(group_of "$NIXF" "$a")"; done
    [[ "$r" == buildbuildbuildbuildbuildbuildbuild ]]'
check "optional: btop, mpd, zsh, discord, vscodium" '
    r=""; for a in btop mpd zsh discord vscodium; do r+="$(group_of "$NIXF" "$a")"; done
    [[ "$r" == optionaloptionaloptionaloptionaloptional ]]'
check "dodatek spoza mapy: xkeyboard_config w core" '[[ "$(group_of "$NIXF" xkeyboard_config)" == core ]]'
opts_in=""
while IFS=$'\t' read -r id _ _ _ _ attr _ _ status _; do
    [[ -z "$id" || "$id" == \#* || ";$status;" != *";nixos=system-managed;"* || "$attr" == - ]] && continue
    for a in $attr; do grep -qF "$a" "$NIXF" && opts_in+=" $id:$a"; done
done < "$REPO/packages/platform-map.tsv"
check "żadna opcja z wierszy system-managed w pliku" '[[ -z "$opts_in" ]] || { echo "    $opts_in"; false; }'
check "programs.hyprland/hyprlock, services.pipewire nieobecne" '! grep -qE "programs\.hypr|services\.pipewire|hardware\.|networking\.|boot\.|virtualisation\." "$NIXF"'

echo "== generator na kopii mapy: aktualizacja i odmowy"
CP="$T/repo"; mkdir -p "$CP/nix" "$CP/packages"
cp "$GEN" "$CP/nix/"; cp "$REPO/packages/platform-map.tsv" "$CP/packages/"; cp "$NIXF" "$CP/nix/"
check "kopia: --check → 0"                       'bash "$CP/nix/generate-packages.sh" --check'
sed -i 's/\tbtop\tcmd:btop\t/\tbtop htop\tcmd:btop\t/' "$CP/packages/platform-map.tsv"
check "nowy atrybut w mapie → --check = 1"       '! bash "$CP/nix/generate-packages.sh" --check 2>/dev/null'
check "regeneracja: htop w optional"             'bash "$CP/nix/generate-packages.sh" >/dev/null && [[ "$(group_of "$CP/nix/packages.nix" htop)" == optional ]] && bash "$CP/nix/generate-packages.sh" --check'
cp "$REPO/packages/platform-map.tsv" "$CP/packages/"
sed -i 's/\thyprpaper\tcmd:hyprpaper\t/\tservices.hyprpaper.enable\tcmd:hyprpaper\t/' "$CP/packages/platform-map.tsv"
bash "$CP/nix/generate-packages.sh" --stdout > /dev/null 2> "$T/err"; rc=$?
check "opcja przy nixos=ok → kod 2"              '[[ $rc -eq 2 ]] && grep -q "option in the package list" "$T/err"'
cp "$REPO/packages/platform-map.tsv" "$CP/packages/"
sed -i 's/^\(yay\tyay\taur\t-\t-\t\)-\(\tcmd:yay\t-\tfedora=unavailable;nixos=\)unavailable/\1yay\2ok/' "$CP/packages/platform-map.tsv"
bash "$CP/nix/generate-packages.sh" --stdout > /dev/null 2> "$T/err"; rc=$?
check "nixos=ok poza listami pakietów → kod 2"   '[[ $rc -eq 2 ]] && grep -q "outside a package list section" "$T/err"'
cp "$REPO/packages/platform-map.tsv" "$CP/packages/"
sed -i 's/\tbtop\tcmd:btop\t/\tbtop;rm\tcmd:btop\t/' "$CP/packages/platform-map.tsv"
bash "$CP/nix/generate-packages.sh" --stdout > /dev/null 2> "$T/err"; rc=$?
check "znaki spoza atrybutu → kod 2"             '[[ $rc -eq 2 ]] && grep -q "not a nixpkgs attribute" "$T/err"'

echo "== izolacja"
if escaped="$(test_escapes "$T")"; then ok "zero zapisów poza \$T w: $(test_isolation_dirs)"
elif [[ $? == 2 ]]; then echo "  – izolacja niedostępna (unshare/overlay)"
else fail "zapisy poza \$T: ${escaped//$'\n'/ }"; fi
echo
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ "$FAIL" -eq 0 ]]
