#version 300 es
/*
 * archenemy — flux-wall: „ziarno” — kompozycja stoi, wędruje sam raster.
 *
 * Pole (domain warping) jest STATYCZNE; animowane jest wyłącznie przesunięcie
 * macierzy Bayera, skokowo, kilkanaście razy na sekundę. Obraz trwa, rusza
 * się jego materiał — efekt „żywego ekranu” starego komputera. To wariant A
 * z porównania ruchów 2026-09-07 (ruch-A-ziarno.gif), tylko bez pętli.
 *
 * Uniformy: kontrakt flux-wall (resolution, time, palette_*, detail).
 */
precision highp float;

uniform vec2  resolution;
uniform float time;
uniform vec3  palette_bg;
uniform vec3  palette_ink;
uniform vec3  palette_accent;
uniform float detail;

out vec4 fragColor;

const float LEVEL    = 0.62;
const float GAMMA    = 1.9;
const float ACC_FROM = 0.80;

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

void main() {
    vec2 uv = gl_FragCoord.xy / resolution.y;
    int   octaves = int(clamp(floor(1.0 + detail * 3.0 + 0.001), 1.0, 4.0));
    /* Tempo wędrówki ziarna: 12 kroków/s przy pełnej baterii, 4 przy pustej —
     * skokowo (floor), bo raster ma tykać, nie płynąć. */
    float steps = floor(time * (4.0 + 8.0 * detail));

    vec2  q = vec2(fbm(uv * 2.4, octaves), fbm(uv * 2.4 + vec2(5.2, 1.3), octaves));
    float r = fbm(uv * 2.4 + 4.0 * q + vec2(1.7, 9.2), octaves);
    float f = fbm(uv * 2.4 + 4.0 * vec2(r), octaves);

    vec2 c = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
    f *= max(0.0, 1.0 - 0.25 * dot(c, c));
    f = pow(clamp(f, 0.0, 1.0), GAMMA) * LEVEL;

    /* Przesunięcie macierzy po przekątnej (3,5) — pełny obieg co 8 kroków. */
    vec2 shift = vec2(mod(steps * 3.0, 8.0), mod(steps * 5.0, 8.0));

    vec3 col = palette_bg;
    if (f > bayer8(gl_FragCoord.xy + shift))
        col = (f >= ACC_FROM * LEVEL) ? palette_accent : palette_ink;
    fragColor = vec4(col, 1.0);
}
