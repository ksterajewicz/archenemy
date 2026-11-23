<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo/banner-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/logo/banner-light.svg">
    <img alt="archenemy" src="assets/logo/banner-dark.svg" width="640">
  </picture>
</p>

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

Read this whole file. The project replaces folders in `~/.config` — the installer offers to make a backup (it lands in `~/archenemy/backups/`), and linking keeps existing real directories or symlinks outside `rices/` as `<name>.bak-<timestamp>`. Links into an old rice are removed before the new rice is linked. Paths managed by home-manager (links into `/nix/store`) are never replaced, moved or written through: `Super+T` stops before changing anything, and the installer leaves those paths untouched, skips linking in step [9] and names the declaration to remove in the summary (see "Other distributions" → NixOS).

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

`./install.sh --skip-packages` installs no package at all — not Hyprland, yay, the required or optional packages, nor the packages later steps install on their own (power-profiles-daemon, UFW, ASUS tools, drivers, kernels, Bluetooth, VirtualBox); the requirement check still runs and every missing package lands in the summary with the command to install it. Without the flag nothing changes on Arch. On NixOS the flag is always on. Fedora and NixOS: see "Other distributions (experimental)".

The installer covers these steps:

- **[2]–[3.7]**: check Hyprland, detect monitors, choose their modes, positions, scale, wallpaper roles, left-to-right numbering and workspace mode.
- **[4]–[6.5]**: prepare yay, install required and selected optional packages (one unknown name cancels the whole pacman transaction, so a failed optional install is listed in the summary with the retry command), choose the hardware profile (DMI supplies a hint), and offer the CPU microcode, GPU driver and alternative kernel installers. ASUS setup uses `install/asus-installation.sh`; the universal profile switcher uses `power-profiles-daemon`, also available as an ASUS fallback.
- **[7]–[8k]**: offer a backup and generate machine configuration, personal-file stubs, autostart app rules and default bar settings.
- **[8l]–[8m]**: configure the optional music stack when installed (see "Music stack"), add the rofi settings entry and shared shell rc block, and offer the `archenemy` alias. Shell selection stays in `Super+A → [h]`.
- **[9]–[9.7]**: link `white-blue` on a fresh install or the saved rice on a repeat run, initialize or restore the wallpaper, optionally build flux-wall, and generate dither-flux wallpapers in the background.
- **[10]–[11]**: configure NetworkManager and pipewire-pulse, offer UFW, Bluetooth and VirtualBox, reload Hyprland and show the summary. Audio counts as already running only when the same pipewire-pulse unit (socket or service) is both enabled and active and its backend — `pipewire.socket` or `pipewire.service`, and `wireplumber.service` — is enabled and active too; anything less is a ⚠ with the `systemctl --user status …` command and a summary entry, without changing anything. The UFW question says what enabling it changes (incoming connections blocked, strict reverse-path filtering from `/etc/ufw/sysctl.conf`, LAN hosting such as Steam Remote Play needs `sudo ufw allow …`); an already active UFW is not asked about again — its policies and rules stay as they are and the installer only prints them. The closing banner says "Everything is set up" only when nothing was skipped or failed; otherwise it gives the number of items marked ⚠ in the summary. Before offering the reload it reminds you to log out and back in once after the first install: the bar, wallpaper, notifications and clipboard start with the Hyprland session (`hl.on("hyprland.start")`), which a reload does not run. VirtualBox uses `install/virtualbox-installation.sh` for DKMS, installed-kernel headers, module checks and optional `vboxusers` membership; a reboot requirement is reported separately.

Installer prompts, status messages, summaries and descriptions emitted directly by `install/*.sh` into generated files use English. `tests/repo-hygiene.sh` checks installer message lines for Polish letters while allowing code comments.

**Updating an existing machine after `git pull`?** Run `install.sh` again — it will generate any missing machine files. The monitor survey ([3]–[3.7]) writes the new `data/monitors/*.dat` into a temporary `data/monitors.new.*` folder and swaps them in only after the last question, so Ctrl-C mid-survey leaves the previous set intact; so does closed input (Ctrl-D, or a pipe that runs out) at the workspace-mode question [3.7], which has no default — the installer stops with code 1 instead of asking forever. Every step reports what actually happened: package installs, `ufw`, `systemctl enable`, the bootloader regeneration in the CPU/kernel installers and the final `hyprctl reload` print ✓ only after checking the result, otherwise the step lands in the summary with the command to finish by hand.

## How this is organized — four layers

