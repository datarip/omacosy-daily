// omacosy-solo — a workspace holding exactly one tiled window gives that
// window the whole display, with no outer gaps. A second window arrives and
// both tile again. Close back to one and it goes full again.
//
// Off unless ~/.config/omacosy/fullscreen.conf sets solo=on. AeroSpace only:
// OmniWM's dwindle already fills a lone window (singleWindowFit = "fill").
//
// A SEPARATE PROCESS on purpose. The rule used to live inside omacosy-bar,
// where it was cheap — it rode the window list the chips already fetched —
// but a Swift trap is uncatchable, so an index out of range in the rule took
// the menu bar down with it. Nothing about fullscreening a window should be
// able to do that. Standing alone costs one `list-windows` per window event,
// measured at 21 ms, and window events are rare. The bar is untouched.
//
// The rule acts on a workspace's tiled window COUNT. Super+F changes no
// count, so a deliberate choice is never undone a second later.
//
// Modes:
//   (none)      run in the foreground, acting for real
//   --dry-run   log every decision, change nothing. For testing beside a
//               bar that still carries the old in-process rule.
//   --daemon    detach and run in the background, pidfile below
//   --force     ignore fullscreen.conf and run the rule anyway

import AppKit

let argv = CommandLine.arguments
let dryRun = argv.contains("--dry-run")
let forceOn = argv.contains("--force")
let wantDaemon = argv.contains("--daemon")

// --- plumbing -------------------------------------------------------------

let aerospaceBin = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "aerospace"

@discardableResult
func aerospace(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: aerospaceBin)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

// Every call that CHANGES something goes through here, so --dry-run has one
// gate rather than a flag tested at each call site.
@discardableResult
func act(_ args: [String]) -> String {
    guard !dryRun else {
        tlog("would run: aerospace \(args.joined(separator: " "))")
        return ""
    }
    return aerospace(args)
}

// The OTHER window manager. omacosy-wm-switch can hand the session over
// while this runs, so it is asked per use and never cached.
let omniwmBundleID = "com.barut.OmniWM"
func omniwmActive() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: omniwmBundleID).isEmpty
}

let logURL = URL(fileURLWithPath: "/tmp/omacosy-solo.log")
func tlog(_ m: String) {
    let line = "\(Date()) \(m)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.data(using: .utf8)!.write(to: logURL)
    }
    if !wantDaemon { FileHandle.standardError.write(line.data(using: .utf8)!) }
}

// --- window events --------------------------------------------------------
//
// The same SkyLight stream the bar watches. `aerospace subscribe` announces
// a window arriving and NOT a window leaving, and a close down to one window
// is the event this rule exists for, so it cannot be the trigger.

typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void

@_silgen_name("SLSRegisterNotifyProc")
func SLSRegisterNotifyProc(_ proc: NotifyProc, _ event: UInt32, _ context: UnsafeMutableRawPointer?) -> CGError
@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> Int32
@_silgen_name("SLSRequestNotificationsForWindows")
func SLSRequestNotificationsForWindows(_ cid: Int32, _ windows: UnsafePointer<UInt32>, _ count: Int32) -> CGError

let cid = SLSMainConnectionID()

// CREATE and DESTROY arrive unasked. MOVE and RESIZE do NOT: they are only
// delivered for windows this connection has explicitly subscribed to, so the
// set is kept equal to every normal window and refreshed whenever one is
// created or destroyed (bar.swift's recipe, and its reason).
//
// Leaving this out cost both Super+F detections in the first test run: a
// fullscreen turned off by hand changes no window count, so a resize is the
// only event that reports it.
var subscribed: Set<UInt32> = []
func rebuildSubscriptions() {
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
    else { return }
    var wids: [UInt32] = []
    for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
        if let n = w[kCGWindowNumber as String] as? Int { wids.append(UInt32(n)) }
    }
    let set = Set(wids)
    guard set != subscribed, !wids.isEmpty else { return }
    subscribed = set
    _ = wids.withUnsafeBufferPointer {
        SLSRequestNotificationsForWindows(cid, $0.baseAddress!, Int32(wids.count))
    }
}

