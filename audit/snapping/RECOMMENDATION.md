# Recommendation: drag-to-snap for window-organizer

This is a design recommendation, not code. It is built on what window-organizer already
has (per AGENTS.md and the task brief): Accessibility permission already granted, a
background daemon/run-loop already running (the focus recorder), CGWindowList-intersected-
with-AX window enumeration already implemented, and per-window minimum sizes already
measured and cached. All claims about prior art are backed by FINDINGS.md; this document is
the opinionated synthesis.

## Recommended drag-detection approach

Start with Loop's architecture, not Rectangle's, and not AXObserver.

Concretely: an NSEvent.addGlobalMonitorForEvents (or, if finer control over thread/latency
is wanted later, a listen-only CGEventTap at .cgSessionEventTap - never .defaultTap and
never kCGHIDEventTap) watching .leftMouseDown / .leftMouseDragged / .leftMouseUp, combined
with polling the dragged window's live AX frame against its frame-at-drag-start to detect
that a real drag is happening.

Why this over the alternatives:

- Not AXObserver (Amethyst/MacsyZones' approach) as the primary drag signal. AXObserver
  notifications arrive after the window has already moved, and cannot distinguish a user
  drag from a programmatic move without an extra signal (MacsyZones needs
  CGEventSource.buttonState just to compensate for this). Since window-organizer's own
  daemon already performs programmatic AX moves during layout, reusing AXObserver as the
  drag trigger risks the daemon's own writes re-triggering "drag" logic - a foot-gun this
  design avoids by construction.
- Not an active/rewriting CGEventTap (Rectangle's upgrade path, yabai's HID-level
  intercepting tap) for v1. Both exist specifically to fight or replace the OS's native
  drag gesture (Mission Control coordinate rewriting, or a modifier-gated synthetic drag
  channel). window-organizer's stated interaction model is "drag toward an edge, see a
  preview, release to snap" riding on top of the OS's own native title-bar drag, not
  replacing it - so there is no need to intercept or swallow events, only to observe them
  and read AX state. That is Loop's model exactly, and it needs only Accessibility, not a
  privilege escalation to event interception.
- Loop's approach is also the cheapest fit with what already exists: window-organizer
  already reads AX frames as part of its enumeration/measurement pipeline; polling "did
  this window's frame change since drag start" is a small extension of that existing
  capability, not a new subsystem.

## Overlay

Borrow the common recipe directly (all three projects converge on it, it's clearly
well-trodden): NSPanel, styleMask [.borderless, .nonactivatingPanel], isOpaque = false,
ignoresMouseEvents = true, hasShadow = false, collectionBehavior = .canJoinAllSpaces, level
somewhere clearly above normal app windows (Loop's NSWindow.Level(.screenSaver.rawValue - 1)
is a reasonable default; Rectangle's .modalPanel is also fine and slightly more
conservative).

Two things worth doing that none of the studied projects seem to do explicitly: (1) filter
window-organizer's own CGWindowList-based enumerator on kCGWindowLayer != 0 (which the
project's Dock/Mission-Control-window detection already needs anyway) so the preview panel
is structurally excluded, and (2) as a second, unconditional guard, filter out any
CGWindowList entry whose owning PID equals window-organizer's own PID before any layout
decision runs.

## Zone model

Start with a fixed set of edge/corner targets (halves, corners, maybe thirds) sized from
each display's own frame - i.e. Rectangle's static 9-way grid, not Loop's aspect-ratio-
dependent dynamic zones and not MacsyZones' freeform editor. Reasons: it's the simplest to
implement and reason about, it's the easiest to test deterministically, and window-
organizer already has a documented, hard-won understanding of per-window minimum sizes -
composing that with a *configurable freeform zone editor* (MacsyZones) or *aspect-ratio-
conditional zone shapes* (Loop) multiplies the state space of "does this app's minimum fit
this zone" before there's evidence users need that flexibility. A fixed grid is also the
only model of the three that has a simple, unambiguous mapping onto the minimum-size
measurement work already done (each zone size is knowable in advance, so eligible-zones-
for-this-window can be precomputed instead of discovered live).

Multi-display seam handling: resolve "which screen owns this drag" the same way Rectangle
does (first NSScreen whose frame contains the cursor), but treat this as a known,
accepted limitation, not a solved problem - Rectangle's own approach is arguably under-
specified for the exact-boundary-pixel case, and nothing else studied does better. Don't
invest more than that in v1.

## The snap itself

Reuse window-organizer's already-documented rules directly - they already match what
Rectangle's source does line for line: write size, then position, then size again (to
handle the cross-display size-clamp behavior); read the resulting frame back after writing
rather than trusting the write; if the resulting size is smaller than the target zone
(minimum-size clamp), realign the actual rect against whichever zone edges it still shares
rather than leaving it pinned to the wrong corner (Rectangle's ClampedWindowAligner
pattern, with its 1pt Dock-clamp-noise tolerance, is worth copying almost verbatim - MIT
licensed, so literally copyable). No animation is required for v1 for the actual window
move (none of the studied projects animate that part); only the preview panel benefits
visibly from animation, and that can be deferred.

## Smallest credible first version (v1 scope)

1. NSEvent global monitor (or listen-only CGEventTap) watching left-mouse down/drag/up.
2. On drag start, resolve the dragged window once via the existing CGWindowList+AX
   enumeration path (no new window-resolution subsystem needed).
3. On each drag tick, compare live AX frame to frame-at-drag-start; once moved, hit-test
   cursor position against a fixed per-display 9-way (or simpler, 4-6 zone) grid.
4. Show/update/hide the borderless overlay panel for the current target zone.
5. On mouse-up inside a zone: compute the target rect, apply size/position/size, read back,
   realign if clamped by the window's already-known measured minimum.
6. Track one pre-snap frame per window (single slot, not a stack) so a subsequent drag that
   ends outside any zone can restore it, following Rectangle's rule: only restore if the
   window's current frame still matches what window-organizer itself last produced (so a
   manual resize since the snap is never silently discarded).
7. Explicit, visible degradation when Accessibility is revoked mid-session (CGEventTap/AX
   calls fail silently at the API level - this needs its own user-facing state, not a
   crash or silent no-op).

## What to deliberately NOT do in v1

- Do not intercept or rewrite events (no active/.defaultTap CGEventTap, no HID-level tap).
  There is no known need to fight Mission Control or Stage Manager yet; wait for it to
  actually be reported as a problem before building Rectangle's coordinate-rewrite hack.
- Do not build a freeform zone editor (MacsyZones' model). It's GPLv3-licensed anyway, and
  it's a UI investment with no evidence yet that fixed zones are insufficient.
- Do not build aspect-ratio-conditional zone shapes (Loop's model). Interesting for later
  polish, not needed for a credible first cut.
- Do not attempt cross-Space or fullscreen-window dragging. Both are unsupported by public
  API (per multiple Rectangle issues and window-organizer's own AGENTS.md rule); detect and
  skip/refuse rather than attempting.
- Do not build multi-level undo. A single pre-snap-frame slot per window, matching both
  Rectangle's and Loop's approach, is sufficient and is what real users of those tools
  apparently live with.
- Do not chase the multi-display exact-boundary-pixel ambiguity described in FINDINGS.md
  section 3. No studied project solves it either; it is not worth the design cost yet.
- Do not request Input Monitoring permission preemptively. No studied project needs it for
  a mouse-only tap; add it only if empirical testing on the target macOS version shows
  Accessibility alone is insufficient.
