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

Saving or applying keeps the editor open: **Save** writes the theme and
**Apply & Save** writes it and puts it on the desktop, but neither closes the
window — only the **✕** button or **Esc** does. Several palettes can therefore
be saved, applied and compared in one sitting. Applying a theme repaints the
whole editor too, scrollbars and buttons included. The dashboard and the bar
draw their own background and pills from the palette's **accent** — Aether's
ANSI blue slot (index 4) for a Mode or Preset, the picture's own derived role
accent for Magic — so any applied palette keeps Omacosy's chrome on theme. The
**Accent** group in the Semantic Colors section is a different thing: its
**Orange** shade is the red slot lightened 15%, a palette shade that drives no
desktop surface by itself.

Magic's slot 0 is the wallpaper theme's own background — the same
`OMACOSY_BG` the auto themes draw on, not the ANSI black one rung above it —
so its terminal preview is as deep as an Aether preset's instead of washing
out over the wallpaper.

The editor previews the theme you are building **live**: its own background,
text, pills and accent follow the draft as you transform the palette, before
you apply; the **Method** and **Presets** dropdowns apply the highlighted
row at once as you walk them with ↑ and ↓, so the preview follows the
arrows and Return is only ever a close. Each Method row's 16-square strip
comes from the engine: the generated modes share one image sample — not one
extraction per row — and Magic runs its own analysis beside them, so an
edited theme's Magic row fills as well as a raw wallpaper's. A strip that
arrives late fills in on the open card rather than waiting for a reopen. A
picture above the engine's 40-megapixel decode cap is sampled from an
ImageIO thumbnail instead of a full-size frame, so an 8K wallpaper still
fills every Method row. The centre pane's toolbar toggles the mock
**menu bar**, the **terminal**, the
focus **ring** and a fake
**cheat sheet** (the one surface that shows Muted as the descriptions,
Label as the keys and Accent as the headings). The mock terminal, the
cheat sheet and the ring follow the **Window & UI Corners** setting, and a
small **AA** pill in the preview's bottom-left — the app's background with
accent ink — carries the same pass count as the **Accessibility** table,
live, so a colour change can be checked without scrolling the Palette
Builder down to the table. A click
outside the mock terminal or the cheat sheet dismisses it, and its toolbar
toggle follows. And the **Semantic Colors** section carries two
Omacosy-owned groups — **Omacosy** (**Background, Pill, Muted, Label,
Accent**) and **Ring & Status** (**Ring, Red, Green, Yellow**) — that are
editable **independently of the palette the terminal tools use**. Overriding
one changes only that Omacosy surface, never the `colors.toml` the terminal
follows; click a card to open the colour inspector, and the pin dot plus the
header Reset or "Reset N pinned" return them to auto. The inspector's header
swatch is a colour well like the Palette Grade and From Colour swatches:
click it for the system colour picker and use its eyedropper to sample the
wallpaper preview.

The **Syntax** row is full width and carries the ten base roles as swatches:
**Operator, Keyword, Function, String, Number, Type, Variable, Property,
Comment, Punctuation**. Each is derived from the palette and pinnable like the
other shades; the nine family roles are stored as `syntax_<role>` pins, while
**Operator** keeps its own `operator` pin. Operator is derived to
stay perceptually clear of the variable foreground and the number colour, and
is pushed to at least 4.5:1 on the background; when the bright-blue slot
already stands apart it is kept, so most themes do not move. A literal
complementary hue is deliberately not used: for a blue accent it would land on
the number colour. The per-app **Template Overrides** panel also lists **Zed**
and **VS Code** with their own **Operator** role, so an editor can diverge
without changing the theme.

The row header carries the **Variant Style** dropdown. **Classic** keeps the
shipped token bindings, so an existing theme does not change. **Grouped**
gives every variant its family's colour and leaves the differentiation to
italics and weights. **Neighboring** keeps each variant a close shade of its
family. **Expressive** rotates the variant's hue far enough to read as its own
colour inside the family — green strings gain a teal escape and a yellow
regex, blue functions a violet builtin — instead of merely a lighter tint.
The choice is stored as `palette.syntax` in the record, applies live to the
mock terminal, and
travels to the Zed, VS Code and Neovim exports. The base swatches are the
families; the dropdown changes their derived variants, which is why the
base colours themselves stay put. It is a **variant style**, not a remap of
the ten base swatches: **Operator** has no derived variant, so it does not
change with the dropdown at all. A read-only **Variants** row below them
(String/Escape, Function/Builtin, Type/Builtin, Number/Boolean,
Comment/Doc, Punctuation/Bracket) shows those derived colours changing as
you pick Grouped, Neighboring or Expressive. The mock terminal's language
tabs show the same choices in context: doc comments, builtin calls,
properties, builtin types, booleans, string escapes, punctuation and
operators. A single variant can still be tuned by editing a template.

