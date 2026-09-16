# Drag-to-snap

Drag a window toward a screen edge, see a preview of where it will land, release to snap.

This document is a design, not a task. It records the decisions and - more usefully - the
reasons, so that whoever implements it does not rediscover them. It is grounded in a read of
Rectangle, Loop, Amethyst, yabai, AeroSpace and MacsyZones; raw findings live in
`audit/snapping/`.

## Why build it at all

Every reviewer in this category treats drag-to-snap as the baseline. Shipping without it
invites the comparison "it does less than Rectangle, which is free" regardless of how good
the layout engine is. That is tracked separately as a strategic question in #26 - this
document assumes the answer is yes and describes how.

It is worth being clear-eyed: this is the one area where the competition is genuinely
excellent and free. We are not going to win on snapping. We build it so that not having it
stops being the reason people never reach the part we are good at.

## The central decision: do not use AXObserver as the drag signal

This is the finding that matters, and it contradicts the mechanism proposed in #30.

`AXObserver` with `kAXWindowMovedNotification` looks like the obvious way to detect a drag.
It is the wrong choice for us specifically, for a reason that is sharper in this project
than in the ones that use it:

**We move windows programmatically. AXObserver cannot tell our own writes apart from a user
drag.** Our layout daemon rewrites frames constantly; every one of those writes would look
exactly like the user dragging. MacsyZones hits this and has to bolt on
`CGEventSource.buttonState` polling purely to compensate. Notifications also arrive *after*
the window has already moved, which is late for a preview.

Instead, follow **Loop's model**:

- A passive `NSEvent.addGlobalMonitorForEvents` watching `.leftMouseDown`,
  `.leftMouseDragged`, `.leftMouseUp`.
- On drag start, resolve the dragged window once through the existing CGWindowList-plus-AX
  enumeration path. No new window-resolution subsystem.
- On each tick, compare the window's live AX frame against its frame at drag start. That
  comparison - not a notification - is what tells us a real drag is happening.

This needs **only Accessibility**, which we already hold. No Input Monitoring, no event
interception, no privilege escalation. And it is a small extension of what we already do
rather than a new subsystem: we read AX frames constantly as part of enumeration and
minimum-size measurement.

