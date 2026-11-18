-- =============================================
--   archenemy - colorscheme (yin rice)
--   Monochrom: tło #0C0C0E (pustka), tekst #E6E6EA (papier), składnia
--   rozróżniana JASNOŚCIĄ i krojem (bold/italic), nie barwą — te same
--   schodki szarości co ANSI alacritty. Biel #FFFFFF = akcent (słowa
--   kluczowe, kursor, tytuły). Żar #E0805A to jedyny ciepły kolor —
--   wyłącznie błędy i ostrzeżenia (spójne z waybar/rofi/mako/alacritty).
--   Ręczny, bez wtyczek.
-- =============================================

local p = {
  bg        = "#0C0C0E", -- tło rice'a (pustka)
  bg_soft   = "#141417", -- CursorLine / panele (o stopień jaśniej)
  bg_float  = "#1E1E22", -- okna pływające (grafit)
  bg_sel    = "#2E2E33", -- Visual / selekcje (łupek)
  fg        = "#E6E6EA", -- papier
  fg_dim    = "#B6B6BD", -- mgła (L* 74)
  accent    = "#FFFFFF", -- biel (akcent)
  mid       = "#C6C6CC", -- L* 80
  muted     = "#A6A6AD", -- L* 68
  comment   = "#868690", -- L* 56 — komentarze (≥ 4,5:1 na tle)
  linenr    = "#5E5E66", -- dym
  alert     = "#E0805A", -- żar — wyłącznie błędy
  warn      = "#F2A07E", -- jasny żar — ostrzeżenia (ten sam odcień)
}

local function hl(group, opts) vim.api.nvim_set_hl(0, group, opts) end

vim.g.colors_name = "archenemy-yin"

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
-- słowa kluczowe białe i pogrubione, typy/funkcje o stopień ciemniej,
-- stałe i łańcuchy jeszcze niżej, komentarze kursywą najciemniej.
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

-- Diagnostyka LSP (żar = błędy, jasny żar = ostrzeżenia — jeden ciepły odcień)
hl("DiagnosticError", { fg = p.alert })
hl("DiagnosticWarn",  { fg = p.warn })
hl("DiagnosticInfo",  { fg = p.fg_dim })
hl("DiagnosticHint",  { fg = p.comment })
hl("DiagnosticUnderlineError", { undercurl = true, sp = p.alert })
hl("DiagnosticUnderlineWarn",  { undercurl = true, sp = p.warn })

-- Diff (bez zieleni i czerwieni tła: dodane jaśniej, usunięte ciemniej,
-- zmienione podkreślone)
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
