# The terminal follows your wallpaper

Off by default. `omacosy-auto-theme on` turns on the custom theme, where every
wallpaper in `~/Pictures/wallpapers` is a theme of its own, and makes each
switch to one set the terminal's colors, the Starship prompt and the directory
color in `ls`, `eza` and yazi, the colours of bat, delta and fzf, btop's colors,
and Neovim's colourscheme.

```sh
omacosy-auto-theme            # status: switch, custom theme, applier, palette file
omacosy-auto-theme on
omacosy-auto-theme off
```

`theme-set` and `theme-bg-next` call `omacosy-auto-theme apply <label>` after
they repoint `~/.config/omarchy/current/theme`. Nothing else calls it.

**A stock theme is never changed.** When one of the shipped themes is on
screen, `apply` removes every generated file, resets the colors of open
terminals (OSC 104, 110, 111, 112) or runs `<applier> --clear <label>`, and
puts back the `EZA_COLORS`, `LS_COLORS` and `STARSHIP_CONFIG` a shell had
before. Each app shows its own colors.

## 1. Where the colors come from

`omacosy-term-palette <theme-dir> <out.env> [<label>]` reads the theme that is
on screen and writes one palette file.

**A shipped theme** (`themes/<name>/`) carries `colors.toml`, a designer's own
16 colors, and they are used as they are. `omacosy-auto-theme` never asks for
this: a stock theme leaves the terminal alone.

**A computed theme** (a wallpaper of your own) has no `colors.toml`, so the 16
colors are derived from the palette `omacosy-derive` already wrote:

- Six hues carry meaning and stay FIXED: red 29, green 142, yellow 95, blue
  258, magenta 328, cyan 210 degrees in OKLCH. Each is nudged at most 15
  degrees toward the accent, so the set belongs to the picture without red
  ceasing to be red. This is where `pywal` and its kin fail: filling all 16
  slots from the image makes a beige photograph print errors in beige.
- Their chroma follows the picture, so a pastel wallpaper gets a pastel set.
- Every one is then pushed in lightness until it reaches 4.5:1 against the
  background.
- The background itself is the theme's surface, pushed AWAY from the text until
  the text reads at 8:1. A terminal cannot be mid-tone: a dusty pink bar at
  relative luminance 0.19 would force every color to run to white or black.
  Which way it runs is the theme's own answer — light text means a dark
  terminal.

## 2. The palette file

`~/.config/omacosy/term-palette.env`, one `KEY='#rrggbb'` per line, meant to be
sourced by a shell.

| Key | What it is |
| --- | --- |
| `OMACOSY_THEME` | the theme's name, for a label |
| `OMACOSY_BG`, `OMACOSY_FG` | terminal background and foreground |
| `OMACOSY_CURSOR`, `OMACOSY_CURSOR_TEXT` | cursor and the text under it |
| `OMACOSY_SEL_BG`, `OMACOSY_SEL_FG` | selection |
| `OMACOSY_P0` … `OMACOSY_P15` | the 16 ANSI colors, by number |
| `OMACOSY_BLACK` … `OMACOSY_BR_WHITE` | the same 16, by name |
| `OMACOSY_ACCENT`, `OMACOSY_ALT` | the theme's accent, and a second one |
| `OMACOSY_OK`, `OMACOSY_WARN`, `OMACOSY_ERR`, `OMACOSY_INFO`, `OMACOSY_PEACH` | the roles a prompt uses, so a template says `err` and not `red` |
| `OMACOSY_MUTED` | dimmed text |
| `OMACOSY_IS_DARK` | 1 on a dark terminal, 0 on a light one |

No surface ramp is written. A consumer that wants one derives it from the
background, the foreground and `OMACOSY_MUTED`.

## 3. Who applies it

`~/.config/omacosy/auto-theme.conf` (`term.conf`, the file of the old name
`omacosy-auto-theme`, is read once and moved into it):

```
auto-theme = on | off         off by default
applier = <command>           empty: omacosy writes the config itself
```

**omacosy as the applier** writes three files, all under `~/.config/omacosy/`:

| File | Read by |
| --- | --- |
| `ghostty-theme.conf` | Ghostty, through `config-file = ?~/.config/omacosy/ghostty-theme.conf` in the shipped config |
| `starship.toml` | Starship, generated from `config/starship-omacosy.template.toml` plus the palette |
| `term-env.sh` | `zsh/zshrc`: `EZA_COLORS`, `LS_COLORS`, `BAT_THEME=ansi` (bat and delta then draw in the 16 colours), `STARSHIP_CONFIG`, and fzf's `--color` added to your own `FZF_DEFAULT_OPTS`. Your own values of all five are kept and put back on a stock theme |
| `~/.config/yazi/theme.toml` | yazi. Written in both modes, because yazi paints itself and no terminal palette reaches it |
| `~/.config/btop/themes/omacosy.theme` | btop, through `color_theme = "omacosy"` in `btop.conf`. Written in both modes, for the same reason |

The `?` makes Ghostty's include optional, so a machine that never turns this on
reads no such file. Your own config is read after it, so a color you set by hand
still wins.

**Another tool as the applier.** omacosy runs `<command> <palette-file>
<theme-label>` on a custom theme and `<command> --clear <theme-label>` on a
stock one, and writes no terminal config of its own, not even a stale file
an include could pick up. It still writes `term-env.sh` for the directory
color and `BAT_THEME`, which are nobody else's job, and it still repaints open
windows. The prompt and fzf's colours are left to the applier.

This exists to keep exactly ONE writer. Two programs writing Ghostty's config
would fight, and the winner would depend on the order the includes are read.

### yazi

