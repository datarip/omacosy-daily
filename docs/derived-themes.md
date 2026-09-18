# Themes computed from your own wallpapers

This page describes the `custom` theme: a directory of your own images
where **every wallpaper is its own theme**. Its bar colour, pill colour,
icon colour and focus ring are computed from the picture rather than read
from a file.

It also covers the optional day and night switch, which follows the macOS
appearance.

- [1. The problem](#1-the-problem)
- [2. What a theme actually is](#2-what-a-theme-actually-is)
- [3. What the four shipped themes have in common](#3-what-the-four-shipped-themes-have-in-common)
- [4. How the colours are computed](#4-how-the-colours-are-computed)
- [5. How a computed theme reaches the screen](#5-how-a-computed-theme-reaches-the-screen)
- [6. Setting it up](#6-setting-it-up)
- [7. Configuration](#7-configuration)
- [8. Day and night](#8-day-and-night)
- [9. Command reference](#9-command-reference)
- [10. What it will not do](#10-what-it-will-not-do)
- [11. Troubleshooting](#11-troubleshooting)

---

## 1. The problem

omacosy ships four themes, each a directory of matching wallpapers with
one hand-picked colour scheme. `Super+Shift+T` moves between themes and
`Super+Shift+B` moves between the wallpapers inside one.

Four themes means four colour schemes. Every wallpaper inside
`gruvbox/backgrounds/` gets gruvbox's orange accent, whichever of them is
showing.

That works because those wallpapers were chosen to go with those colours.
It stops working the moment you use a picture of your own.

`theme-bg-next ~/Pictures/wallpapers/red-sunset.png` sets the wallpaper
and nothing else. The menu bar tints itself from the new picture, because
macOS tints the real menu bar from the desktop and omacosy follows it. The
pills, the icons and the focus ring keep the colours of whichever theme
you were on. Measured on a fully saturated red wallpaper: an orange-red
bar carrying osaka-jade's dark green pills. Legible, and wrong.

There is a second, quieter version of the same problem. Every shipped
wallpaper is dark along its top edge — measured, luminance 0.09 to 0.28.
The shipped label colour is near-white because of that. Use a bright
picture and the bar goes bright while the text stays near-white.

The fix is to stop reading the colours from a file and compute them from
the picture.

---

## 2. What a theme actually is

A theme is a directory. The shipped ones live in `themes/`:

```
themes/osaka-jade/
├── backgrounds/        the wallpapers
├── colors.toml         omarchy's 22-colour palette, for terminals
├── sketchybar.sh       the bar's colours
└── borders.sh          the focus ring's colour
```

Only `sketchybar.sh` and `borders.sh` are read by omacosy.
`colors.toml` is there for terminals that follow the omarchy convention;
nothing in this repo reads it.

Between them those two files declare nine keys. **They are five colours.**
In all four shipped themes:

```
BAR_COLOR   == BAR_BG_SOLID     duplicate name for the bar background
ICON_COLOR  == LABEL_COLOR      icons and text are one colour
ACCENT      == ACTIVE_COLOR     the focus ring IS the accent
```

So a computed theme has five numbers to produce:

| colour | where you see it |
| --- | --- |
| `BAR_BG_SOLID` | the menu bar background |
| `ITEM_BG` | the pill behind each item |
| `MUTED` | unfocused workspace numbers, the clock |
| `LABEL_COLOR` | text and icons |
| `ACCENT` | the focused workspace chip, and the app name's text |
| `ACTIVE_COLOR` | the focus ring, **computed separately**, see 4.6 |

`RED`, `GREEN` and `YELLOW` are also declared. They carry meaning — a low
battery has to read as red — so they are fixed and the wallpaper gets no
say in them.

---

## 3. What the four shipped themes have in common

The derivation is not invented. It reproduces the structure the shipped
themes already have, measured across all four.

**Each theme is one hue.** Converting every key to hue, saturation and
value:

| theme | hue range across all keys | spread | the one exception |
| --- | --- | --- | --- |
| tokyo-night | 221–235 | **14°** | none |
| catppuccin | 226–240 | 14° | accent at 267, +27° out |
| osaka-jade | 143–158 | 15° | label at 64, +79° out |
| gruvbox | 20–43 | 23° | bar is neutral grey |

One hue held to about fifteen degrees, with at most one deliberate escape.

**The lightness ladder is shared.** Reading value down the five colours:

| | catppuccin | gruvbox | osaka-jade | tokyo-night | shape |
| --- | --- | --- | --- | --- | --- |
| bar background | 0.18 | 0.16 | 0.11 | 0.15 | 0.15 |
| pill background | 0.27 | 0.24 | 0.22 | 0.26 | 0.25 |
| muted | 0.53 | 0.57 | 0.41 | 0.54 | 0.51 |
| label and icons | 0.96 | 0.92 | 0.77 | 0.96 | 0.90 |
| accent and ring | 0.97 | 1.00 | 0.58 | 0.97 | 0.88 |

Four themes, one ladder, agreeing to a few hundredths.

**The accent is the background, lifted.** Background to accent, the value
multiplier is 5.3, 6.3, 5.3 and 6.5. Saturation climbs a little.

So the four shipped themes are one structure instantiated four times: a
hue, a fixed lightness ladder, a saturation curve. That structure is
computable from a single colour.

---

## 4. How the colours are computed

`omacosy-derive` does the work. It is a small Swift binary built from
`helper/derive.swift`, with no dependencies beyond AppKit and ImageIO.

### 4.1 The base colour

The one input is the colour the menu bar takes from the wallpaper. omacosy
already computes this, in `seedStrip()` in `helper/bar.swift`, and has
done since before this feature existed. `omacosy-derive` uses the same
maths:

1. Decode the image with `CGImageSource`.
2. Work out the **centred fill crop** — macOS scales a wallpaper to fill,
   so the band under the bar is not simply the top of the file. The scale
   is the larger of the two ratios and the crop is centred.
3. Average the band the bar covers.
4. Push saturation by 1.3 and darken by 0.923.

Those last two numbers are fitted, not documented. Apple's real pipeline
is a private `CABackdropLayer` with a saturation factor and a tint, which
is not reachable from public API. They were measured over seven
wallpapers, twice each, by least squares: worst residual 9.1 per 255
against 18.5 for a raw average.

One detail is load-bearing. Every sample goes through
`.usingColorSpace(.sRGB)`. Skipping it reads raw component values and
lands up to **22 per 255** away — larger than the whole correction above.
A Python prototype of this code did skip it, via Pillow's
`convert("RGB")`, and produced a systematically darker base for every
image.

### 4.2 The picture's colour

The base colour is the right input for the **bar**, because the bar sits over
that strip. It is the wrong input for everything else. A thin band across the
top of a picture is usually sky, and it says nothing about the picture.

Measured on real failures:

| wallpaper | top strip | what you see |
| --- | --- | --- |
| Battersea power station | 179° near-grey | orange brick and sunset |
| purple line art on grey paper | 218° blue | purple |
| red sun over a teal sky | 186° teal | the red sun |
| moon over a tent | purple sky edge | the blue centre |

So a second pass reads the **whole** image on a 200x200 grid and finds the
hue the picture reads as. That is not the colour covering the most area: the
line-art page is 87% paper, and an average of it says blue.

The weight is **saturation x value cubed**. The cube was fitted, not chosen.
Moon-over-a-mountain is 61% dark purple by area and 7% bright blue glow, and
the eye calls it blue; linear and squared weighting both answer purple, and
cubed answers blue. On the lighthouse, whose hues are so spread that no
10-degree bucket holds more than 11%, cubed is also the first that answers
pink rather than one narrow blue band.

Hues go into 36 buckets smoothed over +/-20 degrees, so a hue spread across
several buckets is not beaten by a narrow one, and the winner is merged with
its neighbours by a circular mean. The function also returns a **share**: how
much of the total weight that winning window holds.

**Whether there is any colour at all is a separate test, and it is the older
one.** A greyscale image has a 90th percentile of saturation too, and it is
sensor noise, so the gate is: the top tenth by saturation x value, with a
floor of 0.12, must hold more than five samples. Inventing a hue when it does
not is what painted a black-and-white city yellow and a black-and-white
portrait pink.

Cost: one grid pass over an already-decoded image, about 40,000 samples.

### 4.3 The other four colours — two hues, for two jobs

**The pills, the muted text and the labels keep the BASE hue**, the same
one as the bar. The bar is the wallpaper showing through, so anything on
it in that hue family belongs there. Giving them the loud hue instead made
a beige picture wear blue pills and a pink one wear blue pills, and both
read as foreign objects pasted onto the desktop:

```
                bar hue          pill hue      apart
cat with ball   25  beige        195 blue       170 degrees
lighthouse      297 lilac        235 blue        62 degrees
```

**The ring takes the picture's hue.** It is the one element that has to be
seen rather than blend in, and it sits on a window, not on the bar.

**The pills normally take the bar's hue, and the picture overrules it only
when confident and nearby.** A 34-point strip can lie about a picture: on
moon-over-a-mountain it catches the purple edge of a sky whose body is blue,
and the mauve pills that produced read as foreign. So the picture wins when
its share is at least 65% **and** it is within 90 degrees of the strip. The
beige picture with a small blue jacket fails both tests, 49% and 170 degrees,
and keeps its beige pills. That guard is the reason the rule is safe.

From there: a ladder.

```
low   = no loud colour found    a greyscale picture
light = luminance   > 0.45      which way the ladder runs
```

**Use luminance, not value, to choose the ladder.** A saturated purple at
value 0.62 has luminance 0.27 and needs light text. Choosing on value
called it a light bar and painted near-black text on it.

Dark ladder — light text on a dark bar:

```
pill   = hue,  saturation × 0.85,       max(value + 0.11, 0.20)
muted  = hue,  0.22,                    0.48
label  = hue,  0.18,                    0.92
accent = picture hue,  max(0.45, loud sat × 1.15),   0.92
```

Light ladder — dark text on a light bar:

```
pill   = base hue,  base sat × 0.75,     value × 0.80
muted  = base hue,  min(base sat, 0.30), value × 0.42
label  = base hue,  min(base sat, 0.38), value × 0.16
accent = picture hue,  max(0.85, loud sat),  0.92
```

With no loud colour the saturations become 0 and the result is a neutral
grey scheme. **The accent then goes to the opposite end of the ladder** —
near-white on a dark bar, near-black on a light one. That is the most
visible thing available and it is honest about the picture having no
colour.

The accent keeps the base hue with **no shift**. Three of the four shipped
themes shift their accent negative from their wallpaper's hue and one
shifts positive, so zero is the centre.

### 4.4 Contrast is checked, not assumed

Ladder values alone are not enough. Every colour is then checked against
the surface it sits on and corrected until it passes.

| check | floor | why that number |
| --- | --- | --- |
| pill vs bar | 0.085 | the gap the shipped themes hold |
| label vs pill | 0.50 | the shipped gap is 0.56 to 0.64 |
| muted vs pill | 0.18 | the shipped gap is 0.19 to 0.24 |
| muted vs label | 0.18 | same |
| accent vs bar | 0.28 | so the accent reads against the bar |
| accent vs pill | 0.20 | the accent is drawn ON pills, see below |
| ring vs bar | 0.10 | a stroke on a window edge, see 4.6 |

Two failures during development shaped how this is done.

**A fixed offset cannot separate a pill from a bar.** On a wallpaper whose
base is value 1.00, adding 0.11 clamps and only saturation moves. The
result was a bright red bar carrying bright red pills. The correction now
**blends toward white or black**, which always has somewhere to go, in a
loop that stops only when the gap is real.

**Two corrections in a row fight each other.** `muted` has to clear both
the pill and the label. Separating it from one then the other made the
second undo the first whenever the gap was too small to hold a colour
between them. `muted` is now **placed at the midpoint** of pill and label,
which clears both by construction.

**The accent has to clear two surfaces, not one.** It fills the focused
workspace chip and it is the app name's text colour, so clearing the bar
says nothing about whether it can be read on a pill. Measured before this
floor existed, 33 of 65 wallpapers put the accent within 0.25 of its own
pill, the worst at 0.048 — an invisible ring and unreadable text.

Two `separate()` calls in a row cannot fix it, because the second lands
back inside the first band. `clearOf()` solves both at once: it finds the
luminance nearest the accent's own that sits outside **both** forbidden
bands and blends to it.

**The checks compare 8-bit values.** Satisfied in floating point and then
rounded to hex, three of the five floors fell back under by about 0.002.
Rounding costs up to 0.5/255 per channel, and luminance is a weighted sum,
so two colours can drift 0.004 apart. The floors are a promise about the
hex written to the file.

Measured over 66 images — the 19 shipped wallpapers and 47 personal ones —
all five hold with zero failures, tightest 0.0851 against a floor of
0.085. Two full runs produce byte-identical output.

### 4.6 The ring is not the accent

All four shipped themes write the same value into `sketchybar.sh`'s `ACCENT`
and `borders.sh`'s `ACTIVE_COLOR`. A computed theme does not, because they
are different surfaces with different jobs.

**The accent sits on the bar and on a pill.** It has to clear both, and those
two bands are what crush it dark: a pale bar leaves nowhere to go but down,
and down on a warm hue is brown. Measured on four reported wallpapers, the
accent's saturation was pinned at exactly 0.85 by a floor while the pictures
themselves were pastel:

| wallpaper | picture sat | accent sat | result |
| --- | --- | --- | --- |
| umbrellas | 0.20 | 0.85 | aggressive pure red |
| spider | 0.17 | 0.85 | dark brown |
| tiger | 0.68 | 0.85 | dark maroon at value 0.48 |

**The ring is drawn around a window, on the wallpaper.** It never touches the
bar. So it keeps the picture's own saturation, which lets a pastel picture
have a pastel ring, and it resolves **brighter, never darker** — darkening a
warm hue is exactly how the browns happened.

```
ring = picture hue,  min(0.95, max(0.45, picture sat x 1.20)),  0.86 light / 0.94 dark
       then lifted until it clears the bar by 0.10
```

Only the lift direction is special. Past a bar luminance of 0.75 there is no
room above, and climbing anyway washes the hue out toward white, so those
fall back to going down.

```
umbrellas   eb3523 -> db8279   dusty rose
clouds      ae301a -> e7ada3   soft salmon
tiger       7a122c -> e7728f   bright pink
spider      755f12 -> e5d69e   light golden
```

### 4.5 The fixture

Running the derivation on the first wallpaper of each shipped theme must
produce exactly:

| wallpaper | bar | pill | muted | label | accent | ring |
| --- | --- | --- | --- | --- | --- | --- |
| `catppuccin/1-totoro.webp` | `1d1d33` | `44314f` | `8a7c92` | `dbc0eb` | `c481eb` | `c884f0` | dark |
| `gruvbox/1-the-backwater.jpg` | `464c35` | `68604e` | `a59f93` | `ece0c5` | `ebc778` | `f0ca76` | dark |
| `osaka-jade/1-glowing-city.webp` | `003c30` | `0d5842` | `7f958f` | `c0ebde` | `00eba5` | `0cf0ac` | dark |
| `tokyo-night/0-winding-road.webp` | `7540ac` | `925dc8` | `bcb6c2` | `faf7fd` | `f189b2` | `f05290` | dark |

Reproducing a hand judgement is not the goal; producing a coherent scheme
is. Still, reading the whole image rather than the top strip moved three
of the four a long way toward the colour a designer chose:

```
              hand-picked   top strip    loud colour
catppuccin      cba6f7        30°     ->      1°
gruvbox         fe8019        51°     ->      9°
osaka-jade      509475        15°     ->      9°
tokyo-night     7aa2f7        49°     ->    122°
```

Gruvbox is the striking one: its accent is orange, its top strip is olive,
and the orange only appears once the whole picture is read. Tokyo-night
goes the other way — its wallpaper has a large magenta sky, so pink is a
fair reading of the picture and blue was the designer's taste.

---

## 5. How a computed theme reaches the screen

omacosy's bar and its focus-ring daemon watch `~/.config/omarchy/current`
with **kqueue**, a kernel service that wakes a program when a directory
changes. `theme-set` relies on it: swapping the `theme` symlink inside
that directory *is* the reload notification. There is no reload command.

kqueue on a directory fires when an entry is added, removed or renamed. A
write to a file one level deeper is not an entry change, and whether it
reaches the daemons was never established here.

So nothing depends on it. **Each wallpaper gets its own generated theme
directory**, named after a hash of the wallpaper's path:

```
~/.local/state/omacosy/derived/7ab23b1ea0c77153/
├── backgrounds/<image>   a symlink to your file
├── borders.sh            generated
└── sketchybar.sh         generated
```

Because the directory name changes with the wallpaper, re-pointing
`current/theme` at it is a real change and the daemons reload. That path
was exercised on 53 consecutive wallpaper changes without a miss.

The directories are built on first use and kept. `omacosy-custom-theme
rebuild` discards and regenerates them all.

Nothing is written into your wallpaper directory, and nothing is written
into the repo.

---

## 6. Setting it up

**Create a directory and put images in it.**

```sh
mkdir -p ~/Pictures/wallpapers
cp ~/Downloads/some-wallpapers/*.jpg ~/Pictures/wallpapers/
```

`install.sh` creates that directory for you, empty. There is no command to
run and no flag to set.

`Super+Shift+T` now reaches a fifth theme, `custom`, after the four
shipped ones. `Super+Shift+B` inside it moves through your images, and
every press recolours the bar, the pills, the icons and the focus ring.

Check what omacosy sees:

```sh
omacosy-custom-theme status
```

```
wallpaper directory : /Users/you/Pictures/wallpapers
  set by            : default (no ~/.config/omacosy/themes.conf, or no custom_wallpapers key)
  images            : 48
  state             : active — Super+Shift+T reaches it last
follow_appearance   : off
day                 : (unset)
night               : (unset)
derived themes      : 5 cached in /Users/you/.local/state/omacosy/derived
```

**An empty or missing directory hides the feature completely.** The cycle
stays four themes, `theme-set list` prints four names, and `theme-set
custom` is an unknown theme. No warning is printed, because a machine that
never opted in has nothing to warn about.

Accepted files: `jpg`, `jpeg`, `png`, `webp`, `heic`, `gif`.

---

## 7. Configuration

`~/.config/omacosy/themes.conf`. **The file is optional and is not created
for you.** It exists only to override the default directory or to
configure day and night. Same `key=value` format as `bar.conf` beside it.

```ini
# omacosy custom theme — all keys optional
custom_wallpapers=~/Pictures/wallpapers
day=gruvbox
night=osaka-jade/1-glowing-city.webp
follow_appearance=off
```

| key | default | what it does |
| --- | --- | --- |
| `custom_wallpapers` | `~/Pictures/wallpapers` | where your images live |
| `day` | unset | what to show in the light appearance |
| `night` | unset | what to show in the dark appearance |
| `follow_appearance` | `off` | whether to act on the appearance flip |

`custom_wallpapers` accepts `~`, `$HOME`, and any absolute path including
one on an external volume.

```sh
omacosy-custom-theme path /Volumes/Photos/walls
```

If the directory you point at does not exist or holds no images, the
custom theme is hidden. **It does not quietly fall back to
`~/Pictures/wallpapers`** — a directory you named on purpose should not be
silently replaced by a different one. `omacosy-custom-theme status` says
what it found.

---

## 8. Day and night

Two keys name what to show in each appearance. Either may be a **shipped
theme** or a **wallpaper of your own**, so this is not limited to the
custom theme.

Four forms, one rule each:

| you write | it means |
| --- | --- |
| `gruvbox` | that shipped theme, its first wallpaper |
| `gruvbox/2-flower-basket.webp` | that shipped theme, that wallpaper |
| `a_beach.jpg` | that file in your wallpaper directory |
| `/Volumes/Photos/dawn.jpg` | any absolute path |

A leading `/` is a path. A name matching a directory under `themes/` is a
shipped theme. `theme/file` is that theme's wallpaper. Anything else is a
filename in your directory.

```sh
omacosy-custom-theme day   gruvbox
omacosy-custom-theme night osaka-jade/1-glowing-city.webp
omacosy-custom-theme follow on
```

Check a value before relying on it:

```sh
omacosy-custom-theme resolve gruvbox/2-flower-basket.webp
# theme gruvbox, wallpaper /…/themes/gruvbox/backgrounds/2-flower-basket.webp

omacosy-appearance --status
# appearance        : dark
# follow_appearance : on
# would apply       : osaka-jade/1-glowing-city.webp -> theme osaka-jade, wallpaper …
```

### Why the appearance and not a clock

macOS already owns the schedule. With **System Settings → Appearance →
Auto**, macOS flips Light and Dark at sunrise and sunset using its own
location. Reading that flip means:

- one schedule on the machine instead of two
- it follows the seasons with no maintenance
- if you prefer fixed times, set them in System Settings and this follows

**No hours are stored in omacosy's config.**

Night Shift was the obvious candidate and is the wrong one. It is colour
temperature, not appearance, and its schedule lives undocumented in
`com.apple.CoreBrightness.plist` keyed by UID — a file that does not exist
until Night Shift is switched on.

One quirk worth knowing: `defaults read -g AppleInterfaceStyle` **exits
non-zero in Light mode**, because the key is absent rather than set to
`Light`. That is the documented shape of the setting.

### How it runs

`com.omacosy.appearance`, a launch agent that runs `omacosy-appearance`
once a minute. It exits immediately unless `follow_appearance=on`, so an
install that never configures it costs one `defaults read` a minute.

A poll rather than a resident notification observer: this does nothing on
almost every machine, and a script that exits in milliseconds costs less
than a process holding an observer.

**It acts only on a change of appearance.** Without that it would re-apply
every minute and stamp on a theme you picked by hand thirty seconds
earlier. Pick gruvbox at 3pm with `night=osaka-jade` and gruvbox stays
until the appearance actually flips.

Setting only one of the two keys is fine. A missing value for the other
half means that half does nothing.

---

## 9. Command reference

```
omacosy-custom-theme                   status (default)
omacosy-custom-theme status            the directory, image count, and config
omacosy-custom-theme path <dir>        point the custom theme somewhere else
omacosy-custom-theme day <spec>        what to show in the light appearance
omacosy-custom-theme night <spec>      what to show in the dark appearance
omacosy-custom-theme follow on|off     follow the macOS appearance
omacosy-custom-theme resolve <spec>    say what a spec would do, without doing it
omacosy-custom-theme apply <spec>      put a spec on screen now
omacosy-custom-theme rebuild           discard and regenerate every derived theme

omacosy-appearance                     act if the appearance changed
omacosy-appearance --force             act whatever the cached value says
omacosy-appearance --status            say what it would do, change nothing

omacosy-derive <image> <outdir>        write sketchybar.sh and borders.sh
omacosy-derive --print <image>...      print the palette, for fixtures
```

Three more exist for the scripts rather than for you: `dir`, `list` and
`current`, and `theme <image>`. They are the machine-readable half, so
that `theme-set`, `theme-next` and `theme-bg-next` do not each carry a
copy of the rules.

---

## 10. What it will not do

**It does not reproduce a hand-picked theme.** See the fixture in 4.5.
Gruvbox's wallpaper is olive and gruvbox is orange.

**A greyscale image gives a grey scheme.** When no pixel is loud enough to
vote, there is no hue to use, so the palette is neutral and the accent is
near-white on a dark bar or near-black on a light one. That is the rule for
black-and-white photographs, and it replaces an earlier version that
invented a vivid accent from a noise hue.

**A fully saturated bright wallpaper gives a flat scheme.** Everything
stays legible because the contrast floors hold, but a base at saturation
1.00 and value 1.00 leaves little room for the ladder to breathe.

**Animated GIFs do not animate.** macOS accepts one as a desktop picture
and paints a still frame. Measured, and confirmed in use: 38 frames at
40 ms, and not one desktop pixel moved over 1.7 s. They are accepted because a still frame is
a usable wallpaper and the colours come out fine.

**The four shipped themes are untouched.** They keep their hand-picked
files and their exact behaviour, including restarting at their first
wallpaper on a theme change. The custom theme differs there on purpose: it
**remembers** which wallpaper it was on, because a shipped theme holds 3
to 7 images and a folder of your own can hold hundreds.

---

## 11. Troubleshooting

**`Super+Shift+T` does not reach a fifth theme.**

```sh
omacosy-custom-theme status
```

`MISSING` or `empty` means the directory is not there or holds no images
of an accepted type. That is the whole condition.

**Colours do not change when I press `Super+Shift+B`.**

Check you are on the custom theme:

```sh
omacosy-custom-theme current     # should print: custom
```

On a shipped theme the wallpaper changes and the colours do not, which is
the original behaviour and is unchanged.

**A wallpaper looks wrong and I want it recomputed.**

```sh
omacosy-custom-theme rebuild
```

`rebuild` builds into a scratch directory, swaps it in, and then re-creates
the `current/theme` symlink so the bar and the borders daemon reload. That
last step is not optional: a derived directory is named after a hash of its
wallpaper's path, so a rebuild recreates it under the same name, the symlink
never changes, kqueue never fires, and the desktop keeps showing the palette
the daemons already had while the files on disk are new.

The generated directories are a cache keyed by path. Editing an image in
place is detected by its timestamp; replacing the file at the same path
with a different image is not, until a rebuild.

**Day and night do nothing.**

```sh
omacosy-appearance --status
```

Check `follow_appearance` is `on`, the relevant key is set, and macOS is
actually switching appearance — System Settings → Appearance → Auto.
Force one round to see it work:

```sh
omacosy-appearance --force
```

**I want to see what a colour scheme will look like before applying it.**

```sh
omacosy-derive --print ~/Pictures/wallpapers/*.jpg
```

Five hex values per line — bar, pill, muted, label, accent — then the
ladder and the filename.

**Start again from nothing.**

```sh
rm -rf ~/.local/state/omacosy/derived
rm -f  ~/.config/omacosy/themes.conf
```

Both are rebuilt or optional. Your wallpapers are never touched.
