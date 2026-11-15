/*
 * archenemy - flux-wall: testy jednostkowe funkcji czystych (bez Waylanda/EGL)
 * i jedna sekcja GL na EGL surfaceless (silnik bez Waylanda; bez EGL —
 * „POMINIĘTO” w wyjściu, nie błąd).
 * Budowane przez `make test`: main.c wchodzi z main() przemianowanym na
 * flux_wall_main, więc tu jest własny main(). libpulse-simple zastępuje
 * atrapa niżej (pa_simple_*) — testy nie łączą się z serwerem dźwięku.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "engine.h"
#include "audio.h"
#define TEST_PI 3.14159265f
#include <math.h>
#include <stdatomic.h>
#include <time.h>
#include <pulse/error.h>
#include <pulse/simple.h>
bool  parse_hex_color(const char *hex, float out[3]);
bool  parse_palette(const char *spec, struct palette *p);
float battery_detail(const char *power_supply_dir);
bool  flux_ready_mark(const char *path);
int   flux_wall_main(int argc, char **argv);   /* main() z main.c (-Dmain=flux_wall_main) */

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) printf("  ok   %s\n", msg); \
                              else { printf("  FAIL %s\n", msg); failures++; } } while (0)

static bool near(float a, float b) { return a - b < 0.002f && b - a < 0.002f; }

/* Atrapa libpulse-simple: definicje w tym pliku wygrywają przy linkowaniu
 * z biblioteką, więc wątek audio (audio.c, run_pulse) w testach NIGDY nie
 * łączy się z prawdziwym serwerem dźwięku. Strumień otwiera się zawsze,
 * a każdy odczyt od razu się zrywa — jak serwer, który pada zaraz po
 * połączeniu. `fake_pa_opens` liczy próby połączenia. */
static atomic_int fake_pa_opens;
static char fake_pa_stream;
pa_simple *pa_simple_new(const char *server, const char *name, pa_stream_direction_t dir, const char *dev,
                         const char *stream_name, const pa_sample_spec *ss, const pa_channel_map *map,
                         const pa_buffer_attr *attr, int *error) {
    (void)server; (void)name; (void)dir; (void)dev; (void)stream_name; (void)ss; (void)map; (void)attr; (void)error;
    atomic_fetch_add(&fake_pa_opens, 1);
    return (pa_simple *)(void *)&fake_pa_stream;
}
int pa_simple_read(pa_simple *s, void *data, size_t bytes, int *error) {
    (void)s; (void)data; (void)bytes;
    if (error) *error = PA_ERR_CONNECTIONTERMINATED;
    return -1;
}
void pa_simple_free(pa_simple *s) { (void)s; }

static void write_file(const char *path, const char *content) {
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); exit(1); }
    fputs(content, f);
    fclose(f);
}

/* CLI binarki bez Waylanda: flux_wall_main w procesie potomnym (die() woła
 * exit), WAYLAND_DISPLAY na nieistniejące gniazdo — poprawne argumenty kończą
 * się kodem 2 (brak Waylanda) DOPIERO po parsowaniu i logu -v. Zwraca kod
 * wyjścia, stderr potomka trafia do `log`. */
static int run_cli(const char *dir, char **args, char *log, size_t loglen) {
    char lpath[600];
    snprintf(lpath, sizeof lpath, "%s/cli.log", dir);
    fflush(stdout); fflush(stderr);
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); exit(1); }
    if (pid == 0) {
        if (!freopen(lpath, "w", stderr)) _exit(99);
        setenv("XDG_RUNTIME_DIR", dir, 1);
        setenv("WAYLAND_DISPLAY", "flux-wall-test-brak-gniazda", 1);
        int argc = 0;
        while (args[argc]) argc++;
        exit(flux_wall_main(argc, args));
    }
    int st = 0;
    waitpid(pid, &st, 0);
    log[0] = 0;
    FILE *f = fopen(lpath, "r");
    if (f) { size_t n = fread(log, 1, loglen - 1, f); log[n] = 0; fclose(f); }
    remove(lpath);
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

/* ── GL: silnik na EGL surfaceless (jak tools/offscreen.c) ──────────────────
 * Kilka testów potrzebuje prawdziwego GL (cel silnika, akumulator). Brak EGL
 * albo GLES 3.0 (np. kontener bez Mesy) = jawne „POMINIĘTO” w wyjściu, nie
 * błąd — reszta testów jest czysta. */
#include <EGL/egl.h>
#include <EGL/eglext.h>

