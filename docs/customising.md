# Customising omacosy

This page tells you where your own settings go, and what `install.sh`
resets each time it runs.

## 1. What install.sh owns, and what is yours

`install.sh` regenerates or re-copies these files on every run. An edit
you make to one of them is gone after the next install.

| File | On every `install.sh` run |
| --- | --- |
| `~/.config/aerospace/aerospace.toml` | regenerated from `config/aerospace/aerospace.template.toml` |
| `~/.config/omniwm/settings.toml` | regenerated from `config/omniwm/settings.template.toml` |
| `~/.config/omacosy/borders.conf` | re-copied from `config/borders.conf` |
| `~/.config/omacosy/ffm-ignore`, `~/.config/omacosy/gesture.json` | re-copied from the clone |
| `~/.config/karabiner/karabiner.json` | re-copied from the clone |

These files are yours. `install.sh` creates them once, or never, and does
not overwrite them:

| File | What it holds |
| --- | --- |
| `~/.config/omacosy/settings.conf` | app choices, workspace rules, float rules, ring radius, window corners |
| `~/.config/omacosy/bar.conf` | bar auto-hide, where the top edge splits, the slide time |
| `~/.config/omacosy/solo-fullscreen` | its presence turns the one-window fullscreen on |
| `~/.config/omacosy/themes.conf` | the custom theme's wallpaper directory, and the day/night choices. Optional — absent means `~/Pictures/wallpapers` and no day/night |
| `~/.zshrc.local` | your shell config |

`omacosy-settings` reads `settings.conf` and writes your values back into
the files `install.sh` resets. Run it after every install:

```sh
./install.sh && omacosy-settings
```

Under OmniWM there is a second reason. `install.sh` starts AeroSpace and
resets the Karabiner rules that OmniWM's chords need. `omacosy-settings`
quits that AeroSpace and puts the rules back.

## 2. Find a bundle id

A workspace rule names an app by its bundle id. Ask macOS for it, with
the app's name as it shows in `/Applications`, without `.app`:

```sh
osascript -e 'id of app "Safari"'
# com.apple.Safari
```

## 3. Put your apps on your workspaces

`APP_WORKSPACE_RULES` in `settings.conf` holds one rule per line:
`<bundle id> <workspace>`. To send Visual Studio Code to workspace 4,
find its bundle id:

```sh
osascript -e 'id of app "Visual Studio Code"'
# com.microsoft.VSCode
```

Add a line to the list:

```sh
APP_WORKSPACE_RULES="
com.apple.Safari        1
com.apple.mail          2
com.apple.Terminal      3
com.microsoft.VSCode    4
"
```

Then apply it:

```sh
./install.sh && omacosy-settings
```

Under AeroSpace, `omacosy-settings` appends the rules to
`aerospace.toml` once. A changed list needs the fresh `aerospace.toml`
that `install.sh` writes. Under OmniWM, `omacosy-settings` alone adds a
new rule and corrects a changed one. It does not remove a rule. List the
rules with `omniwmctl query rules`, and remove one with
`omniwmctl rule remove <id>`.

A rule applies when a window opens. Windows that are already open stay
where they are.

`APP_FLOAT_RULES` lists the windows that float instead of tile, one per
line: a bundle id, or `title:` followed by part of the window title.
OmniWM reads this list. AeroSpace takes its float rules from its own
template.

`WORKSPACE_NAMES` gives a workspace a name of your own, one per line:
`<workspace> <name>`, the name holding spaces.

```sh
WORKSPACE_NAMES="
1    Work
2    Leisures
"
```

