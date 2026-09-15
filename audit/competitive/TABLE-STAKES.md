# Table stakes: what any entrant in this category is expected to have

Evidence-led. A feature is "table stakes" if its absence is what a review or
comparison article calls out as a *gap relative to competitors*, rather than
a stylistic choice. Marked HAVE / PARTIAL / MISSING against window-organizer
as described in its README/AGENTS.md.

## 1. Drag-to-edge/corner snapping with a live preview overlay
Universal across Rectangle, Magnet, BetterSnapTool, Swish, and now Apple's
own built-in tiling. Every mainstream comparison piece treats this as the
baseline interaction, to the point that Apple shipping it natively in
Sequoia prompted "do I still need a third-party app" articles rather than
"why would Apple do this."
- **window-organizer: MISSING.** By design - it is hotkey-triggered, not
  drag-driven. This is a deliberate scope cut (README frames the pitch as
  "the other bargain" to tiling managers), not an oversight, but it means
  window-organizer cannot serve the single most common workflow moment in
  this category: "I am dragging this window right now and want it to snap."
  It only ever acts after the fact, on request.

## 2. Configurable keyboard shortcuts for standard positions
Halves, thirds, quarters, fullscreen, next/previous display - present in
every tool surveyed including the free ones (Rectangle, Magnet,
BetterSnapTool, Apple's Control+Option+arrow set).
- **window-organizer: PARTIAL.** Has one global hotkey to trigger a full
  re-layout (via `--master`, `--spill` flags and a Raycast script), not a
  per-position shortcut grammar. That is consistent with its positioning,
  but means it cannot answer "just snap this one window left" without
  reorganizing everything else too - a mode competitors all support and
  window-organizer's docs don't mention supporting.

## 3. Multi-monitor support, including "move to other display"
Called out repeatedly - Swish was built specifically because "dragging-based
window managers are poor on multi-monitor setups." Magnet, Rectangle,
BetterSnapTool, and Apple's own tiling all handle multi-display moves.
- **window-organizer: HAVE.** `--spill` explicitly exists to use other
  displays rather than cramming one; the priority/tier model is inherently
  multi-window/multi-display aware.

## 4. Custom snap zones / custom sizes (paid-tier expectation)
BetterSnapTool, Rectangle Pro, and Moom all offer this, and a review
explicitly frames its absence in a cheaper competitor as a trade-off buyers
should weigh ("no window groups, cursor gestures, or per-app settings").
- **window-organizer: N/A / not applicable to its model.** It computes
  layout from tier + weight + measured minimum rather than exposing
  arbitrary user-drawn zones. Not a gap so much as a different mechanism -
  but it means power users who want to hand-place one specific window at a
  custom pixel size currently have no path to do that.

## 5. Per-app saved layouts / per-app rules
Rectangle Pro (App Layouts), Moom (saved arrangements), yabai and AeroSpace
(app-match rules) all offer some version of "this app gets treated
differently." Reviews treat the presence of per-app settings as a
completeness signal (see BetterSnapTool review above).
- **window-organizer: HAVE, and more granular than any competitor
  surveyed.** `priorities.json` gives four tiers, a weight, and a size cap
  per app - richer than any shipped per-app mechanism found in this survey.
  This is the one dimension where window-organizer is already ahead of the
  table stakes, not just meeting them.

## 6. Respecting window minimum sizes (not crushing content to illegibility)
This is *expected* in the sense that failing at it reads as a bug - Apple's
own built-in tiling was criticized by name (News app example) for ignoring
developer minimum sizes. But no competitor actually *measures* minimums;
they rely on the OS to clamp and hope for the best, which is why the failure
mode exists industry-wide.
- **window-organizer: PARTIAL, and self-documented as such.** It does probe
  real per-window technical minimums (the 1x1-refusal trick), which no
  competitor does - but its own README lists two known gaps: minimums are
  cached per-app not per-window (so a second window of the same app can
  overlap its neighbor), and it currently satisfies the *technical* minimum
  rather than a *useful* one, so "a browser can be placed at 222px tall:
  present, and worthless" - which is precisely the failure the product's
  differentiated claim says it exists to prevent. This is the single
  biggest execution gap between the pitch and the current spike.

## 7. Undo / restore previous arrangement
Present in Rectangle (implicitly, via re-toggling positions), Tiles
(explicit "restore previous size"), and expected generally - users treat
"can I get back to what I had" as baseline trust in any tool that touches
window geometry automatically.
- **window-organizer: HAVE.** `warrange --undo` explicitly restores and
  un-minimizes. This is a real strength and directly mitigates the
  stow-behavior risk discussed in VERDICT.md.

## 8. One-time purchase or free; no forced subscription
Near-universal in this category. Every tool surveyed is either free/OSS or a
one-time purchase; Setapp is the only subscription path and it bundles
hundreds of apps rather than being window-management-specific. A
subscription-only single-purpose window manager would be an outlier.
- **window-organizer: N/A (not yet a priced product).** Worth flagging now:
  whatever the eventual pricing, a subscription-only model would violate
  this category's norm and invite comparison-article criticism on pricing
  grounds alone, independent of the product's merits.

## 9. Working without disabling System Integrity Protection
Increasingly expected, not just nice-to-have: AeroSpace and "Mosaico" were
both built explicitly as reactions to yabai's SIP requirement, described in
their own positioning as a wart to route around.
- **window-organizer: HAVE**, per its own documented permission model
  (Accessibility + Screen Recording only, both standard TCC grants, no SIP
  mentioned anywhere in README/AGENTS.md).

## 10. Correct behavior around Mission Control, Spaces, and fullscreen windows
Every serious tool in this space (yabai, AeroSpace, Amethyst) has to solve
this, and getting it wrong is exactly what marks a tool as "unfinished" in
user reports - stray windows dragged in from other Spaces, or layouts
computed from stale/thumbnail geometry, read as the app "going rogue."
- **window-organizer: HAVE**, and unusually well-documented: AGENTS.md lists
  specific mitigations (CG/AX intersection to avoid dragging in off-Space
  windows, detecting Mission Control's Dock-owned overlay before acting,
  polling for window-count stability after Space transitions). This is a
  case where the project's own "what we learned" notes read like a
  checklist of exactly the mistakes competitors' architecture docs (where
  they exist at all) warn against.

## Summary
| # | Table-stakes feature | Status |
|---|---|---|
| 1 | Drag-to-snap | MISSING (by design) |
| 2 | Per-position keyboard shortcuts | PARTIAL |
| 3 | Multi-monitor support | HAVE |
| 4 | Custom snap zones/sizes | N/A (different model) |
| 5 | Per-app rules/layouts | HAVE (exceeds category norm) |
| 6 | Real minimum-size respect | PARTIAL (technical yes, useful no - self-documented gap) |
| 7 | Undo | HAVE |
| 8 | One-time/free pricing norm | N/A (unpriced) |
| 9 | No SIP disabling required | HAVE |
| 10 | Correct Spaces/Mission Control/fullscreen handling | HAVE |

Net read: window-organizer is behind on the single most common interaction
(drag-to-snap) and on the exact claim it is trying to differentiate on
(useful vs. technical minimum is still open per its own docs). It is ahead
of the category on per-app policy granularity and on documented correctness
around macOS's uglier corners. Shipping without #1 is a legitimate,
defensible bet given the positioning - but it means window-organizer will
never be compared favorably by reviewers who evaluate this category by
"how does it feel to drag a window to the edge," which is most of them.
