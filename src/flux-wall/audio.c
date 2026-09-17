/*
 * archenemy - flux-wall: analiza dźwięku — patrz audio.h.
 */
#define _GNU_SOURCE          /* pthread_timedjoin_np */
#include "audio.h"

#include <errno.h>
#include <math.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <pulse/simple.h>
#include <pulse/error.h>

/* ── FFT radix-2 (własna — bez zależności) ───────────────────────────────── */

void audio_fft_init(struct audio_fft *f) {
    const int N = AUDIO_FFT_N;
    for (int i = 0; i < N; i++)
        f->window[i] = 0.5f - 0.5f * cosf(2.0f * (float)M_PI * (float)i / (float)(N - 1));
    for (int i = 0; i < N / 2; i++) {
        f->cos_t[i] = cosf(2.0f * (float)M_PI * (float)i / (float)N);
        f->sin_t[i] = sinf(2.0f * (float)M_PI * (float)i / (float)N);
    }
    int bits = 0;
    while ((1 << bits) < N) bits++;
    for (int i = 0; i < N; i++) {
        int r = 0;
        for (int b = 0; b < bits; b++) r |= ((i >> b) & 1) << (bits - 1 - b);
        f->bitrev[i] = r;
    }
}

void audio_fft_power(struct audio_fft *f, const float *in, float *power) {
    const int N = AUDIO_FFT_N;
    for (int i = 0; i < N; i++) {
        f->re[f->bitrev[i]] = in[i] * f->window[i];
        f->im[f->bitrev[i]] = 0.0f;
    }
    for (int len = 2; len <= N; len <<= 1) {
        int half = len >> 1, step = N / len;
        for (int i = 0; i < N; i += len) {
            for (int j = 0; j < half; j++) {
                float wr = f->cos_t[j * step], wi = -f->sin_t[j * step];
                float xr = f->re[i + j + half], xi = f->im[i + j + half];
                float tr = xr * wr - xi * wi, ti = xr * wi + xi * wr;
                f->re[i + j + half] = f->re[i + j] - tr;
                f->im[i + j + half] = f->im[i + j] - ti;
                f->re[i + j] += tr;
                f->im[i + j] += ti;
            }
        }
    }
    /* Normalizacja: sinus o amplitudzie 1 trafiony w środek binu daje po oknie
     * Hanna amplitudę N/4 (okno gubi połowę, widmo dwustronne drugą) — skalujemy
     * tak, żeby taki sinus dawał moc 1.0. Częstotliwość między binami rozlewa
     * się na sąsiednie (suma zostaje). */
    float norm = 16.0f / ((float)N * (float)N);
    for (int k = 0; k <= N / 2; k++)
        power[k] = (f->re[k] * f->re[k] + f->im[k] * f->im[k]) * norm;
}

/* ── pasma ──────────────────────────────────────────────────────────────── */

/* RMS pasma [lo, hi) Hz liczony z UŁAMKOWYM pokryciem binów FFT: każdy bin
 * k obejmuje [k-0.5, k+0.5)·hz_per_bin, a do pasma wchodzi tylko część jego
 * mocy proporcjonalna do nakładania się przedziałów. Dawna wersja brała bin
 * w całości albo wcale (ceil/floor) — pasmo węższe niż jeden bin (przy
 * 48 kHz / 2048 = 23.4 Hz/bin trzy dolne biny log: 48–57, 57–68, 98–117 Hz)
 * nie zawierało żadnego całego binu i zwracało ZAWSZE 0 → sześć słupków
 * dither-orb (lustro) nigdy nie drgnęło (zgłoszenie właściciela 2026-09-17). */
static float band_rms(const float *power, int n_power, float hz_per_bin, float lo, float hi) {
    if (hi <= lo) return 0.0f;
    float sum = 0.0f, weight = 0.0f;
    int a = (int)floorf(lo / hz_per_bin + 0.5f), b = (int)floorf(hi / hz_per_bin + 0.5f);
    if (a < 1) a = 1;
    if (b > n_power - 1) b = n_power - 1;
    for (int k = a; k <= b; k++) {
        float k_lo = ((float)k - 0.5f) * hz_per_bin, k_hi = ((float)k + 0.5f) * hz_per_bin;
        float ov = fminf(hi, k_hi) - fmaxf(lo, k_lo);
        if (ov <= 0.0f) continue;
        float w = ov / hz_per_bin;             /* 0..1 — część binu w paśmie */
        sum += power[k] * w;
        weight += w;
    }
    if (weight <= 0.0f) return 0.0f;
    return sqrtf(sum / weight);
}

