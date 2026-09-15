# window-organizer - product gap analysis

Scope: what is missing to go from "working CLI spike on my machine" to "an app a
stranger can download, install, and trust." Read-only review of the spike source
(`main.swift`, `priority.swift`, `dump.swift`, `setup-hotkey.sh`, `install.sh`),
`README.md`, `AGENTS.md`, and GitHub issue #2.

Each gap: **name** - why it matters - size (S/M/L) - priority (BLOCKER / IMPORTANT /
NICE-TO-HAVE).

BLOCKER = cannot ship a public release without this.
IMPORTANT = will generate support burden, churn, or distrust if missing, but a v1 could
technically exist without it.
NICE-TO-HAVE = real product value, defer past v1.

---

## 1. Packaging and distribution

### 1.1 No app bundle at all - BLOCKER - M
Today there are three raw Mach-O binaries (`wdump`, `wprobe`, `warrange`) built by
`build.sh` and copied into `~/.local/bin` by `install.sh`. There is no `.app`, no
`Info.plist`, no bundle identifier, no icon. macOS permission grants (Accessibility,
Screen Recording), Launch Agents, and Gatekeeper/notarization all key off a bundle
identity, not a bare executable path. A raw binary in `~/.local/bin` cannot request
Accessibility with a friendly name/icon in the TCC prompt, cannot register as a login
item via `SMAppService`, and is invisible to Spotlight/Launchpad. This is the
foundational gap everything else in this section depends on.

### 1.2 No code signing - BLOCKER - S/M
Nothing here is signed. An unsigned binary downloaded from the internet is quarantined
by Gatekeeper and, on first run, macOS shows "cannot be opened because it is from an
unidentified developer" with no easy override in newer macOS versions (the old
right-click-Open bypass is being phased down). Needs an Apple Developer ID
($99/yr), a Developer ID Application certificate, and `codesign` in the build/release
pipeline.

### 1.3 No notarization / hardened runtime - BLOCKER - S/M
Signing alone is not enough for smooth distribution outside the App Store - Apple's
notary service must staple a ticket, and the hardened runtime entitlements need to be
set correctly. Given this app uses Accessibility APIs and reads window contents (a
sensitive combination), Apple's automated notarization scanner is more likely to flag
it than a typical app; budget time for entitlement iteration, not just a one-shot
`notarytool submit`.

### 1.4 Mac App Store is very likely not viable - IMPORTANT (as a decision to make now, not a build task) - S to decide, but it forecloses other paths
The tool moves and resizes *other apps' windows* via the Accessibility API and reads
window titles system-wide via `CGWindowListCopyWindowInfo` / Screen Recording. App
Review has historically rejected or heavily restricted apps that manipulate other
processes' windows this way (it is adjacent to the class of "system utility" that
Sandbox rules exist to prevent) - and the App Sandbox entitlements available to
Store apps do not cleanly support unrestricted AX control of arbitrary third-party
apps. This needs an explicit, early decision: **direct distribution outside the App
Store is almost certainly required**, which then drives 1.2/1.3/1.5 as hard
requirements rather than nice-to-haves. Do not spend time on a Store submission path
without first prototyping whether Review will even accept the entitlement request.

### 1.5 No installer / update artifact - IMPORTANT - S/M
`install.sh` builds from source and copies binaries into `~/.local/bin` - this assumes
a working Swift toolchain on the end user's machine, which a "stranger" installing an
app will not have. Ship a `.dmg` (or `.pkg`) with a prebuilt, signed, notarized
`.app`. Building from source cannot be the distribution mechanism for a real product.

### 1.6 No Homebrew cask - NICE-TO-HAVE (but cheap and high-leverage for this audience) - S
Given the target user profile (developer-adjacent, already has terminals/editors
tiered as "hero" apps), a `brew install --cask window-organizer` path is the lowest-
friction distribution channel and doubles as an update mechanism (`brew upgrade`).
Worth doing early even before a "real" installer UI, once there is a signed/notarized
`.app` to point the cask at.

### 1.7 Universal binary / architecture coverage - IMPORTANT - S
`build.sh` was not shown in full but the install flow implies a local build; confirm
the shipped binaries are arm64+x86_64 universal (or arm64-only with an honest minimum-
OS statement). Not doing this silently breaks on the other architecture family.

---

## 2. Permissions and onboarding

