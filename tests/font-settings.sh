#!/bin/bash
# Testy wyboru fontu (Super+A → [f], scripts/appbinds/lib/fonts.sh): zapis tylko
# poza repo, reset i cofnięcie, odrzucanie niebezpiecznych nazw, rice bez wyboru,
# import w alacritty, -theme-str w rofi, ekran TUI. Fałszywy HOME i fc-list.
# shellcheck disable=SC2016,SC2034  # check() ewaluje asercje i używa ich lokalnych zmiennych
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

export HOME="$T/home"
A="$HOME/archenemy"
mkdir -p "$A" "$T/bin"
ln -s "$REPO/scripts" "$A/scripts"
ln -s "$REPO/rices" "$A/rices"
echo tron > "$A/.current_rice"
unset ARCHENEMY_DIR ARCHENEMY_FONT_DIR
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache" XDG_RUNTIME_DIR="$T/runtime"
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
mkdir -p "$XDG_RUNTIME_DIR"
FD="$HOME/.config/archenemy/fonts"
S="$A/scripts/appbinds/font-settings.sh"

# fc-list: lista rodzin albo zapytanie o glif Nerd Font (charset=f303).
cat > "$T/bin/fc-list" <<'MOCK'
#!/bin/bash
if [[ "${1:-}" == *":charset=f303" ]]; then
    [[ "$1" == JetBrainsMono* ]] && echo "JetBrainsMono Nerd Font"
    exit 0
fi
printf '%s\n' \
    "JetBrainsMono Nerd Font,JetBrainsMono NF:spacing=100" \
    "JetBrainsMono Nerd Font:spacing=100" \
    "Iosevka Term:spacing=100" \
    "Fira Code-Retina:spacing=100" \
    "DejaVu Sans" \
    'Evil"Font:spacing=100' \
    'Bad\,Font:spacing=100' \
    $'Ctl\eFont:spacing=100' \
    'Price$Font:spacing=100'
MOCK
cat > "$T/bin/rofi" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@" > "$ROFI_ARGS"
MOCK
chmod +x "$T/bin/fc-list" "$T/bin/rofi"
export PATH="$T/bin:$PATH" ROFI_ARGS="$T/rofi-args"
repo_state() { git -C "$REPO" status --porcelain --untracked-files=all; }
before_repo="$(repo_state)"

echo "== rice bez wyboru"
check "summary: rice default" '[[ "$(bash "$S" summary)" == "rice default" ]]'
check "current: font rice'a z rozmiarem" '[[ "$(bash "$S" current)" == "JetBrainsMono Nerd Font (archenemy choice; unverified: "* ]]'
check "brak katalogu stanu przed wyborem" '[[ ! -e "$FD" ]]'
bash "$REPO/scripts/rofi/rofi_drun.sh"
check "rofi drun bez -theme-str" '! grep -qx -- "-theme-str" "$ROFI_ARGS"'

echo "== lista fontów"
mono="$(bash "$S" list)"
all="$(bash "$S" list --all)"
check "mono: trzy rodziny, posortowane, bez duplikatów" '[[ "$mono" == $'"'"'Fira Code-Retina\nIosevka Term\nJetBrainsMono Nerd Font'"'"' ]]'
check "--all dodaje proporcjonalne" '[[ "$all" == *"DejaVu Sans"* && "$mono" != *"DejaVu"* ]]'
check "odrzuca cudzysłów, backslash, sterujące i \$" '[[ "$all" != *Evil* && "$all" != *Bad* && "$all" != *Ctl* && "$all" != *Price* ]]'

