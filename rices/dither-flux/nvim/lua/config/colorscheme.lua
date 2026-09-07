-- =============================================
--   archenemy - colorscheme (dither-flux rice)
--   Paleta milford-woda: tło #0F1A24, woda #5C87A3, mgła #A8C4D4,
--   piana #D8E6EE jako akcent; bursztyn #E0A23C to jedyny ciepły kolor
--   i służy wyłącznie alarmom/ostrzeżeniom (spójne z waybar/rofi/mako).
-- =============================================

local p = {
  bg        = "#0F1A24", -- tło rice'a (mokre góry)
  bg_soft   = "#14222E", -- CursorLine / panele (wyspy waybara)
  bg_sel    = "#1B3040", -- Visual / selekcje
  fg        = "#D8E6EE", -- piana
  fg_dim    = "#A8C4D4", -- mgła
  accent    = "#D8E6EE", -- piana (akcent = najjaśniejszy kolor)
  accent2   = "#5C87A3", -- woda
  comment   = "#34546A",
  linenr    = "#2A4658",
  alert     = "#E0A23C", -- bursztyn — wyłącznie alarmy
  warn      = "#E0A23C", -- ten sam bursztyn (jeden ciepły kolor w palecie)
}

local function hl(group, opts) vim.api.nvim_set_hl(0, group, opts) end

vim.g.colors_name = "archenemy-dither-flux"

-- Prawie ostre rogi rice'a (rounding=4) → ramka "single" (nvim >= 0.11)
if vim.fn.has("nvim-0.11") == 1 then
  vim.o.winborder = "single"
end

-- Rdzeń edytora
hl("Normal",       { fg = p.fg, bg = p.bg })
hl("NormalFloat",  { fg = p.fg, bg = p.bg_soft })
hl("FloatBorder",  { fg = p.accent, bg = p.bg_soft })
hl("CursorLine",   { bg = p.bg_soft })
hl("CursorLineNr", { fg = p.accent, bold = true })
hl("LineNr",       { fg = p.linenr })
hl("SignColumn",   { bg = p.bg })
hl("Visual",       { bg = p.bg_sel })
hl("StatusLine",   { fg = p.bg, bg = p.accent })
hl("StatusLineNC", { fg = p.comment, bg = p.bg_soft })
hl("Search",       { fg = p.bg, bg = p.fg_dim })
hl("IncSearch",    { fg = p.bg, bg = p.accent, bold = true })
hl("CurSearch",    { fg = p.bg, bg = p.accent, bold = true })
hl("MatchParen",   { fg = p.accent2, bold = true, underline = true })
hl("WinSeparator", { fg = p.accent })
hl("ColorColumn",  { bg = p.bg_soft })

-- Menu (natywne Pmenu — używane też przez popup nvim-cmp)
hl("Pmenu",      { fg = p.fg, bg = p.bg_soft })
hl("PmenuSel",   { fg = p.bg, bg = p.accent })
hl("PmenuSbar",  { bg = p.bg_soft })
hl("PmenuThumb", { bg = p.accent })

-- Składnia (regexowy syntax — brak treesittera w tym configu)
hl("Comment",    { fg = p.comment, italic = true })
hl("String",     { fg = p.fg_dim })
hl("Function",   { fg = p.accent2 })
hl("Keyword",    { fg = p.accent, bold = true })
hl("Statement",  { fg = p.accent, bold = true })
hl("Type",       { fg = p.accent })
hl("Constant",   { fg = p.warn })
hl("Number",     { fg = p.warn })
hl("Boolean",    { fg = p.warn })
hl("Identifier", { fg = p.fg })
hl("PreProc",    { fg = p.accent2 })
hl("Special",    { fg = p.alert })

-- Diagnostyka LSP (bursztyn = alarmy i ostrzeżenia — jeden ciepły kolor)
hl("DiagnosticError", { fg = p.alert })
hl("DiagnosticWarn",  { fg = p.warn })
hl("DiagnosticInfo",  { fg = p.accent })
hl("DiagnosticHint",  { fg = p.fg_dim })
hl("DiagnosticUnderlineError", { undercurl = true, sp = p.alert })
hl("DiagnosticUnderlineWarn",  { undercurl = true, sp = p.warn })

-- Telescope (kursywne tytuły — echo kursywnych tytułów okien z waybara)
hl("TelescopeNormal",       { fg = p.fg, bg = p.bg_soft })
hl("TelescopeBorder",       { fg = p.accent, bg = p.bg_soft })
hl("TelescopeSelection",    { fg = p.fg, bg = p.bg_sel })
hl("TelescopePromptNormal", { fg = p.fg, bg = p.bg_soft })
hl("TelescopePromptBorder", { fg = p.accent, bg = p.bg_soft })
hl("TelescopePromptTitle",  { fg = p.bg, bg = p.accent, italic = true })
hl("TelescopeResultsTitle", { fg = p.accent, italic = true })
hl("TelescopePreviewTitle", { fg = p.accent, italic = true })
hl("TelescopeMatching",     { fg = p.accent2, bold = true })
