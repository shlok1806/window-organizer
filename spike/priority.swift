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
let defaultPriorities: [String: Priority] = [
    // make things - hero
    "WezTerm":           Priority(tier: "hero",   weight: 3.0),
    "iTerm2":            Priority(tier: "hero",   weight: 3.0),
    "Terminal":          Priority(tier: "hero",   weight: 3.0),
    "Ghostty":           Priority(tier: "hero",   weight: 3.0),
    "Alacritty":         Priority(tier: "hero",   weight: 3.0),
    "Code":              Priority(tier: "hero",   weight: 3.0),
    "Cursor":            Priority(tier: "hero",   weight: 3.0),
    "Xcode":             Priority(tier: "hero",   weight: 3.0),

    // read things - normal, but capped at a comfortable reading column
    "Safari":            Priority(tier: "normal", weight: 2.0, maxSize: CGSize(width: 1200, height: 4000)),
    "Google Chrome":     Priority(tier: "normal", weight: 2.0, maxSize: CGSize(width: 1200, height: 4000)),
    "Arc":               Priority(tier: "normal", weight: 2.0, maxSize: CGSize(width: 1200, height: 4000)),
    "Firefox":           Priority(tier: "normal", weight: 2.0, maxSize: CGSize(width: 1200, height: 4000)),
    "Preview":           Priority(tier: "normal", weight: 1.5, maxSize: CGSize(width: 1000, height: 4000)),

    // talk to people - present but contained
    "Microsoft Outlook": Priority(tier: "normal", weight: 1.4, maxSize: CGSize(width: 1300, height: 4000)),
    "Mail":              Priority(tier: "normal", weight: 1.4, maxSize: CGSize(width: 1100, height: 4000)),
    "Slack":             Priority(tier: "minor",  weight: 1.0, maxSize: CGSize(width: 820, height: 4000)),
    "Messages":          Priority(tier: "minor",  weight: 0.7, maxSize: CGSize(width: 560, height: 4000)),
    "Discord":           Priority(tier: "minor",  weight: 0.8, maxSize: CGSize(width: 900, height: 4000)),

    // look things up - small, capped hard
    "Finder":            Priority(tier: "minor",  weight: 0.8, maxSize: CGSize(width: 760, height: 560)),
    "System Settings":   Priority(tier: "minor",  weight: 0.6, maxSize: CGSize(width: 800, height: 620)),
    "Activity Monitor":  Priority(tier: "minor",  weight: 0.6, maxSize: CGSize(width: 800, height: 600)),
    "Calendar":          Priority(tier: "minor",  weight: 1.0, maxSize: CGSize(width: 900, height: 700)),

    // noise - off to another display if one exists
    "Music":             Priority(tier: "banish", weight: 0.3, maxSize: CGSize(width: 560, height: 440)),
    "Spotify":           Priority(tier: "banish", weight: 0.3, maxSize: CGSize(width: 560, height: 440)),
    "TV":                Priority(tier: "banish", weight: 0.3, maxSize: CGSize(width: 700, height: 500)),
]

let priorityURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".window-spike/priorities.json")

func encodePriorities(_ p: [String: Priority]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (k, v) in p {
        var e: [String: Any] = ["tier": v.tier, "weight": Double(v.weight)]
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
    var out: [String: Priority] = [:]
    for (k, raw) in j {
        guard let e = raw as? [String: Any] else { continue }
        var p = Priority()
        if let t = e["tier"] as? String { p.tier = t }
        if let w = e["weight"] as? Double { p.weight = CGFloat(w) }
        if let m = e["max"] as? [Double], m.count == 2 {
            p.maxSize = CGSize(width: m[0], height: m[1])
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
