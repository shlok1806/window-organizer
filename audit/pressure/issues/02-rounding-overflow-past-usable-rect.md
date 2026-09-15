# Per-rect rounding can place a window up to a pixel past the usable rect's bottom edge

**Severity:** minor
**Fixture:** fixtures/09-rounding-overflow-minimal.json
**Command:** `./warrange --plan-from fixtures/09-rounding-overflow-minimal.json --json`

## Expected

Three windows (hero WezTerm, Arc, Ghostty) on a 1728x1085 usable display (origin
0,32). Whatever the plan, no placement rect should extend below `y=32+1085=1117`,
the bottom of the usable area - that is a hard rule from the rubric ("placements ...
extend outside the display's usable rect").

## Actual

```
$ ./warrange --plan-from fixtures/09-rounding-overflow-minimal.json --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":639,"w":748,"x":0,"y":32}},{"app":"Arc","display":0,"id":7,"rect":{"h":639,"w":972,"x":756,"y":32}},{"app":"Ghostty","display":0,"id":20,"rect":{"h":439,"w":1728,"x":0,"y":679}}],"stowed":[]}
```

Ghostty's rect is `y:679, h:439`, so its bottom edge is `679 + 439 = 1118` - one pixel
past the usable bottom edge (`1117`). This was verified programmatically (a small
bounds-check script) and is 100% deterministic/reproducible with this fixture.

## Why this is wrong

`layout()` computes row heights with `waterfill()`, which works in floating point.
For this fixture the two rows' floating-point heights come out to exactly `638.5` and
`438.5` (they must sum to `1085 - GAP` given the display height and weights, and they
do: `638.5 + 438.5 + 8 = 1085.0` exactly - no error in the underlying math).

The bug is at output time. `planJSON()`'s `r()` helper rounds each rect field
independently with `.rounded()` (round-half-away-from-zero). Both `638.5` and `438.5`
sit exactly on a rounding boundary, and *both* get rounded **up** (to `639` and `439`)
because `.rounded()` always rounds `x.5` away from zero for positive numbers - there is
no compensating round-down anywhere. The two independent "round up" choices each add
+0.5px of error, and because the second row's reported height determines whether its
bottom edge fits inside the display, that accumulated +1px pushes Ghostty's bottom
edge outside the usable rect.

This is a different bug from the acknowledged "off-screen overflow not counted as
waste by the mess metric" issue - that one is about a scoring heuristic under-counting
overflow that already exists elsewhere; this is the layout engine's own output
geometry genuinely violating the display bounds it was asked to pack into, for pure
rounding reasons, with no metric involved. It reproduces with a plain 3-window fixture
under real "many windows competing for space" pressure (waterfill pool splitting
across rows), not a contrived one-off.

Given GAP is only 8px, this kind of accumulated per-row/per-column rounding error can
in principle compound further with more rows/columns sharing similarly-fractional
pool splits, though 1px is the worst observed here.

## Suggested fix

Round positions and sizes together per row/column so the cumulative rounded height/width
never exceeds the float total (e.g. round `y` and `y + h` and derive `h` as the
difference, rather than rounding `h` independently), or clamp the final row/column's
bottom/right edge to `area.maxY` / `area.maxX` after rounding.
