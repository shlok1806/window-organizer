# Lifecycle & stability audit - warrange

Territory: how the plan behaves as a desktop evolves (determinism, order-sensitivity,
focus resolution, degenerate inputs).

## Fixtures (9)
- base.json - baseline 3-window desktop, used for the determinism check (run 8x, byte-identical
  --json output every time - no non-determinism found for a fixed input).
- hero-mismatch.json - two WezTerm windows, only the second (higher id) is focused.
- order-tie-AB.json / order-tie-BA.json - same desktop, two structurally-identical Finder windows
  swapped in array order, forcing one to be evicted.
- empty-windows.json - zero windows.
- no-displays.json - zero displays.
- no-focus.json - zero windows with focused:true (exploratory; see notes below).
- two-focus.json - two windows both focused:true (exploratory; see notes below).
- zero-neg-size.json - windows with zero/negative rect size (exploratory; no bug found - rect is
  not consulted by the planner at all, only minSize/usefulSize, so it cannot crash the packer).

## Issues filed (3, all distinct from the 6 known issues)
1. **[blocker]** `issues/01-hero-identity-follows-app-name-not-focused-window.md` - hero status is
   assigned by looking up "first window whose app name matches the focused window's app name", not
   the focused window itself. With two windows of the same hero-tier app (e.g. two WezTerm windows -
   an extremely common setup for exactly the apps this tool privileges), the wrong instance can
   become hero while the window the user is actually looking at gets squeezed into a normal-tier
   strip.
2. **[blocker]** `issues/02-array-order-decides-eviction-victim-among-tied-windows.md` - when two
   windows are genuinely tied on every priority signal the engine considers (tier rank, then area),
   which one gets stowed is decided purely by their position in the input `windows` array. Live
   window enumeration order (NSWorkspace/AX) is not a stable, user-meaningful property, so this is a
   real mechanism by which the same desktop could produce different minimized windows across
   otherwise-identical runs - directly matching the rubric's "plan is unstable" criterion.
3. **[major]** `issues/03-json-mode-emits-plain-text-on-empty-fixture-paths.md` - the zero-windows
   and zero-displays early-exit paths print human text and, in the zero-windows case, exit 0 - even
   when `--json` was requested. Both bypass the `jsonOut` check that every other output path in the
   program respects, breaking the machine-readable contract `--json` exists to provide.

## Notes on things probed but NOT filed as bugs
- **Determinism for fixed input:** confirmed solid (8 identical runs, byte-identical JSON).
- **id monotonicity:** confirmed ids have zero effect on the plan today beyond being echoed back in
  the output (consistent with known issue 1); the array-order tie-break in issue 2 generalizes why
  this matters more than it first appears.
- **No focused window (no-focus.json):** heroApp resolves to nil, so no window gets tier "hero"
  even if its app is normally hero-tier (WezTerm keeps weight 3 but drops to tier "normal"). This
  is a defensible, intentional-looking consequence of "hero == the window you're in" and overlaps
  with known issue 6 (focus recency), so it was not filed separately.
- **Two focused windows (two-focus.json):** the first focused window (by array order) silently wins,
  no warning/error for the malformed "two focused" input. Not filed on its own since the more
  concrete and provable failure mode is issue 1 (hero picks the wrong window even with exactly one
  correctly-focused window present).
- **Zero/negative window size:** does not crash the tool; rect is only used for output/undo
  bookkeeping and is never consulted by the packer (only `minSize`/`usefulSize` are), so a
  zero/negative rect cannot affect placement math today.

## Single most important finding
**Issue 1 (hero identity misresolution).** It breaks the tool's headline promise - "the window
you're using gets the dominant slot" - for the single most predictable power-user scenario this
tool's own app policy anticipates: someone running two terminal/editor windows at once. The bug is
a one-line class of mistake (resolve hero by app-name lookup instead of by the focused object
itself) but its effect is maximally visible and confusing: the active window shrinks, a stale
window balloons, with no indication anything went wrong.
