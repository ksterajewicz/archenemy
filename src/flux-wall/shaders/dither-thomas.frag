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

uniform vec2      resolution;
uniform float     time;
uniform vec3      palette_bg;
uniform vec3      palette_ink;
uniform vec3      palette_accent;
uniform float     detail;
uniform sampler2D accum;
uniform float     gain;
uniform float     audio_high;     /* dźwięk: wysokie 0..1 (iskrzenie rastra) */
uniform float     audio_bass;     /* dźwięk: bas 0..1 */

out vec4 fragColor;

const float LEVEL    = 0.62;
const float GAMMA    = 1.9;
const float ACC_FROM = 0.80;
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

void main() {
    float a = texelFetch(accum, ivec2(gl_FragCoord.xy), 0).r;
    float f = log(1.0 + a * gain) / log(1.0 + gain);

    vec2 c = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
    f *= max(0.0, 1.0 - VIGNETTE * dot(c, c));
    f = pow(clamp(f, 0.0, 1.0), GAMMA) * LEVEL;

    /* Iskrzenie z wysokich: macierz Bayera przesuwa się o high·(3,5) px, a próg
     * akcentu spada o 0.15·high — hi-hat rozsypuje pianę po rastrze. Przy 0 = jak dotąd. */
    vec2  bshift  = floor(vec2(3.0, 5.0) * audio_high);
    float acc_cut = ACC_FROM - 0.15 * audio_high;
    vec3 col = palette_bg;
    if (f > bayer8(gl_FragCoord.xy + bshift))
        col = (f >= acc_cut * LEVEL) ? palette_accent : palette_ink;
    fragColor = vec4(col, 1.0);
}
