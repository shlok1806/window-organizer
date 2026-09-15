# Hero status follows the app name, not the focused window - wrong window instance becomes hero when two windows share an app

**Severity:** blocker
**Fixture:** fixtures/hero-mismatch.json
**Command:** `./warrange --plan-from fixtures/hero-mismatch.json --json` (and without `--json` for the table)

## Expected
The spec says: "Exactly one window `focused: true`; it becomes the hero." In the fixture, window id 3
("work (FOCUSED, newer)", app WezTerm) is the only window with `focused: true`. It should receive
hero tier (rank 0, weight >= 3, uncapped) and the dominant slot. Window id 1 ("scratch (unfocused,
older)", also app WezTerm) should be treated as an ordinary normal-tier WezTerm window since it is
not focused.

## Actual
Ran:
```
./warrange --plan-from fixtures/hero-mismatch.json
```
Output:
```
ARRANGE  3 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  --------------------------------------------------------------------------
  WezTerm             hero     24x29      748x638 @0,32         0
  Safari              normal   200x200    972x638 @756,32       0
  WezTerm             normal   24x29      1728x438 @0,678       0

  dry run - pass --apply to do it
```
JSON:
```
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":639,"w":748,"x":0,"y":32}},{"app":"Safari","display":0,"id":2,"rect":{"h":639,"w":972,"x":756,"y":32}},{"app":"WezTerm","display":0,"id":3,"rect":{"h":439,"w":1728,"x":0,"y":679}}],"stowed":[]}
```
`id: 1` (the unfocused, older WezTerm window) got the hero slot (top-left, 748x638, tier hero).
`id: 3` (the actually-focused window the user is looking at) was placed as a plain normal-tier
window in a short 1728x438 strip at the bottom, exactly like Safari.

## Why this is wrong
In `main.swift`, the hero app name is taken from the first focused window, then the hero object is
looked up again by app name:
```swift
if let hero = wins.first(where: { $0.app == heroApp }) {
    hero.prio.tier = "hero"
    ...
}
```
`heroApp` is only an app *name* string, and `wins.first(where: { $0.app == heroApp })` returns the
first window in the input array whose app matches that name - not the actual window object that had
`focused: true`. When a user runs two windows of the same hero-tier app (extremely common for
WezTerm/iTerm2/Terminal/Code/Cursor - the exact apps this tool special-cases as "hero" apps),
whichever one of them appears earlier in the enumeration order wins the hero slot, regardless of
which one is actually focused. The window the user is currently working in can be silently demoted
to a cramped strip while a stale, unfocused window of the same app is given the premium slot. This
would astonish a user - it defeats the entire purpose of the hero mechanism for the most common
power-user case (multiple terminal windows), and it is not one of the six documented known issues
(which concern birth recency, eviction ordering, cached minimum sizes, no post-apply verification,
off-screen waste, and focus recency across runs - not misidentifying which window is the focused
one among duplicate-app windows).

## Suggested fix (optional)
Track focus by object identity (or window `id`) rather than by app name: find the actual window
whose `focused == true` and mark that window as hero, e.g. `wins.first(where: { $0.focused })`
instead of `wins.first(where: { $0.app == heroApp })`.
