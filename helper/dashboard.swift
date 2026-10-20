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
    // Selected field text, the same pair the active workspace pill uses:
    // accent as the fill, barBG as the ink. Deriving it from the palette
    // replaces AppKit's system blue, which ignores the theme and can leave
    // a light label unreadable on top of it.
    var selectionBackground: NSColor { accent }
    var selectionForeground: NSColor { barBG }
}

// One NSTextView is the field editor for every control in a window, so its
// selection colours are set once per focus rather than per NSTextField. This
// covers workspace and theme names, the wallpaper search, the name prompt,
// and the numeric editor fields alike.
func applySelectionColors(to editor: NSTextView) {
    editor.selectedTextAttributes = [
        .backgroundColor: palette.selectionBackground,
        .foregroundColor: palette.selectionForeground,
    ]
}

// A theme can change while a field has the keyboard, so re-apply to each
// window's live field editor instead of waiting for the next focus.
func refreshSelectionColors() {
    for window in NSApp.windows {
        guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { continue }
        applySelectionColors(to: editor)
    }
}

// Clicking, tabbing into or programmatically focusing a text field all go
// through the window's makeFirstResponder. By the time super returns, the
// shared field editor is first responder, and setting the selection colours
// here lands before it draws the select-all highlight. The begin-editing
// notification is too late: it is not posted until the first keystroke.
class ThemedWindow: NSWindow {
    @discardableResult
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        // the field losing the keyboard must repaint too, or its focus ring
        // stays behind after the next field takes focus
        let previous = (firstResponder as? NSTextView)?.delegate as? NSView
        let ok = super.makeFirstResponder(responder)
        if ok, let editor = firstResponder as? NSTextView, editor.isFieldEditor {
            applySelectionColors(to: editor)
            (editor.delegate as? NSView)?.needsDisplay = true
        }
        previous?.needsDisplay = true
        return ok
    }
}

// The picker's search is the one field AppKit would draw a focus ring for,
// in the system accent. Draw it in the theme's accent instead, around the
// field's own bezel; a field without the keyboard draws no ring.
final class ThemedSearchField: NSSearchField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard currentEditor() != nil else { return }
        let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
        palette.accent.setStroke()
        ring.lineWidth = 1
        ring.stroke()
    }
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

// omniwmctl, from whichever install location has it (same list as bar.swift)
let omniwmctlBin = ["/opt/homebrew/bin/omniwmctl",
                    "/Applications/OmniWM.app/Contents/MacOS/omniwmctl"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "omniwmctl"

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
enum BordersMode: Int { case small = 0, medium = 1, large = 2 }
enum BarMode: Int { case visible = 0, hidden = 1, auto = 2 }
enum TerminalThemeMode: Int { case own = 0, follow = 1 }
enum WeatherUnit: Int { case celsius = 0, fahrenheit = 1 }

enum LauncherChoice: String, CaseIterable {
    case auto, raycast, tinycast, alfred, omniwm, none

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .raycast: return "Raycast"
        case .tinycast: return "Tinycast"
        case .alfred: return "Alfred"
        case .omniwm: return "OmniWM"
        case .none: return "None"
        }
    }

    func displayTitle(omniwm: Bool) -> String { title }

    static func options(omniwm: Bool) -> [(choice: LauncherChoice, label: String)] {
        if omniwm {
            return [(.auto, "Auto"), (.raycast, "Raycast"),
                    (.tinycast, "Tinycast"), (.alfred, "Alfred"),
                    (.omniwm, "OmniWM"), (.none, "None")]
        }
        return [(.auto, "Auto"), (.raycast, "Raycast"),
                (.tinycast, "Tinycast"), (.alfred, "Alfred"), (.none, "None")]
    }

    static func menuIndex(for choice: LauncherChoice, omniwm: Bool) -> Int {
        let opts = options(omniwm: omniwm)
        return opts.firstIndex(where: { $0.choice == choice }) ?? 0
    }

    static func choice(at index: Int, omniwm: Bool) -> LauncherChoice {
        let opts = options(omniwm: omniwm)
        return opts.indices.contains(index) ? opts[index].choice : .auto
    }
}

struct DashboardState {
    var wm: WindowManager = .aerospace
    var corners: CornerMode = .rounded
    var borders: BordersMode = .large
    var ghosttyShadow: Bool = true
    var bar: BarMode = .visible
    var fullscreen: Bool = false
    var termTheme: TerminalThemeMode = .own
    var weatherUnit: WeatherUnit = .celsius
    var launcher: LauncherChoice = .auto
}

// The three widths behind the S/M/L segmented control, and the width a live
// borders.conf maps back to. Anything above the top step still reads large.
func bordersWidth(_ m: BordersMode) -> CGFloat {
    switch m { case .small: return 1; case .medium: return 2; case .large: return 3 }
}
func bordersMode(forWidth w: CGFloat) -> BordersMode {
    if w <= 1.5 { return .small }
    if w <= 2.5 { return .medium }
    return .large
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

    s.borders = bordersMode(forWidth: borderWidth())
    // Ghostty's own macOS window shadow: absent means its default, on.
    s.ghosttyShadow = (readConfKey(SETTINGS, "GHOSTTY_WINDOW_SHADOW") ?? "on") != "off"

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

    s.weatherUnit = readWeatherUnit()

    let rawLauncher = readConfKey(SETTINGS, "LAUNCHER") ?? "auto"
    s.launcher = LauncherChoice(rawValue: rawLauncher) ?? .auto
    // OmniWM's launcher cannot work under AeroSpace; show Auto instead of
    // leaving the row on a value the picker cannot offer.
    if s.wm == .aerospace, s.launcher == .omniwm { s.launcher = .auto }
    return s
}

// The weather scale lives in ~/.config/omacosy/weather.json, written by
// omacosy-weather. Absent, unreadable or unknown all mean the bar's own
// default, celsius, so the row is truthful on a machine that never set it.
func weatherUnit(fromJSON data: Data?) -> WeatherUnit {
    guard let data,
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let unit = obj["unit"] as? String
    else { return .celsius }
    return unit.lowercased() == "fahrenheit" ? .fahrenheit : .celsius
}

func readWeatherUnit() -> WeatherUnit {
    weatherUnit(fromJSON: FileManager.default.contents(atPath: HOME + "/.config/omacosy/weather.json"))
}

func weatherUnitSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)"); if !ok { failures += 1 }
    }
    check("absent -> celsius", weatherUnit(fromJSON: nil) == .celsius)
    check("fahrenheit parsed", weatherUnit(fromJSON: Data(#"{"unit":"fahrenheit"}"#.utf8)) == .fahrenheit)
    check("celsius parsed", weatherUnit(fromJSON: Data(#"{"unit":"celsius"}"#.utf8)) == .celsius)
    check("case-insensitive", weatherUnit(fromJSON: Data(#"{"unit":"Fahrenheit"}"#.utf8)) == .fahrenheit)
    check("unknown unit -> celsius", weatherUnit(fromJSON: Data(#"{"unit":"kelvin"}"#.utf8)) == .celsius)
    check("location only -> celsius", weatherUnit(fromJSON: Data(#"{"location":"Lyon"}"#.utf8)) == .celsius)
    check("garbage -> celsius", weatherUnit(fromJSON: Data("not json".utf8)) == .celsius)
    print(failures == 0 ? "weather-unit selftest: all checks passed"
                        : "weather-unit selftest: \(failures) failed")
    return failures
}
func launcherChoiceSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)"); if !ok { failures += 1 }
    }
    let air = LauncherChoice.options(omniwm: false).map { $0.label }
    let omni = LauncherChoice.options(omniwm: true).map { $0.label }
    check("AeroSpace hides OmniWM", !air.contains("OmniWM"))
    check("Auto is first", air.first == "Auto" && omni.first == "Auto")
    check("AeroSpace keeps None", air.contains("None"))
    check("OmniWM is offered", omni.contains("OmniWM"))
    check("Auto round-trips", LauncherChoice.choice(at: 0, omniwm: true) == .auto)
    check("OmniWM falls back to Auto", LauncherChoice.menuIndex(for: .omniwm, omniwm: false) == 0)
    check("None is last", air.last == "None" && omni.last == "None")
    check("plain title", LauncherChoice.auto.displayTitle(omniwm: false) == "Auto" && LauncherChoice.tinycast.displayTitle(omniwm: true) == "Tinycast")
    print(failures == 0 ? "launcher-choice selftest: all checks passed"
                        : "launcher-choice selftest: \(failures) failed")
    return failures
}
if CommandLine.arguments.contains("--launcher-choice-selftest") {
    exit(launcherChoiceSelfTest() == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--weather-unit-selftest") {
    exit(weatherUnitSelfTest() == 0 ? 0 : 1)
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

// The border width the focused-window ring and every Omacosy-drawn modal
// share, from ~/.config/omacosy/borders.conf. The ring daemon reads the same
// number, so one line drives windows and modals together. Absent means the
// shipped 3 (large). The Borders row in the Options tab writes it back.
func borderWidth() -> CGFloat {
    let path = HOME + "/.config/omacosy/borders.conf"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return 3 }
    for raw in text.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
        if line[..<eq].trimmingCharacters(in: .whitespaces) == "width",
           let v = Double(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)) {
            return CGFloat(v)
        }
    }
    return 3
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
        // Rounded: the macOS shape — one outline on the track, only the chosen
        // segment filled. Square: no container at all; each cell is its own
        // button with its own fill and border, so the group never reads as a
        // box the cells sit inside.
        let rounded = windowCornerRadius(6) > 2
        let f = nerdFont("Regular", 12)
        let bf = nerdFont("Bold", 12)
        if rounded {
            let track = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(8), yRadius: windowCornerRadius(8))
            palette.itemBG.withAlphaComponent(0.55).setFill()
            track.fill()
            palette.accent.withAlphaComponent(0.30).setStroke()
            track.lineWidth = 1
            track.stroke()
        }
        for (i, r) in segFrames.enumerated() {
            if rounded {
                if i == index {
                    let pill = NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
                    palette.accent.withAlphaComponent(0.9).setFill()
                    pill.fill()
                }
            } else {
                // its own border, and the selected cell's border is the same
                // accent as its fill, so it reads as one solid button
                let box = NSBezierPath(rect: r)
                if i == index {
                    palette.accent.withAlphaComponent(0.9).setFill()
                    palette.accent.withAlphaComponent(0.9).setStroke()
                } else {
                    palette.itemBG.withAlphaComponent(0.55).setFill()
                    palette.muted.withAlphaComponent(0.35).setStroke()
                }
                box.lineWidth = 1
                box.fill()
                box.stroke()
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
        let r = NSBezierPath(roundedRect: box, xRadius: windowCornerRadius(4), yRadius: windowCornerRadius(4))
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
        let track = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(5), yRadius: windowCornerRadius(5))
        if isOn {
            palette.accent.setFill(); track.fill()
        } else {
            palette.itemBG.withAlphaComponent(0.45).setFill(); track.fill()
            palette.muted.withAlphaComponent(0.5).setStroke(); track.lineWidth = 1; track.stroke()
        }
        let ks = bounds.height - 8
        let kx = isOn ? bounds.width - ks - 4 : 4
        let knob = NSBezierPath(roundedRect: NSRect(x: kx, y: 4, width: ks, height: ks),
                                xRadius: windowCornerRadius(4), yRadius: windowCornerRadius(4))
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
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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

// The floating arrow over the Themes gallery. It sits above the scroll view,
// so it needs an opaque backdrop to stay legible over any thumbnail; the
// arrow points the way the last scroll went and takes the user straight to
// that end of the shelf.
final class ScrollJumpButton: NSView {
    // true draws the arrow up (jump to the top), false down (jump to the bottom)
    var up = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    // a wheel over the button belongs to the gallery behind it
    var onScrollWheel: ((NSEvent) -> Void)?
    private var pressed = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                               xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
        palette.barBG.withAlphaComponent(0.92).setFill()
        box.fill()
        palette.muted.withAlphaComponent(0.5).setStroke()
        box.lineWidth = 1
        box.stroke()
        whDrawGlyphCentered(up ? "\u{f062}" : "\u{f063}", in: bounds,
                            color: palette.label, size: 13)
        if pressed {
            NSColor.black.withAlphaComponent(0.22).setFill()
            box.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        onClick?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.pressed = false
        }
    }
    override func scrollWheel(with event: NSEvent) { onScrollWheel?(event) }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
    let drop: WHDropdown?
    let slider: OpacitySliderView?
    let check: CheckView?
    let toggle: ToggleView?

    init(category: String, title: String, desc: String,
         seg: SegmentedView? = nil, drop: WHDropdown? = nil,
         slider: OpacitySliderView? = nil,
         check: CheckView? = nil, toggle: ToggleView? = nil) {
        self.category = category
        self.title = title
        self.desc = desc
        self.seg = seg
        self.drop = drop
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
    // 11 puts the first category title's centre on the shared 16 pt line that
    // every tab's first title uses (see the other tabs' first draw call).
    private let topPad: CGFloat = 11

    func contentHeight() -> CGFloat {
        var h = topPad
        for (i, _) in rows.enumerated() {
            if headsCategory(i) { h += catH }
            h += rowH + sectionGap
        }
        return h + 10
    }

    // A category heading is drawn once per run of rows: two rows that share a
    // category (Window & UI Corners, Borders, Ghostty Window Shadow) sit under
    // one heading instead of repeating it.
    private func headsCategory(_ i: Int) -> Bool {
        i == 0 || rows[i].category != rows[i - 1].category
    }

    override func layout() {
        super.layout()
        var top = topPad
        for (i, row) in rows.enumerated() {
            if headsCategory(i) { top += catH }
            if let seg = row.seg {
                let sz = seg.sizeThatFits()
                let segTop = top + (rowH - sz.height) / 2
                seg.frame = NSRect(x: bounds.width - sz.width,
                                   y: bounds.height - segTop - sz.height,
                                   width: sz.width, height: sz.height)
            }
            if let drop = row.drop {
                let sz = drop.sizeThatFits()
                let dTop = top + (rowH - sz.height) / 2
                drop.frame = NSRect(x: bounds.width - sz.width,
                                    y: bounds.height - dTop - sz.height,
                                    width: sz.width, height: sz.height)
            }
            if let slider = row.slider {
                let w: CGFloat = 176
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
        for (i, row) in rows.enumerated() {
            if headsCategory(i) {
                drawTopLeft(row.category, nerdFont("Bold", 13), palette.accent,
                            x: 0, top: top, height: bounds.height)
                top += catH
            }
            let rowMid = top + 20
            drawMidLeft(row.title, nerdFont("Bold", 13), palette.label,
                        x: 0, midTop: rowMid, height: bounds.height)
            // keep the description clear of the row's control on the right,
            // wrapping to a second line when it is long
            var controlMinX = bounds.width
            if let seg = row.seg { controlMinX = min(controlMinX, bounds.width - seg.sizeThatFits().width) }
            if let drop = row.drop { controlMinX = min(controlMinX, bounds.width - drop.sizeThatFits().width) }
            if row.slider != nil { controlMinX = min(controlMinX, bounds.width - 220) }
            if let check = row.check { controlMinX = min(controlMinX, bounds.width - check.sizeThatFits().width) }
            if let toggle = row.toggle { controlMinX = min(controlMinX, bounds.width - toggle.sizeThatFits().width) }
            let descW = max(140, controlMinX - 18)
            let descLines = wrapText(row.desc, nerdFont("Regular", 11), descW, maxLines: 2)
            for (li, line) in descLines.enumerated() {
                drawMidLeft(line, nerdFont("Regular", 11), palette.muted,
                            x: 0, midTop: rowMid + 18 + CGFloat(li) * 13, height: bounds.height)
            }
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
        for r in rows { r.drop?.needsDisplay = true }
        for r in rows { r.slider?.needsDisplay = true }
        for r in rows { r.check?.needsDisplay = true }
        for r in rows { r.toggle?.needsDisplay = true }
        // the Save button rounds its corners too, so a saved Window & UI
        // Corners or Borders change must repaint it with the rest
        saveButton.needsDisplay = true
        scroller.refresh()
    }
    // test door: the corner-drawing pieces a repaint must cover
    func debugDirtyFlags() -> [String: Bool] {
        var out: [String: Bool] = ["doc": doc.needsDisplay, "saveButton": saveButton.needsDisplay]
        for (i, r) in rows.enumerated() {
            if let s = r.seg { out["seg\(i)"] = s.needsDisplay }
            if let s = r.drop { out["drop\(i)"] = s.needsDisplay }
            if let s = r.slider { out["slider\(i)"] = s.needsDisplay }
            if let s = r.check { out["check\(i)"] = s.needsDisplay }
            if let s = r.toggle { out["toggle\(i)"] = s.needsDisplay }
        }
        return out
    }
    // test door: clear every flag so refreshColors() can be shown to set them
    func debugClearDirty() {
        needsDisplay = false
        doc.needsDisplay = false
        for r in rows {
            r.seg?.needsDisplay = false
            r.drop?.needsDisplay = false
            r.slider?.needsDisplay = false
            r.check?.needsDisplay = false
            r.toggle?.needsDisplay = false
        }
        saveButton.needsDisplay = false
    }
    private var original = DashboardState()
    private var launcherChoice: LauncherChoice = .auto
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
        let omniwmSelected = original.wm == .omniwm
        let launcherDrop = WHDropdown()
        let launcherOptions = LauncherChoice.options(omniwm: omniwmSelected)
        launcherDrop.items = launcherOptions.map { $0.label }
        launcherDrop.selectedIndex = LauncherChoice.menuIndex(for: original.launcher, omniwm: omniwmSelected)
        launcherDrop.title = original.launcher.displayTitle(omniwm: omniwmSelected)
        launcherDrop.accentAtRest = true
        launcherDrop.controlWidth = 150
        launcherDrop.menuWidth = 150
        launcherDrop.toolTip = "Launcher"
        launcherChoice = original.launcher
        launcherDrop.onPick = { [weak self, weak launcherDrop] i in
            guard let self, let drop = launcherDrop else { return }
            let choice = LauncherChoice.choice(at: i, omniwm: self.isOmniwmSelected)
            self.launcherChoice = choice
            drop.title = choice.displayTitle(omniwm: self.isOmniwmSelected)
            drop.needsDisplay = true
        }
        let cornerSeg = makeSeg(["Rounded", "Square"], original.corners.rawValue)
        let bordersSeg = makeSeg(["S", "M", "L"], original.borders.rawValue)
        let shadowToggle = ToggleView()
        shadowToggle.isOn = original.ghosttyShadow
        let barSeg = makeSeg(["Visible", "Hidden", "Auto"], original.bar.rawValue)
        let fsToggle = ToggleView()
        fsToggle.isOn = original.fullscreen
        let atSeg = makeSeg(["Own Colours", "Follow Theme"], original.termTheme.rawValue)

        let opacitySlider = OpacitySliderView()
        opacitySlider.value = readGlobalToolOpacity() ?? readTerminalOpacity() ?? 100
        opacitySlider.onChange = { [weak self] _ in self?.doc.needsDisplay = true }

        let nsfwToggle = ToggleView()
        nsfwToggle.isOn = WHConfig.load().hideNSFW

        let weatherSeg = makeSeg(["Celsius", "Fahrenheit"], original.weatherUnit.rawValue)

        rows = [
            OptionRow(category: "Window Manager", title: "Window Manager",
                      desc: "Which tiling manager Omacosy switches to. Switching reloads Omacosy for a moment.",
                      seg: wmSeg),
            OptionRow(category: "Window Manager", title: "Launcher",
                      desc: "What Super+Space opens.",
                      drop: launcherDrop),
            OptionRow(category: "Windows", title: "Window & UI Corners",
                      desc: "MacOS window corners and Omacosy UI components outside the menu bar and the Workspaces overview.", seg: cornerSeg),
            OptionRow(category: "Windows", title: "Borders",
                      desc: "Focused window ring border thickness. Small = 1 px, Medium = 2 px, Large = 3 px (default).", seg: bordersSeg),
            OptionRow(category: "Windows", title: "Ghostty Window Shadow",
                      desc: "Ghostty's window shadow. Off = no black rim. Looks better with 1 px focused window ring",
                      toggle: shadowToggle),
            OptionRow(category: "Bar", title: "Menu Bar Mode",
                      desc: "Keep the bar visible, let it hide at rest, or follow the display.", seg: barSeg),
            OptionRow(category: "Fullscreen", title: "Full Screen Mode",
                      desc: "A workspace holding one window fills the display.", toggle: fsToggle),
            OptionRow(category: "Themes", title: "Terminal Auto-Theme",
                      desc: "Let the terminal and its apps follow the wallpaper theme, or keep their own colours.", seg: atSeg),
            OptionRow(category: "Appearance", title: "Terminal Opacity",
                      desc: "How see-through the terminal and its tools are. Every theme that inherits it follows.",
                      slider: opacitySlider),
            OptionRow(category: "Weather", title: "Weather Units",
                      desc: "The scale the weather pill and its popup show.",
                      seg: weatherSeg),
            OptionRow(category: "Content", title: "Hide NSFW Content",
                      desc: "Hide adult wallhaven results and anything downloaded from them, everywhere. Nothing is deleted.",
                      toggle: nsfwToggle),
        ]
        doc.rows = rows
        wmSeg.onChange = { [weak self] i in self?.wmSelectionChanged(omniwm: i == 1) }
        for r in rows {
            if let s = r.seg { doc.addSubview(s) }
            if let d = r.drop { doc.addSubview(d) }
            if let sl = r.slider { doc.addSubview(sl) }
            if let c = r.check { doc.addSubview(c) }
            if let t = r.toggle { doc.addSubview(t) }
        }
    }

    private var isOmniwmSelected: Bool {
        (rows.first(where: { $0.title == "Window Manager" })?.seg?.index ?? original.wm.rawValue) == 1
    }

    private func wmSelectionChanged(omniwm: Bool) {
        guard let drop = rows.first(where: { $0.title == "Launcher" })?.drop else { return }
        var choice = launcherChoice
        if !omniwm, choice == .omniwm { choice = .auto }
        let opts = LauncherChoice.options(omniwm: omniwm)
        launcherChoice = choice
        drop.items = opts.map { $0.label }
        drop.selectedIndex = LauncherChoice.menuIndex(for: choice, omniwm: omniwm)
        drop.title = choice.displayTitle(omniwm: omniwm)
        drop.needsDisplay = true
        doc.needsLayout = true
        doc.needsDisplay = true
        doc.layoutSubtreeIfNeeded()
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
        // look rows up by title, not by position: the list grows, and a fixed
        // index silently points at the wrong row the moment a row is inserted
        func segIndex(_ title: String) -> Int? { rows.first { $0.title == title }?.seg?.index }
        func toggleValue(_ title: String) -> Bool? { rows.first { $0.title == title }?.toggle?.isOn }

        let wm = WindowManager(rawValue: segIndex("Window Manager") ?? original.wm.rawValue) ?? original.wm
        let corners = CornerMode(rawValue: segIndex("Window & UI Corners") ?? original.corners.rawValue) ?? original.corners
        let borders = BordersMode(rawValue: segIndex("Borders") ?? original.borders.rawValue) ?? original.borders
        let bar = BarMode(rawValue: segIndex("Menu Bar Mode") ?? original.bar.rawValue) ?? original.bar
        let fullscreen = toggleValue("Full Screen Mode") ?? original.fullscreen
        let termTheme = TerminalThemeMode(rawValue: segIndex("Terminal Auto-Theme") ?? original.termTheme.rawValue) ?? original.termTheme
        let ghosttyShadow = toggleValue("Ghostty Window Shadow") ?? original.ghosttyShadow
        let launcher = launcherChoice

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
        if launcher != original.launcher {
            steps.append("\(HOME)/.local/bin/omacosy-launcher set \(launcher.rawValue)")
        }
        if corners != original.corners {
            setConfKey(SETTINGS, "WINDOW_CORNER", corners == .square ? "0.1" : "")
            steps.append("\(HOME)/.local/bin/omacosy-window-corners \(corners == .square ? "square" : "round")")
        }
        if borders != original.borders {
            setConfKey(SETTINGS, "BORDER_WIDTH", ["small", "medium", "large"][borders.rawValue])
            steps.append("\(HOME)/.local/bin/omacosy-window-corners --width \(Int(bordersWidth(borders)))")
        }
        if ghosttyShadow != original.ghosttyShadow {
            // the command records the choice in settings.conf itself
            steps.append("\(HOME)/.local/bin/omacosy-ghostty-shadow \(ghosttyShadow ? "on" : "off")")
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
        if let seg = rows.first(where: { $0.category == "Weather" })?.seg {
            let unit = WeatherUnit(rawValue: seg.index) ?? original.weatherUnit
            if unit != original.weatherUnit {
                steps.append("\(HOME)/.local/bin/omacosy-weather unit \(unit == .fahrenheit ? "fahrenheit" : "celsius")")
            }
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

// The app shelf is read once, off the main thread. Reading every
// Contents/Info.plist in /Applications blocked the modal's first paint; this
// keeps the window responsive and hands the same list to every caller.
final class AppCatalog {
    static let shared = AppCatalog()
    private(set) var apps: [AppInfo] = []
    private var loaded = false
    private var loading = false
    private var waiters: [([AppInfo]) -> Void] = []

    private init() {}

    func load(_ done: @escaping ([AppInfo]) -> Void) {
        if loaded { done(apps); return }
        waiters.append(done)
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = installedApps()
            DispatchQueue.main.async {
                self.apps = list
                self.loaded = true
                self.loading = false
                let callbacks = self.waiters
                self.waiters.removeAll()
                for callback in callbacks { callback(list) }
            }
        }
    }
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
                // the raw name is the workspace's identity: app rules and
                // names are keyed on it. displayName is only a label — the
                // user's own name for the workspace, shown by the row.
                guard let did = (w["display"] as? [String: Any])?["id"] as? String,
                      let rn = w["rawName"] as? String else { continue }
                byDisp[did, default: []].append(rn)
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

// The index of the first quote that is NOT escaped by a backslash: a name
// may hold a `\"` of its own, so only an unescaped quote ends the block.
private func closeQuoteIndex(_ s: String) -> String.Index? {
    var escaped = false
    for i in s.indices {
        let c = s[i]
        if escaped { escaped = false; continue }
        if c == "\\" { escaped = true; continue }
        if c == "\"" { return i }
    }
    return nil
}

// A multi-line shell string in settings.conf holds its value between the
// quotes, so its lines are read from the FILE — the dashboard never sources
// it. nil = the key is not there. These two and the escape pair below have
// a copy in helper/overview.swift; keep them in step.
func readConfBlock(_ key: String, _ file: String = SETTINGS) -> [String]? {
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
    var found = false
    var out: [String] = []
    var inBlock = false
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if !inBlock {
            guard line.hasPrefix("\(key)=") else { continue }
            found = true
            let after = line.dropFirst(key.count + 1)
            guard after.hasPrefix("\"") else { return nil }
            let rest = String(after.dropFirst())
            if let q = closeQuoteIndex(rest) {
                return rest[rest.startIndex..<q]
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            inBlock = true
            continue
        }
        if let q = closeQuoteIndex(line) {
            let head = String(line[line.startIndex..<q]).trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { out.append(head) }
            return out
        }
        if !line.trimmingCharacters(in: .whitespaces).isEmpty { out.append(line) }
    }
    return found ? out : nil
}

// settings.conf is read by the shell with `source`: inside the quotes a
// backslash is eaten and $ or a backtick would expand. The writer escapes
// those four characters; every reader undoes it.
func escapeConfValue(_ s: String) -> String {
    var out = ""
    for c in s {
        switch c {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "$": out += "\\$"
        case "`": out += "\\`"
        default: out.append(c)
        }
    }
    return out
}

func unescapeConfValue(_ s: String) -> String {
    var out = ""
    var it = s.makeIterator()
    while let c = it.next() {
        guard c == "\\", let n = it.next() else { out.append(c); continue }
        switch n {
        case "\\", "\"", "$", "`": out.append(n)
        default: out += "\\"; out.append(n)
        }
    }
    return out
}

@discardableResult
func writeConfBlock(_ key: String, _ body: [String], _ file: String = SETTINGS) -> Bool {
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return false }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var out: [String] = []
    var i = 0
    var replaced = false
    while i < lines.count {
        let line = lines[i]
        if line.hasPrefix("\(key)=") && !replaced {
            out.append("\(key)=\"")
            out.append(contentsOf: body)
            out.append("\"")
            replaced = true
            let after = line.dropFirst(key.count + 1)
            if after.hasPrefix("\""), closeQuoteIndex(String(after.dropFirst())) != nil {
                i += 1
            } else {
                i += 1
                while i < lines.count {
                    if closeQuoteIndex(lines[i]) != nil { break }
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
        out.append("\(key)=\"")
        out.append(contentsOf: body)
        out.append("\"")
    }
    var result = out.joined(separator: "\n")
    if !result.hasSuffix("\n") { result += "\n" }
    do { try result.write(toFile: file, atomically: true, encoding: .utf8); return true }
    catch { return false }
}

// APP_WORKSPACE_RULES is a multi-line shell string: "<bundle id> <workspace>"
// per line.
func readWorkspaceRules(_ file: String = SETTINGS) -> [(String, String)] {
    guard let lines = readConfBlock("APP_WORKSPACE_RULES", file) else { return [] }
    var out: [(String, String)] = []
    for line in lines {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if parts.count >= 2 { out.append((parts[0], parts[1])) }
    }
    return out
}

@discardableResult
func writeWorkspaceRules(_ pairs: [(String, String)]) -> Bool {
    writeConfBlock("APP_WORKSPACE_RULES", pairs.map { "\($0.0)    \($0.1)" })
}

// WORKSPACE_NAMES is "<workspace> <display name>" per line, the name holding
// spaces. The Workspaces tab writes it; omacosy-settings applies it to
// OmniWM's built-in per-workspace displayName; the overview draws it under
// both managers (an AeroSpace workspace has no name of its own beyond the
// numeric one, which the slots depend on).
func readWorkspaceNames(_ file: String = SETTINGS) -> [String: String] {
    guard let lines = readConfBlock("WORKSPACE_NAMES", file) else { return [:] }
    var out: [String: String] = [:]
    for line in lines {
        let t = line.trimmingCharacters(in: .whitespaces)
        let parts = t.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count == 2 else { continue }
        let name = unescapeConfValue(parts[1].trimmingCharacters(in: .whitespaces))
        if !name.isEmpty { out[parts[0]] = name }
    }
    return out
}

@discardableResult
func writeWorkspaceNames(_ names: [String: String], _ file: String = SETTINGS) -> Bool {
    let body = names.keys.sorted(by: numericAsc).compactMap { ws -> String? in
        guard let n = names[ws], !n.isEmpty else { return nil }
        return "\(ws)    \(escapeConfValue(n))"
    }
    return writeConfBlock("WORKSPACE_NAMES", body, file)
}

final class AppListView: NSView {
    var apps: [AppInfo] = []
    var onPick: ((String) -> Void)?
    var selected: Int = 0
    let rowH: CGFloat = 30
    // Icons arrive per visible row on a background queue. The old draw asked
    // LaunchServices for every app in the list before the picker could paint,
    // which is where the spinning wheel came from.
    private var icons: [String: NSImage] = [:]
    private var pendingIcons: Set<String> = []

    private func rowRect(_ i: Int) -> NSRect {
        let top = CGFloat(i) * rowH
        return NSRect(x: 0, y: bounds.height - top - rowH, width: bounds.width, height: rowH)
    }

    private func invalidateRow(_ id: String) {
        guard let i = apps.firstIndex(where: { $0.bundleID == id }) else { return }
        setNeedsDisplay(rowRect(i))
    }

    private func queueIcon(_ app: AppInfo) {
        guard icons[app.bundleID] == nil, !pendingIcons.contains(app.bundleID) else { return }
        if let cached = appIconCache[app.bundleID] {
            icons[app.bundleID] = cached
            return
        }
        pendingIcons.insert(app.bundleID)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = NSWorkspace.shared.icon(forFile: app.path)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingIcons.remove(app.bundleID)
                self.icons[app.bundleID] = image
                appIconCache[app.bundleID] = image
                self.invalidateRow(app.bundleID)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // A full-view invalidation (selection, search) can carry the whole
        // 13k-tall document in dirtyRect; only the viewport should ask for
        // icons.
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        for (i, a) in apps.enumerated() {
            let r = rowRect(i)
            guard r.intersects(dirtyRect) else { continue }
            if i == selected, apps.indices.contains(selected) {
                // the same accent the custom scrollers use, so a chosen row
                // reads as "the one the arrows are on"
                palette.accent.withAlphaComponent(0.85).setFill()
                r.fill()
            } else if i % 2 == 1 {
                palette.itemBG.withAlphaComponent(0.25).setFill()
                r.fill()
            }
            let icon = icons[a.bundleID] ?? appIconCache[a.bundleID]
            if let icon {
                icons[a.bundleID] = icon
                icon.draw(in: NSRect(x: 6, y: r.midY - 8, width: 16, height: 16))
            } else if r.intersects(visible) {
                queueIcon(a)
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
    let search = ThemedSearchField()
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
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(10), yRadius: windowCornerRadius(10))
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

final class PickerWindow: ThemedWindow {
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
        NSBezierPath(roundedRect: box, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6)).fill()
        palette.muted.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(roundedRect: box, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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
    private let rowH: CGFloat = 24
    private let padX: CGFloat = 12
    private let padY: CGFloat = 3
    private var font: NSFont { nerdFont("Regular", 12) }

    static func size(for items: [String]) -> NSSize {
        let f = nerdFont("Regular", 12)
        let w = items.map { advance($0, f) }.max() ?? 80
        return NSSize(width: w + 24, height: CGFloat(items.count) * 24 + 6)
    }

    private func rowRect(_ i: Int) -> NSRect {
        let top = padY + CGFloat(i) * rowH
        return NSRect(x: 0, y: bounds.height - top - rowH, width: bounds.width, height: rowH)
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(7), yRadius: windowCornerRadius(7))
        palette.barBG.setFill(); card.fill()
        palette.muted.withAlphaComponent(0.22).setStroke(); card.lineWidth = 1; card.stroke()
        for (i, item) in items.enumerated() {
            let r = rowRect(i)
            if i == hovered {
                palette.accent.setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 4, dy: 1), xRadius: windowCornerRadius(5), yRadius: windowCornerRadius(5)).fill()
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
        // a system shadow reads as a thick black halo around a small menu
        window.hasShadow = false
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
    var allApps: [AppInfo]
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
            let chip = NSBezierPath(roundedRect: f, xRadius: windowCornerRadius(5), yRadius: windowCornerRadius(5))
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
        let add = NSBezierPath(roundedRect: addFrame, xRadius: windowCornerRadius(5), yRadius: windowCornerRadius(5))
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

final class WorkspaceRowView: NSView, NSTextFieldDelegate {
    let ws: String
    var assigned: [String]
    var allApps: [AppInfo]
    var displayName: String? { didSet { needsDisplay = true } }
    var onAssign: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    var onRename: ((String, String?) -> Void)?
    private var chipFrames: [(NSRect, String)] = []
    private var overflowApps: [String] = []
    private var moreFrame: NSRect = .zero
    private var expanded = false
    private let addButton = ButtonView()
    private let chipScroll = NSScrollView()
    private let chipStrip: ChipStrip
    // the inline name editor; hidden until the name or the pen is clicked
    let nameField = NSTextField()
    private let penButton = ButtonView()
    // [pill][name ....][✎][›][chips ....][＋ Add App]: the pill is a perfect
    // square — a circle in rounded-corner mode — so two-digit workspaces fit
    // it, and the pen keeps its own fixed column whatever the name's length
    private let pillSide: CGFloat = 26
    private let nameX: CGFloat = 36
    private let penX: CGFloat = 150
    private let penSide: CGFloat = 22
    private let chevronX: CGFloat = 178
    private let chipsX: CGFloat = 192
    // narrowed from 96 to pay for the pill: the "＋ Add App" label measures
    // 70 pt in Bold 12, so 80 still leaves a 5 pt margin each side
    private let addW: CGFloat = 80

    init(ws: String, assigned: [String], allApps: [AppInfo], displayName: String?) {
        self.ws = ws
        self.assigned = assigned
        self.allApps = allApps
        self.displayName = displayName
        self.chipStrip = ChipStrip(allApps: allApps)
        super.init(frame: .zero)
        addButton.title = "＋ Add App"
        addButton.onClick = { [weak self] in self?.showMenu() }
        addSubview(addButton)
        penButton.title = "\u{f040}"
        penButton.centeredByBounds = true
        penButton.fontSize = 11
        penButton.secondary = true
        penButton.toolTip = "Rename Workspace"
        penButton.onClick = { [weak self] in self?.startRenaming() }
        addSubview(penButton)
        nameField.isBezeled = false
        nameField.drawsBackground = true
        nameField.backgroundColor = palette.itemBG.withAlphaComponent(0.5)
        nameField.textColor = palette.label
        nameField.font = nerdFont("Bold", 12)
        nameField.focusRingType = .none
        nameField.usesSingleLineMode = true
        nameField.lineBreakMode = .byTruncatingTail
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.isHidden = true
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(nameReturn)
        addSubview(nameField)
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

    // The launch-time scan lands here: names and chip widths can now use the
    // real display names instead of their bundle ids.
    func updateApps(_ apps: [AppInfo]) {
        allApps = apps
        chipStrip.allApps = apps
        computeChips()
        needsLayout = true
        needsDisplay = true
        chipStrip.needsDisplay = true
    }

    private func chipLabel(_ id: String) -> String {
        let name = allApps.first(where: { $0.bundleID == id })?.name ?? id
        return truncate(name, nerdFont("Regular", 11), 150)
    }

    private func chipWidth(_ id: String) -> CGFloat {
        return 16 + 6 + advance(chipLabel(id), nerdFont("Regular", 11)) + 22
    }

    // --- the workspace name, edited in place ---

    private func nameText() -> String {
        displayName ?? "Workspace \(ws)"
    }

    // the name stops short of the pen's fixed column, whatever its length
    private func fittedName() -> (text: String, width: CGFloat) {
        let f = nerdFont("Bold", 12)
        let t = truncate(nameText(), f, penX - 10 - nameX)
        return (t, advance(t, f))
    }

    private var nameRect: NSRect {
        NSRect(x: nameX, y: (bounds.height - 24) / 2, width: fittedName().width, height: 24)
    }

    // both the name text and the pen button open the editor
    var renameZone: NSRect { nameRect.union(penButton.frame) }

    private(set) var editingName = false

    func startRenaming() {
        guard !editingName else { return }
        editingName = true
        nameField.stringValue = displayName ?? ""
        nameField.placeholderString = "Workspace \(ws)"
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.isHidden = false
        nameField.frame = NSRect(x: nameX, y: (bounds.height - 20) / 2,
                                 width: penX - 8 - nameX, height: 20)
        window?.makeFirstResponder(nameField)
        // select-all so a rename can just be typed; the field is single-line
        // and a name is not prose
        if let editor = nameField.currentEditor() {
            editor.selectedRange = NSRange(location: 0, length: (nameField.stringValue as NSString).length)
        }
        needsDisplay = true
    }

    func endRenaming(commit: Bool) {
        guard editingName else { return }
        editingName = false
        if commit {
            var v = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            v = v.replacingOccurrences(of: "\t", with: " ")
            while v.contains("  ") { v = v.replacingOccurrences(of: "  ", with: " ") }
            if v.count > 40 { v = String(v.prefix(40)).trimmingCharacters(in: .whitespaces) }
            let newName: String? = v.isEmpty ? nil : v
            if newName != displayName {
                displayName = newName
                onRename?(ws, newName)
            }
        }
        if let editor = nameField.currentEditor(), editor.window?.firstResponder === editor {
            window?.makeFirstResponder(nil)
        }
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.isHidden = true
        needsDisplay = true
    }

    @objc private func nameReturn() { endRenaming(commit: true) }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Esc cancels the edit and keeps the old name; every other way the
        // field can end (Return, focus loss) commits what is in it
        let movement = (obj.userInfo?["NSTextMovement"] as? Int) ?? 0
        endRenaming(commit: movement != NSCancelTextMovement)
    }

    // a workspace name is not prose: the field editor's red dotted spell
    // underline and smart substitutions have no business here
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let editor = obj.userInfo?["NSFieldEditor"] as? NSTextView else { return }
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isGrammarCheckingEnabled = false
    }

    // the field's colours are properties, not drawing, so a theme change
    // has to set them again
    func refreshFieldColors() {
        nameField.textColor = palette.label
        nameField.backgroundColor = palette.itemBG.withAlphaComponent(0.5)
    }

    // computed on every draw as well as on layout: a rebuild after a
    // removal does not always trigger layout(), and a stale overflow list is
    // exactly the "+N more" that would not come back
    private func computeChips() {
        chipFrames.removeAll()
        overflowApps.removeAll()
        moreFrame = .zero
        var x: CGFloat = chipsX
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
            let mx = chipFrames.last.map { $0.0.maxX + 8 } ?? chipsX
            moreFrame = NSRect(x: mx, y: (bounds.height - 24) / 2, width: 80, height: 24)
        }
    }

    override func layout() {
        super.layout()
        let w: CGFloat = addW, h: CGFloat = 24
        addButton.frame = NSRect(x: bounds.width - w, y: (bounds.height - h) / 2, width: w, height: h)
        penButton.frame = NSRect(x: penX, y: (bounds.height - penSide) / 2,
                                 width: penSide, height: penSide)
        computeChips()
        let stripX = chipsX
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
        // the slot pill: the workspace's own number, still visible after it
        // is given a name. A perfect square that becomes a circle in the
        // rounded-corner mode — the same windowCornerRadius > 2 rule the
        // segmented control uses
        let pillRect = NSRect(x: 0, y: (bounds.height - pillSide) / 2,
                              width: pillSide, height: pillSide)
        let pillPath: NSBezierPath = windowCornerRadius(6) > 2
            ? NSBezierPath(ovalIn: pillRect) : NSBezierPath(rect: pillRect)
        palette.itemBG.withAlphaComponent(0.6).setFill()
        pillPath.fill()
        drawMidCenter(ws, nerdFont("Bold", 12), palette.label,
                      centerX: pillRect.midX, midTop: bounds.height / 2, height: bounds.height)
        if !editingName {
            drawMidLeft(fittedName().text, nerdFont("Bold", 12), palette.label,
                        x: nameX, midTop: bounds.height / 2, height: bounds.height)
        }
        if !assigned.isEmpty, expanded || !overflowApps.isEmpty {
            drawMidLeft(expanded ? "‹" : "›", nerdFont("Bold", 12), palette.accent,
                        x: chevronX, midTop: bounds.height / 2, height: bounds.height)
        }
        if expanded { return }   // the horizontally scrollable strip draws them

        for (frame, id) in chipFrames {
            let name = chipLabel(id)
            let chip = NSBezierPath(roundedRect: frame, xRadius: windowCornerRadius(5), yRadius: windowCornerRadius(5))
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
                        x: chipsX, midTop: bounds.height / 2, height: bounds.height)
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
        // the name and its pen open the editor; before the expand check, or
        // a row with overflow would swallow the name click
        if !editingName, renameZone.contains(p) {
            startRenaming()
            return
        }
        if expanded {
            // the chips live in the strip subview, which folds the row itself
            // on a non-✕ tap; a click on the row body folds it too
            setExpanded(false)
            return
        }
        // the chevron/"+N more": expand into the scrollable strip
        if !overflowApps.isEmpty, (moreFrame.contains(p) || p.x < chipsX) {
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
            let stripX = chipsX
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
        func present(_ apps: [AppInfo]) {
            AppPicker.present(apps: apps, near: addButton, in: self) { [weak self] bundle in
                self?.onAssign?(bundle)
            }
        }
        guard allApps.isEmpty else { present(allApps); return }
        // A click in the first moments after launch: the scan is already in
        // flight, so show the press and open as soon as it lands.
        addButton.busyTitle = "Loading…"
        addButton.busy = true
        AppCatalog.shared.load { [weak self] apps in
            guard let self else { return }
            self.addButton.busy = false
            self.updateApps(apps)
            present(apps)
        }
    }
}

final class WorkspacesTabView: NSView, ScrollStepTab {
    private var screens: [ScreenInfo] = []
    func scrollStep(_ dy: CGFloat) { scrollBy(scroll, dy) }
    func refreshColors() {
        needsDisplay = true
        screenSeg.needsDisplay = true
        for r in rows { r.needsDisplay = true; r.refreshFieldColors(); r.subviews.forEach { $0.needsDisplay = true } }
        scroller.refresh()
    }
    private var allApps: [AppInfo] = []
    private var rules: [(String, String)] = []
    private var savedRules: [(String, String)] = []
    private var names: [String: String] = [:]
    private var savedNames: [String: String] = [:]
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
        // Start the scan at launch, but never block the first paint on it.
        AppCatalog.shared.load { [weak self] apps in self?.appsLoaded(apps) }
        rules = readWorkspaceRules()
        savedRules = rules
        names = readWorkspaceNames()
        savedNames = names
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
        // the open row folds it back, and a click outside the name field
        // commits the edit. Row lifetime does not matter here.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
            self?.commitNameEditIfOutside(e)
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

    // a click outside the name field commits the edit: in this app custom
    // views never take first responder away on their own, so nothing else
    // would end it
    private func commitNameEditIfOutside(_ e: NSEvent) {
        for r in rows where r.editingName {
            guard e.window === r.window else { r.endRenaming(commit: true); continue }
            let p = r.convert(e.locationInWindow, from: nil)
            if !r.nameField.frame.contains(p), !r.renameZone.contains(p) {
                r.endRenaming(commit: true)
            }
        }
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
        names = readWorkspaceNames()
        savedNames = names
        status = ""
        rebuildRows()
    }

    // called when the modal is shown again: unsaved edits are dropped
    func resetToSaved() { reloadFromDisk() }

    private var dirty: Bool {
        rules.map { "\($0.0) \($0.1)" }.sorted() != savedRules.map { "\($0.0) \($0.1)" }.sorted()
            || names != savedNames
    }

    private func assigned(for ws: String) -> [String] {
        rules.filter { $0.1 == ws }.map { $0.0 }
    }

    // The scan lands after the rows exist. Update them in place rather than
    // rebuilding, so an open rename field or expanded chip strip survives.
    private func appsLoaded(_ apps: [AppInfo]) {
        allApps = apps
        for row in rows { row.updateApps(apps) }
    }

    private func rebuildRows() {
        for r in rows { r.removeFromSuperview() }
        rows.removeAll()
        expandedRow = nil
        guard screens.indices.contains(screenIndex) else { return }
        for ws in screens[screenIndex].workspaces {
            let row = WorkspaceRowView(ws: ws, assigned: assigned(for: ws), allApps: allApps,
                                       displayName: names[ws])
            row.onAssign = { [weak self] bundle in self?.assign(bundle, to: ws) }
            row.onRemove = { [weak self] bundle in self?.unassign(bundle) }
            row.onRename = { [weak self] ws, name in self?.rename(ws, to: name) }
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

    private func rename(_ ws: String, to name: String?) {
        if let name { names[ws] = name } else { names.removeValue(forKey: ws) }
        needsDisplay = true
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
            drawMidLeft("Screen: \(s.name)", nerdFont("Bold", 13), palette.accent,
                        x: 0, midTop: 16, height: bounds.height)
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
        let names = self.names
        let rulesChanged = rules.map { "\($0.0) \($0.1)" }.sorted()
            != savedRules.map { "\($0.0) \($0.1)" }.sorted()
        // bundles taken out since the last save: omacosy-settings only adds
        // and corrects OmniWM rules, so these have to be pruned explicitly
        let removed = savedRules.map { $0.0 }.filter { b in !rules.contains { $0.0 == b } }
        // a CLEARED name must go back to the raw workspace name by hand:
        // omacosy-settings only applies the names the file still holds, and
        // OmniWM would keep showing the stale displayName forever
        let cleared = savedNames.keys.filter { names[$0] == nil }.sorted(by: numericAsc)
        // a names-only save skips omacosy-settings: its top-gap step
        // restarts the bar unconditionally, and renaming a workspace has no
        // business reloading it. The renames are issued directly instead; a
        // rules change still needs the full apply (aerospace.toml + OmniWM
        // rules), and its 6b applies the names the file now holds.
        var renames: [(String, String)] = []
        if !rulesChanged {
            for (ws, n) in names where savedNames[ws] != n { renames.append((ws, n)) }
        }
        renames += cleared.map { ($0, $0) }
        renames.sort { numericAsc($0.0, $1.0) }
        DispatchQueue.global().async { [weak self] in
            let wrote = writeWorkspaceRules(rules) && writeWorkspaceNames(names)
            var err = ""
            if wrote {
                if rulesChanged {
                    let (code, out) = shell("\(HOME)/.local/bin/omacosy-settings 2>&1")
                    if code != 0 {
                        err = out.split(separator: "\n").last.map(String.init) ?? ""
                    } else if !removed.isEmpty {
                        let args = removed.map(shellQuote).joined(separator: " ")
                        _ = shell("\(HOME)/.local/bin/omacosy-ws-prune \(args) 2>&1")
                    }
                }
                if err.isEmpty, !renames.isEmpty {
                    let cmds = renames.map {
                        "\(omniwmctlBin) workspace rename \(shellQuote($0.0)) \(shellQuote($0.1))"
                    }.joined(separator: "; ")
                    _ = shell("if \(HOME)/.local/bin/omacosy-omni active >/dev/null 2>&1; then \(cmds); fi")
                }
            } else { err = "could not write settings.conf" }
            DispatchQueue.main.async {
                self?.savedRules = rules
                self?.savedNames = names
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

// What is applied to the live desktop right now, for the Themes grid's
// Active pill: a stock theme name, a saved edition id, or a raw wallpaper
// path. Read from the same `current/theme` symlink everything else uses, so
// the pill can never disagree with the desktop.
enum ActiveTheme {
    case stock(String)
    case edition(String)
    case raw(String)
}

func activeThemeSpec() -> ActiveTheme? {
    let (code, out) = shell("\(HOME)/.local/bin/omacosy-custom-theme current 2>/dev/null")
    guard code == 0 else { return nil }
    let cur = out.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cur.isEmpty else { return nil }
    if cur.hasPrefix("theme:") { return .edition(String(cur.dropFirst("theme:".count))) }
    if cur == "custom" {
        guard let raw = try? String(contentsOfFile: HOME + "/.local/state/omacosy/custom-index",
                                    encoding: .utf8) else { return nil }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : .raw(path)
    }
    return .stock(cur)
}

// The day=/night= spec that names a cell: a saved edition by its record id,
// a raw wallpaper by its path, a stock theme's wallpaper as <theme>/<file>.
// Exactly the forms `omacosy-custom-theme resolve` accepts.
func dayNightSpec(for c: ThemeCell) -> String {
    if let id = c.editionID { return "theme:" + id }
    if c.isCustom { return c.wallpaper }
    return c.logical + "/" + (c.wallpaper as NSString).lastPathComponent
}

// True when a day=/night= value names this cell. The exact spec the menu
// writes matches, and so does a bare filename for a wallpaper in the
// configured folder — the other spelling the value may take.
func dayNightSpecNames(_ spec: String, _ c: ThemeCell) -> Bool {
    guard !spec.isEmpty else { return false }
    if let id = c.editionID { return spec == "theme:" + id }
    if c.isCustom {
        if spec.hasPrefix("/") { return canonicalPath(spec) == canonicalPath(c.wallpaper) }
        if spec.contains("/") { return false }
        return spec == (c.wallpaper as NSString).lastPathComponent
    }
    return spec == c.logical + "/" + (c.wallpaper as NSString).lastPathComponent
}

// The day=/night= values themes.conf holds now. Last line wins, the same
// rule omacosy-custom-theme's conf_get applies, so the menu's check marks
// cannot disagree with what the appearance agent would read.
func dayNightSpecs() -> (day: String, night: String) {
    var day = "", night = ""
    guard let text = try? String(contentsOfFile: HOME + "/.config/omacosy/themes.conf",
                                 encoding: .utf8) else { return (day, night) }
    for line in text.split(separator: "\n") {
        guard let eq = line.firstIndex(of: "=") else { continue }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if key == "day" { day = value } else if key == "night" { night = value }
    }
    return (day, night)
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
func customVariants(_ dir: String) -> [ThemeCell] {
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

// A theme import's file types: our theme record (JSON or TOML), an Omarchy
// colors.toml and a Base16 YAML (the engine also sniffs the content), plus
// plain text so an extensionless file can be picked.
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

// The bare engine message from a failed command, or the fallback when there is
// none. Unlike importErrorMessage it does not assume the word "Import".
func themecoreMessage(_ output: String, fallback: String) -> String {
    for line in output.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("omacosy-themecore:") else { continue }
        let msg = String(t.dropFirst("omacosy-themecore:".count))
            .trimmingCharacters(in: .whitespaces)
        if !msg.isEmpty { return msg }
    }
    return fallback
}

// The bare message from a failed omacosy-custom-theme run, or the fallback.
func customThemeMessage(_ output: String, fallback: String) -> String {
    for line in output.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("omacosy-custom-theme:") else { continue }
        let msg = String(t.dropFirst("omacosy-custom-theme:".count))
            .trimmingCharacters(in: .whitespaces)
        if !msg.isEmpty { return msg }
    }
    return fallback
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

// The gallery needs a 16-colour strip for every raw wallpaper. Deriving it
// costs two processes and a theme rebuild; the result only changes when the
// picture or the deriving tools do, so it is kept next to the thumbnails.
let paletteCacheVersion = 1

// Bumped automatically when any of the tools that produce the colours change,
// so a rebuild invalidates old entries without a manual version bump.
let paletteCacheSalt: String = {
    func stamp(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved),
              let date = attrs[.modificationDate] as? Date else { return "-" }
        return String(Int64(date.timeIntervalSince1970))
    }
    return ["omacosy-custom-theme", "omacosy-derive", "omacosy-term-palette"]
        .map { stamp(HOME + "/.local/bin/" + $0) }
        .joined(separator: ":")
}()

func customPaletteCachePath(_ wallpaper: String) -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: wallpaper),
          let mtime = attrs[.modificationDate] as? Date else { return nil }
    let millis = Int64((mtime.timeIntervalSince1970 * 1000).rounded())
    let seed = "\(wallpaper)|\(millis)|\(paletteCacheSalt)|v\(paletteCacheVersion)"
    return HOME + "/.local/state/omacosy/dashboard/palettes/"
        + String(sha256Hex(seed).prefix(24)) + ".json"
}

func cachedCustomPalette(_ wallpaper: String) -> [NSColor] {
    let cache = customPaletteCachePath(wallpaper)
    if let cache,
       let data = FileManager.default.contents(atPath: cache),
       let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
       (top["version"] as? Int) == paletteCacheVersion,
       let colors = top["colors"] as? [String], colors.count == 16 {
        let parsed = colors.compactMap(hexColor)
        if parsed.count == 16 { return parsed }
    }
    let palette = customPalette(wallpaper)
    let colors = palette.compactMap(hexString)
    if palette.count == 16, colors.count == 16, let cache,
       let data = try? JSONSerialization.data(
            withJSONObject: ["version": paletteCacheVersion, "colors": colors],
            options: [.sortedKeys]) {
        try? FileManager.default.createDirectory(
            atPath: (cache as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: cache), options: .atomic)
    }
    return palette
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func thumbnail(_ path: String, maxPixel: Int = 360) -> NSImage? {
    let dir = HOME + "/.local/state/omacosy/dashboard/thumbs"
    let cache = dir + "/" + stableHash(path + ":\(maxPixel)") + ".png"
    // Decode the cached PNG here, on the caller's background queue. Returning
    // NSImage(contentsOfFile:) leaves the decode lazy, so the first draw while
    // scrolling would do it on the main thread.
    if FileManager.default.fileExists(atPath: cache) {
        if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: cache) as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        if let img = NSImage(contentsOfFile: cache) { return img }
    }
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
        // By id: the engine reads whichever spelling the library holds.
        cmd = "\(HOME)/.local/bin/omacosy-theme-switch set-theme \(shellQuote(id))"
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
    // the theme currently applied, drawn with an "Active" pill
    var active: ActiveTheme? { didSet { needsDisplay = true } }
    var customDir: String?
    var thumbs: [Int: NSImage] = [:]
    var palettes: [Int: [NSColor]] = [:]
    var cellFrames: [Int: NSRect] = [:]
    var headers: [(NSRect, String)] = []
    private var pendingThumbs: Set<Int> = []
    private var pendingPalettes: Set<Int> = []
    // Deriving a palette is the expensive half of a card load; keep a few in
    // flight so a fast scroll cannot launch one process pair per cell.
    private let paletteQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .utility
        return q
    }()
    // Everything in a card that depends only on its title and width. Built
    // once per grid rebuild, so draw() never measures or truncates text.
    private struct CellRender {
        let title: String
        let titleW: CGFloat
        let badge: String
    }
    private var renders: [Int: CellRender] = [:]
    private lazy var titleFont = nerdFont("Regular", 11)
    private lazy var badgeFont = nerdFont("Regular", 10)
    private lazy var pillFont = nerdFont("Bold", 11)
    private lazy var activePillFont = nerdFont("Bold", 10)
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
    // right-click "Set as Day/Night Theme" on any cell; the tab owns the
    // command. key is "day" or "night".
    var onSetDayNight: ((ThemeCell, String) -> Void)?
    // the day=/night= values themes.conf holds now, for the menu's check
    // marks; set by the tab on every reload
    var dayNight: (day: String, night: String) = ("", "")
    // Off-screen review/test only: the gallery's titled blocks, in order.
    func debugSectionTitles() -> [String] { headers.map { $0.1 } }
    func debugSeparatorCount() -> Int { separators.count }
    // Off-screen review only.
    func debugSetHover(_ i: Int?) { hoveredIndex = i; needsDisplay = true }
    private var hoveredIndex: Int?
    private var hoverTracking: NSTrackingArea?

    private var separators: [NSRect] = []
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
        var separatorRects: [NSRect] = []

        func placeCell(_ cellIndex: Int) {
            if x + cellW > padX + usable + 0.5 { x = padX; top += cellH + gapY }
            let f = NSRect(x: x, y: top, width: cellW, height: cellH)
            cellFrames[cellIndex] = f
            x += cellW + gapX
        }
        func endRow() { if x > padX { top += cellH + gapY; x = padX } }

        // A gallery split into titled blocks. `separated` draws the hairline
        // that marks a new block, so only the first one opens without a rule.
        var placedSection = false
        func placeSection(_ title: String, _ indices: [Int], separated: Bool) {
            guard !indices.isEmpty else { return }
            if separated {
                top += 22
                separatorRects.append(NSRect(x: 0, y: top, width: W, height: 1))
                top += 1 + 22
            }
            headers.append((NSRect(x: 0, y: top, width: W, height: headerH), title))
            top += headerH + 8
            for i in indices { placeCell(i) }
            endRow()
            top += 6
            placedSection = true
        }

        // Every wallpaper is an auto-theme, so the custom blocks show whenever
        // there is anything to show — no switch state gates them. Custom
        // `ThemeCell`s are the named editions; the rest are the raw seed
        // wallpapers whose auto themes they are built from.
        let stockIdx = cells.indices.filter { !cells[$0].isCustom }
        let editedIdx = cells.indices.filter { cells[$0].isCustom && cells[$0].editionID != nil }
        let seedIdx = cells.indices.filter { cells[$0].isCustom && cells[$0].editionID == nil }
        placeSection("Omarchy Themes", stockIdx, separated: false)
        placeSection("Custom Themes", editedIdx, separated: placedSection)
        placeSection("Auto Themes", seedIdx, separated: placedSection)

        // convert top-coords to non-flipped bottom coords
        let contentH = max(top + 8, 200)
        func flip(_ r: NSRect) -> NSRect {
            NSRect(x: r.origin.x, y: contentH - r.origin.y - r.height, width: r.width, height: r.height)
        }
        for (k, v) in cellFrames { cellFrames[k] = flip(v) }
        headers = headers.map { (flip($0.0), $0.1) }
        separators = separatorRects.map(flip)

        renders.removeAll()
        for (i, f) in cellFrames where cells.indices.contains(i) {
            let c = cells[i]
            let n = c.variations
            let badge = n > 0 ? "· \(n) variation\(n == 1 ? "" : "s")" : ""
            let badgeW = badge.isEmpty ? 0 : advance(badge, badgeFont) + 8
            let title = truncate(c.title, titleFont, f.width - badgeW)
            renders[i] = CellRender(title: title, titleW: advance(title, titleFont),
                                    badge: badge)
        }

        frame.size = NSSize(width: W, height: contentH)
        needsDisplay = true
    }

    func resetPending() {
        pendingThumbs.removeAll()
        pendingPalettes.removeAll()
    }

    private func invalidate(_ i: Int) {
        if let f = cellFrames[i] { setNeedsDisplay(f) }
    }

    func loadVisible(_ rect: NSRect) {
        for (i, f) in cellFrames where f.intersects(rect) {
            guard cells.indices.contains(i) else { continue }
            if thumbs[i] == nil, !pendingThumbs.contains(i) {
                pendingThumbs.insert(i)
                loadThumb(i)
            }
            if palettes[i] == nil, !pendingPalettes.contains(i) {
                pendingPalettes.insert(i)
                loadPalette(i)
            }
        }
    }

    private func loadThumb(_ i: Int) {
        guard cells.indices.contains(i) else { pendingThumbs.remove(i); return }
        let c = cells[i]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let img = thumbnail(c.wallpaper)
            DispatchQueue.main.async {
                // a reload may have reshuffled the cells while this was in
                // flight; only land on the cell it was decoded for
                guard let self, self.cells.indices.contains(i),
                      self.cells[i].wallpaper == c.wallpaper else { return }
                self.thumbs[i] = img
                self.pendingThumbs.remove(i)
                self.invalidate(i)
            }
        }
    }

    private func loadPalette(_ i: Int) {
        guard cells.indices.contains(i) else { pendingPalettes.remove(i); return }
        let c = cells[i]
        paletteQueue.addOperation { [weak self] in
            guard let self else { return }
            let pal: [NSColor]
            if !c.storedColors.isEmpty { pal = c.storedColors }
            else if c.isCustom { pal = cachedCustomPalette(c.wallpaper) }
            else { pal = parseColorsToml(c.paletteFile) }
            DispatchQueue.main.async {
                guard self.cells.indices.contains(i),
                      self.cells[i].wallpaper == c.wallpaper else { return }
                self.palettes[i] = pal
                self.pendingPalettes.remove(i)
                self.invalidate(i)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // section labels only: the folder buttons live in the Wallpapers tab,
        // which owns the directory. Only the dirty part is redrawn, so a
        // thumbnail arriving (or one hovered card changing) costs one card,
        // not the whole gallery.
        let headerFont = nerdFont("Bold", 13)
        for (r, title) in headers where r.intersects(dirtyRect) {
            drawMidLeft(title, headerFont, palette.accent,
                        x: 0, midTop: bounds.height - r.midY, height: bounds.height)
        }
        for r in separators where r.intersects(dirtyRect) {
            palette.muted.withAlphaComponent(0.25).setFill()
            r.fill()
        }
        for (i, f) in cellFrames where f.intersects(dirtyRect) {
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

        let render = renders[i]
        let title = render?.title ?? cells[i].title
        let badge = render?.badge ?? ""
        let titleTop = bounds.height - (f.minY + cellPaletteH + cellLabelH)
        drawTopLeft(title, titleFont, palette.label,
                    x: f.minX, top: titleTop, height: bounds.height)
        if !badge.isEmpty {
            drawTopLeft(badge, badgeFont, palette.muted,
                        x: f.minX + (render?.titleW ?? advance(title, titleFont)) + 8,
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
                let shape = NSBezierPath(roundedRect: pill, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
                palette.accent.setFill()
                shape.fill()
                let ink = relativeLuminance(palette.accent) > 0.179 ? palette.barBG : palette.label
                drawMidCenter(label, pillFont, ink,
                              centerX: pill.midX, midTop: bounds.height - pill.midY, height: bounds.height)
            }
        }

        // the applied theme carries a green "Active" pill, bottom-left, so the
        // grid says at a glance which one is live
        if isActiveCell(i) {
            let label = "\u{f00c}  Active"
            let pill = activePillRect(f, label: label)
            let shape = NSBezierPath(roundedRect: pill, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
            NSColor.systemGreen.setFill()
            shape.fill()
            drawMidCenter(label, activePillFont, .white,
                          centerX: pill.midX, midTop: bounds.height - pill.midY, height: bounds.height)
        }
    }

    // True when this cell is the theme applied to the desktop.
    private func isActiveCell(_ i: Int) -> Bool {
        guard let a = active, cells.indices.contains(i) else { return false }
        let c = cells[i]
        switch a {
        case .edition(let id): return c.editionID == id
        case .stock(let name): return !c.isCustom && c.logical == name
        case .raw(let path):
            guard c.isCustom, c.editionID == nil else { return false }
            // The index stores the same spelling the cell holds, so the string
            // check settles the normal case without touching the filesystem.
            if c.wallpaper == path { return true }
            return canonicalPath(c.wallpaper) == canonicalPath(path)
        }
    }

    // The Active pill sits over the thumbnail's bottom-left corner, like the
    // Wallpapers grid's Added badge, clear of the hover Edit pill (bottom-
    // right) and the selection checkbox (top-right).
    private func activePillRect(_ f: NSRect, label: String) -> NSRect {
        let thumbRect = NSRect(x: f.minX, y: f.minY + cellPaletteH + cellLabelH + cellThumbGap,
                               width: f.width, height: f.height - cellPaletteH - cellLabelH - cellThumbGap)
        let w = advance(label, nerdFont("Bold", 10)) + 20
        return NSRect(x: thumbRect.minX + pillInset, y: thumbRect.minY + pillInset,
                      width: w, height: pillH)
    }

    // The selection checkbox sits at the thumbnail's top-right corner.
    private func drawCheckbox(_ on: Bool, in cr: NSRect) {
        let box = NSBezierPath(roundedRect: cr, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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

    // Right-click opens a small themed popup at the click (an NSMenu is a
    // grey system panel). Every cell can be made the day or the night theme;
    // a named edition additionally offers Duplicate Theme. A check marks the
    // half this cell already holds.
    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = cellFrames.first(where: { $0.value.contains(p) })?.key,
              cells.indices.contains(i) else {
            super.rightMouseDown(with: event)
            return
        }
        let cell = cells[i]
        let check = "\u{f00c}  "
        let dayItem = (dayNightSpecNames(dayNight.day, cell) ? check : "") + "Set as Day Theme"
        let nightItem = (dayNightSpecNames(dayNight.night, cell) ? check : "") + "Set as Night Theme"
        var items = [dayItem, nightItem]
        if cell.editionID != nil { items.append("Duplicate Theme") }
        ContextMenu.show(items: items, at: NSEvent.mouseLocation) { [weak self] index in
            switch index {
            case 0: self?.onSetDayNight?(cell, "day")
            case 1: self?.onSetDayNight?(cell, "night")
            default: self?.onDuplicate?(cell)
            }
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
        let old = hoveredIndex
        guard hit != old else { return }
        hoveredIndex = hit
        if let old { invalidate(old) }
        if let hit { invalidate(hit) }
    }

    override func mouseExited(with event: NSEvent) {
        guard let old = hoveredIndex else { return }
        hoveredIndex = nil
        invalidate(old)
    }
}

func truncate(_ s: String, _ font: NSFont, _ maxW: CGFloat) -> String {
    if advance(s, font) <= maxW { return s }
    var out = s
    while !out.isEmpty, advance(out + "…", font) > maxW { out.removeLast() }
    return out + "…"
}

// Break a description into at most `maxLines` lines that each fit `maxW`, at
// word boundaries. If a final line still overflows a single word it is clipped
// with an ellipsis. Most strings yield one line.
func wrapText(_ s: String, _ font: NSFont, _ maxW: CGFloat, maxLines: Int = 2) -> [String] {
    let words = s.split(separator: " ").map(String.init)
    var lines: [String] = []
    var current = ""
    var i = 0
    while i < words.count {
        let candidate = current.isEmpty ? words[i] : current + " " + words[i]
        if current.isEmpty || advance(candidate, font) <= maxW {
            current = candidate
            i += 1
            continue
        }
        if lines.count == maxLines - 1 {
            current = words[i...].joined(separator: " ")
            i = words.count
            break
        }
        lines.append(current)
        current = ""
    }
    if !current.isEmpty { lines.append(current) }
    if let last = lines.last, advance(last, font) > maxW {
        lines[lines.count - 1] = truncate(last, font, maxW)
    }
    return lines.isEmpty ? [""] : lines
}

final class ThemesTabView: NSView, ScrollStepTab {
    // the one live Themes tab, so the dashboard's Esc/Delete keys can reach a
    // running selection. nil unless a selection is in progress.
    static weak var selecting: ThemesTabView?

    private let scroll = NSScrollView()
    private let grid = ThemeGridView()
    func scrollStep(_ dy: CGFloat) { scrollBy(scroll, dy) }
    func refreshColors() {
        // a theme switch can land here (the current/theme watcher repaints
        // every tab); the Active pill has to follow it
        grid.active = activeThemeSpec()
        needsDisplay = true
        grid.needsDisplay = true
        scroller.refresh()
        selectButton.needsDisplay = true
        deleteButton.needsDisplay = true
        jumpButton.needsDisplay = true
    }
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8
    // the floating arrow that jumps to the far end in the last scroll direction
    private let jumpButton = ScrollJumpButton()
    private var jumpDown = true
    private var lastScrollY: CGFloat?
    private let selectButton = ButtonView()
    private let deleteButton = ButtonView()
    private var selectionMode = false
    // the same 54pt bottom bar as Options and Workspaces
    private let bottomBand: CGFloat = 54
    private var status = "" { didSet { needsDisplay = true; needsLayout = true } }
    // layout() sets this (truncated to fit left of the centred buttons);
    // draw() renders it
    private var statusShown = ""
    private var needsGridRebuild = true
    // Open at the top only when the tab is (re)shown. A reload from an apply,
    // an edit or a delete must never move the viewport: the grid can be tall
    // and the user is looking at the cell they just acted on.
    private var pendingTopScroll = true
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
        addSubview(jumpButton)
        jumpButton.isHidden = true
        jumpButton.onClick = { [weak self] in self?.jumpToEnd() }
        jumpButton.onScrollWheel = { [weak self] e in self?.scroll.scrollWheel(with: e) }
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
            self?.reload()
            self?.onApplied?()
        }
        grid.onEdit = { [weak self] cell in
            guard let self, let w = self.window else { return }
            ThemeEditor.present(cell: cell, from: w) { [weak self] message in
                self?.status = message
                self?.needsDisplay = true
                self?.reload()
                self?.onApplied?()
            }
        }
        grid.onToggleSelect = { [weak self] i in self?.toggleCell(i) }
        grid.onDuplicate = { [weak self] cell in self?.duplicate(cell) }
        grid.onSetDayNight = { [weak self] cell, key in self?.setDayNight(cell, key: key) }
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
        if window != nil {
            pendingTopScroll = true
            reload()
        } else {
            exitSelection()
        }
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
    // Off-screen review/test only: the scroll position and the top it should
    // open at, plus a scroll to the bottom and a reload with no user action.
    func debugOriginY() -> CGFloat { scroll.contentView.bounds.origin.y }
    func debugTopY() -> CGFloat { max(0, grid.frame.height - scroll.contentSize.height) }
    func debugScrollToBottom() {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroller.refresh()
    }
    func debugReload() { reload() }
    func debugJumpHidden() -> Bool { jumpButton.isHidden }
    func debugJumpUp() -> Bool { jumpButton.up }
    func debugJumpClick() { jumpButton.onClick?() }
    func debugScroll(by dy: CGFloat) { scrollBy(scroll, dy); visibleChanged() }

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
        needsLayout = true
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

    // Right-click Set as Day/Night Theme: write the key the appearance agent
    // reads, switch following on — the whole point of the choice — and put
    // it on screen now when the current appearance is the half chosen.
    private func setDayNight(_ cell: ThemeCell, key: String) {
        let isDay = key == "day"
        let label = isDay ? "Day" : "Night"
        let spec = dayNightSpec(for: cell)
        status = "Setting \(label) Theme…"
        needsDisplay = true
        DispatchQueue.global().async { [weak self] in
            let custom = "\(HOME)/.local/bin/omacosy-custom-theme"
            let (code, out) = shell("\(custom) \(key) \(shellQuote(spec)) 2>&1")
            var message: String
            if code != 0 {
                message = "Error: " + customThemeMessage(out, fallback: "The \(label) Theme was not set")
            } else {
                _ = shell("\(custom) follow on 2>/dev/null")
                // The agent's own rule: the key is absent in light mode, so a
                // non-zero read means light.
                let (dc, dout) = shell("/usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null")
                let dark = dc == 0 && dout.trimmingCharacters(in: .whitespacesAndNewlines) == "Dark"
                let appliesNow = dark != isDay
                if appliesNow { _ = shell("\(custom) apply \(shellQuote(spec)) >/dev/null 2>&1") }
                message = "\(label) Theme: \(cell.title)"
                    + (appliesNow ? " — applied" : " — follows the macOS appearance")
            }
            DispatchQueue.main.async {
                self?.status = message
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

    @objc private func visibleChanged() {
        let y = scroll.contentView.bounds.origin.y
        // A non-flipped document stores later content at a smaller y origin,
        // so moving down the gallery decreases it.
        if let last = lastScrollY, abs(y - last) > 0.5 { jumpDown = y < last }
        lastScrollY = y
        updateJumpButton()
        grid.loadVisible(scroll.documentVisibleRect)
        scroller.refresh()
    }

    // The arrow follows the last scroll direction while there is shelf on
    // both sides of the viewport. At either end it flips to the only useful
    // way out, so the button is never a dead control.
    private func updateJumpButton() {
        let maxScroll = max(0, grid.frame.height - scroll.contentSize.height)
        let y = scroll.contentView.bounds.origin.y
        if maxScroll <= 0.5 {
            jumpButton.isHidden = true
            return
        }
        if y <= 0.5 { jumpDown = false }                       // bottom: offer the top
        else if y >= maxScroll - 0.5 { jumpDown = true }        // top: offer the bottom
        jumpButton.up = !jumpDown
        jumpButton.isHidden = false
        jumpButton.needsDisplay = true
    }

    // "Straight to" the end, as asked: no animation, one jump.
    private func jumpToEnd() {
        let maxScroll = max(0, grid.frame.height - scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: jumpDown ? 0 : maxScroll))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroller.refresh()
        updateJumpButton()
    }

    func reload() {
        let dir = wallpapersDir()
        let cells = stockVariants() + customVariants(dir)
        // the live theme can change without the cell set changing
        grid.active = activeThemeSpec()
        // the day/night values feed the context menu's check marks; a write
        // to themes.conf lands here through the watch, and a set from the
        // menu reloads explicitly
        grid.dayNight = dayNightSpecs()

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
        grid.resetPending()
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
        let jumpSize: CGFloat = 30
        jumpButton.frame = NSRect(x: scroll.frame.maxX - jumpSize - 12, y: band + 12,
                                  width: jumpSize, height: jumpSize)
        // The Select/Delete buttons are centred on the bar, like the centred
        // Save on Options/Workspaces; the status sits to their left.
        let by = (band - 24) / 2
        let delW: CGFloat = deleteButton.isHidden ? 0 : 96 + 8
        let groupW = delW + 96
        let groupX = max(0, (bounds.width - groupW) / 2)
        if !deleteButton.isHidden {
            deleteButton.frame = NSRect(x: groupX, y: by, width: 96, height: 24)
            selectButton.frame = NSRect(x: groupX + 96 + 8, y: by, width: 96, height: 24)
        } else {
            selectButton.frame = NSRect(x: groupX, y: by, width: 96, height: 24)
        }
        let f = nerdFont("Regular", 11)
        statusShown = status.isEmpty ? "" : truncate(status, f, max(0, groupX - 12))
        let w = scroll.contentSize.width
        if w > 0 {
            if abs(grid.frame.width - w) > 0.5 {
                grid.frame.size.width = w
                needsGridRebuild = true
            }
            if needsGridRebuild {
                grid.rebuild()
                needsGridRebuild = false
            }
            // open at the top (the non-flipped document's origin is the
            // bottom, which otherwise shows the custom section first) — but
            // only on a (re)show, never on a reload from an apply or an edit
            if pendingTopScroll {
                pendingTopScroll = false
                let top = max(0, grid.frame.height - scroll.contentSize.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
                scroll.reflectScrolledClipView(scroll.contentView)
                scroller.refresh()
                jumpDown = true
                lastScrollY = top
            }
        }
        grid.loadVisible(scroll.documentVisibleRect)
        updateJumpButton()
    }

    override func draw(_ dirtyRect: NSRect) {
        // the same bottom bar as Options / Workspaces: a hairline above it,
        // the buttons centred on its mid line and the status to their left
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bottomBand - 0.5, width: bounds.width, height: 1).fill()
        if !statusShown.isEmpty {
            drawMidLeft(statusShown, nerdFont("Regular", 11), palette.muted, x: 0,
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

final class EditorWindow: ThemedWindow {
    override var canBecomeKey: Bool { true }

    // End a value field's editing when a click falls outside it. The editor's
    // controls are custom views that never take first responder, so AppKit
    // would otherwise leave the shared field editor first responder: a typed
    // value kept the keyboard and every later click was swallowed until the
    // editor was reopened.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           let fieldEditor = firstResponder as? NSTextView, fieldEditor.isFieldEditor {
            let p = fieldEditor.convert(event.locationInWindow, from: nil)
            if !fieldEditor.bounds.contains(p) { makeFirstResponder(nil) }
        }
        super.sendEvent(event)
    }
}

// The wallpaper editor's slider sections, in Aether's order and membership.
// Every label, range, order and default is Aether's own — FilterControls.svelte
// at v4.32.0, the same source the engine's filters were ported from, also the
// scale the engine's /4 blur expects. Omacosy keeps its own look: each section
// is an accent title over a framed block of sliders, no collapsible rows and
// no extra group headings, so nothing is hidden and nothing is repeated. The
// non-slider sections (Histogram, Curves, Palette Grade, Transform, Presets,
// Blur Desktop) live in the panel's layout beside these.
enum EditorFilterFields {
    // Light — Aether's tone controls, Brightness first.
    static let light: [SliderField] = [
        SliderField(key: "brightness", label: "Brightness", min: 0, max: 200, step: 1, def: 100),
        SliderField(key: "contrast", label: "Contrast", min: 0, max: 200, step: 1, def: 100),
        SliderField(key: "exposure", label: "Exposure", min: -100, max: 100, step: 1, def: 0),
        SliderField(key: "shadows", label: "Shadows", min: -100, max: 100, step: 1, def: 0),
        SliderField(key: "highlights", label: "Highlights", min: -100, max: 100, step: 1, def: 0),
        SliderField(key: "clarity", label: "Clarity", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "fade", label: "Fade", min: 0, max: 100, step: 1, def: 0),
    ]
    // Color — saturation and the hue/colour shifts.
    static let color: [SliderField] = [
        SliderField(key: "saturation", label: "Saturation", min: 0, max: 200, step: 1, def: 100),
        SliderField(key: "temperature", label: "Temperature", min: -100, max: 100, step: 1, def: 0),
        SliderField(key: "tint", label: "Tint", min: -100, max: 100, step: 1, def: 0),
        SliderField(key: "hueRotate", label: "Hue Shift", min: 0, max: 360, step: 1, def: 0),
        SliderField(key: "sepia", label: "Sepia", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "invert", label: "Invert", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "posterize", label: "Posterize", min: 0, max: 10, step: 1, def: 0),
    ]
    // Detail — the texture and grain controls.
    static let detail: [SliderField] = [
        SliderField(key: "sharpen", label: "Sharpen", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "blur", label: "Blur", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "grain", label: "Grain", min: 0, max: 10, step: 1, def: 0),
        SliderField(key: "noise", label: "Color Noise", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "vignette", label: "Vignette", min: 0, max: 100, step: 1, def: 0),
        SliderField(key: "oilPaint", label: "Oil Paint", min: 0, max: 10, step: 1, def: 0),
        SliderField(key: "pixelate", label: "Pixelate", min: 0, max: 100, step: 1, def: 0),
    ]
    // The framed slider sections, in Aether's order. The panel lays these out
    // inside their group (Light under Tone, Color under Color, Detail under
    // Detail) and draws the group labels itself.
    static let groups: [(title: String, fields: [SliderField])] = [
        ("Light", light), ("Color", color), ("Detail", detail),
    ]
}

// The quick presets, verbatim from Aether's FilterControls.svelte (mirrors
// themecore's ImagePresets). Each is a delta over the current state, so
// absent fields keep whatever the user chose.
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
        ("Golden Hour", ["temperature": 40, "brightness": 105, "saturation": 115, "fade": 10]),
        ("Nordic", ["temperature": -30, "contrast": 110, "saturation": 80, "fade": 15, "clarity": 30]),
        ("Retro", ["fade": 30, "saturation": 70, "contrast": 115, "grain": 4, "sepia": 10]),
        ("Poster", ["posterize": 5, "contrast": 130, "saturation": 140]),
        ("Dreamy", ["blur": 15, "brightness": 110, "saturation": 80, "fade": 20]),
        ("Noir", ["saturation": 0, "contrast": 140, "grain": 3, "vignette": 40]),
        ("Red Filter", ["saturation": 0, "contrast": 115, "colorFilterHue": 0, "colorFilterStrength": 100]),
        ("Orange Filter", ["saturation": 0, "contrast": 115, "colorFilterHue": 30, "colorFilterStrength": 100]),
        ("Yellow Filter", ["saturation": 0, "contrast": 115, "colorFilterHue": 55, "colorFilterStrength": 100]),
        ("Green Filter", ["saturation": 0, "contrast": 115, "colorFilterHue": 120, "colorFilterStrength": 100]),
        ("Teal Filter", ["saturation": 0, "contrast": 115, "colorFilterHue": 180, "colorFilterStrength": 100]),
        ("Blue Filter", ["saturation": 0, "contrast": 115, "colorFilterHue": 220, "colorFilterStrength": 100]),
        ("Violet Filter", ["saturation": 0, "contrast": 115, "colorFilterHue": 275, "colorFilterStrength": 100]),
        ("Magenta Filter", ["saturation": 0, "contrast": 115, "colorFilterHue": 320, "colorFilterStrength": 100]),
    ]
    // The colour-filter presets, grouped under their own heading in the
    // dropdown. Kept in step with themecore's ImagePresets.
    static let colorFilters: Set<String> = [
        "Red Filter", "Orange Filter", "Yellow Filter", "Green Filter",
        "Teal Filter", "Blue Filter", "Violet Filter", "Magenta Filter",
    ]
}

// The editor's histogram: the luminance as a filled backdrop, R/G/B as
// coloured traces, each series normalised to its own peak. It sits above the
// tone curve, which also draws the luminance as its own backdrop.
final class HistogramView: NSView {
    var lum: [Int] = [] { didSet { needsDisplay = true } }
    var r: [Int] = [] { didSet { needsDisplay = true } }
    var g: [Int] = [] { didSet { needsDisplay = true } }
    var b: [Int] = [] { didSet { needsDisplay = true } }

    static let viewHeight: CGFloat = 72

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                               xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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

// One row of the picture editor's Custom presets list: the name on the left,
// a delete ✕ on the right. Clicking the name applies the preset, clicking the
// ✕ deletes it. Drawn and hit-tested from shared rects, like the semantic
// cards, so it needs no subview bookkeeping.
final class PresetRowView: NSView {
    var presetName = "" { didSet { needsDisplay = true } }
    var onApply: (() -> Void)?
    var onDelete: (() -> Void)?

    private var deleteRect: NSRect {
        NSRect(x: bounds.maxX - 26, y: 0, width: 26, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
        palette.itemBG.withAlphaComponent(0.35).setFill()
        box.fill()
        palette.muted.withAlphaComponent(0.3).setStroke()
        box.lineWidth = 1
        box.stroke()
        drawMidLeft(truncate(presetName, nerdFont("Regular", 11), bounds.width - 42),
                    nerdFont("Regular", 11), palette.label,
                    x: 10, midTop: bounds.midY, height: bounds.height)
        drawMidCenter("\u{2715}", nerdFont("Regular", 10), palette.muted,
                      centerX: deleteRect.midX, midTop: bounds.midY, height: bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if deleteRect.contains(p) { onDelete?() } else { onApply?() }
    }
}

// The scrollable editor body: Strength and the Auto Enhance buttons, then the
// picture's controls. The luminance histogram sits above the tone curve and is
// also the curve's backdrop. The picture history's own Undo / Redo / Reset sit
// in the header, separate from the palette's. The edited picture is shown in
// the central pane.

// A text field that DRAWS its own value, because AppKit's shared field editor
// honours neither the cell's `alignment` nor a paragraph style we give it, so
// the editing text jumps to the left. This field hides the editor's own text
// and caret (both made clear) and draws the value — and a blinking caret at the
// real insertion point — itself, in `horizontal` alignment, focused or not.
// Self-contained: it draws its own box too (boxAlpha 0 for none).
final class DrawnTextField: NSTextField {
    var centeredPlaceholder = "" { didSet { needsDisplay = true } }
    var boxAlpha: CGFloat = 0.35 { didSet { needsDisplay = true } }
    var horizontal: NSTextAlignment = .center { didSet { needsDisplay = true } }

    private var blinkTimer: Timer?
    private var caretVisible = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBezeled = false
        drawsBackground = false
        textColor = .clear
        alignment = horizontal
        focusRingType = .none
        font = nerdFont("Regular", 11)
        NotificationCenter.default.addObserver(self, selector: #selector(textChanged),
            name: NSControl.textDidChangeNotification, object: self)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { NotificationCenter.default.removeObserver(self); blinkTimer?.invalidate() }

    @objc private func textChanged() { needsDisplay = true }
    // programmatic value changes (syncFromState, setTransform) must repaint too
    override var stringValue: String { didSet { needsDisplay = true } }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if let e = currentEditor() as? NSTextView {
            e.textColor = .clear
            e.insertionPointColor = .clear
        }
        startBlink()
        needsDisplay = true
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if let e = currentEditor() as? NSTextView {
            e.textColor = palette.label
            e.insertionPointColor = palette.label
        }
        stopBlink()
        needsDisplay = true
        return ok
    }

    private func startBlink() {
        blinkTimer?.invalidate()
        caretVisible = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.caretVisible.toggle()
            self?.needsDisplay = true
        }
    }
    private func stopBlink() { blinkTimer?.invalidate(); blinkTimer = nil; caretVisible = true }

    private func textOriginX(_ textWidth: CGFloat) -> CGFloat {
        switch horizontal {
        case .right: return bounds.maxX - textWidth
        case .left:  return bounds.minX
        default:     return bounds.midX - textWidth / 2
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if boxAlpha > 0 {
            let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(4), yRadius: windowCornerRadius(4))
            palette.itemBG.withAlphaComponent(boxAlpha).setFill()
            box.fill()
        }
        let f = font ?? nerdFont("Regular", 11)
        let s = stringValue
        drawCaret(f, s)
        let shown = s.isEmpty ? centeredPlaceholder : s
        guard !shown.isEmpty else { return }
        let ink = s.isEmpty ? palette.muted.withAlphaComponent(0.7) : palette.label
        // NSAttributedString.draw honours the view's flippedness (CTLineDraw
        // does not, which rendered the value upside down in this flipped view)
        let para = NSMutableParagraphStyle()
        para.alignment = horizontal
        para.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: f, .foregroundColor: ink, .paragraphStyle: para,
        ]
        let lineH = ceil(f.ascender - f.descender)
        let textRect = NSRect(x: 0, y: bounds.midY - lineH / 2, width: bounds.width, height: lineH)
        NSAttributedString(string: shown, attributes: attrs).draw(in: textRect)
    }

    private func drawCaret(_ f: NSFont, _ s: String) {
        guard currentEditor() != nil, caretVisible else { return }
        let loc = (currentEditor() as? NSTextView).map { min($0.selectedRange().location, s.count) } ?? s.count
        let x = textOriginX(advance(s, f)) + advance(String(s.prefix(loc)), f)
        palette.accent.setFill()
        NSRect(x: x, y: bounds.midY - f.capHeight / 2, width: 1.5, height: f.capHeight).fill()
    }
}

final class EditorPanelDoc: NSView, NSTextFieldDelegate {
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
    // The built-in presets, chosen from the same dropdown the palette builder's
    // Presets control uses.
    let presetsButton = PopupButtonView()
    // Snapshots: Save the current adjustments, move a presets file in/out, and
    // the user's own presets as a list below the built-in dropdown.
    let savePresetButton = ButtonView()
    let importPresetsButton = ButtonView()
    let exportPresetsButton = ButtonView()
    private(set) var customRows: [PresetRowView] = []
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
    let resizeWField = DrawnTextField()
    let resizeHField = DrawnTextField()
    let resizeLinkButton = ButtonView()
    let cropResetButton = ButtonView()
    let transformResetButton = ButtonView()
    var onSlider: ((String, Double) -> Void)?
    var onAuto: ((String) -> Void)?
    var onCurve: (([[Double]]) -> Void)?
    var onCurveReset: (() -> Void)?
    var onGradeStops: (([String]) -> Void)?
    var onPreset: ((String) -> Void)?
    var onSavePreset: (() -> Void)?
    var onImportPresets: (() -> Void)?
    var onExportPresets: (() -> Void)?
    var onApplyCustomPreset: ((String) -> Void)?
    var onDeletePreset: ((String) -> Void)?
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
    // The accent section titles with a framed block (Light / Color / Detail).
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
    private var presetActionsTop: CGFloat = 0
    private var customLabelTop: CGFloat = 0
    private var histTop: CGFloat = 0
    private var blurTop: CGFloat = 0
    // A rule above Detail: Palette Grade's Strength slider is the last thing
    // in the unframed Palette Grade block, so the section needs its own line.
    private var detailTop: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        strengthSlider.onChange = { [weak self] v in self?.onSlider?("strength", v) }
        addSubview(strengthSlider)
        curveView.onChange = { [weak self] points in self?.onCurve?(points) }
        addSubview(curveView)
        curveResetButton.title = "Reset Curve"
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
            var rows: [MethodPicker.Row] = []
            var addedFilterHeader = false
            for preset in EditorPresets.all {
                if EditorPresets.colorFilters.contains(preset.name) && !addedFilterHeader {
                    rows.append(MethodPicker.Row(header: "COLOR FILTERS", value: nil,
                                                 label: "COLOR FILTERS"))
                    addedFilterHeader = true
                }
                rows.append(MethodPicker.Row(header: nil, value: preset.name, label: preset.name))
            }
            MethodPicker.present(from: self.presetsButton, rows: rows, strips: [:],
                                 currentMethod: "", title: "Presets", liveApply: true) { [weak self] name in
                self?.presetsButton.title = name
                self?.presetsButton.needsDisplay = true
                self?.onPreset?(name)
            }
        }
        addSubview(presetsButton)
        // Snapshots: Save Current, Import and Export as one row of three equal
        // buttons, matching Aether's Presets header.
        savePresetButton.title = "Save Current"
        savePresetButton.fontSize = 11
        savePresetButton.onClick = { [weak self] in self?.onSavePreset?() }
        addSubview(savePresetButton)
        importPresetsButton.title = "Import"
        importPresetsButton.fontSize = 11
        importPresetsButton.secondary = true
        importPresetsButton.toolTip = "Import Presets"
        importPresetsButton.onClick = { [weak self] in self?.onImportPresets?() }
        addSubview(importPresetsButton)
        exportPresetsButton.title = "Export"
        exportPresetsButton.fontSize = 11
        exportPresetsButton.secondary = true
        exportPresetsButton.toolTip = "Export Presets"
        exportPresetsButton.onClick = { [weak self] in self?.onExportPresets?() }
        addSubview(exportPresetsButton)
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
            // DrawnTextField draws its own box, centred value and caret;
            // it only needs the input wiring.
            f.target = self
            f.action = #selector(resizeCommit)
            f.delegate = self
            addSubview(f)
        }
        resizeWField.centeredPlaceholder = "Width"
        resizeHField.centeredPlaceholder = "Height"
        transformResetButton.title = "Reset"
        transformResetButton.fontSize = 10
        transformResetButton.secondary = true
        transformResetButton.onClick = { [weak self] in self?.onTransformReset?() }
        addSubview(transformResetButton)
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

    // One framed slider section: its accent title, the sliders, then a gap.
    private func sectionHeight(_ fields: [SliderField]) -> CGFloat {
        30 + CGFloat(fields.count) * AdjustmentSliderView.rowHeight + 24
    }

    func contentHeight() -> CGFloat {
        // One vertical rhythm shared with the palette column (see layout):
        // outer padding 12, heading->content 24, section gap 24, sub-gap 12.
        var h: CGFloat = 12
        h += 24 + 12                                      // Apply to Palette
        h += AdjustmentSliderView.rowHeight + 24          // Strength
        h += 24 + 22 + 24                                 // Auto Enhance + buttons
        h += 24 + HistogramView.viewHeight + 24           // Histogram
        h += 24 + CurveEditorView.viewHeight + 12 + 20 + 24  // Curves + Reset Curve row
        h += sectionHeight(EditorFilterFields.light)      // Light (framed: 30)
        h += sectionHeight(EditorFilterFields.color)      // Color
        h += 24 + 24 + 8 + AdjustmentSliderView.rowHeight + 24   // Palette Grade
        h += sectionHeight(EditorFilterFields.detail)     // Detail
        h += 24 + 24                                      // Blur Desktop toggle
        h += 260                                          // Transform
        h += 16                                           // "Original: W × H" line
        h += 44                                           // Presets dropdown
        h += 34                                           // Save Current + Import/Export
        if !customRows.isEmpty {
            h += 18 + CGFloat(customRows.count) * 32      // Custom label + rows
        }
        return h + 12
    }

    func setHistogram(_ lum: [Int], _ r: [Int], _ g: [Int], _ b: [Int]) {
        histogram.lum = lum
        histogram.r = r
        histogram.g = g
        histogram.b = b
        // the curve also draws the luminance histogram as its backdrop
        curveView.histogram = lum
    }

    // Rebuild the Custom list from the engine's stored presets. Rows are reused
    // views; the delete/apply closures capture the name, so a refresh keeps them
    // correct. The panel grows or shrinks to fit.
    func setCustomPresets(_ list: [(name: String, values: [String: Any])]) {
        for row in customRows { row.removeFromSuperview() }
        customRows = list.map { entry in
            let row = PresetRowView()
            row.presetName = entry.name
            row.onApply = { [weak self] in self?.onApplyCustomPreset?(entry.name) }
            row.onDelete = { [weak self] in self?.onDeletePreset?(entry.name) }
            addSubview(row)
            return row
        }
        needsLayout = true
        needsDisplay = true
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

    private var resizeRatio: Double {
        originalSize.width > 0 && originalSize.height > 0
            ? originalSize.width / originalSize.height : 0
    }

    @objc private func resizeCommit() {
        let w = Double(resizeWField.stringValue) ?? 0
        var h = Double(resizeHField.stringValue) ?? 0
        if resizeLinked, resizeRatio > 0, w > 0 {
            h = (w / resizeRatio).rounded()
        }
        onResize?(w, h)
    }

    // Typing in one linked field updates the other as you go (Aether's UI), not
    // only on Return/blur.
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if resizeLinked, resizeRatio > 0 {
            if field === resizeWField, let w = Double(resizeWField.stringValue), w > 0 {
                resizeHField.stringValue = "\(Int((w / resizeRatio).rounded()))"
            } else if field === resizeHField, let h = Double(resizeHField.stringValue), h > 0 {
                resizeWField.stringValue = "\(Int((h * resizeRatio).rounded()))"
            }
        }
        resizeCommit()
        needsDisplay = true
    }

    // Hand the shared field editor back with its own colours, since the resize
    // fields borrow it with a clear text/insertion colour.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, f === resizeWField || f === resizeHField,
              let editor = obj.userInfo?["NSFieldEditor"] as? NSTextView else { return }
        editor.textColor = palette.label
        editor.insertionPointColor = palette.label
        needsDisplay = true
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, f === resizeWField || f === resizeHField,
              let editor = obj.userInfo?["NSFieldEditor"] as? NSTextView else { return }
        // the panel draws the value and the caret; hide ours
        editor.insertionPointColor = .clear
        editor.textColor = .clear
        needsDisplay = true
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
        var top: CGFloat = 12
        applyButton.frame = rect(top: top, h: 24, x: insetL, w: contentW)
        top += 24 + 12
        strengthSlider.frame = rect(top: top, h: AdjustmentSliderView.rowHeight,
                                    x: insetL + 10, w: contentW - 20)
        top += AdjustmentSliderView.rowHeight + 24
        autoTop = top
        top += 24                                         // AUTO ENHANCE label
        let gap: CGFloat = 2
        let bw = max(50, (contentW - gap * 2) / 3)
        autoLevelsButton.frame = rect(top: top, h: 22, x: insetL, w: bw)
        autoContrastButton.frame = rect(top: top, h: 22, x: insetL + bw + gap, w: bw)
        autoWBButton.frame = rect(top: top, h: 22, x: insetL + (bw + gap) * 2, w: bw)
        top += 22 + 24
        groupTops.removeAll()
        groupFrames.removeAll()
        var i = 0
        // Histogram (luminance + R/G/B) above the tone curve.
        histTop = top
        top += 24
        histogram.frame = rect(top: top, h: HistogramView.viewHeight, x: insetL, w: contentW)
        top += HistogramView.viewHeight + 24
        curveTop = top
        top += 24
        curveView.frame = rect(top: top, h: CurveEditorView.viewHeight, x: insetL, w: contentW)
        top += CurveEditorView.viewHeight + 12
        curveResetButton.frame = rect(top: top, h: 20, x: insetL + contentW - 84, w: 84)
        top += 20 + 24
        laySection("Light", EditorFilterFields.light, &top, &i)
        laySection("Color", EditorFilterFields.color, &top, &i)
        // Palette Grade: 2-4 colour stops plus a strength slider.
        gradeTop = top
        top += 24
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
                                         x: insetL + 10, w: contentW - 20)
        top += AdjustmentSliderView.rowHeight + 24
        detailTop = top
        laySection("Detail", EditorFilterFields.detail, &top, &i)
        blurTop = top
        blurToggle.frame = rect(top: top, h: 24, x: insetL + contentW - 46, w: 46)
        top += 24 + 24
        // Transform, in Aether's order: ROTATE & FLIP, CROP, RESIZE.
        transformTop = top
        top += 24
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
        // the transform Reset rides the same line, right of the lock
        transformResetButton.frame = rect(top: top, h: 22, x: insetL + 200, w: 70)
        top += 22 + 4
        // "Original: W × H" is drawn at a fixed offset (see draw); leave it a
        // clear line above the Presets section so nothing overlaps it.
        top += 16
        top += 16
        // Snapshots: the built-in presets (the palette-style dropdown), then
        // Save Current / Import / Export, then the user's custom presets.
        presetTop = top
        presetsButton.frame = rect(top: top + 3, h: 26,
                                   x: insetL + max(0, contentW - 170), w: min(170, contentW))
        top += 44
        presetActionsTop = top
        // three equal buttons filling the column width, with room to breathe
        let presetGap: CGFloat = 12
        let presetBW = max(60, (contentW - presetGap * 2) / 3)
        savePresetButton.frame = rect(top: top, h: 24, x: insetL, w: presetBW)
        importPresetsButton.frame = rect(top: top, h: 24, x: insetL + presetBW + presetGap, w: presetBW)
        exportPresetsButton.frame = rect(top: top, h: 24, x: insetL + contentW - presetBW, w: presetBW)
        top += 34
        customLabelTop = 0
        if !customRows.isEmpty {
            customLabelTop = top
            top += 18
            for row in customRows {
                row.frame = rect(top: top, h: 28, x: insetL, w: contentW)
                top += 32
            }
        }
    }

    // One framed slider section: its accent title, then the sliders inside a
    // rounded frame. `i` walks the shared `sliders` array in section order.
    private func laySection(_ title: String, _ fields: [SliderField],
                            _ top: inout CGFloat, _ i: inout Int) {
        groupTops.append((title, top))
        top += 30
        let blockTop = top
        for _ in fields {
            // inset inside the frame so the label and value never touch its
            // line; the frame itself keeps the column edges
            sliders[i].frame = rect(top: top, h: AdjustmentSliderView.rowHeight,
                                    x: insetL + 10, w: contentW - 20)
            top += AdjustmentSliderView.rowHeight
            i += 1
        }
        groupFrames.append((blockTop, top))
        top += 24
    }

    // A hairline above a section's heading: long scrolling panels read as
    // separate feature blocks instead of one continuous column. It sits
    // 10 pt above the heading so the title has room to breathe under it.
    private func drawRule(_ top: CGFloat) {
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: insetL, y: bounds.height - (top - 10), width: contentW, height: 1).fill()
    }

    // A rounded 1 px frame around a multi-slider block: the heading stays
    // above it, the controls sit inside. The frame shares the content column's
    // left and right edges (the same edges as the buttons and popups above),
    // so nothing sticks out of the column.
    private func drawGroupFrame(top: CGFloat, bottom: CGFloat) {
        let r = NSRect(x: insetL, y: bounds.height - bottom - 6,
                       width: contentW, height: (bottom - top) + 12)
        let path = NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(8), yRadius: windowCornerRadius(8))
        palette.muted.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawRule(autoTop)
        // Auto Enhance and Blur Desktop are settings, not sections: a size
        // below the accent section titles, in the label colour.
        drawTopLeft("Auto Enhance", nerdFont("Bold", 11), palette.label,
                    x: insetL, top: autoTop, height: bounds.height)
        // Section titles, each under its own hairline separator.
        drawRule(histTop)
        drawTopLeft("Histogram", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: histTop, height: bounds.height)
        drawTopLeft("Curves", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: curveTop, height: bounds.height)
        // Palette Grade is an unframed block; a rule separates its Strength
        // slider from the Detail section under it.
        drawRule(detailTop)
        for (title, top) in groupTops {
            drawTopLeft(title, nerdFont("Bold", 12), palette.accent,
                        x: insetL, top: top, height: bounds.height)
        }
        for (top, bottom) in groupFrames {
            drawGroupFrame(top: top, bottom: bottom)
        }
        drawMidLeft("Blur Desktop", nerdFont("Bold", 11), palette.label,
                    x: insetL, midTop: blurTop + 12, height: bounds.height)
        drawTopLeft("Palette Grade", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: gradeTop, height: bounds.height)
        // Blur Desktop closes the Detail group; a rule separates it from the
        // Transform section below.
        drawRule(transformTop)
        drawTopLeft("Transform", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: transformTop, height: bounds.height)
        drawRule(presetTop)
        drawMidLeft("Presets", nerdFont("Bold", 12), palette.accent,
                    x: insetL, midTop: presetTop + 16, height: bounds.height)
        if customLabelTop > 0 {
            drawTopLeft("Custom", nerdFont("Bold", 10), palette.muted,
                        x: insetL, top: customLabelTop, height: bounds.height)
        }
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
    var onSavePreset: (() -> Void)? { didSet { doc.onSavePreset = onSavePreset } }
    var onImportPresets: (() -> Void)? { didSet { doc.onImportPresets = onImportPresets } }
    var onExportPresets: (() -> Void)? { didSet { doc.onExportPresets = onExportPresets } }
    var onApplyCustomPreset: ((String) -> Void)? { didSet { doc.onApplyCustomPreset = onApplyCustomPreset } }
    var onDeletePreset: ((String) -> Void)? { didSet { doc.onDeletePreset = onDeletePreset } }
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

    // The editor hands the stored presets here; the list changes the panel's
    // height, so the column re-lays out around it.
    func setCustomPresets(_ list: [(name: String, values: [String: Any])]) {
        doc.setCustomPresets(list)
        needsLayout = true
    }

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
    var oilPaint = 0.0
    var pixelate = 0.0
    var clarity = 0.0
    var fade = 0.0
    var posterize = 0.0
    var noise = 0.0
    var shadows = 0.0
    var highlights = 0.0
    var temperature = 0.0
    var tint = 0.0
    // A photographic colour filter: the picture's luma tinted by `hue` (0-360)
    // and blended by `strength` (0-100). With Saturation 0 this is a black-and-
    // white picture under a coloured filter.
    var colorFilterHue = 0.0
    var colorFilterStrength = 0.0
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
        applyJSON(json)
    }

    // Lay a recipe's fields onto this one; shared by init(json:) and the
    // preset merge, so a built-in or a custom preset speaks one vocabulary.
    mutating func applyJSON(_ json: [String: Any]) {
        let known: Set<String> = ["blur", "brightness", "contrast", "saturation", "hueRotate",
            "hue_rotate", "sepia", "invert", "exposure", "vignette", "sharpen", "grain",
            "oilPaint", "oil_paint", "pixelate", "clarity", "fade", "posterize", "noise",
            "shadows", "highlights", "temperature", "tint", "curvePoints", "curve_points",
            "paletteStops", "palette_stops", "paletteStrength", "palette_strength",
            "cropX", "cropY", "cropW", "cropH", "crop_x", "crop_y", "crop_w", "crop_h",
            "resizeW", "resizeH", "resize_w", "resize_h", "rotate", "flipH", "flipV",
            "flip_h", "flip_v", "strength", "colorFilterHue", "color_filter_hue",
            "colorFilterStrength", "color_filter_strength"]
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
            case "oilPaint", "oil_paint": oilPaint = num(value)
            case "pixelate": pixelate = num(value)
            case "clarity": clarity = num(value)
            case "fade": fade = num(value)
            case "posterize": posterize = num(value)
            case "noise": noise = num(value)
            case "shadows": shadows = num(value)
            case "highlights": highlights = num(value)
            case "temperature": temperature = num(value)
            case "tint": tint = num(value)
            case "colorFilterHue", "color_filter_hue": colorFilterHue = num(value)
            case "colorFilterStrength", "color_filter_strength": colorFilterStrength = num(value)
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
        f.colorFilterStrength = lerp(colorFilterStrength, 0)
        f.hueRotate = hueRotate * s
        f.sepia = sepia * s
        f.invert = invert * s
        f.vignette = vignette * s
        f.sharpen = sharpen * s
        f.grain = grain * s
        f.oilPaint = oilPaint * s
        f.pixelate = pixelate * s
        f.clarity = clarity * s
        f.fade = fade * s
        f.posterize = posterize * s
        f.noise = noise * s
        f.blur = blur * s
        f.paletteStrength = paletteStrength * s
        f.curvePoints = curvePoints.map { [$0[0], $0[0] + ($0[1] - $0[0]) * s] }
        return f
    }

    var isIdentity: Bool {
        curvePoints.isEmpty && paletteStops.count < 2 && blur == 0 && brightness == 100
            && contrast == 100 && saturation == 100 && hueRotate == 0 && sepia == 0 && invert == 0
            && exposure == 0 && vignette == 0 && sharpen == 0 && grain == 0 && shadows == 0
            && oilPaint == 0 && pixelate == 0 && clarity == 0 && fade == 0 && posterize == 0 && noise == 0
            && highlights == 0 && temperature == 0 && tint == 0 && rotate == 0 && !flipH && !flipV
            && colorFilterStrength == 0
            && cropX == 0 && cropY == 0 && cropW == 1 && cropH == 1 && resizeW == 0 && resizeH == 0
    }

    // Aether's FilterControls.applyPreset: start from the defaults, lay the
    // preset's values on top, then let the structural fields the preset does
    // not carry keep the user's current value (crop, resize, rotate, flip,
    // curve, strength). Every absent stylistic field therefore returns to its
    // neutral default — applying a preset is a clean look, not a merge.
    func applyingPreset(_ values: [String: Any]) -> EditorFilters {
        var next = EditorFilters(json: values)
        if values["cropX"] == nil { next.cropX = cropX }
        if values["cropY"] == nil { next.cropY = cropY }
        if values["cropW"] == nil { next.cropW = cropW }
        if values["cropH"] == nil { next.cropH = cropH }
        if values["resizeW"] == nil { next.resizeW = resizeW }
        if values["resizeH"] == nil { next.resizeH = resizeH }
        if values["rotate"] == nil { next.rotate = rotate }
        if values["flipH"] == nil { next.flipH = flipH }
        if values["flipV"] == nil { next.flipV = flipV }
        if values["curvePoints"] == nil { next.curvePoints = curvePoints }
        if values["strength"] == nil { next.strength = strength }
        return next
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
            case "oilPaint": return oilPaint
            case "pixelate": return pixelate
            case "clarity": return clarity
            case "fade": return fade
            case "posterize": return posterize
            case "noise": return noise
            case "shadows": return shadows
            case "highlights": return highlights
            case "temperature": return temperature
            case "tint": return tint
            case "colorFilterHue": return colorFilterHue
            case "colorFilterStrength": return colorFilterStrength
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
            case "oilPaint": oilPaint = newValue
            case "pixelate": pixelate = newValue
            case "clarity": clarity = newValue
            case "fade": fade = newValue
            case "posterize": posterize = newValue
            case "noise": noise = newValue
            case "shadows": shadows = newValue
            case "highlights": highlights = newValue
            case "temperature": temperature = newValue
            case "tint": tint = newValue
            case "colorFilterHue": colorFilterHue = newValue
            case "colorFilterStrength": colorFilterStrength = newValue
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
            "sharpen": sharpen, "grain": grain, "oilPaint": oilPaint, "pixelate": pixelate,
            "clarity": clarity, "fade": fade, "posterize": posterize, "noise": noise,
            "shadows": shadows,
            "highlights": highlights, "temperature": temperature, "tint": tint,
            "colorFilterHue": colorFilterHue, "colorFilterStrength": colorFilterStrength,
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
// own LUTs and arrive with their controls; grain and color noise are random,
// so both are applied only by the engine's render). Where the two differ, the
// engine's `image render` is the record.
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

// The engine's colour-filter tint: a hue at moderate saturation, normalised so
// its brightest channel is 1. Keeps white white-ish instead of the pure hue.
private func colorFilterTint(_ hue: Double) -> (r: Double, g: Double, b: Double) {
    let hex = hslHex(hue, 60, 50)
    guard hex.count == 7, let v = UInt64(hex.dropFirst(), radix: 16) else { return (1, 1, 1) }
    let r = Double((v >> 16) & 0xff), g = Double((v >> 8) & 0xff), b = Double(v & 0xff)
    let m = max(r, max(g, b))
    return m > 0 ? (r / m, g / m, b / m) : (1, 1, 1)
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

    // Pixelate runs before blur in the engine; the block size is the same
    // round(pixelate/5 * spatialScale) the engine uses.
    if f.pixelate > 0 {
        let block = max(2, ((f.pixelate / 5) * spatialScale).rounded())
        if let px = CIFilter(name: "CIPixellate") {
            px.setValue(ci, forKey: kCIInputImageKey)
            px.setValue(block, forKey: kCIInputScaleKey)
            ci = (px.outputImage ?? ci).cropped(to: target)
        }
    }

    if f.blur > 0 {
        let radius = max(1, ((f.blur / 4) * spatialScale).rounded())
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(ci, forKey: kCIInputImageKey)
            blur.setValue(radius, forKey: kCIInputRadiusKey)
            ci = (blur.outputImage ?? ci).cropped(to: target)
        }
    }

    // Oil paint is a box blur in the engine (radius oilPaint*2*spatialScale);
    // CoreImage's own box blur stands in where it exists.
    if f.oilPaint > 0 {
        let radius = max(2, ((f.oilPaint * 2) * spatialScale).rounded())
        if let box = CIFilter(name: "CIBoxBlur") {
            box.setValue(ci, forKey: kCIInputImageKey)
            box.setValue(radius, forKey: kCIInputRadiusKey)
            ci = (box.outputImage ?? ci).cropped(to: target)
        } else if let blur = CIFilter(name: "CIGaussianBlur") {
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
    if f.colorFilterStrength > 0 {
        // out = (1 - amount)·rgb + amount·tint·luma, one 3×3 matrix.
        let amount = f.colorFilterStrength / 100
        let tint = colorFilterTint(f.colorFilterHue)
        let lr = 0.2126, lg = 0.7152, lb = 0.0722
        func row(_ t: Double) -> CIVector {
            CIVector(x: (1 - amount) + amount * t * lr,
                     y: amount * t * lg,
                     z: amount * t * lb, w: 0)
        }
        ci = ciColorMatrix(ci, r: row(tint.r), g: row(tint.g), b: row(tint.b),
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
    // Fade lifts the blacks: out = c + lift*(1 - c/255), the engine's curve.
    if f.fade > 0 {
        let lift = (f.fade / 100) * 60
        let lut = (0..<256).map { i -> Double in
            min(255, Double(i) + lift * (1 - Double(i) / 255)) / 255
        }
        ci = ciCurveCube(ci, lut: lut)
    }
    // Palette grade: the engine's lightness-indexed LUT, reproduced as a cube.
    if f.paletteStops.count >= 2, f.paletteStrength > 0,
       let lut = dashboardPaletteLUT(f.paletteStops) {
        ci = ciPaletteGradeCube(ci, lut: lut, strength: f.paletteStrength / 100)
    }
    // Posterize runs after the palette grade, as in the engine; its level
    // count is the engine's max(2, round(11 - posterize)).
    if f.posterize > 0 {
        let levels = max(2, (11 - f.posterize).rounded())
        if let poster = CIFilter(name: "CIColorPosterize") {
            poster.setValue(ci, forKey: kCIInputImageKey)
            poster.setValue(levels, forKey: "inputLevels")
            ci = poster.outputImage ?? ci
        }
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
    // Clarity is an unsharp mask against a large blur (radius round(w/80),
    // floor 3); CoreImage's unsharp mask stands in for the engine's box pass.
    if f.clarity > 0 {
        if let sharp = CIFilter(name: "CIUnsharpMask") {
            sharp.setValue(ci, forKey: kCIInputImageKey)
            sharp.setValue(max(3, (Double(target.width) / 80).rounded()), forKey: kCIInputRadiusKey)
            sharp.setValue(f.clarity / 100, forKey: kCIInputIntensityKey)
            ci = (sharp.outputImage ?? ci).cropped(to: target)
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
// group's Orange is the red slot lightened 15% (`palette shades`): a shade
// of the palette, not the UI accent. The accent is the ANSI blue slot, as in
// Aether, so this orange moves no desktop surface by itself.
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

// Aether's setPalette rule for the four extended colours: the accent is the
// ANSI blue slot (index 4), which is what Aether's editor shows under UI ->
// Accent and what its templates write as `accent`. The red slot lightened 15%
// is a different colour — the semantic ACCENT group's Orange shade — and
// using it as the UI accent turned every blue-dominant wallpaper's bar, ring
// and chrome red. The two stay apart here exactly as they do in Aether.
// `accent` is the picture's own role accent, which Magic passes through.
func paletteExtendedDefaults(_ colors: [String], accent: String?) -> [String: String] {
    let c = colors.count == 16 ? colors : Array(repeating: "#000000", count: 16)
    return ["accent": accent ?? c[4],
            "cursor": c[7],
            "selection_foreground": c[0], "selection_background": c[7]]
}

// The 16 colours a Magic draft seeds from: the derived theme's ANSI set with
// slot 0 replaced by the background the theme really draws on (OMACOSY_BG).
// The derived set's slot 0 is ANSI black — the background lightened 0.10 — a
// colour for text, not a pane to paint, and the Theme Studio reads slot 0 as
// the background. Without this swap the Magic pane came out a rung too light
// and washed out over the wallpaper, unlike every Aether preset.
func magicThemeColors(_ ansi: [String], background: String?) -> [String] {
    guard ansi.count == 16, let bg = background.flatMap(cleanHex) else { return ansi }
    var colors = ansi
    colors[0] = bg
    return colors
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
    // classic | grouped | neighboring | expressive
    private(set) var syntax = "classic"
    // token -> hex for the mock terminal, from `palette syntax`
    private(set) var syntaxColors: [String: String] = [:]
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
        var syntax: String
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

    // The Omacosy-UI-ONLY roles the editor can override, stored as `ui_<role>`
    // in `extended`. The engine applies them verbatim to the bar/ring and no
    // terminal writer reads them, so recolouring Omacosy's own chrome never
    // moves the palette the terminal tools use.
    static let uiRoles: [(role: String, label: String)] = [
        ("background", "Background"), ("pill", "Pill"), ("muted", "Muted"),
        ("label", "Label"), ("accent", "Accent"), ("ring", "Ring"),
        ("red", "Red"), ("green", "Green"), ("yellow", "Yellow"),
    ]

    // The derived value an Omacosy role falls back to when unpinned. `roles`
    // (from `palette roles`) holds bar/pill/muted/label/accent/ring; the
    // semantic trio is the fixed light/dark set the engine also uses.
    func derivedUIRole(_ role: String) -> String {
        func hashed(_ s: String?) -> String? { s.flatMap(cleanHex) }
        switch role {
        case "background": return hashed(roles["bar"]) ?? hashed(baseColors.first) ?? "#000000"
        case "pill":
            return hashed(roles["pill"])
                ?? hashed(baseColors.indices.contains(8) ? baseColors[8] : nil) ?? "#000000"
        case "muted": return hashed(roles["muted"]) ?? "#8a8a8a"
        case "label":
            return hashed(roles["label"])
                ?? hashed(baseColors.indices.contains(7) ? baseColors[7] : nil) ?? "#ffffff"
        case "accent": return hashed(roles["accent"]) ?? "#8888ff"
        case "ring": return hashed(roles["ring"]) ?? hashed(roles["accent"]) ?? "#8888ff"
        case "red": return resolvedMode == "light" ? "#9d1f1f" : "#e05f5f"
        case "green": return resolvedMode == "light" ? "#1f7a3a" : "#6fcf87"
        case "yellow": return resolvedMode == "light" ? "#8a6d00" : "#e5c736"
        default: return "#000000"
        }
    }

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
        ("operator", "Operator"),
        ("syntax_keyword", "Keyword"),
        ("syntax_function", "Function"),
        ("syntax_string", "String"),
        ("syntax_number", "Number"),
        ("syntax_type", "Type"),
        ("syntax_variable", "Variable"),
        ("syntax_property", "Property"),
        ("syntax_comment", "Comment"),
        ("syntax_punctuation", "Punctuation"),
    ]

    func pinnedShadeCount() -> Int {
        Self.shadeKeys.filter { extendedHex[$0.key] != nil }.count
            + Self.uiRoles.filter { extendedHex["ui_\($0.role)"] != nil }.count
    }

    func clearShadePins() {
        guard pinnedShadeCount() > 0 else { return }
        pushHistory(nil)
        for slot in Self.shadeKeys { extendedHex.removeValue(forKey: slot.key) }
        // the Omacosy UI overrides ride the same "back to auto" reset
        for r in Self.uiRoles { extendedHex.removeValue(forKey: "ui_\(r.role)") }
        extendedHex.removeValue(forKey: "background")
        edited()
        update()
        refreshRender()
    }
    static let ansiLabels = ["BG", "RD", "GR", "YL", "BL", "MG", "CY", "FG",
                             "DIM", "RD+", "GR+", "YL+", "BL+", "MG+", "CY+", "FG+"]

    private(set) var modeGroups: [(label: String, modes: [(value: String, label: String)])] = []
    private(set) var paletteGeneration = 0
    private var renderGeneration = 0
    private var syntaxLoadGeneration = 0
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
        // new palette, and the accent is its ANSI blue slot. For Magic the
        // accent is the wallpaper's own role accent (`palette magic --roles`)
        // so the draft and the raw theme stay one theme; without it the
        // palette's blue slot stands in.
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
                if let v = raw as? String {
                    // the bare "background" is the earlier spelling of ui_background
                    extendedHex[key == "background" ? "ui_background" : key] = v
                }
            }
        }
        method = (pal["method"] as? String) ?? "magic"
        mode = (pal["mode"] as? String) ?? "auto"
        resolvedMode = (pal["resolvedMode"] as? String) ?? "dark"
        syntax = (pal["syntax"] as? String) ?? "classic"
        if !["classic", "grouped", "neighboring", "expressive"].contains(syntax) {
            syntax = "classic"
        }
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
        // The header Reset also returns every Omacosy UI override to auto, so
        // it is not a no-op once only a background has been picked. It never
        // reverts the palette to the last save (Undo/⌘Z steps back).
        let hasUI = Self.uiRoles.contains { extendedHex["ui_\($0.role)"] != nil }
            || extendedHex["background"] != nil
        guard !adjustments.isIdentity || !curve.isEmpty || hasUI else { return }
        pushHistory(nil)
        adjustments = EditorAdjustments()
        curve = []
        for r in Self.uiRoles { extendedHex.removeValue(forKey: "ui_\(r.role)") }
        extendedHex.removeValue(forKey: "background")
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
                     mode: mode, resolvedMode: resolvedMode, syntax: syntax,
                     sourceName: sourceName, appOverrides: appOverrides,
                     toolOpacity: toolOpacity)
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
        syntax = e.syntax
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
            // roles come back from `palette roles` as a bare 6-char hex; the
            // inspector edits "#rrggbb", so normalise before handing it over
            if key.hasPrefix("ui_") {
                let role = String(key.dropFirst(3))
                return cleanHex(extendedHex[key] ?? "") ?? derivedUIRole(role)
            }
            if key == "operator" {
                return extendedHex[key] ?? syntaxColors["operator"]
                    ?? shades["operator"]
                    ?? (baseColors.indices.contains(12) ? baseColors[12] : "#000000")
            }
            if key.hasPrefix("syntax_") {
                let role = String(key.dropFirst(7))
                let slot: Int
                switch role {
                case "keyword": slot = 13
                case "function": slot = 4
                case "string": slot = 2
                case "number": slot = 1
                case "type": slot = 3
                case "variable": slot = 7
                case "property": slot = 6
                case "comment": slot = 8
                default: slot = 12
                }
                return extendedHex[key] ?? syntaxColors[role]
                    ?? (baseColors.indices.contains(slot) ? baseColors[slot] : "#000000")
            }
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
            if key.hasPrefix("ui_") {
                let role = String(key.dropFirst(3))
                return Self.uiRoles.first { $0.role == role }?.label ?? role.capitalized
            }
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

    private func update() {
        onUpdate?()
        // A dropdown opened before its strips finished now fills in place;
        // the old snapshot forced the user to close and reopen it.
        MethodPicker.refreshStrips()
    }
    private func edited() { onUserEdit?() }

    private func defaultExtended(_ colors: [String], accent: String?) -> [String: String] {
        paletteExtendedDefaults(colors, accent: accent)
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
        case "operator": return shades["operator"] ?? slot(12)
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

    func setSyntaxVariety(_ value: String) {
        let allowed = ["classic", "grouped", "neighboring", "expressive"]
        guard allowed.contains(value), syntax != value else { return }
        pushHistory(nil)
        syntax = value
        edited()
        update()
        loadSyntax(finalColors)
    }

    // The token map the mock terminal draws with. It follows the rendered
    // palette and the syntax variety, and is the same map the exporters use.
    private func loadSyntax(_ colors: [String]) {
        guard colors.count == 16 else { return }
        syntaxLoadGeneration += 1
        let generation = syntaxLoadGeneration
        let csv = colors.joined(separator: ",")
        let variety = syntax
        var args = "palette syntax --colors \(shellQuote(csv)) --variety \(variety)"
        if let pin = extendedHex["operator"], !pin.isEmpty {
            args += " --operator \(shellQuote(pin))"
        }
        var pins: [String: String] = [:]
        for (key, value) in extendedHex where key.hasPrefix("syntax_") {
            pins[String(key.dropFirst(7))] = value
        }
        if !pins.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: pins, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            args += " --syntax-json \(shellQuote(json))"
        }
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore("\(args) --json")
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            else { return }
            DispatchQueue.main.async {
                // A later palette/variety change wins even if this process
                // finishes last.
                guard self.syntaxLoadGeneration == generation else { return }
                self.syntaxColors = obj
                self.update()
            }
        }
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
            // Magic asks for one object that carries both the 16 colours and
            // the role accent; a separate --roles run would repeat the same
            // six-pass analysis.
            let cmd = m == "magic"
                ? "palette magic \(q) --roles --json"
                : "palette extract \(q) --mode \(m)\(light ? " --light" : "") --json"
            let (code, out) = self.themecore(cmd)
            var colors: [String] = []
            var magicAccent: String? = nil
            if code == 0, let data = out.data(using: .utf8),
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                colors = obj["colors"] as? [String] ?? []
                // A magic re-extraction is the wallpaper's own theme again:
                // the accent returns to the picture's role accent (so the
                // edition matches the raw Wallpaper cell), not the palette's
                // ANSI blue slot.
                magicAccent = obj["accent"] as? String
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
                self.loadSyntax(final)
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
                  var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            else { return }
            // The operator is Omacosy's own syntax role, not one of Aether's
            // shades, but the swatch and the template overrides read it from
            // the same dictionary.
            let (ocode, oout) = self.themecore("palette operator --colors \(shellQuote(csv)) --json")
            if ocode == 0, let odata = oout.data(using: .utf8),
               let oobj = (try? JSONSerialization.jsonObject(with: odata)) as? [String: String],
               let op = oobj["operator"] {
                obj["operator"] = op
            }
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
        var ui: [String: String] = [:]
        for r in Self.uiRoles {
            if let h = extendedHex["ui_\(r.role)"], !h.isEmpty { ui[r.role] = h }
        }
        if !ui.isEmpty, let d = try? JSONSerialization.data(withJSONObject: ui),
           let s = String(data: d, encoding: .utf8) {
            args += " --ui-json \(shellQuote(s))"
        }
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

    // The mini palette strips the Method picker shows. A draft seeds the
    // Magic strip itself, so it appears at once; the mode strips come from
    // one `palette strips` pass that samples the picture once and generates
    // every mode from the shared dominant colours. An edition seeds no strip
    // (`seedEdition` clears the map), so Magic is fetched beside them — it is
    // its own six-pass analysis, not one of the generated modes, and without
    // this the row stayed a row of placeholders. No delay and no poll: the
    // results land on main, and an already-open picker redraws through
    // update().
    private func loadStrips() {
        guard !extractSource.isEmpty else { return }
        stripGeneration += 1
        let gen = stripGeneration
        let q = shellQuote(extractSource)
        let light = resolvedMode == "light"
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore("palette strips \(q)\(light ? " --light" : "") --json")
            guard self.stripGeneration == gen else { return }
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let modes = obj["modes"] as? [String: [String]]
            else { return }
            DispatchQueue.main.async {
                guard self.stripGeneration == gen else { return }
                for (value, colors) in modes where colors.count == 16 {
                    self.strips[value] = colors
                }
                self.update()
            }
        }
        // Magic runs alongside the bulk pass: on a cold image it is the
        // slower of the two, and the picker fills the row when it lands.
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = self.themecore("palette extract \(q) --mode magic --json")
            guard self.stripGeneration == gen else { return }
            guard code == 0, let data = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let colors = obj["colors"] as? [String], colors.count == 16
            else { return }
            DispatchQueue.main.async {
                guard self.stripGeneration == gen else { return }
                self.strips["magic"] = colors
                self.update()
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
        needsDisplay = true
    }

    // Draw our own swatch so the well follows the window-corner setting — a
    // round bubble when the machine is rounded, a square when it is square.
    // NSColorWell's own chrome has a fixed system radius we cannot set.
    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = min(windowCornerRadius(bounds.height / 2), min(inset.width, inset.height) / 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        (color.usingColorSpace(.sRGB) ?? color).setFill()
        path.fill()
        palette.muted.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()
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
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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
    private let liveApply: Bool
    // Set by the editor's Method picker only: it returns the model's current
    // strips, so a row that was still a placeholder when the card opened
    // fills in when the palette load lands instead of staying blank until
    // the card is reopened.
    private var liveStrips: (() -> [String: [String]])?
    private var completion: ((String) -> Void)?
    private var monitors: [Any] = []
    private let W: CGFloat
    // sized to the list at init, so a short dropdown is a short card; the long
    // Method/Presets lists still cap at the original 430
    private let H: CGFloat

    private init(rows: [Row], strips: [String: [String]], currentMethod: String,
                 title: String, liveApply: Bool,
                 liveStrips: (() -> [String: [String]])?,
                 width: CGFloat,
                 completion: @escaping (String) -> Void) {
        self.rows = rows
        self.liveApply = liveApply
        self.liveStrips = liveStrips
        self.completion = completion
        self.W = max(150, min(340, width))
        let h = min(430, max(80, MethodPickerList.height(for: rows) + 20 + 32))
        self.H = h
        window = PickerWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: h),
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
                        liveApply: Bool = false,
                        liveStrips: (() -> [String: [String]])? = nil,
                        width: CGFloat = 340,
                        completion: @escaping (String) -> Void) {
        active?.close()
        let p = MethodPicker(rows: rows, strips: strips, currentMethod: currentMethod,
                             title: title, liveApply: liveApply, liveStrips: liveStrips,
                             width: width, completion: completion)
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

    // Called from PaletteModel.update(); only the card that supplied a
    // liveStrips closure (the editor's Method picker) does anything, so the
    // presets and filter cards keep the fixed strips they were opened with.
    static func refreshStrips() { active?.refreshLiveStrips() }

    private func refreshLiveStrips() {
        guard let liveStrips else { return }
        root.setStrips(liveStrips())
    }

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
        guard let i = Self.stepped(selected, delta, rows: rows) else { return }
        selected = i
        root.setSelected(i)
        // Where the choice drives a live surface (the editor's Method and
        // Presets), the highlighted row applies at once: the palette or the
        // picture follows the arrows, and Return or a click is only ever a
        // way to close. Opt-in — pickers whose pick fires a network search
        // (the Wallpapers filters) must stay apply-on-pick.
        if liveApply, let v = rows[i].value { completion?(v) }
    }

    // The first selectable row `delta` steps away, walking over group
    // headers; nil when the list ends. Pure, so the arrow walk is testable
    // off-screen.
    static func stepped(_ from: Int, _ delta: Int, rows: [Row]) -> Int? {
        var i = from
        repeat { i += delta } while rows.indices.contains(i) && rows[i].value == nil
        guard rows.indices.contains(i), rows[i].value != nil else { return nil }
        return i
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
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(10), yRadius: windowCornerRadius(10))
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

    func setStrips(_ next: [String: [String]]) {
        guard next != strips else { return }
        strips = next
        list.strips = next
        list.needsDisplay = true
    }

    func scrollToSelected() { list.scrollRowIntoView(selected, in: scroll) }

    // An arrow move must reach the LIST, not just this card's index: the
    // list is what draws the highlighted row and autoscrolls to it. Setting
    // only the card's copy left the move invisible (Return still picked the
    // unseen row), which read as "the arrow keys do nothing".
    func setSelected(_ i: Int) {
        selected = i
        list.selected = i
        list.needsDisplay = true
        needsDisplay = true
        scrollToSelected()
    }
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
            // Palette-strip pickers reserve the strip and checkmark; a plain
            // picker such as Launcher only needs room for the checkmark.
            let labelW = bounds.width - (strips.isEmpty ? 46 : 170)
            drawMidLeft(truncate(row.label, nerdFont("Regular", 12), labelW),
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
    private let valueField = DrawnTextField()
    private var dragging = false

    static let rowHeight: CGFloat = 26

    init(spec: SliderField) {
        self.spec = spec
        super.init(frame: .zero)
        value = spec.def
        // DrawnTextField: right-aligned value and caret, no box
        valueField.horizontal = .right
        valueField.boxAlpha = 0
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
        valueField.needsDisplay = true
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
                                 xRadius: windowCornerRadius(2), yRadius: windowCornerRadius(2))
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
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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

// The one AA tally behind the two readouts — the Accessibility table's
// summary and the preview's pill: checks at or above WCAG AA (4.5) and the
// total, so the two can never disagree about the same palette.
func contrastAATally(_ rows: [PaletteModel.ContrastRow]) -> (pass: Int, total: Int) {
    (rows.flatMap { $0.ratios }.filter { $0 >= 4.5 }.count, rows.count * 3)
}

// The preview pill's compact spelling of the same tally ("AA 21/27").
func contrastAAPillText(_ rows: [PaletteModel.ContrastRow]) -> String {
    let t = contrastAATally(rows)
    return "AA \(t.pass)/\(t.total)"
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
        let variantCards: [Card]
        let fullWidth: Bool

        init(title: String, cards: [Card], variantCards: [Card] = [],
             fullWidth: Bool = false) {
            self.title = title
            self.cards = cards
            self.variantCards = variantCards
            self.fullWidth = fullWidth
        }
    }

    var groups: [Group] = [] { didSet { needsDisplay = true; needsLayout = true } }
    var editTarget: PaletteModel.EditTarget? { didSet { needsDisplay = true } }
    // Keys whose value is an explicit pin (a shade or the UI Background), so
    // the "Reset N pinned" count has something visible to point at.
    var pinnedKeys: Set<String> = [] { didSet { needsDisplay = true } }
    var onEdit: ((PaletteModel.EditTarget) -> Void)?
    var syntaxVariety = "classic" { didSet { varietyButton.title = Self.varietyTitle(syntaxVariety) } }
    var onVariety: ((String) -> Void)?

    private let varietyButton = PopupButtonView()
    private static func varietyTitle(_ value: String) -> String {
        switch value {
        case "grouped": return "Variant Style: Grouped"
        case "neighboring": return "Variant Style: Neighboring"
        case "expressive": return "Variant Style: Expressive"
        default: return "Variant Style: Classic"
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        varietyButton.isHidden = true
        varietyButton.onClick = { [weak self] in self?.showVarietyPicker() }
        addSubview(varietyButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func showVarietyPicker() {
        let rows = [
            MethodPicker.Row(header: nil, value: "classic",
                             label: "Classic — Shipped"),
            MethodPicker.Row(header: nil, value: "grouped",
                             label: "Grouped — One colour"),
            MethodPicker.Row(header: nil, value: "neighboring",
                             label: "Neighboring — Close"),
            MethodPicker.Row(header: nil, value: "expressive",
                             label: "Expressive — Wider"),
        ]
        MethodPicker.present(from: varietyButton, rows: rows, strips: [:],
                             currentMethod: syntaxVariety, title: "Variant Style",
                             liveApply: true) { [weak self] value in
            self?.onVariety?(value)
        }
    }

    static let groupH: CGFloat = 86
    static let rowGap: CGFloat = 8
    // One extra read-only row for the derived variants under the base
    // swatches (card + label).
    static let variantRowH: CGFloat = 50

    // Rows are counted the same way `boxes()` places them, so a full-width
    // group gets its own row and the section's height always covers it.
    static func rowCount(_ groups: [Group]) -> Int {
        var rows = 0
        var halfRow = false
        for group in groups {
            if group.fullWidth {
                if halfRow { rows += 1; halfRow = false }
                rows += 1
            } else if halfRow {
                rows += 1
                halfRow = false
            } else {
                halfRow = true
            }
        }
        if halfRow { rows += 1 }
        return max(1, rows)
    }

    static func height(for groups: [Group]) -> CGFloat {
        let rows = rowCount(groups)
        let extras = groups.reduce(CGFloat(0)) {
            $0 + ($1.variantCards.isEmpty ? 0 : Self.variantRowH)
        }
        return groupH * CGFloat(rows) + rowGap * CGFloat(rows - 1) + extras
    }

    private func boxes() -> [(group: Group, box: NSRect, cards: [NSRect],
                              variants: [NSRect])] {
        guard !groups.isEmpty, bounds.width > 0 else { return [] }
        let colGap: CGFloat = 8
        let colW = (bounds.width - colGap) / 2
        var out: [(Group, NSRect, [NSRect], [NSRect])] = []
        var row = 0, col = 0
        var extra: CGFloat = 0
        for group in groups {
            // A full-width group starts on a fresh row, even after a lone
            // half-width card.
            if group.fullWidth && col != 0 { row += 1; col = 0 }
            let x = group.fullWidth ? 0 : CGFloat(col) * (colW + colGap)
            let width = group.fullWidth ? bounds.width : colW
            let groupHeight = Self.groupH + (group.variantCards.isEmpty ? 0 : Self.variantRowH)
            let top = CGFloat(row) * (Self.groupH + Self.rowGap) + extra
            let box = NSRect(x: x, y: bounds.height - top - groupHeight,
                             width: width, height: groupHeight)
            let padX: CGFloat = 10
            let n = max(1, group.cards.count)
            let gap: CGFloat = 5
            let naturalW = (box.width - padX * 2 - CGFloat(n - 1) * gap) / CGFloat(n)
            // Syntax swatches stay small so more roles fit on the row later.
            let cardW = (group.fullWidth || n == 1) ? min(naturalW, 110) : naturalW
            var rects: [NSRect] = []
            // The base cards stay 30 pt below the group top; a taller group
            // grows downward to fit the variant row.
            let cardTop = box.maxY - 30
            for j in 0..<group.cards.count {
                let cx = box.minX + padX + CGFloat(j) * (cardW + gap)
                rects.append(NSRect(x: cx, y: cardTop - 34, width: cardW, height: 34))
            }
            var variantRects: [NSRect] = []
            if !group.variantCards.isEmpty {
                let vn = max(1, group.variantCards.count)
                let vGap: CGFloat = 5
                let vW = min((box.width - padX * 2 - CGFloat(vn - 1) * vGap) / CGFloat(vn), 130)
                let vTop = cardTop - 58
                for j in 0..<group.variantCards.count {
                    let cx = box.minX + padX + CGFloat(j) * (vW + vGap)
                    variantRects.append(NSRect(x: cx, y: vTop - 24, width: vW, height: 24))
                }
                extra += Self.variantRowH
            }
            out.append((group, box, rects, variantRects))
            if group.fullWidth {
                row += 1
                col = 0
            } else {
                col += 1
                if col == 2 { row += 1; col = 0 }
            }
        }
        return out
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0,
              let box = boxes().first(where: { $0.group.title == "Syntax" })?.box else {
            varietyButton.isHidden = true
            return
        }
        // In the group's header row, beside the SYNTAX title and above the
        // cards: the same 20 pt trigger height the Method/Presets pickers use.
        let w: CGFloat = 250
        varietyButton.isHidden = false
        varietyButton.frame = NSRect(x: box.maxX - 10 - w, y: box.maxY - 26,
                                     width: w, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (group, box, rects, variantRects) in boxes() {
            let boxPath = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
            palette.itemBG.withAlphaComponent(0.22).setFill()
            boxPath.fill()
            // The full-width Syntax row has a long bottom edge; keep it
            // quieter than the half-width groups so it does not read as a
            // rule under the swatch labels.
            palette.muted.withAlphaComponent(group.fullWidth ? 0.08 : 0.15).setStroke()
            boxPath.lineWidth = 1
            boxPath.stroke()
            drawTopLeft(group.title.uppercased(), nerdFont("Bold", 9), palette.muted,
                        x: box.minX + 10, top: bounds.height - box.maxY + 8, height: bounds.height)
            if group.title == "Syntax" {
                drawTopLeft("Variants follow the dropdown.", nerdFont("Regular", 9), palette.muted,
                            x: box.minX + 62, top: bounds.height - box.maxY + 9,
                            height: bounds.height)
            }
            for (j, card) in group.cards.enumerated() {
                let r = rects[j]
                let path = NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(4), yRadius: windowCornerRadius(4))
                nsColor(fromHex: card.hex).setFill()
                path.fill()
                let light = relativeLuminance(nsColor(fromHex: card.hex)) > 0.5
                let main: NSColor = light ? .black : .white
                drawMidLeft(card.hex, nerdFont("Regular", 8), main.withAlphaComponent(0.85),
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
                    // a pin marker in the top-right corner, so the "Reset N
                    // pinned" count points at a card the user can see
                    if pinnedKeys.contains(key) {
                        let dot = NSRect(x: r.maxX - 8, y: r.maxY - 8, width: 6, height: 6)
                        let dotPath = NSBezierPath(ovalIn: dot)
                        palette.accent.setFill()
                        dotPath.fill()
                        main.withAlphaComponent(0.55).setStroke()
                        dotPath.lineWidth = 1
                        dotPath.stroke()
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
            for (j, card) in group.variantCards.enumerated() {
                let r = variantRects[j]
                let path = NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(3),
                                        yRadius: windowCornerRadius(3))
                nsColor(fromHex: card.hex).setFill()
                path.fill()
                let light = relativeLuminance(nsColor(fromHex: card.hex)) > 0.5
                let main: NSColor = light ? .black : .white
                drawMidLeft(card.hex, nerdFont("Regular", 7), main.withAlphaComponent(0.85),
                            x: r.minX + 4, midTop: bounds.height - r.maxY + r.height - 8,
                            height: bounds.height)
                drawMidCenter(card.label, nerdFont("Regular", 8),
                              palette.label.withAlphaComponent(0.72),
                              centerX: r.midX, midTop: bounds.height - r.minY + 4,
                              height: bounds.height)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (group, _, rects, _) in boxes() {
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
        NSBezierPath(roundedRect: track, xRadius: windowCornerRadius(trackH / 2), yRadius: windowCornerRadius(trackH / 2)).fill()
        guard let value else { return }
        let v = CGFloat(max(0, min(100, value))) / 100
        let fill = NSRect(x: 0, y: track.minY, width: bounds.width * v, height: trackH)
        palette.accent.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: fill, xRadius: windowCornerRadius(trackH / 2), yRadius: windowCornerRadius(trackH / 2)).fill()
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
        let cardPath = NSBezierPath(roundedRect: card, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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
        let ipath = NSBezierPath(roundedRect: ir, xRadius: windowCornerRadius(5), yRadius: windowCornerRadius(5))
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
            let path = NSBezierPath(roundedRect: rect, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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
            let path = NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(4), yRadius: windowCornerRadius(4))
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
    private let valueField = DrawnTextField()
    private var dragging = false

    static let rowHeight: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // DrawnTextField: right-aligned value and caret, no box
        valueField.horizontal = .right
        valueField.boxAlpha = 0
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
        valueField.needsDisplay = true
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
        let track = NSBezierPath(roundedRect: trackRect, xRadius: windowCornerRadius(2), yRadius: windowCornerRadius(2))
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
                                  xRadius: windowCornerRadius(1.5), yRadius: windowCornerRadius(1.5))
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

    private let previewWell = ColorWellView()
    private let hexField = DrawnTextField()
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
        // The header swatch opens the same colour picker as the Palette Grade
        // and From Colour wells, so it can sample the preview.
        previewWell.toolTip = "Pick Colour"
        previewWell.onChange = { [weak self] hex in self?.onColor?(hex) }
        addSubview(previewWell)
        // DrawnTextField draws its own box + centred value, so it needs no
        // bezel/background/alignment here; only the input wiring.
        hexField.boxAlpha = 0.25
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
        previewWell.hex = self.hex
        previewWell.isHidden = !active
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
        previewWell.frame = NSRect(x: 0, y: bounds.height - headerTop - 22,
                                   width: 22, height: 22)
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
        // header: the preview well (a subview) + name + hex field
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
            NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(3), yRadius: windowCornerRadius(3)).fill()
            drawMidCenter(h.label, nerdFont("Regular", 9), palette.muted,
                          centerX: r.midX, midTop: bounds.height - r.minY + 8, height: bounds.height)
        }
        for (i, t) in tones.enumerated() {
            let r = toneRects()[i]
            nsColor(fromHex: t).setFill()
            NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(2), yRadius: windowCornerRadius(2)).fill()
            if i == currentTone {
                NSColor.white.setStroke()
                let ring = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: windowCornerRadius(2), yRadius: windowCornerRadius(2))
                ring.lineWidth = 2
                ring.stroke()
            }
        }
        for (i, c) in recents.enumerated() {
            let r = recentRects()[i]
            nsColor(fromHex: c).setFill()
            NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(3), yRadius: windowCornerRadius(3)).fill()
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
        hexField.needsDisplay = true
        previewWell.needsDisplay = true
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
        resetButton.toolTip = "Reset Adjustments and UI Background"
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
                                 currentMethod: model.method, liveApply: true,
                                 liveStrips: { [weak model] in model?.strips ?? [:] }) { [weak model] value in
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
                                     currentMethod: model.sourceName ?? "", liveApply: true) { [weak self] name in
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
        doc.curveResetButton.onClick = { [weak self] in self?.model?.resetCurve() }
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
        // 12 matches the picture column's scroll gap, so both documents get the
        // same content width.
        scroll.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - scrollerW - 12), height: h)
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
    let curveResetButton = ButtonView()
    var sliders: [AdjustmentSliderView] = []
    // palette sources
    let presetsButton = PopupButtonView()
    let fromColorField = DrawnTextField()
    let fromColorWell = ColorWellView()
    let fromColorBuild = ButtonView()
    let gradientStart = DrawnTextField()
    let gradientEnd = DrawnTextField()
    let gradientStartWell = ColorWellView()
    let gradientEndWell = ColorWellView()
    let gradientBuild = ButtonView()
    // Accessibility section data
    var contrast: [PaletteModel.ContrastRow] = []

    // the inspector appears only while a card is selected
    var editorVisible = false

    // The same side padding as the picture column (EditorPanelDoc), so the two
    // panels' contents come out the same width and matching elements line up.
    private let insetL: CGFloat = 12
    private let insetR: CGFloat = 12
    private var methodTop: CGFloat = 0
    private var modeTop: CGFloat = 0
    private var presetsTop: CGFloat = 0
    private var fromColorTop: CGFloat = 0
    private var gradientTop: CGFloat = 0
    private var editorTop: CGFloat = 0
    private var adjTop: CGFloat = 0
    private var adjustmentsTop: CGFloat = 0
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
        curveResetButton.title = "Reset Curve"
        curveResetButton.fontSize = 10
        curveResetButton.secondary = true
        addSubview(curveResetButton)
        for f in EditorAdjustments.fields {
            let s = AdjustmentSliderView(spec: f.spec)
            sliders.append(s)
            addSubview(s)
        }
        presetsButton.title = "Presets"
        addSubview(presetsButton)
        for f in [fromColorField, gradientStart, gradientEnd] {
            // DrawnTextField draws its own box + left-aligned value
            f.horizontal = .left
            f.boxAlpha = 0.35
            f.font = nerdFont("Regular", 12)
            f.usesSingleLineMode = true
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
        var h: CGFloat = 12
        h += 34 + 34                                        // Method + Mode
        h += 34 + 24 + 72 + 72                              // Presets, From Colour, Gradient
        if editorVisible { h += ColorInspectorView.viewHeight + 26 }
        h += 24                                             // Curves
        h += CurveEditorView.viewHeight + 12 + 20 + 24      // curve + Reset Curve row + gap
        h += 30                                             // Adjustments (framed)
        h += CGFloat(sliders.count) * AdjustmentSliderView.rowHeight
        h += 24                                             // gap under the frame
        h += 52 + CGFloat(contrast.count) * 26              // Accessibility (framed)
        h += 12
        return h
    }

    private func rect(top: CGFloat, h: CGFloat, x: CGFloat, w: CGFloat) -> NSRect {
        NSRect(x: x, y: bounds.height - top - h, width: w, height: h)
    }

    override func layout() {
        super.layout()
        var top: CGFloat = 12
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
        // the two generator sections run on the same rhythm: 24 above the
        // heading, 24 to its controls, 72 per section
        fromColorTop = top + 24
        let wellS: CGFloat = 24, buildW: CGFloat = 64
        fromColorWell.frame = rect(top: fromColorTop + 24, h: wellS, x: insetL, w: wellS)
        fromColorField.frame = rect(top: fromColorTop + 25, h: 22, x: insetL + wellS + 6, w: 62)
        fromColorBuild.frame = rect(top: fromColorTop + 24, h: 24, x: insetL + contentW - buildW, w: buildW)
        top = fromColorTop + 72
        gradientTop = top
        let gW: CGFloat = 62
        gradientStartWell.frame = rect(top: gradientTop + 24, h: wellS, x: insetL, w: wellS)
        gradientStart.frame = rect(top: gradientTop + 25, h: 22, x: insetL + wellS + 6, w: gW)
        gradientEndWell.frame = rect(top: gradientTop + 24, h: wellS,
                                     x: insetL + wellS + 6 + gW + 6, w: wellS)
        gradientEnd.frame = rect(top: gradientTop + 25, h: 22,
                                 x: insetL + wellS + 6 + gW + 6 + wellS + 6, w: gW)
        gradientBuild.frame = rect(top: gradientTop + 24, h: 24, x: insetL + contentW - buildW, w: buildW)
        top = gradientTop + 72
        if editorVisible {
            editorTop = top + 16
            inspector.frame = rect(top: editorTop, h: ColorInspectorView.viewHeight,
                                   x: insetL, w: contentW)
            top += ColorInspectorView.viewHeight + 20
        }
        adjTop = top
        top += 24
        curveView.frame = rect(top: top, h: CurveEditorView.viewHeight, x: insetL, w: contentW)
        top += CurveEditorView.viewHeight + 12
        curveResetButton.frame = rect(top: top, h: 20, x: insetL + contentW - 84, w: 84)
        top += 20 + 24
        // the same 24 pt below the Reset Curve button as the picture column, so
        // both curves lead into their next section title by the same amount
        adjustmentsTop = top
        // 30, like the picture column's framed sections: 24 to the frame edge
        // plus the frame's 6 pt inner padding, so the rows sit the same way
        top += 30
        adjSliderTop = top
        for s in sliders {
            // inset inside the frame so the label and value never touch its line
            s.frame = rect(top: top, h: AdjustmentSliderView.rowHeight,
                           x: insetL + 10, w: contentW - 20)
            top += AdjustmentSliderView.rowHeight
        }
        adjSliderBottom = top
        // 24 below the last slider row: the Adjustments frame edge sits 6 lower,
        // so the Accessibility heading clears it by 18 — the same distance the
        // picture column's framed sections leave before their next title
        top += 24
        contrastTop = top
    }

    // A hairline above a section's heading, matching the wallpaper editor's
    // rules: each feature block gets its own visual panel, with 10 pt between
    // the line and its heading.
    private func drawRule(_ top: CGFloat) {
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: insetL, y: bounds.height - (top - 10), width: contentW, height: 1).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawMidLeft("Mode", nerdFont("Bold", 12), palette.accent,
                    x: insetL, midTop: modeTop + 16, height: bounds.height)
        drawMidLeft("Method", nerdFont("Bold", 12), palette.accent,
                    x: insetL, midTop: methodTop + 16, height: bounds.height)
        drawMidLeft("Presets", nerdFont("Bold", 12), palette.accent,
                    x: insetL, midTop: presetsTop + 16, height: bounds.height)
        drawRule(fromColorTop)
        drawTopLeft("From Colour", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: fromColorTop, height: bounds.height)
        drawRule(gradientTop)
        drawTopLeft("Gradient", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: gradientTop, height: bounds.height)
        if editorVisible { drawRule(editorTop) }
        drawRule(adjTop)
        drawTopLeft("Curves", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: adjTop, height: bounds.height)
        // "Adjustments" titles the slider block that follows the curve frame
        drawTopLeft("Adjustments", nerdFont("Bold", 12), palette.accent,
                    x: insetL, top: adjustmentsTop, height: bounds.height)
        // a rounded 1 px frame around the twelve slider rows; it shares the
        // column's left and right edges with the controls above it
        let frame = NSRect(x: insetL, y: bounds.height - adjSliderBottom - 6,
                           width: contentW, height: (adjSliderBottom - adjSliderTop) + 12)
        let path = NSBezierPath(roundedRect: frame, xRadius: windowCornerRadius(8), yRadius: windowCornerRadius(8))
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
        let tally = contrastAATally(contrast)
        let summary = "\(tally.pass) of \(tally.total) pass AA"
        let sf = nerdFont("Regular", 10)
        drawMidLeft(summary, sf, palette.muted,
                    x: insetL + contentW - advance(summary, sf), midTop: contrastTop + 9,
                    height: h)

        // the table sits in its own frame, the same shape as the Adjustments
        // block above: heading +24 to the frame edge, 6 pt of inner padding
        let frame = rect(top: contrastTop + 24, h: 28 + CGFloat(contrast.count) * 26,
                         x: insetL, w: contentW)
        let box = NSBezierPath(roundedRect: frame, xRadius: windowCornerRadius(8),
                               yRadius: windowCornerRadius(8))
        palette.muted.withAlphaComponent(0.4).setStroke()
        box.lineWidth = 1
        box.stroke()

        // rows inset inside the frame so nothing touches its line, matching the
        // slider rows above
        let innerL = insetL + 10
        let innerR = insetL + contentW - 10
        let colW: CGFloat = 64
        let centres = [innerR - colW * 2.5,
                       innerR - colW * 1.5,
                       innerR - colW * 0.5]
        for (i, title) in ["BAR", "PILL", "SURFACE"].enumerated() {
            drawMidCenter(title, nerdFont("Regular", 9), palette.muted,
                          centerX: centres[i], midTop: contrastTop + 34, height: h)
        }
        for (i, row) in contrast.enumerated() {
            let mid = contrastTop + 59 + CGFloat(i) * 26
            // the same label font as the Adjustments sliders
            drawMidLeft(row.name, nerdFont("Regular", 11), palette.label,
                        x: innerL, midTop: mid, height: h)
            let dot = NSRect(x: innerL + 62, y: h - mid - 5, width: 10, height: 10)
            let dotPath = NSBezierPath(roundedRect: dot, xRadius: windowCornerRadius(3), yRadius: windowCornerRadius(3))
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
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6)).fill()
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
    // The mock bar's clock: one formatter for every redraw.
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // Overlays, toggled from the toolbar (step 3); on by default so the
    // preview opens as the desktop looks.
    var showMenuBar = true
    var showTerminal = true
    var showRing = true
    // The fake Super+K cheat sheet: the one surface that shows MUTED as the
    // descriptions, LABEL as the keys and ACCENT as the headings. Off by
    // default, toggled from the toolbar.
    var showCheatsheet = false { didSet { needsDisplay = true } }
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
    private let viewCheatsheet = PreviewIconButton()

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
        viewCheatsheet.glyph = "\u{f11c}"
        viewCheatsheet.toolTip = "Cheat Sheet Preview"
        viewCheatsheet.on = false
        viewCheatsheet.onClick = { [weak self] in
            guard let self else { return }
            self.showCheatsheet.toggle(); self.viewCheatsheet.on = self.showCheatsheet
            self.needsDisplay = true
        }
        for b in [toggleMenuBar, toggleTerminal, toggleRing, viewPrompt, viewCode, viewCheatsheet] {
            addSubview(b)
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let s = screen
        guard s.width > 1, s.height > 1 else { return }
        let size: CGFloat = 22, gap: CGFloat = 4
        let items = [toggleMenuBar, toggleTerminal, toggleRing, viewPrompt, viewCode, viewCheatsheet]
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
        let right: [(glyph: String, label: String, color: NSColor)] = [
            ("\u{F035B}", "", r.accent),                // activity
            ("", Self.clockFormatter.string(from: Date()), r.label),  // clock
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

    // A fake Super+K cheat sheet: MUTED descriptions, LABEL keys, ACCENT
    // headings and ITEM_BG keycaps on the BAR_BG_SOLID card. Fitted between
    // the menu bar and the toolbar with a gap top and bottom, and clipped to
    // the preview so it never spills onto the editor's panels. The keys drop
    // the "Super+" prefix (the header carries it). The terminal stands down
    // while the sheet is up (see the draw dispatch).
    private func cheatsheetCard(in screen: NSRect) -> NSRect {
        let margin: CGFloat = 16
        let gap: CGFloat = 12
        let menuBarH: CGFloat = 34
        let toolbarTop = screen.minY + 8 + 22
        let cardTop = screen.maxY - menuBarH - gap
        let cardBottom = toolbarTop + gap
        return NSRect(x: screen.minX + margin, y: cardBottom,
                      width: screen.width - margin * 2, height: max(80, cardTop - cardBottom))
    }

    private func drawCheatsheet(in screen: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: screen).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let r = resolvedRoles()
        // drawCheatsheet and the click-away dismissal share this rect, so
        // the hit test can never disagree with the sheet on screen
        let card = cheatsheetCard(in: screen)
        // the real Super+K sheet follows the window-corner setting (bar.swift's
        // CheatsheetView); the mock must not disagree with it
        let cardPath = NSBezierPath(roundedRect: card, xRadius: windowCornerRadius(10),
                                    yRadius: windowCornerRadius(10))
        r.bar.setFill()
        cardPath.fill()
        r.accent.withAlphaComponent(0.5).setStroke()
        cardPath.lineWidth = 1.5
        cardPath.stroke()

        let pad: CGFloat = 18
        let titleFont = nerdFont("Bold", 13)
        let subFont = nerdFont("Regular", 9)
        let headFont = nerdFont("Bold", 10)
        let keyFont = nerdFont("Bold", 9)
        let actFont = nerdFont("Regular", 9)

        drawGlyph("\u{f11c}", nerdFont("Regular", 14), r.accent,
                  in: NSRect(x: card.minX + pad, y: card.maxY - pad - 18, width: 20, height: 18))
        let titleX = card.minX + pad + 26
        drawBaseline("Keyboard Shortcuts", titleFont, r.accent,
                     x: titleX, baseline: card.maxY - pad - titleFont.capHeight - 1)
        drawBaseline("Super = Caps Lock", subFont, r.muted,
                     x: titleX + advance("Keyboard Shortcuts", titleFont) + 12,
                     baseline: card.maxY - pad - titleFont.capHeight - 1)
        r.muted.withAlphaComponent(0.3).setFill()
        NSRect(x: card.minX + pad, y: card.maxY - pad - 26, width: card.width - pad * 2,
               height: 1).fill()

        let rowH: CGFloat = 18
        // Whole sections only: each stays in one column, never split across.
        let columns: [[(String, [(String, String)])]] = [
            [
                ("Workspaces", [
                    ("1…9", "Focus workspace"),
                    ("⇧1…9", "Move window there"),
                    ("Tab / ⇧Tab", "Next / previous"),
                ]),
            ],
            [
                ("Window", [
                    ("← ↓ ↑ →", "Focus a window"),
                    ("⇧← ↓ ↑ →", "Move a window"),
                    ("F", "Fullscreen"),
                    ("W", "Close window"),
                    ("T", "Toggle floating"),
                    ("J", "Toggle split"),
                ]),
            ],
            [
                ("Apps", [
                    ("Return", "Terminal"),
                    ("⇧Return", "Browser"),
                    ("Space", "Raycast"),
                    ("⇧F", "Files"),
                ]),
                ("Omacosy", [
                    (",", "Settings"),
                    ("K", "This cheat sheet"),
                ]),
            ],
        ]

        let contentW = card.width - pad * 2
        let colGap: CGFloat = 24
        let colW = (contentW - colGap * 2) / 3
        let topY = card.maxY - pad - 42
        var colX = card.minX + pad
        for col in columns {
            var y = topY
            let keyW = col.flatMap { $0.1 }.map { advance($0.0, keyFont) }.max() ?? 0
            for (si, section) in col.enumerated() {
                if si > 0 { y -= 8 }
                drawBaseline(section.0.uppercased(), headFont, r.accent, x: colX, baseline: y)
                r.accent.withAlphaComponent(0.45).setFill()
                NSRect(x: colX, y: y - 5, width: advance(section.0.uppercased(), headFont),
                       height: 1.5).fill()
                y -= rowH + 7
                for (k, a) in section.1 {
                    let kw = advance(k, keyFont) + 12
                    let cap = NSRect(x: colX, y: y - 4, width: kw, height: 16)
                    let capPath = NSBezierPath(roundedRect: cap, xRadius: 4, yRadius: 4)
                    r.pill.setFill()
                    capPath.fill()
                    r.muted.withAlphaComponent(0.4).setStroke()
                    capPath.lineWidth = 1
                    capPath.stroke()
                    drawBaseline(k, keyFont, r.label, x: cap.minX + 6, baseline: y)
                    let actX = colX + keyW + 20
                    drawBaseline(truncate(a, actFont, colX + colW - actX),
                                 actFont, r.muted, x: actX, baseline: y)
                    y -= rowH
                }
            }
            colX += colW + colGap
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
    private var termOrigin = NSPoint(x: 0.16, y: 0.14)
    private var termSize = NSSize(width: 0.68, height: 0.70)
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

    // The mock terminal reads the same token map the exporters use, so the
    // Syntax Variety control is visible here too.
    private enum Token { case kw, str, strEsc, cmt, cmtDoc, attr, fn, fnBuiltin,
                              num, boolean, type, typeBuiltin, property, punct, op, fg }

    private func tokenColor(_ t: Token, _ c: [NSColor], syntax: [String: String]) -> NSColor {
        func pick(_ key: String, _ slot: Int) -> NSColor {
            if let hex = syntax[key] { return nsColor(fromHex: hex) }
            return c.indices.contains(slot) ? c[slot] : .white
        }
        switch t {
        case .fg: return pick("variable", 7)
        case .kw: return pick("keyword", 13)
        case .str: return pick("string", 2)
        case .strEsc: return pick("string.escape", 13)
        case .cmt: return pick("comment", 8)
        case .cmtDoc: return pick("comment.doc", 8)
        case .attr: return pick("attribute", 13)
        case .fn: return pick("function", 4)
        case .fnBuiltin: return pick("function.builtin", 6)
        case .num: return pick("number", 1)
        case .boolean: return pick("boolean", 1)
        case .type: return pick("type", 3)
        case .typeBuiltin: return pick("type.builtin", 7)
        case .property: return pick("property", 6)
        case .punct: return pick("punctuation", 8)
        case .op: return pick("operator", 12)
        }
    }

    // Split + - * / < > out of the plain runs, so the sample shows the
    // operator role without every language needing a hand-written token map.
    private func operatorSegments(_ line: [(String, Token)]) -> [(String, Token)] {
        line.flatMap { seg -> [(String, Token)] in
            guard seg.1 == .fg else { return [seg] }
            var out: [(String, Token)] = []
            var plain = ""
            for ch in seg.0 {
                if "+-*/<>=!&|".contains(ch) {
                    if !plain.isEmpty { out.append((plain, .fg)); plain = "" }
                    out.append((String(ch), .op))
                } else {
                    plain.append(ch)
                }
            }
            if !plain.isEmpty { out.append((plain, .fg)) }
            return out
        }
    }

    // One small function per language, so the same roles light up in each.
    private func sample(_ lang: Int) -> [[(String, Token)]] {
        let name = (String(Self.fileNames[max(0, min(Self.fileNames.count - 1, lang))].dropLast(2)), Token.fn)
        switch lang {
        case 0: return [ // C
            [("/** fibonacci */", .cmtDoc)],
            [("int ", .typeBuiltin), (name.0, .fn), ("(", .punct), ("int", .typeBuiltin), (" n", .fg), (") {", .punct)],
            [("  ", .fg), ("if", .kw), (" ", .fg), ("(", .punct), ("n", .fg), (" ", .fg), ("<", .op), (" ", .fg), ("2", .num), (") ", .punct), ("return", .kw), (" n", .fg), (";", .punct)],
            [("  ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("1", .num), (") ", .punct), ("+", .op), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("2", .num), (");", .punct)],
            [("  ", .fg), ("bool", .typeBuiltin), (" ok", .fg), (" = ", .fg), ("true", .boolean), (";", .punct)],
            [("  ", .fg), ("printf", .fnBuiltin), ("(", .punct), ("\"%d", .str), ("\\n", .strEsc), ("\", ", .str), (name.0, .fn), ("(", .punct), ("8", .num), ("));", .punct)],
            [("}", .punct)],
        ]
        case 1: return [ // JavaScript
            [("/** fibonacci */", .cmtDoc)],
            [("function", .kw), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (") {", .punct)],
            [("  ", .fg), ("if", .kw), (" ", .fg), ("(", .punct), ("n", .fg), (" ", .fg), ("<", .op), (" ", .fg), ("2", .num), (") ", .punct), ("return", .kw), (" n", .fg), (";", .punct)],
            [("  ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("1", .num), (") ", .punct), ("+", .op), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("2", .num), (");", .punct)],
            [("  ", .fg), ("const", .kw), (" ok", .fg), (" = ", .fg), ("true", .boolean), (";", .punct)],
            [("  ", .fg), ("console", .property), (".", .punct), ("log", .fnBuiltin), ("(", .punct), ("\"%d", .str), ("\\n", .strEsc), ("\", ", .str), ("ok", .fg), (");", .punct)],
            [("}", .punct)],
        ]
        case 2: return [ // Python
            [("\"\"\"fibonacci\"\"\"", .cmtDoc)],
            [("def", .kw), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), ("):", .punct)],
            [("    ", .fg), ("if", .kw), (" n ", .fg), ("<", .op), (" ", .fg), ("2", .num), (": ", .punct), ("return", .kw), (" n", .fg)],
            [("    ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("1", .num), (") ", .punct), ("+", .op), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("2", .num), (")", .punct)],
            [("    ", .fg), ("ok", .fg), (" = ", .fg), ("True", .boolean)],
            [("    ", .fg), ("print", .fnBuiltin), ("(", .punct), (name.0, .fn), ("(", .punct), ("8", .num), ("))", .punct)],
        ]
        case 3: return [ // Rust
            [("/// fibonacci", .cmtDoc)],
            [("fn", .kw), (" ", .fg), (name.0, .fn), ("(", .punct), ("n: ", .fg), ("u32", .typeBuiltin), (")", .punct), (" -> ", .fg), ("u32", .typeBuiltin), (" {", .punct)],
            [("    ", .fg), ("if", .kw), (" n ", .fg), ("<", .op), (" ", .fg), ("2", .num), (" { ", .punct), ("return", .kw), (" n; ", .fg), ("}", .punct)],
            [("    ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("1", .num), (") ", .punct), ("+", .op), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("2", .num), (")", .punct)],
            [("    ", .fg), ("let", .kw), (" ok", .fg), (" = ", .fg), ("true", .boolean), (";", .punct)],
            [("    ", .fg), ("println!", .fnBuiltin), ("(", .punct), ("\"{}\"", .str), (", ", .fg), (name.0, .fn), ("(", .punct), ("8", .num), ("));", .punct)],
            [("}", .punct)],
        ]
        case 4: return [ // Go
            [("// fibonacci", .cmtDoc)],
            [("func", .kw), (" ", .fg), (name.0, .fn), ("(", .punct), ("n ", .fg), ("int", .typeBuiltin), (") ", .punct), ("int", .typeBuiltin), (" {", .punct)],
            [("    ", .fg), ("if", .kw), (" n ", .fg), ("<", .op), (" ", .fg), ("2", .num), (" { ", .punct), ("return", .kw), (" n ", .fg), ("}", .punct)],
            [("    ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(", .punct), ("n-", .fg), ("1", .num), (") ", .punct), ("+", .op), (" ", .fg), (name.0, .fn), ("(", .punct), ("n-", .fg), ("2", .num), (")", .punct)],
            [("    ", .fg), ("ok", .fg), (" := ", .op), ("true", .boolean)],
            [("    ", .fg), ("fmt", .property), (".", .punct), ("Println", .fnBuiltin), ("(", .punct), (name.0, .fn), ("(", .punct), ("8", .num), ("))", .punct)],
            [("}", .punct)],
        ]
        default: return [ // Java
            [("/** fibonacci */", .cmtDoc)],
            [("int ", .typeBuiltin), (name.0, .fn), ("(", .punct), ("int", .typeBuiltin), (" n", .fg), (") {", .punct)],
            [("    ", .fg), ("if", .kw), (" ", .fg), ("(", .punct), ("n", .fg), (" ", .fg), ("<", .op), (" ", .fg), ("2", .num), (") ", .punct), ("return", .kw), (" n", .fg), (";", .punct)],
            [("    ", .fg), ("return", .kw), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("1", .num), (") ", .punct), ("+", .op), (" ", .fg), (name.0, .fn), ("(", .punct), ("n", .fg), (" - ", .fg), ("2", .num), (");", .punct)],
            [("    ", .fg), ("boolean", .typeBuiltin), (" ok", .fg), (" = ", .fg), ("true", .boolean), (";", .punct)],
            [("    ", .fg), ("System", .typeBuiltin), (".", .punct), ("out", .property), (".", .punct), ("println", .fnBuiltin), ("(", .punct), (name.0, .fn), ("(", .punct), ("8", .num), ("));", .punct)],
            [("}", .punct)],
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

        // the focus ring, outside the window, in the ring role. Window and
        // ring both follow the window-corner setting, like the real ones do
        if showRing {
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3),
                                    xRadius: windowCornerRadius(10), yRadius: windowCornerRadius(10))
            r.ring.setStroke()
            ring.lineWidth = 2.5
            ring.stroke()
        }

        // the window: Ghostty's 0.85 background, so the wallpaper shows through
        // exactly as it does on the desktop
        let body = NSBezierPath(roundedRect: rect, xRadius: windowCornerRadius(8),
                                yRadius: windowCornerRadius(8))
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
            // A compact legend for the token families and their neighbouring
            // variants: the Syntax Variety control changes this line.
            let legend: [(String, Token)] = [
                ("@bench ", .attr), ("fn ", .kw), ("parse", .fn), ("(", .punct),
                ("\"x", .str), ("\\n", .strEsc), ("\", ", .str),
                ("42", .num), (")", .punct), (" -> ", .op), ("true", .boolean),
            ]
            drawLine(legend.map {
                ($0.0, tokenColor($0.1, cols, syntax: model.syntaxColors))
            })
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
                drawLine(operatorSegments(line).map {
                    ($0.0, tokenColor($0.1, cols, syntax: model.syntaxColors))
                })
            }
        }
    }

    // The Accessibility score, pinned over the wallpaper's bottom-left as the
    // twin of the toolbar buttons bottom-right: the same AA tally the
    // Accessibility table prints, so a colour edit can be judged against it
    // without scrolling the Palette Builder down to the table after every
    // change. Recomputed per draw, so it moves with the palette. Drawn in the
    // app's own role pairing — barBG for the surface, accent for the ink —
    // like every other Omacosy chrome element.
    private func drawAAPill(in screen: NSRect) {
        guard let model else { return }
        let rows = model.contrastRows()
        guard !rows.isEmpty else { return }
        let text = contrastAAPillText(rows)
        let font = nerdFont("Bold", 10)
        let pill = NSRect(x: screen.minX + 8, y: screen.minY + 8,
                          width: advance(text, font) + 16, height: 20)
        palette.barBG.setFill()
        NSBezierPath(roundedRect: pill, xRadius: windowCornerRadius(6),
                     yRadius: windowCornerRadius(6)).fill()
        drawBaseline(text, font, palette.accent,
                     x: pill.minX + 8, baseline: pill.midY - font.capHeight / 2)
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
        // clip the drawing (not the subviews) to the pane, so an overlay can
        // never spill onto the editor's own panels; the toolbar buttons are
        // subviews and are left alone
        NSBezierPath(rect: bounds).addClip()

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
            // the cheat sheet takes the terminal's place, so it never sits
            // behind the sheet
            if showTerminal, !showCheatsheet { drawTerminal(in: screen) }
            if showCheatsheet { drawCheatsheet(in: screen) }
            drawAAPill(in: screen)
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
        // The mock overlays dismiss like real overlays do: a click outside
        // the cheat sheet — or outside the terminal when no sheet is up —
        // closes it, and the toolbar toggle follows. The click is spent on
        // the dismissal, so it cannot also start a compare-hold.
        let screen = self.screen
        if showCheatsheet, !cheatsheetCard(in: screen).contains(p) {
            showCheatsheet = false
            viewCheatsheet.on = false
            needsDisplay = true
            return
        }
        if !showCheatsheet, showTerminal, !terminalRect(in: screen).contains(p) {
            showTerminal = false
            toggleTerminal.on = false
            needsDisplay = true
            return
        }
        // the tabs only exist while the terminal is drawn: a stale rect must
        // not switch the language from under the cheat sheet
        if showTerminal, !showCheatsheet, showCode,
           let i = tabRects.firstIndex(where: { $0.contains(p) }) {
            if i != selectedLanguage { selectedLanguage = i; needsDisplay = true }
            return
        }
        if showTerminal, !showCheatsheet, terminalRect(in: screen).contains(p) {
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
        doc.semantic.onVariety = { [weak self] value in self?.model?.setSyntaxVariety(value) }
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
        // The syntax base roles live in their own map: `loadShades` replaces
        // the Aether dictionary wholesale, so they must not share it.
        func syntaxShade(_ role: String, _ fallback: Int) -> String {
            let pin = role == "operator" ? "operator" : "syntax_\(role)"
            return model.extendedHex[pin] ?? model.syntaxColors[role] ?? base(fallback)
        }
        func ext(_ key: String) -> String {
            model.finalExtended[key] ?? model.extendedHex[key] ?? "#000000"
        }
        // An Omacosy UI role: the user's override when set, otherwise the
        // derived value. `derivedUIRole` already returns "#rrggbb".
        func uiHex(_ role: String) -> String {
            cleanHex(model.extendedHex["ui_\(role)"] ?? "") ?? model.derivedUIRole(role)
        }
        // Read-only variants: the row that visibly follows the Syntax Variety
        // dropdown. The base swatches above stay the tunable families.
        func syntaxVariant(_ key: String, _ fallback: Int) -> String {
            model.syntaxColors[key] ?? base(fallback)
        }
        let variantCards: [SemanticSectionView.Card] = [
            .init(label: "String/Escape", hex: syntaxVariant("string.escape", 2)),
            .init(label: "Function/Builtin", hex: syntaxVariant("function.builtin", 4)),
            .init(label: "Type/Builtin", hex: syntaxVariant("type.builtin", 3)),
            .init(label: "Number/Boolean", hex: syntaxVariant("boolean", 1)),
            .init(label: "Comment/Doc", hex: syntaxVariant("comment.doc", 8)),
            .init(label: "Punctuation/Bracket", hex: syntaxVariant("punctuation.bracket", 8)),
        ]
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
            SemanticSectionView.Group(title: "Terminal", cards: [
                .init(label: "Accent", hex: ext("accent"), key: "accent"),
                .init(label: "Cursor", hex: ext("cursor"), key: "cursor"),
                .init(label: "Sel FG", hex: ext("selection_foreground"), key: "selection_foreground"),
                .init(label: "Sel BG", hex: ext("selection_background"), key: "selection_background"),
            ]),
            SemanticSectionView.Group(title: "Omacosy", cards: [
                .init(label: "Background", hex: uiHex("background"), key: "ui_background"),
                .init(label: "Pill", hex: uiHex("pill"), key: "ui_pill"),
                .init(label: "Muted", hex: uiHex("muted"), key: "ui_muted"),
                .init(label: "Label", hex: uiHex("label"), key: "ui_label"),
                .init(label: "Accent", hex: uiHex("accent"), key: "ui_accent"),
            ]),
            SemanticSectionView.Group(title: "Ring & Status", cards: [
                .init(label: "Ring", hex: uiHex("ring"), key: "ui_ring"),
                .init(label: "Red", hex: uiHex("red"), key: "ui_red"),
                .init(label: "Green", hex: uiHex("green"), key: "ui_green"),
                .init(label: "Yellow", hex: uiHex("yellow"), key: "ui_yellow"),
            ]),
            // A full-width row of its own: the operator today, with room for
            // more syntax roles beside it later.
            SemanticSectionView.Group(title: "Syntax", cards: [
                .init(label: "Operator", hex: syntaxShade("operator", 12), key: "operator"),
                .init(label: "Keyword", hex: syntaxShade("keyword", 13), key: "syntax_keyword"),
                .init(label: "Function", hex: syntaxShade("function", 4), key: "syntax_function"),
                .init(label: "String", hex: syntaxShade("string", 2), key: "syntax_string"),
                .init(label: "Number", hex: syntaxShade("number", 1), key: "syntax_number"),
                .init(label: "Type", hex: syntaxShade("type", 3), key: "syntax_type"),
                .init(label: "Variable", hex: syntaxShade("variable", 7), key: "syntax_variable"),
                .init(label: "Property", hex: syntaxShade("property", 6), key: "syntax_property"),
                .init(label: "Comment", hex: syntaxShade("comment", 8), key: "syntax_comment"),
                .init(label: "Punctuation", hex: syntaxShade("punctuation", 8), key: "syntax_punctuation"),
            ], variantCards: variantCards, fullWidth: true),
        ]
        var pinnedKeys: Set<String> = []
        for slot in PaletteModel.shadeKeys where model.extendedHex[slot.key] != nil {
            pinnedKeys.insert(slot.key)
        }
        for r in PaletteModel.uiRoles where model.extendedHex["ui_\(r.role)"] != nil {
            pinnedKeys.insert("ui_\(r.role)")
        }
        doc.semantic.pinnedKeys = pinnedKeys
        doc.semantic.editTarget = model.editTarget
        doc.semantic.syntaxVariety = model.syntax
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
        h += 24                                             // "Palette 16 colors · …"
        h += PaletteCardsView.height(for: 16)
        h += 36                                             // spaced hint line
        h += 24                                             // "Semantic Colors"
        h += SemanticSectionView.height(for: semantic.groups)
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
        top += 24
        colorCards.frame = rect(top: top, h: PaletteCardsView.height(for: 16), x: insetL, w: contentW)
        top += PaletteCardsView.height(for: 16)
        hintTop = top + 12
        top += 36
        semanticTop = top
        top += 24
        let semanticH = SemanticSectionView.height(for: semantic.groups)
        semantic.frame = rect(top: top, h: semanticH, x: insetL, w: contentW)
        top += semanticH
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
        applyButton.busyTitle = "Applying…"
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
    // One shared width for both editing columns: the wallpaper editor (step 1)
    // on the left and the palette builder (step 2) on the right read as a
    // symmetrical pair. 340 keeps the picture column's fixed transform row
    // comfortable; the palette builder gains 20 pt over its old 320.
    private let columnW: CGFloat = 340
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

    // The name field's colours are properties, not drawing, so a palette
    // change has to set them again or the header keeps the old theme.
    func refreshNameField() {
        nameField.textColor = palette.label
        nameField.backgroundColor = palette.itemBG.withAlphaComponent(nameEditable ? 0.5 : 0.25)
    }

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
        // Step 1 (picture) on the left, step 2 (colours) on the right, both
        // the same width so the pair is symmetrical.
        wallpaperEditor.frame = NSRect(x: 0, y: footerH, width: columnW, height: h)
        paletteCanvas.frame = NSRect(x: columnW, y: footerH,
                                     width: max(0, bounds.width - columnW * 2), height: h)
        paletteBuilder.frame = NSRect(x: bounds.width - columnW, y: footerH, width: columnW, height: h)
        footer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: footerH)
        // the name field is the whole title — no static prefix (the editor
        // is obvious from its contents)
        nameField.frame = nameRect
        penButton.frame = penRect
    }

    override func draw(_ dirtyRect: NSRect) {
        // the same card chrome as the dashboard: bar background, accent rim
        let corner = min(windowCornerRadius(10), min(bounds.width, bounds.height) / 2)
        let w = borderWidth()
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: w / 2, dy: w / 2),
                                xRadius: corner, yRadius: corner)
        (palette.barBG).setFill()
        body.fill()
        palette.accent.setStroke()
        body.lineWidth = w
        body.stroke()

        drawMidCenter("✕", nerdFont("Regular", 12), palette.muted,
                      centerX: closeRect.midX, midTop: bounds.height - nameRect.midY,
                      height: bounds.height)

        // column rules, drawn last so they sit on every surface
        palette.muted.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: bounds.height - headerH, width: bounds.width, height: 1).fill()
        let columnH = max(0, bounds.height - headerH - footerH)
        NSRect(x: columnW, y: footerH, width: 1, height: columnH).fill()
        NSRect(x: bounds.width - columnW, y: footerH, width: 1, height: columnH).fill()
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

// Mark a view and every descendant dirty. A palette change has to reach the
// nested parts — the CustomScroller behind each column, the buttons in the
// footer — which a single needsDisplay on the parent does not repaint.
func markTreeNeedsDisplay(_ view: NSView) {
    view.needsDisplay = true
    for sub in view.subviews { markTreeNeedsDisplay(sub) }
}

final class ThemeEditor {
    private static var current: ThemeEditor?

    let window: EditorWindow
    private let root: ThemeEditorView
    private let subject: EditorSubject
    private let model = PaletteModel()
    // the picture editor's own state and history, separate from the palette's
    private let editorState = EditorState()
    // the user's saved filter presets, read from the engine's store
    private var customPresets: [(name: String, values: [String: Any])] = []
    private let status: ((String) -> Void)?
    private var keyMonitor: Any?
    private var outsideMonitor: Any?
    private var resignObserver: NSObjectProtocol?
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
    // The applied theme's palette, saved while the editor previews the draft
    // so it can be put back when the editor closes.
    private var appliedPalette: Palette?

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
                    // Aether's applyPreset: absent sliders reset to neutral,
                    // absent structural fields (crop/rotate/curve/strength)
                    // keep the user's own (Phase 10c)
                    f = f.applyingPreset(preset.values.mapValues { $0 as Any })
                }
            }
        }
        root.wallpaperEditor.onSavePreset = { [weak self] in self?.startSavePreset() }
        root.wallpaperEditor.onImportPresets = { [weak self] in self?.startImportPresets() }
        root.wallpaperEditor.onExportPresets = { [weak self] in self?.startExportPresets() }
        root.wallpaperEditor.onApplyCustomPreset = { [weak self] name in
            guard let self, let entry = self.customPresets.first(where: { $0.name == name }) else { return }
            self.editorState.edit("preset:" + name) { $0 = $0.applyingPreset(entry.values) }
        }
        root.wallpaperEditor.onDeletePreset = { [weak self] name in self?.deletePreset(name) }
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
            // the whole editor previews the draft's Omacosy UI colours live
            self.applyDraftPalette()
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
        refreshCustomPresets()
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
    // global palette, so it must be marked dirty too. The mark walks the
    // WHOLE subtree: the custom scrollbars and the footer buttons are nested
    // views, and a parent's needsDisplay alone leaves them showing the old
    // theme until something else makes them redraw (a scroll, a reopen).
    static func refreshColors() {
        guard let e = current else { return }
        markTreeNeedsDisplay(e.root)
        e.root.paletteBuilder.refreshColors()
        e.root.paletteCanvas.refreshColors()
        e.root.wallpaperEditor.refreshColors()
        e.root.refreshNameField()
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
        // whichever action was pressed shows its own busy state through the
        // render-and-write, not only once the write's second half starts
        if case .apply = action { root.footer.applyButton.busy = true }
        if case .export = action { root.footer.exportButton.busy = true }
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
                if case .apply = action { self.root.footer.applyButton.busy = false }
                if case .export = action { self.root.footer.exportButton.busy = false }
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
                "syntax": model.syntax,
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
                return ("A theme with the same name already exists. Please give a different name.", nil)
            }
            return ("Couldn't save the theme. Try again.", nil)
        }
        // A current engine returns the saved record in the save payload, so
        // the editor does not need a second process. An older engine (or a
        // hand-down binary) falls back to `theme show`.
        if let fresh = obj["record"] as? [String: Any] { return (nil, fresh) }
        let (sc, so) = shell("\(themecoreBin()) theme show \(shellQuote(id)) --json 2>/dev/null")
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
            else { savedNotice("Saved \(name)") }
        case .export(let parent):
            if let id = fresh["id"] as? String { performExport(id: id, into: parent) }
            else { showMessage("Export needs a saved theme.", red: true) }
        case .none:
            savedNotice("Saved \(name)")
        }
    }

    // A finished write reports to the dashboard and says so in the footer,
    // but the editor STAYS OPEN: the cross or Esc is the only way out, so a
    // theme can be saved, applied and re-tested without reopening the editor.
    private func savedNotice(_ message: String) {
        status?(message)
        showMessage(message, red: false)
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
            _ = shell("\(HOME)/.local/bin/omacosy-theme-switch set-theme \(shellQuote(id))")
            DispatchQueue.main.async {
                guard let self else { return }
                self.root.footer.applyButton.busy = false
                self.savedNotice("Applied \(name)")
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

    // Import reads our theme record (JSON or TOML), a flat colors.toml or a
    // Base16 (YAML) scheme. The engine refuses an id that already exists
    // unless told which way to go, so the first try asks, then Rename or
    // Replace re-runs with its flag.
    private func startImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "An Omacosy theme, a colors.toml or a Base16 (YAML) scheme."
        panel.allowedContentTypes = importContentTypes()
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            self.runImport(file: url.path, mode: .ask)
        }
    }

    private func runImport(file: String, mode: ImportMode, name: String? = nil,
                           onFailure: ((String) -> Void)? = nil) {
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
                let message = out.lowercased().contains("already exists")
                    ? "A theme with the same name already exists. Please give a different name."
                    : importErrorMessage(out)
                if let onFailure { onFailure(message) }
                else { self.showMessage(message, red: true, seconds: 6) }
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
            self?.runImport(file: file, mode: .rename, name: name,
                            onFailure: { NamePrompt.showError($0) })
        })
    }

    // --- custom filter presets (Phase 10c) ---------------------------------

    // Load the stored presets through the engine and hand them to the panel.
    private func refreshCustomPresets() {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = shell("\(themecoreBin()) image presets custom list --json 2>/dev/null")
            var list: [(name: String, values: [String: Any])] = []
            if code == 0, let data = out.data(using: .utf8),
               let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                list = arr.compactMap { e in
                    guard let name = e["name"] as? String,
                          let values = e["values"] as? [String: Any] else { return nil }
                    return (name, values)
                }
            }
            DispatchQueue.main.async {
                self.customPresets = list
                self.root.wallpaperEditor.setCustomPresets(list)
            }
        }
    }

    private func startSavePreset() {
        NamePrompt.present(from: root, title: "Save Preset",
                           subtitle: "Name these adjustments to reuse them.",
                           confirmTitle: "Save", initial: "My Preset") { [weak self] name in
            self?.savePreset(name, onFailure: { NamePrompt.showError($0) })
        }
    }

    // The engine reduces the recipe to the fields that differ from the
    // defaults and stores it; an unchanged recipe is refused.
    private func savePreset(_ name: String, onFailure: @escaping (String) -> Void) {
        let recipe = editorState.filters.jsonObject()
        guard let data = try? JSONSerialization.data(withJSONObject: recipe),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = shell("\(themecoreBin()) image presets custom save "
                + "--name \(shellQuote(name)) --filters \(shellQuote(json)) --json 2>&1")
            DispatchQueue.main.async {
                if code == 0 {
                    NamePrompt.closeCurrent()
                    self.refreshCustomPresets()
                    self.showMessage("Saved preset \(name)", red: false)
                } else {
                    onFailure(themecoreMessage(out, fallback: "Could not save the preset."))
                }
            }
        }
    }

    private func deletePreset(_ name: String) {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = shell("\(themecoreBin()) image presets custom delete "
                + "--name \(shellQuote(name)) --json 2>&1")
            DispatchQueue.main.async {
                if code == 0 {
                    self.refreshCustomPresets()
                    self.showMessage("Deleted preset \(name)", red: false)
                } else {
                    self.showMessage(themecoreMessage(out, fallback: "Could not delete the preset."),
                                     red: true)
                }
            }
        }
    }

    private func startExportPresets() {
        guard !customPresets.isEmpty else {
            showMessage("No presets to export", red: false)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "aether-presets.json"
        panel.prompt = "Export"
        panel.message = "An Aether/Omacosy preset file."
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            self.exportPresets(to: url.path)
        }
    }

    private func exportPresets(to path: String) {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = shell("\(themecoreBin()) image presets custom export "
                + "\(shellQuote(path)) --json 2>&1")
            DispatchQueue.main.async {
                if code == 0 {
                    self.showMessage("Exported presets", red: false)
                } else {
                    self.showMessage(themecoreMessage(out, fallback: "Could not export the presets."),
                                     red: true)
                }
            }
        }
    }

    private func startImportPresets() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "An aether-presets.json file."
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            self.importPresets(from: url.path)
        }
    }

    private func importPresets(from path: String) {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let (code, out) = shell("\(themecoreBin()) image presets custom import "
                + "\(shellQuote(path)) --json 2>&1")
            DispatchQueue.main.async {
                if code == 0 {
                    self.refreshCustomPresets()
                    self.showMessage("Imported presets", red: false)
                } else {
                    self.showMessage(themecoreMessage(out, fallback: "Import failed."), red: true)
                }
            }
        }
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
        // A click outside the editor closes it, like Esc and the ✕. The
        // editor's own window, its colour panel, its prompts/sheets (children
        // of it) and system panels (save/open) are "inside"; anything else —
        // the dashboard behind it, or another app — is outside.
        outsideMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            guard let self, let w = e.window else { return e }
            if w === self.window || w === NSColorPanel.shared { return e }
            if w is NSPanel || w.parent === self.window { return e }
            self.close()
            return e
        }
        // Leaving the app (desktop, another app) closes it too, without
        // grabbing focus back.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil,
            queue: .main) { [weak self] _ in
            guard let self, ThemeEditor.current === self else { return }
            if NSColorPanel.shared.isVisible { return }
            self.close(reactivate: false)
        }
        loadSubject()
    }

    private func loadSubject() {
        switch subject {
        case .edition(let e):
            let q = shellQuote(e.id)
            DispatchQueue.global().async { [weak self] in
                let (code, out) = shell("\(themecoreBin()) theme show " + q + " --json 2>/dev/null")
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
                // Its ANSI colours plus OMACOSY_BG ARE the Magic palette (the
                // Phase 2 cross-check pins them), and term-palette reads them
                // in milliseconds instead of a fresh extraction (~0.6 s on 4K).
                let (rc, rout) = shell("\(HOME)/.local/bin/omacosy-custom-theme theme --raw \(q) 2>/dev/null")
                let dir = rout.split(separator: "\n").last.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if rc == 0, !dir.isEmpty {
                    let envFile = NSTemporaryDirectory()
                        + "omacosy-editor-seed-\(ProcessInfo.processInfo.processIdentifier).env"
                    let (tc, _) = shell("\(HOME)/.local/bin/omacosy-term-palette \(shellQuote(dir)) \(shellQuote(envFile)) >/dev/null 2>&1")
                    var byIndex: [Int: String] = [:]
                    var accent: String? = nil
                    var background: String? = nil
                    var resolved = "dark"
                    if tc == 0, let text = try? String(contentsOfFile: envFile, encoding: .utf8) {
                        for line in text.split(separator: "\n") {
                            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                            guard parts.count == 2 else { continue }
                            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                            if parts[0].hasPrefix("OMACOSY_P"), let i = Int(parts[0].dropFirst(9)) {
                                byIndex[i] = value
                            } else if parts[0] == "OMACOSY_BG" {
                                background = value
                            } else if parts[0] == "OMACOSY_ACCENT" {
                                accent = value
                            } else if parts[0] == "OMACOSY_IS_DARK" {
                                resolved = value == "1" ? "dark" : "light"
                            }
                        }
                    }
                    try? FileManager.default.removeItem(atPath: envFile)
                    let colors = magicThemeColors((0..<16).compactMap { byIndex[$0] },
                                                  background: background)
                    if colors.count == 16 {
                        DispatchQueue.main.async {
                            self.model.seedDraft(image: wallpaper, colors: colors,
                                                 accent: accent, resolved: resolved)
                        }
                        return
                    }
                }
                // Fallback: one extraction returns both the roles and the
                // 16 colours. It used to be two full six-pass scans in
                // parallel, which doubled the work for the same answer.
                let (c, o) = shell("\(themecoreBin()) palette magic \(q) --roles --json 2>/dev/null")
                var colors: [String] = []
                var accent: String?
                var resolved = "dark"
                if c == 0, let d = o.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                    colors = obj["colors"] as? [String] ?? []
                    accent = obj["accent"] as? String
                    resolved = (obj["ladder"] as? String) == "light" ? "light" : "dark"
                }
                DispatchQueue.main.async {
                    guard colors.count == 16 else { return }
                    self.model.seedDraft(image: wallpaper, colors: colors,
                                         accent: accent, resolved: resolved)
                }
            }
        }
    }

    // The editor draws from the shared `palette`; point it at the DRAFT's
    // derived Omacosy roles so the whole editor previews the theme being built.
    // The applied palette is saved once and restored on close.
    private func applyDraftPalette() {
        if appliedPalette == nil { appliedPalette = palette }
        guard let applied = appliedPalette, !model.roles.isEmpty else { return }
        func c(_ key: String, _ fallback: NSColor) -> NSColor {
            model.roles[key].map(nsColor(fromHex:)) ?? fallback
        }
        var p = Palette()
        p.barBG = c("bar", applied.barBG)
        p.itemBG = c("pill", applied.itemBG)
        p.accent = c("accent", applied.accent)
        p.label = c("label", applied.label)
        p.muted = c("muted", applied.muted)
        palette = p
        refreshSelectionColors()
        markTreeNeedsDisplay(root)
        if let dash = window.parent as? DashboardWindow, let v = dash.contentView {
            markTreeNeedsDisplay(v)
        }
    }

    // `reactivate` is false when the editor closes because the user moved to
    // another app: the dashboard must not grab focus back then.
    private func close(reactivate: Bool = true) {
        guard ThemeEditor.current === self else { return }
        ThemeEditor.current = nil
        // the editor swapped the global palette to the draft; put the applied
        // theme's back before the dashboard takes over
        palette = loadPalette()
        refreshSelectionColors()
        if let dash = window.parent as? DashboardWindow, let v = dash.contentView {
            markTreeNeedsDisplay(v)
        }
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        if let r = resignObserver { NotificationCenter.default.removeObserver(r); resignObserver = nil }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.orderOut(nil)
        model.teardown()
        if let dash = window.parent as? DashboardWindow {
            dash.hideSuppressed = false
            dash.removeChildWindow(window)
            if reactivate {
                NSApp.activate(ignoringOtherApps: true)
                dash.makeKeyAndOrderFront(nil)
                if let root = dash.contentView { dash.makeFirstResponder(root) }
            }
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
    // the cache survey is filled in off the main thread (see reload())
    private var cacheSummaryText = "…"
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
        cacheButton.toolTip = "Delete the cached thumbnails and colour strips; they rebuild as you browse"
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
        refreshCacheSummary()
    }

    // The cache size stats every file under two directories, so it is measured
    // OFF the main thread and shown from a cached string. Measuring it inside
    // draw() stalled the tab for as long as the stat of every cached file took.
    private func refreshCacheSummary() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = StorageTabView.computeCacheSummary()
            DispatchQueue.main.async {
                self?.cacheSummaryText = text
                self?.needsDisplay = true
            }
        }
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
        // the Themes tab's section headers, verbatim: label, path and
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
        drawMidLeft(cacheSummaryText, nerdFont("Regular", 11), palette.muted,
                    x: tw2, midTop: bounds.height - mid2, height: bounds.height)

        if !status.isEmpty {
            drawTopLeft(truncate(status, nerdFont("Regular", 11), bounds.width),
                        nerdFont("Regular", 11), palette.muted,
                        x: 0, top: 84, height: bounds.height)
        }
    }

    // Both cache shelves live under ~/.local/state/omacosy: the wallhaven
    // browse cache, the dashboard's decoded previews and its colour strips.
    // Flushing clears the derived files only; the wallpapers, themes and
    // bookmarks stay, and the caches rebuild as the tabs are opened again.
    private static func cacheDirs() -> [String] {
        [whThumbsDir(), HOME + "/.local/state/omacosy/dashboard/thumbs",
         HOME + "/.local/state/omacosy/dashboard/palettes"]
    }

    private static func computeCacheSummary() -> String {
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
        // Deleting every cached file can take a moment, so the work runs off
        // the main thread: the button dims to its busy state and the status
        // line says what is happening until it is done.
        cacheButton.busy = true
        cacheButton.busyTitle = "Flushing…"
        status = "Flushing cache…"
        needsDisplay = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var count = 0
            for d in StorageTabView.cacheDirs() {
                for e in (try? fm.contentsOfDirectory(atPath: d)) ?? [] {
                    if (try? fm.removeItem(atPath: d + "/" + e)) != nil { count += 1 }
                }
            }
            let text = StorageTabView.computeCacheSummary()
            DispatchQueue.main.async {
                guard let self else { return }
                self.cacheButton.busy = false
                self.status = count == 0 ? "Cache already empty" : "Cleared \(count) cached files"
                self.cacheSummaryText = text
                self.needsDisplay = true
            }
        }
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
                    x: 0, top: 11, height: bounds.height)
        drawTopLeft(truncate("Optional: Create an account and go to https://wallhaven.cc/settings/account to get your API Key. Needed for NSFW content.",
                             nerdFont("Regular", 11), bounds.width),
                    nerdFont("Regular", 11), palette.muted, x: 0, top: 33, height: bounds.height)
        let box = NSRect(x: field.frame.minX - 0.5,
                         y: field.frame.minY - (boxH - fieldH) / 2 - 0.5,
                         width: field.frame.width + 1, height: boxH + 1)
        let border = NSBezierPath(roundedRect: box, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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
        // keep the button on screen in its busy state, so the press and the
        // wait are both visible instead of the button vanishing at once
        installButton.busy = true
        installButton.busyTitle = "Updating…"
        installButton.isHidden = false
        stateText = "Updating…"
        detail = "Omacosy will reload in a moment; the window may flicker."
        needsLayout = true
        needsDisplay = true
        DispatchQueue.global().async { [weak self] in
            let (code, out) = shell("\(HOME)/.local/bin/omacosy-update 2>&1")
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.installButton.busy = false
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

final class DashboardWindow: ThemedWindow {
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
    let views: Int
    let favorites: Int
    let source: String
    let colors: [String]
    let createdAt: String
    let fileType: String
    let ratio: String
    let dimensionX: Int
    let dimensionY: Int

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
        self.views = (json["views"] as? NSNumber)?.intValue ?? 0
        self.favorites = (json["favorites"] as? NSNumber)?.intValue ?? 0
        self.source = json["source"] as? String ?? ""
        self.colors = json["colors"] as? [String] ?? []
        self.createdAt = json["created_at"] as? String ?? ""
        self.fileType = json["file_type"] as? String ?? ""
        self.ratio = json["ratio"] as? String ?? ""
        self.dimensionX = (json["dimension_x"] as? NSNumber)?.intValue ?? 0
        self.dimensionY = (json["dimension_y"] as? NSNumber)?.intValue ?? 0
    }

    // The card shows the large thumb; the bookmark stores it so a restart
    // can redraw the grid without a search.
    var thumbURL: String { thumbs["large"] ?? thumbs["original"] ?? thumbs["small"] ?? "" }
    var smallThumbURL: String { thumbs["small"] ?? thumbURL }
}

struct WHUploader {
    let username: String
    let group: String
    let avatarURL: String
}

struct WHTag {
    let id: Int
    let name: String
    let alias: String
    let category: String
}

// A single-wallpaper response: the search fields plus the two things only
// /w/<id> returns (the uploader and the tag list).
struct WHDetails {
    let wallpaper: WHWallpaper
    let uploader: WHUploader?
    let tags: [WHTag]
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

    func debugRemove(_ id: String) { byID[id] = nil }

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

    func info(_ id: String) throws -> WHDetails {
        guard id.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else {
            throw WHError.badURL("bad id")
        }
        var url = baseURL + "/w/" + id
        if !apiKey.isEmpty { url += "?apikey=" + (apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey) }
        let root = try getJSON(url)
        guard let d = root["data"] as? [String: Any], let w = WHWallpaper(json: d) else {
            throw WHError.decode
        }
        let uploader = (d["uploader"] as? [String: Any]).flatMap { u -> WHUploader? in
            guard let name = u["username"] as? String, !name.isEmpty else { return nil }
            let avatar = (u["avatar"] as? [String: Any])?["32px"] as? String ?? ""
            return WHUploader(username: name, group: u["group"] as? String ?? "", avatarURL: avatar)
        }
        let tags = (d["tags"] as? [[String: Any]] ?? []).compactMap { t -> WHTag? in
            guard let name = t["name"] as? String, !name.isEmpty else { return nil }
            return WHTag(id: (t["id"] as? NSNumber)?.intValue ?? 0,
                         name: name,
                         alias: t["alias"] as? String ?? "",
                         category: t["category"] as? String ?? "Other")
        }
        return WHDetails(wallpaper: w, uploader: uploader, tags: tags)
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
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                // map a rate limit the way the API client does, so the bulk
                // retry can honour Retry-After; a one-shot download shows the
                // wait in its failure text
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
                finish(.failure(WHError.rateLimited(retry)))
            } else {
                finish(.failure(WHError.http((response as? HTTPURLResponse)?.statusCode ?? -1)))
            }
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

// --- bulk download retry ---------------------------------------------------

// Wallhaven rate-limits a large batch. A bulk download retries the errors
// that can pass — a 429, a 5xx, a dropped connection — and gives up on the
// rest, so a deleted picture or an oversized file fails once and is reported.
// The wait doubles per attempt (2 s, 4 s, 8 s …) and carries random jitter,
// so a set does not retry in lock step; a server-sent Retry-After is honoured
// instead. Six attempts means the first try plus five retries; wallhaven's
// own docs state no backoff recipe (45 API calls/min, then a 429).
let whBulkMaxAttempts = 6

func whDownloadIsRetryable(_ error: Error) -> Bool {
    guard let e = error as? WHError else { return false }
    switch e {
    case .rateLimited, .network: return true
    case .http(let code): return code == 429 || (500...599).contains(code)
    default: return false
    }
}

// `attempt` is the attempt that just failed, 1-based. Retry-After is never
// shortened and gets a little jitter on top; otherwise the wait is the
// exponential 2·2^(attempt-1) seconds, capped at 30 s and wobbled ±40 %.
func whRetryDelay(attempt: Int, error: Error) -> TimeInterval {
    if case WHError.rateLimited(let after) = error, let a = after, a > 0 {
        return min(max(a, 1), 30) * Double.random(in: 1.0...1.25)
    }
    let base = min(2.0 * pow(2.0, Double(max(attempt, 1) - 1)), 30.0)
    return base * Double.random(in: 0.6...1.4)
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

// A dropdown in the house style, matching the Theme Editor's: a rounded box
// that shows the current choice and opens the same dark MethodPicker card,
// rather than a native (glass) menu.
final class WHDropdown: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var items: [String] = []
    var selectedIndex = 0 { didSet { needsDisplay = true } }
    var accentAtRest = false { didSet { needsDisplay = true } }
    var controlWidth: CGFloat = 198 { didSet { needsDisplay = true } }
    var menuWidth: CGFloat? = nil
    var onPick: ((Int) -> Void)?

    func sizeThatFits() -> NSSize { NSSize(width: controlWidth, height: 28) }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
        if accentAtRest {
            palette.accent.withAlphaComponent(0.9).setFill(); r.fill()
            palette.accent.withAlphaComponent(0.9).setStroke()
        } else {
            palette.itemBG.withAlphaComponent(0.35).setFill(); r.fill()
            palette.muted.withAlphaComponent(0.35).setStroke()
        }
        r.lineWidth = 1; r.stroke()
        let f = nerdFont("Regular", 12)
        drawMidLeft(truncate(title, f, bounds.width - 40), f,
                    accentAtRest ? palette.barBG : palette.label,
                    x: 10, midTop: bounds.height / 2, height: bounds.height)
        drawMidCenter("\u{f078}", nerdFont("Regular", 9),
                      accentAtRest ? palette.barBG : palette.muted,
                      centerX: bounds.width - 15, midTop: bounds.height / 2, height: bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        // a click commits whatever field is being edited first, like every
        // other button in the dashboard
        window?.makeFirstResponder(nil)
        guard !items.isEmpty else { return }
        let rows = items.map { MethodPicker.Row(header: nil, value: $0, label: $0) }
        let current = items.indices.contains(selectedIndex) ? items[selectedIndex] : ""
        MethodPicker.present(from: self, rows: rows, strips: [:],
                             currentMethod: current, title: toolTip ?? "Select",
                             width: menuWidth ?? 340) { [weak self] value in
            guard let self, let i = self.items.firstIndex(of: value),
                  i != self.selectedIndex else { return }
            self.selectedIndex = i
            self.onPick?(i)
        }
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
    var onInfo: ((WHWallpaper) -> Void)?

    private let gap: CGFloat = 12
    private let metaH: CGFloat = 24
    private let topPad: CGFloat = 2
    private let bottomPad: CGFloat = 16
    private let icon: CGFloat = 24
    private let iconPad: CGFloat = 8
    // The hover scrim is the same gradient every time; building one per
    // hovered card per draw was pure allocation.
    private lazy var scrimGradient: NSGradient? = NSGradient(colorsAndLocations:
        (NSColor.black.withAlphaComponent(0.42), 0.0),
        (NSColor.black.withAlphaComponent(0.0), 0.34),
        (NSColor.black.withAlphaComponent(0.0), 0.48),
        (NSColor.black.withAlphaComponent(0.72), 1.0))

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
        let box = NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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
            scrimGradient?.draw(in: t, angle: 270)
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
            let p = NSBezierPath(roundedRect: pill, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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

    private func invalidate(_ i: Int) {
        if let f = cellFrames[i] { setNeedsDisplay(f) }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        var hit: Int?
        for (i, f) in cellFrames where f.contains(p) { hit = i; break }
        guard hit != hovered else { return }
        let old = hovered
        hovered = hit
        if let old { invalidate(old) }
        if let hit { invalidate(hit) }
    }

    override func mouseExited(with event: NSEvent) {
        guard let old = hovered else { return }
        hovered = nil
        invalidate(old)
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

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, f) in cellFrames where f.contains(p) {
            guard i < cards.count else { return }
            let old = hovered
            hovered = i
            if let old, old != i { invalidate(old) }
            invalidate(i)
            onInfo?(cards[i])
            return
        }
    }

    func loadVisible(_ rect: NSRect) {
        for (i, f) in cellFrames where f.intersects(rect) {
            guard i < cards.count else { continue }
            let w = cards[i]
            if thumbs[w.id] != nil || pending.contains(w.id) { continue }
            if let img = whCachedThumb(w.thumbURL) {
                thumbs[w.id] = img
                invalidate(i)
                continue
            }
            pending.insert(w.id)
            whFetchThumb(w.thumbURL) { [weak self] img in
                guard let self else { return }
                self.pending.remove(w.id)
                if let img {
                    self.thumbs[w.id] = img
                    guard i < self.cards.count, self.cards[i].id == w.id else { return }
                    self.invalidate(i)
                }
            }
        }
    }
}

// --- wallpaper metadata card ------------------------------------------------

private func whMetaDate(_ raw: String) -> String {
    // "2018-10-31 01:23:10" -> "31 Oct 2018". Read the date part as written;
    // wallhaven does not document a timezone, so converting could move a day.
    let day = raw.split(separator: " ").first ?? ""
    let parts = day.split(separator: "-")
    guard parts.count == 3, let month = Int(parts[1]), (1...12).contains(month) else { return "" }
    let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "\(Int(parts[2]) ?? 0) \(names[month - 1]) \(parts[0])"
}

private func whGroupedInt(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US")
    return f.string(from: NSNumber(value: n)) ?? String(n)
}

private func whMetaCategory(_ raw: String) -> String {
    switch raw.lowercased() {
    case "general": return "General"
    case "anime": return "Anime"
    case "people": return "People"
    default: return raw.isEmpty ? "" : raw.prefix(1).uppercased() + raw.dropFirst()
    }
}

private func whMetaPurity(_ raw: String) -> String {
    switch raw.lowercased() {
    case "sfw": return "SFW"
    case "sketchy": return "Sketchy"
    case "nsfw": return "NSFW"
    default: return raw
    }
}

private func whInfoMessage(_ error: Error) -> String {
    if let e = error as? WHError {
        switch e {
        case .rateLimited(let after):
            if let a = after {
                return "Wallhaven is limiting requests. Retry in \(max(1, Int(a.rounded()))) s."
            }
            return "Wallhaven is limiting requests. Try again in a minute."
        case .http(401): return "This wallpaper needs an API key."
        case .http(404): return "This wallpaper is no longer available."
        default: break
        }
    }
    return "Couldn't load the extra details."
}

// A pasted wallhaven page URL, with or without its scheme, becomes the one
// wallpaper it names. A plain keyword is left to the normal search.
private func whPastedID(_ raw: String) -> String? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    let lower = s.lowercased()
    if lower.hasPrefix("https://") { s = String(s.dropFirst(8)) }
    else if lower.hasPrefix("http://") { s = String(s.dropFirst(7)) }
    if s.lowercased().hasPrefix("www.") { s = String(s.dropFirst(4)) }
    let head = "wallhaven.cc/w/"
    guard s.lowercased().hasPrefix(head) else { return nil }
    var id = String(s.dropFirst(head.count))
    if let cut = id.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
        id = String(id[..<cut])
    }
    guard !id.isEmpty,
          id.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else { return nil }
    return id
}

// The source can point anywhere, unlike the wallhaven-only fetch guard. Only
// http(s) links are opened, and only because the person clicked the value.
private func whExternalURL(_ raw: String) -> URL? {
    guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = c.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          let host = c.host, !host.isEmpty else { return nil }
    return c.url
}

private enum WHMetaFact {
    case text(String, String)
    case colors(String, [String])
}

private struct WHMetaLayout {
    let facts: [WHMetaFact]
    let valueW: CGFloat
    let uploaderTop: CGFloat
    let tagsTop: CGFloat
    let tagLines: [String]
    let height: CGFloat
}

// The scrolling body of the card: facts, uploader and one comma-separated tag
// line (wrapped). The facts come from the search result and draw at once; only
// the uploader and the tags wait for /w/<id>.
final class WHInfoBodyView: NSView {
    var wallpaper: WHWallpaper
    var uploader: WHUploader?
    var tags: [WHTag] = []
    var loading = true
    var errorText = ""

    private let padX: CGFloat = 20
    private let colGap: CGFloat = 32
    private let rowH: CGFloat = 24
    private let headH: CGFloat = 24
    private let lineH: CGFloat = 18
    private let topPad: CGFloat = 10

    init(wallpaper: WHWallpaper) {
        self.wallpaper = wallpaper
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ d: WHDetails) {
        wallpaper = d.wallpaper
        uploader = d.uploader
        tags = d.tags
        loading = false
        errorText = ""
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func setLoading() {
        loading = true
        errorText = ""
        needsDisplay = true
    }

    func setError(_ text: String) {
        loading = false
        errorText = text
        needsDisplay = true
    }

    private var facts: [WHMetaFact] {
        var rows: [WHMetaFact] = []
        if !wallpaper.resolution.isEmpty {
            rows.append(.text("Resolution",
                              wallpaper.resolution.replacingOccurrences(of: "x", with: " × ")))
        }
        if !wallpaper.ratio.isEmpty {
            rows.append(.text("Aspect Ratio", wallpaper.ratio + " : 1"))
        }
        if wallpaper.fileSize > 0 {
            rows.append(.text("File Size", whFormatSize(wallpaper.fileSize)))
        }
        let type = wallpaper.fileType.replacingOccurrences(of: "image/", with: "").uppercased()
        if !type.isEmpty { rows.append(.text("File Type", type)) }
        let date = whMetaDate(wallpaper.createdAt)
        if !date.isEmpty { rows.append(.text("Uploaded", date)) }
        rows.append(.text("Views", whGroupedInt(wallpaper.views)))
        rows.append(.text("Favorites", whGroupedInt(wallpaper.favorites)))
        if !wallpaper.source.isEmpty { rows.append(.text("Source", wallpaper.source)) }
        if !wallpaper.colors.isEmpty { rows.append(.colors("Colors", wallpaper.colors)) }
        return rows
    }

    private func layout(width: CGFloat) -> WHMetaLayout {
        let facts = self.facts
        let rows = max(1, (facts.count + 1) / 2)
        let factH = topPad + headH + CGFloat(rows) * rowH
        let uploaderTop = factH + 24
        let contentTop = uploaderTop + headH
        let tagsTop = contentTop + 40
        let groupsTop = tagsTop + headH
        let valueW = max(100, (width - padX * 2 - colGap) / 2)

        let joined = tags.map { $0.name }.joined(separator: ", ")
        let tagLines = joined.isEmpty ? [] : wrapText(joined, nerdFont("Regular", 11),
                                                     width - padX * 2, maxLines: 999)
        let tagH = tagLines.isEmpty ? 20 : CGFloat(tagLines.count) * lineH
        return WHMetaLayout(facts: facts, valueW: valueW,
                            uploaderTop: uploaderTop, tagsTop: tagsTop,
                            tagLines: tagLines, height: groupsTop + tagH + 12)
    }

    func measure(width: CGFloat) -> CGFloat {
        guard width > 100 else { return 260 }
        return layout(width: width).height
    }

    override func draw(_ dirtyRect: NSRect) {
        let H = bounds.height
        let L = layout(width: bounds.width)

        // facts, two per row
        drawTopLeft("Details", nerdFont("Bold", 12), palette.accent,
                    x: padX, top: topPad, height: H)
        let lf = nerdFont("Regular", 11)
        let vf = nerdFont("Regular", 11)
        for (i, fact) in L.facts.enumerated() {
            let col = i % 2
            let row = i / 2
            let x = padX + CGFloat(col) * (L.valueW + colGap)
            let mid = topPad + headH + CGFloat(row) * rowH + rowH / 2
            switch fact {
            case .text(let label, let value):
                drawMidLeft(label, lf, palette.muted, x: x, midTop: mid, height: H)
                let room = L.valueW - advance(label, vf) - 12
                let shown = truncate(value, vf, max(20, room))
                let link = label == "Source" && whExternalURL(value) != nil
                let vx = x + L.valueW - advance(shown, vf)
                drawMidLeft(shown, vf, link ? palette.accent : palette.label,
                            x: vx, midTop: mid, height: H)
                if link {
                    palette.accent.withAlphaComponent(0.6).setFill()
                    NSRect(x: vx, y: H - mid - vf.capHeight / 2 - 2,
                           width: advance(shown, vf), height: 1).fill()
                }
            case .colors(let label, let values):
                drawMidLeft(label, lf, palette.muted, x: x, midTop: mid, height: H)
                var sx = x + L.valueW - CGFloat(values.count) * 20 + 6
                for hex in values {
                    let swatch = NSRect(x: sx, y: H - mid - 7, width: 14, height: 14)
                    let path = NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3)
                    (hexColor(hex) ?? palette.itemBG).setFill()
                    path.fill()
                    palette.muted.withAlphaComponent(0.35).setStroke()
                    path.lineWidth = 1
                    path.stroke()
                    sx += 20
                }
            }
        }

        // uploader, text only
        drawTopLeft("Uploader", nerdFont("Bold", 12), palette.accent,
                    x: padX, top: L.uploaderTop, height: H)
        let lineMid = L.uploaderTop + headH + 9
        if loading {
            drawMidLeft("Loading…", nerdFont("Regular", 11), palette.muted,
                        x: padX, midTop: lineMid, height: H)
        } else if !errorText.isEmpty {
            drawMidLeft(truncate(errorText, nerdFont("Regular", 11), bounds.width - padX * 2),
                        nerdFont("Regular", 11), palette.muted,
                        x: padX, midTop: lineMid, height: H)
        } else if let u = uploader {
            let nf = nerdFont("Regular", 12)
            drawMidLeft(u.username, nf, palette.label, x: padX, midTop: lineMid, height: H)
            if !u.group.isEmpty {
                drawMidLeft("· " + u.group, nerdFont("Regular", 10), palette.muted,
                            x: padX + advance(u.username, nf) + 8,
                            midTop: lineMid, height: H)
            }
        } else {
            drawMidLeft("Unknown uploader", nerdFont("Regular", 11), palette.muted,
                        x: padX, midTop: lineMid, height: H)
        }

        // tags, one comma-separated list
        drawTopLeft("Tags", nerdFont("Bold", 12), palette.accent,
                    x: padX, top: L.tagsTop, height: H)
        let groupsTop = L.tagsTop + headH
        if loading {
            drawMidLeft("Loading…", nerdFont("Regular", 11), palette.muted,
                        x: padX, midTop: groupsTop + 9, height: H)
        } else if !errorText.isEmpty {
            drawMidLeft("Tags unavailable.", nerdFont("Regular", 11), palette.muted,
                        x: padX, midTop: groupsTop + 9, height: H)
        } else if L.tagLines.isEmpty {
            drawMidLeft("No tags", nerdFont("Regular", 11), palette.muted,
                        x: padX, midTop: groupsTop + 9, height: H)
        } else {
            let tf = nerdFont("Regular", 11)
            for (i, line) in L.tagLines.enumerated() {
                drawMidLeft(line, tf, palette.label, x: padX,
                            midTop: groupsTop + CGFloat(i) * lineH + lineH / 2, height: H)
            }
        }
    }

    private func sourceRect() -> NSRect? {
        guard let index = facts.firstIndex(where: {
            if case .text(let label, _) = $0 { return label == "Source" }
            return false
        }), case .text(let label, let value) = facts[index] else { return nil }
        let L = layout(width: bounds.width)
        let x = padX + CGFloat(index % 2) * (L.valueW + colGap)
        let mid = topPad + headH + CGFloat(index / 2) * rowH + rowH / 2
        let vf = nerdFont("Regular", 11)
        let room = L.valueW - advance(label, vf) - 12
        let shown = truncate(value, vf, max(20, room))
        let w = advance(shown, vf)
        return NSRect(x: x + L.valueW - w, y: bounds.height - mid - 10,
                      width: w, height: 20)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let r = sourceRect(), r.contains(p), let url = whExternalURL(wallpaper.source) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        if let r = sourceRect(), whExternalURL(wallpaper.source) != nil {
            addCursorRect(r, cursor: .pointingHand)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}

final class WHInfoCardView: NSView {
    private(set) var wallpaper: WHWallpaper
    private let body: WHInfoBodyView
    private let scroll = NSScrollView()
    private let scroller = CustomScroller()
    private let closeButton = ButtonView()
    private let copyButton = ButtonView()
    private let retryButton = ButtonView()
    private var copyToken = 0

    var onClose: (() -> Void)?
    var onRetry: (() -> Void)?

    init(wallpaper: WHWallpaper) {
        self.wallpaper = wallpaper
        self.body = WHInfoBodyView(wallpaper: wallpaper)
        super.init(frame: NSRect(x: 0, y: 0, width: 620, height: 420))
        wantsLayer = true

        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.contentView.drawsBackground = false
        scroll.documentView = body
        addSubview(scroll)
        addSubview(scroller)
        scroller.scrollView = scroll

        closeButton.title = "\u{f00d}"
        closeButton.secondary = true
        closeButton.fontSize = 10
        closeButton.centeredByBounds = true
        closeButton.onClick = { [weak self] in self?.onClose?() }
        addSubview(closeButton)

        copyButton.title = "Copy Link"
        copyButton.secondary = true
        copyButton.fontSize = 11
        copyButton.onClick = { [weak self] in self?.copyLink() }
        addSubview(copyButton)

        retryButton.title = "Retry"
        retryButton.secondary = true
        retryButton.fontSize = 11
        retryButton.isHidden = true
        retryButton.onClick = { [weak self] in self?.onRetry?() }
        addSubview(retryButton)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func idealHeight(width: CGFloat = 620) -> CGFloat {
        let bodyH = body.measure(width: width - 24)
        return min(760, max(300, 48 + 60 + bodyH))
    }

    func showLoading() {
        body.setLoading()
        retryButton.isHidden = true
        needsLayout = true
        needsDisplay = true
    }

    func apply(_ d: WHDetails) {
        wallpaper = d.wallpaper
        body.apply(d)
        retryButton.isHidden = true
        needsLayout = true
        needsDisplay = true
    }

    func showError(_ text: String) {
        body.setError(text)
        retryButton.isHidden = false
        needsLayout = true
        needsDisplay = true
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(wallpaper.pageURL, forType: .string)
        copyToken += 1
        let token = copyToken
        copyButton.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.copyToken == token else { return }
            self.copyButton.title = "Copy Link"
        }
    }

    override func layout() {
        super.layout()
        let headerH: CGFloat = 48
        let footerH: CGFloat = 60
        let buttonY: CGFloat = 17
        let buttonH: CGFloat = 26

        closeButton.frame = NSRect(x: bounds.width - 20 - 22, y: bounds.height - 12 - 22,
                                   width: 22, height: 22)
        let copyW: CGFloat = 96
        copyButton.frame = NSRect(x: (bounds.width - copyW) / 2, y: buttonY,
                                  width: copyW, height: buttonH)
        retryButton.frame = NSRect(x: copyButton.frame.maxX + 8, y: buttonY,
                                   width: 64, height: buttonH)

        let scrollH = max(0, bounds.height - headerH - footerH)
        scroll.frame = NSRect(x: 12, y: footerH, width: bounds.width - 24, height: scrollH)
        let bodyW = scroll.frame.width
        let bodyH = body.measure(width: bodyW)
        body.frame = NSRect(x: 0, y: 0, width: bodyW, height: max(bodyH, scrollH))
        scroll.documentView = body
        scroller.frame = NSRect(x: bounds.width - 16, y: footerH, width: 8, height: scrollH)
        let maxY = max(0, body.frame.height - scrollH)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroller.refresh()
    }

    private func drawBadge(_ text: String, left: CGFloat, top: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return left }
        let f = nerdFont("Bold", 9)
        let w = advance(text, f) + 16
        let r = NSRect(x: left, y: bounds.height - top - 18, width: w, height: 18)
        let path = NSBezierPath(roundedRect: r,
                                xRadius: windowCornerRadius(5),
                                yRadius: windowCornerRadius(5))
        palette.itemBG.withAlphaComponent(0.55).setFill()
        path.fill()
        palette.muted.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawMidCenter(text, f, palette.label, centerX: r.midX,
                      midTop: top + 9, height: bounds.height)
        return r.maxX + 6
    }

    override func draw(_ dirtyRect: NSRect) {
        let corner = min(windowCornerRadius(12), min(bounds.width, bounds.height) / 2)
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: corner, yRadius: corner)
        palette.barBG.setFill()
        card.fill()
        palette.accent.withAlphaComponent(0.55).setStroke()
        card.lineWidth = 1
        card.stroke()

        var left = 20.0
        left = drawBadge(whMetaPurity(wallpaper.purity), left: left, top: 15)
        _ = drawBadge(whMetaCategory(wallpaper.category), left: left, top: 15)

        palette.muted.withAlphaComponent(0.18).setFill()
        NSRect(x: 20, y: bounds.height - 48, width: bounds.width - 40, height: 1).fill()
        NSRect(x: 20, y: 60, width: bounds.width - 40, height: 1).fill()
    }
}

final class WHInfoCard: NSObject {
    private static var current: WHInfoCard?
    private let window: PickerWindow
    private let root: WHInfoCardView
    private let loadDetails: (@escaping (Result<WHDetails, Error>) -> Void) -> Void
    private var monitors: [Any] = []
    private var generation = 0

    static func present(from host: NSView,
                        wallpaper: WHWallpaper,
                        details: WHDetails?,
                        error: Error?,
                        loadDetails: @escaping (@escaping (Result<WHDetails, Error>) -> Void) -> Void) {
        guard let parent = host.window else { return }
        current?.close()
        let c = WHInfoCard(wallpaper: wallpaper, details: details,
                           error: error, loadDetails: loadDetails)
        current = c
        let f = parent.frame
        var origin = NSPoint(x: f.midX - c.window.frame.width / 2,
                             y: f.midY - c.window.frame.height / 2)
        if let scr = NSScreen.main {
            origin.y = max(scr.visibleFrame.minY + 6,
                           min(origin.y, scr.visibleFrame.maxY - c.window.frame.height - 6))
        }
        c.window.setFrameOrigin(origin)
        parent.addChildWindow(c.window, ordered: .above)
        c.show()
    }

    private init(wallpaper: WHWallpaper, details: WHDetails?, error: Error?,
                 loadDetails: @escaping (@escaping (Result<WHDetails, Error>) -> Void) -> Void) {
        root = WHInfoCardView(wallpaper: wallpaper)
        if let details {
            root.apply(details)
        } else if let error {
            root.showError(whInfoMessage(error))
        } else {
            root.showLoading()
        }
        let height = root.idealHeight()
        window = PickerWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        self.loadDetails = loadDetails
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = root
        root.frame = NSRect(x: 0, y: 0, width: 620, height: height)

        root.onClose = { [weak self] in self?.close() }
        root.onRetry = { [weak self] in self?.load() }
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
                guard let self else { return e }
                if e.type == .keyDown {
                    if e.keyCode == 53 { self.close(); return nil }
                    return e
                }
                if !self.window.frame.contains(NSEvent.mouseLocation) { self.close() }
                return e
            }
        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        monitors = [local, global].compactMap { $0 }
    }

    // Only a retry reaches this: the first presentation already has its data
    // and its final size, so it never grows under the pointer.
    private func load() {
        generation += 1
        let gen = generation
        root.showLoading()
        resize()
        loadDetails { [weak self] result in
            guard let self, gen == self.generation else { return }
            switch result {
            case .success(let d):
                self.root.apply(d)
            case .failure(let e):
                self.root.showError(whInfoMessage(e))
            }
            self.resize()
        }
    }

    private func resize() {
        let height = root.idealHeight()
        var f = window.frame
        f.size.height = height
        f.origin.y = f.midY - height / 2
        if let scr = window.screen ?? NSScreen.main {
            f.origin.y = max(scr.visibleFrame.minY + 6,
                             min(f.origin.y, scr.visibleFrame.maxY - height - 6))
        }
        window.setFrame(f, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func close() {
        generation += 1
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        WHInfoCard.current = nil
    }
}

final class WallpapersTabView: NSView, NSTextFieldDelegate, ScrollStepTab {
    private let scroll = NSScrollView()
    private let grid = WHGridView()
    private let scroller = CustomScroller()
    private let scrollerW: CGFloat = 8
    // the same floating jump arrow the Themes gallery uses, for the
    // Bookmarked view (the search results keep their own load-more scrolling)
    private let jumpButton = ScrollJumpButton()
    private var jumpDown = true
    private var lastScrollY: CGFloat?

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
    private var infoCache: [String: WHDetails] = [:]
    private var infoToken = 0
    private var selected: Set<String> = []
    private var downloadedIDs: Set<String> = []
    private var activeDownloads: [String: WHFileDownloader] = [:]
    private var bulkIDs: Set<String> = []
    private var bulkTotal = 0
    private var bulkDoneCount = 0
    private var bulkFailedCount = 0
    private var bulkRetrying = 0

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
        jumpButton.needsDisplay = true
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

    // test door: seed the Bookmarked view with synthetic cards, in memory only
    func debugSeedBookmarks(_ n: Int) {
        for i in 0..<n {
            let w = WHWallpaper(json: [
                "id": "jump\(i)",
                "path": "https://example.invalid/jump\(i).jpg",
                "url": "https://example.invalid/w/jump\(i)",
                "resolution": "1920x1080",
                "purity": "sfw",
                "file_size": NSNumber(value: 1000),
                "thumbs": ["small": ""],
            ])!
            bookmarks.debugInsert(w)
        }
        config.bookmarkedOnly = true
        // the tab is attached after seeding, and its first show would
        // otherwise run a real search before the shelf is visible
        didInitialSearch = true
        rebuildGrid()
    }

    func debugLeaveBookmarks() {
        config.bookmarkedOnly = false
        results = []
        rebuildGrid()
    }

    func debugUnbookmark(at index: Int) {
        guard config.bookmarkedOnly, index >= 0, index < grid.cards.count else { return }
        let w = grid.cards[index]
        bookmarks.debugRemove(w.id)
        grid.bookmarkedIDs = Set(bookmarks.all().map { $0.id })
        refreshBookmarksGrid()
    }

    func debugJumpTopY() -> CGFloat { max(0, grid.frame.height - scroll.contentSize.height) }
    func debugJumpOriginY() -> CGFloat { scroll.contentView.bounds.origin.y }
    func debugJumpHidden() -> Bool { jumpButton.isHidden }
    func debugJumpUp() -> Bool { jumpButton.up }
    func debugJumpClick() { jumpButton.onClick?() }
    func debugJumpScroll(by dy: CGFloat) { scrollBy(scroll, dy); visibleChanged() }
    func debugJumpToBottom() {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroller.refresh()
        updateJumpButton()
    }

    // test door: seed the grid without a search or a network call
    func debugSeedCards(_ ws: [WHWallpaper]) {
        config.bookmarkedOnly = false
        results = ws
        rebuildGrid()
    }

    // test door: run a batch through the real landing bookkeeping with no
    // network — `failures` names indexes that end failed, the rest succeed
    // with an empty path, which the download manifest writer skips
    func debugBulkSimulate(_ count: Int, failures: Set<Int>) {
        guard count > 0, grid.cards.count >= count else { return }
        let picks = Array(grid.cards.prefix(count))
        selected = Set(picks.map { $0.id })
        grid.selected = selected
        bulkIDs = Set(picks.map { $0.id })
        bulkTotal = count
        bulkDoneCount = 0
        bulkFailedCount = 0
        bulkRetrying = 0
        for (i, w) in picks.enumerated() {
            finishDownload(w, res: failures.contains(i) ? .failure(WHError.network("selftest"))
                                                         : .success(""),
                           isBulk: true)
        }
    }

    // test door: what the batch left behind
    func debugBulkStatus() -> String {
        "selected=[\(selected.sorted().joined(separator: ","))] failed=\(bulkFailedCount) " +
        "done=\(bulkDoneCount) total=\(bulkTotal) gridSelected=\(grid.selected.count)"
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
        addSubview(jumpButton)
        jumpButton.isHidden = true
        jumpButton.onClick = { [weak self] in self?.jumpToEnd() }
        jumpButton.onScrollWheel = { [weak self] e in self?.scroll.scrollWheel(with: e) }
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
        grid.onInfo = { [weak self] w in self?.showInfo(w) }

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

    // Clear the field's selection and give the first responder back to the
    // dashboard, so the typed keyword is not left highlighted.
    private func endSearchEditing() {
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        }
        window?.makeFirstResponder(window?.contentView)
    }

    private func beginSearch(reset: Bool) {
        if reset, let id = whPastedID(field.stringValue) {
            searchByID(id)
            return
        }
        guard !config.bookmarkedOnly else { return }
        // Drop the field's selection highlight and hand focus back to the
        // gallery: a keyword left selected reads as unreadable.
        if reset { DispatchQueue.main.async { [weak self] in self?.endSearchEditing() } }
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

    // A pasted wallhaven.cc/w/<id> is a direct lookup, not a text search.
    // The response also fills the metadata cache, so right-clicking the one
    // result shows its uploader and tags without another request.
    private func searchByID(_ id: String) {
        searchToken += 1
        let token = searchToken
        DispatchQueue.main.async { [weak self] in self?.endSearchEditing() }
        refreshKeyState()
        client.apiKey = readSecret("wallhaven")
        config.bookmarkedOnly = false
        config.save()
        results = []
        selected.removeAll()
        nextRawPage = 1
        totalResults = 0
        hasMore = false
        isLoadingMore = false
        isSearching = true
        searchError = ""
        grid.thumbs.removeAll()
        rebuildGrid()
        needsDisplay = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let d = try self.client.info(id)
                DispatchQueue.main.async {
                    guard token == self.searchToken else { return }
                    self.infoCache[id] = d
                    self.results = [d.wallpaper]
                    self.totalResults = 1
                    self.hasMore = false
                    self.isSearching = false
                    if self.hideNSFW && d.wallpaper.purity.lowercased() == "nsfw" {
                        self.searchError = "This wallpaper is hidden by Hide NSFW."
                    }
                    self.rebuildGrid()
                    self.scrollToTop()
                }
            } catch {
                DispatchQueue.main.async {
                    guard token == self.searchToken else { return }
                    self.isSearching = false
                    self.searchError = error.localizedDescription
                    self.rebuildGrid()
                    self.needsDisplay = true
                }
            }
        }
    }

    private func loadMore() {
        guard !config.bookmarkedOnly, !isSearching, !isLoadingMore, hasMore else { return }
        beginSearch(reset: false)
    }

    private func rebuildGrid(resetScroll: Bool = true) {
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
        if config.bookmarkedOnly && resetScroll { pendingTopScroll = true }
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
        updateJumpButton()
        grid.needsDisplay = true
    }

    // --- actions ---

    @discardableResult
    private func toggleBookmark(_ w: WHWallpaper) -> Bool {
        let on = bookmarks.toggle(w)
        grid.bookmarkedIDs = Set(bookmarks.all().map { $0.id })
        if config.bookmarkedOnly { refreshBookmarksGrid() } else { grid.needsDisplay = true }
        return on
    }

    private func refreshBookmarksGrid() {
        let oldH = grid.frame.height
        let origin = scroll.contentView.bounds.origin
        pendingTopScroll = false
        rebuildGrid(resetScroll: false)
        let delta = grid.frame.height - oldH
        let maxY = max(0, grid.frame.height - scroll.contentSize.height)
        let y = min(maxY, max(0, origin.y + delta))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroller.refresh()
        updateJumpButton()
        grid.loadVisible(scroll.documentVisibleRect)
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
        startDownloadAttempt(w, attempt: 1)
    }

    // Right-click opens the metadata card. The search result already carries
    // the preview and the facts; /w/<id> adds the uploader and tags, and is
    // cached for the tab session so a second right-click is free.
    private func showInfo(_ w: WHWallpaper) {
        grid.hovered = nil
        grid.needsDisplay = true
        client.apiKey = readSecret("wallhaven")
        infoToken += 1
        let token = infoToken
        let present: (WHDetails?, Error?) -> Void = { [weak self] details, error in
            guard let self, token == self.infoToken else { return }
            WHInfoCard.present(
                from: self, wallpaper: w, details: details, error: error,
                loadDetails: { [weak self] completion in
                    self?.loadInfo(w, completion: completion)
                })
        }
        if let cached = infoCache[w.id] {
            present(cached, nil)
            return
        }
        // Fetch first, then open at the final size. The card used to open
        // from the loading state and grow when the tags arrived, which read
        // as a two-step open under the pointer.
        loadInfo(w) { result in
            switch result {
            case .success(let d): present(d, nil)
            case .failure(let e): present(nil, e)
            }
        }
    }

    private func loadInfo(_ w: WHWallpaper,
                          completion: @escaping (Result<WHDetails, Error>) -> Void) {
        if let d = infoCache[w.id] { completion(.success(d)); return }
        let id = w.id
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let d = try self.client.info(id)
                DispatchQueue.main.async {
                    self.infoCache[id] = d
                    completion(.success(d))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func startDownloadAttempt(_ w: WHWallpaper, attempt: Int) {
        let dir = wallpapersDir()
        grid.downloading[w.id] = 0
        grid.needsDisplay = true
        let d = whStartDownload(client: client, wallpaper: w, into: dir,
                                onProgress: { [weak self] frac in
            self?.grid.downloading[w.id] = frac
            self?.grid.needsDisplay = true
        }, completion: { [weak self] res in
            guard let self else { return }
            let isBulk = self.bulkTotal > 0 && self.bulkIDs.contains(w.id)
            if isBulk, case .failure(let e) = res,
               attempt < whBulkMaxAttempts, whDownloadIsRetryable(e) {
                self.scheduleBulkRetry(w, attempt: attempt, error: e)
                return
            }
            self.finishDownload(w, res: res, isBulk: isBulk)
        })
        activeDownloads[w.id] = d
    }

    // A retry keeps the card in flight: its activeDownloads entry stays (so a
    // stray click cannot start a second copy), the progress bar resets, and
    // the wait comes from the shared jittered-backoff policy.
    private func scheduleBulkRetry(_ w: WHWallpaper, attempt: Int, error: Error) {
        grid.downloading[w.id] = 0
        grid.needsDisplay = true
        bulkRetrying += 1
        updateBulkBadge()
        let delay = whRetryDelay(attempt: attempt, error: error)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.bulkTotal > 0, self.bulkIDs.contains(w.id) else { return }
            self.bulkRetrying = max(0, self.bulkRetrying - 1)
            self.startDownloadAttempt(w, attempt: attempt + 1)
            self.updateBulkBadge()
        }
    }

    // The landing bookkeeping, shared by the first attempt and every retry: a
    // success is recorded and clears the card's checkbox at once; a bulk item
    // that is out of retries stays checked, so the next Download press retries
    // exactly the failures.
    private func finishDownload(_ w: WHWallpaper, res: Result<String, Error>, isBulk: Bool) {
        activeDownloads[w.id] = nil
        grid.downloading[w.id] = nil
        let ok: Bool
        if case .success(let path) = res {
            ok = true
            downloadedIDs.insert(w.id)
            grid.downloaded = downloadedIDs
            whRecordDownload((path as NSString).lastPathComponent, id: w.id, purity: w.purity)
            if isBulk {
                selected.remove(w.id)
                grid.selected = selected
            }
        } else {
            ok = false
        }
        grid.needsDisplay = true

        if isBulk {
            bulkIDs.remove(w.id)
            bulkDoneCount += 1
            if !ok { bulkFailedCount += 1 }
            if bulkIDs.isEmpty {
                finishBulk()
            } else {
                updateBulkBadge()
            }
        } else if ok {
            showBadge(.success, label: "Added")
        } else if case .failure(let e) = res {
            showBadge(.failure, label: "Failed — \(e.localizedDescription)")
        }
    }

    // dynamic: a progress ring with the running added count, plus a note while
    // an item waits out its retry delay
    private func updateBulkBadge() {
        let frac = Double(bulkDoneCount) / Double(max(bulkTotal, 1))
        let label = bulkRetrying > 0 ? "\(bulkDoneCount)/\(bulkTotal) · Retrying"
                                     : "\(bulkDoneCount)/\(bulkTotal)"
        showBadge(.progress(frac), label: label, sticky: true)
    }

    // Bulk download: the button slot shows a progress ring and count, then a
    // green check (or a red mark with the failures). A file that lands clears
    // its checkbox as it arrives; a file still failed at the end keeps it, so
    // the button comes back offering exactly those and one more press retries
    // only them.
    private func downloadSelected() {
        let items = grid.cards.filter {
            selected.contains($0.id) && !downloadedIDs.contains($0.id) && activeDownloads[$0.id] == nil
        }
        bulkIDs = Set(items.map { $0.id })
        bulkTotal = items.count
        bulkDoneCount = 0
        bulkFailedCount = 0
        bulkRetrying = 0
        if bulkIDs.isEmpty { clearSelection(); return }
        showBadge(.progress(0), label: "0/\(bulkTotal)", sticky: true)
        for w in items { download(w) }
    }

    private func finishBulk() {
        let failed = bulkFailedCount
        let added = bulkDoneCount - failed
        bulkTotal = 0
        bulkRetrying = 0
        // successes unchecked as they landed; the failures stay checked
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
        let y = scroll.contentView.bounds.origin.y
        // A non-flipped document stores later content at a smaller y origin,
        // so moving down the shelf decreases it.
        if let last = lastScrollY, abs(y - last) > 0.5 { jumpDown = y < last }
        lastScrollY = y
        updateJumpButton()
        grid.loadVisible(vis)
        scroller.refresh()
        // the document is non-flipped, so later results sit at lower y:
        // reaching the end means the viewport's bottom edge nears origin 0
        if vis.minY < 600 { loadMore() }
    }

    // The Bookmarked view is the one shelf here that reaches its end without
    // loading more; the search results keep their load-more scrolling.
    private func updateJumpButton() {
        let maxScroll = max(0, grid.frame.height - scroll.contentSize.height)
        let y = scroll.contentView.bounds.origin.y
        guard config.bookmarkedOnly, maxScroll > 0.5 else {
            jumpButton.isHidden = true
            return
        }
        // at either end, point the only useful way out
        if y <= 0.5 { jumpDown = false }
        else if y >= maxScroll - 0.5 { jumpDown = true }
        jumpButton.up = !jumpDown
        jumpButton.isHidden = false
        jumpButton.needsDisplay = true
    }

    // "Straight to" the end, as in the Themes gallery: one instant jump.
    private func jumpToEnd() {
        let maxScroll = max(0, grid.frame.height - scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: jumpDown ? 0 : maxScroll))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroller.refresh()
        updateJumpButton()
    }

    private func scrollToTop() {
        let maxY = max(0, grid.frame.height - scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroller.refresh()
        jumpDown = true
        lastScrollY = maxY
        updateJumpButton()
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
        let path = NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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
        let jumpSize: CGFloat = 30
        jumpButton.frame = NSRect(x: scroll.frame.maxX - jumpSize - 12, y: 16 + 12,
                                  width: jumpSize, height: jumpSize)
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
        updateJumpButton()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // search box
        let W = bounds.width
        let g: CGFloat = 8
        let sortW: CGFloat = 118, orderW: CGFloat = 34, searchW: CGFloat = 76
        let queryW = max(160, W - sortW - orderW - searchW - g * 3)
        let box = frameFor(top: row1Top, x: 0, w: queryW, h: row1H)
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: windowCornerRadius(6), yRadius: windowCornerRadius(6))
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
                let sq = NSBezierPath(roundedRect: r, xRadius: windowCornerRadius(4), yRadius: windowCornerRadius(4))
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

// --- the logo intro ---------------------------------------------------------
//
// The wordmark comes alive when the modal opens: one of seventeen small
// effects plays over the lit cells of the logo, picked at random each open
// and never repeating the last (LOGO_INTRO in settings.conf pins one;
// OMACOSY_LOGO_INTRO overrides for a single launch). The vocabulary is a
// native take on ttfx (terminal text effects, MIT, github.com/omacom/ttfx —
// by the Omarchy authors, itself a port of terminaltexteffects by
// ChrisBuilds): laseretch's beam and sparks, sweep's travelling band, waves'
// rippling laser bars, beams' converging lights, middleout's single centre
// line splitting open vertically, scattered's pops, print's typewriter,
// decrypt's ciphertext resolving cell by cell, errorcorrect's signal lock,
// rain's falling drops, crumble's debris, expand's blossom, spray's nozzle,
// slice's halves, wipe's clean front, highlight's flash and colorshift's
// shimmer. Every effect flares each cell
// hot on arrival and cools it to its accent shade, and ends on the same crisp
// wordmark. The grid is sampled from the tinted wordmark at open time, so any
// future logo animates with no new asset and no build step.

struct LogoCell {
    let col: Int
    let row: Int
    let coverage: CGFloat
    let color: NSColor
    // The same colour with the coverage baked in. The intro draws this for
    // most cells, so it is built once with the grid instead of once per frame.
    let fill: NSColor

    init(col: Int, row: Int, coverage: CGFloat, color: NSColor) {
        self.col = col
        self.row = row
        self.coverage = coverage
        self.color = color
        self.fill = color.withAlphaComponent(coverage)
    }
}

struct LogoGrid {
    let cols: Int
    let rows: Int
    let cells: [LogoCell]

    // One sample per cell, drawn from the same tinted image the header shows.
    // Coverage, not a cutoff: a cell that is half glyph draws at half alpha,
    // so the grooves between the strips stay readable instead of filling in.
    static func build(from image: NSImage, rows: Int) -> LogoGrid? {
        guard rows > 0 else { return nil }
        let aspect = image.size.width / max(image.size.height, 1)
        let cols = max(1, Int((CGFloat(rows) * aspect).rounded()))
        let count = cols * rows * 4
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        buf.initialize(repeating: 0, count: count)
        defer { buf.deallocate() }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: buf, width: cols, height: rows, bitsPerComponent: 8,
                                  bytesPerRow: cols * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: cols, height: rows))
        NSGraphicsContext.restoreGraphicsState()
        var cells: [LogoCell] = []
        for y in 0..<rows {
            for x in 0..<cols {
                let i = (y * cols + x) * 4
                let a = CGFloat(buf[i + 3]) / 255
                if a < 0.28 { continue }
                // the buffer is premultiplied; divide the coverage back out to
                // recover the strip's shade
                let r = min(255, CGFloat(buf[i]) / a) / 255
                let g = min(255, CGFloat(buf[i + 1]) / a) / 255
                let b = min(255, CGFloat(buf[i + 2]) / a) / 255
                // bitmap memory starts at the image's top row while the view
                // draws row 0 at its bottom edge, so store rows bottom-up —
                // without this every effect plays an upside-down wordmark
                cells.append(LogoCell(col: x, row: rows - 1 - y, coverage: a,
                                      color: NSColor(srgbRed: r, green: g, blue: b, alpha: 1)))
            }
        }
        return LogoGrid(cols: cols, rows: rows, cells: cells)
    }
}

// A small fixed-seed RNG: the walk is the effect, and a run worth debugging
// should be reproducible from its seed.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum LogoIntroKind: String, CaseIterable {
    case laseretch, sweep, middleout, scattered, print, decrypt, rain, waves, highlight, colorshift, errorcorrect, crumble, expand, beams, slice, wipe, spray

    // per-kind pacing: seconds for the whole reveal, the flare's cool-down,
    // and the window a cell spends animating in before its reveal moment
    var target: TimeInterval {
        switch self {
        case .highlight, .colorshift, .slice: return 0.15
        case .middleout: return 0.10
        case .expand: return 0.3
        case .waves: return 0.4
        case .print, .errorcorrect, .spray, .wipe: return 0.7
        case .scattered: return 0.8
        case .sweep: return 0.9
        case .decrypt: return 1.0
        case .beams: return 0.95
        default: return 1.0
        }
    }
    var settle: TimeInterval {
        switch self {
        case .colorshift: return 0.95
        case .errorcorrect: return 0.65
        case .highlight: return 0.45
        case .laseretch: return 0.26
        case .beams: return 0.22
        case .decrypt: return 0.22
        case .middleout: return 0.20
        case .sweep, .slice: return 0.18
        case .print, .wipe: return 0.12
        default: return 0.15
        }
    }
    var lead: TimeInterval {
        switch self {
        case .expand: return 0.32
        case .rain: return 0.35
        case .crumble, .slice, .spray: return 0.40
        case .middleout: return 0.72
        case .waves: return 0.80
        default: return 0
        }
    }
}

final class LogoIntroEffect {
    // One tuning knob for the whole rotation. The per-kind targets below were
    // written to read well at 1.0; 0.75 turns the longest 1.55 s run into
    // ~1.16 s and the average into ~0.8 s, without changing any effect's
    // shape. Raise it toward 1.0 for the older, slower pace.
    static let pace: TimeInterval = 0.75

    let kind: LogoIntroKind
    let cells: [LogoCell]
    let order: [Int]     // the reveal order, indices into cells
    let orderAt: [Int]   // cell index -> its position in the order
    let lead: TimeInterval
    let settle: TimeInterval
    let step: TimeInterval
    var duration: TimeInterval { lead + Double(order.count) * step + settle }

    func revealTime(_ pos: Int) -> TimeInterval { lead + Double(pos) * step }

    init(grid: LogoGrid, kind: LogoIntroKind, seed: UInt64) {
        self.kind = kind
        cells = grid.cells
        self.lead = kind.lead * LogoIntroEffect.pace
        self.settle = kind.settle * LogoIntroEffect.pace
        var rng = SplitMix64(seed: seed)
        let list = grid.cells
        let count = list.count
        var order: [Int]
        switch kind {
        case .laseretch:
            // ttfx etches in a randomised depth-first walk (its recursive
            // backtracker): the beam wanders like a hand, and a disconnected
            // part (each glyph) restarts from a random lit cell.
            var slot = [Int](repeating: -1, count: grid.cols * grid.rows)
            for (i, c) in list.enumerated() { slot[c.row * grid.cols + c.col] = i }
            var visited = [Bool](repeating: false, count: count)
            order = []
            var stack: [Int] = []
            let shuffled = Array(0..<count).shuffled(using: &rng)
            var cursor = 0
            while order.count < count {
                if stack.isEmpty {
                    while cursor < shuffled.count, visited[shuffled[cursor]] { cursor += 1 }
                    guard cursor < shuffled.count else { break }
                    stack.append(shuffled[cursor])
                    cursor += 1
                }
                let ci = stack.removeLast()
                if visited[ci] { continue }
                visited[ci] = true
                order.append(ci)
                let c = list[ci]
                var next: [Int] = []
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let x = c.col + dx, y = c.row + dy
                    guard x >= 0, x < grid.cols, y >= 0, y < grid.rows else { continue }
                    let ni = slot[y * grid.cols + x]
                    if ni >= 0, !visited[ni] { next.append(ni) }
                }
                next.shuffle(using: &rng)
                stack.append(contentsOf: next)
            }
        case .sweep:
            // a crisp diagonal band crossing the wordmark
            order = (0..<count).sorted {
                Double(list[$0].col) + 0.35 * Double(list[$0].row) <
                Double(list[$1].col) + 0.35 * Double(list[$1].row)
            }
        case .beams:
            // two beams sweep in from opposite ends of the diagonal and meet
            // in the middle; a cell appears when the first beam reaches it
            let span = max(1, Double(grid.cols - 1) + 0.6 * Double(grid.rows - 1))
            let key = { (c: LogoCell) -> Double in
                min((Double(c.col) + 0.6 * Double(c.row)) / span, 1 - (Double(c.col) + 0.6 * Double(c.row)) / span)
            }
            order = (0..<count).sorted { key(list[$0]) < key(list[$1]) }
        case .wipe, .waves:
            // a clean left-to-right front; waves also rides it as ripples
            order = (0..<count).sorted { list[$0].col < list[$1].col }
        case .middleout:
            // every cell lands together; the motion lives in the lead, which
            // first gathers them into one centre line, then splits it open
            order = Array(0..<count).shuffled(using: &rng)
        case .print, .errorcorrect:
            // top-left to bottom-right, the way one reads; errorcorrect's
            // identity is the wrong shade each cell arrives wearing
            order = (0..<count).sorted {
                list[$0].row != list[$1].row ? list[$0].row > list[$1].row : list[$0].col < list[$1].col
            }
        case .scattered, .rain, .crumble, .expand, .highlight, .colorshift, .slice, .spray, .decrypt:
            // no spatial order at all: they arrive from everywhere, or the
            // whole wordmark arrives together
            order = Array(0..<count).shuffled(using: &rng)
        }
        self.order = order
        var at = [Int](repeating: 0, count: count)
        for (p, ci) in order.enumerated() { at[ci] = p }
        self.orderAt = at
        // about the target duration whatever the logo, within sane bounds
        self.step = min(0.0045, max(0.0002,
            kind.target * LogoIntroEffect.pace / Double(max(1, count))))
    }
}

// The intro's colours are sRGB by construction. `mixColor` resolves both
// operands through ColorSync on every call, which showed up as the largest
// cost in a 1 ms sample of the animation. Component math is the same blend
// without the conversion, and `logoAlpha` avoids the same round trip when a
// cell's coverage is applied.
@inline(__always)
func logoMix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            alpha: 1)
}

@inline(__always)
func logoAlpha(_ c: NSColor, _ a: CGFloat) -> NSColor {
    NSColor(srgbRed: c.redComponent, green: c.greenComponent,
            blue: c.blueComponent, alpha: a)
}

final class LogoIntroView: NSView {
    private struct Spark {
        var x, y, vx, vy, life, maxLife: Double
        let color: NSColor
    }
    private let logoWhite = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private let logoBlack = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    private var grid: LogoGrid?
    private var effect: LogoIntroEffect?
    private var tickCount: UInt64 = 0
    private var start: TimeInterval = 0
    private var timer: Timer?
    private var sparks: [Spark] = []
    private var lastTick: TimeInterval = 0
    private var lastRevealed = 0
    private var finished = true
    private var cellRects: [NSRect] = []
    private var cellRectsSize = NSSize.zero
    // OMACOSY_LOGO_TRACE=1 prints one summary line per run to stderr: timer
    // ticks, real draw calls and their average cost. Useful when judging a
    // pacing or renderer change without guessing from a screen recording.
    private let tracing = ProcessInfo.processInfo.environment["OMACOSY_LOGO_TRACE"] != nil
    private var traceTicks = 0
    private var traceDraws = 0
    private var traceDrawTime = 0.0
    var onFinished: (() -> Void)?

    // the wordmark is not a control: clicks fall through to the card below
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func start(grid: LogoGrid, kind: LogoIntroKind) {
        stopTimer()
        layer?.removeAllAnimations()
        self.grid = grid
        effect = LogoIntroEffect(grid: grid, kind: kind, seed: UInt64.random(in: .min ... .max))
        buildCellRects()
        sparks.removeAll()
        lastRevealed = 0
        tickCount = 0
        traceTicks = 0
        traceDraws = 0
        traceDrawTime = 0
        finished = false
        isHidden = false
        alphaValue = 1
        // a short lead-in so the first frames are not lost while the window
        // settles on screen
        start = ProcessInfo.processInfo.systemUptime + 0.03
        lastTick = start
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        needsDisplay = true
    }

    // The geometry is fixed for the run: build it once instead of rebuilding
    // a rect and two divisions for every cell, every frame.
    private func buildCellRects() {
        guard let grid, grid.cols > 0, grid.rows > 0 else {
            cellRects.removeAll(); cellRectsSize = .zero; return
        }
        let cellW = bounds.width / CGFloat(grid.cols)
        let cellH = bounds.height / CGFloat(grid.rows)
        cellRects = grid.cells.map { cell in
            NSRect(x: bounds.minX + CGFloat(cell.col) * cellW,
                   y: bounds.minY + CGFloat(cell.row) * cellH,
                   width: cellW, height: cellH)
        }
        cellRectsSize = bounds.size
    }

    func cancel() {
        stopTimer()
        // drop any in-flight fade so a stale animation cannot pull the alpha
        // down under a new run
        layer?.removeAllAnimations()
        finished = true
        isHidden = true
        alphaValue = 1
        effect = nil
        grid = nil
        cellRects.removeAll()
        cellRectsSize = .zero
        sparks.removeAll()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !finished, let effect else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - start
        tickCount &+= 1
        if tracing { traceTicks += 1 }
        let revealed = min(effect.cells.count, Int(max(0, elapsed) / effect.step))
        if effect.kind == .laseretch, revealed > lastRevealed {
            for k in lastRevealed..<revealed { emitSparks(effect.order[k]) }
        }
        lastRevealed = revealed
        updateSparks(dt: min(0.05, now - lastTick))
        lastTick = now
        if elapsed >= effect.duration {
            stopTimer()
            finished = true
            if tracing {
                let avg = traceDraws > 0 ? traceDrawTime / Double(traceDraws) * 1000 : 0
                let line = "logo trace \(effect.kind.rawValue): ticks=\(traceTicks) "
                    + "draws=\(traceDraws) avgDraw="
                    + String(format: "%.2f", avg) + "ms duration="
                    + String(format: "%.2f", effect.duration) + "s\n"
                FileHandle.standardError.write(Data(line.utf8))
            }
            onFinished?()
        }
        needsDisplay = true
    }

    private func emitSparks(_ index: Int) {
        guard let grid else { return }
        let cell = grid.cells[index]
        let cellW = bounds.width / CGFloat(grid.cols)
        let cellH = bounds.height / CGFloat(grid.rows)
        let cx = bounds.minX + (CGFloat(cell.col) + 0.5) * cellW
        let cy = bounds.minY + (CGFloat(cell.row) + 0.5) * cellH
        let count = Double.random(in: 0...1) < 0.25 ? 2 : 1
        for _ in 0..<count {
            let life = Double.random(in: 0.35...0.55)
            sparks.append(Spark(x: Double(cx), y: Double(cy),
                                vx: Double.random(in: -55...55),
                                vy: -Double.random(in: 30...110),
                                life: life, maxLife: life, color: cell.color))
        }
        if sparks.count > 360 { sparks.removeFirst(sparks.count - 360) }
    }

    private func updateSparks(dt: TimeInterval) {
        for i in sparks.indices {
            sparks[i].vy -= 320 * dt
            sparks[i].x += sparks[i].vx * dt
            sparks[i].y += sparks[i].vy * dt
            sparks[i].life -= dt
        }
        sparks.removeAll { $0.life <= 0 }
    }

    // cheap per-cell, per-frame noise for the decrypt scramble
    private func flickerNoise(_ cell: LogoCell, _ tick: UInt64) -> UInt64 {
        let seed = UInt64(bitPattern: Int64((cell.col &* 73856093) ^ (cell.row &* 19349663)))
            ^ (tick &* 0x9E3779B97F4A7C15)
        var h = SplitMix64(seed: seed)
        return h.next()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let grid, let effect, !isHidden else { return }
        let traceStart = tracing ? ProcessInfo.processInfo.systemUptime : 0
        defer {
            if tracing {
                traceDraws += 1
                traceDrawTime += ProcessInfo.processInfo.systemUptime - traceStart
            }
        }
        if cellRects.count != grid.cells.count || cellRectsSize != bounds.size {
            buildCellRects()
        }
        guard cellRects.count == grid.cells.count else { return }
        NSGraphicsContext.current?.cgContext.clip(to: bounds)
        let elapsed = finished ? effect.duration : ProcessInfo.processInfo.systemUptime - start
        let cellW = bounds.width / CGFloat(grid.cols)
        let cellH = bounds.height / CGFloat(grid.rows)
        let hot = logoMix(palette.accent, logoWhite, 0.85)
        let waveEdge = logoMix(palette.accent, logoWhite, 0.95)
        let revealed = min(effect.cells.count, Int(max(0, elapsed) / effect.step))
        for (ci, cell) in grid.cells.enumerated() {
            let box = cellRects[ci]
            let rt = effect.revealTime(effect.orderAt[ci])
            if elapsed < rt {
                if effect.kind == .decrypt || elapsed >= rt - effect.lead {
                    switch effect.kind {
                    case .rain:
                        // the drop falls from above, accelerating into place
                        let p = min(1, max(0, (elapsed - (rt - effect.lead)) / effect.lead))
                        let drop = Double(5 + (cell.col * 7 + cell.row * 13) % 4)
                        let lift = CGFloat(drop * (1 - p) * (1 - p)) * cellH
                        cell.fill.setFill()
                        box.offsetBy(dx: 0, dy: lift).fill()
                    case .crumble:
                        // debris converges from a random direction and fades
                        // into solid as it lands
                        let p = min(1, max(0, (elapsed - (rt - effect.lead)) / effect.lead))
                        let n = flickerNoise(cell, 7)
                        let dist = Double(4 + n % 7)
                        let angle = Double((n >> 8) % 628) / 100
                        let rem = CGFloat(dist * (1 - p) * (1 - p))
                        logoAlpha(cell.color, cell.coverage * CGFloat(0.35 + 0.65 * p)).setFill()
                        box.offsetBy(dx: rem * CGFloat(cos(angle)) * cellW,
                                     dy: rem * CGFloat(sin(angle)) * cellH).fill()
                    case .expand:
                        // the wordmark blossoms out of its centre
                        let p = min(1, max(0, (elapsed - (rt - effect.lead)) / effect.lead))
                        let ease = 1 - (1 - p) * (1 - p)
                        let cx = bounds.minX + bounds.width / 2
                        let cy = bounds.minY + bounds.height / 2
                        let r = box
                        let dx = (cx - r.midX) * CGFloat(1 - ease)
                        let dy = (cy - r.midY) * CGFloat(1 - ease)
                        logoAlpha(cell.color, cell.coverage * CGFloat(0.3 + 0.7 * ease)).setFill()
                        r.offsetBy(dx: dx, dy: dy).fill()
                    case .middleout:
                        // phase one: every cell leaves the centre point and
                        // gathers into a single white line on the middle row;
                        // phase two: the line splits open vertically into the
                        // wordmark while the colours settle
                        let local = min(1, max(0, (elapsed - (rt - effect.lead)) / effect.lead))
                        let r = box
                        let centre = NSPoint(x: bounds.midX, y: bounds.midY)
                        let midRow = NSPoint(x: r.midX, y: bounds.midY)
                        let split = CGFloat(0.42)   // share of the lead spent forming the line
                        var at = centre
                        var white: CGFloat = 0.55
                        if local > split {
                            let q = CGFloat(min(1, (local - split) / (1 - split)))
                            let ease = 0.5 - 0.5 * cos(q * .pi)
                            at = NSPoint(x: midRow.x, y: midRow.y + (r.midY - midRow.y) * ease)
                            white = 0.55 * (1 - ease)
                        } else {
                            let q = CGFloat(local / split)
                            let ease = 0.5 - 0.5 * cos(q * .pi)
                            at = NSPoint(x: centre.x + (midRow.x - centre.x) * ease, y: centre.y)
                        }
                        logoAlpha(logoMix(cell.color, logoWhite, white), cell.coverage).setFill()
                        NSRect(x: at.x - r.width / 2, y: at.y - r.height / 2,
                               width: r.width, height: r.height).fill()
                    case .waves:
                        // ttfx's wave: each cell rides ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁ seven
                        // times as the column front pushes in from the left.
                        // The bars are drawn as laser lines: a bright beam,
                        // a white-hot cutting edge, and a soft glow.
                        let local = min(1, max(0, (elapsed - (rt - effect.lead)) / effect.lead))
                        let rise = min(Int(local * 105) % 15, 14 - Int(local * 105) % 15)
                        let r = box
                        let h = CGFloat(rise + 1) / 8 * cellH
                        let beam = logoMix(cell.color, logoWhite, 0.85)
                        let edge = waveEdge
                        logoAlpha(beam, 0.20 * cell.coverage).setFill()
                        NSRect(x: r.minX - 0.5, y: r.minY - 0.5,
                               width: r.width + 1.0, height: h + 1.0).fill()
                        logoAlpha(logoMix(beam, logoWhite, CGFloat(rise) / 7 * 0.35), cell.coverage).setFill()
                        NSRect(x: r.minX, y: r.minY, width: r.width, height: h).fill()
                        logoAlpha(edge, cell.coverage).setFill()
                        NSRect(x: r.minX, y: r.minY + h - 0.7, width: r.width, height: 0.8).fill()
                    case .slice:
                        // the two halves slide in from opposite sides
                        let p = min(1, max(0, (elapsed - (rt - effect.lead)) / effect.lead))
                        let left = Double(cell.col) < Double(grid.cols - 1) / 2
                        let rem = CGFloat(bounds.width / 2) * (1 - p) * (1 - p)
                        cell.fill.setFill()
                        box.offsetBy(dx: left ? -rem : rem, dy: 0).fill()
                    case .spray:
                        // cells fly out of a single nozzle at varying rates
                        let p = min(1, max(0, (elapsed - (rt - effect.lead)) / effect.lead))
                        let ease = CGFloat(1 - (1 - p) * (1 - p))
                        let r = box
                        let nx = bounds.minX + bounds.width / 2
                        let ny = bounds.minY
                        logoAlpha(cell.color, cell.coverage * CGFloat(0.25 + 0.75 * ease)).setFill()
                        r.offsetBy(dx: (nx - r.midX) * (1 - ease),
                                   dy: (ny - r.midY) * (1 - ease)).fill()
                    case .decrypt:
                        // ciphertext: a bright dither of turning quadrants,
                        // as if the character were cycling through symbols
                        let n = flickerNoise(cell, tickCount)
                        let filled = Int(n % 5)              // 0...4 quadrants lit
                        if filled > 0 {
                            let level = CGFloat((n >> 12) % 1000) / 1000
                            logoAlpha(logoMix(cell.color, logoWhite, 0.35 + 0.3 * level), cell.coverage).setFill()
                            let r = box
                            let w = r.width / 2, h = r.height / 2
                            let spin = Int((n >> 8) & 3)
                            for q in 0..<4 where (q + spin) % 4 < filled {
                                let qx = r.minX + (q % 2 == 0 ? 0 : w)
                                let qy = r.minY + (q / 2 == 0 ? 0 : h)
                                NSRect(x: qx, y: qy, width: w, height: h).fill()
                            }
                        }
                    default:
                        break
                    }
                }
                continue
            }
            if effect.kind == .errorcorrect {
                // the cell arrives wearing a wrong shade and locks on later
                let wrongUntil = rt + Double(flickerNoise(cell, 3) % 1000) / 1000 * 0.45
                if elapsed < wrongUntil {
                    let n = flickerNoise(cell, tickCount)
                    let wrong: NSColor
                    switch n % 3 {
                    case 0: wrong = logoMix(cell.color, logoWhite, 0.6)
                    case 1: wrong = logoMix(cell.color, logoBlack, 0.7)
                    default: wrong = cell.color
                    }
                    logoAlpha(wrong, cell.coverage).setFill()
                    box.fill()
                    continue
                }
                let heat = CGFloat(max(0, 1 - (elapsed - wrongUntil) / 0.18))
                if heat > 0.01 {
                    logoAlpha(logoMix(cell.color, logoWhite, 0.6 * heat), cell.coverage).setFill()
                } else {
                    cell.fill.setFill()
                }
                box.fill()
                continue
            }
            var fill = cell.fill
            if effect.kind == .colorshift {
                // shades chase each other through the wordmark, settling
                let f = CGFloat(min(1, max(0, (elapsed - rt) / 0.9)))
                let phase = Double(flickerNoise(cell, 0) % 628) / 100
                let level = CGFloat(sin(elapsed * 16 + phase)) * (1 - f)
                let color = level >= 0 ? logoMix(cell.color, logoWhite, 0.55 * level)
                                       : logoMix(cell.color, logoBlack, 0.55 * -level)
                fill = logoAlpha(color, cell.coverage)
            }
            let heat = CGFloat(max(0, 1 - (elapsed - rt) / effect.settle))
            let flare: CGFloat
            switch effect.kind {
            case .beams: flare = 0.9
            default: flare = 0.7
            }
            if heat > 0.01 {
                fill = logoAlpha(logoMix(cell.color, logoWhite, flare * heat), cell.coverage)
            }
            fill.setFill()
            box.fill()
        }
        // the beam belongs to laseretch: the cell the laser is on and where
        // it just was
        if effect.kind == .laseretch, revealed > 0, revealed < effect.cells.count {
            hot.withAlphaComponent(0.16).setFill()
            cellRects[effect.order[revealed - 1]].insetBy(dx: -1.3, dy: -1.3).fill()
            for k in 0..<4 {
                let pos = revealed - 1 - k
                guard pos >= 0 else { break }
                hot.withAlphaComponent(0.95 - 0.2 * CGFloat(k)).setFill()
                cellRects[effect.order[pos]].fill()
            }
        }
        for s in sparks {
            let f = CGFloat(max(0, s.life / s.maxLife))
            logoAlpha(logoMix(hot, s.color, 1 - f), f * 0.9).setFill()
            NSRect(x: CGFloat(s.x) - 0.8, y: CGFloat(s.y) - 0.8, width: 1.6, height: 1.6).fill()
        }
    }
}

final class RootView: NSView {
    let tabs = ["Options", "Workspaces", "Themes", "Wallpapers", "Storage", "API Keys", "Update"]
    var selected = 0
    private var logo: NSImage?
    private var lastIntroKind: LogoIntroKind?
    private var introRun = 0
    private let logoView = NSImageView()
    private let logoIntro = LogoIntroView(frame: .zero)
    private let options = OptionsTabView(frame: .zero)
    private let workspaces = WorkspacesTabView(frame: .zero)
    private let themes = ThemesTabView(frame: .zero)
    private let wallpapers = WallpapersTabView(frame: .zero)
    private let storage = StorageTabView(frame: .zero)
    private let keys = APIKeysTabView(frame: .zero)
    private let update = UpdateTabView(frame: .zero)
    private lazy var tabViews: [NSView] = [options, workspaces, themes, wallpapers, storage, keys, update]
    var onHide: (() -> Void)?

    private let logoH: CGFloat = 40
    private let topPad: CGFloat = 16
    private let tabH: CGFloat = 40
    private let pad: CGFloat = 20

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        logoView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(logoView)
        logoIntro.isHidden = true
        addSubview(logoIntro)
        addSubview(options)
        options.onApplied = { [weak self] in self?.optionsApplied() }
        themes.onApplied = { [weak self] in self?.paletteChanged() }
        reloadLogo()
    }

    // A theme switch swaps the palette under the whole modal. Every surface
    // draws its own colour, so each has to be told to repaint: the tab view,
    // its document/list subviews and the custom scroller. Left alone they keep
    // the old theme until the next scroll or hover.
    func paletteChanged() {
        palette = loadPalette()
        refreshSelectionColors()
        reloadLogo()
        for v in tabViews { (v as? RefreshableTab)?.refreshColors() }
        ThemeEditor.refreshColors()
        needsDisplay = true
    }
    // A saved Options change can move the window-corner radius or the border
    // width, and every surface draws its own copy: the card (this view), the
    // Options tab's own controls and its Save button, and an open Theme Studio
    // editor. Repaint them together, once, instead of waiting for a tab switch.
    private func optionsApplied() {
        needsDisplay = true
        options.refreshColors()
        ThemeEditor.refreshColors()
    }

    // test door: exercise the post-save repaint without running the commands
    func debugOptionsApplied() { optionsApplied() }

    // test door: which corner-drawing pieces the Options save repaints
    func debugOptionDirtyFlags() -> [String: Bool] { options.debugDirtyFlags() }
    func debugClearOptionDirty() { options.debugClearDirty() }

    required init?(coder: NSCoder) { fatalError("not used") }

    func reloadLogo() {
        cancelLogoIntro()
        logo = logoImage()
        logoView.image = logo
        needsDisplay = true
        for v in tabViews { v.needsDisplay = true }
    }

    // The open animation: the wordmark comes alive when the modal is shown.
    // The cell grid is sampled from the current tinted image each time, so a
    // wordmark swap keeps animating with no new asset; reduce-motion goes
    // straight to the resting logo.
    func playLogoIntro() {
        cancelLogoIntro()
        layoutSubtreeIfNeeded()
        guard let logo, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        guard let grid = LogoGrid.build(from: logo, rows: max(1, Int((logoH / 2.2).rounded()))),
              !grid.cells.isEmpty else { return }
        logoIntro.frame = logoView.frame
        logoIntro.onFinished = { [weak self] in self?.finishLogoIntro() }
        logoView.alphaValue = 0
        logoIntro.start(grid: grid, kind: nextLogoIntroKind())
    }

    // LOGO_INTRO in settings.conf pins one effect (OMACOSY_LOGO_INTRO does it
    // for a single launch, for testing); otherwise each open picks another
    // one at random, never repeating the last, like the omarchy site's own
    // rotation.
    private func nextLogoIntroKind() -> LogoIntroKind {
        if let pinned = logoIntroPin() {
            lastIntroKind = pinned
            return pinned
        }
        var rng = SplitMix64(seed: UInt64.random(in: .min ... .max))
        var pool = LogoIntroKind.allCases
        if let last = lastIntroKind, pool.count > 1 { pool.removeAll { $0 == last } }
        let kind = pool.randomElement(using: &rng) ?? .laseretch
        lastIntroKind = kind
        return kind
    }

    private func logoIntroPin() -> LogoIntroKind? {
        let env = ProcessInfo.processInfo.environment["OMACOSY_LOGO_INTRO"]
        return (env ?? readConfKey(SETTINGS, "LOGO_INTRO")).flatMap(LogoIntroKind.init(rawValue:))
    }

    private func cancelLogoIntro() {
        introRun &+= 1
        logoIntro.cancel()
        logoView.layer?.removeAllAnimations()
        logoView.alphaValue = 1
    }

    // the effect has settled; land on the crisp wordmark and put the overlay
    // away until the next open. A quick reopen starts a new run while this
    // fade is still in flight, so introRun stamps it and a stale fade can
    // never cancel the new run and leave the logo area empty.
    private func finishLogoIntro() {
        introRun &+= 1
        let run = introRun
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            self.logoIntro.animator().alphaValue = 0
            self.logoView.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let self, self.introRun == run else { return }
            self.logoIntro.cancel()
        })
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
            logoIntro.frame = logoView.frame
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
        let w = borderWidth()
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: w / 2, dy: w / 2), xRadius: corner, yRadius: corner)
        palette.barBG.setFill()
        body.fill()
        palette.accent.setStroke()
        body.lineWidth = w
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
        // A click on the card's own body (padding, section rules, labels) is
        // inert. The card is this view, so hiding here would dismiss the
        // dashboard under the pointer; only a click OUTSIDE the window
        // (AppDelegate's global monitor), Esc, or Super+, closes it.
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
        if let root { root.playLogoIntro() }
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
                // A global monitor also sees the click that re-activates an
                // inactive app, so a click INSIDE the dashboard can arrive
                // here as the window is raised. Only a click outside its
                // frame is a dismiss (the colour panel already guards this
                // way); otherwise the modal closed under the pointer.
                if let w = self.window, w.isVisible, w.frame.contains(NSEvent.mouseLocation) { return }
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

    check("pasted URL yields its id",
          whPastedID("https://wallhaven.cc/w/13rqy1") == "13rqy1")
    check("pasted URL without a scheme works",
          whPastedID("wallhaven.cc/w/13rqy1") == "13rqy1")
    check("pasted URL with www and a query works",
          whPastedID("https://www.wallhaven.cc/w/13rqy1/?x=1") == "13rqy1")
    check("an ordinary query is not an id", whPastedID("winter snow") == nil)
    check("source accepts an https link",
          whExternalURL("https://www.deviantart.com/koy") != nil)
    check("source rejects a file link",
          whExternalURL("file:///etc/passwd") == nil)

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

    let meta = WHWallpaper(json: [
        "id": "abc123",
        "path": "https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg",
        "resolution": "6742x3534",
        "views": NSNumber(value: 1234),
        "favorites": NSNumber(value: 87),
        "source": "https://example.com/x",
        "colors": ["#000000", "#ffffff"],
        "created_at": "2018-10-31 01:23:10",
        "file_type": "image/jpeg",
        "ratio": "1.91",
        "dimension_x": NSNumber(value: 6742),
        "dimension_y": NSNumber(value: 3534),
    ])!
    check("metadata reads views and favorites", meta.views == 1234 && meta.favorites == 87)
    check("metadata reads colours", meta.colors.count == 2)
    check("metadata keeps the source", meta.source == "https://example.com/x")
    check("metadata formats the date", whMetaDate(meta.createdAt) == "31 Oct 2018")
    check("metadata formats a grouped count", whGroupedInt(1234) == "1,234")

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

    // bulk retry policy: which errors get another attempt, and the wait shape
    check("retry: 429 is retryable", whDownloadIsRetryable(WHError.http(429)))
    check("retry: a rate-limit error is retryable", whDownloadIsRetryable(WHError.rateLimited(nil)))
    check("retry: a server error is retryable", whDownloadIsRetryable(WHError.http(503)))
    check("retry: a dropped connection is retryable", whDownloadIsRetryable(WHError.network("reset")))
    check("retry: a 404 is final", !whDownloadIsRetryable(WHError.http(404)))
    check("retry: an oversized file is final", !whDownloadIsRetryable(WHError.tooLarge))
    check("retry: a bad link is final", !whDownloadIsRetryable(WHError.badURL("invalid")))
    var firstInBand = true, growInBand = true, capInBand = true
    var afterNotEarly = true, afterJittered = true
    for _ in 0..<200 {
        let d1 = whRetryDelay(attempt: 1, error: WHError.http(500))
        if d1 < 2.0 * 0.6 - 0.0001 || d1 > 2.0 * 1.4 + 0.0001 { firstInBand = false }
        let d3 = whRetryDelay(attempt: 3, error: WHError.network("reset"))
        if d3 < 8.0 * 0.6 - 0.0001 || d3 > 8.0 * 1.4 + 0.0001 { growInBand = false }
        let d9 = whRetryDelay(attempt: 9, error: WHError.http(500))
        if d9 < 30.0 * 0.6 - 0.0001 || d9 > 30.0 * 1.4 + 0.0001 { capInBand = false }
        let ra = whRetryDelay(attempt: 1, error: WHError.rateLimited(7))
        if ra < 7.0 - 0.0001 { afterNotEarly = false }
        if ra > 7.0 * 1.25 + 0.0001 { afterJittered = false }
    }
    check("retry: attempt 1 waits ~2 s", firstInBand)
    check("retry: the wait grows to ~8 s by attempt 3", growInBand)
    check("retry: the wait is capped at 30 s", capInBand)
    check("retry: Retry-After is honoured, never shortened", afterNotEarly)
    check("retry: Retry-After gets jitter on top", afterJittered)

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
        let info = try client.info(CommandLine.arguments[2])
        let w = info.wallpaper
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

// The requested bulk behaviour, driven headlessly: a file that lands clears
// its checkbox the moment it arrives, and a file still failed after its
// retries keeps it, so the button comes back offering exactly the failures.
// No window and no network: the tab is built detached and its landing
// bookkeeping is fed by hand.
func bulkDownloadSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    palette = loadPalette()
    let tab = WallpapersTabView(frame: NSRect(x: 0, y: 0, width: 860, height: 720))
    let cards = (0..<6).compactMap { i in
        WHWallpaper(json: ["id": "selftest\(i)",
                           "path": "https://w.wallhaven.cc/full/ab/wallhaven-selftest\(i).jpg",
                           "resolution": "1920x1080",
                           "file_size": NSNumber(value: 1_000_000),
                           "thumbs": ["small": "https://thumbs/selftest\(i).jpg"]])
    }
    check("the selftest builds its cards", cards.count == 6)
    tab.debugSeedCards(cards)
    tab.debugBulkSimulate(4, failures: [1, 3])
    var s = tab.debugBulkStatus()
    check("the selection keeps exactly the failures", s.contains("selected=[selftest1,selftest3]"))
    check("the failures stay checked", s.contains("gridSelected=2"))
    check("the counters read two failed of four", s.contains("failed=2") && s.contains("done=4"))
    check("the batch ends", s.contains("total=0"))
    tab.debugBulkSimulate(3, failures: [])
    s = tab.debugBulkStatus()
    check("a clean batch leaves nothing checked", s.contains("selected=[]"))
    check("a clean batch has no failures", s.contains("failed=0"))
    print(failures == 0 ? "bulk-download selftest: all checks passed"
                        : "bulk-download selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--bulk-download-selftest") {
    exit(bulkDownloadSelfTest() == 0 ? 0 : 1)
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

// The colour-filter presets: one per main hue, each a black-and-white recipe
// with a coloured tint. Checks the preset table, the apply/reset rule, the
// JSON round-trip and the tint math the preview and the engine share.
func colorFilterSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    let filters = EditorPresets.all.filter { EditorPresets.colorFilters.contains($0.name) }
    check("eight colour filters", filters.count == 8)
    check("colour filters are part of the preset list",
          filters.count == EditorPresets.colorFilters.count)
    check("preset names are unique",
          Set(EditorPresets.all.map { $0.name }).count == EditorPresets.all.count)
    check("every filter is black and white with a full-strength tint",
          filters.allSatisfy {
              $0.values["saturation"] == 0
                  && $0.values["colorFilterStrength"] == 100
                  && ($0.values["colorFilterHue"] ?? -1) >= 0
                  && ($0.values["colorFilterHue"] ?? 361) <= 360
          })

    var working = EditorFilters()
    working.sepia = 40
    working.brightness = 130
    working.colorFilterStrength = 60
    working.colorFilterHue = 200
    let red = working.applyingPreset(
        EditorPresets.all.first { $0.name == "Red Filter" }!.values.mapValues { $0 as Any })
    check("a filter preset resets the recipe it replaces",
          red.sepia == 0 && red.brightness == 100 && red.saturation == 0)
    check("a filter preset carries its hue and strength",
          red.colorFilterHue == 0 && red.colorFilterStrength == 100)
    check("a filter recipe is not the identity", !red.isIdentity)

    let json = red.jsonObject()
    let roundTrip = EditorFilters(json: json)
    check("the filter survives a JSON round-trip",
          roundTrip.colorFilterHue == red.colorFilterHue
              && roundTrip.colorFilterStrength == red.colorFilterStrength
              && roundTrip == red)

    var half = red
    half.strength = 50
    check("Strength scales the filter amount", half.strengthScaled().colorFilterStrength == 50)
    check("a hue with no strength is the identity",
          EditorFilters().isIdentity
              && { var f = EditorFilters(); f.colorFilterHue = 90; return f.isIdentity }())

    let r = colorFilterTint(0), g = colorFilterTint(120), b = colorFilterTint(240)
    check("hue 0 is red", r.r == 1 && r.g < r.r && r.b < r.r)
    check("hue 120 is green", g.g == 1 && g.r < g.g && g.b < g.g)
    check("hue 240 is blue", b.b == 1 && b.r < b.b && b.g < b.b)

    // The live preview's CoreImage path must tint too, not only the engine.
    let solid = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    var previewRecipe = EditorFilters()
    previewRecipe.saturation = 0
    previewRecipe.colorFilterStrength = 100
    previewRecipe.colorFilterHue = 0
    if let cg = editorPreviewRender(solid, raw: previewRecipe, maxSize: 0),
       let space = CGColorSpace(name: CGColorSpace.sRGB) {
        var px = [UInt8](repeating: 0, count: 4)
        if let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8,
                               bytesPerRow: 4, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            check("the preview tints the luma red",
                  Int(px[0]) > Int(px[1]) && Int(px[0]) > Int(px[2]))
        }
    } else {
        check("the preview renders the colour filter", false)
    }

    print(failures == 0 ? "colour-filter selftest: all checks passed"
                        : "colour-filter selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--color-filter-selftest") {
    exit(colorFilterSelfTest() == 0 ? 0 : 1)
}

// The context menu's day/night rules are two pure functions; drive them with
// all three cell kinds so a spec-form change cannot half-land. Like the other
// doors it runs before the window opens.
func dayNightSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    let edition = ThemeCell(logical: "custom",
                            wallpaper: HOME + "/.local/share/omacosy/theme-media/pic.png",
                            title: "Sunset Drive (Night)", isCustom: true,
                            paletteFile: "", editionID: "sunset-drive-night")
    check("an edition's spec is theme:<id>",
          dayNightSpec(for: edition) == "theme:sunset-drive-night")
    check("an edition matches its own spec",
          dayNightSpecNames("theme:sunset-drive-night", edition))
    check("another edition does not match",
          !dayNightSpecNames("theme:other", edition))
    check("a wallpaper path does not match an edition",
          !dayNightSpecNames(edition.wallpaper, edition))

    let raw = ThemeCell(logical: "custom", wallpaper: "/tmp/pics/beach.jpg",
                        title: "Wallpaper #1", isCustom: true, paletteFile: "")
    check("a raw wallpaper's spec is its path",
          dayNightSpec(for: raw) == "/tmp/pics/beach.jpg")
    check("an absolute spec matches the raw cell",
          dayNightSpecNames("/tmp/pics/beach.jpg", raw))
    check("a bare filename matches a raw cell in the folder",
          dayNightSpecNames("beach.jpg", raw))
    check("a stock spec does not match a raw cell",
          !dayNightSpecNames("gruvbox/beach.jpg", raw))

    let stock = ThemeCell(logical: "gruvbox",
                          wallpaper: "/repo/themes/gruvbox/backgrounds/2-flower.webp",
                          title: "Gruvbox — 2 Flower", isCustom: false, paletteFile: "")
    check("a stock cell's spec is <theme>/<file>",
          dayNightSpec(for: stock) == "gruvbox/2-flower.webp")
    check("the stock spec matches its cell",
          dayNightSpecNames("gruvbox/2-flower.webp", stock))
    check("another theme's wallpaper does not match",
          !dayNightSpecNames("tokyo-night/2-flower.webp", stock))

    print(failures == 0 ? "day-night selftest: all checks passed"
                        : "day-night selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--day-night-selftest") {
    exit(dayNightSelfTest() == 0 ? 0 : 1)
}

// The Themes gallery splits the custom half into a Custom Themes block and
// an Auto Themes block, each with its own rule and heading. Drive the layout
// with synthetic cells so every mix of the three kinds is checked off-screen.
func themeSectionsSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    let stock = ThemeCell(logical: "gruvbox", wallpaper: "/tmp/stock.webp",
                          title: "Gruvbox — 2 Flower", isCustom: false,
                          paletteFile: "/tmp/colors.toml")
    let edited = ThemeCell(logical: "custom", wallpaper: "/tmp/edited.png",
                           title: "Sunset Drive", isCustom: true,
                           paletteFile: "", editionID: "sunset-drive")
    let seed = ThemeCell(logical: "custom", wallpaper: "/tmp/seed.png",
                         title: "Wallpaper #1", isCustom: true, paletteFile: "")
    let grid = ThemeGridView(frame: NSRect(x: 0, y: 0, width: 860, height: 720))
    func layout(_ cells: [ThemeCell]) -> ([String], Int) {
        grid.cells = cells
        grid.rebuild()
        return (grid.debugSectionTitles(), grid.debugSeparatorCount())
    }

    let all = layout([stock, edited, seed])
    check("all three kinds get a block", all.0 == ["Omarchy Themes", "Custom Themes", "Auto Themes"])
    check("all three kinds get two rules", all.1 == 2)
    check("stock alone gets no rule", layout([stock]).0 == ["Omarchy Themes"] && layout([stock]).1 == 0)
    check("an edition alone gets no rule", layout([edited]).0 == ["Custom Themes"] && layout([edited]).1 == 0)
    check("a seed alone gets no rule", layout([seed]).0 == ["Auto Themes"] && layout([seed]).1 == 0)
    let noStock = layout([edited, seed])
    check("edited and seed still split without stock",
          noStock.0 == ["Custom Themes", "Auto Themes"] && noStock.1 == 1)
    let noEdited = layout([stock, seed])
    check("stock and seed are separated by one rule",
          noEdited.0 == ["Omarchy Themes", "Auto Themes"] && noEdited.1 == 1)
    let empty = layout([])
    check("an empty gallery has no headings", empty.0.isEmpty && empty.1 == 0)

    print(failures == 0 ? "themes-sections selftest: all checks passed"
                        : "themes-sections selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--themes-sections-selftest") {
    exit(themeSectionsSelfTest() == 0 ? 0 : 1)
}

// The Themes gallery must open at the top when the tab is (re)shown, and must
// NOT move when an apply or an edit reloads the shelf. Drives the view
// off-screen and asserts both, so a future rebuild-path change cannot quietly
// bring the jump back.
func themesScrollSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    palette = loadPalette()
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 720),
                       styleMask: .borderless, backing: .buffered, defer: false)
    let tab = ThemesTabView(frame: NSRect(x: 0, y: 0, width: 860, height: 720))
    win.contentView = tab
    tab.layoutSubtreeIfNeeded()
    let top = tab.debugTopY()
    guard top > 100 else {
        print("themes-scroll selftest: SKIP (not enough wallpapers to scroll)")
        return 0
    }
    check("opens at the top", abs(tab.debugOriginY() - top) < 1)
    check("at the top, the jump button offers the bottom",
          !tab.debugJumpHidden() && !tab.debugJumpUp())
    tab.debugScrollToBottom()
    let bottom = tab.debugOriginY()
    check("at the bottom, the arrow offers the top",
          !tab.debugJumpHidden() && tab.debugJumpUp())
    tab.debugReload()
    tab.layoutSubtreeIfNeeded()
    check("an apply reload keeps the scroll position", abs(tab.debugOriginY() - bottom) < 1)
    check("an apply reload does not jump to the top", abs(tab.debugOriginY() - top) > 1)
    win.contentView = NSView(frame: win.contentView?.frame ?? .zero)
    win.contentView = tab
    tab.layoutSubtreeIfNeeded()
    check("a re-show opens at the top", abs(tab.debugOriginY() - top) < 1)
    // the floating arrow: down at the top, up after a scroll upwards, and
    // always pointing somewhere it can actually go
    tab.debugJumpClick()
    check("the down arrow jumps to the bottom", abs(tab.debugOriginY() - bottom) < 1)
    check("the arrow now offers the top", !tab.debugJumpHidden() && tab.debugJumpUp())
    tab.debugScroll(by: -120)   // negative dy walks back towards the top
    check("scrolling up keeps the arrow pointing up",
          !tab.debugJumpHidden() && tab.debugJumpUp())
    tab.debugJumpClick()
    check("the up arrow jumps to the top", abs(tab.debugOriginY() - top) < 1)
    check("at the top, the arrow offers the bottom again",
          !tab.debugJumpHidden() && !tab.debugJumpUp())
    print(failures == 0 ? "themes-scroll selftest: all checks passed"
                        : "themes-scroll selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--themes-scroll-selftest") {
    exit(themesScrollSelfTest() == 0 ? 0 : 1)
}

// The Bookmarked view gets the same floating arrow as the Themes gallery. It
// must be absent from the search results, open offering the bottom, and flip
// at each end.
func wallpapersJumpSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    palette = loadPalette()
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 720),
                       styleMask: .borderless, backing: .buffered, defer: false)
    let tab = WallpapersTabView(frame: NSRect(x: 0, y: 0, width: 860, height: 720))
    // seed before attaching so the first show skips its network search, and
    // again afterwards because the show re-reads the saved config
    tab.debugSeedBookmarks(60)
    win.contentView = tab
    tab.debugSeedBookmarks(60)
    tab.layoutSubtreeIfNeeded()
    tab.layoutSubtreeIfNeeded()
    let top = tab.debugJumpTopY()
    guard top > 100 else {
        print("wallpapers-jump selftest: SKIP (not enough bookmarks to scroll)")
        return 0
    }
    check("bookmarks open at the top", abs(tab.debugJumpOriginY() - top) < 1)
    check("at the top, the arrow offers the bottom",
          !tab.debugJumpHidden() && !tab.debugJumpUp())
    tab.debugJumpToBottom()
    check("at the bottom, the arrow offers the top",
          !tab.debugJumpHidden() && tab.debugJumpUp())
    tab.debugJumpClick()
    check("the up arrow jumps to the top", abs(tab.debugJumpOriginY() - top) < 1)
    check("at the top, the arrow offers the bottom again",
          !tab.debugJumpHidden() && !tab.debugJumpUp())
    tab.debugJumpToBottom()
    tab.debugJumpScroll(by: -120)   // negative dy walks back towards the top
    check("scrolling up keeps the arrow pointing up",
          !tab.debugJumpHidden() && tab.debugJumpUp())
    let before = tab.debugJumpOriginY()
    tab.debugUnbookmark(at: 0)
    tab.layoutSubtreeIfNeeded()
    check("unbookmarking keeps the viewport",
          abs(tab.debugJumpOriginY() - before) < 1)
    tab.debugLeaveBookmarks()
    tab.layoutSubtreeIfNeeded()
    check("the arrow hides outside the Bookmarked view", tab.debugJumpHidden())
    print(failures == 0 ? "wallpapers-jump selftest: all checks passed"
                        : "wallpapers-jump selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--wallpapers-jump-selftest") {
    exit(wallpapersJumpSelfTest() == 0 ? 0 : 1)
}

