/*
 * archenemy - flux-wall: testy jednostkowe funkcji czystych (bez Waylanda/EGL),
 * czyste decyzje main.c (recovery.h, logic.h), CLI binarki (kody wyjścia
 * 1 i 2 — run_cli niżej), wątek audio z pliku
 * i z atrapy libpulse (run_pulse, open_stream) oraz sekcje GL na EGL
 * surfaceless (silnik bez Waylanda: --once po zmianie rozmiaru, błędny
 * shader; bez EGL — „POMINIĘTO” w wyjściu, nie błąd).
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
#include "recovery.h"
#include "logic.h"
#include "cli.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"  /* ZWLR_LAYER_SHELL_V1_LAYER_* */
#define TEST_PI 3.14159265f
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <time.h>
#include <pulse/error.h>
#include <pulse/simple.h>
float battery_detail(const char *power_supply_dir);
bool  flux_ready_mark(const char *path);
int   flux_wall_main(int argc, char **argv);   /* main() z main.c (-Dmain=flux_wall_main) */

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) printf("  ok   %s\n", msg); \
                              else { printf("  FAIL %s\n", msg); failures++; } } while (0)

static bool near(float a, float b) { return a - b < 0.002f && b - a < 0.002f; }

/* Atrapa libpulse-simple: definicje w tym pliku wygrywają przy linkowaniu
 * z biblioteką, więc wątek audio (audio.c: run_pulse, open_stream) w testach
 * NIGDY nie łączy się z prawdziwym serwerem dźwięku. fake_pa_setup przed
 * audio_start ustawia zachowanie: `reject` — urządzenie, którego
 * pa_simple_new odmawia (jak serwer bez domyślnego sinka; "*" = każde, czyli
 * brak serwera), `data_reads` — ile odczytów na strumień daje dane (sinus
 * 80 Hz 0.5 w obu kanałach, 20 ms na odczyt jak hop z serwera), potem
 * strumień się zrywa; 0 = zerwanie na pierwszym odczycie (serwer pada zaraz
 * po połączeniu). Atrapa zapisuje, o co prosił audio.c (urządzenia po
 * kolei, kierunek, format, fragment), i kiedy (próby, zerwania). Stan pod
 * muteksem: pisze wątek audio, czyta test. */
#define FAKE_PA_MAX 8
struct fake_pa_state {
    const char *reject;
    int data_reads, left;                /* odczyty z danymi: na strumień / zostało w bieżącym */
    int tries, opens, frees, fails;      /* pa_simple_new: wszystkie / udane; pa_simple_free; zerwania */
    int null_dev;                        /* próby z dev = NULL (domyślne ŹRÓDŁO serwera = mikrofon) */
    bool server_null;                    /* każda próba do domyślnego serwera */
    char dev[FAKE_PA_MAX][64];           /* urządzenia kolejnych prób */
    double t_try[FAKE_PA_MAX], t_fail[FAKE_PA_MAX];   /* zegar monotoniczny: próby / zerwania */
    pa_stream_direction_t dir;           /* kierunek, format i bufor ostatniej próby */
    pa_sample_spec ss;
    bool has_attr;
    uint32_t fragsize;
    long frame;                          /* faza sinusa ciągła między odczytami */
};
static pthread_mutex_t fake_pa_lock = PTHREAD_MUTEX_INITIALIZER;
static struct fake_pa_state fake_pa;
static char fake_pa_stream;

static double test_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ts.tv_nsec / 1e9;
}

