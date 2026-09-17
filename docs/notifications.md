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
| Default | The standard floating capsule |
| Large | The same capsule at 1.2× |
| Notch | Flush against the screen's top edge, opaque black, square top corners and rounded bottom ones, so on a MacBook it reads as a body grown out of the display's notch |

Notch is drawn on every display, not just notched ones. On the built-in screen it continues the real notch (its reveal starts at the notch's true width, read from the screen's auxiliary top areas); on an external display it starts from a 180 pt stub and reads as a floating black island. Instead of sliding down, it reveals outward and downward over 0.28 s and collapses back in 0.22 s.

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

A below-rule pill — the only event that is genuinely bad news — carries a red border tint (`#FF453A` at 55 %) instead of the usual white 14 %, matching the glow's colour. Every other event keeps the neutral border. Nothing else about the pill changes: same material, same shadow, same text.

The pill's size and placement follow the **Style** setting above. In the three floating styles it appears centered, 8 pt below the menubar/notch band, on whichever screen the pointer is on (falling back to the main screen). It floats above fullscreen apps and follows you across Spaces. It slides down and fades in over a quarter second, stays for the duration set in the settings page, then slides up and fades out the same way. The Notch style instead sits flush to the top edge and reveals out of the notch, as described above. If a new event fires while a pill is already showing, its content and size update in place — no stacking, and the entrance animation doesn't replay. **Clicking the pill dismisses it and its glow immediately** and cancels the remaining dwell time. Changing display configuration (e.g. unplugging a monitor) also closes both instantly, without the exit animation.

## The glow

A screen-edge glow accompanies the pill only for below rules with their **Glow** chip on, plus the Preview button. Above rules and power-change alerts never show it. It fills the same screen as the pill: a thin alert-red border with an inward bloom, pulsing between about 45% and full opacity, each half-cycle taking 0.8 s, reversing continuously while it's up. The window is click-through — clicks pass straight to whatever is underneath — and the pulse is a Core Animation layer running on the window server, so it costs no per-frame work in the app itself once the window is up. It fades out over 0.4 s when the pill is dismissed by click or by timing out; a display-configuration change closes it immediately, without the fade.

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

Pill-and-glow CPU has not been measured yet. Once a build is available with Accessibility access to drive Preview and hold a notification on screen, it needs to clear two bars, matching `docs/popover.md`'s method:

- **Mean CPU under 2%** while a notification (pill, or pill + glow) is visible on screen.
- **Idle wakeups back to the popover-closed baseline** once the notification is gone — no elevated wakeups or CPU left running after dismissal.

_Measurements to be filled in here once taken._
