/*
 * archenemy - flux-wall: czyste decyzje main.c poza błędami EGL (te są
 * w recovery.h) — rozmiar bufora ze skali monitora, tempo klatek i czas
 * poll() w pętli, płynna szczegółowość z baterii, wybór monitora (-o),
 * start wątku audio, wersje bindowanych globali i „kompozytor zamknął
 * połączenie” (kod 0). Same liczby i wybory, bez wywołań Waylanda i EGL,
 * żeby test.c sprawdzał je bez kompozytora; skutki wykonuje main.c.
 * static inline jak util.h i recovery.h.
 */
#ifndef FLUX_LOGIC_H
#define FLUX_LOGIC_H

#include <errno.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

/* ── rozmiar bufora ───────────────────────────────────────────────────────── */

/* Bufor w pikselach fizycznych z rozmiaru logicznego (`configure`) i skali.
 * Skala ułamkowa (wp_fractional_scale_v1, `frac120` = skala × 120, 0 =
 * nieznana) działa tylko z viewportem: bufor = logiczny × skala zaokrąglony
 * do najbliższego piksela, a viewport mapuje go na rozmiar logiczny.
 * Inaczej skala całkowita wl_output. true = skala ułamkowa (main.c ustawia
 * wtedy viewport i buffer_scale 1, inaczej buffer_scale = `scale`). */
static inline bool flux_buffer_size(int32_t logical_w, int32_t logical_h, int32_t scale,
                                    uint32_t frac120, bool has_viewport, int32_t *pw, int32_t *ph) {
    if (has_viewport && frac120) {
        *pw = (int32_t)((logical_w * frac120 + 60) / 120);
        *ph = (int32_t)((logical_h * frac120 + 60) / 120);
        return true;
    }
    *pw = logical_w * scale;
    *ph = logical_h * scale;
    return false;
}

/* Skala całkowita z wl_output.scale: niedodatnia (błędny kompozytor) = 1. */
static inline int32_t flux_output_scale(int32_t factor) {
    return factor > 0 ? factor : 1;
}

/* Wersja globala do bindowania: oferowana, ale nie wyższa niż obsługiwana
 * (`want`) — np. wl_output v4 daje zdarzenie `name` (potrzebne do -o),
 * a `release` jest od v3. */
static inline uint32_t flux_bind_version(uint32_t offered, uint32_t want) {
    return offered < want ? offered : want;
}

/* -o: NULL = wszystkie monitory, inaczej tylko monitor o tej nazwie. */
static inline bool flux_output_selected(const char *wanted, const char *name) {
    return !wanted || strcmp(wanted, name) == 0;
}

/* ── tempo klatek i pętla ─────────────────────────────────────────────────── */

/* Klatka zaległa bez limitu fps (tylko po nieudanym EGL) — ponowienie po 100 ms. */
#define FLUX_FRAME_RETRY 0.1

/* Ile sekund brakuje monitorowi do następnej klatki (<= 0 = można rysować):
 * przy limicie -f reszta okresu 1/fps od ostatniej klatki TEGO monitora,
 * bez limitu FLUX_FRAME_RETRY. */
static inline double flux_frame_wait(int fps, double now, double last_render) {
    double min_dt = fps > 0 ? 1.0 / fps : FLUX_FRAME_RETRY;
    return min_dt - (now - last_render);
}

/* Timeout poll() w ms po uwzględnieniu jednego monitora, który czeka `wait`
 * sekund (klatka albo termin ponowienia powierzchni): najkrótszy spośród
 * monitorów, zaokrąglony w górę do ms, nie mniej niż 1 ms; `timeout` < 0 =
 * dotąd nikt nie czeka (poll bez limitu). Pełny okres 1000/fps zamiast
 * reszty dawał przy -f 30 na 60 Hz ok. 20 fps. */
static inline int flux_poll_timeout(int timeout, double wait) {
    int ms = (int)ceil(wait * 1000.0);
    if (ms < 1) ms = 1;
    return (timeout < 0 || ms < timeout) ? ms : timeout;
}

/* Co ile sekund --battery czyta /sys/class/power_supply. */
#define FLUX_BATTERY_POLL 30.0

