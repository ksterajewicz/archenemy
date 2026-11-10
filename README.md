# archenemy

Personal Arch Linux rice for Hyprland. A single installer sets up the entire desktop look — bar, notifications, terminal, lock screen — and lets you switch between themes (rices) with one shortcut. Machine-specific configuration (monitors, graphics card, hardware keys) is generated locally; personal settings such as autostart and app shortcuts also stay outside git.

## Branches

- **dev** — main branch, all changes land here
- **main** — stable releases only, updated after live verification and maintainer approval

## Requirements

- Arch Linux with Hyprland using Lua configuration (the installer offers to install Hyprland if missing). Monitor detection uses a running Hyprland session.
- Keep the checkout at `~/archenemy`: the installer checks this path, and configs and scripts use it. Required packages are listed in `packages/requirements-{pacman,aur}.txt`; optional applications, music tools, zsh, its plugins and CLI tools are in `packages/additional-packages-{pacman,aur}.txt`.
- **hyprpaper >= 0.8.2** — we use the new `wallpaper {}` syntax, `desc:` monitor selectors (added in 0.8.2, matched by prefix since 0.8.4) and the `hyprctl hyprpaper wallpaper "mon, path, fit_mode"` IPC.

## Before you install

Read this whole file. The project replaces folders in `~/.config` — the installer offers to make a backup (it lands in `~/archenemy/backups/`), and linking keeps existing real directories or symlinks outside `rices/` as `<name>.bak-<timestamp>`. Links into an old rice are removed before the new rice is linked.

## Installation

1. Clone the repository into your home directory:

```bash
cd ~
git clone https://github.com/ksterajewicz/archenemy
```

2. Go into the installer folder (the scripts are already executable in git — no `chmod` needed; changing file modes by hand makes `git pull` refuse to update):

```bash
cd ~/archenemy/install/
```

3. Run the installer:

```bash
./install.sh
```

The installer covers these steps:

- **[2]–[3.7]**: check Hyprland, detect monitors, choose their modes, positions, scale, wallpaper roles, left-to-right numbering and workspace mode.
- **[4]–[6.5]**: prepare yay, install required and selected optional packages, choose the hardware profile (DMI supplies a hint), and offer the CPU microcode, GPU driver and alternative kernel installers. ASUS setup uses `install/asus-installation.sh`; the universal profile switcher uses `power-profiles-daemon`, also available as an ASUS fallback.
- **[7]–[8k]**: offer a backup and generate machine configuration, personal-file stubs, autostart app rules and default bar settings.
- **[8l]–[8m]**: configure the optional music stack when installed (see "Music stack"), add the rofi settings entry and shared shell rc block, and offer the `archenemy` alias. Shell selection stays in `Super+A → [h]`.
- **[9]–[9.7]**: link `white-blue` on a fresh install or the saved rice on a repeat run, initialize or restore the wallpaper, optionally build flux-wall, and generate dither-flux wallpapers in the background.
- **[10]–[11]**: configure NetworkManager and pipewire-pulse, offer UFW, Bluetooth and VirtualBox, reload Hyprland and show the summary. VirtualBox uses `install/virtualbox-installation.sh` for DKMS, installed-kernel headers, module checks and optional `vboxusers` membership; a reboot requirement is reported separately.

Installer prompts, status messages, summaries and descriptions emitted directly by `install/*.sh` into generated files use English. `tests/repo-hygiene.sh` checks installer message lines for Polish letters while allowing code comments.

**Updating an existing machine after `git pull`?** Run `install.sh` again — it will generate any missing machine files. The monitor survey ([3]–[3.7]) writes the new `data/monitors/*.dat` into a temporary `data/monitors.new.*` folder and swaps them in only after the last question, so Ctrl-C mid-survey leaves the previous set intact. Every step reports what actually happened: package installs, `ufw`, `systemctl enable`, the bootloader regeneration in the CPU/kernel installers and the final `hyprctl reload` print ✓ only after checking the result, otherwise the step lands in the summary with the command to finish by hand.

## How this is organized — four layers

| Layer | Where it lives | In git? |
|---|---|---|
| **Rice** (looks) | `rices/<name>/` — folders symlinked into `~/.config` | ✅ |
| **Shared** (shortcuts, media keys, shell defaults, music config) | Tracked `config/hypr/*.lua`, `config/shell/zsh-defaults.zsh` and shell catalogs, `config/mpd/mpd.conf` | ✅ |
| **Machine** (monitors, GPU, hardware keys) | `config/hypr/monitorshyprl.lua`, `workspaces-monitors.lua`, `hardware-keys.lua`, `gpu-env.lua`, `hyprpaper.conf`, `hyprlock-background-<rice>.conf`; `config/mpd/output.conf` — generated locally | ❌ |
| **Personal** (your autostart, your app shortcuts, mouse sensitivity, keyboard layouts, your shell aliases, zsh vi key, plugins and CLI choices) | `config/hypr/autostartpersonalisation.lua`, `config/hypr/autostart-apps.lua`, `config/hypr/appbinds.lua`, `config/hypr/mouse.lua`, `config/hypr/keyboard-layouts.lua`, `config/shell/shellrc`, `config/shell/keys.zsh`, `config/shell/plugins.zsh`, `config/shell/cli-tools.bash`, `config/shell/cli-tools.zsh`, `config/mpd/local.conf` | ❌ |

Generated settings and saved choices in `data/` stay outside git. Back up those files separately from the tracked rice and shared layers.

**Hyprland config is in Lua** (as of Hyprland 0.55 the old hyprlang `.conf`
format is deprecated, and 0.57 removed it): every rice has `hypr/hyprland.lua`, and the
shared/machine/personal layers are also `.lua` files pulled in via
`require()`. Repo convention: one bind = one `hl.bind(...)` line — the
Super+A shortcut manager and the workspace guard rely on this. Exceptions to
the migration: `hyprlock.conf` and `hyprpaper.conf` stay in hyprlang (they're
separate programs, not Hyprland). Old `.conf` files sit alongside as
`*.conf.bak` until the migration is verified on a live machine. Each non-beta rice's
lock-screen background (`background { ... }`) is split out via `source =`
into a generated `config/hypr/hyprlock-background-<rice>.conf` — you change
it with the checkbox in `Super + W`, not by editing `hyprlock.conf`. Beta inherits the white-blue lock configuration.

## File structure

