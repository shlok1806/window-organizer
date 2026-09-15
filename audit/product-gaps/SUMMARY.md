# Summary - the three gaps that matter most

1. **No macOS app at all.** Three unsigned CLI binaries with no bundle, no signing,
   no notarization cannot be downloaded and opened by a stranger - Gatekeeper will
   simply refuse to run it. This is the precondition for every other permission,
   login-item, and update mechanism macOS offers, so it blocks everything else.

2. **The skhd dependency is the wrong architecture for a product.** It requires
   Homebrew, a second unsigned daemon, and a second Accessibility grant whose
   connection to "window-organizer" is invisible to the user - and the project's own
   script admits macOS attributes window moves to skhd, not to the tool itself. An
   app that owns its global hotkey in-process removes an entire class of confused
   support requests in one architectural change.

3. **Nothing tells the user anything.** Every current signal - permission missing,
   Mission Control open, nothing fit, undo available - is a colored terminal line a
   GUI user will never see. Without a menu-bar presence and real notifications, the
   tool is either invisible or silently wrong, which directly contradicts the
   project's own pitch that "nothing changes until you ask" - that promise requires
   the user to be able to see what happened.

Single most important thing missing: **there is no app** - no bundle, no signing, no
menu-bar presence, no first-run permission flow. The layout engine itself is the
project's strongest asset (measured 64.8% -> 0.0% hidden pixels) and is largely
solved; the macOS "app shell" around it (packaging, permissions UX, runtime
presence, its own hotkey) is a second, comparably-sized body of work that has not
been started at all.
