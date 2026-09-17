/*
 * archenemy — flux-wall: „dither-waterfall” — spektrogram wodospadowy (sonar/SDR), krok cząstki.
 *
 * Cząstki są „drukarką” wierszy widma. Co krok rodzi się jedna kohorta
 * (N / kroków_na_drogę cząstek) na górnej krawędzi: każda losuje kolumnę
 * (ciąg złotego podziału — równe pokrycie szerokości), odczytuje bin widma
 * pod tą kolumną (32 biny log-freq rozciągnięte na szerokość: bas po lewej,
 * wysokie po prawej) i DRUKUJE (jest widoczna) z prawdopodobieństwem równym
 * poziomowi pasma; niewidoczne parkują poza ekranem (x = -1), ale lecą dalej,
 * żeby zachować fazę kohorty. Widoczne spadają ze stałą prędkością (T_FALL s
 * na wysokość ekranu) i splatują ślad co krok — wiersz przewija się w dół jak
 * na sonarze. Krótkie `life` akumulatora (0.2 s) daje wierszowi tylko cienki
 * ogon fosforu w górę, a gaśnięcie z głębokością wychodzi z mechaniki cząstek:
 * każda ma wylosowaną chwilę „śmierci” między FADE_FROM a końcem drogi, więc
 * gęstość druku (jasność wiersza) maleje liniowo ku dolnej krawędzi i przy
 * niej znika. Historia ≈ T_FALL s.
 *
 * Muzyka: bas = jasne kolumny po lewej, środek = w środku, wysokie = po prawej;
 * uderzenie (audio_beat) dodaje prawdopodobieństwo druku CAŁEMU wierszowi —
 * pozioma linia impulsu. Cisza: widmo = 0, drukuje tylko szum tła (NOISE,
 * modulowany wolnym fBm — dryfujące, ledwie widoczne pasma), więc ciemny
 * wodospad wciąż widocznie płynie.
 *
 * Stan: x = kolumna 0..1 (lub -1 = zaparkowana), y = wysokość 0..1,
 *       z = wiek w krokach, w = wcielenie (patrz engine.h).
 */
#pragma flux audio 1
#pragma flux particles 40320
#pragma flux life 0.2
#pragma flux rate 60
#pragma flux inc 1
#pragma flux gain 1
#pragma flux splat 0
#pragma flux seed 2047
#pragma flux audio_tempo 0
#pragma flux audio_glow 0

const float T_FALL    = 7.0;     /* sekundy: droga wiersza od górnej do dolnej krawędzi */
const float FADE_FROM = 0.35;    /* od tej części drogi wiersz zaczyna gasnąć (cząstki umierają) */
const float NOISE     = 0.05;    /* szum tła: prawdopodobieństwo druku bez sygnału (× fBm 0.5..1.5) */
const float BEAT_ROW  = 0.5;     /* uderzenie: dodatek do prawdopodobieństwa druku w całym wierszu */
const float KNEE      = 0.25;    /* poziom pasma poniżej tego = brak sygnału (podłoga AGC ≈ 0.3 w binach bez sygnału) */
const float GAMMA_IN  = 2.0;     /* (poziom − KNEE) → prawdopodobieństwo druku: kontrast wodospadu */
const float PHI       = 0.6180339887;
const int   BINS      = 32;

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    float age = s.z, gen = s.w;
    int   P   = textureSize(pos, 0).x;
    int   lin = idx.y * P + idx.x;
    float steps = T_FALL / dt;                  /* kroków na całą drogę */
    int   S     = int(steps + 0.5);
    int   slot  = lin % S;                      /* krok narodzin w cyklu (kohorta) */
    int   j     = lin / S;                      /* numer w kohorcie */

    if (age < 0.5) {
        /* start: rozłóż wiek tak, by kohorta `slot` rodziła się w kroku `slot` — zaparkowana */
        o = vec4(-1.0, 0.0, float(S - slot), 0.0);
        return;
    }
    if (age >= steps) {
        /* narodziny na górnej krawędzi: kolumna z ciągu złotego podziału z losowym
         * przesunięciem per kohorta, druk z prawdopodobieństwem = poziom pasma */
        float g = gen + 1.0;
        int   k = int(g);
        float x = fract(float(j) * PHI + h2(slot, k, seed));
        int   bin = clamp(int(x * float(BINS)), 0, BINS - 1);
        float lvl = texelFetch(audio_spectrum, ivec2(bin, 0), 0).r;
        float floorN = NOISE * (0.5 + fbm(vec2(x * 3.0, time * 0.15), 3, seed + 5));
        float pr = floorN + (1.0 - floorN) * pow(max(0.0, (lvl - KNEE) / (1.0 - KNEE)), GAMMA_IN);
        pr = min(1.0, pr + BEAT_ROW * audio_beat * audio_beat);
        bool on = h2(j + 101, k, seed + slot) < pr;
        o = vec4(on ? x : -1.0, 1.0 - 0.5 / resolution.y, 1.0, g);
        return;
    }
    /* lot w dół ze stałą prędkością; „śmierć” (parkowanie) w wylosowanym punkcie drogi */
    float y = s.y - dt / T_FALL;
    float x = s.x;
    float die_y = 1.0 - mix(FADE_FROM, 1.0, h2(j + 303, int(gen), seed + slot * 3));
    if (x >= 0.0 && y < die_y) x = -1.0;
    o = vec4(x, y, age + 1.0, gen);
}