// Prints the intro's real cell count and duration per effect, so a pacing
// change can be judged without screen-recording the modal. The numbers are
// the animation itself; add the 0.03 s lead-in and 0.12 s crossfade for the
// time the logo area is not the crisp wordmark.
func logoTimingReport() -> Int {
    palette = loadPalette()
    guard let logo = logoImage(),
          let grid = LogoGrid.build(from: logo,
                                    rows: max(1, Int((40.0 / 2.2).rounded()))) else {
        print("no logo")
        return 1
    }
    print("cells \(grid.cells.count)")
    for kind in LogoIntroKind.allCases {
        let effect = LogoIntroEffect(grid: grid, kind: kind, seed: 1)
        let name = kind.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
        print(name + String(format: "%.2f s  (lead %.2f, settle %.2f)",
                            effect.duration, effect.lead, effect.settle))
    }
    return 0
}

if CommandLine.arguments.contains("--logo-timing") {
    exit(logoTimingReport() == 0 ? 0 : 1)
}

// A saved Window & UI Corners (or Borders) change moves the radius every
// Omacosy-drawn surface uses, including the Options tab's own controls and its
// Save button. They used to keep the old radius until the tab was switched
// away and back; the save must repaint them at once. Drives a RootView
// off-screen and asserts the post-save repaint covers every corner-drawing
// piece, so the missing-refresh bug cannot come back.
func windowCornerSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    palette = loadPalette()
    // tall enough that every Options row is inside the scroll clip: a view
    // scrolled out of sight is not marked dirty, which would hide the very
    // controls this test is about
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 1200),
                       styleMask: .borderless, backing: .buffered, defer: false)
    let root = RootView(frame: NSRect(x: 0, y: 0, width: 860, height: 1200))
    win.contentView = root
    root.layoutSubtreeIfNeeded()
    // needsDisplay is only honoured for a view in a window; flush the first
    // layout, then clear so the post-save repaint is what sets the flags
    root.displayIfNeeded()
    root.debugClearOptionDirty()
    root.debugOptionsApplied()
    let flags = root.debugOptionDirtyFlags()
    check("the tab body repaints", flags["doc"] == true)
    check("the Save button repaints", flags["saveButton"] == true)
    check("every segmented control repaints",
          !flags.isEmpty && flags.filter { $0.key.hasPrefix("seg") }.values.allSatisfy { $0 })
    check("every toggle repaints",
          flags.filter { $0.key.hasPrefix("toggle") }.values.allSatisfy { $0 })
    check("every slider repaints",
          flags.filter { $0.key.hasPrefix("slider") }.values.allSatisfy { $0 })
    let covered = flags.values.filter { $0 }.count
    check("no corner-drawing piece is left behind (\(covered)/\(flags.count))",
          !flags.isEmpty && covered == flags.count)
    print(failures == 0 ? "window-corner selftest: all checks passed"
                        : "window-corner selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--window-corner-selftest") {
    exit(windowCornerSelfTest() == 0 ? 0 : 1)
}

