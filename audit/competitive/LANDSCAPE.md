# Landscape survey: macOS window management, September 2026

Scope: every tool named in the brief, plus a few that turned up during research
because they sit closer to window-organizer's actual claim than the obvious
incumbents do. "Alive" means actively updated or at minimum functioning on
current macOS with an active repo/support channel as of this survey.

## Drag-snap / hotkey positioners (the crowded middle)

### Rectangle / Rectangle Pro
- **Model:** drag-to-edge snapping with preview overlay, plus a large keyboard
  shortcut set for fixed positions (halves, thirds, quarters, corners,
  fullscreen, next/previous display).
- **Price:** Rectangle is free, open source (MIT). Rectangle Pro is a separate
  paid app, $9.99 one-time, 10-day trial, no subscription.
- **Pro adds:** Window Throw (16 sizes/positions from anywhere on the window),
  custom snap targets and a snap panel, custom sizes, "App Layouts" (a saved
  multi-window arrangement you can re-trigger), iCloud config sync.
- **Alive:** yes, the default recommendation in nearly every comparison
  article found. Free tier is described as "genuinely complete," not a teaser.
- **Content-awareness:** none. Every position is a fixed fraction of the
  screen; the app does not know or care what is being placed there.

### Magnet
- **Model:** drag-to-edge/corner snapping (halves, thirds, quarters,
  fullscreen), keyboard shortcuts, Mac App Store distribution.
- **Price:** history of changes ($1.99-$10 across sources); current App
  Store price is a one-time purchase, no subscription.
- **Alive:** yes, still sold and updated; its main edge over Rectangle is
  App Store distribution (matters on managed/corporate Macs).
- **Content-awareness:** none. Pure geometry, no per-app layouts, no App
  Layouts equivalent, no cursor gestures.

### Moom (Many Tricks)
- **Model:** a "grid" popover you use to define custom positions/sizes, plus
  the ability to save named arrangements and recall them, including
  multi-window layouts.
- **Price:** $15 new, $8 upgrade from Moom 3. One-time, not a subscription.
- **Alive:** yes, Moom 4 shipped 12+ years after Moom 3. Consistently
  described as functionally solid but visually/interaction-wise dated (no
  trackpad or mouse gestures, older-style UI).
- **Content-awareness:** partial and manual. Moom lets a user hand-author a
  saved layout per app and recall it, which is the closest thing to
  "per-app policy" among the drag-snap incumbents - but it is a static,
  user-authored position, not a measured useful-minimum or a tier/weight
  system, and it does nothing automatically.

### BetterSnapTool
- **Model:** drag-to-corner/edge snapping, custom snap zones anywhere on the
  display, keyboard shortcuts per zone, window-button click customization.
- **Price:** $1.99-$2.99 one-time (sources vary by region/date). Same
  developer as BetterTouchTool ($22 lifetime), which absorbs all of
  BetterSnapTool's functionality if you want the superset.
  Reviews explicitly note BetterSnapTool lacks "window groups, cursor
  gestures, or per-app settings" relative to Rectangle Pro - i.e. reviewers
  treat per-app settings as a feature a *more complete* competitor has, not
  as an unusual ask.
- **Alive:** yes.
- **Content-awareness:** none.

### Swish
- **Model:** trackpad-gesture window control (28 swipe/pinch/tap gestures) on
  the title bar, Dock, and menu bar, snapping into 2x2/2x3/3x3 grids.
- **Price:** current listing ~$16 one-time (was $5-$8 in past years); also
  available via Setapp subscription (~$14.99/mo for the whole bundle).
- **Alive:** yes, not on the Mac App Store (needs non-sandboxed system
  access), sold directly and via Setapp.
- **Content-awareness:** none. It changes the *input model* (gestures instead
  of drag or hotkey), not the *decision model*.

### Loop
- **Model:** free, open-source (GPL-3.0), MrKai77's radial-menu window
  manager - hold a trigger key, drag toward a direction, release to
  snap/resize. ~10k+ GitHub stars, active development.
- **Price:** free.
- **Alive:** yes, actively developed, popular enough that a Hacker News
  thread debated its distribution model.
- **Notable feature - Stash:** lets a user manually shove a window off to a
  screen edge to get it out of the way, then recall it by hovering the edge
  or a keybind. This is the single closest *shipped, popular* feature to
  window-organizer's "stow" concept found anywhere in this survey - but it
  is a manual, per-window, user-initiated action, not an automatic decision
  driven by what the window is or how much space is left.

### Tiles
Two unrelated apps share this name, worth disambiguating (no evidence of a
"Space Tyrant" product was found under this name or a related one):
- **Tiles by FreeMacSoft/Semplive** - free, minimalist drag/edge/keyboard
  window manager with a "restore previous size" option. No content-awareness.
