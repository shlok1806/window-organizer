import Foundation
import CoreGraphics
import AppKit

// ---------- models ----------

struct Win {
    let z: Int              // 0 = frontmost
    let app: String
    let title: String?
    let pid: Int
    let rect: CGRect
    let screenIdx: Int?
}

struct ScreenInfo {
    let idx: Int
    let rect: CGRect        // top-left origin, matches CGWindowList coords
    let scale: CGFloat
}

// ---------- collection ----------

func activeScreens() -> [ScreenInfo] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return ids.enumerated().map { i, id in
        let nsScreen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }
        return ScreenInfo(idx: i, rect: CGDisplayBounds(id), scale: nsScreen?.backingScaleFactor ?? 1)
    }
}

/// Windows we care about: normal layer, visible, big enough to be a real window.
func visibleWindows(screens: [ScreenInfo], minSide: CGFloat = 80) -> [Win] {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }

    var out: [Win] = []
    for w in raw {
        let layer = w[kCGWindowLayer as String] as? Int ?? -1
        guard layer == 0 else { continue }                      // drop menubar, dock, overlays
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 0
        guard alpha > 0.05 else { continue }                    // drop invisible/ghost windows

        guard let bd = w[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bd) else { continue }
        guard rect.width >= minSide, rect.height >= minSide else { continue }

        let app = w[kCGWindowOwnerName as String] as? String ?? "?"
        var title = w[kCGWindowName as String] as? String
        if let t = title, t.isEmpty { title = nil }

        let screenIdx = screens.first { $0.rect.intersects(rect) }?.idx

        out.append(Win(z: out.count,
                       app: app,
                       title: title,
                       pid: w[kCGWindowOwnerPID as String] as? Int ?? -1,
                       rect: rect,
                       screenIdx: screenIdx))
    }
    return out
}

// ---------- mess metrics ----------

struct Mess {
    let screenIdx: Int
    let windows: Int
    let coveragePct: Double     // % of screen with >=1 window
    let deadSpacePct: Double    // % of screen showing desktop
    let overlapPct: Double      // % of screen where >=2 windows stack
    let wastedPct: Double       // hidden window pixels / total window pixels
    let occludedWindows: Int    // windows >50% buried
}

/// Grid rasterisation. Simple, obviously correct, plenty accurate at 8px cells.
func measure(_ wins: [Win], screen: ScreenInfo, cell: CGFloat = 8) -> Mess {
    let mine = wins.filter { $0.screenIdx == screen.idx }
    let cols = max(1, Int(screen.rect.width / cell))
    let rows = max(1, Int(screen.rect.height / cell))
    var depth = [Int](repeating: 0, count: cols * rows)

    func cells(_ r: CGRect, _ body: (Int) -> Void) {
        let clipped = r.intersection(screen.rect)
        guard !clipped.isNull, !clipped.isEmpty else { return }
        let x0 = max(0, Int((clipped.minX - screen.rect.minX) / cell))
        let x1 = min(cols - 1, Int((clipped.maxX - screen.rect.minX) / cell))
        let y0 = max(0, Int((clipped.minY - screen.rect.minY) / cell))
        let y1 = min(rows - 1, Int((clipped.maxY - screen.rect.minY) / cell))
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 { for x in x0...x1 { body(y * cols + x) } }
    }

    for w in mine { cells(w.rect) { depth[$0] += 1 } }

    let total = Double(cols * rows)
    let covered = depth.filter { $0 >= 1 }.count
    let stacked = depth.filter { $0 >= 2 }.count
    let windowCellSum = depth.reduce(0, +)
    let hiddenCells = windowCellSum - covered      // pixels paid for but not seen

    // per-window: how much of it is buried by windows above it
    var buried = 0
    for (i, w) in mine.enumerated() {
        guard i > 0 else { continue }
        var own = 0
        var aboveDepth = [Int: Int]()
        cells(w.rect) { own += 1; aboveDepth[$0] = 0 }
        for above in mine[0..<i] {
            cells(above.rect) { if aboveDepth[$0] != nil { aboveDepth[$0]! += 1 } }
        }
        let hid = aboveDepth.values.filter { $0 > 0 }.count
        if own > 0, Double(hid) / Double(own) > 0.5 { buried += 1 }
    }

    return Mess(screenIdx: screen.idx,
                windows: mine.count,
                coveragePct: Double(covered) / total * 100,
                deadSpacePct: (total - Double(covered)) / total * 100,
                overlapPct: Double(stacked) / total * 100,
                wastedPct: windowCellSum > 0 ? Double(hiddenCells) / Double(windowCellSum) * 100 : 0,
                occludedWindows: buried)
}

