/*
 * =============================================
 *   archenemy - flux-wall
 *   Tapeta liczona shaderem na warstwie tła (wlr-layer-shell + EGL + GLES 3.0).
 *
 *   Jedna powierzchnia na każdy monitor, raster liczony natywnie w pikselach
 *   fizycznych (bez skalowania — dither jednopikselowy nie znosi skalowania).
 *   Rysowaniem zajmuje się silnik z engine.c (bez Waylanda — ten sam kod
 *   działa offscreen w testach). Fragment shader dostaje uniformy:
 *     vec2  resolution       rozmiar powierzchni w pikselach
 *     float time             sekundy od startu (animacja; zawijane co FLUX_TIME_PERIOD — engine.h)
 *     vec3  palette_bg/ink/accent   paleta rice'a (0..1)
 *     float detail           szczegółowość 0..1 (z baterii albo stała)
 *   a gdy obok `<shader>.frag` leży `<shader>.update.glsl`, silnik przechodzi
 *   w tryb cząstkowy (formy akumulacyjne: pole przepływu, atraktor) i dokłada
 *   `sampler2D accum` + `gain` — kontrakt w engine.h.
 *
 *   Kody wyjścia (install.sh i przełącznik używają ich do fallbacku na hyprpaper):
 *     0 ok (także: SIGTERM/SIGINT albo kompozytor zamknął połączenie)
 *     1 błąd argumentów/pliku   2 brak Waylanda lub layer-shell
 *     3 błąd EGL/GLES (shader, kontekst)
 *
 *   Skalowanie: przy wp_fractional_scale_v1 + wp_viewporter bufor ma rozmiar
 *   logiczny × skala ułamkowa (np. 1.25) zaokrąglony do pikseli fizycznych,
 *   a viewport mapuje go na rozmiar logiczny — raster 1:1 przy KAŻDEJ skali
 *   ustawionej w install.sh. Bez tych protokołów: skala całkowita wl_output.
 *
 *   Użycie: flux-wall -s shader.frag [-p bg,ink,acc] [-d 0..1 | --battery]
 *                     [-f fps] [-o output] [-l background|bottom] [--once] [-v]
 *                     [--audio-device=monitor] [--no-audio] [--audio-file plik]
 *   Dźwięk (audio.c): tylko animacje z `#pragma flux audio 1` (wizualizacje
 *   muzyki) — pasma z monitora WYJŚCIA → uniformy audio_* i reakcje silnika.
 * =============================================
 */
#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <errno.h>
#include <getopt.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>
#include <wayland-egl.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "fractional-scale-v1-client-protocol.h"
#include "viewporter-client-protocol.h"
#include "engine.h"
#include "audio.h"
#include "util.h"       /* flux_now_seconds, flux_read_file — wspólne z audio.c i tools/offscreen.c */

/* ── konfiguracja ─────────────────────────────────────────────────────────── */

struct config {
    const char *shader_path;
    const char *output_name;     /* NULL = wszystkie monitory */
    struct palette palette;
    float detail;                /* wartość stała, gdy battery == false */
    bool  battery;               /* detail z /sys/class/power_supply */
    int   fps;                   /* 0 = każda klatka kompozytora */
    bool  once;                  /* jedna klatka po configure, bez animacji */
    bool  verbose;
    uint32_t layer;              /* ZWLR_LAYER_SHELL_V1_LAYER_* — bottom = nad hyprpaperem */
    bool  no_audio;              /* --no-audio: nie startuj wątku nawet dla wizualizacji */
    const char *audio_device;    /* --audio-device: jawna nazwa monitora (fallback po @DEFAULT_MONITOR@) */
    const char *audio_file;      /* --audio-file: surowy f32 mono 48 kHz zamiast serwera (debug; wymusza audio) */
};

/* ── stan ─────────────────────────────────────────────────────────────────── */

struct state;

struct output {
    struct state *state;
    struct wl_output *wl_output;
    uint32_t global_name;
    uint32_t version;            /* zbindowana wersja wl_output (release od v3) */
    char name[64];
    int32_t scale;
    struct wl_surface *surface;
    struct zwlr_layer_surface_v1 *layer_surface;
    struct wl_egl_window *egl_window;
    EGLSurface egl_surface;
    struct wl_callback *frame_cb;
    struct wp_viewport *viewport;
    struct wp_fractional_scale_v1 *fractional;
    uint32_t frac_scale120;      /* preferowana skala ×120; 0 = nieznana */
    int32_t logical_w, logical_h;
    int32_t width, height;       /* piksele fizyczne */
    bool configured;
    bool needs_frame;            /* klatka czeka na limit fps */
    bool recreate;               /* po `closed`: pętla ma utworzyć powierzchnię od nowa */
    double last_render;          /* do limitu fps — osobno na monitor, inaczej dwa
                                  * monitory z -f N dławiłyby się nawzajem */
    struct flux_target *target;  /* stan silnika dla tej powierzchni (akumulator, cząstki) */
    struct output *next;
};

struct state {
    struct config cfg;
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct zwlr_layer_shell_v1 *layer_shell;
    struct wp_viewporter *viewporter;
    struct wp_fractional_scale_manager_v1 *fractional_manager;
    struct output *outputs;

