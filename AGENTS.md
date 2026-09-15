# window-organizer

A macOS utility that reorganises overlapping windows on demand. Unlike a tiling
window manager, it takes over nothing until invoked: one hotkey reads what is
actually on screen, infers what you are doing from app and window titles, and
lays the windows out to match - including deciding which windows do not belong
on screen at all.

## Living documentation

This project uses per-folder agent docs. After any session where you introduce a new module,
dependency, or architectural convention, update the doc closest to where the change lives -
not this file unless the change is project-wide. Write what a future agent could not derive
from reading the code: rules, boundaries, ownership decisions.

Root `CLAUDE.md` is a one-line `@AGENTS.md` import, so project-wide facts belong in this file.

## Window enumeration

Two macOS APIs are each necessary and neither is sufficient. `CGWindowList` knows which windows
are genuinely on screen and in what z-order, but cannot move anything. The Accessibility API can
move windows, but returns every window an app owns, including ones on other Spaces or hidden.

Always intersect the two: CG decides which windows are in play, AX performs the move. Laying out
the raw AX list drags resting off-screen windows (Discord, VPN clients) onto the current screen,
which reads as the app being possessed rather than helpful.

## Resize constraints

Moving a window always succeeds; resizing is negotiated. Apps enforce private minimum sizes
that AX will not report - there is no minimum-size attribute to query. The only way to learn a
minimum is to attempt a small resize, read back what you were given, and restore. Measured on a
1728x1117 display: Outlook 1210x684, Music 980x600, System Settings 723x470, Messages 660x380.

Consequences for any layout engine:

- Gather minimums as hard constraints *before* computing a layout, not as failures discovered
  after applying one. Cache per app; they are stable across launches.
- Equal-split tiling is not generally achievable. Outlook alone needs 70% of the width of a
  14-inch display, and two 980-wide windows cannot share a 1728px row at all.
- When constraints cannot be satisfied on one display, relocating a window to another display
  is the correct resolution - never shrink below a minimum, which silently fails.
- Fullscreen windows refuse both move and resize, and occupy their own Space so `CGWindowList`
  reports them alone. Check `AXUIElementIsAttributeSettable` rather than inferring from a
  failed write, and skip or un-fullscreen them deliberately.
- **Minimums vary per window, not per app.** Outlook's Inbox window needs 1210x684 while its
  compose window needs 640x600. A cache keyed on app name will hand a window a slot it cannot
  occupy; it clamps larger, overruns its neighbours, and one bad entry ruins the whole layout.
- **Never trust that a window went where you put it.** Apply, then read geometry back and
  reflow anything that clamped. Minimize is equally unreliable: a successful
  `AXMinimized` write does not guarantee the window actually minimises.

## Hostile UI states

`CGWindowList` does not always report real geometry, and acting on the wrong numbers is worse
than doing nothing:

- **Mission Control / App Exposé** report *thumbnail* frames for every window. Detect it by a
  `Dock`-owned layer-0 window covering a whole display, and refuse to arrange until it closes.
- **Space transitions** are animated with no API to await. After un-fullscreening, poll until
  the window count is stable across two reads rather than sleeping a fixed guess.

## Permissions

Two separate TCC grants, and neither can be assumed:

- **Screen Recording** gates `kCGWindowName`. Without it macOS silently redacts window titles
  rather than erroring, so probe with `CGPreflightScreenCaptureAccess()` instead of inferring
  from empty strings. Titles are the intent signal, so this is the expensive one to lose.
- **Accessibility** gates every move and resize, checked with `AXIsProcessTrusted()`.

Degrade rather than fail when one is missing: without Screen Recording the layout engine must
fall back to app identity alone.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, driven by the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
