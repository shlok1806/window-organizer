import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

// Layout engine: surface every hidden window by packing them all with zero overlap.
//
// Honours per-app minimum sizes, which macOS will not report - they have to be
// measured by asking for a 1x1 window and reading back what you are given. Results
// are cached to disk so the measuring flicker happens once per app. See AGENTS.md.
//
//   ./warrange           dry run - the plan and whether it is even possible
//   ./warrange --apply   do it
//   ./warrange --spill   allow overflow onto other displays when one cannot hold them

let GAP: CGFloat = 8

// ---------- AX plumbing ----------

func axPoint(_ el: AXUIElement, _ a: String) -> CGPoint? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, a as CFString, &raw) == .success,
          let v = raw, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    guard AXValueGetValue(v as! AXValue, .cgPoint, &p) else { return nil }
    return p
}

func axSize(_ el: AXUIElement, _ a: String) -> CGSize? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, a as CFString, &raw) == .success,
          let v = raw, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    guard AXValueGetValue(v as! AXValue, .cgSize, &s) else { return nil }
    return s
}

func axBool(_ el: AXUIElement, _ a: String) -> Bool? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, a as CFString, &raw) == .success else { return nil }
    return (raw as? NSNumber)?.boolValue
}

func axSettable(_ el: AXUIElement, _ a: String) -> Bool {
    var s: DarwinBoolean = false
    guard AXUIElementIsAttributeSettable(el, a as CFString, &s) == .success else { return false }
    return s.boolValue
}

func axString(_ el: AXUIElement, _ a: String) -> String {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, a as CFString, &raw) == .success else { return "" }
    return (raw as? String) ?? ""
}

@discardableResult func setPos(_ el: AXUIElement, _ p: CGPoint) -> Bool {
    var v = p
    guard let val = AXValueCreate(.cgPoint, &v) else { return false }
    return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, val) == .success
}

@discardableResult func setBool(_ el: AXUIElement, _ a: String, _ v: Bool) -> Bool {
    AXUIElementSetAttributeValue(el, a as CFString, (v ? kCFBooleanTrue : kCFBooleanFalse)!) == .success
}

/// Pull every fullscreen window back into the desktop Space so it can be arranged.
/// A fullscreen app is unreachable - own Space, position writes refused - so an
/// organizer that merely skips them cannot organize the app you are actually using.
func exitFullscreenEverywhere() -> Int {
    var n = 0
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                            kAXWindowsAttribute as CFString, &raw) == .success,
              let wins = raw as? [AXUIElement] else { continue }
        for w in wins where axBool(w, "AXFullScreen") == true {
            if setBool(w, "AXFullScreen", false) { n += 1 }
        }
    }
    return n
}

@discardableResult func setSize(_ el: AXUIElement, _ s: CGSize) -> Bool {
    var v = s
    guard let val = AXValueCreate(.cgSize, &v) else { return false }
    return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, val) == .success
}

// ---------- what is genuinely on screen ----------

struct CGWin { let pid: pid_t; let owner: String; let rect: CGRect }

/// Mission Control and App Exposé are drawn by the Dock process as a full-screen
/// layer-0 window, and while either is up CGWindowList reports THUMBNAIL geometry
/// for every window - scaled-down previews that will never match AX's real frames.
/// Arranging from that data would fling every window into preview-sized rectangles.
func missionControlActive(_ onScreen: [CGWin], _ displays: [CGRect]) -> Bool {
    onScreen.contains { w in
        w.owner == "Dock" && displays.contains { d in
            w.rect.width >= d.width * 0.95 && w.rect.height >= d.height * 0.95
        }
    }
}