    EGLDisplay egl_display;
    EGLConfig  egl_config;
    EGLContext egl_context;
    struct flux_engine *engine;  /* programy GL (present + ewentualnie cząstki) */
    char  *frag_src, *update_src; /* źródła wczytane na starcie; update NULL = tryb jednoprzebiegowy */
    char   update_path[1024];

    struct audio *audio;         /* wątek analizy dźwięku (NULL = bez audio) */
    struct timespec start;
    float  detail_current;       /* interpolowana wartość uniformu */
    float  detail_target;
    double last_battery_poll;
    bool running;
};

static void logv(const struct state *s, const char *fmt, ...) {
    if (!s->cfg.verbose) return;
    va_list ap; va_start(ap, fmt);
    fputs("flux-wall: ", stderr); vfprintf(stderr, fmt, ap); fputc('\n', stderr);
    va_end(ap);
}

static void die(int code, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    fputs("flux-wall: ", stderr); vfprintf(stderr, fmt, ap); fputc('\n', stderr);
    va_end(ap);
    exit(code);
}

/* ── paleta i bateria (bez Waylanda — testowalne osobno) ──────────────────── */

/* "0F1A24" albo "#0F1A24" → rgb 0..1; false przy śmieciach. */
bool parse_hex_color(const char *hex, float out[3]) {
    if (!hex) return false;
    if (*hex == '#') hex++;
    if (strlen(hex) != 6) return false;
    /* dokładnie 6 cyfr hex — strtol łykało spacje i znak („ F", „-1") */
    for (int i = 0; i < 6; i++)
        if (!isxdigit((unsigned char)hex[i])) return false;
    for (int i = 0; i < 3; i++) {
        char buf[3] = { hex[2 * i], hex[2 * i + 1], 0 };
        out[i] = (float)strtol(buf, NULL, 16) / 255.0f;
    }
    return true;
}

/* "bg,ink,accent" — trzy hexy rozdzielone przecinkami. */
bool parse_palette(const char *spec, struct palette *p) {
    if (!spec) return false;
    char buf[64];
    if (strlen(spec) >= sizeof buf) return false;
    strcpy(buf, spec);
    char *save = NULL;
    const char *a = strtok_r(buf, ",", &save);
    const char *b = strtok_r(NULL, ",", &save);
    const char *c = strtok_r(NULL, ",", &save);
    if (!a || !b || !c || strtok_r(NULL, ",", &save)) return false;
    return parse_hex_color(a, p->bg) && parse_hex_color(b, p->ink) && parse_hex_color(c, p->accent);
}

/* Poziom baterii 0..1 z sysfs; na zasilaniu sieciowym (status Charging/Full)
 * lub bez baterii → 1.0 (pełna szczegółowość). Ścieżka bazowa jako parametr,
 * żeby dało się testować na atrapie katalogu. */
float battery_detail(const char *power_supply_dir) {
    char path[512];
    for (int i = 0; i < 4; i++) {
        snprintf(path, sizeof path, "%s/BAT%d/capacity", power_supply_dir, i);
        FILE *f = fopen(path, "r");
        if (!f) continue;
        int cap = -1;
        if (fscanf(f, "%d", &cap) != 1) cap = -1;
        fclose(f);
        if (cap < 0) continue;

        snprintf(path, sizeof path, "%s/BAT%d/status", power_supply_dir, i);
        char status[32] = "";
        f = fopen(path, "r");
        if (f) { if (!fgets(status, sizeof status, f)) status[0] = 0; fclose(f); }
        if (strncmp(status, "Charging", 8) == 0 || strncmp(status, "Full", 4) == 0)
            return 1.0f;
        if (cap > 100) cap = 100;
        return (float)cap / 100.0f;
    }
    return 1.0f;
}

/* ── GLES ─────────────────────────────────────────────────────────────────── */

/* Programy GL budujemy przy PIERWSZEJ powierzchni (kompilacja wymaga bieżącego
 * kontekstu). Źródła są już wczytane — błąd pliku wyszedł na starcie kodem 1. */
static void build_engine(struct state *s) {
    char err[2560];
    s->engine = flux_engine_create(s->frag_src, s->cfg.shader_path,
                                   s->update_src, s->update_src ? s->update_path : NULL,
                                   err, sizeof err);
    if (!s->engine) die(3, "%s", err);
    if (flux_engine_is_particle(s->engine)) {
        const struct flux_params *p = flux_engine_params(s->engine);
        logv(s, "silnik cząstkowy: %d cząstek, życie %.1f s, %g kroków/s, splat %s, warm %d",
             p->particles, p->life, p->rate, p->splat ? "plane" : "screen", p->warm);
    } else {
        logv(s, "silnik jednoprzebiegowy (brak %s)", s->update_path);
    }
}

/* ── EGL ──────────────────────────────────────────────────────────────────── */

