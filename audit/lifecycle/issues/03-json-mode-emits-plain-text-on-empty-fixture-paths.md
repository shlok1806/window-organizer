# --json is not honoured on early-exit paths (zero windows, zero displays) - emits plain text instead of JSON

**Severity:** major
**Fixture:** fixtures/empty-windows.json (zero windows), fixtures/no-displays.json (zero displays)
**Command:** `./warrange --plan-from fixtures/empty-windows.json --json` and
`./warrange --plan-from fixtures/no-displays.json --json`

## Expected
`--json` is the documented machine-readable plan mode. Any caller scripting against
`warrange --plan-from ... --json` should be able to assume stdout is always parseable JSON (even if
it is an empty/degenerate plan such as `{"placements":[],"stowed":[]}`), so it can be piped straight
into `jq`/`JSON.parse` without special-casing every error path.

## Actual
Zero-window fixture, with --json requested:
```
./warrange --plan-from fixtures/empty-windows.json --json
no windows on screen
(if you are in a fullscreen app, re-run with --unfullscreen)
exit=0
```
Zero-display fixture, with --json requested:
```
./warrange --plan-from fixtures/no-displays.json --json
no displays
exit=1
```
Neither output is JSON. The zero-window case is the more serious of the two: it exits 0 (success)
while printing human-oriented text instead of JSON, so a script that does
`warrange --plan-from x.json --json | jq .` would get a JSON parse error on what the exit code
claims was a successful run, and could not distinguish "legitimately nothing to place" from a
malformed invocation.

## Why this is wrong
In main.swift, the `wins.isEmpty` and `displays.isEmpty` guards run `print(...); exit(...)`
unconditionally, before the code ever reaches the `if jsonOut { print(planJSON(wins)); exit(0) }`
branch further down. Every other output path in the program correctly checks jsonOut before
choosing between the colored human table and planJSON, but these two early-return guards bypass
that check entirely. This is a distinct bug from anything in the known-issues list (which are about
placement/eviction policy, not the CLI's output contract), and it matches the rubric's "emits
invalid JSON" criterion for a mode whose entire purpose is to emit valid JSON.

## Suggested fix (optional)
Route both early-exit messages through the same jsonOut check as the rest of main, e.g. when
jsonOut is true, print `{"placements":[],"stowed":[],"error":"no windows on screen"}` (or similar)
instead of the human string, keeping exit codes meaningful (0 for "legitimately empty desktop", a
non-zero code reserved for actual failures like "no displays").
