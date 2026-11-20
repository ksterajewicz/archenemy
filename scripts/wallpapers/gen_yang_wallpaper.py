#!/usr/bin/env python3
"""
archenemy — matematyczny generator tapety „zaćmienie w negatywie" (rice yang).
Zero zależności (wzorzec gen_yin_wallpaper.py): PNG pisany przez zlib/struct.
Obraz jest w całości liczony z wzorów poniżej — żadnych cudzych grafik,
więc może leżeć w publicznym repo (licencja repo).

Obraz = negatyw tapety yin: jasne tło („papier") z miękką winietą, która
w rogach kadru wybiela się jeszcze bardziej (negatyw ciemnych rogów yin),
po prawej stronie kadru jasna tarcza „zaćmienia" (bielsza od tła), którą od
lewej góry obrysowuje cienki ciemny rant cienia i szeroka, słaba szara
poświata. Gładkie przejścia, bez rastra, bez ziarna — rice yang to jasne
matowe szkło nad tą tapetą, nie dither. Jedyny „szum" to ±½ poziomu
jasności przy zaokrąglaniu (losowe zaokrąglenie), niewidoczny gołym okiem;
bez niego jasny gradient w 8 bitach rozpada się na prążki.

Ciemność jest ograniczona z dołu: najciemniejszy piksel rantu to #6E6E73
(poziom 110), a szeroka poświata przyciemnia tło najwyżej o ~20 poziomów —
od tego zależy kontrast ciemnego tekstu na półprzezroczystym jasnym szkle
alacritty/waybara (rachunek w README, sekcja yang).

Paleta rice'a yang: papier #F3F3F5 (tło), mleko #EDEDF0 / #E1E1E5 płyty,
popiół #5E5E66, tusz #1E1E22 (tekst), czerń #0C0C0E jako akcent.

Użycie: gen_yang_wallpaper.py [KATALOG]   (domyślnie wallpapers/yang)
"""
import math
import os
import struct
import sys
import zlib

# Jasności liczone jako JEDEN kanał (poziom 0–255), kolor nadaje paleta PNG
# (typ 3): poziom k → chłodna szarość jak w yin. Najwyżej 256 kolorów, więc
# obraz zapisany indeksami waży ułamek truecolora, a każdy dekoder PNG
# (hyprpaper, hyprlock, rofi) rozwija paletę sam.
PAPER = 243.0              # #F3F3F5 — tło rice'a
EDGE  = 250.0              # winieta w rogach kadru (negatyw: bielej)
DISC  = 251.0              # wnętrze tarczy (bielsze od tła)
RIM   = 110.0              # #6E6E73 — rdzeń rantu (najciemniejsze miejsce tapety)
SHADE = 100.0              # siła szerokiej szarej poświaty (odejmowana)


def palette_rgb(k):
    """Poziom jasności → kolor: neutralna szarość z odrobiną chłodu (+2…+7 w B)."""
    return (k, k, min(255, k + 2 + round((255 - k) * 0.02)))


def render(width, height, out_path, seed=0x59414E47):
    h = float(height)
    cx, cy = width * 0.66, height * 0.47     # środek tarczy (jak yin)
    rad = h * 0.30                           # promień tarczy
    core_w = h * 0.0032                      # szerokość rantu (~3,5 px przy 1080)
    glow_w = h * 0.055                       # zasięg poświaty
    bloom_w = h * 0.22                       # bardzo szeroka, bardzo słaba aureola
    light = math.radians(225.0)              # skąd pada światło: lewa góra (oś y w dół)
    lx, ly = math.cos(light), math.sin(light)

    state = seed & 0xFFFFFFFF
    rows = []
    for y in range(height):
        row = bytearray(b'\x00')             # filtr PNG 0 (None) na początku wiersza
        py = (y + 0.5 - cy)
        vy = (y + 0.5) / h - 0.5
        for x in range(width):
            px = (x + 0.5 - cx)
            r = math.hypot(px, py)
            d = r - rad                      # >0 na zewnątrz tarczy

            # ── tło: miękka winieta, w rogach odrobinę bielej ──
            vx = (x + 0.5) / width - 0.5
            v = min(1.0, (vx * vx * 1.6 + vy * vy * 2.2) * 1.4)
            t = v * v * (3.0 - 2.0 * v)      # smoothstep — bez widocznej granicy
            c = PAPER + (EDGE - PAPER) * t

            # ── kierunek światła: rant najciemniejszy od lewej góry ──
            if r > 0.0:
                cosang = (px * lx + py * ly) / r
            else:
                cosang = 0.0
            lit = (0.5 + 0.5 * cosang)
            lit = 0.05 + 0.95 * lit * lit * lit  # druga strona ma ślad rantu

            if d < 0.0:
                # wnętrze tarczy: płynnie od tła do bielszego (1,5 % promienia)
                k = min(1.0, -d / (rad * 0.015))
                c += (DISC - c) * k
                core = math.exp(-(d / (core_w * 0.6)) ** 2) * lit
                glow = 0.0
            else:
                core = math.exp(-(d / core_w) ** 2) * lit
                glow = (0.17 * math.exp(-d / glow_w) + 0.035 * math.exp(-d / bloom_w)) * lit

            # poświata odejmowana (negatyw addytywnej korony yin),
            # rant jako przenikanie do koloru rdzenia
            c -= SHADE * glow
            c += (RIM - c) * core

            # losowe zaokrąglenie ±½ poziomu (xorshift32, deterministyczny)
            state ^= (state << 13) & 0xFFFFFFFF
            state ^= state >> 17
            state ^= (state << 5) & 0xFFFFFFFF
            n = (state & 0xFFFF) / 65536.0
            row.append(max(0, min(255, int(c + n))))
        rows.append(bytes(row))

    raw = b''.join(rows)

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 3, 0, 0, 0))
           + chunk(b'PLTE', b''.join(bytes(palette_rgb(k)) for k in range(256)))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    with open(out_path, 'wb') as f:
        f.write(png)
    print(f'✓ {out_path} ({width}x{height}, {len(png) // 1024} KiB)')


if __name__ == '__main__':
    out_dir = sys.argv[1] if len(sys.argv) > 1 else 'wallpapers/yang'
    os.makedirs(out_dir, exist_ok=True)
    # konwencja przełącznika tapet: v1 = monitor główny, v2 = dodatkowy
    render(1920, 1080, f'{out_dir}/yang-eclipse-v1-1920x1080.png')
    render(2560, 1600, f'{out_dir}/yang-eclipse-v2-2560x1600.png')
