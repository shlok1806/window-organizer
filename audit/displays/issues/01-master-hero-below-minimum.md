# --master forces the hero below its technical minimum size, even with --spill and a fitting secondary sitting right there

**Severity:** blocker
**Fixture:** fixtures/master-realistic-minsize.json
**Command:** `./warrange --plan-from fixtures/master-realistic-minsize.json --master 0.3 --spill --json`

## Expected
`--master` reserves a fraction of the primary display's width for the hero. Every other
placement path in this engine (`pack()`) refuses to place a window below its useful size,
and never below its technical `minSize` at all. So the hero slab should either (a) be at
least the hero's minSize/usefulSize, or (b) if the slab is too small, fall back to normal
packing / spill the hero to a display that can actually hold it - the same courtesy every
other window gets.

## Actual
Fixture: 1280x800 usable primary, 1920x1080 usable secondary. Hero is iTerm2 with a
perfectly realistic technical minimum of 720x400 (declared in the fixture's `minSize`).
`--master 0.3` is not an extreme value - 0.3 is the tool's own documented lower clamp
bound (`let frac = min(0.85, max(0.3, fracArg))` in main.swift).

```
$ ./warrange --plan-from fixtures/master-realistic-minsize.json --master 0.3 --spill --json
{"placements":[{"app":"iTerm2","display":0,"id":1,"rect":{"h":800,"w":380,"x":0,"y":32}},{"app":"Safari","display":1,"id":2,"rect":{"h":1080,"w":1200,"x":1280,"y":0}}],"stowed":[]}
```

Human table for the same run (without --spill, showing the MINIMUM column is right there
and simply not checked):

```
$ ./warrange --plan-from fixtures/master-realistic-minsize.json --master 0.3

ARRANGE  2 windows, 2 displays, hero: iTerm2

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  iTerm2              hero     720x400    380x800 @0,32         0
  Safari              normal   200x150    -                     cannot fit

  1 window cannot fit without overlap on this display.
  stacked minimum heights: 550px vs 800px usable

  dry run - pass --apply to do it
```

iTerm2's declared technical minimum width is 720px; the plan gives it 380px - 340px
*below* the minimum the app will even accept. This is not a rounding-error-sized miss,
it's nearly half the required width missing.

Crucially, adding `--spill` (first run above) does not rescue the hero even though the
1920x1080 secondary display is sitting completely idle right next to it - `--spill` only
gets applied to the *non-hero* remainder (`remaining = wins.filter { $0 !== hero }`), the
hero's slab is placed unconditionally on `areas[0]` before spill logic ever runs.

## Why this is wrong
Look at the code path (main.swift, the `--master` block): `masterW = area.width * frac -
GAP / 2` is computed purely from the display's width and the frac argument. It is then
clamped only against the hero's own `maxSize` (which is `nil` for every hero-tier app -
hero is never capped) - never against `hero.minSize` or `hero.prio.usefulSize`, the two
numbers this engine uses everywhere else to decide whether a placement is even legal.
Contrast with `pack()`, which unconditionally refuses (`return nil`) any placement whose
`packSize.width > area.width`.

If this plan were ever applied, the OS/AX layer would refuse to shrink iTerm2 below its
real minimum (per this tool's own comment: "window came back exactly the original size -
that's a refusal, not a minimum"), so the actual on-screen result would silently diverge
from the reported plan - and, worse, the reserved "stack" region computed alongside it
(`stackX = area.minX + masterW + GAP`) would then likely overlap the hero once the OS
clamps it back up, since that region's geometry was derived from the too-small slab.

This is squarely rubric violation #1 ("a window is placed at a size where its content
would be unusable") taken to its extreme: the window is placed at a size smaller than the
app will even physically permit, silently, while a full 1920x1080 secondary that could
easily fit the hero sits empty one line down in the same JSON output.

## Suggested fix (optional)
Before committing to the master slab, check `masterW >= hero.minSize.width` (and the
height too). If it doesn't fit, either fall back to ordinary weighted packing for the hero
on that display, or - when `--spill` is set - let the hero participate in the normal
spill-eviction loop like every other window instead of being placed unconditionally
before that loop starts.
