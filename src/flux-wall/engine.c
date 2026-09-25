/*
 * archenemy - flux-wall: silnik renderowania — patrz engine.h.
 *
 * Tryb cząstkowy, jedna klatka:
 *   1. zanik akumulatora: mnożenie przez exp(-dt / life)  (blend ZERO, SRC_COLOR)
 *   2. N kroków symulacji (N z tempa `rate` i realnego dt, max 4 — po pauzie
 *      kompozytora NIE dogania straconych sekund, tylko idzie dalej):
 *        a. krok cząstek: pełnoekranowy trójkąt do FBO pozycji P×P (ping-pong)
 *        b. ślady: GL_POINTS × P², blend ONE, ONE, do akumulatora R16F
 *   3. przebieg finalny (.frag użytkownika) z akumulatorem jako `accum`.
 * Tryb jednoprzebiegowy = sam punkt 3 bez `accum`, bit w bit jak przed silnikiem.
 */
#define _POSIX_C_SOURCE 200809L
#include "engine.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── shadery wbudowane ────────────────────────────────────────────────────── */

static const char *VS_QUAD =
    "#version 300 es\n"
    "void main() {\n"
    "    /* jeden trojkat pokrywajacy caly ekran, bez VBO */\n"
    "    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);\n"
    "    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);\n"
    "}\n";

/* Prelude kroku cząstek: uniformy kontraktu + szum 1:1 z generatora PNG
 * (h2 na uint32 z tym samym mnożnikiem i przesunięciami; wynik /0xFFFFFFFF). */
static const char *UPDATE_PRELUDE =
    "#version 300 es\n"
    "precision highp float;\n"
    "precision highp int;\n"
    "precision highp sampler2D;   /* domyślnie lowp: pozycje z texelFetch byłyby zaokrąglane (Mesa honoruje, NVIDIA nie) */\n"
    "uniform sampler2D pos;\n"
    "uniform float time;\n"
    "uniform float dt;\n"
    "uniform float detail;\n"
    "uniform vec2  resolution;\n"
    "uniform float aspect;\n"
    "uniform int   seed;\n"
    "uniform float life_steps;\n"
    "uniform sampler2D accum;   /* akumulator z poprzedniego kroku — cząstki mogą reagować na gęstość */\n"
    "uniform float audio_level;\n"
    "uniform float audio_bass;\n"
    "uniform float audio_lowmid;\n"
    "uniform float audio_mid;\n"
    "uniform float audio_high;\n"
    "uniform float audio_beat;\n"
    "uniform sampler2D audio_spectrum;\n"
    "uniform sampler2D audio_wave;   /* przebieg po triggerze: N×1 RG32F, r = L, g = R, w -1..1 */\n"
    "uniform float audio_wave_peak;  /* szczyt |mono| okna przebiegu — auto-wzmocnienie oscyloskopu */\n"
    "uniform sampler2D audio_spectrogram;     /* historia kolumn: COLS×BINS R8, S = REPEAT (pierścień) */\n"
    "uniform float audio_spectrogram_head;    /* indeks kolumny NAJNOWSZEJ (x tekstury) */\n"
    "out vec4 o;\n"
    "uint h2u(int x, int y, int s) {\n"
    "    uint n = uint(x) * 374761393u + uint(y) * 668265263u + uint(s) * 1013904223u;\n"
    "    n = n ^ (n >> 13u); n = n * 1274126177u; n = n ^ (n >> 16u);\n"
    "    return n;\n"
    "}\n"
    "float h2(int x, int y, int s) { return float(h2u(x, y, s)) / 4294967295.0; }\n"
    "float vnoise(vec2 p, int s) {\n"
    "    vec2 i = floor(p), f = fract(p);\n"
    "    vec2 u = f * f * (3.0 - 2.0 * f);\n"
    "    int xi = int(i.x), yi = int(i.y);\n"
    "    float a = h2(xi, yi, s), b = h2(xi + 1, yi, s);\n"
    "    float c = h2(xi, yi + 1, s), d = h2(xi + 1, yi + 1, s);\n"
    "    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);\n"
    "}\n"
    "float fbm(vec2 p, int octaves, int s) {\n"
    "    float amp = 1.0, fr = 1.0, tot = 0.0, nrm = 0.0;\n"
    "    for (int i = 0; i < 4; i++) {\n"
    "        if (i >= octaves) break;\n"
    "        tot += amp * vnoise(p * fr, s + i * 101);\n"
    "        nrm += amp; amp *= 0.5; fr *= 2.0;\n"
    "    }\n"
    "    return tot / nrm;\n"
    "}\n"
    "#line 1\n";

