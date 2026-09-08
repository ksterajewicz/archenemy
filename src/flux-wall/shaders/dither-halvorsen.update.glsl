/*
 * archenemy — flux-wall: „dither-halvorsen” — atraktor Halvorsena, krok cząstki.
 *
 * ciągły (a = 1.89, RK2) — trzy splecione płaty.
 *
 * Atraktor Halvorsena: dx = −a·x − 4y − 4z − y² (i cyklicznie), a = 1.89. Rzut (X, Y) przesunięty o +2.5 (atraktor leży w ujemnej ćwiartce); w = Z. RK2 krokiem 0.012. Cząstka, która uciekła (|v| > 40), odradza się.
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
#pragma flux scale 0.042
#pragma flux warm 60
#pragma flux seed 2029

const float A = 1.89;
const float H = 0.012;

vec3 field(vec3 v) {
    return vec3(-A * v.x - 4.0 * v.y - 4.0 * v.z - v.y * v.y,
                -A * v.y - 4.0 * v.z - 4.0 * v.x - v.z * v.z,
                -A * v.z - 4.0 * v.x - 4.0 * v.y - v.x * v.x);
}

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    /* xy = rzut (x + 2.5, y + 2.5) — atraktor leży w ujemnej ćwiartce, przesuwamy do środka */
    vec3  v   = vec3(s.x - 2.5, s.y - 2.5, s.w);
    float age = s.z;
    if (age < 0.5 || age >= life_steps || any(greaterThan(abs(v), vec3(40.0)))) {
        int k = int(time * 7.0) + 1;
        v = vec3(h2(idx.x, idx.y, seed + k), h2(idx.x + 533, idx.y + 17, seed + k),
                 h2(idx.x + 91, idx.y + 877, seed + k)) * 4.0 - 4.0;
        o = vec4(v.x + 2.5, v.y + 2.5, 1.0, v.z);
        return;
    }
    vec3 k1 = field(v);
    vec3 k2 = field(v + 0.5 * H * k1);
    v += H * k2;
    o = vec4(v.x + 2.5, v.y + 2.5, age + 1.0, v.z);
}
