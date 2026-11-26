# MouseJiggler — project rules

> **This repository is PUBLIC** (or about to be). Never write personal details in any file or
> commit message: no names, no employer, no workspace paths, no mention of other private repos, no
> names of specific chat or work apps (describe it as a generic mouse jiggler).
> Write "the user". Session-log entries follow the same rule.

## Scope
A small macOS menu-bar app that keeps the Mac from going idle while the user is away from the
keyboard, and pauses while they use the Mac. What it does, the menu-bar icons,
build/install and the Accessibility permission are described for everyone in `README.md`. This
file holds the developer notes and the rules for working on it.

Created 2026-11-26. Tags: `personal`, `macos`, `coding`. UI language: English.

## Design decisions (and why)
- **Small periodic glides, not continuous wandering:** every 15-40 s (random), a 0.4 s glide of
  6-25 points within 25 points of where the user left the pointer, 12 points away from screen
  edges. Enough to keep the idle time low (apps usually react after a few minutes), barely
  noticeable while reading.
- **First move right when the 5 s pause ends**, so the restart is visible.
- **Pauses on any user input**, not only the mouse (keys, clicks, scrolls, drags, gestures):
  a moving pointer while typing would be annoying.
- **Never jiggles** while the screen is locked, the screensaver runs or another user session is
  in front. Coming back counts as input, so the first move waits the usual 5 s.

## Measured facts (2026-11-26, macOS 27.2) — keep them in mind before changing anything
- Only a real `CGEvent` mouse-move posted at `.cghidEventTap`, from an app with the
  **Accessibility** permission, resets the idle time other apps read
  (`CGEventSourceSecondsSinceLastEventType(.combinedSessionState, any)`) and IOKit `HIDIdleTime`.
- Without the permission, posted events are silently dropped. `CGWarpMouseCursorPosition` moves
  the pointer but resets nothing. `IOPMAssertionDeclareUserActivity` resets nothing seen by
  other processes.
- The idle counters are coarse: updated about every 0.5 s, never below ~0.5 s.
- **Event types 32 and above return the "any input" counter.** Watching them made the app take
  its own moves for the user (it paused itself after every move). Types 18-20 are never
  updated. User-input types in use: keyDown, flagsChanged, mouse down/dragged (left, right,
  other), scrollWheel, 29 (gesture), 30 (magnify), 31 (swipe).
- An app's own view of the idle counters lags behind. Check idle detection from a **separate
  observer process** that samples `secondsSinceLastEventType` and shows a reset after each move.
  A simulated user move = `CGWarpMouseCursorPosition` from another process (no permission
  needed).

## Build, install, test
- `./build.sh` / `./build.sh --install` (see README). Installed copy: `/Applications/MouseJiggler.app`.
- **Every rebuild needs the Accessibility permission again** (ad-hoc signature). `--install`
  resets only MouseJiggler's stale entry (`tccutil reset Accessibility local.mousejiggler`); the
  user must switch it on again. Rebuild only when needed, and say so before doing it.
- Self-test: quit the menu-bar copy, ask the user to keep their hands off the Mac, then
  `open -W -n /Applications/MouseJiggler.app --args --test 40 --interval 2-3 --log-idle`
  (other flag: `--resume SECONDS`). Log: `~/Library/Logs/MouseJiggler.log`, each pause with
  its reason; rolls over to `MouseJiggler.old.log` past 1 MB.

## Rules
- Public repo: see the note at the top.
- Keep the app dependency-free. Propose any new framework or tool before adding it.
- No prebuilt binaries in GitHub releases: the app is not notarized, users build it themselves.