static void test_sleep_ms(long ms) {
    struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

static void fake_pa_setup(const char *reject, int data_reads) {
    pthread_mutex_lock(&fake_pa_lock);
    memset(&fake_pa, 0, sizeof fake_pa);
    fake_pa.reject = reject;
    fake_pa.data_reads = data_reads;
    fake_pa.server_null = true;
    pthread_mutex_unlock(&fake_pa_lock);
}

static struct fake_pa_state fake_pa_get(void) {
    pthread_mutex_lock(&fake_pa_lock);
    struct fake_pa_state s = fake_pa;
    pthread_mutex_unlock(&fake_pa_lock);
    return s;
}

pa_simple *pa_simple_new(const char *server, const char *name, pa_stream_direction_t dir, const char *dev,
                         const char *stream_name, const pa_sample_spec *ss, const pa_channel_map *map,
                         const pa_buffer_attr *attr, int *error) {
    (void)name; (void)stream_name; (void)map;
    pthread_mutex_lock(&fake_pa_lock);
    int n = fake_pa.tries++;
    if (n < FAKE_PA_MAX) {
        snprintf(fake_pa.dev[n], sizeof fake_pa.dev[n], "%s", dev ? dev : "(NULL)");
        fake_pa.t_try[n] = test_now();
    }
    if (!dev) fake_pa.null_dev++;
    if (server) fake_pa.server_null = false;
    fake_pa.dir = dir;
    if (ss) fake_pa.ss = *ss;
    fake_pa.has_attr = attr != NULL;
    fake_pa.fragsize = attr ? attr->fragsize : 0;
    bool rejected = fake_pa.reject && (strcmp(fake_pa.reject, "*") == 0 || (dev && strcmp(fake_pa.reject, dev) == 0));
    if (!rejected) { fake_pa.opens++; fake_pa.left = fake_pa.data_reads; }
    pthread_mutex_unlock(&fake_pa_lock);
    if (rejected) { if (error) *error = PA_ERR_NOENTITY; return NULL; }
    return (pa_simple *)(void *)&fake_pa_stream;
}

int pa_simple_read(pa_simple *s, void *data, size_t bytes, int *error) {
    (void)s;
    size_t frames = bytes / (AUDIO_CHANNELS * sizeof(float));
    pthread_mutex_lock(&fake_pa_lock);
    bool more = fake_pa.left > 0;
    long frame = fake_pa.frame;
    if (more) { fake_pa.left--; fake_pa.frame += (long)frames; }
    else if (fake_pa.fails < FAKE_PA_MAX) fake_pa.t_fail[fake_pa.fails++] = test_now();
    pthread_mutex_unlock(&fake_pa_lock);
    if (!more) {
        if (error) *error = PA_ERR_CONNECTIONTERMINATED;
        return -1;
    }
    float *out = data;
    for (size_t i = 0; i < frames; i++)
        out[2 * i] = out[2 * i + 1] = 0.5f * sinf(2.0f * TEST_PI * 80.0f * (float)(frame + (long)i) / AUDIO_RATE);
    test_sleep_ms(20);                   /* hop 20 ms, jak z serwera */
    return 0;
}

void pa_simple_free(pa_simple *s) {
    (void)s;
    pthread_mutex_lock(&fake_pa_lock);
    fake_pa.frees++;
    pthread_mutex_unlock(&fake_pa_lock);
}

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

/* flux_parse_args w TYM procesie: stan getopt od nowa (optind = 0 to pełny
 * reset w glibc i musl), bez komunikatów getopt o nieznanej opcji; komunikat
 * złej wartości (to, co main() wypisałby na stderr) trafia do `msg`. */
static enum flux_args parse_cli(char **args, struct config *cfg, char *msg, size_t msglen) {
    int argc = 0;
    while (args[argc]) argc++;
    optind = 0;
    opterr = 0;
    char *buf = NULL;
    size_t len = 0;
    FILE *m = open_memstream(&buf, &len);
    if (!m) { perror("open_memstream"); exit(1); }
    enum flux_args r = flux_parse_args(argc, args, cfg, m);
    fclose(m);
    snprintf(msg, msglen, "%s", buf ? buf : "");
    free(buf);
    opterr = 1;
    return r;
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
    /* Czyste części rysowania audio z engine.c (bez GL). */
    printf("flux_spectro_advance / flux_spectro_bytes / flux_audio_uniform_values\n");
    {
        double acc = 0.0;
        CHECK(flux_spectro_advance(&acc, 0.02) == 1 && acc < 1e-9 && acc > -1e-9, "20 ms → 1 kolumna (50/s), bez reszty");
        acc = 0.0;
        int n1 = flux_spectro_advance(&acc, 0.01), n2 = flux_spectro_advance(&acc, 0.01);
        CHECK(n1 == 0 && n2 == 1, "2 × 10 ms → 0, potem 1 kolumna (ułamek przechodzi na następną klatkę)");
        acc = 0.0;
        int n3 = flux_spectro_advance(&acc, 1.0 / 144);
        CHECK(n3 == 0 && acc > 0.34 && acc < 0.35, "144 fps: 0 kolumn, 0.347 kolumny czeka");
        acc = 0.5;
        CHECK(flux_spectro_advance(&acc, 600.0) == FLUX_SPECTRO_MAX_COLS && acc == 0.0,
              "po 10 min uśpienia najwyżej 64 kolumny, bez zaległości");
        acc = 0.0;
        CHECK(flux_spectro_advance(&acc, 1.28) == 64 && acc < 1e-9, "dokładnie 64 kolumny → bez obcięcia");
        CHECK(flux_spectro_advance(&acc, 0.0) == 0, "dt 0 → 0 kolumn");

        struct audio_features af;
        memset(&af, 0, sizeof af);
        af.spectro[0] = 0.0f; af.spectro[1] = 0.5f; af.spectro[2] = 1.0f; af.spectro[3] = 2.0f; af.spectro[4] = -1.0f;
        af.spectro[AUDIO_SPECTRO_BINS - 1] = 0.1f;
        unsigned char col[AUDIO_SPECTRO_BINS];
        flux_spectro_bytes(&af, 1.0f, col);
        CHECK(col[0] == 0 && col[1] == 128 && col[2] == 255 && col[3] == 255 && col[4] == 0 &&
              col[AUDIO_SPECTRO_BINS - 1] == 26, "kolumna: 0 / 0.5 → 128 / 1 → 255 / nasycenie / ujemne → 0 / ostatni pas");
        flux_spectro_bytes(&af, 0.5f, col);
        CHECK(col[2] == 128 && col[3] == 255, "strength 0.5 skaluje przed kwantyzacją");
        memset(col, 7, sizeof col);
        flux_spectro_bytes(&af, 0.0f, col);
        bool empty = true;
        for (int i = 0; i < AUDIO_SPECTRO_BINS; i++) if (col[i]) empty = false;
        memset(col, 7, sizeof col);
        flux_spectro_bytes(NULL, 1.0f, col);
        for (int i = 0; i < AUDIO_SPECTRO_BINS; i++) if (col[i]) empty = false;
        CHECK(empty, "bez audio albo strength 0 → pusta kolumna (spektrogram dalej się przewija)");

        af.level = 0.1f; af.bass = 0.2f; af.lowmid = 0.3f; af.mid = 0.4f; af.high = 0.5f; af.beat = 0.6f; af.wave_peak = 0.7f;
        float v[6], peak;
        flux_audio_uniform_values(&af, 1.0f, v, &peak);
        CHECK(v[0] == 0.1f && v[1] == 0.2f && v[2] == 0.3f && v[3] == 0.4f && v[4] == 0.5f && v[5] == 0.6f && peak == 0.7f,
              "uniformy audio: level, bass, lowmid, mid, high, beat, wave_peak w tej kolejności");
        flux_audio_uniform_values(&af, 0.0f, v, &peak);
        bool zero = peak == 0.0f;
        for (int i = 0; i < 6; i++) if (v[i] != 0.0f) zero = false;
        flux_audio_uniform_values(NULL, 1.0f, v, &peak);
        for (int i = 0; i < 6; i++) if (v[i] != 0.0f) zero = false;
        CHECK(zero && peak == 0.0f, "bez audio albo strength 0 → zera");
    }

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
    /* Ułamkowe pokrycie (ta sama naprawa 2026-09-17): bin FFT na granicy dwóch
     * pasm dzieli moc między nie proporcjonalnie do nakładania się — nic nie
     * ginie, nic nie liczy się podwójnie. RMS pasma = sqrt(suma / szerokość
     * w binach), więc Σ rms² · szerokość = moc wszystkich binów. Sinusy w środku
     * binów 6, 21 i 85 — każdy z nich leży na granicy 150, 500 albo 2000 Hz.
     * Bin brany w całości (waga 1) liczy taki bin w obu pasmach. */
    {
        const float hz = (float)AUDIO_RATE / AUDIO_FFT_N;
        const int edge_bins[] = { 6, 21, 85 };
        int bad = 0;
        for (int e = 0; e < 3; e++) {
            for (int j = 0; j < AUDIO_FFT_N; j++)
                sig[j] = 0.5f * sinf(2.0f * TEST_PI * (float)edge_bins[e] * hz * (float)j / AUDIO_RATE);
            audio_fft_power(&fft, sig, pw);
            audio_bands(pw, AUDIO_FFT_N / 2 + 1, AUDIO_RATE, sig, AUDIO_FFT_N, &raw);
            float e_bands = (raw.bass * raw.bass * (150.0f - 20.0f) + raw.lowmid * raw.lowmid * (500.0f - 150.0f) +
                             raw.mid * raw.mid * (2000.0f - 500.0f) + raw.high * raw.high * (10000.0f - 2000.0f)) / hz;
            float e_all = 0.0f;
            for (int k = 0; k <= AUDIO_FFT_N / 2; k++) e_all += pw[k];
            if (fabsf(e_bands / e_all - 1.0f) > 0.01f) { bad++; printf("       bin %d: pasma %.4f, całość %.4f\n", edge_bins[e], e_bands, e_all); }
        }
        CHECK(bad == 0, "bin na granicy pasm dzielony proporcjonalnie (Σ energii pasm = energia widma ±1%)");
    }

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
    /* Przegląd 2026-11-15, R1: skończona próbka rzędu 1e20 przepełnia moc FFT
     * do inf. Auto-gain liczył wtedy inf/inf = NaN, klamra 0..1 go przepuszczała,
     * a NaN w wygładzaniu zostawał na zawsze — objaw jak F3 (wizualizacja stoi
     * do restartu), choć audio_sample_clean wpuszcza tylko liczby skończone. */
    {
        struct audio_agc ag = { .peak = 0.5f };
        float yi = audio_agc_step(&ag, INFINITY, 0.02f, 0.004f);
        float yn = audio_agc_step(&ag, NAN, 0.02f, 0.004f);
        CHECK(yi == 0.0f && yn == 0.0f && isfinite(ag.peak) && ag.peak < 0.5f,
              "agc: x = inf albo NaN → 0, szczyt zostaje skończony (bez inf/inf = NaN)");
        ag.peak = INFINITY;
        float yp = audio_agc_step(&ag, 0.002f, 0.02f, 0.004f);
        CHECK(near(yp, 0.5f) && near(ag.peak, 0.004f), "agc: szczyt inf (stan zatruty) → wraca do podłogi");
        ag.peak = NAN;
        yp = audio_agc_step(&ag, 0.002f, 0.02f, 0.004f);
        CHECK(near(yp, 0.5f) && near(ag.peak, 0.004f), "agc: szczyt NaN → wraca do podłogi");
        CHECK(audio_smooth(0.5f, NAN, 0.02f, 0.03f, 0.25f) == 0.5f && audio_smooth(0.5f, INFINITY, 0.02f, 0.03f, 0.25f) == 0.5f,
              "smooth: x = NaN albo inf → zostaje poprzednia wartość");
        float rec = audio_smooth(NAN, 1.0f, 0.02f, 0.03f, 0.25f);
        CHECK(isfinite(rec) && rec > 0.4f, "smooth: poprzednia NaN → liczy od 0 (stan wychodzi z NaN)");
    }

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
    /* Odstęp 150 ms między uderzeniami: drugie, mocniejsze uderzenie 100 ms po
     * pierwszym (ponad progiem 1.5 × średnia) się nie liczy, trzecie 200 ms po
     * pierwszym — tak. */
    {
        struct audio_beat b3 = {0};
        float o1 = 0, o2 = 0, o3 = 0;
        for (int i = 0; i <= 20; i++) {                            /* krok 20 ms; tło 0.1 */
            float in = i == 10 ? 1.0f : (i == 15 || i == 20) ? 2.0f : 0.1f;
            float o = audio_beat_step(&b3, in, 0.02f);
            if (i == 10) o1 = o;
            if (i == 15) o2 = o;                                   /* 100 ms po pierwszym */
            if (i == 20) o3 = o;                                   /* 200 ms po pierwszym */
        }
        CHECK(o1 >= 0.99f && o2 < 0.99f, "uderzenie 100 ms po poprzednim → bez detekcji (odstęp 150 ms)");
        CHECK(o3 >= 0.99f, "uderzenie 200 ms po poprzednim → detekcja");
    }

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

    /* Widmo 32 binów (uniform audio_spectrum — słupki bars/orb/tunnel, radar,
     * waterfall). Audyt 2026-11-24, U1: każdy bin był dzielony przez WŁASNY
     * szczyt z ~2 s, więc przy muzyce 28–29 z 32 słupków stało średnio ponad
     * 0.5 — ściana wysokich słupków zamiast kształtu muzyki. Decyzja
     * właściciela 2026-11-24 (1A): jeden wspólny szczyt dla wszystkich binów
     * i skala dB (AUDIO_SPECTRUM_RANGE_DB), a bin to ENERGIA pasma (suma mocy,
     * nie średnia) — szum różowy, czyli równa energia na oktawę, daje równe
     * słupki, a nie opadające o 3 dB na oktawę. */
    printf("audio_analyze: widmo 32 binów — wspólny szczyt i skala dB\n");
    {
        static struct audio_state ws; audio_state_init(&ws);
        const int b_lo = 18, b_hi = 27;                /* środki binów: ~1082 Hz i ~5380 Hz */
        float f_lo = 40.0f * powf(300.0f, ((float)b_lo + 0.5f) / AUDIO_SPECTRUM_BINS);
        float f_hi = 40.0f * powf(300.0f, ((float)b_hi + 0.5f) / AUDIO_SPECTRUM_BINS);
        for (int i = 0; i < AUDIO_FFT_N; i++)
            sig[i] = 0.5f  * sinf(2.0f * TEST_PI * f_lo * (float)i / AUDIO_RATE)
                   + 0.05f * sinf(2.0f * TEST_PI * f_hi * (float)i / AUDIO_RATE);   /* drugi ton 20 dB ciszej */
        for (int i = 0; i < 50; i++) audio_analyze(&ws, sig, 0.02f, 1.0 + i * 0.02);
        printf("       ton głośny %.3f, ton -20 dB %.3f, bin bez sygnału %.3f\n",
               ws.out.spectrum[b_lo], ws.out.spectrum[b_hi], ws.out.spectrum[5]);
        CHECK(ws.out.spectrum[b_lo] > 0.95f, "najgłośniejszy bin → ~1.0 (0 dB względem wspólnego szczytu)");
        CHECK(fabsf(ws.out.spectrum[b_hi] - (1.0f - 20.0f / AUDIO_SPECTRUM_RANGE_DB)) < 0.06f,
              "ton o 20 dB cichszy → 1 - 20/zakres (nie ~1.0 jak przy szczycie per bin)");
        CHECK(ws.out.spectrum[5] < 0.02f, "bin bez sygnału → 0");

        /* szum różowy (filtr Kelleta na LCG), okno przesuwane hopami jak w wątku */
        audio_state_init(&ws);
        static float ring[AUDIO_FFT_N];
        memset(ring, 0, sizeof ring);
        uint32_t lcg = 12345u;
        float kb[6] = {0};
        static double acc_bin[AUDIO_SPECTRUM_BINS];
        memset(acc_bin, 0, sizeof acc_bin);
        int counted = 0;
        for (int h = 0; h < 250; h++) {                /* 5 s; średnie z ostatnich 2 s */
            memmove(ring, ring + AUDIO_HOP, (AUDIO_FFT_N - AUDIO_HOP) * sizeof(float));
            for (int i = 0; i < AUDIO_HOP; i++) {
                lcg = lcg * 1664525u + 1013904223u;
                float w = (float)(lcg >> 8) / 16777216.0f * 2.0f - 1.0f;
                kb[0] = 0.99886f * kb[0] + w * 0.0555179f; kb[1] = 0.99332f * kb[1] + w * 0.0750759f;
                kb[2] = 0.96900f * kb[2] + w * 0.1538520f; kb[3] = 0.86650f * kb[3] + w * 0.3104856f;
                kb[4] = 0.55000f * kb[4] + w * 0.5329522f; kb[5] = -0.7616f * kb[5] - w * 0.0168980f;
                ring[AUDIO_FFT_N - AUDIO_HOP + i] = (kb[0] + kb[1] + kb[2] + kb[3] + kb[4] + kb[5] + w * 0.5362f) * 0.04f;
            }
            audio_analyze(&ws, ring, 0.02f, 10.0 + h * 0.02);
            if (h >= 150) { for (int b = 0; b < AUDIO_SPECTRUM_BINS; b++) acc_bin[b] += ws.out.spectrum[b]; counted++; }
        }
        double mn = 1e9, mx = -1e9;
        for (int b = 0; b < AUDIO_SPECTRUM_BINS; b++) {
            double m = acc_bin[b] / counted;
            if (m < mn) mn = m;
            if (m > mx) mx = m;
        }
        printf("       szum różowy: średnie binów %.3f..%.3f\n", mn, mx);
        CHECK(mx - mn < 0.15, "szum różowy (równa energia na oktawę) → słupki równe: rozrzut średnich < 0.15");
        CHECK(mn > 0.5 && mx < 0.98, "szum różowy: słupki wysoko, ale pod sufitem (szczyt łapie chwilowe maksima)");
        for (int i = 0; i < AUDIO_FFT_N; i++) ring[i] = 0.0f;
        for (int i = 0; i < 100; i++) audio_analyze(&ws, ring, 0.02f, 20.0 + i * 0.02);
        float left = 0.0f;
        for (int b = 0; b < AUDIO_SPECTRUM_BINS; b++) if (ws.out.spectrum[b] > left) left = ws.out.spectrum[b];
        CHECK(left < 0.01f, "cisza 2 s → całe widmo ~0");
    }

    /* Bramka szumu −60 dBFS (AUDIO_GATE 0.001 RMS): cichy szum toru nie może
     * zostać wzmocniony przez auto-gain do pełnej reakcji. Sinus 60 Hz o RMS
     * 0.0005 (−66 dBFS) → wszystko dokładnie 0; RMS 0.003 (−50 dBFS) → reaguje
     * (level = 0.003 / podłoga 0.004 ≈ 0.75). Sama cisza cyfrowa (zera) tego
     * nie sprawdza — zera dają 0 także bez bramki. */
    printf("audio_analyze: bramka ciszy\n");
    {
        static struct audio_state gs;
        const float amp[2] = { 0.0005f * 1.41421356f, 0.003f * 1.41421356f };
        float lvl[2], bas[2]; int nz[2];
        for (int g = 0; g < 2; g++) {
            audio_state_init(&gs);
            for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = amp[g] * sinf(2.0f * TEST_PI * 60.0f * (float)i / AUDIO_RATE);
            for (int i = 0; i < 20; i++) audio_analyze(&gs, sig, 0.02f, 1.0 + i * 0.02);
            lvl[g] = gs.out.level; bas[g] = gs.out.bass; nz[g] = 0;
            for (int k = 0; k < AUDIO_SPECTRO_BINS; k++) if (gs.out.spectro[k] != 0.0f) nz[g]++;
        }
        CHECK(lvl[0] == 0.0f && bas[0] == 0.0f && nz[0] == 0, "−66 dBFS (pod bramką) → level, bass i spektrogram dokładnie 0");
        CHECK(lvl[1] > 0.5f && nz[1] > 0, "−50 dBFS (nad bramką) → reaguje (level > 0.5, spektrogram niepusty)");
    }

    /* Przegląd 2026-11-15, R1: okno z jedną skończoną próbką 1e20 w środku
     * (waga Hanna ~1) → |X_k|² ponad FLT_MAX, moc FFT = inf we wszystkich binach.
     * Po trzech takich oknach czysty bas 80 Hz ma być widoczny po 0.4 s, a nie
     * NaN do restartu. Moc skończona, ale olbrzymia (próbka 1e18–1e19 albo na
     * brzegu okna) to inna sprawa: szczyt auto-gain opada wtedy ~100 s —
     * przycinanie próbek czeka na decyzję właściciela (partia 1). */
    printf("audio_analyze: okno z mocą FFT = inf (próbka 1e20)\n");
    {
        static struct audio_state hs; audio_state_init(&hs);
        for (int i = 0; i < AUDIO_FFT_N; i++) sig[i] = 0.5f * sinf(2.0f * TEST_PI * 80.0f * (float)i / AUDIO_RATE);
        for (int i = 0; i < 20; i++) audio_analyze(&hs, sig, 0.02f, 1.0 + i * 0.02);
        float clean = sig[AUDIO_FFT_N / 2];
        sig[AUDIO_FFT_N / 2] = 1e20f;
        audio_fft_power(&hs.fft, sig, pw);
        CHECK(isinf(pw[3]) && isinf(pw[100]), "warunek testu: moc FFT okna z próbką 1e20 = inf");
        for (int i = 0; i < 3; i++) audio_analyze(&hs, sig, 0.02f, 1.4 + i * 0.02);
        sig[AUDIO_FFT_N / 2] = clean;
        for (int i = 0; i < 20; i++) audio_analyze(&hs, sig, 0.02f, 1.46 + i * 0.02);
        const struct audio_features *o = &hs.out;
        bool finite = isfinite(o->level) && isfinite(o->bass) && isfinite(o->lowmid) && isfinite(o->mid)
                   && isfinite(o->high) && isfinite(o->beat);
        for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) finite = finite && isfinite(o->spectrum[i]);
        for (int i = 0; i < AUDIO_SPECTRO_BINS; i++) finite = finite && isfinite(o->spectro[i]);
        finite = finite && isfinite(hs.agc_bass.peak) && isfinite(hs.agc_spectro.peak);
        CHECK(finite, "po oknach z mocą inf: cechy i szczyty auto-gain skończone");
        CHECK(o->bass > 0.5f, "0.4 s czystego basu 80 Hz po oknach z mocą inf → bass > 0.5 (nie zamarza)");
    }

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

    /* Przegląd 2026-11-15, R1: ten sam scenariusz ze SKOŃCZONĄ próbką 1e20
     * (audio_sample_clean ją przepuszcza). W pierwszym oknie moc FFT = inf —
     * dawniej cechy NaN do restartu. W drugim oknie próbka leży na brzegu
     * Hanna i moc jest skończona, ale olbrzymia: auto-gain ścisza wtedy bas
     * na ~100 s (to sprawa przycinania próbek, decyzja właściciela), więc
     * tu sprawdzamy tylko, że stan nie zostaje NaN. */
    printf("audio_start z pliku ze skończoną próbką 1e20 (wątek, bez serwera)\n");
    {
        char fpath[512]; snprintf(fpath, sizeof fpath, "%s/huge.f32", dir);
        FILE *tf = fopen(fpath, "wb");
        for (int i = 0; i < AUDIO_RATE; i++) {
            float v = 0.5f * sinf(2.0f * TEST_PI * 80.0f * (float)i / AUDIO_RATE), z = 0.0f;
            if (i == 0) v = 1e20f;
            fwrite(&v, sizeof v, 1, tf); fwrite(&z, sizeof z, 1, tf);
        }
        fclose(tf);
        struct audio *au = audio_start(NULL, fpath, false);
        CHECK(au != NULL, "wątek wystartował");
        struct timespec ts = { 0, 400000000L }; nanosleep(&ts, NULL);
        struct audio_features snap; audio_snapshot(au, &snap);
        bool finite = isfinite(snap.level) && isfinite(snap.bass) && isfinite(snap.lowmid) && isfinite(snap.mid)
                   && isfinite(snap.high) && isfinite(snap.beat) && isfinite(snap.wave_peak);
        for (int i = 0; i < AUDIO_SPECTRUM_BINS; i++) finite = finite && isfinite(snap.spectrum[i]);
        for (int i = 0; i < AUDIO_SPECTRO_BINS; i++) finite = finite && isfinite(snap.spectro[i]);
        for (int i = 0; i < AUDIO_WAVE_N * AUDIO_CHANNELS; i++) finite = finite && isfinite(snap.wave[i]);
        CHECK(snap.live && finite, "po 0.4 s: wszystkie cechy skończone (moc FFT = inf nie zatruwa stanu)");
        audio_stop(au);
        remove(fpath);
    }

    /* Miks do analizy to (L+R)/2, nie jeden kanał: sam R ma bas (pierwszy
     * test pliku ma sam L). Plik ma dokładnie 10 hopów (0.2 s): fread
     * kończy się wtedy równo na końcu pliku (got == 0 przy ftell ≠ 0)
     * i plik ma się zapętlić — stop jest tylko dla pustego pliku. */
    printf("audio_start z pliku: kanał R, plik krótszy niż bieg (zapętlenie)\n");
    {
        char fpath[512]; snprintf(fpath, sizeof fpath, "%s/right.f32", dir);
        FILE *tf = fopen(fpath, "wb");
        for (int i = 0; i < 10 * AUDIO_HOP; i++) {
            float v = 0.5f * sinf(2.0f * TEST_PI * 80.0f * (float)i / AUDIO_RATE), z = 0.0f;
            fwrite(&z, sizeof z, 1, tf); fwrite(&v, sizeof v, 1, tf);
        }
        fclose(tf);
        struct audio *au = audio_start(NULL, fpath, false);
        CHECK(au != NULL, "wątek wystartował");
        struct timespec ts = { 0, 600000000L }; nanosleep(&ts, NULL);
        struct audio_features snap; audio_snapshot(au, &snap);
        CHECK(snap.live, "po 0.6 s (trzeci obieg pliku 0.2 s): nadal live — plik się zapętla");
        CHECK(snap.bass > 0.5f, "bas 80 Hz tylko w kanale R → widoczny w analizie (miks L+R)");
        float maxl = 0, maxr = 0;
        for (int i = 0; i < AUDIO_WAVE_N; i++) { if (fabsf(snap.wave[2*i]) > maxl) maxl = fabsf(snap.wave[2*i]); if (fabsf(snap.wave[2*i+1]) > maxr) maxr = fabsf(snap.wave[2*i+1]); }
        CHECK(maxl == 0.0f && maxr > 0.45f, "przebieg: L cisza, R sinus 0.5");
        audio_stop(au);
        remove(fpath);
    }

    /* Pusty plik: wątek kończy pracę (live = false), zamiast kręcić się
     * w kółko na pustym odczycie i meldować ciszę jako dźwięk na żywo. */
    printf("audio_start z pustego pliku\n");
    {
        char fpath[512]; snprintf(fpath, sizeof fpath, "%s/empty.f32", dir);
        write_file(fpath, "");
        struct audio *au = audio_start(NULL, fpath, false);
        CHECK(au != NULL, "wątek wystartował");
        struct timespec ts = { 0, 200000000L }; nanosleep(&ts, NULL);
        struct audio_features snap; audio_snapshot(au, &snap);
        CHECK(!snap.live, "po 0.2 s: live = false (pusty plik nie jest pętlą ciszy)");
        audio_stop(au);
        remove(fpath);
    }

    /* Audyt 2026-11-05, F8: po udanym otwarciu backoff wracał do 1, a po
     * zerwanym odczycie pętla od razu otwierała strumień ponownie — serwer,
     * który zrywa strumień zaraz po połączeniu, dostawał próby bez przerwy.
     * Atrapa libpulse wyżej: każdy strumień pada na pierwszym odczycie. */
    printf("audio: zerwany strumień → pauza przed ponowieniem (atrapa libpulse)\n");
    {
        fake_pa_setup(NULL, 0);
        struct audio *au = audio_start(NULL, NULL, false);
        CHECK(au != NULL, "wątek wystartował");
        struct timespec ts = { 0, 300000000L }; nanosleep(&ts, NULL);
        int opens = fake_pa_get().opens;
        printf("       prób połączenia po 0.3 s: %d\n", opens);
        CHECK(opens == 1, "po 0.3 s: jedna próba (pauza ~1 s po zerwaniu, nie pętla bez przerwy)");
        ts = (struct timespec){ 1, 200000000L }; nanosleep(&ts, NULL);
        opens = fake_pa_get().opens;
        printf("       prób połączenia po 1.5 s: %d\n", opens);
        CHECK(opens == 2, "po 1.5 s: dwie próby (ponowienie po ~1 s, następna pauza ~2 s)");
        struct audio_features snap; audio_snapshot(au, &snap);
        CHECK(!snap.live, "zerwany strumień → live = false");
        audio_stop(au);
    }

    /* run_pulse i open_stream (audyt 2026-11-05, KT5). Źródło to zawsze
     * MONITOR wyjścia: najpierw @DEFAULT_MONITOR@, potem --audio-device;
     * nigdy dev = NULL, bo to domyślne ŹRÓDŁO serwera, czyli mikrofon
     * (DECYZJE 2026-09-08). Strumień: nagrywanie, float32 stereo 48 kHz,
     * fragment = jeden hop. Czasy przerw mierzy atrapa (próba vs zerwanie),
     * test czeka na zdarzenia, nie na stałe opóźnienia — przerwa nie bywa
     * krótsza niż zadana, a górne granice mają zapas na obciążony rdzeń. */
    printf("audio: run_pulse / open_stream — monitor wyjścia, dane, zerwanie (atrapa libpulse)\n");
    {
        fake_pa_setup(NULL, 15);                       /* każdy strumień: 15 hopów (0.3 s), potem zerwanie */
        struct audio *au = audio_start(NULL, NULL, false);
        CHECK(au != NULL, "wątek wystartował");
        struct audio_features snap = {0};
        bool heard = false;
        for (double end = test_now() + 2.0; !heard && test_now() < end; test_sleep_ms(5)) {
            audio_snapshot(au, &snap);
            heard = snap.live && snap.bass > 0.5f;
        }
        CHECK(heard, "dane ze strumienia → live, bas 80 Hz widoczny w analizie");
        struct fake_pa_state fs = fake_pa_get();
        CHECK(fs.tries >= 1 && strcmp(fs.dev[0], "@DEFAULT_MONITOR@") == 0, "pierwsza próba: @DEFAULT_MONITOR@ (monitor wyjścia)");
        CHECK(fs.dir == PA_STREAM_RECORD && fs.server_null, "nagrywanie z domyślnego serwera");
        CHECK(fs.ss.format == PA_SAMPLE_FLOAT32NE && fs.ss.rate == AUDIO_RATE && fs.ss.channels == AUDIO_CHANNELS,
              "format strumienia: float32 stereo 48 kHz (jak --audio-file)");
        CHECK(fs.has_attr && fs.fragsize == AUDIO_HOP * AUDIO_CHANNELS * sizeof(float), "fragment = jeden hop (20 ms)");
        bool dark = false;                             /* live gaśnie w pauzie, przed następną próbą */
        for (double end = test_now() + 3.0; test_now() < end; test_sleep_ms(5)) {
            fs = fake_pa_get();
            if (fs.tries >= 2) break;
            audio_snapshot(au, &snap);
            if (fs.fails >= 1 && !snap.live) { dark = true; break; }
        }
        CHECK(dark, "po zerwaniu strumienia live = false (w pauzie przed ponowieniem)");
        for (double end = test_now() + 6.0; fake_pa_get().tries < 3 && test_now() < end; ) test_sleep_ms(10);
        audio_stop(au);
        for (double end = test_now() + 1.0; test_now() < end; test_sleep_ms(10)) {
            fs = fake_pa_get();
            if (fs.frees == fs.opens) break;           /* audio_stop czeka na wątek tylko 200 ms */
        }
        double g1 = fs.t_try[1] - fs.t_fail[0], g2 = fs.t_try[2] - fs.t_fail[1];
        printf("       przerwy od zerwania do ponowienia: %.2f s, %.2f s\n", g1, g2);
        CHECK(fs.tries >= 3 && fs.fails >= 2 && g1 >= 0.95 && g1 < 1.6 && g2 >= 0.95 && g2 < 1.6,
              "po strumieniu z danymi przerwa wraca do 1 s (bez powrotu druga trwałaby 2 s)");
        CHECK(fs.null_dev == 0 && fs.opens >= 3 && fs.frees == fs.opens, "ani razu dev = NULL; każdy otwarty strumień zwolniony");
    }
    printf("audio: @DEFAULT_MONITOR@ odmawia → --audio-device (atrapa libpulse)\n");
    {
        fake_pa_setup("@DEFAULT_MONITOR@", 15);        /* serwer bez domyślnego sinka */
        struct audio *au = audio_start("test-sink.monitor", NULL, false);
        CHECK(au != NULL, "wątek wystartował (--audio-device test-sink.monitor)");
        struct audio_features snap = {0};
        bool heard = false;
        for (double end = test_now() + 2.0; !heard && test_now() < end; test_sleep_ms(5)) {
            audio_snapshot(au, &snap);
            heard = snap.live && snap.bass > 0.5f;
        }
        audio_stop(au);
        struct fake_pa_state fs = fake_pa_get();
        CHECK(heard, "dane z --audio-device → live, bas 80 Hz");
        CHECK(fs.tries == 2 && strcmp(fs.dev[0], "@DEFAULT_MONITOR@") == 0 && strcmp(fs.dev[1], "test-sink.monitor") == 0 &&
              fs.opens == 1, "najpierw @DEFAULT_MONITOR@, po odmowie --audio-device (monitor sinka z wrappera)");
    }
    printf("audio: brak serwera dźwięku → nigdy mikrofon, przerwa się podwaja (atrapa libpulse)\n");
    {
        fake_pa_setup("*", 0);
        struct audio *au = audio_start(NULL, NULL, false);
        CHECK(au != NULL, "wątek wystartował (bez serwera, bez --audio-device)");
        for (double end = test_now() + 6.0; fake_pa_get().tries < 3 && test_now() < end; ) test_sleep_ms(10);
        struct audio_features snap; audio_snapshot(au, &snap);
        audio_stop(au);
        struct fake_pa_state fs = fake_pa_get();
        bool monitors = fs.tries >= 1;
        for (int i = 0; i < fs.tries && i < FAKE_PA_MAX; i++) if (strcmp(fs.dev[i], "@DEFAULT_MONITOR@") != 0) monitors = false;
        CHECK(fs.null_dev == 0 && monitors, "każda próba to @DEFAULT_MONITOR@, nigdy dev = NULL (mikrofon)");
        CHECK(!snap.live && fs.opens == 0, "bez serwera: live = false, nic nie otwarte");
        double g1 = fs.t_try[1] - fs.t_try[0], g2 = fs.t_try[2] - fs.t_try[1];
        printf("       przerwy między próbami: %.2f s, %.2f s\n", g1, g2);
        CHECK(fs.tries >= 3 && g1 >= 0.95 && g1 < 1.6 && g2 >= 1.95 && g2 < 2.8,
              "przerwa między próbami 1 s, potem 2 s (backoff się podwaja)");
    }

    /* Audyt 2026-11-24, U4: komunikaty audio szły tylko z -v, którego wrapper
     * nie podaje — brak serwera albo zły monitor nie zostawiał w flux-wall.log
     * żadnego śladu. Bez -v do logu ma trafić: pierwsze połączenie z nazwą
     * źródła, zerwanie, a brak połączenia RAZ na przerwę (nie co próbę).
     * audio_source oddaje nazwę źródła bieżącego strumienia (linia stanu -v),
     * raw_level — surowy RMS okna (sinus 0.5 → 0.354). */
    printf("audio: log stanu strumienia bez -v, nazwa źródła, surowy poziom (atrapa libpulse)\n");
    {
        FILE *lf = tmpfile();
        CHECK(lf != NULL, "plik tymczasowy na log");
        audio_log_stream(lf);
        fake_pa_setup("@DEFAULT_MONITOR@", 15);        /* 0.3 s danych z --audio-device, potem zerwanie */
        struct audio *au = audio_start("test-sink.monitor", NULL, false);
        struct audio_features snap = {0};
        char src[128] = "?";
        bool heard = false;
        for (double end = test_now() + 2.0; !heard && test_now() < end; test_sleep_ms(5)) {
            audio_snapshot(au, &snap);
            heard = snap.live && snap.bass > 0.5f;
            if (heard) audio_source(au, src, sizeof src);
        }
        CHECK(heard && strcmp(src, "test-sink.monitor") == 0, "audio_source: nazwa źródła bieżącego strumienia");
        CHECK(fabsf(snap.raw_level - 0.3536f) < 0.02f, "raw_level: surowy RMS okna (sinus 0.5 → 0.354), nie wartość po auto-gain");
        for (double end = test_now() + 3.0; fake_pa_get().fails < 1 && test_now() < end; ) test_sleep_ms(10);
        test_sleep_ms(60);                             /* wątek zdąży zapisać linię o zerwaniu */
        audio_source(au, src, sizeof src);
        CHECK(src[0] == 0, "audio_source po zerwaniu: pusty napis (brak połączenia)");
        audio_stop(au);
        fake_pa_setup("*", 0);                         /* brak serwera: próby po 0, 1 i 3 s */
        au = audio_start(NULL, NULL, false);
        for (double end = test_now() + 4.0; fake_pa_get().tries < 2 && test_now() < end; ) test_sleep_ms(10);
        audio_stop(au);
        audio_log_stream(NULL);
        static char logbuf[4096];
        rewind(lf);
        size_t ln = fread(logbuf, 1, sizeof logbuf - 1, lf);
        logbuf[ln] = 0;
        int n_conn = 0, n_lost = 0, n_none = 0;
        for (const char *q = logbuf; (q = strstr(q, "strumień z test-sink.monitor (monitor")) != NULL; q++) n_conn++;
        for (const char *q = logbuf; (q = strstr(q, "zerwany")) != NULL; q++) n_lost++;
        for (const char *q = logbuf; (q = strstr(q, "brak połączenia z monitorem wyjścia")) != NULL; q++) n_none++;
        CHECK(n_conn == 1, "bez -v: pierwsze połączenie w logu, z nazwą źródła");
        CHECK(n_lost == 1, "bez -v: zerwanie strumienia w logu");
        CHECK(fake_pa_get().tries >= 2 && n_none == 1, "bez -v: brak połączenia w logu RAZ, nie co próbę");
        CHECK(strstr(logbuf, "flux-wall: audio: ") == logbuf, "linie zaczynają się od „flux-wall: audio: ” (doctor filtruje po „audio:”)");
    }

    /* Kody wyjścia to kontrakt z flux-wall.sh (DECYZJE 2026-09-07h): 1 =
     * argumenty albo plik shadera, 2 = brak Waylanda/layer-shell, 3 = EGL/
     * shader. Bez kompozytora sprawdzalne są 1 i 2: kod 2 = argumenty
     * przyjęte, plik wczytany, dopiero brak Waylanda. Kod 3 wymaga
     * połączenia z kompozytorem (atrapa kompozytora: audyt T4) — decyzje
     * przed kodem 3 sprawdza sekcja „recovery:” niżej, a błędny shader
     * (NULL z flux_engine_create) sekcja GL na końcu. */
    printf("CLI: kody wyjścia (1 = argumenty/plik, 2 = brak Waylanda)\n");
    {
        char shader[600], missing[600], log[4096];
        snprintf(shader, sizeof shader, "%s/cli.frag", dir);
        snprintf(missing, sizeof missing, "%s/brak.frag", dir);
        write_file(shader, "#version 300 es\nvoid main(){}\n");
        struct { char *args[8]; int rc; const char *what; } cases[] = {
            { { "flux-wall", "-s", shader, NULL }, 2, "poprawny shader → kod 2 (brak Waylanda), nie 1" },
            { { "flux-wall", "-s", missing, NULL }, 1, "brak pliku shadera → kod 1 (nie 3: wrapper nie myli go z EGL)" },
            { { "flux-wall", "-s", dir, NULL }, 1, "katalog zamiast shadera → kod 1" },
            { { "flux-wall", NULL }, 1, "bez -s → kod 1" },
            { { "flux-wall", "-s", shader, "--bez-takiej-opcji", NULL }, 1, "nieznana opcja → kod 1" },
            { { "flux-wall", "-s", shader, "-p", "0F1A24,5C87A3,D8E6EE", NULL }, 2, "-p trzy hexy → przyjęte" },
            { { "flux-wall", "-s", shader, "-p", "0F1A24,5C87A3", NULL }, 1, "-p dwa hexy → kod 1" },
            { { "flux-wall", "-s", shader, "-f", "0", NULL }, 2, "-f 0 → przyjęte" },
            { { "flux-wall", "-s", shader, "-f", "1000", NULL }, 2, "-f 1000 (górna granica) → przyjęte" },
            { { "flux-wall", "-s", shader, "-f", "1001", NULL }, 1, "-f 1001 → kod 1" },
            { { "flux-wall", "-s", shader, "-f", "-1", NULL }, 1, "-f -1 → kod 1" },
            { { "flux-wall", "-s", shader, "-f", "abc", NULL }, 1, "-f abc → kod 1" },
            { { "flux-wall", "-s", shader, "-f", "60x", NULL }, 1, "-f 60x (śmieć po liczbie) → kod 1" },
            { { "flux-wall", "-s", shader, "-d", "0", NULL }, 2, "-d 0 (dolna granica) → przyjęte" },
            { { "flux-wall", "-s", shader, "-d", "1", NULL }, 2, "-d 1 (górna granica) → przyjęte" },
            { { "flux-wall", "-s", shader, "-d", "-0.01", NULL }, 1, "-d -0.01 → kod 1" },
            { { "flux-wall", "-s", shader, "-d", "abc", NULL }, 1, "-d abc → kod 1" },
            { { "flux-wall", "-s", shader, "-d", "0.5x", NULL }, 1, "-d 0.5x (śmieć po liczbie) → kod 1" },
            { { "flux-wall", "-s", shader, "-l", "bottom", NULL }, 2, "-l bottom → przyjęte" },
            { { "flux-wall", "-s", shader, "-l", "background", NULL }, 2, "-l background → przyjęte" },
            { { "flux-wall", "-s", shader, "-l", "top", NULL }, 1, "-l top → kod 1" },
        };
        for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
            int rc = run_cli(dir, cases[i].args, log, sizeof log);
            char msg[200];
            snprintf(msg, sizeof msg, "%s (kod %d)", cases[i].what, rc);
            CHECK(rc == cases[i].rc, msg);
        }
        remove(shader);
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

    /* flux_parse_args w tym procesie (bez fork): każda opcja trafia do
     * swojego pola, wartości domyślne, kolejność i komunikaty złych wartości. */
    printf("CLI: flux_parse_args (opcje → struct config)\n");
    {
        struct config cfg;
        char msg[512];
        char *a1[] = { "flux-wall", "-s", "a.frag", NULL };
        CHECK(parse_cli(a1, &cfg, msg, sizeof msg) == FLUX_ARGS_RUN && msg[0] == 0 &&
              strcmp(cfg.shader_path, "a.frag") == 0, "-s a.frag → uruchom, bez komunikatu");
        CHECK(cfg.detail == 1.0f && cfg.dither == 0.0f && cfg.fps == 0 &&
              cfg.layer == ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM && !cfg.battery && !cfg.once && !cfg.verbose &&
              !cfg.no_audio && !cfg.output_name && !cfg.audio_device && !cfg.audio_file && !cfg.ready_file,
              "domyślnie: detail 1, gładko, każda klatka, warstwa bottom (nad hyprpaperem), bez audio i -o");
        CHECK(near(cfg.palette.bg[0], 0.059f) && near(cfg.palette.ink[1], 0.529f) && near(cfg.palette.accent[2], 0.933f),
              "domyślna paleta");

        char *a2[] = { "flux-wall", "--shader=b.frag", "-p", "000000,FFFFFF,#FF0000", "-d", "0.25", "--battery",
                       "-f", "30", "-o", "DP-1", "-l", "background", "--audio-device=mon.monitor", "--no-audio",
                       "--audio-file", "x.f32", "--dither", "-1v", "--ready-file", "r.pid", NULL };
        CHECK(parse_cli(a2, &cfg, msg, sizeof msg) == FLUX_ARGS_RUN, "wszystkie opcje naraz → uruchom");
        CHECK(strcmp(cfg.shader_path, "b.frag") == 0 && near(cfg.palette.bg[0], 0.0f) && near(cfg.palette.ink[0], 1.0f) &&
              near(cfg.palette.accent[0], 1.0f) && near(cfg.palette.accent[1], 0.0f) && near(cfg.detail, 0.25f) &&
              cfg.battery && cfg.fps == 30 && strcmp(cfg.output_name, "DP-1") == 0 &&
              cfg.layer == ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND,
              "-s -p -d --battery -f -o -l → swoje pola");
        CHECK(strcmp(cfg.audio_device, "mon.monitor") == 0 && cfg.no_audio && strcmp(cfg.audio_file, "x.f32") == 0 &&
              cfg.dither == 1.0f && cfg.once && cfg.verbose && strcmp(cfg.ready_file, "r.pid") == 0,
              "--audio-device --no-audio --audio-file --dither -1v --ready-file → swoje pola");

        char *a3[] = { "flux-wall", "-s", "a.frag", "--dither", "--no-dither", NULL };
        char *a4[] = { "flux-wall", "-s", "a.frag", "--no-dither", "--dither", "-l", "bottom", "--fps=1000", NULL };
        CHECK(parse_cli(a3, &cfg, msg, sizeof msg) == FLUX_ARGS_RUN && cfg.dither == 0.0f, "--dither --no-dither → gładko (ostatnia wygrywa)");
        CHECK(parse_cli(a4, &cfg, msg, sizeof msg) == FLUX_ARGS_RUN && cfg.dither == 1.0f &&
              cfg.layer == ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM && cfg.fps == 1000, "--no-dither --dither → raster; -l bottom; -f 1000 (granica)");

        char *h1[] = { "flux-wall", "-h", "-p", "zle", NULL };
        char *h2[] = { "flux-wall", "-p", "zle", "-h", NULL };
        CHECK(parse_cli(h1, &cfg, msg, sizeof msg) == FLUX_ARGS_HELP && msg[0] == 0, "-h przed złą opcją → pomoc (kod 0)");
        CHECK(parse_cli(h2, &cfg, msg, sizeof msg) == FLUX_ARGS_BAD, "zła opcja przed -h → błąd (pierwsza zła zatrzymuje)");
        char *u1[] = { "flux-wall", "-v", NULL };
        char *u2[] = { "flux-wall", "-s", "a.frag", "--bogus", NULL };
        CHECK(parse_cli(u1, &cfg, msg, sizeof msg) == FLUX_ARGS_USAGE, "bez -s → usage (kod 1)");
        CHECK(parse_cli(u2, &cfg, msg, sizeof msg) == FLUX_ARGS_USAGE, "nieznana opcja → usage (kod 1)");

        char *b1[] = { "flux-wall", "-s", "a.frag", "-p", "zle", NULL };
        CHECK(parse_cli(b1, &cfg, msg, sizeof msg) == FLUX_ARGS_BAD &&
              strcmp(msg, "flux-wall: zła paleta: zle (oczekiwane bg,ink,acc jako hex)\n") == 0,
              "-p zle → błąd z komunikatem jak dawne die(1)");
        char *b2[] = { "flux-wall", "-s", "a.frag", "-f", "-1", NULL };
        char *b3[] = { "flux-wall", "-s", "a.frag", "-f", "30fps", NULL };
        CHECK(parse_cli(b2, &cfg, msg, sizeof msg) == FLUX_ARGS_BAD && strcmp(msg, "flux-wall: fps poza 0..1000\n") == 0,
              "-f -1 → fps poza 0..1000");
        CHECK(parse_cli(b3, &cfg, msg, sizeof msg) == FLUX_ARGS_BAD && strcmp(msg, "flux-wall: fps: '30fps' nie jest liczbą\n") == 0,
              "-f 30fps → nie jest liczbą");
        char *b4[] = { "flux-wall", "-s", "a.frag", "-l", "top", NULL };
        CHECK(parse_cli(b4, &cfg, msg, sizeof msg) == FLUX_ARGS_BAD &&
              strcmp(msg, "flux-wall: zła warstwa: top (bottom|background)\n") == 0, "-l top → zła warstwa");
        char *b5[] = { "flux-wall", "-s", "a.frag", "-d", "inf", NULL };
        char *b6[] = { "flux-wall", "-s", "a.frag", "-d", "1.5", NULL };
        CHECK(parse_cli(b5, &cfg, msg, sizeof msg) == FLUX_ARGS_BAD && strstr(msg, "detail: 'inf' nie jest liczbą"),
              "-d inf → nie jest liczbą");
        CHECK(parse_cli(b6, &cfg, msg, sizeof msg) == FLUX_ARGS_BAD && strcmp(msg, "flux-wall: detail poza 0..1\n") == 0,
              "-d 1.5 → detail poza 0..1");
    }

    /* Błąd EGL powierzchni po starcie (np. nowo podpięty monitor) sprząta
     * tylko ją i ponawia po przerwie; kod 3 wyłącznie przed pierwszą klatką
     * na ekranie — dawne die(3) gasiło animację na wszystkich monitorach
     * (audyt 2026-11-05, F4). Glue w main.c (output_surface_failed) wykonuje
     * te decyzje; sam kompozytor + EGL tylko na żywo. */
    printf("recovery: błąd EGL powierzchni (flux_egl_action, flux_retry)\n");
    {
        CHECK(flux_egl_action(FLUX_STAGE_SURFACE, EGL_BAD_ALLOC, false) == FLUX_EGL_EXIT,
              "przed pierwszą klatką: błąd powierzchni → kod 3 (kontrakt, hyprpaper zostaje)");
        CHECK(flux_egl_action(FLUX_STAGE_SURFACE, EGL_BAD_ALLOC, true) == FLUX_EGL_RETRY_SURFACE,
              "po starcie: błąd powierzchni nowego monitora → tylko ona, ponowienie (nie kod 3)");
        CHECK(flux_egl_action(FLUX_STAGE_SURFACE, EGL_SUCCESS, true) == FLUX_EGL_RETRY_SURFACE,
              "po starcie: błąd celu silnika (poza EGL) → też tylko ta powierzchnia");
        CHECK(flux_egl_action(FLUX_STAGE_FRAME, EGL_BAD_SURFACE, true) == FLUX_EGL_SKIP_FRAME,
              "po starcie: pojedyncza odmowa klatki → klatka później");
        CHECK(flux_egl_action(FLUX_STAGE_FRAME, EGL_BAD_SURFACE, false) == FLUX_EGL_SKIP_FRAME,
              "przed pierwszą klatką: odmowa klatki → też klatka później (jak dawniej)");

        struct flux_retry r = {0};
        CHECK(flux_retry_wait(&r, 100.0) <= 0, "bez błędu → wolno próbować od razu (np. po `closed`)");
        bool ok = true;
        const double want[] = { 1, 2, 4, 8, 16, 30, 30 };
        for (int i = 0; i < 7; i++) {
            double d = flux_retry_failed(&r, 100.0);
            if (!near((float)d, (float)want[i]) || !near((float)flux_retry_wait(&r, 100.0), (float)want[i])) ok = false;
        }
        CHECK(ok, "kolejne błędy: przerwa 1, 2, 4, 8, 16, 30, 30 s (sufit 30 s)");
        CHECK(flux_retry_wait(&r, 129.0) > 0 && flux_retry_wait(&r, 130.0) <= 0, "termin = chwila błędu + przerwa");
        flux_retry_reset(&r);
        CHECK(flux_retry_wait(&r, 0.0) <= 0 && near((float)flux_retry_failed(&r, 5.0), 1.0f),
              "po udanej powierzchni → następny błąd znów od 1 s");
    }

    /* EGL_CONTEXT_LOST (np. wybudzenie GPU) nie mija: pomijanie klatek
     * zamrażało tapetę na zawsze przy żywym procesie i statusie „działa”
     * (audyt 2026-11-05, F5). Po starcie nowy kontekst, przed startem kod 3;
     * utrata za utratą (więcej niż FLUX_CTX_LOST_MAX w FLUX_CTX_LOST_WINDOW s)
     * = kod 3. Glue: egl_context_lost / output_frame_failed w main.c. */
    printf("recovery: utrata kontekstu EGL (EGL_CONTEXT_LOST)\n");
    {
        CHECK(flux_egl_action(FLUX_STAGE_FRAME, EGL_CONTEXT_LOST, true) == FLUX_EGL_NEW_CONTEXT,
              "swap/makecurrent klatki: EGL_CONTEXT_LOST → nowy kontekst (nie „pomijam klatkę”)");
        CHECK(flux_egl_action(FLUX_STAGE_SURFACE, EGL_CONTEXT_LOST, true) == FLUX_EGL_NEW_CONTEXT,
              "nowa powierzchnia: EGL_CONTEXT_LOST → nowy kontekst (nie ponowienie samej powierzchni)");
        CHECK(flux_egl_action(FLUX_STAGE_FRAME, EGL_CONTEXT_LOST, false) == FLUX_EGL_EXIT &&
              flux_egl_action(FLUX_STAGE_SURFACE, EGL_CONTEXT_LOST, false) == FLUX_EGL_EXIT,
              "przed pierwszą klatką: EGL_CONTEXT_LOST → kod 3");

        struct flux_ctx_guard g = {0};
        bool first = flux_ctx_lost_recover(&g, 1000.0) && flux_ctx_lost_recover(&g, 1010.0) &&
                     flux_ctx_lost_recover(&g, 1020.0);
        CHECK(first, "trzy utraty w minucie → za każdym razem nowy kontekst");
        CHECK(!flux_ctx_lost_recover(&g, 1030.0), "czwarta w tej samej minucie → kod 3 (bez pętli migania)");
        struct flux_ctx_guard h = {0};
        bool spread = true;
        for (int i = 0; i < 10; i++) if (!flux_ctx_lost_recover(&h, 5000.0 + i * 3600.0)) spread = false;
        CHECK(spread, "utrata co godzinę (uśpienia) → zawsze nowy kontekst");
        struct flux_ctx_guard k = {0};
        flux_ctx_lost_recover(&k, 0.0); flux_ctx_lost_recover(&k, 1.0); flux_ctx_lost_recover(&k, 2.0);
        CHECK(flux_ctx_lost_recover(&k, 60.0), "okno mija 60 s po pierwszej utracie → licznik od nowa");
    }

    /* Decyzje main.c bez kompozytora (logic.h): main.c tylko je wykonuje. */
    printf("logic: rozmiar bufora ze skali monitora\n");
    {
        int32_t w = 0, h = 0;
        bool frac = flux_buffer_size(1920, 1080, 1, 150, true, &w, &h);
        CHECK(frac && w == 2400 && h == 1350, "skala 1.25 (150/120) z viewportem → bufor 2400x1350, ułamkowa");
        frac = flux_buffer_size(1536, 864, 2, 150, true, &w, &h);
        CHECK(frac && w == 1920 && h == 1080, "skala ułamkowa wygrywa ze skalą całkowitą wl_output (2)");
        flux_buffer_size(1707, 960, 1, 180, true, &w, &h);
        CHECK(w == 2561 && h == 1440, "1707 × 1.5 = 2560.5 → 2561 — zaokrąglenie do najbliższego piksela (+60/120)");
        flux_buffer_size(1001, 1, 1, 210, true, &w, &h);
        CHECK(w == 1752 && h == 2, "1001 × 1.75 = 1751.75 → 1752, 1 × 1.75 → 2 (nie obcięte w dół)");
        flux_buffer_size(1001, 1, 1, 126, true, &w, &h);
        CHECK(w == 1051 && h == 1, "1001 × 1.05 = 1051.05 → 1051, 1 × 1.05 → 1 (nie w górę)");
        frac = flux_buffer_size(1920, 1080, 2, 150, false, &w, &h);
        CHECK(!frac && w == 3840 && h == 2160, "bez viewportu skala ułamkowa nieużyta → całkowita 2");
        frac = flux_buffer_size(1920, 1080, 1, 0, true, &w, &h);
        CHECK(!frac && w == 1920 && h == 1080, "viewport, ale skala ułamkowa nieznana (0) → całkowita 1");
        CHECK(flux_output_scale(2) == 2 && flux_output_scale(0) == 1 && flux_output_scale(-3) == 1,
              "wl_output.scale niedodatnia → 1");
        CHECK(flux_bind_version(3, 4) == 3 && flux_bind_version(4, 4) == 4 && flux_bind_version(6, 4) == 4,
              "wersja globala: oferowana, najwyżej obsługiwana");
        CHECK(flux_output_selected(NULL, "DP-1") && flux_output_selected("DP-1", "DP-1") &&
              !flux_output_selected("DP-1", "HDMI-A-1") && !flux_output_selected("DP-1", "DP-10"),
              "-o: bez nazwy wszystkie monitory, z nazwą tylko ten (dokładnie)");
    }

    printf("logic: tempo klatek i timeout poll()\n");
    {
        CHECK(near((float)flux_frame_wait(30, 100.010, 100.0), (float)(1.0 / 30 - 0.010)),
              "-f 30: 10 ms po klatce czeka resztę okresu (23,3 ms), nie cały okres");
        CHECK(flux_frame_wait(30, 100.034, 100.0) <= 0, "-f 30: po 34 ms można rysować");
        CHECK(near((float)flux_frame_wait(0, 100.030, 100.0), 0.07f), "bez limitu fps: zaległa klatka po 100 ms");
        CHECK(flux_frame_wait(1000, 100.002, 100.0) < 0, "-f 1000: po 2 ms od razu");
        CHECK(flux_poll_timeout(-1, 0.0233) == 24, "jedyny monitor: reszta okresu w górę do ms (23,3 → 24)");
        CHECK(flux_poll_timeout(-1, 0.0) == 1 && flux_poll_timeout(-1, -0.5) == 1,
              "termin już minął → 1 ms, nigdy 0 ani ujemny (bez kręcenia pętli)");
        CHECK(flux_poll_timeout(24, 0.005) == 5 && flux_poll_timeout(5, 0.024) == 5,
              "kilka monitorów → najkrótsze czekanie");
        CHECK(flux_poll_timeout(-1, 30.0) == 30000, "ponowienie powierzchni za 30 s → 30000 ms");
        CHECK(!flux_battery_due(false, 1000.0, 0.0), "bez --battery nigdy nie czyta baterii");
        CHECK(!flux_battery_due(true, 129.0, 100.0) && flux_battery_due(true, 130.5, 100.0),
              "--battery: odczyt dopiero po 30 s od poprzedniego");
        float d = 0.2f;
        d = flux_detail_step(d, 1.0f);
        CHECK(near(d, 0.216f), "szczegółowość: krok to 2 % różnicy (0.2 → 0.216), bez skoku");
        for (int i = 0; i < 2000; i++) d = flux_detail_step(d, 1.0f);
        CHECK(d == 1.0f, "szczegółowość dochodzi DOKŁADNIE do celu (różnica < 0.002 → cel)");
        CHECK(flux_detail_step(1.0f, 0.4f) < 1.0f && flux_detail_step(1.0f, 0.4f) > 0.98f,
              "szczegółowość w dół też płynnie");
        CHECK(flux_connection_closed(EPIPE) && flux_connection_closed(ECONNRESET) &&
              !flux_connection_closed(EPROTO) && !flux_connection_closed(0),
              "EPIPE/ECONNRESET = kompozytor zamknął połączenie (kod 0), inny błąd = kod 2");
    }

    printf("logic: start wątku audio\n");
    {
        CHECK(flux_audio_mode(false, false, false, false) == FLUX_AUDIO_OFF,
              "animacja bez `#pragma flux audio 1` → bez nasłuchu");
        CHECK(flux_audio_mode(true, false, false, false) == FLUX_AUDIO_START, "wizualizacja muzyki → wątek audio");
        CHECK(flux_audio_mode(false, true, false, false) == FLUX_AUDIO_START, "--audio-file wymusza audio");
        CHECK(flux_audio_mode(true, false, true, false) == FLUX_AUDIO_SKIPPED &&
              flux_audio_mode(true, true, false, true) == FLUX_AUDIO_SKIPPED,
              "--once i --no-audio → nigdy wątku, także z --audio-file");
        CHECK(flux_audio_mode(false, false, true, true) == FLUX_AUDIO_OFF, "--once bez audio → OFF (bez logu „pominięte”)");
    }

    /* Linia stanu `-v` co FLUX_STATS_PERIOD s (audyt 2026-11-24, U4): klatki na
     * sekundę z liczby klatek i czasu okna, średni czas klatki, poziom w dBFS. */
    printf("logic: statystyki -v (klatki/s, ms/klatkę, dBFS)\n");
    {
        struct flux_stats fs = {0};
        double fps = -1, ms = -1;
        CHECK(!flux_stats_due(&fs, 100.0, &fps, &ms), "przed pierwszą klatką: nic do wypisania");
        flux_stats_frame(&fs, 100.0, 0.5);                   /* pierwsza klatka tylko otwiera okno */
        int due_early = 0;
        for (int i = 1; i <= 720; i++) {                     /* 144 kl/s przez 5 s, 2 ms na klatkę */
            double now = 100.0 + i / 144.0;
            flux_stats_frame(&fs, now, 0.002);
            if (i < 720 && flux_stats_due(&fs, now, &fps, &ms)) due_early++;
        }
        CHECK(due_early == 0, "przed upływem 5 s: bez linii");
        bool due = flux_stats_due(&fs, 105.0, &fps, &ms);
        CHECK(due && fabs(fps - 144.0) < 0.01 && fabs(ms - 2.0) < 0.001,
              "po 5 s: 144.0 kl/s i 2.00 ms/klatkę (klatka otwierająca okno się nie liczy)");
        CHECK(!flux_stats_due(&fs, 105.1, &fps, &ms) && fs.frames == 0, "po linii okno liczy od nowa");
        for (int i = 1; i <= 10; i++) flux_stats_frame(&fs, 105.0 + i * 0.5, 0.001);
        due = flux_stats_due(&fs, 110.0, &fps, &ms);
        CHECK(due && fabs(fps - 2.0) < 0.01, "rzadkie klatki (zasłonięta tapeta): 2.0 kl/s");
        CHECK(fabs(flux_dbfs(1.0)) < 1e-9 && fabs(flux_dbfs(0.1) + 20.0) < 1e-6 && flux_dbfs(0.0) == -120.0 &&
              flux_dbfs(NAN) == -120.0, "dBFS: 1.0 → 0, 0.1 → -20, cisza i NaN → -120");
    }

    /* --once (tapeta statyczna) liczy rozgrzewkę przed jedyną klatką. Zmiana
     * skali albo rozdzielczości odtwarza i czyści akumulator, więc kolejna
     * klatka też potrzebuje rozgrzewki — inaczej z obrazu zostawało samo tło
     * do restartu (audyt 2026-11-05, F2). */
    printf("GL: --once po zmianie rozmiaru celu (EGL surfaceless)\n");
    bool gl_ok = test_egl_init();
    if (!gl_ok) {
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

    /* Kod 3 = EGL/shader: main.c (build_engine) kończy kodem 3, gdy
     * flux_engine_create zwróci NULL, i wypisuje `err`. Sam kod 3 wymaga
     * kompozytora (atrapa kompozytora: audyt T4), tu jest połowa silnika:
     * shader, który się nie kompiluje albo nie linkuje, daje NULL, a komunikat
     * mówi, który plik i który etap zawiódł. */
    printf("GL: błędny shader → flux_engine_create = NULL i komunikat z nazwą pliku (podstawa kodu 3)\n");
    if (!gl_ok) {
        printf("  POMINIĘTO: brak EGL surfaceless / GLES 3.0 — test wymaga Mesy albo GPU\n");
    } else {
        static const char *BAD_COMPILE =
            "#version 300 es\nprecision highp float;\nout vec4 c;\nvoid main() { c = vec4(nie_ma_takiej, 1.0); }\n";
        /* kompiluje się, ale `uv` nie wychodzi z VS_QUAD → błąd linkowania */
        static const char *BAD_LINK =
            "#version 300 es\nprecision highp float;\nin vec2 uv;\nout vec4 c;\nvoid main() { c = vec4(uv, 0.0, 1.0); }\n";
        static const char *BAD_UPDATE = "void main() { o = nie_ma_takiej; }\n";
        char gerr[2560];
        gerr[0] = 0;
        struct flux_engine *b1 = flux_engine_create(BAD_COMPILE, "test-zly.frag", NULL, NULL, gerr, sizeof gerr);
        CHECK(!b1 && strstr(gerr, "kompilacja shadera (test-zly.frag)"), "błąd kompilacji .frag → NULL, komunikat: kompilacja + plik");
        gerr[0] = 0;
        struct flux_engine *b2 = flux_engine_create(BAD_LINK, "test-link.frag", NULL, NULL, gerr, sizeof gerr);
        CHECK(!b2 && strstr(gerr, "linkowanie programu (test-link.frag)"), "błąd linkowania .frag → NULL, komunikat: linkowanie + plik");
        gerr[0] = 0;
        struct flux_engine *b3 = flux_engine_create(ONCE_FRAG, "test-once.frag", BAD_UPDATE, "test-zly.update.glsl",
                                                    gerr, sizeof gerr);
        CHECK(!b3 && strstr(gerr, "kompilacja shadera (test-zly.update.glsl)"),
              "błąd kompilacji .update.glsl → NULL, komunikat z nazwą .update.glsl");
        if (b1) flux_engine_destroy(b1);
        if (b2) flux_engine_destroy(b2);
        if (b3) flux_engine_destroy(b3);
    }

    /* sprzątanie */
    const char *files[] = { "BAT0/capacity", "BAT0/status", "BAT1/capacity", "BAT1/status", "BAT0", "BAT1", NULL };
    for (int i = 0; files[i]; i++) { snprintf(path, sizeof path, "%s/%s", dir, files[i]); remove(path); }
    rmdir(dir);

    printf("%s: %d błędów\n", failures ? "WYNIK" : "WSZYSTKO OK", failures);
    return failures ? 1 : 0;
}
