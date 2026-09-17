/*
 * archenemy — flux-wall: „dither-radar” — ekran radaru PPI, krok cząstki.
 *
 * Cząstki nie lecą — są „echami pod ramieniem”: w każdym kroku cząstka o
 * indeksie i staje w pierścieniu binu (i % 32) widma (bas blisko środka,
 * wysokie na obwodzie) pod bieżącym kątem ramienia (ten sam wzór na kąt co
 * w .frag: time · ARM_W) i splatuje ślad do akumulatora z prawdopodobieństwem
 * równym poziomowi pasma — jasność echa w danym promieniu = poziom pasma.
 * Ramię obraca się raz na ~4 s (tempo lekko rośnie z audio_mid — pragma
 * audio_tempo); akumulator gaśnie z `life` = 3 s, więc obraz za ramieniem
 * blednie jak fosfor. Cząstka, która nie „trafia” w tym kroku, stoi poza
 * ekranem i nie zostawia śladu. Uderzenie (audio_beat) podbija próg trafienia
 * — pod ramieniem zostaje jaśniejsza smuga. W ciszy: tylko szum odbiornika —
 * bardzo rzadkie, ledwie widoczne echa za ramieniem.
 *
 * Stan: xy = pozycja w 0..1 ekranu, z = wiek (licznik kroków do hasha,
 * zawija się), w = wcielenie (stałe, nieużywane).
 */
#pragma flux audio 1
#pragma flux particles 20000
#pragma flux life 3.0
#pragma flux rate 60
#pragma flux inc 0.03
#pragma flux gain 12
#pragma flux splat 0
#pragma flux seed 1957
#pragma flux audio_tempo 0.35
#pragma flux audio_glow 0.0

const float ARM_W   = 1.5707963;   /* rad/s: pełny obrót w 4 s (= ARM_W w .frag) */
const float R_IN    = 0.06;        /* promień pierwszego binu (w jednostkach wysokości/2) */
const float R_OUT   = 0.86;        /* promień ostatniego binu (= R_OUT w .frag) */
const int   BINS    = 32;
const float NOISE   = 0.025;       /* szum odbiornika: prawdopodobieństwo echa w ciszy */
const float SPEC_G  = 1.7;         /* wzmocnienie poziomu pasma przed progiem */
const float BEAT_G  = 0.35;        /* dodatek do progu przy uderzeniu (smuga pod ramieniem) */
const float AGE_MOD = 4096.0;      /* licznik kroków zawija się (float dokładny) */

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    float age = s.z;
    if (age < 0.5 || age >= AGE_MOD) age = 1.0;     /* start / zawinięcie licznika */
    int   k   = int(age);

    /* bin z indeksu cząstki: i = x + y·P, bin = i % 32 */
    int   P   = textureSize(pos, 0).x;
    int   bin = (idx.x + idx.y * P) % BINS;
    float lvl = texelFetch(audio_spectrum, ivec2(bin, 0), 0).r;

    /* losy tego kroku: promień w pierścieniu binu, kąt w wycinku przemiecionym
     * przez ramię w tym kroku, próg trafienia */
    float u_r = h2(idx.x, idx.y, seed + k * 3);
    float u_a = h2(idx.x + 131, idx.y + 17, seed + k * 3 + 1);
    float u_h = h2(idx.x + 59,  idx.y + 211, seed + k * 3 + 2);

    float r   = R_IN + (float(bin) + u_r) / float(BINS) * (R_OUT - R_IN);
    /* gęstość: pierścienie wewnętrzne mają mniejsze pole na krok — wyrównujemy
     * prawdopodobieństwem ∝ promień, żeby bas nie był jaśniejszy tylko dlatego,
     * że leży bliżej środka */
    /* kwadrat poziomu: widmo ma podłogę ~0.2 w wysokich — bez tego obwód
     * jest jednolicie zamglony, a pierścienie nie odcinają się od siebie */
    float prob = (NOISE + SPEC_G * lvl * lvl * (1.0 + BEAT_G * audio_beat)) * (r / R_OUT);
    bool  hit  = u_h < prob;

    vec2 p = vec2(-1.0);                                 /* poza ekranem: bez śladu */
    if (hit) {
        float arm = time * ARM_W;
        float a   = arm - u_a * ARM_W * dt;              /* kąt 0 u góry, zgodnie z ruchem wskazówek (jak .frag) */
        vec2  c   = vec2(sin(a), cos(a)) * r;
        p = vec2(0.5) + c * 0.5 * vec2(1.0 / aspect, 1.0);
    }
    o = vec4(p, age + 1.0, 1.0);
}
