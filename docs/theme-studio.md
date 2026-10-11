# Theme Studio

The Theme Studio is the editing half of Omacosy's custom themes, inside the
`Super`+`,` settings dashboard. It has two parts:

- the **Theme Editor**, opened from the **Edit** / **Customize** pill on a
  custom theme card, with the Palette Builder, the live previews and the
  Wallpaper Editor (`README.md`, "Themes"); and
- **Export / Import**, the two footer buttons that move a theme in and out of
  Omacosy as a shareable folder.

Everything below is fork-only. The four stock Omarchy themes are never touched,
and a theme's wallpaper picture is never rewritten.

## Exporting a theme

**From the editor.** Press **Export** in the footer. A folder picker opens; the
bundle is written into a **new folder named after the theme** inside the folder
you choose, so nothing is dropped loose among your files. The footer reports
where it landed, e.g. `Exported to /Users/you/Desktop/sunset-drive`. A draft or
an edited theme is saved first, so the bundle always matches what is on screen.

**From the command line.**

```sh
omacosy-themecore theme export <id> --bundle DIR        # the full folder
omacosy-themecore theme export <id> --out FILE.json     # just the record
```

`--templates DIR` points at another `config/theme-templates` tree; it is found
automatically from the repo otherwise.

### What a bundle contains

A full bundle is 17 files (16 when the theme has no per-app overrides):

| File | What it is |
| --- | --- |
| `<id>.json` | the theme record — the same file Omacosy keeps in `~/.config/omacosy/themes/` |
| `colors.toml` | the flat 22-key Omarchy palette |
| `zed.json` | Zed theme |
| `neovim.lua` | Neovim scheme (`omacom/aether.nvim`, LazyVim) |
| `vscode-extension/` | a VS Code colour-theme extension (`package.json`, `themes/theme.json`) |
| `ghostty.conf`, `starship.toml`, `term-env.sh`, `term-palette.env` | the terminal's own colours |
| `btop.theme`, `nvim-palette.lua`, `lazygit-theme.yml`, `delta.gitconfig`, `yazi-theme.toml`, `tmux-theme.conf` | the terminal tools' configs |
| `overrides.env` | per-app role overrides, only when the theme has any |

The bundle is self-contained: every file is generated from the theme, so it
never points back at the machine that made it. It carries the theme's colours
and configs, **not** the wallpaper picture — the record's `wallpaper.path` is
provenance only, and the editor re-seeds its palette from whatever wallpaper
you open it on.

### No secrets

An export contains only colours and configs. The wallhaven API key and any
other value in `~/.config/omacosy/secrets.conf` are never read and never
written into a bundle.

## Importing a theme

**From the editor.** Press **Import** and pick a file. Three formats are read:

- Omacosy's own theme JSON (the `<id>.json` from a bundle);
- a flat Omarchy `colors.toml` (the 22-key shape the stock themes use);
- a Base16 scheme (YAML). The format is sniffed from the content, so a
  correctly-named file needs no flag.

If the theme's id is already in your library, a small card asks **Rename**
(keep both — the import gets a fresh id, `-2`, `-3`…) or **Replace** (overwrite
the saved record). Esc cancels.

**From the command line.**

```sh
omacosy-themecore theme import <file> [--id ID] [--name NAME] \
    [--format json|colors-toml|base16] [--replace|--rename] [--json]
```

Without `--replace` or `--rename`, an id that already exists is refused, and
the message names both flags.

## Credits and attribution

Omacosy's Theme Studio is built on **[Aether](https://github.com/omacom/aether)**
(MIT, © Bjarne Overli): the colour science, the extraction and palette
generators, the tone curve, the image pipeline and the template engine are
ports of Aether's Go and TypeScript. Ported functions carry a header naming
Aether; the vendored templates under `config/theme-templates/` carry the same
header.

The 40 palettes in the Method / Presets pickers are Aether's `PRESET_THEMES`,
kept verbatim (names and colours). The five Omacosy-adjacent entries are
Aether's own designs; the rest are well-known schemes, credited here to their
upstream project and the Neovim port Aether itself points at.

