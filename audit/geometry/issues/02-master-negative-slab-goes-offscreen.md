# --master slab math is unguarded against negative width on extremely narrow displays, producing an off-screen placement

**Severity:** polish
**Fixture:** fixtures/09-extreme-tiny-master.json
**Command:** `./warrange --plan-from fixtures/09-extreme-tiny-master.json --master 0.3 --json`

## Expected
Either the placement stays fully inside the display's usable rect (`x >= area.minX`), or the window is
stowed. It should never come out at a negative x when the display's own origin is 0.

## Actual (real pasted output)
```
$ ./warrange --plan-from fixtures/09-extreme-tiny-master.json --master 0.3 --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":600,"w":1,"x":-1,"y":0}}],"stowed":[]}
```
Fixture display usable rect is `{x:0,y:0,w:10,h:600}`. The placement's `x:-1` is outside the display
(`area.minX == 0`), a direct rubric violation ("a placement extends outside the display's usable rect").

For comparison, with no `--master` flag the same fixture correctly stows the window instead of emitting
a bad placement:
```
$ ./warrange --plan-from fixtures/09-extreme-tiny-master.json --json
{"placements":[],"stowed":[{"app":"WezTerm","id":1}]}
```

## Why this is wrong
`masterW = area.width * frac - GAP/2`. With `area.width = 10` and `frac` clamped to the minimum `0.3`,
`masterW = 10*0.3 - 4 = -1`. The hero is then placed with `CGRect(x: area.minX, y: area.minY, width:
min(masterW, ...), height: ...)`, i.e. `CGRect(x: 0, y: 0, width: -1, height: 600)`. `CGRect` silently
"standardizes" a negative width when its `.minX`/`.width` accessors are read (which is what the JSON
encoder uses): `minX` becomes `origin.x + width = -1` and `width` becomes `abs(width) = 1`. So instead of
crashing or refusing, the tool quietly launders a nonsensical negative-width rectangle into a 1px sliver
sitting one pixel to the left of the screen - i.e. off-screen. There is no floor/clamp on `masterW` itself,
only on `frac`.

This only triggers on displays narrower than `GAP/2 / 0.3 ≈ 13.3px` (or `≈4.7px` at the `0.85` clamp
ceiling), which will never occur on real hardware - hence "polish" rather than a higher severity. It is
included because it is a real, reproducible gap in the arithmetic guard rails, and because it demonstrates
that nothing checks `masterW > 0` before using it.

## Suggested fix (optional)
`let masterW = max(0, area.width * frac - GAP / 2)`, and treat `masterW == 0` the same as "hero does not
fit" (stow it) rather than emitting a zero/negative-derived rect.
