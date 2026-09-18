# Releases

Every push to `main` runs [`.github/workflows/release.yml`](../.github/workflows/release.yml), which
hands the whole decision — whether to release, what version, what changelog — to
[`semantic-release`](https://semantic-release.gitbook.io/), configured in
[`.releaserc.json`](../.releaserc.json). Nothing about a release is typed in by hand.

## What decides the version

`@semantic-release/commit-analyzer` reads every commit since the last release and picks the highest
bump any of them calls for, using the default **Angular** convention (no override in
`.releaserc.json`):

| Commit | Bump |
|---|---|
| `feat: ...` | minor |
| `fix: ...` / `perf: ...` | patch |
| Any type with a `BREAKING CHANGE:` footer, or `type!:` | major |
| `docs`, `style`, `refactor`, `test`, `build`, `ci`, `chore`, ... | no release |

If every commit since the last release falls in that last row, semantic-release does nothing —
no tag, no bump, no CI failure. `CONTRIBUTING.md` has the branch-prefix side of this.

## What `prepareCmd` runs, in order

`.releaserc.json`'s `@semantic-release/exec` plugin chains four commands with `&&`, so any failure
stops the release before anything is published:

1. **`scripts/set-version.sh ${nextRelease.version}`** — stamps `CFBundleShortVersionString` and
   `CFBundleVersion` in `Resources/Info.plist` to the version semantic-release computed.
2. **`swift test`** — the full 159-test, 17-suite run. A red test blocks the release outright.
3. **`make zip`** — builds the arm64 release binary, assembles `LeanBattery.app`, ad-hoc signs it,
   and zips it to `dist/LeanBattery-<version>.zip`.
4. **`scripts/verify-release.sh <version>`** — the last gate before semantic-release is allowed to
   publish anything (see below).

Only after all four succeed do `@semantic-release/github` (uploads the zip as a release asset) and
`@semantic-release/git` (commits `CHANGELOG.md` and the stamped `Info.plist` back to `main`, tagged
`[skip ci]`) run.

## Every check `scripts/verify-release.sh` makes

Each check exists to catch one specific way a release could ship broken without anyone noticing until
a user's `brew install` fails or opens the wrong app:

| Check | Catches |
|---|---|
| `LeanBattery.app` exists | `make zip`'s build step silently failed |
| `Info.plist`'s `CFBundleShortVersionString` equals the release version | `set-version.sh` didn't run, or ran against a different version than what's being published |
| `CFBundleIdentifier` is `am.abhi.leanbattery` | A stray build config shipping under the wrong bundle id — breaks the cask's `uninstall launchctl:` and `zap` stanzas, which are hard-coded to this id |
| `LSMinimumSystemVersion` is `26.0` | The minimum-OS requirement drifting away from what the cask's `depends_on macos:` promises |
| `lipo -archs` reports exactly `arm64` | An accidental universal or x86_64 slice reaching a cask that only declares `depends_on arch: :arm64` |
| `codesign --verify --deep --strict` | A corrupt or missing ad-hoc signature — the first-launch approval flow in the README (System Settings → Privacy & Security → Open Anyway) assumes the signature is at least structurally valid, even though it isn't notarized |
| `dist/LeanBattery-<version>.zip` exists and is non-empty | `make zip` didn't actually write the artifact |
| The zip is a valid archive (`unzip -l`) | A truncated or corrupted zip |
| The zip's root entry is exactly `LeanBattery.app` | The cask's `app "LeanBattery.app"` stanza expects the app at the zip's top level, not nested in a folder or alongside stray files |
| The sha256 is 64 hex characters | A malformed or empty hash reaching the release notes / cask before anyone downloads the asset |

Any single failure exits non-zero, which fails `prepareCmd`, which stops semantic-release before it
tags, publishes, or commits anything.

## A broken release is never replaced

If a published release turns out to be broken — wrong binary, a check that should have caught
something but didn't — the fix is a new patch release (a `fix:` commit on `main`), not editing or
deleting the existing GitHub release or its asset. Once a tag and its asset are public, they stay
public exactly as published; superseding forward is the only path. This matters for the Homebrew tap
too: `livecheck` and the bump workflow (below) always track the *latest* release, so a superseding
patch release is what actually reaches users, not a rewritten old one.

## Publishing the cask to the tap

This repository never pushes to the tap — that's always a manual, separate step, and it can only
happen after a real release exists (so there's a real sha256 to give the cask). `dist/homebrew/`
holds the two files the tap needs; copy and push them from a clone of `manustays/homebrew-tools`:

```bash
# in your clone of manustays/homebrew-tools
cp ~/DEV/abhi_github/menubar-battery-indicator/dist/homebrew/Casks/leanbattery.rb Casks/
cp ~/DEV/abhi_github/menubar-battery-indicator/dist/homebrew/workflows/bump-leanbattery-cask.yml .github/workflows/
brew audit --cask --new Casks/leanbattery.rb
brew install --cask ./Casks/leanbattery.rb
git add Casks/leanbattery.rb .github/workflows/bump-leanbattery-cask.yml
git commit -m "feat: add LeanBattery cask"
git push
```

**Before that first push**, replace the cask's placeholder —
`sha256 "REPLACE_WITH_SHA256_OF_PUBLISHED_ZIP"` — with the sha256 of the *published* release asset
(the `sha256=...` line `scripts/verify-release.sh` prints, or `shasum -a 256` on the zip you
downloaded from the GitHub release page). Don't reuse a sha256 from a local build: CI builds its own
zip for the release, and a locally-built one won't match byte-for-byte even from identical source, so
a locally-computed hash would make `brew install` fail its own checksum. After that first manual fill,
the bump workflow (`bump-leanbattery-cask.yml`, scheduled daily plus `workflow_dispatch`) overwrites
both `version` and `sha256` on its own from then on, so this is a one-time step.

Once pushed, `brew install --cask manustays/tools/leanbattery` must install the app from anywhere.

## Manual fallback, when CI is unavailable

The same steps `prepareCmd` runs, done by hand, produce an identical artifact:

```bash
scripts/set-version.sh <version>
swift test
make verify                      # = make zip + scripts/verify-release.sh <version>
gh release create v<version> dist/LeanBattery-<version>.zip \
  --title "v<version>" --notes "<release notes>"
```

`make verify` is the Makefile target that chains `make zip` and `scripts/verify-release.sh`, so a
release built this way passes the identical gate CI does. `gh release create` is the one step CI's
`@semantic-release/github` plugin normally does for you — it still needs a git tag (`git tag
v<version> && git push --tags`) and, for the changelog, a manual update to `CHANGELOG.md` if you want
one to match what semantic-release would otherwise have generated.
