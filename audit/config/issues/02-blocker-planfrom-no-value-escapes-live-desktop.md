# `--plan-from` with a missing/unmatched value silently falls back to reading (and, combined with --apply, writing) the LIVE desktop

**Severity:** blocker
**Fixture:** none - this is a static-code finding, deliberately NOT executed
**Command:** would be `./warrange --plan-from --apply` (or `--plan-from` as the very last
argument, combined with `--apply`) - **not run**, per the audit's absolute prohibition on
ever invoking warrange without a valid `--plan-from` value, and confirmed by the harness
itself: attempting even the safe half of this test (`--plan-from <fixture> --apply`, which
the source proves is neutralised) was blocked by the sandbox's own destructive-action
classifier ("Irreversible Local Destruction"). So this finding is derived entirely from
reading main.swift; it was not reproduced live and must not be reproduced live.

## Expected
If `--plan-from` is present on the command line but its value is missing or was consumed
by flag confusion, the tool should refuse to run (or at minimum refuse to fall back to
live-desktop mode) rather than silently behaving as if `--plan-from` was never given.

## Actual (read from source, main.swift)
```swift
let planFrom: String? = argv.firstIndex(of: "--plan-from").flatMap { i in
    i + 1 < argv.count ? argv[i + 1] : nil
}
let apply = args.contains("--apply") && planFrom == nil
...
guard planFrom != nil || AXIsProcessTrusted() else {
    print("Accessibility not granted...")
    exit(1)
}
...
let displays = fixture?.displays ?? usableDisplays()          // live desktop read
...
let wins = fixture?.wins ?? collectWindows(onScreenWindows()) // live desktop read
...
if apply && placedAnywhere {                                  // live desktop WRITE
    ...
    setSize(el, p.size); setPos(el, p.origin); setSize(el, p.size)
    ...
    setBool(el, kAXMinimizedAttribute as String, true)         // minimises real windows
}
```

`planFrom` becomes `nil` in exactly two situations: (a) `--plan-from` is absent
entirely (the normal, intentional live-mode invocation), and (b) `--plan-from` **is
present** but has no following token (it's the last argument) or its "value" is
actually the next flag. In case (b) there is no distinction from case (a) anywhere in
the program - `planFrom == nil` is used uniformly to mean "operate on the live desktop"
and, if `--apply` was also passed, `apply` becomes `true` and the program will write
real window geometry via the Accessibility API.

## Why this is wrong
The CLI's entire safety story for this audit rests on "`--plan-from` neutralises
`--apply`" (confirmed true and tested separately - see below). But that guarantee only
holds while `--plan-from`'s value is successfully parsed. A user who mistypes the flag
(`--plan-fro`, `--plna-from`), forgets the path (`--plan-from --apply`), or puts
`--plan-from` last in a generated command line with no path appended, gets **zero
warning** and silently drops into full live mode. Since this is very plausible in
exactly the kind of automated/CI/testing context where someone would reach for
`--plan-from` in the first place, this is the single most dangerous gap in the CLI
contract: "a flag that takes a value is given none ... and misbehaves" combined with
"the outcome is defensible but would astonish a user", except here the astonishment is
a real window layout change on the user's live desktop.

Separately, I *did* verify (statically, and via the harness refusing to let me even run
the safe form) that `--plan-from <valid-fixture> --apply` correctly neutralises apply -
`apply = args.contains("--apply") && planFrom == nil` is `false` whenever `planFrom` is
a real, successfully-parsed value. So the guard itself is sound; the hole is entirely in
how `planFrom` is computed when the flag's value is missing or ambiguous.

## Suggested fix (optional)
Make "`--plan-from` present but no value" a hard parse error (`exit(1)` with a clear
message) rather than silently treating it as "no `--plan-from` given". Never let
"flag present but malformed" and "flag absent" collapse into the same code path when
that path controls live-desktop mutation.
