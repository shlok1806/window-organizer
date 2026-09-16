# Context

The vocabulary this project uses. These words appear in code, issues, commits and tests, and
several of them mean something narrower here than in ordinary use. Use these terms rather
than synonyms; if you need a concept that is not here, either you are inventing language the
project does not use, or there is a real gap worth adding.

## The two views of a window

**CG view** - what `CGWindowList` reports: which windows are genuinely on screen, their
z-order, and a stable **window id**. Cannot move anything.

**AX view** - what the Accessibility API reports: every window an app owns, including ones
resting on other Spaces. Can move windows. Has no window id.

Neither is sufficient. They are always **intersected**: CG decides who is in play, AX does
the moving.

## Sizes

**Technical minimum** - the size an app will actually accept. Physics. Discovered by asking
for a 1x1 window and reading back the refusal, because macOS exposes no attribute for it.

**Useful minimum** - the size below which the window is worthless to a human. Policy,
declared per app in configuration, never measured. A browser will happily *accept* 574x220
and show you three lines of text.

**Effective size** - `max(technical, useful)`. The single definition of how small a window
may be planned. Nothing may place a window below it: not the packer, not a cap, not the
master slab. Where the two disagree, physics wins.

**Cap** - a per-app maximum. A music player does not need a monitor. Caps apply only *above*
the effective size; a cap may never push a window below what it will accept.

## Intent

**Tier** - what a window is worth, one of four:

| Tier | Meaning |
|---|---|
| `hero` | the thing you are actually doing |
| `normal` | real work |
| `minor` | reference material, capped so it stops stealing space |
| `banish` | noise, sent to another display when one exists |

In configuration, `hero` is an appetite hint - it grants weight, not the hero slot.

**Hero** - exactly one *window*: the one you are focused in, or the one named by `--hero`.
Never resolved by app name; an app usually has several windows and picking the first is
usually picking the wrong one.

**Weight** - share of leftover space, once every window has its effective size.

**Recency** - a decayed focus score, summed over events in the focus log. Decay rather than
a cutoff, so relevance fades smoothly and many brief visits can rank alongside one long one.

## Layout

**Plan** - the decision: which windows are placed, where, on which display, and which are
stowed. Produced without touching anything.

**Placement** - one window's target rect within a plan.

**Stow** - remove a window from the screen rather than place it at a size that is no use.
Currently implemented as minimise. "Present but unusable" is not a better outcome than "not
here", but note that users read a minimise as *closed*.

**Master slab** - the fixed portion of a display reserved for the hero, with everything else
packed into the remainder, called the **stack**. The requested fraction is a preference, not
a promise: the slab shrinks rather than starve the stack.

**Shelf packing** - the row-based algorithm. Windows fill a row while width allows, then a
new row starts. A window's vertical neighbour is therefore often a whole row, not a single
window.

**Water-filling** - how leftover space is shared: distribute by weight, and when a window
hits its cap, its unused share flows back to windows that can still use it.

**Eviction** - removing a window from consideration when the set does not fit, repeated
until it does. Greedy today, which is a known weakness (#35).

## Testing

**Fixture** - a recorded desktop: displays, windows, their measured minimums, a focus
history, and a fixed current time. Replayable with `--plan-from`.

**Replay** - planning from a fixture. No permissions, no clock, no live windows, and
structurally incapable of moving anything.

**Golden case** - a fixture plus the plan it must produce.

## Measurement

**Mess metrics** - what `wdump` reports about a desktop: how much of the screen is covered,
how much is stacked two or more deep, how many windows are more than half buried, and the
headline number - **hidden pixels**, the proportion of rendered window area you cannot see.

**Off-screen overflow** - window area pushed past a display edge. Counted as waste, because
a window half off the screen is exactly as useless as one buried underneath another.
