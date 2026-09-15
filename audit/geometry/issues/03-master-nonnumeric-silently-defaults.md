# A garbage --master value is silently treated as the default fraction, with no warning

**Severity:** polish
**Fixture:** fixtures/08-singlewindow-master.json
**Command:** `./warrange --plan-from fixtures/08-singlewindow-master.json --master abc`

## Expected
The numeric clamp to [0.3, 0.85] was verified to work correctly for every out-of-range numeric input
(`0.01`, `0.99`, `1.5`, `0`, `-1` all clamp to `0.3` or `0.85` as expected - no bug there). A non-numeric
value is a different case: it should be rejected with an error/warning, since silently substituting the
default gives the user no signal that their flag was ignored.

## Actual (real pasted output)
```
$ ./warrange --plan-from fixtures/08-singlewindow-master.json --master abc
ARRANGE  1 windows, 1 display, hero: WezTerm

  APP                 TIER     MINIMUM    PLANNED               DISPLAY
  ──────────────────────────────────────────────────────────────────────────
  WezTerm             hero     24x29      1032x1060 @0,25       0

  dry run - pass --apply to do it

$ echo $?
0
```
No warning, no error, no mention of `--master` anywhere in the output, and exit code 0. The plan is
identical to what `--master 0.6` (or omitting `--master` entirely) would produce (`1728*0.6 - 4 = 1032.8`,
matching the `w:1032` above) - i.e. a typo like `--master 0.3` mistyped as `--master o.3` silently becomes
"use the default" instead of surfacing the mistake.

## Why this is wrong
`main.swift` line ~547-548: `i + 1 < argv.count ? (CGFloat(Double(argv[i + 1]) ?? 0.6)) : 0.6`. Any string
that fails to parse as `Double` falls back to `0.6` via `??`, indistinguishable from the user explicitly
asking for the default or omitting the flag. This isn't a geometry/overlap bug (the resulting plan is a
perfectly valid `0.6` layout), but it is exactly the kind of silent-surprise behavior this audit was asked
to check for.

## Suggested fix (optional)
When `--master` is present but its value fails to parse as a `Double`, print a warning (or exit non-zero)
naming the bad value instead of silently substituting `0.6`.
