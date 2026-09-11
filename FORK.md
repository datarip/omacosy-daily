# This fork

omacosy with eight changes on top, maintained by datarip on a MacBook Air
M1 running macOS 27, a single 1440x900 built-in display with no notch, and
AeroSpace rather than OmniWM.

Upstream is [paulsp94/omacosy](https://github.com/paulsp94/omacosy). This
is a personal build, and every change in it is also offered upstream.
Those two things are not in tension: the fork is where they run today, the
pull requests are where they go to become everyone's.

## What it adds

Each row is one self-contained change on its own branch, cut from a fresh
`main` and kept to a single commit. None depends on another.

| # | Change | Files | Kind |
| --- | --- | --- | --- |
| 1 | split-hint reads a stale frame after a window closes | `helper/main.swift` | bug |
| 2 | split-hint predicts from a layout that no longer exists | `helper/main.swift` | bug |
| 3 | split-hint stacks slots that are wider than tall | `helper/main.swift` | bug |
| 4 | the top gap is sized from the display's safe-area inset | `config/`, `helper/main.swift`, `install.sh` | bug |
| 5 | the top edge is split between this bar and the native one | `helper/bar.swift`, `config/bar.conf` | feature, opt-in |
| 6 | a workspace holding one window goes fullscreen | `helper/bar.swift`, `config/fullscreen.conf` | feature, opt-in, **off by default** |
| 7 | a full-display overlay stops hover focus everywhere | `helper/ffm.swift` | bug |
| 8 | the bar height comes from the menu bar macOS draws | `helper/bar.swift` | bug |

Totals against upstream: 17 files, about 2,600 lines added.

### The four that are bugs in split direction and geometry

1, 2 and 3 are the same area: the hint that decides whether a new window
lands beside or below the last one. 1 fixes it reading a window frame that
AeroSpace has not re-expanded yet after a close. 2 fixes it predicting
from a layout that the close destroyed. 3 fixes the width multiplier
stacking slots on a narrow display when it should split them side by side.

4 replaces a fixed top gap with one measured from the display, so a
notchless screen stops reserving space for a notch it does not have.

8 does the same for the bar's own height, taking it from the menu bar
macOS actually draws instead of a constant.

### The two features, both opt-in

5 gives the left half of the top edge to this bar and leaves the right
half to the native one, so status items stay reachable while the bar
auto-hides. Configured in `config/bar.conf`.

6 gives a workspace holding exactly one tiled window the whole display
with no gaps, and tiles again when a second appears. Configured in
`config/fullscreen.conf`, and **off unless you turn it on**. It ignores
floating windows, the windows of hidden apps and notification banners, it
never undoes a manual Super+F, and it records and restores fullscreen
across sleep. That last part exists because AeroSpace re-detects every
window on waking and drops the state; see
`notes/aerospace-window-redetection-report.md` if you have it.

### The one that is not upstream's problem

7 is a fix for AeroSpace's focus-follows-mouse refusing to focus through a
window at a layer above 0. Some apps keep invisible full-display windows
there, which kills hover focus everywhere without any visible cause.

## personal/

Machine-specific tooling. **On the `mine` branch only**, never on a branch
that becomes a pull request. See `personal/README.md`. The important one is
`omacosy-personal-settings`, which puts personal configuration back after
`install.sh` overwrites it.

## Installing this instead of upstream

```sh
git clone -b mine https://github.com/datarip/omacosy.git ~/.local/share/omacosy &&
cd ~/.local/share/omacosy && ./install.sh
```

Both features are off until you turn them on:

```sh
# ~/.config/omacosy/bar.conf         autohide = auto | on | off
# ~/.config/omacosy/fullscreen.conf  solo = on | off
```

Neither config file is overwritten by a later `install.sh`, so your choice
survives updates.

## Going back to upstream

```sh
cd ~/.local/share/omacosy
git remote add upstream https://github.com/paulsp94/omacosy.git
git fetch upstream && git checkout -B main upstream/main
./install.sh
```

`uninstall.sh` removes everything, including both config files this fork
adds and the background subscriber that change 6 starts.

## Contributing back

The eight branches exist to be submitted, one pull request each, cut from
upstream `main` so each applies cleanly on its own. Two of them started as
issues and were invited by the maintainer before any code was written.

Running a personal build and contributing upstream are the same work here.
The fork is what proves the changes on a real machine every day; the pull
requests are what makes that worth anything to anyone else.