### 2.1 No first-run permission flow - BLOCKER - M
Today: `AXIsProcessTrusted()` is checked in `main.swift` and on failure it prints
"Accessibility not granted." to a terminal (`main.swift` lines ~398-401) and exits.
`CGPreflightScreenCaptureAccess()` in `dump.swift` similarly just prints a warning
line. A stranger installing a GUI app will never see a terminal. First run must:
detect each missing grant with the preflight APIs already in use, show a real window
explaining *why* the app needs it (one sentence each, not the TCC boilerplate), and
deep-link straight to the correct pane
(`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` /
`...Privacy_ScreenCapture`) instead of telling the user to hunt through System
Settings themselves.

### 2.2 No re-check without restart - BLOCKER - S
`AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()` are call-and-forget in
the spike; a real app needs to poll (or, for Accessibility, use the
`AXIsProcessTrustedWithOptions` prompt option and re-check on foreground/active
notifications) so that once the user grants the permission in System Settings and
tabs back, the app notices without being force-quit and relaunched. This is a known
sharp edge in macOS: Screen Recording in particular has historically required an app
*relaunch* (not just a re-check) to take effect after being granted - the onboarding
flow needs to detect this case specifically and offer a one-click relaunch, or it will
look broken.

### 2.3 Permission attaches to the launching process, not the tool - BLOCKER (design decision, not just docs) - M
`setup-hotkey.sh` says this out loud: "macOS attributes the window moves to skhd, not
to warrange, because skhd is the process that launches it. Granting warrange alone is
not enough." This is currently solved by telling the user, in a terminal, to grant
Accessibility to *skhd* - a background daemon most users have never heard of and
cannot identify in the System Settings list (it shows as a bare Unix binary, no icon,
possibly no friendly name). Once the tool becomes a signed `.app` that owns its own
global hotkey (see 5.1), the grant target becomes the app itself, which is
identifiable - but if skhd or any other launcher is kept as an option, onboarding must
explicitly explain and verify *which* process needs the grant, because this is the
single most likely support complaint ("I granted it and it still doesn't work").

