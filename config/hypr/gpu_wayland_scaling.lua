-- =============================================
--   archenemy - gpu_wayland_scaling.lua (warstwa WSPÓLNA)
--   Uniwersalne zmienne środowiskowe Wayland/skalowanie.
--
--   Zmienne zależne od karty graficznej (np. NVIDIA)
--   są per-maszyna i lądują w generowanym pliku
--   gpu-env.lua (tworzy go install.sh po wykryciu GPU).
-- =============================================

hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("GDK_SCALE", "1")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("STEAM_FORCE_DESKTOPUI_SCALING", "1")
