/*
 * archenemy - flux-wall: opcje wiersza poleceń (struct config) i ich
 * parsowanie. Implementacja w main.c (getopt_long, bez Waylanda), test.c
 * woła flux_parse_args wprost, bez procesu potomnego; skutki (usage, kod
 * wyjścia 0/1) wykonuje main().
 */
#ifndef FLUX_CLI_H
#define FLUX_CLI_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include "engine.h"     /* struct palette */

struct config {
    const char *shader_path;
    const char *output_name;     /* NULL = wszystkie monitory */
    struct palette palette;
    float detail;                /* wartość stała, gdy battery == false */
    bool  battery;               /* detail z /sys/class/power_supply */
    float dither;                /* uniform `dither`: 1 = raster Bayera, 0 = gładko (domyślnie) —
                                  * cecha rice'a (FLUX_WALL_DITHER), nie animacji */
    int   fps;                   /* 0 = każda klatka kompozytora */
    bool  once;                  /* jedna klatka po configure, bez animacji */
    bool  verbose;
    uint32_t layer;              /* ZWLR_LAYER_SHELL_V1_LAYER_* — bottom = nad hyprpaperem */
    bool  no_audio;              /* --no-audio: nie startuj wątku nawet dla wizualizacji */
    const char *audio_device;    /* --audio-device: jawna nazwa monitora (fallback po @DEFAULT_MONITOR@) */
    const char *audio_file;      /* --audio-file: surowy f32 mono 48 kHz zamiast serwera (debug; wymusza audio) */
    const char *ready_file;      /* --ready-file: plik z PID-em po pierwszej klatce na ekranie (flux-wall.sh) */
};

enum flux_args {
    FLUX_ARGS_RUN,      /* opcje poprawne — uruchom */
    FLUX_ARGS_HELP,     /* -h/--help: usage, kod 0 */
    FLUX_ARGS_USAGE,    /* nieznana opcja (komunikat getopt) albo brak -s: usage, kod 1 */
    FLUX_ARGS_BAD,      /* zła wartość opcji: komunikat „flux-wall: …” już w `errf`, kod 1 */
};

/* "0F1A24" albo "#0F1A24" → rgb 0..1; false przy śmieciach. */
bool parse_hex_color(const char *hex, float out[3]);
/* "bg,ink,accent" — trzy hexy rozdzielone przecinkami. */
bool parse_palette(const char *spec, struct palette *p);

/* Wartości domyślne w `cfg`, potem opcje z argv (getopt_long — wołający
 * odpowiada za stan getopt, main() woła raz). Zatrzymuje się na pierwszej
 * złej opcji jak dawne die(1, …) w main(): komunikat do `errf` (main:
 * stderr), wartości z argv tylko wskazywane, nie kopiowane. */
enum flux_args flux_parse_args(int argc, char **argv, struct config *cfg, FILE *errf);

#endif
