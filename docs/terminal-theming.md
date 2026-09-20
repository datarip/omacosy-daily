# The terminal follows the theme

Off by default. `omacosy-term-sync on` makes every theme and wallpaper switch
set the terminal's colors, the Starship prompt and the directory color in
`ls`, `eza` and yazi.

```sh
omacosy-term-sync            # status: theming, applier, palette file
omacosy-term-sync on
omacosy-term-sync off
```

`theme-set` and `theme-bg-next` call `omacosy-term-sync apply <label>` after
they repoint `~/.config/omarchy/current/theme`. Nothing else calls it.

## 1. Where the colors come from

`omacosy-term-palette <theme-dir> <out.env> [<label>]` reads the theme that is
on screen and writes one palette file.

**A shipped theme** (`themes/<name>/`) carries `colors.toml`, a designer's own
16 colors, and they are used as they are. A theme named gruvbox must give the
gruvbox terminal, not our reading of its wallpaper.

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

`~/.config/omacosy/term.conf`:

```
theming = on | off            off by default
applier = <command>           empty: omacosy writes the config itself
```

**omacosy as the applier** writes three files, all under `~/.config/omacosy/`:

| File | Read by |
| --- | --- |
| `ghostty-theme.conf` | Ghostty, through `config-file = ?~/.config/omacosy/ghostty-theme.conf` in the shipped config |
| `starship.toml` | Starship, generated from `config/starship-omacosy.template.toml` plus the palette |
| `term-env.sh` | `zsh/zshrc`: `EZA_COLORS`, `LS_COLORS`, and `STARSHIP_CONFIG` |
| `~/.config/yazi/theme.toml` | yazi. Written in both modes, because yazi paints itself and no terminal palette reaches it |

The `?` makes Ghostty's include optional, so a machine that never turns this on
reads no such file. Your own config is read after it, so a color you set by hand
still wins.

**Another tool as the applier.** omacosy runs `<command> <palette-file>
<theme-label>` and writes no terminal config of its own, not even a stale file
an include could pick up. It still writes `term-env.sh` for the directory
color, which is nobody else's job, and it still repaints open windows.

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
is missing or when its first line says omacosy wrote it. `omacosy-term-sync
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

## 4. Windows that are already open

A config file only reaches the next window, so `omacosy-term-sync` writes the
colors to the tty of every shell as escape sequences (OSC 4, 10, 11 and 12).
The terminal consumes them, so a shell running Neovim or yazi is unharmed.

The prompt needs one more step. Starship builds its prompt string when it draws
a prompt, so the one on screen keeps the old colors. `omacosy-term-sync` sends
SIGWINCH, and `zsh/zshrc` traps it, re-runs Starship's own precmd and redraws
the line.

Two details that cost an afternoon, kept here so they are not learned twice:

- A login shell is called `-zsh`, not `zsh`. A filter matching `zsh` or
  `/bin/zsh` finds nothing, and no window is repainted.
- Karabiner runs a keybinding with `PATH=/usr/bin:/bin`. A command in
  `~/.local/bin` is not found there, so anything looked up by name alone
  silently does nothing when the switch comes from the keyboard.

## 5. What it does not touch

Neovim, tmux, and any program with colours of its own. `omacosy-term-sync off`
deletes the generated files; the next window reads your own colours again.

## 6. Not done: Neovim

Undecided, written down so the options are not rediscovered. Nothing here is
implemented; a Neovim on a machine without another tool keeps its own
colourscheme. In increasing order of work:

**Terminal colours only.** Set `terminal_color_0` to `terminal_color_15` from
the palette, so a `:terminal` inside Neovim matches the outside one. The
editor's colourscheme is untouched. Small, safe, and it fixes the one place
where the mismatch is obvious.

**A generated palette file, and nothing else.** Write `palette.lua` next to the
other generated files and document it. Whoever wants it reads it from their own
config: `dofile(vim.fn.expand("~/.config/omacosy/palette.lua"))`, then uses the
values however they like — pick a colourscheme by name, tint a statusline, set
the terminal colours above. No plugin, no assumption about how Neovim is set
up, which is the point: LazyVim, kickstart and a hand-written config all load
things differently.

**A colourscheme built from the palette.** A full theme generated per wallpaper.
This is the one to be careful with: sixteen colours plus an accent rarely make
a good editor theme, and syntax highlighting needs more distinctions than a
terminal does. A middle road is to pick the NEAREST existing colourscheme
instead of generating one, the way `OMACOSY_ACCENT_ANSI` picks the nearest
palette slot.

Whatever is chosen, the refresh problem is already solved for it: a running
Neovim would reload on the same signal the shells use, if its config asks for
that.
