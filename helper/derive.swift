// derive.swift — compute a whole omacosy theme from one wallpaper.
//
//   omacosy-derive <image> <outdir>
//
// Writes <outdir>/sketchybar.sh and <outdir>/borders.sh in the omarchy
// theme format the bar and the borders daemon already read. Nothing else
// in omacosy changes: a generated directory IS a theme, and pointing
// ~/.config/omarchy/current/theme at it restyles the desktop.
//
// The base colour is the SAME maths as seedStrip() in bar.swift: the
// centred fill-crop for the screen, the band the bar covers, averaged,
// then saturation pushed 1.3 and darkened 0.923. Those two constants were
// fitted against the real macOS menu bar over seven wallpapers; they are
// not from any documentation and they are not ours to change here.
//
// The other four colours come from that base, using the lightness ladder
// measured across the four stock themes, and every one of them is then
// CHECKED against the surface it sits on and corrected until the check
// passes. See separate() and the floors in derive().

import AppKit
import Foundation

// MARK: - the screen the crop is computed for

// seedStrip crops for the real display. Here there may be no display at
// all (this runs from a script), so the geometry is fixed and matches the
// built-in panel. A different screen shifts WHICH pixels are averaged by
// a few per cent and moves the result by about 1/255 — measured, not
// assumed — so one number is enough and it keeps the output reproducible.
let frameW: Double = 1440
let frameH: Double = 900
let barHeight: Double = 34

let menuBarSaturation = 1.3
let menuBarDarken = 0.923

// MARK: - colour helpers

struct RGB {
    var r: Double, g: Double, b: Double
    var lum: Double { 0.299 * r + 0.587 * g + 0.114 * b }
    var hex: String {
        func q(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "%02x%02x%02x", q(r), q(g), q(b))
    }
    var argb: String { "0xff" + hex }
}

func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

// Written out rather than taken from NSColor. NSColor's HSB accessors go
// through a colour space conversion, and this file has to agree with the
// reference implementation to the last digit for the fixtures to mean
// anything.
func toHSV(_ c: RGB) -> (h: Double, s: Double, v: Double) {
    let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
    let d = mx - mn
    var h = 0.0
    if d > 0 {
        if mx == c.r { h = (c.g - c.b) / d }
        else if mx == c.g { h = 2 + (c.b - c.r) / d }
        else { h = 4 + (c.r - c.g) / d }
        h *= 60
        if h < 0 { h += 360 }
    }
    return (h, mx == 0 ? 0 : d / mx, mx)
}

func fromHSV(_ h: Double, _ s: Double, _ v: Double) -> RGB {
    let hh = h.truncatingRemainder(dividingBy: 360) < 0
        ? h.truncatingRemainder(dividingBy: 360) + 360
        : h.truncatingRemainder(dividingBy: 360)
    let S = clamp01(s), V = clamp01(v)
    if S == 0 { return RGB(r: V, g: V, b: V) }
    let i = Int(hh / 60) % 6
    let f = hh / 60 - Double(Int(hh / 60))
    let p = V * (1 - S), q = V * (1 - S * f), t = V * (1 - S * (1 - f))
    switch i {
    case 0: return RGB(r: V, g: t, b: p)
    case 1: return RGB(r: q, g: V, b: p)
    case 2: return RGB(r: p, g: V, b: t)
    case 3: return RGB(r: p, g: q, b: V)
    case 4: return RGB(r: t, g: p, b: V)
    default: return RGB(r: V, g: p, b: q)
    }
}

func blend(_ c: RGB, toward t: RGB, _ k: Double) -> RGB {
    RGB(r: c.r * (1 - k) + t.r * k,
        g: c.g * (1 - k) + t.g * k,
        b: c.b * (1 - k) + t.b * k)
}

// Snap to the 8 bits per channel that actually get written. The contrast
// loops below MUST compare quantised values: satisfied in floating point
// and then rounded, three of the five floors fell back under by about
// 0.002 — quantisation error is up to 0.5/255 per channel, and luminance
// is a weighted sum, so two colours can drift 0.004 apart. The guarantee
// has to hold for the hex in the file, not for the maths behind it.
func q8(_ c: RGB) -> RGB {
    func q(_ v: Double) -> Double { (clamp01(v) * 255).rounded() / 255 }
    return RGB(r: q(c.r), g: q(c.g), b: q(c.b))
}