static const char *VS_SPLAT =
    "#version 300 es\n"
    "precision highp float;\n"
    "uniform sampler2D pos;\n"
    "uniform int   P;\n"
    "uniform int   n_active;\n"
    "uniform int   splat;\n"
    "uniform float scale;\n"
    "uniform float aspect;\n"
    "uniform float warm;\n"
    "out float vis;\n"
    "void main() {\n"
    "    ivec2 idx = ivec2(gl_VertexID % P, gl_VertexID / P);\n"
    "    vec4 s = texelFetch(pos, idx, 0);\n"
    "    vec2 p = s.xy;\n"
    "    if (splat == 1) p = vec2(0.5) + p * scale * vec2(1.0 / aspect, 1.0);\n"
    "    bool ok = gl_VertexID < n_active && s.z > warm;\n"
    "    vis = ok ? 1.0 : 0.0;\n"
    "    /* nieaktywna cząstka: poza bryłą widzenia = odrzucona bez fragmentu */\n"
    "    gl_Position = ok ? vec4(p * 2.0 - 1.0, 0.0, 1.0) : vec4(2.0, 2.0, 2.0, 1.0);\n"
    "    gl_PointSize = 1.0;\n"
    "}\n";

static const char *FS_SPLAT =
    "#version 300 es\n"
    "precision highp float;\n"
    "uniform float inc;\n"
    "in float vis;\n"
    "out vec4 o;\n"
    "void main() { if (vis < 0.5) discard; o = vec4(inc, 0.0, 0.0, 1.0); }\n";

static const char *FS_FADE =
    "#version 300 es\n"
    "precision highp float;\n"
    "uniform float keep;\n"
    "out vec4 o;\n"
    "void main() { o = vec4(keep, keep, keep, 1.0); }\n";

/* ── struktury ────────────────────────────────────────────────────────────── */

#define AUDIO_UNIFORMS 11
/* Historia spektrogramu: kolumn w pierścieniu (50/s → ~41 s). */
#define SPECTRO_COLS   2048

struct flux_engine {
    bool particle;
    struct flux_params params;
    int P;                                  /* bok tekstury pozycji */
    GLuint prog_present, prog_update, prog_splat, prog_fade;
    GLuint vao;
    /* present */
    GLint u_resolution, u_time, u_bg, u_ink, u_accent, u_detail, u_accum, u_gain;
    /* update */
    GLint uu_pos, uu_time, uu_dt, uu_detail, uu_resolution, uu_aspect, uu_seed, uu_life, uu_accum;
    /* splat */
    GLint us_pos, us_P, us_active, us_splat, us_scale, us_aspect, us_warm, us_inc;
    /* fade */
    GLint uf_keep;
    /* audio: present (p) i update (u): level, bass, lowmid, mid, high, beat, spectrum, wave,
     * wave_peak, spectrogram, spectrogram_head */
    GLint up_audio[AUDIO_UNIFORMS], uu_audio[AUDIO_UNIFORMS];
};

struct flux_target {
    struct flux_engine *e;
    int w, h;
    GLuint acc_tex, acc_fbo;
    GLuint pos_tex[2], pos_fbo[2];
    int src;                                /* która tekstura pozycji jest aktualna */
    double last_time;                       /* < 0 = jeszcze nie renderowano */
    double step_acc;                        /* ułamek kroku przeniesiony na następną klatkę */
    double warp_offset;                     /* anim_time = time + warp_offset (0 bez muzyki — bit w bit) */
    GLuint spec_tex;                        /* widmo 32×1 R32F, jednostka 2 */
    GLuint wave_tex;                        /* przebieg AUDIO_WAVE_N×1 RG32F (L, R), jednostka 3 */
    GLuint spectro_tex;                     /* spektrogram SPECTRO_COLS×BINS R8 (pierścień po x), jednostka 4 */
    int    spectro_head;                    /* kolumna najnowsza */
    double spectro_acc;                     /* ułamek kolumny przeniesiony na następną klatkę */
    bool warmed;
};

/* ── czyste funkcje ───────────────────────────────────────────────────────── */

bool flux_update_path(const char *frag_path, char *out, size_t outlen) {
    size_t n = strlen(frag_path);
    const char *suf = ".frag";
    size_t sl = strlen(suf);
    if (n <= sl || strcmp(frag_path + n - sl, suf) != 0) return false;
    if (n - sl + strlen(".update.glsl") + 1 > outlen) return false;
    memcpy(out, frag_path, n - sl);
    strcpy(out + n - sl, ".update.glsl");
    return true;
}

