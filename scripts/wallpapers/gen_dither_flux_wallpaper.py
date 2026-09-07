#!/usr/bin/env python3
"""
archenemy — generator tapet rice'a `dither-flux`.

Łączy dwa style: generatywne pole ciągłe (algorithmic art) przepuszczone przez
kwantyzację uporządkowanym ditherem Bayera 8x8 (dither art). Algorytm daje formę,
dither daje materiał — ten sam raster wraca potem w pozostałych powierzchniach rice'a.

Zero zależności: PNG pisany ręcznie przez zlib/struct (wzorzec z gen_tron_wallpaper.py).
Deterministycznie — ziarno jest jawnym parametrem, więc ten sam wywołanie zawsze
odtwarza te same pliki.

Paleta jest parametrem, nie stałą: rice deklaruje trzy kolory (tło, atrament, akcent),
a generator maluje nimi każdą formę. Dzięki temu zmiana palety rice'a nie wymaga
dotykania silników.

Użycie:
    gen_dither_flux_wallpaper.py [katalog] [paleta] [ziarno] [filtr nazw...]

    katalog  domyślnie wallpapers/dither-flux
    paleta   nazwa z PALETTES (domyślnie: milford-woda — paleta rice'a)
    ziarno   liczba całkowita (domyślnie 2026)
"""
import math, os, struct, sys, time, zlib

# ── paleta rice'a ────────────────────────────────────────────────────────────
# (tło, atrament, akcent lub None, próg pasma akcentu jako ułamek maksimum pola)
#
# `milford-woda` — paleta deszczowa odczytana z kadru Milford Sound w ulewie
# (wybór właściciela 2026-09-07): czarne mokre góry, stalowo-błękitna wzburzona
# woda, biała piana wodospadu. Akcentem jest PIANA, nie kolor ciepły — dlatego
# rozświetlenia siadają na grzbietach smug i obraz czyta się jak mokre warstwice.
# Słownik zostaje słownikiem, choć ma dziś jeden wpis: paleta jest parametrem
# wywołania, więc kolejny rice dopisze swoją bez dotykania silników.
PALETTES = {
    'milford-woda': dict(bg=(0x0F, 0x1A, 0x24), ink=(0x5C, 0x87, 0xA3), acc=(0xD8, 0xE6, 0xEE), acc_from=0.80),
}

DEFAULT_PALETTE = 'milford-woda'

# Rozdzielczości: v1 trafia na monitor główny, v2 na dodatkowy (konwencja
# przełącznika tapet — rofi_wallpaper_switcher.sh paruje pliki po *v1*/*v2*).
SIZES = [('v1', 1920, 1080), ('v2', 2560, 1600)]

# Rozmiar odniesienia, dla którego dobrano stałe silników. Wszystko, co zależy
# od liczby pikseli (cząstki, iteracje, siatki robocze), skalujemy względem
# niego — inaczej ta sama forma w 2560x1600 wychodzi rzadsza niż w podglądzie.
REF_W, REF_H = 960, 540

MASK = 0xFFFFFFFF

# ── PNG (truecolor 8-bit, filtr 0 per scanline) ──────────────────────────────

def write_png(path, bits, w, h, bg, ink, acc):
    px = (bytes(bg), bytes(ink), bytes(acc or ink))
    rows = [b''.join(px[v] for v in bits[y]) for y in range(h)]
    raw = b''.join(b'\x00' + r for r in rows)

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)

# ── dither: uporządkowana macierz Bayera 8x8 ─────────────────────────────────

def _bayer(n):
    m = [[0]]
    size = 1
    while size < n:
        m = ([[4 * v for v in row] + [4 * v + 2 for v in row] for row in m]
             + [[4 * v + 3 for v in row] + [4 * v + 1 for v in row] for row in m])
        size *= 2
    return m

BAYER8 = _bayer(8)

def dither(field, w, h, acc_from):
    """Pole [0..1] → 0 tło / 1 atrament / 2 akcent.

    Akcent nie jest osobną warstwą, tylko przesunięciem koloru atramentu tam,
    gdzie pole jest najgęstsze — przechodzi przez ten sam próg Bayera, więc
    raster zostaje jednorodny, a akcent sam trafia w „gorące" miejsca formy."""
    peak = max(v for row in field for v in row) or 1.0
    cut = acc_from * peak
    out = []
    for y in range(h):
        row = field[y]
        br = BAYER8[y & 7]
        line = []
        for x in range(w):
            v = row[x]
            if v > (br[x & 7] + 0.5) / 64.0:
                line.append(2 if v >= cut else 1)
            else:
                line.append(0)
        out.append(line)
    return out

