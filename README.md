<div align="center">
<h1>SlimBattery</h1>

> **A battery indicator that doesn't hog your menubar.**
>
> A native macOS menubar app that shows battery level and charging state in an 11-point-wide upright battery — with a popover for per-app energy use, Bluetooth device batteries, and battery health.

<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" /></a>
<a href="#requirements"><img src="https://img.shields.io/badge/macOS-26+-black.svg" alt="Platform: macOS 26+" /></a>
<a href="https://www.swift.org"><img src="https://img.shields.io/badge/built%20with-Swift%206-F05138.svg" alt="Built with Swift" /></a>
<a href="https://abhi.am" target="_blank"><img src="https://img.shields.io/badge/about-me-blue" alt="About Abhishek" /></a>
<a href="https://github.com/sponsors/manustays"><img src="https://img.shields.io/github/sponsors/manustays?label=Sponsor&logo=githubsponsors" alt="Support my work" /></a>

</div>

## Quick Install

> **Not released yet.** SlimBattery is in active development. Homebrew and download instructions will appear here with the first release. Until then, [build from source](#build-from-source).

## The problem

The macOS battery icon with a percentage is wide, and on a notched MacBook menubar space is scarce. Many third-party battery apps are wider still, and many poll the system constantly.

**SlimBattery** turns the battery upright: the charge level, charging plug, Low Power Mode and a high-temperature warning all fit in an 11-point-wide icon. It does no polling for battery state — it redraws only when macOS reports a change.

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

- **No special permissions.** SlimBattery reads battery data from public IOKit APIs. It does not need Accessibility, Full Disk Access, or admin rights to run.
- **Energy history (popover)** comes from macOS's own power log at `/private/var/db/powerlog/Library/BatteryLife/`. The file is readable by all users on the Mac; SlimBattery opens it **read-only** and only while the popover is open.
- **Low Power Mode toggle** asks for your admin password each time (it runs `pmset`), because macOS requires root to change it.
- **Update check (planned, optional).** When enabled, SlimBattery asks GitHub for the latest release at most once a day, and only when you open the popover. GitHub sees your IP address and the app version. It never downloads or installs anything, and turning it off in Settings means no network requests at all.
- **Stays on your machine.** Battery and energy data never leave your Mac. No telemetry, no analytics.

## Build from source

```bash
git clone https://github.com/manustays/slimbattery.git
cd slimbattery
make app                 # release build → SlimBattery.app (ad-hoc signed)
open SlimBattery.app     # run it
make install             # copy to /Applications
```

Run the tests one suite at a time:

```bash
swift test --filter BatteryStateTests
swift test --filter IconSpecTests
swift test --filter IconRendererTests
```

> **First launch of a downloaded build.** Builds are not code-signed or notarized yet, so macOS Gatekeeper may block a copy you download. Open **System Settings → Privacy & Security** and click **Open Anyway** next to the SlimBattery message. Builds you make yourself with `make app` open normally.

## Documentation

| Doc | What's in it |
|-----|--------------|
| [Menubar icon](docs/menubar-icon.md) | Icon states, how updates are triggered, data sources, settings keys, CPU footprint check |
| [Popover](docs/popover.md) | Header values and sources, Battery Information, settings, Low Power Mode prompt, CPU behavior |

## How does it work

SlimBattery is a Swift package with two targets:

- **`SlimBatteryCore`** — pure logic with unit tests: turning macOS power-source data into a `BatteryState`, deciding what the icon shows, and drawing it with Core Graphics.
- **`SlimBattery`** — a small AppKit agent app (no Dock icon) that listens for power-source, Low Power Mode and wake notifications and redraws the status item only when what you see would change.

A 60-second timer with generous tolerance re-reads battery temperature, which has no change notification. Measured idle cost on a MacBook Pro: **0.00% CPU, 0 idle wakeups per minute, ~11 MB memory** (`scripts/cpu-check.sh`).

## Known limitations

- **macOS 26+, Apple Silicon only.**
- **Macs without a battery** show "—" instead of the icon.
- **Energy history relies on a private, undocumented macOS database**; a future macOS update may change it (the popover will say so instead of breaking).
- **Low Power Mode toggle** asks for your admin password every time.
- **Not code-signed or notarized yet.**

## Roadmap

- Popover: battery header, energy by app, Bluetooth batteries, battery information, settings.
- Releases: Homebrew cask (`brew install --cask manustays/tools/slimbattery`), GitHub Releases, optional notify-only update check.

## Support

SlimBattery is an independent project I build and maintain in my spare time. The best way to support it is to use it, share feedback, and report issues.

If you'd also like to support my open-source work financially, [GitHub Sponsors](https://github.com/sponsors/manustays) is available.

## Contributing

Contributions are welcome. Open an issue to discuss first, work on a `feature/`, `bugfix/`, or `chore/` branch, use [Conventional Commits](https://www.conventionalcommits.org), and run the relevant test suites (`swift test --filter <Suite>`) before opening a pull request.

## License

[MIT](LICENSE) © 2026 [Kumar Abhishek](https://abhi.am)