The name is a label, not a new identity: the workspace keeps its number,
so its slot chord (`Super+1`…`Super+9`), its remaining apps and the
digit it shows everywhere stay the same. The `Super+,` settings'
**Workspaces** tab edits the list in place — click the row's name or
its pencil and press **Save** — and that is the usual way to set it.
Under **AeroSpace** the name is drawn by Omacosy itself (the workspace
overview's cards, the Workspaces tab); AeroSpace's own workspaces have
no name other than the numeric one, so there is nothing else to write.
Under **OmniWM** the same list is applied to its built-in per-workspace
display name through `omniwmctl workspace rename`, so OmniWM's own
surfaces agree; `omacosy-settings` (after an install, or a switch to
OmniWM) re-applies it. Clearing a name in the Workspaces tab and saving
puts the workspace's number back everywhere.

The same file sets the apps the launch chords open: `TERMINAL`, `BROWSER`,
`EMAIL`, `MUSIC` and `MESSENGER`. Give the app's name, or leave it empty to
follow the system default where one exists. A changed app takes effect after
`./install.sh && omacosy-settings`.

### Pin an app, or follow the Mac's default

`BROWSER` and `EMAIL` are empty by default, and those two chords then open
**the Mac's default web browser** and **mail app**. `bin/omacosy-browser` and
`bin/omacosy-open` ask LaunchServices on every press, so changing the default
takes effect at the next press, with no reinstall. `omacosy-open` likewise
opens any URL, file or scheme (`omacosy-open mailto:you@example.com`) with
whatever app macOS would use for it.

Name an app (`BROWSER=Firefox`, `EMAIL=Thunderbird`) to **pin** that chord
instead — it then ignores the system default. To go back to following the
system, set the value back to `""` and run `omacosy-settings`; nothing is
baked at install, so no reinstall is needed.

To change the Mac's default itself:

- **Browser.** System Settings → Desktop & Dock → **Default web browser**
  (macOS 13 and later). Pick the app and the chord follows it.
- **Mail.** macOS has no System Settings pane for this, so set it in the mail
  app you want:
  - **Thunderbird:** Settings → General → **System Integration** → *Set as
    Default*; turn on "Always check if Thunderbird is the default client" so
    a later change is noticed.
  - **Apple Mail:** Mail → Settings → General → **Default email reader**, and
    choose the app. That list also shows third-party mail apps, so it is a
    second route to the same setting.

`TERMINAL`, `MUSIC` and `MESSENGER` have no macOS default to follow, so an
empty value there just keeps the shipped app from `config/apps.conf`.

### Choose the launcher

`LAUNCHER` in `settings.conf` is what `Super+Space` opens: `auto`, `raycast`,
`tinycast`, `alfred`, `omniwm` or `none`. `auto` is Raycast on AeroSpace and
OmniWM's own launcher on OmniWM; `omniwm` only works while OmniWM is the
window manager. `none` leaves the chord unbound, for an unsupported launcher
or a launcher's own hotkey. `omacosy-launcher status` shows the current
choice, and `omacosy-launcher set <value>` changes it at once and writes
`settings.conf`, so a later install keeps it.

`SERIALIZE_APP_SPAWNS="1"` sends the music and messenger chords through
`omacosy-spawn-cmd`, so a burst of presses opens one window at a time.

## 4. The focus ring and the window corners

The ring colour comes from the theme. Change it with `theme-set <name>`
or Super+Shift+T.

The ring radius is `RING_RADIUS` in `settings.conf`. The ring sits
concentric with a window when:

```
ring radius = window corner radius + gap + width / 2
```

`gap` and `width` are in `~/.config/omacosy/borders.conf`.

`WINDOW_CORNER` sets the radius macOS draws every window's corners with.
Empty leaves the macOS default alone. When it is set, the ring radius
follows it by the rule above, and `RING_RADIUS` is not used. To try a
value before you put it in `settings.conf`:

```sh
omacosy-window-corners square      # 0.1, square corners
omacosy-window-corners 8           # any radius from 0 to 64
omacosy-window-corners round       # back to the macOS default
omacosy-window-corners             # show what is set now
```

An app reads the corner radius when it opens a window. Relaunch an app to
see the new corners.

The `Super+K` cheatsheet, the popup panel under a bar pill and the whole
`Super+,` Settings dashboard — buttons, toggles, dropdowns, chips, the
palette swatches and the colour wells, the card itself and its theme
thumbnails — are drawn by Omacosy itself on borderless windows, so macOS's
own preference never reaches them. They read the same value and follow it
too, and they pick it up with no relaunch. The bar's own pills and the
workspace overview are left rounded by choice.

### How thick the borders are

`BORDER_WIDTH` in `settings.conf` is `small`, `medium` or `large` (1, 2 or
3 px). One value is shared by the focused-window ring, the `Super+K`
cheatsheet, the `Super+,` Settings dashboard and the Theme Studio editor,
so they always match — it is what the Options tab's **Borders** row (S/M/L)
writes. To change it from a terminal:

```sh
omacosy-window-corners --width 1   # small
omacosy-window-corners --width 2   # medium
omacosy-window-corners --width 3   # large, the default
```

`--width` also re-syncs the ring radius to the new number (the rule above).
The menu bar, its dropdown popups and the workspace overview keep their own
borders.

### The Ghostty window shadow

Ghostty draws its own macOS window shadow (`macos-window-shadow`, on by
default). Under a tiling window manager, and with a translucent Ghostty
theme, that shadow reads as a black rim around the window — most visible at
a `small` border width, because a 1 px ring sits flush and does not cover it.
`GHOSTTY_WINDOW_SHADOW` in `settings.conf` is `on` (Ghostty's default) or
`off`; `omacosy-ghostty-shadow on|off` changes it at once and records the line
in `settings.conf` for you, and `omacosy-ghostty-shadow` with no argument
shows the current state. `omacosy-settings` writes it into
`~/.config/omacosy/ghostty-settings.conf`, which the managed Ghostty config
includes. It applies the next time Ghostty launches. `""` leaves Ghostty's
default. The trade-off of `off` is the loss of the shadow that separates a
floating (un-tiled) Ghostty window from what is behind it.

### Whether the bar hides at rest

`AUTOHIDE` in `settings.conf` is `off` (the bar stays visible, the default),
`on` (it hides at rest), or `auto` (visible on a notched display, hidden on
the others). `omacosy-bar-autohide on|off|auto` changes it at once, with the
top gap for windows, and writes the line in `settings.conf` for you. The
next install applies it again, also after an uninstall.

### The wordmark intro

`LOGO_INTRO` in `settings.conf` names the effect the `Super+,` dashboard
plays over its wordmark when it opens: `laseretch`, `sweep`, `waves`,
`middleout`, `scattered`, `print`, `decrypt`, `errorcorrect`, `rain`,
`crumble`, `expand`, `highlight`, `colorshift`, `beams`, `slice`, `wipe` or
`spray`. Empty or `random` picks a
different one each open, never repeating the last — the same rotation idea
as omarchy.us, whose effect engine, ttfx (MIT), the vocabulary is a native
take on. Each run lasts about half a second to just over a second before it
lands on the crisp wordmark. Reduce Motion (System Settings → Accessibility →
Display) skips the intro and shows the wordmark at rest.

## 5. Keep your shell config

`install.sh` writes `~/.zshrc` once, as a short stub file that loads
omacosy's shell setup. Put your own config in `~/.zshrc.local`. The
omacosy shell setup loads it.

If you had a `~/.zshrc` before, `install.sh` copied it to
`~/.zshrc.local` and kept a backup of the original. If `~/.zshrc.local`
already existed, the old `~/.zshrc` was not merged into it. The install
said so, and named the backup.

Installers append to `~/.zshrc`. Those lines land in your own file, not
in the clone, and `install.sh` never rewrites them. To move them into
`~/.zshrc.local`:

```sh
omacosy-harvest-zshrc
```

The first run adds a marker line to the end of `~/.zshrc` and moves
nothing. After that, each run moves the lines below the marker. Lines
that were in `~/.zshrc` before the first run stay above the marker, so
run it once soon after the install. It backs up both files to
`~/.local/state/omacosy-harvest/` before it writes.

## 6. What survives a re-install

| File | `install.sh` | `omacosy-settings` |
| --- | --- | --- |
| `~/.config/omacosy/settings.conf` | kept | reads it |
| `~/.config/omacosy/bar.conf` | kept | reads `autohide`; `AUTOHIDE` in `settings.conf` wins |
| `~/.config/omacosy/solo-fullscreen` | kept | — |
| the `~/.zshrc` stub, and lines appended to it | kept | — |
| `~/.zshrc.local` | kept | — |
| `aerospace.toml` | regenerated | writes your values back |
| OmniWM `settings.toml` | regenerated | writes your rules and workspace names back, under OmniWM |
| `~/.config/omacosy/borders.conf` | re-copied | writes the ring radius and border width back |
| `config/apps.local.conf` in the clone | read | rewritten from `settings.conf` |
| the window corner preference | kept | set from `WINDOW_CORNER` |

A hand edit to a regenerated or re-copied file is lost at the next
install. Put the value in `settings.conf` instead.

## 7. Undo all of it

```sh
./uninstall.sh
```

It removes what `install.sh` added, and restores what it replaced:

- the commands in `~/.local/bin`, the launch agents and the configs;
- `~/.zshrc`: the stub is removed and your earlier `~/.zshrc` comes
  back. If you added lines to the stub, it is kept as a backup;
- `~/.zshrc.local`: removed only if `install.sh` made it and it is still
  an exact copy of your restored `~/.zshrc`. Otherwise it is kept;
- `~/.config/omacosy/settings.conf`: removed only if `install.sh` made
  it and you never edited it;
- the Homebrew packages that `install.sh` added. Packages you had before
  stay;
- the window corners: both corner keys are deleted, so macOS draws its
  own corners again. An app shows them after a relaunch.
