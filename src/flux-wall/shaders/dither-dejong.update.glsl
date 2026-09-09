/*
 * archenemy — flux-wall: „dither-dejong” — atraktor de Jonga, krok cząstki.
 *
 * mapa (a 1.4, b −2.3, c 2.4, d −2.1) — kształt stoi, obiega go fala światła jak w dither-attractor.
 *
 * Mapa Petera de Jonga: x′ = sin(a·y) − cos(b·x), y′ = sin(c·x) − cos(d·y). Kształt stoi (parametry stałe), 20 kroków rozbiegu bez śladu; ruch daje fala jasności w .frag — ten sam mechanizm co dither-attractor.
 *
 * Wybór właściciela 2026-09-08 z arkusza sześciu kandydatów („te które zrobiłeś są
 * przepiękne"). Kontrakt kroku cząstek: engine.h (prelude daje pos/time/dt/detail/
 * resolution/aspect/seed/life_steps/accum i szum h2/vnoise/fbm).
 */
#pragma flux particles 40000
#pragma flux life 4.0
#pragma flux rate 60
#pragma flux inc 0.005
#pragma flux gain 20
#pragma flux splat 1
#pragma flux scale 0.21
#pragma flux warm 20
#pragma flux seed 2031

const vec4 ABCD = vec4(1.4, -2.3, 2.4, -2.1);

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    vec2  q   = s.xy;
    float age = s.z, gen = s.w;
    if (age < 0.5 || age >= life_steps) {
        float g = gen + 1.0; int k = int(g) * 13;
        q = vec2(h2(idx.x, idx.y, seed + k), h2(idx.x + 533, idx.y + 17, seed + k)) * 4.0 - 2.0;
        o = vec4(q, 1.0, g);
        return;
    }
    vec2 n = vec2(sin(ABCD.x * q.y) - cos(ABCD.y * q.x),
                  sin(ABCD.z * q.x) - cos(ABCD.w * q.y));
    o = vec4(n, age + 1.0, gen);
}
