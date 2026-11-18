#version 300 es
/*
 * archenemy — flux-wall: shader tapety rice'a dither-flux.
 *
 * Generatywne pole ciągłe (domain warping na szumie wartościowym) kwantyzowane
 * macierzą Bayera 8x8 do trzech kolorów palety. Ta sama matematyka co w
 * scripts/wallpapers/gen_dither_flux_wallpaper.py, tylko liczona na GPU
 * w każdej klatce — bez pliku obrazu, bez wideo, bez pętli.
 *
 * Uniformy (kontrakt flux-wall):
 *   resolution      rozmiar powierzchni w pikselach fizycznych
 *   time            sekundy od startu
 *   palette_bg/ink/accent   trzy kolory rice'a (0..1)
 *   detail          0..1 — szczegółowość (bateria): liczba oktaw i prędkość
 */
precision highp float;
precision highp sampler2D;   /* domyślnie lowp — texelFetch z akumulatora/widma byłby zaokrąglany tam, gdzie sterownik honoruje precyzję (Mesa) */

uniform vec2  resolution;
uniform float time;
uniform vec3  palette_bg;
uniform vec3  palette_ink;
uniform vec3  palette_accent;
uniform float dither;   /* 1 = raster Bayera, 0 = gładki gradient palety (engine.h) */
uniform float detail;

out vec4 fragColor;

/* Tonowanie jak w generatorze PNG: gamma ściąga półtony w dół, level ogranicza
 * maksymalne krycie — tapeta ma być tłem dla ikon, nie konkurencją. */
const float LEVEL    = 0.62;
const float GAMMA    = 1.9;
const float ACC_FROM = 0.80;   /* próg pasma akcentu jako ułamek maksimum */
const float ACC_SOFT = 0.10;   /* tryb gładki: szerokość przejścia atrament → akcent nad progiem (część LEVEL) */

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i), b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/* Liczba oktaw zależy od `detail`: 1.0 → 4 oktawy, 0.0 → 1 oktawa.
 * Mniej oktaw = mniej pracy GPU = mniej szczegółów. To jest mechanizm
 * baterii: estetyka i oszczędzanie w jednym miejscu. */
float fbm(vec2 p, int octaves) {
    float v = 0.0, a = 0.5, norm = 0.0;
    for (int i = 0; i < 4; i++) {
        if (i >= octaves) break;
        v += a * vnoise(p);
        norm += a;
        p *= 2.0;
        a *= 0.5;
    }
    return v / norm;
}

/* Macierz Bayera 8x8 proceduralnie: przeplot bitów y oraz (x^y), potem
 * odwrócenie kolejności 6 bitów. Zweryfikowana bit po bicie względem macierzy
 * rekurencyjnej z generatora PNG — pierwsza, „oczywista" wersja dawała klastry
 * sąsiednich wartości (widoczne kwadraty 2x2 zamiast rozproszonego ziarna). */
float bayer8(vec2 c) {
    ivec2 p = ivec2(mod(c, 8.0));
    int xc = p.x ^ p.y;
    int v = 0;
    for (int i = 0; i < 3; i++) {
        int a = (xc >> i) & 1;
        int b = (p.y >> i) & 1;
        v |= ((b << 1) | a) << (2 * i);
    }
    int r = 0;
    for (int i = 0; i < 6; i++)
        r = (r << 1) | ((v >> i) & 1);
    return (float(r) + 0.5) / 64.0;
}

/* Tryb gładki (dither = 0): kolor, który raster daje z daleka, ale bez
 * rastra — ton `f` (ułamek zapalonych pikseli w rastrze) jako krycie koloru
 * „zapalonego” na tle, a `acc` (0..1) przesuwa ten kolor z atramentu
 * w akcent. Gradient palety tło → atrament → akcent, ciągły. */
vec3 palette_ramp(float f, float acc) {
    vec3 lit = mix(palette_ink, palette_accent, clamp(acc, 0.0, 1.0));
    return mix(palette_bg, lit, clamp(f, 0.0, 1.0));
}

void main() {
    /* Współrzędne w jednostkach wysokości ekranu — ta sama skala formy na
     * 1920x1080 i 2560x1600, raster zawsze 1 px. */
    vec2 uv = gl_FragCoord.xy / resolution.y;

    int   octaves = int(clamp(floor(1.0 + detail * 3.0 + 0.001), 1.0, 4.0));
    float speed   = 0.02 + 0.04 * detail;        /* przy niskiej baterii wolniej */
    float t       = time * speed;

    /* Domain warping: szum zniekształcony samym sobą; `t` przesuwa domenę,
     * więc pole dryfuje bez końca i nigdy się nie powtarza. */
    vec2  q = vec2(fbm(uv * 2.4 + t, octaves), fbm(uv * 2.4 + vec2(5.2, 1.3) - t, octaves));
    float r = fbm(uv * 2.4 + 4.0 * q + vec2(1.7, 9.2), octaves);
    float f = fbm(uv * 2.4 + 4.0 * vec2(r), octaves);

    /* Winieta jak w generatorze: rogi ciemniejsze, środek nośny. */
    vec2 c = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
    f *= max(0.0, 1.0 - 0.25 * dot(c, c));

    f = pow(clamp(f, 0.0, 1.0), GAMMA) * LEVEL;

    vec3 col = palette_bg;
    if (dither > 0.5) {
        if (f > bayer8(gl_FragCoord.xy))
            col = (f >= ACC_FROM * LEVEL) ? palette_accent : palette_ink;
    } else {
        col = palette_ramp(f, smoothstep(ACC_FROM * LEVEL, (ACC_FROM + ACC_SOFT) * LEVEL, f));
    }
    fragColor = vec4(col, 1.0);
}
