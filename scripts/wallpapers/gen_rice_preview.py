#!/usr/bin/env python3
"""
archenemy — makieta podglądu rice'a do menu Super+T: rices/<rice>/preview.png.
Zero zależności (wzorzec gen_*_wallpaper.py): PNG pisany przez zlib/struct.

Prawdziwy zrzut ekranu wymaga żywej sesji Hyprlanda, więc repo trzyma
MAKIETĘ złożoną z kolorów, które rice naprawdę deklaruje — nic nie jest
wpisane na sztywno poza motywem tła:
  * tło: paleta z rices/<rice>/flux-wall.conf (bg, ink, accent) + motyw
    tapety rice'a (logo Arch / siatka Tron / oscyloskop / dither Bayera /
    słońce) — tapet nie da się tu zmniejszyć bez dekodera, więc motyw jest
    rysowany, nie skalowany,
  * pasek: wyspy waybara z rices/<rice>/waybar/style.css (.modules-left,
    #clock, .modules-right: tło, ramka, promień; aktywny workspace),
  * okna: ramka i zaokrąglenie z rices/<rice>/hypr/hyprland.lua
    (col.active_border, col.inactive_border, border_size, rounding),
    wnętrze i „tekst" z rices/<rice>/alacritty/alacritty.toml (tło +
    opacity, foreground, kursor, 16 kolorów ANSI jako dwa rzędy próbek).
  * paleta flux-wall (bg, ink, accent) jako trzy próbki w terminalu;
    prawa połowa kadru to sama tapeta z motywem.

Makietę można w każdej chwili zastąpić prawdziwym zrzutem (Super+Print
→ zapisz jako rices/<rice>/preview.png) — menu bierze plik pod tą ścieżką,
cokolwiek w nim jest.

Użycie:
  gen_rice_preview.py                 każdy rice ze stubem w
                                      scripts/changing-theme-scripts/
  gen_rice_preview.py tron crt        wybrane rice'y
  gen_rice_preview.py tron --out X.png   jeden rice do wskazanego pliku
"""
import math
import os
import re
import struct
import sys
import zlib

W, H = 640, 360
MOTIF_CX = 488.0   # środek wolnej (prawej) części kadru — tam motyw tapety
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# Motyw tła per rice (tapeta nie jest przypisana do rice'a w kodzie — to
# skojarzenie z README: zestawy arch-white / tron-grid / crt / dither-flux).
# Paleta awaryjna tylko dla rice'a bez flux-wall.conf (white-blue_beta).
MOTIFS = {
    'white-blue':      'arch',
    'white-blue_beta': 'arch',
    'tron':            'grid',
    'crt':             'scope',
    'dither-flux':     'dither',
    'asia-n-rice':     'sun',
}
FALLBACK_PALETTE = {
    'white-blue_beta': ('F7F9FC', '9AA5B1', '0148ED'),
}

# ─── kolory ──────────────────────────────────────────────────────────────────

def hex_rgb(h):
    h = h.strip().lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

COLOR_RE = re.compile(r'#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b|rgba?\(\s*[^)]*\)')

def css_color(value):
    """Pierwszy kolor w wartości CSS → ((r,g,b), alfa) albo None
    (transparent / brak). linear-gradient → jego pierwszy kolor."""
    if value is None or value.strip().startswith('transparent'):
        return None
    m = COLOR_RE.search(value)
    if not m:
        return None
    s = m.group(0)
    if s.startswith('#'):
        return hex_rgb(s), 1.0
    nums = [p.strip() for p in s[s.index('(') + 1:-1].split(',')]
    if len(nums) == 1 and re.fullmatch(r'[0-9A-Fa-f]{6,8}', nums[0]):   # hypr: rgb(RRGGBB)
        h = nums[0]
        return hex_rgb(h[:6]), (int(h[6:8], 16) / 255.0 if len(h) == 8 else 1.0)
    rgb = tuple(float(n) for n in nums[:3])
    return rgb, (float(nums[3]) if len(nums) > 3 else 1.0)

