# MouseJiggler — session log

Public repo: no personal details here (see `rules.md`).

## 2026-11-26 — First version, English UI, prepared for publication

- **Request:** a menu-bar app that moves the mouse at random so the Mac never goes idle, pauses when the user takes the mouse back and restarts 5 s after they let go. Small periodic glides (15-40 s, a few pixels) chosen over continuous wandering.
- **Why the Accessibility permission is unavoidable:** measured before writing the app. Without it the posted events are dropped; a pointer warp or Apple's "user is active" call changes nothing in the idle counter other apps read. Only a real posted mouse event works.
- **Verified with an independent observer process** (the way other apps read the system idle time): every glide resets the idle counter. Simulated user move → pause with its reason in the log → restart exactly 5 s later.
- **Bug found by testing and fixed:** watching event types 32+ made the app take its own moves for the user (macOS answers those types with the "any input" counter).
- **Pauses on keyboard, clicks, scrolls and gestures too**, never runs while the screen is locked. Side effect: while it runs, the screen never dims or locks by itself.
- **UI switched to English and the repo prepared for publication:** README, MIT license, notes rewritten without personal details or references to specific apps. Start at login was declined (the user opens the app by hand).
