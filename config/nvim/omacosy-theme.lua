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
    on_highlights = function(hl, c)
      -- the LazyVim dashboard logo is the header; Aether links it to Title
      -- (blue), so name the theme's own accent directly.
      hl.SnacksDashboardHeader = { fg = c.accent }
      hl.SnacksDashboardFooter = { fg = c.accent }
      -- Omacosy's syntax layer; Aether has no token keys, so name the
      -- highlights itself. Guarded so an older palette.lua still fits.
      local s = c.syntax or {}
      local groups = {
        ["@operator"] = s.operator or c.operator,
        ["@keyword"] = s.keyword,
        ["@keyword.control"] = s["keyword.control"],
        ["@keyword.import"] = s["keyword.import"],
        ["@keyword.operator"] = s.operator or c.operator,
        ["@function"] = s.function,
        ["@function.call"] = s.function,
        ["@function.builtin"] = s["function.builtin"],
        ["@function.method"] = s["function.method"],
        ["@constructor"] = s.constructor,
        ["@string"] = s.string,
        ["@string.escape"] = s["string.escape"],
        ["@string.regex"] = s["string.regex"],
        ["@string.special"] = s["string.special"],
        ["@number"] = s.number,
        ["@boolean"] = s.boolean,
        ["@constant"] = s.constant,
        ["@constant.builtin"] = s["constant.builtin"],
        ["@type"] = s.type,
        ["@type.builtin"] = s["type.builtin"],
        ["@type.interface"] = s["type.interface"],
        ["@variable"] = s.variable,
        ["@variable.parameter"] = s["variable.parameter"],
        ["@variable.member"] = s["variable.member"],
        ["@property"] = s.property,
        ["@label"] = s.label,
        ["@attribute"] = s.attribute,
        ["@tag"] = s.tag,
        ["@title"] = s.title,
        ["@comment"] = s.comment,
        ["@comment.documentation"] = s["comment.doc"],
        ["@punctuation"] = s.punctuation,
        ["@punctuation.bracket"] = s["punctuation.bracket"],
        ["@punctuation.delimiter"] = s["punctuation.delimiter"],
        ["@punctuation.special"] = s["punctuation.special"],
        ["@preproc"] = s.preproc,
        ["@text.literal"] = s["text.literal"],
        ["@markup.heading"] = s.title,
        ["@markup.strong"] = s["emphasis.strong"],
        ["@markup.italic"] = s.emphasis,
      }
      for group, colour in pairs(groups) do
        if colour then hl[group] = { fg = colour } end
      end
    end,
  })
  vim.cmd.colorscheme("aether")
  -- after the colorscheme, so Snacks cannot relink it to Title
  vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "SnacksDashboardFooter", { fg = colors.accent })
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
