# Notifications

All notifications are optional and off by default except the one starter rule. Nothing here runs between events: there is no polling, no timer ticking in the background. A pill or a glow window is created only when a rule fires or you press Preview, and it is released again as soon as it's dismissed.

## Settings subpage

Opened from **Settings → Notifications ›**; replaces the popover content until you press **‹ Settings** or close the popover.

### Battery rules

Up to 5 rules, with an `n / 5` counter. Each row has: an enable switch, a direction picker (**Below** / **Above (charging)**), a `%` threshold with a stepper (range 1–99), a **Glow** chip (below rules only), a **Sound** chip, and a delete button. **＋ Add rule** is disabled once 5 rules exist.

A fresh install starts with one rule: **Below 20%**, Glow on, Sound on. **＋ Add rule** inserts **Below 20%**, Glow off, Sound off.

### Power-change alerts

One switch — "Connected / disconnected" — plus a **Sound** chip, disabled while the switch is off.

### Duration

A 2–10 s slider (whole seconds) controlling how long every pill (and its glow, if any) stays on screen.

### Style

Four choices for how the pill is drawn:

| Style | What it looks like |
|---|---|
| Small | The default capsule at 0.85× — text, icon, padding and width all scale together |

Title and detail are centred, with the icon and text set in from the body's edges. The battery glyph is rendered at 11 × 22 pt, so that is the largest it is ever drawn: Small shrinks it, and Large grows the text and the box but leaves the glyph at native size rather than upscaling a bitmap.

| Default | The standard floating capsule |
| Large | The same capsule at 1.2× |
| Notch | Starts at the screen's top edge and extends below the notch, opaque black with rounded bottom corners, so the black either side of the cutout makes the notch itself appear to have grown |

Notch is drawn on every display, not just notched ones.

The body starts at the very top of the screen. The notch itself is a physical cutout with no pixels behind it, so the text and icon sit in the band *below* it, while the black drawn either side of the cutout is what makes the two read as one shape. Its width is the notch's own width plus 40 pt, growing to another 140 pt before the text truncates — wide enough to read, narrow enough to still look like the notch.

On the built-in screen the notch's true width and height come from the screen's auxiliary top areas and safe-area inset, and the reveal grows out of exactly that footprint. A display without a notch has a zero inset, so nothing is drawn above the content band and the body simply sits flush at the top, revealing from a 180 pt stub. Instead of sliding down, it grows out of the cutout in both directions at once and shrinks back into it. The window is placed at full size and never moves; a mask the shape of the body expands from the notch's own footprint under a spring, so the contents never re-lay-out mid-animation and the growth reads as the notch itself stretching.

### Preview

**Preview notification** shows the pill and glow for a sample low-battery event (10%, "about 38m left", glow on, sound off), regardless of your actual battery level or rules. Pressing it again while a pill is showing replaces the pill in place rather than stacking a second one.

## Firing semantics

Each enabled rule is either armed or not; only an armed rule can fire, and firing disarms it. A rule is evaluated fresh on every battery state change — there is no separate polling loop.

- **Below** rules fire when the Mac is on battery power and the charge is at or under the threshold.
- **Above** rules fire when the Mac is on adapter power and the charge is at or over the threshold.

A rule (re-)arms when you create it, edit anything that affects its condition (enabled, direction, or threshold), or re-enable it — using the battery level at that moment, not the next reading. After that:

- A **below** rule re-arms as soon as the adapter is connected, or once the charge climbs back at least 2 points above the threshold.
- An **above** rule re-arms only once the charge drops at least 2 points below the threshold.

Two consequences fall out of this directly:

- **Unplugging while already at or under a Below threshold does fire.** A below rule is armed the whole time the adapter is connected, so the moment you unplug at or under the threshold, it fires immediately — you don't have to watch the level fall any further.
- **Plugging in while already at or over an Above threshold does not fire.** An above rule only arms once the charge has dropped at least 2 points under the threshold. If you plug in already at or above it without ever having dropped below `threshold − 2`, the rule was never armed, so nothing happens.

If several rules cross their threshold on the same battery reading, only one pill shows: a firing **below** rule always beats a firing **above** rule, and among several firing rules of the same direction, the most extreme one wins — the lowest threshold for below, the highest for above. A power-change alert only appears when no battery rule fired on that reading.

## The pill

One capsule with the current battery icon, a title, and a detail line:

| Event | Title | Detail |
|---|---|---|
| Below rule fires | `Low Battery` | `<percent>% · about <time> left`, or just `<percent>%` if the time remaining isn't known yet |
| Above rule fires | `Charged to <threshold>%` | `Power Adapter · <watts> W`, or `Plugged In` if the wattage isn't known |
| Adapter connected, charging | `Charging · <percent>%` | `Power Adapter · <watts> W` (or `Power Adapter` if unknown), plus ` · <time> to full` if known |
| Adapter connected, not charging | `Plugged In · Not Charging` | `<percent>%` |
| Adapter disconnected | `On Battery · <percent>%` | `About <time> left`, or `Calculating time left…` |

Time is written as `38m` under an hour, otherwise `4h 05m`.

A below-rule pill — the only event that is genuinely bad news — carries a red border tint (`#FF453A` at 55 %) instead of the usual white 14 %, matching the glow's colour. Every other event keeps the neutral border, as does the Notch style at all times: a coloured outline there breaks the illusion that the body is part of the bezel. Nothing else about the pill changes: same material, same shadow, same text.

