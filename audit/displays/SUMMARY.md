# warrange multi-display audit

Territory: multiple displays - spill, assignment, and geometry across screens. All
probing done via `--plan-from` fixtures only; nothing touched the live desktop.

## Fixtures (12)
- `two-displays-diff-size.json` - small primary, much larger secondary; no-spill vs spill
- `idx-vs-array-order.json` - fixture's `idx` field does not match array order
- `primary-empty-secondary-full.json` - all windows physically on display 1, display 0 empty
- `gap-between-displays.json` - non-adjacent displays with a real coordinate gap between them
- `stacked-vertical.json` - secondary display at negative y (stacked above the primary)
- `tiny-secondary.json` - secondary far smaller than any app's useful size
- `three-displays.json` - 8 windows across 3 displays of different sizes, `--spill`
- `hero-cannot-fit-primary.json` - hero's technical minimum exceeds the primary entirely
- `master-ignores-minsize.json` - `--master` on an extreme 300px-wide primary
- `master-realistic-minsize.json` - `--master 0.3` on a realistic 1280px primary (issue 1)
- `minor-uncapped-height.json` - minor-tier window alone on a spilled secondary (issue 2)
- `banish-stays-on-primary.json` - banish-tier window with an idle secondary (issue 3)

A scripted check ran every fixture through `--json`, `--spill`, `--master 0.6`, and
`--master 0.6 --spill` and verified every placement rect falls fully inside the display it
claims and that no two placements on the same display overlap. No bounds or overlap
violations were found anywhere - the core rect geometry/packing math is solid across gaps,
stacked/negative-y displays, wildly different display sizes, and 3-display spill. The bugs
below are all about sizing and assignment policy, not raw geometry.

## Issues filed (3)
1. blocker - master forces the hero below its technical minimum size, even with --spill
   and a fitting secondary available
2. major   - Minor-tier windows (Slack/Discord/Messages) have no real height cap, so
   --spill lets them balloon to 100% of a display's height
3. major   - Banish-tier apps are not routed to a secondary display; they stay on the
   primary whenever there's room, contradicting the documented tier intent

Severity breakdown: 1 blocker, 2 major, 0 minor, 0 polish.

## Single most important finding
Issue 1 (issues/01-master-hero-below-minimum.md): with --master set to its own documented
lower bound (0.3) on an ordinary 1280px-wide primary, the hero (iTerm2, declared technical
minimum 720x400) is planned at 380px wide - well below what the app will even accept - and
--spill does not rescue it even though a completely idle 1920x1080 secondary sits right
there in the same fixture. Every other placement path in this engine (pack()) refuses to
place a window below its useful/minimum size; the --master code path skips that check
entirely, computing the hero's slab purely from frac * display.width with no reference to
hero.minSize or hero.prio.usefulSize. If applied, this would silently diverge from the
reported plan (the OS would refuse the resize) and risks the adjacent "stack" region
overlapping the hero once macOS clamps it back up. This is the one bug in this audit that
produces an outright physically-impossible plan rather than a merely surprising one.

## Notes on things probed but NOT filed as bugs
- Fixture idx vs array order: the fixture's idx field is not consulted by the loader at
  all (loadFixture just maps displays in array order); "display 0" in the output always
  means "first entry in the displays array," matching how the live path (usableDisplays()
  from NSScreen.screens) works too. Not a product bug, just a fixture-authoring gotcha.
- primary-empty-secondary-full.json: the engine has no concept of "where a window
  currently lives" at all - it always re-packs everything starting from display 0, so
  windows already comfortably settled on display 1 get relocated to display 0 the first
  time you run it. This is clearly deliberate ("Fit onto display 0" per the source
  comments), so it isn't filed as a new bug on its own, but it compounds with issue 3.
- three-displays.json: with --spill, normal/hero windows can saturate all 3 displays
  completely (each grows to 100% of its display since nothing caps it below the available
  space), leaving zero room anywhere for 4 minor/banish windows despite 3 monitors. This
  traces back to the same missing-height-cap root cause as issue 2, so it wasn't filed
  separately.
- master-ignores-minsize.json (300px-wide primary): same root cause as issue 1, kept only
  as a secondary illustration; master-realistic-minsize.json was filed instead because it
  uses fully ordinary values (1280px display, --master 0.3, a 720px technical minimum)
  rather than an extreme display width.
- Negative-width master "stack" region: the --master formula (stackX = area.minX +
  masterW + GAP) can go negative for absurdly narrow displays (<~27px at frac=0.85), but
  that's far outside any real monitor size and the engine handles it gracefully (stows
  rather than crashing), so not filed.
