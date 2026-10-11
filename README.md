# Curbside

**Drive well. Get rewarded.**

Nobody tells new drivers how they actually drive. Curbside does.

Your phone's sensors score every drive, pin each hard brake and sharp turn on a map, and replay the five seconds before it. Smooth drives build a Curbside Score. Families can see it, compete on it and reward it.

Drive. Get scored. Do better next time.

![platform](https://img.shields.io/badge/platform-iOS%2017%2B-black)
![app](https://img.shields.io/badge/app-Swift%206%20%2B%20SwiftUI-FFC400)
![backend](https://img.shields.io/badge/backend-Firebase-black)
![site](https://img.shields.io/badge/site-React%20%2B%20Vite-FFC400)

[Problem](#the-problem) · [What it does](#what-it-does) · [Demo](#demo) · [How it works](#how-it-works) · [Tech stack](#tech-stack) · [Privacy](#privacy) · [Run it](#run-it) · [Roadmap](#status-and-roadmap) · [Team](#team)

---

## The problem

Learning to drive ends with a short test. After that, nobody is in the passenger seat.

The CDC reports about 2,800 U.S. teens aged 13 to 19 were killed in car crashes in 2020, and about 227,000 were injured. Per mile driven, drivers aged 16 to 19 have a fatal crash rate almost three times as high as drivers 20 and older ([CDC](https://www.cdc.gov/teen-drivers/), citing IIHS).

The habits behind that risk are small and easy to miss: braking late and hard, launching off a green light, taking a turn too fast. You can't remember where you did them. A parent who wasn't in the car can't see them at all.

Today's tools cover only part of this. Location apps tell a parent where a teen is, not how they drove. Insurance programs score a driver, but the reward comes at renewal, on the parent's bill. Navigation apps get you there and say nothing about how.

The feedback is missing, and so is a reason to care about it.

## What it does

Curbside turns a drive into feedback you can use.

Tap Start Drive, or just drive. The screen shows your speed and an End drive button, and nothing else.

When the drive ends, you get a **score out of 100**, a **map** with every hard brake, fast start and sharp turn pinned by severity, and the **one habit** that cost you the most points.

> *"You drove a little rough."* Useful, but vague.
>
> *"Hard brake at 2 minutes in. Here are the 5 seconds before it."* Now you can see what to change.

Tap any event and Curbside replays those five seconds: a car marker moving along your route, live speed, and a brake-force bar.

Every drive feeds your **Curbside Score**, a long-term number from 0 to 100 that moves like a credit score. It doesn't grade you daily. Missing a week changes nothing. Steady, smooth driving lifts it, one bad drive dents it a little, and a pattern of bad drives pulls it down.

| Tier | Score |
|---|---|
| Bronze | 0 to 59 |
| Silver | 60 to 79 |
| Gold | 80 to 89 |
| Platinum | 90 to 100 |

Families join with an invite code. Parents get a dashboard and a leaderboard that includes the parents, because they drive too. Parents set goals ("hold 80+ for four weeks") and prizes. Higher tiers unlock partner offers.

There is no live ranking and no popup while you drive. Curbside is quiet until you stop.

## Demo

| Presentation site | Demo video | Screenshots |
|---|---|---|
| `site/`, run locally (not deployed yet) | [`design/curbside-demo-video.html`](design/curbside-demo-video.html), a 2:30 animated walkthrough | Design references in [`design/`](design/) |

The app includes hard-coded demo drives and a demo family, so you can see every screen without going for a drive. See [`Curbside/Drives/DemoDrives.swift`](Curbside/Drives/DemoDrives.swift).

## How it works

Four systems sit under one tap.

### 1. Record

Core Motion streams gravity-free acceleration at 50 Hz. Core Location streams GPS speed, heading and position. Raw samples are saved as a JSON log on the phone, along with a 1 Hz route.

### 2. Detect

A phone in a cupholder doesn't know which way the car faces, shakes over bumps, and gets picked up at red lights. The detector handles each:

- **Forward axis:** learned by matching motion to GPS speed changes. It relearns if the phone tilts more than 20° or spins in its mount.
- **GPS must agree:** a hard brake or fast start counts only if GPS shows the car's speed really changed. A turn needs both the gyroscope and a GPS heading change.
- **Phone handling is ignored:** fast pitch or roll means the phone moved, not the car.
- **Three severities:** moderate, hard and severe, by peak force. A hard brake starts at 0.28 g and a severe one at 0.50 g.
- **Every rejection has a reason:** too short, phone moved, no GPS, too slow, or speed not confirmed.

### 3. Score

- **Drive score (0 to 100):** each event costs points by type (hard brake 8, sharp turn 6, fast start 5), multiplied by severity (1×, 1.5×, 2.5×) and scaled by distance, so one hard brake on a 20-mile drive costs less than on a 1-mile drive.
- **Curbside Score (0 to 100):** a recency-weighted average of drive scores. Each older drive counts 0.95× the next newer one. Decay is by drive count, never by calendar time, and longer drives count more (up to 2×). The average maps to the score through tunable anchors that set how hard each tier is to reach.

The score is never stored. It is a pure function of your scored drives, so changing the formula re-scores your whole history.

### 4. Share (only if you agree)

A teen has to consent before anything leaves the phone, and the consent screen lists exactly what parents can see. Privacy is enforced in Firestore security rules, not only in the app. See [Privacy](#privacy).

## Tech stack

All detection and scoring logic lives in a pure Swift package. The app feeds it sensor samples and displays what comes back.

| Layer | Technology | Role |
|---|---|---|
| App | Swift 6, SwiftUI, `@Observable` | Native iOS interface |
| Local storage | SwiftData + JSON logs | Drive summaries, events, 1 Hz routes, raw sensor logs |
| Sensors | Core Motion, Core Location | Acceleration, rotation, GPS speed and heading |
| Maps and charts | MapKit, Swift Charts | Event maps, replay, speed charts, score history |
| Core logic | `CurbsideCore` (local Swift package) | Detection, scoring, replay, family and rewards logic. No UIKit, SwiftUI or Core Location. |
| Accounts | Sign in with Apple, Firebase Auth | Parent and teen accounts |
| Family sync | Cloud Firestore + security rules | Leaderboard, parent dashboard, reward progress |
| Tuning | `replay` command-line tool | Runs an exported real drive through the same detection and scoring code the app uses |
| Project | XcodeGen, Swift Testing | Generated Xcode project, unit tests |
| Presentation site | React, TypeScript, Vite | Project website and an illustrative scoring demo |

### Architecture at a glance

```
iPhone sensors ──► Core Motion (50 Hz) + Core Location (GPS)
                          │
                          ▼
                 CurbsideCore (pure Swift)
                 ├─ Detection   EventDetector · AxisEstimator · GPSTrack
                 ├─ Scoring     DriveScore · CurbsideScore
                 ├─ Replay      EventClip (the 5 s before each event)
                 ├─ Family      shared data · leaderboard · consent disclosure
                 └─ Rewards     parent goals · partner catalog · celebrations
                          │
        ┌─────────────────┼──────────────────────┐
        ▼                 ▼                      ▼
   SwiftUI app      SwiftData + raw        Firebase Auth + Firestore
   (MapKit,         JSON logs              (family data only, only
   Swift Charts)    on the phone           with consent)
```

The phone does the recording, detection and scoring. Firebase only carries what a family has agreed to share. Curbside works without it: with no `GoogleService-Info.plist`, the app builds and Family runs in demo mode.

Every threshold and weight lives in [`CurbsideConfig.swift`](CurbsideCore/Sources/CurbsideCore/CurbsideConfig.swift). The tuning loop is: record a drive, export its JSON, replay it, change a value, replay again.

### Project structure

```
Curbside/             iOS app (SwiftUI)
  App/ Recording/ Drives/ Score/ Family/ Rewards/ Support/
CurbsideCore/         Swift package: detection, scoring, replay, family, rewards, tests
  Sources/replay/     the `replay` CLI
firebase/             Firestore rules and emulator tests
site/                 React + Vite presentation site
design/               UI reference screenshots and the demo video
project.yml           XcodeGen spec (source of truth for the Xcode project)
CLAUDE.md             product rules, architecture notes and build phases
```

## Privacy

Teens decide what leaves their phone, and the rules are enforced on the server.

- **Consent first.** Nothing about a member is stored unless they are sharing. The consent screen lists every shared field, and a test fails if the shared data gains a field the screen doesn't list.
- **Only drives after consent.** Drives recorded before a teen agrees are never uploaded.
- **Drives are private to the owner and the family's parents.** Teens see the leaderboard and each member's score, never another member's drives.
- **Raw data stays on the phone.** Raw sensor logs, speeds, g-forces and event replays are never uploaded.
- **Turning sharing off deletes what was shared.** Parents see "Sharing paused."
- **Nothing during a drive.** Uploads happen silently after a drive is saved, and every alert and prompt waits until the drive ends.

Today, a shared drive includes a simplified route with each event pinned, so a parent can review a finished drive on a map. Moving to score-and-tier-only sharing is on the roadmap below.

## Run it

You need a recent Xcode with Swift 6, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and an iPhone for real drives. The Simulator has no motion sensors.

```sh
git clone https://github.com/sa087613/Curbside.git
cd Curbside
xcodegen generate                 # creates Curbside.xcodeproj
open Curbside.xcodeproj           # set your signing team, then run on a device
```

To use real accounts, add your own `Curbside/GoogleService-Info.plist` (it is gitignored). Without it, use **Preview with a demo family**.

```sh
# Core unit tests (fast, no simulator)
cd CurbsideCore && swift test

# Replay an exported real drive through the real detector and scorer
swift run replay drive.json --verbose [--csv signal.csv] [--config cfg.json]
swift run replay --dump-config > cfg.json

# Firestore security rules (emulator)
cd firebase && npm install && npm test

# Presentation site
cd site && npm install && npm run dev
```

Exported drive logs are saved in the app's `Documents/Drives` folder, which shows up in the Files app.

## Status and roadmap

**Built**
- Drive recording, event detection (hard brake, fast start, sharp turn), JSON export and the replay tool
- Per-drive score, post-drive summary with event map, coaching tip and speed chart
- 5-second event replay
- Curbside Score on a 0 to 100 scale with four tiers, trends and history
- Sign in with Apple, families, teen consent, parent dashboard, leaderboard
- Parent reward goals and a mock partner catalog (fictional partners, marked as samples)
- New design system and floating tab bar

**In progress** (see `design/` for the target screens)
- New Home and Drive Complete screens
- Driving screen with automatic drive start from Core Motion activity detection
- New Rewards and Family screens
- Privacy screen, and sharing only score, tier and event counts, with no routes

**Planned**
- Validate detection on real drives against a reference measurement, reporting false positives separately from detection rate so that rejecting everything can't score as perfect
- Speed-limit matching
- Telling driver from passenger
- Real partner offers in place of the sample catalog
- Parents on Android or web

## Team

[@sa087613](https://github.com/sa087613)

## License

No license file yet.
