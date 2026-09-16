# Popover

Click the menubar icon to open a 320 pt popover. Click outside it (or the icon again) to close.

## Sections

### Battery header
- Large charge %, with a status line: `On Battery · 4h 05m left`, `Charging · 0h 42m to full`, `Plugged In · Not Charging`, or `Calculating…`.
- **Source**: `Battery`, `Adapter · 96 W`, or `Adapter` when macOS doesn't report the wattage.
- **Draw**: whole-system power draw in watts (`AppleSmartBattery` → `PowerTelemetryData.SystemLoad`, milliwatts).
- **Temp**: battery temperature; red at or above the hot threshold.
- Charge bar in the icon's fill color (yellow in Low Power Mode, green while charging, red at ≤ 20%).
- **Low Power Mode** switch with the current mode (`Low Power` / `Automatic`). Turning it on or off asks for your admin password every time, because macOS only lets root run `pmset -a lowpowermode`. Cancel the prompt and nothing changes; the switch always shows the real mode.

### Energy

Apps using significant energy over `Now` (5 min), `8h`, `24h` or `7d`. The popover always opens on `Now`; the choice is not remembered.

- Up to 5 rows: app icon, name, a bar, and the share of total energy in that range.
- Bar color: orange at 40% or more, yellow at 15% or more, otherwise gray.
- Apps always qualify for a row; background daemons appear only when they rank in the overall top 5 — which they often do (`WindowServer` and menubar tools are genuinely among the largest consumers). Rows under 1% are dropped.
- If less history exists than the range asks for, the segment shows the real span instead (e.g. `6d`). macOS keeps about a week of archives and rotates them daily.

**Where the numbers come from.** macOS's own power log at `/private/var/db/powerlog/Library/BatteryLife/`, opened read-only. It is world-readable, so no special permission is needed. Energy is `energy + gpu_energy_nj + ane_energy_nj` per app.

Two details matter for accuracy:

- **The window is anchored to the log, not the clock.** Powerlog timestamps do not sit on the wall clock, and the difference is not stable enough to correct for. SlimBattery instead measures back from the newest logged moment, which is correct whatever the log's clock is doing. If the log has not been written for more than 15 minutes, the range reads as empty rather than showing stale numbers.
- **Long activities are counted proportionally.** The log records intervals averaging about 10 minutes — longer than the `Now` window itself. Only the part of each interval falling inside the window is counted, so `Now` is a true 5-minute measure.

`7d` also reads the daily archives: each is decompressed to a temporary file, queried, and deleted. Archives that fall entirely inside the range have their totals cached while the popover stays open, so they are not read again. The one archive straddling the start of the range is still re-read on each refresh, because how much of it counts depends on exactly where the range begins.

### Battery Information
Collapsed by default; SlimBattery remembers whether you left it open. Values are read only while the popover is open **and** this section is expanded.

| Row | Source |
|---|---|
| Health | `AppleRawMaxCapacity / DesignCapacity` |
| Condition | IOPS battery health (e.g. `Good`, `Check Battery`) |
| Cycle count | `CycleCount` |
| Capacity | `AppleRawMaxCapacity / DesignCapacity` in mAh |
| Voltage | `Voltage` (mV → V) |
| Adapter | `AdapterDetails.Watts`, or `—` on battery |

### Settings
Opened from the footer; replaces the popover content until you press **‹ Back** or close the popover.

| Setting | Default | Stored in |
|---|---|---|
| High temp alert at (30–60 °C) | 40 °C | `tempThresholdC` (UserDefaults) |
| Launch at login | Off | macOS Login Items (`SMAppService`) |

Launch at login registers SlimBattery as a login item only when you change the switch. If macOS needs approval, the row says so (System Settings → General → Login Items). If registration is rejected (for example for an unsigned build), SlimBattery writes a LaunchAgent at `~/Library/LaunchAgents/<bundle id>.plist` instead and removes it when you turn the switch off.

## CPU behavior

- While the popover is **closed**, nothing here runs.
- While it is **open**, values refresh every 5 s (1 s tolerance) and immediately on any battery change. The timer stops when the popover closes.
- Energy is read on a background actor, never on the main thread: one query costs roughly 30–70 ms, and the `7d` path about a second on its first run — after that, roughly one archive decompression (~70 ms) per refresh, plus the live-log query.

Measured with the popover open: _pending — needs a human to hold the popover open while `scripts/cpu-check.sh 120` runs._

Measured with the popover closed: `samples=60 mean_cpu=0.00% idle_wakeups_per_min=0.0 memory=12M` (2026-09-16).
