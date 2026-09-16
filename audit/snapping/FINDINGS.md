# Drag-to-snap on macOS: findings from open-source implementations

Scope: source-level study of Rectangle, Loop, Amethyst, yabai, AeroSpace, and MacsyZones,
plus a licensing note on Swish and "Tiles" which are closed source. All code excerpts below
were read from the actual repositories (URLs given); anything not directly observed in
source is flagged INFERRED.

---

## 1. Drag detection

Four genuinely different techniques showed up, not one dominant answer.

### 1a. Rectangle: NSEvent global monitor by default, upgrades to an active CGEventTap only when it needs to rewrite events

SnappingManager.startEventMonitor() picks between two monitor implementations at
runtime (SnappingManager.swift, https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Snapping/SnappingManager.swift):

    eventMonitor = Defaults.missionControlDragging.userDisabled
        ? ActiveEventMonitor(mask: mask, filterer: filter, handler: handle)
        : PassiveEventMonitor(mask: mask, handler: handle)

- PassiveEventMonitor (EventMonitor.swift, https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Utilities/EventMonitor.swift) is a plain NSEvent.addGlobalMonitorForEvents / addLocalMonitorForEvents pair watching .leftMouseDown/.leftMouseUp/.leftMouseDragged. This is the default path.
- ActiveEventMonitor is a CGEvent.tapCreate(tap: .cgSessionEventTap, ..., options: .defaultTap, ...) - a real tap that can swallow or mutate events, running on its own RunLoopThread (not the main thread).

Why the upgrade exists: Rectangle fights macOS's own "drag to top edge opens Mission
Control" gesture. Its filter(event:) function, only reachable through the active tap,
rewrites the y-coordinate of the live CGEvent to keep the cursor a pixel below the true
top edge:

    if event.deltaY < -Defaults.missionControlDraggingAllowedOffscreenDistance.cgFloat {
        cgEvent.location.y = minY + 1
        dragRestrictionExpirationTimestamp = ...
    }

An NSEvent monitor cannot do this - you only get a read-only copy of the event, delivered
after the OS has already acted on it. So the choice of API is driven entirely by whether
you need to intercept, not by wanting lower latency. The passive path is preferred because
it is cheaper and can't misbehave; the active tap is opt-in machinery reserved for one
specific OS-fighting hack.

### 1b. Loop: an always-on listen-only CGEventTap, but drag state is inferred by polling geometry, not by AX notifications