let EVENT_WINDOW_MOVE: UInt32 = 806
let EVENT_WINDOW_RESIZE: UInt32 = 807
let EVENT_WINDOW_CREATE: UInt32 = 1325
let EVENT_WINDOW_DESTROY: UInt32 = 1326
// Sending a window to another workspace ORDERS IT OUT, it does not move it:
// a workspace switch fires 806/808/815, but a window CHANGING workspace fires
// only these two (bar.swift's measurement). They change the count on two
// workspaces at once, so the rule has to see them. They arrive as a pair and
// both are watched, because the pairing is observed and not promised.
let EVENT_WINDOW_ORDER: UInt32 = 808
let EVENT_WINDOW_VISIBILITY: UInt32 = 815

// --- opt-in ---------------------------------------------------------------

let autoFullscreenSolo: Bool = {
    if forceOn { return true }
    let file = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".config/omacosy/fullscreen.conf")
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
    for line in text.split(separator: "\n") where line.hasPrefix("solo=") {
        return line.dropFirst("solo=".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) == "on"
    }
    return false
}()

// --- the rule's input -----------------------------------------------------

struct Solo {
    var tiledIDs: [String: [String]] = [:]
    var fullscreenIDs: Set<String> = []
}

// Narrower than the bar's: the app name and the focused flag belong to the
// chips, and this process does not draw any.
let windowFormat = "%{workspace}|%{window-layout}|%{window-id}|%{window-is-fullscreen}"

func soloSnapshot() -> Solo {
    var s = Solo()
    for line in aerospace(["list-windows", "--all", "--format", windowFormat])
        .split(separator: "\n") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 4 else { continue }
        // A hidden app keeps its window in the list. Measured: a workspace
        // holding Zed plus a Cmd+H'd Notes lists two, so a plain count
        // refuses to fullscreen a workspace that is SHOWING one window.
        // Floating windows are left out for the same reason.
        guard f[1] != "floating", f[1] != "macos_native_window_of_hidden_app" else { continue }
        s.tiledIDs[f[0], default: []].append(f[2])
        if f[3] == "true" { s.fullscreenIDs.insert(f[2]) }
    }
    return s
}

// --- the rule's memory ----------------------------------------------------

let work = DispatchQueue(label: "com.omacosy.solo.work")
let soloLock = NSLock()

// The count each workspace was last seen at. A change means a window opened
// or closed, which is what hands a workspace back to automatic.
var soloCount: [String: Int] = [:]
// The window this rule last put into fullscreen, per workspace. Needed to
// tell "the user turned this off" from "it was never on": both look like a
// solo workspace that is not fullscreen.
var soloWeSet: [String: String] = [:]
// Workspaces where the user overrode the rule with Super+F. Cleared the
// moment a window opens or closes there.
var soloOverride: Set<String> = []
// Which windows were fullscreen at the last good look, kept for the sleep
// handler. An `aerospace` call started from willSleep is not guaranteed to
// finish before the system suspends; it resumes after the wake and answers
// with the WOKEN machine, where the fullscreen is already gone.
var lastFullscreenIDs: Set<String> = []
// Nothing is decided from the window list until this passes. For several
// seconds after a wake aerospace answers with a PARTIAL list.
var soloSettleUntil = Date.distantPast

// --- the rule -------------------------------------------------------------

func applyAutoFullscreen(_ s: Solo) {
    guard autoFullscreenSolo, !omniwmActive() else { return }
    soloLock.lock()
    let settling = Date() < soloSettleUntil
    soloLock.unlock()
    guard !settling else { return }

    // aerospace answers with nothing while a display is going down, and
    // caching that would throw the record away exactly when it is needed
    guard !s.tiledIDs.isEmpty else { return }
    soloLock.lock()
    lastFullscreenIDs = s.fullscreenIDs
    soloLock.unlock()

    // EVERY workspace, not only the focused one. App-to-workspace rules put
    // almost every window somewhere else, and those would otherwise sit
    // tiled until that workspace was next visited. The snapshot already
    // carries them, and `fullscreen on --window-id` works off screen.
    for (ws, ids) in s.tiledIDs { applySolo(ws, ids, s) }
}