static bool set_param(struct flux_params *p, const char *key, const char *val, char *err, size_t errlen) {
    char *end;
    double d = strtod(val, &end);
    if (end == val || *end != 0) { snprintf(err, errlen, "#pragma flux %s: '%s' nie jest liczbą", key, val); return false; }
    if      (strcmp(key, "particles") == 0) { if (d < 1 || d > 4000000) goto range; p->particles = (int)d; }
    else if (strcmp(key, "life")      == 0) { if (d <= 0 || d > 600)    goto range; p->life = (float)d; }
    else if (strcmp(key, "rate")      == 0) { if (d <= 0 || d > 1000)   goto range; p->rate = (float)d; }
    else if (strcmp(key, "inc")       == 0) { if (d <= 0 || d > 1)      goto range; p->inc = (float)d; }
    else if (strcmp(key, "gain")      == 0) { if (d <= 0 || d > 10000)  goto range; p->gain = (float)d; }
    else if (strcmp(key, "splat")     == 0) { if (d != 0 && d != 1)     goto range; p->splat = (int)d; }
    else if (strcmp(key, "scale")     == 0) { if (d <= 0 || d > 100)    goto range; p->scale = (float)d; }
    else if (strcmp(key, "warmup")    == 0) { if (d < 0 || d > 600)     goto range; p->warmup = (float)d; }
    else if (strcmp(key, "warm")      == 0) { if (d < 0 || d > 100000)  goto range; p->warm = (int)d; }
    else if (strcmp(key, "seed")      == 0) { if (d < 0 || d > 2147483647.0) goto range; p->seed = (int)d; }
    else if (strcmp(key, "audio")         == 0) { if (d != 0 && d != 1) goto range; p->audio = (int)d; }
    else if (strcmp(key, "audio_tempo")   == 0) { if (d < 0 || d > 10) goto range; p->audio_tempo = (float)d; }
    else if (strcmp(key, "audio_glow")    == 0) { if (d < 0 || d > 10) goto range; p->audio_glow = (float)d; }
    else if (strcmp(key, "audio_sparkle") == 0) { if (d < 0 || d > 10) goto range; p->audio_sparkle = (float)d; }
    else { snprintf(err, errlen, "#pragma flux: nieznany klucz '%s'", key); return false; }
    return true;
range:
    snprintf(err, errlen, "#pragma flux %s: wartość %s poza zakresem", key, val);
    return false;
}

/* `#pragma flux klucz wartość` — jedna para na linię; reszta pliku ignorowana.
 * Wartości domyślne wpisuje wołający (FLUX_PARAMS_DEFAULT). */
bool flux_params_parse(const char *src, struct flux_params *p, char *err, size_t errlen) {
    const char *line = src;
    while (line && *line) {
        const char *nl = strchr(line, '\n');
        size_t len = nl ? (size_t)(nl - line) : strlen(line);
        const char *s = line;
        while (len && isspace((unsigned char)*s)) { s++; len--; }
        if (len > 12 && strncmp(s, "#pragma flux", 12) == 0 && isspace((unsigned char)s[12])) {
            char buf[128];
            if (len >= sizeof buf) { snprintf(err, errlen, "#pragma flux: za długa linia"); return false; }
            memcpy(buf, s + 12, len - 12); buf[len - 12] = 0;
            char *save = NULL;
            char *key = strtok_r(buf, " \t\r", &save);
            char *val = key ? strtok_r(NULL, " \t\r", &save) : NULL;
            char *extra = val ? strtok_r(NULL, " \t\r", &save) : NULL;
            if (!key || !val || extra) { snprintf(err, errlen, "#pragma flux: oczekiwane 'klucz wartość', jest '%.*s'", (int)(len - 12), s + 12); return false; }
            if (!set_param(p, key, val, err, errlen)) return false;
        }
        line = nl ? nl + 1 : NULL;
    }
    return true;
}

/* Linie `#pragma flux` (i `#version`, gdy wersję niesie prelude) zamieniamy
 * na spacje — numery linii w błędach kompilatora zostają zgodne z plikiem. */
char *flux_strip_directives(const char *src, bool keep_version) {
    char *out = strdup(src);
    if (!out) return NULL;
    char *line = out;
    while (line && *line) {
        char *nl = strchr(line, '\n');
        char *s = line;
        while (*s == ' ' || *s == '\t') s++;
        bool pragma = strncmp(s, "#pragma flux", 12) == 0;
        bool version = !keep_version && strncmp(s, "#version", 8) == 0;
        if (pragma || version) {
            size_t len = nl ? (size_t)(nl - line) : strlen(line);
            memset(line, ' ', len);
        }
        line = nl ? nl + 1 : NULL;
    }
    return out;
}

double flux_warp(const struct flux_params *p, const struct audio_features *audio, float strength) {
    if (!audio || strength <= 0.0f) return 1.0;
    double w = 1.0 + (double)p->audio_tempo * strength * audio->mid;
    return w < 1.0 ? 1.0 : w;
}

int flux_step_cap(const struct flux_params *p, float strength) {
    if (strength <= 0.0f) return 4;
    return 4 * (int)ceil(1.0 + (double)p->audio_tempo * strength);
}

/* ── GL: budowanie programów ──────────────────────────────────────────────── */

static GLuint compile(GLenum type, const char *src, const char *label, char *err, size_t errlen) {
    GLuint sh = glCreateShader(type);
    glShaderSource(sh, 1, &src, NULL);
    glCompileShader(sh);
    GLint ok = 0;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[2048];
        glGetShaderInfoLog(sh, sizeof log, NULL, log);
        snprintf(err, errlen, "kompilacja shadera (%s) nie powiodła się:\n%s", label, log);
        glDeleteShader(sh);
        return 0;
    }
    return sh;
}

