/*
 * archenemy - flux-wall: analiza dźwięku z WYJŚCIA systemu (monitor sinku).
 *
 * Wątek czyta próbki przez libpulse-simple (pipewire-pulse), liczy co ~20 ms
 * FFT 2048 z oknem Hanna i sprowadza widmo do pasm jak w wizualizerach:
 *   bass 20–150 Hz · lowmid 150–500 · mid 500–2000 · high 2000–10000
 * plus poziom RMS, detektor uderzenia (onset basu) i 32 biny log-freq.
 * Od 2026-09-17 strumień jest STEREO: FFT/pasma liczone z miksu (L+R)/2,
 * a osobno trzymany jest PRZEBIEG (ostatnie AUDIO_WAVE_N próbek L i R) dla
 * wizualizacji oscyloskopowych — z triggerem jak w prawdziwym oscyloskopie
 * (start okna na ostatnim narastającym przejściu przez zero, żeby ślad
 * okresowego tonu stał w miejscu zamiast skakać co klatkę).
 * Każde pasmo przechodzi auto-gain (bieżące maksimum z zanikiem, z podłogą)
 * i wygładzanie attack/release — wynik w 0..1, w ciszy dokładnie 0.
 *
 * Wątek nie dotyka GL ani Waylanda. Render bierze snapshot pod mutexem raz na
 * klatkę. Snapshot ma znacznik czasu: gdy sink śpi, `pa_simple_read` blokuje
 * bez końca — stęchłe wartości gasi audio_features_age() po stronie renderu.
 *
 * Nigdy mikrofon: urządzenie to zawsze MONITOR sinku (`@DEFAULT_MONITOR@`
 * albo `<sink>.monitor` z wrappera). Brak serwera = praca bez audio, backoff.
 *
 * Funkcje czyste (bez wątku, bez libpulse) są testowane w test.c.
 */
#ifndef FLUX_AUDIO_H
#define FLUX_AUDIO_H

#include <stdbool.h>
#include <stddef.h>

#define AUDIO_RATE          48000
#define AUDIO_FFT_N         2048
#define AUDIO_HOP           960      /* 20 ms */
#define AUDIO_SPECTRUM_BINS 32
#define AUDIO_WAVE_N        1024     /* próbek przebiegu dla shaderów (21 ms) */
#define AUDIO_CHANNELS      2
/* Spektrogram: drobne pasma log-freq (40 Hz – 16 kHz) w skali dB względem
 * wolnego szczytu globalnego (NIE per pasmo — spektrogram ma pokazywać
 * prawdziwe proporcje między częstotliwościami, a auto-gain per pasmo by je
 * spłaszczył). Historia kolumn żyje w silniku (tekstura), nie tutaj. */
#define AUDIO_SPECTRO_BINS  128
#define AUDIO_SPECTRO_LO    40.0f
#define AUDIO_SPECTRO_HI    16000.0f
#define AUDIO_SPECTRO_RANGE_DB 60.0f

/* Cechy dźwięku dla silnika — wszystko w 0..1, `beat` to impuls z zanikiem. */
struct audio_features {
    float level, bass, lowmid, mid, high, beat;
    float spectrum[AUDIO_SPECTRUM_BINS];
    /* przebieg po triggerze: wave[2*i] = L, wave[2*i+1] = R, i = 0..AUDIO_WAVE_N-1,
     * próbki w -1..1 (bez auto-gain — oscyloskop ma pokazywać prawdziwą amplitudę,
     * a `level` mówi shaderowi, jak głośno jest) */
    float wave[AUDIO_WAVE_N * AUDIO_CHANNELS];
    float wave_peak;   /* szczyt max(|L|,|R|) w oknie przebiegu (0..1) — auto-wzmocnienie oscyloskopu */
    /* kolumna spektrogramu: 0..1 = -RANGE_DB..0 dB względem szczytu globalnego; cisza = 0 */
    float spectro[AUDIO_SPECTRO_BINS];
    double t;        /* czas snapshotu (sekundy, zegar monotoniczny); 0 = nigdy */
    bool   live;     /* strumień z serwera działa */
};

/* ── czyste ─────────────────────────────────────────────────────────────── */

