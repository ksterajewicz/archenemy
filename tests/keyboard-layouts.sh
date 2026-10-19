#!/bin/bash
# =============================================
#   archenemy - tests/keyboard-layouts.sh
#   Testy układów klawiatury (Super+A → [k], Super+Ctrl+1…4,
#   scripts/hypr/keyboard-layouts.sh) na atrapie HOME, atrapie hyprctl
#   i atrapie notify-send. Bez Hyprlanda, bez roota, bez zapisu poza mktemp.
#
#   Sprawdza: walidację listy (1–4 układy, znane kody XKB, bez duplikatów),
#   zapis .dat i keyboard-layouts.lua, reset, `show`, reload + potwierdzenie
#   odczytem `getoption input:kb_layout` (rozjazd = kod 2), `switch N` →
#   `switchxkblayout all N-1`, numer spoza listy → powiadomienie, bez
#   przełączenia; gotowe układy istnieją w evdev.lst; wygenerowany Lua
#   ustawia WYŁĄCZNIE input.kb_layout; rice'y parytetu mają require i bindy
#   Super+Ctrl+1…4 (beta nie); menu [k] w TUI — wybór 2 układów z listy
#   i zmiana kolejności — prowadzone z wejścia standardowego.
#   Uruchom: bash tests/keyboard-layouts.sh   (kod 0 = wszystko przeszło)
# =============================================

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KL="$REPO/scripts/hypr/keyboard-layouts.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { if [[ "$2" == 1 ]]; then PASS=$((PASS+1)); echo "OK   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 ${3:-}"; fi; }

export HOME="$T/home"
mkdir -p "$HOME/archenemy/config/hypr" "$T/bin"
DAT="$HOME/archenemy/data/keyboard-layouts.dat"
LUA="$HOME/archenemy/config/hypr/keyboard-layouts.lua"

# Atrapa evdev.lst (sekcja „! layout” jak w xkeyboard-config) — test nie
# zależy od pakietów maszyny; osobno sprawdzamy gotowe układy na prawdziwym pliku.
cat > "$T/evdev.lst" <<'EOF'
! model
  pc105           Generic 105-key PC
! layout
  us              English (US)
  pl              Polish
  de              German
  si              Slovenian
  ru              Russian
  ua              Ukrainian
  cz              Czech
! variant
  dvorak          us: English (Dvorak)
EOF
export ARCHENEMY_XKB_RULES="$T/evdev.lst"

# Atrapa hyprctl: reload „wczytuje” kb_layout z keyboard-layouts.lua,
# getoption oddaje go jak v0.56.2 („str: …”), switchxkblayout → log.
cat > "$T/bin/hyprctl" <<'EOF'
#!/bin/bash
case "$1" in
    reload) echo reload >> "$MOCK_LOG"
            v="pl,us"
            [[ -z "${MOCK_ZLY:-}" && -f "$HOME/archenemy/config/hypr/keyboard-layouts.lua" ]] && \
                v="$(sed -n 's/.*kb_layout = "\([^"]*\)".*/\1/p' "$HOME/archenemy/config/hypr/keyboard-layouts.lua")"
            echo "$v" > "$MOCK_STAN" ;;
    getoption) printf 'str: %s\nset: true\n' "$(cat "$MOCK_STAN" 2>/dev/null || echo pl,us)" ;;
    switchxkblayout) echo "switch $*" >> "$MOCK_LOG" ;;
esac
EOF
printf '#!/bin/bash\necho "notify $*" >> "$MOCK_LOG"\n' > "$T/bin/notify-send"
chmod +x "$T/bin/hyprctl" "$T/bin/notify-send"
export PATH="$T/bin:$PATH" MOCK_LOG="$T/log" MOCK_STAN="$T/stan"

