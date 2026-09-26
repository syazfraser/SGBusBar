# Contributing to SGBusBar

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug or asking for a feature

Open an [issue](https://github.com/syazfraser/SGBusBar/issues/new/choose) and pick the bug report or feature request form. For bugs, your macOS version, the SGBusBar version (Settings > About) and a screenshot help a lot.

Security problems go through [SECURITY.md](SECURITY.md) instead, not a public issue.

## Setting up

1. Install **Xcode 26** from the Mac App Store.
2. Clone the repo and open `SGBusBar.xcodeproj`.
3. Get a free [LTA DataMall API key](https://datamall.lta.gov.sg/content/datamall/en/request-for-api.html) to see live times when you run the app.
4. Press **⌘R** to run and **⌘U** to run the tests.

If `xcodebuild` on the command line says it needs Xcode, either run `sudo xcode-select -s /Applications/Xcode.app` or put `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in front of the command.

## Making a change

1. Fork the repo and create a branch from `main`, e.g. `fix/popup-arrow` or `feature/leave-now-alert`.
2. Keep the change focused: one fix or feature per pull request is easiest to review.
3. Match the code around it: SwiftUI views, small focused types, and comments that explain *why* rather than *what*.
4. Add or update tests in `SGBusBarTests/` for logic changes (colours, timetables, parsing, stop editing). UI-only changes don't need tests, but please include a screenshot.
5. Check the app still builds in Release, since the optimiser can behave differently from Debug:
   ```bash
   xcodebuild build -project SGBusBar.xcodeproj -scheme SGBusBar -configuration Release -destination 'generic/platform=macOS'
   ```
6. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) if users will notice the change.

## Pull requests

- Describe what changed and why, and link the issue it fixes.
- Include before and after screenshots for anything visible, in light and dark mode if it matters.
- GitHub Actions runs the tests and a Release build on every pull request. It needs to pass before merging.

## Guidelines for the app

- **Readable colour.** Coloured text must reach 4.5:1 contrast. On glass, put status colours in solid capsules with white text.
- **Go easy on LTA.** Don't poll faster than every 20 seconds, LTA's own update interval, and prefer one request per stop.
- **Private by default.** No analytics or third-party services. The API key stays in the Keychain.
- **macOS 14 or later.** Wrap macOS 26-only APIs (like Liquid Glass) in `if #available(macOS 26, *)` with a fallback; see `Glass.swift`.

## Code of Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