static bool test_egl_init(void) {
    EGLDisplay dpy = EGL_NO_DISPLAY;
    PFNEGLGETPLATFORMDISPLAYEXTPROC gpd = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
#ifdef EGL_PLATFORM_SURFACELESS_MESA
    if (gpd) dpy = gpd(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
#else
    (void)gpd;
#endif
    if (dpy == EGL_NO_DISPLAY) dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (dpy == EGL_NO_DISPLAY) return false;
    EGLint maj, min;
    if (!eglInitialize(dpy, &maj, &min) || !eglBindAPI(EGL_OPENGL_ES_API)) return false;
    /* domyślne EGL_SURFACE_TYPE to EGL_WINDOW_BIT — surfaceless takich nie ma */
    const EGLint cfg_attr[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE };
    EGLConfig cfg; EGLint n = 0;
    if (!eglChooseConfig(dpy, cfg_attr, &cfg, 1, &n) || n < 1) return false;
    const EGLint ctx_attr[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
    if (ctx == EGL_NO_CONTEXT) return false;
    if (eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) return true;
    const EGLint pb[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
    EGLSurface s = eglCreatePbufferSurface(dpy, cfg, pb);
    return s != EGL_NO_SURFACE && eglMakeCurrent(dpy, s, s, ctx);
}

/* Docelowy FBO RGBA8 w×h — to, co na żywo jest powierzchnią monitora. */
static GLuint test_dest_fbo(int w, int h, GLuint *tex) {
    GLuint fbo;
    glGenTextures(1, tex); glBindTexture(GL_TEXTURE_2D, *tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, *tex, 0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    return fbo;
}

/* Średnia kanału R klatki (0..255). */
static double test_fbo_mean(GLuint fbo, int w, int h) {
    unsigned char *px = malloc((size_t)w * h * 4);
    if (!px) { perror("malloc"); exit(1); }
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    double sum = 0;
    for (int i = 0; i < w * h; i++) sum += px[i * 4];
    free(px);
    return sum / (w * h);
}

/* Najprostsza animacja cząstkowa: cząstki stoją w losowych punktach, każdy
 * krok dokłada ślad. Bez rozgrzewki (`--once`) akumulator jest prawie pusty
 * (najwyżej 4 kroki na klatkę), po rozgrzewce 2 s × 60 kroków — nasycony. */
static const char *ONCE_UPDATE =
    "#pragma flux particles 16384\n"
    "#pragma flux life 10\n"
    "#pragma flux rate 60\n"
    "#pragma flux inc 0.001\n"
    "#pragma flux gain 2\n"
    "#pragma flux warmup 2\n"
    "void main() {\n"
    "    ivec2 idx = ivec2(gl_FragCoord.xy);\n"
    "    vec4 s = texelFetch(pos, idx, 0);\n"
    "    if (s.z < 0.5) { o = vec4(h2(idx.x, idx.y, seed), h2(idx.x + 911, idx.y + 7, seed), 1.0, 1.0); return; }\n"
    "    o = vec4(s.xy, s.z + 1.0, s.w);\n"
    "}\n";
static const char *ONCE_FRAG =
    "#version 300 es\n"
    "precision highp float;\n"
    "precision highp sampler2D;\n"
    "uniform sampler2D accum;\n"
    "uniform float gain;\n"
    "out vec4 fragColor;\n"
    "void main() {\n"
    "    float a = texelFetch(accum, ivec2(gl_FragCoord.xy), 0).r;\n"
    "    fragColor = vec4(vec3(clamp(a * gain, 0.0, 1.0)), 1.0);\n"
    "}\n";

int main(void) {
    float c[3];
    printf("parse_hex_color\n");
    CHECK(parse_hex_color("0F1A24", c) && near(c[0], 15/255.f) && near(c[1], 26/255.f) && near(c[2], 36/255.f), "0F1A24 bez #");
    CHECK(parse_hex_color("#D8E6EE", c) && near(c[0], 216/255.f) && near(c[2], 238/255.f), "#D8E6EE z #");
    CHECK(parse_hex_color("#d8e6ee", c) && near(c[0], 216/255.f), "małe litery");
    CHECK(!parse_hex_color("D8E6E", c),  "za krótki → odrzucony");
    CHECK(!parse_hex_color("D8E6EEFF", c), "z alfą (8 znaków) → odrzucony");
    CHECK(!parse_hex_color("GGGGGG", c), "nie-hex → odrzucony");
    CHECK(!parse_hex_color(NULL, c),     "NULL → odrzucony");
    CHECK(!parse_hex_color(" F1A24", c), "spacja w środku (strtol by ją łyknął) → odrzucony");
    CHECK(!parse_hex_color("-1-1-1", c), "znaki minus (strtol by je łyknął) → odrzucony");
    CHECK(!parse_hex_color("#-F-F-F", c), "z # i minusami → odrzucony");

    struct palette p;
    printf("parse_palette\n");
    CHECK(parse_palette("0F1A24,5C87A3,D8E6EE", &p) && near(p.ink[0], 92/255.f) && near(p.accent[1], 230/255.f), "trzy hexy");
    CHECK(parse_palette("#0F1A24,#5C87A3,#D8E6EE", &p), "trzy hexy z #");
    CHECK(!parse_palette("0F1A24,5C87A3", &p), "dwa hexy → odrzucone");
    CHECK(!parse_palette("0F1A24,5C87A3,D8E6EE,000000", &p), "cztery hexy → odrzucone");
    CHECK(!parse_palette("0F1A24,zzzzzz,D8E6EE", &p), "śmieć w środku → odrzucony");
    CHECK(!parse_palette("", &p), "pusty → odrzucony");

    /* Atrapa /sys/class/power_supply */
    char dir[] = "/tmp/flux-wall-test-XXXXXX";
    if (!mkdtemp(dir)) { perror("mkdtemp"); return 1; }
    char path[512];
    printf("battery_detail (atrapa: %s)\n", dir);

    CHECK(near(battery_detail(dir), 1.0f), "brak baterii → 1.0");

    snprintf(path, sizeof path, "%s/BAT0", dir); mkdir(path, 0755);
    snprintf(path, sizeof path, "%s/BAT0/capacity", dir); write_file(path, "42\n");
    snprintf(path, sizeof path, "%s/BAT0/status", dir);   write_file(path, "Discharging\n");
    CHECK(near(battery_detail(dir), 0.42f), "42% na baterii → 0.42");

    snprintf(path, sizeof path, "%s/BAT0/status", dir);   write_file(path, "Charging\n");
    CHECK(near(battery_detail(dir), 1.0f), "42% ale ładuje → 1.0 (zasilanie sieciowe)");

    write_file(path, "Full\n");
    CHECK(near(battery_detail(dir), 1.0f), "Full → 1.0");

    /* Zasilacz z limitem ładowania (np. 80 % z asusctl albo BIOS-u): bateria
     * stoi, kernel melduje `Not charging`, czasem `Unknown`. To zasilanie
     * sieciowe — obniżać wolno tylko przy `Discharging`. */
    snprintf(path, sizeof path, "%s/BAT0/capacity", dir); write_file(path, "80\n");
    snprintf(path, sizeof path, "%s/BAT0/status", dir);
    write_file(path, "Not charging\n");
    CHECK(near(battery_detail(dir), 1.0f), "80% Not charging (limit ładowania) → 1.0");
    write_file(path, "Unknown\n");
    CHECK(near(battery_detail(dir), 1.0f), "80% Unknown → 1.0");
    unlink(path);
    CHECK(near(battery_detail(dir), 1.0f), "80% bez pliku status → 1.0");

    write_file(path, "Discharging\n");
    snprintf(path, sizeof path, "%s/BAT0/capacity", dir); write_file(path, "117\n");
    CHECK(near(battery_detail(dir), 1.0f), "capacity > 100 → przycięte do 1.0");

    write_file(path, "abc\n");
    CHECK(near(battery_detail(dir), 1.0f), "śmieć w capacity → pominięte → 1.0");

    /* BAT0 bez sensu, BAT1 sensowna — ma wziąć BAT1 */
    snprintf(path, sizeof path, "%s/BAT1", dir); mkdir(path, 0755);
    snprintf(path, sizeof path, "%s/BAT1/capacity", dir); write_file(path, "7\n");
    snprintf(path, sizeof path, "%s/BAT1/status", dir);   write_file(path, "Discharging\n");
    CHECK(near(battery_detail(dir), 0.07f), "BAT0 uszkodzona, BAT1 7% → 0.07");

    /* Dwie baterie (np. ThinkPad): na baterii jedna się rozładowuje, druga
     * stoi — liczy się ta rozładowywana, nie pierwsza z listy. */
    snprintf(path, sizeof path, "%s/BAT0/capacity", dir); write_file(path, "90\n");
    snprintf(path, sizeof path, "%s/BAT0/status", dir);   write_file(path, "Not charging\n");
    CHECK(near(battery_detail(dir), 0.07f), "BAT0 90% Not charging, BAT1 7% Discharging → 0.07");
    snprintf(path, sizeof path, "%s/BAT1/status", dir);   write_file(path, "Not charging\n");
    CHECK(near(battery_detail(dir), 1.0f), "obie Not charging (zasilacz) → 1.0");

    /* #pragma flux — parser parametrów animacji cząstkowej */
    printf("flux_params_parse\n");
    char err[256];
    struct flux_params fp = FLUX_PARAMS_DEFAULT;
    CHECK(flux_params_parse("// bez pragm\nvoid main(){}\n", &fp, err, sizeof err) && fp.particles == 20000 && near(fp.life, 4.0f), "brak pragm → domyślne");
    fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
    CHECK(flux_params_parse("#pragma flux particles 20800\n  #pragma flux life 4.3\n#pragma flux splat 1\n#pragma flux warm 20\n#pragma flux seed 7\n", &fp, err, sizeof err)
          && fp.particles == 20800 && near(fp.life, 4.3f) && fp.splat == 1 && fp.warm == 20 && fp.seed == 7, "pięć kluczy (w tym z wcięciem)");
    fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
    CHECK(!flux_params_parse("#pragma flux particles abc\n", &fp, err, sizeof err) && strstr(err, "nie jest liczbą"), "wartość nie-liczba → błąd");
    CHECK(!flux_params_parse("#pragma flux kolor 1\n", &fp, err, sizeof err) && strstr(err, "nieznany klucz"), "nieznany klucz → błąd");
    CHECK(!flux_params_parse("#pragma flux life 0\n", &fp, err, sizeof err) && strstr(err, "poza zakresem"), "life 0 → poza zakresem");
    CHECK(!flux_params_parse("#pragma flux splat 2\n", &fp, err, sizeof err), "splat 2 → poza zakresem");
    CHECK(!flux_params_parse("#pragma flux life\n", &fp, err, sizeof err) && strstr(err, "klucz wartość"), "brak wartości → błąd");
    CHECK(!flux_params_parse("#pragma flux life 4 5\n", &fp, err, sizeof err), "nadmiarowy token → błąd");
    fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
    CHECK(flux_params_parse("#pragma once\n#pragma fluxx 1 2\n", &fp, err, sizeof err) && fp.particles == 20000, "inne pragmy ignorowane");
    fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
    CHECK(fp.audio == 0 && fp.audio_tempo == 0.0f, "domyślnie bez dźwięku i bez reakcji");
    CHECK(flux_params_parse("#pragma flux audio 1\n#pragma flux audio_tempo 0.6\n", &fp, err, sizeof err) && fp.audio == 1 && near(fp.audio_tempo, 0.6f), "audio 1 + audio_tempo");
    CHECK(!flux_params_parse("#pragma flux audio 2\n", &fp, err, sizeof err), "audio 2 → poza zakresem");
    /* NaN przechodził każde sprawdzenie zakresu (porównanie z NaN zawsze fałszywe),
     * a (int)NaN to zachowanie niezdefiniowane — audyt 2026-11-05, F9. */
    {
        static const char *keys[] = { "particles", "life", "rate", "inc", "gain", "scale", "warmup", "warm", "seed", "audio_tempo", "audio_glow", "audio_sparkle", NULL };
        int accepted = 0;
        for (int i = 0; keys[i]; i++) {
            char src[96]; snprintf(src, sizeof src, "#pragma flux %s nan\n", keys[i]);
            fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
            if (flux_params_parse(src, &fp, err, sizeof err)) { accepted++; printf("       przyjęte: %s nan\n", keys[i]); }
        }
        CHECK(accepted == 0, "wartość nan → błąd dla każdego klucza liczbowego");
        fp = (struct flux_params)FLUX_PARAMS_DEFAULT;
        CHECK(!flux_params_parse("#pragma flux life inf\n", &fp, err, sizeof err), "life inf → błąd");
        CHECK(flux_params_parse("#pragma flux life 0.5\n", &fp, err, sizeof err) && near(fp.life, 0.5f), "life 0.5 nadal przyjęte");
    }

    printf("flux_update_path\n");
    char up[64];
    CHECK(flux_update_path("shaders/dither-flow.frag", up, sizeof up) && strcmp(up, "shaders/dither-flow.update.glsl") == 0, ".frag → .update.glsl");
    CHECK(!flux_update_path("shaders/dither-flow.glsl", up, sizeof up), "nie-.frag → false");
    CHECK(!flux_update_path("shaders/dither-flow.frag", up, 8), "za mały bufor → false");

    printf("flux_strip_directives\n");
    {
        const char *src = "#version 300 es\n  #pragma flux life 4\nvoid main() {}\n\t#pragma flux seed 7";
        char *out = flux_strip_directives(src, true);
        CHECK(out && strlen(out) == strlen(src), "długość zachowana (numery linii w błędach kompilatora zgodne)");
        CHECK(out && strncmp(out, "#version 300 es\n", 16) == 0, "keep_version = true: #version zostaje");
        CHECK(out && strncmp(out + 16, "                     \n", 22) == 0, "linia #pragma flux (z wcięciem) → same spacje, \\n zostaje");
        CHECK(out && strstr(out, "void main() {}\n") == out + 38, "zwykła linia nietknięta");
        CHECK(out && strcmp(out + 53, "                    ") == 0, "ostatnia linia bez \\n też wyczyszczona");
        free(out);
        out = flux_strip_directives(src, false);
        CHECK(out && strncmp(out, "               \n", 16) == 0, "keep_version = false: #version → spacje (wersję niesie prelude)");
        free(out);
        out = flux_strip_directives("#pragma once\n#pragma fluxx 1\n#versionx\n", true);
        CHECK(out && strcmp(out, "#pragma once\n#pragma fluxx 1\n#versionx\n") == 0, "inne pragmy i podobne słowa nietknięte");
        free(out);
        out = flux_strip_directives("", true);
        CHECK(out && out[0] == 0, "pusty tekst → pusty");
        free(out);
    }

    printf("flux_warp / flux_step_cap\n");
    {
        struct flux_params wp = FLUX_PARAMS_DEFAULT;
        struct audio_features af = { .mid = 1.0f };
        CHECK(flux_warp(&wp, NULL, 1.0f) == 1.0, "bez audio → 1.0 (bit w bit jak bez muzyki)");
        CHECK(flux_warp(&wp, &af, 0.0f) == 1.0, "strength 0 → 1.0");
        CHECK(flux_warp(&wp, &af, 1.0f) == 1.0, "audio_tempo 0 (domyślne) → 1.0 nawet z mid = 1");
        wp.audio_tempo = 0.6f;
        CHECK(near((float)flux_warp(&wp, &af, 1.0f), 1.6f), "tempo 0.6 · mid 1 → 1.6");
        af.mid = 0.5f;
        CHECK(near((float)flux_warp(&wp, &af, 0.5f), 1.15f), "tempo 0.6 · strength 0.5 · mid 0.5 → 1.15");
        af.mid = -1.0f;
        CHECK(flux_warp(&wp, &af, 1.0f) == 1.0, "ujemne mid → nie spowalnia poniżej 1.0");

        CHECK(flux_step_cap(&wp, 0.0f) == 4, "bez audio → limit 4 kroków/klatkę");
        CHECK(flux_step_cap(&wp, 1.0f) == 8, "tempo 0.6 → 4·ceil(1.6) = 8");
        wp.audio_tempo = 0.0f;
        CHECK(flux_step_cap(&wp, 1.0f) == 4, "tempo 0 z audio → 4");
        wp.audio_tempo = 2.0f;
        CHECK(flux_step_cap(&wp, 0.5f) == 8, "tempo 2 · strength 0.5 → 4·ceil(2.0) = 8 (bez zaokrąglenia w górę)");
        CHECK(flux_step_cap(&wp, 1.0f) == 12, "tempo 2 · strength 1 → 4·ceil(3.0) = 12");
        wp.audio_tempo = 2.5f;
        CHECK(flux_step_cap(&wp, 1.0f) == 16, "tempo 2.5 → 4·ceil(3.5) = 16");
    }

    /* ── DSP audio (czyste funkcje) ─────────────────────────────────────── */
    printf("audio_fft_power\n");
    static struct audio_fft fft; audio_fft_init(&fft);
    static float sig[AUDIO_FFT_N]; static float pw[AUDIO_FFT_N / 2 + 1];
    const float f44 = 44.0f * AUDIO_RATE / AUDIO_FFT_N;                 /* 1031.25 Hz = środek binu 44 */
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = sinf(2.0f * TEST_PI * f44 * (float)i / AUDIO_RATE);
    audio_fft_power(&fft, sig, pw);
    int kpeak = 0; for (int k = 1; k <= AUDIO_FFT_N / 2; k++) if (pw[k] > pw[kpeak]) kpeak = k;
    CHECK(kpeak == 44, "sinus 1031.25 Hz → pik w binie 44");
    CHECK(pw[kpeak] > 0.9f && pw[kpeak] < 1.1f, "moc piku ~1.0 (normalizacja)");
    CHECK(pw[kpeak + 10] < pw[kpeak] * 0.001f && pw[kpeak - 10] < pw[kpeak] * 0.001f, "10 binów dalej < -30 dB");
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.0f;
    audio_fft_power(&fft, sig, pw);
    float tot = 0; for (int k = 0; k <= AUDIO_FFT_N / 2; k++) tot += pw[k];
    CHECK(tot == 0.0f, "cisza → moc 0");

    printf("audio_bands\n");
    struct audio_bands_raw raw;
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.5f * sinf(2.0f * TEST_PI * 60.0f * (float)i / AUDIO_RATE);
    audio_fft_power(&fft, sig, pw);
    audio_bands(pw, AUDIO_FFT_N / 2 + 1, AUDIO_RATE, sig, AUDIO_FFT_N, &raw);
    CHECK(raw.bass > 5.0f * raw.mid && raw.bass > 5.0f * raw.high, "60 Hz → energia w basie, nie w mid/high");
    CHECK(raw.level > 0.34f && raw.level < 0.36f, "RMS sinusa 0.5 ≈ 0.354 (2.56 okresu w oknie)");
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.5f * sinf(2.0f * TEST_PI * 6000.0f * (float)i / AUDIO_RATE);
    audio_fft_power(&fft, sig, pw);
    audio_bands(pw, AUDIO_FFT_N / 2 + 1, AUDIO_RATE, sig, AUDIO_FFT_N, &raw);
    CHECK(raw.high > 5.0f * raw.bass && raw.high > 5.0f * raw.mid, "6 kHz → energia w high");
    int nz = 0; for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) if (raw.spectrum[i] > 0.01f) nz++;
    CHECK(nz >= 1 && nz <= 3, "6 kHz w widmie log: 1–3 biny");
    /* Regresja 2026-09-17: pasma log węższe niż bin FFT (48–57, 57–68, 98–117 Hz)
     * były martwe — sinus w środku każdego z nich musi dać energię W TYM binie. */
    int dead = 0;
    for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) {
        float lo = 40.0f * powf(300.0f, (float)i / AUDIO_SPECTRUM_BINS);
        float hi = 40.0f * powf(300.0f, (float)(i + 1) / AUDIO_SPECTRUM_BINS);
        float fc = sqrtf(lo * hi);
        for (int j = 0; j < AUDIO_FFT_N; j++) sig[j] = 0.5f * sinf(2.0f * TEST_PI * fc * (float)j / AUDIO_RATE);
        audio_fft_power(&fft, sig, pw);
        audio_bands(pw, AUDIO_FFT_N / 2 + 1, AUDIO_RATE, sig, AUDIO_FFT_N, &raw);
        int kmax = 0; for (int k = 1; k < AUDIO_SPECTRUM_BINS; k++) if (raw.spectrum[k] > raw.spectrum[kmax]) kmax = k;
        if (raw.spectrum[i] < 0.05f || abs(kmax - i) > 1) dead++;
    }
    CHECK(dead == 0, "każde z 32 pasm log reaguje na sinus w swoim środku (żadnych martwych słupków)");

    printf("audio_spectro_column / pasma spektrogramu\n");
    {
        /* sinus 1 kHz → maksimum spektrogramu w paśmie zawierającym 1 kHz */
        for (int j = 0; j < AUDIO_FFT_N; j++) sig[j] = 0.5f * sinf(2.0f * TEST_PI * 1000.0f * (float)j / AUDIO_RATE);
        audio_fft_power(&fft, sig, pw);
        audio_bands(pw, AUDIO_FFT_N / 2 + 1, AUDIO_RATE, sig, AUDIO_FFT_N, &raw);
        int expect = (int)floorf(logf(1000.0f / AUDIO_SPECTRO_LO) / logf(AUDIO_SPECTRO_HI / AUDIO_SPECTRO_LO) * AUDIO_SPECTRO_BINS);
        int smax = 0; for (int k = 1; k < AUDIO_SPECTRO_BINS; k++) if (raw.spectro[k] > raw.spectro[smax]) smax = k;
        CHECK(abs(smax - expect) <= 1, "1 kHz → maksimum w oczekiwanym paśmie spektrogramu (±1)");
        static float col[AUDIO_SPECTRO_BINS];
        audio_spectro_column(raw.spectro, raw.spectro[smax], col);
        CHECK(near(col[smax], 1.0f), "pasmo szczytowe = 1.0 (0 dB względem szczytu)");
        int lowcnt = 0; for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) if (abs(k - smax) > 8 && col[k] > 0.3f) lowcnt++;
        CHECK(lowcnt == 0, "daleko od tonu < 0.3 (poniżej -42 dB)");
        float half[AUDIO_SPECTRO_BINS]; for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) half[k] = raw.spectro[k];
        half[smax] = raw.spectro[smax] * 0.1f;                   /* -20 dB */
        audio_spectro_column(half, raw.spectro[smax], col);
        CHECK(near(col[smax], 1.0f - 20.0f / AUDIO_SPECTRO_RANGE_DB), "-20 dB → 1 - 20/60");
        for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) half[k] = 0.0f;
        audio_spectro_column(half, 0.0f, col);
        int z = 0; for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) if (col[k] != 0.0f) z++;
        CHECK(z == 0, "cisza (peak 0) → cała kolumna 0");
    }

    printf("audio_trigger / audio_wave_fill\n");
    {
        static float mono[AUDIO_FFT_N], lft[AUDIO_FFT_N], rgt[AUDIO_FFT_N];
        /* sinus 100 Hz: okres 480 próbek; trigger ma zwrócić start na zboczu narastającym */
        for (int i = 0; i < AUDIO_FFT_N; i++) { mono[i] = 0.5f * sinf(2.0f * TEST_PI * 100.0f * (float)i / AUDIO_RATE); lft[i] = mono[i]; rgt[i] = -mono[i]; }
        int st1 = audio_trigger(mono, AUDIO_FFT_N, AUDIO_WAVE_N, 0.01f);
        CHECK(st1 >= 0 && st1 <= AUDIO_FFT_N - AUDIO_WAVE_N, "start mieści okno w buforze");
        CHECK(mono[st1] >= 0.0f && mono[st1] < 0.05f && mono[st1 + 10] > mono[st1], "start = zbocze narastające przy zerze");
        /* przesunięcie sygnału o 100 próbek → ślad ma zaczynać się w tej samej fazie */
        for (int i = 0; i < AUDIO_FFT_N; i++) mono[i] = 0.5f * sinf(2.0f * TEST_PI * 100.0f * (float)(i + 100) / AUDIO_RATE);
        int st2 = audio_trigger(mono, AUDIO_FFT_N, AUDIO_WAVE_N, 0.01f);
        CHECK(fabsf(mono[st2] - lft[st1]) < 0.02f && fabsf(mono[st2 + 50] - lft[st1 + 50]) < 0.02f, "po przesunięciu o 100 próbek okno stoi w tej samej fazie");
        for (int i = 0; i < AUDIO_FFT_N; i++) mono[i] = 0.0f;
        CHECK(audio_trigger(mono, AUDIO_FFT_N, AUDIO_WAVE_N, 0.01f) == AUDIO_FFT_N - AUDIO_WAVE_N, "cisza → najświeższe okno");
        for (int i = 0; i < AUDIO_FFT_N; i++) mono[i] = 0.004f * ((i & 1) ? 1.0f : -1.0f);
        CHECK(audio_trigger(mono, AUDIO_FFT_N, AUDIO_WAVE_N, 0.01f) == AUDIO_FFT_N - AUDIO_WAVE_N, "szum pod histerezą nie wyzwala triggera");
        struct audio_features wf; memset(&wf, 0, sizeof wf);
        for (int i = 0; i < AUDIO_FFT_N; i++) { lft[i] = 2.0f; rgt[i] = -0.25f; }
        audio_wave_fill(&wf, lft, rgt, AUDIO_FFT_N, AUDIO_FFT_N - AUDIO_WAVE_N);
        CHECK(wf.wave[0] == 1.0f && wf.wave[1] == -0.25f && wf.wave[2 * (AUDIO_WAVE_N - 1)] == 1.0f, "wave_fill: przeplot L/R i przycięcie do ±1");
        audio_wave_fill(&wf, lft, rgt, AUDIO_FFT_N, AUDIO_FFT_N);   /* start poza buforem → dosunięty */
        CHECK(wf.wave[2 * (AUDIO_WAVE_N - 1)] == 1.0f, "wave_fill: start poza buforem dosunięty do końca");
    }

    printf("audio_agc_step / audio_smooth\n");
    struct audio_agc agc = {0};
    CHECK(near(audio_agc_step(&agc, 0.5f, 0.02f, 0.004f), 1.0f), "pierwszy sygnał → 1.0 (peak = x)");
    CHECK(audio_agc_step(&agc, 0.25f, 0.02f, 0.004f) < 0.55f, "połowa peaku → ~0.5");
    for (int i = 0; i < 1000; i++) audio_agc_step(&agc, 0.0f, 0.02f, 0.004f);  /* 20 s ciszy (stała 2 s) */
    CHECK(near(agc.peak, 0.004f), "po 20 s peak opada do podłogi");
    CHECK(near(audio_agc_step(&agc, 0.002f, 0.02f, 0.004f), 0.5f), "sygnał pod podłogą → x/podłoga, nie 1.0");
    float sm = audio_smooth(0.0f, 1.0f, 0.02f, 0.03f, 0.25f);
    float sd = audio_smooth(1.0f, 0.0f, 0.02f, 0.03f, 0.25f);
    CHECK(sm > 0.4f && sd > 0.9f, "atak szybki (0→0.49), opadanie wolne (1→0.92)");

    printf("audio_beat_step\n");
    struct audio_beat bt = {0};
    int hits = 0;
    for (int i = 0; i < 110; i++) {                       /* impulsy co 500 ms, pierwszy po 200 ms */
        bool imp = (i % 25 == 10);
        float o = audio_beat_step(&bt, imp ? 1.0f : 0.1f, 0.02f);
        if (imp && o >= 0.99f) hits++;
    }
    CHECK(hits == 4, "4 impulsy co 500 ms → 4 detekcje");
    struct audio_beat bt2 = {0}; int onsets = 0;
    for (int i = 0; i < 100; i++) if (audio_beat_step(&bt2, 0.8f, 0.02f) >= 0.99f) onsets++;
    CHECK(onsets == 1, "ton ciągły → dokładnie jeden onset, bez serii");

    printf("audio_features_age\n");
    struct audio_features fe = { .level = 1.0f, .bass = 1.0f, .t = 10.0 };
    audio_features_age(&fe, 10.05, 0.25f);
    CHECK(near(fe.bass, 1.0f), "50 ms → bez zmian");
    audio_features_age(&fe, 10.6, 0.25f);
    CHECK(fe.bass < 0.2f, "500 ms → zgaszone");

    printf("audio_sample_clean\n");
    CHECK(audio_sample_clean(NAN) == 0.0f && audio_sample_clean(-NAN) == 0.0f, "NaN → 0");
    CHECK(audio_sample_clean(INFINITY) == 0.0f && audio_sample_clean(-INFINITY) == 0.0f, "±inf → 0");
    CHECK(audio_sample_clean(0.25f) == 0.25f && audio_sample_clean(-1.5f) == -1.5f, "liczba skończona bez zmian (także ponad pełną skalę)");

    printf("audio_analyze (cały łańcuch)\n");
    static struct audio_state st; audio_state_init(&st);
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.5f * sinf(2.0f * TEST_PI * 60.0f * (float)i / AUDIO_RATE);
    for (int i = 0; i < 20; i++) audio_analyze(&st, sig, 0.02f, 1.0 + i * 0.02);
    CHECK(st.out.bass > 0.8f && st.out.high < 0.2f, "bas 60 Hz przez 0.4 s → bass ~1, high ~0");
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.0f;
    for (int i = 0; i < 50; i++) audio_analyze(&st, sig, 0.02f, 2.0 + i * 0.02);
    CHECK(st.out.bass < 0.05f && st.out.level < 0.05f, "cisza 1 s → wszystko ~0");
    { int z = 0; for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) if (st.out.spectro[k] != 0.0f) z++;
      CHECK(z == 0, "cisza → kolumna spektrogramu dokładnie 0"); }
    for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.5f * sinf(2.0f * TEST_PI * 1000.0f * (float)i / AUDIO_RATE);
    for (int i = 0; i < 10; i++) audio_analyze(&st, sig, 0.02f, 3.0 + i * 0.02);
    { int smax = 0; for (int k = 1; k < AUDIO_SPECTRO_BINS; k++) if (st.out.spectro[k] > st.out.spectro[smax]) smax = k;
      int expect = (int)floorf(logf(1000.0f / AUDIO_SPECTRO_LO) / logf(AUDIO_SPECTRO_HI / AUDIO_SPECTRO_LO) * AUDIO_SPECTRO_BINS);
      /* szczyt AGC z basu 60 Hz jeszcze nie opadł (zanik ~2 s) → ton 1 kHz kilka dB pod 0 dB, ale > 0.9 */
      CHECK(abs(smax - expect) <= 1 && st.out.spectro[smax] > 0.9f, "ton 1 kHz w łańcuchu → szczyt spektrogramu > 0.9 we właściwym paśmie"); }

    printf("audio_start z pliku (wątek, bez serwera)\n");
    {
        char fpath[512]; snprintf(fpath, sizeof fpath, "%s/tone.f32", dir);
        FILE *tf = fopen(fpath, "wb");
        /* stereo przeplatane: L = 80 Hz, R = cisza → miks ma bas, przebieg R pusty */
        for (int i = 0; i < AUDIO_RATE; i++) {
            float v = 0.5f * sinf(2.0f * TEST_PI * 80.0f * (float)i / AUDIO_RATE), z = 0.0f;
            fwrite(&v, sizeof v, 1, tf); fwrite(&z, sizeof z, 1, tf);
        }
        fclose(tf);
        struct audio *au = audio_start(NULL, fpath, false);
        CHECK(au != NULL, "wątek wystartował");
        struct timespec ts = { 0, 400000000L }; nanosleep(&ts, NULL);
        struct audio_features snap; audio_snapshot(au, &snap);
        CHECK(snap.live && snap.bass > 0.5f && snap.t > 0.0, "po 0.4 s: live, bass > 0.5, znacznik czasu");
        float maxl = 0, maxr = 0;
        for (int i = 0; i < AUDIO_WAVE_N; i++) { if (fabsf(snap.wave[2*i]) > maxl) maxl = fabsf(snap.wave[2*i]); if (fabsf(snap.wave[2*i+1]) > maxr) maxr = fabsf(snap.wave[2*i+1]); }
        CHECK(maxl > 0.45f && maxr == 0.0f, "przebieg: L ma sinus 0.5, R jest ciszą (stereo rozdzielone)");
        CHECK(snap.wave[0] >= 0.0f && snap.wave[0] < 0.1f && snap.wave[2 * 30] > snap.wave[0], "trigger: okno zaczyna się na narastającym przejściu przez zero");
        audio_stop(au);
        remove(fpath);
    }

    /* Audyt 2026-11-05, F3: jedna próbka NaN w oknie FFT dawała level = nan
     * na stałe (auto-gain i wygładzanie nie wychodzą z NaN) — wizualizacja
     * muzyki stała do restartu. Ta sama ścieżka co strumień z serwera (push_hop). */
    printf("audio_start z pliku z próbkami NaN/inf (wątek, bez serwera)\n");
    {
        char fpath[512]; snprintf(fpath, sizeof fpath, "%s/nan.f32", dir);
        FILE *tf = fopen(fpath, "wb");
        for (int i = 0; i < AUDIO_RATE; i++) {
            float v = 0.5f * sinf(2.0f * TEST_PI * 80.0f * (float)i / AUDIO_RATE), z = 0.0f;
            if (i == 0)   v = NAN;
            if (i == 100) z = INFINITY;
            if (i == 200) v = -INFINITY;
            fwrite(&v, sizeof v, 1, tf); fwrite(&z, sizeof z, 1, tf);
        }
        fclose(tf);
        struct audio *au = audio_start(NULL, fpath, false);
        CHECK(au != NULL, "wątek wystartował");
        struct timespec ts = { 0, 400000000L }; nanosleep(&ts, NULL);
        struct audio_features snap; audio_snapshot(au, &snap);
        bool finite = isfinite(snap.level) && isfinite(snap.bass) && isfinite(snap.beat) && isfinite(snap.wave_peak);
        for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) finite = finite && isfinite(snap.spectrum[i]);
        for (int i = 0; i < AUDIO_WAVE_N * AUDIO_CHANNELS; i++) finite = finite && isfinite(snap.wave[i]);
        CHECK(finite, "po 0.4 s: wszystkie cechy skończone (NaN/inf nie zatruwa stanu)");
        CHECK(snap.live && snap.bass > 0.5f, "po 0.4 s: bas 80 Hz widoczny mimo uszkodzonych próbek");
        audio_stop(au);
        remove(fpath);
    }

    /* Audyt 2026-11-05, F8: po udanym otwarciu backoff wracał do 1, a po
     * zerwanym odczycie pętla od razu otwierała strumień ponownie — serwer,
     * który zrywa strumień zaraz po połączeniu, dostawał próby bez przerwy.
     * Atrapa libpulse wyżej: każdy strumień pada na pierwszym odczycie. */
    printf("audio: zerwany strumień → pauza przed ponowieniem (atrapa libpulse)\n");
    {
        atomic_store(&fake_pa_opens, 0);
        struct audio *au = audio_start(NULL, NULL, false);
        CHECK(au != NULL, "wątek wystartował");
        struct timespec ts = { 0, 300000000L }; nanosleep(&ts, NULL);
        int opens = atomic_load(&fake_pa_opens);
        printf("       prób połączenia po 0.3 s: %d\n", opens);
        CHECK(opens == 1, "po 0.3 s: jedna próba (pauza ~1 s po zerwaniu, nie pętla bez przerwy)");
        ts = (struct timespec){ 1, 200000000L }; nanosleep(&ts, NULL);
        opens = atomic_load(&fake_pa_opens);
        printf("       prób połączenia po 1.5 s: %d\n", opens);
        CHECK(opens == 2, "po 1.5 s: dwie próby (ponowienie po ~1 s, następna pauza ~2 s)");
        struct audio_features snap; audio_snapshot(au, &snap);
        CHECK(!snap.live, "zerwany strumień → live = false");
        audio_stop(au);
    }

    printf("CLI: --dither / --no-dither (uniform dither)\n");
    {
        char shader[600], log[4096];
        snprintf(shader, sizeof shader, "%s/cli.frag", dir);
        write_file(shader, "#version 300 es\nvoid main(){}\n");
        char *a_def[]  = { "flux-wall", "-s", shader, "-v", NULL };
        char *a_on[]   = { "flux-wall", "-s", shader, "-v", "--dither", NULL };
        char *a_last[] = { "flux-wall", "--dither", "-s", shader, "--no-dither", "-v", NULL };
        char *a_arg[]  = { "flux-wall", "-s", shader, "--dither=1", NULL };
        char *a_help[] = { "flux-wall", "--help", NULL };
        int rc = run_cli(dir, a_def, log, sizeof log);
        CHECK(rc == 2 && strstr(log, "dither: 0"), "domyślnie dither 0 (gładko), argumenty przyjęte (kod 2 = brak Waylanda)");
        rc = run_cli(dir, a_on, log, sizeof log);
        CHECK(rc == 2 && strstr(log, "dither: 1"), "--dither → dither 1");
        rc = run_cli(dir, a_last, log, sizeof log);
        CHECK(rc == 2 && strstr(log, "dither: 0"), "--dither … --no-dither → wygrywa ostatni (0)");
        rc = run_cli(dir, a_arg, log, sizeof log);
        CHECK(rc == 1, "--dither=1 (flaga bez wartości) → kod 1");
        rc = run_cli(dir, a_help, log, sizeof log);
        CHECK(rc == 0 && strstr(log, "--dither") && strstr(log, "--no-dither"), "--help zna --dither/--no-dither (wrapper po tym rozpoznaje binarkę)");
        remove(shader);
    }

    /* --ready-file: flux-wall.sh melduje „działa” dopiero po pierwszej klatce
     * (audyt 2026-11-05, F7). Plik powstaje z PID-em procesu i nigdy nie
     * nadpisuje istniejącego pliku ani nie idzie za dowiązaniem. */
    printf("flux_ready_mark (--ready-file)\n");
    {
        char rp[600], victim[600], link_path[600], got[64] = "", want[32];
        snprintf(rp, sizeof rp, "%s/flux-wall.ready", dir);
        snprintf(want, sizeof want, "%ld\n", (long)getpid());
        CHECK(flux_ready_mark(rp), "nowy plik → utworzony");
        FILE *f = fopen(rp, "r");
        if (f) { if (!fgets(got, sizeof got, f)) got[0] = 0; fclose(f); }
        CHECK(strcmp(got, want) == 0, "w pliku PID procesu");
        struct stat st;
        CHECK(stat(rp, &st) == 0 && (st.st_mode & 077) == 0, "prawa 0600 (bez dostępu dla innych)");
        CHECK(!flux_ready_mark(rp), "plik już jest → odmowa, bez nadpisania");
        remove(rp);
        snprintf(victim, sizeof victim, "%s/victim", dir);
        snprintf(link_path, sizeof link_path, "%s/flux-wall.ready.lnk", dir);
        write_file(victim, "cudzy\n");
        CHECK(symlink(victim, link_path) == 0 && !flux_ready_mark(link_path), "dowiązanie (np. podstawione w /tmp) → odmowa");
        got[0] = 0;
        f = fopen(victim, "r");
        if (f) { if (!fgets(got, sizeof got, f)) got[0] = 0; fclose(f); }
        CHECK(strcmp(got, "cudzy\n") == 0, "cel dowiązania nietknięty");
        remove(link_path); remove(victim);

        char shader[600], log[4096];
        snprintf(shader, sizeof shader, "%s/cli.frag", dir);
        write_file(shader, "#version 300 es\nvoid main(){}\n");
        char *a_ready[] = { "flux-wall", "-s", shader, "--ready-file", rp, NULL };
        char *a_help[]  = { "flux-wall", "--help", NULL };
        int rc = run_cli(dir, a_ready, log, sizeof log);
        struct stat st2;
        CHECK(rc == 2 && stat(rp, &st2) != 0, "--ready-file przyjęte (kod 2 = brak Waylanda), bez klatki brak pliku");
        rc = run_cli(dir, a_help, log, sizeof log);
        CHECK(rc == 0 && strstr(log, "--ready-file"), "--help wymienia --ready-file (wrapper wykrywa po nim nową binarkę)");
        remove(shader);
    }

    printf("CLI: -d (detail) — tylko liczba skończona z 0..1\n");
    {
        char shader[600], log[4096];
        snprintf(shader, sizeof shader, "%s/cli.frag", dir);
        write_file(shader, "#version 300 es\nvoid main(){}\n");
        /* -d nan przechodził `d < 0 || d > 1` (porównania z NaN fałszywe) —
         * audyt 2026-11-05, F9; kod 2 = argumenty przyjęte, dopiero brak Waylanda */
        char *a_nan[]  = { "flux-wall", "-s", shader, "-d", "nan", NULL };
        char *a_nnan[] = { "flux-wall", "-s", shader, "-d", "-nan", NULL };
        char *a_inf[]  = { "flux-wall", "-s", shader, "-d", "inf", NULL };
        char *a_ok[]   = { "flux-wall", "-s", shader, "-d", "0.5", NULL };
        char *a_out[]  = { "flux-wall", "-s", shader, "-d", "1.5", NULL };
        int rc = run_cli(dir, a_nan, log, sizeof log);
        CHECK(rc == 1, "-d nan → kod 1");
        rc = run_cli(dir, a_nnan, log, sizeof log);
        CHECK(rc == 1, "-d -nan → kod 1");
        rc = run_cli(dir, a_inf, log, sizeof log);
        CHECK(rc == 1, "-d inf → kod 1");
        rc = run_cli(dir, a_ok, log, sizeof log);
        CHECK(rc == 2, "-d 0.5 → przyjęte (kod 2 = brak Waylanda)");
        rc = run_cli(dir, a_out, log, sizeof log);
        CHECK(rc == 1, "-d 1.5 → kod 1");
        remove(shader);
    }

    /* --once (tapeta statyczna) liczy rozgrzewkę przed jedyną klatką. Zmiana
     * skali albo rozdzielczości odtwarza i czyści akumulator, więc kolejna
     * klatka też potrzebuje rozgrzewki — inaczej z obrazu zostawało samo tło
     * do restartu (audyt 2026-11-05, F2). */
    printf("GL: --once po zmianie rozmiaru celu (EGL surfaceless)\n");
    if (!test_egl_init()) {
        printf("  POMINIĘTO: brak EGL surfaceless / GLES 3.0 — test wymaga Mesy albo GPU\n");
    } else {
        char gerr[2560];
        struct flux_engine *ge = flux_engine_create(ONCE_FRAG, "test-once.frag", ONCE_UPDATE, "test-once.update.glsl",
                                                    gerr, sizeof gerr);
        struct flux_target *gt = ge ? flux_target_create(ge, 32, 32, gerr, sizeof gerr) : NULL;
        CHECK(ge && gt, "silnik i cel 32x32 (tryb cząstkowy)");
        if (!ge || !gt) printf("       %s\n", gerr);
        if (ge && gt) {
            struct palette gpal = { {0, 0, 0}, {1, 1, 1}, {1, 1, 1} };
            char msg[160];
            GLuint tex1, fbo1 = test_dest_fbo(32, 32, &tex1);
            flux_engine_render(ge, gt, fbo1, 0.0, &gpal, 1.0f, 0.0f, NULL, 0.0f, true);
            double m1 = test_fbo_mean(fbo1, 32, 32);
            snprintf(msg, sizeof msg, "--once: pierwsza klatka po rozgrzewce (średnia %.1f/255)", m1);
            CHECK(m1 > 128.0, msg);
            /* skala 1 → 1.5: bufor 32x32 → 48x48, nowy akumulator; klatka 5 s później */
            bool resized = flux_target_resize(gt, 48, 48, gerr, sizeof gerr);
            GLuint tex2, fbo2 = test_dest_fbo(48, 48, &tex2);
            flux_engine_render(ge, gt, fbo2, 5.0, &gpal, 1.0f, 0.0f, NULL, 0.0f, true);
            double m2 = test_fbo_mean(fbo2, 48, 48);
            snprintf(msg, sizeof msg, "--once po zmianie rozmiaru: rozgrzewka od nowa (średnia %.1f/255, przed %.1f)", m2, m1);
            CHECK(resized && m2 > 0.5 * m1, msg);
            glDeleteFramebuffers(1, &fbo1); glDeleteTextures(1, &tex1);
            glDeleteFramebuffers(1, &fbo2); glDeleteTextures(1, &tex2);
        }
        flux_target_destroy(gt);
        if (ge) flux_engine_destroy(ge);
    }

    /* sprzątanie */
    const char *files[] = { "BAT0/capacity", "BAT0/status", "BAT1/capacity", "BAT1/status", "BAT0", "BAT1", NULL };
    for (int i = 0; files[i]; i++) { snprintf(path, sizeof path, "%s/%s", dir, files[i]); remove(path); }
    rmdir(dir);

    printf("%s: %d błędów\n", failures ? "WYNIK" : "WSZYSTKO OK", failures);
    return failures ? 1 : 0;
}
