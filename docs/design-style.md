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
