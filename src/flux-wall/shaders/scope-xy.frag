#version 300 es
/*
 * archenemy — flux-wall: „scope-xy” — oscyloskop XY (Lissajous), przebieg finalny.
 *
 * Akumulator z kroku cząstek (ślad plamki z fosforowym ogonem) tonowany
 * logarytmicznie i kwantyzowany rastrem Bayera: rdzeń w akcencie, ogon
 * w atramencie. Pod spodem podziałka oscyloskopu (siatka + osie), jak
 * w tapecie crt-scope i w scope.
 *   level → wzmocnienie śladu (gain), beat → rozbłysk, high → iskrzenie rastra.
 * W ciszy: punkt w środku ekranu na podziałce.
 *
 * Uniformy: kontrakt flux-wall + accum/gain + audio_* (engine.h).
 */
precision highp float;
precision highp sampler2D;

uniform vec2      resolution;
uniform float     time;
uniform vec3      palette_bg;
uniform vec3      palette_ink;
uniform vec3      palette_accent;
uniform float     dither;   /* 1 = raster Bayera, 0 = gładki gradient palety (engine.h) */
uniform float     detail;
uniform sampler2D accum;
uniform float     gain;
uniform float     audio_level;
uniform float     audio_high;
uniform float     audio_beat;

out vec4 fragColor;

const float LEVEL    = 0.62;
const float GAMMA    = 1.6;
const float ACC_FROM = 0.70;     /* powyżej tej części tonu — akcent (rdzeń śladu) */
const float ACC_SOFT = 0.10;     /* tryb gładki: szerokość przejścia atrament → akcent nad progiem (część tonu) */
const float CELLS    = 10.0;

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
    vec2 px = gl_FragCoord.xy;

    /* podziałka */
    float cell = resolution.y / CELLS;
    vec2 g = mod(px - resolution * 0.5, cell);
    float line = min(min(g.x, cell - g.x), min(g.y, cell - g.y));
    bool axis = abs(px.x - resolution.x * 0.5) < 0.6 || abs(px.y - resolution.y * 0.5) < 0.6;
    float f = axis ? LEVEL * 0.34 : (line < 0.5 ? LEVEL * 0.22 : 0.0);
    if (audio_beat > 0.02) f *= 1.0 + 0.6 * audio_beat;

    /* ślad z akumulatora */
    float a = texelFetch(accum, ivec2(px), 0).r;
    float ga = gain * (1.0 + 0.8 * audio_level + 0.8 * audio_beat);
    float t = log(1.0 + a * ga) / log(1.0 + ga);
    t = pow(clamp(t, 0.0, 1.0), GAMMA);
    bool accent = t > ACC_FROM;
    f = max(f, LEVEL * t);

    vec2 bshift = floor(vec2(3.0, 5.0) * audio_high);
    vec3 col = palette_bg;
    if (dither > 0.5) {
        if (f > bayer8(px + bshift))
            col = accent ? palette_accent : palette_ink;
    } else {
        col = palette_ramp(f, smoothstep(ACC_FROM, ACC_FROM + ACC_SOFT, t));
    }
    fragColor = vec4(col, 1.0);
}
