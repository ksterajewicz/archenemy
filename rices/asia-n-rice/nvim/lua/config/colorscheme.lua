-- =============================================
--   archenemy - colorscheme (asia-n-rice)
--   Paleta rice'a: przygaszony mauve #b47687 (jaśniejszy #c98a99)
--   na ciemnym granacie — tło terminala #182130, panele #2a3444,
--   urgent #d9738a (spójne z waybar/rofi/mako/hyprlock).
--   Płaski look rice'a → bez boldów na akcentach, ramka "single".
-- =============================================

local p = {
  bg        = "#182130", -- tło alacritty rice'a
  bg_soft   = "#1F2A3B", -- CursorLine
  bg_panel  = "#2a3444", -- panele (kolor wysp waybara) / selekcje
  fg        = "#e8e8e8",
  fg_dim    = "#a3b5cf", -- chłodny błękitnoszary — łańcuchy, info
  accent    = "#b47687", -- mauve rice'a
  accent2   = "#c98a99", -- jaśniejszy wariant
  comment   = "#5C6A85",
  linenr    = "#4a5670",
  alert     = "#d9738a", -- urgent rice'a
}

local function hl(group, opts) vim.api.nvim_set_hl(0, group, opts) end

vim.g.colors_name = "archenemy-asia-n-rice"

-- Płaski look, ostre rogi okien rice'a → ramka "single" (nvim >= 0.11)
if vim.fn.has("nvim-0.11") == 1 then
  vim.o.winborder = "single"
end

-- Rdzeń edytora (płasko: bez boldów na akcentach)
hl("Normal",       { fg = p.fg, bg = p.bg })
hl("NormalFloat",  { fg = p.fg, bg = p.bg_panel })
hl("FloatBorder",  { fg = p.accent, bg = p.bg_panel })
hl("CursorLine",   { bg = p.bg_soft })
hl("CursorLineNr", { fg = p.accent2 })
hl("LineNr",       { fg = p.linenr })
hl("SignColumn",   { bg = p.bg })
hl("Visual",       { bg = p.bg_panel })
hl("StatusLine",   { fg = p.fg, bg = p.bg_panel })
hl("StatusLineNC", { fg = p.comment, bg = p.bg_soft })
hl("Search",       { fg = p.bg, bg = p.fg_dim })
hl("IncSearch",    { fg = p.bg, bg = p.accent2 })
hl("CurSearch",    { fg = p.bg, bg = p.accent2 })
hl("MatchParen",   { fg = p.accent2, underline = true })
hl("WinSeparator", { fg = p.accent })
hl("ColorColumn",  { bg = p.bg_soft })

-- Menu (natywne Pmenu — używane też przez popup nvim-cmp)
hl("Pmenu",      { fg = p.fg, bg = p.bg_panel })
hl("PmenuSel",   { fg = p.bg, bg = p.accent })
hl("PmenuSbar",  { bg = p.bg_panel })
hl("PmenuThumb", { bg = p.accent })

-- Składnia (regexowy syntax — brak treesittera w tym configu)
hl("Comment",    { fg = p.comment, italic = true })
hl("String",     { fg = p.fg_dim })
hl("Function",   { fg = p.accent2 })
hl("Keyword",    { fg = p.accent })
hl("Statement",  { fg = p.accent })
hl("Type",       { fg = p.accent })
hl("Constant",   { fg = p.accent2 })
hl("Number",     { fg = p.accent2 })
hl("Boolean",    { fg = p.accent2 })
hl("Identifier", { fg = p.fg })
hl("PreProc",    { fg = p.accent2 })
hl("Special",    { fg = p.alert })

-- Diagnostyka LSP (urgent rice'a = #d9738a)
hl("DiagnosticError", { fg = p.alert })
hl("DiagnosticWarn",  { fg = p.accent2 })
hl("DiagnosticInfo",  { fg = p.fg_dim })
hl("DiagnosticHint",  { fg = p.comment })
hl("DiagnosticUnderlineError", { undercurl = true, sp = p.alert })
hl("DiagnosticUnderlineWarn",  { undercurl = true, sp = p.accent2 })

-- Telescope (kursywne tytuły — echo kursywnych tytułów okien z waybara)
hl("TelescopeNormal",       { fg = p.fg, bg = p.bg_panel })
hl("TelescopeBorder",       { fg = p.accent, bg = p.bg_panel })
hl("TelescopeSelection",    { fg = p.fg, bg = p.bg_soft })
hl("TelescopePromptNormal", { fg = p.fg, bg = p.bg_panel })
hl("TelescopePromptBorder", { fg = p.accent, bg = p.bg_panel })
hl("TelescopePromptTitle",  { fg = p.bg, bg = p.accent, italic = true })
hl("TelescopeResultsTitle", { fg = p.accent, italic = true })
hl("TelescopePreviewTitle", { fg = p.accent, italic = true })
hl("TelescopeMatching",     { fg = p.accent2 })