static GLuint link(const char *vs_src, const char *fs_src, const char *label, char *err, size_t errlen) {
    GLuint vs = compile(GL_VERTEX_SHADER, vs_src, "vertex", err, errlen);
    if (!vs) return 0;
    GLuint fs = compile(GL_FRAGMENT_SHADER, fs_src, label, err, errlen);
    if (!fs) { glDeleteShader(vs); return 0; }
    GLuint p = glCreateProgram();
    glAttachShader(p, vs);
    glAttachShader(p, fs);
    glLinkProgram(p);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[2048];
        glGetProgramInfoLog(p, sizeof log, NULL, log);
        snprintf(err, errlen, "linkowanie programu (%s) nie powiodło się:\n%s", label, log);
        glDeleteProgram(p);
        return 0;
    }
    return p;
}

struct flux_engine *flux_engine_create(const char *frag_src, const char *frag_label,
                                       const char *update_src, const char *update_label,
                                       char *err, size_t errlen) {
    struct flux_engine *e = calloc(1, sizeof *e);
    if (!e) { snprintf(err, errlen, "brak pamięci"); return NULL; }
    struct flux_params def = FLUX_PARAMS_DEFAULT;
    e->params = def;

    /* Pragmy wolno pisać w .frag (animacje jednoprzebiegowe — np. audio_tempo);
     * .update.glsl czytany dalej nadpisuje. Przed kompilacją linie pragm
     * znikają, `#version` w .frag zostaje (nie ma prelude). */
    if (!flux_params_parse(frag_src, &e->params, err, errlen)) { free(e); return NULL; }
    char *frag_clean = flux_strip_directives(frag_src, true);
    if (!frag_clean) { snprintf(err, errlen, "brak pamięci"); free(e); return NULL; }
    e->prog_present = link(VS_QUAD, frag_clean, frag_label, err, errlen);
    free(frag_clean);
    if (!e->prog_present) { free(e); return NULL; }
    e->u_resolution = glGetUniformLocation(e->prog_present, "resolution");
    e->u_time       = glGetUniformLocation(e->prog_present, "time");
    e->u_bg         = glGetUniformLocation(e->prog_present, "palette_bg");
    e->u_ink        = glGetUniformLocation(e->prog_present, "palette_ink");
    e->u_accent     = glGetUniformLocation(e->prog_present, "palette_accent");
    e->u_detail     = glGetUniformLocation(e->prog_present, "detail");
    e->u_accum      = glGetUniformLocation(e->prog_present, "accum");
    e->u_gain       = glGetUniformLocation(e->prog_present, "gain");
    static const char *AUDIO_NAMES[AUDIO_UNIFORMS] = { "audio_level", "audio_bass", "audio_lowmid", "audio_mid",
                                          "audio_high", "audio_beat", "audio_spectrum", "audio_wave", "audio_wave_peak",
                                          "audio_spectrogram", "audio_spectrogram_head" };
    for (int i = 0; i < AUDIO_UNIFORMS; i++) e->up_audio[i] = glGetUniformLocation(e->prog_present, AUDIO_NAMES[i]);
    for (int i = 0; i < AUDIO_UNIFORMS; i++) e->uu_audio[i] = -1;

    glGenVertexArrays(1, &e->vao);

    if (!update_src) return e;

    e->particle = true;
    if (!flux_params_parse(update_src, &e->params, err, errlen)) { flux_engine_destroy(e); return NULL; }
    e->P = (int)ceil(sqrt((double)e->params.particles));
    if (e->P < 1) e->P = 1;

    char *body = flux_strip_directives(update_src, false);
    if (!body) { snprintf(err, errlen, "brak pamięci"); flux_engine_destroy(e); return NULL; }
    size_t n = strlen(UPDATE_PRELUDE) + strlen(body) + 1;
    char *full = malloc(n);
    if (!full) { free(body); snprintf(err, errlen, "brak pamięci"); flux_engine_destroy(e); return NULL; }
    strcpy(full, UPDATE_PRELUDE);
    strcat(full, body);
    free(body);
    e->prog_update = link(VS_QUAD, full, update_label, err, errlen);
    free(full);
    if (!e->prog_update) { flux_engine_destroy(e); return NULL; }
    e->uu_pos        = glGetUniformLocation(e->prog_update, "pos");
    e->uu_time       = glGetUniformLocation(e->prog_update, "time");
    e->uu_dt         = glGetUniformLocation(e->prog_update, "dt");
    e->uu_detail     = glGetUniformLocation(e->prog_update, "detail");
    e->uu_resolution = glGetUniformLocation(e->prog_update, "resolution");
    e->uu_aspect     = glGetUniformLocation(e->prog_update, "aspect");
    e->uu_seed       = glGetUniformLocation(e->prog_update, "seed");
    e->uu_life       = glGetUniformLocation(e->prog_update, "life_steps");
    e->uu_accum      = glGetUniformLocation(e->prog_update, "accum");
    for (int i = 0; i < AUDIO_UNIFORMS; i++) e->uu_audio[i] = glGetUniformLocation(e->prog_update, AUDIO_NAMES[i]);

    e->prog_splat = link(VS_SPLAT, FS_SPLAT, "splat", err, errlen);
    if (!e->prog_splat) { flux_engine_destroy(e); return NULL; }
    e->us_pos    = glGetUniformLocation(e->prog_splat, "pos");
    e->us_P      = glGetUniformLocation(e->prog_splat, "P");
    e->us_active = glGetUniformLocation(e->prog_splat, "n_active");
    e->us_splat  = glGetUniformLocation(e->prog_splat, "splat");
    e->us_scale  = glGetUniformLocation(e->prog_splat, "scale");
    e->us_aspect = glGetUniformLocation(e->prog_splat, "aspect");
    e->us_warm   = glGetUniformLocation(e->prog_splat, "warm");
    e->us_inc    = glGetUniformLocation(e->prog_splat, "inc");

    e->prog_fade = link(VS_QUAD, FS_FADE, "fade", err, errlen);
    if (!e->prog_fade) { flux_engine_destroy(e); return NULL; }
    e->uf_keep = glGetUniformLocation(e->prog_fade, "keep");
    return e;
}