```
archenemy/
├── THIRD-PARTY.md                   # Optional CLI tools: upstream links, SPDX licenses and package-only distribution.
├── install/
│   ├── install.sh                    # Main installer. Walks you through the whole setup.
│   ├── bootloader.sh                 # Library: detects the bootloader and regenerates its config (GRUB
│   │                                 #   auto, systemd-boot = manual instructions). Sourced by cpu/kernel.
│   ├── cpudrivers-installation.sh    # CPU microcode (Intel/AMD) — detects the CPU, installs it, regenerates the bootloader.
│   ├── gpudrivers-installation.sh    # GPU drivers — detects the card; NVIDIA: open/proprietary, modeset,
│   │                                 #   initramfs; if a driver is already installed: update (-Syu) / switch variant.
│   │                                 #   For gaming: enables the [multilib] repo and installs lib32 (Steam/Proton/Wine).
│   ├── kernel-install.sh             # Installs an alternative kernel (zen/lts) + regenerates the bootloader.
│   ├── asus-installation.sh          # ASUS laptops: asusctl + rog-control-center from the official repo,
│   │                                 #   replaces AUR variants, starts asusd (exit codes are a contract with step [6]).
│   ├── bluetooth-installation.sh     # Optional Bluetooth + bluetui: verified service and bar visibility flag.
│   └── virtualbox-installation.sh    # Oracle VirtualBox host (optional, asked in step [10]): DKMS modules +
│                                     #   kernel headers, vboxdrv loaded and verified, opt-in vboxusers group.
├── packages/
│   ├── requirements-pacman.txt       # Required packages (official repos).
│   ├── requirements-aur.txt          # Required packages (AUR).
│   ├── additional-packages-pacman.txt # Optional packages (official repos).
│   └── additional-packages-aur.txt   # Optional packages (AUR).
├── config/
│   ├── applications/
│   │   └── ncmpcpp.desktop           # rofi (drun) / [p] autostart entry for ncmpcpp; install.sh [8l]
│   │                                 #   copies it to ~/.local/share/applications only if you have none.
│   ├── mpd/
│   │   └── mpd.conf                  # Shared mpd config (user daemon): ~/Music, state in
│   │                                 #   ~/.local/state/mpd, fifo output for the ncmpcpp visualizer.
│   │                                 #   + generated (outside git): output.conf (machine layer — the
│   │                                 #   audio output, pipewire/alsa, rewritten by Super+A → [o]) and
│   │                                 #   local.conf (personal overrides, include_optional).
│   ├── shell/
│   │   ├── cli-tools-v1.tsv           # Frozen catalog for migrating unsigned personal CLI files.
│   │   ├── cli-tools.tsv              # Optional CLI catalog: packages, licenses, shell support and initialization.
│   │   ├── emacs-default-bindings.txt # ZLE emacs key bindings from the Standard Widgets documentation.
│   │   └── zsh-defaults.zsh          # Shared zsh defaults (history, completion, bash-like keys and
│   │                                 #   prompt, no frameworks), loaded from ~/.zshrc before personal files.
│   │                                 #   + generated (outside git): shellrc — YOUR aliases, functions and
│   │                                 #   PATH for bash AND zsh, keys.zsh — YOUR vi-mode key, and plugins.zsh — YOUR plugin choices
│   │                                 #   and cli-tools.bash / cli-tools.zsh — YOUR CLI choices (personal layer, Super+A → [h]).
│   └── hypr/
│       ├── workspaces.lua            # Workspace guard autostart (shared across all machines).
│       ├── focus-highlight.lua       # Dims the active window highlight while the cursor is on another monitor.
│       ├── autostart-common.lua      # Shared autostart required by every rice (flux-wall wallpaper
│                                     #   animation — your Super+W choice comes back after login in any rice;
│                                     #   the closed-apps history daemon behind Super+Tab).
│       ├── keyboard.lua              # Media keys (shared).
│       ├── gpu_wayland_scaling.lua   # Universal Wayland variables (shared).
│       └── custom_window_rules.lua   # Window rules (shared).
│       │   # (*.conf.bak files sit alongside these — old hyprlang versions, to be
│       │   #  removed once the migration is verified on a live machine)
│       # + files generated by install.sh (outside git):
│       # monitorshyprl.lua, workspaces-monitors.lua, hardware-keys.lua,
│       # gpu-env.lua, autostartpersonalisation.lua, autostart-apps.lua, appbinds.lua,
│       # mouse.lua (mouse settings, written by Super+A → [m]; missing = rice defaults),
│       # keyboard-layouts.lua (1–4 layouts in order, Super+A → [k]; missing = pl,us),
│       # hyprpaper.conf (hyprpaper doesn't migrate to Lua; rices point to it
│       # via a symlink), hyprlock-background-<rice>.conf ×5 (one per rice except beta)
│       # (hyprlock background; rices point to it via `source =`)
├── rices/
│   ├── white-blue/                   # Default rice: alacritty, fastfetch, hypr(+hyprlock), mako,
│   │                                 #   MangoHud, networkmanager-dmenu, nvim, rofi, waybar,
│   │                                 #   ncmpcpp (colors + the shared vim-like `bindings`), mpv (OSD colors),
│   │                                 #   swayosd; each non-beta rice also carries flux-wall.conf (palette, default animation,
│   │                                 #   FLUX_WALL_DITHER — Bayer raster on/off in shaders that support it)
│   │                                 #   and every rice carries preview.png — its picture in the Super+T menu (a generated mock-up;
│   │                                 #   replace it with a real screenshot at the same path).
│   ├── white-blue_beta/              # Original look, kept for reference/rollback (frozen: no ncmpcpp,
│   │                                 #   mpv, flux-wall.conf, timer). mako, hyprlock and swayosd inherit
│   │                                 #   from white-blue (symlinks in the repo).
│   ├── tron/                         # Tron: Legacy — dark neon (cyan + CLU orange), glow,
│   │                                 #   4-6px corners. Own fastfetch (Arch logo in cyan) + launcher
│   │                                 #   in the waybar and nvim theme (neon cyan); ncmpcpp + mpv colors;
│   │                                 #   networkmanager-dmenu and ncmpcpp `bindings` from white-blue (symlinks).
│   ├── asia-n-rice/                  # Mauve/pink on navy, flat look. Own hypr, rofi,
│   │                                 #   mako, hyprlock, alacritty, waybar and nvim theme (mauve);
│   │                                 #   default fastfetch; ncmpcpp + mpv colors;
│   │                                 #   MangoHud/networkmanager-dmenu/ncmpcpp `bindings` from white-blue (symlinks).
│   ├── dither-flux/                  # Dither art + algorithmic art in the rainy
│   │                                 #   milford-water palette: zero rounding, no blur or glow,
│   │                                 #   1px borders, flat panels. Full own layer set (incl. ncmpcpp + mpv colors);
│   │                                 #   networkmanager-dmenu and ncmpcpp `bindings` from white-blue (symlinks).
│   └── crt/                          # Blue/cyan phosphor palette: glass islands with glow,
│                                     #   4px corners, amber #FFB000 for alarms only. Full own
│                                     #   layer set (incl. ncmpcpp + mpv colors); networkmanager-dmenu
│                                     #   and ncmpcpp `bindings` from white-blue (symlinks).
├── scripts/
│   ├── shell/                        # shell-settings.sh — Super+A → [h]: bash ↔ zsh (package, chsh),
│   │                                 #   arrow-key menus, editing shellrc in neovim, configuring the zsh vi-mode key, optional zsh plugins and CLI tools for bash/zsh;
│   │                                 #   lib/shell-rc.sh — the shared shell file, rc blocks and personal
│   │                                 #   keys.zsh / plugins.zsh / cli-tools.bash / cli-tools.zsh writer (shared by install.sh [8m] and the TUI).
│   ├── appbinds/                     # Terminal shortcut manager for apps (Super+A); update-archenemy.sh — [u];
│   │                                 #   terminal-settings.sh — [c] copy on select in Alacritty (backup on first change);
│   │                                 #   lib/tui.sh — shared look and keys: rice accent, header, [y/N] prompts,
│   │                                 #   tui_menu — highlighted choices with arrows/j/k, Enter, digits and Esc;
│   │                                 #   yes/no prompts also use arrows/j/k and Enter; y/n shortcuts remain, Esc cancels;
│   │                                 #   lib/mpd-output.sh — mpd output switch and its playback test ([o]);
│   │                                 #   lib/binds.sh — the one place that lists/edits/removes user binds (list and
│   │                                 #   [d] pick the same lines);
│   │                                 #   [w] switches shared/decades workspace mode live;
│   │                                 #   [v] switches the waybar volume bar style;
│   │                                 #   [o] audio: system output/input (audio-devices.sh), mpd output: pipewire (recommended) / alsa;
│   │                                 #   [t] waybar timer: on/off, default duration, color;
│   │                                 #   [m] mouse: speed, DPI, polling rate, acceleration, scrolling (via hypr/mouse-settings.sh);
│   │                                 #   [k] keyboard layouts: 1–4, order (via hypr/keyboard-layouts.sh);
│   │                                 #   [n] monitors: map, resolution, refresh rate, scale, position, new monitor, numbers (via hypr/monitor-settings.sh);
│   │                                 #   [i] diagnostics: config check and saved dumps;
│   │                                 #   autostart-picker.sh — [p] pick apps to autostart
│   │                                 #   (checkboxes + filter, plain bash).
│   ├── changing-theme-scripts/       # One stub per rice (file name = menu entry);
│   │                                 #   shared switching logic lives in lib/switch-rice.sh.
│   ├── hypr/                         # workspace-orphan-guard.sh — daemon (decades mode only): merges
│   │                                 #   orphaned workspaces onto whatever screen exists — no more double
│   │                                 #   "1" on the bar. ws-scroll.sh — waybar scroll per workspace mode.
│   │                                 #   workspace-diag.sh — read-only dump of workspace state (mode,
│   │                                 #   rules vs hyprctl, monitors, workspaces, binds, guard, log) for
│   │                                 #   bug reports; run before and after Super+T and diff.
│   │                                 #   gaming-diag.sh — read-only GPU/gaming dump (no sudo): which GPUs
│   │                                 #   are on the bus, ASUS dgpu_disable / MUX, NVIDIA module vs kernel,
│   │                                 #   dGPU runtime power, Hyprland's GPU env, package history, load,
│   │                                 #   and — with a game open — which GPU the game actually renders on.
│   │                                 #   keyboard-layouts.sh — Super+A → [k] and Super+Ctrl+1…4: layout list
│   │                                 #   (data/keyboard-layouts.dat → config/hypr/keyboard-layouts.lua), reload,
│   │                                 #   read-back; `switch N` = layout #N of the list;
│   │                                 #   mouse-settings.sh — Super+A → [m]: saves data/mouse-sensitivity.dat and
│   │                                 #   data/mouse-settings.dat, generates config/hypr/mouse.lua, hyprctl reload,
│   │                                 #   confirms via getoption; hardware DPI and polling through ratbagctl;
│   │                                 #   monitor-settings.sh — Super+A → [n]: mode, position and scale on a
│   │                                 #   trial, set up a new monitor, renumber left to right, forget an
│   │                                 #   unplugged one; data/monitors/*.dat → monitorshyprl.lua and
│   │                                 #   workspaces-monitors.lua via the generators shared with install.sh,
│   │                                 #   reload, read-back from hyprctl; `notify` = new-monitor notification;
│   │                                 #   workspace-mode-switch.sh — switches shared/decades live
│   │                                 #   (regen + reload + guard); lib/gen-workspaces.sh — shared
│   │                                 #   generator for workspace rules/binds (shared with install.sh);
│   │                                 #   lib/gen-monitors.sh — monitor rules and saved monitor order;
│   │                                 #   lib/hypr-apply.sh — reload checked against configerrors;
│   │                                 #   lib/gen-autostart.sh — generator for autostart-apps.lua
│   │                                 #   (shared with install.sh and the Super+A → [p] picker).
│   │                                 #   lib/monitor-id.sh — monitor identity for the machine layer:
│   │                                 #   "desc:<EDID description>" selectors instead of connector
│   │                                 #   names (eDP-2 / HDMI-A-1 change between reboots).
│   │                                 #   machine-layer-check.sh — read-only self-check at session start:
│   │                                 #   one notification when the generated files no longer match the
│   │                                 #   connected monitors (instead of Hyprland's silent fallback),
│   │                                 #   and when install-relevant code changed since the last install.sh
│   │                                 #   (data/installed-head.dat vs HEAD — re-run the installer).
│   │                                 #   window-history.sh — Super+Tab: reopens recently closed apps
│   │                                 #   (daemon started from autostart-common.lua + `restore`).
│   ├── rofi/                         # Rofi menus: app launcher (rofi_drun.sh), rices, wallpapers, network (with rescan), power.
│   │                                 #   lib/rofi-preview.sh — PNG previews in Super+W / Super+T (3-column
│   │                                 #   grid with big icons; lazy wallpaper thumbnails in data/thumbs/).
│   ├── wallpapers/                   # lib/dither-flux-sizes.sh — which dither-flux wallpapers the current
│   │                                 #   monitors still need (shared by install.sh and Super+A → [n]).
│   │                                 #   Mathematical wallpaper generators (pure Python, zero dependencies):
│   │                                 #   Arch logo (gen_arch_wallpaper.py), Tron grid
│   │                                 #   (gen_tron_wallpaper.py), and generative dither wallpapers
│   │                                 #   for the dither-flux rice (gen_dither_flux_wallpaper.py),
│   │                                 #   oscilloscope Lissajous for crt (gen_crt_wallpaper.py);
│   │                                 #   gen_rice_preview.py — the rices' preview.png mock-ups for Super+T
│   │                                 #   (drawn from each rice's waybar/alacritty/hypr/flux-wall colors);
│   │                                 #   flux-wall.sh — start/stop the shader-driven wallpaper.
│   └── waybar/                       # Power profile switcher (asus/universal: profile-get.sh /
│                                     #   profile-switch.sh — also the ASUS hardware key path) +
│                                     #   volume-bar.sh — volume bar in place of the pulseaudio module;
│                                     #   line/ticks/solid style switchable in Super+A → [v].
│                                     #   bluetooth.sh — optional D-Bus event stream, power toggle and bluetui launcher.
│                                     #   timer.sh + timer-ctl.sh — countdown timer next to the clock,
│                                     #   optional, enabled in Super+A → [t];
│                                     #   lib/timer-state.sh — shared read/write of timer state.
├── src/
│   └── flux-wall/                    # GPU shader-driven wallpaper (C, wlr-layer-shell + EGL/GLES 3):
│       ├── main.c                    #   Wayland/EGL: one surface per monitor, main loop, battery;
│       ├── engine.c / engine.h       #   rendering (GLES, no Wayland): single-pass path
│       │                             #   or the particle engine (accumulative forms — flow field);
│       ├── audio.c / audio.h         #   audio reactivity: FFT from the OUTPUT monitor (libpulse via
│       │                             #   pipewire-pulse), bass/mid/high bands, beat — visualizations only;
│       ├── util.h                    #   shared helpers (monotonic clock, read a regular file) for main/audio/tools;
│       ├── test.c                    #   pure-function tests (palette, battery, #pragma flux, warp, step cap);
│       ├── Makefile                  #   protocol code is generated by wayland-scanner from the XML files in the repo;
│       ├── protocols/                #   wlr-layer-shell, xdg-shell, viewporter, fractional-scale-v1
│       │                             #   (XML, MIT/X11 license);
│       ├── tools/                    #   offscreen.c — dev tool: render animation frames to PNG without
│       │                             #   a screen (EGL surfaceless + the same engine.c); `make tools`,
│       │                             #   never built by install.sh; pngstat.py + bars-accum-debug.frag —
│       │                             #   helpers for tests/flux-wall-bars.sh; render-previews.sh — renders
│       │                             #   shaders/previews/<rice>/<animation>.png (256x144, the rice's palette,
│       │                             #   synth audio for visualizations) for the Super+W menu — dev tool, run
│       │                             #   by hand after adding a shader or changing a palette, then commit;
│       └── shaders/                  #   animations selectable in Super+W: dither-flux (domain warping),
│                                     #   dither-waves (interference) — single .frag files; pairs of
│                                     #   .frag + .update.glsl (particle engine): dither-flow,
│                                     #   dither-attractor, dither-thomas, dither-halvorsen,
│                                     #   dither-aizawa, dither-dejong, dither-vortex, dither-rain,
│                                     #   Music visualizations (no "dither-" prefix): orb-spinnin' /
│                                     #   orb-static (NCS-orb-style — spectrum, bass, beat; rotating / still),
│                                     #   scope (oscilloscope, waveform with trigger), scope-xy (Lissajous
│                                     #   from L/R), spectrogram (plain scrolling spectrogram, dB scale);
│                                     #   bars, waterfall, rings, radar, tunnel (also selectable music visualizations).
│                                     #   previews/<rice>/<animation>.png — menu pictures (render-previews.sh).
│                                     #   Built by install.sh [9.6]; build/ outside git.
├── tests/                            # machine-layer.sh — regression tests on a fake hyprctl (tests/mock/)
│                                     #   replaying the real 2026-09-21 dump: generators, guard, mode switch,
│                                     #   self-check, installer step [3]. `bash tests/machine-layer.sh`.
│                                     #   flux-wall-bars.sh — offscreen render of `bars` at both monitor sizes,
│                                     #   peak marks must land on BOTH halves (needs `make -C src/flux-wall tools`).
│                                     #   flux-wall-dither.sh — flux-wall.sh passes --dither only for the active
│                                     #   dither-flux rice (fake binary); offscreen: --dither = palette colors only,
│                                     #   --no-dither = smooth gradient, with spectrogram unchanged by the flag (render part skips without tools).
│                                     #   wallpaper-switcher.sh — Super+W against a fake hyprpaper daemon
│                                     #   (settings list + first-match rule): the picked wallpaper must end up
│                                     #   ON SCREEN in all three .dat scenarios; plus the menu previews on a
│                                     #   fake rofi (thumbnail cache by mtime, no tool → original image).
│                                     #   `bash tests/wallpaper-switcher.sh`.
│                                     #   rofi-theme-switcher.sh — Super+T previews on a fake rofi; every rice
│                                     #   stub has a valid rices/<RICE_NAME>/preview.png.
│                                     #   render-previews.sh — tools/render-previews.sh on a fake offscreen:
│                                     #   --dither/--no-dither per rice (none for an older offscreen), synth audio,
│                                     #   frame time from `#pragma flux life`.
│                                     #   update-archenemy.sh — the Super+A → [u] updater on real git
│                                     #   (bare origin in a temp dir): no false "✓" on failure, no
│                                     #   switching to a branch older than what you run.
│                                     #   switch-rice.sh — rice switching on a fake ~/.config: foreign
│                                     #   symlinks backed up, two quick Super+T don't race.
│                                     #   install-link.sh — installer step [9] (link-only mode of the same
│                                     #   lib): stow symlinks and real dirs go to .bak, never rm.
│                                     #   install-tui-entry.sh — installer step [8m]: rofi entry with an
│                                     #   absolute path, ~/.bashrc block added silently once, `archenemy`
│                                     #   alias in the shared shell file only once (old ~/.bashrc alias moved).
│                                     #   shell-rc.sh — the shared shell file on a fake HOME: one block after
│                                     #   many runs, backups, safe-line migration, real `bash -i`, and
│                                     #   no Polish text in anything written to a fresh HOME.
│                                     #   shell-settings.sh — Super+A → [h] on fake getent/chsh/pacman/nvim:
│                                     #   zsh installed and chsh only after "y", plus vi-key capture,
│                                     #   collision prompts, default restore and atomic personal-file writes.
│                                     #   shell-cli-tools.sh — CLI catalog, independent shell state, opt-in packages and arrow navigation on mocks.
│                                     #   shell-plugins.sh — optional plugin checklist, package confirmation,
│                                     #   state/backups, loading order and missing-file guards on mocks.
│                                     #   appbinds.sh — Super+A list vs [d]: a hand-written bind between
│                                     #   TUI binds doesn't shift the numbering.
│                                     #   rice-autostart.sh — runs every rice's hyprland.lua on a fake
│                                     #   `hl` API (lua5.4) and checks what starts with the session.
│                                     #   gpudrivers.sh — GPU installer on fake sudo/pacman/modinfo and a
│                                     #   fake /etc: no initramfs changes without a built nvidia module.
│                                     #   repo-hygiene.sh — executable bits, Lua dispatch syntax and installer language.
│                                     #   appbinds-menu.sh, tui-keys.sh, tui-lines.sh, tui-contrast.sh — TUI
│                                     #   dispatch, navigation, line input and palette contrast.
│                                     #   autostart-picker.sh, terminal-settings.sh — app checklist and copy on select.
│                                     #   monitor-settings.sh — monitor trials and rollback; audio-devices.sh /
│                                     #   mpd-output.sh — system and mpd outputs; focus-highlight.sh — cursor-aware borders.
│                                     #   rofi-drun.sh — launcher command gate.
│                                     #   keyboard-layouts.sh — [k] on a fake HOME/hyprctl/evdev.lst: 1–4 known
│                                     #   codes, reload + read-back, switch N, the TUI menu driven via stdin.
│                                     #   mouse-settings.sh — [m] on a fake HOME/hyprctl/ratbagctl: range checks,
│                                     #   reload + read-back, generated Lua, emulated and hardware DPI, the menu.
│                                     #   asus-installation.sh — ASUS installer on a fake pacman: AUR variants
│                                     #   replaced, success = the package named asusctl, supergfxctl guard.
│                                     #   power-profile.sh — profile get/next on a fake asusctl with the 6.5.0
│                                     #   syntax, verified change, fallback to power-profiles-daemon.
│                                     #   virtualbox.sh — VirtualBox installer on fake pacman/modprobe and a
│                                     #   fake /sys/module: success only with vboxdrv loaded, reboot code 2.
│                                     #   window-history.sh — Super+Tab on a fake `hyprctl clients` with
│                                     #   real processes: same argv and directory, apps still running
│                                     #   (tray, dialogs) skipped, the state lock is not inherited.
│                                     #   bluetooth.sh — optional Bluetooth bar and installer on mock BlueZ/D-Bus/services.
│                                     #   run-all.sh — every suite at once: `bash tests/run-all.sh`.
└── wallpapers/                       # Wallpapers (in git) — any files, optionally grouped in set folders.
    ├── arch-white/                   # Set: Arch logo (#0148ED) on white — v1 1920x1080, v2 2560x1600.
    ├── tron-grid/                    # Set: Tron grid (neon cyan on #020A0F) — v1/v2 as above.
    ├── crt/                          # Set: oscilloscope — Lissajous trace in phosphor cyan on
    │                                 #   navy glass with a faint graticule — v1/v2 as above.
    └── dither-flux/generated/        # NOT in git — created by install.sh [9.7]: 3 forms (flow field ×2,
                                      #   attractor) in a Bayer dither raster, milford-water palette, sized
                                      #   to the REAL monitors. No PNGs of this set in git (2026-09-08).
