/*
 * archenemy — flux-wall: „dither-aizawa” — atraktor Aizawy, krok cząstki.
 *
 * ciągły (RK2) — kula z rurą przez środek.
 *
 * Atraktor Aizawy (a 0.95, b 0.7, c 0.6, d 3.5, e 0.25, f 0.1). Rzut (X, Z − 0.5); w = Y. RK2 krokiem 0.012. Rzut boczny pokazuje głównie pionową „rurę" — inny rzut do rozważenia, właściciel przyjął ten (2026-09-08).
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
#pragma flux scale 0.26
#pragma flux warm 60
#pragma flux seed 2030

const float A = 0.95, B = 0.7, C = 0.6, D = 3.5, E = 0.25, F = 0.1;
const float H = 0.012;

vec3 field(vec3 v) {
    float x = v.x, y = v.y, z = v.z;
    return vec3((z - B) * x - D * y,
                D * x + (z - B) * y,
                C + A * z - z * z * z / 3.0 - (x * x + y * y) * (1.0 + E * z) + F * z * x * x * x);
}

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    /* xy = rzut (x, z − 0.5); w = y */
    vec3  v   = vec3(s.x, s.w, s.y + 0.5);
    float age = s.z;
    if (age < 0.5 || age >= life_steps || any(greaterThan(abs(v), vec3(10.0)))) {
        int k = int(time * 7.0) + 1;
        v = vec3(h2(idx.x, idx.y, seed + k), h2(idx.x + 533, idx.y + 17, seed + k),
                 h2(idx.x + 91, idx.y + 877, seed + k)) * 2.0 - 1.0;
        o = vec4(v.x, v.z - 0.5, 1.0, v.y);
        return;
    }
    vec3 k1 = field(v);
    vec3 k2 = field(v + 0.5 * H * k1);
    v += H * k2;
    o = vec4(v.x, v.z - 0.5, age + 1.0, v.y);
}