void flux_engine_destroy(struct flux_engine *e) {
    if (!e) return;
    if (e->prog_present) glDeleteProgram(e->prog_present);
    if (e->prog_update)  glDeleteProgram(e->prog_update);
    if (e->prog_splat)   glDeleteProgram(e->prog_splat);
    if (e->prog_fade)    glDeleteProgram(e->prog_fade);
    if (e->vao)          glDeleteVertexArrays(1, &e->vao);
    free(e);
}

bool flux_engine_is_particle(const struct flux_engine *e) { return e->particle; }
const struct flux_params *flux_engine_params(const struct flux_engine *e) { return &e->params; }

/* ── GL: cel per powierzchnia ─────────────────────────────────────────────── */

static GLuint make_tex(int w, int h, GLenum ifmt, GLenum fmt, GLenum type, const void *data) {
    GLuint t;
    glGenTextures(1, &t);
    glBindTexture(GL_TEXTURE_2D, t);
    glTexImage2D(GL_TEXTURE_2D, 0, (GLint)ifmt, w, h, 0, fmt, type, data);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return t;
}

/* FBO z jedną teksturą; false = format nie jest renderowalny na tym sterowniku. */
static bool make_fbo(GLuint tex, GLuint *fbo) {
    glGenFramebuffers(1, fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, *fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    GLenum st = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (st != GL_FRAMEBUFFER_COMPLETE) { glDeleteFramebuffers(1, fbo); *fbo = 0; return false; }
    return true;
}

static void target_free_gl(struct flux_target *t) {
    if (t->spec_tex) glDeleteTextures(1, &t->spec_tex);
    t->spec_tex = 0;
    if (t->wave_tex) glDeleteTextures(1, &t->wave_tex);
    t->wave_tex = 0;
    if (t->spectro_tex) glDeleteTextures(1, &t->spectro_tex);
    t->spectro_tex = 0;
    if (t->acc_fbo) glDeleteFramebuffers(1, &t->acc_fbo);
    if (t->acc_tex) glDeleteTextures(1, &t->acc_tex);
    for (int i = 0; i < 2; i++) {
        if (t->pos_fbo[i]) glDeleteFramebuffers(1, &t->pos_fbo[i]);
        if (t->pos_tex[i]) glDeleteTextures(1, &t->pos_tex[i]);
    }
    t->acc_fbo = t->acc_tex = 0;
    t->pos_fbo[0] = t->pos_fbo[1] = t->pos_tex[0] = t->pos_tex[1] = 0;
}

/* Nowy, wyczyszczony akumulator w×h; przy błędzie nic nie zostaje przydzielone
 * (tekstura zwolniona), więc wołający może zachować stary. */
static bool alloc_accum(int w, int h, GLuint *tex, GLuint *fbo, char *err, size_t errlen) {
    *tex = make_tex(w, h, GL_R16F, GL_RED, GL_HALF_FLOAT, NULL);
    if (!make_fbo(*tex, fbo)) {
        glDeleteTextures(1, tex);
        *tex = 0;
        snprintf(err, errlen, "akumulator R16F nie jest renderowalny (brak GL_EXT_color_buffer_half_float?)");
        return false;
    }
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    return true;
}

struct flux_target *flux_target_create(struct flux_engine *e, int w, int h, char *err, size_t errlen) {
    struct flux_target *t = calloc(1, sizeof *t);
    if (!t) { snprintf(err, errlen, "brak pamięci"); return NULL; }
    t->e = e; t->w = w; t->h = h; t->last_time = -1.0;
    {
        float zero[AUDIO_SPECTRUM_BINS] = {0};
        t->spec_tex = make_tex(AUDIO_SPECTRUM_BINS, 1, GL_R32F, GL_RED, GL_FLOAT, zero);
    }
    {
        static const float zero_wave[AUDIO_WAVE_N * AUDIO_CHANNELS] = {0};
        t->wave_tex = make_tex(AUDIO_WAVE_N, 1, GL_RG32F, GL_RG, GL_FLOAT, zero_wave);
    }
    if (e->up_audio[9] >= 0 || e->uu_audio[9] >= 0) {
        /* tylko spektrogram — 256 KiB na cel; R8 jest filtrowalny (LINEAR =
         * gładka interpolacja między pasmami i kolumnami), REPEAT po x robi
         * z tekstury pierścień: shader czyta (head - wiek) bez własnego modulo */
        unsigned char *zero = calloc((size_t)SPECTRO_COLS * AUDIO_SPECTRO_BINS, 1);
        if (!zero) { target_free_gl(t); free(t); snprintf(err, errlen, "brak pamięci"); return NULL; }
        t->spectro_tex = make_tex(SPECTRO_COLS, AUDIO_SPECTRO_BINS, GL_R8, GL_RED, GL_UNSIGNED_BYTE, zero);
        free(zero);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    }
    if (!e->particle) return t;

    int P = e->P;
    float *zero = calloc((size_t)P * P * 4, sizeof(float));
    if (!zero) { target_free_gl(t); free(t); snprintf(err, errlen, "brak pamięci"); return NULL; }
    for (int i = 0; i < 2; i++) {
        t->pos_tex[i] = make_tex(P, P, GL_RGBA32F, GL_RGBA, GL_FLOAT, zero);
        if (!make_fbo(t->pos_tex[i], &t->pos_fbo[i])) {
            free(zero);
            snprintf(err, errlen, "tekstura pozycji RGBA32F nie jest renderowalna (brak GL_EXT_color_buffer_float?)");
            target_free_gl(t); free(t);
            return NULL;
        }
    }
    free(zero);
    if (!alloc_accum(t->w, t->h, &t->acc_tex, &t->acc_fbo, err, errlen)) { target_free_gl(t); free(t); return NULL; }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    return t;
}

/* Zmiana rozmiaru odtwarza i CZYŚCI akumulator (pozycje są znormalizowane,
 * więc zostają — cząstki nie skaczą). Nowy akumulator powstaje PRZED
 * zwolnieniem starego: gdy sterownik odmówi (brak pamięci przy dużym
 * buforze), cel zostaje w starym rozmiarze z działającym FBO — fade/splat
 * nigdy nie rysują do okna przez acc_fbo = 0. */
bool flux_target_resize(struct flux_target *t, int w, int h, char *err, size_t errlen) {
    if (w == t->w && h == t->h) return true;
    if (!t->e->particle) { t->w = w; t->h = h; return true; }
    GLuint tex = 0, fbo = 0;
    if (!alloc_accum(w, h, &tex, &fbo, err, errlen)) { glBindFramebuffer(GL_FRAMEBUFFER, 0); return false; }
    if (t->acc_fbo) glDeleteFramebuffers(1, &t->acc_fbo);
    if (t->acc_tex) glDeleteTextures(1, &t->acc_tex);
    t->acc_tex = tex; t->acc_fbo = fbo;
    t->w = w; t->h = h;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    return true;
}

void flux_target_destroy(struct flux_target *t) {
    if (!t) return;
    target_free_gl(t);
    free(t);
}

/* ── GL: render ───────────────────────────────────────────────────────────── */

/* Uniformy audio dla programu o lokacjach `loc` (NULL audio → zera). */
static void set_audio_uniforms(const GLint loc[AUDIO_UNIFORMS], const struct audio_features *a, float strength,
                               GLuint spec_tex, GLuint wave_tex, GLuint spectro_tex, int spectro_head) {
    float v[6] = {0, 0, 0, 0, 0, 0};
    float peak = 0.0f;
    if (a && strength > 0.0f) {
        v[0] = a->level; v[1] = a->bass; v[2] = a->lowmid; v[3] = a->mid; v[4] = a->high; v[5] = a->beat;
        peak = a->wave_peak;
    }
    for (int i = 0; i < 6; i++) if (loc[i] >= 0) glUniform1f(loc[i], v[i]);
    if (loc[8] >= 0) glUniform1f(loc[8], peak);
    if (loc[6] >= 0) {
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, spec_tex);
        glUniform1i(loc[6], 2);
        glActiveTexture(GL_TEXTURE0);
    }
    if (loc[7] >= 0) {
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, wave_tex);
        glUniform1i(loc[7], 3);
        glActiveTexture(GL_TEXTURE0);
    }
    if (loc[9] >= 0) {
        glActiveTexture(GL_TEXTURE4);
        glBindTexture(GL_TEXTURE_2D, spectro_tex);
        glUniform1i(loc[9], 4);
        glActiveTexture(GL_TEXTURE0);
    }
    if (loc[10] >= 0) glUniform1f(loc[10], (float)spectro_head);
}

