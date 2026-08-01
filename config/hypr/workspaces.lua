-- =============================================
--   archenemy - workspaces.lua (warstwa WSPÓLNA)
--
--   Bindy workspace'ów (Super+1..0, Shift, scroll) zależą od TRYBU
--   (shared/decades — data/workspace-mode.dat) i od maszyny, więc
--   generuje je install.sh [8b] do workspaces-monitors.lua
--   (warstwa maszynowa, poza gitem). Tu zostaje tylko część wspólna.
-- =============================================

-- Demon pilnujący workspace'ów-sierot (tylko tryb decades — w trybie
-- shared kończy się sam zaraz po starcie): po odpięciu monitora Hyprland
-- przenosi jego workspace'y na pozostały ekran (na pasku dublowała się
-- "1", a okna lądowały poza zasięgiem Super+1..0) — guard scala je
-- z dekadą ekranu, który został (11→1, 13→3 itd.).
-- hl.exec_cmd odpala asynchronicznie (dawne exec-once, bez & disown).
hl.on("hyprland.start", function()
    hl.exec_cmd("~/archenemy/scripts/hypr/workspace-orphan-guard.sh")
end)
