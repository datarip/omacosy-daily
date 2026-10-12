# This fork

A daily-driver build of
[paulsp94/omacosy](https://github.com/paulsp94/omacosy). It runs every
day on one machine: a MacBook Air M1 with macOS 27 and one 1440x900
display with no notch, under AeroSpace and OmniWM both.

Every fix and feature in the first two tables below is also offered
upstream as a pull request. The fork is where they run today. The pull
requests are where they can become everyone's. See
[those pull requests](https://github.com/paulsp94/omacosy/pulls?q=is%3Apr+author%3Adatarip).

## What it adds

### Fixes, each also a pull request upstream

| Area | Fix | Files |
| --- | --- | --- |
| Tiling | split-hint waits for a window frame to settle after a close, and predicts only from a live layout | `helper/main.swift` |
| Tiling | split-hint puts a slot that is wider than tall side by side, not stacked | `helper/main.swift` |
| Top gap | the gap comes from the display's safe-area inset, so a display with no notch reserves no notch | `helper/main.swift`, `install.sh`, `config/aerospace/` |
| Bar | the bar height comes from the menu bar macOS draws | `helper/bar.swift` |
| Bar | the activity chip takes the new theme's accent | `helper/bar.swift` |
| Bar | a window-manager switch is noticed while the bar runs | `helper/bar.swift` |
| Focus | a full-display overlay no longer stops focus-follows-mouse | `helper/ffm.swift` |
| Finder | Super+Shift+F opens a new Finder window on the current workspace | `bin/omacosy-finder-window` |
| Theme | the first Super+Shift+B after a theme change works | `bin/theme-bg-next` |
| OmniWM | tiled windows keep a margin from the screen edges | `config/omniwm/` |
| OmniWM | one engine owns the four-finger swipe | `bin/omacosy-wm-switch`, `config/omniwm/` |
| OmniWM | a config swap reaches the daemon that reads it | `bin/omacosy-wm-switch` |
| OmniWM | an update or a re-run of `install.sh` keeps OmniWM, and does not start AeroSpace beside it | `install.sh` |
| Overview | the overview follows a theme or wallpaper change, open or closed, and shows the desktop's wallpaper | `helper/overview.swift` |
| Gestures | the OmniWM swipe config no longer points at another user's home | `config/gesture/` |
| Gestures | the trackpad arms at once when OmniWM is the manager | `helper/gesture/` |
| Gestures | the four-finger swipe finds OmniWM's IPC socket after 0.7.5 moved it | `helper/gesture/omniwm.c` |
| Undock | the fold map survives an OmniWM restart, so folded windows still return to their workspace | `bin/omacosy-ws-collapse` |
| Undock | the restore never drops a live window's record when no window manager answers | `bin/omacosy-ws-collapse` |
| Install | a failed or interrupted install no longer leaves the OmniWM command chords wiped: they are restored right after Karabiner is reset | `install.sh` |

### Features, each also a pull request upstream

| Feature | How to use it |
| --- | --- |
| The top edge is split: the left part belongs to this bar, the right part to the native menu bar | `split` in `~/.config/omacosy/bar.conf` |
| One command sets bar auto-hide and the top gap that goes with it | `omacosy-bar-autohide on\|off\|auto` |
| A workspace holding one tiled window fills the display. Off by default | `omacosy-solo-fullscreen on\|off` |

### Only in this fork

| Change | Where |
| --- | --- |
| A fifth theme, `custom`, where **every wallpaper is its own theme**: drop images in `~/Pictures/wallpapers`, and `Super+Shift+B` recomputes the bar, pill, icon and ring colours from each picture. The hue comes from the whole image weighted by saturation x value cubed, a pastel wallpaper gets a pastel theme and a saturated one gets neon, the bar and the ring always name the same colour, dark pills take the picture's shadow hue, and WCAG contrast checks keep the bar text, the focused workspace number and the cheat sheet legible across 66 wallpapers. An empty directory hides it and the four shipped themes are untouched; the desktop always follows, the terminal only when `omacosy-term-auto-theme on` asks. [docs/derived-themes.md](docs/derived-themes.md) | `helper/derive.swift`, `bin/omacosy-custom-theme`, `bin/theme-set`, `bin/theme-next`, `bin/theme-bg-next` |
| Terminal auto-theme, off by default (`omacosy-term-auto-theme on`): while a custom theme is on screen the terminal and its apps follow the wallpaper: Ghostty (background, 16 colours, also in new windows), the Starship prompt, `ls` and `eza`, yazi, btop, Neovim (Aether's colourscheme through a linked plugin, transparent, the accent matching the bar), bat, delta and its line strips, fzf, lazygit, fastfetch, and the band behind tmux's bar. The 16 colours keep six fixed hues, so red stays red; delta's strips stay green and red on every wallpaper. btop, Neovim and tmux draw on the terminal's own background, so Ghostty's transparency shows. A stock theme is never changed: the generated files go and every app shows its own colours. Open apps change at once. `applier` in `term-auto-theme.conf` hands the palette to another tool instead, with `--clear` on a stock theme, so only one program ever writes the terminal config. `./install.sh --tui-tools` adds neovim, git-delta, tmux and fastfetch. Renamed from `omacosy-auto-theme` on 2026-10-09: the desktop always follows the wallpaper theme and only the terminal is optional; the old `off`/`on desktop-only` states, which gated the wallpaper list and the cycle, are gone. [docs/auto-theme.md](docs/auto-theme.md) | `helper/term-palette.swift`, `bin/omacosy-term-auto-theme`, `bin/omacosy-custom-theme`, `config/nvim/omacosy-theme.lua`, `config/starship-omacosy.template.toml`, `zsh/zshrc`, `install.sh` |
| Instant, synced theme switching: `Super+Shift+T`/`Super+Shift+B` draw the chosen wallpaper themselves in a desktop-level window in ~0.15 s and recolour the bar and the focus ring the moment it is on screen, so colours and wallpaper always arrive together; macOS's real wallpaper is applied underneath and the overlay is removed when it has caught up, with no visible flicker. The real wallpaper is asked for through **both** the public `NSWorkspace` API and System Events, so a switch still lands on a macOS build where one of them is broken (27.2 build 26B5101f rejects the API silently). No polling: the handoff is a filesystem event, and the only wait is one settle timer. [docs/theme-switching.md](docs/theme-switching.md) | `helper/overlay.swift`, `helper/main.swift`, `bin/omacosy-theme-switch`, `bin/omacosy-karabiner-omniwm`, `config/aerospace/aerospace.template.toml` |
| Settings: `Super`+`,` opens a cheatsheet-style modal with tabs — everyday options (window manager, corners, bar, fullscreen, terminal auto-theme, a global **Hide NSFW** switch), per-screen app→workspace assignment, a theme gallery that previews each theme's colours and applies on click, a **Wallpapers** tab that browses wallhaven.cc (search, sorting, category/purity chips, resolution, More Filters, downloads, bookmarks and bulk download), Storage (the wallpaper folder and a thumbnail-cache flush), API Keys and an update tab. Up/Down scroll a list, Left/Right move between tabs, the app picker highlights the row under the keyboard or pointer and applies it on Return, and a theme card takes an accent hover ring. It reads and writes the same commands and configs as the CLI, follows the theme palette (logo, lists and scrollbars included), and adds no policy of its own | `helper/dashboard.swift`, `bin/omacosy-dashboard`, `helper/assets/omacosy-logo.*` |
| yazi, the terminal file manager, on `Super+Shift+Y` under both window managers, with its previewers in the Brewfile | `bin/omacosy-files`, `Brewfile`, `config/aerospace/aerospace.template.toml`, `bin/omacosy-karabiner-omniwm` |
| A day and a night theme following the macOS appearance, so sunrise and sunset stay macOS's schedule. Either may name a shipped theme, one of its wallpapers, or a file of your own | `bin/omacosy-appearance`, `install.sh` |
| Your own values live in `~/.config/omacosy/settings.conf`, outside the clone. `omacosy-settings` applies them after every install | `bin/omacosy-settings`, `config/settings.template.conf` |
| `omacosy-window-corners` sets the radius macOS draws window corners with — the `Super+K` cheatsheet, the popup panel under a bar pill and the `Super+,` settings card (theme thumbnails included) follow it too, since borderless windows get no rounding from macOS (the bar pills themselves stay rounded) — and keeps the focus ring concentric | `bin/omacosy-window-corners`, `helper/bar.swift`, `helper/dashboard.swift` |
| `omacosy-spawn-cmd` opens one window at a time from a burst of presses on the music and messenger chords | `bin/omacosy-spawn-cmd` |
| `omacosy-harvest-zshrc` moves installer appends out of `~/.zshrc` into `~/.zshrc.local` | `bin/omacosy-harvest-zshrc` |
| The browser and mail chords follow the macOS default web browser and mail app, resolved from LaunchServices at each press, so a change in System Settings needs no reinstall. Set `BROWSER` or `EMAIL` to pin one app instead. `omacosy-open` opens any URL, file or scheme with its macOS default app | `bin/omacosy-browser`, `bin/omacosy-open`, `helper/main.swift` |
| `~/.zshrc` is a real stub file, not a link into the clone. An existing `~/.zshrc` is copied to `~/.zshrc.local` first, and `uninstall.sh` puts it back | `install.sh`, `uninstall.sh` |
| OmniWM's `settings.toml` is generated from `settings.template.toml`, so OmniWM's rewrites of it never make the clone dirty | `install.sh`, `config/omniwm/` |
| Both window-manager configs are **seeded once and never overwritten**. Your keybindings, and everything OmniWM writes through its own interface, survive every install. When the shipped default moves you are told, and given the path to diff against | `install.sh` (`seed_config`) |
| The focus ring hides when a layer-0 window in front of the focused window reaches its stroke, instead of painting over it. Awaits #51, then a pull request | `helper/borders.swift` |
| **Theme Studio**, in the settings dashboard's Themes tab: every wallpaper can become a saved theme (an *edition*), listed above its raw `Wallpaper #N` cell, and **Edit** / **Customize** opens an editor around the centre preview — **step 1, the Wallpaper Editor** on the left and **step 2, the Palette Builder** on the right, each with its **own Undo/Redo** (⌘Z / ⌘Y / ⇧⌘Z follow whichever surface you last edited). The picture editor is non-destructive and follows Aether's grouping: a filter recipe under **Tone** (Curves, then Light — Brightness, Contrast, Exposure, Shadows, Highlights, Clarity, Fade), **Color** (Saturation, Temperature, Tint, Hue Shift, Sepia, Invert, Posterize; then Palette Grade), **Detail** (Sharpen, Blur, Grain, Color Noise, Vignette, Oil Paint, Pixelate), **Geometry** (Transform — rotate/flip, crop with eight ratio presets and an interactive rect, resize with an aspect link) and **Snapshots** (presets — Aether's **18 built-ins**), with a **Strength** blend, the **Auto Enhance** buttons (Levels / Contrast / White Bal.), a **tone curve**, a **palette grade** (2-4 colour stops plus strength), and watch it live on the centre picture — **press and hold** to compare with the original. **Apply to Palette** renders the edit at full resolution through the engine into `studio/edits/`, then re-derives the palette from it; the **original file is never written**. The palette itself comes from the wallpaper (**Magic**, the same extraction the raw cells use) or one of 23 built-in schemes, plus presets, from-colour and gradient recipes; every slot edits by picker or hex and locks against a swap, with 12 adjustment sliders, a tone curve, undo/redo and accessibility badges. The semantic colours are editable like Aether's: shades pin, pinned shades survive palette swaps, and one click resets them. **Omacosy's own chrome is editable independently of the terminal palette**: a Background, Pill, Muted, Label, Accent, Ring and the red/green/yellow signals, each applied verbatim to the bar and the focus ring and read by no terminal writer, so recolouring Omacosy never moves the palette the terminal tools use. The editor **previews the theme live** as you transform it — its own background, text, pills and accent follow the draft — and the centre toolbar toggles mock **menu bar**, **terminal**, focus **ring** and a fake **cheat sheet** (the one surface that shows Muted as the descriptions, Label as the keys and Accent as the headings). **Save** and **Apply & Save** keep the editor open (only the ✕ or Esc closes it), so palettes can be saved, applied and compared in a row. An untouched Magic palette **is** the wallpaper's auto theme — the edition and the raw cell write byte-identical desktop files. **Save** / **Save As** write a self-contained record and the theme's own picture: the edited render (or the untouched original) is captured into `theme-media/`, the filter recipe is stored so reopening restores the sliders, curve and crop, and the original file is never written. **Apply & Save** does the same and switches the live desktop through `omacosy-theme-switch`. A **Blur Desktop** switch (Aether's `wallpaperBlur`) shows a heavy-blur copy on the desktop while the palette, the extraction and the editor keep the sharp original; **Save as New Wallpaper** was descoped at the user's request — saving a theme carries its wallpaper. A hover **trash** on any custom cell asks before removing: the wallpaper file goes to the Finder Trash, and the variations built from it can be deleted with it; an edition's trash removes just the record. A global **Hide NSFW** switch hides adult wallhaven results and anything downloaded from them, everywhere, without deleting anything. A saved theme can be **exported** as a shareable bundle — its record, a flat `colors.toml`, the terminal tools' generated configs, and loadable Zed, VS Code and Neovim files — and a theme can be **imported** from that JSON, a `colors.toml` or a base16 scheme; `theme export --bundle` and `theme import` are the CLI doors, with the editor buttons following. | `helper/dashboard.swift`, `helper/themecore.swift`, `config/theme-templates/` |

## Known limitations

- **A floating window (System Settings, a settings / About panel, a
  permission prompt) cannot be kept above a tiled window.** On OmniWM, mouse
  focus raises the hovered tile over the float, and no setting changes that;
  an external helper cannot reorder another app's window either (macOS needs
  Dock injection with SIP off). This needs a change in OmniWM — reported as
  [OmniNull/OmniWM#768](https://github.com/OmniNull/OmniWM/issues/768). Under AeroSpace
  the same wall is by design — see [docs/why-aerospace.md](docs/why-aerospace.md)
  — and `omacosy-float` (`Super+S`) surfaces a buried float. The focus ring no
  longer paints over a window that covers the focused one.
- **The wallpaper editor's live preview is best-effort.** All of Aether's
  filters are now built and grouped the Aether way, and the engine's
  `image render` is exact, but the in-dashboard preview runs through CoreImage
  and cannot match the engine's scalar maths in every corner. Grain and
  Color Noise are random (in Aether too), so the live preview leaves them out
  and only the engine's render applies them; Pixelate, Oil Paint, Clarity,
  Posterize and Fade are close approximations. Where they differ, the
  full-resolution render (Apply to Palette, and a saved theme's picture) is
  the record.

## Your settings

| File | What it holds | Survives `install.sh` |
| --- | --- | --- |
| `~/.config/omacosy/settings.conf` | app choices, app-to-workspace rules, float rules, ring radius, window corners | yes |
| `~/.config/omacosy/bar.conf` | `autohide`, `split`, `slide` | yes |
| `~/.config/omacosy/solo-fullscreen` | its presence turns the one-window fullscreen on | yes |
| `config/aerospace/aerospace.toml` | your AeroSpace keybindings and layout | yes — seeded once, then yours |
| `config/omniwm/settings.toml` | everything OmniWM saves for itself | yes — seeded once, then OmniWM's |

The last two are written once and then left alone. When a new version ships a
different default, `install.sh` keeps yours and prints the `diff` command to
compare against `~/.local/state/omacosy/<name>.shipped`.

`docs/customising.md` explains them, and what `install.sh` resets.

## Installing this instead of upstream

```sh
git clone https://github.com/datarip/omacosy-daily.git ~/.local/share/omacosy &&
cd ~/.local/share/omacosy && ./install.sh
```

Then edit `~/.config/omacosy/settings.conf` and run `omacosy-settings`.

## Going back to upstream

Run `./uninstall.sh` in the clone, then install upstream as its README
says. `uninstall.sh` removes what `install.sh` added. It keeps
`~/.config/omacosy/settings.conf` if you edited it.