func onScreenWindows(minSide: CGFloat = 80) -> [CGWin] {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    var out: [CGWin] = []
    for w in raw {
        guard (w[kCGWindowLayer as String] as? Int ?? -1) == 0,
              (w[kCGWindowAlpha as String] as? Double ?? 0) > 0.05,
              let bd = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: bd),
              r.width >= minSide, r.height >= minSide else { continue }
        out.append(CGWin(pid: pid_t(w[kCGWindowOwnerPID as String] as? Int ?? -1),
                         owner: w[kCGWindowOwnerName as String] as? String ?? "?",
                         rect: r))
    }
    return out
}

final class Win {
    let app: String, title: String, el: AXUIElement
    let origin: CGPoint, size: CGSize
    var minSize: CGSize = .zero     // what the app will actually accept
    var packSize: CGSize = .zero    // what we plan against: minSize raised to a usable floor
    var prio = Priority()           // what the content is worth
    var placement: CGRect?
    var display: Int?
    init(app: String, title: String, el: AXUIElement, origin: CGPoint, size: CGSize) {
        self.app = app; self.title = title; self.el = el; self.origin = origin; self.size = size
    }
}

func roughlyEqual(_ a: CGRect, _ b: CGRect, tol: CGFloat = 8) -> Bool {
    abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol &&
    abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
}

/// AX windows that CG confirms are on screen. Never trust AX alone: it also
/// returns windows resting on other Spaces, which must not be hauled into view.
func collectWindows(_ onScreen: [CGWin]) -> [Win] {
    var out: [Win] = []
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        let pid = app.processIdentifier
        guard onScreen.contains(where: { $0.pid == pid }) else { continue }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                                            kAXWindowsAttribute as CFString, &raw) == .success,
              let wins = raw as? [AXUIElement] else { continue }
        for w in wins {
            guard let p = axPoint(w, kAXPositionAttribute as String),
                  let s = axSize(w, kAXSizeAttribute as String),
                  onScreen.contains(where: { $0.pid == pid && roughlyEqual($0.rect, CGRect(origin: p, size: s)) })
            else { continue }
            // Fullscreen windows refuse every write and report their own size as a
            // minimum. Including them poisons the minimum-size cache. See AGENTS.md.
            if axBool(w, "AXFullScreen") == true { continue }
            guard axSettable(w, kAXPositionAttribute as String),
                  axSettable(w, kAXSizeAttribute as String) else { continue }
            out.append(Win(app: app.localizedName ?? "?", title: axString(w, kAXTitleAttribute as String),
                           el: w, origin: p, size: s))
        }
    }
    return out
}

// ---------- minimum sizes: measure once, cache forever ----------

let cacheURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".window-spike/minsizes.json")

func loadCache() -> [String: [CGFloat]] {
    guard let d = try? Data(contentsOf: cacheURL),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: [CGFloat]] else { return [:] }
    return j
}

func saveCache(_ c: [String: [CGFloat]]) {
    try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    if let d = try? JSONSerialization.data(withJSONObject: c, options: [.prettyPrinted, .sortedKeys]) {
        try? d.write(to: cacheURL)
    }
}

/// There is no minimum-size attribute in AX. Ask for 1x1 and read back the refusal.
func measureMinimums(_ wins: [Win]) -> Int {
    var cache = loadCache()
    var measured = 0
    for w in wins {
        if let c = cache[w.app], c.count == 2 { w.minSize = CGSize(width: c[0], height: c[1]); continue }
        setSize(w.el, CGSize(width: 1, height: 1))
        let got = axSize(w.el, kAXSizeAttribute as String) ?? w.size
        setSize(w.el, w.size)                       // restore
        setPos(w.el, w.origin)
        w.minSize = got
        // A window that came back exactly its original size did not shrink at all -
        // that is a refusal, not a minimum. Caching it would claim the app needs a
        // whole display forever. Use it for this run only.
        if got.width < w.size.width || got.height < w.size.height {
            cache[w.app] = [got.width, got.height]
            measured += 1
        }
    }
    if measured > 0 { saveCache(cache) }
    return measured
}

// ---------- displays ----------

