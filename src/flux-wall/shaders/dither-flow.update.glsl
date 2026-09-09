/*
 * archenemy — flux-wall: „dither-flow” — pole przepływu, krok cząstki.
 *
 * Ta sama forma, którą generator PNG (scripts/wallpapers/gen_dither_flux_wallpaper.py,
 * silnik `engine_flow`) maluje na tapecie statycznej `przeplyw`: cząstki wędrują
 * po polu kątów z fBm i zostawiają smugi. Tu żyją naprawdę — każda klatka to jeden
 * krok, ślady gasną w akumulatorze (engine.c), a pole POWOLI DRYFUJE, więc linie
 * prądu przebudowują się bez końca. Szum (h2/vnoise/fbm) jest 1:1 z generatora,
 * ziarno też (2026 + 1), więc bez dryfu byłoby to dokładnie pole z tapety.
 *
 * Kontrakt (engine.h): prelude daje `pos`, `time`, `dt`, `detail`, `resolution`,
 * `aspect`, `seed`, `life_steps`, `out vec4 o` i funkcje szumu. Stan cząstki:
 * xy = pozycja w 0..1 ekranu, z = wiek w krokach, w = numer wcielenia.
 */
#pragma flux particles 20800
#pragma flux life 4.3
#pragma flux rate 60
#pragma flux inc 0.006
#pragma flux gain 14
#pragma flux splat 0
#pragma flux seed 2027

/* Stałe z generatora, przeliczone na ekran 0..1:
 *   siatka szumu: 26 komórek × (4 px kroku siatki) = 104 px na jednostkę szumu
 *   przy szerokości odniesienia 960 → 960/104 = 9.23 jednostek na SZEROKOŚĆ;
 *   krok cząstki: 1.35 px przy 960 px → 1.35/960 szerokości. */
const float FIELD_SCALE = 9.23;
const float STEP        = 1.35 / 960.0;
const float DRIFT       = 0.02;       /* jednostek szumu na sekundę: 0.10 rozmywało linie w szerokie pasma, 0.02 trzyma je cienkie jak na tapecie, a rysunek i tak przebudowuje się w ~3 s */

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    vec2  p   = s.xy;
    float age = s.z;
    float gen = s.w;

    bool respawn = age < 0.5 || age >= life_steps
                || p.x < -0.02 || p.x > 1.02 || p.y < -0.02 || p.y > 1.02;
    if (respawn) {
        float g = gen + 1.0;
        int   k = int(g) * 7;
        p = vec2(h2(idx.x, idx.y, seed + k), h2(idx.x + 911, idx.y + 7, seed + k));
        o = vec4(p, 1.0, g);
        return;
    }

    /* Mniej baterii = mniej oktaw (1–4) i wolniejszy dryf — jak w dither-flux. */
    int   octaves = int(clamp(floor(1.0 + detail * 3.0 + 0.001), 1.0, 4.0));
    float drift   = DRIFT * (0.4 + 0.6 * detail);

    /* Współrzędne szumu w jednostkach SZEROKOŚCI (komórki kwadratowe w pikselach). */
    vec2  q = vec2(p.x, p.y / aspect) * FIELD_SCALE + vec2(drift * time, drift * time * 0.6);
    float a = fbm(q, octaves, seed) * 6.2831853 * 2.0;
    p += vec2(cos(a), sin(a)) * STEP * vec2(1.0, aspect);

    o = vec4(p, age + 1.0, gen);
}