# ─── odczyt plików rice'a ───────────────────────────────────────────────────

def read(path):
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except OSError:
        return ''

def flux_palette(rice):
    m = re.search(r'^FLUX_WALL_PALETTE="?([0-9A-Fa-f]{6}),([0-9A-Fa-f]{6}),([0-9A-Fa-f]{6})"?',
                  read(os.path.join(REPO, 'rices', rice, 'flux-wall.conf')), re.M)
    hexes = m.groups() if m else FALLBACK_PALETTE.get(rice, ('1A1A2E', '9AA5B1', '0148ED'))
    return tuple(hex_rgb(h) for h in hexes)

def css_blocks(rice):
    """selektor → {właściwość: wartość} (ostatnia deklaracja wygrywa)."""
    text = re.sub(r'/\*.*?\*/', '', read(os.path.join(REPO, 'rices', rice, 'waybar', 'style.css')), flags=re.S)
    out = {}
    for sel, body in re.findall(r'([^{}]+)\{([^{}]*)\}', text):
        props = {}
        for decl in body.split(';'):
            if ':' in decl:
                k, v = decl.split(':', 1)
                props[k.strip()] = v.strip()
        for s in sel.split(','):
            out.setdefault(s.strip(), {}).update(props)
    return out

def waybar_style(rice, fallback_bg, fallback_fg, accent):
    css = css_blocks(rice)
    def prop(sel, key):
        return css.get(sel, {}).get(key)
    island = None
    for sel in ('.modules-left', '#clock', 'window#waybar'):
        c = css_color(prop(sel, 'background'))
        if c:
            island = sel
            break
    bg = css_color(prop(island, 'background')) if island else None
    border = css_color(prop(island, 'border')) if island else None
    radius = prop(island, 'border-radius') if island else None
    fg = css_color(prop(island, 'color')) if island else None
    clock_fg = css_color(prop('#clock', 'color'))
    active = css_color(prop('#workspaces button.active', 'background'))
    rad = re.match(r'\s*(\d+(?:\.\d+)?)', radius or '')
    return {
        'bg': bg or (fallback_bg, 0.8),
        'border': border,
        'radius': float(rad.group(1)) if rad else 0.0,
        'fg': fg[0] if fg else fallback_fg,
        'clock': clock_fg[0] if clock_fg else (fg[0] if fg else fallback_fg),
        'active': active[0] if active else accent,
    }

