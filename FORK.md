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
| Gestures | the OmniWM swipe config no longer points at another user's home | `config/gesture/` |
| Gestures | the trackpad arms at once when OmniWM is the manager | `helper/gesture/` |

### Features, each also a pull request upstream

| Feature | How to use it |
| --- | --- |
| The top edge is split: the left part belongs to this bar, the right part to the native menu bar | `split` in `~/.config/omacosy/bar.conf` |
| One command sets bar auto-hide and the top gap that goes with it | `omacosy-bar-autohide on\|off\|auto` |
| A workspace holding one tiled window fills the display. Off by default | `omacosy-solo-fullscreen on\|off` |

### Only in this fork

| Change | Where |
| --- | --- |
| Your own values live in `~/.config/omacosy/settings.conf`, outside the clone. `omacosy-settings` applies them after every install | `bin/omacosy-settings`, `config/settings.template.conf` |
| `omacosy-window-corners` sets the radius macOS draws window corners with, and keeps the focus ring concentric | `bin/omacosy-window-corners` |
| `omacosy-spawn-cmd` opens one window at a time from a burst of presses on the music and messenger chords | `bin/omacosy-spawn-cmd` |
| `omacosy-harvest-zshrc` moves installer appends out of `~/.zshrc` into `~/.zshrc.local` | `bin/omacosy-harvest-zshrc` |
| `~/.zshrc` is a real stub file, not a link into the clone. An existing `~/.zshrc` is copied to `~/.zshrc.local` first, and `uninstall.sh` puts it back | `install.sh`, `uninstall.sh` |
| OmniWM's `settings.toml` is generated from `settings.template.toml`, so OmniWM's rewrites of it never make the clone dirty | `install.sh`, `config/omniwm/` |

## Your settings

| File | What it holds | Survives `install.sh` |
| --- | --- | --- |
| `~/.config/omacosy/settings.conf` | app choices, app-to-workspace rules, float rules, ring radius, window corners | yes |
| `~/.config/omacosy/bar.conf` | `autohide`, `split`, `slide` | yes |
| `~/.config/omacosy/solo-fullscreen` | its presence turns the one-window fullscreen on | yes |

`docs/customising.md` explains all three, and what `install.sh` resets.

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