let white = RGB(r: 1, g: 1, b: 1)
let black = RGB(r: 0, g: 0, b: 0)

// MARK: - the base colour, seedStrip's maths

func baseColour(of url: URL) -> RGB? {
    // CGImageSource, not NSImage: the TIFF round trip costs an 80MB buffer
    // on a 6016x3384 image and nothing reads it.
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
    let bitmap = NSBitmapImageRep(cgImage: cg)
    guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }

    // The wallpaper is scaled to FILL, so the visible band is not simply
    // the top of the image: the scale is the LARGER of the two ratios and
    // the crop is centred. Getting this wrong reads a band nobody sees.
    let sx = frameW / Double(bitmap.pixelsWide)
    let sy = frameH / Double(bitmap.pixelsHigh)
    let scale = max(sx, sy)
    let band = max(1, Int(barHeight / scale))
    let visibleW = Int(frameW / scale)
    let x0 = max(0, (bitmap.pixelsWide - visibleW) / 2)

    var r = 0.0, g = 0.0, b = 0.0, n = 0.0
    for x in stride(from: x0, to: min(x0 + visibleW, bitmap.pixelsWide),
                    by: max(1, visibleW / 64)) {
        for y in stride(from: 0, to: band, by: max(1, band / 4)) {
            // usingColorSpace(.sRGB) is NOT optional. The bitmap carries the
            // image's own profile; skipping the conversion reads raw
            // component values and lands up to 22/255 away. That gap is
            // larger than the whole menu-bar correction below.
            guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            else { continue }
            r += Double(c.redComponent)
            g += Double(c.greenComponent)
            b += Double(c.blueComponent)
            n += 1
        }
    }
    guard n > 0 else { return nil }

    let mean = (r / n, g / n, b / n)
    let luma = 0.299 * mean.0 + 0.587 * mean.1 + 0.114 * mean.2
    func menuBarLike(_ v: Double) -> Double {
        clamp01((luma + menuBarSaturation * (v - luma)) * menuBarDarken)
    }
    return RGB(r: menuBarLike(mean.0), g: menuBarLike(mean.1), b: menuBarLike(mean.2))
}

// MARK: - the picture's colour

