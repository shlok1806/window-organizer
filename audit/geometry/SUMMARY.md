# Geometry audit summary - warrange (display geometry + --master fraction)

Territory: unusual screens and the --master fraction. All commands run via --plan-from <fixture.json>
only; nothing was applied, undone, or read from the live desktop.

## Fixtures generated (11)
- 01-tiny-800x600-master03.json - tiny display, hero + Safari
- 02-ultrawide-5120x1440.json - 5120x1440, hero + Safari + Slack + Finder
- 03-portrait-1440x2560.json - portrait monitor, hero + Safari + Slack
- 04-tinyheight-1728x300.json - huge-dock-style tiny usable height
- 05-nonzero-origin-1728.json - display at x:1728,y:0 (secondary-display-style origin)
- 06-negative-origin.json - display at x:-1920,y:0
- 07-square-1600x1600.json - square display, hero + Safari + Slack
- 08-singlewindow-master.json - single hero window, used to sweep --master across 0.01/0.99/1.5/0/-1/abc
- 09-extreme-tiny-master.json - 10x600 pathological display, to probe masterW arithmetic
- 10-laptop-1280x800-master03.json - ordinary laptop-size display, hero + Safari
- 11-heroiscapped-app-master.json - focused app is normally-capped (Safari), to confirm hero cap is always cleared

## Issues filed (3): 1 major, 0 blocker, 2 polish
1. major - 01-master-slab-ignores-hero-useful-size.md: --master hands the hero a slab with no floor
   against its own usefulSize/minSize. Reproduces on an ordinary 1280x800 laptop display at both
   --master 0.3 (380px slab vs. WezTerm's 640px useful width) and --master 0.5 (636px, still under
   640px), and much worse on an 800x600 display (236px). This is the most important finding: it defeats
   the entire point of --master (give the hero prominence) using two of the four fractions the audit
   brief called out (0.3 and 0.5), on completely realistic screen sizes.
2. polish - 02-master-negative-slab-goes-offscreen.md: on a pathologically narrow display (<~13px
   wide, unrealistic on real hardware but real in the arithmetic), masterW goes negative and CGRect
   silently standardizes it into a 1px placement at x:-1, outside the display's usable rect. No clamp
   guards masterW > 0.
3. polish - 03-master-nonnumeric-silently-defaults.md: --master abc (or any non-numeric value)
   silently falls back to the default 0.6 with no warning and exit code 0, indistinguishable from
   omitting the flag - a typo gives no signal.

## Things explicitly checked and found correct (no issue filed)
- Numeric --master clamping to [0.3, 0.85] is correct for every out-of-range value tried: 0.01 to 0.3,
  0.99 to 0.85, 1.5 to 0.85, 0 to 0.3, -1 to 0.3 (all verified via --json output against the formula).
- "Hero's cap smaller than the master slab" cannot happen in this build: main.swift unconditionally sets
  hero.prio.maxSize = nil when assigning the hero (even when the focused app is normally capped, e.g.
  Safari's usual 1200px cap - verified with fixture 11, hero grew to 4348px wide at --master 0.85
  uncapped). Confirmed, not filed.
- Ultrawide (5120x1440), portrait (1440x2560), square (1600x1600), non-zero-origin (x:1728),
  negative-origin (x:-1920), and tiny-usable-height (1728x300) displays all produced correctly bounded,
  non-overlapping placements across --master 0/0.3/0.5/0.6/0.85 sweeps - verified arithmetically against
  each fixture's usable rect (row y/height sums and column x/width sums line up with GAP=8 between
  items and never exceed usable.x,y + usable.w,h).
- Cascading over-stowing seen at --master 0.85 on the ultrawide fixture (Safari/Slack/Finder all stowed
  even though Slack+Finder could have shared the leftover strip) is an instance of the already-known
  "eviction is greedy by (tier rank, then area)" issue, not filed separately.
- The 1728x300 tiny-usable-height fixture correctly stows every window (nothing meets useful height 300 <
  360-400) rather than cramming - matches the tool's own stated design philosophy, not a bug.

## Most important finding
Issue 01: --master can hand the tool's own showcased "hero" window a slab narrower than the hero's
declared useful width - on an entirely ordinary 1280x800 display, at --master 0.3 and even --master
0.5. Every other placement in this engine is gated on meeting useful size before being placed (else
stowed); the master-slab code path is the one exception, and it's the path that exists specifically to
give the hero prominence.
