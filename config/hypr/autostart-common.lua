-- =============================================
--   archenemy - autostart-common.lua (warstwa WSPÓLNA)
--   Autostart wspólny dla wszystkich rice'ów — require z każdego
--   rices/*/hypr/hyprland.lua (parytet strukturalny, jak workspaces.lua).
--   Autostart wyglądu (waybar, mako, hyprpaper...) zostaje w rice'ach.
-- =============================================

-- flux-wall (animowana tapeta): wybór z Super+W (data/flux-wall.dat)
-- obowiązuje w KAŻDYM ricu (decyzja 2026-09-07j), a rice może mieć animację
-- domyślną (rices/<rice>/flux-wall.conf). `autostart` rozstrzyga oba
-- przypadki sam i po cichu nic nie robi przy wyborze "off", braku
-- deklaracji albo braku binarki (kod 4). Dawniej linia żyła tylko w crt
-- i dither-flux, więc po zalogowaniu do white-blue/tron/asia-n-rice
-- animacja wybrana w Super+W nie wracała (audyt 2026-09-23).
hl.on("hyprland.start", function()
    hl.exec_cmd("~/archenemy/scripts/wallpapers/flux-wall.sh autostart")
end)
