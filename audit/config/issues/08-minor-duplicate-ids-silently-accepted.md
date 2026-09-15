# Duplicate window ids in a fixture are silently accepted and propagate into JSON output unchanged

**Severity:** minor
**Fixture:** fixtures/11_duplicate_ids.json
**Command:** `./warrange --plan-from fixtures/11_duplicate_ids.json --json`

## Expected
Since `id` is documented as the "stable window identity" that downstream tooling would
key on, a fixture with two different windows sharing the same `id` should be rejected
(or at least warned about), since it makes the JSON output ambiguous for any consumer.

## Actual (paste REAL output you actually ran, including exit code)
```
$ ./warrange --plan-from fixtures/11_duplicate_ids.json --json
{"placements":[{"app":"WezTerm","display":0,"id":1,"rect":{"h":1085,"w":748,"x":0,"y":32}},{"app":"Safari","display":0,"id":1,"rect":{"h":1085,"w":972,"x":756,"y":32}}],"stowed":[]}
EXIT=0
```
Both a WezTerm window and an unrelated Safari window are reported with `"id":1`. The
output is syntactically valid JSON (parses fine with jq) but is semantically ambiguous:
any consumer that does `placements[id]` or diffs against a previous plan by id cannot
tell these two windows apart.

## Why this is wrong
`loadFixture` (main.swift ~158-176) reads `raw["id"] as? Int ?? 0` per window with no
uniqueness check across the whole `windows` array. This is explicitly one of the probe
targets in this audit's brief ("duplicate ids") and matches "malformed input is silently
accepted and produces a confident, wrong plan" - the plan itself packs correctly, but
the *contract* of `id` as a stable, unique identity is silently broken, which would
corrupt any external tool trying to correlate this plan back to real windows by id.

## Suggested fix (optional)
Validate fixture window ids for uniqueness while loading and reject the fixture (or at
least warn) if duplicates are found.
