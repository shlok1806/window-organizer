Studied Rectangle, Loop, Amethyst, yabai, AeroSpace, and MacsyZones in source. Four distinct drag-detection strategies exist: NSEvent monitor (Rectangle default), listen-only CGEventTap + AX-frame polling (Loop), per-window AXObserver (Amethyst/MacsyZones), and an intercepting HID-level CGEventTap (yabai). None need Input Monitoring beyond Accessibility for mouse-only taps.
Recommend Loop's model for window-organizer: passive event monitor plus polling the AX frame during a native drag, since it needs no event interception and reuses the AX-read path window-organizer already has.
All overlay implementations converge on the same recipe: borderless non-activating panel, transparent, mouse-events-ignored, elevated level, .canJoinAllSpaces - and a kCGWindowLayer != 0 filter should keep it out of window-organizer's own enumerator for free.
Zone models vary widely (fixed grid, aspect-ratio-dynamic, window-relative BSP, freeform user zones); recommend starting with a fixed grid for simplicity and testability.
The size-position-size AX write dance window-organizer already uses is exactly what Rectangle does, with the same documented reason (cross-display clamping).
Biggest pitfall: Stage Manager and Mission Control fight edge-drag gestures and have caused repeated regressions in Rectangle; avoid touching this in v1.
Licensing: Rectangle, Amethyst, yabai, AeroSpace are MIT (code reusable); Loop and MacsyZones are GPLv3 (approach only, not code, unless window-organizer goes GPLv3).
Full detail in FINDINGS.md, COMPARISON.md, RECOMMENDATION.md.
