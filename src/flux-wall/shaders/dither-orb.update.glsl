/*
 * archenemy — flux-wall: „dither-orb” — wizualizer w stylu kulki NCS, krok cząstki.
 *
 * Cząstki rodzą się na obwodzie tarczy (promień oddycha z basem, jak w .frag)
 * i lecą promieniście na zewnątrz; prędkość rośnie z poziomem dźwięku, a
 * uderzenie (audio_beat) wyrzuca dodatkową falę cząstek. Ślady gasną w
 * akumulatorze — w tle tarczy powstaje rozchodzący się pył. W ciszy: powolny,
 * rzadki dryf na zewnątrz (obraz żyje, ale nie krzyczy).
 *
 * Stan: xy = pozycja w 0..1 ekranu, z = wiek, w = wcielenie (patrz engine.h).
 */
#pragma flux audio 1
#pragma flux particles 6000
#pragma flux life 2.5
#pragma flux rate 60
#pragma flux inc 0.012
#pragma flux gain 12
#pragma flux splat 0
#pragma flux seed 2040
#pragma flux audio_tempo 0.6
#pragma flux audio_glow 0.8

const float ORB_R   = 0.20;      /* promień tarczy w jednostkach wysokości/2 (jak c w .frag) */
const float ORB_BR  = 0.22;      /* przyrost promienia przy pełnym basie */

void main() {
    ivec2 idx = ivec2(gl_FragCoord.xy);
    vec4  s   = texelFetch(pos, idx, 0);
    vec2  p   = s.xy;
    float age = s.z, gen = s.w;

    float R = ORB_R * (1.0 + ORB_BR * audio_bass);
    /* Uderzenie: część cząstek odradza się od razu → fala pyłu od tarczy. */
    bool burst = audio_beat > 0.6 && h2(idx.x + 77, idx.y + int(gen), seed) < 0.35 && age > 20.0;
    bool respawn = age < 0.5 || age >= life_steps || burst
                || p.x < -0.02 || p.x > 1.02 || p.y < -0.02 || p.y > 1.02;
    if (respawn) {
        float g = gen + 1.0;
        int   k = int(g) * 7;
        float a = h2(idx.x, idx.y, seed + k) * 6.2831853;
        vec2  dir = vec2(cos(a), sin(a));
        /* z obwodu tarczy, we współrzędnych ekranu (c → p: p = 0.5 + c·0.5·(1/aspekt, 1)) */
        p = vec2(0.5) + dir * R * 0.5 * vec2(1.0 / aspect, 1.0);
        o = vec4(p, 1.0, g);
        return;
    }
    /* ruch promienisty: kierunek z bieżącej pozycji względem środka */
    vec2  c   = (p - 0.5) * vec2(aspect, 1.0) * 2.0;
    vec2  dir = normalize(c + 1e-6);
    float speed = (0.06 + 0.55 * audio_level + 0.9 * audio_beat) * dt;   /* jednostek c na sekundę */
    c += dir * speed;
    p = vec2(0.5) + c * 0.5 * vec2(1.0 / aspect, 1.0);
    o = vec4(p, age + 1.0, gen);
}
