import Foundation
import CoreGraphics

// Per-app layout intent. The layout engine knows geometry; this file knows what
// content is worth. Without it, leftover space gets shared by current window size,
// which hands a music player a 1920x1080 display and a terminal 138px.
//
// Tiers:
//   hero    the thing you are actually doing - takes the dominant slot
//   normal  real work, grows with available space
//   minor   useful but reference-only - capped so it stops stealing space
//   banish  noise - sent to a secondary display, or shrunk to its cap
//
// Written to ~/.window-spike/priorities.json on first run. Edit it; it is yours.

struct Priority {
    var tier: String = "normal"
    var weight: CGFloat = 1
    var maxSize: CGSize? = nil

    /// The size below which this window is worthless to a human. Distinct from the
    /// technical minimum, which is what the app will merely *accept*: a browser will
    /// happily accept 574x220 and show you three lines of text. Policy, not physics -
    /// where the technical minimum is larger, physics wins.
    var usefulSize = CGSize(width: 480, height: 360)

    var rank: Int {
        switch tier {
        case "hero": return 0
        case "normal": return 1
        case "minor": return 2
        default: return 3
        }
    }
}

/// Sensible starting points by app category. Terminals and editors want width for
/// code; readers want a comfortable column, not the whole screen; chat and media
/// want to be small and out of the way.
/// Both dimensions are required deliberately. A default height let minor-tier apps be
/// capped in width only, so "minor tier is capped so it stops stealing space" was half
/// true - spill one onto its own display and it took the full height. See issue #12.
private func cap(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
private func useful(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }

let defaultPriorities: [String: Priority] = [
    // make things - hero. Code needs width for long lines and height for context.
    "WezTerm":           Priority(tier: "hero", weight: 3.0, usefulSize: useful(640, 400)),
    "iTerm2":            Priority(tier: "hero", weight: 3.0, usefulSize: useful(640, 400)),
    "Terminal":          Priority(tier: "hero", weight: 3.0, usefulSize: useful(640, 400)),
    "Ghostty":           Priority(tier: "hero", weight: 3.0, usefulSize: useful(640, 400)),
    "Alacritty":         Priority(tier: "hero", weight: 3.0, usefulSize: useful(640, 400)),
    "Code":              Priority(tier: "hero", weight: 3.0, usefulSize: useful(800, 500)),
    "Cursor":            Priority(tier: "hero", weight: 3.0, usefulSize: useful(800, 500)),
    "Xcode":             Priority(tier: "hero", weight: 3.0, usefulSize: useful(900, 600)),

    // read things - a page needs a readable column AND enough height to be a page
    "Safari":            Priority(tier: "normal", weight: 2.0, maxSize: cap(1200, 2000), usefulSize: useful(900, 600)),
    "Google Chrome":     Priority(tier: "normal", weight: 2.0, maxSize: cap(1200, 2000), usefulSize: useful(900, 600)),
    "Arc":               Priority(tier: "normal", weight: 2.0, maxSize: cap(1200, 2000), usefulSize: useful(900, 600)),
    "Firefox":           Priority(tier: "normal", weight: 2.0, maxSize: cap(1200, 2000), usefulSize: useful(900, 600)),
    "Preview":           Priority(tier: "normal", weight: 1.5, maxSize: cap(1000, 2000), usefulSize: useful(700, 600)),

    // talk to people - a list plus a reading pane needs real width
    "Microsoft Outlook": Priority(tier: "normal", weight: 1.4, maxSize: cap(1300, 2000), usefulSize: useful(900, 600)),
    "Mail":              Priority(tier: "normal", weight: 1.4, maxSize: cap(1100, 2000), usefulSize: useful(800, 600)),
    "Slack":             Priority(tier: "minor",  weight: 1.0, maxSize: cap(820, 1100),  usefulSize: useful(600, 500)),
    "Messages":          Priority(tier: "minor",  weight: 0.7, maxSize: cap(560, 1100),  usefulSize: useful(400, 500)),
    "Discord":           Priority(tier: "minor",  weight: 0.8, maxSize: cap(900, 1100),  usefulSize: useful(600, 500)),

    // look things up - small is fine, these are glanced at
    "Finder":            Priority(tier: "minor", weight: 0.8, maxSize: cap(760, 560), usefulSize: useful(520, 360)),
    "System Settings":   Priority(tier: "minor", weight: 0.6, maxSize: cap(800, 620), usefulSize: useful(600, 450)),
    "Activity Monitor":  Priority(tier: "minor", weight: 0.6, maxSize: cap(800, 600), usefulSize: useful(600, 400)),
    "Calendar":          Priority(tier: "minor", weight: 1.0, maxSize: cap(900, 700), usefulSize: useful(700, 500)),

    // noise - off to another display if one exists
    "Music":             Priority(tier: "banish", weight: 0.3, maxSize: cap(560, 440), usefulSize: useful(400, 300)),
    "Spotify":           Priority(tier: "banish", weight: 0.3, maxSize: cap(560, 440), usefulSize: useful(400, 300)),
    "TV":                Priority(tier: "banish", weight: 0.3, maxSize: cap(700, 500), usefulSize: useful(480, 320)),
]

let priorityURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".window-spike/priorities.json")