```

## Wallpapers

Wallpapers live in `wallpapers/` (loose files or in subfolders) and are versioned in git — a fresh install has them right away. Exception: the `dither-flux` set is **generated for the real monitors** — `install.sh` step **[9.7]** reads resolutions and roles from `data/monitors/*.dat` (primary → `v1`, secondary → `v2`, further ones → `m-<name>`; modes named like `preferred` are resolved via `hyprctl`) and runs `gen_dither_flux_wallpaper.py` in the background into `wallpapers/dither-flux/generated/` (outside git; logged to `generate.log`). A 1px raster doesn't tolerate scaling, so the wallpaper must exactly match the screen resolution. As of 2026-09-08 the repo keeps no ready-made PNGs for this set — until generation finishes (a few minutes after install) the `dither-flux` entry in `Super+W` simply isn't there; the flux-wall animations are independent of these files.

The `Super+W` menu is two-level: under two checkboxes are the **`Wallpapers/`** folder (files from `wallpapers/`) and **`Animations/`** (flux-wall animations, when built; music visualizations tagged `♪ music visualisation`), and below them **`Animation: off`**; `← Back` in the submenu returns to the top. Picking an animation doesn't change the hyprpaper wallpaper: the animation draws on top of it and works in **every** rice, using `rices/<rice>/flux-wall.conf` for the palette when present (beta has no such file and uses the binary's default palette). The choice is remembered in `data/flux-wall.dat` and survives `Super+T` and reboots; `off` disables the animation everywhere, and deleting the file restores the rice's default behavior (dither-flux: enabled, the rest: disabled). Switching: `Super + W` — the menu shows all images (jpg/jpeg/png/webp), with two checkboxes at the top: `[x] Upload to all monitors` (checked by default — wallpaper goes to all monitors instead of just the focused one) and `[ ] Set as hyprlock background (no blur)` (unchecked by default — checking it sets the chosen image as the lock-screen background without blur, instead of the default live screenshot + blur; survives switching rices).

**Previews.** Both submenus show pictures: a 3-column grid with a large image above each name (set via `-theme-str` only for these menus — each rice's rofi colors, borders and rounding stay; the top level with the checkboxes stays a plain list, and `← Back` has no image). `Wallpapers/` shows thumbnails generated on first use into `data/thumbs/` (machine layer, outside git), keyed by path + modification time — an edited file gets a fresh thumbnail, the stale one is removed. The tool is whichever is present: `glycin-thumbnailer`, `gdk-pixbuf-thumbnailer`, or ImageMagick's `magick`; with none of them, or on an error, the original image is used as the icon (rofi loads it, just more slowly). Generation is capped at 3 s per file and 6 s per menu opening, so the shortcut never hangs — anything left over shows the original and gets its thumbnail next time. `Animations/` shows ready-made frames from `src/flux-wall/shaders/previews/<active rice>/<animation>.png` (committed, rendered in each rice's palette by `src/flux-wall/tools/render-previews.sh`); an animation without a frame is listed without a picture, and a rice with no frames at all (e.g. `white-blue_beta`) gets the plain list.

At the top of the menu is the **`[x] Upload to all monitors`** toggle (checked by default):

- **Checked** — the wallpaper goes to all monitors. If a matching `*v1*`/`*v2*` counterpart sits next to the chosen file, the primary monitor gets `v1` and every other monitor gets `v2`; without a pair, the same image goes everywhere.
- **Unchecked** (click the entry to toggle) — the wallpaper goes only to the monitor you have focus on; the others stay unchanged.

The per-monitor choice is remembered in `data/wallpaper.dat` and restored when you switch rice or re-run `install.sh` (a fresh install, or a choice pointing at deleted files, falls back to the first wallpaper). Set wallpaper roles in the installer or `Super+A → [n]`; the installer proposes the first monitor as primary and the rest as secondary. A monitor without a saved wallpaper uses the secondary wallpaper on restore.

**One monitor = one entry, and the switcher checks the screen.** `data/wallpaper.dat` and the generated `hyprpaper.conf` are keyed by the same monitor selector the rest of the machine layer uses (`desc:<EDID description>`, connector name for older `.dat` files) — and the live IPC call tries that same key first, with a connector-name fallback if it fails. hyprpaper keeps its settings as a list and gives a monitor the **first matching** entry, while IPC appends its entry at the end and only replaces one with an identical key: a leftover entry for the same screen under its old connector name (or an IPC call keyed by connector name against a `desc:` config) would therefore win the match and the newly picked wallpaper would never show up — with `hyprctl` still reporting success. Old connector-name entries are migrated to today's selector on read, and after applying, the switcher asks `hyprctl hyprpaper listactive` what is actually on screen; if it doesn't match, it restarts hyprpaper (which re-reads the freshly written config) and checks again before claiming success. When `listactive` gives no usable response, compatibility handling falls back to the IPC result; this cannot verify the displayed image.

The role only applies to **wallpapers** (primary→v1, every other monitor→v2). Workspace assignment is governed by something else: **left→right monitor numbering** and **workspace mode** (see the "Workspaces" section).

## Shader-computed animated wallpaper (flux-wall)

`src/flux-wall/` is a Wayland client written in C (`wlr-layer-shell`, EGL and GLES 3.0). It draws a shader on a separate surface per monitor, on the `bottom` layer above hyprpaper and below windows. Hyprpaper stays underneath as the fallback if the animation stops or cannot start. Integer and fractional output scales are supported through `wl_output`, `wp_fractional_scale_v1` and `wp_viewporter`.

**Build.** Installer step **[9.6]** runs `make -C src/flux-wall`. Build dependencies are `base-devel`, `wayland`, `mesa` and `libpulse` from the required package list; protocol XML files are included in the repo. A failed build is reported in the summary and does not abort installation. Developer tools are separate: `make -C src/flux-wall tools` builds the offscreen renderer; `make -C src/flux-wall test` runs the C tests.

**Choice and autostart.** `Super+W → Animations/` saves an animation name in `data/flux-wall.dat`; `Animation: off` saves `off`. This choice applies across rices and takes precedence over the rice's default. With no saved choice, only `dither-flux` starts an animation. Each non-beta rice declares `FLUX_WALL_PALETTE`, `FLUX_WALL_SHADER`, `FLUX_WALL_ARGS`, `FLUX_WALL_AUTOSTART` and `FLUX_WALL_DITHER` in its `flux-wall.conf`. Beta uses the binary's default palette for a selected animation. Login starts the wrapper once through shared `config/hypr/autostart-common.lua`; the rice switcher calls it again to apply the new palette and settings. A missing binary leaves the static wallpaper visible. Step [9.6] migrates renamed choices and clears choices whose shader was removed.

**Dither and battery.** Only `dither-flux` sets `FLUX_WALL_DITHER=1`; the wrapper passes `--dither` there and `--no-dither` elsewhere, regardless of the selected animation. Shaders with dithering use an 8×8 Bayer matrix or a smooth palette gradient; `spectrogram` always uses a smooth gradient. An older binary that lacks these flags gets neither until rebuilt. `--battery` adjusts the `detail` uniform from battery state, with full detail on AC power; each shader decides how detail affects its rendering.

Available animations in `src/flux-wall/shaders/`:

- `dither-flux` (domain warping), `dither-waves` (wave interference), `dither-flow` (flow-field trails), `dither-attractor` (Clifford attractor), `dither-thomas`, `dither-halvorsen`, `dither-aizawa`, `dither-dejong`, `dither-vortex` and `dither-rain`.
- Music visualizations: `orb-spinnin'`, `orb-static`, `scope`, `scope-xy`, `spectrogram`, `bars`, `waterfall`, `rings`, `radar` and `tunnel`. All are selectable; menu entries carry `♪ music visualisation`.

**Music.** Shaders declaring `#pragma flux audio 1` automatically enable analysis of the audio output monitor, never the microphone. Regular animations do not listen to audio. `audio.c` uses libpulse through the audio server to provide spectrum bands, a stereo waveform and beat information; a missing audio server does not prevent rendering. For debugging, the binary accepts `--audio-file file.f32` or `--no-audio`.

```bash
scripts/wallpapers/flux-wall.sh list                 # available animations
scripts/wallpapers/flux-wall.sh list-audio           # music visualizations
scripts/wallpapers/flux-wall.sh select dither-waves  # select and remember
scripts/wallpapers/flux-wall.sh off                  # disable and remember
scripts/wallpapers/flux-wall.sh start -f 30          # start with an FPS limit
scripts/wallpapers/flux-wall.sh stop                 # stop without changing the saved choice
scripts/wallpapers/flux-wall.sh status               # exit status: is flux-wall running?
scripts/wallpapers/flux-wall.sh doctor               # read-only diagnostic dump
```

Runtime logs go to `$XDG_RUNTIME_DIR/flux-wall.log` (or `/tmp/flux-wall.log` without that variable). `doctor` reports the checkout, binary age and capabilities, shaders, saved choice, process and log.

**Adding shaders.** A single-pass animation is a `.frag` file. A matching `<name>.update.glsl` enables the particle engine: positions and fading trails live in floating-point textures, with parameters from `#pragma flux` declarations. Supported uniforms and parameters are defined in `src/flux-wall/engine.h` and implemented in `engine.c`. Add previews with `src/flux-wall/tools/render-previews.sh -r <rice>` after building the tools. Dithering must follow the uniform rather than the animation name. Accumulator reads at computed columns need a small band (`bars` uses `xc-1..xc+1`), because point stamps may land one pixel to the left; `tests/flux-wall-bars.sh` checks both screen halves. `tests/flux-wall-dither.sh` checks wrapper flags and, when tools are built, rendering.

## Rices

| Rice | Description |
|---|---|
| `white-blue` | Default. White-blue glass: rounded corners, tuned blur, custom animations, consistent `#0148ED` accent, mako + hyprlock + nvim theme (hand-tuned colorscheme in the rice's palette). ncmpcpp skin (blue accent `#0148ED`, bright blue `13` for the now-playing line, terminal palette only) and mpv OSD (white on `#1A1A2E`). |
| `white-blue_beta` | The original white-blue look, kept for reference/rollback. Functional fixes only, no visual changes. mako and hyprlock inherit from `white-blue` via symlinks in the repo. |
| `tron` | Tron: Legacy — dark glass `#020A0F`, neon cyan `#00E5FF` with glow, CLU orange `#FF7B1C` for alarms only, near-sharp corners (4–6px). Own waybar theme (with a "portal to the Grid" launcher and glowing HUD islands), rofi (search glyph), fastfetch (Arch logo in neon cyan), alacritty/mako/hyprlock (cinematic look with neon lines)/MangoHud/nvim (hand-tuned colorscheme: neon cyan on `#020A0F`, alarms in CLU orange); networkmanager-dmenu inherits from `white-blue` via a repo symlink. Wallpaper: the `tron-grid` set (generated). ncmpcpp skin (neon cyan accent, plate `#0E2A33` as the empty part of the progress bar, no CLU orange) and mpv OSD (`#CFEEF7` on `#020A0F`). |
| `asia-n-rice` | Muted mauve/pink (`#b47687`) on dark navy (`#2a3444`), flat look: waybar with rounded islands (14px) and italic window titles, sharp window corners, `#131a2a` border. Look adapted from an external rice and rewired onto the archenemy backend: alacritty instead of kitty, rofi instead of wofi, machine layer (GPU/monitors/workspaces) via Lua `require()`, no cava. Own waybar/rofi/mako/hyprlock/alacritty theme in the mauve palette; default fastfetch (no recoloring); own nvim theme (hand-tuned colorscheme in the mauve palette, flat — no bold); MangoHud and networkmanager-dmenu inherit from `white-blue` via symlinks. No wallpaper of its own — uses whatever's current (machine layer). ncmpcpp skin (mauve accent, flat — no bold anywhere) and mpv OSD (`#e8e8e8` on `#182130`). |
| `crt` | Blue/cyan phosphor CRT — the owner's six `hyprpicker` samples: `#043D7B`/`#0B358B` (glass, plates), `#3069AD` (borders, dim text), `#5695D6` (text), `#36D2D8` (accent, active), `#74DCE2` (bright text); the dark base `#031533` is `#043D7B` darkened in the same hue (the palette has no near-black), and amber `#FFB000` — classic amber phosphor — is the only warm color, reserved for alarms. (The CRT screen shader — scanlines/aperture mask/vignette — was removed on 2026-09-17 at the owner's request: the palette is the point, the "old monitor" look was not.) Glass islands with blur (alpha 0.55) and a cyan glow, 4px corners, 1px gradient borders (`#36D2D8` → `#5695D6`), phosphor glow (`shadow`) around the active window. Full own set: waybar (launcher glyph as a power LED), rofi, alacritty (cool ANSI, still distinguishable), mako, swayosd, hyprlock (glowing clock via label shadow), fastfetch, MangoHud, nvim (hand-tuned colorscheme); networkmanager-dmenu from `white-blue` via symlink. Wallpaper: the `crt` oscilloscope set from `gen_crt_wallpaper.py`; flux-wall animations available in the rice's palette (off by default). ncmpcpp skin (`#5695D6` text, cyan accent, `#0B358B` as the empty part of the progress bar, `#3069AD` frames) and mpv OSD (`#74DCE2` on `#031533`). |
| `dither-flux` | Dither art + algorithmic art: wallpapers are generative fields (flow field, Clifford attractor) quantized with an 8×8 Bayer raster, in the rainy `milford-water` palette from a Milford Sound frame; the only rice with `FLUX_WALL_DITHER=1`, so shaders with dithering — music visualizations included — use the same 1px Bayer raster (other rices and the `spectrogram` shader use a smooth gradient) — wet mountains `#0F1A24`, steel water `#5C87A3`, mist `#A8C4D4`, foam `#D8E6EE` as an accent; amber `#E0A23C` is the only warm color and is reserved for alarms only. Geometry follows the raster: **zero rounding**, 1px window borders, **blur and shadow disabled** (blur and dither are contradictory materials), waybar/rofi/mako islands as flat, near-opaque panels. Full own set: waybar (with a launcher), rofi, alacritty (ANSI toned to the palette but still distinguishable), mako, swayosd, hyprlock (1px lines, no glow), fastfetch (Arch logo in foam), MangoHud, nvim (hand-tuned colorscheme); networkmanager-dmenu from `white-blue` via symlink. Wallpapers: the `dither-flux` set from `gen_dither_flux_wallpaper.py`. ncmpcpp skin (foam `#D8E6EE` as the accent, water `#5C87A3` as the elapsed bar, plate `#1B3040` as the empty part, flat — no bold) and mpv OSD (foam on `#0F1A24`). |

Each rice is a folder in `rices/` whose subfolders are symlinked into `~/.config`. Switching: `Super + T` — the menu shows scripts from `scripts/changing-theme-scripts/` (the `.sh` file name is the menu label: `white-blue`, `tron`, `asia-n-rice`, `dither-flux`, `crt`, `white-blue_beta`). On switching, the old rice's symlinks are cleaned up, so themes don't mix.

The `Super + T` menu is a grid of pictures: each entry shows `rices/<RICE_NAME>/preview.png` (`RICE_NAME` read from the stub, so the label doesn't have to match the folder). The committed files are **mock-ups** drawn by `scripts/wallpapers/gen_rice_preview.py` from the colors each rice actually declares — the wallpaper motif in the `flux-wall.conf` palette, waybar islands from `waybar/style.css`, a terminal with the border/rounding from `hypr/hyprland.lua` and the ANSI palette from `alacritty/alacritty.toml` (`python3 scripts/wallpapers/gen_rice_preview.py [rice…]` regenerates them). A real screenshot is better: take one with `Super + Print` (drag over the whole screen; it lands in `~/Screenshots`) and copy it over `rices/<rice>/preview.png` — any size works, the menu just scales it. A rice without the file is listed without a picture.

**New rice:** create `rices/<folder>/`, copy `scripts/changing-theme-scripts/white-blue.sh` as `<label>.sh`, and set `RICE_NAME` inside it to your folder's name. The script is a two-line stub — all the switching logic lives in the shared `lib/switch-rice.sh`, so a new rice doesn't require copying any logic. For its `Super + T` picture, run `python3 scripts/wallpapers/gen_rice_preview.py <folder>` (a plain gradient background until you add a motif for it in the script) or drop a screenshot in as `rices/<folder>/preview.png`; if the rice has a `flux-wall.conf`, `src/flux-wall/tools/render-previews.sh -r <folder>` renders its animation previews. The installer's step [9] calls the same library with `SWITCH_RICE_LINK_ONLY=1` (links + `.current_rice` only, no wallpaper/reload/waybar restart), so a foreign symlink or a real directory in `~/.config` always ends up as `<name>.bak-<timestamp>`, never deleted.

### App launcher

`Super+R` and the bar's app launcher call `scripts/rofi/rofi_drun.sh`. It opens rofi's desktop-entry launcher and gates manually typed commands by checking their first command token against `.desktop` `Exec=` lines. With normal desktop entries present, unmatched commands are ignored. If no `Exec=` entries can be read, the gate allows commands as a compatibility fallback. This is an application launcher, not a shell sandbox.

## Custom app shortcuts (Super + A)

`Super + A` opens the archenemy settings menu: a list grouped by area with each entry's current value, and a preview of the selected entry on the right (hidden in narrow terminals). Arrow keys and Enter move around; pressing an entry's letter opens it directly. Colours follow the active rice, with one accent per rice and at least 4.5:1 contrast (`tests/tui-contrast.sh`). Its first job is app shortcuts: you pick a key (e.g. `g`, `F5`, `semicolon`, `SHIFT+g`) and a command (e.g. `spotify`), and the shortcut works right away. `[e]` changes the command of an existing bind; `[d]` removes one after a separate confirmation (default No). The manager checks key names against the local XKB header when available, guards against collisions with existing archenemy shortcuts, reloads Hyprland, reads `hyprctl configerrors` and undoes the change if the config breaks, and the `[s]` option shows a full cheat sheet of every current shortcut — what's under each key and which app/action it launches. Your binds go into `config/hypr/appbinds.lua` — a personal file outside git, so they survive `git pull` and switching rice.

**Two more ways in (installer step [8m]).** The same menu shows up in rofi (`Super + R`) as **archenemy** — `install.sh` writes `~/.local/share/applications/archenemy.desktop` (with this machine's absolute path, because `.desktop` files don't expand `~`; an existing file of that name is never overwritten). And in a terminal you can type `archenemy` to run it right there: the installer asks before adding one marked `alias archenemy=…` line to your shared shell file (see below, so it works in bash and zsh), never adds it twice and leaves your own `archenemy` alias alone; an alias added to `~/.bashrc` by an older installer is moved there without asking (a dated copy of `~/.bashrc` is kept). Open a new terminal (or `exec $SHELL`) after installing. The `white-blue_beta` rice has no `Super + A` bind by design — these two entries work there too.

The same TUI has extra entries: `[w]` — shared/decades workspace mode switcher (see "Workspaces"), `[o] audio` — default output and input for all apps, plus `[o] → 3` mpd music output: pipewire (recommended) or an exclusive ALSA `hw:` device for mpd (see "Music stack"), `[p] autostart apps` — pick which apps launch at Hyprland startup from the list of all `.desktop` entries (checkboxes `[x]`/`[ ]`, filter by name via `/text`; the selection lands in `data/autostart-apps.dat`, from which a personal `config/hypr/autostart-apps.lua` is generated — alongside the manual `autostartpersonalisation.lua`, which this layer doesn't touch), `[v] volume bar` — the waybar volume bar style (`line` ━━━━━━────, `ticks` ▮▮▮▮▮▮▯▯▯▯, `solid` ▬▬▬▬▬▬▬▬▬▬▬▬────────), saved in `data/volume-bar-style.dat` and applied immediately (signal 10 to waybar), `[t] timer` — a countdown timer next to the clock (see "Timer"), `[k] keyboard layouts` — pick how many layouts you use (1–4, the XKB maximum) and which ones: a list of European layouts (Polish, English US/UK, German incl. Austria/Switzerland, French, Belgian, Dutch, Spanish, Portuguese, Italian, Slovenian, Croatian, Serbian, Bosnian, Czech, Slovak, Hungarian, Romanian, Bulgarian, Greek, Russian, Ukrainian, Belarusian, Lithuanian, Latvian, Estonian, Finnish, Swedish, Norwegian, Danish, Icelandic, Turkish) or any XKB layout code; an optional second step changes the order. Layout #1 is active after login; `Super + K` cycles through the list and `Super + Ctrl + 1…4` jumps straight to layout #1–4. The list is saved in `data/keyboard-layouts.dat`, written to the personal `config/hypr/keyboard-layouts.lua` (every rice except `white-blue_beta` loads it after its `input` block; without it you keep `pl,us`) and applied with `hyprctl reload`, then read back; `[m] mouse` — speed from `-1.0` to `1.0` in any step, DPI, polling rate, acceleration (`flat` or `adaptive`), scroll speed, natural scroll and left-handed mode. DPI comes in two kinds. With the optional `libratbag` package and a supported mouse, DPI and polling rate are real hardware values written to the mouse's memory and read back. Otherwise you give your mouse's own DPI once and pick a target from 5% to 200% of it: this is speed in disguise, and it is exact only with `flat` acceleration, where pointer speed is `1 + speed` (libinput's flat filter). Everything else is saved in `data/mouse-sensitivity.dat` and `data/mouse-settings.dat`, written to the personal `config/hypr/mouse.lua` (every rice except `white-blue_beta` loads it right after its `input` block) and applied at once with `hyprctl reload`, then read back with `hyprctl getoption` — the TUI says so if Hyprland reports a different value; and `[u] update archenemy` — the repo updater: pick a branch (`dev` — latest changes / `main` — stable releases only), the script runs `git fetch`/`checkout`/`pull --ff-only`, stashing any local changes to git-tracked files with `git stash` for the duration of the pull and restoring them afterward. It reports what really happened: "✓ updated" only when your checkout equals `origin/<branch>`; a failed fetch/pull or a stash that can't be restored is shown as an error (the stash stays in `git stash list`, nothing is lost); local commits on top of origin get a warning. Switching to a branch that doesn't contain what you currently run (e.g. `main` while it's behind `dev`) rolls your configs back, so the updater warns and asks first (`y` to go ahead, default no). The machine and personal layers (monitors, appbinds, autostart, rice, volume bar style...) are outside git, so the update doesn't touch them — your settings stay unchanged by default. At the end it offers to re-run `install.sh` to generate any new machine files. `[c] terminal` — show or toggle Alacritty copy on select (`[selection] save_to_clipboard`) in the active `~/.config/alacritty/alacritty.toml`; only that setting changes, `alacritty.toml.bak` is kept from the first change for rollback, and Alacritty reloads it automatically. The setting must already exist, and the file must resolve outside the repository: the default rice symlink is refused. To use this toggle, keep a personal Alacritty configuration outside the repo.

`[n] monitors` changes resolution, refresh rate, scale and position without running the installer. A map shows how the screens sit in space. You pick the resolution, then the refresh rate available for it (or `p` preferred, `h` highest resolution, `f` highest refresh rate). The scale prompt lists the values that divide that resolution cleanly. Position is the top left corner in logical pixels, so a 3840x2160 screen at scale 2 is 1920 wide: type `XxY` (negative values work), `auto`, or `l 2`, `r 2`, `a 2`, `b 2` for left of, right of, above or below monitor 2. Overlapping positions are refused, because Hyprland would not register them. When a screen changes size and keeps its position, the monitors attached to its right and bottom edges move with it. The change starts as a trial: press `y` or select Yes within 15 seconds to keep it; No, Esc, timeout or closing the window restores the previous setting, because a wrong mode can leave you with a black screen. A new resolution generates matching dither-flux wallpapers in the background.

**Connecting a new monitor needs no installer run.** Hyprland shows it right away with safe defaults, and a notification points to `[n]`, where it is listed as `new`. Pick it, confirm the mode, position, scale, wallpaper role and numbering, then press `y`. It gets its own monitor and workspace rules and a wallpaper. A monitor moved to another port is not new: it keeps its settings, because it is recognised by its EDID description.

In the same menu, `r` renumbers monitors left to right, and picking an unplugged monitor offers to forget it, which frees its number and workspaces. In `decades` mode, windows on a monitor whose workspace numbers changed move along with it. In `shared` mode open windows stay on their workspaces.

`[h] shell` picks your shell and keeps your commands in one place. Your aliases, functions, environment variables and `PATH` live in `~/archenemy/config/shell/shellrc` — a personal file outside git, so `git pull` and the updater never touch it (back it up like your dotfiles). `~/.bashrc` and `~/.zshrc` only load it through a short marked block (`# >>> archenemy shell >>>` … `# <<< archenemy shell <<<`), so when you switch shells your commands come along. The file has a "common" part that both shells must understand (`alias`, `export`, `PATH=…`, simple functions) and "bash only" / "zsh only" sections at the bottom for things like `shopt` or `setopt`. In the menu:

- `1` opens the file in neovim. After you save and quit it runs `bash -n` (and `zsh -n` when zsh is installed); on a syntax error it shows the message and lets you edit again, restore the version from before the edit, or keep it. Changes apply to new terminals, or run `exec $SHELL` in the current one.
- `2` opens a list of login shells: bash and zsh, with the current shell highlighted. Choosing zsh installs it after asking (`sudo pacman -S --needed zsh`), creates `~/.zshrc` with the block (or adds the block to yours) and loads `config/shell/zsh-defaults.zsh` first: history, completion, bash-like keys and prompt, no frameworks. It then offers to move your `~/.bashrc` lines into the shared file and asks before changing your login shell with `chsh` (it asks for your password). Success means your passwd entry shows the new shell, and the menu tells you how to get back: the same entry again, or `chsh -s /bin/bash`. Log out and back in afterwards.
- `3` moves the plain one-line `alias`, `export` and `NAME=value` lines from `~/.bashrc` into the shared file, with the comments right above them, after showing them and asking. It stays visible when there is nothing to move and reports that state. The prompt (`PS1`), bash history settings, functions, `if`/`for` blocks, `shopt` and `source` lines stay in `~/.bashrc`.
- `4` sets the zsh vi-mode key. It defaults to `Ctrl+X Ctrl+V`, which zsh already binds to `vi-cmd-mode`; choose another combination or restore that default. Press the keys at your own pace and finish with Enter; a 30-second idle timeout cancels, and a standalone Escape goes back. The TUI checks documented defaults, live zsh bindings when zsh is installed, and visible `bindkey` entries in your shell files, then asks before replacing or overlapping a binding. The personal `keys.zsh` is loaded after zsh defaults and before `shellrc`, so manual bindings in your file take precedence. Bash is unaffected.

- `5` opens **zsh plugins**: `[x]` means enabled by archenemy, `[ ]` means disabled. ↑/↓ or `j`/`k` move; Space or Enter toggles; Esc returns. Options: `zsh-autosuggestions` (recommended: gray history suggestions), `zsh-syntax-highlighting` (valid/invalid command colors), and `zsh-completions` (additional completions, active while the package is installed). All start disabled. Missing packages are offered with `sudo pacman -S --needed <package>` and a separate `[y/N]` confirmation. CLI tool packages use `[Y/n]`; both menus show their default explicitly and Esc cancels. After a successful switch to zsh, the menu offers autosuggestions with `[Y/n]`; installing its package still requires `[y/N]`.

Plugin choices live in the gitignored personal `config/shell/plugins.zsh`, written only by `scripts/shell/lib/shell-rc.sh`. Each generated file carries a SHA-256 checksum independent of the current template; legacy unsigned files are recognized against the frozen v1 text. Changes keep `plugins.zsh.bak-<date>`; identical saves do nothing, and custom content or symlinks are refused. The shared zsh defaults register enabled completion paths before `compinit`, then load plugins after `shellrc` and CLI initialization in the managed rc block, with syntax highlighting last. Older rc blocks keep the previous plugin load order until a plugin toggle in `[h] → 5` refreshes them. User code after that block still runs later; place custom widgets before the block to have them available when highlighting loads. Missing plugin files are skipped, and plugin configuration variables are left to the user. The shell summary lists enabled choices. Open a new terminal to apply a toggle; disable it in the same menu to undo it. Packages are kept: completions already available through your system or personal `fpath` remain available independently of this menu. Arch installs extra completions in [`/usr/share/zsh/site-functions`](https://archlinux.org/packages/extra/any/zsh-completions/files/); plugin ordering follows the [upstream instructions](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md).

`6` opens **CLI tools**, then a shell picker (bash/zsh) and a checklist with each tool's SPDX license. All choices start disabled, independently for each shell. ↑/↓ or `j`/`k` move, Space/Enter toggles, and Esc/`q` returns. Unsupported tools remain visible as unavailable. If a command is missing, `[Y/n]` asks before running `sudo pacman -S --needed <package>`; refusal or failed installation leaves it disabled. No package is removed when you disable a choice. Ordinary programs (`fd` and `rg`) remain in PATH for both shells once installed; their switches record your choices without adding aliases or initialization.

The gitignored personal `config/shell/cli-tools.bash` and `cli-tools.zsh` hold marked blocks, written only by `shell-rc.sh` with dated backups and identical saves left unchanged. Custom content or symlinks are refused. The selected shell's rc block loads its file after `shellrc`; opening a new terminal applies changes. Disable a tool in the same menu to remove its block. zoxide uses `eval "$(zoxide init bash)"` / `eval "$(zoxide init zsh)"`, providing `z`/`zi` while preserving `cd` ([upstream setup and flags](https://github.com/ajeetdsouza/zoxide#installation)). Interactive `zi` additionally needs optional `fzf`, which this menu does not install.

| Tool | Upstream | SPDX license | Distribution |
|---|---|---|---|
| fd | [sharkdp/fd](https://github.com/sharkdp/fd) | MIT OR Apache-2.0 | installed from the distribution package, not bundled |
| ripgrep (`rg`) | [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) | MIT OR Unlicense | installed from the distribution package, not bundled |
| zoxide | [ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide) | MIT | installed from the distribution package, not bundled |

See [THIRD-PARTY.md](THIRD-PARTY.md). Extend the menu with one row in the trusted, tracked `config/shell/cli-tools.tsv`: name, repository URL, SPDX license, pacman package, command checked with `command -v`, comma-separated shells, bash initialization, zsh initialization. Separate the eight fields with tabs; empty initialization fields are allowed. Initialization is one line of shell code, executed only by the selected shell after enabling. No TUI logic changes are needed. Add the corresponding package to the optional package list and document its license when publishing a new catalog entry. Generated files carry a SHA-256 checksum (coreutils) so catalog/template updates can regenerate them with a backup; manually changed content is refused. Unsigned v1 files are recognized using the frozen `cli-tools-v1.tsv` catalog.

In `[h]`, syntax-error recovery keeps `e` for edit and `r` for restore; `3` keeps the file with its error (`k` moves the cursor). Piped input works without a TTY, and EOF cancels a list. See "Settings menu navigation" for the shared controls.

Every change to `~/.bashrc` or `~/.zshrc` keeps a dated copy next to it (`~/.bashrc.bak-<date>`), a `~/.bashrc` that is a symlink (e.g. GNU stow) stays a symlink, and repeating an unchanged managed-file save makes no further change. An incomplete marked rc block is refused rather than overwritten. `install.sh` (step [8m]) creates the shared file and adds the block to `~/.bashrc` silently; it also refreshes an existing managed `~/.zshrc` block. It asks separately about the `archenemy` alias, migrates its own legacy alias automatically, and leaves shell selection and migration of your other lines to `[h]`.

`[i] diagnostics` runs a read-only check of the generated config against the connected monitors, and saves workspace and GPU dumps as `~/archenemy-diag-*.txt`. Those files list your hardware, including monitor serial numbers, so keep them private.

Volume: waybar's `pulseaudio` module has been replaced with a custom `custom/volumebar` (script `scripts/waybar/volume-bar.sh`) — it draws a fill bar with a percentage instead of just an icon. Scrolling on the bar and volume keys work as before (hardware keys additionally send waybar signal 10 = instant bar refresh). Click: left-click opens `pavucontrol`, right-click mutes. Three styles selectable in `Super+A` → `[v]`: `line` (thin bar, 10 cells), `ticks` (▮▮▯ segments, 10 cells), and `solid` (a thick volume block on a thin line, longer — 20 cells, 5% per cell). The `>100%` state (boost) has its own color class per rice. The speaker icon automatically switches to headphones when the default sink's Active Port (from `pactl`) points to a headphone output — and switches back on unplug; detected in the same `interval:1` backstop, no separate trigger. The headphone glyph itself sits lower than the speaker and mic glyphs in Iosevka, so the script nudges it up with a pango span (`rise`) — the correction height is a single `ICON_RISE_HEADPHONES` constant at the top of `volume-bar.sh` (positive = up, negative = down, `0` = no correction).

Power profile: the `custom/profileswitcher` module shows the current profile, and clicking cycles through them. On ASUS ROG machines the **top hardware profile key** (`XF86Launch4`) does the same thing — since 2026-09-07 it goes through the same path as a click, i.e. `scripts/waybar/profile-switch.sh`: the change is verified against `/sys/firmware/acpi/platform_profile`, with an automatic fallback to `power-profiles-daemon` if `asusd` is dead, and if nothing works a critical notification shows the tool's actual error. Previously the key called raw `asusctl`, which can exit with code 0 without changing anything (client newer than the daemon after an update without restarting `asusd`) — the bar would refresh, the profile would stay the old one, and the key would look dead. The bind is in the machine layer (`config/hypr/hardware-keys.lua`, generated by `install.sh`), so it needs another installer run after a repo update.

### ASUS laptops

`install/asus-installation.sh` (run by the installer, or on its own any time) installs `asusctl` and `rog-control-center` with pacman from the official repo, so they update with a normal `pacman -Syu` and nothing compiles on your machine.

Why not the AUR: it has several packages that all claim to be `asusctl` and exclude each other, and some are dead. The script handles them like this:

| Found on your machine | What happens |
|---|---|
| `asusctl-devel-git`, `asusctl-git`, `asusctl-x11`, `asusctl-nosystemd`, `rog-control-center-x11`, `rog-control-center-nosystemd` | pacman asks to replace them in one transaction, answer `y`. If it fails, you keep what you had. |
| `supergfxctl`, `supergfxctl-git`, `plasma6-applets-supergfxctl`, `asusctltray-git`, `asusctl-nosystemd-dinit` | Listed with a question, default no. `supergfxctl` stays unless it is in `Hybrid` mode, because removing it in `Integrated` could leave the graphics card off. |

Graphics switching needs nothing extra: the asus-linux guide says `supergfxctl` is not needed with current drivers. Users who added the `[ogc]` repo get the packages from there. `asusd` is started by a udev rule at boot and is not meant to be enabled, so the script starts it once and checks that it runs; if it does not, restart the computer. The power profile scripts use the `asusctl profile next` / `profile get` subcommands (asusctl 6.3.8+).

Screen brightness: the `XF86MonBrightness*` keys call `swayosd-client` — they change brightness and show an OSD bar at the bottom of every monitor (the `swayosd-server` starts with each rice and is restarted when switching rice, since it only reads the theme at startup). Per-rice OSD theme: `rices/*/swayosd/style.css` (beta inherits from white-blue via symlink). Package: `swayosd-git` (AUR).

## Music stack (optional — a recommendation, not a requirement)

Nothing here is required: `mpd`, `mpc`, `ncmpcpp` (and `mpv`) live in `packages/additional-packages-pacman.txt`, so they only get installed when you pick them in the installer's "additional packages" menu. Pick **mpd + mpc + ncmpcpp together** — they are one stack (daemon, CLI, TUI client); `mpv` is independent. Without the binaries the linked rice folders `ncmpcpp/` and `mpv/` are unused and installer step **[8l]** is silently skipped.

**What each non-beta rice ships.** `rices/<rice>/ncmpcpp/config` — a skin based on **terminal colors**: ncmpcpp takes its colors from the terminal, so every rice's config just assigns roles (list text, header, accent, dim lines, progress bar, now-playing line, visualizer gradient) to that rice's ANSI palette from `alacritty/alacritty.toml`. Numbers in the config are ncmpcpp's own 1-based indexes: `1`–`8` = ANSI 0–7, `9`–`16` = the bright half (`9` bright black, `13` bright blue, `15` bright cyan, `16` bright white) — ncmpcpp maps number N to ncurses color N−1, and `:b` (bold) does not give you bright colors in alacritty. The skin also sets ncmpcpp's working and lyrics directories and connects its stereo visualizer to `/tmp/mpd.fifo` (`Visualizer feed`). It leaves the visualizer type and bar glyphs at their defaults; song-column and selection formats assign palette colors. The skin therefore looks right in the rice's alacritty and simply takes another terminal's palette elsewhere — same as the nvim themes. Key bindings are **vim-like** (`j`/`k`, `h`/`l` for columns / master–slave screen / directories, `g`/`G`, `Ctrl-d`/`Ctrl-u`, `/` `?` `n` `N`, `J`/`K` move selected items, `d` delete; displaced defaults: lyrics `L`, jump-to-position `Ctrl-g`, jump-to-browser `Ctrl-b`) in `rices/white-blue/ncmpcpp/bindings`; the other rices point at it with a relative symlink committed to the repo. `rices/<rice>/mpv/mpv.conf` holds **only** the OSD colors (`osd-color`, `osd-outline-color`) in the rice's palette — no other mpv settings. Note the usual rice-folder rule applies to `~/.config/mpv` and `~/.config/ncmpcpp`: a real directory of yours is moved to `<name>.bak-<timestamp>` by the installer/switcher, never deleted.

**Layers.** `config/mpd/mpd.conf` is the shared layer (`~/Music`, all state in `~/.local/state/mpd/`, a `fifo` output named `Visualizer feed` that feeds ncmpcpp's visualizer, `bind_to_address localhost`, `restore_paused yes`). It `include`s two generated, gitignored files: `config/mpd/output.conf` — the **machine layer**: the actual audio output (`pipewire` by default; rewritten by `Super+A → [o]`) — and `config/mpd/local.conf` — the **personal layer** (`include_optional`): put your own `music_directory`, extra outputs etc. there. ncmpcpp's working files (`error.log`, `patterns.list`, lyrics) go to `~/.local/share/ncmpcpp/` — the rice folder is a symlink into this repo, so `ncmpcpp_directory` must stay outside it (`ncmpcpp` appends to that directory).

**Installer step [8l] never breaks an existing setup.** It runs only when `mpd`/`ncmpcpp` are installed and: generates `output.conf`/`local.conf` only if missing; links `~/.config/mpd → config/mpd` **only if you have no mpd config** — an existing `~/.config/mpd` (or `~/.mpdconf`, `~/.mpd`) is left alone unless you answer `y`, and then it is kept as `~/.config/mpd.bak-<timestamp>`; enables the **user** service only after asking (`systemctl --user enable --now mpd`) and not at all when a **system-wide** mpd is enabled (two daemons would fight over port 6600 and the sound card); copies `ncmpcpp.desktop` to `~/.local/share/applications/` only if there is none (it makes ncmpcpp show up in rofi's `Super+R` and in `Super+A → [p]`; it starts `alacritty --class ncmpcpp -e ncmpcpp`). A second run is a no-op. Music from mpd goes through PipeWire like any app: volume keys/waybar apply to it and the music-reactive wallpapers (♪) react to it with no extra setup.

**Audio output: pipewire is recommended.** `Super+A → [o] → 3` switches mpd's output between `pipewire` and an exclusive ALSA `hw:C,D` device (listed from `/proc/asound`, with a "busy" hint when something — usually PipeWire — holds it). Read the warning before choosing ALSA: while mpd holds the card, notifications, the browser, volume keys and the ♪ wallpapers may lose audio, and if PipeWire holds the card first, mpd cannot open it. The switch rewrites `output.conf`, restarts `mpd.service`, runs a 1-second test play, puts playback back as it was and, if mpd reports an error, **rolls back to pipewire on its own**; it never stops or restarts PipeWire/WirePlumber — that would take the whole desktop's audio with it. ALSA output uses `mixer_type "software"` so mpd never turns the hardware mixer knob underneath PipeWire. Releasing the card from PipeWire for bit-perfect playback is deliberately left as a manual, out-of-archenemy step. The menu refuses to act when mpd would not read the change (`~/.config/mpd` not linked, or mpd running as a system service). After switching it plays one second from your queue on the main output alone, with the visualizer `fifo` output disabled for the test: mpd reports an output error only when no output opens, and the fifo always opens, so otherwise a dead output would look like success. An empty queue is reported as "not verified", never as success.

## Bluetooth (optional)

Step [10] offers Bluetooth with bluez, bluez-utils, dbus (`dbus-monitor`) and
bluetui from Extra. Nothing is enabled by default. The separate installer
`install/bluetooth-installation.sh` verifies installed packages and that
`bluetooth.service` is both enabled and active before creating
`data/bluetooth-enabled.dat` (machine state, covered by `/data/` in `.gitignore`).
Failures appear in the installer summary with a command to retry.

Reload waybar after installation (or switch rice with `Super+T`). The five
non-beta rices include `custom/bluetooth`; it emits empty text without the
flag, required commands or a controller. With a controller it shows off,
on or connected, with connected device names in the tooltip. Updates come
from BlueZ D-Bus events, including controller hotplug and daemon restart;
there is no polling interval. The stream follows the [custom module contract](https://man.archlinux.org/man/waybar-custom.5.en)
and uses [bluetoothctl](https://man.archlinux.org/man/bluetoothctl.1.en) and
[dbus-monitor](https://man.archlinux.org/man/dbus-monitor.1.en). Left-click opens a floating Alacritty running
bluetui, right-click toggles controller power. Power off keeps the off icon;
removing the controller hides it. Beta remains frozen. There is no Bluetooth
entry in `Super+A` yet. Removing the flag and reloading waybar hides the icon
without disabling the service; stream processes also accept SIGUSR1 to reread it.

Live-only: in each of the five rices inspect the icon, connect headphones,
check the tooltip and both clicks, remove/replug the controller and verify
`systemctl is-enabled bluetooth` and `systemctl is-active bluetooth` after reboot.

## Timer

An optional countdown timer, as a **separate island just to the right of
the clock** (its own pill, not glued onto the clock). Disabled by default —
enable it in `Super + A` → `[t] timer`, which also sets the default duration
(25 min by default) and the digit color: **red `#ff0000` regardless of
rice**, changeable to any `#rrggbb` typed into the TUI. The color goes
through pango straight from the script, so only the digit color changes —
the pill underneath stays in the rice's palette.

