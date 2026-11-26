# MouseJiggler — backlog

Development ideas and next steps for this project. Remove an item once it is done.
Public repo: no personal details here (see `rules.md`).

- **Real-life check:** leave the Mac alone for 10+ minutes and confirm it is never seen as idle
  (screen does not dim, apps do not show you as away). Also check that typing alone (without touching the mouse) pauses it: the
  icon turns into a plain arrow.
- **Stable code signature:** every rebuild asks for the Accessibility permission again (ad-hoc
  signing). A self-signed "code signing" certificate in the login keychain would keep it across
  rebuilds. It adds a certificate to the keychain, so it needs the user's OK first.
- **Settings in the menu (only if wanted):** pause between moves (now 15-40 s), restart delay
  (now 5 s), "pause for 1 hour".
