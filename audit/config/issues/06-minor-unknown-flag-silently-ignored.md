# Unknown/misspelled flags are silently ignored with no warning

**Severity:** minor
**Fixture:** fixtures/25_valid_base.json
**Command:** `./warrange --plan-from fixtures/25_valid_base.json --nope`

## Expected
An unrecognised flag like `--nope` should produce an error ("unknown flag: --nope") and
a non-zero exit, or at minimum a visible warning - not be silently swallowed.

## Actual (paste REAL output you actually ran, including exit code)
```
$ ./warrange --plan-from fixtures/25_valid_base.json --nope

ARRANGE  2 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      748x1085 @0,32        0
  Safari              normal   200x200    972x1085 @756,32      0

  dry run - pass --apply to do it
EXIT=0
```
Identical output/exit code to the same command without `--nope` at all.

## Why this is wrong
main.swift parses flags with `Set(CommandLine.arguments.dropFirst())` and a series of
`args.contains("--whatever")` checks; there is no allowlist validation pass anywhere, so
any flag not explicitly checked for is simply never looked at. This is called out
directly in the rubric as dangerous: "an unknown or misspelled flag is silently ignored
(dangerous on a tool that moves windows)". Concretely: a user who means to type
`--unfullscreen` but fat-fingers it as `--unfullscren` gets no error and no fullscreen
reclamation, silently, and has no way to know from the output that their flag did
nothing.

## Suggested fix (optional)
Build an explicit set of recognised flags and reject (`exit(1)` with a message) any
argument starting with `--` that isn't in it.
