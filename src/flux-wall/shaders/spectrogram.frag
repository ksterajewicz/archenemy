#version 300 es
/*
 * archenemy — flux-wall: „spectrogram” — zwykły spektrogram (wizualizacja muzyki).
 *
 * Klasyczny obraz jak w Audacity/Spek: czas biegnie w lewo (prawa krawędź =
 * teraz), częstotliwość rośnie ku górze (skala log, 40 Hz – 16 kHz),
 * jasność = poziom w dB względem najgłośniejszego pasma z ostatnich ~2 s
 * (zakres 60 dB). Historię kolumn trzyma silnik (tekstura audio_spectrogram,
 * 50 kolumn/s zegarem realnym — oś czasu jest prawdziwa i przewija się także
 * w ciszy). Bez rastra, bez podziałki, bez efektów: paleta rice'a jako
 * gradient tło → atrament → akcent. Jednoprzebiegowy, jeden odczyt tekstury.
 *
 * Uniformy: kontrakt flux-wall + audio_spectrogram/_head (engine.h);
 * `#pragma flux audio 1`.
 */
#pragma flux audio 1
precision highp float;
precision highp sampler2D;

uniform vec2      resolution;
uniform vec3      palette_bg;
uniform vec3      palette_ink;
uniform vec3      palette_accent;
uniform sampler2D audio_spectrogram;
uniform float     audio_spectrogram_head;

out vec4 fragColor;

const float PX_PER_COL = 2.0;    /* 50 kolumn/s × 2 px = 100 px/s; 2560 px = ~26 s historii */
const float MID        = 0.55;   /* poziom (0..1), przy którym gradient przechodzi z atramentu w akcent */

void main() {
    vec2 px = gl_FragCoord.xy;
    float cols = float(textureSize(audio_spectrogram, 0).x);
    float age  = (resolution.x - px.x) / PX_PER_COL;              /* kolumn wstecz od „teraz” */
    float u    = (audio_spectrogram_head + 0.5 - age) / cols;    /* REPEAT: ujemne zawija pierścień */
    float v    = px.y / resolution.y;                            /* 0 = 40 Hz (dół), 1 = 16 kHz (góra) */
    float s    = texture(audio_spectrogram, vec2(u, v)).r;

    vec3 col = mix(palette_bg, palette_ink, smoothstep(0.0, MID, s));
    col      = mix(col, palette_accent, smoothstep(MID, 1.0, s));
    fragColor = vec4(col, 1.0);
}