echo "== zapis"
out="$(bash "$S" set "Iosevka Term")"; rc=$?
check "set: kod 0" '(( rc == 0 ))'
check "set: komunikat po angielsku" '[[ "$out" == *"Font: Iosevka Term."* && "$out" == *"outside the repository"* ]]'
check "family zapisane" '[[ "$(<"$FD/family")" == "Iosevka Term" ]]'
check "alacritty.toml z rodziną i poprawnym TOML" 'python3 -c "import tomllib,sys; d=tomllib.load(open(sys.argv[1],\"rb\")); sys.exit(d[\"font\"][\"normal\"][\"family\"]!=\"Iosevka Term\")" "$FD/alacritty.toml"'
check "kopia poprzedniej wartości (pusta = rice)" '[[ -f "$FD/family.prev" && ! -s "$FD/family.prev" ]]'
check "brak plików tymczasowych, prawa 644" '[[ -z "$(find "$FD" -name "*.??????")" && "$(stat -c %a "$FD/family")" == 644 ]]'
check "current: wybrany font" '[[ "$(bash "$S" current)" == "Iosevka Term (archenemy choice; unverified: "* ]]'
check "summary: wybrany font" '[[ "$(bash "$S" summary)" == "Iosevka Term" ]]'
bash "$REPO/scripts/rofi/rofi_drun.sh"
check "rofi drun: -theme-str z fontem i rozmiarem rice'a" 'grep -qF "entry { font: \"Iosevka Term 11\"; }" "$ROFI_ARGS"'
check "repozytorium bez zmian" '[[ "$(repo_state)" == "$before_repo" ]]'
check "fałszywe repo bez nowych plików" '[[ "$(find "$A" -mindepth 1 -maxdepth 1 | sort | tr "\n" " ")" == "$A/.current_rice $A/rices $A/scripts " ]]'

echo "== odrzucone nazwy"
snap="$(cat "$FD"/family "$FD"/alacritty.toml)"
bash "$S" set "Nope Mono" >/dev/null; rc=$?
check "niezainstalowany: kod 3, bez zmian" '(( rc == 3 )) && [[ "$(cat "$FD"/family "$FD"/alacritty.toml)" == "$snap" ]]'
bash "$S" set 'Evil"Font' >/dev/null; rc=$?
check "cudzysłów: kod 2" '(( rc == 2 ))'
bash "$S" set $'Ctl\eFont' >/dev/null; rc=$?
check "znak sterujący: kod 2" '(( rc == 2 ))'
bash "$S" set $'Two\nLines' >/dev/null; rc=$?
check "nowa linia: kod 2, stan bez zmian" '(( rc == 2 )) && [[ "$(cat "$FD"/family "$FD"/alacritty.toml)" == "$snap" ]]'

echo "== cofnięcie i reset"
bash "$S" set "Fira Code-Retina" >/dev/null
check "poprzednia wartość zachowana" '[[ "$(<"$FD/family.prev")" == "Iosevka Term" ]]'
check "rodzina z myślnikiem zapisana" '[[ "$(<"$FD/family")" == "Fira Code-Retina" ]]'
bash "$S" undo >/dev/null
check "undo przywraca poprzedni font" '[[ "$(<"$FD/family")" == "Iosevka Term" ]]'
bash "$S" reset >/dev/null; rc=$?
check "reset usuwa wybór i plik alacritty" '(( rc == 0 )) && [[ ! -e "$FD/family" && ! -e "$FD/alacritty.toml" ]]'
check "reset: z powrotem font rice'a" '[[ "$(bash "$S" summary)" == "rice default" && "$(bash "$S" current)" == "JetBrainsMono Nerd Font (archenemy choice; unverified: "* ]]'
bash "$S" undo >/dev/null
check "undo po resecie wraca do wyboru" '[[ "$(<"$FD/family")" == "Iosevka Term" ]]'
printf 'Bad\033[31mName\n' > "$FD/family"
check "uszkodzony plik stanu = font rice'a" '[[ "$(bash "$S" current)" == "JetBrainsMono Nerd Font (archenemy choice; unverified: "* ]]'
bash "$S" set "Iosevka Term" >/dev/null

