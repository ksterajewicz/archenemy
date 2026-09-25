#version 300 es
/*
 * archenemy — flux-wall: „tunnel” — perspektywiczny tunel z pierścieni
 * widma (jak klasyczne wizualizacje Winampa), animacja jednoprzebiegowa.
 *
 * Patrzymy w głąb tunelu. Kolejne pierścienie to kolejne CHWILE: najnowszy
 * rodzi się przy kamerze (największy — wchodzi zza krawędzi kadru), starsze
 * uciekają w głąb i maleją, aż zginą w winiecie tła. Głębokość jest
 * logarytmiczna (r = R0·RATIO^u), więc pierścienie równo rozłożone w czasie
 * wyglądają jak perspektywa. Obwód każdego pierścienia dzieli się na 64
 * segmenty = 32 biny widma (audio_spectrum) odbite lustrzanie lewo/prawo:
 * bas u góry, wysokie u dołu (jak w orb). Segment to „ściana” tunelu
 * wystająca z obręczy ku kamerze — jej długość i jasność = poziom pasma;
 * najgłośniejsze segmenty mają końcówkę w akcencie. Do tego cienkie szprychy
 * na granicach segmentów (siatka tunelu) i obręcze w atramencie.
 *
 * Reakcje: bas rozpycha promień najbliższych pierścieni (najnowszy pulsuje),
 * uderzenie (audio_beat) rozbłyska najbliższe obręcze w akcencie, środek
 * przyspiesza lot w głąb (audio_tempo → time), wysokie iskrzą rastrem
 * (przesunięcie macierzy Bayera). Bez pamięci klatek: „historia” starszych
 * pierścieni to bieżące widmo modulowane hashem stałym dla danego pierścienia
 * — pierścień niesie swój wzór w głąb, więc kolejne chwile różnią się od
 * siebie, a przejście z „teraz” do „wtedy” jest płynne w głębokości.
 * W ciszy: cienkie obręcze i ledwo widoczne szprychy, powolny lot, środek
 * tunelu wolno dryfuje.
 *
 * Uniformy: kontrakt flux-wall + audio_* (engine.h).
 */
#pragma flux audio 1
#pragma flux audio_tempo 1.2
precision highp float;
precision highp sampler2D;   /* domyślnie lowp — texelFetch z widma byłby zaokrąglany tam, gdzie sterownik honoruje precyzję (Mesa) */

uniform vec2      resolution;
uniform float     time;
uniform vec3      palette_bg;
uniform vec3      palette_ink;
uniform vec3      palette_accent;
uniform float     dither;   /* 1 = raster Bayera, 0 = gładki gradient palety (engine.h) */
uniform float     audio_bass;
uniform float     audio_high;
uniform float     audio_beat;
uniform sampler2D audio_spectrum;

out vec4 fragColor;

const float PI        = 3.14159265;
const float LEVEL     = 0.62;
const float ACC_FROM  = 0.82;
const float ACC_SOFT  = 0.10;   /* tryb gładki: szerokość przejścia atrament → akcent nad progiem (część LEVEL) */
const float R0        = 1.25;    /* promień, przy którym rodzi się pierścień (za górną krawędzią kadru; rogi go widzą) */
const float LN_STEP   = 0.2231;  /* = -ln(RATIO), RATIO = 0.80: kolejny pierścień ma 80% promienia poprzedniego */
const float RATE      = 0.8;     /* pierścieni na sekundę (czasu animacji — mid przyspiesza) */
const float DRIFT     = 0.10;    /* amplituda dryfu środka tunelu */
const float FADE_FROM = 2.5;     /* winieta: od tej głębokości (w pierścieniach) obraz gaśnie… */
const float FADE_TO   = 9.5;     /* …a tu ginie w tle */
const float BASS_PULSE= 0.55;    /* o ile pierścieni bas rozpycha najbliższą obręcz (0.55 ≈ ×1.13 promienia) */
const float HOOP_W    = 0.025;   /* półgrubość obręczy w jednostkach głębokości (min. ~2 px) */
const float HOOP_F    = 0.50;    /* jasność obręczy (× LEVEL) */
const float SPOKE_F   = 0.16;    /* jasność szprych (× LEVEL) */
const float W_BASE    = 0.05;    /* długość segmentu w ciszy */
const float W_MAX     = 0.60;    /* długość segmentu przy pełnym pasmie (odstęp obręczy = 1.0) */
const float FILL      = 0.72;    /* część szczeliny kątowej zajęta przez segment (blisko kamery) */
const float ACCENT_LVL= 0.30;    /* segmenty głośniejsze niż to mają końcówkę w akcencie */
const float HIST_MIN  = 0.30;    /* najsłabsza „pamięć” pasma na starszym pierścieniu */
const float BEAT_F    = 0.55;    /* rozbłysk najbliższych pierścieni przy uderzeniu (× LEVEL) */

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

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float spectrum(int bin) {
    bin = clamp(bin, 0, 31);
    return texelFetch(audio_spectrum, ivec2(bin, 0), 0).r;
}