// ---------- output ----------

func jsonSample(_ wins: [Win], _ screens: [ScreenInfo], _ mess: [Mess], titlesOK: Bool) -> String {
    let fmt = ISO8601DateFormatter()
    func r(_ x: CGRect) -> [String: Int] {
        ["x": Int(x.minX), "y": Int(x.minY), "w": Int(x.width), "h": Int(x.height)]
    }
    let obj: [String: Any] = [
        "ts": fmt.string(from: Date()),
        "titles_readable": titlesOK,
        "frontmost": NSWorkspace.shared.frontmostApplication?.localizedName ?? NSNull(),
        "screens": screens.map { ["idx": $0.idx, "scale": $0.scale, "rect": r($0.rect)] },
        "windows": wins.map { w -> [String: Any] in
            ["z": w.z, "app": w.app, "title": w.title ?? NSNull(),
             "pid": w.pid, "screen": w.screenIdx ?? NSNull(), "rect": r(w.rect)]
        },
        "mess": mess.map {
            ["screen": $0.screenIdx, "windows": $0.windows,
             "coverage_pct": round($0.coveragePct * 10) / 10,
             "dead_space_pct": round($0.deadSpacePct * 10) / 10,
             "overlap_pct": round($0.overlapPct * 10) / 10,
             "wasted_pct": round($0.wastedPct * 10) / 10,
             "buried_windows": $0.occludedWindows]
        },
    ]
    let d = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    return String(data: d, encoding: .utf8)!
}

func pad(_ s: String, _ n: Int) -> String {
    let t = s.count > n ? String(s.prefix(n - 1)) + "\u{2026}" : s
    return t + String(repeating: " ", count: max(0, n - t.count))
}

func printHuman(_ wins: [Win], _ screens: [ScreenInfo], _ mess: [Mess], titlesOK: Bool) {
    let dim = "\u{1B}[2m", bold = "\u{1B}[1m", off = "\u{1B}[0m"
    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"

    print("")
    print("\(bold)WINDOW SNAPSHOT\(off)  \(dim)frontmost: \(front)\(off)")
    if !titlesOK {
        print("\u{1B}[33m  ! window titles unavailable - grant Screen Recording to this terminal\(off)")
    }
    print("")
    for s in screens {
        print("  \(dim)screen \(s.idx): \(Int(s.rect.width))x\(Int(s.rect.height)) @\(Int(s.scale))x\(off)")
    }
    print("")
    print("  \(dim)\(pad("Z", 4))\(pad("APP", 22))\(pad("TITLE", 46))\(pad("GEOMETRY", 22))SCR\(off)")
    print("  \(dim)\(String(repeating: "\u{2500}", count: 97))\(off)")
    for w in wins {
        let g = "\(Int(w.rect.width))x\(Int(w.rect.height)) @\(Int(w.rect.minX)),\(Int(w.rect.minY))"
        let titleCell = pad(w.title ?? "\u{2014}", 46)
        print("  \(pad(String(w.z), 4))\(pad(w.app, 22))\(titleCell)\(pad(g, 22))\(w.screenIdx.map(String.init) ?? "-")")
    }
    print("")
    for m in mess {
        print("  \(bold)MESS \u{00B7} screen \(m.screenIdx)\(off)  \(m.windows) windows")
        print("    screen covered      \(String(format: "%5.1f%%", m.coveragePct))")
        print("    desktop showing     \(String(format: "%5.1f%%", m.deadSpacePct))")
        print("    stacked (2+ deep)   \(String(format: "%5.1f%%", m.overlapPct))")
        print("    window px hidden    \(String(format: "%5.1f%%", m.wastedPct))   \(dim)<- the actual waste\(off)")
        print("    windows >50% buried \(m.occludedWindows)")
        print("")
    }
}

// ---------- main ----------

let args = Set(CommandLine.arguments.dropFirst())
let titlesOK = CGPreflightScreenCaptureAccess()
let screens = activeScreens()
let wins = visibleWindows(screens: screens)
let mess = screens.map { measure(wins, screen: $0) }

if args.contains("--json") {
    print(jsonSample(wins, screens, mess, titlesOK: titlesOK))
} else {
    printHuman(wins, screens, mess, titlesOK: titlesOK)
}

if args.contains("--log") {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".window-spike")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let f = dir.appendingPathComponent("samples.jsonl")
    let line = jsonSample(wins, screens, mess, titlesOK: titlesOK) + "\n"
    if let h = try? FileHandle(forWritingTo: f) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: f, atomically: true, encoding: .utf8)
    }
    FileHandle.standardError.write("logged -> \(f.path)\n".data(using: .utf8)!)
}