def toml_colors(rice):
    """alacritty.toml → sekcje z kluczami (tylko to, czego potrzebujemy)."""
    sec, out = '', {}
    for line in read(os.path.join(REPO, 'rices', rice, 'alacritty', 'alacritty.toml')).splitlines():
        line = line.strip()
        m = re.match(r'\[([^\]]+)\]', line)
        if m:
            sec = m.group(1)
            continue
        # wartość w cudzysłowie ("#RRGGBB" — `#` to nie komentarz) albo goła
        m = re.match(r'([A-Za-z_]+)\s*=\s*(?:"([^"]*)"|([^\s#]+))', line)
        if m:
            out.setdefault(sec, {})[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
    return out

def alacritty_style(rice):
    t = toml_colors(rice)
    prim = t.get('colors.primary', {})
    names = ('black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white')
    normal = [hex_rgb(t.get('colors.normal', {}).get(n, '#808080')) for n in names]
    bright = [hex_rgb(t.get('colors.bright', {}).get(n, '#C0C0C0')) for n in names]
    try:
        opacity = float(t.get('window', {}).get('opacity', '1'))
    except ValueError:
        opacity = 1.0
    return {
        'bg': hex_rgb(prim.get('background', '#1A1A2E')),
        'fg': hex_rgb(prim.get('foreground', '#FFFFFF')),
        'cursor': hex_rgb(t.get('colors.cursor', {}).get('cursor', prim.get('foreground', '#FFFFFF'))),
        'opacity': opacity,
        'normal': normal,
        'bright': bright,
    }

def hypr_style(rice, accent):
    lua = read(os.path.join(REPO, 'rices', rice, 'hypr', 'hyprland.lua'))
    def num(key, default):
        m = re.search(r'\b' + key + r'\s*=\s*(\d+)', lua)
        return int(m.group(1)) if m else default
    def col(key, default):
        m = re.search(r'\["col\.' + key + r'"\]\s*=\s*(.*)', lua)
        c = css_color(m.group(1)) if m else None
        return c if c else (default, 1.0)
    return {
        'border_size': max(1, num('border_size', 2)),
        'rounding': num('rounding', 0),          # brak klucza = domyślne 0 Hyprlanda
        'active': col('active_border', accent),
        'inactive': col('inactive_border', (136, 136, 136)),
    }

# ─── płótno ──────────────────────────────────────────────────────────────────

class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[0.0, 0.0, 0.0] for _ in range(w * h)]

    def set(self, x, y, c):
        p = self.px[y * self.w + x]
        p[0], p[1], p[2] = c

    def blend(self, x, y, c, a):
        if a <= 0 or not (0 <= x < self.w and 0 <= y < self.h):
            return
        if a > 1:
            a = 1.0
        p = self.px[y * self.w + x]
        p[0] += (c[0] - p[0]) * a
        p[1] += (c[1] - p[1]) * a
        p[2] += (c[2] - p[2]) * a

    def rrect(self, x0, y0, x1, y1, r, fill=None, alpha=1.0, border=None, bw=0.0, balpha=1.0):
        """Prostokąt z zaokrągleniem r (SDF + 1 px antyaliasingu), opcjonalna
        ramka szerokości bw rysowana do środka — jak ramka okna Hyprlanda."""
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        hw, hh = (x1 - x0) / 2.0, (y1 - y0) / 2.0
        r = max(0.0, min(r, hw, hh))
        for y in range(max(0, int(y0) - 1), min(self.h, int(math.ceil(y1)) + 1)):
            qy = abs(y + 0.5 - cy) - (hh - r)
            for x in range(max(0, int(x0) - 1), min(self.w, int(math.ceil(x1)) + 1)):
                qx = abs(x + 0.5 - cx) - (hw - r)
                d = math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r
                cov = min(1.0, max(0.0, 0.5 - d))
                if cov <= 0:
                    continue
                if border is not None and bw > 0:
                    inner = min(1.0, max(0.0, 0.5 - (d + bw)))
                    if fill is not None:
                        self.blend(x, y, fill, alpha * inner)
                    self.blend(x, y, border, balpha * (cov - inner))
                elif fill is not None:
                    self.blend(x, y, fill, alpha * cov)

    def glow_dot(self, cx, cy, radius, sigma, c, weight):
        inv = -1.0 / (2.0 * sigma * sigma)
        for y in range(max(0, int(cy - radius)), min(self.h, int(cy + radius) + 1)):
            for x in range(max(0, int(cx - radius)), min(self.w, int(cx + radius) + 1)):
                d2 = (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2
                self.blend(x, y, c, weight * math.exp(d2 * inv))

    def png(self, path):
        raw = bytearray()
        for y in range(self.h):
            raw.append(0)
            for x in range(self.w):
                p = self.px[y * self.w + x]
                raw += bytes(max(0, min(255, int(v + 0.5))) for v in p)

        def chunk(tag, data):
            c = struct.pack('>I', len(data)) + tag + data
            return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

        data = (b'\x89PNG\r\n\x1a\n'
                + chunk(b'IHDR', struct.pack('>IIBBBBB', self.w, self.h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
                + chunk(b'IEND', b''))
        tmp = path + '.tmp'
        with open(tmp, 'wb') as f:
            f.write(data)
        os.replace(tmp, path)

# ─── motywy tła (tapeta rice'a w skrócie) ───────────────────────────────────

def bg_gradient(cv, top, bottom):
    for y in range(cv.h):
        c = mix(top, bottom, y / (cv.h - 1))
        for x in range(cv.w):
            cv.set(x, y, c)

def motif_arch(cv, pal):
    """Jasne tło, logo w stylu Arch (trójkąt z wcięciem) w akcencie."""
    bg, ink, acc = pal
    bg_gradient(cv, bg, mix(bg, acc, 0.10))
    cx, top, bot, half = MOTIF_CX, 80.0, 320.0, 104.0
    def inside(px, py):
        if py < top or py > bot:
            return False
        t = (py - top) / (bot - top)
        if abs(px - cx) > half * t:
            return False
        # wcięcie u dołu: odwrócony łuk-trójkąt
        if py > top + (bot - top) * 0.70:
            u = (py - (top + (bot - top) * 0.70)) / ((bot - top) * 0.30)
            if abs(px - cx) < half * 0.34 * math.sqrt(u):
                return False
        return True
    for y in range(int(top) - 1, int(bot) + 2):
        for x in range(int(cx - half) - 1, int(cx + half) + 2):
            n = sum(inside(x + (i + 0.5) / 3.0, y + (j + 0.5) / 3.0) for i in range(3) for j in range(3))
            cv.blend(x, y, acc, n / 9.0)

def motif_grid(cv, pal):
    """Tron: czarne tło, perspektywiczna siatka podłogi w akcencie (linie
    wzdłuż zbiegają się do punktu zbiegu, poprzeczne gęstnieją ku
    horyzontowi), poświata horyzontu."""
    bg, ink, acc = pal
    hy = 200.0
    bg_gradient(cv, bg, mix(bg, acc, 0.05))
    vx = MOTIF_CX
    s_along = 90.0 / (cv.h - hy)     # odstęp linii wzdłuż ≈ 90 px na dole kadru
    k_depth = (cv.h - hy) ** 2 / 26.0  # odstęp poprzecznych ≈ 26 px na dole
    for y in range(int(hy) + 1, cv.h):
        dy = y + 0.5 - hy
        fade = min(1.0, dy / (cv.h - hy)) ** 0.7
        z = k_depth / dy                              # głębokość wiersza
        dz = abs(z - round(z)) * dy * dy / k_depth    # odległość w px od poprzecznej
        # poprzeczne gęstsze niż co 4 px zlewają się w mory — wygaszamy je
        hz = min(1.0, (dy * dy / k_depth) / 4.0) ** 2
        for x in range(cv.w):
            X = (x + 0.5 - vx) / (dy * s_along)       # linie wzdłuż: proste przez punkt zbiegu
            dv = abs(X - round(X)) * dy * s_along     # odległość w px od linii wzdłuż
            a = max(0.0, 1.0 - dv, (1.0 - dz) * hz)
            if a > 0:
                cv.blend(x, y, acc, a * (0.25 + 0.75 * fade))
    for y in range(int(hy) - 24, int(hy) + 4):
        for x in range(cv.w):
            cv.blend(x, y, acc, 0.4 * math.exp(-abs(y + 0.5 - hy) / 6.0))

def motif_scope(cv, pal):
    """crt: granatowe szkło z winietą, podziałka, krzywa Lissajous 3:2."""
    bg, ink, acc = pal
    cx, cy = cv.w / 2.0, cv.h / 2.0
    for y in range(cv.h):
        for x in range(cv.w):
            r = math.hypot((x - cx) / cx, (y - cy) / cy)
            cv.set(x, y, mix(mix(bg, ink, 0.12), bg, min(1.0, r * 0.9)))
    cell = 30
    for y in range(cv.h):
        for x in range(cv.w):
            on = (abs((x - cx) % cell) < 0.6) or (abs((y - cy) % cell) < 0.6)
            axis = abs(x - cx) < 0.6 or abs(y - cy) < 0.6
            if axis:
                cv.blend(x, y, ink, 0.45)
            elif on:
                cv.blend(x, y, ink, 0.18)
    steps = 2600
    for i in range(steps):
        t = 2.0 * math.pi * i / steps
        x = MOTIF_CX + 118 * math.sin(3.0 * t + math.pi / 2.0)
        y = cy + 16 + 110 * math.sin(2.0 * t)
        cv.glow_dot(x, y, 2, 0.8, mix(acc, (255, 255, 255), 0.25), 0.35)
        if i % 4 == 0:
            cv.glow_dot(x, y, 9, 3.5, acc, 0.05)

BAYER8 = [
    [0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21],
]

def motif_dither(cv, pal):
    """dither-flux: pole przepływu skwantowane rastrem Bayera 8x8 (piksel 2x2)."""
    bg, ink, acc = pal
    levels = [bg, mix(bg, ink, 0.5), ink, acc]
    for y in range(0, cv.h, 2):
        for x in range(0, cv.w, 2):
            u, v = x / cv.w, y / cv.h
            f = (math.sin(u * 7.0 + math.sin(v * 5.0) * 1.8)
                 + math.sin(v * 9.0 - u * 3.0 + math.cos(u * 4.0) * 1.3)) * 0.25 + 0.5
            f = min(0.999, max(0.0, f * 0.95 * (0.55 + 0.45 * v)))
            k = f * (len(levels) - 1)
            base = int(k)
            thr = (BAYER8[(y // 2) % 8][(x // 2) % 8] + 0.5) / 64.0
            c = levels[min(len(levels) - 1, base + (1 if (k - base) > thr else 0))]
            for dy in (0, 1):
                for dx in (0, 1):
                    if x + dx < cv.w and y + dy < cv.h:
                        cv.set(x + dx, y + dy, c)

def motif_sun(cv, pal):
    """asia-n-rice: granatowy gradient, mauve słońce z pasami, pasmo gór."""
    bg, ink, acc = pal
    bg_gradient(cv, mix(bg, (0, 0, 0), 0.25), bg)
    cx, cy, r = MOTIF_CX, 180.0, 100.0
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            cov = min(1.0, max(0.0, r - d + 0.5))
            if cov <= 0:
                continue
            t = (y - (cy - r)) / (2 * r)
            if t > 0.55 and ((y - cy) % 16) < 3 + 5 * (t - 0.55):
                continue
            cv.blend(x, y, mix(acc, ink, t), cov)
    for x in range(cv.w):
        hgt = 300 + 22 * math.sin(x / 47.0) + 11 * math.sin(x / 13.0 + 1.3)
        for y in range(int(hgt), cv.h):
            cv.blend(x, y, mix(bg, (0, 0, 0), 0.35), 0.9)

def motif_flat(cv, pal):
    bg, ink, acc = pal
    bg_gradient(cv, bg, mix(bg, acc, 0.12))

MOTIF_FN = {'arch': motif_arch, 'grid': motif_grid, 'scope': motif_scope,
            'dither': motif_dither, 'sun': motif_sun}

# ─── makieta ─────────────────────────────────────────────────────────────────

def text_bar(cv, x, y, length, c, a=0.9, h=4):
    cv.rrect(x, y, x + length, y + h, h / 2.0, fill=c, alpha=a)

def render(rice, out_path):
    pal = flux_palette(rice)
    bg, ink, acc = pal
    term = alacritty_style(rice)
    hyp = hypr_style(rice, acc)
    bar = waybar_style(rice, term['bg'], term['fg'], acc)

    cv = Canvas(W, H)
    MOTIF_FN.get(MOTIFS.get(rice, ''), motif_flat)(cv, pal)

    # ── pasek: trzy wyspy (lewa: workspace'y, środek: zegar, prawa: moduły) ──
    (ib, ia) = bar['bg']
    brd = bar['border']
    rad = min(bar['radius'], 11.0)
    def island(x0, x1):
        cv.rrect(x0, 4, x1, 26, rad, fill=ib, alpha=ia,
                 border=brd[0] if brd else None, bw=1.0 if brd else 0.0, balpha=brd[1] if brd else 0.0)
    island(12, 196)
    for i in range(5):
        x = 20 + i * 24
        if i == 0:
            cv.rrect(x, 8, x + 20, 22, min(rad, 7.0), fill=bar['active'])
        else:
            text_bar(cv, x + 6, 13, 8, bar['fg'], 0.8)
    text_bar(cv, 142, 13, 46, bar['fg'], 0.45)
    island(282, 358)
    text_bar(cv, 294, 13, 52, bar['clock'], 0.95)
    island(452, 628)
    for i, ln in enumerate((22, 30, 18, 36, 26)):
        text_bar(cv, 462 + sum((22, 30, 18, 36, 26)[:i]) + i * 8, 13, ln, bar['fg'], 0.8)

    # ── okno: jeden terminal na lewej połowie (prawa połowa = tapeta) ────────
    bs, rr = hyp['border_size'], hyp['rounding']
    ac, aa = hyp['active']
    cv.rrect(12, 32, 336, 348, rr, fill=term['bg'], alpha=term['opacity'],
             border=ac, bw=bs, balpha=aa)

    # prompt, kilka linii wyjścia, próbki ANSI (normal + bright), paleta
    # flux-wall (bg, ink, accent), prompt z kursorem
    fg = term['fg']
    x0 = 26
    def prompt(y):
        text_bar(cv, x0, y, 52, term['normal'][2], 0.95)
        text_bar(cv, x0 + 58, y, 34, term['normal'][4], 0.95)
    prompt(48)
    text_bar(cv, x0 + 98, 48, 80, fg, 0.9)
    seed = sum(map(ord, rice))
    for i in range(6):
        ln = 70 + ((seed * (i + 3) * 37) % 200)
        text_bar(cv, x0, 64 + i * 12, ln, fg, 0.55 if i % 3 else 0.8)
    sw, gap = 34, 3
    for row, cols in enumerate((term['normal'], term['bright'])):
        for i, c in enumerate(cols):
            cv.rrect(x0 + i * (sw + gap), 144 + row * 22, x0 + i * (sw + gap) + sw, 162 + row * 22,
                     min(3.0, rr), fill=c)
    for i in range(3):
        ln = 60 + ((seed * (i + 11) * 53) % 200)
        text_bar(cv, x0, 202 + i * 12, ln, term['normal'][(i % 6) + 1] if i % 2 else fg, 0.75)
    pw = (8 * (sw + gap) - gap - 2 * 6) / 3.0
    for i, c in enumerate(pal):
        cv.rrect(x0 + i * (pw + 6), 246, x0 + i * (pw + 6) + pw, 290, min(4.0, rr), fill=c,
                 border=mix(c, fg, 0.35), bw=1.0)
    prompt(310)
    cv.rrect(x0 + 98, 306, x0 + 106, 318, 0, fill=term['cursor'])

    cv.png(out_path)

def stub_rices():
    d = os.path.join(REPO, 'scripts', 'changing-theme-scripts')
    out = []
    for name in sorted(os.listdir(d)):
        if name.endswith('.sh'):
            m = re.search(r'^RICE_NAME="?([^"\s]+)"?\s*$', read(os.path.join(d, name)), re.M)
            if m and m.group(1) not in out:
                out.append(m.group(1))
    return out

def main(argv):
    out = None
    if '--out' in argv:
        i = argv.index('--out')
        out = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    rices = argv or stub_rices()
    if out and len(rices) != 1:
        sys.exit('gen_rice_preview.py: --out tylko z jednym rice')
    for rice in rices:
        if not os.path.isdir(os.path.join(REPO, 'rices', rice)):
            sys.exit('gen_rice_preview.py: brak rices/%s' % rice)
        path = out or os.path.join(REPO, 'rices', rice, 'preview.png')
        render(rice, path)
        print('%s → %s' % (rice, os.path.relpath(path, REPO)))

if __name__ == '__main__':
    main(sys.argv[1:])
