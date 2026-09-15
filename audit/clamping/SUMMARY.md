# Clamping audit summary - warrange

Territory: minimums and caps (technical minimum vs useful minimum vs per-app size cap).

## Fixtures: 11
All under `fixtures/`, run only via `--plan-from` (never against the live desktop, never `--apply`/`--undo`/`--unfullscreen`).

## Issues filed: 2
- **Blocker:** 1 — `issues/01-height-cap-violates-technical-minimum.md`
- **Major:** 1 — `issues/02-cap-strands-space-in-shared-row.md`

## Most important finding
`main.swift:351` finalizes every window's height with:

```swift
let h = min(heights[ri], w.prio.maxSize?.height ?? heights[ri])
```

This clamp is unconditional: it does not check whether the window's own
technical minimum (`packSize.height = max(minSize.height, usefulSize.height)`)
already exceeds its built-in cap. Whenever `cap.height < technical minimum
height`, the engine plans a placement shorter than the app will actually
accept - a real "it would clamp and overlap on apply" bug.

Confirmed with two independent fixtures:
- `fixtures/01-height-cap-below-technical-min.json`: System Settings
  (technical min 723x700, built-in cap 800x620), sharing a row with an
  uncapped hero, is planned at **620** tall - 80px under its own technical
  floor.
- `fixtures/11-solo-row-technical-exceeds-cap.json`: same failure with
  Finder (technical min 700x700, cap 800x560) placed **alone** in its own
  row (no hero, no row-mate) - still planned at **560** tall. This rules out
  "row sharing" as the cause: the clamp is simply wrong on its own terms,
  any time an app's cap is below the max of its technical/useful minimums.

Width does not have this bug - per-item width is what `waterfill` computes
directly, so a technical width minimum above the cap is correctly honoured
(verified in `fixtures/03-outlook-technical-exceeds-cap.json`: Outlook with
technical min 1400 wide against a 1300 cap is correctly placed at 1400).
Height is uniquely broken because row height is shared across a row and then
re-clamped per item after the fact, with no floor check against that item's
own base size.

The second issue (`02-cap-strands-space-in-shared-row.md`) is the same code
path's other symptom: when a row mixes capped and uncapped windows, the
row grows to satisfy the uncapped/less-capped windows, and the capped
window's clawed-back height turns into genuinely dead, unusable desktop
space next to windows that could have used it - reproduced in
`fixtures/09-cap-redistribution-in-row.json` (525px x 532px of blank space,
~28% of that row, sitting right under Finder).

Both issues trace to the same line (`main.swift:351`) and the same fix
direction: the per-item cap clamp needs a floor of `w.packSize.height`, and
ideally the height clawed back by a cap should re-enter the row's pool for
redistribution to siblings (mirroring what `waterfill` already does for
width within a row).

## Also probed, confirmed correct (no bug filed)
- Outlook technical min (1210x684) exceeding useful min (900x600), under
  cap: physics correctly wins for width; window is stowed for lack of
  vertical space, which is the honest correct outcome given the numbers
  (`fixtures/02`).
- Technical minimum wider than its own cap (Outlook 1400 vs cap 1300):
  correctly honoured, placed at 1400 (`fixtures/03`).
- Technical minimum larger than the whole display (WhatsApp 2000x2000,
  and Finder 99999x99999): both correctly stowed, no crash, no overflow,
  clean JSON (`fixtures/04`, `fixtures/07`).
- Missing `minSize` and `minSize: {w:0,h:0}`: both treated identically as
  zero technical minimum, engine falls back to useful size cleanly, no
  crash (`fixtures/05`, `fixtures/06`).
- Two windows of the same app (Outlook) with different `minSize` values in
  one fixture: each window's distinct minimum was honoured independently
  (1210x684 vs 640x600) - no cross-window state bleed. The inbox window was
  evicted/stowed to make the compose window fit, which is the documented
  eviction-is-greedy known issue, not a new bug (`fixtures/08`).
- A sole capped window alone on a big display (Finder, cap 760x560): capped
  correctly, rest of the display simply left empty since nothing else needs
  it - not a bug, since there's nothing to redistribute to (`fixtures/10`).
