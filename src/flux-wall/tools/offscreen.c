/*
 * archenemy - flux-wall/tools/offscreen.c — „aparat do animacji".
 *
 * Renderuje klatki dowolnej animacji flux-wall do PNG BEZ ekranu i BEZ
 * Waylanda: EGL surfaceless (Mesa/llvmpipe w kontenerze, na laptopie też
 * zadziała na GPU), ten sam engine.c co na żywo (linkowany, nie kopiowany),
 * dźwięk z wbudowanego syntezatora „muzyki" albo z pliku f32 stereo.
 *
 * Narzędzie deweloperskie: budowane WYŁĄCZNIE ręcznie (`make tools`), nigdy
 * przez install.sh; nie dotyka ścieżki renderowania na żywo (zasada
 * właściciela 2026-09-08: nic, co pogorszyłoby grafikę — narzędzia stoją
 * OBOK obrazu). Decyzja o miejscu w repo: 2026-09-17c.
 *
 * Użycie:
 *   offscreen <shader.frag> -o <katalog> [-s WxH] [-p bg,ink,accent]
 *             [-f fps] [-t 0.5,3,6.25]   czasy klatek do zapisu (sekundy)
 *             [--audio synth|silence|<plik.f32>] [--detail 0..1] [-v]
 *   Klatki liczone są CIĄGLE od 0 z krokiem 1/fps (tryb cząstkowy musi
 *   akumulować), zapisywane tylko w podanych czasach:
 *   <katalog>/<nazwa>-<czas>.png. Na końcu: średni czas klatki (ms).
 *
 * Syntezator (deterministyczny, 48 kHz stereo): stopa 2 Hz (60 Hz z zanikiem),
 * bas na przemian 55/82 Hz, pad z trzech tonów, hi-hat co 250 ms (szum),
 * lekki stereo-spread (pad szerzej w L, hat w R) — wystarczy, żeby zobaczyć
 * reakcję na bas, środek, wysokie i beat oraz figury XY z L≠R.
 *   „silence" — cisza (klatki bazowe animacji).
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <time.h>
#include <zlib.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include "../engine.h"
#include "../audio.h"
#include "../util.h"    /* flux_now_seconds, flux_read_file — wspólne z main.c i audio.c */

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static void die(const char *msg) { fprintf(stderr, "offscreen: %s\n", msg); exit(1); }

static bool parse_hex(const char *s, float out[3]) {
    if (strlen(s) != 6) return false;
    unsigned v = (unsigned)strtoul(s, NULL, 16);
    out[0] = ((v >> 16) & 255) / 255.0f; out[1] = ((v >> 8) & 255) / 255.0f; out[2] = (v & 255) / 255.0f;
    return true;
}

/* ── PNG (RGB8, filtr 0, zlib) ─────────────────────────────────────────── */
static void put32(FILE *f, uint32_t v) { unsigned char b[4] = { v >> 24, v >> 16, v >> 8, v }; fwrite(b, 1, 4, f); }
static void chunk(FILE *f, const char *tag, const unsigned char *data, size_t n) {
    put32(f, (uint32_t)n);
    fwrite(tag, 1, 4, f);
    if (n) fwrite(data, 1, n, f);
    uint32_t crc = crc32(0, (const unsigned char *)tag, 4);
    if (n) crc = crc32(crc, data, (uInt)n);
    put32(f, crc);
}
static bool write_png(const char *path, int w, int h, const unsigned char *rgba) {
    size_t row = (size_t)w * 3 + 1, raw_n = row * (size_t)h;
    unsigned char *raw = malloc(raw_n);
    if (!raw) return false;
    for (int y = 0; y < h; y++) {                     /* GL: wiersz 0 na dole → PNG od góry */
        unsigned char *dst = raw + (size_t)y * row;
        const unsigned char *src = rgba + (size_t)(h - 1 - y) * (size_t)w * 4;
        *dst++ = 0;
        for (int x = 0; x < w; x++) { dst[0] = src[0]; dst[1] = src[1]; dst[2] = src[2]; dst += 3; src += 4; }
    }
    uLongf zn = compressBound((uLong)raw_n);
    unsigned char *z = malloc(zn);
    if (!z || compress2(z, &zn, raw, (uLong)raw_n, 6) != Z_OK) { free(raw); free(z); return false; }
    FILE *f = fopen(path, "wb");
    if (!f) { free(raw); free(z); return false; }
    static const unsigned char sig[8] = { 137, 80, 78, 71, 13, 10, 26, 10 };
    fwrite(sig, 1, 8, f);
    unsigned char ihdr[13] = { (unsigned char)(w >> 24), (unsigned char)(w >> 16), (unsigned char)(w >> 8), (unsigned char)w,
                               (unsigned char)(h >> 24), (unsigned char)(h >> 16), (unsigned char)(h >> 8), (unsigned char)h, 8, 2, 0, 0, 0 };
    chunk(f, "IHDR", ihdr, 13);
    chunk(f, "IDAT", z, zn);
    chunk(f, "IEND", NULL, 0);
    fclose(f); free(raw); free(z);
    return true;
}

