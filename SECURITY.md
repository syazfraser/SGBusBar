# Security

## Supported versions

Security fixes go into the latest release. Please update to it before reporting a problem.

## Reporting a vulnerability

Please report security problems privately, not in a public issue:
go to the repo's **Security** tab and choose **Report a vulnerability**.

Include what you found, how to reproduce it, and which version you tested. You'll get a reply within a week.

## How SGBusBar handles your data

- Your LTA DataMall API key is stored in the macOS Keychain and sent only to LTA DataMall (`datamall2.mytransport.sg`) over HTTPS.
- Your buses and settings are stored locally in the app's preferences. Stop and route lists are cached in `~/Library/Application Support/SGBusBar`.
- The app has no analytics, tracking or accounts, and talks to no other servers.
