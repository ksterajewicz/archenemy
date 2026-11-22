# archenemy logo — Æ

The archenemy mark is the ligature **Æ** — **A**rch**E**nemy: the right leg
of the A and the stem of the E are one shared vertical stroke, the crossbars are
offset, and the counter of the A is a triangle. It is the project's own mark,
drawn as its own geometry (one `<path fill-rule="evenodd">` in a
`viewBox="0 0 256 256"`): no fonts, no outlined glyphs, no raster images and no
external resources, and no logo of Arch Linux or any other distribution. The
PNG files below are only renders of the SVG sources.

| File | What it is |
|---|---|
| `archenemy-ae.svg` | base mark, white (`#FFFFFF`) on transparency |
| `archenemy-ae.txt` | the mark as text for fastfetch: half-block characters, 36 columns, `$1` at the start (fastfetch puts the rice's first logo colour there). Generated — after changing the SVG run `python3 assets/logo/gen_text_logo.py` |
| `gen_text_logo.py` | generator of `archenemy-ae.txt`: reads the path from `archenemy-ae.svg` and fills it with the same code as the boot menu logo (`src/system-theme/grub/assets.py`) |
| `rices/<rice>.svg` | the same geometry in one rice's colour — only `<title>` and `fill` differ |
| `banner-dark.svg` | 1280×320 banner: the mark and the `archenemy` wordmark, white `#FFFFFF` on `#0C0C0E` — the top of the repository README on a dark theme |
| `banner-light.svg` | the same banner, blue `#0148ED` on white `#FFFFFF` — the top of the README on a light theme |
| `wordmark-white.svg` | the banner's mark and wordmark in white, no background (for dark surfaces) |
| `wordmark-black.svg` | the same in `#0C0C0E`, no background (for light surfaces) |
| `banner-dark.png`, `banner-light.png` | 2560×640 renders of the two banners, a fallback where SVG is not accepted |
| `social-preview.svg` | 1280×640 source of the repository's social preview (dark background, mark and wordmark centred) |
| `social-preview.png` | its render — the image GitHub shows when a link to the repository is shared |

## Banner and wordmark

The wordmark `archenemy` is drawn for this project as its own path geometry
(eight letter shapes, the two `e` identical), not outlined from a font. In the
banners the mark keeps the base path unchanged and is only moved and scaled
uniformly (0.625). The banner SVGs contain only `svg`, `title`, `desc`, `g`,
`rect` and `path` — no `<text>`, fonts, images or external resources. The
repository README picks the banner by the reader's GitHub theme with
`<picture>` and `prefers-color-scheme`.

**The social preview is uploaded by hand.** GitHub does not read it from the
repository: as the repository owner open **Settings → General → Social
preview → Edit → Upload an image…** and choose `social-preview.png`. After
changing `social-preview.svg`, render it again
(`rsvg-convert -w 1280 -h 640 -o social-preview.png social-preview.svg`) and
upload the new file.

## Colours per rice

Each colour is taken from that rice's `waybar/style.css` (the colour of its
launcher glyph, `#custom-launcher.distro`, or its accent).

| Variant | Fill | Source | Rice has a bar launcher |
|---|---|---|---|
| `asia-n-rice` | `#B47687` | left-island accent | no — the rice has no launcher |
| `crt` | `#74DCE2` | `#custom-launcher.distro` colour | yes |
| `dither-flux` | `#D8E6EE` | `#custom-launcher.distro` colour | yes |
| `tron` | `#00E5FF` | `#custom-launcher.distro` colour | yes |
| `white-blue` | `#0148ED` | active workspace | no — the rice has no launcher |
| `white-blue_beta` | `#0148ED` | active workspace | no — the rice has no launcher |
| `yin` | `#FFFFFF` | `#custom-launcher.distro` colour | yes |
| `yang` | `#0C0C0E` | `#custom-launcher.distro` colour | yes |

## How the bar uses it

In `crt`, `dither-flux`, `tron`, `yin` and `yang` the waybar module `custom/launcher`
shows the mark only in the **archenemy** mode, picked in `Super+A` → `[l] system
logo` (the same choice sets the logo in fastfetch, on the login screen and in
the boot menu); the default mode shows the user's distribution glyph (a Nerd Font
character chosen from `/etc/os-release`, not part of this mark). The module's
text and class come from `scripts/waybar/launcher-logo.sh`: in the archenemy
mode the text is one space (an empty text hides the module) and the class is
`archenemy`. `rices/<rice>/waybar/launcher.svg` is a tracked symlink to
`assets/logo/rices/<rice>.svg`, and `style.css` sets it only under that class:
`#custom-launcher.archenemy { background-image: url("launcher.svg") }`, drawn at
`background-size: 15px 15px` — the bar's font size, so the mark's ink (208/256
of the box, about 12 px) matches the distribution glyph next to it, and the
tile keeps the glyph's width and padding in both modes. GTK resolves a relative
`url()` against the directory of the CSS file as it was opened
(`~/.config/waybar/`, itself a link into the active rice), so the picture
follows a rice switch without an absolute path. Waybar opens `style.css` by
path only while it contains no 8-digit `#RRGGBBAA` colour (with one it loads
the rewritten CSS as a string and relative URLs stop resolving), so those
style files use `rgba()`; `bash tests/waybar-launcher.sh` checks this.

To change a colour, edit the `fill` of `rices/<rice>.svg` only; keep the path
identical in all files.
