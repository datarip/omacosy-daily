-- omacosy-theme.lua — Neovim follows omacosy's custom theme through Aether's
-- colourscheme (omacom/aether.nvim).
--
-- `omacosy-term-auto-theme on` links this file into ~/.config/nvim/lua/plugins/,
-- and `off` removes the link. While a custom theme is on screen, omacosy writes
-- ~/.config/omacosy/nvim/palette.lua (the role table Aether's colourscheme
-- consumes); this hands that table to the plugin. On a stock theme the file is
-- gone and this spec returns nothing, so your own colourscheme comes back.
--
-- palette.lua is plain data, so a config without lazy.nvim can dofile() it and
-- use the colours however it likes.

local file = vim.fn.expand("~/.config/omacosy/nvim/palette.lua")

local function colors()
  local ok, p = pcall(dofile, file)
  if ok and type(p) == "table" and type(p.colors) == "table" then return p.colors end
end

local palette = colors()
if not palette then return {} end

return {
  {
    "omacom/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = { colors = palette },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "aether" },
  },
}
