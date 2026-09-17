#version 300 es
/*
 * archenemy — flux-wall: „scope” — oscyloskop, tryb Y-t (wizualizacja muzyki).
 *
 * Ekran oscyloskopu na pełnym pulpicie: podziałka (siatka + oś) w atramencie,
 * a przez środek biegnie PRZEBIEG dźwięku z wyjścia — 1024 próbki (21 ms)
 * po triggerze liczonym w C (start na narastającym przejściu przez zero, więc
 * ton okresowy stoi w miejscu, jak na prawdziwej lampie). Wiązka: rdzeń
 * w akcencie, poświata w atramencie, obie w rastrze Bayera.
 *   Wzmocnienie automatyczne (jak pokrętło V/div): szczyt okna liczony w C
 *   (uniform audio_wave_peak) → ślad wypełnia ~70% wysokości niezależnie
 *   od głośności; przy bardzo cichym sygnale wzmocnienie ma sufit.
 *   bas   → grubość i jasność wiązki (głośny bas = gruba, jasna plamka),
 *   level → siła poświaty,
 *   high  → iskrzenie rastra (przesunięcie progu Bayera),
 *   beat  → krótki rozbłysk całego śladu i podziałki.
 * W ciszy: pozioma linia przez środek z ledwo widoczną poświatą — „lampa
 * włączona, sygnału brak".
 *
 * Jednoprzebiegowy: koszt = kilka odczytów tekstury przebiegu na piksel.
 * Uniformy: kontrakt flux-wall + audio_* (engine.h); `#pragma flux audio 1`.
 */
#pragma flux audio 1
precision highp float;
precision highp sampler2D;

uniform vec2      resolution;
uniform float     time;
uniform vec3      palette_bg;
uniform vec3      palette_ink;
uniform vec3      palette_accent;
uniform float     detail;
uniform float     audio_level;
uniform float     audio_bass;
uniform float     audio_high;
uniform float     audio_beat;
uniform sampler2D audio_wave;
uniform float     audio_wave_peak;

out vec4 fragColor;

const int   WAVE_N   = 1024;
const float LEVEL    = 0.62;     /* maksymalny ton (jak w innych animacjach) */
const float AMP      = 0.72;     /* docelowa amplituda szczytu: część połowy wysokości ekranu */
const float GAIN_MAX = 8.0;      /* maksymalne wzmocnienie automatyczne (cisza nie ma wybuchać) */
const float CORE_PX  = 1.6;      /* promień rdzenia wiązki (px) przy ciszy */
const float GLOW_PX  = 9.0;      /* zasięg poświaty (px) */
const float CELLS    = 10.0;     /* działek podziałki w pionie */

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

/* próbka mono i (L+R)/2 → y śladu w pikselach */
float trace_y(int i, float g) {
    vec2 s = texelFetch(audio_wave, ivec2(clamp(i, 0, WAVE_N - 1), 0), 0).rg;
    float m = 0.5 * (s.r + s.g) * g;
    return resolution.y * 0.5 + clamp(m, -1.0, 1.0) * AMP * resolution.y * 0.5;
}

/* odległość punktu p od odcinka a-b */
float seg_dist(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    return length(p - (a + ab * t));
}

void main() {
    vec2 px = gl_FragCoord.xy;
    float f = 0.0;
    bool accent = false;

    /* 1. podziałka: siatka co cell px (kwadratowa), oś pozioma i pionowa mocniejsze */
    float cell = resolution.y / CELLS;
    vec2 gm = mod(px - resolution * 0.5, cell);
    float line = min(min(gm.x, cell - gm.x), min(gm.y, cell - gm.y));
    bool axis = abs(px.x - resolution.x * 0.5) < 0.6 || abs(px.y - resolution.y * 0.5) < 0.6;
    if (axis)            f = LEVEL * 0.34;
    else if (line < 0.5) f = LEVEL * 0.22;

    /* 2. ślad: odległość od łamanej próbek w sąsiedztwie kolumny piksela */
    float g = audio_wave_peak > 1e-4 ? clamp(1.0 / audio_wave_peak, 1.0, GAIN_MAX) : 1.0;
    float sx = px.x / resolution.x * float(WAVE_N);
    int i0 = int(floor(sx));
    float d = 1e9;
    for (int k = -2; k <= 1; k++) {
        int i = i0 + k;
        vec2 a = vec2((float(i)     + 0.5) / float(WAVE_N) * resolution.x, trace_y(i, g));
        vec2 b = vec2((float(i + 1) + 0.5) / float(WAVE_N) * resolution.x, trace_y(i + 1, g));
        d = min(d, seg_dist(px, a, b));
    }
    float core = CORE_PX * (1.0 + 1.2 * audio_bass + 0.6 * audio_beat);
    float glow = GLOW_PX * (1.0 + 0.8 * audio_level);
    if (d < core) {
        f = LEVEL * (0.85 + 0.15 * audio_beat);
        accent = true;
    } else if (d < core + glow) {
        float t = (d - core) / glow;                       /* 0 przy rdzeniu, 1 na brzegu */
        float gl = (1.0 - t) * (1.0 - t) * (0.30 + 0.45 * audio_level + 0.25 * audio_beat);
        f = max(f, LEVEL * gl);
    }

    /* 3. uderzenie: cała podziałka jaśnieje na moment */
    if (audio_beat > 0.02 && !accent) f = max(f, f * (1.0 + 0.6 * audio_beat));

    /* iskrzenie z wysokich — jak w pozostałych animacjach */
    vec2 bshift = floor(vec2(3.0, 5.0) * audio_high);
    vec3 col = palette_bg;
    if (f > bayer8(px + bshift))
        col = accent ? palette_accent : palette_ink;
    fragColor = vec4(col, 1.0);
}