static void egl_init(struct state *s) {
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    if (get_platform_display)
        s->egl_display = get_platform_display(EGL_PLATFORM_WAYLAND_EXT, s->display, NULL);
    else
        s->egl_display = eglGetDisplay((EGLNativeDisplayType)s->display);
    if (s->egl_display == EGL_NO_DISPLAY) die(3, "eglGetDisplay nie powiodło się");

    EGLint major, minor;
    if (!eglInitialize(s->egl_display, &major, &minor)) die(3, "eglInitialize nie powiodło się");
    logv(s, "EGL %d.%d", major, minor);

    if (!eglBindAPI(EGL_OPENGL_ES_API)) die(3, "eglBindAPI(GLES) nie powiodło się");

    const EGLint config_attribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE,
    };
    EGLint n = 0;
    if (!eglChooseConfig(s->egl_display, config_attribs, &s->egl_config, 1, &n) || n < 1)
        die(3, "brak konfiguracji EGL dla GLES 3 / RGBA8");

    const EGLint ctx_attribs[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE };
    s->egl_context = eglCreateContext(s->egl_display, s->egl_config, EGL_NO_CONTEXT, ctx_attribs);
    if (s->egl_context == EGL_NO_CONTEXT) die(3, "eglCreateContext (ES 3.0) nie powiodło się");
}

/* ── render ───────────────────────────────────────────────────────────────── */

static void output_request_frame(struct output *o);
static void output_teardown_surface(struct output *o);

static void render_output(struct output *o) {
    struct state *s = o->state;
    if (!o->configured || !o->egl_surface || !o->target) return;

    /* Pojedyncza odmowa EGL (np. sterownik w trakcie wybudzania) nie kończy
     * procesu: klatkę pomijamy, `needs_frame` każe pętli spróbować ponownie
     * (frame callback bez commitu by nie przyszedł). */
    if (!eglMakeCurrent(s->egl_display, o->egl_surface, o->egl_surface, s->egl_context)) {
        logv(s, "%s: eglMakeCurrent nie powiodło się (0x%x) — pomijam klatkę", o->name, eglGetError());
        o->needs_frame = true;
        return;
    }
    double t = flux_now_seconds() - (s->start.tv_sec + s->start.tv_nsec / 1e9);
    /* Snapshot audio raz na klatkę; stęchły (sink śpi → read blokuje) gaśnie tu. */
    struct audio_features feat;
    const struct audio_features *audio = NULL;
    if (s->audio) {
        audio_snapshot(s->audio, &feat);
        audio_features_age(&feat, flux_now_seconds(), 0.25f);
        audio = &feat;
    }
    flux_engine_render(s->engine, o->target, 0, t, &s->cfg.palette, s->detail_current,
                       audio, 1.0f, s->cfg.once);

    if (!s->cfg.once) output_request_frame(o);   /* callback ZANIM commit (swap) */
    if (!eglSwapBuffers(s->egl_display, o->egl_surface)) {
        logv(s, "%s: eglSwapBuffers nie powiodło się (0x%x) — pomijam klatkę", o->name, eglGetError());
        o->needs_frame = true;               /* bez commitu callback nie przyjdzie — pętla ponowi */
    }
    o->last_render = flux_now_seconds();
}

/* Ile sekund brakuje TEMU monitorowi do następnej klatki z `needs_frame`
 * (<= 0 = można rysować): przy limicie -f reszta okresu, bez limitu
 * (klatka zaległa tylko po nieudanym EGL) ponowienie po 100 ms. */
static double frame_wait(const struct output *o, double now) {
    const struct state *s = o->state;
    double min_dt = s->cfg.fps > 0 ? 1.0 / s->cfg.fps : 0.1;
    return min_dt - (now - o->last_render);
}

static void frame_done(void *data, struct wl_callback *cb, uint32_t time_ms) {
    (void)time_ms;
    struct output *o = data;
    wl_callback_destroy(cb);
    o->frame_cb = NULL;

    if (o->state->cfg.fps > 0 && frame_wait(o, flux_now_seconds()) > 0) { o->needs_frame = true; return; }
    render_output(o);
}

static const struct wl_callback_listener frame_listener = { .done = frame_done };

static void output_request_frame(struct output *o) {
    if (o->frame_cb) return;
    o->frame_cb = wl_surface_frame(o->surface);
    wl_callback_add_listener(o->frame_cb, &frame_listener, o);
}

/* ── layer surface ────────────────────────────────────────────────────────── */

/* Rozmiar bufora z rozmiaru logicznego i skali. Wołane z `configure`
 * (rozmiar) i z `preferred_scale` (skala) — obie mogą przyjść w dowolnej
 * kolejności, więc liczymy dopiero, gdy znamy oba. */
