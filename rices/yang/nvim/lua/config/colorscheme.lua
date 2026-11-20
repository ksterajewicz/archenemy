-- =============================================
--   archenemy - colorscheme (yang rice)
--   Jasny monochrom — odwrotność yin: tło #F3F3F5 (papier), tekst #1E1E22
--   (tusz), składnia rozróżniana JASNOŚCIĄ i krojem (bold/italic), nie
--   barwą — te same schodki szarości co ANSI alacritty. Czerń #0C0C0E =
--   akcent (słowa kluczowe, kursor, tytuły). Rdza #A23A10 to jedyny ciepły
--   kolor — wyłącznie błędy i ostrzeżenia (spójne z waybar/rofi/mako/
--   alacritty). Każdy kolor tekstu ≥ 4,5:1 na najgorszym tle szkła
--   alacritty (#E9E9EC, README). Ręczny, bez wtyczek.
-- =============================================

local p = {
  bg        = "#F3F3F5", -- tło rice'a (papier)
  bg_soft   = "#EBEBEE", -- CursorLine / panele (o stopień ciemniej)
  bg_float  = "#E1E1E5", -- okna pływające (mleko)
  bg_sel    = "#CCCCD0", -- Visual / selekcje (łupek)
  fg        = "#1E1E22", -- tusz
  fg_dim    = "#3B3B41", -- mgła (L* 25)
  accent    = "#0C0C0E", -- czerń (akcent)
  mid       = "#303035", -- L* 20
  muted     = "#46464C", -- L* 30
  comment   = "#5E5E66", -- L* 40 — komentarze (5,3:1 na najgorszym tle)
  linenr    = "#67676E", -- przygaszony (L* 44, 4,6:1)
  alert     = "#A23A10", -- rdza — wyłącznie błędy
  warn      = "#7E2E0E", -- ciemna rdza — ostrzeżenia (ten sam odcień)
}

local function hl(group, opts) vim.api.nvim_set_hl(0, group, opts) end

vim.g.colors_name = "archenemy-yang"
vim.o.background = "light"

-- Zaokrąglone tafle rice'a (rounding=12) → ramka "rounded" (nvim >= 0.11)
if vim.fn.has("nvim-0.11") == 1 then
  vim.o.winborder = "rounded"
end

-- Rdzeń edytora
hl("Normal",       { fg = p.fg, bg = p.bg })
hl("NormalFloat",  { fg = p.fg, bg = p.bg_float })
hl("FloatBorder",  { fg = p.comment, bg = p.bg_float })
hl("CursorLine",   { bg = p.bg_soft })
hl("CursorLineNr", { fg = p.accent, bold = true })
hl("LineNr",       { fg = p.linenr })
hl("SignColumn",   { bg = p.bg })
hl("Visual",       { bg = p.bg_sel })
hl("StatusLine",   { fg = p.bg, bg = p.fg_dim })
hl("StatusLineNC", { fg = p.comment, bg = p.bg_soft })
hl("Search",       { fg = p.bg, bg = p.muted })
hl("IncSearch",    { fg = p.bg, bg = p.accent, bold = true })
hl("CurSearch",    { fg = p.bg, bg = p.accent, bold = true })
hl("MatchParen",   { fg = p.accent, bold = true, underline = true })
hl("WinSeparator", { fg = p.bg_sel })
hl("ColorColumn",  { bg = p.bg_soft })
hl("NonText",      { fg = p.linenr })
hl("ErrorMsg",     { fg = p.alert, bold = true })
hl("WarningMsg",   { fg = p.warn })

-- Menu (natywne Pmenu — używane też przez popup nvim-cmp)
hl("Pmenu",      { fg = p.fg, bg = p.bg_float })
hl("PmenuSel",   { fg = p.bg, bg = p.accent })
hl("PmenuSbar",  { bg = p.bg_float })
hl("PmenuThumb", { bg = p.comment })

-- Składnia (regexowy syntax — brak treesittera w tym configu). Monochrom:
-- słowa kluczowe czarne i pogrubione, typy/funkcje o stopień jaśniej,
-- stałe i łańcuchy jeszcze wyżej, komentarze kursywą najjaśniej.
hl("Comment",    { fg = p.comment, italic = true })
hl("String",     { fg = p.muted })
hl("Function",   { fg = p.mid })
hl("Keyword",    { fg = p.accent, bold = true })
hl("Statement",  { fg = p.accent, bold = true })
hl("Type",       { fg = p.fg_dim, italic = true })
hl("Constant",   { fg = p.mid })
hl("Number",     { fg = p.mid })
hl("Boolean",    { fg = p.mid, bold = true })
hl("Identifier", { fg = p.fg })
hl("PreProc",    { fg = p.fg_dim })
hl("Special",    { fg = p.fg_dim, bold = true })
hl("Todo",       { fg = p.bg, bg = p.fg_dim, bold = true })

-- Diagnostyka LSP (rdza = błędy, ciemna rdza = ostrzeżenia — jeden ciepły odcień)
hl("DiagnosticError", { fg = p.alert })
hl("DiagnosticWarn",  { fg = p.warn })
hl("DiagnosticInfo",  { fg = p.fg_dim })
hl("DiagnosticHint",  { fg = p.comment })
hl("DiagnosticUnderlineError", { undercurl = true, sp = p.alert })
hl("DiagnosticUnderlineWarn",  { undercurl = true, sp = p.warn })

-- Diff (bez zieleni i czerwieni tła: dodane ciemniej, usunięte jaśniej,
-- zmienione podkreślone tłem)
hl("DiffAdd",    { fg = p.accent, bg = p.bg_sel })
hl("DiffDelete", { fg = p.linenr, bg = p.bg_soft })
hl("DiffChange", { bg = p.bg_soft })
hl("DiffText",   { fg = p.accent, bg = p.bg_sel, bold = true })

-- Telescope
hl("TelescopeNormal",       { fg = p.fg, bg = p.bg_float })
hl("TelescopeBorder",       { fg = p.comment, bg = p.bg_float })
hl("TelescopeSelection",    { fg = p.accent, bg = p.bg_sel })
hl("TelescopePromptNormal", { fg = p.fg, bg = p.bg_float })
hl("TelescopePromptBorder", { fg = p.comment, bg = p.bg_float })
hl("TelescopePromptTitle",  { fg = p.bg, bg = p.accent, bold = true })
hl("TelescopeResultsTitle", { fg = p.fg_dim })
hl("TelescopePreviewTitle", { fg = p.fg_dim })
hl("TelescopeMatching",     { fg = p.accent, bold = true })