void audio_bands(const float *power, int n_power, float sample_rate,
                 const float *samples, int n_samples, struct audio_bands_raw *out) {
    float hz_per_bin = sample_rate / (float)AUDIO_FFT_N;
    double acc = 0.0;
    for (int i = 0; i < n_samples; i++) acc += (double)samples[i] * samples[i];
    out->level  = n_samples ? (float)sqrt(acc / n_samples) : 0.0f;
    out->bass   = band_rms(power, n_power, hz_per_bin,   20.0f,   150.0f);
    out->lowmid = band_rms(power, n_power, hz_per_bin,  150.0f,   500.0f);
    out->mid    = band_rms(power, n_power, hz_per_bin,  500.0f,  2000.0f);
    out->high   = band_rms(power, n_power, hz_per_bin, 2000.0f, 10000.0f);
    /* 32 biny log-freq od 40 Hz do 12 kHz */
    for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) {
        float lo = 40.0f * powf(300.0f, (float)i / AUDIO_SPECTRUM_BINS);
        float hi = 40.0f * powf(300.0f, (float)(i + 1) / AUDIO_SPECTRUM_BINS);
        out->spectrum[i] = band_rms(power, n_power, hz_per_bin, lo, hi);
    }
}

/* ── auto-gain, wygładzanie, beat, starzenie ────────────────────────────── */

float audio_agc_step(struct audio_agc *a, float x, float dt, float floor_value) {
    a->peak *= expf(-dt / 2.0f);
    if (a->peak < floor_value) a->peak = floor_value;
    if (x > a->peak) a->peak = x;
    float y = x / a->peak;
    return y < 0.0f ? 0.0f : (y > 1.0f ? 1.0f : y);
}

float audio_smooth(float prev, float x, float dt, float attack, float release) {
    float tau = x > prev ? attack : release;
    if (tau <= 0.0f) return x;
    float k = 1.0f - expf(-dt / tau);
    return prev + (x - prev) * k;
}

float audio_beat_step(struct audio_beat *b, float bass, float dt) {
    b->since += dt;
    if (bass > 1.5f * b->avg && bass > 0.2f && b->since > 0.15f) {
        b->out = 1.0f;
        b->since = 0.0f;
        /* Po uderzeniu średnia skacze do poziomu uderzenia: ciągły ton daje
         * JEDEN onset, a nie serię co 150 ms, dopóki średnia nie dogoni. */
        b->avg = bass;
    } else {
        b->out *= expf(-dt / 0.1f);
        if (b->out < 0.001f) b->out = 0.0f;
    }
    b->avg += (bass - b->avg) * (dt / 1.0f > 1.0f ? 1.0f : dt / 1.0f);
    return b->out;
}

void audio_features_age(struct audio_features *f, double now, float release) {
    if (f->t <= 0.0) return;
    double age = now - f->t;
    if (age <= 0.1) return;
    float k = expf(-(float)(age - 0.1) / release);
    f->level *= k; f->bass *= k; f->lowmid *= k; f->mid *= k; f->high *= k; f->beat *= k;
    for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) f->spectrum[i] *= k;
}

/* ── pełna analiza okna ─────────────────────────────────────────────────── */

/* Bramka szumu: poniżej −60 dBFS RMS wszystko = 0 (cisza nie ma być
 * wzmacniana przez auto-gain do pełnej reakcji). */
#define AUDIO_GATE   0.001f
/* Podłoga auto-gain per pasmo — poniżej niej szum/syk nie liczy się jako sygnał. */
#define AUDIO_FLOOR  0.004f
#define AUDIO_ATTACK 0.03f
#define AUDIO_RELEASE 0.25f

void audio_state_init(struct audio_state *st) {
    memset(st, 0, sizeof *st);
    audio_fft_init(&st->fft);
}