// The preview's AA pill and the Accessibility table's summary are one tally;
// drive it with synthetic rows so the two spellings cannot drift apart. Like
// the other doors it runs before the window opens.
func aaScoreSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    func row(_ ratios: [Double]) -> PaletteModel.ContrastRow {
        PaletteModel.ContrastRow(name: "Label", hex: "#ffffff", ratios: ratios)
    }
    let rows = [row([21, 4.5, 4.49]), row([7, 3, 1.1])]
    let tally = contrastAATally(rows)
    check("AA counts 4.5 and above", tally.pass == 3)
    check("every surface is counted", tally.total == 6)
    check("the pill spells the tally compactly", contrastAAPillText(rows) == "AA 3/6")
    check("a perfect palette reads full", contrastAAPillText([row([8, 8, 8])]) == "AA 3/3")
    check("no rows means no pill text", contrastAAPillText([]) == "AA 0/0")
    print(failures == 0 ? "aa-score selftest: all checks passed"
                        : "aa-score selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--aa-score-selftest") {
    exit(aaScoreSelfTest() == 0 ? 0 : 1)
}

// The editor's UI accent is Aether's ANSI blue slot, not the red slot's
// lightened orange (the semantic ACCENT group's Orange shade). Aether's own
// Semantic Colors panel shows the two side by side — #F59CB5 under ACCENT /
// Orange, #89B4FA under UI / Accent — and its bar, ring and chrome follow the
// latter. Pin that apart so the red slot cannot quietly drive the desktop
// again on a blue-dominant wallpaper.
func paletteAccentSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    // Catppuccin Mocha: the palette in the Aether screenshot beside the bug
    // report. Its blue slot is #89b4fa, its red slot lightens to #f59cb5.
    let mocha = ["#1e1e2e", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7",
                 "#94e2d5", "#cdd6f4", "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af",
                 "#89b4fa", "#cba6f7", "#94e2d5", "#bac2de"]
    let ext = paletteExtendedDefaults(mocha, accent: nil)
    check("the UI accent is Aether's ANSI blue slot", ext["accent"] == "#89b4fa")
    check("the red slot's orange is not the UI accent",
          ext["accent"] != lightenedHex("#f38ba8", percent: 15))
    check("cursor and selection follow the palette",
          ext["cursor"] == "#cdd6f4" && ext["selection_foreground"] == "#1e1e2e"
              && ext["selection_background"] == "#cdd6f4")
    check("Magic keeps the accent it extracted from the picture",
          paletteExtendedDefaults(mocha, accent: "#46a8ef")["accent"] == "#46a8ef")
    check("a short palette still yields four colours",
          paletteExtendedDefaults(["#123456"], accent: nil).values.allSatisfy { $0 == "#000000" })
    print(failures == 0 ? "palette accent selftest: all checks passed"
                        : "palette accent selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--palette-accent-selftest") {
    exit(paletteAccentSelfTest() == 0 ? 0 : 1)
}

