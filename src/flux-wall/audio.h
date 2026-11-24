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
 * Pasma bass/lowmid/mid/high i poziom przechodzą auto-gain per pasmo (bieżące
 * maksimum z zanikiem, z podłogą) i wygładzanie attack/release — wynik w 0..1,
 * w ciszy dokładnie 0. Widmo 32 binów (słupki) ma JEDEN wspólny szczyt i skalę
 * dB — pokazuje kształt muzyki, nie każdy bin względem samego siebie.
 *
 * Wątek nie dotyka GL ani Waylanda. Render bierze snapshot pod mutexem raz na
 * klatkę. Snapshot ma znacznik czasu: gdy sink śpi, `pa_simple_read` blokuje
 * bez końca — stęchłe wartości gasi audio_features_age() po stronie renderu.
 *
 * Nigdy mikrofon: urządzenie to zawsze MONITOR sinku (`@DEFAULT_MONITOR@`
 * albo `<sink>.monitor` z wrappera). Brak serwera albo zerwany strumień =
 * praca bez audio i ponowienie po pauzie (1 s, podwajanej do ~30 s; wraca do
 * 1 s dopiero po odebranych danych).
 *
 * Funkcje czyste (bez wątku, bez libpulse) są testowane w test.c; wątek —
 * z plikiem (`--audio-file`) i z atrapą libpulse (zerwany strumień).
 */
#ifndef FLUX_AUDIO_H
#define FLUX_AUDIO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>

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
#define AUDIO_SPECTRUM_RANGE_DB 45.0f   /* widmo 32 binów: zakres dB pod wspólnym szczytem */

/* Cechy dźwięku dla silnika — wszystko w 0..1, `beat` to impuls z zanikiem. */
struct audio_features {
    float level, bass, lowmid, mid, high, beat;
    /* widmo 32 binów log-freq (40 Hz – 12 kHz): 0..1 = -AUDIO_SPECTRUM_RANGE_DB..0 dB
     * względem najgłośniejszego binu z ostatnich ~2 s, wygładzone attack/release */
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
    /* surowy RMS okna analizy (0..1, PRZED auto-gain i wygładzaniem) — tylko
     * diagnostyka: log `-v` pokazuje, czy do flux-walla w ogóle dociera dźwięk
     * i jak głośny (cechy wyżej są już znormalizowane, więc tego nie powiedzą) */
    float  raw_level;
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
/* `spectrum[i]` to ENERGIA binu log-freq (pierwiastek z sumy mocy binów FFT
 * w paśmie), pozostałe pola — średnia (RMS na bin FFT). Biny log mają stałą
 * szerokość w oktawach, więc energia jest równa dla szumu różowego (równa moc
 * na oktawę, typowe nachylenie muzyki); średnia opadałaby o 3 dB na oktawę
 * i góra widma leżałaby przy każdej muzyce. */
struct audio_bands_raw { float level, bass, lowmid, mid, high; float spectrum[AUDIO_SPECTRUM_BINS]; float spectro[AUDIO_SPECTRO_BINS]; };
void audio_bands(const float *power, int n_power, float sample_rate,
                 const float *samples, int n_samples, struct audio_bands_raw *out);

/* Auto-gain: dzieli przez bieżące maksimum (zanik ~2 s), podłoga chroni ciszę
 * przed wzmocnieniem do pełnej reakcji. Zwraca x/peak przycięte do 0..1.
 * x NaN/inf (moc FFT przepełniona olbrzymią próbką) liczy się jak 0,
 * a szczyt NaN/inf wraca do podłogi — wynik zawsze skończony. */
struct audio_agc { float peak; };
float audio_agc_step(struct audio_agc *a, float x, float dt, float floor_value);

/* Wygładzanie asymetryczne: szybki atak, wolne opadanie (stałe w sekundach).
 * x NaN/inf → zostaje prev; prev NaN/inf → liczy od 0 (stan wychodzi z NaN). */
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

/* `n` surowych pasm → dB względem wspólnego szczytu `peak`, zakres `range_db`
 * przeskalowany na 0..1 (0 dB = 1, -range_db i mniej = 0; peak <= 0 → zera). */
void audio_db_column(const float *raw, int n, float peak, float range_db, float *out);
/* Kolumna spektrogramu ze SUROWYCH pasm: dB względem `peak` (szczyt globalny
 * po auto-gain), zakres AUDIO_SPECTRO_RANGE_DB → 0..1. Czyste, testowane. */
void audio_spectro_column(const float *raw, float peak, float *out);

/* Zanik stęchłego snapshotu: gdy `now - t` > 0.1 s, cechy gasną z `release`. */
void audio_features_age(struct audio_features *f, double now, float release);

/* Próbka wejściowa (serwer dźwięku, plik): NaN i ±inf → 0, reszta bez zmian.
 * Jedna taka próbka w oknie FFT zatruwała auto-gain, wygładzanie i średnią
 * beatu na stałe (NaN nie wychodzi z rekurencji) — wizualizacja stała do
 * restartu. Wołają ją wszyscy, którzy dosuwają próbki do okna analizy.
 * Skończonych olbrzymich próbek nie przycina: moc FFT = inf z nich łapią
 * audio_agc_step i audio_smooth. */
float audio_sample_clean(float x);

/* Pełna analiza jednego okna (N próbek) → cechy; stan między wywołaniami w `st`.
 * To jest to, co wątek robi co hop — wystawione, żeby testy szły bez wątku. */
struct audio_state {
    struct audio_fft  fft;
    float             power[AUDIO_FFT_N / 2 + 1];
    struct audio_agc  agc_level, agc_bass, agc_lowmid, agc_mid, agc_high;
    /* JEDEN szczyt dla 32 binów widma (decyzja właściciela 2026-11-24, 1A):
     * dawny szczyt per bin normalizował każdy słupek do samego siebie i przy
     * muzyce prawie wszystkie stały wysoko (audyt 2026-11-24, U1) */
    struct audio_agc  agc_spectrum;
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

/* Diagnostyka (bez `-v`): pierwsze połączenie ze strumieniem i pierwsza
 * porażka ZAWSZE trafiają do logu, razem z nazwą źródła — bez tego brak
 * serwera albo zły monitor wyglądał jak „wizualizacja nie działa” i nie
 * zostawiał śladu (audyt 2026-11-24, U4). Potem log tylko przy zmianie stanu
 * (połączony ↔ zerwany), więc ponawianie co 1–30 s go nie zalewa.
 * audio_log_stream: gdzie pisać (NULL = stderr, czyli flux-wall.log wrappera);
 * testy podają własny strumień. Ustawiać PRZED audio_start. */
void audio_log_stream(FILE *f);
/* Nazwa źródła, z którego idzie strumień (`@DEFAULT_MONITOR@`, nazwa z
 * --audio-device albo ścieżka --audio-file); pusty napis = brak połączenia. */
void audio_source(struct audio *a, char *out, size_t outlen);

#endif