func applySolo(_ ws: String, _ ids: [String], _ s: Solo) {
    guard !ids.isEmpty else { return }
    let n = ids.count

    soloLock.lock()
    let firstSight = soloCount[ws] == nil
    let countChanged = soloCount[ws] != n
    soloCount[ws] = n
    if countChanged {
        soloOverride.remove(ws)
        soloWeSet[ws] = nil
    }
    let overridden = soloOverride.contains(ws)
    let weSet = soloWeSet[ws]
    soloLock.unlock()
    guard !overridden else { return }

    if n == 1 {
        let id = ids[0]
        if s.fullscreenIDs.contains(id) {
            // already right. Record it, so turning it off later reads as the
            // user's doing rather than a state we never set.
            soloLock.lock()
            soloWeSet[ws] = id
            lastFullscreenIDs.insert(id)
            soloLock.unlock()
            return
        }
        if weSet == id {
            // we put it there, it is off now, and nothing opened or closed:
            // the only thing that does that is Super+F
            soloLock.lock()
            soloOverride.insert(ws)
            soloWeSet[ws] = nil
            soloLock.unlock()
            tlog("\(ws) left fullscreen by hand, leaving it alone")
            return
        }
        act(["fullscreen", "on", "--no-outer-gaps", "--window-id", id])
        soloLock.lock()
        soloWeSet[ws] = id
        lastFullscreenIDs.insert(id)   // recorded now, not at the next snapshot
        soloLock.unlock()
        tlog("\(ws) solo, window \(id) on")
    } else {
        let full = ids.filter { s.fullscreenIDs.contains($0) }
        guard !full.isEmpty else { return }
        // Never clear a fullscreen on a workspace this process has not seen.
        // After a restart every workspace is new, and a deliberate Super+F in
        // a multi-window workspace would be undone on sight.
        guard !firstSight else {
            soloLock.lock(); soloOverride.insert(ws); soloLock.unlock()
            tlog("\(ws) already fullscreen with \(n) windows, leaving it alone")
            return
        }
        if !countChanged {
            // fullscreen appeared here without a window opening or closing:
            // Super+F, in a workspace the rule would never fullscreen
            soloLock.lock(); soloOverride.insert(ws); soloLock.unlock()
            tlog("\(ws) fullscreened by hand with \(n) windows, leaving it alone")
            return
        }
        for id in full {
            act(["fullscreen", "off", "--window-id", id])
            soloLock.lock()
            lastFullscreenIDs.remove(id)
            soloLock.unlock()
            tlog("\(ws) holds \(n), window \(id) off")
        }
        soloLock.lock(); soloWeSet[ws] = nil; soloLock.unlock()
    }
}

func forgetSoloCounts() {
    soloLock.lock()
    soloCount.removeAll()
    soloWeSet.removeAll()
    soloOverride.removeAll()
    soloLock.unlock()
    tlog("display change, counts forgotten")
}

// Takes the settled state as the new baseline and lets the rule act again.
// Waking changes counts by itself: aerospace re-detects windows and re-runs
// on-window-detected, so a window ordered to float comes back floating and
// the tiled count drops. Read as a real change, that switched off the manual
// fullscreen the restore had just put back.
func soloBaselineAfterWake() {
    work.async {
        let s = soloSnapshot()
        guard !s.tiledIDs.isEmpty else { return }
        soloLock.lock()
        for (ws, ids) in s.tiledIDs { soloCount[ws] = ids.count }
        lastFullscreenIDs = s.fullscreenIDs
        // Forget who set what. Waking drops fullscreen without asking, so a
        // workspace that is solo and tiled now is a state nobody chose, and
        // the rule should assert it rather than read it as an override.
        // Overrides themselves are KEPT: a Super+F before the sleep is still
        // the user's decision afterwards.
        soloWeSet.removeAll()
        soloSettleUntil = .distantPast
        soloLock.unlock()
        tlog("settled after wake, baseline taken")
    }
}

// --- debounced triggers ---------------------------------------------------

var pendingRule: DispatchWorkItem?
// create and destroy: the same 0.15 s the bar's chip rebuild uses
func kickRule() {
    guard autoFullscreenSolo, !omniwmActive() else { return }
    pendingRule?.cancel()
    let w = DispatchWorkItem { work.async { applyAutoFullscreen(soloSnapshot()) } }
    pendingRule = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
}