static void output_apply_size(struct output *o) {
    struct state *s = o->state;
    if (o->logical_w <= 0 || o->logical_h <= 0) return;

    int32_t pw, ph;
    if (o->viewport && o->frac_scale120) {
        /* skala ułamkowa: bufor w pikselach fizycznych, viewport → rozmiar logiczny */
        pw = (int32_t)((o->logical_w * o->frac_scale120 + 60) / 120);
        ph = (int32_t)((o->logical_h * o->frac_scale120 + 60) / 120);
        wp_viewport_set_destination(o->viewport, o->logical_w, o->logical_h);
        wl_surface_set_buffer_scale(o->surface, 1);
    } else {
        pw = o->logical_w * o->scale;
        ph = o->logical_h * o->scale;
        wl_surface_set_buffer_scale(o->surface, o->scale);
    }
    if (pw <= 0 || ph <= 0) return;
    bool changed = (pw != o->width || ph != o->height);
    o->width = pw; o->height = ph;
    logv(s, "%s: %dx%d logicznie, skala %s%.3f → bufor %dx%d px", o->name, o->logical_w, o->logical_h,
         (o->viewport && o->frac_scale120) ? "ułamkowa " : "całkowita ",
         (o->viewport && o->frac_scale120) ? o->frac_scale120 / 120.0 : (double)o->scale, pw, ph);

    if (!o->egl_window) {
        o->egl_window = wl_egl_window_create(o->surface, pw, ph);
        o->egl_surface = eglCreateWindowSurface(s->egl_display, s->egl_config,
                                                (EGLNativeWindowType)o->egl_window, NULL);
        if (o->egl_surface == EGL_NO_SURFACE) die(3, "%s: eglCreateWindowSurface", o->name);
        if (!eglMakeCurrent(s->egl_display, o->egl_surface, o->egl_surface, s->egl_context))
            die(3, "%s: eglMakeCurrent nie powiodło się (0x%x)", o->name, eglGetError());
        /* Własne frame callbacks sterują tempem — swap nie może blokować. */
        eglSwapInterval(s->egl_display, 0);
        /* Program budujemy przy PIERWSZEJ powierzchni, nie na starcie: kompilacja
         * shadera wymaga bieżącego kontekstu, a kontekst bez powierzchni
         * (surfaceless) to rozszerzenie, którego nie chcemy wymagać od sterownika
         * — właściciel ma NVIDIĘ, a fallback ma być pewny, nie prawdopodobny. */
        if (!s->engine) build_engine(s);
    } else if (changed) {
        wl_egl_window_resize(o->egl_window, pw, ph, 0, 0);
    }
    if (!eglMakeCurrent(s->egl_display, o->egl_surface, o->egl_surface, s->egl_context)) {
        /* na starcie (jeszcze bez silnika) bez kontekstu nie ma tapety — kod 3;
         * później pojedyncza odmowa = pomijamy ten configure, przyjdzie następny */
        if (!s->engine) die(3, "%s: eglMakeCurrent nie powiodło się (0x%x)", o->name, eglGetError());
        logv(s, "%s: eglMakeCurrent nie powiodło się (0x%x) — pomijam configure", o->name, eglGetError());
        return;
    }
    char err[256];
    if (!o->target) {
        o->target = flux_target_create(s->engine, pw, ph, err, sizeof err);
        if (!o->target) die(3, "%s: %s", o->name, err);
    } else if (changed && !flux_target_resize(o->target, pw, ph, err, sizeof err)) {
        logv(s, "%s: zmiana rozmiaru akumulatora nie powiodła się (%s) — rysuję w starym rozmiarze", o->name, err);
    }
    o->configured = true;
    render_output(o);
}

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *ls,
                            uint32_t serial, uint32_t w, uint32_t h) {
    struct output *o = data;
    zwlr_layer_surface_v1_ack_configure(ls, serial);
    if (w == 0 || h == 0) return;
    o->logical_w = (int32_t)w; o->logical_h = (int32_t)h;
    output_apply_size(o);
}

static void fractional_preferred(void *data, struct wp_fractional_scale_v1 *fs, uint32_t scale120) {
    (void)fs;
    struct output *o = data;
    if (scale120 == 0 || scale120 == o->frac_scale120) return;
    o->frac_scale120 = scale120;
    logv(o->state, "%s: preferowana skala %u/120 = %.3f", o->name, scale120, scale120 / 120.0);
    output_apply_size(o);
}

static const struct wp_fractional_scale_v1_listener fractional_listener = {
    .preferred_scale = fractional_preferred,
};

/* Po `closed` powierzchni nie wolno już używać (protokół wlr-layer-shell):
 * zwalniamy ją całą i prosimy pętlę o nową — dopiero PO tej turze
 * zdarzeń, bo gdy zaraz za `closed` przychodzi global_remove tego
 * monitora, nie ma na czym jej tworzyć (i nie kręcimy się w pętli
 * closed → create → closed). Bez odtworzenia tapeta zostawałaby czarna. */
static void layer_closed(void *data, struct zwlr_layer_surface_v1 *ls) {
    (void)ls;
    struct output *o = data;
    logv(o->state, "%s: layer surface zamknięta przez kompozytor — odtwarzam", o->name);
    output_teardown_surface(o);
    o->recreate = true;
}

static const struct zwlr_layer_surface_v1_listener layer_listener = {
    .configure = layer_configure,
    .closed    = layer_closed,
};

