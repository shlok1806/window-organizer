# --master gives the hero a slab narrower than its own useful size, on ordinary laptop displays

**Severity:** major
**Fixture:** fixtures/10-laptop-1280x800-master03.json (also reproduces with fixtures/01-tiny-800x600-master03.json)
**Command:** `./warrange --plan-from fixtures/10-laptop-1280x800-master03.json --master 0.3 --json`

## Expected
Everywhere else in the engine, a window is only PLACED if its slot meets its
`usefulSize` on both axes ("a slot cannot be given a window it makes
useless" is the design's own stated rule - see `pack()`, which stows a
window rather than cramming it below its useful size). WezTerm's built-in
useful size is 640x400. A `--master` slab handed to the hero should
therefore either be at least as wide as the hero's useful width, or the
hero should be stowed/warned about - not silently squeezed thinner than the
tool itself considers usable.

## Actual (real pasted output)
```
$ ./warrange --plan-from fixtures/10-laptop-1280x800-master03.json --master 0.3
ARRANGE  2 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      380x775 @0,25         0
  Safari              normal   200x100    -                     cannot fit

  1 window cannot fit without overlap on this display.
  stacked minimum heights: 129px vs 775px usable

  dry run - pass --apply to do it

$ ./warrange --plan-from fixtures/10-laptop-1280x800-master03.json --master 0.3 --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":775,"w":380,"x":0,"y":25}}],"stowed":[{"app":"Safari","id":2}]}
```

Arithmetic check: usable area is `{x:0,y:25,w:1280,h:775}`. `masterW = area.width * frac - GAP/2 = 1280*0.3 - 4 = 380`,
which matches the emitted `w:380` exactly - inside its own display and non-overlapping, so it passes the
bounds/overlap checks, but the hero itself is broken: 380px is well below WezTerm's declared useful width
of 640px.

The same formula breaks at `--master 0.5` too (barely): `1280*0.5 - 4 = 636 < 640`:
```
$ ./warrange --plan-from fixtures/10-laptop-1280x800-master03.json --master 0.5 --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":775,"w":636,"x":0,"y":25}}],"stowed":[{"app":"Safari","id":2}]}
```

And it is much worse on a smaller-but-real display (800x600 usable 800x575), where `--master 0.3` gives the
hero only 236px:
```
$ ./warrange --plan-from fixtures/01-tiny-800x600-master03.json --master 0.3 --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":575,"w":236,"x":0,"y":25}}],"stowed":[{"app":"Safari","id":2}]}
```

## Why this is wrong
`main.swift`'s `--master` branch (around line 547-564) computes `masterW = area.width * frac - GAP/2` and
places the hero at `width: min(masterW, hero.prio.maxSize?.width ?? masterW)` with **no floor against
`hero.prio.usefulSize.width` (or even `hero.minSize.width`)**. Every other placement path in this codebase
(`pack()`) refuses to place a window into a slot smaller than its useful size and stows it instead - that
is the tool's stated design philosophy ("present but unusable is not a better outcome than not here" per
the comment above `packSize`). The master-slab path bypasses that gate entirely, so the *one* window the
whole feature exists to showcase (the hero) is the one window allowed to be squeezed unusably thin. On a
1280-wide display (a completely ordinary laptop/external-monitor width) this triggers at both of the
documented low-end fractions (0.3 and 0.5), i.e. two of the four fractions the audit was asked to check.
This is exactly the kind of outcome that would astonish a user: they pass `--master 0.3` expecting "give my
hero window a slab of the screen" and instead get a squashed 380px-wide terminal.

## Suggested fix (optional)
Clamp `masterW` to be at least `max(hero.prio.usefulSize.width, hero.minSize.width)` before using it, and
if the display is too narrow to honor that floor, fall back to giving the hero the whole display (single
column) rather than an unusably thin slab - consistent with how `pack()` treats every other window.
