/*
 * archenemy - flux-wall: silnik renderowania (GLES 3.0, bez Waylanda).
 *
 * Dwa tryby, wybierane obecnością pliku obok shadera:
 *   - jednoprzebiegowy: `shaders/<nazwa>.frag` liczony per piksel (jak dotąd);
 *   - cząstkowy:        do tego `shaders/<nazwa>.update.glsl` — krok symulacji
 *                       cząstek; ślady akumulują się w buforze, który gaśnie
 *                       w czasie, a `<nazwa>.frag` robi z niego tone + dither.
 *
 * Silnik nie wie nic o Waylandzie ani EGL: dostaje bieżący kontekst GL i cel
 * (framebuffer + rozmiar). Dzięki temu ten sam kod działa pod kompozytorem
 * (main.c) i offscreen w testach.
 *
 * Kontrakt uniformów przebiegu finalnego (.frag):
 *   resolution, time, palette_bg/ink/accent, detail   — jak dotąd,
 *   accum (sampler2D), gain                            — tylko tryb cząstkowy.
 * Kontrakt kroku cząstek (.update.glsl) — prelude dokleja silnik:
 *   pos (sampler2D P×P: xy pozycja, z wiek w krokach, w numer wcielenia),
 *   time, dt (sekundy na krok), detail, resolution, aspect (w/h), seed,
 *   life_steps, accum (sampler2D — gęstość śladów z poprzedniego kroku, w
 *   pikselach ekranu); funkcje h2/vnoise/fbm 1:1 z gen_dither_flux_wallpaper.py;
 *   plik definiuje main() i pisze `o = vec4(x, y, wiek, wcielenie)`.
 * Parametry w nagłówku .update.glsl: `#pragma flux <klucz> <wartość>`.
 */
#ifndef FLUX_ENGINE_H
#define FLUX_ENGINE_H

#include <stdbool.h>
#include <stddef.h>
#include <GLES3/gl3.h>

struct palette { float bg[3], ink[3], accent[3]; };

/* Parametry animacji cząstkowej — z `#pragma flux` (wartości domyślne niżej). */
struct flux_params {
    int   particles;   /* liczba cząstek przy detail = 1 (zaokrąglana w górę do P×P) */
    float life;        /* SEKUNDY: życie cząstki i stała zaniku akumulatora */
    float rate;        /* kroków symulacji na sekundę (tempo niezależne od fps) */
    float inc;         /* jasność jednego śladu w akumulatorze */
    float gain;        /* wzmocnienie przed log-tonowaniem w .frag */
    int   splat;       /* 0 = screen: pozycje w 0..1 ekranu; 1 = plane: płaszczyzna × scale */
    float scale;       /* splat plane: mnożnik jednostek płaszczyzny → wysokość ekranu */
    float warmup;      /* SEKUNDY symulacji przed pierwszą klatką przy --once */
    int   warm;        /* kroki po odrodzeniu bez śladu (rozbieg orbity atraktora) */
    int   seed;        /* ziarno hasha h2 — jak `ziarno` generatora PNG */
};

#define FLUX_PARAMS_DEFAULT { 20000, 4.0f, 60.0f, 0.006f, 14.0f, 0, 0.30f, 6.0f, 0, 2026 }

/* Czyste funkcje (testowalne bez GL). */
bool flux_params_parse(const char *src, struct flux_params *p, char *err, size_t errlen);
/* Ścieżka `.update.glsl` dla `.frag`; false, gdy nazwa nie kończy się na .frag. */
bool flux_update_path(const char *frag_path, char *out, size_t outlen);

struct flux_engine;
struct flux_target;

/* Wymaga bieżącego kontekstu GLES 3.0. `update_src` = NULL → tryb jednoprzebiegowy.
 * Przy błędzie zwraca NULL i opis w `err`. */
struct flux_engine *flux_engine_create(const char *frag_src, const char *frag_label,
                                       const char *update_src, const char *update_label,
                                       char *err, size_t errlen);
void flux_engine_destroy(struct flux_engine *e);
bool flux_engine_is_particle(const struct flux_engine *e);
const struct flux_params *flux_engine_params(const struct flux_engine *e);

/* Stan per powierzchnia (akumulator ma rozmiar bufora monitora). Wymaga
 * bieżącego kontekstu. NULL + `err`, gdy FBO zmiennoprzecinkowy nie jest
 * dostępny na tym sterowniku. */
struct flux_target *flux_target_create(struct flux_engine *e, int w, int h, char *err, size_t errlen);
void flux_target_resize(struct flux_target *t, int w, int h);
void flux_target_destroy(struct flux_target *t);

/* Jedna klatka: symulacja (tryb cząstkowy) + przebieg finalny do `dest_fbo`
 * (0 = powierzchnia okna) o rozmiarze celu. `time` w sekundach od startu;
 * `warmup_once` = przed TĄ klatką przelicz `warmup` sekund symulacji
 * (dla --once, gdzie nie ma kolejnych klatek). */
void flux_engine_render(struct flux_engine *e, struct flux_target *t, GLuint dest_fbo,
                        double time, const struct palette *pal, float detail, bool warmup_once);

#endif