### 2.4 No handling of revoked permissions at runtime - BLOCKER - S
Nothing detects a permission being revoked *after* grant (user turns it off later, or
an OS update resets TCC, which happens on major upgrades). The current behavior would
be silent failure or partial failure (e.g., moves fail but the app doesn't say why).
Every arrange action should re-verify trust and surface a clear, specific error state
rather than doing nothing or moving only some windows.

### 2.5 Screen Recording loss degrades silently by design, but the UI doesn't say so - IMPORTANT - S
`AGENTS.md` documents the intended behavior: "Degrade rather than fail when one is
missing: without Screen Recording the layout engine must fall back to app identity
alone." Good design decision, but the current spike doesn't seem to surface this state
to the user - `dump.swift` prints a yellow warning line, but `warrange` (`main.swift`)
never checks `CGPreflightScreenCaptureAccess()` at all before proceeding, meaning
title-blind layout could happen with zero indication anything is degraded. A real app
needs a persistent, visible "degraded mode" indicator (e.g., in the menu bar icon or
a badge) any time it is running with only partial permissions.

### 2.6 No explanation of *why* each permission is needed, in user language - IMPORTANT - S
"Accessibility" and "Screen Recording" are opaque TCC category names. First run needs
plain language: "Accessibility lets window-organizer move and resize windows.
Screen Recording lets it read window titles so it knows a browser from a terminal -
it never records or stores screen content." That second sentence also does real work
for the privacy posture gap (6.4).

---

## 3. Runtime shape

### 3.1 No persistent process at all today - BLOCKER - M/L
`warrange` currently runs once per invocation (spawned by skhd on hotkey) and exits.
There is no long-lived process, so there is nothing to show "the app is alive and
watching," no menu bar icon, and (per issue #2) the planned focus-recency recorder
explicitly requires "a lightweight recorder [that] samples the frontmost window on an
interval and appends focus events to a local log" - i.e., issue #2 already assumes a
background daemon exists, but nothing in the current architecture provides one. This
is a real architectural decision, not a polish item: menu-bar app (NSStatusItem) that
also runs the recency recorder as an internal timer is the natural shape given macOS
conventions and the existing Swift/AppKit codebase; a separate always-on daemon adds
IPC complexity for little benefit at this scale.

### 3.2 No menu bar presence - BLOCKER - M
A tool that only does something when a hotkey is pressed and is otherwise invisible
is indistinguishable from "not installed" or "crashed" to a new user. A menu bar icon
is the minimum affordance for: confirming the app is running, one-click access to
undo, a visible permission-degraded state (2.5), and a path to preferences (4.1)
without a config file. This is standard for the entire class of tool (Rectangle,
Magnet, Moom, etc.) and its absence will read as unfinished by anyone who has used
those.

### 3.3 No launch-at-login - IMPORTANT - S
Nothing sets up launch-at-login. Modern approach is `SMAppService.mainApp.register()`
(macOS 13+), toggled from a preferences UI - no more helper-app LaunchAgent plist
dance required. Without this, every reboot silently disables the tool (hotkeys stop
working) with no indication why, which will look like a bug.

### 3.4 No crash/hang recovery story - IMPORTANT - S/M
If the menu-bar/daemon process crashes or hangs, hotkeys silently stop working. Needs
either OS-level supervision (a LaunchAgent with `KeepAlive`, if going the
daemon route) or, if it's a plain menu-bar app, at minimum a way for the user to
notice it's gone (an anomaly if it vanishes from the menu bar) and a documented "quit
and relaunch" recovery path surfaced somewhere findable (not "cat a log file").

### 3.5 "What does the user do when it misbehaves" is currently: read a terminal - BLOCKER - M
Every diagnostic in the spike (permission state, mission-control-open refusal, "no
windows on screen", cannot-fit warnings) is a colored line printed to stdout by a
process the user only sees if they launch it from Terminal. In the shipped app none of
that exists for the user. Every one of those states needs a GUI equivalent: a
transient notification (macOS `UNUserNotificationCenter` banner) or a status-item
menu entry, at minimum for: permission missing, Mission Control open (arrange
refused), nothing arranged (no windows), and windows that couldn't fit.

---

## 4. Configuration

### 4.1 No preferences UI - BLOCKER - L
Config is `~/.window-spike/priorities.json`, hand-edited. `priority.swift` documents
the schema loading and defaults-merge logic clearly, but there's no UI to change tier/
weight/max/useful size per app, discover installed apps to add them, or validate the
file (malformed JSON currently just falls back silently to defaults per
`loadPriorities()` - the user gets no error, just their edit appears to have "not
worked"). A stranger will not hand-edit JSON. This is the largest single missing
surface area of the whole project and should be scoped early since issue #2
explicitly keeps config-as-a-file as the model for the *next* increment ("Any
graphical preferences interface" is called Out of Scope there) - meaning this gap is
being deliberately deferred by the team, which is a real product-timeline decision
worth surfacing, not just an oversight.

### 4.2 No way to discover app names / bundle IDs from the UI - IMPORTANT - S/M
Priorities are keyed by `NSWorkspace...localizedName` strings (e.g., "Microsoft
Outlook") typed by hand into JSON. There's no picker that lists currently-running or
installed apps so a user can add an override without knowing the exact display name
macOS uses internally (which does not always match the name on the Dock or in
Spotlight, e.g. "Google Chrome" vs "Chrome"). A typo silently means "no override
applied" with zero feedback.

### 4.3 No per-Space / per-display-arrangement profiles - NICE-TO-HAVE - M/L
Today one config applies everywhere. A laptop-only layout and a laptop+external-
monitor layout have very different useful pane counts (issue #2 user story 22 gestures
at this: "the number of windows kept on screen to adapt to display size"). Full
per-Space profiles are a larger feature; the display-count-aware default is closer to
table stakes and could land earlier.

### 4.4 No import/export or backup of config - NICE-TO-HAVE - S
Once there's a UI on top of the JSON file, users will want to back up or share tuned
priority sets. Trivial once 4.1 exists (it's just read/write the same file with a
file picker), but currently there's no story at all - a reinstall or a `rm -rf
~/.window-spike` wipes tuning with no warning.

### 4.5 Malformed/corrupt config fails silently - IMPORTANT - S
`loadPriorities()` in `priority.swift`: if the file exists but fails to parse as
`[String: Any]`, the load falls through the same code path as "file missing" - and a
parse failure returns `defaultPriorities` directly without ever rewriting the corrupt
file, so the user's edits are silently ignored on every run with zero error surfaced.
A GUI needs to detect this and tell the user their file didn't parse, ideally pointing
at the JSON error.

---

## 5. Hotkeys without a third-party daemon

### 5.1 Dependency on skhd is a real distribution liability - BLOCKER (to decide) / IMPORTANT (to build) - M
`setup-hotkey.sh` installs and configures `skhd` via Homebrew, writes into the user's
`~/.config/skhd/skhdrc` inside a marked block, and separately requires the user to
grant Accessibility to skhd itself (2.3). This is fine for a personal spike but wrong
for a public app: it requires Homebrew, a second unsigned/unnotarized third-party
daemon the user has to trust and separately manage (`pgrep -x skhd`, log tailing at
`/tmp/skhd_$USER.err.log`), and a second Accessibility grant whose relationship to
"window-organizer" is not obvious to the user. A real app should register its own
global hotkey in-process (`NSEvent.addGlobalMonitorForEvents` requires Accessibility
already granted to the app itself, or the older Carbon `RegisterEventHotKey` /
`MASShortcut`-style approach) so there is exactly one process, one grant, and one
thing to explain. This is very likely the single biggest architectural change between
the spike and a real v1, because it also resolves 2.3.

### 5.2 The Automator fallback documented in setup-hotkey.sh is not a real answer - NICE-TO-HAVE (drop)
The "zero-dependency alternative" at the bottom of `setup-hotkey.sh` (Automator Quick
Action + Keyboard Shortcuts assignment) is a manual, multi-step, GUI-only workaround
that most users will never discover or complete correctly. It is fine as a spike-era
escape hatch but should not be presented as a shipping option - it's evidence that
the team already knows the daemon dependency is uncomfortable.

### 5.3 No customizable hotkeys - NICE-TO-HAVE - S/M
Current bindings (`cmd+alt+A`, `cmd+alt+Z`, `cmd+alt+S`) are hardcoded in the shell
script that writes skhd config. Once the app owns its own hotkey (5.1), a
preferences UI needs a key-capture control to rebind, plus conflict detection against
existing system/app shortcuts.

---

## 6. Lifecycle and trust

### 6.1 No update mechanism - BLOCKER - M
No Sparkle (or equivalent) integration, no version check, nothing. Outside the App
Store, this is the standard solution (signed appcast feed, delta updates, in-app "an
update is available" prompt). Without it, every fix requires the user to manually
notice, re-download, and reinstall - which most never do, meaning bug fixes never
actually reach the field.

### 6.2 No crash reporting - IMPORTANT - S/M
Given the AX/CG surface area this tool touches (documented hostile states: Mission
Control thumbnail data, fullscreen Space transitions, apps that lie about resize) it
will crash or misbehave on edge cases not yet seen. Without opt-in crash reporting
(e.g., `PLCrashReporter`/Sentry, or even just Apple's own crash log sharing), the team
has no way to learn about failures a stranger hits and never reports.

### 6.3 No uninstall path - BLOCKER - S
There's no uninstaller and no documented list of what's on disk. Today that's:
`~/.local/bin/{wdump,wprobe,warrange}`, `~/.window-spike/{priorities.json,
minsizes.json, undo.json, samples.jsonl if --log used}`, plus (via setup-hotkey.sh) a
marked block in `~/.config/skhd/skhdrc` and a running skhd service. A real app needs
either a proper uninstaller or, at minimum, a documented "remove window-organizer"
doc/menu action that reverses all of the above, including deregistering the login
item and revoking (or at least explaining how to revoke) the permission grants.

### 6.4 Privacy posture is undocumented for an end user - IMPORTANT - S
The tool reads every visible window's title system-wide (`kCGWindowName` via Screen
Recording) - which can include search queries, message previews, document names,
URLs. Issue #2 explicitly plans a *persistent focus history log* on disk ("local and
deterministic... bounded, local, inspectable, deletable, and never transmitted" - user
stories 17-18). None of this is wrong, but none of it is disclosed anywhere a stranger
would see before granting Screen Recording. A real release needs a short, honest
privacy statement (what is read, what is stored, that nothing leaves the device) shown
*before* the Screen Recording prompt, not buried in a README.

### 6.5 No settings/state migration story across versions - NICE-TO-HAVE - S
`priorities.json`'s loader already does a reasonable job of this at the schema level
(merges saved keys over current defaults, per `loadPriorities()`), which is good
prior art - but nothing currently versions the file or the undo/cache files, so a
future breaking schema change has no migration path. Worth a `"version"` field before
it's needed, not after.

---

## 7. Discoverability and feel

### 7.1 No feedback at the moment the hotkey is pressed - BLOCKER - M
Pressing the hotkey today either silently rearranges windows (`--apply`) or does
nothing visible (dry run only happens when run manually from a terminal without
`--apply` - which a GUI user will never do). A stranger pressing a hotkey needs *some*
acknowledgment that something happened: a brief animation, a subtle sound, or at
minimum an instant, correct result with no perceptible lag. Given the tool also
measures and moves windows synchronously (`measureMinimums` can trigger a visible
1x1-then-restore flicker per new app, per `AGENTS.md`'s own description: "the
measuring flicker happens once per app"), first-use of the hotkey on an unfamiliar app
will visibly flicker that window - which needs to either happen invisibly (off-screen
measurement) or be explained so it doesn't read as a bug.

### 7.2 Stow decisions aren't explained to the user - IMPORTANT - S/M
This is the direct subject of issue #2 (user story 6: "I want to know why a window was
stowed, so that the behaviour does not feel arbitrary"; user story 20: dry run should
show stow reasons). The current `main.swift` output does print a `cannot fit` state
per unplaced window in the terminal table, and on `--apply` it minimizes them - but
none of this reaches a GUI user, and there's no reason string at all yet (below-useful-
minimum vs evicted-by-priority vs evicted-by-recency, as issue #2 specifies). This is
core to the tool not feeling arbitrary or hostile, per the project's own thesis
statement in the README ("nothing changes until you ask").

### 7.3 No undo affordance beyond a hotkey - IMPORTANT - S
`--undo` exists and works (restores geometry, un-minimizes) but is only reachable via
a second memorized hotkey. A menu-bar item needs a visible "Undo last arrange" action,
and ideally the moment right after an arrange should surface it prominently (similar
to macOS's own "Undo Move" toast pattern) since that's exactly when a user decides the
result was wrong.

### 7.4 No empty/error states designed for a GUI - IMPORTANT - S
Enumerated in the code but never designed for a non-terminal user: "no windows on
screen" (`main.swift` ~498-501), "Mission Control is open, re-run after closing it"
(~489-494), "nothing to undo" (~424-426), Accessibility not granted (~398-401). Each
currently prints colored ANSI text. Each needs a corresponding notification/menu
state with the same information, phrased for someone who has never seen the CLI.

### 7.5 No onboarding walkthrough of *what the tool does* before first use - NICE-TO-HAVE - S/M
The README's pitch ("nothing changes until you press a key... it also knows what your
windows are, not just where they are") is genuinely good positioning and should
survive into a first-run screen or two: what the hotkey does, that hero/normal/minor/
banish tiers exist and are editable, and that undo is one keystroke away. Not a full
tutorial - two or three screens, skippable.

### 7.6 No indication of which app is currently "hero" - NICE-TO-HAVE - S
The hero is decided dynamically as "whatever you are actually in right now"
(`main.swift` ~504-511) which is a good default but invisible - there is no
confirmation of which app got the master pane before or after an arrange, so a user
who expected a different app to dominate has no feedback loop to understand why.

---

## 8. Things the above sections don't cover

### 8.1 Localization / non-English support - NICE-TO-HAVE - M
Everything is English-only, including app name lookups from `NSWorkspace` (which are
already localized by the OS, so config keys like "Microsoft Outlook" may not match on
a non-English system locale - worth at least testing on one non-English locale before
release, since it silently breaks per-app overrides otherwise).

### 8.2 Accessibility of the app's own UI (not to be confused with the Accessibility API it consumes) - IMPORTANT - S
Ironic gap for a tool built entirely on the Accessibility API: once there's a real
menu-bar UI and preferences window, they need to themselves be usable via VoiceOver,
keyboard navigation, and support Reduce Motion/Increase Contrast, both as a baseline
quality bar and because App Store review (if ever attempted) and general Mac user
expectations check for this.

### 8.3 Multi-monitor and external-display hot-plug behavior - IMPORTANT - S/M
`usableDisplays()` reads `NSScreen.screens` fresh each run, which is correct for a
one-shot CLI invocation, but a persistent menu-bar app needs to react to
`NSApplication.didChangeScreenParametersNotification` (displays connected/
disconnected/rearranged) - e.g., invalidating any cached per-display assumptions and
not crashing or misplacing windows mid-arrange if a display is unplugged while the
app is running.

### 8.4 Sandboxing and per-app resize "compliance" reputation - NICE-TO-HAVE - M
`wprobe`/`dump.swift` and `AGENTS.md` note apps lie about resize acceptance ("Never
trust that a window went where you put it"). Over time, a real product benefits from
crowd-sourced or shipped known-quirky-app data (e.g., a bundled table of apps known to
mis-report minimums) rather than every user's install re-discovering the same quirks
via the flicker-measurement dance. Not required for v1, but worth flagging as a
long-term moat/quality lever.

### 8.5 Legal basics: license is present, but no EULA/support contact/website - NICE-TO-HAVE - S
MIT license exists in the README, which is good and sufficient for open source
distribution. For a signed, notarized, "stranger installs it" release, a minimal
support surface (a URL for the Sparkle appcast to point at, an issues link, a one-line
privacy statement per 6.4) is expected and costs almost nothing to add.