The pill's size and placement follow the **Style** setting above. In the three floating styles it appears centered, 8 pt below the menubar/notch band, on whichever screen the pointer is on (falling back to the main screen). It floats above fullscreen apps and follows you across Spaces. It slides down and fades in over a quarter second, stays for the duration set in the settings page, then slides up and fades out the same way. The Notch style instead sits flush to the top edge and reveals out of the notch, as described above. If a new event fires while a pill is already showing, its content and size update in place — no stacking, and the entrance animation doesn't replay. **Clicking the pill dismisses it and its glow immediately** and cancels the remaining dwell time. Changing display configuration (e.g. unplugging a monitor) also closes both instantly, without the exit animation.

## The glow

A screen-edge glow accompanies the pill only for below rules with their **Glow** chip on, plus the Preview button. Above rules and power-change alerts never show it. It fills the same screen as the pill: a thin alert-red border with an inward bloom, pulsing between about 45% and full opacity, each half-cycle taking 0.8 s, reversing continuously while it's up. The window is click-through — clicks pass straight to whatever is underneath — and the pulse is a Core Animation layer running on the window server, so it costs no per-frame work in the app itself once the window is up. It fades out over 0.4 s when the pill is dismissed by click or by timing out; a display-configuration change closes it immediately, without the fade.

The pill is always drawn above the glow. The glow's border would otherwise cross the pill's top edge, which in the Notch style gives away that the two are separate windows.

## The sound

When a firing rule (or the power-change alert) has its **Sound** chip on, the system alert sound plays once via `NSSound.beep()` when the pill appears.

## Storage

Four UserDefaults keys, all under the app's domain:

| Key | Holds | Default |
|---|---|---|
| `notificationRules` | JSON-encoded array of rules, capped at 5 | One `Below 20%` rule, Glow on, Sound on |
| `powerChangeAlerts` | Bool | Off |
| `powerChangeSound` | Bool | Off |
| `notificationDuration` | Int, seconds | 4 |
| `pillStyle` | String: `small`, `medium`, `large` or `notch` | `medium` |

An unrecognised `pillStyle` (or none at all) reads back as `medium`. If the stored rules can't be decoded (missing, corrupt, or otherwise unreadable JSON), the list falls back to that same single `Below 20%` default rather than starting empty. An intentionally empty list (every rule deleted) is stored and read back as empty — it's only undecodable data that falls back to the default.

## CPU behavior

Nothing runs between notifications: no timer, no polling, no window. A notification costs one non-repeating dismissal timer while it is on screen, and the glow's pulse is a `CABasicAnimation` the window server renders, so the app does no per-frame work for it.

Measured 2026-09-17 on the development Mac with `scripts/cpu-check.sh`, notch style, pill and glow both visible, under `caffeinate -di`:

| Case | Result | Bar |
|---|---|---|
| Notification visible, popover closed | `mean_cpu=0.01% idle_wakeups_per_min=0.0 memory=44M` | mean < 2% — **passes** |
| Nothing showing, popover closed | `mean_cpu=0.00% idle_wakeups_per_min=0.0` | back to the cold-idle baseline — **passes** |

A visible notification costs the app essentially nothing, which is what the design intends: the dismissal timer is one-shot and does not fire inside the sample, the content never changes so nothing redraws, and the glow's pulse belongs to the window server. A *pending* timer does not wake the process, hence zero idle wakeups. The pill was confirmed still on screen when the sampler finished — without that check the figure is indistinguishable from the app sitting idle with no notification at all.

**Hold sleep off for the whole run.** An earlier attempt let the display sleep and was woken with a fingerprint unlock mid-sample, and read `0.63%` — the redraw on wake plus the `NSWorkspace.didWakeNotification` → `BatteryMonitor.refresh` it triggers are real work, and they landed inside the window. A sample that needs two untouched minutes is exactly long enough for the display to sleep, so:

```
(sleep 25; caffeinate -di scripts/cpu-check.sh 120)
```

To hold a notification up long enough to sample, write a duration past the slider's range while the app is quit — it is read from UserDefaults at launch and never clamped — then launch, press **Preview notification**, close the popover, and leave the machine alone:

```
defaults write am.abhi.leanbattery notificationDuration -int 150
```

Delete the key again afterwards, or the next launch keeps the inflated duration.

### Reveal animation under stress

A separate run clicked **Preview** roughly every 3 s for a minute — about 20 full reveal-and-collapse cycles of the notch style, with the settings popover open the whole time to reach the button: `mean_cpu=2.87% idle_wakeups_per_min=6.0`. Subtracting the popover's own measured 0.81% on the `Now` range leaves roughly 2% for twenty animations in sixty seconds.

That is far past any real usage — a threshold rule fires a handful of times a day, not twenty times a minute — and it is not the figure the acceptance bar refers to. It is recorded because it is the cost of the reveal itself, and because a future change to the animation should be compared against it.

### A note on where the cost lands

`scripts/cpu-check.sh` samples the `LeanBattery` process only. The glow's pulse and the notch style's mask are composited by **WindowServer**, so some of their real cost sits in a process these numbers do not include. The spec's bar is mean *app* CPU, so the results above are valid against it, but they are not the whole system cost of showing a notification.

### Memory

Both runs above report ~44M, against the 14M cold idle in `docs/popover.md`. That is popover residue rather than the notification's own cost, and it is unavoidable in this measurement: reaching **Preview notification** means opening the popover, and working memory is released a couple of minutes after it closes, not immediately. The closed-popover memory bar (spec §10, under 30M) is the one already measured at 14M in `docs/popover.md` on a session that never opened the popover; nothing here displaces it.
