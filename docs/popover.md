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

Measured with the popover open: _pending — needs a human to hold the popover open while `scripts/cpu-check.sh 120` runs._

Measured with the popover closed: `samples=60 mean_cpu=0.00% idle_wakeups_per_min=0.0 memory=12M` (2026-09-16).