Bar controls: **left-click** start / pause / resume (and on a timer that's
reached zero — dismiss the alert), **right-click** reset to the default
duration, **scroll** ±1 minute (only works while the timer is stopped or
paused — scroll doesn't touch a running countdown). One notification fires
(`notify-send`) when it reaches zero. The countdown is computed from the
wall clock, so reloading waybar or switching rice doesn't shift it.
Disabling the timer in the TUI hides the module entirely — the clock then
returns to exactly the center of the bar.

Settings and state live in the machine layer (outside git):
`data/timer-enabled.dat`, `timer-duration.dat`, `timer-color.dat`,
`timer-state.dat`. `white-blue_beta` doesn't have the timer (the rice is
frozen — bugfixes only).

## Keyboard shortcuts

These tables describe the five non-beta rices. `white-blue_beta` retains its legacy binds: it has no built-in `Super+A`, `Super+Tab`, `Super+Ctrl+1…4` or power-menu bind. Open settings there through rofi or the `archenemy` alias.

### Apps

| Shortcut | Action |
|---|---|
| `Super + Enter` | Terminal (Alacritty) |
| `Super + E` | File manager (Thunar) |
| `Super + R` | App launcher (Rofi) |
| `Super + B` | Browser (Brave) |
| `Super + S` | Game launcher (Steam) — if installed |
| `Super + N` | Network manager (with Wi-Fi rescan) |
| `Super + T` | Rice switcher |
| `Super + W` | Wallpaper switcher |
| `Super + L` | Lock screen (hyprlock) |
| `Super + K` | Switch keyboard layout (next on your list) |
| `Super + Ctrl + 1…4` | Switch straight to keyboard layout #1–4 of your list (`Super + A` → `[k]`) |
| `Super + A` | Settings menu: app shortcuts, audio, monitors, keyboard, autostart, diagnostics |
| `Super + right Shift` | Power menu (shutdown / restart); with the screen locked (hyprlock) — direct shutdown, no menu or confirmation |