| Layer | Where it lives | In git? |
|---|---|---|
| **Rice** (looks) | `rices/<name>/` — folders symlinked into `~/.config` | ✅ |
| **Shared** (shortcuts, media keys, shell defaults, music config) | Tracked `config/hypr/*.lua`, `config/shell/zsh-defaults.zsh` and shell catalogs, `config/mpd/mpd.conf` | ✅ |
| **Machine** (monitors, GPU, hardware keys) | `config/hypr/monitorshyprl.lua`, `workspaces-monitors.lua`, `hardware-keys.lua`, `gpu-env.lua`, `hyprpaper.conf`, `hyprlock-background-<rice>.conf`; `config/mpd/output.conf` — generated locally | ❌ |
| **Personal** (your autostart, your app shortcuts, mouse sensitivity, keyboard layouts, your shell aliases, zsh vi key, plugins and CLI choices; your font choice lives outside the checkout in `~/.config/archenemy/fonts/`, see "Fonts") | `config/hypr/autostartpersonalisation.lua`, `config/hypr/autostart-apps.lua`, `config/hypr/appbinds.lua`, `config/hypr/mouse.lua`, `config/hypr/keyboard-layouts.lua`, `config/shell/shellrc`, `config/shell/keys.zsh`, `config/shell/plugins.zsh`, `config/shell/cli-tools.bash`, `config/shell/cli-tools.zsh`, `config/mpd/local.conf` | ❌ |

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
├── AGENTS.md                        # Rules for AI agents working on this repo (layers, pitfalls, tests).
├── CONTRIBUTING.md                  # Contribution rules: GPL-3.0-or-later inbound = outbound, third-party files.
├── .github/workflows/tests.yml      # CI: tests/run-all.sh in an archlinux container (see "Verification").
├── LICENSE                          # GPL-3.0-or-later: unmodified GPLv3 text from the FSF (gnu.org).
├── LICENSES/
│   └── Apache-2.0.txt               # Full Apache-2.0 text for the lazy.nvim bootstrap snippet (see THIRD-PARTY.md).
├── THIRD-PARTY.md                   # Bundled third-party files (Wayland protocol XML, lazy.nvim bootstrap,
│                                    #   networkmanager-dmenu config, ZLE table): source, version, license
│                                    #   and full notices; optional CLI tools installed from packages.
├── assets/
│   └── logo/                         # The project mark Æ (own SVG geometry, no fonts): archenemy-ae.svg (white base),
│                                     #   rices/<rice>.svg (same shape in each rice's colour, yang included);
│                                     #   banner-dark.svg / banner-light.svg (mark + wordmark, top of this README),
│                                     #   wordmark-white.svg / wordmark-black.svg (no background), PNG renders,
│                                     #   social-preview.svg/.png (uploaded by hand in the repo settings);
│                                     #   README.md — what each file is, colours and where each one comes from.
├── install/
│   ├── install.sh                    # Main installer. Walks you through the whole setup.
│   ├── bootloader.sh                 # Library: detects the bootloader and regenerates its config (GRUB
│   │                                 #   auto, systemd-boot = manual instructions). Sourced by cpu/kernel.
│   │                                 #   Outside Arch regenerate_bootloader only prints instructions (code 2).
│   │                                 #   CPU/kernel/GPU installer exit codes are a contract with step [6.5]:
│   │                                 #   0 done or declined, 1 failed, 2 boot entries need manual steps.
│   ├── cpudrivers-installation.sh    # CPU microcode (Intel/AMD) — detects the CPU, installs it, regenerates the bootloader.
│   │                                 #   Outside Arch: Fedora/NixOS instructions only, exit 2 (also kernel-install.sh).
│   ├── gpudrivers-installation.sh    # GPU drivers — detects the card (PCI class 03xx, `lspci -d ::03xx`,
│   │                                 #   same filter as gpu-env.lua in [8d]); NVIDIA: open/proprietary, modeset,
│   │                                 #   initramfs; if a driver is already installed: update (-Syu) / switch variant.
│   │                                 #   For gaming: enables the [multilib] repo and installs lib32 (Steam/Proton/Wine).
│   │                                 #   Exits 1 when any step printed ✗ (pacman, lib32, initramfs).
│   │                                 #   Outside Arch: Fedora/NixOS instructions only, exit 2 (see "Other distributions").
│   ├── kernel-install.sh             # Installs an alternative kernel (zen/lts) + regenerates the bootloader.
│   ├── asus-installation.sh          # ASUS laptops: asusctl + rog-control-center from the official repo,
│   │                                 #   replaces AUR variants, starts asusd (exit codes are a contract with step [6]).
│   │                                 #   Outside Arch: Fedora/NixOS instructions only, exit 2.
│   ├── bluetooth-installation.sh     # Optional Bluetooth + bluetui: verified service and bar visibility flag.
│   ├── system-theme-installation.sh  # Optional login screen (SDDM) and boot menu (GRUB) themes for every rice:
│   │                                 #   only what applies to the machine, a foreign theme is replaced only after
│   │                                 #   its own "y", optional root service that follows rice/logo/wallpaper/login
│   │                                 #   monitor changes, `--remove` undoes everything (see "Login screen and boot menu").
│   ├── lib/aur.sh                    # Library (sourced by install.sh): builds yay in a fresh mktemp dir with an
│   │                                 #   optional PKGBUILD review; AUR installs with opt-in `--diffmenu --answerdiff All`;
│   │                                 #   reviews fall back to more/cat when `less` is missing.
│   ├── lib/pkg.sh                    # EXPERIMENTAL package layer per distribution: install.sh uses it to detect
│   │                                 #   the platform and, on Fedora/NixOS, for steps [2]/[4]/[5]: pkg_detect /
│   │                                 #   pkg_arch_derivative / pkg_route / pkg_gate / pkg_installed / pkg_install /
│   │                                 #   pkg_install_extra / pkg_hint / pkg_version / pkg_min_version over
│   │                                 #   packages/platform-map.tsv — see "Other distributions".
│   └── virtualbox-installation.sh    # Oracle VirtualBox host (optional, asked in step [10]): DKMS modules +
│                                     #   kernel headers, vboxdrv loaded and verified, opt-in vboxusers group.
│                                     #   Outside Arch: Fedora/NixOS instructions only, exit 2.
├── packages/
│   ├── requirements-pacman.txt       # Required packages (official repos).
│   ├── requirements-aur.txt          # Required packages (AUR).
│   ├── additional-packages-pacman.txt # Optional packages (official repos).
│   ├── additional-packages-aur.txt   # Optional packages (AUR).
│   └── platform-map.tsv              # EXPERIMENTAL Arch → Fedora / NixOS package map (data, one row per
│                                     #   list entry, CLI catalog package and ad-hoc install); Arch keeps using the four lists.
├── nix/
│   ├── packages.nix                  # EXPERIMENTAL NixOS / home-manager package list `{ pkgs }: { core fonts build
│   │                                 #   optional }`, GENERATED from platform-map.tsv (nixos=ok rows only) — packages,
│   │                                 #   never options or services; see "Other distributions" → NixOS.
│   └── generate-packages.sh          # Regenerates packages.nix; `--check` = 1 when it is out of date.
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
│                                     #   the closed-apps history daemon behind Super+Tab; the new-monitor
│                                     #   notification, monitor-settings.sh notify).
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
│       # via a symlink), hyprlock-background-<rice>.conf ×7 (one per rice except beta)
│       # (hyprlock background; rices point to it via `source =`)
├── rices/
│   ├── white-blue/                   # Default rice: alacritty, fastfetch, hypr(+hyprlock), mako,
│   │                                 #   MangoHud, networkmanager-dmenu, nvim, rofi, waybar,
│   │                                 #   ncmpcpp (colors + the shared vim-like `bindings`), mpv (OSD colors),
│   │                                 #   swayosd; each non-beta rice also carries flux-wall.conf (palette, default animation,
│   │                                 #   FLUX_WALL_DITHER — Bayer raster on/off in shaders that support it),
│   │                                 #   system-theme.conf (login screen wallpapers and boot menu colours, read as data)
│   │                                 #   and every rice carries preview.png — its picture in the Super+T menu (a generated mock-up;
│   │                                 #   replace it with a real screenshot at the same path).
│   ├── white-blue_beta/              # Original look, kept for reference/rollback (frozen: no ncmpcpp,
│   │                                 #   mpv, flux-wall.conf, timer). mako, hyprlock and swayosd inherit
│   │                                 #   from white-blue (symlinks in the repo).
│   ├── tron/                         # Tron: Legacy — dark neon (cyan + CLU orange), glow,
│   │                                 #   4-6px corners. Own fastfetch (distro logo in cyan) + launcher
│   │                                 #   in the waybar and nvim theme (neon cyan); ncmpcpp + mpv colors;
│   │                                 #   networkmanager-dmenu and ncmpcpp `bindings` from white-blue (symlinks).
│   ├── asia-n-rice/                  # Mauve/pink on navy, flat look. Own hypr, rofi,
│   │                                 #   mako, hyprlock, alacritty, waybar and nvim theme (mauve);
│   │                                 #   fastfetch distro logo in mauve; ncmpcpp + mpv colors;
│   │                                 #   MangoHud/networkmanager-dmenu/ncmpcpp `bindings` from white-blue (symlinks).
│   ├── dither-flux/                  # Dither art + algorithmic art in the rainy
│   │                                 #   milford-water palette: zero rounding, no blur or glow,
│   │                                 #   1px borders, flat panels. Full own layer set (incl. ncmpcpp + mpv colors);
│   │                                 #   networkmanager-dmenu and ncmpcpp `bindings` from white-blue (symlinks).
│   ├── crt/                          # Blue/cyan phosphor palette: glass islands with glow,
│   │                                 #   4px corners, amber #FFB000 for alarms only. Full own
│   │                                 #   layer set (incl. ncmpcpp + mpv colors); networkmanager-dmenu
│   │                                 #   and ncmpcpp `bindings` from white-blue (symlinks).
│   ├── yin/                          # Black with a white accent: frosted glass (translucent alacritty +
│   │                                 #   strong blur), 12px corners, soft black shadows, greys with even
│   │                                 #   lightness steps, ember #E0805A for alarms only. Full own layer
│   │                                 #   set; fastfetch with the distro logo in white and ash, and
│   │                                 #   palette dots; networkmanager-dmenu and
│   │                                 #   ncmpcpp `bindings` from white-blue (symlinks).
│   └── yang/                         # yin inverted: paper with a black accent, light frosted glass
│                                     #   over the negative eclipse, the same backend, layout, 12px
│                                     #   corners and 4px rhythm; greys with inverted lightness, rust
│                                     #   #A23A10 for alarms only. Full own layer set (fastfetch: distro
│                                     #   logo in black and ash); networkmanager-dmenu and ncmpcpp
│                                     #   `bindings` from white-blue (symlinks).
├── scripts/
│   ├── archenemy-doctor.sh           # Public, offline installation diagnostics (`archenemy doctor`).
│   ├── lib/runtime-dir.sh            # Library: the private session directory for locks, state and logs —
│                                     #   $XDG_RUNTIME_DIR, /run/user/<UID> or a 0700 archenemy-<UID> dir in /tmp,
│                                     #   only if ours and private; never a shared /tmp file.
│   ├── lib/hm-conflict.sh            # Library: paths home-manager manages (links into /nix/store, also via a parent,
│                                     #   a link chain or a file inside a real folder) — read-only checks and advice for
│                                     #   lib/switch-rice.sh and install.sh [8l]/[9]; nothing is replaced or moved.
│   ├── shell/                        # shell-settings.sh — Super+A → [h]: bash ↔ zsh (package, chsh),
│   │                                 #   arrow-key menus, editing shellrc in neovim, configuring the zsh vi-mode key, optional zsh plugins and CLI tools for bash/zsh;
│   │                                 #   lib/shell-rc.sh — the shared shell file, rc blocks and personal
│   │                                 #   keys.zsh / plugins.zsh / cli-tools.bash / cli-tools.zsh writer (shared by install.sh [8m] and the TUI).
│   ├── appbinds/                     # Terminal shortcut manager for apps (Super+A); update-archenemy.sh — [u];
│   │                                 #   terminal-settings.sh — [c] copy on select in Alacritty (backup on first change);
│   │                                 #   font-settings.sh — [f] fonts: the rice font or any installed font (lib/fonts.sh;
│   │                                 #   your choice lives in ~/.config/archenemy/fonts/, outside the repo);
│   │                                 #   lib/tui.sh — shared look and keys: rice accent, header, [y/N] prompts,
│   │                                 #   tui_menu — highlighted choices with arrows/j/k, Enter, digits and Esc;
│   │                                 #   yes/no prompts also use arrows/j/k and Enter; y/n shortcuts remain, Esc cancels;
│   │                                 #   lib/mpd-output.sh — mpd output switch and its playback test ([o]);
│   │                                 #   lib/binds.sh — the one place that lists/edits/removes user binds (list and
│   │                                 #   [d] pick the same lines);
│   │                                 #   [w] switches shared/decades workspace mode live;
│   │                                 #   [v] switches the waybar volume bar style;
│   │                                 #   [l] system logo: the distro glyph (default) or the archenemy Æ logo —
│   │                                 #   in the bar, in fastfetch, on the login screen and in the boot menu;
│   │                                 #   [g] login screen: which monitor shows the login form (default: primary);
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
│   │                                 #   Per platform (os-release via install/lib/pkg.sh): pacman on Arch,
│   │                                 #   one `rpm -qa` on Fedora, Nix store paths on NixOS; last line
│   │                                 #   `diagnosis: complete` (exit 0) or `partial; not checked: …` (exit 2).
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
│   │                                 #   lib/hypr-apply.sh — reload checked against configerrors read before the write;
│   │                                 #   lib/gen-autostart.sh — generator for autostart-apps.lua
│   │                                 #   (shared with install.sh and the Super+A → [p] picker).
│   │                                 #   lib/monitor-id.sh — monitor identity for the machine layer:
│   │                                 #   "desc:<EDID description>" selectors instead of connector
│   │                                 #   names (eDP-2 / HDMI-A-1 change between reboots);
│   │                                 #   lua_string/lua_comment put names into generated Lua with
│   │                                 #   control characters escaped, so a CR can't break the file.
│   │                                 #   machine-layer-check.sh — read-only self-check at session start:
│   │                                 #   one notification when the generated files no longer match the
│   │                                 #   connected monitors (instead of Hyprland's silent fallback),
│   │                                 #   and when install-relevant code changed since the last install.sh
│   │                                 #   (data/installed-head.dat vs HEAD — re-run the installer).
│   │                                 #   window-history.sh — Super+Tab: reopens recently closed apps
│   │                                 #   (daemon started from autostart-common.lua + `restore`).
│   │                                 #   polkit-agent.sh — starts hyprpolkitagent from the rices' autostart
│   │                                 #   (no enable; a failure is one quiet log line, always exit 0).
│   ├── rofi/                         # Rofi menus: app launcher (rofi_drun.sh), rices, wallpapers, clipboard history (rofi_clipboard.sh), network (with rescan), power.
│   │                                 #   lib/rofi-preview.sh — PNG previews in Super+W / Super+T (3-column
│   │                                 #   grid with big icons; lazy wallpaper thumbnails in data/thumbs/).
│   ├── wallpapers/                   # lib/dither-flux-sizes.sh — which dither-flux wallpapers the current
│   │                                 #   monitors still need (shared by install.sh and Super+A → [n]).
│   │                                 #   Mathematical wallpaper generators (pure Python, zero dependencies):
│   │                                 #   blue-hex honeycomb (gen_hex_wallpaper.py), Tron grid
│   │                                 #   (gen_tron_wallpaper.py), and generative dither wallpapers
│   │                                 #   for the dither-flux rice (gen_dither_flux_wallpaper.py),
│   │                                 #   oscilloscope Lissajous for crt (gen_crt_wallpaper.py),
│   │                                 #   eclipse for yin (gen_yin_wallpaper.py), its negative for
│   │                                 #   yang (gen_yang_wallpaper.py);
│   │                                 #   gen_rice_preview.py — the rices' preview.png mock-ups for Super+T
│   │                                 #   (drawn from each rice's waybar/alacritty/hypr/flux-wall colors);
│   │                                 #   flux-wall.sh — start/stop the shader-driven wallpaper.
│   └── waybar/                       # Power profile switcher (asus/universal: profile-get.sh /
│                                     #   profile-switch.sh — also the ASUS hardware key path; the switch
│                                     #   itself, verified by reading the profile back: asusprofile.sh /
│                                     #   universalprofile.sh) +
│                                     #   volume-bar.sh — volume bar in place of the pulseaudio module;
│                                     #   line/ticks/solid style switchable in Super+A → [v].
│                                     #   bluetooth.sh — optional D-Bus event stream, power toggle and bluetui launcher;
│                                     #   power choice in data/bluetooth-power.dat, "off" kept until you turn it on.
│                                     #   timer.sh + timer-ctl.sh — countdown timer next to the clock,
│                                     #   optional, enabled in Super+A → [t];
│                                     #   lib/timer-state.sh — shared read/write of timer state.
│                                     #   dnd.sh — do-not-disturb bell: state from `makoctl mode`, click toggles
│                                     #   mako's do-not-disturb mode; "unavailable" icon when mako is not running.
│                                     #   launcher-logo.sh — the system logo: custom/launcher text and class (the
│                                     #   distro glyph from os-release by default, or the Æ logo, Super+A → [l]);
│                                     #   `glyph` prints the distro glyph for the login screen and boot menu themes;
│                                     #   `sync` keeps data/fastfetch-logo.txt (the Æ mark for fastfetch) in step.
├── src/
│   ├── system-theme/                 # login screen (SDDM) and boot menu (GRUB) themes per rice:
│   │   ├── build.sh                  #   builds a rice's SDDM theme, or ONE GRUB theme directory for all rices
│   │   │                             #   (per-rice images, shared fonts, theme-<rice>-<logo>.txt), into any directory;
│   │   ├── system-theme-sync.sh      #   root script (installed as a root-owned copy): applies the rice, system logo,
│   │   │                             #   login monitor and wallpaper; everything read from the home directory is
│   │   │                             #   untrusted data, read with the user's own privileges;
│   │   ├── sddm/<rice>/              #   one login screen layout per rice (Main.qml, theme.conf, metadata.desktop);
│   │   ├── sddm/components/          #   logic shared by all layouts: login, clock, system logo, password field,
│   │   │                             #   login monitor with fallback (Seat.qml), wallpaper with fallback (Backdrop.qml);
│   │   ├── grub/assets.py            #   boot menu images (Æ logo, selection frame) with the Python standard library only;
│   │   └── tools/                    #   render-sddm.sh — dev tool: PNG preview of an SDDM theme (the real Qt6 greeter
│   │                                 #   in test mode under Xvfb, inside a private namespace with a fake user and
│   │                                 #   session, so a picture never shows the machine it was made on; `-m` adds
│   │                                 #   virtual monitors, `-u` unplugs one, `-k` types on the keyboard);
│   │                                 #   render-grub.sh — dev tool: PNG preview of a GRUB theme (the real GRUB as a
│   │                                 #   standalone EFI file in QEMU + OVMF; /boot is not touched). Run by hand,
│   │                                 #   never by install.sh; the packages they need are listed in each header;
│   └── flux-wall/                    # GPU shader-driven wallpaper (C, wlr-layer-shell + EGL/GLES 3):
│       ├── main.c                    #   Wayland/EGL: one surface per monitor, main loop, battery;
│       ├── engine.c / engine.h       #   rendering (GLES, no Wayland): single-pass path
│       │                             #   or the particle engine (accumulative forms — flow field);
│       ├── audio.c / audio.h         #   audio reactivity: FFT from the OUTPUT monitor (libpulse via
│       │                             #   pipewire-pulse), bass/mid/high bands, beat — visualizations only;
│       ├── util.h                    #   shared helpers (monotonic clock, read a regular file) for main/audio/tools;
│       ├── recovery.h                #   decisions after EGL errors (exit 3, retry one surface, new context after
│       │                             #   EGL_CONTEXT_LOST), retry delays and the context-loss limit, without
│       │                             #   Wayland/EGL calls — main.c carries them out, test.c tests them;
│       ├── logic.h                   #   the other pure decisions of main.c (buffer size from the monitor scale,
│       │                             #   frame pacing and the poll timeout, battery detail easing, -o, when the
│       │                             #   audio thread starts), same pattern as recovery.h;
│       ├── cli.h                     #   command-line options (struct config) and flux_parse_args (in main.c);
│       ├── test.c                    #   pure-function tests (palette, battery, #pragma flux, warp, step cap,
│       │                             #   audio DSP, spectrogram/audio-uniform helpers of engine.c, EGL error
│       │                             #   decisions, logic.h, every option of
│       │                             #   flux_parse_args), CLI exit codes 1 and 2,
│       │                             #   the audio thread on a file and on a libpulse mock (output monitor only,
│       │                             #   never the microphone; stream format; retry delays)
│       │                             #   + GL checks on EGL surfaceless (--once after a resize; a shader that
│       │                             #   fails to compile or link → no engine, the basis of exit 3; skipped without EGL);
│       ├── Makefile                  #   protocol code is generated by wayland-scanner from the XML files in the repo;
│       ├── protocols/                #   wlr-layer-shell, xdg-shell, viewporter, fractional-scale-v1
│       │                             #   (XML: MIT, layer-shell HPND-sell-variant — see THIRD-PARTY.md);
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
│                                     #   flux-wall-shaders.sh — static check: every flux-wall shader (.frag files and
│                                     #   GLSL built into engine.c) declares `precision highp sampler2D` before using a sampler.
│                                     #   flux-wall-dither.sh — flux-wall.sh passes --dither only for the active
│                                     #   dither-flux rice (fake binary); offscreen: --dither = palette colors only,
│                                     #   --no-dither = smooth gradient, with spectrogram unchanged by the flag (render part skips without tools).
│                                     #   flux-wall-wrapper.sh — effect of flux-wall.sh start/select/off/stop/status/autostart/doctor
│                                     #   on a fake binary with process state (pgrep/pkill mocks see only its PIDs);
│                                     #   the ready file sits in the private session dir, without one start exits 3.
│                                     #   dither-flux-sizes.sh — the plan from data/monitors/*.dat plus the REAL
│                                     #   generator at ~64 px: every role (other = m-<connector>) gets every form;
│                                     #   an interrupted run is re-queued and never leaves a truncated PNG.
│                                     #   wallpaper-switcher.sh — Super+W against a fake hyprpaper daemon
│                                     #   (settings list + first-match rule): the picked wallpaper must end up
│                                     #   ON SCREEN in all three .dat scenarios; plus the menu on a fake rofi:
│                                     #   all monitors vs the focused one, the hyprlock background toggle,
│                                     #   only existing animations reach flux-wall.dat, previews (thumbnail
│                                     #   cache by mtime, no tool → original image).
│                                     #   `bash tests/wallpaper-switcher.sh`.
│                                     #   rofi-inputbar.sh — static font and vertical alignment checks for every rice input bar.
│                                     #   rofi-theme-switcher.sh — Super+T previews on a fake rofi; every rice
│                                     #   stub has a valid rices/<RICE_NAME>/preview.png.
│                                     #   render-previews.sh — tools/render-previews.sh on a fake offscreen:
│                                     #   --dither/--no-dither per rice (none for an older offscreen), synth audio,
│                                     #   frame time from `#pragma flux life`.
│                                     #   update-archenemy.sh — the Super+A → [u] updater on real git
│                                     #   (bare origin in a temp dir): no false "✓" on failure, no
│                                     #   switching to a branch older than what you run; per-platform installer
│                                     #   advice (UPDATE_ARCHENEMY_REV=<rev> compares Arch with that revision).
│                                     #   runtime-platforms.sh — mouse DPI advice and the workspace guard's single
│                                     #   fallback notice (missing socat vs missing Hyprland socket) per platform,
│                                     #   plus every active rice (yin and yang too) using the shared TUI and guard.
│                                     #   switch-rice.sh — rice switching on a fake ~/.config: foreign
│                                     #   symlinks backed up, two quick Super+T don't race, a lock held
│                                     #   past the wait ends with code 1 and the old rice intact; the real
│                                     #   yin.sh → yang.sh stubs link every rices/yang folder, nothing of yin.
│                                     #   hm-conflict.sh — home-manager links into /nix/store: Super+T, link-only
│                                     #   and installer [9] refuse before any change (code 3, ~/.config and
│                                     #   .current_rice unchanged), a second installer run is identical, after
│                                     #   removing the declaration it links once; HM ~/.bashrc → no write/backup,
│                                     #   block shown for programs.bash.initExtra; HM mpd config not offered for
│                                     #   replacement; ~/archenemy in the store → installer refuses; the real
│                                     #   yang with an HM fastfetch/alacritty/nvim folder is refused the same way.
│                                     #   install-link.sh — installer step [9] (link-only mode of the same
│                                     #   lib): stow symlinks and real dirs go to .bak, never rm; the real
│                                     #   yang after yin: every folder linked with ✓.
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
│                                     #   shell-platforms.sh — [h] on Arch, EndeavourOS, Fedora, NixOS, Ubuntu and without pkg.sh:
│                                     #   same questions/defaults, dnf only from Fedora's repos, state after a confirmed
│                                     #   package + file/command, NixOS declarations only (no chsh); SHELL_PLATFORMS_REV=<rev> parity.
│                                     #   shell-plugins.sh — optional plugin checklist, package confirmation,
│                                     #   state/backups, loading order and missing-file guards on mocks.
│                                     #   appbinds.sh — Super+A list vs [d]: a hand-written bind between
│                                     #   TUI binds doesn't shift the numbering.
│                                     #   rice-autostart.sh — runs every rice's hyprland.lua on a fake
│                                     #   `hl` API (lua5.4) and checks what starts with the session;
│                                     #   window `move` rules must evaluate (PiP lands in the corner);
│                                     #   yang's output equals yin's (same backend, only the looks differ).
│                                     #   gpudrivers.sh — GPU installer on fake sudo/pacman/modinfo and a
│                                     #   fake /etc: no initramfs changes without a built nvidia module.
│                                     #   archenemy-doctor.sh — public diagnostics, privacy, deadlines and read-only checks.
│                                     #   doctor-platforms.sh — doctor per platform (Arch, derivative, Fedora, Atomic, NixOS,
│                                     #   unknown) × zero/missing/error/empty/hang/no backend, AUR, multi-RPM, i686,
│                                     #   --full gaming status, rices yin and yang; DOCTOR_PLATFORMS_REV=<rev> compares Arch.
│                                     #   gaming-diag.sh — the real gaming-diag.sh on mock commands and a mock
│                                     #   filesystem root on every platform, --doctor, Super+A "Saved";
│                                     #   GAMING_DIAG_REV=<rev> compares Arch.
│                                     #   fastfetch-logo.sh — every rice's fastfetch follows the system logo: "auto" with the
│                                     #   machine-layer logo file as source (the Æ mark when chosen, the detected distro's
│                                     #   built-in logo without the file), colors 1–6 set (NixOS uses 1–6, Arch/Fedora 1–2);
│                                     #   launcher-logo.sh sync on a fake HOME; with fastfetch installed, both modes and
│                                     #   Arch/Fedora/NixOS render only in the rice's colors.
│                                     #   yang-wallpaper.sh — gen_yang_wallpaper.py twice: same SHA-256, equal to
│                                     #   wallpapers/yang/, v1/v2 sizes, darkest level ≥ #6E6E73 (README contrast).
│                                     #   repo-hygiene.sh — executable bits, `#!/usr/bin/env bash` shebangs (also tested without /bin/bash),
│                                     #   no /bin/bash or fixed /usr/bin/<program> inside session files (git grep),
│                                     #   Lua dispatch syntax and installer/doctor language;
│                                     #   no machine data (interface names such as network=wlo1, /home/<login>);
│                                     #   suites that execute generated Lua in lua5.4 report "? skip" without it
│                                     #   (every lua5.4 block is run on its own with lua5.4 hidden from PATH).
│                                     #   appbinds-menu.sh, tui-keys.sh, tui-lines.sh, tui-contrast.sh — TUI
│                                     #   dispatch, navigation, line input and palette contrast.
│                                     #   appbinds-menu.sh also forces a failed write, a dead Hyprland, a dead waybar
│                                     #   and a guard that does not start: no green ✓ without a read-back effect.
│                                     #   tui-effects.sh + tui-effects.list — guard: every Super+A entry that changes state names
│                                     #   the test of its effect; every monitor position form is read back.
│                                     #   autostart-picker.sh, terminal-settings.sh — app checklist and copy on select.
│                                     #   font-settings.sh — [f] fonts on a fake HOME/fc-list/rofi: writes only outside the repo.
│                                     #   system-theme.sh — login screen and boot menu themes on mocks: building, the root
│                                     #   script on hostile state files (rice, logo, monitor, wallpaper), the installer
│                                     #   with foreign themes, and --remove.
│                                     #   monitor-settings.sh — monitor trials and rollback, every position form read back from the mock; audio-devices.sh /
│                                     #   mpd-output.sh — system and mpd outputs; focus-highlight.sh — cursor-aware borders.
│                                     #   rofi-drun.sh — launcher command gate.
│                                     #   waybar-launcher.sh — custom/launcher: exec launcher-logo.sh, json, format {}, signal 12
│                                     #   (no other module on 12), no interval; the image only under .archenemy
│                                     #   (url("launcher.svg") symlinked to assets/logo per rice, also through a fake
│                                     #   ~/.config/waybar link), the glyph under .distro, no #RRGGBBAA in those style
│                                     #   files, distro glyphs only in launcher-logo.sh.
│                                     #   launcher-logo.sh — the launcher script on a fake HOME and os-release: mode
│                                     #   from data/launcher-logo.dat (missing/garbage = distro), Arch/derivative/
│                                     #   Fedora/NixOS/unknown glyph, os-release read as data, always exit 0.
│                                     #   dnd.sh — do-not-disturb bell on a fake makoctl (tests/mock/makoctl) and
│                                     #   fake pgrep/pkill: no makoctl call without a running mako, exact mode match,
│                                     #   toggle both ways keeping other modes, signal 13, failing/stuck/hung makoctl;
│                                     #   custom/dnd in the seven non-beta bars (signal 13 nowhere else), and every
│                                     #   mako/config hides notifications in do-not-disturb but lets critical ones through.
│                                     #   rofi-clipboard.sh — clipboard selection, deletion, clearing, previews and dependency errors on mocks.
│                                     #   keyboard-layouts.sh — [k] on a fake HOME/hyprctl/evdev.lst: 1–4 known
│                                     #   codes, reload + read-back, switch N, the TUI menu driven via stdin.
│                                     #   nix-paths.sh — no /usr/share (NixOS): evdev.lst from Nix profiles or
│                                     #   XKB_CONFIG_ROOT, Arch's /usr/share first; zsh plugin paths only from profiles.
│                                     #   mouse-settings.sh — [m] on a fake HOME/hyprctl/ratbagctl: range checks,
│                                     #   reload + read-back, generated Lua, emulated and hardware DPI, the menu.
│                                     #   Without lua5.4 (package lua54) mouse-settings, keyboard-layouts,
│                                     #   machine-layer and autostart-picker print "? skip" and count it in their
│                                     #   last line — never OK.
│                                     #   asus-installation.sh — ASUS installer on a fake pacman: AUR variants
│                                     #   replaced, success = the package named asusctl, supergfxctl guard.
│                                     #   power-profile.sh — profile get/next on a fake asusctl with the 6.5.0
│                                     #   syntax, verified change, fallback to power-profiles-daemon; ppd
│                                     #   without `performance` still cycles (only listed profiles, failed step skipped).
│                                     #   bootloader.sh — install/bootloader.sh, kernel-install.sh and
│                                     #   cpudrivers-installation.sh on fake sudo/pacman/grub-mkconfig/bootctl,
│                                     #   a fake /boot and /proc/cpuinfo: GRUB regenerated only after the
│                                     #   packages are really installed, systemd-boot/unknown entries untouched.
│                                     #   volume-bar.sh — waybar volume module on fake pactl/wpctl: headphones in any locale.
│                                     #   timer.sh — waybar timer: running → finished, one notification with two bars at once.
│                                     #   rofi-power-menu.sh — Super+RShift power menu on fake rofi/pidof/systemctl (nothing
│                                     #   is shut down): poweroff under hyprlock, confirm with Yes, Esc/No do nothing; the
│                                     #   fake rofi (tests/lib/mock_rofi.py) models script mode, one process = one window:
│                                     #   both steps in one rofi process (fast input is not lost), each row carries its
│                                     #   action, forged callbacks do nothing, a waiting systemctl does not hold the
│                                     #   window, every rice binds the same script; the script passes
│                                     #   `-kb-accept-entry '!Return,!KP_Enter'` and the fake models that rule (accept on
│                                     #   key release: a held Enter stops at the question, Enter-Enter shuts down, the
│                                     #   same script without the option does not stop). No clock or real keyboard:
│                                     #   speed and the held key are checked live.
│                                     #   runtime-dir.sh — scripts/lib/runtime-dir.sh: no ${XDG_RUNTIME_DIR:-/tmp} left,
│                                     #   only our private dirs, refusal on a planted one, window history then off.
│                                     #   virtualbox.sh — VirtualBox installer on fake pacman/modprobe and a
│                                     #   fake /sys/module: success only with vboxdrv loaded, reboot code 2.
│                                     #   window-history.sh — Super+Tab on a fake `hyprctl clients` with
│                                     #   real processes: same argv and directory, apps still running
│                                     #   (tray, dialogs) skipped, the state lock is not inherited.
│                                     #   bluetooth.sh — optional Bluetooth bar and installer on mock BlueZ/D-Bus/services,
│                                     #   power choice kept across mock login, resume, replug and bluetoothd restart.
│                                     #   install-guards.sh — install.sh refuses root, `sudo -k` after the last
│                                     #   sudo and on every exit (Ctrl+C, step [2]; none on NixOS), GPU and VirtualBox installer
│                                     #   test hooks only with ARCHENEMY_TEST=1.
│                                     #   install-summary.sh — installer steps cut out of install.sh on fake
│                                     #   sudo/pacman/yay: failed optional packages and [6.5] installer exit codes
│                                     #   land in the summary; the banner claims full success only without them.
│                                     #   install-main.sh — the WHOLE install.sh on a copy of the repo in a temporary
│                                     #   HOME, in a pty (tests/lib/drive-pty.py answers only known prompts) on fake
│                                     #   sudo/pacman/yay/systemctl/hyprctl/ufw: the effect of every step is read back
│                                     #   (files, links, service calls) and a second run changes no file.
│                                     #   install-aur.sh — install/lib/aur.sh on fake git/makepkg/yay: fresh
│                                     #   mktemp build dir, cleanup, review on request (also without `less`),
│                                     #   ✓ only with yay in PATH, Ctrl+C in step [4] stops install.sh,
│                                     #   yay always cloned from the fixed AUR URL (no environment override).
│                                     #   shellcheck.sh — `shellcheck -x -S info -e SC1091` on every tracked script;
│                                     #   fails only on findings not in tests/shellcheck.baseline; no shellcheck → "skip";
│                                     #   a broken or killed shellcheck (output not in gcc format, xargs exit
│                                     #   other than 0/123) → ✗; `--selftest` runs only its fake-shellcheck autotest;
│                                     #   `--update-baseline` only removes fixed entries — new findings are fixed in
│                                     #   code (a deliberate exception is added to the baseline by hand, with a comment).
│                                     #   secrets.sh — private keys/tokens in tracked files (always) and gitleaks
│                                     #   over the whole history (when installed; otherwise "skip").
│                                     #   platform-map.sh — packages/platform-map.tsv: 10 tab-separated fields, every
│                                     #   entry of the four lists, cli-tools.tsv and literal ad-hoc installs has a
│                                     #   row, no dead rows, no -git, only the approved COPR; negative cases → ✗.
│                                     #   nix-packages.sh — nix/packages.nix without nix (text parser
│                                     #   tests/lib/nix_packages.py): current vs the map, balanced syntax, only
│                                     #   pkgs.<attr>, no options/"-"/duplicates, all 66 attrs, groups; mutations → ✗.
│                                     #   pkg.sh — install/lib/pkg.sh on fake os-release/sudo/pacman/yay/dnf/rpm/nix-*:
│                                     #   Arch uses the old commands, Fedora exact RPM names without masking flags,
│                                     #   COPR/Brave only after "y", NixOS never mutates, unsupported ID → refusal;
│                                     #   map: glob-free splitting, statuses/sources/field consistency, duplicate id;
│                                     #   rpm/pacman: error ≠ installed/missing, results independent of locale.
│                                     #   packages-exist.sh — every name in packages/*.txt exists where it is
│                                     #   installed from (official repos core/extra/multilib in the pacman sync DB /
│                                     #   AUR RPC v5), no -git in requirements;
│                                     #   offline → "skip", never ✓; without a synced [multilib] only steam and
│                                     #   lib32-* skip, any other unknown name → ✗.
│                                     #   run-all.sh — every suite at once: `bash tests/run-all.sh`; each suite
│                                     #   gets RUN_ALL_TIMEOUT seconds (default ceil(600 × time scale), 0 = no
│                                     #   limit), then it is killed with its child processes and reported
│                                     #   as "timeout pakietu" (a suite timeout, not proof of a hang); a failing
│                                     #   suite prints its exit code, the last 200 lines and the paths of its
│                                     #   full .log/.rc kept in /tmp/archenemy-run-all-*.
│                                     #   lib/timing.sh, lib/test_timing.py — shared harness watchdogs scaled by
│                                     #   ARCHENEMY_TEST_TIME_SCALE (1..10, default 1); product timing contracts
│                                     #   stay unscaled (tests/README-timing.md).
│                                     #   run-all-timeout.sh — that limit on a copy of run-all.sh with stub
│                                     #   suites: suite timeout, TERM-ignoring, red, exit 124/137 before the limit
│                                     #   (plain ✗, not a suite timeout), raw AssertionError/TimeoutExpired with
│                                     #   full logs, scale validation and skipping (exit 0 = ✓); Ctrl+C, SIGTERM
│                                     #   and SIGHUP (closed terminal) stop the run together with the current suite;
│                                     #   suites get default INT/QUIT/HUP handling even when the run was
│                                     #   started with SIGHUP ignored (nohup, a tool's background job).
└── wallpapers/                       # Wallpapers (in git) — any files, optionally grouped in set folders.
    ├── blue-hex/                     # Set: honeycomb of 7 hexagons (#0148ED) on white — v1 1920x1080,
    │                                 #   v2 2560x1600; first in sort order, so the default after a fresh install.
    ├── arch-white/                   # Transitional symlinks only: the old file names point to blue-hex
    │                                 #   (the drawn Arch Linux mark was removed on 2026-11-17 — trademark).
    │                                 #   Super+W, --restore and --init rewrite saved choices to blue-hex;
    │                                 #   the menu lists regular files only, so these links stay hidden.
    ├── tron-grid/                    # Set: Tron grid (neon cyan on #020A0F) — v1/v2 as above.
    ├── crt/                          # Set: oscilloscope — Lissajous trace in phosphor cyan on
    │                                 #   navy glass with a faint graticule — v1/v2 as above.
    ├── yin/                          # Set: eclipse — a dark disc rimmed by a thin white light on
    │                                 #   near-black, soft corona; v1/v2 as above (gen_yin_wallpaper.py).
    ├── yang/                         # Set: eclipse in negative — a light disc rimmed by a thin dark
    │                                 #   shadow on paper, soft grey corona; v1/v2 (gen_yang_wallpaper.py).
    └── dither-flux/generated/        # NOT in git — created by install.sh [9.7]: 3 forms (flow field ×2,
                                      #   attractor) in a Bayer dither raster, milford-water palette, sized
                                      #   to the REAL monitors. No PNGs of this set in git (2026-09-08).
