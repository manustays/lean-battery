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

- **The window is anchored to the log, not the clock.** Powerlog timestamps do not sit on the wall clock, and the difference is not stable enough to correct for. LeanBattery instead measures back from the newest logged moment, which is correct whatever the log's clock is doing. If the log has not been written for more than 15 minutes, the range reads as empty rather than showing stale numbers.
- **Long activities are counted proportionally.** The log records intervals averaging about 10 minutes — longer than the `Now` window itself. Only the part of each interval falling inside the window is counted, so `Now` is a true 5-minute measure.

`7d` also reads the daily archives: each is decompressed to a temporary file, queried, and deleted. Archives that fall entirely inside the range have their totals cached while the popover stays open, so they are not read again. The one archive straddling the start of the range depends on exactly where the range begins, so its contribution is cached against those precise bounds and reused until they move — and they move only when macOS writes to the log, not on every refresh. In practice most refreshes read nothing but the live log.

### Battery Information
Collapsed by default; LeanBattery remembers whether you left it open. Values are read only while the popover is open **and** this section is expanded.

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
| Notifications › | — | See [Notifications](notifications.md) |

Launch at login registers LeanBattery as a login item only when you change the switch. If macOS needs approval, the row says so (System Settings → General → Login Items). If registration is rejected (for example for an unsigned build), LeanBattery writes a LaunchAgent at `~/Library/LaunchAgents/<bundle id>.plist` instead and removes it when you turn the switch off.

## CPU behavior

- While the popover is **closed**, nothing here runs.
- While it is **open**, values refresh every 5 s (1 s tolerance) and immediately on any battery change. The timer stops when the popover closes.
- Energy is read on a background actor, never on the main thread. Each refresh opens the live log **once**: about 12 ms of SQLite work on `Now` and 21 ms on `7d`. The `7d` path costs roughly a second on its first run while it decompresses the archives; afterwards it usually re-reads nothing but the live log.
- The section is redrawn only when its values actually change, so a refresh that finds the same apps in the same order costs nothing on screen.

Measured with the popover open on `7d`, the most expensive range: `samples=120 mean_cpu=0.91% idle_wakeups_per_min=1.0 memory=44M` (2026-09-17). On `Now` an earlier build measured `mean_cpu=0.81%`; the optimisations since can only have lowered it, so treat that as an upper bound.

Both are inside the 1% budget, but `7d` clears it by only 0.09 points. Anything added to the 5-second refresh path should be re-measured rather than assumed free. Profile before optimising: SQLite is only about 55–60% of the per-tick cost, and the first attempt to speed this up targeted the wrong half.

Measured with the popover closed: `samples=60 mean_cpu=0.00% idle_wakeups_per_min=0.0 memory=14M` (2026-09-17). Working memory rises while the popover is open — around 44M on `7d` — and is released again a couple of minutes after it closes.

Re-measured with the popover closed and **update checking on** (Task 8 §10 re-run, spec §13.4): `samples=120 mean_cpu=0.04% idle_wakeups_per_min=0.0 memory=14M` (2026-09-18, `caffeinate -di scripts/cpu-check.sh 120`). Idle wakeups and memory are unchanged from the bar; mean CPU reads 0.04%, not 0.00%. The cause isn't update checking — `UpdateService` only runs from a popover open or the manual "Check now" button, neither of which happened here — it's `BatteryMonitor`'s pre-existing 60 s temperature-poll `Timer` (`Sources/LeanBattery/BatteryMonitor.swift:39`, 30 s tolerance), which runs for the app's lifetime independent of the popover. The earlier 0.00% reading used a 60-sample (1-minute) window, giving that timer at most one chance to fire inside the sample; this 120-sample (2-minute) window gave it two, and the resulting `refresh()` calls (an IOKit power-source read plus an SMC temperature read) are what shows up as 0.04% mean CPU. Recorded as measured, not rounded down.
