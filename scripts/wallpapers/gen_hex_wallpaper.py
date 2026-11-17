#!/usr/bin/env python3
"""
archenemy — matematyczny generator tapety „blue-hex” (zestaw white-blue):
plaster miodu z siedmiu sześciokątów w akcencie #0148ED na białym tle.
Motyw neutralny — czysta geometria, bez logo ani znaku towarowego (2026-11-17
zastąpił odrysowany znak Arch Linux, decyzja właściciela).
Zero zależności: wielokąty → scanline fill (even-odd) z antyaliasingiem
(4 subpróbki w pionie + ułamkowe pokrycie w poziomie), PNG pisany ręcznie
przez zlib/struct. Wynik jest deterministyczny (te same bajty przy każdym
biegu).

Użycie: gen_hex_wallpaper.py [v1.png] [v2.png]
  bez argumentów: blue-hex-v1-1920x1080.png i blue-hex-v2-2560x1600.png
  w bieżącym katalogu (w repo: wallpapers/blue-hex/).
"""
import math, os, sys, zlib, struct

# ── motyw: plaster miodu — 7 sześciokątów (płaski bok u góry) ───────────────
# Środkowy i sześć sąsiadów w odległości √3·R (kierunki 30°+60°·k), każdy
# pomniejszony do CELL·R, więc między komórkami zostaje równa biała szczelina.
# Wysokość motywu = 3·√3·R.
CELL = 0.86

def hexagon(cx, cy, r):
    return [(cx + r * math.cos(math.pi / 3 * k), cy + r * math.sin(math.pi / 3 * k))
            for k in range(6)]

def motif_polygons(cx, cy, height):
    R = height / (3 * math.sqrt(3))
    centers = [(cx, cy)] + [(cx + math.sqrt(3) * R * math.cos(math.radians(30 + 60 * k)),
                             cy + math.sqrt(3) * R * math.sin(math.radians(30 + 60 * k)))
                            for k in range(6)]
    return [hexagon(x, y, R * CELL) for x, y in centers]

# ── rasteryzacja ─────────────────────────────────────────────────────────────

def render(width, height, motif_frac, bg, fg, out_path):
    cx, cy = width / 2.0, height / 2.0
    polys = motif_polygons(cx, cy, height * motif_frac)
    edges = []
    for pts in polys:
        n = len(pts)
        edges += [(pts[i], pts[(i + 1) % n]) for i in range(n)]
    ys = [p[1] for pts in polys for p in pts]
    y_min, y_max = max(0, int(min(ys)) - 1), min(height - 1, int(max(ys)) + 2)

    SUB = 4
    bg_row = bytes(bg * width)
    rows = []
    for py in range(height):
        if py < y_min or py > y_max:
            rows.append(bg_row)
            continue
        cov = [0.0] * width
        for s in range(SUB):
            yline = py + (s + 0.5) / SUB
            xs = []
            for (x1, y1), (x2, y2) in edges:
                if (y1 <= yline < y2) or (y2 <= yline < y1):
                    xs.append(x1 + (yline - y1) * (x2 - x1) / (y2 - y1))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                xa, xb = max(xs[i], 0.0), min(xs[i + 1], float(width))
                if xb <= xa:
                    continue
                ia, ib = int(xa), int(xb)
                if ia == ib:
                    cov[ia] += (xb - xa) / SUB
                else:
                    cov[ia] += (ia + 1 - xa) / SUB
                    for px in range(ia + 1, ib):
                        cov[px] += 1.0 / SUB
                    if ib < width:
                        cov[ib] += (xb - ib) / SUB
        row = bytearray(bg_row)
        for px in range(width):
            c = cov[px]
            if c > 0.001:
                if c > 1.0:
                    c = 1.0
                base = px * 3
                for k in range(3):
                    row[base + k] = round(bg[k] + (fg[k] - bg[k]) * c)
        rows.append(bytes(row))

    # ── PNG (RGB8, filtr 0, zlib) ────────────────────────────────────────────
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    raw = b"".join(b"\x00" + r for r in rows)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    # ścieżka z argv może wskazywać nieistniejący katalog
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(png)
    print(f"OK {out_path} ({width}x{height}, motif {int(height * motif_frac)}px)")

if __name__ == "__main__":
    BG = (255, 255, 255)
    FG = (0x01, 0x48, 0xED)   # #0148ED — akcent white-blue
    FRAC = 0.40               # wysokość motywu = 40% wysokości ekranu
    # v1 = monitor główny (1920x1080), v2 = dodatkowy (2560x1600)
    for w, h, name in [
        (1920, 1080, sys.argv[1] if len(sys.argv) > 1 else "blue-hex-v1-1920x1080.png"),
        (2560, 1600, sys.argv[2] if len(sys.argv) > 2 else "blue-hex-v2-2560x1600.png"),
    ]:
        render(w, h, FRAC, BG, FG, name)
