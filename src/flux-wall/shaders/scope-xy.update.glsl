/*
 * archenemy — flux-wall: „scope-xy” — oscyloskop w trybie XY, krok cząstki.
 *
 * Tryb XY prawdziwego oscyloskopu: x = kanał lewy, y = kanał prawy — muzyka
 * rysuje figury Lissajous („oscilloscope music”). Każda cząstka to jeden
 * punkt przebiegu: 1024 próbki × 8 podpunktów interpolowanych liniowo między
 * sąsiednimi próbkami (8192 cząstek), więc ślad jest ciągły także tam, gdzie
 * plamka leci szybko. Co krok WSZYSTKIE cząstki przeskakują na bieżący
 * przebieg, a akumulator (life 0,25 s) daje fosforowy ogon — jasne tam,
 * gdzie plamka zwalnia, blade tam, gdzie pędzi, jak na lampie.
 * W ciszy: wszystkie próbki ≈ 0 → świecący punkt w środku ekranu.
 *
 * Stan: xy = pozycja w 0..1 ekranu, z = wiek (zawsze > warm → widoczna), w = 0.
 */
#pragma flux audio 1
#pragma flux particles 8192
#pragma flux life 0.25
#pragma flux rate 60
#pragma flux inc 0.35
#pragma flux gain 6
#pragma flux splat 0
#pragma flux warm 0
#pragma flux seed 2050

const int   WAVE_N = 1024;
const int   SUB    = 8;          /* podpunktów między próbkami */
const float AMP    = 0.42;       /* część połowy wysokości ekranu przy pełnym wychyleniu */
const float GAIN_MAX = 8.0;      /* sufit auto-wzmocnienia */

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    int P = textureSize(pos, 0).x;
    int n = idx.y * P + idx.x;
    int i = n / SUB;
    float fr = float(n - i * SUB) / float(SUB);
    if (i >= WAVE_N) { o = vec4(-1.0, -1.0, 0.0, 0.0); return; }   /* nadmiarowe → poza ekranem */
    vec2 a = texelFetch(audio_wave, ivec2(i, 0), 0).rg;
    vec2 b = texelFetch(audio_wave, ivec2(min(i + 1, WAVE_N - 1), 0), 0).rg;
    vec2 s = mix(a, b, fr);                                  /* (L, R) w -1..1 */
    /* auto-wzmocnienie jak pokrętło V/div: szczyt okna (liczony w C) → figura
     * wypełnia ekran niezależnie od głośności, z sufitem dla bardzo cichych */
    float g = audio_wave_peak > 1e-4 ? clamp(1.0 / audio_wave_peak, 1.0, GAIN_MAX) : 1.0;
    s = clamp(s * g, -1.0, 1.0);
    /* jednostki ekranu: pion ±1 = pełna wysokość/2, poziom skalowany przez aspekt */
    vec2 p = vec2(0.5) + vec2(s.x * AMP / aspect, s.y * AMP);
    o = vec4(p, 1.0, 0.0);
}