/// Usable area per display in CG (top-left origin) coordinates, menu bar and Dock excluded.
func usableDisplays() -> [CGRect] {
    guard let primary = NSScreen.screens.first else { return [] }
    let flipH = primary.frame.height
    return NSScreen.screens.map { s in
        let vf = s.visibleFrame
        return CGRect(x: vf.minX, y: flipH - vf.maxY, width: vf.width, height: vf.height)
    }
}

// ---------- packing ----------

struct Row { var items: [Win]; var minHeight: CGFloat }

/// Shelf packing. Returns nil when the windows cannot fit without overlap -
/// which is a real outcome, not an error.
///
/// `comfort` raises every window's planning size to a usable floor before packing.
/// Without it a terminal (true minimum 24x29) reads as costless, so the packer crams
/// four windows into one row and hands the terminals 140px. Feasibility is still
/// decided by real minimums: if the comfortable pass fails, the caller retries without it.
func pack(_ wins: [Win], into area: CGRect, comfort: Bool) -> [Row]? {
    // Even the cramped fallback keeps a hard floor. Falling back to raw minimums lets
    // a terminal (true minimum 24px) be handed 72px - present on screen, useless to a
    // human. Below the floor the right answer is to evict a window, not to shrink one.
    let floorW = comfort ? min(460, area.width / 3) : min(260, area.width)
    let floorH = comfort ? min(300, area.height / 3) : min(200, area.height)
    for w in wins {
        w.packSize = CGSize(width: max(w.minSize.width, floorW),
                            height: max(w.minSize.height, floorH))
    }

    // Highest priority first, so the hero lands in the top row rather than wherever
    // its pixel height happens to sort it.
    let sorted = wins.sorted {
        $0.prio.rank != $1.prio.rank ? $0.prio.rank < $1.prio.rank
                                     : $0.packSize.height > $1.packSize.height
    }
    var rows: [Row] = []
    var cur: [Win] = []
    var curW: CGFloat = 0

    for w in sorted {
        if w.packSize.width > area.width { return nil }         // wider than the display
        let need = w.packSize.width + (cur.isEmpty ? 0 : GAP)
        if curW + need <= area.width {
            cur.append(w); curW += need
        } else {
            rows.append(Row(items: cur, minHeight: cur.map { $0.packSize.height }.max()!))
            cur = [w]; curW = w.packSize.width
        }
    }
    if !cur.isEmpty { rows.append(Row(items: cur, minHeight: cur.map { $0.packSize.height }.max()!)) }

    let needed = rows.map(\.minHeight).reduce(0, +) + GAP * CGFloat(max(0, rows.count - 1))
    return needed <= area.height ? rows : nil
}

/// Turn packed rows into concrete frames, spending leftover space by priority weight
/// rather than by current size, and honouring each app's cap. Space freed by a capped
/// window flows back to windows that can still use it.
func layout(_ rows: [Row], in area: CGRect, display: Int) {
    let baseH = rows.map(\.minHeight)
    let rowWeight = rows.map { r in r.items.map { $0.prio.weight }.max() ?? 1 }
    // A row only stops growing when every window in it is capped.
    let rowCap: [CGFloat?] = rows.map { r in
        let caps = r.items.compactMap { $0.prio.maxSize?.height }
        return caps.count == r.items.count ? caps.max() : nil
    }
    let poolH = max(0, area.height - baseH.reduce(0, +) - GAP * CGFloat(max(0, rows.count - 1)))
    let heights = waterfill(base: baseH, weight: rowWeight, cap: rowCap, pool: poolH)

    var y = area.minY
    for (ri, row) in rows.enumerated() {
        let baseW = row.items.map { $0.packSize.width }
        let poolW = max(0, area.width - baseW.reduce(0, +) - GAP * CGFloat(max(0, row.items.count - 1)))
        let widths = waterfill(base: baseW,
                               weight: row.items.map { $0.prio.weight },
                               cap: row.items.map { $0.prio.maxSize?.width },
                               pool: poolW)
        var x = area.minX
        for (ci, w) in row.items.enumerated() {
            let h = min(heights[ri], w.prio.maxSize?.height ?? heights[ri])
            w.placement = CGRect(x: x, y: y, width: widths[ci], height: h)
            w.display = display
            x += widths[ci] + GAP
        }
        y += heights[ri] + GAP
    }
}

