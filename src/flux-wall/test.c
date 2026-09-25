/*
 * archenemy - flux-wall: testy jednostkowe funkcji czystych (bez Waylanda/EGL).
 * Budowane przez `make test`: main.c wchodzi z main() przemianowanym na
 * flux_wall_main, więc tu jest własny main().
 */
#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "engine.h"
#include "audio.h"
#define TEST_PI 3.14159265f
#include <math.h>
#include <time.h>
bool  parse_hex_color(const char *hex, float out[3]);
bool  parse_palette(const char *spec, struct palette *p);
float battery_detail(const char *power_supply_dir);

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) printf("  ok   %s\n", msg); \
                              else { printf("  FAIL %s\n", msg); failures++; } } while (0)

static bool near(float a, float b) { return a - b < 0.002f && b - a < 0.002f; }

static void write_file(const char *path, const char *content) {
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); exit(1); }
    fputs(content, f);
    fclose(f);
}

int main(void) {
    float c[3];
    printf("parse_hex_color\n");
    CHECK(parse_hex_color("0F1A24", c) && near(c[0], 15/255.f) && near(c[1], 26/255.f) && near(c[2], 36/255.f), "0F1A24 bez #");
    CHECK(parse_hex_color("#D8E6EE", c) && near(c[0], 216/255.f) && near(c[2], 238/255.f), "#D8E6EE z #");
    CHECK(parse_hex_color("#d8e6ee", c) && near(c[0], 216/255.f), "małe litery");
    CHECK(!parse_hex_color("D8E6E", c),  "za krótki → odrzucony");
    CHECK(!parse_hex_color("D8E6EEFF", c), "z alfą (8 znaków) → odrzucony");
    CHECK(!parse_hex_color("GGGGGG", c), "nie-hex → odrzucony");
    CHECK(!parse_hex_color(NULL, c),     "NULL → odrzucony");
    CHECK(!parse_hex_color(" F1A24", c), "spacja w środku (strtol by ją łyknął) → odrzucony");
    CHECK(!parse_hex_color("-1-1-1", c), "znaki minus (strtol by je łyknął) → odrzucony");
    CHECK(!parse_hex_color("#-F-F-F", c), "z # i minusami → odrzucony");

    struct palette p;
    printf("parse_palette\n");
    CHECK(parse_palette("0F1A24,5C87A3,D8E6EE", &p) && near(p.ink[0], 92/255.f) && near(p.accent[1], 230/255.f), "trzy hexy");
    CHECK(parse_palette("#0F1A24,#5C87A3,#D8E6EE", &p), "trzy hexy z #");
    CHECK(!parse_palette("0F1A24,5C87A3", &p), "dwa hexy → odrzucone");
    CHECK(!parse_palette("0F1A24,5C87A3,D8E6EE,000000", &p), "cztery hexy → odrzucone");
    CHECK(!parse_palette("0F1A24,zzzzzz,D8E6EE", &p), "śmieć w środku → odrzucony");
    CHECK(!parse_palette("", &p), "pusty → odrzucony");

    /* Atrapa /sys/class/power_supply */
    char dir[] = "/tmp/flux-wall-test-XXXXXX";
    if (!mkdtemp(dir)) { perror("mkdtemp"); return 1; }
    char path[512];
    printf("battery_detail (atrapa: %s)\n", dir);

    CHECK(near(battery_detail(dir), 1.0f), "brak baterii → 1.0");

    snprintf(path, sizeof path, "%s/BAT0", dir); mkdir(path, 0755);
    snprintf(path, sizeof path, "%s/BAT0/capacity", dir); write_file(path, "42\n");
    snprintf(path, sizeof path, "%s/BAT0/status", dir);   write_file(path, "Discharging\n");
    CHECK(near(battery_detail(dir), 0.42f), "42% na baterii → 0.42");

    snprintf(path, sizeof path, "%s/BAT0/status", dir);   write_file(path, "Charging\n");
    CHECK(near(battery_detail(dir), 1.0f), "42% ale ładuje → 1.0 (zasilanie sieciowe)");

    write_file(path, "Full\n");
    CHECK(near(battery_detail(dir), 1.0f), "Full → 1.0");

    write_file(path, "Discharging\n");
    snprintf(path, sizeof path, "%s/BAT0/capacity", dir); write_file(path, "117\n");
    CHECK(near(battery_detail(dir), 1.0f), "capacity > 100 → przycięte do 1.0");

    write_file(path, "abc\n");
    CHECK(near(battery_detail(dir), 1.0f), "śmieć w capacity → pominięte → 1.0");

    /* BAT0 bez sensu, BAT1 sensowna — ma wziąć BAT1 */
    snprintf(path, sizeof path, "%s/BAT1", dir); mkdir(path, 0755);
    snprintf(path, sizeof path, "%s/BAT1/capacity", dir); write_file(path, "7\n");
    snprintf(path, sizeof path, "%s/BAT1/status", dir);   write_file(path, "Discharging\n");
    CHECK(near(battery_detail(dir), 0.07f), "BAT0 uszkodzona, BAT1 7% → 0.07");

    /* #pragma flux — parser parametrów animacji cząstkowej */
    printf("flux_params_parse\n");
    char err[256];
    struct flux_params fp = FLUX_PARAMS_DEFAULT;
    CHECK(flux_params_parse("// bez pragm\nvoid main(){}\n", &fp, err, sizeof err) && fp.particles == 20000 && near(fp.life, 4.0f), "brak pragm → domyślne");
    fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
    CHECK(flux_params_parse("#pragma flux particles 20800\n  #pragma flux life 4.3\n#pragma flux splat 1\n#pragma flux warm 20\n#pragma flux seed 7\n", &fp, err, sizeof err)
          && fp.particles == 20800 && near(fp.life, 4.3f) && fp.splat == 1 && fp.warm == 20 && fp.seed == 7, "pięć kluczy (w tym z wcięciem)");
    fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
    CHECK(!flux_params_parse("#pragma flux particles abc\n", &fp, err, sizeof err) && strstr(err, "nie jest liczbą"), "wartość nie-liczba → błąd");
    CHECK(!flux_params_parse("#pragma flux kolor 1\n", &fp, err, sizeof err) && strstr(err, "nieznany klucz"), "nieznany klucz → błąd");
    CHECK(!flux_params_parse("#pragma flux life 0\n", &fp, err, sizeof err) && strstr(err, "poza zakresem"), "life 0 → poza zakresem");
    CHECK(!flux_params_parse("#pragma flux splat 2\n", &fp, err, sizeof err), "splat 2 → poza zakresem");
    CHECK(!flux_params_parse("#pragma flux life\n", &fp, err, sizeof err) && strstr(err, "klucz wartość"), "brak wartości → błąd");
    CHECK(!flux_params_parse("#pragma flux life 4 5\n", &fp, err, sizeof err), "nadmiarowy token → błąd");
    fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
    CHECK(flux_params_parse("#pragma once\n#pragma fluxx 1 2\n", &fp, err, sizeof err) && fp.particles == 20000, "inne pragmy ignorowane");
    fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
    CHECK(fp.audio == 0 && fp.audio_tempo == 0.0f, "domyślnie bez dźwięku i bez reakcji");
    CHECK(flux_params_parse("#pragma flux audio 1\n#pragma flux audio_tempo 0.6\n", &fp, err, sizeof err) && fp.audio == 1 && near(fp.audio_tempo, 0.6f), "audio 1 + audio_tempo");
    CHECK(!flux_params_parse("#pragma flux audio 2\n", &fp, err, sizeof err), "audio 2 → poza zakresem");

    printf("flux_update_path\n");
    char up[64];
    CHECK(flux_update_path("shaders/dither-flow.frag", up, sizeof up) && strcmp(up, "shaders/dither-flow.update.glsl") == 0, ".frag → .update.glsl");
    CHECK(!flux_update_path("shaders/dither-flow.glsl", up, sizeof up), "nie-.frag → false");
    CHECK(!flux_update_path("shaders/dither-flow.frag", up, 8), "za mały bufor → false");

    /* ── DSP audio (czyste funkcje) ─────────────────────────────────────── */
    printf("audio_fft_power\n");
    static struct audio_fft fft; audio_fft_init(&fft);
    static float sig[AUDIO_FFT_N]; static float pw[AUDIO_FFT_N / 2 + 1];
    const float f44 = 44.0f * AUDIO_RATE / AUDIO_FFT_N;                 /* 1031.25 Hz = środek binu 44 */
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = sinf(2.0f * TEST_PI * f44 * (float)i / AUDIO_RATE);
    audio_fft_power(&fft, sig, pw);
    int kpeak = 0; for (int k = 1; k <= AUDIO_FFT_N / 2; k++) if (pw[k] > pw[kpeak]) kpeak = k;
    CHECK(kpeak == 44, "sinus 1031.25 Hz → pik w binie 44");
    CHECK(pw[kpeak] > 0.9f && pw[kpeak] < 1.1f, "moc piku ~1.0 (normalizacja)");
    CHECK(pw[kpeak + 10] < pw[kpeak] * 0.001f && pw[kpeak - 10] < pw[kpeak] * 0.001f, "10 binów dalej < -30 dB");
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.0f;
    audio_fft_power(&fft, sig, pw);
    float tot = 0; for (int k = 0; k <= AUDIO_FFT_N / 2; k++) tot += pw[k];
    CHECK(tot == 0.0f, "cisza → moc 0");

    printf("audio_bands\n");
    struct audio_bands_raw raw;
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.5f * sinf(2.0f * TEST_PI * 60.0f * (float)i / AUDIO_RATE);
    audio_fft_power(&fft, sig, pw);
    audio_bands(pw, AUDIO_FFT_N / 2 + 1, AUDIO_RATE, sig, AUDIO_FFT_N, &raw);
    CHECK(raw.bass > 5.0f * raw.mid && raw.bass > 5.0f * raw.high, "60 Hz → energia w basie, nie w mid/high");
    CHECK(raw.level > 0.34f && raw.level < 0.36f, "RMS sinusa 0.5 ≈ 0.354 (2.56 okresu w oknie)");
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.5f * sinf(2.0f * TEST_PI * 6000.0f * (float)i / AUDIO_RATE);
    audio_fft_power(&fft, sig, pw);
    audio_bands(pw, AUDIO_FFT_N / 2 + 1, AUDIO_RATE, sig, AUDIO_FFT_N, &raw);
    CHECK(raw.high > 5.0f * raw.bass && raw.high > 5.0f * raw.mid, "6 kHz → energia w high");
    int nz = 0; for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) if (raw.spectrum[i] > 0.01f) nz++;
    CHECK(nz >= 1 && nz <= 3, "6 kHz w widmie log: 1–3 biny");
    /* Regresja 2026-09-17: pasma log węższe niż bin FFT (48–57, 57–68, 98–117 Hz)
     * były martwe — sinus w środku każdego z nich musi dać energię W TYM binie. */
    int dead = 0;
    for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) {
        float lo = 40.0f * powf(300.0f, (float)i / AUDIO_SPECTRUM_BINS);
        float hi = 40.0f * powf(300.0f, (float)(i + 1) / AUDIO_SPECTRUM_BINS);
        float fc = sqrtf(lo * hi);
        for (int j = 0; j < AUDIO_FFT_N; j++) sig[j] = 0.5f * sinf(2.0f * TEST_PI * fc * (float)j / AUDIO_RATE);
        audio_fft_power(&fft, sig, pw);
        audio_bands(pw, AUDIO_FFT_N / 2 + 1, AUDIO_RATE, sig, AUDIO_FFT_N, &raw);
        int kmax = 0; for (int k = 1; k < AUDIO_SPECTRUM_BINS; k++) if (raw.spectrum[k] > raw.spectrum[kmax]) kmax = k;
        if (raw.spectrum[i] < 0.05f || abs(kmax - i) > 1) dead++;
    }
    CHECK(dead == 0, "każde z 32 pasm log reaguje na sinus w swoim środku (żadnych martwych słupków)");

    printf("audio_spectro_column / pasma spektrogramu\n");
    {
        /* sinus 1 kHz → maksimum spektrogramu w paśmie zawierającym 1 kHz */
        for (int j = 0; j < AUDIO_FFT_N; j++) sig[j] = 0.5f * sinf(2.0f * TEST_PI * 1000.0f * (float)j / AUDIO_RATE);
        audio_fft_power(&fft, sig, pw);
        audio_bands(pw, AUDIO_FFT_N / 2 + 1, AUDIO_RATE, sig, AUDIO_FFT_N, &raw);
        int expect = (int)floorf(logf(1000.0f / AUDIO_SPECTRO_LO) / logf(AUDIO_SPECTRO_HI / AUDIO_SPECTRO_LO) * AUDIO_SPECTRO_BINS);
        int smax = 0; for (int k = 1; k < AUDIO_SPECTRO_BINS; k++) if (raw.spectro[k] > raw.spectro[smax]) smax = k;
        CHECK(abs(smax - expect) <= 1, "1 kHz → maksimum w oczekiwanym paśmie spektrogramu (±1)");
        static float col[AUDIO_SPECTRO_BINS];
        audio_spectro_column(raw.spectro, raw.spectro[smax], col);
        CHECK(near(col[smax], 1.0f), "pasmo szczytowe = 1.0 (0 dB względem szczytu)");
        int lowcnt = 0; for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) if (abs(k - smax) > 8 && col[k] > 0.3f) lowcnt++;
        CHECK(lowcnt == 0, "daleko od tonu < 0.3 (poniżej -42 dB)");
        float half[AUDIO_SPECTRO_BINS]; for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) half[k] = raw.spectro[k];
        half[smax] = raw.spectro[smax] * 0.1f;                   /* -20 dB */
        audio_spectro_column(half, raw.spectro[smax], col);
        CHECK(near(col[smax], 1.0f - 20.0f / AUDIO_SPECTRO_RANGE_DB), "-20 dB → 1 - 20/60");
        for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) half[k] = 0.0f;
        audio_spectro_column(half, 0.0f, col);
        int z = 0; for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) if (col[k] != 0.0f) z++;
        CHECK(z == 0, "cisza (peak 0) → cała kolumna 0");
    }

    printf("audio_trigger / audio_wave_fill\n");
    {
        static float mono[AUDIO_FFT_N], lft[AUDIO_FFT_N], rgt[AUDIO_FFT_N];
        /* sinus 100 Hz: okres 480 próbek; trigger ma zwrócić start na zboczu narastającym */
        for (int i = 0; i < AUDIO_FFT_N; i++) { mono[i] = 0.5f * sinf(2.0f * TEST_PI * 100.0f * (float)i / AUDIO_RATE); lft[i] = mono[i]; rgt[i] = -mono[i]; }
        int st1 = audio_trigger(mono, AUDIO_FFT_N, AUDIO_WAVE_N, 0.01f);
        CHECK(st1 >= 0 && st1 <= AUDIO_FFT_N - AUDIO_WAVE_N, "start mieści okno w buforze");
        CHECK(mono[st1] >= 0.0f && mono[st1] < 0.05f && mono[st1 + 10] > mono[st1], "start = zbocze narastające przy zerze");
        /* przesunięcie sygnału o 100 próbek → ślad ma zaczynać się w tej samej fazie */
        for (int i = 0; i < AUDIO_FFT_N; i++) mono[i] = 0.5f * sinf(2.0f * TEST_PI * 100.0f * (float)(i + 100) / AUDIO_RATE);
        int st2 = audio_trigger(mono, AUDIO_FFT_N, AUDIO_WAVE_N, 0.01f);
        CHECK(fabsf(mono[st2] - lft[st1]) < 0.02f && fabsf(mono[st2 + 50] - lft[st1 + 50]) < 0.02f, "po przesunięciu o 100 próbek okno stoi w tej samej fazie");
        for (int i = 0; i < AUDIO_FFT_N; i++) mono[i] = 0.0f;
        CHECK(audio_trigger(mono, AUDIO_FFT_N, AUDIO_WAVE_N, 0.01f) == AUDIO_FFT_N - AUDIO_WAVE_N, "cisza → najświeższe okno");
        for (int i = 0; i < AUDIO_FFT_N; i++) mono[i] = 0.004f * ((i & 1) ? 1.0f : -1.0f);
        CHECK(audio_trigger(mono, AUDIO_FFT_N, AUDIO_WAVE_N, 0.01f) == AUDIO_FFT_N - AUDIO_WAVE_N, "szum pod histerezą nie wyzwala triggera");
        struct audio_features wf; memset(&wf, 0, sizeof wf);
        for (int i = 0; i < AUDIO_FFT_N; i++) { lft[i] = 2.0f; rgt[i] = -0.25f; }
        audio_wave_fill(&wf, lft, rgt, AUDIO_FFT_N, AUDIO_FFT_N - AUDIO_WAVE_N);
        CHECK(wf.wave[0] == 1.0f && wf.wave[1] == -0.25f && wf.wave[2 * (AUDIO_WAVE_N - 1)] == 1.0f, "wave_fill: przeplot L/R i przycięcie do ±1");
        audio_wave_fill(&wf, lft, rgt, AUDIO_FFT_N, AUDIO_FFT_N);   /* start poza buforem → dosunięty */
        CHECK(wf.wave[2 * (AUDIO_WAVE_N - 1)] == 1.0f, "wave_fill: start poza buforem dosunięty do końca");
    }

    printf("audio_agc_step / audio_smooth\n");
    struct audio_agc agc = {0};
    CHECK(near(audio_agc_step(&agc, 0.5f, 0.02f, 0.004f), 1.0f), "pierwszy sygnał → 1.0 (peak = x)");
    CHECK(audio_agc_step(&agc, 0.25f, 0.02f, 0.004f) < 0.55f, "połowa peaku → ~0.5");
    for (int i = 0; i < 1000; i++) audio_agc_step(&agc, 0.0f, 0.02f, 0.004f);  /* 20 s ciszy (stała 2 s) */
    CHECK(near(agc.peak, 0.004f), "po 20 s peak opada do podłogi");
    CHECK(near(audio_agc_step(&agc, 0.002f, 0.02f, 0.004f), 0.5f), "sygnał pod podłogą → x/podłoga, nie 1.0");
    float sm = audio_smooth(0.0f, 1.0f, 0.02f, 0.03f, 0.25f);
    float sd = audio_smooth(1.0f, 0.0f, 0.02f, 0.03f, 0.25f);
    CHECK(sm > 0.4f && sd > 0.9f, "atak szybki (0→0.49), opadanie wolne (1→0.92)");

    printf("audio_beat_step\n");
    struct audio_beat bt = {0};
    int hits = 0;
    for (int i = 0; i < 110; i++) {                       /* impulsy co 500 ms, pierwszy po 200 ms */
        bool imp = (i % 25 == 10);
        float o = audio_beat_step(&bt, imp ? 1.0f : 0.1f, 0.02f);
        if (imp && o >= 0.99f) hits++;
    }
    CHECK(hits == 4, "4 impulsy co 500 ms → 4 detekcje");
    struct audio_beat bt2 = {0}; int onsets = 0;
    for (int i = 0; i < 100; i++) if (audio_beat_step(&bt2, 0.8f, 0.02f) >= 0.99f) onsets++;
    CHECK(onsets == 1, "ton ciągły → dokładnie jeden onset, bez serii");

    printf("audio_features_age\n");
    struct audio_features fe = { .level = 1.0f, .bass = 1.0f, .t = 10.0 };
    audio_features_age(&fe, 10.05, 0.25f);
    CHECK(near(fe.bass, 1.0f), "50 ms → bez zmian");
    audio_features_age(&fe, 10.6, 0.25f);
    CHECK(fe.bass < 0.2f, "500 ms → zgaszone");

    printf("audio_analyze (cały łańcuch)\n");
    static struct audio_state st; audio_state_init(&st);
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.5f * sinf(2.0f * TEST_PI * 60.0f * (float)i / AUDIO_RATE);
    for (int i = 0; i < 20; i++) audio_analyze(&st, sig, 0.02f, 1.0 + i * 0.02);
    CHECK(st.out.bass > 0.8f && st.out.high < 0.2f, "bas 60 Hz przez 0.4 s → bass ~1, high ~0");
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.0f;
    for (int i = 0; i < 50; i++) audio_analyze(&st, sig, 0.02f, 2.0 + i * 0.02);
    CHECK(st.out.bass < 0.05f && st.out.level < 0.05f, "cisza 1 s → wszystko ~0");
    { int z = 0; for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) if (st.out.spectro[k] != 0.0f) z++;
      CHECK(z == 0, "cisza → kolumna spektrogramu dokładnie 0"); }
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.5f * sinf(2.0f * TEST_PI * 1000.0f * (float)i / AUDIO_RATE);
    for (int i = 0; i < 10; i++) audio_analyze(&st, sig, 0.02f, 3.0 + i * 0.02);
    { int smax = 0; for (int k = 1; k < AUDIO_SPECTRO_BINS; k++) if (st.out.spectro[k] > st.out.spectro[smax]) smax = k;
      int expect = (int)floorf(logf(1000.0f / AUDIO_SPECTRO_LO) / logf(AUDIO_SPECTRO_HI / AUDIO_SPECTRO_LO) * AUDIO_SPECTRO_BINS);
      /* szczyt AGC z basu 60 Hz jeszcze nie opadł (zanik ~2 s) → ton 1 kHz kilka dB pod 0 dB, ale > 0.9 */
      CHECK(abs(smax - expect) <= 1 && st.out.spectro[smax] > 0.9f, "ton 1 kHz w łańcuchu → szczyt spektrogramu > 0.9 we właściwym paśmie"); }

    printf("audio_start z pliku (wątek, bez serwera)\n");
    {
        char fpath[512]; snprintf(fpath, sizeof fpath, "%s/tone.f32", dir);
        FILE *tf = fopen(fpath, "wb");
        /* stereo przeplatane: L = 80 Hz, R = cisza → miks ma bas, przebieg R pusty */
        for (int i = 0; i < AUDIO_RATE; i++) {
            float v = 0.5f * sinf(2.0f * TEST_PI * 80.0f * (float)i / AUDIO_RATE), z = 0.0f;
            fwrite(&v, sizeof v, 1, tf); fwrite(&z, sizeof z, 1, tf);
        }
        fclose(tf);
        struct audio *au = audio_start(NULL, fpath, false);
        CHECK(au != NULL, "wątek wystartował");
        struct timespec ts = { 0, 400000000L }; nanosleep(&ts, NULL);
        struct audio_features snap; audio_snapshot(au, &snap);
        CHECK(snap.live && snap.bass > 0.5f && snap.t > 0.0, "po 0.4 s: live, bass > 0.5, znacznik czasu");
        float maxl = 0, maxr = 0;
        for (int i = 0; i < AUDIO_WAVE_N; i++) { if (fabsf(snap.wave[2*i]) > maxl) maxl = fabsf(snap.wave[2*i]); if (fabsf(snap.wave[2*i+1]) > maxr) maxr = fabsf(snap.wave[2*i+1]); }
        CHECK(maxl > 0.45f && maxr == 0.0f, "przebieg: L ma sinus 0.5, R jest ciszą (stereo rozdzielone)");
        CHECK(snap.wave[0] >= 0.0f && snap.wave[0] < 0.1f && snap.wave[2 * 30] > snap.wave[0], "trigger: okno zaczyna się na narastającym przejściu przez zero");
        audio_stop(au);
        remove(fpath);
    }

    /* sprzątanie */
    const char *files[] = { "BAT0/capacity", "BAT0/status", "BAT1/capacity", "BAT1/status", "BAT0", "BAT1", NULL };
    for (int i = 0; files[i]; i++) { snprintf(path, sizeof path, "%s/%s", dir, files[i]); remove(path); }
    rmdir(dir);

    printf("%s: %d błędów\n", failures ? "WYNIK" : "WSZYSTKO OK", failures);
    return failures ? 1 : 0;
}
