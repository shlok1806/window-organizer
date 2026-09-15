# `--json` is silently ignored when there are zero windows - prints human text instead of JSON

**Severity:** major
**Fixture:** fixtures/06_empty_windows.json
**Command:** `./warrange --plan-from fixtures/06_empty_windows.json --json`

## Expected
With `--json` passed, output should always be valid JSON (e.g. an empty placements/stowed
object), so downstream tooling can rely on `--json` output always parsing with `jq`.

## Actual (paste REAL output you actually ran, including exit code)
```
$ ./warrange --plan-from fixtures/06_empty_windows.json --json
no windows on screen
(if you are in a fullscreen app, re-run with --unfullscreen)
EXIT=0
```

```
$ ./warrange --plan-from fixtures/06_empty_windows.json --json | jq .
jq: parse error: Invalid numeric literal at line 1, column 3
```
(jq exits 5)

Same result for fixtures/05_missing_windows.json (windows key absent entirely).

## Why this is wrong
`main.swift` around line 498-502 does:
```swift
let wins = fixture?.wins ?? collectWindows(onScreenWindows())
guard !wins.isEmpty else {
    print("no windows on screen")
    print("(dim)(if you are in a fullscreen app, re-run with --unfullscreen)(off)")
    exit(0)
}
```
This early-exit guard runs before `jsonOut` is ever consulted, so it unconditionally
prints human-formatted (ANSI-colored) text regardless of `--json`. This directly
violates the CLI contract this audit was asked to verify: "confirm `--json` output
always parses with `jq`." Any script piping warrange's `--json` output into `jq`
(exactly the use case `--json` exists for) will crash on this input. It is also doubly
confusing on a fixture run, since the hint "re-run with --unfullscreen" refers to a
live-desktop-only flag that has no effect when planning from a fixture at all.

## Suggested fix (optional)
Move the `wins.isEmpty` short-circuit below the `jsonOut` check and have it print
`{"placements":[],"stowed":[]}` (or similar) when `--json` was requested; also suppress
the `--unfullscreen` hint whenever `fixture != nil`, since it cannot apply.
