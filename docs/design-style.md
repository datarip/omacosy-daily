# Design style

How the settings dashboard and the Theme Studio are laid out and styled, so a
new control or block matches what is already there.

**The code is the source of truth.** The numbers below live in
`helper/dashboard.swift` (and `helper/bar.swift` for the shared helpers); this
page explains the system and the reasoning behind it. If a value here and the
code ever disagree, the code wins — correct this page, do not change the code
to match it.

## The one rhythm

Every vertical gap is one of five numbers, all built on 4. A new block picks
the token that matches its role; it does not invent a number.

| Token | Value | Between |
| --- | --- | --- |
| outer padding | 12 | the top of a scroll body and its first element, and its last element and the bottom |
| heading → content | 24 | an accent heading and the first control under it |
| framed heading → content | 30 | a heading and the first row of a **framed** block — 24 to the frame edge plus the frame's 6 pt inner padding |
| section → section | 24 | the last row of one section and the next section's heading (a framed section sits 6 pt below its last row, so the visible space before the next heading is 18) |
| sub-gap | 12 | a control and its own caption, or two buttons on one line |
| hairline → heading | 10 | a rule and the heading it introduces |

## Panels and columns

- The Theme Editor is **two columns of the same width** around the centre
  preview: the Wallpaper Editor (step 1) on the left, the Palette Builder
  (step 2) on the right. Both use the same inner padding (`insetL` = `insetR` =
  12) and the same scroll gap (12), so a matching element — the tone curve, a
  slider row — comes out the same width in both.
- A scroll body's content width is always `bounds.width - insets`. Nothing
  hardcodes a pixel width; that is what keeps the two columns in step. The
  shared column width is `columnW` in `ThemeEditorView`.

## Framed blocks

A group of similar rows is a rounded frame: the picture editor's
`Light`/`Color`/`Detail`, the palette's `Adjustments` sliders and its
`Accessibility` table.

- corner radius `windowCornerRadius(8)`, a 1 px border in `palette.muted` at
  0.4 alpha;
- the frame spans `insetL … insetL + contentW` — the same left and right edges
  as the headings and controls above it;
- the rows are inset **10** inside it, so no label or value touches the line;
- heading **+24** to the frame edge, **+30** to the first row.

## Typography

One family, `JetBrainsMono Nerd Font`, always through the `nerdFont(face,
size)` helper. The size carries the meaning — reuse these, do not add new
ones:

| Role | Face / size | Colour |
| --- | --- | --- |
| panel title (the numbered step header) | Bold 13 | `palette.accent` |
| window title (the theme name) | Bold 14 | `palette.label` |
| tab label | Bold 13 | accent when active, else label |
| dashboard tab's first content title | Bold 13 | `palette.accent` |
| section heading | Bold 12 | `palette.accent` |
| sub-setting heading | Bold 11 | `palette.label` |
| sub-group label (e.g. `ROTATE & FLIP`) | Bold 10 | `palette.muted` |
| row / slider label | Regular 11 | `palette.label` |
| value, right-aligned | Regular 11 | `palette.label` |
| caption, summary, column header | Regular 9–10 | `palette.muted` |

Every 12 pt heading is accent, in both panels alike, so the editor reads as
one system. A sub-setting drops to Bold 11 label; a sub-group to Bold 10
muted.

## Roles, not colours

Draw with the theme roles, never a literal colour: `palette.accent` (headings,
the active choice, the ON state), `palette.label` (primary text),
`palette.muted` (secondary text, hairlines, frame borders), `palette.itemBG`
and `palette.barBG` (surfaces). A theme switch repaints every surface, so a
literal colour would stay wrong after it.

## Slider rows

`AdjustmentSliderView` is the one slider, used by both panels. It is a label
column 88 pt (left-aligned), a flexible track, then a value column 34 pt
(right-aligned), 26 pt tall. Every slider row — standalone or inside a frame —
uses the same frame (`x: insetL + 10, w: contentW - 20`), so the labels, the
tracks and the values line up down the column and across the two columns.

## Segmented controls