static void output_create_surface(struct output *o) {
    struct state *s = o->state;
    if (o->surface) return;
    if (s->cfg.output_name && strcmp(s->cfg.output_name, o->name) != 0) {
        logv(s, "%s: pomijam (wybrano %s)", o->name, s->cfg.output_name);
        return;
    }
    o->surface = wl_compositor_create_surface(s->compositor);
    /* Skala ułamkowa: bez obu obiektów zostajemy przy skali całkowitej wl_output. */
    if (s->fractional_manager && s->viewporter) {
        o->fractional = wp_fractional_scale_manager_v1_get_fractional_scale(s->fractional_manager, o->surface);
        wp_fractional_scale_v1_add_listener(o->fractional, &fractional_listener, o);
        o->viewport = wp_viewporter_get_viewport(s->viewporter, o->surface);
    }
    o->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
        s->layer_shell, o->surface, o->wl_output, s->cfg.layer, "flux-wall");
    zwlr_layer_surface_v1_add_listener(o->layer_surface, &layer_listener, o);
    zwlr_layer_surface_v1_set_anchor(o->layer_surface,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(o->layer_surface, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(o->layer_surface,
        ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
    zwlr_layer_surface_v1_set_size(o->layer_surface, 0, 0);   /* rozmiar poda kompozytor */
    wl_surface_commit(o->surface);
    logv(s, "%s: layer surface utworzona", o->name);
}

/* Zwolnienie powierzchni monitora (layer surface, EGL, cel silnika) z
 * zachowaniem samego wl_output — po `closed` od kompozytora powierzchnię
 * tworzymy od nowa, po odpięciu monitora zwalniamy wszystko. */
static void output_teardown_surface(struct output *o) {
    struct state *s = o->state;
    if (o->frame_cb) wl_callback_destroy(o->frame_cb);
    o->frame_cb = NULL;
    if (o->target && o->egl_surface) {
        /* obiekty GL zwalniamy przy bieżącym kontekście — inaczej wyciekną
         * (bez kontekstu wywołania GL są pustymi operacjami; strukturę i tak
         * zwalniamy, żeby nie wisiał wskaźnik) */
        if (!eglMakeCurrent(s->egl_display, o->egl_surface, o->egl_surface, s->egl_context))
            logv(s, "%s: eglMakeCurrent przy sprzątaniu nie powiodło się (0x%x) — obiekty GL celu mogą wyciec", o->name, eglGetError());
        flux_target_destroy(o->target);
        o->target = NULL;
    }
    if (o->egl_surface) {
        eglMakeCurrent(s->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroySurface(s->egl_display, o->egl_surface);
        o->egl_surface = EGL_NO_SURFACE;
    }
    if (o->egl_window) wl_egl_window_destroy(o->egl_window);
    o->egl_window = NULL;
    if (o->fractional) wp_fractional_scale_v1_destroy(o->fractional);
    o->fractional = NULL;
    if (o->viewport) wp_viewport_destroy(o->viewport);
    o->viewport = NULL;
    if (o->layer_surface) zwlr_layer_surface_v1_destroy(o->layer_surface);
    o->layer_surface = NULL;
    if (o->surface) wl_surface_destroy(o->surface);
    o->surface = NULL;
    o->configured = false;
    o->needs_frame = false;
    o->logical_w = o->logical_h = 0;
    o->width = o->height = 0;
    o->frac_scale120 = 0;
}

static void output_destroy(struct output *o) {
    output_teardown_surface(o);
    if (o->wl_output) {
        /* `release` (v3+) mówi kompozytorowi, że obiekt jest zwolniony;
         * starsze wersje mają tylko lokalne destroy. */
        if (o->version >= WL_OUTPUT_RELEASE_SINCE_VERSION) wl_output_release(o->wl_output);
        else wl_output_destroy(o->wl_output);
    }
    free(o);
}

/* ── wl_output ────────────────────────────────────────────────────────────── */

static void out_geometry(void *d, struct wl_output *w, int32_t x, int32_t y, int32_t pw, int32_t ph,
                         int32_t sub, const char *make, const char *model, int32_t tr) {
    (void)d; (void)w; (void)x; (void)y; (void)pw; (void)ph; (void)sub; (void)make; (void)model; (void)tr;
}
static void out_mode(void *d, struct wl_output *w, uint32_t f, int32_t mw, int32_t mh, int32_t r) {
    (void)d; (void)w; (void)f; (void)mw; (void)mh; (void)r;
}
static void out_done(void *data, struct wl_output *w) {
    (void)w;
    struct output *o = data;
    /* Po `done` znamy skalę i nazwę — dopiero teraz sens ma tworzyć powierzchnię. */
    if (o->state->layer_shell && o->state->compositor) output_create_surface(o);
}
static void out_scale(void *data, struct wl_output *w, int32_t factor) {
    (void)w;
    struct output *o = data;
    o->scale = factor > 0 ? factor : 1;
}
static void out_name(void *data, struct wl_output *w, const char *name) {
    (void)w;
    struct output *o = data;
    snprintf(o->name, sizeof o->name, "%s", name);
}
static void out_description(void *d, struct wl_output *w, const char *desc) { (void)d; (void)w; (void)desc; }

static const struct wl_output_listener output_listener = {
    .geometry = out_geometry, .mode = out_mode, .done = out_done,
    .scale = out_scale, .name = out_name, .description = out_description,
};

/* ── registry ─────────────────────────────────────────────────────────────── */

static void reg_global(void *data, struct wl_registry *reg, uint32_t name,
                       const char *iface, uint32_t version) {
    struct state *s = data;
    if (strcmp(iface, wl_compositor_interface.name) == 0) {
        s->compositor = wl_registry_bind(reg, name, &wl_compositor_interface, version < 4 ? version : 4);
    } else if (strcmp(iface, zwlr_layer_shell_v1_interface.name) == 0) {
        s->layer_shell = wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, version < 4 ? version : 4);
    } else if (strcmp(iface, wp_viewporter_interface.name) == 0) {
        s->viewporter = wl_registry_bind(reg, name, &wp_viewporter_interface, 1);
    } else if (strcmp(iface, wp_fractional_scale_manager_v1_interface.name) == 0) {
        s->fractional_manager = wl_registry_bind(reg, name, &wp_fractional_scale_manager_v1_interface, 1);
    } else if (strcmp(iface, wl_output_interface.name) == 0) {
        struct output *o = calloc(1, sizeof *o);
        if (!o) die(2, "brak pamięci na stan monitora (wl_output %u)", name);
        o->state = s;
        o->global_name = name;
        o->scale = 1;
        snprintf(o->name, sizeof o->name, "output-%u", name);
        /* v4 daje zdarzenie `name` (potrzebne do -o); starsze wersje — sama skala. */
        o->version = version < 4 ? version : 4;
        o->wl_output = wl_registry_bind(reg, name, &wl_output_interface, o->version);
        wl_output_add_listener(o->wl_output, &output_listener, o);
        o->next = s->outputs;
        s->outputs = o;
    }
}

static void reg_global_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)reg;
    struct state *s = data;
    struct output **pp = &s->outputs;
    while (*pp) {
        if ((*pp)->global_name == name) {
            struct output *o = *pp;
            *pp = o->next;
            logv(s, "%s: monitor odpięty", o->name);
            output_destroy(o);
            return;
        }
        pp = &(*pp)->next;
    }
}

