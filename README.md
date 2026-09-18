<div align="center">
<h1>LeanBattery</h1>

> **A battery indicator that doesn't hog your menubar.**
>
> A native macOS menubar app that shows battery level and charging state in an 11-point-wide upright battery — with a popover for per-app energy use, Bluetooth device batteries, and battery health.
>
> **0.00% CPU and 0 idle wakeups** while it sits in your menubar. Measured, not claimed — [see the numbers](#efficiency-measured).

<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" /></a>
<a href="#requirements"><img src="https://img.shields.io/badge/macOS-26+-black.svg" alt="Platform: macOS 26+" /></a>
<a href="https://www.swift.org"><img src="https://img.shields.io/badge/built%20with-Swift%206-F05138.svg" alt="Built with Swift" /></a>
<a href="https://abhi.am" target="_blank"><img src="https://img.shields.io/badge/about-me-blue" alt="About Abhishek" /></a>
<a href="https://github.com/sponsors/manustays"><img src="https://img.shields.io/github/sponsors/manustays?label=Sponsor&logo=githubsponsors" alt="Support my work" /></a>

</div>

## Quick Install

> **Not released yet.** LeanBattery is in active development. Homebrew and download instructions will appear here with the first release. Until then, [build from source](#build-from-source).

## The problem

The macOS battery icon with a percentage is wide, and on a notched MacBook menubar space is scarce. Many third-party battery apps are wider still, and many poll the system constantly.

**LeanBattery** turns the battery upright: the charge level, charging plug, Low Power Mode and a high-temperature warning all fit in an 11-point-wide icon. It does no polling for battery state — it redraws only when macOS reports a change.

## Efficiency, measured

A battery app that costs you battery is a bad joke. LeanBattery is built to do **nothing at all** until macOS tells it something changed, and the numbers below are from the real app on a real Mac, not estimates.

| What you're doing | CPU | Idle wakeups | Memory |
|---|---|---|---|
| **Menubar only** — the 99% case | **0.00%** | **0 / min** | **14 MB** |
| Notification on screen (pill + glow) | 0.01% | 0 / min | — ¹ |
| Popover open, `Now` range | 0.81% | — | ~38 MB |
| Popover open, `7d` range — the heaviest thing it does | 0.91% | 1.0 / min | 44 MB |

¹ Memory during a notification reads ~44 MB, but that is the popover's working set — you have to open the popover to reach the preview button. It is released a couple of minutes after the popover closes.

**Why it's idle:**

- **No polling for battery state.** The icon redraws when macOS posts a power-source, Low Power Mode or wake notification, and not otherwise. A state that looks identical to the one on screen redraws nothing.
- **One lax timer, for temperature only** — 60 s with 30 s tolerance, because battery temperature is the one value macOS has no notification for. The tolerance lets macOS coalesce it with other wakeups instead of waking the CPU on its own.
- **The popover's timers exist only while it is open.** Close it and they are invalidated. Energy history is read on a background actor, never on the main thread, and each section redraws only when its values actually change.
- **Notifications cost nothing between events.** No timer, no window, no polling. The pill and glow are created when something fires and destroyed on dismissal, and the glow's pulse is a Core Animation the window server renders — the app does no per-frame work for it.
- **Energy data is read, not collected.** LeanBattery opens macOS's own power log read-only, only while the popover is open. It stores no history of its own.

**Measured with** [`scripts/cpu-check.sh`](scripts/cpu-check.sh), which samples once a second via `top` and reports the mean, on an M3 Pro MacBook Pro running macOS 27. Reproduce it yourself:

```bash
scripts/cpu-check.sh 60                      # 60 one-second samples
(sleep 25; caffeinate -di scripts/cpu-check.sh 120)   # for runs you must not touch
```

Wrap any long run in `caffeinate -di` — a sample that needs two untouched minutes is exactly long enough for the display to sleep, and waking it lands real work inside your measurement.

Numbers are one machine and one configuration; yours will differ. The full method and the per-feature breakdowns are in [docs/popover.md](docs/popover.md) and [docs/notifications.md](docs/notifications.md).

## Features

**In the menubar (available now)**

- **Upright battery icon, 11 pt wide** with the charge % inside.
- **Charging at a glance** — a plug replaces the number while on power; green fill while charging.
- **Low Power Mode** shown as a yellow fill; **low battery** (≤ 20%) as red.
- **High-temperature badge** — a red dot when the battery reaches your threshold (default 40 °C).
- **Follows your menubar** — white on dark menubars, black on light ones.

**In the popover (available now)**

- **Apps using significant energy** with a `Now / 8h / 24h / 7d` range switch.
- Battery header: %, time left, power source and adapter wattage, live system power draw, temperature, and a Low Power Mode switch.
- Collapsible **battery information**: health, condition, cycle count, capacity, voltage, adapter.
- Settings: high-temperature threshold and launch at login.

**Notifications (available now)**

- One low-battery rule on by default; up to 5 battery threshold rules in total. Power connected/disconnected alerts are off by default.
- A floating pill below the notch, and a screen-edge glow for low battery.

**Coming next**

- **Bluetooth device batteries** (headphones, mice, keyboards, controllers).

## Requirements

- **macOS 26** or later.
- **Apple Silicon** Mac with a battery (a MacBook).
- To build from source: Xcode 26 command line tools (Swift 6.2+).

## Permissions & Privacy

- **No special permissions.** LeanBattery reads battery data from public IOKit APIs. It does not need Accessibility, Full Disk Access, or admin rights to run.
- **Energy history (popover)** comes from macOS's own power log at `/private/var/db/powerlog/Library/BatteryLife/`. The file is readable by all users on the Mac; LeanBattery opens it **read-only** and only while the popover is open.
- **Low Power Mode toggle** asks for your admin password each time (it runs `pmset`), because macOS requires root to change it.
- **Update check (planned, optional).** When enabled, LeanBattery asks GitHub for the latest release at most once a day, and only when you open the popover. GitHub sees your IP address and the app version. It never downloads or installs anything, and turning it off in Settings means no network requests at all.
- **Stays on your machine.** Battery and energy data never leave your Mac. No telemetry, no analytics.

## Build from source

```bash
git clone https://github.com/manustays/lean-battery.git
cd lean-battery
make app                 # release build → LeanBattery.app (ad-hoc signed)
open LeanBattery.app     # run it
make install             # copy to /Applications
```

Run the tests one suite at a time:

```bash
swift test --filter BatteryStateTests
swift test --filter IconSpecTests
swift test --filter IconRendererTests
```

> **First launch of a downloaded build.** Builds are not code-signed or notarized yet, so macOS Gatekeeper may block a copy you download. Open **System Settings → Privacy & Security** and click **Open Anyway** next to the LeanBattery message. Builds you make yourself with `make app` open normally.

## Documentation

| Doc | What's in it |
|-----|--------------|
| [Menubar icon](docs/menubar-icon.md) | Icon states, how updates are triggered, data sources, settings keys, CPU footprint check |
| [Popover](docs/popover.md) | Header values and sources, Battery Information, settings, Low Power Mode prompt, CPU behavior |
| [Notifications](docs/notifications.md) | Rules and firing semantics, the pill and its four styles, the screen-edge glow, storage, CPU behavior |

## How does it work

LeanBattery is a Swift package with two targets:

- **`LeanBatteryCore`** — pure logic with unit tests: turning macOS power-source data into a `BatteryState`, deciding what the icon shows, and drawing it with Core Graphics.
- **`LeanBattery`** — a small AppKit agent app (no Dock icon) that listens for power-source, Low Power Mode and wake notifications and redraws the status item only when what you see would change.

A 60-second timer with generous tolerance re-reads battery temperature, which has no change notification. Measured idle cost: **0.00% CPU, 0 idle wakeups per minute, 14 MB memory** — see [Efficiency, measured](#efficiency-measured).

## Known limitations

- **macOS 26+, Apple Silicon only.**
- **Macs without a battery** show "—" instead of the icon.
- **Energy history relies on a private, undocumented macOS database**; a future macOS update may change it (the popover will say so instead of breaking).
- **Low Power Mode toggle** asks for your admin password every time.
- **Not code-signed or notarized yet.**

## Roadmap

- Popover: battery header, energy by app, Bluetooth batteries, battery information, settings.
- Releases: Homebrew cask (`brew install --cask manustays/tools/leanbattery`), GitHub Releases, optional notify-only update check.

## Support

LeanBattery is an independent project I build and maintain in my spare time. The best way to support it is to use it, share feedback, and report issues.

If you'd also like to support my open-source work financially, [GitHub Sponsors](https://github.com/sponsors/manustays) is available.

## Contributing

Contributions are welcome. Open an issue to discuss first, work on a `feature/`, `bugfix/`, or `chore/` branch, use [Conventional Commits](https://www.conventionalcommits.org), and run the relevant test suites (`swift test --filter <Suite>`) before opening a pull request.

## License

[MIT](LICENSE) © 2026 [Kumar Abhishek](https://abhi.am)
