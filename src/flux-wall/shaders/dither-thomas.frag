#version 300 es
/*
 * archenemy — flux-wall: „dither-thomas” — przebieg finalny (atraktor Thomasa).
 *
 * Krok cząstek jest w dither-thomas.update.glsl; tu akumulator śladów (`accum`,
 * jeden kanał) przechodzi to, co w generatorze PNG robią log1p → normalize →
 * winieta → tone → dither: log-tonowanie z `gain`, winieta 0.30, gamma/level
 * jak w pozostałych animacjach, macierz Bayera 8x8 do trzech kolorów palety.
 *
 * Uniformy: kontrakt flux-wall (resolution, time, palette_*, detail)
 *           + accum (sampler2D), gain — tryb cząstkowy (engine.h).
 */
precision highp float;
precision highp sampler2D;   /* domyślnie lowp — texelFetch z akumulatora/widma byłby zaokrąglany tam, gdzie sterownik honoruje precyzję (Mesa) */

uniform vec2      resolution;
uniform float     time;
uniform vec3      palette_bg;
uniform vec3      palette_ink;
uniform vec3      palette_accent;
uniform float     dither;   /* 1 = raster Bayera, 0 = gładki gradient palety (engine.h) */
uniform float     detail;
uniform sampler2D accum;
uniform float     gain;

out vec4 fragColor;

const float LEVEL    = 0.62;
const float GAMMA    = 1.9;
const float ACC_FROM = 0.80;
const float ACC_SOFT = 0.10;   /* tryb gładki: szerokość przejścia atrament → akcent nad progiem (część LEVEL) */
const float VIGNETTE = 0.30;

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
    float a = texelFetch(accum, ivec2(gl_FragCoord.xy), 0).r;
    float f = log(1.0 + a * gain) / log(1.0 + gain);

    vec2 c = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
    f *= max(0.0, 1.0 - VIGNETTE * dot(c, c));
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