## Layout and styling

The editor is two columns of the same width around the centre preview: the
**Wallpaper Editor** (step 1) on the left and the **Palette Builder** (step 2)
on the right. Both use the same padding and the same vertical rhythm, so a
matching element — the tone curve, a slider row — comes out the same width and
the same distance from its heading on either side. The palette groups its data
under **Curves**, an **Adjustments** block of sliders and a framed
**Accessibility** table; each tone curve carries a scoped **Reset Curve**.

The whole system — the spacing scale, the type sizes, the frames and the
colour roles — is written down in [design-style.md](design-style.md). The code
in `helper/dashboard.swift` is the source of truth; that page explains it, and
a new control should follow it rather than copy a number from somewhere else.

## Saved editions

Every picture in the wallpaper folder (set in the **Storage** tab) is already a
theme of its own: the Themes
tab shows each as a `Wallpaper #N` cell under the **Auto Themes** heading,
whose colours come from that picture (the same Magic extraction the raw cells
use).
**Customize** on a raw cell opens the editor on a new, unsaved theme; **Save**
or **Apply & Save** stores it as a named **edition**, and from then on it sits
in the **Custom Themes** section above the auto themes — a rule and a section
title keep the two apart — sorted A→Z, with its own name and card — **Edit**
reopens it. With an untouched Magic palette the edition and the raw cell it
came from write byte-identical desktop files; an edition is the picture's own
theme plus, only when you change them, its palette, its picture edits and its
per-app overrides.

Each saved edition is one TOML file, `~/.config/omacosy/themes/<id>.toml`.
Schema 1 wrote JSON instead: those files are still read, and convert to TOML
the next time the theme is saved. `omacosy-themecore theme migrate` converts
a whole library at once, moving each superseded `.json` to the Finder Trash.

The theme on the desktop right now carries a green **Active** pill in the
bottom-left of its card. While the `custom` theme is on, `Super+Shift+B` walks
the grid's own order — the saved editions A→Z first, then the `Wallpaper #N`
cells — and wraps, so the keyboard and the grid never disagree. Right-click
any card for **Set as Day Theme** / **Set as Night Theme**: the macOS
appearance then picks between them, and a check marks the half a card already
holds; a named edition adds **Duplicate Theme** to the same menu, and every
custom card adds **Downscale a Copy…**, which writes a copy with a 3840 px
long side (4K) and leaves the original where it is. The save panel starts in
your wallpaper folder, so saving there adds the copy as a new `Wallpaper #N`
cell; the picture is decoded at the target size, so an 8K source is never
loaded whole. The Wallpaper Editor still renders at full resolution, which is
why this is the way to edit a picture the editor's own limit refuses. The same
copy is one command:

```sh
omacosy-themecore image downscale PICTURE --out COPY.jpg   # --max defaults to 3840
```

The hover **trash** asks before
removing: an edition's trash deletes just the record, while a raw wallpaper's trash moves
the picture to the Finder Trash and, as a separate choice, can delete the
editions built from it. Nothing is ever hard-deleted.

## Exporting a theme

**From the editor.** Press **Export** in the footer. A folder picker opens; the
bundle is written into a **new folder named after the theme** inside the folder
you choose, so nothing is dropped loose among your files. The footer reports
where it landed, e.g. `Exported to /Users/you/Desktop/sunset-drive`. A draft or
an edited theme is saved first, so the bundle always matches what is on screen.

**From the command line.**

```sh
omacosy-themecore theme export <id> --bundle DIR        # the full folder
omacosy-themecore theme export <id> --out FILE.toml     # just the record
```

`--templates DIR` points at another `config/theme-templates` tree; it is found
automatically from the repo otherwise.

### What a bundle contains

A full bundle is 17 files (16 when the theme has no per-app overrides or syntax pins):