// ---------- output ----------

let dim = "\u{1B}[2m", bold = "\u{1B}[1m", off = "\u{1B}[0m"
let red = "\u{1B}[31m", green = "\u{1B}[32m", yellow = "\u{1B}[33m"
func col(_ s: String, _ n: Int) -> String { (s as NSString).padding(toLength: n, withPad: " ", startingAt: 0) }

let args = Set(CommandLine.arguments.dropFirst())
let apply = args.contains("--apply")
let spill = args.contains("--spill")

if args.contains("--help") || args.contains("-h") {
    print("""

    \(bold)warrange\(off) - pack every visible window with zero overlap

      \(dim)no flags\(off)           dry run: print the plan, change nothing
      \(bold)--apply\(off)            do it
      \(bold)--undo\(off)             put everything back where it was, un-minimising as needed

      \(bold)--master\(off) [frac]    give the hero a slab of the display (default 0.6)
      \(bold)--hero\(off) <app>       who gets it (default: the app you are in)
      \(bold)--spill\(off)            use other displays when one cannot hold everything
      \(bold)--unfullscreen\(off)     reclaim fullscreen apps into the desktop first

    Windows that cannot fit are minimised. Per-app priorities live in
    \(dim)~/.window-spike/priorities.json\(off) - edit it, it is yours.

    """)
    exit(0)
}

guard AXIsProcessTrusted() else {
    print("\(red)Accessibility not granted.\(off) System Settings > Privacy & Security > Accessibility")
    exit(1)
}

// ---------- undo ----------

let undoURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".window-spike/undo.json")

func saveUndo(_ wins: [Win]) {
    let arr: [[String: Any]] = wins.map {
        ["app": $0.app, "title": $0.title,
         "x": Double($0.origin.x), "y": Double($0.origin.y),
         "w": Double($0.size.width), "h": Double($0.size.height),
         "minimized": axBool($0.el, kAXMinimizedAttribute as String) ?? false]
    }
    try? FileManager.default.createDirectory(at: undoURL.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    if let d = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) {
        try? d.write(to: undoURL)
    }
}

if args.contains("--undo") {
    guard let d = try? Data(contentsOf: undoURL),
          let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else {
        print("\(yellow)nothing to undo\(off)"); exit(0)
    }
    var restored = 0
    // Un-minimize first: a minimized window ignores geometry writes.
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                            kAXWindowsAttribute as CFString, &raw) == .success,
              let ws = raw as? [AXUIElement] else { continue }
        for w in ws where axBool(w, kAXMinimizedAttribute as String) == true {
            let title = axString(w, kAXTitleAttribute as String)
            if let e = arr.first(where: { $0["app"] as? String == app.localizedName
                                       && $0["title"] as? String == title }),
               (e["minimized"] as? Bool) == false {
                setBool(w, kAXMinimizedAttribute as String, false)
            }
        }
    }
    Thread.sleep(forTimeInterval: 0.4)

    for w in collectWindows(onScreenWindows()) {
        guard let e = arr.first(where: { $0["app"] as? String == w.app && $0["title"] as? String == w.title }),
              let x = e["x"] as? Double, let y = e["y"] as? Double,
              let ww = e["w"] as? Double, let hh = e["h"] as? Double else { continue }
        setSize(w.el, CGSize(width: ww, height: hh))
        setPos(w.el, CGPoint(x: x, y: y))
        setSize(w.el, CGSize(width: ww, height: hh))
        restored += 1
    }
    print("\(green)restored \(restored) windows\(off)")
    exit(0)
}

