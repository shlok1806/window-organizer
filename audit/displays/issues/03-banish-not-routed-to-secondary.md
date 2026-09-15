# Banish-tier apps are not routed to a secondary display; they stay on the primary whenever there's room

**Severity:** major
**Fixture:** fixtures/banish-stays-on-primary.json
**Command:** `./warrange --plan-from fixtures/banish-stays-on-primary.json --spill --json`

## Expected
`priority.swift`'s own tier documentation: *"banish  noise - sent to secondary display,
shrunk cap"*. A banish-tier app (Music/Spotify/TV) is meant to end up on another display
whenever one exists, precisely because it is "noise" that shouldn't share the primary with
real work.

## Actual
Fixture: 1280x800 primary with WezTerm (hero) and Music (banish); 1920x1080 secondary that
is completely empty of any window. There is ample room for both WezTerm and Music
side-by-side on the primary, so nothing ever gets evicted.

```
$ ./warrange --plan-from fixtures/banish-stays-on-primary.json --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":800,"w":851,"x":0,"y":32}},{"app":"Music","display":0,"id":2,"rect":{"h":440,"w":421,"x":859,"y":32}}],"stowed":[]}

$ ./warrange --plan-from fixtures/banish-stays-on-primary.json --spill --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":800,"w":851,"x":0,"y":32}},{"app":"Music","display":0,"id":2,"rect":{"h":440,"w":421,"x":859,"y":32}}],"stowed":[]}
```

Identical output with or without `--spill`. Human table:

```
$ ./warrange --plan-from fixtures/banish-stays-on-primary.json --spill

ARRANGE  2 windows, 2 displays, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      850x800 @0,32         0
  Music                banish   200x150    421x440 @858,32       0

  dry run - pass --apply to do it
```

Music (banish) is planted directly beside the hero on the primary display, while the
entire 1920x1080 secondary display is left completely unused - not mentioned anywhere in
the plan.

## Why this is wrong
The implementation never special-cases the banish tier for display assignment. The only
thing that pushes a window to another display is the eviction loop inside the per-display
`while !candidates.isEmpty` block in main.swift, and that loop only runs when `pack()`
fails to fit everyone on the current display - i.e. banish-tier windows only move to a
secondary display as an accidental side effect of crowding, and only when `--spill` is
also given. If there's slack on the primary (as there almost always will be for a single
small "noise" window), banish tier gets no different treatment than "normal" tier: it just
sits wherever `pack()`'s shelf algorithm drops it, which is typically right next to the
hero.

This directly matches rubric bullet 2 - "a window is placed on a display that makes no
sense" - measured against the tool's own stated intent for the tier ("sent to secondary
display"), and is one of the explicit things this audit was asked to check: "whether
banish-tier apps actually end up on the secondary." They do not, except by accident under
crowding.

## Suggested fix (optional)
When more than one display is available (regardless of whether the primary is crowded),
proactively route banish-tier windows to `areas[1]` (or the least-loaded non-primary
display) before running the primary's packing pass, rather than relying on eviction to
discover this only when the primary happens to be full.
