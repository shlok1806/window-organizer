# Eviction victim among tied windows is decided by input array order, not any priority signal

**Severity:** blocker
**Fixture:** fixtures/order-tie-AB.json, fixtures/order-tie-BA.json (identical desktop, only the
order of two structurally-identical windows in the `windows` array is swapped)
**Command:** `./warrange --plan-from fixtures/order-tie-AB.json --json` vs
`./warrange --plan-from fixtures/order-tie-BA.json --json`

## Expected
Two Finder windows (winA/id 10 and winB/id 11) are identical in every priority-relevant way: same
app, same tier (minor), same rect size, same minSize, same area, neither focused. The display is
sized so only one of the two Finder windows plus the hero (WezTerm) can fit, forcing exactly one
Finder window to be stowed. Since the two candidates are genuinely tied on every signal the engine
looks at (rank, then area), which one gets stowed should either be identical no matter what order
they were enumerated in, or the tie-break should be deterministic on a meaningful property (e.g.
id). At minimum, reordering two otherwise-identical windows in the input should not change which
real window on the user's screen goes away.

## Actual
Fixture AB (winA=id 10 listed before winB=id 11):
```
./warrange --plan-from fixtures/order-tie-AB.json --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":583,"w":900,"x":0,"y":32}},{"app":"Finder","display":0,"id":11,"rect":{"h":409,"w":760,"x":0,"y":623}}],"stowed":[{"app":"Finder","id":10}]}
```
Fixture BA (same windows, only winB listed before winA in the array):
```
./warrange --plan-from fixtures/order-tie-BA.json --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":583,"w":900,"x":0,"y":32}},{"app":"Finder","display":0,"id":10,"rect":{"h":409,"w":760,"x":0,"y":623}}],"stowed":[{"app":"Finder","id":11}]}
```
The `stowed` window flips from id 10 to id 11 purely because of array order - nothing else about
the two windows differs.

## Why this is wrong
This is a distinct failure mode from the documented "greedy eviction by (tier rank, then area)"
known issue: that known issue explains which class of window gets evicted first, but says nothing
about how ties within that class are broken. Here the tie-break has no principled basis at all - it
is purely positional. Concretely:
- id is proven to have zero influence on the outcome (both fixtures assign ids 10/11 identically;
  only their position in the array differs, and the plan follows position, not id).
- The real-world enumeration order that feeds `windows` on a live desktop comes from
  `NSWorkspace.runningApplications` / per-app AX window lists, which is not a stable, semantically
  meaningful ordering a user controls - it can shift between runs based on process launch order,
  most-recent-activation, or internal OS bookkeeping, with no change to the actual desktop the user
  perceives.
- Because eviction has genuine ties in ordinary usage (two Finder windows, two Slack windows, two
  browser windows of the same priority), the same conceptual desktop, planned twice in a row, can
  disagree about which specific window gets minimized - precisely the "plan is unstable" criterion
  in the audit rubric, and also "a trivial change to input causes a disproportionate change in
  output" (swap two array entries and a different real window disappears from the screen).

## Suggested fix (optional)
Make the tie-break explicit and stable, e.g. break rank/area ties by window id (lowest id = oldest
= evicted first, consistent with the documented no-birth-recency policy) instead of leaving it to
whatever order Array.max(by:) happens to resolve ties in.
