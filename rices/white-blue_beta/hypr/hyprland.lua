-- ~/archenemy/rices/white-blue_beta/hypr/hyprland.lua
-- made by kst - https://github.com/ksterajewicz
-- github - https://github.com/ksterajewicz/archenemy
--
-- Konwencja formatu (wspólna dla rice'ów; beta nie ma TUI Super+A):
--   * zmienne rice'a: `local nazwa = "wartość"` — jedna na linię,
--   * bindy: JEDNA linia na bind, zaczyna się od `hl.bind(`.
-- require() dostaje ścieżki absolutne budowane z $HOME — pliki wspólne
-- i maszynowe leżą w repo (~/archenemy/config/hypr/), a nie obok tego pliku;
-- tyldy w komendach exec rozwija shell (hl.dsp.exec_cmd robi sh -c).

local HOME = os.getenv("HOME")

local mainMod      = "SUPER"
local terminal     = "alacritty"
local filemanager  = "thunar"
local menu         = "rofi -show drun"
local browser      = "brave"
local lock         = "hyprlock"
local gamelauncher = "steam"
local networkmanager_gui = "networkmanager_dmenu"
local theme_menu   = "~/archenemy/scripts/rofi/rofi_theme_switcher.sh"
local wallpaper_menu = "~/archenemy/scripts/rofi/rofi_wallpaper_switcher.sh"

-- GPU + Wayland + scaling
require(HOME .. "/archenemy/config/hypr/gpu_wayland_scaling.lua")
require(HOME .. "/archenemy/config/hypr/gpu-env.lua")

-- Autostart (dawne exec-once; hl.exec_cmd odpala asynchronicznie)
hl.on("hyprland.start", function()
    hl.exec_cmd("waybar")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("mako")
    hl.exec_cmd("swayosd-server")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text  --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
require(HOME .. "/archenemy/config/hypr/autostartpersonalisation.lua")
require(HOME .. "/archenemy/config/hypr/autostart-apps.lua")

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})

-- Monitors
require(HOME .. "/archenemy/config/hypr/monitorshyprl.lua")

-- Workspaces
require(HOME .. "/archenemy/config/hypr/workspaces.lua")
require(HOME .. "/archenemy/config/hypr/workspaces-monitors.lua")

hl.config({
    general = {
        gaps_in     = 6,
        -- Góra = 4 (równa margin-top waybara z config.jsonc) — przerwa pasek-okno
        -- ma być identyczna jak pasek-krawędź ekranu.
        gaps_out    = { top = 4, right = 12, bottom = 12, left = 12 },
        border_size = 2,

        ["col.active_border"]   = "rgb(0148ED)",
        ["col.inactive_border"] = "rgb(888888)",

        layout           = "dwindle",
        resize_on_border = true,
        allow_tearing    = true,
    },
})


hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })

hl.config({
    misc = {
        disable_hyprland_logo        = true,
        disable_splash_rendering     = true,
        force_default_wallpaper      = 0,
        vrr                          = 1,
        mouse_move_enables_dpms      = true,
        key_press_enables_dpms       = true,
        enable_swallow               = true,
        swallow_regex                = "^(Alacritty)$",
        focus_on_activate            = false,
        animate_manual_resizes       = false,
        animate_mouse_windowdragging = false,
    },

    cursor = {
        no_hardware_cursors      = true,
        enable_hyprcursor        = true,
        warp_on_change_workspace = false,
    },

    dwindle = {
        preserve_split       = true,
        smart_split          = false,
        smart_resizing       = true,
        force_split          = 0,
        special_scale_factor = 0.95,
    },
})

-- Apps
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(filemanager))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd(gamelauncher))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd(networkmanager_gui))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(theme_menu))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(wallpaper_menu))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(lock))

-- Keyboard language
-- Allows the user to switch between any two chosen keyboard layouts.
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))

hl.config({
    input = {
        -- Bez kb_options: grp:alt_shift_toggle kolidował z AltGr+Shift+litera
        -- (wielkie polskie znaki, np. Ż) — Prawy Alt+Prawy Shift jest w XKB
        -- naraz group-togglem I drogą do 4. poziomu klawisza, więc próba
        -- napisania Ż przełączała układ i połykała znak. Jedyny przełącznik
        -- układu: Super+K (hyprctl switchxkblayout, wyżej w bindach).
        kb_layout = "pl,us",

        follow_mouse  = 1,
        sensitivity   = 0,
        accel_profile = "flat",

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
            tap_to_click         = true, -- w hyprlangu: tap-to-click
            scroll_factor        = 0.5,
        },
    },
})

-- Window control
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + V", hl.dsp.window.float())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))

-- Focus
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "d" }))

-- Move windows
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.move({ direction = "d" }))

-- Resize ({ repeating = true } = dawne binde)
hl.bind(mainMod .. " + ALT + left", hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + right", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + up", hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + down", hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })

-- Monitor focus
hl.bind(mainMod .. " + period", hl.dsp.focus({ monitor = "+1" }))
hl.bind(mainMod .. " + comma", hl.dsp.focus({ monitor = "-1" }))

-- Mouse drag ({ mouse = true } = dawne bindm)
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots
hl.bind("PRINT", hl.dsp.exec_cmd("hyprshot -m region --clipboard-only"))
hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd("hyprshot -m region -o $HOME/Screenshots"))

-- Keybindings depending on the keyboard model
require(HOME .. "/archenemy/config/hypr/keyboard.lua")
require(HOME .. "/archenemy/config/hypr/hardware-keys.lua")

-- Window rules
hl.window_rule({ match = { class = "^(thunar)$", title = "^(File Operation Progress)$" }, float = true })
hl.window_rule({ match = { title = "^(Open File)$" }, float = true })
hl.window_rule({ match = { title = "^(Save File|Save As)$" }, float = true })
hl.window_rule({ match = { class = "^(xdg-desktop-portal-gtk)$" }, float = true })
hl.window_rule({ match = { title = "^(Picture-in-Picture)$" }, float = true })
hl.window_rule({ match = { title = "^(Picture-in-Picture)$" }, pin = true })
hl.window_rule({ match = { title = "^(Picture-in-Picture)$" }, size = { 480, 270 } })
hl.window_rule({ match = { title = "^(Picture-in-Picture)$" }, move = { "100%-490", "100%-280" } })
require(HOME .. "/archenemy/config/hypr/custom_window_rules.lua")

-- Layer rules
hl.layer_rule({ match = { namespace = "^(waybar)$" }, blur = true })
hl.layer_rule({ match = { namespace = "^(waybar)$" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "^(notifications)$" }, blur = true })
hl.layer_rule({ match = { namespace = "^(notifications)$" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "^(notifications)$" }, animation = "slide" })
hl.layer_rule({ match = { namespace = "^(rofi)$" }, blur = true })
hl.layer_rule({ match = { namespace = "^(rofi)$" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "^(rofi)$" }, animation = "popin 80%" })
