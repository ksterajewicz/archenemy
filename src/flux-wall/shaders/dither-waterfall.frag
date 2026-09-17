#version 300 es
/*
 * archenemy — flux-wall: „dither-waterfall” — spektrogram wodospadowy (sonar/SDR), przebieg finalny.
 *
 * Obraz to akumulator z dither-waterfall.update.glsl: u góry drukuje się
 * najświeższy wiersz widma (32 biny log-freq na szerokość — bas po lewej,
 * wysokie po prawej; jasność = poziom pasma), historia płynie w dół i gaśnie
 * jak fosfor przy dolnej krawędzi. Tu:
 *   1. gęstość śladów uśredniana w małym oknie (8×1 px przy 960×540, rośnie
 *      z rozdzielczością) OGRANICZONYM do jednego binu — zbija ziarno Poissona
 *      drukarki, nie rozmywa granic między binami; gęstość przeliczana na
 *      piksel 960×540 i na liczbę aktywnych cząstek (detail), więc jasność nie
 *      zależy od rozdzielczości ani od `detail`,
 *   2. log-tonowanie z `gain`, gamma/level jak w pozostałych animacjach,
 *   3. „głowica”: trzy górne wiersze pokazują bieżące widmo bez opóźnienia
 *      (jasne biny w akcencie),
 *   4. cienka szczelina tła między binami (32 kolumny czytelne jak na SDR),
 *   5. raster Bayera 8x8 do trzech kolorów; najgłośniejsze piksele (ACC_FROM)
 *      w akcencie; audio_high przesuwa macierz — iskrzenie na hi-hacie.
 * Beat jest już w akumulatorze jako jaśniejszy wiersz (drukarka), tu tylko
 * lekko unosi próg akcentu. W ciszy: prawie pusty, ciemny wodospad z szumem tła.
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
uniform float     detail;
uniform sampler2D accum;
uniform float     gain;
uniform float     audio_high;
uniform float     audio_beat;
uniform sampler2D audio_spectrum;

out vec4 fragColor;

const float LEVEL    = 0.62;
const float GAMMA    = 1.5;
const float ACC_FROM = 0.86;
const int   BINS     = 32;
const float REF_PX   = 518400.0; /* 960×540: gęstość śladów przeliczana na piksel tej rozdzielczości */
const float NORM     = 1.2;      /* ~1 ślad/piksel (960×540) przy pełnym druku → pełna jasność */
const int   HEAD_PX  = 3;        /* wysokość „głowicy” (bieżące widmo) w pikselach przy 540 */

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

float spectrum(int bin) {
    bin = clamp(bin, 0, BINS - 1);
    return texelFetch(audio_spectrum, ivec2(bin, 0), 0).r;
}

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    int   W  = int(resolution.x), H = int(resolution.y);

    /* 1. okno uśredniania w obrębie binu */
    float binw = resolution.x / float(BINS);
    int   bin  = clamp(int(float(px.x) / binw), 0, BINS - 1);
    int   bs   = int(ceil(float(bin) * binw));
    int   be   = int(ceil(float(bin + 1) * binw)) - 1;
    int   gap  = max(1, W / 960);
    int   bw   = clamp(W / 120, 8, 32);       /* 8×1 przy 960×540, 16×2 przy 1080p — okno w ułamku ekranu, szerokie (wiersz), nie wysokie */
    int   bh   = clamp(H / 540, 1, 4);
    int   x0   = clamp(px.x - bw / 2, bs, be - bw + 1);   /* okno przesuwane do wnętrza binu (bin jest szerszy niż okno) */
    int   y0   = clamp(px.y - bh / 2, 0, H - bh);
    float sum  = 0.0;
    for (int y = 0; y < bh; y++)
        for (int x = 0; x < bw; x++)
            sum += texelFetch(accum, ivec2(x0 + x, y0 + y), 0).r;
    float n = float(bw * bh);
    float a = sum / n * (resolution.x * resolution.y / REF_PX) * NORM
            / (0.35 + 0.65 * detail);   /* silnik aktywuje (0.35 + 0.65·detail)·N cząstek — jasność stała, rośnie tylko ziarno */

    /* 2. tonowanie */
    float f = log(1.0 + a * gain) / log(1.0 + gain);
    f = pow(clamp(f, 0.0, 1.0), GAMMA) * LEVEL;
    bool accent = false;

    /* 3. głowica: bieżące widmo w górnych wierszach */
    int head = max(1, int(float(HEAD_PX) * resolution.y / 540.0));
    if (px.y >= H - head) {
        float lvl = spectrum(bin);
        f = LEVEL * (0.25 + 0.75 * lvl);
        accent = lvl > 0.6;
    }

    /* 4. szczelina między binami: cienka linia tła (32 kolumny czytelne jak na SDR) */
    if (px.x - bs < gap) f = 0.0;

    /* 5. raster: iskrzenie z wysokich, próg akcentu lżejszy przy uderzeniu */
    vec2  bshift  = floor(vec2(3.0, 5.0) * audio_high);
    float acc_cut = ACC_FROM - 0.10 * audio_beat;

    vec3 col = palette_bg;
    if (f > bayer8(gl_FragCoord.xy + bshift))
        col = (accent || f >= acc_cut * LEVEL) ? palette_accent : palette_ink;
    fragColor = vec4(col, 1.0);
}
