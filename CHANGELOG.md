# Changelog

All notable changes to SGBusBar are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow
[Semantic Versioning](https://semver.org/). The app shows this file under Settings > About > What's New.

## [Unreleased]

## [0.2.1] - 2026-09-28

### Fixed
- After starting up or waking your Mac before Wi-Fi has connected, times now load as soon as the connection is back. Before, the popup could say Offline for several minutes until you clicked Refresh.

### Changed
- The popup says when there's no internet connection, and when LTA can't be reached, instead of "Getting bus times…".

## [0.2.0] - 2026-09-26

The first public release.

### Added
- The menu bar shows your chosen bus with none, 1, 2 or 3 arrival times, coloured by how soon you need to leave.
- A popup with a large card for your menu bar bus and a card for each stop, listing the next 3 arrivals for every bus with that bus's own type and crowding.
- An Add Bus wizard: find a stop by name, road or code, or find your bus and pick the stop from its route. Every service at a stop is listed, running now or not, so there's nothing to type.
- Edit Stop: use LTA's stop name or your own nickname, set one walk time for the stop, and add or remove its buses.
- Settings with General, Appearance, Menu Bar, Buses and About pages, including this What's New list.
- Light, Dark or System theme, with a Frosted or Clear glass popup.
- Launch at login.
- LTA's recommended messages when a bus has no times: "No estimate available" and "Not in operation".

### Changed
- Checking for new times follows the LTA DataMall guide: never faster than every 20 seconds, stops with nothing scheduled are skipped, a single service is requested where possible, and retries back off when LTA can't be reached.

### Fixed
- The Release build no longer crashes on launch.

## [0.1.0] - 2026-09-26

- First working version for personal use: one bus in the menu bar with colour-coded times.

[Unreleased]: https://github.com/syazfraser/SGBusBar/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/syazfraser/SGBusBar/releases/tag/v0.2.1
[0.2.0]: https://github.com/syazfraser/SGBusBar/releases/tag/v0.2.0
