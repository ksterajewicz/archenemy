#!/usr/bin/env python3
# =============================================
#   archenemy - assets/logo/gen_text_logo.py
#   Znak Æ jako logo tekstowe dla fastfetcha: assets/logo/archenemy-ae.txt.
#   Ta sama geometria co archenemy-ae.svg — ścieżkę czyta i wypełnia
#   src/system-theme/grub/assets.py (jedno miejsce rasteryzacji), tutaj
#   piksele zamieniają się w znaki półbloków (▀ ▄ █): jedna komórka
#   terminala to dwa piksele w pionie, więc znak zachowuje proporcje.
#   Pierwsza linia zaczyna się od $1 — fastfetch podstawia tam pierwszy
#   kolor logo z configu rice'a (typ logo "file": zamiana kodów koloru).
#
#   Użycie: gen_text_logo.py            zapisuje assets/logo/archenemy-ae.txt
#           gen_text_logo.py --print    wypisuje na stdout (porównanie w teście)
#   Sama biblioteka standardowa. Kod 0 = gotowe.
# =============================================
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
COLUMNS = 36          # szerokość logo w znakach (logo Archa w fastfetchu ma 38)
VIEW = 256.0          # viewBox pliku SVG


def load_raster():
    spec = importlib.util.spec_from_file_location("grub_assets", REPO / "src/system-theme/grub/assets.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def text_logo():
    raster = load_raster()
    polygons = raster.svg_polygons(str(HERE / "archenemy-ae.svg"))
    xs = [x for polygon in polygons for x, _ in polygon]
    ys = [y for polygon in polygons for _, y in polygon]
    left, top = min(xs), min(ys)
    span = max(xs) - left
    # Znak przesunięty do rogu i przeskalowany tak, żeby jego szerokość
    # wypełniła COLUMNS pikseli; wysokość w pikselach zaokrąglona do parzystej.
    moved = [[(x - left, y - top) for x, y in polygon] for polygon in polygons]
    rows = round((max(ys) - top) / span * COLUMNS)
    rows += rows % 2
    size = max(COLUMNS, rows)
    alpha = raster.render_logo(moved, size, (255, 255, 255), view=span * size / COLUMNS)

    def on(x, y):
        return y < rows and alpha[(y * size + x) * 4 + 3] >= 128

    lines = []
    for y in range(0, rows, 2):
        line = ""
        for x in range(COLUMNS):
            upper, lower = on(x, y), on(x, y + 1)
            line += "█" if upper and lower else "▀" if upper else "▄" if lower else " "
        lines.append(line.rstrip())
    while lines and not lines[-1]:
        lines.pop()
    return "$1" + "\n".join(lines) + "\n"


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--print":
        sys.stdout.write(text_logo())
    elif len(sys.argv) == 1:
        (HERE / "archenemy-ae.txt").write_text(text_logo(), encoding="utf-8")
    else:
        raise SystemExit("usage: gen_text_logo.py [--print]")
