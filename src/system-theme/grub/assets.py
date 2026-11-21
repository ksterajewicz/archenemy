#!/usr/bin/env python3
# =============================================
#   archenemy - src/system-theme/grub/assets.py
#   Obrazki motywu GRUB-a dla jednego rice'a: logo Æ w kolorze rice'a i
#   wycinki ramki zaznaczonej pozycji menu. Sama biblioteka standardowa
#   (zlib, struct) — instalator nie potrzebuje Pillow, librsvg ani
#   ImageMagick na maszynie użytkownika. Woła to src/system-theme/build.sh.
#
#   Logo: ścieżka `d` z assets/logo/archenemy-ae.svg (jedno źródło
#   geometrii; tylko polecenia M L H V Z w układzie bezwzględnym),
#   wypełniana regułą parzystości z wygładzaniem krawędzi.
#
#   Zaznaczenie (selected_item_pixmap_style = "<rice>-select_*.png"):
#     bar    — pionowa kreska akcentu po lewej, tło wypełnienia;
#     frame  — ramka w kolorze akcentu dookoła, tło wypełnienia.
#   Szerokość wycinków bocznych to odstęp tekstu od krawędzi: GRUB nie ma
#   osobnego ustawienia dla tego odstępu (item_padding działa na całe menu).
#
#   Użycie: assets.py <katalog> <przedrostek> <logo.svg> <rozmiar logo px>
#                     <kolor logo> <styl: bar|frame> <kolor akcentu>
#                     <kolor wypełnienia> <grubość akcentu px> <odstęp px>
#   Kolory jako #RRGGBB. Kod 0 = pliki zapisane.
# =============================================
import re
import struct
import sys
import zlib


def write_png(path, width, height, rgba):
    """Zapisuje bufor RGBA (bytes, wiersz po wierszu) jako PNG 8 bitów na kanał."""
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    stride = width * 4
    raw = b"".join(b"\x00" + rgba[y * stride:(y + 1) * stride] for y in range(height))
    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        out.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        out.write(chunk(b"IEND", b""))


def colour(text):
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", text):
        raise SystemExit(f"assets.py: bad colour '{text}' (expected #RRGGBB)")
    return tuple(int(text[i:i + 2], 16) for i in (1, 3, 5))


def solid(width, height, rgb):
    return bytes(rgb + (255,)) * (width * height)


def with_strip(width, height, fill, accent, strip, side):
    """Prostokąt wypełnienia z paskiem akcentu przy lewej albo prawej krawędzi."""
    row = b""
    for x in range(width):
        on = x < strip if side == "w" else x >= width - strip
        row += bytes((accent if on else fill) + (255,))
    return row * height


def svg_polygons(svg_path):
    """Wielokąty ze ścieżki pierwszego <path d="..."> w pliku SVG."""
    with open(svg_path, encoding="utf-8") as src:
        match = re.search(r'<path[^>]*\sd="([^"]+)"', src.read())
    if not match:
        raise SystemExit(f"assets.py: no <path d=...> in {svg_path}")
    tokens = re.findall(r"[MLHVZ]|-?\d+(?:\.\d+)?", match.group(1))
    polygons, current, x, y, i = [], [], 0.0, 0.0, 0
    command = ""
    while i < len(tokens):
        token = tokens[i]
        if token in "MLHVZ":
            command = token
            i += 1
            if command == "Z":
                if current:
                    polygons.append(current)
                current = []
            continue
        if command in ("M", "L"):
            x, y = float(tokens[i]), float(tokens[i + 1])
            i += 2
            if command == "M":
                if current:
                    polygons.append(current)
                current = []
                command = "L"   # kolejne pary po M to odcinki
        elif command == "H":
            x = float(tokens[i])
            i += 1
        elif command == "V":
            y = float(tokens[i])
            i += 1
        else:
            raise SystemExit(f"assets.py: unsupported path data in {svg_path}")
        current.append((x, y))
    if current:
        polygons.append(current)
    if not polygons:
        raise SystemExit(f"assets.py: empty path in {svg_path}")
    return polygons


def render_logo(polygons, size, rgb, view=256.0, rows_per_pixel=8):
    """Wypełnienie regułą parzystości; pokrycie piksela = kanał alfa."""
    scale = size / view
    edges = []
    for polygon in polygons:
        points = [(px * scale, py * scale) for px, py in polygon]
        for index, (x0, y0) in enumerate(points):
            x1, y1 = points[(index + 1) % len(points)]
            if y0 != y1:
                edges.append((x0, y0, x1, y1))
    coverage = [0.0] * (size * size)
    weight = 1.0 / rows_per_pixel
    for sub in range(size * rows_per_pixel):
        line = (sub + 0.5) / rows_per_pixel
        crossings = sorted(
            x0 + (line - y0) * (x1 - x0) / (y1 - y0)
            for x0, y0, x1, y1 in edges
            if (y0 <= line < y1) or (y1 <= line < y0)
        )
        row = (sub // rows_per_pixel) * size
        for left, right in zip(crossings[0::2], crossings[1::2]):
            left, right = max(0.0, left), min(float(size), right)
            first, last = int(left), min(size - 1, int(right))
            for pixel in range(first, last + 1):
                span = min(right, pixel + 1) - max(left, pixel)
                if span > 0:
                    coverage[row + pixel] += span * weight
    out = bytearray()
    for value in coverage:
        out += bytes(rgb + (max(0, min(255, round(value * 255))),))
    return bytes(out)


def main(argv):
    if len(argv) != 11:
        raise SystemExit(__doc__ or "usage: see the header of assets.py")
    out_dir, prefix, svg = argv[1], argv[2], argv[3]
    try:
        logo_size, bar, pad = int(argv[4]), max(1, int(argv[9])), max(1, int(argv[10]))
    except ValueError:
        raise SystemExit("assets.py: sizes must be whole numbers")
    if not 8 <= logo_size <= 1024:
        raise SystemExit("assets.py: logo size out of range (8-1024)")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", prefix):
        raise SystemExit(f"assets.py: bad prefix '{prefix}'")
    logo_rgb, style = colour(argv[5]), argv[6]
    accent, fill = colour(argv[7]), colour(argv[8])

    def save(name, width, height, rgba):
        write_png(f"{out_dir}/{prefix}-{name}.png", width, height, rgba)

    save("logo", logo_size, logo_size, render_logo(svg_polygons(svg), logo_size, logo_rgb))
    save("select_c", 1, 1, solid(1, 1, fill))
    if style == "bar":
        save("select_w", bar + pad, 1, with_strip(bar + pad, 1, fill, accent, bar, "w"))
        save("select_e", pad, 1, solid(pad, 1, fill))
    elif style == "frame":
        for name in ("n", "s"):
            save(f"select_{name}", 1, bar, solid(1, bar, accent))
        save("select_w", bar + pad, 1, with_strip(bar + pad, 1, fill, accent, bar, "w"))
        save("select_e", bar + pad, 1, with_strip(bar + pad, 1, fill, accent, bar, "e"))
        for name in ("nw", "ne", "sw", "se"):
            save(f"select_{name}", bar + pad, bar, solid(bar + pad, bar, accent))
    else:
        raise SystemExit(f"assets.py: unknown selection style '{style}' (bar or frame)")


if __name__ == "__main__":
    main(sys.argv)