// The semantic grid has one full-width row now (Syntax). Its row count and
// height must agree, or the last row draws over Template Override again.
func syntaxLayoutSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    func group(_ title: String, variants: Bool = false,
               full: Bool = false) -> SemanticSectionView.Group {
        .init(title: title,
              cards: [.init(label: "Operator", hex: "#ffffff", key: "operator")],
              variantCards: variants ? [.init(label: "Escape", hex: "#ffffff")] : [],
              fullWidth: full)
    }
    let groups = [group("Background"), group("Foreground"), group("Accent"),
                  group("Terminal"), group("Omacosy"), group("Ring & Status"),
                  group("Syntax", variants: true, full: true)]
    check("seven groups make four rows", SemanticSectionView.rowCount(groups) == 4)
    check("height covers the variant row",
          SemanticSectionView.height(for: groups) == 4 * 86 + 3 * 8 + 50)
    check("a full-width group starts its own row",
          SemanticSectionView.rowCount([group("Syntax", full: true), group("Omacosy")]) == 2)
    print(failures == 0 ? "syntax layout selftest: all checks passed"
                        : "syntax layout selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--syntax-layout-selftest") {
    exit(syntaxLayoutSelfTest() == 0 ? 0 : 1)
}

// A Magic draft takes its 16 colours from term-palette's ANSI set, whose slot 0
// is ANSI black (the background lightened 0.10) — so the preview and a saved
// Magic theme painted their terminal a rung too light and looked washed out
// over the wallpaper, unlike every Aether preset. The draft now seeds slot 0
// from OMACOSY_BG, the background the theme really draws on; pin it here.
func magicBackgroundSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    // The derived theme of wallhaven-13vym3 on this machine: P0 is ANSI black,
    // OMACOSY_BG is the surface the auto theme actually draws on.
    let ansi = ["2f2720", "d08260", "86a559", "bb9043", "8293db", "c77daa", "27adad", "e6c8a8",
                "736a61", "f9a784", "abcb7e", "e2b669", "a9bafd", "efa2d0", "59d3d3", "e6c8a8"]
    let fixed = magicThemeColors(ansi, background: "171009")
    check("slot 0 is the theme's real background", fixed[0] == "#171009")
    check("the ANSI colours after slot 0 are untouched",
          Array(fixed[1...]) == Array(ansi[1...]))
    check("a #-prefixed background normalises too",
          magicThemeColors(ansi, background: "#171009")[0] == "#171009")
    check("without a background the set is unchanged", magicThemeColors(ansi, background: nil) == ansi)
    check("a malformed background is ignored", magicThemeColors(ansi, background: "nope") == ansi)
    check("a short set is left alone", magicThemeColors(["2f2720"], background: "171009") == ["2f2720"])
    print(failures == 0 ? "magic background selftest: all checks passed"
                        : "magic background selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--magic-background-selftest") {
    exit(magicBackgroundSelfTest() == 0 ? 0 : 1)
}

