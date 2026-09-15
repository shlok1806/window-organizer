# Summary

Closest competitor: yabai / AeroSpace, for the "per-app policy" half only
(both support app-match rules to float/ignore/pin specific apps) - neither
measures a useful minimum size or automatically stows a window nobody asked
it to hide. Loop's manual "Stash" is the closest shipped analog to stowing,
but the user picks what gets hidden; nothing lets the software decide.

The real gap: automatic, tier-driven space allocation combined with a
measured useful-minimum (not just a technical one) and automatic stow as a
first-class outcome. That combination doesn't exist anywhere surveyed. But
by the project's own README, the useful-minimum piece - the actual claim -
isn't built yet either; only technical-minimum probing is. The
differentiation is real on paper, unproven in the shipped spike.

Biggest risk: automatic, unsolicited banishing of windows the user didn't
choose to hide has no product precedent, positive or negative, anywhere in
this survey. The nearest analog, Stage Manager, was rejected by a vocal
slice of users - but for being ambient and hard to reverse, not simply for
hiding windows (Loop's Stash is popular and does exactly that, invoked and
reversible). window-organizer's hotkey-only, undo-backed model looks
structurally closer to the accepted pattern than the rejected one, but this
needs real-user testing, not analogy, before it's treated as settled.

Secondary risk: shipping without drag-to-snap, the one interaction every
reviewer in this category treats as baseline, guarantees unfavorable
comparisons from anyone evaluating "does it feel good to move a window,"
which is most of the press this category gets.