var pendingRecheck: DispatchWorkItem?
// A window moving between floating and tiling changes the count without
// creating or destroying anything, and fires only MOVE and RESIZE. Longer
// than the rule debounce: dragging a window edge fires a stream of these and
// only the settled result is worth a subprocess.
func kickSoloRecheck() {
    guard autoFullscreenSolo, !omniwmActive() else { return }
    pendingRecheck?.cancel()
    let w = DispatchWorkItem { work.async { applyAutoFullscreen(soloSnapshot()) } }
    pendingRecheck = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
}

// --- sleep, wake and boot -------------------------------------------------
//
// The part a focus hook cannot reach, and the reason this is a resident
// process rather than a script on a hook.

var fullscreenAtSleep: [String] = []

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
) { _ in
    guard autoFullscreenSolo, !omniwmActive() else { return }
    // read, never asked: see lastFullscreenIDs
    soloLock.lock()
    fullscreenAtSleep = Array(lastFullscreenIDs)
    soloLock.unlock()
    tlog("sleeping, recorded \(fullscreenAtSleep.count) fullscreen window(s)")
}

// Waking is driven by aerospace's own detection, not a guessed delay. A wake
// re-detects every window in one burst about 10 ms wide and places each on
// the FOCUSED workspace before on-window-detected moves them back out. That
// is what drops fullscreen, and restoring while it happens achieves nothing.
var detectWatch: Process?
var detectBuffer = Data()
var wakeArmed = false
var detectQuiet: DispatchWorkItem?
var wakeFallback: DispatchWorkItem?
var bootArmed = false
var bootQuiet: DispatchWorkItem?
let bootGiveUp = Date().addingTimeInterval(90)

func startDetectWatch() {
    guard autoFullscreenSolo, !omniwmActive(), detectWatch == nil else { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: aerospaceBin)
    p.arguments = ["subscribe", "window-detected", "--no-send-initial"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else { return }
        DispatchQueue.main.async {
            detectBuffer.append(chunk)
            while let nl = detectBuffer.firstIndex(of: 0x0A) {
                detectBuffer = Data(detectBuffer[detectBuffer.index(after: nl)...])
                windowDetected()
                bootDetected()
            }
        }
    }
    p.terminationHandler = { proc in
        DispatchQueue.main.async {
            pipe.fileHandleForReading.readabilityHandler = nil
            guard detectWatch === proc else { return }
            detectWatch = nil
            guard autoFullscreenSolo, !omniwmActive() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { startDetectWatch() }
        }
    }
    guard (try? p.run()) != nil else { return }
    detectWatch = p
    tlog("watching window-detected")
}

// Every event pushes the settle point out, so the restore waits for the
// whole burst rather than a fixed number of seconds.
func windowDetected() {
    guard wakeArmed else { return }
    detectQuiet?.cancel()
    let w = DispatchWorkItem { finishWake("detection settled") }
    detectQuiet = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
}

func finishWake(_ why: String) {
    guard wakeArmed else { return }
    wakeArmed = false
    detectQuiet?.cancel(); detectQuiet = nil
    wakeFallback?.cancel(); wakeFallback = nil
    let ids = fullscreenAtSleep
    tlog("wake \(why), restoring \(ids.count) window(s)")
    // Two more passes after the first: the burst of app activations a few
    // seconds after a wake focuses another window in the workspace, and
    // aerospace leaves fullscreen when that happens.
    for delay in [0.0, 3.0, 8.0] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            work.async {
                for id in ids {
                    // tiling FIRST. A window can come back from a sleep
                    // floating, having lost its tiling as well as its
                    // fullscreen, and aerospace cannot fullscreen a floating
                    // window: it exits 0 and does nothing. Unconditional is
                    // safe, because only a tiled window can be fullscreen.
                    act(["layout", "tiling", "--window-id", id])
                    act(["fullscreen", "on", "--no-outer-gaps", "--window-id", id])
                }
            }
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 11.0) { soloBaselineAfterWake() }
}