// The picker's arrow keys must move the LIST's highlight, not just the
// card's own index: the list is what draws the selected row, and a move
// that only lands on the card looks like "the arrows do nothing" while
// Return still picks the unseen selection. Drives the root off-screen and
// walks the pure header-skipping step, like the other doors.
func dropdownSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    let rows = [
        MethodPicker.Row(header: "COLOR THEORY", value: nil, label: "COLOR THEORY"),
        MethodPicker.Row(header: nil, value: "Analogous", label: "Analogous"),
        MethodPicker.Row(header: nil, value: "Complementary", label: "Complementary"),
        MethodPicker.Row(header: "MOOD", value: nil, label: "MOOD"),
        MethodPicker.Row(header: nil, value: "Fire", label: "Fire"),
    ]
    check("a step off a row lands on the next row", MethodPicker.stepped(1, 1, rows: rows) == 2)
    check("a step over a header skips it", MethodPicker.stepped(2, 1, rows: rows) == 4)
    check("stepping back reaches the row before the header", MethodPicker.stepped(4, -1, rows: rows) == 2)
    check("walking past the end stops", MethodPicker.stepped(4, 1, rows: rows) == nil)
    check("walking past the top stops", MethodPicker.stepped(1, -1, rows: rows) == nil)

    palette = loadPalette()
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 430),
                       styleMask: .borderless, backing: .buffered, defer: false)
    let root = MethodPickerRoot(frame: NSRect(x: 0, y: 0, width: 340, height: 430))
    win.contentView = root
    root.rows = rows
    root.selected = 1
    root.relayout()
    check("the card hands the current row to the list", root.list.selected == 1)
    root.setSelected(4)
    check("a move reaches the list's highlight", root.selected == 4 && root.list.selected == 4)
    root.setSelected(2)
    check("moving back reaches it too", root.selected == 2 && root.list.selected == 2)
    print(failures == 0 ? "dropdown selftest: all checks passed"
                        : "dropdown selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--dropdown-selftest") {
    exit(dropdownSelfTest() == 0 ? 0 : 1)
}

