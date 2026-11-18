#!/usr/bin/env python3
"""archenemy — flux-wall: statystyka stempli akumulatora z klatki PNG.

Narzędzie testowe (tests/flux-wall-bars.sh). Czysty Python (dekoder PNG na
zlib — bez PIL/numpy/ImageMagick, których nie ma w kontenerze i nie wolno ich
wymagać od użytkownika).

Tryby:
  pngstat.py marks <klatka.png> [tol]   klatka z PRAWDZIWEGO bars.frag: liczy
      KRESKI SZCZYTU per połowa ekranu — wiersz, w którym ≥30% pikseli
      szczeliny słupka jest w akcencie (raster Bayera), a wiersz pod nim to
      ≥90% tło (dolna krawędź kreski wiszącej nad słupkiem; końcówka słupka
      ma pod sobą ciało słupka, nie tło).
      Na klatce sprzed poprawki prawa połowa daje 0 (regresja 2026-09-21).
  pngstat.py accum <klatka.png> [tol]   klatka z tools/bars-accum-debug.frag:
      piksele akcentu w paśmie xc±1 per połowa (surowe stemple akumulatora)
      + informacyjnie xc±2.
Kod 0 = obie połowy niezerowe i w proporcji tol..1/tol (domyślnie 0.5).
"""
import struct
import sys
import zlib
from collections import Counter


def read_png(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n', 'nie PNG'
    p, idat, W, H, ct = 8, b'', 0, 0, 0
    while p < len(d):
        n, = struct.unpack('>I', d[p:p + 4])
        t, c = d[p + 4:p + 8], d[p + 8:p + 8 + n]
        p += 12 + n
        if t == b'IHDR':
            W, H, bd, ct = struct.unpack('>IIBB', c[:10])
            assert bd == 8, 'tylko 8 bitów na kanał'
        elif t == b'IDAT':
            idat += c
    bpp = {2: 3, 6: 4, 0: 1}[ct]
    raw = zlib.decompress(idat)
    stride = W * bpp
    out, prev, q = bytearray(), bytearray(stride), 0
    for _ in range(H):
        f = raw[q]
        line = bytearray(raw[q + 1:q + 1 + stride])
        q += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out += line
        prev = line
    return W, H, bpp, bytes(out)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ('marks', 'accum'):
        print(__doc__)
        return 2
    mode, path = sys.argv[1], sys.argv[2]
    tol = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
    W, H, bpp, b = read_png(path)

    def px(x, y):
        k = (y * W + x) * bpp
        return b[k:k + 3]

    # trzy kolory palety: tło (najczęstszy), atrament, akcent (najrzadszy z trzech)
    cols = Counter(px(x, y) for y in range(0, H, 7) for x in range(0, W, 3))
    bg = cols.most_common(1)[0][0]
    acc = cols.most_common(3)[2][0]
    sw = W / 64.0
    y_base = int(H * 0.12)          # jak BASE_FRAC w bars.frag
    top = H - y_base                # wiersz obrazu linii bazowej (PNG: y=0 u góry)

    def slot(i):
        x0, x1 = int(i * sw), int((i + 1) * sw)
        gap = max(int((x1 - x0) * 0.3 * 0.5), 1)   # (1 - BAR_FILL) / 2
        return x0 + gap, x1 - gap, (x0 + x1) // 2

    left = right = 0
    extra = [0, 0]
    for i in range(64):
        a, z, xc = slot(i)
        half = 1 if i >= 32 else 0
        if mode == 'marks':
            n = z - a
            for y in range(1, top - 2):
                # raster Bayera: kreska to ~połowa pikseli szczeliny w akcencie,
                # a wiersz pod nią prawie sam tło (pod końcówką słupka jest ciało
                # słupka — atrament w ~50-80% pikseli, więc odpada)
                acc_frac = sum(1 for x in range(a, z) if px(x, y) == acc) / n
                # dwa wiersze tła pod spodem (MARK_GAP = 2): ciemna linia
                # segmentu w ciele słupka (SEG_PX) ma pod sobą tylko JEDEN
                # ciemny wiersz, a niżej znów ciało słupka
                nonbg_below = max(sum(1 for x in range(a, z) if px(x, y + k) != bg) for k in (1, 2)) / n
                if acc_frac >= 0.3 and nonbg_below <= 0.1:
                    if half: right += 1
                    else: left += 1
        else:
            for y in range(0, top - 2):
                for dx in range(-2, 3):
                    if px(xc + dx, y) == acc:
                        if abs(dx) <= 1:
                            if half: right += 1
                            else: left += 1
                        else:
                            extra[half] += 1
    what = 'kreski szczytu (dolne krawedzie)' if mode == 'marks' else 'stemple w pasmie xc+-1'
    info = '' if mode == 'marks' else f'; akcent w xc+-2: {extra}'
    print(f'{what}: lewa {left}, prawa {right}{info}')
    ok = left > 0 and right > 0 and tol <= right / left <= 1.0 / tol
    print('OK' if ok else 'BLAD: asymetria polow (regresja 2026-09-21: prawa polowa bez kresek)')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
