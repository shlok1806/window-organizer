# Minor-tier windows have no real height cap, so spill lets them balloon to 100% of a display's height

**Severity:** major
**Fixture:** fixtures/minor-uncapped-height.json
**Command:** `./warrange --plan-from fixtures/minor-uncapped-height.json --master 0.9 --spill --json`

## Expected
`priority.swift` documents the "minor" tier explicitly: *"useful but reference-only -
capped so it stops stealing space"*. Slack is minor-tier with `maxSize: cap(820)`
(width-only cap, per the source). A reference/glance app like Slack, when it lands alone
on a spilled secondary display, should stay a modest reference-sized window - not consume
the entire vertical real estate of that display.

## Actual
Fixture: 1280x800 primary, 2560x1440 secondary. WezTerm (hero) is forced to consume most
of the primary via `--master 0.9`, leaving no room for Slack there, so `--spill` pushes
Slack alone onto the secondary.

```
$ ./warrange --plan-from fixtures/minor-uncapped-height.json --master 0.9 --spill --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":775,"w":1084,"x":0,"y":25}},{"app":"Slack","display":1,"id":2,"rect":{"h":1440,"w":820,"x":1280,"y":0}}],"stowed":[]}
```

Human table for the same run:

```
$ ./warrange --plan-from fixtures/minor-uncapped-height.json --master 0.9 --spill

ARRANGE  2 windows, 2 displays, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      1084x775 @0,25         0
  Slack                minor    300x300    820x1440 @1280,0      1

  dry run - pass --apply to do it
```

Slack's width does respect its cap (820), but its height is 1440px - literally 100% of the
secondary display's full usable height. A chat app sized as a floor-to-ceiling 1440px-tall
slab is the opposite of "reference-only, capped so it stops stealing space." The same
reproduces for Discord and for stacked-vertical layouts (see
`fixtures/stacked-vertical.json`, where both Slack and Discord independently get placed at
the full 1080px height of a stacked secondary display).

## Why this is wrong
`priority.swift`'s `cap()` helper is `private func cap(_ w: CGFloat, _ h: CGFloat = 4000)`
- height defaults to 4000 if not given. Every minor-tier chat app in
`defaultPriorities` (Slack, Messages, Discord) only passes a width to `cap()`:

```
"Slack":    Priority(tier: "minor", weight: 1.0, maxSize: cap(820), usefulSize: useful(600, 500)),
"Messages": Priority(tier: "minor", weight: 0.7, maxSize: cap(560), usefulSize: useful(400, 500)),
"Discord":  Priority(tier: "minor", weight: 0.8, maxSize: cap(900), usefulSize: useful(600, 500)),
```

so their effective height cap is 4000px - i.e. no real cap on any usable display. Compare
this to the other minor-tier entries (Finder, System Settings, Activity Monitor, Calendar)
and every banish-tier entry, which all pass an explicit, reasonable height to `cap()` and
are correctly bounded. This is an inconsistency within the minor tier itself, not a
tier-wide design choice: three of the seven minor/banish-adjacent apps are simply missing
their height cap.

This is exactly rubric bullet "the outcome is defensible but would astonish a user": a
user running `--spill` to tidy up expects a reference app like Slack to land as a small
side panel on the spare display, not to seize the entire monitor.

## Suggested fix (optional)
Give Slack, Messages, and Discord an explicit height cap in `defaultPriorities` (e.g.
`cap(820, 700)` for Slack), matching the pattern already used by Finder, System Settings,
Activity Monitor, Calendar, Music, Spotify, and TV.