```

## Wallpapers

Wallpapers live in `wallpapers/` (loose files or in subfolders) and are versioned in git — a fresh install has them right away. Exception: the `dither-flux` set is **generated for the real monitors** — `install.sh` step **[9.7]** reads resolutions and roles from `data/monitors/*.dat` (primary → `v1`, secondary → `v2`, further ones → `m-<name>`; modes named like `preferred` are resolved via `hyprctl`) and runs `gen_dither_flux_wallpaper.py` in the background into `wallpapers/dither-flux/generated/` (outside git; logged to `generate.log`). Each PNG is written atomically (a hidden `.part` file, then a rename), and a size counts as done only once its last form exists, so a run cut short by a reboot is completed by the next `install.sh` or `Super+A → [n]`. A 1px raster doesn't tolerate scaling, so the wallpaper must exactly match the screen resolution. As of 2026-09-08 the repo keeps no ready-made PNGs for this set — until generation finishes (a few minutes after install) the `dither-flux` entry in `Super+W` simply isn't there; the flux-wall animations are independent of these files.

The `Super+W` menu is two-level: under two checkboxes are the **`Wallpapers/`** folder (files from `wallpapers/`) and **`Animations/`** (flux-wall animations, when built; music visualizations tagged `♪ music visualisation`), and below them **`Animation: off`**; `← Back` in the submenu returns to the top. Picking an animation doesn't change the hyprpaper wallpaper: the animation draws on top of it and works in **every** rice, using `rices/<rice>/flux-wall.conf` for the palette when present (beta has no such file and uses the binary's default palette). The choice is remembered in `data/flux-wall.dat` and survives `Super+T` and reboots; `off` disables the animation everywhere, and deleting the file restores the rice's default behavior (dither-flux: enabled, the rest: disabled). Switching: `Super + W` — the menu shows all images (jpg/jpeg/png/webp), with two checkboxes at the top: `[x] Upload to all monitors` (checked by default — wallpaper goes to all monitors instead of just the focused one) and `[ ] Set as hyprlock background (no blur)` (unchecked by default — checking it sets the chosen image as the lock-screen background without blur, instead of the default live screenshot + blur; survives switching rices).

**Previews.** Both submenus show pictures: a 3-column grid with a large image above each name (set via `-theme-str` only for these menus — each rice's rofi colors, borders and rounding stay; the top level with the checkboxes stays a plain list, and `← Back` has no image). `Wallpapers/` shows thumbnails generated on first use into `data/thumbs/` (machine layer, outside git), keyed by path + modification time — an edited file gets a fresh thumbnail, the stale one is removed. The tool is whichever is present: `glycin-thumbnailer`, `gdk-pixbuf-thumbnailer`, or ImageMagick's `magick`; with none of them, or on an error, the original image is used as the icon (rofi loads it, just more slowly). Generation is capped at 3 s per file and 6 s per menu opening, so the shortcut never hangs — anything left over shows the original and gets its thumbnail next time. `Animations/` shows ready-made frames from `src/flux-wall/shaders/previews/<active rice>/<animation>.png` (committed, rendered in each rice's palette by `src/flux-wall/tools/render-previews.sh`); an animation without a frame is listed without a picture, and a rice with no frames at all (e.g. `white-blue_beta`) gets the plain list.

At the top of the menu is the **`[x] Upload to all monitors`** toggle (checked by default):

- **Checked** — the wallpaper goes to all monitors. If a matching `*v1*`/`*v2*` counterpart sits next to the chosen file, the primary monitor gets `v1` and every other monitor gets `v2`; without a pair, the same image goes everywhere. The counterpart is found from the chosen file's own name: same part before the tag, so `dither-flux-atraktor-v1-1920x1080.png` pairs with `dither-flux-atraktor-v2-…`, never with another form from the same folder; among several such files the one with the monitor's resolution (from `data/monitors/*.dat`) wins, then the same name with the tag swapped. The extension may differ (`city-v1.jpg` pairs with `city-v2.png`, as long as the counterpart is a `jpg`/`jpeg`/`png`/`webp` image); it only breaks ties, so `city-v2.jpg` next to it would win.
- **Unchecked** (click the entry to toggle) — the wallpaper goes only to the monitor you have focus on; the others stay unchanged.

The per-monitor choice is remembered in `data/wallpaper.dat` and restored when you switch rice or re-run `install.sh` (a fresh install, or a choice pointing at deleted files, falls back to the first wallpaper). The installer's `✓` for this step (`--init` in [9.5]) comes only after the switcher has applied the wallpaper; if hyprpaper does not show it, the step lands in the summary with the log path. Set wallpaper roles in the installer or `Super+A → [n]`; the role the installer proposes is the monitor's current one, otherwise the first free one (see the role note below). A monitor without a saved wallpaper uses the secondary wallpaper on restore.

**One monitor = one entry, and the switcher checks the screen.** `data/wallpaper.dat` and the generated `hyprpaper.conf` are keyed by the same monitor selector the rest of the machine layer uses (`desc:<EDID description>`, connector name for older `.dat` files) — and the live IPC call tries that same key first, with a connector-name fallback if it fails. hyprpaper keeps its settings as a list and gives a monitor the **first matching** entry, while IPC appends its entry at the end and only replaces one with an identical key: a leftover entry for the same screen under its old connector name (or an IPC call keyed by connector name against a `desc:` config) would therefore win the match and the newly picked wallpaper would never show up — with `hyprctl` still reporting success. Old connector-name entries are migrated to today's selector on read, and after applying, the switcher asks `hyprctl hyprpaper listactive` what is actually on screen; if it doesn't match, it restarts hyprpaper (which re-reads the freshly written config) and checks again before claiming success. When `listactive` gives no usable response, compatibility handling falls back to the IPC result; this cannot verify the displayed image.

The role only applies to **wallpapers** (primary→v1, every other monitor→v2). When `install.sh` runs again, Enter at the role question [3.5] keeps the role the monitor has now (from the `data/monitors/*.dat` entry that matches it by EDID description, or by connector name for older entries); a monitor without one gets the first role nobody else has (primary, then secondary, then other). Workspace assignment is governed by something else: **left→right monitor numbering** and **workspace mode** (see the "Workspaces" section).

## Shader-computed animated wallpaper (flux-wall)

`src/flux-wall/` is a Wayland client written in C (`wlr-layer-shell`, EGL and GLES 3.0). It draws a shader on a separate surface per monitor, on the `bottom` layer above hyprpaper and below windows. Hyprpaper stays underneath as the fallback if the animation stops or cannot start. Integer and fractional output scales are supported through `wl_output`, `wp_fractional_scale_v1` and `wp_viewporter`.

**Build.** Installer step **[9.6]** runs `make -C src/flux-wall`. Build dependencies are `base-devel`, `wayland`, `mesa` and `libpulse` from the required package list; protocol XML files are included in the repo. A failed build is reported in the summary and does not abort installation. Developer tools are separate: `make -C src/flux-wall tools` builds the offscreen renderer; `make -C src/flux-wall test` runs the C tests.

**Choice and autostart.** `Super+W → Animations/` saves an animation name in `data/flux-wall.dat`; `Animation: off` saves `off`. This choice applies across rices and takes precedence over the rice's default. With no saved choice, only `dither-flux` starts an animation. Each non-beta rice declares `FLUX_WALL_PALETTE`, `FLUX_WALL_SHADER`, `FLUX_WALL_ARGS`, `FLUX_WALL_AUTOSTART` and `FLUX_WALL_DITHER` in its `flux-wall.conf`. Beta uses the binary's default palette for a selected animation. Login starts the wrapper once through shared `config/hypr/autostart-common.lua`; the rice switcher calls it again to apply the new palette and settings. A missing binary leaves the static wallpaper visible. Step [9.6] migrates renamed choices and clears choices whose shader was removed.

**Dither and battery.** Only `dither-flux` sets `FLUX_WALL_DITHER=1`; the wrapper passes `--dither` there and `--no-dither` elsewhere, regardless of the selected animation. Shaders with dithering use an 8×8 Bayer matrix or a smooth palette gradient; `spectrogram` always uses a smooth gradient. An older binary that lacks these flags gets neither until rebuilt. `--battery` lowers the `detail` uniform to the battery level only while a battery reports `Discharging`; on AC power detail stays at 1.0, including a battery held at a charge limit (`Not charging`, e.g. 80% set by asusctl or the BIOS) or reporting `Unknown`. Each shader decides how detail affects its rendering.

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

`start` and `select` (what `Super+W` reports as "applied") wait for the binary to confirm its **first frame on screen**: the binary gets `--ready-file <session dir>/flux-wall.ready` and creates that file with its PID after the first successful buffer swap, i.e. after the shader compiled and the EGL surface exists. A process that is merely alive proves nothing — shader or EGL errors (exit code 3) arrive only at the first surface, later on a slow GPU. If the process exits first, or no frame arrives within `FLUX_WALL_READY_TIMEOUT` seconds (default 10; the process is then left running), the wrapper exits with 3 and prints the end of the log. An older binary without `--ready-file` is checked as before (alive after 0.5 s). `autostart`/`restore` stay quiet and do not wait. The ready file and the runtime log (`flux-wall.log`) live in the private session directory from `scripts/lib/runtime-dir.sh`: `$XDG_RUNTIME_DIR` (without that variable, or when it is not a private directory: `/run/user/<UID>` or a private `0700` `archenemy-<UID>` directory in `$TMPDIR`, default `/tmp`), never a shared `/tmp` file. When no such directory is available, the log goes to `/dev/null` and there is no ready file, so `start` cannot confirm the first frame: it exits with 3 instead of reporting success, and leaves the process running. `doctor` reports the checkout, binary age and capabilities, shaders, saved choice, process and log.

**EGL errors while running.** Exit code 3 belongs to startup: until the first frame is on screen (the moment `--ready-file` marks), any EGL error ends the process and hyprpaper stays visible. After that, an EGL error on one monitor's surface (for example a newly connected monitor on which `eglCreateWindowSurface` fails) drops only that surface and retries it after 1 s, doubling up to 30 s; the other monitors keep animating. A lost EGL context (`EGL_CONTEXT_LOST`, e.g. after the GPU wakes up) never recovers by itself, so the binary creates a new context, rebuilds the shader program and recreates every monitor's surface instead of skipping frames forever with a frozen picture while `status` reports it running. More than 3 losses within 60 s, or a failed new context, end the process with 3 and hyprpaper stays. Such errors are always written to the log, also without `-v`.

**Adding shaders.** A single-pass animation is a `.frag` file. A matching `<name>.update.glsl` enables the particle engine: positions and fading trails live in floating-point textures, with parameters from `#pragma flux` declarations. Supported uniforms and parameters are defined in `src/flux-wall/engine.h` and implemented in `engine.c`. Every shader declares `precision highp sampler2D;` before its first sampler, because GLSL ES defaults samplers to low precision and Mesa then rounds texture reads; `tests/flux-wall-shaders.sh` checks it. Add previews with `src/flux-wall/tools/render-previews.sh -r <rice>` after building the tools. Dithering must follow the uniform rather than the animation name. Accumulator reads at computed columns need a small band (`bars` uses `xc-1..xc+1`), because point stamps may land one pixel to the left; `tests/flux-wall-bars.sh` checks both screen halves. `tests/flux-wall-dither.sh` checks wrapper flags and, when tools are built, rendering.

## Rices

| Rice | Description |
|---|---|
| `white-blue` | Default. White-blue glass: rounded corners, tuned blur, custom animations, consistent `#0148ED` accent, mako + hyprlock + nvim theme (hand-tuned colorscheme in the rice's palette). ncmpcpp skin (blue accent `#0148ED`, bright blue `13` for the now-playing line, terminal palette only) and mpv OSD (white on `#1A1A2E`). |
| `white-blue_beta` | The original white-blue look, kept for reference/rollback. Functional fixes only, no visual changes. mako and hyprlock inherit from `white-blue` via symlinks in the repo. |
| `tron` | Tron: Legacy — dark glass `#020A0F`, neon cyan `#00E5FF` with glow, CLU orange `#FF7B1C` for alarms only, near-sharp corners (4–6px). Own waybar theme (with a "portal to the Grid" launcher and glowing HUD islands), rofi (search glyph), fastfetch (distro logo in neon cyan), alacritty/mako/hyprlock (cinematic look with neon lines)/MangoHud/nvim (hand-tuned colorscheme: neon cyan on `#020A0F`, alarms in CLU orange); networkmanager-dmenu inherits from `white-blue` via a repo symlink. Wallpaper: the `tron-grid` set (generated). ncmpcpp skin (neon cyan accent, plate `#0E2A33` as the empty part of the progress bar, no CLU orange) and mpv OSD (`#CFEEF7` on `#020A0F`). |
| `asia-n-rice` | Muted mauve/pink (`#b47687`) on dark navy (`#2a3444`), flat look: waybar with rounded islands (14px) and italic window titles, sharp window corners, `#131a2a` border. Look carried over from the author's own earlier rice (`arch_linux_rice-beta1.2`) and rewired onto the archenemy backend: alacritty instead of kitty, rofi instead of wofi, machine layer (GPU/monitors/workspaces) via Lua `require()`, no cava. Own waybar/rofi/mako/hyprlock/alacritty theme in the mauve palette; fastfetch (distro logo in mauve, default key colors); own nvim theme (hand-tuned colorscheme in the mauve palette, flat — no bold); MangoHud and networkmanager-dmenu inherit from `white-blue` via symlinks. No wallpaper of its own — uses whatever's current (machine layer). ncmpcpp skin (mauve accent, flat — no bold anywhere) and mpv OSD (`#e8e8e8` on `#182130`). |
| `crt` | Blue/cyan phosphor CRT — the owner's six `hyprpicker` samples: `#043D7B`/`#0B358B` (glass, plates), `#3069AD` (borders, dim text), `#5695D6` (text), `#36D2D8` (accent, active), `#74DCE2` (bright text); the dark base `#031533` is `#043D7B` darkened in the same hue (the palette has no near-black), and amber `#FFB000` — classic amber phosphor — is the only warm color, reserved for alarms. (The CRT screen shader — scanlines/aperture mask/vignette — was removed on 2026-09-17 at the owner's request: the palette is the point, the "old monitor" look was not.) Glass islands with blur (alpha 0.55) and a cyan glow, 4px corners, 1px gradient borders (`#36D2D8` → `#5695D6`), phosphor glow (`shadow`) around the active window. Full own set: waybar (the launcher shows your distribution's glyph with a phosphor glow, or the archenemy Æ logo in bright phosphor cyan — `Super+A` → `[l]`), rofi, alacritty (cool ANSI, still distinguishable), mako, swayosd, hyprlock (glowing clock via label shadow), fastfetch, MangoHud, nvim (hand-tuned colorscheme); networkmanager-dmenu from `white-blue` via symlink. Wallpaper: the `crt` oscilloscope set from `gen_crt_wallpaper.py`; flux-wall animations available in the rice's palette (off by default). ncmpcpp skin (`#5695D6` text, cyan accent, `#0B358B` as the empty part of the progress bar, `#3069AD` frames) and mpv OSD (`#74DCE2` on `#031533`). |
| `yin` | Black with a white accent, frosted glass — the dark half of the yin/yang pair (`yang` is its light half). Near-black `#0C0C0E`, graphite `#121215`/`#1E1E22` plates, slate `#2E2E33`, smoke `#5E5E66`, ash `#8C8C96` (secondary text), paper `#E6E6EA` (text), white `#FFFFFF` (accent: active workspace, cursor, active border, keywords); ember `#E0805A` is the only warm color and is reserved for alarms (critical battery, urgent workspace, critical notifications, errors, the ANSI "red" slot). Glass: alacritty at opacity 0.82 over a strong, grain-free blur (3 passes, brightness 0.85, no vibrancy), translucent waybar/rofi/mako/swayosd plates with a 1px white edge at low alpha, 12px corners everywhere, soft black shadows within the 4px rhythm, no glow. ANSI greys climb in even lightness steps (L\* ≈ 56 → 86, bright one step higher) so `ls`, `git` and syntax stay readable without hue. Full own set: waybar (a white launcher — your distribution's glyph, or the archenemy Æ logo via `Super+A` → `[l]` — and a white pill for the active workspace), rofi, alacritty, mako, swayosd, hyprlock (a glass panel behind the clock), fastfetch (the distro logo in white and ash, two rows of palette dots), MangoHud, nvim (hand-tuned monochrome colorscheme: lightness and bold/italic instead of hue); networkmanager-dmenu and ncmpcpp `bindings` from `white-blue` via symlinks. Wallpaper: the `yin` eclipse set from `gen_yin_wallpaper.py`; flux-wall animations available in the monochrome palette (off by default). ncmpcpp skin and mpv OSD (`#E6E6EA` on `#0C0C0E`) follow the same palette. |
| `yang` | `yin` inverted — the light half of the yin/yang pair: the same backend, layout, 12px corners, 4px rhythm, animations and frosted glass, with the lightness turned around. Paper `#F3F3F5`, milk `#EEEEF1`/`#E1E1E5` plates, slate `#CCCCD0`, ash `#5E5E66` (secondary text), ink `#1E1E22` (text), black `#0C0C0E` (accent: active workspace, cursor, active border, keywords); rust `#A23A10` is the only warm color and is reserved for alarms (critical battery, urgent workspace, critical notifications, errors, the ANSI "red" slot). Glass: alacritty at opacity 0.82 over the same 3-pass blur with brightness 1.0 (dark text must not lose contrast to a darkened background), translucent milk waybar/rofi/mako/swayosd plates with a 1px black edge at low alpha, soft light shadows within the 4px rhythm, no glow. ANSI keeps `yin`'s order of contrast (white is the darkest text grey, black the lightest plate), in even lightness steps (L\* ≈ 40 → 14, bright one step darker), so `ls`, `git` and syntax stay readable without hue. Full own set: waybar (a black launcher — your distribution's glyph, or the archenemy Æ logo via `Super+A` → `[l]` — and a black pill for the active workspace), rofi, alacritty, mako, swayosd, hyprlock (a denser light glass panel behind the clock, the screenshot not dimmed), fastfetch (the distro logo in black and ash, two rows of palette dots), MangoHud (a denser light plate), nvim (hand-tuned light monochrome colorscheme); networkmanager-dmenu and ncmpcpp `bindings` from `white-blue` via symlinks. Wallpaper: the `yang` set (the eclipse in negative) from `gen_yang_wallpaper.py`; flux-wall animations available in the light monochrome palette (off by default). ncmpcpp skin and mpv OSD (`#1E1E22` on `#F3F3F5`) follow the same palette. |
| `dither-flux` | Dither art + algorithmic art: wallpapers are generative fields (flow field, Clifford attractor) quantized with an 8×8 Bayer raster, in the rainy `milford-water` palette from a Milford Sound frame; the only rice with `FLUX_WALL_DITHER=1`, so shaders with dithering — music visualizations included — use the same 1px Bayer raster (other rices and the `spectrogram` shader use a smooth gradient) — wet mountains `#0F1A24`, steel water `#5C87A3`, mist `#A8C4D4`, foam `#D8E6EE` as an accent; amber `#E0A23C` is the only warm color and is reserved for alarms only. Geometry follows the raster: **zero rounding**, 1px window borders, **blur and shadow disabled** (blur and dither are contradictory materials), waybar/rofi/mako islands as flat, near-opaque panels. Full own set: waybar (with a launcher), rofi, alacritty (ANSI toned to the palette but still distinguishable), mako, swayosd, hyprlock (1px lines, no glow), fastfetch (distro logo in foam), MangoHud, nvim (hand-tuned colorscheme); networkmanager-dmenu from `white-blue` via symlink. Wallpapers: the `dither-flux` set from `gen_dither_flux_wallpaper.py`. ncmpcpp skin (foam `#D8E6EE` as the accent, water `#5C87A3` as the elapsed bar, plate `#1B3040` as the empty part, flat — no bold) and mpv OSD (foam on `#0F1A24`). |

**yin — contrast on glass.** Text must stay at WCAG 4.5:1 or more with the glass over the brightest part of the wallpaper. The worst case is computed from the `yin` wallpaper itself: its brightest pixel is `#D8D8DE` (the rim), and after even a light blur (Gaussian σ = 8 px, weaker than Hyprland's 3 passes) the brightest spot under the glass is `#454548`. With alacritty's 0.82 opacity that makes the effective background `#161618` (solid: `#0C0C0E`). On it: text `#E6E6EA` 14.5:1, the darkest ANSI text grey (blue `#868690`) 5.0:1, ember `#E0805A` 6.4:1, ash `#8C8C96` 5.4:1; black on ember (critical alarms) 6.9:1. Only bright black `#5E5E66` (2.8:1) stays below — it is used for dimmed hints and backgrounds, not for text you read. Even with blur off and the bare rim behind the glass (`#313133`), text keeps 10.4:1. Waybar plates (graphite at alpha 0.62 over the same worst spot, effective `#252528`): paper 12.3:1, module text `#D7D7DC` 10.7:1, ash 4.6:1, ember 5.4:1; rofi (0.72), mako (0.78) and swayosd (0.80) are denser and only higher.

**yin wallpaper source and license.** `wallpapers/yin/*.png` are computed by `scripts/wallpapers/gen_yin_wallpaper.py` in this repository from formulas only (no third-party images, photos, logos or film stills), so they carry no third-party rights and are distributed on the same terms as the rest of the repository; rerun `python3 scripts/wallpapers/gen_yin_wallpaper.py` to rebuild them. The PNGs use an indexed palette (≤ 256 greys), which keeps the pair under 1 MB while the ±½-level random rounding prevents banding in the dark gradient.

**yang — palette and contrast on glass.** `yang` is `yin` with the lightness inverted: the same cool neutral greys (blue a few levels above red and green), each placed at L\* ≈ 100 − its `yin` counterpart, so the steps keep their spacing and their order of contrast. Paper `#F3F3F5` (background), milk `#EEEEF1`/`#E1E1E5` (plates), slate `#CCCCD0` (frames, ANSI black — a background, not text), smoke `#8C8C96` (non-text only: edges and tracks, 3.0:1 on paper), dim `#67676E` (ANSI bright black, line numbers), ash `#5E5E66` (secondary text, empty workspaces, ANSI blue), graphite `#46464C` (workspace numbers), mist `#3B3B41` (hover), `#232327` (module text, ANSI white), ink `#1E1E22` (text), black `#0C0C0E` (accent: active workspace, cursor, active border, keywords); rust `#A23A10` is the only warm color and is reserved for alarms (critical battery, urgent workspace, critical notifications, errors, ANSI red), dark rust `#7E2E0E` is its warning step (ANSI bright red). ANSI keeps `yin`'s order of contrast rather than the names' literal lightness: white is the darkest text grey and black the lightest plate, so programs written for dark terminals stay readable. Unlike `white-blue` (white glass bar and rofi, blue accent `#0148ED`, dark terminal), `yang` has no hue at all and its terminal is light too. The worst case is computed from the `yang` wallpaper itself: its darkest pixel is `#6E6E73` (the rim), and after a light blur (Gaussian σ = 8 px, weaker than Hyprland's 3 passes) and the blur's contrast 0.95 the darkest spot under the glass is `#BEBEC2` (brightness stays 1.0 — `yang` must not darken what is under the glass). With alacritty's 0.82 opacity that makes the effective background `#E9E9EC` (solid: `#F3F3F5`). On it: ink `#1E1E22` 13.7:1, the lightest ANSI text grey (blue `#5E5E66`) 5.3:1, dim `#67676E` 4.6:1, rust `#A23A10` 5.5:1, dark rust 7.6:1; paper on rust (critical alarms) 6.0:1, paper on black (active workspace) 17.6:1. Even with blur off and the bare rim behind the glass (`#DBDBDE`), ink keeps 12.0:1 and ash 4.7:1. Waybar plates (milk at alpha 0.62 over the same worst spot, effective `#DCDCDF`): ink 12.1:1, module text `#232327` 11.4:1, workspace numbers 6.9:1, ash 4.7:1, rust 4.9:1; rofi (0.72, ash 4.9:1), mako (0.78) and swayosd (0.80) are denser and only higher. Dimmed inactive windows (`dim_inactive`) are outside the rule, as WCAG exempts inactive components.

**yang wallpaper source and license.** `wallpapers/yang/*.png` are computed by `scripts/wallpapers/gen_yang_wallpaper.py` in this repository from formulas only (no third-party images, photos, logos or film stills) — the negative of the `yin` eclipse with its own constants and seed, so they carry no third-party rights and are distributed on the same terms as the rest of the repository; rerun `python3 scripts/wallpapers/gen_yang_wallpaper.py` to rebuild them. The output is deterministic (a fixed seed for the ±½-level random rounding), so two runs give byte-identical PNGs.

**fastfetch logo.** fastfetch follows the system logo (`Super+A` → `[l] system logo`). By default every rice (`white-blue_beta` included) shows fastfetch's built-in logo of the distribution it detects — Arch on Arch, Fedora on Fedora, NixOS on NixOS, and a derivative such as EndeavourOS gets its own — recolored with the rice's palette. With `archenemy logo` chosen it shows the Æ mark in the rice's first colour. Every rice config has `"type": "auto"` with `"source": "~/archenemy/data/fastfetch-logo.txt"`: `scripts/waybar/launcher-logo.sh sync` (run by the TUI, `install.sh` and the updater) puts a copy of `assets/logo/archenemy-ae.txt` there in the archenemy mode and removes it in the distro mode, and without the file fastfetch picks the distribution's logo itself. Colors 1–6 are set in every rice, because the NixOS logo uses six color slots (Arch and Fedora use two); a missing slot would leave that part in fastfetch's default color. A distribution's logo is drawn by fastfetch from its own character set; the repository ships no distribution logo file. `tests/fastfetch-logo.sh` guards this and renders both modes for every rice when fastfetch is installed.

Each rice is a folder in `rices/` whose subfolders are symlinked into `~/.config`. Switching: `Super + T` — the menu shows scripts from `scripts/changing-theme-scripts/` (the `.sh` file name is the menu label: `white-blue`, `tron`, `asia-n-rice`, `dither-flux`, `crt`, `yin`, `yang`, `white-blue_beta`). On switching, the old rice's symlinks are cleaned up, so themes don't mix.

The `Super + T` menu is a grid of pictures: each entry shows `rices/<RICE_NAME>/preview.png` (`RICE_NAME` read from the stub, so the label doesn't have to match the folder). The committed files are **mock-ups** drawn by `scripts/wallpapers/gen_rice_preview.py` from the colors each rice actually declares — the wallpaper motif in the `flux-wall.conf` palette, waybar islands from `waybar/style.css`, a terminal with the border/rounding from `hypr/hyprland.lua` and the ANSI palette from `alacritty/alacritty.toml` (`python3 scripts/wallpapers/gen_rice_preview.py [rice…]` regenerates them). A real screenshot is better: take one with `Super + Print` (drag over the whole screen; it lands in `~/Screenshots`) and copy it over `rices/<rice>/preview.png` — any size works, the menu just scales it. A rice without the file is listed without a picture.

**New rice:** create `rices/<folder>/`, copy `scripts/changing-theme-scripts/white-blue.sh` as `<label>.sh`, and set `RICE_NAME` inside it to your folder's name. The script is a two-line stub — all the switching logic lives in the shared `lib/switch-rice.sh`, so a new rice doesn't require copying any logic. For its `Super + T` picture, run `python3 scripts/wallpapers/gen_rice_preview.py <folder>` (a plain gradient background until you add a motif for it in the script) or drop a screenshot in as `rices/<folder>/preview.png`; if the rice has a `flux-wall.conf`, `src/flux-wall/tools/render-previews.sh -r <folder>` renders its animation previews. The installer's step [9] calls the same library with `SWITCH_RICE_LINK_ONLY=1` (links + `.current_rice` only, no wallpaper/reload/waybar restart), so a foreign symlink or a real directory in `~/.config` always ends up as `<name>.bak-<timestamp>`, never deleted.

### App launcher

`Super+R` and the bar's app launcher call `scripts/rofi/rofi_drun.sh`. In `crt`, `dither-flux`, `tron`, `yin` and `yang` the bar's launcher (left click: apps, right click: power menu) shows your distribution's logo by default — the Nerd Font glyph of Arch (also for Arch derivatives such as EndeavourOS or Manjaro), Fedora or NixOS, and a generic Linux glyph for anything else, read from `/etc/os-release` — and optionally the archenemy Æ logo in the rice's colour. Pick it in `Super+A` → `[l] system logo`; the choice is saved in `data/launcher-logo.dat` (outside the rice, so it survives a rice switch) and applied at once (waybar signal 12, `scripts/waybar/launcher-logo.sh`). The same choice is the logo in fastfetch (see "Rices"), and on the login screen and in the boot menu when their themes are installed (see "Login screen and boot menu"). `white-blue`, `white-blue_beta` and `asia-n-rice` have no launcher module. See "Logo". It opens rofi's desktop-entry launcher and gates manually typed commands by checking their first command token against `.desktop` `Exec=` lines. With normal desktop entries present, unmatched commands are ignored. If no `Exec=` entries can be read, the gate allows commands as a compatibility fallback. This is an application launcher, not a shell sandbox.

## Logo

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo/archenemy-ae.svg">
    <img src="assets/logo/rices/yang.svg" width="96" height="96" alt="archenemy logo: the Æ ligature">
  </picture>
</p>

The archenemy mark is the ligature **Æ** — **A**rch**E**nemy: the right leg of the A and the stem of the E are one shared vertical stroke. It is the project's own mark, drawn as plain SVG geometry (no font glyphs), and not the logo of Arch Linux or of any other distribution.

- `assets/logo/archenemy-ae.svg` — the base mark, white on transparency.
- `assets/logo/archenemy-ae.txt` — the same shape as text (half blocks), generated from the SVG by `assets/logo/gen_text_logo.py`; fastfetch shows it in the rice's first colour when the system logo is `archenemy logo`.
- `assets/logo/rices/<rice>.svg` — the same shape in each rice's colour (`yin` and `yang` are the white and black halves of the yin/yang pair); `assets/logo/README.md` lists the colours and where each one comes from.
- `assets/logo/banner-dark.svg`, `banner-light.svg` — the mark with the `archenemy` wordmark (also drawn as paths), shown at the top of this file by GitHub theme; `wordmark-white.svg` / `wordmark-black.svg` are the same without a background, and `social-preview.png` is the repository's link preview (uploaded by hand, see `assets/logo/README.md`).
- In the bar, `crt`, `dither-flux`, `tron`, `yin` and `yang` can show it as the app launcher when you pick `archenemy logo` in `Super+A` → `[l] system logo`; the default there is your distribution's glyph (see "App launcher"). The login screen and the boot menu show the same choice (see "Login screen and boot menu").

## Login screen and boot menu (optional)

Every rice has its own login screen (SDDM) and boot menu (GRUB) look. Nothing is installed unless you ask for it:

```
bash ~/archenemy/install/system-theme-installation.sh
```

(`install.sh` offers the same in step [10], default **N**.) The helper only touches what applies to your machine and says what it skipped:

- **Login screen** — only when SDDM is the enabled display manager (archenemy does not install one). Themes go to `/usr/share/sddm/themes/archenemy-<rice>/`, the choice to `/etc/sddm.conf.d/20-archenemy-theme.conf`. `/etc/sddm.conf` is never edited; if it sets a theme, the helper tells you and stops there.
- **Boot menu** — only when GRUB is the bootloader in use (systemd-boot has no themes) and it draws a graphical menu: with a text terminal in `/etc/default/grub` (`GRUB_TERMINAL` or `GRUB_TERMINAL_OUTPUT` without `gfxterm`, e.g. a serial console) GRUB ignores themes, so the helper skips it and says why. GRUB sizes are in pixels: the helper takes the height from an explicit `GRUB_GFXMODE`, otherwise from the laptop panel or the primary monitor, and prints which one it used — if the text looks too big or too small at boot, set `GRUB_GFXMODE=<width>x<height>` and run the helper again. One directory, `/boot/grub/themes/archenemy/`, holds all rices; `GRUB_THEME` is set in `/etc/default/grub` (a copy is kept as `grub.archenemy.bak`) and `grub.cfg` is regenerated once. A broken or missing GRUB theme does not stop the boot: GRUB falls back to its text menu.
- A theme you already use (SDDM or GRUB) is replaced only after its own question, default **N**.
- **Undo everything:** `bash ~/archenemy/install/system-theme-installation.sh --remove`.

**What follows your choices.** The login screen and boot menu are system files, so a small root script, `/usr/local/lib/archenemy/system-theme-sync` (a root-owned copy, not the file in your checkout), carries your choices over:

| Choice | Where you make it | Effect |
|---|---|---|
| rice | `Super+T` | login screen and boot menu of that rice |
| system logo | `Super+A` → `[l]` | distro glyph or Æ on the login screen and in the boot menu |
| login monitor | `Super+A` → `[g]` | which monitor shows the login form |
| wallpaper | `Super+W` | login screen background, in rices that follow it |

The helper asks separately (default **N**) whether to install `archenemy-system-theme.path`, a systemd unit that runs the script whenever one of these changes. Without it, apply by hand: `sudo /usr/local/lib/archenemy/system-theme-sync`. Switching the boot menu replaces one file (`theme.txt`); `grub.cfg` is not regenerated.

**Login monitor.** By default the form is on the primary monitor (the one marked primary in `[n] monitors`). `[g] login screen` picks another one. A chosen monitor that is not connected never leaves you with an empty screen: the theme works from the monitors that are actually connected and falls back to the primary one, also when a monitor is unplugged while the login screen is up. Connector names differ between Hyprland and the login screen's display server (`HDMI-A-1` vs `HDMI-1`, `eDP-2` vs `eDP-1`), so the match goes from the exact name, through connector type, to "built-in or external screen".

**If you cannot see the form.** A monitor can be connected but out of sight — a docked laptop with the lid closed still reports its panel. Every monitor without the form shows a small "click to log in on this screen" line; a click there moves the form to that monitor for this login. The lasting choice is `[g] login screen`.

**Keyboard and users.** `Enter` logs in, `F2` switches the user and `F3` the session (a click on the user or session name does the same). When SDDM lists no users at all — an account outside its UID range, a network account — the field first asks for the user name, then for the password; `F2` goes back to the name.

**Wallpaper.** In `tron`, `crt`, `dither-flux`, `asia-n-rice` and `white-blue` the background is the wallpaper you last set with `Super+W` (PNG or JPEG up to 64 MiB, copied into the theme directory — it is visible before login); other files, and rices whose wallpaper is not set, use the rice's own background. `yin` and `yang` always keep their eclipse wallpaper, because the form sits inside its disc.

**Safety.** The root script treats everything in your home directory as untrusted data: state files are read with your own privileges (`setpriv`), with size and time limits; rice and monitor names must match a strict pattern and the rice must have a theme installed by root; nothing read from there is executed. After `git pull` the copies in the system are older than the sources — the updater (`[u]`) says so when the theme sources changed; run the helper again to refresh them.

**Without graphics acceleration** (a virtual machine, a broken driver) Qt draws in software and cannot render glow or blur: the login screens stay usable, only without those effects.

**Not covered:** Fedora and NixOS (the helper prints what to do and changes nothing), other display managers, Plymouth. A theme for your own rice needs `rices/<rice>/system-theme.conf` and a layout in `src/system-theme/sddm/<rice>/`; a rice without them keeps the previous login screen and boot menu. Previews without a reboot: `src/system-theme/tools/render-sddm.sh` and `render-grub.sh` (dev tools, see their headers).

## Fonts

Each rice has a fixed default font. `Super + A` → `[f] fonts` keeps it or replaces the **family** with any installed font; sizes stay as the rice sets them (terminal 11.5, rofi 11), so layouts don't shift.

| Rice | Terminal (alacritty) | rofi | waybar | mako | hyprlock |
|---|---|---|---|---|---|
| `white-blue` | JetBrainsMono Nerd Font 11.5 | JetBrainsMono Nerd Font 11 | Iosevka Nerd Font 12px | JetBrainsMono Nerd Font 11 | JetBrainsMono Nerd Font |
| `tron`, `crt`, `dither-flux`, `yin`, `yang` | JetBrainsMono Nerd Font 11.5 | JetBrainsMono Nerd Font 11 | Iosevka Nerd Font 12px | JetBrainsMono Nerd Font 11 | JetBrainsMono Nerd Font |
| `asia-n-rice` | JetBrainsMono Nerd Font 11.5 | JetBrainsMono Nerd Font 11 | IosevkaTerm Nerd Font 12px | JetBrainsMono Nerd Font 11 | JetBrainsMono Nerd Font |
| `white-blue_beta` | JetBrainsMono Nerd Font 11.5 | JetBrainsMono Nerd Font 11 | Iosevka Nerd Font 12px | from `white-blue` | from `white-blue` |

JetBrainsMono Nerd Font and Iosevka Nerd Font come from `ttf-jetbrains-mono-nerd` and `ttf-iosevka-nerd` (`packages/requirements-pacman.txt`). The distinct IosevkaTerm Nerd Font requested by the asia-n-rice waybar has no matching package on these lists; that bar may use a fontconfig fallback unless you install that family yourself. No package is added automatically for it. swayosd, MangoHud and nvim set no font: swayosd and MangoHud use their built-in fonts, and nvim and ncmpcpp use the terminal font. GTK/Qt fonts are not set by archenemy.

**How it works.** The rice's terminal family lives in `rices/<rice>/alacritty/font.toml`. Each rice's `alacritty.toml` imports it first and then `~/.config/archenemy/fonts/alacritty.toml`. Alacritty skips a missing import, so with no choice saved the rice font applies. `[d]` uses the rice font and removes the choice. `[l]` lists installed fonts from `fc-list`, monospace first, and `[a]` shows all fonts. Names with control characters, quotes, backslashes, `$`, `:` or `,` are skipped. The screen shows a sample, says whether the font has Nerd Font icons, and checks that the font is still installed before saving. `[u]` restores the previous choice. Writes and resets take a `flock` lock, prepare the complete new state and backups in a temporary directory, then publish with `mv -T`. If publication fails, all three files, including `family.prev`, are restored. Directories and symlinks at any managed target (including the lock file) are refused, as is a state directory resolving into the repository. Undo reads the previous choice while holding the same lock. Menus time out after 120 s without input.

| Applies to | Covered | When / why |
|---|---|---|
| Alacritty and terminal apps (nvim, ncmpcpp, btop) | conditional | open a new terminal using the rice config and its imports; a personal config may omit the import or override family/size |
| rofi: launcher, power, rice and wallpaper menus | yes | next time a menu opens (`-theme-str` from `scripts/appbinds/lib/fonts.sh`) |
| fastfetch | yes | `FONT` / `Terminal Font` row labels the archenemy choice as unverified, next run; it does not measure the font in the terminal. fastfetch silently drops a `command` row that prints nothing, so if `font-settings.sh` cannot run the row falls back to the family in the Alacritty font files (`… (alacritty config)`) and never disappears |
| waybar | no | a GTK CSS import of a missing file stops the bar from loading its style |
| mako | no | a missing `include=` aborts its whole config |
| hyprlock | no | labels can't be overridden from outside; the lock screen stays as the rice ships it |
| Wi-Fi menu (networkmanager-dmenu) | no | it starts rofi itself |
| swayosd, MangoHud, GTK/Qt apps | no | not set by the rices |

Open a new terminal after the first choice, subsequent changes, reset and choosing again. An already open Alacritty window may not watch a previously missing import, so live reload is not promised. `current` and fastfetch always label the family as an **archenemy choice**, with **unverified** terminal state. They distinguish the rice Alacritty config, personal/unknown Alacritty configs (imports and local family/size overrides unverified), and other/unknown terminals. Even a recognized rice config cannot confirm command-line overrides, runtime zoom or what an existing window loaded. No terminal size is reported as measured.

`white-blue_beta` is frozen and keeps its own font; a saved choice applies again after switching to another rice. Scripts can call `scripts/appbinds/font-settings.sh set "<family>"`, `reset`, `undo` or `current`.

## Custom app shortcuts (Super + A)

`Super + A` opens the archenemy settings menu: a list grouped by area with each entry's current value, and a preview of the selected entry on the right (hidden in narrow terminals). Arrow keys and Enter move around; pressing an entry's letter opens it directly. Colours follow the active rice, with one accent per rice and at least 4.5:1 contrast (`tests/tui-contrast.sh`). Its first job is app shortcuts: you pick a key (e.g. `g`, `F5`, `semicolon`, `SHIFT+g`) and a command (e.g. `spotify`), and the shortcut works right away. `[e]` changes the command of an existing bind; `[d]` removes one after a separate confirmation (default No). The manager checks key names against the local XKB header when available, guards against collisions with existing archenemy shortcuts, reloads Hyprland, reads `hyprctl configerrors` and undoes the change if the config breaks. The green `✓ Added / Changed / Removed` appears only after the file was read back and the reload reported no errors; a failed write (full disk, read-only file) is reported as such and Hyprland is not reloaded, and without a Hyprland answer the menu says `Saved` instead. The `[s]` option shows a full cheat sheet of every current shortcut — what's under each key and which app/action it launches. Your binds go into `config/hypr/appbinds.lua` — a personal file outside git, so they survive `git pull` and switching rice.

**Two more ways in (installer step [8m]).** The same menu shows up in rofi (`Super + R`) as **archenemy** — `install.sh` writes `~/.local/share/applications/archenemy.desktop` (with this machine's absolute path, because `.desktop` files don't expand `~`; an existing file of that name is never overwritten). And in a terminal you can type `archenemy` to run it right there: the installer asks before adding one marked `alias archenemy=…` line to your shared shell file (see below, so it works in bash and zsh), never adds it twice and leaves your own `archenemy` alias alone; an alias added to `~/.bashrc` by an older installer is moved there without asking (a dated copy of `~/.bashrc` is kept). Open a new terminal (or `exec $SHELL`) after installing. The `white-blue_beta` rice has no `Super + A` bind by design — these two entries work there too.

The same TUI has extra entries: `[w]` — shared/decades workspace mode switcher (see "Workspaces"), `[f] fonts` — the rice font or any installed font (see "Fonts"), `[o] audio` — default output and input for all apps, plus `[o] → 3` mpd music output: pipewire (recommended) or an exclusive ALSA `hw:` device for mpd (see "Music stack"), `[p] autostart apps` — pick which apps launch at Hyprland startup from the list of all `.desktop` entries (checkboxes `[x]`/`[ ]`, filter by name via `/text`; the selection lands in `data/autostart-apps.dat`, from which a personal `config/hypr/autostart-apps.lua` is generated — alongside the manual `autostartpersonalisation.lua`, which this layer doesn't touch), `[v] volume bar` — the waybar volume bar style (`line` ━━━━━━────, `ticks` ▮▮▮▮▮▮▯▯▯▯, `solid` ▬▬▬▬▬▬▬▬▬▬▬▬────────), saved in `data/volume-bar-style.dat` and applied immediately (signal 10 to waybar), `[l] system logo` — one logo for the left box of the bar, fastfetch, the login screen and the boot menu: `distro logo` (default; the Arch/Fedora/NixOS glyph from `/etc/os-release`, a generic Linux glyph otherwise — the preview shows the detected distribution) or `archenemy logo` (Æ), saved in `data/launcher-logo.dat` and applied to the bar immediately (signal 12; rices without a launcher keep the choice for later and say so), `[g] login screen` — which monitor shows the login form (default: the primary monitor; see "Login screen and boot menu"), `[t] timer` — a countdown timer next to the clock (see "Timer"); all three report `✓` only when waybar is running and took the refresh signal, otherwise they say the setting is saved and when the bar will show it; a waybar still running an older bar config (it reads `config.jsonc` only at start, e.g. after a manual `git pull`) is reloaded instead (`SIGUSR2`), `[k] keyboard layouts` — pick how many layouts you use (1–4, the XKB maximum) and which ones: a list of European layouts (Polish, English US/UK, German incl. Austria/Switzerland, French, Belgian, Dutch, Spanish, Portuguese, Italian, Slovenian, Croatian, Serbian, Bosnian, Czech, Slovak, Hungarian, Romanian, Bulgarian, Greek, Russian, Ukrainian, Belarusian, Lithuanian, Latvian, Estonian, Finnish, Swedish, Norwegian, Danish, Icelandic, Turkish) or any XKB layout code; an optional second step changes the order on a selection screen: for each place you pick one of the remaining layouts with ↑/↓ (or `j`/`k`) and Enter, Esc cancels without changes, and typing the whole order as numbers on the first screen (e.g. `2 1`, then Enter) still works as a shortcut. Layout #1 is active after login; `Super + K` cycles through the list and `Super + Ctrl + 1…4` jumps straight to layout #1–4. The list is saved in `data/keyboard-layouts.dat`, written to the personal `config/hypr/keyboard-layouts.lua` (every rice except `white-blue_beta` loads it after its `input` block; without it you keep `pl,us`) and applied with `hyprctl reload`, then read back; `[m] mouse` — speed from `-1.0` to `1.0` in any step, DPI, polling rate, acceleration (`flat` or `adaptive`), scroll speed, natural scroll and left-handed mode. DPI comes in two kinds. With the optional `libratbag` package and a supported mouse, DPI and polling rate are real hardware values written to the mouse's memory and read back. Otherwise you give your mouse's own DPI once and pick a target from 5% to 200% of it: this is speed in disguise, and it is exact only with `flat` acceleration, where pointer speed is `1 + speed` (libinput's flat filter). Everything else is saved in `data/mouse-sensitivity.dat` and `data/mouse-settings.dat`, written to the personal `config/hypr/mouse.lua` (every rice except `white-blue_beta` loads it right after its `input` block) and applied at once with `hyprctl reload`, then read back with `hyprctl getoption` — the TUI says so if Hyprland reports a different value; and `[u] update archenemy` — the repo updater: pick a branch (`dev` — latest changes / `main` — stable releases only), the script runs `git fetch`/`checkout`/`pull --ff-only`, stashing any local changes to git-tracked files with `git stash` for the duration of the pull and restoring them afterward. It reports what really happened: "✓ updated" only when your checkout equals `origin/<branch>`; a failed fetch/pull or a stash that can't be restored is shown as an error (the stash stays in `git stash list`, nothing is lost); local commits on top of origin get a warning. Switching to a branch that doesn't contain what you currently run (e.g. `main` while it's behind `dev`) rolls your configs back, so the updater warns and asks first (`y` to go ahead, default no). The machine and personal layers (monitors, appbinds, autostart, rice, volume bar style...) are outside git, so the update doesn't touch them — your settings stay unchanged by default. When the update changed the bar's config or its scripts and waybar is running, it reloads waybar (`SIGUSR2`), so the bar shows the change without a restart. At the end it offers to re-run `install.sh` to generate any new machine files. `[c] terminal` — show or toggle Alacritty copy on select (`[selection] save_to_clipboard`) in the active `~/.config/alacritty/alacritty.toml`; only that setting changes, `alacritty.toml.bak` is kept from the first change for rollback, and Alacritty reloads it automatically. The setting must already exist, and the file must resolve outside the repository: the default rice symlink is refused. To use this toggle, keep a personal Alacritty configuration outside the repo.

`[n] monitors` changes resolution, refresh rate, scale and position without running the installer. A map shows how the screens sit in space. You pick the resolution, then the refresh rate available for it (or `p` preferred, `h` highest resolution, `f` highest refresh rate). The scale prompt lists the values that divide that resolution cleanly. Position is the top left corner in logical pixels, so a 3840x2160 screen at scale 2 is 1920 wide: type `XxY` (negative values work), `auto`, or `l 2`, `r 2`, `a 2`, `b 2` for left of, right of, above or below monitor 2. Overlapping positions are refused: Hyprland keeps such a layout but warns that it causes issues. The refusal names the monitor in the way and the forms that put the screen beside it, so changing sides is one step: pick the monitor that should move and type `l 1` or `r 1`. Logical sizes follow Hyprland's rounding of fractional scales (a 2560 wide panel at 1.33 is 1920 wide), so screens meet without a gap. A monitor saved as `preferred`, `highres` or `highrr` keeps that mode on Enter and goes on to scale and position. When a screen changes size and keeps its position, the monitors attached to its right and bottom edges move with it. The change starts as a trial: press `y` or select Yes within 15 seconds to keep it; No, Esc, timeout or closing the window restores the previous setting, because a wrong mode can leave you with a black screen. Success is what `hyprctl monitors` shows afterwards: when Hyprland shows something else, the menu says so instead of printing a green tick. A new resolution generates matching dither-flux wallpapers in the background.

**Connecting a new monitor needs no installer run.** Hyprland shows it right away with safe defaults, and a notification points to `[n]`, where it is listed as `new`. Pick it, confirm the mode, position, scale, wallpaper role and numbering, then press `y`. It gets its own monitor and workspace rules and a wallpaper. A monitor moved to another port is not new: it keeps its settings, because it is recognised by its EDID description.

In the same menu, `r` renumbers monitors left to right (numbers and workspaces only: it never moves a screen, and says so when the numbers you chose no longer follow the layout), and picking an unplugged monitor offers to forget it, which frees its number and workspaces. In `decades` mode, windows on a monitor whose workspace numbers changed move along with it. In `shared` mode open windows stay on their workspaces.

`[h] shell` picks your shell and keeps your commands in one place. Your aliases, functions, environment variables and `PATH` live in `~/archenemy/config/shell/shellrc` — a personal file outside git, so `git pull` and the updater never touch it (back it up like your dotfiles). `~/.bashrc` and `~/.zshrc` only load it through a short marked block (`# >>> archenemy shell >>>` … `# <<< archenemy shell <<<`), so when you switch shells your commands come along. The file has a "common" part that both shells must understand (`alias`, `export`, `PATH=…`, simple functions) and "bash only" / "zsh only" sections at the bottom for things like `shopt` or `setopt`. In the menu:

- `1` opens the file in neovim. After you save and quit it runs `bash -n` (and `zsh -n` when zsh is installed); on a syntax error it shows the message and lets you edit again, restore the version from before the edit, or keep it. Changes apply to new terminals, or run `exec $SHELL` in the current one.
- `2` opens a list of login shells: bash and zsh, with the current shell highlighted. Choosing zsh installs it after asking (`sudo pacman -S --needed zsh`), creates `~/.zshrc` with the block (or adds the block to yours) and loads `config/shell/zsh-defaults.zsh` first: history, completion, bash-like keys and prompt, no frameworks. It then offers to move your `~/.bashrc` lines into the shared file and asks before changing your login shell with `chsh` (it asks for your password). Success means your passwd entry shows the new shell, and the menu tells you how to get back: the same entry again, or `chsh -s /bin/bash`. Log out and back in afterwards.
- `3` moves the plain one-line `alias`, `export` and `NAME=value` lines from `~/.bashrc` into the shared file, with the comments right above them, after showing them and asking. It stays visible when there is nothing to move and reports that state. The prompt (`PS1`), bash history settings, functions, `if`/`for` blocks, `shopt` and `source` lines stay in `~/.bashrc`.
- `4` sets the zsh vi-mode key. It defaults to `Ctrl+X Ctrl+V`, which zsh already binds to `vi-cmd-mode`; choose another combination or restore that default. Press the keys at your own pace and finish with Enter; a 30-second idle timeout cancels, and a standalone Escape goes back. The TUI checks documented defaults, live zsh bindings when zsh is installed, and visible `bindkey` entries in your shell files, then asks before replacing or overlapping a binding. The personal `keys.zsh` is loaded after zsh defaults and before `shellrc`, so manual bindings in your file take precedence. Bash is unaffected.

- `5` opens **zsh plugins**: `[x]` means enabled by archenemy, `[ ]` means disabled. ↑/↓ or `j`/`k` move; Space or Enter toggles; Esc returns. Options: `zsh-autosuggestions` (recommended: gray history suggestions), `zsh-syntax-highlighting` (valid/invalid command colors), and `zsh-completions` (additional completions, active while the package is installed). All start disabled. Missing packages are offered with `sudo pacman -S --needed <package>` and a separate `[y/N]` confirmation. CLI tool packages use `[Y/n]`; both menus show their default explicitly and Esc cancels. After a successful switch to zsh, the menu offers autosuggestions with `[Y/n]`; installing its package still requires `[y/N]`.

Plugin choices live in the gitignored personal `config/shell/plugins.zsh`, written only by `scripts/shell/lib/shell-rc.sh`. Each generated file carries a SHA-256 checksum independent of the current template; legacy unsigned files are recognized against the frozen v1 text. Changes keep `plugins.zsh.bak-<date>`; identical saves do nothing, and custom content or symlinks are refused. The shared zsh defaults register enabled completion paths before `compinit`, then load plugins after `shellrc` and CLI initialization in the managed rc block, with syntax highlighting last. Older rc blocks keep the previous plugin load order until a plugin toggle in `[h] → 5` refreshes them. User code after that block still runs later; place custom widgets before the block to have them available when highlighting loads. Missing plugin files are skipped, and plugin configuration variables are left to the user. The shell summary lists enabled choices. Open a new terminal to apply a toggle; disable it in the same menu to undo it. Packages are kept: completions already available through your system or personal `fpath` remain available independently of this menu. Arch installs extra completions in [`/usr/share/zsh/site-functions`](https://archlinux.org/packages/extra/any/zsh-completions/files/); plugin ordering follows the [upstream instructions](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md).

**[h] on Fedora and NixOS (experimental).** The menu finds the platform with the same `pkg_route` as the installer (os-release; Arch derivatives take the Arch path), so it works the same when started later from Super+A. Arch and its derivatives keep exactly the behaviour described above (`SHELL_PLATFORMS_REV=<rev> bash tests/shell-platforms.sh` compares questions, commands and files with that revision). On **Fedora** packages come from `pkg_install` — `sudo dnf install --repo=fedora --repo=updates <RPM>` from `packages/platform-map.tsv` — with the same questions and defaults (plugins `[y/N]`, CLI tools and zsh `[Y/n]`, `chsh` `[Y/n]`); a plugin is enabled only when `rpm -q` finds the RPM **and** its file exists (`/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh`, `/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`), a CLI tool only when its command is on `PATH` (`fd-find` → `fd`, `ripgrep` → `rg`). A failed `rpm` query is reported as such, not as "missing". `zsh-completions` has no Fedora package: the menu says so and installs nothing. On **NixOS** archenemy installs nothing and never runs `chsh`: choosing a login shell prints `users.users.<you>.shell = pkgs.zsh;` (with `programs.zsh.enable = true;`) or `pkgs.bashInteractive` for bash, to apply with `nixos-rebuild switch` and a new login; without zsh nothing is written. A plugin is enabled only when its file is in one of your Nix profiles (`~/.nix-profile`, `~/.local/state/nix/profile`, `/etc/profiles/per-user/<you>`, `/run/current-system/sw`); otherwise the menu points to `programs.zsh.autosuggestions.enable` / home-manager `programs.zsh.autosuggestion.enable`, `programs.zsh.syntaxHighlighting.enable`, or the package for `home.packages`. A plugin already loaded by NixOS or home-manager is not loaded a second time. NixOS adds completions from every profile to `fpath` itself, so the `zsh-completions` entry only tells you to add the package. CLI tools and neovim get the `pkgs.<name>` to add. On other distributions, or without `install/lib/pkg.sh`, the menu installs nothing and says so; `chsh` still works there. Plugin paths per platform live in `shell_plugin_paths` (`scripts/shell/lib/shell-rc.sh`); Arch keeps the frozen v1 file, Fedora/NixOS get a signed file with a `# archenemy plugin paths: <platform>` line.

`6` opens **CLI tools**, then a shell picker (bash/zsh) and a checklist with each tool's SPDX license. All choices start disabled, independently for each shell. ↑/↓ or `j`/`k` move, Space/Enter toggles, and Esc/`q` returns. Unsupported tools remain visible as unavailable. If a command is missing, `[Y/n]` asks before running `sudo pacman -S --needed <package>`; refusal or failed installation leaves it disabled. No package is removed when you disable a choice. Ordinary programs (`fd` and `rg`) remain in PATH for both shells once installed; their switches record your choices without adding aliases or initialization.

The gitignored personal `config/shell/cli-tools.bash` and `cli-tools.zsh` hold marked blocks, written only by `shell-rc.sh` with dated backups and identical saves left unchanged. Custom content or symlinks are refused. The selected shell's rc block loads its file after `shellrc`; opening a new terminal applies changes. Disable a tool in the same menu to remove its block. zoxide uses `eval "$(zoxide init bash)"` / `eval "$(zoxide init zsh)"`, providing `z`/`zi` while preserving `cd` ([upstream setup and flags](https://github.com/ajeetdsouza/zoxide#installation)). Interactive `zi` additionally needs optional `fzf`, which this menu does not install.

| Tool | Upstream | SPDX license | Distribution |
|---|---|---|---|
| fd | [sharkdp/fd](https://github.com/sharkdp/fd) | MIT OR Apache-2.0 | installed from the distribution package, not bundled |
| ripgrep (`rg`) | [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) | MIT OR Unlicense | installed from the distribution package, not bundled |
| zoxide | [ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide) | MIT | installed from the distribution package, not bundled |

See [THIRD-PARTY.md](THIRD-PARTY.md). Extend the menu with one row in the trusted, tracked `config/shell/cli-tools.tsv`: name, repository URL, SPDX license, pacman package, command checked with `command -v`, comma-separated shells, bash initialization, zsh initialization. Separate the eight fields with tabs; empty initialization fields are allowed. Initialization is one line of shell code, executed only by the selected shell after enabling. No TUI logic changes are needed. Add the corresponding package to the optional package list and document its license when publishing a new catalog entry. Generated files carry a SHA-256 checksum (coreutils) so catalog/template updates can regenerate them with a backup; manually changed content is refused. Unsigned v1 files are recognized using the frozen `cli-tools-v1.tsv` catalog.

In `[h]`, syntax-error recovery keeps `e` for edit and `r` for restore; `3` keeps the file with its error (`k` moves the cursor). Piped input works without a TTY, and EOF cancels a list. See "Settings menu navigation" for the shared controls.

Every change to `~/.bashrc` or `~/.zshrc` keeps a dated copy next to it (`~/.bashrc.bak-<date>`), a `~/.bashrc` that is a symlink (e.g. GNU stow) stays a symlink — but one that home-manager manages (a link into `/nix/store`, `programs.bash`/`programs.zsh`) is left alone, without a backup, and `[h]` and the installer print the archenemy block to add to `programs.bash.initExtra` (zsh: `programs.zsh.initContent`) instead; moving your lines out of it is not offered, and an old `archenemy` alias in it stays there (no backup, nothing added to the shared file; remove it in home-manager and re-run the installer) —, and repeating an unchanged managed-file save makes no further change. An incomplete marked rc block is refused rather than overwritten. `install.sh` (step [8m]) creates the shared file and adds the block to `~/.bashrc` silently; it also refreshes an existing managed `~/.zshrc` block. It asks separately about the `archenemy` alias, migrates its own legacy alias automatically, and leaves shell selection and migration of your other lines to `[h]`.

`[i] diagnostics` runs a read-only check of the generated config against the connected monitors, and saves workspace and GPU dumps as `~/archenemy-diag-*.txt`. Those files list your hardware, including monitor serial numbers, so keep them private.

Volume: waybar's `pulseaudio` module has been replaced with a custom `custom/volumebar` (script `scripts/waybar/volume-bar.sh`) — it draws a fill bar with a percentage instead of just an icon. Scrolling on the bar and volume keys work as before (hardware keys additionally send waybar signal 10 = instant bar refresh). Click: left-click opens `pavucontrol`, right-click mutes. Three styles selectable in `Super+A` → `[v]`: `line` (thin bar, 10 cells), `ticks` (▮▮▯ segments, 10 cells), and `solid` (a thick volume block on a thin line, longer — 20 cells, 5% per cell). The `>100%` state (boost) has its own color class per rice. The speaker icon automatically switches to headphones when the default sink's Active Port (from `pactl`, read in the C locale, so any system language works) points to a headphone output — and switches back on unplug; detected in the same `interval:1` backstop, no separate trigger. The headphone glyph itself sits lower than the speaker and mic glyphs in Iosevka, so the script nudges it up with a pango span (`rise`) — the correction height is a single `ICON_RISE_HEADPHONES` constant at the top of `volume-bar.sh` (positive = up, negative = down, `0` = no correction).

Power profile: the `custom/profileswitcher` module shows the current profile, and clicking cycles through them. On ASUS ROG machines the **top hardware profile key** (`XF86Launch4`) does the same thing — since 2026-09-07 it goes through the same path as a click, i.e. `scripts/waybar/profile-switch.sh`: the change is verified against `/sys/firmware/acpi/platform_profile`, with an automatic fallback to `power-profiles-daemon` if `asusd` is dead, and if nothing works a critical notification shows the tool's actual error. With `power-profiles-daemon` the click cycles only through the profiles `powerprofilesctl list` offers (hardware without a platform driver has no `performance`), and a profile that does not take is skipped for the next one. Previously the key called raw `asusctl`, which can exit with code 0 without changing anything (client newer than the daemon after an update without restarting `asusd`) — the bar would refresh, the profile would stay the old one, and the key would look dead. The bind is in the machine layer (`config/hypr/hardware-keys.lua`, generated by `install.sh`), so it needs another installer run after a repo update.

Do not disturb: the bell (`custom/dnd`, script `scripts/waybar/dnd.sh`) sits between the battery and the tray in the seven non-beta rices. A click toggles mako's `do-not-disturb` mode: the bell turns into a crossed-out bell in the rice's accent color, and ordinary notifications stop showing (they still expire on their usual timeout into mako's history, so nothing floods the screen when you turn the mode off, and `makoctl restore` brings back the most recent one). **Critical notifications still show** (`notify-send -u critical` — the timer finishing, archenemy's own error messages): each rice's `mako/config` has a `[mode=do-not-disturb urgency=critical]` section with `invisible=0` after `[mode=do-not-disturb]`. The tooltip says what the next click does. The state is read from `makoctl mode` every time (no state file), the bar refreshes right after a click (waybar signal 13) and every 10 seconds otherwise, so a mode set from a terminal (`makoctl mode -a do-not-disturb`) shows up too. Restarting mako turns do-not-disturb off. When mako is not running the bell shows a dimmed "unavailable" icon and a click does nothing — the script never calls `makoctl` then, because that could start mako through D-Bus activation. There is no keyboard shortcut; `white-blue_beta` stays frozen without the bell.

### ASUS laptops

`install/asus-installation.sh` (run by the installer, or on its own any time) installs `asusctl` and `rog-control-center` with pacman from the official repo, so they update with a normal `pacman -Syu` and nothing compiles on your machine. On Fedora and NixOS it only points to the [asus-linux Fedora guide](https://asus-linux.org/guides/fedora-guide/) or `services.asusd.enable = true;` and exits with code 2, without touching any package.

Why not the AUR: it has several packages that all claim to be `asusctl` and exclude each other, and some are dead. The script handles them like this:

| Found on your machine | What happens |
|---|---|
| `asusctl-devel-git`, `asusctl-git`, `asusctl-x11`, `asusctl-nosystemd`, `rog-control-center-x11`, `rog-control-center-nosystemd` | pacman asks to replace them in one transaction, answer `y`. If it fails, you keep what you had. |
| `supergfxctl`, `supergfxctl-git`, `plasma6-applets-supergfxctl`, `asusctltray-git`, `asusctl-nosystemd-dinit` | Listed with a question, default no. `supergfxctl` stays unless it is in `Hybrid` mode, because removing it in `Integrated` could leave the graphics card off. |

Graphics switching needs nothing extra: the asus-linux guide says `supergfxctl` is not needed with current drivers. Users who added the `[ogc]` repo get the packages from there. `asusd` is started by a udev rule at boot and is not meant to be enabled, so the script starts it once and checks that it runs; if it does not, restart the computer. The power profile scripts use the `asusctl profile next` / `profile get` subcommands (asusctl 6.3.8+).

Screen brightness: the `XF86MonBrightness*` keys call `swayosd-client` — they change brightness and show an OSD bar at the bottom of every monitor (the `swayosd-server` starts with each rice and is restarted when switching rice, since it only reads the theme at startup). Per-rice OSD theme: `rices/*/swayosd/style.css` (beta inherits from white-blue via symlink). Package: `swayosd` (official `extra` repo, a tagged 0.3.x release). If you still have `swayosd-git` installed, pacman asks to remove it when the installer pulls in `swayosd` — answer `y`.

## Music stack (optional — a recommendation, not a requirement)

Nothing here is required: `mpd`, `mpc`, `ncmpcpp` (and `mpv`) live in `packages/additional-packages-pacman.txt`, so they only get installed when you pick them in the installer's "additional packages" menu. Pick **mpd + mpc + ncmpcpp together** — they are one stack (daemon, CLI, TUI client); `mpv` is independent. Without the binaries the linked rice folders `ncmpcpp/` and `mpv/` are unused and installer step **[8l]** is silently skipped.

**What each non-beta rice ships.** `rices/<rice>/ncmpcpp/config` — a skin based on **terminal colors**: ncmpcpp takes its colors from the terminal, so every rice's config just assigns roles (list text, header, accent, dim lines, progress bar, now-playing line, visualizer gradient) to that rice's ANSI palette from `alacritty/alacritty.toml`. Numbers in the config are ncmpcpp's own 1-based indexes: `1`–`8` = ANSI 0–7, `9`–`16` = the bright half (`9` bright black, `13` bright blue, `15` bright cyan, `16` bright white) — ncmpcpp maps number N to ncurses color N−1, and `:b` (bold) does not give you bright colors in alacritty. The skin also sets ncmpcpp's working and lyrics directories and connects its stereo visualizer to `/tmp/mpd.fifo` (`Visualizer feed`). It leaves the visualizer type and bar glyphs at their defaults; song-column and selection formats assign palette colors. The skin therefore looks right in the rice's alacritty and simply takes another terminal's palette elsewhere — same as the nvim themes. Key bindings are **vim-like** (`j`/`k`, `h`/`l` for columns / master–slave screen / directories, `g`/`G`, `Ctrl-d`/`Ctrl-u`, `/` `?` `n` `N`, `J`/`K` move selected items, `d` delete; displaced defaults: lyrics `L`, jump-to-position `Ctrl-g`, jump-to-browser `Ctrl-b`) in `rices/white-blue/ncmpcpp/bindings`; the other rices point at it with a relative symlink committed to the repo. `rices/<rice>/mpv/mpv.conf` holds **only** the OSD colors (`osd-color`, `osd-outline-color`) in the rice's palette — no other mpv settings. Note the usual rice-folder rule applies to `~/.config/mpv` and `~/.config/ncmpcpp`: a real directory of yours is moved to `<name>.bak-<timestamp>` by the installer/switcher, never deleted.

**Layers.** `config/mpd/mpd.conf` is the shared layer (`~/Music`, all state in `~/.local/state/mpd/`, a `fifo` output named `Visualizer feed` that feeds ncmpcpp's visualizer, `bind_to_address localhost`, `restore_paused yes`). It `include`s two generated, gitignored files: `config/mpd/output.conf` — the **machine layer**: the actual audio output (`pipewire` by default; rewritten by `Super+A → [o]`) — and `config/mpd/local.conf` — the **personal layer** (`include_optional`): put your own `music_directory`, extra outputs etc. there. ncmpcpp's working files (`error.log`, `patterns.list`, lyrics) go to `~/.local/share/ncmpcpp/` — the rice folder is a symlink into this repo, so `ncmpcpp_directory` must stay outside it (`ncmpcpp` appends to that directory).

**Installer step [8l] never breaks an existing setup.** It runs only when `mpd`/`ncmpcpp` are installed and: generates `output.conf`/`local.conf` only if missing; links `~/.config/mpd → config/mpd` **only if you have no mpd config** — an existing `~/.config/mpd` (or `~/.mpdconf`, `~/.mpd`), including a broken symlink, is left alone unless you answer `y`, and then it is kept as `~/.config/mpd.bak-<timestamp>`; the `✓` comes only after the new link is read back, otherwise the summary gives the `ln` command to finish by hand; enables the **user** service only after asking (`systemctl --user enable --now mpd`) and not at all when a **system-wide** mpd is enabled (two daemons would fight over port 6600 and the sound card); if you enabled the user `mpd.socket` yourself, it warns instead of saying "already enabled" — socket activation listens on port 6600 on all interfaces and ignores `bind_to_address "localhost"`, so mpd (no password) is reachable from your network unless a firewall blocks it — and gives the command to switch to the local-only `mpd.service`, without changing anything — that warning is for Arch's packaged `mpd.socket` (`ListenStream=6600`); on Fedora and NixOS the installer first reads `systemctl --user show -p Listen mpd.socket` and warns only when it shows a non-local address (a loopback-only socket, home-manager's default, is left alone without a warning; when Listen cannot be read it tells you how to check and what to do if it shows `[::]:6600` or `0.0.0.0:6600`) (on NixOS: remove the socket from your configuration — home-manager `services.mpd.network.startWhenNeeded = false;` or `systemd.user.sockets.mpd.enable = false;` — never a `systemctl` command); the `✓` for the user service comes only when it is both enabled and active — an enabled service that is not running, and an `enable --now` that returned 0 without effect, are reported with `systemctl --user status mpd` / `journalctl --user -u mpd` and listed in the summary; copies `ncmpcpp.desktop` to `~/.local/share/applications/` only if there is none (it makes ncmpcpp show up in rofi's `Super+R` and in `Super+A → [p]`; it starts `alacritty --class ncmpcpp -e ncmpcpp`). A second run is a no-op. Music from mpd goes through PipeWire like any app: volume keys/waybar apply to it and the music-reactive wallpapers (♪) react to it with no extra setup.

**Audio output: pipewire is recommended.** `Super+A → [o] → 3` switches mpd's output between `pipewire` and an exclusive ALSA `hw:C,D` device (listed from `/proc/asound`, with a "busy" hint when something — usually PipeWire — holds it). Read the warning before choosing ALSA: while mpd holds the card, notifications, the browser, volume keys and the ♪ wallpapers may lose audio, and if PipeWire holds the card first, mpd cannot open it. The switch rewrites `output.conf`, restarts `mpd.service`, runs a 1-second test play, puts playback back as it was and, if mpd reports an error, **rolls back to pipewire on its own**; it never stops or restarts PipeWire/WirePlumber — that would take the whole desktop's audio with it. ALSA output uses `mixer_type "software"` so mpd never turns the hardware mixer knob underneath PipeWire. Releasing the card from PipeWire for bit-perfect playback is deliberately left as a manual, out-of-archenemy step. The menu refuses to act when mpd would not read the change (`~/.config/mpd` not linked, or mpd running as a system service). After switching it plays one second from your queue on the main output alone, with the visualizer `fifo` output disabled for the test: mpd reports an output error only when no output opens, and the fifo always opens, so otherwise a dead output would look like success. An empty queue is reported as "not verified", never as success.

## Clipboard history

`Super+C` opens `scripts/rofi/rofi_clipboard.sh` in the current rice's rofi theme
(all seven non-beta rices). Select an entry to copy its full text or image, then
paste with `Ctrl+V`. Esc closes the menu. Text previews occupy one line; image
previews use the shared thumbnail library with a time budget and a private,
temporary cache under `$XDG_CACHE_HOME` (default `~/.cache`), removed on exit.
`Delete entry` opens a second list to choose what to remove; `Clear history`
asks for confirmation, with **No** selected by default. These actions remove
saved history; they do not clear the current clipboard. The selected entry is decoded
into a private temporary file before copying. A failed or empty decode leaves
the current clipboard unchanged; temporary files are removed when the menu exits.

The existing `wl-paste` watchers store text and images using `cliphist` (default
750 entries in `~/.cache/cliphist/db`). Both `cliphist` and `wl-clipboard` are
required packages. History persists across logins and may contain private data.
`cliphist` skips data marked `CLIPBOARD_STATE=sensitive` by `wl-paste`; this menu
preserves that behavior. Verify KeePassXC's sensitive clipboard handling in your
live session: do not assume every application marks secrets correctly.
See the [cliphist 0.7 source](https://github.com/sentriz/cliphist/blob/v0.7.0/cliphist.go).

## Bluetooth (optional)

Step [10] offers Bluetooth with bluez, bluez-utils, dbus (`dbus-monitor`) and
bluetui from Extra. Nothing is enabled by default. The separate installer
`install/bluetooth-installation.sh` verifies installed packages and that
`bluetooth.service` is both enabled and active before creating
`data/bluetooth-enabled.dat` (machine state, covered by `/data/` in `.gitignore`).
Failures appear in the installer summary with a command to retry, and a
failed run removes an icon flag left from an earlier run. Run by hand on
Fedora or NixOS, the installer changes nothing and exits with code 2: it prints
the Fedora packages (`bluez` — bluetoothctl —, `dbus-tools` — dbus-monitor —,
`bluetooth.service`; bluetui is not packaged for Fedora) or the NixOS option
`hardware.bluetooth.enable = true;` with `pkgs.bluetui`, and tells you to turn
the icon on yourself with `touch ~/archenemy/data/bluetooth-enabled.dat` once
`bluetoothctl show` lists your adapter.

Reload waybar after installation (or switch rice with `Super+T`). The seven
non-beta rices include `custom/bluetooth`; it emits empty text without the
flag, `bluetoothctl`, `timeout` (coreutils), Python or a controller. With a
controller it shows off, on or connected, with connected device names in the tooltip. Updates come
from BlueZ D-Bus events, including controller hotplug and daemon restart;
bursts are coalesced after 0.3 seconds of quiet. Without `dbus-monitor`, it
falls back to refreshing every 60 seconds and the icon can remain visible.
The stream follows the [custom module contract](https://man.archlinux.org/man/waybar-custom.5.en)
and uses [bluetoothctl](https://man.archlinux.org/man/bluetoothctl.1.en) and
[dbus-monitor](https://man.archlinux.org/man/dbus-monitor.1.en). Left-click opens a floating Alacritty running
bluetui, right-click toggles controller power. Power off keeps the off icon;
removing the controller hides it. Beta remains frozen. There is no Bluetooth
entry in `Super+A` yet. Removing the flag and reloading waybar hides the icon
without disabling the service; stream processes also accept SIGUSR1 to reread it.

**Once turned off, Bluetooth stays off across reboots, logins, suspend/resume
and controller replug until you turn it on again.** Right-click toggles
controller power. BlueZ does not remember power on its own: since BlueZ 5.65
`AutoEnable` (`[Policy]` in `/etc/bluetooth/main.conf`, default `true`) powers
on every controller it finds — at boot, when a controller is plugged in or
re-registers after resume, after a `bluetooth.service` restart — unblocking
rfkill powers it on too, and the adapter settings under `/var/lib/bluetooth`
have no power key. So the choice lives in `data/bluetooth-power.dat` (`on` or
`off`; machine state, ignored by git, written atomically) and the bar stream
keeps it:

- **Every deliberate change is saved.** Right-click writes the file before it
  changes power; overlapping clicks and saves from the bars take turns
  (`flock` on `$XDG_RUNTIME_DIR/archenemy-bluetooth.lock`), so a click whose
  power change failed restores the old file without overwriting a newer
  choice, and a newer choice always wins over an older change still being
  saved. Turning Bluetooth on or off anywhere else — bluetui,
  blueman, a phone, `bluetoothctl` — is saved by the stream once the new
  state has held for 2 seconds.
- **The system's own power-on is undone.** For 15 seconds after the events
  where BlueZ powers on by itself — the bar starting (login, waybar restart;
  counted from when `bluetoothd` started), a controller appearing,
  `bluetoothd` starting, waking from sleep (logind `PrepareForSleep`),
  rfkill being unblocked (also a quick block/unblock seen only in the
  `PowerState` of the signals), the stream reconnecting to D-Bus after
  losing it — a power-on while the file says `off` is switched
  off again (at most 3 times per event, so there is no on/off loop) and is
  not saved. Power-off by `bluetoothd` itself when it stops (also while
  `bluetooth.service` is still stopping or starting, which with several
  controllers can take longer than 2 seconds), and changes while
  the system is going to sleep or shutting down, are not saved either. A busy
  bus (device scans flood `PropertiesChanged`) does not delay this: the stream
  looks at the controller at least once a second.
- With `on`, a controller left off after such an event is switched on.
  No file, or anything other than exactly `on`/`off`, enforces nothing — the
  system decides; so does a missing icon flag.

Every bar (one per monitor) runs its own stream; they react to the same
system events the same way, so one bar never undoes what another just saved.
A change made elsewhere is announced to the other bars while it is being
confirmed (`$XDG_RUNTIME_DIR/archenemy-bluetooth.pending`, session tmpfs;
`data/` without it): a bar that starts in those 2 seconds — another monitor,
a waybar restart right after turning Bluetooth off in bluetui — takes the
pending change over instead of undoing it.

**Known limit — turning on from bluetui, blueman or `bluetoothctl` right
after such an event.** The power signal does not say who switched the
controller on, and a bar running as your user cannot see which program asked
`bluetoothd` to do it. So while the file says `off`, a power-on from
anywhere but the bar within the 15-second window after one of the events above
(after the bar starts: 15 seconds minus how long `bluetoothd` has been running)
is treated as the system and switched off again — up to 3 times; a fourth
power-on stays on for now but is not saved, and the next event switches it
off. Outside the window it is saved as usual. To turn Bluetooth on inside the
window, right-click the icon (the choice is saved before power changes and is
never undone) or wait 15 seconds and turn it on again. `AutoEnable=false`
(below) stops BlueZ from powering on by itself, but the bar still treats a
power-on in the window as the system's.

Changes made while no bar is running (for example from a TTY) are not seen; at the next login the
file wins. If `data/` cannot be written, right-click changes nothing and shows
a notification; a change from elsewhere stays, with a notification that it
was not saved, and the bar keeps retrying the save every 5 seconds (10
attempts) and keeps that choice itself until it exits. Nothing in `/etc` is
changed. To forget the choice: `rm ~/archenemy/data/bluetooth-power.dat`.

**Optional, for full certainty (system file, not done by archenemy):** with
`AutoEnable=false` BlueZ never powers a controller on by itself, so Bluetooth
also stays off between boot and login and no power-on depends on timing; with
`on`, the bar stream switches the controller on at login and after the events
above. This edits a system file and affects every user and the login screen:

```bash
sudo cp /etc/bluetooth/main.conf /etc/bluetooth/main.conf.archenemy-backup
sudoedit /etc/bluetooth/main.conf      # under [Policy]: AutoEnable=false
sudo systemctl restart bluetooth
```

To undo: `sudo mv /etc/bluetooth/main.conf.archenemy-backup /etc/bluetooth/main.conf && sudo systemctl restart bluetooth`.

Live-only: in each of the seven rices (beta excluded) inspect the icon, connect headphones,
check the tooltip and both clicks, remove/replug the controller and verify
`systemctl is-enabled bluetooth` and `systemctl is-active bluetooth` after reboot.
Right-click off, then log out and in, `systemctl suspend` and wake, reboot and
replug the controller: after each `bluetoothctl show | grep Powered` says `no`.
Turn it on in bluetui, suspend and wake: `Powered: yes`. Edge cases (off in
the file each time, `Powered: no` after): with two monitors turn it off in
bluetui and restart waybar within 2 seconds; wake while scanning (busy bus);
quick `rfkill block bluetooth; rfkill unblock bluetooth`; `systemctl restart
bluetooth` with one and with several controllers; two quick right-clicks.
Turn it on in bluetui 1 and 5 seconds after waking (undone, the known limit)
and after 15 seconds (stays on, saved).

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
(`notify-send`) when it reaches zero, also with a bar on every monitor: the
bars take turns under a lock on `data/`, and only the one that records the
finish sends it. The countdown is computed from the
wall clock, so reloading waybar or switching rice doesn't shift it.
Disabling the timer in the TUI hides the module entirely — the clock then
returns to exactly the center of the bar.

Settings and state live in the machine layer (outside git):
`data/timer-enabled.dat`, `timer-duration.dat`, `timer-color.dat`,
`timer-state.dat`. `white-blue_beta` doesn't have the timer (the rice is
frozen — bugfixes only).

## Keyboard shortcuts

These tables describe the seven non-beta rices. `white-blue_beta` retains its legacy binds: it has no built-in `Super+A`, `Super+C`, `Super+Tab`, `Super+Ctrl+1…4` or power-menu bind. Open settings there through rofi or the `archenemy` alias.

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
| `Super + C` | Clipboard history (copy a saved entry, then Ctrl+V to paste) |
| `Super + L` | Lock screen (hyprlock) |
| `Super + K` | Switch keyboard layout (next on your list) |
| `Super + Ctrl + 1…4` | Switch straight to keyboard layout #1–4 of your list (`Super + A` → `[k]`) |
| `Super + A` | Settings menu: app shortcuts, audio, monitors, keyboard, fonts, autostart, diagnostics |
| `Super + right Shift` | Power menu (shutdown / restart, then `Yes` in the same window, so a fast second Enter or double-click is not lost). Enter accepts when the key is released, so a held Enter stops at `Are you sure?`; `Ctrl+j` and `Ctrl+m` do not accept in this menu. With the screen locked (hyprlock) — direct shutdown, no menu or confirmation |

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
- Steam games (`steam_app_<id>`) come back through `steam steam://rungameid/<id>`, Flatpak apps through `flatpak run <id>`; archenemy's own tool windows (`archenemy-*`, e.g. the Super+A manager) are not recorded. Windows of any other sandbox (bubblewrap, firejail, chroot — a different mount namespace or root directory than the session) and windows whose `/proc/<pid>` cannot be read are not recorded either: a sandboxed program chooses its own command line, and `Super + Tab` would otherwise run it outside the sandbox.
- The history lives in `$XDG_RUNTIME_DIR` (memory, private to your user) and disappears on logout — command lines can contain file paths, so nothing is written to disk. `window-history.sh list` shows the stack.