echo "== white-blue_beta (zamrożony)"
echo white-blue_beta > "$A/.current_rice"
check "beta: font własny, nie wybór" '[[ "$(bash "$S" current)" == "JetBrainsMono Nerd Font (archenemy choice; unverified: "* ]]'
check "beta: summary mówi, że nie działa" '[[ "$(bash "$S" summary)" == "Iosevka Term (not in this rice)" ]]'
bash "$REPO/scripts/rofi/rofi_drun.sh"
check "beta: rofi bez -theme-str" '! grep -qx -- "-theme-str" "$ROFI_ARGS"'
echo tron > "$A/.current_rice"

echo "== katalog stanu wskazujący repo"
mkdir -p "$T/h2/archenemy/data" "$T/h2/.config"
ln -s "$REPO/scripts" "$T/h2/archenemy/scripts"; ln -s "$REPO/rices" "$T/h2/archenemy/rices"
ln -s "$T/h2/archenemy/data" "$T/h2/.config/archenemy"
out="$(HOME="$T/h2" bash "$T/h2/archenemy/scripts/appbinds/font-settings.sh" set "Iosevka Term")"; rc=$?
check "odmowa: kod 4, nic w repo" '(( rc == 4 )) && [[ ! -e "$T/h2/archenemy/data/fonts" && "$out" == *"points into the repository"* ]]'

echo "== ochrona każdego celu"
for target in alacritty.toml family family.prev .lock; do
    for kind in directory symlink-repo symlink-outside dangling file-link; do
        attack="$T/attack-$target-$kind"
        mkdir -p "$attack" "$A/foreign-dir" "$T/foreign-dir"
        echo keep > "$A/foreign-dir/keep"; echo keep > "$T/foreign-dir/keep"
        case "$kind" in
            directory) mkdir "$attack/$target"; echo keep > "$attack/$target/keep" ;;
            symlink-repo) ln -s "$A/foreign-dir" "$attack/$target" ;;
            symlink-outside) ln -s "$T/foreign-dir" "$attack/$target" ;;
            dangling) ln -s "$T/missing" "$attack/$target" ;;
            file-link) ln -s "$T/foreign-dir/keep" "$attack/$target" ;;
        esac
        snapshot="$(find "$attack" -printf '%P %y %l\n'; cat "$A/foreign-dir/keep" "$T/foreign-dir/keep")"
        ARCHENEMY_FONT_DIR="$attack" bash "$S" set "Iosevka Term" >/dev/null; rc=$?
        check "$target / $kind: odmowa bez zmian" '(( rc != 0 )) && [[ "$(find "$attack" -printf "%P %y %l\n"; cat "$A/foreign-dir/keep" "$T/foreign-dir/keep")" == "$snapshot" ]]'
    done
done
rm -r "$A/foreign-dir"

# Atrapy psują pojedynczą operację; rollback nie zależy od mv/ln.
for tool in mv ln chmod; do
    real="$(command -v "$tool")"
    cat > "$T/bin/$tool" <<MOCK
#!/bin/bash
if [[ \${FONT_FAIL_TOOL:-} == $tool ]]; then
    count=0
    [[ -f \$FONT_FAIL_COUNT ]] && read -r count < "\$FONT_FAIL_COUNT"
    count=\$((count + 1))
    echo "\$count" > "\$FONT_FAIL_COUNT"
    if (( count == FONT_FAIL_AT )); then
        [[ \${FONT_FAIL_NOOP:-0} == 1 ]] && exit 0
        exit 1
    fi
fi
exec "$real" "\$@"
MOCK
    chmod +x "$T/bin/$tool"
done
state_snapshot() {
    local file
    for file in alacritty.toml family family.prev; do
        if [[ -e "$FD/$file" ]]; then
            stat -c '%n %a %s' "$FD/$file"
            sha256sum "$FD/$file"
        else
            echo "$file absent"
        fi
    done
}
echo "== rollback całego stanu i historii"
export FONT_FAIL_COUNT="$T/failure-count"
for mode in set reset; do
    for tool in ln mv chmod; do
        stages=3; [[ "$tool" == chmod ]] && stages=1
        for ((step=1; step<=stages; step++)); do
            bash "$S" set "Iosevka Term" >/dev/null
            bash "$S" set "Fira Code-Retina" >/dev/null
            snapshot="$(state_snapshot)"
            rm -f "$FONT_FAIL_COUNT"
            FONT_FAIL_TOOL="$tool" FONT_FAIL_AT="$step" bash "$S" "$mode" "Iosevka Term" >/dev/null; rc=$?
            check "$mode: awaria $tool #$step przywraca wszystkie pliki i historię" '(( rc != 0 )) && [[ "$(state_snapshot)" == "$snapshot" && -z "$(find "$FD" -name ".transaction.*")" ]]'
        done
    done