/* ── syntezator ────────────────────────────────────────────────────────── */
static uint32_t rng = 2026u;
static float frand(void) { rng = rng * 1664525u + 1013904223u; return (float)(rng >> 8) / 16777216.0f * 2.0f - 1.0f; }

/* próbka stereo w czasie t (sekundy) */
static void synth(double t, float *l, float *r) {
    double beat = fmod(t, 0.5);                                      /* stopa 2 Hz */
    float kick = (float)(sin(2 * M_PI * 60.0 * beat * (1.0 - beat)) * exp(-beat * 9.0)) * 0.9f;
    int bar = (int)(t / 2.0) & 1;
    double fb = bar ? 82.41 : 55.0;
    float bass = (float)sin(2 * M_PI * fb * t) * 0.35f * (float)(0.6 + 0.4 * (1.0 - fmod(t, 0.25) / 0.25));
    float pad = (float)(sin(2 * M_PI * 220.0 * t) + sin(2 * M_PI * 277.18 * t) * 0.8 + sin(2 * M_PI * 329.63 * t) * 0.6) * 0.08f;
    /* prawy kanał: bas przesunięty o 90° i pad odstrojony o 1% — w trybie XY
     * daje elipsy i pętle zamiast jednej kreski (stereo, którego mono nie ma) */
    float bass_r = (float)cos(2 * M_PI * fb * t) * 0.35f * (float)(0.6 + 0.4 * (1.0 - fmod(t, 0.25) / 0.25));
    float pad_r = (float)(sin(2 * M_PI * 222.2 * t) + sin(2 * M_PI * 280.0 * t) * 0.8 + sin(2 * M_PI * 332.9 * t) * 0.6) * 0.08f;
    double hb = fmod(t, 0.25);
    float hat = frand() * (float)exp(-hb * 40.0) * 0.18f * (fmod(t, 0.5) > 0.25 ? 1.0f : 0.6f);
    *l = kick + bass + pad * 1.2f + hat * 0.6f;
    *r = kick + bass_r * 0.9f + pad_r * 0.7f + hat * 1.2f;
}

/* Cechy dźwięku na chwilę `t`: analiza okien co hop, jak wątek na żywo. */
struct feeder {
    struct audio_state st;
    float ring[AUDIO_FFT_N], ring_l[AUDIO_FFT_N], ring_r[AUDIO_FFT_N];
    long  next_sample;           /* pierwsza próbka jeszcze niewprowadzona */
    FILE *file;                  /* NULL = synth; pusty tryb: silence */
    bool  silence;
};

static void feeder_advance(struct feeder *fd, double t) {
    long target = (long)(t * AUDIO_RATE);
    while (fd->next_sample + AUDIO_HOP <= target) {
        const size_t keep = (AUDIO_FFT_N - AUDIO_HOP) * sizeof(float);
        memmove(fd->ring, fd->ring + AUDIO_HOP, keep);
        memmove(fd->ring_l, fd->ring_l + AUDIO_HOP, keep);
        memmove(fd->ring_r, fd->ring_r + AUDIO_HOP, keep);
        for (int i = 0; i < AUDIO_HOP; i++) {
            float l = 0, r = 0;
            if (fd->file) {
                float p[2];
                if (fread(p, sizeof(float), 2, fd->file) < 2) { rewind(fd->file); if (fread(p, sizeof(float), 2, fd->file) < 2) p[0] = p[1] = 0; }
                l = p[0]; r = p[1];
            } else if (!fd->silence) {
                synth((double)(fd->next_sample + i) / AUDIO_RATE, &l, &r);
            }
            fd->ring_l[AUDIO_FFT_N - AUDIO_HOP + i] = l;
            fd->ring_r[AUDIO_FFT_N - AUDIO_HOP + i] = r;
            fd->ring[AUDIO_FFT_N - AUDIO_HOP + i]   = 0.5f * (l + r);
        }
        fd->next_sample += AUDIO_HOP;
        audio_analyze(&fd->st, fd->ring, (float)AUDIO_HOP / AUDIO_RATE, (double)fd->next_sample / AUDIO_RATE);
        int start = audio_trigger(fd->ring, AUDIO_FFT_N, AUDIO_WAVE_N, 0.01f);
        audio_wave_fill(&fd->st.out, fd->ring_l, fd->ring_r, AUDIO_FFT_N, start);
        fd->st.out.live = true;
    }
}