// The hue the picture READS as, and how much of the picture agrees.
//
// Weighted by saturation x value CUBED. The cube is the whole trick and it
// was fitted, not chosen: the moon-over-a-mountain picture is 61% dark
// purple by area and 7% bright blue glow, and the eye calls it blue. Linear
// and squared weighting both answer purple; cubed answers blue. On the
// lighthouse, whose hues are spread so thinly that no 10-degree bucket holds
// more than 11%, cubed is also the first that answers pink instead of a
// narrow blue band.
//
// Hues go into 36 buckets smoothed over +/-20 degrees, so a hue spread
// across several buckets is not beaten by a narrow one. `share` is how much
// of the total weight the winning window holds — the caller uses it to
// decide how far to trust this.
//
// nil means the picture has no colour at all: a greyscale photograph.
func pictureColour(of url: URL) -> (hue: Double, sat: Double, share: Double)? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let bm = NSBitmapImageRep(cgImage: cg)
    guard bm.pixelsWide > 0, bm.pixelsHigh > 0 else { return nil }
    let sx = max(1, bm.pixelsWide / 200), sy = max(1, bm.pixelsHigh / 200)

    var samples: [(h: Double, s: Double, v: Double)] = []
    samples.reserveCapacity(40000)
    for x in stride(from: 0, to: bm.pixelsWide, by: sx) {
        for y in stride(from: 0, to: bm.pixelsHigh, by: sy) {
            guard let c = bm.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let t = toHSV(RGB(r: Double(c.redComponent), g: Double(c.greenComponent),
                              b: Double(c.blueComponent)))
            if t.v >= 0.10 { samples.append((t.h, t.s, t.v)) }
        }
    }
    guard samples.count > 20 else { return nil }

    // IS there any colour at all? This test is kept exactly as it was, because
    // it is the one that stopped a black-and-white city being painted yellow
    // and a black-and-white portrait pink. A greyscale image has a 90th
    // percentile of saturation too, and it is sensor noise, so the floor
    // matters as much as the percentile.
    let scores = samples.map { $0.s * $0.v }.sorted()
    let cut = max(0.12, scores[Int(0.90 * Double(scores.count - 1))])
    guard samples.filter({ $0.s * $0.v >= cut && $0.s >= 0.18 }).count > 5 else { return nil }

    // WHICH colour, then, over everything that carries any chroma at all.
    var bucket = [Double](repeating: 0, count: 36)
    var bs = [Double](repeating: 0, count: 36)
    for t in samples where t.s >= 0.10 {
        let w = t.s * t.v * t.v * t.v
        let i = min(35, Int(t.h / 10))
        bucket[i] += w
        bs[i] += t.s * w
    }

    var smooth = [Double](repeating: 0, count: 36)
    for i in 0..<36 { for d in -2...2 { smooth[i] += bucket[(i + d + 36) % 36] } }
    guard let best = smooth.indices.max(by: { smooth[$0] < smooth[$1] }), smooth[best] > 0
    else { return nil }

    var wsum = 0.0, hx = 0.0, hy = 0.0, ss = 0.0
    for d in -2...2 {
        let i = (best + d + 36) % 36
        let w = bucket[i]; guard w > 0 else { continue }
        let ang = (Double(i) * 10 + 5) * .pi / 180
        hx += cos(ang) * w; hy += sin(ang) * w; ss += bs[i]; wsum += w
    }
    guard wsum > 0 else { return nil }
    var h = atan2(hy, hx) * 180 / .pi
    if h < 0 { h += 360 }
    let totalWeight = bucket.reduce(0, +)
    return (h, min(1.0, ss / wsum), totalWeight > 0 ? smooth[best] / totalWeight : 0)
}

// MARK: - the palette

struct Palette {
    var bar: RGB, pill: RGB, muted: RGB, label: RGB, accent: RGB
    var isLight: Bool, isLowChroma: Bool
    var hue: Double, sat: Double, val: Double
}

let accentHueShift = 0.0        // 3 of 4 stock themes shift negative; 0 is the centre

// Push c away from ref until their luminance differs by `need`. Blending
// toward white or black ALWAYS has somewhere to go; an offset in HSV value
// does not, and a base already at value 1.00 could not lift its pill at all.
func separate(_ c: RGB, from ref: RGB, need: Double) -> RGB {
    let lr = q8(ref).lum
    if abs(q8(c).lum - lr) >= need { return c }
    let target = (1 - lr) >= lr ? white : black
    for step in 1...50 {
        let cand = blend(c, toward: target, 0.02 * Double(step))
        if abs(q8(cand).lum - lr) >= need { return cand }
    }
    return target
}

// Place c AT a luminance. muted sits between the pill and the label, and
// two separate() calls applied in turn fought each other: the second undid
// the first whenever the gap could not hold a colour between them.
func towardLum(_ c: RGB, _ wanted: Double) -> RGB {
    let target = wanted > q8(c).lum ? white : black
    var best = c
    for step in 0...50 {
        let cand = blend(c, toward: target, 0.02 * Double(step))
        if abs(q8(cand).lum - wanted) < abs(q8(best).lum - wanted) { best = cand }
    }
    return best
}

// Push a colour out of two forbidden luminance bands at once, the bar's and
// the pill's. Calling separate() twice cannot do it: the second call happily
// lands back inside the first band.
func clearOf(_ c: RGB, bar: RGB, pill: RGB) -> RGB {
    let lb = q8(bar).lum, lp = q8(pill).lum
    let lo = min(lb - 0.28, lp - 0.20)
    let hi = max(lb + 0.28, lp + 0.20)
    let lc = q8(c).lum
    if lc <= lo || lc >= hi { return c }
    let downOK = lo >= 0.0, upOK = hi <= 1.0
    let goUp: Bool
    if upOK && downOK { goUp = (hi - lc) <= (lc - lo) }
    else if upOK { goUp = true }
    else if downOK { goUp = false }
    else { goUp = (1.0 - lc) >= lc }
    let target = goUp ? white : black
    let wanted = goUp ? hi : lo
    for step in 1...50 {
        let cand = blend(c, toward: target, 0.02 * Double(step))
        let l = q8(cand).lum
        if goUp ? (l >= wanted) : (l <= wanted) { return cand }
    }
    return target
}