static const struct wl_registry_listener registry_listener = {
    .global = reg_global, .global_remove = reg_global_remove,
};

/* ── pętla ────────────────────────────────────────────────────────────────── */

/* SIGTERM/SIGINT (kill przy zmianie rice'a, wylogowanie): handler tylko
 * zapisuje numer sygnału, poll() wraca z EINTR i pętla kończy się czysto
 * kodem 0 — bez SA_RESTART, żeby poll faktycznie wrócił. */
static volatile sig_atomic_t stop_requested;
static void on_stop_signal(int sig) { stop_requested = sig; }

/* Normalne zamknięcie połączenia przez kompozytor (wylogowanie, restart
 * kompozytora) — to nie jest błąd, kończymy kodem 0. */
static bool connection_closed(int err) { return err == EPIPE || err == ECONNRESET; }

static void update_detail(struct state *s) {
    double t = flux_now_seconds();
    if (s->cfg.battery && t - s->last_battery_poll > 30.0) {
        s->detail_target = battery_detail("/sys/class/power_supply");
        s->last_battery_poll = t;
        logv(s, "bateria → detail cel %.2f", s->detail_target);
    }
    /* Płynne dojście do celu — skok szczegółowości byłby widoczny. */
    float d = s->detail_target - s->detail_current;
    if (d > 0.002f || d < -0.002f) s->detail_current += d * 0.02f;
    else s->detail_current = s->detail_target;
}

static void main_loop(struct state *s) {
    struct pollfd pfd = { .fd = wl_display_get_fd(s->display), .events = POLLIN };
    while (s->running) {
        while (wl_display_prepare_read(s->display) != 0)
            wl_display_dispatch_pending(s->display);
        wl_display_flush(s->display);

        /* Limit fps: czekamy tylko RESZTĘ okresu (najkrótszą spośród monitorów
         * z zaległą klatką), zaokrągloną w górę do ms, nie mniej niż 1 ms.
         * Pełny okres 1000/fps dawał przy -f 30 na 60 Hz ~20 fps. */
        int timeout = -1;
        {
            double now = flux_now_seconds();
            for (struct output *o = s->outputs; o; o = o->next) {
                if (!o->needs_frame) continue;
                int ms = (int)ceil(frame_wait(o, now) * 1000.0);
                if (ms < 1) ms = 1;
                if (timeout < 0 || ms < timeout) timeout = ms;
            }
        }
        int r = poll(&pfd, 1, timeout);
        if (r < 0 && errno != EINTR) { wl_display_cancel_read(s->display); die(2, "poll: %s", strerror(errno)); }
        if (stop_requested) {                       /* SIGTERM/SIGINT: poll wraca z EINTR */
            wl_display_cancel_read(s->display);
            logv(s, "sygnał %d — kończę", (int)stop_requested);
            s->running = false;
            break;
        }
        if (r > 0 && (pfd.revents & POLLIN)) {
            if (wl_display_read_events(s->display) < 0) {
                if (connection_closed(errno)) { logv(s, "kompozytor zamknął połączenie — kończę"); s->running = false; break; }
                die(2, "połączenie z kompozytorem zerwane: %s", strerror(errno));
            }
        } else {
            wl_display_cancel_read(s->display);
            if (r > 0 && (pfd.revents & (POLLHUP | POLLERR))) {
                logv(s, "kompozytor zamknął połączenie — kończę");
                s->running = false;
                break;
            }
        }
        if (wl_display_dispatch_pending(s->display) < 0) {
            if (connection_closed(errno)) { logv(s, "kompozytor zamknął połączenie — kończę"); s->running = false; break; }
            die(2, "dispatch: %s", strerror(errno));
        }

        /* Powierzchnie zamknięte przez kompozytor (`closed`) — monitor wciąż
         * istnieje (global_remove zdjąłby go z listy), więc tworzymy nową. */
        for (struct output *o = s->outputs; o; o = o->next)
            if (o->recreate) { o->recreate = false; output_create_surface(o); }

        update_detail(s);
        {
            double now = flux_now_seconds();
            for (struct output *o = s->outputs; o; o = o->next)
                if (o->needs_frame && frame_wait(o, now) <= 0) {
                    o->needs_frame = false;
                    render_output(o);
                }
        }
        int err = wl_display_get_error(s->display);
        if (err) {
            if (connection_closed(err)) { logv(s, "kompozytor zamknął połączenie — kończę"); s->running = false; break; }
            die(2, "błąd protokołu Waylanda: %s", strerror(err));
        }
    }
}

