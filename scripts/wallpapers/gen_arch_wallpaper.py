#!/usr/bin/env python3
"""
archenemy — matematyczny generator tapety z logo Arch Linux.
Zero zależności: krzywe Béziera → polygon → scanline fill (even-odd)
z antyaliasingiem (4 subpróbki w pionie + ułamkowe pokrycie w poziomie),
PNG pisany ręcznie przez zlib/struct.
"""
import sys, zlib, struct

# ── logo: sylwetka "A" Archa w przestrzeni 1000x900 (y w dół) ────────────────
# Krzywe dobrane ręcznie; legs rozszerzają się ku dołowi, spód nóg wznosi się
# wklęsło ku środkowi, szczyt i wierzchołek szczeliny lekko zaokrąglone.

def bezier(p0, c1, c2, p1, n=80):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        u = 1 - t
        x = u*u*u*p0[0] + 3*u*u*t*c1[0] + 3*u*t*t*c2[0] + t*t*t*p1[0]
        y = u*u*u*p0[1] + 3*u*u*t*c1[1] + 3*u*t*t*c2[1] + t*t*t*p1[1]
        pts.append((x, y))
    return pts

def logo_polygon():
    P = [(486, 25)]                                            # lewy brzeg szczytu
    P += bezier((486, 25), (494, 8), (506, 8), (514, 25))      # zaokrąglony wierzchołek
    P.append((1000, 900))                                      # prawa krawędź zewn.
    P += bezier((1000, 900), (885, 858), (760, 826), (668, 822))  # prawy spód (wklęsły)
    # krawędź szczeliny lekko wybrzuszona w stronę nogi (jak w oryginale)
    P += bezier((668, 822), (585, 610), (543, 475), (526, 432))
    P += bezier((526, 432), (514, 398), (486, 398), (474, 432))  # szczyt szczeliny
    P += bezier((474, 432), (457, 475), (415, 610), (332, 822))
    P += bezier((332, 822), (240, 826), (115, 858), (0, 900))  # lewy spód (wklęsły)
    return P                                                   # zamknięcie do (486,25)

LOGO_W, LOGO_H = 1000.0, 875.0   # wysokość: y 25..900

# ── rasteryzacja ─────────────────────────────────────────────────────────────

def render(width, height, logo_frac, bg, fg, out_path):
    scale = (height * logo_frac) / LOGO_H
    off_x = width / 2 - (LOGO_W / 2) * scale
    off_y = height / 2 - (25 + LOGO_H / 2) * scale

    pts = [(x * scale + off_x, y * scale + off_y) for x, y in logo_polygon()]
    n = len(pts)
    edges = [(pts[i], pts[(i + 1) % n]) for i in range(n)]
    ys = [p[1] for p in pts]
    y_min, y_max = max(0, int(min(ys)) - 1), min(height - 1, int(max(ys)) + 2)

    SUB = 4
    white_row = bytes(bg * width)
    rows = []
    for py in range(height):
        if py < y_min or py > y_max:
            rows.append(white_row)
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
        row = bytearray(white_row)
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
    with open(out_path, "wb") as f:
        f.write(png)
    print(f"OK {out_path} ({width}x{height}, logo {int(height*logo_frac)}px)")

if __name__ == "__main__":
    BG = (255, 255, 255)
    FG = (0x01, 0x48, 0xED)   # #0148ED — akcent white-blue
    FRAC = 0.40               # wysokość logo = 40% wysokości ekranu
    # v1 = monitor główny (1920x1080), v2 = dodatkowy (2560x1600)
    for w, h, name in [
        (1920, 1080, sys.argv[1] if len(sys.argv) > 1 else "arch-logo-v1-1920x1080.png"),
        (2560, 1600, sys.argv[2] if len(sys.argv) > 2 else "arch-logo-v2-2560x1600.png"),
    ]:
        render(w, h, FRAC, BG, FG, name)