| Preset(s) | Upstream project |
| --- | --- |
| Aether, Pina, Sakura, Fireside, Frost | Aether (© Bjarne Overli, MIT) |
| Catppuccin Mocha, Catppuccin Latte | [Catppuccin](https://github.com/catppuccin/catppuccin) (`catppuccin/nvim`) |
| Tokyo Night, Tokyo Night Day | [Tokyo Night](https://github.com/folke/tokyonight.nvim) (`folke`) |
| Gruvbox Dark, Gruvbox Light | [Gruvbox](https://github.com/morhetz/gruvbox) (`ellisonleao/gruvbox.nvim`) |
| Gruvbox Material | [Gruvbox Material](https://github.com/sainnhe/gruvbox-material) (`sainnhe`) |
| Solarized Dark, Solarized Light | [Solarized](https://github.com/altercation/solarized) (`maxmx03/solarized.nvim`) |
| One Dark, One Light | [One Dark](https://github.com/navarasu/onedark.nvim) (`navarasu`) |
| Dracula | [Dracula](https://github.com/dracula/dracula-theme) (`Mofiqul/dracula.nvim`) |
| Nord | [Nord](https://github.com/nordtheme/nord) (`shaunsingh/nord.nvim`) |
| Monokai Pro, Ristretto | [Monokai Pro](https://monokai.pro) (`loctvl842/monokai-pro.nvim`) |
| Palenight | [Material Palenight](https://github.com/drewtempelmeyer/palenight.vim) (`drewtempelmeyer`) |
| Rose Pine, Rose Pine Dawn | [Rosé Pine](https://github.com/rose-pine/rose-pine) (`rose-pine/neovim`) |
| Everforest, Everforest Light | [Everforest](https://github.com/sainnhe/everforest) (`neanias/everforest-nvim`) |
| Matte Black | [Matte Black](https://github.com/tahayvr/matteblack.nvim) (`tahayvr`) |
| Osaka Jade | [Bamboo](https://github.com/ribru17/bamboo.nvim) (`ribru17`); also maps to Omarchy's stock `osaka-jade` |
| Kanagawa | [Kanagawa](https://github.com/rebelot/kanagawa.nvim) (`rebelot`) |
| Nightfox | [Nightfox](https://github.com/EdenEast/nightfox.nvim) (`EdenEast`) |
| Ayu Mirage | [Ayu](https://github.com/ayu-theme/ayu-colors) (`Shatur/neovim-ayu`) |
| Oceanic Next | [Oceanic Next](https://github.com/voronianski/oceanic-next-color-scheme) (`mhartington/oceanic-next`) |
| Horizon | [Horizon](https://github.com/jolaleye/horizon-theme-vscode) (`akinsho/horizon.nvim`) |
| Andromeda | [Andromeda](https://github.com/EliverLara/Andromeda) (`safv12/andromeda.vim`) |
| Synthwave 84 | [Synthwave '84](https://github.com/robb0wen/synthwave-vscode) (`artanikin/vim-synthwave84`) |
| GitHub Dark, GitHub Light | [GitHub](https://github.com/projekt0n/github-nvim-theme) (`projekt0n`) |
| Monochrome Dark, Monochrome Light | [Monochrome](https://github.com/kdheepak/monochrome.nvim) (`kdheepak`) |
| Oxocarbon Dark, Oxocarbon Light | [Oxocarbon](https://github.com/nyoom-engineering/oxocarbon.nvim) (`nyoom-engineering`) |

## Future improvements

- **Kitty / Alacritty / Warp appliers** — Aether also writes `kitty.conf`,
  `alacritty.toml` and `warp.yaml`. Omacosy does not yet; the terminal pipeline
  covers Ghostty, btop, Neovim, lazygit, fastfetch, yazi, bat, delta, fzf and
  tmux. When added, they should be **installed-only**: rendered only for a
  terminal found with `command -v`, guarded, and written into the export bundle
  like the others. Templates would be vendored under `config/theme-templates/`
  with the Aether attribution header. Deferred (optional, after publish).
- **LLM naming and LLM API keys** are deferred to a separate effort; the
  `~/.config/omacosy/secrets.conf` shape already leaves room for the keys, and
  naming would rename through `omacosy-themecore wallpaper rename` and
  `theme rename` so no reference is left dangling.