void main() {
    /* współrzędne: środek 0, pion ±1, poziom ±aspekt; środek tunelu dryfuje */
    vec2 c = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
    c.x *= resolution.x / resolution.y;
    c -= DRIFT * vec2(sin(time * 0.23), cos(time * 0.17));
    float r   = max(length(c), 1e-4);
    float ang = atan(c.x, c.y);                      /* 0 u góry, ±π u dołu → |ang| to lustro lewo/prawo */
    float am  = abs(ang);                            /* 0..π: bas u góry, wysokie u dołu */
    float slot = am / PI * 32.0;                     /* 0..32 */
    int   bin  = int(min(floor(slot), 31.0));
    float within = fract(slot);
    float px_slot = (2.0 / resolution.y) / r * (32.0 / PI);   /* ile szczelin kątowych ma jeden piksel na tym promieniu */

    /* głębokość w jednostkach pierścieni: u = 0 przy kamerze (r = R0), rośnie w głąb */
    float u = log(R0 / r) / LN_STEP;
    float du_px = (2.0 / resolution.y) / (LN_STEP * r);      /* jednostek głębokości na piksel */
    /* bas rozpycha najbliższe pierścienie: piksel dalej od środka „widzi” bliższą obręcz */
    u += BASS_PULSE * audio_bass * clamp(1.0 - u / 3.0, 0.0, 1.0);

    /* lot: pierścień n leży na głębokości n + phase; nowy rodzi się przy phase = 0 */
    float s     = time * RATE;
    float phase = fract(s);
    float q     = u - phase;                         /* obręcze przy q = 0, 1, 2, … */
    float v     = 1.0 - smoothstep(FADE_FROM, FADE_TO, u);   /* winieta w głębi */

    float f = 0.0;
    bool  accent = false;

    /* 1. szprychy — siatka tunelu na granicach segmentów (≈1 px) */
    if (abs(within - 0.5) > 0.5 - 0.55 * px_slot && u > 0.0) f = SPOKE_F * LEVEL * v;

    /* 2. segmenty — ściana od obręczy pierścienia nb ku kamerze */
    float nb   = ceil(q);                            /* pierścień, którego ściana może tu sięgać */
    float dist = nb - q;                             /* 0 na obręczy, rośnie ku kamerze */
    float un   = nb + phase;                         /* głębokość obręczy tego pierścienia */
    float near_flash = clamp((2.2 - un) / 1.9, 0.0, 1.0);   /* uderzenie widać na najbliższych pierścieniach */
    if (nb >= 0.0) {
        float g    = floor(s) - nb;                  /* tożsamość pierścienia (stała, gdy ucieka w głąb) */
        float lvl  = spectrum(bin);
        float hist = mix(HIST_MIN, 1.0, hash(vec2(g * 0.731 + 7.0, float(bin) * 1.117 + 3.0)));
        lvl *= mix(1.0, hist, clamp(un - 0.25, 0.0, 1.0));   /* „teraz” → „wtedy” płynnie z głębokością */
        float w    = W_BASE + W_MAX * lvl;
        float fill = mix(1.0, FILL, clamp((r - 0.08) / 0.27, 0.0, 1.0));   /* w głębi segmenty zlewają się w obręcz */
        if (abs(within - 0.5) < 0.5 * fill && dist < w) {
            float t = dist / w;                      /* 0 przy obręczy, 1 na końcówce (ku kamerze) */
            f = LEVEL * v * (0.45 + 0.55 * t) * (0.55 + 0.45 * lvl);
            accent = t > 0.78 && lvl > ACCENT_LVL;
        }
    }

    /* 3. obręcze — zawsze, także w ciszy; minimum ~2 px grubości */
    float nr = floor(q + 0.5);
    if (nr >= 0.0 && abs(q - nr) < max(HOOP_W, du_px)) {
        f = max(f, HOOP_F * LEVEL * v);
    }

    /* 4. uderzenie — rozbłysk najbliższych obręczy i ich ścian w akcencie */
    if (f > 0.0 && audio_beat > 0.02) {
        f += BEAT_F * LEVEL * audio_beat * near_flash;
        accent = accent || (audio_beat * near_flash > 0.5);
    }

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
