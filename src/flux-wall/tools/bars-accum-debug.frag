#version 300 es
/*
 * archenemy — flux-wall: shader DIAGNOSTYCZNY do tests/flux-wall-bars.sh.
 * Zastępuje bars.frag (ten sam bars.update.glsl obok — test kopiuje oba pod
 * tą samą nazwą): rysuje surowy akumulator (akcent = każdy stempel), środkową
 * kolumnę każdego słupka (atrament) i linię bazową. Nie jest animacją, nie
 * trafia do Super+W (katalog tools/, nie shaders/).
 */
precision highp float; precision highp int; precision highp sampler2D;
uniform vec2 resolution; uniform sampler2D accum; uniform sampler2D audio_spectrum;
uniform vec3 palette_bg; uniform vec3 palette_ink; uniform vec3 palette_accent;
out vec4 fragColor;
void main(){
  ivec2 px = ivec2(gl_FragCoord.xy);
  float sw = resolution.x/64.0;
  int i = int(float(px.x)/sw);
  int x0 = int(floor(float(i)*sw)), x1 = int(floor(float(i+1)*sw));
  int xc = (x0+x1)/2;
  float a = texelFetch(accum, px, 0).r;
  vec3 c = palette_bg;
  if (px.x == xc) c = palette_ink;                 // środkowa kolumna każdego słupka
  if (px.y < 20 && (i % 2 == 0)) c = palette_ink;   // pasek numeracji słupków
  if (a > 0.0) c = palette_accent;                  // gdzie są stemple
  if (px.y >= int(resolution.y*0.12)-1 && px.y <= int(resolution.y*0.12)) c = palette_ink;
  fragColor = vec4(c,1.0);
}
