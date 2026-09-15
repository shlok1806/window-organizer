# Enormous minSize value crashes the CLI with SIGTRAP (exit 133), no error message

**Severity:** blocker
**Fixture:** fixtures/24b_minsize_1e19.json
**Command:** `./warrange --plan-from fixtures/24b_minsize_1e19.json`

## Expected
Either the plan succeeds by treating the oversized minSize sensibly (e.g. clamp it, or
mark the window "cannot fit"), or the tool prints a clear validation error and exits
non-zero. Either way, the process must not crash.

## Actual (paste REAL output you actually ran, including exit code)
```
$ ./warrange --plan-from fixtures/24b_minsize_1e19.json
EXIT=133
```
stdout: empty
stderr: empty

Exit code 133 = 128 + 5 (SIGTRAP): a Swift runtime fatal trap, not a handled error path.
Reproduced twice for consistency, and also with a second, even more clearly malformed
value (`999999999999999999999`, fixtures/24_minsize_enormous.json) - same 133 exit.

Notably this is specific to the **human-readable** output path. The identical fixture
through `--json` does NOT crash:
```
$ ./warrange --plan-from fixtures/24_minsize_enormous.json --json
{"placements":[],"stowed":[{"app":"WezTerm","id":1}]}
EXIT=0
```

## Why this is wrong
`main.swift:610` builds the MINIMUM column like this:

```swift
let mn = "\(Int(w.minSize.width))x\(Int(w.minSize.height))"
```

`w.minSize` comes straight from the fixture's `minSize.w`/`minSize.h` with no bounds
check (`fixtureRect` just does `r["w"] as? Double ?? 0`). When that Double exceeds
`Int64.max` (~9.22e18), `Int(CGFloat)` traps and kills the whole process instead of
throwing a catchable error. A single corrupted or adversarial fixture takes down the
entire CLI with zero diagnostic output - exactly "malformed input causes a crash ... or
an unhelpful/absent error message" from the rubric. It is also inconsistent: the JSON
path silently tolerates the same fixture (treats the window as unplaceable), so human
and JSON output modes disagree on whether this input is even valid.

## Suggested fix (optional)
Validate/clamp numeric fixture fields while parsing (`fixtureRect`), and/or replace the
raw `Int(...)` conversions in the human-output formatter (`main.swift:610`, `:614`,
`:625`, and `planJSON`'s `r()` at `:181`) with a saturating conversion (e.g.
`Int(exactly:)` with a fallback, or clamp to `Int32.max`) so oversized values degrade
gracefully instead of trapping.