/* Sprzątanie przy czystym wyjściu (sygnał, kompozytor zamknął połączenie):
 * audio, programy GL (przy bieżącym kontekście którejś powierzchni — bez
 * niej nie da się ich zwolnić, ale proces i tak kończy się za chwilę),
 * powierzchnie z celami, EGL, obiekty globalne i połączenie. Po zerwanym
 * połączeniu żądania Waylanda idą w pustkę — to nieszkodliwe. */
static void state_cleanup(struct state *s) {
    audio_stop(s->audio);
    s->audio = NULL;
    if (s->engine) {
        for (struct output *o = s->outputs; o; o = o->next)
            if (o->egl_surface && eglMakeCurrent(s->egl_display, o->egl_surface, o->egl_surface, s->egl_context)) {
                flux_engine_destroy(s->engine);
                break;
            }
        s->engine = NULL;
    }
    while (s->outputs) {
        struct output *o = s->outputs;
        s->outputs = o->next;
        output_destroy(o);
    }
    if (s->egl_display != EGL_NO_DISPLAY) {
        eglMakeCurrent(s->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (s->egl_context != EGL_NO_CONTEXT) eglDestroyContext(s->egl_display, s->egl_context);
        eglTerminate(s->egl_display);
    }
    if (s->fractional_manager) wp_fractional_scale_manager_v1_destroy(s->fractional_manager);
    if (s->viewporter) wp_viewporter_destroy(s->viewporter);
    if (s->layer_shell) zwlr_layer_shell_v1_destroy(s->layer_shell);
    if (s->compositor) wl_compositor_destroy(s->compositor);
    if (s->registry) wl_registry_destroy(s->registry);
    wl_display_disconnect(s->display);
    free(s->frag_src);
    free(s->update_src);
}

/* ── main ─────────────────────────────────────────────────────────────────── */

static void usage(void) {
    fputs("Użycie: flux-wall -s shader.frag [-p bg,ink,acc] [-d 0..1 | --battery]\n"
          "                  [-f fps] [-o output] [-l background|bottom] [--once] [-v]\n"
          "                  [--audio-device=monitor] [--no-audio] [--audio-file plik.f32]\n"
          "  -l  warstwa: bottom (domyślnie — nad tapetą hyprpapera, pod oknami)\n"
          "      albo background (na równi z hyprpaperem)\n"
          "  Plik <shader>.update.glsl obok .frag włącza silnik cząstkowy (engine.h).\n"
          "  Dźwięk startuje SAM, gdy shader deklaruje `#pragma flux audio 1` (wizualizacja\n"
          "  muzyki): monitor WYJŚCIA (nigdy mikrofon) — najpierw @DEFAULT_MONITOR@, potem\n"
          "  --audio-device (np. z pactl get-default-sink + .monitor).\n", stderr);
}

int main(int argc, char **argv) {
    struct state s = {0};
    s.cfg.detail = 1.0f;
    /* bottom: zawsze NAD hyprpaperem (warstwa background) i POD oknami —
     * hyprpaper zostaje pod spodem jako fallback, gdyby flux-wall padł. */
    s.cfg.layer = ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM;
    s.cfg.palette = (struct palette){ {0.059f, 0.102f, 0.141f}, {0.361f, 0.529f, 0.639f}, {0.847f, 0.902f, 0.933f} };

    static const struct option longopts[] = {
        {"shader", required_argument, 0, 's'}, {"palette", required_argument, 0, 'p'},
        {"detail", required_argument, 0, 'd'}, {"battery", no_argument, 0, 'B'},
        {"fps", required_argument, 0, 'f'},    {"output", required_argument, 0, 'o'},
        {"layer", required_argument, 0, 'l'},
        {"audio-device", required_argument, 0, 'A'}, {"no-audio", no_argument, 0, 'N'},
        {"audio-file", required_argument, 0, 'F'},
        {"once", no_argument, 0, '1'},          {"verbose", no_argument, 0, 'v'},
        {"help", no_argument, 0, 'h'},          {0, 0, 0, 0},
    };
    int c;
    while ((c = getopt_long(argc, argv, "s:p:d:f:o:l:1vh", longopts, NULL)) != -1) {
        switch (c) {
        case 's': s.cfg.shader_path = optarg; break;
        case 'p': if (!parse_palette(optarg, &s.cfg.palette)) die(1, "zła paleta: %s (oczekiwane bg,ink,acc jako hex)", optarg); break;
        case 'd': {
            char *end;
            s.cfg.detail = strtof(optarg, &end);
            if (end == optarg || *end) die(1, "detail: '%s' nie jest liczbą", optarg);
            if (s.cfg.detail < 0 || s.cfg.detail > 1) die(1, "detail poza 0..1");
            break;
        }
        case 'B': s.cfg.battery = true; break;
        case 'f': {
            char *end;
            long v = strtol(optarg, &end, 10);
            if (end == optarg || *end) die(1, "fps: '%s' nie jest liczbą", optarg);
            if (v < 0 || v > 1000) die(1, "fps poza 0..1000");
            s.cfg.fps = (int)v;
            break;
        }
        case 'o': s.cfg.output_name = optarg; break;
        case 'l':
            if (strcmp(optarg, "bottom") == 0) s.cfg.layer = ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM;
            else if (strcmp(optarg, "background") == 0) s.cfg.layer = ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND;
            else die(1, "zła warstwa: %s (bottom|background)", optarg);
            break;
        case 'A': s.cfg.audio_device = optarg; break;
        case 'N': s.cfg.no_audio = true; break;
        case 'F': s.cfg.audio_file = optarg; break;
        case '1': s.cfg.once = true; break;
        case 'v': s.cfg.verbose = true; break;
        case 'h': usage(); return 0;
        default: usage(); return 1;
        }
    }
    if (!s.cfg.shader_path) { usage(); return 1; }

    s.detail_target = s.cfg.battery ? battery_detail("/sys/class/power_supply") : s.cfg.detail;
    s.detail_current = s.detail_target;
    s.last_battery_poll = flux_now_seconds();

    /* Źródła wczytujemy od razu, PRZED Waylandem (błąd pliku = kod 1 zanim
     * cokolwiek wstanie), kompilujemy dopiero przy pierwszej powierzchni —
     * patrz output_apply_size. Plik `<nazwa>.update.glsl` obok `.frag`
     * włącza tryb cząstkowy. */
    s.frag_src = flux_read_file(s.cfg.shader_path);
    if (!s.frag_src) die(1, "nie mogę odczytać shadera: %s (%s)", s.cfg.shader_path, strerror(errno));
    if (flux_update_path(s.cfg.shader_path, s.update_path, sizeof s.update_path))
        s.update_src = flux_read_file(s.update_path);      /* NULL = brak pliku = tryb jednoprzebiegowy */
    else
        snprintf(s.update_path, sizeof s.update_path, "(shader bez rozszerzenia .frag)");

    s.display = wl_display_connect(NULL);
    if (!s.display) die(2, "brak połączenia z Waylandem (WAYLAND_DISPLAY?)");
    s.registry = wl_display_get_registry(s.display);
    wl_registry_add_listener(s.registry, &registry_listener, &s);
    wl_display_roundtrip(s.display);              /* globale */
    if (!s.compositor) die(2, "kompozytor nie wystawia wl_compositor");
    if (!s.layer_shell) die(2, "kompozytor nie wspiera wlr-layer-shell");
    logv(&s, "skala ułamkowa: %s", (s.fractional_manager && s.viewporter) ? "dostępna" : "brak (skala całkowita)");

    egl_init(&s);

    /* Audio: TYLKO gdy shader deklaruje `#pragma flux audio 1` (wizualizacja
     * muzyki) albo podano --audio-file; nigdy przy --once i --no-audio; nigdy
     * nie jest błędem krytycznym — brak serwera = praca bez reakcji. Pragmy
     * czytamy tu z tekstu (silnik zbuduje się dopiero przy pierwszej
     * powierzchni), błędy pragm zgłosi wtedy silnik. */
    {
        struct flux_params pp = FLUX_PARAMS_DEFAULT;
        char perr[256];
        flux_params_parse(s.frag_src, &pp, perr, sizeof perr);
        if (s.update_src) flux_params_parse(s.update_src, &pp, perr, sizeof perr);
        bool wants = pp.audio || s.cfg.audio_file;
        if (wants && !s.cfg.once && !s.cfg.no_audio) {
            s.audio = audio_start(s.cfg.audio_device, s.cfg.audio_file, s.cfg.verbose);
            if (!s.audio) logv(&s, "audio: nie udało się uruchomić wątku — bez reakcji na dźwięk");
            else logv(&s, "audio: wizualizacja muzyki, źródło %s", s.cfg.audio_file ? s.cfg.audio_file
                      : (s.cfg.audio_device ? s.cfg.audio_device : "@DEFAULT_MONITOR@"));
        } else if (wants) {
            logv(&s, "audio: pominięte (%s)", s.cfg.once ? "--once" : "--no-audio");
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &s.start);
    s.running = true;
    {
        struct sigaction sa = { .sa_handler = on_stop_signal };
        sigemptyset(&sa.sa_mask);          /* bez SA_RESTART — poll ma wrócić z EINTR */
        sigaction(SIGTERM, &sa, NULL);
        sigaction(SIGINT, &sa, NULL);
    }
    /* Monitory znane po pierwszym roundtripie dostały listenery; drugi roundtrip
     * dowozi ich zdarzenia (scale/name/done) — i w `done` powstają powierzchnie. */
    wl_display_roundtrip(s.display);
    for (struct output *o = s.outputs; o; o = o->next) output_create_surface(o);

    main_loop(&s);
    state_cleanup(&s);
    return 0;
}