// Boot looks like a wake from here: aerospace detects every window at once,
// and this process can be up and asking before aerospace answers at all. A
// single evaluation at startup then finds nothing, and with no further window
// event the feature stays dormant. There is nothing to RESTORE at boot, only
// to assert, which is why this is separate from the wake path.
func bootDetected() {
    guard bootArmed else { return }
    bootQuiet?.cancel()
    let w = DispatchWorkItem { finishBoot("detection settled") }
    bootQuiet = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
}

func finishBoot(_ why: String) {
    guard bootArmed else { return }
    bootQuiet?.cancel(); bootQuiet = nil
    work.async {
        let s = soloSnapshot()
        guard !s.tiledIDs.isEmpty else {
            // Disarms only once aerospace actually answers. A boot can start
            // this before the window manager is up, and firing into an empty
            // list would find nothing and disarm for good.
            DispatchQueue.main.async {
                guard bootArmed, Date() < bootGiveUp else {
                    if bootArmed {
                        bootArmed = false
                        soloLock.lock(); soloSettleUntil = .distantPast; soloLock.unlock()
                        tlog("boot gave up waiting for aerospace")
                    }
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    finishBoot("aerospace was not answering yet")
                }
            }
            return
        }
        DispatchQueue.main.async {
            guard bootArmed else { return }
            bootArmed = false
            soloLock.lock(); soloSettleUntil = .distantPast; soloLock.unlock()
            tlog("boot \(why), evaluating")
        }
        applyAutoFullscreen(s)
    }
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
) { _ in
    guard autoFullscreenSolo, !omniwmActive() else { return }
    // The counts are deliberately KEPT until the baseline runs. Clearing them
    // here would defeat the restore: the next window event would read a
    // changed count on a multi-window workspace and switch off the manual
    // Super+F just put back.
    soloLock.lock()
    soloSettleUntil = Date().addingTimeInterval(60) // the baseline clears it
    soloLock.unlock()
    wakeArmed = true
    detectQuiet?.cancel(); detectQuiet = nil
    // a shallow sleep re-detects nothing, so nothing would ever settle
    wakeFallback?.cancel()
    let fb = DispatchWorkItem { finishWake("no detection burst") }
    wakeFallback = fb
    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: fb)
    startDetectWatch() // in case the stream died while asleep
}

// a display arriving or leaving re-lays every workspace out, so the counts
// this last acted on mean nothing afterwards
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
) { _ in forgetSoloCounts() }

// --- entry ----------------------------------------------------------------

let pidPath = "/tmp/omacosy-solo-\(getuid()).pid"

if wantDaemon {
    // same shape as omacosy-overview: no launchd agent, killed by pidfile
    try? "\(getpid())".write(toFile: pidPath, atomically: true, encoding: .utf8)
}

guard autoFullscreenSolo else {
    tlog("solo=off in fullscreen.conf, nothing to do")
    exit(0)
}
guard !omniwmActive() else {
    tlog("OmniWM is running; its dwindle already fills a lone window")
    exit(0)
}

let notify: NotifyProc = { event, _, _, _ in
    DispatchQueue.main.async {
        if event == EVENT_WINDOW_CREATE || event == EVENT_WINDOW_DESTROY {
            kickRule()
            rebuildSubscriptions() // a new window is not subscribed until asked
        } else if event == EVENT_WINDOW_ORDER || event == EVENT_WINDOW_VISIBILITY {
            kickRule() // a window changed workspace: two counts moved
        } else {
            kickSoloRecheck() // MOVE and RESIZE: a float/tile toggle is only these
        }
    }
}
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_CREATE, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_DESTROY, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_MOVE, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_RESIZE, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_ORDER, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_VISIBILITY, nil)
rebuildSubscriptions()

// Evaluated once now, which is enough for a restart on a settled machine,
// and again once aerospace's detection burst goes quiet, which is what a
// real boot needs. Nothing is decided in between.
work.async { applyAutoFullscreen(soloSnapshot()) }
soloLock.lock()
soloSettleUntil = Date().addingTimeInterval(30) // finishBoot clears it
soloLock.unlock()
bootArmed = true
// a restart on a settled machine re-detects nothing, so nothing would settle
DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { finishBoot("no detection burst") }
startDetectWatch()

tlog("omacosy-solo up\(dryRun ? " (DRY RUN — nothing will be changed)" : "")")
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.run()
