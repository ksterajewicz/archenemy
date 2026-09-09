/*
 * archenemy — flux-wall: „dither-attractor” — atraktor Clifforda, krok cząstki.
 *
 * Ta sama forma, którą generator PNG (gen_dither_flux_wallpaper.py, `engine_attractor`)
 * maluje na tapecie statycznej `atraktor`: mapa Clifforda a,b,c,d = −1.7, 1.3, −0.1, −1.21,
 * kadr poziomy (generator liczy na płótnie pionowym i transponuje — tu to samo mapowanie:
 * ekran = (0.5 − Y·scale/aspekt, 0.5 − X·scale), scale = 0.304 wysokości).
 *
 * Decyzja właściciela 2026-09-08: KSZTAŁT MA STAĆ. Dlatego parametry mapy są stałe,
 * a ruch daje przebieg finalny (dither-attractor.frag): po nieruchomych śladach obiega
 * spiralna fala jasności. Cząstka: 20 kroków rozbiegu bez śladu (`warm`), potem każda
 * iteracja ląduje na atraktorze i zostawia punkt; po `life` sekundach odradza się losowo.
 *
 * Kontrakt (engine.h): stan xy = (−Y, −X) w płaszczyźnie mapy, z = wiek, w = wcielenie.
 */
#pragma flux particles 40000
#pragma flux life 4.0
#pragma flux rate 60
#pragma flux inc 0.022
#pragma flux gain 20
#pragma flux splat 1
#pragma flux scale 0.304
#pragma flux warm 20
#pragma flux seed 2028

const vec4 ABCD = vec4(-1.7, 1.3, -0.1, -1.21);

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    vec2  q   = vec2(-s.y, -s.x);          /* (X, Y) mapy z zapisanego (−Y, −X) */
    float age = s.z;
    float gen = s.w;

    if (age < 0.5 || age >= life_steps) {
        float g = gen + 1.0;
        int   k = int(g) * 13;
        q = vec2(h2(idx.x, idx.y, seed + k), h2(idx.x + 533, idx.y + 17, seed + k)) * 4.0 - 2.0;
        o = vec4(-q.y, -q.x, 1.0, g);
        return;
    }

    vec2 n = vec2(sin(ABCD.x * q.y) + ABCD.z * cos(ABCD.x * q.x),
                  sin(ABCD.y * q.x) + ABCD.w * cos(ABCD.y * q.y));
    o = vec4(-n.y, -n.x, age + 1.0, gen);
}
