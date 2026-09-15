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

struct CGWin { let id: Int; let pid: pid_t; let owner: String; let rect: CGRect }

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
        out.append(CGWin(id: w[kCGWindowNumber as String] as? Int ?? 0,
                         pid: pid_t(w[kCGWindowOwnerPID as String] as? Int ?? -1),
                         owner: w[kCGWindowOwnerName as String] as? String ?? "?",
                         rect: r))
    }
    return out
}

final class Win {
    var id: Int                     // stable window identity; 0 when unknown
    let app: String, title: String
    let el: AXUIElement?            // nil when planning from a recorded desktop
    let origin: CGPoint, size: CGSize
    var minSize: CGSize = .zero     // what the app will actually accept
    var packSize: CGSize = .zero    // what we plan against: minSize raised to a usable floor
    var prio = Priority()           // what the content is worth
    var placement: CGRect?
    var display: Int?
    var focused = false
    init(id: Int = 0, app: String, title: String, el: AXUIElement?,
         origin: CGPoint, size: CGSize) {
        self.id = id; self.app = app; self.title = title; self.el = el
        self.origin = origin; self.size = size
    }
}

// ---------- recorded desktops ----------

// Planning from a recording is the test seam: no Accessibility, no clock, no live
// windows. Anything that can be replayed can be asserted on, and any real desktop
// (including a bug report) becomes a permanent test case.

struct Fixture {
    let displays: [CGRect]
    let wins: [Win]
    let now: Date
}

func fixtureRect(_ any: Any?) -> CGRect {
    guard let r = any as? [String: Any] else { return .zero }
    return CGRect(x: r["x"] as? Double ?? 0, y: r["y"] as? Double ?? 0,
                  width: r["w"] as? Double ?? 0, height: r["h"] as? Double ?? 0)
}

func loadFixture(_ path: String) -> Fixture? {
    guard let d = FileManager.default.contents(atPath: path),
          let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }

    let displays = (j["displays"] as? [[String: Any]] ?? []).map { fixtureRect($0["usable"]) }
    var wins: [Win] = []
    for raw in j["windows"] as? [[String: Any]] ?? [] {
        let r = fixtureRect(raw["rect"])
        let w = Win(id: raw["id"] as? Int ?? 0,
                    app: raw["app"] as? String ?? "?",
                    title: raw["title"] as? String ?? "",
                    el: nil, origin: r.origin, size: r.size)
        w.minSize = fixtureRect(raw["minSize"]).size
        w.focused = raw["focused"] as? Bool ?? false
        wins.append(w)
    }
    let now = ISO8601DateFormatter().date(from: j["now"] as? String ?? "") ?? Date()
    return Fixture(displays: displays, wins: wins, now: now)
}

