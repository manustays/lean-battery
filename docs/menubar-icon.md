# Menubar Icon

SlimBattery's menubar item is an upright battery, 11 × 22 pt, drawn in code (no image assets).

## States

| State | Inside the battery | Fill |
|---|---|---|
| On battery | charge % (7.8pt bold; 5.6pt at 100) | white/black per menubar, red at ≤ 20% |
| Charging | plug | green `#30D158` |
| Plugged in, not charging | plug | white/black per menubar |
| Low Power Mode | % (plug if plugged in) | yellow `#FFD60A` (wins over other colors) |
| Temperature ≥ threshold | unchanged | unchanged + red dot top-right |

Where the % or plug overlaps a white/black fill it is cut out to transparent, so the menubar shows through; over a colored fill it is drawn black.

## How it updates

`BatteryMonitor` does no polling for charge state. It rebuilds `BatteryState` only when:

- IOPS posts a power source change (`IOPSNotificationCreateRunLoopSource`),
- Low Power Mode changes (`NSProcessInfoPowerStateDidChange`),
- the Mac wakes (`NSWorkspace.didWakeNotification`),
- a 60 s timer (30 s tolerance) fires to re-read battery temperature, which has no change notification.

`StatusIcon` redraws only when the derived `IconSpec` or the menubar's light/dark appearance changes, so time-remaining changes never trigger drawing.

## Data sources

| Value | Source |
|---|---|
| %, charging, plugged in, time remaining | `IOPSCopyPowerSourcesInfo` → internal battery (`Current Capacity`, `Max Capacity`, `Is Charging`, `Power Source State`, `Time to Empty`, `Time to Full Charge`) |
| Low Power Mode | `ProcessInfo.isLowPowerModeEnabled` |
| Temperature | IORegistry `AppleSmartBattery` → `Temperature` (hundredths of °C) |

## Settings

| Key (`com.manustays.slimbattery`) | Default | Meaning |
|---|---|---|
| `tempThresholdC` | 40 | Hot badge threshold in °C (UI arrives with the popover) |

## Build & run

```sh
make app                # release build → SlimBattery.app, ad-hoc signed
open SlimBattery.app
make install            # copy to /Applications
swift test --filter IconRendererTests   # run one test suite
```

## CPU footprint

`scripts/cpu-check.sh [samples]` samples the running app once per second.

Measured: `samples=570 mean_cpu=0.00% idle_wakeups_per_min=0.0 memory=11M` (2026-09-15, popover not yet implemented).