/* Spektrogram: kolumny przybywają w tempie hopu analizy (AUDIO_RATE/AUDIO_HOP
 * = 50/s) według zegara REALNEGO — oś czasu jest prawdziwa niezależnie od fps,
 * a w ciszy/bez serwera obraz dalej przewija się pustą kolumną (jak prawdziwy
 * spektrogram, który nie zatrzymuje się, gdy nic nie gra). Po pauzie
 * (uśpiony ekran) nie dopisujemy zaległych sekund — limit kolumn na klatkę. */
static void spectro_push(struct flux_target *t, double dt_real, const struct audio_features *audio, float strength) {
    const double cols_per_s = (double)AUDIO_RATE / AUDIO_HOP;
    t->spectro_acc += dt_real * cols_per_s;
    int n = (int)floor(t->spectro_acc);
    if (n <= 0) return;
    if (n > 64) { n = 64; t->spectro_acc = 0; } else t->spectro_acc -= n;
    unsigned char col[AUDIO_SPECTRO_BINS] = {0};
    if (audio && strength > 0.0f)
        for (int i = 0; i < AUDIO_SPECTRO_BINS; i++) {
            float v = audio->spectro[i] * strength;
            col[i] = (unsigned char)(v <= 0.0f ? 0 : (v >= 1.0f ? 255 : (int)(v * 255.0f + 0.5f)));
        }
    glActiveTexture(GL_TEXTURE4);
    glBindTexture(GL_TEXTURE_2D, t->spectro_tex);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    for (int k = 0; k < n; k++) {
        t->spectro_head = (t->spectro_head + 1) % SPECTRO_COLS;
        glTexSubImage2D(GL_TEXTURE_2D, 0, t->spectro_head, 0, 1, AUDIO_SPECTRO_BINS, GL_RED, GL_UNSIGNED_BYTE, col);
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glActiveTexture(GL_TEXTURE0);
}

static void sim_step(struct flux_engine *e, struct flux_target *t, double step_time, float detail,
                     float inc_eff, const struct audio_features *audio, float strength) {
    const struct flux_params *p = &e->params;
    float aspect = (float)t->w / (float)t->h;

    /* a. krok cząstek → druga tekstura pozycji */
    glBindFramebuffer(GL_FRAMEBUFFER, t->pos_fbo[1 - t->src]);
    glViewport(0, 0, e->P, e->P);
    glDisable(GL_BLEND);
    glUseProgram(e->prog_update);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, t->pos_tex[t->src]);
    if (e->uu_pos        >= 0) glUniform1i(e->uu_pos, 0);
    if (e->uu_time       >= 0) glUniform1f(e->uu_time, (float)fmod(step_time, FLUX_TIME_PERIOD));
    if (e->uu_dt         >= 0) glUniform1f(e->uu_dt, 1.0f / p->rate);
    if (e->uu_detail     >= 0) glUniform1f(e->uu_detail, detail);
    if (e->uu_resolution >= 0) glUniform2f(e->uu_resolution, (float)t->w, (float)t->h);
    if (e->uu_aspect     >= 0) glUniform1f(e->uu_aspect, aspect);
    if (e->uu_seed       >= 0) glUniform1i(e->uu_seed, p->seed);
    if (e->uu_life       >= 0) glUniform1f(e->uu_life, p->life * p->rate);
    if (e->uu_accum      >= 0) {
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, t->acc_tex);
        glUniform1i(e->uu_accum, 1);
        glActiveTexture(GL_TEXTURE0);
    }
    set_audio_uniforms(e->uu_audio, audio, strength, t->spec_tex, t->wave_tex, t->spectro_tex, t->spectro_head);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    t->src = 1 - t->src;

    /* b. ślady → akumulator */
    int total = e->P * e->P;
    int active = (int)((0.35f + 0.65f * detail) * (float)p->particles);
    if (active > total) active = total;
    if (active < 1) active = 1;
    glBindFramebuffer(GL_FRAMEBUFFER, t->acc_fbo);
    glViewport(0, 0, t->w, t->h);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE);
    glUseProgram(e->prog_splat);
    glBindTexture(GL_TEXTURE_2D, t->pos_tex[t->src]);
    if (e->us_pos    >= 0) glUniform1i(e->us_pos, 0);
    if (e->us_P      >= 0) glUniform1i(e->us_P, e->P);
    if (e->us_active >= 0) glUniform1i(e->us_active, active);
    if (e->us_splat  >= 0) glUniform1i(e->us_splat, p->splat);
    if (e->us_scale  >= 0) glUniform1f(e->us_scale, p->scale);
    if (e->us_aspect >= 0) glUniform1f(e->us_aspect, aspect);
    if (e->us_warm   >= 0) glUniform1f(e->us_warm, (float)p->warm);
    if (e->us_inc    >= 0) glUniform1f(e->us_inc, inc_eff);
    glDrawArrays(GL_POINTS, 0, total);
    glDisable(GL_BLEND);
}

