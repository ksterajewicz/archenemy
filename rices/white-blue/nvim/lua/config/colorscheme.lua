-- =============================================
--   archenemy - colorscheme (white-blue rice)
--   Paleta rice'a: biało-niebieskie szkło — akcent #0148ED / #4A7FFF,
--   tło terminala #1A1A2E, alert #D93025 (spójne z waybar/rofi/mako).
--   Ręczny motyw (nvim_set_hl), bez wtyczki-colorscheme — zgodnie
--   z filozofią repo: każda apka stylowana ręcznie per rice.
-- =============================================

local p = {
  bg        = "#1A1A2E", -- tło alacritty rice'a
  bg_soft   = "#24243A", -- CursorLine / panele
  bg_sel    = "#2C3454", -- Visual / selekcje
  fg        = "#FFFFFF",
  fg_dim    = "#C9D4FF", -- jasny niebieskawy — stałe, liczby
  accent    = "#0148ED", -- główny akcent rice'a
  accent2   = "#4A7FFF", -- partner gradientu
  accent3   = "#7FA6FF", -- jaśniejsza pochodna (funkcje)
  string_   = "#9FB8FF", -- łańcuchy — miękki błękit
  comment   = "#7A7A9A",
  linenr    = "#5A5A78",
  alert     = "#D93025", -- urgent/critical rice'a
}

local function hl(group, opts) vim.api.nvim_set_hl(0, group, opts) end

vim.g.colors_name = "archenemy-white-blue"

-- Miękkie szkło rice'a → zaokrąglone ramki okien pływających (nvim >= 0.11)
if vim.fn.has("nvim-0.11") == 1 then
  vim.o.winborder = "rounded"
end

-- Rdzeń edytora
hl("Normal",       { fg = p.fg, bg = p.bg })
hl("NormalFloat",  { fg = p.fg, bg = p.bg_soft })
hl("FloatBorder",  { fg = p.accent2, bg = p.bg_soft })
hl("CursorLine",   { bg = p.bg_soft })
hl("CursorLineNr", { fg = p.accent2, bold = true })
hl("LineNr",       { fg = p.linenr })
hl("SignColumn",   { bg = p.bg })
hl("Visual",       { bg = p.bg_sel })
hl("StatusLine",   { fg = p.fg, bg = p.accent })
hl("StatusLineNC", { fg = p.comment, bg = p.bg_soft })
hl("Search",       { fg = p.bg, bg = p.accent3 })
hl("IncSearch",    { fg = p.bg, bg = p.accent2, bold = true })
hl("CurSearch",    { fg = p.bg, bg = p.accent2, bold = true })
hl("MatchParen",   { fg = p.accent2, bold = true, underline = true })
hl("WinSeparator", { fg = p.accent })
hl("ColorColumn",  { bg = p.bg_soft })

-- Menu (natywne Pmenu — używane też przez popup nvim-cmp)
hl("Pmenu",      { fg = p.fg, bg = p.bg_soft })
hl("PmenuSel",   { fg = p.fg, bg = p.accent })
hl("PmenuSbar",  { bg = p.bg_soft })
hl("PmenuThumb", { bg = p.accent2 })

-- Składnia (regexowy syntax — brak treesittera w tym configu)
hl("Comment",    { fg = p.comment, italic = true })
hl("String",     { fg = p.string_ })
hl("Function",   { fg = p.accent3 })
hl("Keyword",    { fg = p.accent2, bold = true })
hl("Statement",  { fg = p.accent2, bold = true })
hl("Type",       { fg = p.accent2 })
hl("Constant",   { fg = p.fg_dim })
hl("Number",     { fg = p.fg_dim })
hl("Boolean",    { fg = p.fg_dim })
hl("Identifier", { fg = p.fg })
hl("PreProc",    { fg = p.accent3 })
hl("Special",    { fg = p.accent2 })

-- Diagnostyka LSP (alert rice'a = #D93025)
hl("DiagnosticError", { fg = p.alert })
hl("DiagnosticWarn",  { fg = p.accent3 })
hl("DiagnosticInfo",  { fg = p.accent2 })
hl("DiagnosticHint",  { fg = p.comment })
hl("DiagnosticUnderlineError", { undercurl = true, sp = p.alert })
hl("DiagnosticUnderlineWarn",  { undercurl = true, sp = p.accent3 })

-- Telescope (kursywne tytuły — echo kursywnych tytułów okien z waybara)
hl("TelescopeNormal",       { fg = p.fg, bg = p.bg_soft })
hl("TelescopeBorder",       { fg = p.accent2, bg = p.bg_soft })
hl("TelescopeSelection",    { fg = p.fg, bg = p.bg_sel })
hl("TelescopePromptNormal", { fg = p.fg, bg = p.bg_soft })
hl("TelescopePromptBorder", { fg = p.accent2, bg = p.bg_soft })
hl("TelescopePromptTitle",  { fg = p.fg, bg = p.accent, italic = true })
hl("TelescopeResultsTitle", { fg = p.accent2, italic = true })
hl("TelescopePreviewTitle", { fg = p.accent2, italic = true })
hl("TelescopeMatching",     { fg = p.accent3, bold = true })
