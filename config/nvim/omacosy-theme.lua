-- omacosy-theme.lua — Neovim follows omacosy's custom theme through Aether's
-- colourscheme (omacom/aether.nvim).
--
-- `omacosy-term-auto-theme on` links this file into ~/.config/nvim/lua/plugins/,
-- and `off` removes the link. While a custom theme is on screen, omacosy writes
-- ~/.config/omacosy/nvim/palette.lua (the role table Aether's colourscheme
-- consumes); this applies it. On a stock theme that file is gone and the
-- colourscheme that was on before ours comes back.
--
-- The palette folder is watched, and Aether's `setup` is re-run on every change,
-- so an already-open Neovim follows a theme switch without a restart. The
-- editor stays transparent so the terminal's opacity shows through, as it does
-- in the shell.

local dir = vim.fn.expand("~/.config/omacosy/nvim")
local file = dir .. "/palette.lua"

-- the colourscheme that was on before ours, so it can come back
local own

local function load()
  local ok, p = pcall(dofile, file)
  if ok and type(p) == "table" and type(p.colors) == "table" then return p.colors end
end

local function apply()
  local colors = load()
  if not colors then
    if vim.g.colors_name == "aether" then
      vim.cmd("hi clear")
      pcall(vim.cmd.colorscheme, own or "default")
    end
    return
  end
  if vim.g.colors_name ~= "aether" then own = vim.g.colors_name end
  require("aether").setup({
    transparent = true,
    styles = { sidebars = "transparent", floats = "transparent" },
    colors = colors,
  })
  vim.cmd.colorscheme("aether")
end

return {
  {
    "omacom/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    lazy = false,
    config = function()
      -- omacosy replaces palette.lua with a rename, so the FOLDER is watched,
      -- and the burst of events one write makes is folded into one reload.
      local ev, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
      if ev and timer then
        ev:start(dir, {}, function()
          timer:stop()
          timer:start(100, 0, vim.schedule_wrap(apply))
        end)
      end
      -- after VimEnter, so the colourscheme your config sets comes first and is
      -- the one remembered for the way back
      vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = apply })
    end,
  },
}
