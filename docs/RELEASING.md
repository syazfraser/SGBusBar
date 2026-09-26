# Releasing a new version

A release is a git tag like `v0.3.0`. Pushing the tag makes GitHub Actions test and build the app, publish it on the
[Releases](https://github.com/syazfraser/SGBusBar/releases) page with notes from CHANGELOG.md, and update the Homebrew cask.

## Each release

1. **Pick the version** using [Semantic Versioning](https://semver.org): `0.2.0` → `0.2.1` for fixes only,
   `0.3.0` for new features, `1.0.0` when you consider it stable.
2. **Bump the version.** In Xcode, select the SGBusBar project, then the **SGBusBar** target > **General**,
   and set **Version** (this is `MARKETING_VERSION`). Increase **Build** by one too.
3. **Update CHANGELOG.md.** Rename `## [Unreleased]` to `## [0.3.0] - YYYY-MM-DD`, add a new empty
   `## [Unreleased]` above it, and update the links at the bottom. The app's What's New page reads this file,
   and a test checks it has an entry for the app's version.
4. **Commit and push** to `main`, and wait for CI to pass:
   ```bash
   git add -A
   git commit -m "Release 0.3.0"
   git push
   ```
5. **Tag and push the tag:**
   ```bash
   git tag v0.3.0
   git push origin v0.3.0
   ```
6. Watch **Actions > Release** on GitHub. When it finishes, the release and its zip are live, and Homebrew users get
   the update with `brew upgrade --cask sgbusbar`.

If the workflow stops at "Check the tag matches the app's version", the tag and the Version in Xcode don't agree.
Delete the tag (`git tag -d v0.3.0 && git push origin :refs/tags/v0.3.0`), fix the version, and tag again.

## One-time setup for Homebrew

The cask lives in a separate repo, **syazfraser/homebrew-tap** (the `homebrew-` prefix is what lets people type
`syazfraser/tap`). The main repo must be public, so Homebrew can download the release zip.

1. Create a public repo named `homebrew-tap` on GitHub.
2. Add `packaging/homebrew/sgbusbar.rb` to it as `Casks/sgbusbar.rb`, with the real `sha256` from the release's
   `.sha256` file.
3. So releases can update the cask for you: create a
   [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) with
   **Contents: Read and write** on `syazfraser/homebrew-tap` only, and add it to the SGBusBar repo under
   **Settings > Secrets and variables > Actions** as `HOMEBREW_TAP_TOKEN`.
4. Test it: `brew install --cask syazfraser/tap/sgbusbar`.

## How people update

| Installed with | To update |
| --- | --- |
| Homebrew | `brew upgrade --cask sgbusbar` |
| Downloaded zip | Download the new zip from Releases and replace the app |
| Source | `git pull && ./install.sh` |

## Later: signing and notarisation

Releases are currently unsigned, which is why macOS asks people to click **Open Anyway** the first time.
With an [Apple Developer Program](https://developer.apple.com/programs/) membership, the release workflow can sign
the app with a Developer ID certificate and notarise it, which removes that warning and is required for the main
Homebrew catalogue.