# --- bez Hyprlanda ----------------------------------------------------------
unset HYPRLAND_INSTANCE_SIGNATURE
ok "show bez pliku = pl,us" "$([[ "$(bash "$KL" show)" == pl,us ]] && echo 1)"
out="$(bash "$KL" set "PL, de")"; rc=$?
ok "set 'PL, de' → pl,de (kod 0, bez reloadu)" "$([[ $rc == 0 && "$(cat "$DAT")" == pl,de && ! -f "$T/log" ]] && echo 1)" "$out"
for zle in "" "pl,pl" "pl,xx" "pl,us,de,si,ru" "p1" "pl;us" ",,"; do
    bash "$KL" set "$zle" >/dev/null 2>&1; rc=$?
    ok "zła lista '$zle' → kod 1, .dat bez zmian" "$([[ $rc == 1 && "$(cat "$DAT")" == pl,de ]] && echo 1)"
done
bash "$KL" set "si,ru,ua,cz" >/dev/null; ok "4 układy przyjęte" "$([[ "$(cat "$DAT")" == si,ru,ua,cz ]] && echo 1)"
ok "name si = Slovenian (z evdev.lst)" "$([[ "$(bash "$KL" name si)" == Slovenian ]] && echo 1)"

# --- z Hyprlandem -----------------------------------------------------------
export HYPRLAND_INSTANCE_SIGNATURE=atrapa
rm -f "$T/log"
out="$(bash "$KL" set pl,ru)"; rc=$?
ok "Hyprland: kod 0 i ✓" "$([[ $rc == 0 && "$out" == *"✓ keyboard layouts: pl,ru"* ]] && echo 1)" "$out"
ok "Hyprland: jeden reload" "$([[ "$(grep -c reload "$T/log")" == 1 ]] && echo 1)"
ok "Lua: dokładnie kb_layout = \"pl,ru\"" "$(grep -qx 'hl.config({ input = { kb_layout = "pl,ru" } })' "$LUA" && echo 1)"
out="$(MOCK_ZLY=1 bash "$KL" set pl,de 2>&1)"; rc=$?
ok "rozjazd odczytu → kod 2" "$([[ $rc == 2 && "$out" == *configerrors* ]] && echo 1)" "$rc $out"
bash "$KL" set pl,de,ru >/dev/null
rm -f "$T/log"
bash "$KL" switch 3; rc=$?
ok "switch 3 → switchxkblayout all 2" "$([[ $rc == 0 && "$(cat "$T/log")" == "switch switchxkblayout all 2" ]] && echo 1)" "$(cat "$T/log" 2>/dev/null)"
rm -f "$T/log"
bash "$KL" switch 4; rc=$?
ok "switch 4 przy 3 układach → kod 1, powiadomienie, bez przełączenia" \
   "$([[ $rc == 1 && "$(cat "$T/log")" == notify* && "$(cat "$T/log")" != *switchxkb* ]] && echo 1)" "$(cat "$T/log" 2>/dev/null)"
bash "$KL" reset >/dev/null; ok "reset → pl,us" "$([[ "$(cat "$DAT")" == pl,us ]] && echo 1)"
ls "$HOME/archenemy/config/hypr/"*.?????? >/dev/null 2>&1
ok "brak plików tymczasowych mktemp" "$([[ $? != 0 ]] && echo 1)"

# --- wygenerowany Lua: tylko input.kb_layout --------------------------------
if command -v lua5.4 >/dev/null 2>&1; then
    bash "$KL" set de,si >/dev/null
    cat > "$T/harness.lua" <<'EOF'
