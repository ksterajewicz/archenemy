/*
 * archenemy - flux-wall: decyzje po błędach EGL (co zrobić z błędem, kiedy
 * ponowić powierzchnię monitora, ile utrat kontekstu znosimy). Same liczby
 * i wybory — bez Waylanda i bez wywołań EGL (z EGL tylko stałe), żeby
 * test.c sprawdzał je bez kompozytora; skutki (sprzątanie, nowa
 * powierzchnia, nowy kontekst, kod wyjścia) wykonuje main.c. static inline
 * jak util.h.
 */
#ifndef FLUX_RECOVERY_H
#define FLUX_RECOVERY_H

#include <stdbool.h>
#include <EGL/egl.h>    /* EGL_CONTEXT_LOST */

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
    FLUX_EGL_NEW_CONTEXT,    /* EGL_CONTEXT_LOST: nowy kontekst, silnik i powierzchnie
                              * wszystkich monitorów (flux_ctx_lost_recover niżej) */
};

/* `started` = pierwsza klatka tego procesu już na ekranie (udany swap — ten
 * sam moment co --ready-file). Do tej chwili błąd EGL to kontrakt „kod 3”
 * (wrapper melduje porażkę, zostaje hyprpaper, proces nie wisi bez obrazu).
 * Po starcie błąd powierzchni jednego monitora (np. świeżo podpięty, na którym
 * EGL odmawia) dotyczy tylko jej: kod 3 gasił animację na WSZYSTKICH
 * monitorach (audyt 2026-11-05, F4). Odmowa w klatce istniejącej
 * powierzchni to „klatka później” — także przed pierwszą klatką — z jednym
 * wyjątkiem: EGL_CONTEXT_LOST (zdarzenie zasilania, np. wybudzenie GPU) nie
 * mija nigdy, bo kontekst i obiekty GL przepadły. Pomijanie klatek
 * zamrażało wtedy tapetę na zawsze przy żywym procesie i statusie
 * „działa” (audyt 2026-11-05, F5): po starcie — nowy kontekst, przed
 * startem — kod 3. `egl_error` = eglGetError() zaraz po odmowie (albo
 * EGL_SUCCESS, gdy odmówiło coś poza EGL, np. cel silnika). */
static inline enum flux_egl_action flux_egl_action(enum flux_egl_stage stage, int egl_error, bool started) {
    if (egl_error == EGL_CONTEXT_LOST) return started ? FLUX_EGL_NEW_CONTEXT : FLUX_EGL_EXIT;
    if (stage == FLUX_STAGE_FRAME) return FLUX_EGL_SKIP_FRAME;
    return started ? FLUX_EGL_RETRY_SURFACE : FLUX_EGL_EXIT;
}

/* ── utrata kontekstu ────────────────────────────────────────────────────── */

/* Więcej niż FLUX_CTX_LOST_MAX utrat kontekstu w oknie FLUX_CTX_LOST_WINDOW s
 * (licząc od pierwszej w oknie) = kod 3: sterownik, który gubi każdy nowy
 * kontekst, nie kręci pętli „nowy kontekst → utrata” z miganiem tapety;
 * hyprpaper zostaje. Pojedyncze wybudzenia (rzadziej niż kilka na minutę)
 * odtwarzamy zawsze. */
#define FLUX_CTX_LOST_MAX    3
#define FLUX_CTX_LOST_WINDOW 60.0

struct flux_ctx_guard {
    double window_start;   /* zegar monotoniczny: pierwsza utrata w bieżącym oknie */
    int    losses;         /* utraty w bieżącym oknie */
};

/* Kolejna utrata kontekstu: true = odtwarzać, false = kod 3. */
static inline bool flux_ctx_lost_recover(struct flux_ctx_guard *g, double now) {
    if (g->losses == 0 || now - g->window_start >= FLUX_CTX_LOST_WINDOW) {
        g->window_start = now;
        g->losses = 0;
    }
    return ++g->losses <= FLUX_CTX_LOST_MAX;
}

#endif