struct audio_fft {
    float window[AUDIO_FFT_N];
    float cos_t[AUDIO_FFT_N / 2], sin_t[AUDIO_FFT_N / 2];
    int   bitrev[AUDIO_FFT_N];
    float re[AUDIO_FFT_N], im[AUDIO_FFT_N];
};
void audio_fft_init(struct audio_fft *f);
/* Moc widma: `power[k]` dla k = 0..N/2 (N/2+1 wartości), okno Hanna. */
void audio_fft_power(struct audio_fft *f, const float *in, float *power);

/* Surowe pasma z mocy widma i RMS z próbek czasu (bez auto-gain). */
struct audio_bands_raw { float level, bass, lowmid, mid, high; float spectrum[AUDIO_SPECTRUM_BINS]; float spectro[AUDIO_SPECTRO_BINS]; };
void audio_bands(const float *power, int n_power, float sample_rate,
                 const float *samples, int n_samples, struct audio_bands_raw *out);

/* Auto-gain: dzieli przez bieżące maksimum (zanik ~2 s), podłoga chroni ciszę
 * przed wzmocnieniem do pełnej reakcji. Zwraca x/peak przycięte do 0..1. */
struct audio_agc { float peak; };
float audio_agc_step(struct audio_agc *a, float x, float dt, float floor_value);

/* Wygładzanie asymetryczne: szybki atak, wolne opadanie (stałe w sekundach). */
float audio_smooth(float prev, float x, float dt, float attack, float release);

/* Detektor uderzenia: onset basu względem średniej kroczącej (~1 s), nie
 * częściej niż co 150 ms; wyjście 1.0 z zanikiem ~100 ms. */
struct audio_beat { float avg; float since; float out; };
float audio_beat_step(struct audio_beat *b, float bass, float dt);

/* Trigger oscyloskopu: w buforze `mono` (n próbek, najnowsza na końcu) szuka
 * NAJPÓŹNIEJSZEGO narastającego przejścia przez zero (z histerezą `hyst`), po
 * którym mieści się jeszcze `span` próbek; zwraca indeks startu okna.
 * Bez przejścia (cisza, DC) → n - span (najświeższe okno). */
int audio_trigger(const float *mono, int n, int span, float hyst);

/* Wypełnia `out->wave` (L/R przeplatane) oknem `span` próbek od `start`
 * z buforów L i R długości n. */
void audio_wave_fill(struct audio_features *out, const float *l, const float *r, int n, int start);

/* Kolumna spektrogramu ze SUROWYCH pasm: dB względem `peak` (szczyt globalny
 * po auto-gain), zakres AUDIO_SPECTRO_RANGE_DB → 0..1. Czyste, testowane. */
void audio_spectro_column(const float *raw, float peak, float *out);

/* Zanik stęchłego snapshotu: gdy `now - t` > 0.1 s, cechy gasną z `release`. */
void audio_features_age(struct audio_features *f, double now, float release);

/* Pełna analiza jednego okna (N próbek) → cechy; stan między wywołaniami w `st`.
 * To jest to, co wątek robi co hop — wystawione, żeby testy szły bez wątku. */
struct audio_state {
    struct audio_fft  fft;
    float             power[AUDIO_FFT_N / 2 + 1];
    struct audio_agc  agc_level, agc_bass, agc_lowmid, agc_mid, agc_high, agc_spec[AUDIO_SPECTRUM_BINS];
    struct audio_agc  agc_spectro;   /* JEDEN szczyt dla całej kolumny spektrogramu */
    struct audio_beat beat;
    struct audio_features out;
};
void audio_state_init(struct audio_state *st);
void audio_analyze(struct audio_state *st, const float *window, float dt, double now);

/* ── wątek ──────────────────────────────────────────────────────────────── */

struct audio;
/* `device`: nazwa monitora dla libpulse (NULL = tylko `@DEFAULT_MONITOR@`);
 * silnik próbuje najpierw `@DEFAULT_MONITOR@`, potem `device`.
 * `file`: zamiast serwera — surowy float32 STEREO (przeplatane L R) 48 kHz,
 * czytany w tempie realnym i zapętlony (tryb debug/testy). NULL przy braku
 * pamięci/wątku. */
struct audio *audio_start(const char *device, const char *file, bool verbose);
void audio_snapshot(struct audio *a, struct audio_features *out);
void audio_stop(struct audio *a);

#endif
