# One oversized window collapses the entire plan to empty, even with room to spare

**Severity:** blocker
**Fixture:** fixtures/01-hero-oversize-wipes-desktop.json
**Command:** `./warrange --plan-from fixtures/01-hero-oversize-wipes-desktop.json --json` (also run without `--json` for the human table)

## Expected

The fixture has a focused Xcode window (useful size 900x600, policy width wider than
the 850px-wide display) plus four small minor-tier windows (Slack, Messages, Finder,
Calendar) on a display that is 850x2000 usable. The four minor windows alone easily
fit stacked in a single 850-wide column (their combined minimum heights add up to well
under 2000px, as the tool's own diagnostic admits). The worst defensible outcome is:
stow Xcode alone (its policy width doesn't fit at 850px), place the other four.

## Actual

Table output:

```
ARRANGE  5 windows, 1 display, hero: Xcode

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  Xcode               hero     200x150    -                     cannot fit
  Slack               minor    400x300    -                     cannot fit
  Messages            minor    250x300    -                     cannot fit
  Finder              minor    300x200    -                     cannot fit
  Calendar            minor    400x300    -                     cannot fit

  5 windows cannot fit without overlap on this display.
  stacked minimum heights: 1250px vs 2000px usable

  dry run - pass --apply to do it
```

JSON output:

```
{"placements":[],"stowed":[{"app":"Xcode","id":20},{"app":"Slack","id":21},{"app":"Messages","id":22},{"app":"Finder","id":23},{"app":"Calendar","id":24}]}
```

Every single window is stowed. The tool's own diagnostic line even says the stacked
minimum heights (1250px) comfortably fit the 2000px usable height - it is telling the
user there was room, and still produced a completely empty plan.

## Why this is wrong

`pack()` (main.swift) checks, for every window in the candidate list in turn:
```
if w.packSize.width > area.width { return nil }         // wider than the display
```
This means a single window whose *useful* width (a policy choice, not a technical
minimum - see the comment at priority.swift:21-24) exceeds the display's width makes
`pack()` fail for the **whole candidate set**, regardless of how many other windows
would have fit fine together.

The caller's eviction loop then repeatedly removes the *worst-tier* candidate and
retries `pack()` on everyone else - but since the oversized window's presence alone
keeps killing `pack()`, and it is the *hero* (rank 0, i.e. never picked as "worst"
until it's the only one left), the loop evicts every other window one at a time before
finally reaching the hero and evicting it too. The net effect: an oversized *hero*
window can wipe out an otherwise-fine layout for every other window on the desktop,
leaving a completely blank, empty plan - the worst possible outcome under the rubric
("the engine ... produces an empty/partial plan", "large empty screen regions remain
while windows are stowed", and it would obviously astonish a user watching their whole
desktop vanish because one window's *preferred* size didn't fit).

This is a distinct failure mode from the acknowledged "eviction is greedy by (tier
rank, then area)" issue: that issue is about which single victim gets picked when
`pack()` legitimately can't fit everyone. This bug is that `pack()` itself conflates
"one item is individually oversized" with "the whole set doesn't fit," so a single
oversized window poisons every subsequent packing attempt until literally everything
is gone, even other windows that never competed with it for the same row/column.

## Suggested fix

Before running the shelf-packing loop, filter out (and stow immediately) any window
whose `packSize.width` exceeds `area.width` on its own - don't let its presence make
`pack()` return `nil` for combinations it isn't even part of. Then pack the remaining,
individually-fittable windows as usual.