func derive(_ base: RGB, picture: (hue: Double, sat: Double, share: Double)?) -> Palette {
    // Two hues, for two jobs.
    //
    // The BAR, the pills, the muted text and the labels all keep the BASE
    // hue. The bar is the wallpaper showing through, so anything sitting on
    // it in the same hue family belongs there. Giving them the loud hue
    // instead made a beige picture wear blue pills and a pink one wear blue
    // pills, and both read as foreign objects pasted onto the desktop.
    //
    // The RING takes the loud hue — the colour the eye goes to in the whole
    // picture. It is the one element that has to be SEEN rather than blend
    // in, and it sits on a window, not on the bar.
    let (baseH, baseS, V) = toHSV(base)
    let H = picture?.hue ?? 0
    let S = picture?.sat ?? 0
    let low = picture == nil

    // Which hue the PILLS wear. Normally the bar's, because the bar is the
    // wallpaper showing through and they sit on it. But the bar is a 34-point
    // strip across the top, and a strip can lie about the picture: on
    // moon-over-a-mountain it catches the purple edge of a sky whose body is
    // blue, and the mauve pills that produced read as foreign.
    //
    // So the picture overrules the strip only when it is BOTH confident and
    // nearby: at least 65% of the weight behind one hue, and within 90
    // degrees of the strip. The beige picture with a small blue jacket fails
    // both tests (49%, 170 degrees) and keeps its beige pills, which is the
    // case this guard exists to protect.
    var pillH = baseH, pillS = baseS
    if let p = picture, p.share >= 0.65 {
        let gap = min(abs(p.hue - baseH), 360 - abs(p.hue - baseH))
        if gap <= 90 { pillH = p.hue; pillS = max(baseS, p.sat * 0.7) }
    }
    // Luminance, NOT V. A saturated purple at V=0.62 has luminance 0.27 and
    // needs LIGHT text; choosing on V called it a light bar and painted
    // near-black text on it.
    let light = base.lum > 0.45

    var pill: RGB, muted: RGB, label: RGB, accent: RGB
    if light {
        pill   = fromHSV(pillH, pillS * 0.75, V * 0.80)
        muted  = fromHSV(pillH, min(pillS, 0.30), V * 0.42)
        label  = fromHSV(pillH, min(pillS, 0.38), V * 0.16)
        // No loud colour means no hue, so the accent goes to the opposite
        // end of the ladder instead — the most visible thing available, and
        // honest about the picture having no colour.
        //
        // The chromatic branch is VIVID and lets separate() below decide how
        // far down it has to come. It used to be value * 0.38, which on a
        // bright picture landed every accent at 0.28-0.38: a warm hue there
        // is brown and a cool one is near-black. The hues were right the
        // whole time — a red umbrella came out as dark brown — and one
        // multiplier was crushing them.
        accent = low ? fromHSV(0, 0, 0.06)
                     : fromHSV(H + accentHueShift, max(0.85, S), 0.92)
    } else {
        pill   = fromHSV(pillH, pillS * 0.85, max(V + 0.11, 0.20))
        muted  = fromHSV(pillH, min(pillS, 0.22), 0.48)
        label  = fromHSV(pillH, min(pillS, 0.18), 0.92)
        accent = low ? fromHSV(0, 0, 0.99)
                     : fromHSV(H + accentHueShift, max(0.45, S * 1.15), 0.92)
    }

    // The floors are the gaps the four stock themes already hold. Order
    // matters: the label is placed off the pill first so that muted has a
    // gap to sit in the middle of.
    pill   = separate(pill,   from: base, need: 0.085)
    label  = separate(label,  from: pill, need: 0.50)
    // The accent is drawn ON pills — it fills the focused workspace chip and
    // it is the app name's text colour — so clearing the BAR is not enough.
    accent = clearOf(accent, bar: base, pill: pill)
    muted  = towardLum(muted, (q8(pill).lum + q8(label).lum) / 2)

    return Palette(bar: base, pill: pill, muted: muted, label: label, accent: accent,
                   isLight: light, isLowChroma: low, hue: H, sat: S, val: V)
}

