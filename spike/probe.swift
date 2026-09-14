import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

// Compliance probe: can we ACTUALLY move and resize each window?
// Records original geometry, attempts a move + a deliberately-small resize,
// reads back what the app really did, then restores. Reports who lies.
//
//   ./wprobe --check   dry run - trust status + what it would touch, moves nothing
//   ./wprobe           the real thing - briefly shuffles every window, then restores

struct Target {
    let app: String
    let pid: pid_t
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

func collectTargets() -> [Target] {
    var out: [Target] = []
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &raw) == .success,
              let wins = raw as? [AXUIElement] else { continue }
        for w in wins {
            guard let pos = axPoint(w, kAXPositionAttribute as String),
                  let size = axSize(w, kAXSizeAttribute as String),
                  size.width >= 80, size.height >= 80 else { continue }
            out.append(Target(app: app.localizedName ?? "?", pid: pid, axWindow: w,
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

// ---------- dry run ----------

if args.contains("--check") {
    print("")
    print("\(bold)PRE-FLIGHT\(off)  \(dim)nothing will be moved\(off)")
    print("")
    print("  accessibility   \(trusted ? "\(green)granted\(off)" : "\(red)NOT granted\(off)")")
    print("  screen recording \(CGPreflightScreenCaptureAccess() ? "\(green)granted\(off)" : "\(red)NOT granted\(off)")  \(dim)(needed for window titles)\(off)")
    if trusted {
        let t = collectTargets()
        print("  reachable windows \(bold)\(t.count)\(off)")
        print("")
        for x in t { print("    \(dim)\(col(x.app, 22))\(col(x.title, 44))\(Int(x.size.width))x\(Int(x.size.height))\(off)") }
    } else {
        print("")
        print("  \(yellow)Grant Accessibility to this terminal:\(off)")
        print("  System Settings > Privacy & Security > Accessibility")
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

let targets = collectTargets()
print("")
print("\(bold)COMPLIANCE PROBE\(off)  \(dim)\(targets.count) windows - each moved, resized, then restored\(off)")
print("")
print("  \(dim)\(col("APP", 22))\(col("MOVE", 10))\(col("RESIZE", 12))NOTE\(off)")
print("  \(dim)\(String(repeating: "\u{2500}", count: 78))\(off)")

let probeSize = CGSize(width: 520, height: 380)
let probeOrigin = CGPoint(x: 120, y: 120)
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
