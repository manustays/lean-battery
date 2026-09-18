# Updates

LeanBattery can tell you a newer release exists. That's all it does: **notify-only**. It never
downloads, never installs, and never touches your `Applications` folder. Getting the new version is
always something you do yourself — via `brew upgrade` or a manual download.

## What happens on the wire

One `GET` to GitHub's REST API, nothing else:

```
GET https://api.github.com/repos/manustays/lean-battery/releases/latest
User-Agent: LeanBattery/<installed version>
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
If-None-Match: <etag>          # only once a previous check has one
```

No authentication, no identifiers beyond the version number embedded in the User-Agent, no request
body. `If-None-Match` is sent once GitHub has returned an `ETag` from a prior check, so an unchanged
latest release costs GitHub (and you) a `304 Not Modified` instead of a full response.

## When a check runs

Two triggers only, both in [`UpdateService.check(manual:)`](../Sources/LeanBattery/UpdateService.swift):

- **Opening the popover** calls `check(manual: false)` every time (`PopoverModel.start()`), but the
  policy in [`UpdatePolicy.shouldCheck`](../Sources/LeanBatteryCore/UpdatePolicy.swift) drops it unless
  the last attempt was at least **24 hours** ago (or there has never been one).
- **Pressing "Check now"** in Settings calls `check(manual: true)`, which skips the 24 h cooldown.

Either way, an **active rate limit** blocks the check outright, and a check already in flight blocks a
second one from starting.

## What you see

The popover shows an update row only when a newer version is actually on offer:

> `Update available: v<version>`  — **Download** / **Homebrew** / ✕

The settings block always shows one line, driven by `UpdateStatus`:

| `UpdateStatus` | Text shown |
|---|---|
| `.disabled` | `Version <installed version>` |
| `.idle` | `Checks once a day when you open this popover.` |
| `.checking` | `Checking…` |
| `.current(version)` | `Up to date (v<version>)` |
| `.available(version, _)` | `Version <version> is available.` |
| `.noReleases` | `No releases yet` |
| `.failed(reason)` | `Couldn't check — <reason>` |

In practice `<reason>` only ever renders as one of two literal strings, because `UpdatePolicy.status`
recomputes the status from **persisted state**, not from the outcome of the request that just ran:

- `"rate limited"` — while `state.rateLimitReset` is still in the future.
- `"couldn't reach GitHub"` — a failed attempt with no successful check ever recorded.

The finer-grained reasons a request can fail with internally (`"bad endpoint"`, `"no response"`,
`"unreadable response"`, `"GitHub returned <code>"`, `"cancelled"`, or the system error's own
description) are used only to decide *that* the attempt failed; `UpdateOutcome.failed`'s own
`reason` string is discarded once folded into state, and the app never displays it. If you've had
even one successful check before, a later failed one leaves the last good result on screen instead
of reporting anything went wrong — `UpdatePolicy.apply` doesn't touch `lastSuccess`, `cachedTag`, or
`cachedURL` on failure.

**A rate limit stops being reported the moment it expires**, without a new network request.
`UpdatePolicy.status(state:enabled:currentVersion:now:)` takes `now` as a parameter rather than reading
the clock itself, and the popover re-derives status from the same stored state on every open — so
once real time passes `state.rateLimitReset`, the very next status computation (no request needed)
falls through to the cached result instead of `.failed(reason: "rate limited")`.

## What's persisted

Eight `UserDefaults` keys, all defined in [`AppDelegate.DefaultsKey`](../Sources/LeanBattery/AppDelegate.swift):

| Key | Holds | Notes |
|---|---|---|
| `updateCheckEnabled` | Bool | Default **on** (registered `true` at launch) |
| `updateLastAttempt` | Double (unix seconds) | Stamped on every attempt, success or failure |
| `updateLastSuccess` | Double (unix seconds) | Stamped on `ok` and `notModified`, never on failure |
| `updateRateLimitReset` | Double (unix seconds) | Set from `Retry-After` or `X-RateLimit-Reset`; cleared on the next `ok` or `notModified` |
| `updateETag` | String | The last response's `ETag`, sent back as `If-None-Match` |
| `updateCachedTag` | String | The latest release tag GitHub returned |
| `updateCachedURL` | String | The latest release's HTML page URL |
| `updateDismissedVersion` | String | The version you clicked ✕ on; cleared automatically once a newer one is offered |

## The URL prefix guard

Two independent checks make sure LeanBattery only ever offers or opens a URL that is actually a
release of this project, never wherever a GitHub response happened to point:

- `UpdatePolicy.status` only turns a cached tag into `.available` when
  `UpdatePolicy.releaseURL(cachedURL)` returns non-nil — i.e. the URL starts with
  `https://github.com/manustays/lean-battery/releases/`.
- `UpdateService.openDownloadPage()` re-validates the same prefix immediately before calling
  `NSWorkspace.shared.open`, even though the status it's reading should already be validated.

Anything else — a redirect, a compromised response, a malformed field — is silently dropped instead
of offered or opened.

## Turning it off

The Settings switch is a hard opt-out, not a "pause": with it off, **no network access happens at
all**. Flipping it cancels any request already in flight (`task?.cancel()`), and a result that lands
after the switch was turned off is discarded rather than applied (`guard !Task.isCancelled, isEnabled
else { return }`). `check(manual:)` itself also refuses to start a new request while disabled.

## The gap

A user who never opens the popover never learns about an update. There is no background timer and no
launch-time check — the popover opening is the only automatic trigger, and it only opens when you
click the menubar icon. That's the deliberate trade-off behind zero idle work: LeanBattery does not
wake itself up, or your Mac, just to ask GitHub a question you haven't asked it to ask.

## Idle cost

Measured 2026-09-18 with the popover closed and the update-check switch **on**:
`samples=120 mean_cpu=0.04% idle_wakeups_per_min=0.0 memory=14M`
(`caffeinate -di scripts/cpu-check.sh 120`; see `docs/popover.md`'s CPU behavior section for the
full note). Update checking itself adds no idle cost — `check()` only ever runs from a popover open
or "Check now", and neither fired during this measurement. The 0.04% (idle wakeups and memory are
still exactly at the bar) traces to `BatteryMonitor`'s unrelated 60 s temperature-poll timer, which
predates this feature and runs regardless of the update switch.
