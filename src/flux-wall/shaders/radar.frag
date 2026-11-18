#version 300 es
/*
 * archenemy — flux-wall: „radar” — ekran radaru PPI, przebieg finalny.
 *
 * Cztery warstwy, wszystkie w rastrze Bayera i trzech kolorach palety:
 *   1. podziałka (graticule): cztery koncentryczne kręgi, krzyż i obwód —
 *      bardzo słabe, w atramencie; zewnętrzny obwód rozjaśnia się z wysokimi,
 *   2. echa z akumulatora (krok w radar.update.glsl): pierścieniowy
 *      obraz widma — bas przy środku, wysokie na obwodzie (32 biny log);
 *      gaśnie za ramieniem jak fosfor (~3 s); najjaśniejsze echa w akcencie,
 *   3. ramię: obraca się raz na ~4 s (czas animacji, tempo lekko rośnie
 *      z audio_mid), za nim krótka poświata; uderzenie (audio_beat) rozjaśnia
 *      i pogrubia całe ramię,
 *   4. piasta: mały krążek w środku, którego promień pulsuje z basem.
 * W ciszy: samo ramię obraca się nad pustą podziałką, za nim ledwie widoczny
 * szum odbiornika.
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
uniform float     detail;
uniform sampler2D accum;
uniform float     gain;
uniform float     audio_bass;
uniform float     audio_high;
uniform float     audio_beat;

out vec4 fragColor;

const float LEVEL     = 0.80;
const float GAMMA     = 1.25;
const float ACC_FROM  = 0.72;      /* echo w akcencie od tej części LEVEL */
const float ACC_SOFT  = 0.10;   /* tryb gładki: szerokość przejścia atrament → akcent nad progiem (część LEVEL) */
const float ARM_W     = 1.5707963; /* rad/s (= ARM_W w .update.glsl) */
const float R_OUT     = 0.86;      /* obwód tarczy (= R_OUT w .update.glsl) */
const float GRAT_F    = 0.09;      /* jasność podziałki (część LEVEL) */
const float GRAT_PX   = 1.2;       /* grubość linii podziałki w pikselach */
const float BEZEL_F   = 0.16;      /* jasność obwodu w ciszy */
const float BEZEL_HI  = 0.55;      /* dodatek do obwodu przy pełnych wysokich */
const float ARM_PX    = 1.6;       /* grubość ramienia w pikselach */
const float ARM_BEAT  = 2.4;       /* dodatkowa grubość przy uderzeniu */
const float TRAIL     = 0.30;      /* stała zaniku poświaty za ramieniem (rad) */
const float TRAIL_F   = 0.30;      /* jasność poświaty tuż za ramieniem */
const float HUB_R     = 0.022;     /* promień piasty */
const float HUB_BASS  = 0.030;     /* przyrost promienia przy pełnym basie */

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
    /* współrzędne: środek 0, pion ±1, poziom ±aspekt; piksel w tych jednostkach */
    vec2  c = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
    c.x *= resolution.x / resolution.y;
    float px  = 2.0 / resolution.y;
    float r   = length(c);
    float ang = atan(c.x, c.y);                      /* 0 u góry, rośnie zgodnie z ruchem wskazówek */

    /* 1. podziałka: kręgi co ćwierć promienia, krzyż, obwód */
    float f = 0.0;
    bool accent = false;
    if (r < R_OUT + GRAT_PX * px) {
        float ring = abs(fract(r / R_OUT * 4.0 + 0.5) - 0.5) * R_OUT / 4.0;   /* odległość od najbliższego kręgu */
        bool on_ring  = ring < GRAT_PX * px && r > R_OUT * 0.125;
        bool on_cross = min(abs(c.x), abs(c.y)) < GRAT_PX * px;
        if (on_ring || on_cross) f = GRAT_F * LEVEL;
        if (abs(r - R_OUT) < GRAT_PX * px) f = (BEZEL_F + BEZEL_HI * audio_high) * LEVEL;   /* obwód żyje z wysokimi */
    }

    /* 2. echa z akumulatora — log-tonowanie jak w pozostałych animacjach */
    float a = texelFetch(accum, ivec2(gl_FragCoord.xy), 0).r;
    float e = log(1.0 + a * gain) / log(1.0 + gain);
    e = pow(clamp(e, 0.0, 1.0), GAMMA) * LEVEL;

    /* 3. ramię i poświata za nim */
    float arm  = time * ARM_W;
    vec2  u    = vec2(sin(arm), cos(arm));
    float d    = mod(arm - ang, 6.2831853);           /* kąt ZA ramieniem, 0..2π */
    float wedge = (r < R_OUT) ? TRAIL_F * LEVEL * exp(-d / TRAIL) * (1.0 + audio_beat) : 0.0;
    f = max(f, min(1.0, e + wedge));
    accent = e >= ACC_FROM * LEVEL;
    float acc = smoothstep(ACC_FROM * LEVEL, (ACC_FROM + ACC_SOFT) * LEVEL, e);   /* tryb gładki */

    float along = dot(c, u);
    float side  = abs(c.x * u.y - c.y * u.x);
    float arm_w = (ARM_PX + ARM_BEAT * audio_beat) * px;
    if (along > 0.0 && along < R_OUT && side < arm_w) {
        f = LEVEL * (0.80 + 0.20 * audio_beat);
        accent = true;
        acc = 1.0;
    }

    /* 4. piasta pulsująca z basem */
    if (r < HUB_R + HUB_BASS * audio_bass) { f = LEVEL; accent = true; acc = 1.0; }

    /* iskrzenie z wysokich jak w pozostałych animacjach */
    vec2  bshift  = floor(vec2(3.0, 5.0) * audio_high);

    vec3 col = palette_bg;
    if (dither > 0.5) {
        if (f > bayer8(gl_FragCoord.xy + bshift))
            col = accent ? palette_accent : palette_ink;
    } else {
        col = palette_ramp(f, acc);
    }
    fragColor = vec4(col, 1.0);
}