`SegmentedView` is one control with two shapes, both chosen from the
window-corner setting (`windowCornerRadius`) so it always agrees with the
window it sits in:

- **Rounded** — one `palette.itemBG` track at 0.55, corner radius
  `windowCornerRadius(8)`, with a single 1 px `palette.accent` outline at 0.30
  around the group, and only the active segment filled: a
  `windowCornerRadius(6)` pill in `palette.accent` at 0.9. The unselected
  cells are plain text — the cells are never boxed individually.
- **Square** — no track and no group outline. Each cell is its own button: a
  full-height box with its own fill and border. The active cell is
  `palette.accent` at 0.9 for both fill and border, so it reads as one solid
  button; the others are `palette.itemBG` at 0.55 with a 1 px `palette.muted`
  border at 0.35. The group never reads as a container.

Height 28, 12 pt text: the active segment Bold in `palette.barBG`, the rest
Regular in `palette.label`.

## Buttons

`ButtonView` dims (a black 0.22 overlay) for 0.12 s on every press, so an
instant action still shows a response. Work that is not instant keeps the
button in its muted `busy` state with a `busyTitle` until the background work
finishes, then returns it to normal: Save → "Saving…", Apply & Save →
"Applying…", Export → "Exporting…", Clear Cache → "Flushing…", Install
Update → "Updating…", Add App → "Loading…" while the app catalog finishes its
first scan.

## Text fields

Editable fields — workspace and theme names, the Wallpapers search, the name
prompt and the numeric editor fields — take their text decoration from the
palette, never from a system colour:

- **Selection** is `palette.selectionBackground` (`palette.accent`) under
  `palette.selectionForeground` (`palette.barBG`) ink — the same pair as the
  active workspace pill. A light label therefore stays readable on every
  theme, where AppKit's fixed blue could swallow it. `ThemedWindow` applies
  it whenever a field takes the keyboard (click, Tab or programmatic focus),
  and `paletteChanged` re-applies it after a live or draft theme change.
- **Focus ring**: the app picker's search is the one field that draws one — a
  1 px `palette.accent` stroke at `windowCornerRadius(6)`, shown only while
  the field has the keyboard and cleared when it loses it. Other editable
  fields draw their own box; none uses AppKit's blue focus ring.

A new editable field inherits both from its window. Do not set a literal
selection or focus-ring colour on the control.

## Motion

Motion is rare, short, and always says that something arrived.

