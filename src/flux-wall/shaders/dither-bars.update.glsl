/*
 * archenemy — flux-wall: „dither-bars” — słupki widma jak w cavie, krok cząstki.
 *
 * Cząstki nie są tu pyłem, tylko PAMIĘCIĄ między klatkami (przebieg finalny
 * nie ma własnego stanu):
 *   - id 0..63  — po jednej na słupek: trzymają wysokość szczytu (peak hold).
 *     Szczyt skacze w górę razem ze słupkiem, trzyma się PEAK_HOLD sekund,
 *     potem opada coraz szybciej (grawitacja PEAK_GRAV), wolniej niż słupek.
 *     Cząstka stoi w środkowej kolumnie pikseli swojego słupka i co krok
 *     stempluje akumulator w wierszu szczytu — .frag czyta ten jeden teksel
 *     i rozciąga go w kreskę na całą szerokość słupka; ślad w akumulatorze
 *     gaśnie z `life`, więc po kresce zostaje krótka poświata jak na fosforze.
 *   - id 64..   — iskry: rodzą się na końcówce słupka, lecą pionowo w górę i
 *     gasną; częściej, gdy pasmo gra głośno, przy wysokich i na uderzeniu.
 *     Nigdy nie wchodzą w środkową kolumnę słupka (tam mieszka szczyt).
 * W ciszy: szczyty leżą na wysokości bazowej, iskier prawie nie ma (rzadkie,
 * wolne żarzenie znad linii bazowej — obraz żyje, ale nie krzyczy).
 *
 * Stan: xy = pozycja w 0..1 ekranu, z = wiek w krokach (szczyt: od ostatniego
 * podbicia), w = wcielenie (szczyt: numer podbicia; iskra: numer lotu).
 * Stałe układu (BARS, BASE_FRAC, BAR_BASE, BAR_MAX, MARK_GAP, bar_center)
 * muszą być 1:1 z dither-bars.frag.
 * `particles 184`: 0.35·184 = 64 aktywnych przy detail 0 — szczyty działają
 * zawsze, iskry (id ≥ 64) dochodzą z detail. audio_tempo 0: czas symulacji
 * = czas realny, więc PEAK_HOLD jest w sekundach zegara.
 */
#pragma flux audio 1
#pragma flux particles 184
#pragma flux life 0.12
#pragma flux rate 60
#pragma flux inc 0.05
#pragma flux gain 10
#pragma flux splat 0
#pragma flux seed 2041
#pragma flux audio_tempo 0
#pragma flux audio_glow 0.5

const int   P         = 14;      /* bok siatki cząstek: ceil(sqrt(184)) */
const int   BARS      = 64;      /* 32 biny × 2 (lustro: bas w środku) */
const float BASE_FRAC = 0.12;    /* linia bazowa: ułamek wysokości ekranu od dołu */
const float BAR_BASE  = 3.0;     /* px: wysokość w ciszy */
const float BAR_MAX   = 0.40;    /* ułamek wysokości ekranu przy pełnym paśmie */
const float MARK_GAP  = 2.0;     /* px: szczelina słupek → kreska szczytu */
const float PEAK_HOLD = 0.40;    /* s: ile kreska trzyma się na szczycie */
const float PEAK_GRAV = 900.0;   /* px/s²: opadanie po zwolnieniu (v = grav · t) */
const float SPARK_MAX = 0.9;     /* s: najdłuższy lot iskry */

int bar_bin(int i) { return i < 32 ? 31 - i : i - 32; }   /* lustro */

/* Środkowa kolumna pikseli słupka `i` — ta sama formuła, co w .frag. */
int bar_center(int i) {
    float sw = resolution.x / float(BARS);
    int x0 = int(floor(float(i) * sw)), x1 = int(floor(float(i + 1) * sw));
    return (x0 + x1) / 2;
}

float spectrum(int bin) { return texelFetch(audio_spectrum, ivec2(clamp(bin, 0, 31), 0), 0).r; }

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    int   id  = idx.y * P + idx.x;
    vec4  s   = texelFetch(pos, idx, 0);
    float age = s.z, gen = s.w;

    float y_base = floor(resolution.y * BASE_FRAC);

    if (id < BARS) {
        /* ── szczyt słupka ───────────────────────────────────────────── */
        int   i     = id;
        float lvl   = spectrum(bar_bin(i));
        float h     = BAR_BASE + lvl * BAR_MAX * resolution.y;   /* px nad linią bazową */
        float peak  = s.y * resolution.y - y_base - MARK_GAP;     /* poprzedni szczyt (px nad bazą) */
        if (age < 0.5) peak = 0.0;                                /* pierwszy krok: stan zerowy */
        float t_age = age * dt;
        float v     = PEAK_GRAV * max(0.0, t_age - PEAK_HOLD);    /* px/s po zwolnieniu */
        peak -= v * dt;
        if (h >= peak) { peak = h; age = 0.0; gen += 1.0; }       /* podbicie: nowy szczyt, licznik od zera */
        peak = max(peak, BAR_BASE);
        float px = (float(bar_center(i)) + 0.5) / resolution.x;
        float py = (floor(y_base + peak + MARK_GAP) + 0.5) / resolution.y;
        o = vec4(px, py, age + 1.0, gen);
        return;
    }

    /* ── iskra ─────────────────────────────────────────────────────────── */
    int   i    = (id - BARS) % BARS;
    float lvl  = spectrum(bar_bin(i));
    bool  idle = age < 0.5 || s.y > 1.02 || age * dt > SPARK_MAX;
    if (idle) {
        /* szansa na start w tym kroku: pasmo + wysokie + uderzenie; w ciszy rzadkie żarzenie */
        float rate = 0.003 + lvl * (0.15 + 2.5 * audio_high) + 3.0 * audio_beat * lvl;   /* startów/s na iskrę */
        float roll = h2(idx.x + 31, idx.y + 17 * int(gen), seed + int(time * 60.0));
        if (roll > rate * dt) { o = vec4(-1.0, -1.0, 0.0, gen); return; }
        float g    = gen + 1.0;
        float sw   = resolution.x / float(BARS);
        int   xc   = bar_center(i);
        int   halfw = max(int(sw * 0.35), 1);
        int   off  = int(h2(idx.x, idx.y, seed + int(g) * 13) * float(2 * halfw - 1)) - halfw + 1;   /* -halfw+1..halfw-1 */
        if (off >= 0) off += 1;                                   /* nigdy kolumna środkowa */
        float h    = BAR_BASE + lvl * BAR_MAX * resolution.y;
        float px   = (float(xc + off) + 0.5) / resolution.x;
        float py   = (y_base + h + 1.0) / resolution.y;
        o = vec4(px, py, 1.0, g);
        return;
    }
    /* lot: pionowo w górę, prędkość z pasma i wysokich, z osobistą domieszką */
    float k   = 0.6 + 0.8 * h2(idx.x + 5, idx.y + 9, seed + int(gen) * 13);
    float vy  = (40.0 + 260.0 * lvl + 220.0 * audio_high) * k;   /* px/s */
    float y   = s.y + vy * dt / resolution.y;
    o = vec4(s.x, y, age + 1.0, gen);
}