static inline bool flux_battery_due(bool battery, double now, double last_poll) {
    return battery && now - last_poll > FLUX_BATTERY_POLL;
}

/* Jeden krok płynnego dojścia szczegółowości do celu (2 % różnicy na
 * obrót pętli) — skok byłby widoczny; różnica do 0.002 = od razu cel. */
static inline float flux_detail_step(float current, float target) {
    float d = target - current;
    if (d > 0.002f || d < -0.002f) return current + d * 0.02f;
    return target;
}

/* Normalne zamknięcie połączenia przez kompozytor (wylogowanie, restart
 * kompozytora) — to nie jest błąd, kończymy kodem 0; inny błąd = kod 2. */
static inline bool flux_connection_closed(int err) {
    return err == EPIPE || err == ECONNRESET;
}

/* ── statystyki `-v` ──────────────────────────────────────────────────────── */

/* Co ile sekund `-v` wypisuje linię stanu monitora: klatki na sekundę, czas
 * CPU jednej klatki, stan dźwięku. Bez tego „za wolne” i „nie reaguje” nie
 * dawało się zmierzyć na laptopie (audyt 2026-11-24, U4). */
#define FLUX_STATS_PERIOD 5.0

struct flux_stats {
    double since;        /* początek okna (zegar monotoniczny); 0 = okno jeszcze nie otwarte */
    int    frames;       /* klatki w oknie */
    double render_sum;   /* suma czasu rysowania klatek w oknie (sekundy) */
};

/* Jedna narysowana klatka: `now` = chwila po swapie, `render_s` = czas od
 * początku rysowania do końca swapu (CPU: wywołania GL i przekazanie klatki,
 * bez czekania na GPU — swap nie blokuje, eglSwapInterval 0). */
static inline void flux_stats_frame(struct flux_stats *s, double now, double render_s) {
    if (s->since <= 0.0) { s->since = now; s->frames = 0; s->render_sum = 0.0; return; }
    s->frames++;
    s->render_sum += render_s > 0.0 ? render_s : 0.0;
}

/* true, gdy okno ma już FLUX_STATS_PERIOD s: oddaje klatki/s i średni czas
 * klatki w ms, po czym otwiera nowe okno od `now`. Pierwsza klatka tylko
 * otwiera okno (nie liczy się), więc fps = klatki / czas między pierwszą
 * a ostatnią chwilą, bez zawyżania o jedną. */
static inline bool flux_stats_due(struct flux_stats *s, double now, double *fps, double *ms_per_frame) {
    if (s->since <= 0.0 || now - s->since < FLUX_STATS_PERIOD) return false;
    double span = now - s->since;
    *fps = s->frames / span;
    *ms_per_frame = s->frames ? s->render_sum / s->frames * 1000.0 : 0.0;
    s->since = now; s->frames = 0; s->render_sum = 0.0;
    return true;
}

/* Surowy poziom RMS (0..1) w dBFS do logu; cisza cyfrowa i śmieci = -120. */
static inline double flux_dbfs(double rms) {
    if (!(rms > 1e-6)) return -120.0;
    return 20.0 * log10(rms);
}

/* ── dźwięk ───────────────────────────────────────────────────────────────── */

enum flux_audio_mode {
    FLUX_AUDIO_OFF,       /* animacja nie reaguje na dźwięk */
    FLUX_AUDIO_START,     /* uruchom wątek audio */
    FLUX_AUDIO_SKIPPED,   /* chciałaby, ale --once albo --no-audio */
};

/* Wątek audio TYLKO dla `#pragma flux audio 1` (wizualizacja muzyki) albo
 * jawnego --audio-file; nigdy przy --once i --no-audio (decyzja właściciela
 * 2026-09-08: bez przełącznika, automatycznie). */
static inline enum flux_audio_mode flux_audio_mode(bool pragma_audio, bool audio_file, bool once, bool no_audio) {
    if (!pragma_audio && !audio_file) return FLUX_AUDIO_OFF;
    return (once || no_audio) ? FLUX_AUDIO_SKIPPED : FLUX_AUDIO_START;
}

#endif