static void fade(struct flux_engine *e, struct flux_target *t, double dt) {
    float keep = (float)exp(-dt / e->params.life);
    glBindFramebuffer(GL_FRAMEBUFFER, t->acc_fbo);
    glViewport(0, 0, t->w, t->h);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ZERO, GL_SRC_COLOR);
    glUseProgram(e->prog_fade);
    if (e->uf_keep >= 0) glUniform1f(e->uf_keep, keep);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glDisable(GL_BLEND);
}

/* Dwie domeny czasu: `dt_real` z zegara steruje ZANIKIEM (ślady gasną w
 * sekundach realnych — wygląd niezależny od fps i od muzyki), `dt_sim` =
 * dt_real · warp steruje liczbą kroków i czasem animacji (muzyka przyspiesza
 * ruch). Bez audio warp = 1 i obie domeny są tożsame. */
static void simulate(struct flux_engine *e, struct flux_target *t, double anim_time, double dt_real,
                     double dt_sim, float detail, const struct audio_features *audio, float strength) {
    const struct flux_params *p = &e->params;
    if (dt_real > 0) fade(e, t, dt_real);
    t->step_acc += dt_sim * p->rate;
    int steps = (int)floor(t->step_acc);
    int cap = flux_step_cap(p, audio ? strength : 0.0f);
    if (steps > cap) { steps = cap; t->step_acc = 0; }   /* po pauzie nie doganiamy */
    else t->step_acc -= steps;
    double step_dt = 1.0 / p->rate;
    float inc_eff = p->inc;
    if (audio && strength > 0.0f) inc_eff *= 1.0f + p->audio_glow * strength * audio->bass;
    for (int i = 0; i < steps; i++)
        sim_step(e, t, anim_time - dt_sim + (i + 1) * step_dt, detail, inc_eff, audio, strength);
}