### Workspaces — two modes to choose from

Monitors get **numbers 1, 2, 3… counted left to right** (the installer and `Super+A` → `[n]` propose an order based on screen positions; you can correct it), and at install time you pick one of two modes:

**Monitor identity.** Connector names (`eDP-2`, `HDMI-A-1`) are **not stable** — after a reboot or a replug Hyprland may hand the very same screens `eDP-1` and `HDMI-A-3`. Since 2026-09-21 the machine layer therefore targets monitors by their EDID description (`desc:<make model serial>`, saved as `DESCRIPTION=` in `data/monitors/<name>.dat` by step [3]): `monitorshyprl.lua`, `workspaces-monitors.lua`, `hyprpaper.conf` and the orphan guard all use that selector, which Hyprland, hyprpaper and hyprlock match by prefix. The connector name is still stored (it decides which monitor is the built-in panel, and it names the generated `dither-flux` files). `.dat` files from before that date have no description — re-run `install.sh` once after pulling, otherwise the rules keep targeting the old connector names and, after a rename, both monitors fall back to `preferred`/`auto` and all workspaces end up orphaned (the bar shows `21`, `22`…).

The `desc:` selector is used **only when it is safe**: the description must be non-empty, free of characters that would break Lua/hyprlang (`"`, `\`, `#`, `=`), free of control characters, and **unique among the detected monitors** — two identical monitors without a serial number would both match the same prefix, so in that case (and for virtual/headless outputs without EDID) the installer keeps connector names for them and says so. Every edge case therefore degrades to the pre-2026-09-21 behaviour, never below it. If the rules were wrong for a while (old connector names), Hyprland has already given the live monitors the first free numbers outside the decades — `21`, `22` on the bar — and a `hyprctl reload` never moves existing workspaces. The orphan guard (decades mode) handles that too: a workspace with **no rule at all** sitting on a monitor that owns a decade is merged into that decade (`21` on the HDMI with `11–20` → `11`), the same way orphans of an unplugged monitor are. At session start `scripts/hypr/machine-layer-check.sh` (read-only, started from the shared `workspaces.lua`) verifies that the generated files still match the connected monitors and shows a single notification with the fix (`re-run install.sh`) when they don't — an unplugged external monitor is not an alarm. A mismatch is reported when no rules match, a connected monitor lacks its own rule, or required generated files are missing.

- **`shared`** — 10 workspaces (1-10) shared across all monitors. Monitor number k has workspace k as its "home" (that's where it opens on startup), but `Super + 1..0` works globally — you summon a workspace onto whichever screen you're on. Resilient to unplugging a monitor: each workspace always exists exactly once, so nothing gets duplicated.
- **`decades`** — each monitor has **its own** workspaces numbered 1 to 10 (isolated decades). The bar shows only the focused monitor's workspaces, and `Super + 1..0` works within the focused monitor. External monitors' decades follow the left→right numbering; exception: the laptop's built-in panel (eDP/LVDS/DSI) always keeps the first decade — it's the only screen guaranteed to exist, otherwise working without an external monitor would create orphaned workspaces (a double "1" on the bar). When a monitor is unplugged, a guard daemon merges its workspaces (windows from workspace N land on N); when it's replugged, the monitor gets its own back.

You can switch the mode **live** in the TUI under `Super + A` → `[w] workspace mode` (no need to re-run the installer): it regenerates the workspace rules and binds, saves the mode, reloads Hyprland, and starts the guard daemon if needed. The green `✓` lines report what was read back: the mode file, `hyprctl configerrors` and the guard process after its start. If the mode cannot be saved, the old rules are put back and nothing is reloaded; if Hyprland does not answer or the guard does not start, the menu says so instead of reporting success. Monitor numbering can be changed in `Super+A → [n]` or `install.sh`; the mode uses that saved order. Note: a reload doesn't move already-open windows — for a clean resort (especially decades' `defaultName`) log out and back in, or move windows manually. The shortcuts work the same in both modes — only the scope differs:

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
- `[m] mouse`, `[k] keyboard`, `[v] volume bar`, `[l] system logo`, `[g] login screen`, `[o] audio`, `[t] timer`, `[h] shell` and `[i] diagnostics`: selection screens use the shared menu. Numeric values, custom XKB codes, layout order, timer duration and color remain text fields. The vi-mode key capture in `[h] → 4` finishes with Enter.
- `[p] autostart`: arrows or `j`/`k` navigate, Space/Enter toggle apps or open action rows. `/text`, global app numbers (including `1 2` and numbers on other pages), `n`/`p` pages, `s` save and `q` cancel remain available. Action rows have no numeric labels; discarding changes asks for confirmation. Desktop IDs with spaces or quotes (e.g. Steam game shortcuts) are quoted for `gtk-launch`; `Saved N apps` counts the entries written to `autostart-apps.lua`, and an ID with control characters is listed as not saved.
- `[h] → 5` plugins and `[h] → 6` CLI tools: Space/Enter toggle checkboxes; Esc returns. Missing plugin packages require a separate `[y/N]`, CLI packages a separate `[Y/n]`.
- `[f] fonts`: `d` rice font, `l` installed fonts (`a` toggles all fonts; more than nine fonts take the number and Enter), `u` undo; the new font is confirmed with a yes/no menu.
- `[u] update archenemy`: choose dev/main with arrows and Enter or `1`/`2`. Stashing changes, switching to an older branch and running the installer use yes/no menus.

## Diagnostics

Run `archenemy doctor` (or `bash ~/archenemy/scripts/archenemy-doctor.sh`) for
an English plain-text report suitable for a public bug report. `--full` adds
generated-file details and bounded calls to the existing workspace, gaming and
flux-wall diagnostics. Their raw output, config error text, monitor descriptions,
logs, process arguments and personal file contents are withheld in both modes;
the canonical checkout path is shown as `~/archenemy`, other checkout paths are
withheld, and only standard branch names (`dev`, `main`, `master`, `HEAD`) are
published. Custom branch names are withheld. Other displayed fields mask the
home directory, user, host and common secret/address patterns. Version and hardware output is limited to numeric versions, PCI IDs,
driver module names and status fields.

The command reads local state only, does not fetch from the network, install
packages, edit files or send notifications, and has a shared four-second probe
budget plus an external 4.5-second collection deadline, including file reads and
process cleanup. Direct file reads accept only regular files up to 1 MiB (256
bytes for the rice name), opened without blocking on FIFOs; invalid UTF-8 is
replaced. Full mode uses `flux-wall.sh doctor-safe`, which never executes rice
configuration and rejects traversal and configuration symlinks outside the repo.
Missing Hyprland is reported as `not running`. Exit status is 1 for
problems (including broken/wrong rice links, config errors, missing required
packages and a package check that could not run), otherwise 0.

**Required packages per platform.** The platform comes from `/etc/os-release`
the same way as in the installer (`Platform: arch`, `arch-derivative`, `fedora`,
`nixos`, `unsupported` — Fedora Atomic or another distribution — or `unknown`;
the raw os-release is not published). Both `packages/requirements-pacman.txt`
and `packages/requirements-aur.txt` are required; a missing, empty or invalid
list is a problem. Every required package gets one state — `checked`, `missing`,
`unavailable` (could not be checked) or `skipped` (with a reason) — and the line
`Package check: complete|partial|unavailable (<backend>; N required: …)` sums
them up. On Arch and its derivatives the check is `pacman -Qq` as before, now
including the AUR list. On Fedora one `rpm -q` covers every RPM name from
`packages/platform-map.tsv` (several RPMs per entry; an RPM installed only for
another architecture, e.g. i686, counts as missing; an architecture name outside
the known RPM list is shown only as `other architecture`); entries without an RPM use
the map's command or font probe, and system-managed entries (`ufw` → firewalld)
are `skipped`, not missing. On NixOS the command and font probes of the map are
used without the `nix` CLI; system-managed entries are shown as advice (the
NixOS option to set), entries without a probe as `skipped`. Unknown platforms
are `unavailable` — a `pacman` found on Fedora, NixOS or an unknown system is
never queried. A missing backend, a query error, empty or unrecognized query
output or a timeout is `unavailable` and a problem (`Missing: unknown`), never
"Missing: 0". Font probes run `fc-list` with its cache directories pointed at
`/proc`, so a stale fontconfig cache is never written. The Fedora/NixOS backend
is `pkg_check_ids` in `install/lib/pkg.sh` and shares the probe budget. The last line gives the problem count. Origin comparison
uses cached refs, so it may predate the latest upstream changes. Generated optional
shell/music files may be absent without constituting a critical problem. The
active rice's generated hyprlock background is required (beta uses white-blue). A Lua
Super+A bind can be counted, but its callback target cannot be verified through
`hyprctl`; the report explicitly marks that limitation. Existing helpers expect
`~/archenemy` and are skipped for checkouts elsewhere. In full mode gaming-diag
runs as `gaming-diag.sh --doctor`: only its package and driver checks (no
`nvidia-smi`, so the dGPU is not woken), printing nothing but its completeness
line; the report shows `completed` only for `diagnosis: complete`, otherwise
`partial (not checked: …)` with keys from a fixed list (`platform`, `packages`,
`foreign`, `nvidia-32bit`, `owners`, `history`, `initramfs`, `vulkan-icd`).

The private dump `Super+A → [i] → 3` (`scripts/hypr/gaming-diag.sh`) follows the
platform too: on Arch `pacman -Q`, `pacman -Qm` (foreign packages — AUR or any
other source outside the sync databases, not proof of AUR), `pacman -Qo`,
`/var/log/pacman.log` and mkinitcpio; on Fedora one `rpm -qa` (versions,
architectures, packages whose RPM vendor is not "Fedora Project": COPR, RPM
Fusion, vendors), `rpm -qf`, install times from the rpm database instead of a
history (no dnf: no network, no cache) and dracut; on NixOS versions from the
Nix store paths of the commands and of `/run/opengl-driver(-32)`, while AUR,
package history and initramfs do not apply. NVIDIA 64/32-bit userspace is
compared on every platform (Fedora: the real RPM names — RPM Fusion
`xorg-x11-drv-nvidia-libs` and its legacy `xorg-x11-drv-nvidia-580xx-libs` /
`-470xx-libs`, negativo17 `nvidia-driver-libs`); when neither is installed the dump says whether an
NVIDIA GPU is on the bus. A missing unit or path is not reported as a failure.
Whatever could not be checked (query error or timeout, no log, an owner the
dump cannot recognize, unreadable kernel log, outside Hyprland, an `nvidia-smi`,
`vulkaninfo` or `eglinfo` that is installed but fails or times out) is listed under
"kompletność", and the last line is `diagnosis: complete` (exit 0) or
`diagnosis: partial; not checked: …` (exit 2). The menu says `✓ Saved` only for
a complete diagnosis, `⚠ Saved … partial` for an explicitly partial one, and
`✗` otherwise (the file is kept). The dump stays private: keep it to yourself.

Tests: `bash tests/archenemy-doctor.sh` uses isolated homes and mock commands;
`bash tests/doctor-platforms.sh` and `bash tests/gaming-diag.sh` cover every
platform (with `DOCTOR_PLATFORMS_REV=<rev>` / `GAMING_DIAG_REV=<rev>` the Arch
scenarios are also compared with that revision — for gaming-diag a revision
from before D9, e.g. `0a3ca91`: the harness copies only the script);
`bash tests/run-all.sh` includes it automatically. The required `procps-ng`
package supplies `pgrep` for daemon status; no daemon arguments are published. **Live-only:** on Arch with
Hyprland running, run both report modes, check the Super+A status against the
actual shortcut, inspect link/package results, and repeat from a TTY without
Hyprland; on Fedora and NixOS compare both modes with the real packages and
services, also in the yin and yang rices, and run the private gaming dump before and
during a game. No new settings-menu entry is added.

## Updating and supply chain

The updater (`Super + A → [u]`, `scripts/appbinds/update-archenemy.sh`) fetches the chosen branch, pulls it with `--ff-only` and reports success only when `HEAD` equals `origin/<branch>`.

- **AUR:** when yay is missing, the installer clones it from `https://aur.archlinux.org/yay.git` (fixed; no environment variable can change the source) and builds it in a fresh `mktemp -d` directory (removed afterwards, never a fixed `/tmp/yay` that another user could plant; Ctrl+C during this step removes it too and stops the installer), offers to show its PKGBUILD first and reports ✓ only when `yay` is actually on `PATH`. Before every `yay -S` it says that AUR packages are user-submitted and offers `--diffmenu --answerdiff All` (yay shows each PKGBUILD diff before building, even if you turned its diff menu off with `yay --diffmenu=false --save`); the default is a plain `yay -S --needed`. A fresh Arch has no `less`, so both reviews use the first pager that exists: `$PAGER` (arguments allowed, e.g. `less -R`), `less`, `more` (util-linux, part of `base`), `cat`; yay gets the same pager as `GIT_PAGER` unless you set `GIT_PAGER` or git's `core.pager` yourself. No pager package is installed for this.
- **Root and sudo:** `install.sh` refuses to run as root or under `sudo` (it asks for sudo itself where needed, and AUR packages must never be built as root) and runs `sudo -k` on every exit — before the last question of a normal run, and from an `EXIT` trap after Ctrl+C, the early exit in step [2] or an error — so the cached sudo password does not outlive the installer. This applies wherever the installer uses sudo (Arch, also with `--skip-packages`, and Fedora when it installs with dnf); on NixOS and on Fedora with `--skip-packages` it never calls `sudo`, not even `sudo -k`, and nothing before platform detection (option parsing, repository check) calls it either. The GPU installer's test hooks (`ARCHENEMY_ETC_DIR`, `ARCHENEMY_MODULES_DIR`) and the boot hooks (`ARCHENEMY_BOOT_DIR` in `install/bootloader.sh`, `ARCHENEMY_CPUINFO` in the microcode installer) work only together with `ARCHENEMY_TEST=1`; a variable left in your environment cannot redirect their `sudo` writes or detection. The VirtualBox installer's hooks (`ARCHENEMY_MODULES_DIR`, `ARCHENEMY_SYSMODULE_DIR`) have the same gate, so they cannot change which kernel headers it installs or fake a loaded `vboxdrv`.
- **What is coming:** before pulling, the updater lists the new commits from `origin/<branch>` (up to 30, then a count of the rest) and warns separately when the update changes `install/` or `packages/` — that is the code the installer later runs with sudo and yay. After a successful update it prints `To go back: git switch --detach <old commit>` with the previous `HEAD`. By then the pull output has usually scrolled the list out of the Super+A window, so right above the "Run install.sh now?" question the updater repeats a summary: new commits (or commits rolled back, when you switched to an older branch), files changed and — when the warning was shown — how many `install/`/`packages/` files changed, with `git -C ~/archenemy diff <old commit> HEAD -- install packages` to review them.
- **Local changes:** tracked files you changed are stashed before the pull and restored after it. If restoring conflicts, the updater prints no ✓ and does not offer the installer: it lists the conflicting files, which now contain conflict markers, and a copy of your changes stays in the stash (`git stash list`). In `~/archenemy`, fix the markers, `git add` those files and run `git stash drop`, then start `install.sh` yourself. Do not run `git stash pop` again: on a file with conflict markers it fails with "needs merge", and after `git add` it applies the same changes a second time. If restoring fails without a conflict (nothing was applied), the updater says so and the right command is `git stash pop` once the error it printed is fixed.
- **Installer prompt:** "Run install.sh now?" defaults to **No** and says that the installer will ask for sudo — the installer comes from code fetched a moment earlier, so a single Enter must not run it as root. The machine-layer check reminds you when the installed version is behind the code.

## Other distributions (experimental)

Arch Linux is the reference platform. Fedora and NixOS are supported by `install.sh` as **experimental**: package and configuration paths are covered by mocks only; desktop sessions and hardware have not been verified live. Debian/Ubuntu are out of scope (no rolling release, no Hyprland with Lua configuration).

**How the installer picks a path.** Before writing anything, `install.sh` reads `/etc/os-release` through `install/lib/pkg.sh`. Arch Linux and Arch derivatives (`ID_LIKE=arch`: EndeavourOS, Manjaro, CachyOS…) run the same steps as before, with the same questions, commands and results. Fedora and NixOS use the package map below for steps [2], [4] and [5]. Any other distribution, and Fedora Atomic (rpm-ostree), is refused with exit code 1 and nothing changed. Steps [6]–[10] still install system software and enable services only on Arch: on Fedora and NixOS the installer skips power-profiles-daemon setup, ASUS tools, microcode/GPU/kernel installers, UFW, Bluetooth, VirtualBox and service enabling (NetworkManager, pipewire-pulse, the mpd user service), and prints what to do by hand instead; required ones are also listed in the summary. On every platform a service gets its `✓` only after `systemctl is-enabled` **and** `is-active` (power-profiles-daemon, NetworkManager, pipewire-pulse/WirePlumber, the mpd user service): enabled but not running is a warning with the command to check it, never a `✓`, and lands in the summary. On Fedora no service is changed; a running `tuned-ppd` (Fedora Workstation's default) is recognised, and archenemy does not tell you to install a second profile manager — only, optionally, `sudo dnf swap tuned-ppd power-profiles-daemon` for the bar's `powerprofilesctl`. firewalld is left alone, also when UFW is active too. The same goes for the repair hint when the profile switcher does not respond after step [6]: Fedora gets the dnf/systemctl commands, NixOS the `services.asusd`/`services.power-profiles-daemon` options — never `install/asus-installation.sh`, which uses pacman. Monitors, machine files, rice links, wallpapers and flux-wall work as on Arch.

**Runtime advice outside the installer (Super+A, workspace guard).** Programs started later — `[h] shell` (see "Custom app shortcuts"), `[m] mouse`, `[u] update` and the workspace guard — detect the platform themselves with `pkg_route` (os-release), never from variables left by the installer, and never install anything or enable a service from a menu. Arch and its derivatives keep their previous texts. `[m]` without `ratbagctl` points to `sudo dnf install --repo=fedora --repo=updates libratbag-ratbagd` on Fedora and `services.ratbagd.enable = true;` on NixOS; DPI stays emulated until you install it. The workspace guard falls back to polling every 2 s and sends one notification that names what is missing: `socat` (with the platform's command, `pkgs.socat` on NixOS) or, when socat is installed, Hyprland's event socket; it still exits after 5 failed reads once Hyprland is gone. `[u]` asks about `install.sh` per platform: on Fedora it says sudo goes to dnf and that extra repositories are asked about separately; on NixOS that the installer installs nothing and uses no sudo, and changes under `nix/` count as risky together with `install/` and `packages/`; on other distributions the installer is not offered. Tests: `bash tests/runtime-platforms.sh` (`RUNTIME_PLATFORMS_REV=<rev>` compares Arch), `bash tests/update-archenemy.sh`.

**System helpers run by hand.** The helpers in `install/` that change the system — `gpudrivers-installation.sh`, `cpudrivers-installation.sh`, `kernel-install.sh`, `asus-installation.sh`, `virtualbox-installation.sh`, `bluetooth-installation.sh`, `system-theme-installation.sh` — check the platform themselves, with the same `pkg_route` as `install.sh` (never an inherited `PLATFORM` variable). Run directly outside Arch they change nothing: on Fedora and NixOS they print what to do there (Fedora: the dnf command or RPM Fusion — for NVIDIA the driver by card generation: Turing and newer `akmod-nvidia`, Pascal/Maxwell/Volta `akmod-nvidia-580xx`, Kepler `akmod-nvidia-470xx`, each with its 32-bit `-libs.i686`; NixOS: the `configuration.nix` options — for NVIDIA `hardware.nvidia.open` and the driver branch by card generation: Turing and newer `open = true` with `nvidiaPackages.stable`, Pascal/Maxwell `open = false` with `legacy_580`, Kepler `legacy_470`; branch names depend on the nixpkgs version, see its `pkgs/os-specific/linux/nvidia-x11/default.nix`) and exit with code 2 ("manual step"), without asking anything and without running `sudo`, `pacman`, `systemctl`, `mkinitcpio`, `grub-mkconfig`, `modprobe`, `usermod` or any other command; on any other distribution they say it is not supported, also with code 2. The bootloader library `install/bootloader.sh` has the same gate inside `regenerate_bootloader`: sourced and called on Fedora or NixOS, it detects nothing, leaves `/boot` alone and returns 2 with the platform's instruction (Fedora: `kernel-install`/BLS, `grub2-mkconfig` only as advice; NixOS: `nixos-rebuild boot`); sourcing it never ends the calling shell. On Arch and its derivatives they behave exactly as before (`bash tests/helper-gates.sh`).

**Version check (Fedora and NixOS).** Right after step [2], before anything is written, the installer checks that the running Hyprland (first line of `hyprctl version`) and, on Fedora, the installed `hyprland` package are at least 0.56 (Lua configuration), and that `hyprpaper` is at least 0.8.2 (`min_version` in the package map; on Fedora from `rpm -q`, on NixOS from the Nix store path the `hyprpaper` command resolves to, `/nix/store/<hash>-hyprpaper-<version>/`). An older version — or a version that cannot be determined (running Hyprland not answering `hyprctl version`, a NixOS `hyprpaper` outside the Nix store, a failing `rpm -q hyprland` or `rpm -q hyprpaper`) — stops the installer with exit code 1, a hint (COPR on Fedora, "log out and back in" when only the running session is old, nixos-unstable or the Hyprland flake on NixOS, `pkgs.hyprpaper` from nixpkgs) and nothing installed or changed. A `hyprpaper` that is not installed yet is left to step [5]; so is a missing Fedora `hyprland` package (for example Hyprland built outside rpm) — then the running session decides. Arch has no such check, as before.

- `packages/platform-map.tsv` maps every Arch package archenemy installs — each entry of the four `packages/*.txt` lists, the CLI tool catalog and the packages installed directly by `install/*.sh` (yay, ASUS, microcode, kernels, GPU drivers, VirtualBox) — to Fedora RPM names and their source, and to nixpkgs attributes or NixOS options. One id may expand to several packages (`libpulse` → `pulseaudio-libs-devel pulseaudio-utils`). Rows without an equivalent say so explicitly: `manual`, `unavailable` or `system-managed`; there are no `-git` substitutes. The four lists remain the source for Arch and are unchanged. The file is data: it is read with `read`, never `eval`/`source`, and every package name must match a fixed character set.
- **Fedora (43/44/45 checked).** Step [4] is skipped (no AUR). Step [5] checks every required package by its exact RPM name and, after `Install missing packages with dnf? [Y/n]`, installs the ones from Fedora's repositories with `sudo dnf install --repo=fedora --repo=updates` (DNF5: only Fedora's own `fedora` and `updates` repositories in that transaction, even if you have other repositories enabled; no `-y`, `--skip-*` or `--allowerasing`; success only when `rpm -q` finds every name). Still to be checked on a live Fedora: whether any package mapped to `fedora` pulls a dependency that exists only outside `fedora`/`updates` (dnf would then refuse the transaction). The Hyprland stack (`hyprland`, `hyprpaper`, `hyprlock`, `hyprpolkitagent`, `hyprshot`, `hyprpicker`, `xdg-desktop-portal-hyprland`, `swayosd`, `cliphist`) comes from the community COPR [`nett00n/hyprland`](https://copr-be.cloud.fedoraproject.org/results/nett00n/hyprland/), and Brave from [Brave's own RPM repository](https://brave.com/linux/): both are opt-in — the installer shows the source and asks `[y/N]` before enabling either, also in step [2] when Hyprland is missing (Fedora's own Hyprland is older than the 0.56 archenemy needs; an older installed one stops the installer, see "Version check"). RPM Fusion (Steam, Discord) is never enabled. `ufw` maps to Fedora's firewalld, which archenemy leaves alone.
  - **`tuned-ppd`:** Fedora Workstation ships `tuned-ppd`, which conflicts with `power-profiles-daemon`. archenemy does not replace installed packages: it tries `power-profiles-daemon` in its own dnf transaction, shows dnf's refusal and suggests `sudo dnf swap tuned-ppd power-profiles-daemon` (the bar's profile switcher uses `powerprofilesctl`, which only `power-profiles-daemon` provides). Then enable it: `sudo systemctl enable --now power-profiles-daemon`.
  - **`networkmanager-dmenu` (manual):** there is no maintained Fedora package. Install the single script from [firecat53/networkmanager-dmenu](https://github.com/firecat53/networkmanager-dmenu) as `~/.local/bin/networkmanager_dmenu` (executable) with its dependencies from the upstream README (Python GObject bindings and NetworkManager's libnm); `Super+N` and the rice config work once `networkmanager_dmenu` is on `PATH`.
  - **Nerd Fonts (manual):** archenemy does not enable an unofficial font COPR. Download `Iosevka`, `JetBrainsMono` and `NerdFontsSymbolsOnly` from the [Nerd Fonts releases](https://github.com/ryanoasis/nerd-fonts/releases/latest), extract them into `~/.local/share/fonts/`, run `fc-cache -f`, and check with `fc-list : family | grep -E 'Iosevka Nerd Font|JetBrainsMono Nerd Font|Symbols Nerd Font Mono'`. Run `install.sh` again afterwards: the check in [5] then shows them as present.
  - Other packages without a Fedora package in the default repositories (for example `bluetui`, some optional programs) are listed with a link to install them by hand; the summary shows every required one that is still missing.
- **NixOS.** NixOS is declarative, so `--skip-packages` is always on: archenemy never runs `nix-env`, `nix profile` or `nixos-rebuild`, runs nothing with `sudo` (not even `sudo -k`), and enables no service. Two runtime actions still talk to systemd, and only to your user session: the rices' autostart starts the polkit agent with `systemctl --user start hyprpolkitagent` (no enable; on NixOS the unit exists only if you add `systemd.packages = [ pkgs.hyprpolkitagent ];`, otherwise the agent stays off and a line goes to the session log), and `Super+A → [o] → 3` restarts your user `mpd.service` after you pick an output. The frozen `white-blue_beta` rice keeps its old bare `systemctl --user start` line; use a parity rice on NixOS. Step [2] stops with instructions when Hyprland is missing (`programs.hyprland.enable`; nixos-26.05 ships Hyprland 0.55.4, below the 0.56 Lua configuration archenemy needs — use nixos-unstable, which has 0.57.2, or the Hyprland flake). Step [5] checks commands and fonts and prints what to add to `environment.systemPackages`/`home.packages` or which NixOS option to set; entries it cannot probe are shown with `?`. Steps [6]–[10] print the NixOS options to set instead (`services.power-profiles-daemon.enable`, `networking.networkmanager.enable`, `services.pipewire.pulse.enable`, …). For the optional mpd it prints a user service that reads archenemy's config — `systemd.user.services.mpd = { wantedBy = [ "default.target" ]; serviceConfig.ExecStart = "${pkgs.mpd}/bin/mpd --no-daemon %h/.config/mpd/mpd.conf"; };` — rather than home-manager's `services.mpd`, which generates its own `mpd.conf` ([module source](https://github.com/nix-community/home-manager/blob/master/modules/services/mpd.nix)).
  - **Package list: `nix/packages.nix`.** A function `{ pkgs }:` that returns four groups: `core` (what the desktop needs at runtime), `fonts`, `build` (compiler and headers for `src/flux-wall`) and `optional` — a named set, so you pick optional programs explicitly (`with archenemy.optional; [ btop mpv ]`); nothing optional is added by default. It is generated from the `nixos=ok` rows of `packages/platform-map.tsv` (`bash nix/generate-packages.sh`; `--check` fails when it is out of date), deduplicated, plus two attributes the map does not have because Arch's base system provides them: `xkeyboard_config` (the layout list for `Super+A → [k]`) and `zlib` (flux-wall tools). It contains **only packages**: it does not enable Hyprland, the screen-sharing portal, PAM for hyprlock, audio, NetworkManager, Bluetooth, power profiles or any other service — those stay NixOS / home-manager options and are set separately: `programs.hyprland.enable = true;` (also installs `xdg-desktop-portal-hyprland`), `programs.hyprlock.enable = true;` (PAM), `services.pipewire = { enable = true; pulse.enable = true; wireplumber.enable = true; };`, `networking.networkmanager.enable = true;`, `services.power-profiles-daemon.enable = true;`, `hardware.bluetooth.enable = true;`, and `programs.zsh.enable = true;` when zsh is your login shell. Fonts belong in `fonts.packages` on NixOS (in `home.packages` with `fonts.fontconfig.enable = true;` in home-manager). Some optional programs are unfree in nixpkgs (for example `discord`, `megasync`) and need `nixpkgs.config.allowUnfreePredicate`.
  - **Pin nixpkgs** to the revision the attribute names were checked against instead of a moving channel: nixos-unstable at `d5cc6833999746cffdfe0598f7bc801a57b887a9` (2026-11-13; Hyprland 0.57.2, hyprpaper 0.8.5). A newer revision may rename or drop an attribute; the list has not been evaluated by Nix yet (planned in CI), so no compatibility with other revisions is claimed. NixOS without flakes (`/etc/nixos/configuration.nix`):

    ```nix
    { pkgs, ... }:
    let
      # nixos-unstable, 2026-11-13. Add  sha256 = "...";  printed by
      # nix-prefetch-url --unpack <url>  to make the download tamper-proof.
      pinned = import (builtins.fetchTarball
        "https://github.com/NixOS/nixpkgs/archive/d5cc6833999746cffdfe0598f7bc801a57b887a9.tar.gz")
        { system = pkgs.stdenv.hostPlatform.system; };
      archenemy = import /home/you/archenemy/nix/packages.nix { pkgs = pinned; };
    in {
      environment.systemPackages = archenemy.core ++ (with archenemy.optional; [ btop mpv ]);
      fonts.packages = archenemy.fonts;
    }
    ```

    home-manager (`home.nix`):

    ```nix
    { pkgs, ... }:
    let archenemy = import /home/you/archenemy/nix/packages.nix { inherit pkgs; };
    in {
      home.packages = archenemy.core ++ archenemy.fonts ++ (with archenemy.optional; [ btop ]);
      fonts.fontconfig.enable = true;
    }
    ```

    In a flake, pin the input instead — `inputs.nixpkgs.url = "github:NixOS/nixpkgs/d5cc6833999746cffdfe0598f7bc801a57b887a9";` — and, because pure evaluation cannot import `/home/…`, add the repository as a non-flake input: `inputs.archenemy = { url = "git+file:///home/you/archenemy"; flake = false; };`, then `import "${inputs.archenemy}/nix/packages.nix" { inherit pkgs; }`. That copies only tracked files into the store; the checkout itself stays a writable `~/archenemy` (never a `/nix/store` path). archenemy ships no flake and no home-manager module of its own.
  - **`build`** is meant for a shell, not for the system profile — headers in `environment.systemPackages` are not visible to `pkg-config`: `nix-shell -E 'let pkgs = import <nixpkgs> {}; in pkgs.mkShell { packages = (import ./nix/packages.nix { inherit pkgs; }).build; }' --run 'make -C src/flux-wall'` from `~/archenemy`.
  - **home-manager and archenemy must not manage the same files.** A rice folder in `~/.config` (or a file inside it, or `~/.config` itself), `~/.config/mpd`, `~/.bashrc` or `~/.zshrc` that is a link into `/nix/store` belongs to home-manager. archenemy checks this **before** it changes anything: `Super+T` (and re-applying the current rice) stops with exit code 3, a critical notification and the list of paths; the installer's step [9] skips linking with `⚠` and the same advice in the summary, step [8l] does not offer to replace the mpd config, and step [8m] shows the block for `programs.bash.initExtra`. Nothing is moved to `.bak`, no link is created, `.current_rice` is not written — a second installer run gives the same result. Remove the conflicting declaration (`xdg.configFile."waybar"`, `programs.waybar.settings`, `wayland.windowManager.hyprland`, …), run `home-manager switch`, then run the installer or `Super+T` again. Do not use home-manager's `force` for these paths: the two tools would overwrite each other on every switch. `~/archenemy` itself must be a writable clone — the installer refuses a checkout inside `/nix/store`. Tests: `bash tests/hm-conflict.sh`.
  - **No `/usr/share` on NixOS.** `Super+A → [k]` and `Super+Ctrl+1…4` (both run `scripts/hypr/keyboard-layouts.sh`) read the XKB layout list from `/usr/share/X11/xkb/rules/evdev.lst` as on Arch and Fedora; when that file does not exist they use `$XKB_CONFIG_ROOT/rules/evdev.lst` or the first Nix profile that has `share/X11/xkb/rules/evdev.lst` (`~/.nix-profile`, `~/.local/state/nix/profile`, `/etc/profiles/per-user/<you>`, `/run/current-system/sw`; `xkeyboard_config` is in `core`), so layout names and the check for unknown codes work without any session variable. To force one file, set `environment.sessionVariables.ARCHENEMY_XKB_RULES = "${pkgs.xkeyboard_config}/share/X11/xkb/rules/evdev.lst";`. Without any of these files the menu accepts any well-formed 2–3 letter code, as before. zsh plugins are loaded only from Nix profiles, never from `/usr/share` (see "[h] on Fedora and NixOS"). Tests: `bash tests/nix-paths.sh`.
  - The installer neither reads nor applies this list and still never runs `nix-env`, `nix profile` or `nixos-rebuild`: you apply your configuration yourself.
- `install/lib/pkg.sh`: `pkg_detect` reads `ID`/`VERSION_ID` from `/etc/os-release` (fallback `/usr/lib/os-release`) without `eval` and accepts only `arch`, `fedora` and `nixos`; `pkg_arch_derivative` recognizes `ID_LIKE=arch`, which `install.sh` sends down the unchanged Arch path. `pkg_route` is that choice as one function (`PKG_ROUTE=arch` for Arch and derivatives, `fedora`, `nixos`, or code 1 = refused); `install.sh` and every system helper in `install/` call it, never an inherited `PLATFORM` variable. `pkg_gate <step>` is the helpers' entry gate: 0 on Arch and derivatives, otherwise it prints that nothing was changed and returns 2, without a question or any command beyond reading os-release. On Arch the library runs exactly the installer's commands (`pacman -Qi`, `sudo pacman -S --needed`, `yay -S --needed` through `install/lib/aur.sh`). COPR and the Brave repository are handled only by `pkg_install_extra`, after an explicit `y`. The map is validated as a whole before anything runs: package lists are split without filename expansion, and an unknown status or source, inconsistent fields (for example `fedora=ok` without RPM names or with an RPM Fusion source, or `nixos=ok` with a NixOS option such as `services.x.enable` instead of a nixpkgs attribute), a `source_url` that is not HTTPS or a duplicate id rejects the whole map (code 2). Package queries run `rpm`/`pacman` with `LC_ALL=C` and read only their standard output and exit code, so the result does not depend on the user's language: "not installed" is code 1, and a database or query error is code 2, never "installed" or "missing". After `dnf install`, success is what `rpm -q` reports; if dnf failed but every name is installed, the result is 0 with a warning. For `fedora_source=fedora`, `pkg_install` limits dnf to `--repo=fedora --repo=updates` (`PKG_FEDORA_REPOS`); COPR and Brave packages (`pkg_install_extra`) are installed without `--repo`, after their repository is enabled. Test-only overrides (`ARCHENEMY_OS_RELEASE`, `ARCHENEMY_PKG_MAP`, …) work only with `ARCHENEMY_TEST=1`. `pkg_version` reads the installed version (pacman, `rpm -q`, or on NixOS the Nix store path of the entry's first command, only for `nixos=ok` rows whose store name equals the nixpkgs attribute) and returns 3 below `min_version`; `pkg_min_version` and `pkg_version_ge` expose the minimum and the `sort -V` comparison. `pkg_installable <id>` answers, without running anything, whether `pkg_install` would install that id from the platform's default source (0 on Arch; on Fedora only `fedora=ok` rows from Fedora's repositories; never on NixOS) — the runtime menus offer an installation only then. Tests: `bash tests/platform-map.sh`, `bash tests/pkg.sh`, `bash tests/helper-gates.sh` (system helpers run directly), `bash tests/install-platforms.sh` (steps [6], [6.5] and [10] on Arch, EndeavourOS, Arch with `--skip-packages`, Fedora with and without it, and NixOS: no helper starts outside Arch, no `sudo` beyond Fedora's `sudo -k`, no false "done" in the summary, helper exit codes 0/1/2 → summary on Arch), and the platform runs of `bash tests/install-main.sh` (Arch with AUR and extras, EndeavourOS identical to Arch, Fedora, Fedora with `--skip-packages`, NixOS, Arch with `--skip-packages`, Ubuntu refused, Fedora/NixOS with too old Hyprland or hyprpaper refused before any write).

## Verification

CI (`.github/workflows/tests.yml`) runs `bash tests/run-all.sh` in an `archlinux` container on pushes to `dev`/`main` and on pull requests, with read-only permissions and no third-party actions (plain `git fetch` of the tested commit). It only complements local runs: installation, sudo, Hyprland and hardware are still checked on a real machine. Run `bash tests/repo-hygiene.sh` for executable bits, `#!/usr/bin/env bash` shebangs, Lua dispatch syntax and installer language, or `bash tests/run-all.sh` for all shell suites. `run-all.sh` gives every suite `RUN_ALL_TIMEOUT` seconds with stdin from `/dev/null`. The default is `ceil(600 × ARCHENEMY_TEST_TIME_SCALE)`; an explicit `RUN_ALL_TIMEOUT` is the final whole number of seconds (not multiplied) and `0` disables the limit. A suite that does not finish is killed together with its child processes and listed as a suite timeout ("timeout pakietu: przekroczono N s") — a deadline, not proof of a hang; a suite's own exit code 124/137 is reported as a plain failure. For every failing suite the runner prints the exit code, the last 200 lines and the paths of the full `.log` and `.rc` files, which stay in a private `/tmp/archenemy-run-all-*` directory (removed when everything is green), so one slow or hanging regression no longer blocks the whole run and its output is not lost. `ARCHENEMY_TEST_TIME_SCALE` (a finite number from 1 to 10, default 1, never guessed from the load) multiplies only harness watchdogs and readiness deadlines in the suites, via `tests/lib/timing.sh` (`test_timeout`) and `tests/lib/test_timing.py` (`seconds`, `wait_until`); on a slow or busy machine run e.g. `ARCHENEMY_TEST_TIME_SCALE=2 bash tests/run-all.sh`. Product timing contracts (doctor < 5 s, its 4/4.5 s probes, Bluetooth render < 1 s, debounce and reconnect, the 15-second monitor trial) are never scaled and fail as `KONTRAKT`; an expired harness watchdog says `ZABEZPIECZENIE`. Details: `tests/README-timing.md`. Ctrl+C stops the run and the current suite. A suite that exits 0 still counts as ✓, also when it skipped something. Tests use temporary homes, mock commands and temporary git repositories. Suites that create temporary trees source `tests/lib/environment.sh` before `mktemp` and call `test_environment_init "$T"` after installing their cleanup trap: HOME, runtime and temporary paths stay inside the test tree, XDG home overrides and desktop session identifiers are cleared, and locale and shell are fixed. XDG configuration, cache and data paths follow the temporary HOME; individual scenarios may override these defaults. The initial temporary tree is created under `/tmp`, independently of the caller's TMPDIR. Suites that must prove they write nothing outside their tree (`install-services.sh`, `rice-autostart.sh`, `shell-platforms.sh`, `runtime-platforms.sh`, `doctor-platforms.sh`, `gaming-diag.sh`, `hm-conflict.sh`, `nix-packages.sh`, `nix-paths.sh`) call `test_isolate` first: the suite re-runs in a private user and mount namespace (`unshare -rm`) with an overlay on `/tmp`, `/var`, `/root`, `/home`, `/etc`, `/usr`, `/opt`, `/srv`, `/boot` and `/mnt`, so any write, change or deletion there lands only in a throwaway upper layer in `/dev/shm` and `test_escapes` reports every path outside the test tree as ✗ — the host stays untouched and other processes cannot cause false alarms. Not covered: `/run` (its submounts cannot be overlaid), `/dev/shm`, `/proc`, `/sys` and new names directly in `/`, which those suites check separately. Without user namespaces or overlay (some containers) the suite runs as before and says the isolation is unavailable; `ARCHENEMY_NO_ISOLATE=1` turns it off. The flux-wall render checks require `make -C src/flux-wall tools`; without it, `flux-wall-bars.sh` and the render part of `flux-wall-dither.sh` skip. C tests run separately with `make -C src/flux-wall test`.

`bash tests/secrets.sh` looks for private keys (including armored PGP `PRIVATE KEY BLOCK` headers) and tokens: high-confidence patterns in tracked files always, and the whole git history through `gitleaks` when it is installed (without it that part is `skip`). `tests/repo-hygiene.sh` also rejects machine data in tracked files — a network interface name in a MangoHud config or a `/home/<login>` path — because the repository is public and such values only work on one machine; MangoHud's `network` line therefore names no interface and shows all of them.

`bash tests/packages-exist.sh` is the supply-chain check for the package lists: a name on a pacman list must be in the official repos (read-only `pacman -Slq core extra` and `pacman -Slq multilib`; third-party repos in `pacman.conf` do not count), a name on an AUR list must exist in the AUR (one AUR RPC v5 `info` request) and must not be in the official repos, and required lists must not contain `-git` packages. An AUR name that disappears can be registered by anyone, and `yay -S` would then build that stranger's PKGBUILD. Without network, or without pacman or its synced `core`/`extra` databases, the affected names are reported as `skip`, never as passed; the one exception is an AUR name on a machine without pacman, which is checked against the AUR only (its "not in the official repos" rule needs pacman). Without a synced `[multilib]` database (CI, servers) only the multilib names — `steam` and `lib32-*`, the same pattern step [5] of `install.sh` warns about — are skipped; any other name that is not in the repos fails, so a typo cannot pass as a skip.

`tests/install-services.sh` runs the service parts of steps [6], [8l] and [10] on a stateful mock `systemctl` (enable failing, returning 0 without effect, enabled-but-dead, partial start, no user bus) on every platform; `INSTALL_SERVICES_REV=<rev> bash tests/install-services.sh` compares 32 Arch scenarios with that revision — also hardware choices 1/2 with every ASUS helper result, Bluetooth and VirtualBox consent with helper codes 0/2/1, a running pulse service without the socket, and separate UFW failures (`ufw default`, `ufw enable`, inactive status, `systemctl enable ufw`): same questions and rest of stdin; the revision's mock calls must appear in the same order, and the only extra calls allowed are `systemctl [--user] is-enabled|is-active --quiet` reads; the same output and summary, except in scenarios that fix a false ✓, where every differing line must match that scenario's pattern. `tests/helper-gates.sh` compares the system helpers the same way: `HELPER_GATES_REV=<rev> bash tests/helper-gates.sh` also runs its Arch and EndeavourOS scenarios with the `install/` helpers of that revision and requires identical output, exit code, mock calls and mock `/etc`/`/boot`. `tests/install-main.sh` can also compare the Arch path of the installer with another revision: `INSTALL_MAIN_REV=<rev>` runs the Arch scenarios with `install/install.sh` from that git revision, and `INSTALL_MAIN_SAVE=<dir>` stores normalized transcripts, answered questions, mock calls and file snapshots of every run. For example `INSTALL_MAIN_REV=e6e281d INSTALL_MAIN_SAVE=/tmp/base bash tests/install-main.sh`, then `INSTALL_MAIN_SAVE=/tmp/head bash tests/install-main.sh` and `diff /tmp/base/log.1 /tmp/head/log.1` (likewise `asked.N`, `out.N`, `files.N` for runs 1–3). A new installer question needs an answer in the answer list of `tests/install-main.sh`, otherwise the run fails as stuck.

**Known limits of the automated proof (D8–D10 review, L5).** The `*_REV` parity runs compare what they name and nothing more:

- `SHELL_PLATFORMS_REV`: 20 Arch scenarios of `[h]` (output, exit code, commands, HOME files). home-manager paths are not part of it: they are an intended change, checked by `tests/hm-conflict.sh` (also the whole step [8m] with an old alias in a home-manager `~/.bashrc`); `HM_CONFLICT_REV=<rev>` compares the whole [8m] with an old alias in a plain `~/.bashrc` on Arch.
- `RUNTIME_PLATFORMS_REV`: the mouse menu and the orphan guard with and without `socat` and the Hyprland socket (the socat-but-no-socket case may differ only in its notification text); the rest of the mouse and guard logic is not compared.
- `UPDATE_ARCHENEMY_REV`: the whole output of five scenarios, not the final HOME or the command calls, and not every stash conflict.
- `INSTALL_SERVICES_REV`: slices of steps [6], [8l] and [10], with the current `install/lib/pkg.sh` on both sides; the whole installer runs only in `tests/install-main.sh` (needs a pty).
- `GAMING_DIAG_REV` (a revision before D9, e.g. `0a3ca91`): dump text with listed allowed differences, not calls or files; hardware sources are mocks. `DOCTOR_PLATFORMS_REV` compares exit code and text (lines new in D9 left out) with a shared gaming-diag mock.
- The D10 rice switch, rc block and XKB changes have regression tests, not a comparison of every path with an older revision.
- Without user namespaces (`unshare -rm` not permitted) suites that call `test_isolate` print that isolation is unavailable instead of `✓`; `tests/repo-hygiene.sh` does not use `test_isolate`.

**Live-only — a real Arch + Hyprland session is required:**

1. Run `~/archenemy/install/install.sh`, review its summary, log in again and inspect `hyprctl configerrors`.
2. Switch rices with `Super+T`; in each rice, check that the rofi prompt, placeholder and typed text align in `Super+T`, `Super+W` and `Super+R`. Beta keeps its input-only bar. Check the bar, notifications, terminal, lock screen, wallpaper and app shortcuts. Check that a saved animation restarts after logout/login and follows the new rice's palette.
3. Open `Super+A`; check `[h]` in newly opened bash/zsh terminals, `[p]` after login, `[u]` on the intended branch, and `[c]` with a personal Alacritty config outside the repo. A rice symlink must be refused. In `[f]`, test first choice → another family → `[d]` reset → choose again → undo. After each action open a new Alacritty terminal using the rice config and check its appearance; compare with the unverified archenemy-choice label in fastfetch. Repeat with a personal config without the import, one overriding family/size, and another terminal: fastfetch must not claim the choice is their actual font. Check `Super+R` on its next open; waybar and mako keep their fonts. Test the installed-font list with more than nine entries: arrows, j/k, a multi-digit number + Enter, Esc and `[a]`.
4. In `[n]`, try a monitor change and let its 15-second confirmation expire; verify restoration. Replug a monitor, check `[w]` shared/decades workspaces and `Super+W` on every output. Run `hyprctl hyprpaper listactive` to compare the active images.
5. On Fedora and NixOS (experimental), run the installer on a fresh installation and again after it, then repeat steps 1–4; on Fedora also the COPR/Brave questions and the tuned-ppd hint; on NixOS also the configuration built from `nix/packages.nix` with the options above, `Super+A → [k]` layout names, zsh plugins from the profile, and the installer and `Super+T` with a home-manager declaration for one rice folder (refused, nothing changed) and again after removing it. Containers do not cover sessions, PAM, SELinux or hardware.
6. On applicable hardware, verify the ASUS profile key and bar against the actual profile; if VirtualBox was installed, check `modinfo vboxdrv`, the loaded module and a test VM after any requested reboot. For the optional music stack, test playback and `[o] → 3` with a non-empty queue.
7. Open the power menu with `Super + right Shift` and with a right click on the bar's launcher. Press Enter twice as fast as you can; then repeat with a quick double-click on `Power off` followed at once by a double-click on `Yes`. The computer must shut down without a second, slower attempt. A single Enter or double-click must stop at `Are you sure?`; `Esc`, `No` and a click outside the window must close the menu with nothing done. Then hold Enter for more than a second: nothing may happen while the key is down, `Are you sure?` must appear when you release it, and the computer must stay on; `Ctrl+j` must do nothing. If Enter does nothing at all or rofi shows an error window instead of the menu, note `rofi -version` and the error text.

## License

Original code, documentation and artwork by the archenemy contributors are licensed under GPL-3.0-or-later. See [LICENSE](LICENSE). Third-party components and assets retain their own licenses; see [THIRD-PARTY.md](THIRD-PARTY.md). Third-party names and logos remain subject to their owners' trademark rights. This project is not endorsed by those owners.
