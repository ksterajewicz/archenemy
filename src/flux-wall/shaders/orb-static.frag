#version 300 es
/*
 * archenemy — flux-wall: „orb-static” — wizualizer w stylu kulki NCS, przebieg finalny.
 *
 * Trzy warstwy, wszystkie w rastrze Bayera i trzech kolorach palety:
 *   1. pył cząstek z akumulatora (krok w orb.update.glsl) — tło,
 *   2. 64 promieniste słupki widma wokół tarczy — 32 biny log-freq (uniform
 *      audio_spectrum) odbite lustrzanie lewo/prawo jak w NCS; bas przy górze,
 *      wysokie przy dole; wysokość słupka = poziom pasma; końcówki w akcencie,
 *   3. tarcza: promień oddycha z basem, obrys w akcencie, wnętrze w atramencie
 *      z delikatnym gradientem; całość STOI (bez obrotu), a uderzenie (audio_beat)
 *      dorysowuje rozchodzący się pierścień.
 * Bliźniak z obrotem: orb-spinnin' (ta sama para plików, ORB_SPIN = 0.05).
 * Zlecenie właściciela 2026-09-17: „wersja, która się nie kręci”.
 * W ciszy: tarcza stoi, słupki mają tylko wysokość bazową, pył ledwo dryfuje.
 *
 * Uniformy: kontrakt flux-wall + accum/gain + audio_* (engine.h).
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
uniform float     audio_level;
uniform float     audio_bass;
uniform float     audio_mid;
uniform float     audio_high;
uniform float     audio_beat;
uniform sampler2D audio_spectrum;

out vec4 fragColor;

const float LEVEL    = 0.62;
const float GAMMA    = 1.9;
const float ACC_FROM = 0.80;
const float ACC_SOFT = 0.10;   /* tryb gładki: szerokość przejścia atrament → akcent nad progiem (część LEVEL) */
const float ORB_R    = 0.20;     /* = ORB_R w .update.glsl */
const float ORB_BR   = 0.22;
const int   BARS     = 64;       /* 32 biny × 2 (lustro) */
const float BAR_GAP  = 0.035;    /* odstęp tarcza → słupki */
const float BAR_BASE = 0.03;     /* wysokość w ciszy */
const float BAR_MAX  = 0.42;     /* wysokość przy pełnym pasmie */
const float BAR_FILL = 0.62;     /* część szczeliny kątowej zajęta przez słupek */
const float ORB_SPIN = 0.0;      /* bez obrotu — jedyna różnica wobec orb-spinnin' */

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

float spectrum(int bin) {
    bin = clamp(bin, 0, 31);
    return texelFetch(audio_spectrum, ivec2(bin, 0), 0).r;
}

void main() {
    /* współrzędne: środek 0, pion ±1, poziom ±aspekt */
    vec2  c = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
    c.x *= resolution.x / resolution.y;
    float r   = length(c);
    float ang = atan(c.x, c.y);                      /* 0 u góry, rośnie zgodnie z ruchem wskazówek */

    /* 1. pył z akumulatora */
    float a = texelFetch(accum, ivec2(gl_FragCoord.xy), 0).r;
    float f = log(1.0 + a * gain) / log(1.0 + gain);
    f = pow(clamp(f, 0.0, 1.0), GAMMA) * LEVEL;
    bool accent = false;

    /* 2. słupki widma — lustro: |ang| od góry (bas) do dołu (wysokie) */
    float R = ORB_R * (1.0 + ORB_BR * audio_bass);
    float rot = time * ORB_SPIN;                     /* 0 → tarcza i słupki stoją */
    float am  = abs(mod(ang + rot + 3.14159265, 6.2831853) - 3.14159265);   /* 0..π */
    float slot = am / 3.14159265 * 32.0;             /* 0..32 */
    int   bin  = int(floor(slot));
    float within = fract(slot);
    float lvl = mix(spectrum(bin), spectrum(bin + 1), 0.0);   /* dyskretne słupki jak w NCS */
    float h = BAR_BASE + BAR_MAX * lvl;
    bool in_bar = abs(within - 0.5) < 0.5 * BAR_FILL && r > R + BAR_GAP && r < R + BAR_GAP + h;
    if (in_bar) {
        float t = (r - R - BAR_GAP) / h;             /* 0 przy tarczy, 1 na końcu */
        f = LEVEL * (0.55 + 0.45 * t);
        accent = t > 0.82;                           /* końcówka w akcencie */
    }

    /* 3. tarcza: obrys w akcencie, wnętrze z gradientem; pierścień uderzenia */
    float edge = 0.012;
    if (r < R) {
        float t = r / R;
        f = LEVEL * (0.35 + 0.35 * t * t + 0.25 * audio_bass);
        if (r > R - edge) { f = LEVEL; accent = true; }
    }
    float ring_r = R + BAR_GAP + BAR_MAX * (1.0 - audio_beat) * 1.2;   /* rozchodzi się, gdy beat gaśnie */
    if (audio_beat > 0.02 && abs(r - ring_r) < 0.006) { f = LEVEL * audio_beat; accent = accent || audio_beat > 0.5; }

    /* iskrzenie z wysokich jak w pozostałych animacjach */
    vec2  bshift  = floor(vec2(3.0, 5.0) * audio_high);
    float acc_cut = ACC_FROM - 0.15 * audio_high;

    vec3 col = palette_bg;
    if (dither > 0.5) {
        if (f > bayer8(gl_FragCoord.xy + bshift))
            col = (accent || f >= acc_cut * LEVEL) ? palette_accent : palette_ink;
    } else {
        col = palette_ramp(f, accent ? 1.0 : smoothstep(acc_cut * LEVEL, (acc_cut + ACC_SOFT) * LEVEL, f));
    }
    fragColor = vec4(col, 1.0);
}