local klucze = {}
hl = { config = function(t)
    local function walk(p, x) for k, v in pairs(x) do
        if type(v) == "table" then walk(p .. k .. ".", v) else klucze[#klucze + 1] = p .. k .. "=" .. tostring(v) end end end
    walk("", t) end }
dofile(arg[1]); print(table.concat(klucze, ","))
EOF
    wynik="$(lua5.4 "$T/harness.lua" "$LUA" 2>&1)"
    ok "Lua: jedyny klucz input.kb_layout=de,si" "$([[ "$wynik" == "input.kb_layout=de,si" ]] && echo 1)" "$wynik"
fi

# --- gotowe układy w prawdziwym evdev.lst -----------------------------------
if [[ -r /usr/share/X11/xkb/rules/evdev.lst ]]; then
    brak=""
    while IFS=$'\t' read -r c _; do
        ARCHENEMY_XKB_RULES=/usr/share/X11/xkb/rules/evdev.lst bash "$KL" name "$c" >/dev/null
        awk -v k="$c" '/^! /{s=$2;next} s=="layout" && $1==k {f=1} END{exit !f}' /usr/share/X11/xkb/rules/evdev.lst || brak+=" $c"
    done < <(bash "$KL" presets)
    ok "każdy gotowy układ istnieje w evdev.lst" "$([[ -z "$brak" ]] && echo 1)" "brak:$brak"
fi

# --- rice'y: require + bindy Super+Ctrl+1…4, beta bez ------------------------
for r in white-blue tron asia-n-rice dither-flux crt; do
    f="$REPO/rices/$r/hypr/hyprland.lua"
    n_in="$(grep -n 'kb_layout = "pl,us"' "$f" | head -1 | cut -d: -f1)"
    n_req="$(grep -n 'require_optional(HOME .. "/archenemy/config/hypr/keyboard-layouts.lua")' "$f" | cut -d: -f1)"
    ok "$r: keyboard-layouts.lua wczytywany raz, po bloku input" "$([[ -n "$n_req" && "$n_req" != *$'\n'* && "$n_req" -gt "$n_in" ]] && echo 1)"
    nb=0
    for n in 1 2 3 4; do
        grep -qxF "hl.bind(mainMod .. \" + CTRL + $n\", hl.dsp.exec_cmd(\"~/archenemy/scripts/hypr/keyboard-layouts.sh switch $n\"))" "$f" && nb=$((nb+1))
    done
    ok "$r: bindy Super+Ctrl+1…4 (4)" "$([[ $nb == 4 ]] && echo 1)" "$nb"
    ok "$r: Super+K dalej = next" "$(grep -q 'switchxkblayout all next' "$f" && echo 1)"
done
f="$REPO/rices/white-blue_beta/hypr/hyprland.lua"
ok "white-blue_beta: bez keyboard-layouts.lua i Super+Ctrl+N" "$(grep -q 'keyboard-layouts' "$f" || echo 1)"
ok "keyboard-layouts.lua w .gitignore" "$(grep -qx '/config/hypr/keyboard-layouts.lua' "$REPO/.gitignore" && echo 1)"

# --- TUI [k]: wybór 2 układów z listy, potem zmiana kolejności --------------
mkdir -p "$HOME/archenemy/scripts"
ln -sfn "$REPO/scripts/hypr" "$HOME/archenemy/scripts/hypr"
unset HYPRLAND_INSTANCE_SIGNATURE
bash "$KL" reset >/dev/null
# Kolejność gotowych układów: 1 pl, 4 de (patrz PRESETS w skrypcie).
nr_de="$(bash "$KL" presets | awk -F'\t' '$1=="de"{print NR}')"
printf 'k12%s\n%s\n\nq' 1 "$nr_de" | bash "$REPO/scripts/appbinds/appbinds.sh" >/dev/null 2>&1
ok "TUI [k] → 1 → 2 układy: pl, de" "$([[ "$(cat "$DAT")" == pl,de ]] && echo 1)" "$(cat "$DAT")"
printf 'k22 1\n\nq' | bash "$REPO/scripts/appbinds/appbinds.sh" >/dev/null 2>&1
ok "TUI [k] → 2 → kolejność '2 1' → de,pl" "$([[ "$(cat "$DAT")" == de,pl ]] && echo 1)" "$(cat "$DAT")"
printf 'k22 2\n\nq' | bash "$REPO/scripts/appbinds/appbinds.sh" >/dev/null 2>&1
ok "TUI [k] → 2 → zła kolejność '2 2' nic nie zmienia" "$([[ "$(cat "$DAT")" == de,pl ]] && echo 1)"
printf 'k3\nq' | bash "$REPO/scripts/appbinds/appbinds.sh" >/dev/null 2>&1
ok "TUI [k] → 3 → reset pl,us" "$([[ "$(cat "$DAT")" == pl,us ]] && echo 1)"

echo ""
echo "WYNIK keyboard-layouts: $PASS ok, $FAIL fail"
[[ $FAIL == 0 ]]