- **The wordmark comes alive when the modal opens**: one of seventeen effects
  plays over the logo's lit cells — laseretch's beam and sparks, sweep's
  travelling band, waves' columns pushing in while every cell rides rising
  and falling laser bars, beams' converging lights, middleout's single
  centre line splitting open vertically, scattered's pops, print's
  typewriter, decrypt's ciphertext resolving cell by cell, errorcorrect's
  signal lock, rain's falling drops, crumble's debris, expand's blossom,
  slice's two halves, spray's nozzle, wipe's clean front, highlight's flash
  and colorshift's shimmer — a different one at random each open, never
  repeating the last. Each cell flares hot on arrival and cools to its accent
  shade, and every run ends by crossfading 0.12 s onto the crisp wordmark.
  `LOGO_INTRO` in `settings.conf` pins one effect. `LogoIntroView` samples
  the grid from the tinted wordmark at open time (about 18 rows, ~2.2 pt
  cells, colour from the same shade ladder as the header), so a new logo
  animates with no new asset. The vocabulary is a native take on
  [ttfx](https://github.com/omacom/ttfx) (MIT) — the terminal text effects
  engine by the Omarchy authors, itself a port of TerminalTextEffects by
  ChrisBuilds. The dynamics were written from its Rust source (laseretch's
  walk, flare and sparks closely; the rest as block-cell readings of its
  ideas). Nothing from omarchy.us itself is used: the site's wrapper code and
  its wordmark bitmap are unlicensed. The attribution line sits at the top of
  the logo intro block in `helper/dashboard.swift`.
- **The rotation is paced down as a set.** `LogoIntroEffect.pace` is the one
  tuning knob (0.75 today): a run lasts about 0.6–1.2 s, the longest being
  crumble at 1.16 s, the average about 0.85 s. Add the 0.03 s lead-in and the
  0.12 s crossfade for the time before the crisp wordmark returns.
  `omacosy-dashboard-bin --logo-timing` prints the real cell count and every
  effect's numbers; `OMACOSY_LOGO_TRACE=1` prints one tick/draw summary per
  run. Raise the pace toward 1.0 for the older, slower reading.
- **Reduce Motion turns it off.** `playLogoIntro` checks
  `NSWorkspace.accessibilityDisplayShouldReduceMotion` and shows the logo at
  rest instead.
- The 0.12 s button press dim above is the only other motion in the modal.

## Dropdowns

A dropdown is never a native menu (the glass `NSMenu`): the Theme Editor's
Method and Presets pickers, and the Wallpapers tab's **Sort Order** and
**Aspect Ratio** pickers, all use one component.

- **The trigger** (`PopupButtonView`, `WHDropdown`) is a `windowCornerRadius(6)`
  box: `palette.itemBG` at 0.35, a 1 px `palette.muted` border at 0.35, the
  current choice in Regular 12 `palette.label` at the left, and a `\u{f078}`
  chevron Regular 9 `palette.muted` at `bounds.width - 15`. A click commits any
  open field first.
- **The card** (`MethodPicker` / `MethodPickerRoot`) is a borderless child
  window: `palette.barBG` at `windowCornerRadius(10)`, a 1 px `palette.accent`
  border, and a Bold 12 `palette.accent` header naming the choice. Rows are 30 pt
  with Regular 12 `palette.label`; the selected row is `palette.accent` at 0.85
  filled, in `palette.barBG`, with a `\u{f00c}` tick. The card is sized to its
  list (`min(430, rows + 52)`), so a short list is a short menu.
- **Keyboard first.** Omacosy is a keyboard-driven app, so every dropdown
  opens keyboard-ready: ↑ and ↓ walk the rows (group headers are skipped) and
  the list scrolls to keep the highlighted row visible, Return picks it and
  Esc closes. Where the choice drives a live surface — the editor's Method
  and Presets — the highlighted row applies as you walk, so the preview
  follows the arrows and Return is only ever a close; a picker whose pick
  fires work of its own (the Wallpapers filters' search) applies on pick.
  Mouse scrolling and clicking are alternatives, never the only way to move
  the selection. A new dropdown control must behave the same.

## The Workspaces tab rows

One row per workspace, 48 pt tall: a numbered **slot pill**, the editable
name, the pen, the app chips, then **＋ Add App**.

- The pill is a perfect **square** (26 pt) that becomes a **circle** in the
  rounded-corner mode — the same `windowCornerRadius(6) > 2` rule the
  segmented control reads, so square mode keeps it square. Its fill is the
  chips' `palette.itemBG` at 0.6, the slot number in Bold 12 `palette.label`
  centred inside, so a two-digit workspace (11, 19) still fits.
- The **pen is a real `ButtonView`** (`secondary`, 22 pt square, the
  `\u{f040}` glyph) in its own fixed column after the name — never chasing
  the name's width — and the name is truncated to stop short of it. Both
  the name text and the pen open the inline edit field; a click anywhere
  else commits.
- The Add App button is 80 pt, not 96: the label measures 70 pt in Bold 12,
  and the pill and pen column come out of the same row budget.

## The dashboard tabs

Every tab draws its first content title on one shared line: its centre 16 pt
below the top of the tab's content area. A `drawMidLeft` title uses
`midTop: 16`; a `drawTopLeft` title uses `top: 11` (11 + half the cap height
puts the centre on 16). All are Bold 13 accent. A new tab must put its first
title on the same 16 pt line.

**The Themes gallery sections.** The gallery is one list of titled blocks:
**Omarchy Themes**, then **Custom Themes** (the saved editions), then **Auto
Themes** (the raw `Wallpaper #N` pictures whose auto themes they seed). Each
block is a Bold 13 accent heading on a 34 pt header, 8 pt above its first
card. A block with no cells is left out, and the first block opens with no
rule above it. Between blocks a 1 px `palette.muted` hairline at 0.25 sits
22 pt after the previous block and 22 pt before the next heading.

**The favourite star.** A saved edition's card carries a 24 pt overlay button
at its top-left, the same slot and 8 pt inset as the Wallpapers grid's
bookmark: the black 0.5 pill with a 1 px white border at 0.14, the outline
star (`\u{f006}`, white) while hovered, and the filled star (`\u{f005}`,
`palette.accent`) once set. It stays visible while set, and selection mode
hides it because a click there ticks the card instead. Starred editions lead
the **Custom Themes** block, A→Z within each group. The star is the
confirmation; there is no separate notification. Stock and `Wallpaper #N`
cards have no record, so they never show one.

**The Themes filter row.** A fixed 34 pt strip between the tab strip and the
gallery, with the three `LabeledCheckView`s (18 pt box, 6 pt gap, Regular 12
label, 16 pt between controls) centred horizontally.

**The Themes bottom panel.** A solid `palette.barBG` bar, 76 pt tall, with no
hairline. It has two rows: the muted Regular 11 **Color** label, the nine
20 × 20 swatches with 6 pt gaps and the `WHDropdown` Sort (170 × 24), 20 pt
after the swatches, as one combined group centred in the strip; below it, the
**Select** / **Done** button (96 × 24) centred, with **Delete N** 8 pt to its
left while a selection is live. A muted **Clear** text action sits at the far
right only while a swatch is selected. Selected swatches use the 2 pt
`palette.accent` ring; unselected use 1 pt `palette.muted` at 0.5. The bar is
vertically centred: 20 pt above the colour row and the modal's own 20 pt card
padding below Select.
A section with no matching cards is omitted, and an empty result draws one
centred Regular 12 `palette.muted` line in the gallery.

**The gallery jump arrows** — the Themes gallery and the Wallpapers tab's
**Bookmarked** view — are 30 pt squares, 12 pt inside the scroll area's
bottom-right corner. Each is `palette.barBG` at 0.92 with a 1 px
`palette.muted` border at 0.5 and a Regular 13 `palette.label` arrow
(`\u{f063}` down, `\u{f062}` up), so it stays legible over any thumbnail. The
arrow follows the last scroll direction while shelf remains on both sides,
flips to the only way out at either end, and hides when the content fits. The
search results keep their load-more scrolling and do not show the arrow.
Removing a bookmark rebuilds the shelf in place and restores its scroll
position, so a clearing run does not jump back to the top.

## The wallpaper metadata card

Right-clicking a Wallpapers result opens a compact, text-only card. It is
620 pt wide, at most 760 pt tall, and opens at its exact content height: the
`/w/<id>` response is fetched before the card is drawn, so it never grows or
re-centres under the pointer. A tag list too long for the card scrolls inside
it instead.

- **Header, 48 pt.** The purity and category badges sit at the top left
  (Bold 9, `itemBG` at 0.55, a `muted` border at 0.35, radius 5); the close
  button is at the top right. There is no title. The hairline sits 10 pt
  above the first heading.
- **Body, 20 pt side padding.** `Details` is the Bold 12 accent heading.
  Facts use two equal columns with a 32 pt gutter and 24 pt rows: label
  Regular 11 `muted`, value Regular 11 `label`, right-aligned in its column.
  The colour row draws 14 pt swatches in place of a value.
- **The source is a link.** A `Source` value that is an http(s) URL draws in
  `palette.accent` with a 1 pt underline and opens in the browser on click;
  any other value is ordinary text.
- **Uploader and tags.** `Uploader` is a Bold 12 accent heading with one
  line under it: the name in Regular 12 `label`, then `· role` in Regular 10
  `muted`. `Tags` is the same heading over one wrapped, comma-separated line
  (Regular 11 `label`, 18 pt line height). There is no avatar and no tag
  chips.
- **Footer, 60 pt.** **Copy Link** is the only action: 96 × 26 pt, centred.
  A **Retry** button appears beside it only when the extra details could not
  be loaded.

There is no preview image; the card is for the metadata, not the picture.