// The Workspace names block in settings.conf is read and written by hand
// (the file is sourced by the shell, never by the dashboard), so its two
// formats, its escaping and the in-place block replacement get their own
// door. Like the other doors it runs before the window opens.
func workspaceNamesSelfTest() -> Int {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { failures += 1 }
    }
    let tmp = NSTemporaryDirectory() + "omacosy-names-selftest-\(ProcessInfo.processInfo.processIdentifier)"
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    try? """
    TERMINAL=Ghostty
    WORKSPACE_NAMES="
    1    Work
    11    Deep Work
    "

    APP_FLOAT_RULES=""
    """.write(toFile: tmp, atomically: true, encoding: .utf8)
    check("a multi-line block is read",
          readWorkspaceNames(tmp) == ["1": "Work", "11": "Deep Work"])
    check("a key that is absent reads as nil", readConfBlock("MUSIC", tmp) == nil)

    try? "WORKSPACE_NAMES=\"2    Leisures\"\n".write(toFile: tmp, atomically: true, encoding: .utf8)
    check("a one-line block is read", readWorkspaceNames(tmp) == ["2": "Leisures"])

    // the shelly characters must survive a write→read trip: the shell would
    // eat or expand them if their escapes did not reach the file
    let tricky = ["1": "It's a $5 \"work\" `day` \\ night", "9": "Course work"]
    try? "TERMINAL=Ghostty\nWORKSPACE_NAMES=\"\"\nMUSIC=Spotify\n"
        .write(toFile: tmp, atomically: true, encoding: .utf8)
    check("the write lands", writeWorkspaceNames(tricky, tmp))
    check("every name survives the trip", readWorkspaceNames(tmp) == tricky)
    let text = (try? String(contentsOfFile: tmp, encoding: .utf8)) ?? ""
    check("the key is replaced once, not duplicated",
          text.components(separatedBy: "WORKSPACE_NAMES=").count == 2)
    check("the keys around it are untouched",
          text.contains("TERMINAL=Ghostty") && text.contains("MUSIC=Spotify"))
    // and the real consumer is the shell: source the file and compare (the
    // block keeps a leading and a trailing newline, like the rules block)
    let (rc, sourced) = shell("bash -c '. \(shellQuote(tmp)); printf %s \"$WORKSPACE_NAMES\"'")
    check("bash sources back the exact names",
          rc == 0 && sourced == "\n1    It's a $5 \"work\" `day` \\ night\n9    Course work\n")

    check("clearing writes an empty block", writeWorkspaceNames([:], tmp))
    check("an empty block reads as no names", readWorkspaceNames(tmp).isEmpty)
    check("the empty block keeps the key",
          (try? String(contentsOfFile: tmp, encoding: .utf8))?
              .contains("WORKSPACE_NAMES=\"\n\"") == true)

    try? "TERMINAL=Ghostty\n".write(toFile: tmp, atomically: true, encoding: .utf8)
    check("a file without the key gains one", writeWorkspaceNames(["3": "Learning"], tmp))
    check("the appended block reads back", readWorkspaceNames(tmp) == ["3": "Learning"])

    try? "WORKSPACE_NAMES=\"\n1\n2    Two\n\"\n"
        .write(toFile: tmp, atomically: true, encoding: .utf8)
    check("a line without a name is skipped", readWorkspaceNames(tmp) == ["2": "Two"])

    // the same block machinery still serves the app rules
    try? "APP_WORKSPACE_RULES=\"\ncom.apple.Safari    1\ncom.apple.mail      2\n\"\n"
        .write(toFile: tmp, atomically: true, encoding: .utf8)
    check("the rules reader still parses its block",
          readWorkspaceRules(tmp).map { "\($0.0) \($0.1)" }
              == ["com.apple.Safari 1", "com.apple.mail 2"])

    check("escaping round-trips",
          unescapeConfValue(escapeConfValue("a $b `c` \"d\" \\e")) == "a $b `c` \"d\" \\e")
    check("an unknown escape stays literal", unescapeConfValue("C:\\Users") == "C:\\Users")

    print(failures == 0 ? "workspace-names selftest: all checks passed"
                        : "workspace-names selftest: \(failures) failed")
    return failures
}

