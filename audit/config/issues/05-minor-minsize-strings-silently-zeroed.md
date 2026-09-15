# Numeric fixture fields given as JSON strings are silently coerced to 0 instead of erroring

**Severity:** minor
**Fixture:** fixtures/23_minsize_strings.json
**Command:** `./warrange --plan-from fixtures/23_minsize_strings.json`

## Expected
A `minSize` of `{"w": "2000", "h": "2000"}` (numbers given as strings - an easy mistake
for any JSON producer that stringifies numbers) should either be parsed as numbers, or
rejected with a validation error. It should not be silently treated as `0x0`.

## Actual (paste REAL output you actually ran, including exit code)
```
$ ./warrange --plan-from fixtures/23_minsize_strings.json

ARRANGE  1 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     0x0        1728x1085 @0,32       0

  dry run - pass --apply to do it
EXIT=0
```

For comparison, the same fixture with numeric (non-string) `minSize` of 2000x2000 would
correctly report "cannot fit" on a 1728x1085 display - instead the string-typed input is
silently treated as having *no* minimum size whatsoever, and the tool confidently reports
success with `MINIMUM 0x0`.

## Why this is wrong
`fixtureRect` in main.swift:152-156 does:
```swift
func fixtureRect(_ any: Any?) -> CGRect {
    guard let r = any as? [String: Any] else { return .zero }
    return CGRect(x: r["x"] as? Double ?? 0, y: r["y"] as? Double ?? 0,
                  width: r["w"] as? Double ?? 0, height: r["h"] as? Double ?? 0)
}
```
`"2000" as? Double` fails (JSONSerialization gives an `NSString`, not `NSNumber`), so
every numeric-as-string field silently becomes `0` with no diagnostic at all. This is
"malformed input is silently accepted and produces a confident, wrong plan" verbatim
from the rubric: the resulting plan is not just imprecise, it is the *opposite* of
correct (a window with a genuinely huge minimum size is reported as having none, and
gets happily packed into whatever tiny slot is available).

## Suggested fix (optional)
When decoding required numeric fields, also accept/parse numeric strings explicitly, or
better, reject the fixture with a clear "field 'minSize.w' must be a number, got string"
error rather than silently defaulting.