| File | What it is |
| --- | --- |
| `<id>.toml` | the theme record — the same file Omacosy keeps in `~/.config/omacosy/themes/` (an older bundle's `<id>.json` imports too) |
| `colors.toml` | the flat 22-key Omarchy palette |
| `zed.json` | Zed theme |
| `neovim.lua` | Neovim scheme (`omacom/aether.nvim`, LazyVim) |
| `vscode-extension/` | a VS Code colour-theme extension (`package.json`, `themes/theme.json`) |
| `ghostty.conf`, `starship.toml`, `term-env.sh`, `term-palette.env` | the terminal's own colours |
| `btop.theme`, `nvim-palette.lua`, `lazygit-theme.yml`, `delta.gitconfig`, `yazi-theme.toml`, `tmux-theme.conf` | the terminal tools' configs |
| `overrides.env` | per-app role overrides plus the theme-wide operator and `syntax_<role>` pins, when present |

The bundle is self-contained: every file is generated from the theme, so it
never points back at the machine that made it. It carries the theme's colours
and configs, **not** the wallpaper picture — the record's `wallpaper.path` is
provenance only, and the editor re-seeds its palette from whatever wallpaper
you open it on.

Zed's `operator`, VS Code's semantic and TextMate operator scopes, and
Neovim's `operator` colour all read the theme's **Operator** role, so the
exported editors agree with the editor preview and with each other.

### No secrets

An export contains only colours and configs. The wallhaven API key and any
other value in `~/.config/omacosy/secrets.conf` are never read and never
written into a bundle.

## Importing a theme

**From the editor.** Press **Import** and pick a file. Three formats are read:

- Omacosy's own theme record, TOML (and the JSON an older bundle carries);
- a flat Omarchy `colors.toml` (the 22-key shape the stock themes use);
- a Base16 scheme (YAML). The format is sniffed from the content, so a
  correctly-named file needs no flag.

If the theme's id is already in your library, a small card asks **Rename**
(keep both — the import gets a fresh id, `-2`, `-3`…) or **Replace** (overwrite
the saved record). Esc cancels.

**From the command line.**

```sh
omacosy-themecore theme import <file> [--id ID] [--name NAME] \
    [--format json|toml|colors-toml|base16] [--replace|--rename] [--json]
```

Without `--replace` or `--rename`, an id that already exists is refused, and
the message names both flags.

## Custom presets

The Wallpaper Editor's **Presets** section keeps Aether's built-in looks (the
dropdown) and lets you save your own. Under **COLOR FILTERS** it also carries
eight Wratten-style filters — **Red, Orange, Yellow, Green, Teal, Blue, Violet
and Magenta** — each of which turns the picture black and white and lays a
coloured filter over the luma. They are ordinary recipes: Saturation 0,
Contrast 115, plus `colorFilterHue` (0–360) and `colorFilterStrength` (0–100),
so a custom preset can carry its own hue and the master **Strength** blends it
with everything else. From the CLI the same two fields are
`--color-filter-hue` and `--color-filter-strength`.

**Save Current** stores the filter
adjustments you have made to the picture — only the values that differ from the
defaults — under a name you type. Saved presets show as rows under **Custom**:
click a name to apply it, click its **✕** to delete it. Applying a preset is a
clean look, exactly Aether's rule: every slider the preset does not mention
returns to its neutral default, while the structural settings it does not carry
— crop, rotate/flip, resize, the tone curve and the master strength — are left
as they are.

**Import** and **Export** move the whole list as one JSON file in Aether's
`aether-presets.json` shape (an array of `{name, values}`), so a preset file
made in Aether loads in Omacosy and the other way round. Import **merges by
name**: a preset the file shares with one of yours replaces it, the rest are
added. The list lives in `~/.config/omacosy/presets.json`, which survives both
`install.sh` and `uninstall.sh`.

From the command line:

```sh
omacosy-themecore image presets custom list
omacosy-themecore image presets custom save --name NAME --filters JSON
omacosy-themecore image presets custom delete --name NAME
omacosy-themecore image presets custom import FILE
omacosy-themecore image presets custom export FILE
```

## Credits and attribution

Omacosy's Theme Studio is built on **[Aether](https://github.com/omacom/aether)**
(MIT, © Bjarne Overli): the colour science, the extraction and palette
generators, the tone curve, the image pipeline and the template engine are
ports of Aether's Go and TypeScript. Ported functions carry a header naming
Aether, and so does the vendored Neovim template under
`config/theme-templates/`; the Zed and VS Code templates are JSON, which
cannot hold a comment.

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

- **Zed colours** — the generated `zed.json` loads, but its background reads
  much brighter than the desktop palette (reported 2026-10-11). The vendored
  template maps a role Omacosy resolves differently, so revisit its
  background/foreground mapping.
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