# ── szum wartościowy i fBm ───────────────────────────────────────────────────

def h2(x, y, seed):
    n = (x * 374761393 + y * 668265263 + seed * 1013904223) & MASK
    n = (n ^ (n >> 13)) & MASK
    n = (n * 1274126177) & MASK
    n = (n ^ (n >> 16)) & MASK
    return n / MASK

def vnoise(x, y, seed=0):
    xi, yi = math.floor(x), math.floor(y)
    xf, yf = x - xi, y - yi
    u = xf * xf * (3 - 2 * xf)
    v = yf * yf * (3 - 2 * yf)
    a = h2(xi,     yi,     seed)
    b = h2(xi + 1, yi,     seed)
    c = h2(xi,     yi + 1, seed)
    d = h2(xi + 1, yi + 1, seed)
    top = a + (b - a) * u
    bot = c + (d - c) * u
    return top + (bot - top) * v

def fbm(x, y, octaves=4, seed=0):
    amp, freq, tot, norm = 1.0, 1.0, 0.0, 0.0
    for i in range(octaves):
        tot += amp * vnoise(x * freq, y * freq, seed + i * 101)
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return tot / norm

def lcg(state):
    """Jeden krok generatora liniowego — deterministyczny, bez modułu random."""
    state = (state * 1103515245 + 12345) & MASK
    return state, state / MASK

# ── operacje na polu ─────────────────────────────────────────────────────────

def normalize(field, w, h, lo_pct=0.5, hi_pct=99.5, gamma=1.0):
    vals = sorted(v for row in field for v in row)
    lo = vals[int(len(vals) * lo_pct / 100.0)]
    hi = vals[min(len(vals) - 1, int(len(vals) * hi_pct / 100.0))]
    if hi <= lo:
        hi = lo + 1e-6
    span = hi - lo
    for y in range(h):
        row = field[y]
        for x in range(w):
            t = (row[x] - lo) / span
            t = 0.0 if t < 0 else (1.0 if t > 1 else t)
            row[x] = t ** gamma if gamma != 1.0 else t
    return field

def upsample(src, sw, sh, w, h):
    out = [[0.0] * w for _ in range(h)]
    fx, fy = (sw - 1) / (w - 1), (sh - 1) / (h - 1)
    for y in range(h):
        sy = y * fy
        y0 = int(sy); y1 = min(sh - 1, y0 + 1); ty = sy - y0
        r0, r1 = src[y0], src[y1]
        orow = out[y]
        for x in range(w):
            sx = x * fx
            x0 = int(sx); x1 = min(sw - 1, x0 + 1); tx = sx - x0
            a = r0[x0] + (r0[x1] - r0[x0]) * tx
            b = r1[x0] + (r1[x1] - r1[x0]) * tx
            orow[x] = a + (b - a) * ty
    return out

def blur(field, w, h, passes=1):
    """Tanie rozmycie pudełkowe — zmiękcza akumulacje punktowe (cząstki, atraktor)."""
    for _ in range(passes):
        for y in range(h):
            row = field[y]
            prev = row[0]
            for x in range(1, w - 1):
                cur = row[x]
                row[x] = (prev + cur + row[x + 1]) / 3.0
                prev = cur
        for x in range(w):
            prev = field[0][x]
            for y in range(1, h - 1):
                cur = field[y][x]
                field[y][x] = (prev + cur + field[y + 1][x]) / 3.0
                prev = cur
    return field

def vignette(field, w, h, strength=0.35):
    cx, cy = w / 2.0, h / 2.0
    for y in range(h):
        row = field[y]
        dy = (y - cy) / cy
        for x in range(w):
            dx = (x - cx) / cx
            row[x] *= max(0.0, 1.0 - strength * (dx * dx + dy * dy))
    return field

def tone(field, w, h, level=0.62, gamma=1.9):
    """Tapeta ma być tłem, nie konkurencją dla ikon: gamma ściąga półtony w dół,
    level ogranicza maksymalne krycie atramentem."""
    for y in range(h):
        row = field[y]
        for x in range(w):
            row[x] = (row[x] ** gamma) * level
    return field

