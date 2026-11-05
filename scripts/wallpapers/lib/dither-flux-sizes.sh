#!/usr/bin/env bash
# =============================================
#   archenemy - scripts/wallpapers/lib/dither-flux-sizes.sh
#   Które tapety dither-flux trzeba wygenerować pod monitory z data/monitors/*.dat.
#   JEDNO ŹRÓDŁO PRAWDY — source'owane przez install/install.sh [9.7]
#   i scripts/hypr/monitor-settings.sh (Super+A → [n]).
#   Nie uruchamiaj bezpośrednio — to biblioteka funkcji.
# =============================================

# Wynik w zmiennych globalnych:
#   FLUX_SIZES         "tag:rozdzielczość" do wygenerowania
#   FLUX_READY         "monitor rozdzielczość (tag)" już gotowe
#   FLUX_SKIPPED_MONS  monitory pominięte, z powodem
# Argumenty: <katalog data/monitors> <katalog wyjściowy generated/>.
dither_flux_plan() {
    local mon_dir="$1" out_dir="$2" dat mon res role tag
    FLUX_SIZES=(); FLUX_READY=(); FLUX_SKIPPED_MONS=()
    for dat in "$mon_dir"/*.dat; do
        [[ -f "$dat" ]] || continue
        mon=$(grep '^MONITOR='    "$dat" | cut -d= -f2)
        res=$(grep '^RESOLUTION=' "$dat" | cut -d= -f2)
        role=$(grep '^ROLE='      "$dat" | cut -d= -f2)
        # Tryby nazwane (preferred/highres/highrr) nie mówią, ile to pikseli —
        # pytamy działającego Hyprlanda; bez niego monitor pomijamy z komunikatem.
        if [[ ! "$res" =~ ^[0-9]+x[0-9]+$ ]]; then
            # Bez f-stringa: backslash w wyrażeniu f-stringa to SyntaxError, a błąd
            # składni powstaje przed wykonaniem — `except` go nie złapie (złapane
            # testem na atrapie 2026-09-07).
            res=$(hyprctl -j monitors 2>/dev/null | python3 -c '
import json, sys
mon = sys.argv[1]
try:
    for m in json.load(sys.stdin):
        if m.get("name") == mon and m.get("width") and m.get("height"):
            print("%dx%d" % (int(m["width"]), int(m["height"]))); break
except Exception:
    pass' "$mon" 2>/dev/null)
            if [[ ! "$res" =~ ^[0-9]+x[0-9]+$ ]]; then
                FLUX_SKIPPED_MONS+=("$mon (tryb nazwany, brak hyprctl)")
                continue
            fi
        fi
        # Tag z NAZWY monitora, nie z licznika: numeracja zależałaby od kolejności
        # plików .dat i nowy monitor przesuwałby numery już wygenerowanych plików
        # (przeliczanie gotowych tapet — złapane testem na atrapie 2026-09-07).
        case "$role" in
            primary)   tag="v1" ;;
            secondary) tag="v2" ;;
            *)         tag="m-$mon" ;;
        esac
        # gotowe? (pierwsza forma jako wskaźnik kompletu tej rozdzielczości)
        if [[ -f "$out_dir/dither-flux-przeplyw-$tag-$res.png" ]]; then
            FLUX_READY+=("$mon $res ($tag)")
            continue
        fi
        FLUX_SIZES+=("$tag:$res")
    done
}

# Generowanie w tle, poza sesją terminala: okno Super+A może się już zamknąć.
# Argumenty: <generator .py> <katalog wyjściowy>; rozmiary z FLUX_SIZES.
dither_flux_start() {
    local gen="$1" out_dir="$2"
    mkdir -p "$out_dir"
    nohup python3 "$gen" "$out_dir" milford-woda 2026 "${FLUX_SIZES[@]}" \
        >"$out_dir/generate.log" 2>&1 &
}