done
# Kod 0 atrapy mv nie dowodzi, że publikacja rzeczywiście nastąpiła.
for mode in set reset; do
    for step in 1 2 3; do
        bash "$S" set "Iosevka Term" >/dev/null
        bash "$S" set "Fira Code-Retina" >/dev/null
        snapshot="$(state_snapshot)"
        rm -f "$FONT_FAIL_COUNT"
        FONT_FAIL_TOOL=mv FONT_FAIL_AT="$step" FONT_FAIL_NOOP=1 bash "$S" "$mode" "Iosevka Term" >/dev/null; rc=$?
        check "$mode: mv #$step zwraca 0 bez zmiany, odmowa i rollback" '(( rc != 0 )) && [[ "$(state_snapshot)" == "$snapshot" ]]'
    done
done
# Początkowo nieobecne cele także muszą zostać odtworzone jako nieobecne.
bash "$S" reset >/dev/null
rm -f "$FONT_FAIL_COUNT"
snapshot="$(state_snapshot)"
FONT_FAIL_TOOL=mv FONT_FAIL_AT=2 bash "$S" set "Iosevka Term" >/dev/null; rc=$?
check "pierwszy wybór: rollback nie zostawia nowych celów" '(( rc != 0 )) && [[ "$(state_snapshot)" == "$snapshot" ]]'

# Trzymana blokada musi zatrzymać drugiego piszącego.
exec 7>>"$FD/.lock"
flock -x 7
bash "$S" set "Iosevka Term" >/dev/null 7>&- & writer=$!
sleep 0.2
check "zapis czeka na flock" 'kill -0 "$writer" 2>/dev/null'
flock -u 7; exec 7>&-
wait "$writer"
check "po zwolnieniu blokady pełny zapis" '[[ "$(<"$FD/family")" == "Iosevka Term" ]]'

# Nie obiecujemy live reload ani nie udajemy odczytu rzeczywistego fontu.
for action in first next reset again; do
    case "$action" in
        first|again) out="$(bash "$S" set "Iosevka Term")" ;;
        next) out="$(bash "$S" set "Fira Code-Retina")" ;;
        reset) out="$(bash "$S" reset)" ;;
    esac
    check "$action: jawne open a new terminal" '[[ "$out" == *"Open a new terminal"* && "$out" != *"reloads open windows"* ]]'
done
mkdir -p "$XDG_CONFIG_HOME/alacritty"
for config in no-import local-family local-size; do
    case "$config" in
        no-import) echo '[font]' > "$XDG_CONFIG_HOME/alacritty/alacritty.toml" ;;
        local-family) printf '[general]\nimport = ["~/.config/archenemy/fonts/alacritty.toml"]\n[font.normal]\nfamily = "Personal Mono"\n' > "$XDG_CONFIG_HOME/alacritty/alacritty.toml" ;;
        local-size) printf '[general]\nimport = ["~/.config/archenemy/fonts/alacritty.toml"]\n[font]\nsize = 27\n' > "$XDG_CONFIG_HOME/alacritty/alacritty.toml" ;;
    esac
    out="$(TERM_PROGRAM=Alacritty bash "$S" current)"
    check "$config: wybór, bez fałszywego rozmiaru terminala" '[[ "$out" == *"archenemy choice; unverified: personal"* && "$out" != *pt* ]]'
