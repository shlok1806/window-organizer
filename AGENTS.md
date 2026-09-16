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

## Building and testing

```sh
cd spike
./build.sh            # builds wdump, wprobe, warrange, wfocus
./tests/run.sh        # golden-file plans
./tests/cli.sh        # exit codes and refusals
./install.sh          # copies binaries to ~/.local/bin
```

**Swift will only accept top-level code in a file named `main.swift`.** `warrange` therefore
lives in `spike/main.swift` and `wfocus` in `spike/focus/main.swift`. Adding a new tool means
a new directory with its own `main.swift`, not a descriptively named file. This has bitten
twice; the error is `statements are not allowed at the top level`.

### The test seam

`warrange --plan-from <fixture.json> --json` plans a **recorded** desktop: no Accessibility,
no clock, no live windows, and it cannot move anything. This is the only seam. Everything
interesting - config loading, scoring, packing, layout, output - runs behind it.

Capture a real desktop as a fixture with `wdump --json`. Any bug report becomes a permanent
regression test by redirect, which is how the 84 fixtures in `audit/` were produced.

A golden case is two files, plus an optional third:

```
tests/cases/<name>.json        the recorded desktop
tests/expected/<name>.json     the plan it must produce
tests/cases/<name>.flags       optional extra flags, e.g. --spill or --master 0.6
```

**Derive expected values from the spec, never from running the code**, or the test passes by
construction and can never disagree with the implementation.

One trap worth knowing: a fixture can pass *before* the fix if its input order happens to
match the buggy behaviour. The eviction-tiebreak case needed a second, reversed fixture to
actually catch anything.

### Hermetic by design

Planning from a fixture uses built-in defaults and never reads `~/.window-spike/`. A test
that depends on whatever the operator last edited is not a test.

## How the layout engine works

Seven stages in `spike/main.swift`:

1. **Gather** - intersect CGWindowList with AX. Refuse if Mission Control is open; skip
   fullscreen and non-settable windows.
2. **Measure** - learn each app's technical minimum by requesting 1x1 and reading the
   refusal. Cached to disk.
3. **Score** - tier and weight from config, the hero (the focused *window*), and a decayed
   focus-recency score.
4. **Effective size** - `max(technical minimum, useful size)`. This is the single definition
   of how small a window may be planned; `effectiveSize()` exists because three call sites
   each had their own idea and one of them contradicted the rule written in this file.
5. **Select and place** - route banish tier onward, optionally reserve a master slab, shelf
   pack into rows, evict and retry until it fits.
6. **Distribute** - water-fill leftover space by weight, honouring caps, returning a capped
   window's unused share to windows that can still use it.
7. **Apply** - save undo, then size, position, size again. Unplaced windows are stowed.

Eviction order is the part that matters most, and every line of it was a bug once:

```
1. unsatisfiable at any size   (else one oversized window empties the desktop)
2. lowest tier
3. lowest recency              (behaviour beats geometry)
4. largest area
5. lowest id                   (oldest; never array order, which is not stable)
```

## State on disk, outside the repo

None of this is version controlled, and all of it is regenerable:

- `~/.window-spike/priorities.json` - per-app tiers, weights, caps, useful sizes. Seeded on
  first run and then owned by the user; loading overlays the file onto built-in defaults so
  a config written by an older version inherits new fields rather than losing them.
- `~/.window-spike/minsizes.json` - measured technical minimums. **Keyed by app, which is
  wrong** - minimums vary per window (#33).
- `~/.window-spike/focus.jsonl` - the recency log. Window ids and timestamps only.
- `~/.window-spike/undo.json` - geometry from the last apply.
- `~/Library/LaunchAgents/com.windoworganizer.wfocus.plist` - the recorder.
- `~/.config/skhd/skhdrc` - hotkeys, inside a marked block that `setup-hotkey.sh` owns.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues, driven by the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