func encodePriorities(_ p: [String: Priority]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (k, v) in p {
        var e: [String: Any] = ["tier": v.tier, "weight": Double(v.weight),
                                "useful": [Double(v.usefulSize.width), Double(v.usefulSize.height)]]
        if let m = v.maxSize { e["max"] = [Double(m.width), Double(m.height)] }
        out[k] = e
    }
    return out
}

/// Load the user's file, seeding it with the defaults the first time.
func loadPriorities() -> [String: Priority] {
    guard let d = try? Data(contentsOf: priorityURL),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
        try? FileManager.default.createDirectory(at: priorityURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: encodePriorities(defaultPriorities),
                                               options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: priorityURL)
        }
        return defaultPriorities
    }
    // Start from the built-in defaults and overlay the file. A config written by an
    // older version is missing keys that have since been added; inheriting the default
    // for those beats silently falling back to a generic value for every app.
    var out = defaultPriorities
    for (k, raw) in j {
        guard let e = raw as? [String: Any] else { continue }
        var p = out[k] ?? Priority()
        if let t = e["tier"] as? String { p.tier = t }
        if let w = e["weight"] as? Double { p.weight = CGFloat(w) }
        if let m = e["max"] as? [Double], m.count == 2 {
            p.maxSize = CGSize(width: m[0], height: m[1])
        }
        if let u = e["useful"] as? [Double], u.count == 2 {
            p.usefulSize = CGSize(width: u[0], height: u[1])
        }
        out[k] = p
    }
    return out
}

/// Share `pool` among items by weight, honouring caps. When an item hits its cap its
/// unused share flows back to the others rather than being wasted - without this, a
/// capped music player silently strands pixels nobody can use.
func waterfill(base: [CGFloat], weight: [CGFloat], cap: [CGFloat?], pool poolIn: CGFloat) -> [CGFloat] {
    var result = base
    var pool = poolIn
    var active = Set(base.indices.filter { i in
        if let c = cap[i] { return base[i] < c }
        return true
    })

    while pool > 0.5 && !active.isEmpty {
        let wsum = active.map { weight[$0] }.reduce(0, +)
        guard wsum > 0 else { break }
        var spent: CGFloat = 0
        var capped: [Int] = []
        for i in active.sorted() {
            let share = pool * (weight[i] / wsum)
            if let c = cap[i], result[i] + share >= c {
                spent += c - result[i]
                result[i] = c
                capped.append(i)
            } else {
                result[i] += share
                spent += share
            }
        }
        pool -= spent
        if capped.isEmpty { break }
        capped.forEach { active.remove($0) }
    }
    return result
}
