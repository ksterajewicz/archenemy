#version 300 es
/*
 * archenemy — flux-wall: „rings” — koncentryczne pierścienie z uderzeń, przebieg finalny.
 *
 * Obraz w trzech kolorach palety i rastrze Bayera 8×8:
 *   1. pierścienie z akumulatora (krok w rings.update.glsl): tone
 *      logarytmiczny jak w orb; front pierścienia jasny (akcent), smuga
 *      fosforu za nim gaśnie w atramencie,
 *   2. źródło: mała, nieruchoma tarczka w środku — obrys w akcencie, wnętrze
 *      w atramencie, którego gęstość rastra pulsuje z basem; wokół słaba
 *      poświata (rastrowana), żeby środek żył także w ciszy,
 *   3. iskrzenie rastra z wysokich: przesunięcie macierzy Bayera + losowe
 *      przeskoki pikseli pierścieni do akcentu.
 * Bas/środek/beat kształtują pierścienie już w kroku cząstek (grubość, jasność,
 * falowanie obwodu, wystrzał). W ciszy: tarczka, poświata i co ~3 s słaby
 * pierścień oddechu z akumulatora.
 *
 * Uniformy: kontrakt flux-wall + accum/gain + audio_* (engine.h).
 */
precision highp float;
precision highp sampler2D;   /* domyślnie lowp — texelFetch z akumulatora byłby zaokrąglany tam, gdzie sterownik honoruje precyzję (Mesa) */

uniform vec2      resolution;
uniform float     time;
uniform vec3      palette_bg;
uniform vec3      palette_ink;
uniform vec3      palette_accent;
uniform float     dither;   /* 1 = raster Bayera, 0 = gładki gradient palety (engine.h) */
uniform sampler2D accum;
uniform float     gain;
uniform float     audio_bass;
uniform float     audio_high;

out vec4 fragColor;

const float LEVEL    = 0.66;
const float GAMMA    = 1.20;     /* łagodniej niż orb: front pierścienia ma być czytelny, smuga gasnąć */
const float ACC_FROM = 0.70;     /* od tej części LEVEL piksel idzie w akcent (front pierścienia) */
const float ACC_SOFT = 0.10;   /* tryb gładki: szerokość przejścia atrament → akcent nad progiem (część LEVEL) */
const float SRC_R    = 0.07;     /* = SRC_R w .update.glsl */
const float SRC_EDGE = 0.012;    /* grubość obrysu źródła */
const float HALO     = 0.16;     /* jasność poświaty tuż przy źródle (część LEVEL) */
const float HALO_LEN = 0.14;     /* zasięg poświaty (jednostki c) */
const float SPARK    = 0.22;     /* udział pikseli pierścieni przeskakujących do akcentu przy pełnych wysokich */
const float R_NORM   = 0.45;     /* promień, przy którym wzmocnienie promieniowe = 1 */
const float RG_MIN   = 0.12;     /* wzmocnienie tuż przy źródle (pierścień jest tam ~10× gęstszy) */
const float RG_MAX   = 2.2;      /* wzmocnienie przy krawędzi (pierścień rzadki — punkty w akcencie) */

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

/* hash pikselowy do iskrzenia (zmienia się ~20 razy na sekundę) */
float hash_px(vec2 px, float t) {
    vec3 q = fract(vec3(px, t) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

void main() {
    /* współrzędne: środek 0, pion ±1, poziom ±aspekt */
    vec2  c = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
    c.x *= resolution.x / resolution.y;
    float r = length(c);

    /* 1. pierścienie z akumulatora; wzmocnienie promieniowe ~r wyrównuje gęstość
     *    cząstek 1/r: przy źródle pierścień nie zalewa środka, przy krawędzi
     *    rzadkie punkty jeszcze świecą */
    float a  = texelFetch(accum, ivec2(gl_FragCoord.xy), 0).r;
    float rg = clamp(r / R_NORM, RG_MIN, RG_MAX);
    float f  = log(1.0 + a * gain * rg) / log(1.0 + gain);
    f = pow(clamp(f, 0.0, 1.0), GAMMA) * LEVEL;
    bool accent = false;

    /* 2. poświata wokół źródła (oddycha powoli) i tarczka */
    float breath = 0.85 + 0.15 * sin(time * 1.1);
    float halo = HALO * LEVEL * breath * exp(-(r - SRC_R) / HALO_LEN);
    f = max(f, halo);
    if (r < SRC_R) {
        f = LEVEL * (0.30 + 0.30 * audio_bass);
        if (r > SRC_R - SRC_EDGE) { f = LEVEL; accent = true; }
    }

    /* 3. iskrzenie z wysokich: przesunięta macierz Bayera + przeskoki do akcentu */
    vec2  bshift  = floor(vec2(3.0, 5.0) * audio_high);
    float acc_cut = ACC_FROM - 0.12 * audio_high;
    bool  spark   = r > SRC_R && f > halo + 0.02
                 && hash_px(gl_FragCoord.xy, floor(time * 20.0)) < SPARK * audio_high;

    /* gładko: zamiast pojedynczych iskier — cały pierścień lekko w stronę akcentu */
    float acc = accent ? 1.0 : smoothstep(acc_cut * LEVEL, (acc_cut + ACC_SOFT) * LEVEL, f);
    if (r > SRC_R && f > halo + 0.02) acc = max(acc, SPARK * audio_high);

    vec3 col = palette_bg;
    if (dither > 0.5) {
        if (f > bayer8(gl_FragCoord.xy + bshift))
            col = (accent || spark || f >= acc_cut * LEVEL) ? palette_accent : palette_ink;
    } else {
        col = palette_ramp(f, acc);
    }
    fragColor = vec4(col, 1.0);
}
