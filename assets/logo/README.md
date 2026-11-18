# archenemy logo — Æ

The archenemy mark is the ligature **Æ** — **A**rch**E**nemy: the left leg of
the A and the stem of the E are one shared vertical stroke, the crossbars are
offset, and the counter of the A is a triangle. It is the project's own mark,
drawn as its own geometry (one `<path fill-rule="evenodd">` in a
`viewBox="0 0 256 256"`): no fonts, no outlined glyphs, no raster images and no
external resources, and no logo of Arch Linux or any other distribution.

| File | What it is |
|---|---|
| `archenemy-ae.svg` | base mark, white (`#FFFFFF`) on transparency |
| `rices/<rice>.svg` | the same geometry in one rice's colour — only `<title>` and `fill` differ |

## Colours per rice

Each colour is taken from that rice's `waybar/style.css` (the colour its
launcher or accent already used).

| Variant | Fill | Source | Rice has a bar launcher |
|---|---|---|---|
| `asia-n-rice` | `#B47687` | left-island accent | no — the rice has no launcher |
| `crt` | `#74DCE2` | `#custom-launcher` colour | yes |
| `dither-flux` | `#D8E6EE` | `#custom-launcher` colour | yes |
| `tron` | `#00E5FF` | `#custom-launcher` colour | yes |
| `white-blue` | `#0148ED` | active workspace | no — the rice has no launcher |
| `white-blue_beta` | `#0148ED` | active workspace | no — the rice has no launcher |
| `yin` | `#FFFFFF` | `#custom-launcher` colour | yes |
| `yang` | `#0C0C0E` | yin's dark text colour | no — there is no `yang` rice yet |

## How the bar uses it

In `crt`, `dither-flux`, `tron` and `yin` the waybar module `custom/launcher`
shows the mark instead of text: `rices/<rice>/waybar/launcher.svg` is a tracked
symlink to `assets/logo/rices/<rice>.svg`, and `style.css` sets it as the
module's `background-image: url("launcher.svg")`. GTK resolves a relative
`url()` against the directory of the CSS file as it was opened
(`~/.config/waybar/`, itself a link into the active rice), so the picture
follows a rice switch without an absolute path. Waybar opens `style.css` by
path only while it contains no 8-digit `#RRGGBBAA` colour (with one it loads
the rewritten CSS as a string and relative URLs stop resolving), so those
style files use `rgba()`; `bash tests/waybar-launcher.sh` checks this.

To change a colour, edit the `fill` of `rices/<rice>.svg` only; keep the path
identical in all files.
