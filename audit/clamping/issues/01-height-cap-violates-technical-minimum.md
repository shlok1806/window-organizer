# Height cap silently overrides a window's own technical minimum

**Severity:** blocker
**Fixture:** fixtures/01-height-cap-below-technical-min.json
**Command:** `./warrange --plan-from fixtures/01-height-cap-below-technical-min.json --json`

## Expected
System Settings is fixtured with `minSize`: 723x700 (a technical minimum from the
fixture, i.e. physics: the app will not accept anything shorter than 700px tall).
Per the engine's own stated rule (main.swift:292-295, "technical minimum larger than
useful size, physics wins"), the planned height should never go below 700.

## Actual
Ran:

```
cd spike
./warrange --plan-from fixtures/01-height-cap-below-technical-min.json --json
```

Output:

```
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":1085,"w":938,"x":0,"y":32}},{"app":"System Settings","display":0,"id":2,"rect":{"h":620,"w":783,"x":946,"y":32}}],"stowed":[]}
```

And the human table:

```
ARRANGE  2 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      937x1085 @0,32        0
  System Settings     minor    723x700    782x620 @945,32       0

  dry run - pass --apply to do it
```

System Settings is placed at height **620**, which is below its own fixtured
technical minimum of **700**. On a real desktop this would clamp back up to
700 on apply and overlap whatever is below/beside it - exactly the failure
mode the rubric calls out ("a window is placed smaller than its TECHNICAL
minimum").

## Why this is wrong
System Settings has a built-in cap of 800x620 (priority.swift: `"System Settings"`
-> `maxSize: cap(800, 620)`). Row height is computed ONCE per row and shared by
every window in that row (main.swift `layout()`, `baseH`/`heights`). Because
WezTerm (the hero) shares the row and hero windows are never capped
(`hero.prio.maxSize = nil`, main.swift:523), the row is not "every window
capped", so `rowCap` is `nil` and the row is free to grow to the full display
height (1085).

Only then, per-window, the code does (main.swift:351):

```swift
let h = min(heights[ri], w.prio.maxSize?.height ?? heights[ri])
```

This clamps System Settings down to its cap (620) unconditionally - it never
checks that System Settings's own `packSize.height` (which already incorporates
its technical minimum of 700, since `packSize = max(minSize, usefulSize)`) is
itself above the cap. The clamp is meant to stop a capped window from stealing
growth space, but it also claws back space the window needed just to meet its
technical minimum in the first place. The result is a placement that violates
physics.

This is not an artifact of sharing a row with an uncapped hero: the same clamp
fires even when the capped window is entirely alone in its own row, with no
sibling to have "stolen" the extra height. See
`fixtures/11-solo-row-technical-exceeds-cap.json`, where Finder (technical
minimum 700x700, cap 800x620) sits in its own row below WezTerm on a tall
1000x1600 display:

```
./warrange --plan-from fixtures/11-solo-row-technical-exceeds-cap.json --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":892,"w":1000,"x":0,"y":32}},{"app":"Finder","display":0,"id":2,"rect":{"h":560,"w":760,"x":0,"y":932}}],"stowed":[]}
```

Finder is placed at height 560, again below its own technical minimum of 700,
even though it has no row-mate to blame. This confirms the clamp at
main.swift:351 is unconditionally wrong whenever `cap.height <
max(minSize.height, usefulSize.height)`, regardless of what else is on
screen.

## Suggested fix (optional)
The per-window clamp should never go below that window's own `packSize.height`:

```swift
let h = max(w.packSize.height, min(heights[ri], w.prio.maxSize?.height ?? heights[ri]))
```

i.e. the cap should only limit how much GROWTH a window gets beyond its base
packSize, never cut into the base itself.
