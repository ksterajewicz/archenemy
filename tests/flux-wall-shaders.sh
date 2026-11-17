#!/usr/bin/env bash
# =============================================
#   archenemy - tests/flux-wall-shaders.sh
#   Precyzja samplerów we WSZYSTKICH shaderach flux-walla (decyzja
#   2026-09-08 „precision highp sampler2D”). W GLSL ES 3.00 sampler bez
#   deklaracji ma lowp; Mesa/llvmpipe honorują to i zaokrąglają wynik
#   texelFetch (pozycje cząstek RGBA32F wracały z ~8-bitową precyzją),
#   NVIDIA kwalifikatory ignoruje — na laptopie błąd jest niewidoczny,
#   więc pilnuje go ten test, nie oko. Audyt 2026-11-05, F6: brakowało
#   linii w VS_SPLAT (engine.c), który czyta pozycje cząstek przez texelFetch.
#
#   Reguły (statycznie, bez GPU i bez kompilatora):
#     1. każdy src/flux-wall/shaders/*.frag i tools/*.frag deklaruje
#        `precision highp sampler2D;` przed pierwszym użyciem sampler2D;
#     2. każde źródło GLSL wpisane w engine.c jako `static const char *X =`
#        („#version …”), które używa sampler2D, deklaruje tę precyzję
#        przed pierwszym użyciem; *.update.glsl dostają ją z UPDATE_PRELUDE.
#   Uruchom: bash tests/flux-wall-shaders.sh   (kod 0 = wszystko przeszło)
# =============================================

# shellcheck disable=SC1111  # „” w komunikatach to tekst
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="$REPO/src/flux-wall"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

# check_glsl — stdin: tekst jednego shadera; stdout: „ok”, „brak”
# (sampler2D bez deklaracji precyzji), „za-pozno” (deklaracja po pierwszym
# użyciu) albo „bez-samplera”. Komentarze (/* … */ także wieloliniowe, //)
# są pomijane — nagłówki shaderów wspominają „accum (sampler2D)” przed kodem.
check_glsl() {
    awk '
        {
            rest = $0; code = ""
            while (rest != "") {
                if (inc) {
                    p = index(rest, "*/")
                    if (!p) { rest = ""; break }
                    rest = substr(rest, p + 2); inc = 0
                } else {
                    p = index(rest, "/*"); q = index(rest, "//")
                    if (q && (!p || q < p)) { code = code substr(rest, 1, q - 1); rest = ""; break }
                    if (p) { code = code substr(rest, 1, p - 1); rest = substr(rest, p + 2); inc = 1 }
                    else   { code = code rest; rest = "" }
                }
            }
        }
        code ~ /precision[ \t]+highp[ \t]+sampler2D[ \t]*;/ { if (!prec) prec = NR; next }
        code ~ /sampler2D/                                  { if (!use) use = NR }
        END {
            if (!use)              print (prec ? "ok" : "bez-samplera")
            else if (!prec)        print "brak"
            else if (prec > use)   print "za-pozno"
            else                   print "ok"
        }'
}

echo "pliki shaderów (.frag): precision highp sampler2D"
n=0
for f in "$FW"/shaders/*.frag "$FW"/tools/*.frag; do
    [[ -f "$f" ]] || continue
    n=$((n + 1))
    rel="${f#"$REPO"/}"
    case "$(check_glsl < "$f")" in
        ok)       ok "$rel" ;;
        za-pozno) fail "$rel: deklaracja precyzji po pierwszym użyciu sampler2D" ;;
        *)        fail "$rel: brak \`precision highp sampler2D;\` (decyzja 2026-09-08)" ;;
    esac
done
((n > 0)) || fail "nie znaleziono żadnego .frag w $FW/shaders"

echo "shadery wbudowane w engine.c"
# Bloki `static const char *NAZWA =` aż do linii kończącej się `";` — każdy
# wypisywany jako „@@ NAZWA” + jego linie, dalej dzielony w bashu.
blocks="$(awk '
    /^static const char \*[A-Za-z_0-9]+ =/ { name = $4; sub(/^\*/, "", name); print "@@ " name; inb = 1; next }
    inb { print; if ($0 ~ /";[ \t]*(\/\*.*)?$/) inb = 0 }
' "$FW/engine.c")"
glsl=0; with_sampler=0; seen_splat=0
name=""; body=""
flush() {
    [[ -n "$name" ]] || return 0
    if ! grep -q '"#version' <<< "$body"; then return 0; fi
    glsl=$((glsl + 1))
    local res
    res="$(check_glsl <<< "$body")"
    [[ "$res" == bez-samplera ]] && return 0
    with_sampler=$((with_sampler + 1))
    [[ "$name" == VS_SPLAT ]] && seen_splat=1
    case "$res" in
        ok)       ok "engine.c: $name" ;;
        za-pozno) fail "engine.c: $name — deklaracja precyzji po pierwszym użyciu sampler2D" ;;
        *)        fail "engine.c: $name używa sampler2D bez \`precision highp sampler2D;\` (decyzja 2026-09-08)" ;;
    esac
}
while IFS= read -r line; do
    if [[ "$line" == "@@ "* ]]; then
        flush
        name="${line#@@ }"; body=""
    else
        body+="$line"$'\n'
    fi
done <<< "$blocks"
flush
# Bezpiecznik parsera: gdyby zmienił się zapis źródeł w engine.c, test nie
# może przejść „zielono”, bo nic nie sprawdził.
if ((glsl >= 4 && with_sampler >= 2 && seen_splat == 1)); then
    ok "parser: $glsl źródeł GLSL, $with_sampler z sampler2D (w tym VS_SPLAT)"
else
    fail "parser: $glsl źródeł GLSL, $with_sampler z sampler2D, VS_SPLAT: $seen_splat — zmienił się zapis shaderów w engine.c?"
fi

echo ""
echo "Wynik: $PASS ✓ / $FAIL ✗"
[[ $FAIL -eq 0 ]]
