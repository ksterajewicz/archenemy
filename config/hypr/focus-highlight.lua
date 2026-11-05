-- =============================================
--   archenemy - focus-highlight.lua (warstwa WSPÓLNA)
--   Podświetlenie aktywnego okna (ramka + poświata) gaśnie, gdy kursor
--   opuści monitor tego okna, i wraca razem z nim. require z rice'ów parytetu.
--
--   Hyprland przy przejściu kursora na inny monitor zmienia tylko fokus
--   MONITORA; okno zostaje aktywne, dopóki kursor nie wjedzie na inne okno
--   (src/managers/input/InputManager.cpp v0.57.1). Stąd neon na monitorze,
--   z którego kursor już wyszedł. Lua nie ma dyspozytora „odbierz fokus”,
--   a `hl.dsp.focus({ monitor = … })` przerzuca kursor na środek ekranu,
--   więc zmieniamy wyłącznie wygląd: na czas nieobecności kolory aktywnego
--   okna = kolory nieaktywnego. Klawiatura zostaje w oknie, także w grze.
--
--   Kolory czytamy z żywego configu, dlatego plik nie zna palety rice'a.
--   Reload (Super+T, `hyprctl reload`) buduje stan Lua od nowa i przywraca
--   kolory rice'a sam, więc nic nie zostaje zgaszone na stałe.
-- =============================================

-- Paleta czytana RAZ na stan Lua: Hyprland oddaje kolor obcięty do liczby
-- całkowitej (CHyprColor::getAsHex), więc ponowny odczyt po każdym cyklu
-- przyciemniałby kolory o ułamek przy każdym przejściu kursora.
local palette = nil
local dimmed = false

-- color_inactive bez wartości w ricu = -1, czyli biel; to nie jest kolor rice'a.
local function usable(value)
    if type(value) == "table" then value = value.colors and value.colors[1] end
    return value ~= nil and value ~= "0xFFFFFFFF"
end

local function apply(active_border, shadow)
    hl.config({ general = { ["col.active_border"] = active_border } })
    if shadow then hl.config({ decoration = { shadow = { color = shadow } } }) end
end

local function read_palette()
    local active   = hl.get_config("general:col.active_border")
    local inactive = hl.get_config("general:col.inactive_border")
    if not active or not inactive then return nil end

    local shadow          = hl.get_config("decoration:shadow:color")
    local shadow_inactive = hl.get_config("decoration:shadow:color_inactive")
    if not usable(shadow_inactive) then shadow, shadow_inactive = nil, nil end

    return { active = active, inactive = inactive, shadow = shadow, shadow_inactive = shadow_inactive }
end

local function dim()
    if dimmed then return end
    palette = palette or read_palette()
    if not palette then return end
    dimmed = true
    apply(palette.inactive, palette.shadow_inactive)
end

local function restore()
    if not dimmed then return end
    dimmed = false
    apply(palette.active, palette.shadow)
end

-- pcall: starszy Hyprland bez tych zdarzeń traci tylko tę funkcję, nie config.
pcall(hl.on, "monitor.focused", function(monitor)
    local window = hl.get_active_window()
    if window and window.monitor and window.monitor.id ~= monitor.id then
        dim()
    else
        restore()
    end
end)

-- Fokus trafił na okno: podświetlenie znów należy do aktywnego okna. Bez tego
-- zostałoby zgaszone po Super+strzałce na inny monitor, bo zdarzenie monitora
-- przychodzi wcześniej, gdy aktywne jest jeszcze stare okno.
pcall(hl.on, "window.active", restore)
