import Foundation
import CoreGraphics

// Verifies the priority water-filling: space freed by a capped window must flow
// back to windows that can still use it, and nothing may exceed its cap.

func show(_ label: String, _ v: [CGFloat]) {
    print("  \(label): [" + v.map { String(format: "%.0f", $0) }.joined(separator: ", ") +
          "]  sum=\(Int(v.reduce(0, +).rounded()))")
}

print("")
print("1. three windows, base 100 each, 300px to share, weights 3:1:1, window2 capped at 150")
show("result", waterfill(base: [100, 100, 100], weight: [3, 1, 1], cap: [nil, 150, nil], pool: 300))
print("   expect window2 pinned at 150, its unused share flowing to the other two, sum 600")
print("")
print("2. no caps, equal weights - even split")
show("result", waterfill(base: [100, 100], weight: [1, 1], cap: [nil, nil], pool: 200))
print("   expect [200, 200], sum 400")
print("")
print("3. everything capped - pool cannot be spent, nothing exceeds its cap")
show("result", waterfill(base: [100, 100], weight: [1, 1], cap: [120, 120], pool: 500))
print("   expect [120, 120], sum 240")
print("")