### Window control

| Shortcut | Action |
|---|---|
| `Super + Q` | Close window |
| `Super + Tab` | Reopen the most recently closed app — press again to go further back (see below) |
| `Super + V` | Toggle floating |
| `Super + F` | Fullscreen |
| `Super + Shift + F` | Maximize (bar stays visible) |
| `Super + P` | Pseudo-tiling |

**Reopening closed apps (`Super + Tab`).** Hyprland forgets a window the moment it closes, so a small daemon (`scripts/hypr/window-history.sh daemon`, started from the shared `autostart-common.lua` in every rice) remembers, for every open window, the command line and working directory of its process while it is still alive. When an app's last window closes, it goes onto a per-session stack (20 entries, newest on top); `Super + Tab` relaunches the newest one on the current workspace, in the same directory, with the same arguments — like `Ctrl + Shift + T` in a browser, each press goes one step further back. What it deliberately does not do:

- **An app that is still running is skipped** (a window closed to the tray — Steam, Discord — or a dialog of a portal / polkit agent): relaunching it would start a second copy of a background process. Closing one of several windows of the same app (e.g. one of two browser windows) is not recorded either — the app is still open; use the app's own "reopen closed window".
- It restarts the program, it does not restore its contents (unsaved text, open tabs — unless the app restores its own session). The window lands where Hyprland puts new windows, not at its old position. The process environment is not replayed.
- Steam games (`steam_app_<id>`) come back through `steam steam://rungameid/<id>`, Flatpak apps through `flatpak run <id>`; archenemy's own tool windows (`archenemy-*`, e.g. the Super+A manager) are not recorded.
- The history lives in `$XDG_RUNTIME_DIR` (memory, private to your user) and disappears on logout — command lines can contain file paths, so nothing is written to disk. `window-history.sh list` shows the stack.

