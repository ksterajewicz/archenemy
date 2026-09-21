#version 300 es
/*
 * archenemy — flux-wall: „bars” — słupki widma jak w cavie, przebieg finalny.
 *
 * U dołu ekranu 64 słupki: 32 biny log-freq (uniform audio_spectrum) odbite
 * lustrzanie — BAS W ŚRODKU, wysokie na brzegach; pełne pasmo = ~40%
 * wysokości ekranu. Wszystko w rastrze Bayera i trzech kolorach palety:
 *   1. słupki w atramencie, jaśniejsze ku górze, końcówka w akcencie; pod
 *      linią bazową ich przygaszone, ściśnięte odbicie (jak na szkle CRT),
 *   2. kreska szczytu (peak hold) nad każdym słupkiem: wysokość trzyma cząstka
 *      w bars.update.glsl i stempluje ją do akumulatora w środkowej
 *      kolumnie słupka — tu czytamy PASMO trzech kolumn (xc-1..xc+1) i
 *      rysujemy kreskę na całą szerokość; gasnący ślad daje poświatę fosforu.
 *      Trzy kolumny, nie jedna: punkt GL_POINTS o rozmiarze 1 celowany w
 *      środek piksela xc ląduje po rasteryzacji o piksel obok, gdy błąd
 *      float przy NDC > 0 (prawa połowa ekranu) przesunie go pod xc — stąd
 *      „kreski tylko na lewej połowie" (zmierzone offscreen 2026-09-21:
 *      lewa połowa 937 stempli w xc, prawa 15 w xc i wszystkie w xc-1).
 *      Iskry omijają całe pasmo (patrz .update.glsl), więc nie udają kreski,
 *   3. iskry z akumulatora (reszta cząstek) — lecą znad końcówek w górę,
 *   4. linia bazowa: na uderzeniu (audio_beat) rozbłyska w akcencie,
 *   5. wysokie → iskrzenie rastra (przesunięcie macierzy Bayera, jak w
 *      orb), środek → gęstsze migotanie tła nad słupkami.
 * W ciszy: słupki o wysokości bazowej 3 px, kreski leżą tuż nad nimi, tło
 * ledwo migocze pojedynczymi pikselami — spokojny, ale żywy obraz.
 *
 * Uniformy: kontrakt flux-wall + accum/gain + audio_* (engine.h).
 * Stałe układu muszą być 1:1 z bars.update.glsl.
 */
precision highp float;
precision highp int;         /* hash h2 na uint32 — mediump zgubiłby bity */
precision highp sampler2D;   /* domyślnie lowp — texelFetch z akumulatora/widma byłby zaokrąglany tam, gdzie sterownik honoruje precyzję (Mesa) */

uniform vec2      resolution;
uniform float     time;
uniform vec3      palette_bg;
uniform vec3      palette_ink;
uniform vec3      palette_accent;
uniform sampler2D accum;
uniform float     gain;
uniform float     audio_mid;
uniform float     audio_high;
uniform float     audio_beat;
uniform sampler2D audio_spectrum;

out vec4 fragColor;

const float LEVEL     = 0.62;
const float GAMMA     = 1.6;
const float ACC_FROM  = 0.80;
const int   BARS      = 64;      /* 32 biny × 2 (lustro) */
const float BAR_FILL  = 0.70;    /* część szczeliny zajęta przez słupek */
const float BASE_FRAC = 0.12;    /* linia bazowa: ułamek wysokości ekranu od dołu */
const float BAR_BASE  = 3.0;     /* px: wysokość w ciszy */
const float BAR_MAX   = 0.40;    /* ułamek wysokości ekranu przy pełnym paśmie */
const float MARK_GAP  = 2.0;     /* px: szczelina słupek → kreska szczytu */
const float MARK_INC  = 0.05;    /* = inc w .update.glsl: jeden stempel szczytu */
const float REFL_K    = 0.28;    /* odbicie: ściśnięcie wysokości */
const float REFL_LVL  = 0.30;    /* odbicie: jasność względem słupka */
const float SEG_PX    = 6.0;     /* px: podział słupka na segmenty jak w VU-metrze */
const float HAZE      = 0.09;    /* mgiełka nad linią bazową: jasność względem LEVEL */
const float HAZE_PX   = 40.0;    /* px: zasięg mgiełki */
const float GLINT_W   = 0.35;    /* rad/s: tempo wędrującego błysku */

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

/* hash jak h2 z prelude kroku cząstek (do migotania tła) */
float h2(int x, int y, int s) {
    uint n = uint(x) * 374761393u + uint(y) * 668265263u + uint(s) * 1013904223u;
    n = n ^ (n >> 13u); n = n * 1274126177u; n = n ^ (n >> 16u);
    return float(n) / 4294967295.0;
}

int bar_bin(int i) { return i < 32 ? 31 - i : i - 32; }   /* lustro */

/* Środkowa kolumna pikseli słupka `i` — ta sama formuła, co w .update.glsl. */
int bar_center(int i) {
    float sw = resolution.x / float(BARS);
    int x0 = int(floor(float(i) * sw)), x1 = int(floor(float(i + 1) * sw));
    return (x0 + x1) / 2;
}

float spectrum(int bin) { return texelFetch(audio_spectrum, ivec2(clamp(bin, 0, 31), 0), 0).r; }

