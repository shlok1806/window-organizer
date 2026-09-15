import Foundation
import CoreGraphics

// Focus recency: how recently you actually used a window, as a decaying score.
//
// Relevance cannot be reconstructed at arrange time - by the time the hotkey is
// pressed the information is already gone. So a recorder samples the frontmost
// window on an interval and appends events here; the planner reads them back.
//
// The log records a window id and a timestamp. Never a title, never content.

struct FocusEvent {
    let id: Int
    let at: Date
}

let focusLogURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".window-spike/focus.jsonl")

/// Events decay with a half-life rather than falling off a threshold, so a window
/// does not abruptly stop mattering at some arbitrary age. Summing decayed events
/// also means many brief visits can rank alongside one long one, which is closer
/// to how people actually work than "last focused at" would be.
let focusHalfLife: TimeInterval = 10 * 60

func recencyScore(_ id: Int, _ events: [FocusEvent], now: Date) -> CGFloat {
    guard id != 0 else { return 0 }
    let tau = focusHalfLife / log(2)
    var score: CGFloat = 0
    for e in events where e.id == id {
        let age = now.timeIntervalSince(e.at)
        guard age >= 0 else { continue }              // clock skew: ignore the future
        score += CGFloat(exp(-age / tau))
    }
    return score
}

/// Read the recorder's log. Every failure mode - missing, empty, truncated, corrupt,
/// half-written last line - degrades to "no events", which scores every window equally
/// and leaves layout to priority alone. The hotkey must never fail because the recorder
/// is not running.
func loadFocusLog(_ url: URL = focusLogURL, limit: Int = 5000) -> [FocusEvent] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    let fmt = ISO8601DateFormatter()
    var out: [FocusEvent] = []
    for line in text.split(separator: "\n").suffix(limit) {
        guard let d = line.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let id = j["id"] as? Int,
              let ts = j["at"] as? String,
              let at = fmt.date(from: ts) else { continue }   // skip junk, keep going
        out.append(FocusEvent(id: id, at: at))
    }
    return out
}

/// Append one event. Kept to a bounded tail so the file cannot grow without limit.
func appendFocusEvent(_ id: Int, at: Date = Date(), url: URL = focusLogURL, keep: Int = 5000) {
    let fmt = ISO8601DateFormatter()
    let line = "{\"id\":\(id),\"at\":\"\(fmt.string(from: at))\"}\n"
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }

    // Trim occasionally rather than on every write.
    guard Int.random(in: 0..<50) == 0,
          let text = try? String(contentsOf: url, encoding: .utf8) else { return }
    let lines = text.split(separator: "\n")
    guard lines.count > keep * 2 else { return }
    let trimmed = lines.suffix(keep).joined(separator: "\n") + "\n"
    try? trimmed.write(to: url, atomically: true, encoding: .utf8)
}