if CommandLine.arguments.contains("--workspace-names-selftest") {
    exit(workspaceNamesSelfTest() == 0 ? 0 : 1)
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
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--wallhaven-meta-shot" {
    // Off-screen render of the metadata card, for layout review. Uses a
    // seeded reply so it needs no network and never touches a running
    // dashboard.
    app.setActivationPolicy(.accessory)
    palette = loadPalette()
    let w = WHWallpaper(json: [
        "id": "94x38z",
        "url": "https://wallhaven.cc/w/94x38z",
        "path": "https://w.wallhaven.cc/full/94/wallhaven-94x38z.jpg",
        "resolution": "6742x3534",
        "file_size": NSNumber(value: 5_070_446),
        "category": "anime",
        "purity": "sfw",
        "views": NSNumber(value: 1234),
        "favorites": NSNumber(value: 87),
        "source": "https://example.com/the-witcher",
        "colors": ["#663300", "#996633", "#000000", "#ffcc33", "#cc6633"],
        "created_at": "2018-10-31 01:23:10",
        "file_type": "image/jpeg",
        "ratio": "1.91",
        "dimension_x": NSNumber(value: 6742),
        "dimension_y": NSNumber(value: 3534),
        "thumbs": ["large": "https://th.wallhaven.cc/lg/94/94x38z.jpg"],
    ])!
    let tags = [
        WHTag(id: 7678, name: "The Witcher", alias: "witcher", category: "Games"),
        WHTag(id: 2686, name: "The Witcher 3: Wild Hunt", alias: "wild hunt", category: "Games"),
        WHTag(id: 132574, name: "Witcher 3 7th Anniversary", alias: "", category: "Games"),
        WHTag(id: 64, name: "sunset", alias: "dusk", category: "Nature"),
        WHTag(id: 65, name: "landscape", alias: "", category: "Nature"),
        WHTag(id: 66, name: "clouds", alias: "", category: "Nature"),
        WHTag(id: 241, name: "Sun", alias: "the sun", category: "Space"),
        WHTag(id: 242, name: "starry sky", alias: "", category: "Space"),
        WHTag(id: 9001, name: "anime", alias: "Chinese cartoons", category: "Anime & Manga"),
    ]
    let uploader = WHUploader(username: "almahun112", group: "User", avatarURL: "")
    let details = WHDetails(wallpaper: w, uploader: uploader, tags: tags)

    let v = WHInfoCardView(wallpaper: w)
    v.apply(details)
    v.frame = NSRect(x: 0, y: 0, width: 620, height: v.idealHeight())
    let win = NSWindow(contentRect: v.frame, styleMask: .borderless,
                       backing: .buffered, defer: false)
    win.contentView = v
    v.layoutSubtreeIfNeeded()
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
    v.cacheDisplay(in: v.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("wrote \(CommandLine.arguments[2])")
    exit(0)
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--wallhaven-shot" {
    // Off-screen render for layout review. Never ordered front, so it cannot
    // steal focus from a running dashboard. Add `options`, `workspaces`,
    // `themes`, `storage` or `keys` to pick a tab; default is the Wallpapers tab.
    app.setActivationPolicy(.accessory)
    let shotH: CGFloat = CommandLine.arguments.contains("tall") ? 1200 : 720
    let root = RootView(frame: NSRect(x: 0, y: 0, width: 860, height: shotH))
    let win = NSWindow(contentRect: root.frame, styleMask: .borderless,
                       backing: .buffered, defer: false)
    win.contentView = root
    let args = CommandLine.arguments
    var tabIndex = 3
    if args.contains("options") { tabIndex = 0 }
    else if args.contains("workspaces") { tabIndex = 1 }
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
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--contextmenu-shot" {
    // Off-screen render of the themed context menu, for layout review.
    app.setActivationPolicy(.accessory)
    palette = loadPalette()
    let v = ContextMenuView()
    v.items = ["Duplicate Theme"]
    v.frame = NSRect(origin: .zero, size: ContextMenuView.size(for: v.items))
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
    v.cacheDisplay(in: v.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("wrote \(CommandLine.arguments[2])")
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