/* ── EGL surfaceless ──────────────────────────────────────────────────── */
static void egl_init(bool verbose) {
    EGLDisplay dpy = EGL_NO_DISPLAY;
    PFNEGLGETPLATFORMDISPLAYEXTPROC gpd = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
#ifdef EGL_PLATFORM_SURFACELESS_MESA
    if (gpd) dpy = gpd(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
#endif
    if (dpy == EGL_NO_DISPLAY) dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (dpy == EGL_NO_DISPLAY) die("eglGetDisplay: brak wyświetlacza EGL (surfaceless)");
    EGLint maj, min;
    if (!eglInitialize(dpy, &maj, &min)) die("eglInitialize");
    if (verbose) fprintf(stderr, "offscreen: EGL %d.%d, %s\n", maj, min, eglQueryString(dpy, EGL_VENDOR));
    if (!eglBindAPI(EGL_OPENGL_ES_API)) die("eglBindAPI");
    const EGLint cfg_attr[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
                                EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE };
    EGLConfig cfg; EGLint n = 0;
    if (!eglChooseConfig(dpy, cfg_attr, &cfg, 1, &n) || n < 1) {
        const EGLint any[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE };
        if (!eglChooseConfig(dpy, any, &cfg, 1, &n) || n < 1) die("eglChooseConfig: brak konfiguracji GLES3");
    }
    const EGLint ctx_attr[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
    if (ctx == EGL_NO_CONTEXT) die("eglCreateContext (ES 3.0)");
    /* surfaceless: bez powierzchni (EGL_KHR_surfaceless_context); fallback pbuffer 1×1 */
    if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
        const EGLint pb[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
        EGLSurface s = eglCreatePbufferSurface(dpy, cfg, pb);
        if (s == EGL_NO_SURFACE || !eglMakeCurrent(dpy, s, s, ctx)) die("eglMakeCurrent (surfaceless i pbuffer)");
    }
    if (verbose) fprintf(stderr, "offscreen: GL %s / %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
}

static void usage(void) {
    fprintf(stderr,
        "offscreen <shader.frag> -o <katalog> [-s WxH] [-p bg,ink,accent] [-f fps]\n"
        "          [-t t1,t2,...] [--audio synth|silence|plik.f32] [--detail 0..1] [-v]\n");
    exit(2);
}

int main(int argc, char **argv) {
    const char *frag_path = NULL, *out_dir = NULL, *audio_mode = "synth";
    int w = 960, h = 540; double fps = 60.0; float detail = 1.0f; bool verbose = false;
    struct palette pal = { {0.012f, 0.082f, 0.2f}, {0.188f, 0.412f, 0.678f}, {0.212f, 0.824f, 0.847f} };   /* crt */
    double times[64]; int ntimes = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-o") && i + 1 < argc) out_dir = argv[++i];
        else if (!strcmp(argv[i], "-s") && i + 1 < argc) { if (sscanf(argv[++i], "%dx%d", &w, &h) != 2) usage(); }
        else if (!strcmp(argv[i], "-p") && i + 1 < argc) {
            char buf[64]; strncpy(buf, argv[++i], sizeof buf - 1); buf[sizeof buf - 1] = 0;
            char *a = strtok(buf, ","), *b = strtok(NULL, ","), *c = strtok(NULL, ",");
            if (!a || !b || !c || !parse_hex(a, pal.bg) || !parse_hex(b, pal.ink) || !parse_hex(c, pal.accent)) usage();
        }
        else if (!strcmp(argv[i], "-f") && i + 1 < argc) fps = atof(argv[++i]);
        else if (!strcmp(argv[i], "-t") && i + 1 < argc) {
            char buf[512]; strncpy(buf, argv[++i], sizeof buf - 1); buf[sizeof buf - 1] = 0;
            for (char *tok = strtok(buf, ","); tok && ntimes < 64; tok = strtok(NULL, ",")) times[ntimes++] = atof(tok);
        }
        else if (!strcmp(argv[i], "--audio") && i + 1 < argc) audio_mode = argv[++i];
        else if (!strcmp(argv[i], "--detail") && i + 1 < argc) detail = (float)atof(argv[++i]);
        else if (!strcmp(argv[i], "-v")) verbose = true;
        else if (argv[i][0] == '-') usage();
        else frag_path = argv[i];
    }
    if (!frag_path || !out_dir) usage();
    if (ntimes == 0) { times[0] = 0.5; times[1] = 3.0; times[2] = 6.0; ntimes = 3; }
    if (fps <= 0) fps = 60.0;

    char *frag = flux_read_file(frag_path);
    if (!frag) die("nie mogę wczytać shadera");
    char upath[1024]; char *update = NULL;
    if (flux_update_path(frag_path, upath, sizeof upath)) update = flux_read_file(upath);

    egl_init(verbose);
    char err[2560];
    struct flux_engine *e = flux_engine_create(frag, frag_path, update, update ? upath : NULL, err, sizeof err);
    if (!e) { fprintf(stderr, "offscreen: %s\n", err); return 3; }
    struct flux_target *t = flux_target_create(e, w, h, err, sizeof err);
    if (!t) { fprintf(stderr, "offscreen: %s\n", err); return 3; }

    /* FBO docelowe (RGBA8) — to, co na żywo jest powierzchnią okna */
    GLuint tex, fbo;
    glGenTextures(1, &tex); glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) die("FBO RGBA8 niekompletny");
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    struct feeder fd; memset(&fd, 0, sizeof fd);
    audio_state_init(&fd.st);
    bool use_audio = strcmp(audio_mode, "silence") != 0;
    if (strcmp(audio_mode, "synth") && strcmp(audio_mode, "silence")) {
        fd.file = fopen(audio_mode, "rb");
        if (!fd.file) die("nie mogę otworzyć pliku audio");
    }
    fd.silence = !use_audio;
    const struct flux_params *p = flux_engine_params(e);
    bool wants_audio = p->audio != 0;
    if (verbose) fprintf(stderr, "offscreen: %s, %dx%d, %s, audio=%s (pragma audio %d)\n", frag_path, w, h,
                         flux_engine_is_particle(e) ? "cząstkowy" : "jednoprzebiegowy", audio_mode, p->audio);

    double tmax = 0; for (int i = 0; i < ntimes; i++) if (times[i] > tmax) tmax = times[i];
    long nframes = (long)ceil(tmax * fps) + 1;
    unsigned char *pix = malloc((size_t)w * h * 4);
    if (!pix) die("brak pamięci");
    const char *base = strrchr(frag_path, '/'); base = base ? base + 1 : frag_path;
    char name[256]; strncpy(name, base, sizeof name - 1); name[sizeof name - 1] = 0;
    char *dot = strrchr(name, '.'); if (dot) *dot = 0;

    double clock_total = 0; long rendered = 0; int saved = 0;
    for (long fi = 0; fi < nframes; fi++) {
        double tt = fi / fps;
        const struct audio_features *feat = NULL;
        if (wants_audio) { feeder_advance(&fd, tt); feat = &fd.st.out; }
        double c0 = flux_now_seconds();
        flux_engine_render(e, t, fbo, tt, &pal, detail, feat, 1.0f, false);
        glFinish();
        clock_total += flux_now_seconds() - c0; rendered++;
        for (int i = 0; i < ntimes; i++) {
            if (fabs(times[i] - tt) < 0.5 / fps) {
                glBindFramebuffer(GL_FRAMEBUFFER, fbo);
                glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, pix);
                glBindFramebuffer(GL_FRAMEBUFFER, 0);
                char path[1200]; snprintf(path, sizeof path, "%s/%s-%05.2f.png", out_dir, name, times[i]);
                if (!write_png(path, w, h, pix)) die("zapis PNG");
                if (verbose) fprintf(stderr, "offscreen: %s\n", path);
                saved++;
            }
        }
    }
    printf("%s: %d klatek zapisanych, %ld policzonych, %.2f ms/klatka (%s)\n", name, saved, rendered,
           rendered ? clock_total / rendered * 1000.0 : 0.0, (const char *)glGetString(GL_RENDERER));
    free(pix); flux_target_destroy(t); flux_engine_destroy(e); free(frag); free(update);
    if (fd.file) fclose(fd.file);
    return 0;
}