void flux_engine_render(struct flux_engine *e, struct flux_target *t, GLuint dest_fbo,
                        double time, const struct palette *pal, float detail,
                        const struct audio_features *audio, float audio_strength, bool warmup_once) {
    glBindVertexArray(e->vao);
    const struct flux_params *p = &e->params;

    /* czas animacji = zegar + offset narastający tylko przy warpie > 1;
     * bez muzyki offset = 0 i `time` idzie do shaderów bit w bit jak dotąd */
    double dt_real = t->last_time < 0 ? 0.0 : time - t->last_time;
    if (dt_real < 0) dt_real = 0;
    double warp = flux_warp(p, audio, audio_strength);
    double dt_sim = dt_real * warp;
    t->warp_offset += dt_sim - dt_real;
    double anim_time = time + t->warp_offset;

    /* widmo do tekstury (jednostka 2) — tylko gdy jakiś shader go używa */
    if (audio && audio_strength > 0.0f && (e->up_audio[6] >= 0 || e->uu_audio[6] >= 0)) {
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, t->spec_tex);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, AUDIO_SPECTRUM_BINS, 1, GL_RED, GL_FLOAT, audio->spectrum);
        glActiveTexture(GL_TEXTURE0);
    }
    /* przebieg L/R do tekstury (jednostka 3) — tylko dla shaderów oscyloskopowych */
    if (audio && audio_strength > 0.0f && (e->up_audio[7] >= 0 || e->uu_audio[7] >= 0)) {
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, t->wave_tex);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, AUDIO_WAVE_N, 1, GL_RG, GL_FLOAT, audio->wave);
        glActiveTexture(GL_TEXTURE0);
    }
    /* spektrogram (jednostka 4) — tylko gdy shader go deklaruje; przewija się
     * zegarem realnym także bez sygnału */
    if (t->spectro_tex) spectro_push(t, dt_real, audio, audio_strength);

    if (e->particle) {
        if (warmup_once && !t->warmed) {
            int n = (int)(p->warmup * p->rate);
            double step_dt = 1.0 / p->rate;
            for (int i = 0; i < n; i++)
                simulate(e, t, time - (n - i) * step_dt, step_dt, step_dt, detail, NULL, 0.0f);
            t->warmed = true;
            dt_real = dt_sim = 0.0;
        }
        simulate(e, t, anim_time, dt_real, dt_sim, detail, audio, audio_strength);
    }
    t->last_time = time;

    glBindFramebuffer(GL_FRAMEBUFFER, dest_fbo);
    glViewport(0, 0, t->w, t->h);
    glDisable(GL_BLEND);
    glUseProgram(e->prog_present);
    if (e->particle) {
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, t->acc_tex);
        if (e->u_accum >= 0) glUniform1i(e->u_accum, 0);
        /* Puls basu w PRZEBIEGU FINALNYM: mnożnik `gain` działa natychmiast na
         * cały obraz. Przez sam `inc` puls tonął w akumulatorze — ślady sumują
         * się przez `life` sekund, a uderzenie trwa 0.2 s (zmierzone: korelacja
         * bas↔jasność ≈ 0 przy samym inc). */
        float gain_eff = p->gain;
        if (audio && audio_strength > 0.0f) gain_eff *= 1.0f + 1.5f * p->audio_glow * audio_strength * audio->bass;
        if (e->u_gain  >= 0) glUniform1f(e->u_gain, gain_eff);
    }
    set_audio_uniforms(e->up_audio, audio, audio_strength, t->spec_tex, t->wave_tex, t->spectro_tex, t->spectro_head);
    if (e->u_resolution >= 0) glUniform2f(e->u_resolution, (float)t->w, (float)t->h);
    if (e->u_time       >= 0) glUniform1f(e->u_time, (float)fmod(anim_time, FLUX_TIME_PERIOD));
    if (e->u_bg         >= 0) glUniform3fv(e->u_bg, 1, pal->bg);
    if (e->u_ink        >= 0) glUniform3fv(e->u_ink, 1, pal->ink);
    if (e->u_accent     >= 0) glUniform3fv(e->u_accent, 1, pal->accent);
    if (e->u_detail     >= 0) glUniform1f(e->u_detail, detail);
    glDrawArrays(GL_TRIANGLES, 0, 3);
}
