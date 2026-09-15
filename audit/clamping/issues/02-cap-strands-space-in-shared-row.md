# Per-window height cap strands large blocks of usable space in a shared row

**Severity:** major
**Fixture:** fixtures/09-cap-redistribution-in-row.json
**Command:** `./warrange --plan-from fixtures/09-cap-redistribution-in-row.json --json`

## Expected
The engine's own design comment (main.swift, above `layout()`) states: "Space
freed by a capped window flows back to windows that can still use it." When
Finder (capped at 800x620... actually 760x560, see priority.swift) shares a row
with two uncapped/less-capped windows, the vertical space Finder's cap frees up
should either (a) be redistributed to a window that can use it, or (b) simply
not be allocated to Finder's row-slot in the first place. It should not become
a dead rectangle of usable desktop nobody occupies.

## Actual
Ran:

```
cd spike
./warrange --plan-from fixtures/09-cap-redistribution-in-row.json --json
./warrange --plan-from fixtures/09-cap-redistribution-in-row.json
```

Output (human table):

```
ARRANGE  3 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      685x1085 @0,32        0
  SomeRandomApp       normal   300x200    495x1085 @693,32      0
  Finder              minor    459x252    532x560 @1196,32      0

  dry run - pass --apply to do it
```

JSON:

```
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":1085,"w":685,"x":0,"y":32}},{"app":"Finder","display":0,"id":2,"rect":{"h":560,"w":532,"x":1196,"y":32}},{"app":"SomeRandomApp","display":0,"id":3,"rect":{"h":1085,"w":495,"x":693,"y":32}}],"stowed":[]}
```

All three windows are in the same row (same y=32). WezTerm and SomeRandomApp
both extend the full display height (1085), but Finder is clamped to 560 -
leaving a **532px-wide x 525px-tall block of empty, unusable desktop**
(x:1196-1728, y:592-1117) directly below Finder that nothing else occupies.
Neither WezTerm nor SomeRandomApp grew into it, and Finder wasn't given the
option to use it either (its own cap forbids it, correctly) - the space is
simply lost. On a 1728x1085 display that is roughly 28% of the row's area
gone to waste, immediately adjacent to two windows that could have used
extra width or height.

## Why this is wrong
Row height is shared per-row (one `heights[ri]` value for the whole row,
computed by `waterfill` over `baseH`/`rowWeight`/`rowCap`). Because the row
isn't uniformly capped (only Finder has a height cap; WezTerm/SomeRandomApp
don't), `rowCap` is `nil` for the row and the row height waterfills up to
whatever the tallest/most-weighted row demands (1085 here). Then
(main.swift:351) each item's OWN cap clips its rect after the fact:

```swift
let h = min(heights[ri], w.prio.maxSize?.height ?? heights[ri])
```

This happens per-item, in isolation, after the row height (and hence the
`y` advance for the next row) has already been fixed. There is no mechanism
that gives the pixels clawed back from Finder to any other window in the
row - the redistribution logic in `waterfill` only operates on the values it
computes (per-row height, or per-row-item width); it has no path for
"a single item's cap fired after the shared value was chosen, hand the
difference to a sibling in the same row." The result is dead space that is
neither used nor accounted for as waste anywhere in the output.

## Suggested fix (optional)
Height caps are a per-item concept but height is currently allocated per-row.
Either (a) run the same "capped item frees pool, active items absorb it"
loop that `waterfill` already does for row-level allocation across
individual items within a row too (mirroring how widths are done per-item),
or (b) route a capped window's clawed-back height back into the row's pool
and re-run `waterfill` for the remaining uncapped siblings before finalizing
row height.
