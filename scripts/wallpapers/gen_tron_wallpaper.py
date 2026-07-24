#!/usr/bin/env python3
"""
archenemy — matematyczny generator tapety „siatka Tron" (rice tron).
Zero zależności: perspektywiczna siatka (podłoga Gridu) pod linią horyzontu
z cyjanową poświatą, pionowe linie zbiegające do punktu zbiegu, delikatna
winieta; PNG pisany ręcznie przez zlib/struct (wzorzec z gen_arch_wallpaper.py).

Paleta rice'a tron: tło #020A0F, neon #00E5FF, przygaszony #0E2A33.
"""
import os, sys, zlib, struct, math

BG    = (2, 10, 15)        # ~#020A0F
NEON  = (0, 229, 255)      # #00E5FF
DIM   = (14, 42, 51)       # #0E2A33 — linie daleko od horyzontu

# ── geometria siatki ─────────────────────────────────────────────────────────

def grid_pixel(x, y, w, h):
    """Zwraca jasność linii siatki [0..1] dla piksela (x, y).

    Podłoga Gridu: poniżej horyzontu (h*0.42) linie poziome zagęszczają się
    perspektywicznie ku horyzontowi, pionowe zbiegają do punktu zbiegu.
    Nad horyzontem tylko poświata."""
    horizon = h * 0.42
    if y <= horizon:
        # nad horyzontem: sama poświata (obliczana osobno) — bez linii
        return 0.0

    # głębia 0 (horyzont) → 1 (dolna krawędź); rozkład perspektywiczny
    depth = (y - horizon) / (h - horizon)

    # ── linie poziome: stałe kroki w przestrzeni świata → 1/z na ekranie ──
    # z = 1/depth (im bliżej horyzontu, tym dalej w świecie)
    z = 1.0 / max(depth, 1e-6)
    fz = z * 6.0                     # 6 „płyt" podłogi na głębokość ekranu
    dist_h = abs(fz - round(fz))     # odległość od najbliższej linii (0..0.5)
    # grubość linii rośnie z bliskością (depth→1 = gruba linia przy dole)
    thick_h = 0.020 + 0.030 * depth
    line_h = max(0.0, 1.0 - dist_h / thick_h)

    # ── linie pionowe: promienie z punktu zbiegu (środek, horyzont) ──
    cx = w / 2.0
    # kąt względem punktu zbiegu, znormalizowany do szerokości płyty
    u = (x - cx) / (y - horizon + 1e-6)   # stałe u = linia prosta do zbiegu
    fu = u / 1.6                          # gęstość promieni
    dist_v = abs(fu - round(fu))
    thick_v = 0.020 + 0.018 * depth
    line_v = max(0.0, 1.0 - dist_v / thick_v)

    return max(line_h, line_v)

def render(width, height, out_path):
    horizon = height * 0.42
    cx = width / 2.0
    rows = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            r, g, b = BG

            # ── poświata horyzontu (obie strony, nad — szersza i słabsza) ──
            d_hor = abs(y - horizon) / height
            glow = math.exp(-(d_hor * 18.0) ** 2) * 0.55        # wąski neon
            glow += math.exp(-(d_hor * 5.0) ** 2) * 0.12        # szeroka mgła
            # rozjaśnienie ku środkowi (punkt zbiegu „świeci")
            glow *= 0.55 + 0.45 * math.exp(-((x - cx) / (width * 0.45)) ** 2)

            # ── siatka pod horyzontem ──
            g_line = grid_pixel(x, y, width, height)
            if g_line > 0.0:
                depth = (y - horizon) / (height - horizon)
                # linie: daleko przygaszone (DIM), blisko dołu — pełny neon
                mix = 0.25 + 0.75 * depth ** 1.5
                lr = DIM[0] + (NEON[0] - DIM[0]) * mix
                lg = DIM[1] + (NEON[1] - DIM[1]) * mix
                lb = DIM[2] + (NEON[2] - DIM[2]) * mix
                a = g_line * (0.35 + 0.65 * depth)   # krycie linii rośnie z bliskością
                r += (lr - r) * a
                g += (lg - g) * a
                b += (lb - b) * a

            # ── nałóż poświatę (additive, przycięta) ──
            r += NEON[0] * glow * 0.9
            g += NEON[1] * glow * 0.9
            b += NEON[2] * glow * 0.9

            # ── winieta na rogach ──
            dx = (x - cx) / (width * 0.5)
            dy = (y - height * 0.5) / (height * 0.5)
            vig = 1.0 - 0.22 * min(1.0, (dx * dx + dy * dy) * 0.55)
            r *= vig; g *= vig; b *= vig

            row += bytes((min(255, int(r)), min(255, int(g)), min(255, int(b))))
        rows.append(bytes(row))

    # ── zapis PNG (truecolor 8-bit, filtr 0 per scanline) ──
    raw = b''.join(b'\x00' + r for r in rows)
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    with open(out_path, 'wb') as f:
        f.write(png)
    print(f'✓ {out_path} ({width}x{height}, {len(png)//1024} KiB)')

if __name__ == '__main__':
    out_dir = sys.argv[1] if len(sys.argv) > 1 else 'wallpapers/tron-grid'
    # katalog wyjściowy może nie istnieć (świeże repo / własna ścieżka)
    os.makedirs(out_dir, exist_ok=True)
    # konwencja przełącznika tapet: v1 = monitor główny, v2 = dodatkowy
    render(1920, 1080, f'{out_dir}/tron-grid-v1-1920x1080.png')
    render(2560, 1600, f'{out_dir}/tron-grid-v2-2560x1600.png')