void audio_analyze(struct audio_state *st, const float *window, float dt, double now) {
    struct audio_bands_raw raw;
    audio_fft_power(&st->fft, window, st->power);
    audio_bands(st->power, AUDIO_FFT_N / 2 + 1, (float)AUDIO_RATE, window, AUDIO_FFT_N, &raw);

    struct audio_features *o = &st->out;
    if (raw.level < AUDIO_GATE) {
        /* cisza: opadamy do zera, nic nie wzmacniamy */
        o->level  = audio_smooth(o->level,  0.0f, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        o->bass   = audio_smooth(o->bass,   0.0f, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        o->lowmid = audio_smooth(o->lowmid, 0.0f, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        o->mid    = audio_smooth(o->mid,    0.0f, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        o->high   = audio_smooth(o->high,   0.0f, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++)
            o->spectrum[i] = audio_smooth(o->spectrum[i], 0.0f, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        o->beat = audio_beat_step(&st->beat, 0.0f, dt);
    } else {
        float lv = audio_agc_step(&st->agc_level,  raw.level,  dt, AUDIO_FLOOR);
        float ba = audio_agc_step(&st->agc_bass,   raw.bass,   dt, AUDIO_FLOOR);
        float lm = audio_agc_step(&st->agc_lowmid, raw.lowmid, dt, AUDIO_FLOOR);
        float mi = audio_agc_step(&st->agc_mid,    raw.mid,    dt, AUDIO_FLOOR);
        float hi = audio_agc_step(&st->agc_high,   raw.high,   dt, AUDIO_FLOOR);
        o->level  = audio_smooth(o->level,  lv, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        o->bass   = audio_smooth(o->bass,   ba, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        o->lowmid = audio_smooth(o->lowmid, lm, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        o->mid    = audio_smooth(o->mid,    mi, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        o->high   = audio_smooth(o->high,   hi, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) {
            float v = audio_agc_step(&st->agc_spec[i], raw.spectrum[i], dt, AUDIO_FLOOR);
            o->spectrum[i] = audio_smooth(o->spectrum[i], v, dt, AUDIO_ATTACK, AUDIO_RELEASE);
        }
        o->beat = audio_beat_step(&st->beat, ba, dt);
    }
    o->t = now;
}

/* ── wątek ──────────────────────────────────────────────────────────────── */

struct audio {
    pthread_t       thread;
    pthread_mutex_t lock;
    volatile bool   running;
    bool            verbose;
    char           *device;
    char           *file;
    struct audio_features snap;
    struct audio_state    st;
    float           ring[AUDIO_FFT_N];
    float           hop[AUDIO_HOP];
    bool            started;
};

static double now_s(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void logv(const struct audio *a, const char *fmt, ...) {
    if (!a->verbose) return;
    va_list ap; va_start(ap, fmt);
    fputs("flux-wall: audio: ", stderr); vfprintf(stderr, fmt, ap); fputc('\n', stderr);
    va_end(ap);
}

/* Dosuń hop do bufora pierścieniowego (tu: przesuwany), przeanalizuj, opublikuj. */
static void push_hop(struct audio *a) {
    memmove(a->ring, a->ring + AUDIO_HOP, (AUDIO_FFT_N - AUDIO_HOP) * sizeof(float));
    memcpy(a->ring + AUDIO_FFT_N - AUDIO_HOP, a->hop, AUDIO_HOP * sizeof(float));
    audio_analyze(&a->st, a->ring, (float)AUDIO_HOP / AUDIO_RATE, now_s());
    pthread_mutex_lock(&a->lock);
    a->snap = a->st.out;
    a->snap.live = true;
    pthread_mutex_unlock(&a->lock);
}

static void set_live(struct audio *a, bool live) {
    pthread_mutex_lock(&a->lock);
    a->snap.live = live;
    pthread_mutex_unlock(&a->lock);
}

static void run_file(struct audio *a) {
    FILE *f = fopen(a->file, "rb");
    if (!f) { logv(a, "nie mogę otworzyć %s: %s", a->file, strerror(errno)); return; }
    struct timespec next; clock_gettime(CLOCK_MONOTONIC, &next);
    while (a->running) {
        size_t got = fread(a->hop, sizeof(float), AUDIO_HOP, f);
        if (got < AUDIO_HOP) {                      /* koniec pliku → od początku */
            if (got == 0 && feof(f) && ftell(f) == 0) break;   /* pusty plik */
            memset(a->hop + got, 0, (AUDIO_HOP - got) * sizeof(float));
            rewind(f);
        }
        push_hop(a);
        next.tv_nsec += 20000000L;
        while (next.tv_nsec >= 1000000000L) { next.tv_nsec -= 1000000000L; next.tv_sec++; }
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL);
    }
    fclose(f);
}

static pa_simple *open_stream(struct audio *a, const char **used) {
    const pa_sample_spec ss = { .format = PA_SAMPLE_FLOAT32NE, .rate = AUDIO_RATE, .channels = 1 };
    const pa_buffer_attr attr = {
        .maxlength = (uint32_t)-1, .tlength = (uint32_t)-1, .prebuf = (uint32_t)-1,
        .minreq = (uint32_t)-1, .fragsize = AUDIO_HOP * sizeof(float),
    };
    const char *candidates[2] = { "@DEFAULT_MONITOR@", a->device };
    for (int i = 0; i < 2; i++) {
        if (!candidates[i]) continue;
        int err = 0;
        pa_simple *s = pa_simple_new(NULL, "flux-wall", PA_STREAM_RECORD, candidates[i],
                                     "monitor wyjścia (tapeta)", &ss, NULL, &attr, &err);
        if (s) { *used = candidates[i]; return s; }
        logv(a, "%s: %s", candidates[i], pa_strerror(err));
    }
    return NULL;
}

static void run_pulse(struct audio *a) {
    int backoff = 1;
    bool reported = false;
    while (a->running) {
        const char *used = NULL;
        pa_simple *s = open_stream(a, &used);
        if (!s) {
            set_live(a, false);
            if (!reported) { logv(a, "brak serwera dźwięku — ponawiam (backoff do 30 s)"); reported = true; }
            for (int i = 0; i < backoff * 10 && a->running; i++) {
                struct timespec ts = { 0, 100000000L }; nanosleep(&ts, NULL);
            }
            if (backoff < 30) backoff *= 2;
            continue;
        }
        logv(a, "strumień z %s", used);
        reported = false; backoff = 1;
        int err = 0;
        while (a->running) {
            /* Blokuje, gdy sink śpi (nic nie gra) — wtedy snapshot się starzeje,
             * a render gasi go sam (audio_features_age). */
            if (pa_simple_read(s, a->hop, sizeof a->hop, &err) < 0) {
                logv(a, "strumień zerwany: %s", pa_strerror(err));
                break;
            }
            push_hop(a);
        }
        pa_simple_free(s);
        set_live(a, false);
    }
}

static void *thread_main(void *arg) {
    struct audio *a = arg;
    if (a->file) run_file(a); else run_pulse(a);
    set_live(a, false);
    return NULL;
}

struct audio *audio_start(const char *device, const char *file, bool verbose) {
    struct audio *a = calloc(1, sizeof *a);
    if (!a) return NULL;
    a->verbose = verbose;
    a->device = device ? strdup(device) : NULL;
    a->file   = file ? strdup(file) : NULL;
    audio_state_init(&a->st);
    pthread_mutex_init(&a->lock, NULL);
    a->running = true;
    if (pthread_create(&a->thread, NULL, thread_main, a) != 0) {
        free(a->device); free(a->file); free(a);
        return NULL;
    }
    a->started = true;
    return a;
}

void audio_snapshot(struct audio *a, struct audio_features *out) {
    pthread_mutex_lock(&a->lock);
    *out = a->snap;
    pthread_mutex_unlock(&a->lock);
}

void audio_stop(struct audio *a) {
    if (!a) return;
    a->running = false;
    if (a->started) {
        /* pthread_cancel nie jest bezpieczny wobec libpulse (własne mutexy);
         * czekamy chwilę, a jeśli read blokuje w uśpionym sinku — odłączamy
         * wątek i zostawiamy go do końca procesu (gniazdo zamknie kernel). */
        struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_nsec += 200000000L;
        while (ts.tv_nsec >= 1000000000L) { ts.tv_nsec -= 1000000000L; ts.tv_sec++; }
        if (pthread_timedjoin_np(a->thread, NULL, &ts) != 0) {
            pthread_detach(a->thread);
            return;                       /* struktury zostają — wątek może ich dotknąć */
        }
    }
    pthread_mutex_destroy(&a->lock);
    free(a->device); free(a->file); free(a);
}
