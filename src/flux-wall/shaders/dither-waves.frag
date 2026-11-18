#version 300 es
/*
 * archenemy — flux-wall: „fale” — interferencja fal kołowych.
 *
 * Sześć źródeł fal o różnych długościach i fazach; suma sinusów daje prążki
 * mory, a obwiednia fBm wycisza część kadru, żeby prążki nie pokrywały go
 * równomiernie. Fale PŁYNĄ od źródeł (faza rośnie z czasem). Ten sam silnik
 * co w przeglądzie form z 2026-09-07 (wariant „interferencja”), liczony na GPU.
 *
 * Uniformy: kontrakt flux-wall (resolution, time, palette_*, detail).
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

const float LEVEL    = 0.60;
const float GAMMA    = 1.9;
const float ACC_FROM = 0.84;
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

/* Tryb gładki (dither = 0): kolor, który raster daje z daleka, ale bez
 * rastra — ton `f` (ułamek zapalonych pikseli w rastrze) jako krycie koloru
 * „zapalonego” na tle, a `acc` (0..1) przesuwa ten kolor z atramentu
 * w akcent. Gradient palety tło → atrament → akcent, ciągły. */
vec3 palette_ramp(float f, float acc) {
    vec3 lit = mix(palette_ink, palette_accent, clamp(acc, 0.0, 1.0));
    return mix(palette_bg, lit, clamp(f, 0.0, 1.0));
}

void main() {
    /* Współrzędne w pikselach, ale długości fal w jednostkach wysokości ekranu —
     * ta sama gęstość prążków na 1080p i 1600p. */
    vec2  px    = gl_FragCoord.xy;
    float unit  = resolution.y / 540.0;          /* 1 „piksel odniesienia” */
    int   octaves = int(clamp(floor(1.0 + detail * 2.0 + 0.001), 1.0, 3.0));
    float speed = 0.6 + 1.4 * detail;            /* przy niskiej baterii wolniej */

    float s = 0.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        /* źródła rozrzucone deterministycznie, część poza kadrem */
        vec2 src = vec2(hash(vec2(fi, 1.7)) * 1.4 - 0.2,
                        hash(vec2(fi, 9.3)) * 1.4 - 0.2) * resolution;
        float wavelength = (14.0 + 22.0 * hash(vec2(fi, 4.1))) * unit;
        float phase = hash(vec2(fi, 6.6)) * 6.2831853;
        float d = distance(px, src) / wavelength;
        s += sin(d * 6.2831853 + phase - time * speed);
    }
    float env = fbm(px / (170.0 * unit), octaves);       /* gdzie fale „są” */
    float f = (0.5 + s / 12.0) * (0.25 + 0.75 * env);

    vec2 c = (px / resolution) * 2.0 - 1.0;
    f *= max(0.0, 1.0 - 0.35 * dot(c, c));

    f = pow(clamp(f, 0.0, 1.0), GAMMA) * LEVEL;

    vec3 col = palette_bg;
    if (dither > 0.5) {
        if (f > bayer8(px))
            col = (f >= ACC_FROM * LEVEL) ? palette_accent : palette_ink;
    } else {
        col = palette_ramp(f, smoothstep(ACC_FROM * LEVEL, (ACC_FROM + ACC_SOFT) * LEVEL, f));
    }
    fragColor = vec4(col, 1.0);
}
