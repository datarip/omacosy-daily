// omacosy-dashboard — the settings modal (Super+,).
//
// A Super+K-style card with three tabs: Options, Workspaces, Themes. It
// reads current state from the same files and commands the rest of omacosy
// uses, and applies changes by running those commands — it holds no policy
// of its own, so the GUI can never disagree with the CLI.
//
// Self-contained on purpose: install.sh builds one source file per binary,
// and a fault here must never be able to take the menu bar down, so the
// palette/font/measure helpers the cheatsheet uses are copied in rather
// than shared with bar.swift.
//
// Palette comes from ~/.config/omarchy/current/theme/sketchybar.sh, the
// same file the bar and cheatsheet read, and it is re-read when that
// symlink is swapped — so stock, custom and auto-theme-derived palettes
// all follow automatically.

import Cocoa
import CoreImage
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

let HOME = NSHomeDirectory()

// --- palette ---------------------------------------------------------------

struct Palette {
    var itemBG = NSColor.black
    var accent = NSColor.systemBlue
    var label = NSColor.white
    var muted = NSColor.gray
    var barBG = NSColor.black
}

func color(fromARGB v: UInt64) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: CGFloat((v >> 24) & 0xff) / 255)
}

func loadPalette() -> Palette {
    var p = Palette()
    let file = HOME + "/.config/omarchy/current/theme/sketchybar.sh"
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return p }
    for line in text.split(separator: "\n") {
        let parts = line.replacingOccurrences(of: "export ", with: "").split(separator: "=")
        guard parts.count == 2, parts[1].hasPrefix("0x"),
              let v = UInt64(parts[1].dropFirst(2), radix: 16) else { continue }
        switch parts[0] {
        case "ITEM_BG": p.itemBG = color(fromARGB: v)
        case "ACCENT": p.accent = color(fromARGB: v)
        case "LABEL_COLOR": p.label = color(fromARGB: v)
        case "MUTED": p.muted = color(fromARGB: v)
        case "BAR_BG_SOLID": p.barBG = color(fromARGB: v)
        default: break
        }
    }
    return p
}

var palette = loadPalette()

func nerdFont(_ face: String, _ size: CGFloat) -> NSFont {
    let desc = NSFontDescriptor(fontAttributes: [
        .family: "JetBrainsMono Nerd Font", .face: face,
    ])
    if let f = NSFont(descriptor: desc, size: size), f.familyName == "JetBrainsMono Nerd Font" {
        return f
    }
    return .monospacedSystemFont(ofSize: size, weight: face == "Bold" ? .bold : .semibold)
}

// --- text ------------------------------------------------------------------

func textLine(_ s: String, _ font: NSFont, _ color: NSColor) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(
        string: s, attributes: [.font: font, .foregroundColor: color]))
}

func advance(_ s: String, _ font: NSFont) -> CGFloat {
    CGFloat(CTLineGetTypographicBounds(textLine(s, font, .black), nil, nil, nil))
}

func drawBaseline(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, baseline: CGFloat) {
    guard !s.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(textLine(s, font, color), ctx)
}

// top-based helpers: `top`/`midTop` measure down from the view's top edge
func drawTopLeft(_ s: String, _ font: NSFont, _ color: NSColor,
                 x: CGFloat, top: CGFloat, height: CGFloat) {
    drawBaseline(s, font, color, x: x, baseline: height - top - font.capHeight)
}

func drawMidLeft(_ s: String, _ font: NSFont, _ color: NSColor,
                 x: CGFloat, midTop: CGFloat, height: CGFloat) {
    drawBaseline(s, font, color, x: x, baseline: height - midTop - font.capHeight / 2)
}

func drawMidCenter(_ s: String, _ font: NSFont, _ color: NSColor,
                   centerX: CGFloat, midTop: CGFloat, height: CGFloat) {
    drawBaseline(s, font, color, x: centerX - advance(s, font) / 2,
                 baseline: height - midTop - font.capHeight / 2)
}

// The numbered step bubble on a column header (1 = picture, 2 = colours).
func drawStepBadge(_ n: Int, centerX: CGFloat, midTop: CGFloat, height: CGFloat) {
    let d: CGFloat = 18
    let rect = NSRect(x: centerX - d / 2, y: height - midTop - d / 2, width: d, height: d)
    palette.accent.setFill()
    NSBezierPath(ovalIn: rect).fill()
    drawMidCenter("\(n)", nerdFont("Bold", 11), palette.barBG,
                  centerX: centerX, midTop: midTop, height: height)
}

// --- shell / config --------------------------------------------------------

@discardableResult
func shell(_ command: String) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", command]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (127, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func sha256Hex(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

func readConfKey(_ file: String, _ key: String) -> String? {
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
        let k = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        if k == key {
            var v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return v
        }
    }
    return nil
}

@discardableResult
func setConfKey(_ file: String, _ key: String, _ value: String) -> Bool {
    var text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if let last = lines.last, last.isEmpty { lines.removeLast() }
    var found = false
    for i in 0..<lines.count {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
        let k = trimmed[trimmed.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        if k == key { lines[i] = "\(key)=\"\(value)\""; found = true; break }
    }
    if !found { lines.append("\(key)=\"\(value)\"") }
    text = lines.joined(separator: "\n") + "\n"
    do { try text.write(toFile: file, atomically: true, encoding: .utf8); return true }
    catch { return false }
}

// --- secrets ---------------------------------------------------------------

let SECRETS = HOME + "/.config/omacosy/secrets.conf"

// The machine-wide tool opacity (0...100) the editor shows; an edition's own
// toolOpacity overrides it. nil = unset, so the terminal's own setting stands.
let TERM_AUTO_CONF = HOME + "/.config/omacosy/term-auto-theme.conf"

func readGlobalToolOpacity() -> Int? {
    guard let s = readConfKey(TERM_AUTO_CONF, "tool_opacity"), let n = Int(s),
          n >= 0, n <= 100 else { return nil }
    return n
}

func writeGlobalToolOpacity(_ value: Int?) {
    _ = setConfKey(TERM_AUTO_CONF, "tool_opacity", value.map(String.init) ?? "")
}

// Ghostty's own background-opacity, as a percent, from whichever of its config
// files names it. It is the value in use when the theme sets nothing, so the
// editor's sliders open showing it rather than an empty track.
func readTerminalOpacity() -> Int? {
    let paths = [HOME + "/Library/Application Support/com.mitchellh.ghostty/config",
                 HOME + "/.config/ghostty/config"]
    for path in paths {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
            if t[..<eq].trimmingCharacters(in: .whitespaces) == "background-opacity",
               let v = Double(t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)) {
                return Int((max(0, min(1, v)) * 100).rounded())
            }
        }
    }
    return nil
}

func readSecret(_ key: String) -> String {
    guard let text = try? String(contentsOfFile: SECRETS, encoding: .utf8) else { return "" }
    for raw in text.split(separator: "\n") {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
        if t[..<eq].trimmingCharacters(in: .whitespaces) == key {
            return String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
    }
    return ""
}

// secrets.conf holds credentials, so it is the one config file that must
// not be world-readable and must not be half-written. The temp file is
// created with mode 600 BEFORE any value is written, flushed to disk, then
// renamed over the old file. Nothing here shells out, so the value cannot
// reach a log or a transcript. An empty value removes the key, which is
// what clearing the field in the API Keys tab does.
@discardableResult
func writeSecret(_ key: String, _ value: String) -> Bool {
    let dir = HOME + "/.config/omacosy"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var lines: [String] = []
    if let text = try? String(contentsOfFile: SECRETS, encoding: .utf8) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let last = lines.last, last.isEmpty { lines.removeLast() }
    }
    let clean = value.replacingOccurrences(of: "\n", with: "")
    var out: [String] = []
    var found = false
    for line in lines {
        let t = line.trimmingCharacters(in: .whitespaces)
        let eq = t.firstIndex(of: "=")
        let k = eq.map { t[..<$0].trimmingCharacters(in: .whitespaces) } ?? ""
        if !t.hasPrefix("#"), k == key {
            found = true
            if !clean.isEmpty { out.append("\(key)=\(clean)") }
        } else {
            out.append(line)
        }
    }
    if !found && !clean.isEmpty { out.append("\(key)=\(clean)") }
    if out.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
        _ = unlink(SECRETS)
        return true
    }
    let text = out.joined(separator: "\n") + "\n"

    let tmp = SECRETS + ".tmp"
    _ = unlink(tmp)
    let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard fd >= 0 else { return false }
    let data = Array(text.utf8)
    let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    _ = fsync(fd)
    _ = close(fd)
    guard written == data.count else { _ = unlink(tmp); return false }
    guard rename(tmp, SECRETS) == 0 else { _ = unlink(tmp); return false }
    _ = chmod(SECRETS, 0o600)
    return true
}

// --- logo ------------------------------------------------------------------

func repoDir() -> String? {
    if let env = ProcessInfo.processInfo.environment["OMACOSY_REPO"], !env.isEmpty { return env }
    let link = HOME + "/.local/bin/theme-set"
    guard FileManager.default.fileExists(atPath: link) else { return nil }
    let resolved = URL(fileURLWithPath: link).resolvingSymlinksInPath().path
    var url = URL(fileURLWithPath: resolved)
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    let path = url.path
    return FileManager.default.fileExists(atPath: path + "/install.sh") ? path : nil
}

func logoFiles() -> [String] {
    var bases: [String] = []
    if let r = repoDir() { bases.append(r + "/helper/assets") }
    bases.append(HOME + "/.local/state/omacosy/assets")
    bases.append(HOME + "/.local/share/omacosy/assets")
    var out: [String] = []
    for b in bases {
        // SVG first: it is the source of the wordmark and the only file that
        // carries the shaded strips. The PNG is a legacy pre-render that a
        // stale copy in the state dir would otherwise shadow.
        for name in ["omacosy-logo.svg", "omacosy-logo.png"] {
            let p = b + "/" + name
            if FileManager.default.fileExists(atPath: p) { out.append(p) }
        }
    }
    return out
}

func mixColor(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let x = a.usingColorSpace(.sRGB) ?? a, y = b.usingColorSpace(.sRGB) ?? b
    return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * t,
                   green: x.greenComponent + (y.greenComponent - x.greenComponent) * t,
                   blue: x.blueComponent + (y.blueComponent - x.blueComponent) * t,
                   alpha: 1)
}

// Omarchy's luminance ladder: one accent colour becomes five shades, "lit" being
// the accent itself, crest and hover mixed toward white, mid and dim toward
// black. The ratios are pulled in from Omarchy's own, which make the top band
// glow and the bottom sink; and they are walked back smoothly as the card
// brightens, so a mid-tone card gets neither a grey top nor a black bottom. A
// light card lands on the gentlest ladder, where neither end reaches the card.
func accentShades(_ accent: NSColor, cardL: CGFloat) -> [NSColor] {
    let strong: [CGFloat] = [0.40, 0.19, 0, -0.21, -0.42]
    let gentle: [CGFloat] = [0.12, 0.06, 0, -0.18, -0.36]
    let t = min(1, max(0, (cardL - 0.10) / 0.35))
    let step = zip(strong, gentle).map { $0 + ($1 - $0) * t }
    return step.map { $0 >= 0 ? mixColor(accent, .white, $0) : mixColor(accent, .black, -$0) }
}

// crest, hover, lit, mid, dim sit at these brightnesses of the wordmark mask
func shade(level: CGFloat, in shades: [NSColor]) -> NSColor {
    let stop: [CGFloat] = [1, 0.75, 0.5, 0.25, 0]
    if level >= 1 { return shades[0] }
    if level <= 0 { return shades[4] }
    for i in 0..<4 where level <= stop[i] && level >= stop[i + 1] {
        return mixColor(shades[i], shades[i + 1], (stop[i] - level) / (stop[i] - stop[i + 1]))
    }
    return shades[2]
}

// the wordmark SVG is a neutral white-to-black ramp. Every pixel is mapped onto
// the accent's shade ladder by its brightness, so each strip becomes a shade of
// the theme colour and the top bands can be lighter than the accent. A flat fill
// cannot do that, and neither can a multiply, which only ever darkens.
func shadedImage(_ image: NSImage, _ color: NSColor, cardL: CGFloat) -> NSImage? {
    let aspect = image.size.width / max(image.size.height, 1)
    let h = 220
    let w = max(1, Int((CGFloat(h) * aspect).rounded()))
    let count = w * h * 4
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    buf.initialize(repeating: 0, count: count)
    defer { buf.deallocate() }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    let shades = accentShades(color, cardL: cardL)
    for i in stride(from: 0, to: count, by: 4) {
        let a = CGFloat(buf[i + 3]) / 255
        if a == 0 { continue }
        let level = (0.299 * CGFloat(buf[i]) + 0.587 * CGFloat(buf[i + 1])
                     + 0.114 * CGFloat(buf[i + 2])) / 255 / a
        let c = shade(level: min(1, level), in: shades)
        buf[i] = UInt8((c.redComponent * a * 255).rounded())
        buf[i + 1] = UInt8((c.greenComponent * a * 255).rounded())
        buf[i + 2] = UInt8((c.blueComponent * a * 255).rounded())
    }
    guard let provider = CGDataProvider(data: Data(bytes: buf, count: count) as CFData),
          let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: w * 4, space: cs,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: true,
                           intent: .defaultIntent) else { return nil }
    let out = NSImage(size: NSSize(width: w, height: h))
    out.addRepresentation(NSBitmapImageRep(cgImage: cg))
    return out
}

func logoImage() -> NSImage? {
    let card = palette.barBG.usingColorSpace(.sRGB) ?? .black
    let cardL = 0.299 * card.redComponent + 0.587 * card.greenComponent + 0.114 * card.blueComponent
    for path in logoFiles() {
        guard let img = NSImage(contentsOfFile: path), img.size.width > 0 else { continue }
        // no alpha check: an SVG loads as a vector rep that reports no alpha
        // even though it renders transparent, which rejected the shipped asset.
        return shadedImage(img, palette.accent, cardL: cardL)
    }
    return nil
}

// --- state -----------------------------------------------------------------

enum WindowManager: Int { case aerospace = 0, omniwm = 1 }
enum CornerMode: Int { case rounded = 0, square = 1 }
enum BarMode: Int { case visible = 0, hidden = 1, auto = 2 }
enum TerminalThemeMode: Int { case own = 0, follow = 1 }

struct DashboardState {
    var wm: WindowManager = .aerospace
    var corners: CornerMode = .rounded
    var bar: BarMode = .visible
    var fullscreen: Bool = false
    var termTheme: TerminalThemeMode = .own
}

let SETTINGS = HOME + "/.config/omacosy/settings.conf"
let BARCONF = HOME + "/.config/omacosy/bar.conf"
let TERMCONF = HOME + "/.config/omacosy/term-auto-theme.conf"
// the setting's earlier home; read only until omacosy-term-auto-theme has
// migrated it, so the row is truthful on the first open after an upgrade
let OLD_AUTOCONF = HOME + "/.config/omacosy/auto-theme.conf"

func readState() -> DashboardState {
    var s = DashboardState()
    if shell("\(HOME)/.local/bin/omacosy-omni active >/dev/null 2>&1").0 == 0 { s.wm = .omniwm }

    let (cc, cout) = shell("/usr/bin/defaults read -g NSConvolutionOverride1 2>/dev/null")
    if cc == 0, let d = Double(cout.trimmingCharacters(in: .whitespacesAndNewlines)), d < 5 {
        s.corners = .square
    }

    var bv = readConfKey(SETTINGS, "AUTOHIDE") ?? ""
    if bv.isEmpty { bv = readConfKey(BARCONF, "autohide") ?? "off" }
    switch bv { case "on": s.bar = .hidden; case "auto": s.bar = .auto; default: s.bar = .visible }

    s.fullscreen = FileManager.default.fileExists(atPath: HOME + "/.config/omacosy/solo-fullscreen")

    // The terminal-following setting. Before the rename it lived in
    // auto-theme.conf as `apps`, with the `auto-theme` master switch as the
    // fallback when apps was never written; an unmigrated install reads
    // exactly the same truth either way.
    if let terminal = readConfKey(TERMCONF, "terminal") {
        s.termTheme = terminal == "on" ? .follow : .own
    } else if let apps = readConfKey(OLD_AUTOCONF, "apps") {
        s.termTheme = apps == "off" ? .own : .follow
    } else {
        s.termTheme = (readConfKey(OLD_AUTOCONF, "auto-theme") ?? "off") == "on" ? .follow : .own
    }
    return s
}

// The radius macOS draws window corners with, when the user has set one.
// omacosy-window-corners writes NSConvolutionOverride1, and this modal's
// borderless card gets no rounding from macOS, so it reads the value back
// to stay consistent with every other window. Absent means macOS's own
// radius, and the card keeps its rounded default.
func windowCornerRadius(_ fallback: CGFloat) -> CGFloat {
    guard let n = UserDefaults.standard.object(forKey: "NSConvolutionOverride1") as? NSNumber
    else { return fallback }
    return CGFloat(n.doubleValue)
}

// --- controls --------------------------------------------------------------

final class SegmentedView: NSView {
    var items: [String] = []
    var index: Int = 0
    var onChange: ((Int) -> Void)?
    private var segFrames: [NSRect] = []

    func sizeThatFits() -> NSSize {
        let f = nerdFont("Regular", 12)
        var w: CGFloat = 4
        for it in items { w += max(advance(it, f) + 22, 46) }
        return NSSize(width: w, height: 28)
    }

    private func layoutSegments() {
        segFrames.removeAll()
        let f = nerdFont("Regular", 12)
        var widths = items.map { max(advance($0, f) + 22, 46) }
        // a frame wider than the natural width shares the slack out evenly,
        // so a stretch-to-fit use keeps every segment flush with its edges
        let slack = bounds.width - 4 - widths.reduce(0, +)
        if slack > 1, !widths.isEmpty {
            let add = slack / CGFloat(widths.count)
            for i in widths.indices { widths[i] += add }
        }
        var x: CGFloat = 2
        for w in widths {
            segFrames.append(NSRect(x: x, y: 2, width: w, height: bounds.height - 4))
            x += w
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        layoutSegments()
        let track = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.55).setFill()
        track.fill()
        let f = nerdFont("Regular", 12)
        let bf = nerdFont("Bold", 12)
        for (i, r) in segFrames.enumerated() {
            let path = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
            if i == index {
                palette.accent.withAlphaComponent(0.9).setFill()
                path.fill()
            } else {
                // a faint accent outline so an unselected choice is legible
                // on a dark card instead of blending into it
                palette.accent.withAlphaComponent(0.30).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            drawMidCenter(items[i], i == index ? bf : f,
                          i == index ? palette.barBG : palette.label,
                          centerX: r.midX, midTop: bounds.height / 2, height: bounds.height)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, r) in segFrames.enumerated() where r.contains(p) {
            if i != index { index = i; needsDisplay = true; onChange?(i) }
            return
        }
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// A drawn checkbox, in the house style. The row's title and description
// carry the words; the box shows the state and is the only hit target.
final class CheckView: NSView {
    var isOn = false { didSet { needsDisplay = true } }
    var onChange: ((Bool) -> Void)?

    func sizeThatFits() -> NSSize { NSSize(width: 22, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 0, y: (bounds.height - 18) / 2, width: 18, height: 18)
        let r = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        if isOn {
            palette.accent.setFill(); r.fill()
            whDrawGlyphCentered("\u{f00c}", in: box, color: palette.barBG, size: 12)
        } else {
            palette.itemBG.withAlphaComponent(0.4).setFill(); r.fill()
            palette.muted.withAlphaComponent(0.5).setStroke()
            r.lineWidth = 1; r.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onChange?(isOn)
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// A single on/off switch, square-ish and themed: a track with a knob that
// slides left (off) or right (on). One control, not two buttons. AppKit's
// NSSwitch exists but is a system-styled pill that would not match the
// hand-drawn dashboard.
final class ToggleView: NSView {
    var isOn = false { didSet { needsDisplay = true } }
    var onChange: ((Bool) -> Void)?

    func sizeThatFits() -> NSSize { NSSize(width: 46, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        if isOn {
            palette.accent.setFill(); track.fill()
        } else {
            palette.itemBG.withAlphaComponent(0.45).setFill(); track.fill()
            palette.muted.withAlphaComponent(0.5).setStroke(); track.lineWidth = 1; track.stroke()
        }
        let ks = bounds.height - 8
        let kx = isOn ? bounds.width - ks - 4 : 4
        let knob = NSBezierPath(roundedRect: NSRect(x: kx, y: 4, width: ks, height: ks),
                                xRadius: 4, yRadius: 4)
        (isOn ? palette.barBG : palette.muted).setFill(); knob.fill()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onChange?(isOn)
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ButtonView: NSView {
    var title = "Save" { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 12
    // icon buttons centre on the glyph's own box; text buttons centre on cap
    // height, which reads better for words
    var centeredByBounds = false
    // a quieter fill for the second action in a dialog or footer row
    var secondary = false { didSet { needsDisplay = true } }
    var busy = false { didSet { needsDisplay = true } }
    // what a busy button says, for work that is not a save
    var busyTitle = "Saving…"
    var danger = false { didSet { needsDisplay = true } }
    // a brief dim on the press, so a tap always shows even when the action
    // it fires is instant
    var highlighted = false { didSet { needsDisplay = true } }
    // 0...1 draws a left-to-right fill over the button; -1 hides it, for work
    // a click starts (Apply to Palette's full-resolution render).
    var progress: CGFloat = -1 { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        if secondary && !busy {
            palette.itemBG.withAlphaComponent(0.35).setFill()
            r.fill()
            palette.muted.withAlphaComponent(0.35).setStroke()
            r.lineWidth = 1
            r.stroke()
        } else {
            (busy ? palette.muted : (danger ? NSColor.systemRed : palette.accent)).setFill()
            r.fill()
        }
        if progress >= 0 {
            // whole-button left-to-right fill while the work runs
            NSGraphicsContext.saveGraphicsState()
            r.addClip()
            NSColor.black.withAlphaComponent(0.28).setFill()
            NSRect(x: 0, y: 0, width: bounds.width * min(max(progress, 0), 1),
                   height: bounds.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let text = busy ? busyTitle : title
        let font = nerdFont("Bold", fontSize)
        let ink = (secondary && !busy) ? palette.label : palette.barBG
        if centeredByBounds {
            whDrawGlyphCentered(text, in: bounds, color: ink, size: fontSize)
        } else {
            drawMidCenter(text, font, ink,
                          centerX: bounds.midX, midTop: bounds.height / 2, height: bounds.height)
        }
        if highlighted {
            NSColor.black.withAlphaComponent(0.22).setFill()
            r.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !busy else { return }
        highlighted = true
        needsDisplay = true
        onClick?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.highlighted = false
            self?.needsDisplay = true
        }
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- custom scrollbar ------------------------------------------------------
// System scrollers are overlay-styled on macOS and float over the content,
// which put one on top of the "Add App" button. This draws a squared,
// accent-coloured thumb in a reserved strip instead, and takes its place.

final class CustomScroller: NSView {
    weak var scrollView: NSScrollView?
    private var dragging = false
    private var dragStartY: CGFloat = 0
    private var dragStartOrigin: CGFloat = 0
    private let minThumb: CGFloat = 30

    override var isFlipped: Bool { true }

    private var docH: CGFloat { scrollView?.documentView?.frame.height ?? 0 }
    private var clipH: CGFloat { scrollView?.contentSize.height ?? 0 }
    private var maxScroll: CGFloat { max(0, docH - clipH) }
    private var thumbH: CGFloat {
        guard docH > clipH, docH > 0 else { return 0 }
        return max(minThumb, bounds.height * clipH / docH)
    }
    private func originY() -> CGFloat { scrollView?.contentView.bounds.origin.y ?? 0 }
    private var frac: CGFloat { maxScroll > 0 ? originY() / maxScroll : 1 }
    private var thumbTop: CGFloat { (1 - frac) * (bounds.height - thumbH) }

    func refresh() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let h = thumbH
        guard h > 0, h < bounds.height - 1 else { return }
        palette.itemBG.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: bounds).fill()
        let r = NSRect(x: 0, y: thumbTop, width: bounds.width, height: h)
        palette.accent.withAlphaComponent(0.85).setFill()
        NSBezierPath(rect: r).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard thumbH > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        if NSRect(x: 0, y: thumbTop, width: bounds.width, height: thumbH).contains(p) {
            dragging = true
            dragStartY = p.y
            dragStartOrigin = originY()
        } else {
            let t = (p.y - thumbH / 2) / max(1, bounds.height - thumbH)
            setOrigin(max(0, min(1, 1 - t)) * maxScroll)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, maxScroll > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        let delta = (p.y - dragStartY) / max(1, bounds.height - thumbH)
        let f = max(0, min(1, dragStartOrigin / maxScroll - delta))
        setOrigin(f * maxScroll)
    }

    override func mouseUp(with event: NSEvent) { dragging = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setOrigin(_ o: CGFloat) {
        guard let sv = scrollView else { return }
        sv.contentView.scroll(to: NSPoint(x: 0, y: o))
        sv.reflectScrolledClipView(sv.contentView)
        needsDisplay = true
    }
}

// --- arrow-key scrolling ---------------------------------------------------
// A positive dy scrolls towards later content ("down"). Every document view
// here is non-flipped, so later content sits at a *smaller* y origin: subtract
// dy. Used by the arrow keys in the app picker and the dashboard's own tabs.

func scrollBy(_ sv: NSScrollView, _ dy: CGFloat) {
    guard let doc = sv.documentView else { return }
    let clip = sv.contentView
    let maxY = max(0, doc.frame.height - clip.bounds.height)
    let y = max(0, min(maxY, clip.bounds.origin.y - dy))
    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
    sv.reflectScrolledClipView(clip)
}

// A tab with one vertical list the arrow keys can move.
protocol ScrollStepTab: AnyObject {
    func scrollStep(_ dy: CGFloat)
}

// --- options tab -----------------------------------------------------------

struct OptionRow {
    let category: String
    let title: String
    let desc: String
    let seg: SegmentedView?
    let slider: OpacitySliderView?
    let check: CheckView?
    let toggle: ToggleView?

    init(category: String, title: String, desc: String,
         seg: SegmentedView? = nil, slider: OpacitySliderView? = nil,
         check: CheckView? = nil, toggle: ToggleView? = nil) {
        self.category = category
        self.title = title
        self.desc = desc
        self.seg = seg
        self.slider = slider
        self.check = check
        self.toggle = toggle
    }
}

final class OptionsDocView: NSView {
    var rows: [OptionRow] = []
    private let rowH: CGFloat = 58
    private let catH: CGFloat = 30
    private let sectionGap: CGFloat = 6
    private let topPad: CGFloat = 6

    func contentHeight() -> CGFloat {
        topPad + CGFloat(rows.count) * (catH + rowH + sectionGap) + 10
    }

    override func layout() {
        super.layout()
        var top = topPad
        for row in rows {
            top += catH
            if let seg = row.seg {
                let sz = seg.sizeThatFits()
                let segTop = top + (rowH - sz.height) / 2
                seg.frame = NSRect(x: bounds.width - sz.width,
                                   y: bounds.height - segTop - sz.height,
                                   width: sz.width, height: sz.height)
            }
            if let slider = row.slider {
                let w: CGFloat = 220
                slider.frame = NSRect(x: bounds.width - w, y: bounds.height - (top + rowH / 2) - 7,
                                      width: w, height: 14)
            }
            if let check = row.check {
                let sz = check.sizeThatFits()
                let cTop = top + (rowH - sz.height) / 2
                check.frame = NSRect(x: bounds.width - sz.width,
                                     y: bounds.height - cTop - sz.height,
                                     width: sz.width, height: sz.height)
            }
            if let toggle = row.toggle {
                let sz = toggle.sizeThatFits()
                let tTop = top + (rowH - sz.height) / 2
                toggle.frame = NSRect(x: bounds.width - sz.width,
                                      y: bounds.height - tTop - sz.height,
                                      width: sz.width, height: sz.height)
            }
            top += rowH + sectionGap
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        var top = topPad
        for row in rows {
            drawTopLeft(row.category, nerdFont("Bold", 13), palette.accent,
                        x: 0, top: top, height: bounds.height)
            top += catH
            let rowMid = top + 20
            drawMidLeft(row.title, nerdFont("Bold", 13), palette.label,
                        x: 0, midTop: rowMid, height: bounds.height)
            drawMidLeft(row.desc, nerdFont("Regular", 11), palette.muted,
                        x: 0, midTop: rowMid + 18, height: bounds.height)
            if let slider = row.slider {
                drawMidLeft(slider.value.map { "\($0)%" } ?? "—", nerdFont("Bold", 11),
                            palette.label, x: bounds.width - 264, midTop: rowMid, height: bounds.height)
            }
            top += rowH
            palette.muted.withAlphaComponent(0.25).setFill()
            NSRect(x: 0, y: bounds.height - top - 0.5, width: bounds.width, height: 1).fill()
            top += sectionGap
        }
    }
}

final class OptionsTabView: NSView, ScrollStepTab {
    private(set) var rows: [OptionRow] = []
    func scrollStep(_ dy: CGFloat) { scrollBy(scroll, dy) }
    func refreshColors() {
        needsDisplay = true
        doc.needsDisplay = true
        for r in rows { r.seg?.needsDisplay = true }
        for r in rows { r.check?.needsDisplay = true }
        for r in rows { r.toggle?.needsDisplay = true }
        scroller.refresh()
    }
    private var original = DashboardState()
    private var status = ""
    private let scroll = NSScrollView()
    private let doc = OptionsDocView()
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8
    let saveButton = ButtonView()
    // the root draws the card, which follows the window-corner setting; a
    // saved change must redraw it at once, not wait for a tab switch
    var onApplied: (() -> Void)?
    private let bottomBarH: CGFloat = 54
    private var lastDocH: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = doc
        addSubview(scroller)
        scroller.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        build()
        saveButton.title = "Save"
        saveButton.onClick = { [weak self] in self?.save() }
        addSubview(saveButton)
    }
    @objc private func scrolled() { scroller.refresh() }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeSeg(_ items: [String], _ idx: Int) -> SegmentedView {
        let s = SegmentedView()
        s.items = items
        s.index = idx
        return s
    }

    private func build() {
        original = readState()

        let wmSeg = makeSeg(["AeroSpace", "OmniWM"], original.wm.rawValue)
        let cornerSeg = makeSeg(["Rounded", "Square"], original.corners.rawValue)
        let barSeg = makeSeg(["Visible", "Hidden", "Auto"], original.bar.rawValue)
        let fsToggle = ToggleView()
        fsToggle.isOn = original.fullscreen
        let atSeg = makeSeg(["Own Colours", "Follow Theme"], original.termTheme.rawValue)

        let opacitySlider = OpacitySliderView()
        opacitySlider.value = readGlobalToolOpacity() ?? readTerminalOpacity() ?? 100
        opacitySlider.onChange = { [weak self] _ in self?.doc.needsDisplay = true }

        let nsfwToggle = ToggleView()
        nsfwToggle.isOn = WHConfig.load().hideNSFW

        rows = [
            OptionRow(category: "Window Manager", title: "Window Manager",
                      desc: "Which tiling manager Omacosy switches to. Switching reloads Omacosy for a moment.",
                      seg: wmSeg),
            OptionRow(category: "Windows", title: "Window Corners",
                      desc: "Radius macOS draws window corners with; the ring follows.", seg: cornerSeg),
            OptionRow(category: "Bar", title: "Menu Bar Mode",
                      desc: "Keep the bar visible, let it hide at rest, or follow the display.", seg: barSeg),
            OptionRow(category: "Fullscreen", title: "Full Screen Mode",
                      desc: "A workspace holding one window fills the display.", toggle: fsToggle),
            OptionRow(category: "Themes", title: "Terminal Auto-Theme",
                      desc: "Let the terminal and its apps follow the wallpaper theme, or keep their own colours.", seg: atSeg),
            OptionRow(category: "Appearance", title: "Terminal Opacity",
                      desc: "How see-through the terminal and its tools are. Every theme that inherits it follows.",
                      slider: opacitySlider),
            OptionRow(category: "Content", title: "Hide NSFW Content",
                      desc: "Hide adult wallhaven results and anything downloaded from them, everywhere. Nothing is deleted.",
                      toggle: nsfwToggle),
        ]
        doc.rows = rows
        for r in rows {
            if let s = r.seg { doc.addSubview(s) }
            if let sl = r.slider { doc.addSubview(sl) }
            if let c = r.check { doc.addSubview(c) }
            if let t = r.toggle { doc.addSubview(t) }
        }
    }

    override func layout() {
        super.layout()
        let saveW: CGFloat = 96, saveH: CGFloat = 24
        saveButton.frame = NSRect(x: (bounds.width - saveW) / 2,
                                  y: (bottomBarH - saveH) / 2, width: saveW, height: saveH)
        let scrollH = max(0, bounds.height - bottomBarH)
        scroll.frame = NSRect(x: 0, y: bottomBarH, width: max(0, bounds.width - scrollerW - 14), height: scrollH)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: bottomBarH, width: scrollerW, height: scrollH)
        scroller.refresh()
        let w = scroll.contentSize.width
        if w > 0, abs(doc.frame.width - w) > 0.5 {
            doc.frame.size.width = w
            let h = doc.contentHeight()
            doc.frame.size.height = h
            doc.needsLayout = true
            if h != lastDocH {
                lastDocH = h
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, h - scroll.contentSize.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bottomBarH - 0.5, width: bounds.width, height: 1).fill()
        if !status.isEmpty {
            drawMidLeft(status, nerdFont("Regular", 11), palette.muted,
                        x: 0, midTop: bounds.height - bottomBarH / 2, height: bounds.height)
        }
    }

    private func save() {
        let wm = WindowManager(rawValue: rows[0].seg!.index) ?? original.wm
        let corners = CornerMode(rawValue: rows[1].seg!.index) ?? original.corners
        let bar = BarMode(rawValue: rows[2].seg!.index) ?? original.bar
        let fullscreen = rows[3].toggle?.isOn ?? original.fullscreen
        let termTheme = TerminalThemeMode(rawValue: rows[4].seg!.index) ?? original.termTheme

        // the machine-wide terminal opacity
        var opacityChanged = false
        if let slider = rows.first(where: { $0.slider != nil })?.slider,
           slider.value != readGlobalToolOpacity() {
            writeGlobalToolOpacity(slider.value)
            opacityChanged = true
        }

        // the global NSFW hide lives in the wallhaven preferences
        var nsfwChanged = false
        if let toggle = rows.first(where: { $0.category == "Content" })?.toggle {
            var cfg = WHConfig.load()
            if cfg.hideNSFW != toggle.isOn { cfg.hideNSFW = toggle.isOn; cfg.save(); nsfwChanged = true }
        }

        var steps: [String] = []
        if wm != original.wm {
            steps.append("\(HOME)/.local/bin/omacosy-wm-switch \(wm == .omniwm ? "omniwm" : "aerospace")")
        }
        if corners != original.corners {
            setConfKey(SETTINGS, "WINDOW_CORNER", corners == .square ? "0.1" : "")
            steps.append("\(HOME)/.local/bin/omacosy-window-corners \(corners == .square ? "square" : "round")")
        }
        if bar != original.bar {
            let v = ["off", "on", "auto"][bar.rawValue]
            steps.append("\(HOME)/.local/bin/omacosy-bar-autohide \(v)")
        }
        if fullscreen != original.fullscreen {
            steps.append("\(HOME)/.local/bin/omacosy-solo-fullscreen \(fullscreen ? "on" : "off")")
        }
        if termTheme != original.termTheme {
            steps.append("\(HOME)/.local/bin/omacosy-term-auto-theme \(termTheme == .follow ? "on" : "off")")
        }

        guard !steps.isEmpty || opacityChanged || nsfwChanged else {
            status = "No changes"
            needsDisplay = true
            return
        }

        saveButton.busy = true
        status = "Applying…"
        needsDisplay = true

        DispatchQueue.global().async { [weak self] in
            var last = ""
            for step in steps {
                let (code, out) = shell(step)
                last = out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
                if code != 0 {
                    DispatchQueue.main.async {
                        self?.status = "Error: \(step.split(separator: " ").last ?? "") — \(last)"
                        self?.saveButton.busy = false
                        self?.needsDisplay = true
                    }
                    return
                }
            }
            DispatchQueue.main.async {
                self?.original = readState()
                self?.status = "Saved"
                self?.saveButton.busy = false
                self?.needsDisplay = true
                self?.onApplied?()
            }
        }
    }
}

// --- workspaces tab --------------------------------------------------------

struct AppInfo {
    let bundleID: String
    let name: String
    let path: String
}

struct ScreenInfo {
    let name: String
    let workspaces: [String]
}

var appIconCache: [String: NSImage] = [:]

func iconForBundle(_ id: String) -> NSImage? {
    if let c = appIconCache[id] { return c }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
    let img = NSWorkspace.shared.icon(forFile: url.path)
    appIconCache[id] = img
    return img
}

func installedApps() -> [AppInfo] {
    let dirs = ["/Applications", "/System/Applications", HOME + "/Applications"]
    var seen = Set<String>()
    var out: [AppInfo] = []
    for dir in dirs {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
        for e in entries where e.hasSuffix(".app") {
            let path = dir + "/" + e
            let plist = path + "/Contents/Info.plist"
            guard let d = NSDictionary(contentsOfFile: plist),
                  let bid = d["CFBundleIdentifier"] as? String, !bid.isEmpty,
                  !seen.contains(bid) else { continue }
            seen.insert(bid)
            let name = (d["CFBundleDisplayName"] as? String)
                ?? (d["CFBundleName"] as? String)
                ?? String(e.dropLast(4))
            out.append(AppInfo(bundleID: bid, name: name, path: path))
        }
    }
    return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

func numericAsc(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: .numeric) == .orderedAscending
}

func screensInfo() -> [ScreenInfo] {
    if shell("\(HOME)/.local/bin/omacosy-omni active >/dev/null 2>&1").0 == 0 {
        let (c1, out1) = shell("\(HOME)/.local/bin/omacosy-omni query displays 2>/dev/null")
        let (c2, out2) = shell("\(HOME)/.local/bin/omacosy-omni query workspaces 2>/dev/null")
        if c1 == 0, c2 == 0,
           let d1 = out1.data(using: .utf8), let d2 = out2.data(using: .utf8),
           let r1 = (try? JSONSerialization.jsonObject(with: d1)) as? [String: Any],
           let r2 = (try? JSONSerialization.jsonObject(with: d2)) as? [String: Any],
           let p1 = (r1["result"] as? [String: Any])?["payload"] as? [String: Any],
           let p2 = (r2["result"] as? [String: Any])?["payload"] as? [String: Any],
           let displays = p1["displays"] as? [[String: Any]],
           let workspaces = p2["workspaces"] as? [[String: Any]] {
            var byDisp: [String: [String]] = [:]
            for w in workspaces {
                guard let did = (w["display"] as? [String: Any])?["id"] as? String,
                      let dn = w["displayName"] as? String else { continue }
                byDisp[did, default: []].append(dn)
            }
            let ordered = displays.sorted {
                (($0["isMain"] as? Bool) ?? false) && !(($1["isMain"] as? Bool) ?? false)
            }
            return ordered.compactMap { d in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                return ScreenInfo(name: name, workspaces: (byDisp[id] ?? []).sorted(by: numericAsc))
            }
        }
    }
    let (_, out) = shell("/opt/homebrew/bin/aerospace list-monitors --format '%{monitor-name}' 2>/dev/null")
    let names = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    var res: [ScreenInfo] = []
    for (i, n) in names.enumerated() {
        if i == 0 { res.append(ScreenInfo(name: n, workspaces: (1...9).map(String.init))) }
        else { res.append(ScreenInfo(name: n, workspaces: (11...19).map(String.init))) }
    }
    return res
}

// APP_WORKSPACE_RULES is a multi-line shell string; read the block between
// the quotes rather than a single line
func readWorkspaceRules() -> [(String, String)] {
    guard let text = try? String(contentsOfFile: SETTINGS, encoding: .utf8) else { return [] }
    var out: [(String, String)] = []
    var inBlock = false
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if !inBlock {
            guard line.hasPrefix("APP_WORKSPACE_RULES=") else { continue }
            let after = line.dropFirst("APP_WORKSPACE_RULES=".count)
            if after.hasPrefix("\"") {
                let rest = after.dropFirst()
                if let close = rest.firstIndex(of: "\"") {
                    let one = rest[rest.startIndex..<close]
                    for t in one.split(separator: "\n") {
                        let parts = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                        if parts.count >= 2 { out.append((parts[0], parts[1])) }
                    }
                } else {
                    inBlock = true
                }
            }
            continue
        }
        if line.contains("\"") { inBlock = false; continue }
        let t = line.trimmingCharacters(in: .whitespaces)
        let parts = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if parts.count >= 2 { out.append((parts[0], parts[1])) }
    }
    return out
}

@discardableResult
func writeWorkspaceRules(_ pairs: [(String, String)]) -> Bool {
    guard let text = try? String(contentsOfFile: SETTINGS, encoding: .utf8) else { return false }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var out: [String] = []
    var i = 0
    var replaced = false
    while i < lines.count {
        let line = lines[i]
        if line.hasPrefix("APP_WORKSPACE_RULES=") && !replaced {
            out.append("APP_WORKSPACE_RULES=\"")
            for (app, ws) in pairs { out.append("\(app)    \(ws)") }
            out.append("\"")
            replaced = true
            let after = line.dropFirst("APP_WORKSPACE_RULES=".count)
            if after.hasPrefix("\"") && after.dropFirst().contains("\"") {
                i += 1
            } else {
                i += 1
                while i < lines.count {
                    if lines[i].contains("\"") { break }
                    i += 1
                }
                i += 1
            }
            continue
        }
        out.append(line)
        i += 1
    }
    if !replaced {
        out.append("APP_WORKSPACE_RULES=\"")
        for (app, ws) in pairs { out.append("\(app)    \(ws)") }
        out.append("\"")
    }
    var result = out.joined(separator: "\n")
    if !result.hasSuffix("\n") { result += "\n" }
    do { try result.write(toFile: SETTINGS, atomically: true, encoding: .utf8); return true }
    catch { return false }
}

final class AppListView: NSView {
    var apps: [AppInfo] = []
    var onPick: ((String) -> Void)?
    var selected: Int = 0
    let rowH: CGFloat = 30

    private func rowRect(_ i: Int) -> NSRect {
        let top = CGFloat(i) * rowH
        return NSRect(x: 0, y: bounds.height - top - rowH, width: bounds.width, height: rowH)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, a) in apps.enumerated() {
            let r = rowRect(i)
            if i == selected, apps.indices.contains(selected) {
                // the same accent the custom scrollers use, so a chosen row
                // reads as "the one the arrows are on"
                palette.accent.withAlphaComponent(0.85).setFill()
                r.fill()
            } else if i % 2 == 1 {
                palette.itemBG.withAlphaComponent(0.25).setFill()
                r.fill()
            }
            if let ic = iconForBundle(a.bundleID) {
                ic.draw(in: NSRect(x: 6, y: r.midY - 8, width: 16, height: 16))
            }
            drawMidLeft(a.name, nerdFont("Regular", 12),
                        i == selected ? palette.barBG : palette.label,
                        x: 30, midTop: CGFloat(i) * rowH + rowH / 2, height: bounds.height)
        }
    }

    func moveSelection(_ delta: Int) {
        guard !apps.isEmpty else { return }
        let next = max(0, min(apps.count - 1, selected + delta))
        guard next != selected else { return }
        selected = next
        needsDisplay = true
        ensureVisible()
    }

    // keep the highlighted row inside the viewport as the arrows walk it
    private func ensureVisible() {
        guard let sv = enclosingScrollView, apps.indices.contains(selected) else { return }
        let r = rowRect(selected)
        let visible = sv.documentVisibleRect
        var origin = sv.contentView.bounds.origin
        if r.maxY > visible.maxY { origin.y = r.maxY - visible.height }
        else if r.minY < visible.minY { origin.y = r.minY }
        else { return }
        let maxY = max(0, bounds.height - sv.contentSize.height)
        origin.y = max(0, min(maxY, origin.y))
        sv.contentView.scroll(to: origin)
        sv.reflectScrolledClipView(sv.contentView)
    }

    private var trackingArea: NSTrackingArea?

    // the highlighting follows the mouse as well as the arrows, so the row
    // under the pointer is always the one Enter would apply
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((bounds.height - p.y) / rowH)
        guard apps.indices.contains(i), i != selected else { return }
        selected = i
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((bounds.height - p.y) / rowH)
        if apps.indices.contains(i) {
            selected = i
            needsDisplay = true
            onPick?(apps[i].bundleID)
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PickerRoot: NSView {
    let search = NSSearchField()
    let scroll = NSScrollView()
    let list = AppListView()
    var titleText: String?
    var showsSearch = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(search)
        addSubview(scroll)
        scroll.documentView = list
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        palette.barBG.setFill()
        r.fill()
        palette.accent.setStroke()
        r.lineWidth = 1
        r.stroke()
        if !showsSearch, let t = titleText {
            drawTopLeft(t, nerdFont("Bold", 12), palette.accent, x: 12, top: 9, height: bounds.height)
        }
    }

    override func layout() {
        super.layout()
        relayout()
    }

    func relayout() {
        let pad: CGFloat = 10
        let headerH: CGFloat = showsSearch ? 26 + 8 : 32
        if showsSearch {
            search.isHidden = false
            search.frame = NSRect(x: pad, y: bounds.height - pad - 26,
                                  width: max(0, bounds.width - pad * 2), height: 26)
        } else {
            search.isHidden = true
        }
        scroll.frame = NSRect(x: pad, y: pad, width: max(0, bounds.width - pad * 2),
                              height: max(0, bounds.height - pad * 2 - headerH))
        if scroll.documentView !== list { scroll.documentView = list }
        let w = max(scroll.contentSize.width, 10)
        list.frame = NSRect(x: 0, y: 0, width: w,
                            height: max(scroll.contentSize.height, CGFloat(list.apps.count) * list.rowH))
        showTop()
    }

    // the list is drawn top-down inside a non-flipped document view, so
    // "the top of the list" is the document's maximum scroll offset
    func showTop() {
        let maxY = max(0, list.frame.height - scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

final class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// --- delete confirmation ---------------------------------------------------

// A small centred card that asks before a wallpaper or theme is removed. The
// checkboxes choose what goes: the file to the Trash, and/or the editions
// built from it. It is a child window, so it sits above the modal and
// dismisses with it. Nothing here hard-deletes: the file goes to the Trash.
final class DeleteConfirmView: NSView {
    var titleText = "" { didSet { needsDisplay = true } }
    var subtitleText = "" { didSet { needsDisplay = true } }
    var labels: [String] = []
    private(set) var values: [Bool] = []
    private var checks: [CheckView] = []
    private let cancel = ButtonView()
    private let deleteButton = ButtonView()
    var onCancel: (() -> Void)?
    var onDelete: (() -> Void)?

    init(width: CGFloat, labels: [String], defaults: [Bool], subtitle: String) {
        self.labels = labels
        self.values = defaults
        self.subtitleText = subtitle
        let height = 96 + CGFloat(max(labels.count, 0)) * 30 + 46
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        wantsLayer = true
        for (i, _) in labels.enumerated() {
            let c = CheckView()
            c.isOn = defaults[i]
            c.onChange = { [weak self] on in
                guard let self, i < self.values.count else { return }
                self.values[i] = on
            }
            addSubview(c)
            checks.append(c)
        }
        cancel.title = "Cancel"
        cancel.secondary = true
        cancel.fontSize = 12
        cancel.onClick = { [weak self] in self?.onCancel?() }
        addSubview(cancel)
        deleteButton.title = "Delete"
        deleteButton.danger = true
        deleteButton.fontSize = 12
        deleteButton.onClick = { [weak self] in self?.onDelete?() }
        addSubview(deleteButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let bw: CGFloat = 96, bh: CGFloat = 26
        deleteButton.frame = NSRect(x: bounds.width - 20 - bw, y: 18, width: bw, height: bh)
        cancel.frame = NSRect(x: bounds.width - 20 - bw - 8 - bw, y: 18, width: bw, height: bh)
        var top: CGFloat = 78
        for c in checks {
            c.frame = NSRect(x: 20, y: bounds.height - top - 18, width: 22, height: 18)
            top += 30
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let corner = min(windowCornerRadius(12), min(bounds.width, bounds.height) / 2)
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: corner, yRadius: corner)
        palette.barBG.setFill(); card.fill()
        palette.accent.withAlphaComponent(0.55).setStroke(); card.lineWidth = 1; card.stroke()

        let tf = nerdFont("Bold", 13)
        drawTopLeft(truncate(titleText, tf, bounds.width - 40), tf, palette.label,
                    x: 20, top: 16, height: bounds.height)
        drawTopLeft(truncate(subtitleText, nerdFont("Regular", 11), bounds.width - 40),
                    nerdFont("Regular", 11), palette.muted, x: 20, top: 40, height: bounds.height)
        var top: CGFloat = 78
        for lab in labels {
            drawMidLeft(lab, nerdFont("Regular", 12), palette.label,
                        x: 50, midTop: top + 9, height: bounds.height)
            top += 30
        }
    }
}

final class DeleteConfirm: NSObject {
    private static var current: DeleteConfirm?
    private let window: PickerWindow
    private let root: DeleteConfirmView
    private var keyMonitor: Any?

    private init(title: String, subtitle: String, labels: [String], defaults: [Bool],
                 onDelete: @escaping ([Bool]) -> Void) {
        let width: CGFloat = 420
        root = DeleteConfirmView(width: width, labels: labels, defaults: defaults, subtitle: subtitle)
        root.titleText = title
        window = PickerWindow(contentRect: root.frame,
                              styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
        root.onCancel = { [weak self] in self?.close() }
        root.onDelete = { [weak self] in
            let vals = self?.root.values ?? []
            self?.close()
            onDelete(vals)
        }
    }

    static func present(from host: NSView, title: String, subtitle: String,
                        labels: [String] = [], defaults: [Bool] = [],
                        onDelete: @escaping ([Bool]) -> Void) {
        current?.close()
        let d = DeleteConfirm(title: title, subtitle: subtitle, labels: labels,
                              defaults: defaults, onDelete: onDelete)
        guard let win = host.window else { return }
        let f = win.frame
        let x = f.midX - d.window.frame.width / 2
        let y = f.midY - d.window.frame.height / 2
        d.window.setFrameOrigin(NSPoint(x: x, y: y))
        current = d
        win.addChildWindow(d.window, ordered: .above)
        d.show()
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            if e.keyCode == 53 { self?.close(); return nil }               // Esc
            if e.keyCode == 36 || e.keyCode == 76 { self?.root.onDelete?(); return nil }
            return e
        }
    }

    private func close() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        DeleteConfirm.current = nil
    }
}

// --- import collision ------------------------------------------------------

// A small centred card for a theme import whose id is already in the library.
// The engine refuses without a flag, so the UI asks: Rename keeps both (the
// import gets a fresh id), Replace overwrites the saved record.
final class ImportConflictView: NSView {
    var titleText = "" { didSet { needsDisplay = true } }
    var subtitleText = "" { didSet { needsDisplay = true } }
    private let renameButton = ButtonView()
    private let replaceButton = ButtonView()
    var onRename: (() -> Void)?
    var onReplace: (() -> Void)?

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 132))
        wantsLayer = true
        renameButton.title = "Rename"
        renameButton.secondary = true
        renameButton.fontSize = 12
        renameButton.onClick = { [weak self] in self?.onRename?() }
        addSubview(renameButton)
        replaceButton.title = "Replace"
        replaceButton.danger = true
        replaceButton.fontSize = 12
        replaceButton.onClick = { [weak self] in self?.onReplace?() }
        addSubview(replaceButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let bw: CGFloat = 96, bh: CGFloat = 26
        replaceButton.frame = NSRect(x: bounds.width - 20 - bw, y: 18, width: bw, height: bh)
        renameButton.frame = NSRect(x: bounds.width - 20 - bw - 8 - bw, y: 18, width: bw, height: bh)
    }

    override func draw(_ dirtyRect: NSRect) {
        let corner = min(windowCornerRadius(12), min(bounds.width, bounds.height) / 2)
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: corner, yRadius: corner)
        palette.barBG.setFill(); card.fill()
        palette.accent.withAlphaComponent(0.55).setStroke(); card.lineWidth = 1; card.stroke()
        let tf = nerdFont("Bold", 13)
        drawTopLeft(truncate(titleText, tf, bounds.width - 40), tf, palette.label,
                    x: 20, top: 22, height: bounds.height)
        drawTopLeft(truncate(subtitleText, nerdFont("Regular", 11), bounds.width - 40),
                    nerdFont("Regular", 11), palette.muted, x: 20, top: 50, height: bounds.height)
    }
}

final class ImportConflict: NSObject {
    private static var current: ImportConflict?
    private let window: PickerWindow
    private let root: ImportConflictView
    private var keyMonitor: Any?

    private init(title: String, subtitle: String,
                 onRename: @escaping () -> Void, onReplace: @escaping () -> Void) {
        let width: CGFloat = 420
        root = ImportConflictView(width: width)
        root.titleText = title
        root.subtitleText = subtitle
        window = PickerWindow(contentRect: root.frame,
                              styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
        root.onRename = { [weak self] in self?.close(); onRename() }
        root.onReplace = { [weak self] in self?.close(); onReplace() }
    }

    static func present(from host: NSView, title: String, subtitle: String,
                        onRename: @escaping () -> Void, onReplace: @escaping () -> Void) {
        current?.close()
        let c = ImportConflict(title: title, subtitle: subtitle,
                               onRename: onRename, onReplace: onReplace)
        guard let win = host.window else { return }
        let f = win.frame
        c.window.setFrameOrigin(NSPoint(x: f.midX - c.window.frame.width / 2,
                                        y: f.midY - c.window.frame.height / 2))
        current = c
        win.addChildWindow(c.window, ordered: .above)
        c.show()
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            if e.keyCode == 53 { self?.close(); return nil }               // Esc cancels
            if e.keyCode == 36 || e.keyCode == 76 { self?.root.onRename?(); return nil }
            return e
        }
    }

    private func close() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        ImportConflict.current = nil
    }
}

// --- name prompt -----------------------------------------------------------

// A small centred card that asks for a theme's name when an action creates a
// new one — Save As…, or Export of a still-unsaved draft. Naming here is
// clearly "a new theme", where typing in the editor's header field reads as
// renaming the theme that is open. A name collision is shown inline and the
// card stays open.
final class NamePromptView: NSView {
    var titleText = "" { didSet { needsDisplay = true } }
    var subtitleText = "" { didSet { needsDisplay = true } }
    var errorText = "" { didSet { needsDisplay = true } }
    let field = NSTextField()
    private let cancelButton = ButtonView()
    private let confirmButton = ButtonView()
    var onCancel: (() -> Void)?
    var onConfirm: ((String) -> Void)?

    init(width: CGFloat, confirmTitle: String, initial: String, subtitle: String) {
        self.subtitleText = subtitle
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 176))
        wantsLayer = true
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = palette.label
        field.font = nerdFont("Regular", 13)
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.stringValue = initial
        addSubview(field)
        cancelButton.title = "Cancel"
        cancelButton.secondary = true
        cancelButton.fontSize = 12
        cancelButton.onClick = { [weak self] in self?.onCancel?() }
        addSubview(cancelButton)
        confirmButton.title = confirmTitle
        confirmButton.fontSize = 12
        confirmButton.onClick = { [weak self] in self?.commit() }
        addSubview(confirmButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func commit() {
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorText = "Give the theme a name."
            return
        }
        onConfirm?(name)
    }

    override func layout() {
        super.layout()
        let bw: CGFloat = 96, bh: CGFloat = 26
        confirmButton.frame = NSRect(x: bounds.width - 20 - bw, y: 18, width: bw, height: bh)
        cancelButton.frame = NSRect(x: bounds.width - 20 - bw - 8 - bw, y: 18, width: bw, height: bh)
        field.frame = NSRect(x: 28, y: bounds.height - 114, width: bounds.width - 56, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let corner = min(windowCornerRadius(12), min(bounds.width, bounds.height) / 2)
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: corner, yRadius: corner)
        palette.barBG.setFill(); card.fill()
        palette.accent.withAlphaComponent(0.55).setStroke(); card.lineWidth = 1; card.stroke()

        let tf = nerdFont("Bold", 13)
        drawTopLeft(truncate(titleText, tf, bounds.width - 48), tf, palette.label,
                    x: 24, top: 20, height: bounds.height)
        drawTopLeft(truncate(subtitleText, nerdFont("Regular", 11), bounds.width - 48),
                    nerdFont("Regular", 11), palette.muted, x: 24, top: 44, height: bounds.height)
        // the drawn box, because AppKit lays a taller field's text near its top
        let box = NSRect(x: 24, y: bounds.height - 116, width: bounds.width - 48, height: 24)
        palette.itemBG.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        palette.muted.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        border.lineWidth = 1; border.stroke()
        if !errorText.isEmpty {
            drawTopLeft(truncate(errorText, nerdFont("Regular", 11), bounds.width - 48),
                        nerdFont("Regular", 11), .systemRed, x: 24, top: 68, height: bounds.height)
        }
    }
}

final class NamePrompt: NSObject {
    private static var current: NamePrompt?
    private let window: PickerWindow
    private let root: NamePromptView
    private var keyMonitor: Any?
    private let onConfirm: (String) -> Void

    private init(title: String, subtitle: String, confirmTitle: String, initial: String,
                 onConfirm: @escaping (String) -> Void) {
        self.onConfirm = onConfirm
        let width: CGFloat = 420
        root = NamePromptView(width: width, confirmTitle: confirmTitle,
                              initial: initial, subtitle: subtitle)
        root.titleText = title
        window = PickerWindow(contentRect: root.frame,
                              styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
        root.onCancel = { [weak self] in self?.close() }
        root.onConfirm = { [weak self] name in self?.onConfirm(name) }
    }

    static func present(from host: NSView, title: String, subtitle: String,
                        confirmTitle: String, initial: String,
                        onConfirm: @escaping (String) -> Void) {
        current?.close()
        let p = NamePrompt(title: title, subtitle: subtitle, confirmTitle: confirmTitle,
                           initial: initial, onConfirm: onConfirm)
        guard let win = host.window else { return }
        let f = win.frame
        p.window.setFrameOrigin(NSPoint(x: f.midX - p.window.frame.width / 2,
                                        y: f.midY - p.window.frame.height / 2))
        current = p
        win.addChildWindow(p.window, ordered: .above)
        p.show()
    }

    static func showError(_ message: String) { current?.root.errorText = message }
    static func closeCurrent() { current?.close() }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(root.field)
        if let editor = root.field.currentEditor() {
            editor.selectedRange = NSRange(location: 0, length: root.field.stringValue.count)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            if e.keyCode == 53 { self.close(); return nil }               // Esc
            if e.keyCode == 36 || e.keyCode == 76 { self.root.commit(); return nil }
            return e
        }
    }

    private func close() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        NamePrompt.current = nil
    }
}

// --- context menu ----------------------------------------------------------

// A small themed context menu. An NSMenu is a grey system panel that ignores
// the Omacosy palette and font, so right-click menus are drawn here instead:
// one row per item, the accent on the hovered row, the app's own font.
final class ContextMenuView: NSView {
    var items: [String] = []
    var onSelect: ((Int) -> Void)?
    private var hovered = -1
    private var hoverTracking: NSTrackingArea?
    private let rowH: CGFloat = 26
    private let padX: CGFloat = 14
    private var font: NSFont { nerdFont("Regular", 12) }

    static func size(for items: [String]) -> NSSize {
        let f = nerdFont("Regular", 12)
        let w = items.map { advance($0, f) }.max() ?? 80
        return NSSize(width: w + 28, height: CGFloat(items.count) * 26 + 8)
    }

    private func rowRect(_ i: Int) -> NSRect {
        let top = 4 + CGFloat(i) * rowH
        return NSRect(x: 0, y: bounds.height - top - rowH, width: bounds.width, height: rowH)
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        palette.barBG.setFill(); card.fill()
        palette.muted.withAlphaComponent(0.35).setStroke(); card.lineWidth = 1; card.stroke()
        for (i, item) in items.enumerated() {
            let r = rowRect(i)
            if i == hovered {
                palette.accent.setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 4, dy: 2), xRadius: 5, yRadius: 5).fill()
            }
            let ink = i == hovered
                ? (relativeLuminance(palette.accent) > 0.179 ? palette.barBG : palette.label)
                : palette.label
            drawMidLeft(item, font, ink, x: padX, midTop: bounds.height - r.midY, height: bounds.height)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        hoverTracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        var hit = -1
        for i in items.indices where rowRect(i).contains(p) { hit = i; break }
        if hit != hovered { hovered = hit; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if hovered != -1 { hovered = -1; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for i in items.indices where rowRect(i).contains(p) { onSelect?(i); return }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ContextMenu: NSObject {
    private static var current: ContextMenu?
    private let window: PickerWindow
    private let view: ContextMenuView
    private var monitors: [Any] = []

    static func show(items: [String], at point: NSPoint, onSelect: @escaping (Int) -> Void) {
        current?.close()
        current = ContextMenu(items: items, at: point, onSelect: onSelect)
    }

    private init(items: [String], at point: NSPoint, onSelect: @escaping (Int) -> Void) {
        view = ContextMenuView()
        view.items = items
        let size = ContextMenuView.size(for: items)
        view.frame = NSRect(origin: .zero, size: size)
        window = PickerWindow(contentRect: view.frame,
                              styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = view
        var origin = NSPoint(x: point.x, y: point.y - size.height)
        if let scr = NSScreen.main {
            origin.x = min(origin.x, scr.visibleFrame.maxX - size.width - 6)
            origin.y = max(origin.y, scr.visibleFrame.minY + 6)
        }
        window.setFrameOrigin(origin)
        view.onSelect = { [weak self] i in self?.close(); onSelect(i) }
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
                guard let self else { return e }
                if e.type == .keyDown { if e.keyCode == 53 { self.close(); return nil }; return e }
                if !self.window.frame.contains(NSEvent.mouseLocation) { self.close() }
                return e
            }
        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        monitors = [local, global].compactMap { $0 }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        window.orderOut(nil)
        ContextMenu.current = nil
    }
}

final class AppPicker: NSObject, NSWindowDelegate {
    private static var current: AppPicker?
    private let window: NSWindow
    private let root = PickerRoot(frame: .zero)
    private var apps: [AppInfo] = []
    private var completion: ((String) -> Void)?
    private var monitors: [Any] = []
    private var searchable = true
    private let W: CGFloat = 340
    private let H: CGFloat = 430

    init(apps: [AppInfo], title: String?, searchable: Bool, completion: @escaping (String) -> Void) {
        self.apps = apps
        self.completion = completion
        self.searchable = searchable
        window = PickerWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                              styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.appearance = NSAppearance(named: .darkAqua)
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
        root.titleText = title
        root.showsSearch = searchable
        root.scroll.hasVerticalScroller = true
        root.scroll.drawsBackground = false
        root.scroll.borderType = .noBorder
        root.list.apps = apps
        root.list.onPick = { [weak self] bundle in self?.pick(bundle) }
        root.search.placeholderString = "Search apps"
        root.search.sendsWholeSearchString = false
        root.search.sendsSearchStringImmediately = true
        root.search.target = self
        root.search.action = #selector(searchChanged)
    }

    static func present(apps: [AppInfo], near view: NSView, in parent: NSView,
                        title: String? = nil, searchable: Bool = true,
                        completion: @escaping (String) -> Void) {
        current?.close()
        let p = AppPicker(apps: apps, title: title, searchable: searchable, completion: completion)
        guard let host = view.window else { return }
        let btn = host.convertToScreen(view.convert(view.bounds, to: nil))
        var x = btn.minX
        var y = btn.minY - p.H - 6
        if y < 40 { y = btn.maxY + 6 }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(btn.origin) }) ?? NSScreen.main {
            x = min(max(screen.frame.minX + 8, x), screen.frame.maxX - p.W - 8)
        }
        p.window.setFrame(NSRect(x: x, y: y, width: p.W, height: p.H), display: true)
        current = p
        // a child window: it stays above the modal and is ordered out with it
        host.addChildWindow(p.window, ordered: .above)
        p.show()
    }

    static func dismiss() { current?.close() }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        root.relayout()
        if searchable {
            root.search.stringValue = ""
            searchChanged()
            window.makeFirstResponder(root.search)
        }
        // Esc, or any click outside the picker's own window. The LOCAL
        // monitor is the important one: a click on the dashboard is our own
        // app, so a global monitor never sees it and the picker used to stay
        // up behind the modal.
        let km = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.close(); return nil }
            // the search field holds focus, so consume the arrows before it
            // sees them: they scroll the list, one row a press
            if e.window === self.window {
                if e.keyCode == 126 { self.root.list.moveSelection(-1); return nil } // up
                if e.keyCode == 125 { self.root.list.moveSelection(1); return nil }  // down
                if e.keyCode == 36 || e.keyCode == 76 { self.pickSelected(); return nil } // return
            }
            return e
        }
        let lm = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            if e.window !== self?.window { self?.close() }
            return e
        }
        let gm = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        monitors = [km, lm, gm].compactMap { $0 }
    }

    @objc private func searchChanged() {
        let q = root.search.stringValue.lowercased()
        root.list.apps = q.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(q) }
        // a new result set starts with the top app highlighted
        root.list.selected = 0
        root.list.needsDisplay = true
        root.relayout()
    }

    private func pickSelected() {
        guard root.list.apps.indices.contains(root.list.selected) else { return }
        pick(root.list.apps[root.list.selected].bundleID)
    }

    private func pick(_ bundle: String) {
        completion?(bundle)
        close()
    }

    private func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        if AppPicker.current === self { AppPicker.current = nil }
    }
}

// the chip strip inside the horizontal scroll view a row shows when it is
// expanded: all assigned apps, icons and all, scrollable sideways
final class ChipStrip: NSView {
    var assigned: [String] = []
    let allApps: [AppInfo]
    var onRemove: ((String) -> Void)?
    var onAdd: (() -> Void)?
    var onTap: (() -> Void)?
    private var chipFrames: [(NSRect, String)] = []
    private var addFrame: NSRect = .zero
    private let gap: CGFloat = 8
    // only the "✕" removes: clicking the rest of a chip must not delete an
    // app by accident (the whole chip used to be a delete target)
    private let removeZone: CGFloat = 22

    init(allApps: [AppInfo]) {
        self.allApps = allApps
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func label(_ id: String) -> String {
        let name = allApps.first { $0.bundleID == id }?.name ?? id
        return truncate(name, nerdFont("Regular", 11), 150)
    }
    private func chipWidth(_ id: String) -> CGFloat {
        return 16 + 6 + advance(label(id), nerdFont("Regular", 11)) + 22
    }

    private let addChipW: CGFloat = 78

    func stripWidth() -> CGFloat {
        var w: CGFloat = 0
        for id in assigned { w += chipWidth(id) + gap }
        return max(0, w - gap) + gap + addChipW + 4
    }

    private func layoutChips() {
        chipFrames.removeAll()
        var x: CGFloat = 2
        for id in assigned {
            let cw = chipWidth(id)
            chipFrames.append((NSRect(x: x, y: (bounds.height - 24) / 2, width: cw, height: 24), id))
            x += cw + gap
        }
        addFrame = NSRect(x: x, y: (bounds.height - 24) / 2, width: addChipW, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        layoutChips()
        for (f, id) in chipFrames {
            let chip = NSBezierPath(roundedRect: f, xRadius: 5, yRadius: 5)
            palette.itemBG.withAlphaComponent(0.6).setFill()
            chip.fill()
            if let ic = iconForBundle(id) {
                ic.draw(in: NSRect(x: f.minX + 5, y: f.midY - 7, width: 14, height: 14))
            }
            drawMidLeft(label(id), nerdFont("Regular", 11), palette.label,
                        x: f.minX + 24, midTop: bounds.height / 2, height: bounds.height)
            drawMidLeft("✕", nerdFont("Regular", 10), palette.muted,
                        x: f.maxX - 14, midTop: bounds.height / 2, height: bounds.height)
        }
        // a trailing "＋ Add" so an app can be added from the expanded strip
        let add = NSBezierPath(roundedRect: addFrame, xRadius: 5, yRadius: 5)
        palette.accent.withAlphaComponent(0.30).setStroke()
        add.lineWidth = 1
        add.stroke()
        drawMidCenter("＋ Add", nerdFont("Bold", 11), palette.accent,
                      centerX: addFrame.midX, midTop: bounds.height / 2, height: bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if addFrame.contains(p) { onAdd?(); return }
        for (f, id) in chipFrames where f.contains(p) {
            if p.x >= f.maxX - removeZone { onRemove?(id) } else { onTap?() }
            return
        }
        onTap?()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class WorkspaceRowView: NSView {
    let ws: String
    var assigned: [String]
    let allApps: [AppInfo]
    var onAssign: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    private var chipFrames: [(NSRect, String)] = []
    private var overflowApps: [String] = []
    private var moreFrame: NSRect = .zero
    private var expanded = false
    private let addButton = ButtonView()
    private let chipScroll = NSScrollView()
    private let chipStrip: ChipStrip
    private let labelW: CGFloat = 120
    private let addW: CGFloat = 96

    init(ws: String, assigned: [String], allApps: [AppInfo]) {
        self.ws = ws
        self.assigned = assigned
        self.allApps = allApps
        self.chipStrip = ChipStrip(allApps: allApps)
        super.init(frame: .zero)
        addButton.title = "＋ Add App"
        addButton.onClick = { [weak self] in self?.showMenu() }
        addSubview(addButton)
        chipScroll.hasHorizontalScroller = true
        chipScroll.drawsBackground = false
        chipScroll.borderType = .noBorder
        chipScroll.autohidesScrollers = true
        chipScroll.documentView = chipStrip
        chipScroll.isHidden = true
        addSubview(chipScroll)
        chipStrip.onRemove = { [weak self] bundle in self?.onRemove?(bundle) }
        chipStrip.onAdd = { [weak self] in self?.showMenu() }
        chipStrip.onTap = { [weak self] in self?.setExpanded(false) }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func chipLabel(_ id: String) -> String {
        let name = allApps.first(where: { $0.bundleID == id })?.name ?? id
        return truncate(name, nerdFont("Regular", 11), 150)
    }

    private func chipWidth(_ id: String) -> CGFloat {
        return 16 + 6 + advance(chipLabel(id), nerdFont("Regular", 11)) + 22
    }

    // computed on every draw as well as on layout: a rebuild after a
    // removal does not always trigger layout(), and a stale overflow list is
    // exactly the "+N more" that would not come back
    private func computeChips() {
        chipFrames.removeAll()
        overflowApps.removeAll()
        moreFrame = .zero
        var x: CGFloat = labelW + 8
        let limit = bounds.width - addW - 8
        var placed = 0
        for (idx, id) in assigned.enumerated() {
            let cw = chipWidth(id)
            let remaining = assigned.count - idx - 1
            // if chips will not fit, keep room for the "+N more" label
            let reserve: CGFloat = remaining > 0 ? 74 : 0
            if x + cw > limit - reserve { break }
            chipFrames.append((NSRect(x: x, y: (bounds.height - 24) / 2, width: cw, height: 24), id))
            x += cw + 8
            placed = idx + 1
        }
        overflowApps = Array(assigned.dropFirst(placed))
        if !overflowApps.isEmpty {
            let mx = chipFrames.last.map { $0.0.maxX + 8 } ?? (labelW + 8)
            moreFrame = NSRect(x: mx, y: (bounds.height - 24) / 2, width: 80, height: 24)
        }
    }

    override func layout() {
        super.layout()
        let w: CGFloat = addW, h: CGFloat = 24
        addButton.frame = NSRect(x: bounds.width - w, y: (bounds.height - h) / 2, width: w, height: h)
        computeChips()
        let stripX = labelW + 8
        let stripW = max(0, bounds.width - stripX - addW - 8)
        chipScroll.frame = NSRect(x: stripX, y: 0, width: stripW, height: bounds.height)
        if expanded {
            chipScroll.isHidden = false
            chipStrip.assigned = assigned
            // fill the clip view at least: the empty space past the chips is
            // still part of the strip, so a click there reaches ChipStrip and
            // folds the row instead of being swallowed by the scroll view
            let stripW = max(chipStrip.stripWidth(), chipScroll.contentSize.width)
            chipStrip.frame = NSRect(x: 0, y: 0, width: stripW, height: bounds.height)
            chipStrip.needsDisplay = true
        } else {
            chipScroll.isHidden = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        computeChips()
        drawMidLeft("Workspace \(ws)", nerdFont("Bold", 12), palette.label,
                    x: 0, midTop: bounds.height / 2, height: bounds.height)
        if !assigned.isEmpty, expanded || !overflowApps.isEmpty {
            drawMidLeft(expanded ? "‹" : "›", nerdFont("Bold", 12), palette.accent,
                        x: labelW - 16, midTop: bounds.height / 2, height: bounds.height)
        }
        if expanded { return }   // the horizontally scrollable strip draws them

        for (frame, id) in chipFrames {
            let name = chipLabel(id)
            let chip = NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
            palette.itemBG.withAlphaComponent(0.6).setFill()
            chip.fill()
            if let ic = iconForBundle(id) {
                ic.draw(in: NSRect(x: frame.minX + 5, y: frame.midY - 7, width: 14, height: 14))
            }
            drawMidLeft(name, nerdFont("Regular", 11), palette.label,
                        x: frame.minX + 24, midTop: bounds.height / 2, height: bounds.height)
            drawMidLeft("✕", nerdFont("Regular", 10), palette.muted,
                        x: frame.maxX - 14, midTop: bounds.height / 2, height: bounds.height)
        }
        if assigned.isEmpty {
            drawMidLeft("No app assigned", nerdFont("Regular", 11), palette.muted,
                        x: labelW + 8, midTop: bounds.height / 2, height: bounds.height)
        } else if !overflowApps.isEmpty {
            // accent, and clickable: reveals the hidden apps in a sideways
            // scroll on this same row
            drawMidLeft("+\(overflowApps.count) more", nerdFont("Bold", 11), palette.accent,
                        x: moreFrame.minX, midTop: bounds.height / 2, height: bounds.height)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // let the tab fold any OTHER open row before this click is handled
        onWillHandleClick?(self)
        let p = convert(event.locationInWindow, from: nil)
        if expanded {
            // the chips live in the strip subview, which folds the row itself
            // on a non-✕ tap; a click on the row body folds it too
            setExpanded(false)
            return
        }
        // the chevron/"+N more": expand into the scrollable strip
        if !overflowApps.isEmpty, (moreFrame.contains(p) || p.x < labelW) {
            setExpanded(true)
            return
        }
        // a chip only loses its app on the "✕"; its body opens the row so the
        // hidden apps can be seen (no overflow means there is nothing to open)
        for (frame, id) in chipFrames where frame.contains(p) {
            if p.x >= frame.maxX - 22 { onRemove?(id) }
            else if !overflowApps.isEmpty { setExpanded(true) }
            return
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The tab owns one always-on click monitor and tracks which row is open.
    // A per-row monitor was tried first and was unreliable: the row is a
    // short-lived view (rebuilt on every add or remove), so its monitor
    // could be gone before a click arrived.
    var onWillHandleClick: ((WorkspaceRowView) -> Void)?
    var onExpandedChanged: ((WorkspaceRowView, Bool) -> Void)?

    func setExpanded(_ v: Bool) {
        guard expanded != v else { return }
        expanded = v
        // toggle the strip directly, not via layout(): a missing layout pass
        // would leave the strip on top of the "+N more" it should reveal.
        // On collapse the strip leaves the hierarchy entirely, so it can never
        // paint over the folded row (a hidden view still could).
        if v {
            let stripX = labelW + 8
            chipScroll.frame = NSRect(x: stripX, y: 0,
                                      width: max(0, bounds.width - stripX - addW - 8),
                                      height: bounds.height)
            chipStrip.assigned = assigned
            chipStrip.frame = NSRect(x: 0, y: 0,
                                     width: max(chipStrip.stripWidth(), chipScroll.contentSize.width),
                                     height: bounds.height)
            chipStrip.needsDisplay = true
            if chipScroll.superview == nil { addSubview(chipScroll) }
            chipScroll.isHidden = false
        } else {
            chipScroll.isHidden = true
            chipScroll.removeFromSuperview()
        }
        computeChips()
        needsLayout = true
        needsDisplay = true
        displayIfNeeded()
        onExpandedChanged?(self, v)
    }

    private func showMenu() {
        AppPicker.present(apps: allApps, near: addButton, in: self) { [weak self] bundle in
            self?.onAssign?(bundle)
        }
    }
}

final class WorkspacesTabView: NSView, ScrollStepTab {
    private var screens: [ScreenInfo] = []
    func scrollStep(_ dy: CGFloat) { scrollBy(scroll, dy) }
    func refreshColors() {
        needsDisplay = true
        screenSeg.needsDisplay = true
        for r in rows { r.needsDisplay = true; r.subviews.forEach { $0.needsDisplay = true } }
        scroller.refresh()
    }
    private var allApps: [AppInfo] = []
    private var rules: [(String, String)] = []
    private var savedRules: [(String, String)] = []
    private var screenIndex = 0
    private var rows: [WorkspaceRowView] = []
    private let screenSeg = SegmentedView()
    private let scroll = NSScrollView()
    private let doc = NSView()
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8
    let saveButton = ButtonView()
    private var status = ""
    private var expandedRow: WorkspaceRowView?
    private var clickMonitor: Any?

    private let headerH: CGFloat = 40
    private let bottomBarH: CGFloat = 54
    private let rowH: CGFloat = 48
    private var lastDocH: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        screens = screensInfo()
        allApps = installedApps()
        rules = readWorkspaceRules()
        savedRules = rules
        if screens.isEmpty { screens = [ScreenInfo(name: "This display", workspaces: (1...9).map(String.init))] }
        screenSeg.items = screens.map { $0.name }
        screenSeg.index = 0
        screenSeg.onChange = { [weak self] i in self?.screenIndex = i; self?.rebuildRows() }
        addSubview(screenSeg)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = doc
        addSubview(scroller)
        scroller.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        saveButton.title = "Save"
        saveButton.onClick = { [weak self] in self?.save() }
        addSubview(saveButton)
        // one always-on monitor for the whole tab: a click anywhere outside
        // the open row folds it back. Row lifetime does not matter here.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
            self?.collapseIfClickOutside(e)
            return e
        }
        rebuildRows()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { if let m = clickMonitor { NSEvent.removeMonitor(m) } }
    @objc private func scrolled() { scroller.refresh() }

    private func collapseExpanded(except keep: WorkspaceRowView?) {
        if let r = expandedRow, r !== keep { r.setExpanded(false); expandedRow = nil }
    }

    func collapseIfClickOutside(_ e: NSEvent) {
        guard let r = expandedRow else { return }
        let inside = (e.window === r.window) && r.bounds.contains(r.convert(e.locationInWindow, from: nil))
        let hit = r.window?.contentView?.hitTest(e.locationInWindow)
        if !inside { r.setExpanded(false); expandedRow = nil; return }
        // a click inside the open row folds it too, so there is no dead zone
        // that only a reopen can clear. The one exception is the Add button,
        // which must open the picker. Deferred one tick so the click is
        // handled against the current layout first (a chip "✕" rebuilds the
        // rows and clears expandedRow before this runs).
        if hit is ButtonView { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.expandedRow === r else { return }
            r.setExpanded(false)
            self.expandedRow = nil
        }
    }

    // a click on the tab's own empty space also folds the open row, and is
    // consumed so it does not fall through to the modal's close-on-click
    override func mouseDown(with event: NSEvent) {
        collapseExpanded(except: nil)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // the workspace rules are sensitive: only the SAVE button persists them.
    // Re-entering the tab drops anything unsaved and shows the file's state
    // again, so an edit is never mistaken for an applied one.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { reloadFromDisk() }
    }

    private func reloadFromDisk() {
        rules = readWorkspaceRules()
        savedRules = rules
        status = ""
        rebuildRows()
    }

    // called when the modal is shown again: unsaved edits are dropped
    func resetToSaved() { reloadFromDisk() }

    private var dirty: Bool {
        rules.map { "\($0.0) \($0.1)" }.sorted() != savedRules.map { "\($0.0) \($0.1)" }.sorted()
    }

    private func assigned(for ws: String) -> [String] {
        rules.filter { $0.1 == ws }.map { $0.0 }
    }

    private func rebuildRows() {
        for r in rows { r.removeFromSuperview() }
        rows.removeAll()
        expandedRow = nil
        guard screens.indices.contains(screenIndex) else { return }
        for ws in screens[screenIndex].workspaces {
            let row = WorkspaceRowView(ws: ws, assigned: assigned(for: ws), allApps: allApps)
            row.onAssign = { [weak self] bundle in self?.assign(bundle, to: ws) }
            row.onRemove = { [weak self] bundle in self?.unassign(bundle) }
            row.onWillHandleClick = { [weak self] r in self?.collapseExpanded(except: r) }
            row.onExpandedChanged = { [weak self] r, exp in
                if exp {
                    self?.collapseExpanded(except: r)
                    self?.expandedRow = r
                } else if self?.expandedRow === r {
                    self?.expandedRow = nil
                }
            }
            doc.addSubview(row)
            rows.append(row)
        }
        for row in rows { row.needsLayout = true; row.needsDisplay = true }
        needsLayout = true
        needsDisplay = true
    }

    private func assign(_ bundle: String, to ws: String) {
        rules.removeAll { $0.0 == bundle }
        rules.append((bundle, ws))
        rebuildRows()
    }

    private func unassign(_ bundle: String) {
        rules.removeAll { $0.0 == bundle }
        rebuildRows()
    }

    override func layout() {
        super.layout()
        let showSeg = screens.count > 1
        screenSeg.isHidden = !showSeg
        let segSize = screenSeg.sizeThatFits()
        screenSeg.frame = NSRect(x: 0, y: bounds.height - 2 - segSize.height,
                                 width: min(segSize.width, bounds.width), height: segSize.height)
        let saveW: CGFloat = 96, saveH: CGFloat = 24
        saveButton.frame = NSRect(x: (bounds.width - saveW) / 2,
                                  y: (bottomBarH - saveH) / 2, width: saveW, height: saveH)
        // a whole number of rows: on first open the list sits at the top, so
        // an unrounded viewport would show a half-cut row at its bottom edge.
        // The leftover goes as a small gap above the Save bar instead.
        let rawH = max(0, bounds.height - bottomBarH - headerH)
        let shownRows = floor(rawH / rowH)
        let scrollH = shownRows > 0 ? shownRows * rowH : rawH
        let gap = rawH - scrollH
        scroll.frame = NSRect(x: 0, y: bottomBarH + gap, width: max(0, bounds.width - scrollerW - 14), height: scrollH)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: bottomBarH + gap, width: scrollerW, height: scrollH)
        scroller.refresh()
        let w = scroll.contentSize.width
        guard w > 0 else { return }
        if abs(doc.frame.width - w) > 0.5 { doc.frame.size.width = w }
        let h = CGFloat(rows.count) * rowH
        if abs(doc.frame.height - h) > 0.5 { doc.frame.size.height = h }
        for (i, row) in rows.enumerated() {
            let f = NSRect(x: 0, y: h - CGFloat(i + 1) * rowH, width: w, height: rowH)
            if row.frame != f { row.frame = f }
        }
        if h != lastDocH {
            lastDocH = h
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, h - scroll.contentSize.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if screens.count <= 1, let s = screens.first {
            drawMidLeft("Screen: \(s.name)", nerdFont("Bold", 12), palette.accent,
                        x: 0, midTop: headerH / 2, height: bounds.height)
        }
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bottomBarH - 0.5, width: bounds.width, height: 1).fill()
        if !status.isEmpty {
            drawMidLeft(status, nerdFont("Regular", 11), palette.muted,
                        x: 0, midTop: bounds.height - bottomBarH / 2, height: bounds.height)
        } else if dirty {
            drawMidLeft("Unsaved changes", nerdFont("Regular", 11), palette.accent,
                        x: 0, midTop: bounds.height - bottomBarH / 2, height: bounds.height)
        }
    }

    private func save() {
        saveButton.busy = true
        status = "Applying…"
        needsDisplay = true
        let rules = self.rules
        // bundles taken out since the last save: omacosy-settings only adds
        // and corrects OmniWM rules, so these have to be pruned explicitly
        let removed = savedRules.map { $0.0 }.filter { b in !rules.contains { $0.0 == b } }
        DispatchQueue.global().async { [weak self] in
            let wrote = writeWorkspaceRules(rules)
            var err = ""
            if wrote {
                let (code, out) = shell("\(HOME)/.local/bin/omacosy-settings 2>&1")
                if code != 0 {
                    err = out.split(separator: "\n").last.map(String.init) ?? ""
                } else if !removed.isEmpty {
                    let args = removed.map(shellQuote).joined(separator: " ")
                    _ = shell("\(HOME)/.local/bin/omacosy-ws-prune \(args) 2>&1")
                }
            } else { err = "could not write settings.conf" }
            DispatchQueue.main.async {
                self?.savedRules = rules
                self?.status = err.isEmpty ? "Saved" : "Error: \(err)"
                self?.saveButton.busy = false
                self?.needsDisplay = true
            }
        }
    }
}

// --- themes tab ------------------------------------------------------------

struct ThemeCell: Equatable {
    let logical: String
    let wallpaper: String
    let title: String
    let isCustom: Bool
    let paletteFile: String
    // a named edition: its immutable record id; nil on stock and raw cells
    var editionID: String?
    // a raw wallpaper with editions: how many variations hang off its source
    var variations: Int
    var storedColors: [NSColor]

    init(logical: String, wallpaper: String, title: String, isCustom: Bool,
         paletteFile: String, editionID: String? = nil, variations: Int = 0,
         storedColors: [NSColor] = []) {
        self.logical = logical
        self.wallpaper = wallpaper
        self.title = title
        self.isCustom = isCustom
        self.paletteFile = paletteFile
        self.editionID = editionID
        self.variations = variations
        self.storedColors = storedColors
    }
}

func stableHash(_ s: String) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
    return String(h, radix: 16)
}

func isImageFile(_ name: String) -> Bool {
    let ext = (name as NSString).pathExtension.lowercased()
    return ["jpg", "jpeg", "png", "webp", "heic", "gif"].contains(ext)
}

func prettyThemeName(_ t: String) -> String {
    t.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}

func prettyWallName(_ file: String) -> String {
    var s = (file as NSString).deletingPathExtension
    if let r = s.range(of: "^[0-9]+[-_]", options: .regularExpression) { s.removeSubrange(r) }
    s = s.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    return s.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}

func stockVariants() -> [ThemeCell] {
    guard let repo = repoDir() else { return [] }
    let themesDir = repo + "/themes"
    let themes = ((try? FileManager.default.contentsOfDirectory(atPath: themesDir)) ?? [])
        .filter { !$0.hasPrefix(".") }.sorted()
    var out: [ThemeCell] = []
    for t in themes {
        let colors = themesDir + "/" + t + "/colors.toml"
        guard FileManager.default.fileExists(atPath: colors) else { continue }
        let bg = themesDir + "/" + t + "/backgrounds"
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: bg)) ?? [])
            .filter { isImageFile($0) }.sorted()
        for f in files {
            out.append(ThemeCell(logical: t, wallpaper: bg + "/" + f,
                                 title: "\(prettyThemeName(t)) — \(prettyWallName(f))",
                                 isCustom: false, paletteFile: colors))
        }
    }
    return out
}

// symlink-canonical spelling, so a raw entry and an edition's recorded
// provenance match even when one is /tmp and the other /private/tmp
func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

// --- theme editions ---------------------------------------------------------

struct ThemeEdition {
    let id: String
    let name: String
    let primary: Bool
    let sourcePath: String?
    let media: String?
    let colors: [NSColor]
}

// What the editor and the grid need from the record store: id, name,
// provenance and the stored palette. `theme list --json` is the library's
// own answer, so the tab and the CLI can never disagree.
func allEditions() -> [ThemeEdition] {
    let (code, out) = shell("\(HOME)/.local/bin/omacosy-themecore theme list --json 2>/dev/null")
    guard code == 0, let data = out.data(using: .utf8),
          let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
        guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
        let wall = row["wallpaper"] as? [String: Any] ?? [:]
        let palette = row["palette"] as? [String: Any] ?? [:]
        let hexes = palette["colors"] as? [String] ?? []
        return ThemeEdition(id: id, name: name,
                            primary: (row["primary"] as? Bool) ?? false,
                            sourcePath: wall["path"] as? String,
                            media: wall["media"] as? String,
                            colors: hexes.compactMap(hexColor))
    }
}

// "<name> #N" for a duplicate, N from 2: the smallest number that is free
// among the library's names with that base.
func nextDuplicateName(_ base: String) -> String {
    var maxN = 1
    for e in allEditions() {
        guard e.name.hasPrefix(base + " #") else { continue }
        if let n = Int(e.name.dropFirst(base.count + 2)) { maxN = max(maxN, n) }
    }
    return "\(base) #\(maxN + 1)"
}

// The edition's own snapshot wins; the recorded source is the fallback. A
// record with neither left in place cannot be applied, so it gets no cell.
func editionImage(_ e: ThemeEdition) -> String? {
    if let m = e.media, !m.isEmpty, !m.contains("/") {
        let p = HOME + "/.local/share/omacosy/theme-media/" + m
        if FileManager.default.fileExists(atPath: p) { return p }
    }
    if let s = e.sourcePath, FileManager.default.fileExists(atPath: s) { return s }
    return nil
}

// Every wallpaper in the configured folder is an auto-theme
// (`Wallpaper #N`); named editions always sit on top.
func customVariants() -> [ThemeCell] {
    let dir = wallpapersDir()
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
        .filter { isImageFile($0) }.sorted()
    let editions = allEditions()

    // Hide NSFW downloads (and editions built from them) when the global
    // toggle is on. Nothing is removed from disk; the number simply skips.
    let hideNSFW = WHConfig.load().hideNSFW
    let manifest = hideNSFW ? whDownloadManifest() : [:]
    func hidden(_ path: String) -> Bool {
        hideNSFW && manifest[(path as NSString).lastPathComponent]?.purity == "nsfw"
    }
    let visibleFiles = files.filter { !hidden($0) }

    var bySource: [String: Int] = [:]
    for e in editions {
        guard let src = e.sourcePath else { continue }
        bySource[canonicalPath(src), default: 0] += 1
    }

    var out: [ThemeCell] = []
    // named editions A→Z on top; the raw entries stay below in today's
    // lexicographic order and are numbered over the full sorted list
    let sorted = editions.sorted {
        let cmp = $0.name.localizedCaseInsensitiveCompare($1.name)
        return cmp == .orderedSame ? $0.id < $1.id : cmp == .orderedAscending
    }
    for e in sorted {
        guard let img = editionImage(e) else { continue }
        if let src = e.sourcePath, hidden(src) { continue }
        out.append(ThemeCell(logical: "custom", wallpaper: img, title: e.name,
                             isCustom: true, paletteFile: "",
                             editionID: e.id, storedColors: e.colors))
    }
    for (i, f) in visibleFiles.enumerated() {
        let p = dir + "/" + f
        out.append(ThemeCell(logical: "custom", wallpaper: p,
                             title: "Wallpaper #\(i + 1)", isCustom: true, paletteFile: "",
                             variations: bySource[canonicalPath(p), default: 0]))
    }
    return out
}

// --- wallpapers tab data ---------------------------------------------------

// The configured folder, read from the CLI so the dashboard and
// `omacosy-custom-theme status` can never disagree. status answers even
// when terminal following is off, so this tab never depends on a switch.
func wallpapersDir() -> String {
    let (_, out) = shell("\(HOME)/.local/bin/omacosy-custom-theme status 2>/dev/null")
    for line in out.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("wallpaper directory"), let r = t.range(of: ":") else { continue }
        let d = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
        if !d.isEmpty { return d }
    }
    return HOME + "/Pictures/wallpapers"
}

enum WallpaperImport { case added, skipped, failed }

// Copy, never move: the user's file stays where it was, and picking an
// image already in the folder is skipped — compared by content against
// every file in the folder, not just against a same-named file, so the
// same picture under a new name does not pile up. A name already taken by
// genuinely different content gets a -2/-3 suffix; nothing is ever
// overwritten.
func importWallpaper(_ src: String, into dir: String) -> WallpaperImport {
    let fm = FileManager.default
    let name = (src as NSString).lastPathComponent
    guard isImageFile(name) else { return .failed }
    do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }
    catch { return .failed }
    let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
    for e in entries where isImageFile(e) {
        let p = dir + "/" + e
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue else { continue }
        if fm.contentsEqual(atPath: src, andPath: p) { return .skipped }
    }
    var dest = dir + "/" + name
    var n = 2
    while fm.fileExists(atPath: dest) {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        dest = dir + "/\(base)-\(n)" + (ext.isEmpty ? "" : ".\(ext)")
        n += 1
    }
    do { try fm.copyItem(atPath: src, toPath: dest); return .added }
    catch { return .failed }
}

func hexColor(_ s: String) -> NSColor? {
    var h = s
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
    return color(fromARGB: 0xff000000 | v)
}

// The first complete JSON object in a command's output. The engine
// pretty-prints (multi-line) and exits, so a line-by-line scan misses it;
// try the whole output, then brace-match from each `{`.
func firstJSONObject(in output: String) -> [String: Any]? {
    if let obj = try? JSONSerialization.jsonObject(with: Data(output.utf8)),
       let dict = obj as? [String: Any] {
        return dict
    }
    let bytes = Array(output.utf8)
    let open = UInt8(ascii: "{"), close = UInt8(ascii: "}")
    let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
    var i = 0
    while i < bytes.count {
        guard bytes[i] == open else { i += 1; continue }
        var depth = 0, inString = false, escaped = false
        var j = i
        while j < bytes.count {
            let c = bytes[j]
            if inString {
                if escaped { escaped = false }
                else if c == backslash { escaped = true }
                else if c == quote { inString = false }
            } else if c == quote { inString = true }
            else if c == open { depth += 1 }
            else if c == close {
                depth -= 1
                if depth == 0 {
                    if let obj = try? JSONSerialization.jsonObject(with: Data(bytes[i...j])),
                       let dict = obj as? [String: Any] { return dict }
                    break
                }
            }
            j += 1
        }
        i = j + 1
    }
    return nil
}

// A theme import's file types: our JSON, an Omarchy colors.toml and a Base16
// YAML (the engine also sniffs the content), plus plain text so an
// extensionless file can be picked.
func importContentTypes() -> [UTType] {
    var types: [UTType] = [.json, .yaml, .plainText]
    if let toml = UTType(filenameExtension: "toml") { types.append(toml) }
    return types
}

// A fresh bundle folder named after the theme id, -2/-3 on a clash, so an
// export never overwrites an earlier one.
func uniqueExportDir(in parent: String, id: String) -> String {
    let fm = FileManager.default
    var dir = parent + "/" + id
    var n = 2
    while fm.fileExists(atPath: dir) {
        dir = parent + "/\(id)-\(n)"
        n += 1
    }
    return dir
}

// The id between the first pair of double quotes, for the engine's
// `theme "<id>" already exists` message.
func quotedID(from output: String) -> String? {
    guard let a = output.firstIndex(of: "\""),
          let b = output[output.index(after: a)...].firstIndex(of: "\"") else { return nil }
    return String(output[output.index(after: a)..<b])
}

// The engine prefixes its errors with "omacosy-themecore: "; hand back a line
// a person can read.
func importErrorMessage(_ output: String) -> String {
    for line in output.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("omacosy-themecore:") else { continue }
        let msg = String(t.dropFirst("omacosy-themecore:".count))
            .trimmingCharacters(in: .whitespaces)
        if !msg.isEmpty { return "Import failed. " + msg }
    }
    return "Import failed."
}

// WCAG relative luminance, so the Edit pill can pick a label colour that
// stays readable on the accent fill. 0.179 is the sRGB pivot where black
// and white trade places.
func relativeLuminance(_ c: NSColor) -> CGFloat {
    let s = c.usingColorSpace(.sRGB) ?? c
    func lin(_ v: CGFloat) -> CGFloat {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
}

func parseColorsToml(_ path: String) -> [NSColor] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var map: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let eq = t.firstIndex(of: "=") else { continue }
        let k = t[..<eq].trimmingCharacters(in: .whitespaces)
        var v = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        map[String(k)] = v
    }
    let ansi = (0...15).map { "color\($0)" }
    if ansi.allSatisfy({ map[$0] != nil }) {
        return ansi.compactMap { map[$0].flatMap(hexColor) }
    }
    let order = ["background", "accent", "color1", "color2", "color3", "color4", "color5", "color6"]
    return order.compactMap { map[$0].flatMap(hexColor) }
}

// a derived custom theme has no colors.toml; its palette lives in the
// generated sketchybar.sh the bar itself reads. Eight keys, same order the
// stock strip uses: background, accent, then the named hues.
func parseSketchybar(_ path: String) -> [NSColor] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var map: [String: NSColor] = [:]
    for line in text.split(separator: "\n") {
        let t = line.replacingOccurrences(of: "export ", with: "")
        let parts = t.split(separator: "=")
        guard parts.count == 2, parts[1].hasPrefix("0x"),
              let v = UInt64(parts[1].dropFirst(2), radix: 16) else { continue }
        map[String(parts[0])] = color(fromARGB: v)
    }
    let order = ["BAR_BG_SOLID", "ACCENT", "RED", "GREEN", "YELLOW", "ITEM_BG", "LABEL_COLOR", "MUTED"]
    return order.compactMap { map[$0] }
}

// derive-on-first-use for a custom wallpaper; cached by its derived dir
func customPalette(_ wallpaper: String) -> [NSColor] {
    let (code, out) = shell("\(HOME)/.local/bin/omacosy-custom-theme theme --raw \(shellQuote(wallpaper)) 2>/dev/null")
    guard code == 0 else { return [] }
    let dir = out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
    guard !dir.isEmpty else { return [] }
    // the full 16 ANSI colours the editor seeds from (same helper, same
    // milliseconds); the bar's 8-role summary is the fallback
    let envFile = NSTemporaryDirectory()
        + "omacosy-cell-palette-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).env"
    let (tc, _) = shell("\(HOME)/.local/bin/omacosy-term-palette \(shellQuote(dir)) \(shellQuote(envFile)) >/dev/null 2>&1")
    var byIndex: [Int: NSColor] = [:]
    if tc == 0, let text = try? String(contentsOfFile: envFile, encoding: .utf8) {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasPrefix("OMACOSY_P"),
                  let i = Int(parts[0].dropFirst(9)) else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            if let col = hexColor(value) { byIndex[i] = col }
        }
    }
    try? FileManager.default.removeItem(atPath: envFile)
    if byIndex.count == 16 { return (0..<16).compactMap { byIndex[$0] } }
    return parseSketchybar(dir + "/sketchybar.sh")
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func thumbnail(_ path: String, maxPixel: Int = 360) -> NSImage? {
    let dir = HOME + "/.local/state/omacosy/dashboard/thumbs"
    let cache = dir + "/" + stableHash(path + ":\(maxPixel)") + ".png"
    if let img = NSImage(contentsOfFile: cache) { return img }
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: cache) as CFURL, "public.png" as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

func applyTheme(_ c: ThemeCell, done: @escaping () -> Void) {
    // a named edition applies through its record, a raw wallpaper through
    // the derived dir, a stock theme through its logical name
    let cmd: String
    if let id = c.editionID {
        let json = HOME + "/.config/omacosy/themes/" + id + ".json"
        cmd = "\(HOME)/.local/bin/omacosy-theme-switch set-theme \(shellQuote(json))"
    } else if c.isCustom {
        cmd = "\(HOME)/.local/bin/omacosy-theme-switch set-raw \(shellQuote(c.wallpaper))"
    } else {
        cmd = "\(HOME)/.local/bin/omacosy-theme-switch set \(c.logical) \(shellQuote(c.wallpaper))"
    }
    DispatchQueue.global().async {
        _ = shell(cmd)
        DispatchQueue.main.async { done() }
    }
}

final class ThemeGridView: NSView {
    var cells: [ThemeCell] = []
    var customDir: String?
    var thumbs: [Int: NSImage] = [:]
    var palettes: [Int: [NSColor]] = [:]
    var pending: Set<Int> = []
    var cellFrames: [Int: NSRect] = [:]
    var headers: [(NSRect, String)] = []
    var onApplied: ((String) -> Void)?
    // the Edit pill's click: opens the Theme Editor on this cell
    var onEdit: ((ThemeCell) -> Void)?
    // bulk selection: custom cells only. The tab owns the Select toggle and
    // the Delete bar; the grid draws and hit-tests the checkboxes.
    var selectionMode = false { didSet { needsDisplay = true } }
    var selected: Set<Int> = [] { didSet { needsDisplay = true } }
    var onToggleSelect: ((Int) -> Void)?
    // right-click "Duplicate Theme" on a named edition
    var onDuplicate: ((ThemeCell) -> Void)?
    // Off-screen review only.
    func debugSetHover(_ i: Int?) { hoveredIndex = i; needsDisplay = true }
    private var hoveredIndex: Int?
    private var hoverTracking: NSTrackingArea?

    private var customHeaderRect = NSRect.zero
    private var separatorRect = NSRect.zero
    private let headerH: CGFloat = 34
    private let cellH: CGFloat = 180
    private let gapX: CGFloat = 14
    private let gapY: CGFloat = 16
    private let cellPaletteH: CGFloat = 12
    private let cellLabelH: CGFloat = 18
    private let cellThumbGap: CGFloat = 12
    private let pillH: CGFloat = 22
    private let pillInset: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func rebuild() {
        cellFrames.removeAll(); headers.removeAll()
        hoveredIndex = nil
        let W = max(bounds.width, 120)
        // keep a margin at both edges so the hover ring is never clipped by
        // the scroll view's clip rect
        let padX: CGFloat = 4
        let usable = W - padX * 2
        var cols = max(2, Int((usable + gapX) / (216 + gapX)))
        if cols < 2 { cols = 2 }
        let cellW = (usable - gapX * CGFloat(cols - 1)) / CGFloat(cols)

        var top: CGFloat = 0
        var x: CGFloat = padX
        var idx = 0

        func placeCell(_ cellIndex: Int) {
            if x + cellW > padX + usable + 0.5 { x = padX; top += cellH + gapY }
            let f = NSRect(x: x, y: top, width: cellW, height: cellH)
            cellFrames[cellIndex] = f
            x += cellW + gapX
        }
        func endRow() { if x > padX { top += cellH + gapY; x = padX } }

        let stockCount = cells.filter { !$0.isCustom }.count
        if stockCount > 0 {
            headers.append((NSRect(x: 0, y: top, width: W, height: headerH), "Omarchy Themes"))
            top += headerH + 8
            for (i, c) in cells.enumerated() where !c.isCustom { placeCell(i); idx += 1 }
            endRow()
            top += 6
        }

        // custom section: every wallpaper is an auto-theme, so the section
        // shows whenever there is anything to show — no switch state gates it
        let customIdx = cells.enumerated().filter { $0.element.isCustom }.map { $0.offset }
        if !customIdx.isEmpty {
            // a rule between the Omarchy grid and the custom grid, so the two
            // galleries read as separate sections
            top += 22
            separatorRect = NSRect(x: 0, y: top, width: W, height: 1)
            top += 1 + 22
            customHeaderRect = NSRect(x: 0, y: top, width: W, height: headerH)
            headers.append((customHeaderRect, "Custom Themes"))
            top += headerH + 8
            for i in customIdx { placeCell(i) }
            endRow()
        }

        // convert top-coords to non-flipped bottom coords
        let contentH = max(top + 8, 200)
        func flip(_ r: NSRect) -> NSRect {
            NSRect(x: r.origin.x, y: contentH - r.origin.y - r.height, width: r.width, height: r.height)
        }
        for (k, v) in cellFrames { cellFrames[k] = flip(v) }
        headers = headers.map { (flip($0.0), $0.1) }
        customHeaderRect = flip(customHeaderRect)
        separatorRect = flip(separatorRect)

        frame.size = NSSize(width: W, height: contentH)
        needsDisplay = true
    }

    func loadVisible(_ rect: NSRect) {
        for (i, f) in cellFrames where f.intersects(rect) {
            guard thumbs[i] == nil, !pending.contains(i) else { continue }
            pending.insert(i)
            loadCell(i)
        }
    }

    private func loadCell(_ i: Int) {
        guard cells.indices.contains(i) else { pending.remove(i); return }
        let c = cells[i]
        DispatchQueue.global().async { [weak self] in
            let img = thumbnail(c.wallpaper)
            let pal: [NSColor]
            if !c.storedColors.isEmpty { pal = c.storedColors }
            else if c.isCustom { pal = customPalette(c.wallpaper) }
            else { pal = parseColorsToml(c.paletteFile) }
            DispatchQueue.main.async {
                // a reload may have reshuffled the cells while this was in
                // flight; only land on the cell it was decoded for
                guard let self, self.cells.indices.contains(i),
                      self.cells[i].wallpaper == c.wallpaper else { return }
                self.thumbs[i] = img
                self.palettes[i] = pal
                self.pending.remove(i)
                self.needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // section labels only: the folder buttons live in the Wallpapers tab,
        // which owns the directory
        for (r, title) in headers {
            drawMidLeft(title, nerdFont("Bold", 13), palette.accent,
                        x: 0, midTop: bounds.height - r.midY, height: bounds.height)
        }
        if cells.contains(where: { $0.isCustom }) {
            palette.muted.withAlphaComponent(0.25).setFill()
            separatorRect.fill()
        }
        for (i, f) in cellFrames {
            drawCell(i, f)
        }
    }

    private func drawCell(_ i: Int, _ f: NSRect) {
        // leave room under the thumbnail for the hover ring (2 px) plus air
        // before the theme name
        let thumbRect = NSRect(x: f.minX, y: f.minY + cellPaletteH + cellLabelH + cellThumbGap,
                               width: f.width, height: f.height - cellPaletteH - cellLabelH - cellThumbGap)
        let thumbCorner = min(windowCornerRadius(7), min(thumbRect.width, thumbRect.height) / 2)
        let thumb = NSBezierPath(roundedRect: thumbRect, xRadius: thumbCorner, yRadius: thumbCorner)
        NSGraphicsContext.current?.saveGraphicsState()
        thumb.setClip()
        if let img = thumbs[i] {
            drawAspectFill(img, in: thumbRect)
        } else {
            palette.itemBG.withAlphaComponent(0.5).setFill()
            thumbRect.fill()
            drawMidCenter("loading…", nerdFont("Regular", 10), palette.muted,
                          centerX: thumbRect.midX, midTop: bounds.height - thumbRect.midY, height: bounds.height)
        }
        NSGraphicsContext.current?.restoreGraphicsState()
        thumb.lineWidth = 1
        palette.muted.withAlphaComponent(0.3).setStroke()
        thumb.stroke()

        // the focus-ring accent, drawn on the thumbnail's own outline: no gap
        // to the picture, and it inherits the radius from windowCornerRadius()
        if i == hoveredIndex || (selectionMode && selected.contains(i)) {
            thumb.lineWidth = 2
            palette.accent.setStroke()
            thumb.stroke()
        }

        let titleFont = nerdFont("Regular", 11)
        let badgeFont = nerdFont("Regular", 10)
        let n = cells[i].variations
        let badge = n > 0 ? "· \(n) variation\(n == 1 ? "" : "s")" : ""
        let badgeW = badge.isEmpty ? 0 : advance(badge, badgeFont) + 8
        let title = truncate(cells[i].title, titleFont, f.width - badgeW)
        let titleTop = bounds.height - (f.minY + cellPaletteH + cellLabelH)
        drawTopLeft(title, titleFont, palette.label,
                    x: f.minX, top: titleTop, height: bounds.height)
        if !badge.isEmpty {
            drawTopLeft(badge, badgeFont, palette.muted,
                        x: f.minX + advance(title, titleFont) + 8,
                        top: titleTop, height: bounds.height)
        }

        // palette strip along the bottom
        let colors = palettes[i] ?? []
        if !colors.isEmpty {
            let sw = f.width / CGFloat(colors.count)
            for (j, col) in colors.enumerated() {
                col.setFill()
                NSRect(x: f.minX + CGFloat(j) * sw, y: f.minY, width: sw + 0.5, height: cellPaletteH).fill()
            }
        } else {
            palette.itemBG.withAlphaComponent(0.5).setFill()
            NSRect(x: f.minX, y: f.minY, width: f.width, height: cellPaletteH).fill()
        }

        // In selection mode every custom cell carries a checkbox; otherwise
        // the hovered custom cell carries the Edit/Customize pill, the door
        // into the Theme Editor. No scrim either way: the picture stays whole.
        if cells[i].isCustom {
            if selectionMode {
                drawCheckbox(selected.contains(i), in: checkRect(f))
            } else if i == hoveredIndex {
                let label = pillLabel(cells[i])
                let pill = editPillRect(f, label: label)
                let shape = NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6)
                palette.accent.setFill()
                shape.fill()
                let ink = relativeLuminance(palette.accent) > 0.179 ? palette.barBG : palette.label
                drawMidCenter(label, nerdFont("Bold", 11), ink,
                              centerX: pill.midX, midTop: bounds.height - pill.midY, height: bounds.height)
            }
        }
    }

    // The selection checkbox sits at the thumbnail's top-right corner.
    private func drawCheckbox(_ on: Bool, in cr: NSRect) {
        let box = NSBezierPath(roundedRect: cr, xRadius: 6, yRadius: 6)
        if on {
            palette.accent.setFill(); box.fill()
            let ink = relativeLuminance(palette.accent) > 0.179 ? palette.barBG : palette.label
            whDrawGlyphCentered("\u{f00c}", in: cr, color: ink, size: 11)
        } else {
            NSColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 0.5).setFill(); box.fill()
            NSColor.white.withAlphaComponent(0.18).setStroke(); box.lineWidth = 1; box.stroke()
            whDrawGlyphCentered("\u{f096}", in: cr, color: .white, size: 11)
        }
    }

    // A named variation resumes a saved record; a raw wallpaper seeds a new
    // one. The label says which, and the pill's width follows it.
    private func pillLabel(_ c: ThemeCell) -> String {
        c.editionID != nil ? "Edit" : "Customize"
    }

    // The pill sits over the picture's bottom-right corner. drawCell and
    // mouseDown share this rect, so the hit test can never disagree with the
    // pill that is on screen.
    private func editPillRect(_ f: NSRect, label: String) -> NSRect {
        let thumbRect = NSRect(x: f.minX, y: f.minY + cellPaletteH + cellLabelH + cellThumbGap,
                               width: f.width, height: f.height - cellPaletteH - cellLabelH - cellThumbGap)
        let w = advance(label, nerdFont("Bold", 11)) + 20
        return NSRect(x: thumbRect.maxX - pillInset - w,
                      y: thumbRect.minY + pillInset,
                      width: w, height: pillH)
    }

    // The selection checkbox sits at the thumbnail's top-right corner;
    // drawCell and mouseDown share this rect.
    private func checkRect(_ f: NSRect) -> NSRect {
        let thumbRect = NSRect(x: f.minX, y: f.minY + cellPaletteH + cellLabelH + cellThumbGap,
                               width: f.width, height: f.height - cellPaletteH - cellLabelH - cellThumbGap)
        let s: CGFloat = pillH
        return NSRect(x: thumbRect.maxX - pillInset - s,
                      y: thumbRect.maxY - pillInset - s, width: s, height: s)
    }

    private func drawAspectFill(_ img: NSImage, in rect: NSRect) {
        let imgA = img.size.width / max(img.size.height, 1)
        let rectA = rect.width / max(rect.height, 1)
        var src = NSRect(origin: .zero, size: img.size)
        if imgA > rectA {
            let w = img.size.height * rectA
            src = NSRect(x: (img.size.width - w) / 2, y: 0, width: w, height: img.size.height)
        } else {
            let h = img.size.width / rectA
            src = NSRect(x: 0, y: (img.size.height - h) / 2, width: img.size.width, height: h)
        }
        img.draw(in: rect, from: src, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, f) in cellFrames where f.contains(p) {
            let c = cells[i]
            // in selection mode a click anywhere on a custom cell toggles it
            if selectionMode {
                if c.isCustom { onToggleSelect?(i) }
                return
            }
            // a visible Edit/Customize pill takes the click; anywhere else
            // applies the theme as before
            if i == hoveredIndex, c.isCustom, editPillRect(f, label: pillLabel(c)).contains(p) {
                onEdit?(c)
                return
            }
            applyTheme(c) { [weak self] in self?.onApplied?(c.title) }
            return
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Right-click on a named edition opens a small themed popup at the click
    // (an NSMenu is a grey system panel). Raw Wallpaper #N cells have no
    // record to copy, so they get no menu.
    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = cellFrames.first(where: { $0.value.contains(p) })?.key,
              cells.indices.contains(i), cells[i].isCustom, cells[i].editionID != nil else {
            super.rightMouseDown(with: event)
            return
        }
        let cell = cells[i]
        ContextMenu.show(items: ["Duplicate Theme"], at: NSEvent.mouseLocation) { [weak self] _ in
            self?.onDuplicate?(cell)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        hoverTracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hit = cellFrames.first { $0.value.contains(p) }?.key
        guard hit != hoveredIndex else { return }
        hoveredIndex = hit
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredIndex != nil else { return }
        hoveredIndex = nil
        needsDisplay = true
    }
}

func truncate(_ s: String, _ font: NSFont, _ maxW: CGFloat) -> String {
    if advance(s, font) <= maxW { return s }
    var out = s
    while !out.isEmpty, advance(out + "…", font) > maxW { out.removeLast() }
    return out + "…"
}

final class ThemesTabView: NSView, ScrollStepTab {
    // the one live Themes tab, so the dashboard's Esc/Delete keys can reach a
    // running selection. nil unless a selection is in progress.
    static weak var selecting: ThemesTabView?

    private let scroll = NSScrollView()
    private let grid = ThemeGridView()
    func scrollStep(_ dy: CGFloat) { scrollBy(scroll, dy) }
    func refreshColors() {
        needsDisplay = true
        grid.needsDisplay = true
        scroller.refresh()
        selectButton.needsDisplay = true
        deleteButton.needsDisplay = true
    }
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8
    private let selectButton = ButtonView()
    private let deleteButton = ButtonView()
    private var selectionMode = false
    // the same 54pt bottom bar as Options and Workspaces
    private let bottomBand: CGFloat = 54
    private var status = ""
    private var needsGridRebuild = true
    var onApplied: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = grid
        addSubview(scroller)
        scroller.scrollView = scroll
        selectButton.title = "Select"
        selectButton.secondary = true
        selectButton.fontSize = 12
        selectButton.onClick = { [weak self] in self?.toggleSelection() }
        addSubview(selectButton)
        deleteButton.title = "Delete"
        deleteButton.danger = true
        deleteButton.fontSize = 12
        deleteButton.isHidden = true
        deleteButton.onClick = { [weak self] in self?.confirmDeleteSelection() }
        addSubview(deleteButton)
        grid.onApplied = { [weak self] title in
            self?.status = "Applied \(title)"
            self?.needsDisplay = true
            self?.onApplied?()
        }
        grid.onEdit = { [weak self] cell in
            guard let self, let w = self.window else { return }
            ThemeEditor.present(cell: cell, from: w) { [weak self] message in
                self?.status = message
                self?.needsDisplay = true
                self?.onApplied?()
            }
        }
        grid.onToggleSelect = { [weak self] i in self?.toggleCell(i) }
        grid.onDuplicate = { [weak self] cell in self?.duplicate(cell) }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(visibleChanged),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        reload()
        watchSources()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    // re-read when the tab is shown, so a wallpaper added or removed while
    // the modal is closed is picked up. Leaving the tab drops any selection,
    // so Esc on another tab is not swallowed by a stale selection.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { reload() } else { exitSelection() }
    }

    // Off-screen review only.
    func debugHoverFirstCustom() {
        if let i = grid.cells.firstIndex(where: { $0.isCustom }) { grid.debugSetHover(i) }
    }
    func debugSetStatus(_ s: String) { status = s; needsDisplay = true }
    func debugSelectFirstCustom(_ n: Int) {
        selectionMode = true
        grid.selectionMode = true
        selectButton.title = "Done"
        for i in grid.cells.indices where grid.cells[i].isCustom {
            grid.selected.insert(i)
            if grid.selected.count >= n { break }
        }
        updateDeleteButton()
        needsLayout = true
    }

    // --- bulk selection ----------------------------------------------------

    private func toggleSelection() {
        selectionMode.toggle()
        if selectionMode {
            ThemesTabView.selecting = self
        } else {
            grid.selected.removeAll()
            if ThemesTabView.selecting === self { ThemesTabView.selecting = nil }
        }
        grid.selectionMode = selectionMode
        selectButton.title = selectionMode ? "Done" : "Select"
        updateDeleteButton()
        needsLayout = true
    }

    func exitSelection() { if selectionMode { toggleSelection() } }

    private func toggleCell(_ i: Int) {
        guard grid.cells.indices.contains(i), grid.cells[i].isCustom else { return }
        if grid.selected.contains(i) { grid.selected.remove(i) } else { grid.selected.insert(i) }
        updateDeleteButton()
    }

    // The Delete button only exists once something is ticked — an always-on
    // red button with nothing to delete is a trap — and vanishes when the
    // last checkbox is cleared.
    private func updateDeleteButton() {
        let n = grid.selected.count
        deleteButton.isHidden = !selectionMode || n == 0
        deleteButton.title = "Delete \(n)"
        needsDisplay = true
    }

    // Esc / Delete reach here from the dashboard's key monitor while a
    // selection is live, so the keys do not fall through to the dashboard.
    @discardableResult
    func handleEscapeKey() -> Bool {
        guard selectionMode else { return false }
        exitSelection()
        return true
    }

    @discardableResult
    func handleDeleteKey() -> Bool {
        guard selectionMode, !grid.selected.isEmpty else { return false }
        confirmDeleteSelection()
        return true
    }

    // Ask before removing the selection. Named editions are records; raw
    // wallpapers are files that go to the Trash, with their editions as a
    // convenience option. Nothing is hard-deleted.
    private func confirmDeleteSelection() {
        let picked = grid.selected.compactMap { grid.cells.indices.contains($0) ? grid.cells[$0] : nil }
        guard !picked.isEmpty else { return }
        let editions = picked.filter { $0.editionID != nil }
        let seeds = picked.filter { $0.editionID == nil }
        let variations = seeds.reduce(0) { $0 + $1.variations }
        var parts: [String] = []
        if !editions.isEmpty { parts.append("\(editions.count) theme\(editions.count == 1 ? "" : "s")") }
        if !seeds.isEmpty { parts.append("\(seeds.count) wallpaper\(seeds.count == 1 ? "" : "s")") }
        var labels: [String] = []
        var defaults: [Bool] = []
        if !seeds.isEmpty {
            labels.append(seeds.count == 1 ? "Move the wallpaper file to Trash"
                                           : "Move the wallpaper files to Trash")
            defaults.append(true)
        }
        if variations > 0 {
            labels.append("Also delete the \(variations) theme\(variations == 1 ? "" : "s") built from them")
            defaults.append(true)
        }
        let subtitle = seeds.isEmpty
            ? "Themes are removed. Their wallpapers stay in place."
            : "Wallpaper files move to the Trash, so they can be recovered."
        DeleteConfirm.present(from: self,
                              title: "Delete \(parts.joined(separator: " and "))?",
                              subtitle: subtitle, labels: labels, defaults: defaults,
                              onDelete: { vals in
            let trashSeeds = seeds.isEmpty ? false : (vals.first ?? true)
            let delEditions = variations > 0 ? (vals.count > 1 ? vals[1] : false) : false
            let count = picked.count
            DispatchQueue.global().async {
                for c in editions {
                    if let id = c.editionID {
                        _ = shell("\(HOME)/.local/bin/omacosy-themecore theme delete \(shellQuote(id)) 2>&1")
                    }
                }
                if delEditions {
                    let targets = Set(seeds.map { canonicalPath($0.wallpaper) })
                    for e in allEditions() where e.sourcePath.map({ targets.contains(canonicalPath($0)) }) == true {
                        _ = shell("\(HOME)/.local/bin/omacosy-themecore theme delete \(shellQuote(e.id)) 2>&1")
                    }
                }
                if trashSeeds {
                    for c in seeds {
                        _ = shell("\(HOME)/.local/bin/omacosy-themecore wallpaper trash \(shellQuote(c.wallpaper)) 2>&1")
                    }
                }
                DispatchQueue.main.async {
                    self.exitSelection()
                    self.status = "Deleted \(count) item\(count == 1 ? "" : "s")"
                    self.reload()
                }
            }
        })
    }

    // Right-click Duplicate Theme: a copy under "<name> #N", N from 2.
    private func duplicate(_ cell: ThemeCell) {
        guard let id = cell.editionID else { return }
        let name = nextDuplicateName(cell.title)
        status = "Duplicating \(cell.title)…"
        needsDisplay = true
        DispatchQueue.global().async { [weak self] in
            _ = shell("\(HOME)/.local/bin/omacosy-themecore theme duplicate \(shellQuote(id)) --name \(shellQuote(name)) 2>&1")
            DispatchQueue.main.async {
                self?.status = "Duplicated \(name)"
                self?.reload()
            }
        }
    }

    private var watchedPaths: [String] = []
    private func watchSources() {
        var paths: [String] = []
        if let r = repoDir() { paths.append(r + "/themes") }
        if let d = grid.customDir { paths.append(d) }
        paths.append(HOME + "/.config/omacosy/themes")
        paths.append(HOME + "/.config/omacosy/themes.conf")
        for p in paths where !watchedPaths.contains(p) {
            watchedPaths.append(p)
            watch(p) { [weak self] in self?.reload() }
        }
    }

    @objc private func visibleChanged() { grid.loadVisible(scroll.documentVisibleRect); scroller.refresh() }

    func reload() {
        let cells = stockVariants() + customVariants()
        let dir = wallpapersDir()

        // Re-entering the tab re-reads the shelves. When nothing changed,
        // leave the decoded thumbnails and palettes exactly as they are:
        // clearing them repaints a grid of "loading…" placeholders for a
        // frame, which reads as a flicker when the gallery is already at
        // the top and no scroll motion hides it.
        if cells == grid.cells, dir == grid.customDir {
            needsGridRebuild = true
            needsLayout = true
            return
        }

        // The set changed: keep what is still valid, keyed by wallpaper,
        // because an added or removed picture shifts every index.
        var decodedThumbs: [String: NSImage] = [:]
        var decodedPalettes: [String: [NSColor]] = [:]
        for (i, c) in grid.cells.enumerated() {
            if let t = grid.thumbs[i] { decodedThumbs[c.wallpaper] = t }
            if let p = grid.palettes[i] { decodedPalettes[c.wallpaper] = p }
        }

        grid.cells = cells
        grid.customDir = dir

        var thumbs: [Int: NSImage] = [:]
        var palettes: [Int: [NSColor]] = [:]
        for (i, c) in cells.enumerated() {
            if let t = decodedThumbs[c.wallpaper] { thumbs[i] = t }
            if let p = decodedPalettes[c.wallpaper] { palettes[i] = p }
        }
        grid.thumbs = thumbs
        grid.palettes = palettes
        grid.pending.removeAll()
        needsGridRebuild = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let band = bottomBand
        let scrollH = max(0, bounds.height - band)
        scroll.frame = NSRect(x: 0, y: band, width: max(0, bounds.width - scrollerW - 14), height: scrollH)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: band, width: scrollerW, height: scrollH)
        scroller.refresh()
        let by = (band - 24) / 2
        selectButton.frame = NSRect(x: bounds.width - 96, y: by, width: 96, height: 24)
        deleteButton.frame = NSRect(x: selectButton.frame.minX - 8 - 96, y: by, width: 96, height: 24)
        let w = scroll.contentSize.width
        if w > 0 {
            if abs(grid.frame.width - w) > 0.5 {
                grid.frame.size.width = w
                needsGridRebuild = true
            }
            if needsGridRebuild {
                grid.rebuild()
                needsGridRebuild = false
                // open at the top (the non-flipped document's origin is the
                // bottom, which otherwise shows the custom section first)
                let top = max(0, grid.frame.height - scroll.contentSize.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
                scroll.reflectScrolledClipView(scroll.contentView)
                scroller.refresh()
            }
        }
        grid.loadVisible(scroll.documentVisibleRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        // the same bottom bar as Options / Workspaces: a hairline above it,
        // with the buttons right-aligned and the status centred horizontally
        // in the bar (and everything on the bar's mid line)
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bottomBand - 0.5, width: bounds.width, height: 1).fill()
        if !status.isEmpty {
            let f = nerdFont("Regular", 11)
            let right = max(0, (deleteButton.isHidden ? selectButton.frame.minX : deleteButton.frame.minX) - 12)
            let text = truncate(status, f, right)
            drawMidLeft(text, f, palette.muted, x: max(0, (right - advance(text, f)) / 2),
                        midTop: bounds.height - bottomBand / 2, height: bounds.height)
        }
    }
}

// --- theme editor ----------------------------------------------------------

// The editor opens on one of two things: a stored edition (its record is
// loaded from the library) or a new draft seeded from a raw wallpaper's
// Magic palette. 5a-2 builds the shell and the door; the Palette Builder,
// the previews and the Wallpaper Editor arrive in later sessions.
enum EditorSubject {
    case edition(ThemeEdition)
    case draft(wallpaper: String)

    var displayName: String {
        switch self {
        case .edition(let e): return e.name
        case .draft(let w): return prettyWallName((w as NSString).lastPathComponent)
        }
    }
}

final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// The wallpaper editor's four slider groups, in Aether's categories. Ranges
// follow FilterControls.svelte (the real Aether UI, and the scale the engine's
// /4 blur expects); the docs' §Filter Categories ranges differ for blur
// (0-5px) and brightness/contrast (50-150), which do not fit the engine.
enum EditorFilterFields {
    static let basic: [SliderField] = [
        SliderField(key: "blur", label: "Blur", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "brightness", label: "Brightness", min: 0, max: 200, step: 1, def: 100),
        SliderField(key: "contrast", label: "Contrast", min: 0, max: 200, step: 1, def: 100),
        SliderField(key: "saturation", label: "Saturation", min: 0, max: 200, step: 1, def: 100),
        SliderField(key: "hueRotate", label: "Hue Shift", min: 0, max: 360, step: 1, def: 0),
    ]
    static let effects: [SliderField] = [
        SliderField(key: "sepia", label: "Sepia", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "invert", label: "Invert", min: 0, max: 100, step: 1, def: 0),
    ]
    static let advanced: [SliderField] = [
        SliderField(key: "exposure", label: "Exposure", min: -100, max: 100, step: 1, def: 0),
        SliderField(key: "sharpen", label: "Sharpen", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "vignette", label: "Vignette", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "grain", label: "Grain", min: 0, max: 10, step: 1, def: 0),
        SliderField(key: "shadows", label: "Shadows", min: -100, max: 100, step: 1, def: 0),
        SliderField(key: "highlights", label: "Highlights", min: -100, max: 100, step: 1, def: 0),
    ]
    static let colourTone: [SliderField] = [
        SliderField(key: "temperature", label: "Temperature", min: -100, max: 100, step: 1, def: 0),
        SliderField(key: "tint", label: "Tint", min: -100, max: 100, step: 1, def: 0),
    ]
    static let groups: [(title: String, fields: [SliderField])] = [
        ("Basic", basic), ("Effects", effects), ("Advanced", advanced), ("Colour Tone", colourTone),
    ]
}

// The 12 quick presets of docs/wallpaper-editor.md, verbatim from Aether's
// FilterControls.svelte (mirrors themecore's ImagePresets). Each is a delta
// over the current state, so absent fields keep whatever the user chose.
enum EditorPresets {
    static let all: [(name: String, values: [String: Double])] = [
        ("Muted", ["brightness": 95, "contrast": 85, "saturation": 60, "exposure": -10]),
        ("Dramatic", ["brightness": 90, "contrast": 130, "saturation": 110]),
        ("Soft", ["brightness": 105, "contrast": 90, "saturation": 95, "exposure": 10]),
        ("Vintage", ["brightness": 95, "contrast": 110, "saturation": 70, "sepia": 30]),
        ("Vibrant", ["brightness": 105, "contrast": 115, "saturation": 140, "exposure": 10]),
        ("Faded", ["brightness": 110, "contrast": 75, "saturation": 65, "exposure": 20]),
        ("Cool", ["contrast": 105, "saturation": 95, "hueRotate": 200]),
        ("Warm", ["contrast": 105, "saturation": 95, "hueRotate": 20]),
        ("Cinematic", ["contrast": 120, "saturation": 85, "shadows": 20, "highlights": -15, "vignette": 35]),
        ("Film", ["contrast": 95, "saturation": 90, "grain": 3, "sepia": 15, "vignette": 20]),
        ("Crisp", ["contrast": 110, "saturation": 105, "sharpen": 40, "exposure": 5]),
        ("Portrait", ["brightness": 102, "contrast": 95, "saturation": 92, "shadows": 15, "vignette": 25]),
    ]
}

// The editor's histogram: the luminance as a filled backdrop, R/G/B as
// coloured traces, each series normalised to its own peak.
final class HistogramView: NSView {
    var lum: [Int] = [] { didSet { needsDisplay = true } }
    var r: [Int] = [] { didSet { needsDisplay = true } }
    var g: [Int] = [] { didSet { needsDisplay = true } }
    var b: [Int] = [] { didSet { needsDisplay = true } }

    static let viewHeight: CGFloat = 72

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                               xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.35).setFill()
        box.fill()
        palette.muted.withAlphaComponent(0.3).setStroke()
        box.lineWidth = 1
        box.stroke()
        guard lum.count == 256 else {
            drawMidCenter("Histogram", nerdFont("Regular", 11), palette.muted,
                          centerX: bounds.midX, midTop: bounds.midY, height: bounds.height)
            return
        }
        let inner = bounds.insetBy(dx: 6, dy: 6)
        func point(_ i: Int, _ v: Int, _ maxV: Int) -> NSPoint {
            NSPoint(x: inner.minX + inner.width * CGFloat(i) / 255,
                    y: inner.minY + inner.height * CGFloat(Double(v) / Double(maxV)))
        }
        if let maxP = lum.max(), maxP > 0 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: inner.minX, y: inner.minY))
            for i in 0..<256 { path.line(to: point(i, lum[i], maxP)) }
            path.line(to: NSPoint(x: inner.maxX, y: inner.minY))
            path.close()
            palette.muted.withAlphaComponent(0.35).setFill()
            path.fill()
        }
        for (bins, color) in [(r, NSColor.systemRed), (g, .systemGreen), (b, .systemBlue)] {
            guard let maxP = bins.max(), maxP > 0 else { continue }
            let path = NSBezierPath()
            for i in 0..<256 {
                if i == 0 { path.move(to: point(i, bins[i], maxP)) }
                else { path.line(to: point(i, bins[i], maxP)) }
            }
            color.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

// The scrollable editor body: the histogram and its Auto buttons, the four
// slider groups, then the picture history's own Undo / Redo / Reset (separate
// from the palette's). The edited picture is shown in the central pane.
final class EditorPanelDoc: NSView {
    let histogram = HistogramView()
    let strengthSlider = AdjustmentSliderView(
        spec: SliderField(key: "strength", label: "Strength", min: 0, max: 100, step: 1, def: 100))
    let curveView = CurveEditorView()
    let curveResetButton = ButtonView()
    let applyButton = ButtonView()
    let blurToggle = ToggleView()
    let autoLevelsButton = ButtonView()
    let autoContrastButton = ButtonView()
    let autoWBButton = ButtonView()
    let gradeStrengthSlider = AdjustmentSliderView(
        spec: SliderField(key: "paletteStrength", label: "Strength", min: 0, max: 100, step: 1, def: 70))
    let gradeAddButton = ButtonView()
    let gradeRemoveButton = ButtonView()
    let gradeWells = (0..<4).map { _ in ColorWellView() }
    let presetsButton = PopupButtonView()
    let cropButton = ButtonView()
    static let ratios: [(label: String, value: Double)] = [
        ("Free", 0), ("1:1", 1), ("16:9", 16.0 / 9), ("4:3", 4.0 / 3),
        ("3:2", 3.0 / 2), ("9:16", 9.0 / 16), ("3:4", 3.0 / 4), ("2:3", 2.0 / 3),
    ]
    let ratioButtons = (0..<8).map { _ in ButtonView() }
    let rotateCCWButton = ButtonView()
    let rotateCWButton = ButtonView()
    let flipHButton = ButtonView()
    let flipVButton = ButtonView()
    let resizeWField = NSTextField()
    let resizeHField = NSTextField()
    let resizeLinkButton = ButtonView()
    let cropResetButton = ButtonView()
    let transformResetButton = ButtonView()
    var onSlider: ((String, Double) -> Void)?
    var onAuto: ((String) -> Void)?
    var onCurve: (([[Double]]) -> Void)?
    var onCurveReset: (() -> Void)?
    var onGradeStops: (([String]) -> Void)?
    var onPreset: ((String) -> Void)?
    var onCropToggle: ((Bool) -> Void)?
    var onCropPreset: ((Double) -> Void)?
    var onCropReset: (() -> Void)?
    var onRotate: ((Double) -> Void)?
    var onFlip: ((String) -> Void)?
    var onResize: ((Double, Double) -> Void)?
    var onTransformReset: (() -> Void)?
    var onApply: (() -> Void)?
    var onBlur: ((Bool) -> Void)?
    private(set) var sliders: [AdjustmentSliderView] = []

    private let insetL: CGFloat = 12
    private let insetR: CGFloat = 12
    private var groupTops: [(title: String, top: CGFloat)] = []
    private var groupFrames: [(top: CGFloat, bottom: CGFloat)] = []
    private var autoTop: CGFloat = 0
    private var curveTop: CGFloat = 0
    private var gradeTop: CGFloat = 0
    private var transformTop: CGFloat = 0
    private var gradeStops: [String] = []
    private var cropOn = false
    private var resizeLinked = true
    private var originalSize = CGSize.zero
    private var rotLabelTop: CGFloat = 0
    private var cropLabelTop: CGFloat = 0
    private var resizeLabelTop: CGFloat = 0
    private var presetTop: CGFloat = 0
    private var histTop: CGFloat = 0
    private var blurTop: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        strengthSlider.onChange = { [weak self] v in self?.onSlider?("strength", v) }
        addSubview(strengthSlider)
        curveView.onChange = { [weak self] points in self?.onCurve?(points) }
        addSubview(curveView)
        curveResetButton.title = "Reset"
        curveResetButton.fontSize = 10
        curveResetButton.secondary = true
        curveResetButton.onClick = { [weak self] in self?.onCurveReset?() }
        addSubview(curveResetButton)
        for (b, title, op) in [(autoLevelsButton, "Levels", "levels"),
                               (autoContrastButton, "Contrast", "contrast"),
                               (autoWBButton, "White Bal.", "white-balance")] {
            b.title = title
            b.fontSize = 10
            b.onClick = { [weak self] in self?.onAuto?(op) }
            addSubview(b)
        }
        presetsButton.title = "Choose…"
        presetsButton.onClick = { [weak self] in
            guard let self else { return }
            let rows = EditorPresets.all.map {
                MethodPicker.Row(header: nil, value: $0.name, label: $0.name)
            }
            MethodPicker.present(from: self.presetsButton, rows: rows, strips: [:],
                                 currentMethod: "", title: "Presets") { [weak self] name in
                self?.presetsButton.title = name
                self?.presetsButton.needsDisplay = true
                self?.onPreset?(name)
            }
        }
        addSubview(presetsButton)
        addSubview(histogram)
        applyButton.title = "Apply to Palette"
        applyButton.toolTip = "Recompute the palette from this edit"
        applyButton.onClick = { [weak self] in self?.onApply?() }
        addSubview(applyButton)
        blurToggle.onChange = { [weak self] on in self?.onBlur?(on) }
        addSubview(blurToggle)
        gradeStrengthSlider.onChange = { [weak self] v in self?.onSlider?("paletteStrength", v) }
        addSubview(gradeStrengthSlider)
        for (i, w) in gradeWells.enumerated() {
            w.isHidden = true
            w.onChange = { [weak self] hex in
                guard let self, i < self.gradeStops.count else { return }
                self.gradeStops[i] = hex
                self.onGradeStops?(self.gradeStops)
            }
            addSubview(w)
        }
        gradeAddButton.title = "+"
        gradeAddButton.toolTip = "Add Colour Stop"
        gradeAddButton.fontSize = 13
        gradeAddButton.onClick = { [weak self] in self?.addGradeStop() }
        addSubview(gradeAddButton)
        gradeRemoveButton.title = "\u{2212}"
        gradeRemoveButton.toolTip = "Remove Colour Stop"
        gradeRemoveButton.fontSize = 13
        gradeRemoveButton.onClick = { [weak self] in self?.removeGradeStop() }
        addSubview(gradeRemoveButton)
        cropButton.title = "Crop"
        cropButton.fontSize = 11
        cropButton.onClick = { [weak self] in
            guard let self else { return }
            self.cropOn.toggle()
            self.onCropToggle?(self.cropOn)
        }
        addSubview(cropButton)
        for (i, spec) in Self.ratios.enumerated() {
            let b = ratioButtons[i]
            b.title = spec.label
            b.fontSize = 9
            b.onClick = { [weak self] in
                guard let self else { return }
                if !self.cropOn {
                    self.cropOn = true
                    self.onCropToggle?(true)
                }
                self.onCropPreset?(spec.value)
            }
            addSubview(b)
        }
        rotateCCWButton.title = "\u{f2ea}"
        rotateCWButton.title = "\u{f2f9}"
        for b in [rotateCCWButton, rotateCWButton] {
            b.centeredByBounds = true
            b.fontSize = 12
            addSubview(b)
        }
        rotateCCWButton.onClick = { [weak self] in self?.onRotate?(-90) }
        rotateCWButton.onClick = { [weak self] in self?.onRotate?(90) }
        for (b, title, which) in [(flipHButton, "Flip H", "h"), (flipVButton, "Flip V", "v")] {
            b.title = title
            b.fontSize = 10
            b.onClick = { [weak self] in self?.onFlip?(which) }
            addSubview(b)
        }
        for f in [resizeWField, resizeHField] {
            f.isBezeled = false
            f.drawsBackground = true
            f.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
            f.textColor = palette.label
            f.font = nerdFont("Regular", 11)
            f.alignment = .center
            f.focusRingType = .none
            f.target = self
            f.action = #selector(resizeCommit)
            addSubview(f)
        }
        transformResetButton.title = "Reset"
        transformResetButton.fontSize = 10
        transformResetButton.secondary = true
        transformResetButton.onClick = { [weak self] in self?.onTransformReset?() }
        addSubview(transformResetButton)
        resizeWField.placeholderString = "Width"
        resizeHField.placeholderString = "Height"
        cropResetButton.title = "Reset Crop"
        cropResetButton.fontSize = 10
        cropResetButton.secondary = true
        cropResetButton.onClick = { [weak self] in self?.onCropReset?() }
        addSubview(cropResetButton)
        resizeLinkButton.title = "\u{f023}"
        resizeLinkButton.fontSize = 11
        resizeLinkButton.centeredByBounds = true
        resizeLinkButton.toolTip = "Keep the original aspect ratio"
        resizeLinkButton.onClick = { [weak self] in
            guard let self else { return }
            self.resizeLinked.toggle()
            self.resizeLinkButton.title = self.resizeLinked ? "\u{f023}" : "\u{f09c}"
            self.resizeLinkButton.needsDisplay = true
        }
        addSubview(resizeLinkButton)
        for group in EditorFilterFields.groups {
            for f in group.fields {
                let s = AdjustmentSliderView(spec: f)
                s.onChange = { [weak self] v in self?.onSlider?(f.key, v) }
                sliders.append(s)
                addSubview(s)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private var contentW: CGFloat { max(0, bounds.width - insetL - insetR) }

    func contentHeight() -> CGFloat {
        var h: CGFloat = 10
        h += 24 + 12                                      // Apply to Palette
        h += AdjustmentSliderView.rowHeight + 10          // Strength
        h += 16 + 22 + 12                                 // AUTO ENHANCE + buttons
        h += 34 + 12                                      // Presets + gap
        h += 26 + HistogramView.viewHeight + 12           // Histogram
        h += 26 + CurveEditorView.viewHeight + 12         // Curves
        h += 24 + 10                                      // Blur Desktop toggle
        for group in EditorFilterFields.groups {
            h += 30
            h += CGFloat(group.fields.count) * AdjustmentSliderView.rowHeight
            h += 24
        }
        h += 26 + 24 + 8 + AdjustmentSliderView.rowHeight + 12   // Palette Grade
        h += 294                                                 // Transform
        return h
    }

    func setHistogram(_ lum: [Int], _ r: [Int], _ g: [Int], _ b: [Int]) {
        histogram.lum = lum
        histogram.r = r
        histogram.g = g
        histogram.b = b
        // the curve draws the luminance histogram as its backdrop
        curveView.histogram = lum
    }

    func setGradeStops(_ stops: [String]) {
        gradeStops = stops
        for (i, w) in gradeWells.enumerated() {
            let show = i < stops.count
            w.isHidden = !show
            if show { w.hex = stops[i] }
        }
        gradeAddButton.isHidden = stops.count >= gradeWells.count
        gradeRemoveButton.isHidden = stops.isEmpty
        needsLayout = true
        needsDisplay = true
    }

    private func addGradeStop() {
        guard gradeStops.count < gradeWells.count else { return }
        gradeStops.append("#808080")
        setGradeStops(gradeStops)
        onGradeStops?(gradeStops)
    }

    private func removeGradeStop() {
        guard !gradeStops.isEmpty else { return }
        gradeStops.removeLast()
        setGradeStops(gradeStops)
        onGradeStops?(gradeStops)
    }

    @objc private func resizeCommit() {
        let w = Double(resizeWField.stringValue) ?? 0
        var h = Double(resizeHField.stringValue) ?? 0
        if resizeLinked, originalSize.width > 0, originalSize.height > 0, w > 0 {
            h = (w / (originalSize.width / originalSize.height)).rounded()
        }
        onResize?(w, h)
    }

    func setOriginalSize(_ size: CGSize) {
        originalSize = size
        needsDisplay = true
    }

    func setBlur(_ on: Bool) { blurToggle.isOn = on }

    // The resize fields and the crop toggle follow the state; the crop MODE
    // itself is the user's (set through onCropToggle), not derived from a rect.
    func setTransform(_ f: EditorFilters) {
        if resizeWField.currentEditor() == nil {
            resizeWField.stringValue = f.resizeW > 0 ? "\(Int(f.resizeW))" : ""
        }
        if resizeHField.currentEditor() == nil {
            resizeHField.stringValue = f.resizeH > 0 ? "\(Int(f.resizeH))" : ""
        }
        needsDisplay = true
    }

    func setCropOn(_ on: Bool) {
        cropOn = on
        needsDisplay = true
    }

    private func rect(top: CGFloat, h: CGFloat, x: CGFloat, w: CGFloat) -> NSRect {
        NSRect(x: x, y: bounds.height - top - h, width: w, height: h)
    }

    override func layout() {
        super.layout()
        var top: CGFloat = 10
        applyButton.frame = rect(top: top, h: 24, x: insetL, w: contentW)
        top += 24 + 12
        strengthSlider.frame = rect(top: top, h: AdjustmentSliderView.rowHeight,
                                    x: insetL, w: contentW)
        top += AdjustmentSliderView.rowHeight + 10
        autoTop = top
        top += 16                                         // AUTO ENHANCE label
        let gap: CGFloat = 2
        let bw = max(50, (contentW - gap * 2) / 3)
        autoLevelsButton.frame = rect(top: top, h: 22, x: insetL, w: bw)
        autoContrastButton.frame = rect(top: top, h: 22, x: insetL + bw + gap, w: bw)
        autoWBButton.frame = rect(top: top, h: 22, x: insetL + (bw + gap) * 2, w: bw)
        top += 22 + 12
        presetTop = top
        presetsButton.frame = rect(top: top + 3, h: 26,
                                   x: insetL + max(0, contentW - 170), w: min(170, contentW))
        top += 34 + 12
        histTop = top
        top += 26
        histogram.frame = rect(top: top, h: HistogramView.viewHeight, x: insetL, w: contentW)
        top += HistogramView.viewHeight + 12
        curveTop = top
        curveResetButton.frame = rect(top: top, h: 20, x: insetL + contentW - 60, w: 60)
        top += 26
        curveView.frame = rect(top: top, h: CurveEditorView.viewHeight, x: insetL, w: contentW)
        top += CurveEditorView.viewHeight + 12
        blurTop = top
        blurToggle.frame = rect(top: top, h: 24, x: insetL + contentW - 46, w: 46)
        top += 24 + 10
        groupTops.removeAll()
        groupFrames.removeAll()
        var i = 0
        for group in EditorFilterFields.groups {
            groupTops.append((group.title, top))
            top += 30
            let blockTop = top
            for _ in group.fields {
                // inset inside the frame so the label and value never touch
                // its line; the frame itself keeps the column edges
                sliders[i].frame = rect(top: top, h: AdjustmentSliderView.rowHeight,
                                        x: insetL + 10, w: contentW - 20)
                top += AdjustmentSliderView.rowHeight
                i += 1
            }
            groupFrames.append((blockTop, top))
            top += 24
        }
        // Palette Grade: 2-4 colour stops plus a strength slider.
        gradeTop = top
        top += 26
        let sw: CGFloat = 24, swGap: CGFloat = 6
        var gx = insetL
        for (i, w) in gradeWells.enumerated() where i < gradeStops.count {
            w.frame = rect(top: top, h: sw, x: gx, w: sw)
            gx += sw + swGap
        }
        gradeAddButton.frame = rect(top: top, h: sw, x: gx, w: 24)
        gradeRemoveButton.frame = rect(top: top, h: sw, x: gx + 30, w: 24)
        top += sw + 8
        gradeStrengthSlider.frame = rect(top: top, h: AdjustmentSliderView.rowHeight,
                                         x: insetL, w: contentW)
        top += AdjustmentSliderView.rowHeight + 12
        // Transform, in Aether's order: ROTATE & FLIP, CROP, RESIZE.
        transformTop = top
        top += 26
        rotLabelTop = top
        top += 18
        let q = (contentW - 18) / 4
        for (i, b) in [rotateCCWButton, rotateCWButton, flipHButton, flipVButton].enumerated() {
            b.frame = rect(top: top, h: 24, x: insetL + CGFloat(i) * (q + 6), w: q)
        }
        top += 24 + 12
        cropLabelTop = top
        top += 20
        let rc = (contentW - 12) / 4
        for (i, b) in ratioButtons.enumerated() {
            let row = i / 4, col = i % 4
            b.frame = rect(top: top + CGFloat(row) * 26, h: 22,
                           x: insetL + CGFloat(col) * (rc + 4), w: rc)
        }
        top += 26 * 2 + 2
        top += 14                                        // separation from the ratios
        cropResetButton.frame = rect(top: top, h: 20, x: insetL + contentW - 84, w: 84)
        cropButton.frame = rect(top: top, h: 20, x: cropResetButton.frame.minX - 6 - 64, w: 64)
        top += 20 + 14
        resizeLabelTop = top
        top += 18
        resizeWField.frame = rect(top: top, h: 22, x: insetL, w: 74)
        resizeHField.frame = rect(top: top, h: 22, x: insetL + 86, w: 74)
        resizeLinkButton.frame = rect(top: top, h: 22, x: insetL + 168, w: 24)
        top += 22 + 4
        top += 16                                        // "Original: W × H"
        transformResetButton.frame = rect(top: top, h: 20, x: insetL, w: 70)
        top += 20 + 12
    }

    // A hairline 6 pt above a section's heading: long scrolling panels read
    // as separate feature blocks instead of one continuous column.
    private func drawRule(_ top: CGFloat) {
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: insetL, y: bounds.height - (top - 6), width: contentW, height: 1).fill()
    }

    // A rounded 1 px frame around a multi-slider block: the heading stays
    // above it, the controls sit inside. The frame shares the content column's
    // left and right edges (the same edges as the buttons and popups above),
    // so nothing sticks out of the column.
    private func drawGroupFrame(top: CGFloat, bottom: CGFloat) {
        let r = NSRect(x: insetL, y: bounds.height - bottom - 6,
                       width: contentW, height: (bottom - top) + 12)
        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        palette.muted.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawRule(autoTop)
        drawTopLeft("Auto Enhance", nerdFont("Bold", 12), palette.label,
                    x: insetL, top: autoTop, height: bounds.height)
        drawMidLeft("Presets", nerdFont("Bold", 12), palette.label,
                    x: insetL, midTop: presetTop + 16, height: bounds.height)
        drawRule(histTop)
        drawTopLeft("Histogram", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: histTop, height: bounds.height)
        drawTopLeft("Curves", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: curveTop, height: bounds.height)
        drawMidLeft("Blur Desktop", nerdFont("Bold", 12), palette.label,
                    x: insetL, midTop: blurTop + 12, height: bounds.height)
        for (title, top) in groupTops {
            drawTopLeft(title, nerdFont("Bold", 12), palette.accent,
                        x: insetL, top: top, height: bounds.height)
        }
        for (top, bottom) in groupFrames {
            drawGroupFrame(top: top, bottom: bottom)
        }
        // no rule between the last frame and Palette Grade: the frame separates
        drawTopLeft("Palette Grade", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: gradeTop, height: bounds.height)
        drawRule(transformTop)
        drawTopLeft("Transform", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: transformTop, height: bounds.height)
        drawTopLeft("ROTATE & FLIP", nerdFont("Bold", 10), palette.muted,
                    x: insetL, top: rotLabelTop, height: bounds.height)
        drawTopLeft("CROP", nerdFont("Bold", 10), palette.muted,
                    x: insetL, top: cropLabelTop, height: bounds.height)
        drawTopLeft("RESIZE", nerdFont("Bold", 10), palette.muted,
                    x: insetL, top: resizeLabelTop, height: bounds.height)
        if originalSize.width > 0 {
            drawTopLeft("Original: \(Int(originalSize.width)) × \(Int(originalSize.height))",
                        nerdFont("Regular", 10), palette.muted,
                        x: insetL, top: resizeLabelTop + 48, height: bounds.height)
        }
    }
}

// The right column: controls only. The edited picture is shown in the central
// pane. The picture history's Undo / Redo / Reset sit fixed in the header.
final class EditorColumnView: NSView {
    var state: EditorState? { didSet { wire() } }
    var stepBadge = 0 { didSet { needsDisplay = true } }
    // The Auto and Apply buttons call out to the editor, which owns the picture
    // path and the engine.
    var onAuto: ((String) -> Void)? { didSet { doc.onAuto = onAuto } }
    var onCurve: (([[Double]]) -> Void)? { didSet { doc.onCurve = onCurve } }
    var onCurveReset: (() -> Void)? { didSet { doc.onCurveReset = onCurveReset } }
    var onGradeStops: (([String]) -> Void)? { didSet { doc.onGradeStops = onGradeStops } }
    var onPreset: ((String) -> Void)? { didSet { doc.onPreset = onPreset } }
    var onCropToggle: ((Bool) -> Void)? { didSet { doc.onCropToggle = onCropToggle } }
    var onCropPreset: ((Double) -> Void)? { didSet { doc.onCropPreset = onCropPreset } }
    var onCropReset: (() -> Void)? { didSet { doc.onCropReset = onCropReset } }
    var onRotate: ((Double) -> Void)? { didSet { doc.onRotate = onRotate } }
    var onFlip: ((String) -> Void)? { didSet { doc.onFlip = onFlip } }
    var onResize: ((Double, Double) -> Void)? { didSet { doc.onResize = onResize } }
    var onTransformReset: (() -> Void)? { didSet { doc.onTransformReset = onTransformReset } }
    var onApply: (() -> Void)? { didSet { doc.onApply = onApply } }
    var onBlur: ((Bool) -> Void)? { didSet { doc.onBlur = onBlur } }

    let doc = EditorPanelDoc()
    private let undoButton = ButtonView()
    private let redoButton = ButtonView()
    private let resetButton = ButtonView()
    private let scroll = NSScrollView()
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        undoButton.title = "\u{f0e2}"
        redoButton.title = "\u{f01e}"
        for b in [undoButton, redoButton] {
            b.centeredByBounds = true
            b.fontSize = 12
            addSubview(b)
        }
        undoButton.toolTip = "Undo Picture Edit"
        redoButton.toolTip = "Redo Picture Edit"
        resetButton.title = "Reset"
        resetButton.fontSize = 11
        addSubview(resetButton)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = doc
        addSubview(scroller)
        scroller.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled() { scroller.refresh() }

    func refreshColors() {
        needsDisplay = true
        markTree(doc)
    }

    private func markTree(_ view: NSView) {
        view.needsDisplay = true
        for sub in view.subviews { markTree(sub) }
    }

    private func wire() {
        guard let state else { return }
        // EditorState.onChange belongs to the editor (dirty + the central
        // preview); the column only drives its own controls.
        doc.onSlider = { [weak state] key, value in state?.set(key, value) }
        doc.onAuto = onAuto
        doc.onCurve = onCurve
        doc.onCurveReset = onCurveReset
        doc.onGradeStops = onGradeStops
        doc.onPreset = onPreset
        doc.onCropToggle = onCropToggle
        doc.onCropPreset = onCropPreset
        doc.onCropReset = onCropReset
        doc.onRotate = onRotate
        doc.onFlip = onFlip
        doc.onResize = onResize
        doc.onTransformReset = onTransformReset
        doc.onApply = onApply
        undoButton.onClick = { [weak state] in state?.undo() }
        redoButton.onClick = { [weak state] in state?.redo() }
        resetButton.onClick = { [weak state] in state?.reset() }
        syncFromState()
    }

    // Redraws the slider thumbs from the state; the editor calls this after an
    // undo, redo or reset so the controls follow the history.
    func syncFromState() {
        guard let state else { return }
        for s in doc.sliders { s.setValue(state.filters[s.spec.key], notify: false) }
        doc.strengthSlider.setValue(state.filters["strength"], notify: false)
        doc.curveView.points = state.filters.curvePoints
        doc.setGradeStops(state.filters.paletteStops)
        doc.gradeStrengthSlider.setValue(state.filters["paletteStrength"], notify: false)
        doc.setTransform(state.filters)
    }

    // The editor hands the source's histograms here once it has decoded it.
    func setHistogram(_ lum: [Int], _ r: [Int], _ g: [Int], _ b: [Int]) {
        doc.setHistogram(lum, r, g, b)
    }

    func setOriginalSize(_ size: CGSize) { doc.setOriginalSize(size) }

    func setBlur(_ on: Bool) { doc.setBlur(on) }

    func setApplyProgress(_ p: CGFloat) { doc.applyButton.progress = p }

    override func layout() {
        super.layout()
        let headerH: CGFloat = 40
        let h = max(0, bounds.height - headerH)
        resetButton.frame = NSRect(x: bounds.width - 12 - 56, y: bounds.height - 30,
                                   width: 56, height: 24)
        redoButton.frame = NSRect(x: resetButton.frame.minX - 6 - 24, y: bounds.height - 30,
                                  width: 24, height: 24)
        undoButton.frame = NSRect(x: redoButton.frame.minX - 6 - 24, y: bounds.height - 30,
                                  width: 24, height: 24)
        let scrollW = max(0, bounds.width - scrollerW - 12)
        scroll.frame = NSRect(x: 0, y: 0, width: scrollW, height: h)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: 0, width: scrollerW, height: h)
        scroller.refresh()
        let w = scroll.contentSize.width
        let clipH = scroll.contentSize.height
        let targetH = max(doc.contentHeight(), clipH)
        if w > 0, (abs(doc.frame.width - w) > 0.5 || abs(doc.frame.height - targetH) > 0.5) {
            let first = doc.frame.width == 0
            doc.frame = NSRect(origin: .zero, size: NSSize(width: w, height: targetH))
            doc.needsLayout = true
            doc.layoutSubtreeIfNeeded()
            let clip = scroll.contentView
            let maxY = max(0, targetH - clipH)
            if first { clip.scroll(to: NSPoint(x: 0, y: maxY)); scroll.reflectScrolledClipView(clip) }
            scroller.refresh()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if stepBadge > 0 {
            drawStepBadge(stepBadge, centerX: 24, midTop: 18, height: bounds.height)
        }
        drawMidLeft("Wallpaper Editor", nerdFont("Bold", 13), palette.accent,
                    x: stepBadge > 0 ? 42 : 16, midTop: 18, height: bounds.height)
    }
}

// --- wallpaper filters (Phase 8b) -------------------------------------------

// The dashboard's mirror of themecore's ImageFilters (Aether's Filters). The
// dashboard and themecore are separate binaries built from separate files, so
// this is a deliberate copy of the recipe shape: the engine's `image render`
// stays the record and this drives the fast in-process CoreImage preview only.
// Keep the field names, the JSON keys and the strength rule in step with
// helper/themecore.swift's ImageFilters.
struct EditorFilters: Equatable {
    var blur = 0.0
    var brightness = 100.0
    var contrast = 100.0
    var saturation = 100.0
    var hueRotate = 0.0
    var sepia = 0.0
    var invert = 0.0
    var exposure = 0.0
    var vignette = 0.0
    var sharpen = 0.0
    var grain = 0.0
    var shadows = 0.0
    var highlights = 0.0
    var temperature = 0.0
    var tint = 0.0
    var curvePoints: [[Double]] = []
    var paletteStops: [String] = []
    var paletteStrength = 70.0
    var cropX = 0.0
    var cropY = 0.0
    var cropW = 1.0
    var cropH = 1.0
    var resizeW = 0.0
    var resizeH = 0.0
    var rotate = 0.0
    var flipH = false
    var flipV = false
    var strength = 100.0

    init() {}

    // The same vocabulary `image render --filters` accepts, including the
    // snake_case aliases, so a recipe recorded by the engine round-trips.
    init(json: [String: Any]) {
        self.init()
        let known: Set<String> = ["blur", "brightness", "contrast", "saturation", "hueRotate",
            "hue_rotate", "sepia", "invert", "exposure", "vignette", "sharpen", "grain",
            "shadows", "highlights", "temperature", "tint", "curvePoints", "curve_points",
            "paletteStops", "palette_stops", "paletteStrength", "palette_strength",
            "cropX", "cropY", "cropW", "cropH", "crop_x", "crop_y", "crop_w", "crop_h",
            "resizeW", "resizeH", "resize_w", "resize_h", "rotate", "flipH", "flipV",
            "flip_h", "flip_v", "strength"]
        for (key, value) in json where known.contains(key) {
            switch key {
            case "blur": blur = num(value)
            case "brightness": brightness = num(value)
            case "contrast": contrast = num(value)
            case "saturation": saturation = num(value)
            case "hueRotate", "hue_rotate": hueRotate = num(value)
            case "sepia": sepia = num(value)
            case "invert": invert = num(value)
            case "exposure": exposure = num(value)
            case "vignette": vignette = num(value)
            case "sharpen": sharpen = num(value)
            case "grain": grain = num(value)
            case "shadows": shadows = num(value)
            case "highlights": highlights = num(value)
            case "temperature": temperature = num(value)
            case "tint": tint = num(value)
            case "paletteStrength", "palette_strength": paletteStrength = num(value)
            case "cropX", "crop_x": cropX = num(value)
            case "cropY", "crop_y": cropY = num(value)
            case "cropW", "crop_w": cropW = num(value)
            case "cropH", "crop_h": cropH = num(value)
            case "resizeW", "resize_w": resizeW = num(value)
            case "resizeH", "resize_h": resizeH = num(value)
            case "rotate": rotate = num(value)
            case "strength": strength = num(value)
            case "flipH", "flip_h": flipH = bool(value)
            case "flipV", "flip_v": flipV = bool(value)
            case "curvePoints", "curve_points":
                var pts: [[Double]] = []
                if let outer = value as? [Any] {
                    for row in outer {
                        if let pair = row as? [Any], pair.count == 2,
                           let x = (pair[0] as? NSNumber)?.doubleValue,
                           let y = (pair[1] as? NSNumber)?.doubleValue {
                            pts.append([x, y])
                        }
                    }
                }
                curvePoints = pts
            case "paletteStops", "palette_stops":
                if let list = value as? [String] { paletteStops = list }
            default: break
            }
        }
    }

    private func num(_ value: Any) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        return 0
    }
    private func bool(_ value: Any) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }

    // Aether's applyStrength: structural fields (crop, resize, rotate, flip,
    // palette stops) are not scaled; curve points shift toward y=x.
    func strengthScaled() -> EditorFilters {
        let s = strength / 100
        if s == 1 { return self }
        var f = self
        func lerp(_ v: Double, _ def: Double) -> Double { def + (v - def) * s }
        f.brightness = lerp(brightness, 100)
        f.contrast = lerp(contrast, 100)
        f.saturation = lerp(saturation, 100)
        f.exposure = lerp(exposure, 0)
        f.shadows = lerp(shadows, 0)
        f.highlights = lerp(highlights, 0)
        f.temperature = lerp(temperature, 0)
        f.tint = lerp(tint, 0)
        f.hueRotate = hueRotate * s
        f.sepia = sepia * s
        f.invert = invert * s
        f.vignette = vignette * s
        f.sharpen = sharpen * s
        f.grain = grain * s
        f.blur = blur * s
        f.paletteStrength = paletteStrength * s
        f.curvePoints = curvePoints.map { [$0[0], $0[0] + ($0[1] - $0[0]) * s] }
        return f
    }

    var isIdentity: Bool {
        curvePoints.isEmpty && paletteStops.count < 2 && blur == 0 && brightness == 100
            && contrast == 100 && saturation == 100 && hueRotate == 0 && sepia == 0 && invert == 0
            && exposure == 0 && vignette == 0 && sharpen == 0 && grain == 0 && shadows == 0
            && highlights == 0 && temperature == 0 && tint == 0 && rotate == 0 && !flipH && !flipV
            && cropX == 0 && cropY == 0 && cropW == 1 && cropH == 1 && resizeW == 0 && resizeH == 0
    }

    // Keyed access to the numeric fields the editor's sliders drive.
    subscript(key: String) -> Double {
        get {
            switch key {
            case "blur": return blur
            case "brightness": return brightness
            case "contrast": return contrast
            case "saturation": return saturation
            case "hueRotate": return hueRotate
            case "sepia": return sepia
            case "invert": return invert
            case "exposure": return exposure
            case "vignette": return vignette
            case "sharpen": return sharpen
            case "grain": return grain
            case "shadows": return shadows
            case "highlights": return highlights
            case "temperature": return temperature
            case "tint": return tint
            case "paletteStrength": return paletteStrength
            case "cropX": return cropX
            case "cropY": return cropY
            case "cropW": return cropW
            case "cropH": return cropH
            case "resizeW": return resizeW
            case "resizeH": return resizeH
            case "rotate": return rotate
            case "strength": return strength
            default: return 0
            }
        }
        set {
            switch key {
            case "blur": blur = newValue
            case "brightness": brightness = newValue
            case "contrast": contrast = newValue
            case "saturation": saturation = newValue
            case "hueRotate": hueRotate = newValue
            case "sepia": sepia = newValue
            case "invert": invert = newValue
            case "exposure": exposure = newValue
            case "vignette": vignette = newValue
            case "sharpen": sharpen = newValue
            case "grain": grain = newValue
            case "shadows": shadows = newValue
            case "highlights": highlights = newValue
            case "temperature": temperature = newValue
            case "tint": tint = newValue
            case "paletteStrength": paletteStrength = newValue
            case "cropX": cropX = newValue
            case "cropY": cropY = newValue
            case "cropW": cropW = newValue
            case "cropH": cropH = newValue
            case "resizeW": resizeW = newValue
            case "resizeH": resizeH = newValue
            case "rotate": rotate = newValue
            case "strength": strength = newValue
            default: break
            }
        }
    }

    // The recipe as the engine's `image render --filters` JSON (canonical keys).
    func jsonObject() -> [String: Any] {
        var o: [String: Any] = [
            "blur": blur, "brightness": brightness, "contrast": contrast,
            "saturation": saturation, "hueRotate": hueRotate, "sepia": sepia,
            "invert": invert, "exposure": exposure, "vignette": vignette,
            "sharpen": sharpen, "grain": grain, "shadows": shadows,
            "highlights": highlights, "temperature": temperature, "tint": tint,
            "paletteStrength": paletteStrength, "cropX": cropX, "cropY": cropY,
            "cropW": cropW, "cropH": cropH, "resizeW": resizeW, "resizeH": resizeH,
            "rotate": rotate, "flipH": flipH, "flipV": flipV, "strength": strength,
        ]
        if !curvePoints.isEmpty { o["curvePoints"] = curvePoints }
        if paletteStops.count >= 2 { o["paletteStops"] = paletteStops }
        return o
    }
}

// The wallpaper editor's own state and history, deliberately separate from
// PaletteModel's palette history: an edit to the picture conditions the
// colours it later yields, so the two histories never interleave. Mirrors
// Aether, whose filter history is local to the editor while the palette
// history is a separate global store. 50 deep; a burst on one control inside
// a second folds into a single step.
final class EditorState {
    private(set) var filters = EditorFilters()
    var onChange: (() -> Void)?

    private var undoStack: [EditorFilters] = []
    private var redoStack: [EditorFilters] = []
    private var lastPushKey: String?
    private var lastPushTime = Date.distantPast

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasEdits: Bool { filters != EditorFilters() }

    // One door for a change. Rejected when the value did not move; otherwise
    // it folds (same control, within 1 s) and reports every accepted change.
    func edit(_ key: String?, _ mutate: (inout EditorFilters) -> Void) {
        var next = filters
        mutate(&next)
        guard next != filters else { return }
        pushHistory(key)
        filters = next
        onChange?()
    }

    func set(_ key: String, _ value: Double) { edit(key) { $0[key] = value } }

    func reset() {
        guard hasEdits else { return }
        pushHistory(nil)
        filters = EditorFilters()
        onChange?()
    }

    // Reopening a saved edition: adopt its stored recipe as the baseline,
    // with no history behind it (undo walks only the edits made this session).
    func restore(_ f: EditorFilters) {
        filters = f
        undoStack.removeAll()
        redoStack.removeAll()
        lastPushKey = nil
        lastPushTime = .distantPast
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        redoStack.append(filters)
        filters = entry
        onChange?()
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        undoStack.append(filters)
        filters = entry
        onChange?()
    }

    private func pushHistory(_ key: String?) {
        let now = Date()
        if let key, key == lastPushKey, now.timeIntervalSince(lastPushTime) < 1.0 {
            // same control inside a second: one step, already pushed
            lastPushTime = now
            return
        }
        undoStack.append(filters)
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
        redoStack.removeAll()
        lastPushKey = key
        lastPushTime = now
    }
}

// Parse the door's --filters argument: an inline JSON object or @file, the
// same shape `image render --filters` takes.
func editorFiltersJSON(_ raw: String) -> [String: Any]? {
    let text = raw.hasPrefix("@")
        ? (try? String(contentsOfFile: String(raw.dropFirst()), encoding: .utf8)) ?? ""
        : raw
    guard let data = text.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return nil
    }
    return obj
}

// The in-process preview: the same recipe through CoreImage, best-effort.
// CoreImage cannot always match the engine's scalar maths (the engine's
// brightness multiplies; the tone curve and the palette grade are the engine's
// own LUTs and arrive with their controls; grain is random). Where the two
// differ, the engine's `image render` is the record.
private let editorCIContext = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
])

private func ciColorMatrix(_ image: CIImage, r: CIVector, g: CIVector, b: CIVector,
                           a: CIVector, bias: CIVector) -> CIImage {
    guard let f = CIFilter(name: "CIColorMatrix") else { return image }
    f.setValue(image, forKey: kCIInputImageKey)
    f.setValue(r, forKey: "inputRVector")
    f.setValue(g, forKey: "inputGVector")
    f.setValue(b, forKey: "inputBVector")
    f.setValue(a, forKey: "inputAVector")
    f.setValue(bias, forKey: "inputBiasVector")
    return f.outputImage ?? image
}

// The engine's hue rotation is a fixed linear map (luma/luma·u/v), so the
// preview can use the same matrix instead of CoreImage's own approximation.
private func ciHueColorMatrix(_ image: CIImage, degrees: Double) -> CIImage {
    let h = degrees * Double.pi / 180
    let c = cos(h), s = sin(h)
    let a = [[0.2126, 0.7152, 0.0722],
             [-0.09991, -0.33609, 0.436],
             [0.615, -0.55861, -0.05639]]
    let rot = [[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]]
    let b = [[1.0, 0.0, 1.28033],
             [1.0, -0.21482, -0.38059],
             [1.0, 2.12798, 0.0]]
    var m = [[Double]](repeating: [0, 0, 0], count: 3)
    for i in 0..<3 {
        for j in 0..<3 {
            var sum = 0.0
            for k in 0..<3 { for l in 0..<3 { sum += b[i][k] * rot[k][l] * a[l][j] } }
            m[i][j] = sum
        }
    }
    return ciColorMatrix(image,
        r: CIVector(x: m[0][0], y: m[0][1], z: m[0][2], w: 0),
        g: CIVector(x: m[1][0], y: m[1][1], z: m[1][2], w: 0),
        b: CIVector(x: m[2][0], y: m[2][1], z: m[2][2], w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1),
        bias: CIVector(x: 0, y: 0, z: 0, w: 0))
}

// A tone curve applied to every channel, done as a colour cube because the
// engine's shadow/highlight response is piecewise linear and has no single CI
// filter. The same helper serves the per-channel curve once its controls land.
private func ciCurveCube(_ image: CIImage, lut: [Double], size: Int = 32) -> CIImage {
    func sample(_ x: Double) -> Double {
        let p = min(max(0, x), 1) * 255
        let i = Int(p), f = p - Double(i)
        if i >= 255 { return lut[255] }
        return lut[i] + (lut[i + 1] - lut[i]) * f
    }
    var cube = [Float](repeating: 0, count: size * size * size * 4)
    var idx = 0
    for bi in 0..<size {
        let b = sample(Double(bi) / Double(size - 1))
        for gi in 0..<size {
            let g = sample(Double(gi) / Double(size - 1))
            for ri in 0..<size {
                cube[idx] = Float(sample(Double(ri) / Double(size - 1)))
                cube[idx + 1] = Float(g)
                cube[idx + 2] = Float(b)
                cube[idx + 3] = 1
                idx += 4
            }
        }
    }
    guard let f = CIFilter(name: "CIColorCube") else { return image }
    f.setValue(image, forKey: kCIInputImageKey)
    f.setValue(size, forKey: "inputCubeDimension")
    f.setValue(Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size),
               forKey: "inputCubeData")
    return f.outputImage ?? image
}

// Decode the source once to a CGImage; the editor column caches it and wraps
// it per edit, so a slider drag never re-decodes the file.
func editorSourceCGImage(_ url: URL) -> CGImage? {
    guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        return nil
    }
    return editorCIContext.createCGImage(input, from: input.extent)
}

// The luminance + R/G/B histograms of a decoded picture, matching themecore's
// imageHistogram()/channelHistograms(): a <=512 px sRGB draw, unpremultiplied,
// luminance = (77r + 150g + 29b) >> 8. The dashboard already holds the picture,
// so no engine round-trip is needed for the backdrop.
func editorHistograms(from cg: CGImage, maxWidth: Int = 512)
    -> (lum: [Int], r: [Int], g: [Int], b: [Int]) {
    let empty = [Int](repeating: 0, count: 256)
    let width = cg.width, height = cg.height
    guard width > 0, height > 0 else { return (empty, empty, empty, empty) }
    let dw = min(width, maxWidth)
    let dh = max(1, Int((Double(height) * Double(dw) / Double(width)).rounded()))
    let bytesPerRow = dw * 4
    var buffer = [UInt8](repeating: 0, count: bytesPerRow * dh)
    buffer.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(data: raw.baseAddress, width: dw, height: dh, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dw, height: dh))
    }
    var lum = empty, r = empty, g = empty, b = empty
    for i in stride(from: 0, to: buffer.count, by: 4) {
        let alpha = Int(buffer[i + 3])
        if alpha < 128 { continue }
        var rr = Int(buffer[i]), gg = Int(buffer[i + 1]), bb = Int(buffer[i + 2])
        if alpha != 255 {
            let a = Double(alpha) / 255
            rr = min(255, Int((Double(rr) / a).rounded()))
            gg = min(255, Int((Double(gg) / a).rounded()))
            bb = min(255, Int((Double(bb) / a).rounded()))
        }
        lum[min(255, max(0, (rr * 77 + gg * 150 + bb * 29) >> 8))] += 1
        r[rr] += 1; g[gg] += 1; b[bb] += 1
    }
    return (lum, r, g, b)
}

// The largest centred crop rect (fractions of the source) whose pixel aspect is
// `ratio`, for the ratio presets.
func editorCropRect(ratio: Double, imageSize: CGSize) -> CGRect {
    let a = imageSize.width / max(1, imageSize.height)
    let r = CGFloat(ratio)
    var w: CGFloat = 1, h: CGFloat = 1
    if r > a { h = a / r } else { w = r / a }
    return CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
}

// themecore's buildPaletteLUT, mirrored for the preview's gradient: stops
// sorted by HSL lightness, interpolated in HSL, the output lightness pinned to
// the LUT axis. 256 RGB triplets. The engine remains the source of truth.
func dashboardPaletteLUT(_ stops: [String]) -> [UInt8]? {
    guard stops.count >= 2 else { return nil }
    var hsl = stops.map { hslComponents($0) }
    hsl.sort { $0.l < $1.l }
    let segs = hsl.count - 1
    var lut = [UInt8](repeating: 0, count: 256 * 3)
    for y in 0..<256 {
        let t = Double(y) / 255
        let pos = t * Double(segs)
        let i0 = min(segs - 1, Int(pos.rounded(.down)))
        let f = pos - Double(i0)
        let a = hsl[i0], b = hsl[i0 + 1]
        let h = lerpHueDeg(a.h, b.h, f)
        let s = a.s * (1 - f) + b.s * f
        let hex = hslHex(h, s, t * 100)
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if clean.count == 6, let v = UInt64(clean, radix: 16) {
            lut[y * 3] = UInt8((v >> 16) & 0xff)
            lut[y * 3 + 1] = UInt8((v >> 8) & 0xff)
            lut[y * 3 + 2] = UInt8(v & 0xff)
        }
    }
    return lut
}

func lerpHueDeg(_ a: Double, _ b: Double, _ f: Double) -> Double {
    var d = (b - a).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return a + d * f
}

// The palette grade as a colour cube: out = src*(1-t) + LUT[lightness]*t with
// lightness = (max+min)/2, exactly the engine's mapping (the LUT axis is HSL
// lightness). CIColorMap approximates it by luminance; a cube does not.
private func ciPaletteGradeCube(_ image: CIImage, lut: [UInt8], strength: Double,
                                size: Int = 32) -> CIImage {
    var cube = [Float](repeating: 0, count: size * size * size * 4)
    var idx = 0
    for bi in 0..<size {
        let b = Double(bi) / Double(size - 1)
        for gi in 0..<size {
            let g = Double(gi) / Double(size - 1)
            for ri in 0..<size {
                let r = Double(ri) / Double(size - 1)
                let light = (max(r, max(g, b)) + min(r, min(g, b))) / 2
                let li = min(255, max(0, Int((light * 255).rounded()))) * 3
                let tr = Double(lut[li]) / 255
                let tg = Double(lut[li + 1]) / 255
                let tb = Double(lut[li + 2]) / 255
                cube[idx] = Float(r * (1 - strength) + tr * strength)
                cube[idx + 1] = Float(g * (1 - strength) + tg * strength)
                cube[idx + 2] = Float(b * (1 - strength) + tb * strength)
                cube[idx + 3] = 1
                idx += 4
            }
        }
    }
    guard let f = CIFilter(name: "CIColorCube") else { return image }
    f.setValue(image, forKey: kCIInputImageKey)
    f.setValue(size, forKey: "inputCubeDimension")
    f.setValue(Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size),
               forKey: "inputCubeData")
    return f.outputImage ?? image
}

// Source-taking wrapper for the door: decode and render in one call.
func imagePreviewCGImage(source: URL, raw: EditorFilters, maxSize: Int = 960) -> CGImage? {
    guard let input = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]) else {
        return nil
    }
    return editorPreviewRender(input, raw: raw, maxSize: maxSize)
}

// The render itself — crop, resize, the long-side cap, then the colour chain
// and the transforms — on an already-loaded image.
func editorPreviewRender(_ input: CIImage, raw: EditorFilters, maxSize: Int) -> CGImage? {
    let f = raw.strengthScaled()
    let natW = input.extent.width, natH = input.extent.height
    guard natW >= 1, natH >= 1 else { return nil }

    // Crop: fractions from the top-left of the source; CoreImage's y is up.
    let ox = min(max(0, (f.cropX * Double(natW)).rounded()), max(0, Double(natW) - 1))
    let oy = min(max(0, (f.cropY * Double(natH)).rounded()), max(0, Double(natH) - 1))
    let ow = min(max(1, (f.cropW * Double(natW)).rounded()), Double(natW) - ox)
    let oh = min(max(1, (f.cropH * Double(natH)).rounded()), Double(natH) - oy)
    let cropRect = CGRect(x: ox, y: Double(natH) - (oy + oh), width: ow, height: oh)
    var ci = input.cropped(to: cropRect)
    ci = ci.transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))

    // Resize, then the preview's long-side cap — the engine's own arithmetic.
    var outW = ow, outH = oh
    if f.resizeW > 0 && f.resizeH > 0 { outW = f.resizeW; outH = f.resizeH }
    else if f.resizeW > 0 { outW = f.resizeW; outH = (oh * outW / ow).rounded() }
    else if f.resizeH > 0 { outH = f.resizeH; outW = (ow * outH / oh).rounded() }
    let fullLong = max(outW, outH)
    if maxSize > 0 && (outW > Double(maxSize) || outH > Double(maxSize)) {
        let s = Double(maxSize) / max(outW, outH)
        outW = (outW * s).rounded(); outH = (outH * s).rounded()
    }
    if abs(outW - ow) > 0.5 || abs(outH - oh) > 0.5 {
        // CILanczosScaleTransform scales the height by `scale` and the width by
        // scale*aspect, so the height carries the scale and the width the ratio.
        let scale = outH / oh
        if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
            lanczos.setValue(ci, forKey: kCIInputImageKey)
            lanczos.setValue(scale, forKey: kCIInputScaleKey)
            lanczos.setValue((outW / ow) / scale, forKey: kCIInputAspectRatioKey)
            ci = lanczos.outputImage ?? ci
        }
    }
    let target = CGRect(x: 0, y: 0, width: outW, height: outH)
    ci = ci.cropped(to: target)
    let spatialScale = fullLong > 0 ? max(outW, outH) / fullLong : 1

    if f.blur > 0 {
        let radius = max(1, ((f.blur / 4) * spatialScale).rounded())
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(ci, forKey: kCIInputImageKey)
            blur.setValue(radius, forKey: kCIInputRadiusKey)
            ci = (blur.outputImage ?? ci).cropped(to: target)
        }
    }

    // Per-pixel chain, in the engine's order as far as CoreImage allows.
    // The tone curve runs first; one LUT on every channel until the per-channel
    // selector lands.
    if !f.curvePoints.isEmpty, let lut = dashboardToneCurveLUT(f.curvePoints) {
        ci = ciCurveCube(ci, lut: lut.map { Double($0) / 255 })
    }
    if f.invert > 0 {
        let a = f.invert / 100
        let s = 1 - 2 * a
        ci = ciColorMatrix(ci, r: CIVector(x: s, y: 0, z: 0, w: 0),
                           g: CIVector(x: 0, y: s, z: 0, w: 0),
                           b: CIVector(x: 0, y: 0, z: s, w: 0),
                           a: CIVector(x: 0, y: 0, z: 0, w: 1),
                           bias: CIVector(x: a, y: a, z: a, w: 0))
    }
    if f.brightness != 100 {
        let s = f.brightness / 100
        ci = ciColorMatrix(ci, r: CIVector(x: s, y: 0, z: 0, w: 0),
                           g: CIVector(x: 0, y: s, z: 0, w: 0),
                           b: CIVector(x: 0, y: 0, z: s, w: 0),
                           a: CIVector(x: 0, y: 0, z: 0, w: 1),
                           bias: CIVector(x: 0, y: 0, z: 0, w: 0))
    }
    if f.contrast != 100 || f.saturation != 100 {
        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(ci, forKey: kCIInputImageKey)
            controls.setValue(0.0, forKey: kCIInputBrightnessKey)
            controls.setValue(f.contrast / 100, forKey: kCIInputContrastKey)
            controls.setValue(f.saturation / 100, forKey: kCIInputSaturationKey)
            ci = controls.outputImage ?? ci
        }
    }
    if f.hueRotate != 0 { ci = ciHueColorMatrix(ci, degrees: f.hueRotate) }
    if f.sepia > 0 {
        let amt = f.sepia / 100
        let s = [[0.393, 0.769, 0.189], [0.349, 0.686, 0.168], [0.272, 0.534, 0.131]]
        func row(_ i: Int) -> CIVector {
            CIVector(x: (i == 0 ? 1 - amt : 0) + amt * s[i][0],
                     y: (i == 1 ? 1 - amt : 0) + amt * s[i][1],
                     z: (i == 2 ? 1 - amt : 0) + amt * s[i][2], w: 0)
        }
        ci = ciColorMatrix(ci, r: row(0), g: row(1), b: row(2),
                           a: CIVector(x: 0, y: 0, z: 0, w: 1),
                           bias: CIVector(x: 0, y: 0, z: 0, w: 0))
    }
    if f.exposure != 0 {
        // The engine's exposure is a gamma, not a linear EV.
        let gamma = f.exposure > 0 ? 1 / (1 + f.exposure / 100) : 1 + abs(f.exposure) / 100
        if let g = CIFilter(name: "CIGammaAdjust") {
            g.setValue(ci, forKey: kCIInputImageKey)
            g.setValue(gamma, forKey: "inputPower")
            ci = g.outputImage ?? ci
        }
    }
    if f.shadows != 0 || f.highlights != 0 {
        // The engine lifts shadows and recovers highlights with a piecewise
        // linear curve about 0.5; reproduce it exactly.
        let sh = f.shadows / 200, hi = f.highlights / 200
        let lut = (0..<256).map { i -> Double in
            let x = Double(i) / 255
            return x < 0.5 ? x + sh * (1 - x / 0.5) : x + hi * ((x - 0.5) / 0.5)
        }
        ci = ciCurveCube(ci, lut: lut)
    }
    if f.temperature != 0 || f.tint != 0 {
        let t = f.temperature / 100, n = f.tint / 100
        ci = ciColorMatrix(ci, r: CIVector(x: 1, y: 0, z: 0, w: 0),
                           g: CIVector(x: 0, y: 1, z: 0, w: 0),
                           b: CIVector(x: 0, y: 0, z: 1, w: 0),
                           a: CIVector(x: 0, y: 0, z: 0, w: 1),
                           bias: CIVector(x: t * 30 / 255 + n * 10 / 255,
                                          y: -n * 20 / 255,
                                          z: -t * 30 / 255 + n * 10 / 255, w: 0))
    }
    // Palette grade: the engine's lightness-indexed LUT, reproduced as a cube.
    if f.paletteStops.count >= 2, f.paletteStrength > 0,
       let lut = dashboardPaletteLUT(f.paletteStops) {
        ci = ciPaletteGradeCube(ci, lut: lut, strength: f.paletteStrength / 100)
    }
    if f.sharpen > 0 {
        if let conv = CIFilter(name: "CIConvolution3X3") {
            let a = f.sharpen / 100
            let k = CIVector(values: [0, -0.25 * a, 0,
                                      -0.25 * a, 1 + 1.25 * a, -0.25 * a,
                                      0, -0.25 * a, 0], count: 9)
            conv.setValue(ci, forKey: kCIInputImageKey)
            conv.setValue(k, forKey: kCIInputWeightsKey)
            conv.setValue(0.0, forKey: kCIInputBiasKey)
            ci = (conv.outputImage ?? ci).cropped(to: target)
        }
    }
    if f.vignette > 0 {
        // The engine's vignette is a radial multiply: full brightness out to
        // 0.3 of the corner radius, falling to (1 - strength*0.8) at 0.85.
        let cx = target.midX, cy = target.midY
        let maxR = hypot(cx, cy)
        let r0 = maxR * 0.3, r1 = maxR * 0.85
        let edge = 1 - f.vignette / 100 * 0.8
        if let grad = CIFilter(name: "CIRadialGradient") {
            grad.setValue(CIVector(x: cx, y: cy), forKey: "inputCenter")
            grad.setValue(r0, forKey: "inputRadius0")
            grad.setValue(r1, forKey: "inputRadius1")
            grad.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: "inputColor0")
            grad.setValue(CIColor(red: edge, green: edge, blue: edge), forKey: "inputColor1")
            if let mask = grad.outputImage?.cropped(to: target),
               let mul = CIFilter(name: "CIMultiplyCompositing") {
                mul.setValue(mask, forKey: kCIInputImageKey)
                mul.setValue(ci, forKey: kCIInputBackgroundImageKey)
                ci = mul.outputImage ?? ci
            }
        }
    }

    // Rotate (clockwise) and flip about the centre. The engine's inverse map
    // undoes the flip first, so the forward order is rotate, then flip.
    // CoreImage's y is up, the engine's is down: clockwise is a negative angle.
    if f.rotate.truncatingRemainder(dividingBy: 360) != 0 || f.flipH || f.flipV {
        let e = ci.extent
        let cx = e.midX, cy = e.midY
        var m = CGAffineTransform(translationX: cx, y: cy)
        m = m.scaledBy(x: f.flipH ? -1 : 1, y: f.flipV ? -1 : 1)
        m = m.rotated(by: -f.rotate * Double.pi / 180)
        m = m.translatedBy(x: -cx, y: -cy)
        ci = ci.transformed(by: m)
        let r = ci.extent
        ci = ci.transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
    }

    return editorCIContext.createCGImage(ci, from: ci.extent)
}

// The engine's blurred variant is what the desktop shows when wallpaper.blur
// is on, so the preview must show it too. Same shape as `blurredVariant`:
// work at the 640 px long side with sigma 32, then scale to the preview —
// equivalent at preview resolution to sigma 32 × previewLong / workLong.
func editorBlurredPreview(_ input: CIImage, maxSize: Int) -> CGImage? {
    let extent = input.extent
    let long = max(extent.width, extent.height)
    guard long > 0 else { return nil }
    let scale = maxSize > 0 ? min(1.0, Double(maxSize) / Double(long)) : 1.0
    let scaled = scale < 1
        ? input.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : input
    let previewLong = long * scale
    let workLong = min(long, 640.0)
    let sigma = max(1.0, 32.0 * previewLong / workLong)
    let blurred = scaled.clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: sigma])
        .cropped(to: scaled.extent)
    return editorCIContext.createCGImage(
        blurred, from: blurred.extent, format: .RGBA8,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
}

// --- palette builder --------------------------------------------------------

// The engine's binary. OMACOSY_THEMECORE_BIN is the test seam: a /tmp build
// drives the editor without touching ~/.local/bin.
func themecoreBin() -> String {
    if let env = ProcessInfo.processInfo.environment["OMACOSY_THEMECORE_BIN"], !env.isEmpty {
        return env
    }
    return HOME + "/.local/bin/omacosy-themecore"
}

func nsColor(fromHex hex: String) -> NSColor {
    let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard clean.count == 6, let v = UInt64(clean, radix: 16) else { return .black }
    return color(fromARGB: 0xff000000 | v)
}

func hexString(from color: NSColor) -> String? {
    guard let c = color.usingColorSpace(.sRGB) else { return nil }
    let r = max(0, min(255, Int((c.redComponent * 255).rounded())))
    let g = max(0, min(255, Int((c.greenComponent * 255).rounded())))
    let b = max(0, min(255, Int((c.blueComponent * 255).rounded())))
    return String(format: "#%02x%02x%02x", r, g, b)
}

// The engine's ColorMath.lightened, integer-exact. The semantic ACCENT
// group's Orange is the red slot lightened 15% (`palette shades`), and
// that orange is the accent an edition carries to the desktop — the bar,
// the focus ring and the dashboard chrome all read it.
func lightenedHex(_ hex: String, percent: Double) -> String {
    let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard clean.count == 6, let v = UInt64(clean, radix: 16) else { return hex }
    func ch(_ c: UInt64) -> UInt64 {
        let f = Double(c)
        return UInt64((f + (255 - f) * percent / 100).rounded())
    }
    let r = ch((v >> 16) & 0xff), g = ch((v >> 8) & 0xff), b = ch(v & 0xff)
    return String(format: "#%02x%02x%02x", r, g, b)
}

// The writers' `mix(a, b, p)` exactly: an integer sRGB lerp toward b by p
// percent, truncating like bash. btop's meter, boxes and divider are built
// from it, so the override panel's default must be the colour the writer emits.
func mixHex(_ a: String, _ b: String, _ p: Int) -> String {
    func comps(_ hex: String) -> (Int, Int, Int)? {
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard clean.count == 6, let v = UInt64(clean, radix: 16) else { return nil }
        return (Int((v >> 16) & 0xff), Int((v >> 8) & 0xff), Int(v & 0xff))
    }
    guard let (ar, ag, ab) = comps(a), let (br, bg, bb) = comps(b) else { return a }
    func ch(_ x: Int, _ y: Int) -> Int { x + (y - x) * p / 100 }
    return String(format: "#%02x%02x%02x", ch(ar, br), ch(ag, bg), ch(ab, bb))
}

// A user-typed colour, normalised to "#rrggbb"; nil when it is not one.
func cleanHex(_ raw: String) -> String? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !s.hasPrefix("#") { s = "#" + s }
    guard s.count == 7, s.dropFirst().allSatisfy({ $0.isHexDigit }) else { return nil }
    return s
}

// The tone curve's 256-entry LUT, for drawing the curve graph instantly.
// This is a copy of themecore's ToneCurve.lut (Aether's buildCurveLUT); the
// harness extracts this marked block and diffs it against the engine's
// `curve lut` output, so the two cannot drift. Keep the markers intact.
// MARK: tone-curve-lut-begin
func dashboardToneCurveLUT(_ points: [[Double]]) -> [UInt8]? {
    guard !points.isEmpty else { return nil }

    var tagged: [(i: Int, x: Double, y: Double)] = [(0, 0, 0)]
    for (i, p) in points.enumerated() where p.count == 2 {
        tagged.append((i + 1, p[0], p[1]))
    }
    tagged.append((points.count + 1, 1, 1))
    tagged.sort { $0.x == $1.x ? $0.i < $1.i : $0.x < $1.x }
    let pts = tagged.map { (x: $0.x, y: $0.y) }
    let n = pts.count

    var m: [Double] = []
    for i in 0..<(n - 1) {
        let dx = pts[i + 1].x - pts[i].x
        let dy = pts[i + 1].y - pts[i].y
        m.append(dx == 0 ? 0 : dy / dx)
    }

    var tangents = [Double](repeating: 0, count: n)
    tangents[0] = m[0]
    tangents[n - 1] = m[n - 2]
    for i in 1..<(n - 1) {
        if m[i - 1] * m[i] <= 0 {
            tangents[i] = 0
        } else {
            tangents[i] = (m[i - 1] + m[i]) / 2
        }
    }
    for i in 0..<(n - 1) {
        if m[i] == 0 {
            tangents[i] = 0
            tangents[i + 1] = 0
        } else {
            let a = tangents[i] / m[i]
            let b = tangents[i + 1] / m[i]
            let s = a * a + b * b
            if s > 9 {
                let t = 3 / s.squareRoot()
                tangents[i] = t * a * m[i]
                tangents[i + 1] = t * b * m[i]
            }
        }
    }

    var lut = [UInt8](repeating: 0, count: 256)
    var seg = 0
    for i in 0..<256 {
        let x = Double(i) / 255
        while seg < n - 2 && x > pts[seg + 1].x { seg += 1 }
        let p0 = pts[seg], p1 = pts[seg + 1]
        let h = p1.x - p0.x
        if h == 0 {
            lut[i] = UInt8(max(0, min(255, (p0.y * 255).rounded())))
            continue
        }
        let t = (x - p0.x) / h
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        let val = h00 * p0.y + h10 * h * tangents[seg]
            + h01 * p1.y + h11 * h * tangents[seg + 1]
        lut[i] = UInt8(max(0, min(255, (val * 255).rounded())))
    }
    return lut
}
// MARK: tone-curve-lut-end

// The 12 adjustments and their UI ranges, mirroring themecore's
// Adjustments.limits (Aether's ADJUSTMENT_LIMITS). The editor keeps the
// values so it can drive its controls; the engine applies them.
struct EditorAdjustments {
    var vibrance = 0.0
    var saturation = 0.0
    var contrast = 0.0
    var brightness = 0.0
    var shadows = 0.0
    var highlights = 0.0
    var hueShift = 0.0
    var temperature = 0.0
    var tint = 0.0
    var blackPoint = 0.0
    var whitePoint = 0.0
    var gamma = 1.0

    struct Field {
        let key: String       // the record's spelling
        let cli: String       // themecore's flag
        let label: String
        var min = 0.0, max = 0.0, step = 0.0, def = 0.0
    }

    static let fields: [Field] = [
        Field(key: "vibrance", cli: "--vibrance", label: "Vibrance", min: -50, max: 50, step: 5, def: 0),
        Field(key: "saturation", cli: "--saturation", label: "Saturation", min: -100, max: 100, step: 5, def: 0),
        Field(key: "contrast", cli: "--contrast", label: "Contrast", min: -30, max: 30, step: 5, def: 0),
        Field(key: "brightness", cli: "--brightness", label: "Brightness", min: -30, max: 30, step: 5, def: 0),
        Field(key: "shadows", cli: "--shadows", label: "Shadows", min: -50, max: 50, step: 5, def: 0),
        Field(key: "highlights", cli: "--highlights", label: "Highlights", min: -50, max: 50, step: 5, def: 0),
        Field(key: "hueShift", cli: "--hue-shift", label: "Hue Shift", min: -180, max: 180, step: 10, def: 0),
        Field(key: "temperature", cli: "--temperature", label: "Temperature", min: -50, max: 50, step: 5, def: 0),
        Field(key: "tint", cli: "--tint", label: "Tint", min: -50, max: 50, step: 5, def: 0),
        Field(key: "blackPoint", cli: "--black-point", label: "Black Point", min: -30, max: 30, step: 5, def: 0),
        Field(key: "whitePoint", cli: "--white-point", label: "White Point", min: -30, max: 30, step: 5, def: 0),
        Field(key: "gamma", cli: "--gamma", label: "Gamma", min: 0.5, max: 2.0, step: 0.1, def: 1.0),
    ]

    subscript(key: String) -> Double {
        get {
            switch key {
            case "vibrance": return vibrance
            case "saturation": return saturation
            case "contrast": return contrast
            case "brightness": return brightness
            case "shadows": return shadows
            case "highlights": return highlights
            case "hueShift": return hueShift
            case "temperature": return temperature
            case "tint": return tint
            case "blackPoint": return blackPoint
            case "whitePoint": return whitePoint
            case "gamma": return gamma
            default: return 0
            }
        }
        set {
            switch key {
            case "vibrance": vibrance = newValue
            case "saturation": saturation = newValue
            case "contrast": contrast = newValue
            case "brightness": brightness = newValue
            case "shadows": shadows = newValue
            case "highlights": highlights = newValue
            case "hueShift": hueShift = newValue
            case "temperature": temperature = newValue
            case "tint": tint = newValue
            case "blackPoint": blackPoint = newValue
            case "whitePoint": whitePoint = newValue
            case "gamma": gamma = newValue
            default: break
            }
        }
    }

    var isIdentity: Bool {
        EditorAdjustments.fields.allSatisfy { abs(self[$0.key] - $0.def) < 1e-9 }
    }

    // The flags `palette render` takes.
    var cliFlags: String {
        EditorAdjustments.fields.map { f in
            let v = self[f.key]
            let text = f.step < 1 ? String(format: "%.1f", v) : String(format: "%.0f", v)
            return "\(f.cli) \(text)"
        }.joined(separator: " ")
    }

    // the record's spelling of every value
    var values: [String: Double] {
        var out: [String: Double] = [:]
        for f in Self.fields { out[f.key] = self[f.key] }
        return out
    }

    static func format(_ v: Double, _ step: Double) -> String {
        step < 1 ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }
}

// The editor's shared state. Both columns read it; its setters run the
// engine calls. It mirrors Aether's theme store — a base palette, the four
// extended colours, the 12 adjustments, the tone curve, locks and the
// multi-selection — and owns every themecore invocation. Nothing here
// touches the desktop.
final class PaletteModel {
    var onUpdate: (() -> Void)?
    var onUserEdit: (() -> Void)?

    private(set) var baseColors: [String] = []
    private(set) var extendedHex: [String: String] = [:]
    private(set) var adjustments = EditorAdjustments()
    private(set) var curve: [[Double]] = []
    private(set) var locked = Set<Int>()
    private(set) var selected = Set<Int>()
    private(set) var finalColors: [String] = []
    private(set) var finalExtended: [String: String] = [:]
    private(set) var method = "magic"
    private(set) var mode = "auto"
    private(set) var resolvedMode = "dark"
    private(set) var strips: [String: [String]] = [:]
    private(set) var histogram: [Int] = []
    private(set) var shades: [String: String] = [:]
    private(set) var recentColors: [String] = []
    private(set) var imagePath = ""
    // When an edit is applied, the palette derives from the rendered file while
    // the editor keeps the original as its source (non-destructive, re-editable).
    private(set) var editedPath: String?
    var extractSource: String { editedPath ?? imagePath }
    // bar/pill/label/muted/ring for the current rendered palette, for the
    // accessibility panel
    private(set) var roles: [String: String] = [:]
    // the palette source that is not a Method: a preset name, "From Colour"
    // or "Gradient"; nil means the header follows the method
    private(set) var sourceName: String?
    private(set) var sourceIsPreset = false

    // Per-app template overrides, and the app/role catalogue from themecore
    // (`template apps`). Overrides live at the top level of the record; the
    // appliers read them only while the terminal theme is on.
    struct TemplateRoleInfo { let key: String; let label: String; let source: String }
    struct TemplateAppInfo { let id: String; let name: String; let roles: [TemplateRoleInfo] }
    private(set) var appOverrides: [String: [String: String]] = [:]
    private(set) var templateApps: [TemplateAppInfo] = []
    private(set) var selectedTemplateApp = 0
    // nil = follow the machine default; else this edition's opacity, 0...100.
    private(set) var toolOpacity: Int?

    // Undo/redo: whole-editor snapshots, 50 deep. A burst of changes to the
    // same control inside one second folds into a single step (a slider drag
    // is one undo, not sixty).
    private struct HistoryEntry {
        var baseColors: [String]
        var extendedHex: [String: String]
        var adjustments: EditorAdjustments
        var curve: [[Double]]
        var method: String
        var mode: String
        var resolvedMode: String
        var sourceName: String?
        var appOverrides: [String: [String: String]]
        var toolOpacity: Int?
    }
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []
    private var lastPushKey: String?
    private var lastPushTime = Date.distantPast
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var presetsCache: [(name: String, mode: String, colors: [String])]?

    enum EditTarget: Equatable {
        case color(Int)
        case extended(String)
        case override(String, String)   // app, role key
    }
    private(set) var editTarget: EditTarget?

    static let extendedKeys: [(key: String, label: String)] = [
        ("accent", "Accent"),
        ("cursor", "Cursor"),
        ("selection_foreground", "Selection Text"),
        ("selection_background", "Selection"),
    ]

    // Aether's pinnable semantic shades: derived from the palette, but a
    // click-to-edit stores an explicit value that survives palette swaps
    // until "Reset N pinned".
    static let shadeKeys: [(key: String, label: String)] = [
        ("darker_bg", "Darker Background"),
        ("dark_bg", "Dark Background"),
        ("lighter_bg", "Lighter Background"),
        ("dark_fg", "Dark Foreground"),
        ("light_fg", "Light Foreground"),
        ("bright_fg", "Bright Foreground"),
        ("orange", "Orange"),
        ("brown", "Brown"),
    ]

    func pinnedShadeCount() -> Int {
        Self.shadeKeys.filter { extendedHex[$0.key] != nil }.count
    }

    func clearShadePins() {
        guard pinnedShadeCount() > 0 else { return }
        pushHistory(nil)
        for slot in Self.shadeKeys { extendedHex.removeValue(forKey: slot.key) }
        edited()
        update()
        refreshRender()
    }
    static let ansiLabels = ["BG", "RD", "GR", "YL", "BL", "MG", "CY", "FG",
                             "DIM", "RD+", "GR+", "YL+", "BL+", "MG+", "CY+", "FG+"]

    private(set) var modeGroups: [(label: String, modes: [(value: String, label: String)])] = []
    private(set) var paletteGeneration = 0
    private var renderGeneration = 0
    private var renderWork: DispatchWorkItem?
    private var recentWork: DispatchWorkItem?
    private var stripGeneration = 0

    init() {
        loadModes()
        loadTemplateApps()
    }

    // --- seeding ------------------------------------------------------------

    func seedDraft(image: String, colors: [String], accent: String?, resolved: String) {
        imagePath = image
        method = "magic"
        sourceIsPreset = false
        mode = "auto"
        resolvedMode = resolved == "light" ? "light" : "dark"
        baseColors = colors
        // Aether's setPalette at extraction: the UI colours derive from the
        // new palette. For Magic the accent is the wallpaper's own role
        // accent (`palette magic --roles`) so the draft and the raw theme
        // stay one theme; without it the palette's orange stands in.
        extendedHex = defaultExtended(colors, accent: accent)
        adjustments = EditorAdjustments()
        curve = []
        locked.removeAll()
        selected.removeAll()
        editTarget = nil
        finalColors = colors
        finalExtended = extendedHex
        strips.removeAll()
        strips["magic"] = colors
        histogram = []
        roles = [:]
        sourceName = nil
        appOverrides.removeAll()
        selectedTemplateApp = 0
        toolOpacity = nil
        undoStack.removeAll()
        redoStack.removeAll()
        lastPushKey = nil
        lastPushTime = .distantPast
        rebuildHistogram(finalColors)
        update()
        refreshRender()
        loadStrips()
    }

    func seedEdition(record: [String: Any], image: String) {
        imagePath = image
        let pal = record["palette"] as? [String: Any] ?? [:]
        baseColors = (pal["colors"] as? [String]) ?? []
        extendedHex = defaultExtended(baseColors, accent: nil)
        if let ext = pal["extended"] as? [String: Any] {
            for (key, raw) in ext {
                if let v = raw as? String { extendedHex[key] = v }
            }
        }
        method = (pal["method"] as? String) ?? "magic"
        mode = (pal["mode"] as? String) ?? "auto"
        resolvedMode = (pal["resolvedMode"] as? String) ?? "dark"
        adjustments = EditorAdjustments()
        if let adj = pal["adjustments"] as? [String: Any] {
            for f in EditorAdjustments.fields {
                if let n = adj[f.key] as? NSNumber { adjustments[f.key] = n.doubleValue }
            }
        }
        locked = Set((pal["locked"] as? [Int]) ?? [])
        curve = parseCurve(pal["curve"])
        selected.removeAll()
        editTarget = nil
        finalColors = baseColors
        finalExtended = extendedHex
        strips.removeAll()
        histogram = []
        roles = [:]
        sourceName = nil
        appOverrides.removeAll()
        if let ov = record["appOverrides"] as? [String: [String: String]] {
            appOverrides = ov
        }
        selectedTemplateApp = 0
        toolOpacity = record["toolOpacity"] as? Int
        undoStack.removeAll()
        redoStack.removeAll()
        lastPushKey = nil
        lastPushTime = .distantPast
        rebuildHistogram(finalColors)
        update()
        refreshRender()
        loadStrips()
    }

    // --- user actions -------------------------------------------------------

    func setBaseColor(_ index: Int, _ hex: String) {
        guard baseColors.indices.contains(index), baseColors[index] != hex else { return }
        pushHistory("color:\(index)")
        baseColors[index] = hex
        edited()
        update()
        refreshRender()
    }

    func setExtended(_ key: String, _ hex: String) {
        guard extendedHex[key] != hex else { return }
        pushHistory("extended:\(key)")
        extendedHex[key] = hex
        edited()
        update()
        refreshRender()
    }

    func setAdjustment(_ key: String, _ value: Double) {
        guard abs(adjustments[key] - value) > 1e-9 else { return }
        pushHistory("adjust:\(key)")
        adjustments[key] = value
        edited()
        update()
        refreshRender()
    }

    func resetAdjustments() {
        guard !adjustments.isIdentity || !curve.isEmpty else { return }
        pushHistory(nil)
        adjustments = EditorAdjustments()
        curve = []
        edited()
        update()
        refreshRender()
    }

    func setCurve(_ points: [[Double]]) {
        guard points != curve else { return }
        pushHistory("curve")
        curve = points
        edited()
        update()
        refreshRender()
    }

    func resetCurve() {
        guard !curve.isEmpty else { return }
        pushHistory(nil)
        curve = []
        edited()
        update()
        refreshRender()
    }

    // --- history ------------------------------------------------------------

    private func snapshot() -> HistoryEntry {
        HistoryEntry(baseColors: baseColors, extendedHex: extendedHex,
                     adjustments: adjustments, curve: curve, method: method,
                     mode: mode, resolvedMode: resolvedMode, sourceName: sourceName,
                     appOverrides: appOverrides, toolOpacity: toolOpacity)
    }

    private func pushHistory(_ key: String?) {
        let now = Date()
        if let key, key == lastPushKey, now.timeIntervalSince(lastPushTime) < 1.0 {
            // same control inside a second: one step, already pushed
            lastPushTime = now
            return
        }
        undoStack.append(snapshot())
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
        redoStack.removeAll()
        lastPushKey = key
        lastPushTime = now
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(entry)
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(entry)
    }

    private func restore(_ e: HistoryEntry) {
        lastPushKey = nil
        lastPushTime = .distantPast
        baseColors = e.baseColors
        extendedHex = e.extendedHex
        adjustments = e.adjustments
        curve = e.curve
        method = e.method
        mode = e.mode
        resolvedMode = e.resolvedMode
        sourceName = e.sourceName
        appOverrides = e.appOverrides
        toolOpacity = e.toolOpacity
        sourceIsPreset = e.sourceName.map { name in presetsCache?.contains { $0.name == name } ?? false } ?? false
        update()
        refreshRender()
        edited()
    }

    // --- palette sources (presets, from colour, gradient) -------------------

    func sourceLabel() -> String {
        sourceName ?? methodLabel(method)
    }

    func withPresets(_ handler: @escaping ([(name: String, mode: String, colors: [String])]) -> Void) {
        if let cache = presetsCache { handler(cache); return }
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore("presets --json")
            var list: [(name: String, mode: String, colors: [String])] = []
            if code == 0, let data = out.data(using: .utf8),
               let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                list = arr.compactMap { p in
                    guard let name = p["name"] as? String,
                          let colors = p["colors"] as? [String], colors.count == 16 else { return nil }
                    return (name, (p["mode"] as? String) ?? "dark", colors)
                }
            }
            DispatchQueue.main.async {
                guard !list.isEmpty else { return }
                self.presetsCache = list
                handler(list)
            }
        }
    }

    func applyPreset(_ name: String, colors: [String]) {
        guard colors.count == 16, baseColors.count == 16 else { return }
        pushHistory(nil)
        var next = colors
        for i in locked where i < 16 { next[i] = baseColors[i] }
        baseColors = next
        // a whole-palette swap also resets the sliders and the curve, like
        // Aether's setPalette
        curve = []
        adjustments = EditorAdjustments()
        resetExtended(next)
        sourceName = name
        sourceIsPreset = true
        edited()
        update()
        refreshRender()
    }

    func applyFromColor(_ raw: String) {
        let hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.isEmpty == false else { return }
        applyGenerated("color from-color \(shellQuote(hex)) --json",
                       label: "From \(hex.uppercased())")
    }

    func applyGradient(_ startRaw: String, _ endRaw: String) {
        let a = startRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = endRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty else { return }
        applyGenerated("color gradient \(shellQuote(a)) \(shellQuote(b)) --steps 16 --json",
                       label: "Gradient")
    }

    // One path for the two generated sources: ask the engine, then apply the
    // 16 colours with locked slots kept, exactly like a preset.
    private func applyGenerated(_ command: String, label: String) {
        guard baseColors.count == 16 else { return }
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore(command)
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let colors = obj["colors"] as? [String], colors.count == 16 else { return }
            DispatchQueue.main.async {
                guard self.baseColors.count == 16 else { return }
                self.pushHistory(nil)
                var next = colors
                for i in self.locked where i < 16 { next[i] = self.baseColors[i] }
                self.baseColors = next
                self.curve = []
                self.adjustments = EditorAdjustments()
                self.resetExtended(next)
                self.sourceName = label
                self.sourceIsPreset = false
                self.edited()
                self.update()
                self.refreshRender()
            }
        }
    }

    func chooseMethod(_ value: String) {
        guard value != method else { return }
        pushHistory(nil)
        method = value
        sourceName = nil
        sourceIsPreset = false
        edited()
        update()
        regenerate()
    }

    func setMode(_ index: Int) {
        let names = ["auto", "dark", "light"]
        let newMode = names[max(0, min(2, index))]
        guard newMode != mode else { return }
        mode = newMode
        edited()
        update()
        if newMode == "auto" {
            paletteGeneration += 1
            let gen = paletteGeneration
            let q = shellQuote(extractSource)
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                let (code, out) = self.themecore("palette suggest-mode \(q)")
                let resolved = (code == 0
                    && out.trimmingCharacters(in: .whitespacesAndNewlines) == "light") ? "light" : "dark"
                DispatchQueue.main.async {
                    guard self.paletteGeneration == gen else { return }
                    self.resolvedMode = resolved
                    self.update()
                    if self.method != "magic" { self.regenerate() }
                    else { self.refreshRender() }
                    self.loadStrips()
                }
            }
        } else {
            resolvedMode = newMode
            if method != "magic" { regenerate() } else { refreshRender() }
            loadStrips()
        }
    }

    func toggleLock(_ index: Int) {
        let targets = selected.contains(index) ? selected : [index]
        let lockAll = !locked.contains(index)
        for t in targets {
            if lockAll { locked.insert(t) } else { locked.remove(t) }
        }
        edited()
        update()
    }

    func toggleSelect(_ index: Int) {
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
        update()
    }

    @discardableResult
    func clearSelection() -> Bool {
        guard !selected.isEmpty else { return false }
        selected.removeAll()
        update()
        return true
    }

    @discardableResult
    func clearEditTarget() -> Bool {
        guard editTarget != nil else { return false }
        editTarget = nil
        update()
        return true
    }

    func selectForEdit(_ target: EditTarget) {
        if case .color(let i) = target, locked.contains(i) { return }
        editTarget = target
        update()
    }

    func editTargetHex() -> String? {
        switch editTarget {
        case .color(let i): return baseColors.indices.contains(i) ? baseColors[i] : nil
        case .extended(let key):
            return extendedHex[key] ?? shades[key] ?? defaultExtended(baseColors, accent: nil)[key]
        case .override(let app, let key):
            if let ov = appOverrides[app]?[key] { return ov }
            if let src = templateSource(app, key) { return templateDefault(src) }
            return nil
        case nil: return nil
        }
    }

    private func templateSource(_ app: String, _ key: String) -> String? {
        templateApps.first { $0.id == app }?.roles.first { $0.key == key }?.source
    }

    func editTargetTitle() -> String {
        switch editTarget {
        case .color(let i):
            guard Self.ansiLabels.indices.contains(i) else { return "Colour \(i)" }
            return "\(Self.ansiLabels[i]) (ANSI \(i))"
        case .extended(let key):
            if let slot = Self.extendedKeys.first(where: { $0.key == key }) { return slot.label }
            if let slot = Self.shadeKeys.first(where: { $0.key == key }) { return slot.label }
            return key
        case .override(let app, let key):
            let appName = templateApps.first { $0.id == app }?.name ?? app
            let roleLabel = templateApps.first { $0.id == app }?
                .roles.first { $0.key == key }?.label ?? key
            return "\(appName) · \(roleLabel)"
        case nil:
            return "No colour selected"
        }
    }

    func writeEditTarget(_ hex: String) {
        switch editTarget {
        case .color(let i): setBaseColor(i, hex)
        case .extended(let key): setExtended(key, hex)
        case .override(let app, let key): setAppOverride(app, key, hex)
        case nil: break
        }
        scheduleRecent(hex)
    }

    // Recently touched colours, debounced so a drag records only the value
    // the user settles on.
    private func scheduleRecent(_ hex: String) {
        recentWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.recentColors.removeAll { $0 == hex }
            self.recentColors.insert(hex, at: 0)
            if self.recentColors.count > 6 { self.recentColors.removeLast(self.recentColors.count - 6) }
            self.update()
        }
        recentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func methodLabel(_ value: String) -> String {
        if value == "magic" { return "Magic" }
        for group in modeGroups {
            if let m = group.modes.first(where: { $0.value == value }) { return m.label }
        }
        return value
    }

    func teardown() {
        renderWork?.cancel()
        renderWork = nil
        stripGeneration += 1
        MethodPicker.dismiss()
    }

    // --- engine -------------------------------------------------------------

    private func update() { onUpdate?() }
    private func edited() { onUserEdit?() }

    private func defaultExtended(_ colors: [String], accent: String?) -> [String: String] {
        let c = colors.count == 16 ? colors : Array(repeating: "#000000", count: 16)
        // The accent is the same orange the semantic ACCENT group shows:
        // the red slot lightened 15% (the engine's `palette shades`). The
        // ANSI blue slot (c[4]) left the desktop accent unrelated to the
        // palette the editor draws, so the bar and dashboard kept a colour
        // the user could not find anywhere in the editor.
        return ["accent": accent ?? lightenedHex(c[1], percent: 15),
                "cursor": c[7],
                "selection_foreground": c[0], "selection_background": c[7]]
    }

    // Aether's setPalette: a whole-palette swap re-derives the four UI
    // extended colours from the new palette, so the desktop accent follows
    // the Method you pick instead of staying at the seed's wallpaper colour.
    // Pinned shades are the user's own choice and survive the swap.
    private func resetExtended(_ colors: [String]) {
        guard colors.count == 16 else { return }
        for (k, v) in defaultExtended(colors, accent: nil) { extendedHex[k] = v }
    }

    private func parseCurve(_ raw: Any?) -> [[Double]] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { pair in
            guard let p = pair as? [Any], p.count == 2,
                  let x = (p[0] as? NSNumber)?.doubleValue,
                  let y = (p[1] as? NSNumber)?.doubleValue else { return nil }
            return [x, y]
        }
    }

    private func loadModes() {
        let (code, out) = themecore("modes --json")
        guard code == 0, let data = out.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let groups = obj["groups"] as? [[String: Any]] else { return }
        modeGroups = groups.map { g in
            let modes = (g["modes"] as? [[String: Any]] ?? []).compactMap {
                m -> (value: String, label: String)? in
                guard let v = m["value"] as? String else { return nil }
                return (v, (m["label"] as? String) ?? v)
            }
            return ((g["label"] as? String) ?? "", modes)
        }
    }

    // The apps and colour roles a saved edition can override. themecore owns
    // the catalogue so the editor and the appliers name the roles the same way.
    private func loadTemplateApps() {
        let (code, out) = themecore("template apps --json")
        guard code == 0, let data = out.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let apps = obj["apps"] as? [[String: Any]] else { return }
        templateApps = apps.compactMap { a in
            guard let id = a["id"] as? String, let name = a["name"] as? String else { return nil }
            let roles = (a["roles"] as? [[String: Any]] ?? []).compactMap { r -> TemplateRoleInfo? in
                guard let key = r["key"] as? String, let label = r["label"] as? String,
                      let source = r["source"] as? String else { return nil }
                return TemplateRoleInfo(key: key, label: label, source: source)
            }
            return TemplateAppInfo(id: id, name: name, roles: roles)
        }
    }

    // --- template overrides -------------------------------------------------

    func templateOverride(_ app: String, _ key: String) -> String? {
        appOverrides[app]?[key]
    }

    // The colour a role would take with no override: the palette slot its
    // catalogue `source` names, the same slot the applier reads.
    func templateDefault(_ source: String) -> String {
        let c = finalColors.count == 16 ? finalColors : baseColors
        func slot(_ i: Int, _ fallback: String = "#000000") -> String {
            c.indices.contains(i) ? c[i] : fallback
        }
        switch source {
        case "bg": return slot(0)
        case "fg": return slot(7, "#ffffff")
        case "muted": return slot(8, "#808080")
        case "accent": return finalExtended["accent"] ?? slot(1)
        case "cursor": return finalExtended["cursor"] ?? slot(7, "#ffffff")
        case "sel_bg": return finalExtended["selection_background"] ?? slot(0)
        case "sel_fg": return finalExtended["selection_foreground"] ?? slot(7, "#ffffff")
        case "red": return slot(1)
        case "green": return slot(2)
        case "yellow", "warn": return slot(3)
        case "blue": return slot(4)
        case "info": return slot(6)
        case "magenta": return slot(5)
        case "cyan": return slot(6)
        case "err": return slot(1)
        // Aether's orange is the red slot lightened 15%; its accent is the blue
        // slot. These are the roles the ported templates bind to.
        case "orange": return lightenedHex(slot(1), percent: 15)
        case "lighter_bg": return mixHex(slot(0), "#ffffff", 10)
        case "light_fg": return lightenedHex(slot(7, "#ffffff"), percent: 15)
        case "bright_fg": return lightenedHex(slot(7, "#ffffff"), percent: 25)
        case "dark_bg": return mixHex(slot(0), "#000000", 8)
        case "darker_bg": return mixHex(slot(0), "#000000", 15)
        case "dark_fg": return mixHex(slot(7, "#ffffff"), "#000000", 30)
        case "brown": return mixHex(slot(1), "#000000", 40)
        default:
            if source.hasPrefix("p"), let i = Int(source.dropFirst(1)) { return slot(i) }
            return "#000000"
        }
    }

    func selectTemplateApp(_ index: Int) {
        guard templateApps.indices.contains(index), index != selectedTemplateApp else { return }
        selectedTemplateApp = index
        editTarget = nil
        update()
    }

    func setAppOverride(_ app: String, _ key: String, _ hex: String) {
        var roles = appOverrides[app] ?? [:]
        guard roles[key] != hex else { return }
        pushHistory("ovr:\(app):\(key)")
        roles[key] = hex
        appOverrides[app] = roles
        edited()
        update()
    }

    func resetAppOverrides() {
        guard templateApps.indices.contains(selectedTemplateApp) else { return }
        let app = templateApps[selectedTemplateApp].id
        guard appOverrides[app] != nil else { return }
        pushHistory(nil)
        appOverrides.removeValue(forKey: app)
        edited()
        update()
    }

    func hasTemplateOverride(_ app: String) -> Bool {
        !(appOverrides[app] ?? [:]).isEmpty
    }

    // The per-edition tool opacity: nil inherits the machine default.
    func setToolOpacity(_ value: Int?) {
        guard toolOpacity != value else { return }
        pushHistory(nil)
        toolOpacity = value
        edited()
        update()
    }

    @discardableResult
    private func themecore(_ args: String) -> (Int32, String) {
        shell("\(shellQuote(themecoreBin())) \(args) 2>/dev/null")
    }

    // Re-derives the base palette from the image. Locked colours keep their
    // old value; choosing Magic resets the adjustments too (the plan's
    // reset action).
    // The wallpaper editor's "Apply to Palette": re-derive the palette from the
    // edited render (or the original when nil). One palette-history step.
    func applyEditedSource(_ path: String?) {
        guard path != editedPath else { return }
        pushHistory("source")
        editedPath = path
        edited()
        update()
        regenerate()
        loadStrips()
    }

    private func regenerate() {
        guard !extractSource.isEmpty, baseColors.count == 16 else { return }
        paletteGeneration += 1
        let gen = paletteGeneration
        let q = shellQuote(extractSource)
        let m = method
        let light = resolvedMode == "light"
        let lockedNow = locked
        let previous = baseColors
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let cmd = m == "magic"
                ? "palette magic \(q) --json"
                : "palette extract \(q) --mode \(m)\(light ? " --light" : "") --json"
            let (code, out) = self.themecore(cmd)
            var colors: [String] = []
            if code == 0, let data = out.data(using: .utf8),
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                colors = obj["colors"] as? [String] ?? []
            }
            // A magic re-extraction is the wallpaper's own theme again: the
            // accent returns to the picture's role accent (so the edition
            // matches the raw Wallpaper cell), not the palette's orange.
            var magicAccent: String? = nil
            if m == "magic" {
                let (rc, ro) = self.themecore("palette magic \(q) --roles --json")
                if rc == 0, let d = ro.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                    magicAccent = obj["accent"] as? String
                }
            }
            guard colors.count == 16 else { return }
            DispatchQueue.main.async {
                guard self.paletteGeneration == gen else { return }
                var next = colors
                for i in lockedNow where i < 16 { next[i] = previous[i] }
                self.baseColors = next
                // re-extraction is a whole-palette swap: sliders and curve
                // reset, like Aether's setPalette
                self.curve = []
                self.adjustments = EditorAdjustments()
                self.resetExtended(next)
                if let magicAccent { self.extendedHex["accent"] = magicAccent }
                self.update()
                self.refreshRender()
            }
        }
    }

    // One render per 75 ms while the user drags: the first change schedules
    // the call, later changes ride along instead of restarting it.
    private func refreshRender() {
        guard baseColors.count == 16 else { return }
        guard renderWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.renderWork = nil
            self?.performRender()
        }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: work)
    }

    private func performRender() {
        guard baseColors.count == 16 else { return }
        renderGeneration += 1
        let gen = renderGeneration
        var args = "palette render --colors \(shellQuote(baseColors.joined(separator: ",")))"
        for slot in Self.extendedKeys {
            let flag = slot.key.replacingOccurrences(of: "_", with: "-")
            args += " --\(flag) \(shellQuote(extendedHex[slot.key] ?? "#000000"))"
        }
        args += " \(adjustments.cliFlags)"
        if !curve.isEmpty {
            let text = curve.map { "\($0[0]),\($0[1])" }.joined(separator: ";")
            args += " --curve \(shellQuote(text))"
        }
        args += " --json"
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore(args)
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let colors = obj["colors"] as? [String], colors.count == 16 else { return }
            let ext = obj["extended"] as? [String: String] ?? [:]
            DispatchQueue.main.async {
                guard self.renderGeneration == gen else { return }
                // a locked slot is frozen: Aether reverts it to its raw base
                // after the adjustments, so the hex never moves until unlocked
                var final = colors
                for i in self.locked where i < 16 { final[i] = self.baseColors[i] }
                self.finalColors = final
                if !ext.isEmpty { self.finalExtended = ext }
                self.rebuildHistogram(final)
                self.update()
                self.loadShades(final)
                self.loadRoles(final, accent: self.finalExtended["accent"])
            }
        }
    }

    // Aether's derived shade ramps, for the semantic colour groups. Follows
    // the rendered palette, so the shades move with the adjustments.
    private func loadShades(_ colors: [String]) {
        let csv = colors.joined(separator: ",")
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore("palette shades --colors \(shellQuote(csv)) --json")
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            else { return }
            DispatchQueue.main.async {
                self.shades = obj
                self.update()
            }
        }
    }

    // Bar/pill/label/muted/ring for the rendered palette: the surfaces the
    // accessibility panel checks text colours against.
    private func loadRoles(_ colors: [String], accent: String?) {
        var args = "palette roles --colors \(shellQuote(colors.joined(separator: ",")))"
        if let accent, !accent.isEmpty { args += " --accent \(shellQuote(accent))" }
        args += " --json"
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore(args)
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            else { return }
            DispatchQueue.main.async {
                self.roles = obj
                self.update()
            }
        }
    }

    // One row per colour the Accessibility section checks: the three text
    // roles first, then every accent. Ratios run in surface order (bar,
    // pill, surface); follows the rendered palette, so it moves live.
    struct ContrastRow {
        let name: String
        let hex: String
        let ratios: [Double]
    }

    func contrastRows() -> [ContrastRow] {
        guard finalColors.count == 16 else { return [] }
        let names = ["Label", "Accent", "Muted",
                     "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan"]
        let hexes = [finalColors[7],
                     finalExtended["accent"] ?? finalColors[4],
                     finalColors[8],
                     finalColors[1], finalColors[2], finalColors[3],
                     finalColors[4], finalColors[5], finalColors[6]]
        let surfaces = [roles["bar"] ?? "#000000",
                        roles["pill"] ?? "#000000",
                        finalColors[0]]
        return zip(names, hexes).map { name, hex in
            ContrastRow(name: name, hex: hex,
                        ratios: surfaces.map { contrastRatioHex(hex, $0) })
        }
    }

    // Aether's palette luminance histogram, the curve backdrop: every colour
    // adds a Gaussian bump (sigma 8) at its HSL lightness, so editing a
    // swatch reshapes the graph before any slider is touched.
    private func rebuildHistogram(_ colors: [String]) {
        var bins = [Double](repeating: 0, count: 256)
        for hex in colors {
            let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard clean.count == 6, let v = UInt64(clean, radix: 16) else { continue }
            let r = Double((v >> 16) & 0xff), g = Double((v >> 8) & 0xff), b = Double(v & 0xff)
            let lum = ((max(r, g, b) + min(r, g, b)) / 2).rounded()
            for i in 0..<256 {
                let d = Double(i) - lum
                bins[i] += exp(-d * d / 128)
            }
        }
        // integers; the view normalises against the tallest bin anyway
        histogram = bins.map { Int(($0 * 4096).rounded()) }
    }

    // The mini palette strips the Method picker shows. The Magic strip is
    // the seed itself and appears at once; the mode strips run in small
    // parallel batches shortly after the first paint, so the picker is
    // populated by the time it is opened. Magic runs with them: an edition
    // seeds no strip of its own, and without it the Magic row stayed empty.
    private func loadStrips() {
        guard !extractSource.isEmpty else { return }
        stripGeneration += 1
        let gen = stripGeneration
        let values = ["magic"] + modeGroups.flatMap { $0.modes.map { $0.value } }
        let q = shellQuote(extractSource)
        let light = resolvedMode == "light"
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let batchSize = 6
            var start = 0
            while start < values.count {
                guard self.stripGeneration == gen else { return }
                let batch = Array(values[start..<min(start + batchSize, values.count)])
                let group = DispatchGroup()
                let lock = NSLock()
                var done: [(String, [String])] = []
                for value in batch {
                    group.enter()
                    DispatchQueue.global().async {
                        defer { group.leave() }
                        let cmd = "palette extract \(q) --mode \(value)\(light ? " --light" : "") --json"
                        let (code, out) = self.themecore(cmd)
                        guard code == 0, let data = out.data(using: .utf8),
                              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                              let colors = obj["colors"] as? [String], colors.count == 16
                        else { return }
                        lock.lock()
                        done.append((value, colors))
                        lock.unlock()
                    }
                }
                group.wait()
                guard self.stripGeneration == gen else { return }
                DispatchQueue.main.async {
                    guard self.stripGeneration == gen else { return }
                    for (value, colors) in done { self.strips[value] = colors }
                    if !done.isEmpty { self.update() }
                }
                start += batchSize
            }
        }
    }
}

// A flat "popup button": the current choice and a chevron; the menu itself
// is the MethodPicker card window.
// A colour swatch for the palette sources: shows the current colour and
// opens the shared colour panel for its field.
// A minimal NSColorWell: the click opens the system swatch popover (the same
// grid Aether shows in its webview), which closes on any outside click and
// offers "Show Colors…" for the full panel. The action fires while picking.
final class ColorWellView: NSColorWell {
    var hex = "#000000" { didSet { syncColor() } }
    var onChange: ((String) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        colorWellStyle = .minimal
        target = self
        action = #selector(picked)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func syncColor() {
        guard let want = hexString(from: nsColor(fromHex: hex)) else { return }
        if hexString(from: color) != want {
            color = nsColor(fromHex: hex)
        }
    }

    override func activate(_ exclusive: Bool) {
        // a click on the well commits whatever field is being edited first
        window?.makeFirstResponder(nil)
        super.activate(exclusive)
    }

    @objc private func picked() {
        guard let h = hexString(from: color) else { return }
        hex = h
        onChange?(h)
    }
}

final class PopupButtonView: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.35).setFill()
        r.fill()
        palette.muted.withAlphaComponent(0.35).setStroke()
        r.lineWidth = 1
        r.stroke()
        drawMidLeft(truncate(title, nerdFont("Regular", 12), bounds.width - 40),
                    nerdFont("Regular", 12), palette.label,
                    x: 10, midTop: bounds.height / 2, height: bounds.height)
        drawMidCenter("\u{f078}", nerdFont("Regular", 9), palette.muted,
                      centerX: bounds.width - 15, midTop: bounds.height / 2, height: bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        // a click on any button commits whatever field is being edited
        // first — without this the field stays first responder, and a
        // later ⌘Z would undo the field's text instead of the palette
        window?.makeFirstResponder(nil)
        onClick?()
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- method picker ----------------------------------------------------------

// The dark Method dropdown, in the same visual language as the Workspaces
// "Add App" picker: a borderless card child window with a scrollable list,
// Esc/outside-click to close, and a compact 16-square strip on each mode row
// showing that mode's palette for the current image.
final class MethodPicker: NSObject {
    private static var active: MethodPicker?

    struct Row {
        let header: String?   // a group label row when set
        let value: String?    // a selectable mode when set
        let label: String
    }

    private let window: PickerWindow
    private let root = MethodPickerRoot()
    private var rows: [Row]
    private var selected = 0
    private var completion: ((String) -> Void)?
    private var monitors: [Any] = []
    private let W: CGFloat = 340
    private let H: CGFloat = 430

    private init(rows: [Row], strips: [String: [String]], currentMethod: String,
                 title: String, completion: @escaping (String) -> Void) {
        self.rows = rows
        self.completion = completion
        window = PickerWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                              styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
        root.rows = rows
        root.strips = strips
        root.header = title
        root.onPick = { [weak self] value in self?.pick(value) }
        selected = rows.firstIndex { $0.value == currentMethod }
            ?? rows.firstIndex { $0.value != nil } ?? 0
        root.selected = selected
    }

    static func present(from view: NSView, rows: [Row], strips: [String: [String]],
                        currentMethod: String, title: String = "Method",
                        completion: @escaping (String) -> Void) {
        active?.close()
        let p = MethodPicker(rows: rows, strips: strips, currentMethod: currentMethod,
                             title: title, completion: completion)
        guard let host = view.window else { return }
        let btn = host.convertToScreen(view.convert(view.bounds, to: nil))
        var x = btn.minX
        var y = btn.minY - p.H - 6
        if y < 40 { y = btn.maxY + 6 }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(btn.origin) }) ?? NSScreen.main {
            x = min(max(screen.frame.minX + 8, x), screen.frame.maxX - p.W - 8)
        }
        p.window.setFrame(NSRect(x: x, y: y, width: p.W, height: p.H), display: true)
        active = p
        // a child window: it stays above the modal and is ordered out with it
        host.addChildWindow(p.window, ordered: .above)
        p.show()
    }

    static func dismiss() { active?.close() }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        root.relayout()
        root.scrollToSelected()
        let km = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.close(); return nil }
            if e.window === self.window {
                if e.keyCode == 126 { self.move(-1); return nil }  // up
                if e.keyCode == 125 { self.move(1); return nil }   // down
                if e.keyCode == 36 || e.keyCode == 76 { self.pickSelected(); return nil }
            }
            return e
        }
        let lm = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            if e.window !== self?.window { self?.close() }
            return e
        }
        let gm = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        monitors = [km, lm, gm].compactMap { $0 }
    }

    private func move(_ delta: Int) {
        var i = selected
        repeat { i += delta } while rows.indices.contains(i) && rows[i].value == nil
        guard rows.indices.contains(i), rows[i].value != nil else { return }
        selected = i
        root.selected = i
        root.needsDisplay = true
        root.scrollToSelected()
    }

    private func pickSelected() {
        guard rows.indices.contains(selected), let v = rows[selected].value else { return }
        pick(v)
    }

    private func pick(_ value: String) {
        completion?(value)
        close()
    }

    private func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        if MethodPicker.active === self { MethodPicker.active = nil }
    }
}

final class MethodPickerRoot: NSView {
    let scroll = NSScrollView()
    let list = MethodPickerList()
    var rows: [MethodPicker.Row] = []
    var strips: [String: [String]] = [:]
    var header = "Method"
    var selected = 0
    var onPick: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(scroll)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = list
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        palette.barBG.setFill()
        r.fill()
        palette.accent.setStroke()
        r.lineWidth = 1
        r.stroke()
        drawTopLeft(header, nerdFont("Bold", 12), palette.accent,
                    x: 12, top: 9, height: bounds.height)
    }

    override func layout() {
        super.layout()
        relayout()
    }

    func relayout() {
        let pad: CGFloat = 10
        let headerH: CGFloat = 32
        scroll.frame = NSRect(x: pad, y: pad, width: max(0, bounds.width - pad * 2),
                              height: max(0, bounds.height - pad * 2 - headerH))
        list.rows = rows
        list.strips = strips
        list.selected = selected
        list.onPick = onPick
        let w = max(scroll.contentSize.width, 10)
        list.frame = NSRect(x: 0, y: 0, width: w,
                            height: max(scroll.contentSize.height, MethodPickerList.height(for: rows)))
    }

    func scrollToSelected() { list.scrollRowIntoView(selected, in: scroll) }
}

final class MethodPickerList: NSView {
    var rows: [MethodPicker.Row] = [] { didSet { needsDisplay = true } }
    var strips: [String: [String]] = [:] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    var onPick: ((String) -> Void)?
    private static let rowH: CGFloat = 30
    private static let headerH: CGFloat = 26

    static func height(for rows: [MethodPicker.Row]) -> CGFloat {
        rows.reduce(0) { $0 + ($1.value == nil ? headerH : rowH) }
    }

    private func rowTops() -> [CGFloat] {
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for row in rows {
            tops.append(y)
            y += row.value == nil ? Self.headerH : Self.rowH
        }
        return tops
    }

    private func rowRect(_ i: Int, tops: [CGFloat]) -> NSRect {
        let h = rows[i].value == nil ? Self.headerH : Self.rowH
        return NSRect(x: 0, y: bounds.height - tops[i] - h, width: bounds.width, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let tops = rowTops()
        for (i, row) in rows.enumerated() {
            let r = rowRect(i, tops: tops)
            if row.value == nil {
                drawMidLeft(row.header ?? "", nerdFont("Bold", 10), palette.muted,
                            x: 10, midTop: tops[i] + Self.headerH / 2, height: bounds.height)
                continue
            }
            if i == selected {
                palette.accent.withAlphaComponent(0.85).setFill()
                r.fill()
            }
            let ink = i == selected ? palette.barBG : palette.label
            drawMidLeft(truncate(row.label, nerdFont("Regular", 12), bounds.width - 170),
                        nerdFont("Regular", 12), ink,
                        x: 10, midTop: tops[i] + Self.rowH / 2, height: bounds.height)
            if !strips.isEmpty {
                if let strip = strips[row.value ?? ""] {
                    drawStrip(strip, in: r, selected: i == selected)
                } else {
                    drawStripPlaceholder(in: r, selected: i == selected)
                }
            }
            if i == selected {
                drawMidLeft("\u{f00c}", nerdFont("Regular", 10), palette.barBG,
                            x: bounds.width - 16, midTop: tops[i] + Self.rowH / 2, height: bounds.height)
            }
        }
    }

    // 16 tiny bars, the mode's palette left to right; slim, line-like.
    private func drawStrip(_ colors: [String], in row: NSRect, selected: Bool) {
        let sqW: CGFloat = 7, sqH: CGFloat = 5, gap: CGFloat = 1
        let total = CGFloat(colors.count) * sqW + CGFloat(max(0, colors.count - 1)) * gap
        var x = row.maxX - 30 - total
        let y = row.midY - sqH / 2
        for hex in colors {
            let cell = NSRect(x: x, y: y, width: sqW, height: sqH)
            let path = NSBezierPath(roundedRect: cell, xRadius: 1, yRadius: 1)
            nsColor(fromHex: hex).setFill()
            path.fill()
            palette.barBG.withAlphaComponent(selected ? 0.25 : 0.4).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            x += sqW + gap
        }
    }

    private func drawStripPlaceholder(in row: NSRect, selected: Bool) {
        let sqW: CGFloat = 7, sqH: CGFloat = 5, gap: CGFloat = 1
        var x = row.maxX - 30 - (16 * sqW + 15 * gap)
        let y = row.midY - sqH / 2
        for _ in 0..<16 {
            palette.muted.withAlphaComponent(selected ? 0.35 : 0.18).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: sqW, height: sqH),
                         xRadius: 1, yRadius: 1).fill()
            x += sqW + gap
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let tops = rowTops()
        for i in rows.indices where rowRect(i, tops: tops).contains(p) {
            guard let value = rows[i].value else { return }
            selected = i
            needsDisplay = true
            onPick?(value)
            return
        }
    }

    func scrollRowIntoView(_ index: Int, in scroll: NSScrollView) {
        guard rows.indices.contains(index) else { return }
        let tops = rowTops()
        let r = rowRect(index, tops: tops)
        let clip = scroll.contentView.bounds
        var origin = clip.origin
        if r.minY < clip.minY { origin.y = r.minY }
        else if r.maxY > clip.maxY { origin.y = r.maxY - clip.height }
        let maxY = max(0, bounds.height - scroll.contentSize.height)
        origin.y = max(0, min(maxY, origin.y))
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- compact slider ---------------------------------------------------------

// One adjustment, Aether-style: label on the left, a thin track with a small
// square thumb in the middle, the value on the right. Drag sets the value
// (snapped to the range's step), double-click resets it, and the value can be
// typed.
// A labelled slider row: drag to change with snapping, double-click to reset,
// type a value and press Return to commit. Shared by the palette builder's 12
// adjustments and the wallpaper editor's filter groups.
struct SliderField {
    let key: String
    let label: String
    let min: Double
    let max: Double
    let step: Double
    let def: Double
}

extension EditorAdjustments.Field {
    var spec: SliderField {
        SliderField(key: key, label: label, min: min, max: max, step: step, def: def)
    }
}

final class AdjustmentSliderView: NSView, NSTextFieldDelegate {
    let spec: SliderField
    var value: Double = 0 { didSet { needsDisplay = true } }
    var onChange: ((Double) -> Void)?
    private let valueField = NSTextField()
    private var dragging = false

    static let rowHeight: CGFloat = 26

    init(spec: SliderField) {
        self.spec = spec
        super.init(frame: .zero)
        value = spec.def
        valueField.isBezeled = false
        valueField.drawsBackground = false
        valueField.textColor = palette.label
        valueField.font = nerdFont("Regular", 11)
        valueField.alignment = .right
        valueField.focusRingType = .none
        valueField.delegate = self
        valueField.target = self
        valueField.action = #selector(fieldReturn)
        addSubview(valueField)
        syncField()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func setValue(_ v: Double, notify: Bool) {
        value = v
        syncField()
        if notify { onChange?(v) }
    }

    func refreshColors() {
        valueField.textColor = palette.label
        needsDisplay = true
    }

    private func syncField() {
        guard valueField.currentEditor() == nil else { return }
        valueField.stringValue = EditorAdjustments.format(value, spec.step)
    }

    private func snap(_ v: Double) -> Double {
        let steps = ((v - spec.min) / spec.step).rounded()
        return min(spec.max, max(spec.min, spec.min + steps * spec.step))
    }

    @objc private func fieldReturn() { commitField() }

    private func commitField() {
        guard let raw = Double(valueField.stringValue) else { syncField(); return }
        let v = snap(raw)
        if abs(v - value) > 1e-9 { setValue(v, notify: true) }
        syncField()
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitField() }

    private var labelW: CGFloat { 88 }
    private var valueW: CGFloat { 34 }
    private var track: (CGFloat, CGFloat) { (labelW, max(labelW + 24, bounds.width - valueW - 4)) }

    override func layout() {
        super.layout()
        valueField.frame = NSRect(x: bounds.width - valueW,
                                  y: bounds.height / 2 - 8, width: valueW, height: 16)
    }

    private func updateValue(from p: NSPoint) {
        let (x0, x1) = track
        let t = min(1, max(0, (p.x - x0) / max(1, x1 - x0)))
        setValue(snap(spec.min + Double(t) * (spec.max - spec.min)), notify: true)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.x >= labelW - 4, p.x <= bounds.width, p.y >= 4, p.y <= bounds.height - 4 else { return }
        if event.clickCount == 2 {
            setValue(spec.def, notify: true)
            return
        }
        dragging = true
        updateValue(from: p)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        updateValue(from: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    override func draw(_ dirtyRect: NSRect) {
        let mid = bounds.height / 2
        drawMidLeft(spec.label, nerdFont("Regular", 11), palette.label,
                    x: 0, midTop: mid, height: bounds.height)
        let (x0, x1) = track
        palette.muted.withAlphaComponent(0.35).setFill()
        NSRect(x: x0, y: mid - 1, width: x1 - x0, height: 2).fill()
        let t = (value - spec.min) / max(1e-9, spec.max - spec.min)
        let cx = x0 + CGFloat(t) * (x1 - x0)
        let atDefault = abs(value - spec.def) < 1e-9
        let thumb = NSBezierPath(roundedRect: NSRect(x: cx - 4.5, y: mid - 4.5, width: 9, height: 9),
                                 xRadius: 2, yRadius: 2)
        (atDefault ? palette.muted : palette.accent).setFill()
        thumb.fill()
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- tone curve editor ------------------------------------------------------

// The curve box, Aether-style: the palette's luminance histogram as a
// backdrop, the curve sampled from the LUT, and draggable control points.
// The endpoints (0,0) and (1,1) are fixed; click empty space to add, drag
// to move, double-click a point to remove, Reset returns to identity.
final class CurveEditorView: NSView {
    var points: [[Double]] = [] { didSet { needsDisplay = true } }
    var histogram: [Int] = [] { didSet { needsDisplay = true } }
    var onChange: (([[Double]]) -> Void)?

    static let viewHeight: CGFloat = 116
    private var dragIndex: Int?
    private let inset: CGFloat = 10
    private let topPad: CGFloat = 12

    private var graph: NSRect {
        NSRect(x: inset, y: inset, width: max(1, bounds.width - inset * 2),
               height: max(1, bounds.height - topPad - inset))
    }

    private func pointXY(_ p: NSPoint) -> (Double, Double) {
        let g = graph
        let x = Double((p.x - g.minX) / max(1, g.width))
        let y = Double((p.y - g.minY) / max(1, g.height))
        return (min(1, max(0, x)), min(1, max(0, y)))
    }

    private func screenXY(_ x: Double, _ y: Double) -> NSPoint {
        let g = graph
        return NSPoint(x: g.minX + CGFloat(x) * g.width, y: g.minY + CGFloat(y) * g.height)
    }

    private func hitIndex(_ p: NSPoint) -> Int? {
        for (i, pt) in points.enumerated() {
            let s = screenXY(pt[0], pt[1])
            if hypot(s.x - p.x, s.y - p.y) <= 9 { return i }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.35).setFill()
        box.fill()
        palette.muted.withAlphaComponent(0.35).setStroke()
        box.lineWidth = 1
        box.stroke()

        let g = graph
        palette.muted.withAlphaComponent(0.12).setStroke()
        for i in 1..<4 {
            let x = g.minX + g.width * CGFloat(i) / 4
            let y = g.minY + g.height * CGFloat(i) / 4
            NSBezierPath.strokeLine(from: NSPoint(x: x, y: g.minY), to: NSPoint(x: x, y: g.maxY))
            NSBezierPath.strokeLine(from: NSPoint(x: g.minX, y: y), to: NSPoint(x: g.maxX, y: y))
        }

        if histogram.count == 256, let maxBins = histogram.max(), maxBins > 0 {
            let barW = g.width / 256
            palette.muted.withAlphaComponent(0.20).setFill()
            for (i, n) in histogram.enumerated() {
                let h = CGFloat(Double(n) / Double(maxBins)) * g.height
                NSRect(x: g.minX + CGFloat(i) * barW, y: g.minY, width: max(0.5, barW), height: h).fill()
            }
        }

        let lut = dashboardToneCurveLUT(points) ?? (0...255).map { UInt8($0) }
        let path = NSBezierPath()
        for i in 0..<256 {
            let p = screenXY(Double(i) / 255, Double(lut[i]) / 255)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        palette.accent.setStroke()
        path.lineWidth = 2
        path.stroke()

        // fixed endpoints, faint; interior points solid
        for (x, y) in [(0.0, 0.0), (1.0, 1.0)] {
            let s = screenXY(x, y)
            palette.label.withAlphaComponent(0.45).setFill()
            NSBezierPath(ovalIn: NSRect(x: s.x - 2, y: s.y - 2, width: 4, height: 4)).fill()
        }
        for pt in points {
            let s = screenXY(pt[0], pt[1])
            let dot = NSBezierPath(ovalIn: NSRect(x: s.x - 4, y: s.y - 4, width: 8, height: 8))
            palette.accent.setFill()
            dot.fill()
            palette.barBG.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard graph.contains(p) else { return }
        if let i = hitIndex(p) {
            if event.clickCount == 2 {
                var next = points
                next.remove(at: i)
                onChange?(next)
                dragIndex = nil
            } else {
                dragIndex = i
            }
            return
        }
        let (x, y) = pointXY(p)
        let clampedX = min(0.99, max(0.01, x))
        var next = points
        let newIndex = next.firstIndex { $0[0] > clampedX } ?? next.count
        next.insert([clampedX, y], at: newIndex)
        dragIndex = newIndex
        onChange?(next)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let i = dragIndex, points.indices.contains(i) else { return }
        let p = convert(event.locationInWindow, from: nil)
        let (rawX, y) = pointXY(p)
        let lower = i > 0 ? points[i - 1][0] + 0.005 : 0.005
        let upper = i < points.count - 1 ? points[i + 1][0] - 0.005 : 0.995
        guard lower < upper else { return }
        var next = points
        next[i] = [min(upper, max(lower, rawX)), y]
        onChange?(next)
    }

    override func mouseUp(with event: NSEvent) { dragIndex = nil }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- palette cards ----------------------------------------------------------

// Aether's palette cards: role label and a contrast badge on top, the hex at
// the bottom, the colour filling the card. Used for the 16 ANSI colours and
// for the four extended colours.
final class PaletteCardsView: NSView {
    struct Card {
        let label: String
        let hex: String
        let index: Int          // 0...15 for an ANSI slot, -1 for extended
        let extendedKey: String?
    }

    var cards: [Card] = [] { didSet { needsDisplay = true } }
    var locked = Set<Int>() { didSet { needsDisplay = true } }
    var selected = Set<Int>() { didSet { needsDisplay = true } }
    var editTarget: PaletteModel.EditTarget? { didSet { needsDisplay = true } }
    var bgHex = "#000000"
    var showsLocks = true
    var onEdit: ((PaletteModel.EditTarget) -> Void)?
    var onToggleLock: ((Int) -> Void)?
    var onToggleSelect: ((Int) -> Void)?
    var onHover: (() -> Void)?

    static let columns = 8
    static let cardH: CGFloat = 50
    static let cardGap: CGFloat = 5

    static func height(for count: Int) -> CGFloat {
        let rows = max(1, (count + columns - 1) / columns)
        return CGFloat(rows) * cardH + CGFloat(rows - 1) * cardGap
    }

    private func rects() -> [NSRect] {
        guard bounds.width > 0 else { return [] }
        let w = ((bounds.width - CGFloat(Self.columns - 1) * Self.cardGap) / CGFloat(Self.columns))
        var out: [NSRect] = []
        let rowCount = (cards.count + Self.columns - 1) / Self.columns
        for row in 0..<max(1, rowCount) {
            for col in 0..<Self.columns {
                let i = row * Self.columns + col
                if i >= cards.count { break }
                let x = CGFloat(col) * (w + Self.cardGap)
                let top = CGFloat(row) * (Self.cardH + Self.cardGap)
                out.append(NSRect(x: x, y: bounds.height - top - Self.cardH, width: w, height: Self.cardH))
            }
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, card) in cards.enumerated() {
            let all = rects()
            guard all.indices.contains(i) else { break }
            let r = all[i]
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            nsColor(fromHex: card.hex).setFill()
            path.fill()

            let light = relativeLuminance(nsColor(fromHex: card.hex)) > 0.5
            let ink: NSColor = light ? .black : .white
            let inkMain = ink.withAlphaComponent(light ? 0.78 : 0.92)
            let inkFaint = ink.withAlphaComponent(light ? 0.55 : 0.68)

            drawMidLeft(card.label, nerdFont("Bold", 9), inkMain,
                        x: r.minX + 6, midTop: bounds.height - r.maxY + 10, height: bounds.height)
            drawMidLeft(card.hex, nerdFont("Regular", 8), inkFaint,
                        x: r.minX + 6, midTop: bounds.height - r.maxY + Self.cardH - 10,
                        height: bounds.height)

            if showsLocks, card.index >= 0 {
                let lockedNow = locked.contains(card.index)
                drawMidCenter("\u{f023}", nerdFont("Regular", 8),
                              lockedNow ? inkMain : ink.withAlphaComponent(0.22),
                              centerX: r.maxX - 11, midTop: bounds.height - r.maxY + 10,
                              height: bounds.height)
            }

            // contrast badge against the palette background, bottom-right
            // (the BG card compares with itself, so it carries none)
            if card.index > 0, r.width >= 60 {
                let ratio = contrastRatioHex(card.hex, bgHex)
                let level = ratio >= 7 ? "AAA" : (ratio >= 4.5 ? "AA" : (ratio >= 3 ? "AA-L" : "!"))
                drawMidCenter(level, nerdFont("Bold", 8), level == "!" ? ink : inkFaint,
                              centerX: r.maxX - 16, midTop: bounds.height - r.maxY + Self.cardH - 10,
                              height: bounds.height)
            }

            let isEditing: Bool
            switch editTarget {
            case .color(let idx): isEditing = card.index >= 0 && idx == card.index
            case .extended(let key): isEditing = card.extendedKey == key
            case .override: isEditing = false
            case nil: isEditing = false
            }
            if isEditing {
                palette.accent.setStroke()
                path.lineWidth = 2.5
                path.stroke()
            } else if card.index >= 0 && selected.contains(card.index) {
                palette.accent.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let all = rects()
        for (i, card) in cards.enumerated() {
            guard all.indices.contains(i), all[i].contains(p) else { continue }
            let r = all[i]
            let lockZone = NSRect(x: r.maxX - 22, y: r.maxY - 18, width: 20, height: 18)
            if showsLocks, card.index >= 0, lockZone.contains(p) {
                onToggleLock?(card.index)
            } else if card.index >= 0, event.modifierFlags.contains(.shift) {
                onToggleSelect?(card.index)
            } else if let key = card.extendedKey {
                onEdit?(.extended(key))
            } else {
                onEdit?(.color(card.index))
            }
            return
        }
    }

    func flashHover() { onHover?() }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// WCAG contrast between two hex colours, for the card badges.
func contrastRatioHex(_ a: String, _ b: String) -> Double {
    let la = Double(relativeLuminance(nsColor(fromHex: a)))
    let lb = Double(relativeLuminance(nsColor(fromHex: b)))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// Shared badge spelling for every contrast readout: WCAG AA (4.5), AAA (7)
// and the large-text AA-L (3) the swatch cards already use.
func contrastBadge(_ ratio: Double) -> String {
    ratio >= 7 ? "AAA" : (ratio >= 4.5 ? "AA" : (ratio >= 3 ? "AA-L" : "!"))
}

// --- semantic colours -------------------------------------------------------

// Aether's semantic groups: the Background and Foreground shade ramps and the
// accent pair, all derived from the palette, plus the UI group — the four
// extended colours, which are editable.
final class SemanticSectionView: NSView {
    struct Card {
        let label: String
        let hex: String
        let key: String?   // non-nil: an editable extended colour (UI or shade)
        let slot: Int?     // non-nil: an ANSI slot this card edits

        init(label: String, hex: String, key: String? = nil, slot: Int? = nil) {
            self.label = label
            self.hex = hex
            self.key = key
            self.slot = slot
        }
    }
    struct Group {
        let title: String
        let cards: [Card]
    }

    var groups: [Group] = [] { didSet { needsDisplay = true } }
    var editTarget: PaletteModel.EditTarget? { didSet { needsDisplay = true } }
    var onEdit: ((PaletteModel.EditTarget) -> Void)?

    static let groupH: CGFloat = 86
    static let rowGap: CGFloat = 8

    static func height() -> CGFloat { groupH * 2 + rowGap }

    private func boxes() -> [(group: Group, box: NSRect, cards: [NSRect])] {
        guard groups.count == 4, bounds.width > 0 else { return [] }
        let colGap: CGFloat = 8
        let colW = (bounds.width - colGap) / 2
        var out: [(Group, NSRect, [NSRect])] = []
        for (i, group) in groups.enumerated() {
            let col = i % 2, row = i / 2
            let x = CGFloat(col) * (colW + colGap)
            let top = CGFloat(row) * (Self.groupH + Self.rowGap)
            let box = NSRect(x: x, y: bounds.height - top - Self.groupH,
                             width: colW, height: Self.groupH)
            let padX: CGFloat = 10
            let n = max(1, group.cards.count)
            let gap: CGFloat = 5
            let cardW = (box.width - padX * 2 - CGFloat(n - 1) * gap) / CGFloat(n)
            var rects: [NSRect] = []
            for j in 0..<group.cards.count {
                let cx = box.minX + padX + CGFloat(j) * (cardW + gap)
                rects.append(NSRect(x: cx, y: box.minY + 22, width: cardW, height: 34))
            }
            out.append((group, box, rects))
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        for (group, box, rects) in boxes() {
            let boxPath = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            palette.itemBG.withAlphaComponent(0.22).setFill()
            boxPath.fill()
            palette.muted.withAlphaComponent(0.15).setStroke()
            boxPath.lineWidth = 1
            boxPath.stroke()
            drawTopLeft(group.title.uppercased(), nerdFont("Bold", 9), palette.muted,
                        x: box.minX + 10, top: bounds.height - box.maxY + 8, height: bounds.height)
            for (j, card) in group.cards.enumerated() {
                let r = rects[j]
                let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
                nsColor(fromHex: card.hex).setFill()
                path.fill()
                let light = relativeLuminance(nsColor(fromHex: card.hex)) > 0.5
                let main: NSColor = light ? .black : .white
                drawMidLeft(card.hex, nerdFont("Regular", 8), main.withAlphaComponent(0.62),
                            x: r.minX + 5, midTop: bounds.height - r.maxY + r.height - 9,
                            height: bounds.height)
                drawMidCenter(card.label, nerdFont("Regular", 9), palette.label.withAlphaComponent(0.72),
                              centerX: r.midX, midTop: bounds.height - r.minY + 7,
                              height: bounds.height)
                if let key = card.key {
                    var isEditing = false
                    if case .extended(let k) = editTarget, k == key { isEditing = true }
                    if isEditing {
                        palette.accent.setStroke()
                        path.lineWidth = 2
                        path.stroke()
                    }
                } else if let slot = card.slot {
                    var isEditing = false
                    if case .color(let i) = editTarget, i == slot { isEditing = true }
                    if isEditing {
                        palette.accent.setStroke()
                        path.lineWidth = 2
                        path.stroke()
                    }
                }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (group, _, rects) in boxes() {
            for (j, card) in group.cards.enumerated() {
                guard rects[j].contains(p) else { continue }
                if let key = card.key { onEdit?(.extended(key)); return }
                if let slot = card.slot { onEdit?(.color(slot)); return }
            }
        }
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- template override ------------------------------------------------------

// The per-app colour overrides. An app picker, then that app's roles as
// swatches; a swatch that carries an override is ringed in the accent, and
// Reset clears them for the app. The values reach the terminal tools only
// while the terminal theme follows the theme.
// A small 0...100 slider, shared by the editor's per-edition control and the
// Options tab's machine default. nil draws as an empty track (unset).
final class OpacitySliderView: NSView {
    var value: Int? { didSet { needsDisplay = true } }
    var onChange: ((Int) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let trackH: CGFloat = 4
        let track = NSRect(x: 0, y: bounds.midY - trackH / 2, width: bounds.width, height: trackH)
        palette.itemBG.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: trackH / 2, yRadius: trackH / 2).fill()
        guard let value else { return }
        let v = CGFloat(max(0, min(100, value))) / 100
        let fill = NSRect(x: 0, y: track.minY, width: bounds.width * v, height: trackH)
        palette.accent.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: fill, xRadius: trackH / 2, yRadius: trackH / 2).fill()
        let hx = max(6, min(bounds.width - 6, bounds.width * v))
        palette.accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: hx - 6, y: bounds.midY - 6, width: 12, height: 12)).fill()
    }

    private func setFrom(_ p: NSPoint) {
        guard bounds.width > 0 else { return }
        let v = Int((max(0, min(1, p.x / bounds.width)) * 100).rounded())
        if value != v { value = v; onChange?(v) }
    }
    override func mouseDown(with event: NSEvent) { setFrom(convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { setFrom(convert(event.locationInWindow, from: nil)) }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class TemplateOverrideSectionView: NSView {
    struct Role {
        let key: String
        let label: String
        let hex: String
        let overridden: Bool
    }
    var apps: [String] = [] { didSet { needsDisplay = true } }
    var appIds: [String] = []
    var selectedApp = 0 { didSet { needsDisplay = true } }
    var roles: [Role] = [] { didSet { needsDisplay = true } }
    var canReset = false { didSet { needsDisplay = true } }
    var editTarget: PaletteModel.EditTarget? { didSet { needsDisplay = true } }
    var toolOpacity: Int? { didSet { needsDisplay = true; refreshSliders() } }
    var globalOpacity: Int? { didSet { needsDisplay = true; refreshSliders() } }
    var terminalOpacity: Int? { didSet { needsDisplay = true; refreshSliders() } }
    var onSelectApp: ((Int) -> Void)?
    var onEdit: ((String, String) -> Void)?
    var onReset: (() -> Void)?
    var onToolOpacity: ((Int?) -> Void)?
    let opacitySlider = OpacitySliderView()

    private let headerH: CGFloat = 44
    private let settingsH: CGFloat = 30
    private let chipsH: CGFloat = 30
    private let cols = 4
    private let cardH: CGFloat = 34
    private let labelH: CGFloat = 15
    private let rowGap: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        opacitySlider.onChange = { [weak self] v in self?.onToolOpacity?(v) }
        addSubview(opacitySlider)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // The slider opens showing the opacity actually in use, so it is never an
    // empty track: edition -> global -> the terminal's own -> opaque.
    private func refreshSliders() {
        opacitySlider.value = toolOpacity ?? globalOpacity ?? terminalOpacity ?? 100
    }

    static func height(roleCount: Int) -> CGFloat {
        let rows = max(1, (roleCount + 3) / 4)
        return 44 + 30 + 30 + 6 + CGFloat(rows) * (34 + 15) + CGFloat(rows - 1) * 12 + 18
    }

    private var contentTop: CGFloat { headerH + settingsH + chipsH + 6 }
    private var editRowTop: CGFloat { headerH }
    private var sliderX: CGFloat { 94 }

    private var inheritRect: NSRect {
        NSRect(x: bounds.width - 108 - 16, y: bounds.height - editRowTop - 26, width: 104, height: 20)
    }

    override func layout() {
        super.layout()
        let w = max(60, bounds.width - sliderX - 108 - 32 - 50)
        opacitySlider.frame = NSRect(x: sliderX, y: bounds.height - editRowTop - 23, width: w, height: 14)
    }

    private func appRects() -> [NSRect] {
        var out: [NSRect] = []
        let font = nerdFont("Regular", 11)
        var x: CGFloat = 16
        for name in apps {
            let w = advance(name, font) + 14
            out.append(NSRect(x: x, y: bounds.height - headerH - settingsH - chipsH + 4,
                              width: w, height: 24))
            x += w + 5
        }
        return out
    }

    private func cardRects() -> [NSRect] {
        guard !roles.isEmpty, bounds.width > 0 else { return [] }
        let colGap: CGFloat = 8
        let insetL: CGFloat = 16
        let colW = (bounds.width - insetL * 2 - CGFloat(cols - 1) * colGap) / CGFloat(cols)
        var out: [NSRect] = []
        for i in roles.indices {
            let col = i % cols, row = i / cols
            let x = insetL + CGFloat(col) * (colW + colGap)
            let top = contentTop + CGFloat(row) * (cardH + labelH + rowGap)
            out.append(NSRect(x: x, y: bounds.height - top - cardH, width: colW, height: cardH))
        }
        return out
    }

    private var resetRect: NSRect? {
        guard canReset else { return nil }
        let w = advance("Reset \(selectedAppName)", nerdFont("Regular", 11)) + 10
        // the header's title line, right-aligned
        return NSRect(x: bounds.width - w - 16, y: bounds.height - 26, width: w, height: 20)
    }

    private var selectedAppName: String {
        apps.indices.contains(selectedApp) ? apps[selectedApp] : ""
    }

    override func draw(_ dirtyRect: NSRect) {
        // framed card, like the semantic groups
        let card = bounds.insetBy(dx: 0.5, dy: 0.5)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.12).setFill()
        cardPath.fill()
        palette.muted.withAlphaComponent(0.15).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        drawTopLeft("Template Override", nerdFont("Bold", 12), palette.accent,
                    x: 16, top: 8, height: bounds.height)
        drawTopLeft("Per-app colours; applied only when the terminal follows the theme.",
                    nerdFont("Regular", 10), palette.muted,
                    x: 16, top: 26, height: bounds.height)
        if let r = resetRect {
            drawMidLeft("Reset \(selectedAppName)", nerdFont("Regular", 11), .systemRed,
                        x: r.minX + 3, midTop: bounds.height - r.midY, height: bounds.height)
        }
        // separator under the header
        palette.muted.withAlphaComponent(0.15).setFill()
        NSRect(x: 1, y: bounds.height - headerH, width: bounds.width - 2, height: 1).fill()
        // Tool opacity: an edition slider that inherits the machine default.
        let sfont = nerdFont("Regular", 11)
        drawMidLeft("Opacity", nerdFont("Regular", 10), palette.muted,
                    x: 16, midTop: editRowTop + 15, height: bounds.height)
        let effective = toolOpacity ?? globalOpacity ?? terminalOpacity ?? 100
        drawMidLeft("\(effective)%", sfont, palette.label,
                    x: opacitySlider.frame.maxX + 8, midTop: editRowTop + 14, height: bounds.height)
        let ir = inheritRect
        let ipath = NSBezierPath(roundedRect: ir, xRadius: 5, yRadius: 5)
        if toolOpacity == nil {
            palette.accent.withAlphaComponent(0.9).setFill()
            ipath.fill()
        } else {
            palette.itemBG.withAlphaComponent(0.3).setFill()
            ipath.fill()
            palette.muted.withAlphaComponent(0.3).setStroke()
            ipath.lineWidth = 1
            ipath.stroke()
        }
        drawMidCenter("Inherit global", nerdFont("Regular", 10),
                      toolOpacity == nil ? palette.barBG : palette.label,
                      centerX: ir.midX, midTop: bounds.height - ir.midY, height: bounds.height)
        for (i, rect) in appRects().enumerated() {
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            if i == selectedApp {
                palette.accent.withAlphaComponent(0.9).setFill()
                path.fill()
                drawMidCenter(apps[i], nerdFont("Bold", 11), palette.barBG,
                              centerX: rect.midX, midTop: bounds.height - rect.midY,
                              height: bounds.height)
            } else {
                palette.itemBG.withAlphaComponent(0.3).setFill()
                path.fill()
                palette.muted.withAlphaComponent(0.3).setStroke()
                path.lineWidth = 1
                path.stroke()
                drawMidCenter(apps[i], nerdFont("Regular", 11), palette.label,
                              centerX: rect.midX, midTop: bounds.height - rect.midY,
                              height: bounds.height)
            }
        }
        let rects = cardRects()
        for (i, role) in roles.enumerated() where rects.indices.contains(i) {
            let r = rects[i]
            let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            nsColor(fromHex: role.hex).setFill()
            path.fill()
            let light = relativeLuminance(nsColor(fromHex: role.hex)) > 0.5
            drawMidLeft(role.hex, nerdFont("Regular", 8),
                        (light ? NSColor.black : .white).withAlphaComponent(0.62),
                        x: r.minX + 5, midTop: bounds.height - r.maxY + r.height - 9,
                        height: bounds.height)
            drawMidCenter(role.label, nerdFont("Regular", 9),
                          palette.label.withAlphaComponent(0.72),
                          centerX: r.midX, midTop: bounds.height - r.minY + 7,
                          height: bounds.height)
            var editing = false
            if case .override(_, let k) = editTarget, k == role.key { editing = true }
            if role.overridden || editing {
                palette.accent.setStroke()
                path.lineWidth = role.overridden ? 2 : 1.5
                path.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let r = resetRect, r.contains(p) { onReset?(); return }
        if inheritRect.contains(p) { onToolOpacity?(nil); return }
        for (i, rect) in appRects().enumerated() where rect.contains(p) {
            onSelectApp?(i)
            return
        }
        guard appIds.indices.contains(selectedApp) else { return }
        let rects = cardRects()
        for (i, role) in roles.enumerated()
            where rects.indices.contains(i) && rects[i].contains(p) {
            onEdit?(appIds[selectedApp], role.key)
            return
        }
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- colour inspector -------------------------------------------------------

// HSL helpers for the inspector's channels, harmony and tones. Same formulas
// as Aether's color.ts: h in degrees, s and l in percent.
func hslComponents(_ hex: String) -> (h: Double, s: Double, l: Double) {
    let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard clean.count == 6, let v = UInt64(clean, radix: 16) else { return (0, 0, 0) }
    let r = Double((v >> 16) & 0xff) / 255
    let g = Double((v >> 8) & 0xff) / 255
    let b = Double(v & 0xff) / 255
    let maxV = max(r, max(g, b)), minV = min(r, min(g, b))
    let l = (maxV + minV) / 2
    var h = 0.0, s = 0.0
    if maxV != minV {
        let d = maxV - minV
        s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        if maxV == r { h = ((g - b) / d + (g < b ? 6 : 0)) / 6 }
        else if maxV == g { h = ((b - r) / d + 2) / 6 }
        else { h = ((r - g) / d + 4) / 6 }
    }
    return (h * 360, s * 100, l * 100)
}

func hslHex(_ h: Double, _ s: Double, _ l: Double) -> String {
    let hn = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360
    let sn = min(100, max(0, s)) / 100
    let ln = min(100, max(0, l)) / 100
    if sn == 0 {
        let v = Int((ln * 255).rounded())
        return String(format: "#%02x%02x%02x", v, v, v)
    }
    let q = ln < 0.5 ? ln * (1 + sn) : ln + sn - ln * sn
    let p = 2 * ln - q
    func hue(_ t0: Double) -> Double {
        var t = t0
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
        return p
    }
    let r = Int((hue(hn + 1.0 / 3.0) * 255).rounded())
    let g = Int((hue(hn) * 255).rounded())
    let b = Int((hue(hn - 1.0 / 3.0) * 255).rounded())
    return String(format: "#%02x%02x%02x", min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)))
}

// One channel row, Aether's channel style: a gradient track with a white
// handle and a typed value on the right.
final class ChannelSliderView: NSView, NSTextFieldDelegate {
    var label = ""
    var suffix = ""
    var minValue = 0.0
    var maxValue = 255.0
    var value = 0.0 { didSet { needsDisplay = true; syncField() } }
    var gradient: [NSColor]?
    var onChange: ((Double) -> Void)?
    private let valueField = NSTextField()
    private var dragging = false

    static let rowHeight: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        valueField.isBezeled = false
        valueField.drawsBackground = false
        valueField.textColor = palette.label
        valueField.font = nerdFont("Regular", 11)
        valueField.alignment = .right
        valueField.focusRingType = .none
        valueField.delegate = self
        valueField.target = self
        valueField.action = #selector(fieldReturn)
        addSubview(valueField)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func setValue(_ v: Double, notify: Bool) {
        value = v
        syncField()
        if notify { onChange?(v) }
    }

    func refreshColors() {
        valueField.textColor = palette.label
        needsDisplay = true
    }

    private func syncField() {
        guard valueField.currentEditor() == nil else { return }
        valueField.stringValue = "\(Int(value.rounded()))\(suffix)"
    }

    @objc private func fieldReturn() { commitField() }
    func controlTextDidEndEditing(_ obj: Notification) { commitField() }

    private func commitField() {
        let raw = valueField.stringValue
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let n = Double(raw) else { syncField(); return }
        let v = min(maxValue, max(minValue, n))
        if abs(v - value) > 1e-9 { setValue(v, notify: true) }
        syncField()
    }

    private var trackRect: NSRect {
        NSRect(x: 18, y: bounds.height / 2 - 4, width: max(10, bounds.width - 18 - 48), height: 8)
    }

    private func update(from p: NSPoint) {
        let t = min(1, max(0, (p.x - trackRect.minX) / max(1, trackRect.width)))
        setValue(minValue + Double(t) * (maxValue - minValue), notify: true)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.x >= 10, p.x <= bounds.width - 40 else { return }
        dragging = true
        update(from: p)
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        update(from: convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) { dragging = false }

    override func draw(_ dirtyRect: NSRect) {
        let mid = bounds.height / 2
        drawMidLeft(label, nerdFont("Regular", 10), palette.muted,
                    x: 0, midTop: mid, height: bounds.height)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 2, yRadius: 2)
        if let colors = gradient, colors.count >= 2 {
            NSGradient(colors: colors)?.draw(in: track, angle: 0)
        } else {
            palette.itemBG.withAlphaComponent(0.6).setFill()
            track.fill()
        }
        palette.muted.withAlphaComponent(0.3).setStroke()
        track.lineWidth = 0.5
        track.stroke()
        let t = (value - minValue) / max(1e-9, maxValue - minValue)
        let cx = trackRect.minX + CGFloat(t) * trackRect.width
        let handle = NSBezierPath(roundedRect: NSRect(x: cx - 2, y: mid - 7, width: 4, height: 14),
                                  xRadius: 1.5, yRadius: 1.5)
        NSColor.white.setFill()
        handle.fill()
        NSColor.black.withAlphaComponent(0.6).setStroke()
        handle.lineWidth = 1
        handle.stroke()
    }

    override func layout() {
        super.layout()
        valueField.frame = NSRect(x: bounds.width - 44, y: bounds.height / 2 - 8, width: 44, height: 16)
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// The full colour inspector for the selected swatch: name and hex, contrast
// against the palette's background and foreground, the RGB/HSL channels with
// gradient tracks, harmony swatches, the 11-step tone row and the session's
// recent colours. Harmony, tones and recents apply the colour they show.
final class ColorInspectorView: NSView, NSTextFieldDelegate {
    var onColor: ((String) -> Void)?

    private let hexField = NSTextField()
    private let tabs = SegmentedView()
    private var rgbSliders: [ChannelSliderView] = []
    private var hslSliders: [ChannelSliderView] = []

    private(set) var hex = "#000000"
    private var title = "No colour selected"
    private var bgHex = "#000000"
    private var fgHex = "#ffffff"
    private var recents: [String] = []
    private var active = false
    private var syncing = false
    private var tab = 0   // 0 RGB, 1 HSL

    private var harmony: [(label: String, hex: String)] = []
    private var tones: [String] = []
    private var currentTone = -1

    static let viewHeight: CGFloat = 292
    static let harmonySpec: [(label: String, delta: Double)] = [
        ("An−", -30), ("Tri+", 120), ("Comp", 180), ("Tri−", 240), ("An+", 30),
    ]

    // vertical plan, top down
    private let headerTop: CGFloat = 0
    private let contrastTop: CGFloat = 28
    private let channelsTop: CGFloat = 48
    private let channelRowsTop: CGFloat = 78
    private let harmonyTop: CGFloat = 168
    private let tonesTop: CGFloat = 226
    private let recentTop: CGFloat = 266

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hexField.isBezeled = false
        hexField.drawsBackground = true
        hexField.backgroundColor = palette.itemBG.withAlphaComponent(0.25)
        hexField.textColor = palette.label
        hexField.font = nerdFont("Regular", 11)
        hexField.alignment = .center
        hexField.focusRingType = .none
        hexField.delegate = self
        hexField.target = self
        hexField.action = #selector(hexReturn)
        addSubview(hexField)

        tabs.items = ["RGB", "HSL"]
        tabs.index = 0
        tabs.onChange = { [weak self] i in
            guard let self else { return }
            self.tab = i
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.needsDisplay = true
        }
        addSubview(tabs)

        for (i, label) in ["R", "G", "B"].enumerated() {
            let s = ChannelSliderView()
            s.label = label
            s.minValue = 0
            s.maxValue = 255
            s.onChange = { [weak self] v in self?.rgbChanged(i, v) }
            rgbSliders.append(s)
            addSubview(s)
        }
        for (i, spec) in [("H", "°", 360.0), ("S", "%", 100.0), ("L", "%", 100.0)].enumerated() {
            let s = ChannelSliderView()
            s.label = spec.0
            s.suffix = spec.1
            s.minValue = 0
            s.maxValue = spec.2
            s.onChange = { [weak self] v in self?.hslChanged(i, v) }
            hslSliders.append(s)
            addSubview(s)
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(hex: String?, title: String, active: Bool,
                bgHex: String, fgHex: String, recent: [String]) {
        syncing = true
        self.title = title
        self.active = active
        self.bgHex = bgHex
        self.fgHex = fgHex
        self.recents = recent
        self.hex = hex ?? "#000000"
        if hexField.currentEditor() == nil { hexField.stringValue = hex ?? "" }
        syncChannels()
        syncing = false
        recomputeDerivedSwatches()
        needsDisplay = true
        layoutSubtreeIfNeeded()
    }

    private func syncChannels() {
        guard hex.count == 7, let v = UInt64(hex.dropFirst(), radix: 16) else { return }
        let r = Double((v >> 16) & 0xff), g = Double((v >> 8) & 0xff), b = Double(v & 0xff)
        rgbSliders[0].setValue(r, notify: false)
        rgbSliders[1].setValue(g, notify: false)
        rgbSliders[2].setValue(b, notify: false)
        let hsl = hslComponents(hex)
        hslSliders[0].setValue(hsl.h, notify: false)
        hslSliders[1].setValue(hsl.s, notify: false)
        hslSliders[2].setValue(hsl.l, notify: false)
        hslSliders[0].gradient = stride(from: 0.0, through: 360.0, by: 30.0).map {
            nsColor(fromHex: hslHex($0, max(40, hsl.s), min(70, max(30, hsl.l))))
        }
        hslSliders[1].gradient = [
            nsColor(fromHex: hslHex(hsl.h, 0, hsl.l)),
            nsColor(fromHex: hslHex(hsl.h, 50, hsl.l)),
            nsColor(fromHex: hslHex(hsl.h, 100, hsl.l)),
        ]
        hslSliders[2].gradient = [
            nsColor(fromHex: hslHex(hsl.h, hsl.s, 4)),
            nsColor(fromHex: hslHex(hsl.h, hsl.s, 50)),
            nsColor(fromHex: hslHex(hsl.h, hsl.s, 96)),
        ]
    }

    private func recomputeDerivedSwatches() {
        let hsl = hslComponents(hex)
        harmony = Self.harmonySpec.map { ($0.label, hslHex(hsl.h + $0.delta, hsl.s, hsl.l)) }
        tones = (0..<11).map { i in hslHex(hsl.h, hsl.s, 8 + Double(i) * 8.4) }
        currentTone = (0..<11).first { abs((8 + Double($0) * 8.4) - hsl.l) < 4.2 } ?? -1
    }

    @objc private func hexReturn() { commitHex() }
    func controlTextDidEndEditing(_ obj: Notification) { commitHex() }

    private func commitHex() {
        guard !syncing else { return }
        guard let clean = cleanHex(hexField.stringValue) else {
            hexField.stringValue = hex
            return
        }
        if clean != hex { onColor?(clean) }
    }

    private func rgbChanged(_ index: Int, _ value: Double) {
        guard !syncing, hex.count == 7, let v = UInt64(hex.dropFirst(), radix: 16) else { return }
        var c = [Double((v >> 16) & 0xff), Double((v >> 8) & 0xff), Double(v & 0xff)]
        c[index] = max(0, min(255, value.rounded()))
        apply(String(format: "#%02x%02x%02x", Int(c[0]), Int(c[1]), Int(c[2])))
    }

    private func hslChanged(_ index: Int, _ value: Double) {
        guard !syncing else { return }
        var hsl = hslComponents(hex)
        switch index {
        case 0: hsl.h = value
        case 1: hsl.s = value
        default: hsl.l = value
        }
        apply(hslHex(hsl.h, hsl.s, hsl.l))
    }

    private func apply(_ out: String) {
        hex = out
        hexField.stringValue = out
        syncChannels()
        recomputeDerivedSwatches()
        needsDisplay = true
        onColor?(out)
    }

    // --- geometry ----------------------------------------------------------

    private func swatchRow(count: Int, top: CGFloat, height: CGFloat) -> [NSRect] {
        guard count > 0 else { return [] }
        let gap: CGFloat = 4
        let w = (bounds.width - CGFloat(count - 1) * gap) / CGFloat(count)
        return (0..<count).map {
            NSRect(x: CGFloat($0) * (w + gap), y: bounds.height - top - height, width: w, height: height)
        }
    }

    private func harmonyRects() -> [NSRect] { swatchRow(count: harmony.count, top: harmonyTop, height: 28) }
    private func toneRects() -> [NSRect] { swatchRow(count: tones.count, top: tonesTop, height: 22) }
    private func recentRects() -> [NSRect] { swatchRow(count: recents.count, top: recentTop, height: 16) }

    override func layout() {
        super.layout()
        hexField.frame = NSRect(x: bounds.width - 96, y: bounds.height - headerTop - 24,
                                width: 96, height: 18)
        let tabsSize = tabs.sizeThatFits()
        tabs.frame = NSRect(x: bounds.width - tabsSize.width,
                            y: bounds.height - channelsTop - tabsSize.height + 4,
                            width: tabsSize.width, height: tabsSize.height)
        let active = tab == 0 ? rgbSliders : hslSliders
        for s in rgbSliders { s.isHidden = tab != 0 }
        for s in hslSliders { s.isHidden = tab != 1 }
        for (i, s) in active.enumerated() {
            s.frame = NSRect(x: 0, y: bounds.height - channelRowsTop - CGFloat(i + 1) * ChannelSliderView.rowHeight,
                             width: bounds.width, height: ChannelSliderView.rowHeight)
        }
    }

    private func eyebrow(_ text: String, _ top: CGFloat) {
        drawTopLeft(text, nerdFont("Bold", 9), palette.muted,
                    x: 0, top: top, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        if !active {
            drawMidLeft("Click a colour card to edit it.", nerdFont("Regular", 11), palette.muted,
                        x: 0, midTop: 12, height: bounds.height)
            return
        }
        // header: preview + name + hex field
        let preview = NSRect(x: 0, y: bounds.height - headerTop - 22, width: 22, height: 22)
        let path = NSBezierPath(roundedRect: preview.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        nsColor(fromHex: hex).setFill()
        path.fill()
        palette.muted.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawMidLeft(truncate(title, nerdFont("Bold", 11), bounds.width - 130),
                    nerdFont("Bold", 11), palette.label,
                    x: 30, midTop: headerTop + 11, height: bounds.height)

        // contrast against the palette background and foreground
        let bgRatio = contrastRatioHex(hex, bgHex)
        let fgRatio = contrastRatioHex(hex, fgHex)
        func level(_ r: Double) -> String {
            r >= 7 ? "AAA" : (r >= 4.5 ? "AA" : (r >= 3 ? "AA-L" : "fail"))
        }
        let bgText = String(format: "%.1f \(level(bgRatio)) vs bg", bgRatio)
        let fgText = String(format: "%.1f \(level(fgRatio)) vs fg", fgRatio)
        let startX = drawColored(bgText, nerdFont("Regular", 9),
                                 ink: bgRatio >= 4.5 ? .systemGreen : .systemRed,
                                 x: 0, top: contrastTop, height: bounds.height)
        _ = drawColored(fgText, nerdFont("Regular", 9),
                        ink: fgRatio >= 4.5 ? .systemGreen : .systemRed,
                        x: startX + 10, top: contrastTop, height: bounds.height)

        eyebrow("Channels", channelsTop + 2)
        eyebrow("Harmony", harmonyTop - 12)
        eyebrow("Tones", tonesTop - 12)
        if !recents.isEmpty { eyebrow("Recent", recentTop - 12) }

        for (i, h) in harmony.enumerated() {
            let r = harmonyRects()[i]
            nsColor(fromHex: h.hex).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
            drawMidCenter(h.label, nerdFont("Regular", 9), palette.muted,
                          centerX: r.midX, midTop: bounds.height - r.minY + 8, height: bounds.height)
        }
        for (i, t) in tones.enumerated() {
            let r = toneRects()[i]
            nsColor(fromHex: t).setFill()
            NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
            if i == currentTone {
                NSColor.white.setStroke()
                let ring = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
                ring.lineWidth = 2
                ring.stroke()
            }
        }
        for (i, c) in recents.enumerated() {
            let r = recentRects()[i]
            nsColor(fromHex: c).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
        }
    }

    // draws one text run and returns the x it ended at, so two runs can sit
    // on one line with different inks
    @discardableResult
    private func drawColored(_ s: String, _ font: NSFont, ink: NSColor,
                             x: CGFloat, top: CGFloat, height: CGFloat) -> CGFloat {
        drawTopLeft(s, font, ink, x: x, top: top, height: height)
        return x + advance(s, font)
    }

    override func mouseDown(with event: NSEvent) {
        guard active else { return }
        let p = convert(event.locationInWindow, from: nil)
        for (i, h) in harmony.enumerated() where harmonyRects()[i].contains(p) {
            onColor?(h.hex)
            return
        }
        for (i, t) in tones.enumerated() where toneRects()[i].contains(p) {
            onColor?(t)
            return
        }
        for (i, c) in recents.enumerated() where recentRects()[i].contains(p) {
            onColor?(c)
            return
        }
    }

    func refreshColors() {
        hexField.textColor = palette.label
        hexField.backgroundColor = palette.itemBG.withAlphaComponent(0.25)
        for s in rgbSliders + hslSliders { s.refreshColors() }
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// --- editor columns ---------------------------------------------------------

// The left column: Method, Mode, the curve box, the 12 sliders and Reset.
// A thin view over the shared PaletteModel.
final class PaletteBuilderView: NSView {
    var model: PaletteModel? { didSet { wire() } }
    var stepBadge = 0 { didSet { needsDisplay = true } }

    private let scroll = NSScrollView()
    private let scroller = CustomScroller()
    private let doc = PaletteBuilderDoc()
    private let scrollerW: CGFloat = 8
    private var shownEditKey: String?
    private var shownImage = ""
    // The palette's own history, fixed in the column header.
    private let undoButton = ButtonView()
    private let redoButton = ButtonView()
    private let resetButton = ButtonView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        undoButton.title = "\u{f0e2}"
        redoButton.title = "\u{f01e}"
        for b in [undoButton, redoButton] {
            b.centeredByBounds = true
            b.fontSize = 12
            addSubview(b)
        }
        undoButton.toolTip = "Undo Palette Edit"
        redoButton.toolTip = "Redo Palette Edit"
        resetButton.title = "Reset"
        resetButton.fontSize = 11
        resetButton.toolTip = "Reset Colour Adjustments"
        addSubview(resetButton)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = doc
        addSubview(scroller)
        scroller.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled() { scroller.refresh() }

    private func wire() {
        doc.methodButton.onClick = { [weak self] in
            guard let self, let model = self.model else { return }
            var rows: [MethodPicker.Row] = [
                MethodPicker.Row(header: nil, value: "magic", label: "Magic"),
            ]
            for group in model.modeGroups {
                rows.append(MethodPicker.Row(header: group.label.uppercased(),
                                             value: nil, label: group.label))
                for m in group.modes {
                    rows.append(MethodPicker.Row(header: nil, value: m.value, label: m.label))
                }
            }
            MethodPicker.present(from: self.doc.methodButton, rows: rows, strips: model.strips,
                                 currentMethod: model.method) { [weak model] value in
                model?.chooseMethod(value)
            }
        }
        doc.presetsButton.onClick = { [weak self] in
            guard let self, let model = self.model else { return }
            model.withPresets { [weak self] presets in
                guard let self, !presets.isEmpty else { return }
                var rows: [MethodPicker.Row] = []
                var strips: [String: [String]] = [:]
                for mode in ["dark", "light"] {
                    let group = presets.filter { $0.mode == mode }
                    guard !group.isEmpty else { continue }
                    rows.append(MethodPicker.Row(header: mode.uppercased(),
                                                 value: nil, label: mode.uppercased()))
                    for p in group {
                        rows.append(MethodPicker.Row(header: nil, value: p.name, label: p.name))
                        strips[p.name] = p.colors
                    }
                }
                MethodPicker.present(from: self.doc.presetsButton, rows: rows, strips: strips,
                                     currentMethod: model.sourceName ?? "") { [weak self] name in
                    guard let colors = strips[name] else { return }
                    self?.model?.applyPreset(name, colors: colors)
                }
            }
        }
        doc.fromColorBuild.onClick = { [weak self] in
            self?.model?.applyFromColor(self?.doc.fromColorField.stringValue ?? "")
        }
        doc.gradientBuild.onClick = { [weak self] in
            guard let self else { return }
            self.model?.applyGradient(self.doc.gradientStart.stringValue,
                                      self.doc.gradientEnd.stringValue)
        }
        doc.fromColorWell.onChange = { [weak self] hex in
            self?.doc.fromColorField.stringValue = hex
        }
        doc.gradientStartWell.onChange = { [weak self] hex in
            self?.doc.gradientStart.stringValue = hex
        }
        doc.gradientEndWell.onChange = { [weak self] hex in
            self?.doc.gradientEnd.stringValue = hex
        }
        doc.modeSeg.onChange = { [weak self] i in self?.model?.setMode(i) }
        doc.inspector.onColor = { [weak self] hex in self?.model?.writeEditTarget(hex) }
        doc.curveView.onChange = { [weak self] points in self?.model?.setCurve(points) }
        for slider in doc.sliders {
            let key = slider.spec.key
            slider.onChange = { [weak self] v in self?.model?.setAdjustment(key, v) }
        }
        resetButton.onClick = { [weak self] in self?.model?.resetAdjustments() }
        undoButton.onClick = { [weak self] in self?.model?.undo() }
        redoButton.onClick = { [weak self] in self?.model?.redo() }
    }

    func sync() {
        guard let model else { return }
        doc.methodButton.title = model.methodLabel(model.method)
        doc.presetsButton.title = model.sourceIsPreset ? (model.sourceName ?? "Choose…") : "Choose…"
        // scratch inputs for the two generated sources: seeded per document
        if model.imagePath != shownImage {
            shownImage = model.imagePath
            doc.fromColorField.stringValue = model.extendedHex["accent"] ?? "#ffffff"
            doc.gradientStart.stringValue = model.baseColors.first ?? "#000000"
            doc.gradientEnd.stringValue = model.extendedHex["accent"] ?? "#ffffff"
        }
        doc.fromColorWell.hex = doc.fromColorField.stringValue
        doc.gradientStartWell.hex = doc.gradientStart.stringValue
        doc.gradientEndWell.hex = doc.gradientEnd.stringValue
        doc.contrast = model.contrastRows()
        doc.modeSeg.index = model.mode == "light" ? 2 : (model.mode == "dark" ? 1 : 0)
        doc.modeSeg.needsDisplay = true
        doc.curveView.points = model.curve
        doc.curveView.histogram = model.histogram
        for slider in doc.sliders {
            slider.setValue(model.adjustments[slider.spec.key], notify: false)
        }
        let editing = model.editTarget != nil
        if doc.editorVisible != editing {
            doc.editorVisible = editing
            doc.inspector.isHidden = !editing
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        let finals = model.finalColors.count == 16 ? model.finalColors : model.baseColors
        doc.inspector.update(hex: model.editTargetHex(), title: model.editTargetTitle(),
                             active: editing,
                             bgHex: finals.first ?? "#000000",
                             fgHex: finals.indices.contains(7) ? finals[7] : "#ffffff",
                             recent: model.recentColors)
        // Bring the inspector into view only when a different colour is
        // picked: keyed on the target itself, not its hex, so applying a
        // preset or rendering the palette never yanks the column around.
        let editKey = editing ? model.editTargetTitle() : nil
        if editKey != shownEditKey {
            shownEditKey = editKey
            if editKey != nil {
                DispatchQueue.main.async { [weak self] in self?.doc.scrollInspectorIntoView() }
            }
        }
        // the Contrast section appears once the roles land: the document
        // grows, so the scroll host has to re-run its layout
        needsLayout = true
        doc.needsDisplay = true
        needsDisplay = true
    }

    func refreshColors() {
        needsDisplay = true
        markTree(doc)
        for slider in doc.sliders { slider.refreshColors() }
        doc.inspector.refreshColors()
    }

    private func markTree(_ view: NSView) {
        view.needsDisplay = true
        for sub in view.subviews { markTree(sub) }
    }

    override func layout() {
        super.layout()
        let headerH: CGFloat = 40
        let h = max(0, bounds.height - headerH)
        resetButton.frame = NSRect(x: bounds.width - 12 - 56, y: bounds.height - 30,
                                   width: 56, height: 24)
        redoButton.frame = NSRect(x: resetButton.frame.minX - 6 - 24, y: bounds.height - 30,
                                  width: 24, height: 24)
        undoButton.frame = NSRect(x: redoButton.frame.minX - 6 - 24, y: bounds.height - 30,
                                  width: 24, height: 24)
        scroll.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - scrollerW - 14), height: h)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: 0, width: scrollerW, height: h)
        scroller.refresh()
        let w = scroll.contentSize.width
        let clipH = scroll.contentSize.height
        let targetH = max(doc.contentHeight(), clipH)
        if w > 0, (abs(doc.frame.width - w) > 0.5 || abs(doc.frame.height - targetH) > 0.5) {
            let first = doc.frame.width == 0
            let oldH = doc.frame.height
            doc.frame = NSRect(origin: .zero, size: NSSize(width: w, height: targetH))
            doc.needsLayout = true
            doc.layoutSubtreeIfNeeded()
            // Top-anchored layout: content moves up in document coordinates
            // whenever the height grows (the Accessibility rows arrive
            // asynchronously). Carry the scroll origin by the same delta so
            // the view stays on the content under it — first open lands at
            // the top and stays there.
            let clip = scroll.contentView
            let maxY = max(0, targetH - clipH)
            let cur = clip.bounds.origin.y
            let next = first ? maxY : min(maxY, max(0, cur + (targetH - oldH)))
            if abs(next - cur) > 0.5 {
                clip.scroll(to: NSPoint(x: 0, y: next))
                scroll.reflectScrolledClipView(clip)
            }
            scroller.refresh()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if stepBadge > 0 {
            drawStepBadge(stepBadge, centerX: 24, midTop: 18, height: bounds.height)
        }
        drawMidLeft("Palette Builder", nerdFont("Bold", 13), palette.accent,
                    x: stepBadge > 0 ? 42 : 16, midTop: 18, height: bounds.height)
    }
}

final class PaletteBuilderDoc: NSView {
    let methodButton = PopupButtonView()
    let modeSeg = SegmentedView()
    let inspector = ColorInspectorView()
    let curveView = CurveEditorView()
    var sliders: [AdjustmentSliderView] = []
    // palette sources
    let presetsButton = PopupButtonView()
    let fromColorField = NSTextField()
    let fromColorWell = ColorWellView()
    let fromColorBuild = ButtonView()
    let gradientStart = NSTextField()
    let gradientEnd = NSTextField()
    let gradientStartWell = ColorWellView()
    let gradientEndWell = ColorWellView()
    let gradientBuild = ButtonView()
    // Accessibility section data
    var contrast: [PaletteModel.ContrastRow] = []

    // the inspector appears only while a card is selected
    var editorVisible = false

    private let insetL: CGFloat = 16
    private let insetR: CGFloat = 12
    private var methodTop: CGFloat = 0
    private var modeTop: CGFloat = 0
    private var presetsTop: CGFloat = 0
    private var fromColorTop: CGFloat = 0
    private var gradientTop: CGFloat = 0
    private var editorTop: CGFloat = 0
    private var adjTop: CGFloat = 0
    private var adjSliderTop: CGFloat = 0
    private var adjSliderBottom: CGFloat = 0
    private var contrastTop: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        modeSeg.items = ["Auto", "Dark", "Light"]
        addSubview(methodButton)
        addSubview(modeSeg)
        inspector.isHidden = true
        addSubview(inspector)
        addSubview(curveView)
        for f in EditorAdjustments.fields {
            let s = AdjustmentSliderView(spec: f.spec)
            sliders.append(s)
            addSubview(s)
        }
        presetsButton.title = "Presets"
        addSubview(presetsButton)
        for f in [fromColorField, gradientStart, gradientEnd] {
            f.isBezeled = false
            f.drawsBackground = true
            f.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
            f.textColor = palette.label
            f.font = nerdFont("Regular", 12)
            f.focusRingType = .none
            f.usesSingleLineMode = true
            f.lineBreakMode = .byTruncatingTail
            addSubview(f)
        }
        fromColorBuild.title = "Build"
        gradientBuild.title = "Build"
        addSubview(fromColorBuild)
        addSubview(gradientBuild)
        addSubview(fromColorWell)
        addSubview(gradientStartWell)
        addSubview(gradientEndWell)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private var contentW: CGFloat { max(0, bounds.width - insetL - insetR) }

    // Brings the colour panel to the top of the left pane when a card is
    // picked, so the controls the click opened are in view.
    func scrollInspectorIntoView() {
        guard editorVisible, let scroll = enclosingScrollView else { return }
        layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let docH = bounds.height
        let top = max(0, editorTop - 12)
        let origin = min(max(0, docH - clip.bounds.height), max(0, docH - top - clip.bounds.height))
        clip.scroll(to: NSPoint(x: 0, y: origin))
        scroll.reflectScrolledClipView(clip)
    }

    func contentHeight() -> CGFloat {
        var h: CGFloat = 10
        h += 34 + 34                                        // Method + Mode
        h += 34 + 10 + 60 + 60                              // Presets, From Colour, Gradient
        if editorVisible { h += ColorInspectorView.viewHeight + 20 }
        h += 24                                             // Adjustments
        h += CurveEditorView.viewHeight + 14
        h += CGFloat(sliders.count) * AdjustmentSliderView.rowHeight
        h += 12                                             // gap under the frame
        h += 38 + CGFloat(contrast.count) * 26              // Accessibility
        h += 10
        return h
    }

    private func rect(top: CGFloat, h: CGFloat, x: CGFloat, w: CGFloat) -> NSRect {
        NSRect(x: x, y: bounds.height - top - h, width: w, height: h)
    }

    override func layout() {
        super.layout()
        var top: CGFloat = 10
        modeTop = top
        let segSize = modeSeg.sizeThatFits()
        // same width as the Method and Presets popups: one flush column
        modeSeg.frame = rect(top: top + 3, h: segSize.height,
                             x: insetL + max(0, contentW - 170), w: min(170, contentW))
        top += 34
        methodTop = top
        methodButton.frame = rect(top: top + 3, h: 26, x: insetL + max(0, contentW - 170), w: 170)
        top += 34
        presetsTop = top
        presetsButton.frame = rect(top: top + 3, h: 26, x: insetL + max(0, contentW - 170), w: 170)
        top += 34
        // the two generator sections run on the same rhythm: 10 above the
        // heading, 22 to its controls, 60 per section
        fromColorTop = top + 10
        let wellS: CGFloat = 24, buildW: CGFloat = 64
        fromColorWell.frame = rect(top: fromColorTop + 22, h: wellS, x: insetL, w: wellS)
        fromColorField.frame = rect(top: fromColorTop + 23, h: 22, x: insetL + wellS + 6, w: 62)
        fromColorBuild.frame = rect(top: fromColorTop + 22, h: 24, x: insetL + contentW - buildW, w: buildW)
        top = fromColorTop + 60
        gradientTop = top
        let gW: CGFloat = 62
        gradientStartWell.frame = rect(top: gradientTop + 22, h: wellS, x: insetL, w: wellS)
        gradientStart.frame = rect(top: gradientTop + 23, h: 22, x: insetL + wellS + 6, w: gW)
        gradientEndWell.frame = rect(top: gradientTop + 22, h: wellS,
                                     x: insetL + wellS + 6 + gW + 6, w: wellS)
        gradientEnd.frame = rect(top: gradientTop + 23, h: 22,
                                 x: insetL + wellS + 6 + gW + 6 + wellS + 6, w: gW)
        gradientBuild.frame = rect(top: gradientTop + 22, h: 24, x: insetL + contentW - buildW, w: buildW)
        top = gradientTop + 60
        if editorVisible {
            editorTop = top + 10
            inspector.frame = rect(top: editorTop, h: ColorInspectorView.viewHeight,
                                   x: insetL, w: contentW)
            top += ColorInspectorView.viewHeight + 20
        }
        adjTop = top
        top += 24
        curveView.frame = rect(top: top, h: CurveEditorView.viewHeight, x: insetL, w: contentW)
        top += CurveEditorView.viewHeight + 14
        adjSliderTop = top
        for s in sliders {
            // inset inside the frame so the label and value never touch its line
            s.frame = rect(top: top, h: AdjustmentSliderView.rowHeight,
                           x: insetL + 10, w: contentW - 20)
            top += AdjustmentSliderView.rowHeight
        }
        adjSliderBottom = top
        top += 20
        contrastTop = top
    }

    // A hairline 6 pt above a section's heading, matching the wallpaper
    // editor's rules: each feature block gets its own visual panel.
    private func drawRule(_ top: CGFloat) {
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: insetL, y: bounds.height - (top - 6), width: contentW, height: 1).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawMidLeft("Mode", nerdFont("Bold", 12), palette.label,
                    x: insetL, midTop: modeTop + 16, height: bounds.height)
        drawMidLeft("Method", nerdFont("Bold", 12), palette.label,
                    x: insetL, midTop: methodTop + 16, height: bounds.height)
        drawMidLeft("Presets", nerdFont("Bold", 12), palette.label,
                    x: insetL, midTop: presetsTop + 16, height: bounds.height)
        drawRule(fromColorTop)
        drawTopLeft("From Colour", nerdFont("Bold", 12), palette.label,
                    x: insetL, top: fromColorTop, height: bounds.height)
        drawRule(gradientTop)
        drawTopLeft("Gradient", nerdFont("Bold", 12), palette.label,
                    x: insetL, top: gradientTop, height: bounds.height)
        if editorVisible { drawRule(editorTop) }
        drawRule(adjTop)
        drawTopLeft("Adjustments", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: adjTop, height: bounds.height)
        // a rounded 1 px frame around the twelve slider rows; it shares the
        // column's left and right edges with the controls above it
        let frame = NSRect(x: insetL, y: bounds.height - adjSliderBottom - 6,
                           width: contentW, height: (adjSliderBottom - adjSliderTop) + 12)
        let path = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        palette.muted.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 1
        path.stroke()
        // no rule between the frame and Accessibility: the frame separates
        drawTopLeft("Accessibility", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: contrastTop, height: bounds.height)
        drawContrast()
    }

    // Label / Accent / Muted against the three surfaces the theme paints
    // (bar, pill, base background), each with its WCAG badge.
    private func drawContrast() {
        guard !contrast.isEmpty else { return }
        let h = bounds.height
        let pass = contrast.flatMap { $0.ratios }.filter { $0 >= 4.5 }.count
        let summary = "\(pass) of \(contrast.count * 3) pass AA"
        let sf = nerdFont("Regular", 10)
        drawMidLeft(summary, sf, palette.muted,
                    x: insetL + contentW - advance(summary, sf), midTop: contrastTop + 9,
                    height: h)
        let colW: CGFloat = 64
        let centres = [insetL + contentW - colW * 2.5,
                       insetL + contentW - colW * 1.5,
                       insetL + contentW - colW * 0.5]
        for (i, title) in ["BAR", "PILL", "SURFACE"].enumerated() {
            drawMidCenter(title, nerdFont("Regular", 9), palette.muted,
                          centerX: centres[i], midTop: contrastTop + 26, height: h)
        }
        for (i, row) in contrast.enumerated() {
            let mid = contrastTop + 38 + CGFloat(i) * 26 + 13
            drawMidLeft(row.name, nerdFont("Bold", 12), palette.label,
                        x: insetL, midTop: mid, height: h)
            let dot = NSRect(x: insetL + 62, y: h - mid - 5, width: 10, height: 10)
            let dotPath = NSBezierPath(roundedRect: dot, xRadius: 3, yRadius: 3)
            nsColor(fromHex: row.hex).setFill()
            dotPath.fill()
            palette.muted.withAlphaComponent(0.4).setStroke()
            dotPath.lineWidth = 1
            dotPath.stroke()
            for (j, ratio) in row.ratios.enumerated() {
                // ratio and verdict, centred as one pair inside the column
                let badge = contrastBadge(ratio)
                let ratioText = String(format: "%.1f:1", ratio)
                let rf = nerdFont("Regular", 9)
                let bf = nerdFont(badge == "AAA" ? "Bold" : "Regular", 10)
                let rw = advance(ratioText, rf)
                let bw = advance(badge, bf)
                let x0 = centres[j] - (rw + 6 + bw) / 2
                let ink = badge == "!" ? NSColor.systemRed
                    : (badge == "AA-L" ? palette.muted : palette.label)
                drawMidLeft(ratioText, rf, palette.muted,
                            x: x0, midTop: mid, height: h)
                drawMidLeft(badge, bf, ink,
                            x: x0 + rw + 6, midTop: mid, height: h)
            }
        }
    }
}

// --- preview pane -----------------------------------------------------------

// The centre column's live desktop: the wallpaper being edited, drawn
// aspect-filled exactly as the real wallpaper is. It decodes straight to the
// pane's device-pixel size (the approach of helper/overlay.swift:129-192;
// never the full source, which costs ~80 MB per 4K picture), on a 16:10
// screen shape so what is shown IS the desktop and the menu-bar band can be
// cropped from it. Everything it draws comes from the PaletteModel; it never
// reads ~/.config/omarchy/current/theme, so an unsaved draft cannot be fooled
// by the live theme.
// A small icon button for the preview toolbar. It follows the ButtonView
// glyph pattern (centred on its ink, not its line box) but draws a translucent
// dark backplate so it stays legible over any wallpaper, and colours the glyph
// with the accent when ON and the muted role when OFF.
final class PreviewIconButton: NSView {
    var glyph = "" { didSet { needsDisplay = true } }
    var on = true { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let font = nerdFont("Regular", 12)
        let line = textLine(glyph, font, on ? palette.accent : palette.muted)
        let ink = CTLineGetImageBounds(line, ctx)
        ctx.textPosition = CGPoint(x: bounds.midX - ink.midX, y: bounds.midY - ink.midY)
        CTLineDraw(line, ctx)
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PreviewPaneView: NSView {
    weak var model: PaletteModel?

    // 1440x900: the frame derive.swift crops the menu-bar band from.
    static let screenAspect: CGFloat = 1440.0 / 900.0
    static let barFraction: CGFloat = 34.0 / 900.0

    // Overlays, toggled from the toolbar (step 3); on by default so the
    // preview opens as the desktop looks.
    var showMenuBar = true
    var showTerminal = true
    var showRing = true
    // The effective tool opacity (0...100) the terminal window is drawn at;
    // nil anywhere means opaque.
    var toolOpacity: Int?
    var globalOpacity: Int?
    var terminalOpacity: Int?
    // The edited render while a wallpaper filter is active; nil shows the raw
    // picture. The central pane is the edit surface, so the picture behind the
    // mock desktop reflects the edit.
    var editedImage: CGImage? { didSet { needsDisplay = true } }
    // Press and hold anywhere on the picture to see the original.
    var showingOriginal = false { didSet { needsDisplay = true } }
    private var compareDrag = false
    // Crop mode (step 1's interactive crop): the central pane shows the whole
    // picture with a draggable rect. cropRect is fractions of the source with a
    // top-left origin, exactly the engine's cropX/Y/W/H.
    var cropMode = false { didSet { needsDisplay = true } }
    var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1) { didSet { needsDisplay = true } }
    var cropAspect: CGFloat = 0          // 0 = free; otherwise the crop's pixel W/H
    var onCropChange: ((CGRect) -> Void)?
    private var cropDrag: (mode: Int, start: NSPoint, orig: CGRect)?

    private let toggleMenuBar = PreviewIconButton()
    private let toggleTerminal = PreviewIconButton()
    private let toggleRing = PreviewIconButton()
    private let viewPrompt = PreviewIconButton()
    private let viewCode = PreviewIconButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toggleMenuBar.glyph = "\u{f0c9}"
        toggleMenuBar.toolTip = "Menu Bar Preview"
        toggleMenuBar.onClick = { [weak self] in
            guard let self else { return }
            self.showMenuBar.toggle(); self.toggleMenuBar.on = self.showMenuBar
            self.needsDisplay = true
        }
        toggleTerminal.glyph = "\u{f120}"
        toggleTerminal.toolTip = "Terminal Preview"
        toggleTerminal.onClick = { [weak self] in
            guard let self else { return }
            self.showTerminal.toggle(); self.toggleTerminal.on = self.showTerminal
            self.needsDisplay = true
        }
        toggleRing.glyph = "\u{f2d0}"
        toggleRing.toolTip = "Focus Ring Preview"
        toggleRing.onClick = { [weak self] in
            guard let self else { return }
            self.showRing.toggle(); self.toggleRing.on = self.showRing
            self.needsDisplay = true
        }
        viewPrompt.glyph = "\u{f489}"
        viewPrompt.toolTip = "Terminal View"
        viewPrompt.onClick = { [weak self] in
            guard let self else { return }
            self.showPrompt.toggle(); self.viewPrompt.on = self.showPrompt
            self.needsDisplay = true
        }
        viewCode.glyph = "\u{f121}"
        viewCode.toolTip = "Code View"
        viewCode.onClick = { [weak self] in
            guard let self else { return }
            self.showCode.toggle(); self.viewCode.on = self.showCode
            self.needsDisplay = true
        }
        for b in [toggleMenuBar, toggleTerminal, toggleRing, viewPrompt, viewCode] { addSubview(b) }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let s = screen
        guard s.width > 1, s.height > 1 else { return }
        let size: CGFloat = 22, gap: CGFloat = 4
        let items = [toggleMenuBar, toggleTerminal, toggleRing, viewPrompt, viewCode]
        let total = CGFloat(items.count) * size + CGFloat(items.count - 1) * gap
        var x = max(s.minX + 6, s.maxX - 8 - total)
        let y = s.minY + 8
        for b in items {
            b.frame = NSRect(x: x, y: y, width: size, height: size)
            x += size + gap
        }
    }

    // The six bar roles, resolved from the editor's own state: `palette roles`
    // for bar/pill/muted/label/accent/ring, with the rendered palette as the
    // fallback before the first round-trip lands.
    private struct BarRoles {
        var bar = NSColor.black
        var pill = NSColor.black
        var muted = NSColor.gray
        var label = NSColor.white
        var accent = NSColor.systemBlue
        var ring = NSColor.systemBlue
    }

    private func resolvedRoles() -> BarRoles {
        guard let model else { return BarRoles() }
        let colors = model.finalColors.count == 16 ? model.finalColors : model.baseColors
        func color(_ i: Int) -> NSColor? {
            colors.indices.contains(i) ? nsColor(fromHex: colors[i]) : nil
        }
        var r = BarRoles()
        r.bar = model.roles["bar"].map(nsColor(fromHex:)) ?? color(0) ?? r.bar
        r.pill = model.roles["pill"].map(nsColor(fromHex:)) ?? color(8) ?? r.pill
        r.muted = model.roles["muted"].map(nsColor(fromHex:)) ?? color(8) ?? r.muted
        r.label = model.roles["label"].map(nsColor(fromHex:)) ?? color(7) ?? r.label
        r.accent = model.roles["accent"].map(nsColor(fromHex:))
            ?? model.finalExtended["accent"].map(nsColor(fromHex:)) ?? color(1) ?? r.accent
        r.ring = model.roles["ring"].map(nsColor(fromHex:)) ?? r.accent
        return r
    }

    // one glyph, centred on its ink in both axes (bar.swift's drawIcon): a
    // nerd-font icon drifts high and left in a line-box centre.
    private func drawGlyph(_ s: String, _ font: NSFont, _ color: NSColor, in box: NSRect) {
        guard !s.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let line = textLine(s, font, color)
        // measure from the line origin: a previous text draw leaves a
        // non-zero text position, and the ink bounds are relative to it
        ctx.textPosition = .zero
        let ink = CTLineGetImageBounds(line, ctx)
        ctx.textPosition = CGPoint(x: box.midX - ink.midX, y: box.midY - ink.midY)
        CTLineDraw(line, ctx)
    }

    // The real bar on this machine is transparent (autohide off): the pills sit
    // straight on the wallpaper's top band, so the picture behind them is the
    // real picture. Same pill vocabulary as bar.swift, same roles.
    private func drawMenuBar(in screen: NSRect) {
        let r = resolvedRoles()
        // Same numbers as bar.swift: the workspace chip is a 20x20 SQUARE
        // inside a bracket, not a stretched slot, and the pills derive from
        // the bar height rather than from a hand-tuned rectangle.
        let h: CGFloat = 34
        let baseY = screen.maxY - h
        let pillH = h - 8
        let chipBox: CGFloat = 20
        let chipPad: CGFloat = 2
        let chipPillH = min(chipBox, pillH - 2)
        let chipRadius = chipPillH * 0.28
        let radius: CGFloat = 4
        let padLeft: CGFloat = 10
        let gap: CGFloat = 14
        let chipFont = nerdFont("Regular", 11)
        let iconFont = nerdFont("Bold", 12)
        let nameFont = nerdFont("Bold", 12)
        let bar = NSRect(x: screen.minX, y: baseY, width: screen.width, height: h)
        let pillY = baseY + (h - pillH) / 2

        // apple pill, square
        let apple = NSRect(x: bar.minX + padLeft, y: pillY, width: pillH, height: pillH)
        r.pill.setFill()
        NSBezierPath(roundedRect: apple, xRadius: radius, yRadius: radius).fill()
        drawGlyph("\u{f179}", iconFont, r.accent, in: apple)

        // workspace bracket: five square chips, the third focused
        let chips: [(String, Bool)] = [("1", false), ("2", false), ("3", true),
                                       ("4", false), ("5", false)]
        let slotW = chipBox + chipPad * 2
        let bracket = NSRect(x: apple.maxX + 10, y: pillY,
                             width: CGFloat(chips.count) * slotW, height: pillH)
        r.pill.setFill()
        NSBezierPath(roundedRect: bracket, xRadius: radius, yRadius: radius).fill()
        var x = bracket.minX
        for (label, focused) in chips {
            let box = NSRect(x: x + chipPad, y: baseY, width: chipBox, height: h)
            if focused {
                let chip = NSRect(x: box.minX, y: baseY + (h - chipPillH) / 2,
                                  width: chipBox, height: chipPillH)
                r.accent.setFill()
                NSBezierPath(roundedRect: chip, xRadius: chipRadius, yRadius: chipRadius).fill()
            }
            drawGlyph(label, chipFont, focused ? r.bar : r.muted, in: box)
            x += slotW
        }

        // right cluster, laid out from the right edge inwards
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        let right: [(glyph: String, label: String, color: NSColor)] = [
            ("\u{F035B}", "", r.accent),                // activity
            ("", clock.string(from: Date()), r.label),  // clock
            ("\u{F0079}", "84%", r.label),              // battery
            ("\u{F05A9}", "", r.label),                 // wifi
        ]
        var cursor = bar.maxX - padLeft
        for item in right {
            let hasIcon = !item.glyph.isEmpty
            let hasLabel = !item.label.isEmpty
            let iconInk = hasIcon ? advance(item.glyph, iconFont) : 0
            let labelAdv = hasLabel ? advance(item.label, nameFont) : 0
            let inner: CGFloat = hasIcon && hasLabel ? 7 : 0
            let square = hasIcon && !hasLabel
            let w = square ? pillH : 10 + iconInk + inner + labelAdv + 10
            let pill = NSRect(x: cursor - w, y: pillY, width: w, height: pillH)
            r.pill.setFill()
            NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            if hasIcon {
                let box = square ? pill
                    : NSRect(x: pill.minX + 10, y: pill.minY, width: iconInk, height: pill.height)
                drawGlyph(item.glyph, iconFont, item.color, in: box)
            }
            if hasLabel {
                drawBaseline(item.label, nameFont, r.label,
                             x: pill.minX + 10 + iconInk + inner,
                             baseline: pill.midY - nameFont.capHeight / 2)
            }
            cursor = pill.minX - gap
        }
    }

    // --- fake terminal + code editor ---------------------------------------

    // `term view` shows the Starship-like prompt, `edit` shows the code sample;
    // the terminal/code toolbar toggle shows the whole window.
    var showPrompt = true
    var showCode = true
    private var selectedLanguage = 0
    static let languages = ["C", "JS", "PY", "RS", "GO", "JAVA"]
    private static let fileNames = ["fib.c", "fib.js", "fib.py", "fib.rs", "fib.go", "Fib.java"]

    // The window floats over the desktop, stored normalised to the screen rect
    // so it keeps its place when the pane is resized.
    private var termOrigin = NSPoint(x: 0.17, y: 0.19)
    private var termSize = NSSize(width: 0.66, height: 0.62)
    private var dragging = false
    private var dragStart = NSPoint.zero
    private var dragOrigin = NSPoint.zero
    private var tabRects: [NSRect] = []

    private var screen: NSRect {
        screenRect(in: bounds.insetBy(dx: 14, dy: 12)).integral
    }

    private func terminalRect(in screen: NSRect) -> NSRect {
        NSRect(x: screen.minX + screen.width * termOrigin.x,
               y: screen.minY + screen.height * termOrigin.y,
               width: screen.width * termSize.width,
               height: screen.height * termSize.height)
    }

    // The plan's fixed syntax map: keyword 5, string 2, comment 8, function 4,
    // number 3, type 6, plain 7.
    private enum Token { case kw, str, cmt, fn, num, type, fg }

    private func tokenColor(_ t: Token, _ c: [NSColor]) -> NSColor {
        func pick(_ i: Int) -> NSColor { c.indices.contains(i) ? c[i] : .white }
        switch t {
        case .fg: return pick(7)
        case .kw: return pick(5)
        case .str: return pick(2)
        case .cmt: return pick(8)
        case .fn: return pick(4)
        case .num: return pick(3)
        case .type: return pick(6)
        }
    }

    // One small function per language, so the same roles light up in each.
    private func sample(_ lang: Int) -> [[(String, Token)]] {
        let name = (String(Self.fileNames[max(0, min(Self.fileNames.count - 1, lang))].dropLast(2)), Token.fn)
        switch lang {
        case 0: return [ // C
            [("// fibonacci", .cmt)],
            [("char *", .type), ("name", .fg), (" = ", .fg), ("\"" + name.0 + "\"", .str), (";", .fg)],
            [("int ", .type), (name.0, .fn), ("(int n) {", .fg)],
            [("  ", .fg), ("if", .kw), (" (n < ", .fg), ("2", .num), (") ", .fg), ("return", .kw), (" n;", .fg)],
            [("  ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(n-", .fg), ("1", .num),
             (") + ", .fg), (name.0, .fn), ("(n-", .fg), ("2", .num), (");", .fg)],
            [("}", .fg)],
        ]
        case 1: return [ // JavaScript
            [("// fibonacci", .cmt)],
            [("const", .kw), (" name = ", .fg), ("\"" + name.0 + "\"", .str), (";", .fg)],
            [("function", .kw), (" ", .fg), (name.0, .fn), ("(n) {", .fg)],
            [("  ", .fg), ("if", .kw), (" (n < ", .fg), ("2", .num), (") ", .fg), ("return", .kw), (" n;", .fg)],
            [("  ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(n - ", .fg), ("1", .num),
             (") + ", .fg), (name.0, .fn), ("(n - ", .fg), ("2", .num), (");", .fg)],
            [("}", .fg)],
        ]
        case 2: return [ // Python
            [("# fibonacci", .cmt)],
            [("name", .fg), (" = ", .fg), ("\"" + name.0 + "\"", .str)],
            [("def", .kw), (" ", .fg), (name.0, .fn), ("(n):", .fg)],
            [("    ", .fg), ("if", .kw), (" n < ", .fg), ("2", .num), (": ", .fg), ("return", .kw), (" n", .fg)],
            [("    ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(n - ", .fg), ("1", .num),
             (") + ", .fg), (name.0, .fn), ("(n - ", .fg), ("2", .num), (")", .fg)],
        ]
        case 3: return [ // Rust
            [("// fibonacci", .cmt)],
            [("let", .kw), (" name = ", .fg), ("\"" + name.0 + "\"", .str), (";", .fg)],
            [("fn", .kw), (" ", .fg), (name.0, .fn), ("(n: ", .fg), ("u32", .type), (") -> ", .fg), ("u32", .type), (" {", .fg)],
            [("    ", .fg), ("if", .kw), (" n < ", .fg), ("2", .num), (" { n } ", .fg), ("else", .kw), (" {", .fg)],
            [("        ", .fg), (name.0, .fn), ("(n - ", .fg), ("1", .num),
             (") + ", .fg), (name.0, .fn), ("(n - ", .fg), ("2", .num), (")", .fg)],
            [("    }", .fg)],
        ]
        case 4: return [ // Go
            [("// fibonacci", .cmt)],
            [("name", .fg), (" := ", .fg), ("\"" + name.0 + "\"", .str)],
            [("func", .kw), (" ", .fg), (name.0, .fn), ("(n ", .fg), ("int", .type), (") ", .fg), ("int", .type), (" {", .fg)],
            [("    ", .fg), ("if", .kw), (" n < ", .fg), ("2", .num), (" { ", .fg), ("return", .kw), (" n }", .fg)],
            [("    ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(n-", .fg), ("1", .num),
             (") + ", .fg), (name.0, .fn), ("(n-", .fg), ("2", .num), (")", .fg)],
            [("}", .fg)],
        ]
        default: return [ // Java
            [("// fibonacci", .cmt)],
            [("String", .type), (" name = ", .fg), ("\"" + name.0 + "\"", .str), (";", .fg)],
            [("int ", .type), (name.0, .fn), ("(int n) {", .fg)],
            [("    ", .fg), ("if", .kw), (" (n < ", .fg), ("2", .num), (") ", .fg), ("return", .kw), (" n;", .fg)],
            [("    ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(n-", .fg), ("1", .num),
             (") + ", .fg), (name.0, .fn), ("(n-", .fg), ("2", .num), (");", .fg)],
            [("}", .fg)],
        ]
        }
    }

    private func drawTerminal(in screen: NSRect) {
        let r = resolvedRoles()
        guard let model else { return }
        let colors = model.finalColors.count == 16 ? model.finalColors : model.baseColors
        let cols = (0..<16).map { i in
            colors.indices.contains(i) ? nsColor(fromHex: colors[i]) : NSColor.black
        }
        let termBG = cols[0]
        let rect = terminalRect(in: screen)

        // the focus ring, outside the window, in the ring role
        if showRing {
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 10, yRadius: 10)
            r.ring.setStroke()
            ring.lineWidth = 2.5
            ring.stroke()
        }

        // the window: Ghostty's 0.85 background, so the wallpaper shows through
        // exactly as it does on the desktop
        let body = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        termBG.withAlphaComponent(CGFloat(toolOpacity ?? globalOpacity ?? terminalOpacity ?? 100) / 100).setFill()
        body.fill()
        cols[8].withAlphaComponent(0.6).setStroke()
        body.lineWidth = 1
        body.stroke()

        let font = nerdFont("Regular", 11)
        let bold = nerdFont("Bold", 11)
        let tabFont = nerdFont("Bold", 10)
        let lineH: CGFloat = 14
        let pad: CGFloat = 10
        let titleH: CGFloat = 18

        // title bar: traffic lights and the file name
        let dots = [cols[1], cols[3], cols[2]]
        for (i, dc) in dots.enumerated() {
            let cx = rect.minX + 12 + CGFloat(i) * 13
            dc.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - 4, y: rect.maxY - titleH / 2 - 4,
                                        width: 8, height: 8)).fill()
        }
        drawBaseline(Self.fileNames[selectedLanguage], bold, r.label,
                     x: rect.minX + 56, baseline: rect.maxY - titleH / 2 - bold.capHeight / 2)

        var y = rect.maxY - titleH - pad
        func drawLine(_ segs: [(String, NSColor)]) {
            var cx = rect.minX + pad
            for (s, c) in segs {
                drawBaseline(s, font, c, x: cx, baseline: y - font.ascender)
                cx += advance(s, font)
            }
            y -= lineH
        }

        // the Starship-like prompt
        if showPrompt {
            drawLine([("\u{f0ab} ", cols[2]), ("~/Projects/omacosy", cols[4]),
                      (" ", cols[7]), ("\u{e0b0} main", cols[3])])
            drawLine([("\u{f0da} ", cols[2]), ("bat ", cols[7]),
                      (Self.fileNames[selectedLanguage], cols[7])])
            drawLine([("# syntax preview, live from the palette", cols[8])])
            y -= 4
        }

        // the code sample, with short language tabs
        if showCode {
            tabRects.removeAll()
            var tx = rect.minX + pad
            for (i, label) in Self.languages.enumerated() {
                let w = advance(label, tabFont) + 12
                let tab = NSRect(x: tx, y: y - 15, width: w, height: 16)
                tabRects.append(tab)
                if i == selectedLanguage {
                    r.accent.setFill()
                    NSBezierPath(roundedRect: tab.insetBy(dx: 1, dy: 0), xRadius: 3, yRadius: 3).fill()
                    drawGlyph(label, tabFont, termBG, in: tab)
                } else {
                    drawGlyph(label, tabFont, r.muted, in: tab)
                }
                tx += w
            }
            y -= 22
            for line in sample(selectedLanguage) {
                drawLine(line.map { ($0.0, tokenColor($0.1, cols)) })
            }
        }
    }

    private var cachePath = ""
    private var cacheSide = 0
    private var cacheImage: CGImage?
    private var decoding = false
    private let decodeQueue = DispatchQueue(label: "omacosy.preview.decode", qos: .userInitiated)

    // the screen-shaped rect the wallpaper fills, centred in the pane so the
    // picture never stretches to the pane's own shape
    private func screenRect(in rect: NSRect) -> NSRect {
        var w = rect.width, h = w / Self.screenAspect
        if h > rect.height { h = rect.height; w = h * Self.screenAspect }
        return NSRect(x: rect.minX + (rect.width - w) / 2,
                      y: rect.minY + (rect.height - h) / 2,
                      width: w, height: h)
    }

    // The picture, aspect-filled into the screen rect. The edited render draws
    // here in place of the raw decode while a filter is active.
    private func drawWallpaper(_ cg: CGImage, in screen: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: screen).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let s = max(screen.width / iw, screen.height / ih)
        let dw = iw * s, dh = ih * s
        NSImage(cgImage: cg, size: NSSize(width: iw, height: ih))
            .draw(in: NSRect(x: screen.midX - dw / 2, y: screen.midY - dh / 2,
                             width: dw, height: dh))
        NSGraphicsContext.restoreGraphicsState()
    }

    // --- crop mode ------------------------------------------------------

    private func cropFit(_ cg: CGImage) -> NSRect {
        let pane = bounds.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: cg.width, height: cg.height)
        guard size.width > 0, size.height > 0 else { return pane }
        let s = min(pane.width / size.width, pane.height / size.height)
        let w = size.width * s, h = size.height * s
        return NSRect(x: pane.midX - w / 2, y: pane.midY - h / 2, width: w, height: h)
    }

    private func cropScreenRect(_ fit: NSRect) -> NSRect {
        let w = cropRect.width * fit.width
        let h = cropRect.height * fit.height
        let x = fit.minX + cropRect.minX * fit.width
        let y = fit.maxY - cropRect.minY * fit.height - h
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func cropFromScreen(_ p: NSPoint, _ fit: NSRect) -> CGPoint {
        CGPoint(x: (p.x - fit.minX) / fit.width, y: (fit.maxY - p.y) / fit.height)
    }

    private func drawCropOverlay(_ fit: NSRect) {
        let cr = cropScreenRect(fit)
        palette.barBG.withAlphaComponent(0.6).setFill()
        let outside = NSBezierPath(rect: fit)
        outside.append(NSBezierPath(rect: cr))
        outside.windingRule = .evenOdd
        outside.fill()
        palette.label.withAlphaComponent(0.25).setStroke()
        for i in 1..<3 {
            let x = cr.minX + cr.width * CGFloat(i) / 3
            let y = cr.minY + cr.height * CGFloat(i) / 3
            NSBezierPath.strokeLine(from: NSPoint(x: x, y: cr.minY), to: NSPoint(x: x, y: cr.maxY))
            NSBezierPath.strokeLine(from: NSPoint(x: cr.minX, y: y), to: NSPoint(x: cr.maxX, y: y))
        }
        palette.accent.setStroke()
        let border = NSBezierPath(rect: cr)
        border.lineWidth = 1.5
        border.stroke()
        palette.accent.setFill()
        for c in [NSPoint(x: cr.minX, y: cr.minY), NSPoint(x: cr.maxX, y: cr.minY),
                  NSPoint(x: cr.maxX, y: cr.maxY), NSPoint(x: cr.minX, y: cr.maxY)] {
            NSBezierPath(ovalIn: NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)).fill()
        }
    }

    func setCrop(_ rect: CGRect, aspect: CGFloat) {
        cropAspect = aspect
        cropRect = rect
    }

    private func cropHandleHit(_ p: NSPoint, _ cr: NSRect) -> Int {
        let r: CGFloat = 10
        let corners = [NSPoint(x: cr.minX, y: cr.minY), NSPoint(x: cr.maxX, y: cr.minY),
                       NSPoint(x: cr.maxX, y: cr.maxY), NSPoint(x: cr.minX, y: cr.maxY)]
        for (i, c) in corners.enumerated() where hypot(p.x - c.x, p.y - c.y) <= r { return i + 1 }
        return cr.contains(p) ? 0 : 5
    }

    private func updateCrop(_ drag: (mode: Int, start: NSPoint, orig: CGRect),
                            _ p: NSPoint, _ fit: NSRect) {
        var r = drag.orig
        let s = cropFromScreen(drag.start, fit)
        let e = cropFromScreen(p, fit)
        switch drag.mode {
        case 0:                                   // move
            r.origin.x = drag.orig.minX + (e.x - s.x)
            r.origin.y = drag.orig.minY + (e.y - s.y)
        case 1:                                   // top-left
            r.origin.x = min(drag.orig.maxX - 0.05, drag.orig.minX + (e.x - s.x))
            r.origin.y = min(drag.orig.maxY - 0.05, drag.orig.minY + (e.y - s.y))
            r.size.width = drag.orig.maxX - r.origin.x
            r.size.height = drag.orig.maxY - r.origin.y
        case 2:                                   // top-right
            r.origin.y = min(drag.orig.maxY - 0.05, drag.orig.minY + (e.y - s.y))
            r.size.width = max(0.05, drag.orig.width + (e.x - s.x))
            r.size.height = drag.orig.maxY - r.origin.y
        case 3:                                   // bottom-right
            r.size.width = max(0.05, drag.orig.width + (e.x - s.x))
            r.size.height = max(0.05, drag.orig.height + (e.y - s.y))
        case 4:                                   // bottom-left
            r.origin.x = min(drag.orig.maxX - 0.05, drag.orig.minX + (e.x - s.x))
            r.size.width = drag.orig.maxX - r.origin.x
            r.size.height = max(0.05, drag.orig.height + (e.y - s.y))
        default:                                  // a fresh rect
            r = CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                       width: abs(e.x - s.x), height: abs(e.y - s.y))
        }
        if cropAspect > 0 { r = constrainedCrop(r) }
        r = clampedCrop(r)
        cropRect = r
        onCropChange?(r)
    }

    private func clampedCrop(_ r: CGRect) -> CGRect {
        var out = r
        out.size.width = max(0.02, min(1, out.size.width))
        out.size.height = max(0.02, min(1, out.size.height))
        out.origin.x = max(0, min(1 - out.size.width, out.origin.x))
        out.origin.y = max(0, min(1 - out.size.height, out.origin.y))
        return out
    }

    // Keep the crop's pixel aspect at cropAspect: h = w * (imgW/imgH) / aspect.
    private func constrainedCrop(_ r: CGRect) -> CGRect {
        guard let cg = cacheImage, cg.height > 0, cropAspect > 0 else { return r }
        let imgAspect = CGFloat(cg.width) / CGFloat(cg.height)
        var out = r
        out.size.height = out.size.width * imgAspect / cropAspect
        if out.size.height > 1 { out.size.height = 1; out.size.width = cropAspect / imgAspect }
        out.origin.y = min(out.origin.y, 1 - out.size.height)
        out.origin.x = min(out.origin.x, 1 - out.size.width)
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        // A dark frame fills the whole column (Aether's preview panel) and the
        // wallpaper is centred inside it, so the picture never floats on the
        // card background and the frame edges line up with the column rules.
        NSColor.black.setFill()
        NSBezierPath(rect: bounds).fill()

        let path = model?.imagePath ?? ""
        let screen = self.screen
        if cropMode {
            // The whole picture, fit, with the crop rect over it.
            if screen.width > 1, !path.isEmpty { ensureImage(path: path, screen: screen) }
            if cachePath == path, let cg = cacheImage {
                let fit = cropFit(cg)
                NSGraphicsContext.current?.imageInterpolation = .high
                NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)).draw(in: fit)
                drawCropOverlay(fit)
            }
        } else if screen.width > 1, screen.height > 1, !path.isEmpty {
            ensureImage(path: path, screen: screen)
            let shown = showingOriginal ? cacheImage
                : (editedImage ?? (cachePath == path ? cacheImage : nil))
            if let cg = shown {
                drawWallpaper(cg, in: screen)
            } else {
                drawMidCenter("Loading preview…", nerdFont("Regular", 11), palette.muted,
                              centerX: screen.midX, midTop: bounds.height - screen.midY,
                              height: bounds.height)
            }
            if showMenuBar { drawMenuBar(in: screen) }
            if showTerminal { drawTerminal(in: screen) }
        }
        // the frame line, drawn on every edge so the panel reads as a frame
        palette.muted.withAlphaComponent(0.3).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if cropMode, cachePath == (model?.imagePath ?? ""), let cg = cacheImage {
            let fit = cropFit(cg)
            cropDrag = (cropHandleHit(p, cropScreenRect(fit)), p, cropRect)
            return
        }
        if showTerminal, showCode, let i = tabRects.firstIndex(where: { $0.contains(p) }) {
            if i != selectedLanguage { selectedLanguage = i; needsDisplay = true }
            return
        }
        if showTerminal, terminalRect(in: screen).contains(p) {
            dragging = true
            dragStart = p
            dragOrigin = termOrigin
            return
        }
        // press and hold anywhere else to compare with the original
        compareDrag = true
        showingOriginal = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let d = cropDrag, let cg = cacheImage {
            updateCrop(d, p, cropFit(cg))
            return
        }
        guard dragging else { return }
        let s = screen
        guard s.width > 0, s.height > 0 else { return }
        termOrigin.x = min(max(0, dragOrigin.x + (p.x - dragStart.x) / s.width),
                           max(0, 1 - termSize.width))
        termOrigin.y = min(max(0, dragOrigin.y + (p.y - dragStart.y) / s.height),
                           max(0, 1 - termSize.height))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if cropDrag != nil { cropDrag = nil; return }
        if compareDrag { compareDrag = false; showingOriginal = false; return }
        dragging = false
    }

    // Decode only when the picture or the needed pixel size changes; a size
    // change reuses the same path and re-decodes to the new cap.
    private func ensureImage(path: String, screen: NSRect) {
        let scale = window?.backingScaleFactor ?? 2
        let side = Int((max(screen.width, screen.height) * scale).rounded())
        if path == cachePath, side == cacheSide, cacheImage != nil { return }
        if path != cachePath || side != cacheSide {
            cachePath = path; cacheSide = side
        }
        guard !decoding else { return }
        decoding = true
        decodeQueue.async { [weak self] in
            let img = PreviewPaneView.decode(path: path, maxSide: side)
            DispatchQueue.main.async {
                guard let self else { return }
                self.decoding = false
                if self.cachePath == path, self.cacheSide == side { self.cacheImage = img }
                self.needsDisplay = true
            }
        }
    }

    private static func decode(path: String, maxSide: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(
            URL(fileURLWithPath: path) as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxSide),
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

// The centre column: the pinned preview on top, then the palette cards, the
// semantic colours and (Phase 6) the template overrides, which scroll.
final class PaletteCanvasView: NSView {
    var model: PaletteModel? { didSet { wire(); sync() } }

    private let preview = PreviewPaneView()
    private var previewH: CGFloat = 0
    private let scroll = NSScrollView()
    private let scroller = CustomScroller()
    private let doc = PaletteCanvasDoc()
    private let scrollerW: CGFloat = 8
    private let previewGap: CGFloat = 10

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(preview)
        addSubview(scroll)
        scroll.documentView = doc
        addSubview(scroller)
        scroller.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled() { scroller.refresh() }

    private func wire() {
        preview.model = model
        doc.colorCards.onEdit = { [weak self] target in self?.model?.selectForEdit(target) }
        doc.colorCards.onToggleLock = { [weak self] i in self?.model?.toggleLock(i) }
        doc.colorCards.onToggleSelect = { [weak self] i in self?.model?.toggleSelect(i) }
        doc.semantic.onEdit = { [weak self] target in self?.model?.selectForEdit(target) }
        doc.template.onSelectApp = { [weak self] i in self?.model?.selectTemplateApp(i) }
        doc.template.onEdit = { [weak self] app, key in
            self?.model?.selectForEdit(.override(app, key))
        }
        doc.template.onReset = { [weak self] in self?.model?.resetAppOverrides() }
        doc.template.onToolOpacity = { [weak self] v in self?.model?.setToolOpacity(v) }
    }

    func sync() {
        guard let model else { return }
        let finals = model.finalColors.count == 16 ? model.finalColors : model.baseColors
        doc.colorCards.cards = model.baseColors.enumerated().map { i, base in
            let label = PaletteModel.ansiLabels.indices.contains(i) ? PaletteModel.ansiLabels[i] : "\(i)"
            return PaletteCardsView.Card(label: label,
                                         hex: finals.indices.contains(i) ? finals[i] : base,
                                         index: i, extendedKey: nil)
        }
        doc.colorCards.locked = model.locked
        doc.colorCards.selected = model.selected
        doc.colorCards.editTarget = model.editTarget
        doc.colorCards.bgHex = finals.first ?? "#000000"
        doc.methodText = "· \(model.sourceLabel())"

        func base(_ i: Int) -> String { finals.indices.contains(i) ? finals[i] : "#000000" }
        func shade(_ key: String, _ fallback: Int) -> String {
            // a pinned shade shows its pin; otherwise the derived value
            model.extendedHex[key] ?? model.shades[key] ?? base(fallback)
        }
        func ext(_ key: String) -> String {
            model.finalExtended[key] ?? model.extendedHex[key] ?? "#000000"
        }
        doc.semantic.groups = [
            SemanticSectionView.Group(title: "Background", cards: [
                .init(label: "Darker", hex: shade("darker_bg", 0), key: "darker_bg"),
                .init(label: "Dark", hex: shade("dark_bg", 0), key: "dark_bg"),
                .init(label: "Base", hex: base(0), slot: 0),
                .init(label: "Lighter", hex: shade("lighter_bg", 0), key: "lighter_bg"),
            ]),
            SemanticSectionView.Group(title: "Foreground", cards: [
                .init(label: "Muted", hex: base(8), slot: 8),
                .init(label: "Dark", hex: shade("dark_fg", 7), key: "dark_fg"),
                .init(label: "Base", hex: base(7), slot: 7),
                .init(label: "Light", hex: shade("light_fg", 7), key: "light_fg"),
                .init(label: "Bright", hex: shade("bright_fg", 7), key: "bright_fg"),
            ]),
            SemanticSectionView.Group(title: "Accent", cards: [
                .init(label: "Orange", hex: shade("orange", 1), key: "orange"),
                .init(label: "Brown", hex: shade("brown", 1), key: "brown"),
            ]),
            SemanticSectionView.Group(title: "UI", cards: [
                .init(label: "Accent", hex: ext("accent"), key: "accent"),
                .init(label: "Cursor", hex: ext("cursor"), key: "cursor"),
                .init(label: "Sel FG", hex: ext("selection_foreground"), key: "selection_foreground"),
                .init(label: "Sel BG", hex: ext("selection_background"), key: "selection_background"),
            ]),
        ]
        doc.semantic.editTarget = model.editTarget
        doc.pinnedCount = model.pinnedShadeCount()
        doc.onResetPins = { [weak self] in self?.model?.clearShadePins() }

        // Template overrides: the app picker and the selected app's roles.
        doc.template.apps = model.templateApps.map { $0.name }
        doc.template.appIds = model.templateApps.map { $0.id }
        doc.template.selectedApp = model.selectedTemplateApp
        if model.templateApps.indices.contains(model.selectedTemplateApp) {
            let app = model.templateApps[model.selectedTemplateApp]
            doc.template.roles = app.roles.map { r in
                let override = model.templateOverride(app.id, r.key)
                return TemplateOverrideSectionView.Role(
                    key: r.key, label: r.label,
                    hex: override ?? model.templateDefault(r.source),
                    overridden: override != nil)
            }
            doc.template.canReset = model.hasTemplateOverride(app.id)
            doc.templateHeight = TemplateOverrideSectionView.height(roleCount: app.roles.count)
        } else {
            doc.template.roles = []
            doc.template.canReset = false
            doc.templateHeight = model.templateApps.isEmpty
                ? 0 : TemplateOverrideSectionView.height(roleCount: 0)
        }
        doc.template.editTarget = model.editTarget
        doc.template.toolOpacity = model.toolOpacity
        doc.template.globalOpacity = readGlobalToolOpacity()
        doc.template.terminalOpacity = readTerminalOpacity()
        preview.toolOpacity = model.toolOpacity
        preview.globalOpacity = readGlobalToolOpacity()
        preview.terminalOpacity = readTerminalOpacity()

        doc.needsDisplay = true
        preview.needsDisplay = true
        needsLayout = true
        needsDisplay = true
    }

    func refreshColors() {
        needsDisplay = true
        preview.needsDisplay = true
        markTree(doc)
    }

    // The wallpaper editor hands its edited render here; nil shows the raw
    // picture again. The central pane is the edit surface.
    func setEditedImage(_ cg: CGImage?) {
        preview.editedImage = cg
    }

    // The wallpaper editor's crop mode lives on the central preview.
    func setCropMode(_ on: Bool) { preview.cropMode = on }
    func setCrop(_ rect: CGRect, aspect: CGFloat) { preview.setCrop(rect, aspect: aspect) }
    func syncCrop(_ rect: CGRect) { preview.cropRect = rect }
    var onCropChange: ((CGRect) -> Void)? {
        get { preview.onCropChange }
        set { preview.onCropChange = newValue }
    }

    private func markTree(_ view: NSView) {
        view.needsDisplay = true
        for sub in view.subviews { markTree(sub) }
    }

    override func layout() {
        super.layout()
        // The preview is pinned: a palette edit is judged against the picture,
        // so it must stay visible while the palette below scrolls. Capped so
        // the palette always keeps a workable share of the column.
        let natural = bounds.width / PreviewPaneView.screenAspect
        previewH = max(120, min(natural, 360, bounds.height * 0.5))
        preview.frame = NSRect(x: 0, y: max(0, bounds.height - previewH),
                               width: bounds.width, height: previewH)
        let scrollH = max(0, bounds.height - previewH - previewGap)
        scroll.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - scrollerW - 14), height: scrollH)
        scroller.frame = NSRect(x: bounds.width - scrollerW, y: 0, width: scrollerW, height: scrollH)
        scroller.refresh()
        let w = scroll.contentSize.width
        let clipH = scroll.contentSize.height
        let targetH = max(doc.contentHeight(), clipH)
        if w > 0, (abs(doc.frame.width - w) > 0.5 || abs(doc.frame.height - targetH) > 0.5) {
            let first = doc.frame.width == 0
            let oldH = doc.frame.height
            doc.frame = NSRect(origin: .zero, size: NSSize(width: w, height: targetH))
            doc.needsLayout = true
            doc.layoutSubtreeIfNeeded()
            // same anchoring as the builder column: carry the origin by the
            // height delta so arriving content does not shift the view
            let clip = scroll.contentView
            let maxY = max(0, targetH - clipH)
            let cur = clip.bounds.origin.y
            let next = first ? maxY : min(maxY, max(0, cur + (targetH - oldH)))
            if abs(next - cur) > 0.5 {
                clip.scroll(to: NSPoint(x: 0, y: next))
                scroll.reflectScrolledClipView(clip)
            }
            scroller.refresh()
        }
    }
}

final class PaletteCanvasDoc: NSView {
    let colorCards = PaletteCardsView()
    let semantic = SemanticSectionView()
    let template = TemplateOverrideSectionView()
    var methodText = ""
    var pinnedCount = 0 { didSet { needsDisplay = true } }
    var templateHeight: CGFloat = 0 { didSet { needsDisplay = true } }
    var onResetPins: (() -> Void)?

    private let insetL: CGFloat = 16
    private let insetR: CGFloat = 14
    private var paletteTop: CGFloat = 0
    private var hintTop: CGFloat = 0
    private var semanticTop: CGFloat = 0
    private var templateTop: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        colorCards.showsLocks = true
        addSubview(colorCards)
        addSubview(semantic)
        addSubview(template)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private var contentW: CGFloat { max(0, bounds.width - insetL - insetR) }

    func contentHeight() -> CGFloat {
        var h: CGFloat = 12
        h += 26                                             // "Palette 16 colors · …"
        h += PaletteCardsView.height(for: 16)
        h += 36                                             // spaced hint line
        h += 26                                             // "Semantic Colors"
        h += SemanticSectionView.height()
        if templateHeight > 0 { h += 24 + templateHeight }
        h += 12
        return h
    }

    private func rect(top: CGFloat, h: CGFloat, x: CGFloat, w: CGFloat) -> NSRect {
        NSRect(x: x, y: bounds.height - top - h, width: w, height: h)
    }

    override func layout() {
        super.layout()
        var top: CGFloat = 12
        paletteTop = top
        top += 26
        colorCards.frame = rect(top: top, h: PaletteCardsView.height(for: 16), x: insetL, w: contentW)
        top += PaletteCardsView.height(for: 16)
        hintTop = top + 12
        top += 36
        semanticTop = top
        top += 26
        semantic.frame = rect(top: top, h: SemanticSectionView.height(), x: insetL, w: contentW)
        top += SemanticSectionView.height()
        if templateHeight > 0 {
            templateTop = top + 24
            template.frame = rect(top: templateTop, h: templateHeight, x: insetL, w: contentW)
        } else {
            template.frame = .zero
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        drawTopLeft("Palette", nerdFont("Bold", 13), palette.label,
                    x: insetL, top: paletteTop, height: h)
        drawTopLeft(methodText, nerdFont("Regular", 11), palette.muted,
                    x: insetL + 62, top: paletteTop + 2, height: h)
        drawTopLeft("Click to edit · Shift-click to select; the padlock survives a Method change.",
                    nerdFont("Regular", 10), palette.muted,
                    x: insetL, top: hintTop, height: h)
        drawTopLeft("Semantic Colors", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: semanticTop, height: h)
        drawTopLeft("Derived automatically. Click a shade to pin it.",
                    nerdFont("Regular", 10), palette.muted,
                    x: insetL + 118, top: semanticTop + 1, height: h)
        if pinnedCount > 0, let r = resetRect {
            drawTopLeft("Reset \(pinnedCount) pinned",
                        nerdFont("Regular", 11), .systemRed,
                        x: r.minX + 3, top: semanticTop + 1, height: h)
        }
    }

    // Aether's "Reset N pinned": clears every pinned shade back to auto.
    private var resetRect: NSRect? {
        guard pinnedCount > 0 else { return nil }
        let w = advance("Reset \(pinnedCount) pinned", nerdFont("Regular", 11)) + 8
        return NSRect(x: bounds.width - insetR - w, y: bounds.height - semanticTop - 18,
                      width: w, height: 18)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let r = resetRect, r.contains(p) {
            onResetPins?()
        }
    }
}

// --- editor footer ----------------------------------------------------------

// Save / Save As / Apply, and the one place unsaved changes are announced.
final class EditorFooterView: NSView {
    let saveButton = ButtonView()
    let saveAsButton = ButtonView()
    let applyButton = ButtonView()
    let importButton = ButtonView()
    let exportButton = ButtonView()
    var dirty = false { didSet { needsDisplay = true } }
    var message: (text: String, red: Bool)? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        saveAsButton.title = "Save As…"
        saveAsButton.secondary = true
        saveButton.title = "Save"
        applyButton.title = "Apply & Save"
        importButton.title = "Import"
        importButton.secondary = true
        importButton.busyTitle = "Importing…"
        exportButton.title = "Export"
        exportButton.secondary = true
        exportButton.busyTitle = "Exporting…"
        addSubview(importButton)
        addSubview(exportButton)
        addSubview(saveAsButton)
        addSubview(saveButton)
        addSubview(applyButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let margin: CGFloat = 16
        let w: CGFloat = 96, h: CGFloat = 24
        let y = (bounds.height - h) / 2
        applyButton.frame = NSRect(x: bounds.width - margin - w, y: y, width: w, height: h)
        saveButton.frame = NSRect(x: applyButton.frame.minX - 8 - w, y: y, width: w, height: h)
        saveAsButton.frame = NSRect(x: saveButton.frame.minX - 8 - w, y: y, width: w, height: h)
        // import/export are a separate pair: a wider gap sets the file group
        // apart from the save group
        exportButton.frame = NSRect(x: saveAsButton.frame.minX - 20 - w, y: y, width: w, height: h)
        importButton.frame = NSRect(x: exportButton.frame.minX - 8 - w, y: y, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        if let message {
            // the buttons sit on the right; keep the message clear of them
            let maxW = max(0, importButton.frame.minX - 16 - 10)
            drawMidLeft(truncate(message.text, nerdFont("Regular", 11), maxW),
                        nerdFont("Regular", 11),
                        message.red ? .systemRed : palette.muted,
                        x: 16, midTop: bounds.height / 2, height: bounds.height)
        } else if dirty {
            let dot = NSRect(x: 16, y: bounds.midY - 3, width: 6, height: 6)
            palette.accent.setFill()
            NSBezierPath(ovalIn: dot).fill()
            drawMidLeft("Unsaved changes", nerdFont("Regular", 11), palette.muted,
                        x: 28, midTop: bounds.height / 2, height: bounds.height)
        }
    }
}

final class ThemeEditorView: NSView, NSTextFieldDelegate {
    var onClose: (() -> Void)?
    var onNameEdit: (() -> Void)?
    var displayName = "" { didSet { needsDisplay = true } }
    var dirty = false { didSet { footer.dirty = dirty } }
    let nameField = NSTextField()
    let paletteBuilder = PaletteBuilderView()
    let paletteCanvas = PaletteCanvasView()
    let wallpaperEditor = EditorColumnView()
    let footer = EditorFooterView()
    private let penButton = ButtonView()

    private let headerH: CGFloat = 56
    private let footerH: CGFloat = 54
    private let leftW: CGFloat = 340    // wallpaper editor (step 1)
    private let rightW: CGFloat = 320   // palette builder (step 2)
    private let closeSize: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wallpaperEditor.stepBadge = 1
        paletteBuilder.stepBadge = 2
        nameField.isBezeled = false
        nameField.drawsBackground = true
        nameField.backgroundColor = palette.itemBG.withAlphaComponent(0.25)
        nameField.textColor = palette.label
        nameField.font = nerdFont("Bold", 14)
        nameField.focusRingType = .none
        nameField.usesSingleLineMode = true
        nameField.lineBreakMode = .byTruncatingTail
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(nameReturn)
        penButton.title = "\u{f040}"
        penButton.centeredByBounds = true
        penButton.fontSize = 12
        penButton.toolTip = "Rename Theme"
        penButton.onClick = { [weak self] in
            guard let self else { return }
            self.setPenOpen(!self.nameEditable)
        }
        addSubview(nameField)
        addSubview(penButton)
        addSubview(paletteBuilder)
        addSubview(paletteCanvas)
        addSubview(wallpaperEditor)
        addSubview(footer)
        // a click anywhere else ends the name edit — the app's custom views
        // never take first responder, so nothing else closes the field
        penMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, self.nameEditable else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                if !self.nameField.frame.contains(p), !self.penRect.contains(p) {
                    self.setPenOpen(false)
                }
                return event
            }
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { if let m = penMonitor { NSEvent.removeMonitor(m) } }

    var nameValue: String {
        nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func setName(_ name: String) { nameField.stringValue = name }

    @objc private func nameReturn() { window?.makeFirstResponder(self) }
    func controlTextDidChange(_ obj: Notification) { onNameEdit?() }
    func controlTextDidEndEditing(_ obj: Notification) { setPenOpen(false) }

    // a theme name is not prose: the field editor's red dotted spell
    // underline reads as a rendering bug in the header
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let editor = obj.userInfo?["NSFieldEditor"] as? NSTextView else { return }
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isGrammarCheckingEnabled = false
    }

    // -14 centres the cell-drawn text on the header's mid line — NSTextField
    // lays text out from the frame top, not on cap height. The pen and the
    // close ride this field's centre line, not the header's. The field's y
    // is the single source for that line: the three rects must stay a chain
    // (name → pen → close), never a cycle, or evaluating one recurses.
    private var nameTop: CGFloat { bounds.height - headerH / 2 - 14 }

    private var nameRect: NSRect {
        NSRect(x: 20, y: nameTop,
               width: max(120, penRect.minX - 14 - 20), height: 22)
    }

    private var closeRect: NSRect {
        NSRect(x: bounds.width - closeSize - 16, y: nameTop + 11 - closeSize / 2,
               width: closeSize, height: closeSize)
    }

    // the pen unlocks the name: the title reads as a label until asked for
    private var nameEditable = false
    private var penMonitor: Any?

    private var penRect: NSRect {
        NSRect(x: closeRect.minX - closeSize - 8, y: closeRect.minY,
               width: closeSize, height: closeSize)
    }

    private func setPenOpen(_ open: Bool) {
        guard nameEditable != open else { return }
        nameEditable = open
        if open {
            nameField.isEditable = true
            nameField.isSelectable = true
            nameField.backgroundColor = palette.itemBG.withAlphaComponent(0.5)
            window?.makeFirstResponder(nameField)
            // focus without selecting: a select-all highlight over the
            // label colour is unreadable — park the caret at the end
            if let editor = nameField.currentEditor() {
                let end = (nameField.stringValue as NSString).length
                editor.selectedRange = NSRange(location: end, length: 0)
            }
        } else {
            if let editor = nameField.currentEditor(), editor.window?.firstResponder === editor {
                window?.makeFirstResponder(nil)
            }
            nameField.isEditable = false
            nameField.isSelectable = false
            nameField.backgroundColor = palette.itemBG.withAlphaComponent(0.25)
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let h = max(0, bounds.height - headerH - footerH)
        // Step 1 (picture) on the left, step 2 (colours) on the right.
        wallpaperEditor.frame = NSRect(x: 0, y: footerH, width: leftW, height: h)
        paletteCanvas.frame = NSRect(x: leftW, y: footerH,
                                     width: max(0, bounds.width - leftW - rightW), height: h)
        paletteBuilder.frame = NSRect(x: bounds.width - rightW, y: footerH, width: rightW, height: h)
        footer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: footerH)
        // the name field is the whole title — no static prefix (the editor
        // is obvious from its contents)
        nameField.frame = nameRect
        penButton.frame = penRect
    }

    override func draw(_ dirtyRect: NSRect) {
        // the same card chrome as the dashboard: bar background, accent rim
        let corner = min(windowCornerRadius(10), min(bounds.width, bounds.height) / 2)
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: corner, yRadius: corner)
        palette.barBG.setFill()
        body.fill()
        palette.accent.setStroke()
        body.lineWidth = 1
        body.stroke()

        drawMidCenter("✕", nerdFont("Regular", 12), palette.muted,
                      centerX: closeRect.midX, midTop: bounds.height - nameRect.midY,
                      height: bounds.height)

        // column rules, drawn last so they sit on every surface
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bounds.height - headerH, width: bounds.width, height: 1).fill()
        let columnH = max(0, bounds.height - headerH - footerH)
        NSRect(x: leftW, y: footerH, width: 1, height: columnH).fill()
        NSRect(x: bounds.width - rightW, y: footerH, width: 1, height: columnH).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.contains(p) { onClose?() }
        else if nameField.frame.contains(p) { setPenOpen(true) }
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() }
    }
}

final class ThemeEditor {
    private static var current: ThemeEditor?

    let window: EditorWindow
    private let root: ThemeEditorView
    private let subject: EditorSubject
    private let model = PaletteModel()
    // the picture editor's own state and history, separate from the palette's
    private let editorState = EditorState()
    private let status: ((String) -> Void)?
    private var keyMonitor: Any?
    private var messageWork: DispatchWorkItem?
    // what the later panels read: the edition's stored record, or the
    // draft's Magic seed
    private(set) var record: [String: Any]?
    // set on any user change; Save/Apply clear it
    private(set) var dirty = false
    // The picture the editor renders from: the provenance source while it still
    // exists, so the stored recipe stays non-destructive; otherwise the
    // edition's own media (apply-only). `editSourceIsSource` records which.
    private var editSource = ""
    private var editSourceIsSource = true
    // wallpaper.blur: the desktop shows a heavy-blur variant while the editor
    // and the palette extraction keep the sharp image.
    private var blurOn = false
    // Which history ⌘Z / ⌘Y walk: the surface the user last edited (the
    // picture editor and the palette builder keep separate histories).
    private enum HistorySurface { case picture, palette }
    private var historySurface: HistorySurface = .palette
    // Apply to Palette's button fill while it renders, and the palette
    // generation captured when it started.
    private var applyProgressActive = false
    private var applyProgressTimer: Timer?
    private var applyProgressGeneration = -1
    private var applyProgressSafety: DispatchWorkItem?
    private var applyProgressStarted = Date.distantPast

    private init(subject: EditorSubject, size: NSSize, status: ((String) -> Void)?) {
        self.subject = subject
        self.status = status
        root = ThemeEditorView(frame: NSRect(origin: .zero, size: size))
        window = EditorWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        root.displayName = subject.displayName
        root.setName(subject.displayName)
        root.onClose = { [weak self] in self?.close() }
        root.onNameEdit = { [weak self] in
            guard let self else { return }
            self.dirty = true
            self.root.dirty = true
        }
        root.paletteBuilder.model = model
        root.paletteCanvas.model = model
        root.wallpaperEditor.state = editorState
        root.wallpaperEditor.onAuto = { [weak self] op in self?.runAuto(op) }
        root.wallpaperEditor.onCurve = { [weak self] points in
            self?.editorState.edit("curve") { $0.curvePoints = points }
        }
        root.wallpaperEditor.onCurveReset = { [weak self] in
            self?.editorState.edit("curve") { $0.curvePoints = [] }
        }
        root.wallpaperEditor.onGradeStops = { [weak self] stops in
            self?.editorState.edit("palette") { $0.paletteStops = stops }
        }
        root.wallpaperEditor.onPreset = { [weak self] name in
            self?.editorState.edit("preset:" + name) { f in
                if let preset = EditorPresets.all.first(where: { $0.name == name }) {
                    for (k, v) in preset.values { f[k] = v }
                }
            }
        }
        root.wallpaperEditor.onCropToggle = { [weak self] on in
            guard let self else { return }
            self.root.paletteCanvas.setCropMode(on)
            if on {
                let f = self.editorState.filters
                self.root.paletteCanvas.setCrop(CGRect(x: f.cropX, y: f.cropY,
                                                       width: f.cropW, height: f.cropH), aspect: 0)
            }
        }
        root.wallpaperEditor.onCropPreset = { [weak self] ratio in
            guard let self else { return }
            if ratio == 0 {
                self.root.paletteCanvas.setCrop(CGRect(x: 0, y: 0, width: 1, height: 1), aspect: 0)
                self.editorState.edit("crop") { $0.cropX = 0; $0.cropY = 0; $0.cropW = 1; $0.cropH = 1 }
                return
            }
            let size = self.editBase?.extent.size ?? CGSize(width: 1, height: 1)
            let rect = editorCropRect(ratio: ratio, imageSize: size)
            self.root.paletteCanvas.setCrop(rect, aspect: CGFloat(ratio))
            self.editorState.edit("crop") {
                $0.cropX = rect.minX; $0.cropY = rect.minY
                $0.cropW = rect.width; $0.cropH = rect.height
            }
        }
        root.wallpaperEditor.onCropReset = { [weak self] in
            guard let self else { return }
            self.editorState.edit(nil) { $0.cropX = 0; $0.cropY = 0; $0.cropW = 1; $0.cropH = 1 }
            self.root.paletteCanvas.setCrop(CGRect(x: 0, y: 0, width: 1, height: 1), aspect: 0)
        }
        root.paletteCanvas.onCropChange = { [weak self] r in
            self?.editorState.edit("crop") {
                $0.cropX = r.minX; $0.cropY = r.minY; $0.cropW = r.width; $0.cropH = r.height
            }
        }
        root.wallpaperEditor.onRotate = { [weak self] delta in
            self?.editorState.edit("rotate") {
                $0.rotate = ((($0.rotate + delta).truncatingRemainder(dividingBy: 360)) + 360)
                    .truncatingRemainder(dividingBy: 360)
            }
        }
        root.wallpaperEditor.onFlip = { [weak self] which in
            self?.editorState.edit("flip") {
                if which == "h" { $0.flipH.toggle() } else { $0.flipV.toggle() }
            }
        }
        root.wallpaperEditor.onResize = { [weak self] w, h in
            self?.editorState.edit("resize") { $0.resizeW = w; $0.resizeH = h }
        }
        root.wallpaperEditor.onTransformReset = { [weak self] in
            guard let self else { return }
            self.editorState.edit(nil) {
                $0.cropX = 0; $0.cropY = 0; $0.cropW = 1; $0.cropH = 1
                $0.rotate = 0; $0.flipH = false; $0.flipV = false
                $0.resizeW = 0; $0.resizeH = 0
            }
            self.root.paletteCanvas.setCrop(CGRect(x: 0, y: 0, width: 1, height: 1), aspect: 0)
        }
        root.wallpaperEditor.onApply = { [weak self] in self?.applyToPalette() }
        root.wallpaperEditor.onBlur = { [weak self] on in
            guard let self else { return }
            self.blurOn = on
            self.dirty = true
            self.root.dirty = true
            self.refreshEditedPreview()
        }
        editorState.onChange = { [weak self] in
            guard let self else { return }
            self.historySurface = .picture
            self.dirty = true
            self.root.dirty = true
            self.root.wallpaperEditor.syncFromState()
            let f = self.editorState.filters
            self.root.paletteCanvas.syncCrop(CGRect(x: f.cropX, y: f.cropY,
                                                    width: f.cropW, height: f.cropH))
            self.refreshEditedPreview()
        }
        model.onUpdate = { [weak self] in
            guard let self else { return }
            self.root.paletteBuilder.sync()
            self.root.paletteCanvas.sync()
            // the picture the central pane and the palette see (an edition's
            // media or a draft's wallpaper); decode it once for the edits
            self.loadEditBase()
            // the apply's fill ends when the palette has really regenerated
            if self.applyProgressActive, self.model.paletteGeneration != self.applyProgressGeneration {
                self.completeApplyProgress()
            }
        }
        model.onUserEdit = { [weak self] in
            guard let self else { return }
            self.historySurface = .palette
            self.dirty = true
            self.root.dirty = true
        }
        root.footer.saveButton.onClick = { [weak self] in self?.startSave(newID: false, action: .none) }
        root.footer.saveAsButton.onClick = { [weak self] in self?.startSaveAs() }
        root.footer.applyButton.onClick = { [weak self] in self?.startSave(newID: false, action: .apply) }
        root.footer.exportButton.onClick = { [weak self] in self?.startExport() }
        root.footer.importButton.onClick = { [weak self] in self?.startImport() }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
        // "Show Colors…" in the swatch popover opens the shared panel, and
        // the system resets its level to floating on every show — below the
        // editor card. Watch it and lift it back above on every appearance.
        Self.installPanelWatch()
    }

    // --- the central pane's edited preview ------------------------------

    private var editBasePath = ""
    private var editBase: CIImage?
    private var editBaseGeneration = 0
    private var editRenderWork: DispatchWorkItem?

    // Decode the subject's picture once when it changes; the central pane
    // draws the edited render on top of it while a filter is active.
    private func loadEditBase() {
        // The sharp provenance source when it still exists; the edition's media
        // otherwise. The palette's own extraction path is separate and may use
        // the media even when this does not.
        let path = editSource.isEmpty ? model.imagePath : editSource
        guard path != editBasePath else { return }
        editBasePath = path
        editBaseGeneration += 1
        let gen = editBaseGeneration
        editBase = nil
        root.paletteCanvas.setEditedImage(nil)
        root.wallpaperEditor.setHistogram([], [], [], [])
        guard !path.isEmpty else { return }
        DispatchQueue.global().async { [weak self] in
            let cg = editorSourceCGImage(URL(fileURLWithPath: path))
            let ci = cg.map { CIImage(cgImage: $0) }
            let hist = cg.map { editorHistograms(from: $0) }
            DispatchQueue.main.async {
                guard let self, self.editBaseGeneration == gen else { return }
                self.editBase = ci
                if let ci { self.root.wallpaperEditor.setOriginalSize(ci.extent.size) }
                if let hist {
                    self.root.wallpaperEditor.setHistogram(hist.lum, hist.r, hist.g, hist.b)
                }
                self.refreshEditedPreview()
            }
        }
    }

    // The histogram's one-click corrections: the engine computes them on the
    // source picture and returns a filter fragment (curve points, or the WB
    // temperature/tint).
    private func runAuto(_ op: String) {
        let path = model.imagePath
        guard !path.isEmpty else { return }
        let q = shellQuote(path)
        DispatchQueue.global().async { [weak self] in
            let command = "\(themecoreBin()) image auto \(op) \(q) --json 2>/dev/null"
            let (code, out) = shell(command)
            DispatchQueue.main.async {
                guard let self else { return }
                guard code == 0, let data = out.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    self.showMessage("Auto correction failed", red: true)
                    return
                }
                if op == "white-balance" {
                    let temp = (obj["temperature"] as? NSNumber)?.doubleValue ?? 0
                    let tint = (obj["tint"] as? NSNumber)?.doubleValue ?? 0
                    self.editorState.edit("white-balance") { $0.temperature = temp; $0.tint = tint }
                } else {
                    guard let rows = obj["curvePoints"] as? [[Any]] else { return }
                    var pts: [[Double]] = []
                    for row in rows where row.count == 2 {
                        if let x = (row[0] as? NSNumber)?.doubleValue,
                           let y = (row[1] as? NSNumber)?.doubleValue { pts.append([x, y]) }
                    }
                    guard !pts.isEmpty else { return }
                    self.editorState.edit("curve") { $0.curvePoints = pts }
                }
            }
        }
    }

    // 75 ms debounce, the same as the panel's own controls.
    private func refreshEditedPreview() {
        editRenderWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.renderEditedPreview() }
        editRenderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: work)
    }

    private func renderEditedPreview() {
        let filters = editorState.filters
        let blur = blurOn
        // The blurred variant is what the desktop will show, so it is what the
        // preview shows; the edit base and the palette extraction stay sharp.
        guard let base = editBase, !filters.isIdentity || blur else {
            root.paletteCanvas.setEditedImage(nil)
            return
        }
        let gen = editBaseGeneration
        DispatchQueue.global().async { [weak self] in
            var cg: CGImage?
            if filters.isIdentity {
                cg = editorBlurredPreview(base, maxSize: 1280)
            } else if blur {
                cg = editorPreviewRender(base, raw: filters, maxSize: 1280)
                    .flatMap { editorBlurredPreview(CIImage(cgImage: $0), maxSize: 1280) }
            } else {
                cg = editorPreviewRender(base, raw: filters, maxSize: 1280)
            }
            DispatchQueue.main.async {
                guard let self, self.editBaseGeneration == gen else { return }
                self.root.paletteCanvas.setEditedImage(cg)
            }
        }
    }

    // Renders the current edit at full resolution through the engine (the
    // record) into a content-addressed working file, then re-derives the
    // palette from it. The original picture is never written.
    private func applyToPalette() {
        let source = editSource.isEmpty ? model.imagePath : editSource
        let filters = editorState.filters
        guard !source.isEmpty else { return }
        guard !filters.isIdentity else {
            model.applyEditedSource(nil)
            showMessage("Palette back to the original", red: false)
            return
        }
        startApplyProgress()
        let generation = model.paletteGeneration
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            guard let out = self.renderWorkingImage(source: source, filters: filters) else {
                DispatchQueue.main.async {
                    self.completeApplyProgress()
                    self.showMessage("Apply to Palette failed", red: true)
                }
                return
            }
            DispatchQueue.main.async {
                self.model.applyEditedSource(out)
                // if the palette did not need regenerating, end the fill now;
                // otherwise the next model update ends it
                if self.model.paletteGeneration == generation {
                    self.completeApplyProgress()
                }
                self.showMessage("Palette updated from the edit", red: false)
            }
        }
    }

    // The button shows a bottom progress bar while the render runs; the fill
    // eases towards 92% (a render has no progress to report), then snaps to
    // 100% when the palette is really up to date.
    private func startApplyProgress() {
        stopApplyProgress()
        applyProgressActive = true
        applyProgressGeneration = model.paletteGeneration
        applyProgressStarted = Date()
        root.wallpaperEditor.setApplyProgress(0)
        var p: CGFloat = 0
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            p = min(0.92, p + (1 - p) * 0.14)
            self.root.wallpaperEditor.setApplyProgress(p)
        }
        RunLoop.main.add(timer, forMode: .common)
        applyProgressTimer = timer
        let safety = DispatchWorkItem { [weak self] in self?.completeApplyProgress() }
        applyProgressSafety = safety
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: safety)
    }

    private func stopApplyProgress() {
        applyProgressTimer?.invalidate()
        applyProgressTimer = nil
        applyProgressSafety?.cancel()
        applyProgressSafety = nil
    }

    private func completeApplyProgress() {
        applyProgressSafety?.cancel()
        applyProgressSafety = nil
        guard applyProgressActive else { return }
        applyProgressActive = false
        // a cache hit can finish in milliseconds: keep the bar moving long
        // enough that the click is always seen
        let remaining = max(0, 0.45 - Date().timeIntervalSince(applyProgressStarted))
        guard remaining > 0 else { finishApplyProgress(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, !self.applyProgressActive else { return }
            self.finishApplyProgress()
        }
    }

    private func finishApplyProgress() {
        stopApplyProgress()
        root.wallpaperEditor.setApplyProgress(1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.applyProgressActive else { return }
            self.root.wallpaperEditor.setApplyProgress(-1)
        }
    }

    // One pair of keys for both separate histories: act on the surface the
    // user last touched, and fall back to the other when it has nothing left.
    private func walkHistory(redo: Bool) {
        let pic = editorState
        let pal = model
        func pictureStep() -> Bool {
            if redo { guard pic.canRedo else { return false }; pic.redo() }
            else { guard pic.canUndo else { return false }; pic.undo() }
            return true
        }
        func paletteStep() -> Bool {
            if redo { guard pal.canRedo else { return false }; pal.redo() }
            else { guard pal.canUndo else { return false }; pal.undo() }
            return true
        }
        switch historySurface {
        case .picture: if !pictureStep() { _ = paletteStep() }
        case .palette: if !paletteStep() { _ = pictureStep() }
        }
    }

    // The one door to a full-resolution working render: content-addressed by
    // (source + recipe) under the scratch studio/edits directory, so the same
    // recipe is a cache hit and the original is never written. Returns nil on
    // any failure (the caller reports it).
    private func renderWorkingImage(source: String, filters: EditorFilters) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: filters.jsonObject()),
              let recipe = String(data: data, encoding: .utf8) else { return nil }
        let ext = (source as NSString).pathExtension.isEmpty
            ? "png" : (source as NSString).pathExtension.lowercased()
        let dir = HOME + "/.local/state/omacosy/studio/edits"
        let name = String(sha256Hex(source + "\n" + recipe).prefix(16))
        let out = dir + "/" + name + "." + ext
        if FileManager.default.fileExists(atPath: out) { return out }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cmd = "\(themecoreBin()) image render \(shellQuote(source)) "
            + "--filters \(shellQuote(recipe)) --out \(shellQuote(out))"
        let (code, _) = shell(cmd)
        guard code == 0, FileManager.default.fileExists(atPath: out) else { return nil }
        return out
    }

    private static var panelWatchInstalled = false

    private static func installPanelWatch() {
        let panel = NSColorPanel.shared
        let above = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.showsAlpha = false
        panel.level = above
        guard !panelWatchInstalled else { return }
        panelWatchInstalled = true
        let lift: (Notification) -> Void = { note in
            guard let p = note.object as? NSWindow, p.level != above else { return }
            p.level = above
            p.orderFrontRegardless()
        }
        for name: Notification.Name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didUpdateNotification,
        ] {
            NotificationCenter.default.addObserver(
                forName: name, object: panel, queue: .main, using: lift)
        }
        // like the swatch popover, the full panel dismisses on any click
        // outside it — in-app or in any other app
        let outside: (NSEvent) -> Void = { _ in
            if panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) {
                panel.orderOut(nil)
            }
        }
        NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { event in
                outside(event)
                return event
            }
        NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown], handler: outside)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil,
            queue: .main) { _ in
                if panel.isVisible { panel.orderOut(nil) }
            }
    }

    // The Edit pill's front door. A named variation opens its saved record;
    // a raw Wallpaper #N always starts a fresh draft seeded from its Magic
    // palette — Customize never replaces an existing variation.
    static func present(cell: ThemeCell, from host: NSWindow, status: ((String) -> Void)? = nil) {
        guard let dash = host as? DashboardWindow else { return }
        if let id = cell.editionID, let e = allEditions().first(where: { $0.id == id }) {
            openEditor(.edition(e), from: dash, status: status)
            return
        }
        openEditor(.draft(wallpaper: cell.wallpaper), from: dash, status: status)
    }

    private static func openEditor(_ subject: EditorSubject, from dash: DashboardWindow,
                                   status: ((String) -> Void)?) {
        current?.close()
        let screen = dash.screen ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = min(1280, frame.width - 80)
        let h = min(800, frame.height - 80)
        let editor = ThemeEditor(subject: subject, size: NSSize(width: w, height: h), status: status)
        current = editor
        editor.window.setFrameOrigin(NSPoint(x: frame.midX - w / 2, y: frame.midY - h / 2))
        // the editor owns the session: outside clicks and the toggle key
        // must not dismiss the dashboard until the editor is closed
        dash.hideSuppressed = true
        dash.addChildWindow(editor.window, ordered: .above)
        editor.show()
    }

    // a theme switch repaints the card; the editor draws with the same
    // global palette, so it must be marked dirty too
    static func refreshColors() {
        guard let e = current else { return }
        e.root.needsDisplay = true
        for v in e.root.subviews { v.needsDisplay = true }
        e.root.paletteBuilder.refreshColors()
        e.root.paletteCanvas.refreshColors()
        e.root.wallpaperEditor.refreshColors()
    }

    // Esc on the dashboard while the editor is up means "close the editor,
    // not the dashboard": a click on the card around the editor hands the
    // keyboard back to the dashboard, and Esc must still return to Themes
    @discardableResult
    static func closeIfOpen() -> Bool {
        guard let e = current else { return false }
        e.close()
        return true
    }

    // --- save / apply -------------------------------------------------------

    private enum SaveAction {
        case none
        case apply
        case export(String)   // the folder the user picked for the bundle
    }

    // `explicitName` is set when a NamePrompt card collected the name (Save As,
    // or Export of a draft); plain Save/Apply take the header field. `onFailure`
    // routes an error back to that card instead of the footer.
    private func startSave(newID: Bool, action: SaveAction, name explicitName: String? = nil,
                           onFailure: ((String) -> Void)? = nil) {
        let name = explicitName ?? root.nameValue
        guard !name.isEmpty else {
            if let onFailure { onFailure("Give the theme a name.") }
            else { showMessage("Give the theme a name.", red: true) }
            return
        }
        let base = saveBase(newID: newID)
        let source = editSource.isEmpty ? model.imagePath : editSource
        let filters = editorState.filters
        let hasEdits = editorState.hasEdits
        let usesSource = editSourceIsSource
        root.footer.saveButton.busy = true
        root.footer.saveAsButton.busy = true
        root.footer.message = nil
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            // The edition's own image always matches the current edit: the
            // render when a recipe is active, the source snapshot otherwise.
            var mediaFrom: String?
            var edited = false
            var renderError: String?
            if usesSource {
                if hasEdits {
                    if let render = self.renderWorkingImage(source: source, filters: filters) {
                        mediaFrom = render
                        edited = true
                    } else {
                        renderError = "Couldn't render the edit."
                    }
                } else if FileManager.default.fileExists(atPath: source) {
                    mediaFrom = source
                }
            }
            let (error, fresh) = renderError == nil
                ? self.runSave(base: base, name: name, newID: newID, mediaFrom: mediaFrom, edited: edited)
                : (renderError, nil)
            DispatchQueue.main.async {
                self.root.footer.saveButton.busy = false
                self.root.footer.saveAsButton.busy = false
                if let error {
                    if let onFailure { onFailure(error) } else { self.showMessage(error, red: true) }
                } else if let fresh {
                    self.didSave(fresh, action: action)
                }
            }
        }
    }

    // The record skeleton, built on the main thread so a save in flight
    // never reads the model while an edit is running.
    private func saveBase(newID: Bool) -> [String: Any] {
        var top: [String: Any]
        if let rec = record {
            top = rec
            if newID {
                top["schema"] = rec["schema"] ?? 1
                top["primary"] = rec["primary"] ?? true
                top.removeValue(forKey: "id")
                top.removeValue(forKey: "created")
                top.removeValue(forKey: "updated")
            }
        } else {
            top = ["schema": 1, "primary": true, "favorite": false,
                   "wallpaper": ["path": model.imagePath, "source": "local",
                                 "blur": false, "edited": false]]
        }
        // The wallpaper block carries the provenance path, the desktop blur
        // flag and the picture recipe. The media/edited pair is set by the
        // engine's --media-from capture, not here.
        var wall = top["wallpaper"] as? [String: Any] ?? [:]
        if wall["path"] == nil || newID {
            wall["path"] = editSourceIsSource ? editSource : model.imagePath
        }
        if wall["source"] == nil { wall["source"] = "local" }
        wall["blur"] = blurOn
        if editorState.hasEdits { wall["filters"] = editorState.filters.jsonObject() }
        else { wall.removeValue(forKey: "filters") }
        top["wallpaper"] = wall
        top["palette"] = palettePayload()
        if model.appOverrides.isEmpty {
            top.removeValue(forKey: "appOverrides")
        } else {
            top["appOverrides"] = model.appOverrides
        }
        if let op = model.toolOpacity {
            top["toolOpacity"] = op
        } else {
            top.removeValue(forKey: "toolOpacity")
        }
        return top
    }

    private func palettePayload() -> [String: Any] {
        // pins only: the four UI keys are always seeded, shade keys ride
        // along exactly when the user pinned them
        var extended: [String: String] = [:]
        for (key, hex) in model.extendedHex { extended[key] = hex }
        return ["method": model.method, "mode": model.mode, "resolvedMode": model.resolvedMode,
                "colors": model.baseColors, "extended": extended,
                "locked": model.locked.sorted(),
                "adjustments": model.adjustments.values, "curve": model.curve]
    }

    private func runSave(base: [String: Any], name: String, newID: Bool,
                         mediaFrom: String?, edited: Bool)
        -> (error: String?, record: [String: Any]?) {
        var top = base
        top["name"] = name
        let tmp = NSTemporaryDirectory()
            + "omacosy-editor-save-\(ProcessInfo.processInfo.processIdentifier).json"
        guard let data = try? JSONSerialization.data(withJSONObject: top, options: [.sortedKeys]),
              (try? data.write(to: URL(fileURLWithPath: tmp))) != nil else {
            return ("Couldn't prepare the theme file.", nil)
        }
        var extra = ""
        if let mediaFrom { extra += " --media-from \(shellQuote(mediaFrom))" }
        if edited { extra += " --edited" }
        let (code, out) = shell("\(themecoreBin()) theme save \(shellQuote(tmp)) --json\(extra) 2>&1")
        try? FileManager.default.removeItem(atPath: tmp)
        guard code == 0, let od = out.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: od)) as? [String: Any],
              let id = obj["id"] as? String else {
            if out.lowercased().contains("already exists") {
                return ("A theme named “\(name)” already exists. Choose another name.", nil)
            }
            return ("Couldn't save the theme. Try again.", nil)
        }
        let (sc, so) = shell("\(themecoreBin()) theme show \(shellQuote(id)) 2>/dev/null")
        if sc == 0, let fresh = (try? JSONSerialization.jsonObject(with: Data(so.utf8))) as? [String: Any] {
            return (nil, fresh)
        }
        var fallback = top
        fallback["id"] = id
        return (nil, fallback)
    }

    private func didSave(_ fresh: [String: Any], action: SaveAction) {
        // a naming card, if one asked, is done once the write succeeds
        NamePrompt.closeCurrent()
        record = fresh
        dirty = false
        root.dirty = false
        let name = fresh["name"] as? String ?? root.nameValue
        switch action {
        case .apply:
            if let id = fresh["id"] as? String { performApply(id: id, name: name) }
            else { finish(with: "Saved \(name)") }
        case .export(let parent):
            if let id = fresh["id"] as? String { performExport(id: id, into: parent) }
            else { showMessage("Export needs a saved theme.", red: true) }
        case .none:
            finish(with: "Saved \(name)")
        }
    }

    // a finished write hands the dashboard a line of status and steps out
    private func finish(with message: String) {
        let report = status
        close()
        report?(message)
    }

    private func showMessage(_ text: String, red: Bool, seconds: Double = 4) {
        messageWork?.cancel()
        root.footer.message = (text, red)
        let work = DispatchWorkItem { [weak self] in self?.root.footer.message = nil }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func performApply(id: String, name: String) {
        root.footer.applyButton.busy = true
        DispatchQueue.global().async { [weak self] in
            let json = HOME + "/.config/omacosy/themes/" + id + ".json"
            _ = shell("\(HOME)/.local/bin/omacosy-theme-switch set-theme \(shellQuote(json))")
            DispatchQueue.main.async {
                guard let self else { return }
                self.root.footer.applyButton.busy = false
                self.finish(with: "Applied \(name)")
            }
        }
    }

    // --- import / export ----------------------------------------------------

    private enum ImportMode { case ask, rename, replace }

    // Save As always makes a new theme, so it asks for the name in a card
    // rather than the header field (which would read as renaming the open one).
    private func startSaveAs() {
        NamePrompt.present(from: root,
                           title: "Save Theme As",
                           subtitle: "Give the new theme a name.",
                           confirmTitle: "Save As",
                           initial: suggestedNewName(),
                           onConfirm: { [weak self] name in
            self?.startSave(newID: true, action: .none, name: name,
                            onFailure: { NamePrompt.showError($0) })
        })
    }

    private func suggestedNewName() -> String {
        let base = root.nameValue.isEmpty ? "New Theme" : root.nameValue
        return record == nil ? base : base + " Copy"
    }

    // The engine exports a stored theme by id; the bundle lands in a new
    // folder named after the theme inside the folder the user picks.
    private func startExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "The bundle is written to a new folder named after the theme."
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            self.export(into: url.path)
        }
    }

    private func export(into parent: String) {
        if let id = record?["id"] as? String, !dirty {
            performExport(id: id, into: parent)
        } else if record == nil {
            // a draft must become a saved theme first; name it in a card, not
            // in the header
            NamePrompt.present(from: root,
                               title: "Export Theme",
                               subtitle: "Name the theme before exporting.",
                               confirmTitle: "Continue",
                               initial: root.nameValue.isEmpty ? "My Theme" : root.nameValue,
                               onConfirm: { [weak self] name in
                self?.startSave(newID: false, action: .export(parent), name: name,
                                onFailure: { NamePrompt.showError($0) })
            })
        } else {
            // an edited edition keeps its name and id
            startSave(newID: false, action: .export(parent))
        }
    }

    private func performExport(id: String, into parent: String) {
        root.footer.exportButton.busy = true
        root.footer.message = nil
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let dir = uniqueExportDir(in: parent, id: id)
            let (code, out) = shell("\(themecoreBin()) theme export \(shellQuote(id)) "
                + "--bundle \(shellQuote(dir)) --json 2>&1")
            DispatchQueue.main.async {
                self.root.footer.exportButton.busy = false
                guard code == 0 else {
                    self.showMessage("Export failed.", red: true, seconds: 6)
                    return
                }
                let path = firstJSONObject(in: out)?["bundle"] as? String ?? dir
                self.showMessage("Exported to \(path)", red: false, seconds: 8)
            }
        }
    }

    // Import reads our JSON, a flat colors.toml or a Base16 (YAML) scheme.
    // The engine refuses an id that already exists unless told which way to
    // go, so the first try asks, then Rename or Replace re-runs with its flag.
    private func startImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Omacosy JSON, a colors.toml or a Base16 (YAML) scheme."
        panel.allowedContentTypes = importContentTypes()
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            self.runImport(file: url.path, mode: .ask)
        }
    }

    private func runImport(file: String, mode: ImportMode, name: String? = nil) {
        root.footer.importButton.busy = true
        root.footer.message = nil
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            var flags = ""
            if let name { flags += " --name \(shellQuote(name))" }
            if mode == .rename { flags += " --rename" }
            if mode == .replace { flags += " --replace" }
            let (code, out) = shell("\(themecoreBin()) theme import \(shellQuote(file)) --json\(flags) 2>&1")
            DispatchQueue.main.async {
                self.root.footer.importButton.busy = false
                if code == 0, let obj = firstJSONObject(in: out) {
                    NamePrompt.closeCurrent()
                    let imported = obj["name"] as? String ?? "theme"
                    self.showMessage("Imported \(imported)", red: false)
                    return
                }
                if mode == .ask, out.lowercased().contains("already exists") {
                    self.confirmImport(file: file, existingID: quotedID(from: out))
                    return
                }
                self.showMessage(importErrorMessage(out), red: true, seconds: 6)
            }
        }
    }

    // The id collides: ask Rename or Replace. Rename collects the new name in
    // the same card Save As uses, so the copy does not share the old name and
    // the id the engine derives from it.
    private func confirmImport(file: String, existingID: String?) {
        ImportConflict.present(from: root.footer,
                               title: "Theme Already Exists",
                               subtitle: "A theme with this id is already saved. Keep both, or replace the saved one?",
                               onRename: { [weak self] in self?.promptImportName(file: file, existingID: existingID) },
                               onReplace: { [weak self] in self?.runImport(file: file, mode: .replace) })
    }

    private func promptImportName(file: String, existingID: String?) {
        var initial = "Imported Copy"
        if let existingID, !existingID.isEmpty {
            let (code, out) = shell("\(themecoreBin()) theme show \(shellQuote(existingID)) --json 2>/dev/null")
            if code == 0, let stored = firstJSONObject(in: out)?["name"] as? String, !stored.isEmpty {
                initial = stored + " Copy"
            }
        }
        NamePrompt.present(from: root,
                           title: "Rename Imported Theme",
                           subtitle: "Give the imported copy a name.",
                           confirmTitle: "Rename",
                           initial: initial,
                           onConfirm: { [weak self] name in
            self?.runImport(file: file, mode: .rename, name: name)
        })
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(root)
        // Esc, wherever focus sits in the editor; the dashboard's own
        // monitors ignore an Esc aimed at another window
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            // ⌘Z / ⌘Y (and ⇧⌘Z) walk the history of the surface last edited;
            // while a text field is editing, let the field keep its own undo
            if (e.keyCode == 6 || e.keyCode == 16), e.modifierFlags.contains(.command),
               !(self.window.firstResponder is NSTextView) {
                self.walkHistory(redo: e.keyCode == 16 || e.modifierFlags.contains(.shift))
                return nil
            }
            if e.keyCode == 53 {
                // Esc while the name is being edited ends that first
                if self.root.nameField.currentEditor() != nil {
                    self.root.window?.makeFirstResponder(self.root)
                    return nil
                }
                // Esc peels one layer at a time: selection, then the edited
                // colour, then the editor itself
                if self.model.clearSelection() { return nil }
                if self.model.clearEditTarget() { return nil }
                self.close()
                return nil
            }
            return e
        }
        loadSubject()
    }

    private func loadSubject() {
        switch subject {
        case .edition(let e):
            let q = shellQuote(e.id)
            DispatchQueue.global().async { [weak self] in
                let (code, out) = shell("\(themecoreBin()) theme show " + q + " 2>/dev/null")
                guard code == 0, let data = out.data(using: .utf8),
                      let rec = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                else { return }
                let (wc, wo) = shell("\(themecoreBin()) theme wallpaper " + q + " --json 2>/dev/null")
                var image = ""
                if wc == 0, let wd = wo.data(using: .utf8),
                   let wobj = (try? JSONSerialization.jsonObject(with: wd)) as? [String: Any] {
                    image = wobj["path"] as? String ?? ""
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.record = rec
                    if let name = rec["name"] as? String, !name.isEmpty { self.root.setName(name) }
                    let wall = rec["wallpaper"] as? [String: Any] ?? [:]
                    self.blurOn = (wall["blur"] as? Bool) ?? false
                    self.root.wallpaperEditor.setBlur(self.blurOn)
                    // Resume non-destructively from the provenance source while
                    // it still exists; otherwise the edition's own media
                    // (apply-only, no recipe).
                    var base = image
                    self.editSourceIsSource = false
                    if let p = wall["path"] as? String, !p.isEmpty {
                        let resolved = (p as NSString).expandingTildeInPath
                        if FileManager.default.fileExists(atPath: resolved) {
                            base = resolved
                            self.editSourceIsSource = true
                        }
                    }
                    self.editSource = base
                    if self.editSourceIsSource, let f = wall["filters"] as? [String: Any] {
                        self.editorState.restore(EditorFilters(json: f))
                    } else {
                        self.editorState.restore(EditorFilters())
                    }
                    guard !image.isEmpty else { return }
                    self.model.seedEdition(record: rec, image: image)
                    self.root.wallpaperEditor.syncFromState()
                }
            }
        case .draft(let wallpaper):
            // A fresh draft always edits the wallpaper itself, blurred or not.
            editSource = wallpaper
            editSourceIsSource = true
            blurOn = false
            root.wallpaperEditor.setBlur(false)
            editorState.restore(EditorFilters())
            let q = shellQuote(wallpaper)
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                // Fast path: the derived theme the Themes grid already shows.
                // Its 16 colours ARE the Magic palette (the Phase 2
                // cross-check pins them), and term-palette reads them in
                // milliseconds instead of a fresh extraction (~0.6 s on 4K).
                let (rc, rout) = shell("\(HOME)/.local/bin/omacosy-custom-theme theme --raw \(q) 2>/dev/null")
                let dir = rout.split(separator: "\n").last.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if rc == 0, !dir.isEmpty {
                    let envFile = NSTemporaryDirectory()
                        + "omacosy-editor-seed-\(ProcessInfo.processInfo.processIdentifier).env"
                    let (tc, _) = shell("\(HOME)/.local/bin/omacosy-term-palette \(shellQuote(dir)) \(shellQuote(envFile)) >/dev/null 2>&1")
                    var byIndex: [Int: String] = [:]
                    var accent: String? = nil
                    var resolved = "dark"
                    if tc == 0, let text = try? String(contentsOfFile: envFile, encoding: .utf8) {
                        for line in text.split(separator: "\n") {
                            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                            guard parts.count == 2 else { continue }
                            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                            if parts[0].hasPrefix("OMACOSY_P"), let i = Int(parts[0].dropFirst(9)) {
                                byIndex[i] = value
                            } else if parts[0] == "OMACOSY_ACCENT" {
                                accent = value
                            } else if parts[0] == "OMACOSY_IS_DARK" {
                                resolved = value == "1" ? "dark" : "light"
                            }
                        }
                    }
                    try? FileManager.default.removeItem(atPath: envFile)
                    let colors = (0..<16).compactMap { byIndex[$0] }
                    if colors.count == 16 {
                        DispatchQueue.main.async {
                            self.model.seedDraft(image: wallpaper, colors: colors,
                                                 accent: accent, resolved: resolved)
                        }
                        return
                    }
                }
                // Fallback: a fresh extraction; the two calls run in parallel.
                let lock = NSLock()
                var colors: [String] = []
                var roles: [String: Any] = [:]
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    let (c, o) = shell("\(themecoreBin()) palette magic \(q) --json 2>/dev/null")
                    if c == 0, let d = o.data(using: .utf8),
                       let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                        lock.lock(); colors = obj["colors"] as? [String] ?? []; lock.unlock()
                    }
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    let (c, o) = shell("\(themecoreBin()) palette magic \(q) --roles --json 2>/dev/null")
                    if c == 0, let d = o.data(using: .utf8),
                       let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                        lock.lock(); roles = obj; lock.unlock()
                    }
                    group.leave()
                }
                group.wait()
                lock.lock()
                let finalColors = colors
                let accent = roles["accent"] as? String
                let resolved = (roles["ladder"] as? String) == "light" ? "light" : "dark"
                lock.unlock()
                DispatchQueue.main.async {
                    guard finalColors.count == 16 else { return }
                    self.model.seedDraft(image: wallpaper, colors: finalColors,
                                         accent: accent, resolved: resolved)
                }
            }
        }
    }

    private func close() {
        guard ThemeEditor.current === self else { return }
        ThemeEditor.current = nil
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.orderOut(nil)
        model.teardown()
        if let dash = window.parent as? DashboardWindow {
            dash.hideSuppressed = false
            dash.removeChildWindow(window)
            NSApp.activate(ignoringOtherApps: true)
            dash.makeKeyAndOrderFront(nil)
            if let root = dash.contentView { dash.makeFirstResponder(root) }
        }
        window.orderOut(nil)
    }
}

// --- storage tab -----------------------------------------------------------

// where the local wallpapers folder is set and fed
final class StorageTabView: NSView {
    private let browseButton = ButtonView()
    private let addButton = ButtonView()
    private let chooseButton = ButtonView()
    private let cacheButton = ButtonView()
    private let cacheOpenButton = ButtonView()
    private var dir = ""
    private var status = ""
    // three buttons right-aligned as one group; every text button in the
    // dashboard shares one compact size (96×24, font 12 — the chips and
    // segmented controls' scale), the folder glyph keeps its icon width
    private let chooseW: CGFloat = 96
    private let addW: CGFloat = 96
    private let folderW: CGFloat = 26
    private let gap: CGFloat = 6

    func refreshColors() {
        browseButton.needsDisplay = true
        addButton.needsDisplay = true
        chooseButton.needsDisplay = true
        cacheButton.needsDisplay = true
        cacheOpenButton.needsDisplay = true
        needsDisplay = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        browseButton.title = "\u{f07b}"
        // an icon glyph, not text: centre it on its own box, not cap height
        browseButton.centeredByBounds = true
        browseButton.fontSize = 12
        browseButton.toolTip = "Open the Wallpaper Folder"
        browseButton.onClick = { [weak self] in
            guard let d = self?.dir, !d.isEmpty else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: d))
        }
        addButton.title = "Add Images"
        addButton.onClick = { [weak self] in self?.addFiles() }
        chooseButton.title = "Set Folder"
        chooseButton.toolTip = "Change the Wallpaper Folder"
        chooseButton.onClick = { [weak self] in self?.chooseDirectory() }
        cacheButton.title = "Clear Cache"
        cacheButton.toolTip = "Delete the cached thumbnails; they rebuild as you browse"
        cacheButton.onClick = { [weak self] in self?.clearCache() }
        cacheOpenButton.title = "\u{f07b}"
        cacheOpenButton.centeredByBounds = true
        cacheOpenButton.fontSize = 12
        cacheOpenButton.toolTip = "Open the Thumbnail Cache Folder"
        cacheOpenButton.onClick = {
            let d = whThumbsDir()
            try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
            NSWorkspace.shared.open(URL(fileURLWithPath: d))
        }
        addSubview(browseButton)
        addSubview(addButton)
        addSubview(chooseButton)
        addSubview(cacheButton)
        addSubview(cacheOpenButton)
        reload()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { reload() }
    }

    // the folder is the CLI's answer, so the path shown and the path
    // omacosy-custom-theme writes to can never disagree
    func reload() {
        dir = wallpapersDir()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let y = bounds.height - 28
        chooseButton.frame = NSRect(x: bounds.width - chooseW, y: y, width: chooseW, height: 24)
        addButton.frame = NSRect(x: chooseButton.frame.minX - gap - addW, y: y, width: addW, height: 24)
        browseButton.frame = NSRect(x: addButton.frame.minX - gap - folderW, y: y, width: folderW, height: 24)
        cacheButton.frame = NSRect(x: bounds.width - chooseW, y: y - 40, width: chooseW, height: 24)
        cacheOpenButton.frame = NSRect(x: cacheButton.frame.minX - gap - folderW, y: y - 40,
                                       width: folderW, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        // the Themes tab's Custom Themes header, verbatim: label, path and
        // the buttons centre on one line
        let mid = browseButton.frame.midY
        drawMidLeft("Local Wallpapers", nerdFont("Bold", 13), palette.accent,
                    x: 0, midTop: bounds.height - mid, height: bounds.height)
        let tw = advance("Local Wallpapers", nerdFont("Bold", 13)) + 14
        // the folder we ship with is marked, so it is clear the path was
        // set for the user and can be changed with Set Folder
        let marker = dir == HOME + "/Pictures/wallpapers" ? " (default)" : ""
        let markerW = marker.isEmpty ? 0 : advance(marker, nerdFont("Regular", 11))
        let pathW = max(80, browseButton.frame.minX - tw - 16 - markerW)
        drawMidLeft(truncate(dir, nerdFont("Regular", 11), pathW) + marker,
                    nerdFont("Regular", 11), palette.muted,
                    x: tw, midTop: bounds.height - mid, height: bounds.height)

        // row 2: the on-disk thumbnail cache, with its size and a flush
        let mid2 = cacheButton.frame.midY
        drawMidLeft("Thumbnail Cache", nerdFont("Bold", 13), palette.accent,
                    x: 0, midTop: bounds.height - mid2, height: bounds.height)
        let tw2 = advance("Thumbnail Cache", nerdFont("Bold", 13)) + 14
        drawMidLeft(cacheSummary(), nerdFont("Regular", 11), palette.muted,
                    x: tw2, midTop: bounds.height - mid2, height: bounds.height)

        if !status.isEmpty {
            drawTopLeft(truncate(status, nerdFont("Regular", 11), bounds.width),
                        nerdFont("Regular", 11), palette.muted,
                        x: 0, top: 84, height: bounds.height)
        }
    }

    // Both thumbnail shelves live under ~/.local/state/omacosy: the wallhaven
    // browse cache and the dashboard's decoded previews. Flushing clears the
    // pictures only; the wallpapers and bookmarks stay, and the thumbnails
    // rebuild as the tabs are opened again.
    private func cacheDirs() -> [String] {
        [whThumbsDir(), HOME + "/.local/state/omacosy/dashboard/thumbs"]
    }

    private func cacheSummary() -> String {
        let fm = FileManager.default
        var files = 0
        var bytes = 0
        for d in cacheDirs() {
            for e in (try? fm.contentsOfDirectory(atPath: d)) ?? [] {
                files += 1
                if let a = try? fm.attributesOfItem(atPath: d + "/" + e),
                   let s = a[.size] as? NSNumber { bytes += s.intValue }
            }
        }
        if files == 0 { return "empty" }
        return "\(files) files · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
    }

    private func clearCache() {
        let fm = FileManager.default
        var count = 0
        for d in cacheDirs() {
            for e in (try? fm.contentsOfDirectory(atPath: d)) ?? [] {
                if (try? fm.removeItem(atPath: d + "/" + e)) != nil { count += 1 }
            }
        }
        status = count == 0 ? "Cache already empty" : "Cleared \(count) cached thumbnails"
        needsDisplay = true
    }

    // Images picked from anywhere — a USB key, a NAS, another folder — are
    // copied into the configured folder (never moved), so they become the
    // next Wallpaper #N in Themes without extra steps.
    private func addFiles() {
        guard let dash = window as? DashboardWindow else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.allowedContentTypes = [.image]
        // as a sheet the panel can never fall behind the popUpMenu-level
        // dashboard card, which a runModal panel does
        dash.hideSuppressed = true
        panel.beginSheetModal(for: dash) { [weak self] resp in
            dash.hideSuppressed = false
            guard let self, resp == .OK else { return }
            let sources = panel.urls.map { $0.path }
            guard !sources.isEmpty else { return }
            self.status = "Adding…"
            self.needsDisplay = true
            let dest = self.dir
            DispatchQueue.global().async {
                var added = 0, skipped = 0, failed = 0
                for s in sources {
                    switch importWallpaper(s, into: dest) {
                    case .added: added += 1
                    case .skipped: skipped += 1
                    case .failed: failed += 1
                    }
                }
                DispatchQueue.main.async {
                    var parts: [String] = []
                    if added > 0 { parts.append("\(added) added") }
                    if skipped > 0 { parts.append("\(skipped) already in the folder") }
                    if failed > 0 { parts.append("\(failed) could not be copied") }
                    self.status = parts.joined(separator: ", ")
                    self.needsDisplay = true
                }
            }
        }
    }

    private func chooseDirectory() {
        guard let dash = window as? DashboardWindow else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        // as a sheet the panel can never fall behind the popUpMenu-level
        // dashboard card, which a runModal panel does
        dash.hideSuppressed = true
        panel.beginSheetModal(for: dash) { [weak self] resp in
            dash.hideSuppressed = false
            guard resp == .OK, let url = panel.url else { return }
            _ = shell("\(HOME)/.local/bin/omacosy-custom-theme path \(shellQuote(url.path))")
            self?.reload()
        }
    }
}

// --- api keys tab ----------------------------------------------------------

final class APIKeysTabView: NSView, NSTextFieldDelegate {
    private let field = NSSecureTextField()
    private let plainField = NSTextField()
    private let eyeButton = ButtonView()
    private var revealed = false
    private var pendingSave: DispatchWorkItem?
    // matches the compact buttons, so the box and the eye line up
    private let boxH: CGFloat = 24
    // the field itself is only as tall as its text: AppKit draws the value
    // near the top of a taller field, which read as uncentred. The visible
    // box is drawn around it, the text can't drift.
    private let fieldH: CGFloat = 16
    private var status = ""

    func refreshColors() {
        field.textColor = palette.label
        field.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
        plainField.textColor = palette.label
        plainField.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
        eyeButton.needsDisplay = true
        needsDisplay = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for f in [field, plainField] {
            f.isBezeled = false
            f.drawsBackground = true
            f.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
            f.textColor = palette.label
            f.font = nerdFont("Regular", 12)
            f.focusRingType = .none
            f.delegate = self
            f.target = self
            f.action = #selector(persistNow)
            addSubview(f)
        }
        plainField.isHidden = true
        eyeButton.title = "\u{f070}"
        eyeButton.centeredByBounds = true
        eyeButton.fontSize = 12
        eyeButton.toolTip = "Show the Key"
        eyeButton.onClick = { [weak self] in self?.toggleReveal() }
        addSubview(eyeButton)
        let key = readSecret("wallhaven")
        field.stringValue = key
        plainField.stringValue = key
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // the native placeholder sat high in the taller field; this draws it on
    // the same mid line as the value so an empty field reads centred
    func controlTextDidChange(_ obj: Notification) {
        if let src = obj.object as? NSTextField {
            let other: NSTextField = src === field ? plainField : field
            if other.stringValue != src.stringValue { other.stringValue = src.stringValue }
        }
        scheduleSave()
        needsDisplay = true
    }

    private var activeField: NSTextField { revealed ? plainField : field }

    // one field is always hidden; the eye swaps which, keeping the text
    private func toggleReveal() {
        revealed.toggle()
        let value = activeField.stringValue
        field.stringValue = value
        plainField.stringValue = value
        field.isHidden = revealed
        plainField.isHidden = !revealed
        eyeButton.title = revealed ? "\u{f06e}" : "\u{f070}"
        eyeButton.toolTip = revealed ? "Hide the Key" : "Show the Key"
        window?.makeFirstResponder(activeField)
        if let editor = activeField.currentEditor() {
            editor.selectedRange = NSRange(location: (value as NSString).length, length: 0)
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let w = min(420, max(160, bounds.width - 60))
        let boxY = bounds.height - 52 - boxH
        field.frame = NSRect(x: 0, y: boxY + (boxH - fieldH) / 2, width: w, height: fieldH)
        plainField.frame = field.frame
        eyeButton.frame = NSRect(x: w + 12, y: boxY, width: 26, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawTopLeft("Wallhaven.cc API Key", nerdFont("Bold", 13), palette.accent,
                    x: 0, top: 0, height: bounds.height)
        drawTopLeft(truncate("Optional: Create an account and go to https://wallhaven.cc/settings/account to get your API Key. Needed for NSFW content.",
                             nerdFont("Regular", 11), bounds.width),
                    nerdFont("Regular", 11), palette.muted, x: 0, top: 22, height: bounds.height)
        let box = NSRect(x: field.frame.minX - 0.5,
                         y: field.frame.minY - (boxH - fieldH) / 2 - 0.5,
                         width: field.frame.width + 1, height: boxH + 1)
        let border = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        palette.muted.withAlphaComponent(0.35).setStroke()
        border.lineWidth = 1
        border.stroke()
        if field.stringValue.isEmpty {
            drawMidLeft("Paste your key", nerdFont("Regular", 12), palette.muted,
                        x: field.frame.minX + 6,
                        midTop: bounds.height - field.frame.midY, height: bounds.height)
        }
        if !status.isEmpty {
            drawTopLeft(status, nerdFont("Regular", 11), palette.muted,
                        x: 0, top: 90, height: bounds.height)
        }
    }

    // the key saves itself; a failed write is the only thing worth saying
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistKey() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    @objc private func persistNow() { pendingSave?.cancel(); persistKey() }

    private func persistKey() {
        let value = field.stringValue.replacingOccurrences(of: "\n", with: "")
        if writeSecret("wallhaven", value) {
            field.stringValue = value
            plainField.stringValue = value
            status = ""
        } else {
            status = "Could not save the key"
        }
        needsDisplay = true
    }
}

// --- update tab ------------------------------------------------------------

final class UpdateTabView: NSView {
    private var stateText = "Checking for updates…"
    private var detail = ""
    private var warning = "Installing an update reloads Omacosy for a short moment."
    private let lineH: CGFloat = 24
    private var hasUpdate = false
    private var busy = false
    private var upToDate = false
    private let installButton = ButtonView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installButton.title = "Install Update"
        installButton.onClick = { [weak self] in self?.install() }
        installButton.isHidden = true
        addSubview(installButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    func refreshColors() { needsDisplay = true; installButton.needsDisplay = true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // check whenever the tab is shown, unless one is already running
        if window != nil, !busy { check() }
    }

    // the update script prints ANSI-coloured "==> ..." messages and an
    // indented list of commits. Keep the one line a reader can use: strip the
    // colour, strip a leading "==> ", drop the chatter, and take what is left
    // (the newest commit subject on an update, the reason on a failure).
    private func infoLine(_ s: String) -> String {
        let noANSI = s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]",
                                            with: "", options: .regularExpression)
        return noANSI.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("==>") ? String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("checking for updates") && !$0.hasPrefix("already up to date")
                      && !$0.hasPrefix("run without --check") && !$0.hasPrefix("pulling") }
            .last ?? ""
    }

    private func check() {
        stateText = "Checking for updates…"
        detail = ""
        hasUpdate = false
        upToDate = false
        installButton.isHidden = true
        needsDisplay = true
        DispatchQueue.global().async { [weak self] in
            let (code, out) = shell("\(HOME)/.local/bin/omacosy-update --check 2>&1")
            DispatchQueue.main.async {
                guard let self else { return }
                if code != 0 {
                    self.stateText = "Could not check for updates"
                    self.detail = self.infoLine(out)
                    self.hasUpdate = false
                } else if out.contains("new commit") {
                    self.stateText = "Update available"
                    self.detail = self.infoLine(out)
                    self.hasUpdate = true
                } else {
                    self.stateText = "Omacosy is up to date"
                    self.detail = self.infoLine(out)
                    self.upToDate = true
                }
                self.installButton.isHidden = !self.hasUpdate
                self.needsLayout = true
                self.needsDisplay = true
            }
        }
    }

    private func install() {
        busy = true
        hasUpdate = false
        upToDate = false
        installButton.isHidden = true
        stateText = "Updating…"
        detail = "Omacosy will reload in a moment; the window may flicker."
        needsDisplay = true
        DispatchQueue.global().async { [weak self] in
            let (code, out) = shell("\(HOME)/.local/bin/omacosy-update 2>&1")
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if code != 0 {
                    self.stateText = "Update failed"
                    self.detail = self.infoLine(out)
                } else {
                    self.stateText = "Updated"
                    self.detail = ""
                }
                self.installButton.isHidden = true
                self.needsLayout = true
                self.needsDisplay = true
            }
        }
    }

    // the visible lines, top to bottom; the button (when shown) sits above
    // them. Kept in one place so layout and draw agree on the block height.
    private func stackLines() -> [(String, NSFont, NSColor)] {
        var lines: [(String, NSFont, NSColor)] = [
            (stateText, nerdFont("Bold", 15), palette.accent)
        ]
        if !detail.isEmpty {
            lines.append((truncate(detail, nerdFont("Regular", 11), bounds.width - 40),
                          nerdFont("Regular", 11), palette.muted))
        }
        if hasUpdate {
            lines.append((warning, nerdFont("Regular", 11), palette.muted))
        } else if upToDate {
            lines.append(("Checked against the origin of this clone.",
                          nerdFont("Regular", 11), palette.muted))
        }
        return lines
    }

    private func blockHeight() -> CGFloat {
        CGFloat(stackLines().count) * lineH + (installButton.isHidden ? 0 : 24 + 14)
    }

    override func layout() {
        super.layout()
        var top = (bounds.height - blockHeight()) / 2
        if !installButton.isHidden {
            installButton.frame = NSRect(x: (bounds.width - 160) / 2,
                                         y: bounds.height - top - 24, width: 96, height: 24)
            top += 24 + 14
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        var top = (bounds.height - blockHeight()) / 2
        if !installButton.isHidden { top += 24 + 14 }
        for (text, font, color) in stackLines() {
            drawMidCenter(text, font, color, centerX: bounds.midX,
                          midTop: top + lineH / 2, height: bounds.height)
            top += lineH
        }
    }
}

// --- window / root ---------------------------------------------------------

final class DashboardWindow: NSWindow {
    // fires for every left click the window receives, before dispatch. Used
    // to fold an expanded workspace row back on a click anywhere else.
    var onMouseDown: ((NSEvent) -> Void)?
    // set while a system open panel is attached as a sheet: clicks in that
    // window must not be mistaken for a click outside the dashboard
    var hideSuppressed = false
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onMouseDown?(event) }
        super.sendEvent(event)
    }
}

protocol RefreshableTab: AnyObject {
    func refreshColors()
}

extension OptionsTabView: RefreshableTab {}
extension WorkspacesTabView: RefreshableTab {}
extension ThemesTabView: RefreshableTab {}
// --- wallhaven (Phase 7) ---------------------------------------------------
//
// The wallhaven.cc browsing logic, ported from Aether's internal/wallhaven
// package (github.com/omacom/aether, MIT) but kept in this file: install.sh
// builds one source file per binary, and the dashboard is the only caller.
// Everything here is Foundation-only and offline-testable; the UI lives in
// WallpapersTabView below.

enum WHError: Error, LocalizedError {
    case badURL(String)
    case insecure
    case privateHost
    case http(Int)
    case network(String)
    case decode
    case tooLarge
    case rateLimited(Double?)
    case noContent

    var errorDescription: String? {
        switch self {
        case .badURL(let m): return "That URL is not usable (\(m))."
        case .insecure: return "Only https:// links are allowed."
        case .privateHost: return "That host is not public."
        case .http(let c): return "Wallhaven answered \(c)."
        case .network(let m): return "Network problem: \(m)"
        case .decode: return "Wallhaven's reply could not be read."
        case .tooLarge: return "The file is larger than the allowed limit."
        case .rateLimited(let after):
            if let a = after { return "Wallhaven is rate-limiting. Try again in \(Int(a))s." }
            return "Wallhaven is rate-limiting. Try again shortly."
        case .noContent: return "That link has no image."
        }
    }
}

// --- URL guard -------------------------------------------------------------

// Rejects anything that is not a plain https link to a public host, so a
// crafted wallhaven reply (or a redirect) can never make the dashboard
// fetch http://, localhost, or a LAN address. This is the Swift port of
// Aether's ValidateRemoteURL plus its blocked-prefix table.
func whHost(_ raw: String) -> String? {
    guard let u = URLComponents(string: raw), let host = u.host else { return nil }
    var h = host.lowercased()
    if h.hasPrefix("["), h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
    if h.hasSuffix(".") { h.removeLast() }
    return h
}

func whParseIPv4(_ s: String) -> [UInt8]? {
    let parts = s.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    var out: [UInt8] = []
    for p in parts {
        guard !p.isEmpty, p.count <= 3, p.allSatisfy({ $0.isNumber }),
              let v = UInt8(p) else { return nil }
        out.append(v)
    }
    return out
}

func whParseIPv6(_ s: String) -> [UInt8]? {
    var addr = in6_addr()
    guard s.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 else { return nil }
    return withUnsafeBytes(of: &addr) { Array($0) }
}

func whIPv4IsPublic(_ b: [UInt8]) -> Bool {
    let (a, c, d) = (b[0], b[1], b[2])
    if a == 0 || a == 10 || a == 127 { return false }                    // this-network, private, loopback
    if a == 100 && (64...127).contains(c) { return false }               // CGNAT 100.64/10
    if a == 169 && c == 254 { return false }                             // link-local
    if a == 172 && (16...31).contains(c) { return false }                // private
    if a == 192 && c == 168 { return false }                             // private
    if a == 192 && c == 0 && (d == 0 || d == 2) { return false }         // 192.0.0/24, 192.0.2/24
    if a == 198 && (c == 18 || c == 19) { return false }                 // benchmarking 198.18/15
    if a == 198 && c == 51 && d == 100 { return false }                  // TEST-NET-2
    if a == 203 && c == 0 && d == 113 { return false }                   // TEST-NET-3
    if a >= 224 { return false }                                         // multicast + reserved
    return true
}

func whIPv6IsPublic(_ b: [UInt8]) -> Bool {
    if b.allSatisfy({ $0 == 0 }) { return false }                        // unspecified ::
    if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return false }  // loopback ::1
    if (b[0] & 0xfe) == 0xfc { return false }                            // unique-local fc00::/7
    if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return false }            // link-local fe80::/10
    if b[0] == 0xff { return false }                                     // multicast ff00::/8
    if b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8 { return false } // docs 2001:db8::/32
    return true
}

func validateWHURL(_ raw: String) throws {
    guard let u = URLComponents(string: raw), let scheme = u.scheme?.lowercased() else {
        throw WHError.badURL("invalid")
    }
    guard scheme == "https" else { throw WHError.insecure }
    guard let g = whHost(raw), !g.isEmpty else { throw WHError.badURL("no host") }
    if u.user != nil || u.password != nil { throw WHError.badURL("credentials are not allowed") }
    if g == "localhost" || g.hasSuffix(".localhost") || g.hasSuffix(".local") ||
       g.hasSuffix(".internal") || g == "home.arpa" || g.hasSuffix(".home.arpa") {
        throw WHError.privateHost
    }
    if let v4 = whParseIPv4(g), !whIPv4IsPublic(v4) { throw WHError.privateHost }
    if let v6 = whParseIPv6(g), !whIPv6IsPublic(v6) { throw WHError.privateHost }
}

// --- search types ----------------------------------------------------------

struct WHParams {
    var query = ""
    var categories = "111"
    var purity = "100"
    var sorting = "date_added"
    var order = "desc"
    var page = 1
    var atleast = ""
    var colors = ""
    var ratios = ""
}

struct WHWallpaper {
    let id: String
    let pageURL: String
    let imageURL: String
    let resolution: String
    let fileSize: Int64
    let category: String
    let purity: String
    let thumbs: [String: String]

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String,
              let path = json["path"] as? String, !path.isEmpty else { return nil }
        self.id = id
        self.imageURL = path
        self.pageURL = json["url"] as? String ?? "https://wallhaven.cc/w/\(id)"
        self.resolution = json["resolution"] as? String ?? ""
        self.fileSize = (json["file_size"] as? NSNumber)?.int64Value ?? 0
        self.category = json["category"] as? String ?? ""
        self.purity = json["purity"] as? String ?? ""
        self.thumbs = json["thumbs"] as? [String: String] ?? [:]
    }

    // The card shows the large thumb; the bookmark stores it so a restart
    // can redraw the grid without a search.
    var thumbURL: String { thumbs["large"] ?? thumbs["original"] ?? thumbs["small"] ?? "" }
    var smallThumbURL: String { thumbs["small"] ?? thumbURL }
}

struct WHMeta {
    var currentPage = 1
    var lastPage = 0
    var total = 0
}

struct WHResult {
    var data: [WHWallpaper]
    var meta: WHMeta
}

// --- filename sanitising ---------------------------------------------------

// The image basename, made safe to write: reserved path characters dropped,
// an extension forced, and a leading dot never allowed. A collision is
// resolved by the caller with a -2 suffix.
func whDownloadFilename(_ imageURL: String) -> String {
    guard let u = URL(string: imageURL) else { return "wallhaven.jpg" }
    let raw = (u.path as NSString).lastPathComponent
    var safe = ""
    for ch in raw.unicodeScalars {
        let v = ch.value
        if (48...57).contains(v) || (65...90).contains(v) || (97...122).contains(v) ||
           ch == "." || ch == "_" || ch == "-" {
            safe.unicodeScalars.append(ch)
        } else {
            safe.append("-")
        }
    }
    while safe.hasPrefix(".") || safe.hasPrefix("-") { safe.removeFirst() }
    if safe.isEmpty || !safe.contains(where: { $0.isLetter || $0.isNumber }) {
        safe = "wallhaven.jpg"
    }
    if (safe as NSString).pathExtension.isEmpty { safe += ".jpg" }
    return safe
}

// A free path in `dir` for `name`: the name itself, or name-2, name-3, …
func whUniquePath(_ dir: String, _ name: String) -> String {
    let fm = FileManager.default
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var dest = dir + "/" + name
    var n = 2
    while fm.fileExists(atPath: dest) {
        dest = dir + "/\(base)-\(n)" + (ext.isEmpty ? "" : ".\(ext)")
        n += 1
    }
    return dest
}

// --- search preferences + bookmarks ----------------------------------------

func whConfigPath() -> String { HOME + "/.config/omacosy/wallhaven.json" }
func whBookmarksPath() -> String { HOME + "/.config/omacosy/wallpaper-bookmarks.json" }
func whThumbsDir() -> String { HOME + "/.local/state/omacosy/studio/wallhaven-thumbs" }
func whDownloadsPath() -> String { HOME + "/.local/state/omacosy/studio/wallhaven-downloads.json" }

// Which wallhaven rating each downloaded file carried, keyed by the file's
// basename in the wallpaper folder. Written when a download lands, read to
// hide NSFW downloads (and editions built from them) when Hide NSFW is on.
// Nothing here is used to delete anything.
struct WHDownload {
    let id: String
    let purity: String
}

func whDownloadManifest() -> [String: WHDownload] {
    guard let data = FileManager.default.contents(atPath: whDownloadsPath()),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    var out: [String: WHDownload] = [:]
    for (name, v) in obj {
        guard let d = v as? [String: Any] else { continue }
        out[name] = WHDownload(id: d["id"] as? String ?? "",
                               purity: (d["purity"] as? String ?? "").lowercased())
    }
    return out
}

func whRecordDownload(_ basename: String, id: String, purity: String) {
    guard !basename.isEmpty else { return }
    var obj: [String: Any] = [:]
    if let data = FileManager.default.contents(atPath: whDownloadsPath()),
       let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        obj = existing
    }
    obj[basename] = ["id": id, "purity": purity.lowercased()]
    guard let data = try? JSONSerialization.data(withJSONObject: obj,
                                                 options: [.prettyPrinted, .sortedKeys]) else { return }
    let dir = (whDownloadsPath() as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? data.write(to: URL(fileURLWithPath: whDownloadsPath()), options: .atomic)
}

func whIsNSFWFile(_ basenameOrPath: String) -> Bool {
    whDownloadManifest()[(basenameOrPath as NSString).lastPathComponent]?.purity == "nsfw"
}

struct WHConfig {
    var categories = "111"
    var purity = "100"
    var sorting = "relevance"
    var order = "desc"
    var atleast = ""
    var colors = ""
    var ratios = ""
    var cardSize = "small"          // small | medium | large
    var bookmarkedOnly = false
    var hideNSFW = false

    static func load() -> WHConfig {
        var c = WHConfig()
        guard let data = FileManager.default.contents(atPath: whConfigPath()),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return c }
        if let v = obj["categories"] as? String, v.count == 3 { c.categories = v }
        if let v = obj["purity"] as? String, v.count == 3 { c.purity = v }
        if let v = obj["sorting"] as? String { c.sorting = v }
        if let v = obj["order"] as? String { c.order = v }
        if let v = obj["atleast"] as? String { c.atleast = v }
        if let v = obj["colors"] as? String { c.colors = v }
        if let v = obj["ratios"] as? String { c.ratios = v }
        if let v = obj["cardSize"] as? String, ["small", "medium", "large"].contains(v) {
            c.cardSize = v
        }
        if let v = obj["bookmarkedOnly"] as? Bool { c.bookmarkedOnly = v }
        if let v = obj["hideNSFW"] as? Bool { c.hideNSFW = v }
        return c
    }

    func save() {
        let obj: [String: Any] = ["categories": categories, "purity": purity,
                                  "sorting": sorting, "order": order, "atleast": atleast,
                                  "colors": colors, "ratios": ratios, "cardSize": cardSize,
                                  "bookmarkedOnly": bookmarkedOnly, "hideNSFW": hideNSFW]
        guard let data = try? JSONSerialization.data(withJSONObject: obj,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return }
        let dir = (whConfigPath() as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: whConfigPath()), options: .atomic)
    }
}

struct WHBookmark {
    let id: String
    var imageURL: String
    var pageURL: String
    var thumbURL: String
    var resolution: String
    var fileSize: Int64
    var purity: String
    var savedAt: Double
}

// Bookmarks live in one small JSON array keyed by wallhaven id. Kept in
// memory and rewritten atomically, so a restart shows a full grid from the
// Bookmarked filter without any network call.
final class WHBookmarkStore {
    private var byID: [String: WHBookmark] = [:]
    private let path: String

    init(path: String = whBookmarksPath()) {
        self.path = path
        load()
    }

    func isBookmarked(_ id: String) -> Bool { byID[id] != nil }
    var count: Int { byID.count }

    @discardableResult
    func toggle(_ w: WHWallpaper) -> Bool {
        if byID[w.id] != nil {
            byID[w.id] = nil
            save()
            return false
        }
        byID[w.id] = WHBookmark(id: w.id, imageURL: w.imageURL, pageURL: w.pageURL,
                                thumbURL: w.smallThumbURL, resolution: w.resolution,
                                fileSize: w.fileSize, purity: w.purity,
                                savedAt: Date().timeIntervalSince1970)
        save()
        return true
    }

    func all() -> [WHBookmark] {
        byID.values.sorted { $0.savedAt > $1.savedAt }
    }

    // Off-screen review only: seed in memory, never written to disk.
    func debugInsert(_ w: WHWallpaper) {
        byID[w.id] = WHBookmark(id: w.id, imageURL: w.imageURL, pageURL: w.pageURL,
                                thumbURL: w.smallThumbURL, resolution: w.resolution,
                                fileSize: w.fileSize, purity: w.purity,
                                savedAt: Date().timeIntervalSince1970)
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: path),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        for o in arr {
            guard let id = o["id"] as? String else { continue }
            byID[id] = WHBookmark(id: id,
                                  imageURL: o["imageURL"] as? String ?? "",
                                  pageURL: o["pageURL"] as? String ?? "",
                                  thumbURL: o["thumbURL"] as? String ?? "",
                                  resolution: o["resolution"] as? String ?? "",
                                  fileSize: (o["fileSize"] as? NSNumber)?.int64Value ?? 0,
                                  purity: o["purity"] as? String ?? "",
                                  savedAt: (o["savedAt"] as? NSNumber)?.doubleValue ?? 0)
        }
    }

    private func save() {
        let arr: [[String: Any]] = byID.values.map {
            ["id": $0.id, "imageURL": $0.imageURL, "pageURL": $0.pageURL,
             "thumbURL": $0.thumbURL, "resolution": $0.resolution,
             "fileSize": $0.fileSize, "purity": $0.purity, "savedAt": $0.savedAt]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return }
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

// --- HTTP client -----------------------------------------------------------

final class WHRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let s = request.url?.absoluteString, (try? validateWHURL(s)) != nil {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

// A small wallhaven.cc API client. Search and info hit api/v1 and are
// rate-limited; downloads and thumbnails are validated but not throttled
// (they are on the image CDN, not the API).
final class WallhavenClient {
    private let session: URLSession
    private let lock = NSLock()
    private var requestTimes: [Date] = []
    private var lockoutUntil: Date?
    private var backoff: TimeInterval = 0
    private let baseURL = "https://wallhaven.cc/api/v1"
    let anonymousPerMinute = 45
    let keyedPerMinute = 90

    var apiKey = "" {
        didSet { apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 300
        cfg.httpAdditionalHeaders = ["User-Agent": "Omacosy-Theme-Studio"]
        session = URLSession(configuration: cfg, delegate: WHRedirectGuard(), delegateQueue: nil)
    }

    // Returns 0 when a slot is free (and records it), or the seconds to wait.
    func reserveRequestSlot() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if let until = lockoutUntil, until > now { return until.timeIntervalSince(now) }
        requestTimes = requestTimes.filter { now.timeIntervalSince($0) < 60 }
        let cap = apiKey.isEmpty ? anonymousPerMinute : keyedPerMinute
        if requestTimes.count >= cap {
            return max(60 - now.timeIntervalSince(requestTimes[0]), 0.05)
        }
        requestTimes.append(now)
        return 0
    }

    private func throttle() {
        while true {
            let wait = reserveRequestSlot()
            if wait <= 0 { return }
            Thread.sleep(forTimeInterval: min(wait, 30))
        }
    }

    private func noteRateLimit(retryAfter: Double?) {
        lock.lock(); defer { lock.unlock() }
        backoff = backoff == 0 ? 60 : min(backoff * 2, 900)
        let wait = max(retryAfter ?? 0, backoff)
        lockoutUntil = Date().addingTimeInterval(wait)
    }

    private func noteSuccess() {
        lock.lock(); defer { lock.unlock() }
        backoff = 0
        lockoutUntil = nil
    }

    private func getJSON(_ urlString: String) throws -> [String: Any] {
        try validateWHURL(urlString)
        guard let url = URL(string: urlString) else { throw WHError.badURL("invalid") }
        throttle()
        let sem = DispatchSemaphore(value: 0)
        var outcome: Result<[String: Any], Error> = .failure(WHError.network("no response"))
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        let task = session.dataTask(with: req) { data, response, error in
            defer { sem.signal() }
            if let error = error { outcome = .failure(WHError.network(error.localizedDescription)); return }
            guard let http = response as? HTTPURLResponse else { outcome = .failure(WHError.network("no response")); return }
            if http.statusCode == 429 {
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
                outcome = .failure(WHError.rateLimited(retry)); return
            }
            guard http.statusCode == 200 else { outcome = .failure(WHError.http(http.statusCode)); return }
            guard let data = data else { outcome = .failure(WHError.noContent); return }
            guard data.count <= (4 << 20) else { outcome = .failure(WHError.tooLarge); return }
            do {
                let obj = try JSONSerialization.jsonObject(with: data)
                guard let dict = obj as? [String: Any] else { throw WHError.decode }
                outcome = .success(dict)
            } catch { outcome = .failure(WHError.decode) }
        }
        task.resume()
        sem.wait()
        switch outcome {
        case .success(let d): noteSuccess(); return d
        case .failure(let e):
            if case WHError.rateLimited(let r) = e { noteRateLimit(retryAfter: r) }
            throw e
        }
    }

    private func searchURL(_ p: WHParams) -> String {
        var comps = URLComponents(string: baseURL + "/search")!
        var items: [URLQueryItem] = []
        if !p.query.isEmpty { items.append(URLQueryItem(name: "q", value: p.query)) }
        items.append(URLQueryItem(name: "categories", value: p.categories.isEmpty ? "111" : p.categories))
        items.append(URLQueryItem(name: "purity", value: p.purity.isEmpty ? "100" : p.purity))
        items.append(URLQueryItem(name: "sorting", value: p.sorting.isEmpty ? "date_added" : p.sorting))
        items.append(URLQueryItem(name: "order", value: p.order.isEmpty ? "desc" : p.order))
        items.append(URLQueryItem(name: "page", value: String(max(p.page, 1))))
        if !p.atleast.isEmpty { items.append(URLQueryItem(name: "atleast", value: p.atleast)) }
        if !p.colors.isEmpty { items.append(URLQueryItem(name: "colors", value: p.colors)) }
        if !p.ratios.isEmpty { items.append(URLQueryItem(name: "ratios", value: p.ratios)) }
        if !apiKey.isEmpty { items.append(URLQueryItem(name: "apikey", value: apiKey)) }
        comps.queryItems = items
        return comps.url!.absoluteString
    }

    func search(_ params: WHParams) throws -> WHResult {
        let root = try getJSON(searchURL(params))
        let data = (root["data"] as? [[String: Any]]) ?? []
        let meta = root["meta"] as? [String: Any] ?? [:]
        return WHResult(
            data: data.compactMap { WHWallpaper(json: $0) },
            meta: WHMeta(currentPage: (meta["current_page"] as? NSNumber)?.intValue ?? 1,
                         lastPage: (meta["last_page"] as? NSNumber)?.intValue ?? 0,
                         total: (meta["total"] as? NSNumber)?.intValue ?? 0))
    }

    // Fetches several consecutive pages at once and merges them, exactly as
    // Aether does: page 0's failure aborts, later pages are skipped, and the
    // pagination metadata is normalised to logical (multi-page) numbering.
    func searchMultiPage(_ params: WHParams, numPages: Int) throws -> WHResult {
        if numPages <= 1 { return try search(params) }
        var results = [WHResult?](repeating: nil, count: numPages)
        var firstError: Error?
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "wallhaven.multipage", attributes: .concurrent)
        let gate = NSLock()
        for i in 0..<numPages {
            group.enter()
            queue.async {
                defer { group.leave() }
                var p = params
                p.page = params.page + i
                do {
                    let r = try self.search(p)
                    gate.lock(); results[i] = r; gate.unlock()
                } catch {
                    gate.lock(); if i == 0 { firstError = error }; gate.unlock()
                }
            }
        }
        group.wait()
        if let e = firstError { throw e }
        guard var merged = results[0] else { throw WHError.network("wallhaven search failed for first page") }
        for i in 1..<numPages { if let r = results[i] { merged.data.append(contentsOf: r.data) } }
        merged.meta.currentPage = (params.page - 1) / numPages + 1
        merged.meta.lastPage = (merged.meta.lastPage + numPages - 1) / numPages
        return merged
    }

    func info(_ id: String) throws -> WHWallpaper {
        guard id.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else {
            throw WHError.badURL("bad id")
        }
        var url = baseURL + "/w/" + id
        if !apiKey.isEmpty { url += "?apikey=" + (apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey) }
        let root = try getJSON(url)
        guard let d = root["data"] as? [String: Any], let w = WHWallpaper(json: d) else {
            throw WHError.decode
        }
        return w
    }
}

// Streams a remote file straight into its destination, writing a .part file
// beside it and renaming on success. Every byte lands in the destination
// directory; nothing is buffered whole in memory and no system temp file is
// used. Reports progress 0…1 on the main queue.
final class WHFileDownloader: NSObject, URLSessionDataDelegate {
    private let destPath: String
    private let partPath: String
    private let maxBytes: Int64
    private let onProgress: (Double) -> Void
    private let completion: (Result<String, Error>) -> Void
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var expected: Int64 = -1
    private var session: URLSession?
    private var finished = false

    init(destPath: String, maxBytes: Int64 = 50 << 20,
         onProgress: @escaping (Double) -> Void,
         completion: @escaping (Result<String, Error>) -> Void) {
        self.destPath = destPath
        self.partPath = destPath + ".part"
        self.maxBytes = maxBytes
        self.onProgress = onProgress
        self.completion = completion
    }

    func start(_ urlString: String) {
        do { try validateWHURL(urlString) } catch { finish(.failure(error)); return }
        guard let url = URL(string: urlString) else { finish(.failure(WHError.badURL("invalid"))); return }
        FileManager.default.createFile(atPath: partPath, contents: nil)
        handle = FileHandle(forWritingAtPath: partPath)
        guard handle != nil else { finish(.failure(WHError.network("cannot open the destination"))); return }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 600
        cfg.httpAdditionalHeaders = ["User-Agent": "Omacosy-Theme-Studio"]
        let q = OperationQueue(); q.maxConcurrentOperationCount = 1
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: q)
        session = s
        var req = URLRequest(url: url)
        req.timeoutInterval = 300
        s.dataTask(with: req).resume()
    }

    private func finish(_ result: Result<String, Error>) {
        if finished { return }
        finished = true
        try? handle?.close()
        handle = nil
        session?.invalidateAndCancel()
        session = nil
        switch result {
        case .success:
            do {
                try? FileManager.default.removeItem(atPath: destPath)
                try FileManager.default.moveItem(atPath: partPath, toPath: destPath)
                DispatchQueue.main.async { self.completion(.success(self.destPath)) }
            } catch {
                try? FileManager.default.removeItem(atPath: partPath)
                DispatchQueue.main.async { self.completion(.failure(WHError.network("could not save the file"))) }
            }
        case .failure(let e):
            try? FileManager.default.removeItem(atPath: partPath)
            DispatchQueue.main.async { self.completion(.failure(e)) }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            completionHandler(.cancel)
            finish(.failure(WHError.http((response as? HTTPURLResponse)?.statusCode ?? -1)))
            return
        }
        expected = response.expectedContentLength
        if expected > maxBytes {
            completionHandler(.cancel)
            finish(.failure(WHError.tooLarge))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received += Int64(data.count)
        if received > maxBytes {
            dataTask.cancel()
            finish(.failure(WHError.tooLarge))
            return
        }
        handle?.write(data)
        let frac = expected > 0 ? min(Double(received) / Double(expected), 1) : 0
        let report = onProgress
        DispatchQueue.main.async { report(frac) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            finish(.failure(WHError.network(error.localizedDescription)))
        } else {
            finish(.success(destPath))
        }
    }
}

// One download at a time from the tab's point of view: the client resolves
// the destination and hands back a downloader the caller keeps alive.
func whStartDownload(client: WallhavenClient, wallpaper: WHWallpaper, into dir: String,
                     onProgress: @escaping (Double) -> Void,
                     completion: @escaping (Result<String, Error>) -> Void) -> WHFileDownloader {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let dest = whUniquePath(dir, whDownloadFilename(wallpaper.imageURL))
    let d = WHFileDownloader(destPath: dest, onProgress: onProgress, completion: completion)
    d.start(wallpaper.imageURL)
    return d
}

// A thumbnail cache: studio/wallhaven-thumbs/<hash>.<ext>. Fetched with a
// plain data task (validated, not throttled — CDN) and written atomically.
func whThumbCachePath(_ url: String) -> String {
    let ext = (URL(string: url)?.pathExtension ?? "").lowercased()
    let e = (ext.count >= 2 && ext.count <= 5) ? ext : "jpg"
    return whThumbsDir() + "/" + stableHash(url) + "." + e
}

func whCachedThumb(_ url: String) -> NSImage? {
    guard !url.isEmpty else { return nil }
    return NSImage(contentsOfFile: whThumbCachePath(url))
}

func whFetchThumb(_ url: String, completion: @escaping (NSImage?) -> Void) {
    guard !url.isEmpty else { completion(nil); return }
    let cache = whThumbCachePath(url)
    if let img = NSImage(contentsOfFile: cache) { completion(img); return }
    guard (try? validateWHURL(url)) != nil, let u = URL(string: url) else { completion(nil); return }
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = 20
    cfg.timeoutIntervalForResource = 60
    let session = URLSession(configuration: cfg)
    session.dataTask(with: URLRequest(url: u)) { data, _, _ in
        defer { session.finishTasksAndInvalidate() }
        guard let data = data, data.count <= (5 << 20), let img = NSImage(data: data) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        try? FileManager.default.createDirectory(atPath: whThumbsDir(), withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: cache), options: .atomic)
        DispatchQueue.main.async { completion(img) }
    }.resume()
}

// --- wallpapers tab --------------------------------------------------------

// wallhaven.cc browsing lands here (Phase 7): search row, chips and the
// results grid. Local files are never previewed in this tab — they are
// sourced from the Storage tab and appear as Wallpaper #N in Themes.

let whSortLabels = ["Latest", "Relevance", "Random", "Views", "Favorites", "Top List"]
let whSortValues = ["date_added", "relevance", "random", "views", "favorites", "toplist"]
let whResLabels = ["Any Resolution", "1920×1080+", "2560×1440+", "3840×2160+"]
let whResValues = ["", "1920x1080", "2560x1440", "3840x2160"]
let whRatioLabels = ["Any Ratio", "16:9", "16:10", "4:3", "21:9", "9:16"]
let whRatioValues = ["", "16x9", "16x10", "4x3", "21x9", "9x16"]
let whColorPresets: [(hex: String, label: String)] = [
    ("660000", "Red"), ("cc6633", "Orange"), ("ffcc00", "Yellow"),
    ("006600", "Green"), ("336699", "Blue"), ("660066", "Purple"),
    ("000000", "Black"), ("cccccc", "Gray"), ("ffffff", "White"),
]

func whFormatSize(_ bytes: Int64) -> String {
    if bytes <= 0 { return "" }
    let mb = Double(bytes) / 1_048_576
    if mb >= 0.1 { return String(format: "%.1f MB", mb) }
    return String(format: "%.0f KB", Double(bytes) / 1024)
}

func whDrawThumb(_ img: NSImage, in rect: NSRect, radius: CGFloat) {    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    let imgA = img.size.width / max(img.size.height, 1)
    let rectA = rect.width / max(rect.height, 1)
    var src = NSRect(origin: .zero, size: img.size)
    if imgA > rectA {
        let w = img.size.height * rectA
        src = NSRect(x: (img.size.width - w) / 2, y: 0, width: w, height: img.size.height)
    } else {
        let h = img.size.width / rectA
        src = NSRect(x: 0, y: (img.size.height - h) / 2, width: img.size.width, height: h)
    }
    img.draw(in: rect, from: src, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

// The ink box of a string, from the font's own glyph metrics and advances.
// Context-independent, so it is reliable where CTLineGetImageBounds is not.
func whGlyphInkBounds(_ s: String, _ font: NSFont) -> CGRect {
    let ct = font as CTFont
    let chars = Array(s.utf16)
    guard !chars.isEmpty else { return .zero }
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    guard CTFontGetGlyphsForCharacters(ct, chars, &glyphs, chars.count) else { return .zero }
    var rects = [CGRect](repeating: .zero, count: glyphs.count)
    CTFontGetBoundingRectsForGlyphs(ct, .default, glyphs, &rects, glyphs.count)
    var advances = [CGSize](repeating: .zero, count: glyphs.count)
    CTFontGetAdvancesForGlyphs(ct, .default, glyphs, &advances, glyphs.count)
    var union = CGRect.null
    var x: CGFloat = 0
    for i in 0..<glyphs.count {
        var r = rects[i]
        r.origin.x += x
        union = union.union(r)
        x += advances[i].width
    }
    return union.isNull ? .zero : union
}

// Centres a glyph on the centre of its ink, so a square (checkbox), an arrow
// (download) and a bookmark all sit identically inside their pill.
func whDrawGlyphCentered(_ glyph: String, in r: NSRect, color: NSColor, size: CGFloat) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    let font = nerdFont("Regular", size)
    let line = textLine(glyph, font, color)
    let ink = whGlyphInkBounds(glyph, font)
    if ink.width > 0 && ink.height > 0 {
        ctx.textPosition = CGPoint(x: r.midX - ink.midX, y: r.midY - ink.midY)
    } else {
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        ctx.textPosition = CGPoint(x: r.midX - w / 2, y: r.midY - font.capHeight / 2)
    }
    CTLineDraw(line, ctx)
}

// A small dropdown in the house style: a rounded box that shows the current
// choice and pops a native menu. The menu runs its own tracking loop, so
// the dashboard's Esc/outside-click monitors never see its events.
final class WHDropdown: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var items: [String] = []
    var selectedIndex = 0 { didSet { needsDisplay = true } }
    var onPick: ((Int) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.35).setFill(); r.fill()
        palette.muted.withAlphaComponent(0.35).setStroke(); r.lineWidth = 1; r.stroke()
        let f = nerdFont("Regular", 11)
        drawMidLeft(truncate(title, f, bounds.width - 26), f, palette.label,
                    x: 9, midTop: bounds.height / 2, height: bounds.height)
        drawMidCenter("\u{f078}", nerdFont("Regular", 8), palette.muted,
                      centerX: bounds.width - 12, midTop: bounds.height / 2, height: bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)
        guard !items.isEmpty else { return }
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        for (i, it) in items.enumerated() {
            let mi = NSMenuItem(title: it, action: #selector(pickItem(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            mi.state = i == selectedIndex ? .on : .off
            menu.addItem(mi)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)
    }

    @objc private func pickItem(_ sender: NSMenuItem) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        onPick?(sender.tag)
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// The download indicator, in the bulk Download button's slot: a small round
// badge — a progress ring while a download runs, a green check when it
// lands, a red mark when it fails — with a short label beside it. Modern and
// quiet, unlike a full-width bar.
final class WHBadge: NSView {
    enum Style { case hidden, progress(Double), success, failure }

    var style: Style = .hidden {
        didSet {
            needsDisplay = true
            if case .hidden = style { isHidden = true } else { isHidden = false }
        }
    }
    var label = "" { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if case .hidden = style { return }
        let d: CGFloat = 24
        let circle = NSRect(x: 2, y: (bounds.height - d) / 2, width: d, height: d)
        switch style {
        case .hidden:
            return
        case .success, .failure:
            let success = { if case .success = style { return true }; return false }()
            (success ? NSColor.systemGreen : NSColor.systemRed).setFill()
            NSBezierPath(ovalIn: circle).fill()
            whDrawGlyphCentered(success ? "\u{f00c}" : "\u{f00d}", in: circle, color: .white, size: 12)
        case .progress(let frac):
            let track = NSBezierPath(ovalIn: circle)
            NSColor.white.withAlphaComponent(0.18).setStroke(); track.lineWidth = 3; track.stroke()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: circle.midX, y: circle.midY),
                          radius: d / 2 - 1.5, startAngle: 90,
                          endAngle: 90 - 360 * CGFloat(max(0.02, min(1, frac))), clockwise: true)
            NSColor.systemGreen.setStroke(); arc.lineWidth = 3; arc.lineCapStyle = .round; arc.stroke()
            whDrawGlyphCentered("\u{f019}", in: circle, color: palette.label, size: 10)
        }
        if !label.isEmpty {
            let f = nerdFont("Regular", 11)
            drawMidLeft(truncate(label, f, bounds.width - (circle.maxX + 10)), f, palette.label,
                        x: circle.maxX + 8, midTop: bounds.height / 2, height: bounds.height)
        }
    }

    override var acceptsFirstResponder: Bool { false }
}

// The scrolling results grid. Cards are laid out in columns whose width
// follows the S/M/L size; thumbnails are cached on disk and loaded only for
// the visible rows. All per-card state is keyed by wallhaven id, so a
// reload (or a bookmark-view swap) never mixes up a decoded image.
final class WHGridView: NSView {
    var cards: [WHWallpaper] = []
    var cardSize = "small"
    var thumbs: [String: NSImage] = [:]
    private var pending: Set<String> = []
    var selected: Set<String> = []
    var downloaded: Set<String> = []
    var downloading: [String: Double] = [:]
    var cellFrames: [Int: NSRect] = [:]
    // the scroll viewport height; the document is padded to at least this so
    // a short list (e.g. a handful of bookmarks) top-aligns instead of
    // sitting at the bottom of a non-flipped scroll view
    var minContentHeight: CGFloat = 0
    var hovered: Int? = nil
    private var hoverTracking: NSTrackingArea?

    var onBookmark: ((WHWallpaper) -> Void)?
    var onDownload: ((WHWallpaper) -> Void)?
    var onToggleSelect: ((WHWallpaper) -> Void)?

    private let gap: CGFloat = 12
    private let metaH: CGFloat = 24
    private let topPad: CGFloat = 2
    private let bottomPad: CGFloat = 16
    private let icon: CGFloat = 24
    private let iconPad: CGFloat = 8

    private func minColWidth() -> CGFloat {
        switch cardSize {
        case "large": return 500
        case "medium": return 340
        default: return 220
        }
    }

    func rebuild() {
        cellFrames.removeAll()
        let avail = bounds.width
        guard avail > 40 else { frame.size = NSSize(width: avail, height: 10); return }
        let minCol = minColWidth()
        let cols = max(1, Int((avail + gap) / (minCol + gap)))
        let cellW = (avail - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let thumbH = (cellW * 9 / 16).rounded()
        let cellH = thumbH + metaH
        let rows = max(1, (cards.count + cols - 1) / cols)
        let contentH = max(topPad + CGFloat(rows) * (cellH + gap) - gap + bottomPad, minContentHeight)
        var top = topPad
        var i = 0
        for _ in 0..<rows {
            for c in 0..<cols {
                if i >= cards.count { break }
                let x = CGFloat(c) * (cellW + gap)
                cellFrames[i] = NSRect(x: x, y: contentH - top - cellH, width: cellW, height: cellH)
                i += 1
            }
            top += cellH + gap
        }
        frame.size = NSSize(width: avail, height: contentH)
        needsDisplay = true
    }

    private func thumbRect(_ f: NSRect) -> NSRect {
        NSRect(x: f.minX, y: f.minY + metaH, width: f.width, height: f.height - metaH)
    }

    private func hotRects(_ f: NSRect) -> (bookmark: NSRect, check: NSRect, download: NSRect) {
        let t = thumbRect(f)
        let bookmark = NSRect(x: t.minX + iconPad, y: t.maxY - iconPad - icon, width: icon, height: icon)
        let check = NSRect(x: t.maxX - iconPad - icon, y: t.maxY - iconPad - icon, width: icon, height: icon)
        let download = NSRect(x: t.maxX - iconPad - icon, y: t.minY + iconPad, width: icon, height: icon)
        return (bookmark, check, download)
    }

    private func iconButton(_ glyph: String, in r: NSRect, tint: NSColor, fillAlpha: CGFloat) {
        let box = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        NSColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: fillAlpha).setFill()
        box.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke(); box.lineWidth = 1; box.stroke()
        whDrawGlyphCentered(glyph, in: r, color: tint, size: 12)
    }

    private func drawCard(_ i: Int, _ f: NSRect) {
        let w = cards[i]
        let t = thumbRect(f)
        let corner = min(windowCornerRadius(7), min(t.width, t.height) / 2)
        let thumb = NSBezierPath(roundedRect: t, xRadius: corner, yRadius: corner)

        // thumbnail: rounded, with the same ring treatment as the Themes tab
        if let img = thumbs[w.id] {
            whDrawThumb(img, in: t, radius: corner)
        } else {
            NSGraphicsContext.current?.saveGraphicsState()
            thumb.setClip()
            palette.itemBG.withAlphaComponent(0.5).setFill()
            t.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            drawMidCenter("loading…", nerdFont("Regular", 10), palette.muted,
                          centerX: t.midX, midTop: bounds.height - t.midY, height: bounds.height)
        }

        let isDownloaded = downloaded.contains(w.id)
        let isSelected = selected.contains(w.id)
        let isBookmarked = isBookmarkedCard(i)
        let showOverlays = (hovered == i) || isSelected || downloading[w.id] != nil

        // top and bottom scrim, a gradient like Aether's: dark under the top
        // icons, clear across the middle, dark under the bottom one
        if showOverlays {
            NSGraphicsContext.current?.saveGraphicsState()
            thumb.setClip()
            if let grad = NSGradient(colorsAndLocations:
                (NSColor.black.withAlphaComponent(0.42), 0.0),
                (NSColor.black.withAlphaComponent(0.0), 0.34),
                (NSColor.black.withAlphaComponent(0.0), 0.48),
                (NSColor.black.withAlphaComponent(0.72), 1.0)) {
                grad.draw(in: t, angle: 270)
            }
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        // bookmark: always shown once bookmarked, in the theme accent
        let r = hotRects(f)
        if isBookmarked || showOverlays {
            iconButton("\u{f02e}", in: r.bookmark, tint: isBookmarked ? palette.accent : .white, fillAlpha: 0.5)
        }
        if showOverlays {
            iconButton(isSelected ? "\u{f00c}" : "\u{f096}", in: r.check,
                       tint: isSelected ? palette.accent : .white, fillAlpha: 0.5)
            iconButton("\u{f019}", in: r.download, tint: .white, fillAlpha: 0.5)
        }

        if isDownloaded {
            let label = "  Added"
            let bf = nerdFont("Bold", 10)
            let pillW = advance(label, bf) + 30
            let pill = NSRect(x: t.minX + iconPad, y: t.minY + iconPad, width: pillW, height: 22)
            let p = NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6)
            NSColor.systemGreen.withAlphaComponent(0.9).setFill(); p.fill()
            whDrawGlyphCentered("\u{f00c}" + label, in: NSRect(x: pill.minX + 4, y: pill.minY,
                                                               width: pillW - 8, height: pill.height),
                                color: .white, size: 10)
        }

        if let frac = downloading[w.id] {
            let bar = NSRect(x: t.minX + 4, y: t.minY + 4, width: t.width - 8, height: 5)
            let bp = NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5)
            NSColor.white.withAlphaComponent(0.28).setFill(); bp.fill()
            let fill = NSRect(x: bar.minX, y: bar.minY, width: max(2, bar.width * CGFloat(frac)), height: bar.height)
            let fp = NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5)
            NSColor.systemGreen.setFill(); fp.fill()
        }

        // the ring: 1px muted, 2px accent on hover or selection
        thumb.lineWidth = 1
        palette.muted.withAlphaComponent(0.3).setStroke()
        thumb.stroke()
        if hovered == i || isSelected {
            thumb.lineWidth = 2
            palette.accent.setStroke()
            thumb.stroke()
        }

        // resolution + size below the thumbnail, dissociated from the ring
        let rf = nerdFont("Regular", 11)
        let metaMid = bounds.height - (f.minY + metaH / 2)
        drawMidLeft(w.resolution.replacingOccurrences(of: "x", with: " × "), rf,
                    isSelected ? palette.accent : palette.label,
                    x: f.minX + 2, midTop: metaMid, height: bounds.height)
        let sizeText = whFormatSize(w.fileSize)
        drawMidLeft(sizeText, rf, palette.muted,
                    x: f.maxX - advance(sizeText, rf) - 2, midTop: metaMid, height: bounds.height)
    }

    // The grid does not own the bookmark store, so the tab injects the
    // current bookmark id set; this keeps the icon truthful.
    var bookmarkedIDs: Set<String> = []
    private func isBookmarkedCard(_ i: Int) -> Bool {
        i < cards.count && bookmarkedIDs.contains(cards[i].id)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, f) in cellFrames where f.intersects(dirtyRect) { drawCard(i, f) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        hoverTracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        var hit: Int?
        for (i, f) in cellFrames where f.contains(p) { hit = i; break }
        if hit != hovered { hovered = hit; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if hovered != nil { hovered = nil; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, f) in cellFrames where f.contains(p) {
            guard i < cards.count else { return }
            let w = cards[i]
            let r = hotRects(f)
            if r.check.contains(p) { onToggleSelect?(w); return }
            if r.bookmark.contains(p) { onBookmark?(w); return }
            if r.download.contains(p) { onDownload?(w); return }
            // a click on the picture itself does nothing: applying a wallpaper
            // happens from the Themes tab, and no link leaves the dashboard
            return
        }
    }

    func loadVisible(_ rect: NSRect) {
        for (i, f) in cellFrames where f.intersects(rect) {
            guard i < cards.count else { continue }
            let w = cards[i]
            if thumbs[w.id] != nil || pending.contains(w.id) { continue }
            if let img = whCachedThumb(w.thumbURL) { thumbs[w.id] = img; needsDisplay = true; continue }
            pending.insert(w.id)
            whFetchThumb(w.thumbURL) { [weak self] img in
                guard let self else { return }
                self.pending.remove(w.id)
                if let img { self.thumbs[w.id] = img; self.needsDisplay = true }
            }
        }
    }
}

final class WallpapersTabView: NSView, NSTextFieldDelegate, ScrollStepTab {
    private let scroll = NSScrollView()
    private let grid = WHGridView()
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8

    private let field = NSTextField()
    private let searchButton = ButtonView()
    private let orderButton = ButtonView()
    private let sortButton = WHDropdown()
    private let resButton = WHDropdown()
    private let ratioButton = WHDropdown()
    private let moreButton = ButtonView()
    private let sizeSeg = SegmentedView()
    private let bulkButton = ButtonView()
    private let badge = WHBadge()

    private let client = WallhavenClient()
    private var config = WHConfig.load()
    private let bookmarks = WHBookmarkStore()

    private var results: [WHWallpaper] = []
    private var selected: Set<String> = []
    private var downloadedIDs: Set<String> = []
    private var activeDownloads: [String: WHFileDownloader] = [:]
    private var bulkIDs: Set<String> = []
    private var bulkTotal = 0
    private var bulkDoneCount = 0
    private var bulkFailedCount = 0

    private var searchToken = 0
    private var isSearching = false
    private var isLoadingMore = false
    private var hasMore = false
    private var nextRawPage = 1
    private var totalResults = 0
    private var searchError = ""
    private var hasAPIKey = false
    private var hideNSFW = false
    private var statusMessage = ""
    private var toastToken = 0
    private var pendingTopScroll = false
    private var didInitialSearch = false

    // header geometry
    private let hTop: CGFloat = 8
    private let row1H: CGFloat = 32
    private let chipH: CGFloat = 24
    private let row3H: CGFloat = 28
    private let row4H: CGFloat = 30
    private let rowGap: CGFloat = 10
    private let bottomGap: CGFloat = 12
    private let fieldH: CGFloat = 18

    private var row1Top: CGFloat { hTop }
    private var row2Top: CGFloat { row1Top + row1H + rowGap }
    private var row3Top: CGFloat { row2Top + chipH + rowGap }
    private var row4Top: CGFloat { row3Top + row3H + rowGap }
    private var showMore = false
    private var headerHeight: CGFloat {
        showMore ? row4Top + row4H + bottomGap : row3Top + row3H + bottomGap
    }

    func refreshColors() {
        needsDisplay = true
        grid.needsDisplay = true
        field.textColor = palette.label
        field.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
        for v in [searchButton, orderButton, sortButton, resButton, ratioButton, moreButton, bulkButton, sizeSeg] as [NSView] {
            v.needsDisplay = true
        }
        scroller.refresh()
    }

    func scrollStep(_ dy: CGFloat) { scrollBy(scroll, dy) }

    // Used by the off-screen layout review; harmless in normal use.
    func setMoreFilters(_ on: Bool) {
        showMore = on
        moreButton.title = on ? "Fewer Filters" : "More Filters"
        needsLayout = true
        needsDisplay = true
    }

    func debugGridInfo() -> String {
        "results=\(results.count) cards=\(grid.cards.count) frames=\(grid.cellFrames.count) " +
        "w=\(grid.frame.width) h=\(grid.frame.height) searching=\(isSearching) err=\(searchError)"
    }

    func debugPreviewStates() {
        grid.hovered = 0
        if grid.cards.count > 1 { grid.selected.insert(grid.cards[1].id) }
        if grid.cards.count > 2 { grid.downloaded.insert(grid.cards[2].id) }
        if grid.cards.count > 3 { grid.downloading[grid.cards[3].id] = 0.55 }
        if grid.cards.count > 4 { grid.bookmarkedIDs.insert(grid.cards[4].id) }
        grid.needsDisplay = true
    }

    func debugToast() { showBadge(.success, label: "Added") }

    func debugShowBookmarks(_ n: Int) {
        for w in grid.cards.prefix(n) { bookmarks.debugInsert(w) }
        config.bookmarkedOnly = true
        rebuildGrid()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        scroll.documentView = grid
        addSubview(scroller)
        scroller.scrollView = scroll
        addSubview(badge)
        badge.style = .hidden

        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = palette.itemBG.withAlphaComponent(0.35)
        field.textColor = palette.label
        field.font = nerdFont("Regular", 12)
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(searchNowAction)
        addSubview(field)

        searchButton.title = "Search"
        searchButton.fontSize = 12
        searchButton.onClick = { [weak self] in self?.beginSearch(reset: true) }
        addSubview(searchButton)

        orderButton.centeredByBounds = false
        orderButton.fontSize = 15
        orderButton.toolTip = "Toggle Sort Direction"
        orderButton.onClick = { [weak self] in self?.toggleOrder() }
        addSubview(orderButton)

        sortButton.items = whSortLabels
        sortButton.selectedIndex = whSortValues.firstIndex(of: config.sorting) ?? 0
        sortButton.title = whSortLabels[sortButton.selectedIndex]
        sortButton.toolTip = "Sort Order"
        sortButton.onPick = { [weak self] i in
            guard let self else { return }
            self.config.sorting = whSortValues[i]
            self.sortButton.title = whSortLabels[i]
            self.config.save()
            self.beginSearch(reset: true)
        }
        addSubview(sortButton)

        resButton.items = whResLabels
        resButton.selectedIndex = whResValues.firstIndex(of: config.atleast) ?? 0
        resButton.title = whResLabels[resButton.selectedIndex]
        resButton.toolTip = "Minimum Resolution"
        resButton.onPick = { [weak self] i in
            guard let self else { return }
            self.config.atleast = whResValues[i]
            self.resButton.title = whResLabels[i]
            self.config.save()
            self.beginSearch(reset: true)
        }
        addSubview(resButton)

        ratioButton.items = whRatioLabels
        ratioButton.selectedIndex = whRatioValues.firstIndex(of: config.ratios) ?? 0
        ratioButton.title = whRatioLabels[ratioButton.selectedIndex]
        ratioButton.toolTip = "Aspect Ratio"
        ratioButton.onPick = { [weak self] i in
            guard let self else { return }
            self.config.ratios = whRatioValues[i]
            self.ratioButton.title = whRatioLabels[i]
            self.config.save()
            self.beginSearch(reset: true)
        }
        addSubview(ratioButton)

        moreButton.title = "More Filters"
        moreButton.secondary = true
        moreButton.fontSize = 11
        moreButton.onClick = { [weak self] in
            guard let self else { return }
            self.showMore.toggle()
            self.moreButton.title = self.showMore ? "Fewer Filters" : "More Filters"
            self.needsLayout = true
            self.needsDisplay = true
        }
        addSubview(moreButton)

        sizeSeg.items = ["S", "M", "L"]
        sizeSeg.index = ["small", "medium", "large"].firstIndex(of: config.cardSize) ?? 0
        sizeSeg.onChange = { [weak self] i in
            guard let self else { return }
            self.config.cardSize = ["small", "medium", "large"][i]
            self.config.save()
            self.applyCardSize()
        }
        addSubview(sizeSeg)

        bulkButton.title = "Download"
        bulkButton.fontSize = 11
        bulkButton.isHidden = true
        bulkButton.onClick = { [weak self] in self?.downloadSelected() }
        addSubview(bulkButton)

        orderButton.title = config.order == "desc" ? "\u{f175}" : "\u{f176}"

        grid.onBookmark = { [weak self] w in self?.toggleBookmark(w) }
        grid.onDownload = { [weak self] w in self?.download(w) }
        grid.onToggleSelect = { [weak self] w in self?.toggleSelected(w) }

        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(visibleChanged),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // re-read the shared prefs on every show, so a change made in the
        // Options tab (Hide NSFW) is honoured without a restart
        config = WHConfig.load()
        hideNSFW = config.hideNSFW
        refreshKeyState()
        downloadedIDs = whDownloadedIDs(in: wallpapersDir())
        grid.downloaded = downloadedIDs
        if !didInitialSearch {
            didInitialSearch = true
            if config.bookmarkedOnly { rebuildGrid() } else { beginSearch(reset: true) }
        } else {
            rebuildGrid()
        }
    }

    private func refreshKeyState() {
        hasAPIKey = !readSecret("wallhaven").trimmingCharacters(in: .whitespaces).isEmpty
    }

    // The stored purity, with NSFW forced off while Hide NSFW is on. The
    // stored value is never overwritten, so turning the toggle off restores it.
    private var effectivePurity: String {
        guard hideNSFW, config.purity.count == 3 else { return config.purity }
        var chars = Array(config.purity)
        chars[2] = "0"
        return String(chars)
    }

    private func toggleOrder() {
        config.order = config.order == "desc" ? "asc" : "desc"
        orderButton.title = config.order == "desc" ? "\u{f175}" : "\u{f176}"
        orderButton.toolTip = config.order == "desc" ? "Descending" : "Ascending"
        config.save()
        beginSearch(reset: true)
    }

    private func currentParams() -> WHParams {
        var p = WHParams()
        p.query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        p.categories = config.categories
        p.purity = effectivePurity
        p.sorting = config.sorting
        p.order = config.order
        p.atleast = config.atleast
        p.colors = config.colors
        p.ratios = config.ratios
        return p
    }

    // No search on keystroke: a wallhaven session shares one small rate
    // budget, so the query only goes out on the Search button or Return.
    // The delegate is kept only to clear the drawn placeholder on typing.
    func controlTextDidChange(_ obj: Notification) {
        needsDisplay = true
    }

    @objc private func searchNowAction() { beginSearch(reset: true) }

    private func beginSearch(reset: Bool) {
        guard !config.bookmarkedOnly else { return }
        refreshKeyState()
        client.apiKey = readSecret("wallhaven")
        searchError = ""
        if reset {
            searchToken += 1
            results = []
            selected.removeAll()
            nextRawPage = 1
            totalResults = 0
            hasMore = false
            isLoadingMore = false
            isSearching = true
            grid.thumbs.removeAll()
            rebuildGrid()
        } else {
            guard hasMore, !isLoadingMore, !isSearching else { return }
            isLoadingMore = true
        }
        let token = searchToken
        var p = currentParams()
        p.page = nextRawPage
        let pages = 3
        needsDisplay = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let r = try self.client.searchMultiPage(p, numPages: pages)
                DispatchQueue.main.async {
                    guard token == self.searchToken else { return }
                    let seen = Set(self.results.map { $0.id })
                    let fresh = r.data.filter { !seen.contains($0.id) }
                    self.results.append(contentsOf: fresh)
                    self.totalResults = r.meta.total
                    self.nextRawPage += pages
                    self.isSearching = false
                    self.isLoadingMore = false
                    self.hasMore = self.results.count < self.totalResults && !fresh.isEmpty
                    let oldH = self.grid.frame.height
                    self.rebuildGrid()
                    if reset {
                        self.scrollToTop()
                    } else {
                        // the document is non-flipped, so appended rows move
                        // the existing content up; nudge the origin by the
                        // same amount so the view does not jump
                        let delta = self.grid.frame.height - oldH
                        if delta > 0.5 {
                            let maxY = max(0, self.grid.frame.height - self.scroll.contentSize.height)
                            let y = min(maxY, self.scroll.contentView.bounds.origin.y + delta)
                            self.scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                            self.scroll.reflectScrolledClipView(self.scroll.contentView)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard token == self.searchToken else { return }
                    self.isSearching = false
                    self.isLoadingMore = false
                    self.searchError = error.localizedDescription
                    self.needsDisplay = true
                }
            }
        }
    }

    private func loadMore() {
        guard !config.bookmarkedOnly, !isSearching, !isLoadingMore, hasMore else { return }
        beginSearch(reset: false)
    }

    private func rebuildGrid() {
        let cards: [WHWallpaper]
        if config.bookmarkedOnly {
            cards = bookmarks.all()
                .filter { !(hideNSFW && $0.purity.lowercased() == "nsfw") }
                .compactMap { b in
                    WHWallpaper(json: ["id": b.id, "path": b.imageURL, "url": b.pageURL,
                                       "resolution": b.resolution, "purity": b.purity,
                                       "file_size": NSNumber(value: b.fileSize),
                                       "thumbs": ["small": b.thumbURL]])
                }
        } else {
            cards = results.filter { !(hideNSFW && $0.purity.lowercased() == "nsfw") }
        }
        grid.cards = cards
        grid.cardSize = config.cardSize
        grid.selected = selected
        grid.downloaded = downloadedIDs
        grid.bookmarkedIDs = Set(bookmarks.all().map { $0.id })
        let avail = bounds.width - scrollerW - 14
        if avail > 40 { grid.frame.size.width = avail }
        grid.minContentHeight = scroll.contentSize.height
        grid.rebuild()
        if config.bookmarkedOnly { pendingTopScroll = true }
        needsLayout = true
        needsDisplay = true
    }

    // S/M/L: rebuild in place, keeping the view inside the new bounds
    private func applyCardSize() {
        grid.cardSize = config.cardSize
        grid.minContentHeight = scroll.contentSize.height
        grid.rebuild()
        let maxY = max(0, grid.frame.height - scroll.contentSize.height)
        let y = min(scroll.contentView.bounds.origin.y, maxY)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroller.refresh()
        grid.needsDisplay = true
    }

    // --- actions ---

    private func toggleBookmark(_ w: WHWallpaper) {
        bookmarks.toggle(w)
        grid.bookmarkedIDs = Set(bookmarks.all().map { $0.id })
        if config.bookmarkedOnly { rebuildGrid() } else { grid.needsDisplay = true }
    }

    private func toggleSelected(_ w: WHWallpaper) {
        if selected.contains(w.id) { selected.remove(w.id) } else { selected.insert(w.id) }
        grid.selected = selected
        grid.needsDisplay = true
        updateBulkButton()
    }

    private func updateBulkButton() {
        let n = selected.count
        // works in the Bookmarked view too: a saved wallpaper can be
        // downloaded from there just as from a search result
        bulkButton.isHidden = n == 0
        bulkButton.title = n == 1 ? "Download 1" : "Download \(n)"
        needsLayout = true
    }

    private func download(_ w: WHWallpaper) {
        guard activeDownloads[w.id] == nil, !downloadedIDs.contains(w.id) else { return }
        let dir = wallpapersDir()
        grid.downloading[w.id] = 0
        grid.needsDisplay = true
        let d = whStartDownload(client: client, wallpaper: w, into: dir,
                                onProgress: { [weak self] frac in
            self?.grid.downloading[w.id] = frac
            self?.grid.needsDisplay = true
        }, completion: { [weak self] res in
            guard let self else { return }
            self.activeDownloads[w.id] = nil
            self.grid.downloading[w.id] = nil
            let ok: Bool
            if case .success(let path) = res {
                ok = true
                self.downloadedIDs.insert(w.id)
                self.grid.downloaded = self.downloadedIDs
                whRecordDownload((path as NSString).lastPathComponent, id: w.id, purity: w.purity)
            } else {
                ok = false
            }
            self.grid.needsDisplay = true

            let isBulk = self.bulkTotal > 0 && self.bulkIDs.contains(w.id)
            if isBulk {
                self.bulkIDs.remove(w.id)
                self.bulkDoneCount += 1
                if !ok { self.bulkFailedCount += 1 }
                if self.bulkIDs.isEmpty {
                    self.finishBulk()
                } else {
                    // dynamic: a progress ring with the running added count
                    let frac = Double(self.bulkDoneCount) / Double(max(self.bulkTotal, 1))
                    self.showBadge(.progress(frac),
                                   label: "\(self.bulkDoneCount)/\(self.bulkTotal)", sticky: true)
                }
            } else if ok {
                self.showBadge(.success, label: "Added")
            } else if case .failure(let e) = res {
                self.showBadge(.failure, label: "Failed — \(e.localizedDescription)")
            }
        })
        activeDownloads[w.id] = d
    }

    // Bulk download: the button slot shows a progress ring and count, then a
    // green check (or a red mark with the failures), after which the
    // selection clears and the button is gone.
    private func downloadSelected() {
        let items = grid.cards.filter {
            selected.contains($0.id) && !downloadedIDs.contains($0.id) && activeDownloads[$0.id] == nil
        }
        bulkIDs = Set(items.map { $0.id })
        bulkTotal = items.count
        bulkDoneCount = 0
        bulkFailedCount = 0
        if bulkIDs.isEmpty { clearSelection(); return }
        showBadge(.progress(0), label: "0/\(bulkTotal)", sticky: true)
        for w in items { download(w) }
    }

    private func finishBulk() {
        let failed = bulkFailedCount
        let added = bulkDoneCount - failed
        bulkTotal = 0
        clearSelection()
        if failed == 0 {
            showBadge(.success, label: "Added \(added)")
        } else {
            showBadge(.failure, label: "Added \(added), \(failed) failed")
        }
    }

    private func clearSelection() {
        selected.removeAll()
        grid.selected = selected
        updateBulkButton()
        grid.needsDisplay = true
        needsDisplay = true
    }

    // A sticky badge stays until replaced (its ring and count update in
    // place); a normal one clears itself after a moment.
    private func showBadge(_ style: WHBadge.Style, label: String, sticky: Bool = false) {
        toastToken += 1
        let token = toastToken
        badge.label = label
        badge.style = style
        bulkButton.isHidden = true
        guard !sticky else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.badge.style = .hidden
            self.badge.label = ""
            self.updateBulkButton()
        }
    }

    @objc private func visibleChanged() {
        let vis = scroll.documentVisibleRect
        grid.loadVisible(vis)
        scroller.refresh()
        // the document is non-flipped, so later results sit at lower y:
        // reaching the end means the viewport's bottom edge nears origin 0
        if vis.minY < 600 { loadMore() }
    }

    private func scrollToTop() {
        let maxY = max(0, grid.frame.height - scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroller.refresh()
    }

    // --- header geometry ---

    private func frameFor(top: CGFloat, x: CGFloat, w: CGFloat, h: CGFloat) -> NSRect {
        NSRect(x: x, y: bounds.height - top - h, width: w, height: h)
    }

    private func categoryRects() -> [NSRect] {
        let labels = ["General", "Anime", "People"]
        let f = nerdFont("Regular", 11)
        var x: CGFloat = 0
        var out: [NSRect] = []
        for l in labels {
            let w = advance(l, f) + 20
            out.append(frameFor(top: row2Top, x: x, w: w, h: chipH))
            x += w + 6
        }
        return out
    }

    private func purityRects() -> [NSRect] {
        let labels = ["SFW", "Sketchy", "NSFW"]
        let f = nerdFont("Regular", 11)
        var x = categoryRects().last.map { $0.maxX + 16 } ?? 0
        var out: [NSRect] = []
        for l in labels {
            let w = advance(l, f) + 20
            out.append(frameFor(top: row2Top, x: x, w: w, h: chipH))
            x += w + 6
        }
        return out
    }

    private func bookmarkChipRect() -> NSRect {
        let x = purityRects().last.map { $0.maxX + 16 } ?? 0
        let w = advance("Bookmarked", nerdFont("Regular", 11)) + 20
        return frameFor(top: row2Top, x: x, w: w, h: chipH)
    }

    private func colorSwatchRects() -> [NSRect] {
        let labelW = advance("Color", nerdFont("Regular", 11)) + 10
        var x = labelW
        var out: [NSRect] = []
        for _ in whColorPresets {
            out.append(frameFor(top: row4Top + 5, x: x, w: 20, h: 20))
            x += 26
        }
        return out
    }

    private func chip(_ r: NSRect, _ label: String, on: Bool, tint: NSColor, enabled: Bool = true) {
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        if on && enabled {
            tint.withAlphaComponent(0.16).setFill(); path.fill()
            tint.setStroke(); path.lineWidth = 1; path.stroke()
        } else {
            palette.itemBG.withAlphaComponent(0.35).setFill(); path.fill()
            (enabled ? palette.muted.withAlphaComponent(0.35) : palette.muted.withAlphaComponent(0.2)).setStroke()
            path.lineWidth = 1; path.stroke()
        }
        let ink = !enabled ? palette.muted.withAlphaComponent(0.6) : (on ? tint : palette.label)
        drawMidCenter(label, nerdFont("Regular", 11), ink,
                      centerX: r.midX, midTop: bounds.height - r.midY, height: bounds.height)
    }

    override func layout() {
        super.layout()
        let W = bounds.width
        let g: CGFloat = 8
        let sortW: CGFloat = 118
        let orderW: CGFloat = 34
        let searchW: CGFloat = 76
        let queryW = max(160, W - sortW - orderW - searchW - g * 3)
        field.frame = frameFor(top: row1Top + (row1H - fieldH) / 2, x: 30, w: queryW - 40, h: fieldH)
        sortButton.frame = frameFor(top: row1Top + 1, x: queryW + g, w: sortW, h: row1H - 2)
        orderButton.frame = frameFor(top: row1Top + 1, x: queryW + g + sortW + g, w: orderW, h: row1H - 2)
        searchButton.frame = frameFor(top: row1Top + 1, x: queryW + g + sortW + g + orderW + g, w: searchW, h: row1H - 2)

        resButton.frame = frameFor(top: row3Top, x: 0, w: 130, h: row3H)
        let bulkW: CGFloat = bulkButton.isHidden ? 0 : 104
        bulkButton.frame = frameFor(top: row3Top, x: 138, w: bulkW, h: row3H)
        let segSize = sizeSeg.sizeThatFits()
        sizeSeg.frame = frameFor(top: row3Top - 1, x: W - segSize.width, w: segSize.width, h: segSize.height)
        let moreW: CGFloat = 100
        moreButton.frame = frameFor(top: row3Top, x: W - segSize.width - g - moreW, w: moreW, h: row3H)
        updateBulkButton()

        ratioButton.isHidden = !showMore
        if showMore {
            ratioButton.frame = frameFor(top: row4Top, x: W - 130, w: 130, h: row4H - 2)
        }

        let scrollTop = headerHeight
        let scrollH = max(0, bounds.height - scrollTop - 16)
        scroll.frame = NSRect(x: 0, y: 16, width: max(0, W - scrollerW - 14), height: scrollH)
        scroller.frame = NSRect(x: W - scrollerW, y: 16, width: scrollerW, height: scrollH)
        scroller.refresh()
        // the download indicator shares the bulk button's slot in the header
        badge.frame = frameFor(top: row3Top, x: 138, w: 200, h: row3H)

        let gridW = scroll.contentSize.width
        if gridW > 0, abs(grid.frame.width - gridW) > 0.5 {
            grid.frame.size.width = gridW
            grid.rebuild()
        }
        // keep the short-list padding in step with the viewport
        let clipH = scroll.contentSize.height
        if clipH > 0, abs(grid.minContentHeight - clipH) > 0.5 {
            grid.minContentHeight = clipH
            grid.rebuild()
        }
        if pendingTopScroll {
            pendingTopScroll = false
            scrollToTop()
        }
        grid.loadVisible(scroll.documentVisibleRect)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // search box
        let W = bounds.width
        let g: CGFloat = 8
        let sortW: CGFloat = 118, orderW: CGFloat = 34, searchW: CGFloat = 76
        let queryW = max(160, W - sortW - orderW - searchW - g * 3)
        let box = frameFor(top: row1Top, x: 0, w: queryW, h: row1H)
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        palette.itemBG.withAlphaComponent(0.35).setFill(); path.fill()
        palette.muted.withAlphaComponent(0.35).setStroke(); path.lineWidth = 1; path.stroke()
        drawMidCenter("\u{f002}", nerdFont("Regular", 12), palette.muted,
                      centerX: 16, midTop: bounds.height - box.midY, height: bounds.height)
        if field.stringValue.isEmpty {
            drawMidLeft("Search for wallpapers on wallhaven.cc", nerdFont("Regular", 12), palette.muted,
                        x: 30, midTop: bounds.height - box.midY, height: bounds.height)
        }

        // chips
        let catRects = categoryRects()
        for (i, r) in catRects.enumerated() {
            chip(r, ["General", "Anime", "People"][i], on: config.categories[config.categories.index(config.categories.startIndex, offsetBy: i)] == "1",
                 tint: palette.accent)
        }
        let purRects = purityRects()
        let purTints = [NSColor.systemGreen, NSColor.systemYellow, NSColor.systemRed]
        for (i, r) in purRects.enumerated() {
            let locked = i == 2 && (!hasAPIKey || hideNSFW)
            chip(r, ["SFW", "Sketchy", "NSFW"][i],
                 on: effectivePurity[effectivePurity.index(effectivePurity.startIndex, offsetBy: i)] == "1",
                 tint: purTints[i], enabled: !locked)
        }
        let bookmarkRect = bookmarkChipRect()
        chip(bookmarkRect, "Bookmarked", on: config.bookmarkedOnly, tint: palette.accent)

        // colour swatches (More Filters)
        if showMore {
            drawMidLeft("Color", nerdFont("Regular", 11), palette.muted,
                        x: 0, midTop: row4Top + row4H / 2, height: bounds.height)
            for (i, r) in colorSwatchRects().enumerated() {
                let p = whColorPresets[i]
                let sq = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
                (hexColor(p.hex) ?? palette.muted).setFill(); sq.fill()
                let selected = config.colors == p.hex
                (selected ? palette.accent : palette.muted.withAlphaComponent(0.5)).setStroke()
                sq.lineWidth = selected ? 2 : 1; sq.stroke()
            }
        }

        // results count / search state, right-aligned before More Filters
        var countText = ""
        if isSearching {
            countText = "Searching…"
        } else if !searchError.isEmpty {
            countText = searchError
        } else if config.bookmarkedOnly {
            countText = "\(bookmarks.count) bookmarked"
        } else if totalResults > 0 {
            countText = "\(totalResults) results"
        }
        if !countText.isEmpty {
            let ink = searchError.isEmpty ? palette.muted : NSColor.systemRed
            let f = nerdFont("Regular", 11)
            drawMidLeft(countText, f, ink,
                        x: moreButton.frame.minX - 12 - advance(countText, f),
                        midTop: row3Top + row3H / 2, height: bounds.height)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let catRects = categoryRects()
        for (i, r) in catRects.enumerated() where r.contains(p) {
            toggleMask(&config.categories, i)
            config.save()
            beginSearch(reset: true)
            return
        }
        let purRects = purityRects()
        for (i, r) in purRects.enumerated() where r.contains(p) {
            if i == 2 && (!hasAPIKey || hideNSFW) { return }
            toggleMask(&config.purity, i)
            config.save()
            beginSearch(reset: true)
            return
        }
        if bookmarkChipRect().contains(p) {
            config.bookmarkedOnly.toggle()
            config.save()
            if config.bookmarkedOnly {
                searchToken += 1
                isSearching = false
                rebuildGrid()
            } else {
                beginSearch(reset: true)
            }
            updateBulkButton()
            return
        }
        if showMore {
            for (i, r) in colorSwatchRects().enumerated() where r.contains(p) {
                let hex = whColorPresets[i].hex
                config.colors = config.colors == hex ? "" : hex
                config.save()
                beginSearch(reset: true)
                return
            }
        }
    }

    // A 3-bit mask string; the last on bit cannot be turned off, so a search
    // never asks for zero categories or zero purity.
    private func toggleMask(_ mask: inout String, _ index: Int) {
        var chars = Array(mask)
        guard index < chars.count else { return }
        chars[index] = chars[index] == "1" ? "0" : "1"
        if chars.allSatisfy({ $0 == "0" }) { return }
        mask = String(chars)
    }
}

// The download-folder scan that marks a card "Saved": a downloaded file is
// named wallhaven-<id>.<ext>, so its id is recoverable without a manifest.
func whDownloadedIDs(in dir: String) -> Set<String> {
    var out: Set<String> = []
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    for e in entries where e.hasPrefix("wallhaven-") {
        let rest = e.dropFirst("wallhaven-".count)
        let id = rest.split(separator: ".").first.map(String.init) ?? ""
        if !id.isEmpty { out.insert(id) }
    }
    return out
}

extension StorageTabView: RefreshableTab {}
extension APIKeysTabView: RefreshableTab {}
extension UpdateTabView: RefreshableTab {}
extension WallpapersTabView: RefreshableTab {}

final class RootView: NSView {
    let tabs = ["Options", "Workspaces", "Themes", "Wallpapers", "Storage", "API Keys", "Update"]
    var selected = 0
    private var logo: NSImage?
    private let logoView = NSImageView()
    private let options = OptionsTabView(frame: .zero)
    private let workspaces = WorkspacesTabView(frame: .zero)
    private let themes = ThemesTabView(frame: .zero)
    private let wallpapers = WallpapersTabView(frame: .zero)
    private let storage = StorageTabView(frame: .zero)
    private let keys = APIKeysTabView(frame: .zero)
    private let update = UpdateTabView(frame: .zero)
    private lazy var tabViews: [NSView] = [options, workspaces, themes, wallpapers, storage, keys, update]
    var onHide: (() -> Void)?

    private let logoH: CGFloat = 34
    private let topPad: CGFloat = 16
    private let tabH: CGFloat = 40
    private let pad: CGFloat = 20

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        logoView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(logoView)
        addSubview(options)
        options.onApplied = { [weak self] in self?.needsDisplay = true }
        themes.onApplied = { [weak self] in self?.paletteChanged() }
        reloadLogo()
    }

    // A theme switch swaps the palette under the whole modal. Every surface
    // draws its own colour, so each has to be told to repaint: the tab view,
    // its document/list subviews and the custom scroller. Left alone they keep
    // the old theme until the next scroll or hover.
    func paletteChanged() {
        palette = loadPalette()
        reloadLogo()
        for v in tabViews { (v as? RefreshableTab)?.refreshColors() }
        ThemeEditor.refreshColors()
        needsDisplay = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func reloadLogo() {
        logo = logoImage()
        logoView.image = logo
        needsDisplay = true
        for v in tabViews { v.needsDisplay = true }
    }

    private var tabTop: CGFloat { topPad + logoH + 24 }
    private var contentTop: CGFloat { tabTop + tabH + 10 }
    private var contentFrame: NSRect {
        NSRect(x: pad, y: pad, width: bounds.width - pad * 2,
               height: bounds.height - contentTop - pad)
    }

    // every open starts from the saved state, not from edits left over from
    // a previous visit
    func resetTabsOnShow() {
        workspaces.resetToSaved()
    }

    // the window forwards every left click here before dispatch
    func mouseDownAnywhere(_ e: NSEvent) {
        workspaces.collapseIfClickOutside(e)
    }

    func showTab(_ i: Int) {
        selected = i
        for v in tabViews { v.removeFromSuperview() }
        let v = tabViews[i]
        v.frame = contentFrame
        addSubview(v)
        // a tab holding a text field may have made it first responder; the
        // arrows and Esc have to keep reaching this view after a switch
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if let logo {
            let aspect = logo.size.width / max(logo.size.height, 1)
            let w = logoH * aspect
            // centred between the card's top edge and the tabs' top edge
            logoView.frame = NSRect(x: bounds.midX - w / 2,
                                    y: bounds.height - (tabTop + logoH) / 2,
                                    width: w, height: logoH)
        }
        for v in tabViews { v.frame = contentFrame }
    }

    private func tabFrame(_ i: Int) -> NSRect {
        let f = nerdFont("Bold", 13)
        var widths: [CGFloat] = []
        for t in tabs { widths.append(advance(t, f) + 34) }
        let total = widths.reduce(0, +)
        var x = (bounds.width - total) / 2
        for (j, w) in widths.enumerated() {
            if j == i {
                return NSRect(x: x, y: bounds.height - tabTop - tabH + 6, width: w, height: tabH)
            }
            x += w
        }
        return .zero
    }

    override func draw(_ dirtyRect: NSRect) {
        let corner = min(windowCornerRadius(10), min(bounds.width, bounds.height) / 2)
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: corner, yRadius: corner)
        palette.barBG.setFill()
        body.fill()
        palette.accent.setStroke()
        body.lineWidth = 1
        body.stroke()

        // tab strip
        var x = (bounds.width - tabsWidth()) / 2
        let f = nerdFont("Bold", 13)
        for (i, t) in tabs.enumerated() {
            let w = advance(t, f) + 34
            let mid = bounds.height - (tabTop + tabH / 2)
            drawMidCenter(t, f, i == selected ? palette.accent : palette.label,
                          centerX: x + w / 2, midTop: tabTop + tabH / 2, height: bounds.height)
            if i == selected {
                palette.accent.setFill()
                NSRect(x: x + 10, y: mid - 15, width: w - 20, height: 2).fill()
            }
            x += w
        }
    }

    private func tabsWidth() -> CGFloat {
        let f = nerdFont("Bold", 13)
        return tabs.reduce(0) { $0 + advance($1, f) + 34 }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let f = nerdFont("Bold", 13)
        var x = (bounds.width - tabsWidth()) / 2
        for (i, t) in tabs.enumerated() {
            let w = advance(t, f) + 34
            let rect = NSRect(x: x, y: bounds.height - tabTop - tabH, width: w, height: tabH)
            if rect.contains(p) { showTab(i); return }
            x += w
        }
        onHide?()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var activeTab: NSView { tabViews[selected] }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onHide?()
        case 43 where event.modifierFlags.contains([.command, .control, .option]): onHide?()
        case 126: (activeTab as? ScrollStepTab)?.scrollStep(-48)   // up
        case 125: (activeTab as? ScrollStepTab)?.scrollStep(48)    // down
        case 123: showTab((selected + tabs.count - 1) % tabs.count) // left
        case 124: showTab((selected + 1) % tabs.count)              // right
        default: break
        }
    }
}

// --- app -------------------------------------------------------------------

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: DashboardWindow?
    var root: RootView?
    var globalMonitor: Any?
    var localKeyMonitor: Any?
    let width: CGFloat = 860
    let height: CGFloat = 720

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // An accessory app has no visible menu bar, but key equivalents are
        // dispatched through the main menu: without an Edit menu, Cmd+V/C/X/A
        // do nothing and only the field's context menu offers paste.
        let main = NSMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApplication.shared.mainMenu = main

        let root = RootView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.onHide = { [weak self] in self?.hide() }
        self.root = root

        let w = DashboardWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .popUpMenu
        w.acceptsMouseMovedEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.contentView = root
        w.onMouseDown = { [weak self] e in self?.root?.mouseDownAnywhere(e) }
        window = w

        let pid = HOME + "/.local/state/omacosy/dashboard.pid"
        try? "\(ProcessInfo.processInfo.processIdentifier)\n"
            .write(toFile: pid, atomically: true, encoding: .utf8)

        watch("/tmp/omacosy-dashboard", create: true) { [weak self] in self?.toggle() }
        watch(HOME + "/.config/omarchy/current") { [weak self] in
            self?.root?.paletteChanged()
        }
        show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func show() {
        guard let w = window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        w.setFrame(NSRect(x: screen.frame.midX - width / 2,
                          y: screen.frame.midY - height / 2,
                          width: width, height: height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        if let root { root.resetTabsOnShow() }
        w.makeKeyAndOrderFront(nil)
        if let root { w.makeFirstResponder(root) }
        // AeroSpace hands the window to the screen without making it key, so
        // the first keystroke — Escape — has nowhere to go until a click. Ask
        // for focus again one tick later, once the window server has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let w = self?.window, w.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            if let root = self?.root { w.makeFirstResponder(root) }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                // an NSOpenPanel is a window from a system helper process, so
                // its clicks reach this monitor as "another app"; while such a
                // sheet is up, its clicks must not hide the dashboard
                guard let self, self.window?.hideSuppressed != true else { return }
                self.hide()
            }
        }
        if localKeyMonitor == nil {
            // Esc closes the dashboard even while a text field is editing,
            // where the field editor swallows it before the responder chain.
            // A local monitor sees the event first, like the picker's does.
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
                guard let self else { return e }
                // a live Theme Editor owns the session: Esc closes it and
                // returns to Themes, never the dashboard under it
                if e.keyCode == 53, e.window === self.window, ThemeEditor.closeIfOpen() { return nil }
                // a live grid selection eats Esc (leave selection) and Delete
                // (open the confirm) before the dashboard acts on them
                if e.window === self.window, let sel = ThemesTabView.selecting {
                    if e.keyCode == 53, sel.handleEscapeKey() { return nil }
                    if e.keyCode == 51 || e.keyCode == 117, sel.handleDeleteKey() { return nil }
                }
                guard self.window?.hideSuppressed != true else { return e }
                // only Esc aimed at the dashboard: while the app picker is
                // up it is the key window and handles its own Esc
                if e.keyCode == 53, e.window === self.window { self.hide(); return nil }
                return e
            }
        }
    }

    func hide() {
        // a live Theme Editor owns the session: outside clicks and the
        // toggle key must not dismiss the dashboard until it is closed
        guard window?.hideSuppressed != true else { return }
        AppPicker.dismiss()
        window?.hideSuppressed = false
        window?.orderOut(nil)
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let k = localKeyMonitor { NSEvent.removeMonitor(k); localKeyMonitor = nil }
    }

    func toggle() {
        if window?.isVisible == true { hide() } else { show() }
    }
}

// create makes the trigger if it is missing. Without it the retry below runs
// every 2 s for as long as the file is absent, and /tmp is emptied on reboot —
// so a fresh session would tick every two seconds until the shortcut was
// pressed again. The bar's own watcher creates its trigger for the same reason.
func watch(_ path: String, create: Bool = false, _ handler: @escaping () -> Void) {
    if create, !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    let fd = open(path, O_EVTONLY)
    guard fd >= 0 else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { watch(path, create: create, handler) }
        return
    }
    let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
        eventMask: [.write, .attrib, .delete, .rename], queue: .main)
    src.setEventHandler {
        let ev = src.data
        handler()
        if ev.contains(.delete) || ev.contains(.rename) { src.cancel() }
    }
    src.setCancelHandler {
        close(fd)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { watch(path, create: create, handler) }
    }
    src.resume()
}

// Hidden entry points for the Phase 7 acceptance tests. They run before the
// window ever opens, so `omacosy-dashboard-bin --wallhaven-…` is a plain CLI.
func whRunSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    func expectOK(_ url: String) {
        check("guard accepts \(url)", (try? validateWHURL(url)) != nil)
    }
    func expectReject(_ url: String) {
        if (try? validateWHURL(url)) != nil {
            check("guard rejects \(url)", false)
        } else {
            check("guard rejects \(url)", true)
        }
    }

    expectOK("https://wallhaven.cc/api/v1/search")
    expectOK("https://w.wallhaven.cc/full/j3/wallhaven-j3qv85.jpg")
    expectOK("https://thumbs.wallhaven.cc/0x/example.jpg")
    expectReject("http://wallhaven.cc/api/v1/search")
    expectReject("https://localhost/x")
    expectReject("https://foo.localhost/x")
    expectReject("https://foo.local/x")
    expectReject("https://foo.internal/x")
    expectReject("https://127.0.0.1/x")
    expectReject("https://10.0.0.5/x")
    expectReject("https://192.168.1.1/x")
    expectReject("https://172.16.0.1/x")
    expectReject("https://169.254.1.1/x")
    expectReject("https://100.64.0.1/x")
    expectReject("https://[::1]/x")
    expectReject("https://[fe80::1]/x")
    expectReject("https://user:pass@wallhaven.cc/x")

    check("filename keeps a safe basename",
          whDownloadFilename("https://w.wallhaven.cc/full/j3/wallhaven-j3qv85.jpg") == "wallhaven-j3qv85.jpg")
    check("filename strips traversal",
          whDownloadFilename("https://evil/../../etc/passwd") == "passwd.jpg")
    check("filename forces an extension",
          whDownloadFilename("https://evil/wall") == "wall.jpg")
    check("filename survives an empty path",
          whDownloadFilename("https://evil/") == "wallhaven.jpg")
    check("filename replaces odd characters",
          !whDownloadFilename("https://evil/a b?c.jpg").contains(" "))

    let fm = FileManager.default
    let tmp = NSTemporaryDirectory() + "wh-selftest-\(ProcessInfo.processInfo.processIdentifier)"
    try? fm.removeItem(atPath: tmp)
    try? fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: tmp) }
    check("unique path uses the name when free", whUniquePath(tmp, "a.jpg") == tmp + "/a.jpg")
    fm.createFile(atPath: tmp + "/a.jpg", contents: Data("x".utf8))
    check("unique path adds -2 on collision", whUniquePath(tmp, "a.jpg") == tmp + "/a-2.jpg")

    let bpath = tmp + "/bookmarks.json"
    let store = WHBookmarkStore(path: bpath)
    let sample = WHWallpaper(json: ["id": "abc123",
                                    "path": "https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg",
                                    "thumbs": ["small": "https://thumbs/abc.jpg"],
                                    "resolution": "3840x2160"])!
    check("bookmark starts empty", !store.isBookmarked("abc123"))
    check("bookmark toggles on", store.toggle(sample))
    check("bookmark is remembered", store.isBookmarked("abc123"))
    let reloaded = WHBookmarkStore(path: bpath)
    check("bookmark survives a reload", reloaded.isBookmarked("abc123"))
    check("bookmark toggles off", reloaded.toggle(sample) == false)
    check("bookmark removal persists", !WHBookmarkStore(path: bpath).isBookmarked("abc123"))

    let anon = WallhavenClient()
    var immediate = 0
    for _ in 0..<(anon.anonymousPerMinute + 1) {
        if anon.reserveRequestSlot() <= 0 { immediate += 1 }
    }
    check("rate limiter allows \(anon.anonymousPerMinute)/min anonymous",
          immediate == anon.anonymousPerMinute)
    let keyed = WallhavenClient()
    keyed.apiKey = "abc"
    var keyedImmediate = 0
    for _ in 0..<(keyed.keyedPerMinute + 1) {
        if keyed.reserveRequestSlot() <= 0 { keyedImmediate += 1 }
    }
    check("rate limiter allows \(keyed.keyedPerMinute)/min with a key",
          keyedImmediate == keyed.keyedPerMinute)

    print(failures == 0 ? "wallhaven selftest: all checks passed"
                        : "wallhaven selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--wallhaven-guard" {
    do {
        try validateWHURL(CommandLine.arguments[2])
        print("OK")
        exit(0)
    } catch {
        print("REJECT \(error.localizedDescription)")
        exit(1)
    }
}
if CommandLine.arguments.contains("--wallhaven-selftest") {
    exit(whRunSelfTest() == 0 ? 0 : 1)
}
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--wallhaven-search" {
    let client = WallhavenClient()
    var p = WHParams()
    p.query = CommandLine.arguments[2]
    p.atleast = "1920x1080"
    do {
        let r = try client.search(p)
        print("total=\(r.meta.total) lastPage=\(r.meta.lastPage) got=\(r.data.count)")
        for w in r.data.prefix(3) {
            print("  \(w.id)  \(w.resolution)  \(w.fileSize)B  \(w.thumbURL)")
        }
        exit(0)
    } catch {
        print("search failed: \(error.localizedDescription)")
        exit(1)
    }
}
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--wallhaven-multipage" {
    let client = WallhavenClient()
    var p = WHParams(); p.query = CommandLine.arguments[2]
    let n = Int(CommandLine.arguments[3]) ?? 3
    do {
        let r = try client.searchMultiPage(p, numPages: n)
        print("pages=\(n) got=\(r.data.count) logicalLastPage=\(r.meta.lastPage) currentPage=\(r.meta.currentPage)")
        exit(0)
    } catch { print("multipage failed: \(error.localizedDescription)"); exit(1) }
}
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--wallhaven-download" {
    let client = WallhavenClient()
    do {
        let w = try client.info(CommandLine.arguments[2])
        print("resolved \(w.imageURL)")
        let dir = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : NSTemporaryDirectory() + "wh-dl"
        var done = false
        var rc: Int32 = 1
        _ = whStartDownload(client: client, wallpaper: w, into: dir, onProgress: { _ in },
                            completion: { res in
            switch res {
            case .success(let path):
                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                print("saved \(path) (\(size) bytes)")
                rc = 0
            case .failure(let e):
                print("download failed: \(e.localizedDescription)")
            }
            done = true
        })
        let deadline = Date().addingTimeInterval(60)
        while !done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        exit(rc)
    } catch { print("download failed: \(error.localizedDescription)"); exit(1) }
}

// Headless checks for EditorState's history and folding. Like
// --wallhaven-selftest, it runs before the window opens.
func editorStateSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    let s = EditorState()
    check("starts neutral", s.filters.isIdentity && !s.canUndo && !s.canRedo && !s.hasEdits)
    s.set("brightness", 100)
    check("a no-op edit is rejected", !s.canUndo && !s.hasEdits)

    s.set("brightness", 110)
    check("an edit is remembered", s.filters["brightness"] == 110 && s.canUndo && s.hasEdits)
    s.set("brightness", 120)
    check("a same-control burst folds", s.filters["brightness"] == 120)
    s.undo()
    check("undo returns before the burst", s.filters["brightness"] == 100 && !s.canUndo)
    s.redo()
    check("redo returns the burst result", s.filters["brightness"] == 120 && s.canUndo && !s.canRedo)

    s.set("contrast", 110)
    s.set("contrast", 130)
    s.undo()
    check("a burst on a new control is one step",
          s.filters["contrast"] == 100 && s.filters["brightness"] == 120)
    s.undo()
    check("undo keeps walking", s.filters.isIdentity && !s.canUndo)
    s.redo()
    check("redo walks forward again", s.filters["brightness"] == 120)

    s.reset()
    check("reset clears the recipe", s.filters.isIdentity)
    s.undo()
    check("reset is one undoable step", s.filters["brightness"] == 120)
    s.set("strength", 80)
    s.set("strength", 60)
    check("strength folds too", s.filters["strength"] == 60)
    s.undo()
    check("strength burst undoes in one",
          s.filters["strength"] == 100 && s.filters["brightness"] == 120)

    print(failures == 0 ? "editor-state selftest: all checks passed"
                        : "editor-state selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--image-editor-selftest") {
    exit(editorStateSelfTest() == 0 ? 0 : 1)
}

// The wallpaper editor's preview door (Phase 8b): render the in-process
// CoreImage preview headlessly so its output can be compared, by hand, with
// the engine's `image render --max 960`. `--blur` renders the wallpaper.blur
// variant instead, for comparison with the engine's blurredVariant. Like the
// wallhaven doors, it runs before the window opens.
if CommandLine.arguments.count >= 5, CommandLine.arguments[1] == "--image-preview" {
    let src = CommandLine.arguments[2]
    let filtersRaw = CommandLine.arguments[3]
    let out = CommandLine.arguments[4]
    guard let obj = editorFiltersJSON(filtersRaw) else {
        print("--image-preview: filters must be a JSON object or @file")
        exit(2)
    }
    var cg: CGImage?
    if CommandLine.arguments.contains("--blur") {
        let url = URL(fileURLWithPath: src)
        cg = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
            .flatMap { editorBlurredPreview($0, maxSize: 960) }
    } else {
        cg = imagePreviewCGImage(source: URL(fileURLWithPath: src),
                                 raw: EditorFilters(json: obj), maxSize: 960)
    }
    guard let cg else {
        print("--image-preview: cannot render \(src)")
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try png.write(to: URL(fileURLWithPath: out)) } catch {
        print("--image-preview: cannot write \(out)")
        exit(1)
    }
    print("\(out) \(cg.width)x\(cg.height)")
    exit(0)
}

let app = NSApplication.shared
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--wh-icon-debug" {
    let size = NSSize(width: 420, height: 120)
    let img = NSImage(size: size)
    img.lockFocus()
    NSColor.black.setFill(); NSRect(origin: .zero, size: size).fill()
    let glyphs = ["\u{f02e}", "\u{f096}", "\u{f00c}", "\u{f019}"]
    for (i, g) in glyphs.enumerated() {
        let box = NSRect(x: 10 + CGFloat(i) * 100, y: 15, width: 90, height: 90)
        let p = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        NSColor(white: 0.1, alpha: 1).setFill(); p.fill()
        NSColor.white.withAlphaComponent(0.2).setStroke(); p.lineWidth = 2; p.stroke()
        whDrawGlyphCentered(g, in: box, color: .white, size: 48)
    }
    img.unlockFocus()
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("wrote \(CommandLine.arguments[2])")
    }
    exit(0)
}
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--wallhaven-shot" {
    // Off-screen render for layout review. Never ordered front, so it cannot
    // steal focus from a running dashboard. Add `options`, `themes`,
    // `storage` or `keys` to pick a tab; default is the Wallpapers tab.
    app.setActivationPolicy(.accessory)
    let shotH: CGFloat = CommandLine.arguments.contains("tall") ? 1200 : 720
    let root = RootView(frame: NSRect(x: 0, y: 0, width: 860, height: shotH))
    let win = NSWindow(contentRect: root.frame, styleMask: .borderless,
                       backing: .buffered, defer: false)
    win.contentView = root
    let args = CommandLine.arguments
    var tabIndex = 3
    if args.contains("options") { tabIndex = 0 }
    else if args.contains("themes") { tabIndex = 2 }
    else if args.contains("storage") { tabIndex = 4 }
    else if args.contains("keys") { tabIndex = 5 }
    root.showTab(tabIndex)
    if tabIndex == 3 {
        if args.contains("more"),
           let tab = root.subviews.compactMap({ $0 as? WallpapersTabView }).first {
            tab.setMoreFilters(true)
        }
        root.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            if let tab = root.subviews.compactMap({ $0 as? WallpapersTabView }).first,
               !tab.debugGridInfo().contains("searching=true") { break }
        }
        let settle = Date().addingTimeInterval(1.5)
        while Date() < settle { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
        if args.contains("hover"),
           let tab = root.subviews.compactMap({ $0 as? WallpapersTabView }).first {
            tab.debugPreviewStates()
        }
        if args.contains("toast"),
           let tab = root.subviews.compactMap({ $0 as? WallpapersTabView }).first {
            tab.debugToast()
        }
        if args.contains("bookmarks"),
           let tab = root.subviews.compactMap({ $0 as? WallpapersTabView }).first {
            tab.debugShowBookmarks(2)
        }
    } else {
        let settle = Date().addingTimeInterval(1.5)
        while Date() < settle { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
        if args.contains("hoverTheme"),
           let tab = root.subviews.compactMap({ $0 as? ThemesTabView }).first {
            tab.debugHoverFirstCustom()
        }
        if let tab = root.subviews.compactMap({ $0 as? ThemesTabView }).first {
            if args.contains("applied") { tab.debugSetStatus("Applied 4chan Permanent Underclass") }
            if args.contains("selected") { tab.debugSelectFirstCustom(2) }
        }
    }
    root.layoutSubtreeIfNeeded()
    guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { exit(1) }
    root.cacheDisplay(in: root.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("wrote \(CommandLine.arguments[2])")
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
