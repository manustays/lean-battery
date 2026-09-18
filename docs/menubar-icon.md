# Menubar Icon

LeanBattery's menubar item is an upright battery, 11 × 22 pt, drawn in code (no image assets).

## States

| State | Inside the battery | Fill |
|---|---|---|
| On battery | charge % (9pt SF semibold compressed; 6.6pt at 100) | white/black per menubar at 28% opacity, red at ≤ 20% |
| Charging | plug | green `#30D158` at 60% opacity |
| Plugged in, not charging | plug | white/black per menubar at 28% opacity |
| Low Power Mode | % (plug if plugged in) | yellow `#FFD60A` at 60% opacity (wins over other colors) |
| Temperature ≥ threshold | unchanged | unchanged + red dot top-right |
| No battery data (desktop Mac, or before macOS reports power at login) | "—" text instead of the battery | — |

The fill is translucent and the % or plug is always drawn in one solid color (white on a dark menubar, black on a light one) on top of it, so digits stay whole and readable at any charge level. Digits use SF compressed so two digits fit the 8.3pt interior without touching the frame.

## How it updates

`BatteryMonitor` does no polling for charge state. It rebuilds `BatteryState` only when:

- IOPS posts a power source change (`IOPSNotificationCreateRunLoopSource`),
- Low Power Mode changes (`NSProcessInfoPowerStateDidChange`),
- the Mac wakes (`NSWorkspace.didWakeNotification`),
- a 60 s timer (30 s tolerance) fires to re-read battery temperature, which has no change notification.

`StatusIcon` redraws only when the derived `IconSpec` or the menubar's light/dark appearance changes, so time-remaining changes never trigger drawing.

Clicking the icon opens the [popover](popover.md).

## Data sources

| Value | Source |
|---|---|
| %, charging, plugged in, time remaining | `IOPSCopyPowerSourcesInfo` → internal battery (`Current Capacity`, `Max Capacity`, `Is Charging`, `Power Source State`, `Time to Empty`, `Time to Full Charge`) |
| Low Power Mode | `ProcessInfo.isLowPowerModeEnabled` |
| Temperature | IORegistry `AppleSmartBattery` → `Temperature` (hundredths of °C) |

## Settings

| Key (`am.abhi.leanbattery`) | Default | Meaning |
|---|---|---|
| `tempThresholdC` | 40 | Hot badge threshold in °C (set in the popover's Settings) |

## Build & run

```sh
make app                # release build → LeanBattery.app, ad-hoc signed
open LeanBattery.app
make install            # copy to /Applications
swift test --filter IconRendererTests   # run one test suite
```

## CPU footprint

`scripts/cpu-check.sh [samples]` samples the running app once per second.

Measured: `samples=570 mean_cpu=0.00% idle_wakeups_per_min=0.0 memory=11M` (2026-09-15, popover not yet implemented). Later ten-minute runs on the finished app read 0.06-0.08% (see `docs/popover.md`); the 60 s temperature timer is cheap enough that whether it shows up at all depends on how its wakeups coalesce, so treat <0.1% as the honest figure rather than zero.
