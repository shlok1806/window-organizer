import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

// Compliance probe: can we ACTUALLY move and resize each window?
// Records original geometry, attempts a move + a deliberately-small resize,
// reads back what the app really did, then restores. Reports who lies.
//
// Scoped to ONE screen (the one holding the frontmost window) and to windows
// CGWindowList agrees are on screen. AX alone reports windows resting on other
// Spaces; probing those would haul them into view. See AGENTS.md.
//
//   ./wprobe --check   dry run - permissions + what it would touch, moves nothing
//   ./wprobe           the real thing - briefly shuffles those windows, then restores

struct Target {
    let app: String
    let axWindow: AXUIElement
    let title: String
    let origin: CGPoint
    let size: CGSize
}

// Type-safe AX readers. Kept concrete rather than generic: handing a generic T
// to AXValueGetValue forms a raw pointer to something that may hold a reference.

func axPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &raw) == .success,
          let v = raw, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    guard AXValueGetValue(v as! AXValue, .cgPoint, &p) else { return nil }
    return p
}

func axSize(_ el: AXUIElement, _ attr: String) -> CGSize? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &raw) == .success,
          let v = raw, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    guard AXValueGetValue(v as! AXValue, .cgSize, &s) else { return nil }
    return s
}

func axString(_ el: AXUIElement, _ attr: String) -> String {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &raw) == .success else { return "" }
    return (raw as? String) ?? ""
}

func axBool(_ el: AXUIElement, _ attr: String) -> Bool? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &raw) == .success else { return nil }
    return (raw as? NSNumber)?.boolValue
}

/// Whether macOS will accept a write to this attribute at all. Definitive:
/// a fullscreen window reports position and size as read-only.
func axSettable(_ el: AXUIElement, _ attr: String) -> Bool {
    var settable: DarwinBoolean = false
    guard AXUIElementIsAttributeSettable(el, attr as CFString, &settable) == .success else { return false }
    return settable.boolValue
}

@discardableResult
func axSetPoint(_ el: AXUIElement, _ p: CGPoint) -> Bool {
    var v = p
    guard let val = AXValueCreate(.cgPoint, &v) else { return false }
    return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, val) == .success
}

@discardableResult
func axSetSize(_ el: AXUIElement, _ s: CGSize) -> Bool {
    var v = s
    guard let val = AXValueCreate(.cgSize, &v) else { return false }
    return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, val) == .success
}

// ---------- the on-screen truth ----------

struct CGWin { let pid: pid_t; let rect: CGRect }

/// What is genuinely on screen, front to back. CG knows this; AX does not.
func onScreenWindows(minSide: CGFloat = 80) -> [CGWin] {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    var out: [CGWin] = []
    for w in raw {
        guard (w[kCGWindowLayer as String] as? Int ?? -1) == 0,
              (w[kCGWindowAlpha as String] as? Double ?? 0) > 0.05,
              let bd = w[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bd),
              rect.width >= minSide, rect.height >= minSide else { continue }
        out.append(CGWin(pid: pid_t(w[kCGWindowOwnerPID as String] as? Int ?? -1), rect: rect))
    }
    return out
}

/// The display holding the frontmost on-screen window - "the monitor you're looking at".
func currentScreen(_ onScreen: [CGWin]) -> CGRect {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    let bounds = ids.map { CGDisplayBounds($0) }
    if let front = onScreen.first, let hit = bounds.first(where: { $0.intersects(front.rect) }) { return hit }
    return CGDisplayBounds(CGMainDisplayID())
}

func roughlyEqual(_ a: CGRect, _ b: CGRect, tol: CGFloat = 8) -> Bool {
    abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol &&
    abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
}

/// AX windows that CG confirms are on screen AND sit on the target display.
func collectTargets(onScreen: [CGWin], screen: CGRect) -> [Target] {
    var out: [Target] = []
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        let pid = app.processIdentifier
        guard onScreen.contains(where: { $0.pid == pid }) else { continue }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                                            kAXWindowsAttribute as CFString, &raw) == .success,
              let wins = raw as? [AXUIElement] else { continue }
        for w in wins {
            guard let pos = axPoint(w, kAXPositionAttribute as String),
                  let size = axSize(w, kAXSizeAttribute as String) else { continue }
            let rect = CGRect(origin: pos, size: size)
            guard screen.intersects(rect) else { continue }                       // this monitor only
            guard onScreen.contains(where: { $0.pid == pid && roughlyEqual($0.rect, rect) })
            else { continue }                                                     // CG must confirm it
            out.append(Target(app: app.localizedName ?? "?", axWindow: w,
                              title: axString(w, kAXTitleAttribute as String),
                              origin: pos, size: size))
        }
    }
    return out
}

func col(_ s: String, _ n: Int) -> String {
    (s as NSString).padding(toLength: n, withPad: " ", startingAt: 0)
}