def _scale(w, h):
    """Współczynnik skali względem rozmiaru odniesienia — liniowy i powierzchniowy."""
    return (w / REF_W), (w * h) / (REF_W * REF_H)

# ── silnik: pole przepływu ───────────────────────────────────────────────────

def engine_flow(w, h, seed):
    """Cząstki wędrujące po polu wektorowym z fBm zostawiają smugi jak warstwice."""
    lin, area = _scale(w, h)
    gw, gh = max(2, w // 4), max(2, h // 4)
    ang = [[fbm(x / (26.0 * lin), y / (26.0 * lin), 4, seed) * math.tau * 2.0
            for x in range(gw)] for y in range(gh)]
    acc = [[0.0] * w for _ in range(h)]
    gx, gy = (gw - 1) / (w - 1), (gh - 1) / (h - 1)

    parts = int(5200 * area)          # gęstość smug niezależna od rozdzielczości
    steps = 260
    step = 1.35 * lin
    rnd = seed * 9781
    for _ in range(parts):
        rnd, u = lcg(rnd)
        rnd, v = lcg(rnd)
        x, y = u * w, v * h
        for _ in range(steps):
            ax, ay = int(x * gx), int(y * gy)
            if ax < 0 or ay < 0 or ax >= gw or ay >= gh:
                break
            a = ang[ay][ax]
            x += math.cos(a) * step
            y += math.sin(a) * step
            ix, iy = int(x), int(y)
            if 0 <= ix < w and 0 <= iy < h:
                acc[iy][ix] += 1.0
            else:
                break
    for y in range(h):
        row = acc[y]
        for x in range(w):
            row[x] = math.log1p(row[x])
    blur(acc, w, h, 1)
    normalize(acc, w, h, 1.0, 99.0, 0.85)
    vignette(acc, w, h, 0.30)
    return acc

# ── silnik: atraktor Clifforda (kadr poziomy) ────────────────────────────────

def _attractor_raw(w, h, seed):
    a, b, c, d = -1.7, 1.3, -0.1, -1.21
    acc = [[0.0] * w for _ in range(h)]
    x = y = 0.1
    scale = min(w, h) / 4.6
    cx, cy = w / 2.0, h / 2.0
    _, area = _scale(w, h)
    iters = min(20_000_000, int(2_600_000 * area))
    for i in range(iters):
        x, y = (math.sin(a * y) + c * math.cos(a * x),
                math.sin(b * x) + d * math.cos(b * y))
        if i < 1000:
            continue
        px, py = int(cx + x * scale), int(cy + y * scale)
        if 0 <= px < w and 0 <= py < h:
            acc[py][px] += 1.0
    for yy in range(h):
        row = acc[yy]
        for xx in range(w):
            row[xx] = math.log1p(row[xx])
    return acc

def engine_attractor(w, h, seed):
    """Kształt Clifforda jest wysoki, więc liczymy go na płótnie PIONOWYM
    powiększonym o 40%, wycinamy środek i transponujemy — inaczej stoi wąskim
    słupkiem pośrodku kadru 16:9 zamiast go wypełniać."""
    bw, bh = int(h * 1.4), int(w * 1.4)
    tall = _attractor_raw(bw, bh, seed)
    ox, oy = (bw - h) // 2, (bh - w) // 2
    out = [[tall[oy + w - 1 - x][ox + y] for x in range(w)] for y in range(h)]
    normalize(out, w, h, 2.0, 99.8, 0.9)
    return out

# ── silnik: interferencja fal ────────────────────────────────────────────────

def engine_waves(w, h, seed):
    """Sześć źródeł fal kołowych o różnych długościach; suma daje prążki mory,
    a obwiednia fBm wycisza część kadru, żeby nie pokrywały go równomiernie."""
    lin, _ = _scale(w, h)
    gw, gh = max(2, w // 2), max(2, h // 2)
    rnd = seed * 6007
    srcs = []
    for _ in range(6):
        rnd, u = lcg(rnd)
        rnd, v = lcg(rnd)
        rnd, k = lcg(rnd)
        rnd, p = lcg(rnd)
        srcs.append(((u * 1.4 - 0.2) * gw, (v * 1.4 - 0.2) * gh,
                     math.tau / ((14.0 + 22.0 * k) * lin), p * math.tau))
    field = [[0.0] * gw for _ in range(gh)]
    inv = 1.0 / (2.0 * len(srcs))
    for y in range(gh):
        row = field[y]
        for x in range(gw):
            s = 0.0
            for sx, sy, k, p in srcs:
                s += math.sin(math.hypot(x - sx, y - sy) * k + p)
            env = fbm(x / (170.0 * lin), y / (170.0 * lin), 3, seed)
            row[x] = (0.5 + s * inv) * (0.25 + 0.75 * env)
    normalize(field, gw, gh, 1.0, 99.0, 1.3)
    out = upsample(field, gw, gh, w, h)
    vignette(out, w, h, 0.35)
    return out

# ── silnik: domain warping ───────────────────────────────────────────────────

def engine_warp(w, h, seed):
    """Szum zniekształcony samym sobą — marmur, mgławica, warstwice."""
    lin, _ = _scale(w, h)
    gw, gh = max(2, w // 3), max(2, h // 3)
    field = [[0.0] * gw for _ in range(gh)]
    div = 44.0 * lin / 2.0            # siatka jest 3x mniejsza niż obraz
    for y in range(gh):
        row = field[y]
        fy = y / div
        for x in range(gw):
            fx = x / div
            qx = fbm(fx, fy, 3, seed)
            qy = fbm(fx + 5.2, fy + 1.3, 3, seed)
            rx = fbm(fx + 4.0 * qx + 1.7, fy + 4.0 * qy + 9.2, 3, seed + 7)
            row[x] = fbm(fx + 4.0 * rx, fy + 4.0 * rx, 3, seed + 13)
    normalize(field, gw, gh, 1.0, 99.0, 1.0)
    out = upsample(field, gw, gh, w, h)
    vignette(out, w, h, 0.25)
    return out

# ── formy pierwszego zestawu (wybór właściciela 2026-09-07) ──────────────────
# (nazwa pliku, silnik, offset ziarna, poziom tonowania, gamma tonowania)
# Silniki fal i domain warpingu zostają wyżej i są sprawne — po prostu nie weszły
# do pierwszego zestawu tapet; dopisanie ich tutaj wystarczy, by wróciły.
FORMS = [
    ('przeplyw',  engine_flow,      1,  0.62, 1.9),
    ('atraktor',  engine_attractor, 2,  0.62, 1.9),
    ('przeplyw2', engine_flow,      17, 0.62, 1.9),
]

def coverage(bits, w, h):
    n = w * h
    ink = sum(1 for row in bits for v in row if v)
    acc = sum(1 for row in bits for v in row if v == 2)
    return ink / n, acc / n

def render(form, engine, seed, level, gamma, palette, out_dir):
    pal = PALETTES[palette]
    for tag, w, h in SIZES:
        t0 = time.time()
        path = os.path.join(out_dir, f'dither-flux-{form}-{tag}-{w}x{h}.png')
        field = engine(w, h, seed)
        tone(field, w, h, level=level, gamma=gamma)
        bits = dither(field, w, h, pal['acc_from'])
        write_png(path, bits, w, h, pal['bg'], pal['ink'], pal['acc'])
        ink, acc = coverage(bits, w, h)
        size = os.path.getsize(path) // 1024
        print(f'  ✓ {os.path.basename(path)}  krycie {ink*100:.1f}% '
              f'akcent {acc*100:.1f}%  {size} KiB  ({time.time() - t0:.0f} s)', flush=True)

if __name__ == '__main__':
    out_dir = sys.argv[1] if len(sys.argv) > 1 else 'wallpapers/dither-flux'
    palette = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_PALETTE
    base_seed = int(sys.argv[3]) if len(sys.argv) > 3 else 2026
    only = sys.argv[4:] or None

    if palette not in PALETTES:
        sys.exit(f'Nieznana paleta: {palette}. Dostępne: {", ".join(PALETTES)}')
    os.makedirs(out_dir, exist_ok=True)
    print(f'archenemy — tapety dither-flux (paleta {palette}, ziarno {base_seed})')
    for form, engine, off, level, gamma in FORMS:
        if only and not any(o in form for o in only):
            continue
        print(f'→ {form}', flush=True)
        render(form, engine, base_seed + off, level, gamma, palette, out_dir)