func planJSON(_ wins: [Win]) -> String {
    func r(_ x: CGRect) -> [String: Int] {
        ["x": Int(x.minX.rounded()), "y": Int(x.minY.rounded()),
         "w": Int(x.width.rounded()), "h": Int(x.height.rounded())]
    }
    let placements: [[String: Any]] = wins.compactMap { w in
        guard let p = w.placement else { return nil }
        return ["id": w.id, "app": w.app, "display": w.display ?? 0, "rect": r(p)]
    }
    let stowed: [[String: Any]] = wins.filter { $0.placement == nil }.map {
        ["id": $0.id, "app": $0.app]
    }
    let obj: [String: Any] = ["placements": placements, "stowed": stowed]
    let d = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    return String(data: d, encoding: .utf8)!
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
                  // CG carries the stable window id; AX does not expose one. Matching on
                  // pid plus geometry is how the two views are joined.
                  let cg = onScreen.first(where: {
                      $0.pid == pid && roughlyEqual($0.rect, CGRect(origin: p, size: s))
                  })
            else { continue }
            // Fullscreen windows refuse every write and report their own size as a
            // minimum. Including them poisons the minimum-size cache. See AGENTS.md.
            if axBool(w, "AXFullScreen") == true { continue }
            guard axSettable(w, kAXPositionAttribute as String),
                  axSettable(w, kAXSizeAttribute as String) else { continue }
            out.append(Win(id: cg.id,
                           app: app.localizedName ?? "?", title: axString(w, kAXTitleAttribute as String),
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
        if w.minSize != .zero { continue }          // recorded desktop already told us
        guard let el = w.el else { continue }
        if let c = cache[w.app], c.count == 2 { w.minSize = CGSize(width: c[0], height: c[1]); continue }
        setSize(el, CGSize(width: 1, height: 1))
        let got = axSize(el, kAXSizeAttribute as String) ?? w.size
        setSize(el, w.size)                         // restore
        setPos(el, w.origin)
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
func pack(_ wins: [Win], into area: CGRect) -> [Row]? {
    // Plan against USEFUL sizes, not technical minimums. A window that cannot be given
    // a useful size is stowed by the caller rather than shrunk - there is no cramped
    // fallback, because "present but unusable" is not a better outcome than "not here".
    // Where the technical minimum is larger than the useful size, physics wins.
    for w in wins {
        w.packSize = CGSize(width: max(w.minSize.width, w.prio.usefulSize.width),
                            height: max(w.minSize.height, w.prio.usefulSize.height))
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
let argv = Array(CommandLine.arguments.dropFirst())
let spill = args.contains("--spill")
let jsonOut = args.contains("--json")

// Planning from a recording must be physically incapable of touching a window.
let planFrom: String? = argv.firstIndex(of: "--plan-from").flatMap { i in
    i + 1 < argv.count ? argv[i + 1] : nil
}
let apply = args.contains("--apply") && planFrom == nil

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

guard planFrom != nil || AXIsProcessTrusted() else {
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
         "minimized": $0.el.flatMap { axBool($0, kAXMinimizedAttribute as String) } ?? false]
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
        guard let el = w.el else { continue }
        setSize(el, CGSize(width: ww, height: hh))
        setPos(el, CGPoint(x: x, y: y))
        setSize(el, CGSize(width: ww, height: hh))
        restored += 1
    }
    print("\(green)restored \(restored) windows\(off)")
    exit(0)
}

// Either replay a recording, or read the live desktop. Never both.
var fixture: Fixture? = nil
if let path = planFrom {
    guard let f = loadFixture(path) else {
        FileHandle.standardError.write("cannot read fixture: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    fixture = f
}

let displays = fixture?.displays ?? usableDisplays()
guard !displays.isEmpty else { print("no displays"); exit(1) }

if fixture == nil, args.contains("--unfullscreen") {
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

if fixture == nil {
    guard !missionControlActive(onScreenWindows(), displays) else {
        print("\(yellow)Mission Control is open.\(off) Window geometry is thumbnail data right now,")
        print("\(dim)not real frames - arranging from it would scatter every window.\(off)")
        print("\(dim)Press Escape and re-run.\(off)")
        exit(1)
    }
}

let wins = fixture?.wins ?? collectWindows(onScreenWindows())
guard !wins.isEmpty else {
    print("no windows on screen")
    print("\(dim)(if you are in a fullscreen app, re-run with --unfullscreen)\(off)")
    exit(0)
}

// Assign intent. The hero defaults to whatever you are actually in right now,
// which is the answer most of the time and costs no configuration.
// Planning from a recording must not read the user's config: a test that depends on
// whatever the operator last edited is not a test. Fixtures get the built-in defaults.
let priorities = fixture == nil ? loadPriorities() : defaultPriorities
var heroApp = fixture == nil ? NSWorkspace.shared.frontmostApplication?.localizedName
                             : wins.first(where: { $0.focused })?.app
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

if !jsonOut {
    print("")
    print("\(bold)ARRANGE\(off)  \(dim)\(wins.count) windows, \(displays.count) display\(displays.count == 1 ? "" : "s")" +
          "\(heroApp.map { ", hero: \($0)" } ?? "")\(off)")
}

let measured = measureMinimums(wins)
if !jsonOut {
    if measured > 0 { print("\(dim)  measured \(measured) new minimum size\(measured == 1 ? "" : "s") (cached)\(off)") }
    print("")
}

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

    var candidates = remaining
    var pushed: [Win] = []

    while !candidates.isEmpty {
        if let rows = pack(candidates, into: area) {
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

if jsonOut {
    print(planJSON(wins))
    exit(0)
}

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
        guard let el = w.el else { continue }
        setSize(el, p.size)
        setPos(el, p.origin)
        setSize(el, p.size)
    }
    // Windows with nowhere to go get minimized. Leaving them put would strand them
    // on top of the layout we just built - "cannot fit" has to actually mean something.
    var stowed = 0
    for w in unplaced {
        guard let el = w.el else { continue }
        if setBool(el, kAXMinimizedAttribute as String, true) { stowed += 1 }
    }
    print("  \(green)applied\(off)" + (stowed > 0 ? "\(dim), \(stowed) minimised\(off)" : ""))
} else if !apply {
    print("  \(dim)dry run - pass --apply to do it\(off)")
}
print("")
