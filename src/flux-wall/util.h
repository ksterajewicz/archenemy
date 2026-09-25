/*
 * archenemy - flux-wall: drobne narzędzia wspólne dla main.c, audio.c i
 * tools/offscreen.c (zegar monotoniczny, cały plik do stringa). Bez GL i bez
 * Waylanda; static inline, żeby nie dokładać jednostki kompilacji do Makefile.
 * Wołający definiuje _POSIX_C_SOURCE przed pierwszym include (clock_gettime).
 */
#ifndef FLUX_UTIL_H
#define FLUX_UTIL_H

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <time.h>

/* Sekundy zegara CLOCK_MONOTONIC (do dt, limitu fps, znaczników audio). */
static inline double flux_now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

/* Cały plik jako string (malloc; wołający zwalnia); NULL + errno przy
 * błędzie. Katalog (fopen go otwiera, fread daje pusty shader → mylący
 * „błąd shadera") i inne nie-pliki odrzucamy tu: EISDIR/EINVAL. */
static inline char *flux_read_file(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return NULL;
    if (!S_ISREG(st.st_mode)) { errno = S_ISDIR(st.st_mode) ? EISDIR : EINVAL; return NULL; }
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) { fclose(f); return NULL; }
    char *buf = malloc((size_t)n + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t got = fread(buf, 1, (size_t)n, f);
    fclose(f);
    buf[got] = 0;
    return buf;
}

#endif
