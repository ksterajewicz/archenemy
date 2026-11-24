# Third-party components

archenemy's own code, documentation and artwork are licensed under GPL-3.0-or-later (see [LICENSE](LICENSE) and the License section of the [README](README.md)). The components below are not ours: they keep their own licenses and notices, listed here with their source and version. GPL-3.0-or-later does not grant any rights to them.

Third-party names and logos (for example Arch Linux, Hyprland, Neovim) remain subject to their owners' trademark rights. This project is not endorsed by those owners. Distribution logos shown at runtime by tools such as fastfetch or Nerd Font glyphs come from those installed packages, not from this repository.

## Included in this repository

| Files | Upstream | Version | SPDX license | Notice |
|---|---|---|---|---|
| `src/flux-wall/protocols/xdg-shell.xml` | [wayland-protocols](https://gitlab.freedesktop.org/wayland/wayland-protocols) `stable/xdg-shell/xdg-shell.xml` | commit `1475d551` (2026-05-30), byte-identical | MIT | [below](#wayland-protocol-notices) and in the file |
| `src/flux-wall/protocols/viewporter.xml` | [wayland-protocols](https://gitlab.freedesktop.org/wayland/wayland-protocols) `stable/viewporter/viewporter.xml` | release 1.45, byte-identical | MIT | [below](#wayland-protocol-notices) and in the file |
| `src/flux-wall/protocols/fractional-scale-v1.xml` | [wayland-protocols](https://gitlab.freedesktop.org/wayland/wayland-protocols) `staging/fractional-scale/fractional-scale-v1.xml` | release 1.45, byte-identical | MIT | [below](#wayland-protocol-notices) and in the file |
| `src/flux-wall/protocols/wlr-layer-shell-unstable-v1.xml` | [wlr-protocols](https://gitlab.freedesktop.org/wlroots/wlr-protocols) `unstable/wlr-layer-shell-unstable-v1.xml` | commit `2b8d4332` (2024-01-26), byte-identical | HPND-sell-variant | [below](#wayland-protocol-notices) and in the file |
| `rices/*/nvim/lua/config/lazy.lua`, lines 1–11 (bootstrap block, same in every rice) | [lazy.nvim](https://github.com/folke/lazy.nvim) installation snippet from its README | adapted from the v9.x README (2023; without `--branch=stable`) | Apache-2.0 | [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt); upstream has no NOTICE file |
| `rices/white-blue/networkmanager-dmenu/config.ini` and the identical copy in `rices/white-blue_beta/` (other rices link to it) | [networkmanager-dmenu](https://github.com/firecat53/networkmanager-dmenu) `config.ini.example` | adapted from the 2.x example (exact upstream version not recorded; latest checked: v2.7.2) | MIT | [below](#networkmanager-dmenu-mit) |
| `config/shell/emacs-default-bindings.txt` | [Zsh manual, ZLE Standard Widgets](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html#Standard-Widgets) — first column of default emacs bindings | documentation for zsh 5.9.2, checked 2026-11-09 | Zsh license (MIT-style) | [below](#zsh) |

`src/flux-wall/Makefile` generates C code from the protocol XML files at build time with `wayland-scanner`; the generated files are not tracked.

## Installed separately, not bundled

These tools are installed from distribution packages after user consent. Their source and binaries are not copied into or bundled with archenemy.

| Tool | Upstream | SPDX license | Distribution |
|---|---|---|---|
| fd | [sharkdp/fd](https://github.com/sharkdp/fd) | MIT OR Apache-2.0 | installed from the distribution package, not bundled |
| ripgrep (`rg`) | [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) | MIT OR Unlicense | installed from the distribution package, not bundled |
| zoxide | [ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide) | MIT | installed from the distribution package, not bundled |
| Starship (optional zsh prompt, `config/shell/rice-look.zsh`) | [starship/starship](https://github.com/starship/starship) | ISC | installed from the distribution package, not bundled; `rices/*/zsh/starship.toml` are our own configs |

Upstream license texts: fd [MIT](https://github.com/sharkdp/fd/blob/master/LICENSE-MIT) / [Apache-2.0](https://github.com/sharkdp/fd/blob/master/LICENSE-APACHE), ripgrep [MIT](https://github.com/BurntSushi/ripgrep/blob/master/LICENSE-MIT) / [Unlicense](https://github.com/BurntSushi/ripgrep/blob/master/UNLICENSE), zoxide [MIT](https://github.com/ajeetdsouza/zoxide/blob/main/LICENSE).

Neovim plugins listed in `lazy.lua` (telescope.nvim, nvim-lspconfig, nvim-cmp and their dependencies) are downloaded by lazy.nvim on the user's machine and are not part of this repository.

## Notices

### Wayland protocol notices

The notices below are copied verbatim from the `<copyright>` element of each file; the files themselves keep them unchanged.

#### `src/flux-wall/protocols/xdg-shell.xml`

```text
Copyright © 2008-2013 Kristian Høgsberg
Copyright © 2013      Rafael Antognolli
Copyright © 2013      Jasper St. Pierre
Copyright © 2010-2013 Intel Corporation
Copyright © 2015-2017 Samsung Electronics Co., Ltd
Copyright © 2015-2017 Red Hat Inc.

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice (including the next
paragraph) shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
```

#### `src/flux-wall/protocols/viewporter.xml`

```text
Copyright © 2013-2016 Collabora, Ltd.

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice (including the next
paragraph) shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
```

#### `src/flux-wall/protocols/fractional-scale-v1.xml`

```text
Copyright © 2022 Kenny Levinsen

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice (including the next
paragraph) shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
```

#### `src/flux-wall/protocols/wlr-layer-shell-unstable-v1.xml`

```text
Copyright © 2017 Drew DeVault

Permission to use, copy, modify, distribute, and sell this
software and its documentation for any purpose is hereby granted
without fee, provided that the above copyright notice appear in
all copies and that both that copyright notice and this permission
notice appear in supporting documentation, and that the name of
the copyright holders not be used in advertising or publicity
pertaining to distribution of the software without specific,
written prior permission.  The copyright holders make no
representations about the suitability of this software for any
purpose.  It is provided "as is" without express or implied
warranty.

THE COPYRIGHT HOLDERS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS
SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS, IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.
```

### networkmanager-dmenu (MIT)

From [`LICENSE.txt`](https://github.com/firecat53/networkmanager-dmenu/blob/main/LICENSE.txt) of networkmanager-dmenu:

```text
The MIT License (MIT)

Copyright (c) 2025 Scott Hansen <tech at firecat53 dot net>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### Zsh

From [`LICENCE`](https://github.com/zsh-users/zsh/blob/master/LICENCE) of the Z shell:

```text
The Z Shell is copyright (c) 1992-2017 Paul Falstad, Richard Coleman,
Zoltán Hidvégi, Andrew Main, Peter Stephenson, Sven Wischnowsky, and
others.  All rights reserved.  Individual authors, whether or not
specifically named, retain copyright in all changes; in what follows, they
are referred to as `the Zsh Development Group'.  This is for convenience
only and this body has no legal status.  The Z shell is distributed under
the following licence; any provisions made in individual files take
precedence.

Permission is hereby granted, without written agreement and without
licence or royalty fees, to use, copy, modify, and distribute this
software and to distribute modified versions of this software for any
purpose, provided that the above copyright notice and the following
two paragraphs appear in all copies of this software.

In no event shall the Zsh Development Group be liable to any party for
direct, indirect, special, incidental, or consequential damages arising out
of the use of this software and its documentation, even if the Zsh
Development Group have been advised of the possibility of such damage.

The Zsh Development Group specifically disclaim any warranties, including,
but not limited to, the implied warranties of merchantability and fitness
for a particular purpose.  The software provided hereunder is on an "as is"
basis, and the Zsh Development Group have no obligation to provide
maintenance, support, updates, enhancements, or modifications.
```
