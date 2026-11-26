# MouseJiggler

A tiny macOS menu-bar mouse jiggler: it nudges the pointer now and then so your Mac never goes
idle while you are away from the keyboard, and it gets out of your way the moment you come back.

- Every 15–40 seconds (at random) it glides the pointer a few pixels, staying close to where you
  left it and away from screen edges (Dock, hot corners).
- As soon as you move the mouse or trackpad, type, click or scroll, it pauses.
- 5 seconds after your last input it starts again.
- It never moves while the screen is locked or the screensaver is running.
- The menu-bar icon shows what it is doing, and the menu has **Pause** / **Resume**.

No third-party dependencies: Swift and Apple frameworks only.

## Menu-bar icon

| Icon (SF Symbol) | Meaning |
| --- | --- |
| `cursorarrow.motionlines` | Active: the next small move is coming (the menu shows the countdown) |
| `cursorarrow` | Paused because you are using the Mac; resumes 5 s after you stop |
| `pause.circle` | Paused from the menu |
| `lock` | Screen locked or screensaver running |
| `exclamationmark.triangle` | Accessibility permission missing: the pointer cannot move |

## Requirements

- macOS 15 or later (tested on macOS 27.2, Apple silicon).
- Apple's Command Line Tools (`xcode-select --install`). Xcode itself is not needed.

## Build and install

```bash
git clone https://github.com/RinaldiPortanova/MouseJiggler.git
cd MouseJiggler
./build.sh --install
```

`./build.sh` alone builds `build/MouseJiggler.app`. With `--install` it also quits a running
copy, moves the new build into `/Applications` (the previous version goes to the Trash), resets
MouseJiggler's Accessibility entry and starts the app.

There is no prebuilt download: the app is not signed or notarized by Apple, so build it
yourself.

## The Accessibility permission

macOS only accepts simulated mouse events from apps you allow in
**System Settings → Privacy & Security → Accessibility**. On first launch macOS asks for it;
otherwise use **Grant Accessibility Permission…** in the app's menu.

The build is ad-hoc signed, so macOS treats every rebuild as a new app: after each
`./build.sh --install`, switch MouseJiggler on again in that list.

## How it works

- **The move is a real "mouse moved" event** posted at the HID level. For macOS and for apps
  that read the system idle time (`CGEventSourceSecondsSinceLastEventType`), it is the same as
  you touching the mouse.
- **What does not work** (measured on macOS 27.2): moving the pointer with
  `CGWarpMouseCursorPosition`, or calling `IOPMAssertionDeclareUserActivity`, does not reset
  the idle time other apps see. Posted events from an app without the Accessibility permission
  are silently dropped.
- **Telling you apart from the app:**
  - the app remembers where it put the pointer; any other position means you moved it (a grab
    in the middle of a glide stops it at once);
  - for keys, clicks, scrolls, drags and trackpad gestures it reads macOS's "seconds since the
    last event of this type" counters. The app only ever sends "mouse moved", so those are
    always you.
  - It never reads what you type and needs no Input Monitoring permission: it only asks macOS
    how long ago the last key press happened.
- Only one copy runs at a time (two copies would take each other's moves for you).

## Side effects

While MouseJiggler is active, your Mac never becomes idle: the display will not sleep and the
screen will not lock by itself. Lock it yourself when you walk away (Control-Command-Q); the
app then pauses.

## Troubleshooting

- Log: `~/Library/Logs/MouseJiggler.log` (each pause with its reason, permission changes,
  lock events).
- Self-test (the pointer really moves, so keep your hands off): quit the menu-bar copy, then
  `open -W -n /Applications/MouseJiggler.app --args --test 40 --interval 2-3 --log-idle`
  runs for 40 s with a move every 2–3 s. Other flag: `--resume SECONDS`.

## Disclaimer

Provided as is, without warranty (see the license).

## License

[MIT](LICENSE)
