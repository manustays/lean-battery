# Contributing

Contributions are welcome. Open an issue first for anything beyond a small fix, so we agree on the
approach before you write code.

## Branches

Name your branch by what it does:

- `feature/...` — new behavior
- `bugfix/...` — a fix
- `chore/...` — everything else (docs, tooling, refactors with no behavior change)

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org). The type is not just style — it
drives what `semantic-release` publishes on every push to `main` (see [docs/release.md](docs/release.md)
for the full mapping):

- `fix:` / `perf:` → a patch release
- `feat:` → a minor release
- A `BREAKING CHANGE:` footer, or `type!:` → a major release
- `docs:`, `style:`, `refactor:`, `test:`, `build:`, `ci:`, `chore:` → no release at all

A commit with the wrong type either publishes something that shouldn't ship yet, or silently doesn't
publish a change users are waiting on.

## Before opening a PR

Run the tests. Prefer a targeted suite over the full run while you iterate:

```bash
swift test --filter <Suite>
```

Run the full suite (159 tests, 17 suites) before you open the PR — CI's `prepareCmd` runs `swift
test` unfiltered, so a suite you didn't touch can still fail there:

```bash
swift test
```

If your change touches any UI that's on screen while idle, or that runs on a timer — the menubar
icon, the popover, or a notification — measure it against the CPU bar in [spec §10](README.md#efficiency-measured)
before you open the PR, not after review flags it:

```bash
scripts/cpu-check.sh 60
```

The budgets already measured and documented are the ones to stay under: **0.00% CPU / 0 idle
wakeups** with the popover closed, and roughly **1% mean CPU** with it open (`docs/popover.md`), or
**under 2% mean CPU** while a notification is on screen (`docs/notifications.md`). Wrap any run you
can't babysit in `caffeinate -di` — a sample long enough to matter is also long enough for the
display to sleep, and a wake mid-sample will make your numbers look worse than your change actually
is.

## Code style

- **Tabs**, not spaces, for indentation.
- Favor pure, testable logic in `LeanBatteryCore`; keep `LeanBattery` (the AppKit/SwiftUI target) thin
  — glue, not decisions.

## Documentation

`docs/` is one topic per file. If you add or materially change a feature, add or update its doc in
the same PR — a feature without a doc entry is only half done. Look at `docs/popover.md` or
`docs/notifications.md` for the level of detail and honesty about limitations we're going for: what
it does, where the data comes from, what's persisted and under what key, and the measured CPU cost
if it's the kind of feature that could have one.