let displays = usableDisplays()
guard !displays.isEmpty else { print("no displays"); exit(1) }

if args.contains("--unfullscreen") {
    let n = exitFullscreenEverywhere()
    if n > 0 {
        print("  \(dim)reclaimed \(n) fullscreen window\(n == 1 ? "" : "s") - waiting for the Space to settle\(off)")
        // The Space change is animated and its duration is not ours to predict, so
        // poll for the desktop to actually arrive rather than sleeping a guess.
        var settled = 0
        for _ in 0..<16 {
            Thread.sleep(forTimeInterval: 0.35)
            let n = collectWindows(onScreenWindows()).count
            if n > 1 && n == settled { break }      // two identical reads: stable
            settled = n
        }
    }
}

guard !missionControlActive(onScreenWindows(), displays) else {
    print("\(yellow)Mission Control is open.\(off) Window geometry is thumbnail data right now,")
    print("\(dim)not real frames - arranging from it would scatter every window.\(off)")
    print("\(dim)Press Escape and re-run.\(off)")
    exit(1)
}

let wins = collectWindows(onScreenWindows())
guard !wins.isEmpty else {
    print("no windows on screen")
    print("\(dim)(if you are in a fullscreen app, re-run with --unfullscreen)\(off)")
    exit(0)
}

// Assign intent. The hero defaults to whatever you are actually in right now,
// which is the answer most of the time and costs no configuration.
let priorities = loadPriorities()
let argv = Array(CommandLine.arguments.dropFirst())
var heroApp = NSWorkspace.shared.frontmostApplication?.localizedName
if let i = argv.firstIndex(of: "--hero"), i + 1 < argv.count { heroApp = argv[i + 1] }

for w in wins {
    w.prio = priorities[w.app] ?? Priority()
    // A config tier of "hero" is an appetite hint (keep its weight), not a claim on
    // THE hero slot - otherwise every terminal is a hero and the word means nothing.
    if w.prio.tier == "hero" { w.prio.tier = "normal" }
}
// Exactly one hero: the single window you are actually in.
if let hero = wins.first(where: { $0.app == heroApp }) {
    hero.prio.tier = "hero"
    hero.prio.weight = max(hero.prio.weight, 3.0)
    hero.prio.maxSize = nil                     // the hero is never capped
}

print("")
print("\(bold)ARRANGE\(off)  \(dim)\(wins.count) windows, \(displays.count) display\(displays.count == 1 ? "" : "s")" +
      "\(heroApp.map { ", hero: \($0)" } ?? "")\(off)")

let measured = measureMinimums(wins)
if measured > 0 { print("\(dim)  measured \(measured) new minimum size\(measured == 1 ? "" : "s") (cached)\(off)") }
print("")

// Fit onto display 0; spill the tallest windows onward only when asked.
var remaining = wins
var placedAnywhere = false
var areas = displays

// Master pane: the hero takes a fixed slab of the primary display and everything
// else packs into what is left. Weights alone cannot express dominance - when a row
// is mostly minimum widths there is no leftover pool to weight, so the "hero" ends up
// the same size as everything else. A reserved slab is the only reliable way.
if let fracArg = argv.firstIndex(of: "--master").map({ i -> CGFloat in
        i + 1 < argv.count ? (CGFloat(Double(argv[i + 1]) ?? 0.6)) : 0.6
   }),
   let hero = wins.first(where: { $0.prio.tier == "hero" }), !areas.isEmpty {
    let frac = min(0.85, max(0.3, fracArg))
    let area = areas[0]
    let masterW = area.width * frac - GAP / 2

    hero.placement = CGRect(x: area.minX, y: area.minY,
                            width: min(masterW, hero.prio.maxSize?.width ?? masterW),
                            height: min(area.height, hero.prio.maxSize?.height ?? area.height))
    hero.display = 0
    placedAnywhere = true

    let stackX = area.minX + masterW + GAP
    areas[0] = CGRect(x: stackX, y: area.minY, width: area.maxX - stackX, height: area.height)
    remaining = wins.filter { $0 !== hero }
}