### Workspaces — two modes to choose from

Monitors get **numbers 1, 2, 3… counted left to right** (the installer and `Super+A` → `[n]` propose an order based on screen positions; you can correct it), and at install time you pick one of two modes:

**Monitor identity.** Connector names (`eDP-2`, `HDMI-A-1`) are **not stable** — after a reboot or a replug Hyprland may hand the very same screens `eDP-1` and `HDMI-A-3`. Since 2026-09-21 the machine layer therefore targets monitors by their EDID description (`desc:<make model serial>`, saved as `DESCRIPTION=` in `data/monitors/<name>.dat` by step [3]): `monitorshyprl.lua`, `workspaces-monitors.lua`, `hyprpaper.conf` and the orphan guard all use that selector, which Hyprland, hyprpaper and hyprlock match by prefix. The connector name is still stored (it decides which monitor is the built-in panel, and it names the generated `dither-flux` files). `.dat` files from before that date have no description — re-run `install.sh` once after pulling, otherwise the rules keep targeting the old connector names and, after a rename, both monitors fall back to `preferred`/`auto` and all workspaces end up orphaned (the bar shows `21`, `22`…).

The `desc:` selector is used **only when it is safe**: the description must be non-empty, free of characters that would break Lua/hyprlang (`"`, `\`, `#`, `=`), free of control characters, and **unique among the detected monitors** — two identical monitors without a serial number would both match the same prefix, so in that case (and for virtual/headless outputs without EDID) the installer keeps connector names for them and says so. Every edge case therefore degrades to the pre-2026-09-21 behaviour, never below it. If the rules were wrong for a while (old connector names), Hyprland has already given the live monitors the first free numbers outside the decades — `21`, `22` on the bar — and a `hyprctl reload` never moves existing workspaces. The orphan guard (decades mode) handles that too: a workspace with **no rule at all** sitting on a monitor that owns a decade is merged into that decade (`21` on the HDMI with `11–20` → `11`), the same way orphans of an unplugged monitor are. At session start `scripts/hypr/machine-layer-check.sh` (read-only, started from the shared `workspaces.lua`) verifies that the generated files still match the connected monitors and shows a single notification with the fix (`re-run install.sh`) when they don't — an unplugged external monitor is not an alarm. A mismatch is reported when no rules match, a connected monitor lacks its own rule, or required generated files are missing.

- **`shared`** — 10 workspaces (1-10) shared across all monitors. Monitor number k has workspace k as its "home" (that's where it opens on startup), but `Super + 1..0` works globally — you summon a workspace onto whichever screen you're on. Resilient to unplugging a monitor: each workspace always exists exactly once, so nothing gets duplicated.
- **`decades`** — each monitor has **its own** workspaces numbered 1 to 10 (isolated decades). The bar shows only the focused monitor's workspaces, and `Super + 1..0` works within the focused monitor. External monitors' decades follow the left→right numbering; exception: the laptop's built-in panel (eDP/LVDS/DSI) always keeps the first decade — it's the only screen guaranteed to exist, otherwise working without an external monitor would create orphaned workspaces (a double "1" on the bar). When a monitor is unplugged, a guard daemon merges its workspaces (windows from workspace N land on N); when it's replugged, the monitor gets its own back.

You can switch the mode **live** in the TUI under `Super + A` → `[w] workspace mode` (no need to re-run the installer): it regenerates the workspace rules and binds, reloads Hyprland, and starts the guard daemon if needed. Monitor numbering can be changed in `Super+A → [n]` or `install.sh`; the mode uses that saved order. Note: a reload doesn't move already-open windows — for a clean resort (especially decades' `defaultName`) log out and back in, or move windows manually. The shortcuts work the same in both modes — only the scope differs:

| Shortcut | Action |
|---|---|
| `Super + 1..0` | Go to workspace 1–10 (shared: globally / decades: on the active monitor) |
| `Super + Shift + 1..0` | Move window to workspace 1–10 |
| `Super + Ctrl + ←/→` | Cycle through workspaces |
| `Super + scroll` | Cycle through workspaces |

### Focus

| Shortcut | Action |
|---|---|
| `Super + arrows` | Move focus |
| `Super + Shift + arrows` | Move window |
| `Super + Alt + arrows` | Resize window |
| `Super + .` | Focus next monitor |
| `Super + ,` | Focus previous monitor |

### Mouse

| Shortcut | Action |
|---|---|
| `Super + left-click` | Move window |
| `Super + right-click` | Resize window |

### Screenshots

| Shortcut | Action |
|---|---|
| `Print` | Selection screenshot → clipboard |
| `Super + Print` | Selection screenshot → ~/Screenshots |

### Settings menu navigation

`Super+A` uses ↑/↓ and Enter; an entry's letter opens it immediately, and Esc or `q` exits. Shared choice menus use `scripts/appbinds/lib/tui.sh`: ↑/↓ or `j`/`k` move, Enter selects, Esc returns. Existing letter and numeric shortcuts remain. Lists longer than nine items collect the full number followed by Enter and scroll to fit the terminal; EOF cancels.

Yes/no menus use the same navigation: Enter keeps the displayed default, `y`/`n` answer immediately, and Esc or EOF cancels. Digits cancel confirmations. Removing an app bind requires confirmation with default No. Monitor trials share one 15-second deadline; No, Esc, timeout or SIGHUP restores the previous monitor data and generated rules.

- `[n] monitors`: arrows work for monitor, resolution, refresh rate, numbering, wallpaper roles and forgetting a monitor; `p`/`h`/`f`/`r` shortcuts remain. Scale, position and other text fields still require typed input.
- `[m] mouse`, `[k] keyboard`, `[v] volume bar`, `[o] audio`, `[t] timer`, `[h] shell` and `[i] diagnostics`: selection screens use the shared menu. Numeric values, custom XKB codes, layout order, timer duration and color remain text fields. The vi-mode key capture in `[h] → 4` finishes with Enter.
- `[p] autostart`: arrows or `j`/`k` navigate, Space/Enter toggle apps or open action rows. `/text`, global app numbers (including `1 2` and numbers on other pages), `n`/`p` pages, `s` save and `q` cancel remain available. Action rows have no numeric labels; discarding changes asks for confirmation.
- `[h] → 5` plugins and `[h] → 6` CLI tools: Space/Enter toggle checkboxes; Esc returns. Missing plugin packages require a separate `[y/N]`, CLI packages a separate `[Y/n]`.
- `[u] update archenemy`: choose dev/main with arrows and Enter or `1`/`2`. Stashing changes, switching to an older branch and running the installer use yes/no menus.

## Verification

There is no CI pipeline. Run `bash tests/repo-hygiene.sh` for executable bits, Lua dispatch syntax and installer language, or `bash tests/run-all.sh` for all shell suites. Tests use temporary homes, mock commands and temporary git repositories. The flux-wall render checks require `make -C src/flux-wall tools`; without it, `flux-wall-bars.sh` and the render part of `flux-wall-dither.sh` skip. C tests run separately with `make -C src/flux-wall test`.

**Live-only — a real Arch + Hyprland session is required:**

1. Run `~/archenemy/install/install.sh`, review its summary, log in again and inspect `hyprctl configerrors`.
2. Switch rices with `Super+T`; check the bar, notifications, terminal, lock screen, wallpaper and app shortcuts. Check that a saved animation restarts after logout/login and follows the new rice's palette.
3. Open `Super+A`; check `[h]` in newly opened bash/zsh terminals, `[p]` after login, `[u]` on the intended branch, and `[c]` with a personal Alacritty config outside the repo. A rice symlink must be refused.
4. In `[n]`, try a monitor change and let its 15-second confirmation expire; verify restoration. Replug a monitor, check `[w]` shared/decades workspaces and `Super+W` on every output. Run `hyprctl hyprpaper listactive` to compare the active images.
5. On applicable hardware, verify the ASUS profile key and bar against the actual profile; if VirtualBox was installed, check `modinfo vboxdrv`, the loaded module and a test VM after any requested reboot. For the optional music stack, test playback and `[o] → 3` with a non-empty queue.
