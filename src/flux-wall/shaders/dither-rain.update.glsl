/*
 * archenemy — flux-wall: „dither-rain” — deszcz, krok cząstki.
 *
 * krople spadają (0.55 ekranu/s) z tempem per kropla, wiatr z fBm je odchyla, smugi gasną w akumulatorze — Milford Sound w ulewie, skąd paleta rice'a.
 *
 * Deszcz: start nad górną krawędzią (rozrzut w czasie przez wysokość 1.0–1.3), spadanie 0.55 ekranu/s ± 20% per kropla, wiatr z wolnego pola fBm. `rate 240` (4 kroki na klatkę), bo przy 60 krokach/s smuga była przerywana co ~5 px; `life 1.6 s` = jedna droga przez ekran. 1200 kropli — przy 5000 kadr był jednolitą siatką kresek.
 *
 * Wybór właściciela 2026-09-08 z arkusza sześciu kandydatów („te które zrobiłeś są
 * przepiękne"). Kontrakt kroku cząstek: engine.h (prelude daje pos/time/dt/detail/
 * resolution/aspect/seed/life_steps/accum i szum h2/vnoise/fbm).
 */
#pragma flux particles 1200
#pragma flux life 1.6
#pragma flux rate 240
#pragma flux inc 0.03
#pragma flux gain 14
#pragma flux splat 0
#pragma flux seed 2033

const float FALL  = 0.55 / 240.0;     /* wysokości ekranu na krok (0.55 ekranu/s) */
const float WIND  = 0.12;            /* maksymalne odchylenie poziome (części FALL) */

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    vec2  p   = s.xy;
    float age = s.z, gen = s.w;
    if (age < 0.5 || age >= life_steps || p.y < -0.02) {
        float g = gen + 1.0; int k = int(g) * 7;
        /* start nad górną krawędzią, rozrzucony w czasie: część kropli zaczyna wyżej */
        p = vec2(h2(idx.x, idx.y, seed + k), 1.0 + 0.3 * h2(idx.x + 911, idx.y + 7, seed + k));
        o = vec4(p, 1.0, g);
        return;
    }
    /* wiatr: wolne pole fBm w skali kadru, plus lekki dryf w czasie */
    float w = (fbm(vec2(p.x * 2.0 + time * 0.05, p.y * 1.5 + time * 0.03), 3, seed) - 0.5) * 2.0;
    float speed = FALL * (0.8 + 0.4 * h2(idx.x + 3, idx.y + 5, seed));   /* każda kropla ma swoje tempo */
    p += vec2(w * WIND * speed / aspect, -speed);
    o = vec4(p, age + 1.0, gen);
}
