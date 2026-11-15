/*
 * archenemy - flux-wall: decyzje po błędach EGL (co zrobić z błędem, kiedy
 * ponowić powierzchnię monitora). Same liczby i wybory — bez Waylanda i bez
 * wywołań EGL, żeby test.c sprawdzał je bez kompozytora; skutki (sprzątanie,
 * nowa powierzchnia, kod wyjścia) wykonuje main.c. static inline jak util.h.
 */
#ifndef FLUX_RECOVERY_H
#define FLUX_RECOVERY_H

#include <stdbool.h>

/* ── ponowienie powierzchni jednego monitora ─────────────────────────────── */

/* Przerwa przed ponowną próbą po błędzie EGL powierzchni: 1 s, potem
 * podwajana do 30 s (jak backoff audio) — monitor, na którym EGL stale
 * odmawia, nie kręci pętli tworzenia powierzchni co klatkę. */
#define FLUX_RETRY_FIRST 1.0
#define FLUX_RETRY_MAX   30.0

struct flux_retry {
    double delay;     /* ostatnia przerwa w s; 0 = od ostatniego sukcesu bez błędu */
    double next_at;   /* zegar monotoniczny: od tej chwili wolno próbować */
};

/* Kolejny błąd: wydłuża przerwę i wyznacza termin próby; zwraca przerwę. */
static inline double flux_retry_failed(struct flux_retry *r, double now) {
    r->delay = r->delay > 0 ? r->delay * 2 : FLUX_RETRY_FIRST;
    if (r->delay > FLUX_RETRY_MAX) r->delay = FLUX_RETRY_MAX;
    r->next_at = now + r->delay;
    return r->delay;
}

/* Powierzchnia rysuje — następny błąd znów zaczyna od FLUX_RETRY_FIRST. */
static inline void flux_retry_reset(struct flux_retry *r) {
    r->delay = 0;
    r->next_at = 0;
}

/* Ile sekund do terminu próby (<= 0 = można próbować). */
static inline double flux_retry_wait(const struct flux_retry *r, double now) {
    return r->next_at - now;
}

/* ── co zrobić z błędem EGL ──────────────────────────────────────────────── */

enum flux_egl_stage {
    FLUX_STAGE_SURFACE,   /* nowa powierzchnia monitora: okno EGL, eglCreateWindowSurface,
                           * pierwszy eglMakeCurrent, cel silnika (akumulator) */
    FLUX_STAGE_FRAME,     /* istniejąca powierzchnia: eglMakeCurrent / eglSwapBuffers klatki
                           * albo zmiany rozmiaru */
};

enum flux_egl_action {
    FLUX_EGL_EXIT,           /* kod 3 — przed startem nie ma tapety, hyprpaper zostaje */
    FLUX_EGL_RETRY_SURFACE,  /* sprzątnąć TĘ powierzchnię i ponowić po przerwie;
                              * pozostałe monitory rysują dalej */
    FLUX_EGL_SKIP_FRAME,     /* pojedyncza odmowa — klatka (albo configure) później */
};

/* `started` = pierwsza klatka tego procesu już na ekranie (udany swap — ten
 * sam moment co --ready-file). Do tej chwili błąd EGL to kontrakt „kod 3”
 * (wrapper melduje porażkę, zostaje hyprpaper, proces nie wisi bez obrazu).
 * Po starcie błąd powierzchni jednego monitora (np. świeżo podpięty, na którym
 * EGL odmawia) dotyczy tylko jej: kod 3 gasił animację na WSZYSTKICH
 * monitorach (audyt 2026-11-05, F4). Odmowa w klatce istniejącej
 * powierzchni to zawsze „klatka później” — także przed pierwszą klatką. */
static inline enum flux_egl_action flux_egl_action(enum flux_egl_stage stage, bool started) {
    if (stage == FLUX_STAGE_FRAME) return FLUX_EGL_SKIP_FRAME;
    return started ? FLUX_EGL_RETRY_SURFACE : FLUX_EGL_EXIT;
}

#endif
