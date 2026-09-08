/*
 * archenemy — flux-wall: „dither-vortex” — wiry, krok cząstki.
 *
 * przepływ bezźródłowy — prędkość to obrócony gradient potencjału fBm (curl noise), więc cząstki krążą w wirach bez źródeł i ścieków.
 *
 * Curl noise: potencjał ψ = fbm, prędkość v = (∂ψ/∂y, −∂ψ/∂x) — dywergencja zero, więc cząstki nie zbiegają się ani nie rozbiegają, tylko krążą. Gradient z różnic skończonych (ε = 0.01). Pole dryfuje 0.03 jednostki/s. Szum h2/fbm 1:1 z generatora.
 *
 * Wybór właściciela 2026-09-08 z arkusza sześciu kandydatów („te które zrobiłeś są
 * przepiękne"). Kontrakt kroku cząstek: engine.h (prelude daje pos/time/dt/detail/
 * resolution/aspect/seed/life_steps/accum i szum h2/vnoise/fbm).
 */
#pragma flux particles 20800
#pragma flux life 4.3
#pragma flux rate 60
#pragma flux inc 0.007
#pragma flux gain 14
#pragma flux splat 0
#pragma flux seed 2032

const float FIELD_SCALE = 3.5;
const float STEP        = 1.35 / 960.0;
const float DRIFT       = 0.03;

float psi(vec2 q, int oct) { return fbm(q, oct, seed); }

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    vec2  p   = s.xy;
    float age = s.z, gen = s.w;
    bool respawn = age < 0.5 || age >= life_steps
                || p.x < -0.02 || p.x > 1.02 || p.y < -0.02 || p.y > 1.02;
    if (respawn) {
        float g = gen + 1.0; int k = int(g) * 7;
        p = vec2(h2(idx.x, idx.y, seed + k), h2(idx.x + 911, idx.y + 7, seed + k));
        o = vec4(p, 1.0, g);
        return;
    }
    int   octaves = int(clamp(floor(1.0 + detail * 3.0 + 0.001), 1.0, 4.0));
    vec2  q = vec2(p.x, p.y / aspect) * FIELD_SCALE + vec2(DRIFT * time, -DRIFT * time * 0.7);
    float e = 0.01;
    /* prędkość = obrócony gradient potencjału → dywergencja zero → wiry bez źródeł i ścieków */
    vec2 g = vec2(psi(q + vec2(e, 0.0), octaves) - psi(q - vec2(e, 0.0), octaves),
                  psi(q + vec2(0.0, e), octaves) - psi(q - vec2(0.0, e), octaves)) / (2.0 * e);
    vec2 v = normalize(vec2(g.y, -g.x) + 1e-6);
    p += v * STEP * vec2(1.0, aspect);
    o = vec4(p, age + 1.0, gen);
}
