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
 *   accum (sampler2D), gain                            — tylko tryb cząstkowy,
 *   audio_level/bass/lowmid/mid/high/beat (0..1), audio_spectrum (sampler2D
 *   32×1 R, jednostka 2), audio_wave (sampler2D AUDIO_WAVE_N×1 RG: r = L,
 *   g = R, próbki -1..1 po triggerze — oscyloskop), audio_wave_peak (szczyt
 *   |mono| tego okna — auto-wzmocnienie) — dźwięk; ustawiane,
 *   jeśli shader je zadeklaruje (tekstury ładowane tylko wtedy).
 *   `time` to CZAS ANIMACJI: przy muzyce płynie szybciej (audio_tempo·mid).
 * `#pragma flux` wolno pisać także w .frag (np. audio_tempo dla animacji
 * jednoprzebiegowych) — linie są usuwane przed kompilacją, `#version` zostaje.
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
#include "audio.h"

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
    /* dźwięk — TYLKO animacje do tego stworzone: `audio 1` włącza nasłuch
     * monitora wyjścia (decyzja właściciela 2026-09-08: bez przełącznika,
     * automatycznie); pozostałe pola to reakcje ogólne silnika, domyślnie 0 */
    int   audio;         /* 1 = ta animacja jest wizualizacją muzyki — start wątku audio */
    float audio_tempo;   /* mid → tempo: czas animacji płynie 1 + tempo·mid razy szybciej */
    float audio_glow;    /* bass → jasność: gain · (1 + 1.5·glow·bass) w przebiegu finalnym */
    float audio_sparkle; /* zarezerwowane dla shaderów (uniform audio_high) */
};

#define FLUX_PARAMS_DEFAULT { 20000, 4.0f, 60.0f, 0.006f, 14.0f, 0, 0.30f, 6.0f, 0, 2026, 0, 0.0f, 0.0f, 0.0f }

/* Czyste funkcje (testowalne bez GL). */
bool flux_params_parse(const char *src, struct flux_params *p, char *err, size_t errlen);
/* Mnożnik tempa z dźwięku: 1 + audio_tempo·strength·mid; 1.0 bez audio. */
double flux_warp(const struct flux_params *p, const struct audio_features *audio, float strength);
/* Maksimum kroków symulacji na klatkę: 4 · ceil(1 + audio_tempo·strength) — przy warpie
 * stały limit 4 obcinałby tempo; bez audio zostaje 4. */
int flux_step_cap(const struct flux_params *p, float strength);
/* Kopia źródła z liniami `#pragma flux` zamienionymi na spacje (numery linii
 * zostają); `keep_version` = zostaw `#version` (dla .frag bez prelude). */
char *flux_strip_directives(const char *src, bool keep_version);
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
/* `audio` = NULL → bez reakcji (warp 1, uniformy audio = 0); `audio_strength`
 * skaluje wzmocnienia (1.0 = wartości z pragm shadera). */
void flux_engine_render(struct flux_engine *e, struct flux_target *t, GLuint dest_fbo,
                        double time, const struct palette *pal, float detail,
                        const struct audio_features *audio, float audio_strength, bool warmup_once);

#endif
