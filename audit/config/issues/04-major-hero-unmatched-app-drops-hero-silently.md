# `--hero <app not on screen>` silently drops the hero designation from every window while still claiming it worked

**Severity:** major
**Fixture:** fixtures/25_valid_base.json
**Command:** `./warrange --plan-from fixtures/25_valid_base.json --hero Nonexistentapp`

## Expected
If `--hero` names an app that is not present among the planned windows, the tool should
either error out, or at minimum warn that the requested hero could not be found and fall
back to the default hero selection (e.g. the focused window / the natural built-in hero
tier) rather than losing the hero designation altogether.

## Actual (paste REAL output you actually ran, including exit code)
Baseline, no `--hero` flag:
```
$ ./warrange --plan-from fixtures/25_valid_base.json

ARRANGE  2 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      748x1085 @0,32        0
  Safari              normal   200x200    972x1085 @756,32      0

  dry run - pass --apply to do it
EXIT=0
```

With `--hero Nonexistentapp`:
```
$ ./warrange --plan-from fixtures/25_valid_base.json --hero Nonexistentapp

ARRANGE  2 windows, 1 display, hero: Nonexistentapp

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             normal   24x29      748x1085 @980,32      0
  Safari              normal   200x200    972x1085 @0,32        0

  dry run - pass --apply to do it
EXIT=0
```

## Why this is wrong
Around main.swift:504-524:
```swift
for w in wins where w.prio.tier == "hero" { w.prio.tier = "normal" }  // demote built-in hero
if let hero = wins.first(where: { $0.app == heroApp }) {
    hero.prio.tier = "hero"
    hero.prio.weight = max(hero.prio.weight, 3.0)
    hero.prio.maxSize = nil
}
```
The code unconditionally demotes whichever window would naturally be "hero" (WezTerm has
a built-in hero tier in `defaultPriorities`), then tries to re-promote whichever window
matches `heroApp`. When `heroApp` matches nothing, the re-promotion silently does
nothing - the result is a plan with **no hero window at all**, and the layout/order
visibly changes (WezTerm moves from x=0 to x=980, both windows drop to "normal" tier).
Yet the header confidently prints `hero: Nonexistentapp`, as if the request succeeded.
This is precisely "malformed input is silently accepted and produces a confident, wrong
plan" - a simple typo in an app name (e.g. "Wezterm" vs "WezTerm", case-sensitive
matching) silently downgrades the user's actual terminal/IDE window and produces a
materially different, worse layout with no indication anything went wrong.

## Suggested fix (optional)
When `--hero <app>` is given but no window matches, print a warning ("no window named
'<app>' found; using default hero selection") and fall back to the normal hero-selection
path instead of leaving every window demoted.
