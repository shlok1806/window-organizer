import Foundation
import CoreGraphics

// Focus recorder. Samples the frontmost window on an interval and appends it to the
// focus log, which the layout engine reads to decide what you actually use.
//
// Deliberately needs NO permissions. Window ids and z-order come from CGWindowList,
// which is readable without Accessibility or Screen Recording, and the log stores only
// an id and a timestamp - never a title, never content. A record of what you look at
// all day deserves to be as thin as it can possibly be.
//
//   wfocus --once     take a single sample and exit
//   wfocus            sample every 5 seconds until killed
//   wfocus --status   how many events are recorded, and the newest

let args = Set(CommandLine.arguments.dropFirst())
let interval: TimeInterval = 5

/// Topmost normal window. CGWindowList returns on-screen windows front to back, so
/// the first real one is what the user is looking at.
func frontmostWindowID() -> Int? {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in raw {
        guard (w[kCGWindowLayer as String] as? Int ?? -1) == 0,
              (w[kCGWindowAlpha as String] as? Double ?? 0) > 0.05,
              let bd = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: bd),
              r.width >= 80, r.height >= 80 else { continue }
        return w[kCGWindowNumber as String] as? Int
    }
    return nil
}

if args.contains("--status") {
    let events = loadFocusLog()
    print("focus log: \(focusLogURL.path)")
    print("events:    \(events.count)")
    if let newest = events.last {
        let age = Int(Date().timeIntervalSince(newest.at))
        print("newest:    window \(newest.id), \(age)s ago")
    } else {
        print("newest:    none - recorder is not running, layout falls back to priority alone")
    }
    exit(0)
}

// Only record when the frontmost window actually changes. Sampling every tick would
// bury a brief visit under a long idle one and make the log mostly noise.
var last: Int? = nil
repeat {
    if let id = frontmostWindowID(), id != last {
        appendFocusEvent(id)
        last = id
    }
    if args.contains("--once") { break }
    Thread.sleep(forTimeInterval: interval)
} while true