yazi ignores the terminal's 16 colours: its default theme names its own blues
and cyans, so a themed terminal still showed a blue file list. The generated
`theme.toml` gives it the palette, and a directory — name and folder glyph —
wears the ACCENT, the colour the bar and the focus ring already name.

yazi MERGES a user theme over its defaults, so only the keys written here
change; the icon table's 650 entries for file types stay. Two things learned
from yazi's own error messages, kept so they are not learned twice:

- A filetype rule needs `url` or `mime`; `is` only qualifies one of them, and a
  directory is the url pattern `*/`. Without that, yazi refuses to start:
  "at least one of `url` or `mime` must be specified".
- The folder GLYPH is coloured by the icon table, not by the filetype rules.
  Colouring the rules alone leaves accent names next to blue icons.

A `theme.toml` of your own is never touched: the file is only written when it
is missing or when its first line says omacosy wrote it. `omacosy-auto-theme
off` deletes ours and leaves yours.

yazi reads its theme when it starts, so a window that is already open keeps
the old colours until you reopen it.

**Why not palette slot names, which would update live.** Tried, and it works:
a name means "the terminal's slot N", and repainting those slots is what this
script already does to every live window, so an open yazi recoloured on a theme
switch. Two things sank it. A slot is only the NEAREST of 16 — gruvbox's orange
accent lands on yellow — and the CHOICE is frozen at startup: a window opened
under gruvbox keeps drawing "yellow", which after a switch to catppuccin is
cream. The colour stayed live and stopped being the accent. The palette file
still carries `OMACOSY_ACCENT_ANSI`, the nearest slot by name, for a consumer
that would rather have live colour than an exact one.

### btop

btop paints itself from a theme file too. The CPU, temperature and memory
meters run from `OK` to `WARN` to `ERR`, because load has a meaning, as red
does in the terminal. The highlights take the accent. Box outlines, dividers
and meter backgrounds are the accent or the dimmed text, mixed toward the
background.

On a custom theme, `color_theme` in `btop.conf` is set to `omacosy`, and
btop's own value is kept in `~/.local/state/omacosy/btop-color-theme`. A
stock theme puts it back, but only while `btop.conf` still names `omacosy`: a
theme chosen in btop's menu since then stays. An `omacosy.theme` of your own,
without the first line omacosy writes, is never touched.

A running btop changes at once: `SIGUSR2` makes it read `btop.conf` and the
theme file again. That also matters when it quits, because btop writes
`btop.conf` on exit. After the reload, the value it writes is the new one.

## 4. Windows that are already open

A config file only reaches the next window, so `omacosy-auto-theme` writes the
colors to the tty of every shell as escape sequences (OSC 4, 10, 11 and 12).
The terminal consumes them, so a shell running Neovim or yazi is unharmed.

The prompt needs one more step. Starship builds its prompt string when it draws
a prompt, so the one on screen keeps the old colors. `omacosy-auto-theme` sends
SIGWINCH, and `zsh/zshrc` traps it, re-runs Starship's own precmd and redraws
the line.

Two details that cost an afternoon, kept here so they are not learned twice:

- A login shell is called `-zsh`, not `zsh`. A filter matching `zsh` or
  `/bin/zsh` finds nothing, and no window is repainted.
- Karabiner runs a keybinding with `PATH=/usr/bin:/bin`. A command in
  `~/.local/bin` is not found there, so anything looked up by name alone
  silently does nothing when the switch comes from the keyboard.

## 5. Neovim

`omacosy-auto-theme on` links `config/nvim/omacosy-theme.lua` into
`~/.config/nvim/lua/plugins/`, the folder a lazy.nvim config (LazyVim,
kickstart) loads plugins from. `off` removes the link. A file of your own with
that name is never replaced or removed. Without that folder nothing is linked,
and the palette file below is still there to use by hand.

**The palette.** On a custom theme omacosy writes
`~/.config/omacosy/nvim/palette.lua`. It returns one table: the theme name,
`dark`, the roles (`bg`, `fg`, `accent`, `alt`, `ok`, `warn`, `err`, `info`,
`peach`, `muted`), the 16 colours as `ansi`, and a `base16` table. Any config
can read it with `dofile()`.

**The colourscheme.** The plugin gives `base16` to `mini.base16`, which lazy.nvim
installs the first time. Functions wear the accent; strings, keywords and
constants keep the six fixed hues of section 1, so red stays red in the editor
too.

| base16 | from |
| --- | --- |
| base00 | background |
| base01 | background mixed 8% toward the text |
| base02 | selection background |
| base03 | `MUTED` (comments) |
| base04 | `MUTED` mixed halfway to the text |
| base05 | foreground |
| base06, base07 | the brightest of the 16 |
| base08, base0A, base0B, base0C, base0E | red, yellow, green, cyan, magenta |
| base09 | `PEACH` |
| base0D | `ACCENT` |
| base0F | `ALT` |

`terminal_color_0` to `terminal_color_15` are set too, so a `:terminal` matches
the one outside.

**Following a switch.** The plugin watches `~/.config/omacosy/nvim/`, the
folder and not the file, because omacosy replaces the file with a rename and
a watch on a file stops after the first rename. On a stock theme the file is
deleted, and the plugin puts back the colourscheme your config set at startup.
It applies its own at `VimEnter`, after your config, so that scheme is the one
it remembers.

**One plugin only.** Some terminal-theme tools ship a Neovim plugin that also
sets the colourscheme from a palette. Two such plugins fight over it, so keep
one of the two.

## 6. What it does not touch

tmux, and any other program with colours of its own. `omacosy-auto-theme off`
deletes the generated files; the next window reads your own colours again.