- **Tiles (gettiles.vercel.app)** - a newer, paid app focused on *saving and
  recalling* whole window layouts per workspace rather than live tiling
  decisions - closer in spirit to a session-restore tool (see ShiftPlus,
  below) than to a layout engine.

## Automatic tiling window managers

### Amethyst
- **Model:** always-on, automatic BSP/xmonad-style tiling with cyclable
  layouts (Tall, Wide, 3Column, Floating). Once running, it keeps every
  window tiled continuously - the opposite interaction model from
  window-organizer's "do nothing until invoked."
- **Price:** free, open source.
- **Alive:** yes, actively maintained (ianyh/Amethyst is canonical; several
  GitHub results are stale forks).
- **Content-awareness:** none reported. Splits panes geometrically; no
  per-app minimum handling, no weighting, no stow.

### yabai
- **Model:** scriptable BSP tiling manager, CLI-driven (`yabai -m ...`),
  usually paired with `skhd` for keybindings. Always-on tiling once
  configured, like Amethyst but far more configurable.
- **Price:** free, open source.
- **Alive:** yes, current macOS (through Tahoe 26) supported. Full
  functionality (moving windows between Spaces, some display features)
  requires partially disabling System Integrity Protection; "basic mode"
  works without it.
- **Content-awareness - closest existing precedent found in this survey:**
  yabai supports per-app/per-title *rules* (regex-matched) that decide
  whether a given app is tiled, floated, ignored, or assigned to a specific
  space/opacity. This is genuine "the tool knows what an app is and treats
  it differently by policy," which is conceptually the same move
  window-organizer makes with hero/normal/minor/banish tiers. What it does
  *not* do: measure a useful minimum size (it has no concept of "technical
  vs useful" minimum at all), weight space allocation, or fully stow a
  window as a first-class automatic layout outcome - rules are binary
  (managed or not), authored by the user up front, not computed at
  layout time from what's on screen.

### AeroSpace
- **Model:** i3-like tree-based tiling, TOML config, its own emulated virtual
  workspaces (deliberately does not use macOS Spaces).
- **Price:** free, open source.
- **Alive:** yes, usable as a daily driver; pre-1.0, breaking changes
  expected; explicitly does not require disabling SIP (built partly as a
  reaction to yabai's SIP requirement) and is not notarized.
- **Content-awareness:** same shape as yabai - per-app window-detection
  rules can assign floating behavior or workspace placement - but again no
  measured minimum sizing, no weighting, no automatic stow.

## Apple's own tooling

### macOS built-in window tiling (Sequoia 15+, carried into current macOS)
- **Model:** drag-to-edge/corner snapping with a preview overlay (half,
  quarter via corners), plus a green-button popover offering 1-4 window
  layout templates; Control+Option+arrow shortcuts.
- **Price:** free, built in.
- **Alive:** yes, actively evolving; treated by reviewers as "welcome and
  overdue" but not a replacement for third-party tools.
- **Documented failure mode, relevant to window-organizer's claim:** layouts
  cap at four windows and anything beyond that "stacks underneath" -
  i.e. Apple's own tiling already makes windows involuntarily disappear
  from the active layout once you have too many, with no visible policy for
  which ones. Reviewers flagged this as a limitation, not a delight.
  Apple's tiling is also documented to ignore developer-set minimum sizes
  (their own News app example), producing exactly the "present but
  worthless" failure window-organizer's README calls out as a known gap in
  its *own* spike.

## Raycast window management
- **Model:** command-driven (not drag), 70+ built-in layout commands, custom
  saved layouts via the "Window Layouts" extension, multi-monitor aware.
- **Price:** free tier covers window management; bundled into a
  freemium/Pro launcher product.
- **Alive:** yes, actively shipped, frequent changelog entries.
- **Content-awareness:** none - user-authored fixed layouts, applied on
  command, same limitation as Moom/Rectangle Pro App Layouts.
- Note: Raycast is also window-organizer's own hotkey-integration path
  (its install.sh wires a Raycast script), so it is simultaneously a
  distribution partner and a category competitor for the "one key,
  everything reorganizes" moment.

## Alt-Tab-adjacent (visibility, not layout)
- **AltTab** - free, open source, actively developed, the default
  recommendation for a Windows-style Alt-Tab preview switcher on macOS.
- **HyperSwitch** - freemium fallback, notable if AltTab is blocked by IT
  policy.
- **Contexts** - search-driven, multi-display switcher; **discontinued**,
  called out explicitly as a risky choice for that reason.
- These solve "what's open and where can I find it," not "how should it be
  arranged." Not real competitors on layout, but relevant: some users' actual
  problem is *findability*, not geometry, and a switcher alone satisfies them.

## DIY / scriptable (proves the idea has occurred to people, ships to no one)
- **Hammerspoon** - free, open-source Lua automation environment with a
  window API (`hs.window`, `hs.grid`, etc). Power users have written
  personal configs that assign priority/size logic per app. This is the
  strongest evidence that "some apps deserve more space than others" is a
  need real people have already tried to solve for themselves - but it has
  always been a bespoke script, never a packaged product with a UI, a
  measured useful-minimum, or a default policy. Zero competitive threat as
  a product; strong validation as a need.

## 2026 newcomers (marketing-heavy, treat claims skeptically)
- **NeoTiler** - released 2026, tiling + workspace switching, no independent
  reviews found; nearly all available copy is the vendor's own blog
  (including its "vs Rectangle/Magnet" comparison posts, written by the
  founder). No demonstrated content-awareness.
- **ShiftPlus** - $24-$39 one-time, a *workspace/session restorer*: captures
  apps + browser profiles + window layout + Spaces under one hotkey and
  replays them. This is adjacent but a different problem - it restores a
  layout you built, it does not decide live what deserves space based on
  what a window is. Its own marketing tells Rectangle/Magnet users to stay
  put if they only want snapping, which is an unusually honest positioning
  signal worth noting.

## Comparison table

| Tool | Interaction model | Automatic per-app policy | Useful-minimum awareness | Automatic stow | Price | Alive |
|---|---|---|---|---|---|---|
| Rectangle / Pro | drag-snap + hotkey | no (App Layouts = manual, saved) | no | no | free / $9.99 | yes |
| Magnet | drag-snap + hotkey | no | no | no | ~$8-10 | yes |
| Moom | hotkey + saved layouts | manual, user-authored per app | no | no | $15/$8 upgrade | yes |
| BetterSnapTool | drag-snap + hotkey | no | no | no | $1.99-2.99 | yes |
| Swish | trackpad gestures | no | no | no | ~$16 | yes |
| Loop | hotkey + radial menu | no | no | **manual** (Stash) | free/OSS | yes |
| Tiles (FreeMacSoft) | drag-snap | no | no | no | free | yes |
| Amethyst | automatic tiling | no | no | no | free/OSS | yes |
| yabai | automatic tiling | **yes, binary rules** | no | no | free/OSS | yes |
| AeroSpace | automatic tiling | **yes, binary rules** | no | no | free/OSS | yes |
| Apple built-in | drag-snap + hotkey | no | no | **involuntary, unpoliced** (>4 windows) | free | yes |
| Raycast | command-driven | no (saved layouts, manual) | no | no | free/Pro | yes |
| ShiftPlus | hotkey session restore | no | no | no (restores what you saved) | $24-39 | yes |
| Hammerspoon | scripted, DIY | **yes, if you write it** | if you write it | if you write it | free/OSS | yes |
| **window-organizer** | hotkey, on-demand | **yes, 4-tier + weight** | **yes, probed 1x1 refusal** | **yes, automatic** | n/a (spike) | spike |

Sources: [Rectangle Pro](https://rectangleapp.com/pro/), [Rectangle Pro worth it?](https://www.mactools.pro/blog/rectangle-pro-is-it-worth-it), [Magnet App Store](https://apps.apple.com/us/app/magnet/id441258766), [Magnet essential](https://evanmccann.net/blog/magnet-is-an-essential-macos-app), [Moom announcement](https://manytricks.com/blog/?p=6385), [Moom tested](https://9to5mac.com/2025/01/28/tested-moom-is-my-new-mac-window-management-app/), [BetterSnapTool vs Magnet](https://setapp.com/app-reviews/magnet-vs-bettersnaptool), [BetterSnapTool](https://folivora.ai/bettersnaptool/), [Swish](https://highlyopinionated.co/swish/), [Swish on Setapp](https://setapp.com/apps/swish), [Loop GitHub](https://github.com/mrkai77/loop), [Loop on HN](https://news.ycombinator.com/item?id=40717698), [Tiles - FreeMacSoft](https://freemacsoft.net/tiles/), [Tiles - workspace app](https://gettiles.vercel.app/), [Amethyst GitHub](https://github.com/ianyh/Amethyst), [yabai wiki - SIP](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection), [Mosaico (SIP-free yabai alt)](https://mautoblog.com/en/posts/mosaico-tiling-window-manager-macos-yabai-no-sip-2026/), [AeroSpace GitHub](https://github.com/nikitabobko/AeroSpace), [macOS Sequoia tiling - MacRumors](https://www.macrumors.com/2024/06/12/macos-sequoia-window-tiling/), [macOS Sequoia tiling - Macworld](https://www.macworld.com/article/2365751/macos-sequoia-windows-tiling-dont-ditch-that-tiling-app.html), [Raycast window management](https://www.raycast.com/core-features/window-management), [AltTab comparison](https://alternativeto.net/software/hyperswitch/?platform=mac), [Plumb GitHub](https://github.com/Lv-0/plumb), [NeoTiler](https://getneotiler.com/blog/rectangle-vs-magnet-vs-neotiler-best-mac-window-manager/), [ShiftPlus](https://shiftplus.app/).