Loop's PassiveEventMonitor (PassiveEventMonitor.swift, https://github.com/MrKai77/Loop/blob/develop/Loop/Utilities/Event%20Monitoring/PassiveEventMonitor.swift) - despite the name, this is a CGEvent.tapCreate with options: .listenOnly - feeds .leftMouseDragged / .leftMouseUp into WindowDragManager
(WindowDragManager.swift, https://github.com/MrKai77/Loop/blob/develop/Loop/Core/WindowDragManager.swift). Crucially, Loop does not rely on AXObserver/kAXWindowMovedNotification to know a window is moving. On every .leftMouseDragged tick it:
1. Resolves which window is under the mouse once (WindowUtility.windowAtPosition) and caches it for the drag.
2. Reads that window's current AX frame and compares its four corners to the frame recorded at drag start (hasWindowMoved/hasWindowResized).
3. Only when the frame has actually changed does it run snap-zone logic and open the preview.

This means Loop treats the OS's native title-bar drag as ground truth and watches it via
polling-on-event rather than subscribing to an AX notification stream. WindowUtility.windowAtPosition (read in full, WindowUtility.swift, https://github.com/MrKai77/Loop/blob/develop/Loop/Window%20Management/Window/WindowUtility.swift) itself tries a private SkyLight API first ("faster and doesn't deadlock on own process"), then AX hit-testing (AXUIElement.systemWide.getElementAtPosition + kAXWindow on the element under point), then falls back to iterating CGWindowListCopyWindowInfo and testing containment - three-tier fallback, private API first.

### 1c. Amethyst and MacsyZones: per-window AXObserver + kAXWindowMovedNotification

Amethyst's ApplicationObservation struct (read in full, ApplicationObservation.swift, https://github.com/ianyh/Amethyst/blob/development/Amethyst/Model/ApplicationObservation.swift) sets up one AXObserver per running application
and subscribes to kAXWindowMovedNotification/kAXWindowResizedNotification (mapped from
an internal Notification enum, lines 106-156) alongside window-created/miniaturized notifications, retrying registration with exponential backoff up to 6 attempts (addObservers(), lines 200-210). Amethyst is a tiling WM, not a drag-to-snap
tool, but this is the textbook "observe, don't poll" pattern and it's what most agents
would reach for first.

MacsyZones uses the identical notification but adds a mitigation Loop solves differently.
Its onObserverNotification handler for kAXWindowMovedNotification throttles itself and
uses mouse-button polling to distinguish an active drag from any other window move:

    var shouldThrottleWindowMove: Bool {
        let isDragging = CGEventSource.buttonState(.hidSystemState, button: .left)
        let minInterval = isDragging ? activeWindowMoveThrottle : idleWindowMoveThrottle
        ...
    }

(Macsy.swift, https://github.com/rohanrhu/MacsyZones/blob/main/MacsyZones/Macsy.swift, lines ~205-226; throttle values are 1/120s while dragging vs 0.1s while idle) AXObserver fires for any frame change - programmatic or user-driven -
with no way to tell which. MacsyZones' answer is CGEventSource.buttonState, a cheap
synchronous poll of physical mouse-button state, used purely as a gate, not as the drag
source of truth.

Known pitfall with this family: MacsyZones issue #89 (https://github.com/rohanrhu/MacsyZones/issues/89), "Slow-launching app windows never observed by MacsyZones, causes snap-while-dragging to not load" - a newly launched app's window isn't snap-aware until its AXObserver has actually been registered (triggered by kAXWindowCreatedNotification), so a user who starts dragging a window before that registration completes gets no preview and no snap. This is a real registration-race, not a hypothetical.

### 1d. yabai: an active CGEventTap at kCGHIDEventTap that consumes the mouse-down click itself

yabai's mouse_handler.c (read in full, https://github.com/asmvik/yabai/blob/master/src/mouse_handler.c) creates its tap with CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, mouse_handler, mouse_state) - HID-level, not session-level, and non-listen-only. On kCGEventLeftMouseDown it checks whether the held modifier flags match a configured mouse_modifier; if so it swallows the click (return NULL) and starts tracking a synthetic drag/resize/swap gesture entirely inside yabai. If the modifier isn't held, the event passes through untouched and the app's own native drag behavior (title bar, etc.) proceeds normally. This is a fundamentally different posture from Rectangle/Loop: yabai's drag-to-tile is a separate, modifier-gated input channel, not an observer of the OS's native drag.

### Tradeoffs summary

| Approach | Latency | CPU | Can intercept/rewrite | Permission |
|---|---|---|---|---|
| NSEvent.addGlobalMonitorForEvents (Rectangle default) | Good enough for UI feedback; delivered async, no thread control | Very low | No - read-only copy | Accessibility (see below) |
| CGEventTap, .listenOnly (Loop) | Low, but tap runs off main thread deliberately | Low; own run loop avoids stalling UI | No | Accessibility |
| CGEventTap, .defaultTap, session-level (Rectangle active path) | Low | Low | Yes - required for the Mission-Control rewrite hack | Accessibility |
| CGEventTap, .defaultTap, HID-level (yabai) | Lowest, closest to hardware | Low | Yes - swallows clicks outright | Accessibility (stricter tap location; see note) |
| AXObserver + kAXWindowMovedNotification (Amethyst, MacsyZones) | Delivered after the app has already moved the window - inherently reactive, one AX round-trip of lag | Very low when idle; MacsyZones throttles to 120 Hz while a button is down to bound cost during a drag | No - you only ever hear about a fait accompli move | Accessibility |

Input Monitoring: none of the four codebases request Input Monitoring separately -
grepping all of Rectangle, Loop, MacsyZones, and yabai's mouse code for
CGPreflightListenEventAccess/CGRequestListenEventAccess/"InputMonitoring" turns up
nothing, and none declare an NSInputMonitoringUsageDescription. All of them gate their
tap purely on AXIsProcessTrusted()/Accessibility, consistent with the long-standing
behavior that CGEventTap at .cgSessionEventTap is authorized by the Accessibility TCC
list. Caveat (partially inferred): several developer-forum threads report that
keyboard event taps have, on some macOS versions, additionally required Input
Monitoring, and that kCGHIDEventTap (the level yabai uses) is anecdotally treated more
strictly than .cgSessionEventTap (used by Rectangle and Loop). None of the four projects'
own source or docs mention a second permission prompt for their mouse-only taps, so the
practical takeaway for window-organizer - which only needs mouse events and already holds
Accessibility - is: prefer .cgSessionEventTap, not kCGHIDEventTap, and expect Accessibility
alone to suffice, but confirm this empirically on the target macOS version rather than
trusting it blindly.

---

## 2. The preview overlay

All three overlay implementations examined converge on the same recipe: a borderless,
non-activating NSWindow/NSPanel, isOpaque = false, mouse events disabled, and a window
level well above normal app windows but still tagged so it survives Space switches without
being a "real" window.

Rectangle - FootprintWindow (read in full, FootprintWindow.swift, https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Snapping/FootprintWindow.swift):

    super.init(contentRect: initialRect, styleMask: .titled, backing: .buffered, defer: false)
    isOpaque = false
    level = .modalPanel
    hasShadow = false
    collectionBehavior.insert(.transient)

It's initialized with .titled style (then hides all the title-bar buttons and makes the
title bar transparent) rather than .borderless - likely to get free rounded-corner /
vibrancy behavior on some macOS versions - but visually presents as a plain rounded rect via
an NSBox content view. It fades in/out (orderFront/orderOut overridden to animate
alphaValue) rather than just appearing. Notably it overrides isVisible to force true
while Stage Manager's strip is showing, working around Stage Manager pushing the panel
off-window - a comment right there says as much (line ~50).

Loop - ActivePanel in PreviewController (read in full, PreviewController.swift, https://github.com/MrKai77/Loop/blob/develop/Loop/Window%20Action%20Indicators/Preview%20Window/PreviewController.swift):

    let panel = ActivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = .canJoinAllSpaces
    panel.hasShadow = false
    panel.level = NSWindow.Level(NSWindow.Level.screenSaver.rawValue - 1)

Explicitly borderless + .nonactivatingPanel (never takes key/main status, never steals
focus from the dragged window), ignoresMouseEvents = true (clicks pass through to
whatever's under it), and a level just below .screenSaver - deliberately very high so it
floats above literally everything including other floating panels, but one notch down so an
actual screen saver would still win.

MacsyZones - SectionWindow/LayoutWindow (partially read via targeted grep, Layout.swift, https://github.com/rohanrhu/MacsyZones/blob/main/MacsyZones/Layout.swift):

    window = NSWindow(..., styleMask: [.borderless], ...)
    window.isOpaque = false
    window.ignoresMouseEvents = true
    window.level = .statusBar - 2
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

(the first .level line is SectionWindow, the zone highlight; the second is LayoutWindow / GridLayoutWindow). Same shape again: borderless, transparent background, mouse-transparent, elevated level,
.canJoinAllSpaces (or .stationary) so it doesn't get reassigned to a Space when the app
that owns it changes Space.

How they avoid being treated as "a window" by other enumerators, and how window-organizer
should avoid re-arranging its own overlay (this part is INFERRED - no explicit "we exclude
our own overlay" code was found in any of the three, most likely because none of these tools
also enumerate all on-screen windows for a tiling pass while the overlay is up):
CGWindowListCopyWindowInfo's kCGWindowLayer key reflects the originating
NSWindow.level, and normal application windows sit at layer 0. Every overlay above uses a
non-zero level (.modalPanel, .screenSaver - 1, .statusBar +/- N), so a kCGWindowLayer
!= 0 filter - which window-organizer's CGWindowList enumeration would need anyway to
skip the Dock/menu bar/Notification Center - should also exclude these panels "for free."
The project's own AGENTS.md already gestures at this (a Dock-owned layer-0 window used to
detect Mission Control thumbnails), so the convention is consistent. As a second, cheaper
guard: filter out any CGWindowList entry whose owning PID equals the tool's own PID before
doing anything else - this is unconditionally correct regardless of layer and costs nothing.

---

## 3. Zone / target detection

Three distinct models, not one "the" answer:

Rectangle - configurable 9-way directional grid, per screen, with "compound" dynamic
zones. SnappingManager.directionalLocationOfCursor (SnappingManager.swift, lines ~447-490) hit-tests the cursor against frame.minX/maxX/minY/maxY plus per-edge margins (marginTop/Bottom/Left/Right, user-configurable) and a cornerSnapAreaSize, returning one of 9 Directional cases (tl, t, tr, l, r, bl, b, br, c). Each Directional maps, via SnapAreaModel (SnapAreaModel.swift, https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Snapping/SnapAreaModel.swift, read in full), to either a fixed WindowAction (e.g. .topLeft) or a CompoundSnapArea - a calculation object (HalvesCompoundCalculation, ThirdsCompoundCalculation, etc.) that changes what rect you get depending on repeated hovers or on landscape vs. portrait screen orientation (there are separate landscape/portrait maps). So the left edge, for instance, isn't one fixed rect; it can cycle through left-third -> left-two-thirds -> left-half depending on dwell/re-entry, and the whole map is user-remappable per direction.

Loop - dynamically shaped zones from cursor position + screen aspect ratio, not a fixed
grid. WindowDirection.getSnapDirection (WindowDirection+Snapping.swift, https://github.com/MrKai77/Loop/blob/develop/Loop/Window%20Management/Window%20Action/WindowDirection%2BSnapping.swift, partially read lines 82-130, 240-244) first computes an inset "ignored" center rectangle (snapThreshold inset from all four edges, with the top inset additionally respecting the menu bar height) - inside that rectangle, nothing snaps. Outside it, the direction returned depends on which edge the cursor crossed and on the screen's aspect ratio (isNearSquare, verticalSimple, horizontalSimple flags): near-square or portrait-ish screens get simpler halves, wide screens get corner/third logic on the vertical axis. This is meaningfully different from a static configuration file - the zone shape itself is a function of physical screen proportions.

yabai - target is relative to the window being hovered over, not the screen edge.
mouse_determine_drop_action (mouse_handler.c, lines ~108-131) divides the destination window's own rect into a center 25%-75% box (stack or swap) and four triangular quadrants (top/right/bottom/left "warp" - insert as a new BSP split on that side, via triangle_contains_point). This is a completely different paradigm from edge-of-screen snapping: it's "drop onto a window to react to that window," matching yabai's BSP-tiling model where windows, not screen regions, are the primary target.

MacsyZones - fully freeform, user-authored zones (FancyZones model). Zones are
arbitrary SectionWindows inside a Layout, each with percentage-based bounds
(xPercentage/yPercentage/widthPercentage/heightPercentage relative to the screen), drawn
by the user in an editor. Target selection (getHoveredSectionWindow in
Macsy.swift, partially read lines 195-315) can optionally prioritize a small (100x100pt) hotspot at each zone's center over raw
point-containment, controlled by a prioritizeCenterToSnap setting - i.e., they explicitly
solved the "cursor is inside two overlapping zones, which one wins" ambiguity with a
"nearest center" override rather than pure containment.

Multi-display boundaries. None of the projects examined treat the seam between two
adjacent monitors as a merged/special target. Each screen's zones are computed purely from
that screen's own NSScreen.frame; Rectangle resolves "the current screen" for a drag via
NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) - first match
in NSScreen.screens' (unspecified) order wins (ScreenDetection.swift, partially read, line ~38), so a
pixel that is simultaneously the right edge of one screen and the left edge of an adjacent
one is resolved arbitrarily by array order, not by any deliberate tie-break rule. A
separate spatially-sorted list (order(screens:)) is maintained only for "move to
adjacent display" keyboard actions, not for drag hit-testing. This looks like a latent
edge case in Rectangle itself, not a solved problem to copy - worth treating as an open
question in window-organizer's own design rather than assuming prior art solved it.

---

## 4. The snap itself

Same AX position/size writes window-organizer already uses, plus the same
size-position-size dance, confirmed directly in Rectangle's AccessibilityElement.setFrame
(partially read, lines ~120-220):

    /// Accessibility API only allows size & position adjustments individually.
    /// To handle moving to different displays, we adjust size, position, size again since
    /// macOS will enforce sizes to fit on the current display.
    func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true) {
        ...
        adjustSizeFirst { size = frame.size }
        position = frame.origin
        size = frame.size
    }

(AccessibilityElement.swift, https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift) - this is exactly the "size, position, size" pattern window-organizer's docs already describe, and the comment gives the reason: macOS clamps a size write to fit the window's current display, so if you write the target size before moving to the target display, you can get clamped against the wrong screen's constraints; the final size write after the position change corrects for that. The same function also detects and manages AXEnhancedUserInterface (VoiceOver/Switch-Control compatibility mode) around the write - some apps behave differently under AX writes depending on that flag. getWindowId() in the same file has a derived-hash fallback (deriveWindowId(fromElementHash:)) for apps that don't vend real window ids.

StandardWindowMover.moveWindow (read in full, StandardWindowMover.swift, https://github.com/rxhanson/Rectangle/blob/main/Rectangle/WindowMover/StandardWindowMover.swift) conditionally flips whether size or position is written
first based on which corner is being expanded (shouldAdjustSizeFirst), specifically to
avoid a window jumping across a screen boundary mid-resize for certain corner-cycle
directions.

Apps that refuse the requested size (the minimum-size problem window-organizer already
solved by measurement) get two dedicated mitigations in Rectangle:

- ClampedWindowAligner/EdgeAlignmentWindowMover (read in full, WindowMover.swift, https://github.com/rxhanson/Rectangle/blob/main/Rectangle/WindowMover/WindowMover.swift): after the AX write, re-read the window's actual resulting frame; if it's smaller than the zone (e.g. FaceTime holding a fixed aspect ratio), realign the actual rect against whichever zone edge(s) it shares, or center it if it shares none - rather than leaving the shortfall pinned arbitrarily to one corner. It has a deliberate 1pt tolerance to avoid overcorrecting the common one-point clamp macOS applies near the Dock edge (their comment explicitly calls this out as a "don't chase noise" guard).
- BestEffortWindowMover (read in full, BestEffortWindowMover.swift, https://github.com/rxhanson/Rectangle/blob/main/Rectangle/WindowMover/BestEffortWindowMover.swift): a second-pass safety net - if after resizing the window still overhangs the visible screen bounds, nudge its origin back so it's fully on-screen (never shrinks further, just repositions).

Both mitigations depend on reading geometry back after writing it, matching
window-organizer's own documented rule ("never trust that a window went where you put it").

Animation: only the preview animates in the projects studied; the actual snap-on-release write is an instant, unanimated AX call in every project examined. Rectangle's FootprintWindow grows from a zero-size point anchored at the appropriate corner of the target rect (getFootprintAnimationOrigin) via NSAnimationContext.runAnimationGroup, with duration derived from box.animationResizeTime(rect) times a user multiplier (skippable entirely if the multiplier is 0). No evidence of animated window moves (as opposed to animated overlay) was found in Rectangle or Loop's snap path - Loop does have a WindowTransformAnimation.swift file in its tree (not read in depth - flagging as a gap) which may animate the actual window for some actions, worth a follow-up read before assuming snap-on-release is always instant everywhere.

---

## 5. State and undo

Rectangle keeps a global AppDelegate.windowHistory keyed by CGWindowID, with two
maps: lastRectangleActions[windowId] (what action Rectangle last applied, and the frame
it produced) and restoreRects[windowId] (the frame to go back to). unsnapRestore
(SnappingManager.swift, lines ~320-367) only restores if the window's frame right
before this drag still matches exactly what Rectangle itself last produced
(lastAction.rect == initialWindowRect) - i.e., it refuses to "restore" a window the user
had already manually readjusted since the snap, which would otherwise silently discard their
work. This directly answers "what happens when a snapped window is dragged again": if you
pick up a Rectangle-snapped window and drop it somewhere that isn't a new snap zone (a fast
drag that the footprint never caught), Rectangle restores its pre-snap size while leaving it
at the drop location.

Loop has the equivalent WindowRecords.shared store with getInitialFrame/
eraseRecords. restoreInitialWindowSize (WindowDragManager.swift, lines ~212-243), gated by a restoreWindowFrameOnDrag setting, is more elaborate: it restores the pre-snap size but then runs a three-step fallback to keep the window under the cursor - (1) keep the frame's original maxX, (2) if that still doesn't contain the cursor, keep the drop point as the new left edge, (3) if that still fails, center the window on the cursor. This is worth studying directly as a UX pattern: "restore size, but never let the window teleport out from under the user's grip."

Neither Rectangle nor Loop appears to maintain more than one level of undo (last-applied
frame only, not a stack) - INFERRED from not finding any stack/array-of-history
structure in either codebase, only single-slot dictionaries keyed by window id.

---

## 6. Known pitfalls (from issues and code comments)

- Stage Manager eats left-edge drags. Multiple Rectangle issues - #854, #1200/discussion #1555, #1502 (https://github.com/rxhanson/Rectangle/issues/854, https://github.com/rxhanson/Rectangle/issues/1200, https://github.com/rxhanson/Rectangle/issues/1502; surfaced via WebSearch summaries, not independently re-fetched - treat with slightly less confidence than the direct source reads elsewhere in this document) - report that dragging toward the Stage Manager strip (which lives on the left) gets the window absorbed into Stage Manager instead of Rectangle's left-half snap, repeatedly regressing across macOS point releases. Rectangle's FootprintWindow.isVisible override that special-cases StageUtil.stageEnabled && stageStripShow (line ~50, directly read in source) is a direct scar from this fight, not a hypothetical.
- macOS's own top-edge-opens-Mission-Control gesture fights top-edge snapping. Issue #250 (https://github.com/rxhanson/Rectangle/issues/250, WebSearch summary): dragging to the top edge and lingering ~0.5s pops Mission Control before the user can release. Rectangle's answer is the active-CGEventTap coordinate-rewrite described in section 1a - a real, load-bearing piece of code directly read in source, not a settings toggle alone.
- Fullscreen windows cannot be moved between displays or Spaces at all, because Apple has no public API for it - #782, #16 (https://github.com/rxhanson/Rectangle/issues/782, https://github.com/rxhanson/Rectangle/issues/16; WebSearch summaries). This matches window-organizer's own documented rule to detect and skip/un-fullscreen rather than attempt a move.
- CGEventTap timeout/disable-by-user-input. Both Rectangle's ActiveEventMonitor and Loop's PassiveEventMonitor explicitly handle kCGEventTapDisabledByTimeout/tapDisabledByUserInput in their callback and re-enable the tap (CGEvent.tapEnable(tap:enable:true)) rather than tearing it down (both confirmed directly in source). Rectangle additionally documents why CFMachPortInvalidate must be called on stop even though releasing the Swift reference doesn't deallocate the port - the comment explains that CoreGraphics holds internal references to the CFMachPort, and without an explicit invalidate, the WindowServer keeps the (disabled) tap registration until the process exits, so repeated stop()/start() cycles would otherwise each leak one entry, degrading system-wide input latency once they accumulate (EventMonitor.swift, lines ~102-108). This is a genuinely non-obvious correctness requirement, not boilerplate.
- Permission loss is silent at the API level. CGEvent.tapCreate just returns nil if Accessibility isn't authorized (or was revoked mid-session); there's no thrown error to catch. Any drag-to-snap feature needs its own explicit, user-visible "snapping is off because permission was revoked" state, because the OS gives you nothing to detect this beyond a nil return. (This point about the nil-return behavior is standard, well-documented CGEventTap behavior; I did not find a Rectangle source comment phrased exactly as a quote, so treat the framing here as my own synthesis, not a verbatim citation.)
- AXObserver registration race on newly-launched apps - MacsyZones #89 (https://github.com/rohanrhu/MacsyZones/issues/89), discussed in section 1c: a window isn't snap-aware until its app's AXObserver has been created and its kAXWindowCreatedNotification handled, which can lose a race against the user's first drag of that app.
- Multi-display scale-factor differences: no explicit handling or comment about differing backingScaleFactor across displays was found in any of the six codebases' snap/preview/mover code. INFERRED: this is plausibly a non-issue for the geometry logic itself because the Accessibility API's position/size values, and NSScreen.frame, are in points, not pixels - DPI-independent by construction - but no project comment was found confirming this was a deliberate non-problem versus simply untested. Treat as an open question, not a solved one.
- AeroSpace's window-moving APIs aren't Spaces-aware when "displays have separate Spaces" is on, which is one of the stated reasons AeroSpace avoids native Spaces for its own workspace model and instead simulates workspace switching by hiding/showing windows within one persistent native Space - see the AeroSpace guide (https://nikitabobko.github.io/AeroSpace/guide, Workspaces section). Consequence for window-organizer: leave "which Space is this on" alone until proven necessary; simulating multi-desktop rather than driving real Spaces sidesteps an entire class of unsupported/undocumented API.
- Third-party move/resize tools reportedly don't compose with AeroSpace's own tiling (from a targeted web search of AeroSpace's issue tracker, not source-read): dragging with e.g. Easy Move+Resize "just flickers around and ends up doing nothing" while native title-bar dragging works fine, per user reports in AeroSpace's discussions - a caution that two AX-driven movers fighting over the same window in the same drag gesture can produce visible flicker rather than a clean handoff. This is a search-summary finding, not something verified in source - flagged explicitly as the weakest-sourced item in this document.

---

## 7. Licensing

| Project | License | Can you copy the code? |
|---|---|---|
| Rectangle (rxhanson/Rectangle) | MIT (LICENSE: https://github.com/rxhanson/Rectangle/blob/main/LICENSE, copyright Ryan Hanson 2019-2026, confirmed by direct read) | Yes. MIT permits copying/modifying/relicensing with only an attribution + license-notice requirement. Safe to lift actual Swift, including the mover/snapping classes cited above, into a project under any license (including closed-source), as long as the MIT notice is retained. |
| Loop (MrKai77/Loop) | GPLv3 (LICENSE: https://github.com/MrKai77/Loop/blob/develop/LICENSE, confirmed by direct read) | Copy-paste is legally loaded. GPLv3 is copyleft: if you incorporate Loop's code into window-organizer and distribute the result, the combined work must also be licensed under GPLv3 (source available, same terms) - this applies even to a small excerpted function once it's part of a distributed binary. Safe to study the approach (the event-tap/frame-polling pattern, the preview panel setup, the restore-on-redrag UX) and reimplement independently; not safe to paste WindowDragManager.swift or PreviewController.swift into a differently-licensed codebase. |
| Amethyst (ianyh/Amethyst) | MIT (confirmed via GitHub API) | Yes, same as Rectangle. |
| yabai (asmvik/yabai, formerly koekeishiya/yabai) | MIT (confirmed via GitHub API; repo transferred to new maintainer Asmund Vikane, corroborated by WebSearch - still actively maintained, not a hijack) | Yes - but it's C, and the mouse-drag code (mouse_handler.c) is deeply entangled with yabai's own BSP tree/view/space-manager data structures; legally copyable, not practically without a large rewrite. |
| AeroSpace (nikitabobko/AeroSpace) | MIT (confirmed via GitHub API) | Yes. |
| MacsyZones (rohanrhu/MacsyZones) | GPL-3.0 (confirmed via GitHub API) | Same copyleft caveat as Loop - study the approach (freeform percentage-based zones, center-hotspot tie-break, AXObserver+buttonState-poll drag detection), don't paste the code, unless window-organizer itself becomes GPLv3. |
| Swish | Proprietary, closed source, no public repository | Not applicable - nothing to read or borrow. A GitHub org called "SwishWorks" surfaces in search results claiming to be gesture-window-management source; this is not the official Swish (the real product has no public source) and should be treated as a potential lookalike, not a research source. |
| Tiles | Appears to be commercial/closed; no authoritative open-source repository for "Tiles" the drag-to-edge app was found (search results surfaced unrelated same-named tiling-WM projects). Treat as unresearched, not as "closed and confirmed." |

Bottom line for window-organizer: Rectangle, Amethyst, yabai, and AeroSpace (all MIT) are
safe to borrow code from directly, with attribution. Loop and MacsyZones are GPLv3 - their
ideas are fair game (and in some ways more directly applicable, since Loop in particular is
the closest architectural match to what window-organizer needs), but their code is not,
unless window-organizer is prepared to ship under GPLv3 itself.
