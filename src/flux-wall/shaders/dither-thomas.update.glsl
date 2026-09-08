/*
 * archenemy — flux-wall: „dither-thomas” — atraktor Thomasa, krok cząstki.
 *
 * ciągły (równanie różniczkowe, b = 0.208186, RK2) — kropki naprawdę płyną po splecionych pętlach.
 *
 * Atraktor Thomasa — układ cyklicznie symetryczny dx = sin y − b·x (i cyklicznie), b = 0.208186. Stan 3D mieści się w kontrakcie: xy = rzut (X, Z) na ekran, z = wiek, w = trzecia współrzędna Y; sól odrodzenia z int(time·7), bo nie ma miejsca na numer wcielenia. Całkowanie RK2 (punkt środkowy) krokiem 0.06 na krok symulacji — cząstki płyną ciągle, kształt (zbiór graniczny) stoi.
 *
 * Wybór właściciela 2026-09-08 z arkusza sześciu kandydatów („te które zrobiłeś są
 * przepiękne"). Kontrakt kroku cząstek: engine.h (prelude daje pos/time/dt/detail/
 * resolution/aspect/seed/life_steps/accum i szum h2/vnoise/fbm).
 */
#pragma flux particles 40000
#pragma flux life 10
#pragma flux rate 60
#pragma flux inc 0.0016
#pragma flux gain 20
#pragma flux splat 1
#pragma flux scale 0.11
#pragma flux warm 60
#pragma flux seed 2028

const float B = 0.208186;
const float H = 0.06;      /* krok całkowania na jeden krok symulacji */

vec3 field(vec3 v) { return vec3(sin(v.y) - B * v.x, sin(v.z) - B * v.y, sin(v.x) - B * v.z); }

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    /* stan: x = X, y = Z (rzut na ekran), z = wiek, w = Y (trzecia współrzędna) */
    vec3  v   = vec3(s.x, s.w, s.y);
    float age = s.z;
    if (age < 0.5 || age >= life_steps) {
        int k = int(time * 7.0) + 1;
        v = vec3(h2(idx.x, idx.y, seed + k), h2(idx.x + 533, idx.y + 17, seed + k),
                 h2(idx.x + 91, idx.y + 877, seed + k)) * 6.0 - 3.0;
        o = vec4(v.x, v.z, 1.0, v.y);
        return;
    }
    vec3 k1 = field(v);
    vec3 k2 = field(v + 0.5 * H * k1);
    v += H * k2;
    o = vec4(v.x, v.z, age + 1.0, v.y);
}
