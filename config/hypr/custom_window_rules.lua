-- =============================================
--   archenemy - custom_window_rules.lua (warstwa WSPÓLNA)
--   Reguły okien wspólne dla wszystkich rice'ów.
--   Uwaga na regexy: w stringach Lua backslash musi być podwojony
--   ("\\d", "\\.exe") — pojedynczy "\d" to błąd składni.
-- =============================================

-- Gry: tearing (immediate) = minimalny input lag (master toggle: general.allow_tearing)
-- steam_app_<id> = gry Steam/Proton — wcześniej nie łapała ich żadna reguła
hl.window_rule({ match = { class = "^(gamescope)$" }, immediate = true })
hl.window_rule({ match = { class = "^(.*\\.exe)$" }, immediate = true })
hl.window_rule({ match = { class = "^(steam_app_\\d+)$" }, immediate = true })

-- Gry: content type "game" — włącza auto-tryb cursor:no_break_fs_vrr
-- (ruch myszy nie wymusza dodatkowych klatek w fullscreenowej grze z VRR = brak skoków frametime)
hl.window_rule({ match = { class = "^(steam_app_\\d+|gamescope|.*\\.exe)$" }, content = "game" })

-- Gry: zero efektów rice'a na oknie gry — parytet z betą (tam gry działały dobrze):
-- bez blura, cieni, przyciemniania i animacji; okno w pełni nieprzezroczyste
hl.window_rule({ match = { class = "^(steam_app_\\d+|gamescope|.*\\.exe)$" }, no_blur = true })
hl.window_rule({ match = { class = "^(steam_app_\\d+|gamescope|.*\\.exe)$" }, no_shadow = true })
hl.window_rule({ match = { class = "^(steam_app_\\d+|gamescope|.*\\.exe)$" }, no_dim = true })
hl.window_rule({ match = { class = "^(steam_app_\\d+|gamescope|.*\\.exe)$" }, no_anim = true })
hl.window_rule({ match = { class = "^(steam_app_\\d+|gamescope|.*\\.exe)$" }, opaque = true })

hl.window_rule({ match = { class = "^(MEGAsync)$" }, float = true })
hl.window_rule({ match = { title = "^(Set up MEGA)$" }, float = true })