let dim = "\u{1B}[2m", bold = "\u{1B}[1m", off = "\u{1B}[0m"
let red = "\u{1B}[31m", green = "\u{1B}[32m", yellow = "\u{1B}[33m"

let args = Set(CommandLine.arguments.dropFirst())
let trusted = AXIsProcessTrusted()
let onScreen = onScreenWindows()
let screen = currentScreen(onScreen)

// ---------- dry run ----------

if args.contains("--check") {
    print("")
    print("\(bold)PRE-FLIGHT\(off)  \(dim)nothing will be moved\(off)")
    print("")
    print("  accessibility    \(trusted ? "\(green)granted\(off)" : "\(red)NOT granted\(off)")")
    print("  screen recording \(CGPreflightScreenCaptureAccess() ? "\(green)granted\(off)" : "\(red)NOT granted\(off)")  \(dim)(window titles)\(off)")
    print("  target display   \(Int(screen.width))x\(Int(screen.height)) @\(Int(screen.minX)),\(Int(screen.minY))")
    if trusted {
        let t = collectTargets(onScreen: onScreen, screen: screen)
        print("  will touch       \(bold)\(t.count)\(off) windows \(dim)(of \(onScreen.count) on screen)\(off)")
        print("")
        print("    \(dim)\(col("APP", 20))\(col("POS", 8))\(col("SIZE", 8))\(col("FULLSCREEN", 12))\(col("FS-WRITABLE", 13))MINIMIZED\(off)")
        for x in t {
            let p = axSettable(x.axWindow, kAXPositionAttribute as String)
            let s = axSettable(x.axWindow, kAXSizeAttribute as String)
            let fs = axBool(x.axWindow, "AXFullScreen")
            let mn = axBool(x.axWindow, kAXMinimizedAttribute as String)
            func mark(_ b: Bool) -> String { b ? "\(green)yes\(off)     " : "\(red)NO\(off)      " }
            let fsw = axSettable(x.axWindow, "AXFullScreen")
            print("    \(col(x.app, 20))\(mark(p))\(mark(s))" +
                  "\(col(fs.map { $0 ? "YES" : "no" } ?? "?", 12))\(mark(fsw))   \(mn.map { $0 ? "yes" : "no" } ?? "?")")
        }
    } else {
        print("")
        print("  \(yellow)Grant Accessibility: System Settings > Privacy & Security > Accessibility\(off)")
    }
    print("")
    exit(0)
}

// ---------- real probe ----------

guard trusted else {
    print("\(red)Accessibility permission not granted.\(off) Run with --check for details.")
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
    exit(1)
}

let targets = collectTargets(onScreen: onScreen, screen: screen)
print("")
print("\(bold)COMPLIANCE PROBE\(off)  \(dim)\(targets.count) windows on the \(Int(screen.width))x\(Int(screen.height)) display - moved, resized, restored\(off)")
print("")
print("  \(dim)\(col("APP", 22))\(col("MOVE", 10))\(col("RESIZE", 12))NOTE\(off)")
print("  \(dim)\(String(repeating: "\u{2500}", count: 78))\(off)")

let probeSize = CGSize(width: 520, height: 380)
let probeOrigin = CGPoint(x: screen.minX + 120, y: screen.minY + 120)
var lies = 0

for t in targets {
    axSetPoint(t.axWindow, probeOrigin)
    let gotPos = axPoint(t.axWindow, kAXPositionAttribute as String) ?? .zero
    let moveOK = abs(gotPos.x - probeOrigin.x) < 6 && abs(gotPos.y - probeOrigin.y) < 6

    axSetSize(t.axWindow, probeSize)
    let gotSize = axSize(t.axWindow, kAXSizeAttribute as String) ?? .zero
    let resizeOK = abs(gotSize.width - probeSize.width) < 6 && abs(gotSize.height - probeSize.height) < 6

    axSetSize(t.axWindow, t.size)      // restore
    axSetPoint(t.axWindow, t.origin)

    var note = ""
    if !resizeOK { note = "min \(Int(gotSize.width))x\(Int(gotSize.height))"; lies += 1 }
    else if !moveOK { note = "landed \(Int(gotPos.x)),\(Int(gotPos.y))"; lies += 1 }

    let m = moveOK ? "\(green)ok\(off)     " : "\(red)CLAMPED\(off)"
    let r = resizeOK ? "\(green)ok\(off)          " : "\(red)CLAMPED\(off)     "
    print("  \(col(t.app, 22))\(m)  \(r)\(dim)\(note)\(off)")
}

print("")
print("  \(bold)\(targets.count - lies)/\(targets.count)\(off) windows fully obeyed. " +
      (lies > 0 ? "\(yellow)\(lies) fought back.\(off)" : "\(green)No resistance.\(off)"))
print("")