// Fill each display comfortably, pushing whatever will not fit onto the next one.
// Cramped packing is a last resort, used only on the final display - otherwise a
// display "succeeds" by squashing everything and nothing ever spills.
for (i, area) in areas.enumerated() {
    if remaining.isEmpty { break }
    if i > 0 && !spill { break }
    let isLastChance = !spill || i == areas.count - 1

    var candidates = remaining
    var pushed: [Win] = []

    while !candidates.isEmpty {
        var rows = pack(candidates, into: area, comfort: true)
        if rows == nil && isLastChance { rows = pack(candidates, into: area, comfort: false) }
        if let rows {
            layout(rows, in: area, display: i)
            placedAnywhere = true
            break
        }
        // Too much for this display: move the LEAST important window onward, not the
        // biggest. Banished apps leave first; the hero is the last thing to go.
        let victim = candidates.max {
            $0.prio.rank != $1.prio.rank ? $0.prio.rank < $1.prio.rank
                : $0.minSize.width * $0.minSize.height < $1.minSize.width * $1.minSize.height
        }!
        candidates.removeAll { $0 === victim }
        pushed.append(victim)
    }
    remaining = pushed
}

let unplaced = wins.filter { $0.placement == nil }

print("  \(dim)\(col("APP", 20))\(col("TIER", 9))\(col("MINIMUM", 11))\(col("PLANNED", 22))DISPLAY\(off)")
print("  \(dim)\(String(repeating: "\u{2500}", count: 74))\(off)")
for w in wins.sorted(by: { $0.prio.rank < $1.prio.rank }) {
    let mn = "\(Int(w.minSize.width))x\(Int(w.minSize.height))"
    let tierColor = w.prio.tier == "hero" ? green : (w.prio.tier == "banish" ? dim : "")
    let tier = "\(tierColor)\(col(w.prio.tier, 9))\(off)"
    if let p = w.placement {
        let g = "\(Int(p.width))x\(Int(p.height)) @\(Int(p.minX)),\(Int(p.minY))"
        print("  \(col(w.app, 20))\(tier)\(col(mn, 11))\(col(g, 22))\(green)\(w.display!)\(off)")
    } else {
        print("  \(col(w.app, 20))\(tier)\(col(mn, 11))\(col("-", 22))\(red)cannot fit\(off)")
    }
}
print("")

if !unplaced.isEmpty {
    print("  \(yellow)\(unplaced.count) window\(unplaced.count == 1 ? "" : "s") cannot fit without overlap on this display.\(off)")
    let total = wins.map { $0.minSize.height }.reduce(0, +)
    print("  \(dim)stacked minimum heights: \(Int(total))px vs \(Int(displays[0].height))px usable\(off)")
    if !spill && displays.count > 1 {
        print("  \(dim)re-run with --spill to use the other display\(off)")
    }
    print("")
}

if apply && placedAnywhere {
    saveUndo(wins)
    for w in wins {
        guard let p = w.placement else { continue }
        // size, position, size again: some apps re-clamp after a move
        setSize(w.el, p.size)
        setPos(w.el, p.origin)
        setSize(w.el, p.size)
    }
    // Windows with nowhere to go get minimized. Leaving them put would strand them
    // on top of the layout we just built - "cannot fit" has to actually mean something.
    var stowed = 0
    for w in unplaced where setBool(w.el, kAXMinimizedAttribute as String, true) { stowed += 1 }
    print("  \(green)applied\(off)" + (stowed > 0 ? "\(dim), \(stowed) minimised\(off)" : ""))
} else if !apply {
    print("  \(dim)dry run - pass --apply to do it\(off)")
}
print("")