done
rm "$XDG_CONFIG_HOME/alacritty/alacritty.toml"
ln -s "$REPO/rices/tron/alacritty/alacritty.toml" "$XDG_CONFIG_HOME/alacritty/alacritty.toml"
out="$(TERM_PROGRAM=Alacritty bash "$S" current)"
check "rice config nadal nie potwierdza fontu otwartego okna" '[[ "$out" == *"unverified: rice Alacritty config; open a new terminal"* ]]'
out="$(TERM_PROGRAM=kitty TERM=xterm-kitty bash "$S" current)"
check "inny terminal nie dostaje fontu Alacritty jako faktu" '[[ "$out" == *"unverified: other or unknown terminal"* ]]'
rm "$XDG_CONFIG_HOME/alacritty/alacritty.toml"

echo "== konfiguracja rice'ów"
for rice in asia-n-rice crt dither-flux tron white-blue; do
    f="$REPO/rices/$rice/alacritty"
    check "$rice: import font.toml, potem wybór, bez family w alacritty.toml" \
        'python3 -c "import tomllib,sys; d=tomllib.load(open(sys.argv[1],\"rb\")); f=tomllib.load(open(sys.argv[2],\"rb\")); imp=d[\"general\"][\"import\"]; sys.exit(not (imp==[\"~/.config/alacritty/font.toml\",\"~/.config/archenemy/fonts/alacritty.toml\"] and all(\"family\" not in d[\"font\"][k] for k in (\"normal\",\"bold\",\"italic\")) and f[\"font\"][\"normal\"][\"family\"]))" "$f/alacritty.toml" "$f/font.toml"'
done
check "white-blue_beta bez zmian (family w pliku, bez importu)" 'grep -q "^family = \"JetBrainsMono Nerd Font\"" "$REPO/rices/white-blue_beta/alacritty/alacritty.toml" && ! grep -q "^import" "$REPO/rices/white-blue_beta/alacritty/alacritty.toml"'

echo "== ekran TUI"
bash "$S" reset >/dev/null
out="$(printf 'l2\n' | bash "$S" menu 2>&1)"
check "[l] + numer + Enter zapisuje font" '[[ "$(<"$FD/family")" == "Iosevka Term" ]]'
check "ekran pokazuje rice, font rice'a i tabelę" '[[ "$out" == *"Rice font"*"JetBrainsMono Nerd Font"* && "$out" == *waybar*no* && "$out" == *alacritty*yes* ]]'
check "podgląd mówi o ikonach Nerd Font" '[[ "$out" == *"Nerd Font icons: no"* ]]'
out="$(printf 'la\n' | bash "$S" menu 2>&1)"
check "[a] przełącza na wszystkie fonty" '[[ "$out" == *"installed fonts:"* && "$out" == *"DejaVu Sans"* ]]'
printf 'd' | bash "$S" menu >/dev/null 2>&1
check "[d] wraca do fontu rice'a" '[[ ! -e "$FD/family" ]]'
printf 'u' | bash "$S" menu >/dev/null 2>&1
check "[u] cofa ostatnią zmianę" '[[ "$(<"$FD/family")" == "Iosevka Term" ]]'
# Otwarte, puste FIFO = użytkownik nic nie naciska (bez procesu, na który czeka $()).
mkfifo "$T/idle"
exec 3<>"$T/idle"
start=$SECONDS
out="$(ARCHENEMY_FONT_MENU_TIMEOUT=1 timeout 8 bash "$S" menu 2>&1 <&3)"
exec 3<&-
check "menu bez odpowiedzi kończy się po limicie czasu" '(( SECONDS - start < 5 )) && [[ "$out" == *Cancelled* ]]'
out="$(printf 'fq\nq' | timeout 10 bash "$A/scripts/appbinds/appbinds.sh" 2>&1)"
check "menu główne: [f] otwiera ekran fontów" '[[ "$out" == *"Rice font"* && "$out" == *fonts* ]]'

