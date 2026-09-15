# Verdict: does the differentiation hold up, and is the stow behavior safe?

## Short answer
The differentiation is real but narrower than "nobody does content-aware
layout." Nobody ships the *combination* window-organizer describes -
automatic per-app tiers driving space allocation, a measured (not guessed)
useful-minimum distinct from the technical minimum, and full automatic stow
as a first-class outcome, invoked on demand rather than running always-on.
Each individual ingredient already exists somewhere in the market, just
never assembled, and never with the "useful minimum" piece at all. That
makes this a synthesis/product-design bet, not a technically novel
capability nobody has thought of. Whether that's "enough" differentiation is
a judgment call - see the closing section.

## Where the closest competitors actually stand

**yabai and AeroSpace are the closest in spirit, not in outcome.** Both let
you write rules that say "this app is different" - float it, ignore it,
pin it to a space, set its opacity. That is the same fundamental move as
window-organizer's hero/normal/minor/banish tiers: the tool has an opinion
about what an app *is*, not just where it sits. But the resemblance stops
at "has an opinion." Neither probes a real minimum size (there is no
technical-vs-useful distinction in either project at all), neither weighs
space allocation, and neither will look at an app, decide it does not
deserve any of the display, and remove it. Their rules are static,
user-authored, and binary (managed/unmanaged) - not computed at layout
time from what's actually on screen and how much room is left. Getting
from "yabai rule that floats Music" to "warrange decides Music gets zero
pixels because a music player's content isn't display-worthy, measures
that the browser needs 400px to be legible, and stows anything left over"
is a real step, not a rebrand.

**Moom's saved per-app arrangements** are the closest thing to "per-app
policy" among the pure drag-snap tools, but they are user-authored static
positions you have to build by hand per app, with no measurement and no
automatic decision about whether a window deserves space at all.

**Loop's Stash** is the closest shipped, popular *stow* mechanic - and it
is evidence people will use a "shove this off-screen, get it back on
hover/keybind" feature (10k+ stars, active use). But it's manual and
per-window: the user picks what gets stashed. Nothing in this survey lets
the *software* decide a window doesn't deserve space and act on that
decision automatically - which is exactly what "banish" does. That is the
one piece of window-organizer's design with no real product precedent at
all, anywhere in this survey. It is also, correspondingly, the piece with
the least evidence either way about how it will be received.

**Apple's own built-in tiling already does an unpoliced version of "windows
disappear."** Past four windows, extras silently stack underneath with no
visible rule for which ones. This is the closest thing to an existing
mass-market precedent for "some windows just don't make the cut" - and
notably, reviewers treated it as a limitation to route around, not as a
delight. That's mild negative evidence on the *acceptability* question, but
it's also an apples-to-yabai comparison in one important way: it's an
unannounced, silent degradation with no visible logic, not a legible,
intentional, on-demand decision.

**Hammerspoon** confirms the underlying need is real - power users have
built exactly this kind of app-priority logic for themselves in Lua - but
as personal scripts, never as a product with a UI or a default policy. That
is validation of the itch, not competitive pressure.

## Is "press a key and some windows disappear" something users will accept?

The strongest and most directly relevant precedent is **Stage Manager**,
and the reaction there is a real warning sign: one detailed first-person
account describes enabling it and having every open window vanish off the
left edge except the most recent, calling their carefully arranged windows
"decimated," and disabling the feature within minutes despite having seen
demos beforehand. That account is not an outlier framing - multiple pieces
describe Stage Manager as having "landed itself in a heap of criticism"
for being fiddly, rigid, and built around a workflow assumption (one app
group visible at a time) that doesn't match how many people actually want
to work (everything visible, all the time - the exact opposite of what
Stage Manager enforces).

But the failure modes are not the same, and the differences matter:

- **Stage Manager is an ambient mode change** - once on, it reshapes every
  window interaction going forward, unpredictably, with a "where did my
  windows go" learning curve. **window-organizer is invoked** - nothing
  happens until the hotkey is pressed, exactly once, on demand. That is
  structurally much closer to Loop's Stash (accepted, popular) than to
  Stage Manager's always-on reshaping (rejected by a meaningful, vocal
  slice of users).
- **Stage Manager gives poor legibility and recovery** - users reported not
  knowing where windows went or how to get the arrangement back. Loop's
  Stash and window-organizer's own `--undo` both solve exactly this: a
  known, discoverable way back. This is the single most important variable
  in whether "windows disappearing" reads as helpful or hostile, and it is
  also the variable most within the product's control.
- **The genuinely untested part is *automatic, unsolicited* selection.**
  Loop's Stash is accepted because the user chooses what to hide. Stage
  Manager's ambient reshaping is rejected partly because of *when* it acts,
  not just *what* it does. Banish is neither: it is invoked (good) but the
  software - not the user - decides per-window whether it's worth
  displaying at all (untested). No tool in this survey does that. It is
  plausible users accept it exactly because it is invoked and undoable; it
  is equally plausible that the first time a real window a user actually
  wanted gets banished without being asked, it reads as presumptuous in
  the same way Stage Manager did. Nothing found here can settle this
  either way - it needs to be tested with users, not argued from analogy.

**What would de-risk it, based on the evidence above:** make every banish
decision legible at the moment it happens (which app, why, one keypress to
override just that one window) and keep `--undo` as cheap and reliable as
it already is. The Stage Manager backlash was not really about "windows
went away" in the abstract - people minimize and hide windows constantly
without complaint - it was about *ambient, opaque, hard-to-reverse* windows
going away. Avoid those three adjectives and the closest bad precedent
mostly doesn't apply.

## What would have to be true for the differentiation to matter commercially

1. **The useful-minimum gap has to actually get built**, not stay a known
   gap. Right now the README's own "Known gaps" section admits the exact
   claim in the pitch - stowing rather than placing at a useless size - is
   not yet true ("a browser can be placed at 222px tall: present, and
   worthless"). Until that closes, the differentiation is aspirational, not
   shipped.
2. **Per-window (not per-app) minimum caching has to close too.** The
   Outlook inbox/compose example in the project's own docs is a real
   correctness bug today, and it undermines the "we understand what your
   windows are" claim if a second window of a known app still gets
   clamped into an unusable slot.
3. **The interaction model (hotkey-only, no drag-snap) has to be an
   accepted trade, not a stopgap.** Every competitor surveyed treats
   drag-to-snap as the baseline expectation. Shipping without it is a
   legitimate positioning bet ("the other bargain," per the README) but it
   means most reviewers will evaluate window-organizer by a yardstick it
   deliberately doesn't optimize for, and will likely mark it down for that
   even if the on-demand model is the more honest pitch.
4. **Banish needs field evidence, not confidence.** This is the one piece
   of the design with zero product precedent either confirming or denying
   it. Get it in front of real users doing real work before treating it as
   a settled part of the pitch.

## Bottom line
This is not "a thin layer on a crowded market" - the crowded market is all
solving *where*, and this product is trying to solve *whether and how
much*, which genuinely nobody ships today. But it is also not yet doing
what it claims: by the project's own documentation, the useful-minimum
distinction - the specific thing that would separate it from "yet another
snapping tool" - doesn't exist yet, only the technical-minimum probing
does. The differentiation is a real, well-reasoned bet with no shipped
competitor and a plausible (if unproven) answer to the "will people accept
disappearing windows" question - but today it's a bet on a roadmap, not a
demonstrated result. Closest competitor: yabai/AeroSpace for the "per-app
policy" half of the idea; nothing for the "useful minimum + automatic stow"
half.
