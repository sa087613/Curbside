# /brag plan: Curbside

## Inspect
- **What it is:** a native iOS driving coach for teen drivers. It scores every drive out of 100, pins every hard brake on a map, and builds a slow-moving Curbside Score that unlocks rewards.
- **Who it's for:** new drivers, and the parents who worry about them (and pay their insurance).
- **What sets it apart:** you're rewarded for good driving *now*, not at renewal on the parent's bill. There's a family leaderboard with parents on it too. The phone stays quiet during the drive, and only the score leaves the phone.
- **Most impressive claim:** "Nobody rewards you for driving well." (the project's own opener, from `design/curbside-demo-video.html`).
- **Visual hook:** the yellow route line and the dark-glass phone UI, with the Curbside Score gauge sweeping into Gold.
- **Real UI shown:** the phone screens from `design/` (the redesign target), reused from the demo's own markup: Home gauge, Driving, Drive Complete, Rewards, Family.
- **Tone:** `default`. Punchy, clean, a dark stage matching the app (#0D0D0F, accent #FFC400, coral #FF5A4E, DM Serif Display headlines like the demo deck).
- **Share caption:** "Curbside scores every drive out of 100 and turns smooth driving into rewards today, not at renewal."

## Honesty notes
- Names (Mom, Ava, Jordan, Dad), the partner offer ("10% off · illustrative") and the drive numbers are the design's sample data. No real brands or people.
- No "Hard brake" / "Sharp turn" popups during the drive. The project's safety rule forbids them, so the driving scene shows only the map, speed and End drive.
- Trip name uses the agreed time-based name ("Afternoon drive"), not a destination.

## Storyboard: 22.0 s, 1920×1080, 30 fps

| # | Time | Scene | On screen | Phone |
|---|---|---|---|---|
| 1 | 0.0–3.0 | Hook | "Nobody rewards you for **driving well**." A yellow route draws across the stage with a car arrow riding it. | none |
| 2 | 3.0–6.0 | Reveal | "Meet **Curbside**." / "Rewards teens for every smooth trip." | Slides in, right. Home: the gauge sweeps 56 → 84, Gold, "+6 this week" |
| 3 | 6.0–9.5 | Drive | 01 The drive: "Then just **drive**." / "It starts on its own. No alerts while you drive." | Left. Driving: road scrolls, MPH climbs, End drive |
| 4 | 9.5–13.5 | Score | 02 The score: "Every trip, scored and **explained**." / "A score out of 100, and the one habit to fix." | Right. Drive Complete: ring fills to 92, scrolls to the event map and coaching |
| 5 | 13.5–16.2 | Rewards | 03 Rewards: "Safe driving **pays** today." / "Higher tiers unlock bigger offers." | Left. Rewards: Gold chip, offer card with QR, locked Platinum filling |
| 6 | 16.2–19.2 | Family | 04 Family: "Parents are on the **board** too." / "Scores only. Routes never leave the phone." | Right. Family leaderboard rows slide in, Family goal 3 of 4 |
| 7 | 19.2–22.0 | Outro | "Curbside" / "Drive well. **Get rewarded.**" Hold. | Right. Home at 84 Gold |

Transitions: old text lifts out, then new text rises in (staggered, no crossfade of busy layouts). Phone screens dip through black. The phone glides between left and right on each cut.

## Sound
120 BPM in F major (F, C, Dm, B♭; one chord per bar). The hook has a soft pad and pluck only. Kick, shaker and bass enter on the reveal at 3.0 s. The drums drop out at 19.0 s and the last F chord rings out. Effects are tuned to the key and sit under the music: soft airy swells into each cut, a bell on F/A/C when the score lands (5.0 s and 10.8 s), and a low thump for the outro.
