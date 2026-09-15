# window-organizer

A macOS window organizer that takes over nothing until you press a key.

Tiling window managers ask you to hand over every window forever and learn a new
keyboard grammar first. Most people install one, never turn it on, and go back to
overlapping windows. This is the other bargain: **nothing changes until you ask, then
it fixes what is in front of you and gets out of the way.**

It also knows what your windows *are*, not just where they are. A music player does
not need a monitor. An inbox does not need permanent pixels. A terminal does.

## Status

Working spike. The layout engine runs, and on a real desktop it measured:

| | before | after |
|---|---|---|
| window pixels hidden | 64.8% | **0.0%** |
| screen stacked 2+ deep | 77.2% | **0.0%** |
| windows >50% buried | 5 | **0** |

Not a product yet - see [Known gaps](#known-gaps).

## Tools

```
wdump      snapshot every on-screen window and quantify the mess
wprobe     per-app move/resize compliance, permissions, writability
warrange   the layout engine
```

```sh
cd spike && ./install.sh          # builds and installs into ~/.local/bin
warrange --help
```

Needs **Accessibility** (to move windows) and **Screen Recording** (to read window
titles, which is the intent signal). Both are granted in System Settings ->
Privacy & Security.

```sh
warrange                    # dry run: print the plan, change nothing
warrange --apply            # do it
warrange --undo             # put everything back, un-minimising as needed
warrange --master 0.6       # give the focused app 60% of the display
warrange --spill            # use other displays rather than cramming one
```

Per-app priorities live in `~/.window-spike/priorities.json` - four tiers (`hero`,
`normal`, `minor`, `banish`), a weight, and a size cap. Edit it; it is yours.

## What we learned building it

macOS makes this harder than it looks, and most of it is undocumented:

- **Two APIs, both required.** `CGWindowList` knows what is genuinely on screen and in
  what order but cannot move anything; the Accessibility API can move windows but also
  returns windows resting on other Spaces. Use AX alone and you drag Discord in from
  another desktop.
- **Minimum sizes are unknowable.** There is no minimum-size attribute. The only way to
  learn one is to ask for a 1x1 window and read back the refusal. They also vary *per
  window*, not per app: Outlook's inbox needs 1210x684 while its compose window needs
  640x600.
- **Equal-split tiling is often impossible.** Outlook alone needs 70% of the width of a
  14-inch display. A 2x2 grid cannot be built with it on screen.
- **Fullscreen windows refuse everything** and occupy their own Space, so they report as
  the only window that exists.
- **Mission Control lies.** While it is open `CGWindowList` returns *thumbnail* geometry.
  Arranging from it would fling every window into preview-sized rectangles.

Details in [AGENTS.md](AGENTS.md).

## Known gaps

Tracked as [issues](https://github.com/shlok1806/window-organizer/issues). The ones worth
knowing before you rely on it:

- Minimum sizes are cached per app, so a second window of the same app can clamp past
  its slot and overlap its neighbour.
- Nothing verifies the layout after applying it, so a window that lies about accepting a
  size is never detected or reflowed.
- A window you just opened is not recognised as wanted, so it can be stowed immediately
  after you open it.
- `--master` hands the hero a fixed slab without checking the hero's own minimum, so a
  small display or a low fraction can plan it below a usable size.

Layout plans against **useful** sizes rather than merely technical ones, so a browser is
either given room to be a browser or stowed - it is never placed at 222px tall.

## Licence

MIT