// MARK: - output

// RED, GREEN and YELLOW carry meaning: a low battery has to read as red.
// The wallpaper gets no say in them. Only their lightness follows the
// ladder, so they stay legible on a light bar.
let semanticDark  = ["RED": "0xffe05f5f", "GREEN": "0xff6fcf87", "YELLOW": "0xffe5c736"]
let semanticLight = ["RED": "0xff9d1f1f", "GREEN": "0xff1f7a3a", "YELLOW": "0xff8a6d00"]

func write(_ p: Palette, to dir: URL, from image: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let sem = p.isLight ? semanticLight : semanticDark
    let note = String(format: "# base hue %.0f sat %.2f val %.2f  %@%@",
                      p.hue, p.sat, p.val,
                      p.isLight ? "light" : "dark",
                      p.isLowChroma ? "  low-chroma" : "")

    var sb = "#!/usr/bin/env bash\n"
    sb += "# generated by omacosy-derive from \(image.lastPathComponent)\n"
    sb += note + "\n"
    // BAR_COLOR mirrors BAR_BG_SOLID and ICON_COLOR mirrors LABEL_COLOR:
    // both pairs are identical in all four stock themes.
    sb += "export BAR_BG_SOLID=\(p.bar.argb)\n"
    sb += "export BAR_COLOR=\(p.bar.argb)\n"
    sb += "export ITEM_BG=\(p.pill.argb)\n"
    sb += "export MUTED=\(p.muted.argb)\n"
    sb += "export LABEL_COLOR=\(p.label.argb)\n"
    sb += "export ICON_COLOR=\(p.label.argb)\n"
    sb += "export ACCENT=\(p.accent.argb)\n"
    for k in ["RED", "GREEN", "YELLOW"] { sb += "export \(k)=\(sem[k]!)\n" }

    // ACTIVE_COLOR is the accent in all four stock themes: the focus ring
    // is not a colour of its own.
    var bd = "#!/usr/bin/env bash\n"
    bd += "# generated by omacosy-derive from \(image.lastPathComponent)\n"
    bd += "export ACTIVE_COLOR=\(p.accent.argb)\n"
    bd += "export INACTIVE_COLOR=\(p.pill.argb)\n"

    try sb.write(to: dir.appendingPathComponent("sketchybar.sh"),
                 atomically: true, encoding: .utf8)
    try bd.write(to: dir.appendingPathComponent("borders.sh"),
                 atomically: true, encoding: .utf8)
}

// MARK: - main

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(
        "usage: omacosy-derive <image> [outdir]\n       omacosy-derive --print <image>...\n"
            .data(using: .utf8)!)
    exit(2)
}

if args[1] == "--print" {
    // Fixture mode: print the palette without writing anything. This is what
    // regenerates the golden vectors.
    for path in args.dropFirst(2) {
        let url = URL(fileURLWithPath: path)
        guard let base = baseColour(of: url) else {
            print("FAIL  \(url.lastPathComponent)"); continue
        }
        let p = derive(base, picture: pictureColour(of: url))
        print("\(p.bar.hex) \(p.pill.hex) \(p.muted.hex) \(p.label.hex) \(p.accent.hex) "
            + "\(p.isLight ? "light" : "dark")\(p.isLowChroma ? "+lowchroma" : "") "
            + url.lastPathComponent)
    }
    exit(0)
}

guard args.count >= 3 else {
    FileHandle.standardError.write("omacosy-derive: no output directory\n".data(using: .utf8)!)
    exit(2)
}
let image = URL(fileURLWithPath: args[1])
guard let base = baseColour(of: image) else {
    FileHandle.standardError.write(
        "omacosy-derive: cannot decode \(image.path)\n".data(using: .utf8)!)
    exit(1)
}
do {
    try write(derive(base, picture: pictureColour(of: image)), to: URL(fileURLWithPath: args[2]), from: image)
} catch {
    FileHandle.standardError.write(
        "omacosy-derive: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