float tone(float a) {
    float f = log(1.0 + a * gain) / log(1.0 + gain);
    return pow(clamp(f, 0.0, 1.0), GAMMA) * LEVEL;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    float y_base = floor(resolution.y * BASE_FRAC);
    float sw = resolution.x / float(BARS);
    int   i  = clamp(int(float(px.x) / sw), 0, BARS - 1);
    int   x0 = int(floor(float(i) * sw)), x1 = int(floor(float(i + 1) * sw));
    int   gap = max(int(float(x1 - x0) * (1.0 - BAR_FILL) * 0.5), 1);
    bool  in_slot = px.x >= x0 + gap && px.x < x1 - gap;
    int   xc = bar_center(i);

    float lvl = spectrum(bar_bin(i));
    float h   = BAR_BASE + lvl * BAR_MAX * resolution.y;    /* px nad linią bazową */
    float yb  = float(px.y) - y_base;                        /* wysokość piksela nad bazą */

    float f = 0.0;
    bool  accent = false;

    /* tło: pojedyncze migoczące piksele — gęściej ze środkiem pasma */
    {
        int   tick = int(time * 6.0);
        float r = h2(px.x, px.y, 7 + tick);
        float dens = 0.004 + 0.03 * audio_mid;
        if (r < dens && yb > h + MARK_GAP + 2.0) f = LEVEL * (0.25 + 0.5 * h2(px.x + 3, px.y, tick));
    }
    /* mgiełka nad linią bazową — poświata fosforu, żeby cisza nie była pustym ekranem */
    if (yb > 0.0) f = max(f, HAZE * LEVEL * max(0.0, 1.0 - yb / HAZE_PX));
    /* wędrujący błysk: powoli przesuwa się po słupkach (w ciszy jedyny ruch prócz migotania) */
    float glint = exp(-pow((float(i) - (32.0 + 30.0 * sin(time * GLINT_W))) / 2.5, 2.0));

    /* iskry z akumulatora (poza pasmem szczytu xc-1..xc+1) */
    float a_self = texelFetch(accum, ivec2(px), 0).r;
    if (abs(px.x - xc) > 1 && a_self > 0.0) {
        float fs = tone(a_self);
        if (fs > f) { f = fs; accent = fs >= ACC_FROM * LEVEL; }
    }

    if (in_slot) {
        /* 1. słupek: jaśniej ku górze, segmenty co SEG_PX, końcówka w akcencie */
        if (yb >= 0.0 && yb < h) {
            float t = yb / max(h, 1.0);
            f = LEVEL * min(0.45 + 0.33 * t + 0.25 * glint, 0.78);   /* pod progiem akcentu; wysokie obniżają próg → górna część iskrzy */
            bool seg_line = h > 12.0 && mod(yb, SEG_PX) < 1.0;
            if (seg_line) f *= 0.45;
            accent = yb >= h - max(2.0, 0.12 * h);
            if (accent) f = LEVEL;
        }
        /* odbicie pod linią bazową: ściśnięte, przygaszone, bez akcentu */
        else if (yb < -2.0) {
            float d = (-yb - 2.0) / REFL_K;                     /* „wysokość” w odbiciu */
            if (d < h) f = max(f, LEVEL * (REFL_LVL + 0.2 * glint) * (1.0 - 0.6 * d / max(h, 1.0)));
        }
        /* 2. kreska szczytu: pasmo trzech kolumn wokół środka, ten wiersz —
         *    maksimum, bo stempel może wylądować o piksel obok (nagłówek) */
        if (yb >= h + MARK_GAP - 0.5) {
            float a_m = max(max(texelFetch(accum, ivec2(xc - 1, px.y), 0).r,
                                texelFetch(accum, ivec2(xc,     px.y), 0).r),
                                texelFetch(accum, ivec2(xc + 1, px.y), 0).r);
            if (a_m >= 0.5 * MARK_INC) {                        /* świeży stempel lub trzymany szczyt */
                f = LEVEL * clamp(0.75 + tone(a_m), 0.0, 1.0);
                accent = true;
            } else if (a_m > 0.0) {                              /* gasnąca poświata po kresce */
                float fm = tone(a_m) * 0.9;
                if (fm > f) { f = fm; accent = false; }
            }
        }
    }

    /* 4. linia bazowa: cienka w atramencie, na uderzeniu rozbłysk w akcencie */
    if (yb >= -2.0 && yb < 0.0) {
        float bl = 0.35 + 0.65 * audio_beat;
        f = LEVEL * bl;
        accent = audio_beat > 0.35;
    } else if (audio_beat > 0.05 && abs(yb + 1.0) < 2.0 + 6.0 * audio_beat) {
        float glow = LEVEL * audio_beat * 0.6;                  /* poświata wokół linii */
        if (glow > f) { f = glow; accent = false; }
    }

    /* 5. iskrzenie rastra z wysokich jak w pozostałych animacjach */
    vec2  bshift  = floor(vec2(3.0, 5.0) * audio_high);
    float acc_cut = ACC_FROM - 0.15 * audio_high;

    vec3 col = palette_bg;
    if (f > bayer8(gl_FragCoord.xy + bshift))
        col = (accent || f >= acc_cut * LEVEL) ? palette_accent : palette_ink;
    fragColor = vec4(col, 1.0);
}
