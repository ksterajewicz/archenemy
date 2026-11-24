#!/usr/bin/env bash
# =============================================
#   archenemy - scripts/wallpapers/lib/dither-flux-sizes.sh
#   Które tapety dither-flux trzeba wygenerować pod monitory z data/monitors/*.dat.
#   JEDNO ŹRÓDŁO PRAWDY — source'owane przez install/install.sh [9.7]
#   i scripts/hypr/monitor-settings.sh (Super+A → [n]).
#   Nie uruchamiaj bezpośrednio — to biblioteka funkcji.
# =============================================

# Znacznik kompletu: OSTATNIA forma z FORMS w gen_dither_flux_wallpaper.py.
# Generator rysuje formy po kolei i każdy plik zapisuje atomowo, więc gdy jest
# plik tej formy, są i wcześniejsze. Przerwany bieg (reboot w trakcie generowania
# w tle) zostawia tylko pierwsze formy i rozmiar wraca do kolejki. Dawniej
# znacznikiem była PIERWSZA forma: po przerwie reszta form nigdy się nie
# dorabiała (audyt 2026-11-05, A10). Zgodność z FORMS: tests/dither-flux-sizes.sh.
DITHER_FLUX_LAST_FORM="przeplyw2"

# Wynik w zmiennych globalnych:
#   FLUX_SIZES         "tag:rozdzielczość" do wygenerowania
#   FLUX_READY         "monitor rozdzielczość (tag)" już gotowe
#   FLUX_SKIPPED_MONS  monitory pominięte, z powodem
#   FLUX_WANT          "tag-rozdzielczość" WSZYSTKICH monitorów (gotowe i do
#                      wygenerowania) — dla dither_flux_prune
#   FLUX_SKIPPED_TAGS  tagi monitorów pominiętych (rozdzielczość nieznana, więc
#                      dither_flux_prune nie rusza żadnego pliku z takim tagiem)
#   FLUX_MONS          liczba przeczytanych plików .dat
# Argumenty: <katalog data/monitors> <katalog wyjściowy generated/>.
dither_flux_plan() {
    local mon_dir="$1" out_dir="$2" dat mon res role tag
    FLUX_SIZES=(); FLUX_READY=(); FLUX_SKIPPED_MONS=()
    FLUX_WANT=(); FLUX_SKIPPED_TAGS=(); FLUX_MONS=0
    for dat in "$mon_dir"/*.dat; do
        [[ -f "$dat" ]] || continue
        FLUX_MONS=$((FLUX_MONS + 1))
        mon=$(grep '^MONITOR='    "$dat" | cut -d= -f2)
        res=$(grep '^RESOLUTION=' "$dat" | cut -d= -f2)
        role=$(grep '^ROLE='      "$dat" | cut -d= -f2)
        # Tag z NAZWY monitora, nie z licznika: numeracja zależałaby od kolejności
        # plików .dat i nowy monitor przesuwałby numery już wygenerowanych plików
        # (przeliczanie gotowych tapet — złapane testem na atrapie 2026-09-07).
        # Generator przyjmuje w tagu litery, cyfry i myślnik; inny znak (nazwa
        # złącza spoza DRM) zamieniamy na myślnik, bo nierozpoznany tag generator
        # bierze za filtr form i nie rysuje wtedy niczego.
        case "$role" in
            primary)   tag="v1" ;;
            secondary) tag="v2" ;;
            *)         tag="m-${mon//[^A-Za-z0-9-]/-}" ;;
        esac
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
                FLUX_SKIPPED_TAGS+=("$tag")
                continue
            fi
        fi
        FLUX_WANT+=("$tag-$res")
        # gotowe? (ostatnia forma jako znacznik kompletu tej rozdzielczości)
        if [[ -f "$out_dir/dither-flux-$DITHER_FLUX_LAST_FORM-$tag-$res.png" ]]; then
            FLUX_READY+=("$mon $res ($tag)")
            continue
        fi
        FLUX_SIZES+=("$tag:$res")
    done
}

# Sprzątanie generated/ — wołaj ZARAZ po dither_flux_plan (bierze FLUX_WANT,
# FLUX_SKIPPED_TAGS i FLUX_MONS). Zgłoszenie właściciela 2026-11-24 („przy
# aktualizacjach tapety często się dublują”): plan tylko dokładał trzy formy pod
# każdą nową parę tag:rozdzielczość (dok/bez doku zmienia, kto jest primary;
# zmiana trybu w Super+A → [n]; rola other po nazwie złącza), a pliki pod
# monitory, których już nie ma, zostawały na zawsze i każdy był kaflem w Super+W.
# Bezpiecznie:
#   - tylko pliki z nazwą generatora (dither-flux-<forma>-<tag>-<W>x<H>.png)
#     w generated/, który tworzy sam program; inne pliki zostają;
#   - nigdy plik, na który wskazuje zapisany wybór (data/wallpaper.dat,
#     data/hyprlock-wallpaper.dat, config/hypr/hyprpaper.conf) — np. tapeta
#     odpiętego monitora czeka w configu na ponowne podpięcie;
#   - monitor pominięty w planie (tryb nazwany bez Hyprlanda) chroni wszystkie
#     pliki swojego tagu; brak jakiegokolwiek .dat = nic nie ruszamy;
#   - nie rm, tylko mv do ukrytego generated/.bak-<czas>-XXXX (menu Super+W
#     pomija ukryte ścieżki); stamtąd można je przywrócić albo skasować ręcznie.
# Ścieżki stanu liczone od katalogu .dat: <archenemy>/data/monitors → data/,
# a config/ obok data/ (tak wołają install.sh [9.7] i monitor-settings.sh).
# Argumenty: <katalog data/monitors> <katalog generated/>.
# Wynik: FLUX_PRUNED (liczba przeniesionych), FLUX_PRUNE_DIR (dokąd; puste = nic).
dither_flux_prune() {
    local mon_dir="$1" out_dir="$2" data_dir f base keep w t
    local -a refs=()
    FLUX_PRUNED=0; FLUX_PRUNE_DIR=""
    (( ${FLUX_MONS:-0} > 0 )) || return 0
    [[ -d "$out_dir" ]] || return 0
    data_dir="$(dirname "$mon_dir")"
    for f in "$data_dir/wallpaper.dat" "$data_dir/hyprlock-wallpaper.dat" \
             "$(dirname "$data_dir")/config/hypr/hyprpaper.conf"; do
        [[ -f "$f" ]] && refs+=("$f")
    done
    for f in "$out_dir"/dither-flux-*.png; do
        [[ -f "$f" && ! -L "$f" ]] || continue
        base="${f##*/}"
        [[ "$base" =~ ^dither-flux-[a-z0-9]+-(v[0-9]+|m-[A-Za-z0-9-]+)-[0-9]+x[0-9]+\.png$ ]] || continue
        keep=0
        for w in "${FLUX_WANT[@]}"; do
            [[ "$base" == *"-$w.png" ]] && { keep=1; break; }
        done
        for t in "${FLUX_SKIPPED_TAGS[@]}"; do
            [[ "$base" == *"-$t-"[0-9]*x[0-9]*.png ]] && { keep=1; break; }
        done
        # Nazwa w pliku stanu = plik w użyciu (także ta sama nazwa z innego
        # katalogu — wtedy też zostaje: wolimy nadmiar niż czarny ekran).
        (( keep == 0 && ${#refs[@]} > 0 )) && grep -qF -- "$base" "${refs[@]}" && keep=1
        (( keep )) && continue
        if [[ -z "$FLUX_PRUNE_DIR" ]]; then
            FLUX_PRUNE_DIR="$(mktemp -d "$out_dir/.bak-$(date +%Y%m%d-%H%M%S)-XXXX")" || { FLUX_PRUNE_DIR=""; return 1; }
        fi
        mv -n -- "$f" "$FLUX_PRUNE_DIR/" && FLUX_PRUNED=$((FLUX_PRUNED + 1))
    done
    # Nic nie przeniesione (np. mv odmówił) — pusty katalog .bak nie zostaje.
    if [[ -n "$FLUX_PRUNE_DIR" ]] && (( FLUX_PRUNED == 0 )); then
        rmdir -- "$FLUX_PRUNE_DIR" 2>/dev/null
        FLUX_PRUNE_DIR=""
    fi
    return 0
}

# Generowanie w tle, poza sesją terminala: okno Super+A może się już zamknąć.
# Argumenty: <generator .py> <katalog wyjściowy>; rozmiary z FLUX_SIZES.
dither_flux_start() {
    local gen="$1" out_dir="$2"
    mkdir -p "$out_dir"
    nohup python3 "$gen" "$out_dir" milford-woda 2026 "${FLUX_SIZES[@]}" \
        >"$out_dir/generate.log" 2>&1 &
}
