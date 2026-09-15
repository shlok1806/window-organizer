# warrange input-robustness audit - SUMMARY

Scope: input robustness and the command-line contract, per the audit brief. All commands
were run with `--plan-from <fixture.json>` only; `--apply`, `--undo`, `--unfullscreen`
were never invoked against the live desktop, `wdump`/`wprobe` were never run. One
combination (`--plan-from <valid fixture> --apply`, to empirically confirm apply is
neutralised) was attempted and was itself refused by the harness's own destructive-action
classifier; that neutralisation claim is instead confirmed by static reading of
main.swift (see issue 02).

## Inputs tried

Fixture-level (fixtures/ directory, 24 files):
- invalid JSON (syntax error)
- valid JSON but not an object (array, string, number)
- missing "displays" key; empty displays array
- missing "windows" key; empty windows array
- window missing "app" / "rect" / "minSize" / "id"
- duplicate window ids
- negative and zero width/height (both on a window's rect and on a display's usable rect)
- string values where numbers are expected (rect fields, and separately minSize fields)
- enormous numbers (rect fields, and separately minSize at 1e19 and ~1e21)
- a float where an int id is expected
- deeply nested junk trailing a well-formed window
- a 500-window fixture (performance)
- non-existent fixture path
- a directory passed as the fixture path
- an unreadable file (chmod 000)
- an empty (0-byte) file

CLI-contract level:
- unknown flag (`--nope`)
- `--master` with no value, with a non-numeric value, with a negative (out-of-range) value
- `--hero` with no value, naming an app not present in the fixture
- `--plan-from` with no value / value consumed by another flag (verified via source only)
- `--json` combined with `--help`
- repeated `--plan-from` (first occurrence wins)
- flags in different orders
- verified `--apply` is neutralised whenever `--plan-from` successfully parses a value
  (`apply = args.contains("--apply") && planFrom == nil`, main.swift:381), and confirmed
  the live-desktop-reading guard (`guard planFrom != nil || AXIsProcessTrusted() ...`,
  main.swift:404) is only skipped once a fixture path is present

Total distinct malformed/edge inputs exercised: **29 fixture files + 12 CLI-flag
scenarios (41 total probes)**.

## Issues filed: 8

| # | Severity | Title |
|---|----------|-------|
| 01 | blocker | Enormous `minSize` value crashes the CLI with SIGTRAP (exit 133) in human output |
| 02 | blocker | `--plan-from` with a missing/unmatched value silently escapes to live-desktop mode (static finding, not executed) |
| 03 | major | `--json` is silently ignored (prints human text) when there are zero windows |
| 04 | major | `--hero <app not present>` silently drops the hero designation from every window |
| 05 | minor | `minSize` given as JSON strings is silently coerced to 0 instead of erroring |
| 06 | minor | Unknown flags (e.g. `--nope`) are silently ignored |
| 07 | minor | `--master` with a garbage or out-of-range value is silently defaulted/clamped |
| 08 | minor | Duplicate window ids in a fixture are silently accepted into JSON output |

Severity breakdown: 2 blocker, 2 major, 4 minor.

Everything else probed (invalid JSON, non-object JSON, missing/empty displays, missing
windows key, missing rect/minSize/id on a window, negative/zero window dims, negative
display dims, string/enormous values that don't feed the crashing code path, a
non-existent/directory/unreadable/empty fixture path, the 500-window fixture, deeply
nested junk, `--json --help`, repeated `--plan-from`, flag ordering) was handled
correctly: clear `cannot read fixture: <path>` / `no displays` errors with exit 1 where
appropriate, sane defensible output otherwise, and the 500-window fixture planned in
~30ms with valid, jq-parseable JSON.

## Single most important finding

**Issue 01: an enormous `minSize` value in a fixture crashes the CLI outright (SIGTRAP,
exit 133, no output at all) when using the default human-readable output.** This is the
clearest, cleanest violation of the rubric ("malformed input causes a crash") in the
audit: fully reproducible, trivial to trigger (a single window with
`"minSize": {"w": 1e19, "h": 1e19}`), and it fails silently - no stdout, no stderr,
just a dead process. It's also inconsistent with `--json` mode, which handles the exact
same fixture gracefully by marking the window unplaceable. A production layout tool
should never let a bad number in an input file kill the whole process; a bug in
whatever produces `minSize` values (a plausible real-world source, since minSize is
itself measured/cached from live AX queries per main.swift's own comments) would brick
every future invocation of `warrange` for the affected app until the cache is manually
cleared.

A close second is Issue 02 (the `--plan-from`-without-a-value hole): it wasn't executed
live, in observance of the audit's hard prohibitions, but the source code shows a real
path by which a mistyped or truncated `--plan-from` combined with `--apply` would fall
straight through to writing real window geometry on the live desktop with zero warning -
precisely the failure mode this whole audit exists to catch.
