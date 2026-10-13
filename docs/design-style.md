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
Update → "Updating…".

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

## The dashboard tabs

Every tab draws its first content title on one shared line: its centre 16 pt
below the top of the tab's content area. A `drawMidLeft` title uses
`midTop: 16`; a `drawTopLeft` title uses `top: 11` (11 + half the cap height
puts the centre on 16). All are Bold 13 accent. A new tab must put its first
title on the same 16 pt line.
