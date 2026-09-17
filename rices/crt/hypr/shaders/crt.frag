#version 300 es
// archenemy - crt.frag (rice crt)
// Shader ekranowy Hyprlanda (decoration.screen_shader): obraz kineskopu.
//   1. scanlines — co 3 px fizyczny ciemniejsza linia (rytm rastra lampy),
//   2. maska apertury — subtelne przyciemnienie co trzeciej kolumny, jak
//      szczeliny maski cieniowej; bardzo słabe, żeby tekst nie łapał tęczy,
//   3. winieta — rogi ciemniejsze, środek pełnej jasności (lampa świeci
//      najmocniej w osi),
//   4. lekkie podniesienie czerni ku cyjanowi fosforu (#36D2D8)
//      w najciemniejszych tonach — czerń kineskopu nigdy nie jest czarna.
//
// Kontrakt Hyprlanda v0.56 (src/render/OpenGL.cpp::applyScreenShader +
// src/render/shaders/glsl/tex300.vert): #version 300 es, wejście v_texcoord
// (0..1), tekstura `tex`, wyjście fragColor; gl_FragCoord = piksele fizyczne
// (dostępne też uniformy wl_output, fullSize — tu niepotrzebne).
// CELOWO bez uniformu `time` i `pointer_*`: ich użycie wymaga wyłączenia
// damage trackingu („massively increases GPU utilization” — ostrzeżenie
// samego Hyprlanda). Shader statyczny = koszt jednego przebiegu na
// przerysowanym obszarze. Zasada „nic, co pogorszyłoby grafikę" zachowana.
//
// Kolor wyjściowy jest premultiplied (Hyprland blenduje GL_ONE /
// GL_ONE_MINUS_SRC_ALPHA) — skalujemy RGB, alfę zostawiamy.

precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;

layout(location = 0) out vec4 fragColor;

// Siła efektów — jedno miejsce do strojenia po live-teście.
const float SCANLINE_DEPTH = 0.14;  // 0 = brak linii, 1 = czarne linie
const float SCANLINE_PERIOD = 3.0;  // co ile pikseli fizycznych ciemna linia
const float MASK_DEPTH = 0.05;      // maska apertury (kolumny)
const float VIGNETTE = 0.22;        // przyciemnienie rogów
const float PHOSPHOR_LIFT = 0.018;  // podniesienie czerni ku cyjanowi

const vec3 PHOSPHOR = vec3(0.212, 0.824, 0.847); // #36D2D8

void main() {
    vec4 c = texture(tex, v_texcoord);

    // 1. scanlines — gładki profil (cos), nie schodek: brak aliasingu przy
    //    skalowaniu ułamkowym, linie wyglądają jak rozmyty ślad wiązki.
    float row = gl_FragCoord.y;
    float scan = 0.5 + 0.5 * cos(row * 6.28318530718 / SCANLINE_PERIOD);
    float scanFactor = 1.0 - SCANLINE_DEPTH * scan;

    // 2. maska apertury — co trzecia kolumna odrobinę ciemniejsza.
    float col = mod(floor(gl_FragCoord.x), 3.0);
    float maskFactor = 1.0 - MASK_DEPTH * step(2.0, col);

    // 3. winieta — odległość od środka w przestrzeni 0..1, kwadratowa.
    vec2 uv = v_texcoord * 2.0 - 1.0;
    float r2 = dot(uv, uv) * 0.5;               // 0 w środku, 1 w rogu
    float vignetteFactor = 1.0 - VIGNETTE * r2 * r2;

    vec3 rgb = c.rgb * scanFactor * maskFactor * vignetteFactor;

    // 4. podniesienie czerni: tylko tam, gdzie obraz jest ciemny (waga
    //    maleje z jasnością), w kolorze fosforu — pełnowartościowe kolory
    //    okien zostają nietknięte.
    float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    rgb += PHOSPHOR * PHOSPHOR_LIFT * (1.0 - clamp(luma * 4.0, 0.0, 1.0)) * c.a;

    fragColor = vec4(rgb, c.a);
}