Explicitly rejected for v1: an active or rewriting `CGEventTap` (Rectangle's upgrade path,
yabai's HID-level tap). Both exist to *fight or replace* the OS's native drag. Our
interaction rides on top of the native title-bar drag, so we only need to observe. If
`.cgSessionEventTap` becomes necessary later for latency, keep it **listen-only** - never
`.defaultTap`, never `kCGHIDEventTap`.

## The preview overlay

All the studied projects converge on the same recipe, so take it:

- `NSPanel`, `styleMask: [.borderless, .nonactivatingPanel]`
- `isOpaque = false`, `hasShadow = false`, `ignoresMouseEvents = true`
- `collectionBehavior = .canJoinAllSpaces`
- window level clearly above normal app windows

Two guards that **none of the studied projects appear to do explicitly**, and that we need
because we are also a window enumerator:

1. Filter our enumeration on `kCGWindowLayer != 0`, which our Mission Control detection
   already relies on, so the panel is structurally excluded.
2. Unconditionally drop any CGWindowList entry whose owning PID is our own, before any
   layout decision runs.

Without both, the organizer will eventually try to arrange its own preview overlay.

## Zone model: a fixed grid

Start with fixed edge and corner targets - halves, corners, perhaps thirds - sized from each
display's frame. Rectangle's static grid, not Loop's aspect-ratio-conditional zones and not
MacsyZones' freeform editor.

The reason is specific to us. **We already know every window's measured minimum size.** With
a fixed grid, every zone's dimensions are knowable in advance, so "which zones can this
window actually occupy" is precomputable. A freeform or aspect-conditional zone model
multiplies that state space before there is any evidence users need the flexibility.

That composition is also the part a competitor cannot copy easily: we can grey out a zone
that a window physically cannot fit, because we measured. Rectangle cannot, because it never
did.

Multi-display: resolve which screen owns the drag by the first `NSScreen` whose frame
contains the cursor, as Rectangle does. Treat the exact-boundary-pixel case as a known
limitation. Nothing studied solves it and it is not worth the design cost.

## The snap

This part needs no new thinking - our existing rules already match what Rectangle does line
for line (see `AGENTS.md`, "Resize constraints"):

- write size, then position, then size again
- read the frame back rather than trusting the write
- if the result is smaller than the target zone because the app clamped, realign the actual
  rect against whichever zone edges it still shares, rather than leaving it pinned to the
  wrong corner

That last behaviour is Rectangle's `ClampedWindowAligner`, including a 1pt tolerance for
Dock-clamp noise. It is MIT, so it can be copied directly with attribution.

No animation for the window move in v1; none of the studied projects animate it. Only the
preview panel benefits visibly, and that can wait.

## v1 scope

1. Passive global mouse monitor for down / drag / up.
2. Resolve the dragged window once at drag start, via the existing enumeration path.
3. Per tick, compare live AX frame to frame-at-drag-start; once moved, hit-test the cursor
   against the fixed per-display grid.
4. Show, update and hide the overlay panel for the current target zone.
5. On mouse-up inside a zone: compute the target rect, apply, read back, realign if clamped.
6. Track **one** pre-snap frame per window - a single slot, not a stack - so a later drag
   ending outside any zone can restore it. Restore only if the window's current frame still
   matches what we last produced, so a manual resize is never silently discarded.
7. Visible degradation when Accessibility is revoked mid-session. AX calls fail *silently*
   at the API level, so this needs its own user-facing state rather than a silent no-op.

## Deliberately not in v1

- **No event interception.** No active `CGEventTap`, no HID-level tap. Wait for a reported
  problem before building Rectangle's coordinate-rewriting workaround.
- **No freeform zone editor.** Also GPLv3 in its reference implementation.
- **No aspect-ratio-conditional zones.** Later polish at best.
- **No cross-Space or fullscreen dragging.** Unsupported by public API; detect and refuse,
  consistent with our existing fullscreen rule.
- **No multi-level undo.** One slot per window is what real users of Rectangle and Loop
  live with.
- **No pre-emptive Input Monitoring request.** No studied project needs it for a mouse-only
  passive monitor. Add it only if testing proves Accessibility insufficient.

## The pitfall to expect

**macOS's own edge gestures fight edge-based snapping.** Stage Manager owns the left edge;
Mission Control owns the top. This has caused repeated regressions in Rectangle across macOS
point releases, with load-bearing workaround code in its `FootprintWindow` and
`SnappingManager`.

Do not try to pre-solve this. Treat it as a known future problem, and expect it to break on
a macOS update rather than being surprised by it.

## Licences

This matters and is easy to get wrong.

| Project | Licence | What we may take |
|---|---|---|
| Rectangle | MIT | code, with attribution |
| Amethyst | MIT | code, with attribution |
| yabai | MIT | code, with attribution |
| AeroSpace | MIT | code, with attribution |
| **Loop** | **GPLv3** | **approach only** |
| **MacsyZones** | **GPLv3** | **approach only** |

The awkward part: **Loop is the project architecturally closest to what we need**, and it is
GPLv3. Copying its code would make our distributed result GPLv3. Everything above borrows
Loop's *design* and describes it independently; the only code worth lifting verbatim is
Rectangle's clamp-realignment, which is MIT.

## Open questions

- Which zones ship in v1 - halves and corners only, or thirds as well?
- Does a snapped window join the managed layout, so a later hotkey press accounts for it, or
  stay independent until the next arrange?
- Should zones a window cannot fit be hidden, greyed, or shown and refused on release?
- Does snapping live in the existing `wfocus` daemon or its own process?

## Relationship to #30

#30 (shared-edge resizing) and this feature need the same foundation: live drag observation
and a persisted layout structure. #30 currently proposes `AXObserver` as its mechanism -
**that recommendation is superseded by this document** and should use the same passive
monitor plus frame-diff approach, for the same reason: our own writes are indistinguishable
from a user drag otherwise.

Build the drag-observation layer once and both features sit on top of it.
