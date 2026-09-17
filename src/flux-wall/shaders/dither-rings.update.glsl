/*
 * archenemy — flux-wall: „dither-rings” — koncentryczne pierścienie z uderzeń, krok cząstki.
 *
 * Każde uderzenie (audio_beat) wystrzeliwuje ze środka ekranu pierścień:
 * budzi część uśpionych cząstek na małym okręgu wokół źródła, a te lecą
 * promieniście ze stałą prędkością (RING_V = 0,35 wysokości ekranu/s).
 * Ślady w akumulatorze (krótkie `life`) dają rysunek pierścienia z fosforową
 * smugą za frontem; sam pierścień gaśnie przez ~RING_TAU s, bo cząstki
 * losowo zasypiają (gęstość punktów maleje wykładniczo, a obwód rośnie).
 *   - bas   → grubość (rozrzut promienia startowego) i jasność (ile cząstek
 *             budzi uderzenie) nowo wystrzelonego pierścienia,
 *   - środek → deformacja kształtu: prędkość zależy od kąta (szum po okręgu
 *             + drobna harmoniczna, dryfujące), więc obwód faluje z amplitudą
 *             od audio_mid,
 *   - beat  → wystrzał; cząstki budzone w kolejnych krokach tego samego
 *             uderzenia startują dalej o RING_V·(czas od onsetu), więc trafiają
 *             do JEDNEGO pierścienia (front nie grubieje od liczby kroków).
 * W ciszy: co BREATH s bardzo słaby pierścień „oddechu” (poziom < ~0,1),
 * żeby obraz żył. Uśpiona cząstka = wiek 0 (splat silnika jej nie rysuje).
 *
 * Stan: xy = pozycja w 0..1 ekranu, z = wiek w krokach (0 = śpi), w = wcielenie.
 * Bez audio_tempo — pierścienie mają rosnąć równo, nie w rytm środka.
 */
#pragma flux audio 1
#pragma flux particles 12000
#pragma flux life 0.05
#pragma flux rate 120
#pragma flux inc 0.25
#pragma flux gain 4
#pragma flux splat 0
#pragma flux seed 2041
#pragma flux audio_tempo 0
#pragma flux audio_glow 0.5

const float SRC_R      = 0.07;       /* promień źródła w jednostkach c (pion ±1) — jak w .frag */
const float RING_V     = 0.70;       /* jednostek c na sekundę = 0,35 wysokości ekranu/s */
const float RING_TAU   = 2.5;        /* sekundy: stała zaniku gęstości pierścienia (fosfor) */
const float MAX_AGE    = 4.5;        /* sekundy: twardy kres życia cząstki */
const float BEAT_MIN   = 0.45;       /* okno wystrzału: audio_beat powyżej progu */
const float BEAT_DECAY = 0.10;       /* stała zaniku audio_beat w silniku (audio.c) */
const float WAKE_BEAT  = 0.055;      /* p. obudzenia uśpionej cząstki na krok okna uderzenia */
const float THICK_MIN  = 0.008;      /* grubość pierścienia w ciszy basu (jednostki c) */
const float THICK_BASS = 0.025;      /* przyrost grubości przy pełnym basie */
const float WAVE_NZ    = 2.2;        /* skala szumu kątowego (vnoise po okręgu — bez szwu, nieregularne fale) */
const float WAVE_K2    = 11.0;       /* drobna harmoniczna na wierzchu */
const float WAVE_AMP   = 0.14;       /* ± prędkości przy pełnym środku (delikatne fale) */
const float BREATH     = 3.0;        /* sekundy między pierścieniami oddechu w ciszy */
const float WAKE_BREATH= 0.018;      /* p. obudzenia na krok okna oddechu (słaby pierścień) */

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    vec2  p   = s.xy;
    float age = s.z, gen = s.w;
    int   step_id = int(time * 997.0);               /* inny hash w każdym kroku */

    if (age < 0.5) {
        /* uśpiona: czeka na wystrzał (uderzenie) albo oddech (cisza) */
        float wake = 0.0, r0 = SRC_R, thick = THICK_MIN;
        if (audio_beat > BEAT_MIN) {
            wake  = WAKE_BEAT * (0.35 + 0.65 * audio_bass);
            r0   += RING_V * (-BEAT_DECAY * log(audio_beat));   /* wyrównanie do frontu tego uderzenia */
            thick = THICK_MIN + THICK_BASS * audio_bass;
        } else {
            float quiet = 1.0 - smoothstep(0.03, 0.12, audio_level);
            float ph = mod(time, BREATH);
            if (quiet > 0.0 && ph < 2.0 * dt) {
                wake = WAKE_BREATH * quiet;
                r0  += RING_V * ph;
            }
        }
        if (wake > 0.0 && h2(idx.x, idx.y, seed + step_id) < wake) {
            float g = gen + 1.0;
            int   k = int(g) * 7;
            float a = h2(idx.x + 13, idx.y, seed + k) * 6.2831853;
            float rr = r0 + thick * h2(idx.x, idx.y + 29, seed + k);
            vec2  c = vec2(cos(a), sin(a)) * rr;
            p = vec2(0.5) + c * 0.5 * vec2(1.0 / aspect, 1.0);
            o = vec4(p, 1.0, g);
            return;
        }
        o = vec4(-1.0, -1.0, 0.0, gen);
        return;
    }

    /* żywa: zaśnięcie losowe (fosfor), z wieku albo poza ekranem */
    bool die = age > MAX_AGE / dt
            || h2(idx.x + 5, idx.y + 3, seed + step_id) < dt / RING_TAU
            || p.x < -0.02 || p.x > 1.02 || p.y < -0.02 || p.y > 1.02;
    if (die) { o = vec4(-1.0, -1.0, 0.0, gen); return; }

    /* ruch promienisty; prędkość faluje z kątem (środek) + drobny rozrzut per cząstka */
    vec2  c   = (p - 0.5) * vec2(aspect, 1.0) * 2.0;
    vec2  dir = normalize(c + 1e-6);
    float ang = atan(c.y, c.x);
    vec2  ring = vec2(cos(ang), sin(ang)) * WAVE_NZ + vec2(time * 0.25, -time * 0.2);
    float wave = 2.0 * vnoise(ring, seed + 303) - 1.0 + 0.4 * sin(WAVE_K2 * ang - time * 1.3);
    float jitter = 0.99 + 0.02 * h2(idx.x, idx.y + 41, seed + int(gen) * 7);
    float v = RING_V * jitter * (1.0 + WAVE_AMP * audio_mid * wave);
    c += dir * v * dt;
    p = vec2(0.5) + c * 0.5 * vec2(1.0 / aspect, 1.0);
    o = vec4(p, age + 1.0, gen);
}
