-- =============================================
--   archenemy - keyboard.lua (warstwa WSPÓLNA)
--   Uniwersalne klawisze multimedialne.
--
--   Bindy zależne od sprzętu (np. klawisze ASUS ROG)
--   są per-maszyna i lądują w generowanym pliku
--   hardware-keys.lua (tworzy go install.sh).
--
--   Konwencja formatu (parsuje ją appbinds.sh — [s] w Super+A):
--   każdy bind w JEDNEJ linii zaczynającej się od `hl.bind(`.
-- =============================================

-- Głośność ({ repeating = true } = dawne binde: trzymanie klawisza powtarza)
-- `; pkill -RTMIN+10 waybar` = natychmiastowe odświeżenie paska głośności
-- (moduł custom/volumebar, signal 10) po klawiszu sprzętowym.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+; pkill -RTMIN+10 waybar"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-; pkill -RTMIN+10 waybar"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle; pkill -RTMIN+10 waybar"))
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))

-- Multimedia
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))

-- Jasność przez swayosd-client: zmienia jasność I pokazuje pasek OSD u dołu
-- wszystkich monitorów (swayosd-server autostartuje każdy rice). Zastępuje
-- brightnessctl w bindzie (swayosd robi jedno i drugie).
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("swayosd-client --brightness raise"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("swayosd-client --brightness lower"), { repeating = true })
