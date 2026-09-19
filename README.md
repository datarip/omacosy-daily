# omacosy-daily

A personal build of [omacosy](https://github.com/paulsp94/omacosy) by
Paul Spende. It is the build I run every day. It adds fixes and
features, and I offer each one that fits upstream as a pull request.
[FORK.md](FORK.md) lists what it adds.

**It takes no contributions.** Open issues and pull requests at
[paulsp94/omacosy](https://github.com/paulsp94/omacosy).

omakase + macOS + cosy. An [omarchy](https://omarchy.org)-style setup
for macOS: tiling window management with a real Super key and
Hyprland's dwindle layout, a status bar built for it (bar, popups,
sliders and screen dimming in one process), focus follows mouse,
trackpad workspace swipes, a Mission-Control-style workspace overview
with live previews, focused-window border rings, and one theme switch
that covers everything down to the wallpaper. All of it installs from
this one repo.

![The omacosy desktop — themed bar over the osaka-jade wallpaper](docs/screenshots/desktop.jpg)

The whole environment idles at about **157MB** of memory. Numbers per
process in [Memory use](#memory-use).

Most of it is eight small binaries (Swift and C) built by the installer,
because several of the existing tools are broken on macOS 26. The
details are under [What's inside](#whats-inside).

## Where it runs

| Setup | Status |
| --- | --- |
| Apple silicon, macOS 27, one display with no notch | runs every day on a MacBook Air M1, under AeroSpace and under OmniWM |
| macOS 26 (Tahoe) | supported. Upstream omacosy is built and measured on macOS 26.3, and this build keeps that code |
| A MacBook with a notch | supported in the code, and not yet run on a notched MacBook. The six things it does differently are listed below |
| An external monitor, or two displays | supported in the code: each display gets its own nine workspaces. Upstream runs it docked to a second display. This build is tested on one display: the MacBook Air M1 drives only one external display, so two external displays need other hardware. A test on a Mac mini with two displays is in progress |
| An Intel Mac | not supported. `install.sh` builds the gesture daemon and the OmniWM client for Apple silicon only |
| `./uninstall.sh` | tested in a sandbox, for every starting state of `~/.zshrc`. Not yet run on a real Mac |

The first tests on a notched MacBook and of `uninstall.sh` use release
`v1.0.0`. Their results go into this section.

### On a MacBook with a notch

The code reads the notch height of each display from macOS, so a notched
built-in display and a flat external monitor each get their own layout.
On a notched display it does six things differently. Each one is written,
and each one waits for its first run on a notched MacBook:

1. The bar stays visible at rest. macOS already keeps the camera strip
   out of the space windows use, so hiding the bar there gains nothing.
   `autohide=auto` in `bar.conf` selects this.
2. The top gap for windows subtracts the notch height, so tiled windows
   start just below the bar and not one notch lower.
3. The media pill sits at the left edge, because the camera takes the
   centre of the strip.
4. The media title is cut at 20 characters, not 28.
5. At the top edge, right of the split, the bar steps aside so the
   native menu bar and its status icons can come through.
6. A fullscreen window starts below the camera strip, and the strip is
   painted black, so fullscreen looks complete.

## What install.sh changes on your Mac

Read this before you run it.

- It installs Homebrew if it is missing, then the packages in `Brewfile`:
  AeroSpace, Karabiner-Elements, Ghostty, Raycast, a Nerd Font and a
  set of command-line tools.
- It writes `~/.zshrc` as a short stub. A `~/.zshrc` you had before is
  backed up and copied to `~/.zshrc.local`, which keeps loading.
- It replaces `~/.config/karabiner/karabiner.json` to make Caps Lock the
  Super key. Karabiner-Elements runs as root; see
  [What it does not do](#what-it-does-not-do).
- It hides the native menu bar and turns off the four-finger swipe
  gestures of macOS, so the bar and the swipe daemon can take them.
- It builds its helpers into `~/.local/bin` and starts them as launch
  agents.

It records each change in a manifest, and `./uninstall.sh` reverses
exactly those changes.

## Upstream pull requests

The fixes this build offers upstream, and their state today.

<!-- upstream-prs:start -->
| PR | State | Title |
| --- | --- | --- |
| [#50](https://github.com/paulsp94/omacosy/pull/50) | OPEN | fix(wallpaper): a screen connected later takes the current theme's picture |
| [#49](https://github.com/paulsp94/omacosy/pull/49) | OPEN | fix(overview): the overview keeps an old theme's colour and wallpaper |
| [#47](https://github.com/paulsp94/omacosy/pull/47) | OPEN | feat(bar): the icon-only pills are squares |
| [#46](https://github.com/paulsp94/omacosy/pull/46) | OPEN | fix(aerospace): Super+F comes out identical to Super+N |
| [#45](https://github.com/paulsp94/omacosy/pull/45) | OPEN | fix(omniwm): Cmd+H leaves the workspace, and the Dock icon does not return to it |
| [#44](https://github.com/paulsp94/omacosy/pull/44) | OPEN | fix(spawn): a burst of launch chords opens one window, 13 s late |
| [#42](https://github.com/paulsp94/omacosy/pull/42) | OPEN | fix(install): keep a real ~/.zshrc working, and out of the clone |
| [#41](https://github.com/paulsp94/omacosy/pull/41) | MERGED | fix(uninstall): stop relinking ~/.zshrc to one machine's dotfiles path |
| [#40](https://github.com/paulsp94/omacosy/pull/40) | MERGED | fix(install): quote the app names written to apps.conf |
| [#39](https://github.com/paulsp94/omacosy/pull/39) | MERGED | fix(install): match Karabiner's current agent label |
| [#37](https://github.com/paulsp94/omacosy/pull/37) | OPEN | fix(gesture): the trackpad arms at once when OmniWM is the manager |
| [#36](https://github.com/paulsp94/omacosy/pull/36) | OPEN | fix(bar): a window-manager switch is noticed while the bar runs |
| [#35](https://github.com/paulsp94/omacosy/pull/35) | OPEN | fix(omniwm): one engine owns the four-finger swipe |
| [#34](https://github.com/paulsp94/omacosy/pull/34) | MERGED | fix(wm-switch): a config swap reaches the daemon that reads it |
| [#33](https://github.com/paulsp94/omacosy/pull/33) | MERGED | fix(gesture): the OmniWM swipe config points at another user's home |
| [#32](https://github.com/paulsp94/omacosy/pull/32) | OPEN | fix(omniwm): tiled windows keep a margin from the screen edges |
| [#31](https://github.com/paulsp94/omacosy/pull/31) | OPEN | feat(tiling): a workspace holding one window can fill the display |
| [#30](https://github.com/paulsp94/omacosy/pull/30) | OPEN | feat(bar): one command for autohide and the top gap it implies |
| [#29](https://github.com/paulsp94/omacosy/pull/29) | OPEN | feat(bar): split the top edge between this bar and the native one |
| [#28](https://github.com/paulsp94/omacosy/pull/28) | OPEN | fix(tiling): a read is a guess until it settles, and a prediction needs a live layout |
| [#27](https://github.com/paulsp94/omacosy/pull/27) | OPEN | fix(helper): split-hint stacks slots that are wider than tall |
| [#26](https://github.com/paulsp94/omacosy/pull/26) | OPEN | fix(aerospace): Super+Shift+F can only ever open one Finder window |
| [#25](https://github.com/paulsp94/omacosy/pull/25) | OPEN | fix(config): size the top gap from the display's safe-area inset |
| [#24](https://github.com/paulsp94/omacosy/pull/24) | OPEN | fix(bar): take the bar height from the menu bar macOS draws |
| [#23](https://github.com/paulsp94/omacosy/pull/23) | OPEN | fix(ffm): a full-display overlay stops hover focus everywhere |
| [#22](https://github.com/paulsp94/omacosy/pull/22) | MERGED | fix(theme): the first Super+Shift+B after a theme change does nothing |
| [#21](https://github.com/paulsp94/omacosy/pull/21) | OPEN | fix(bar): the activity chip keeps the old theme's accent |
<!-- upstream-prs:end -->

## Fresh Mac

```sh
git clone https://github.com/datarip/omacosy-daily.git ~/.local/share/omacosy &&
cd ~/.local/share/omacosy && ./install.sh
```

Upstream omacosy already in `~/.local/share/omacosy`? Run its
`./uninstall.sh`, delete that folder, then run the command above.

Then put your own apps and values in `~/.config/omacosy/settings.conf`
and run `omacosy-settings`. See [Your own settings](#your-own-settings).

The clone location matters. Configs are symlinked into the repo, and
macOS privacy (TCC) blocks launchd services from reading `~/Documents`,
`~/Desktop` and `~/Downloads`. If you clone there anyway, the installer
falls back to copying configs; that still works, but edits then need an
`install.sh` re-run to apply.

The installer is idempotent. It installs Homebrew if missing, runs
`brew bundle`, compiles the helper binaries, generates the AeroSpace
config from your app choices, symlinks configs (backing up anything it
would replace), hides the native menu bar, applies the default theme,
and starts the services.

See [Permissions](#permissions) for the grants it asks of you, what
each one is used for, and what breaks without it. Karabiner-Elements
also asks you to approve its driver extension.

## Updating

```sh
omacosy-update          # pull, then re-run the installer
omacosy-update --check  # just say whether there is anything new
```

`install.sh` rebuilds only the binaries whose sources changed and
restarts their agents, so an update is a pull plus a re-run, and this
command wraps both. It refuses a clone with local edits, and refuses
one whose branch has diverged, rather than deciding either for you.

Then run `omacosy-settings`. The installer resets the files your
settings go into, and `omacosy-settings` puts your values back.

There is no background update check. The bar makes exactly one network
call (the weather), and a daemon polling GitHub on a timer would
quietly make that two. Nothing here contacts the network unless you
run it.

## Permissions

A window manager needs broad permissions, so here is the whole list:
every grant, which binary asks, what it is used for, and what you lose
by refusing it. Everything is refusable; the parts that depend on a
grant hide themselves rather than half-work.

| Grant | Who asks | What it does | Without it |
|---|---|---|---|
| **Accessibility** | AeroSpace *or* OmniWM, `omacosy-gesture`, `omacosy-bar` (reads the focused app's menus for the app-pill popup), `omacosy-ffm` (AeroSpace mode only) | Move, resize and focus other apps' windows. This is the tiling itself, and it is the broadest permission here. | Nothing tiles. Not optional in practice. |
| **Input Monitoring** | Karabiner-Elements, `omacosy-gesture` (and OmniWM, under that option) | Karabiner reads keys to remap Caps Lock; `omacosy-gesture` reads raw trackpad contacts, because macOS 26 stopped carrying touch data in normal events. | No Super key, no swipe gestures. |
| **Screen Recording** | `omacosy-overview`, `omacosy-bar` | Overview captures a thumbnail per window for its cards, including windows the window manager has stashed offscreen, which a screenshot of the visible screen could not see. The bar samples the native menu bar's colour once, so an auto-hiding bar can paint it on the first frame instead of resolving a blur on every reveal. | Cards fall back to app icons and titles; the bar falls back to a live blur, which reveals more slowly and matches the menu bar less exactly. |
| **Bluetooth** | `omacosy-bar` | Reads adapter power and the paired-device list for the bluetooth pill and its menu. | The pill hides itself. |
| **Location** | `omacosy-bar` | Reads **only** the wi-fi network's name, which macOS classes as location data. No coordinate is ever requested; the authorisation itself is what unlocks `CWInterface.ssid()`. | The wi-fi popup's title row reads "wi-fi" instead of your network's name. Everything else is unaffected. |
| **Automation** | `omacosy-bar`, `theme-set` | Apple Events to **Spotify** (what is playing; play/pause/next from the media pill) and to **System Events** (sleep, lock and restart from the Apple menu; setting the wallpaper). | The media pill hides; those menu rows do nothing. |
| **Automation (Finder)** | `omacosy-finder-window` | Apple Events to **Finder**, to open a new Finder window on the current workspace (Super+Shift+F). macOS asks on the first press. | Super+Shift+F opens no window. |
| **Files and Folders** | `omacosy-bar` | Only if your clone lives in `~/Documents`, `~/Desktop` or `~/Downloads`. The bar reads its palette from the theme directory inside the repo, and macOS walls launchd agents off from those folders. | The bar **hangs at startup** waiting on the prompt. Clone to `~/.local/share/omacosy` and this never comes up. |

More on **Location**, because it sounds worse than it is: it buys
exactly one string. The bar requests authorisation and then reads
`ssid()`. It never asks for a position, holds no coordinate and starts
no location updates. Two things are required and neither alone is
enough: measured on macOS 26.3, an unbundled binary reads `nil` however
it is authorised, which is why the bar ships inside a minimal `.app`.
Refuse the grant and you lose the name, nothing else.

### What it does not do

- **No telemetry, no analytics, no crash reporting.** Nothing is sent
  anywhere about you or this machine.
- **One network call**, ever: `https://wttr.in/?format=j1` on a long
  timer, for the weather pill. wttr.in infers your city from the IP the
  request arrives on; no coordinates are gathered or sent, and the bar
  holds no location API. Delete the weather pill and nothing leaves the
  machine.
- **omacosy's own binaries never run as root.** `install.sh` uses no
  sudo, installs no LaunchDaemon, and every helper it builds runs as
  you, in your login session.
- **Karabiner-Elements does run as root, and you should know that
  before installing.** It is a Homebrew dependency here, purely to turn
  Caps Lock into Super. It ships a DriverKit system extension plus
  daemons that run as root (`Karabiner-VirtualHIDDevice-Daemon`,
  `Karabiner-Core-Service`); that is what the driver-extension approval
  during install is. It is the most privileged thing this repo puts on
  your Mac, and it is third-party. Skip it if that trade is wrong for
  you; you lose the Super key and keep everything else.
- **Nothing here reads your keystrokes.** No omacosy binary opens a
  keyboard event tap. Only Karabiner sees keys, which is inherent to
  remapping one. `omacosy-gesture`'s event tap is gesture-only and
  listen-only (`1 << NSEventTypeGesture`, `kCGEventTapOptionListenOnly`),
  so it cannot see or alter a keystroke. Debug logs
  (`/tmp/omacosy-*.log`) carry window titles, app names and workspace
  numbers, never input.

Grants are tied to a binary's code signature. With an Apple Development
identity present, `install.sh` signs every helper with a stable
identifier so rebuilds keep their grants; without one, macOS treats
each rebuild as a new app and you re-grant after every install.

## Your own settings

Your values live in one file outside the clone,
`~/.config/omacosy/settings.conf`. `install.sh` copies it from
`config/settings.template.conf` once, and never overwrites it.

| Setting | What it sets |
| --- | --- |
| `TERMINAL`, `BROWSER`, `MUSIC`, `MESSENGER` | the apps the launch chords open. The defaults are Ghostty, Safari, Spotify and Slack |
| `APP_WORKSPACE_RULES` | the workspace an app's windows open on |
| `APP_FLOAT_RULES` | the windows that float instead of tile, under OmniWM |
| `RING_RADIUS`, `WINDOW_CORNER` | the focus ring radius, and the radius macOS draws window corners with |
| `SERIALIZE_APP_SPAWNS` | one window at a time from a burst of presses on the music and messenger chords |

Apply the file after every install:

```sh
./install.sh && omacosy-settings
```

`install.sh` regenerates the window-manager configs on each run, and
`omacosy-settings` writes your values back into them. Set the apps in
`settings.conf`, not in `config/apps.local.conf`: `omacosy-settings`
rewrites that file. [docs/customising.md](docs/customising.md) explains
each setting, how to find an app's bundle id, and what survives a
re-install.

Your own shell config belongs in `~/.zshrc.local`. `install.sh` writes
`~/.zshrc` once, as a short stub that loads the repo's `zshrc`, and that
file loads `~/.zshrc.local`.

## Commands

The commands you run:

| Command | What it does |
| --- | --- |
| `omacosy-settings` | applies `~/.config/omacosy/settings.conf`. Run it after every install |
| `omacosy-update [--check]` | pulls this repo and runs `install.sh` again |
| `omacosy-wm-switch omniwm\|aerospace` | moves this Mac from one window manager to the other |
| `omacosy-toggle [on\|off]` | parks the whole setup without uninstalling it. No argument flips |
| `omacosy-bar-autohide on\|off\|auto\|status` | sets whether the bar hides at rest, and the top gap that goes with it |
| `omacosy-solo-fullscreen on\|off\|status` | a workspace with one tiled window fills the display. Off by default |
| `omacosy-window-corners [square\|round\|<radius>]` | sets the radius macOS draws window corners with. No argument shows it |
| `omacosy-harvest-zshrc` | moves the lines installers appended to `~/.zshrc` into `~/.zshrc.local` |
| `theme-set <name>` | switches the whole theme |
| `theme-next` | the next theme (Super+Shift+T) |
| `theme-bg-next [path]` | the next wallpaper of the theme, or the image you name (Super+Shift+B) |

The keys and the daemons run these. You do not need to run them:

| Command | Run by |
| --- | --- |
| `omacosy-ws` | Super+1..9, Super+Shift+1..9 and Super+Tab: the workspace slots of the focused display |
| `omacosy-cycle` | Alt+Tab, under AeroSpace: the windows of this workspace |
| `omacosy-float` | Super+S, under AeroSpace: the next floating window |
| `omacosy-layout` | Super+J, Super+- and Super+=, under AeroSpace: split direction and resize |
| `omacosy-spawn`, `omacosy-spawn-cmd` | the launch chords: one new window at a time |
| `omacosy-finder-window` | Super+Shift+F: a new Finder window on this workspace |
| `omacosy-focus-guard` | AeroSpace, on each workspace change: it undoes a switch that an app caused by activating itself |
| `omacosy-ws-collapse` | the bar, when a display is unplugged or plugged back in |
| `omacosy-karabiner-omniwm` | `omacosy-wm-switch` and `omacosy-settings`: the launch chords under OmniWM |

## What's inside

| Piece | Tool | Config |
|---|---|---|
| Tiling WM | [AeroSpace](https://github.com/nikitabobko/AeroSpace) *or* [OmniWM](https://github.com/BarutSRB/OmniWM) via `omacosy-wm-switch` | `config/aerospace/aerospace.template.toml`, `config/omniwm/settings.template.toml` |
| Super key | [Karabiner](https://karabiner-elements.pqrs.org) (Caps Lock → cmd+ctrl+alt) | `config/karabiner/` (copied, not symlinked — TCC) |
| Status bar, popups, shade | `omacosy-bar` (self-compiled launchd agent, one process draws all of it) | `helper/bar.swift`, `config/bar.conf` (live copy: `~/.config/omacosy/bar.conf`) |
| Window borders + fullscreen shroud | `omacosy-borders` (self-compiled launchd agent) | `helper/borders.swift`, `config/borders.conf` |
| Focus follows mouse | `omacosy-ffm` (self-compiled launchd agent; parked under OmniWM, whose native ffm takes over) | `helper/ffm.swift`, `config/ffm-ignore` |
| Trackpad gestures | `omacosy-gesture` (self-compiled launchd agent; engine absorbed from [aerospace-swipe](https://github.com/acsandmann/aerospace-swipe), MIT) | `helper/gesture/`, `config/gesture/` (live copy: `~/.config/omacosy/gesture.json`) |
| Workspace overview | `omacosy-overview` (self-compiled resident daemon) | `helper/overview.swift` |
| One window, whole display | `omacosy-solo` (self-compiled resident daemon; runs only while switched on) | `helper/solo.swift`, `bin/omacosy-solo-fullscreen` |
| Dwindle split direction | AeroSpace: `on-focus-changed` hook running `omacosy-helper split-hint`; OmniWM: native dwindle + a preselect in `omacosy-spawn` (omarchy's right/below insertion) | `config/aerospace/aerospace.template.toml`, `helper/main.swift` |
| Workspace / window navigation | `omacosy-ws`, `omacosy-cycle`, `omacosy-float`, `omacosy-wm-switch`; under OmniWM all of it rides `omacosy-omni`, a held-socket IPC client | `bin/`, `helper/gesture/omniwm.c` |
| Terminal look & spawn size | Ghostty (hidden titlebar; new windows spawn small so tiling never flashes full-screen) | `config/ghostty/config` |
| Park/restore the stack | `omacosy-toggle` | `bin/omacosy-toggle` |
| System glue | `omacosy-helper` (self-compiled) | `helper/main.swift` |
| Your settings | `omacosy-settings` | `config/settings.template.conf` (live copy: `~/.config/omacosy/settings.conf`) |
| Prompt | starship | `config/starship.toml` |
| Shell | zsh | `zsh/zshrc` + your `~/.zshrc.local` |
| CLI stack | fzf, eza, zoxide, ripgrep, bat, lazygit, btop | wired in `zsh/zshrc` |

Why so much of it is self-built:

- **AutoRaise** broke on macOS 26 (cooperative activation), so
  `omacosy-ffm` focuses windows through the same SkyLight calls
  AeroSpace uses.
- **aerospace-swipe** broke because CGEvent taps stopped carrying
  multi-touch data on macOS 26.3. We fixed it (raw MultitouchSupport
  frames) and offered the fixes upstream as
  [#29](https://github.com/acsandmann/aerospace-swipe/pull/29) and
  [#30](https://github.com/acsandmann/aerospace-swipe/pull/30); once
  the daemon had to serve both window managers and carried more of
  our patches than upstream commits, the engine moved in-tree as
  `omacosy-gesture` (MIT notice kept).
- **JankyBorders** keeps a bitmap per window and costs hundreds of MB.
  `omacosy-borders` strokes one CAShapeLayer that the WindowServer
  rasterizes, driven by SkyLight notifications for focus, move and
  resize, so the ring glides with drags without polling.
- **Mission Control** cannot see AeroSpace's virtual workspaces, so a
  workspace overview cannot be had any other way than
  `omacosy-overview` capturing them itself.
- **`omacosy-helper`** covers wallpaper setting (System Events
  scripting half-broke in macOS 14+), CoreAudio output switching,
  IOBluetooth control, cursor position, per-display notch detection,
  and the dwindle split hint.
- **`omacosy-bar`** holds the window model in memory and subscribes to
  the system's own publishers: SkyLight for window churn, IOBluetooth
  for connects, SCDynamicStore for the network, IOPS for battery,
  CoreAudio for volume, DisplayServices for brightness, Spotify's own
  broadcast for the track. It polls for nothing macOS announces; its
  only timers are the weather fetch and the clock. A workspace switch
  repaints in 2.5 ms because it asks no one anything; the shell bar it
  replaced took 164 ms to answer the same event.

## The bar

One process draws all of it: bar, popups and sliders are surfaces of
`helper/bar.swift`. Transparent bar, everything a flat radius-4 pill.
A popup stays open while the pointer is anywhere in the bar or the
popup, and closes when it is in neither. The bar hides itself when a
window takes the whole display, and comes back if you put the pointer
on the very top edge, so brightness and volume stay reachable mid-film
without leaving fullscreen. The climb happens only when a fullscreen
window actually covers the bar — otherwise the top edge belongs to the
auto-hidden native menu bar, which reveals ABOVE the bar and stays
clickable (app menus were unreachable before that fix). It drops back
behind everything when the pointer leaves. Under OmniWM the bar simply
stays visible in its reserved strip and never plays this game.

If the native menu bar ever gets stuck revealed over the bar (a
Tahoe bug, most often poked by a Focus mode's menu-bar icon),
`killall SystemUIServer` resets it.

### Hiding the bar, and the split top edge

`~/.config/omacosy/bar.conf` holds three settings. The bar reads the
file when it starts.

| Setting | Values | What it does |
| --- | --- | --- |
| `autohide` | `auto`, `on`, `off` | `auto` keeps the bar visible on a notched display, and hides it at rest on a display with no notch or on an external monitor |
| `split` | `0.0` to `1.0` | where the top edge divides, as a fraction of the display width. The left part belongs to this bar, the right part to the native menu bar |
| `slide` | milliseconds, or `off` | how long the bar takes to slide in and out, on a display where it hides |

Change `autohide` with `omacosy-bar-autohide on|off|auto`. It also sets
the top gap for windows, and restarts the bar. An edit by hand sets the
bar but not the gap.

### Workspace icons

You can set workspace icons in the optional
`~/.config/omacosy/workspace-icons.conf` file. Each non-comment line has one
workspace name, an equals sign, and either one Unicode scalar or a reverse-DNS
application bundle identifier.

```
1 = ★
14 = ◆

4 = com.apple.Safari
```

The bar first uses a configured icon. It then uses the icon of the sole app on
that workspace, and finally shows the workspace's last digit. Exact workspace
names win. In this example, workspace `14` uses `◆`, not the `4` shorthand.
The shorthand applies only to multi-digit, all-numeric workspace names ending
in `1` through `9` when they have no valid exact declaration.

The bar reads the file once at startup. To apply an edit, restart it with:

```sh
launchctl kickstart -k "gui/$(id -u)/com.omacosy.bar"
```

Malformed lines are logged and ignored. A well-formed bundle identifier that
does not resolve to an installed app is unavailable. It blocks shorthand for
that exact workspace, then the bar falls back to the sole app or the digit.
Image paths are unsupported because the bar resolves configured app icons at
startup and does no config-file or image-file I/O while it draws.

- **Apple menu**: the REAL one, read over Accessibility — About This
  Mac, System Settings, Recent Items (drills in, with app and
  file-type icons resolved locally since AX exposes none), Force Quit,
  the power verbs — plus omacosy's Next Theme at the bottom. Hidden
  hold-Option duplicates are collapsed; falls back to a hand-rolled
  list without the Accessibility grant.
- **App menus**: clicking the front-app pill drops that app's actual
  menu bar into a popup — File/Edit/… drill into their real items,
  nested submenus included, and clicking a leaf performs it directly
  via AXPress with no native menu ever appearing. Shortcuts sit
  right-aligned; enabled-state is not rendered because apps validate
  menu items only when a menu opens, so closed-menu reads lie. Menus
  taller than the screen scroll. The one thing the auto-hidden native
  bar still owned, gone.
- **Workspaces**: one segmented capsule per monitor showing only that
  monitor's workspaces; accent pill on the focused one; click to jump.
- **Media**: prev / play-pause / next + track title (Spotify). Centered
  on flat displays, left cluster on notched ones (per-display notch
  detection via `NSScreen.safeAreaInsets`), hidden when Spotify isn't
  running.
- **Bluetooth**: device menu (click to connect/disconnect), power
  toggle.
- **WiFi**: the pill is the icon alone; the popup names the network and
  adds ip and router, signal with a verdict, link rate and security
  generation, channel with its band and width. The name is in the popup
  because an SSID can be arbitrarily wide, and on a notched display a
  long one pushed the right cluster under the notch. The name needs the
  Location grant (see [Permissions](#permissions)).
- **Weather**: wttr.in, cached details popup.
- **Volume**: scroll adjusts, click opens slider + output-device menu,
  right-click mutes.
- **Brightness**: scroll adjusts, click opens a slider (DisplayServices,
  no deps). Scrolling past 0 keeps going: a **shade** dims the display
  below its hardware minimum by scaling gamma, so there is no overlay
  window in the z-order and screenshots come out normal. It survives
  sleep/wake and it reaches external displays, which have no backlight
  API. Gamma is reset when the setting process exits, so a crash or an
  uninstall restores the screen by itself.
- **Battery** / **Clock** (calendar popup) / **Activity** (floating
  btop).
- **Floats**: appears only while the workspace holds floating windows;
  click surfaces the next one.

## Keybindings — Super = hold Caps Lock

Karabiner remaps Caps Lock to `cmd+ctrl+alt` (a combo macOS never
uses), so omarchy's scheme works letter-for-letter without breaking
typing or app shortcuts. Caps Lock tapped alone is Escape.

| Chord | Action |
|---|---|
| **Navigation** | |
| `Super+1..9` | switch to this display's workspace N |
| `Super+tab` / `Super+shift+tab` | next / previous workspace, within this display's set |
| `Super+b` | back and forth between the last two workspaces |
| `Alt+tab` / `Alt+shift+tab` | cycle windows **on this workspace**, floats included |
| `Ctrl+Alt+tab` | cycle focus between displays |
| `Super+arrows` | focus the window in that direction |
| `Super+s` | surface the next floating window (and bring the cursor) |
| **Moving windows** | |
| `Super+shift+arrows` | AeroSpace: move the window in that direction. OmniWM: **swap** tiles (`ctrl+opt+shift+arrows` stacks into the neighbor as a group instead) |
| `Super+shift+1..9` | move the window to workspace N and follow it |
| `Super+shift+o` | throw the window to the same slot on the other display |
| `Super+shift+space` | throw the WHOLE workspace to the other display |
| **Layout** | |
| `Super+w` | close window |
| `Super+t` | toggle floating |
| `Super+j` | toggle split direction |
| `Super+-` / `Super+=` | resize |
| `Super+f` | fullscreen — on notched displays the camera strip is blacked out so it reads as true fullscreen, while the window stays in its workspace (swipes still reach it) |
| `Super+n` | native macOS fullscreen (a separate Space — outside the workspace model, avoid unless an app needs it) |
| `Super+r` | resize mode (`h/j/k/l`, `-`/`=`, `esc`) — AeroSpace only; OmniWM has no binding modes |
| `Super+shift+;` | service mode (`esc` reload, `r` flatten, `⌫` close others) |
| **Apps and system** | |
| `Super+enter` / `Super+shift+enter` | terminal / browser |
| `Super+space` | launcher (Raycast; the OmniWM option opens OmniWM's command palette instead) |
| `Super+shift+f` / `+m` / `+g` | files / music / messenger (set in `settings.conf`) |
| `Super+shift+t` | next theme |
| `Super+shift+b` | next wallpaper of the current theme |
| `Super+shift+l` | lock the screen |
| `Super+k` | keybinding cheatsheet (this table, rendered from the config) |

![The keybinding cheatsheet — every binding, parsed from aerospace.toml](docs/screenshots/cheatsheet.jpg)

Screenshots, clipboard and app switching stay macOS's own
(`Cmd+Shift+3/4/5`, `Cmd+C/V`, `Cmd+Tab`). `Alt+Tab` above is the
*window*-scoped switcher macOS lacks.

**On the modifier space.** omarchy layers `Super+Ctrl` and `Super+Alt`
on top of `Super`. This setup cannot: Super IS `cmd+ctrl+alt`, so those
modifiers are already spent and Shift is the only layer left, two
against omarchy's four. Bindings that would collide are re-homed by
mnemonic (lock is `Super+Shift+L`, not `Super+Ctrl+L`), and the
overflow lives in binding modes instead.

Each display owns an independent set of nine workspaces, omarchy style:
main holds 1–9, secondary holds 11–19. Same last digit means the same
slot, and the bar and overview render only the slot digit. `Super+N`
switches the focused monitor's slot N (via `omacosy-ws`);
`Super+Shift+N` moves the window to that slot; `Super+Shift+O` throws
the window to the same slot on the other monitor. Windows open on the
workspace you're on; nothing is auto-assigned by app.

**Unplugging folds the second display's workspaces into the first.**
AeroSpace parks 11–19 on the remaining display, but `Super+N` and
`Super+Tab` only match single-digit slots, so without help every window
on a secondary workspace would be stranded where no keybinding reaches
it. On a monitor-count change the bar runs `omacosy-ws-collapse`: each
occupied guest workspace empties into the lowest free 1–9 slot,
occupied slots are never touched, and every moved window is recorded
with its origin. Plug the display back in and they go home
individually, so anything you opened while undocked stays put.

## Themes

`theme-set <name>` switches everything at once: bar, borders, wallpaper
on every display, and any terminal that follows omarchy's
`~/.config/omarchy/current/theme` convention (the upstream author's does).
`Super+Shift+T` cycles.

Each theme ships omarchy's full wallpaper set. `Super+Shift+B` (or
`theme-bg-next`) cycles through them; `theme-bg-next <path>` sets any
image you like. Switching themes restarts at the theme's first
wallpaper.

Themes: `tokyo-night`, `catppuccin`, `gruvbox`, `osaka-jade`. Each
`themes/<name>/` holds `colors.toml` (omarchy's 22-color palette),
`sketchybar.sh` / `borders.sh` (bar and ring colors; the file keeps its
omarchy name and format, and the ring uses the theme accent, omarchy's
own convention), and `backgrounds/` (wallpapers from omarchy's
MIT-licensed theme packs). Copy a directory to add one.

### Your own wallpapers, with colors to match

Four themes means four color schemes, and they were chosen to suit their
own wallpapers. A picture of your own gets whichever scheme you were on,
which is how you end up with osaka-jade's dark green pills on a red bar.

Put images in `~/Pictures/wallpapers` and `Super+Shift+T` reaches a fifth
theme, `custom`, after the four. Inside it **every wallpaper is its own
theme**: `Super+Shift+B` moves to the next picture and recomputes the bar
color, the pill color, the icon color and the focus ring from it.

```sh
mkdir -p ~/Pictures/wallpapers      # install.sh already made it
cp ~/Downloads/walls/*.jpg ~/Pictures/wallpapers/
omacosy-custom-theme status
```

That is the whole setup. No config file, no flag. An empty or missing
directory hides the feature: the cycle stays four themes and nothing is
printed.

**How the colors are chosen.** The bar's own background keeps the
measurement omacosy already makes to match the real macOS menu bar — a
34-point strip across the top of the picture. Everything else reads the
**whole** image, because a strip across the top is usually sky and says
nothing about the picture: a power-station photo measures near-grey at the
top and orange everywhere else.

The picture's hue is its pixels weighted by saturation x value cubed. The
cube is fitted, not chosen — a moonlit scene that is 61% dark purple by
area and 7% bright blue glow reads as blue, and only the cube agrees.

**A pastel wallpaper gets a pastel theme, a saturated one gets neon.** The
accent's saturation follows the picture rather than a fixed floor: across a
48-image folder, pastel wallpapers average an accent saturation of 0.53 and
saturated ones 0.77.

**The bar and the focus ring always name the same color.** They differ only
in treatment — the ring keeps more of the picture's saturation and stays
brighter, because it is a stroke on a window rather than text on a pill.

Every color is then checked against the surface it sits on and corrected
until it passes. Seven contrast floors, taken from the gaps the four
shipped themes already hold, verified across 65 wallpapers with no
failures. The derivation is pure: the same image always yields the same
palette, so a cached theme and a fresh one cannot disagree.

Optionally, a day and a night theme that follow the macOS appearance, so
sunrise and sunset are macOS's schedule rather than a second one:

```sh
omacosy-custom-theme day   gruvbox
omacosy-custom-theme night osaka-jade/1-glowing-city.webp
omacosy-custom-theme follow on
```

Either may name a shipped theme, one of its wallpapers, or a file of your
own. Full manual: **[docs/derived-themes.md](docs/derived-themes.md)**.

## Tiling: dwindle

![Three terminals in a dwindle layout — README, git log and btop — accent border ring on the focused one](docs/screenshots/tiling.jpg)

AeroSpace natively inserts new windows as equal siblings, so three
windows become three columns. Hyprland's dwindle splits the focused
window along its own longer edge instead: a new window lands beside a
wide window and below a tall one. That is the omarchy feel, and on a
3440-wide display it is also the difference between a usable third
window and three narrow strips.

AeroSpace cannot express that rule. Its config language has no window
geometry; the format variables are ids, titles and container layouts,
with no width or height anywhere. So the direction is decided in code:
the `on-focus-changed` hook runs `omacosy-helper split-hint`, which
reads the newly focused window's frame and issues
`aerospace split horizontal` or `vertical` on it.

The timing is what matters. The hint lands before the next window
exists, so AeroSpace places that window correctly in its first pass.
An earlier version was a daemon that re-nested windows after AeroSpace
had already placed them, and you could see it: the screen laid out
twice, about 250ms apart. What remains now is the new window's own
first frame, which appears about 150ms before AeroSpace tiles it. No
window manager can place a window that does not exist yet.

Two implementation notes. `enable-normalization-flatten-containers` is
off, because it dissolves the very container `split` creates (AeroSpace
prints a warning saying so if you try). And the hint waits for the
window's frame to hold still before reading it, then names its window
with `--window-id` instead of trusting "the focused window". Both guard
against the same thing: a new window fires the hook too (it takes focus
on open), at a moment when its frame is still the app's default shape
and another window may grab focus before the hint lands. One hook
covers both hover and keyboard focus: AeroSpace notices the focus
`omacosy-ffm` moves, even though ffm moves it through SkyLight.

Manual control (Super+J flips, resize, float) works unchanged.

Floats get a rescue path, because macOS will not keep them on top:
z-order is per app, not per window, so a float sinks behind whichever
app you focus next, and pinning it would need a private call with SIP
off. Instead the bar grows a pill whenever the focused workspace holds
floats, and **Super+S** or a click on that pill surfaces the next one
and brings the cursor with it.

### One window, whole display

Opt-in, off by default: `omacosy-solo-fullscreen on`. A workspace holding a
single tiled window then shows it the way `Super+F` does: the whole display,
no outer gaps. A second window drops back to normal tiling, and closing down
to one goes full again. `omacosy-solo-fullscreen off` hands back every window
it took, and `status` says what it is holding.

`Super+F` keeps its meaning. The rule acts on a workspace's window COUNT, and
pressing `Super+F` changes no count, so a deliberate choice is never undone a
second later; the workspace returns to automatic at the next open or close. A
window counts as the rule's own only when `fullscreen on --fail-if-noop`
actually changed it, so a window you fullscreened by hand is never taken over
and never handed back. Floating windows, and the windows of hidden apps, do
not count — a workspace *showing* one window behaves as one window.

The rule runs in `omacosy-solo`, a small resident daemon under launchd,
rather than on a focus hook. It has to be resident: waking from sleep fires
no focus change and no window event at all, and only a live process receives
the sleep and wake notifications needed to put fullscreen back. It is also
its own process rather than part of `omacosy-bar`, because a Swift trap
cannot be caught and nothing about fullscreening a window should be able to
take the menu bar down. Switched off, the daemon exits and nothing runs.

Under OmniWM there is nothing to switch: its dwindle layout already gives a
lone window the frame its own `Super+F` uses (`singleWindowFit = "fill"`).

## Two window managers (OmniWM option, beta)

AeroSpace is the default. [OmniWM](https://github.com/BarutSRB/OmniWM)
is a newer, signed-and-notarized tiling WM with a native dwindle
layout — omacosy can run on either, and switching is one command:

```sh
omacosy-wm-switch omniwm      # installs OmniWM on first use, then
                              # switches with a guarded handover
omacosy-wm-switch aerospace   # the way back
```

The switch is deliberately paranoid: it snapshots your windows, waits
for you to grant OmniWM's permissions, and requires you to confirm
within 90 seconds that workspace switching works — anything else
reverts to AeroSpace automatically and puts your windows back.

Under OmniWM everything keeps working — bar, overview (with
type-to-search), gestures, keybindings, themes — and the dwindle
layout is native, so the split-hint machinery below simply isn't
needed there. What changes: OmniWM draws the focus border (themed by
theme-set), app-launching chords run through Karabiner rules that the
switch installs and removes, and Super+Space opens OmniWM's command
palette instead of Raycast.

Under OmniWM the plumbing changes shape: `Super+N`/`Hyper+N` route
through Karabiner into `omacosy-omni` (a held-socket IPC client) so
slots resolve on the display under your cursor — OmniWM's native
hotkeys are name-global and would always hit the main set — at the
cost of ~40 ms per chord. `Hyper+arrows` swap tiles; OmniWM's own
directional move *stacks* windows into a group, which stays available
on `ctrl+opt+shift+arrows`.

Honesty section: the upstream author daily-drives this option (0.6.4,
docked multi-monitor, each display running its own nine workspaces),
and this build runs it daily on one display. docs/omniwm-port.md
carries a ledger of upstream
quirks found while porting — read it before assuming a weird layout is
omacosy's fault. AeroSpace remains the longer-tested default.

## Focus follows mouse & swipes

Under the OmniWM option this daemon is parked: OmniWM's native
focus-follows-mouse (with warp-to-focus and hover-raise) replaces it.
Under AeroSpace, `omacosy-ffm`: hover focuses, with no raise over floating windows, so
floats stay in front. It is event-driven off mouse movement, so a
parked cursor never steals focus from a launching window. It never
changes focus during drags, and never through an always-on-top panel:
hovering a Touch ID prompt leaves focus exactly where it is instead of
falling through to the window beneath. Per-app opt-out lives in
`config/ffm-ignore` (omarchy's JetBrains-style exception).

4-finger swipes left/right switch workspaces on the display under the
cursor (native-Spaces semantics), with wrap-around, on any trackpad.
The system's own 4-finger gestures are disabled by `macos-defaults.sh`
so Mission Control never fights the daemon; `uninstall.sh` restores
them.

## Workspace overview

![Workspace overview — live preview cards over the zoomed-out wallpaper, chips for empty workspaces](docs/screenshots/overview.jpg)

4-finger **swipe up**: the wallpaper breathes in behind a dim wash and
every non-empty workspace of the cursor's monitor gets a card
(per-display Mission Control semantics), with live window previews
(ScreenCaptureKit, composed into the tile layout), app icons, and an
accent ring on the focused workspace. Click a card or press its digit
to jump; empty workspaces show as small chips, and digits work for them
too. **Swipe down**, Esc, or a backdrop click dismisses. It is a
resident daemon, so it opens instantly.

**Type to search** while it is open: a search pill filters cards to
matching window titles and apps as you type, `Enter` jumps to the
first hit, `Esc` clears the filter before it closes the overview.
Digits type into an active filter instead of switching, so numeric
titles stay reachable.

**Drag a card** to reorganize: the row makes room as you move, and the
drop slides everything between the old and new position over by one.
Workspaces cannot be renamed or resequenced in either WM (the name is
the position), so what actually moves is their windows, which means a
split layout inside a moved workspace comes back as a flat row. Dropping a
card on an empty chip moves that workspace there instead.

## Parking the setup

`omacosy-toggle off` returns to a vanilla Mac in one command (AeroSpace
stops managing, all daemons and the bar stop) without uninstalling;
`omacosy-toggle on` brings everything back. No argument flips.

## Memory use

About **157MB** of physical footprint (what Activity Monitor calls
Memory) across WM, bar, three background daemons, the gesture daemon and
Karabiner, measured by upstream, docked to a second display. Resident set size reads
~322MB, but RSS counts each process's share of the same shared system
frameworks more than once, so footprint is the number to compare.
(Measured in AeroSpace mode; OmniWM mode is a wash — its ~44MB WM
replaces AeroSpace plus the parked `omacosy-ffm`.)
Largest first:

| | footprint | RSS |
|---|---|---|
| `omacosy-overview` | 36MB | 46MB |
| `omacosy-bar` | 32MB | 55MB |
| AeroSpace | 24MB | 85MB |
| Karabiner (4 processes) | 24MB | 61MB |
| `omacosy-borders` | 19MB | 29MB |
| `omacosy-gesture` | 13MB | 22MB |
| `omacosy-ffm` | 10MB | 24MB |

On one display the same set measured ~155MB; the bar and the border
overlay each draw per-screen, and AeroSpace carries a second workspace
set. The figures move with uptime. `omacosy-overview` caches a
half-resolution capture per window shown, so it starts near 9MB and
settles around 37MB; it plateaus there rather than climbing, because
the cache is refiltered to the visible set on each open. AeroSpace
drifts the other way, reading higher the longer it runs. Packaging the
bar as an `.app` (which is what unlocks the wi-fi network name) cost
about 1MB; the bundle is a directory and an Info.plist, not a second
copy of anything.

## Back to a normal Mac

```sh
./uninstall.sh
```

Manifest-driven: `install.sh` records what this machine actually gained
(Homebrew packages that weren't already present, cloned repos, every
`defaults` key's prior value), and `uninstall.sh` removes and restores
exactly that. Tools and settings you had before omacosy are never
touched. Pre-manifest installs fall back to a conservative teardown
that leaves all Homebrew packages in place.

## License & credits

MIT (see `LICENSE`). This is a build of
[omacosy](https://github.com/paulsp94/omacosy) by Paul Spende, whose
copyright notice `LICENSE` keeps. Standing on: [omarchy](https://omarchy.org)
(the whole idea, plus MIT-licensed theme palettes and wallpapers),
[AeroSpace](https://github.com/nikitabobko/AeroSpace),
[Karabiner-Elements](https://karabiner-elements.pqrs.org),
[aerospace-swipe](https://github.com/acsandmann/aerospace-swipe) (MIT;
its gesture engine lives on here as `omacosy-gesture`, notice kept in
`helper/gesture/`).