echo "== lista ponad dziewięciu rzeczywistych pozycji"
cat >> "$T/bin/fc-list" <<'MOCK'
for ((i=1; i<=12; i++)); do printf 'Mono %02d:spacing=100\n' "$i"; done
MOCK
mapfile -t long_fonts < <(bash "$S" list)
check "lista ma ponad 9 prawdziwych fontów" '(( ${#long_fonts[@]} > 9 ))'
for keys in $'l\e[B\n\n' $'lj\n\n' $'l\e[B\e[A\n\n' $'ljk\n\n' $'l12\n\n'; do
    bash "$S" reset >/dev/null
    out="$(printf '%s' "$keys" | bash "$S" menu 2>&1)"
    case "$keys" in
        *12*) expected="${long_fonts[11]}" ;;
        *$'\e[A'*|*jk*) expected="${long_fonts[0]}" ;;
        *) expected="${long_fonts[1]}" ;;
    esac
    check "długa lista: strzałki/j/k lub numer+Enter" '[[ "$(<"$FD/family")" == "$expected" ]]'
done
snapshot="$(state_snapshot)"
out="$(printf 'l\e' | bash "$S" menu 2>&1)"
check "długa lista: Esc zachowuje stan" '[[ "$(state_snapshot)" == "$snapshot" && "$out" == *Cancelled* ]]'
out="$(printf 'la\e' | bash "$S" menu 2>&1)"
check "długa lista: [a] pokazuje proporcjonalne" '[[ "$out" == *"installed fonts:"* && "$out" == *"DejaVu Sans"* ]]'
bash "$S" set "Iosevka Term" >/dev/null

echo "== fastfetch"
# jsonc → json: komentarze // poza łańcuchami (w "$schema" jest https://).
cat > "$T/jsonc.py" <<'PY'
import json, sys
def strip(text):
    out, i, q = [], 0, False
    while i < len(text):
        c = text[i]
        if q:
            out.append(c)
            if c == "\\": out.append(text[i + 1]); i += 1
            elif c == '"': q = False
        elif c == '"': q = True; out.append(c)
        elif text.startswith("//", i):
            while i < len(text) and text[i] != "\n": i += 1
            continue
        else: out.append(c)
        i += 1
    return "".join(out)
d = json.loads(strip(open(sys.argv[1], encoding="utf-8").read()))
mods = d["modules"]
cmds = [m for m in mods if isinstance(m, dict) and m.get("type") == "command"]
tf = [m for m in mods if m == "terminalfont" or (isinstance(m, dict) and m.get("type") == "terminalfont")]
if sys.argv[2] == "beta":
    sys.exit(0 if not cmds and tf else 1)
ok = len(cmds) == 1 and not tf and "font-settings.sh\" current" in cmds[0]["text"]
keys = [m["key"] for m in mods if isinstance(m, dict) and "key" in m]
if sys.argv[2] == "panel":
    ok = ok and cmds[0]["key"] == "FONT " and all(len(k) == 5 for k in keys)
print(cmds[0]["text"] if cmds else "")
sys.exit(0 if ok else 1)
PY
for rice in asia-n-rice white-blue tron crt dither-flux; do
    kind=list; [[ "$rice" == tron || "$rice" == crt || "$rice" == dither-flux ]] && kind=panel
    text="$(python3 "$T/jsonc.py" "$REPO/rices/$rice/fastfetch/config.jsonc" "$kind")"; rc=$?
    check "$rice: jsonc się parsuje, jeden wiersz fontu ($kind)" '(( rc == 0 ))'
    check "$rice: polecenie wiersza oznacza niezweryfikowany wybór" '[[ "$(sh -c "$text")" == "Iosevka Term (archenemy choice; unverified: "* ]]'
done
python3 "$T/jsonc.py" "$REPO/rices/white-blue_beta/fastfetch/config.jsonc" beta >/dev/null
check "white-blue_beta: zostaje terminalfont (rice zamrożony)" '(( $? == 0 ))'

check "repozytorium nadal bez zmian" '[[ "$(repo_state)" == "$before_repo" ]]'
echo ""
echo "PASS: $PASS  FAIL: $FAIL"
(( FAIL == 0 ))
