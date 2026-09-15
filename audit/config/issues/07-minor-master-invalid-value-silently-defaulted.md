# `--master` with a non-numeric or out-of-range value is silently defaulted/clamped with no feedback

**Severity:** minor
**Fixture:** fixtures/25_valid_base.json
**Command:** `./warrange --plan-from fixtures/25_valid_base.json --master banana` and
`./warrange --plan-from fixtures/25_valid_base.json --master -0.5`

## Expected
A non-numeric `--master` value should produce a validation error, not silently fall back
to the default. An out-of-range numeric value (e.g. negative) should at least warn that
it was clamped, rather than silently substituting a different number than what was asked
for.

## Actual (paste REAL output you actually ran, including exit code)
Garbage (non-numeric) value silently becomes the default 0.6:
```
$ ./warrange --plan-from fixtures/25_valid_base.json --master banana

ARRANGE  2 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      1032x1085 @0,32       0
  Safari              normal   200x200    -                     cannot fit

  1 window cannot fit without overlap on this display.
  stacked minimum heights: 229px vs 1085px usable

  dry run - pass --apply to do it
EXIT=0
```
(1032/1728 ≈ 0.6, confirming the default silently kicked in)

Out-of-range negative value silently clamped to 0.3 with no message:
```
$ ./warrange --plan-from fixtures/25_valid_base.json --master -0.5

ARRANGE  2 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      514x1085 @0,32        0
  Safari              normal   200x200    1200x1085 @522,32     0

  dry run - pass --apply to do it
EXIT=0
```
(514/1728 ≈ 0.3, the hard-coded floor)

## Why this is wrong
```swift
if let fracArg = argv.firstIndex(of: "--master").map({ i -> CGFloat in
        i + 1 < argv.count ? (CGFloat(Double(argv[i + 1]) ?? 0.6)) : 0.6
   }), ... {
    let frac = min(0.85, max(0.3, fracArg))
```
Both an unparseable string and an out-of-range number are silently absorbed with no
indication to the user that their requested value was not honoured. This matches the
rubric's "a flag that takes a value is ... given a garbage value, and misbehaves" - here
"misbehaves" specifically means silently substituting a materially different value
(0.6 or clamped-to-0.3/0.85) than what the user asked for, changing the actual layout
without any warning.

## Suggested fix (optional)
When `Double(argv[i+1])` fails to parse, print a warning ("invalid --master value
'banana', using default 0.6") instead of silently substituting; likewise print a warning
when clamping an out-of-range fraction.
