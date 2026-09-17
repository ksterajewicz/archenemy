#!/usr/bin/env python3
"""
archenemy — matematyczny generator tapety „oscyloskop" (rice crt).
Zero zależności (wzorzec gen_tron_wallpaper.py): PNG pisany przez zlib/struct.

Obraz: zgaszony kineskop oscyloskopu — granatowe szkło z winietą, słaba
siatka podziałki (graticule) z jaśniejszą osią, na niej świecąca krzywa
Lissajous (3:2) w cyjanie fosforu z poświatą; delikatna mgła fosforu wokół
środka ekranu. Scanlines NIE są wypalane w tapecie — nakłada je na żywo
shader ekranowy rice'a (rices/crt/hypr/shaders/crt.frag).

Paleta rice'a crt: szkło #031533 (= #043D7B ściemnione w tym samym odcieniu),
podziałka #0B358B, oś #3069AD, poświata #36D2D8, rdzeń śladu #74DCE2.
"""
import os, sys, zlib, struct, math

GLASS = (3, 21, 51)        # #031533 — tło (zgaszony kineskop)
DEEP  = (11, 53, 139)      # #0B358B — podziałka
AXIS  = (48, 105, 173)     # #3069AD — osie podziałki
GLOW  = (54, 210, 216)     # #36D2D8 — poświata śladu
CORE  = (116, 220, 226)    # #74DCE2 — rdzeń śladu

def splat(acc, w, h, cx, cy, radius, sigma, weight):
    """Dodaje gaussowską plamkę do akumulatora (lista floatów w*h)."""
    x0 = max(0, int(cx - radius)); x1 = min(w - 1, int(cx + radius))
    y0 = max(0, int(cy - radius)); y1 = min(h - 1, int(cy + radius))
    inv = -1.0 / (2.0 * sigma * sigma)
    for y in range(y0, y1 + 1):
        dy = y - cy
        row = y * w
        for x in range(x0, x1 + 1):
            dx = x - cx
            acc[row + x] += weight * math.exp((dx * dx + dy * dy) * inv)

def trace(w, h):
    """Dwa akumulatory: rdzeń (ostry) i poświata (szeroka) krzywej Lissajous."""
    core = [0.0] * (w * h)
    glow = [0.0] * (w * h)
    cx, cy = w / 2.0, h / 2.0
    ax, ay = w * 0.30, h * 0.34
    # 3:2 z przesunięciem fazy π/2 — zamknięta, symetryczna figura
    steps = 7000
    for i in range(steps):
        t = 2.0 * math.pi * i / steps
        x = cx + ax * math.sin(3.0 * t + math.pi / 2.0)
        y = cy + ay * math.sin(2.0 * t)
        # jasność wiązki zmienia się z prędkością plamki: wolniej = jaśniej
        vx = 3.0 * ax * math.cos(3.0 * t + math.pi / 2.0)
        vy = 2.0 * ay * math.cos(2.0 * t)
        speed = math.hypot(vx, vy) / (3.0 * ax)
        bright = 0.55 + 0.45 * (1.0 - min(1.0, speed))
        splat(core, w, h, x, y, 4, 1.35, 0.045 * bright)
        if i % 5 == 0:
            splat(glow, w, h, x, y, 26, 9.0, 0.020 * bright)
    return core, glow

def render(width, height, out_path):
    core, glow = trace(width, height)
    cx, cy = width / 2.0, height / 2.0
    cell = max(48, round(min(width, height) / 12))   # podziałka: 12 działek w pionie
    rows = []
    for y in range(height):
        row = bytearray()
        base = y * width
        gy = abs((y - cy) % cell)
        on_h = min(gy, cell - gy) < 0.5              # pozioma linia siatki
        axis_h = abs(y - cy) < 0.6                   # oś pozioma
        for x in range(width):
            r, g, b = GLASS

            # ── podziałka: cienkie linie co `cell`, oś środkowa mocniejsza ──
            gx = abs((x - cx) % cell)
            on_v = min(gx, cell - gx) < 0.5
            axis_v = abs(x - cx) < 0.6
            if axis_h or axis_v:
                a = 0.45
                r += (AXIS[0] - r) * a; g += (AXIS[1] - g) * a; b += (AXIS[2] - b) * a
            elif on_h or on_v:
                a = 0.28
                r += (DEEP[0] - r) * a; g += (DEEP[1] - g) * a; b += (DEEP[2] - b) * a

            # ── mgła fosforu wokół środka (lampa świeci najmocniej w osi) ──
            dx = (x - cx) / (width * 0.5)
            dy = (y - cy) / (height * 0.5)
            haze = 0.10 * math.exp(-(dx * dx + dy * dy) * 2.2)
            r += GLOW[0] * haze; g += GLOW[1] * haze; b += GLOW[2] * haze

            # ── ślad: poświata (additive), potem rdzeń ──
            gl = min(1.0, glow[base + x])
            r += GLOW[0] * gl; g += GLOW[1] * gl; b += GLOW[2] * gl
            co = min(1.0, core[base + x])
            r += (CORE[0] - r) * co; g += (CORE[1] - g) * co; b += (CORE[2] - b) * co

            # ── winieta szkła ──
            vig = 1.0 - 0.34 * min(1.0, (dx * dx + dy * dy) * 0.6)
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
    out_dir = sys.argv[1] if len(sys.argv) > 1 else 'wallpapers/crt'
    os.makedirs(out_dir, exist_ok=True)
    # konwencja przełącznika tapet: v1 = monitor główny, v2 = dodatkowy
    render(1920, 1080, f'{out_dir}/crt-scope-v1-1920x1080.png')
    render(2560, 1600, f'{out_dir}/crt-scope-v2-2560x1600.png')
